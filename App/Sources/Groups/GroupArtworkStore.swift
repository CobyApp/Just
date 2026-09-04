import Foundation
import JustCore
import JustMusic
import Observation

/// The seven groups' pictures and songs.
///
/// Restored from disk at init, so the grid has faces on its first frame; then
/// whatever is missing or a day old is refreshed in the background without
/// taking the existing picture away. A group that fails is simply left as it
/// was — on its cached page, or on its gradient — and the detail screen asks
/// again.
@MainActor
@Observable
final class GroupArtworkStore {
    private(set) var pages: [String: AppleMusicClient.ArtistPage]
    private var fetchedAt: [String: Date]
    private var inFlight: Set<String> = []
    private let client = AppleMusicClient()
    private let cache: GroupPageCache

    init(cache: GroupPageCache = GroupPageCache()) {
        self.cache = cache
        let snapshot = cache.restore()
        pages = snapshot.pages
        fetchedAt = snapshot.fetchedAt
    }

    func artworkURL(for group: IdolGroup) -> URL? {
        pages[group.id]?.artworkURL
    }

    func songs(for group: IdolGroup) -> [Track]? {
        pages[group.id]?.songs
    }

    /// Fills whatever is missing or stale. Safe to call on every appearance.
    func loadAll() async {
        for group in IdolGroup.all
        where GroupPageCache.isStale(fetchedAt[group.id]) && !inFlight.contains(group.id) {
            inFlight.insert(group.id)
            defer { inFlight.remove(group.id) }
            if let page = try? await client.artistPage(id: group.id) {
                remember(page, for: group)
            }
        }
    }

    func reload(_ group: IdolGroup) async throws -> AppleMusicClient.ArtistPage {
        let page = try await client.artistPage(id: group.id)
        remember(page, for: group)
        return page
    }

    private func remember(_ page: AppleMusicClient.ArtistPage, for group: IdolGroup) {
        pages[group.id] = page
        fetchedAt[group.id] = .now
        let snapshot = GroupPageCache.Snapshot(pages: pages, fetchedAt: fetchedAt)
        let cache = self.cache
        Task.detached(priority: .utility) { cache.persist(snapshot) }
    }
}
