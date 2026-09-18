import Foundation
import JustCore

/// Finds the video for a song.
///
/// One search per song, the first time it is opened, and the answer is kept
/// on disk — the Data API's free quota is about a hundred searches a day, and
/// a reader who opens the same song twice should cost one.
public struct YouTubeClient: Sendable {
    public enum Failure: LocalizedError, Equatable {
        /// No key was built into the app, so no search can be made.
        case noKey
        case notFound
        case quotaExceeded
        case transport(String)

        public var errorDescription: String? {
            switch self {
            case .noKey: "영상을 찾을 수 없어 짧은 클립으로 재생합니다."
            case .notFound: "이 곡의 영상을 찾지 못했습니다."
            case .quotaExceeded: "오늘은 새 영상을 더 찾을 수 없습니다. 내일 다시 시도해 주세요."
            case .transport(let message): message
            }
        }
    }

    public struct Candidate: Sendable, Equatable, Codable {
        public let videoID: String
        public let title: String
        public let channelTitle: String
        public let channelID: String

        public init(videoID: String, title: String, channelTitle: String, channelID: String = "") {
            self.videoID = videoID
            self.title = title
            self.channelTitle = channelTitle
            self.channelID = channelID
        }
    }

    /// Read from the app's Info.plist, where Tuist writes the
    /// `TUIST_YOUTUBE_API_KEY` environment variable at generation. Empty when
    /// the app was generated without one.
    public static var configuredKey: String? {
        let key = Bundle.main.object(forInfoDictionaryKey: "YouTubeAPIKey") as? String
        return key.flatMap { $0.isEmpty ? nil : $0 }
    }

    private let key: String?
    private let session: URLSession

    public init(key: String? = YouTubeClient.configuredKey, session: URLSession = .shared) {
        self.key = key
        self.session = session
    }

    /// The videos for a song, best first — the official music video when
    /// there is one, then anything else on YouTube that is this song.
    ///
    /// Two searches at most. The first asks for the MV; when nothing in it
    /// names the song, the second drops 「MV」 and accepts the label's
    /// auto-generated audio track (the 「Topic」 channels), a lyric video, a
    /// live take — a whole song from YouTube before a 30-second clip from
    /// anywhere else.
    public func videos(for track: Track, channels: [String] = []) async throws -> [Candidate] {
        guard let key else { throw Failure.noKey }
        var ranked = Self.rank(try await search(Self.query(for: track), key: key), for: track, channels: channels, strict: true)
        if ranked.isEmpty {
            ranked = Self.rank(try await search(Self.plainQuery(for: track), key: key), for: track, channels: channels, strict: false)
        }
        guard !ranked.isEmpty else { throw Failure.notFound }
        return ranked
    }

    // MARK: - Durations

    /// How long each video is, by id. One unit per fifty.
    ///
    /// Titles lie about what a video is — a Short announcing the MV is called
    /// 「MV公開」 — but a length does not: the song's video is about as long as
    /// the song.
    public func durations(of videoIDs: [String]) async throws -> [String: TimeInterval] {
        guard let key else { throw Failure.noKey }
        var found: [String: TimeInterval] = [:]
        for chunk in stride(from: 0, to: videoIDs.count, by: 50).map({ Array(videoIDs[$0..<min($0 + 50, videoIDs.count)]) }) {
            var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
            components.queryItems = [
                .init(name: "part", value: "contentDetails"),
                .init(name: "id", value: chunk.joined(separator: ",")),
                .init(name: "key", value: key),
            ]
            let (data, response) = try await send(components.url!)
            try Self.check(response, data: data)
            for (id, seconds) in try Self.durations(from: data) { found[id] = seconds }
        }
        return found
    }

    /// Keeps the videos that are about as long as the song — from a little
    /// shorter (a radio edit) to half again as long (an MV with a prologue).
    /// Videos the lengths do not cover are kept: not knowing is not a reason
    /// to drop the group's own upload.
    public static func aboutTheSongsLength(_ candidates: [Candidate], track: Track, durations: [String: TimeInterval]) -> [Candidate] {
        guard track.duration > 0 else { return candidates }
        return candidates.filter { candidate in
            guard let seconds = durations[candidate.videoID] else { return true }
            return seconds >= track.duration * 0.6 && seconds <= track.duration * 1.6
        }
    }

