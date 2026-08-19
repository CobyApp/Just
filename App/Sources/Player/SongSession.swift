import JustCore
import JustDesign
import JustLyrics
import JustSensei
import Observation
import SwiftData
import SwiftUI

/// Everything that belongs to the song currently open: its lyrics, its
/// analysis progress, and the library record they get written back to.
@MainActor
@Observable
final class SongSession {
    enum LyricsState: Equatable {
        case loading
        case ready(Lyrics)
        case missing(String)
    }

    /// How far the song is from being ready to read.
    ///
    /// The player shows a finished song or nothing at all, so this is what
    /// stands between choosing a song and hearing it.
    enum Phase: Equatable {
        case loadingLyrics
        case analyzing(done: Int, total: Int, remaining: TimeInterval?)
        case ready
    }

    let track: Track
    private(set) var lyricsState: LyricsState = .loading
    private(set) var song: StudySong?
    private(set) var bulkProgress: (done: Int, total: Int)?
    private(set) var phase: Phase = .loadingLyrics

    var selectedLine: Int?
    var showsFurigana = true
    var textSize: LyricTextSize = .stored {
        didSet { textSize.store() }
    }
    /// Line being repeated, if any.
    var loopingLine: Int?
    /// Hides the artwork and transport so the lyrics get the whole screen.
    var isLyricsFullscreen = false
    var followsPlayback = true

    private let store: JustStore
    private let sensei: Sensei
    private let client = LRCLIBClient()
    private var bulkTask: Task<Void, Never>?

    private let autoAnalysis: Bool

    init(track: Track, context: ModelContext, sensei: Sensei, autoAnalysis: Bool) {
        self.track = track
        self.store = JustStore(context: context)
        self.sensei = sensei
        self.autoAnalysis = autoAnalysis
    }

    var lyrics: Lyrics? {
        if case .ready(let lyrics) = lyricsState { return lyrics }
        return nil
    }

    var isBulkAnalyzing: Bool { bulkProgress != nil }

    func translation(for lineIndex: Int) -> String? {
        let translation = sensei.cached(lineIndex)?.translationKo
        return (translation?.isEmpty == false) ? translation : nil
    }

    // MARK: - Loading

    /// Everything that has to happen before the player may open.
    ///
    /// Analysis is awaited rather than left running behind the lyrics: the
    /// player shows a finished song, and a song filling in line by line under
    /// the reader is the thing this replaces.
    func prepare() async {
        // Claiming the shared cache is the session's own job, not the caller's.
        // Doing it here is what orders it correctly against the outgoing
        // session's final flush: that one runs first, under its own song's
        // scope, so its work is saved before this song takes the cache over.
        // Re-opening the same song is a no-op and keeps everything cached.
        sensei.reset(for: track.id)

        // The song enters the library as soon as it is opened, so "recently
        // played" works without an explicit save step.
        let record = store.upsertSong(track)
        song = record

        // Everything generated for this song before is loaded back before any
        // work is scheduled, so a reopened song costs nothing.
        sensei.preload(record.analyses)

        if let cached = record.lyrics, !cached.isEmpty {
            lyricsState = .ready(cached)
        } else {
            await fetchLyrics()
        }

        // "안 함" and low-power mode keep their meaning: a setting made to save
        // energy must not turn into a ten-minute wait. Those songs open at once
        // and analyse the lines the reader taps, as before.
        if autoAnalysis {
            await analyzeRemaining()
        }

        guard !Task.isCancelled else { return }
        phase = .ready
    }

    /// One pass over the lines that still need the model.
    ///
    /// Exactly one. A line the model keeps failing on stays unsettled, so
    /// looping until nothing is pending would never let the song open.
    private func analyzeRemaining() async {
        guard let lyrics else { return }
        let pending = sensei.pendingLines(in: lyrics)
        guard !pending.isEmpty else { return }

        var pace = AnalysisPace()
        var lastTick = Date.now
        phase = .analyzing(done: 0, total: pending.count, remaining: nil)

        await sensei.analyzeAll(
            lyrics: lyrics,
            songTitle: track.title,
            artist: track.artist
        ) { done, total in
            let now = Date.now
            pace.record(now.timeIntervalSince(lastTick))
            lastTick = now
            self.phase = .analyzing(
                done: done,
                total: total,
                remaining: pace.estimate(remaining: total - done)
            )
            // Flushed as it goes, so a cancelled run keeps what it produced.
            self.flush()
        }
        flush()
    }

    /// Re-runs the search with a corrected artist and title, then prepares the
    /// song properly.
    ///
    /// Going back through preparation rather than analysing behind the lyrics
    /// keeps one rule: the player only ever shows a finished song.
    func retryLyrics(artistOverride: String?, titleOverride: String?) async {
        phase = .loadingLyrics
        await fetchLyrics(artistOverride: artistOverride, titleOverride: titleOverride)
        if autoAnalysis {
            await analyzeRemaining()
        }
        guard !Task.isCancelled else { return }
        phase = .ready
    }

    func fetchLyrics(artistOverride: String? = nil, titleOverride: String? = nil) async {
        lyricsState = .loading
        do {
            let lyrics = try await client.lyrics(
                artist: artistOverride ?? track.artist,
                title: titleOverride ?? track.title,
                album: track.album,
                duration: track.duration
            )
            lyricsState = .ready(lyrics)
            song?.lyrics = lyrics
        } catch {
            lyricsState = .missing(error.localizedDescription)
        }
    }

    // MARK: - Analysis

    func analyze(lineIndex: Int) async {
        guard let lyrics else { return }
        await sensei.analyze(
            lineIndex: lineIndex,
            in: lyrics,
            songTitle: track.title,
            artist: track.artist
        )
        flush()
    }

