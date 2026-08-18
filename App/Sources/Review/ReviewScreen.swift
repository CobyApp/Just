import JustCore
import JustDesign
import JustSensei
import SwiftData
import SwiftUI

/// Spaced-repetition review.
///
/// The card shows the lyric the word came from rather than a made-up example
/// sentence — recall is anchored to a melody the user already knows, which is
/// the advantage studying from songs has over a plain word list.
struct ReviewScreen: View {
    @Environment(\.modelContext) private var context

    @State private var queue: [VocabEntry] = []
    @State private var index = 0
    @State private var isRevealed = false
    @State private var completed = 0

    private var scheduler = FSRS()
    private var store: JustStore { JustStore(context: context) }
    private var current: VocabEntry? { index < queue.count ? queue[index] : nil }

    var body: some View {
        ZStack {
            JustTheme.Surface.base.ignoresSafeArea()

            if let current {
                card(current)
            } else {
                finished
            }
        }
        .navigationTitle("복습")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !queue.isEmpty, current != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(index + 1) / \(queue.count)")
                        .font(JustTheme.Font.caption.monospacedDigit())
                        .foregroundStyle(JustTheme.Ink.tertiary)
                }
            }
        }
        .onAppear(perform: reload)
    }

    // MARK: - Card

    private func card(_ entry: VocabEntry) -> some View {
        VStack(spacing: JustTheme.Space.loose) {
            Spacer()

            VStack(spacing: JustTheme.Space.regular) {
                // The prompt is the word alone; the reading is part of the
                // answer, so it stays hidden until reveal.
                Text(entry.lemma)
                    .font(.just(44, weight: .semibold, relativeTo: .largeTitle))
                    .foregroundStyle(JustTheme.Ink.primary)

                if isRevealed {
                    VStack(spacing: JustTheme.Space.tight) {
                        if entry.showsReading {
                            Text(entry.reading)
                                .font(.just(18, relativeTo: .body))
                                .foregroundStyle(JustTheme.Ink.secondary)
                        }
                        Text(entry.meaningKo)
                            .font(.just(22, weight: .medium, relativeTo: .title3))
                            .foregroundStyle(JustTheme.Ink.primary)
                            .multilineTextAlignment(.center)
                        if !entry.note.isEmpty {
                            Text(entry.note)
                                .font(JustTheme.Font.caption)
                                .foregroundStyle(JustTheme.Ink.tertiary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }

            if isRevealed, let occurrence = entry.occurrences.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text(occurrence.lineText)
                        .font(JustTheme.Font.japanese)
                        .foregroundStyle(JustTheme.Ink.primary)
                    if let translation = occurrence.lineTranslation {
                        Text(translation)
                            .font(JustTheme.Font.body)
                            .foregroundStyle(JustTheme.Ink.secondary)
                    }
                    if let song = occurrence.song {
                        Text("\(song.artist) — \(song.title)")
                            .font(JustTheme.Font.caption)
                            .foregroundStyle(JustTheme.Ink.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .justCard()
                .transition(.opacity)
            }

            Spacer()

            if isRevealed {
                gradeButtons(entry)
            } else {
                Button {
                    withAnimation(.snappy) { isRevealed = true }
                } label: {
                    Text("뜻 보기").frame(maxWidth: .infinity)
                }
                .buttonStyle(.justPrimary)
                .controlSize(.large)
            }
        }
        .padding(JustTheme.Space.regular)
        .contentShape(.rect)
        .onTapGesture {
            if !isRevealed { withAnimation(.snappy) { isRevealed = true } }
        }
    }

    private func gradeButtons(_ entry: VocabEntry) -> some View {
        let previews = entry.review.map { scheduler.previewIntervals(for: $0) } ?? [:]
        return HStack(spacing: JustTheme.Space.tight) {
            ForEach(ReviewGrade.allCases, id: \.self) { grade in
                Button {
                    submit(grade, for: entry)
                } label: {
                    VStack(spacing: 2) {
                        Text(grade.label).font(JustTheme.Font.body.weight(.medium))
                        Text(Self.intervalLabel(previews[grade] ?? 0))
                            .font(JustTheme.Font.caption)
                            .foregroundStyle(JustTheme.Ink.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, JustTheme.Space.snug)
                }
                .buttonStyle(.glass)
                .tint(grade == .again ? .orange : JustTheme.Ink.primary)
            }
        }
    }

    private var finished: some View {
        ContentUnavailableView {
            Label(
                completed > 0 ? "오늘 복습 끝" : "복습할 단어가 없습니다",
                systemImage: completed > 0 ? "checkmark.circle" : "sparkles"
            )
        } description: {
            Text(
                completed > 0
                    ? "\(completed)개를 복습했습니다. 다음 카드는 일정에 맞춰 다시 올라옵니다."
                    : "가사에서 단어를 담으면 여기에서 복습할 수 있습니다."
            )
        } actions: {
            Button("다시 확인") { reload() }
                .buttonStyle(.justSecondary)
        }
    }

    // MARK: - Actions

    private func reload() {
        queue = store.dueEntries()
        index = 0
        isRevealed = false
        completed = 0
    }

    private func submit(_ grade: ReviewGrade, for entry: VocabEntry) {
        grade == .again ? Haptics.wrong() : Haptics.tick()
        store.grade(entry, grade)
        completed += 1
        withAnimation(.snappy) {
            isRevealed = false
            index += 1
        }
    }

    private static func intervalLabel(_ days: Double) -> String {
        switch days {
        case ..<1: "10분"
        case ..<30: "\(Int(days))일"
        case ..<365: "\(Int(days / 30))개월"
        default: String(format: "%.1f년", days / 365)
        }
    }
}
