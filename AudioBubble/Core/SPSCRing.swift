import Synchronization

/// Single-producer / single-consumer ring of Float samples.
///
/// Safe to use from a real-time thread: no locks, no allocation after init.
/// Exactly one thread may call `write`, and exactly one (other) thread may call `read`/`discard`.
nonisolated final class SampleRing: @unchecked Sendable {
    let capacity: Int
    private let mask: Int
    private let storage: UnsafeMutablePointer<Float>
    /// Total samples ever written. Only the producer stores it.
    private let writeCount = Atomic<Int>(0)
    /// Total samples ever read. Only the consumer stores it.
    private let readCount = Atomic<Int>(0)

    /// `capacity` is rounded up to a power of two.
    init(capacity: Int) {
        var size = 1
        while size < capacity { size <<= 1 }
        self.capacity = size
        mask = size - 1
        storage = .allocate(capacity: size)
        storage.initialize(repeating: 0, count: size)
    }

    deinit { storage.deallocate() }

    /// Samples ready to read. Accurate from the consumer, a lower bound from the producer.
    var availableToRead: Int {
        writeCount.load(ordering: .acquiring) - readCount.load(ordering: .acquiring)
    }

    /// Space left to write. Accurate from the producer, a lower bound from the consumer.
    var availableToWrite: Int { capacity - availableToRead }

    /// Producer. Writes as many samples as fit and returns how many were written.
    @discardableResult
    func write(_ source: UnsafePointer<Float>, count: Int) -> Int {
        let w = writeCount.load(ordering: .relaxed)
        let r = readCount.load(ordering: .acquiring)
        let n = min(count, capacity - (w - r))
        guard n > 0 else { return 0 }
        let start = w & mask
        let first = min(n, capacity - start)
        (storage + start).update(from: source, count: first)
        if n > first { storage.update(from: source + first, count: n - first) }
        writeCount.store(w + n, ordering: .releasing)
        return n
    }

    /// Consumer. Reads up to `count` samples and returns how many were read.
    @discardableResult
    func read(into destination: UnsafeMutablePointer<Float>, count: Int) -> Int {
        let r = readCount.load(ordering: .relaxed)
        let w = writeCount.load(ordering: .acquiring)
        let n = min(count, w - r)
        guard n > 0 else { return 0 }
        let start = r & mask
        let first = min(n, capacity - start)
        destination.update(from: storage + start, count: first)
        if n > first { (destination + first).update(from: storage, count: n - first) }
        readCount.store(r + n, ordering: .releasing)
        return n
    }

    /// Consumer. Drops everything currently readable.
    func discardAll() {
        readCount.store(writeCount.load(ordering: .acquiring), ordering: .releasing)
    }
}

/// Single-producer / single-consumer queue of fixed-size audio frames, as they arrive from the network.
///
/// The network queue pushes, the audio thread pops. No locks, no allocation after init.
nonisolated final class FrameQueue: @unchecked Sendable {
    let capacity: Int
    private let mask: Int
    private let samples: UnsafeMutablePointer<Int16>
    private let sequences: UnsafeMutablePointer<UInt32>
    private let silentFlags: UnsafeMutablePointer<Bool>
    private let writeCount = Atomic<Int>(0)
    private let readCount = Atomic<Int>(0)

    init(capacity: Int = 64) {
        var size = 1
        while size < capacity { size <<= 1 }
        self.capacity = size
        mask = size - 1
        samples = .allocate(capacity: size * AudioFormat.frameSamples)
        samples.initialize(repeating: 0, count: size * AudioFormat.frameSamples)
        sequences = .allocate(capacity: size)
        sequences.initialize(repeating: 0, count: size)
        silentFlags = .allocate(capacity: size)
        silentFlags.initialize(repeating: false, count: size)
    }

    deinit {
        samples.deallocate()
        sequences.deallocate()
        silentFlags.deallocate()
    }

    var count: Int { writeCount.load(ordering: .acquiring) - readCount.load(ordering: .acquiring) }

    /// Producer. `payload` holds `AudioFormat.frameSamples` little-endian Int16 samples, or is
    /// ignored when `silent` is true. Returns false (dropping the frame) when the queue is full.
    @discardableResult
    func push(sequence: UInt32, silent: Bool, payload: UnsafeRawBufferPointer) -> Bool {
        let w = writeCount.load(ordering: .relaxed)
        let r = readCount.load(ordering: .acquiring)
        guard w - r < capacity else { return false }
        let slot = w & mask
        sequences[slot] = sequence
        let hasPayload = !silent && payload.count >= AudioFormat.frameSamples * 2
        silentFlags[slot] = !hasPayload
        if hasPayload {
            let dst = samples + slot * AudioFormat.frameSamples
            for i in 0..<AudioFormat.frameSamples {
                dst[i] = Int16(littleEndian: payload.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))
            }
        }
        writeCount.store(w + 1, ordering: .releasing)
        return true
    }

    /// Consumer. Hands the oldest frame to `body` (samples are nil for a silent frame) and removes it.
    /// Returns false when empty.
    @discardableResult
    func pop(_ body: (_ sequence: UInt32, _ samples: UnsafePointer<Int16>?) -> Void) -> Bool {
        let r = readCount.load(ordering: .relaxed)
        let w = writeCount.load(ordering: .acquiring)
        guard w > r else { return false }
        let slot = r & mask
        body(sequences[slot], silentFlags[slot] ? nil : UnsafePointer(samples + slot * AudioFormat.frameSamples))
        readCount.store(r + 1, ordering: .releasing)
        return true
    }

    /// Consumer. Drops every queued frame.
    func discardAll() {
        readCount.store(writeCount.load(ordering: .acquiring), ordering: .releasing)
    }
}
