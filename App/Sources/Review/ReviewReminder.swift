import Foundation
import JustCore
import Observation
import UserNotifications

/// A daily nudge when cards are waiting.
///
/// Spaced repetition only works if the user comes back on the day the schedule
/// asks for — an app that computes a perfect interval and then says nothing is
/// relying on the user to remember, which defeats the point.
@MainActor
@Observable
final class ReviewReminder {
    private enum Key {
        static let enabled = "reminder.enabled"
        static let hour = "reminder.hour"
        static let minute = "reminder.minute"
    }

    private static let identifier = "just.review.daily"

    private let defaults: UserDefaults

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Key.enabled)
            Task { await apply() }
        }
    }

    /// Stored as components rather than a `Date` so it survives timezone moves.
    var time: DateComponents {
        didSet {
            guard time != oldValue else { return }
            defaults.set(time.hour ?? 21, forKey: Key.hour)
            defaults.set(time.minute ?? 0, forKey: Key.minute)
            Task { await apply() }
        }
    }

    private(set) var isDenied = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Key.enabled)
        self.time = DateComponents(
            hour: defaults.object(forKey: Key.hour) as? Int ?? 21,
            minute: defaults.object(forKey: Key.minute) as? Int ?? 0
        )
    }

    var timeAsDate: Date {
        Calendar.current.date(
            bySettingHour: time.hour ?? 21,
            minute: time.minute ?? 0,
            second: 0,
            of: .now
        ) ?? .now
    }

    func setTime(from date: Date) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        time = DateComponents(hour: parts.hour, minute: parts.minute)
    }

    /// Requests permission and schedules, or clears the schedule when off.
    func apply() async {
        let center = UNUserNotificationCenter.current()

        guard isEnabled else {
            center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
            return
        }

        let granted: Bool
        do {
            granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            granted = false
        }

        guard granted else {
            isDenied = true
            // Reflect reality: the switch should not read as on when the system
            // will never deliver anything.
            isEnabled = false
            return
        }

        isDenied = false
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])

        let content = UNMutableNotificationContent()
        content.title = "복습할 단어가 기다리고 있어요"
        content.body = "가사에서 담은 단어를 예문과 함께 다시 봅니다."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        )
        try? await center.add(request)
    }

    /// Keeps the badge honest about how many cards are actually due.
    func updateBadge(dueCount: Int) async {
        guard isEnabled else { return }
        try? await UNUserNotificationCenter.current().setBadgeCount(dueCount)
    }
}
