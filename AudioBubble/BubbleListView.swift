//
//  BubbleListView.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/8/25.
//

import SwiftUI
import MultipeerConnectivity

struct BubbleListView: View {
    @EnvironmentObject var sessionManager: BubbleSessionManager
    @EnvironmentObject var userProfile: UserProfile
    @StateObject private var audioSettings = AudioSettings()
    @State private var showingCreateBubble = false
    @State private var showingProfile = false
    @State private var showingAudioSettings = false
    @State private var newBubbleName = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Profile
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Audio Bubbles")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Welcome, \(userProfile.username)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 16) {
                        Button(action: {
                            showingAudioSettings = true
                        }) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                        
                        Button(action: {
                            showingProfile = true
                        }) {
                            Image(systemName: "person.circle")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                if !sessionManager.isHeadphonesConnected {
                    HStack {
                        Image(systemName: "headphones")
                            .foregroundColor(.orange)
                        Text("Connect headphones to create or join bubbles")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                    .padding()
                    .background(.orange.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding()
            
            // Available Bubbles
            List {
                Section("Available Bubbles") {
                    if sessionManager.availableBubbles.isEmpty {
                        Text("No bubbles nearby")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(sessionManager.availableBubbles, id: \.id) { bubble in
                            BubbleRowView(bubble: bubble) {
                                sessionManager.joinBubble(bubble)
                            }
                        }
                    }
                }
            }
            .listStyle(PlainListStyle())
            
            // Create Bubble Button
            VStack(spacing: 16) {
                Button(action: {
                    showingCreateBubble = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Create New Bubble")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(sessionManager.isHeadphonesConnected ? .blue : .gray)
                    .cornerRadius(12)
                }
                .disabled(!sessionManager.isHeadphonesConnected)
                .padding(.horizontal)
                
                if let errorMessage = sessionManager.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
            }
            .padding(.bottom)
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingAudioSettings) {
            AudioSettingsView()
                .environmentObject(audioSettings)
        }
        .sheet(isPresented: $showingProfile) {
            NavigationView {
                ProfileSetupView(isEditing: true)
                    .environmentObject(userProfile)
                    .navigationTitle("Edit Profile")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingProfile = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingCreateBubble) {
            CreateBubbleView(bubbleName: $newBubbleName) {
                sessionManager.createBubble(name: newBubbleName)
                showingCreateBubble = false
                newBubbleName = ""
            }
        }
        .onAppear {
            sessionManager.setupSession()
            sessionManager.updateAudioSettings(audioSettings)
        }
        .fullScreenCover(item: $sessionManager.currentBubble) { bubble in
            BubbleDetailView(
                bubble: bubble,
                isHost: sessionManager.isHost,
                onLeave: {
                    sessionManager.leaveBubble()
                },
                sessionManager: sessionManager
            )
        }
    }
}

#Preview {
    NavigationView {
        BubbleListView()
            .environmentObject(MockBubbleSessionManager())
    }
}
