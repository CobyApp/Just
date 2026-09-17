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
/// No account, no permission prompt, no key. The previous source was MusicKit,
/// which asked every reader to allow Apple Music access on first launch and
/// then failed in ways that looked like a group having no songs when the
/// device had no Apple account. The lookup service answers for anyone, and it
/// uses the same catalogue ids — so a song saved under MusicKit is the same
/// song here, and nothing the reader studied is lost.
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
            case .noPreview: "이 곡은 영상도 미리듣기도 찾지 못했습니다."
            case .transport(let message): message
            }
        }
    }

    private let session: URLSession
    /// The storefront. The roster is Japanese, and a song missing from another
    /// storefront is not missing from this one.
    private let country = "jp"

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Artist

    /// The group's picture and songs.
    ///
    /// Two requests, because the lookup service knows the songs but has no
    /// picture of the artist. The picture is read off the artist's public
    /// Apple Music page; when that fails the newest album cover stands in, so
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
        // 「1200x630cw」 is the banner; 「800x800cc」 is the same picture cropped
        // square from the centre.
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
                throw Failure.transport(
                    http.statusCode == 403
                        ? "곡 정보 요청이 너무 잦습니다. 잠시 뒤에 다시 시도해 주세요."
                        : "곡 정보를 받지 못했습니다 (\(http.statusCode)). 잠시 뒤에 다시 시도해 주세요."
                )
            }
            return try JSONDecoder().decode(Payload.self, from: data)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.transport("곡 정보를 받지 못했습니다. 인터넷 연결을 확인해 주세요.")
        }
    }

    /// The songs worth listing, newest first.
    ///
    /// The lookup returns every recording — the instrumental, the off-vocal,
    /// the same single on three albums. One row per song, and none that cannot
    /// be studied because nobody sings on it.
    static func tracks(from payload: Payload, limit: Int) -> [Track] {
        let songs = payload.results.filter { $0.wrapperType == "track" && $0.kind == "song" }
        let sorted = songs.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
        var seen: Set<String> = []
        var tracks: [Track] = []
        for song in sorted {
            guard let id = song.trackId, let title = song.trackName, !isUnsingable(title) else { continue }
            let key = normalized(title)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            tracks.append(Track(
                id: String(id),
                title: title,
                artist: song.artistName ?? "",
                album: song.collectionName,
                artworkURL: song.artworkUrl100.map(Self.largeArtwork).flatMap(URL.init(string:)),
                duration: TimeInterval(song.trackTimeMillis ?? 0) / 1000
            ))
            if tracks.count == limit { break }
        }
        return tracks
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
