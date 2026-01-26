import Foundation
import Combine
import SwiftUI

/// Manages the current user's profile with persistent storage
final class UserProfile: ObservableObject {
    static let shared = UserProfile()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let displayName = "userDisplayName"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let avatarColorIndex = "avatarColorIndex"
    }

    /// User's chosen display name
    @Published var displayName: String {
        didSet {
            defaults.set(displayName, forKey: Keys.displayName)
        }
    }

    /// Whether the user has completed onboarding
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        }
    }

    /// Index into the avatar color palette
    @Published var avatarColorIndex: Int {
        didSet {
            defaults.set(avatarColorIndex, forKey: Keys.avatarColorIndex)
        }
    }

    /// Available avatar colors
    static let avatarColors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .cyan, .mint, .indigo, .teal, .red
    ]

    /// Current avatar color
    var avatarColor: Color {
        Self.avatarColors[avatarColorIndex % Self.avatarColors.count]
    }

    private init() {
        // Load from UserDefaults or use defaults
        self.displayName = defaults.string(forKey: Keys.displayName) ?? ""
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        self.avatarColorIndex = defaults.integer(forKey: Keys.avatarColorIndex)
    }

    /// Complete onboarding with the given name
    func completeOnboarding(name: String, colorIndex: Int) {
        self.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.avatarColorIndex = colorIndex
        self.hasCompletedOnboarding = true
    }

    /// Reset profile (for testing)
    func reset() {
        displayName = ""
        hasCompletedOnboarding = false
        avatarColorIndex = 0
    }
}
