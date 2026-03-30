import AVFoundation
import MLXAudioTTS
import MLXAudioCore
import VoiceVoice

/// A speech synthesizer powered by on-device ML models (Kokoro TTS).
///
/// Usage:
/// ```swift
/// let synth = MLXSpeechSynthesizer()
/// try await synth.speak("Hello, world!")
/// try await synth.speak("こんにちは", voice: .japanese)
/// ```
@MainActor
public final class MLXSpeechSynthesizer: ObservableObject {

    private var model: (any SpeechGenerationModel)?
    private let audioPlayer = AudioPlayer()
    private var speakTask: Task<Void, any Error>?

    /// Whether the model has been loaded.
    @Published public private(set) var isModelLoaded = false

    /// Whether the model is currently being downloaded/loaded.
    @Published public private(set) var isLoadingModel = false

    /// Whether audio is currently being generated or played.
    @Published public private(set) var isSpeaking = false

    /// HuggingFace model repository.
    public let modelRepo: String

    /// Called for each speech event.
    public var onEvent: ((SpeechEvent) -> Void)?

    public init(modelRepo: String = "mlx-community/Kokoro-82M-bf16") {
        self.modelRepo = modelRepo
    }

    /// Pre-load the TTS model. Called automatically on first speak.
    public func loadModel() async throws {
        guard !isModelLoaded else { return }
        isLoadingModel = true
        defer { isLoadingModel = false }
        let loaded = try await TTS.loadModel(modelRepo: modelRepo)

        // Replace the default Japanese G2P with our Apple NLP-based processor
        if let kokoro = loaded as? KokoroModel,
           let upstream = kokoro.textProcessor {
            kokoro.setTextProcessor(JapaneseTextProcessor(upstream: upstream))
        }

        model = loaded
        isModelLoaded = true
    }

    /// Speak text using a Kokoro voice. Suspends until finished.
    public func speak(_ text: String, voice: KokoroVoice = .english) async throws {
        try await speak(text, voiceName: voice.rawValue)
    }

    /// Speak text using a voice name string. Suspends until finished.
    public func speak(_ text: String, voiceName: String) async throws {
        if !isModelLoaded {
            try await loadModel()
        }
        guard let model else { return }

        isSpeaking = true
        onEvent?(.started)

        do {
            let sampleRate = Double(model.sampleRate)
            audioPlayer.startStreaming(sampleRate: sampleRate)

            let stream = model.generateSamplesStream(
                text: text, voice: voiceName,
                refAudio: nil, refText: nil, language: nil
            )
            for try await samples in stream {
                try Task.checkCancellation()
                audioPlayer.scheduleAudioChunk(samples)
            }
            audioPlayer.finishStreamingInput()

            // Wait for playback to drain
            while audioPlayer.isPlaying {
                try await Task.sleep(for: .milliseconds(50))
            }

            isSpeaking = false
            onEvent?(.finished)
        } catch is CancellationError {
            audioPlayer.stop()
            isSpeaking = false
            onEvent?(.cancelled)
            throw VoiceVoiceError.cancelled
        } catch {
            audioPlayer.stop()
            isSpeaking = false
            onEvent?(.cancelled)
            throw error
        }
    }

    /// Speak without waiting (fire-and-forget).
    public func enqueue(_ text: String, voice: KokoroVoice = .english) {
        speakTask = Task {
            try await speak(text, voice: voice)
        }
    }

    /// Stop speaking.
    @discardableResult
    public func stop() -> Bool {
        let wasSpeaking = isSpeaking
        speakTask?.cancel()
        speakTask = nil
        audioPlayer.stop()
        isSpeaking = false
        return wasSpeaking
    }
}
