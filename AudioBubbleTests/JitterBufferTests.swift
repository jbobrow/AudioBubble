import Foundation
import Testing
@testable import AudioBubble

/// Simulates one sender and one receiver in sample time.
///
/// The sender emits a 240-sample frame every 5 ms of *its* clock (optionally drifting from the
/// receiver's). Each packet gets a network delay from `delay`, may be dropped by `drop`, and the
/// receiver renders `callbackSize` samples per I/O cycle, inserting every packet that has arrived.
struct Simulation {
    var seconds: Double = 20
    var callbackSize = 256
    /// Sender clock rate relative to the receiver (1.005 = sender runs 0.5 % fast).
    var senderRate = 1.0
    var delay: (_ sequence: Int, _ sendTime: Double) -> Double = { _, _ in 0.002 }
    var drop: (_ sequence: Int) -> Bool = { _ in false }
    var frequency = 300.0
    /// Also capture the statistics at this receiver time.
    var snapshotTime: Double?

    struct Result {
        var output: [Float]
        var statistics: JitterBuffer.Statistics
        /// Buffer level after each callback, in ms, with the callback's receiver time.
        var levels: [(time: Double, ms: Double)]
        var buffer: JitterBuffer
        var snapshot: JitterBuffer.Statistics?
    }

    func run() -> Result {
        let buffer = JitterBuffer()
        let frame = AudioFormat.frameSamples
        let frameCount = Int(seconds / AudioFormat.frameDuration * senderRate)

        struct Packet { var arrival: Double; var sequence: Int }
        var packets: [Packet] = []
        for seq in 0..<frameCount where !drop(seq) {
            let sendTime = Double(seq + 1) * AudioFormat.frameDuration / senderRate
            packets.append(Packet(arrival: sendTime + delay(seq, sendTime), sequence: seq))
        }
        packets.sort { $0.arrival < $1.arrival }

        var output: [Float] = []
        output.reserveCapacity(Int(seconds * AudioFormat.sampleRate))
        var levels: [(Double, Double)] = []
        var next = 0
        var chunk = [Float](repeating: 0, count: callbackSize)
        var time = 0.0
        var snapshot: JitterBuffer.Statistics?
        let callbackDuration = Double(callbackSize) / AudioFormat.sampleRate
        while time < seconds {
            time += callbackDuration
            while next < packets.count && packets[next].arrival <= time {
                let seq = packets[next].sequence
                let samples = (0..<frame).map { Int16(12_000 * sin(2 * .pi * frequency * Double(seq * frame + $0) / AudioFormat.sampleRate)) }
                samples.withUnsafeBufferPointer { buffer.insert(sequence: UInt32(truncatingIfNeeded: seq), samples: $0.baseAddress) }
                next += 1
            }
            buffer.render(into: &chunk, count: callbackSize)
            output += chunk
            levels.append((time, AudioFormat.milliseconds(samples: buffer.lastLevel)))
            if let snapshotTime, snapshot == nil, time >= snapshotTime { snapshot = buffer.statistics }
        }
        return Result(output: output, statistics: buffer.statistics, levels: levels, buffer: buffer, snapshot: snapshot)
    }
}

/// Deterministic pseudo-random numbers for repeatable tests.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

func maxJump(_ samples: ArraySlice<Float>) -> Float {
    zip(samples.dropFirst(), samples).map { abs($0 - $1) }.max() ?? 0
}

func meanLevel(_ result: Simulation.Result, after time: Double) -> Double {
    let tail = result.levels.filter { $0.time > time }.map(\.ms)
    return tail.reduce(0, +) / Double(tail.count)
}

struct JitterBufferTests {
    @Test func cleanNetworkPlaysEverythingWithLowLatency() {
        let result = Simulation(seconds: 10).run()
        #expect(result.statistics.lost == 0)
        #expect(result.statistics.late == 0)
        #expect(result.statistics.droppedForLatency == 0)
        #expect(result.statistics.underruns <= 1)
        #expect(result.statistics.played > 1_990)
        // Only the minimum margin plus frame/callback granularity.
        #expect(meanLevel(result, after: 2) < 12, "mean level \(meanLevel(result, after: 2)) ms")
        // A 300 Hz sine at 0.37 amplitude never moves more than ~0.015 per sample: no clicks.
        let jump = maxJump(result.output[4_800...])
        #expect(jump < 0.03, "max jump \(jump)")
    }

