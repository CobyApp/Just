import SwiftUI
import UIKit

/// Colours pulled from album art, used to tint the whole player screen.
public struct ArtworkPalette: Equatable, Sendable {
    public let colors: [Color]

    public static let fallback = ArtworkPalette(colors: [
        Color(red: 0.10, green: 0.11, blue: 0.18),
        Color(red: 0.18, green: 0.13, blue: 0.26),
        Color(red: 0.08, green: 0.15, blue: 0.22),
        Color(red: 0.14, green: 0.10, blue: 0.14),
    ])

    public init(colors: [Color]) {
        self.colors = colors.isEmpty ? Self.fallback.colors : colors
    }

    /// Four colours, cycled if the artwork yielded fewer, for the mesh corners.
    public func mesh(count: Int = 4) -> [Color] {
        guard !colors.isEmpty else { return Self.fallback.mesh(count: count) }
        return (0..<count).map { colors[$0 % colors.count] }
    }

    /// Extracts dominant colours by downsampling to a tiny bitmap and bucketing
    /// by hue.
    ///
    /// Downsampling first is the whole trick: averaging 64 pixels is instant
    /// and gives a better result than sampling a full-size image, because the
    /// resize already does the averaging in optimised code.
    public static func extract(from image: UIImage, sampleCount: Int = 8) -> ArtworkPalette {
        guard let cgImage = image.cgImage else { return .fallback }

        let side = sampleCount
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .fallback }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        // Hue bucket -> accumulated colour, so near-identical shades merge.
        var buckets: [Int: (h: Double, s: Double, b: Double, count: Int)] = [:]
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[index]) / 255
            let g = Double(pixels[index + 1]) / 255
            let b = Double(pixels[index + 2]) / 255
            let (hue, saturation, brightness) = hsb(r: r, g: g, b: b)

            // Near-black and near-white make a muddy background.
            guard brightness > 0.12, brightness < 0.97 else { continue }

            let bucket = saturation < 0.12 ? -1 : Int(hue * 12)
            let existing = buckets[bucket] ?? (0, 0, 0, 0)
            buckets[bucket] = (
                existing.h + hue,
                existing.s + saturation,
                existing.b + brightness,
                existing.count + 1
            )
        }

        let ranked = buckets.values
            .sorted { $0.count > $1.count }
            .prefix(4)
            .map { bucket -> Color in
                let count = Double(bucket.count)
                return Color(
                    hue: bucket.h / count,
                    // Push toward a deep, desaturated backdrop so white lyrics
                    // stay readable over any album cover.
                    saturation: min(bucket.s / count * 0.85, 0.7),
                    brightness: min(max(bucket.b / count * 0.42, 0.08), 0.34)
                )
            }

        return ArtworkPalette(colors: Array(ranked))
    }

    public static func extract(from data: Data) -> ArtworkPalette {
        guard let image = UIImage(data: data) else { return .fallback }
        return extract(from: image)
    }

    private static func hsb(r: Double, g: Double, b: Double) -> (Double, Double, Double) {
        let maxValue = max(r, g, b)
        let minValue = min(r, g, b)
        let delta = maxValue - minValue

        var hue: Double = 0
        if delta > 0 {
            if maxValue == r {
                hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxValue == g {
                hue = (b - r) / delta + 2
            } else {
                hue = (r - g) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, maxValue == 0 ? 0 : delta / maxValue, maxValue)
    }
}

/// Slowly drifting mesh gradient built from the artwork palette.
public struct ArtworkBackground: View {
    private let palette: ArtworkPalette
    @State private var phase: Double = 0

    public init(palette: ArtworkPalette) {
        self.palette = palette
    }

    public var body: some View {
        let colors = palette.mesh(count: 9)
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5],
                [Float(0.5 + 0.12 * sin(phase)), Float(0.5 + 0.12 * cos(phase))],
                [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0],
            ],
            colors: colors
        )
        .overlay(JustTheme.Surface.base.opacity(0.35))
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                phase = .pi * 2
            }
        }
        .animation(.easeInOut(duration: 0.8), value: palette)
    }
}
