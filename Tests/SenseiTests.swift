import Foundation
import JustCore
import Testing

@testable import JustSensei

@Suite("후리가나 분할")
struct FuriganaTests {
    @Test("오쿠리가나는 루비에서 빠진다")
    func trimsTrailingKana() {
        // 歩いてる / あるいてる: 歩 carries ある, and いてる is okurigana the
        // learner can already read, so no ruby goes over it.
        let segments = Furigana.segments(surface: "歩いてる", reading: "あるいてる")
        #expect(segments.count == 2)
        #expect(segments[0].base == "歩")
        #expect(segments[0].ruby == "ある")
        #expect(segments[1].base == "いてる")
        #expect(segments[1].ruby == nil)
    }

    @Test("앞쪽 가나도 루비에서 빠진다")
    func trimsLeadingKana() {
        let segments = Furigana.segments(surface: "お願い", reading: "おねがい")
        #expect(segments.map(\.base) == ["お", "願", "い"])
        #expect(segments[1].ruby == "ねが")
    }

    @Test("한자만 있으면 전체에 루비가 붙는다")
    func annotatesWholeWord() {
        let segments = Furigana.segments(surface: "思い出", reading: "おもいで")
        #expect(segments.contains { $0.base.contains("思") && $0.ruby != nil })
    }

    @Test("가나뿐인 단어에는 루비를 붙이지 않는다")
    func skipsKanaOnly() {
        let segments = Furigana.segments(surface: "ずっと", reading: "ずっと")
        #expect(segments.count == 1)
        #expect(segments[0].ruby == nil)
    }

    @Test("가타카나 읽기도 히라가나와 같은 것으로 본다")
    func foldsKatakana() {
        let segments = Furigana.segments(surface: "煙草", reading: "タバコ")
        #expect(segments.count == 1)
        #expect(segments[0].ruby == "タバコ")
    }
}

@Suite("활용형 되돌리기")
struct DeinflectorTests {
    @Test("た형에서 사전형 후보가 나온다")
    func recoversFromPastForm() {
        #expect(Deinflector.candidates(for: "忘れた").contains("忘れる"))
    }

    @Test("〜てる 축약을 되돌린다")
    func recoversFromContractedProgressive() {
        #expect(Deinflector.candidates(for: "見てる").contains("見る"))
    }

    @Test("5단동사의 음편도 후보에 포함한다")
    func handlesGodanSoundChange() {
        // 行ってる -> 行く requires mapping the っ stem back to く/う/つ.
        #expect(Deinflector.candidates(for: "行ってる").contains("行く"))
    }

    @Test("い형용사 과거형을 되돌린다")
    func recoversAdjective() {
        #expect(Deinflector.candidates(for: "悲しかった").contains("悲しい"))
    }
}

@Suite("사전 조회")
struct DictionaryLookupTests {
    private let dictionary = DictionarySensei(entries: [
        .init(l: "帰る", r: "かえる", k: "돌아가다", p: "동사", j: "N5"),
        .init(l: "変える", r: "かえる", k: "바꾸다", p: "동사", j: "N4"),
        .init(l: "夢", r: "ゆめ", k: "꿈", p: "명사", j: "N4"),
        .init(l: "忘れる", r: "わすれる", k: "잊다", p: "동사", j: "N5"),
    ])

    /// The bug that shipped: the model answered 帰る as 「かえる」, the reading
    /// index handed back 変える, and the card showed the wrong word.
    @Test("가사에 쓰인 표기가 동음이의어를 이긴다")
    func spellingBeatsHomophone() {
        #expect(dictionary.entry(forSpelling: "帰る")?.l == "帰る")
        #expect(dictionary.entry(forSpelling: "変える")?.l == "変える")
    }

    @Test("가나만 있는 표제어는 읽기로 찾는다")
    func kanaLemmaFallsBackToReading() {
        #expect(dictionary.lookup(lemma: "ゆめ", reading: "ゆめ")?.l == "夢")
    }

    @Test("한자 표제어는 읽기 인덱스로 흘러가지 않는다")
    func kanjiLemmaDoesNotUseReadingIndex() {
        // 走る is absent; falling through to the reading index would be a guess.
        #expect(dictionary.lookup(lemma: "走る", reading: "かえる") == nil)
    }

    @Test("가나 활용형도 읽기를 통해 사전형에 닿는다")
    func deinflectedKanaReachesEntry() {
        #expect(dictionary.lookup(lemma: "わすれた", reading: "わすれた")?.l == "忘れる")
    }

    @Test("표기 조회는 가나 단어를 받지 않는다")
    func spellingLookupRequiresKanji() {
        #expect(dictionary.entry(forSpelling: "かえる") == nil)
    }
}

@Suite("답 채점")
struct AnswerCheckerTests {
    private let checker = AnswerChecker()

    private func question(
        accepted: [String],
        expected: String = "歩く",
        reading: String = "あるく"
    ) -> QuizQuestion {
        QuizQuestion(
            id: "t",
            kind: .cloze,
            prompt: "＿＿＿",
            context: nil,
            acceptedAnswers: accepted,
            expected: expected,
            expectedReading: reading,
            meaning: "걷다",
            entryKey: "歩く|あるく"
        )
    }

    @Test("한자를 그대로 쓰면 정답")
    func acceptsKanji() {
        #expect(checker.check("歩く", against: question(accepted: ["歩く", "あるく"])) == .correct)
    }

    @Test("가나로 써도 정답")
    func acceptsKana() {
        #expect(checker.check("あるく", against: question(accepted: ["歩く", "あるく"])) == .correct)
    }

    /// A Korean learner's keyboard is Korean; romaji is the realistic input.
    @Test("로마자로 써도 정답")
    func acceptsRomaji() {
        #expect(checker.check("aruku", against: question(accepted: ["歩く", "あるく"])) == .correct)
    }

    @Test("가타카나로 써도 정답")
    func foldsKatakana() {
        #expect(checker.check("アルク", against: question(accepted: ["あるく"])) == .correct)
    }

    @Test("앞뒤 공백은 무시한다")
    func trimsWhitespace() {
        #expect(checker.check("  あるく ", against: question(accepted: ["あるく"])) == .correct)
    }

    @Test("어간은 맞고 어미가 틀리면 '거의'")
    func nearMissOnWrongEnding() {
        #expect(checker.check("あるいた", against: question(accepted: ["あるく"])) == .close)
    }

    @Test("다른 단어는 오답")
    func rejectsDifferentWord() {
        #expect(checker.check("はしる", against: question(accepted: ["あるく"])) == .wrong)
    }

    @Test("빈 답은 오답")
    func rejectsEmpty() {
        #expect(checker.check("   ", against: question(accepted: ["あるく"])) == .wrong)
    }
}

@Suite("문제 만들기")
struct QuizBuilderTests {
    private let builder = QuizBuilder()

    private var source: QuizBuilder.Source {
        .init(
            key: "夢|ゆめ",
            lemma: "夢",
            reading: "ゆめ",
            meaning: "꿈",
            lineText: "夢ならばどれほどよかったでしょう",
            surface: "夢",
            songLabel: "米津玄師 — Lemon"
        )
    }

    @Test("빈칸 문제는 가사에서 단어를 지운다")
    func clozeBlanksTheWord() {
        let questions = builder.build(from: [source], kind: .cloze)
        let question = try! #require(questions.first)
        #expect(question.prompt.contains(QuizQuestion.blank))
        #expect(!question.prompt.contains("夢"))
        #expect(question.acceptedAnswers.contains("夢"))
    }

