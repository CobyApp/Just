import Foundation
import SwiftData

/// One calendar day of study activity.
///
/// `ReviewState` only remembers a word's *last* review, so it cannot answer
/// "how many days in a row have I studied" — the history is overwritten every
/// time. A row per day is the smallest thing that can.
@Model
public final class StudyDay {
    #Unique<StudyDay>([\.day])

    /// Midnight, in the user's calendar, of the day being recorded.
    public var day: Date = Date.distantPast
    public var reviewed: Int = 0
    public var learned: Int = 0

    public init(day: Date) {
        self.day = day
    }
}

/// One day on the activity chart.
public struct DayActivity: Identifiable, Sendable, Equatable {
    public var id: Date { day }
    public let day: Date
    public let reviewed: Int
    public let learned: Int

    public init(day: Date, reviewed: Int, learned: Int) {
        self.day = day
        self.reviewed = reviewed
        self.learned = learned
    }

    public var isEmpty: Bool { reviewed == 0 && learned == 0 }
}

/// A rolled-up view of study activity, for the header on the word list.
public struct StudyStats: Sendable, Equatable {
    public let reviewedToday: Int
    public let learnedToday: Int
    /// Consecutive days up to and including today with any activity.
    public let streak: Int
    public let totalWords: Int
    public let dueCount: Int
    /// Words grouped by JLPT level, for the distribution chart.
    public let levelCounts: [JLPTLevel: Int]
    /// Trailing week, oldest first, with quiet days filled in as zero so the
    /// chart keeps a fixed seven-column shape.
    public let week: [DayActivity]

    public init(
        reviewedToday: Int,
        learnedToday: Int,
        streak: Int,
        totalWords: Int,
        dueCount: Int,
        levelCounts: [JLPTLevel: Int] = [:],
        week: [DayActivity] = []
    ) {
        self.reviewedToday = reviewedToday
        self.learnedToday = learnedToday
        self.streak = streak
        self.totalWords = totalWords
        self.dueCount = dueCount
        self.levelCounts = levelCounts
        self.week = week
    }

    public var weeklyReviewed: Int { week.reduce(0) { $0 + $1.reviewed } }

    /// Highest single-day count, used to scale the chart so a quiet week still
    /// renders readable bars.
    public var weeklyPeak: Int { max(week.map(\.reviewed).max() ?? 0, 1) }

    public var levelBreakdown: [(level: JLPTLevel, count: Int)] {
        JLPTLevel.allCases.sorted(by: <).compactMap { level in
            guard let count = levelCounts[level], count > 0 else { return nil }
            return (level, count)
        }
    }

    public static let empty = StudyStats(
        reviewedToday: 0, learnedToday: 0, streak: 0, totalWords: 0, dueCount: 0
    )
}

/// Computes a streak from day records.
///
/// Kept separate from the store so it is testable without a context, and so
/// the "today doesn't break the streak yet" rule lives in exactly one place.
public enum StreakCalculator {
    /// Days are counted backwards from today. Today having no activity yet does
    /// not break a streak — otherwise every morning would show zero, which
    /// punishes the user for not having studied yet.
    public static func streak(
        days: [Date],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let recorded = Set(days.map { calendar.startOfDay(for: $0) })
        guard !recorded.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: now)
        if !recorded.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  recorded.contains(yesterday)
            else { return 0 }
            cursor = yesterday
        }

        var count = 0
        while recorded.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}
