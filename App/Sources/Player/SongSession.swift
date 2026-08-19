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

    let track: Track
    private(set) var lyricsState: LyricsState = .loading
    private(set) var song: StudySong?
    private(set) var bulkProgress: (done: Int, total: Int)?

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

    func start() async {
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

        if autoAnalysis { analyzeAll() }
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

    /// Analyses every line that has none yet, once, and writes the result to
    /// the song record.
    ///
    /// Started automatically when a song opens rather than waiting for a tap
    /// per line: the model is the slow part, the user is going to read the
    /// whole song anyway, and the results are permanent — so doing it once up
    /// front is strictly cheaper than doing it forty times on demand.
    func analyzeAll() {
        guard let lyrics, bulkTask == nil else { return }
        let pending = sensei.pendingLines(in: lyrics)
        guard !pending.isEmpty else { return }

        bulkProgress = (0, pending.count)
        bulkTask = Task { [weak self] in
            guard let self else { return }
            await sensei.analyzeAll(
                lyrics: lyrics,
                songTitle: track.title,
                artist: track.artist
            ) { done, total in
                self.bulkProgress = (done, total)
                // Flushed as it goes, so a cancelled or interrupted run keeps
                // whatever it already produced.
                self.flush()
            }
            flush()
            bulkProgress = nil
            bulkTask = nil
        }
    }

    func cancelBulk() {
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

    /// Index the lyric view should keep centred, or nil when the user has
    /// taken over scrolling.
    func activeLine(at time: TimeInterval) -> Int? {
        guard followsPlayback, let lyrics, lyrics.isSynced else { return nil }
        return lyrics.activeLineIndex(at: time)
    }

    func seekTarget(for lineIndex: Int) -> TimeInterval? {
        lyrics?.lines.first { $0.id == lineIndex }?.time
    }
}
