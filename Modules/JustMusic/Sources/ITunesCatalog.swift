import Foundation
import JustCore

/// What one group looks like and sings — its picture and its songs.
public struct ArtistPage: Sendable, Codable, Equatable {
    public let artworkURL: URL?
    public let songs: [Track]

    public init(artworkURL: URL?, songs: [Track]) {
        self.artworkURL = artworkURL
        self.songs = songs
    }
}

/// A song's playable clip, looked up when the video cannot be played.
public struct SongPreview: Sendable, Equatable {
    public let previewURL: URL?
    public let duration: TimeInterval
}

/// The song catalogue, from Apple's public iTunes lookup.
///
/// No account, no permission prompt, no key. The lookup service answers for
/// anyone, and its ids are the catalogue ids the app has always used — so
/// nothing the reader studied under the previous source is lost.
///
/// Playback is not this file's business: songs are played as YouTube videos
/// (`MusicPlayerController`), and the 30-second preview here is the fallback
/// for a song with no playable video.
public struct ITunesCatalog: Sendable {
    public enum Failure: LocalizedError, Equatable {
        case notFound
        case noPreview
        case transport(String)

        public var errorDescription: String? {
            switch self {
            case .notFound: "곡을 찾지 못했습니다."
            case .noPreview: "이 곡은 재생할 수 있는 영상을 찾지 못했습니다."
            case .transport(let message): message
            }
        }
    }

    private let session: URLSession
    /// The storefront. The roster is Japanese, and a song missing from another
    /// storefront is not missing from this one.
    private let country = "jp"

    public init(session: URLSession = ITunesCatalog.defaultSession) {
        self.session = session
    }

    /// Ten seconds per request, thirty for the whole transfer, rather than
    /// the default sixty — a lookup that slow is not going to answer.
    public static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    // MARK: - Artist

    /// The group's picture and songs.
    ///
    /// Two requests, because the lookup service knows the songs but has no
    /// picture of the artist. The picture is read off the artist's public
    /// artist page; when that fails the newest album cover stands in, so
    /// the card is never blank.
    ///
    /// Every song, not the newest forty: the lookup has no popularity to
    /// rank by, and a cap on a newest-first list dropped the group's biggest
    /// hit from three years ago while keeping this month's B-sides.
    public func artistPage(id artistID: String, limit: Int = 200) async throws -> ArtistPage {
        let songs = try await songs(forArtist: artistID, limit: limit)
        let portrait = await artistPortrait(id: artistID)
        return ArtistPage(artworkURL: portrait ?? songs.first?.artworkURL, songs: songs)
    }

