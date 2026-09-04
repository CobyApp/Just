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
                        deepenButton(study)
                    }
                }
                .padding(JustTheme.Space.regular)
            }
            .background(JustBrandBackground())
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
                // Also gated on the clock: repeating a line needs a song
                // position to rewind to, and a preview clip has none.
                if session.canLoop, app.player.position.followsLyrics {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            session.toggleLoop(lineIndex)
                            Haptics.tick()
                        } label: {
                            Label("이 줄 반복", systemImage: "repeat")
                                .labelStyle(.iconOnly)
                        }
                        .tint(
                            session.loopingLine == lineIndex
                                ? JustTheme.Accent.end
                                : JustTheme.Ink.secondary
                        )
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { session.selectedLine = nil }
                }
            }
        }
        .preferredColorScheme(.light)
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
            if let translation = session.translation(for: lineIndex), !translation.isEmpty {
                Text(translation)
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
                            .buttonStyle(.justSecondary)
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
        // An English line has nothing missing — there is nothing there to
        // learn as Japanese, and saying so is different from saying the
        // analysis came up short.
        let isForeign = !LineScript.hasJapanese(study.original)

        return VStack(alignment: .leading, spacing: JustTheme.Space.tight) {
            Text(isForeign ? "영어 구절 — 외울 단어가 없습니다." : "이 줄에서 뽑을 단어가 없습니다.")
                .font(JustTheme.Font.body)
                .foregroundStyle(JustTheme.Ink.secondary)
            if isForeign {
                Text("뜻은 위에 있습니다. 일본어가 아니라서 단어장에 담을 것은 없습니다.")
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(JustTheme.Ink.tertiary)
            } else if study.engine != .onDevice {
                // Points at what can actually be done from here. "Apple
                // Intelligence를 켜면" described a system switch, and the choice
                // now lives in this app — either the button below this text, or
                // the mode in settings.
                Text(
                    app.sensei.usesOnDeviceModel
                        ? "빠른 해석은 사전에 수록된 단어만 찾습니다. 아래에서 이 줄만 다시 해석할 수 있습니다."
                        : "사전에 수록된 단어만 찾을 수 있습니다. 이 기기에서는 문맥 해석을 쓸 수 없습니다."
                )
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(JustTheme.Ink.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .justCard()
    }

    /// Asks the model to read this one line properly.
    ///
    /// Shown only where there is something to improve on — a line the model
    /// already answered has nothing better coming. This is the other half of
    /// the fast mode: the whole song in seconds, and the model on the line the
    /// reader actually stopped at, which costs seconds rather than the minutes
    /// a whole song costs.
    @ViewBuilder
    private func deepenButton(_ study: LineStudy) -> some View {
        if app.sensei.canDeepen(lineIndex) {
            VStack(spacing: JustTheme.Space.tight) {
                Button {
                    Task { await deepen() }
                } label: {
                    Label("정확하게 다시 번역", systemImage: "sparkles")
                }
                .buttonStyle(.justSecondary)

                // What happened last time, when it did not work. Without this
                // the button is tapped, a few seconds pass, and the card comes
                // back exactly as it was — which reads as the app ignoring it.
                if let failure = app.sensei.lastFailure[lineIndex] {
                    Text(failure.readerExplanation)
                        .font(JustTheme.Font.caption)
                        .foregroundStyle(JustTheme.Ink.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("AI가 앞뒤 줄까지 읽고 이 줄을 다시 번역합니다. 몇 초 걸립니다.")
                        .font(JustTheme.Font.caption)
                        .foregroundStyle(JustTheme.Ink.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func deepen() async {
        guard let lyrics = session.lyrics else { return }
        await app.sensei.deepen(
            lineIndex: lineIndex,
            in: lyrics,
            songTitle: session.track.title,
            artist: session.track.artist
        )
        // Written to the record right away. A line improved by hand is worth
        // more than the automatic passes, and losing it because the player was
        // closed before the next flush would be the reader paying twice.
        session.flushNow()
        syncSavedState()
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

                SpeakButton(word: word.dictionaryForm, reading: word.reading)

                Button(action: toggle) {
                    Image(systemName: isSaved ? "checkmark" : "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(isSaved ? .white : JustTheme.Ink.primary)
                        .frame(
                            width: JustIconButtonStyle.minimumTapTarget,
                            height: JustIconButtonStyle.minimumTapTarget
                        )
                        .background(
                            isSaved ? JustTheme.Kawaii.accent : JustTheme.Surface.raised,
                            in: .circle
                        )
                        .overlay {
                            Circle().strokeBorder(JustTheme.Ink.hairline, lineWidth: 0.5)
                        }
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

            KanjiGlossStrip(word: word.dictionaryForm)

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
