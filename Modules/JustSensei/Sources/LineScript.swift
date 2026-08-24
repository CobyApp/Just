import Foundation

/// What script a lyric line is written in.
///
/// J-pop mixes them freely — an English hook over a Japanese verse, a whole
/// chorus in English — and the two want different treatment. An English line
/// still wants translating, because the reader wants to know what the song
/// says. It does not want vocabulary cards: nothing in it is a Japanese word
/// to learn, and a card for "baby" with a made-up kana reading is worse than
/// no card, because it enters the review schedule and comes back.
public enum LineScript {
    /// Whether there is any Japanese in this text.
    ///
    /// Kana or kanji. Not a ratio: one Japanese word in an English line is
    /// still a word worth learning, so the question is only whether there is
    /// anything Japanese at all.
    ///
    /// Deliberately false for Korean, which sits right next to the line as its
    /// translation and must never be mistaken for it.
    public static func hasJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            let value = scalar.value
            return (0x3040...0x30FA).contains(value)   // hiragana, katakana
                || (0x30FC...0x30FF).contains(value)   // ー and the rest
                || value == 0x3005                     // 々
                || (0x3400...0x4DBF).contains(value)   // kanji, extension A
                || (0x4E00...0x9FFF).contains(value)   // kanji
                || (0xF900...0xFAFF).contains(value)   // compatibility kanji
        }
    }
}
