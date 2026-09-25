import Foundation
import Testing
@testable import AudioBubble

// MARK: Signals

/// Deterministic generator for synthetic speech.
struct SpeechRandom: RandomNumberGenerator {
    var s: UInt64
    mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s }
}

/// Voiced "speech": harmonics of a wandering pitch with moving formants, in syllables and talk spurts.
func speechLike(seconds: Double, seed: UInt64, pitch: Double, activity: [(Double, Double)]) -> [Float] {
    var rng = SpeechRandom(s: seed)
    let n = Int(seconds * 48_000)
    var out = [Float](repeating: 0, count: n)
    var phase = 0.0, envelope = 0.0, target = 0.0, formant = 700.0
    var nextChange = 0
    for i in 0..<n {
        let t = Double(i) / 48_000
        if i >= nextChange {
            let active = activity.contains { t >= $0.0 && t < $0.1 }
            target = active && Double.random(in: 0..<1, using: &rng) < 0.7 ? Double.random(in: 0.4...1, using: &rng) : 0
            nextChange = i + Int(Double.random(in: 0.08...0.25, using: &rng) * 48_000)
            formant = Double.random(in: 400...2000, using: &rng)
        }
        envelope += (target - envelope) * 0.002
        let f0 = pitch * (1 + 0.1 * sin(2 * .pi * 0.7 * t + Double(seed)))
        phase += 2 * .pi * f0 / 48_000
        var s = 0.0
        for h in 1...20 {
            let f = f0 * Double(h)
            if f > 7_000 { break }
            let shape = exp(-pow((f - formant) / 900, 2)) + 0.3 * exp(-pow((f - 2 * formant) / 1200, 2)) + 0.05
            s += shape * sin(Double(h) * phase) / Double(h).squareRoot()
        }
        out[i] = Float(0.15 * envelope * s)
    }
    return out
}

/// Your voice as it comes back in a peer's stream: delayed, dulled by their mic, quieter.
func leaked(_ x: [Float], delayMs: Double, gain: Float) -> [Float] {
    let delay = Int(delayMs * 48)
    var y = [Float](repeating: 0, count: x.count)
    var lowpass: Float = 0
    for i in 0..<x.count {
        lowpass += 0.35 * ((i >= delay ? x[i - delay] : 0) - lowpass)
        y[i] = gain * lowpass
    }
    return y
}

func energy(_ x: [Float], _ ranges: (Double, Double)...) -> Double {
    ranges.reduce(0) { total, r in
        total + x[Int(r.0 * 48_000)..<min(x.count, Int(r.1 * 48_000))].reduce(0) { $0 + Double($1 * $1) }
    }
}

func decibels(_ ratio: Double) -> Double { 10 * log10(max(ratio, 1e-12)) }

struct EchoRun {
    var echoOut: [Float], peerOut: [Float], detected: Bool, delayMs: Double
}

/// Runs the suppressor on `peer + echo` with `mine` as reference, and applies the gains it chose to
/// the peer and echo components separately so each can be measured.
func runSuppressor(mine: [Float], peer: [Float], echo: [Float]) -> EchoRun {
    let reference = EchoReference()
    let suppressor = SelfEchoSuppressor(reference: reference)
    let echoPart = SpectralTransform(), peerPart = SpectralTransform()
    let hop = SpectralTransform.hop
    var echoOut = [Float](repeating: 0, count: mine.count), peerOut = echoOut
    var input = [Float](repeating: 0, count: hop), output = input
    var i = 0
    while i + hop <= mine.count {
        mine.withUnsafeBufferPointer { reference.process($0.baseAddress! + i) }
        for j in 0..<hop { input[j] = peer[i + j] + echo[i + j] }
        suppressor.process(input, into: &output)
        echo.withUnsafeBufferPointer { echoPart.analyze($0.baseAddress! + i) }
        peer.withUnsafeBufferPointer { peerPart.analyze($0.baseAddress! + i) }
        echoPart.apply(gains: suppressor.currentGains)
        peerPart.apply(gains: suppressor.currentGains)
        echoOut.withUnsafeMutableBufferPointer { echoPart.synthesize(into: $0.baseAddress! + i) }
        peerOut.withUnsafeMutableBufferPointer { peerPart.synthesize(into: $0.baseAddress! + i) }
        i += hop
    }
    return EchoRun(echoOut: echoOut, peerOut: peerOut, detected: suppressor.echoDetected,
                   delayMs: AudioFormat.milliseconds(samples: suppressor.delayHops * hop))
}

// MARK: Tests

