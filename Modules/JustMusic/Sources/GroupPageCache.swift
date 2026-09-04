import Foundation

/// The groups' pages, kept between launches.
///
/// The pictures themselves were already on disk, but the *addresses* of the
/// pictures were not — every launch asked Apple Music for all seven groups
/// again and showed gradients until the answers came. Offline, or before Apple
/// Music was allowed, the grid had no faces at all. The page is a URL and a
/// song list, small enough to keep as one JSON file.
///
/// Lives in Caches: the system may reclaim it, which is the right contract for
/// something that can always be fetched again, and it stays out of backups.
public struct GroupPageCache: Sendable {
    public struct Snapshot: Codable, Equatable {
        public var pages: [String: AppleMusicClient.ArtistPage]
        public var fetchedAt: [String: Date]

        public init(pages: [String: AppleMusicClient.ArtistPage] = [:], fetchedAt: [String: Date] = [:]) {
            self.pages = pages
            self.fetchedAt = fetchedAt
        }
    }

    public let file: URL

    public init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        file = base.appendingPathComponent("groups.json")
    }

    public func restore() -> Snapshot {
        guard let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return Snapshot() }
        return snapshot
    }

    public func persist(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: file, options: .atomic)
    }

    /// A page older than this is refreshed in the background — the picture
    /// stays on screen while the new one is fetched. A group's songs change
    /// on release days, not hourly.
    public static let freshFor: TimeInterval = 60 * 60 * 24

    public static func isStale(_ fetchedAt: Date?, now: Date = .now) -> Bool {
        guard let fetchedAt else { return true }
        return now.timeIntervalSince(fetchedAt) > freshFor
    }
}
