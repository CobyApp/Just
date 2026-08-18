import JustCore
import SwiftUI

/// A song's JLPT makeup as one stacked bar.
///
/// A bar rather than a number: "N3 수준" alone hides whether the rest is N5
/// filler or N1 spikes, and that difference decides whether the song is a
/// comfortable read or a slog.
public struct DifficultyBar: View {
    private let difficulty: SongDifficulty
    private let height: CGFloat
    private let showsLegend: Bool

    public init(
        difficulty: SongDifficulty,
        height: CGFloat = 6,
        showsLegend: Bool = true
    ) {
        self.difficulty = difficulty
        self.height = height
        self.showsLegend = showsLegend
    }

    public var body: some View {
        if !difficulty.isEmpty {
            VStack(alignment: .leading, spacing: JustTheme.Space.tight) {
                bar
                if showsLegend {
                    Text(difficulty.summary)
                        .font(JustTheme.Font.caption)
                        .foregroundStyle(JustTheme.Ink.secondary)
                }
            }
        }
    }

    private var bar: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(difficulty.breakdown, id: \.level) { slice in
                    slice.level.tint
                        .frame(
                            width: max(
                                2,
                                geometry.size.width * CGFloat(slice.count) / CGFloat(difficulty.total)
                            )
                        )
                }
            }
            .clipShape(.capsule)
        }
        .frame(height: height)
    }
}
