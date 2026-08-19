import Foundation

/// Renders saved vocabulary as CSV.
///
/// A learner who has collected a few hundred words from songs will want them in
/// Anki or a spreadsheet eventually, and an app that holds vocabulary hostage is
/// one they will hesitate to invest in. The column order matches what Anki's
/// importer expects for a front/back note, with the extras following.
public enum VocabularyExport {
    public struct Row: Sendable {
        public let lemma: String
        public let reading: String
        public let meaningKo: String
        public let jlpt: String
        public let partOfSpeech: String
        /// The lyric the word was captured from, if any.
        public let example: String
        public let song: String

        public init(
            lemma: String,
            reading: String,
            meaningKo: String,
            jlpt: String,
            partOfSpeech: String,
            example: String,
            song: String
        ) {
            self.lemma = lemma
            self.reading = reading
            self.meaningKo = meaningKo
            self.jlpt = jlpt
            self.partOfSpeech = partOfSpeech
            self.example = example
            self.song = song
        }
    }

    public static let header = "단어,읽기,뜻,등급,품사,예문,곡"

    public static func csv(from rows: [Row]) -> String {
        ([header] + rows.map(line)).joined(separator: "\n") + "\n"
    }

    private static func line(_ row: Row) -> String {
        [
            row.lemma, row.reading, row.meaningKo,
            row.jlpt, row.partOfSpeech, row.example, row.song,
        ]
        .map(escaped)
        .joined(separator: ",")
    }

    /// Quotes a field when it contains anything that would break the row.
    ///
    /// Lyrics carry commas constantly and Korean glosses carry them almost as
    /// often, so this is the common case rather than an edge one.
    static func escaped(_ field: String) -> String {
        let needsQuotes = field.contains(",")
            || field.contains("\"")
            || field.contains("\n")
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Writes the CSV to a temporary file for sharing.
    ///
    /// A file rather than a string: `ShareLink` on a string offers to paste it
    /// into a message, which is not what "export my vocabulary" means.
    public static func writeFile(rows: [Row], filename: String = "just-vocabulary.csv") -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        guard let data = csv(from: rows).data(using: .utf8) else { return nil }
        // A BOM, so Excel opens the Korean and Japanese columns as UTF-8 rather
        // than as the system's legacy encoding.
        let bom = Data([0xEF, 0xBB, 0xBF])
        try? (bom + data).write(to: url, options: .atomic)
        return url
    }
}
