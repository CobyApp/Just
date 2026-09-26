import Foundation
import SwiftData
#if canImport(WidgetKit)
import WidgetKit
#endif

public enum JustSchema {
    public static let models: [any PersistentModel.Type] = [
        StudySong.self,
        VocabEntry.self,
        VocabOccurrence.self,
        ReviewState.self,
        StudyDay.self,
    ]

    private static let migrationKey = "store.legacyMigrationChecked"

    /// Opens the app's store.
    ///
    /// On disk it lives in the App Group container, named explicitly rather
    /// than left to `.automatic` — see `StoreLocation` for why that mattered
    /// and for the one-time copy of a pre-widget store that runs first.
    public static func container(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        guard !inMemory else {
            return try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }

        guard let group = StoreLocation.groupDirectory else {
            // No App Group — a build without the entitlement. Stay exactly
            // where such a build always kept the store.
            let url = StoreLocation.legacyDirectory.appending(path: StoreLocation.storeName)
            return try ModelContainer(for: schema, configurations: ModelConfiguration(url: url))
        }

        // Checked once per install: the old file is copied, never removed,
        // so without the flag every launch would open the group store twice
        // just to find out again that it has data.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: migrationKey) {
            let outcome = StoreLocation.migrate(
                from: StoreLocation.legacyDirectory,
                to: group,
                schema: schema
            )
            if outcome != .failed { defaults.set(true, forKey: migrationKey) }
        }

        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(groupContainer: .identifier(StoreLocation.appGroup))
        )
    }
}

