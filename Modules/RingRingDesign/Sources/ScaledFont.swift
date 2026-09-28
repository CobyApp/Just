import SwiftUI
import UIKit

/// A system font at an explicit point size that follows Dynamic Type — live.
///
/// Neither built-in option covers an explicit size that scales:
/// `Font.system(size:)` ignores the user's text-size setting entirely, and
/// `Font.custom(_:size:relativeTo:)` scales but demands a font file name — the
/// system font's private names resolve to Times.
///
/// This used to be a `Font`, made by running a `UIFont` through
/// `UIFontMetrics`. That scaled, but only as of the moment it was built: text
/// picked up a new setting when its view happened to be evaluated again, and a
/// `.dynamicTypeSize` limit further up was ignored altogether. So the style is
/// now a description, and `.font(_:)` resolves it through `@ScaledMetric`,
/// which SwiftUI re-resolves whenever the setting changes.
///
/// Call sites read as they did — `.font(JustTheme.Font.caption)`,
/// `.font(JustTheme.Font.body.weight(.semibold))` — because the modifiers they
/// chain exist here too.
public struct JustFontStyle: Hashable, Sendable {
    public var size: CGFloat
    public var weight: Font.Weight
    /// Decides how aggressively the size grows; headings should scale less
    /// than body copy.
    public var textStyle: Font.TextStyle
    public var design: Font.Design
    public var monospacedDigits: Bool

    /// - Parameter style: the text style the size is anchored to.
    public static func just(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo style: UIFont.TextStyle = .body,
        design: Font.Design = .default
    ) -> JustFontStyle {
        JustFontStyle(
            size: size,
            weight: weight,
            textStyle: Self.textStyle(style),
            design: design,
            monospacedDigits: false
        )
    }

    /// The bright screens' display face: the same system font, rounded.
    ///
    /// Rounded for the wordmark, group names and section titles — the places
    /// that carry the app's personality. Lyrics, readings and translations stay
    /// on the default design: that text is for reading Japanese, not for
    /// looking cheerful, and the rounded face is not where its contrast was
    /// tuned.
    public static func kawaii(
        _ size: CGFloat,
        weight: Font.Weight = .bold,
        relativeTo style: UIFont.TextStyle = .title2
    ) -> JustFontStyle {
        just(size, weight: weight, relativeTo: style, design: .rounded)
    }

    public func weight(_ weight: Font.Weight) -> JustFontStyle {
        var copy = self
        copy.weight = weight
        return copy
    }

    /// For counters, whose width should not jitter as the digits change.
    public func monospacedDigit() -> JustFontStyle {
        var copy = self
        copy.monospacedDigits = true
        return copy
    }

    /// A `Font` at the size the current setting gives *now* — for the rare
    /// API that insists on a `Font` value. It does not follow a later change;
    /// prefer `.font(_:)` with the style itself.
    public var snapshot: Font {
        let scaled = UIFontMetrics(forTextStyle: Self.uiTextStyle(textStyle)).scaledValue(for: size)
        return resolved(size: scaled)
    }

    func resolved(size: CGFloat) -> Font {
        let font = Font.system(size: size, weight: weight, design: design)
        return monospacedDigits ? font.monospacedDigit() : font
    }

    // UIKit's vocabulary is kept in `just(…)` so call sites read `.caption1`,
    // `.title1` as they always have; SwiftUI wants its own.

    private static func textStyle(_ style: UIFont.TextStyle) -> Font.TextStyle {
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

    private static func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

public extension View {
    /// Applies a `JustFontStyle`, following Dynamic Type as it changes.
    func font(_ style: JustFontStyle) -> some View {
        modifier(ScaledSystemFont(style: style))
    }

    /// `.font(.just(…))`, spelled out — kept for the call sites that read
    /// better with the size up front.
    func justFont(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo style: UIFont.TextStyle = .body,
        design: Font.Design = .default,
        monospacedDigits: Bool = false
    ) -> some View {
        var font = JustFontStyle.just(size, weight: weight, relativeTo: style, design: design)
        font.monospacedDigits = monospacedDigits
        return self.font(font)
    }

    /// `.font(.kawaii(…))`, spelled out.
    func kawaiiFont(
        _ size: CGFloat,
        weight: Font.Weight = .bold,
        relativeTo style: UIFont.TextStyle = .title2
    ) -> some View {
        font(JustFontStyle.kawaii(size, weight: weight, relativeTo: style))
    }
}

private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let style: JustFontStyle

    init(style: JustFontStyle) {
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.textStyle)
        self.style = style
    }

    func body(content: Content) -> some View {
        content.font(style.resolved(size: size))
    }
}

public extension CGFloat {
    /// Scales a layout measurement the same way the text styles scale type,
    /// as of this call.
    ///
    /// Needed wherever a hand-computed dimension has to stay in step with text.
    /// Inside a view, prefer `@ScaledMetric`, which follows a change live.
    func scaledForText(_ style: UIFont.TextStyle = .body) -> CGFloat {
        UIFontMetrics(forTextStyle: style).scaledValue(for: self)
    }
}
