import Foundation
import JustCore
import NaturalLanguage

public struct JapaneseToken: Hashable, Sendable {
    public let surface: String
    /// Hiragana reading produced by ICU transliteration.
    public let reading: String
    /// Dictionary form from `NLTagger`, falling back to the surface form.
    public let lemma: String
    public let lexicalClass: String
    public let range: Range<String.Index>

    /// Words worth putting in front of a learner. Particles, punctuation and
    /// numerals are dropped — a lyric line is mostly those, and surfacing them
    /// buries the two or three words that actually matter.
    public var isStudyCandidate: Bool {
        guard surface.count > 0, !surface.allSatisfy(\.isWhitespace) else { return false }
        guard surface.contains(where: { $0.isJapanese }) else { return false }
        switch lexicalClass {
        case "Particle", "Punctuation", "Number", "Determiner", "Conjunction", "Preposition":
            return false
        default:
            // Single hiragana characters are almost always grammatical glue
            // that NLTagger failed to classify.
            return !(surface.count == 1 && surface.allSatisfy(\.isHiragana))
        }
    }
}

/// Segments Japanese text and attaches readings and dictionary forms.
///
/// Two Apple frameworks are used together because neither is sufficient alone:
/// `CFStringTokenizer` is the only on-device API that gives a *context-aware*
/// reading (it knows 生 is せい in 人生 and なま in 生ビール), while `NLTagger`
/// is the one that gives lemmas. Segmenting once with the tokenizer and then
/// querying the tagger at each token's start index keeps the two aligned.
public struct JapaneseTokenizer: Sendable {
    public init() {}

    public func tokenize(_ text: String) -> [JapaneseToken] {
        guard !text.isEmpty else { return [] }

        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
        tagger.string = text
        tagger.setLanguage(.japanese, range: text.startIndex..<text.endIndex)

        let locale = (Locale(identifier: "ja") as NSLocale) as CFLocale
        let cfText = text as CFString
        let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault,
            cfText,
            CFRangeMake(0, CFStringGetLength(cfText)),
            kCFStringTokenizerUnitWordBoundary,
            locale
        )

        var tokens: [JapaneseToken] = []
        while CFStringTokenizerAdvanceToNextToken(tokenizer).rawValue != 0 {
            let cfRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            guard
                let range = Range(
                    NSRange(location: cfRange.location, length: cfRange.length),
                    in: text
                )
            else { continue }

            let surface = String(text[range])
            guard !surface.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else { continue }

            let transcription = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer,
                kCFStringTokenizerAttributeLatinTranscription
            ) as? String

            let lemmaTag = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0
            let classTag = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lexicalClass).0

            tokens.append(
                JapaneseToken(
                    surface: surface,
                    reading: Self.hiragana(fromRomaji: transcription) ?? surface.toHiragana(),
                    lemma: lemmaTag?.rawValue ?? surface,
                    lexicalClass: classTag?.rawValue ?? "Other",
                    range: range
                )
            )
        }
        return tokens
    }

    /// Words from a line, de-duplicated, in the order they appear.
    public func studyCandidates(in text: String) -> [JapaneseToken] {
        var seen = Set<String>()
        return tokenize(text)
            .filter(\.isStudyCandidate)
            .filter { seen.insert($0.surface).inserted }
    }

    private static func hiragana(fromRomaji romaji: String?) -> String? {
        guard let romaji, !romaji.isEmpty else { return nil }
        let mutable = NSMutableString(string: romaji) as CFMutableString
        guard CFStringTransform(mutable, nil, kCFStringTransformLatinHiragana, false) else {
            return nil
        }
        let result = mutable as String
        return result.isEmpty ? nil : result
    }
}

// MARK: - Character helpers

public extension Character {
    var isHiragana: Bool { ("\u{3040}"..."\u{309F}").contains(self) }
    var isKatakana: Bool { ("\u{30A0}"..."\u{30FF}").contains(self) }
    var isKanji: Bool {
        ("\u{4E00}"..."\u{9FFF}").contains(self) || ("\u{3400}"..."\u{4DBF}").contains(self)
    }
    var isJapanese: Bool { isHiragana || isKatakana || isKanji }
}

public extension String {
    var containsKanji: Bool { contains(where: \.isKanji) }

    /// Best-effort kana conversion, used when the tokenizer gives no
    /// transcription (single symbols, mixed-script fragments).
    func toHiragana() -> String {
        let mutable = NSMutableString(string: self) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformLatinHiragana, false)
        return mutable as String
    }
}
