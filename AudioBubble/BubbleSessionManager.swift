//
//  BubbleSessionManager.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/8/25.
//

import SwiftUI
import MultipeerConnectivity
import Combine

class BubbleSessionManager: NSObject, ObservableObject {
    // Published properties for UI
    @Published var availableBubbles: [AudioBubble] = []
    @Published var currentBubble: AudioBubble?
    @Published var isHost = false
    @Published var isConnected = false
    @Published var errorMessage: String?
    
    // Forward AudioManager published properties to our published properties
    @Published var isHeadphonesConnected = false
    @Published var isMonitoringEnabled = false
    
    // Audio management delegation
    private let audioManager = AudioManager()
    
    // MultipeerConnectivity components
    private var myPeerID: MCPeerID
    private var serviceType = "audio-bubble"
    private var session: MCSession?
    private var nearbyServiceBrowser: MCNearbyServiceBrowser?
    private var nearbyServiceAdvertiser: MCNearbyServiceAdvertiser?
    
    // Connection management
    private var connectionRetryCount = 0
    private let maxRetryAttempts = 3
    
    // Combine cancellables
    private var cancellables = Set<AnyCancellable>()
    
    var currentPeerID: MCPeerID {
        return myPeerID
    }
    
    init(username: String) {
        self.myPeerID = MCPeerID(displayName: username)
        super.init()
        
        audioManager.audioDelegate = self
        setupAudioManagerObservation()
    }
    
    // MARK: - Audio Manager Observation
    
    private func setupAudioManagerObservation() {
        // Forward AudioManager published properties to our published properties
        audioManager.$isHeadphonesConnected
            .receive(on: DispatchQueue.main)
            .assign(to: \.isHeadphonesConnected, on: self)
            .store(in: &cancellables)
        
        audioManager.$isMonitoringEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: \.isMonitoringEnabled, on: self)
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    func setupSession() {
        cleanupSession()
        
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .none)
        session?.delegate = self
        
        nearbyServiceBrowser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        nearbyServiceBrowser?.delegate = self
        
        nearbyServiceBrowser?.startBrowsingForPeers()
        print("Session setup complete for \(myPeerID.displayName)")
        
        // Add a delay to ensure session is fully ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("Session ready with \(self.session?.connectedPeers.count ?? 0) connected peers")
        }
    }
    
    func createBubble(name: String) {
        guard isHeadphonesConnected else {
            errorMessage = "Headphones required to create a bubble"
            return
        }
        
        var bubble = AudioBubble(id: UUID().uuidString, name: name, hostPeerID: myPeerID)
        
        // Host is always the first participant
        bubble.participants = [myPeerID]
        
        currentBubble = bubble
        isHost = true
        isConnected = true
        
        let info = ["bubbleID": bubble.id, "bubbleName": name]
        nearbyServiceAdvertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: info, serviceType: serviceType)
        nearbyServiceAdvertiser?.delegate = self
        nearbyServiceAdvertiser?.startAdvertisingPeer()
        
        audioManager.startAudioEngine()
    }
    
    func joinBubble(_ bubble: AudioBubble) {
        guard isHeadphonesConnected else {
            errorMessage = "Headphones required to join a bubble"
            return
        }
        
        guard let browser = nearbyServiceBrowser, let session = session else {
            errorMessage = "Session not ready"
            return
        }
        
        connectionRetryCount = 0
        attemptConnection(to: bubble, with: browser, session: session)
    }
    
    private func attemptConnection(to bubble: AudioBubble, with browser: MCNearbyServiceBrowser, session: MCSession) {
        browser.invitePeer(bubble.hostPeerID, to: session, withContext: nil, timeout: 10)
        currentBubble = bubble
        isHost = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            if !self.isConnected && self.currentBubble?.id == bubble.id {
                self.connectionRetryCount += 1
                
                if self.connectionRetryCount < self.maxRetryAttempts {
                    print("Connection attempt \(self.connectionRetryCount) failed, retrying...")
                    self.attemptConnection(to: bubble, with: browser, session: session)
                } else {
                    self.errorMessage = "Failed to connect after \(self.maxRetryAttempts) attempts"
                    self.currentBubble = nil
                    self.connectionRetryCount = 0
                }
            }
        }
    }
    
    func leaveBubble() {
        cleanupSession()
        audioManager.stopAudioEngine()
        
        DispatchQueue.main.async {
            self.currentBubble = nil
            self.isConnected = false
            self.isHost = false
        }
        
        setupSession()
    }
    
    func toggleMonitoring(enabled: Bool) {
        audioManager.toggleMonitoring(enabled: enabled)
    }
    
    func updateAudioSettings(_ settings: AudioSettings) {
        audioManager.updateSettings(settings)
    }
    
    func getAudioDataForPeer(_ peerID: MCPeerID) -> AudioManager.ParticipantAudioData {
        let peerKey = (peerID == myPeerID) ? "local" : peerID.displayName
        return audioManager.getAudioDataForPeer(peerKey)
    }
    
    func simulateAudioActivity(for peerID: MCPeerID, active: Bool, level: CGFloat? = nil) {
        let peerKey = (peerID == myPeerID) ? "local" : peerID.displayName
        let audioData = audioManager.getAudioDataForPeer(peerKey)
        
        if active {
            let customLevel = level ?? CGFloat.random(in: 0.3...1.0)
            audioData.simulateActivity(active: true, level: customLevel)
        } else {
            audioData.simulateActivity(active: false, level: 0.0)
        }
    }
    
    // MARK: - Private Methods
    
    private func cleanupSession() {
        nearbyServiceBrowser?.stopBrowsingForPeers()
        nearbyServiceAdvertiser?.stopAdvertisingPeer()
        
        session?.disconnect()
        
        session?.delegate = nil
        nearbyServiceBrowser?.delegate = nil
        nearbyServiceAdvertiser?.delegate = nil
        
        session = nil
        nearbyServiceBrowser = nil
        nearbyServiceAdvertiser = nil
    }
    
    // MARK: - Cleanup
    
    deinit {
        cleanupSession()
        cancellables.removeAll()
    }
}

