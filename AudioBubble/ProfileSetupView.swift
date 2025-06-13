//
//  ProfileSetupView.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/8/25.
//

import SwiftUI

struct ProfileSetupView: View {
    @EnvironmentObject var userProfile: UserProfile
    @State private var tempUsername: String = ""
    @State private var isUsernameValid = false
    @Environment(\.dismiss) private var dismiss
    
    let isEditing: Bool
    
    init(isEditing: Bool = false) {
        self.isEditing = isEditing
    }
    
    var body: some View {
        VStack(spacing: 32) {
            
            if !isEditing {
                Spacer()
                
                // App Icon/Logo placeholder
                Circle()
                    .fill(.blue.gradient)
                    .frame(width: 100, height: 100)
                    .overlay {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                    }
                
                VStack(spacing: 8) {
                    Text("Welcome to AudioBubble")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text("Connect with friends through spatial audio conversations")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isEditing ? "Update Your Name" : "What should we call you?")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    TextField("Enter your name", text: $tempUsername)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .onSubmit {
                            saveProfile()
                        }
                        .onChange(of: tempUsername) { _, newValue in
                            validateUsername(newValue)
                        }
                    
                    if !isUsernameValid && !tempUsername.isEmpty {
                        Text("Name must be at least 2 characters")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                Button(action: saveProfile) {
                    Text(isEditing ? "Save Changes" : "Get Started")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isUsernameValid ? .blue : .gray)
                        .cornerRadius(12)
                }
                .disabled(!isUsernameValid)
                
                if isEditing {
                    Button(action: {
                        userProfile.clearProfile()
                        dismiss()
                    }) {
                        Text("Clear Profile")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 24)
            
            if !isEditing {
                Spacer()
                
                Text("Your name will be visible to other users in bubbles")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
        .onAppear {
            tempUsername = userProfile.username
            validateUsername(tempUsername)
        }
    }
    
    private func validateUsername(_ username: String) {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        isUsernameValid = trimmed.count >= 2
    }
    
    private func saveProfile() {
        guard isUsernameValid else { return }
        
        let trimmed = tempUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        userProfile.username = trimmed
        userProfile.hasCompletedOnboarding = true
        
        if isEditing {
            dismiss()
        }
    }
}

#Preview("First Time Setup") {
    ProfileSetupView()
        .environmentObject(UserProfile())
}

#Preview("Editing Profile") {
    ProfileSetupView(isEditing: true)
        .environmentObject({
            let profile = UserProfile()
            profile.username = "John Doe"
            return profile
        }())
}
