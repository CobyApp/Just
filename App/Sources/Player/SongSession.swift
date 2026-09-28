import RingRingCore
import RingRingDesign
import RingRingLyrics
import RingRingSensei
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
    /// Only the lyrics stand between choosing a song and hearing it now: the
    /// quick reading is fast enough to fill in behind the words rather than
    /// before them, so there is no analysis wait to show.
    enum Phase: Equatable {
        case loadingLyrics
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

    /// Seconds the words are sung later than the sheet says. See `LyricSync`.
    var lyricsOffset: TimeInterval {
        get { song?.lyricsOffset ?? 0 }
        set { song?.lyricsOffset = LyricSync.clamped(newValue) }
    }

    func translation(for lineIndex: Int) -> String? {
        let translation = sensei.cached(lineIndex)?.translationKo
        return (translation?.isEmpty == false) ? translation : nil
    }

    // MARK: - Loading

    /// Everything that has to happen before the player may open.
    ///
    /// Only the lyrics are waited for. The quick reading is fast, so it runs
    /// behind the words — the song opens the moment the lyrics are in, and the
    /// translations fill in line by line, reported by the same progress bar a
    /// manual pass uses.
    func prepare() async {
        // Claiming the shared cache is the session's own job, not the caller's.
        // Doing it here is what orders it correctly against the outgoing
        // session's final flush: that one runs first, under its own song's
        // scope, so its work is saved before this song takes the cache over.
        // Re-opening the same song is a no-op and keeps everything cached.
        sensei.reset(for: track.id)
        // The language pack may have been downloaded, or the setting changed,
        // since the last song — read now so lines are not left blank on a stale
        // "no translator" answer.
        await sensei.refreshTranslator()

        // The song enters the library as soon as it is opened, so "recently
        // played" works without an explicit save step.
        let record = store.upsertSong(track)
        song = record

        // Everything generated for this song before is loaded back before any
        // work is scheduled, so a reopened song costs nothing.
        sensei.preload(record.analyses)
        // The stored difficulty counts may predate the current way of
        // counting (each word once, the unrated kept apart); recounted from
        // the analyses just loaded, so a song analysed long ago does not
        // show a stale level until something new is saved.
        if record.analysedCount > 0 { flush() }

        if let cached = record.lyrics, !cached.isEmpty {
            lyricsState = .ready(cached)
        } else {
            await fetchLyrics()
        }

        guard !Task.isCancelled else { return }
        phase = .ready
        // Behind the lyrics, when the reader has not turned it off.
        if autoAnalysis { analyzeAll() }
    }

    /// Re-runs the search with a corrected artist and title.
    func retryLyrics(artistOverride: String?, titleOverride: String?) async {
        phase = .loadingLyrics
        await fetchLyrics(artistOverride: artistOverride, titleOverride: titleOverride)
        guard !Task.isCancelled else { return }
        phase = .ready
        if autoAnalysis { analyzeAll() }
    }

    /// Lyrics the reader pasted in, because no database had them.
    ///
    /// New releases reach LRCLIB weeks after they reach the group's channel,
    /// and some never do. A reader who has the words — from the booklet, the
    /// label's site, wherever — should not be stopped from studying them.
    /// LRC timestamps are honoured when present; plain text is unsynced.
    func useLyrics(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        phase = .loadingLyrics
        let lyrics = LRCParser.parse(trimmed, source: "직접 입력")
        lyricsState = .ready(lyrics)
        song?.lyrics = lyrics
        guard !Task.isCancelled else { return }
        phase = .ready
        if autoAnalysis { analyzeAll() }
    }

    /// Sends pasted lyrics back to LRCLIB so the song is found automatically
    /// next time — the only thing that grows coverage for songs no database has
    /// yet. Explicit: the reader taps to share, because this puts their text in
    /// a public database. Timestamped lines go up as synced too.
    func shareLyrics(_ text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let hasTimestamps = trimmed.range(of: #"\[\d{1,2}:\d{2}"#, options: .regularExpression) != nil
        // Plain text drops every [..] tag — line timestamps and metadata alike.
        let plain = trimmed
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        try await client.publish(
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            plain: plain,
            synced: hasTimestamps ? trimmed : nil
        )
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
        } catch where error.isCancellation {
            // The player closed mid-lookup; "cancelled" is not a missing lyric.
            return
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
    /// Runs behind the lyrics: `prepare()` starts it as soon as the song opens,
    /// and the player's menu can start it again for whatever is still blank —
    /// lines the translator could not reach the first time, now that a language
    /// pack may have arrived.
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
    /// `flush`, for the one caller outside this class.
    ///
    /// A line the reader improved by hand is not part of any automatic pass, so
    /// nothing else is going to save it — and the periodic flush that covers the
    /// bulk runs only fires while one is running.
    func flushNow() { flush() }

    private func flush() {
        guard let song, let studies = sensei.cache(for: song.videoID) else { return }
        song.analyses = studies

        // Each word once. A chorus sung four times used to count its words
        // four times, so 「어려운 단어 18개」 was really eighteen sightings.
        var counts: [String: Int] = [:]
        var seen: Set<String> = []
        for study in studies.values {
            for word in study.words where seen.insert(word.id).inserted {
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
    func loopRewindTarget(at position: PlaybackPosition) -> TimeInterval? {
        guard let time = position.songTime else { return nil }
        return loopRewindTarget(at: time)
    }

    private func loopRewindTarget(at time: TimeInterval) -> TimeInterval? {
        guard let loopingLine,
              let lyrics,
              let sheetRange = lyrics.range(of: loopingLine)
        else { return nil }
        // Shifted with everything else: a loop set from a corrected highlight
        // has to repeat the words the reader saw, not the sheet's timings.
        let range = (
            start: LyricSync.seekTarget(forLine: sheetRange.start, offset: lyricsOffset),
            end: LyricSync.seekTarget(forLine: sheetRange.end, offset: lyricsOffset)
        )
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
    ///
    /// Takes a position rather than a number so a preview clip's clock cannot
    /// be mistaken for the song's — it returns nil there, because a highlight
    /// drawn from the wrong clock is wrong with nothing to show that it is.
    func activeLine(at position: PlaybackPosition) -> Int? {
        guard let lyrics, lyrics.isSynced, let songTime = position.songTime else { return nil }
        return lyrics.activeLineIndex(
            at: LyricSync.lyricTime(forSongTime: songTime, offset: lyricsOffset)
        )
    }

    func seekTarget(for lineIndex: Int) -> TimeInterval? {
        guard let time = lyrics?.lines.first(where: { $0.id == lineIndex })?.time else {
            return nil
        }
        return LyricSync.seekTarget(forLine: time, offset: lyricsOffset)
    }
}