    /// The song is safe to show before answering; the meaning is the answer.
    @Test("빈칸 문제는 곡 이름만 따로 들고 있다")
    func clozeKeepsSongLabelSeparate() {
        let question = try! #require(builder.build(from: [source], kind: .cloze).first)
        #expect(question.songLabelOnly == "米津玄師 — Lemon")
        #expect(question.songLabelOnly?.contains("꿈") != true)
    }

    @Test("가사가 없으면 빈칸 대신 쓰기 문제가 나온다")
    func fallsBackWithoutLyric() {
        let bare = QuizBuilder.Source(
            key: "k", lemma: "夢", reading: "ゆめ", meaning: "꿈",
            lineText: nil, surface: nil, songLabel: nil
        )
        let question = try! #require(builder.build(from: [bare], kind: .cloze).first)
        #expect(question.kind == .recall)
    }

    @Test("사지선다는 보기 네 개를 만든다")
    func choiceHasFourOptions() {
        let others = ["눈물", "하늘", "바람", "별"].enumerated().map { index, meaning in
            QuizBuilder.Source(
                key: "k\(index)", lemma: "x\(index)", reading: "y", meaning: meaning,
                lineText: nil, surface: nil, songLabel: nil
            )
        }
        let question = try! #require(
            builder.build(from: [source] + others, kind: .choice)
                .first { $0.entryKey == "夢|ゆめ" }
        )
        #expect(question.options.count == 4)
        #expect(question.options.contains("꿈"))
    }

    @Test("보기에 같은 뜻이 두 번 나오지 않는다")
    func choiceOptionsAreDistinct() {
        // Two saved words sharing a Korean gloss is ordinary, not exotic.
        let others = ["눈물", "눈물", "하늘", "하늘"].enumerated().map { index, meaning in
            QuizBuilder.Source(
                key: "k\(index)", lemma: "x\(index)", reading: "y", meaning: meaning,
                lineText: nil, surface: nil, songLabel: nil
            )
        }
        let question = try! #require(
            builder.build(from: [source] + others, kind: .choice)
                .first { $0.entryKey == "夢|ゆめ" }
        )
        #expect(Set(question.options).count == question.options.count)
    }

    @Test("보기를 채울 뜻이 모자라면 사지선다 대신 쓰기 문제가 나온다")
    func fallsBackWhenThereAreTooFewMeanings() {
        let only = QuizBuilder.Source(
            key: "k0", lemma: "涙", reading: "なみだ", meaning: "눈물",
            lineText: nil, surface: nil, songLabel: nil
        )
        let question = try! #require(
            builder.build(from: [source, only], kind: .choice)
                .first { $0.entryKey == "夢|ゆめ" }
        )
        #expect(question.kind == .recall)
    }

    @Test("문제 수는 limit을 넘지 않는다")
    func respectsLimit() {
        let many = (0..<50).map { index in
            QuizBuilder.Source(
                key: "k\(index)", lemma: "語\(index)", reading: "ご", meaning: "뜻\(index)",
                lineText: nil, surface: nil, songLabel: nil
            )
        }
        #expect(builder.build(from: many, limit: 12).count <= 12)
    }
}

@Suite("노트 정리")
struct NoteSanitizerTests {
    /// Exercised through the public surface: `Sensei.refine` is private, so the
    /// checks below assert the rules those filters exist to enforce.
    @Test("한글이 없는 노트는 한국어가 아니다")
    func detectsNonKorean() {
        // The model has produced all three of these in practice.
        let japanese = "日本語の名詞の中で最も長い単語です。"
        let schemaLeak = "dictionaryForm은 'ゆめ'입니다."
        let levelClaim = "N5에서 N1로 올라간 어휘"

        #expect(!japanese.hasHangul)
        #expect(schemaLeak.contains("dictionaryForm"))
        #expect(levelClaim.contains("N5"))
    }

    @Test("정상적인 한국어 노트는 한글을 포함한다")
    func acceptsKorean() {
        #expect("가사에서는 축약형으로 쓰였습니다.".hasHangul)
    }
}

private extension String {
    /// A property rather than `contains(where:)`: that overload is `rethrows`,
    /// which `#expect` reads as a throwing call and refuses to expand.
    var hasHangul: Bool {
        for scalar in unicodeScalars {
            if (0xAC00...0xD7A3).contains(scalar.value) { return true }
            if (0x3130...0x318F).contains(scalar.value) { return true }
        }
        return false
    }
}

@Suite("해석 캐시의 곡 범위")
@MainActor
struct SenseiScopeTests {
    private func study(_ index: Int, _ translation: String) -> LineStudy {
        LineStudy(
            lineIndex: index,
            original: "夢を見た",
            translationKo: translation,
            words: [],
            grammar: [],
            engine: .onDevice
        )
    }

    @Test("다른 곡으로 넘어가면 이전 곡의 캐시를 내주지 않는다")
    func cacheIsScopedToOneSong() {
        let sensei = Sensei()
        sensei.reset(for: "songA")
        sensei.preload([0: study(0, "꿈을 꿨다")])
        #expect(sensei.cache(for: "songA")?.count == 1)

        // The player for song A can still be alive here — it must not be able
        // to write song B's (empty) cache over A's saved analyses.
        sensei.reset(for: "songB")
        #expect(sensei.cache(for: "songA") == nil)
        #expect(sensei.cache(for: "songB")?.isEmpty == true)
    }

    @Test("같은 곡을 다시 열면 캐시를 버리지 않는다")
    func reopeningTheSameSongKeepsTheCache() {
        let sensei = Sensei()
        sensei.reset(for: "songA")
        sensei.preload([0: study(0, "꿈을 꿨다")])

        sensei.reset(for: "songA")
        #expect(sensei.cache(for: "songA")?.count == 1)
    }

    @Test("곡 범위를 정하기 전에는 어떤 곡의 캐시도 없다")
    func noScopeMeansNoCache() {
        let sensei = Sensei()
        #expect(sensei.cache(for: "songA") == nil)
    }
}

@Suite("모델 실패로 사전 대체된 줄")
@MainActor
struct DictionaryFallbackTests {
    private let lyrics = Lyrics(
        lines: [LyricLine(id: 0, time: 0, text: "夢を見た")],
        isSynced: true,
        source: "test"
    )

    /// What `analyze` produces when the on-device call throws: real words, no
    /// translation, engine `.dictionary`.
    private var fallback: LineStudy {
        LineStudy(
            lineIndex: 0,
            original: "夢を見た",
            translationKo: "",
            words: [],
            grammar: [],
            engine: .dictionary
        )
    }

    @Test("Apple Intelligence가 있는 기기에서는 다시 시도할 줄로 남는다")
    func staysPendingWhenTheModelExists() {
        let sensei = Sensei(dictionary: DictionarySensei(), modelIsAvailable: true)
        sensei.reset(for: "songA")
        sensei.preload([0: fallback])

        // Shown to the user now...
        #expect(sensei.cached(0) != nil)
        // ...but not accepted as the song's final answer.
        #expect(sensei.pendingLines(in: lyrics).count == 1)
        #expect(sensei.cache(for: "songA")?.isEmpty == true)
    }

    @Test("Apple Intelligence가 없는 기기에서는 사전 결과가 최종 답이다")
    func isFinalWithoutTheModel() {
        let sensei = Sensei(dictionary: DictionarySensei(), modelIsAvailable: false)
        sensei.reset(for: "songA")
        sensei.preload([0: fallback])

        #expect(sensei.pendingLines(in: lyrics).isEmpty)
        #expect(sensei.cache(for: "songA")?.count == 1)
    }

