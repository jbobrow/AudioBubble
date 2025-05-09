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
    
    init(username: String) {
        self.myPeerID = MCPeerID(displayName: username)
        super.init()
        
        // Setup audio session
        setupAudioSession()
        
        // Start observing for headphone connection
        monitorHeadphonesConnection()
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
        
        // Only connect input to mixer if monitoring is enabled
        // This determines whether users hear themselves
        if isMonitoringEnabled, let inputNode = inputNode, let mixerNode = mixerNode, let format = format {
            audioEngine.connect(inputNode, to: mixerNode, format: format)
        }
        
        // Install tap on the input node to get audio data for sending to peers
        // This happens regardless of whether monitoring is enabled
        inputNode?.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            // Process and send audio data to peers
            self?.processAndSendAudioBuffer(buffer)
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
        
        // First, reset all connections
        audioEngine.disconnectNodeInput(mixerNode)
        
        // Configure format
        let format = inputNode.outputFormat(forBus: 0)
        
        // If monitoring is enabled, connect input to mixer so user can hear themselves
        // Otherwise, don't connect input to mixer (user won't hear themselves)
        if isMonitoringEnabled {
            audioEngine.connect(inputNode, to: mixerNode, format: format)
        }
        
        // Note: We're still tapping into the input node to capture audio data for sending to peers
        // This doesn't affect whether the user hears themselves
    }
    
    private func stopAudioEngine() {
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }
    
    private func processAndSendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Convert buffer to data and send to connected peers
        guard let session = session, !session.connectedPeers.isEmpty else { return }
        
        // Convert buffer to data (simplified)
        // In a real app, you'd compress this data and handle it more efficiently
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
        // Process received audio data (simplified)
        // In a real app, you'd decompress this data and handle it properly
        guard let audioEngine = audioEngine, let mixerNode = mixerNode else { return }
        
        // Convert data back to audio buffer and play through mixer
        // This is a simplified example and would need more work in a real app
        print("Received audio data from \(peer.displayName)")
        
        // In a real implementation, you would:
        // 1. Convert data back to an AVAudioPCMBuffer
        // 2. Create a player node for this buffer
        // 3. Connect player node to mixer
        // 4. Schedule buffer for playback
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
                    if !updatedBubble.participants.contains(peerID) {
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
