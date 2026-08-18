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
            JustTheme.Surface.base.ignoresSafeArea()

            if let question {
                card(question)
            } else if questions.isEmpty {
                ContentUnavailableView {
                    Label("연습할 단어가 없습니다", systemImage: "square.dashed")
                } description: {
                    Text("가사에서 단어를 담으면 그 단어로 문제를 만듭니다.")
                }
            } else {
                summary
            }
        }
        .navigationTitle(kind?.title ?? "랜덤 믹스")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if question != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(index + 1) / \(questions.count)")
                        .font(JustTheme.Font.caption.monospacedDigit())
                        .foregroundStyle(JustTheme.Ink.tertiary)
                }
            }
        }
        .onAppear(perform: start)
    }

    // MARK: - Question

    private func card(_ question: QuizQuestion) -> some View {
        VStack(spacing: JustTheme.Space.loose) {
            ScrollView {
                VStack(spacing: JustTheme.Space.loose) {
                    prompt(question)
                    if question.kind.isTyped {
                        typedField
                    } else {
                        choices(question)
                    }
                    if let outcome {
                        feedback(question, outcome)
                    }
                }
                .padding(JustTheme.Space.regular)
            }
            .scrollIndicators(.hidden)

            actionBar(question)
                .padding(JustTheme.Space.regular)
        }
    }

    private func prompt(_ question: QuizQuestion) -> some View {
        VStack(spacing: JustTheme.Space.snug) {
            Text(question.kind.title).justSectionHeader()

            // The lyric is the prompt for cloze, so it gets lyric-sized type.
            Text(question.prompt)
                .font(
                    question.kind == .cloze
                        ? JustTheme.Font.lyricActive
                        : .system(size: 30, weight: .semibold)
                )
                .foregroundStyle(JustTheme.Ink.primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if let detail = displayedContext(question) {
                Text(detail)
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(JustTheme.Ink.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, JustTheme.Space.loose)
    }

    /// For cloze the meaning is withheld until the answer is in — printing it
    /// under the gap hands over the answer, which is the one thing the
    /// exercise is testing.
    private func displayedContext(_ question: QuizQuestion) -> String? {
        guard question.kind == .cloze, outcome == nil else { return question.context }
        return question.songLabelOnly
    }

    private var typedField: some View {
        VStack(spacing: JustTheme.Space.tight) {
            TextField("답 입력", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 26, weight: .medium))
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
                    .font(.system(size: 20, weight: .medium))
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
        case .correct: .green
        case .close: .orange
        case .wrong: .red
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
                            Image(systemName: "checkmark").foregroundStyle(.green)
                        }
                    }
                    .padding(JustTheme.Space.snug)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        optionBackground(option, question: question),
                        in: .rect(cornerRadius: JustTheme.Radius.chip)
                    )
                }
                .buttonStyle(.plain)
                .disabled(outcome != nil)
            }
        }
    }

    private func optionBackground(_ option: String, question: QuizQuestion) -> Color {
        guard outcome != nil else { return JustTheme.Surface.raised }
        if option == question.meaning { return .green.opacity(0.22) }
        if option == input { return .red.opacity(0.22) }
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
        case .correct: .green
        case .close: .orange
        case .wrong: .red
        }
    }

    private func actionBar(_ question: QuizQuestion) -> some View {
        Group {
            if outcome == nil {
                Button(question.kind.isTyped ? "확인" : "모르겠어요") {
                    if !question.kind.isTyped { input = "" }
                    submit()
                }
                .buttonStyle(.justPrimary)
                .frame(maxWidth: .infinity)
            } else {
                Button(index + 1 < questions.count ? "다음" : "결과 보기") { advance() }
                    .buttonStyle(.justPrimary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Summary

    private var summary: some View {
        VStack(spacing: JustTheme.Space.regular) {
            Text("\(correctCount) / \(questions.count)")
                .font(.system(size: 44, weight: .bold).monospacedDigit())
                .foregroundStyle(JustTheme.Ink.primary)
            Text("복습 일정에 반영했습니다")
                .font(JustTheme.Font.body)
                .foregroundStyle(JustTheme.Ink.secondary)
            Button("한 번 더") { start() }
                .buttonStyle(.justPrimary)
        }
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
        entries.map { entry in
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
