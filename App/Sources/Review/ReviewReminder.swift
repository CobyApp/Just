import Foundation
import JustCore
import Observation
import UserNotifications

/// A nudge when cards are waiting.
///
/// Spaced repetition only works if the user comes back on the day the schedule
/// asks for — an app that computes a perfect interval and then says nothing is
/// relying on the user to remember, which defeats the point.
///
/// One notification, not a repeating one: it is set for the reminder time on
/// or after the next card falls due, and set again every time the schedule is
/// published (each grade, each save, each return to the app). The repeating
/// version fired every evening whether or not anything was due — with no
/// words at all, even — and a reminder that is usually wrong is one that gets
/// switched off.
@MainActor
@Observable
final class ReviewReminder {
    private enum Key {
        static let enabled = "reminder.enabled"
        static let hour = "reminder.hour"
        static let minute = "reminder.minute"
    }

    /// Kept from the repeating version on purpose: scheduling under the same
    /// identifier replaces the daily request an older build left behind.
    private static let identifier = "just.review.daily"

    private let defaults: UserDefaults

    /// The schedule as last published by the store; nil until the first
    /// publish after launch.
    @ObservationIgnored private var outlook: ReviewOutlook?

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

    /// Takes a freshly published schedule and re-plans around it.
    func update(_ outlook: ReviewOutlook) {
        self.outlook = outlook
        Task { await reschedule() }
    }

    /// Requests permission and schedules, or clears the schedule when off.
    func apply() async {
        guard isEnabled else {
            await reschedule()
            return
        }

        let granted: Bool
        do {
            granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            granted = false
        }

        guard granted else {
            isDenied = true
            // Reflect reality: the switch should not read as on when the system
            // will never deliver anything. (Its didSet clears what is left.)
            isEnabled = false
            return
        }

        isDenied = false
        await reschedule()
    }

    /// Replaces the pending reminder and the badge with ones that match the
    /// current schedule.
    private func reschedule() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])

        guard isEnabled else {
            // Nothing else would ever take the number off the icon once
            // reminders are off, so it goes now.
            try? await center.setBadgeCount(0)
            return
        }
        // Never prompts from here — only turning the switch on asks.
        guard await Self.isAuthorized(), let outlook else { return }

        // Keeps the badge honest about how many cards are actually due.
        try? await center.setBadgeCount(outlook.dueCount)

        // Nothing due and nothing coming: no reminder at all.
        guard let fireDate = outlook.reminderDate(
            hour: time.hour ?? 21,
            minute: time.minute ?? 0
        ) else { return }

        let content = UNMutableNotificationContent()
        content.title = "복습할 단어가 기다리고 있어요"
        content.body = "가사에서 담은 단어를 예문과 함께 다시 봅니다."
        content.sound = .default
        // What the badge should read by then, since the app will not be
        // running to update it.
        content.badge = NSNumber(value: outlook.dueCount(at: fireDate))
        // Read by the notification delegate to route the tap.
        content.userInfo = ["route": "review"]

        let parts = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let request = UNNotificationRequest(
            identifier: Self.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        )
        // Checked again: the switch may have been turned off while this was
        // suspended above, and that reschedule's removal has already run.
        guard isEnabled else { return }
        try? await center.add(request)
    }

    /// Reads the permission without asking for it. Nonisolated so the
    /// settings object never has to cross onto the main actor.
    private nonisolated static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }
}
