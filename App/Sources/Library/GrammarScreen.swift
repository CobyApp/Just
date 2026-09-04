import JustCore
import JustDesign
import JustSensei
import SwiftUI

/// Grammar patterns pooled from every song the user has studied.
struct GrammarScreen: View {
    @Environment(\.modelContext) private var context

    @State private var notes: [GrammarSighting] = []
    @State private var hasLoaded = false

    var body: some View {
        ZStack {
            JustBrandBackground()

            if !hasLoaded {
                List(0..<5, id: \.self) { _ in
                    SkeletonTrackRow().listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .allowsHitTesting(false)
            } else if notes.isEmpty {
                ContentUnavailableView {
                    Label("아직 모인 문법이 없습니다", systemImage: "text.book.closed")
                } description: {
                    Text("가사를 해석하면 그 줄에 쓰인 문법이 함께 정리되어 여기에 모입니다.")
                }
            } else {
                List(notes) { note in
                    row(note)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("문법")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            notes = JustStore(context: context).grammarNotes()
            hasLoaded = true
        }
    }

    private func row(_ note: GrammarSighting) -> some View {
        VStack(alignment: .leading, spacing: JustTheme.Space.tight) {
            HStack(alignment: .firstTextBaseline, spacing: JustTheme.Space.tight) {
                Text(note.pattern)
                    .font(JustTheme.Font.japanese)
                    .foregroundStyle(JustTheme.Ink.primary)
                Spacer(minLength: JustTheme.Space.tight)
                // The count is the point of pooling: a pattern in four songs is
                // the one to learn next.
                if note.songCount > 1 {
                    JustChip("\(note.songCount)곡", tint: JustTheme.Accent.end)
                }
            }

            Text(note.explanationKo)
                .font(JustTheme.Font.body)
                .foregroundStyle(JustTheme.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 3) {
                RubyText(
                    segments: Furigana.segments(forLine: note.example),
                    font: JustTheme.Font.caption,
                    color: JustTheme.Ink.secondary
                )
                if !note.exampleTranslation.isEmpty {
                    Text(note.exampleTranslation)
                        .font(JustTheme.Font.caption)
                        .foregroundStyle(JustTheme.Ink.tertiary)
                }
            }
            .padding(.top, 2)
        }
        .justCard()
        .padding(.vertical, 3)
    }
}
