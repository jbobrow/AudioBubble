import Foundation
import MultipeerConnectivity
import SwiftUI

/// Represents information about a connected peer in the audio bubble
class PeerInfo: ObservableObject, Identifiable {
    let id: MCPeerID

    /// Display name for this peer
    var displayName: String { id.displayName }

    /// Current audio level (0.0 to 1.0)
    @Published var audioLevel: Float = 0.0

    /// Whether this peer is currently speaking (audio level above threshold)
    @Published var isSpeaking: Bool = false

    /// Timestamp of when peer joined
    let joinedAt: Date

    /// Timestamp of last audio received from this peer
    @Published var lastAudioAt: Date?

    /// Color assigned to this peer for UI
    let color: Color

    /// Speaking threshold - audio level above this is considered "speaking"
    private let speakingThreshold: Float = 0.02

    /// Time after which peer is no longer considered speaking (seconds)
    private let speakingTimeout: TimeInterval = 0.3

    // Timer for speaking timeout
    private var speakingTimer: Timer?

    init(peerID: MCPeerID, color: Color) {
        self.id = peerID
        self.joinedAt = Date()
        self.color = color
    }

    /// Update audio level and speaking status
    func updateAudioLevel(_ level: Float) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Smooth the audio level with exponential moving average
            self.audioLevel = self.audioLevel * 0.3 + level * 0.7
            self.lastAudioAt = Date()

            // Update speaking status
            if self.audioLevel > self.speakingThreshold {
                self.isSpeaking = true

                // Reset the speaking timeout timer
                self.speakingTimer?.invalidate()
                self.speakingTimer = Timer.scheduledTimer(withTimeInterval: self.speakingTimeout, repeats: false) { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.isSpeaking = false
                    }
                }
            }
        }
    }

    /// Reset audio state (when peer disconnects and reconnects)
    func reset() {
        DispatchQueue.main.async { [weak self] in
            self?.audioLevel = 0.0
            self?.isSpeaking = false
            self?.lastAudioAt = nil
            self?.speakingTimer?.invalidate()
        }
    }
}

// MARK: - Hashable & Equatable

extension PeerInfo: Hashable {
    static func == (lhs: PeerInfo, rhs: PeerInfo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Color Assignment

/// Manages color assignment for peers
class PeerColorManager {
    static let shared = PeerColorManager()

    private let availableColors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .cyan, .mint, .indigo, .teal, .yellow
    ]

    private var assignedColors: [MCPeerID: Color] = [:]
    private var colorIndex = 0

    private init() {}

    func colorForPeer(_ peerID: MCPeerID) -> Color {
        if let existingColor = assignedColors[peerID] {
            return existingColor
        }

        let color = availableColors[colorIndex % availableColors.count]
        colorIndex += 1
        assignedColors[peerID] = color
        return color
    }

    func reset() {
        assignedColors.removeAll()
        colorIndex = 0
    }
}
