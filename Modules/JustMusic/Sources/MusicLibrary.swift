import Foundation
import JustCore
@preconcurrency import MusicKit

/// One of the user's own playlists.
public struct MusicPlaylist: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let artworkURL: URL?
    /// nil when the catalog did not report a count, which library playlists
    /// often do not until their tracks are loaded.
    public let trackCount: Int?

    public init(id: String, name: String, artworkURL: URL?, trackCount: Int?) {
        self.id = id
        self.name = name
        self.artworkURL = artworkURL
        self.trackCount = trackCount
    }
}

public extension AppleMusicClient {
    // MARK: - The user's own library

    /// The playlists in the user's library.
    ///
    /// The same authorization that allows catalog search covers this, so it
    /// costs the user nothing extra — and it is a far better starting point than
    /// a search box: someone studying with J-pop already keeps the songs they
    /// care about in a playlist, and typing them in one at a time is work they
    /// have already done once.
    func libraryPlaylists(limit: Int = 40) async throws -> [MusicPlaylist] {
        guard Self.access == .authorized else { throw Failure.notAuthorized }

        var request = MusicLibraryRequest<Playlist>()
        request.limit = limit
        do {
            let response = try await request.response()
            return response.items.map { playlist in
                MusicPlaylist(
                    id: playlist.id.rawValue,
                    name: playlist.name,
                    artworkURL: playlist.artwork?.url(width: 600, height: 600),
                    trackCount: playlist.tracks?.count
                )
            }
        } catch {
            throw Self.failure(from: error)
        }
    }

    /// The songs on one playlist.
    ///
    /// Video tracks are dropped rather than shown and then failing to open: a
    /// playlist can hold music videos, and this app has nothing to do with one.
    func tracks(inPlaylist playlistID: String, limit: Int = 100) async throws -> [JustCore.Track] {
        guard Self.access == .authorized else { throw Failure.notAuthorized }

        var request = MusicLibraryRequest<Playlist>()
        request.filter(matching: \.id, equalTo: MusicItemID(playlistID))
        do {
            guard let playlist = try await request.response().items.first else {
                throw Failure.notFound
            }
            let detailed = try await playlist.with([.tracks])
            return Array((detailed.tracks ?? []).prefix(limit)).compactMap { item in
                guard case .song(let song) = item else { return nil }
                return Self.track(from: song)
            }
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Self.failure(from: error)
        }
    }

    /// Songs the user played recently, in Apple Music rather than in this app.
    ///
    /// A better seed than the app's own history at the start, when the app has
    /// no history and the user has years of one.
    func recentlyPlayed(limit: Int = 20) async throws -> [JustCore.Track] {
        guard Self.access == .authorized else { throw Failure.notAuthorized }

        var request = MusicRecentlyPlayedRequest<Song>()
        request.limit = limit
        do {
            return try await request.response().items.map(Self.track(from:))
        } catch {
            throw Self.failure(from: error)
        }
    }

    /// A shelf of songs the user played recently, or nil when there are none.
    ///
    /// Optional like the other shelves: a fresh account has no history, and an
    /// empty row is worse than an absent one.
    func recentlyPlayedShelf(excluding excluded: Set<String> = []) async -> MusicShelf? {
        guard let tracks = try? await recentlyPlayed() else { return nil }
        let filtered = tracks.filter { !excluded.contains($0.id) }
        guard !filtered.isEmpty else { return nil }
        return MusicShelf(
            id: "library.recentlyPlayed",
            title: "최근 들은 곡",
            subtitle: "Apple Music에서 재생한 곡",
            tracks: filtered
        )
    }
}
