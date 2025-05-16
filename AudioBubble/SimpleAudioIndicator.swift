//
//  SimpleAudioIndicator.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/16/25.
//

import SwiftUI

struct SimpleAudioIndicator: View {
    let isActive: Bool
    let level: CGFloat // Single value 0.0 to 1.0
    
    var body: some View {
        Circle()
            .fill(isActive ? Color.green : Color.gray.opacity(0.3))
            .frame(width: 12, height: 12)
            .scaleEffect(isActive ? 1.0 + (level * 0.5) : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isActive)
            .animation(.easeInOut(duration: 0.05), value: level)
    }
}

// Alternative: Simple bar indicator
struct SimpleAudioBar: View {
    let isActive: Bool
    let level: CGFloat
    
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(isActive ? Color.green : Color.gray.opacity(0.3))
            .frame(width: 6, height: isActive ? 8 + (level * 20) : 8)
            .animation(.easeInOut(duration: 0.1), value: isActive)
            .animation(.easeInOut(duration: 0.05), value: level)
    }
}

// Alternative: Waveform-style indicator
struct SimpleWaveIndicator: View {
    let isActive: Bool
    let level: CGFloat
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(isActive ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 3, height: isActive ? 8 + (level * CGFloat(index + 1) * 8) : 8)
            }
        }
        .animation(.easeInOut(duration: 0.1), value: isActive)
        .animation(.easeInOut(duration: 0.05), value: level)
    }
}

// MARK: - Previews

#Preview("Circle Indicator - Inactive") {
    VStack(spacing: 20) {
        SimpleAudioIndicator(isActive: false, level: 0.0)
        SimpleAudioIndicator(isActive: true, level: 0.3)
        SimpleAudioIndicator(isActive: true, level: 0.7)
        SimpleAudioIndicator(isActive: true, level: 1.0)
    }
    .padding()
}

#Preview("Bar Indicator") {
    VStack(spacing: 20) {
        SimpleAudioBar(isActive: false, level: 0.0)
        SimpleAudioBar(isActive: true, level: 0.3)
        SimpleAudioBar(isActive: true, level: 0.7)
        SimpleAudioBar(isActive: true, level: 1.0)
    }
    .padding()
}

#Preview("Wave Indicator") {
    VStack(spacing: 20) {
        SimpleWaveIndicator(isActive: false, level: 0.0)
        SimpleWaveIndicator(isActive: true, level: 0.3)
        SimpleWaveIndicator(isActive: true, level: 0.7)
        SimpleWaveIndicator(isActive: true, level: 1.0)
    }
    .padding()
}
