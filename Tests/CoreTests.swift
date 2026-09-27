import Foundation
import SwiftData
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

    /// Answering the 21:00 reminder at 21:05 used to leave the next due at
    /// 21:05, after that day's reminder — so the reminder slid a day each round.
    @Test("복습 날짜는 시각이 아니라 그날 새벽 4시에 올라온다")
    func dueIsTheStartOfTheDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))
        let evening = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 26, hour: 21, minute: 5
        )))
        let outcome = scheduler.schedule(ReviewState(), grade: .good, now: evening, calendar: calendar)
        let parts = calendar.dateComponents([.day, .hour, .minute], from: outcome.due)
        #expect(parts.hour == FSRS.dayStartHour)
        #expect(parts.minute == 0)
        #expect(parts.day == 26 + Int(outcome.intervalDays))
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

    /// FSRS-4.5 reverts difficulty toward D0(3) = w4, the "good" baseline.
    /// Reverting toward D0(4) (FSRS-5's target) drifts every word easier.
    @Test("난이도 평균 회귀는 '알맞음' 기준값을 향한다")
    func meanReversionTargetsGood() {
        let start = Date(timeIntervalSince1970: 0)
        let state = ReviewState()
        state.phase = .review
        state.stability = 10
        state.difficulty = 5
        state.lastReview = start

        let outcome = scheduler.schedule(state, grade: .good, now: start.addingTimeInterval(86_400 * 10))
        let w = FSRS.defaultWeights
        // A "good" grade leaves the pre-reversion difficulty unchanged, so
        // only the reversion moves it: 0.031 × 5.1618 + 0.969 × 5.
        let expected = w[7] * w[4] + (1 - w[7]) * 5
        #expect(abs(outcome.difficulty - expected) < 1e-9)
        #expect(abs(outcome.difficulty - 5.0050158) < 1e-6)
    }

    @Test("새 카드를 모른다고 해도 실패 횟수는 늘지 않는다")
    func newCardAgainIsNotALapse() {
        let state = ReviewState()
        state.apply(scheduler.schedule(state, grade: .again))
        #expect(state.phase == .relearning)
        #expect(state.lapses == 0)
    }

    @Test("복습 단계에서 잊었을 때만 실패로 센다")
    func onlyForgettingAReviewCardIsALapse() {
        let state = ReviewState()
        state.apply(scheduler.schedule(state, grade: .good))          // new → review
        state.apply(scheduler.schedule(state, grade: .again))         // review → relearning: lapse
        #expect(state.lapses == 1)
        state.apply(scheduler.schedule(state, grade: .again))         // still relearning: not another
        #expect(state.lapses == 1)
        state.apply(scheduler.schedule(state, grade: .good))          // relearning → review
        state.apply(scheduler.schedule(state, grade: .again))         // review → relearning: lapse
        #expect(state.lapses == 2)
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

    /// KAKUMEI, fully analysed, read 「JLPT 범위 밖」: its loanwords and names
    /// were counted as harder than N1.
    @Test("등급 없는 단어는 곡 등급을 끌어올리지 않는다")
    func unratedWordsDoNotSetTheLevel() {
        let difficulty = SongDifficulty(counts: [.n5: 6, .n4: 3, .n2: 1, .beyond: 14])
        #expect(difficulty.comprehensionLevel == .n4)
        #expect(difficulty.unratedCount == 14)
        #expect(difficulty.advancedCount == 1)
        #expect(difficulty.detail.contains("14개"))
    }

    @Test("등급 있는 단어가 하나도 없을 때만 범위 밖")
    func onlyUnratedIsBeyond() {
        #expect(SongDifficulty(counts: [.beyond: 5]).comprehensionLevel == .beyond)
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
        example: String = "夢の中でまた会えたらいいな"
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

    @Test("캐리지 리턴이 든 필드도 인용부호로 감싼다")
    func quotesCarriageReturns() {
        #expect(VocabularyExport.escaped("a\rb") == "\"a\rb\"")
        #expect(VocabularyExport.escaped("a\r\nb") == "\"a\r\nb\"")
    }

    /// A cell that starts with one of these is evaluated as a formula by
    /// Excel and Numbers; the apostrophe makes it text.
    @Test("수식으로 읽힐 수 있는 필드 앞에는 작은따옴표를 붙인다")
    func neutralisesFormulas() {
        #expect(VocabularyExport.escaped("=1+1") == "'=1+1")
        #expect(VocabularyExport.escaped("+82") == "'+82")
        #expect(VocabularyExport.escaped("-ない") == "'-ない")
        #expect(VocabularyExport.escaped("@home") == "'@home")
        // Both guards at once: the apostrophe goes inside the quotes.
        #expect(VocabularyExport.escaped("=A1,B1") == "\"'=A1,B1\"")
        // Only the first character matters.
        #expect(VocabularyExport.escaped("1+1=2") == "1+1=2")
    }
}

@Suite("복습 대기열과 어려운 단어")
@MainActor
struct ReviewQueueTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() throws -> (ModelContainer, JustStore) {
        let container = try JustSchema.container(inMemory: true)
        return (container, JustStore(context: container.mainContext))
    }

    @discardableResult
    private func insert(
        _ store: JustStore,
        _ index: Int,
        due: Date,
        lapses: Int = 0,
        difficulty: Double = 5
    ) -> VocabEntry {
        let entry = VocabEntry(lemma: "語\(index)", reading: "ご\(index)", meaningKo: "단어 \(index)")
        // Oldest first, so index order is creation order.
        entry.createdAt = now.addingTimeInterval(Double(index) - 100_000)
        let review = ReviewState()
        review.due = due
        review.lapses = lapses
        review.difficulty = difficulty
        review.phase = .review
        entry.review = review
        store.context.insert(entry)
        return entry
    }

    /// The old query took the 500 oldest words and filtered those, so words
    /// saved after the 500th never came up at all.
    @Test("500개가 넘어도 나중에 담은 단어가 복습에 올라온다")
    func dueBeyondFiveHundred() throws {
        let (container, store) = try makeStore()
        _ = container
        for index in 0..<550 {
            insert(store, index, due: now.addingTimeInterval(86_400))
        }
        for index in 550..<600 {
            // Due at different moments in the past, newest-saved most overdue.
            insert(store, index, due: now.addingTimeInterval(-Double(index)))
        }
        try store.context.save()

        let due = store.dueEntries(limit: 40, now: now)
        #expect(due.count == 40)
        #expect(due.allSatisfy { ($0.review?.due ?? .distantFuture) <= now })
        let dates = due.compactMap { $0.review?.due }
        #expect(dates == dates.sorted())
        #expect(store.dueCount(now: now) == 50)
    }

    @Test("통계의 복습 수는 대기열 전체를 센다")
    func statsCountsEveryDueCard() throws {
        let (container, store) = try makeStore()
        _ = container
        for index in 0..<520 {
            insert(store, index, due: .now.addingTimeInterval(86_400))
        }
        for index in 520..<530 {
            insert(store, index, due: .now.addingTimeInterval(-60))
        }
        try store.context.save()
        #expect(store.stats().dueCount == 10)
    }

    /// Lapses outrank difficulty because a repeated failure is evidence,
    /// while difficulty also rises for a word merely answered slowly.
    @Test("어려운 단어는 실패 횟수, 그다음 난이도 순이고 500개 밖에서도 찾는다")
    func strugglingOrder() throws {
        let (container, store) = try makeStore()
        _ = container
        for index in 0..<520 {
            insert(store, index, due: now)
        }
        let fewLapsesHard = insert(store, 520, due: now, lapses: 1, difficulty: 9)
        let manyLapses = insert(store, 521, due: now, lapses: 3, difficulty: 4)
        let fewLapsesEasy = insert(store, 522, due: now, lapses: 1, difficulty: 2)
        try store.context.save()

        let keys = store.strugglingEntries().map(\.key)
        #expect(keys == [manyLapses.key, fewLapsesHard.key, fewLapsesEasy.key])
        #expect(store.strugglingEntries(limit: 1).map(\.key) == [manyLapses.key])
    }

    @Test("앞으로의 일정은 가까운 순서로 담긴다")
    func outlookListsUpcoming() throws {
        let (container, store) = try makeStore()
        _ = container
        insert(store, 0, due: now.addingTimeInterval(-10))
        insert(store, 1, due: now.addingTimeInterval(-20))
        insert(store, 2, due: now.addingTimeInterval(3_600 * 5))
        insert(store, 3, due: now.addingTimeInterval(3_600))
        try store.context.save()

        let outlook = store.outlook(now: now)
        #expect(outlook.dueCount == 2)
        #expect(outlook.upcoming == [now.addingTimeInterval(3_600), now.addingTimeInterval(3_600 * 5)])
        #expect(outlook.dueCount(at: now.addingTimeInterval(3_600 * 2)) == 3)
    }
}

