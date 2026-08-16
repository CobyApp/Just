import Foundation
import SwiftData

public enum ReviewPhase: Int, Codable, Sendable {
    case new = 0
    case learning = 1
    case review = 2
    case relearning = 3
}

/// Grades follow the FSRS convention: 1 again, 2 hard, 3 good, 4 easy.
public enum ReviewGrade: Int, CaseIterable, Sendable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    public var label: String {
        switch self {
        case .again: "다시"
        case .hard: "어려움"
        case .good: "알맞음"
        case .easy: "쉬움"
        }
    }
}

@Model
public final class ReviewState {
    public var due: Date = Date.distantPast
    public var stability: Double = 0
    public var difficulty: Double = 0
    public var reps: Int = 0
    public var lapses: Int = 0
    public var lastReview: Date?
    public var phaseRaw: Int = ReviewPhase.new.rawValue

    public init() {
        self.due = .now
        self.phaseRaw = ReviewPhase.new.rawValue
    }

    public var phase: ReviewPhase {
        get { ReviewPhase(rawValue: phaseRaw) ?? .new }
        set { phaseRaw = newValue.rawValue }
    }

    public var isDue: Bool { due <= .now }
}
