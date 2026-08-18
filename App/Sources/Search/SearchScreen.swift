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
    @State private var searchTask: Task<Void, Never>?

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
            .searchable(text: $query, prompt: "곡 이름, 아티스트")
            .onSubmit(of: .search) { runSearch() }
            .sheet(isPresented: $showsSettings) { SettingsScreen() }
        }
    }

    @ViewBuilder
    private var content: some View {
        // Debug builds fall through to the browse screen, which carries the
        // sample songs — a Simulator can never be authorized, and gating it
        // here would make the whole app unreachable there.
        if !app.isAuthorized && !Self.allowsUnauthorizedBrowsing {
            authorizationGate
        } else {
            switch state {
            case .idle:
                DiscoveryView()
            case .loading:
                ProgressView().controlSize(.large)
            case .failed(let message):
                ContentUnavailableView {
                    Label("검색할 수 없습니다", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("다시 시도") { runSearch() }
                        .buttonStyle(.justPrimary)
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
        ContentUnavailableView {
            Label("Apple Music 접근 허용", systemImage: "music.note")
        } description: {
            Text("곡을 검색하고 재생하려면 Apple Music 라이브러리 접근을 허용해 주세요. 계정 정보는 앱 밖으로 나가지 않습니다.")
        } actions: {
            Button("허용하기") {
                Task { await app.requestAccess() }
            }
            .buttonStyle(.justPrimary)
        }
    }

    private static var allowsUnauthorizedBrowsing: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
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

    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .idle
            return
        }
        searchTask?.cancel()
        state = .loading
        searchTask = Task {
            do {
                let found = try await app.music.search(trimmed)
                guard !Task.isCancelled else { return }
                results = found
                state = .loaded
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }
}

struct TrackRow: View {
    let track: Track
    var progress: Double?

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
                if let progress, progress > 0 {
                    ProgressView(value: progress)
                        .tint(JustTheme.Ink.secondary)
                        .frame(height: 2)
                        .padding(.top, 2)
                }
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
