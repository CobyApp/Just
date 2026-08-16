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
    private let rubyHeight: CGFloat = 13

    public init(
        segments: [RubySegment],
        font: Font = JustTheme.Font.lyric,
        rubyFont: Font = JustTheme.Font.ruby,
        color: Color = JustTheme.Ink.primary,
        rubyColor: Color = JustTheme.Ink.tertiary,
        showsRuby: Bool = true
    ) {
        self.segments = segments
        self.font = font
        self.rubyFont = rubyFont
        self.color = color
        self.rubyColor = rubyColor
        self.showsRuby = showsRuby
    }

    public var body: some View {
        RubyFlowLayout(spacing: 0, lineSpacing: showsRuby ? 10 : 6) {
            ForEach(segments) { segment in
                Text(segment.base)
                    .font(font)
                    .foregroundStyle(color)
                    .fixedSize()
                    // Reserve the ruby's line above the text rather than
                    // stacking it, so a segment is exactly as wide as its base.
                    .padding(.top, showsRuby ? rubyHeight : 0)
                    .overlay(alignment: .top) {
                        if showsRuby, let ruby = segment.ruby {
                            // An overlay overhangs instead of widening the
                            // layout: 埃[ほこり] is three kana over one kanji,
                            // and stacking it would push the neighbouring
                            // characters apart. Print sets the reading over the
                            // character and lets it spill.
                            Text(ruby)
                                .font(rubyFont)
                                .foregroundStyle(rubyColor)
                                .fixedSize()
                        }
                    }
            }
        }
    }
}

/// A left-to-right wrapping layout. `Text` can't wrap a heterogeneous run of
/// subviews, and `WrappingHStack` isn't in the SDK, so this is the minimum
/// that makes ruby text behave like a paragraph.
public struct RubyFlowLayout: Layout {
    public var spacing: CGFloat
    public var lineSpacing: CGFloat

    public init(spacing: CGFloat = 0, lineSpacing: CGFloat = 6) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, maxWidth: maxWidth)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } +
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
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height)),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
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
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