@Suite("복습 일정 전망")
struct ReviewOutlookTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2023-11-14 10:00 UTC.
    private var morning: Date {
        calendar.date(from: DateComponents(year: 2023, month: 11, day: 14, hour: 10))!
    }

    private func at(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2023, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test("지금 복습할 카드가 있으면 오늘 알림 시각")
    func dueNowFiresToday() {
        let outlook = ReviewOutlook(asOf: morning, dueCount: 3, upcoming: [])
        let date = outlook.reminderDate(hour: 21, minute: 0, now: morning, calendar: calendar)
        #expect(date == at(day: 14, hour: 21))
    }

    @Test("오늘 알림 시각이 지났으면 내일")
    func pastTodayFiresTomorrow() {
        let late = at(day: 14, hour: 22)
        let outlook = ReviewOutlook(asOf: late, dueCount: 1, upcoming: [])
        let date = outlook.reminderDate(hour: 21, minute: 0, now: late, calendar: calendar)
        #expect(date == at(day: 15, hour: 21))
    }

    @Test("다음 카드가 사흘 뒤면 그날 알림 시각")
    func nextDueDayLater() {
        let outlook = ReviewOutlook(asOf: morning, dueCount: 0, upcoming: [at(day: 17, hour: 9)])
        #expect(outlook.reminderDate(hour: 21, minute: 0, now: morning, calendar: calendar) == at(day: 17, hour: 21))
    }

    @Test("알림 시각보다 늦게 올라오는 카드는 다음 날 알린다")
    func dueAfterReminderTime() {
        let outlook = ReviewOutlook(asOf: morning, dueCount: 0, upcoming: [at(day: 17, hour: 23)])
        #expect(outlook.reminderDate(hour: 21, minute: 0, now: morning, calendar: calendar) == at(day: 18, hour: 21))
    }

    @Test("복습할 것이 없으면 알림도 없다")
    func nothingScheduledNoReminder() {
        let outlook = ReviewOutlook(asOf: morning, dueCount: 0, upcoming: [])
        #expect(outlook.reminderDate(hour: 21, minute: 0, now: morning, calendar: calendar) == nil)
    }
}