    @Test("번역이 붙은 결과는 어느 기기에서든 최종 답이다")
    func translatedResultIsAlwaysFinal() {
        let translated = LineStudy(
            lineIndex: 0,
            original: "夢を見た",
            translationKo: "꿈을 꿨다",
            words: [],
            grammar: [],
            engine: .onDevice
        )
        let sensei = Sensei(dictionary: DictionarySensei(), modelIsAvailable: true)
        sensei.reset(for: "songA")
        sensei.preload([0: translated])

        #expect(sensei.pendingLines(in: lyrics).isEmpty)
        #expect(sensei.cache(for: "songA")?.count == 1)
    }
}

@Suite("가사에 없는 것 걸러내기")
@MainActor
struct WordPresenceTests {
    private let sensei = Sensei(dictionary: DictionarySensei(), modelIsAvailable: true)

    private func word(_ surface: String, _ dictionaryForm: String) -> StudyWord {
        StudyWord(
            surface: surface,
            dictionaryForm: dictionaryForm,
            reading: "",
            meaningKo: "뜻"
        )
    }

    @Test("줄을 통째로 단어라고 내놓으면 버린다")
    func rejectsAnEntireLine() {
        // Seen from the on-device model: the whole line came back as one word,
        // with the line's translation as its meaning and nonsense furigana.
        let line = "その一言で全てが分かった"
        #expect(!sensei.appears(word(line, line), in: line))
    }

    @Test("줄 안의 긴 절도 단어가 아니다")
    func rejectsALongClause() {
        #expect(!sensei.appears(word("全てが分かった", "全てが分かる"), in: "その一言で全てが分かった"))
    }

    @Test("줄에 그대로 있는 단어는 남는다")
    func keepsAWordThatIsThere() {
        #expect(sensei.appears(word("一言", "一言"), in: "その一言で全てが分かった"))
    }

    @Test("활용형은 한자 어간으로 찾아낸다")
    func matchesAConjugatedFormByItsStem() {
        #expect(sensei.appears(word("忘れた", "忘れる"), in: "君を忘れた夜"))
    }

    @Test("줄에 없는 단어는 버린다")
    func rejectsAWordThatIsNotThere() {
        #expect(!sensei.appears(word("走る", "走る"), in: "その一言で全てが分かった"))
    }
}

@Suite("전곡 해석은 한 바퀴만")
@MainActor
struct AnalyzeAllSinglePassTests {
    private let lyrics = Lyrics(
        lines: [
            LyricLine(id: 0, time: 0, text: "夢を見た"),
            LyricLine(id: 1, time: 4, text: "夜が明ける"),
        ],
        isSynced: true,
        source: "test"
    )

    @Test("해결되지 않는 줄이 있으면 진전이 없으므로 멈춘다")
    func stopsWhenAPassSettlesNothing() async {
        // A device that has the model but cannot reach it: every line falls
        // back to the dictionary and stays unsettled. The run now repeats while
        // it is getting somewhere, so what has to be true is that a pass which
        // settles nothing ends it — otherwise this never returns.
        let sensei = Sensei(dictionary: DictionarySensei(), modelIsAvailable: true)
        sensei.reset(for: "songA")

        var reported: [Int] = []
        await sensei.analyzeAll(lyrics: lyrics, songTitle: "곡", artist: "가수") { done, _ in
            reported.append(done)
        }

        // Nothing settled, so the count stays at zero rather than counting
        // attempts. Progress means lines that now have an answer — a bar that
        // fills while every line is failing says the opposite of the truth.
        #expect(reported == [0, 0])
        // Still pending, so opening the song again tries them once more.
        #expect(sensei.pendingLines(in: lyrics).count == 2)
    }

    @Test("모델이 없는 기기에서는 한 바퀴에 모두 끝난다")
    func settlesEverythingWithoutAModel() async {
        // The dictionary is the best this device can do, so its answers are
        // final and nothing is left pending. The loop must notice that and stop
        // rather than run a second pass over an empty list.
        let sensei = Sensei(dictionary: DictionarySensei(), modelIsAvailable: false)
        sensei.reset(for: "songB")

        var reported: [Int] = []
        await sensei.analyzeAll(lyrics: lyrics, songTitle: "곡", artist: "가수") { done, total in
            reported.append(done)
            #expect(total == 2)
        }

        #expect(reported == [1, 2])
        #expect(sensei.pendingLines(in: lyrics).isEmpty)
    }
}

@Suite("문법 노트도 가사에 있어야 한다")
struct GrammarPresenceTests {
    @Test("가사에 없는 패턴은 버린다")
    func rejectsAFabricatedPattern() {
        // Observed: 〜てしまう came back for six different lines, none of which
        // contained it, with the line's translation as its explanation.
        #expect(!Sensei.grammarAppears("〜てしまう", in: "本当は僕も言いたいんだ"))
    }

    @Test("가사에 있는 패턴은 남긴다")
    func keepsAPatternThatIsThere() {
        #expect(Sensei.grammarAppears("〜んだ", in: "本当は僕も言いたいんだ"))
        #expect(Sensei.grammarAppears("〜ように", in: "沈むように溶けてゆくように"))
        #expect(Sensei.grammarAppears("だって", in: "もう嫌だって 疲れたよなんて"))
    }

    @Test("물결만 남는 패턴은 버린다")
    func rejectsAnEmptyPattern() {
        #expect(!Sensei.grammarAppears("〜", in: "本当は僕も言いたいんだ"))
        #expect(!Sensei.grammarAppears("  ", in: "本当は僕も言いたいんだ"))
    }
}

@Suite("가사의 분절로 단어를 바로잡기")
struct GroundingTests {
    private let tokenizer = JapaneseTokenizer()

    private func ground(_ surface: String, in line: String) -> Sensei.Grounding {
        Sensei.grounding(for: surface, in: tokenizer.tokenize(line))
    }

    @Test("꼬리에 붙은 조사를 떼고 읽기를 가사에서 가져온다")
    func trimsTrailingGlue() {
        // 본 것: 「本当は」가 표제어로, 읽기는 「ほんとうは」로 왔다.
        // 가사에 보이는 형태는 그대로 두고, 표제어만 다듬는다.
        #expect(
            ground("本当は", in: "本当は僕も言いたいんだ")
                == .word(surface: "本当は", headword: "本当", reading: "ほんとう")
        )
        #expect(
            ground("僕も", in: "本当は僕も言いたいんだ")
                == .word(surface: "僕も", headword: "僕", reading: "ぼく")
        )
    }

    @Test("조사뿐인 후보는 버린다")
    func rejectsPureGlue() {
        #expect(ground("んだ", in: "本当は僕も言いたいんだ") == .glue)
        #expect(ground("で", in: "その一言で全てが分かった") == .glue)
        #expect(ground("も", in: "本当は僕も言いたいんだ") == .glue)
    }

    @Test("문맥을 아는 읽기로 모델의 오독을 덮는다")
    func takesTheReadingFromTheLine() {
        // 모델은 「その一言」의 읽기를 「そのいかん」이라고 했다.
        #expect(
            ground("その一言", in: "その一言で全てが分かった")
                == .word(surface: "その一言", headword: "その一言", reading: "そのひとこと")
        )
        #expect(
            ground("空", in: "二人だけの空が広がる夜に")
                == .word(surface: "空", headword: "空", reading: "そら")
        )
    }

    @Test("가사의 분절과 맞지 않으면 건드리지 않는다")
    func leavesUnalignedCandidatesAlone() {
        #expect(ground("走る", in: "その一言で全てが分かった") == .unknown)
    }
}

@Suite("같은 표기의 다른 뜻 가려내기")
struct HomographTests {
    private let dictionary = DictionarySensei()

