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
        @Published var level: CGFloat = 0.0         // Single value 0.0 to 1.0
        @Published var isActive: Bool = false
        private var threshold: Float = 0.01
        
        // Smoothing for level changes
        private var smoothingFactor: CGFloat = 0.3
        
        // Update with new audio data
        public func updateWithBuffer(_ buffer: AVAudioPCMBuffer) {
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            
            // Calculate RMS (root mean square) of the buffer
            var sum: Float = 0
            for i in 0..<frameLength {
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frameLength))
            
            // Determine if audio is active
            let newIsActive = rms > threshold
            
            // Normalize to 0.0-1.0 range with reasonable scaling
            let normalizedLevel = min(rms * 20, 1.0) // Adjust multiplier as needed
            
            DispatchQueue.main.async {
                self.isActive = newIsActive
                
                if newIsActive {
                    // Smooth the level changes for less jittery animation
                    self.level = self.level * (1 - self.smoothingFactor) + CGFloat(normalizedLevel) * self.smoothingFactor
                } else {
                    // Gradually fade out when inactive
                    self.level = max(self.level * 0.8, 0.0)
                }
            }
        }
        
        // Simple simulation for previews
        public func simulateActivity(active: Bool, level: CGFloat = 0.7) {
            DispatchQueue.main.async {
                self.isActive = active
                self.level = active ? level : 0.0
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
    
    // Updated simulateAudioActivity method in BubbleSessionManager
    public func simulateAudioActivity(for peerID: MCPeerID, active: Bool, level: CGFloat? = nil) {
        let audioData = getAudioDataForPeer(peerID)
        
        if active {
            let customLevel = level ?? CGFloat.random(in: 0.3...1.0)
            audioData.simulateActivity(active: true, level: customLevel)
        } else {
            audioData.simulateActivity(active: false, level: 0.0)
        }
    }
    
    // MARK: - Public Methods
    
    func setupSession() {
        // Clean up existing session first
        cleanupSession()
        
        // Create the session
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
        
        // Create the service browser to find other bubbles
        nearbyServiceBrowser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        nearbyServiceBrowser?.delegate = self
        
        // Start browsing for nearby peers
        nearbyServiceBrowser?.startBrowsingForPeers()
    }

    private func cleanupSession() {
        // Stop browsing and advertising
        nearbyServiceBrowser?.stopBrowsingForPeers()
        nearbyServiceAdvertiser?.stopAdvertisingPeer()
        
        // Disconnect session
        session?.disconnect()
        
        // Clear delegates to prevent callbacks
        session?.delegate = nil
        nearbyServiceBrowser?.delegate = nil
        nearbyServiceAdvertiser?.delegate = nil
        
        // Clear references
        session = nil
        nearbyServiceBrowser = nil
        nearbyServiceAdvertiser = nil
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
        
        guard let browser = nearbyServiceBrowser, let session = session else {
            errorMessage = "Session not ready"
            return
        }
        
        browser.invitePeer(bubble.hostPeerID, to: session, withContext: nil, timeout: 10) // Reduced timeout
        currentBubble = bubble
        isHost = false
        
        // Set a fallback timer in case connection fails
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            if !self.isConnected && self.currentBubble?.id == bubble.id {
                self.errorMessage = "Failed to connect to bubble"
                self.currentBubble = nil
            }
        }
    }
    
    func leaveBubble() {
        cleanupSession()
        stopAudioEngine()
        
        DispatchQueue.main.async {
            self.currentBubble = nil
            self.isConnected = false
            self.isHost = false
        }
        
        // Restart session for finding new bubbles
        setupSession()
    }
    
    func toggleMonitoring(enabled: Bool) {
        isMonitoringEnabled = enabled
        updateMonitoringConnections()
    }
    
    // MARK: - Private Methods
        
    private func setupAudioSession() {
        // setup Opus Codec
        opusCodec = OpusCodec()
        
        do {
            // Configure audio session with more specific options
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,  // This is key for real-time audio
                options: [
                    .defaultToSpeaker,
                    .allowBluetooth,
                    .allowBluetoothA2DP,
                    .mixWithOthers
                ]
            )
            
            // Set preferred settings for low latency
            try audioSession.setPreferredIOBufferDuration(0.02) // 20ms is more stable than 5ms
            try audioSession.setPreferredSampleRate(48000)
            
            // Make sure to activate the session
            try audioSession.setActive(true, options: [])
            
            print("Audio session configured successfully")
            
        } catch {
            errorMessage = "Failed to set up audio session: \(error.localizedDescription)"
            print("Audio session error: \(error)")
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
        print("Setting up audio engine...")
        
        // Stop any existing engine first
        stopAudioEngine()
        
        // Create new audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            print("Failed to create audio engine")
            return
        }
        
        // Get the input and output nodes
        inputNode = audioEngine.inputNode
        let mainMixer = audioEngine.mainMixerNode
        
        // Make sure we have input node
        guard let inputNode = inputNode else {
            print("Failed to get input node")
            return
        }
        
        // Create our custom mixer for remote audio
        remoteAudioMixer = AVAudioMixerNode()
        guard let remoteAudioMixer = remoteAudioMixer else {
            print("Failed to create remote audio mixer")
            return
        }
        
        // Attach the remote mixer to the engine
        audioEngine.attach(remoteAudioMixer)
        
        // Use the hardware sample rate to avoid conflicts
        let hardwareSampleRate = audioSession.sampleRate
        print("Hardware sample rate: \(hardwareSampleRate)")
        
        // Create our processing format (mono for voice chat)
        guard let processingFormat = AVAudioFormat(
            standardFormatWithSampleRate: hardwareSampleRate,
            channels: 1
        ) else {
            print("Failed to create processing format")
            return
        }
        
        // Get input format
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("Input format: \(inputFormat)")
        print("Processing format: \(processingFormat)")
        
        // Install tap on input node for capturing audio to send
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
            // Convert to our processing format if needed
            if let convertedBuffer = self?.convertBufferIfNeeded(buffer, to: processingFormat) {
                self?.processAndSendAudioBuffer(convertedBuffer)
            }
        }
        
        // Connect remote mixer to main mixer (for incoming audio)
        audioEngine.connect(remoteAudioMixer, to: mainMixer, format: processingFormat)
        
        // Set up monitoring if enabled
        updateMonitoringConnections()
        
        // Prepare and start the engine
        do {
            audioEngine.prepare()
            try audioEngine.start()
            print("Audio engine started successfully")
        } catch {
            print("Failed to start audio engine: \(error) (\(error._code))")
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
            
            // Try to recover by resetting the audio session
            do {
                try audioSession.setActive(false)
                try audioSession.setActive(true)
                audioEngine.prepare()
                try audioEngine.start()
                print("Audio engine started after recovery")
            } catch {
                print("Recovery failed: \(error)")
            }
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
        print("Stopping audio engine...")
        
        // Stop all player nodes first
        for (peer, playerNode) in peerPlayerNodes {
            playerNode.stop()
            print("Stopped player node for: \(peer.displayName)")
        }
        
        // Remove input tap
        inputNode?.removeTap(onBus: 0)
        
        // Stop and reset the engine
        audioEngine?.stop()
        audioEngine?.reset()
        
        // Detach all player nodes
        for (_, playerNode) in peerPlayerNodes {
            audioEngine?.detach(playerNode)
        }
        
        // Clear references
        peerPlayerNodes.removeAll()
        
        // Clean up nodes
        if let remoteAudioMixer = remoteAudioMixer {
            audioEngine?.detach(remoteAudioMixer)
        }
        
        audioEngine = nil
        inputNode = nil
        mixerNode = nil
        remoteAudioMixer = nil
        
        print("Audio engine stopped and cleaned up")
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
    
    // Separate method for handling monitoring connections
    private func updateMonitoringConnections() {
        guard let audioEngine = audioEngine,
              let inputNode = inputNode else { return }
                
        let mainMixer = audioEngine.mainMixerNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Disconnect any existing monitoring connections
        let connections = audioEngine.outputConnectionPoints(for: inputNode, outputBus: 0)
        for connection in connections {
            if connection.node === mainMixer {
                audioEngine.disconnectNodeOutput(inputNode)
                break
            }
        }
        
        // Connect input to main mixer if monitoring is enabled
        if isMonitoringEnabled {
            audioEngine.connect(inputNode, to: mainMixer, format: inputFormat)
            print("Monitoring enabled - connected input to main mixer")
        } else {
            print("Monitoring disabled")
        }
    }
    
    private func receiveAudioData(_ data: Data, fromPeer peer: MCPeerID) {
        print("Received \(data.count) bytes from peer: \(peer.displayName)")
        
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
        
        let opusData = data.subdata(in: 4..<data.count)
        
        // Decode Opus data
        guard let decodedBuffer = opusCodec?.decode(data: opusData) else {
            print("Failed to decode audio data from peer: \(peer.displayName)")
            return
        }
        
        print("Decoded buffer: \(decodedBuffer.frameLength) frames, format: \(decodedBuffer.format)")
        
        // Update peer's audio levels
        let peerAudioData = getAudioDataForPeer(peer)
        peerAudioData.updateWithBuffer(decodedBuffer)
        
        // Use consistent processing format
        let hardwareSampleRate = audioSession.sampleRate
        guard let processingFormat = AVAudioFormat(
            standardFormatWithSampleRate: hardwareSampleRate,
            channels: 1
        ) else {
            print("Failed to create processing format")
            return
        }
        
        // Get or create player node for this peer
        let playerNode: AVAudioPlayerNode
        if let existingNode = peerPlayerNodes[peer] {
            playerNode = existingNode
        } else {
            playerNode = AVAudioPlayerNode()
            audioEngine.attach(playerNode)
            
            // Connect to remote mixer
            audioEngine.connect(playerNode, to: remoteAudioMixer, format: processingFormat)
            peerPlayerNodes[peer] = playerNode
            
            print("Created new player node for peer: \(peer.displayName)")
        }
        
        // Convert buffer to processing format if needed
        let bufferToPlay: AVAudioPCMBuffer
        if let convertedBuffer = convertBufferIfNeeded(decodedBuffer, to: processingFormat) {
            bufferToPlay = convertedBuffer
        } else {
            print("Using original buffer format")
            bufferToPlay = decodedBuffer
        }
        
        // Start player if not already playing
        if !playerNode.isPlaying {
            playerNode.play()
            print("Started player node for peer: \(peer.displayName)")
        }
        
        // Schedule the buffer
        playerNode.scheduleBuffer(bufferToPlay, at: nil, options: [], completionHandler: {
            // Buffer completed - could add logic here if needed
        })
        
        // Make sure audio engine is still running
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
                print("Restarted audio engine")
            } catch {
                print("Failed to restart audio engine: \(error)")
            }
        }
    }
    
    // Helper method to convert audio buffer format if needed
    private func convertBufferIfNeeded(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // If formats match, return original buffer
        if buffer.format == format {
            return buffer
        }
        
        // Create converter
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
            print("Could not create audio converter")
            return nil
        }
        
        // Create output buffer
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: buffer.frameLength
        ) else {
            print("Could not create converted buffer")
            return nil
        }
        
        // Perform conversion
        var error: NSError?
        let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        if let error = error {
            print("Audio conversion error: \(error)")
            return nil
        }
        
        if status == .error {
            print("Audio conversion failed with status: \(status)")
            return nil
        }
        
        return convertedBuffer
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
                    if !updatedBubble.participants.contains(peerID) && peerID != updatedBubble.hostPeerID {
                        updatedBubble.participants.append(peerID)
                    }
                    self.currentBubble = updatedBubble
                }
                self.isConnected = true
                
                // Setup audio on background queue to avoid blocking UI
                DispatchQueue.global(qos: .userInitiated).async {
                    if !self.isHost {
                        self.setupAudioEngine()
                    }
                }
                
            case .connecting:
                print("Connecting to \(peerID.displayName)")
                
            case .notConnected:
                if let bubble = self.currentBubble {
                    var updatedBubble = bubble
                    updatedBubble.participants.removeAll { $0 == peerID }
                    self.currentBubble = updatedBubble
                }
                
                // Clean up audio resources for this peer
                if let playerNode = self.peerPlayerNodes[peerID] {
                    playerNode.stop()
                    self.audioEngine?.detach(playerNode)
                    self.peerPlayerNodes.removeValue(forKey: peerID)
                }
                self.remoteAudioData.removeValue(forKey: peerID)
                
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
