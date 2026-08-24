import Foundation

/// Corrects a lyric sheet that runs early or late against the recording.
///
/// Sheet selection can be sound and the timing still be a second or two out:
/// whoever timed it decided where a line begins — at the first beat, at the
/// first syllable, at the breath before it — and nothing in the data says which.
/// There is no second source to check against, so no heuristic can find this.
/// The listener can, in one gesture, and it only has to be done once per song.
///
/// One sign convention, used everywhere: **positive delays the lyrics.** The
/// number is how much later than the sheet says the words are actually sung.
public enum LyricSync {
    /// How far a correction may go.
    ///
    /// Past this it is not timing any more, it is the wrong sheet — a different
    /// edit, a live take, a cover. Allowing twenty seconds would let someone
    /// dial their way to something that looks aligned in one verse and drifts
    /// apart in the next, and hide the real problem while they did it.
    public static let limit: TimeInterval = 5

    /// Steps of this size, so the printed value stays a number a person can read.
    public static func stepped(_ offset: TimeInterval, by delta: TimeInterval) -> TimeInterval {
        // Rounded to a tenth: repeated addition of 0.1 in binary floating point
        // drifts, and this number is printed on screen.
        clamped(((offset + delta) * 10).rounded() / 10)
    }

    public static func clamped(_ offset: TimeInterval) -> TimeInterval {
        min(max(offset, -limit), limit)
    }

    /// The point in the sheet to read when the song is at `songTime`.
    ///
    /// Subtracts, because a positive offset means the sheet is ahead of the
    /// singing: at ten seconds into the song with +2, the line to light up is
    /// the one the sheet stamped at eight.
    public static func lyricTime(
        forSongTime songTime: TimeInterval,
        offset: TimeInterval
    ) -> TimeInterval {
        songTime - offset
    }

    /// Where to move playback so that `line` is what plays next.
    ///
    /// The mirror of `lyricTime`, and it has to be: a corrected highlight with
    /// an uncorrected tap is more confusing than no correction at all, because
    /// the two halves of the screen then disagree.
    public static func seekTarget(
        forLine lineTime: TimeInterval,
        offset: TimeInterval
    ) -> TimeInterval {
        max(0, lineTime + offset)
    }

    /// The correction that makes `lineTime` the line playing at `songTime`.
    ///
    /// Taken from the line the listener says they are hearing rather than the
    /// one the app is highlighting — the highlighted one is by definition the
    /// wrong one when the sync is off, so calibrating against it would compute
    /// the offset already in force and change nothing.
    public static func calibrated(
        songTime: TimeInterval,
        lineTime: TimeInterval
    ) -> TimeInterval {
        clamped(songTime - lineTime)
    }
}
