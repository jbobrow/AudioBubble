//
//  AudioSettings.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 6/14/25.
//

import Foundation
import SwiftUI

class AudioSettings: ObservableObject {
    
    // Audio Format Options
    enum AudioFormat: String, CaseIterable {
        case rawPCM = "Raw PCM"
        case opus = "Opus Codec"
        case aac = "AAC Codec"
        case compressedPCM = "Compressed PCM"
        
        var description: String {
            switch self {
            case .rawPCM: return "Uncompressed audio (highest quality, most data)"
            case .opus: return "Opus compression (good quality, efficient)"
            case .aac: return "AAC compression (balanced quality/size)"
            case .compressedPCM: return "Simple PCM compression"
            }
        }
    }
    
    // Buffer Size Options
    enum BufferSize: Int, CaseIterable {
        case tiny = 256
        case small = 512
        case medium = 1024
        case large = 2048
        case huge = 4096
        
        var description: String {
            return "\(rawValue) samples (\(latencyDescription))"
        }
        
        var latencyDescription: String {
            let latencyMs = Double(rawValue) / 48000.0 * 1000.0
            return String(format: "~%.1fms", latencyMs)
        }
    }
    
    // Sample Rate Options
    enum SampleRate: Double, CaseIterable {
        case rate16k = 16000
        case rate22k = 22050
        case rate44k = 44100
        case rate48k = 48000
        
        var description: String {
            if rawValue >= 1000 {
                return "\(Int(rawValue / 1000))kHz"
            } else {
                return "\(Int(rawValue))Hz"
            }
        }
    }
    
    // Network Reliability Options
    enum NetworkMode: String, CaseIterable {
        case unreliable = "Unreliable"
        case reliable = "Reliable"
        case mixed = "Mixed"
        
        var description: String {
            switch self {
            case .unreliable: return "Fast, may drop packets"
            case .reliable: return "Guaranteed delivery, slower"
            case .mixed: return "Important data reliable, audio unreliable"
            }
        }
    }
    
    // Published Settings
    @Published var audioFormat: AudioFormat = .rawPCM
    @Published var bufferSize: BufferSize = .medium
    @Published var sampleRate: SampleRate = .rate48k
    @Published var networkMode: NetworkMode = .unreliable
    @Published var enableLogging: Bool = true
    @Published var enableMonitoring: Bool = false
    @Published var monitoringVolume: Double = 0.5
    @Published var outputVolume: Double = 1.0
    @Published var inputGain: Double = 1.0
    
    // Audio Session Options
    @Published var lowLatencyMode: Bool = true
    @Published var noiseReduction: Bool = false
    @Published var echoCancellation: Bool = true
    
    private let settingsKey = "AudioBubble_AudioSettings"
    
    init() {
        loadSettings()
    }
    
    // MARK: - Persistence
    
    private func loadSettings() {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let decoded = try? JSONDecoder().decode(SettingsData.self, from: data) else {
            return
        }
        
        audioFormat = decoded.audioFormat
        bufferSize = decoded.bufferSize
        sampleRate = decoded.sampleRate
        networkMode = decoded.networkMode
        enableLogging = decoded.enableLogging
        enableMonitoring = decoded.enableMonitoring
        monitoringVolume = decoded.monitoringVolume
        outputVolume = decoded.outputVolume
        inputGain = decoded.inputGain
        lowLatencyMode = decoded.lowLatencyMode
        noiseReduction = decoded.noiseReduction
        echoCancellation = decoded.echoCancellation
    }
    
    func saveSettings() {
        let settings = SettingsData(
            audioFormat: audioFormat,
            bufferSize: bufferSize,
            sampleRate: sampleRate,
            networkMode: networkMode,
            enableLogging: enableLogging,
            enableMonitoring: enableMonitoring,
            monitoringVolume: monitoringVolume,
            outputVolume: outputVolume,
            inputGain: inputGain,
            lowLatencyMode: lowLatencyMode,
            noiseReduction: noiseReduction,
            echoCancellation: echoCancellation
        )
        
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: settingsKey)
        }
    }
    
    func resetToDefaults() {
        audioFormat = .rawPCM
        bufferSize = .medium
        sampleRate = .rate48k
        networkMode = .unreliable
        enableLogging = true
        enableMonitoring = false
        monitoringVolume = 0.5
        outputVolume = 1.0
        inputGain = 1.0
        lowLatencyMode = true
        noiseReduction = false
        echoCancellation = true
        saveSettings()
    }
    
    // MARK: - Settings Data Structure
    
    private struct SettingsData: Codable {
        let audioFormat: AudioFormat
        let bufferSize: BufferSize
        let sampleRate: SampleRate
        let networkMode: NetworkMode
        let enableLogging: Bool
        let enableMonitoring: Bool
        let monitoringVolume: Double
        let outputVolume: Double
        let inputGain: Double
        let lowLatencyMode: Bool
        let noiseReduction: Bool
        let echoCancellation: Bool
    }
}

// MARK: - Codable Extensions

extension AudioSettings.AudioFormat: Codable {}
extension AudioSettings.BufferSize: Codable {}
extension AudioSettings.SampleRate: Codable {}
extension AudioSettings.NetworkMode: Codable {}
