//
//  MockBubbleSessionManager.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/8/25.
//

import Foundation
import MultipeerConnectivity
import Combine

// A mock session manager for SwiftUI previews
class MockBubbleSessionManager: BubbleSessionManager {
    
    // Override the init to create a simple mock
    override init(username: String = "Preview User") {
        super.init(username: username)
        
        // Use the public accessor instead of directly accessing isHeadphonesConnected
        previewHeadphonesConnected = true
        
        // Start a timer to simulate audio activity
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            self?.simulateRandomAudioActivity()
        }
    }
    
    // Simulate random audio activity for previews
    private func simulateRandomAudioActivity() {
        let hostPeerID = MCPeerID(displayName: "Host User")
        let user1PeerID = MCPeerID(displayName: "User 1")
        let user2PeerID = MCPeerID(displayName: "User 2")
        
        let peers = [hostPeerID, user1PeerID, user2PeerID]
        
        // Randomly select a peer to make active
        if let randomPeer = peers.randomElement() {
            let audioData = getAudioDataForPeer(randomPeer)
            
            // 50% chance of being active
            let isActive = Bool.random()
            
            if isActive {
                // Generate random level between 0.3 and 1.0
                let level = CGFloat.random(in: 0.3...1.0)
                
                DispatchQueue.main.async {
                    audioData.level = level
                    audioData.isActive = true
                }
            } else {
                DispatchQueue.main.async {
                    audioData.isActive = false
                    audioData.level = 0.0
                }
            }
        }
    }
}
