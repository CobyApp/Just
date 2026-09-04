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
            Tab("노래 찾기", systemImage: "music.mic", value: AppModel.Tab.groups) {
                GroupsScreen()
            }
            Tab("내 노래", systemImage: "music.note.list", value: AppModel.Tab.mySongs) {
                MySongsScreen()
            }
            Tab("단어장", systemImage: "character.book.closed.fill", value: AppModel.Tab.words) {
                LibraryScreen()
            }
            Tab("연습", systemImage: "checkmark.circle.fill", value: AppModel.Tab.practice) {
                PracticeScreen()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // The selected tab in the app's own pink rather than system blue.
        .tint(JustTheme.Kawaii.accent)
        // Sits above the tab bar rather than inside a tab, so it survives
        // switching tabs — which is the whole point of having it.
        .modifier(MiniPlayerAccessory(
            track: app.openTrack == nil ? app.nowPlaying : nil
        ))
        .fullScreenCover(item: $app.openTrack) { track in
            PlayerScreen(track: track)
        }
        .task { await app.prepareAccess() }
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
/// tab bar. `isEnabled` is how the slot is declined instead. The earlier fix —
/// an `if let` around the whole modifier — gave SwiftUI two different view
/// trees, and swapping between them rebuilt the `TabView`: every tab's
/// `NavigationStack` lost its path, so collapsing the player dropped the reader
/// from a group's song list back to the home grid.
private struct MiniPlayerAccessory: ViewModifier {
    let track: Track?

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: track != nil) {
                if let track {
                    MiniPlayer(track: track)
                }
            }
        } else if let track {
            // iOS 26.0 has no `isEnabled`; this branch still rebuilds the tab
            // tree. The home tab keeps its navigation path in `AppModel` so
            // the rebuild at least does not lose the reader's place.
            content.tabViewBottomAccessory {
                MiniPlayer(track: track)
            }
        } else {
            content
        }
    }
}
