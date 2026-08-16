import Foundation
import JustCore

/// Parses the LRC format returned by LRCLIB.
public enum LRCParser {
    // Regex is immutable once built and safe to match from any thread, but
    // isn't marked Sendable, so the guarantee is stated explicitly.
    nonisolated(unsafe) private static let timestamp = /\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]/

    public static func parse(_ lrc: String, source: String = "LRCLIB") -> Lyrics {
        var timed: [(time: TimeInterval, text: String)] = []

        for rawLine in lrc.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(rawLine)
            let matches = line.matches(of: timestamp)
            guard !matches.isEmpty else { continue }

            // The text is whatever follows the final timestamp; a line can carry
            // several when the same words repeat at different points.
            let text = String(line[matches[matches.count - 1].range.upperBound...])
                .trimmingCharacters(in: .whitespaces)

            for match in matches {
                let minutes = Double(match.output.1) ?? 0
                let seconds = Double(match.output.2) ?? 0
                let fractionText = match.output.3.map(String.init) ?? "0"
                // LRC uses either centiseconds or milliseconds.
                let fraction = (Double(fractionText) ?? 0)
                    / pow(10, Double(fractionText.count))
                timed.append((minutes * 60 + seconds + fraction, text))
            }
        }

        guard !timed.isEmpty else {
            return parsePlain(lrc, source: source)
        }

        let lines = timed
            .sorted { $0.time < $1.time }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: $0.element.time, text: $0.element.text) }

        return Lyrics(lines: lines, isSynced: true, source: source)
    }

    public static func parsePlain(_ text: String, source: String = "LRCLIB") -> Lyrics {
        let lines = text
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: nil, text: $0.element) }
        return Lyrics(lines: lines, isSynced: false, source: source)
    }
}
