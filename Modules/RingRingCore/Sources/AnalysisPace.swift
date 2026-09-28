import Foundation

/// Estimates how long an analysis run has left, from how long its lines have
/// actually taken.
///
/// A median over a short window rather than a mean: one line that stalls —
/// thermal throttling, a long verse, the model warming up — should not triple
/// the number someone is staring at for the next ten minutes.
public struct AnalysisPace: Sendable {
    private var samples: [TimeInterval] = []
    private let window: Int

    public init(window: Int = 8) {
        self.window = max(1, window)
    }

    /// Records one line's elapsed time.
    ///
    /// Non-positive and non-finite samples are dropped: a clock that did not
    /// move, or moved to infinity, says nothing about pace.
    public mutating func record(_ seconds: TimeInterval) {
        guard seconds.isFinite, seconds > 0 else { return }
        samples.append(seconds)
        if samples.count > window {
            samples.removeFirst(samples.count - window)
        }
    }

    /// Seconds left for `remaining` lines, or nil when nothing has been timed
    /// yet — showing no estimate is better than showing an invented one.
    public func estimate(remaining: Int) -> TimeInterval? {
        guard !samples.isEmpty else { return nil }
        guard remaining > 0 else { return 0 }
        return median * Double(remaining)
    }

    private var median: TimeInterval {
        let sorted = samples.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}
