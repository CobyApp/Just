import JustCore
import SwiftUI

/// Renders Japanese text with furigana above the kanji.
///
/// SwiftUI has no ruby primitive, so each segment becomes a two-line stack and
/// a flow layout wraps them like text. The reading is laid out *outside* the
/// base's width so a long reading over a single kanji doesn't stretch the
/// character spacing — it overhangs instead, which is how print sets it.
public struct RubyText: View {
    private let segments: [RubySegment]
    private let font: Font
    private let rubyFont: Font
    private let color: Color
    private let rubyColor: Color
    private let showsRuby: Bool

    /// Vertical room reserved above every segment so baselines stay aligned
    /// whether or not a given segment carries a reading.
    ///
    /// Passed in rather than fixed: it has to track the ruby font, and `Font`
    /// cannot be measured. A constant here left a visible gap between wrapped
    /// rows once the lyric type was scaled up.
    private let rubyHeight: CGFloat

    public init(
        segments: [RubySegment],
        font: Font = JustTheme.Font.lyric,
        rubyFont: Font = JustTheme.Font.ruby,
        color: Color = JustTheme.Ink.primary,
        rubyColor: Color = JustTheme.Ink.tertiary,
        showsRuby: Bool = true,
        rubyHeight: CGFloat = 13
    ) {
        self.rubyHeight = rubyHeight
        self.segments = segments
        self.font = font
        self.rubyFont = rubyFont
        self.color = color
        self.rubyColor = rubyColor
        self.showsRuby = showsRuby
    }

    public var body: some View {
        RubyFlowLayout(spacing: 0, lineSpacing: lineSpacing, rubyHeight: rubyHeight) {
            ForEach(segments) { segment in
                Text(segment.base)
                    .font(font)
                    .foregroundStyle(color)
                    .fixedSize()
                    .overlay(alignment: .top) {
                        if showsRuby, let ruby = segment.ruby {
                            // Drawn *outside* the text's bounds — above it and
                            // overhanging sideways. 埃[ほこり] is three kana over
                            // one kanji; stacking it inside the layout would
                            // push the neighbouring characters apart, which is
                            // not how print sets ruby.
                            Text(ruby)
                                .font(rubyFont)
                                .foregroundStyle(rubyColor)
                                .fixedSize()
                                .offset(y: -rubyHeight)
                        }
                    }
                    // The layout reserves the band only for rows that actually
                    // carry a reading, so a wrapped fragment like でしょう does
                    // not inherit a gap it has no use for.
                    .layoutValue(key: RubyRowKey.self, value: showsRuby && segment.ruby != nil)
            }
        }
    }

    private var lineSpacing: CGFloat { showsRuby ? rubyHeight * 0.25 : 5 }
}

/// Marks a segment as carrying a reading, so the layout can reserve vertical
/// room per row instead of unconditionally.
struct RubyRowKey: LayoutValueKey {
    static let defaultValue = false
}

/// A left-to-right wrapping layout. `Text` can't wrap a heterogeneous run of
/// subviews, and `WrappingHStack` isn't in the SDK, so this is the minimum
/// that makes ruby text behave like a paragraph.
public struct RubyFlowLayout: Layout {
    public var spacing: CGFloat
    public var lineSpacing: CGFloat
    /// Room added above a row when something in it has a reading to print.
    public var rubyHeight: CGFloat

    public init(spacing: CGFloat = 0, lineSpacing: CGFloat = 6, rubyHeight: CGFloat = 0) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.rubyHeight = rubyHeight
    }

    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, maxWidth: maxWidth)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.totalHeight(rubyHeight) } +
            lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: min(width, maxWidth), height: height)
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = layout(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let reserve = row.hasRuby ? rubyHeight : 0
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + reserve + (row.height - item.size.height)),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.totalHeight(rubyHeight) + lineSpacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
        var hasRuby = false

        func totalHeight(_ rubyHeight: CGFloat) -> CGFloat {
            height + (hasRuby ? rubyHeight : 0)
        }
    }

    private func layout(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let advance = current.items.isEmpty ? size.width : size.width + spacing
            if !current.items.isEmpty, current.width + advance > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.items.append((index, size))
            current.width += current.items.count == 1 ? size.width : advance
            current.height = max(current.height, size.height)
            if subviews[index][RubyRowKey.self] { current.hasRuby = true }
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
