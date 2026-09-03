import Foundation
import JustCore
import JustMusic
import Observation

/// The seven groups' pictures, fetched once and kept for the launch.
///
/// The grid appears every time the tab does, and a card that refetched its
/// image on each appearance would flicker to a gradient and back. Seven
/// requests, once, is the right cost — and the same request already carries the
/// songs, so the detail screen gets those for free when it opens.
@MainActor
@Observable
final class GroupArtworkStore {
    private(set) var pages: [String: AppleMusicClient.ArtistPage] = [:]
    private var inFlight: Set<String> = []
    private let client = AppleMusicClient()

    func artworkURL(for group: IdolGroup) -> URL? {
        pages[group.id]?.artworkURL
    }

    func songs(for group: IdolGroup) -> [Track]? {
        pages[group.id]?.songs
    }

    /// Fills whatever is missing. Safe to call on every appearance.
    func loadAll() async {
        for group in IdolGroup.all where pages[group.id] == nil && !inFlight.contains(group.id) {
            inFlight.insert(group.id)
            defer { inFlight.remove(group.id) }
            // A group that fails is simply left without a picture; the card
            // still works on its gradient, and the detail screen asks again.
            if let page = try? await client.artistPage(id: group.id) {
                pages[group.id] = page
            }
        }
    }

    func reload(_ group: IdolGroup) async throws -> AppleMusicClient.ArtistPage {
        let page = try await client.artistPage(id: group.id)
        pages[group.id] = page
        return page
    }
}
