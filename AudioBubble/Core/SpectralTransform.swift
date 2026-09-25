import Accelerate

/// A 256-point STFT with 50 % overlap and sqrt-Hann windows (perfect reconstruction).
/// Feed it 128-sample hops; each hop comes back out 128 samples later.
///
/// Real-time safe: the FFT setup and all buffers are created in `init`.
nonisolated final class SpectralTransform {
    static let size = 256
    static let hop = 128
    static let bins = size / 2 + 1
    private static let log2n: vDSP_Length = 8

    private let setup: FFTSetup
    private let window: UnsafeMutablePointer<Float>
    private let input: UnsafeMutablePointer<Float>      // last `size` input samples
    private let frame: UnsafeMutablePointer<Float>      // windowed frame / inverse output
    private let overlap: UnsafeMutablePointer<Float>    // overlap-add accumulator
    let real: UnsafeMutablePointer<Float>                // spectrum, zrip packing: real[0] = DC, imag[0] = Nyquist
    let imag: UnsafeMutablePointer<Float>

    init() {
        let n = Self.size
        setup = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2))!
        window = .allocate(capacity: n)
        for i in 0..<n { window[i] = (0.5 - 0.5 * cos(2 * .pi * Float(i) / Float(n))).squareRoot() }
        input = .allocate(capacity: n); input.initialize(repeating: 0, count: n)
        frame = .allocate(capacity: n); frame.initialize(repeating: 0, count: n)
        overlap = .allocate(capacity: n); overlap.initialize(repeating: 0, count: n)
        real = .allocate(capacity: n / 2); real.initialize(repeating: 0, count: n / 2)
        imag = .allocate(capacity: n / 2); imag.initialize(repeating: 0, count: n / 2)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
        for p in [window, input, frame, overlap, real, imag] { p.deallocate() }
    }

    func reset() {
        input.update(repeating: 0, count: Self.size)
        overlap.update(repeating: 0, count: Self.size)
    }

    /// Slides in one hop of input and computes the spectrum of the newest frame.
    func analyze(_ hop: UnsafePointer<Float>) {
        let h = Self.hop
        input.update(from: input + h, count: h)
        (input + h).update(from: hop, count: h)
        vDSP_vmul(input, 1, window, 1, frame, 1, vDSP_Length(Self.size))
        var split = DSPSplitComplex(realp: real, imagp: imag)
        frame.withMemoryRebound(to: DSPComplex.self, capacity: h) {
            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(h))
        }
        vDSP_fft_zrip(setup, &split, 1, Self.log2n, FFTDirection(FFT_FORWARD))
    }

    /// Power of each of the `bins` bins of the current spectrum (arbitrary but consistent scale).
    func power(into out: UnsafeMutablePointer<Float>) {
        let half = Self.size / 2
        out[0] = real[0] * real[0]
        out[half] = imag[0] * imag[0]
        for k in 1..<half { out[k] = real[k] * real[k] + imag[k] * imag[k] }
    }

    /// Scales each bin of the current spectrum.
    func apply(gains: UnsafePointer<Float>) {
        let half = Self.size / 2
        real[0] *= gains[0]
        imag[0] *= gains[half]
        for k in 1..<half {
            real[k] *= gains[k]
            imag[k] *= gains[k]
        }
    }

    /// Inverts the current spectrum and overlap-adds it, writing the finished hop to `out`.
    func synthesize(into out: UnsafeMutablePointer<Float>) {
        let n = Self.size, h = Self.hop
        var split = DSPSplitComplex(realp: real, imagp: imag)
        vDSP_fft_zrip(setup, &split, 1, Self.log2n, FFTDirection(FFT_INVERSE))
        frame.withMemoryRebound(to: DSPComplex.self, capacity: h) {
            vDSP_ztoc(&split, 1, $0, 2, vDSP_Length(h))
        }
        var scale = 1 / Float(2 * n)
        vDSP_vsmul(frame, 1, &scale, frame, 1, vDSP_Length(n))
        vDSP_vmul(frame, 1, window, 1, frame, 1, vDSP_Length(n))
        vDSP_vadd(overlap, 1, frame, 1, overlap, 1, vDSP_Length(n))
        out.update(from: overlap, count: h)
        overlap.update(from: overlap + h, count: h)
        (overlap + h).update(repeating: 0, count: h)
    }
}
