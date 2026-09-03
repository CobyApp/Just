import JustCore
import JustDesign
import JustMusic
import SwiftUI

/// One group's songs.
struct GroupDetailScreen: View {
    let group: IdolGroup
    let store: GroupArtworkStore

    @Environment(AppModel.self) private var app
    @State private var tracks: [Track] = []
    @State private var failure: String?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            JustTheme.Surface.kawaii.ignoresSafeArea()
            content
        }
        // The app is pinned to dark in its Info.plist, which the navigation
            // bar obeys — so on a bright screen the title and the toolbar
            // button were white on white. The bar is told otherwise.
        .environment(\.colorScheme, .light)
        // Same reason as the groups screen: the bar follows the app-wide dark
        // style, so its own contents are coloured here instead.
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(group.name)
                    .font(JustTheme.Font.body.weight(.bold))
                    .foregroundStyle(JustTheme.Kawaii.ink)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .tint(JustTheme.Kawaii.ink)
        .task(id: group.id) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().controlSize(.large)
        } else if let failure {
            JustEmptyState(
                icon: "exclamationmark.triangle",
                title: "곡을 불러오지 못했습니다",
                message: failure,
                actionTitle: "다시 시도",
                action: { Task { await load() } }
            )
        } else if tracks.isEmpty {
            JustEmptyState(
                icon: "music.note",
                title: "곡이 없습니다",
                message: "Apple Music에 이 그룹의 곡이 아직 올라오지 않았습니다."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: JustTheme.Space.tight) {
                    ForEach(tracks) { track in
                        Button { app.open(track) } label: { row(track) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(JustTheme.Space.regular)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func row(_ track: Track) -> some View {
        HStack(spacing: JustTheme.Space.snug) {
            ArtworkTile(track: track, width: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(JustTheme.Font.body.weight(.semibold))
                    .foregroundStyle(JustTheme.Kawaii.ink)
                    .lineLimit(2)
                Text(track.artist)
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(JustTheme.Kawaii.inkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(JustTheme.Kawaii.inkSoft)
        }
        .padding(JustTheme.Space.snug)
        .background(.white.opacity(0.75), in: .rect(cornerRadius: 18))
        .contentShape(.rect)
    }

    private func load() async {
        // Already fetched for the card, usually — the same request carried the
        // songs, so opening a group the grid has shown costs nothing.
        if let cached = store.songs(for: group) {
            tracks = cached
            isLoading = false
            return
        }
        isLoading = true
        failure = nil
        do {
            tracks = try await store.reload(group).songs
        } catch {
            failure = error.localizedDescription
        }
        isLoading = false
    }
}
