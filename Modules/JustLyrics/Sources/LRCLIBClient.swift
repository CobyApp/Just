import Foundation
import JustCore

/// Client for lrclib.net — an open, key-free, community lyrics database with
/// good coverage of Japanese releases and, crucially, time-synced LRC.
///
/// Apple Music does not expose lyrics through a public API — the Music app
/// shows them, the catalog API does not — so a dedicated lyrics source is
/// required no matter where the songs come from.
public struct LRCLIBClient: Sendable {
    public enum Failure: LocalizedError {
        case notFound
        case instrumental
        case transport(String)

        public var errorDescription: String? {
            switch self {
            case .notFound: "가사를 찾지 못했습니다. 곡명이나 아티스트를 손봐서 다시 시도해 보세요."
            case .instrumental: "연주곡으로 등록된 트랙이라 가사가 없습니다."
            case .transport(let message): message
            }
        }
    }

    struct Record: Decodable, Sendable {
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private static let host = "https://lrclib.net"
    /// lrclib asks clients to identify themselves.
    private static let userAgent = "Just/1.0 (https://github.com/; Japanese study app)"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Exact lookup first, then a fuzzy search — the exact endpoint needs the
    /// duration to match within a couple of seconds, which often misses when
    /// LRCLIB's entry was timed against a different release of the same song
    /// (single vs album vs remaster).
    public func lyrics(
        artist: String,
        title: String,
        album: String? = nil,
        duration: TimeInterval? = nil
    ) async throws -> Lyrics {
        // The exact endpoint is asked with the real metadata only: it matches on
        // all four fields, so a trimmed title would not help it.
        if let duration, duration > 0,
           let record = try? await exact(
               artist: artist,
               title: title,
               album: album,
               duration: duration
           ),
           Self.isJapanese(record.syncedLyrics ?? record.plainLyrics ?? "") {
            return try Self.lyrics(from: record)
        }

        // Searching is attempted once per spelling, cleanest last. Apple Music
        // titles carry decoration LRCLIB does not index, and a single "(feat. …)"
        // takes the count from twenty results to none — for the structured
        // search and the free-text fallback alike, so there was no way back.
        var transportFailure: Error?
        for variant in Self.queryVariants(artist: artist, title: title) {
            do {
                let results = try await search(artist: variant.artist, title: variant.title)
                if let best = Self.best(from: results, duration: duration) {
                    return try Self.lyrics(from: best)
                }
            } catch {
                // Kept, not thrown: a later spelling may still succeed, and if
                // none does the user deserves the network's reason rather than
                // "not found".
                transportFailure = transportFailure ?? error
            }
        }
        if let transportFailure { throw transportFailure }
        throw Failure.notFound
    }

    /// The spellings worth trying, most faithful first.
    ///
    /// Only ever *adds* attempts. The catalog's own spelling is asked first, so
    /// trimming can never lose a song that the untrimmed query would have found.
    static func queryVariants(
        artist: String,
        title: String
    ) -> [(artist: String, title: String)] {
        var variants: [(artist: String, title: String)] = [(artist, title)]
        let cleanTitle = simplifiedTitle(title)
        let cleanArtist = primaryArtist(artist)

        for candidate in [(artist, cleanTitle), (cleanArtist, cleanTitle)]
        where !variants.contains(where: { $0 == candidate }) {
            variants.append(candidate)
        }
        return variants
    }

