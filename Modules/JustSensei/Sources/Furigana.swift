import Foundation
import JustCore

public enum Furigana {
    /// Splits `surface` against `reading` so the ruby sits only over the kanji.
    ///
    /// Naively annotating the whole word gives 歩いてる[あるいてる], which puts
    /// the reading over kana the learner can already read. Trimming the kana
    /// that both strings share at each end narrows it to 歩[あ]いてる, which is
    /// how furigana is actually typeset.
    public static func segments(surface: String, reading: String) -> [RubySegment] {
        guard surface.containsKanji, !reading.isEmpty, surface != reading else {
            return [RubySegment(id: 0, base: surface, ruby: nil)]
        }

        let surfaceChars = Array(surface)
        // Two copies: the normalised one decides where the kana match, the
        // original is what gets printed. Slicing the normalised copy would
        // silently rewrite タバコ as たばこ — fine for comparison, wrong for a
        // reading the user is meant to read back.
        let readingChars = Array(reading)
        let comparableReading = readingChars.map(normalizeKana)

        // Okurigana shared at the tail (歩いてる / あるいてる -> "いてる").
        var tail = 0
        while tail < surfaceChars.count, tail < comparableReading.count {
            let s = surfaceChars[surfaceChars.count - 1 - tail]
            let r = comparableReading[comparableReading.count - 1 - tail]
            guard !s.isKanji, normalizeKana(s) == r else { break }
            tail += 1
        }

        // Kana shared at the head (お願い / おねがい -> "お").
        var head = 0
        while head < surfaceChars.count - tail, head < comparableReading.count - tail {
            let s = surfaceChars[head]
            let r = comparableReading[head]
            guard !s.isKanji, normalizeKana(s) == r else { break }
            head += 1
        }

        let coreSurface = String(surfaceChars[head..<(surfaceChars.count - tail)])
        let coreReading = String(readingChars[head..<(readingChars.count - tail)])

        guard !coreSurface.isEmpty else {
            return [RubySegment(id: 0, base: surface, ruby: nil)]
        }

        var segments: [RubySegment] = []
        var index = 0
        if head > 0 {
            segments.append(
                RubySegment(id: index, base: String(surfaceChars[0..<head]), ruby: nil)
            )
            index += 1
        }
        segments.append(
            RubySegment(id: index, base: coreSurface, ruby: coreReading.isEmpty ? nil : coreReading)
        )
        index += 1
        if tail > 0 {
            segments.append(
                RubySegment(
                    id: index,
                    base: String(surfaceChars[(surfaceChars.count - tail)...]),
                    ruby: nil
                )
            )
        }
        return segments
    }

    /// Ruby for a whole lyric line, using the tokenizer's per-token readings.
    public static func segments(
        forLine line: String,
        tokenizer: JapaneseTokenizer = JapaneseTokenizer()
    ) -> [RubySegment] {
        let tokens = tokenizer.tokenize(line)
        guard !tokens.isEmpty else { return [RubySegment(id: 0, base: line, ruby: nil)] }

        var result: [RubySegment] = []
        var cursor = line.startIndex
        var id = 0

        for token in tokens {
            if cursor < token.range.lowerBound {
                result.append(
                    RubySegment(id: id, base: String(line[cursor..<token.range.lowerBound]), ruby: nil)
                )
                id += 1
            }
            for piece in Self.segments(surface: token.surface, reading: token.reading) {
                result.append(RubySegment(id: id, base: piece.base, ruby: piece.ruby))
                id += 1
            }
            cursor = token.range.upperBound
        }
        if cursor < line.endIndex {
            result.append(RubySegment(id: id, base: String(line[cursor...]), ruby: nil))
        }
        return result
    }

    /// Katakana and hiragana compare equal — readings come back in either script.
    private static func normalizeKana(_ character: Character) -> Character {
        guard character.isKatakana else { return character }
        guard let scalar = character.unicodeScalars.first,
              let shifted = Unicode.Scalar(scalar.value - 0x60)
        else { return character }
        return Character(shifted)
    }
}
