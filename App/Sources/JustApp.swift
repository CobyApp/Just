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
                .tint(JustTheme.Ink.primary)
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
