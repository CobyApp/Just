import JustCore
import JustDesign
import JustSensei
import SwiftData
import SwiftUI

struct LibraryScreen: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \VocabEntry.createdAt, order: .reverse) private var words: [VocabEntry]

    @State private var levelFilter: JLPTLevel?
    @State private var search = ""
    @State private var order: WordOrder = .added

    @Environment(AppModel.self) private var app

    @State private var stats: StudyStats = .empty

    private var store: JustStore { JustStore(context: context) }

    private var filteredWords: [VocabEntry] {
        let matches = words.filter { entry in
            if let levelFilter, entry.jlpt != levelFilter { return false }
            guard !search.isEmpty else { return true }
            return entry.lemma.contains(search)
                || entry.reading.contains(search)
                || entry.meaningKo.localizedCaseInsensitiveContains(search)
        }
        return order.sort(matches)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                JustTheme.Surface.base.ignoresSafeArea()
                // The search field and the sort control are only attached once
                // there is something to search and sort. Offering them over an
                // empty list asks the reader to rule out two things that could
                // not have helped.
                if words.isEmpty {
                    emptyState
                } else {
                    wordList
                }
            }
            .navigationTitle("단어장")
            .navigationDestination(for: VocabEntry.self) { VocabDetailView(entry: $0) }
            .navigationDestination(for: ReviewRoute.self) { _ in ReviewScreen() }
        }
        // Recomputed on appear rather than observed: the counts change only
        // when the user grades or saves something, both of which leave and
        // return to this screen.
        .onAppear(perform: refresh)
        .task(id: words.count) { refresh() }
    }

    private func refresh() {
        stats = store.stats()
        store.publishWidgetSnapshot(stats)
        Task { await app.reminder.updateBadge(dueCount: stats.dueCount) }
    }

    private var emptyState: some View {
        JustEmptyState(
            icon: "character.book.closed",
            title: "아직 저장한 단어가 없습니다",
            message: "가사에서 줄을 눌러 단어를 담으면 여기에 모입니다.",
            actionTitle: "곡 보러 가기",
            action: { app.tab = .browse }
        )
    }

    private var wordList: some View {
        Group {
            List {
                Section {
                    StatsHeader(stats: stats)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    reviewCard
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    levelFilterBar
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
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
        .searchable(text: $search, prompt: "단어, 뜻")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("정렬", selection: $order) {
                        ForEach(WordOrder.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    // The current order, in words. An anonymous ↑↓ said neither
                    // what the button was nor what it was set to.
                    //
                    // Spelled out as an HStack rather than a Label: a toolbar
                    // collapses `Label` to its icon whatever `labelStyle` asks
                    // for, which is how the text went missing the first time.
                    HStack(spacing: 4) {
                        Text(order.title)
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .font(JustTheme.Font.caption.weight(.semibold))
                }
            }
        }
    }

    /// Review is an action, not a place — so it reads as one call to action
    /// with the number on it, rather than a tab that is usually empty.
    private var reviewCard: some View {
        NavigationLink(value: ReviewRoute()) {
            HStack(spacing: JustTheme.Space.snug) {
                Image(systemName: stats.dueCount > 0 ? "sparkles" : "checkmark.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(JustTheme.Ink.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stats.dueCount > 0 ? "복습 시작" : "오늘 복습 끝")
                        .font(JustTheme.Font.body.weight(.semibold))
                        .foregroundStyle(JustTheme.Ink.primary)
                    Text(
                        stats.dueCount > 0
                            ? "가사 예문과 함께 \(stats.dueCount)개"
                            : "다음 카드는 일정에 맞춰 올라옵니다"
                    )
                        .font(JustTheme.Font.caption)
                        .foregroundStyle(JustTheme.Ink.tertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(JustTheme.Ink.secondary)
            }
            .padding(JustTheme.Space.snug)
            .background(JustTheme.Surface.raised, in: .rect(cornerRadius: JustTheme.Radius.card))
        }
        .buttonStyle(.plain)
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
                .font(JustTheme.Font.caption.weight(.semibold))
                .foregroundStyle(isSelected ? JustTheme.Surface.base : JustTheme.Ink.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ? JustTheme.Ink.primary : JustTheme.Surface.raised,
                    in: .capsule
                )
                .overlay {
                    Capsule().strokeBorder(
                        isSelected ? .clear : JustTheme.Ink.hairline,
                        lineWidth: 0.5
                    )
                }
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
                            font: .just(34, weight: .semibold, relativeTo: .largeTitle),
                            rubyFont: .just(13, weight: .medium, relativeTo: .caption2),
                            color: JustTheme.Ink.primary
                        )
                        Text(entry.meaningKo)
                            .font(.just(18, relativeTo: .body))
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

/// How the word list is ordered.
enum WordOrder: String, CaseIterable, Identifiable {
    case added
    case level
    case due
    case frequency

    var id: String { rawValue }

    var title: String {
        switch self {
        case .added: "담은 순"
        case .level: "등급 순"
        case .due: "복습 임박 순"
        case .frequency: "여러 곡에 나온 순"
        }
    }

    func sort(_ entries: [VocabEntry]) -> [VocabEntry] {
        switch self {
        case .added:
            entries.sorted { $0.createdAt > $1.createdAt }
        case .level:
            entries.sorted { $0.jlpt < $1.jlpt }
        case .due:
            entries.sorted {
                ($0.review?.due ?? .distantFuture) < ($1.review?.due ?? .distantFuture)
            }
        case .frequency:
            // The words worth prioritising: recurring across songs means
            // recurring in the language.
            entries.sorted { $0.occurrences.count > $1.occurrences.count }
        }
    }
}
