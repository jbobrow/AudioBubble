import MultipeerConnectivity
import Foundation
import Combine
import UIKit

class NetworkManager: NSObject, ObservableObject {
    // Published properties for UI
    @Published var connectedPeers: [MCPeerID] = []
    @Published var peerInfos: [MCPeerID: PeerInfo] = [:]
    @Published var availablePeers: [MCPeerID] = []
    @Published var isConnected = false
    @Published var connectionStatus = "Disconnected"

    // MultipeerConnectivity components
    private let serviceType = "audio-bubble"
    private var myPeerID: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser
    private var browser: MCNearbyServiceBrowser

    // Audio data callback - now includes peer ID
    var onAudioDataReceived: ((Data, MCPeerID) -> Void)?

    // Callback when peer connects/disconnects
    var onPeerConnected: ((MCPeerID) -> Void)?
    var onPeerDisconnected: ((MCPeerID) -> Void)?

    // Network stats
    @Published var bytesSent: Int = 0
    @Published var bytesReceived: Int = 0
    @Published var latencyMs: Double = 0

    // Per-peer latency tracking
    @Published var peerLatencies: [MCPeerID: Double] = [:]

    private var lastSentTimestamp: [MCPeerID: Date] = [:]

    override init() {
        // Create peer ID with device name
        let deviceName = UIDevice.current.name
        myPeerID = MCPeerID(displayName: deviceName)

        // Initialize session with no security (fastest for PoC)
        session = MCSession(peer: myPeerID,
                           securityIdentity: nil,
                           encryptionPreference: .none) // No encryption for lowest latency

        // Initialize advertiser and browser
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID,
                                               discoveryInfo: nil,
                                               serviceType: serviceType)

        browser = MCNearbyServiceBrowser(peer: myPeerID,
                                        serviceType: serviceType)

        super.init()

        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self

        print("Network Manager initialized as: \(deviceName)")
    }

    // MARK: - Peer Info Helpers

    /// Get or create PeerInfo for a peer
    func getPeerInfo(for peerID: MCPeerID) -> PeerInfo {
        if let existing = peerInfos[peerID] {
            return existing
        }

        let color = PeerColorManager.shared.colorForPeer(peerID)
        let peerInfo = PeerInfo(peerID: peerID, color: color)

        DispatchQueue.main.async {
            self.peerInfos[peerID] = peerInfo
        }

        return peerInfo
    }

    /// Get list of connected peer infos
    var connectedPeerInfos: [PeerInfo] {
        connectedPeers.compactMap { peerInfos[$0] }
    }

    // MARK: - Connection Management

    func startHosting() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        connectionStatus = "Looking for peers..."
        print("Started advertising and browsing")
    }

    func stopHosting() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()

        DispatchQueue.main.async {
            self.connectionStatus = "Disconnected"
            self.connectedPeers.removeAll()
            self.availablePeers.removeAll()
            self.peerInfos.removeAll()
            self.peerLatencies.removeAll()
            self.isConnected = false
            self.bytesSent = 0
            self.bytesReceived = 0
            self.latencyMs = 0
        }

        // Reset color manager for next session
        PeerColorManager.shared.reset()

        print("Stopped hosting")
    }

    // MARK: - Audio Transmission

    func sendAudioData(_ data: Data) {
        guard !connectedPeers.isEmpty else { return }

        // Add timestamp for latency measurement (first 8 bytes)
        var packetData = Data()
        let timestamp = Date().timeIntervalSince1970
        withUnsafeBytes(of: timestamp) { packetData.append(contentsOf: $0) }
        packetData.append(data)

        do {
            try session.send(packetData,
                           toPeers: connectedPeers,
                           with: .unreliable) // Unreliable = UDP-like, lowest latency

            let count = packetData.count
            DispatchQueue.main.async {
                self.bytesSent += count
            }

            // Track send time
            for peer in connectedPeers {
                lastSentTimestamp[peer] = Date()
            }

        } catch {
            print("Error sending audio: \(error)")
        }
    }

    private func processReceivedAudioData(_ data: Data, from peer: MCPeerID) {
        // Extract timestamp and calculate latency
        if data.count > 8 {
            let timestamp = data.withUnsafeBytes { $0.load(as: TimeInterval.self) }
            let now = Date().timeIntervalSince1970
            let latency = (now - timestamp) * 1000 // Convert to ms

            // Extract audio data (skip first 8 bytes)
            let audioData = data.subdata(in: 8..<data.count)
            let dataCount = audioData.count

            DispatchQueue.main.async {
                // Update per-peer latency
                let prevLatency = self.peerLatencies[peer] ?? latency
                self.peerLatencies[peer] = prevLatency * 0.8 + latency * 0.2

                // Use average latency across all peers for global display
                if !self.peerLatencies.isEmpty {
                    let avgLatency = self.peerLatencies.values.reduce(0, +) / Double(self.peerLatencies.count)
                    self.latencyMs = avgLatency
                }

                self.bytesReceived += dataCount
            }

            onAudioDataReceived?(audioData, peer)
        }
    }

    // MARK: - Connection Status Helpers

    private func updateConnectionStatus() {
        DispatchQueue.main.async {
            let count = self.connectedPeers.count
            if count == 0 {
                self.connectionStatus = "Looking for peers..."
            } else if count == 1 {
                self.connectionStatus = "Connected to \(self.connectedPeers[0].displayName)"
            } else {
                self.connectionStatus = "Connected to \(count) people"
            }
        }
    }
}

// MARK: - MCSessionDelegate

extension NetworkManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                print("Connected to: \(peerID.displayName)")
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                    // Create PeerInfo for this peer
                    _ = self.getPeerInfo(for: peerID)
                }
                self.isConnected = true
                self.updateConnectionStatus()
                self.onPeerConnected?(peerID)

            case .connecting:
                print("Connecting to: \(peerID.displayName)")

            case .notConnected:
                print("Disconnected from: \(peerID.displayName)")
                self.connectedPeers.removeAll { $0 == peerID }
                self.peerInfos.removeValue(forKey: peerID)
                self.peerLatencies.removeValue(forKey: peerID)
                self.isConnected = !self.connectedPeers.isEmpty
                self.updateConnectionStatus()
                self.onPeerDisconnected?(peerID)

            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Process received audio data
        processReceivedAudioData(data, from: peerID)
    }

    // Required but unused delegate methods
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension NetworkManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                   didReceiveInvitationFromPeer peerID: MCPeerID,
                   withContext context: Data?,
                   invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("Received invitation from: \(peerID.displayName)")
        // Auto-accept invitations for PoC
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Failed to advertise: \(error)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension NetworkManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("Found peer: \(peerID.displayName)")

        DispatchQueue.main.async {
            if !self.availablePeers.contains(peerID) {
                self.availablePeers.append(peerID)
            }
        }

        // Auto-invite found peers for PoC
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
        print("Invited peer: \(peerID.displayName)")
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("Lost peer: \(peerID.displayName)")

        DispatchQueue.main.async {
            self.availablePeers.removeAll { $0 == peerID }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("Failed to browse: \(error)")
    }
}
