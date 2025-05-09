//
//  AudioLevelMeterView.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/8/25.
//

import SwiftUI
import AVFoundation

struct AudioLevelMeterView: View {
    let levels: [CGFloat] // Values between 0.0 and 1.0
    let isActive: Bool
    
    // Default initialization with inactive state
    init(levels: [CGFloat] = [0, 0, 0, 0, 0], isActive: Bool = false) {
        self.levels = levels
        self.isActive = isActive
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .frame(width: 4, height: isActive ? 10 + levels[index] * 30 : 0)
                    .foregroundColor(.blue)
            }
        }
        .frame(height: 40, alignment: .center) // Fixed height container, vertically centered
        .animation(.spring(response: 0.3), value: levels)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}

// MARK: - AudioLevelMeterView Previews

#Preview("Inactive", traits: .sizeThatFitsLayout) {
    AudioLevelMeterView(isActive: false)
        .padding()
}

#Preview("Active - Low", traits: .sizeThatFitsLayout) {
    AudioLevelMeterView(
        levels: [0.1, 0.2, 0.15, 0.2, 0.1],
        isActive: true
    )
    .padding()
}

#Preview("Active - Medium", traits: .sizeThatFitsLayout) {
    AudioLevelMeterView(
        levels: [0.4, 0.5, 0.6, 0.5, 0.4],
        isActive: true
    )
    .padding()
}

#Preview("Active - High", traits: .sizeThatFitsLayout) {
    AudioLevelMeterView(
        levels: [0.7, 0.8, 0.9, 0.8, 0.7],
        isActive: true
    )
    .padding()
}
