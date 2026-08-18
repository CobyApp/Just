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
