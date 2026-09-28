import Foundation

public enum JLPTLevel: String, CaseIterable, Codable, Sendable, Comparable {
    case n5 = "N5"
    case n4 = "N4"
    case n3 = "N3"
    case n2 = "N2"
    case n1 = "N1"
    /// Slang, dialect, or vocabulary that sits outside the JLPT lists —
    /// which is a large slice of pop lyrics.
    case beyond = "圏外"

    public init(rawTag: String) {
        self = JLPTLevel(rawValue: rawTag.uppercased()) ?? .beyond
    }

    /// Lower is easier. Used for sorting and for the difficulty filter.
    public var order: Int {
        switch self {
        case .n5: 0
        case .n4: 1
        case .n3: 2
        case .n2: 3
        case .n1: 4
        case .beyond: 5
        }
    }

    public var label: String {
        guard self == .beyond else { return rawValue }
        return AppLanguage.current == .ko ? "범위 밖" : "Beyond"
    }

    public static func < (lhs: JLPTLevel, rhs: JLPTLevel) -> Bool {
        lhs.order < rhs.order
    }
}

public enum PartOfSpeech: String, CaseIterable, Codable, Sendable {
    case noun = "명사"
    case verb = "동사"
    case iAdjective = "い형용사"
    case naAdjective = "な형용사"
    case adverb = "부사"
    case particle = "조사"
    case expression = "표현"
    case other = "기타"

    public init(rawTag: String) {
        self = PartOfSpeech(rawValue: rawTag) ?? .other
    }

    /// The chip label, in the app's language. `rawValue` stays Korean because it
    /// is the tag stored in the seed and in saved words; only the display moves.
    public var displayName: String {
        guard AppLanguage.current == .en else { return rawValue }
        switch self {
        case .noun: return "noun"
        case .verb: return "verb"
        case .iAdjective: return "i-adjective"
        case .naAdjective: return "na-adjective"
        case .adverb: return "adverb"
        case .particle: return "particle"
        case .expression: return "expression"
        case .other: return "other"
        }
    }
}
