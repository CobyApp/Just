import JustCore
import JustDesign
import JustMusic
import SwiftUI

/// The bar above the tab bar while a song is loaded but the player is dismissed.
///
/// Without it, leaving the player to look something up in the word list meant
/// losing the transport entirely — the song kept going with no way to pause it
/// short of reopening the full screen.
struct MiniPlayer: View {
    let track: Track

    @Environment(AppModel.self) private var app
    @State private var artwork = ArtworkLoader()

    var body: some View {
        Button {
            app.expandPlayer()
        } label: {
            HStack(spacing: JustTheme.Space.snug) {
                ArtworkView(image: artwork.image, cornerRadius: 8, seed: track.id)
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(JustTheme.Font.caption.weight(.semibold))
                        .foregroundStyle(JustTheme.Ink.primary)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(JustTheme.Font.caption)
                        .foregroundStyle(JustTheme.Ink.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: JustTheme.Space.tight)

                Button {
                    app.player.togglePlayback()
                } label: {
                    Image(systemName: app.player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(JustTheme.Ink.primary)
                }
                // A styled icon button also keeps this from inheriting the row's
                // tap, which would expand the player instead of toggling
                // playback.
                .buttonStyle(.justIcon)
                .accessibilityLabel(app.player.isPlaying ? "일시정지" : "재생")

                Button {
                    app.stopPlayback()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        // Quieter than play: ending a song is not the main act.
                        .foregroundStyle(JustTheme.Ink.secondary)
                }
                .buttonStyle(.justIcon)
                .accessibilityLabel("재생 종료")
            }
            .padding(.horizontal, JustTheme.Space.snug)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(JustTheme.Ink.hairline, lineWidth: 0.5)
            }
            .overlay(alignment: .bottom) {
                // A hairline of progress, so the bar says where in the song we
                // are without spending height on it.
                GeometryReader { geometry in
                    let fraction = app.player.duration > 0
                        ? app.player.currentTime / app.player.duration
                        : 0
                    JustTheme.Ink.primary.opacity(0.5)
                        .frame(width: geometry.size.width * fraction, height: 1.5)
                }
                .frame(height: 1.5)
                .padding(.horizontal, 8)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, JustTheme.Space.snug)
        .task(id: track.artworkURL) { await artwork.load(track.artworkURL) }
    }
}
