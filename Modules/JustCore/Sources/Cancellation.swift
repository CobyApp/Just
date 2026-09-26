import Foundation

public extension Error {
    /// The caller gave up — the player was closed, another song was opened.
    /// Not a failure, and never to be shown or remembered as one.
    ///
    /// URLSession reports a cancelled task as `URLError.cancelled` rather than
    /// `CancellationError`, so both count.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let url = self as? URLError, url.code == .cancelled { return true }
        return false
    }
}
