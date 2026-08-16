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

    public enum Font {
        /// The lyric line being studied. Large, low contrast between kanji and
        /// kana, generous line height — this is what the eye lives on.
        public static let lyricActive = SwiftUI.Font.system(size: 26, weight: .semibold)
        public static let lyric = SwiftUI.Font.system(size: 21, weight: .regular)
        public static let ruby = SwiftUI.Font.system(size: 10, weight: .medium)
        public static let translation = SwiftUI.Font.system(size: 15, weight: .regular)
        public static let title = SwiftUI.Font.system(size: 22, weight: .bold)
        public static let sectionTitle = SwiftUI.Font.system(size: 13, weight: .semibold)
        public static let body = SwiftUI.Font.system(size: 15)
        public static let caption = SwiftUI.Font.system(size: 12, weight: .medium)
        public static let japanese = SwiftUI.Font.system(size: 19, weight: .medium)
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
