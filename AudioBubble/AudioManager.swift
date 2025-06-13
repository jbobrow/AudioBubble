//
//  AudioManager.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/8/25.
//

import Foundation
import AVFoundation
import Combine

protocol AudioManagerDelegate: AnyObject {
    func audioManager(_ manager: AudioManager, didCaptureAudioData data: Data)
}

class AudioManager: ObservableObject {
    // Published properties
    @Published var isHeadphonesConnected = false
    @Published var isMonitoringEnabled = false
    
    // Audio components
    private var audioSession: AVAudioSession = .sharedInstance()
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var remoteAudioMixer: AVAudioMixerNode?
    private var opusCodec: OpusCodec?
    private var cancellables = Set<AnyCancellable>()
    private var peerPlayerNodes: [String: AVAudioPlayerNode] = [:]
    
    // Audio level tracking
    private var localAudioData = ParticipantAudioData()
    private var remoteAudioData: [String: ParticipantAudioData] = [:]
    
    // Delegate for sending audio data
    weak var audioDelegate: AudioManagerDelegate?
    
    // Each participant will have their own audio level data
    public class ParticipantAudioData: ObservableObject {
        @Published var level: CGFloat = 0.0
        @Published var isActive: Bool = false
        private var threshold: Float = 0.01
        private var smoothingFactor: CGFloat = 0.3
        private var isPreviewMode = false
        
        public func updateWithBuffer(_ buffer: AVAudioPCMBuffer) {
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
            
            // Ensure rms is not NaN or infinite
            guard rms.isFinite && !rms.isNaN else { return }
            
            let newIsActive = rms > threshold
            let normalizedLevel = min(max(rms * 20, 0.0), 1.0)
            
            // Ensure normalizedLevel is valid
            guard normalizedLevel.isFinite && !normalizedLevel.isNaN else { return }
            
            DispatchQueue.main.async {
                self.isActive = newIsActive
                
                if newIsActive {
                    let newLevel = self.level * (1 - self.smoothingFactor) + CGFloat(normalizedLevel) * self.smoothingFactor
                    // Ensure final level is valid
                    if newLevel.isFinite && !newLevel.isNaN {
                        self.level = newLevel
                    }
                } else {
                    let newLevel = max(self.level * 0.8, 0.0)
                    if newLevel.isFinite && !newLevel.isNaN {
                        self.level = newLevel
                    }
                }
            }
        }
        
        public func simulateActivity(active: Bool, level: CGFloat = 0.7) {
            isPreviewMode = true
            
            // Validate level input
            let validLevel = max(0.0, min(1.0, level))
            guard validLevel.isFinite && !validLevel.isNaN else { return }
            
            DispatchQueue.main.async {
                self.isActive = active
                self.level = active ? validLevel : 0.0
            }
        }
    }
    
    init() {
        setupAudioSession()
        monitorHeadphonesConnection()
    }
    
    // MARK: - Public Methods
    
    func getAudioDataForPeer(_ peerID: String) -> ParticipantAudioData {
        if peerID == "local" {
            return localAudioData
        } else if let data = remoteAudioData[peerID] {
            return data
        } else {
            let newData = ParticipantAudioData()
            remoteAudioData[peerID] = newData
            return newData
        }
    }
    
    func startAudioEngine() {
        setupAudioEngine()
    }
    
    func stopAudioEngine() {
        cleanupAudioEngine()
    }
    
    func toggleMonitoring(enabled: Bool) {
        isMonitoringEnabled = enabled
        updateMonitoringConnections()
    }
    
    func processIncomingAudio(_ data: Data, fromPeer peerID: String) {
        receiveAudioData(data, fromPeer: peerID)
    }
    
    func cleanupPeer(_ peerID: String) {
        if let playerNode = peerPlayerNodes[peerID] {
            playerNode.stop()
            audioEngine?.detach(playerNode)
            peerPlayerNodes.removeValue(forKey: peerID)
        }
        remoteAudioData.removeValue(forKey: peerID)
    }
    
    // MARK: - Private Methods
    
