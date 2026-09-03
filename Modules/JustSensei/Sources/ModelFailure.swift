import Foundation

/// Why the model did not answer a line.
///
/// Recorded rather than swallowed. The fallback is deliberately quiet — a
/// reader working through a song has no use for the news that a guardrail
/// fired — but two callers do need it. The report needs it to tell a
/// measurement of the model apart from a run where it never spoke. And the line
/// sheet needs it the moment someone taps 「이 줄만 정확하게」: an explicit
/// request that silently changes nothing is the worst of the three possible
/// outcomes.
public enum ModelFailure: Sendable, Equatable {
    /// The words themselves were refused. J-pop is full of parting and death,
    /// so this is not rare — 「夜に駆ける」 tripped it three times in nine lines.
    case guardrail
    case refused
    case contextWindow
    case assetsMissing
    case rateLimited
    case concurrent
    case decoding
    case other

    /// Short label, for counting in the report.
    public var label: String {
        switch self {
        case .guardrail: "가드레일"
        case .refused: "거부"
        case .contextWindow: "문맥 초과"
        case .assetsMissing: "모델 자산 없음"
        case .rateLimited: "속도 제한"
        case .concurrent: "동시 요청"
        case .decoding: "응답 해석 실패"
        case .other: "그 외 생성 오류"
        }
    }

    /// What to tell the reader who asked for this line and got nothing.
    ///
    /// Only where there is something true and useful to say. A decoding failure
    /// means nothing to anyone outside this file, so it gets the plain sentence
    /// rather than a name that sounds like their fault.
    public var readerExplanation: String {
        switch self {
        case .guardrail, .refused:
            "이 줄은 AI가 번역을 거절했습니다. 가사 내용 때문일 수 있습니다."
        case .rateLimited, .concurrent:
            "지금은 처리할 수 없었습니다. 잠시 뒤에 다시 눌러 보세요."
        case .assetsMissing:
            "지금은 AI 번역을 쓸 수 없습니다."
        case .contextWindow, .decoding, .other:
            "지금은 이 줄을 번역하지 못했습니다."
        }
    }
}
