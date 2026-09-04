import JustCore
import JustDesign
import JustSensei
import SwiftData
import SwiftUI

/// The practice tab: one way in per exercise type.
///
/// Separated from the word list because studying and browsing are different
/// intents — the list is for looking a word up, this is for being tested on it.
struct PracticeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var entries: [VocabEntry]

    @State private var stats: StudyStats = .empty
    @State private var struggling = 0

    private var store: JustStore { JustStore(context: context) }

    var body: some View {
        NavigationStack {
            ZStack {
                JustBrandBackground()
                content
            }
            .navigationTitle("퀴즈")
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: ReviewRoute.self) { _ in ReviewScreen() }
            .navigationDestination(for: QuizRoute.self) {
                QuizScreen(kind: $0.kind, scope: $0.scope)
            }
            .onAppear {
                stats = store.stats()
                struggling = store.strugglingEntries().count
            }
        }
        // A list screen, so bright. The player it opens stays dark.
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private var content: some View {
        if entries.isEmpty {
            JustEmptyState(
                icon: "square.dashed",
                title: "아직 연습할 단어가 없습니다",
                message: "가사에서 줄을 눌러 단어를 담으면 그 단어와 가사로 문제를 만듭니다.",
                actionTitle: "그룹 보러 가기",
                action: { app.tab = .groups }
            )
        } else {
            ScrollView {
                VStack(spacing: JustTheme.Space.snug) {
                    JustScreenHeader("퀴즈", subtitle: "좋아하는 가사로 가볍게 한 판")
                        .padding(.bottom, JustTheme.Space.tight)
                    reviewRow
                    struggleRow
                    quizRow(nil)
                    ForEach(Self.offeredKinds, id: \.self) { quizRow($0) }
                }
                .padding(JustTheme.Space.regular)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// Every mode this device can actually run.
    ///
    /// Dictation needs a Japanese voice. Without one the device would read a
    /// Japanese line in its own language, and no amount of listening would let
    /// the learner answer — so the row is withheld rather than offered and
    /// found broken. Same principle as the struggling row below: do not
    /// advertise a mode that cannot be used.
    private static var offeredKinds: [QuizKind] {
        QuizKind.allCases.filter { kind in
            kind != .dictation || Pronouncer.shared.canSpeakJapanese
        }
    }

    /// Offered only when there is something to struggle with, so the tab does
    /// not advertise a mode that would open empty.
    @ViewBuilder
    private var struggleRow: some View {
        if struggling > 0 {
            NavigationLink(value: QuizRoute(kind: nil, scope: .struggling)) {
                PracticeRow(
                    symbol: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90",
                    title: "어려운 단어 집중",
                    detail: "틀린 적 있는 \(struggling)개만 골라서 냅니다",
                    badge: nil,
                    isProminent: false
                )
            }
            .buttonStyle(.plain)
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
    var scope: QuizScope = .all
}

/// Which words a round draws from.
enum QuizScope: Hashable {
    case all
    /// Only words with recorded lapses — see `JustStore.strugglingEntries`.
    case struggling
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
                .foregroundStyle(isProminent ? .white : JustTheme.Kawaii.accent)
                .frame(width: 42, height: 42)
                .background(
                    isProminent ? AnyShapeStyle(JustTheme.Accent.gradient) : AnyShapeStyle(JustTheme.Kawaii.accent.opacity(0.10)),
                    in: .circle
                )

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
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(JustTheme.Kawaii.accent, in: .capsule)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(JustTheme.Ink.secondary)
        }
        .padding(JustTheme.Space.snug)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.86), in: .rect(cornerRadius: JustTheme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: JustTheme.Radius.card)
                .strokeBorder(.white.opacity(0.72), lineWidth: 0.8)
        }
        .shadow(color: JustTheme.Kawaii.accent.opacity(isProminent ? 0.14 : 0.06), radius: 12, y: 5)
    }
}