    /// Drops the decoration Apple Music appends and LRCLIB does not index.
    static func simplifiedTitle(_ title: String) -> String {
        var result = title.trimmingCharacters(in: .whitespaces)

        for suffix in [" - Single", " - EP"] where result.hasSuffix(suffix) {
            result = String(result.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }

        // Trailing bracketed groups: "(feat. …)", "(Remix)", "[Live]". Stripped
        // repeatedly, because a title can carry two of them.
        while let open = openerMatchingFinalBracket(of: result) {
            let remainder = String(result[result.startIndex..<open])
                .trimmingCharacters(in: .whitespaces)
            // A title that is nothing but the bracket is left alone; querying
            // for an empty string finds everything and means nothing.
            guard !remainder.isEmpty else { break }
            result = remainder
        }

        return result
    }

    /// Where the group that closes the string begins, counting depth.
    ///
    /// Taking the *last* opening bracket instead cut inside a nested group:
    /// "Yes! 東京 (feat. A (B))" lost everything from the inner "(", leaving
    /// "Yes! 東京 (feat. A" with the bracket unmatched.
    private static func openerMatchingFinalBracket(of title: String) -> String.Index? {
        guard let last = title.last else { return nil }
        let opener: Character
        switch last {
        case ")": opener = "("
        case "]": opener = "["
        default: return nil
        }

        var depth = 0
        var index = title.endIndex
        while index > title.startIndex {
            index = title.index(before: index)
            if title[index] == last { depth += 1 }
            if title[index] == opener {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    /// The first act named, without its parenthetical reading.
    ///
    /// Apple Music joins collaborators into one string — "EBiDAN (恵比寿学園男子部),
    /// 超特急, M!LK & 原因は自分にある。" — where LRCLIB indexes a single name.
    static func primaryArtist(_ artist: String) -> String {
        var result = artist.trimmingCharacters(in: .whitespaces)

        for separator in [",", " & ", " feat", " with ", " × "] {
            if let range = result.range(of: separator, options: .caseInsensitive) {
                result = String(result[result.startIndex..<range.lowerBound])
            }
        }

        if let open = result.firstIndex(of: "("), open != result.startIndex {
            result = String(result[result.startIndex..<open])
        }

        let trimmed = result.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? artist : trimmed
    }

    private func exact(
        artist: String,
        title: String,
        album: String?,
        duration: TimeInterval
    ) async throws -> Record {
        var components = URLComponents(string: "\(Self.host)/api/get")!
        components.queryItems = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "album_name", value: album ?? ""),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
        ]
        return try await get(components.url!, as: Record.self)
    }

    func search(artist: String, title: String) async throws -> [Record] {
        var components = URLComponents(string: "\(Self.host)/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        let results = try await get(components.url!, as: [Record].self)
        guard results.isEmpty else { return results }

        // Fall back to a free-text query: Japanese artist names are often
        // indexed in a different script than the catalog spells them.
        var loose = URLComponents(string: "\(Self.host)/api/search")!
        loose.queryItems = [URLQueryItem(name: "q", value: "\(artist) \(title)")]
        return try await get(loose.url!, as: [Record].self)
    }

    private func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Failure.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw Failure.transport("응답을 해석하지 못했습니다.")
        }
        guard http.statusCode != 404 else { throw Failure.notFound }
        guard (200..<300).contains(http.statusCode) else {
            throw Failure.transport("LRCLIB 오류 (\(http.statusCode))")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw Failure.transport("가사 응답 형식이 예상과 다릅니다.")
        }
    }

    /// Fraction of lyric lines written in Japanese.
    ///
    /// A ratio rather than a contains-check, because translated lyric sheets
    /// on lrclib keep the original credit header — "作词 : 米津玄師" — above a
    /// body that is entirely Vietnamese or English. Any test that only asks
    /// "is there Japanese anywhere" passes those, and the app ends up showing
    /// a translation instead of the words the user is trying to learn.
    ///
    /// Kana specifically: kanji alone would also match Chinese credits.
    ///
    /// Split on `isNewline` rather than the literal "\n": lrclib serves CRLF
    /// for some submissions, and Swift treats "\r\n" as a single Character
    /// that compares equal to neither "\r" nor "\n" — so a literal split
    /// collapses a CRLF document into one line and every check downstream
    /// silently sees a single blob.
    static func japaneseRatio(_ lrc: String) -> Double {
        var total = 0
        var japanese = 0

        for rawLine in lrc.split(whereSeparator: \.isNewline) {
            // Drop LRC timestamps and metadata tags before judging the text.
            let text = rawLine
                .replacing(/\[[^\]]*\]/, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            total += 1
            if text.unicodeScalars.contains(where: { (0x3040...0x30FF).contains($0.value) }) {
                japanese += 1
            }
        }

        guard total > 0 else { return 0 }
        return Double(japanese) / Double(total)
    }

    /// Half the lines is a wide margin either way: real Japanese lyric sheets
    /// sit well above it even with romaji sections, translations well below.
    private static let japaneseThreshold = 0.5

    static func isJapanese(_ lrc: String) -> Bool {
        japaneseRatio(lrc) >= japaneseThreshold
    }

    private static func lyrics(from record: Record) throws -> Lyrics {
        if record.instrumental == true { throw Failure.instrumental }
        if let synced = record.syncedLyrics, !synced.isEmpty {
            return LRCParser.parse(synced)
        }
        if let plain = record.plainLyrics, !plain.isEmpty {
            return LRCParser.parsePlain(plain)
        }
        throw Failure.notFound
    }

    /// Prefers Japanese lyrics, then synced lyrics, then the closest duration.
    ///
    /// The language check is not optional: lrclib is full of user-submitted
    /// translations, and a search for a J-pop song routinely ranks a
    /// Vietnamese or English rendering above the original. For a Japanese
    /// study app a translated lyric sheet is worse than none at all.
    /// How far a record's length may sit from the catalog's before its timings
    /// stop landing on the right lines.
    static let durationTolerance: TimeInterval = 10

    static func best(from records: [Record], duration: TimeInterval?) -> Record? {
        let usable = records.filter {
            ($0.syncedLyrics?.isEmpty == false) || ($0.plainLyrics?.isEmpty == false)
        }
        guard !usable.isEmpty else { return nil }

        let japanese = usable.filter { isJapanese($0.syncedLyrics ?? $0.plainLyrics ?? "") }
        let candidates = japanese.isEmpty ? usable : japanese

        return candidates.min { lhs, rhs in
            let lhsGap = Self.gap(lhs, from: duration)
            let rhsGap = Self.gap(rhs, from: duration)

            // Length agreement comes first once the gap is past what timings
            // survive. A synced sheet written for a different edit highlights
            // the wrong line for the whole song, which is worse than lyrics
            // that simply do not follow along — it looks right and is not.
            let lhsFits = lhsGap <= Self.durationTolerance
            let rhsFits = rhsGap <= Self.durationTolerance
            if lhsFits != rhsFits { return lhsFits }

            let lhsSynced = lhs.syncedLyrics?.isEmpty == false
            let rhsSynced = rhs.syncedLyrics?.isEmpty == false
            if lhsSynced != rhsSynced { return lhsSynced }

            return lhsGap < rhsGap
        }
    }

    /// Distance between a record's length and the song's, or infinity when
    /// either is unknown — an unknown length cannot vouch for its timings.
    private static func gap(_ record: Record, from duration: TimeInterval?) -> TimeInterval {
        guard let duration, let recorded = record.duration else {
            return .greatestFiniteMagnitude
        }
        return abs(recorded - duration)
    }
}
