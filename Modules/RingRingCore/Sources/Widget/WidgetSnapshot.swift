import Foundation

/// What the home screen widget shows.
///
/// A snapshot rather than shared database access: a widget has no business
/// opening the app's SwiftData store — it would have to survive schema changes
/// and it can never write. (The store does live in the App Group container,
/// but only because that is where SwiftData put it once the entitlement
/// existed — see `StoreLocation`.) The app writes this file; the widget reads
/// it, and works out from the schedule it carries what changes over time.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    /// Cards due at `updatedAt`. Read `dueCount(at:)` for any later moment.
    public let dueCount: Int
    /// The streak as of `updatedAt`. Read `streak(at:)` for any later moment.
    public let streak: Int
    public let totalWords: Int
    /// One word to show on the face of the widget, if there is one.
    public let word: Word?
    public let updatedAt: Date
    /// Due dates after `updatedAt`, soonest first and capped — see
    /// `ReviewOutlook`. Optional, like everything added after the first
    /// release: a snapshot written by an older build must still decode.
    public let upcomingDue: [Date]?
    /// The last day with any study activity, so the widget can tell when the
    /// streak has lapsed without the app running.
    public let lastStudyDay: Date?
    /// The reader's favourite group, for the widget's colour and its
    /// 「최애」 line. Nil when none is picked, or from an older build.
    public let oshi: Oshi?

    public struct Oshi: Codable, Sendable, Equatable {
        public let name: String
        /// The group's hue, 0–1.
        public let hue: Double

        public init(name: String, hue: Double) {
            self.name = name
            self.hue = hue
        }
    }

    public struct Word: Codable, Sendable, Equatable {
        public let lemma: String
        public let reading: String
        public let meaningKo: String
        public let songLabel: String?

        public init(lemma: String, reading: String, meaningKo: String, songLabel: String?) {
            self.lemma = lemma
            self.reading = reading
            self.meaningKo = meaningKo
            self.songLabel = songLabel
        }
    }

    public init(
        dueCount: Int,
        streak: Int,
        totalWords: Int,
        word: Word?,
        updatedAt: Date = .now,
        upcomingDue: [Date]? = nil,
        lastStudyDay: Date? = nil,
        oshi: Oshi? = nil
    ) {
        self.dueCount = dueCount
        self.streak = streak
        self.totalWords = totalWords
        self.word = word
        self.updatedAt = updatedAt
        self.upcomingDue = upcomingDue
        self.lastStudyDay = lastStudyDay
        self.oshi = oshi
    }

    /// The same snapshot with another favourite.
    public func with(oshi: Oshi?) -> WidgetSnapshot {
        WidgetSnapshot(
            dueCount: dueCount,
            streak: streak,
            totalWords: totalWords,
            word: word,
            updatedAt: updatedAt,
            upcomingDue: upcomingDue,
            lastStudyDay: lastStudyDay,
            oshi: oshi
        )
    }

    /// The schedule this snapshot carries.
    public var outlook: ReviewOutlook {
        ReviewOutlook(asOf: updatedAt, dueCount: dueCount, upcoming: upcomingDue ?? [])
    }

    /// Cards due at `date`, counting the ones that came up since the app last
    /// wrote. Without this the widget read 「오늘 복습 완료」 all day after
    /// cards had in fact come due.
    public func dueCount(at date: Date) -> Int {
        outlook.dueCount(at: date)
    }

    /// The streak as it stands at `date`.
    ///
    /// `streak` counts consecutive days ending at `lastStudyDay`, and it
    /// survives until the end of the following day — the same "today doesn't
    /// break it yet" rule as `StreakCalculator`. After that it is zero, whether
    /// or not the app has run to say so. An old snapshot without the day is
    /// shown as written.
    public func streak(at date: Date, calendar: Calendar = .current) -> Int {
        guard let lastStudyDay else { return streak }
        let today = calendar.startOfDay(for: date)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            return streak
        }
        return calendar.startOfDay(for: lastStudyDay) >= yesterday ? streak : 0
    }

    /// The moments after `date` at which the widget's numbers change: each
    /// upcoming due time within `horizon`, plus the next two midnights, where
    /// the streak can lapse. Rounded to the minute and capped, since a timeline
    /// with hundreds of entries is not something WidgetKit will honour.
    public func timelineDates(
        after date: Date,
        horizon: TimeInterval = 24 * 60 * 60,
        limit: Int = 40,
        calendar: Calendar = .current
    ) -> [Date] {
        let end = date.addingTimeInterval(horizon)
        var dates = Set<Date>()
        var isCapped = false
        for due in (upcomingDue ?? []).sorted() where due > date && due <= end {
            // Rounded up, so the entry never lands a moment before the card
            // it is meant to count.
            let minute = (due.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60
            dates.insert(Date(timeIntervalSinceReferenceDate: minute))
            if dates.count >= limit { isCapped = true; break }
        }
        // At the cap, the timeline stops at the last card it counted rather
        // than running on to midnight: the widget reloads at its end, so the
        // cards past the cap are counted then instead of never.
        let cutoff = isCapped ? dates.max() ?? end : end
        let today = calendar.startOfDay(for: date)
        for offset in 1...2 {
            if let midnight = calendar.date(byAdding: .day, value: offset, to: today),
               midnight <= cutoff || !isCapped {
                dates.insert(midnight)
            }
        }
        return dates.sorted()
    }

    public static let placeholder = WidgetSnapshot(
        dueCount: 0,
        streak: 0,
        totalWords: 0,
        word: Word(
            lemma: "夢",
            reading: "ゆめ",
            meaningKo: "꿈",
            songLabel: nil
        )
    )
}

/// Reads and writes the snapshot in the shared container.
public enum WidgetStore {
    public static let appGroup = "group.com.coby.ringring"
    private static let filename = "widget-snapshot.json"

    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(filename)
    }

    public static func write(_ snapshot: WidgetSnapshot) {
        guard let url, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public static func read() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
