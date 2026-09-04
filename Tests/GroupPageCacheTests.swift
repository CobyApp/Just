import Foundation
import JustCore
import JustMusic
import Testing

@Suite("그룹 페이지 캐시")
struct GroupPageCacheTests {
    private func temporary() -> GroupPageCache {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("group-cache-\(UUID().uuidString)", isDirectory: true)
        return GroupPageCache(directory: dir)
    }

    @Test("저장한 페이지를 다음 실행에서 그대로 돌려준다")
    func roundTrip() {
        let cache = temporary()
        let track = Track(
            id: "s1", title: "わたしの一番かわいいところ", artist: "FRUITS ZIPPER",
            artworkURL: URL(string: "https://example.com/a.jpg"), duration: 255
        )
        let page = AppleMusicClient.ArtistPage(
            artworkURL: URL(string: "https://example.com/artist.jpg"), songs: [track]
        )
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        cache.persist(.init(pages: ["g": page], fetchedAt: ["g": stamp]))

        let restored = cache.restore()
        #expect(restored.pages["g"] == page)
        #expect(restored.fetchedAt["g"] == stamp)
    }

    @Test("파일이 없으면 빈 스냅샷")
    func empty() {
        #expect(temporary().restore() == .init())
    }

    @Test("하루가 지나면 낡은 것, 없으면 낡은 것")
    func staleness() {
        let now = Date()
        #expect(GroupPageCache.isStale(nil, now: now))
        #expect(!GroupPageCache.isStale(now.addingTimeInterval(-3600), now: now))
        #expect(GroupPageCache.isStale(now.addingTimeInterval(-90_000), now: now))
    }
}
