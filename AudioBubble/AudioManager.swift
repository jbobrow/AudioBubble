import AVFoundation
import Accelerate
import Combine

class AudioManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFormat: AVAudioFormat!
    
    // Audio callback for sending data
    var onAudioData: ((Data) -> Void)?
    
    // Buffer for incoming audio
    private var audioBufferQueue: [AVAudioPCMBuffer] = []
    private let bufferLock = NSLock()
    
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
            
            print("✅ Audio session configured for low-latency voice chat")
            print("   Sample Rate: \(audioSession.sampleRate) Hz")
            print("   IO Buffer Duration: \(audioSession.ioBufferDuration * 1000) ms")
            print("   Hardware Input Latency: \(audioSession.inputLatency * 1000) ms")
            print("   Hardware Output Latency: \(audioSession.outputLatency * 1000) ms")
            
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
    }
    
    // MARK: - Audio Engine Setup
    
    private func setupAudioEngine() {
        let inputNode = audioEngine.inputNode
        let mainMixer = audioEngine.mainMixerNode
        
        // Use hardware format for lowest latency
        audioFormat = inputNode.inputFormat(forBus: 0)
        
        // Create a format for transmission (16kHz mono is enough for voice)
        let transmitFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )!
        
        print("📊 Audio Format:")
        print("   Hardware: \(audioFormat.sampleRate) Hz, \(audioFormat.channelCount) channels")
        print("   Transmit: \(transmitFormat.sampleRate) Hz, \(transmitFormat.channelCount) channels")
        
        // Install tap on input for recording
        inputNode.installTap(onBus: 0, bufferSize: 256, format: nil) { [weak self] buffer, time in
            self?.processInputAudio(buffer: buffer, format: transmitFormat)
        }
        
        // Attach player node for playback of received audio
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: mainMixer, format: transmitFormat)
        
        // Prepare the engine
        audioEngine.prepare()
    }
    
    // MARK: - Recording Control
    
    func startRecording() {
        guard !isRecording else { return }
        
        do {
            try audioEngine.start()
            playerNode.play()
            isRecording = true
            print("🎤 Recording started")
        } catch {
            print("❌ Failed to start audio engine: \(error)")
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        audioEngine.stop()
        playerNode.stop()
        isRecording = false
        print("⏹️ Recording stopped")
    }
    
    // MARK: - Audio Processing
    
    private func processInputAudio(buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        // Convert to desired format and send
        guard let convertedBuffer = convertBuffer(buffer, to: format) else { return }
        
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
    
    func receiveAudioData(_ data: Data) {
        guard let buffer = dataToBuffer(data, format: AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )!) else { return }
        
        // Schedule buffer for playback immediately
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
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
            print("❌ Conversion error: \(error)")
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
