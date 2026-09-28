import Foundation
import RingRingCore
import Testing

@testable import RingRingLyrics

@Suite("LRC 파싱")
struct LRCParserTests {
    /// The bug that shipped: Swift treats "\r\n" as one Character, so
    /// `split(separator: "\n")` collapsed a CRLF document into a single line and
    /// every timestamp ended up carrying the last line's text.
    @Test("CRLF 가사도 줄 단위로 쪼개진다")
    func parsesCarriageReturnLineFeed() {
        let lrc = "[00:01.00] 一行目\r\n[00:05.00] 二行目\r\n[00:09.00] 三行目"
        let lyrics = LRCParser.parse(lrc)

        #expect(lyrics.lines.count == 3)
        #expect(lyrics.lines.map(\.text) == ["一行目", "二行目", "三行目"])
        #expect(lyrics.isSynced)
    }

    @Test("LF 가사도 같은 결과를 낸다")
    func parsesLineFeed() {
        let lyrics = LRCParser.parse("[00:01.00] 一行目\n[00:05.00] 二行目")
        #expect(lyrics.lines.map(\.text) == ["一行目", "二行目"])
    }

    @Test("한 줄에 여러 타임스탬프가 붙으면 각각 등장한다")
    func expandsRepeatedTimestamps() {
        let lyrics = LRCParser.parse("[00:10.00][01:20.00] サビ")
        #expect(lyrics.lines.count == 2)
        #expect(lyrics.lines.allSatisfy { $0.text == "サビ" })
        #expect(lyrics.lines[0].time == 10)
        #expect(lyrics.lines[1].time == 80)
    }

    @Test("센티초와 밀리초를 구분한다")
    func readsFractionByDigitCount() {
        #expect(LRCParser.parse("[00:00.50] a").lines[0].time == 0.5)
        #expect(LRCParser.parse("[00:00.500] a").lines[0].time == 0.5)
    }

    @Test("타임스탬프가 없으면 순서만 있는 가사로 취급한다")
    func fallsBackToPlain() {
        let lyrics = LRCParser.parse("一行目\n二行目")
        #expect(!lyrics.isSynced)
        #expect(lyrics.lines.count == 2)
    }

    @Test("싱크 가사에서 재생 위치에 맞는 줄을 찾는다")
    func findsActiveLine() {
        let lyrics = LRCParser.parse("[00:00.00] a\n[00:10.00] b\n[00:20.00] c")
        #expect(lyrics.activeLineIndex(at: 0) == 0)
        #expect(lyrics.activeLineIndex(at: 5) == 0)
        #expect(lyrics.activeLineIndex(at: 10) == 1)
        #expect(lyrics.activeLineIndex(at: 999) == 2)
    }

    /// The highlight moves a fraction of a second early on purpose: a lyric that
    /// lights up exactly on the beat reads as late when you are trying to sing
    /// along with it.
    @Test("다음 줄은 150ms 먼저 활성화된다")
    func highlightLeadsSlightly() {
        let lyrics = LRCParser.parse("[00:00.00] a\n[00:10.00] b")
        #expect(lyrics.activeLineIndex(at: 9.8) == 0)
        #expect(lyrics.activeLineIndex(at: 9.9) == 1)
    }

    @Test("동기화되지 않은 가사에는 활성 줄이 없다")
    func plainLyricsHaveNoActiveLine() {
        #expect(LRCParser.parsePlain("a\nb").activeLineIndex(at: 10) == nil)
    }

    /// LRC convention: a positive offset makes the lyrics appear earlier.
    @Test("[offset:+ms]는 가사를 그만큼 앞당긴다")
    func positiveOffsetShowsLyricsEarlier() {
        let lyrics = LRCParser.parse("[offset:+500]\n[00:10.00] a\n[00:20.00] b")
        #expect(lyrics.lines.map(\.time) == [9.5, 19.5])
        #expect(lyrics.lines.map(\.text) == ["a", "b"])
    }

