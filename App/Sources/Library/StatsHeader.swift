import Charts
import JustCore
import JustDesign
import SwiftUI

/// The study summary at the top of the word list.
///
/// Three numbers, chosen because they answer the three questions a learner
/// actually has when they open a vocabulary list: is there anything to do right
/// now, am I keeping it up, and how much have I collected.
struct StatsHeader: View {
    let stats: StudyStats

    var body: some View {
        VStack(spacing: JustTheme.Space.snug) {
            metrics
            if !stats.levelBreakdown.isEmpty { levelChart }
        }
        .padding(.vertical, JustTheme.Space.snug)
        .background(JustTheme.Surface.raised, in: .rect(cornerRadius: JustTheme.Radius.card))
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            metric(
                value: "\(stats.dueCount)",
                label: "복습 대기",
                emphasised: stats.dueCount > 0
            )
            divider
            metric(
                // A streak reads as an achievement, so it carries a unit.
                value: stats.streak > 0 ? "\(stats.streak)일" : "—",
                label: "연속",
                emphasised: false
            )
            divider
            metric(value: "\(stats.totalWords)", label: "모은 단어", emphasised: false)
        }
    }

    /// Where the collection actually sits on the JLPT scale.
    ///
    /// A total word count says nothing about level; this is what tells the user
    /// whether they have been collecting N5 filler or real N2 vocabulary.
    private var levelChart: some View {
        VStack(alignment: .leading, spacing: JustTheme.Space.tight) {
            Divider().overlay(JustTheme.Ink.hairline)
            Text("등급 분포").justSectionHeader()
            Chart(stats.levelBreakdown, id: \.level) { slice in
                BarMark(
                    x: .value("개수", slice.count),
                    y: .value("등급", slice.level.label)
                )
                .clipShape(.capsule)
                .foregroundStyle(slice.level.tint)
                .annotation(position: .trailing) {
                    Text("\(slice.count)")
                        .font(JustTheme.Font.caption.monospacedDigit())
                        .foregroundStyle(JustTheme.Ink.tertiary)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisValueLabel().foregroundStyle(JustTheme.Ink.secondary)
                }
            }
            .frame(height: CGFloat(stats.levelBreakdown.count) * 26 + 8)
        }
        .padding(.horizontal, JustTheme.Space.snug)
    }

    private var divider: some View {
        Rectangle()
            .fill(JustTheme.Ink.hairline)
            .frame(width: 0.5, height: 28)
    }

    private func metric(value: String, label: String, emphasised: Bool) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.just(20, weight: .semibold, relativeTo: .title3).monospacedDigit())
                .foregroundStyle(emphasised ? JustTheme.Ink.primary : JustTheme.Ink.secondary)
            Text(label)
                .font(JustTheme.Font.caption)
                .foregroundStyle(JustTheme.Ink.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
