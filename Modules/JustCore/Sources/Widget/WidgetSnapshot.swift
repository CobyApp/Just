import Foundation

/// What the home screen widget shows.
///
/// A snapshot rather than shared database access: a widget has no business
/// opening the app's SwiftData store — it would have to survive schema changes
/// and it can never write — and moving the store into a shared container just
/// to read three numbers would put existing user data through a migration for
/// no gain. The app writes this file; the widget reads it.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public let dueCount: Int
    public let streak: Int
    public let totalWords: Int
    /// One word to show on the face of the widget, if there is one.
    public let word: Word?
    public let updatedAt: Date

    public struct Word: Codable, Sendable, Equatable {
        public let lemma: String
        public let reading: String
        public let meaningKo: String
        public let songLabel: String?

        public init(lemma: String, reading: String, meaningKo: String, songLabel: String?) {
            self.lemma = lemma
            self.reading = reading
            self.meaningKo = meaningKo
            self.songLabel = songLabel
        }
    }

    public init(
        dueCount: Int,
        streak: Int,
        totalWords: Int,
        word: Word?,
        updatedAt: Date = .now
    ) {
        self.dueCount = dueCount
        self.streak = streak
        self.totalWords = totalWords
        self.word = word
        self.updatedAt = updatedAt
    }

    public static let placeholder = WidgetSnapshot(
        dueCount: 0,
        streak: 0,
        totalWords: 0,
        word: Word(
            lemma: "夢",
            reading: "ゆめ",
            meaningKo: "꿈",
            songLabel: nil
        )
    )
}

/// Reads and writes the snapshot in the shared container.
public enum WidgetStore {
    public static let appGroup = "group.com.coby.just"
    private static let filename = "widget-snapshot.json"

    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(filename)
    }

    public static func write(_ snapshot: WidgetSnapshot) {
        guard let url, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public static func read() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
