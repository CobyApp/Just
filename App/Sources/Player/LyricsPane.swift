import JustCore
import JustDesign
import JustMusic
import JustSensei
import SwiftUI

struct LyricsPane: View {
    @Bindable var session: SongSession
    let player: MusicPlayerController

    @Environment(AppModel.self) private var app
    @State private var activeLine: Int?

    var body: some View {
        Group {
            switch session.lyricsState {
            case .loading:
                VStack(alignment: .leading, spacing: JustTheme.Space.regular) {
                    Text("가사를 찾는 중")
                        .font(JustTheme.Font.caption)
                        .foregroundStyle(JustTheme.Ink.tertiary)
                    SkeletonLyrics()
                    Spacer(minLength: 0)
                }
                .padding(.top, JustTheme.Space.loose)
                .frame(maxWidth: .infinity, alignment: .leading)

            case .missing(let message):
                MissingLyricsView(session: session, message: message)

            case .ready(let lyrics):
                lyricsList(lyrics)
            }
        }
        .sheet(item: Binding(
            get: { session.selectedLine.map(LineSelection.init) },
            set: { session.selectedLine = $0?.index }
        )) { selection in
            LineStudySheet(session: session, lineIndex: selection.index)
                .presentationDetents([.medium, .large])
                .presentationBackground(.ultraThinMaterial)
        }
        .onChange(of: player.currentTime) { _, time in
            if let rewind = session.loopRewindTarget(at: time) {
                player.seek(to: rewind)
                return
            }
            guard let index = session.activeLine(at: time), index != activeLine else { return }
            activeLine = index
        }
    }

    private func lyricsList(_ lyrics: Lyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: JustTheme.Space.regular) {
                    ForEach(lyrics.lines) { line in
                        LyricRow(
                            line: line,
                            isActive: line.id == activeLine,
                            showsFurigana: session.showsFurigana,
                            scale: session.textSize.scale,
                            translation: session.translation(for: line.id),
                            isLooping: session.loopingLine == line.id,
                            isAnalyzing: app.sensei.isAnalyzing(line.id)
                        )
                        .id(line.id)
                        .contentShape(.rect)
                        .onTapGesture { select(line, in: lyrics) }
                    }
                }
                .padding(.vertical, JustTheme.Space.loose)
                // Room to scroll the last line up to a readable position.
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: JustTheme.Space.tight) {
                    followBar(proxy: proxy)
                    bulkBar
                }
            }
            // Only a finger on the list counts. Programmatic scrolling reports
            // `.animating`, so reacting to any phase would have auto-follow
            // switch itself off the first time it followed anything.
            .onScrollPhaseChange { _, phase in
                guard phase == .tracking || phase == .interacting else { return }
                session.followsPlayback = false
            }
            .onChange(of: activeLine) { _, index in
                guard let index, session.followsPlayback else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }

    /// The way back to the song after scrolling off to read something else.
    ///
    /// Auto-follow has to yield to a finger — being dragged back to the current
    /// line a second after looking up makes the lyrics unreadable while the song
    /// plays. But silently staying put strands the reader, so the way back is an
    /// offer rather than a timer: it waits as long as they are reading, and
    /// never moves the playhead, which is what tapping a line would do.
    @ViewBuilder
    private func followBar(proxy: ScrollViewProxy) -> some View {
        if !session.followsPlayback, let activeLine {
            Button {
                session.followsPlayback = true
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(activeLine, anchor: .center)
                }
                Haptics.tick()
            } label: {
                Label("현재 줄로", systemImage: "arrow.down.to.line")
                    .font(JustTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(JustTheme.Ink.primary)
                    .padding(.horizontal, JustTheme.Space.snug)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: .capsule)
                    .overlay {
                        Capsule().strokeBorder(JustTheme.Ink.hairline, lineWidth: 0.5)
                    }
            }
            .buttonStyle(.plain)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    /// Only present while a whole-song pass is actually running.
    ///
    /// This used to be a permanent button pinned over the lyrics — a
    /// once-per-song action occupying the bottom of the screen for the entire
    /// time the user is reading. The action moved to the player's menu; what
    /// stays is progress, which is worth interrupting the view for.
    @ViewBuilder
    private var bulkBar: some View {
        if let progress = session.bulkProgress {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: JustTheme.Space.snug) {
                    Text("해석 중")
                        .font(JustTheme.Font.caption)
                        .foregroundStyle(JustTheme.Ink.secondary)
                    Spacer()
                    Text("\(progress.done)/\(progress.total)")
                        .font(JustTheme.Font.caption.monospacedDigit())
                        .foregroundStyle(JustTheme.Ink.secondary)
                    Button("중지") { session.cancelBulk() }
                        .buttonStyle(.justSecondary)
                }
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .tint(JustTheme.Ink.primary)
            }
            .justCard()
            .padding(.bottom, JustTheme.Space.snug)
        }
    }

    private func select(_ line: LyricLine, in lyrics: Lyrics) {
        if let time = line.time {
            player.seek(to: max(0, time))
        }
        // Choosing a line is choosing where the song is, so the list has no
        // reason to stay detached from it afterwards.
        session.followsPlayback = true
        activeLine = line.id
        session.selectedLine = line.id
        Task { await session.analyze(lineIndex: line.id) }
    }
}

