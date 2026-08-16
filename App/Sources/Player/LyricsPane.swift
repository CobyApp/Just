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
                VStack(spacing: JustTheme.Space.snug) {
                    ProgressView()
                    Text("가사를 찾는 중").font(JustTheme.Font.caption)
                        .foregroundStyle(JustTheme.Ink.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                            study: app.sensei.cached(line.id),
                            isAnalyzing: app.sensei.isAnalyzing(line.id)
                        )
                        .id(line.id)
                        .contentShape(.rect)
                        .onTapGesture { select(line, in: lyrics) }
                    }
                }
                .padding(.vertical, JustTheme.Space.loose)
                // Room to scroll the last line up to a readable position.
                .padding(.bottom, 160)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) { bulkBar }
            .onChange(of: activeLine) { _, index in
                guard let index, session.followsPlayback else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private var bulkBar: some View {
        if let progress = session.bulkProgress {
            HStack(spacing: JustTheme.Space.snug) {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .tint(JustTheme.Ink.primary)
                Text("\(progress.done)/\(progress.total)")
                    .font(JustTheme.Font.caption.monospacedDigit())
                    .foregroundStyle(JustTheme.Ink.secondary)
                Button("중지") { session.cancelBulk() }
                    .font(JustTheme.Font.caption)
            }
            .justCard()
            .padding(.bottom, JustTheme.Space.snug)
        } else if session.lyrics != nil {
            Button {
                session.analyzeAll()
            } label: {
                Label("이 곡 전체 분석", systemImage: "sparkles")
                    .font(JustTheme.Font.body.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.justPrimary)
            .padding(.bottom, JustTheme.Space.snug)
        }
    }

    private func select(_ line: LyricLine, in lyrics: Lyrics) {
        if let time = line.time {
            player.seek(to: max(0, time))
        }
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
    let study: LineStudy?
    let isAnalyzing: Bool

    /// Ruby segmentation walks the tokenizer, so it is computed once per row
    /// and only when furigana is actually on screen.
    private var segments: [RubySegment] {
        Furigana.segments(forLine: line.text)
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
                    font: isActive ? JustTheme.Font.lyricActive : JustTheme.Font.lyric,
                    color: isActive ? JustTheme.Ink.primary : JustTheme.Ink.secondary
                )
            } else {
                Text(line.text)
                    .font(isActive ? JustTheme.Font.lyricActive : JustTheme.Font.lyric)
                    .foregroundStyle(isActive ? JustTheme.Ink.primary : JustTheme.Ink.secondary)
            }

            if isAnalyzing {
                ProgressView().controlSize(.mini)
            } else if let study, !study.translationKo.isEmpty {
                Text(study.translationKo)
                    .font(JustTheme.Font.translation)
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

            // YouTube titles carry a lot of promotional noise, so the parsed
            // artist/title is a guess. Letting the user correct it here is far
            // cheaper than trying to parse every upload convention.
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
