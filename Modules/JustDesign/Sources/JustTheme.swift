import SwiftUI

/// The design system is deliberately small: one ink scale, one accent that
/// comes from the current artwork, and generous type. Everything colourful on
/// screen is the album art — the chrome stays out of the way.
public enum JustTheme {
    /// The bright half of the app.
    ///
    /// Lists and group cards are cheerful; the player and the lyrics stay dark.
    /// Reading is what this app is mostly doing, and dark is where the furigana
    /// and the translation contrast was tuned — an idol app is still a reading
    /// app once a song is open.
    public enum Kawaii {
        public static let ink = Color(red: 0.24, green: 0.14, blue: 0.28)
        public static let inkSoft = Color(red: 0.45, green: 0.35, blue: 0.48)

        /// A group's own two-tone card.
        public static func gradient(hue: Double) -> LinearGradient {
            LinearGradient(
                colors: [
                    Color(hue: hue, saturation: 0.55, brightness: 0.98),
                    Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1),
                          saturation: 0.72, brightness: 0.86),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    public enum Ink {
        public static let primary = Color.white
        public static let secondary = Color.white.opacity(0.62)
        public static let tertiary = Color.white.opacity(0.38)
        public static let hairline = Color.white.opacity(0.12)
    }

    public enum Surface {
        public static let base = Color(red: 0.04, green: 0.04, blue: 0.05)
        /// The bright ground for lists and group cards.
        public static let kawaii = LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.94, blue: 0.97),
                Color(red: 0.94, green: 0.95, blue: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
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

/// The icon-only control: a transport button, a dismiss, a toggle.
///
/// Guarantees the tap target and answers a press. It deliberately paints **no**
/// surface of its own.
///
/// Every icon control in this app already sits somewhere that frames it — the
/// mini player's material capsule, a sheet, or its own circle whose fill carries
/// state (the furigana toggle, the save button's green). Adding a grey disc
/// inside those made the mini player muddy and gave "종료" the same weight as
/// "재생". What they all actually shared was size: 30–34pt against a 44pt
/// minimum. Whether an icon needs a background is the container's business, not
/// this style's.
public struct JustIconButtonStyle: ButtonStyle {
    /// Apple's minimum comfortable target. Not a design preference.
    public static let minimumTapTarget: CGFloat = 44

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(
                minWidth: Self.minimumTapTarget,
                minHeight: Self.minimumTapTarget
            )
            // The whole target reacts, not just the glyph inside it.
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == JustIconButtonStyle {
    static var justIcon: JustIconButtonStyle { JustIconButtonStyle() }
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


public extension View {
    /// Section heading on the bright screens.
    func kawaiiSectionTitle() -> some View {
        font(.just(20, weight: .bold, relativeTo: .title3))
            .foregroundStyle(JustTheme.Kawaii.ink)
            .padding(.horizontal, JustTheme.Space.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