    public func songs(forArtist artistID: String, limit: Int = 200) async throws -> [Track] {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            .init(name: "id", value: artistID),
            .init(name: "entity", value: "song"),
            .init(name: "country", value: country),
            .init(name: "limit", value: "200"),
        ]
        let payload = try await fetch(components.url!)
        let tracks = Self.tracks(from: payload, limit: limit)
        guard !tracks.isEmpty else { throw Failure.notFound }
        return tracks
    }

    /// The song's 30-second clip, by catalogue id.
    public func preview(forSong id: String) async throws -> SongPreview {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [.init(name: "id", value: id), .init(name: "country", value: country)]
        let payload = try await fetch(components.url!)
        guard let result = payload.results.first(where: { $0.wrapperType == "track" }) else {
            throw Failure.notFound
        }
        return SongPreview(
            previewURL: result.previewUrl.flatMap(URL.init(string:)),
            duration: TimeInterval(result.trackTimeMillis ?? 0) / 1000
        )
    }

    /// The artist's picture, from the `og:image` of their public page.
    ///
    /// Apple publishes it as a wide banner; the same image service serves a
    /// square when asked, which is what the cards want.
    func artistPortrait(id artistID: String) async -> URL? {
        guard let url = URL(string: "https://music.apple.com/\(country)/artist/\(artistID)"),
              let (data, _) = try? await session.data(from: url),
              let html = String(data: data, encoding: .utf8)
        else { return nil }
        return Self.portraitURL(inPage: html)
    }

    static func portraitURL(inPage html: String) -> URL? {
        guard let range = html.range(of: #"property="og:image"\s+content="([^"]+)""#, options: .regularExpression) else {
            return nil
        }
        let tag = String(html[range])
        guard let start = tag.range(of: "content=\""), let end = tag[start.upperBound...].firstIndex(of: "\"") else {
            return nil
        }
        var address = String(tag[start.upperBound..<end])
        // 「1200x630cw」 is Apple Music's share card — the portrait as a circle
        // on a blurred banner, not the photo. 「800x800cc」 is the photo itself,
        // cropped square. Some groups uploaded photos with black bars baked
        // in; `ArtworkLoader` trims those when asked.
        address = address.replacingOccurrences(
            of: #"\d+x\d+[a-z]{2}(?=\.\w+$)"#, with: "800x800cc", options: .regularExpression
        )
        return URL(string: address)
    }

    // MARK: - Decoding

    struct Payload: Decodable {
        let results: [Result]
    }

    struct Result: Decodable {
        let wrapperType: String?
        let kind: String?
        let trackId: Int?
        let trackName: String?
        let artistName: String?
        let collectionName: String?
        let artworkUrl100: String?
        let trackTimeMillis: Int?
        let previewUrl: String?
        let releaseDate: String?
    }

    private func fetch(_ url: URL) async throws -> Payload {
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                switch http.statusCode {
                case 403:
                    throw Failure.transport("곡 정보 요청이 너무 잦습니다. 잠시 뒤에 다시 시도해 주세요.")
                case 400, 404:
                    // The catalog does not know the id. A status code means
                    // nothing to the reader; "not found" is what it says.
                    throw Failure.notFound
                default:
                    throw Failure.transport("곡 정보를 받지 못했습니다. 잠시 뒤에 다시 시도해 주세요.")
                }
            }
            return try JSONDecoder().decode(Payload.self, from: data)
        } catch let failure as Failure {
            throw failure
        } catch let error where error.isCancellation {
            // Not a network failure: whoever asked no longer wants the answer,
            // and must be able to tell that apart from being offline.
            throw error
        } catch {
            throw Failure.transport("곡 정보를 받지 못했습니다. 인터넷 연결을 확인해 주세요.")
        }
    }

    /// The songs worth listing, newest first.
    ///
    /// The lookup returns every recording — the instrumental, the off-vocal,
    /// the same single on three albums, the tour recording, the Korean
    /// version. One row per song, and none that cannot be studied: nobody
    /// sings on an instrumental, and a Korean version is not Japanese.
    ///
    /// Of a song's recordings the studio one is listed, and of those the
    /// newest — a 「(2024 ver.)」 re-recording is the one fans hear now. Taking
    /// the newest of *everything* used to put a group's latest tour album on
    /// top of every song it played: =LOVE's page opened on six live takes.
    static func tracks(from payload: Payload, limit: Int) -> [Track] {
        let songs = payload.results.filter {
            guard $0.wrapperType == "track", $0.kind == "song", let title = $0.trackName else { return false }
            return !isUnsingable(title) && !isOtherLanguage(title)
        }
        // Per song, the recording to list.
        var chosen: [String: Result] = [:]
        for song in songs {
            guard song.trackId != nil, let title = song.trackName else { continue }
            let key = normalized(title)
            guard let current = chosen[key] else { chosen[key] = song; continue }
            if isPreferred(song, over: current) { chosen[key] = song }
        }
        return chosen.values
            .sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
            .prefix(limit)
            .compactMap { song in
                guard let id = song.trackId, let title = song.trackName else { return nil }
                return Track(
                    id: String(id),
                    title: title,
                    artist: song.artistName ?? "",
                    album: song.collectionName,
                    artworkURL: song.artworkUrl100.map(Self.largeArtwork).flatMap(URL.init(string:)),
                    duration: TimeInterval(song.trackTimeMillis ?? 0) / 1000
                )
            }
    }

    /// Studio before remix before live; among equals, the newer release.
    private static func isPreferred(_ candidate: Result, over current: Result) -> Bool {
        let a = variantRank(candidate), b = variantRank(current)
        if a != b { return a < b }
        return (candidate.releaseDate ?? "") > (current.releaseDate ?? "")
    }

    /// 0 for a studio recording, 1 for a remix or cut-down edit, 2 for a
    /// concert recording. Read from the album name too: a tour album's tracks
    /// often carry the tour in the album and nothing in the title.
    static func variantRank(_ song: Result) -> Int {
        let text = [song.trackName, song.collectionName].compactMap { $0 }.joined(separator: " ").lowercased()
        let live = ["live", "tour", "concert", "ライブ", "ツアー", "コンサート", "武道館", "budokan", "arena", "dome"]
        if live.contains(where: text.contains) { return 2 }
        let edits = ["remix", " mix", "acoustic", "tv size", "tv ver", "short ver", "piano ver", "orchestra", "a cappella", "アコースティック"]
        if edits.contains(where: text.contains) { return 1 }
        return 0
    }

    /// A version sung in another language — a Korean or English release of a
    /// Japanese song. Nothing in it to study as Japanese.
    static func isOtherLanguage(_ title: String) -> Bool {
        let lowered = title.lowercased()
        return [
            "korean ver", "korean version", "english ver", "english version",
            "chinese ver", "chinese version", "thai ver", "韓国語", "英語ver", "中国語",
        ].contains { lowered.contains($0) }
    }

    /// Recordings with no vocal — nothing to study in them.
    static func isUnsingable(_ title: String) -> Bool {
        let lowered = title.lowercased()
        return ["instrumental", "inst.", "off vocal", "オフボーカル", "カラオケ", "karaoke", "backing track"]
            .contains { lowered.contains($0) }
    }

    /// The same song across releases, ignoring the bits that differ per release.
    static func normalized(_ title: String) -> String {
        var key = title.lowercased()
        // 「(2024 ver.)」 「-Single Version-」 「[Live]」 and their kin.
        for pattern in [#"\s*[\(\[（【][^\)\]）】]*[\)\]）】]"#, #"\s*[-−–—]\s*[^-−–—]*(ver|version|mix|edit|live)[^-−–—]*$"#] {
            key = key.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return key.replacingOccurrences(of: #"[\s!！?？・・.,、。]"#, with: "", options: .regularExpression)
    }

    /// The lookup hands out 100pt covers. The same service serves any size.
    static func largeArtwork(_ address: String) -> String {
        address.replacingOccurrences(of: "100x100bb", with: "600x600bb")
    }
}