    /// Numbers the whole-song runs.
    ///
    /// A cancelled run does not stop where it was told to: cancellation is only
    /// checked between lines, so the line already inside the model finishes
    /// first. Numbering keeps that tail from reporting progress for, or tearing
    /// down, the run that has since replaced it.
    private var bulkRun = 0

    /// Analyses every line that has none yet, once, and writes the result to
    /// the song record.
    ///
    /// Only reachable from the player's menu now. Opening a song runs the same
    /// pass through `prepare()` and waits for it, so what is left here is the
    /// leftovers: lines the model failed on, which stay unsettled and are worth
    /// another attempt without reopening the song.
    func analyzeAll() {
        guard let lyrics, bulkTask == nil else { return }
        let pending = sensei.pendingLines(in: lyrics)
        guard !pending.isEmpty else { return }

        bulkRun &+= 1
        let run = bulkRun
        bulkProgress = (0, pending.count)
        bulkTask = Task { [weak self] in
            guard let self else { return }
            await sensei.analyzeAll(
                lyrics: lyrics,
                songTitle: track.title,
                artist: track.artist
            ) { done, total in
                guard run == self.bulkRun else { return }
                self.bulkProgress = (done, total)
                // Flushed as it goes, so a cancelled or interrupted run keeps
                // whatever it already produced.
                self.flush()
            }
            flush()
            guard run == bulkRun else { return }
            bulkProgress = nil
            bulkTask = nil
        }
    }

    func cancelBulk() {
        bulkRun &+= 1
        bulkTask?.cancel()
        bulkTask = nil
        bulkProgress = nil
        flush()
    }

    /// Writes the session's analyses and the difficulty histogram onto the
    /// song record.
    ///
    /// Recomputed from the cache rather than accumulated: the cache is the
    /// single source of truth, and adding to a running total would inflate the
    /// histogram every time a line was re-analysed.
    ///
    /// Does nothing once the cache has moved on to another song. A session
    /// outlives its turn — the album sheet can open a different song while this
    /// screen is still mounted, and `onDisappear` flushes on the way out — so
    /// without the scope check the departing session would write the new song's
    /// cache, usually empty, over everything this song had analysed.
    private func flush() {
        guard let song, let studies = sensei.cache(for: song.videoID) else { return }
        song.analyses = studies

        var counts: [String: Int] = [:]
        for study in studies.values {
            for word in study.words {
                counts[word.jlpt.rawValue, default: 0] += 1
            }
        }
        song.levelCounts = counts
    }

    // MARK: - Vocabulary

    func save(_ word: StudyWord, from study: LineStudy) {
        guard let song else { return }
        store.save(
            word,
            from: song,
            lineIndex: study.lineIndex,
            lineText: study.original,
            lineTranslation: study.translationKo.isEmpty ? nil : study.translationKo
        )
    }

    /// Saves every word from every analysed line, and reports how many were new.
    ///
    /// The per-line "모두 저장" is the right default — the user is reading and
    /// choosing — but after a whole song has been analysed, picking through
    /// forty sheets to collect it is not a choice anyone makes.
    @discardableResult
    func saveAllWords() -> Int {
        guard let song else { return 0 }
        var added = 0
        for study in sensei.entries.values.sorted(by: { $0.lineIndex < $1.lineIndex }) {
            for word in study.words where !isSaved(word) {
                store.save(
                    word,
                    from: song,
                    lineIndex: study.lineIndex,
                    lineText: study.original,
                    lineTranslation: study.translationKo.isEmpty ? nil : study.translationKo
                )
                added += 1
            }
        }
        return added
    }

    /// How many words the analysed lines hold that are not saved yet.
    var unsavedWordCount: Int {
        sensei.entries.values.reduce(0) { total, study in
            total + study.words.filter { !isSaved($0) }.count
        }
    }

    func isSaved(_ word: StudyWord) -> Bool {
        store.vocab(lemma: word.dictionaryForm, reading: word.reading) != nil
    }

    func remove(_ word: StudyWord) {
        guard let entry = store.vocab(lemma: word.dictionaryForm, reading: word.reading) else {
            return
        }
        store.remove(entry)
    }

    // MARK: - Playback follow

    func toggleLoop(_ lineIndex: Int) {
        loopingLine = loopingLine == lineIndex ? nil : lineIndex
    }

    var canLoop: Bool { lyrics?.isSynced == true }

    /// Seek target when playback has run past the end of the looping line.
    ///
    /// Returns nil while still inside the line, so the caller can call this on
    /// every clock tick without tracking state of its own.
    func loopRewindTarget(at time: TimeInterval) -> TimeInterval? {
        guard let loopingLine,
              let lyrics,
              let range = lyrics.range(of: loopingLine)
        else { return nil }
        // Also rewinds when playback has jumped *before* the line, so a loop
        // survives the user scrubbing away from it.
        guard time >= range.end || time < range.start - 0.5 else { return nil }
        return range.start
    }

    /// The line the song is on, whoever is driving the scroll.
    ///
    /// Deliberately not gated on `followsPlayback`: taking over the scroll means
    /// the view stops chasing the song, not that the song stops. Reading the two
    /// off one flag froze the highlight on whatever line was current when the
    /// user first touched the list.
    func activeLine(at time: TimeInterval) -> Int? {
        guard let lyrics, lyrics.isSynced else { return nil }
        return lyrics.activeLineIndex(at: time)
    }

    func seekTarget(for lineIndex: Int) -> TimeInterval? {
        lyrics?.lines.first { $0.id == lineIndex }?.time
    }
}
