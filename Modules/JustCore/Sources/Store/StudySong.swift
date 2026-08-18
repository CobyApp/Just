import Foundation
import SwiftData

/// A song the user has added to their library. Lyrics are cached on the record
/// so a saved song opens instantly and works offline.
@Model
public final class StudySong {
    #Unique<StudySong>([\.videoID])

    public var videoID: String = ""
    public var title: String = ""
    public var artist: String = ""
    public var album: String?
    public var artworkURLString: String?
    public var duration: Double = 0
    public var addedAt: Date = Date.distantPast
    public var lastOpenedAt: Date?

    /// JSON-encoded `Lyrics`. Kept opaque so the lyric shape can evolve
    /// without a schema migration.
    public var lyricsData: Data?

    /// Line index -> Korean translation, for lines the user has analysed.
    public var translations: [Int: String] = [:]

    /// JLPT level -> how many words the analyser found at that level.
    ///
    /// Accumulated as lines are analysed so a song can describe its own
    /// difficulty without re-running the model.
    public var levelCounts: [String: Int] = [:]

    @Relationship(deleteRule: .cascade, inverse: \VocabOccurrence.song)
    public var occurrences: [VocabOccurrence] = []

    public init(track: Track) {
        self.videoID = track.id
        self.title = track.title
        self.artist = track.artist
        self.album = track.album
        self.artworkURLString = track.artworkURL?.absoluteString
        self.duration = track.duration
        self.addedAt = .now
    }

    public var artworkURL: URL? {
        artworkURLString.flatMap(URL.init(string:))
    }

    public var track: Track {
        Track(
            id: videoID,
            title: title,
            artist: artist,
            album: album,
            artworkURL: artworkURL,
            duration: duration
        )
    }

    public var lyrics: Lyrics? {
        get {
            guard let lyricsData else { return nil }
            return try? JSONDecoder().decode(Lyrics.self, from: lyricsData)
        }
        set {
            lyricsData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    public var difficulty: SongDifficulty {
        SongDifficulty(raw: levelCounts)
    }

    /// Fraction of lyric lines that have been analysed at least once.
    public var studyProgress: Double {
        guard let total = lyrics?.lines.filter({ !$0.text.isEmpty }).count, total > 0 else {
            return 0
        }
        return min(1, Double(translations.count) / Double(total))
    }
}
