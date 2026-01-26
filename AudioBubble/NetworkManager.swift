import MultipeerConnectivity
import Foundation
import Combine
import UIKit

/// Manages peer-to-peer networking for audio bubble discovery and communication
final class NetworkManager: NSObject, ObservableObject {
    // MARK: - Published Properties

    /// Currently connected peers
    @Published var connectedPeers: [MCPeerID] = []

    /// Info about each connected peer
    @Published var peerInfos: [MCPeerID: PeerInfo] = [:]

    /// Discovered bubbles nearby
    @Published var discoveredBubbles: [BubbleInfo] = []

    /// Whether we're connected to a bubble
    @Published var isConnected = false

    /// Current connection status message
    @Published var connectionStatus = "Not connected"

    /// Network statistics
    @Published var bytesSent: Int = 0
    @Published var bytesReceived: Int = 0
    @Published var latencyMs: Double = 0
    @Published var peerLatencies: [MCPeerID: Double] = [:]

    // MARK: - Callbacks

    /// Called when audio data is received from a peer
    var onAudioDataReceived: ((Data, MCPeerID) -> Void)?

    /// Called when a peer connects
    var onPeerConnected: ((MCPeerID) -> Void)?

    /// Called when a peer disconnects
    var onPeerDisconnected: ((MCPeerID) -> Void)?

    // MARK: - Private Properties

    private let serviceType = "audio-bubble"
    private var myPeerID: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    /// Current bubble we're hosting or joined
    private var currentBubble: BubbleInfo?
    private var isHosting = false

    /// User profile reference
    private let userProfile: UserProfile

    // MARK: - Initialization

    init(userProfile: UserProfile = .shared) {
        self.userProfile = userProfile

        // Create peer ID with user's display name or device name
        let displayName = userProfile.displayName.isEmpty
            ? UIDevice.current.name
            : userProfile.displayName

        self.myPeerID = MCPeerID(displayName: displayName)

        super.init()

        print("NetworkManager initialized as: \(displayName)")
    }

    /// Update peer ID when user changes their name
    func updateDisplayName(_ name: String) {
        // Note: MCPeerID is immutable, but for a PoC we create a new one
        // In production, you'd need to handle session recreation
        let newName = name.isEmpty ? UIDevice.current.name : name
        myPeerID = MCPeerID(displayName: newName)
    }

    // MARK: - Session Management

