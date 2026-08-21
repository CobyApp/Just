import Foundation
import JustCore
import MusicKit

/// A titled row of songs for the browse screen.
public struct MusicShelf: Identifiable, Sendable {
    public let id: String
    public let title: String
    /// Why these songs are here, shown under the title.
    public let subtitle: String?
    public let tracks: [JustCore.Track]

    public init(id: String, title: String, subtitle: String? = nil, tracks: [JustCore.Track]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.tracks = tracks
    }
}

/// An album with its full track list.
public struct AlbumDetail: Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let artworkURL: URL?
    public let releaseYear: String?
    public let genre: String?
    public let tracks: [JustCore.Track]
}

public extension AppleMusicClient {
    // MARK: - Album

    /// The album a song belongs to, with every track on it.
    ///
    /// This is the "앨범 정보 전부" that a video platform cannot answer: the
    /// catalog knows the record, its running order and its release date.
    func album(forTrackID trackID: String) async throws -> AlbumDetail {
        let song = try await song(id: trackID)
        guard let album = try await song.with([.albums]).albums?.first else {
            throw Failure.notFound
        }
        let full = try await album.with([.tracks])
        let year = album.releaseDate.map {
            String(Calendar(identifier: .gregorian).component(.year, from: $0))
        }
        return AlbumDetail(
            id: album.id.rawValue,
            title: album.title,
            artist: album.artistName,
            artworkURL: album.artwork?.url(width: 800, height: 800),
            releaseYear: year,
            genre: album.genreNames.first,
            tracks: (full.tracks ?? []).compactMap { item in
                guard case .song(let song) = item else { return nil }
                return Self.track(from: song)
            }
        )
    }

    // MARK: - Browse

    /// Shelves for the browse screen.
    ///
    /// Every fetch is independently optional. A shelf that fails to load is
    /// omitted rather than failing the screen — Apple Music requests can go
    /// wrong per-storefront and per-account in ways that should not leave the
    /// user staring at an error where a list of songs used to be.
    func shelves(seedArtists: [String], excluding excluded: Set<String> = []) async -> [MusicShelf] {
        async let charts = japaneseCharts()
        // The user's own history beats anything computed, and at the start it is
        // the only history there is: the app has none and the account has years.
        async let recent = recentlyPlayedShelf(excluding: excluded)
        // Three seeds keep this to a handful of requests while still reflecting
        // more than whatever song was played last.
        async let artists = artistShelves(for: Array(seedArtists.prefix(3)))

        var shelves: [MusicShelf] = []
        if let recent = await recent { shelves.append(recent) }
        if let charts = await charts { shelves.append(charts) }
        shelves.append(contentsOf: await artists)

        return shelves.compactMap { shelf in
            let filtered = shelf.tracks.filter { !excluded.contains($0.id) }
            guard !filtered.isEmpty else { return nil }
            return MusicShelf(
                id: shelf.id,
                title: shelf.title,
                subtitle: shelf.subtitle,
                tracks: filtered
            )
        }
    }

    /// Top J-Pop songs.
    ///
    /// Charts are storefront-scoped, so an unfiltered request returns the local
    /// top 40 — Korean pop, for this user. Constraining it to the J-Pop genre
    /// is what makes the shelf worth showing in a Japanese study app.
    private func japaneseCharts(limit: Int = 20) async -> MusicShelf? {
        guard Self.access == .authorized else { return nil }

        var request = MusicCatalogChartsRequest(
            genre: try? await Self.jpopGenre(),
            types: [Song.self]
        )
        request.limit = limit

        guard
            let response = try? await request.response(),
            let chart = response.songCharts.first
        else { return nil }

        let tracks = chart.items.map(Self.track(from:))
        guard !tracks.isEmpty else { return nil }
        return MusicShelf(
            id: "charts.jpop",
            title: "일본 인기곡",
            subtitle: "Apple Music J-Pop 차트",
            tracks: tracks
        )
    }

    /// Apple Music's J-Pop genre, looked up once per process.
    private static func jpopGenre() async throws -> Genre? {
        let request = MusicCatalogResourceRequest<Genre>(
            matching: \.id,
            equalTo: MusicItemID("27")
        )
        return try await request.response().items.first
    }

    /// More from the artists already in the user's library.
    ///
    /// Grounding recommendations in songs they chose to study beats a generic
    /// popularity feed: the vocabulary and register carry over from a song they
    /// already worked through.
    private func artistShelves(for names: [String]) async -> [MusicShelf] {
        guard Self.access == .authorized, !names.isEmpty else { return [] }

        var shelves: [MusicShelf] = []
        for name in names {
            guard let tracks = try? await topSongs(byArtist: name), !tracks.isEmpty else {
                continue
            }
            shelves.append(
                MusicShelf(
                    id: "artist.\(name)",
                    title: "\(name)의 다른 곡",
                    subtitle: "보관함에 있는 아티스트",
                    tracks: tracks
                )
            )
        }
        return shelves
    }

    func topSongs(byArtist name: String, limit: Int = 12) async throws -> [JustCore.Track] {
        var request = MusicCatalogSearchRequest(term: name, types: [Artist.self])
        request.limit = 1
        guard let artist = try await request.response().artists.first else { return [] }
        let detailed = try await artist.with([.topSongs])
        return Array((detailed.topSongs ?? []).prefix(limit)).map(Self.track(from:))
    }
}
