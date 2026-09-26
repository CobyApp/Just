import SwiftUI
import UIKit

public extension Font {
    /// A system font at an explicit point size, scaled for Dynamic Type *as of
    /// this call*.
    ///
    /// Neither built-in option covers an explicit size that scales:
    /// `Font.system(size:)` ignores the user's text-size setting entirely, and
    /// `Font.custom(_:size:relativeTo:)` scales but demands a font file name —
    /// the system font's private names resolve to Times. So this runs a
    /// `UIFont` through `UIFontMetrics`, which produces a *fixed* size: text
    /// only picks up a new setting when the view that built the font is
    /// evaluated again. Where a `View` is being styled, prefer `justFont(…)` /
    /// `kawaiiFont(…)`, which read the size from the environment and follow a
    /// change live; this stays for the places that need a `Font` value —
    /// `RubyText`'s parameters, the theme's font tokens.
    ///
    /// - Parameter style: the text style the size is anchored to. It decides how
    ///   aggressively the size grows; headings should scale less than body copy.
    static func just(
        _ size: CGFloat,
        weight: UIFont.Weight = .regular,
        relativeTo style: UIFont.TextStyle = .body,
        design: UIFontDescriptor.SystemDesign = .default
    ) -> Font {
        var base = UIFont.systemFont(ofSize: size, weight: weight)
        if design != .default,
           let descriptor = base.fontDescriptor.withDesign(design) {
            base = UIFont(descriptor: descriptor, size: size)
        }
        return Font(UIFontMetrics(forTextStyle: style).scaledFont(for: base))
    }

    /// The bright screens' display face: the same system font, rounded.
    ///
    /// Rounded for the wordmark, group names and section titles — the places
    /// that carry the app's personality. Lyrics, readings and translations stay
    /// on the default design: that text is for reading Japanese, not for
    /// looking cheerful, and the rounded face is not where its contrast was
    /// tuned.
    static func kawaii(
        _ size: CGFloat,
        weight: UIFont.Weight = .bold,
        relativeTo style: UIFont.TextStyle = .title2
    ) -> Font {
        just(size, weight: weight, relativeTo: style, design: .rounded)
    }
}

public extension View {
    /// `Font.just`, applied so that it follows Dynamic Type live.
    ///
    /// The size is a `@ScaledMetric`, which SwiftUI re-resolves whenever the
    /// text-size setting changes — including a `.dynamicTypeSize` override
    /// further up — rather than a number frozen when the body last ran.
    ///
    /// - Parameter monospacedDigits: for counters, whose width should not
    ///   jitter as the digits change.
    func justFont(
        _ size: CGFloat,
        weight: UIFont.Weight = .regular,
        relativeTo style: UIFont.TextStyle = .body,
        design: UIFontDescriptor.SystemDesign = .default,
        monospacedDigits: Bool = false
    ) -> some View {
        modifier(ScaledSystemFont(
            size: size,
            weight: weight,
            style: style,
            design: design,
            monospacedDigits: monospacedDigits
        ))
    }

    /// `Font.kawaii`, applied so that it follows Dynamic Type live.
    func kawaiiFont(
        _ size: CGFloat,
        weight: UIFont.Weight = .bold,
        relativeTo style: UIFont.TextStyle = .title2
    ) -> some View {
        justFont(size, weight: weight, relativeTo: style, design: .rounded)
    }
}

private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design
    private let monospacedDigits: Bool

    init(
        size: CGFloat,
        weight: UIFont.Weight,
        style: UIFont.TextStyle,
        design: UIFontDescriptor.SystemDesign,
        monospacedDigits: Bool
    ) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: Self.swiftUIStyle(style))
        self.weight = Self.swiftUIWeight(weight)
        self.design = Self.swiftUIDesign(design)
        self.monospacedDigits = monospacedDigits
    }

    func body(content: Content) -> some View {
        let font = Font.system(size: size, weight: weight, design: design)
        content.font(monospacedDigits ? font.monospacedDigit() : font)
    }

    // UIKit's vocabulary is kept in the signature so call sites read the same
    // as `Font.just` (`.caption1`, `.title1`); SwiftUI wants its own.

    private static func swiftUIStyle(_ style: UIFont.TextStyle) -> Font.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title1: .title
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption1: .caption
        case .caption2: .caption2
        default: .body
        }
    }

    private static func swiftUIWeight(_ weight: UIFont.Weight) -> Font.Weight {
        switch weight {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }

    private static func swiftUIDesign(_ design: UIFontDescriptor.SystemDesign) -> Font.Design {
        switch design {
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        default: .default
        }
    }
}

public extension CGFloat {
    /// Scales a layout measurement the same way `Font.just` scales type.
    ///
    /// Needed wherever a hand-computed dimension has to stay in step with text
    /// — the furigana band above a lyric line, for instance, which would clip
    /// the reading if the type grew and the reserved space did not.
    func scaledForText(_ style: UIFont.TextStyle = .body) -> CGFloat {
        UIFontMetrics(forTextStyle: style).scaledValue(for: self)
    }
}
