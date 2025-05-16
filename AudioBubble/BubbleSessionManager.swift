//
//  BubbleSessionManager.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/8/25.
//

import SwiftUI
import MultipeerConnectivity
import AVFoundation
import Combine

class BubbleSessionManager: NSObject, ObservableObject {
    // Published properties to update UI
    @Published var availableBubbles: [AudioBubble] = []
    @Published var currentBubble: AudioBubble?
    @Published var isHost = false
    @Published var isConnected = false
    @Published var isHeadphonesConnected = false
    @Published var isMonitoringEnabled = false
    @Published var errorMessage: String?
    
    // MultipeerConnectivity
    private var myPeerID: MCPeerID
    private var serviceType = "audio-bubble"
    private var session: MCSession?
    private var nearbyServiceBrowser: MCNearbyServiceBrowser?
    private var nearbyServiceAdvertiser: MCNearbyServiceAdvertiser?
    
    // Audio
    private var audioSession: AVAudioSession = .sharedInstance()
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var mixerNode: AVAudioMixerNode?
    private var remoteAudioMixer: AVAudioMixerNode?
    private var cancellables = Set<AnyCancellable>()
    private var peerPlayerNodes: [MCPeerID: AVAudioPlayerNode] = [:]
    private var opusCodec: OpusCodec?
    
    // Audio Level Tracking
    private var localAudioData = ParticipantAudioData()
    private var remoteAudioData: [MCPeerID: ParticipantAudioData] = [:]
        
    // Each participant will have their own audio level data
    public class ParticipantAudioData: ObservableObject {
        @Published var levels: [CGFloat] = [0, 0, 0, 0, 0]
        @Published var isActive: Bool = false
        private var threshold: Float = 0.005 // Lower threshold to detect more audio
        
        // Update levels with new audio data
        public func updateWithBuffer(_ buffer: AVAudioPCMBuffer) {
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            
            // Calculate RMS (root mean square) of the buffer to get amplitude
            var sum: Float = 0
            for i in 0..<frameLength {
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frameLength))
            
            // Debug output
            print("Audio RMS: \(rms), threshold: \(threshold)")
            
            // Determine if audio is active based on threshold
            let newIsActive = rms > threshold
            
            // Generate new levels based on audio amplitude
            // Normalize to 0.0-1.0 range with more amplification for visibility
            let normalizedRms = min(rms * 10, 1.0) // More amplification
            
            DispatchQueue.main.async {
                // Update levels even if not active, just make them small
                if newIsActive {
                    self.levels = [
                        CGFloat(normalizedRms * Float.random(in: 0.7...1.0)),
                        CGFloat(normalizedRms * Float.random(in: 0.8...1.0)),
                        CGFloat(normalizedRms * Float.random(in: 0.9...1.0)),
                        CGFloat(normalizedRms * Float.random(in: 0.8...1.0)),
                        CGFloat(normalizedRms * Float.random(in: 0.7...1.0))
                    ]
                    self.isActive = true
                } else {
                    // Gradually reduce levels when not active
                    self.levels = self.levels.map { max($0 * 0.8, 0.0) }
                    
                    // Only set inactive when levels are low enough
                    if self.levels.allSatisfy({ $0 < 0.1 }) {
                        self.isActive = false
                    }
                }
            }
        }
        
