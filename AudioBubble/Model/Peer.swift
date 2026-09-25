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
