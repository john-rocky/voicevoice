import AVFoundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Top-level convenience API for quick speech synthesis.
///
/// Usage:
/// ```swift
/// // Simple
/// try await VoiceVoice.speak("Hello, world!")
///
/// // With options
/// try await VoiceVoice.speak("Hello", voice: .bestVoice(for: "en-US"), rate: 0.4)
///
/// // Fire-and-forget
/// VoiceVoice.enqueue("Hello")
///
/// // Stop
/// VoiceVoice.stop()
/// ```
public enum VoiceVoice {

    /// The shared synthesizer used by all static methods.
    @MainActor
    public static let shared = SpeechSynthesizer()

    // MARK: - Quick Speak

    /// Speak text using the shared synthesizer. Suspends until finished.
    @MainActor
    public static func speak(
        _ text: String,
        voice: Voice? = nil,
        rate: Float? = nil,
        pitch: Float? = nil,
        volume: Float? = nil
    ) async throws {
        var opts = shared.defaultOptions
        if let voice { opts.voice = voice }
        if let rate { opts.rate = rate }
        if let pitch { opts.pitch = pitch }
        if let volume { opts.volume = volume }
        try await shared.speak(text, options: opts)
    }

    /// Speak text without waiting (fire-and-forget).
    @MainActor
    public static func enqueue(
        _ text: String,
        voice: Voice? = nil,
        rate: Float? = nil,
        pitch: Float? = nil,
        volume: Float? = nil
    ) {
        var opts = shared.defaultOptions
        if let voice { opts.voice = voice }
        if let rate { opts.rate = rate }
        if let pitch { opts.pitch = pitch }
        if let volume { opts.volume = volume }
        shared.enqueue(text, options: opts)
    }

    /// Stop all speech on the shared synthesizer.
    @MainActor
    @discardableResult
    public static func stop() -> Bool {
        shared.stop()
    }

    // MARK: - Voice Discovery

    /// All available voices on the system.
    public static var availableVoices: [Voice] { Voice.all }

    /// Best voice for the given language.
    public static func bestVoice(for language: String) -> Voice? {
        Voice.bestVoice(for: language)
    }

    // MARK: - System Settings

    /// Open the system voice download settings (Accessibility > Spoken Content).
    @MainActor
    public static func openVoiceSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?TextToSpeech") {
            NSWorkspace.shared.open(url)
        }
        #elseif os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
