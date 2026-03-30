import Foundation

/// Events emitted during speech synthesis.
public enum SpeechEvent: Sendable {
    case started
    case finished
    case paused
    case continued
    case cancelled
    /// The synthesizer is about to speak the given word.
    case willSpeakWord(String)
}
