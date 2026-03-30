import Foundation

/// Errors thrown by VoiceVoice.
public enum VoiceVoiceError: Error, LocalizedError, Sendable {
    /// The requested voice was not found on this device.
    case voiceNotFound(language: String)
    /// The synthesizer is already speaking and cannot accept a new async utterance.
    case alreadySpeaking
    /// The speech was cancelled before completing.
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .voiceNotFound(let language):
            return "No voice found for language: \(language)"
        case .alreadySpeaking:
            return "The synthesizer is already speaking"
        case .cancelled:
            return "Speech was cancelled"
        }
    }
}
