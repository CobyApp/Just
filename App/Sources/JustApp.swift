import GoogleMobileAds
import JustCore
import JustDesign
import SwiftData
import SwiftUI
import UserNotifications

@main
struct JustApp: App {
    @State private var app = AppModel()
    private let container: ModelContainer
    private let notifications = NotificationRouter()

    init() {
        // Started here rather than on the wait screen: the first request after
        // start-up is slow, and the wait screen is exactly where that delay
        // would be visible.
        MobileAds.shared.start(completionHandler: nil)

        do {
            container = try JustSchema.container()
        } catch {
            // A store that won't open is unrecoverable at launch; fall back to
            // memory so the app still runs and can report the problem.
            container = try! JustSchema.container(inMemory: true)
        }

        // Registered here rather than in a view: a notification tapped from a
        // cold start is delivered before any view exists.
        UNUserNotificationCenter.current().delegate = notifications
        let model = app
        NotificationRouter.onRoute = { route in model.go(to: route) }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(JustTheme.Kawaii.accent)
                // Bright by default so status/navigation chrome stays legible
                // on the pastel top-level screens. The lyric player opts back
                // into dark explicitly for long-form reading.
                .preferredColorScheme(.light)
        }
        .modelContainer(container)
    }
}
