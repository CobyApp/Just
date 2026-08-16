import Foundation
import JustCore

/// Offline fallback for devices without Apple Intelligence.
///
/// It cannot translate a line — that genuinely needs a model — so it is honest
/// about it and returns word meanings only. The engine kind is carried through
/// to `LineStudy` so the UI can say which one answered.
public struct DictionarySensei: Sendable {
    public struct Entry: Codable, Sendable {
        let l: String  // lemma
        let r: String  // reading
        let k: String  // Korean meaning
        let p: String  // part of speech
        let j: String  // JLPT tag
    }

    private let byLemma: [String: Entry]
    private let byReading: [String: Entry]
    private let tokenizer = JapaneseTokenizer()

    public init(entries: [Entry]) {
        var lemmas: [String: Entry] = [:]
        var readings: [String: Entry] = [:]
        for entry in entries {
            lemmas[entry.l] = entry
            // Only the first entry wins for a reading, so 会う doesn't get
            // shadowed by a later homophone.
            if readings[entry.r] == nil { readings[entry.r] = entry }
        }
        byLemma = lemmas
        byReading = readings
    }

    public init() {
        self.init(bundle: .module)
    }

    init(bundle: Bundle) {
        guard
            let url = bundle.url(forResource: "seed-dictionary", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else {
            self.init(entries: [])
            return
        }
        self.init(entries: entries)
    }

    public var count: Int { byLemma.count }

    public func lookup(lemma: String, reading: String? = nil) -> Entry? {
        if let hit = byLemma[lemma] { return hit }
        if let reading, let hit = byReading[reading] { return hit }

        // Both indexes are tried for every de-inflected candidate: the model
        // often answers in kana ("わすれた"), which matches no kanji headword
        // but does match a reading once it is put back into dictionary form.
        for candidate in Deinflector.candidates(for: lemma) {
            if let hit = byLemma[candidate] ?? byReading[candidate] { return hit }
        }
        if let reading {
            for candidate in Deinflector.candidates(for: reading) {
                if let hit = byReading[candidate] ?? byLemma[candidate] { return hit }
            }
        }
        return nil
    }

    public func analyze(line: String, lineIndex: Int) -> LineStudy {
        let words = tokenizer.studyCandidates(in: line).compactMap { token -> StudyWord? in
            guard let entry = lookup(lemma: token.lemma, reading: token.reading) else {
                return nil
            }
            return StudyWord(
                surface: token.surface,
                dictionaryForm: entry.l,
                reading: entry.r,
                meaningKo: entry.k,
                partOfSpeech: PartOfSpeech(rawTag: entry.p),
                jlpt: JLPTLevel(rawTag: entry.j),
                note: token.surface == entry.l ? "" : "가사에서는 「\(token.surface)」 형태로 쓰였습니다."
            )
        }

        return LineStudy(
            lineIndex: lineIndex,
            original: line,
            translationKo: "",
            words: words,
            grammar: [],
            engine: .dictionary
        )
    }
}

/// Reverses the inflections that `NLTagger` most often leaves in place.
///
/// Pop lyrics lean on contracted spoken forms — 「〜てる」 for 「〜ている」,
/// 「〜とく」 for 「〜ておく」 — which the tagger reports verbatim, so a plain
/// dictionary lookup misses them. These rules run before the lookup gives up.
enum Deinflector {
    private static let suffixRules: [(suffix: String, replacement: String)] = [
        ("ています", "る"), ("ている", "る"), ("てる", "る"), ("てた", "る"), ("てて", "る"),
        ("ちゃう", "る"), ("ちゃった", "る"), ("じゃう", "ぐ"),
        ("ました", "ます"), ("ません", "ます"),
        ("なかった", "ない"),
        ("られる", "る"), ("させる", "する"), ("せる", "す"),
        ("かった", "い"), ("くない", "い"), ("くて", "い"), ("さ", "い"),
    ]

    /// Godan stems: the last kana of the て/た form maps back to a dictionary ending.
    private static let stemEndings: [Character: [String]] = [
        "い": ["く", "ぐ"],
        "っ": ["る", "う", "つ"],
        "ん": ["ぬ", "ぶ", "む"],
        "し": ["す"],
    ]

    static func candidates(for word: String) -> [String] {
        var results: [String] = []

        for rule in suffixRules where word.hasSuffix(rule.suffix) {
            let stem = String(word.dropLast(rule.suffix.count))
            guard !stem.isEmpty else { continue }
            results.append(stem + rule.replacement)
            // Ichidan verbs keep the stem as-is (見てる -> 見る); godan verbs
            // carry a sound change in the last stem kana (行ってる -> 行く).
            if let last = stem.last, let endings = stemEndings[last] {
                let trimmed = String(stem.dropLast())
                guard !trimmed.isEmpty else { continue }
                results.append(contentsOf: endings.map { trimmed + $0 })
            }
        }

        // Bare て/た forms with no auxiliary.
        for suffix in ["て", "た", "で", "だ"] where word.hasSuffix(suffix) && word.count > 1 {
            let stem = String(word.dropLast())
            results.append(stem + "る")
            if let last = stem.last, let endings = stemEndings[last] {
                let trimmed = String(stem.dropLast())
                guard !trimmed.isEmpty else { continue }
                results.append(contentsOf: endings.map { trimmed + $0 })
            }
        }

        return results
    }
}
