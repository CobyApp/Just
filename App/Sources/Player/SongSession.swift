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
    var followsPlayback = true

    private let store: JustStore
    private let sensei: Sensei
    private let client = LRCLIBClient()
    private var bulkTask: Task<Void, Never>?

    init(track: Track, context: ModelContext, sensei: Sensei) {
        self.track = track
        self.store = JustStore(context: context)
        self.sensei = sensei
    }

    var lyrics: Lyrics? {
        if case .ready(let lyrics) = lyricsState { return lyrics }
        return nil
    }

    var isBulkAnalyzing: Bool { bulkProgress != nil }

    /// The Korean line, from the persisted cache or from this session's
    /// analysis.
    ///
    /// Kept separate from the analysis cache: seeding that cache with
    /// translation-only entries made `analyze` short-circuit, so a reopened
    /// song showed its translations but could never produce word cards again.
    func translation(for lineIndex: Int) -> String? {
        if let study = sensei.cached(lineIndex), !study.translationKo.isEmpty {
            return study.translationKo
        }
        return song?.translations[lineIndex]
    }

    // MARK: - Loading

    func start() async {
        // The song enters the library as soon as it is opened, so "recently
        // played" works without an explicit save step.
        let record = store.upsertSong(track)
        song = record

        if let cached = record.lyrics, !cached.isEmpty {
            lyricsState = .ready(cached)
            return
        }

        await fetchLyrics()
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
        let study = await sensei.analyze(
            lineIndex: lineIndex,
            in: lyrics,
            songTitle: track.title,
            artist: track.artist
        )
        persist(study)
    }

    func analyzeAll() {
        guard let lyrics, bulkTask == nil else { return }
        bulkProgress = (0, lyrics.lines.count)
        bulkTask = Task { [weak self] in
            guard let self else { return }
            await sensei.analyzeAll(
                lyrics: lyrics,
                songTitle: track.title,
                artist: track.artist
            ) { done, total in
                self.bulkProgress = (done, total)
            }
            for index in sensei.cache.keys {
                persist(sensei.cached(index))
            }
            bulkProgress = nil
            bulkTask = nil
        }
    }

    func cancelBulk() {
        bulkTask?.cancel()
        bulkTask = nil
        bulkProgress = nil
    }

    /// Caches the Korean translation on the song so a reopened song shows its
    /// translations immediately, without re-running the model.
    private func persist(_ study: LineStudy?) {
        guard let study, let song else { return }
        if !study.translationKo.isEmpty {
            song.translations[study.lineIndex] = study.translationKo
        }

        // Recount from scratch for this line rather than adding to a running
        // total: a line can be re-analysed, and blind accumulation would
        // inflate the histogram every time it is.
        var counts = song.levelCounts
        for previous in analyzedLevels[study.lineIndex] ?? [] {
            counts[previous, default: 0] = max(0, (counts[previous] ?? 0) - 1)
        }
        let levels = study.words.map(\.jlpt.rawValue)
        for level in levels {
            counts[level, default: 0] += 1
        }
        analyzedLevels[study.lineIndex] = levels
        song.levelCounts = counts.filter { $0.value > 0 }
    }

    /// Levels already counted per line, so a re-analysis replaces rather than
    /// double-counts.
    private var analyzedLevels: [Int: [String]] = [:]

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
