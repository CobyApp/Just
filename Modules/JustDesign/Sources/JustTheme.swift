import SwiftUI
import UIKit

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
        public static let ink = Color(red: 0.22, green: 0.12, blue: 0.27)
        public static let inkSoft = Color(red: 0.47, green: 0.35, blue: 0.50)
        /// The pink the icon's heart is made of. Selected tabs, primary buttons.
        public static let accent = Color(red: 1.0, green: 0.37, blue: 0.56)
        public static let coral = Color(red: 1.0, green: 0.48, blue: 0.44)
        public static let lavender = Color(red: 0.55, green: 0.47, blue: 0.97)
        public static let cream = Color(red: 1.0, green: 0.98, blue: 0.96)

        /// A group's own two-tone card.
        public static func gradient(hue: Double) -> LinearGradient {
            LinearGradient(
                colors: [
                    Color(hue: hue, saturation: 0.42, brightness: 1.0),
                    Color(hue: (hue + 0.07).truncatingRemainder(dividingBy: 1),
                          saturation: 0.58, brightness: 0.92),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    /// Functional colours have one job each. Pink remains the only action
    /// colour; these appear only as feedback, so a coloured control always
    /// means the same thing throughout the app.
    public enum Feedback {
        public static let success = Color(red: 0.18, green: 0.62, blue: 0.43)
        public static let warning = Color(red: 0.90, green: 0.52, blue: 0.16)
        public static let error = Color(red: 0.86, green: 0.28, blue: 0.36)
        public static let info = Kawaii.lavender
    }

    /// Text colours that follow the colour scheme.
    ///
    /// The app has two grounds now — bright lists and a dark player — and the
    /// same components sit on both. Fixed white ink was right when everything
    /// was dark; on the bright screens it vanished. Resolving per scheme means
    /// a screen goes bright with one `.environment(\.colorScheme, .light)` and
    /// every label on it follows, instead of dozens of colour edits per screen.
    public enum Ink {
        public static let primary = adaptive(
            dark: .white, light: Color(red: 0.24, green: 0.14, blue: 0.28))
        public static let secondary = adaptive(
            dark: .white.opacity(0.62), light: Color(red: 0.24, green: 0.14, blue: 0.28).opacity(0.68))
        public static let tertiary = adaptive(
            dark: .white.opacity(0.38), light: Color(red: 0.24, green: 0.14, blue: 0.28).opacity(0.45))
        public static let hairline = adaptive(
            dark: .white.opacity(0.12), light: Color(red: 0.24, green: 0.14, blue: 0.28).opacity(0.10))
    }

    /// One colour for each scheme, resolved where the view is drawn.
    static func adaptive(dark: Color, light: Color) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

    public enum Surface {
        /// Near-black under the player; cream-pink under the lists.
        public static let base = adaptive(
            dark: Color(red: 0.04, green: 0.04, blue: 0.05),
            light: Color(red: 0.99, green: 0.95, blue: 0.97))
        /// The bright ground for lists and group cards.
        public static let kawaii = LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.985, blue: 0.975),
                Color(red: 0.985, green: 0.975, blue: 1.0),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        public static let raised = adaptive(dark: .white.opacity(0.07), light: .white.opacity(0.84))
        public static let sunken = adaptive(dark: .black.opacity(0.28), light: Color(red: 0.24, green: 0.14, blue: 0.28).opacity(0.06))
        public static let panel = adaptive(dark: .white.opacity(0.08), light: .white.opacity(0.94))
        public static let border = adaptive(dark: .white.opacity(0.10), light: Color(red: 0.25, green: 0.16, blue: 0.29).opacity(0.07))
    }

    /// The one saturated element in an otherwise monochrome app. Used for
    /// progress and achievement, where a number alone reads as flat.
    public enum Accent {
        public static let start = Kawaii.lavender
        public static let end = Kawaii.accent

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
        public static let card: CGFloat = 24
        public static let chip: CGFloat = 12
        public static let artwork: CGFloat = 16
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
        public static var title: SwiftUI.Font { .kawaii(22, weight: .bold, relativeTo: .title2) }
        public static var sectionTitle: SwiftUI.Font { .kawaii(13, weight: .bold, relativeTo: .caption1) }
        public static var body: SwiftUI.Font { .just(15, relativeTo: .subheadline) }
        public static var caption: SwiftUI.Font { .just(12, weight: .medium, relativeTo: .caption1) }
        public static var japanese: SwiftUI.Font { .just(19, weight: .medium, relativeTo: .body) }
    }
}

public extension View {
    /// The standard raised container: glass over artwork, never a flat card.
    func justCard(cornerRadius: CGFloat = JustTheme.Radius.card) -> some View {
        padding(JustTheme.Space.regular)
            .background(JustTheme.Surface.panel, in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(JustTheme.Surface.border, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.04), radius: 12, y: 5)
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
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 22)
            .background(JustTheme.Kawaii.accent.opacity(configuration.isPressed ? 0.72 : 1), in: .capsule)
            .contentShape(.capsule)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The shared bright backdrop. The soft colour pools echo concert lights but
/// stay away from text, so list screens feel branded without becoming noisy.
public struct JustBrandBackground: View {
    public init() {}

    public var body: some View {
        JustTheme.Surface.kawaii.ignoresSafeArea()
    }
}

/// A compact version of the app icon: one note and one beat.
public struct UtaringMark: View {
    private let size: CGFloat

    public init(size: CGFloat = 44) { self.size = size }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(JustTheme.Kawaii.cream)
            Image(systemName: "music.note")
                .font(.system(size: size * 0.48, weight: .black))
                .foregroundStyle(JustTheme.Kawaii.accent)
            Circle()
                .fill(JustTheme.Kawaii.lavender)
                .frame(width: size * 0.13, height: size * 0.13)
                .offset(x: size * 0.25, y: -size * 0.22)
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.28)
                .strokeBorder(JustTheme.Surface.border, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

/// Consistent title treatment for the bright top-level screens.
public struct JustScreenHeader: View {
    private let title: String
    private let subtitle: String
    private let showsMark: Bool

    public init(_ title: String, subtitle: String, showsMark: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self.showsMark = showsMark
    }

    public var body: some View {
        HStack(spacing: JustTheme.Space.snug) {
            if showsMark { UtaringMark(size: 46) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.kawaii(32, weight: .bold, relativeTo: .largeTitle))
                    .foregroundStyle(JustTheme.Kawaii.ink)
                Text(subtitle)
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(JustTheme.Kawaii.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A semantic icon container used by rows, setup states and exercise cards.
public struct JustIconBadge: View {
    private let symbol: String
    private let tint: Color
    private let size: CGFloat

    public init(_ symbol: String, tint: Color = JustTheme.Kawaii.accent, size: CGFloat = 44) {
        self.symbol = symbol
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.10), in: .rect(cornerRadius: size * 0.32))
            .accessibilityHidden(true)
    }
}

/// Compact progress treatment shared by review and quizzes.
public struct JustProgressHeader: View {
    private let current: Int
    private let total: Int

    public init(current: Int, total: Int) {
        self.current = current
        self.total = max(total, 1)
    }

    public var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(current) / \(total)")
                    .font(JustTheme.Font.caption.monospacedDigit())
                    .foregroundStyle(JustTheme.Ink.secondary)
                Spacer()
                Text("\(Int((Double(current) / Double(total) * 100).rounded()))%")
                    .font(JustTheme.Font.caption.monospacedDigit())
                    .foregroundStyle(JustTheme.Ink.tertiary)
            }
            ProgressView(value: Double(current), total: Double(total))
                .tint(JustTheme.Kawaii.accent)
        }
    }
}

/// A short, always-visible explanation of a feature. Each step pairs a
/// familiar symbol with a verb so the symbol never has to be guessed.
public struct JustGuideStep: Identifiable {
    public let id: String
    public let symbol: String
    public let title: String
    public let detail: String

    public init(_ symbol: String, title: String, detail: String) {
        self.id = "\(symbol)-\(title)"
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }
}

public struct JustFeatureGuide: View {
    private let title: String
    private let detail: String?
    private let steps: [JustGuideStep]
    @Environment(\.guideIsDismissible) private var isDismissible

    public init(_ title: String, detail: String? = nil, steps: [JustGuideStep]) {
        self.title = title
        self.detail = detail
        self.steps = steps
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: JustTheme.Space.snug) {
            HStack(spacing: JustTheme.Space.tight) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(JustTheme.Feedback.info)
                    .accessibilityHidden(true)
                Text(title)
                    .font(JustTheme.Font.body.weight(.bold))
                    .foregroundStyle(JustTheme.Ink.primary)
            }
            // Room for the ✕ that `dismissibleGuide` lays over the corner.
            .padding(.trailing, isDismissible ? 30 : 0)

            if let detail {
                Text(detail)
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(JustTheme.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(steps) { step in
                HStack(alignment: .top, spacing: JustTheme.Space.tight) {
                    JustIconBadge(step.symbol, tint: JustTheme.Feedback.info, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(JustTheme.Font.caption.weight(.bold))
                            .foregroundStyle(JustTheme.Ink.primary)
                        Text(step.detail)
                            .font(JustTheme.Font.caption)
                            .foregroundStyle(JustTheme.Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(JustTheme.Space.regular)
        .background(JustTheme.Feedback.info.opacity(0.07), in: .rect(cornerRadius: JustTheme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: JustTheme.Radius.card)
                .strokeBorder(JustTheme.Feedback.info.opacity(0.16), lineWidth: 1)
        }
    }
}

/// One-line instruction used inside an active task such as lyrics or review.
public struct JustActionHint: View {
    private let symbol: String
    private let text: String
    @Environment(\.guideIsDismissible) private var isDismissible

    public init(_ text: String, symbol: String = "hand.tap.fill") {
        self.symbol = symbol
        self.text = text
    }

    public var body: some View {
        Label(text, systemImage: symbol)
            .font(JustTheme.Font.caption.weight(.semibold))
            .foregroundStyle(JustTheme.Ink.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, JustTheme.Space.snug)
            // Room for the ✕ that `dismissibleGuide` lays over the corner.
            .padding(.trailing, isDismissible ? 40 : JustTheme.Space.snug)
            .padding(.vertical, JustTheme.Space.tight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JustTheme.Feedback.info.opacity(0.08), in: .rect(cornerRadius: JustTheme.Radius.chip))
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
                JustTheme.Surface.panel.opacity(configuration.isPressed ? 0.55 : 1),
                in: .capsule
            )
            .overlay {
                Capsule().strokeBorder(JustTheme.Surface.border, lineWidth: 1)
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
        font(.kawaii(20, relativeTo: .title3))
            .foregroundStyle(JustTheme.Kawaii.ink)
            .padding(.horizontal, JustTheme.Space.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
