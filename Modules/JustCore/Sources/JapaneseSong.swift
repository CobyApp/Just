import Foundation

/// Whether a catalog song is one this app can teach from.
///
/// The app studies Japanese lyrics, so a search that returns everything Apple
/// Music has is mostly noise — and a song with no Japanese in it has no lesson
/// in it either.
///
/// Genre first, because script does not work. 「Lemon」, 「Pretender」 and
/// 「KICK BACK」 are Japanese songs with Latin titles, and YOASOBI, King Gnu,
/// Vaundy, Ado and RADWIMPS are Japanese acts with Latin names — a script test
/// would throw away exactly the songs someone opens this app to study.
///
/// Script is the second chance rather than the only test, because genre names
/// are not always filled in on a search result.
public enum JapaneseSong {
    /// Genre names Apple Music uses for Japanese music, in the storefronts it
    /// uses them in.
    private static let markers = [
        "j-pop", "jpop", "j-rock", "jrock", "japanese", "anime",
        "j-ポップ", "ポップ", "ロック", "アニメ", "邦楽",
    ]

    public static func isJapanese(title: String, artist: String, genres: [String]) -> Bool {
        for genre in genres {
            let lowered = genre.lowercased()
            if markers.contains(where: lowered.contains) { return true }
        }
        return containsJapanese(title) || containsJapanese(artist)
    }

    /// Kana or kanji. Deliberately false for Korean and for Chinese written
    /// without kana — the first would let K-pop through, and this app cannot
    /// teach from either.
    private static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value)   // kana
                || (0x4E00...0x9FFF).contains(scalar.value)  // kanji
                || (0x3400...0x4DBF).contains(scalar.value)
        }
    }
}
