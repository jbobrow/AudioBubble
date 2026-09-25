import Foundation

/// The one audio format used everywhere: on the wire, in the rings and in the jitter buffers.
nonisolated enum AudioFormat {
    /// 48 kHz mono.
    static let sampleRate: Double = 48_000
    /// Samples in one network frame (5 ms at 48 kHz).
    static let frameSamples = 240
    /// Duration of one frame in seconds.
    static let frameDuration: Double = Double(frameSamples) / sampleRate

    static func samples(ms: Double) -> Int { Int((ms * sampleRate / 1000).rounded()) }
    static func milliseconds(samples: Int) -> Double { Double(samples) * 1000 / sampleRate }
}

/// Monotonic microseconds since boot, used for RTT measurements. Never compared across devices.
nonisolated enum MonotonicClock {
    static func nowMicros() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds / 1_000
    }
}
