import JustCore
import JustDesign
import SwiftUI

/// Four tabs, one per intent: what to do now, what to study next, what I have
/// collected, and being tested on it.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app

        TabView(selection: $app.tab) {
            Tab("오늘", systemImage: "flame", value: AppModel.Tab.today) {
                HomeScreen()
            }
            Tab("둘러보기", systemImage: "music.note.list", value: AppModel.Tab.browse) {
                SearchScreen()
            }
            Tab("단어장", systemImage: "character.book.closed", value: AppModel.Tab.words) {
                LibraryScreen()
            }
            Tab("연습", systemImage: "square.dashed", value: AppModel.Tab.practice) {
                PracticeScreen()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // Sits above the tab bar rather than inside a tab, so it survives
        // switching tabs — which is the whole point of having it.
        .modifier(MiniPlayerAccessory(
            track: app.openTrack == nil ? app.nowPlaying : nil
        ))
        .fullScreenCover(item: $app.openTrack) { track in
            PlayerScreen(track: track)
        }
        .task { await app.refreshAccess() }
        .onOpenURL { url in
            guard let route = AppModel.Route(url: url) else { return }
            app.go(to: route)
        }
        .onChange(of: scenePhase) { _, phase in
            // The permission can be flipped in Settings while the app is
            // backgrounded, and iOS gives no callback for it.
            guard phase == .active else { return }
            Task { await app.refreshAccess() }
        }
    }
}

/// Attaches the mini player, or nothing at all.
///
/// The accessory slot is reserved as soon as the modifier is applied, so
/// returning an empty view inside it left an empty capsule floating above the
/// tab bar. The modifier itself has to be conditional. Tab selection lives in
/// `AppModel` rather than inside the `TabView`, so rebuilding the subtree when a
/// song starts does not move the user to another tab — and a screen can send
/// them to one deliberately.
private struct MiniPlayerAccessory: ViewModifier {
    let track: Track?

    func body(content: Content) -> some View {
        if let track {
            content.tabViewBottomAccessory {
                MiniPlayer(track: track)
            }
        } else {
            content
        }
    }
}
