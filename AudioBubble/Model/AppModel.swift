import Foundation
import Observation
import os

/// App state: identity, the people nearby, the bubble you're in, and invites.
///
/// Membership is leaderless and eventually consistent. Every peer says hello about once a second
/// with its name, color and current bubble id; the bubble is simply everyone advertising the same
/// bubble id as you. Invites and replies are sent several times and de-duplicated by id. There is no
/// host to lose.
@Observable
@MainActor
final class AppModel {
    // MARK: Published state

    private(set) var identity: Identity?
    private(set) var peers: [UInt64: Peer] = [:]
    private(set) var bubbleID: UUID?
    private(set) var incomingInvite: IncomingInvite?
    private(set) var outgoingInvites: [UInt64: OutgoingInvite] = [:]
    private(set) var isMuted = false
    /// Peers visible through Bonjour (some may not have said hello yet).
    private(set) var discovered: Set<UInt64> = []
    /// When we started looking, for the empty state.
    let searchStarted = Date()
    private(set) var micModeName = AudioSessionController.micModeName
    /// Whether this phone is joined to a Wi-Fi network (slower, less reliable bubbles).
    private(set) var isOnWiFiNetwork = false
    /// The user dismissed the "disconnect from Wi-Fi" advice for this session.
    var wifiAdviceDismissed = false

    // MARK: Engine

    let localID = Identity.newPeerID()
    @ObservationIgnored private let streams = StreamTable()
    @ObservationIgnored private let engine: VoiceEngine
    @ObservationIgnored private let session: AudioSessionController
    @ObservationIgnored private let transport: MeshTransport
    @ObservationIgnored private let sender: AudioSender
    @ObservationIgnored private let wifiMonitor = WiFiMonitor()
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var seenMessageIDs: Set<UUID> = []
    @ObservationIgnored private var lastHadCompany = Date()
    @ObservationIgnored private var audioActive = false
    @ObservationIgnored private let log = Logger(subsystem: "com.jonbobrow.AudioBubble", category: "model")

    static let helloInterval: Duration = .seconds(1)
    static let resendDelays: [Duration] = [.zero, .milliseconds(250), .milliseconds(750), .milliseconds(1_500)]
    static let inviteLifetime: TimeInterval = 30
    static let aloneTimeout: TimeInterval = 15

    init() {
        identity = Identity.load()
        engine = VoiceEngine(streams: streams)
        session = AudioSessionController(engine: engine)
        transport = MeshTransport(localID: localID, streams: streams)
        sender = AudioSender(engine: engine, transport: transport)
        transport.onControl = { [weak self] sender, message in self?.handle(message, from: sender) }
        transport.onDiscoveryChanged = { [weak self] peers in self?.discovered = peers }
        transport.onLinkChanged = { [weak self] peer, interface in self?.peers[peer]?.linkInterface = interface }
        wifiMonitor.onChange = { [weak self] joined in
            guard let self, joined != isOnWiFiNetwork else { return }
            isOnWiFiNetwork = joined
            sendHellos()
        }
        if identity != nil { start() }
    }

    // MARK: Derived state

    private var now: UInt64 { MonotonicClock.nowMicros() }

    /// Present peers, sorted for a stable layout.
    var presentPeers: [Peer] {
        let now = now
        return peers.values.filter { $0.isPresent(now: now) }.sorted { $0.id < $1.id }
    }

    /// The other people in your bubble.
    var members: [Peer] {
        guard let bubbleID else { return [] }
        return presentPeers.filter { $0.bubble == bubbleID }
    }

    /// People nearby who aren't in your bubble.
    var nearby: [Peer] {
        presentPeers.filter { bubbleID == nil || $0.bubble != bubbleID }
    }

    func peer(_ id: UInt64) -> Peer? { peers[id] }

    /// Live voice level of a member (0...1). Read it from a TimelineView; it isn't observable.
    func level(of peer: UInt64) -> Float { streams.level(of: peer) }

    /// Your own mic level (0...1), zero when muted.
    var myLevel: Float { isMuted ? 0 : engine.micLevel }

    /// Estimated mouth-to-ear latency from a member to you, in milliseconds.
    func latencyMilliseconds(from peer: UInt64) -> Double? {
        latencyBreakdown(from: peer)?.total
    }

