import Foundation
import Testing

@testable import JustCore

@Suite("FSRS 스케줄링")
struct FSRSTests {
    private let scheduler = FSRS()

    @Test("첫 복습 간격은 다시 < 어려움 < 알맞음 < 쉬움 순으로 길어진다")
    func firstReviewIntervalsAreOrdered() {
        let intervals = ReviewGrade.allCases.map { grade in
            scheduler.schedule(ReviewState(), grade: grade).intervalDays
        }
        #expect(intervals == intervals.sorted())
        #expect(intervals.first == 0)
    }

    @Test("'다시'는 하루가 아니라 같은 세션에 되돌아온다")
    func againComesBackWithinTheSession() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let outcome = scheduler.schedule(ReviewState(), grade: .again, now: now)
        #expect(outcome.phase == .relearning)
        #expect(outcome.due.timeIntervalSince(now) == 600)
    }

    @Test("잘 맞히면 안정도가 커지고 간격이 늘어난다")
    func successGrowsStability() {
        let state = ReviewState()
        let first = scheduler.schedule(state, grade: .good)
        state.apply(first, at: Date(timeIntervalSince1970: 0))

        let second = scheduler.schedule(state, grade: .good, now: Date(timeIntervalSince1970: 86_400 * 4))
        #expect(second.stability > first.stability)
        #expect(second.intervalDays > first.intervalDays)
    }

    @Test("난이도는 1에서 10 사이를 벗어나지 않는다")
    func difficultyStaysInRange() {
        let state = ReviewState()
        var now = Date(timeIntervalSince1970: 0)
        // Ten consecutive failures would drive difficulty past the ceiling
        // without the clamp.
        for _ in 0..<10 {
            state.apply(scheduler.schedule(state, grade: .again, now: now), at: now)
            now.addTimeInterval(86_400)
            #expect(state.difficulty >= 1)
            #expect(state.difficulty <= 10)
        }
    }

    @Test("회상 확률은 시간이 지나면 떨어진다")
    func retrievabilityDecays() {
        let fresh = scheduler.retrievability(elapsedDays: 0, stability: 10)
        let later = scheduler.retrievability(elapsedDays: 30, stability: 10)
        #expect(fresh > later)
        #expect(fresh <= 1)
        #expect(later > 0)
    }

    @Test("복습 횟수와 실패 횟수가 누적된다")
    func countersAccumulate() {
        let state = ReviewState()
        state.apply(scheduler.schedule(state, grade: .good))
        state.apply(scheduler.schedule(state, grade: .again))
        #expect(state.reps == 2)
        #expect(state.lapses == 1)
    }
}

@Suite("연속일수")
struct StreakTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func daysAgo(_ counts: [Int]) -> [Date] {
        counts.compactMap { calendar.date(byAdding: .day, value: -$0, to: now) }
    }

    @Test("기록이 없으면 0")
    func emptyIsZero() {
        #expect(StreakCalculator.streak(days: [], now: now, calendar: calendar) == 0)
    }

    @Test("오늘부터 연속 사흘")
    func countsFromToday() {
        let streak = StreakCalculator.streak(days: daysAgo([0, 1, 2]), now: now, calendar: calendar)
        #expect(streak == 3)
    }

    /// Starting the count at yesterday when today is still empty: otherwise the
    /// streak would read zero every morning, punishing the user for not having
    /// studied yet.
    @Test("오늘 아직 안 했어도 어제까지 이어졌으면 유지된다")
    func todayNotYetStudiedKeepsStreak() {
        let streak = StreakCalculator.streak(days: daysAgo([1, 2, 3]), now: now, calendar: calendar)
        #expect(streak == 3)
    }

    @Test("이틀을 비우면 끊긴다")
    func gapBreaksStreak() {
        let streak = StreakCalculator.streak(days: daysAgo([2, 3, 4]), now: now, calendar: calendar)
        #expect(streak == 0)
    }

    @Test("같은 날 기록이 여러 개여도 하루로 센다")
    func duplicateDaysCountOnce() {
        let sameDay = [now, now.addingTimeInterval(3_600), now.addingTimeInterval(7_200)]
        #expect(StreakCalculator.streak(days: sameDay, now: now, calendar: calendar) == 1)
    }
}

