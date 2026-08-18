import JustCore
import JustDesign
import JustSensei
import SwiftData
import SwiftUI

struct LibraryScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context

    @Query(sort: \StudySong.lastOpenedAt, order: .reverse) private var songs: [StudySong]
    @Query(sort: \VocabEntry.createdAt, order: .reverse) private var words: [VocabEntry]

    @State private var mode: Mode = .words
    @State private var levelFilter: JLPTLevel?
    @State private var search = ""

    private enum Mode: String, CaseIterable {
        case words = "단어"
        case songs = "곡"
    }

    private var filteredWords: [VocabEntry] {
        words.filter { entry in
            if let levelFilter, entry.jlpt != levelFilter { return false }
            guard !search.isEmpty else { return true }
            return entry.lemma.contains(search)
                || entry.reading.contains(search)
                || entry.meaningKo.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                JustTheme.Surface.base.ignoresSafeArea()
                content
            }
            .navigationTitle("보관함")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
            .searchable(text: $search, prompt: mode == .words ? "단어, 뜻" : "곡, 아티스트")
            .navigationDestination(for: VocabEntry.self) { VocabDetailView(entry: $0) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .words:
            if words.isEmpty {
                ContentUnavailableView {
                    Label("아직 저장한 단어가 없습니다", systemImage: "character.book.closed")
                } description: {
                    Text("가사에서 줄을 눌러 단어를 담으면 여기에 모입니다.")
                }
            } else {
                List {
                    Section {
                        levelFilterBar
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    ForEach(filteredWords) { entry in
                        NavigationLink(value: entry) {
                            VocabRow(entry: entry)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(filteredWords[index]) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

        case .songs:
            if songs.isEmpty {
                ContentUnavailableView {
                    Label("곡이 없습니다", systemImage: "music.note.list")
                } description: {
                    Text("검색에서 곡을 열면 자동으로 보관함에 들어옵니다.")
                }
            } else {
                List(songs.filter {
                    search.isEmpty
                        || $0.title.localizedCaseInsensitiveContains(search)
                        || $0.artist.localizedCaseInsensitiveContains(search)
                }) { song in
                    TrackRow(track: song.track, progress: song.studyProgress)
                        .contentShape(.rect)
                        .onTapGesture { app.open(song.track) }
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var levelFilterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                filterChip(nil, label: "전체")
                ForEach(JLPTLevel.allCases, id: \.self) { level in
                    filterChip(level, label: level.label)
                }
            }
            .padding(.horizontal, JustTheme.Space.regular)
            .padding(.vertical, JustTheme.Space.tight)
        }
        .scrollIndicators(.hidden)
    }

    private func filterChip(_ level: JLPTLevel?, label: String) -> some View {
        let isSelected = levelFilter == level
        return Button {
            levelFilter = isSelected ? nil : level
        } label: {
            Text(label)
                .font(JustTheme.Font.caption)
                .foregroundStyle(isSelected ? JustTheme.Surface.base : JustTheme.Ink.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ? JustTheme.Ink.primary : JustTheme.Surface.raised,
                    in: .capsule
                )
        }
        .buttonStyle(.plain)
    }
}

struct VocabRow: View {
    let entry: VocabEntry

    var body: some View {
        HStack(spacing: JustTheme.Space.snug) {
            VStack(alignment: .leading, spacing: 3) {
                RubyText(
                    segments: Furigana.segments(surface: entry.lemma, reading: entry.reading),
                    font: JustTheme.Font.japanese,
                    color: JustTheme.Ink.primary
                )
                Text(entry.meaningKo)
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(JustTheme.Ink.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: JustTheme.Space.tight)

            VStack(alignment: .trailing, spacing: 4) {
                JustChip(entry.jlpt.label, tint: entry.jlpt.tint)
                // The whole point of keying vocabulary globally: a word that
                // recurs across songs is a word worth knowing.
                if entry.occurrences.count > 1 {
                    Text("\(entry.occurrences.count)곳")
                        .font(JustTheme.Font.caption)
                        .foregroundStyle(JustTheme.Ink.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct VocabDetailView: View {
    let entry: VocabEntry
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            JustTheme.Surface.base.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: JustTheme.Space.loose) {
                    VStack(alignment: .leading, spacing: JustTheme.Space.tight) {
                        RubyText(
                            segments: Furigana.segments(
                                surface: entry.lemma,
                                reading: entry.reading
                            ),
                            font: .system(size: 34, weight: .semibold),
                            rubyFont: .system(size: 13, weight: .medium),
                            color: JustTheme.Ink.primary
                        )
                        Text(entry.meaningKo)
                            .font(.system(size: 18))
                            .foregroundStyle(JustTheme.Ink.primary)
                        HStack(spacing: 6) {
                            JustChip(entry.jlpt.label, tint: entry.jlpt.tint)
                            JustChip(entry.partOfSpeech.rawValue)
                        }
                        KanjiGlossStrip(word: entry.lemma)
                        if !entry.note.isEmpty {
                            Text(entry.note)
                                .font(JustTheme.Font.body)
                                .foregroundStyle(JustTheme.Ink.secondary)
                        }
                    }

                    if let review = entry.review {
                        VStack(alignment: .leading, spacing: JustTheme.Space.tight) {
                            Text("복습").justSectionHeader()
                            LabeledContent("다음 복습", value: review.due.formatted(.relative(presentation: .named)))
                            LabeledContent("복습 횟수", value: "\(review.reps)회")
                            if review.lapses > 0 {
                                LabeledContent("잊은 횟수", value: "\(review.lapses)회")
                            }
                        }
                        .font(JustTheme.Font.body)
                        .foregroundStyle(JustTheme.Ink.secondary)
                        .justCard()
                    }

                    VStack(alignment: .leading, spacing: JustTheme.Space.snug) {
                        Text("나온 곳").justSectionHeader()
                        ForEach(entry.occurrences.sorted(by: { $0.capturedAt > $1.capturedAt })) { occurrence in
                            OccurrenceCard(occurrence: occurrence) {
                                if let song = occurrence.song { app.open(song.track) }
                            }
                        }
                    }
                }
                .padding(JustTheme.Space.regular)
            }
        }
        .navigationTitle(entry.lemma)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct OccurrenceCard: View {
    let occurrence: VocabOccurrence
    let play: () -> Void

    var body: some View {
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
                Button(action: play) {
                    Label("\(song.artist) — \(song.title)", systemImage: "play.circle")
                        .font(JustTheme.Font.caption)
                        .foregroundStyle(JustTheme.Ink.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .justCard()
    }
}
