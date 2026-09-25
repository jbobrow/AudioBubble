import Foundation
import Network
import Synchronization
import os

/// Finds nearby Audio Bubble devices and exchanges UDP datagrams with them, directly.
///
/// Peer-to-peer comes first: the listener, the browser and every connection set
/// `includePeerToPeer`, and connections go to the Bonjour *service endpoint* (never a resolved
/// address) so the system can route over AWDL when there is no shared Wi-Fi network. Packets are
/// marked `.interactiveVoice` (WMM AC_VO).
///
/// Each device advertises `_audio-bubble._udp` named with its peer id, and opens one outbound
/// connection to every other device it browses. It sends on its outbound connections and receives
/// on both those and the inbound flows the listener accepts. That keeps the mesh symmetric, with no
/// tie-breaking over who connects to whom.
///
/// Everything here runs on one serial queue, except `sendAudio`, which the sender thread calls.
nonisolated final class MeshTransport: @unchecked Sendable {
    static let serviceType = "_audio-bubble._udp"

    let localID: UInt64
    private let streams: StreamTable
    private let queue = DispatchQueue(label: "audio-bubble.network", qos: .userInteractive)
    private let log = Logger(subsystem: "com.jonbobrow.AudioBubble", category: "network")

    private var listener: NWListener?
    private var browser: NWBrowser?
    /// Outbound connection to each browsed peer. Network queue only.
    private var outbound: [UInt64: NWConnection] = [:]
    /// Inbound flows, keyed by the sender id seen on them. Network queue only.
    private var inbound: [UInt64: NWConnection] = [:]
    private var unidentifiedInbound: [ObjectIdentifier: NWConnection] = [:]
    private var browsed: Set<UInt64> = []
    private var audioMembers: Set<UInt64> = []

    /// Connections the sender thread sends audio on, rebuilt on the network queue.
    private let audioTargets = Mutex<[NWConnection]>([])

    /// Called on the main queue for every control message received.
    var onControl: (@MainActor (_ sender: UInt64, _ message: ControlMessage) -> Void)?
    /// Called on the main queue when the set of peers visible through Bonjour changes.
    var onDiscoveryChanged: (@MainActor (_ peers: Set<UInt64>) -> Void)?

    init(localID: UInt64, streams: StreamTable) {
        self.localID = localID
        self.streams = streams
    }

    static func parameters() -> NWParameters {
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = true
        parameters.serviceClass = .interactiveVoice
        parameters.prohibitedInterfaceTypes = [.cellular]
        return parameters
    }

    static func serviceName(for id: UInt64) -> String { String(format: "%016llx", id) }

    // MARK: Lifecycle

    func start() {
        queue.async { [self] in
            startListener()
            startBrowser()
        }
    }

    func stop() {
        queue.async { [self] in
            listener?.cancel()
            browser?.cancel()
            listener = nil
            browser = nil
            for connection in outbound.values { connection.cancel() }
            for connection in inbound.values { connection.cancel() }
            for connection in unidentifiedInbound.values { connection.cancel() }
            outbound = [:]
            inbound = [:]
            unidentifiedInbound = [:]
            browsed = []
            rebuildAudioTargets()
        }
    }

    private func startListener() {
        do {
            let listener = try NWListener(using: Self.parameters())
            listener.service = NWListener.Service(name: Self.serviceName(for: localID), type: Self.serviceType)
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case let .failed(error):
                    log.error("listener failed: \(String(describing: error)); restarting")
                    self.listener?.cancel()
                    self.listener = nil
                    queue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.startListener() }
                case .ready:
                    log.info("listening as \(Self.serviceName(for: self.localID))")
                default: break
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            log.error("listener could not be created: \(String(describing: error))")
        }
    }

    private func startBrowser() {
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: Self.parameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in self?.updateBrowseResults(results) }
        browser.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case let .failed(error) = state {
                log.error("browser failed: \(String(describing: error)); restarting")
                self.browser?.cancel()
                self.browser = nil
                queue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.startBrowser() }
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    // MARK: Discovery

    private func updateBrowseResults(_ results: Set<NWBrowser.Result>) {
        var endpoints: [UInt64: NWEndpoint] = [:]
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint,
                  let id = UInt64(name, radix: 16), id != localID else { continue }
            endpoints[id] = result.endpoint
        }
        let visible = Set(endpoints.keys)

        for id in browsed.subtracting(visible) {
            outbound.removeValue(forKey: id)?.cancel()
            inbound.removeValue(forKey: id)?.cancel()
        }
        for (id, endpoint) in endpoints where outbound[id] == nil {
            connect(to: id, endpoint: endpoint)
        }
        browsed = visible
        rebuildAudioTargets()
        let callback = onDiscoveryChanged
        DispatchQueue.main.async { callback?(visible) }
    }

    private func connect(to id: UInt64, endpoint: NWEndpoint) {
        let connection = NWConnection(to: endpoint, using: Self.parameters())
        outbound[id] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                rebuildAudioTargets()
            case let .failed(error):
                log.info("link to \(Self.serviceName(for: id)) failed: \(String(describing: error))")
                connection.cancel()
                if outbound[id] === connection {
                    outbound[id] = nil
                    rebuildAudioTargets()
                    // Try again while the peer is still advertised.
                    queue.asyncAfter(deadline: .now() + 1) { [weak self] in
                        guard let self, outbound[id] == nil, browsed.contains(id) else { return }
                        connect(to: id, endpoint: endpoint)
                    }
                }
            default: break
            }
        }
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func accept(_ connection: NWConnection) {
        unidentifiedInbound[ObjectIdentifier(connection)] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .failed, .cancelled:
                unidentifiedInbound[ObjectIdentifier(connection)] = nil
                if let id = inbound.first(where: { $0.value === connection })?.key { inbound[id] = nil }
                if case .failed = state { connection.cancel() }
            default: break
            }
        }
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self, weak connection] data, _, _, error in
            guard let self, let connection else { return }
            if let data, !data.isEmpty { handle(data, on: connection) }
            if error == nil, connection.state != .cancelled { receive(on: connection) }
        }
    }

    private func handle(_ data: Data, on connection: NWConnection) {
        data.withUnsafeBytes { bytes in
            guard let header = WireProtocol.parseHeader(bytes), header.sender != localID else { return }
            identify(connection, as: header.sender)
            switch header.kind {
            case .audio:
                guard let frame = WireProtocol.parseAudio(bytes, header: header) else { return }
                streams.receive(from: header.sender, sequence: frame.sequence, silent: header.silent, payload: frame.payload)
            case .control:
                guard let message = WireProtocol.decodeControl(data) else { return }
                let callback = onControl
                let sender = header.sender
                DispatchQueue.main.async { callback?(sender, message) }
            }
        }
    }

    /// Remembers which peer an inbound flow belongs to, replacing an older flow from that peer.
    private func identify(_ connection: NWConnection, as id: UInt64) {
        guard unidentifiedInbound.removeValue(forKey: ObjectIdentifier(connection)) != nil else { return }
        if let old = inbound[id], old !== connection { old.cancel() }
        inbound[id] = connection
    }

    // MARK: Sending

    /// Sends a control message to one peer (from any thread).
    func send(_ message: ControlMessage, to peer: UInt64) {
        guard let data = WireProtocol.encodeControl(message, sender: localID) else { return }
        queue.async { [self] in
            outbound[peer]?.send(content: data, completion: .idempotent)
        }
    }

    /// Sends a control message to every browsed peer (from any thread).
    func broadcast(_ message: ControlMessage) {
        guard let data = WireProtocol.encodeControl(message, sender: localID) else { return }
        queue.async { [self] in
            for connection in outbound.values { connection.send(content: data, completion: .idempotent) }
        }
    }

    /// The peers that should receive our audio: the other members of the bubble.
    func setAudioMembers(_ members: Set<UInt64>) {
        queue.async { [self] in
            audioMembers = members
            rebuildAudioTargets()
        }
    }

    private func rebuildAudioTargets() {
        let targets = audioMembers.compactMap { id -> NWConnection? in
            guard let connection = outbound[id], connection.state == .ready else { return nil }
            return connection
        }
        audioTargets.withLock { $0 = targets }
    }

    /// Sender thread. Sends one audio datagram to every bubble member.
    func sendAudio(_ packet: Data) {
        let targets = audioTargets.withLock { $0 }
        for connection in targets {
            connection.send(content: packet, completion: .idempotent)
        }
    }
}