@Suite("곡 난이도")
struct SongDifficultyTests {
    @Test("75% 커버리지 등급을 고른다")
    func picksCoverageLevel() {
        // 8 of 10 words are N4 or easier, so N4 covers the song.
        let difficulty = SongDifficulty(counts: [.n5: 5, .n4: 3, .n1: 2])
        #expect(difficulty.total == 10)
        #expect(difficulty.comprehensionLevel == .n4)
    }

    /// A single hard word should not relabel the whole song — that is why this
    /// is a coverage threshold and not a maximum.
    @Test("어려운 단어 하나가 곡 등급을 끌어올리지 않는다")
    func oneHardWordDoesNotDominate() {
        let difficulty = SongDifficulty(counts: [.n5: 19, .n1: 1])
        #expect(difficulty.comprehensionLevel == .n5)
        #expect(difficulty.advancedCount == 1)
    }

    @Test("절반 이상이 어려우면 등급이 올라간다")
    func hardSongReportsHardLevel() {
        let difficulty = SongDifficulty(counts: [.n5: 2, .n2: 5, .n1: 3])
        #expect(difficulty.comprehensionLevel == .n1)
        #expect(difficulty.advancedCount == 8)
    }

    @Test("비어 있으면 등급이 없다")
    func emptyHasNoLevel() {
        let difficulty = SongDifficulty(counts: [:])
        #expect(difficulty.isEmpty)
        #expect(difficulty.comprehensionLevel == nil)
        #expect(difficulty.summary.isEmpty)
    }

    @Test("막대 그래프는 쉬운 등급부터 나열한다")
    func breakdownIsSortedEasiestFirst() {
        let difficulty = SongDifficulty(counts: [.n1: 1, .n5: 3, .n3: 2])
        #expect(difficulty.breakdown.map(\.level) == [.n5, .n3, .n1])
    }

    @Test("저장된 문자열 딕셔너리에서 복원된다")
    func decodesFromRawCounts() {
        let difficulty = SongDifficulty(raw: ["N5": 2, "N3": 1, "圏外": 1])
        #expect(difficulty.total == 4)
        #expect(difficulty.counts[.beyond] == 1)
    }
}

@Suite("가사 구간")
struct LyricRangeTests {
    private func lyrics(_ lrc: String) -> Lyrics {
        // Built by hand so the test does not depend on the LRC parser.
        let lines = lrc.split(separator: "|").enumerated().map { index, spec in
            let parts = spec.split(separator: "@")
            return LyricLine(
                id: index,
                time: parts.count > 1 ? TimeInterval(parts[1]) : nil,
                text: String(parts[0])
            )
        }
        return Lyrics(lines: lines, isSynced: true, source: "test")
    }

    @Test("구간은 다음 줄이 시작할 때 끝난다")
    func endsAtNextLine() {
        let range = lyrics("a@0|b@10|c@20").range(of: 1)
        #expect(range?.start == 10)
        #expect(range?.end == 20)
    }

    /// A blank "♪" line between verses must not cut the loop short.
    @Test("타임스탬프 없는 빈 줄은 건너뛴다")
    func skipsUntimedLines() {
        let range = lyrics("a@0|b@10|♪|c@30").range(of: 1)
        #expect(range?.end == 30)
    }

    @Test("마지막 줄은 정해진 길이만큼만 반복한다")
    func lastLineUsesFallback() {
        let range = lyrics("a@0|b@10").range(of: 1, fallbackLength: 8)
        #expect(range?.end == 18)
    }

    @Test("동기화되지 않은 가사에는 구간이 없다")
    func plainLyricsHaveNoRange() {
        let plain = Lyrics(
            lines: [LyricLine(id: 0, time: nil, text: "a")],
            isSynced: false,
            source: "test"
        )
        #expect(plain.range(of: 0) == nil)
    }
}

@Suite("해석 남은 시간 추정")
struct AnalysisPaceTests {
    @Test("재본 적이 없으면 추정하지 않는다")
    func noSamplesMeansNoEstimate() {
        #expect(AnalysisPace().estimate(remaining: 10) == nil)
    }