    private struct DurationsPayload: Decodable {
        struct Item: Decodable {
            struct Details: Decodable { let duration: String }
            let id: String
            let contentDetails: Details
        }
        let items: [Item]
    }

    static func durations(from data: Data) throws -> [String: TimeInterval] {
        let payload = try JSONDecoder().decode(DurationsPayload.self, from: data)
        return Dictionary(uniqueKeysWithValues: payload.items.compactMap { item in
            parseDuration(item.contentDetails.duration).map { (item.id, $0) }
        })
    }

    /// 「PT3M28S」 → 208. Hours appear on concert films.
    static func parseDuration(_ iso: String) -> TimeInterval? {
        guard iso.hasPrefix("PT") else { return nil }
        var total: TimeInterval = 0
        var number = ""
        for character in iso.dropFirst(2) {
            if character.isNumber { number.append(character); continue }
            guard let value = Double(number) else { return nil }
            number = ""
            switch character {
            case "H": total += value * 3600
            case "M": total += value * 60
            case "S": total += value
            default: return nil
            }
        }
        return total
    }

    // MARK: - A channel's uploads

    /// Everything a channel has published, newest first — up to `limit`.
    ///
    /// One unit per fifty videos, against a hundred for a search. The
    /// group's own channels hold its music videos, so most songs are found
    /// here without searching at all, and the list is kept on the device.
    public func uploads(ofChannel channelID: String, limit: Int = 200) async throws -> [Candidate] {
        guard let key else { throw Failure.noKey }
        var found: [Candidate] = []
        var page: String?
        repeat {
            var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/playlistItems")!
            components.queryItems = [
                .init(name: "part", value: "snippet"),
                .init(name: "playlistId", value: Self.uploadsPlaylist(ofChannel: channelID)),
                .init(name: "maxResults", value: "50"),
                .init(name: "key", value: key),
            ] + (page.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
            let (data, response) = try await send(components.url!)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                // A channel with no uploads playlist (some Topic channels).
                return found
            }
            try Self.check(response, data: data)
            let (items, next) = try Self.playlistItems(from: data, channelID: channelID)
            found += items
            page = next
        } while page != nil && found.count < limit
        return Array(found.prefix(limit))
    }

    /// A channel's uploads playlist has the channel's id with 「UU」 in place
    /// of 「UC」 — a documented convention, and one request fewer.
    static func uploadsPlaylist(ofChannel channelID: String) -> String {
        channelID.hasPrefix("UC") ? "UU" + channelID.dropFirst(2) : channelID
    }

    private func send(_ url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        // A key restricted to this iOS app is checked against this header;
        // without it Google answers 403 as if the quota were gone.
        if let bundleID = Bundle.main.bundleIdentifier {
            request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        return try await session.data(for: request)
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 403 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw body.contains("quota") ? Failure.quotaExceeded : Failure.transport("영상 검색이 거절되었습니다. 앱 설정의 YouTube 키를 확인해 주세요.")
        }
        if !(200..<300).contains(http.statusCode) {
            throw Failure.transport("영상을 찾지 못했습니다 (\(http.statusCode)). 잠시 뒤에 다시 시도해 주세요.")
        }
    }

    /// The best video for a song.
    public func videoID(for track: Track) async throws -> String {
        try await videos(for: track)[0].videoID
    }

    private func search(_ query: String, key: String) async throws -> [Candidate] {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        components.queryItems = [
            .init(name: "part", value: "snippet"),
            .init(name: "type", value: "video"),
            .init(name: "videoCategoryId", value: "10"),
            .init(name: "videoEmbeddable", value: "true"),
            .init(name: "maxResults", value: "10"),
            .init(name: "regionCode", value: "JP"),
            .init(name: "relevanceLanguage", value: "ja"),
            .init(name: "q", value: query),
            .init(name: "key", value: key),
        ]
        let (data, response) = try await send(components.url!)
        try Self.check(response, data: data)
        return try Self.candidates(from: data)
    }

