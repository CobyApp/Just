import JustCore
import JustDesign
import SwiftUI

/// Four tabs, one per intent: what to do now, what to study next, what I have
/// collected, and being tested on it.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Destination = .today

    enum Destination: Hashable {
        case today, browse, words, practice
    }

    var body: some View {
        @Bindable var app = app

        TabView(selection: $selection) {
            Tab("오늘", systemImage: "flame", value: Destination.today) {
                HomeScreen()
            }
            Tab("둘러보기", systemImage: "music.note.list", value: Destination.browse) {
                SearchScreen()
            }
            Tab("단어장", systemImage: "character.book.closed", value: Destination.words) {
                LibraryScreen()
            }
            Tab("연습", systemImage: "square.dashed", value: Destination.practice) {
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
/// `RootView`'s own state rather than inside the `TabView`, so rebuilding the
/// subtree when a song starts does not move the user to another tab.
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
