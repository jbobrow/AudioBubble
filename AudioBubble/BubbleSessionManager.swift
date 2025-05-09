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
    private var cancellables = Set<AnyCancellable>()
    private var peerPlayerNodes: [MCPeerID: AVAudioPlayerNode] = [:]
    
    // Audio Level Tracking
    private var localAudioData = ParticipantAudioData()
    private var remoteAudioData: [MCPeerID: ParticipantAudioData] = [:]
    
    // Each participant will have their own audio level data
    class ParticipantAudioData: ObservableObject {
        @Published var levels: [CGFloat] = [0, 0, 0, 0, 0]
        @Published var isActive: Bool = false
        private var threshold: Float = 0.005 // Lower threshold to detect more audio
        
        // Update levels with new audio data
        func updateWithBuffer(_ buffer: AVAudioPCMBuffer) {
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
        func simulateActivity(active: Bool) {
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
    func getAudioDataForPeer(_ peerID: MCPeerID) -> ParticipantAudioData {
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
            try audioSession.setActive(true)
        } catch {
            errorMessage = "Failed to set up audio session: \(error.localizedDescription)"
        }
        
        // Get the input and mixer nodes
        inputNode = audioEngine.inputNode
        mixerNode = audioEngine.mainMixerNode
        
        guard let inputNode = inputNode,
              let mixerNode = mixerNode else { return }
        
        // Get the input format directly
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        // We'll use a consistent format throughout the audio graph
        let processingFormat = AVAudioFormat(standardFormatWithSampleRate: inputFormat.sampleRate,
                                            channels: 1)
        
        guard let processingFormat = processingFormat else { return }
        
        print("Using audio format: \(processingFormat)")
        
        // Create a separate node for local input monitoring
        let monitorMixer = AVAudioMixerNode()
        audioEngine.attach(monitorMixer)
        
        // Install tap on the input node to get audio data for sending to peers
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: processingFormat) { [weak self] buffer, time in
            // Process and send audio data to peers
            self?.processAndSendAudioBuffer(buffer)
        }
        
        // Only connect input to monitor mixer if monitoring is enabled
        if isMonitoringEnabled {
            audioEngine.connect(inputNode, to: monitorMixer, format: processingFormat)
        }
        
        // Always connect monitor mixer to main mixer
        audioEngine.connect(monitorMixer, to: mixerNode, format: processingFormat)
        
        do {
            // Prepare the engine before starting
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
        }
    }
    
    private func updateMonitoringState() {
        guard let audioEngine = audioEngine,
              let inputNode = inputNode,
              let mixerNode = mixerNode else { return }
        
        // Find the monitor mixer node
        let monitorMixer = audioEngine.outputConnectionPoints(for: inputNode, outputBus: 0)
            .compactMap { $0.node as? AVAudioMixerNode }
            .first
        
        // If we found the monitor mixer, disconnect and reconnect as needed
        if let monitorMixer = monitorMixer {
            audioEngine.disconnectNodeOutput(inputNode)
            
            let format = inputNode.outputFormat(forBus: 0)
            
            // If monitoring is enabled, connect input to monitor mixer
            if isMonitoringEnabled {
                audioEngine.connect(inputNode, to: monitorMixer, format: format)
            }
        } else {
            // If no monitor mixer found, we need to recreate the audio engine
            stopAudioEngine()
            setupAudioEngine()
        }
    }
    
    private func stopAudioEngine() {
        // First stop all player nodes
        for playerNode in peerPlayerNodes.values {
            playerNode.stop()
        }
        
        // Remove input tap if it exists
        inputNode?.removeTap(onBus: 0)
        
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
    }
    
    private func processAndSendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Update local audio levels
        localAudioData.updateWithBuffer(buffer)
        
        // Send buffer to peers
        guard let session = session, !session.connectedPeers.isEmpty else { return }
        
        guard let data = buffer.floatChannelData?[0] else { return }
        let dataSize = Int(buffer.frameLength) * MemoryLayout<Float>.size
        let audioData = Data(bytes: data, count: dataSize)
        
        do {
            // Use unreliable delivery for lower latency
            try session.send(audioData, toPeers: session.connectedPeers, with: .unreliable)
        } catch {
            errorMessage = "Failed to send audio data: \(error.localizedDescription)"
        }
    }
    
    private func receiveAudioData(_ data: Data, fromPeer peer: MCPeerID) {
        // Get or create audio data for this peer
        let peerAudioData = getAudioDataForPeer(peer)
        
        guard let audioEngine = audioEngine, let mixerNode = mixerNode else {
            print("Audio engine or mixer not available")
            return
        }
        
        // Convert data to audio buffer
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)
        
        guard let format = format,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count / MemoryLayout<Float>.size)) else {
            print("Failed to create buffer")
            return
        }
        
        // Copy data into buffer
        data.withUnsafeBytes { (bufferPointer: UnsafeRawBufferPointer) -> Void in
            if let address = bufferPointer.baseAddress {
                buffer.frameLength = AVAudioFrameCount(data.count / MemoryLayout<Float>.size)
                let audioBuffer = buffer.floatChannelData![0]
                memcpy(audioBuffer, address, data.count)
            }
        }
        
        // Update the peer's audio levels
        peerAudioData.updateWithBuffer(buffer)
        
        // Get or create a player node for this peer
        if let existingNode = peerPlayerNodes[peer] {
            // Use existing player node
            existingNode.scheduleBuffer(buffer, at: nil, options: .interruptsAtLoop, completionHandler: nil)
        } else {
            // Create new player node
            let playerNode = AVAudioPlayerNode()
            
            // Remember to attach the node BEFORE connecting it
            audioEngine.attach(playerNode)
            
            // Connect with the proper format
            audioEngine.connect(playerNode, to: mixerNode, format: format)
            
            // Store for future use
            peerPlayerNodes[peer] = playerNode
            
            // Start playing and schedule buffer
            playerNode.play()
            playerNode.scheduleBuffer(buffer, at: nil, options: .interruptsAtLoop, completionHandler: nil)
            
            print("Created new player node for peer: \(peer.displayName)")
        }
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