    @Test("[offset:-ms]는 가사를 그만큼 늦춘다")
    func negativeOffsetShowsLyricsLater() {
        let lyrics = LRCParser.parse("[00:10.00] a\n[offset:-250]")
        #expect(lyrics.lines.map(\.time) == [10.25])
    }

    @Test("오프셋으로 0초 앞으로 밀린 줄은 0초에 둔다")
    func offsetNeverGoesNegative() {
        let lyrics = LRCParser.parse("[offset:1000]\n[00:00.50] a")
        #expect(lyrics.lines.first?.time == 0)
    }

    @Test("줄 끝의 타임스탬프는 떼고 글은 남긴다")
    func stripsTrailingTimestamps() {
        let lyrics = LRCParser.parse("[00:12.00]窓を開けて[00:15.00]\n[00:15.00]風が来る")
        #expect(lyrics.lines.count == 2)
        #expect(lyrics.lines.map(\.text) == ["窓を開けて", "風が来る"])
        #expect(lyrics.lines.map(\.time) == [12, 15])
    }

    @Test("줄 안의 단어별 타임스탬프도 글이 아니다")
    func stripsInlineWordTimestamps() {
        let lyrics = LRCParser.parse("[00:12.00]<00:12.00>窓を<00:12.50>開けて[00:13.00]もう一度")
        #expect(lyrics.lines.count == 1)
        #expect(lyrics.lines[0].text == "窓を開けてもう一度")
        #expect(lyrics.lines[0].time == 12)
    }

    @Test("BOM이 붙은 첫 줄도 잃지 않는다")
    func stripsByteOrderMark() {
        let lyrics = LRCParser.parse("\u{FEFF}[00:01.00] 一行目\n[00:05.00] 二行目")
        #expect(lyrics.isSynced)
        #expect(lyrics.lines.map(\.text) == ["一行目", "二行目"])
        #expect(lyrics.lines.first?.time == 1)

        let plain = LRCParser.parsePlain("\u{FEFF}一行目")
        #expect(plain.lines.first?.text == "一行目")
    }
}

@Suite("가사 언어 판정")
struct LyricsLanguageTests {
    /// The other bug that shipped: translated lyric sheets keep the original
    /// credit header, so "does this contain Japanese" was true for a body that
    /// was entirely Vietnamese.
    @Test("크레딧만 일본어인 번역본은 일본어로 보지 않는다")
    func rejectsTranslationWithJapaneseCredits() {
        let vietnamese = """
        [00:00.00] 作词 : 米津玄師
        [00:00.00] 作曲 : 米津玄師
        [00:01.00] Đến bây giờ, em vẫn là ánh sáng của anh
        [00:05.00] Anh vẫn mơ về em mỗi đêm
        [00:09.00] Như thể đi lấy lại thứ đã quên
        [00:13.00] Anh phủi lớp bụi của kỷ niệm cũ
        """
        #expect(!LRCLIBClient.isJapanese(vietnamese))
    }

    @Test("본문이 일본어면 일본어로 본다")
    func acceptsJapaneseBody() {
        let japanese = """
        [00:01.64] 雨ならば窓の外で待っていよう
        [00:07.19] 今でも君の声を夢にみる
        [00:12.00] 置いてきた傘を探しに戻るように
        """
        #expect(LRCLIBClient.isJapanese(japanese))
        #expect(LRCLIBClient.japaneseRatio(japanese) == 1)
    }

    @Test("한자만 있는 중국어 가사는 걸러진다")
    func rejectsKanjiOnlyText() {
        // Kana is the discriminator; Chinese lyrics share the characters.
        #expect(!LRCLIBClient.isJapanese("[00:01.00] 我愛你\n[00:05.00] 天空很藍"))
    }

    @Test("빈 가사는 0")
    func emptyIsZero() {
        #expect(LRCLIBClient.japaneseRatio("") == 0)
    }
}

@Suite("가사 검색 질의 정리")
struct LyricsQueryTests {
    @Test("제목의 (feat. …)를 떼어낸 판본도 시도한다")
    func stripsFeatureCredits() {
        let titles = LRCLIBClient.queryVariants(
            artist: "YOASOBI",
            title: "夜に駆ける (feat. X)"
        ).map(\.title)
        // 원본을 먼저 시도하고, 그다음 정리한 것을 시도한다.
        #expect(titles.first == "夜に駆ける (feat. X)")
        #expect(titles.contains("夜に駆ける"))
    }

