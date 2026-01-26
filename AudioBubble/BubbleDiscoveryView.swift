import SwiftUI

struct BubbleDiscoveryView: View {
    @ObservedObject var networkManager: NetworkManager
    @ObservedObject var userProfile: UserProfile

    var onJoinBubble: (BubbleInfo) -> Void
    var onCreateBubble: (String) -> Void

    @State private var showCreateSheet = false
    @State private var newBubbleName = ""
    @State private var isSearching = false

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.15), Color.purple.opacity(0.15)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView
                    .padding(.top, 10)

                // Content
                ScrollView {
                    VStack(spacing: 20) {
                        // User info card
                        userInfoCard
                            .padding(.horizontal)

                        // Nearby bubbles section
                        nearbyBubblesSection
                            .padding(.horizontal)

                        // Create bubble button
                        createBubbleButton
                            .padding(.horizontal)
                            .padding(.bottom, 30)
                    }
                    .padding(.top, 20)
                }
            }
        }
        .onAppear {
            startSearching()
        }
        .onDisappear {
            networkManager.stopBrowsing()
        }
        .sheet(isPresented: $showCreateSheet) {
            createBubbleSheet
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Audio Bubble")
                .font(.title)
                .fontWeight(.bold)
        }
    }

    // MARK: - User Info Card

    private var userInfoCard: some View {
        HStack(spacing: 15) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [userProfile.avatarColor, userProfile.avatarColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)

                Text(userInitials)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(userProfile.displayName)
                    .font(.headline)

                Text("Ready to chat")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color.white.opacity(0.9))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10)
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

    // MARK: - Nearby Bubbles Section

    private var nearbyBubblesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Nearby Bubbles")
                    .font(.headline)

                Spacer()

                if isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if networkManager.discoveredBubbles.isEmpty {
                emptyBubblesView
            } else {
                ForEach(networkManager.discoveredBubbles) { bubble in
                    BubbleRow(bubble: bubble) {
                        onJoinBubble(bubble)
                    }
                }
            }
        }
    }

    private var emptyBubblesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.5))

            Text("No bubbles nearby")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Create one and invite others to join!")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color.white.opacity(0.5))
        .cornerRadius(16)
    }

    // MARK: - Create Bubble Button

    private var createBubbleButton: some View {
        Button(action: { showCreateSheet = true }) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)

                Text("Create a Bubble")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .shadow(color: .blue.opacity(0.3), radius: 10)
        }
    }

    // MARK: - Create Bubble Sheet

    private var createBubbleSheet: some View {
        NavigationView {
            VStack(spacing: 30) {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("Create a Bubble")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Give your bubble a name so others can find it")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Bubble Name")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("e.g. Living Room, Team Standup", text: $newBubbleName)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                Spacer()

                Button(action: createBubble) {
                    Text("Create Bubble")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canCreate ? Color.blue : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(!canCreate)
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showCreateSheet = false
                        newBubbleName = ""
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var canCreate: Bool {
        !newBubbleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func startSearching() {
        isSearching = true
        networkManager.startBrowsing()

        // Keep searching indicator for a few seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            isSearching = false
        }
    }

    private func createBubble() {
        let name = newBubbleName.trimmingCharacters(in: .whitespacesAndNewlines)
        showCreateSheet = false
        newBubbleName = ""
        onCreateBubble(name)
    }
}

// MARK: - Bubble Row

private struct BubbleRow: View {
    let bubble: BubbleInfo
    let onJoin: () -> Void

    var body: some View {
        HStack(spacing: 15) {
            // Bubble icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.8), .purple.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)

                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(bubble.name)
                    .font(.headline)

                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                    Text("\(bubble.participantCount)")
                        .font(.caption)

                    Text("hosted by \(bubble.hostName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(action: onJoin) {
                Text("Join")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .cornerRadius(20)
            }
        }
        .padding()
        .background(Color.white.opacity(0.9))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }
}

// MARK: - Preview

struct BubbleDiscoveryView_Previews: PreviewProvider {
    static var previews: some View {
        BubbleDiscoveryView(
            networkManager: NetworkManager(),
            userProfile: UserProfile.shared,
            onJoinBubble: { _ in },
            onCreateBubble: { _ in }
        )
    }
}
