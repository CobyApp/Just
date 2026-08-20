import Foundation
import FoundationModels
import JustCore

// MARK: - Guided generation schema

/// The shape the on-device model is constrained to produce.
///
/// Guided generation is what makes this viable at 3B parameters: the model
/// never has to invent JSON, so the only thing it can get wrong is the
/// *content*, not the structure.
@Generable
struct GeneratedLine {
    @Guide(description: "가사 한 줄의 한국어 번역. 직역이 아니라 노래 가사로 자연스럽게 읽히도록.")
    var translation: String

    @Guide(
        description: "이 줄에서 한국인 학습자에게 배울 가치가 있는 단어. 조사와 극히 기본적인 단어는 넣지 말 것.",
        .maximumCount(6)
    )
    var words: [GeneratedWord]

    @Guide(
        description: "이 줄에 쓰인 문법 패턴이나 관용 표현. 특별한 게 없으면 빈 배열.",
        .maximumCount(3)
    )
    var grammar: [GeneratedGrammar]
}

@Generable
struct GeneratedWord {
    @Guide(description: "가사에 나온 그대로의 형태. 예: 歩いてる")
    var surface: String

    @Guide(description: "사전에 실리는 기본형. 예: 歩く")
    var dictionaryForm: String

    @Guide(description: "기본형의 히라가나 읽기. 히라가나만 사용. 예: あるく")
    var reading: String

    @Guide(description: "한국어 뜻. 한 줄로 간결하게.")
    var meaningKo: String

    @Guide(
        description: "품사",
        .anyOf(["명사", "동사", "い형용사", "な형용사", "부사", "표현", "기타"])
    )
    var partOfSpeech: String

    @Guide(
        description: "JLPT 등급. 어느 등급에도 없는 속어·방언이면 圏外.",
        .anyOf(["N5", "N4", "N3", "N2", "N1", "圏外"])
    )
    var jlpt: String

    @Guide(
        description: "가사 속 형태가 기본형과 다른 이유(활용·축약·구어체)나 뉘앙스. JLPT 등급 이야기는 쓰지 않습니다. 설명할 게 없으면 빈 문자열."
    )
    var note: String
}

@Generable
struct GeneratedGrammar {
    @Guide(description: "문법 패턴. 예: 〜てしまう")
    var pattern: String

    @Guide(description: "이 패턴이 여기서 어떤 의미인지 한국어로 한두 문장.")
    var explanationKo: String
}

// MARK: - Engine

/// Wraps Apple Intelligence's on-device language model.
///
/// Main-actor isolated on purpose: a `LanguageModelSession` must not receive
/// overlapping `respond` calls, and pinning it to one actor makes that
/// impossible to get wrong from the UI. Inference itself runs off-thread, so
/// this does not block scrolling.
@MainActor
public final class OnDeviceSensei {
    public enum Unavailability: Sendable {
        case deviceNotEligible
        case notEnabled
        case modelNotReady
        case unknown

        public var message: String {
            switch self {
            case .deviceNotEligible:
                "이 기기는 Apple Intelligence를 지원하지 않아 사전 모드로 동작합니다."
            case .notEnabled:
                "설정 > Apple Intelligence에서 기능을 켜면 AI 해설을 쓸 수 있습니다."
            case .modelNotReady:
                "모델을 내려받는 중입니다. 잠시 후 다시 시도해 주세요."
            case .unknown:
                "온디바이스 모델을 쓸 수 없어 사전 모드로 동작합니다."
            }
        }
    }

    private static let instructions = """
    당신은 J-POP 가사로 일본어를 가르치는 선생님입니다. 학습자는 한국인입니다.

    지켜야 할 것:
    - 설명은 모두 한국어 '~합니다'체로 씁니다. 반말을 쓰지 않습니다.
    - dictionaryForm에는 사전 표제어 표기를 그대로 씁니다. 한자로 적는 단어는 한자로 씁니다.
      예: 「夢」의 dictionaryForm은 「夢」이고 reading이 「ゆめ」입니다. 「ゆめ」를 표제어로 쓰지 않습니다.
    - 가사는 구어체·축약·도치·생략이 많습니다. 「〜てる」(→ている), 「〜じゃん」, 「〜んだ」,
      ら抜き言葉 같은 형태를 만나면 반드시 사전형으로 되돌려서 dictionaryForm에 넣고,
      원래 형태는 surface에 그대로 둔 뒤 note에 무엇이 줄어든 것인지 적습니다.
    - reading은 사전형의 히라가나 읽기입니다. 로마자나 한자를 섞지 않습니다.
    - 조사(は, が, を, に, で…)와 N5 수준의 아주 기본적인 단어는 words에 넣지 않습니다.
      한 줄에서 정말 배울 가치가 있는 것만 고릅니다.
    - 번역은 뜻이 통하는 한국어 문장으로 씁니다. 어색한 직역을 하지 않습니다.
    - 모르는 것은 지어내지 않습니다. 확신이 없으면 jlpt를 圏外로 둡니다.
    """

