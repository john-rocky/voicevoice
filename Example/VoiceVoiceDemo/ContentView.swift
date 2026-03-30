import SwiftUI
import VoiceVoice
import VoiceVoiceMLX

enum SpeechEngine: String, CaseIterable {
    case system = "System"
    case mlx = "MLX (Kokoro)"
}

struct ContentView: View {

    @State private var text = "Hello! VoiceVoice makes text-to-speech simple and natural."
    @State private var engine: SpeechEngine = .system
    @State private var isSpeaking = false
    @State private var isPaused = false
    @State private var eventLog: [String] = []

    // System engine state
    @State private var selectedLanguage = Voice.currentLanguageCode
    @State private var voices: [Voice] = []
    @State private var selectedVoiceID: String?
    @State private var rate: Double = 0.5
    @State private var pitch: Double = 1.0
    @State private var volume: Double = 1.0

    // MLX engine state
    @State private var mlxSynth = MLXSpeechSynthesizer()
    @State private var selectedKokoroVoice: KokoroVoice = .afHeart
    @State private var isLoadingModel = false

    private let languages = [
        "en-US", "en-GB", "ja-JP", "zh-CN", "zh-TW",
        "ko-KR", "fr-FR", "de-DE", "es-ES", "it-IT",
        "pt-BR", "ru-RU", "ar-SA", "hi-IN", "th-TH"
    ]

    var body: some View {
        #if os(iOS)
        NavigationStack {
            mainForm
                .navigationTitle("VoiceVoice Demo")
                .navigationBarTitleDisplayMode(.inline)
        }
        #else
        ScrollView {
            mainForm
                .padding()
        }
        #endif
    }

