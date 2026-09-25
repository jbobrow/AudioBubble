/// Adaptive jitter buffer for one remote peer. Every method runs on the audio thread.
///
/// - Frames are stored by sequence number, so reordered packets land in place.
/// - A frame is declared lost only when its audio is needed *and* a later frame has arrived.
///   If nothing later has arrived, the stream is merely late: playback stalls on concealment
///   instead of skipping ahead, so the late audio is still played when it shows up.
/// - The controller steers the *minimum* buffer level (measured after each render) toward a safety
///   margin. Underruns and late packets raise the margin; clean periods lower it.
/// - Excess latency and clock drift are removed by playing up to 1 % faster or slower through a
///   cubic resampler. A hard cap drops frames only if the buffer ever exceeds `maxLevel`.
///
/// Real-time safe: all storage is allocated in `init`.
nonisolated final class JitterBuffer {
    struct Statistics: Equatable {
        var received = 0
        var played = 0
        var lost = 0
        var late = 0
        var underruns = 0
        var droppedForLatency = 0
    }

    enum State { case buffering, playing }

    static let minMargin = AudioFormat.samples(ms: 2.5)
    static let maxMargin = AudioFormat.samples(ms: 150)
    /// Above this the oldest audio is dropped outright (the resampler handles everything below it).
    static let maxLevel = AudioFormat.samples(ms: 200)
    static let maxRatioOffset = 0.01
    static let controlWindow = AudioFormat.samples(ms: 500)
    static let marginDecayInterval = AudioFormat.samples(ms: 10_000)

    let capacity: Int
    private let frameSamples = AudioFormat.frameSamples
    private let slotSamples: UnsafeMutablePointer<Int16>
    private let slotSequence: UnsafeMutablePointer<UInt32>
    private let slotState: UnsafeMutablePointer<UInt8>   // 0 empty, 1 audio, 2 silent

    private(set) var state = State.buffering
    private var hasSequence = false
    /// Next frame to decode.
    private(set) var playSequence: UInt32 = 0
    /// Newest frame received.
    private var highestSequence: UInt32 = 0
    private var hasFramesAhead = false

    private let concealer = PacketLossConcealer()
    /// Playback is waiting on concealment for `stallSequence`, which has not arrived yet.
    private var stalled = false
    private var stallSequence: UInt32 = 0

    // Resampler FIFO: decoded input samples; `readPosition` is the fractional index of the next output.
    private static let fifoCapacity = 8_192
    private let fifo: UnsafeMutablePointer<Float>
    private var fifoCount = 0
    private var readPosition = 0.0

    // Control
    private(set) var margin = JitterBuffer.minMargin
    private(set) var ratio = 1.0
    private var targetRatio = 1.0
    /// Integral term of the rate controller: the estimated clock drift between the two devices.
    private(set) var driftEstimate = 0.0
    private var windowMin = Int.max
    private var windowElapsed = 0
    private var cleanElapsed = 0
    private var raisedThisWindow = false

    private(set) var statistics = Statistics()
    /// Buffer level after the last render, in samples.
    private(set) var lastLevel = 0

    init(capacity: Int = 64) {
        self.capacity = capacity
        slotSamples = .allocate(capacity: capacity * AudioFormat.frameSamples)
        slotSamples.initialize(repeating: 0, count: capacity * AudioFormat.frameSamples)
        slotSequence = .allocate(capacity: capacity)
        slotSequence.initialize(repeating: 0, count: capacity)
        slotState = .allocate(capacity: capacity)
        slotState.initialize(repeating: 0, count: capacity)
        fifo = .allocate(capacity: Self.fifoCapacity)
        fifo.initialize(repeating: 0, count: Self.fifoCapacity)
        resetResampler()
    }

    deinit {
        slotSamples.deallocate()
        slotSequence.deallocate()
        slotState.deallocate()
        fifo.deallocate()
    }

    /// Forgets the stream entirely (new peer, or the sender restarted).
    func reset() {
        slotState.update(repeating: 0, count: capacity)
        state = .buffering
        hasSequence = false
        hasFramesAhead = false
        stalled = false
        concealer.reset()
        resetResampler()
        margin = Self.minMargin
        ratio = 1
        targetRatio = 1
        driftEstimate = 0
        windowMin = .max
        windowElapsed = 0
        cleanElapsed = 0
        raisedThisWindow = false
        statistics = Statistics()
        lastLevel = 0
    }

    private func resetResampler() {
        // One sample of history before the read position, for the cubic interpolator.
        fifo[0] = 0
        fifoCount = 1
        readPosition = 1
    }

    // MARK: Input

    /// Stores a received frame. `samples` is nil for a silent frame.
    func insert(sequence: UInt32, samples: UnsafePointer<Int16>?) {
        statistics.received += 1
        if !hasSequence {
            hasSequence = true
            playSequence = sequence
            highestSequence = sequence
        }
        var ahead = Int(Int32(bitPattern: sequence &- playSequence))
        if ahead < 0 {
            if state == .buffering && statistics.played == 0 && ahead > -capacity / 4 {
                // Not started yet and this frame came in out of order: start from it instead.
                playSequence = sequence
                ahead = 0
            } else if ahead > -capacity * 4 {
                statistics.late += 1
                raiseMargin()
                return
            } else {
                // Far in the past: the sender restarted its sequence numbers.
                restart(at: sequence)
                ahead = 0
            }
        } else if ahead >= capacity {
            if ahead < capacity * 4 {
                // Too far ahead to fit: skip forward to make room.
                let newStart = sequence &- UInt32(capacity / 2)
                dropUntil(newStart)
            } else {
                restart(at: sequence)
            }
            ahead = Int(Int32(bitPattern: sequence &- playSequence))
        }

        let slot = Int(sequence % UInt32(capacity))
        slotSequence[slot] = sequence
        if let samples {
            (slotSamples + slot * frameSamples).update(from: samples, count: frameSamples)
            slotState[slot] = 1
        } else {
            slotState[slot] = 2
        }
        if !hasFramesAhead || Int32(bitPattern: sequence &- highestSequence) > 0 {
            highestSequence = sequence
        }
        hasFramesAhead = true
    }

    private func restart(at sequence: UInt32) {
        slotState.update(repeating: 0, count: capacity)
        concealer.beginIfNeeded()
        playSequence = sequence
        highestSequence = sequence
        hasFramesAhead = false
        state = .buffering
    }

    /// Frames from `playSequence` through the newest received, including holes.
    private var framesAhead: Int {
        guard hasFramesAhead else { return 0 }
        let n = Int(Int32(bitPattern: highestSequence &- playSequence)) + 1
        return max(0, n)
    }

    /// Samples of audio buffered but not yet played.
    var level: Int {
        framesAhead * frameSamples + max(0, fifoCount - Int(readPosition) - 1)
    }

    // MARK: Output

    /// Renders `count` samples of this peer's audio into `out` (overwriting it).
    func render(into out: UnsafeMutablePointer<Float>, count: Int) {
        var done = 0
        while done < count {
            let chunk = min(1_024, count - done)
            renderChunk(into: out + done, count: chunk)
            done += chunk
        }
    }

    private func renderChunk(into out: UnsafeMutablePointer<Float>, count: Int) {
        if state == .buffering {
            if framesAhead > 0 && level >= margin + count {
                state = .playing
                resetResampler()
                ratio = 1 + driftEstimate
                targetRatio = ratio
            } else {
                out.update(repeating: 0, count: count)
                return
            }
        }

        if level > Self.maxLevel { trimLatency() }

        // Slew the playout rate toward its target: at most 0.05 % per callback.
        let step = 0.0005
        ratio += max(-step, min(step, targetRatio - ratio))

        for i in 0..<count {
            var index = Int(readPosition)
            while index + 2 >= fifoCount { pullFrame() }
            index = Int(readPosition)
            let t = Float(readPosition - Double(index))
            let x0 = fifo[index - 1], x1 = fifo[index], x2 = fifo[index + 1], x3 = fifo[index + 2]
            // Catmull-Rom cubic
            let a = 3 * (x1 - x2) + x3 - x0
            let b = 2 * x0 - 5 * x1 + 4 * x2 - x3
            out[i] = x1 + 0.5 * t * (x2 - x0 + t * (b + t * a))
            readPosition += ratio
        }
        compactFIFO()

        if concealer.isSilent && stalled {
            // Nothing has arrived for a while: wait for the stream to come back.
            state = .buffering
        }
        updateControl(renderedSamples: count)
    }

    private func compactFIFO() {
        let drop = Int(readPosition) - 1
        guard drop > 0 else { return }
        let keep = fifoCount - drop
        if keep > 0 { fifo.update(from: fifo + drop, count: keep) }
        fifoCount = keep
        readPosition -= Double(drop)
    }

    /// Appends the next frame of input to the resampler FIFO: real audio, or concealment.
    private func pullFrame() {
        let dst = fifo + fifoCount
        fifoCount += frameSamples
        let slot = Int(playSequence % UInt32(capacity))

        if slotState[slot] != 0 && slotSequence[slot] == playSequence {
            if slotState[slot] == 1 {
                let src = slotSamples + slot * frameSamples
                for i in 0..<frameSamples { dst[i] = Float(src[i]) * (1 / 32_768) }
            } else {
                dst.update(repeating: 0, count: frameSamples)
            }
            slotState[slot] = 0
            concealer.play(dst, count: frameSamples)
            if stalled && playSequence == stallSequence {
                // The frame we stalled for did arrive, just late: the margin was too small.
                raiseMargin()
            }
            advance()
            statistics.played += 1
            stalled = false
            return
        }

        concealer.conceal(into: dst, count: frameSamples)
        if framesAhead > 1 {
            // A later frame is here, so this one is lost: skip it.
            statistics.lost += 1
            advance()
            stalled = false
        } else {
            // Nothing newer yet: the stream is late, not lossy. Stall on concealment. Whether the
            // margin was too small is decided when we learn if this frame was late or lost.
            if !stalled {
                statistics.underruns += 1
                stallSequence = playSequence
            }
            stalled = true
        }
    }

    private func advance() {
        let wasLast = playSequence == highestSequence
        playSequence &+= 1
        if wasLast { hasFramesAhead = false }
    }

    /// Discards frames before `sequence`, crossfading across the jump.
    private func dropUntil(_ sequence: UInt32) {
        while Int32(bitPattern: sequence &- playSequence) > 0 {
            let slot = Int(playSequence % UInt32(capacity))
            if slotState[slot] != 0 && slotSequence[slot] == playSequence { slotState[slot] = 0 }
            advance()
            statistics.droppedForLatency += 1
        }
        if !hasFramesAhead { highestSequence = playSequence &- 1 }
        concealer.beginIfNeeded()
    }

    private func trimLatency() {
        let target = margin + AudioFormat.samples(ms: 20)
        let excessFrames = (level - target) / frameSamples
        guard excessFrames > 0 else { return }
        dropUntil(playSequence &+ UInt32(min(excessFrames, framesAhead)))
    }

    // MARK: Control

    private func raiseMargin() {
        cleanElapsed = 0
        guard !raisedThisWindow else { return }
        raisedThisWindow = true
        margin = min(Self.maxMargin, margin + max(Self.minMargin, margin / 2))
    }

    private func updateControl(renderedSamples: Int) {
        lastLevel = level
        windowMin = min(windowMin, lastLevel)
        windowElapsed += renderedSamples
        cleanElapsed += renderedSamples

        if cleanElapsed >= Self.marginDecayInterval {
            cleanElapsed = 0
            margin = max(Self.minMargin, margin * 85 / 100)
        }

        guard windowElapsed >= Self.controlWindow else { return }
        // PI control of the window's minimum level. The integral term tracks clock drift, so the
        // level settles on the margin instead of a drift-dependent offset from it.
        let errorMs = AudioFormat.milliseconds(samples: windowMin - margin)
        if abs(errorMs) < 10 {
            driftEstimate += errorMs * 0.000_2
            driftEstimate = max(-Self.maxRatioOffset, min(Self.maxRatioOffset, driftEstimate))
        }
        // Proportional: 10 ms of error → the full 1 %. A small deadband above the margin keeps the
        // rate steady when the level is just right; below the margin there is none.
        let proportional = errorMs > 0 && errorMs < 1 ? 0 : errorMs / 10 * Self.maxRatioOffset
        targetRatio = 1 + max(-Self.maxRatioOffset, min(Self.maxRatioOffset, proportional + driftEstimate))
        windowMin = .max
        windowElapsed = 0
        raisedThisWindow = false
    }
}
