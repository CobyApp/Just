import Foundation
import RingRingCore
@testable import RingRingMusic
import Testing

@Suite("영상 목록의 「없음」 기억")
struct VideoDirectoryMissTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("옛 파일의 「없음」은 날짜가 없어 한 번 더 찾는다")
    func oldMissIsAskedAgain() throws {
        let data = #"{"videos":{"1":"abc","2":""}}"#.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(VideoDirectory.Snapshot.self, from: data)
        #expect(snapshot.misses.isEmpty)
        #expect(snapshot.lookup("1", now: now) == .video("abc"))
        #expect(snapshot.lookup("2", now: now) == .unknown)
        #expect(snapshot.lookup("3", now: now) == .unknown)
    }

    @Test("「없음」은 일주일 동안만 믿는다")
    func missExpires() {
        var snapshot = VideoDirectory.Snapshot()
        snapshot.recordMiss(for: "1", permanent: false, now: now)
        #expect(snapshot.videos["1"] == "")
        #expect(snapshot.lookup("1", now: now.addingTimeInterval(60 * 60 * 24 * 6)) == .noVideo)
        #expect(snapshot.lookup("1", now: now.addingTimeInterval(60 * 60 * 24 * 8)) == .unknown)
    }

    @Test("퍼가기 거부로 끝난 곡은 계속 기억한다")
    func permanentMissStays() {
        var snapshot = VideoDirectory.Snapshot()
        snapshot.recordMiss(for: "1", permanent: true, now: now)
        #expect(snapshot.lookup("1", now: now.addingTimeInterval(60 * 60 * 24 * 365)) == .noVideo)
    }

    @Test("다음 후보로 넘어가고, 다 떨어지면 오류 코드로 영구 여부를 정한다")
    func advance() {
        var snapshot = VideoDirectory.Snapshot()
        snapshot.record("a", alternates: ["b"], for: "1")
        #expect(snapshot.advance("1", afterError: 150, now: now) == "b")
        #expect(snapshot.lookup("1", now: now) == .video("b"))
        #expect(snapshot.advance("1", afterError: 150, now: now) == nil)
        #expect(snapshot.misses["1"] == VideoDirectory.Miss(at: now, permanent: true))

        var stalled = VideoDirectory.Snapshot()
        stalled.record("a", alternates: [], for: "2")
        #expect(stalled.advance("2", afterError: 0, now: now) == nil)
        #expect(stalled.misses["2"]?.permanent == false)
    }

    @Test("찾은 영상은 「없음」 기록을 지운다")
    func recordClearsMiss() {
        var snapshot = VideoDirectory.Snapshot()
        snapshot.recordMiss(for: "1", permanent: true, now: now)
        snapshot.record("a", alternates: [], for: "1")
        #expect(snapshot.misses["1"] == nil)
        #expect(snapshot.lookup("1", now: now) == .video("a"))
    }

    @Test("날짜까지 저장하고 다시 읽는다")
    func roundTrip() throws {
        var snapshot = VideoDirectory.Snapshot(videos: ["1": "abc"])
        snapshot.recordMiss(for: "2", permanent: false, now: now)
        let decoded = try JSONDecoder().decode(
            VideoDirectory.Snapshot.self, from: JSONEncoder().encode(snapshot)
        )
        #expect(decoded == snapshot)
        #expect(decoded.lookup("2", now: now) == .noVideo)
    }

    @Test("늦게 도착한 옛 저장은 새 저장을 덮지 않는다")
    func writerKeepsNewest() async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("videos-\(UUID().uuidString)", isDirectory: true)
        let directory = VideoDirectory(directory: dir)
        let writer = VideoDirectoryWriter(directory: directory)
        await writer.write(.init(videos: ["1": "new"]), sequence: 2)
        await writer.write(.init(videos: ["1": "old"]), sequence: 1)
        #expect(directory.restore().videos == ["1": "new"])
    }
}

@Suite("재생 실패 처리")
struct PlaybackFailureTests {
    @Test("영상 길이 응답에 같은 ID가 두 번 와도 죽지 않는다")
    func duplicateDurations() throws {
        let data = """
        {"items":[{"id":"a","contentDetails":{"duration":"PT3M"}},
                  {"id":"a","contentDetails":{"duration":"PT4M"}}]}
        """.data(using: .utf8)!
        #expect(try YouTubeClient.durations(from: data) == ["a": 180])
    }

    @Test("취소는 실패가 아니다")
    func cancellation() {
        #expect(CancellationError().isCancellation)
        #expect(URLError(.cancelled).isCancellation)
        #expect(!URLError(.timedOut).isCancellation)
        #expect(!YouTubeClient.Failure.notFound.isCancellation)
    }

    @Test("네트워크 문제와 영상 없음은 다르게 말한다")
    func messages() {
        let noVideo = PlaybackFailure.message(
            videoError: YouTubeClient.Failure.notFound,
            previewError: ITunesCatalog.Failure.noPreview
        )
        #expect(noVideo == ITunesCatalog.Failure.noPreview.localizedDescription)

        let offline = PlaybackFailure.message(
            videoError: URLError(.notConnectedToInternet),
            previewError: ITunesCatalog.Failure.notFound
        )
        #expect(offline != noVideo)
        #expect(offline.contains("인터넷"))

        let transport = PlaybackFailure.message(
            videoError: nil,
            previewError: ITunesCatalog.Failure.transport("곡 정보를 받지 못했습니다.")
        )
        #expect(transport == "곡 정보를 받지 못했습니다.")
    }
}