    @Test("부제·판 표기를 뗀 가장 단순한 제목")
    func plainestTitle() {
        #expect(LRCLIBClient.plainestTitle("超めでたいソング 〜こんなに幸せでいいのかな?〜") == "超めでたいソング")
        #expect(LRCLIBClient.plainestTitle("はちゃめちゃわちゃライフ! -TV size-") == "はちゃめちゃわちゃライフ!")
        #expect(LRCLIBClient.plainestTitle("NEW KAWAII - Single Version") == "NEW KAWAII")
        #expect(LRCLIBClient.plainestTitle("かがみ") == "かがみ")
    }

    @Test("그룹의 일본어 표기와 제목만으로도 찾는다")
    func aliasVariants() {
        let variants = LRCLIBClient.queryVariants(artist: "FRUITS ZIPPER", title: "わたしの一番かわいいところ")
        #expect(variants.contains { $0.artist == "フルーツジッパー" && $0.title == "わたしの一番かわいいところ" })
        #expect(variants.last?.artist == "")
        #expect(variants.last?.title == "わたしの一番かわいいところ")
    }

    @Test("- Single 꼬리표를 떼어낸다")
    func stripsReleaseTag() {
        #expect(LRCLIBClient.simplifiedTitle("夜に駆ける - Single") == "夜に駆ける")
    }

    @Test("장식이 없는 제목은 그대로 둔다")
    func leavesACleanTitleAlone() {
        #expect(LRCLIBClient.simplifiedTitle("アイドル") == "アイドル")
    }

    @Test("제목이 통째로 괄호면 비우지 않는다")
    func neverEmptiesATitle() {
        #expect(LRCLIBClient.simplifiedTitle("(Intro)") == "(Intro)")
    }

    @Test("합작 아티스트에서 첫 이름만 남긴다")
    func takesThePrimaryArtist() {
        #expect(
            LRCLIBClient.primaryArtist("EBiDAN (恵比寿学園男子部), 超特急, M!LK & 原因は自分にある。")
                == "EBiDAN"
        )
        #expect(LRCLIBClient.primaryArtist("Ayase & YOASOBI") == "Ayase")
        #expect(LRCLIBClient.primaryArtist("YOASOBI") == "YOASOBI")
    }

    @Test("같은 질의를 두 번 보내지 않는다")
    func doesNotRepeatItself() {
        let variants = LRCLIBClient.queryVariants(artist: "YOASOBI", title: "アイドル")
        #expect(Set(variants.map { "\($0.artist)|\($0.title)" }).count == variants.count)
        #expect(variants.first?.title == "アイドル")
    }
}

@Suite("직접 붙여 넣은 가사")
struct PastedLyricsTests {
    @Test("시간이 있으면 싱크, 없으면 글로")
    func parsesBothForms() {
        let synced = LRCParser.parse("[00:12.34]秘密の鍵を開けて\n[00:15.00]心の奥を見せてあげる", source: "직접 입력")
        #expect(synced.isSynced)
        #expect(synced.lines.map(\.text) == ["秘密の鍵を開けて", "心の奥を見せてあげる"])
        #expect(synced.lines[0].time == 12.34)

        let plain = LRCParser.parse("秘密の鍵を開けて\n\n心の奥を見せてあげる\n", source: "직접 입력")
        #expect(!plain.isSynced)
        // Blank lines stay as stanza breaks; the words are what matter here.
        #expect(plain.lines.map(\.text).filter { !$0.isEmpty } == ["秘密の鍵を開けて", "心の奥を見せてあげる"])
    }
}

@Suite("가사 후보 고르기")
struct LyricsCandidateTests {
    private func record(
        duration: Double?,
        synced: Bool
    ) -> LRCLIBClient.Record {
        LRCLIBClient.Record(
            trackName: "夜に駆ける",
            artistName: "YOASOBI",
            albumName: nil,
            duration: duration,
            instrumental: false,
            plainLyrics: "眠るように",
            syncedLyrics: synced ? "[00:01.00]眠るように" : nil
        )
    }

