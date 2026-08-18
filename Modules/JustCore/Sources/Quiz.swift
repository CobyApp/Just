import Foundation

public enum QuizKind: String, CaseIterable, Sendable {
    /// The lyric line with the word removed — the learner types it back in.
    case cloze
    /// Korean meaning shown, Japanese word typed.
    case recall
    /// Japanese word shown, meaning picked from four options.
    case choice

    public var title: String {
        switch self {
        case .cloze: "빈칸 채우기"
        case .recall: "뜻 보고 쓰기"
        case .choice: "사지선다"
        }
    }

    public var detail: String {
        switch self {
        case .cloze: "가사에서 단어를 지웠습니다. 노래를 떠올리며 채워 보세요."
        case .recall: "한국어 뜻만 보고 일본어를 직접 씁니다. 가장 어렵습니다."
        case .choice: "네 개 중 하나를 고릅니다. 빠르게 훑을 때 좋습니다."
        }
    }

    public var symbol: String {
        switch self {
        case .cloze: "square.dashed"
        case .recall: "pencil.line"
        case .choice: "list.bullet.circle"
        }
    }

    /// Whether answering means typing rather than tapping.
    public var isTyped: Bool { self != .choice }
}

/// One question, fully resolved so the quiz view needs no store access.
public struct QuizQuestion: Identifiable, Sendable {
    public let id: String
    public let kind: QuizKind
    /// What the learner reads: a lyric line with a gap, or a Korean meaning.
    public let prompt: String
    /// Shown under the prompt — the song, or nothing.
    public let context: String?
    /// Every spelling that counts as correct.
    public let acceptedAnswers: [String]
    /// Shown after answering.
    public let expected: String
    public let expectedReading: String
    public let meaning: String
    /// Choices for `.choice`, the first of which is correct.
    public let options: [String]
    /// Key of the `VocabEntry` this came from, so grading can find it again.
    public let entryKey: String
    /// The song alone, for prompts that must not reveal the meaning yet.
    public let songLabelOnly: String?

    public init(
        id: String,
        kind: QuizKind,
        prompt: String,
        context: String?,
        acceptedAnswers: [String],
        expected: String,
        expectedReading: String,
        meaning: String,
        options: [String] = [],
        entryKey: String,
        songLabelOnly: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.prompt = prompt
        self.context = context
        self.acceptedAnswers = acceptedAnswers
        self.expected = expected
        self.expectedReading = expectedReading
        self.meaning = meaning
        self.options = options
        self.entryKey = entryKey
        self.songLabelOnly = songLabelOnly
    }

    /// The placeholder a cloze prompt leaves behind.
    public static let blank = "＿＿＿"
}

public enum QuizOutcome: Sendable {
    case correct
    /// Right word, wrong form — a near miss is worth distinguishing so it can
    /// be graded "hard" rather than "again".
    case close
    case wrong

    public var grade: ReviewGrade {
        switch self {
        case .correct: .good
        case .close: .hard
        case .wrong: .again
        }
    }
}
