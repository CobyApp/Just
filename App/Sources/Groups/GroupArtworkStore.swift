import Foundation
import RingRingCore
import RingRingMusic
import Observation

/// Every group's picture and songs.
///
/// Restored from disk at init, so the grid has faces on its first frame; then
/// whatever is missing or a day old is refreshed in the background without
/// taking the existing picture away. A group that fails is simply left as it
/// was — on its cached page, or on its gradient — and the detail screen asks
/// again.
@MainActor
@Observable
final class GroupArtworkStore {
    private(set) var pages: [String: ArtistPage]
    private var fetchedAt: [String: Date]
    private var inFlight: Set<String> = []
    private let client = ITunesCatalog()
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
    ///
    /// In roster order, so the sections at the top fill first. The lookup
    /// service allows about twenty requests a minute, and with thirty-odd
    /// groups a first launch runs into that — a group that is turned away is
    /// asked again after a pause rather than left blank until tomorrow.
    func loadAll() async {
        var waiting = IdolGroup.all.filter { GroupPageCache.isStale(fetchedAt[$0.id]) && !inFlight.contains($0.id) }
        for attempt in 0..<3 where !waiting.isEmpty {
            if attempt > 0 {
                // The limit is per minute; half of one is usually enough.
                try? await Task.sleep(for: .seconds(35))
                guard !Task.isCancelled else { return }
            }
            var refused: [IdolGroup] = []
            for group in waiting {
                guard !Task.isCancelled else { return }
                inFlight.insert(group.id)
                if let page = try? await client.artistPage(id: group.id) {
                    remember(page, for: group)
                } else {
                    refused.append(group)
                }
                inFlight.remove(group.id)
            }
            waiting = refused
        }
    }

    func reload(_ group: IdolGroup) async throws -> ArtistPage {
        let page = try await client.artistPage(id: group.id)
        remember(page, for: group)
        return page
    }

    private func remember(_ page: ArtistPage, for group: IdolGroup) {
        pages[group.id] = page
        fetchedAt[group.id] = .now
        let snapshot = GroupPageCache.Snapshot(pages: pages, fetchedAt: fetchedAt)
        let cache = self.cache
        Task.detached(priority: .utility) { cache.persist(snapshot) }
    }
}