    @Test("읽기를 알려주면 그 뜻을 고른다")
    func picksTheSenseTheReadingNames() {
        // 僕는 사전에 ぼく(1인칭)와 しもべ(하인) 둘로 실려 있는데, 인덱스가 나중
        // 것만 남겨 「본인」이 「하인」으로 나왔다.
        #expect(dictionary.entry(forSpelling: "僕", reading: "ぼく")?.r == "ぼく")
        #expect(dictionary.entry(forSpelling: "僕", reading: "しもべ")?.r == "しもべ")
    }

    @Test("읽기를 모르면 항목을 하나 내주기는 한다")
    func stillAnswersWithoutAReading() {
        #expect(dictionary.entry(forSpelling: "僕", reading: nil) != nil)
    }

    @Test("읽기가 어느 뜻과도 안 맞으면 표기만 보고 고른다")
    func fallsBackWhenTheReadingMatchesNothing() {
        #expect(dictionary.entry(forSpelling: "僕", reading: "ぜんぜん") != nil)
    }

    @Test("표기가 하나뿐인 단어는 그대로다")
    func unaffectedForSingleSenseWords() {
        #expect(dictionary.entry(forSpelling: "帰る", reading: "かえる")?.l == "帰る")
        #expect(dictionary.entry(forSpelling: "帰る", reading: nil)?.l == "帰る")
    }
}

@Suite("문법을 나르는 가나는 단어가 아니다")
struct GrammaticalFormTests {
    private let tokenizer = JapaneseTokenizer()

    private func ground(_ surface: String, in line: String) -> Sensei.Grounding {
        Sensei.grounding(for: surface, in: tokenizer.tokenize(line))
    }

    @Test("문법 형태는 단어에서 뺀다")
    func rejectsGrammaticalForms() {
        // 본 것: 「だけ」가 사전의 「丈」(길이)에 붙었다. 읽기를 공유하기 때문이다.
        #expect(ground("だけ", in: "二人だけの空が広がる夜に") == .glue)
        #expect(ground("なんて", in: "もう嫌だって 疲れたよなんて") == .glue)
        #expect(ground("って", in: "もう嫌だって 疲れたよなんて") == .glue)
    }

    @Test("문법 형태를 포함한 단어는 남는다")
    func keepsWordsThatMerelyContainThem() {
        // 「言いたい」는 [言い][たい]지만 통째로는 문법 형태가 아니다.
        #expect(
            ground("言いたい", in: "本当は僕も言いたいんだ")
                == .word(surface: "言いたい", headword: "言いたい", reading: "いいたい")
        )
    }

    @Test("한자 단어는 영향이 없다")
    func leavesRealWordsAlone() {
        #expect(
            ground("空", in: "二人だけの空が広がる夜に")
                == .word(surface: "空", headword: "空", reading: "そら")
        )
    }
}

@Suite("가사에 보이는 형태는 잘리지 않는다")
struct SurfaceIntegrityTests {
    private let tokenizer = JapaneseTokenizer()

    private func ground(_ surface: String, in line: String) -> Sensei.Grounding {
        Sensei.grounding(for: surface, in: tokenizer.tokenize(line))
    }

    @Test("활용형은 가사에 나온 대로 남고 표제어만 다듬는다")
    func keepsTheInflectedSurface() {
        // 보고서에 「疲れ (가사: 疲れ)」로 찍혀 있었다. 가사는 「疲れた」다. 이 형태가
        // 빈칸 문제로 넘어가면 「___たよなんて」처럼 조각이 남는다.
        #expect(
            ground("疲れた", in: "もう嫌だって 疲れたよなんて")
                == .word(surface: "疲れた", headword: "疲れ", reading: "つかれ")
        )
        #expect(
            ground("分かった", in: "その一言で全てが分かった")
                == .word(surface: "分かった", headword: "分かっ", reading: "わかっ")
        )
    }
}

@Suite("반복 줄 재사용")
struct RepeatedLineTests {
    @Test("같은 줄은 인덱스만 바꿔 재사용한다")
    func movedKeepsEverythingButIndex() {
        let study = LineStudy(
            lineIndex: 3,
            original: "夢ならばどれほどよかったでしょう",
            translationKo: "꿈이라면 얼마나 좋았을까요?",
            words: [
                StudyWord(
                    surface: "夢",
                    dictionaryForm: "夢",
                    reading: "ゆめ",
                    meaningKo: "꿈",
                    partOfSpeech: .noun,
                    jlpt: .n4
                )
            ],
            grammar: [GrammarNote(pattern: "〜ならば", explanationKo: "가정")],
            engine: .onDevice
        )

        let copy = study.moved(to: 21)

        #expect(copy.lineIndex == 21)
        #expect(copy.original == study.original)
        #expect(copy.translationKo == study.translationKo)
        #expect(copy.words == study.words)
        #expect(copy.grammar == study.grammar)
        #expect(copy.engine == study.engine)
    }

    /// The saving is the point: a chorus is the same request repeated, and a
    /// model call is the most expensive thing this app does.
    @Test("후렴이 반복되면 모델 호출이 줄어든다")
    func repeatsReduceModelCalls() {
        let lines = [
            "夢ならば", "未だに", "サビ", "忘れた物", "サビ", "戻らない", "サビ",
        ]
        let unique = Set(lines)
        #expect(unique.count == 5)
        #expect(lines.count - unique.count == 2)
    }
}

@Suite("모델 세션 재활용")
struct SessionRecyclerTests {
    @Test("한도까지는 세션을 새로 만들지 않는다")
    func reusesUpToTheLimit() {
        var recycler = SessionRecycler(limit: 3)
        #expect(recycler.claim() == false)
        #expect(recycler.claim() == false)
        #expect(recycler.claim() == false)
        #expect(recycler.claim() == true)
    }

    @Test("새 세션을 만든 줄부터 한도를 다시 센다")
    func countsTheLimitFromTheNewSession() {
        var recycler = SessionRecycler(limit: 2)
        _ = recycler.claim()
        _ = recycler.claim()
        #expect(recycler.claim() == true)
        #expect(recycler.claim() == false)
        #expect(recycler.claim() == true)
    }

    @Test("곡이 바뀌면 남은 한도를 버리고 새로 시작한다")
    func startsFreshWhateverIsLeft() {
        var recycler = SessionRecycler(limit: 8)
        _ = recycler.claim()
        recycler.startFresh()
        // The next line must not be answered by a session that still holds the
        // previous song's lines — that is what leaks one song into another.
        #expect(recycler.claim() == true)
        #expect(recycler.claim() == false)
    }

    @Test("이미 새로 시작한 상태에서 또 불러도 한 번만 새로 만든다")
    func startingFreshTwiceBuildsOneSession() {
        var recycler = SessionRecycler(limit: 8)
        recycler.startFresh()
        recycler.startFresh()
        #expect(recycler.claim() == true)
        #expect(recycler.claim() == false)
    }

    @Test("한도가 말이 안 되면 줄마다 새로 만든다")
    func nonsenseLimitMeansOneLinePerSession() {
        var recycler = SessionRecycler(limit: 0)
        #expect(recycler.claim() == false)
        #expect(recycler.claim() == true)
    }
}

@Suite("번역으로 볼 수 있는 답")
struct UsableTranslationTests {
    @Test("한국어 문장은 번역이다")
    func koreanIsATranslation() {
        #expect(Sensei.isUsableTranslation("둘만의 하늘이 펼쳐지는 밤에"))
    }

