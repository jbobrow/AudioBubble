//
//  AudioBubble.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/8/25.
//

import MultipeerConnectivity

struct AudioBubble: Identifiable {
    let id: String
    let name: String
    let hostPeerID: MCPeerID
    var participants: [MCPeerID] = []
}

struct AlertItem: Identifiable {
    let id = UUID()
    let message: String
}