@Suite("위젯 스냅숏")
struct WidgetSnapshotTests {
    private let written = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("최애가 없던 옛 스냅숏도 읽힌다")
    func decodesWithoutOshi() throws {
        let old = #"{"dueCount":2,"streak":3,"totalWords":9,"updatedAt":0}"#
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(old.utf8))
        #expect(snapshot.oshi == nil)
        #expect(snapshot.totalWords == 9)
    }

    @Test("최애만 바꾸고 나머지는 그대로")
    func swapsOnlyTheOshi() {
        let snapshot = WidgetSnapshot(dueCount: 4, streak: 2, totalWords: 30, word: nil, updatedAt: written)
        let picked = snapshot.with(oshi: .init(name: "=LOVE", hue: 0.75))
        #expect(picked.oshi?.name == "=LOVE")
        #expect(picked.dueCount == 4 && picked.totalWords == 30 && picked.updatedAt == written)
        #expect(picked.with(oshi: nil).oshi == nil)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// A file written by a build before the schedule fields existed must still
    /// decode, and show exactly what it said.
    @Test("예전 형식의 스냅숏도 읽힌다")
    func decodesOldSnapshot() throws {
        let json = #"{"dueCount":3,"streak":2,"totalWords":10,"updatedAt":721692800}"#
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.upcomingDue == nil)
        #expect(snapshot.lastStudyDay == nil)
        #expect(snapshot.word == nil)
        #expect(snapshot.dueCount(at: .distantFuture) == 3)
        #expect(snapshot.streak(at: .distantFuture) == 2)
    }

    @Test("새 필드는 저장했다가 그대로 읽힌다")
    func roundTrips() throws {
        let snapshot = WidgetSnapshot(
            dueCount: 1, streak: 4, totalWords: 9, word: nil,
            updatedAt: written,
            upcomingDue: [written.addingTimeInterval(60)],
            lastStudyDay: written
        )
        let decoded = try JSONDecoder().decode(
            WidgetSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        #expect(decoded == snapshot)
    }

    @Test("시간이 지나면 올라온 카드가 더해진다")
    func dueCountGrowsOverTime() {
        let snapshot = WidgetSnapshot(
            dueCount: 2, streak: 0, totalWords: 5, word: nil,
            updatedAt: written,
            upcomingDue: [written.addingTimeInterval(3_600), written.addingTimeInterval(7_200)]
        )
        #expect(snapshot.dueCount(at: written) == 2)
        #expect(snapshot.dueCount(at: written.addingTimeInterval(3_600)) == 3)
        #expect(snapshot.dueCount(at: written.addingTimeInterval(10_000)) == 4)
    }

    @Test("하루를 통째로 거르면 연속일수가 끊긴다")
    func streakLapses() {
        let studied = calendar.startOfDay(for: written)
        let snapshot = WidgetSnapshot(
            dueCount: 0, streak: 5, totalWords: 5, word: nil,
            updatedAt: written, upcomingDue: [], lastStudyDay: studied
        )
        let day: TimeInterval = 86_400
        #expect(snapshot.streak(at: studied.addingTimeInterval(day * 0.5), calendar: calendar) == 5)
        // The next day, not yet studied, still counts.
        #expect(snapshot.streak(at: studied.addingTimeInterval(day * 1.5), calendar: calendar) == 5)
        #expect(snapshot.streak(at: studied.addingTimeInterval(day * 2.5), calendar: calendar) == 0)
    }

    @Test("타임라인은 카드가 올라오는 시각과 자정마다 갱신된다")
    func timelineDates() {
        let due = written.addingTimeInterval(3_600 + 30)
        let snapshot = WidgetSnapshot(
            dueCount: 0, streak: 0, totalWords: 1, word: nil,
            updatedAt: written,
            upcomingDue: [due, written.addingTimeInterval(86_400 * 3)]
        )
        let dates = snapshot.timelineDates(after: written, calendar: calendar)
        #expect(dates == dates.sorted())
        #expect(dates.allSatisfy { $0 > written })
        // Rounded up to the minute, never before the card is due.
        #expect(dates.contains { $0 >= due && $0.timeIntervalSince(due) < 60 })
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: written))!
        #expect(dates.contains(midnight))
        // Three days out is past the horizon.
        #expect(!dates.contains { $0 > written.addingTimeInterval(86_400 * 2 + 1) })
    }
}