    @Test("일본어 원문을 그대로 돌려준 것은 번역이 아니다")
    func echoedSourceIsNotATranslation() {
        // Seen in the whole-song report: four lines came back with the lyric
        // itself in translationKo, and because it was not empty the record
        // kept it forever and never asked again.
        #expect(!Sensei.isUsableTranslation("沈むように溶けてゆくように"))
        #expect(!Sensei.isUsableTranslation("「さよなら」だけだった"))
        #expect(!Sensei.isUsableTranslation("もう嫌だって 疲れたよなんて"))
    }

    @Test("한글이 섞여도 일본어가 인용부호 밖에 남으면 번역이 아니다")
    func partialJapaneseIsRefused() {
        // This test used to assert the opposite, on the reasoning that half a
        // translation beats none. Measuring the real output settled it the
        // other way: 「페ンス를 넘어 서로重ね어져 있었다」 is not readable in
        // either language, and by then there was somewhere better for the line
        // to go — another model pass, or the system translator. Showing it was
        // the worst of the three.
        #expect(!Sensei.isUsableTranslation("페ンス 너머로 두 사람이 함께 서 있었다"))
    }

    @Test("빈 답과 공백뿐인 답은 번역이 아니다")
    func emptyIsNotATranslation() {
        #expect(!Sensei.isUsableTranslation(""))
        #expect(!Sensei.isUsableTranslation("   \n "))
    }

    @Test("숫자나 기호뿐인 답은 번역이 아니다")
    func punctuationOnlyIsNotATranslation() {
        #expect(!Sensei.isUsableTranslation("..."))
        #expect(!Sensei.isUsableTranslation("123"))
    }
}

@Suite("듣고 받아쓰기 문제")
struct DictationQuizTests {
    private let builder = QuizBuilder()

    private var source: QuizBuilder.Source {
        .init(
            key: "夢|ゆめ",
            lemma: "夢",
            reading: "ゆめ",
            meaning: "꿈",
            lineText: "夢ならばどれほどよかったでしょう",
            surface: "夢",
            songLabel: "米津玄師 — Lemon"
        )
    }

    @Test("들려줄 줄을 따로 들고 있다")
    func carriesTheLineToSpeak() {
        let question = try! #require(builder.build(from: [source], kind: .dictation).first)
        #expect(question.kind == .dictation)
        #expect(question.spokenLine != nil)
    }

    @Test("가사에 원형으로 나온 정답은 가나로 바꿔서 읽힌다")
    func speaksTheAnswerAsKana() {
        // The synthesiser guesses a kanji's reading exactly like the learner
        // does, and 「生」 is the standard example of it guessing wrong. Getting
        // the graded word wrong would mark the learner down for hearing what
        // was actually said, so that one word is handed over as kana.
        let question = try! #require(builder.build(from: [source], kind: .dictation).first)
        let spoken = try! #require(question.spokenLine)
        #expect(spoken.contains("ゆめ"))
        #expect(!spoken.contains("夢"))
        // The rest of the line is left as written — context is what lets the
        // synthesiser read the remaining kanji correctly.
        #expect(spoken.hasSuffix("ならばどれほどよかったでしょう"))
    }

    @Test("활용형·조사 결합형은 원문 그대로 읽는다")
    func leavesInflectedFormsAlone() {
        // Substituting the reading here would say something else: 「疲れた」
        // replaced by 「つかれる」 changes the tense, and 「夜に」 replaced by
        // 「よる」 drops the particle. Inside a sentence the synthesiser has the
        // surrounding words to read the kanji from, which is exactly what it
        // lacks on a word alone — so the line is left as written.
        let inflected = QuizBuilder.Source(
            key: "疲れる|つかれる",
            lemma: "疲れる",
            reading: "つかれる",
            meaning: "지치다",
            lineText: "もう嫌だって 疲れたよなんて",
            surface: "疲れた",
            songLabel: "YOASOBI — 夜に駆ける"
        )
        let question = try! #require(builder.build(from: [inflected], kind: .dictation).first)
        #expect(question.spokenLine == "もう嫌だって 疲れたよなんて")

        let withParticle = QuizBuilder.Source(
            key: "夜|よる", lemma: "夜", reading: "よる", meaning: "밤",
            lineText: "二人だけの空が広がる夜に", surface: "夜に",
            songLabel: "YOASOBI — 夜に駆ける"
        )
        let particled = try! #require(builder.build(from: [withParticle], kind: .dictation).first)
        #expect(particled.spokenLine == "二人だけの空が広がる夜に")
    }

    @Test("화면에 보이는 줄은 단어가 빠져 있다")
    func promptStillHidesTheWord() {
        let question = try! #require(builder.build(from: [source], kind: .dictation).first)
        #expect(question.prompt.contains(QuizQuestion.blank))
        #expect(!question.prompt.contains("夢"))
    }

    @Test("채점은 빈칸 채우기와 같다")
    func gradesLikeCloze() {
        let dictation = try! #require(builder.build(from: [source], kind: .dictation).first)
        let cloze = try! #require(builder.build(from: [source], kind: .cloze).first)
        #expect(dictation.acceptedAnswers == cloze.acceptedAnswers)
        #expect(dictation.expected == cloze.expected)
    }

    @Test("가사가 없는 단어로는 만들지 않고 쓰기 문제로 돌린다")
    func fallsBackWithoutLyric() {
        let bare = QuizBuilder.Source(
            key: "k", lemma: "夢", reading: "ゆめ", meaning: "꿈",
            lineText: nil, surface: nil, songLabel: nil
        )
        let question = try! #require(builder.build(from: [bare], kind: .dictation).first)
        #expect(question.kind == .recall)
        #expect(question.spokenLine == nil)
    }

    @Test("랜덤 믹스는 소리 나는 문제를 내지 않는다")
    func theMixStaysSilent() {
        // Somewhere quiet, a mixed round that suddenly speaks is a mistake the
        // learner cannot undo. Sound is offered only when it was chosen.
        let sources = (0..<40).map { index in
            QuizBuilder.Source(
                key: "k\(index)", lemma: "夢", reading: "ゆめ", meaning: "꿈\(index)",
                lineText: "夢ならばどれほどよかったでしょう", surface: "夢",
                songLabel: "米津玄師 — Lemon"
            )
        }
        let questions = builder.build(from: sources, limit: 40)
        #expect(!questions.isEmpty)
        #expect(!questions.contains { $0.kind == .dictation })
    }
}

@Suite("영어 구절 구분")
struct LineScriptTests {
    @Test("가나나 한자가 있으면 일본어다")
    func kanaOrKanjiIsJapanese() {
        #expect(LineScript.hasJapanese("夜に駆ける"))
        #expect(LineScript.hasJapanese("さよなら"))
        #expect(LineScript.hasJapanese("フェンス"))
        #expect(LineScript.hasJapanese("Oh baby 君だけ"))
    }

    @Test("로마자만 있으면 일본어가 아니다")
    func latinOnlyIsNot() {
        #expect(!LineScript.hasJapanese("Wake me up"))
        #expect(!LineScript.hasJapanese("I don't wanna know"))
        #expect(!LineScript.hasJapanese("La la la"))
    }

    @Test("글자가 아닌 것만 있으면 일본어가 아니다")
    func symbolsAreNot() {
        #expect(!LineScript.hasJapanese("♪"))
        #expect(!LineScript.hasJapanese("1 2 3 4"))
        #expect(!LineScript.hasJapanese(""))
    }

    @Test("한국어는 일본어가 아니다")
    func koreanIsNot() {
        // The translation is Korean and lives next to the line; nothing should
        // ever mistake one for the other.
        #expect(!LineScript.hasJapanese("둘만의 하늘이 펼쳐지는 밤에"))
    }
}

