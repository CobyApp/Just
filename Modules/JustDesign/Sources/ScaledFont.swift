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
        relativeTo style: UIFont.TextStyle = .body
    ) -> Font {
        Font(
            UIFontMetrics(forTextStyle: style)
                .scaledFont(for: .systemFont(ofSize: size, weight: weight))
        )
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