@Suite("저장소 위치 옮기기")
struct StoreLocationTests {
    private let fileManager = FileManager.default
    private let schema = Schema(JustSchema.models)

    private func temporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory
            .appending(path: "store-location-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFakeStore(in directory: URL, marker: String) throws {
        try Data(marker.utf8).write(to: directory.appending(path: "default.store"))
        try Data((marker + "-wal").utf8).write(to: directory.appending(path: "default.store-wal"))
    }

    private func contents(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    /// Creates a real SwiftData store, releasing it before returning.
    private func makeRealStore(at directory: URL, words: Int) throws {
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(url: directory.appending(path: "default.store"))
        )
        let context = ModelContext(container)
        for index in 0..<words {
            context.insert(VocabEntry(lemma: "語\(index)", reading: "ご", meaningKo: "단어"))
        }
        try context.save()
    }

    @Test("옛 저장소만 있으면 그룹 컨테이너로 복사한다")
    func copiesLegacyStore() throws {
        let legacy = try temporaryDirectory()
        let group = try temporaryDirectory().appending(path: "Library/Application Support")
        try writeFakeStore(in: legacy, marker: "legacy")

        #expect(StoreLocation.migrate(from: legacy, to: group, schema: schema) == .copied)
        #expect(contents(group.appending(path: "default.store")) == "legacy")
        #expect(contents(group.appending(path: "default.store-wal")) == "legacy-wal")
        // Copied, not moved: the original stays as a fallback.
        #expect(fileManager.fileExists(atPath: legacy.appending(path: "default.store").path(percentEncoded: false)))
    }

