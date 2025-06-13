//
//  OpusManager.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/10/25.
//

import Foundation
import AVFoundation

class OpusCodec {
    // Audio configuration for iOS-native compression
    private let sampleRate: Double = 48000
    private let channels: AVAudioChannelCount = 1
    private let frameSize: AVAudioFrameCount = 480 // 10ms frame at 48kHz
    
    // Use iOS native audio compression instead of Opus
    private var compressionFormat: AVAudioFormat?
    
    init?() {
        // Create compressed audio format using iOS native codec
        guard AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: channels
        ) != nil else {
            print("Failed to create audio format")
            return nil
        }
        
        // Store the format for later use
        self.compressionFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: channels
        )
        print("Native audio codec initialized successfully")
    }
    
    func encode(buffer: AVAudioPCMBuffer) -> Data? {
        guard let format = compressionFormat else {
            print("Compression format not available")
            return nil
        }
        
        // Convert PCM buffer to Data using simple serialization
        // This is a temporary solution - for production you'd want proper compression
        return serializePCMBuffer(buffer)
    }
    
    func decode(data: Data?) -> AVAudioPCMBuffer? {
        guard let data = data else {
            // Handle packet loss with silence
            return createSilentBuffer()
        }
        
        // Deserialize data back to PCM buffer
        return deserializeToPCMBuffer(data)
    }
    
    // MARK: - Helper Methods
    
    private func serializePCMBuffer(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let floatData = buffer.floatChannelData?[0] else { return nil }
        
        let frameCount = Int(buffer.frameLength)
        let dataSize = frameCount * MemoryLayout<Float>.size
        
        var data = Data(capacity: dataSize + 8) // 8 bytes for header
        
        // Add header with frame count and sample rate
        withUnsafeBytes(of: buffer.frameLength) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: Float(buffer.format.sampleRate)) { data.append(contentsOf: $0) }
        
        // Add audio data
        let audioDataPointer = UnsafeRawPointer(floatData)
        let audioBytes = audioDataPointer.assumingMemoryBound(to: UInt8.self)
        data.append(audioBytes, count: dataSize)
        
        return data
    }
    
    private func deserializeToPCMBuffer(_ data: Data) -> AVAudioPCMBuffer? {
        guard data.count >= 8 else { return nil }
        
        // Read header
        let frameLength = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: AVAudioFrameCount.self) }
        let sampleRate = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: Float.self) }
        
        // Create format and buffer
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
            return nil
        }
        
        buffer.frameLength = frameLength
        
        // Copy audio data
        guard let floatData = buffer.floatChannelData?[0] else { return nil }
        
        let audioDataStart = 8
        let audioDataSize = Int(frameLength) * MemoryLayout<Float>.size
        
        guard data.count >= audioDataStart + audioDataSize else { return nil }
        
        data.withUnsafeBytes { bytes in
            let audioBytes = bytes.bindMemory(to: Float.self)
            let audioStart = audioDataStart / MemoryLayout<Float>.size
            for i in 0..<Int(frameLength) {
                floatData[i] = audioBytes[audioStart + i]
            }
        }
        
        return buffer
    }
    
    private func createSilentBuffer() -> AVAudioPCMBuffer? {
        guard let format = compressionFormat,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameSize) else {
            return nil
        }
        
        buffer.frameLength = frameSize
        
        // Fill with silence
        if let floatData = buffer.floatChannelData?[0] {
            for i in 0..<Int(frameSize) {
                floatData[i] = 0.0
            }
        }
        
        return buffer
    }
}
