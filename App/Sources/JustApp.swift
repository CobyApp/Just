import JustCore
import JustDesign
import SwiftData
import SwiftUI

@main
struct JustApp: App {
    @State private var app = AppModel()
    private let container: ModelContainer

    init() {
        do {
            container = try JustSchema.container()
        } catch {
            // A store that won't open is unrecoverable at launch; fall back to
            // memory so the app still runs and can report the problem.
            container = try! JustSchema.container(inMemory: true)
        }
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
