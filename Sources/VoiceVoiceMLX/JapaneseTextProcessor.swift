import Foundation
import MLXAudioTTS

/// Custom TextProcessor that wraps the default Kokoro processor but replaces
/// the ByT5 neural G2P for Japanese with Apple's built-in NLP romanization + IPA conversion.
///
/// Apple's CFStringTokenizer with Japanese locale handles kanji readings,
/// particle は→wa, long vowels, and word boundaries correctly.
public final class JapaneseTextProcessor: TextProcessor, @unchecked Sendable {

    private let upstream: TextProcessor

    public init(upstream: TextProcessor) {
        self.upstream = upstream
    }

    public func prepare() async throws {
        try await upstream.prepare()
    }

    public func process(text: String, language: String?) throws -> String {
        let lang = language?.lowercased() ?? ""
        guard lang == "ja" || lang.hasPrefix("ja") else {
            return try upstream.process(text: text, language: language)
        }
        return convertJapaneseToIPA(text)
    }

    // MARK: - Japanese → Romaji (Apple NLP)

    private func convertJapaneseToIPA(_ text: String) -> String {
        let romaji = tokenizeToRomaji(text)
        return romajiToIPA(romaji)
    }

    /// Use CFStringTokenizer with Japanese locale for accurate word-boundary
    /// segmentation and Latin transcription of kanji/kana.
    private func tokenizeToRomaji(_ text: String) -> String {
        let cfText = text as CFString
        let length = CFStringGetLength(cfText)
        let locale = Locale(identifier: "ja_JP") as CFLocale
        let tokenizer = CFStringTokenizerCreate(
            nil, cfText, CFRangeMake(0, length),
            kCFStringTokenizerUnitWordBoundary, locale
        )

        var parts: [String] = []
        var tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)

