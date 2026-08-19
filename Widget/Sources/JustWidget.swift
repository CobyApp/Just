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
        let entry = JustWidgetEntry(date: .now, snapshot: WidgetStore.read() ?? .placeholder)
        // Cards come due on a schedule the widget cannot see, so it refreshes on
        // the hour rather than trying to predict the next one.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct JustWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: JustWidgetEntry

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
                Label("\(entry.snapshot.streak)일 연속", systemImage: "flame")
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
        Text(entry.snapshot.dueCount > 0 ? "복습 \(entry.snapshot.dueCount)개" : "복습 완료")
            .font(.caption.weight(.semibold))
            .foregroundStyle(entry.snapshot.dueCount > 0 ? .primary : .secondary)
    }
}

struct JustWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "JustWidget", provider: JustWidgetProvider()) { entry in
            JustWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                // Tapping the widget lands on the cards, not on wherever the
                // app happened to be left.
                .widgetURL(URL(string: entry.snapshot.dueCount > 0 ? "just://review" : "just://words"))
        }
        .configurationDisplayName("Just")
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
