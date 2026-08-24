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

    /// JSON-encoded `[lineIndex: LineStudy]` — the complete analysis, not just
    /// the translation.
    ///
    /// The whole point of persisting this is that the on-device model runs over
    /// a song exactly once. Keeping only the translation meant reopening a song
    /// showed the Korean but had to regenerate every word card from scratch,
    /// which is the most expensive part of the pipeline.
    public var analysisData: Data?

    /// Counts kept as stored properties, not derived.
    ///
    /// `studyProgress` is read for every row of every list that shows a song,
    /// and deriving it meant JSON-decoding both the lyrics and the whole
    /// analysis on each access — once per row, per redraw. These are written
    /// when the blobs are, and read for free.
    public var lineCount: Int = 0
    public var analysedCount: Int = 0

    /// JLPT level -> how many words the analyser found at that level.
    ///
    /// Denormalised from `analyses` so the browse screen can rank songs by
    /// difficulty without decoding every analysis it lists.
    public var levelCounts: [String: Int] = [:]

    /// Seconds the words are actually sung later than the sheet says.
    ///
    /// Per song, because it is a property of the sheet rather than the device.
    /// Defaulted like every other field here, which is what lets the store open
    /// an older database without a migration plan.
    public var lyricsOffset: Double = 0

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
            lineCount = newValue?.lines.filter { !$0.text.isEmpty }.count ?? 0
        }
    }

    public var difficulty: SongDifficulty {
        SongDifficulty(raw: levelCounts)
    }

    public var analyses: [Int: LineStudy] {
        get {
            guard let analysisData else { return [:] }
            return (try? JSONDecoder().decode([Int: LineStudy].self, from: analysisData)) ?? [:]
        }
        set {
            analysisData = newValue.isEmpty
                ? nil
                : try? JSONEncoder().encode(newValue)
            analysedCount = newValue.count
        }
    }

    /// Fraction of lyric lines that have been analysed at least once.
    public var studyProgress: Double {
        guard lineCount > 0 else { return 0 }
        return min(1, Double(analysedCount) / Double(lineCount))
    }
}
