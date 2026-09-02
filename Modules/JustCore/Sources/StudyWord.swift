import Foundation

/// A word the analyser produced for one lyric line, before the user saves it.
///
/// Deliberately a plain value type: the analysis engine has no idea SwiftData
/// exists, and results can be cached, diffed, and previewed without a context.
public struct StudyWord: Identifiable, Hashable, Sendable, Codable {
    public var id: String { "\(surface)|\(dictionaryForm)|\(reading)" }

    /// Exactly as it appears in the lyric, e.g. 歩いてる.
    public let surface: String
    /// Dictionary form, e.g. 歩く.
    public let dictionaryForm: String
    /// Hiragana reading of the dictionary form.
    public let reading: String
    public let meaningKo: String
    public let partOfSpeech: PartOfSpeech
    public let jlpt: JLPTLevel
    /// Why this form differs from the dictionary form, when it does.
    public let note: String

    public init(
        surface: String,
        dictionaryForm: String,
        reading: String,
        meaningKo: String,
        partOfSpeech: PartOfSpeech = .other,
        jlpt: JLPTLevel = .beyond,
        note: String = ""
    ) {
        self.surface = surface
        self.dictionaryForm = dictionaryForm
        self.reading = reading
        self.meaningKo = meaningKo
        self.partOfSpeech = partOfSpeech
        self.jlpt = jlpt
        self.note = note
    }

    /// True when the lyric bends the word — contraction, conjugation, slang.
    public var isInflected: Bool { surface != dictionaryForm }
}

/// A grammar or idiom note attached to a whole line rather than a single word.
public struct GrammarNote: Identifiable, Hashable, Sendable, Codable {
    public var id: String { pattern }
    public let pattern: String
    public let explanationKo: String

    public init(pattern: String, explanationKo: String) {
        self.pattern = pattern
        self.explanationKo = explanationKo
    }
}

/// Everything the engine knows about one lyric line.
public struct LineStudy: Hashable, Sendable, Codable {
    public let lineIndex: Int
    public let original: String
    public let translationKo: String
    public let words: [StudyWord]
    public let grammar: [GrammarNote]
    /// Which engine produced this, so the UI can be honest about quality.
    public let engine: AnalysisEngineKind

    public init(
        lineIndex: Int,
        original: String,
        translationKo: String,
        words: [StudyWord],
        grammar: [GrammarNote],
        engine: AnalysisEngineKind
    ) {
        self.lineIndex = lineIndex
        self.original = original
        self.translationKo = translationKo
        self.words = words
        self.grammar = grammar
        self.engine = engine
    }
}

public extension LineStudy {
    /// The same analysis under another line's index.
    ///
    /// Lyrics repeat: a chorus is several lines with identical text, and asking
    /// the model about each of them separately is paying for the same answer
    /// twice.
    func moved(to lineIndex: Int) -> LineStudy {
        LineStudy(
            lineIndex: lineIndex,
            original: original,
            translationKo: translationKo,
            words: words,
            grammar: grammar,
            engine: engine
        )
    }
}

public enum AnalysisEngineKind: String, Sendable, Codable {
    /// Apple Intelligence, on-device.
    case onDevice
    /// Bundled dictionary lookup — meanings and matched grammar, no
    /// translation. Either the system translator is off, or the model failed
    /// on the line and the translator could not answer it either.
    case dictionary
    /// Dictionary meanings, matched grammar, and the system translator's
    /// Korean line. The whole of what `AnalysisDepth.quick` produces.
    ///
    /// No nuance and a fairly literal sentence — but fast, and complete. This
    /// began as what an old device could manage; it is now also what someone
    /// picks when they would rather read the chorus than wait for it.
    case plainTranslation

    public var label: String {
        switch self {
        case .onDevice: "온디바이스 AI"
        case .dictionary: "사전"
        case .plainTranslation: "사전 + 시스템 번역"
        }
    }
}
