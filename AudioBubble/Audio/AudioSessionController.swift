import AVFoundation
import os

/// Owns the shared AVAudioSession: voice-chat mode at 48 kHz with a 5 ms I/O buffer, and keeps the
/// engine running through interruptions, route changes and media-services resets.
@MainActor
final class AudioSessionController {
    let engine: VoiceEngine
    private let log = Logger(subsystem: "com.jonbobrow.AudioBubble", category: "audio")
    private var observers: [NSObjectProtocol] = []
    private var wantsAudio = false
    /// Called on the main actor when headphones are connected or disconnected.
    var onRouteChange: (() -> Void)?

    init(engine: VoiceEngine) {
        self.engine = engine
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated { self?.handleInterruption(typeValue.flatMap(AVAudioSession.InterruptionType.init)) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onRouteChange?() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMediaServicesReset() }
        })
    }

    /// Hardware input + output latency plus one I/O buffer each way, in milliseconds.
    var hardwareLatencyMilliseconds: Double {
        let session = AVAudioSession.sharedInstance()
        return (session.inputLatency + session.outputLatency + 2 * session.ioBufferDuration) * 1000
    }

    /// Starts audio when in a bubble; stops it (releasing the mic) when not.
    func setActive(_ active: Bool) {
        wantsAudio = active
        if active { start() } else { stop() }
    }

    /// Sets the voice-chat category without activating the session. That changes nothing
    /// audible, but makes `availableInputs` list connected headsets (AirPods), which is how
    /// `headphonesConnected` sees them before a bubble starts.
    static func prepareCategory() {
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat,
                                                         options: [.allowBluetoothHFP, .defaultToSpeaker])
    }

    private func start() {
        do {
            let session = AVAudioSession.sharedInstance()
            Self.prepareCategory()
            try session.setPreferredSampleRate(AudioFormat.sampleRate)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
            try engine.start()
            log.info("audio running: \(session.sampleRate) Hz, I/O \(session.ioBufferDuration * 1000) ms, in \(session.inputLatency * 1000) ms, out \(session.outputLatency * 1000) ms")
        } catch {
            log.error("audio start failed: \(String(describing: error))")
        }
    }

    private func stop() {
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType?) {
        switch type {
        case .began: engine.stop()
        case .ended: if wantsAudio { start() }
        default: break
        }
    }

    private func handleMediaServicesReset() {
        engine.teardown()
        if wantsAudio { start() }
    }

    /// Whether audio is going to headphones (wired, USB or Bluetooth, such as AirPods). The app is
    /// meant to be used with them: from the speaker, everyone nearby hears the bubble too, and
    /// echo cancellation has to work much harder.
    ///
    /// Checks both the current route and the available inputs: while the voice-chat session is
    /// inactive, newly connected AirPods don't become the route until it's activated, but their
    /// mic is already listed as an available input.
    static var headphonesConnected: Bool {
        let session = AVAudioSession.sharedInstance()
        let headphoneOutputs: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio]
        let headsetInputs: Set<AVAudioSession.Port> = [.bluetoothHFP, .bluetoothLE, .headsetMic, .usbAudio]
        return session.currentRoute.outputs.contains { headphoneOutputs.contains($0.portType) }
            || (session.availableInputs ?? []).contains { headsetInputs.contains($0.portType) }
    }

    /// Asks for the microphone up front, so joining a bubble never waits on a prompt.
    static func requestMicrophonePermission() {
        guard AVAudioApplication.shared.recordPermission == .undetermined else { return }
        AVAudioApplication.requestRecordPermission { _ in }
    }

    /// Opens Control Center's Mic Modes, where the user can choose Voice Isolation.
    static func showMicModes() {
        AVCaptureDevice.showSystemUserInterface(.microphoneModes)
    }

    static var micModeName: String {
        switch AVCaptureDevice.activeMicrophoneMode {
        case .voiceIsolation: "Voice Isolation"
        case .wideSpectrum: "Wide Spectrum"
        default: "Standard"
        }
    }
}
