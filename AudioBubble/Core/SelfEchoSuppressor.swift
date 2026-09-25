import Foundation

/// Removes *your own voice* from a peer's stream.
///
/// People in a bubble are in the same room, so a peer's microphone (say, their AirPods) also picks
/// up your voice through the air and sends it back to you ~100 ms later. Their phone's echo
/// canceller can't remove it (your voice reaches their mic *before* your stream reaches their ears),
/// but your phone holds a clean copy of what you said: your own mic. So on your side, per peer:
///
/// 1. **Delay**: cross-correlate band-energy envelopes of your mic (`EchoReference`) with the
///    peer's stream over 0…1 s of lag. A clear peak means your voice is coming back, and where.
/// 2. **Coupling**: per frequency bin, learn how loud your voice returns (echo power / mic power),
///    tracked toward the low end so the peer's own speech doesn't inflate it.
/// 3. **Suppression**: predict the echo's power in each bin from your delayed mic and turn down
///    only the bins where it dominates. The peer's own voice, including double talk, passes.
///
/// Costs one STFT hop (128 samples, 2.7 ms) of latency. Real-time safe.
nonisolated final class EchoReference {
    static let historyHops = 384            // 1.02 s of lag
    static let bandCount = 8

    let transform = SpectralTransform()
    private let powerHistory: UnsafeMutablePointer<Float>
    private let featureHistory: UnsafeMutablePointer<Float>
    private let featureMean: UnsafeMutablePointer<Float>
    private(set) var hopCount = 0

    init() {
        powerHistory = .allocate(capacity: Self.historyHops * SpectralTransform.bins)
        powerHistory.initialize(repeating: 0, count: Self.historyHops * SpectralTransform.bins)
        featureHistory = .allocate(capacity: Self.historyHops * Self.bandCount)
        featureHistory.initialize(repeating: 0, count: Self.historyHops * Self.bandCount)
        featureMean = .allocate(capacity: Self.bandCount)
        featureMean.initialize(repeating: 0, count: Self.bandCount)
    }

    deinit {
        powerHistory.deallocate()
        featureHistory.deallocate()
        featureMean.deallocate()
    }

    /// Analyzes the next hop of your mic.
    func process(_ hop: UnsafePointer<Float>) {
        hopCount += 1
        let slot = hopCount % Self.historyHops
        transform.analyze(hop)
        let power = powerHistory + slot * SpectralTransform.bins
        transform.power(into: power)
        EchoFeatures.compute(power: power, mean: featureMean, into: featureHistory + slot * Self.bandCount)
    }

    @inline(__always)
    private func slot(_ hopsAgo: Int) -> Int {
        let r = (hopCount - hopsAgo) % Self.historyHops
        return r < 0 ? r + Self.historyHops : r
    }

    /// Mic power spectrum from `hopsAgo` hops before the latest one.
    @inline(__always)
    func power(hopsAgo: Int) -> UnsafePointer<Float> {
        UnsafePointer(powerHistory + slot(hopsAgo) * SpectralTransform.bins)
    }

    @inline(__always)
    func features(hopsAgo: Int) -> UnsafePointer<Float> {
        UnsafePointer(featureHistory + slot(hopsAgo) * Self.bandCount)
    }
}

/// Band-energy envelopes for delay estimation: log energy in eight speech bands (~190 Hz–4.5 kHz),
/// with a slow running mean removed so only changes (syllables) correlate.
nonisolated enum EchoFeatures {
    /// Bin edges at 187.5 Hz per bin.
    static let edges = [1, 3, 5, 7, 9, 12, 15, 19, 24]

    static func compute(power: UnsafePointer<Float>, mean: UnsafeMutablePointer<Float>, into out: UnsafeMutablePointer<Float>) {
        for b in 0..<EchoReference.bandCount {
            var energy: Float = 1e-6
            for k in edges[b]..<edges[b + 1] { energy += power[k] }
            let value = log(energy)
            mean[b] += 0.01 * (value - mean[b])
            out[b] = value - mean[b]
        }
    }
}

