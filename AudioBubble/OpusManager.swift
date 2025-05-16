//
//  OpusManager.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/10/25.
//

import Foundation
import AVFoundation
import Opus  // Import for alta/swift-opus

class OpusCodec {
    // Audio configuration
    private let sampleRate = Double.opus48khz  // Use the extension constant for 48kHz
    private let channels: AVAudioChannelCount = 1  // Mono for voice
    private let frameSize: AVAudioFrameCount = 480  // 10ms frame at 48kHz for lower latency
    
    // Opus encoder and decoder
    private var encoder: Opus.Encoder?
    private var decoder: Opus.Decoder?
    
    // Packet loss tracking
    private var packetLossCounter = 0
    private let maxConsecutivePacketLoss = 5
    private var lastGoodData: Data?
    
    // Buffer for encoded data
    private var encodedDataBuffer = Data(capacity: 1500)
    
    init?() {
        do {
            // Create the audio format for PCM audio using the extension provided
            guard let format = AVAudioFormat(
                opusPCMFormat: .float32,
                sampleRate: sampleRate,
                channels: channels
            ) else {
                print("Failed to create audio format")
                return nil
            }
            
            // Create the encoder with the correct format and application
            encoder = try Opus.Encoder(
                format: format,
                application: .voip  // Optimize for voice
            )
            
            // Create the decoder with the same format
            decoder = try Opus.Decoder(
                format: format,
                application: .voip  // Match encoder application
            )
            
            print("Opus codec initialized successfully")
        } catch {
            print("Failed to initialize Opus codec: \(error)")
            return nil
        }
    }
    
    func encode(buffer: AVAudioPCMBuffer) -> Data? {
        guard let encoder = encoder else {
            print("Encoder not initialized")
            return nil
        }
        
        print("Encoding PCM buffer: frameLength=\(buffer.frameLength), format=\(buffer.format)")
        
        do {
            // Reset the encoded data buffer
            encodedDataBuffer.removeAll(keepingCapacity: true)
            
            // Encode the audio buffer directly to our Data buffer using the proper API
            let encodedSize = try encoder.encode(buffer, to: &encodedDataBuffer)
            print("Encoded \(encodedSize) bytes of audio data")
            
            // Return the encoded data
            return encodedDataBuffer
        } catch {
            print("Encoding failed: \(error)")
            return nil
        }
    }
    
    func decode(data: Data?) -> AVAudioPCMBuffer? {
        guard let decoder = decoder else {
            print("Decoder not initialized")
            return nil
        }
        
        if data == nil {
            // Handle packet loss
            packetLossCounter += 1
            print("Packet loss detected (\(packetLossCounter))")
            
            // Create a silent buffer for packet loss
            return createSilentBuffer()
        }
        
        // Reset packet loss counter on successful packet
        packetLossCounter = 0
        
        print("Decoding \(data!.count) bytes of Opus data")
        
        do {
            // Use the proper decode method - it returns a new AVAudioPCMBuffer
            let outputBuffer = try decoder.decode(data!)
            print("Decoded to PCM buffer: frameLength=\(outputBuffer.frameLength), format=\(outputBuffer.format)")
            
            // Save this packet for potential FEC
            lastGoodData = data
            
            return outputBuffer
        } catch {
            print("Decoding failed: \(error)")
            return nil
        }
    }
    
    // Create a silent buffer for packet loss concealment
    private func createSilentBuffer() -> AVAudioPCMBuffer? {
        // Create a format with the same parameters we used for the decoder
        guard let format = AVAudioFormat(
            opusPCMFormat: .float32,
            sampleRate: sampleRate,
            channels: channels
        ) else {
            print("Failed to create audio format")
            return nil
        }
        
        let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameSize
        )
        
        guard let outputBuffer = outputBuffer else {
            return nil
        }
        
        // Set the frame length to match our standard frame size
        outputBuffer.frameLength = frameSize
        
        // Fill with zeros (silence)
        if let floatData = outputBuffer.floatChannelData {
            for channel in 0..<Int(channels) {
                let channelData = floatData[channel]
                for sample in 0..<Int(outputBuffer.frameLength) {
                    channelData[sample] = 0.0
                }
            }
        }
        
        return outputBuffer
    }
}
