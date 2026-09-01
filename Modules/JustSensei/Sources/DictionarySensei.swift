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

    /// Every sense, not one per spelling.
    ///
    /// This was `[String: Entry]`, which meant the last row read for a spelling
    /// silently erased the others at load time. Only eight spellings in the
    /// bundled data are affected — but 僕 is one of them, and it resolved to
    /// しもべ (a servant) rather than ぼく, on a word J-pop uses constantly.
    /// Counting the collisions said they were negligible; weighting them by how
    /// often lyrics use the word said otherwise.
    private let byLemma: [String: [Entry]]
    private let byReading: [String: Entry]
    private let tokenizer = JapaneseTokenizer()

    public init(entries: [Entry]) {
        var lemmas: [String: [Entry]] = [:]
        var readings: [String: Entry] = [:]
        for entry in entries {
            lemmas[entry.l, default: []].append(entry)
            // Only the first entry wins for a reading, so 会う doesn't get
            // shadowed by a later homophone.
            if readings[entry.r] == nil { readings[entry.r] = entry }
        }
        byLemma = lemmas
        byReading = readings
    }

    /// The sense whose reading matches, or the first one when nothing names it.
    private func sense(_ candidates: [Entry]?, reading: String?) -> Entry? {
        guard let candidates, !candidates.isEmpty else { return nil }
        guard let reading, !reading.isEmpty else { return candidates.first }
        return candidates.first { $0.r == reading } ?? candidates.first
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

    /// What the line's words mean, for handing to the model before it answers.
    ///
    /// The model is good at reading a sentence and bad at recall, and the two
    /// failures it makes here are both recall: it wrote 「공기」 for 空, which is
    /// 空気 — a different word the dictionary has right — and it pads short
    /// lines with things that are not in them. Telling it what the words are
    /// gives it less room for either.
    ///
    /// Only what the dictionary actually holds. A guessed gloss would ground
    /// the model in an invention, which is worse than leaving it to guess.
    ///
    /// Capped, because the context window overflows after three lines as it is
    /// and a list that grew with the line would bring that forward.
    public func glossary(for line: String, limit: Int = 4) -> [String] {
        var seen = Set<String>()
        var withKanji: [String] = []
        var kanaOnly: [String] = []

        for token in tokenizer.studyCandidates(in: line) {
            guard let entry = entry(forSpelling: token.surface, reading: token.reading)
                ?? lookup(lemma: token.lemma, reading: token.reading)
            else { continue }
            guard !entry.k.isEmpty else { continue }
            // A kana word matched to a kanji headword is a reading collision,
            // not a match: 「だけ」 — the particle — found 丈(だけ), 「길이, 키」,
            // and the prompt tells the model to follow what it is given. The
            // lyric wrote it in kana; the dictionary's kanji word is a
            // different word that happens to sound the same.
            guard LineScript.hasJapanese(token.surface) else { continue }
            if !Self.containsKanji(token.surface), Self.containsKanji(entry.l) { continue }
            guard seen.insert(entry.l).inserted else { continue }

            let gloss = "\(entry.l)(\(entry.r)) \(entry.k)"
            // Kanji words go in first. They are where the misreadings are —
            // 空 came back as 「공기」, which is 空気 — while a kana word says its
            // own reading and leaves the model much less room. With the list
            // capped for context, the ambiguous ones are worth the slots.
            if Self.containsKanji(entry.l) {
                withKanji.append(gloss)
            } else {
                kanaOnly.append(gloss)
            }
        }
        return Array((withKanji + kanaOnly).prefix(limit))
    }

    private static func containsKanji(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (0x3400...0x4DBF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value)
        }
    }

    /// The Korean meanings the dictionary can find in a line.
    ///
    /// The glossary's raw material, exposed because a check outside this type
    /// needs the same question answered: which of these meanings belong to this
    /// line, and which came from somewhere else.
    public func meanings(in line: String) -> [String] {
        var results: [String] = []
        for token in tokenizer.studyCandidates(in: line) {
            guard let entry = entry(forSpelling: token.surface, reading: token.reading)
                ?? lookup(lemma: token.lemma, reading: token.reading)
            else { continue }
            guard !entry.k.isEmpty else { continue }
            if !Self.containsKanji(token.surface), Self.containsKanji(entry.l) { continue }
            results.append(entry.k)
        }
        return results
    }

    public func lookup(lemma: String, reading: String? = nil) -> Entry? {
        if let hit = sense(byLemma[lemma], reading: reading) { return hit }

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
            if let hit = sense(byLemma[candidate], reading: reading) { return hit }
            if lemmaIsAmbiguous, let hit = byReading[candidate] { return hit }
        }
        if lemmaIsAmbiguous, let reading {
            for candidate in Deinflector.candidates(for: reading) {
                if let hit = byReading[candidate] ?? sense(byLemma[candidate], reading: reading) {
                    return hit
                }
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
    /// - Parameter reading: how the line reads this spelling, when known. It is
    ///   what separates 僕/ぼく from 僕/しもべ; without it the first sense is
    ///   returned, which is a guess rather than an answer.
    public func entry(forSpelling spelling: String, reading: String? = nil) -> Entry? {
        guard spelling.containsKanji else { return nil }
        if let hit = sense(byLemma[spelling], reading: reading) { return hit }
        for candidate in Deinflector.candidates(for: spelling) {
            if let hit = sense(byLemma[candidate], reading: reading) { return hit }
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

    /// Godan stems: the last kana of the て/た form maps back to a dictionary
    /// ending.
    ///
    /// A candidate that is wrong costs nothing — every one is looked up and
    /// discarded if absent — so the lists are generous rather than precise.
    /// 「っ」 includes く for 行く, which is irregular but far too common in
    /// lyrics to leave out: 行ってる would otherwise never resolve.
    private static let stemEndings: [Character: [String]] = [
        "い": ["く", "ぐ"],
        "っ": ["る", "う", "つ", "く"],
        "ん": ["ぬ", "ぶ", "む"],
        "し": ["す"],
    ]

    /// A stem's own ending, mapped back to the dictionary form's.
    ///
    /// The tagger reports a bare 連用形 or 未然形 — 「沈み」, 「言い」, 「戻ら」 —
    /// with nothing attached to strip, so the て/た rules below never fire and
    /// the lookup gives up on a word the dictionary actually holds. Fourteen of
    /// the twenty-nine misses in the coverage report were exactly this.
    ///
    /// Both the い-row (連用形) and the あ-row (未然形) map to the same う-row
    /// ending, so one table covers both.
    private static let stemToDictionary: [Character: [String]] = [
        "い": ["う", "く"], "き": ["く"], "ぎ": ["ぐ"], "し": ["す"], "ち": ["つ"],
        "に": ["ぬ"], "び": ["ぶ"], "み": ["む"], "り": ["る"],
        "わ": ["う"], "か": ["く"], "が": ["ぐ"], "さ": ["す"], "た": ["つ"],
        "な": ["ぬ"], "ば": ["ぶ"], "ま": ["む"], "ら": ["る"],
        "っ": ["る", "う", "つ"],
        "ん": ["ぬ", "ぶ", "む"],
    ]

    static func candidates(for word: String) -> [String] {
        var results: [String] = []

        // Read as a stem first. Every candidate is looked up and discarded if
        // the dictionary does not have it, so guessing generously costs nothing
        // — 「疲れ」 proposes both 疲れる and 疲る, and only one exists.
        if word.count > 1 {
            results.append(word + "る")
            if let last = word.last, let endings = stemToDictionary[last] {
                let trimmed = String(word.dropLast())
                if !trimmed.isEmpty {
                    results.append(contentsOf: endings.map { trimmed + $0 })
                }
            }
        }

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
