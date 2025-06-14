import Foundation
import AVFoundation
import MultipeerConnectivity
import Combine

protocol AudioManagerDelegate: AnyObject {
    func audioManager(_ manager: AudioManager, didCaptureAudioData data: Data)
}

class AudioManager: NSObject, ObservableObject {
    @Published var isHeadphonesConnected = false
    @Published var isMonitoringEnabled = false
    
    weak var audioDelegate: AudioManagerDelegate?
    
    private let audioSession = AVAudioSession.sharedInstance()
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var playerNodes: [String: AVAudioPlayerNode] = [:]
    private var monitorMixer: AVAudioMixerNode?
    
    // Settings
    private var audioSettings: AudioSettings?
    
    // Simple audio data tracking
    class ParticipantAudioData: ObservableObject {
        @Published var isActive: Bool = false
        @Published var level: CGFloat = 0.0
        
        private var isPreviewMode = false
        
        func updateWithBuffer(_ buffer: AVAudioPCMBuffer) {
            guard !isPreviewMode else { return }
            
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }
            
            var sum: Float = 0
            for i in 0..<frameLength {
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frameLength))
            
            DispatchQueue.main.async {
                self.isActive = rms > 0.01  // Simple threshold
                self.level = min(CGFloat(rms * 10), 1.0)  // Simple scaling
            }
        }
        
        func simulateActivity(active: Bool, level: CGFloat = 0.7) {
            isPreviewMode = true
            DispatchQueue.main.async {
                self.isActive = active
                self.level = active ? level : 0.0
            }
        }
    }
    
    private var participantAudioData: [String: ParticipantAudioData] = [:]
    private let localAudioData = ParticipantAudioData()
    
    override init() {
        super.init()
        checkHeadphones()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioRouteChanged),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    func getAudioDataForPeer(_ peerKey: String) -> ParticipantAudioData {
        if peerKey == "local" {
            return localAudioData
        }
        
        if let existing = participantAudioData[peerKey] {
            return existing
        }
        
        let newData = ParticipantAudioData()
        participantAudioData[peerKey] = newData
        return newData
    }
    
    // MARK: - Simple Audio Engine
    
    func startAudioEngine() {
        print("Starting simple audio engine...")
        
        setupAudioSession()
        setupSimpleAudioEngine()
    }
    
    func stopAudioEngine() {
        print("Stopping audio engine...")
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        monitorMixer = nil
        playerNodes.removeAll()
    }
    
    private func setupAudioSession() {
        do {
            // Simplest possible audio session setup with low latency
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
            try audioSession.setPreferredSampleRate(48000)
            try audioSession.setPreferredIOBufferDuration(0.005) // Very low latency for monitoring
            try audioSession.setActive(true)
            print("Simple audio session configured: \(audioSession.sampleRate)Hz, Buffer: \(audioSession.ioBufferDuration)s")
        } catch {
            print("Audio session error: \(error)")
        }
    }
    
    private func setupSimpleAudioEngine() {
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }
        
        inputNode = audioEngine.inputNode
        guard let inputNode = inputNode else { return }
        
        // Create a mixer for monitoring
        monitorMixer = AVAudioMixerNode()
        guard let monitorMixer = monitorMixer else { return }
        audioEngine.attach(monitorMixer)
        
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Connect input to main mixer for monitoring
        audioEngine.connect(inputNode, to: monitorMixer, format: inputFormat)
        audioEngine.connect(monitorMixer, to: audioEngine.mainMixerNode, format: inputFormat)
        
        // Set initial monitoring volume (muted by default)
        monitorMixer.outputVolume = isMonitoringEnabled ? 0.5 : 0.0
        
        // Install the simplest possible tap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        
        do {
            try audioEngine.start()
            print("Simple audio engine started")
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Update local audio data
        localAudioData.updateWithBuffer(buffer)
        
        // Convert to simplest possible data format
        guard let data = bufferToData(buffer) else { return }
        
        print("Sending audio data: \(data.count) bytes")
        
        // Send immediately
        audioDelegate?.audioManager(self, didCaptureAudioData: data)
    }
    
    // MARK: - Receive Audio
    
    func processIncomingAudio(_ data: Data, fromPeer peerID: String) {
        print("Received audio data from \(peerID): \(data.count) bytes")
        
        guard let buffer = dataToBuffer(data) else {
            print("Failed to convert data to buffer for \(peerID)")
            return
        }
        
        // Update peer audio data
        let peerAudioData = getAudioDataForPeer(peerID)
        peerAudioData.updateWithBuffer(buffer)
        
        // Play immediately
        playAudioBuffer(buffer, forPeer: peerID)
    }
    
    private func playAudioBuffer(_ buffer: AVAudioPCMBuffer, forPeer peerID: String) {
        guard let audioEngine = audioEngine, audioEngine.isRunning else {
            print("Audio engine not running for \(peerID)")
            return
        }
        
        let playerNode: AVAudioPlayerNode
        if let existingNode = playerNodes[peerID] {
            playerNode = existingNode
        } else {
            print("Creating new player node for \(peerID)")
            playerNode = AVAudioPlayerNode()
            audioEngine.attach(playerNode)
            
            // Use buffer's native format to avoid conversion
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: buffer.format)
            playerNodes[peerID] = playerNode
            
            playerNode.play()
            print("Started player node for \(peerID)")
        }
        
        // Schedule the buffer
        if playerNode.isPlaying {
            playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            print("Scheduled buffer for \(peerID): \(buffer.frameLength) frames")
        } else {
            print("Player node not playing for \(peerID)")
        }
    }
    
    // MARK: - Simple Data Conversion
    
    private func bufferToData(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.floatChannelData?[0] else { return nil }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }
        
        // Just send the raw float data
        let audioData = Data(bytes: channelData, count: frameLength * MemoryLayout<Float>.size)
        return audioData
    }
    
    private func dataToBuffer(_ data: Data) -> AVAudioPCMBuffer? {
        let frameCount = data.count / MemoryLayout<Float>.size
        guard frameCount > 0 else { return nil }
        
        // Use a standard format - 48kHz, 1 channel
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        
        buffer.frameLength = AVAudioFrameCount(frameCount)
        
        // Copy the data directly
        data.withUnsafeBytes { bytes in
            let floatBytes = bytes.bindMemory(to: Float.self)
            buffer.floatChannelData?[0].update(from: floatBytes.baseAddress!, count: frameCount)
        }
        
        return buffer
    }
    
    // MARK: - Settings
    
    func updateSettings(_ settings: AudioSettings) {
        self.audioSettings = settings
        
        // Apply monitoring settings immediately
        isMonitoringEnabled = settings.enableMonitoring
        if let monitorMixer = monitorMixer {
            monitorMixer.outputVolume = settings.enableMonitoring ? Float(settings.monitoringVolume) : 0.0
        }
        
        if audioSettings?.enableLogging == true {
            print("Audio settings updated: \(settings.audioFormat.rawValue), \(settings.sampleRate.description), \(settings.bufferSize.description)")
        }
    }
    
    // MARK: - Monitoring & Cleanup
    
    func toggleMonitoring(enabled: Bool) {
        isMonitoringEnabled = enabled
        
        // Update settings if available
        audioSettings?.enableMonitoring = enabled
        audioSettings?.saveSettings()
        
        // Adjust the monitoring volume
        if let monitorMixer = monitorMixer {
            let volume = enabled ? Float(audioSettings?.monitoringVolume ?? 0.5) : 0.0
            monitorMixer.outputVolume = volume
        }
        
        if audioSettings?.enableLogging == true {
            print("Monitoring \(enabled ? "enabled" : "disabled")")
        }
    }
    
    func cleanupPeer(_ peerID: String) {
        playerNodes[peerID]?.stop()
        playerNodes.removeValue(forKey: peerID)
        participantAudioData.removeValue(forKey: peerID)
    }
    
    @objc private func audioRouteChanged() {
        checkHeadphones()
    }
    
    private func checkHeadphones() {
        let outputs = audioSession.currentRoute.outputs
        let hasHeadphones = outputs.contains { output in
            [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains(output.portType)
        }
        
        DispatchQueue.main.async {
            self.isHeadphonesConnected = hasHeadphones
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopAudioEngine()
    }
}