    @Test("옛 저장소가 없으면 아무것도 하지 않는다")
    func nothingToCopy() throws {
        let legacy = try temporaryDirectory()
        let group = try temporaryDirectory()
        #expect(StoreLocation.migrate(from: legacy, to: group, schema: schema) == .nothingToDo)
        #expect(!fileManager.fileExists(atPath: group.appending(path: "default.store").path(percentEncoded: false)))
    }

    @Test("그룹 저장소에 단어가 있으면 덮어쓰지 않는다")
    func keepsGroupStoreWithData() throws {
        let legacy = try temporaryDirectory()
        let group = try temporaryDirectory()
        try writeFakeStore(in: legacy, marker: "legacy")
        try makeRealStore(at: group, words: 1)

        #expect(StoreLocation.migrate(from: legacy, to: group, schema: schema) == .keptExisting)
        #expect(contents(group.appending(path: "default.store")) != "legacy")
    }

    /// The widget build created an empty store in the group container on
    /// first launch; that file must not hide the user's real library.
    @Test("그룹 저장소가 비어 있으면 옛 저장소로 바꾼다")
    func replacesEmptyGroupStore() throws {
        let legacy = try temporaryDirectory()
        let group = try temporaryDirectory()
        try writeFakeStore(in: legacy, marker: "legacy")
        try makeRealStore(at: group, words: 0)

        #expect(StoreLocation.migrate(from: legacy, to: group, schema: schema) == .copied)
        #expect(contents(group.appending(path: "default.store")) == "legacy")
    }
}

@Suite("문법 집계")
struct GrammarSightingTests {
    private var sighting: GrammarSighting {
        GrammarSighting(
            pattern: "〜てしまう",
            explanationKo: "완료·후회를 나타냅니다",
            example: "忘れてしまった",
            exampleTranslation: "잊어버렸다",
            song: "米津玄師 — Lemon"
        )
    }

    @Test("처음 본 곡이 곧 곡 수 1")
    func startsAtOne() {
        #expect(sighting.songCount == 1)
    }

    @Test("다른 곡에서 또 보이면 곡 수가 늘어난다")
    func countsDistinctSongs() {
        var note = sighting
        note.addSighting(song: "YOASOBI — 夜に駆ける")
        #expect(note.songCount == 2)
        #expect(note.songs.contains("YOASOBI — 夜に駆ける"))
    }

