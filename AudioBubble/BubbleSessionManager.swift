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
        private var threshold: Float = 0.03 // Silence threshold
        
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
            
            // Determine if audio is active based on threshold
            let newIsActive = rms > threshold
            
            // Only update if there's actual audio activity
            if newIsActive {
                // Generate new levels based on audio amplitude
                // Normalize to 0.0-1.0 range with some amplification for visibility
                let normalizedRms = min(rms * 5, 1.0) // Amplify but cap at 1.0
                
                // Create slightly varied levels for visual interest
                DispatchQueue.main.async {
                    self.levels = [
                        CGFloat(normalizedRms * Float.random(in: 0.7...1.0)),
                        CGFloat(normalizedRms * Float.random(in: 0.8...1.0)),
                        CGFloat(normalizedRms * Float.random(in: 0.9...1.0)),
                        CGFloat(normalizedRms * Float.random(in: 0.8...1.0)),
                        CGFloat(normalizedRms * Float.random(in: 0.7...1.0))
                    ]
                    self.isActive = true
                }
            } else if self.isActive {
                // If we were active but now silent, update state
                DispatchQueue.main.async {
                    self.isActive = false
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
        audioEngine = AVAudioEngine()
        
        guard let audioEngine = audioEngine else { return }
        
        inputNode = audioEngine.inputNode
        mixerNode = audioEngine.mainMixerNode
        
        // Configure audio format
        let format = inputNode?.outputFormat(forBus: 0)
        
        // Create a separate node for local input monitoring
        let monitorMixer = AVAudioMixerNode()
        audioEngine.attach(monitorMixer)
        
        // Always connect the input to the main mixer for capturing
        if let inputNode = inputNode, let mixerNode = mixerNode, let format = format {
            // Install tap on the input node to get audio data for sending to peers
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
                // Process and send audio data to peers
                self?.processAndSendAudioBuffer(buffer)
            }
            
            // Only connect input to monitor mixer if monitoring is enabled
            if isMonitoringEnabled {
                audioEngine.connect(inputNode, to: monitorMixer, format: format)
            }
            
            // Always connect monitor mixer to main mixer (the volume could be zero if no monitoring)
            audioEngine.connect(monitorMixer, to: mixerNode, format: format)
        }
        
        do {
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
        // Stop all player nodes
        for playerNode in peerPlayerNodes.values {
            playerNode.stop()
            audioEngine?.detach(playerNode)
        }
        peerPlayerNodes.removeAll()
        
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }
    
    private func processAndSendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Update local audio levels
        localAudioData.updateWithBuffer(buffer)
        
        // Rest of the existing code to send buffer to peers...
        guard let session = session, !session.connectedPeers.isEmpty else { return }
        
        guard let data = buffer.floatChannelData?[0] else { return }
        let dataSize = Int(buffer.frameLength) * MemoryLayout<Float>.size
        let audioData = Data(bytes: data, count: dataSize)
        
        do {
            try session.send(audioData, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            errorMessage = "Failed to send audio data: \(error.localizedDescription)"
        }
    }
    
    private func receiveAudioData(_ data: Data, fromPeer peer: MCPeerID) {
        // Get or create audio data for this peer
        let peerAudioData = getAudioDataForPeer(peer)
        
        // Convert data to audio buffer
        let bufferSize = data.count / MemoryLayout<Float>.size
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)
        
        guard let format = format,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(bufferSize)) else {
            print("Failed to create buffer")
            return
        }
        
        // Copy data into buffer
        data.withUnsafeBytes { (bufferPointer: UnsafeRawBufferPointer) -> Void in
            if let address = bufferPointer.baseAddress {
                buffer.frameLength = AVAudioFrameCount(bufferSize)
                let audioBuffer = buffer.floatChannelData![0]
                memcpy(audioBuffer, address, data.count)
            }
        }
        
        // Update the peer's audio levels
        peerAudioData.updateWithBuffer(buffer)
        
        // Process audio for playback
        guard let audioEngine = audioEngine, let mixerNode = mixerNode else {
            print("Audio engine or mixer not available")
            return
        }
        
        // Get or create a player node for this peer
        let playerNode: AVAudioPlayerNode
        if let existingNode = peerPlayerNodes[peer] {
            playerNode = existingNode
        } else {
            playerNode = AVAudioPlayerNode()
            audioEngine.attach(playerNode)
            audioEngine.connect(playerNode, to: mixerNode, format: format)
            peerPlayerNodes[peer] = playerNode
            
            // Start the player
            playerNode.play()
        }
        
        // Schedule the buffer for playback
        if playerNode.isPlaying {
            playerNode.scheduleBuffer(buffer, completionHandler: nil)
        } else {
            playerNode.play()
            playerNode.scheduleBuffer(buffer, completionHandler: nil)
        }
        
        print("Playing audio data from \(peer.displayName)")
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
