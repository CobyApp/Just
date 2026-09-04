import JustCore
import JustDesign
import SwiftUI

/// A song in a list — the group's songs, 「내 노래」, anywhere songs are rows.
///
/// One component rather than a row per screen, because the two rows had
/// already drifted: one cropped its artwork to a band by squeezing a captioned
/// card tile into 56pt, the other repeated the artist on every line of a list
/// that was all one artist. What a row needs is the art as a square, the title
/// with room to wrap, one quiet line of facts, and a clear way in.
struct SongRow: View {
    let track: Track
    /// Position in the list, when the list has an order worth showing.
    var index: Int? = nil
    /// Study progress 0…1, when the song has been opened before.
    var progress: Double? = nil
    /// What tapping does, in one word.
    var action: String = "열기"

    var body: some View {
        HStack(spacing: JustTheme.Space.snug) {
            if let index {
                Text("\(index)")
                    .font(JustTheme.Font.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(JustTheme.Kawaii.inkSoft)
                    .frame(width: 22, alignment: .trailing)
            }

            RowArtwork(url: track.artworkURL, seed: track.id)

            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(JustTheme.Font.body.weight(.semibold))
                    .foregroundStyle(JustTheme.Kawaii.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    if track.duration > 0 {
                        Text(track.duration.clockString)
                            .font(JustTheme.Font.caption.monospacedDigit())
                            .foregroundStyle(JustTheme.Kawaii.inkSoft)
                    }
                    if let progress, progress > 0 {
                        StudyProgressBar(progress: progress, width: 120)
                    }
                }
            }

            Spacer(minLength: JustTheme.Space.tight)

            Label(action, systemImage: "play.fill")
                .font(JustTheme.Font.caption.weight(.semibold))
                .foregroundStyle(JustTheme.Kawaii.accent)
                .labelStyle(.titleAndIcon)
                .fixedSize()
        }
        .padding(JustTheme.Space.snug)
        .background(JustTheme.Surface.panel, in: .rect(cornerRadius: JustTheme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: JustTheme.Radius.card)
                .strokeBorder(JustTheme.Surface.border, lineWidth: 1)
        }
        .contentShape(.rect)
    }
}

/// A square thumbnail for a list row.
///
/// Not `ArtworkTile`: that is a card with caption space under the art, and
/// squeezed into a row it kept the caption space and cropped the picture to a
/// band.
struct RowArtwork: View {
    let url: URL?
    let seed: String
    var size: CGFloat = 56
    @State private var artwork = ArtworkLoader()

    var body: some View {
        ArtworkView(image: artwork.image, seed: seed)
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: 10))
            .task(id: url) { await artwork.load(url) }
    }
}
