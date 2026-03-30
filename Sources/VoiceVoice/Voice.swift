import AVFoundation

/// Quality tier for a voice.
public enum VoiceQuality: Int, Comparable, Sendable, CaseIterable {
    case `default` = 1
    case enhanced = 2
    case premium = 3

    public static func < (lhs: VoiceQuality, rhs: VoiceQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Gender of a voice.
public enum VoiceGender: Sendable, CaseIterable {
    case unspecified
    case male
    case female
}

/// A speech synthesis voice.
public struct Voice: Sendable, Identifiable, CustomStringConvertible {
    /// Unique identifier (AVSpeechSynthesisVoice.identifier).
    public let id: String
    /// Display name.
    public let name: String
    /// BCP-47 language code (e.g. "en-US", "ja-JP").
    public let language: String
    /// Voice quality tier.
    public let quality: VoiceQuality
    /// Voice gender.
    public let gender: VoiceGender

    public var description: String {
        "\(name) (\(language), \(quality))"
    }

    /// Resolve the underlying AVSpeechSynthesisVoice. Returns nil if no longer available.
    @MainActor
    public var avVoice: AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(identifier: id)
    }
}

// MARK: - Discovery

extension Voice {

    /// All voices available on the system.
    public static var all: [Voice] {
        AVSpeechSynthesisVoice.speechVoices().map { Voice(from: $0) }
    }

    /// Voices filtered by language code (prefix match, e.g. "en" matches "en-US", "en-GB").
    public static func voices(for language: String) -> [Voice] {
        all.filter { $0.language.hasPrefix(language) }
    }

    /// Voices filtered by minimum quality.
    public static func voices(minQuality: VoiceQuality) -> [Voice] {
        all.filter { $0.quality >= minQuality }
    }

    /// Voices matching both language and minimum quality.
    public static func voices(for language: String, minQuality: VoiceQuality) -> [Voice] {
        all.filter { $0.language.hasPrefix(language) && $0.quality >= minQuality }
    }

    /// The best available voice for a language (prefers premium > enhanced > default).
    public static func bestVoice(for language: String) -> Voice? {
        voices(for: language).sorted { $0.quality > $1.quality }.first
    }

    /// The current system language code (BCP-47).
    public static var currentLanguageCode: String {
        AVSpeechSynthesisVoice.currentLanguageCode()
    }

    /// Whether enhanced or premium voices are available for the given language.
    public static func hasHighQualityVoice(for language: String) -> Bool {
        voices(for: language).contains { $0.quality >= .enhanced }
    }

    // MARK: - Internal

    init(from avVoice: AVSpeechSynthesisVoice) {
        self.id = avVoice.identifier
        self.name = avVoice.name
        self.language = avVoice.language

        switch avVoice.quality {
        case .premium:
            self.quality = .premium
        case .enhanced:
            self.quality = .enhanced
        default:
            self.quality = .default
        }

        switch avVoice.gender {
        case .male:
            self.gender = .male
        case .female:
            self.gender = .female
        default:
            self.gender = .unspecified
        }
    }
}
