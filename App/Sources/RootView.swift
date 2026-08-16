import JustCore
import JustDesign
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var selection: Destination = .search

    enum Destination: Hashable {
        case search, library, review
    }

    var body: some View {
        @Bindable var app = app

        TabView(selection: $selection) {
            Tab("검색", systemImage: "magnifyingglass", value: Destination.search) {
                SearchScreen()
            }
            Tab("보관함", systemImage: "music.note.list", value: Destination.library) {
                LibraryScreen()
            }
            Tab("복습", systemImage: "sparkles.rectangle.stack", value: Destination.review) {
                ReviewScreen()
            }
        }
        // One layout for both idioms: iPad and landscape get a sidebar, iPhone
        // keeps the tab bar.
        .tabViewStyle(.sidebarAdaptable)
        .fullScreenCover(item: $app.openTrack) { track in
            PlayerScreen(track: track)
        }
    }
}
