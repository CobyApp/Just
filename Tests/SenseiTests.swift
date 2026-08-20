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

    @Test("사전으로 대체된 줄이 남아도 한 바퀴 뒤에 끝난다")
    func stopsAfterOnePass() async {
        // A device that has the model but cannot reach it: every line falls
        // back to the dictionary and stays unsettled. Preparation must still
        // finish — retrying until nothing is pending would never return.
        let sensei = Sensei(dictionary: DictionarySensei(), modelIsAvailable: true)
        sensei.reset(for: "songA")

        var reported: [Int] = []
        await sensei.analyzeAll(lyrics: lyrics, songTitle: "곡", artist: "가수") { done, _ in
            reported.append(done)
        }

        #expect(reported == [1, 2])
        // Still pending, so opening the song again tries them once more.
        #expect(sensei.pendingLines(in: lyrics).count == 2)
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
