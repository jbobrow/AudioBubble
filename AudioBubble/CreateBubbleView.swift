//
//  CreateBubbleView.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/8/25.
//

import SwiftUI

struct CreateBubbleView: View {
    @Binding var bubbleName: String
    @Environment(\.presentationMode) var presentationMode
    var onCreate: () -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Bubble Details")) {
                    TextField("Bubble Name", text: $bubbleName)
                }
                
                Section {
                    Button("Create Bubble") {
                        onCreate()
                    }
                    .disabled(bubbleName.isEmpty)
                }
            }
            .navigationTitle("Create Bubble")
            .navigationBarItems(trailing: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}
