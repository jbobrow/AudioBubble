import MultipeerConnectivity
import Foundation
import Combine

class NetworkManager: NSObject, ObservableObject {
    // Published properties for UI
    @Published var connectedPeers: [MCPeerID] = []
    @Published var availablePeers: [MCPeerID] = []
    @Published var isConnected = false
    @Published var connectionStatus = "Disconnected"
    
    // MultipeerConnectivity components
    private let serviceType = "audio-bubble"
    private var myPeerID: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser
    private var browser: MCNearbyServiceBrowser
    
    // Audio data callback
    var onAudioDataReceived: ((Data, MCPeerID) -> Void)?
    
    // Network stats
    @Published var bytesSent: Int = 0
    @Published var bytesReceived: Int = 0
    @Published var latencyMs: Double = 0
    
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
        
        print("📱 Network Manager initialized as: \(deviceName)")
    }
    
    // MARK: - Connection Management
    
    func startHosting() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        connectionStatus = "Looking for peers..."
        print("🔍 Started advertising and browsing")
    }
    
    func stopHosting() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        connectionStatus = "Disconnected"
        connectedPeers.removeAll()
        availablePeers.removeAll()
        isConnected = false
        print("⏹️ Stopped hosting")
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
            print("❌ Error sending audio: \(error)")
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
                // Use exponential moving average for smooth latency display
                self.latencyMs = self.latencyMs * 0.8 + latency * 0.2
                self.bytesReceived += dataCount
            }
            
            onAudioDataReceived?(audioData, peer)
        }
    }
}

// MARK: - MCSessionDelegate

extension NetworkManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                print("✅ Connected to: \(peerID.displayName)")
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                }
                self.isConnected = true
                self.connectionStatus = "Connected to \(peerID.displayName)"
                
            case .connecting:
                print("🔄 Connecting to: \(peerID.displayName)")
                self.connectionStatus = "Connecting..."
                
            case .notConnected:
                print("❌ Disconnected from: \(peerID.displayName)")
                self.connectedPeers.removeAll { $0 == peerID }
                self.isConnected = !self.connectedPeers.isEmpty
                self.connectionStatus = self.isConnected ? "Connected" : "Disconnected"
                
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
        print("📨 Received invitation from: \(peerID.displayName)")
        // Auto-accept invitations for PoC
        invitationHandler(true, session)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("❌ Failed to advertise: \(error)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension NetworkManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("🔍 Found peer: \(peerID.displayName)")
        
        DispatchQueue.main.async {
            if !self.availablePeers.contains(peerID) {
                self.availablePeers.append(peerID)
            }
        }
        
        // Auto-invite found peers for PoC
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
        print("📤 Invited peer: \(peerID.displayName)")
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("📡 Lost peer: \(peerID.displayName)")
        
        DispatchQueue.main.async {
            self.availablePeers.removeAll { $0 == peerID }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("❌ Failed to browse: \(error)")
    }
}
