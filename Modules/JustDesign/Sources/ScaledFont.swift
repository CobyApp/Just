import SwiftUI
import UIKit

public extension Font {
    /// A system font at an explicit point size that still follows Dynamic Type.
    ///
    /// Neither built-in option covers this: `Font.system(size:)` ignores the
    /// user's text-size setting entirely, and `Font.custom(_:size:relativeTo:)`
    /// scales but demands a font file name. Running a `UIFont` through
    /// `UIFontMetrics` keeps the sizes the design was drawn at while honouring
    /// the setting — which a reading-heavy app cannot reasonably ignore.
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
