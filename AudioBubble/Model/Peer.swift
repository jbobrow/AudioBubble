import Foundation

/// Someone nearby, as last described by their hello.
struct Peer: Identifiable, Equatable {
    let id: UInt64
    var name: String
    var hue: Double
    var bubble: UUID?
    /// Our monotonic clock when their last hello arrived.
    var lastSeen: UInt64
    /// Their clock value from that hello, echoed back in ours.
    var lastHelloTime: UInt64
    /// Smoothed round-trip time, milliseconds.
    var rttMilliseconds: Double?
    /// Whether they're joined to a Wi-Fi network.
    var onWiFi = false
    /// Emoji shown in their bubble, if they chose one.
    var emoji: String?
    /// Version of their avatar image (Memoji), if they have one.
    var avatarVersion: UInt32?
    /// The interface our link to them uses, e.g. "awdl0" (direct) or "en0" (through a network).
    var linkInterface: String?

    /// True when audio goes straight between the two phones, with no access point in between.
    var isDirect: Bool? { linkInterface.map(MeshTransport.isPeerToPeer(interfaceName:)) }

    static let presenceTimeout: UInt64 = 5_000_000   // µs without a hello before someone is gone

    func isPresent(now: UInt64) -> Bool { now &- lastSeen < Self.presenceTimeout }
}

struct IncomingInvite: Equatable, Identifiable {
    let id: UUID
    let from: UInt64
    let bubble: UUID
    let received: Date
}

struct OutgoingInvite: Equatable {
    let id: UUID
    let bubble: UUID
    let sent: Date
}

/// The parts of mouth-to-ear latency from one member, in milliseconds.
struct LatencyBreakdown: Equatable {
    /// One way over the air: half the measured round trip.
    var network: Double
    /// Audio waiting in our jitter buffer.
    var buffer: Double
    /// Framing (5 ms) and echo suppression (2.7 ms).
    var processing: Double
    /// Mic and speaker latency reported by iOS (Bluetooth headphones add a lot here).
    var hardware: Double

    var total: Double { network + buffer + processing + hardware }
}
