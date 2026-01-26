import AVFoundation
import Accelerate
import Combine
import MultipeerConnectivity

class AudioManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0

    private let audioEngine = AVAudioEngine()
    private var audioFormat: AVAudioFormat!

    // Multi-peer audio playback
    private var peerPlayerNodes: [MCPeerID: AVAudioPlayerNode] = [:]
    private let mixerNode = AVAudioMixerNode()
    private let playerNodesLock = NSLock()

    // Audio format for transmission (16kHz mono)
    private var transmitFormat: AVAudioFormat!

    // Audio callback for sending data
    var onAudioData: ((Data) -> Void)?

    // Callback for peer audio level updates (for UI)
    var onPeerAudioLevel: ((MCPeerID, Float) -> Void)?

    override init() {
        super.init()
        setupAudioSession()
        setupAudioEngine()
    }

    // MARK: - Audio Session Setup

    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()

        do {
            // Configure for voice chat - THIS IS THE KEY TO FACETIME QUALITY
            // This enables echo cancellation, AGC, and noise suppression
            try audioSession.setCategory(.playAndRecord,
                                        mode: .voiceChat,
                                        options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])

            // Prefer low latency
            try audioSession.setPreferredIOBufferDuration(0.005) // 5ms buffer

            // Set sample rate for voice optimization
            try audioSession.setPreferredSampleRate(48000)

            // Allow background audio
            try audioSession.setActive(true)

            print("Audio session configured for low-latency voice chat")
            print("   Sample Rate: \(audioSession.sampleRate) Hz")
            print("   IO Buffer Duration: \(audioSession.ioBufferDuration * 1000) ms")
            print("   Hardware Input Latency: \(audioSession.inputLatency * 1000) ms")
            print("   Hardware Output Latency: \(audioSession.outputLatency * 1000) ms")

        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    // MARK: - Audio Engine Setup

    private func setupAudioEngine() {
        let inputNode = audioEngine.inputNode
        let mainMixer = audioEngine.mainMixerNode

        // Use hardware format for lowest latency
        audioFormat = inputNode.inputFormat(forBus: 0)

        // Create a format for transmission (16kHz mono is enough for voice)
        transmitFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )!

        print("Audio Format:")
        print("   Hardware: \(audioFormat.sampleRate) Hz, \(audioFormat.channelCount) channels")
        print("   Transmit: \(transmitFormat.sampleRate) Hz, \(transmitFormat.channelCount) channels")

        // Install tap on input for recording
        inputNode.installTap(onBus: 0, bufferSize: 256, format: nil) { [weak self] buffer, time in
            self?.processInputAudio(buffer: buffer)
        }

        // Attach mixer node for combining multiple peer audio streams
        audioEngine.attach(mixerNode)
        audioEngine.connect(mixerNode, to: mainMixer, format: transmitFormat)

        // Prepare the engine
        audioEngine.prepare()
    }

    // MARK: - Recording Control

    func startRecording() {
        guard !isRecording else { return }

        do {
            try audioEngine.start()
            isRecording = true
            print("Recording started")
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        audioEngine.stop()
        isRecording = false

        // Stop all peer player nodes
        playerNodesLock.lock()
        for (_, playerNode) in peerPlayerNodes {
            playerNode.stop()
        }
        playerNodesLock.unlock()

        print("Recording stopped")
    }

    // MARK: - Peer Management

    /// Add a player node for a new peer
    func addPeer(_ peerID: MCPeerID) {
        playerNodesLock.lock()
        defer { playerNodesLock.unlock() }

        guard peerPlayerNodes[peerID] == nil else { return }

        let playerNode = AVAudioPlayerNode()
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: mixerNode, format: transmitFormat)

        if isRecording {
            playerNode.play()
        }

        peerPlayerNodes[peerID] = playerNode
        print("Added audio player for peer: \(peerID.displayName)")
    }

    /// Remove a player node when peer disconnects
    func removePeer(_ peerID: MCPeerID) {
        playerNodesLock.lock()
        defer { playerNodesLock.unlock() }

        guard let playerNode = peerPlayerNodes[peerID] else { return }

        playerNode.stop()
        audioEngine.disconnectNodeOutput(playerNode)
        audioEngine.detach(playerNode)
        peerPlayerNodes.removeValue(forKey: peerID)

        print("Removed audio player for peer: \(peerID.displayName)")
    }

    /// Remove all peer player nodes
    func removeAllPeers() {
        playerNodesLock.lock()
        let peers = Array(peerPlayerNodes.keys)
        playerNodesLock.unlock()

        for peerID in peers {
            removePeer(peerID)
        }
    }

    // MARK: - Audio Processing

    private func processInputAudio(buffer: AVAudioPCMBuffer) {
        // Convert to desired format and send
        guard let convertedBuffer = convertBuffer(buffer, to: transmitFormat) else { return }

        // Calculate audio level for visualization
        if let channelData = convertedBuffer.int16ChannelData {
            let channelDataValue = channelData.pointee
            let frames = Int(convertedBuffer.frameLength)

            var sum: Float = 0
            for i in 0..<frames {
                let sample = Float(channelDataValue[i]) / Float(Int16.max)
                sum += abs(sample)
            }
            let avgLevel = sum / Float(frames)

            DispatchQueue.main.async {
                self.audioLevel = avgLevel
            }
        }

        // Convert buffer to Data and send via network
        if let data = bufferToData(convertedBuffer) {
            onAudioData?(data)
        }
    }

    // MARK: - Receiving Audio

    /// Receive audio data from a specific peer
    func receiveAudioData(_ data: Data, from peerID: MCPeerID) {
        guard let buffer = dataToBuffer(data, format: transmitFormat) else { return }

        // Calculate audio level for this peer
        if let channelData = buffer.int16ChannelData {
            let channelDataValue = channelData.pointee
            let frames = Int(buffer.frameLength)

            var sum: Float = 0
            for i in 0..<frames {
                let sample = Float(channelDataValue[i]) / Float(Int16.max)
                sum += abs(sample)
            }
            let avgLevel = sum / Float(frames)

            // Notify about peer audio level
            onPeerAudioLevel?(peerID, avgLevel)
        }

        // Schedule buffer for playback on this peer's player node
        playerNodesLock.lock()
        let playerNode = peerPlayerNodes[peerID]
        playerNodesLock.unlock()

        if let playerNode = playerNode {
            playerNode.scheduleBuffer(buffer, completionHandler: nil)
        } else {
            // Peer doesn't have a player node yet - add one
            addPeer(peerID)
            playerNodesLock.lock()
            peerPlayerNodes[peerID]?.scheduleBuffer(buffer, completionHandler: nil)
            playerNodesLock.unlock()
        }
    }

    /// Legacy method for backward compatibility (plays on first available peer node)
    func receiveAudioData(_ data: Data) {
        guard let buffer = dataToBuffer(data, format: transmitFormat) else { return }

        playerNodesLock.lock()
        let firstPlayerNode = peerPlayerNodes.values.first
        playerNodesLock.unlock()

        if let playerNode = firstPlayerNode {
            playerNode.scheduleBuffer(buffer, completionHandler: nil)
        }
    }

    // MARK: - Buffer Conversion Utilities

    private func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
            return nil
        }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            print("Conversion error: \(error)")
            return nil
        }

        convertedBuffer.frameLength = convertedBuffer.frameCapacity
        return convertedBuffer
    }

    private func bufferToData(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.int16ChannelData else { return nil }

        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(from: 0,
                                           to: Int(buffer.frameLength),
                                           by: buffer.stride).map { channelDataValue[$0] }

        return Data(bytes: channelDataValueArray, count: channelDataValueArray.count * MemoryLayout<Int16>.size)
    }

    private func dataToBuffer(_ data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(data.count) / format.streamDescription.pointee.mBytesPerFrame

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        guard let channelData = buffer.int16ChannelData else { return nil }

        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let baseAddress = bytes.baseAddress else { return }
            channelData.pointee.update(from: baseAddress.assumingMemoryBound(to: Int16.self), count: Int(frameCount))
        }

        return buffer
    }
}
