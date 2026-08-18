import JustCore
import JustDesign
import SwiftUI

/// Two tabs, because the app has two jobs: find a song, and study the words
/// that came out of it.
///
/// Review used to be a third tab and was empty most of the time — a permanent
/// slot for something that only exists once cards are due. It now lives at the
/// top of the word list, where the due count can actually be shown.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var selection: Destination = .browse

    enum Destination: Hashable {
        case browse, words
    }

    var body: some View {
        @Bindable var app = app

        TabView(selection: $selection) {
            Tab("둘러보기", systemImage: "music.note.list", value: Destination.browse) {
                SearchScreen()
            }
            Tab("단어장", systemImage: "character.book.closed", value: Destination.words) {
                LibraryScreen()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .fullScreenCover(item: $app.openTrack) { track in
            PlayerScreen(track: track)
        }
    }
}
