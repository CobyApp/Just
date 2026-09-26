import Foundation

/// What the review schedule looks like from one moment: how many cards are due
/// now and when the next ones come up.
///
/// The widget and the reminder both run while the app is not — the widget in
/// its own process, the notification at a time chosen in advance — so neither
/// can ask the store "how many are due now". This carries enough of the
/// schedule for them to answer that for any later moment themselves.
public struct ReviewOutlook: Codable, Sendable, Equatable {
    /// How many upcoming due dates are carried. Past this the counts are a
    /// lower bound, which only matters for someone with hundreds of cards
    /// falling due before the app is next opened.
    public static let upcomingCap = 200

    /// The moment `dueCount` was counted at.
    public let asOf: Date
    /// Cards due at `asOf`.
    public let dueCount: Int
    /// Due dates after `asOf`, soonest first, capped at `upcomingCap`.
    public let upcoming: [Date]

    public init(asOf: Date, dueCount: Int, upcoming: [Date]) {
        self.asOf = asOf
        self.dueCount = dueCount
        self.upcoming = upcoming.sorted()
    }

    /// Cards due at `date`: the ones already due plus those that have come up
    /// since. Before `asOf` there is nothing better to say than `dueCount`.
    public func dueCount(at date: Date) -> Int {
        guard date > asOf else { return dueCount }
        return dueCount + upcoming.prefix { $0 <= date }.count
    }

    /// When the next card is due — `asOf` itself if some already are.
    public var nextDue: Date? {
        dueCount > 0 ? asOf : upcoming.first
    }

    /// When a reminder set for `hour`:`minute` should next fire.
    ///
    /// The first time of day at that clock time on or after the next due card,
    /// and never in the past. Nil when nothing is scheduled at all — a reminder
    /// about an empty queue is noise, and noise is what gets notifications
    /// turned off.
    public func reminderDate(
        hour: Int,
        minute: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        guard let next = nextDue else { return nil }
        let start = max(next, now)
        guard let sameDay = calendar.date(
            bySettingHour: hour, minute: minute, second: 0, of: start
        ) else { return nil }
        if sameDay >= start, sameDay > now { return sameDay }
        return calendar.date(byAdding: .day, value: 1, to: sameDay)
    }
}