nonisolated final class SelfEchoSuppressor {
    static let minGain: Float = 0.056          // −25 dB
    static let overSubtraction: Float = 3
    static let detectOn: Float = 0.35
    static let detectOff: Float = 0.2
    /// Your voice can't come back sooner than their mic + framing + network + our buffer allow.
    /// Excluding tiny lags also stops coincident speech onsets from looking like an echo.
    static let minLagHops = 6               // 16 ms
    /// Hops of history needed before trusting the correlation.
    static let warmupHops = 400             // ~1 s
    /// How far the peak must stand above the other lags (in standard deviations). Hundreds of
    /// lags of unrelated speech always produce some high value by chance; an echo stands out.
    static let minProminence: Float = 2.5
    /// Once detected, an echo path is a property of the room: keep it through turn-taking and
    /// only drop it after this long without supporting evidence.
    static let releaseHops = 3_750          // 10 s
    /// Delay uncertainty covered when predicting the echo, in hops either side (±8 ms).
    static let delaySpread = 3

    private let reference: EchoReference
    private let transform = SpectralTransform()
    private let bins = SpectralTransform.bins
    private let lags = EchoReference.historyHops - 2

    private let peerPower: UnsafeMutablePointer<Float>
    private let peerFeatures: UnsafeMutablePointer<Float>
    private let peerMean: UnsafeMutablePointer<Float>
    private let correlation: UnsafeMutablePointer<Float>
    private let coupling: UnsafeMutablePointer<Float>
    private let echo: UnsafeMutablePointer<Float>
    private let gains: UnsafeMutablePointer<Float>
    private let rawGains: UnsafeMutablePointer<Float>
    private let referenceFloor: UnsafeMutablePointer<Float>
    private var referenceEnergy: Float = 0
    private var peerEnergy: Float = 0
    private var hopsSinceReset = 0
    private var weakHops = 0
    /// Slowly decaying peak of your (delayed) speech energy, to tell talking from silence.
    private var minePeak: Float = 0
    private let smoothedPeer: UnsafeMutablePointer<Float>
    private let smoothedMine: UnsafeMutablePointer<Float>
    private let spreadMine: UnsafeMutablePointer<Float>

    /// Estimated delay of your voice in the peer's stream, in hops.
    private(set) var delayHops = 0
    /// True while your voice is detected in this stream.
    private(set) var echoDetected = false
    private(set) var confidence: Float = 0
    /// Peak height above the other lags, in standard deviations.
    private(set) var prominence: Float = 0
    /// The per-bin gains applied to the latest hop (for tests and diagnostics).
    var currentGains: UnsafePointer<Float> { UnsafePointer(gains) }
    /// Learned echo coupling per bin (diagnostics).
    var couplingEstimate: UnsafePointer<Float> { UnsafePointer(coupling) }

    init(reference: EchoReference) {
        self.reference = reference
        func buffer(_ count: Int, _ value: Float) -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: count)
            p.initialize(repeating: value, count: count)
            return p
        }
        peerPower = buffer(bins, 0)
        peerFeatures = buffer(EchoReference.bandCount, 0)
        peerMean = buffer(EchoReference.bandCount, 0)
        correlation = buffer(EchoReference.historyHops, 0)
        coupling = buffer(bins, 0)
        echo = buffer(bins, 0)
        gains = buffer(bins, 1)
        rawGains = buffer(bins, 1)
        referenceFloor = buffer(bins, 1e-4)
        smoothedPeer = buffer(bins, 0)
        smoothedMine = buffer(bins, 0)
        spreadMine = buffer(bins, 0)
    }

    deinit {
        for p in [peerPower, peerFeatures, peerMean, correlation, coupling, echo, gains, rawGains, referenceFloor, smoothedPeer, smoothedMine, spreadMine] {
            p.deallocate()
        }
    }

    func reset() {
        transform.reset()
        peerMean.update(repeating: 0, count: EchoReference.bandCount)
        correlation.update(repeating: 0, count: EchoReference.historyHops)
        coupling.update(repeating: 0, count: bins)
        echo.update(repeating: 0, count: bins)
        gains.update(repeating: 1, count: bins)
        referenceFloor.update(repeating: 1e-4, count: bins)
        smoothedPeer.update(repeating: 0, count: bins)
        smoothedMine.update(repeating: 0, count: bins)
        hopsSinceReset = 0
        weakHops = 0
        minePeak = 0
        referenceEnergy = 0
        peerEnergy = 0
        delayHops = 0
        echoDetected = false
        confidence = 0
    }

    /// Processes one hop of the peer's stream. Call after `reference.process` for the same hop.
    /// `output` gets the cleaned hop, 128 samples late.
    func process(_ input: UnsafePointer<Float>, into output: UnsafeMutablePointer<Float>) {
        transform.analyze(input)
        transform.power(into: peerPower)
        EchoFeatures.compute(power: peerPower, mean: peerMean, into: peerFeatures)
        estimateDelay()
        computeGains()
        transform.apply(gains: gains)
        transform.synthesize(into: output)
    }

    // MARK: Delay

    private func estimateDelay() {
        let decay: Float = 0.9995               // ~5 s memory: an echo persists, coincidences don't
        let bands = EchoReference.bandCount
        var peerSquare: Float = 0
        var referenceSquare: Float = 0
        let current = reference.features(hopsAgo: 0)
        for b in 0..<bands {
            peerSquare += peerFeatures[b] * peerFeatures[b]
            referenceSquare += current[b] * current[b]
        }
        peerEnergy = decay * peerEnergy + peerSquare
        referenceEnergy = decay * referenceEnergy + referenceSquare

        hopsSinceReset += 1
        var best = Self.minLagHops
        var bestValue: Float = -.infinity
        var sum: Float = 0
        var sumSquares: Float = 0
        for lag in Self.minLagHops..<lags {
            let x = reference.features(hopsAgo: lag)
            var dot: Float = 0
            for b in 0..<bands { dot += peerFeatures[b] * x[b] }
            let c = decay * correlation[lag] + dot
            correlation[lag] = c
            sum += c
            sumSquares += c * c
            if c > bestValue { bestValue = c; best = lag }
        }
        let count = Float(lags - Self.minLagHops)
        let mean = sum / count
        let spread = max(0, sumSquares / count - mean * mean).squareRoot()
        prominence = spread > 1e-9 ? (bestValue - mean) / spread : 0

        let norm = (peerEnergy * referenceEnergy).squareRoot()
        confidence = norm > 1e-6 && hopsSinceReset >= Self.warmupHops ? bestValue / norm : 0
        // Hysteresis on the delay: move only for a clearly better peak.
        if best != delayHops && prominence > Self.minProminence && (bestValue > correlation[delayHops] * 1.1 || !echoDetected) {
            delayHops = best
        }
        if echoDetected {
            let weak = confidence < Self.detectOff || prominence < Self.minProminence / 2
            weakHops = weak ? weakHops + 1 : 0
            if weakHops > Self.releaseHops { echoDetected = false }
        } else if confidence > Self.detectOn && prominence > Self.minProminence {
            echoDetected = true
            // Start from a moderate coupling; it's pulled down quickly if that's too much.
            for k in 0..<bins where coupling[k] == 0 { coupling[k] = 0.1 }
        }
    }

    // MARK: Suppression

    private func computeGains() {
        let d = max(Self.minLagHops, min(lags - 1 - Self.delaySpread, delayHops))
        let at = reference.power(hopsAgo: d)
        let now = reference.power(hopsAgo: 0)
        // The envelope correlation peak is broad, so the delay can be a few hops off: predict the
        // echo from the loudest of the neighboring hops.
        for k in 0..<bins { spreadMine[k] = at[k] }
        for offset in 1...Self.delaySpread {
            let early = reference.power(hopsAgo: d + offset), late = reference.power(hopsAgo: d - offset)
            for k in 0..<bins { spreadMine[k] = max(spreadMine[k], early[k], late[k]) }
        }

        // You're "talking" (at the echo's delay) when within 20 dB of your recent peak.
        var mineEnergy: Float = 0
        for k in 1..<24 { mineEnergy += at[k] }
        minePeak = max(mineEnergy, minePeak * 0.9995)
        let talking = mineEnergy > 0.01 * minePeak && mineEnergy > 1e-9

        for k in 0..<bins {
            // Minimum-statistics noise floor of your mic, to know when you're really talking.
            let floor = referenceFloor[k]
            referenceFloor[k] = now[k] < floor ? now[k] : floor * 1.002 + 1e-12

            let x = spreadMine[k]
            let y = peerPower[k] + 1e-12
            // Short-term averages make the ratio below far less noisy than single STFT bins.
            smoothedMine[k] += 0.3 * (at[k] - smoothedMine[k])
            smoothedPeer[k] += 0.3 * (peerPower[k] - smoothedPeer[k])
            guard echoDetected else {
                rawGains[k] = 1
                echo[k] = 0
                continue
            }
            if talking && smoothedMine[k] > 20 * referenceFloor[k] {
                // Ratio of what came back to what you said. Your peer talking over you inflates
                // it, so it falls much faster than it rises: the estimate sits in the lower
                // part of the ratio's spread, near the true echo path.
                let ratio = min(4, smoothedPeer[k] / smoothedMine[k])
                // Multiplicative steps: down up to 7 % per hop, up at most 0.4 % (×2 in ~0.5 s).
                let c = coupling[k]
                coupling[k] = ratio < c ? max(ratio, c * 0.93) : min(ratio, c * 1.004)
            }
            // Predicted echo, with a decaying tail for room reverberation.
            echo[k] = max(coupling[k] * x, echo[k] * 0.6)
            rawGains[k] = max(Self.minGain, min(1, 1 - Self.overSubtraction * echo[k] / y))
        }

        // Smooth across frequency, then in time: suppress quickly, recover a little slower.
        for k in 0..<bins {
            let lo = rawGains[max(0, k - 1)], hi = rawGains[min(bins - 1, k + 1)]
            let g = min(rawGains[k], (lo + 2 * rawGains[k] + hi) / 4)
            let previous = gains[k]
            gains[k] = g < previous ? 0.3 * previous + 0.7 * g : 0.75 * previous + 0.25 * g
        }
    }
}
