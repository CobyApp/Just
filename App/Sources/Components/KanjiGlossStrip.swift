import JustCore
import JustDesign
import JustSensei
import SwiftUI

/// The Korean sound/meaning readings of each kanji in a word.
///
/// Sits directly under the word it explains, because the point is the moment
/// of recognition — 夢 「몽」 lands only if it is next to 夢.
struct KanjiGlossStrip: View {
    let word: String
    var glosses: [KanjiGloss] { KanjiKorean.shared.glosses(in: word) }

    var body: some View {
        if !glosses.isEmpty {
            HStack(spacing: 6) {
                ForEach(glosses) { gloss in
                    HStack(spacing: 4) {
                        Text(gloss.character)
                            .font(.just(14, weight: .medium, relativeTo: .footnote))
                            .foregroundStyle(JustTheme.Ink.secondary)
                        Text(gloss.label)
                            .font(JustTheme.Font.caption)
                            .foregroundStyle(JustTheme.Ink.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        JustTheme.Surface.sunken,
                        in: .rect(cornerRadius: JustTheme.Radius.chip)
                    )
                }
            }
        }
    }
}