    /// A chorus repeating the pattern in one song says nothing about how common
    /// the pattern is, so only distinct songs count.
    @Test("같은 곡에서 반복돼도 곡 수는 늘지 않는다")
    func ignoresRepeatsWithinASong() {
        var note = sighting
        note.addSighting(song: "米津玄師 — Lemon")
        note.addSighting(song: "米津玄師 — Lemon")
        #expect(note.songCount == 1)
    }

    @Test("패턴이 곧 식별자")
    func patternIsIdentity() {
        #expect(sighting.id == "〜てしまう")
    }
}

@Suite("재생 위치가 어느 시계인지")
struct PlaybackPositionTests {
    private let lyrics = Lyrics(
        lines: [
            LyricLine(id: 0, time: 0.9, text: "ゆっくり歩いてゆく帰り道"),
            LyricLine(id: 1, time: 8.0, text: "二人で見上げた空が広がる"),
            LyricLine(id: 2, time: 120.0, text: "「またね」と言えなかった"),
        ],
        isSynced: true,
        source: "test"
    )

    @Test("전곡 재생의 위치는 곡 안의 위치다")
    func inSongIsASongTime() {
        #expect(PlaybackPosition.inSong(8.5).songTime == 8.5)
    }

    @Test("미리듣기 클립의 위치는 곡 안의 위치가 아니다")
    func anExcerptHasNoSongTime() {
        // Measured, not assumed: the first second of an Apple preview sits
        // within 0.3–3.5 dB of the whole clip's mean level, so the clip starts
        // mid-song rather than at the beginning. Its clock therefore says
        // nothing about where the song is, and there is no published offset to
        // convert it with.
        #expect(PlaybackPosition.excerpt(8.5).songTime == nil)
    }

    @Test("클립에서도 경과 시간은 그대로 쓸 수 있다")
    func anExcerptStillReportsElapsed() {
        // The transport needs a number to draw — 0:08 of 0:30 is true and
        // useful. It is only the lyrics that need it to mean a place in the song.
        #expect(PlaybackPosition.excerpt(8.5).elapsed == 8.5)
        #expect(PlaybackPosition.inSong(8.5).elapsed == 8.5)
    }

    @Test("전곡 재생이면 가사가 따라간다")
    func lyricsFollowTheSong() {
        #expect(lyrics.activeLineIndex(at: PlaybackPosition.inSong(8.0)) == 1)
        #expect(lyrics.activeLineIndex(at: PlaybackPosition.inSong(130)) == 2)
    }

    @Test("미리듣기면 어떤 줄도 강조하지 않는다")
    func lyricsDoNotFollowAnExcerpt() {
        // Highlighting the line at 8 seconds while the clip plays the chorus is
        // worse than highlighting nothing: it is confidently wrong, and the
        // reader has no way to tell.
        #expect(lyrics.activeLineIndex(at: PlaybackPosition.excerpt(8.0)) == nil)
        #expect(PlaybackPosition.excerpt(8.0).followsLyrics == false)
        #expect(PlaybackPosition.inSong(8.0).followsLyrics == true)
    }
}

@Suite("가사 싱크 오프셋")
struct LyricSyncTests {
    @Test("오프셋이 없으면 아무것도 바꾸지 않는다")
    func zeroChangesNothing() {
        #expect(LyricSync.lyricTime(forSongTime: 10, offset: 0) == 10)
        #expect(LyricSync.seekTarget(forLine: 8, offset: 0) == 8)
    }

    @Test("양수는 가사를 늦춘다")
    func positiveDelaysTheLyrics() {
        // The sheet runs ahead: the line marked 8.0 is actually sung at 10.0.
        // With +2 the app looks up 8.0 when the song is at 10.0, so the line
        // lights up when it is heard rather than two seconds early.
        #expect(LyricSync.lyricTime(forSongTime: 10, offset: 2) == 8)
        // And jumping to that line has to land where it really is.
        #expect(LyricSync.seekTarget(forLine: 8, offset: 2) == 10)
    }

