import Foundation
import JustCore

/// Grades a typed answer.
///
/// Deliberately forgiving about *script* and strict about *word*. A learner
/// without a Japanese keyboard would otherwise be locked out of every typed
/// question, so romaji is converted and compared too: typing "arauku" for 歩く
/// is a spelling slip, not a vocabulary failure.
public struct AnswerChecker: Sendable {
    public init() {}

    public func check(_ input: String, against question: QuizQuestion) -> QuizOutcome {
        let answer = Self.normalize(input)
        guard !answer.isEmpty else { return .wrong }

        let accepted = question.acceptedAnswers.map(Self.normalize)
        if accepted.contains(answer) { return .correct }

        // Romaji in, kana out — then compare again.
        let asKana = Self.normalize(input.romajiToHiragana())
        if accepted.contains(asKana) { return .correct }

        // Same word, different inflection or a missing okurigana.
        if accepted.contains(where: { Self.isNearMiss(answer, $0) || Self.isNearMiss(asKana, $0) }) {
            return .close
        }
        return .wrong
    }

    /// Katakana folded to hiragana, long vowels and spacing dropped, so the
    /// comparison is about the word rather than how it was typed.
    static func normalize(_ text: String) -> String {
        var result = ""
        for character in text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            if character.isWhitespace || character == "ー" || character == "・" { continue }
            if character.isKatakana,
               let scalar = character.unicodeScalars.first,
               let shifted = Unicode.Scalar(scalar.value - 0x60) {
                result.append(Character(shifted))
            } else {
                result.append(character)
            }
        }
        return result
    }

    /// Shares a stem with the expected answer — the learner knew the word but
    /// wrote the wrong ending.
    private static func isNearMiss(_ answer: String, _ expected: String) -> Bool {
        guard answer.count >= 2, expected.count >= 2 else { return false }
        let stem = String(expected.prefix(max(2, expected.count - 1)))
        return answer.hasPrefix(stem) || expected.hasPrefix(String(answer.prefix(stem.count)))
    }
}

public extension String {
    /// Best-effort romaji to hiragana, for learners typing on a Latin keyboard.
    func romajiToHiragana() -> String {
        guard !isEmpty, allSatisfy({ $0.isASCII }) else { return self }
        let mutable = NSMutableString(string: self) as CFMutableString
        guard CFStringTransform(mutable, nil, kCFStringTransformLatinHiragana, false) else {
            return self
        }
        return mutable as String
    }
}

/// Turns saved vocabulary into questions.
public struct QuizBuilder: Sendable {
    public init() {}

    /// A word with the context needed to quiz it.
    public struct Source: Sendable {
        public let key: String
        public let lemma: String
        public let reading: String
        public let meaning: String
        /// Lyric line and the form the word took in it, when known.
        public let lineText: String?
        public let surface: String?
        public let songLabel: String?

        public init(
            key: String,
            lemma: String,
            reading: String,
            meaning: String,
            lineText: String?,
            surface: String?,
            songLabel: String?
        ) {
            self.key = key
            self.lemma = lemma
            self.reading = reading
            self.meaning = meaning
            self.lineText = lineText
            self.surface = surface
            self.songLabel = songLabel
        }

        /// Cloze needs the lyric and the exact form that appeared in it.
        var supportsCloze: Bool {
            guard let lineText, let surface, !surface.isEmpty else { return false }
            return lineText.contains(surface)
        }
    }

    /// Builds a round.
    ///
    /// `kind` nil mixes the types, which is the default because varying the
    /// retrieval route — recognise, produce, recall in context — tests the word
    /// rather than the format.
    public func build(
        from sources: [Source],
        kind: QuizKind? = nil,
        limit: Int = 20
    ) -> [QuizQuestion] {
        let pool = sources.shuffled().prefix(limit)
        let meanings = sources.map(\.meaning).filter { !$0.isEmpty }

        return pool.compactMap { source in
            let chosen = kind ?? preferredKind(for: source)
            switch chosen {
            case .cloze:
                return source.supportsCloze
                    ? cloze(source)
                    : recall(source)
            case .recall:
                return recall(source)
            case .choice:
                return choice(source, allMeanings: meanings)
            }
        }
    }

    /// Cloze when there is a lyric to hide the word in, otherwise fall back —
    /// a blank with no sentence around it is just a recall question.
    private func preferredKind(for source: Source) -> QuizKind {
        source.supportsCloze
            ? [QuizKind.cloze, .cloze, .recall, .choice].randomElement() ?? .cloze
            : [QuizKind.recall, .choice].randomElement() ?? .recall
    }

    private func cloze(_ source: Source) -> QuizQuestion? {
        guard let lineText = source.lineText, let surface = source.surface else { return nil }
        return QuizQuestion(
            id: "\(source.key).cloze",
            kind: .cloze,
            prompt: lineText.replacingOccurrences(of: surface, with: QuizQuestion.blank),
            context: [source.meaning, source.songLabel].compactMap { $0 }.joined(separator: " · "),
            // The inflected form is what the line needs, but the dictionary
            // form shows the learner knew the word, so both pass.
            acceptedAnswers: [surface, source.lemma, source.reading],
            expected: surface,
            expectedReading: source.reading,
            meaning: source.meaning,
            entryKey: source.key,
            songLabelOnly: source.songLabel
        )
    }

    private func recall(_ source: Source) -> QuizQuestion {
        QuizQuestion(
            id: "\(source.key).recall",
            kind: .recall,
            prompt: source.meaning,
            context: source.songLabel,
            acceptedAnswers: [source.lemma, source.reading],
            expected: source.lemma,
            expectedReading: source.reading,
            meaning: source.meaning,
            entryKey: source.key
        )
    }

    private func choice(_ source: Source, allMeanings: [String]) -> QuizQuestion {
        let distractors = allMeanings
            .filter { $0 != source.meaning }
            .shuffled()
            .prefix(3)
        return QuizQuestion(
            id: "\(source.key).choice",
            kind: .choice,
            prompt: source.lemma,
            context: source.songLabel,
            acceptedAnswers: [source.meaning],
            expected: source.lemma,
            expectedReading: source.reading,
            meaning: source.meaning,
            options: ([source.meaning] + distractors).shuffled(),
            entryKey: source.key
        )
    }
}
