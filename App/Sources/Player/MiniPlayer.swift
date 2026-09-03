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
                // Small enough to clear the accessory's rounded ends. At 38pt the
                // artwork's own corners pushed through the container's curve.
                ArtworkView(image: artwork.image, cornerRadius: 6, seed: track.id)
                    .frame(width: 30, height: 30)

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

                Button { app.playPrevious() } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(JustTheme.Ink.primary)
                }
                .buttonStyle(.justIcon)
                .disabled(app.previousTrack == nil)
                .accessibilityLabel("이전 곡")

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

                // Step buttons in place of ✕. Stopping is rare and lives in the
                // player's menu now; moving to the next song of the group is the
                // thing a mini player is actually for.
                Button { app.playNext() } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(JustTheme.Ink.primary)
                }
                .buttonStyle(.justIcon)
                .disabled(app.nextTrack == nil)
                .accessibilityLabel("다음 곡")
            }
            // No surface of its own. `tabViewBottomAccessory` supplies the glass,
            // the shape and the outer insets; drawing a second rounded rectangle
            // inside it put one capsule in another with mismatched corners and a
            // doubled edge, which is what made the bar look badly finished.
            //
            // The inner padding stays. Without it the artwork's corners poke out
            // through the accessory's rounding, which looks worse than the double
            // edge did.
            .padding(.horizontal, JustTheme.Space.regular)
            .padding(.vertical, 2)
            .overlay(alignment: .bottom) {
                // A hairline of progress, so the bar says where in the song we
                // are without spending height on it. Inset to the artwork's edge
                // so it reads as part of the row rather than the container's rim.
                GeometryReader { geometry in
                    let fraction = app.player.duration > 0
                        ? app.player.currentTime / app.player.duration
                        : 0
                    JustTheme.Ink.primary.opacity(0.5)
                        .frame(width: geometry.size.width * fraction, height: 1.5)
                }
                .frame(height: 1.5)
                .padding(.horizontal, JustTheme.Space.snug)
            }
        }
        .buttonStyle(.plain)
        .task(id: track.artworkURL) { await artwork.load(track.artworkURL) }
    }
}
