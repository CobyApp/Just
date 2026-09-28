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

    /// Words the JLPT lists rate, N5 to N1.
    public var ratedTotal: Int { total - unratedCount }

    /// Words outside the JLPT lists: loanwords in katakana, names, slang.
    /// A large slice of any idol song, and not a measure of how hard it is —
    /// 「キラキラ」 is not harder than N1 — so they are kept out of the level.
    public var unratedCount: Int { counts[.beyond] ?? 0 }

    /// The level a learner needs to follow most of the song.
    ///
    /// Reported as a coverage threshold rather than a maximum, because one
    /// obscure word does not make a song an N1 song — but needing N1 for a
    /// quarter of the lines does. Measured over the rated words only: counted
    /// as harder than N1, the unrated ones made nearly every song 「범위 밖」,
    /// which says nothing. `.beyond` only when nothing in the song is rated.
    public var comprehensionLevel: JLPTLevel? {
        guard total > 0 else { return nil }
        guard ratedTotal > 0 else { return .beyond }
        let goal = Double(ratedTotal) * Self.coverageTarget
        var running = 0
        for level in JLPTLevel.allCases.sorted(by: <) where level != .beyond {
            running += counts[level] ?? 0
            if Double(running) >= goal { return level }
        }
        return .n1
    }

    /// Words at N2 or N1 — the ones that will actually need looking up.
    public var advancedCount: Int {
        (counts[.n2] ?? 0) + (counts[.n1] ?? 0)
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
        let en = AppLanguage.current == .en
        let level: String
        if comprehensionLevel == .beyond {
            level = en ? "Beyond JLPT" : "JLPT 범위 밖"
        } else {
            level = en ? "\(comprehensionLevel.rawValue) level" : "\(comprehensionLevel.rawValue) 수준"
        }
        guard advancedCount > 0 else { return level }
        return en
            ? "\(level) · \(advancedCount) hard words"
            : "\(level) · 어려운 단어 \(advancedCount)개"
    }

    public var detail: String {
        let en = AppLanguage.current == .en
        guard let comprehensionLevel, comprehensionLevel != .beyond else {
            return en
                ? "A song with many words outside the JLPT levels."
                : "JLPT 등급 밖 단어가 많은 곡입니다."
        }
        let rated = en
            ? "75% of the JLPT words are \(comprehensionLevel.rawValue) or easier."
            : "JLPT 단어의 75%가 \(comprehensionLevel.rawValue) 이하입니다."
        guard unratedCount > 0 else { return rated }
        return en
            ? rated + " \(unratedCount) ungraded words (loanwords, names) are counted separately."
            : rated + " 외래어·이름처럼 등급이 없는 단어 \(unratedCount)개는 따로 셉니다."
    }
}
