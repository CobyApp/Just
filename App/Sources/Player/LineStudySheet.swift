import RingRingCore
import RingRingDesign
import RingRingSensei
import SwiftUI

/// The word-by-word breakdown of one lyric line.
struct LineStudySheet: View {
    @Bindable var session: SongSession
    let lineIndex: Int

    @Environment(AppModel.self) private var app
    @State private var savedWords: Set<String> = []
    @State private var showsCard = false

    private var study: LineStudy? { app.sensei.cached(lineIndex) }
    private var lineText: String {
        session.lyrics?.lines.first { $0.id == lineIndex }?.text ?? ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JustTheme.Space.loose) {
                    original

                    JustActionHint(
                        "단어 카드의 +를 누르면 단어장에 저장됩니다. 저장한 단어로 퀴즈와 복습이 만들어져요.",
                        symbol: "plus.circle.fill"
                    )
                        .dismissibleGuide("linestudy.hint")

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
            .background(JustBrandBackground())
            .scrollIndicators(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            if !lineText.isEmpty {
                Button {
                    showsCard = true
                } label: {
                    Label("가사 카드 만들기", systemImage: "sparkles.rectangle.stack")
                }
                .buttonStyle(.justSecondary)
                .padding(.top, JustTheme.Space.hairline)
            }
        }
        .sheet(isPresented: $showsCard) {
            LyricCardSheet(card: LyricCard(
                line: lineText,
                translation: session.translation(for: lineIndex),
                title: session.track.title,
                artist: session.track.artist,
                tint: IdolGroup.group(forArtist: session.track.artist)?.memberColor
                    ?? JustTheme.Kawaii.accent
            ))
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
            } else {
                Text("사전에 수록된 단어만 찾을 수 있습니다.")
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
    @State private var saves = 0
    let toggle: () -> Void

    /// "the form the lyric uses", in the app's language. A String because the
    /// surface is dynamic; `JustChip` renders it verbatim.
    private func inflectedChip(_ surface: String) -> String {
        AppLanguage.current == .en ? "lyric: \(surface)" : "가사: \(surface)"
    }

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
                        // + turns into ✓ rather than being swapped for it.
                        .contentTransition(.symbolEffect(.replace))
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
                .scaleEffect(isSaved ? 1 : 0.94)
                .animation(.spring(duration: 0.35, bounce: 0.6), value: isSaved)
                // A little glitter for each word kept.
                .sparkleBurst(trigger: saves, count: 10, spread: 46)
                .sensoryFeedback(.success, trigger: saves)
                .onChange(of: isSaved) { _, saved in
                    if saved { saves += 1 }
                }
                .accessibilityLabel(isSaved ? "단어장에서 빼기" : "단어장에 넣기")
            }

            Text(word.meaningKo)
                .font(JustTheme.Font.body)
                .foregroundStyle(JustTheme.Ink.primary)

            HStack(spacing: 6) {
                JustChip(word.jlpt.label, tint: word.jlpt.tint)
                JustChip(word.partOfSpeech.displayName)
                if word.isInflected {
                    JustChip(inflectedChip(word.surface), tint: JustTheme.Feedback.warning)
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
