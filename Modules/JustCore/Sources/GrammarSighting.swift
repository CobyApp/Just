import Foundation

/// A grammar pattern as it has actually turned up in the user's songs.
///
/// The model attaches notes to lines, and a line belongs to one song — but the
/// pattern does not. Pooling by pattern is what turns forty scattered notes into
/// a list worth reading, and what makes "this shows up in four of your songs"
/// sayable at all.
public struct GrammarSighting: Identifiable, Sendable, Hashable {
    public var id: String { pattern }
    public let pattern: String
    public let explanationKo: String
    /// The first line it was seen in, kept as the example.
    public let example: String
    public let exampleTranslation: String
    /// Songs it has been seen in, in the order they were met.
    public private(set) var songs: [String]

    public init(
        pattern: String,
        explanationKo: String,
        example: String,
        exampleTranslation: String,
        song: String
    ) {
        self.pattern = pattern
        self.explanationKo = explanationKo
        self.example = example
        self.exampleTranslation = exampleTranslation
        self.songs = [song]
    }

    public var songCount: Int { songs.count }

    /// Records another song, ignoring one already counted.
    ///
    /// A pattern repeating within a single song says nothing about how common it
    /// is — a chorus would inflate it — so only distinct songs count.
    mutating func addSighting(song: String) {
        guard !songs.contains(song) else { return }
        songs.append(song)
    }
}
