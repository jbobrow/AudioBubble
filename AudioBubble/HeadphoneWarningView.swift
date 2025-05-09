//
//  HeadphoneWarningView.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/8/25.
//

import SwiftUI

struct HeadphoneWarningView: View {
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Please connect headphones to participate")
                    .font(.headline)
                    .foregroundColor(.orange)
            }
            .padding()
            .background(Color.orange.opacity(0.2))
            .cornerRadius(10)
        }
        .padding(.horizontal)
    }
}

// MARK: - HeadphoneWarningView Previews

#Preview("Headphone Warning", traits: .sizeThatFitsLayout) {
    HeadphoneWarningView()
        .padding()
}
