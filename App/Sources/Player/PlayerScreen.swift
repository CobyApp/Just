import JustCore
import JustDesign
import JustMusic
import SwiftData
import SwiftUI

struct PlayerScreen: View {
    let track: Track

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var session: SongSession?
    @State private var artwork = ArtworkLoader()
    @State private var showsAlbum = false
    @State private var showsWords = false

    var body: some View {
        ZStack {
            ArtworkBackground(palette: artwork.palette)

            if let session {
                Group {
                    if sizeClass == .regular {
                        // iPad: artwork and transport sit beside the lyrics so
                        // the lyric column keeps a comfortable measure.
                        HStack(alignment: .top, spacing: JustTheme.Space.loose) {
                            // Centred vertically: the artwork column is much
                            // shorter than a full lyric sheet, and pinning it
                            // to the top leaves a conspicuous void beneath.
                            VStack {
                                Spacer(minLength: 0)
                                stage
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: 420)
                            LyricsPane(session: session, player: app.player)
                        }
                        .padding(.horizontal, JustTheme.Space.loose)
                    } else {
                        VStack(spacing: 0) {
                            if !session.isLyricsFullscreen {
                                stage
                            }
                            LyricsPane(session: session, player: app.player)
                        }
                        .padding(.horizontal, JustTheme.Space.regular)
                        .safeAreaInset(edge: .bottom) {
                            if session.isLyricsFullscreen {
                                CompactTransport(player: app.player)
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .top) { header(session: session) }
            } else {
                VStack(spacing: JustTheme.Space.regular) {
                    Skeleton(cornerRadius: JustTheme.Radius.card)
                        .frame(width: 260, height: 260)
                    Skeleton().frame(width: 160, height: 22)
                    Skeleton().frame(width: 110, height: 15)
                    Spacer()
                }
                .padding(.top, JustTheme.Space.section)
            }
        }
        .task {
            let session = SongSession(
                track: track,
                context: context,
                sensei: app.sensei,
                autoAnalysis: app.autoAnalysis.allowsAutoRun
            )
            self.session = session
            async let playback: Void = app.player.load(track)
            await session.start()
            await playback
        }
        .task(id: track.artworkURL) { await artwork.load(track.artworkURL) }
        .sheet(isPresented: $showsAlbum) { AlbumSheet(track: track) }
        .sheet(isPresented: $showsWords) {
            if let song = session?.song {
                SongWordsSheet(song: song)
            }
        }
        // Leaving the player stops the model. Progress is already written to
        // the song record, so reopening resumes where this left off rather than
        // grinding away invisibly after the user has moved on.
        .onDisappear { session?.cancelBulk() }
    }

    // MARK: - Header

    private func header(session: SongSession) -> some View {
        HStack(spacing: JustTheme.Space.snug) {
            Button {
                app.closePlayer()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.glass)

            Spacer()

            // Furigana stays a one-tap control: it is toggled constantly while
            // reading. Everything else is once-per-song and belongs in a menu.
            // `textformat.size.ja.smaller` does not exist in SF Symbols, so the
            // off state used to render an empty button. One real symbol now,
            // with the state shown by fill rather than by swapping the glyph.
            Button {
                session.showsFurigana.toggle()
                Haptics.tick()
            } label: {
                Image(systemName: "textformat.size.ja")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        session.showsFurigana ? JustTheme.Surface.base : JustTheme.Ink.primary
                    )
                    .frame(width: 34, height: 34)
                    .background(
                        session.showsFurigana ? AnyShapeStyle(JustTheme.Accent.gradient)
                            : AnyShapeStyle(JustTheme.Surface.raised),
                        in: .circle
                    )
                    .overlay {
                        Circle().strokeBorder(JustTheme.Ink.hairline, lineWidth: 0.5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("후리가나")
            .accessibilityValue(session.showsFurigana ? "켜짐" : "꺼짐")

            Menu {
                Button {
                    withAnimation(.snappy) { session.isLyricsFullscreen.toggle() }
                } label: {
                    Label(
                        session.isLyricsFullscreen ? "플레이어 보기" : "가사 전체화면",
                        systemImage: session.isLyricsFullscreen
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right"
                    )
                }

                Button {
                    session.analyzeAll()
                } label: {
                    Label("남은 줄 분석", systemImage: "sparkles")
                }
                .disabled(session.lyrics == nil || session.isBulkAnalyzing)

                Picker("가사 크기", selection: Binding(
                    get: { session.textSize },
                    set: { session.textSize = $0 }
                )) {
                    ForEach(LyricTextSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.menu)

                if let song = session.song, !song.occurrences.isEmpty {
                    Button { showsWords = true } label: {
                        Label("이 곡의 단어", systemImage: "character.book.closed")
                    }
                }

                if track.album != nil {
                    Button { showsAlbum = true } label: {
                        Label("앨범 보기", systemImage: "square.stack")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, JustTheme.Space.regular)
        .padding(.bottom, JustTheme.Space.tight)
    }

    // MARK: - Artwork + transport

    private var stage: some View {
        VStack(spacing: JustTheme.Space.regular) {
            Button {
                withAnimation(.snappy) { session?.isLyricsFullscreen = true }
                Haptics.tick()
            } label: {
                ArtworkView(
                    image: artwork.image,
                    cornerRadius: JustTheme.Radius.card,
                    seed: track.id
                )
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: sizeClass == .regular ? .infinity : 260)
                .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("가사 전체화면")

            VStack(spacing: 2) {
                Text(track.title)
                    .font(JustTheme.Font.title)
                    .foregroundStyle(JustTheme.Ink.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(track.artist)
                    .font(JustTheme.Font.body)
                    .foregroundStyle(JustTheme.Ink.secondary)
                    .lineLimit(1)
                if let album = track.album, album != track.title {
                    Button { showsAlbum = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.stack")
                                .font(.system(size: 10, weight: .semibold))
                            Text(album).lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .font(JustTheme.Font.caption)
                        .foregroundStyle(JustTheme.Ink.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(JustTheme.Surface.raised, in: .capsule)
                        .overlay {
                            Capsule().strokeBorder(JustTheme.Ink.hairline, lineWidth: 0.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)

            if let difficulty = session?.song?.difficulty, !difficulty.isEmpty {
                DifficultyBar(difficulty: difficulty)
                    .frame(maxWidth: 260)
            }

            TransportControls(player: app.player)
        }
    }
}

// MARK: - Transport

private struct TransportControls: View {
    @Bindable var player: MusicPlayerController
    @State private var scrubbing: Double?

    var body: some View {
        VStack(spacing: JustTheme.Space.tight) {
            Slider(
                value: Binding(
                    get: { scrubbing ?? player.currentTime },
                    set: { scrubbing = $0 }
                ),
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    guard !editing, let target = scrubbing else { return }
                    player.seek(to: target)
                    scrubbing = nil
                }
            )
            .tint(JustTheme.Ink.primary)

            HStack {
                Text((scrubbing ?? player.currentTime).clockString)
                // Says why the track is 30 seconds long instead of leaving the
                // user to wonder whether playback broke.
                if player.isPreview {
                    Spacer()
                    Text("미리듣기")
                        .foregroundStyle(JustTheme.Ink.secondary)
                }
                Spacer()
                Text(player.duration.clockString)
            }
            .font(JustTheme.Font.caption.monospacedDigit())
            .foregroundStyle(JustTheme.Ink.tertiary)

            HStack(spacing: JustTheme.Space.section) {
                Button { player.skip(by: -5) } label: {
                    Image(systemName: "gobackward.5").font(.system(size: 20))
                }
                Button { player.togglePlayback() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30))
                        .frame(width: 56, height: 56)
                }
                Button { player.skip(by: 5) } label: {
                    Image(systemName: "goforward.5").font(.system(size: 20))
                }
            }
            .foregroundStyle(JustTheme.Ink.primary)
            .padding(.top, JustTheme.Space.hairline)

            if case .failed(let message) = player.status {
                Text(message)
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    // A truncated error tells the user nothing; let it wrap.
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The transport in fullscreen lyrics: position, one control, nothing else.
///
/// Kept separate from `TransportControls` rather than parameterised, because the
/// two have different jobs — that one is the focus of the player screen, this one
/// has to stay out of the way of the text it sits under.
private struct CompactTransport: View {
    @Bindable var player: MusicPlayerController

    var body: some View {
        HStack(spacing: JustTheme.Space.regular) {
            Button { player.togglePlayback() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(JustTheme.Ink.primary)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)

            ProgressView(
                value: min(player.currentTime, max(player.duration, 1)),
                total: max(player.duration, 1)
            )
            .tint(JustTheme.Ink.primary)

            Text(player.currentTime.clockString)
                .font(JustTheme.Font.caption.monospacedDigit())
                .foregroundStyle(JustTheme.Ink.secondary)
        }
        .padding(.horizontal, JustTheme.Space.regular)
        .padding(.vertical, JustTheme.Space.tight)
        .background(.ultraThinMaterial, in: .capsule)
        .overlay { Capsule().strokeBorder(JustTheme.Ink.hairline, lineWidth: 0.5) }
        .padding(.horizontal, JustTheme.Space.regular)
        .padding(.bottom, JustTheme.Space.tight)
    }
}
