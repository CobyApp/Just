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
            case .noKey: "영상을 찾을 수 없어 미리듣기로 재생합니다."
            case .notFound: "이 곡의 영상을 찾지 못했습니다."
            case .quotaExceeded: "오늘은 새 영상을 더 찾을 수 없습니다. 내일 다시 시도해 주세요."
            case .transport(let message): message
            }
        }
    }

    public struct Candidate: Sendable, Equatable {
        public let videoID: String
        public let title: String
        public let channelTitle: String

        public init(videoID: String, title: String, channelTitle: String) {
            self.videoID = videoID
            self.title = title
            self.channelTitle = channelTitle
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

    /// The video for a song — the official music video when there is one.
    public func videoID(for track: Track) async throws -> String {
        guard let key else { throw Failure.noKey }
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        components.queryItems = [
            .init(name: "part", value: "snippet"),
            .init(name: "type", value: "video"),
            .init(name: "videoCategoryId", value: "10"),
            .init(name: "videoEmbeddable", value: "true"),
            .init(name: "maxResults", value: "8"),
            .init(name: "regionCode", value: "JP"),
            .init(name: "relevanceLanguage", value: "ja"),
            .init(name: "q", value: Self.query(for: track)),
            .init(name: "key", value: key),
        ]
        let (data, response) = try await session.data(from: components.url!)
        if let http = response as? HTTPURLResponse, http.statusCode == 403 {
            throw Failure.quotaExceeded
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.transport("영상을 찾지 못했습니다 (\(http.statusCode)). 잠시 뒤에 다시 시도해 주세요.")
        }
        let candidates = try Self.candidates(from: data)
        guard let best = Self.choose(candidates, for: track) else { throw Failure.notFound }
        return best.videoID
    }

    static func query(for track: Track) -> String {
        "\(track.artist) \(track.title) MV"
    }

    // MARK: - Choosing

    /// The result that is most likely this song's official video.
    ///
    /// Search relevance alone picks dance-practice videos, fan uploads and
    /// live clips. The song's title has to be in the video's title; then the
    /// official music video outranks the rest, and the group's own channel
    /// outranks strangers.
    public static func choose(_ candidates: [Candidate], for track: Track) -> Candidate? {
        let wantedTitle = fold(track.title)
        let wantedArtist = fold(track.artist)
        let scored: [(Candidate, Int)] = candidates.compactMap { candidate in
            let title = fold(candidate.title)
            let channel = fold(candidate.channelTitle)
            guard title.contains(wantedTitle) else { return nil }
            var score = 1
            if title.contains("mv") || title.contains("musicvideo") || title.contains("ミュージックビデオ") { score += 4 }
            if title.contains("official") || title.contains("公式") { score += 1 }
            if channel.contains(wantedArtist) || channel.contains("official") { score += 3 }
            for bad in ["dancepractice", "ダンスプラクティス", "live", "ライブ", "cover", "カバー", "踊ってみた", "歌ってみた", "lyric", "リリック", "teaser", "ティザー", "makingof", "メイキング", "reaction", "short"] where title.contains(bad) {
                score -= 3
            }
            return (candidate, score)
        }
        return scored.max { $0.1 < $1.1 }?.0
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
            struct Snippet: Decodable { let title: String; let channelTitle: String }
            let id: ID
            let snippet: Snippet
        }
        let items: [Item]
    }

    static func candidates(from data: Data) throws -> [Candidate] {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return payload.items.compactMap { item in
            guard let id = item.id.videoId else { return nil }
            return Candidate(videoID: id, title: Self.unescaped(item.snippet.title), channelTitle: item.snippet.channelTitle)
        }
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
        public init(videos: [String: String] = [:]) { self.videos = videos }
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
