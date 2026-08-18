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
                            stage
                            LyricsPane(session: session, player: app.player)
                        }
                        .padding(.horizontal, JustTheme.Space.regular)
                    }
                }
                .safeAreaInset(edge: .top) { header(session: session) }
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .task {
            let session = SongSession(track: track, context: context, sensei: app.sensei)
            self.session = session
            async let playback: Void = app.player.load(track)
            await session.start()
            await playback
        }
        .task(id: track.artworkURL) { await artwork.load(track.artworkURL) }
        .sheet(isPresented: $showsAlbum) { AlbumSheet(track: track) }
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
            Button {
                session.showsFurigana.toggle()
            } label: {
                Label(
                    "후리가나",
                    systemImage: session.showsFurigana ? "textformat.size.ja" : "textformat.size.ja.smaller"
                )
                .labelStyle(.iconOnly)
                .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.glass)
            .tint(session.showsFurigana ? JustTheme.Ink.primary : JustTheme.Ink.tertiary)

            Menu {
                Button {
                    session.analyzeAll()
                } label: {
                    Label("이 곡 전체 분석", systemImage: "sparkles")
                }
                .disabled(session.lyrics == nil || session.isBulkAnalyzing)

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
            ArtworkView(
                image: artwork.image,
                cornerRadius: JustTheme.Radius.card,
                seed: track.id
            )
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: sizeClass == .regular ? .infinity : 260)
                .shadow(color: .black.opacity(0.4), radius: 24, y: 10)

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
                        HStack(spacing: 3) {
                            Text(album)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .font(JustTheme.Font.caption)
                        .foregroundStyle(JustTheme.Ink.tertiary)
                        .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)

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