    @Test("길이가 비슷하면 싱크된 쪽을 고른다")
    func prefersSyncedWhenBothFit() {
        let chosen = LRCLIBClient.best(
            from: [record(duration: 261, synced: false), record(duration: 262, synced: true)],
            duration: 261
        )
        #expect(chosen?.syncedLyrics != nil)
    }

    @Test("싱크돼 있어도 길이가 크게 어긋나면 길이가 맞는 쪽에 밀린다")
    func lengthBeatsSyncWhenTheGapIsWide() {
        // A synced sheet timed against a different edit drifts all song long.
        let chosen = LRCLIBClient.best(
            from: [record(duration: 261, synced: false), record(duration: 200, synced: true)],
            duration: 261
        )
        #expect(chosen?.syncedLyrics == nil)
        #expect(chosen?.duration == 261)
    }

    @Test("길이를 모르면 예전처럼 싱크된 쪽을 고른다")
    func fallsBackToSyncWithoutADuration() {
        let chosen = LRCLIBClient.best(
            from: [record(duration: 261, synced: false), record(duration: 200, synced: true)],
            duration: nil
        )
        #expect(chosen?.syncedLyrics != nil)
    }

    private func translation(duration: Double?) -> LRCLIBClient.Record {
        LRCLIBClient.Record(
            trackName: "夜に駆ける",
            artistName: "YOASOBI",
            albumName: nil,
            duration: duration,
            instrumental: false,
            plainLyrics: "Like sinking\nLike melting away",
            syncedLyrics: "[00:01.00]Like sinking\n[00:04.00]Like melting away"
        )
    }

    /// Nil is what lets the caller move on — to the next spelling, and in the
    /// end to the other edit's words as plain text. Falling back to whatever
    /// was left meant neither ever ran.
    @Test("맞는 후보가 없으면 아무것도 고르지 않는다")
    func returnsNilWhenNothingFits() {
        let chosen = LRCLIBClient.best(
            from: [translation(duration: 261), record(duration: 200, synced: true)],
            duration: 261
        )
        #expect(chosen == nil)
    }

    @Test("번역본보다 길이가 맞는 일본어 가사를 고른다")
    func choosesJapaneseWithinTolerance() {
        let chosen = LRCLIBClient.best(
            from: [translation(duration: 261), record(duration: 265, synced: false)],
            duration: 261
        )
        #expect(chosen?.duration == 265)
        #expect(chosen?.plainLyrics == "眠るように")
    }

    @Test("번역본만 있으면 길이가 맞아도 고르지 않는다")
    func neverFallsBackToATranslation() {
        #expect(LRCLIBClient.best(from: [translation(duration: 261)], duration: 261) == nil)
        #expect(LRCLIBClient.best(from: [translation(duration: nil)], duration: nil) == nil)
    }

    @Test("길이가 어긋난 일본어 가사는 다른 판본으로 따로 남는다")
    func lengthMismatchIsLeftForThePlainFallback() {
        let other = record(duration: 200, synced: true)
        #expect(LRCLIBClient.best(from: [other], duration: 261) == nil)
        #expect(LRCLIBClient.bestRegardlessOfLength(from: [translation(duration: 261), other])?.duration == 200)
    }
}

@Suite("가사 요청 취소")
struct LyricsCancellationTests {
    @Test("취소는 취소로 알아본다")
    func recognisesCancellation() {
        #expect(CancellationError().isCancellation)
        #expect(URLError(.cancelled).isCancellation)
    }

    @Test("네트워크 실패는 취소가 아니다")
    func networkFailureIsNotCancellation() {
        #expect(!URLError(.notConnectedToInternet).isCancellation)
        #expect(!LRCLIBClient.Failure.notFound.isCancellation)
    }