        while tokenType != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let original = CFStringCreateWithSubstring(nil, cfText, range) as String

            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer, kCFStringTokenizerAttributeLatinTranscription
            ) as? String {
                var romaji = postProcessRomaji(latin, original: original)
                // Expand macron vowels to double vowels
                romaji = expandLongVowels(romaji)
                parts.append(romaji)
            } else {
                // Punctuation / whitespace pass-through
                let normalized = normalizePunctuation(original)
                if !normalized.trimmingCharacters(in: .whitespaces).isEmpty {
                    parts.append(normalized)
                }
            }
            tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }

        return parts.joined(separator: " ")
    }

    /// Fix particle readings and common patterns.
    private func postProcessRomaji(_ romaji: String, original: String) -> String {
        // Standalone particles
        if original == "は" { return "wa" }
        if original == "を" { return "o" }
        if original == "へ" { return "e" }

        // Greetings ending with は (e.g. こんにちは, こんばんは)
        var r = romaji
        if original.hasSuffix("は") && r.hasSuffix("ha") && original.count > 1 {
            r = String(r.dropLast(2)) + "wa"
        }

        // Remove apostrophes (romaji convention for ん before vowel)
        r = r.replacingOccurrences(of: "'", with: "")

        return r
    }

    /// Convert macron vowels (ā ī ū ē ō) to double vowels.
    private func expandLongVowels(_ s: String) -> String {
        s.replacingOccurrences(of: "ā", with: "aa")
         .replacingOccurrences(of: "ī", with: "ii")
         .replacingOccurrences(of: "ū", with: "uu")
         .replacingOccurrences(of: "ē", with: "ee")
         .replacingOccurrences(of: "ō", with: "oo")
    }

    /// Normalize full-width punctuation to half-width.
    private func normalizePunctuation(_ s: String) -> String {
        s.replacingOccurrences(of: "、", with: ",")
         .replacingOccurrences(of: "。", with: ".")
         .replacingOccurrences(of: "！", with: "!")
         .replacingOccurrences(of: "？", with: "?")
         .replacingOccurrences(of: "；", with: ";")
         .replacingOccurrences(of: "：", with: ":")
         .replacingOccurrences(of: "｡", with: ".")
         .replacingOccurrences(of: "､", with: ",")
    }

    // MARK: - Romaji → IPA

    private func romajiToIPA(_ input: String) -> String {
        var result = ""
        var i = input.startIndex

        while i < input.endIndex {
            if let (ipa, next) = matchRomaji(input, at: i) {
                result += ipa
                i = next
            } else {
                let ch = input[i]
                if ch == " " {
                    result += " "
                } else if ",.!?;:".contains(ch) {
                    result += String(ch)
                }
                i = input.index(after: i)
            }
        }

        return result
    }

    /// Try to match a romaji sequence at the given position (longest first).
    private func matchRomaji(_ s: String, at i: String.Index) -> (String, String.Index)? {
        for len in stride(from: 4, through: 1, by: -1) {
            guard let end = s.index(i, offsetBy: len, limitedBy: s.endIndex) else { continue }
            let sub = String(s[i..<end])
            if let ipa = romajiMap[sub] {
                return (ipa, end)
            }
        }
        return nil
    }

    // MARK: - Romaji → IPA Table (Kokoro vocab compatible)

    // Uses IPA characters from Kokoro's vocab:
    //   ɯ(110) ɴ(115) ɲ(114) ɕ(77) ɸ(118) ɾ(125) ç(78)
    //   ʦ(20) ʨ(21) ʣ(18) ʥ(19) ɡ(92) j(52)
    private let romajiMap: [String: String] = {
        var m = [String: String]()

        // 4-char: geminate palatals
        m["sshi"] = "ɕɕi"
        m["cchi"] = "ʨʨi"
        m["ttsu"] = "ʦʦɯ"

        // 3-char: palatalized consonants + affricates
        m["shi"] = "ɕi";  m["chi"] = "ʨi";  m["tsu"] = "ʦɯ"
        m["sha"] = "ɕa";  m["shu"] = "ɕɯ";  m["sho"] = "ɕo"
        m["cha"] = "ʨa";  m["chu"] = "ʨɯ";  m["cho"] = "ʨo"
        m["nya"] = "ɲa";  m["nyu"] = "ɲɯ";  m["nyo"] = "ɲo"
        m["hya"] = "ça";   m["hyu"] = "çɯ";   m["hyo"] = "ço"
        m["rya"] = "ɾja"; m["ryu"] = "ɾjɯ"; m["ryo"] = "ɾjo"
        m["kya"] = "kja";  m["kyu"] = "kjɯ";  m["kyo"] = "kjo"
        m["gya"] = "ɡja"; m["gyu"] = "ɡjɯ"; m["gyo"] = "ɡjo"
        m["mya"] = "mja";  m["myu"] = "mjɯ";  m["myo"] = "mjo"
        m["bya"] = "bja";  m["byu"] = "bjɯ";  m["byo"] = "bjo"
        m["pya"] = "pja";  m["pyu"] = "pjɯ";  m["pyo"] = "pjo"
        m["dya"] = "dja";  m["dyu"] = "djɯ";  m["dyo"] = "djo"

        // 2-char: basic CV syllables
        m["ka"] = "ka"; m["ki"] = "ki"; m["ku"] = "kɯ"; m["ke"] = "ke"; m["ko"] = "ko"
        m["ga"] = "ɡa"; m["gi"] = "ɡi"; m["gu"] = "ɡɯ"; m["ge"] = "ɡe"; m["go"] = "ɡo"
        m["sa"] = "sa"; m["si"] = "ɕi"; m["su"] = "sɯ"; m["se"] = "se"; m["so"] = "so"
        m["za"] = "za"; m["ji"] = "ʥi"; m["zu"] = "zɯ"; m["ze"] = "ze"; m["zo"] = "zo"
        m["ta"] = "ta"; m["ti"] = "ʨi"; m["tu"] = "ʦɯ"; m["te"] = "te"; m["to"] = "to"
        m["da"] = "da"; m["di"] = "di"; m["du"] = "dɯ"; m["de"] = "de"; m["do"] = "do"
        m["na"] = "na"; m["ni"] = "ɲi"; m["nu"] = "nɯ"; m["ne"] = "ne"; m["no"] = "no"
        m["ha"] = "ha"; m["hi"] = "çi"; m["hu"] = "ɸɯ"; m["he"] = "he"; m["ho"] = "ho"
        m["fu"] = "ɸɯ"
        m["ba"] = "ba"; m["bi"] = "bi"; m["bu"] = "bɯ"; m["be"] = "be"; m["bo"] = "bo"
        m["pa"] = "pa"; m["pi"] = "pi"; m["pu"] = "pɯ"; m["pe"] = "pe"; m["po"] = "po"
        m["ma"] = "ma"; m["mi"] = "mi"; m["mu"] = "mɯ"; m["me"] = "me"; m["mo"] = "mo"
        m["ya"] = "ja"; m["yu"] = "jɯ"; m["yo"] = "jo"
        m["ra"] = "ɾa"; m["ri"] = "ɾi"; m["ru"] = "ɾɯ"; m["re"] = "ɾe"; m["ro"] = "ɾo"
        m["wa"] = "wa"; m["wo"] = "o"
        m["nn"] = "ɴ"

        // Geminate consonants
        m["kk"] = "kk"; m["ss"] = "ss"; m["tt"] = "tt"; m["pp"] = "pp"
        m["dd"] = "dd"; m["gg"] = "ɡɡ"; m["bb"] = "bb"; m["zz"] = "zz"

        // 1-char: vowels and isolated consonants
        m["a"] = "a"; m["i"] = "i"; m["u"] = "ɯ"; m["e"] = "e"; m["o"] = "o"
        m["n"] = "ɴ"
        m["k"] = "k"; m["s"] = "s"; m["t"] = "t"; m["h"] = "h"
        m["m"] = "m"; m["r"] = "ɾ"; m["w"] = "w"; m["y"] = "j"
        m["g"] = "ɡ"; m["z"] = "z"; m["d"] = "d"; m["b"] = "b"; m["p"] = "p"
        m["f"] = "ɸ"

        return m
    }()
}