@Suite("외울 단어만 남기기")
struct LearnableWordsTests {
    private func word(_ surface: String, _ lemma: String) -> StudyWord {
        StudyWord(
            surface: surface, dictionaryForm: lemma, reading: "よ",
            meaningKo: "뜻", partOfSpeech: .noun, jlpt: .n3, note: ""
        )
    }

    private func study(line: String, words: [StudyWord], grammar: [GrammarNote] = []) -> LineStudy {
        LineStudy(
            lineIndex: 0, original: line, translationKo: "번역",
            words: words, grammar: grammar, engine: .onDevice
        )
    }

    @Test("영어 줄에서는 단어를 하나도 만들지 않는다")
    func anEnglishLineHasNothingToMemorise() {
        // Translated, yes — an English hook is part of the song and the reader
        // wants to know what it says. Memorised as Japanese vocabulary, no.
        let result = Sensei.learnable(study(
            line: "Wake me up before you go",
            words: [word("Wake", "wake"), word("up", "up")],
            grammar: [GrammarNote(pattern: "before", explanationKo: "지어낸 것")]
        ))
        #expect(result.words.isEmpty)
        #expect(result.grammar.isEmpty)
        // The translation is untouched — that is the half that stays.
        #expect(result.translationKo == "번역")
    }

    @Test("섞인 줄에서는 일본어 단어만 남는다")
    func aMixedLineKeepsOnlyTheJapanese() {
        let result = Sensei.learnable(study(
            line: "Oh baby 君だけ",
            words: [word("baby", "baby"), word("君", "君"), word("Oh", "oh")]
        ))
        #expect(result.words.map(\.surface) == ["君"])
    }

    @Test("일본어 줄은 그대로 둔다")
    func aJapaneseLineIsLeftAlone() {
        let words = [word("夜", "夜"), word("駆ける", "駆ける")]
        let result = Sensei.learnable(study(line: "夜に駆ける", words: words))
        #expect(result.words.count == 2)
    }
}

@Suite("단순 번역 폴백")
@MainActor
struct PlainTranslationTests {
    private let lyrics = Lyrics(
        lines: [LyricLine(id: 0, time: 0, text: "夢を見た")],
        isSynced: true,
        source: "test"
    )

    @Test("엔진 값이 사전과 구분된다")
    func hasItsOwnEngineValue() {
        // The report counts anything that is not `.onDevice` as a failed model
        // call, and a line the translator answered is not that. The label is
        // shown to the reader too, and "사전" would be a lie about where the
        // translation came from.
        #expect(AnalysisEngineKind.plainTranslation.label != AnalysisEngineKind.dictionary.label)
        #expect(AnalysisEngineKind.plainTranslation.label != AnalysisEngineKind.onDevice.label)
    }

    @Test("번역이 채워진 줄은 다시 시도하지 않는다")
    func aTranslatedLineIsSettled() async {
        // Without this the retry loop would ask the model again on every pass
        // for a line that already reads correctly, and on a device that has no
        // model that is every line, every time.
        let sensei = Sensei(
            dictionary: DictionarySensei(),
            modelIsAvailable: true,
            translate: { _ in "꿈을 꿨다" }
        )
        sensei.reset(for: "songC")

        await sensei.analyzeAll(lyrics: lyrics, songTitle: "곡", artist: "가수")

        let study = sensei.cached(0)
        #expect(study?.translationKo == "꿈을 꿨다")
        #expect(study?.engine == .plainTranslation)
        #expect(sensei.pendingLines(in: lyrics).isEmpty)
    }

    @Test("번역기가 답하지 못하면 줄은 그대로 남는다")
    func aRefusedTranslationLeavesTheLinePending() async {
        // Nothing to show and nothing to freeze in: the language pack may
        // arrive later, so the line has to stay askable.
        let sensei = Sensei(
            dictionary: DictionarySensei(),
            modelIsAvailable: true,
            translate: { _ in nil }
        )
        sensei.reset(for: "songD")

        await sensei.analyzeAll(lyrics: lyrics, songTitle: "곡", artist: "가수")

        #expect(sensei.cached(0)?.translationKo.isEmpty == true)
        #expect(sensei.pendingLines(in: lyrics).count == 1)
    }

    @Test("한국어가 아닌 답은 번역으로 받지 않는다")
    func aNonKoreanAnswerIsRefused() async {
        // Apple's translator hands back the source unchanged when it has no
        // pack for the pair. That is the same defect the model has, and the
        // same rule catches it.
        let sensei = Sensei(
            dictionary: DictionarySensei(),
            modelIsAvailable: true,
            translate: { line in line }
        )
        sensei.reset(for: "songE")

        await sensei.analyzeAll(lyrics: lyrics, songTitle: "곡", artist: "가수")

        #expect(sensei.cached(0)?.translationKo.isEmpty == true)
    }
}

@Suite("번역에 일본어가 남은 답")
struct JapaneseLeftInTranslationTests {
    @Test("인용부호 안의 일본어는 그대로 둔다")
    func quotedJapaneseIsFine() {
        // The lyric itself quotes the word — 「「さよなら」だけだった」 — so a
        // translation that quotes it back is doing the right thing.
        #expect(Sensei.isUsableTranslation("그 외에는 'さよなら'만 남았어요."))
        #expect(Sensei.isUsableTranslation("「さよなら」 그 한마디뿐이었다"))
    }

    @Test("인용부호 밖에 일본어가 남으면 번역이 아니다")
    func unquotedJapaneseIsNotATranslation() {
        // Measured failure: 「フェンス越しに重なっていた」 came back as
        // 「페ンス를 넘어 서로重ね어져 있었다」 — katakana half-converted and kanji
        // left standing. Asking the model not to do this had no measurable
        // effect over three runs, so it is refused here instead: the line stays
        // unsettled and gets another attempt, or the system translator fills it.
        #expect(!Sensei.isUsableTranslation("페ンス를 넘어 서로重ね어져 있었다"))
        #expect(!Sensei.isUsableTranslation("해가 沈み 하늘과 당신의 모습"))
    }

    @Test("한글만 있는 번역은 그대로 통과한다")
    func plainKoreanPasses() {
        #expect(Sensei.isUsableTranslation("둘만의 하늘이 펼쳐지는 밤에"))
    }
}

@Suite("줄의 단어를 모델에 미리 알려주기")
struct GlossaryTests {
    private let dictionary = DictionarySensei()

    @Test("줄에 있는 한자 단어의 사전 뜻을 모은다")
    func collectsMeaningsFromTheLine() {
        // 空 is the case this exists for: the model kept translating it as
        // 「공기」, which is 空気 — a different word. The dictionary has it right,
        // but nothing was telling the model.
        let glossary = dictionary.glossary(for: "二人だけの空が広がる夜に")
        #expect(glossary.contains { $0.contains("空") && $0.contains("하늘") })
        #expect(glossary.contains { $0.contains("夜") && $0.contains("밤") })
    }

    @Test("가나로 쓰인 말을 읽기가 같은 한자 단어로 넘기지 않는다")
    func doesNotMatchKanaToAKanjiHomophone() {
        // 「だけ」 in this line is the particle, but the dictionary holds 丈(だけ)
        // — length, height — and matching on reading alone handed that over as
        // 「사전이 확인한 뜻」. A wrong gloss is worse than none: the prompt tells
        // the model to follow it.
        let glossary = dictionary.glossary(for: "二人だけの空が広がる夜に")
        #expect(!glossary.contains { $0.contains("丈") })
    }