    @Test("음수는 가사를 당긴다")
    func negativePullsTheLyricsForward() {
        #expect(LyricSync.lyricTime(forSongTime: 10, offset: -2) == 12)
        #expect(LyricSync.seekTarget(forLine: 8, offset: -2) == 6)
    }

    @Test("곡 시작 앞으로는 넘어가지 않는다")
    func neverSeeksBeforeTheStart() {
        #expect(LyricSync.seekTarget(forLine: 0.9, offset: -3) == 0)
    }

    @Test("다섯 초를 넘는 보정은 받지 않는다")
    func refusesMoreThanFiveSeconds() {
        // Past five seconds it is not a timing offset any more — it is the wrong
        // sheet, and letting someone dial in twenty seconds hides that.
        #expect(LyricSync.clamped(12) == 5)
        #expect(LyricSync.clamped(-12) == -5)
        #expect(LyricSync.clamped(1.5) == 1.5)
    }

    @Test("들리는 줄을 누르면 그 줄에 맞는 오프셋이 나온다")
    func calibratesFromTheLineBeingHeard() {
        // Heard the line stamped 8.0 while playback said 10.0.
        #expect(LyricSync.calibrated(songTime: 10, lineTime: 8) == 2)
        // The other way round, and clamped like any other value.
        #expect(LyricSync.calibrated(songTime: 8, lineTime: 10) == -2)
        #expect(LyricSync.calibrated(songTime: 100, lineTime: 8) == 5)
    }

    @Test("한 단계씩 미는 값은 소수점에서 어긋나지 않는다")
    func steppingStaysExact() {
        // 0.1 three times has to read as 0.3, not 0.30000000000000004 — the
        // sheet prints this number.
        var offset = 0.0
        for _ in 0..<3 { offset = LyricSync.stepped(offset, by: 0.1) }
        #expect(offset == 0.3)
    }
}

@Suite("얼마나 기다릴지")
struct WaitBudgetTests {
    @Test("재본 적이 없으면 계속 기다린다")
    func waitsWithoutASample() {
        // Nothing to judge by yet. Bailing out on no evidence would open the
        // player for a song that was about to finish.
        #expect(WaitBudget.shouldOpenEarly(estimate: nil, done: 0) == false)
    }

    @Test("표본이 적으면 아직 판단하지 않는다")
    func needsAFewLinesFirst() {
        // The first line pays for the session and the instructions, so its time
        // says more about start-up than about the song.
        #expect(WaitBudget.shouldOpenEarly(estimate: 600, done: 1) == false)
        #expect(WaitBudget.shouldOpenEarly(estimate: 600, done: 2) == false)
    }

    @Test("남은 시간이 짧으면 끝까지 기다린다")
    func finishesAShortWait() {
        // A completed song is the better thing to hand over, so a wait worth
        // sitting through is sat through.
        #expect(WaitBudget.shouldOpenEarly(estimate: 20, done: 3) == false)
        #expect(WaitBudget.shouldOpenEarly(estimate: 30, done: 5) == false)
    }

    @Test("남은 시간이 길면 먼저 열어준다")
    func doesNotMakeThemWaitMinutes() {
        #expect(WaitBudget.shouldOpenEarly(estimate: 31, done: 3))
        #expect(WaitBudget.shouldOpenEarly(estimate: 600, done: 3))
    }
}