    private var session: LanguageModelSession
    private let tokenizer = JapaneseTokenizer()
    /// When to stop reusing the session. See `SessionRecycler` for the balance
    /// it strikes.
    private var recycler = SessionRecycler()

    public init() {
        session = LanguageModelSession { Self.instructions }
    }

    public static var availability: Unavailability? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .notEnabled
            case .modelNotReady: return .modelNotReady
            @unknown default: return .unknown
            }
        @unknown default:
            return .unknown
        }
    }

    public static var isAvailable: Bool { availability == nil }

    /// Warms the model so the first tap isn't the slow one.
    public func prewarm() {
        session.prewarm()
    }

    private func respond(
        to prompt: String
    ) async throws -> LanguageModelSession.Response<GeneratedLine> {
        try await session.respond(
            to: prompt,
            generating: GeneratedLine.self,
            options: GenerationOptions(temperature: 0.3)
        )
    }

    /// Forgets what the model was told about the song being left behind.
    ///
    /// The next line builds its own session, so nothing from the old song is in
    /// context when the new one is asked about.
    public func startFresh() {
        recycler.startFresh()
    }

    /// Analyses one line. The line above is passed as context because a lyric
    /// line is often a fragment whose subject lives there.
    ///
    /// The line *below* is not passed, though the caller still offers it. Measured
    /// over six lines, two came back translated as their neighbour — 「さよなら」
    /// だけだった answered with the meaning of the line after it — and the pair of
    /// translations were near-identical. Naming the target more insistently in the
    /// prompt did not help when this was tried before. Removing the line it was
    /// copying is the other way at it, and the original reason for context only
    /// ever argued for the line above.
    public func analyze(
        line: String,
        lineIndex: Int,
        previous: String?,
        next: String?,
        songTitle: String,
        artist: String
    ) async throws -> LineStudy {
        // Tagged delimiters rather than Korean labels like "분석할 줄:".
        // A 3B model reads a bare label as content — labelling the target with
        // the word 분석 produced vocabulary cards for 分析する on a line that
        // contains no such word.
        var prompt = "곡: \(artist) - \(songTitle)\n\n"
        if let previous, !previous.isEmpty {
            prompt += "<before>\(previous)</before>\n"
        }
        prompt += "<target>\(line)</target>\n"
        prompt += """

        <target> 안의 일본어 문장만 다루세요. <before>는 문맥 파악에만 쓰고 결과에
        넣지 않습니다. words에는 <target> 문장에 실제로 나오는 표현만 넣습니다.
        """

        if recycler.claim() {
            session = LanguageModelSession { Self.instructions }
        }

        let response: LanguageModelSession.Response<GeneratedLine>
        do {
            response = try await respond(to: prompt)
        } catch let error as LanguageModelSession.GenerationError {
            // A transcript that outgrew the window, not a prompt that is too
            // long: the session is finished either way, and every later line
            // asked of it fails too. Counting lines cannot prevent this — how
            // much a line costs depends on how long it is and how much the
            // model finds to say about it — so the count is the common case and
            // this is the guarantee.
            guard case .exceededContextWindowSize = error else { throw error }
            recycler.startFresh()
            if recycler.claim() {
                session = LanguageModelSession { Self.instructions }
            }
            // Once. A fresh session that still overflows is a line that does
            // not fit at all, and the caller's dictionary fallback is right.
            response = try await respond(to: prompt)
        }
        return Self.study(from: response.content, line: line, lineIndex: lineIndex)
    }

    private static func study(
        from generated: GeneratedLine,
        line: String,
        lineIndex: Int
    ) -> LineStudy {
        let words = generated.words.compactMap { word -> StudyWord? in
            let dictionaryForm = word.dictionaryForm.trimmingCharacters(in: .whitespaces)
            guard !dictionaryForm.isEmpty else { return nil }
            let surface = word.surface.trimmingCharacters(in: .whitespaces)
            return StudyWord(
                surface: surface.isEmpty ? dictionaryForm : surface,
                dictionaryForm: dictionaryForm,
                reading: normalizedReading(word.reading, fallback: dictionaryForm),
                meaningKo: word.meaningKo.trimmingCharacters(in: .whitespaces),
                partOfSpeech: PartOfSpeech(rawTag: word.partOfSpeech),
                jlpt: JLPTLevel(rawTag: word.jlpt),
                note: word.note.trimmingCharacters(in: .whitespaces)
            )
        }

        return LineStudy(
            lineIndex: lineIndex,
            original: line,
            translationKo: generated.translation.trimmingCharacters(in: .whitespaces),
            words: words,
            grammar: generated.grammar
                .filter { !$0.pattern.isEmpty }
                .map { GrammarNote(pattern: $0.pattern, explanationKo: $0.explanationKo) },
            engine: .onDevice
        )
    }

    /// The model occasionally answers with romaji or leaves kanji in the
    /// reading field. Both are recoverable with ICU, so repair rather than drop.
    private static func normalizedReading(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed.allSatisfy({ $0.isHiragana || $0 == "ー" }) {
            return trimmed
        }
        if !trimmed.isEmpty, !trimmed.containsKanji {
            return trimmed.toHiragana()
        }
        return fallback.toHiragana()
    }
}
