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
