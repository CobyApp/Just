import Foundation
import JustCore

/// Offline fallback for devices without Apple Intelligence.
///
/// It cannot translate a line — that genuinely needs a model — so it is honest
/// about it and returns word meanings only. The engine kind is carried through
/// to `LineStudy` so the UI can say which one answered.
public struct DictionarySensei: Sendable {
    public struct Entry: Codable, Sendable {
        let l: String   // lemma
        let r: String   // reading
        let k: String   // Korean meaning
        /// Part of speech and JLPT level are present only on hand-checked
        /// entries. The bulk-imported rows carry neither, and nil means
        /// "unknown" rather than "none" — callers must leave the model's own
        /// answer alone instead of overwriting it with a default.
        let p: String?
        let j: String?

        var partOfSpeech: PartOfSpeech? { p.map(PartOfSpeech.init(rawTag:)) }
        var jlpt: JLPTLevel? { j.map(JLPTLevel.init(rawTag:)) }
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

        // The reading index is consulted only when the lemma carries no kanji
        // of its own. Readings are heavily shared once the dictionary is a few
        // thousand entries deep — かえる alone is 帰る, 変える and 蛙 — so
        // letting a reading outvote an explicit kanji spelling would quietly
        // swap in the wrong word. When the lemma *is* bare kana it has no
        // spelling to contradict, which is exactly the ゆめ→夢 case worth
        // recovering.
        let lemmaIsAmbiguous = !lemma.containsKanji

        if lemmaIsAmbiguous, let reading, let hit = byReading[reading] { return hit }

        for candidate in Deinflector.candidates(for: lemma) {
            if let hit = byLemma[candidate] { return hit }
            if lemmaIsAmbiguous, let hit = byReading[candidate] { return hit }
        }
        if lemmaIsAmbiguous, let reading {
            for candidate in Deinflector.candidates(for: reading) {
                if let hit = byReading[candidate] ?? byLemma[candidate] { return hit }
            }
        }
        return nil
    }

    /// Looks a word up by its written form only, never by reading.
    ///
    /// The spelling in the lyric is ground truth in a way the model's answer is
    /// not: when the model reports 帰る as 「かえる」, the reading index is free
    /// to hand back 変える instead, because both are かえる. Matching on the
    /// kanji the singer actually wrote removes that whole class of mistake.
    public func entry(forSpelling spelling: String) -> Entry? {
        guard spelling.containsKanji else { return nil }
        if let hit = byLemma[spelling] { return hit }
        for candidate in Deinflector.candidates(for: spelling) {
            if let hit = byLemma[candidate] { return hit }
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
                partOfSpeech: entry.partOfSpeech ?? .other,
                jlpt: entry.jlpt ?? .beyond,
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
