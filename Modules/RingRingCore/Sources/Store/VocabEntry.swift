import Foundation
import SwiftData

/// One vocabulary item, unique across the whole library.
///
/// The same word turning up in several songs is the point of the app, so the
/// entry is keyed by dictionary form + reading and the songs hang off it as
/// `occurrences` rather than each song owning its own copy.
@Model
public final class VocabEntry {
    #Unique<VocabEntry>([\.key])

    /// "夜明け|よあけ" — dictionary form and reading, so homographs stay distinct.
    public var key: String = ""
    public var lemma: String = ""
    public var reading: String = ""
    public var meaningKo: String = ""
    public var partOfSpeechRaw: String = PartOfSpeech.other.rawValue
    public var jlptRaw: String = JLPTLevel.beyond.rawValue
    /// Colloquial / contracted / lyric-specific usage note. Often the most
    /// useful field for pop lyrics.
    public var note: String = ""
    public var createdAt: Date = Date.distantPast
    public var isStarred: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \VocabOccurrence.vocab)
    public var occurrences: [VocabOccurrence] = []

    @Relationship(deleteRule: .cascade)
    public var review: ReviewState?

    public init(
        lemma: String,
        reading: String,
        meaningKo: String,
        partOfSpeech: PartOfSpeech = .other,
        jlpt: JLPTLevel = .beyond,
        note: String = ""
    ) {
        self.key = Self.key(lemma: lemma, reading: reading)
        self.lemma = lemma
        self.reading = reading
        self.meaningKo = meaningKo
        self.partOfSpeechRaw = partOfSpeech.rawValue
        self.jlptRaw = jlpt.rawValue
        self.note = note
        self.createdAt = .now
    }

    public static func key(lemma: String, reading: String) -> String {
        "\(lemma)|\(reading)"
    }

    public var partOfSpeech: PartOfSpeech {
        get { PartOfSpeech(rawTag: partOfSpeechRaw) }
        set { partOfSpeechRaw = newValue.rawValue }
    }

    public var jlpt: JLPTLevel {
        get { JLPTLevel(rawTag: jlptRaw) }
        set { jlptRaw = newValue.rawValue }
    }

    /// Only show the reading when it actually adds information.
    public var showsReading: Bool { reading != lemma && !reading.isEmpty }
}

/// Where a word showed up: which song, which line, and the line itself so the
/// review card can quote the lyric as the example sentence.
@Model
public final class VocabOccurrence {
    public var surface: String = ""
    public var lineIndex: Int = 0
    public var lineText: String = ""
    public var lineTranslation: String?
    public var capturedAt: Date = Date.distantPast

    public var song: StudySong?
    public var vocab: VocabEntry?

    public init(
        surface: String,
        lineIndex: Int,
        lineText: String,
        lineTranslation: String?
    ) {
        self.surface = surface
        self.lineIndex = lineIndex
        self.lineText = lineText
        self.lineTranslation = lineTranslation
        self.capturedAt = .now
    }
}
