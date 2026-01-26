import Foundation
import Combine
import MultipeerConnectivity

/// Represents a discoverable audio bubble (room)
struct BubbleInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let hostPeerID: MCPeerID
    let hostName: String
    let participantCount: Int
    let createdAt: Date

    /// Discovery info keys for MultipeerConnectivity
    enum DiscoveryKeys {
        static let bubbleID = "bubbleID"
        static let bubbleName = "bubbleName"
        static let hostName = "hostName"
        static let participantCount = "participantCount"
        static let createdAt = "createdAt"
    }

    /// Create from discovery info dictionary
    init?(peerID: MCPeerID, discoveryInfo: [String: String]?) {
        guard let info = discoveryInfo,
              let bubbleID = info[DiscoveryKeys.bubbleID],
              let bubbleName = info[DiscoveryKeys.bubbleName],
              let hostName = info[DiscoveryKeys.hostName],
              let countStr = info[DiscoveryKeys.participantCount],
              let count = Int(countStr) else {
            return nil
        }

        self.id = bubbleID
        self.name = bubbleName
        self.hostPeerID = peerID
        self.hostName = hostName
        self.participantCount = count

        if let createdStr = info[DiscoveryKeys.createdAt],
           let createdInterval = TimeInterval(createdStr) {
            self.createdAt = Date(timeIntervalSince1970: createdInterval)
        } else {
            self.createdAt = Date()
        }
    }

    /// Create a new bubble
    init(name: String, hostPeerID: MCPeerID, hostName: String) {
        self.id = UUID().uuidString
        self.name = name
        self.hostPeerID = hostPeerID
        self.hostName = hostName
        self.participantCount = 1
        self.createdAt = Date()
    }

    /// Convert to discovery info dictionary for advertising
    func toDiscoveryInfo(participantCount: Int) -> [String: String] {
        return [
            DiscoveryKeys.bubbleID: id,
            DiscoveryKeys.bubbleName: name,
            DiscoveryKeys.hostName: hostName,
            DiscoveryKeys.participantCount: String(participantCount),
            DiscoveryKeys.createdAt: String(createdAt.timeIntervalSince1970)
        ]
    }

    // Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: BubbleInfo, rhs: BubbleInfo) -> Bool {
        lhs.id == rhs.id
    }
}

/// Manages the current bubble session state
final class BubbleSession: ObservableObject {
    static let shared = BubbleSession()

    /// Current bubble info (nil if not in a bubble)
    @Published var currentBubble: BubbleInfo?

    /// Whether we are the host of the current bubble
    @Published var isHost: Bool = false

    /// Create a new bubble as host
    func createBubble(name: String, hostPeerID: MCPeerID, hostName: String) {
        let bubble = BubbleInfo(name: name, hostPeerID: hostPeerID, hostName: hostName)
        currentBubble = bubble
        isHost = true
    }

    /// Join an existing bubble
    func joinBubble(_ bubble: BubbleInfo) {
        currentBubble = bubble
        isHost = false
    }

    /// Leave the current bubble
    func leaveBubble() {
        currentBubble = nil
        isHost = false
    }

    private init() {}
}
