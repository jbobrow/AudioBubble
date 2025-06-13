//
//  UserProfile.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 6/13/25.
//


//
//  UserProfile.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/8/25.
//

import Foundation
import SwiftUI

class UserProfile: ObservableObject {
    @Published var username: String = "" {
        didSet {
            saveUsername()
        }
    }
    
    @Published var hasCompletedOnboarding: Bool = false {
        didSet {
            saveOnboardingStatus()
        }
    }
    
    private let usernameKey = "AudioBubble_Username"
    private let onboardingKey = "AudioBubble_HasCompletedOnboarding"
    
    init() {
        loadProfile()
    }
    
    private func loadProfile() {
        username = UserDefaults.standard.string(forKey: usernameKey) ?? ""
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
    }
    
    private func saveUsername() {
        UserDefaults.standard.set(username, forKey: usernameKey)
    }
    
    private func saveOnboardingStatus() {
        UserDefaults.standard.set(hasCompletedOnboarding, forKey: onboardingKey)
    }
    
    func clearProfile() {
        username = ""
        hasCompletedOnboarding = false
        UserDefaults.standard.removeObject(forKey: usernameKey)
        UserDefaults.standard.removeObject(forKey: onboardingKey)
    }
    
    var isProfileComplete: Bool {
        return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
