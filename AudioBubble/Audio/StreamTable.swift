import Synchronization

/// The remote streams being played: one slot per bubble member, mixed on the audio thread.
///
/// Three threads touch it, each through its own door:
/// - main: `setMembers` assigns and frees slots;
/// - the network queue: `receive` pushes frames into a slot's lock-free queue (single producer);
/// - the audio thread: `mix` drains the queues into each slot's jitter buffer and renders (single consumer).
///
/// The audio thread never locks. The id→slot map is behind a mutex, used only by main and network.
nonisolated final class StreamTable: @unchecked Sendable {
    static let slotCount = 8
    static let maxFrames = 4_096

    final class Slot: @unchecked Sendable {
        let queue = FrameQueue(capacity: 64)
        let jitter = JitterBuffer()
        let peer = Atomic<UInt64>(0)
        let active = Atomic<Bool>(false)
        /// Bumped whenever the slot is given to a new peer, so the audio thread resets it.
        let generation = Atomic<Int>(0)
        /// Written by the audio thread for the UI.
        let level = Atomic<UInt32>(0)
        let depthSamples = Atomic<Int>(0)
        // Audio thread only.
        var seenGeneration = -1
        var smoothedLevel: Float = 0
    }

    let slots: [Slot] = (0..<StreamTable.slotCount).map { _ in Slot() }
    private let map = Mutex<[UInt64: Int]>([:])
    private let scratch: UnsafeMutablePointer<Float>

    init() {
        scratch = .allocate(capacity: Self.maxFrames)
        scratch.initialize(repeating: 0, count: Self.maxFrames)
    }

    deinit { scratch.deallocate() }

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
        out.update(repeating: 0, count: count)
        let n = min(count, Self.maxFrames)
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
                slot.smoothedLevel = 0
            }
            let jitter = slot.jitter
            while slot.queue.pop({ sequence, samples in jitter.insert(sequence: sequence, samples: samples) }) {}

            jitter.render(into: scratch, count: n)
            var peak: Float = 0
            for i in 0..<n {
                let s = scratch[i]
                out[i] += s
                peak = max(peak, abs(s))
            }
            // Fast attack, slow release.
            slot.smoothedLevel = peak > slot.smoothedLevel ? peak : slot.smoothedLevel * 0.92 + peak * 0.08
            slot.level.store(slot.smoothedLevel.bitPattern, ordering: .relaxed)
            slot.depthSamples.store(jitter.lastLevel, ordering: .relaxed)
        }
        SoftLimiter.process(out, count: n)
    }
}