@Suite("아이돌 그룹 명단")
struct IdolGroupTests {
    @Test("원래 일곱 그룹이 그대로 있고, 새 그룹이 더해졌다")
    func hasEveryGroup() {
        let names = Set(IdolGroup.all.map(\.name))
        #expect(names.isSuperset(of: [
            "FRUITS ZIPPER", "CANDY TUNE", "SWEET STEADY", "CUTIE STREET",
            "MORE STAR", "iLiFE!", "=LOVE",
        ]))
        #expect(names.isSuperset(of: ["≠ME", "≒JOY", "乃木坂46", "日向坂46", "AKB48", "モーニング娘。", "ももいろクローバーZ"]))
        #expect(IdolGroup.all.count == 31)
    }

    @Test("모든 섹션에 그룹이 있고, 모든 그룹이 한 섹션에 있다")
    func everySectionIsFilled() {
        for label in IdolGroup.Label.allCases {
            #expect(!IdolGroup.groups(in: label).isEmpty, "\(label.rawValue)")
        }
        #expect(IdolGroup.Label.allCases.map { IdolGroup.groups(in: $0).count }.reduce(0, +) == IdolGroup.all.count)
    }

    @Test("곡의 아티스트 표기로 그룹을 찾는다 — 협업·로마자 표기도")
    func findsGroupsByCredit() {
        #expect(IdolGroup.group(forArtist: "乃木坂46")?.name == "乃木坂46")
        #expect(IdolGroup.group(forArtist: "モーニング娘。'17")?.name == "モーニング娘。")
        #expect(IdolGroup.group(forArtist: "=LOVE & ≠ME")?.name == "=LOVE")
        #expect(IdolGroup.group(forArtist: "≠ME")?.name == "≠ME")
        #expect(IdolGroup.group(forArtist: "Hinatazaka46")?.name == "日向坂46")
        #expect(IdolGroup.group(forArtist: "AKB48, SKE48, NMB48 & HKT48")?.name == "AKB48")
        #expect(IdolGroup.group(forArtist: "椎名林檎と新しい学校のリーダーズ")?.name == "新しい学校のリーダーズ")
    }

    @Test("모든 그룹에 공식 채널이 있다")
    func everyGroupHasAChannel() {
        for group in IdolGroup.all {
            #expect(!group.youtubeChannels.isEmpty, "\(group.name)")
            #expect(group.youtubeChannels.allSatisfy { $0.hasPrefix("UC") && $0.count == 24 }, "\(group.name)")
        }
    }

    @Test("아티스트 ID가 서로 다르다")
    func idsAreDistinct() {
        // A duplicated id would quietly give two groups the same songs.
        #expect(Set(IdolGroup.all.map(\.id)).count == IdolGroup.all.count)
    }

    @Test("ID로 그룹을 찾는다")
    func findsByID() {
        #expect(IdolGroup.group(id: "1617607581")?.name == "FRUITS ZIPPER")
        #expect(IdolGroup.group(id: "없는id") == nil)
    }

    @Test("KAWAII LAB.에 다섯 그룹이 있다")
    func kawaiiLabRoster() {
        #expect(IdolGroup.groups(in: .kawaiiLab).count == 5)
        #expect(IdolGroup.groups(in: .kawaiiLab).map(\.name).contains("MORE STAR"))
    }

    @Test("모든 그룹에 한국어 표기와 색이 있다")
    func everyGroupIsPresentable() {
        for group in IdolGroup.all {
            #expect(!group.readingKo.isEmpty)
            #expect((0...1).contains(group.hue))
        }
    }
}


@Suite("재생 순서")
struct PlaybackQueueTests {
    private func track(_ id: String) -> Track {
        Track(id: id, title: id, artist: "a", album: nil, artworkURL: nil, duration: 0)
    }

    @Test("다음 곡과 이전 곡을 돌려준다")
    func stepsBothWays() {
        let queue = PlaybackQueue([track("a"), track("b"), track("c")])
        #expect(queue.next(after: track("a"))?.id == "b")
        #expect(queue.previous(before: track("c"))?.id == "b")
    }

    @Test("끝에서는 멈춘다 — 감싸 돌지 않는다")
    func stopsAtTheEnds() {
        let queue = PlaybackQueue([track("a"), track("b")])
        #expect(queue.next(after: track("b")) == nil)
        #expect(queue.previous(before: track("a")) == nil)
    }

    @Test("목록에 없는 곡이면 어디로도 가지 않는다")
    func unknownTrackGoesNowhere() {
        let queue = PlaybackQueue([track("a")])
        #expect(queue.next(after: track("zzz")) == nil)
    }
}
