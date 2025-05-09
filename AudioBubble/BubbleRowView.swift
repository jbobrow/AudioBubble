//
//  BubbleRowView.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/8/25.
//

import SwiftUI
import MultipeerConnectivity

struct BubbleRowView: View {
    let bubble: AudioBubble
    var onJoin: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(bubble.name)
                    .font(.headline)
                Text("Host: \(bubble.hostPeerID.displayName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("\(bubble.participants.count + 1) participants")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Join") {
                onJoin()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .padding(.vertical, 4)
    }
}
