import RingRingCore
import RingRingDesign
import SwiftUI

/// The brief wait between choosing a song and hearing it — just the lyric
/// lookup now. The quick reading fills in behind the words once the player is
/// open, so there is no analysis to wait through here.
struct PreparingView: View {
    let track: Track
    let artwork: Image?
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: JustTheme.Space.loose) {
            Spacer(minLength: 0)

            ArtworkView(image: artwork, cornerRadius: JustTheme.Radius.card, seed: track.id)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 220)
                .shadow(color: .black.opacity(0.4), radius: 24, y: 10)

            VStack(spacing: 4) {
                Text(track.title)
                    .font(JustTheme.Font.title)
                    .foregroundStyle(JustTheme.Ink.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(track.artist)
                    .font(JustTheme.Font.body)
                    .foregroundStyle(JustTheme.Ink.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }

            VStack(spacing: JustTheme.Space.tight) {
                BouncingNotes()
                Text("가사를 찾는 중")
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(JustTheme.Ink.tertiary)
            }

            Spacer(minLength: 0)

            Button("중단", action: onCancel)
                .buttonStyle(.justSecondary)
        }
        .padding(JustTheme.Space.section)
        .frame(maxWidth: 420)
    }
}