    /// Where the latency from a member comes from.
    func latencyBreakdown(from peer: UInt64) -> LatencyBreakdown? {
        guard let rtt = peers[peer]?.rttMilliseconds, let depth = streams.depthMilliseconds(of: peer) else { return nil }
        return LatencyBreakdown(network: rtt / 2, buffer: depth,
                                processing: AudioFormat.frameDuration * 1000 + AudioFormat.milliseconds(samples: SpectralTransform.hop),
                                hardware: session.hardwareLatencyMilliseconds)
    }

    /// Whether your own voice is being removed from a member's stream (their mic hears you).
    func isSuppressingEcho(from peer: UInt64) -> Bool { streams.isSuppressingEcho(from: peer) }

    /// Show the advice to leave the Wi-Fi network: in a bubble, joined to a network, not dismissed.
    var shouldAdviseLeavingWiFi: Bool {
        bubbleID != nil && isOnWiFiNetwork && !wifiAdviceDismissed
    }

    // MARK: Actions

    func completeOnboarding(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let identity = Identity(name: String(trimmed.prefix(24)), hue: .random(in: 0..<1))
        identity.save()
        self.identity = identity
        start()
    }

    func rename(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var identity else { return }
        identity.name = String(trimmed.prefix(24))
        identity.save()
        self.identity = identity
        sendHellos()
    }

    /// Invites someone into your bubble (or a new one, if you aren't in one yet).
    func invite(_ peer: UInt64) {
        guard outgoingInvites[peer] == nil else { return }
        let invite = OutgoingInvite(id: UUID(), bubble: bubbleID ?? UUID(), sent: Date())
        outgoingInvites[peer] = invite
        repeatSend(.invite(.init(id: invite.id, bubble: invite.bubble)), to: peer)
    }

    func acceptInvite() {
        guard let invite = incomingInvite else { return }
        incomingInvite = nil
        repeatSend(.reply(.init(id: invite.id, bubble: invite.bubble, accepted: true)), to: invite.from)
        join(invite.bubble)
    }

    func declineInvite() {
        guard let invite = incomingInvite else { return }
        incomingInvite = nil
        repeatSend(.reply(.init(id: invite.id, bubble: invite.bubble, accepted: false)), to: invite.from)
    }

    func leaveBubble() {
        bubbleID = nil
        outgoingInvites = [:]
        sendHellos()
        reconcile()
    }

    func toggleMute() {
        isMuted.toggle()
        sender.isMuted = isMuted
    }

    func showMicModes() {
        AudioSessionController.showMicModes()
    }

    // MARK: Lifecycle

