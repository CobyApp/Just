import Foundation
import FoundationModels

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
    /// The system's model machinery failed, whatever the words: on iOS 27 a
    /// safety classifier that errored out (SensitiveContentAnalysisML 15), or
    /// a model the system could not load. Every line fails the same way.
    case system
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
        case .system: "시스템 오류"
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
        case .system:
            "기기의 AI가 요청을 처리하지 못했습니다. 기기를 재시동하거나 Apple Intelligence 설정을 확인해 보세요."
        case .contextWindow, .decoding, .other:
            "지금은 이 줄을 번역하지 못했습니다."
        }
    }
}

public extension ModelFailure {
    /// The failure for any error the model throws — the iOS 26 error type,
    /// the iOS 27 one, and the bare `NSError` the system sometimes passes up
    /// without either.
    init(_ error: any Error) {
        if let error = error as? LanguageModelSession.GenerationError {
            self = switch error {
            case .guardrailViolation: .guardrail
            case .refusal: .refused
            case .exceededContextWindowSize: .contextWindow
            case .assetsUnavailable: .assetsMissing
            case .rateLimited: .rateLimited
            case .concurrentRequests: .concurrent
            case .decodingFailure: .decoding
            default: .other
            }
            return
        }
        // `LanguageModelError` exists only in the iOS 27 SDK. `#available`
        // is decided at run time, so on the Xcode 26 toolchain the type is not
        // even there to name and the build fails; the compiler check keeps it
        // out. Built with the older SDK, these errors still land below, on
        // the NSError domain.
        #if compiler(>=6.4)
        if #available(iOS 27.0, *), let error = error as? LanguageModelError {
            self = switch error {
            case .guardrailViolation: .guardrail
            case .refusal: .refused
            case .contextSizeExceeded: .contextWindow
            case .rateLimited: .rateLimited
            default: .other
            }
            return
        }
        #endif
        let ns = error as NSError
        let description = String(describing: error)
        if ns.domain.contains("LanguageModelError") || description.contains("SensitiveContentAnalysis") || description.contains("ModelManager") {
            self = .system
            return
        }
        self = .other
    }
}
