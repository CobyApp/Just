/// Decides when the model's session has to be thrown away and rebuilt.
///
/// Two pressures pull against each other. Rebuilding costs the instruction
/// prompt — fifteen lines of it — so a session wants to be reused. But the
/// session carries its own transcript, and everything already in it is context
/// the model answers the next line from, so a session that lives too long
/// starts answering about lines that are not the target, and eventually
/// overflows the context window outright.
///
/// Split out from the caller because the balance is a rule worth testing, and
/// the thing it governs — a live model session — cannot be inspected.
public struct SessionRecycler: Sendable {
    private let limit: Int
    private var used = 0
    private var needsNew = false

    /// `limit` lines are answered by one session. The caller is assumed to have
    /// built the first one already, so the first `limit` claims reuse it.
    ///
    /// Six, measured rather than chosen — and re-measured after the answer got
    /// smaller. Three was right when a turn carried a translation, six words
    /// with readings and JLPT levels, and grammar notes: the fourth line's
    /// request reached 4094 tokens against a 4096-token window. Grammar is no
    /// longer asked for and words are capped at three, so a turn is far smaller
    /// and more of them fit.
    ///
    /// Getting it wrong costs nothing now: an overflow rebuilds the session and
    /// asks again, which is the guarantee the count never was.
    public init(limit: Int = 6) {
        self.limit = max(1, limit)
    }

    /// Books one line against the session, answering whether the caller must
    /// build a new one before asking.
    public mutating func claim() -> Bool {
        guard needsNew || used >= limit else {
            used += 1
            return false
        }
        needsNew = false
        used = 1
        return true
    }

    /// Drops the current session and whatever is left of its quota.
    ///
    /// Called when the song changes. Without it the new song's opening lines
    /// are answered by a session still holding the old song's questions and
    /// answers — and answering about a neighbouring line is this model's
    /// commonest mistake, so handing it a whole other song to borrow from is
    /// the same mistake with a wider reach.
    ///
    /// Marks rather than rebuilds: leaving a song is not a reason to pay for a
    /// session the reader may never ask anything of.
    public mutating func startFresh() {
        needsNew = true
        used = 0
    }
}
