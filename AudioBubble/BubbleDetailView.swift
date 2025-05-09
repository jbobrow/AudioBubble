//
//  BubbleDetailView.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/8/25.
//

import SwiftUI
import MultipeerConnectivity

struct BubbleDetailView: View {
    let bubble: AudioBubble
    let isHost: Bool
    var onLeave: () -> Void
    @ObservedObject var sessionManager: BubbleSessionManager
    
    var body: some View {
        VStack(spacing: 20) {
            VStack {
                Text(bubble.name)
                    .font(.title)
                    .fontWeight(.bold)
                
                if isHost {
                    Text("You are the host")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
                
                Text("Active Conversation")
                    .font(.headline)
                    .padding(.top)
                
                // Animated sound waves
                HStack(spacing: 4) {
                    ForEach(0..<5) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .frame(width: 4, height: 20)
                            .foregroundColor(.blue)
                            .opacity(0.8)
                            .animation(
                                Animation.easeInOut(duration: 0.5)
                                    .repeatForever()
                                    .delay(Double.random(in: 0...0.5)),
                                value: UUID()
                            )
                    }
                }
                .padding()
                
                // Monitoring toggle
                Toggle("Monitor My Microphone", isOn: Binding(
                    get: { sessionManager.isMonitoringEnabled },
                    set: { sessionManager.toggleMonitoring(enabled: $0) }
                ))
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                
                // Participants
                VStack(alignment: .leading) {
                    Text("Participants:")
                        .font(.headline)
                    
                    ForEach([bubble.hostPeerID] + bubble.participants, id: \.self) { peer in
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(.blue)
                            Text(peer.displayName)
                                .fontWeight(peer == bubble.hostPeerID ? .bold : .regular)
                            
                            if peer == bubble.hostPeerID {
                                Text("(Host)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            // Animated speaking indicator (simplified)
                            Image(systemName: "waveform")
                                .foregroundColor(.green)
                                .opacity(Double.random(in: 0...1) > 0.7 ? 1.0 : 0.0)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
            }
            
            Spacer()
            
            Button(action: onLeave) {
                Text("Leave Bubble")
                    .fontWeight(.bold)
                    .padding()
                    .frame(width: 200)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
}
