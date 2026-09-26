import SwiftUI

/// The decorations that make the bright screens look like an idol goods shop
/// rather than a settings app: stickers, polka dots, glitter, washi tape and a
/// highlighter pen.
///
/// All of it is chrome. Lyrics, readings and translations never sit on a
/// pattern or under a sparkle — the study text is where contrast matters, and
/// the dark player stays plain for the same reason. Everything decorative is
/// hidden from VoiceOver and stands still when Reduce Motion is on.
public extension JustTheme {
    enum Kitsch {
        /// Candy colours for stickers and glitter. Not for text.
        public static let bubblegum = Color(red: 1.0, green: 0.80, blue: 0.89)
        public static let mint = Color(red: 0.56, green: 0.90, blue: 0.80)
        public static let lemon = Color(red: 1.0, green: 0.90, blue: 0.48)
        public static let sky = Color(red: 0.60, green: 0.80, blue: 1.0)
        /// The hard shadow under stickers and buttons — a deeper pink, so the
        /// offset reads as printed rather than as a soft drop shadow.
        public static let stickerShadow = Color(red: 0.96, green: 0.52, blue: 0.70)

        /// Pink into lavender into sky: the primary button, the progress bar.
        public static let candy = LinearGradient(
            colors: [Kawaii.accent, Color(red: 0.86, green: 0.47, blue: 0.97), sky],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Sticker

public extension View {
    /// A die-cut sticker: a thick white rim and a hard offset shadow.
    ///
    /// - Parameter tint: the colour of the printed shadow.
    func kitschSticker(
        cornerRadius: CGFloat = JustTheme.Radius.card,
        tint: Color = JustTheme.Kitsch.stickerShadow,
        rim: CGFloat = 2.5,
        lift: CGFloat = 4
    ) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(.white, lineWidth: rim)
        }
        .background {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(tint.opacity(0.55))
                .offset(x: lift * 0.6, y: lift)
        }
    }
}

// MARK: - Highlighter

public extension View {
    /// A marker-pen stripe behind the lower half of the text.
    func kitschHighlight(_ color: Color = JustTheme.Kitsch.lemon) -> some View {
        background(alignment: .bottom) {
            Capsule()
                .fill(color.opacity(0.75))
                .frame(height: 9)
                .offset(y: -1)
                .padding(.horizontal, -3)
        }
    }
}

// MARK: - Washi tape

/// A strip of translucent masking tape, stuck on at a slant.
public struct WashiTape: View {
    private let color: Color
    private let angle: Double

    public init(_ color: Color = JustTheme.Kitsch.mint, angle: Double = -4) {
        self.color = color
        self.angle = angle
    }

    public var body: some View {
        Rectangle()
            .fill(color.opacity(0.62))
            .overlay {
                // The tape's own print: thin diagonal stripes.
                Canvas { context, size in
                    var x: CGFloat = -size.height
                    while x < size.width {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: size.height))
                        path.addLine(to: CGPoint(x: x + size.height, y: 0))
                        context.stroke(path, with: .color(.white.opacity(0.35)), lineWidth: 3)
                        x += 9
                    }
                }
            }
            .mask(TornEdges())
            .frame(width: 74, height: 20)
            .rotationEffect(.degrees(angle))
            .accessibilityHidden(true)
    }
}

/// Zig-zag ends, the way tape looks when it is torn off by hand.
private struct TornEdges: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let teeth = 5
        let step = rect.height / CGFloat(teeth)
        path.move(to: CGPoint(x: 3, y: 0))
        path.addLine(to: CGPoint(x: rect.width - 3, y: 0))
        for index in 0..<teeth {
            let y = CGFloat(index) * step
            path.addLine(to: CGPoint(x: rect.width, y: y + step / 2))
            path.addLine(to: CGPoint(x: rect.width - 3, y: y + step))
        }
        path.addLine(to: CGPoint(x: 3, y: rect.height))
        for index in (0..<teeth).reversed() {
            let y = CGFloat(index) * step
            path.addLine(to: CGPoint(x: 0, y: y + step / 2))
            path.addLine(to: CGPoint(x: 3, y: y))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Glitter

/// A four-pointed twinkle — the ✦ that idol goods scatter over everything.
public struct Twinkle: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.22
        var path = Path()
        for index in 0..<8 {
            let angle = Double(index) * .pi / 4 - .pi / 2
            let radius = index.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

/// A few twinkles that pulse gently, for next to a title.
public struct SparkleCluster: View {
    private let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBright = false

    public init(tint: Color = JustTheme.Kawaii.accent) {
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            Twinkle().fill(tint)
                .frame(width: 14, height: 14)
                .offset(x: 0, y: -6)
                .scaleEffect(isBright ? 1 : 0.7)
            Twinkle().fill(JustTheme.Kitsch.lemon)
                .frame(width: 9, height: 9)
                .offset(x: 11, y: 5)
                .scaleEffect(isBright ? 0.7 : 1)
            Image(systemName: "heart.fill")
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(JustTheme.Kitsch.sky)
                .offset(x: -9, y: 7)
        }
        .frame(width: 30, height: 26)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                isBright = true
            }
        }
    }
}

