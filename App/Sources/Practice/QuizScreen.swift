import JustCore
import JustDesign
import JustSensei
import SwiftData
import SwiftUI

/// Typed and multiple-choice practice over saved vocabulary.
///
/// Answers feed straight back into the FSRS schedule rather than into a
/// separate score: getting a word right in a quiz is evidence of recall, and
/// throwing that away would mean the review queue learns nothing from practice.
struct QuizScreen: View {
    /// nil mixes the question types.
    let kind: QuizKind?
    /// Which words the round draws from.
    var scope: QuizScope = .all

    @Environment(\.modelContext) private var context
    @Query private var entries: [VocabEntry]

    @State private var questions: [QuizQuestion] = []
    @State private var index = 0
    @State private var input = ""
    @State private var outcome: QuizOutcome?
    @State private var correctCount = 0
    @FocusState private var isTyping: Bool

    private let checker = AnswerChecker()
    private var store: JustStore { JustStore(context: context) }
    private var question: QuizQuestion? {
        index < questions.count ? questions[index] : nil
    }

    var body: some View {
        ZStack {
            JustBrandBackground()

            if let question {
                card(question)
            } else if questions.isEmpty {
                JustEmptyState(
                    icon: "square.dashed",
                    title: "연습할 단어가 없습니다",
                    message: "가사에서 단어를 담으면 그 단어로 문제를 만듭니다."
                )
            } else {
                summary
            }
        }
        .navigationTitle(scope == .struggling ? "어려운 단어" : (kind?.title ?? "랜덤 믹스"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear(perform: start)
        // Asked out loud as soon as it is on screen: a listening question that
        // waits to be tapped reads as a broken one. Keyed on the question so
        // moving to the next line asks the next line.
        .task(id: question?.id) {
            guard let question, question.kind == .dictation else { return }
            speak(question)
        }
        .onDisappear { Pronouncer.shared.stop() }
    }

    // MARK: - Question

    private func card(_ question: QuizQuestion) -> some View {
        VStack(spacing: JustTheme.Space.loose) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: JustTheme.Space.loose) {
                        JustProgressHeader(current: index + 1, total: questions.count)
                        JustActionHint(instruction(for: question), symbol: instructionSymbol(for: question.kind))
                        prompt(question).justCard()
                        if question.kind.isTyped {
                            typedField
                        } else {
                            choices(question)
                        }
                        if let outcome {
                            feedback(question, outcome)
                                .id("feedback")
                        }
                    }
                    .padding(JustTheme.Space.regular)
                }
                .scrollIndicators(.hidden)
                // The verdict lands below the answer, which on a phone is under
                // the action bar. Brought into view, so grading is never a card
                // the reader has to know to scroll for.
                .onChange(of: outcome != nil) { _, graded in
                    guard graded else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("feedback", anchor: .bottom)
                    }
                }
            }

            actionBar(question)
                .padding(JustTheme.Space.regular)
        }
    }

    private func prompt(_ question: QuizQuestion) -> some View {
        VStack(spacing: JustTheme.Space.snug) {
            Text(question.kind.title).justSectionHeader()

            // The lyric is the prompt for cloze and dictation, so it gets
            // lyric-sized type.
            Text(question.prompt)
                .font(
                    Self.showsLyricPrompt(question.kind)
                        ? JustTheme.Font.lyricActive
                        : .just(30, weight: .semibold, relativeTo: .title1)
                )
                .foregroundStyle(JustTheme.Ink.primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if question.kind == .dictation {
                replayButton(question)
            }

            if let detail = displayedContext(question) {
                Text(detail)
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(JustTheme.Ink.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, JustTheme.Space.loose)
    }

    private func instruction(for question: QuizQuestion) -> String {
        switch question.kind {
        case .cloze:
            "가사의 빈칸에 들어갈 일본어 단어를 입력하세요. 로마자로 써도 됩니다."
        case .recall:
            "보이는 한국어 뜻에 맞는 일본어 단어를 입력하세요. 로마자로 써도 됩니다."
        case .choice:
            "일본어 단어와 맞는 한국어 뜻 하나를 눌러 선택하세요."
        case .dictation:
            "재생되는 가사를 듣고 빈칸의 일본어 단어를 입력하세요. 다시 듣기도 가능합니다."
        }
    }

    private func instructionSymbol(for kind: QuizKind) -> String {
        switch kind {
        case .cloze: "rectangle.and.pencil.and.ellipsis"
        case .recall: "pencil.line"
        case .choice: "hand.tap.fill"
        case .dictation: "ear.fill"
        }
    }

    /// For cloze and dictation the meaning is withheld until the answer is in —
    /// printing it under the gap hands over the answer, which is the one thing
    /// the exercise is testing.
    private func displayedContext(_ question: QuizQuestion) -> String? {
        guard Self.showsLyricPrompt(question.kind), outcome == nil else {
            return question.context
        }
        return question.songLabelOnly
    }

    /// The kinds whose prompt is a lyric line rather than a word or a meaning.
    private static func showsLyricPrompt(_ kind: QuizKind) -> Bool {
        kind == .cloze || kind == .dictation
    }

    /// Says the line again.
    ///
    /// Prominent rather than tucked away: in a listening exercise this is not a
    /// convenience, it is how the question is asked, and a learner who missed a
    /// word needs it more than once.
    private func replayButton(_ question: QuizQuestion) -> some View {
        Button {
            speak(question)
        } label: {
            Label("다시 듣기", systemImage: "arrow.trianglehead.counterclockwise")
        }
        .buttonStyle(.justSecondary)
    }

    /// Reads the line, if there is one to read.
    private func speak(_ question: QuizQuestion) {
        guard let line = question.spokenLine else { return }
        Pronouncer.shared.speakLine(line)
    }

    private var typedField: some View {
        VStack(spacing: JustTheme.Space.tight) {
            TextField("답 입력", text: $input)
                .textFieldStyle(.plain)
                .font(.just(26, weight: .medium, relativeTo: .title2))
                .multilineTextAlignment(.center)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                // Forces a Latin keyboard whatever the user's locale is. A
                // Korean learner's keyboard is usually Korean, and typing
                // "yume" on it produces 자모, not romaji — so the romaji
                // fallback would never see ASCII to work with.
                .keyboardType(.asciiCapable)
                .focused($isTyping)
                .disabled(outcome != nil)
                .onSubmit(submit)
                .padding(.vertical, JustTheme.Space.snug)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(underlineColor).frame(height: 2)
                }

            // Shows the romaji turning into kana as it is typed, so the user
            // can see their input landing instead of trusting it blindly.
            if let preview = kanaPreview {
                Text(preview)
                    .font(.just(20, weight: .medium, relativeTo: .title3))
                    .foregroundStyle(JustTheme.Ink.secondary)
                    .transition(.opacity)
            } else {
                Text("일본어 키보드가 없으면 로마자로 써도 됩니다 (yume → ゆめ)")
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(JustTheme.Ink.tertiary)
            }
        }
    }

    /// nil when the input is already kana, or when conversion changed nothing.
    private var kanaPreview: String? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isASCII) else { return nil }
        let kana = trimmed.romajiToHiragana()
        return kana == trimmed ? nil : kana
    }

    private var underlineColor: Color {
        switch outcome {
        case .correct: JustTheme.Feedback.success
        case .close: JustTheme.Feedback.warning
        case .wrong: JustTheme.Feedback.error
        case nil: JustTheme.Ink.hairline
        }
    }

    private func choices(_ question: QuizQuestion) -> some View {
        VStack(spacing: JustTheme.Space.tight) {
            ForEach(question.options, id: \.self) { option in
                Button {
                    input = option
                    submit()
                } label: {
                    HStack {
                        Text(option)
                            .font(JustTheme.Font.body)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if outcome != nil, option == question.meaning {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(JustTheme.Feedback.success)
                        }
                    }
                    .padding(JustTheme.Space.snug)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        optionBackground(option, question: question),
                        in: .rect(cornerRadius: JustTheme.Radius.card)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: JustTheme.Radius.card)
                            .strokeBorder(JustTheme.Surface.border, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(outcome != nil)
            }
        }
    }

    private func optionBackground(_ option: String, question: QuizQuestion) -> Color {
        guard outcome != nil else { return JustTheme.Surface.raised }
        if option == question.meaning { return JustTheme.Feedback.success.opacity(0.16) }
        if option == input { return JustTheme.Feedback.error.opacity(0.14) }
        return JustTheme.Surface.raised
    }

    private func feedback(_ question: QuizQuestion, _ outcome: QuizOutcome) -> some View {
        VStack(alignment: .leading, spacing: JustTheme.Space.tight) {
            Text(label(for: outcome))
                .font(JustTheme.Font.body.weight(.semibold))
                .foregroundStyle(color(for: outcome))

            HStack(alignment: .firstTextBaseline, spacing: JustTheme.Space.tight) {
                RubyText(
                    segments: Furigana.segments(
                        surface: question.expected,
                        reading: question.expectedReading
                    ),
                    font: JustTheme.Font.japanese,
                    color: JustTheme.Ink.primary
                )
                Text(question.meaning)
                    .font(JustTheme.Font.body)
                    .foregroundStyle(JustTheme.Ink.secondary)
                Spacer(minLength: JustTheme.Space.tight)
                SpeakButton(word: question.expected, reading: question.expectedReading)
            }

            KanjiGlossStrip(word: question.expected)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .justCard()
    }

    private func label(for outcome: QuizOutcome) -> String {
        switch outcome {
        case .correct: "정답"
        case .close: "거의 맞았어요 — 형태가 다릅니다"
        case .wrong: "다시 볼까요"
        }
    }

    private func color(for outcome: QuizOutcome) -> Color {
        switch outcome {
        case .correct: JustTheme.Feedback.success
        case .close: JustTheme.Feedback.warning
        case .wrong: JustTheme.Feedback.error
        }
    }

    private func actionBar(_ question: QuizQuestion) -> some View {
        Group {
            if outcome == nil {
                Button {
                    if !question.kind.isTyped { input = "" }
                    submit()
                } label: {
                    Text(question.kind.isTyped ? "답 확인하기" : "모르겠어요 · 정답 보기")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.justPrimary)
            } else {
                Button { advance() } label: {
                    Text(index + 1 < questions.count ? "다음 문제" : "결과 보기")
                        .frame(maxWidth: .infinity)
                }
                    .buttonStyle(.justPrimary)
            }
        }
    }

    // MARK: - Summary

    private var summary: some View {
        VStack(spacing: JustTheme.Space.regular) {
            JustIconBadge(correctCount == questions.count ? "checkmark" : "flag.checkered", size: 64)
            Text("\(correctCount) / \(questions.count)")
                .font(.just(44, weight: .bold, relativeTo: .largeTitle).monospacedDigit())
                .foregroundStyle(JustTheme.Ink.primary)
            Text("복습 일정에 반영했습니다")
                .font(JustTheme.Font.body)
                .foregroundStyle(JustTheme.Ink.secondary)
            Button("한 번 더") { start() }
                .buttonStyle(.justPrimary)

            // The round is over, so the screen is not being used for anything.
            // Kept clear of the button above it.
            AdBanner(unitID: AdBanner.testUnitID)
                // Inset like the card above it, not a strip across the screen.
                .padding(.horizontal, JustTheme.Space.regular)
                .padding(.top, JustTheme.Space.loose)
        }
        .justCard()
        .padding(JustTheme.Space.regular)
    }

    // MARK: - Flow

    private func start() {
        questions = QuizBuilder().build(from: sources(), kind: kind)
        index = 0
        input = ""
        outcome = nil
        correctCount = 0
        isTyping = questions.first?.kind.isTyped ?? false
    }

    private func submit() {
        guard let question, outcome == nil else { return }
        let result = question.kind == .choice
            ? (input == question.meaning ? QuizOutcome.correct : .wrong)
            : checker.check(input, against: question)

        outcome = result
        if result == .correct { correctCount += 1 }
        isTyping = false

        switch result {
        case .correct: Haptics.correct()
        case .close: Haptics.nearMiss()
        case .wrong: Haptics.wrong()
        }

        if let entry = store.vocab(key: question.entryKey) {
            store.grade(entry, result.grade)
        }
    }

    private func advance() {
        input = ""
        outcome = nil
        index += 1
        isTyping = question?.kind.isTyped ?? false
    }

    private func sources() -> [QuizBuilder.Source] {
        let pool = scope == .struggling ? store.strugglingEntries() : entries
        return pool.map { entry in
            // The most recently captured occurrence gives the freshest lyric.
            let occurrence = entry.occurrences.max { $0.capturedAt < $1.capturedAt }
            return QuizBuilder.Source(
                key: entry.key,
                lemma: entry.lemma,
                reading: entry.reading,
                meaning: entry.meaningKo,
                lineText: occurrence?.lineText,
                surface: occurrence?.surface,
                songLabel: occurrence?.song.map { "\($0.artist) — \($0.title)" }
            )
        }
    }
}
