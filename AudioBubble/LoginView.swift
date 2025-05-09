//
//  LoginView.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/8/25.
//

import SwiftUI

struct LoginView: View {
    @Binding var username: String
    var onLogin: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Audio Bubble")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Connect with nearby friends using audio bubbles")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            TextField("Your Name", text: $username)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            Button("Join") {
                if !username.isEmpty {
                    onLogin()
                }
            }
            .disabled(username.isEmpty)
            .padding()
            .background(username.isEmpty ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .padding()
    }
}

// MARK: - LoginView Previews

#Preview {
    LoginView(username: .constant("User123"), onLogin: {})
}

#Preview("Empty Username") {
    LoginView(username: .constant(""), onLogin: {})
}