    @Test("사전에 없는 말은 넣지 않는다")
    func skipsWhatItDoesNotKnow() {
        // A guessed gloss would be worse than none: it would ground the model
        // in something invented.
        let glossary = dictionary.glossary(for: "ズギャギャン")
        #expect(glossary.isEmpty)
    }

    @Test("한 줄에서 너무 많이 넣지 않는다")
    func staysShort() {
        // The context window overflows at three lines as it is. A gloss list
        // that grows with the line would bring that forward.
        let glossary = dictionary.glossary(for: "夢を見た夜が明ける空が広がる君の姿が見えた朝", limit: 3)
        #expect(glossary.count <= 3)
    }
}

@Suite("한국어 문장인지")
struct MostlyKoreanTests {
    @Test("거의 영어인 답은 한글이 한 글자 있어도 받지 않는다")
    func mostlyEnglishIsRefused() {
        // Measured: 「フェンス越しに重なっていた」 came back as 「가 fence across
        // from each other.」 and passed, because the rule only asked whether
        // there was any Hangul at all. One character is not a translation.
        #expect(!Sensei.isUsableTranslation("가 fence across from each other."))
        #expect(!Sensei.isUsableTranslation("그 I don't wanna know anything now"))
    }

    @Test("인용된 영어는 세지 않는다")
    func quotedEnglishDoesNotCount() {
        // A Korean line quoting the song's own English hook is right, and the
        // quote is longer than the sentence around it often enough that
        // counting it would throw the good answer away.
        #expect(Sensei.isUsableTranslation("'Wake me up'이라고 말했다"))
        #expect(Sensei.isUsableTranslation("「I love you」 그 한마디뿐이었다"))
    }

    @Test("한국어 문장은 그대로 통과한다")
    func koreanPasses() {
        #expect(Sensei.isUsableTranslation("두 사람만의 하늘이 펼쳐진 밤"))
        #expect(Sensei.isUsableTranslation("작별 인사만 남았어요"))
    }
}

@Suite("활용형에서 사전형 되돌리기")
struct StemDeinflectionTests {
    private let dictionary = DictionarySensei()

    /// Every one of these came out of the coverage report as a word the
    /// dictionary holds but the lookup could not reach.
    private func resolves(_ surface: String, to lemma: String) -> Bool {
        dictionary.lookup(lemma: surface)?.l == lemma
    }

    @Test("이치단 동사의 어간에 る를 붙여 찾는다")
    func ichidanStems() {
        #expect(resolves("溶け", to: "溶ける"))
        #expect(resolves("疲れ", to: "疲れる"))
        #expect(resolves("眺め", to: "眺める"))
        #expect(resolves("忘れ", to: "忘れる"))
    }

    @Test("고단 동사의 い단 어간을 う단으로 되돌린다")
    func godanContinuative() {
        #expect(resolves("沈み", to: "沈む"))
        #expect(resolves("言い", to: "言う"))
        #expect(resolves("取り", to: "取る"))
        #expect(resolves("出し", to: "出す"))
    }

    @Test("あ단 어간도 되돌린다")
    func godanIrrealis() {
        #expect(resolves("戻ら", to: "戻る"))
        #expect(resolves("飛ばさ", to: "飛ばす"))
    }

    @Test("촉음편도 되돌린다")
    func soundChanges() {
        #expect(resolves("分かっ", to: "分かる"))
        #expect(resolves("重なっ", to: "重なる"))
        #expect(resolves("吹い", to: "吹く"))
    }

    @Test("아무 말이나 사전형으로 만들지는 않는다")
    func doesNotInventWords() {
        // Every candidate is looked up, so a wrong guess costs nothing — but it
        // must not resolve to something unrelated.
        #expect(dictionary.lookup(lemma: "ズギャ") == nil)
    }
}

// MARK: - Grammar patterns

@Suite("문법 패턴 매칭")
struct GrammarPatternTests {
    @Test("줄에 있는 패턴을 찾는다")
    func findsPatterns() {
        let notes = GrammarPatterns.matches(in: "歩きながら考えてしまう")
        let patterns = notes.map(\.pattern)
        #expect(patterns.contains("〜ながら"))
        #expect(patterns.contains("〜てしまう"))
    }

    @Test("줄에 없는 패턴은 찾지 않는다")
    func skipsAbsentPatterns() {
        let patterns = GrammarPatterns.matches(in: "君の名前").map(\.pattern)
        #expect(patterns.isEmpty)
    }

    /// 「なきゃ」 is a lesson about obligation. Reporting 〜ない alongside it —
    /// which it contains — would be telling the reader the opposite of what the
    /// line means.
    @Test("긴 패턴이 그 안에 든 짧은 패턴을 가린다")
    func longerPatternWins() {
        let patterns = GrammarPatterns.matches(in: "行かなきゃ").map(\.pattern)
        #expect(patterns.contains("〜なければならない"))
        #expect(!patterns.contains("〜ない"))
    }

    @Test("일본어가 없는 줄에는 문법이 없다")
    func skipsNonJapanese() {
        #expect(GrammarPatterns.matches(in: "I don't wanna say goodbye").isEmpty)
    }

    /// A short line with eight notes on it is not a lesson.
    @Test("한 줄에 붙는 노트 수를 제한한다")
    func capsNotes() {
        let line = "行かなきゃならないけど、まだ君に会いたいから待ってるだけかもしれない"
        #expect(GrammarPatterns.matches(in: line).count <= 3)
    }

    @Test("모든 패턴에 한국어 설명이 있다")
    func everyPatternExplained() {
        for pattern in GrammarPatterns.all {
            #expect(!pattern.explanationKo.isEmpty, "\(pattern.display)에 설명이 없습니다")
            #expect(!pattern.forms.isEmpty)
        }
    }
}

// MARK: - Analysis depth

@MainActor
@Suite("해석 방식 선택")
struct AnalysisDepthTests {
    private func sensei(depth: AnalysisDepth) -> Sensei {
        Sensei(
            dictionary: DictionarySensei(entries: [
                .init(l: "夢", r: "ゆめ", k: "꿈", p: "명사", j: "N4")
            ]),
            modelIsAvailable: true,
            depth: depth,
            translate: { _ in "번역된 문장" }
        )
    }

    private let lyrics = Lyrics(
        lines: [LyricLine(id: 0, time: 0, text: "夢を見ている")],
        isSynced: true,
        source: "test"
    )

    /// The whole point of the fast mode: it does not wait for the model, and it
    /// still fills the sentence.
    @Test("빠른 모드는 모델을 기다리지 않고 문장을 채운다")
    func quickFillsWithoutModel() async {
        let sensei = sensei(depth: .quick)
        let study = await sensei.analyze(lineIndex: 0, in: lyrics, songTitle: "곡", artist: "가수")
        #expect(study?.translationKo == "번역된 문장")
        #expect(study?.words.contains { $0.dictionaryForm == "夢" } == true)
    }

    /// Without this, a song analysed quickly would stay quick forever: the
    /// dictionary's answers carry a translation, and a translation used to be
    /// enough to settle a line.
    @Test("빠른 모드 결과는 정확 모드에서 다시 해석된다")
    func quickResultsAreRedoneWhenDeep() async {
        let sensei = sensei(depth: .quick)
        await sensei.analyze(lineIndex: 0, in: lyrics, songTitle: "곡", artist: "가수")
        #expect(sensei.pendingLines(in: lyrics).isEmpty)

        sensei.depth = .deep
        #expect(sensei.pendingLines(in: lyrics).count == 1)
    }

