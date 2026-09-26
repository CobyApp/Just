import Foundation
import JustCore

/// Parses the LRC format returned by LRCLIB.
public enum LRCParser {
    // Regex is immutable once built and safe to match from any thread, but
    // isn't marked Sendable, so the guarantee is stated explicitly.
    nonisolated(unsafe) private static let timestamp = /\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]/
    /// The run of timestamps a line opens with. These, and only these, say when
    /// the line is sung.
    nonisolated(unsafe) private static let leadingTimestamps = /^(?:\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]\s*)+/
    /// Enhanced LRC's per-word times — 「<00:12.50>」 — which are not text.
    nonisolated(unsafe) private static let wordTimestamp = /<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>/
    /// 「[offset:+500]」, in milliseconds.
    nonisolated(unsafe) private static let offsetTag = /\[offset:\s*([+-]?\d+)\s*\]/.ignoresCase()

    public static func parse(_ lrc: String, source: String = "LRCLIB") -> Lyrics {
        // A byte-order mark in front of the first line hid its timestamp: the
        // line no longer began with 「[」, and the song lost its first line.
        let lrc = lrc.replacingOccurrences(of: "\u{FEFF}", with: "")
        var timed: [(time: TimeInterval, text: String)] = []
        var offset: TimeInterval = 0

        for rawLine in lrc.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)

            if let tag = line.wholeMatch(of: offsetTag) {
                offset = (Double(tag.output.1) ?? 0) / 1000
                continue
            }

            guard let lead = line.prefixMatch(of: leadingTimestamps) else { continue }

            // The text is whatever follows the opening timestamps; a line can
            // carry several when the same words repeat at different points.
            // Timestamps further along — an end time, 「[00:12.00]text[00:15.00]」,
            // or enhanced LRC's per-word marks — are timing, not words, and
            // used to be all that was left of the line: its text was taken from
            // after the *last* timestamp, which for those lines is nothing.
            let text = String(line[lead.range.upperBound...])
                .replacing(timestamp, with: "")
                .replacing(wordTimestamp, with: "")
                .trimmingCharacters(in: .whitespaces)

            for match in line[lead.range].matches(of: timestamp) {
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

        // The LRC convention: a positive offset makes the lyrics appear
        // earlier. It applies to the whole file wherever the tag sits, and a
        // line pulled before the start is simply the first thing shown.
        let lines = timed
            .map { (time: max(0, $0.time - offset), text: $0.text) }
            .sorted { $0.time < $1.time }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: $0.element.time, text: $0.element.text) }

        return Lyrics(lines: lines, isSynced: true, source: source)
    }

    public static func parsePlain(_ text: String, source: String = "LRCLIB") -> Lyrics {
        let lines = text
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: nil, text: $0.element) }
        return Lyrics(lines: lines, isSynced: false, source: source)
    }
}
