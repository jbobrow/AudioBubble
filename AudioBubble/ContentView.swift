import SwiftUI
import MultipeerConnectivity

/// App state to manage navigation between views
enum AppState: Equatable {
    case onboarding
    case discovery
    case inSession(bubbleName: String, isHost: Bool)

    static func == (lhs: AppState, rhs: AppState) -> Bool {
        switch (lhs, rhs) {
        case (.onboarding, .onboarding): return true
        case (.discovery, .discovery): return true
        case (.inSession(let n1, let h1), .inSession(let n2, let h2)): return n1 == n2 && h1 == h2
        default: return false
        }
    }
}

struct ContentView: View {
    @StateObject private var userProfile = UserProfile.shared
    @StateObject private var audioManager = AudioManager()
    @StateObject private var networkManager: NetworkManager

    @State private var appState: AppState

    init() {
        // Initialize network manager with shared user profile
        let nm = NetworkManager(userProfile: UserProfile.shared)
        _networkManager = StateObject(wrappedValue: nm)

        // Set initial state based on whether onboarding is complete
        if UserProfile.shared.hasCompletedOnboarding {
            _appState = State(initialValue: .discovery)
        } else {
            _appState = State(initialValue: .onboarding)
        }
    }

    var body: some View {
        Group {
            switch appState {
            case .onboarding:
                OnboardingView(userProfile: userProfile) {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        appState = .discovery
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

            case .discovery:
                BubbleDiscoveryView(
                    networkManager: networkManager,
                    userProfile: userProfile,
                    onJoinBubble: joinBubble,
                    onCreateBubble: createBubble
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

            case .inSession(let bubbleName, let isHost):
                BubbleSessionView(
                    bubbleName: bubbleName,
                    isHost: isHost,
                    audioManager: audioManager,
                    networkManager: networkManager,
                    userProfile: userProfile,
                    onLeave: leaveBubble
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
        .onAppear {
            setupCallbacks()
        }
    }

    // MARK: - Actions

    private func joinBubble(_ bubble: BubbleInfo) {
        // Update network manager display name if needed
        networkManager.updateDisplayName(userProfile.displayName)

        // Join the bubble
        networkManager.joinBubble(bubble)

        // Start audio
        audioManager.startRecording()

        // Navigate to session
        withAnimation(.easeInOut(duration: 0.4)) {
            appState = .inSession(bubbleName: bubble.name, isHost: false)
        }
    }

    private func createBubble(_ name: String) {
        // Update network manager display name if needed
        networkManager.updateDisplayName(userProfile.displayName)

        // Create and host the bubble
        networkManager.createBubble(name: name)

        // Start audio
        audioManager.startRecording()

        // Navigate to session
        withAnimation(.easeInOut(duration: 0.4)) {
            appState = .inSession(bubbleName: name, isHost: true)
        }
    }

    private func leaveBubble() {
        // Stop audio
        audioManager.stopRecording()
        audioManager.removeAllPeers()

        // Stop networking
        networkManager.stopAll()

        // Navigate back to discovery
        withAnimation(.easeInOut(duration: 0.4)) {
            appState = .discovery
        }
    }

    // MARK: - Callbacks Setup

    private func setupCallbacks() {
        // When audio is captured, send it via network
        audioManager.onAudioData = { [weak networkManager] data in
            networkManager?.sendAudioData(data)
        }

        // When audio is received from network, play it
        networkManager.onAudioDataReceived = { [weak audioManager] data, peer in
            audioManager?.receiveAudioData(data, from: peer)
        }

        // When peer audio level is calculated, update peer info
        audioManager.onPeerAudioLevel = { [weak networkManager] peerID, level in
            if let peerInfo = networkManager?.peerInfos[peerID] {
                peerInfo.updateAudioLevel(level)
            }
        }

        // When peer connects, add audio player
        networkManager.onPeerConnected = { [weak audioManager] peerID in
            audioManager?.addPeer(peerID)
        }

        // When peer disconnects, remove audio player
        networkManager.onPeerDisconnected = { [weak audioManager] peerID in
            audioManager?.removePeer(peerID)
        }
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
