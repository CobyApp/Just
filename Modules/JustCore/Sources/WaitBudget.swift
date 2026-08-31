import Foundation

/// How long a song may keep someone on the wait screen.
///
/// Opening a finished song is the better experience and stays the default. But
/// the wait is bounded by what the device can do, not by what is reasonable to
/// ask of a person: a long song on a busy phone can run into minutes, and a
/// minute of staring at a progress bar is worse than reading lyrics that fill
/// in behind you.
///
/// So the decision is deferred rather than guessed. The run starts, the first
/// lines are timed, and the estimate they produce decides. `AnalysisPace`
/// already computes it for the label on screen; this only says what to do with
/// the number.
public enum WaitBudget {
    /// Longest wait worth sitting through, once it is known.
    ///
    /// Half a minute: long enough that most songs finish inside it on a device
    /// that is keeping up, short enough that nobody is left watching a bar.
    public static let tolerable: TimeInterval = 30

    /// Lines to time before trusting the estimate.
    ///
    /// The first line pays for the session and the fifteen-line instruction
    /// prompt, so on its own it reads as far slower than the song really is.
    public static let warmup = 2

    /// Whether to hand over the player now and finish the analysis behind it.
    public static func shouldOpenEarly(estimate: TimeInterval?, done: Int) -> Bool {
        guard done > warmup, let estimate else { return false }
        return estimate > tolerable
    }
}
