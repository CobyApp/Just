import Foundation

/// FSRS 4.5 scheduler.
///
/// Chosen over SM-2 because lyric vocabulary is wildly uneven in difficulty —
/// a song mixes N5 particles with slang that has no JLPT level at all — and
/// FSRS models per-item difficulty instead of assuming a uniform ease factor.
public struct FSRS: Sendable {
    /// Published FSRS-4.5 default weights.
    public static let defaultWeights: [Double] = [
        0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.0310,
        1.6474, 0.1367, 1.0461, 2.1072, 0.0793, 0.3246, 1.5870, 0.2272, 2.8755,
    ]

    private static let decay = -0.5
    private static let factor = 19.0 / 81.0

    public var weights: [Double]
    /// Target probability of recall at review time.
    public var requestRetention: Double
    public var maximumInterval: Double

    public init(
        weights: [Double] = FSRS.defaultWeights,
        requestRetention: Double = 0.9,
        maximumInterval: Double = 365 * 3
    ) {
        self.weights = weights
        self.requestRetention = requestRetention
        self.maximumInterval = maximumInterval
    }

    public struct Outcome: Sendable {
        public let stability: Double
        public let difficulty: Double
        public let intervalDays: Double
        public let due: Date
        public let phase: ReviewPhase
    }

    /// Probability the item is still recalled `elapsedDays` after a review that
    /// left it at `stability`.
    public func retrievability(elapsedDays: Double, stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        return pow(1 + Self.factor * elapsedDays / stability, Self.decay)
    }

    private func interval(stability: Double) -> Double {
        let raw = (stability / Self.factor)
            * (pow(requestRetention, 1 / Self.decay) - 1)
        return min(max(raw.rounded(), 1), maximumInterval)
    }

    private func initialDifficulty(_ grade: ReviewGrade) -> Double {
        clampDifficulty(weights[4] - Double(grade.rawValue - 3) * weights[5])
    }

    private func clampDifficulty(_ value: Double) -> Double {
        min(max(value, 1), 10)
    }

    private func nextDifficulty(_ difficulty: Double, _ grade: ReviewGrade) -> Double {
        let delta = difficulty - weights[6] * Double(grade.rawValue - 3)
        // Mean reversion pulls difficulty back toward the "good"-grade baseline
        // so a single bad day doesn't permanently mark a word as hard.
        let reverted = weights[7] * initialDifficulty(.easy) + (1 - weights[7]) * delta
        return clampDifficulty(reverted)
    }

    private func recallStability(
        difficulty: Double,
        stability: Double,
        retrievability: Double,
        grade: ReviewGrade
    ) -> Double {
        let hardPenalty = grade == .hard ? weights[15] : 1
        let easyBonus = grade == .easy ? weights[16] : 1
        let growth = exp(weights[8])
            * (11 - difficulty)
            * pow(stability, -weights[9])
            * (exp(weights[10] * (1 - retrievability)) - 1)
            * hardPenalty
            * easyBonus
        return stability * (1 + growth)
    }

    private func forgetStability(
        difficulty: Double,
        stability: Double,
        retrievability: Double
    ) -> Double {
        weights[11]
            * pow(difficulty, -weights[12])
            * (pow(stability + 1, weights[13]) - 1)
            * exp(weights[14] * (1 - retrievability))
    }

    /// Schedules `state` after the user grades it. Pure — the caller writes the
    /// outcome back, which keeps this testable without a SwiftData context.
    public func schedule(
        _ state: ReviewState,
        grade: ReviewGrade,
        now: Date = .now
    ) -> Outcome {
        let isFirstReview = state.phase == .new || state.stability <= 0

        let stability: Double
        let difficulty: Double

        if isFirstReview {
            stability = max(weights[grade.rawValue - 1], 0.1)
            difficulty = initialDifficulty(grade)
        } else {
            let elapsed = max(0, (state.lastReview.map { now.timeIntervalSince($0) } ?? 0) / 86_400)
            let r = retrievability(elapsedDays: elapsed, stability: state.stability)
            difficulty = nextDifficulty(state.difficulty, grade)
            stability = grade == .again
                ? min(
                    forgetStability(
                        difficulty: state.difficulty,
                        stability: state.stability,
                        retrievability: r
                    ),
                    state.stability
                )
                : recallStability(
                    difficulty: state.difficulty,
                    stability: state.stability,
                    retrievability: r,
                    grade: grade
                )
        }

        let phase: ReviewPhase = grade == .again ? .relearning : .review

        // "Again" comes back in the same session rather than tomorrow.
        if grade == .again {
            return Outcome(
                stability: stability,
                difficulty: difficulty,
                intervalDays: 0,
                due: now.addingTimeInterval(10 * 60),
                phase: phase
            )
        }

        let days = interval(stability: stability)
        return Outcome(
            stability: stability,
            difficulty: difficulty,
            intervalDays: days,
            due: now.addingTimeInterval(days * 86_400),
            phase: phase
        )
    }

    /// Interval each grade would produce, for the "1일 / 4일 / 9일" hints on the
    /// grading buttons.
    public func previewIntervals(for state: ReviewState, now: Date = .now) -> [ReviewGrade: Double] {
        Dictionary(uniqueKeysWithValues: ReviewGrade.allCases.map { grade in
            (grade, schedule(state, grade: grade, now: now).intervalDays)
        })
    }
}

public extension ReviewState {
    /// Applies a scheduling outcome in place.
    func apply(_ outcome: FSRS.Outcome, at now: Date = .now) {
        stability = outcome.stability
        difficulty = outcome.difficulty
        due = outcome.due
        phase = outcome.phase
        lastReview = now
        reps += 1
        if outcome.phase == .relearning { lapses += 1 }
    }
}
