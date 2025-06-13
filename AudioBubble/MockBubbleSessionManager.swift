//
//  MockBubbleSessionManager.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/8/25.
//

import Foundation
import MultipeerConnectivity

class MockBubbleSessionManager: BubbleSessionManager {
    
    override init(username: String = "Preview User") {
        super.init(username: username)
        setupMockStates()
    }
    
    override var isHeadphonesConnected: Bool {
        return true // Always true for previews
    }
    
    // Override to expose the correct type for previews
    var previewHeadphonesConnected: Bool {
        get { return true }
        set { /* ignore for mock */ }
    }
    
    private func setupMockStates() {
        let hostPeerID = MCPeerID(displayName: "Host User")
        let user1PeerID = MCPeerID(displayName: "User 1")
        let user2PeerID = MCPeerID(displayName: "User 2")
        
        // Set some static mock audio states for previews
        getAudioDataForPeer(hostPeerID).simulateActivity(active: true, level: 0.6)
        getAudioDataForPeer(user1PeerID).simulateActivity(active: false, level: 0.0)
        getAudioDataForPeer(user2PeerID).simulateActivity(active: true, level: 0.8)
    }
}
