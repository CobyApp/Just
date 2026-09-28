import RingRingCore
import RingRingDesign
import SwiftUI

/// Four tabs, one per intent: what to do now, what to study next, what I have
/// collected, and being tested on it.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app

        TabView(selection: $app.tab) {
            Tab("노래 찾기", systemImage: "music.mic", value: AppModel.Tab.groups) {
                GroupsScreen()
                    .modifier(MiniPlayerRoom(isShown: app.nowPlaying != nil))
            }
            Tab("내 노래", systemImage: "music.note.list", value: AppModel.Tab.mySongs) {
                MySongsScreen()
                    .modifier(MiniPlayerRoom(isShown: app.nowPlaying != nil))
            }
            Tab("단어장", systemImage: "character.book.closed.fill", value: AppModel.Tab.words) {
                LibraryScreen()
                    .modifier(MiniPlayerRoom(isShown: app.nowPlaying != nil))
            }
            Tab("연습", systemImage: "checkmark.circle.fill", value: AppModel.Tab.practice) {
                PracticeScreen()
                    .modifier(MiniPlayerRoom(isShown: app.nowPlaying != nil))
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // The selected tab in the app's own pink rather than system blue.
        .tint(app.oshi?.memberColor ?? JustTheme.Kawaii.accent)
        // Sits above the tab bar rather than inside a tab, so it survives
        // switching tabs — which is the whole point of having it.
        .modifier(MiniPlayerAccessory(
            track: app.openTrack == nil ? app.nowPlaying : nil
        ))
        .fullScreenCover(item: $app.openTrack) { track in
            PlayerScreen(track: track)
        }
        .onOpenURL { url in
            guard let route = AppModel.Route(url: url) else { return }
            app.go(to: route)
        }
        // A YouTube video may not play where it cannot be seen, so going to
        // the background pauses it. `.inactive` is not enough: pulling down
        // Control Center passes through it while the video is still on screen.
        // The 30-second clip is audio and carries on.
        .onChange(of: scenePhase) { _, phase in
            app.player.sceneDidChange(isActive: phase != .background)
            if phase == .active {
                JustStore(context: context).publishActivity()
                // The translation pack may have finished downloading, or the
                // setting been changed, while the app was away — so lines left
                // without a sentence can get one on the next pass.
                Task { await app.sensei.refreshTranslator() }
            }
        }
        // Cards fall due while the app is closed, and the reminder planned
        // last time may no longer fit, so the widget, the badge and the
        // reminder are brought up to date whenever the app comes back — not
        // only after a grade. Here rather than in a tab, which may never load.
        .task { JustStore(context: context).publishActivity() }
        // Fetched at launch, so the first song's ad is ready the moment its
        // analysis starts instead of loading while the analysis runs alone.
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

/// Room at the bottom of a tab for the mini player.
///
/// The accessory floats over the tab's content without adding to its safe
/// area, so anything pinned to the bottom of a screen — the review's grade
/// buttons, a quiz's answer bar — sat half underneath it. Scrolling screens
/// got away with it; fixed ones did not.
private struct MiniPlayerRoom: ViewModifier {
    let isShown: Bool

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.bottom, isShown ? 58 : 0)
            .animation(.snappy, value: isShown)
    }
}