    /// Cancelled before it starts, the lookup must not walk every spelling and
    /// then report the cancellation as a network failure.
    @Test("취소된 작업은 다른 표기를 더 시도하지 않고 취소로 끝난다")
    func cancelledLookupThrowsCancellation() async {
        let task = Task {
            try await LRCLIBClient().lyrics(artist: "テスト", title: "テスト")
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("취소됐는데 가사를 돌려받았다")
        } catch {
            #expect(error.isCancellation)
        }
    }
}

@Suite("제목 정리의 괄호 짝맞추기")
struct TitleBracketTests {
    @Test("중첩 괄호를 짝으로 떼어낸다")
    func matchesNestedBrackets() {
        // 마지막 여는 괄호를 찾으면 안쪽 것을 잡아 「Yes! 東京 (feat. A」처럼
        // 괄호가 안 맞는 조각이 남는다.
        #expect(LRCLIBClient.simplifiedTitle("Yes! 東京 (feat. A (B))") == "Yes! 東京")
    }

    @Test("괄호가 여러 개 붙어도 다 떼어낸다")
    func stripsSeveralGroups() {
        #expect(LRCLIBClient.simplifiedTitle("Hello (World) [Live]") == "Hello")
    }

    @Test("가운데 괄호는 건드리지 않는다")
    func leavesInnerGroupsAlone() {
        #expect(LRCLIBClient.simplifiedTitle("Hello (World) Goodbye") == "Hello (World) Goodbye")
    }

    @Test("짝이 맞지 않으면 손대지 않는다")
    func leavesUnbalancedTitlesAlone() {
        #expect(LRCLIBClient.simplifiedTitle("Hello (World") == "Hello (World")
    }
}

/// Answers every request from a script, and counts them.
private final class ScriptedLRCLIB: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var statuses: [Int] = []
    nonisolated(unsafe) static var body = Data("[]".utf8)
    nonisolated(unsafe) static var requests = 0

    static func session(statuses: [Int], body: String) -> URLSession {
        self.statuses = statuses
        self.body = Data(body.utf8)
        requests = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptedLRCLIB.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let status = Self.statuses.isEmpty ? 200 : Self.statuses.removeFirst()
        Self.requests += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: status == 200 ? Self.body : Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("가사 서버가 바쁠 때", .serialized)
struct LyricsServerBusyTests {
    private let sheet = #"[{"trackName":"テスト","artistName":"テスト","duration":200,"instrumental":false,"plainLyrics":"君と見た空","syncedLyrics":"[00:01.00]君と見た空"}]"#

    /// A 503 is often a moment's overload: one retry gets through.
    @Test("한 번 503이면 잠시 뒤 다시 물어 가사를 받는다")
    func retriesOnce() async throws {
        let session = ScriptedLRCLIB.session(statuses: [503, 200], body: sheet)
        let client = LRCLIBClient(session: session, retryDelay: .zero)
        let lyrics = try await client.lyrics(artist: "テスト", title: "テスト")
        #expect(lyrics.lines.first?.text == "君と見た空")
        #expect(ScriptedLRCLIB.requests == 2)
    }

    /// Every spelling hit the same dead server before; now the first answer
    /// that says the server is down ends the lookup, with words a reader can
    /// act on instead of 「LRCLIB 오류 (503)」.
    @Test("계속 503이면 다른 표기를 더 묻지 않고 바쁘다고 알린다")
    func stopsWhenTheServerIsDown() async {
        let session = ScriptedLRCLIB.session(statuses: Array(repeating: 503, count: 20), body: "[]")
        let client = LRCLIBClient(session: session, retryDelay: .zero)
        do {
            _ = try await client.lyrics(artist: "テスト", title: "テスト (feat. 誰か)")
            Issue.record("서버가 죽어 있는데 가사를 돌려받았다")
        } catch let failure as LRCLIBClient.Failure {
            guard case .serverBusy(503) = failure else {
                Issue.record("serverBusy가 아니라 \(failure)")
                return
            }
            #expect(failure.localizedDescription.contains("가사 서버"))
        } catch {
            Issue.record("예상하지 못한 오류 \(error)")
        }
        // One search and its single retry — not one per spelling.
        #expect(ScriptedLRCLIB.requests == 2)
    }
}
