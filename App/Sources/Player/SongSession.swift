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

    // MARK: - Loading

    func start() async {
        // The song enters the library as soon as it is opened, so "recently
        // played" works without an explicit save step.
        let record = store.upsertSong(track)
        song = record

        if let cached = record.lyrics, !cached.isEmpty {
            lyricsState = .ready(cached)
            sensei.restore(translations: record.translations, lyrics: cached)
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
        guard let study, !study.translationKo.isEmpty, let song else { return }
        song.translations[study.lineIndex] = study.translationKo
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
