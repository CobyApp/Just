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
    @ObservationIgnored
    private var trimsLetterbox = false

    public init() {}

    /// - Parameter trimmingLetterbox: cut black bars off the edges before
    ///   showing the picture — for artist photos, a few of which were
    ///   uploaded with bars baked into the image.
    public func load(_ url: URL?, trimmingLetterbox: Bool = false) async {
        self.trimsLetterbox = trimmingLetterbox
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

    private func apply(_ original: UIImage, for url: URL) {
        let uiImage = trimsLetterbox ? Letterbox.trimmed(original) : original
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

    /// Filenames are a stable hash of the URL — catalogue artwork URLs
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
                    .transition(.opacity)
            } else {
                placeholder
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.28), value: image == nil)
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

/// Black bars inside a picture, and cutting them off.
enum Letterbox {
    /// The picture without uniform black bands along its edges.
    ///
    /// A row or column counts as bar when its samples are dark and nearly
    /// equal. Bars thicker than a third of the picture are left alone — that
    /// is a dark photo, not a letterbox.
    static func trimmed(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let width = cg.width, height = cg.height
        guard width > 8, height > 8,
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return image }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return image }

        func brightness(_ x: Int, _ y: Int) -> Int {
            let offset = (y * width + x) * 4
            return Int(data[offset]) + Int(data[offset + 1]) + Int(data[offset + 2])
        }
        // A bar is dark and flat: every sample in the line close to the same
        // dark value. Not only pure black — one group's photo has bars of a
        // flat charcoal grey.
        func isBar(_ samples: [Int]) -> Bool {
            guard let high = samples.max(), let low = samples.min() else { return false }
            return high < 200 && high - low < 24
        }
        let columnStep = max(1, width / 40), rowStep = max(1, height / 40)
        func rowIsBar(_ y: Int) -> Bool { isBar(stride(from: 0, to: width, by: columnStep).map { brightness($0, y) }) }
        func columnIsBar(_ x: Int) -> Bool { isBar(stride(from: 0, to: height, by: rowStep).map { brightness(x, $0) }) }

        var top = 0; while top < height / 3, rowIsBar(top) { top += 1 }
        var bottom = 0; while bottom < height / 3, rowIsBar(height - 1 - bottom) { bottom += 1 }
        var left = 0; while left < width / 3, columnIsBar(left) { left += 1 }
        var right = 0; while right < width / 3, columnIsBar(width - 1 - right) { right += 1 }

        // Hitting the limit means a dark picture rather than a bar.
        if top >= height / 3 || bottom >= height / 3 { top = 0; bottom = 0 }
        if left >= width / 3 || right >= width / 3 { left = 0; right = 0 }
        // A few pixels of dark edge is the photo, not a bar.
        guard top + bottom + left + right > 6 else { return image }

        let crop = CGRect(x: left, y: top, width: width - left - right, height: height - top - bottom)
        guard let cropped = cg.cropping(to: crop) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}
