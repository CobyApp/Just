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
                JustEmptyState(
                    icon: "text.book.closed",
                    title: "아직 모인 문법이 없습니다",
                    message: "노래를 열고 궁금한 가사 줄을 누르세요. 분석된 문법과 표현이 여기에 자동으로 모입니다."
                )
            } else {
                List {
                    JustActionHint(
                        "가사에서 발견한 문법을 모아 둔 곳입니다. 여러 곡에 나온 표현은 곡 수로 표시해요.",
                        symbol: "text.book.closed.fill"
                    )
                        .dismissibleGuide("grammar.hint")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    ForEach(notes) { note in
                        row(note)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
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
