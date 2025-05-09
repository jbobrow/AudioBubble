//
//  ContentView.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/8/25.
//

import SwiftUI

struct ContentView: View {
    @State private var username = ""
    @State private var isLoggedIn = false
    
    var body: some View {
        if isLoggedIn {
            MainView(username: username)
        } else {
            LoginView(username: $username, onLogin: {
                isLoggedIn = true
            })
        }
    }
}

// MARK: - ContentView Previews

#Preview("Light Mode") {
    ContentView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    ContentView()
        .preferredColorScheme(.dark)
}
