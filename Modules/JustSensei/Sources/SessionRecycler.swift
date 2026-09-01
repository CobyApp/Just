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
    /// Three, measured rather than chosen: a fourth line's request reached 4094
    /// tokens against a 4096-token window and every line after it failed too.
    ///
    /// Six was tried on the device once the answers got smaller — grammar
    /// dropped, words capped at three — on the theory that more turns would now
    /// fit. They do: no overflow at all. But the median response went from 3.5
    /// to 9.2 seconds, because a longer transcript is more context to read
    /// before every answer. Reusing a session saves the instruction prompt and
    /// pays for the conversation; past a few lines the second cost is larger.
    ///
    /// Getting it wrong costs nothing now: an overflow rebuilds the session and
    /// asks again, which is the guarantee the count never was.
    public init(limit: Int = 3) {
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
