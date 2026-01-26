import SwiftUI
import MultipeerConnectivity

struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    @StateObject private var networkManager = NetworkManager()

    @State private var isActive = false

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 20) {
                    // Header
                    headerView

                    // Connection Status
                    connectionStatusView

                    // Participants Bubble View
                    if isActive {
                        participantsView
                    }

                    Spacer()

                    // Network Stats (when active and connected)
                    if isActive && networkManager.isConnected {
                        networkStatsView
                    }

                    // Main Action Button
                    actionButton
                }
                .padding()
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            setupCallbacks()
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
                .opacity(isActive && networkManager.isConnected ? 1.0 : 0.7)
                .scaleEffect(isActive && networkManager.isConnected ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isActive && networkManager.isConnected)

            Text("Audio Bubble")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(isActive ? "Tap a bubble when speaking" : "Low-Latency Voice Chat")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 20)
    }

    // MARK: - Connection Status View

    private var connectionStatusView: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)

            Text(networkManager.connectionStatus)
                .font(.headline)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.9))
        .cornerRadius(20)
        .shadow(radius: 3)
    }

    private var statusColor: Color {
        if !isActive {
            return .gray
        } else if networkManager.isConnected {
            return .green
        } else {
            return .orange
        }
    }

    // MARK: - Participants View

    private var participantsView: some View {
        VStack(spacing: 15) {
            // "You" bubble - always shown when active
            youBubbleView

            // Connected peers
            if !networkManager.connectedPeers.isEmpty {
                Text("In the Bubble")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 5)

                // Grid of peer bubbles
                LazyVGrid(columns: gridColumns, spacing: 15) {
                    ForEach(networkManager.connectedPeers, id: \.self) { peerID in
                        peerBubbleView(for: peerID)
                    }
                }
            } else if isActive {
                waitingForPeersView
            }
        }
        .padding()
        .background(Color.white.opacity(0.7))
        .cornerRadius(20)
        .shadow(radius: 5)
    }

    private var gridColumns: [GridItem] {
        let count = networkManager.connectedPeers.count
        if count <= 2 {
            return [GridItem(.flexible()), GridItem(.flexible())]
        } else {
            return [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        }
    }

    // MARK: - You Bubble

    private var youBubbleView: some View {
        VStack(spacing: 8) {
            ZStack {
                // Speaking ring
                Circle()
                    .stroke(Color.blue.opacity(audioManager.audioLevel > 0.02 ? 0.8 : 0.2), lineWidth: 4)
                    .frame(width: 80, height: 80)
                    .scaleEffect(audioManager.audioLevel > 0.02 ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: audioManager.audioLevel)

                // Avatar circle
                Circle()
                    .fill(LinearGradient(
                        colors: [.blue, .blue.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 70, height: 70)

                // Icon
                Image(systemName: "person.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)

                // Audio level indicator
                if audioManager.audioLevel > 0.02 {
                    Circle()
                        .fill(Color.green.opacity(0.5))
                        .frame(width: 20, height: 20)
                        .offset(x: 25, y: -25)
                }
            }

            Text("You")
                .font(.caption)
                .fontWeight(.medium)

            // Audio level bar
            audioLevelBar(level: audioManager.audioLevel, color: .blue)
        }
    }

    // MARK: - Peer Bubble

    private func peerBubbleView(for peerID: MCPeerID) -> some View {
        let peerInfo = networkManager.peerInfos[peerID]
        let color = peerInfo?.color ?? .gray
        let isSpeaking = peerInfo?.isSpeaking ?? false
        let audioLevel = peerInfo?.audioLevel ?? 0

        return VStack(spacing: 8) {
            ZStack {
                // Speaking ring
                Circle()
                    .stroke(color.opacity(isSpeaking ? 0.8 : 0.2), lineWidth: 4)
                    .frame(width: 80, height: 80)
                    .scaleEffect(isSpeaking ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isSpeaking)

                // Avatar circle
                Circle()
                    .fill(LinearGradient(
                        colors: [color, color.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 70, height: 70)

                // Icon
                Image(systemName: "person.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)

                // Speaking indicator
                if isSpeaking {
                    Circle()
                        .fill(Color.green.opacity(0.8))
                        .frame(width: 20, height: 20)
                        .offset(x: 25, y: -25)
                }
            }

            Text(peerID.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)

            // Audio level bar
            audioLevelBar(level: audioLevel, color: color)
        }
    }

    // MARK: - Audio Level Bar

    private func audioLevelBar(level: Float, color: Color) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 6)

                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: max(0, CGFloat(level) * geometry.size.width * 10), height: 6)
                    .animation(.linear(duration: 0.1), value: level)
            }
        }
        .frame(width: 60, height: 6)
    }

    // MARK: - Waiting View

    private var waitingForPeersView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Waiting for others to join...")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Make sure other devices have Audio Bubble open")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Network Stats View

    private var networkStatsView: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading) {
                Text("Latency")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(format: "%.0f ms", networkManager.latencyMs))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(latencyColor(networkManager.latencyMs))
            }

            Divider()
                .frame(height: 30)

            VStack(alignment: .leading) {
                Text("Peers")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(networkManager.connectedPeers.count)")
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            Divider()
                .frame(height: 30)

            VStack(alignment: .trailing) {
                Text("Data")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(formatBytes(networkManager.bytesSent + networkManager.bytesReceived))
                    .font(.title3)
                    .fontWeight(.semibold)
            }
        }
        .padding()
        .background(Color.white.opacity(0.9))
        .cornerRadius(15)
        .shadow(radius: 3)
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Button(action: toggleActive) {
            HStack(spacing: 15) {
                Image(systemName: isActive ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))

                Text(isActive ? "Leave Bubble" : "Join Bubble")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(isActive ? Color.red : Color.blue)
            .cornerRadius(15)
            .shadow(radius: 10)
        }
        .padding(.bottom, 20)
    }

    // MARK: - Actions

    private func toggleActive() {
        isActive.toggle()

        if isActive {
            networkManager.startHosting()
            audioManager.startRecording()
        } else {
            audioManager.stopRecording()
            audioManager.removeAllPeers()
            networkManager.stopHosting()
        }
    }

    private func setupCallbacks() {
        // When audio is captured, send it via network
        audioManager.onAudioData = { data in
            networkManager.sendAudioData(data)
        }

        // When audio is received from network, play it and update peer info
        networkManager.onAudioDataReceived = { data, peer in
            audioManager.receiveAudioData(data, from: peer)
        }

        // When peer audio level is calculated, update peer info
        audioManager.onPeerAudioLevel = { peerID, level in
            if let peerInfo = networkManager.peerInfos[peerID] {
                peerInfo.updateAudioLevel(level)
            }
        }

        // When peer connects, add audio player
        networkManager.onPeerConnected = { peerID in
            audioManager.addPeer(peerID)
        }

        // When peer disconnects, remove audio player
        networkManager.onPeerDisconnected = { peerID in
            audioManager.removePeer(peerID)
        }
    }

    // MARK: - Helper Functions

    private func latencyColor(_ latency: Double) -> Color {
        if latency < 50 {
            return .green
        } else if latency < 100 {
            return .orange
        } else {
            return .red
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024 {
            return String(format: "%.0f KB", kb)
        } else {
            let mb = kb / 1024.0
            return String(format: "%.1f MB", mb)
        }
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
