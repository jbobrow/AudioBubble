import Synchronization

/// The remote streams being played: one slot per bubble member, mixed on the audio thread.
///
/// Three threads touch it, each through its own door:
/// - main: `setMembers` assigns and frees slots;
/// - the network queue: `receive` pushes frames into a slot's lock-free queue (single producer);
/// - the audio thread: `mix` drains the queues into each slot's jitter buffer and renders (single consumer).
///
/// The audio thread never locks. The id→slot map is behind a mutex, used only by main and network.
///
/// Mixing runs in 128-sample hops so each stream can pass through its `SelfEchoSuppressor`, which
/// removes your own voice (picked up by their mic) using your mic as the reference.
nonisolated final class StreamTable: @unchecked Sendable {
    static let slotCount = 8
    static let maxFrames = 4_096

    final class Slot: @unchecked Sendable {
        let queue = FrameQueue(capacity: 64)
        let jitter = JitterBuffer()
        let suppressor: SelfEchoSuppressor
        let peer = Atomic<UInt64>(0)
        let active = Atomic<Bool>(false)
        /// Bumped whenever the slot is given to a new peer, so the audio thread resets it.
        let generation = Atomic<Int>(0)
        /// Written by the audio thread for the UI.
        let level = Atomic<UInt32>(0)
        let depthSamples = Atomic<Int>(0)
        /// True while your own voice is detected (and suppressed) in this stream.
        let echoDetected = Atomic<Bool>(false)
        // Audio thread only.
        var seenGeneration = -1
        var smoothedLevel: Float = 0

        init(reference: EchoReference) {
            suppressor = SelfEchoSuppressor(reference: reference)
        }
    }

    /// Your processed mic, written by the capture callback: the reference for echo suppression.
    let referenceRing = SampleRing(capacity: 8_192)
    private let echoReference = EchoReference()
    let slots: [Slot]
    private let map = Mutex<[UInt64: Int]>([:])

    private static let hop = SpectralTransform.hop
    private let micHop: UnsafeMutablePointer<Float>
    private let peerHop: UnsafeMutablePointer<Float>
    private let cleanHop: UnsafeMutablePointer<Float>
    /// Mixed output not yet handed to the speaker (less than one hop between callbacks).
    private let pending: UnsafeMutablePointer<Float>
    private var pendingCount = 0

    init() {
        let reference = echoReference
        slots = (0..<Self.slotCount).map { _ in Slot(reference: reference) }
        func buffer(_ count: Int) -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: count)
            p.initialize(repeating: 0, count: count)
            return p
        }
        micHop = buffer(Self.hop)
        peerHop = buffer(Self.hop)
        cleanHop = buffer(Self.hop)
        pending = buffer(Self.maxFrames + 2 * Self.hop)
    }

    deinit {
        for p in [micHop, peerHop, cleanHop, pending] { p.deallocate() }
    }

    // MARK: Main thread

    /// Makes the set of played streams exactly `members` (at most `slotCount`).
    func setMembers(_ members: Set<UInt64>) {
        map.withLock { map in
            for (peer, index) in map where !members.contains(peer) {
                map[peer] = nil
                slots[index].active.store(false, ordering: .releasing)
            }
            for peer in members where map[peer] == nil {
                guard let index = slots.indices.first(where: { i in !map.values.contains(i) }) else { break }
                let slot = slots[index]
                slot.peer.store(peer, ordering: .relaxed)
                slot.generation.add(1, ordering: .relaxed)
                slot.level.store(0, ordering: .relaxed)
                slot.depthSamples.store(0, ordering: .relaxed)
                slot.active.store(true, ordering: .releasing)
                map[peer] = index
            }
        }
    }

    /// Peak output level of a peer, 0...1, smoothed for display.
    func level(of peer: UInt64) -> Float {
        guard let slot = slot(for: peer) else { return 0 }
        return Float(bitPattern: slot.level.load(ordering: .relaxed))
    }

    /// Whether your own voice is being removed from a peer's stream.
    func isSuppressingEcho(from peer: UInt64) -> Bool {
        slot(for: peer)?.echoDetected.load(ordering: .relaxed) ?? false
    }

    /// Current jitter-buffer depth of a peer's stream, in milliseconds.
    func depthMilliseconds(of peer: UInt64) -> Double? {
        guard let slot = slot(for: peer) else { return nil }
        return AudioFormat.milliseconds(samples: slot.depthSamples.load(ordering: .relaxed))
    }

    private func slot(for peer: UInt64) -> Slot? {
        map.withLock { $0[peer] }.map { slots[$0] }
    }

    // MARK: Network queue

    /// Queues a received frame. Frames from peers outside the bubble are ignored.
    func receive(from peer: UInt64, sequence: UInt32, silent: Bool, payload: UnsafeRawBufferPointer) {
        guard let slot = slot(for: peer) else { return }
        slot.queue.push(sequence: sequence, silent: silent, payload: payload)
    }

    // MARK: Audio thread

    /// Renders the mix of every active stream into `out`. Real-time safe.
    func mix(into out: UnsafeMutablePointer<Float>, count: Int) {
        let n = min(count, Self.maxFrames)
        while pendingCount < n { mixHop(into: pending + pendingCount) }
        out.update(from: pending, count: n)
        pendingCount -= n
        if pendingCount > 0 { pending.update(from: pending + n, count: pendingCount) }
        if count > n { (out + n).update(repeating: 0, count: count - n) }
    }

    private func mixHop(into out: UnsafeMutablePointer<Float>) {
        let hop = Self.hop
        // The mic hop captured alongside this output. Input and output run in lockstep, so the
        // ring holds about one callback; drop any excess so the reference stays current.
        while referenceRing.availableToRead > 8 * hop { referenceRing.read(into: micHop, count: hop) }
        let got = referenceRing.read(into: micHop, count: hop)
        if got < hop { (micHop + got).update(repeating: 0, count: hop - got) }
        echoReference.process(micHop)

        out.update(repeating: 0, count: hop)
        for slot in slots {
            let generation = slot.generation.load(ordering: .acquiring)
            guard slot.active.load(ordering: .acquiring) else {
                // Keep the queue from filling up with stale frames.
                slot.queue.discardAll()
                continue
            }
            if generation != slot.seenGeneration {
                slot.seenGeneration = generation
                slot.queue.discardAll()
                slot.jitter.reset()
                slot.suppressor.reset()
                slot.smoothedLevel = 0
            }
            let jitter = slot.jitter
            while slot.queue.pop({ sequence, samples in jitter.insert(sequence: sequence, samples: samples) }) {}

            jitter.render(into: peerHop, count: hop)
            slot.suppressor.process(peerHop, into: cleanHop)
            var peak: Float = 0
            for i in 0..<hop {
                let s = cleanHop[i]
                out[i] += s
                peak = max(peak, abs(s))
            }
            // Fast attack, slow release.
            slot.smoothedLevel = peak > slot.smoothedLevel ? peak : slot.smoothedLevel * 0.955 + peak * 0.045
            slot.level.store(slot.smoothedLevel.bitPattern, ordering: .relaxed)
            slot.depthSamples.store(jitter.lastLevel, ordering: .relaxed)
            slot.echoDetected.store(slot.suppressor.echoDetected, ordering: .relaxed)
        }
        SoftLimiter.process(out, count: hop)
        pendingCount += hop
    }
}
