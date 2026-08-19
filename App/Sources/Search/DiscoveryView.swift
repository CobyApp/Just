import JustCore
import JustDesign
import JustMusic
import SwiftData
import SwiftUI

/// What the search tab shows before anything is typed.
///
/// Recommendations are seeded from the artists already in the library rather
/// than from a generic popularity feed: a song by an artist the user has
/// already worked through shares vocabulary, register and often subject matter,
/// which makes it a better second song than whatever is trending.
struct DiscoveryView: View {
    @Environment(AppModel.self) private var app

    @Query(sort: \StudySong.lastOpenedAt, order: .reverse)
    private var recents: [StudySong]

    @State private var shelves: [MusicShelf] = []
    @State private var isLoading = false
    @State private var hasLoaded = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: JustTheme.Space.section) {
                if !recents.isEmpty {
                    recentShelf
                }

                ForEach(shelves) { item in
                    shelf(title: item.title, subtitle: item.subtitle, tracks: item.tracks)
                }

                if isLoading {
                    // Two shelves' worth, so the screen has the shape of what
                    // is coming instead of a spinner in the middle of nothing.
                    SkeletonShelf()
                    SkeletonShelf()
                } else if isEmpty {
                    emptyState
                }

            }
            .padding(.vertical, JustTheme.Space.regular)
        }
        .scrollIndicators(.hidden)
        .task { await load() }
        .refreshable { await load(force: true) }
    }

    // MARK: - Shelves

    private var recentShelf: some View {
        shelfContainer(title: "이어서 공부하기", subtitle: nil) {
            ForEach(recents.prefix(12)) { song in
                Button {
                    app.open(song.track)
                } label: {
                    VStack(alignment: .leading, spacing: JustTheme.Space.tight) {
                        ArtworkTile(track: song.track)
                        if song.studyProgress > 0 {
                            StudyProgressBar(progress: song.studyProgress, width: 148)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func shelf(
        title: String,
        subtitle: String?,
        tracks: [Track],
        muted: Bool = false
    ) -> some View {
        shelfContainer(title: title, subtitle: subtitle, muted: muted) {
            ForEach(tracks) { track in
                Button { app.open(track) } label: { ArtworkTile(track: track) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func shelfContainer<Content: View>(
        title: String,
        subtitle: String?,
        muted: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: JustTheme.Space.snug) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(muted ? JustTheme.Font.body.weight(.semibold) : JustTheme.Font.title)
                    .foregroundStyle(muted ? JustTheme.Ink.secondary : JustTheme.Ink.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(JustTheme.Font.caption)
                        .foregroundStyle(JustTheme.Ink.tertiary)
                }
            }
            .padding(.horizontal, JustTheme.Space.regular)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: JustTheme.Space.snug) {
                    content()
                }
                .padding(.horizontal, JustTheme.Space.regular)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var emptyState: some View {
        JustEmptyState(
            icon: "music.note",
            title: "좋아하는 노래로 시작하세요",
            message: "곡을 검색하면 가사를 줄 단위로 뜯어서 단어와 표현을 정리해 줍니다. 한 곡을 공부하고 나면 여기에 다음 곡을 추천해 드립니다."
        )
        .padding(.top, JustTheme.Space.section)
    }

    private var isEmpty: Bool {
        hasLoaded && shelves.isEmpty && recents.isEmpty
    }

    // MARK: - Loading

    private func load(force: Bool = false) async {
        guard app.isAuthorized else {
            hasLoaded = true
            return
        }
        guard force || !hasLoaded else { return }

        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        // Songs already in the library are dropped from the shelves — a
        // recommendation the user is already studying is not a recommendation.
        let owned = Set(recents.map(\.videoID))
        let seeds = orderedArtists(from: recents)
        shelves = await app.music.shelves(seedArtists: seeds, excluding: owned)
    }

    /// Distinct artists, most recently opened first.
    private func orderedArtists(from songs: [StudySong]) -> [String] {
        var seen = Set<String>()
        return songs.compactMap { song in
            let name = song.artist.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, seen.insert(name).inserted else { return nil }
            return name
        }
    }
}
