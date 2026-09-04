import JustCore
import SwiftUI

/// A song as a browsable card: art on top, title and artist beneath.
///
/// Used in the horizontal shelves on the browse screen, where the artwork is
/// doing the work of helping the user recognise a record at a glance.
public struct ArtworkTile: View {
    private let title: String
    private let subtitle: String
    private let seed: String
    private let width: CGFloat
    @State private var artwork = ArtworkLoader()
    private let url: URL?

    public init(
        title: String,
        subtitle: String,
        artworkURL: URL?,
        seed: String,
        width: CGFloat = 148
    ) {
        self.title = title
        self.subtitle = subtitle
        self.url = artworkURL
        self.seed = seed
        self.width = width
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: JustTheme.Space.tight) {
            ArtworkView(image: artwork.image, seed: seed)
                .frame(width: width, height: width)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(JustTheme.Font.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2, reservesSpace: true)
                Text(subtitle)
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
        }
        .task(id: url) { await artwork.load(url) }
    }
}

public extension ArtworkTile {
    init(track: Track, width: CGFloat = 148) {
        self.init(
            title: track.title,
            subtitle: track.artist,
            artworkURL: track.artworkURL,
            seed: track.id,
            width: width
        )
    }
}
