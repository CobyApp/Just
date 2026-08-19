import Charts
import JustCore
import JustDesign
import SwiftData
import SwiftUI

/// The landing tab: what to do today, and proof of what was done already.
struct HomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context

    @Query(sort: \StudySong.lastOpenedAt, order: .reverse) private var songs: [StudySong]

    @State private var stats: StudyStats = .empty
    @State private var showsSettings = false

    /// Cards a day is considered "done" at. Arbitrary but has to be something
    /// for the ring to have a denominator.
    private let dailyGoal = 20

    private var store: JustStore { JustStore(context: context) }

    var body: some View {
        NavigationStack {
            ZStack {
                JustTheme.Surface.base.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: JustTheme.Space.section) {
                        header
                        if stats.weeklyReviewed > 0 { weekChart }
                        if !songs.isEmpty { continueSection }
                    }
                    .padding(.vertical, JustTheme.Space.regular)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("오늘")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("설정", systemImage: "gearshape") { showsSettings = true }
                }
            }
            .sheet(isPresented: $showsSettings) { SettingsScreen() }
            .navigationDestination(for: ReviewRoute.self) { _ in ReviewScreen() }
            .onAppear {
                stats = store.stats()
                store.publishWidgetSnapshot(stats)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: JustTheme.Space.regular) {
            StreakRing(
                streak: stats.streak,
                progress: Double(stats.reviewedToday) / Double(dailyGoal)
            )

            Text(headline)
                .font(JustTheme.Font.body)
                .foregroundStyle(JustTheme.Ink.secondary)
                .multilineTextAlignment(.center)

            if stats.dueCount > 0 {
                NavigationLink(value: ReviewRoute()) {
                    Label("복습 \(stats.dueCount)개 시작", systemImage: "sparkles")
                }
                .buttonStyle(.justPrimary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, JustTheme.Space.regular)
    }

    private var headline: String {
        if stats.totalWords == 0 {
            return "노래를 열어 가사에서 단어를 담아 보세요."
        }
        if stats.dueCount > 0 {
            return "오늘 \(stats.reviewedToday)개 복습했고, \(stats.dueCount)개가 남았습니다."
        }
        return stats.reviewedToday > 0
            ? "오늘 \(stats.reviewedToday)개 복습했습니다. 남은 카드가 없습니다."
            : "지금 올라온 카드가 없습니다. 새 곡을 공부해 볼까요?"
    }

    // MARK: - Week

    private var weekChart: some View {
        VStack(alignment: .leading, spacing: JustTheme.Space.snug) {
            HStack(alignment: .firstTextBaseline) {
                Text("이번 주").font(JustTheme.Font.title)
                    .foregroundStyle(JustTheme.Ink.primary)
                Spacer()
                Text("\(stats.weeklyReviewed)개")
                    .font(JustTheme.Font.caption.monospacedDigit())
                    .foregroundStyle(JustTheme.Ink.tertiary)
            }

            Chart(stats.week) { day in
                BarMark(
                    x: .value("날짜", day.day, unit: .day),
                    y: .value("복습", day.reviewed),
                    width: .fixed(18)
                )
                .clipShape(.capsule)
                .foregroundStyle(JustTheme.Accent.gradient)
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                    AxisGridLine().foregroundStyle(JustTheme.Ink.hairline)
                    AxisValueLabel().foregroundStyle(JustTheme.Ink.tertiary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(
                        format: .dateTime.weekday(.narrow),
                        centered: true
                    )
                    .foregroundStyle(JustTheme.Ink.tertiary)
                }
            }
            .frame(height: 132)
        }
        .padding(.horizontal, JustTheme.Space.regular)
    }

    // MARK: - Continue

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: JustTheme.Space.snug) {
            Text("이어서 공부하기")
                .font(JustTheme.Font.title)
                .foregroundStyle(JustTheme.Ink.primary)
                .padding(.horizontal, JustTheme.Space.regular)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: JustTheme.Space.snug) {
                    ForEach(songs.prefix(10)) { song in
                        Button { app.open(song.track) } label: {
                            VStack(alignment: .leading, spacing: JustTheme.Space.tight) {
                                ArtworkTile(track: song.track, width: 168)
                                if !song.difficulty.isEmpty {
                                    DifficultyBar(
                                        difficulty: song.difficulty,
                                        height: 4,
                                        showsLegend: false
                                    )
                                    .frame(width: 168)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, JustTheme.Space.regular)
            }
            .scrollIndicators(.hidden)
        }
    }
}
