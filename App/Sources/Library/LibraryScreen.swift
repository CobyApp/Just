import CoreTransferable
import RingRingCore
import RingRingDesign
import RingRingSensei
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryScreen: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \VocabEntry.createdAt, order: .reverse) private var words: [VocabEntry]

    @State private var levelFilter: JLPTLevel?
    @State private var showsGrammar = false
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
                JustBrandBackground()
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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            // The title and the sort control are drawn in the content; a bar
            // for nothing was a blank strip. Pushed screens keep their own.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: VocabEntry.self) { VocabDetailView(entry: $0) }
            .navigationDestination(for: ReviewRoute.self) { _ in ReviewScreen() }
            // Recomputed on appear rather than observed: the counts change
            // only when the user grades or saves something, both of which
            // leave and return to this screen. On the root content, not on the
            // NavigationStack — the stack's own onAppear does not fire again
            // when a pushed review screen is popped, which left the counts
            // from before the review on screen.
            .onAppear(perform: refresh)
        }
        // A list screen, so bright. The player it opens stays dark.
        .environment(\.colorScheme, .light)
        .task(id: words.count) {
            refresh()
            // Adding and grading publish on their own; deleting a word here
            // does not, and the widget would go on counting it.
            store.publishActivity(stats: stats)
        }
    }

    private func refresh() {
        stats = store.stats()
    }

    private var emptyState: some View {
        JustEmptyState(
            icon: "character.book.closed",
            title: "아직 저장한 단어가 없습니다",
            message: "가사에서 줄을 눌러 단어를 담으면 여기에 모입니다.",
            actionTitle: "노래에서 단어 담기",
            action: { app.tab = .groups }
        )
    }

    private var wordList: some View {
        Group {
            List {
                Section {
                    HStack(alignment: .top, spacing: JustTheme.Space.snug) {
                        JustScreenHeader("단어장", subtitle: "노래에서 만난 일본어")
                        Spacer(minLength: 0)
                        sortMenu
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    searchField
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 14, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    libraryGuide
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    toolsRow
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
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
                    // The link is hidden behind the card for the same reason as
                    // the review card: the List's own chevron landed outside
                    // the card's border. The card draws one inside instead.
                    VocabRow(entry: entry)
                        .background {
                            NavigationLink(value: entry) { EmptyView() }.opacity(0)
                        }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(filteredWords[index]) }
                }
                // A filter or a search that matches nothing left the list
                // blank under the chips, which reads as the words having gone.
                if filteredWords.isEmpty {
                    noMatches
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationDestination(isPresented: $showsGrammar) { GrammarScreen() }
        .navigationDestination(for: GrammarRoute.self) { _ in GrammarScreen() }
    }

    /// The current order, in words, beside the title it orders. It used to be a
    /// toolbar item — but this screen draws its own title, so the toolbar was
    /// an empty bar with one button floating in it.
    private var sortMenu: some View {
        Menu {
            Picker("정렬", selection: $order) {
                ForEach(WordOrder.allCases) { Text($0.title).tag($0) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(order.title)
                Image(systemName: "arrow.up.arrow.down")
            }
            .font(JustTheme.Font.caption.weight(.semibold))
            .foregroundStyle(JustTheme.Kawaii.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(JustTheme.Surface.panel, in: .capsule)
            .overlay { Capsule().strokeBorder(JustTheme.Surface.border, lineWidth: 1) }
        }
        .padding(.top, 4)
    }

    /// In the content rather than `.searchable`: the system field lives in the
    /// navigation bar, and keeping the bar for it alone left a blank strip
    /// above the page.
    private var searchField: some View {
        HStack(spacing: JustTheme.Space.tight) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(JustTheme.Kawaii.inkSoft)
            TextField("단어, 뜻", text: $search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(JustTheme.Kawaii.ink)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(JustTheme.Kawaii.inkSoft)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("검색어 지우기")
            }
        }
        .padding(.horizontal, JustTheme.Space.snug)
        .padding(.vertical, 12)
        .background(JustTheme.Surface.panel, in: .capsule)
        .overlay { Capsule().strokeBorder(JustTheme.Surface.border, lineWidth: 1) }
    }

    private var libraryGuide: some View {
        JustFeatureGuide(
            "단어장은 이렇게 사용해요",
            detail: "저장한 단어는 원래 가사와 함께 남고, 퀴즈와 복습에 자동으로 사용됩니다.",
            steps: [
                JustGuideStep("hand.tap.fill", title: "단어 눌러 자세히 보기", detail: "읽기, 뜻, 나온 가사와 다음 복습일을 확인하세요."),
                JustGuideStep("clock.arrow.circlepath", title: "복습 시작", detail: "오늘 외울 단어만 일정에 맞춰 카드로 보여드려요."),
            ]
        )
            .dismissibleGuide("library.howto")
    }

    private var toolsRow: some View {
        HStack(spacing: JustTheme.Space.tight) {
            // A Button, not a NavigationLink: inside a List a link is drawn
            // as a list row with a chevron and its button style is ignored,
            // which left this half plain beside a capsule.
            Button {
                showsGrammar = true
            } label: {
                Label("모은 문법", systemImage: "text.book.closed")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.justSecondary)

            ShareLink(
                item: VocabularyCSV(container: context.container),
                preview: SharePreview("단어장 CSV", image: Image(systemName: "tablecells"))
            ) {
                Label("내보내기", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.justSecondary)
        }
    }

    /// Review is an action, not a place — so it reads as one call to action
    /// with the number on it, rather than a tab that is usually empty.
    private var reviewCard: some View {
        HStack(spacing: JustTheme.Space.snug) {
                Image(systemName: stats.dueCount > 0 ? "clock.arrow.circlepath" : "checkmark.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(stats.dueCount > 0 ? JustTheme.Kawaii.accent : JustTheme.Kawaii.lavender)
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
            .justSurface()
            // In a List a NavigationLink draws its own disclosure chevron next
            // to the card's. Hidden in the background, the row still navigates
            // and only the card's chevron shows.
            .background {
                NavigationLink(value: ReviewRoute()) { EmptyView() }.opacity(0)
            }
        .buttonStyle(.plain)
    }

    private var noMatches: some View {
        VStack(spacing: JustTheme.Space.tight) {
            Image(systemName: search.isEmpty ? "sparkle.magnifyingglass" : "magnifyingglass")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(JustTheme.Kawaii.accent.opacity(0.6))
            Text(noMatchesTitle)
                .font(JustTheme.Font.body.weight(.bold))
                .foregroundStyle(JustTheme.Ink.secondary)
            Button("모든 단어 보기") {
                levelFilter = nil
                search = ""
            }
            .buttonStyle(.justSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, JustTheme.Space.loose)
    }

    private var noMatchesTitle: String {
        if !search.isEmpty { return String(localized: "「\(search)」에 맞는 단어가 없어요") }
        if let levelFilter { return String(localized: "\(levelFilter.label) 단어는 아직 없어요") }
        return String(localized: "단어가 없어요")
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
                .foregroundStyle(isSelected ? .white : JustTheme.Ink.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ? JustTheme.Kawaii.accent : JustTheme.Surface.raised,
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
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
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

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(JustTheme.Ink.secondary)
        }
        .padding(.horizontal, JustTheme.Space.snug)
        .padding(.vertical, JustTheme.Space.tight)
        .justSurface()
    }
}

struct VocabDetailView: View {
    let entry: VocabEntry
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            JustBrandBackground()
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
                            .justFont(18, relativeTo: .body)
                            .foregroundStyle(JustTheme.Ink.primary)
                        HStack(spacing: 6) {
                            JustChip(entry.jlpt.label, tint: entry.jlpt.tint)
                            JustChip(entry.partOfSpeech.rawValue)
                            Spacer()
                            SpeakButton(word: entry.lemma, reading: entry.reading, size: 34)
                        }
                        KanjiGlossStrip(word: entry.lemma)
                        if !entry.note.isEmpty {
                            Text(entry.note)
                                .font(JustTheme.Font.body)
                                .foregroundStyle(JustTheme.Ink.secondary)
                        }
                    }

                    JustActionHint(
                        "스피커로 발음을 듣고, 아래 가사 카드를 누르면 해당 노래를 다시 열 수 있어요.",
                        symbol: "speaker.wave.2.fill"
                    )
                        .dismissibleGuide("library.detail")

                    if let review = entry.review {
                        VStack(alignment: .leading, spacing: JustTheme.Space.tight) {
                            Text("복습").justSectionHeader()
                            // A card past its date is due now, not 「34분 전」 — the past tense
                            // read as a review that had already happened.
                            LabeledContent(
                                "다음 복습",
                                value: review.due <= .now ? String(localized: "지금") : review.due.formatted(.relative(presentation: .named))
                            )
                            LabeledContent("복습 횟수", value: String(localized: "\(review.reps)회"))
                            if review.lapses > 0 {
                                LabeledContent("잊은 횟수", value: String(localized: "\(review.lapses)회"))
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
                    HStack {
                        Label("곡에서 다시 듣기", systemImage: "play.circle.fill")
                            .font(JustTheme.Font.caption.weight(.semibold))
                            .foregroundStyle(JustTheme.Kawaii.accent)
                        Spacer(minLength: JustTheme.Space.tight)
                        Text("\(song.title) · \(song.artist)")
                            .font(JustTheme.Font.caption)
                            .foregroundStyle(JustTheme.Ink.tertiary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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

/// Empty route value — the grammar list takes no parameters.
struct GrammarRoute: Hashable {}

/// Every saved word as a CSV file, built only when the share sheet asks for it.
///
/// Anki and spreadsheets both read this; the header is Korean because the
/// person importing it is. It used to be a computed property that fetched the
/// whole library and wrote the file on every render of the screen — typing one
/// letter into the search field rewrote it. Carrying only the container keeps
/// the value free to create; the work happens once, off the main actor, when
/// the user actually shares.
struct VocabularyCSV: Transferable {
    let container: ModelContainer

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { csv in
            // A context of its own: this runs off the main actor, where the
            // view's context must not be touched.
            let rows = JustStore.exportRows(in: ModelContext(csv.container))
            guard let url = VocabularyExport.writeFile(rows: rows) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return SentTransferredFile(url)
        }
    }
}