    static func query(for track: Track) -> String {
        "\(track.artist) \(track.title) MV"
    }

    static func plainQuery(for track: Track) -> String {
        "\(track.artist) \(track.title)"
    }

    // MARK: - Choosing

    /// The result that is most likely this song's official video.
    public static func choose(_ candidates: [Candidate], for track: Track, channels: [String] = []) -> Candidate? {
        rank(candidates, for: track, channels: channels, strict: true).first
    }

    /// Every result that is this song, best first.
    ///
    /// Search relevance alone picks dance-practice videos, fan uploads and
    /// live clips. The song's title has to be in the video's title; then the
    /// official music video outranks the rest, the group's own channel and
    /// the label's auto-generated 「Topic」 track outrank strangers, and the
    /// videos that are not the song — practice, teasers, reactions — sink.
    ///
    /// - Parameter strict: true keeps only videos that read as the song
    ///   itself; false also admits the takes a strict pass would drop (live,
    ///   lyric videos), for when the strict pass found nothing at all.
    public static func rank(_ candidates: [Candidate], for track: Track, channels: [String] = [], strict: Bool) -> [Candidate] {
        let wantedTitle = fold(track.title)
        let wantedArtist = fold(track.artist)
        let scored: [(Candidate, Int)] = candidates.compactMap { candidate in
            let title = fold(candidate.title)
            let channel = fold(candidate.channelTitle)
            guard title.contains(wantedTitle) else { return nil }
            // Nothing to study in an instrumental.
            if title.contains("instrumental") || title.contains("inst.") || title.contains("offvocal") { return nil }
            var score = 1
            // The group's own channel: this is the video, whatever it is called.
            if channels.contains(candidate.channelID) { score += 8 }
            if title.contains("mv") || title.contains("musicvideo") || title.contains("ミュージックビデオ") { score += 4 }
            // Tagged as the video itself, not a clip that mentions the MV.
            if title.contains("【mv】") || title.contains("[mv]") || title.contains("(mv)") { score += 2 }
            // Announcements and clips: 「MV公開」, 「MVティザー公開」, TV debuts,
            // collaborations, hashtag-titled Shorts.
            for clip in ["公開", "期間限定", "初披露", "コラボ", "聴いてくれた", "ありがとう"] where title.contains(clip) {
                score -= 5
            }
            if candidate.title.filter({ $0 == "#" }).count >= 2 { score -= 4 }
            if title.contains("official") || title.contains("公式") { score += 1 }
            if channel.contains(wantedArtist) || channel.contains("official") { score += 3 }
            // The labels behind the roster. Their uploads are the official
            // videos even when the channel is not named after the group.
            if ["kawaiilab", "代々木アニメーション", "equallove", "イコールラブ", "ilife"].contains(where: channel.contains) { score += 3 }
            // The label's auto-generated audio: the whole song, static art.
            if channel.hasSuffix("topic") { score += 2 }
            // A re-upload with burnt-in subtitles is somebody else's copy of
            // the video, and it outranked the original on 「MV」 alone.
            for copy in ["자막", "한글", "sub", "字幕", "번역", "翻訳", "kansub", "eng"] where title.contains(copy) || channel.contains(copy) {
                score -= 4
            }
            for bad in ["dancepractice", "ダンスプラクティス", "cover", "カバー", "踊ってみた", "歌ってみた", "teaser", "ティザー", "makingof", "メイキング", "reaction", "short", "focus", "フォーカス"] where title.contains(bad) {
                score -= 3
            }
            for soft in ["live", "ライブ", "lyric", "リリック"] where title.contains(soft) {
                score -= strict ? 3 : 1
            }
            return (candidate, score)
        }
        return scored
            .filter { strict ? $0.1 > 0 : true }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// Lowercased, no spaces or punctuation, so 「わたしの一番かわいいところ / FRUITS ZIPPER」
    /// and 「FRUITS ZIPPER「わたしの一番かわいいところ」MV」 agree about the title.
    static func fold(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: #"[\s\p{P}\p{S}]"#, with: "", options: .regularExpression)
    }

    // MARK: - Decoding

    private struct Payload: Decodable {
        struct Item: Decodable {
            struct ID: Decodable { let videoId: String? }
            struct Snippet: Decodable { let title: String; let channelTitle: String; let channelId: String? }
            let id: ID
            let snippet: Snippet
        }
        let items: [Item]
    }

    static func candidates(from data: Data) throws -> [Candidate] {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return payload.items.compactMap { item in
            guard let id = item.id.videoId else { return nil }
            return Candidate(videoID: id, title: Self.unescaped(item.snippet.title), channelTitle: item.snippet.channelTitle, channelID: item.snippet.channelId ?? "")
        }
    }

    private struct PlaylistPayload: Decodable {
        struct Item: Decodable {
            struct Snippet: Decodable {
                struct Resource: Decodable { let videoId: String? }
                let title: String
                let channelTitle: String?
                let resourceId: Resource
            }
            let snippet: Snippet
        }
        let items: [Item]
        let nextPageToken: String?
    }

    static func playlistItems(from data: Data, channelID: String) throws -> ([Candidate], String?) {
        let payload = try JSONDecoder().decode(PlaylistPayload.self, from: data)
        let items = payload.items.compactMap { item -> Candidate? in
            guard let id = item.snippet.resourceId.videoId, item.snippet.title != "Private video", item.snippet.title != "Deleted video" else { return nil }
            return Candidate(videoID: id, title: Self.unescaped(item.snippet.title), channelTitle: item.snippet.channelTitle ?? "", channelID: channelID)
        }
        return (items, payload.nextPageToken)
    }

    /// Titles come HTML-escaped (`&#39;`, `&amp;`, `&quot;`).
    static func unescaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

/// Which video plays which song, kept between launches.
///
/// In Caches, like the group pages: it can always be searched for again, and
/// it stays out of backups. A song with no video is remembered too, so a
/// song that has none is not searched for on every open.
public struct VideoDirectory: Sendable {
    public struct Snapshot: Codable, Equatable {
        /// Video id by song id; an empty string means 「searched, none found」.
        public var videos: [String: String] = [:]
        /// The other videos the search found, by song id, in order. When the
        /// chosen one refuses to play the next is tried before the clip is.
        public var alternates: [String: [String]] = [:]
        /// What each of the groups' channels has published, by channel id.
        /// Refreshed after a day, so a new single's video is there the week
        /// it comes out.
        public var channels: [String: ChannelUploads] = [:]

        public init(videos: [String: String] = [:], alternates: [String: [String]] = [:], channels: [String: ChannelUploads] = [:]) {
            self.videos = videos
            self.alternates = alternates
            self.channels = channels
        }

        // Older files have fewer fields.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            videos = try c.decodeIfPresent([String: String].self, forKey: .videos) ?? [:]
            alternates = try c.decodeIfPresent([String: [String]].self, forKey: .alternates) ?? [:]
            channels = try c.decodeIfPresent([String: ChannelUploads].self, forKey: .channels) ?? [:]
        }
    }

    public struct ChannelUploads: Codable, Equatable, Sendable {
        public var fetchedAt: Date
        public var videos: [YouTubeClient.Candidate]

        public init(fetchedAt: Date, videos: [YouTubeClient.Candidate]) {
            self.fetchedAt = fetchedAt
            self.videos = videos
        }

        /// A day. Groups release on a schedule of months; a day is generous.
        public static let freshFor: TimeInterval = 60 * 60 * 24
        public var isStale: Bool { Date.now.timeIntervalSince(fetchedAt) > Self.freshFor }
    }

    public let file: URL

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        file = base.appendingPathComponent("videos.json")
    }

    public func restore() -> Snapshot {
        guard let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return Snapshot() }
        return snapshot
    }

    public func persist(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
