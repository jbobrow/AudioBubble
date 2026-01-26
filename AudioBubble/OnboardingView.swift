import SwiftUI

struct OnboardingView: View {
    @ObservedObject var userProfile: UserProfile
    var onComplete: () -> Void

    @State private var currentPage = 0
    @State private var userName = ""
    @State private var selectedColorIndex = 0

    private let totalPages = 3

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
                // Page content
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    featuresPage.tag(1)
                    profileSetupPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                // Page indicator and buttons
                VStack(spacing: 20) {
                    // Page dots
                    HStack(spacing: 8) {
                        ForEach(0..<totalPages, id: \.self) { index in
                            Circle()
                                .fill(index == currentPage ? Color.blue : Color.gray.opacity(0.4))
                                .frame(width: 8, height: 8)
                                .animation(.easeInOut, value: currentPage)
                        }
                    }

                    // Navigation buttons
                    HStack(spacing: 20) {
                        if currentPage > 0 {
                            Button("Back") {
                                withAnimation { currentPage -= 1 }
                            }
                            .foregroundColor(.secondary)
                        }

                        Spacer()

                        if currentPage < totalPages - 1 {
                            Button(action: {
                                withAnimation { currentPage += 1 }
                            }) {
                                HStack {
                                    Text("Next")
                                    Image(systemName: "arrow.right")
                                }
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 30)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .cornerRadius(25)
                            }
                        } else {
                            Button(action: completeOnboarding) {
                                HStack {
                                    Text("Get Started")
                                    Image(systemName: "arrow.right")
                                }
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 30)
                                .padding(.vertical, 12)
                                .background(canComplete ? Color.blue : Color.gray)
                                .cornerRadius(25)
                            }
                            .disabled(!canComplete)
                        }
                    }
                    .padding(.horizontal, 30)
                }
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 30) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 100))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Audio Bubble")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Voice chat that just works.\nNo accounts. No internet. Just talk.")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Page 2: Features

    private var featuresPage: some View {
        VStack(spacing: 25) {
            Spacer()

            Text("How it works")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 20) {
                FeatureRow(
                    icon: "wifi",
                    title: "Local Network",
                    description: "Connect with nearby devices over WiFi or Bluetooth"
                )

                FeatureRow(
                    icon: "bolt.fill",
                    title: "Low Latency",
                    description: "FaceTime-quality audio with minimal delay"
                )

                FeatureRow(
                    icon: "person.3.fill",
                    title: "Group Chat",
                    description: "Talk with multiple people at once"
                )

                FeatureRow(
                    icon: "lock.shield.fill",
                    title: "Private",
                    description: "No servers, no accounts, no data collection"
                )
            }
            .padding(.horizontal, 30)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Page 3: Profile Setup

    private var profileSetupPage: some View {
        VStack(spacing: 25) {
            Spacer()

            Text("Set up your profile")
                .font(.title)
                .fontWeight(.bold)

            Text("Choose how others will see you")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Avatar preview
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [UserProfile.avatarColors[selectedColorIndex],
                                    UserProfile.avatarColors[selectedColorIndex].opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)

                Text(avatarInitials)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.top, 10)

            // Name input
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Name")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Enter your name", text: $userName)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.05), radius: 5)
            }
            .padding(.horizontal, 40)

            // Color picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Avatar Color")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    ForEach(0..<UserProfile.avatarColors.count, id: \.self) { index in
                        Circle()
                            .fill(UserProfile.avatarColors[index])
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: selectedColorIndex == index ? 3 : 0)
                            )
                            .shadow(color: selectedColorIndex == index ? UserProfile.avatarColors[index].opacity(0.5) : .clear, radius: 5)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedColorIndex = index
                                }
                            }
                    }
                }
            }
            .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Helpers

    private var avatarInitials: String {
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "?" }

        let components = name.split(separator: " ")
        if components.count >= 2 {
            let first = components[0].prefix(1)
            let last = components[1].prefix(1)
            return "\(first)\(last)".uppercased()
        } else {
            return String(name.prefix(2)).uppercased()
        }
    }

    private var canComplete: Bool {
        !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func completeOnboarding() {
        userProfile.completeOnboarding(name: userName, colorIndex: selectedColorIndex)
        onComplete()
    }
}

// MARK: - Feature Row Component

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(userProfile: UserProfile.shared) {}
    }
}
