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
        self == .beyond ? "범위 밖" : rawValue
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
}
