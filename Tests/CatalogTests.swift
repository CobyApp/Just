import Foundation
import JustCore
@testable import JustMusic
import Testing
import UIKit
@testable import JustDesign

@Suite("iTunes 카탈로그")
struct ITunesCatalogTests {
    private let payload = """
    {"resultCount":5,"results":[
      {"wrapperType":"artist","artistName":"FRUITS ZIPPER"},
      {"wrapperType":"track","kind":"song","trackId":1,"trackName":"わたしの一番かわいいところ","artistName":"FRUITS ZIPPER","collectionName":"A","artworkUrl100":"https://x/100x100bb.jpg","trackTimeMillis":255000,"releaseDate":"2022-04-01T12:00:00Z"},
      {"wrapperType":"track","kind":"song","trackId":2,"trackName":"わたしの一番かわいいところ (Instrumental)","artistName":"FRUITS ZIPPER","trackTimeMillis":255000,"releaseDate":"2022-04-01T12:00:00Z"},
      {"wrapperType":"track","kind":"song","trackId":3,"trackName":"わたしの一番かわいいところ (2024 ver.)","artistName":"FRUITS ZIPPER","trackTimeMillis":250000,"releaseDate":"2024-01-01T12:00:00Z"},
      {"wrapperType":"track","kind":"song","trackId":4,"trackName":"NEW KAWAII","artistName":"FRUITS ZIPPER","trackTimeMillis":266000,"releaseDate":"2024-06-01T12:00:00Z"}
    ]}
    """.data(using: .utf8)!

    @Test("노래만, 한 곡에 한 행, 새 것부터, 큰 커버")
    func tracks() throws {
        let decoded = try JSONDecoder().decode(ITunesCatalog.Payload.self, from: payload)
        let tracks = ITunesCatalog.tracks(from: decoded, limit: 40)
        #expect(tracks.map(\.title) == ["NEW KAWAII", "わたしの一番かわいいところ (2024 ver.)"])
        #expect(tracks.map(\.id) == ["4", "3"])
        #expect(tracks[0].duration == 266)
    }

