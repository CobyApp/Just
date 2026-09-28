import Foundation

/// Where playback is, and whether that number means a place in the song.
///
/// The two are not the same thing, and conflating them is how the lyrics came
/// to highlight the wrong line. Without a subscription the app plays a
/// thirty-second preview clip, whose clock starts at zero for the clip — not
/// for the song. Measured rather than assumed: the first second of an Apple
/// preview sits within 0.3–3.5 dB of the clip's own mean level across the songs
/// checked, so the clip opens at full level in the middle of the track. A song
/// starts from silence; these do not.
///
/// Apple publishes no offset for where a preview was cut from, so clip time
/// cannot be converted into song time. It can only be refused.
///
/// One name for two clocks was the whole defect. Naming them separately is the
/// fix: a caller that needs a position in the song has to ask for `songTime`
/// and handle its absence.
public enum PlaybackPosition: Equatable, Sendable {
    /// Playing the song itself. The number is a position in the song.
    case inSong(TimeInterval)
    /// Playing a preview excerpt. The number is a position in the clip, and
    /// where that clip sits in the song is not known.
    case excerpt(TimeInterval)

    /// The position within the song, when the clock is the song's.
    ///
    /// nil is the honest answer for an excerpt. Everything that places itself
    /// against the lyrics — the highlight, the auto-scroll, a line's loop —
    /// depends on this being a song position, and would otherwise be confidently
    /// wrong with nothing to show the reader that it was.
    public var songTime: TimeInterval? {
        switch self {
        case .inSong(let time): time
        case .excerpt: nil
        }
    }

    /// How long the thing being played has been playing.
    ///
    /// Always meaningful, because the transport is drawing the clip's own
    /// progress: 0:08 of 0:30 is true even when the song is somewhere else.
    public var elapsed: TimeInterval {
        switch self {
        case .inSong(let time), .excerpt(let time): time
        }
    }

    /// Whether the lyrics can follow this.
    public var followsLyrics: Bool { songTime != nil }
}

extension Lyrics {
    /// The line playing now, or nil when the position cannot say.
    public func activeLineIndex(at position: PlaybackPosition) -> Int? {
        guard let songTime = position.songTime else { return nil }
        return activeLineIndex(at: songTime)
    }
}
