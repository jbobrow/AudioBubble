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
        @Published var audioLevels: [CGFloat] = [0, 0, 0, 0, 0]
        
        private var cancellables = Set<AnyCancellable>()
        
        init(audioData: BubbleSessionManager.ParticipantAudioData) {
            // Subscribe to changes in the audio data
            audioData.$isActive
                .sink { [weak self] newValue in
                    self?.isAudioActive = newValue
                }
                .store(in: &cancellables)
            
            audioData.$levels
                .sink { [weak self] newValues in
                    self?.audioLevels = newValues
                }
                .store(in: &cancellables)
        }
    }
    
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
                            
                            // Audio level meter
                            if let viewState = participantStates[peer] {
                                AudioLevelMeterView(
                                    levels: viewState.audioLevels,
                                    isActive: viewState.isAudioActive
                                )
                            } else {
                                AudioLevelMeterView() // Default inactive state
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
            
            // In preview/demo mode, set up a timer to simulate audio activity
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                simulationTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                    simulateRandomActivity()
                }
            }
        }
        .onDisappear {
            simulationTimer?.invalidate()
            simulationTimer = nil
        }
    }
    
    private func setupParticipantStates() {
        // Initialize states for all participants including host
        let allPeers = [bubble.hostPeerID] + bubble.participants
        
        for peer in allPeers {
            let audioData = sessionManager.getAudioDataForPeer(peer)
            participantStates[peer] = ParticipantViewState(audioData: audioData)
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
    
    // For demo/preview mode only
    private func simulateRandomActivity() {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" else { return }
        
        let allPeers = [bubble.hostPeerID] + bubble.participants
        guard let randomPeer = allPeers.randomElement() else { return }
        
        // Simulate activity for a random peer
        let audioData = sessionManager.getAudioDataForPeer(randomPeer)
        audioData.simulateActivity(active: Bool.random())
    }
}
