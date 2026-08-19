import Foundation
import SwiftData

public enum JustSchema {
    public static let models: [any PersistentModel.Type] = [
        StudySong.self,
        VocabEntry.self,
        VocabOccurrence.self,
        ReviewState.self,
        StudyDay.self,
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

    public func vocab(key: String) -> VocabEntry? {
        let descriptor = FetchDescriptor<VocabEntry>(
            predicate: #Predicate { $0.key == key }
        )
        return try? context.fetch(descriptor).first
    }

    /// Every saved word as export rows, newest first.
    public func exportRows() -> [VocabularyExport.Row] {
        let descriptor = FetchDescriptor<VocabEntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let entries = (try? context.fetch(descriptor)) ?? []
        return entries.map { entry in
            let occurrence = entry.occurrences.max { $0.capturedAt < $1.capturedAt }
            return VocabularyExport.Row(
                lemma: entry.lemma,
                reading: entry.reading,
                meaningKo: entry.meaningKo,
                jlpt: entry.jlpt.label,
                partOfSpeech: entry.partOfSpeech.rawValue,
                example: occurrence?.lineText ?? "",
                song: occurrence?.song.map { "\($0.artist) — \($0.title)" } ?? ""
            )
        }
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
        let wasNew = state.phase == .new
        state.apply(scheduler.schedule(state, grade: grade))
        record { day in
            day.reviewed += 1
            // A word graded for the first time counts as learned today.
            if wasNew { day.learned += 1 }
        }
    }

    // MARK: - Activity

    /// Applies `change` to today's record, creating it if this is the first
    /// activity of the day.
    private func record(_ change: (StudyDay) -> Void) {
        let today = Calendar.current.startOfDay(for: .now)
        let descriptor = FetchDescriptor<StudyDay>(
            predicate: #Predicate { $0.day == today }
        )
        let day = (try? context.fetch(descriptor).first) ?? {
            let new = StudyDay(day: today)
            context.insert(new)
            return new
        }()
        change(day)
    }

    /// Publishes the numbers the widget shows.
    ///
    /// Called wherever stats are recomputed, so the widget tracks the app
    /// without a second source of truth.
    public func publishWidgetSnapshot(_ stats: StudyStats) {
        let due = dueEntries(limit: 1).first
            ?? (try? context.fetch(FetchDescriptor<VocabEntry>()))?.first
        let occurrence = due?.occurrences.max { $0.capturedAt < $1.capturedAt }

        WidgetStore.write(
            WidgetSnapshot(
                dueCount: stats.dueCount,
                streak: stats.streak,
                totalWords: stats.totalWords,
                word: due.map { entry in
                    WidgetSnapshot.Word(
                        lemma: entry.lemma,
                        reading: entry.reading,
                        meaningKo: entry.meaningKo,
                        songLabel: occurrence?.song.map { "\($0.artist) — \($0.title)" }
                    )
                }
            )
        )
    }

    public func stats(weekLength: Int = 7) -> StudyStats {
        let days = (try? context.fetch(FetchDescriptor<StudyDay>())) ?? []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let todayRecord = days.first { $0.day == today }

        let entries = (try? context.fetch(FetchDescriptor<VocabEntry>())) ?? []
        var levels: [JLPTLevel: Int] = [:]
        for entry in entries {
            levels[entry.jlpt, default: 0] += 1
        }

        let byDay = Dictionary(
            days.map { (calendar.startOfDay(for: $0.day), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // Built by walking the calendar rather than by grouping the records, so
        // days with no activity still appear as zero-height bars.
        let week: [DayActivity] = (0..<weekLength).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            let record = byDay[day]
            return DayActivity(
                day: day,
                reviewed: record?.reviewed ?? 0,
                learned: record?.learned ?? 0
            )
        }

        return StudyStats(
            reviewedToday: todayRecord?.reviewed ?? 0,
            learnedToday: todayRecord?.learned ?? 0,
            streak: StreakCalculator.streak(days: days.map(\.day)),
            totalWords: entries.count,
            dueCount: dueEntries(limit: 500).count,
            levelCounts: levels,
            week: week
        )
    }
}
