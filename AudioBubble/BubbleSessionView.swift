import SwiftUI
import MultipeerConnectivity

struct BubbleSessionView: View {
    let bubbleName: String
    let isHost: Bool

    @ObservedObject var audioManager: AudioManager
    @ObservedObject var networkManager: NetworkManager
    @ObservedObject var userProfile: UserProfile

    var onLeave: () -> Void

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.2)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with bubble name
                headerView
                    .padding(.top, 10)

                // Connection status
                connectionStatusView
                    .padding(.top, 15)

                // Participants
                participantsView
                    .padding(.top, 20)

                Spacer()

                // Network stats
                if networkManager.isConnected {
                    networkStatsView
                        .padding(.bottom, 10)
                }

                // Leave button
                leaveButton
                    .padding(.bottom, 30)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.title)
                    .foregroundColor(.blue)

                Text(bubbleName)
                    .font(.title2)
                    .fontWeight(.bold)

                if isHost {
                    Text("HOST")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange)
                        .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Connection Status

    private var connectionStatusView: some View {
        HStack {
            Circle()
                .fill(networkManager.isConnected ? Color.green : Color.orange)
                .frame(width: 10, height: 10)

            Text(networkManager.connectionStatus)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.8))
        .cornerRadius(20)
    }

    // MARK: - Participants View

    private var participantsView: some View {
        VStack(spacing: 15) {
            // "You" bubble - always at top
            youBubbleView

            if !networkManager.connectedPeers.isEmpty {
                Text("In this bubble")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 5)

                // Connected peers grid
                LazyVGrid(columns: gridColumns, spacing: 15) {
                    ForEach(networkManager.connectedPeers, id: \.self) { peerID in
                        peerBubbleView(for: peerID)
                    }
                }
            } else {
                waitingView
            }
        }
        .padding()
        .background(Color.white.opacity(0.7))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 10)
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
                    .stroke(
                        userProfile.avatarColor.opacity(audioManager.audioLevel > 0.02 ? 0.8 : 0.2),
                        lineWidth: 4
                    )
                    .frame(width: 85, height: 85)
                    .scaleEffect(audioManager.audioLevel > 0.02 ? 1.08 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: audioManager.audioLevel)

                // Avatar circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [userProfile.avatarColor, userProfile.avatarColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 75, height: 75)

                // Initials
                Text(userInitials)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)

                // Speaking indicator
                if audioManager.audioLevel > 0.02 {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle().stroke(Color.white, lineWidth: 2)
                        )
                        .offset(x: 28, y: -28)
                }
            }

            Text("You")
                .font(.caption)
                .fontWeight(.medium)

            audioLevelBar(level: audioManager.audioLevel, color: userProfile.avatarColor)
        }
    }

    private var userInitials: String {
        let name = userProfile.displayName
        let components = name.split(separator: " ")
        if components.count >= 2 {
            let first = components[0].prefix(1)
            let last = components[1].prefix(1)
            return "\(first)\(last)".uppercased()
        } else {
            return String(name.prefix(2)).uppercased()
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
                    .frame(width: 85, height: 85)
                    .scaleEffect(isSpeaking ? 1.08 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isSpeaking)

                // Avatar circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 75, height: 75)

                // Initials
                Text(peerInitials(peerID.displayName))
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)

                // Speaking indicator
                if isSpeaking {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle().stroke(Color.white, lineWidth: 2)
                        )
                        .offset(x: 28, y: -28)
                }
            }

            Text(peerID.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)

            audioLevelBar(level: audioLevel, color: color)
        }
    }

    private func peerInitials(_ name: String) -> String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            let first = components[0].prefix(1)
            let last = components[1].prefix(1)
            return "\(first)\(last)".uppercased()
        } else {
            return String(name.prefix(2)).uppercased()
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

    private var waitingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Waiting for others to join...")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if isHost {
                Text("Others can see '\(bubbleName)' nearby")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 20)
    }

    // MARK: - Network Stats

    private var networkStatsView: some View {
        HStack(spacing: 25) {
            VStack(spacing: 2) {
                Text("Latency")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "%.0f ms", networkManager.latencyMs))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(latencyColor)
            }

            Divider()
                .frame(height: 25)

            VStack(spacing: 2) {
                Text("Peers")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(networkManager.connectedPeers.count)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            Divider()
                .frame(height: 25)

            VStack(spacing: 2) {
                Text("Data")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(formatBytes(networkManager.bytesSent + networkManager.bytesReceived))
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.9))
        .cornerRadius(15)
    }

    private var latencyColor: Color {
        if networkManager.latencyMs < 50 {
            return .green
        } else if networkManager.latencyMs < 100 {
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

    // MARK: - Leave Button

    private var leaveButton: some View {
        Button(action: onLeave) {
            HStack(spacing: 10) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)

                Text("Leave Bubble")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.red.opacity(0.9))
            .cornerRadius(15)
        }
    }
}

// MARK: - Preview

struct BubbleSessionView_Previews: PreviewProvider {
    static var previews: some View {
        BubbleSessionView(
            bubbleName: "Living Room",
            isHost: true,
            audioManager: AudioManager(),
            networkManager: NetworkManager(),
            userProfile: UserProfile.shared,
            onLeave: {}
        )
    }
}
