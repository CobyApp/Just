import SwiftUI

/// How the stickers move.
///
/// One vocabulary for the whole bright half of the app, so a card, a row and a
/// save button all answer a finger the same way: a sticker is pressed flat onto
/// its printed shadow, peels back up with a little bounce, arrives on the page
/// with a slap, and glitters when something good happens.
///
/// Every piece stands still under Reduce Motion — decoration is never worth
/// making someone feel sick — and none of it touches the lyrics.

// MARK: - Pressing a sticker

private struct KitschPressedKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// True while the button a sticker belongs to is held down.
    var kitschPressed: Bool {
        get { self[KitschPressedKey.self] }
        set { self[KitschPressedKey.self] = newValue }
    }
}

/// For buttons whose label is a sticker (`kitschSticker`, `justCard`).
///
/// Holding the button pushes the sticker down onto its own shadow — the shadow
/// stays put and the sticker moves over it, which is what makes it read as a
/// thing being pressed rather than a thing shrinking. Released, it springs back
/// with a small overshoot.
public struct KitschPressStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.kitschPressed, configuration.isPressed)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(duration: 0.24, bounce: 0.5), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: configuration.isPressed) { _, pressed in
                pressed
            }
    }
}

public extension ButtonStyle where Self == KitschPressStyle {
    static var kitschPress: KitschPressStyle { KitschPressStyle() }
}

/// The sticker itself: a white rim, a printed shadow, and the press.
struct KitschStickerModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color
    let rim: CGFloat
    let lift: CGFloat

    @Environment(\.kitschPressed) private var isPressed

    func body(content: Content) -> some View {
        // Most of the way down, not all: a sticker pressed completely flat
        // loses its edge and looks like it vanished.
        let sink: CGFloat = isPressed ? 0.8 : 0
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white, lineWidth: rim)
            }
            // A render offset, so the shadow below keeps its place.
            .offset(x: lift * 0.6 * sink, y: lift * sink)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(tint.opacity(0.55))
                    .offset(x: lift * 0.6, y: lift)
            }
            .animation(.spring(duration: 0.24, bounce: 0.5), value: isPressed)
    }
}

// MARK: - Arriving

/// Stickers slapped onto the page one after another.
///
/// Only the first screenful is staggered. Further down a list, the row simply
/// appears: a reader scrolling fast should not wait for a cascade to catch up.
struct KitschEntrance: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown: Bool

    /// Rows past this many are already on the page when they scroll in.
    static let staggered = 12

    init(index: Int) {
        self.index = index
        _isShown = State(initialValue: index >= Self.staggered)
    }

    func body(content: Content) -> some View {
        let hidden = !isShown && !reduceMotion
        content
            .opacity(isShown ? 1 : 0)
            .offset(y: hidden ? 18 : 0)
            .scaleEffect(hidden ? 0.92 : 1, anchor: .bottom)
            // Alternate a hair left and right, the way stickers never go on
            // quite straight.
            .rotationEffect(.degrees(hidden ? (index.isMultiple(of: 2) ? -2 : 2) : 0))
            .onAppear {
                guard !isShown else { return }
                let animation: Animation = reduceMotion
                    ? .easeOut(duration: 0.2)
                    : .spring(duration: 0.55, bounce: 0.42).delay(Double(index) * 0.05)
                withAnimation(animation) { isShown = true }
            }
    }
}

public extension View {
    /// Pops the view in on first appearance, `index` steps after the first.
    func kitschEntrance(index: Int) -> some View {
        modifier(KitschEntrance(index: index))
    }
}

// MARK: - Holographic sheen

