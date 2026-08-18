import Foundation

/// How hard a song's vocabulary is, derived from the words the analyser found.
///
/// The app can currently tell you nothing about a song until you are already
/// inside it reading. A learner picking their next song wants to know whether
/// it is within reach *before* committing twenty minutes to it.
public struct SongDifficulty: Sendable, Equatable {
    public let counts: [JLPTLevel: Int]

    public init(counts: [JLPTLevel: Int]) {
        self.counts = counts.filter { $0.value > 0 }
    }

    /// Builds from the persisted `[rawLevel: count]` dictionary.
    public init(raw: [String: Int]) {
        self.init(
            counts: Dictionary(
                raw.map { (JLPTLevel(rawTag: $0.key), $0.value) },
                uniquingKeysWith: +
            )
        )
    }

    public var total: Int { counts.values.reduce(0, +) }
    public var isEmpty: Bool { total == 0 }

    /// Fraction of the song's vocabulary covered at or below `coverageTarget`.
    private static let coverageTarget = 0.75

    /// The level a learner needs to follow most of the song.
    ///
    /// Reported as a coverage threshold rather than a maximum, because one
    /// obscure word does not make a song an N1 song — but needing N1 for a
    /// quarter of the lines does.
    public var comprehensionLevel: JLPTLevel? {
        guard total > 0 else { return nil }
        let goal = Double(total) * Self.coverageTarget
        var running = 0
        for level in JLPTLevel.allCases.sorted(by: <) {
            running += counts[level] ?? 0
            if Double(running) >= goal { return level }
        }
        return .beyond
    }

    /// Words at N2 or harder — the ones that will actually need looking up.
    public var advancedCount: Int {
        counts.filter { $0.key >= .n2 }.values.reduce(0, +)
    }

    /// Levels easiest-first, for a stacked bar.
    public var breakdown: [(level: JLPTLevel, count: Int)] {
        JLPTLevel.allCases
            .sorted(by: <)
            .compactMap { level in
                guard let count = counts[level], count > 0 else { return nil }
                return (level, count)
            }
    }

    public var summary: String {
        guard let comprehensionLevel else { return "" }
        let level = comprehensionLevel == .beyond
            ? "JLPT 범위 밖"
            : "\(comprehensionLevel.rawValue) 수준"
        return advancedCount > 0
            ? "\(level) · 어려운 단어 \(advancedCount)개"
            : level
    }

    public var detail: String {
        guard let comprehensionLevel, comprehensionLevel != .beyond else {
            return "JLPT 등급 밖 단어가 많은 곡입니다."
        }
        return "이 곡 단어의 75%가 \(comprehensionLevel.rawValue) 이하입니다."
    }
}
