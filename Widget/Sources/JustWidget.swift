import JustCore
import SwiftUI
import WidgetKit

/// The home screen widget: how many cards are waiting, and one word to look at.
///
/// Reads a snapshot the app publishes rather than the app's database — see
/// `WidgetSnapshot`. A missing file means the app has not run since install, so
/// the placeholder stands in rather than showing zeroes as if they were real.
struct JustWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct JustWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> JustWidgetEntry {
        JustWidgetEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (JustWidgetEntry) -> Void) {
        completion(JustWidgetEntry(date: .now, snapshot: WidgetStore.read() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JustWidgetEntry>) -> Void) {
        let snapshot = WidgetStore.read() ?? .placeholder
        let now = Date.now
        // One entry per moment the numbers change — each card coming due, and
        // the midnights where the streak can lapse — worked out from the
        // schedule the snapshot carries, so the counts stay right while the
        // app is closed. The app reloads the timeline whenever it writes a
        // new snapshot; `.atEnd` covers the stretch after the last entry.
        let dates = [now] + snapshot.timelineDates(after: now)
        let entries = dates.map { JustWidgetEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct JustWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: JustWidgetEntry

    private var dueCount: Int { entry.snapshot.dueCount(at: entry.date) }
    private var streak: Int { entry.snapshot.streak(at: entry.date) }

    var body: some View {
        switch family {
        case .systemSmall:
            small
        default:
            medium
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 0)
            if let word = entry.snapshot.word {
                Text(word.reading)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(word.lemma)
                    .font(.system(size: 28, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(word.meaningKo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("가사에서 단어를 담아 보세요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                header
                Spacer(minLength: 0)
                Label("\(streak)일 연속", systemImage: "flame")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("\(entry.snapshot.totalWords)개 모음", systemImage: "character.book.closed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let word = entry.snapshot.word {
                VStack(alignment: .leading, spacing: 4) {
                    Text(word.reading)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(word.lemma)
                        .font(.system(size: 32, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(word.meaningKo)
                        .font(.footnote)
                        .lineLimit(2)
                    if let song = word.songLabel {
                        Text(song)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "music.note")
                .foregroundStyle(Color(red: 1.0, green: 0.37, blue: 0.56))
            Text(dueCount > 0 ? "복습 \(dueCount)개" : "오늘 복습 완료")
                .foregroundStyle(dueCount > 0 ? .primary : .secondary)
        }
        .font(.system(.caption, design: .rounded, weight: .bold))
    }
}

struct JustWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "JustWidget", provider: JustWidgetProvider()) { entry in
            JustWidgetView(entry: entry)
                // The background is a fixed cream, so the ink must be fixed
                // too: left to follow the system, `.primary` and `.secondary`
                // turned near-white in dark mode and the text vanished into
                // the cream.
                .environment(\.colorScheme, .light)
                .containerBackground(Color(red: 1.0, green: 0.98, blue: 0.96), for: .widget)
                // Tapping the widget lands on the cards, not on wherever the
                // app happened to be left.
                .widgetURL(URL(string: entry.snapshot.dueCount(at: entry.date) > 0 ? "just://review" : "just://words"))
        }
        .configurationDisplayName("우타링")
        .description("복습할 단어 수와 오늘 볼 단어를 보여줍니다.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct JustWidgetBundle: WidgetBundle {
    var body: some Widget {
        JustWidget()
    }
}
