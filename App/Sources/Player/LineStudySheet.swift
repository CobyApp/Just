import JustCore
import JustDesign
import JustSensei
import SwiftUI

/// The word-by-word breakdown of one lyric line.
struct LineStudySheet: View {
    @Bindable var session: SongSession
    let lineIndex: Int

    @Environment(AppModel.self) private var app
    @State private var savedWords: Set<String> = []

    private var study: LineStudy? { app.sensei.cached(lineIndex) }
    private var lineText: String {
        session.lyrics?.lines.first { $0.id == lineIndex }?.text ?? ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JustTheme.Space.loose) {
                    original

                    if app.sensei.isAnalyzing(lineIndex) {
                        HStack(spacing: JustTheme.Space.tight) {
                            ProgressView().controlSize(.small)
                            Text("해석 중").font(JustTheme.Font.caption)
                                .foregroundStyle(JustTheme.Ink.tertiary)
                        }
                    } else if let study {
                        results(study)
                    }
                }
                .padding(JustTheme.Space.regular)
            }
            .scrollIndicators(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if let study {
                        Text(study.engine.label)
                            .font(JustTheme.Font.caption)
                            .foregroundStyle(JustTheme.Ink.tertiary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { session.selectedLine = nil }
                }
            }
        }
        .task(id: lineIndex) {
            savedWords = []
            await session.analyze(lineIndex: lineIndex)
            syncSavedState()
        }
    }

    private var original: some View {
        VStack(alignment: .leading, spacing: JustTheme.Space.tight) {
            RubyText(
                segments: Furigana.segments(forLine: lineText),
                font: JustTheme.Font.japanese,
                color: JustTheme.Ink.primary
            )
            if let study, !study.translationKo.isEmpty {
                Text(study.translationKo)
                    .font(JustTheme.Font.body)
                    .foregroundStyle(JustTheme.Ink.secondary)
            }
        }
    }

    @ViewBuilder
    private func results(_ study: LineStudy) -> some View {
        if study.words.isEmpty, study.grammar.isEmpty {
            emptyState(study)
        } else {
            if !study.words.isEmpty {
                VStack(alignment: .leading, spacing: JustTheme.Space.snug) {
                    HStack {
                        Text("단어").justSectionHeader()
                        Spacer()
                        Button("모두 저장") { saveAll(study) }
                            .font(JustTheme.Font.caption)
                            .disabled(study.words.allSatisfy { savedWords.contains($0.id) })
                    }
                    ForEach(study.words) { word in
                        WordCard(
                            word: word,
                            isSaved: savedWords.contains(word.id),
                            toggle: { toggle(word, in: study) }
                        )
                    }
                }
            }

            if !study.grammar.isEmpty {
                VStack(alignment: .leading, spacing: JustTheme.Space.snug) {
                    Text("문법 · 표현").justSectionHeader()
                    ForEach(study.grammar) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.pattern)
                                .font(JustTheme.Font.japanese)
                                .foregroundStyle(JustTheme.Ink.primary)
                            Text(note.explanationKo)
                                .font(JustTheme.Font.body)
                                .foregroundStyle(JustTheme.Ink.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .justCard()
                    }
                }
            }
        }
    }

    private func emptyState(_ study: LineStudy) -> some View {
        VStack(alignment: .leading, spacing: JustTheme.Space.tight) {
            Text("이 줄에서 뽑을 단어가 없습니다.")
                .font(JustTheme.Font.body)
                .foregroundStyle(JustTheme.Ink.secondary)
            if study.engine == .dictionary {
                Text("사전 모드에서는 수록된 단어만 찾을 수 있습니다. Apple Intelligence를 켜면 문맥까지 해석합니다.")
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(JustTheme.Ink.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .justCard()
    }

    private func toggle(_ word: StudyWord, in study: LineStudy) {
        if savedWords.contains(word.id) {
            session.remove(word)
            savedWords.remove(word.id)
        } else {
            session.save(word, from: study)
            savedWords.insert(word.id)
        }
    }

    private func saveAll(_ study: LineStudy) {
        for word in study.words where !savedWords.contains(word.id) {
            session.save(word, from: study)
            savedWords.insert(word.id)
        }
    }

    private func syncSavedState() {
        guard let study else { return }
        savedWords = Set(study.words.filter { session.isSaved($0) }.map(\.id))
    }
}

// MARK: - Word card

struct WordCard: View {
    let word: StudyWord
    let isSaved: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JustTheme.Space.tight) {
            HStack(alignment: .firstTextBaseline, spacing: JustTheme.Space.tight) {
                RubyText(
                    segments: Furigana.segments(
                        surface: word.dictionaryForm,
                        reading: word.reading
                    ),
                    font: JustTheme.Font.japanese,
                    color: JustTheme.Ink.primary
                )

                Spacer(minLength: JustTheme.Space.tight)

                Button(action: toggle) {
                    Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isSaved ? Color.green : JustTheme.Ink.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSaved ? "단어장에서 빼기" : "단어장에 넣기")
            }

            Text(word.meaningKo)
                .font(JustTheme.Font.body)
                .foregroundStyle(JustTheme.Ink.primary)

            HStack(spacing: 6) {
                JustChip(word.jlpt.label, tint: word.jlpt.tint)
                JustChip(word.partOfSpeech.rawValue)
                if word.isInflected {
                    JustChip("가사: \(word.surface)", tint: .orange)
                }
            }

            if !word.note.isEmpty {
                Text(word.note)
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(JustTheme.Ink.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .justCard()
    }
}

extension JLPTLevel {
    /// Green through red as the level gets harder; grey for out-of-syllabus.
    var tint: Color {
        switch self {
        case .n5: Color(red: 0.42, green: 0.78, blue: 0.55)
        case .n4: Color(red: 0.55, green: 0.76, blue: 0.45)
        case .n3: Color(red: 0.86, green: 0.74, blue: 0.40)
        case .n2: Color(red: 0.90, green: 0.58, blue: 0.36)
        case .n1: Color(red: 0.88, green: 0.44, blue: 0.44)
        case .beyond: JustTheme.Ink.tertiary
        }
    }
}
