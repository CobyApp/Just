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
            guard !(surface.count == 1 && surface.allSatisfy(\.isHiragana)) else { return false }
            return !JapaneseToken.isFunctionWord(surface) && !JapaneseToken.isFunctionWord(lemma)
        }
    }

    /// Words that are grammar rather than vocabulary.
    ///
    /// The `lexicalClass` switch above should have caught these, and does not:
    /// NLTagger labels almost everything in lyrics `OtherWord`, so the Particle
    /// case never fires. A list is the honest mechanism — the same trade the
    /// rest of this module makes, judgement to the tagger and facts to fixed
    /// data.
    ///
    /// Measured, not imagined: these were the most frequent things the coverage
    /// report called 「모르는 것」 across fifteen songs — 「から」 thirty-two
    /// times, 「じゃ」 twenty-four. Adding them to the dictionary would have been
    /// the wrong fix, because then they become cards to memorise.
    ///
    /// Kana only, deliberately. A kanji word is a word worth learning even when
    /// it is common, and a list of kana cannot swallow one by accident.
    static func isFunctionWord(_ word: String) -> Bool {
        functionWords.contains(word)
    }

    private static let functionWords: Set<String> = [
        // 조사·접속
        "から", "まで", "けど", "けれど", "けれども", "しか", "だけ", "など", "のに",
        "ので", "ばかり", "ほど", "より", "って", "とか", "でも", "ても", "たら",
        "なら", "ながら", "つつ",
        // 지시·대명사
        "これ", "それ", "あれ", "どれ", "この", "その", "あの", "どの",
        "こんな", "そんな", "あんな", "どんな", "ここ", "そこ", "あそこ",
        // 조동사·보조동사
        "です", "ます", "ある", "いる", "する", "なる", "てる", "でる", "てく",
        "しまう", "みる", "おく", "くる", "いく", "ゆく", "られ", "れる", "せる",
        "たく", "だっ", "じゃ", "だろう", "でしょう", "よう", "そう", "みたい",
        "らしい", "はず", "つもり", "わけ", "こそ",
        // 감탄·간투사
        "ほら", "ねえ", "さあ", "もう", "まだ", "もっと", "ずっと", "きっと",
        "やっぱり", "ちょっと",
    ]
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
