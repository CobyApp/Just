import JustCore
import JustDesign
import SwiftUI

/// Four tabs, one per intent: what to do now, what to study next, what I have
/// collected, and being tested on it.
struct RootView: View {
    @Environment(AppModel.self) private var app
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
        .fullScreenCover(item: $app.openTrack) { track in
            PlayerScreen(track: track)
        }
    }
}