    private var mainForm: some View {
        VStack(spacing: 20) {
            // MARK: - Engine
            GroupBox("Engine") {
                Picker("Engine", selection: $engine) {
                    ForEach(SpeechEngine.allCases, id: \.self) { e in
                        Text(e.rawValue).tag(e)
                    }
                }
                .pickerStyle(.segmented)
            }

            // MARK: - Text Input
            GroupBox("Text") {
                TextEditor(text: $text)
                    .frame(minHeight: 80, maxHeight: 120)
            }

            // MARK: - Voice
            if engine == .system {
                systemVoiceSection
            } else {
                mlxVoiceSection
            }

            // MARK: - Options (system only)
            if engine == .system {
                GroupBox("Options") {
                    VStack(spacing: 8) {
                        LabeledSlider(label: "Rate", value: $rate, range: 0...1)
                        LabeledSlider(label: "Pitch", value: $pitch, range: 0.5...2.0)
                        LabeledSlider(label: "Volume", value: $volume, range: 0...1)
                    }
                }
            }

            // MARK: - Playback
            GroupBox("Playback") {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Button {
                            speak()
                        } label: {
                            Label(isLoadingModel ? "Loading Model..." : "Speak",
                                  systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(text.isEmpty || isSpeaking || isLoadingModel)

                        if engine == .system {
                            Button {
                                togglePause()
                            } label: {
                                Label(isPaused ? "Resume" : "Pause",
                                      systemImage: isPaused ? "play.fill" : "pause.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!isSpeaking)
                        }

                        Button(role: .destructive) {
                            stopSpeaking()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!isSpeaking)
                    }
                }
            }

            // MARK: - Event Log
            GroupBox {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(eventLog.enumerated()), id: \.offset) { _, entry in
                            Text(entry)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 120)
            } label: {
                HStack {
                    Text("Events")
                    Spacer()
                    Button("Clear") { eventLog.removeAll() }
                        .font(.caption)
                }
            }
        }
        .onAppear {
            refreshVoices()
        }
    }

    // MARK: - System Voice Section

    private var systemVoiceSection: some View {
        GroupBox("Voice") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Language", selection: $selectedLanguage) {
                    ForEach(languages, id: \.self) { lang in
                        Text(lang).tag(lang)
                    }
                }

                if !voices.isEmpty {
                    Picker("Voice", selection: $selectedVoiceID) {
                        Text("Best Available").tag(nil as String?)
                        ForEach(voices) { voice in
                            Text("\(voice.name) (\(qualityLabel(voice.quality)))")
                                .tag(voice.id as String?)
                        }
                    }
                } else {
                    Text("No voices for \(selectedLanguage)")
                        .foregroundStyle(.secondary)
                }

                if !Voice.hasHighQualityVoice(for: selectedLanguage) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Only default voices. Download Enhanced/Premium in System Settings, or use MLX engine.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        VoiceVoice.openVoiceSettings()
                    } label: {
                        Label("Open Voice Settings", systemImage: "arrow.down.circle")
                    }
                    .font(.caption)
                }
            }
        }
        .onChange(of: selectedLanguage) { _ in
            refreshVoices()
        }
    }

    // MARK: - MLX Voice Section

    private var mlxVoiceSection: some View {
        GroupBox("Voice (Kokoro)") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Voice", selection: $selectedKokoroVoice) {
                    ForEach(KokoroVoice.allCases, id: \.self) { voice in
                        Text("\(voice.rawValue) (\(voice.language))")
                            .tag(voice)
                    }
                }

                if !mlxSynth.isModelLoaded {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text("Kokoro model (~300MB) will be downloaded on first use.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Model loaded and ready.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    Task {
                        isLoadingModel = true
                        eventLog.append("> Loading Kokoro model...")
                        do {
                            try await mlxSynth.loadModel()
                            eventLog.append("  Model loaded!")
                        } catch {
                            eventLog.append("  Error: \(error.localizedDescription)")
                        }
                        isLoadingModel = false
                    }
                } label: {
                    Label("Pre-load Model", systemImage: "arrow.down.circle")
                }
                .font(.caption)
                .disabled(mlxSynth.isModelLoaded || isLoadingModel)
            }
        }
    }

    // MARK: - Actions

    private func speak() {
        isSpeaking = true
        isPaused = false

        if engine == .system {
            speakSystem()
        } else {
            speakMLX()
        }
    }

    private func speakSystem() {
        let voice = resolveSystemVoice()
        eventLog.append("> [System] Speaking...")

        VoiceVoice.shared.onEvent = { event in
            eventLog.append("  \(eventLabel(event))")
            if case .finished = event { isSpeaking = false; isPaused = false }
            if case .cancelled = event { isSpeaking = false; isPaused = false }
        }

        Task {
            do {
                let opts = SpeechOptions(
                    rate: Float(rate), pitch: Float(pitch), volume: Float(volume), voice: voice
                )
                try await VoiceVoice.shared.speak(text, options: opts)
            } catch {
                eventLog.append("  Error: \(error.localizedDescription)")
                isSpeaking = false
            }
        }
    }

    private func speakMLX() {
        eventLog.append("> [MLX] Speaking with \(selectedKokoroVoice.rawValue)...")
        isLoadingModel = !mlxSynth.isModelLoaded

        mlxSynth.onEvent = { event in
            eventLog.append("  \(eventLabel(event))")
        }

        Task {
            do {
                try await mlxSynth.speak(text, voice: selectedKokoroVoice)
                isSpeaking = false
            } catch {
                eventLog.append("  Error: \(error.localizedDescription)")
                isSpeaking = false
            }
            isLoadingModel = false
        }
    }

    private func togglePause() {
        if isPaused {
            VoiceVoice.shared.resume()
            isPaused = false
        } else {
            VoiceVoice.shared.pause()
            isPaused = true
        }
    }

    private func stopSpeaking() {
        if engine == .system {
            VoiceVoice.stop()
        } else {
            mlxSynth.stop()
        }
        isSpeaking = false
        isPaused = false
    }

    // MARK: - Helpers

    private func refreshVoices() {
        voices = Voice.voices(for: selectedLanguage)
            .sorted { $0.quality > $1.quality }
        selectedVoiceID = nil
    }

    private func resolveSystemVoice() -> Voice? {
        if let id = selectedVoiceID {
            return voices.first { $0.id == id }
        }
        return Voice.bestVoice(for: selectedLanguage)
    }

    private func qualityLabel(_ q: VoiceQuality) -> String {
        switch q {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        case .default: return "Default"
        }
    }

    private func eventLabel(_ event: SpeechEvent) -> String {
        switch event {
        case .started: return "[Started]"
        case .finished: return "[Finished]"
        case .paused: return "[Paused]"
        case .continued: return "[Continued]"
        case .cancelled: return "[Cancelled]"
        case .willSpeakWord(let word): return "Speaking: \(word)"
        }
    }
}

// MARK: - Components

private struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 55, alignment: .leading)
            Slider(value: $value, in: range)
            Text(String(format: "%.2f", value))
                .monospacedDigit()
                .frame(width: 40)
        }
    }
}
