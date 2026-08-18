import JustCore
import JustDesign
import SwiftData
import SwiftUI

/// The practice tab: one way in per exercise type.
///
/// Separated from the word list because studying and browsing are different
/// intents — the list is for looking a word up, this is for being tested on it.
struct PracticeScreen: View {
    @Environment(\.modelContext) private var context
    @Query private var entries: [VocabEntry]

    @State private var stats: StudyStats = .empty

    private var store: JustStore { JustStore(context: context) }

    var body: some View {
        NavigationStack {
            ZStack {
                JustTheme.Surface.base.ignoresSafeArea()
                content
            }
            .navigationTitle("연습")
            .navigationDestination(for: ReviewRoute.self) { _ in ReviewScreen() }
            .navigationDestination(for: QuizRoute.self) { QuizScreen(kind: $0.kind) }
            .onAppear { stats = store.stats() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if entries.isEmpty {
            ContentUnavailableView {
                Label("아직 연습할 단어가 없습니다", systemImage: "square.dashed")
            } description: {
                Text("가사에서 줄을 눌러 단어를 담으면 그 단어와 가사로 문제를 만듭니다.")
            }
        } else {
            ScrollView {
                VStack(spacing: JustTheme.Space.snug) {
                    reviewRow
                    quizRow(nil)
                    ForEach(QuizKind.allCases, id: \.self) { quizRow($0) }
                }
                .padding(JustTheme.Space.regular)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var reviewRow: some View {
        NavigationLink(value: ReviewRoute()) {
            PracticeRow(
                symbol: "rectangle.on.rectangle.angled",
                title: "복습 카드",
                detail: stats.dueCount > 0
                    ? "일정에 올라온 \(stats.dueCount)개를 가사 예문과 함께"
                    : "지금은 올라온 카드가 없습니다",
                badge: stats.dueCount > 0 ? "\(stats.dueCount)" : nil,
                isProminent: stats.dueCount > 0
            )
        }
        .buttonStyle(.plain)
    }

    private func quizRow(_ kind: QuizKind?) -> some View {
        NavigationLink(value: QuizRoute(kind: kind)) {
            PracticeRow(
                symbol: kind?.symbol ?? "shuffle",
                title: kind?.title ?? "랜덤 믹스",
                detail: kind?.detail ?? "세 유형을 섞어서 냅니다. 형식이 아니라 단어를 시험합니다.",
                badge: nil,
                isProminent: false
            )
        }
        .buttonStyle(.plain)
    }
}

struct QuizRoute: Hashable {
    let kind: QuizKind?
}

private struct PracticeRow: View {
    let symbol: String
    let title: String
    let detail: String
    let badge: String?
    let isProminent: Bool

    var body: some View {
        HStack(spacing: JustTheme.Space.snug) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(isProminent ? JustTheme.Accent.end : JustTheme.Ink.primary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(JustTheme.Font.body.weight(.semibold))
                    .foregroundStyle(JustTheme.Ink.primary)
                Text(detail)
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(JustTheme.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: JustTheme.Space.tight)

            if let badge {
                Text(badge)
                    .font(JustTheme.Font.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(JustTheme.Surface.base)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(JustTheme.Ink.primary, in: .capsule)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(JustTheme.Ink.secondary)
        }
        .padding(JustTheme.Space.snug)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JustTheme.Surface.raised, in: .rect(cornerRadius: JustTheme.Radius.card))
    }
}
