import Foundation
import JustCore
import Testing

@testable import JustLyrics

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
        [00:01.64] 夢ならばどれほどよかったでしょう
        [00:07.19] 未だにあなたのことを夢にみる
        [00:12.00] 忘れた物を取りに帰るように
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
