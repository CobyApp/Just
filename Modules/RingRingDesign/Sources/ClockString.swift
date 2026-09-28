import Foundation

public extension TimeInterval {
    /// A duration as a transport reads it: 3:47.
    ///
    /// Lived inside the search screen until search was removed, which took the
    /// player's clock down with it — a formatting helper three screens use had
    /// no business being private to one of them.
    var clockString: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
