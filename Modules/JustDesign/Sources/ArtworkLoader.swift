import SwiftUI
import UIKit

/// Loads album art once and hands back both the image and its palette.
///
/// `AsyncImage` can't do this: the palette needs the decoded bitmap, which
/// `AsyncImage` never exposes. Loading here also means artwork and background
/// colour appear in the same frame instead of the screen flashing grey first.
@MainActor
@Observable
public final class ArtworkLoader {
    public private(set) var image: Image?
    public private(set) var palette: ArtworkPalette = .fallback

    @ObservationIgnored
    private static var cache: [URL: (Image, ArtworkPalette)] = [:]
    @ObservationIgnored
    private var currentURL: URL?

    public init() {}

    public func load(_ url: URL?) async {
        guard let url else {
            image = nil
            palette = .fallback
            currentURL = nil
            return
        }
        guard url != currentURL else { return }
        currentURL = url

        if let cached = Self.cache[url] {
            image = cached.0
            palette = cached.1
            return
        }

        guard
            let (data, _) = try? await URLSession.shared.data(from: url),
            let uiImage = UIImage(data: data)
        else { return }

        // Palette extraction touches a 64-pixel bitmap, so it is cheap enough
        // to stay on the main actor rather than pay for an actor hop.
        let extracted = ArtworkPalette.extract(from: uiImage)
        let rendered = Image(uiImage: uiImage)

        Self.cache[url] = (rendered, extracted)
        guard currentURL == url else { return }
        image = rendered
        palette = extracted
    }
}

/// Album art with a placeholder that matches the app's surface treatment.
public struct ArtworkView: View {
    private let image: Image?
    private let cornerRadius: CGFloat

    public init(image: Image?, cornerRadius: CGFloat = JustTheme.Radius.artwork) {
        self.image = image
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                JustTheme.Surface.raised
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 20))
                            .foregroundStyle(JustTheme.Ink.tertiary)
                    }
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(JustTheme.Ink.hairline, lineWidth: 0.5)
        }
    }
}
