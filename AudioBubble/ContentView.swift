import SwiftUI
import MultipeerConnectivity

struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    @StateObject private var networkManager = NetworkManager()
    
    @State private var isActive = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    // Header
                    VStack(spacing: 10) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.blue)
                        
                        Text("Audio Bubble")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Low-Latency Voice Chat")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 40)
                    
                    // Connection Status Card
                    VStack(spacing: 15) {
                        HStack {
                            Circle()
                                .fill(networkManager.isConnected ? Color.green : Color.gray)
                                .frame(width: 12, height: 12)
                            
                            Text(networkManager.connectionStatus)
                                .font(.headline)
                        }
                        
                        if !networkManager.connectedPeers.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Connected to:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                ForEach(networkManager.connectedPeers, id: \.self) { peer in
                                    HStack {
                                        Image(systemName: "person.fill")
                                            .foregroundColor(.blue)
                                        Text(peer.displayName)
                                            .font(.body)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 5)
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(15)
                    .shadow(radius: 5)
                    .padding(.horizontal)
                    
                    // Audio Level Indicator
                    if isActive {
                        VStack(spacing: 10) {
                            Text("Audio Level")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 30)
                                
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [.green, .yellow, .red]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(0, CGFloat(audioManager.audioLevel) * 300), height: 30)
                                    .animation(.linear(duration: 0.1), value: audioManager.audioLevel)
                            }
                            .frame(width: 300)
                        }
                        .padding()
                        .background(Color.white.opacity(0.9))
                        .cornerRadius(15)
                        .shadow(radius: 5)
                    }
                    
                    // Network Stats
                    if isActive && networkManager.isConnected {
                        VStack(spacing: 8) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Latency")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.1f ms", networkManager.latencyMs))
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .foregroundColor(latencyColor(networkManager.latencyMs))
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing) {
                                    Text("Bandwidth")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(formatBytes(networkManager.bytesSent + networkManager.bytesReceived))
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.9))
                        .cornerRadius(15)
                        .shadow(radius: 5)
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                    
                    // Main Action Button
                    Button(action: toggleActive) {
                        HStack(spacing: 15) {
                            Image(systemName: isActive ? "stop.circle.fill" : "play.circle.fill")
                                .font(.system(size: 30))
                            
                            Text(isActive ? "Stop Audio Bubble" : "Start Audio Bubble")
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isActive ? Color.red : Color.blue)
                        .cornerRadius(15)
                        .shadow(radius: 10)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            setupAudioCallbacks()
        }
    }
    
    // MARK: - Actions
    
    private func toggleActive() {
        isActive.toggle()
        
        if isActive {
            networkManager.startHosting()
            audioManager.startRecording()
        } else {
            audioManager.stopRecording()
            networkManager.stopHosting()
        }
    }
    
    private func setupAudioCallbacks() {
        // When audio is captured, send it via network
        audioManager.onAudioData = { data in
            networkManager.sendAudioData(data)
        }
        
        // When audio is received from network, play it
        networkManager.onAudioDataReceived = { data, peer in
            audioManager.receiveAudioData(data)
        }
    }
    
    // MARK: - Helper Functions
    
    private func latencyColor(_ latency: Double) -> Color {
        if latency < 50 {
            return .green
        } else if latency < 100 {
            return .yellow
        } else {
            return .red
        }
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        } else {
            let mb = kb / 1024.0
            return String(format: "%.1f MB", mb)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
