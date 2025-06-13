//
//  CreateBubbleView.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/8/25.
//

import SwiftUI

struct CreateBubbleView: View {
    @Binding var bubbleName: String
    let onCreate: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                
                Spacer()
                
                // Bubble Icon
                Circle()
                    .fill(.blue.gradient)
                    .frame(width: 100, height: 100)
                    .overlay {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                    }
                
                VStack(spacing: 8) {
                    Text("Create Audio Bubble")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text("Start a new conversation space for you and your friends")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("What's your bubble called?")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    TextField("Enter bubble name", text: $bubbleName)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .onSubmit {
                            if !bubbleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                onCreate()
                            }
                        }
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Big action button at bottom
                VStack(spacing: 16) {
                    Button(action: onCreate) {
                        Text("Create Bubble")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(bubbleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                            .cornerRadius(12)
                    }
                    .disabled(bubbleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.horizontal, 24)
                    
                    Text("Others nearby will be able to discover and join your bubble")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding()
            .navigationTitle("New Bubble")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    CreateBubbleView(bubbleName: .constant("")) {
        print("Create bubble")
    }
}