    @Test("한 줄만 재도 추정한다")
    func estimatesFromASingleSample() {
        var pace = AnalysisPace()
        pace.record(10)
        #expect(pace.estimate(remaining: 5) == 50)
    }

    @Test("남은 줄이 없으면 0이다")
    func nothingLeftMeansZero() {
        var pace = AnalysisPace()
        pace.record(10)
        #expect(pace.estimate(remaining: 0) == 0)
    }

    @Test("한 줄이 유난히 오래 걸려도 추정을 지배하지 않는다")
    func oneStallDoesNotDominate() {
        var pace = AnalysisPace()
        for seconds in [10.0, 10.0, 10.0, 600.0] { pace.record(seconds) }
        // 평균이라면 157.5초가 된다.
        #expect(pace.estimate(remaining: 1) == 10)
    }

    @Test("창 밖으로 밀린 표본은 버린다")
    func forgetsSamplesOutsideTheWindow() {
        var pace = AnalysisPace(window: 2)
        for seconds in [100.0, 100.0, 10.0, 10.0] { pace.record(seconds) }
        #expect(pace.estimate(remaining: 1) == 10)
    }

    @Test("말이 안 되는 표본은 세지 않는다")
    func ignoresNonsenseSamples() {
        var pace = AnalysisPace()
        pace.record(-5)
        pace.record(.infinity)
        pace.record(.nan)
        #expect(pace.estimate(remaining: 3) == nil)
    }
}

@Suite("단어 내보내기")
struct VocabularyExportTests {
    private func row(
        lemma: String = "夢",
        meaning: String = "꿈",
        example: String = "夢ならばどれほどよかったでしょう"
    ) -> VocabularyExport.Row {
        .init(
            lemma: lemma,
            reading: "ゆめ",
            meaningKo: meaning,
            jlpt: "N4",
            partOfSpeech: "명사",
            example: example,
            song: "米津玄師 — Lemon"
        )
    }

    @Test("헤더와 행 수가 맞는다")
    func hasHeaderAndRows() {
        let csv = VocabularyExport.csv(from: [row(), row(lemma: "涙")])
        let lines = csv.split(separator: "\n")
        #expect(lines.first.map(String.init) == VocabularyExport.header)
        #expect(lines.count == 3)
    }

    /// Lyrics carry commas constantly and Korean glosses carry them almost as
    /// often, so quoting is the common case rather than an edge one.
    @Test("쉼표가 든 필드는 인용부호로 감싼다")
    func quotesCommas() {
        let csv = VocabularyExport.csv(from: [row(meaning: "꿈, 희망")])
        #expect(csv.contains("\"꿈, 희망\""))
    }

    @Test("인용부호는 두 번 써서 이스케이프한다")
    func escapesQuotes() {
        #expect(VocabularyExport.escaped("그는 \"꿈\"이라 했다").contains("\"\""))
    }

    @Test("특별한 문자가 없으면 그대로 둔다")
    func leavesPlainFieldsAlone() {
        #expect(VocabularyExport.escaped("ゆめ") == "ゆめ")
    }
}

@Suite("어려운 단어 정렬")
struct StruggleOrderTests {
    /// Mirrors `JustStore.strugglingEntries`' comparator, which cannot be called
    /// without a context. Lapses outrank difficulty because a repeated failure is
    /// evidence, while difficulty also rises for a word merely answered slowly.
    private func ordered(_ pairs: [(lapses: Int, difficulty: Double)]) -> [Int] {
        pairs.enumerated()
            .sorted {
                if $0.element.lapses != $1.element.lapses {
                    return $0.element.lapses > $1.element.lapses
                }
                return $0.element.difficulty > $1.element.difficulty
            }
            .map(\.offset)
    }

    @Test("실패 횟수가 난이도를 앞선다")
    func lapsesOutrankDifficulty() {
        // Index 1 has fewer lapses but the highest difficulty; it must not win.
        let order = ordered([(lapses: 3, difficulty: 4), (lapses: 1, difficulty: 9)])
        #expect(order == [0, 1])
    }

    @Test("실패 횟수가 같으면 난이도로 가른다")
    func difficultyBreaksTies() {
        let order = ordered([(lapses: 2, difficulty: 3), (lapses: 2, difficulty: 8)])
        #expect(order == [1, 0])
    }
}
