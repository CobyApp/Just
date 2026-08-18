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
    private static var memory: [URL: (Image, ArtworkPalette)] = [:]
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

        if let cached = Self.memory[url] {
            image = cached.0
            palette = cached.1
            return
        }

        // Disk before network: artwork is immutable for a given URL, so a
        // second launch — or a flight with no signal — should not have to
        // fetch it again.
        if let uiImage = ArtworkDiskCache.shared.image(for: url) {
            apply(uiImage, for: url)
            return
        }

        guard
            let (data, _) = try? await URLSession.shared.data(from: url),
            let uiImage = UIImage(data: data)
        else { return }

        ArtworkDiskCache.shared.store(data, for: url)
        apply(uiImage, for: url)
    }

    private func apply(_ uiImage: UIImage, for url: URL) {
        // Palette extraction touches a 64-pixel bitmap, so it is cheap enough
        // to stay on the main actor rather than pay for an actor hop.
        let extracted = ArtworkPalette.extract(from: uiImage)
        let rendered = Image(uiImage: uiImage)

        Self.memory[url] = (rendered, extracted)
        guard currentURL == url else { return }
        image = rendered
        palette = extracted
    }
}

/// On-disk store for album art.
///
/// Lives in Caches, so the system may reclaim it under storage pressure — that
/// is the correct contract for data that can always be re-fetched, and it keeps
/// artwork out of the user's iCloud backup.
final class ArtworkDiskCache: @unchecked Sendable {
    static let shared = ArtworkDiskCache()

    private let directory: URL
    private let queue = DispatchQueue(label: "just.artwork.cache")

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func image(for url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: path(for: url)) else { return nil }
        return UIImage(data: data)
    }

    func store(_ data: Data, for url: URL) {
        let destination = path(for: url)
        queue.async {
            try? data.write(to: destination, options: .atomic)
        }
    }

    /// Filenames are a stable hash of the URL — Apple Music artwork URLs
    /// contain slashes and query strings that cannot be a path component.
    private func path(for url: URL) -> URL {
        var hash: UInt64 = 5381
        for byte in url.absoluteString.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return directory.appendingPathComponent(String(hash, radix: 36))
    }
}

/// Album art, with a placeholder that stands in for it rather than admitting
/// something is missing.
public struct ArtworkView: View {
    private let image: Image?
    private let cornerRadius: CGFloat
    private let seed: String

    /// - Parameter seed: identifies the song, so the placeholder colour is
    ///   stable for a given track instead of every empty slot looking alike.
    public init(
        image: Image?,
        cornerRadius: CGFloat = JustTheme.Radius.artwork,
        seed: String = ""
    ) {
        self.image = image
        self.cornerRadius = cornerRadius
        self.seed = seed
    }

    public var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(JustTheme.Ink.hairline, lineWidth: 0.5)
        }
    }

    /// A tinted gradient rather than a grey box. Artwork is missing often
    /// enough — offline, debug songs, a catalog entry without a cover — that a
    /// uniform grey placeholder makes a whole shelf look broken.
    private var placeholder: some View {
        let hue = Self.hue(for: seed)
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.42, brightness: 0.32),
                Color(hue: (hue + 0.09).truncatingRemainder(dividingBy: 1),
                      saturation: 0.5, brightness: 0.18),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "music.note")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    /// Stable hash — `hashValue` is seeded per process, so the same song would
    /// change colour between launches.
    private static func hue(for seed: String) -> Double {
        guard !seed.isEmpty else { return 0.72 }
        var hash: UInt64 = 5381
        for byte in seed.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return Double(hash % 360) / 360
    }
}
