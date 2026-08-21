import JustCore
import JustDesign
import JustMusic
import SwiftData
import SwiftUI

struct SearchScreen: View {
    @Environment(AppModel.self) private var app

    @State private var query = ""
    @State private var results: [Track] = []
    @State private var state: LoadState = .idle
    @State private var showsSettings = false
    @State private var history = SearchHistory()

    private enum LoadState: Equatable {
        case idle, loading, loaded, failed(String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                JustTheme.Surface.base.ignoresSafeArea()
                content
            }
            .navigationTitle("Just")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("설정", systemImage: "gearshape") { showsSettings = true }
                }
            }
            .navigationDestination(for: PlaylistsRoute.self) { _ in PlaylistScreen() }
            .searchable(text: $query, prompt: "곡 이름, 아티스트")
            .task(id: query) { await searchAsTyped() }
            .sheet(isPresented: $showsSettings) { SettingsScreen() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !app.isAuthorized {
            authorizationGate
        } else {
            switch state {
            case .idle:
                DiscoveryView(
                    history: history.queries,
                    onPickHistory: { query = $0 },
                    onClearHistory: { history.clear() }
                )
            case .loading:
                List(0..<8, id: \.self) { _ in
                    SkeletonTrackRow()
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .allowsHitTesting(false)
            case .failed(let message):
                ContentUnavailableView {
                    Label("검색할 수 없습니다", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    VStack(spacing: JustTheme.Space.snug) {
                        Button("다시 시도") { retry() }
                            .buttonStyle(.justPrimary)
                        Button("설정에서 연결 확인") { showsSettings = true }
                            .buttonStyle(.justSecondary)
                    }
                }
            case .loaded:
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    trackList(results)
                }
            }
        }
    }

    private var authorizationGate: some View {
        AppleMusicGate()
    }

    private func trackList(_ tracks: [Track]) -> some View {
        List(tracks) { track in
            TrackRow(track: track)
                .contentShape(.rect)
                .onTapGesture { app.open(track) }
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func searchAsTyped() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .idle
            return
        }

        // Waits for a pause in typing. Cancellation of this task by the next
        // keystroke is what makes it a debounce rather than a request per
        // character.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        state = .loading
        do {
            let found = try await app.music.search(trimmed)
            guard !Task.isCancelled else { return }
            results = found
            state = .loaded
            if !found.isEmpty { history.record(trimmed) }
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(error.localizedDescription)
        }
    }

    private func retry() {
        // Re-runs the current query by hand; `.task(id:)` only fires on change.
        Task { await searchAsTyped() }
    }
}

struct TrackRow: View {
    let track: Track

    @State private var artwork = ArtworkLoader()

    var body: some View {
        HStack(spacing: JustTheme.Space.snug) {
            ArtworkView(image: artwork.image, cornerRadius: 8, seed: track.id)
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(JustTheme.Font.body.weight(.medium))
                    .foregroundStyle(JustTheme.Ink.primary)
                    .lineLimit(1)
                // Album is worth a line of its own now that the catalog
                // actually supplies it.
                Text([track.artist, track.album].compactMap { $0 }.joined(separator: " · "))
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(JustTheme.Ink.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: JustTheme.Space.tight)

            if track.duration > 0 {
                Text(track.duration.clockString)
                    .font(JustTheme.Font.caption.monospacedDigit())
                    .foregroundStyle(JustTheme.Ink.tertiary)
            }
        }
        .padding(.vertical, 4)
        .task(id: track.artworkURL) { await artwork.load(track.artworkURL) }
    }
}

extension TimeInterval {
    var clockString: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Empty route value — the playlist list takes no parameters.
struct PlaylistsRoute: Hashable {}
