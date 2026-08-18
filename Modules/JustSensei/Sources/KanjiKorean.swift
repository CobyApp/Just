import Foundation
import JustCore

/// The Korean sound and meaning readings (음/훈) of a kanji.
public struct KanjiGloss: Identifiable, Hashable, Sendable {
    public var id: String { character }
    public let character: String
    /// 음 — the Sino-Korean sound, e.g. 夢 -> 몽.
    public let sound: String
    /// 훈 — the native Korean meaning, e.g. 夢 -> 꿈. May be empty.
    public let meaning: String

    public var label: String {
        meaning.isEmpty ? sound : "\(sound) · \(meaning)"
    }
}

/// Korean readings for 1,591 kanji.
///
/// This is the one piece of help that is specific to studying Japanese *from
/// Korean*. A Korean speaker already carries most of these characters around in
/// Sino-Korean vocabulary, so being told that 夢 is 「몽」 connects it to 몽상 and
/// 악몽 at no cost — a link an explanation written for English speakers cannot
/// make. It needs no model and no network.
public struct KanjiKorean: Sendable {
    public static let shared = KanjiKorean()

    private let table: [Character: KanjiGloss]

    public init() {
        guard
            let url = Bundle.module.url(forResource: "kanji-ko", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let raw = try? JSONDecoder().decode([String: [String]].self, from: data)
        else {
            table = [:]
            return
        }

        var parsed: [Character: KanjiGloss] = [:]
        for (key, readings) in raw {
            guard let character = key.first, character.isKanji else { continue }
            let sound = readings.first?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !sound.isEmpty else { continue }
            let meaning = readings.count > 1
                ? readings[1].trimmingCharacters(in: .whitespaces)
                : ""
            parsed[character] = KanjiGloss(
                character: key,
                sound: sound,
                meaning: meaning
            )
        }
        table = parsed
    }

    public var count: Int { table.count }

    public func gloss(for character: Character) -> KanjiGloss? {
        table[character]
    }

    /// Glosses for every kanji in a word, in order and without repeats.
    ///
    /// De-duplicated because a word like 日々 would otherwise print the same
    /// character twice for no benefit.
    public func glosses(in word: String) -> [KanjiGloss] {
        var seen = Set<Character>()
        return word.compactMap { character in
            guard character.isKanji, seen.insert(character).inserted else { return nil }
            return table[character]
        }
    }
}
