import AudioToolbox
import Foundation
import Synchronization

/// Microphone and speaker through a raw VoiceProcessingIO AudioUnit: Apple's echo cancellation,
/// noise suppression and AGC in one ~5 ms real-time I/O cycle, as WebRTC does on iOS.
///
/// - Input callback: renders the processed mic into `captureRing` and wakes the sender.
/// - Output callback: fills the speaker from `streams` — remote peers only, never the local mic.
///
/// Both callbacks run on the real-time audio thread: no locks, no allocation, no Swift runtime
/// work beyond atomics.
nonisolated final class VoiceEngine: @unchecked Sendable {
    static let maxFrames = 4_096

    /// Processed mic samples at 48 kHz mono, for the sender thread.
    let captureRing = SampleRing(capacity: 16_384)
    /// Signalled after every input callback.
    let captureSignal = DispatchSemaphore(value: 0)
    let streams: StreamTable

    /// Peak mic level, smoothed, as Float bits (0...1).
    let inputLevel = Atomic<UInt32>(0)

    private var unit: AudioUnit?
    private let inputBuffer: UnsafeMutablePointer<Float>
    private let inputBufferList: UnsafeMutablePointer<AudioBufferList>
    private var smoothedInputLevel: Float = 0   // audio thread only
    private(set) var isRunning = false

    init(streams: StreamTable) {
        self.streams = streams
        inputBuffer = .allocate(capacity: Self.maxFrames)
        inputBuffer.initialize(repeating: 0, count: Self.maxFrames)
        inputBufferList = .allocate(capacity: 1)
        inputBufferList.initialize(to: AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(Self.maxFrames * 4), mData: inputBuffer)))
    }

    deinit {
        if let unit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
        }
        inputBuffer.deallocate()
        inputBufferList.deallocate()
    }

    var micLevel: Float { Float(bitPattern: inputLevel.load(ordering: .relaxed)) }

    // MARK: Lifecycle (main thread)

    func start() throws {
        guard !isRunning else { return }
        if unit == nil { unit = try makeUnit() }
        guard let unit else { return }
        captureRing.discardAll()
        try check(AudioOutputUnitStart(unit), "start")
        isRunning = true
    }

    func stop() {
        guard isRunning, let unit else { return }
        AudioOutputUnitStop(unit)
        isRunning = false
    }

    /// Throws the unit away, e.g. after the media services were reset. `start()` builds a new one.
    func teardown() {
        stop()
        if let unit {
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
        }
        unit = nil
    }

    private func makeUnit() throws -> AudioUnit {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_VoiceProcessingIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw VoiceEngineError.status(-1, "find VoiceProcessingIO")
        }
        var newUnit: AudioUnit?
        try check(AudioComponentInstanceNew(component, &newUnit), "instantiate")
        guard let unit = newUnit else { throw VoiceEngineError.status(-1, "instantiate") }

        let inputBus: AudioUnitElement = 1
        let outputBus: AudioUnitElement = 0
        var one: UInt32 = 1
        var zero: UInt32 = 0
        try set(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, inputBus, &one)
        try set(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, outputBus, &one)

        var format = AudioStreamBasicDescription(
            mSampleRate: AudioFormat.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        // What we read from the mic, and what we give the speaker.
        try set(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, inputBus, &format)
        try set(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, outputBus, &format)

        var maxFrames = UInt32(Self.maxFrames)
        try set(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames)

        // Echo cancellation and noise suppression on, with AGC.
        try set(unit, kAUVoiceIOProperty_BypassVoiceProcessing, kAudioUnitScope_Global, 0, &zero)
        try set(unit, kAUVoiceIOProperty_VoiceProcessingEnableAGC, kAudioUnitScope_Global, 0, &one)

        let context = Unmanaged.passUnretained(self).toOpaque()
        var input = AURenderCallbackStruct(
            inputProc: { refCon, flags, timestamp, _, frames, _ in
                Unmanaged<VoiceEngine>.fromOpaque(refCon).takeUnretainedValue()
                    .captureInput(flags: flags, timestamp: timestamp, frames: frames)
            },
            inputProcRefCon: context)
        try set(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, inputBus, &input)

        var output = AURenderCallbackStruct(
            inputProc: { refCon, _, _, _, frames, ioData in
                Unmanaged<VoiceEngine>.fromOpaque(refCon).takeUnretainedValue()
                    .renderOutput(frames: frames, ioData: ioData)
            },
            inputProcRefCon: context)
        try set(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, outputBus, &output)

        try check(AudioUnitInitialize(unit), "initialize")
        return unit
    }

    // MARK: Real-time callbacks

    private func captureInput(flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                              timestamp: UnsafePointer<AudioTimeStamp>, frames: UInt32) -> OSStatus {
        guard let unit else { return noErr }
        let count = min(Int(frames), Self.maxFrames)
        inputBufferList.pointee.mBuffers.mDataByteSize = UInt32(count * 4)
        inputBufferList.pointee.mBuffers.mData = UnsafeMutableRawPointer(inputBuffer)
        let status = AudioUnitRender(unit, flags, timestamp, 1, UInt32(count), inputBufferList)
        guard status == noErr else { return status }

        var peak: Float = 0
        for i in 0..<count { peak = max(peak, abs(inputBuffer[i])) }
        smoothedInputLevel = peak > smoothedInputLevel ? peak : smoothedInputLevel * 0.92 + peak * 0.08
        inputLevel.store(smoothedInputLevel.bitPattern, ordering: .relaxed)

        captureRing.write(inputBuffer, count: count)
        captureSignal.signal()
        return noErr
    }

    private func renderOutput(frames: UInt32, ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        guard let ioData else { return noErr }
        // Mono, non-interleaved: exactly one buffer.
        let first = ioData.pointee.mBuffers
        guard let data = first.mData else { return noErr }
        let count = min(Int(frames), Self.maxFrames, Int(first.mDataByteSize) / 4)
        streams.mix(into: data.assumingMemoryBound(to: Float.self), count: count)
        return noErr
    }

    // MARK: Helpers

    private func set<T: BitwiseCopyable>(_ unit: AudioUnit, _ property: AudioUnitPropertyID, _ scope: AudioUnitScope,
                        _ element: AudioUnitElement, _ value: inout T) throws {
        try check(AudioUnitSetProperty(unit, property, scope, element, &value, UInt32(MemoryLayout<T>.size)),
                  "set property \(property)")
    }

    private func check(_ status: OSStatus, _ what: String) throws {
        guard status == noErr else { throw VoiceEngineError.status(status, what) }
    }
}

nonisolated enum VoiceEngineError: Error, CustomStringConvertible {
    case status(OSStatus, String)

    var description: String {
        switch self {
        case let .status(status, what): "VoiceProcessingIO: \(what) failed (\(status))"
        }
    }
}