    private func start() {
        AudioSessionController.requestMicrophonePermission()
        wifiMonitor.start()
        transport.start()
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: Self.helloInterval)
            }
        }
    }

    private func tick() {
        sendHellos()
        let date = Date()
        outgoingInvites = outgoingInvites.filter { date.timeIntervalSince($0.value.sent) < Self.inviteLifetime }
        if let invite = incomingInvite, date.timeIntervalSince(invite.received) > Self.inviteLifetime {
            incomingInvite = nil
        }
        micModeName = AudioSessionController.micModeName
        reconcile()
        #if DEBUG
        debugAutomation()
        #endif
    }

    #if DEBUG
    /// Launch with `-autoInvite` / `-autoAccept` to test two simulators or devices hands-free.
    private func debugAutomation() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-autoAccept"), incomingInvite != nil { acceptInvite() }
        if arguments.contains("-autoInvite"), bubbleID == nil, outgoingInvites.isEmpty, let first = nearby.first {
            invite(first.id)
        }
        for member in members {
            let depth = streams.depthMilliseconds(of: member.id) ?? -1
            let latency = latencyMilliseconds(from: member.id) ?? -1
            let rtt = member.rttMilliseconds ?? -1
            log.debug("member \(member.name) [\(member.linkInterface ?? "?")\(member.onWiFi ? ", on Wi-Fi" : "")\(self.isSuppressingEcho(from: member.id) ? ", echo suppressed" : "")]: rtt \(rtt, format: .fixed(precision: 1)) ms, buffer \(depth, format: .fixed(precision: 1)) ms, level \(self.level(of: member.id)), latency \(latency, format: .fixed(precision: 1)) ms, mic \(self.myLevel)")
        }
    }
    #endif

    private func join(_ bubble: UUID) {
        bubbleID = bubble
        lastHadCompany = Date()
        sendHellos()
        reconcile()
    }

    /// Makes audio match membership: who we play, who we send to, and whether audio runs at all.
    private func reconcile() {
        let memberIDs = Set(members.map(\.id))
        streams.setMembers(memberIDs)
        transport.setAudioMembers(memberIDs)

        if bubbleID != nil {
            if !memberIDs.isEmpty || !outgoingInvites.isEmpty {
                lastHadCompany = Date()
            } else if Date().timeIntervalSince(lastHadCompany) > Self.aloneTimeout {
                // Everyone else left.
                bubbleID = nil
                sendHellos()
            }
        }

        let shouldRun = bubbleID != nil && !memberIDs.isEmpty
        guard shouldRun != audioActive else { return }
        audioActive = shouldRun
        if shouldRun {
            session.setActive(true)
            sender.start()
        } else {
            sender.stop()
            session.setActive(false)
        }
    }

    // MARK: Messaging

    private func sendHellos() {
        guard let identity else { return }
        let now = now
        for id in discovered {
            let known = peers[id]
            let hello = ControlMessage.Hello(
                name: identity.name, hue: identity.hue, bubble: bubbleID, time: now,
                echoTime: known?.lastHelloTime,
                echoHold: known.map { now &- $0.lastSeen },
                onWiFi: isOnWiFiNetwork)
            transport.send(.hello(hello), to: id)
        }
    }

    private func repeatSend(_ message: ControlMessage, to peer: UInt64) {
        let transport = transport
        Task {
            for delay in Self.resendDelays {
                if delay > .zero { try? await Task.sleep(for: delay) }
                transport.send(message, to: peer)
            }
        }
    }

    private func handle(_ message: ControlMessage, from sender: UInt64) {
        switch message {
        case let .hello(hello):
            handleHello(hello, from: sender)
        case let .invite(invite):
            guard seenMessageIDs.insert(invite.id).inserted else { return }
            if invite.bubble == bubbleID {
                // Already together.
                repeatSend(.reply(.init(id: invite.id, bubble: invite.bubble, accepted: true)), to: sender)
            } else {
                incomingInvite = IncomingInvite(id: invite.id, from: sender, bubble: invite.bubble, received: Date())
            }
        case let .reply(reply):
            guard seenMessageIDs.insert(reply.id).inserted else { return }
            guard let pending = outgoingInvites[sender], pending.id == reply.id else { return }
            outgoingInvites[sender] = nil
            if reply.accepted && bubbleID == nil {
                join(reply.bubble)
            } else {
                reconcile()
            }
        }
    }

    private func handleHello(_ hello: ControlMessage.Hello, from sender: UInt64) {
        let now = now
        var peer = peers[sender] ?? Peer(id: sender, name: hello.name, hue: hello.hue, bubble: hello.bubble,
                                         lastSeen: now, lastHelloTime: hello.time, rttMilliseconds: nil)
        let wasPresent = peers[sender]?.isPresent(now: now) ?? false
        let bubbleChanged = peer.bubble != hello.bubble
        peer.name = hello.name
        peer.hue = hello.hue
        peer.bubble = hello.bubble
        peer.lastSeen = now
        peer.lastHelloTime = hello.time
        peer.onWiFi = hello.onWiFi ?? false

        if let echo = hello.echoTime, let hold = hello.echoHold, now > echo &+ hold {
            let rtt = Double(now - echo - hold) / 1000
            if rtt < 2_000 {
                peer.rttMilliseconds = peer.rttMilliseconds.map { $0 * 0.8 + rtt * 0.2 } ?? rtt
            }
        }
        if peers[sender] != peer { peers[sender] = peer }

        if !wasPresent {
            // Answer right away so they learn our bubble (and get an RTT sample) quickly.
            sendHellos()
        }
        if bubbleChanged || !wasPresent { reconcile() }
    }
}