/// A band of light that sweeps across a card now and then, like the foil on a
/// trading card catching the light.
struct HoloSheen: ViewModifier {
    let cornerRadius: CGFloat
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geometry in
                        let width = geometry.size.width
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.5), .white.opacity(0.15), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: width * 0.5, height: geometry.size.height * 2)
                        .rotationEffect(.degrees(22))
                        .position(x: width * 0.5 + phase * width * 1.1, y: geometry.size.height / 2)
                    }
                    .clipShape(.rect(cornerRadius: cornerRadius))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .task {
                guard !reduceMotion else { return }
                try? await Task.sleep(for: .seconds(0.6 + delay))
                while !Task.isCancelled {
                    var reset = Transaction()
                    reset.disablesAnimations = true
                    withTransaction(reset) { phase = -1 }
                    withAnimation(.easeInOut(duration: 1.2)) { phase = 1 }
                    // Long enough apart that the sweep stays a surprise.
                    try? await Task.sleep(for: .seconds(6.5 + delay))
                }
            }
    }
}

public extension View {
    /// A foil sheen that passes over the view every few seconds.
    func holoSheen(cornerRadius: CGFloat = JustTheme.Radius.card, delay: Double = 0) -> some View {
        modifier(HoloSheen(cornerRadius: cornerRadius, delay: delay))
    }
}

// MARK: - Glitter burst

/// Twinkles and hearts thrown out from the centre and falling away — for a
/// word saved, an answer right, a review done.
public struct SparkleBurst: View {
    private let trigger: Int
    private let count: Int
    private let spread: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bursts: [Int] = []

    /// - Parameters:
    ///   - trigger: a burst fires whenever this changes.
    ///   - count: pieces per burst.
    ///   - spread: how far the pieces fly, in points.
    public init(trigger: Int, count: Int = 12, spread: CGFloat = 70) {
        self.trigger = trigger
        self.count = count
        self.spread = spread
    }

    public var body: some View {
        ZStack {
            ForEach(bursts, id: \.self) { seed in
                BurstPieces(seed: UInt64(truncatingIfNeeded: seed), count: count, spread: spread)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) {
            guard !reduceMotion else { return }
            let seed = Int.random(in: 1...Int.max)
            bursts.append(seed)
            Task {
                try? await Task.sleep(for: .seconds(1.1))
                bursts.removeAll { $0 == seed }
            }
        }
    }
}

public extension View {
    /// Throws glitter out of the view whenever `trigger` changes.
    func sparkleBurst(trigger: Int, count: Int = 12, spread: CGFloat = 70) -> some View {
        overlay { SparkleBurst(trigger: trigger, count: count, spread: spread) }
    }
}

private struct BurstPieces: View {
    let seed: UInt64
    let count: Int
    let spread: CGFloat
    @State private var progress: Double = 0

    var body: some View {
        BurstFrame(progress: progress, pieces: Self.pieces(seed: seed, count: count, spread: spread))
            .onAppear {
                withAnimation(.easeOut(duration: 0.95)) { progress = 1 }
            }
    }

    struct Piece {
        let angle: Double
        let distance: CGFloat
        let size: CGFloat
        let spin: Double
        let colour: Color
        let isHeart: Bool
    }

    static func pieces(seed: UInt64, count: Int, spread: CGFloat) -> [Piece] {
        var random = SeededRandom(seed: seed)
        let colours: [Color] = [
            JustTheme.Kawaii.accent, JustTheme.Kitsch.lemon, JustTheme.Kitsch.sky,
            JustTheme.Kawaii.lavender, JustTheme.Kitsch.mint,
        ]
        return (0..<count).map { index in
            // Spread evenly round the circle, then jittered, so no burst has
            // a gap on one side.
            let base = Double(index) / Double(count) * .pi * 2
            return Piece(
                angle: base + Double(random.next() - 0.5) * 0.6,
                distance: spread * (0.55 + random.next() * 0.6),
                size: 7 + random.next() * 8,
                spin: Double(random.next() - 0.5) * 540,
                colour: colours[index % colours.count],
                isHeart: index.isMultiple(of: 3)
            )
        }
    }
}

/// One frame of a burst. Animatable, so the arc — out, then dropping under a
/// little gravity — is computed per frame rather than tweened as a line.
private struct BurstFrame: View, @MainActor Animatable {
    var progress: Double
    let pieces: [BurstPieces.Piece]

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        ZStack {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                let travel = CGFloat(progress)
                let x = CGFloat(cos(piece.angle)) * piece.distance * travel
                let y = CGFloat(sin(piece.angle)) * piece.distance * travel + 26 * travel * travel
                Group {
                    if piece.isHeart {
                        HeartShape().fill(piece.colour)
                    } else {
                        Twinkle().fill(piece.colour)
                    }
                }
                .frame(width: piece.size, height: piece.size)
                .rotationEffect(.degrees(piece.spin * progress))
                .scaleEffect(progress < 0.15 ? progress / 0.15 : 1 - (progress - 0.15) * 0.6)
                .offset(x: x, y: y)
                .opacity(progress < 0.6 ? 1 : (1 - progress) / 0.4)
            }
        }
    }
}

