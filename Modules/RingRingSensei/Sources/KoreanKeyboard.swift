import Foundation

public extension String {
    /// The Latin keys that produce this text on a Korean two-set (두벌식)
    /// keyboard, or nil when there is no Hangul in it.
    ///
    /// The readers are Korean, and a Korean keyboard is the one they have on.
    /// Typing romaji without switching layouts first turns 「yume」 into
    /// 「ㅛㅕㅡㄷ」 — the right keys, read as the wrong alphabet — and that was
    /// marked wrong. Every syllable decomposes back into the jamo that were
    /// typed, and each jamo sits on one key (two, for the compound ones), so
    /// the keystrokes can be recovered exactly.
    func dubeolsikKeystrokes() -> String? {
        var keys = ""
        var sawHangul = false
        for scalar in unicodeScalars {
            if let jamo = Self.jamo(ofSyllable: scalar) {
                sawHangul = true
                for part in jamo { keys += Self.keys(for: part) ?? "" }
            } else if let typed = Self.keys(for: Character(scalar)) {
                sawHangul = true
                keys += typed
            } else {
                keys.unicodeScalars.append(scalar)
            }
        }
        return sawHangul ? keys : nil
    }

    // Unicode orders the precomposed syllables by initial, medial and final,
    // so each syllable's code is arithmetic on those three indices.

    private static let initials: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    private static let medials: [Character] = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    /// Index 0 is "no final consonant".
    private static let finals: [Character?] = [nil] + Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ").map { $0 }

    private static func jamo(ofSyllable scalar: Unicode.Scalar) -> [Character]? {
        let base: UInt32 = 0xAC00
        guard (base...0xD7A3).contains(scalar.value) else { return nil }
        let index = Int(scalar.value - base)
        let initial = initials[index / (21 * 28)]
        let medial = medials[(index % (21 * 28)) / 28]
        return [initial, medial] + [finals[index % 28]].compactMap { $0 }
    }

    /// The two-set layout. Doubled consonants and ㅒ ㅖ are the shifted keys;
    /// romaji is case-blind, so they map to the same letters.
    private static let layout: [Character: String] = [
        "ㅂ": "q", "ㅈ": "w", "ㄷ": "e", "ㄱ": "r", "ㅅ": "t",
        "ㅛ": "y", "ㅕ": "u", "ㅑ": "i", "ㅐ": "o", "ㅔ": "p",
        "ㅁ": "a", "ㄴ": "s", "ㅇ": "d", "ㄹ": "f", "ㅎ": "g",
        "ㅗ": "h", "ㅓ": "j", "ㅏ": "k", "ㅣ": "l",
        "ㅋ": "z", "ㅌ": "x", "ㅊ": "c", "ㅍ": "v", "ㅠ": "b", "ㅜ": "n", "ㅡ": "m",
        "ㅃ": "q", "ㅉ": "w", "ㄸ": "e", "ㄲ": "r", "ㅆ": "t", "ㅒ": "o", "ㅖ": "p",
        // Compounds are typed as their parts.
        "ㅘ": "hk", "ㅙ": "ho", "ㅚ": "hl", "ㅝ": "nj", "ㅞ": "np", "ㅟ": "nl", "ㅢ": "ml",
        "ㄳ": "rt", "ㄵ": "sw", "ㄶ": "sg", "ㄺ": "fr", "ㄻ": "fa", "ㄼ": "fq",
        "ㄽ": "ft", "ㄾ": "fx", "ㄿ": "fv", "ㅀ": "fg", "ㅄ": "qt",
    ]

    private static func keys(for jamo: Character) -> String? {
        layout[jamo]
    }
}
