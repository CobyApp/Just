import SwiftUI

/// A shimmering placeholder block.
///
/// Used instead of a centred spinner. A spinner replaces the screen with
/// nothing, so the user loses the layout and cannot tell how much is coming;
/// blocks in the shape of the content that is loading answer both, and the
/// arrival of real data becomes a fill rather than a jump.
public struct Skeleton: View {
    private let cornerRadius: CGFloat
    @State private var phase: CGFloat = -1

    public init(cornerRadius: CGFloat = 6) {
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(JustTheme.Surface.raised)
            .overlay {
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [.clear, JustTheme.Ink.hairline, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.6)
                    .offset(x: phase * geometry.size.width * 1.6)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

/// A song row's silhouette: artwork square, title line, subtitle line.
public struct SkeletonTrackRow: View {
    public init() {}

    public var body: some View {
        HStack(spacing: JustTheme.Space.snug) {
            Skeleton(cornerRadius: 8).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 6) {
                Skeleton().frame(width: 160, height: 13)
                Skeleton().frame(width: 110, height: 11)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

/// A browse shelf's silhouette.
public struct SkeletonShelf: View {
    private let tileWidth: CGFloat

    public init(tileWidth: CGFloat = 148) {
        self.tileWidth = tileWidth
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: JustTheme.Space.snug) {
            Skeleton().frame(width: 140, height: 20)
                .padding(.horizontal, JustTheme.Space.regular)
            HStack(alignment: .top, spacing: JustTheme.Space.snug) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: JustTheme.Space.tight) {
                        Skeleton(cornerRadius: JustTheme.Radius.artwork)
                            .frame(width: tileWidth, height: tileWidth)
                        Skeleton().frame(width: tileWidth * 0.8, height: 13)
                        Skeleton().frame(width: tileWidth * 0.55, height: 11)
                    }
                }
            }
            .padding(.horizontal, JustTheme.Space.regular)
        }
        // Not interactive and not meaningful to read aloud.
        .accessibilityHidden(true)
    }
}

/// Lyric-shaped placeholders, with varied widths so the block does not read as
/// a table.
public struct SkeletonLyrics: View {
    private let widths: [CGFloat] = [0.86, 0.62, 0.94, 0.71, 0.8, 0.55]

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: JustTheme.Space.loose) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, fraction in
                GeometryReader { geometry in
                    Skeleton().frame(width: geometry.size.width * fraction, height: 22)
                }
                .frame(height: 22)
            }
        }
        .accessibilityHidden(true)
    }
}