// MARK: - Shake

/// Side to side, the way a head shakes "no".
struct KitschShake: GeometryEffect {
    var travel: CGFloat
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        // Three shakes that die down over the run.
        let damping = 1 - (animatableData - animatableData.rounded(.down))
        let x = travel * damping * sin(animatableData * .pi * 6)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}

private struct KitschShakeModifier: ViewModifier {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .modifier(KitschShake(travel: reduceMotion ? 0 : 9, animatableData: CGFloat(trigger)))
            .animation(.linear(duration: 0.45), value: trigger)
    }
}

public extension View {
    /// Shakes the view whenever `trigger` changes.
    func kitschShake(trigger: Int) -> some View {
        modifier(KitschShakeModifier(trigger: trigger))
    }
}

// MARK: - Floating

private struct KitschFloat: ViewModifier {
    let amplitude: CGFloat
    let duration: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isUp = false

    func body(content: Content) -> some View {
        content
            .offset(y: isUp ? -amplitude : amplitude * 0.3)
            .rotationEffect(.degrees(isUp ? 2 : -2))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                    isUp = true
                }
            }
    }
}

public extension View {
    /// Bobs gently, as if hung on a thread — for the icon of an empty screen.
    func kitschFloat(amplitude: CGFloat = 5, duration: Double = 1.8) -> some View {
        modifier(KitschFloat(amplitude: amplitude, duration: duration))
    }
}

// MARK: - Flicking a card away

private struct StickerTilt: ViewModifier {
    let angle: Double
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle), anchor: .bottom)
            .scaleEffect(scale)
            .offset(x: x, y: y)
    }
}

public extension AnyTransition {
    /// A card that is finished is flicked off to the left with a twist; the
    /// next is slapped on from just below.
    static var stickerFlick: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: StickerTilt(angle: 3, x: 0, y: 28, scale: 0.9),
                identity: StickerTilt(angle: 0, x: 0, y: 0, scale: 1)
            ).combined(with: .opacity),
            removal: .modifier(
                active: StickerTilt(angle: -14, x: -420, y: 40, scale: 0.95),
                identity: StickerTilt(angle: 0, x: 0, y: 0, scale: 1)
            ).combined(with: .opacity)
        )
    }
}

// MARK: - Waiting

/// Three notes hopping in turn — the app's spinner, for waits that belong to
/// a song.
public struct BouncingNotes: View {
    private let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(tint: Color = JustTheme.Kawaii.accent) {
        self.tint = tint
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    // Each note half a beat behind the one before.
                    let beat = (time * 2.4 - Double(index) * 0.33).truncatingRemainder(dividingBy: 1)
                    let hop = reduceMotion ? 0 : max(0, sin(beat * .pi)) * 9
                    Image(systemName: index == 1 ? "music.note" : "music.quarternote.3")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(index == 1 ? JustTheme.Kitsch.lemon : tint)
                        .offset(y: -hop)
                        .rotationEffect(.degrees(reduceMotion ? 0 : (hop / 9) * (index.isMultiple(of: 2) ? -12 : 12)))
                }
            }
        }
        .frame(height: 30)
        .accessibilityHidden(true)
    }
}
