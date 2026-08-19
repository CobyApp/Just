import Foundation

/// A song as it comes back from the music source, before the user saves it.
public struct Track: Identifiable, Hashable, Sendable, Codable {
    /// Apple Music catalog id.
    public let id: String
    public let title: String
    public let artist: String
    public let album: String?
    public let artworkURL: URL?
    public let duration: TimeInterval

    public init(
        id: String,
        title: String,
        artist: String,
        album: String? = nil,
        artworkURL: URL? = nil,
        duration: TimeInterval = 0
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.duration = duration
    }
}

/// One line of lyrics. `time` is nil for unsynced lyrics.
public struct LyricLine: Identifiable, Hashable, Sendable, Codable {
    public let id: Int
    public let time: TimeInterval?
    public let text: String

    public init(id: Int, time: TimeInterval?, text: String) {
        self.id = id
        self.time = time
        self.text = text
    }
}

public struct Lyrics: Hashable, Sendable, Codable {
    public let lines: [LyricLine]
    public let isSynced: Bool
    public let source: String

    public init(lines: [LyricLine], isSynced: Bool, source: String) {
        self.lines = lines
        self.isSynced = isSynced
        self.source = source
    }

    public var isEmpty: Bool { lines.isEmpty }

    /// Start and end of one line's audio, for looping it.
    ///
    /// A line has no recorded end — LRC only marks starts — so the end is the
    /// next line's start. The last line falls back to a fixed span, since the
    /// alternative is looping to the end of the track.
    public func range(of lineIndex: Int, fallbackLength: TimeInterval = 8) -> (start: TimeInterval, end: TimeInterval)? {
        guard isSynced,
              let line = lines.first(where: { $0.id == lineIndex }),
              let start = line.time
        else { return nil }

        // The next line that actually carries a timestamp — blank "♪" lines in
        // the middle of a song would otherwise cut the loop short.
        let end = lines
            .first { $0.id > lineIndex && ($0.time ?? 0) > start }?
            .time ?? (start + fallbackLength)

        return (start, end)
    }

    /// Index of the line that should be highlighted at `time`.
    /// Returns nil when the lyrics are unsynced or playback sits before the first line.
    public func activeLineIndex(at time: TimeInterval) -> Int? {
        guard isSynced else { return nil }
        var match: Int?
        for line in lines {
            guard let lineTime = line.time else { continue }
            if lineTime <= time + 0.15 { match = line.id } else { break }
        }
        return match
    }
}
