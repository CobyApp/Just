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

    /// The favourite's colour when there is one — the widget is the app on
    /// the home screen, so it wears the same member colour as the tab bar.
    private var accent: Color {
        entry.snapshot.oshi.map { WidgetStyle.memberColor(hue: $0.hue) } ?? WidgetStyle.pink
    }

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
                wordSticker(word, lemmaSize: 26, showsSong: false)
            } else {
                emptyWord
            }
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                header
                Spacer(minLength: 0)
                Label("\(streak)일 연속", systemImage: "flame.fill")
                Label("\(entry.snapshot.totalWords)개 모음", systemImage: "heart.fill")
                if let oshi = entry.snapshot.oshi {
                    Label("최애 \(oshi.name)", systemImage: "crown.fill")
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }
            }
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(WidgetStyle.inkSoft)
            .labelStyle(.titleAndIcon)

            if let word = entry.snapshot.word {
                wordSticker(word, lemmaSize: 30, showsSong: true)
            } else {
                emptyWord
            }
        }
    }

    /// The count, as a candy pill: filled when there is something to do.
    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: dueCount > 0 ? "sparkles" : "checkmark")
                .font(.system(size: 11, weight: .black))
            Text(dueCount > 0 ? "복습 \(dueCount)개" : "오늘 복습 완료")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.system(.caption, design: .rounded, weight: .heavy))
        .foregroundStyle(dueCount > 0 ? .white : accent)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(dueCount > 0 ? accent : .white, in: .capsule)
        .overlay { Capsule().strokeBorder(dueCount > 0 ? .white : accent.opacity(0.45), lineWidth: 1.5) }
    }

    /// One word on a white sticker with a printed shadow.
    private func wordSticker(_ word: WidgetSnapshot.Word, lemmaSize: CGFloat, showsSong: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(word.reading)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .lineLimit(1)
            Text(word.lemma)
                .font(.system(size: lemmaSize, weight: .bold))
                .foregroundStyle(WidgetStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(word.meaningKo)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(WidgetStyle.inkSoft)
                .lineLimit(showsSong ? 2 : 1)
            if showsSong, let song = word.songLabel {
                Text("♪ \(song)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetStyle.inkSoft.opacity(0.75))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: .rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(0.35), lineWidth: 1.5) }
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(accent.opacity(0.35))
                .offset(x: 2, y: 3)
        }
    }

    private var emptyWord: some View {
        Text("가사에서 단어를 담아 보세요 ♡")
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(WidgetStyle.inkSoft)
    }
}

/// The app's colours, repeated here: the widget links JustCore only, and the
/// design module brings UIKit and far more than four colours need.
enum WidgetStyle {
    static let pink = Color(red: 1.0, green: 0.37, blue: 0.56)
    static let ink = Color(red: 0.22, green: 0.12, blue: 0.27)
    static let inkSoft = Color(red: 0.47, green: 0.35, blue: 0.50)

    /// Same rule as `IdolGroup.memberColor` in the app.
    static func memberColor(hue: Double) -> Color {
        let isYellowish = (0.08...0.24).contains(hue)
        return Color(hue: hue, saturation: 0.75, brightness: isYellowish ? 0.68 : 0.82)
    }
}

/// Pastel ground with a little glitter in the corners. Plain shapes and
/// text only — no Canvas, which widgets do not draw.
struct WidgetBackdrop: View {
    let accent: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 1.0, green: 0.94, blue: 0.97), Color(red: 0.95, green: 0.94, blue: 1.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text("✦").font(.system(size: 14)).foregroundStyle(accent.opacity(0.35))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(10)
            Text("♡").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(red: 0.6, green: 0.8, blue: 1.0).opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(8)
            Text("✧").font(.system(size: 10)).foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.4).opacity(0.8))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 6)
        }
    }
}

struct JustWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "JustWidget", provider: JustWidgetProvider()) { entry in
            JustWidgetView(entry: entry)
                // The background is a fixed pastel, so the ink must be fixed
                // too: left to follow the system, `.primary` and `.secondary`
                // turned near-white in dark mode and the text vanished into
                // the cream.
                .environment(\.colorScheme, .light)
                .containerBackground(for: .widget) {
                    WidgetBackdrop(
                        accent: entry.snapshot.oshi.map { WidgetStyle.memberColor(hue: $0.hue) } ?? WidgetStyle.pink
                    )
                }
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
