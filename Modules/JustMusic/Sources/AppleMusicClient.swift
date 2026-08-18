import Foundation
import JustCore
import MusicKit

/// Catalog search and lookup through MusicKit.
///
/// No API key is involved anywhere in this file, and that is the point: for a
/// native app, MusicKit mints its own developer token from the MusicKit
/// service enabled on the App ID. There is nothing for the user to paste and
/// no daily quota to run out of.
///
/// What MusicKit does *not* provide is lyrics — the Music app's lyrics are not
/// exposed through any public API — so `JustLyrics` still fetches them from
/// LRCLIB.
public struct AppleMusicClient: Sendable {
    public enum Failure: LocalizedError {
        case notAuthorized
        case noSubscription
        case notFound
        case noPreview
        case transport(String)

        public var errorDescription: String? {
            switch self {
            case .notAuthorized:
                "Apple Music 접근이 허용되지 않았습니다. 설정 > 개인정보 보호 > 미디어 및 Apple Music에서 Just를 켜 주세요."
            case .noSubscription:
                "이 곡을 재생하려면 Apple Music 구독이 필요합니다."
            case .notFound:
                "곡을 찾지 못했습니다."
            case .noPreview:
                "이 곡은 미리듣기도 제공되지 않습니다. 전곡 재생에는 Apple Music 구독이 필요합니다."
            case .transport(let message):
                message
            }
        }
    }

    /// Authorization state, re-declared so the app layer never has to import
    /// MusicKit just to render a settings row.
    public enum Access: Sendable {
        case notDetermined
        case denied
        case restricted
        case authorized

        init(_ status: MusicAuthorization.Status) {
            switch status {
            case .authorized: self = .authorized
            case .denied: self = .denied
            case .restricted: self = .restricted
            case .notDetermined: self = .notDetermined
            @unknown default: self = .notDetermined
            }
        }

        public var label: String {
            switch self {
            case .authorized: "허용됨"
            case .denied: "거부됨"
            case .restricted: "제한됨"
            case .notDetermined: "미설정"
            }
        }
    }

    public init() {}

    // MARK: - Authorization

    public static var access: Access {
        Access(MusicAuthorization.currentStatus)
    }

    @discardableResult
    public static func requestAccess() async -> Access {
        Access(await MusicAuthorization.request())
    }

    /// Whether the signed-in account can play full songs rather than previews.
    public static func canPlayFullTracks() async -> Bool {
        guard let subscription = try? await MusicSubscription.current else { return false }
        return subscription.canPlayCatalogContent
    }

    // MARK: - Search

    public func search(_ term: String, limit: Int = 25) async throws -> [JustCore.Track] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard MusicAuthorization.currentStatus == .authorized else {
            throw Failure.notAuthorized
        }

        var request = MusicCatalogSearchRequest(term: trimmed, types: [Song.self])
        request.limit = limit

        do {
            let response = try await request.response()
            return response.songs.map(Self.track(from:))
        } catch {
            throw Failure.transport(error.localizedDescription)
        }
    }

    /// Re-fetches a song by catalog id.
    ///
    /// Needed because `JustCore.Track` is a plain value type stored in SwiftData — it
    /// cannot hold a MusicKit `Song` — so playback resolves the catalog item
    /// again when a saved song is reopened.
    public func song(id: String) async throws -> Song {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw Failure.notAuthorized
        }
        let request = MusicCatalogResourceRequest<Song>(
            matching: \.id,
            equalTo: MusicItemID(id)
        )
        do {
            guard let song = try await request.response().items.first else {
                throw Failure.notFound
            }
            return song
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.transport(error.localizedDescription)
        }
    }

    /// The other songs on the same album — the album context the catalog gives
    /// us for free and YouTube never could.
    public func albumTracks(for song: Song) async throws -> [JustCore.Track] {
        do {
            let detailed = try await song.with([.albums])
            guard let album = detailed.albums?.first else { return [] }
            let full = try await album.with([.tracks])
            return (full.tracks ?? []).compactMap { item in
                guard case .song(let song) = item else { return nil }
                return Self.track(from: song)
            }
        } catch {
            throw Failure.transport(error.localizedDescription)
        }
    }

    static func track(from song: Song) -> JustCore.Track {
        JustCore.Track(
            id: song.id.rawValue,
            title: song.title,
            artist: song.artistName,
            album: song.albumTitle,
            // 600pt covers the largest artwork the app displays on iPad.
            artworkURL: song.artwork?.url(width: 600, height: 600),
            duration: song.duration ?? 0
        )
    }
}
