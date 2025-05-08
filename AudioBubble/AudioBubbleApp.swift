//
//  AudioBubbleApp.swift
//  AudioBubble
//
//  Created by Jonathan Bobrow on 5/8/25.
//

import SwiftUI
import MultipeerConnectivity
import AVFoundation
import Combine

// MARK: - Models

struct AudioBubble: Identifiable {
    let id: String
    let name: String
    let hostPeerID: MCPeerID
    var participants: [MCPeerID] = []
}

// MARK: - View Models

class BubbleSessionManager: NSObject, ObservableObject {
    // Published properties to update UI
    @Published var availableBubbles: [AudioBubble] = []
    @Published var currentBubble: AudioBubble?
    @Published var isHost = false
    @Published var isConnected = false
    @Published var isHeadphonesConnected = false
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
        
        // Connect input to mixer
        if let inputNode = inputNode, let mixerNode = mixerNode, let format = format {
            audioEngine.connect(inputNode, to: mixerNode, format: format)
        }
        
        // Install tap on the input node to get audio data
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
        guard let audioEngine = audioEngine else { return }
        
        // Convert data back to audio buffer and play
        // This is a simplified example and would need more work in a real app
        print("Received audio data from \(peer.displayName)")
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

// MARK: - Views

struct ContentView: View {
    @State private var username = ""
    @State private var isLoggedIn = false
    
    var body: some View {
        if isLoggedIn {
            MainView(username: username)
        } else {
            LoginView(username: $username, onLogin: {
                isLoggedIn = true
            })
        }
    }
}

struct LoginView: View {
    @Binding var username: String
    var onLogin: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Audio Bubble")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Connect with nearby friends using audio bubbles")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            TextField("Your Name", text: $username)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            Button("Join") {
                if !username.isEmpty {
                    onLogin()
                }
            }
            .disabled(username.isEmpty)
            .padding()
            .background(username.isEmpty ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .padding()
    }
}

struct MainView: View {
    let username: String
    @StateObject private var sessionManager: BubbleSessionManager
    @State private var bubbleName = ""
    @State private var showingCreateBubble = false
    
    init(username: String) {
        self.username = username
        _sessionManager = StateObject(wrappedValue: BubbleSessionManager(username: username))
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if !sessionManager.isHeadphonesConnected {
                    HeadphoneWarningView()
                }
                
                if let currentBubble = sessionManager.currentBubble {
                    BubbleDetailView(bubble: currentBubble, isHost: sessionManager.isHost) {
                        sessionManager.leaveBubble()
                    }
                } else {
                    // Available bubbles list
                    List {
                        Section(header: Text("Available Bubbles")) {
                            if sessionManager.availableBubbles.isEmpty {
                                Text("No bubbles found nearby")
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(sessionManager.availableBubbles) { bubble in
                                    BubbleRowView(bubble: bubble) {
                                        sessionManager.joinBubble(bubble)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                }
            }
            .navigationTitle("Audio Bubble")
            .toolbar {
                if sessionManager.currentBubble == nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            showingCreateBubble = true
                        }) {
                            Label("Create", systemImage: "plus")
                        }
                        .disabled(!sessionManager.isHeadphonesConnected)
                    }
                }
            }
            .sheet(isPresented: $showingCreateBubble) {
                CreateBubbleView(bubbleName: $bubbleName) {
                    sessionManager.createBubble(name: bubbleName)
                    showingCreateBubble = false
                    bubbleName = ""
                }
            }
            .alert(item: Binding<AlertItem?>(
                get: {
                    sessionManager.errorMessage.map { AlertItem(message: $0) }
                },
                set: { _ in
                    sessionManager.errorMessage = nil
                }
            )) { alertItem in
                Alert(title: Text("Error"), message: Text(alertItem.message))
            }
            .onAppear {
                sessionManager.setupSession()
            }
        }
    }
}

struct AlertItem: Identifiable {
    let id = UUID()
    let message: String
}

struct HeadphoneWarningView: View {
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Please connect headphones to participate")
                    .font(.headline)
                    .foregroundColor(.orange)
            }
            .padding()
            .background(Color.orange.opacity(0.2))
            .cornerRadius(10)
        }
        .padding(.horizontal)
    }
}

struct BubbleRowView: View {
    let bubble: AudioBubble
    var onJoin: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(bubble.name)
                    .font(.headline)
                Text("Host: \(bubble.hostPeerID.displayName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("\(bubble.participants.count + 1) participants")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Join") {
                onJoin()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .padding(.vertical, 4)
    }
}

struct BubbleDetailView: View {
    let bubble: AudioBubble
    let isHost: Bool
    var onLeave: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            VStack {
                Text(bubble.name)
                    .font(.title)
                    .fontWeight(.bold)
                
                if isHost {
                    Text("You are the host")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
                
                Text("Active Conversation")
                    .font(.headline)
                    .padding(.top)
                
                // Animated sound waves
                HStack(spacing: 4) {
                    ForEach(0..<5) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .frame(width: 4, height: 20)
                            .foregroundColor(.blue)
                            .opacity(0.8)
                            .animation(
                                Animation.easeInOut(duration: 0.5)
                                    .repeatForever()
                                    .delay(Double.random(in: 0...0.5)),
                                value: UUID()
                            )
                    }
                }
                .padding()
                
                // Participants
                VStack(alignment: .leading) {
                    Text("Participants:")
                        .font(.headline)
                    
                    ForEach([bubble.hostPeerID] + bubble.participants, id: \.self) { peer in
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(.blue)
                            Text(peer.displayName)
                                .fontWeight(peer == bubble.hostPeerID ? .bold : .regular)
                            
                            if peer == bubble.hostPeerID {
                                Text("(Host)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            // Animated speaking indicator (simplified)
                            Image(systemName: "waveform")
                                .foregroundColor(.green)
                                .opacity(Double.random(in: 0...1) > 0.7 ? 1.0 : 0.0)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
            }
            
            Spacer()
            
            Button(action: onLeave) {
                Text("Leave Bubble")
                    .fontWeight(.bold)
                    .padding()
                    .frame(width: 200)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
}

struct CreateBubbleView: View {
    @Binding var bubbleName: String
    @Environment(\.presentationMode) var presentationMode
    var onCreate: () -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Bubble Details")) {
                    TextField("Bubble Name", text: $bubbleName)
                }
                
                Section {
                    Button("Create Bubble") {
                        onCreate()
                    }
                    .disabled(bubbleName.isEmpty)
                }
            }
            .navigationTitle("Create Bubble")
            .navigationBarItems(trailing: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

@main
struct AudioBubbleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