// MARK: - Backdrop

/// Polka dots with glitter and hearts strewn over them.
///
/// Laid out from a fixed seed, so the pattern is the same on every launch and
/// does not reshuffle when the view is rebuilt. Faint on purpose: it has to
/// read as wallpaper behind cards, not as something to look at.
struct KitschWallpaper: View {
    var body: some View {
        Canvas { context, size in
            // Polka dots on a staggered grid.
            let spacing: CGFloat = 26
            var row = 0
            var y: CGFloat = 8
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 8 : 8 + spacing / 2
                while x < size.width {
                    let dot = CGRect(x: x - 2.2, y: y - 2.2, width: 4.4, height: 4.4)
                    context.fill(Path(ellipseIn: dot), with: .color(JustTheme.Kawaii.accent.opacity(0.07)))
                    x += spacing
                }
                y += spacing
                row += 1
            }

            // Glitter and hearts.
            var random = SeededRandom(seed: 0x5EED)
            let colours: [Color] = [
                JustTheme.Kawaii.accent, JustTheme.Kawaii.lavender,
                JustTheme.Kitsch.sky, JustTheme.Kitsch.lemon, JustTheme.Kitsch.mint,
            ]
            let count = Int(size.width * size.height / 9_000)
            for index in 0..<count {
                let point = CGPoint(x: random.next() * size.width, y: random.next() * size.height)
                let colour = colours[index % colours.count].opacity(0.26)
                let side = 6 + random.next() * 9
                let rect = CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
                if index.isMultiple(of: 3) {
                    context.fill(HeartShape().path(in: rect), with: .color(colour))
                } else {
                    context.fill(Twinkle().path(in: rect), with: .color(colour))
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// A heart drawn as a path, so the wallpaper can fill it in a `Canvas`.
public struct HeartShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + h * 0.32),
            control1: CGPoint(x: rect.minX + w * 0.1, y: rect.minY + h * 0.72),
            control2: CGPoint(x: rect.minX, y: rect.minY + h * 0.52)
        )
        path.addArc(
            center: CGPoint(x: rect.minX + w * 0.25, y: rect.minY + h * 0.3),
            radius: w * 0.25, startAngle: .degrees(175), endAngle: .degrees(0), clockwise: false
        )
        path.addArc(
            center: CGPoint(x: rect.minX + w * 0.75, y: rect.minY + h * 0.3),
            radius: w * 0.25, startAngle: .degrees(180), endAngle: .degrees(5), clockwise: false
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.minY + h * 0.52),
            control2: CGPoint(x: rect.maxX - w * 0.1, y: rect.minY + h * 0.72)
        )
        path.closeSubpath()
        return path
    }
}

/// A tiny deterministic generator; `SystemRandomNumberGenerator` would move
/// the glitter on every redraw.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    /// A value in 0..<1.
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(state >> 33) / CGFloat(UInt64(1) << 31)
    }
}

// MARK: - Candy progress

/// A striped candy bar with a star riding its end.
public struct CandyProgressBar: View {
    private let fraction: Double

    public init(value: Double, total: Double) {
        fraction = total > 0 ? min(max(value / total, 0), 1) : 0
    }

    public var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(JustTheme.Kitsch.bubblegum.opacity(0.55))
                Capsule()
                    .fill(JustTheme.Kitsch.candy)
                    .overlay {
                        Canvas { context, size in
                            var x: CGFloat = -size.height
                            while x < size.width {
                                var path = Path()
                                path.move(to: CGPoint(x: x, y: size.height))
                                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                                context.stroke(path, with: .color(.white.opacity(0.28)), lineWidth: 3)
                                x += 10
                            }
                        }
                        .clipShape(.capsule)
                    }
                    .frame(width: max(width * fraction, fraction > 0 ? 10 : 0))
                Twinkle()
                    .fill(JustTheme.Kitsch.lemon)
                    .overlay { Twinkle().stroke(.white, lineWidth: 1.5) }
                    .frame(width: 18, height: 18)
                    .offset(x: max(width * fraction - 9, -2))
            }
        }
        .frame(height: 10)
        .padding(.vertical, 4)
        .animation(.snappy, value: fraction)
        .accessibilityElement()
        .accessibilityValue("\(Int((fraction * 100).rounded()))%")
    }
}