        // Simulate levels for demo/testing purposes
        public func simulateActivity(active: Bool) {
            isActive = active
            
            if active {
                // Generate random levels for visualization
                levels = (0..<5).map { _ in CGFloat.random(in: 0.3...1.0) }
            }
        }
    }
    
    init(username: String) {
        self.myPeerID = MCPeerID(displayName: username)
        super.init()
        
        // Setup audio session
        setupAudioSession()
        
        // Start observing for headphone connection
        monitorHeadphonesConnection()
    }
    
    // Get audio data for a specific peer
    public func getAudioDataForPeer(_ peerID: MCPeerID) -> ParticipantAudioData {
        if peerID == myPeerID {
            return localAudioData
        } else if let data = remoteAudioData[peerID] {
            return data
        } else {
            let newData = ParticipantAudioData()
            remoteAudioData[peerID] = newData
            return newData
        }
    }
    
    public var previewHeadphonesConnected: Bool {
        get { return isHeadphonesConnected }
        set { isHeadphonesConnected = newValue }
    }
    
    public var currentPeerID: MCPeerID {
        return myPeerID
    }
    
    public func simulateAudioActivity(for peerID: MCPeerID, active: Bool, levels: [CGFloat]? = nil) {
        let audioData = getAudioDataForPeer(peerID)
        
        if active {
            if let customLevels = levels {
                audioData.levels = customLevels
            } else {
                audioData.levels = (0..<5).map { _ in CGFloat.random(in: 0.3...1.0) }
            }
            audioData.isActive = true
        } else {
            audioData.isActive = false
        }
    }
    
    // MARK: - Public Methods
    
    func setupSession() {
        // Create the session
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
        
        // Create the service browser to find other bubbles
        nearbyServiceBrowser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        nearbyServiceBrowser?.delegate = self
        
        // Start browsing for nearby peers
        nearbyServiceBrowser?.startBrowsingForPeers()
    }
    
    func createBubble(name: String) {
        guard isHeadphonesConnected else {
            errorMessage = "Headphones required to create a bubble"
            return
        }
        
        let bubble = AudioBubble(id: UUID().uuidString, name: name, hostPeerID: myPeerID)
        currentBubble = bubble
        isHost = true
        isConnected = true
        
        // Start advertising our bubble
        let info = ["bubbleID": bubble.id, "bubbleName": name]
        nearbyServiceAdvertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: info, serviceType: serviceType)
        nearbyServiceAdvertiser?.delegate = self
        nearbyServiceAdvertiser?.startAdvertisingPeer()
        
        // Setup audio engine for the host
        setupAudioEngine()
    }
    
    func joinBubble(_ bubble: AudioBubble) {
        guard isHeadphonesConnected else {
            errorMessage = "Headphones required to join a bubble"
            return
        }
        
        guard let browser = nearbyServiceBrowser else { return }
        
        browser.invitePeer(bubble.hostPeerID, to: session!, withContext: nil, timeout: 30)
        currentBubble = bubble
        isHost = false
    }
    
    func leaveBubble() {
        if isHost {
            nearbyServiceAdvertiser?.stopAdvertisingPeer()
        }
        
        stopAudioEngine()
        session?.disconnect()
        currentBubble = nil
        isConnected = false
        isHost = false
    }
    
    func toggleMonitoring(enabled: Bool) {
        isMonitoringEnabled = enabled
        
        // Reconfigure audio engine based on monitoring state
        if let audioEngine = audioEngine, audioEngine.isRunning {
            updateMonitoringState()
        }
    }
    
    // MARK: - Private Methods
        
    private func setupAudioSession() {
        // setup Opus Codec
        opusCodec = OpusCodec()
        
        do {
            try audioSession.setCategory(.playAndRecord, options: [.allowBluetooth, .defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            errorMessage = "Failed to set up audio session: \(error.localizedDescription)"
        }
    }
    
    private func monitorHeadphonesConnection() {
        // Check initial state
        checkHeadphonesConnection()
        
        // Monitor future route changes
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] _ in
                self?.checkHeadphonesConnection()
            }
            .store(in: &cancellables)
    }
    
    private func checkHeadphonesConnection() {
        // Check if current route has headphone outputs
        let currentRoute = audioSession.currentRoute
        isHeadphonesConnected = currentRoute.outputs.contains {
            $0.portType == .headphones ||
            $0.portType == .bluetoothA2DP ||
            $0.portType == .bluetoothHFP
        }
        
        // If we're connected and AirPods are detected, try to enable noise cancellation
        if isHeadphonesConnected && isConnected {
            enableAirPodsNoiseCancellation()
        }
    }
    
    private func enableAirPodsNoiseCancellation() {
        // Note: This is a simplified placeholder for the AirPods noise cancellation feature
        // In a real app, you would need to use private APIs or CoreBluetooth
        // to communicate with AirPods for noise cancellation control
        
        // This would require additional research and potentially private APIs
        print("Attempting to enable AirPods noise cancellation")
    }
    
    private func setupAudioEngine() {
        // Stop any existing engine first
        stopAudioEngine()
        
        audioEngine = AVAudioEngine()
        
        guard let audioEngine = audioEngine else { return }
        
        // Configure audio session for real-time low-latency audio
        do {
            try audioSession.setCategory(.playAndRecord,
                                  options: [.allowBluetooth, .defaultToSpeaker, .mixWithOthers])
            try audioSession.setPreferredIOBufferDuration(0.005) // 5ms buffer for lower latency
            try audioSession.setPreferredSampleRate(48000) // Match Opus sampleRate
            try audioSession.setActive(true)
        } catch {
            errorMessage = "Failed to set up audio session: \(error.localizedDescription)"
            print("Audio session setup error: \(error)")
            return
        }
        
        // Get the input and mixer nodes
        inputNode = audioEngine.inputNode
        mixerNode = audioEngine.mainMixerNode
        
        guard let inputNode = inputNode,
              let mixerNode = mixerNode else {
            print("Failed to get input or mixer nodes")
            return
        }
        
        // Ensure mixer volume is set to audible level
        mixerNode.outputVolume = 1.0
        
        // Use a consistent format throughout the audio graph
        let processingFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)
        
        guard let processingFormat = processingFormat else {
            print("Failed to create processing format")
            return
        }
        
        print("Using audio format: \(processingFormat)")
        
        // Create a format converter node to handle any format conversions
        let formatConverter = AVAudioMixerNode()
        audioEngine.attach(formatConverter)
        
        // Create a monitor mixer for local monitoring (hearing yourself)
        let monitorMixer = AVAudioMixerNode()
        audioEngine.attach(monitorMixer)
        
        // Create a remote audio mixer for incoming audio from peers
        let remoteAudioMixer = AVAudioMixerNode()
        audioEngine.attach(remoteAudioMixer)
        
        // CRITICAL FIX: Always connect input to format converter
        // This ensures the tap has a proper audio graph connection
        audioEngine.connect(inputNode, to: formatConverter, format: inputNode.outputFormat(forBus: 0))
        
        // Install tap AFTER connecting the input node
        formatConverter.installTap(onBus: 0, bufferSize: 480, format: processingFormat) { [weak self] buffer, time in
            self?.processAndSendAudioBuffer(buffer)
        }
        
        // Connect format converter to monitor mixer if monitoring is enabled
        if isMonitoringEnabled {
            audioEngine.connect(formatConverter, to: monitorMixer, format: processingFormat)
        }
        
        // Connect both mixers to the main mixer
        audioEngine.connect(monitorMixer, to: mixerNode, format: processingFormat)
        audioEngine.connect(remoteAudioMixer, to: mixerNode, format: processingFormat)
        
        // Store reference to remote audio mixer for peer audio
        self.remoteAudioMixer = remoteAudioMixer
        
        do {
            // Prepare the engine before starting
            audioEngine.prepare()
            try audioEngine.start()
            print("Audio engine started successfully")
        } catch {
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
            print("Audio engine start error: \(error)")
        }
    }
    
    private func updateMonitoringState() {
        guard let audioEngine = audioEngine,
              let formatConverter = audioEngine.attachedNodes.first(where: { $0 is AVAudioMixerNode && $0 !== mixerNode && $0 !== remoteAudioMixer }) as? AVAudioMixerNode,
              let monitorMixer = audioEngine.attachedNodes.first(where: { $0 is AVAudioMixerNode && $0 !== mixerNode && $0 !== remoteAudioMixer && $0 !== formatConverter }) as? AVAudioMixerNode else {
            print("Could not find format converter or monitor mixer")
            return
        }
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        
        // Disconnect and reconnect monitor based on state
        audioEngine.disconnectNodeOutput(formatConverter, bus: 0)
        
        // Always connect to main mixer via remoteAudioMixer
        audioEngine.connect(remoteAudioMixer!, to: mixerNode!, format: format)
        audioEngine.connect(monitorMixer, to: mixerNode!, format: format)
        
        // Connect to monitor mixer only if monitoring is enabled
        if isMonitoringEnabled {
            audioEngine.connect(formatConverter, to: monitorMixer, format: format)
        }
    }
    
    private func stopAudioEngine() {
        // First stop all player nodes
        for playerNode in peerPlayerNodes.values {
            playerNode.stop()
        }
        
        // Remove taps
        inputNode?.removeTap(onBus: 0)
        
        // Find and remove tap from format converter
        if let audioEngine = audioEngine {
            for node in audioEngine.attachedNodes {
                if let mixerNode = node as? AVAudioMixerNode, mixerNode !== self.mixerNode && mixerNode !== self.remoteAudioMixer {
                    mixerNode.removeTap(onBus: 0)
                }
            }
        }
        
        // If engine is running, stop it
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
        }
        
        // Detach player nodes
        if let engine = audioEngine {
            for playerNode in peerPlayerNodes.values {
                engine.detach(playerNode)
            }
        }
        
        // Clear references
        peerPlayerNodes.removeAll()
        audioEngine = nil
        inputNode = nil
        mixerNode = nil
        remoteAudioMixer = nil
    }
    
    private func processAndSendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Update local audio levels
        localAudioData.updateWithBuffer(buffer)
        
        // Send buffer to peers
        guard let session = session, !session.connectedPeers.isEmpty else {
            print("No session or no connected peers")
            return
        }
        
        print("Processing audio buffer: frameLength=\(buffer.frameLength), format=\(buffer.format)")
        
        // Encode using Opus
        if let encodedData = opusCodec?.encode(buffer: buffer) {
            print("Successfully encoded \(encodedData.count) bytes with Opus")
            
            // Add packet header with sequence number for tracking packet loss
            var dataPacket = Data()
            let seqNumber = UInt32(Date().timeIntervalSince1970 * 1000) // Simple sequence number
            withUnsafeBytes(of: seqNumber) { seqBytes in
                dataPacket.append(contentsOf: seqBytes)
            }
            dataPacket.append(encodedData)
            
            print("Sending \(dataPacket.count) bytes to \(session.connectedPeers.count) peers")
            
            do {
                // Use unreliable delivery for lower latency
                try session.send(dataPacket, toPeers: session.connectedPeers, with: .unreliable)
            } catch {
                errorMessage = "Failed to send audio data: \(error.localizedDescription)"
                print("Send error: \(error)")
            }
        } else {
            print("Failed to encode audio data with Opus")
        }
    }
    
    private func receiveAudioData(_ data: Data, fromPeer peer: MCPeerID) {
        print("Received \(data.count) bytes from peer: \(peer.displayName)")
        
        // Get or create audio data for this peer
        let peerAudioData = getAudioDataForPeer(peer)
        
        guard let audioEngine = audioEngine,
              let remoteAudioMixer = remoteAudioMixer else {
            print("Audio engine or remote mixer not available")
            return
        }
        
        // Extract sequence number and opus data
        guard data.count > 4 else {
            print("Received malformed packet (too small)")
            return
        }
        
        let seqNumber = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        let opusData = data.subdata(in: 4..<data.count)
        
        print("Extracted sequence number: \(seqNumber), opus data size: \(opusData.count) bytes")
        
        // Decode Opus data
        guard let buffer = opusCodec?.decode(data: opusData) else {
            print("Failed to decode audio data from peer: \(peer.displayName)")
            return
        }
        
        print("Successfully decoded to PCM buffer: frameLength=\(buffer.frameLength)")
        
        // Update the peer's audio levels
        peerAudioData.updateWithBuffer(buffer)
        
        // Use consistent processing format
        let processingFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        
        // Check if the player node exists for this peer
        if let existingNode = peerPlayerNodes[peer] {
            print("Using existing player node for peer: \(peer.displayName)")
            
            // Convert buffer to processing format if needed
            let convertedBuffer: AVAudioPCMBuffer
            if buffer.format == processingFormat {
                convertedBuffer = buffer
            } else {
                guard let converted = convertAudioBuffer(buffer, to: processingFormat) else {
                    print("Failed to convert audio format")
                    return
                }
                convertedBuffer = converted
            }
            
            existingNode.scheduleBuffer(convertedBuffer, at: nil, options: .interruptsAtLoop, completionHandler: {
                print("Buffer completed playback for peer: \(peer.displayName)")
            })
            
            // Make sure the node is playing
            if !existingNode.isPlaying {
                existingNode.play()
                print("Started player node for peer: \(peer.displayName)")
            }
        } else {
            print("Creating new player node for peer: \(peer.displayName)")
            
            // Create new player node
            let playerNode = AVAudioPlayerNode()
            
            // Attach the node BEFORE connecting it
            audioEngine.attach(playerNode)
            
            // Connect to the remote audio mixer with consistent format
            audioEngine.connect(playerNode, to: remoteAudioMixer, format: processingFormat)
            
            // Store for future use
            peerPlayerNodes[peer] = playerNode
            
            // Convert buffer to processing format if needed
            let convertedBuffer: AVAudioPCMBuffer
            if buffer.format == processingFormat {
                convertedBuffer = buffer
            } else {
                guard let converted = convertAudioBuffer(buffer, to: processingFormat) else {
                    print("Failed to convert audio format")
                    return
                }
                convertedBuffer = converted
            }
            
            // Start playing and schedule buffer
            playerNode.play()
            playerNode.scheduleBuffer(convertedBuffer, at: nil, options: .interruptsAtLoop, completionHandler: {
                print("Buffer completed playback for peer: \(peer.displayName)")
            })
            
            print("Player node created and started for peer: \(peer.displayName)")
        }
        
        // Make sure the audio engine is running
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
                print("Started audio engine")
            } catch {
                print("Failed to start audio engine: \(error)")
            }
        }
    }
    
    // Helper method to convert audio buffer formats
    private func convertAudioBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
            print("Could not create audio converter")
            return nil
        }
        
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength) else {
            print("Could not create converted buffer")
            return nil
        }
        
        var error: NSError?
        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        if let error = error {
            print("Audio conversion error: \(error)")
            return nil
        }
        
        return convertedBuffer
    }
}

