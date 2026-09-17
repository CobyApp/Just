import Foundation
import JustCore
import JustMusic
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
