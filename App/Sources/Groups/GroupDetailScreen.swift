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
            JustBrandBackground()
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
                VStack(spacing: JustTheme.Space.snug) {
                    groupHeader
                    JustActionHint("노래를 누르면 재생과 함께 가사 공부가 시작됩니다.", symbol: "play.circle.fill")
                        .dismissibleGuide("group.tap")

                    LazyVStack(spacing: JustTheme.Space.tight) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { offset, track in
                            Button { app.open(track, in: tracks) } label: {
                                SongRow(track: track, index: offset + 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                }
                .padding(JustTheme.Space.regular)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// The group's own picture, already fetched for its card.
    private var groupHeader: some View {
        HStack(spacing: JustTheme.Space.snug) {
            RowArtwork(url: store.artworkURL(for: group), seed: group.id, size: 72)
            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.kawaii(24, weight: .bold, relativeTo: .title2))
                    .foregroundStyle(JustTheme.Kawaii.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text("\(group.readingKo) · \(group.label.rawValue) · 노래 \(tracks.count)곡")
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(JustTheme.Kawaii.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .justCard()
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
