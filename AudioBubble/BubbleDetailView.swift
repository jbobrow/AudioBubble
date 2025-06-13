//
//  BubbleDetailView.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/8/25.
//

import SwiftUI
import MultipeerConnectivity
import Combine

struct BubbleDetailView: View {
    let bubble: AudioBubble
    let isHost: Bool
    var onLeave: () -> Void
    @ObservedObject var sessionManager: BubbleSessionManager
    @State private var participantStates: [MCPeerID: ParticipantViewState] = [:]
    
    // Timer for simulating audio activity in preview/demo mode
    @State private var simulationTimer: Timer? = nil
    
    // View state for each participant, including the host
    class ParticipantViewState: ObservableObject {
        @Published var isAudioActive: Bool = false
        @Published var audioLevel: CGFloat = 0.0
        
        private var cancellables = Set<AnyCancellable>()
        
        init(audioData: AudioManager.ParticipantAudioData) {  // Change this line
            // Subscribe to changes in the audio data
            audioData.$isActive
                .receive(on: DispatchQueue.main)
                .sink { [weak self] newValue in
                    self?.isAudioActive = newValue
                }
                .store(in: &cancellables)
            
            audioData.$level
                .receive(on: DispatchQueue.main)
                .sink { [weak self] newValue in
                    self?.audioLevel = newValue
                }
                .store(in: &cancellables)
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Audio Bubble Icon
            Circle()
                .fill(.blue.gradient)
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }
            
            VStack(spacing: 8) {
                Text(bubble.name)
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(isHost ? "You're hosting this bubble" : "Hosted by \(bubble.hostPeerID.displayName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top)
        VStack(spacing: 20) {
            VStack {
                Text("Active Conversation")
                    .font(.headline)
                    .padding(.top)
                
                // Monitoring toggle
                Toggle("Monitor My Microphone", isOn: Binding(
                    get: { sessionManager.isMonitoringEnabled },
                    set: { sessionManager.toggleMonitoring(enabled: $0) }
                ))
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                
                // Participants
                VStack(alignment: .leading) {
                    Text("Participants:")
                        .font(.headline)
                    
                    // Get a unique list of participants
                    let allPeers = getAllUniquePeers()
                    
                    ForEach(allPeers, id: \.self) { peer in
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
                            
                            // Simple audio indicator - choose one of these:
                            if let viewState = participantStates[peer] {
                                // Option 1: Circle indicator
                                SimpleAudioIndicator(
                                    isActive: viewState.isAudioActive,
                                    level: viewState.audioLevel
                                )
                                
                                // Option 2: Bar indicator (uncomment to use instead)
                                // SimpleAudioBar(
                                //     isActive: viewState.isAudioActive,
                                //     level: viewState.audioLevel
                                // )
                                
                                // Option 3: Wave indicator (uncomment to use instead)
                                // SimpleWaveIndicator(
                                //     isActive: viewState.isAudioActive,
                                //     level: viewState.audioLevel
                                // )
                            } else {
                                SimpleAudioIndicator(isActive: false, level: 0.0)
                            }
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
        .onAppear {
            setupParticipantStates()
        }
        .onDisappear {
            // nothing needed here at the moment
        }
    }
    
    private func setupParticipantStates() {
        participantStates.removeAll()
        
        // Always include the host
        let hostState = ParticipantViewState(audioData: sessionManager.getAudioDataForPeer(bubble.hostPeerID))
        participantStates[bubble.hostPeerID] = hostState
        
        // Add all other participants
        for participant in bubble.participants {
            if participant != bubble.hostPeerID {  // Don't duplicate the host
                let state = ParticipantViewState(audioData: sessionManager.getAudioDataForPeer(participant))
                participantStates[participant] = state
            }
        }
    }
    
    private func getAllUniquePeers() -> [MCPeerID] {
        var uniquePeers = [MCPeerID]()
        
        // Always add the host first
        uniquePeers.append(bubble.hostPeerID)
        
        // Add other participants if they're not the host
        for participant in bubble.participants {
            if !uniquePeers.contains(participant) {
                uniquePeers.append(participant)
            }
        }
        
        return uniquePeers
    }
}

// MARK: - BubbleDetailView Previews

#Preview("Host View") {
    let mockSessionManager = MockBubbleSessionManager()
    let hostPeerID = MCPeerID(displayName: "Host User")
    let bubble = AudioBubble(
        id: "bubble-1",
        name: "Test Bubble",
        hostPeerID: hostPeerID,
        participants: [
            MCPeerID(displayName: "User 1"),
            MCPeerID(displayName: "User 2")
        ]
    )
    
    return BubbleDetailView(
        bubble: bubble,
        isHost: true,
        onLeave: {},
        sessionManager: mockSessionManager
    )
}

#Preview("Participant View") {
    let mockSessionManager = MockBubbleSessionManager()
    let hostPeerID = MCPeerID(displayName: "Host User")
    let bubble = AudioBubble(
        id: "bubble-1",
        name: "Test Bubble",
        hostPeerID: hostPeerID,
        participants: [
            MCPeerID(displayName: "User 1"),
            MCPeerID(displayName: "User 2")
        ]
    )
    
    return BubbleDetailView(
        bubble: bubble,
        isHost: false,
        onLeave: {},
        sessionManager: mockSessionManager
    )
}