    private func createSession() {
        session = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            encryptionPreference: .none  // No encryption for lowest latency (PoC)
        )
        session?.delegate = self
    }

    private func destroySession() {
        session?.disconnect()
        session?.delegate = nil
        session = nil
    }

    // MARK: - Bubble Discovery (Browser Mode)

    /// Start browsing for nearby bubbles
    func startBrowsing() {
        stopAll()

        createSession()

        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()

        connectionStatus = "Looking for bubbles..."
        print("Started browsing for bubbles")
    }

    /// Stop browsing
    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
    }

    // MARK: - Bubble Hosting (Advertiser Mode)

    /// Create and host a new bubble
    func createBubble(name: String) {
        stopAll()

        let hostName = userProfile.displayName.isEmpty
            ? UIDevice.current.name
            : userProfile.displayName

        let bubble = BubbleInfo(name: name, hostPeerID: myPeerID, hostName: hostName)
        currentBubble = bubble
        isHosting = true

        createSession()

        // Advertise with bubble info
        let discoveryInfo = bubble.toDiscoveryInfo(participantCount: 1)
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: discoveryInfo,
            serviceType: serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()

        // Also browse for others who might want to join
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()

        connectionStatus = "Hosting '\(name)'..."
        print("Created bubble: \(name)")
    }

    /// Update advertised participant count
    private func updateAdvertisedParticipantCount() {
        guard isHosting, let bubble = currentBubble else { return }

        // Stop and restart advertiser with updated count
        advertiser?.stopAdvertisingPeer()

        let count = connectedPeers.count + 1  // +1 for self
        let discoveryInfo = bubble.toDiscoveryInfo(participantCount: count)

        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: discoveryInfo,
            serviceType: serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
    }

    // MARK: - Joining a Bubble

    /// Join a discovered bubble
    func joinBubble(_ bubble: BubbleInfo) {
        stopAll()

        currentBubble = bubble
        isHosting = false

        createSession()

        // Start browsing to find the host
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()

        connectionStatus = "Joining '\(bubble.name)'..."
        print("Joining bubble: \(bubble.name)")
    }

    // MARK: - Leaving

    /// Stop all networking and leave current bubble
    func stopAll() {
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil

        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil

        destroySession()

        DispatchQueue.main.async {
            self.connectionStatus = "Not connected"
            self.connectedPeers.removeAll()
            self.peerInfos.removeAll()
            self.discoveredBubbles.removeAll()
            self.peerLatencies.removeAll()
            self.isConnected = false
            self.bytesSent = 0
            self.bytesReceived = 0
            self.latencyMs = 0
        }

        currentBubble = nil
        isHosting = false

        PeerColorManager.shared.reset()

        print("Stopped all networking")
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

    // MARK: - Audio Transmission

    /// Send audio data to all connected peers
    func sendAudioData(_ data: Data) {
        guard let session = session, !connectedPeers.isEmpty else { return }

        // Add timestamp for latency measurement (first 8 bytes)
        var packetData = Data()
        let timestamp = Date().timeIntervalSince1970
        withUnsafeBytes(of: timestamp) { packetData.append(contentsOf: $0) }
        packetData.append(data)

        do {
            try session.send(
                packetData,
                toPeers: connectedPeers,
                with: .unreliable  // UDP-like for lowest latency
            )

            let count = packetData.count
            DispatchQueue.main.async {
                self.bytesSent += count
            }

        } catch {
            print("Error sending audio: \(error)")
        }
    }

    /// Process received audio data
    private func processReceivedAudioData(_ data: Data, from peer: MCPeerID) {
        guard data.count > 8 else { return }

        // Extract timestamp and calculate latency
        let timestamp = data.withUnsafeBytes { $0.load(as: TimeInterval.self) }
        let now = Date().timeIntervalSince1970
        let latency = (now - timestamp) * 1000  // Convert to ms

        // Extract audio data (skip first 8 bytes)
        let audioData = data.subdata(in: 8..<data.count)
        let dataCount = audioData.count

        DispatchQueue.main.async {
            // Update per-peer latency with smoothing
            let prevLatency = self.peerLatencies[peer] ?? latency
            self.peerLatencies[peer] = prevLatency * 0.8 + latency * 0.2

            // Calculate average latency across all peers
            if !self.peerLatencies.isEmpty {
                let avgLatency = self.peerLatencies.values.reduce(0, +) / Double(self.peerLatencies.count)
                self.latencyMs = avgLatency
            }

            self.bytesReceived += dataCount
        }

        onAudioDataReceived?(audioData, peer)
    }

    // MARK: - Connection Status

    private func updateConnectionStatus() {
        DispatchQueue.main.async {
            let count = self.connectedPeers.count

            if count == 0 {
                if self.isHosting {
                    self.connectionStatus = "Waiting for others to join..."
                } else if self.currentBubble != nil {
                    self.connectionStatus = "Connecting..."
                } else {
                    self.connectionStatus = "Looking for bubbles..."
                }
            } else if count == 1 {
                self.connectionStatus = "Connected with \(self.connectedPeers[0].displayName)"
            } else {
                self.connectionStatus = "Connected with \(count) people"
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
                    _ = self.getPeerInfo(for: peerID)
                }
                self.isConnected = true
                self.updateConnectionStatus()

                // Update advertised participant count if hosting
                if self.isHosting {
                    self.updateAdvertisedParticipantCount()
                }

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

                // Update advertised participant count if hosting
                if self.isHosting {
                    self.updateAdvertisedParticipantCount()
                }

                self.onPeerDisconnected?(peerID)

            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
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
        // Auto-accept all invitations when hosting
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Failed to advertise: \(error)")
        DispatchQueue.main.async {
            self.connectionStatus = "Failed to create bubble"
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension NetworkManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        print("Found peer: \(peerID.displayName), info: \(info ?? [:])")

        // If we're trying to join a specific bubble, check if this is the host
        if let targetBubble = currentBubble, !isHosting {
            if let foundBubble = BubbleInfo(peerID: peerID, discoveryInfo: info),
               foundBubble.id == targetBubble.id {
                // This is our target bubble's host - send invitation
                browser.invitePeer(peerID, to: session!, withContext: nil, timeout: 30)
                print("Inviting host of target bubble: \(peerID.displayName)")
            }
            return
        }

        // If we're hosting, invite anyone who finds us
        if isHosting {
            if let foundInfo = info,
               let foundBubbleID = foundInfo[BubbleInfo.DiscoveryKeys.bubbleID],
               foundBubbleID == currentBubble?.id {
                // Same bubble - don't invite ourselves
                return
            }

            // Invite this peer to our bubble
            browser.invitePeer(peerID, to: session!, withContext: nil, timeout: 30)
            print("Invited peer to our bubble: \(peerID.displayName)")
            return
        }

        // We're just browsing - add to discovered bubbles
        if let bubble = BubbleInfo(peerID: peerID, discoveryInfo: info) {
            DispatchQueue.main.async {
                // Update or add the bubble
                if let index = self.discoveredBubbles.firstIndex(where: { $0.id == bubble.id }) {
                    self.discoveredBubbles[index] = bubble
                } else {
                    self.discoveredBubbles.append(bubble)
                }
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("Lost peer: \(peerID.displayName)")

        DispatchQueue.main.async {
            self.discoveredBubbles.removeAll { $0.hostPeerID == peerID }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("Failed to browse: \(error)")
        DispatchQueue.main.async {
            self.connectionStatus = "Failed to search for bubbles"
        }
    }
}