/// The pending widget/reminder refresh, so a burst of saves publishes once.
@MainActor
private enum ActivityDebounce {
    static var pending: Task<Void, Never>?
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
        noteActivity()
        return entry
    }

    public func vocab(key: String) -> VocabEntry? {
        let descriptor = FetchDescriptor<VocabEntry>(
            predicate: #Predicate { $0.key == key }
        )
        return try? context.fetch(descriptor).first
    }

    /// Every grammar note the model has produced, with where it came from.
    ///
    /// These are already generated and already persisted on each song, and until
    /// now the only way to see one was to reopen the exact line it came from.
    /// Patterns repeat across songs far more than vocabulary does — 「〜 てしまう」
    /// turns up everywhere — so the same grouping that makes the word list
    /// useful applies here.
    public func grammarNotes(limit: Int = 200) -> [GrammarSighting] {
        var descriptor = FetchDescriptor<StudySong>(
            sortBy: [SortDescriptor(\.lastOpenedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        let songs = (try? context.fetch(descriptor)) ?? []

        var byPattern: [String: GrammarSighting] = [:]
        var order: [String] = []

        for song in songs {
            let label = "\(song.artist) — \(song.title)"
            for study in song.analyses.values.sorted(by: { $0.lineIndex < $1.lineIndex }) {
                for note in study.grammar {
                    let key = note.pattern.trimmingCharacters(in: .whitespaces)
                    guard !key.isEmpty else { continue }

                    if var existing = byPattern[key] {
                        existing.addSighting(song: label)
                        byPattern[key] = existing
                    } else {
                        order.append(key)
                        byPattern[key] = GrammarSighting(
                            pattern: key,
                            explanationKo: note.explanationKo,
                            example: study.original,
                            exampleTranslation: study.translationKo,
                            song: label
                        )
                    }
                }
            }
        }

        // Most-seen first: a pattern in four songs is the one worth learning
        // next, and that ranking is only visible once they are pooled.
        return order
            .compactMap { byPattern[$0] }
            .sorted { $0.songCount > $1.songCount }
            .prefix(limit)
            .map { $0 }
    }

    /// Words the user keeps getting wrong.
    ///
    /// FSRS already records every lapse and a per-word difficulty; nothing read
    /// them. These are the words a learner would pick out by hand if they could
    /// remember which ones they were.
    ///
    /// Ordered by lapses first and difficulty second: three failures is a
    /// stronger signal than a high difficulty score, which the scheduler also
    /// raises for words merely answered slowly.
    ///
    /// Filtered and ordered by the store, not in memory: fetching a fixed
    /// number of rows first and sorting those meant a library past that size
    /// only ever looked at whichever words happened to come back.
    public func strugglingEntries(limit: Int = 40) -> [VocabEntry] {
        var descriptor = FetchDescriptor<VocabEntry>(
            predicate: #Predicate { ($0.review?.lapses ?? 0) > 0 },
            sortBy: [
                SortDescriptor(\VocabEntry.review?.lapses, order: .reverse),
                SortDescriptor(\VocabEntry.review?.difficulty, order: .reverse),
            ]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Every saved word as export rows, newest first.
    public func exportRows() -> [VocabularyExport.Row] {
        Self.exportRows(in: context)
    }

    /// The same, from any context — the share sheet builds the file off the
    /// main actor, in a context of its own.
    public nonisolated static func exportRows(in context: ModelContext) -> [VocabularyExport.Row] {
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

    /// Cards due at `now`, most overdue first.
    ///
    /// The filter and the order are both pushed into the fetch. Fetching the
    /// oldest 500 words and filtering those meant that in a larger library
    /// every word saved after the 500th never came up for review at all.
    public func dueEntries(limit: Int = 40, now: Date = .now) -> [VocabEntry] {
        var descriptor = FetchDescriptor<VocabEntry>(
            predicate: Self.duePredicate(now: now),
            // A word without review state sorts first (NULL), matching its
            // treatment as due since forever.
            sortBy: [SortDescriptor(\VocabEntry.review?.due), SortDescriptor(\VocabEntry.createdAt)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    /// How many cards are due at `now`, counted by the store.
    public func dueCount(now: Date = .now) -> Int {
        let descriptor = FetchDescriptor<VocabEntry>(predicate: Self.duePredicate(now: now))
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    private static func duePredicate(now: Date) -> Predicate<VocabEntry> {
        // A word with no review state has never been scheduled, so it is due.
        let never = Date.distantPast
        return #Predicate<VocabEntry> { ($0.review?.due ?? never) <= now }
    }

    /// The schedule from `now` on, for the widget and the reminder.
    ///
    /// Read from `ReviewState` directly: it is the one side that carries the
    /// date, and every state belongs to exactly one entry (created with it,
    /// deleted with it).
    public func outlook(now: Date = .now) -> ReviewOutlook {
        var descriptor = FetchDescriptor<ReviewState>(
            predicate: #Predicate { $0.due > now },
            sortBy: [SortDescriptor(\.due)]
        )
        descriptor.fetchLimit = ReviewOutlook.upcomingCap
        descriptor.propertiesToFetch = [\.due]
        let upcoming = ((try? context.fetch(descriptor)) ?? []).map(\.due)
        return ReviewOutlook(asOf: now, dueCount: dueCount(now: now), upcoming: upcoming)
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
        noteActivity()
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

    // MARK: - Publishing

    /// Receives the schedule every time it is published — the app hangs the
    /// review reminder and the badge off this. JustCore cannot see either.
    public static var onOutlookChange: (@MainActor (ReviewOutlook) -> Void)?

    /// Refreshes everything that shows the schedule outside the app: the
    /// widget's snapshot and timeline, and (through `onOutlookChange`) the
    /// reminder and badge.
    ///
    /// Grading and saving call this themselves, debounced; screens that have
    /// just computed `stats()` can pass it in to save a second pass.
    public func publishActivity(stats: StudyStats? = nil, now: Date = .now) {
        let outlook = self.outlook(now: now)
        if !isInMemory {
            publishWidgetSnapshot(stats ?? self.stats(), outlook: outlook, now: now)
        }
        Self.onOutlookChange?(outlook)
    }

    /// Writes the numbers the widget shows and asks WidgetKit to redraw.
    ///
    /// Without the reload the widget kept whatever it last drew until its own
    /// timeline ran out — an hour of 「복습 12개」 after the twelve were done.
    private func publishWidgetSnapshot(_ stats: StudyStats, outlook: ReviewOutlook, now: Date) {
        // The card most worth looking at: one that is due, else the next to
        // come due, else anything at all.
        let featured = dueEntries(limit: 1, now: now).first
            ?? nextUpcomingEntry(now: now)
            ?? (try? context.fetch(FetchDescriptor<VocabEntry>()))?.first
        let occurrence = featured?.occurrences.max { $0.capturedAt < $1.capturedAt }

        WidgetStore.write(
            WidgetSnapshot(
                dueCount: outlook.dueCount,
                streak: stats.streak,
                totalWords: stats.totalWords,
                word: featured.map { entry in
                    WidgetSnapshot.Word(
                        lemma: entry.lemma,
                        reading: entry.reading,
                        meaningKo: entry.meaningKo,
                        songLabel: occurrence?.song.map { "\($0.artist) — \($0.title)" }
                    )
                },
                updatedAt: now,
                upcomingDue: outlook.upcoming,
                lastStudyDay: lastStudyDay()
            )
        )
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private func nextUpcomingEntry(now: Date) -> VocabEntry? {
        var descriptor = FetchDescriptor<VocabEntry>(
            predicate: #Predicate { ($0.review?.due ?? now) > now },
            sortBy: [SortDescriptor(\VocabEntry.review?.due)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func lastStudyDay() -> Date? {
        var descriptor = FetchDescriptor<StudyDay>(
            sortBy: [SortDescriptor(\.day, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first?.day
    }

    /// Previews and unit tests run on a throwaway in-memory store; they must
    /// not overwrite the real widget's snapshot or schedule a refresh that
    /// outlives them.
    private var isInMemory: Bool {
        context.container.configurations.contains { $0.isStoredInMemoryOnly }
    }

    /// Schedules `publishActivity` shortly after the last change.
    ///
    /// 「모두 저장」 saves dozens of words in one go; publishing after each
    /// would recount the whole library dozens of times for one visible result.
    private func noteActivity() {
        guard !isInMemory else { return }
        ActivityDebounce.pending?.cancel()
        let context = self.context
        ActivityDebounce.pending = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            JustStore(context: context).publishActivity()
        }
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
            dueCount: dueCount(),
            levelCounts: levels,
            week: week
        )
    }
}
