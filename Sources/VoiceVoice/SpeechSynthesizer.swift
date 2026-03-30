import AVFoundation

/// A speech synthesizer with async/await and callback support.
@MainActor
public final class SpeechSynthesizer {

    private let synthesizer = AVSpeechSynthesizer()
    private let delegate: SynthesizerDelegate

    /// Continuations for async speak() calls, keyed by utterance ObjectIdentifier.
    private var continuations: [ObjectIdentifier: CheckedContinuation<Void, any Error>] = [:]

    /// Active AsyncStream continuations for event broadcasting.
    private var streamContinuations: [UUID: AsyncStream<SpeechEvent>.Continuation] = [:]

    /// Whether the synthesizer is currently speaking.
    public var isSpeaking: Bool { synthesizer.isSpeaking }

    /// Whether the synthesizer is paused.
    public var isPaused: Bool { synthesizer.isPaused }

    /// Default options applied to all utterances unless overridden.
    public var defaultOptions: SpeechOptions

    /// Called for each speech event.
    public var onEvent: ((SpeechEvent) -> Void)?

    public init(defaultOptions: SpeechOptions = .normal) {
        self.defaultOptions = defaultOptions
        self.delegate = SynthesizerDelegate()
        self.synthesizer.delegate = delegate

        delegate.onStart = { [weak self] utterance in
            self?.emit(.started, for: utterance)
        }
        delegate.onFinish = { [weak self] utterance in
            self?.resume(for: utterance, with: .success(()))
            self?.emit(.finished, for: utterance)
        }
        delegate.onPause = { [weak self] utterance in
            self?.emit(.paused, for: utterance)
        }
        delegate.onContinue = { [weak self] utterance in
            self?.emit(.continued, for: utterance)
        }
        delegate.onCancel = { [weak self] utterance in
            self?.resume(for: utterance, with: .failure(VoiceVoiceError.cancelled))
            self?.emit(.cancelled, for: utterance)
        }
        delegate.onWillSpeak = { [weak self] utterance, range in
            let text = (utterance.speechString as NSString).substring(with: range)
            self?.emit(.willSpeakWord(text), for: utterance)
        }
    }

    // MARK: - Speaking (async/await)

    /// Speak text and suspend until speech finishes.
    /// Throws `VoiceVoiceError.cancelled` if stopped before completion.
    public func speak(_ text: String, options: SpeechOptions? = nil) async throws {
        let utterance = makeUtterance(text: text, options: options ?? defaultOptions)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            continuations[ObjectIdentifier(utterance)] = continuation
            synthesizer.speak(utterance)
        }
    }

    // MARK: - Speaking (fire-and-forget)

    /// Enqueue text for speaking without waiting.
    public func enqueue(_ text: String, options: SpeechOptions? = nil) {
        let utterance = makeUtterance(text: text, options: options ?? defaultOptions)
        synthesizer.speak(utterance)
    }

    // MARK: - Playback Control

    /// Stop all speech immediately.
    @discardableResult
    public func stop(at boundary: SpeechBoundary = .immediate) -> Bool {
        synthesizer.stopSpeaking(at: boundary.avBoundary)
    }

    /// Pause speech.
    @discardableResult
    public func pause(at boundary: SpeechBoundary = .immediate) -> Bool {
        synthesizer.pauseSpeaking(at: boundary.avBoundary)
    }

    /// Resume paused speech.
    @discardableResult
    public func resume() -> Bool {
        synthesizer.continueSpeaking()
    }

    // MARK: - Event Stream

    /// An async stream of speech events.
    public var events: AsyncStream<SpeechEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            streamContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.streamContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    // MARK: - Private

    private func makeUtterance(text: String, options: SpeechOptions) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = options.rate
        utterance.pitchMultiplier = options.pitch
        utterance.volume = options.volume
        utterance.preUtteranceDelay = options.preDelay
        utterance.postUtteranceDelay = options.postDelay

        if let voice = options.voice {
            utterance.voice = AVSpeechSynthesisVoice(identifier: voice.id)
        }

        return utterance
    }

    private func resume(for utterance: AVSpeechUtterance, with result: Result<Void, any Error>) {
        let key = ObjectIdentifier(utterance)
        if let continuation = continuations.removeValue(forKey: key) {
            continuation.resume(with: result)
        }
    }

    private func emit(_ event: SpeechEvent, for utterance: AVSpeechUtterance) {
        onEvent?(event)
        for continuation in streamContinuations.values {
            continuation.yield(event)
        }
    }
}

// MARK: - SpeechBoundary

/// When to stop or pause speech.
public enum SpeechBoundary: Sendable {
    case immediate
    case word

    var avBoundary: AVSpeechBoundary {
        switch self {
        case .immediate: return .immediate
        case .word: return .word
        }
    }
}

// MARK: - Delegate

private final class SynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate {

    var onStart: ((AVSpeechUtterance) -> Void)?
    var onFinish: ((AVSpeechUtterance) -> Void)?
    var onPause: ((AVSpeechUtterance) -> Void)?
    var onContinue: ((AVSpeechUtterance) -> Void)?
    var onCancel: ((AVSpeechUtterance) -> Void)?
    var onWillSpeak: ((AVSpeechUtterance, NSRange) -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        onStart?(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish?(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        onPause?(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        onContinue?(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onCancel?(utterance)
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        onWillSpeak?(utterance, characterRange)
    }
}