    private func setupAudioSession() {
        opusCodec = OpusCodec()
        if opusCodec == nil {
            print("Warning: Could not initialize audio codec")
        }
        
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
            )
            // Use the lowest possible latency settings
            try audioSession.setPreferredSampleRate(48000)
            try audioSession.setPreferredIOBufferDuration(0.005) // 5ms for ultra-low latency
            try audioSession.setActive(true, options: [])
            print("Audio session configured: SR=\(audioSession.sampleRate), Buffer=\(audioSession.ioBufferDuration)")
        } catch {
            print("Audio session error: \(error)")
        }
    }
    
    private func monitorHeadphonesConnection() {
        checkHeadphonesConnection()
        
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] _ in
                self?.checkHeadphonesConnection()
            }
            .store(in: &cancellables)
    }
    
    private func checkHeadphonesConnection() {
        let currentRoute = audioSession.currentRoute
        isHeadphonesConnected = currentRoute.outputs.contains {
            $0.portType == .headphones ||
            $0.portType == .bluetoothA2DP ||
            $0.portType == .bluetoothHFP
        }
    }
    
    private func setupAudioEngine() {
        print("Setting up audio engine...")
        
        cleanupAudioEngine()
        
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            print("Failed to create audio engine")
            return
        }
        
        inputNode = audioEngine.inputNode
        let mainMixer = audioEngine.mainMixerNode
        
        guard let inputNode = inputNode else {
            print("Failed to get input node")
            return
        }
        
        remoteAudioMixer = AVAudioMixerNode()
        guard let remoteAudioMixer = remoteAudioMixer else {
            print("Failed to create remote audio mixer")
            return
        }
        
        audioEngine.attach(remoteAudioMixer)
        
        // Use hardware sample rate for best performance
        let hardwareSampleRate = audioSession.sampleRate
        guard let processingFormat = AVAudioFormat(
            standardFormatWithSampleRate: hardwareSampleRate,
            channels: 1
        ) else {
            print("Failed to create processing format")
            return
        }
        
        audioEngine.connect(remoteAudioMixer, to: mainMixer, format: processingFormat)
        
        // Use very small buffer for minimum latency
        let inputFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 256, format: inputFormat) { [weak self] buffer, time in
            self?.processAndSendAudioBuffer(buffer, with: processingFormat)
        }
        
        updateMonitoringConnections()
        prepareAndStartEngine()
    }
    
    private func prepareAndStartEngine() {
        guard let audioEngine = audioEngine else { return }
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
            print("Audio engine started successfully")
        } catch {
            print("Failed to start audio engine: \(error)")
            recoverAudioEngine()
        }
    }
    
    private func recoverAudioEngine() {
        do {
            try audioSession.setActive(false)
            try audioSession.setActive(true)
            audioEngine?.prepare()
            try audioEngine?.start()
            print("Audio engine recovered")
        } catch {
            print("Audio system unavailable: \(error)")
        }
    }
    
    private func cleanupAudioEngine() {
        print("Cleaning up audio engine...")
        
        for (_, playerNode) in peerPlayerNodes {
            playerNode.stop()
        }
        
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine?.reset()
        
        for (_, playerNode) in peerPlayerNodes {
            audioEngine?.detach(playerNode)
        }
        
        peerPlayerNodes.removeAll()
        
        if let remoteAudioMixer = remoteAudioMixer {
            audioEngine?.detach(remoteAudioMixer)
        }
        
        audioEngine = nil
        inputNode = nil
        remoteAudioMixer = nil
        
        print("Audio engine cleaned up")
    }
    
    private func processAndSendAudioBuffer(_ buffer: AVAudioPCMBuffer, with format: AVAudioFormat) {
        localAudioData.updateWithBuffer(buffer)
        
        let bufferToEncode = convertBufferIfNeeded(buffer, to: format) ?? buffer
        
        guard let encodedData = opusCodec?.encode(buffer: bufferToEncode) else {
            return
        }
        
        var dataPacket = Data()
        // Use a simple incrementing counter instead of timestamp to avoid overflow
        let seqNumber = UInt32(Int(Date().timeIntervalSince1970) % Int(UInt32.max))
        withUnsafeBytes(of: seqNumber) { seqBytes in
            dataPacket.append(contentsOf: seqBytes)
        }
        dataPacket.append(encodedData)
        
        audioDelegate?.audioManager(self, didCaptureAudioData: dataPacket)
    }
    
    private func receiveAudioData(_ data: Data, fromPeer peerID: String) {
        guard let audioEngine = audioEngine,
              let remoteAudioMixer = remoteAudioMixer else { return }
        
        guard data.count > 4 else { return }
        
        let opusData = data.subdata(in: 4..<data.count)
        
        guard let decodedBuffer = opusCodec?.decode(data: opusData) else {
            return
        }
        
        let peerAudioData = getAudioDataForPeer(peerID)
        peerAudioData.updateWithBuffer(decodedBuffer)
        
        let hardwareSampleRate = audioSession.sampleRate
        guard let processingFormat = AVAudioFormat(
            standardFormatWithSampleRate: hardwareSampleRate,
            channels: 1
        ) else { return }
        
        let playerNode: AVAudioPlayerNode
        if let existingNode = peerPlayerNodes[peerID] {
            playerNode = existingNode
        } else {
            playerNode = AVAudioPlayerNode()
            audioEngine.attach(playerNode)
            audioEngine.connect(playerNode, to: remoteAudioMixer, format: processingFormat)
            peerPlayerNodes[peerID] = playerNode
        }
        
        let bufferToPlay = convertBufferIfNeeded(decodedBuffer, to: processingFormat) ?? decodedBuffer
        
        if !playerNode.isPlaying {
            playerNode.play()
        }
        
        playerNode.scheduleBuffer(bufferToPlay, at: nil, options: [], completionHandler: nil)
        
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                print("Failed to restart audio engine: \(error)")
            }
        }
    }
    
    private func updateMonitoringConnections() {
        guard let audioEngine = audioEngine,
              let inputNode = inputNode else { return }
        
        let mainMixer = audioEngine.mainMixerNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        audioEngine.disconnectNodeOutput(inputNode)
        
        if isMonitoringEnabled {
            audioEngine.connect(inputNode, to: mainMixer, format: inputFormat)
            print("Monitoring enabled")
        } else {
            print("Monitoring disabled")
        }
    }
    
    private func convertBufferIfNeeded(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format.sampleRate == format.sampleRate &&
           buffer.format.channelCount == format.channelCount {
            return buffer
        }
        
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
            return nil
        }
        
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: buffer.frameLength
        ) else {
            return nil
        }
        
        var error: NSError?
        let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        guard status != .error, error == nil else {
            return nil
        }
        
        return convertedBuffer
    }
}