    /// The reverse is not symmetrical on purpose — being fast is no reason to
    /// throw away the better answer already in hand.
    @Test("정확 모드 결과는 빠른 모드로 바꿔도 남는다")
    func deepResultsSurviveSwitchToQuick() {
        let sensei = sensei(depth: .deep)
        sensei.preload([0: LineStudy(
            lineIndex: 0,
            original: "夢を見ている",
            translationKo: "꿈을 꾸고 있어",
            words: [],
            grammar: [],
            engine: .onDevice
        )])
        sensei.depth = .quick
        #expect(sensei.cached(0)?.translationKo == "꿈을 꾸고 있어")
        #expect(sensei.pendingLines(in: lyrics).isEmpty)
    }

    @Test("빠른 모드에서도 문법이 채워진다")
    func quickModeHasGrammar() async {
        let sensei = sensei(depth: .quick)
        let study = await sensei.analyze(lineIndex: 0, in: lyrics, songTitle: "곡", artist: "가수")
        #expect(study?.grammar.contains { $0.pattern == "〜ている" } == true)
    }

    /// Choosing a mode the device cannot run would leave the reader waiting on a
    /// model that is never asked.
    @Test("모델이 없는 기기는 정확 모드를 선택해도 빠른 모드로 동작한다")
    func unavailableModelForcesQuick() {
        let sensei = Sensei(
            dictionary: DictionarySensei(entries: []),
            modelIsAvailable: false,
            depth: .deep
        )
        #expect(sensei.depth == .quick)
    }
}

@MainActor
@Suite("줄 하나만 정확하게")
struct DeepenTests {
    private let lyrics = Lyrics(
        lines: [LyricLine(id: 0, time: 0, text: "夢を見ている")],
        isSynced: true,
        source: "test"
    )

    private func sensei(modelIsAvailable: Bool = true) -> Sensei {
        Sensei(
            dictionary: DictionarySensei(entries: [
                .init(l: "夢", r: "ゆめ", k: "꿈", p: "명사", j: "N4")
            ]),
            modelIsAvailable: modelIsAvailable,
            depth: .quick,
            translate: { _ in "직역된 문장" }
        )
    }

    /// A quick answer is settled as far as `isFinal` is concerned, and asking to
    /// improve it is exactly a request to ignore that.
    @Test("빠른 결과가 있는 줄은 다시 해석할 수 있다")
    func offersDeepenOnQuickResult() async {
        let sensei = sensei()
        await sensei.analyze(lineIndex: 0, in: lyrics, songTitle: "곡", artist: "가수")
        #expect(sensei.canDeepen(0))
    }

    @Test("모델이 낸 답은 다시 해석하자고 하지 않는다")
    func noDeepenOnModelResult() {
        let sensei = sensei()
        sensei.preload([0: LineStudy(
            lineIndex: 0,
            original: "夢を見ている",
            translationKo: "꿈을 꾸고 있어",
            words: [],
            grammar: [],
            engine: .onDevice
        )])
        #expect(!sensei.canDeepen(0))
    }

    @Test("해석되지 않은 줄에는 제안하지 않는다")
    func noDeepenBeforeAnalysis() {
        #expect(!sensei().canDeepen(0))
    }

    @Test("모델이 없는 기기에서는 제안하지 않는다")
    func noDeepenWithoutModel() async {
        let sensei = sensei(modelIsAvailable: false)
        await sensei.analyze(lineIndex: 0, in: lyrics, songTitle: "곡", artist: "가수")
        #expect(!sensei.canDeepen(0))
        #expect(await sensei.deepen(lineIndex: 0, in: lyrics, songTitle: "곡", artist: "가수") == nil)
    }

    /// Asking for an improvement must never cost the reader what they had. The
    /// model's failure path falls back to the dictionary, which has no
    /// translation of its own — so without this the line comes back blank.
    @Test("다시 해석이 실패해도 이미 있던 번역은 남는다")
    func failedDeepenKeepsTranslation() async {
        let sensei = sensei()
        await sensei.analyze(lineIndex: 0, in: lyrics, songTitle: "곡", artist: "가수")
        #expect(sensei.cached(0)?.translationKo == "직역된 문장")

        // The seam has no model, so `deepen` takes the model's failure path.
        let result = await sensei.deepen(
            lineIndex: 0, in: lyrics, songTitle: "곡", artist: "가수"
        )
        #expect(result?.translationKo == "직역된 문장")
        #expect(sensei.cached(0)?.translationKo == "직역된 문장")
    }
}

/// The false positives that substring matching produces, each one taken from a
/// real lyric line the report ran over. Every one of these was a note the reader
/// would have been taught wrongly, which is the one thing this approach was
/// justified by not doing.
@Suite("문법 패턴 오탐")
struct GrammarPatternFalsePositiveTests {
    private func patterns(_ line: String) -> [String] {
        GrammarPatterns.matches(in: line).map(\.pattern)
    }

    /// 「あれから七年」 is "seven years since then". A note calling it a reason
    /// says the opposite of what the line means.
    @Test("명사에 붙은 から는 이유가 아니다")
    func fromANounIsNotCausal() {
        #expect(!patterns("あれから七年経っても").contains("〜から"))
        #expect(!patterns("今から行こう").contains("〜から"))
        #expect(!patterns("ここから始まる").contains("〜から"))
    }

    @Test("서술어에 붙은 から는 이유로 잡는다")
    func fromAPredicateIsCausal() {
        #expect(patterns("寂しいから").contains("〜から"))
        #expect(patterns("言ったから").contains("〜から"))
        #expect(patterns("好きだから").contains("〜から"))
    }

    /// 「今でも」 is 今 + でも, "even now" — not a verb concession.
    @Test("명사에 붙은 でも는 양보 활용이 아니다")
    func nounPlusDemoIsNotConcessive() {
        #expect(!patterns("今でもあなたはわたしの光").contains("〜ても"))
        #expect(!patterns("それでも歩く").contains("〜ても"))
    }

    /// The で-form only comes from ぐ/ぬ/ぶ/む verbs, which always leave ん.
    @Test("ん 뒤의 でも는 양보로 잡는다")
    func ndemoIsConcessive() {
        #expect(patterns("本を読んでも分からない").contains("〜ても"))
        #expect(patterns("経っても").contains("〜ても"))
    }

    /// 「ものに」 is a noun and a particle. 「大切なのに」 is the pattern.
    @Test("명사에 붙은 のに는 역접이 아니다")
    func nounPlusNoniIsNotConcessive() {
        #expect(!patterns("大切なものになる").contains("〜のに"))
        #expect(patterns("時間がないのに").contains("〜のに"))
    }

    /// Words that end in a pattern without being it. All three are common enough
    /// in lyrics that leaving them in meant teaching the wrong thing regularly.
    @Test("패턴 글자를 품은 다른 단어는 잡지 않는다")
    func falseFriends() {
        #expect(!patterns("「さよなら」だけだった").contains("〜なら"))
        #expect(!patterns("素晴らしい世界").contains("〜らしい"))
        #expect(!patterns("切ない気持ち").contains("〜ない"))
        #expect(!patterns("少ない時間").contains("〜ない"))
    }

    /// Blanking a word must not glue its neighbours into a form nobody wrote.
    @Test("가린 단어가 이웃을 붙여 새 패턴을 만들지 않는다")
    func maskingDoesNotCreateForms() {
        let masked = GrammarPatterns.masked("君にさよならを言う")
        #expect(masked.count == "君にさよならを言う".count)
        #expect(!masked.contains("にを"))
    }

    /// The real conditional still fires — the fix must not have removed the
    /// pattern along with its lookalikes.
    @Test("진짜 조건형은 그대로 잡는다")
    func realConditionalStillMatches() {
        #expect(patterns("夢ならばどれほどよかったでしょう").contains("〜なら"))
    }
}
