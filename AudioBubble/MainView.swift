//
//  MainView.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/8/25.
//

import SwiftUI

struct MainView: View {
    let username: String
    @StateObject private var sessionManager: BubbleSessionManager
    @State private var bubbleName = ""
    @State private var showingCreateBubble = false
    
    init(username: String) {
        self.username = username
        _sessionManager = StateObject(wrappedValue: BubbleSessionManager(username: username))
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if !sessionManager.isHeadphonesConnected {
                    HeadphoneWarningView()
                }
                
                if let currentBubble = sessionManager.currentBubble {
                    BubbleDetailView(
                        bubble: currentBubble,
                        isHost: sessionManager.isHost,
                        onLeave: { sessionManager.leaveBubble() },
                        sessionManager: sessionManager
                    )
                } else {
                    // Available bubbles list
                    List {
                        Section(header: Text("Available Bubbles")) {
                            if sessionManager.availableBubbles.isEmpty {
                                Text("No bubbles found nearby")
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(sessionManager.availableBubbles) { bubble in
                                    BubbleRowView(bubble: bubble) {
                                        sessionManager.joinBubble(bubble)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                }
            }
            .navigationTitle("Audio Bubble")
            .toolbar {
                if sessionManager.currentBubble == nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            showingCreateBubble = true
                        }) {
                            Label("Create", systemImage: "plus")
                        }
                        .disabled(!sessionManager.isHeadphonesConnected)
                    }
                }
            }
            .sheet(isPresented: $showingCreateBubble) {
                CreateBubbleView(bubbleName: $bubbleName) {
                    sessionManager.createBubble(name: bubbleName)
                    showingCreateBubble = false
                    bubbleName = ""
                }
            }
            .alert(item: Binding<AlertItem?>(
                get: {
                    sessionManager.errorMessage.map { AlertItem(message: $0) }
                },
                set: { _ in
                    sessionManager.errorMessage = nil
                }
            )) { alertItem in
                Alert(title: Text("Error"), message: Text(alertItem.message))
            }
            .onAppear {
                sessionManager.setupSession()
            }
        }
    }
}
