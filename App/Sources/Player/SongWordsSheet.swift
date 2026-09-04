import JustCore
import JustDesign
import JustSensei
import SwiftUI

/// The words collected from one song.
///
/// The word list answers "where did I see this?" per word; this answers the
/// other direction — "what did I get out of this song?" — which is the question
/// you have right after finishing one.
struct SongWordsSheet: View {
    let song: StudySong

    @Environment(\.dismiss) private var dismiss

    /// Deduplicated because a word can appear on several lines of the same song.
    private var entries: [VocabEntry] {
        var seen = Set<String>()
        return song.occurrences
            .sorted { $0.lineIndex < $1.lineIndex }
            .compactMap(\.vocab)
            .filter { seen.insert($0.key).inserted }
    }

    private var difficulty: SongDifficulty {
        SongDifficulty(
            counts: entries.reduce(into: [:]) { counts, entry in
                counts[entry.jlpt, default: 0] += 1
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                JustBrandBackground()

                if entries.isEmpty {
                    JustEmptyState(
                        icon: "character.book.closed",
                        title: "담은 단어가 없습니다",
                        message: "가사 줄을 눌러 단어 카드에서 + 를 누르면 여기에 모입니다."
                    )
                } else {
                    List {
                        Section {
                            JustActionHint(
                                "이 노래에서 저장한 단어만 모아 봅니다. 전체 단어는 하단 ‘단어장’ 탭에서 확인하세요.",
                                symbol: "character.book.closed.fill"
                            )
                                .dismissibleGuide("songwords.hint")
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            DifficultyBar(difficulty: difficulty)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        } header: {
                            Text("담은 단어 \(entries.count)개").justSectionHeader()
                        }

                        ForEach(entries) { entry in
                            row(entry)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle(song.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private func row(_ entry: VocabEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                RubyText(
                    segments: Furigana.segments(surface: entry.lemma, reading: entry.reading),
                    font: JustTheme.Font.japanese,
                    color: JustTheme.Ink.primary
                )
                Spacer(minLength: JustTheme.Space.tight)
                JustChip(entry.jlpt.label, tint: entry.jlpt.tint)
            }
            Text(entry.meaningKo)
                .font(JustTheme.Font.body)
                .foregroundStyle(JustTheme.Ink.secondary)

            // The line it came from, so the word stays attached to the melody
            // rather than becoming another entry on a list.
            if let line = entry.occurrences.first(where: { $0.song?.videoID == song.videoID }) {
                Text(line.lineText)
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(JustTheme.Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .justCard()
        .padding(.vertical, 3)
    }
}
