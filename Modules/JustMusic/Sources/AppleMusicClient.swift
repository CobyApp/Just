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
        /// MusicKit refused to mint a developer token.
        case developerTokenUnavailable
        case notSignedIn
        /// Apple Music refused the request and did not say which of the two
        /// reasons it was.
        case catalogRefused
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
            case .developerTokenUnavailable:
                "Apple Music 개발자 토큰을 받지 못했습니다. App ID에 MusicKit 서비스가 켜져 있어야 합니다 — developer.apple.com > Identifiers에서 com.coby.just를 명시적 App ID로 만들고 MusicKit을 켠 뒤 다시 빌드해 주세요."
            case .notSignedIn:
                "기기에 Apple Music 계정이 로그인되어 있지 않습니다. 설정 > Apple 계정에서 로그인해 주세요."
            case .catalogRefused:
                """
                Apple Music이 요청을 거절했습니다. 두 가지 중 하나입니다.

                1. 설정 > 개인정보 보호 및 보안 > 미디어 및 Apple Music에서 Just가 켜져 있는지
                2. 설정 > Apple 계정에 Apple Music을 쓰는 계정으로 로그인되어 있는지

                거절만으로는 둘 중 어느 쪽인지 알 수 없어 둘 다 적었습니다.
                """
            case .transport(let message):
                message
            }
        }

        /// True when the error carries no specific diagnosis, so a caller with
        /// more context is free to offer a better one.
        var isGeneric: Bool {
            if case .transport = self { return true }
            return false
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

    /// Translates MusicKit's own errors into something actionable.
    ///
    /// The failure that matters here is the developer token: MusicKit mints one
    /// automatically, but only for an *explicit* App ID with the MusicKit
    /// service enabled. Signed with a wildcard team profile it fails, and the
    /// raw error says nothing about the portal switch that fixes it — which is
    /// a long detour to discover from a build that otherwise looks fine.
    static func failure(from error: Error) -> Failure {
        if let failure = error as? Failure { return failure }

        if let tokenError = error as? MusicTokenRequestError {
            switch tokenError {
            case .developerTokenRequestFailed:
                return .developerTokenUnavailable
            case .userNotSignedIn:
                return .notSignedIn
            case .permissionDenied, .privacyAcknowledgementRequired:
                return .notAuthorized
            default:
                return .transport(error.localizedDescription)
            }
        }

        // A failed catalog request carries a diagnosis and does not print it.
        // 「MusicKit.MusicDataRequest.Error 1」 is what the reader saw, which
        // names nothing they can act on — while the error itself holds the HTTP
        // status, Apple's own title, and a sentence of detail.
        if let request = error as? MusicDataRequest.Error {
            switch request.status {
            case 401, 403:
                // Refused rather than broken — but the status does not say
                // whether the app was never granted access to Media & Apple
                // Music, or the device is not signed in to an account that can
                // reach the catalog. Naming one would send half the readers to
                // the wrong screen, so the message names both.
                return .catalogRefused
            case 404:
                return .notFound
            case 429:
                return .transport("Apple Music 요청이 너무 잦습니다. 잠시 뒤에 다시 시도해 주세요.")
            case 500...599:
                return .transport("Apple Music 서버가 응답하지 않습니다 (\(request.status)). 잠시 뒤에 다시 시도해 주세요.")
            default:
                let detail = request.detailText.isEmpty ? request.title : request.detailText
                return .transport("Apple Music 요청이 실패했습니다 (\(request.status)/\(request.code)). \(detail)")
            }
        }

        // Not every path surfaces a typed error; the description still carries
        // the token failure when MusicKit wraps it.
        let description = error.localizedDescription
        if description.localizedCaseInsensitiveContains("developer token") {
            return .developerTokenUnavailable
        }
        return .transport(description)
    }

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

    /// Every song this app knows for one group.
    ///
    /// The roster is the app's whole catalogue, so this is what search used to
    /// be. Asked by artist id rather than by name: a name lookup hands the
    /// group's entire catalogue to whoever matches better that day, and the
    /// failure looks like the group having no songs.
    ///
    /// Top songs rather than every release. A group with six years of singles
    /// has more B-sides than anyone will study, and the ones worth opening are
    /// the ones people know.
    /// What one group looks like and sings — its picture and its songs, from a
    /// single artist request.
    public struct ArtistPage: Sendable {
        public let artworkURL: URL?
        public let songs: [JustCore.Track]
    }

    /// The artist's own artwork, for the group card.
    ///
    /// Comes with the songs because it is the same request: the card and the
    /// detail screen want different halves of one `Artist`, and asking twice
    /// would fetch it twice.
    public func artistPage(id artistID: String, limit: Int = 40) async throws -> ArtistPage {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw Failure.notAuthorized
        }
        var request = MusicCatalogResourceRequest<Artist>(
            matching: \.id,
            equalTo: MusicItemID(artistID)
        )
        request.properties = [.topSongs]
        do {
            guard let artist = try await request.response().items.first else {
                throw Failure.notFound
            }
            return ArtistPage(
                // 800pt: the card is half the screen wide on iPad and the image
                // is cropped to a wide aspect, so it needs more than the tiles.
                artworkURL: artist.artwork?.url(width: 800, height: 800),
                songs: (artist.topSongs ?? []).prefix(limit).map(Self.track(from:))
            )
        } catch {
            throw Self.failure(from: error)
        }
    }

    public func songs(forArtist artistID: String, limit: Int = 40) async throws -> [JustCore.Track] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw Failure.notAuthorized
        }

        var request = MusicCatalogResourceRequest<Artist>(
            matching: \.id,
            equalTo: MusicItemID(artistID)
        )
        request.properties = [.topSongs]

        do {
            guard let artist = try await request.response().items.first else {
                throw Failure.notFound
            }
            let songs = artist.topSongs ?? []
            return songs.prefix(limit).map(Self.track(from:))
        } catch {
            throw Self.failure(from: error)
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
        } catch {
            throw Self.failure(from: error)
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
