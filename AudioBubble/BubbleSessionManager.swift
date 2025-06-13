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
    
    // Audio management delegation
    private let audioManager = AudioManager()
    
    // Expose audio properties through computed properties
    var isHeadphonesConnected: Bool { audioManager.isHeadphonesConnected }
    var isMonitoringEnabled: Bool { audioManager.isMonitoringEnabled }
    
    // MultipeerConnectivity components
    private var myPeerID: MCPeerID
    private var serviceType = "audio-bubble"
    private var session: MCSession?
    private var nearbyServiceBrowser: MCNearbyServiceBrowser?
    private var nearbyServiceAdvertiser: MCNearbyServiceAdvertiser?
    
    var currentPeerID: MCPeerID {
        return myPeerID
    }
    
    init(username: String) {
        self.myPeerID = MCPeerID(displayName: username)
        super.init()
        
        audioManager.audioDelegate = self
    }
    
    // MARK: - Public Methods
    
    func setupSession() {
        cleanupSession()
        
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
        
        nearbyServiceBrowser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        nearbyServiceBrowser?.delegate = self
        
        nearbyServiceBrowser?.startBrowsingForPeers()
    }
    
    func createBubble(name: String) {
        guard isHeadphonesConnected else {
            errorMessage = "Headphones required to create a bubble"
            return
        }
        
        let bubble = AudioBubble(id: UUID().uuidString, name: name, hostPeerID: myPeerID)
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
        
        browser.invitePeer(bubble.hostPeerID, to: session, withContext: nil, timeout: 10)
        currentBubble = bubble
        isHost = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            if !self.isConnected && self.currentBubble?.id == bubble.id {
                self.errorMessage = "Failed to connect to bubble"
                self.currentBubble = nil
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
}

// MARK: - AudioManagerDelegate

extension BubbleSessionManager: AudioManagerDelegate {
    func audioManager(_ manager: AudioManager, didCaptureAudioData data: Data) {
        guard let session = session, !session.connectedPeers.isEmpty else { return }
        
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .unreliable)
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
        audioManager.processIncomingAudio(data, fromPeer: peerID.displayName)
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
