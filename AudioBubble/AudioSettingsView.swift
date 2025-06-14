//
//  AudioSettingsView.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 6/14/25.
//

import SwiftUI

struct AudioSettingsView: View {
    @EnvironmentObject var audioSettings: AudioSettings
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Audio Format") {
                    Picker("Codec", selection: $audioSettings.audioFormat) {
                        ForEach(AudioSettings.AudioFormat.allCases, id: \.self) { format in
                            VStack(alignment: .leading) {
                                Text(format.rawValue)
                                Text(format.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(format)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                
                Section("Audio Quality") {
                    Picker("Sample Rate", selection: $audioSettings.sampleRate) {
                        ForEach(AudioSettings.SampleRate.allCases, id: \.self) { rate in
                            Text(rate.description).tag(rate)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Picker("Buffer Size", selection: $audioSettings.bufferSize) {
                        ForEach(AudioSettings.BufferSize.allCases, id: \.self) { size in
                            Text(size.description).tag(size)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                
                Section("Network") {
                    Picker("Transmission Mode", selection: $audioSettings.networkMode) {
                        ForEach(AudioSettings.NetworkMode.allCases, id: \.self) { mode in
                            VStack(alignment: .leading) {
                                Text(mode.rawValue)
                                Text(mode.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(mode)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                
                Section("Audio Levels") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Input Gain: \(audioSettings.inputGain, specifier: "%.1f")")
                        Slider(value: $audioSettings.inputGain, in: 0.1...3.0, step: 0.1)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Output Volume: \(audioSettings.outputVolume, specifier: "%.1f")")
                        Slider(value: $audioSettings.outputVolume, in: 0.0...2.0, step: 0.1)
                    }
                    
                    Toggle("Enable Monitoring", isOn: $audioSettings.enableMonitoring)
                    
                    if audioSettings.enableMonitoring {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Monitor Volume: \(audioSettings.monitoringVolume, specifier: "%.1f")")
                            Slider(value: $audioSettings.monitoringVolume, in: 0.0...1.0, step: 0.1)
                        }
                    }
                }
                
                Section("Audio Processing") {
                    Toggle("Low Latency Mode", isOn: $audioSettings.lowLatencyMode)
                    Toggle("Echo Cancellation", isOn: $audioSettings.echoCancellation)
                    Toggle("Noise Reduction", isOn: $audioSettings.noiseReduction)
                }
                
                Section("Debug") {
                    Toggle("Enable Audio Logging", isOn: $audioSettings.enableLogging)
                    
                    Button("Reset to Defaults") {
                        audioSettings.resetToDefaults()
                    }
                    .foregroundColor(.red)
                }
                
                Section("Current Configuration") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Format: \(audioSettings.audioFormat.rawValue)")
                        Text("Quality: \(audioSettings.sampleRate.description) @ \(audioSettings.bufferSize.description)")
                        Text("Network: \(audioSettings.networkMode.rawValue)")
                        Text("Latency: \(audioSettings.lowLatencyMode ? "Low" : "Normal")")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Audio Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        audioSettings.saveSettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    AudioSettingsView()
        .environmentObject(AudioSettings())
}