    /// =LOVE's page opened on its tour album: the newest release of every
    /// song it played that night, plus a Korean version at the very top.
    @Test("라이브·외국어 버전보다 스튜디오 원곡이 목록에 선다")
    func prefersTheStudioRecording() throws {
        let tour = """
        {"resultCount":5,"results":[
          {"wrapperType":"track","kind":"song","trackId":10,"trackName":"僕のヒロイン","collectionName":"僕のヒロイン - Single","trackTimeMillis":200000,"releaseDate":"2023-01-01T12:00:00Z"},
          {"wrapperType":"track","kind":"song","trackId":11,"trackName":"僕のヒロイン (=LOVE 8th ANNIVERSARY PREMIUM TOUR)","collectionName":"=LOVE 8th ANNIVERSARY PREMIUM TOUR","trackTimeMillis":210000,"releaseDate":"2025-09-01T12:00:00Z"},
          {"wrapperType":"track","kind":"song","trackId":12,"trackName":"恋、はじめました。","collectionName":"恋、はじめました。 - Single","trackTimeMillis":220000,"releaseDate":"2025-03-01T12:00:00Z"},
          {"wrapperType":"track","kind":"song","trackId":13,"trackName":"恋、はじめました。 (Korean ver.)","collectionName":"恋、はじめました。 (Korean ver.) - Single","trackTimeMillis":220000,"releaseDate":"2025-10-01T12:00:00Z"},
          {"wrapperType":"track","kind":"song","trackId":14,"trackName":"青春サブリミナル","collectionName":"=LOVE LIVE TOUR","trackTimeMillis":300000,"releaseDate":"2025-09-01T12:00:00Z"}
        ]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ITunesCatalog.Payload.self, from: tour)
        let tracks = ITunesCatalog.tracks(from: decoded, limit: 40)
        // The live take stays only where it is the song's one recording.
        #expect(tracks.map(\.id) == ["14", "12", "10"])
        #expect(!tracks.contains { $0.title.contains("Korean") })
    }

    @Test("한국어·영어 버전은 일본어가 아니다")
    func otherLanguages() {
        #expect(ITunesCatalog.isOtherLanguage("恋、はじめました。 (Korean ver.)"))
        #expect(ITunesCatalog.isOtherLanguage("Chu Chu - English Version"))
        #expect(!ITunesCatalog.isOtherLanguage("恋、はじめました。"))
    }

    @Test("Instrumental·off vocal은 공부할 게 없다")
    func unsingable() {
        #expect(ITunesCatalog.isUnsingable("かがみ (Instrumental)"))
        #expect(ITunesCatalog.isUnsingable("かがみ -off vocal-"))
        #expect(!ITunesCatalog.isUnsingable("かがみ"))
    }

    @Test("아티스트 페이지의 og:image를 정사각 사진으로")
    func portrait() {
        let html = #"<meta property="og:image" content="https://is1-ssl.mzstatic.com/image/thumb/abc/1200x630cw.png">"#
        #expect(ITunesCatalog.portraitURL(inPage: html)?.absoluteString == "https://is1-ssl.mzstatic.com/image/thumb/abc/800x800cc.png")
        #expect(ITunesCatalog.portraitURL(inPage: "<html></html>") == nil)
    }

    @Test("100pt 커버를 600pt로")
    func artwork() {
        #expect(ITunesCatalog.largeArtwork("https://x/100x100bb.jpg") == "https://x/600x600bb.jpg")
    }
}

@Suite("YouTube 영상 고르기")
struct YouTubeClientTests {
    private let track = Track(id: "1", title: "わたしの一番かわいいところ", artist: "FRUITS ZIPPER", duration: 255)

    @Test("공식 MV가 댄스 프랙티스와 라이브를 이긴다")
    func choosesOfficialVideo() {
        let candidates = [
            YouTubeClient.Candidate(videoID: "dance", title: "FRUITS ZIPPER「わたしの一番かわいいところ」Dance Practice", channelTitle: "FRUITS ZIPPER"),
            YouTubeClient.Candidate(videoID: "mv", title: "FRUITS ZIPPER「わたしの一番かわいいところ」Music Video", channelTitle: "FRUITS ZIPPER"),
            YouTubeClient.Candidate(videoID: "live", title: "わたしの一番かわいいところ / FRUITS ZIPPER LIVE", channelTitle: "someone"),
        ]
        #expect(YouTubeClient.choose(candidates, for: track)?.videoID == "mv")
    }

    @Test("ISO 8601 길이를 초로")
    func parsesDuration() {
        #expect(YouTubeClient.parseDuration("PT3M28S") == 208)
        #expect(YouTubeClient.parseDuration("PT24S") == 24)
        #expect(YouTubeClient.parseDuration("PT1H2M") == 3720)
        #expect(YouTubeClient.parseDuration("P1D") == nil)
    }

    @Test("곡 길이와 어긋나는 영상은 걸러진다")
    func filtersByLength() {
        let short = YouTubeClient.Candidate(videoID: "short", title: "『わたしの一番かわいいところ』MV公開", channelTitle: "FRUITS ZIPPER")
        let mv = YouTubeClient.Candidate(videoID: "mv", title: "【MV】わたしの一番かわいいところ", channelTitle: "KAWAII LAB.")
        let unknown = YouTubeClient.Candidate(videoID: "x", title: "わたしの一番かわいいところ", channelTitle: "Topic")
        let kept = YouTubeClient.aboutTheSongsLength([short, mv, unknown], track: track, durations: ["short": 24, "mv": 262])
        #expect(kept.map(\.videoID) == ["mv", "x"])
    }

    @Test("MV 공개 안내 쇼츠는 MV보다 뒤로 간다")
    func announcementsSink() {
        let candidates = [
            YouTubeClient.Candidate(videoID: "short", title: "『わたしの一番かわいいところ』MV公開🚃 #FRUITSZIPPER #ふるっぱー", channelTitle: "FRUITS ZIPPER", channelID: "UCQG8tNnV4hKetLhMb4MopHQ"),
            YouTubeClient.Candidate(videoID: "mv", title: "【MV】FRUITS ZIPPER『わたしの一番かわいいところ』", channelTitle: "KAWAII LAB.", channelID: "UCW8Q9LBGGBgK6a-u0C0h95A"),
            YouTubeClient.Candidate(videoID: "inst", title: "わたしの一番かわいいところ (Instrumental)", channelTitle: "FRUITS ZIPPER - Topic", channelID: "UCB_jIxmkTjjAHyVZUD-kf4w"),
        ]
        let channels = IdolGroup.group(forArtist: "FRUITS ZIPPER")!.youtubeChannels
        let ranked = YouTubeClient.rank(candidates, for: track, channels: channels, strict: true)
        #expect(ranked.first?.videoID == "mv")
        #expect(!ranked.contains { $0.videoID == "inst" })
    }

    @Test("그룹 채널의 영상이 무엇보다 앞선다")
    func groupChannelFirst() {
        let candidates = [
            YouTubeClient.Candidate(videoID: "copy", title: "【MV】FRUITS ZIPPER「わたしの一番かわいいところ」", channelTitle: "someone official"),
            YouTubeClient.Candidate(videoID: "own", title: "わたしの一番かわいいところ", channelTitle: "FRUITS ZIPPER - Topic", channelID: "UCB_jIxmkTjjAHyVZUD-kf4w"),
        ]
        let channels = IdolGroup.group(forArtist: "FRUITS ZIPPER")!.youtubeChannels
        #expect(YouTubeClient.choose(candidates, for: track, channels: channels)?.videoID == "own")
    }

    @Test("업로드 목록은 채널 ID로 정해진다")
    func uploadsPlaylist() {
        #expect(YouTubeClient.uploadsPlaylist(ofChannel: "UCW8Q9LBGGBgK6a-u0C0h95A") == "UUW8Q9LBGGBgK6a-u0C0h95A")
    }

    @Test("업로드 응답에서 비공개·삭제 영상은 뺀다")
    func decodesPlaylist() throws {
        let data = """
        {"nextPageToken":"N","items":[
          {"snippet":{"title":"【MV】A","channelTitle":"KAWAII LAB.","resourceId":{"videoId":"a"}}},
          {"snippet":{"title":"Private video","resourceId":{"videoId":"p"}}}]}
        """.data(using: .utf8)!
        let (items, next) = try YouTubeClient.playlistItems(from: data, channelID: "UC1")
        #expect(items.map(\.videoID) == ["a"])
        #expect(items[0].channelID == "UC1")
        #expect(next == "N")
    }

    @Test("아티스트 이름으로 그룹을 찾는다")
    func groupForArtist() {
        #expect(IdolGroup.group(forArtist: "FRUITS ZIPPER")?.name == "FRUITS ZIPPER")
        #expect(IdolGroup.group(forArtist: "=LOVE")?.name == "=LOVE")
        #expect(IdolGroup.group(forArtist: "米津玄師") == nil)
    }

    @Test("공식 MV가 자막 재업로드를 이긴다")
    func officialBeatsSubtitledCopy() {
        let candidates = [
            YouTubeClient.Candidate(videoID: "copy", title: "[MV] FRUITS ZIPPER - わたしの一番かわいいところ (한글자막)", channelTitle: "some subs"),
            YouTubeClient.Candidate(videoID: "mv", title: "【MV】FRUITS ZIPPER「わたしの一番かわいいところ」", channelTitle: "KAWAII LAB."),
        ]
        #expect(YouTubeClient.choose(candidates, for: track)?.videoID == "mv")
    }

    @Test("MV 다음에 다른 후보가 순서대로 남는다")
    func keepsRunnersUp() {
        let candidates = [
            YouTubeClient.Candidate(videoID: "live", title: "わたしの一番かわいいところ LIVE", channelTitle: "FRUITS ZIPPER"),
            YouTubeClient.Candidate(videoID: "mv", title: "【MV】FRUITS ZIPPER「わたしの一番かわいいところ」", channelTitle: "KAWAII LAB."),
            YouTubeClient.Candidate(videoID: "topic", title: "わたしの一番かわいいところ", channelTitle: "FRUITS ZIPPER - Topic"),
        ]
        #expect(YouTubeClient.rank(candidates, for: track, strict: true).map(\.videoID) == ["mv", "topic", "live"])
    }

    @Test("느슨한 패스는 라이브·리릭도 받는다")
    func plainPassAdmitsMore() {
        let candidates = [YouTubeClient.Candidate(videoID: "lyric", title: "わたしの一番かわいいところ Lyric Video", channelTitle: "fan")]
        #expect(YouTubeClient.rank(candidates, for: track, strict: true).isEmpty)
        #expect(YouTubeClient.rank(candidates, for: track, strict: false).map(\.videoID) == ["lyric"])
    }

    @Test("옛 목록 파일도 읽힌다")
    func decodesOldDirectory() throws {
        let data = #"{"videos":{"1":"abc"}}"#.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(VideoDirectory.Snapshot.self, from: data)
        #expect(snapshot.videos == ["1": "abc"])
        #expect(snapshot.alternates.isEmpty)
    }

    @Test("제목에 곡명이 없으면 후보가 아니다")
    func requiresTitle() {
        let candidates = [YouTubeClient.Candidate(videoID: "x", title: "FRUITS ZIPPER NEW KAWAII MV", channelTitle: "FRUITS ZIPPER")]
        #expect(YouTubeClient.choose(candidates, for: track) == nil)
    }

    @Test("검색 응답을 후보로")
    func decodes() throws {
        let data = """
        {"items":[{"id":{"kind":"youtube#video","videoId":"abc"},"snippet":{"title":"A &amp; B","channelTitle":"C"}},
                  {"id":{"kind":"youtube#channel"},"snippet":{"title":"ch","channelTitle":"C"}}]}
        """.data(using: .utf8)!
        let candidates = try YouTubeClient.candidates(from: data)
        #expect(candidates == [YouTubeClient.Candidate(videoID: "abc", title: "A & B", channelTitle: "C")])
    }

    @Test("영상 목록은 다음 실행에도 남는다")
    func directory() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("videos-\(UUID().uuidString)", isDirectory: true)
        let directory = VideoDirectory(directory: dir)
        directory.persist(.init(videos: ["1": "abc", "2": ""]))
        #expect(directory.restore().videos == ["1": "abc", "2": ""])
    }
}

@Suite("사진 속 검은 띠 자르기")
@MainActor
struct LetterboxTests {
    private func image(width: Int, height: Int, bar: Int, barColor: UIColor = .black) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: {
            let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f
        }())
        return renderer.image { context in
            barColor.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.systemPink.setFill(); context.fill(CGRect(x: 0, y: bar, width: width, height: height - bar * 2))
        }
    }

    @Test("위아래 띠를 잘라낸다")
    func trimsBars() {
        let trimmed = Letterbox.trimmed(image(width: 200, height: 200, bar: 25))
        #expect(trimmed.cgImage?.width == 200)
        #expect(trimmed.cgImage?.height == 150)
    }

    @Test("짙은 회색 띠도 잘라낸다")
    func trimsCharcoalBars() {
        let grey = UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1)
        #expect(Letterbox.trimmed(image(width: 200, height: 200, bar: 20, barColor: grey)).cgImage?.height == 160)
    }

    @Test("띠가 없으면 그대로")
    func leavesCleanPictures() {
        let clean = image(width: 200, height: 200, bar: 0)
        #expect(Letterbox.trimmed(clean).cgImage?.height == 200)
    }

    @Test("거의 전부 어두운 사진은 자르지 않는다")
    func leavesDarkPictures() {
        let dark = image(width: 200, height: 200, bar: 80)
        #expect(Letterbox.trimmed(dark).cgImage?.height == 200)
    }
}

@Suite("MV 찾기 보강")
struct VideoMatchingTests {
    private func track(_ title: String, artist: String = "モーニング娘。") -> Track {
        Track(id: "t", title: title, artist: artist, duration: 240)
    }

    @Test("카탈로그의 하이픈 장음도 영상 제목의 ー와 맞는다")
    func longVowelHyphen() {
        let video = YouTubeClient.Candidate(videoID: "v", title: "モーニング娘。『LOVEマシーン』(MV)", channelTitle: "モーニング娘。")
        #expect(YouTubeClient.rank([video], for: track("LOVEマシ-ン"), strict: true).map(\.videoID) == ["v"])
    }

    @Test("「/멤버」 크레딧과 판 표기를 떼고도 찾는다")
    func coreTitle() {
        let video = YouTubeClient.Candidate(videoID: "v", title: "モーニング娘。『大きい瞳』MV", channelTitle: "モーニング娘。")
        #expect(!YouTubeClient.rank([video], for: track("大きい瞳/亀井絵里・道重さゆみ・田中れいな"), strict: true).isEmpty)
        let ver = YouTubeClient.Candidate(videoID: "w", title: "【MV】NEW KAWAII", channelTitle: "KAWAII LAB.")
        #expect(!YouTubeClient.rank([ver], for: track("NEW KAWAII (2025 ver.)", artist: "FRUITS ZIPPER"), strict: true).isEmpty)
    }

    @Test("「・・・(略)」로 줄인 긴 제목은 잘린 앞부분으로 찾는다")
    func shortenedTitle() {
        let video = YouTubeClient.Candidate(videoID: "v", title: "【MV】鈴懸の木の道で「君の微笑みを夢に見る」と言ってしまったら僕たちの関係はどう変わってしまうのか、僕なりに何日か考えた上でのやや気恥ずかしい結論のようなもの / AKB48", channelTitle: "AKB48")
        #expect(!YouTubeClient.rank([video], for: track("鈴懸の木の道で・・・(略)やや気恥ずかしい結論のようなもの", artist: "AKB48"), strict: true).isEmpty)
    }

    @Test("짧은 영문 키는 버리고, 두 글자 일본어 제목은 쓴다")
    func noTinyKeys() {
        #expect(YouTubeClient.titleKeys("I").isEmpty)
        #expect(YouTubeClient.titleKeys("走れ! -ZZ ver.-").contains("走れ"))
    }

    @Test("채널 목록은 새 영상을 앞에, 겹침 없이 붙인다")
    func mergesUploads() {
        let old = VideoDirectory.ChannelUploads(fetchedAt: .distantPast, videos: [
            .init(videoID: "b", title: "B", channelTitle: "c"), .init(videoID: "a", title: "A", channelTitle: "c"),
        ])
        let merged = old.merging(newer: [.init(videoID: "c", title: "C", channelTitle: "c"), .init(videoID: "b", title: "B", channelTitle: "c")])
        #expect(merged.videos.map(\.videoID) == ["c", "b", "a"])
        #expect(merged.isDeep)
    }

    @Test("옛 파일의 '못 찾음'은 다시 찾고, 임베드 거부는 유지한다")
    func oldMissesAreRetried() throws {
        let json = #"{"videos":{"1":"","2":""},"misses":{"1":{"at":0,"permanent":false},"2":{"at":0,"permanent":true}},"channels":{"UCx":{"fetchedAt":0,"videos":[]}}}"#
        let snapshot = try JSONDecoder().decode(VideoDirectory.Snapshot.self, from: Data(json.utf8))
        #expect(snapshot.videos["1"] == nil)
        #expect(snapshot.videos["2"] == "")
        #expect(snapshot.channels["UCx"]?.isDeep == false)
    }
}
