import Foundation
import SwiftData

public enum JustSchema {
    public static let models: [any PersistentModel.Type] = [
        StudySong.self,
        VocabEntry.self,
        VocabOccurrence.self,
        ReviewState.self,
    ]

    public static func container(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: Schema(models),
            configurations: configuration
        )
    }
}

/// Writes that touch more than one model live here so the screens stay thin
/// and the de-duplication rule has exactly one home.
@MainActor
public struct JustStore {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Songs

    public func song(videoID: String) -> StudySong? {
        let descriptor = FetchDescriptor<StudySong>(
            predicate: #Predicate { $0.videoID == videoID }
        )
        return try? context.fetch(descriptor).first
    }

    @discardableResult
    public func upsertSong(_ track: Track) -> StudySong {
        if let existing = song(videoID: track.id) {
            existing.lastOpenedAt = .now
            return existing
        }
        let song = StudySong(track: track)
        song.lastOpenedAt = .now
        context.insert(song)
        return song
    }

    // MARK: - Vocabulary

    public func vocab(lemma: String, reading: String) -> VocabEntry? {
        let key = VocabEntry.key(lemma: lemma, reading: reading)
        let descriptor = FetchDescriptor<VocabEntry>(
            predicate: #Predicate { $0.key == key }
        )
        return try? context.fetch(descriptor).first
    }

    /// Saves a word and links it to the line it came from.
    ///
    /// If the word already exists the entry is reused and only a new
    /// occurrence is added — that is what makes "this word shows up in 3 of
    /// your songs" possible.
    @discardableResult
    public func save(
        _ word: StudyWord,
        from song: StudySong,
        lineIndex: Int,
        lineText: String,
        lineTranslation: String?
    ) -> VocabEntry {
        let entry = vocab(lemma: word.dictionaryForm, reading: word.reading)
            ?? {
                let new = VocabEntry(
                    lemma: word.dictionaryForm,
                    reading: word.reading,
                    meaningKo: word.meaningKo,
                    partOfSpeech: word.partOfSpeech,
                    jlpt: word.jlpt,
                    note: word.note
                )
                new.review = ReviewState()
                context.insert(new)
                return new
            }()

        let alreadyLinked = entry.occurrences.contains {
            $0.song?.videoID == song.videoID && $0.lineIndex == lineIndex
        }
        if !alreadyLinked {
            let occurrence = VocabOccurrence(
                surface: word.surface,
                lineIndex: lineIndex,
                lineText: lineText,
                lineTranslation: lineTranslation
            )
            occurrence.song = song
            occurrence.vocab = entry
            context.insert(occurrence)
        }
        return entry
    }

    public func remove(_ entry: VocabEntry) {
        context.delete(entry)
    }

    // MARK: - Review queue

    public func dueEntries(limit: Int = 40, now: Date = .now) -> [VocabEntry] {
        var descriptor = FetchDescriptor<VocabEntry>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 500
        let all = (try? context.fetch(descriptor)) ?? []
        return all
            .filter { ($0.review?.due ?? .distantPast) <= now }
            .sorted { ($0.review?.due ?? .distantPast) < ($1.review?.due ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    public func grade(_ entry: VocabEntry, _ grade: ReviewGrade, scheduler: FSRS = FSRS()) {
        let state = entry.review ?? {
            let new = ReviewState()
            entry.review = new
            return new
        }()
        state.apply(scheduler.schedule(state, grade: grade))
    }
}
