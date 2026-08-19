import JustCore
import UIKit
import UserNotifications

/// Routes a tapped notification into the app.
///
/// `onOpenURL` never fires for notifications, so the app needs a delegate to
/// turn a tap into the same route a URL would produce. Installed at launch
/// because iOS delivers a notification tapped from a cold start immediately, and
/// a delegate registered later would miss it.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    /// Set before the delegate can fire; read on the main actor.
    nonisolated(unsafe) static var onRoute: (@MainActor (AppModel.Route) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if let name = info["route"] as? String,
           let route = AppModel.Route(rawValue: name) {
            Task { @MainActor in Self.onRoute?(route) }
        }
        completionHandler()
    }

    /// Shows the banner even in the foreground.
    ///
    /// Suppressing it would mean a reminder that arrives while the user is in the
    /// app does nothing at all — and being in the app is not the same as being on
    /// the review screen.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
