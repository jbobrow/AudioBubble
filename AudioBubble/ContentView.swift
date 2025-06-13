//
//  ContentView.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/8/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var userProfile = UserProfile()
    @State private var sessionManager: BubbleSessionManager?
    @State private var showingProfileSetup = false
    
    var body: some View {
        Group {
            if userProfile.isProfileComplete {
                if let manager = sessionManager {
                    BubbleListView()
                        .environmentObject(manager)
                        .environmentObject(userProfile)
                } else {
                    ProgressView("Initializing...")
                        .onAppear {
                            setupSessionManager()
                        }
                }
            } else {
                ProfileSetupView()
                    .environmentObject(userProfile)
                    .onAppear {
                        showingProfileSetup = false
                    }
            }
        }
        .sheet(isPresented: $showingProfileSetup) {
            NavigationView {
                ProfileSetupView(isEditing: true)
                    .environmentObject(userProfile)
                    .navigationTitle("Edit Profile")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingProfileSetup = false
                            }
                        }
                    }
            }
        }
        .onChange(of: userProfile.isProfileComplete) { _, isComplete in
            if isComplete && sessionManager == nil {
                setupSessionManager()
            } else if !isComplete {
                sessionManager = nil
            }
        }
    }
    
    private func setupSessionManager() {
        sessionManager = BubbleSessionManager(username: userProfile.username)
        sessionManager?.setupSession()
    }
}

#Preview {
    ContentView()
}
