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
    @State private var showsWords = false
    @State private var showsSyncOffset = false
    @State private var savedBanner: String?

    var body: some View {
        ZStack {
            ArtworkBackground(palette: artwork.palette)

            if let session, session.phase == .ready {
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
                PreparingView(
                    track: track,
                    artwork: artwork.image,
                    phase: session?.phase ?? .loadingLyrics,
                    onCancel: { app.closePlayer() },
                    onSkip: (session?.canSkipWaiting ?? false)
                        ? { session?.skipWaiting() }
                        : nil,
                    onUseQuick: (session?.canUseQuickAnalysis ?? false)
                        ? { session?.useQuickAnalysis() }
                        : nil,
                    onChoose: { depth, remember in session?.choose(depth, remember: remember) }
                )
            }
        }
        // Keyed on the track: `fullScreenCover(item:)` swaps the item in place
        // rather than dismissing and re-presenting, so picking another song
        // from the album sheet used to leave this screen showing a new title
        // over the old song's session — and never loading the new song at all.
        .task(id: track.id) {
            // The outgoing session flushes here, while the cache is still its
            // own, so its analyses are saved before the new song claims it.
            session?.cancelBulk()

            let session = SongSession(
                track: track,
                context: context,
                sensei: app.sensei,
                autoAnalysis: app.autoAnalysis.allowsAutoRun
            )
            self.session = session
            await session.prepare()

            // Backing out during preparation must leave no trace, so the song
            // is not adopted as "now playing" until it is about to be heard.
            guard !Task.isCancelled, session.phase == .ready else { return }
            app.confirmPlaying(track)

            // Only autoplays when this is a different song. Reopening a paused
            // one from the mini player should not start it again.
            await app.player.load(track, autoplay: app.player.trackID != track.id)
        }
        .task(id: track.artworkURL) { await artwork.load(track.artworkURL) }
        .sheet(isPresented: $showsSyncOffset) {
            if let session {
                SyncOffsetSheet(session: session, player: app.player)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showsWords) {
            if let song = session?.song {
                SongWordsSheet(song: song)
            }
        }
        // Leaving the player stops the model. Progress is already written to
        // the song record, so reopening resumes where this left off rather than
        // grinding away invisibly after the user has moved on.
        .onDisappear { session?.cancelBulk() }
        .overlay(alignment: .top) {
            if let savedBanner {
                Text(savedBanner)
                    .font(JustTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(JustTheme.Ink.primary)
                    .padding(.horizontal, JustTheme.Space.snug)
                    .padding(.vertical, JustTheme.Space.tight)
                    .background(.ultraThinMaterial, in: .capsule)
                    .padding(.top, JustTheme.Space.section * 2)
                    .transition(.opacity)
                    // Bulk saving gives no visible result on this screen — the
                    // words land in another tab — so it has to say so itself.
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { self.savedBanner = nil }
                    }
            }
        }
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
            .accessibilityLabel("플레이어 닫기")

            Spacer()

            // Furigana stays a one-tap control: it is toggled constantly while
            // reading. Everything else is once-per-song and belongs in a menu.
            // `textformat.size.ja.smaller` does not exist in SF Symbols, so the
            // off state used to render an empty button. One real symbol, with
            // the state carried by the button style rather than the glyph.
            //
            // The same system style as its three neighbours, so the row has one
            // set of metrics. A hand-rolled circle is what made the header
            // uneven: sized to the 44pt rule it came out smaller than the glass
            // buttons, and sizing those to match only made them bigger, because
            // the style adds padding of its own around whatever it is handed.
            furiganaToggle(session: session)

            // Promoted out of the menu: it is used constantly while reading, and
            // its only other route was tapping the artwork — a gesture nothing
            // announces.
            Button {
                withAnimation(.snappy) { session.isLyricsFullscreen.toggle() }
            } label: {
                Image(
                    systemName: session.isLyricsFullscreen
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right"
                )
                .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.glass)
            .accessibilityLabel(session.isLyricsFullscreen ? "플레이어 보기" : "가사 전체화면")

            Menu {
                Button {
                    session.analyzeAll()
                } label: {
                    Label("남은 줄 분석", systemImage: "sparkles")
                }
                .disabled(session.lyrics == nil || session.isBulkAnalyzing)

                // Withheld while a preview is playing: there is no song clock
                // to line the sheet up against, so nothing could be adjusted.
                if session.lyrics?.isSynced == true, app.player.position.followsLyrics {
                    Button { showsSyncOffset = true } label: {
                        Label(
                            session.lyricsOffset == 0
                                ? "가사 싱크 조절"
                                : "가사 싱크 \(SyncOffsetSheet.label(for: session.lyricsOffset))",
                            systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right"
                        )
                    }
                }

                Picker("가사 크기", selection: Binding(
                    get: { session.textSize },
                    set: { session.textSize = $0 }
                )) {
                    ForEach(LyricTextSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.menu)

                if session.unsavedWordCount > 0 {
                    Button {
                        let added = session.saveAllWords()
                        savedBanner = "\(added)개 담았습니다"
                        Haptics.correct()
                    } label: {
                        Label(
                            "단어 \(session.unsavedWordCount)개 모두 담기",
                            systemImage: "square.and.arrow.down"
                        )
                    }
                }

                Button(role: .destructive) {
                    app.stopPlayback()
                } label: {
                    Label("재생 종료", systemImage: "stop.fill")
                }

                if let song = session.song, !song.occurrences.isEmpty {
                    Button { showsWords = true } label: {
                        Label("이 곡의 단어", systemImage: "character.book.closed")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.glass)
            .accessibilityLabel("더 보기")
        }
        .padding(.horizontal, JustTheme.Space.regular)
        .padding(.bottom, JustTheme.Space.tight)
    }

    /// The prominent variant is how the system says "on".
    @ViewBuilder
    private func furiganaToggle(session: SongSession) -> some View {
        let action = {
            session.showsFurigana.toggle()
            Haptics.tick()
        }
        let symbol = Image(systemName: "textformat.size.ja")
            .font(.system(size: 15, weight: .semibold))

        if session.showsFurigana {
            // The prominent style takes its label colour from the tint, and this
            // app tints everything white — which is white on white. The glyph is
            // told to be dark instead, the same trick JustPrimaryButtonStyle uses.
            Button(action: action) {
                symbol.foregroundStyle(JustTheme.Surface.base)
            }
                .buttonStyle(.glassProminent)
                .accessibilityLabel("후리가나")
                .accessibilityValue("켜짐")
        } else {
            Button(action: action) { symbol }
                .buttonStyle(.glass)
                .accessibilityLabel("후리가나")
                .accessibilityValue("꺼짐")
        }
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
                    // Was a button into an album sheet. The group screen lists
                    // the songs now, so this is just the album's name.
                    Text(album)
                        .font(JustTheme.Font.caption)
                        .foregroundStyle(JustTheme.Ink.tertiary)
                        .lineLimit(1)
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
                // 56pt targets on every control, not only the play button. The
                // skip buttons were a 20pt glyph with nothing around it, and a
                // finger aimed at one landed on the slider or nothing.
                Button { player.skip(by: -5) } label: {
                    Image(systemName: "gobackward.5").font(.system(size: 24))
                        .frame(width: 56, height: 56)
                        .contentShape(.rect)
                }
                Button { player.togglePlayback() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 32))
                        .frame(width: 72, height: 72)
                        .contentShape(.rect)
                }
                Button { player.skip(by: 5) } label: {
                    Image(systemName: "goforward.5").font(.system(size: 24))
                        .frame(width: 56, height: 56)
                        .contentShape(.rect)
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
            }
            .buttonStyle(.justIcon)
            .accessibilityLabel(player.isPlaying ? "일시정지" : "재생")

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