// MARK: - AudioManagerDelegate

extension BubbleSessionManager: AudioManagerDelegate {
    func audioManager(_ manager: AudioManager, didCaptureAudioData data: Data) {
        guard let session = session, !session.connectedPeers.isEmpty else {
            print("No connected peers to send audio to")
            return
        }
        
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .unreliable)
            print("Sent audio data to \(session.connectedPeers.count) peers: \(data.count) bytes")
        } catch {
            print("Send error: \(error)")
        }
    }
}

// MARK: - MultipeerConnectivity Delegates

extension BubbleSessionManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if let bubble = self.currentBubble {
                    var updatedBubble = bubble
                    if !updatedBubble.participants.contains(peerID) && peerID != updatedBubble.hostPeerID {
                        updatedBubble.participants.append(peerID)
                    }
                    self.currentBubble = updatedBubble
                }
                self.isConnected = true
                
                DispatchQueue.global(qos: .userInitiated).async {
                    if !self.isHost {
                        self.audioManager.startAudioEngine()
                    }
                }
                
            case .connecting:
                print("Connecting to \(peerID.displayName)")
                
            case .notConnected:
                if let bubble = self.currentBubble {
                    var updatedBubble = bubble
                    updatedBubble.participants.removeAll { $0 == peerID }
                    self.currentBubble = updatedBubble
                }
                
                self.audioManager.cleanupPeer(peerID.displayName)
                
            @unknown default:
                print("Unknown state: \(state)")
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Check if this is a participant list update
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let participantNames = json["participants"] as? [String] {
            
            DispatchQueue.main.async {
                if let bubble = self.currentBubble {
                    var updatedBubble = bubble
                    // Convert names back to MCPeerID objects
                    var participants: [MCPeerID] = []
                    
                    for name in participantNames {
                        if name == bubble.hostPeerID.displayName {
                            participants.append(bubble.hostPeerID)
                        } else if name == self.myPeerID.displayName {
                            participants.append(self.myPeerID)
                        } else {
                            // Find from connected peers
                            if let peer = session.connectedPeers.first(where: { $0.displayName == name }) {
                                participants.append(peer)
                            }
                        }
                    }
                    
                    updatedBubble.participants = participants
                    self.currentBubble = updatedBubble
                    print("Received participant update: \(participantNames)")
                }
            }
        } else {
            // This is audio data - log it
            print("Received audio data from \(peerID.displayName): \(data.count) bytes")
            audioManager.processIncomingAudio(data, fromPeer: peerID.displayName)
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used
    }
}

extension BubbleSessionManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            guard let info = info,
                  let bubbleID = info["bubbleID"],
                  let bubbleName = info["bubbleName"] else { return }
            
            let bubble = AudioBubble(id: bubbleID, name: bubbleName, hostPeerID: peerID)
            
            if !self.availableBubbles.contains(where: { $0.id == bubble.id }) {
                self.availableBubbles.append(bubble)
            }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.availableBubbles.removeAll { $0.hostPeerID == peerID }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        errorMessage = "Failed to start browsing: \(error.localizedDescription)"
    }
}

extension BubbleSessionManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        errorMessage = "Failed to start advertising: \(error.localizedDescription)"
    }
}
