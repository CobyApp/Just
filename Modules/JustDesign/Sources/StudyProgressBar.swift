import SwiftUI

/// How far a song has been analysed, on a "continue studying" card.
///
/// Lives here, and is used by both shelves, because the two tabs had drifted
/// apart: the browse shelf stacked a grey progress bar under a coloured
/// difficulty bar, 12pt apart and the same width, so they read as one thing —
/// and a barely-analysed song showed an empty top bar with a full orange one
/// beneath it, which looks like a warning. The home shelf, meanwhile, showed
/// difficulty and no progress at all.
///
/// One bar now, and a label on it. Difficulty is a property of the song, useful
/// when picking one; a shelf called "이어서 공부하기" is about resuming, and the
/// player already shows difficulty. An unnamed bar does not say what it is a
/// percentage of.
public struct StudyProgressBar: View {
    private let progress: Double
    private let width: CGFloat

    public init(progress: Double, width: CGFloat) {
        self.progress = min(max(progress, 0), 1)
        self.width = width
    }

    public var body: some View {
        ProgressView(value: progress) {
            Text("해석 \(Int((progress * 100).rounded()))%")
                .font(JustTheme.Font.caption)
                .foregroundStyle(JustTheme.Ink.tertiary)
        }
        .tint(JustTheme.Ink.secondary)
        .frame(width: width)
    }
}
