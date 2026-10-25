import Foundation
import Synchronization

/// The sender thread: waits for the capture callback's signal, cuts the mic stream into 5 ms
/// frames of 16-bit PCM and sends each one to every bubble member.
nonisolated final class AudioSender: @unchecked Sendable {
    private let engine: VoiceEngine
    private let transport: MeshTransport
    private let running = Atomic<Bool>(false)
    private let muted = Atomic<Bool>(false)
    /// Bumped by every `start`, so a thread from an earlier run stops even if `running` is true again.
    private let generation = Atomic<Int>(0)
    /// Held by the running thread: a new run waits for the old one to finish, so the capture ring
    /// and `sequence` only ever have one reader.
    private let runLock = NSLock()
    private var thread: Thread?
    private var sequence: UInt32 = 0

    init(engine: VoiceEngine, transport: MeshTransport) {
        self.engine = engine
        self.transport = transport
    }

    /// Muted frames are still sent, as payload-less silent frames, so receivers' jitter buffers
    /// stay primed and don't mistake mute for network trouble.
    var isMuted: Bool {
        get { muted.load(ordering: .relaxed) }
        set { muted.store(newValue, ordering: .relaxed) }
    }

    func start() {
        guard !running.load(ordering: .acquiring) else { return }
        running.store(true, ordering: .releasing)
        let id = generation.wrappingAdd(1, ordering: .acquiringAndReleasing).newValue
        let thread = Thread { [self] in run(id) }
        thread.name = "audio-bubble.sender"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread
    }

    func stop() {
        running.store(false, ordering: .releasing)
        engine.captureSignal.signal()
        thread = nil
    }

    private func run(_ id: Int) {
        runLock.lock()
        defer { runLock.unlock() }
        func isCurrent() -> Bool {
            running.load(ordering: .acquiring) && generation.load(ordering: .acquiring) == id
        }
        let frame = AudioFormat.frameSamples
        let floats = UnsafeMutablePointer<Float>.allocate(capacity: frame)
        let pcm = UnsafeMutablePointer<Int16>.allocate(capacity: frame)
        defer {
            floats.deallocate()
            pcm.deallocate()
        }
        var packet = Data(count: WireProtocol.audioPacketSize)

        while isCurrent() {
            _ = engine.captureSignal.wait(timeout: .now() + .milliseconds(100))
            while isCurrent(), engine.captureRing.availableToRead >= frame {
                engine.captureRing.read(into: floats, count: frame)
                let isMuted = muted.load(ordering: .relaxed)
                if !isMuted {
                    for i in 0..<frame {
                        let s = max(-1, min(1, floats[i])) * 32_767
                        pcm[i] = Int16(s.rounded())
                    }
                }
                let seq = sequence
                sequence &+= 1
                packet.count = WireProtocol.audioPacketSize
                let length = packet.withUnsafeMutableBytes {
                    WireProtocol.encodeAudio(sender: transport.localID, sequence: seq,
                                             samples: isMuted ? nil : UnsafePointer(pcm), into: $0)
                }
                packet.count = length
                transport.sendAudio(packet)
            }
        }
    }
}
