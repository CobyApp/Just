import Foundation
import JustCore
@testable import JustMusic
import Testing

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

    @Test("Instrumental·off vocal은 공부할 게 없다")
    func unsingable() {
        #expect(ITunesCatalog.isUnsingable("かがみ (Instrumental)"))
        #expect(ITunesCatalog.isUnsingable("かがみ -off vocal-"))
        #expect(!ITunesCatalog.isUnsingable("かがみ"))
    }

    @Test("아티스트 페이지의 og:image를 정사각으로")
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
        #expect(IdolGroup.group(forArtist: "YOASOBI") == nil)
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