    @Test func reorderedPacketsAreNotLostOnceAdapted() {
        var sim = Simulation(seconds: 10)
        // Every pair swaps: odd frames arrive 1 ms before the even frame before them.
        sim.delay = { seq, _ in seq % 2 == 0 ? 0.0065 : 0.0005 }
        sim.snapshotTime = 3
        let result = sim.run()
        // The first few swapped frames are needed before they arrive; each one raises the margin...
        #expect(result.statistics.lost < 25, "\(result.statistics)")
        #expect(result.statistics.lost == result.statistics.late)
        // ...until reordering is absorbed completely.
        #expect(result.statistics.lost == result.snapshot?.lost)
        #expect(result.statistics.droppedForLatency == 0)
        #expect(meanLevel(result, after: 3) < 20)
    }

    @Test func randomLossIsConcealedNotStalled() {
        var sim = Simulation(seconds: 10)
        var rng = SeededRandom(state: 1)
        let dropped = Set((0..<2_000).filter { _ in Double.random(in: 0..<1, using: &rng) < 0.05 })
        sim.drop = { dropped.contains($0) }
        let result = sim.run()
        // Each dropped frame is concealed once (the final one may still be pending).
        #expect(abs(result.statistics.lost - dropped.count) <= 2, "lost \(result.statistics.lost) of \(dropped.count)")
        #expect(result.statistics.played + result.statistics.lost > 1_990)
        // Pure loss does not raise the margin, so latency stays low.
        #expect(result.buffer.margin < AudioFormat.samples(ms: 5))
        #expect(meanLevel(result, after: 2) < 15, "mean level \(meanLevel(result, after: 2)) ms")
    }

    @Test func adaptsToJitterAndStopsUnderrunning() {
        var sim = Simulation(seconds: 30)
        var rng = SeededRandom(state: 7)
        let delays = (0..<7_000).map { _ in 0.002 + Double.random(in: 0..<0.015, using: &rng) }
        sim.delay = { seq, _ in delays[seq] }
        let result = sim.run()
        // After the first adaptation, late packets and underruns are rare.
        #expect(result.statistics.late + result.statistics.underruns < 10, "\(result.statistics)")
        #expect(result.statistics.lost < 10)
        // And latency stays bounded, far below the cap.
        #expect(meanLevel(result, after: 10) < 40, "mean level \(meanLevel(result, after: 10)) ms")
    }

    @Test(arguments: [1.005, 0.995])
    func tracksClockDrift(senderRate: Double) {
        var sim = Simulation(seconds: 60)
        sim.senderRate = senderRate
        let result = sim.run()
        #expect(result.statistics.droppedForLatency == 0)
        #expect(result.statistics.underruns <= 2, "\(result.statistics)")
        // Latency neither creeps up (fast sender) nor starves (slow sender).
        let early = meanLevel(result, after: 5)
        let late = meanLevel(result, after: 50)
        #expect(late < 15, "late level \(late) ms")
        #expect(abs(late - early) < 5, "early \(early) ms, late \(late) ms")
    }

    @Test func absorbsAnAWDLSpikeThenDrainsBack() {
        var sim = Simulation(seconds: 30)
        // At t = 5 s, packets are held for 80 ms and then arrive in a burst (a channel hop).
        sim.delay = { _, sendTime in
            if sendTime >= 5 && sendTime < 5.08 { return 5.08 - sendTime + 0.002 }
            return 0.002
        }
        let result = sim.run()
        // Delayed packets are late, not lost: they are all played.
        #expect(result.statistics.lost == 0, "\(result.statistics)")
        #expect(result.statistics.droppedForLatency == 0)
        #expect(result.statistics.played > 5_990)
        // Right after the burst the buffer holds the spike...
        let peak = result.levels.filter { $0.time > 5 && $0.time < 5.3 }.map(\.ms).max()!
        #expect(peak > 50, "peak \(peak) ms")
        // ...and it drains back down automatically.
        #expect(meanLevel(result, after: 25) < 20, "final level \(meanLevel(result, after: 25)) ms")
    }

    @Test func recoversWhenTheSenderRestarts() {
        let buffer = JitterBuffer()
        var chunk = [Float](repeating: 0, count: 256)
        let frame = [Int16](repeating: 1_000, count: AudioFormat.frameSamples)
        var seq: UInt32 = 50_000
        for _ in 0..<400 {
            buffer.insert(sequence: seq, samples: frame)
            seq &+= 1
            buffer.render(into: &chunk, count: 240)
        }
        // New sequence space.
        seq = 3
        for _ in 0..<400 {
            buffer.insert(sequence: seq, samples: frame)
            seq &+= 1
            buffer.render(into: &chunk, count: 240)
        }
        #expect(buffer.state == .playing)
        #expect(abs(chunk[100] - Float(1_000) / 32_768) < 1e-3)
    }
}
