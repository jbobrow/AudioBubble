/// Transparent below the knee, then a smooth tanh curve that never exceeds full scale.
nonisolated enum SoftLimiter {
    static let knee: Float = 0.8

    @inline(__always)
    static func limit(_ x: Float) -> Float {
        let magnitude = abs(x)
        guard magnitude > knee else { return x }
        let headroom = 1 - knee
        let shaped = knee + headroom * tanhApprox((magnitude - knee) / headroom)
        return x < 0 ? -shaped : shaped
    }

    static func process(_ buffer: UnsafeMutablePointer<Float>, count: Int) {
        for i in 0..<count { buffer[i] = limit(buffer[i]) }
    }

    /// Padé approximation of tanh, clamped to ±1. Cheap and monotonic.
    @inline(__always)
    private static func tanhApprox(_ x: Float) -> Float {
        if x >= 3 { return 1 }
        let x2 = x * x
        return min(1, x * (27 + x2) / (27 + 9 * x2))
    }
}