/// Sheet identity wrapper — `Int` isn't `Identifiable`.
private struct LineSelection: Identifiable {
    let index: Int
    var id: Int { index }
}

// MARK: - Row

private struct LyricRow: View {
    let line: LyricLine
    let isActive: Bool
    let showsFurigana: Bool
    let scale: Double
    let translation: String?
    let isLooping: Bool
    let isAnalyzing: Bool

    /// Ruby segmentation walks the tokenizer, so it is computed once per row
    /// and only when furigana is actually on screen.
    private var segments: [RubySegment] {
        Furigana.segments(forLine: line.text)
    }

    /// Scaled from the theme's sizes so the active/inactive contrast survives.
    private var lyricFont: Font {
        .just(
            (isActive ? 26 : 21) * scale,
            weight: isActive ? .semibold : .regular,
            relativeTo: isActive ? .title2 : .title3
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if line.text.isEmpty {
                Text("♪")
                    .font(JustTheme.Font.lyric)
                    .foregroundStyle(JustTheme.Ink.tertiary)
            } else if showsFurigana {
                RubyText(
                    segments: segments,
                    font: lyricFont,
                    rubyFont: .just(10 * scale, weight: .medium, relativeTo: .caption2),
                    color: isActive ? JustTheme.Ink.primary : JustTheme.Ink.secondary,
                    rubyHeight: (13 * scale).scaledForText(.caption2)
                )
            } else {
                Text(line.text)
                    .font(lyricFont)
                    .foregroundStyle(isActive ? JustTheme.Ink.primary : JustTheme.Ink.secondary)
            }

            if isLooping {
                Label("이 줄 반복 중", systemImage: "repeat")
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(JustTheme.Accent.end)
            }

            if isAnalyzing {
                ProgressView().controlSize(.mini)
            } else if let translation, !translation.isEmpty {
                Text(translation)
                    .font(.just(15 * scale, relativeTo: .subheadline))
                    .foregroundStyle(JustTheme.Ink.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.25), value: isActive)
    }
}

// MARK: - Missing lyrics

private struct MissingLyricsView: View {
    @Bindable var session: SongSession
    let message: String

    @State private var artist = ""
    @State private var title = ""
    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: JustTheme.Space.regular) {
            Image(systemName: "text.badge.xmark")
                .font(.system(size: 32))
                .foregroundStyle(JustTheme.Ink.tertiary)

            Text(message)
                .font(JustTheme.Font.body)
                .foregroundStyle(JustTheme.Ink.secondary)
                .multilineTextAlignment(.center)

            // The catalog's artist/title are clean, but LRCLIB may index the
            // same song in a different script or under a release-specific
            // title. Letting the user correct it here is far cheaper than
            // trying to guess every spelling LRCLIB might have used.
            VStack(spacing: JustTheme.Space.tight) {
                TextField("아티스트", text: $artist)
                TextField("곡 제목", text: $title)
            }
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()

            Button {
                isRetrying = true
                Task {
                    await session.fetchLyrics(
                        artistOverride: artist.isEmpty ? nil : artist,
                        titleOverride: title.isEmpty ? nil : title
                    )
                    isRetrying = false
                }
            } label: {
                if isRetrying {
                    ProgressView()
                } else {
                    Text("다시 찾기").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.justPrimary)
            .disabled(isRetrying)
        }
        .justCard()
        .frame(maxWidth: 420)
        .padding(JustTheme.Space.regular)
        .onAppear {
            if artist.isEmpty { artist = session.track.artist }
            if title.isEmpty { title = session.track.title }
        }
    }
}
