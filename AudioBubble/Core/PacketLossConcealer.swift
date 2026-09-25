/// Packet loss concealment by pitch-period repetition, in the spirit of G.711 Appendix I.
///
/// It keeps a history of everything that was played. When a frame is missing it estimates the pitch
/// period of the recent audio and repeats the last period (with an overlap-added seam so the loop is
/// smooth), holding full level for 10 ms and fading to silence by 60 ms. When real audio resumes it
/// crossfades from the concealment into it.
///
/// Real-time safe: all buffers are allocated in `init`.
nonisolated final class PacketLossConcealer {
    static let minPeriod = 120          // 2.5 ms, 400 Hz
    static let maxPeriod = 720          // 15 ms, ~67 Hz
    static let holdSamples = 480        // 10 ms at full level
    static let fadeEndSamples = 2_880   // silent after 60 ms
    static let resumeCrossfade = 96     // 2 ms

    private static let historySize = 2_048
    private let history: UnsafeMutablePointer<Float>
    private var historyCount = 0        // total samples ever pushed
    private let periodBuffer: UnsafeMutablePointer<Float>
    private var period = 0
    private var phase = 0

    /// True while generating (or ready to crossfade out of) concealment.
    private(set) var isConcealing = false
    /// Samples generated since concealment began.
    private(set) var concealedSamples = 0

    /// True once concealment has faded to silence.
    var isSilent: Bool { isConcealing && concealedSamples >= Self.fadeEndSamples }

    init() {
        history = .allocate(capacity: Self.historySize)
        history.initialize(repeating: 0, count: Self.historySize)
        periodBuffer = .allocate(capacity: Self.maxPeriod)
        periodBuffer.initialize(repeating: 0, count: Self.maxPeriod)
    }

    deinit {
        history.deallocate()
        periodBuffer.deallocate()
    }

    func reset() {
        history.update(repeating: 0, count: Self.historySize)
        historyCount = 0
        isConcealing = false
        concealedSamples = 0
    }

    /// Recent history sample, `back` samples before the newest (1 = newest).
    @inline(__always)
    private func past(_ back: Int) -> Float {
        guard back <= historyCount else { return 0 }
        return history[(historyCount - back) & (Self.historySize - 1)]
    }

    private func pushHistory(_ samples: UnsafePointer<Float>, count: Int) {
        for i in 0..<count {
            history[(historyCount + i) & (Self.historySize - 1)] = samples[i]
        }
        historyCount += count
    }

    /// Replaces a missing frame with concealment.
    func conceal(into out: UnsafeMutablePointer<Float>, count: Int) {
        if !isConcealing { begin() }
        for i in 0..<count { out[i] = nextConcealedSample() }
        pushHistory(out, count: count)
    }

    /// Starts concealment without producing output, so the next real frame is crossfaded
    /// from a continuation of what was playing (used when frames are dropped to cut latency).
    func beginIfNeeded() {
        if !isConcealing { begin() }
    }

    /// Hands over a real frame. If concealment was running, the start of the frame is crossfaded
    /// from the concealment, in place. The frame is then added to the history.
    func play(_ frame: UnsafeMutablePointer<Float>, count: Int) {
        if isConcealing {
            let n = min(Self.resumeCrossfade, count)
            for i in 0..<n {
                let w = Float(i + 1) / Float(n + 1)
                frame[i] = frame[i] * w + nextConcealedSample() * (1 - w)
            }
            isConcealing = false
        }
        pushHistory(frame, count: count)
    }

    @inline(__always)
    private func nextConcealedSample() -> Float {
        let gain: Float
        if concealedSamples < Self.holdSamples {
            gain = 1
        } else if concealedSamples < Self.fadeEndSamples {
            gain = 1 - Float(concealedSamples - Self.holdSamples) / Float(Self.fadeEndSamples - Self.holdSamples)
        } else {
            gain = 0
        }
        let s = periodBuffer[phase] * gain
        phase += 1
        if phase == period { phase = 0 }
        concealedSamples += 1
        return s
    }

    private func begin() {
        period = estimatePeriod()
        // One period of the most recent audio, with its end blended into the audio one period
        // earlier so that wrapping from the last sample back to the first is continuous.
        let seam = period / 4
        for i in 0..<period {
            var s = past(period - i)
            if i >= period - seam {
                let w = Float(i - (period - seam) + 1) / Float(seam)
                s = s * (1 - w) + past(2 * period - i) * w
            }
            periodBuffer[i] = s
        }
        phase = 0
        concealedSamples = 0
        isConcealing = true
    }

    /// Normalized autocorrelation pitch search: coarse at 12 kHz, then refined at 48 kHz.
    func estimatePeriod() -> Int {
        let fallback = 480
        guard historyCount >= 2 * Self.maxPeriod else { return fallback }

        func score(lag: Int, window: Int, step: Int) -> Float {
            var cross: Float = 0, energyA: Float = 0, energyB: Float = 0
            var k = 1
            while k <= window {
                let a = past(k)
                let b = past(k + lag)
                cross += a * b
                energyA += a * a
                energyB += b * b
                k += step
            }
            let denom = (energyA * energyB).squareRoot()
            return denom > 1e-9 ? cross / denom : 0
        }

        var bestLag = fallback
        var bestScore: Float = -1
        var lag = Self.minPeriod
        while lag <= Self.maxPeriod {
            let s = score(lag: lag, window: 480, step: 4)
            if s > bestScore { bestScore = s; bestLag = lag }
            lag += 4
        }
        guard bestScore > 0.1 else { return fallback }

        var refined = bestLag
        var refinedScore: Float = -1
        for candidate in max(Self.minPeriod, bestLag - 4)...min(Self.maxPeriod, bestLag + 4) {
            let s = score(lag: candidate, window: 480, step: 1)
            if s > refinedScore { refinedScore = s; refined = candidate }
        }
        return refined
    }
}
