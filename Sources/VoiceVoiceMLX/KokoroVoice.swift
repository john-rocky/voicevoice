import Foundation

/// Predefined Kokoro TTS voices.
///
/// Voice naming: first letter = language, second = gender (f=female, m=male).
/// You can also pass any voice name string directly to `MLXSpeechSynthesizer.speak()`.
public enum KokoroVoice: String, CaseIterable, Sendable {
    // American English
    case afHeart = "af_heart"
    case afBella = "af_bella"
    case afNicole = "af_nicole"
    case afSarah = "af_sarah"
    case afSky = "af_sky"
    case amAdam = "am_adam"
    case amMichael = "am_michael"

    // British English
    case bfEmma = "bf_emma"
    case bfIsabella = "bf_isabella"
    case bmGeorge = "bm_george"
    case bmLewis = "bm_lewis"

    // Japanese
    case jfAlpha = "jf_alpha"
    case jfGongitsune = "jf_gongitsune"
    case jmKumo = "jm_kumo"

    // Korean
    case kfBora = "kf_bora"
    case kmJongho = "km_jongho"

    // Chinese (Mandarin)
    case zfXiaobei = "zf_xiaobei"
    case zmYunjian = "zm_yunjian"

    // French
    case ffSiwis = "ff_siwis"

    /// BCP-47 language code for this voice.
    public var language: String {
        switch rawValue.prefix(1) {
        case "a": return "en-US"
        case "b": return "en-GB"
        case "j": return "ja-JP"
        case "k": return "ko-KR"
        case "z": return "zh-CN"
        case "f": return "fr-FR"
        case "e": return "es-ES"
        default: return "en-US"
        }
    }

    /// Whether this is a female voice.
    public var isFemale: Bool {
        rawValue.dropFirst().first == "f"
    }

    /// Default Japanese female voice.
    public static var japanese: KokoroVoice { .jfAlpha }
    /// Default English female voice.
    public static var english: KokoroVoice { .afHeart }
}
