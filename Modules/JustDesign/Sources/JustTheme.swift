import SwiftUI

/// The design system is deliberately small: one ink scale, one accent that
/// comes from the current artwork, and generous type. Everything colourful on
/// screen is the album art — the chrome stays out of the way.
public enum JustTheme {
    public enum Ink {
        public static let primary = Color.white
        public static let secondary = Color.white.opacity(0.62)
        public static let tertiary = Color.white.opacity(0.38)
        public static let hairline = Color.white.opacity(0.12)
    }

    public enum Surface {
        public static let base = Color(red: 0.04, green: 0.04, blue: 0.05)
        public static let raised = Color.white.opacity(0.06)
        public static let sunken = Color.black.opacity(0.28)
    }

    /// The one saturated element in an otherwise monochrome app. Used for
    /// progress and achievement, where a number alone reads as flat.
    public enum Accent {
        public static let start = Color(red: 0.55, green: 0.42, blue: 0.98)
        public static let end = Color(red: 0.96, green: 0.44, blue: 0.72)

        public static var gradient: LinearGradient {
            LinearGradient(
                colors: [start, end],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        public static var angular: AngularGradient {
            AngularGradient(
                colors: [start, end, start],
                center: .center
            )
        }
    }

    public enum Radius {
        public static let card: CGFloat = 20
        public static let chip: CGFloat = 10
        public static let artwork: CGFloat = 14
    }

    public enum Space {
        public static let hairline: CGFloat = 4
        public static let tight: CGFloat = 8
        public static let snug: CGFloat = 12
        public static let regular: CGFloat = 16
        public static let loose: CGFloat = 24
        public static let section: CGFloat = 36
    }

    /// Every entry follows Dynamic Type — see `Font.just`. Computed rather than
    /// stored because `UIFontMetrics` resolves against the *current* text-size
    /// setting, and a `static let` would freeze whatever it was at first use.
    public enum Font {
        /// The lyric line being studied. Large, low contrast between kanji and
        /// kana, generous line height — this is what the eye lives on.
        public static var lyricActive: SwiftUI.Font { .just(26, weight: .semibold, relativeTo: .title2) }
        public static var lyric: SwiftUI.Font { .just(21, relativeTo: .title3) }
        public static var ruby: SwiftUI.Font { .just(10, weight: .medium, relativeTo: .caption2) }
        public static var translation: SwiftUI.Font { .just(15, relativeTo: .subheadline) }
        public static var title: SwiftUI.Font { .just(22, weight: .bold, relativeTo: .title2) }
        public static var sectionTitle: SwiftUI.Font { .just(13, weight: .semibold, relativeTo: .caption1) }
        public static var body: SwiftUI.Font { .just(15, relativeTo: .subheadline) }
        public static var caption: SwiftUI.Font { .just(12, weight: .medium, relativeTo: .caption1) }
        public static var japanese: SwiftUI.Font { .just(19, weight: .medium, relativeTo: .body) }
    }
}

public extension View {
    /// The standard raised container: glass over artwork, never a flat card.
    func justCard(cornerRadius: CGFloat = JustTheme.Radius.card) -> some View {
        padding(JustTheme.Space.regular)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(JustTheme.Ink.hairline, lineWidth: 0.5)
            }
    }

    func justSectionHeader() -> some View {
        font(JustTheme.Font.sectionTitle)
            .foregroundStyle(JustTheme.Ink.tertiary)
            .textCase(.uppercase)
            .kerning(0.8)
    }
}

/// The one filled button in the app.
///
/// The built-in prominent styles derive their label colour from the tint, and
/// this app tints everything white — which renders white-on-white. Owning the
/// style keeps the monochrome palette without fighting that.
public struct JustPrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(JustTheme.Font.body.weight(.semibold))
            .foregroundStyle(JustTheme.Surface.base)
            .padding(.vertical, 12)
            .padding(.horizontal, 22)
            .background(
                JustTheme.Ink.primary.opacity(configuration.isPressed ? 0.72 : 1),
                in: .capsule
            )
            .contentShape(.capsule)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == JustPrimaryButtonStyle {
    static var justPrimary: JustPrimaryButtonStyle { JustPrimaryButtonStyle() }
}

/// The bordered button, for actions that are real but not the main one on the
/// screen — "모두 저장", "중지", "다시 확인".
///
/// These were bare tinted text at caption size, which is the same treatment the
/// app gives passive labels. An outline is the cheapest way to say "this is a
/// control" without competing with the filled button.
public struct JustSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(JustTheme.Font.caption.weight(.semibold))
            .foregroundStyle(JustTheme.Ink.primary)
            .padding(.vertical, 7)
            .padding(.horizontal, 14)
            .background(
                JustTheme.Surface.raised.opacity(configuration.isPressed ? 0.4 : 1),
                in: .capsule
            )
            .overlay {
                Capsule().strokeBorder(JustTheme.Ink.hairline, lineWidth: 0.5)
            }
            .contentShape(.capsule)
    }
}

public extension ButtonStyle where Self == JustSecondaryButtonStyle {
    static var justSecondary: JustSecondaryButtonStyle { JustSecondaryButtonStyle() }
}

/// A small pill used for JLPT levels and parts of speech.
public struct JustChip: View {
    private let text: String
    private let tint: Color

    public init(_ text: String, tint: Color = JustTheme.Ink.secondary) {
        self.text = text
        self.tint = tint
    }

    public var body: some View {
        Text(text)
            .font(JustTheme.Font.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: .rect(cornerRadius: JustTheme.Radius.chip))
    }
}
