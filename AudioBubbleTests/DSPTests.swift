import Foundation
import Testing
@testable import AudioBubble

func sine(frequency: Double, amplitude: Double = 0.5, start: Int, count: Int) -> [Float] {
    (0..<count).map { Float(amplitude * sin(2 * .pi * frequency * Double(start + $0) / AudioFormat.sampleRate)) }
}

struct ConcealerTests {
    @Test func findsThePitchPeriod() {
        let plc = PacketLossConcealer()
        // 200 Hz → 240-sample period.
        var audio = sine(frequency: 200, start: 0, count: 2_400)
        plc.play(&audio, count: audio.count)
        let period = plc.estimatePeriod()
        #expect(abs(period - 240) <= 2, "period \(period)")
    }

    @Test func continuesThenFadesToSilence() {
        let plc = PacketLossConcealer()
        var audio = sine(frequency: 200, start: 0, count: 2_400)
        plc.play(&audio, count: audio.count)

        var concealed = [Float](repeating: 0, count: PacketLossConcealer.fadeEndSamples + 480)
        plc.conceal(into: &concealed, count: concealed.count)

        // The first 10 ms keeps the waveform going at full level, close to the true continuation.
        let truth = sine(frequency: 200, start: 2_400, count: 480)
        let error = zip(concealed.prefix(480), truth).map { abs($0 - $1) }.max()!
        #expect(error < 0.05, "max error \(error)")
        // No large jumps anywhere in the concealment.
        let jump = zip(concealed.dropFirst(), concealed).map { abs($0 - $1) }.max()!
        #expect(jump < 0.05, "max jump \(jump)")
        // Silent after 60 ms.
        #expect(concealed.suffix(480).allSatisfy { $0 == 0 })
        #expect(plc.isSilent)
    }

    @Test func crossfadesBackIntoRealAudio() {
        let plc = PacketLossConcealer()
        var audio = sine(frequency: 200, start: 0, count: 2_400)
        plc.play(&audio, count: audio.count)
        var concealed = [Float](repeating: 0, count: 240)
        plc.conceal(into: &concealed, count: 240)
        // Resume with the true signal: the seam must be smooth.
        var resumed = sine(frequency: 200, start: 2_640, count: 240)
        plc.play(&resumed, count: 240)
        #expect(!plc.isConcealing)
        let joined = concealed + resumed
        let jump = zip(joined.dropFirst(), joined).map { abs($0 - $1) }.max()!
        #expect(jump < 0.05, "max jump \(jump)")
    }
}

struct SoftLimiterTests {
    @Test func transparentBelowKneeAndBounded() {
        #expect(SoftLimiter.limit(0.5) == 0.5)
        #expect(SoftLimiter.limit(-0.79) == -0.79)
        for x in stride(from: Float(-10), through: 10, by: 0.01) {
            let y = SoftLimiter.limit(x)
            #expect(abs(y) <= 1)
            #expect((y >= 0) == (x >= 0) || x == 0)
        }
        // Monotonic
        var last = SoftLimiter.limit(-5)
        for x in stride(from: Float(-5), through: 5, by: 0.01) {
            let y = SoftLimiter.limit(x)
            #expect(y >= last)
            last = y
        }
    }
}