// MARK: - MultipeerConnectivity Delegates

extension BubbleSessionManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if let bubble = self.currentBubble {
                    var updatedBubble = bubble
                    
                    // Only add the peer if it's not already in the list and is not the host
                    if !updatedBubble.participants.contains(peerID) && peerID != updatedBubble.hostPeerID {
                        updatedBubble.participants.append(peerID)
                    }
                    
                    self.currentBubble = updatedBubble
                }
                self.isConnected = true
                
                // If we just joined as a client, start audio
                if !self.isHost {
                    self.setupAudioEngine()
                }
                
            case .connecting:
                print("Connecting to \(peerID.displayName)")
                
            case .notConnected:
                if let bubble = self.currentBubble {
                    var updatedBubble = bubble
                    updatedBubble.participants.removeAll { $0 == peerID }
                    self.currentBubble = updatedBubble
                }
                
            @unknown default:
                print("Unknown state: \(state)")
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Process received data - in this case, audio data
        receiveAudioData(data, fromPeer: peerID)
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used in this example
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used in this example
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used in this example
    }
}

extension BubbleSessionManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            // Make sure it's a bubble advertisement
            guard let info = info,
                  let bubbleID = info["bubbleID"],
                  let bubbleName = info["bubbleName"] else { return }
            
            // Create bubble object
            let bubble = AudioBubble(id: bubbleID, name: bubbleName, hostPeerID: peerID)
            
            // Add to available bubbles if not already there
            if !self.availableBubbles.contains(where: { $0.id == bubble.id }) {
                self.availableBubbles.append(bubble)
            }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            // Remove bubbles hosted by this peer
            self.availableBubbles.removeAll { $0.hostPeerID == peerID }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        errorMessage = "Failed to start browsing: \(error.localizedDescription)"
    }
}

extension BubbleSessionManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Automatically accept the invitation
        invitationHandler(true, session)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        errorMessage = "Failed to start advertising: \(error.localizedDescription)"
    }
}
