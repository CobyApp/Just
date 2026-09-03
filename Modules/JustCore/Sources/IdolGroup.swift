import Foundation

/// A group the app teaches from.
///
/// The whole catalogue of this app is this list. There is no search: a song
/// gets in by belonging to one of these seven, which is what makes it an idol
/// app rather than a music app that happens to have idols in it.
///
/// Only the roster is bundled. The songs come from Apple Music, so a new
/// single appears without an app update, and artwork and durations come with it.
public struct IdolGroup: Identifiable, Hashable, Sendable {
    /// Apple Music's artist id.
    ///
    /// An id rather than a name, because names collide. Looked up by name, a
    /// group loses its whole catalogue the day another artist matches better —
    /// and the failure looks like the group simply having no songs.
    public let id: String
    /// As the group writes it.
    public let name: String
    /// What to call it in Korean, for readers who know the group by ear.
    public let readingKo: String
    /// The label it belongs to, shown as a section.
    public let label: Label
    /// Hue for this group's card and accents, 0–1.
    public let hue: Double

    public enum Label: String, CaseIterable, Sendable {
        case kawaiiLab = "KAWAII LAB."
        case iLife = "iLiFE!"
        case equalLove = "=LOVE"
    }

    public init(id: String, name: String, readingKo: String, label: Label, hue: Double) {
        self.id = id
        self.name = name
        self.readingKo = readingKo
        self.label = label
        self.hue = hue
    }
}

public extension IdolGroup {
    /// Every group, in the order they are shown.
    ///
    /// Ids were checked against Apple Music rather than typed from memory —
    /// MORE STAR was confirmed by its own song 「WITH KAWAII論」, which is how
    /// its label was settled too.
    static let all: [IdolGroup] = [
        .init(id: "1617607581", name: "FRUITS ZIPPER", readingKo: "후룻파", label: .kawaiiLab, hue: 0.92),
        .init(id: "1671095780", name: "CANDY TUNE", readingKo: "캔디튠", label: .kawaiiLab, hue: 0.02),
        .init(id: "1729116371", name: "SWEET STEADY", readingKo: "스윗스테", label: .kawaiiLab, hue: 0.55),
        .init(id: "1763185226", name: "CUTIE STREET", readingKo: "큐티스트리트", label: .kawaiiLab, hue: 0.85),
        .init(id: "1855752654", name: "MORE STAR", readingKo: "모어스타", label: .kawaiiLab, hue: 0.13),
        .init(id: "1578837625", name: "iLiFE!", readingKo: "아이라이프", label: .iLife, hue: 0.45),
        .init(id: "1273762750", name: "=LOVE", readingKo: "이코러브", label: .equalLove, hue: 0.75),
    ]

    static func group(id: String) -> IdolGroup? {
        all.first { $0.id == id }
    }

    /// The groups under one label, in roster order.
    static func groups(in label: Label) -> [IdolGroup] {
        all.filter { $0.label == label }
    }
}