struct SpectralTransformTests {
    @Test func reconstructsPerfectlyWithUnityGains() {
        let transform = SpectralTransform()
        var rng = SpeechRandom(s: 3)
        let x = (0..<9_600).map { _ in Float.random(in: -0.5...0.5, using: &rng) }
        var y = [Float](repeating: 0, count: x.count)
        let ones = [Float](repeating: 1, count: SpectralTransform.bins)
        var i = 0
        while i + 128 <= x.count {
            x.withUnsafeBufferPointer { transform.analyze($0.baseAddress! + i) }
            transform.apply(gains: ones)
            y.withUnsafeMutableBufferPointer { transform.synthesize(into: $0.baseAddress! + i) }
            i += 128
        }
        // Output is the input, exactly one hop late.
        let error = (256..<9_000).map { abs(y[$0 + 128] - x[$0]) }.max()!
        #expect(error < 1e-5, "max error \(error)")
    }
}

struct SelfEchoSuppressorTests {
    // You talk in spurts; the peer talks in between, and over you from 20 to 24 s.
    static let mineActivity: [(Double, Double)] = [(0, 4), (6, 10), (13, 17), (20, 24), (26, 30)]
    static let peerActivity: [(Double, Double)] = [(4, 6), (10, 13), (17, 20), (20, 24), (24, 26)]
    static let mine = speechLike(seconds: 30, seed: 1, pitch: 120, activity: mineActivity)

    @Test(arguments: [(120.0, Float(0.3)), (300.0, 0.15), (60.0, 0.5)])
    func removesYourVoiceFromThePeersStream(delayMs: Double, gain: Float) {
        let peer = speechLike(seconds: 30, seed: 2, pitch: 210, activity: Self.peerActivity)
        let echo = leaked(Self.mine, delayMs: delayMs, gain: gain)
        let run = runSuppressor(mine: Self.mine, peer: peer, echo: echo)

        #expect(run.detected)
        #expect(abs(run.delayMs - delayMs) < 15, "delay \(run.delayMs) ms")
        // Where only your voice comes back, it is removed (after the first seconds of learning).
        let reduction = decibels(energy(echo, (13, 17), (26, 30)) / energy(run.echoOut, (13, 17), (26, 30)))
        #expect(reduction > 18, "echo reduced by \(reduction) dB")
        // Where only the peer talks, they are untouched.
        let peerChange = decibels(energy(run.peerOut, (17, 20), (24, 26)) / energy(peer, (17, 20), (24, 26)))
        #expect(peerChange > -1.5, "peer changed by \(peerChange) dB")
        // Talking over each other, the peer stays clearly audible while your voice still drops.
        let doubleTalkPeer = decibels(energy(run.peerOut, (20, 24)) / energy(peer, (20, 24)))
        let doubleTalkEcho = decibels(energy(echo, (20, 24)) / energy(run.echoOut, (20, 24)))
        #expect(doubleTalkPeer > -6, "peer in double talk \(doubleTalkPeer) dB")
        #expect(doubleTalkEcho > 3, "echo in double talk reduced by \(doubleTalkEcho) dB")
    }

    @Test(arguments: [UInt64(2), 3, 4])
    func leavesThePeerAloneWhenThereIsNoEcho(seed: UInt64) {
        let peer = speechLike(seconds: 30, seed: seed, pitch: 180 + Double(seed) * 10, activity: Self.peerActivity)
        let run = runSuppressor(mine: Self.mine, peer: peer, echo: [Float](repeating: 0, count: Self.mine.count))
        #expect(!run.detected)
        let change = decibels(energy(run.peerOut, (1, 30)) / energy(peer, (1, 30)))
        #expect(abs(change) < 0.2, "peer changed by \(change) dB")
    }

    @Test func followsADelayThatChanges() {
        // The jitter buffer grows mid-conversation, moving your echo from 120 to 170 ms.
        let peer = speechLike(seconds: 30, seed: 2, pitch: 210, activity: Self.peerActivity)
        let early = leaked(Self.mine, delayMs: 120, gain: 0.3), late = leaked(Self.mine, delayMs: 170, gain: 0.3)
        let echo = (0..<Self.mine.count).map { $0 < 15 * 48_000 ? early[$0] : late[$0] }
        let run = runSuppressor(mine: Self.mine, peer: peer, echo: echo)
        #expect(abs(run.delayMs - 170) < 15, "delay \(run.delayMs) ms")
        let reduction = decibels(energy(echo, (26, 30)) / energy(run.echoOut, (26, 30)))
        #expect(reduction > 18, "echo reduced by \(reduction) dB")
    }
}
