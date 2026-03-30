import AVFoundation

/// Configuration for a speech utterance.
public struct SpeechOptions: Sendable {
    /// Speech rate. 0.0 (slowest) to 1.0 (fastest). Default is system default rate.
    public var rate: Float
    /// Pitch multiplier. 0.5 to 2.0. Default 1.0.
    public var pitch: Float
    /// Volume. 0.0 to 1.0. Default 1.0.
    public var volume: Float
    /// The voice to use. nil = best voice for system language.
    public var voice: Voice?
    /// Delay before this utterance begins (seconds).
    public var preDelay: TimeInterval
    /// Delay after this utterance finishes (seconds).
    public var postDelay: TimeInterval

    public init(
        rate: Float = AVSpeechUtteranceDefaultSpeechRate,
        pitch: Float = 1.0,
        volume: Float = 1.0,
        voice: Voice? = nil,
        preDelay: TimeInterval = 0,
        postDelay: TimeInterval = 0
    ) {
        self.rate = rate
        self.pitch = pitch
        self.volume = volume
        self.voice = voice
        self.preDelay = preDelay
        self.postDelay = postDelay
    }

    /// Slow rate preset.
    public static var slow: SpeechOptions {
        SpeechOptions(rate: AVSpeechUtteranceDefaultSpeechRate * 0.7)
    }

    /// Normal (default) rate preset.
    public static var normal: SpeechOptions {
        SpeechOptions()
    }

    /// Fast rate preset.
    public static var fast: SpeechOptions {
        SpeechOptions(rate: AVSpeechUtteranceDefaultSpeechRate * 1.5)
    }
}
