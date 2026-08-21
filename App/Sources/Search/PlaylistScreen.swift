import JustCore
import JustDesign
import JustMusic
import SwiftUI

/// The user's Apple Music playlists, and the songs on one of them.
///
/// This is the fastest way into the app for someone who already listens to
/// J-pop: their playlists are the list of songs they care about, and typing
/// those into a search box one at a time is work they have already done.
struct PlaylistScreen: View {
    @Environment(AppModel.self) private var app

    @State private var playlists: [MusicPlaylist] = []
    @State private var state: LoadState = .loading

    private enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    var body: some View {
        ZStack {
            JustTheme.Surface.base.ignoresSafeArea()
            content
        }
        .navigationTitle("내 플레이리스트")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: MusicPlaylist.self) { PlaylistDetailScreen(playlist: $0) }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            List(0..<6, id: \.self) { _ in
                SkeletonTrackRow().listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .allowsHitTesting(false)

        case .failed(let message):
            ContentUnavailableView {
                Label("플레이리스트를 불러오지 못했습니다", systemImage: "music.note.list")
            } description: {
                Text(message)
            } actions: {
                Button("다시 시도") { Task { await load() } }
                    .buttonStyle(.justPrimary)
            }

        case .loaded:
            if playlists.isEmpty {
                ContentUnavailableView {
                    Label("플레이리스트가 없습니다", systemImage: "music.note.list")
                } description: {
                    Text("Apple Music에서 플레이리스트를 만들면 여기에 나타납니다.")
                }
            } else {
                List(playlists) { playlist in
                    NavigationLink(value: playlist) {
                        PlaylistRow(playlist: playlist)
                    }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func load() async {
        state = .loading
        do {
            playlists = try await app.music.libraryPlaylists()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct PlaylistRow: View {
    let playlist: MusicPlaylist
    @State private var artwork = ArtworkLoader()

    var body: some View {
        HStack(spacing: JustTheme.Space.snug) {
            ArtworkView(image: artwork.image, cornerRadius: 8, seed: playlist.id)
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .font(JustTheme.Font.body.weight(.medium))
                    .foregroundStyle(JustTheme.Ink.primary)
                    .lineLimit(1)
                if let count = playlist.trackCount {
                    Text("\(count)곡")
                        .font(JustTheme.Font.caption)
                        .foregroundStyle(JustTheme.Ink.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .task(id: playlist.artworkURL) { await artwork.load(playlist.artworkURL) }
    }
}

/// The songs on one playlist.
private struct PlaylistDetailScreen: View {
    let playlist: MusicPlaylist

    @Environment(AppModel.self) private var app
    @State private var tracks: [Track] = []
    @State private var failure: String?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            JustTheme.Surface.base.ignoresSafeArea()

            if isLoading {
                List(0..<8, id: \.self) { _ in
                    SkeletonTrackRow().listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .allowsHitTesting(false)
            } else if let failure {
                ContentUnavailableView {
                    Label("곡을 불러오지 못했습니다", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure)
                }
            } else if tracks.isEmpty {
                ContentUnavailableView {
                    Label("곡이 없습니다", systemImage: "music.note")
                } description: {
                    Text("이 플레이리스트에는 재생할 수 있는 곡이 없습니다.")
                }
            } else {
                List(tracks) { track in
                    TrackRow(track: track)
                        .contentShape(.rect)
                        .onTapGesture { app.open(track) }
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                tracks = try await app.music.tracks(inPlaylist: playlist.id)
            } catch {
                failure = error.localizedDescription
            }
            isLoading = false
        }
    }
}
