import Foundation
import RingRingCore
import Observation

/// The single entry point the app uses for lyric analysis.
///
/// One reading, the fast one: the bundled dictionary names the words and their
/// meanings, a pattern list matches the grammar, and the system translator
/// renders the sentence. No on-device language model — it needed recent hardware,
/// took minutes over a song, and its answers still had to be corrected against
/// this same dictionary. What is left is instant, offline for everything but the
/// sentence, and the same on every device.
@MainActor
@Observable
public final class Sensei {
    /// Line index -> result, so re-tapping a line is instant.
    ///
    /// Line index alone is not an identity: line 3 exists in every song. The
    /// cache therefore carries the song it was filled for, and callers that
    /// write it back to a record must ask through `cache(for:)`.
    public private(set) var entries: [Int: LineStudy] = [:]
    /// The song `entries` belongs to. Nil before any song has been opened.
    public private(set) var songID: String?
    public private(set) var inFlight: Set<Int> = []
    /// Bumped whenever `reset(for:)` changes the song, so work that awaits the
    /// translator and comes back late is filed under the right song or dropped.
    private var scope = 0

    private let dictionary: DictionarySensei
    private let tokenizer = JapaneseTokenizer()
    /// The system translator, injected so the rules around it can be tested
    /// without one.
    private let translate: @MainActor (String) async -> String?
    /// The language the sentence targets, and the script a usable translation
    /// has to be written in.
    private let language: AppLanguage
    /// Whether the system translator can produce a sentence right now. Cached so
    /// a song's worth of lines do not each re-ask; refreshed when the app comes
    /// forward or the language pack is downloaded. Optimistic at first so the
    /// first song tries the translator before the check has returned.
    private var translatorReady = true

    public init(dictionary: DictionarySensei = DictionarySensei()) {
        self.dictionary = dictionary
        self.language = AppLanguage.current
        self.translate = { await PlainTranslator.shared.translate($0) }
    }

    /// Test seam: the rules around the translator need checking without a system
    /// translator, which a test process has no access to.
    init(
        dictionary: DictionarySensei,
        language: AppLanguage = .ko,
        translatorReady: Bool = true,
        translate: @escaping @MainActor (String) async -> String? = { _ in nil }
    ) {
        self.dictionary = dictionary
        self.language = language
        self.translatorReady = translatorReady
        self.translate = translate
    }

    /// Re-reads whether the translator can answer — after the reader downloads
    /// the language pack, or turns the setting back on, or the app returns to the
    /// foreground. Lines left without a sentence become pending again, so the
    /// next pass over the song fills them in.
    public func refreshTranslator() async {
        PlainTranslator.shared.reconsider()
        translatorReady = await PlainTranslator.shared.isReady()
    }

    /// Points the cache at a song, dropping the previous song's results.
    ///
    /// Re-opening the song already in scope keeps everything: the player is
    /// reopened far more often than the song changes.
    public func reset(for songID: String) {
        guard songID != self.songID else { return }
        self.songID = songID
        scope += 1
        entries.removeAll()
        inFlight.removeAll()
    }

    /// The cache, but only if it still belongs to the song asking for it.
    ///
    /// A session whose song has been left behind gets nil rather than the new
    /// song's entries — writing those to its own record would replace a whole
    /// analysed song with someone else's lines.
    ///
    /// Only settled results are handed over: a line still waiting on a
    /// translation that could yet arrive is left out, so the record does not
    /// freeze in a blank the next pass would have filled.
    public func cache(for songID: String) -> [Int: LineStudy]? {
        guard self.songID == songID else { return nil }
        return entries.filter { isFinal($0.value) }
    }

    public func cached(_ lineIndex: Int) -> LineStudy? { entries[lineIndex] }

    /// Seeds the cache with analyses already persisted for this song.
    public func preload(_ studies: [Int: LineStudy]) {
        for (index, study) in studies where entries[index] == nil {
            entries[index] = study
        }
    }

    /// Lines still needing work — never analysed, or analysed into nothing the
    /// translator could still improve.
    public func pendingLines(in lyrics: Lyrics) -> [LyricLine] {
        lyrics.lines.filter { line in
            guard !line.text.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
            guard let cached = entries[line.id] else { return true }
            return !isFinal(cached)
        }
    }

    public func isAnalyzing(_ lineIndex: Int) -> Bool { inFlight.contains(lineIndex) }

    @discardableResult
    public func analyze(
        lineIndex: Int,
        in lyrics: Lyrics,
        songTitle: String,
        artist: String
    ) async -> LineStudy? {
        if let cached = entries[lineIndex], isFinal(cached) { return cached }
        // Already being worked on — a tap landing while a background pass is on
        // this line. A second run would translate the same sentence twice.
        guard !inFlight.contains(lineIndex) else { return entries[lineIndex] }
        guard let line = lyrics.lines.first(where: { $0.id == lineIndex }) else { return nil }
        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        return await produce(text: text, lineIndex: lineIndex)
    }

    /// Reads one line with the dictionary, matches its grammar, and — when the
    /// translator can — renders the sentence.
    ///
    /// - Returns: nil when the song changed while the line was being worked on.
    private func produce(text: String, lineIndex: Int) async -> LineStudy? {
        let scope = self.scope
        inFlight.insert(lineIndex)
        defer {
            // Only our own marker. After a song change the set belongs to the
            // new song, and the same index there may be in flight for real.
            if self.scope == scope { inFlight.remove(lineIndex) }
        }

        var result = Self.learnable(dictionary.analyze(line: text, lineIndex: lineIndex))

        // Grammar from matching the line rather than asking anything.
        if result.grammar.isEmpty {
            let matched = GrammarPatterns.matches(in: result.original)
            if !matched.isEmpty {
                result = LineStudy(
                    lineIndex: result.lineIndex,
                    original: result.original,
                    translationKo: result.translationKo,
                    words: result.words,
                    grammar: matched,
                    engine: result.engine
                )
            }
        }

        // The sentence, from the system translator, when it can give one that is
        // actually in the target language. A translator with no pack returns the
        // source unchanged, which `isUsableTranslation` rejects.
        if result.translationKo.isEmpty, translatorReady {
            let rendered = await translate(result.original)
            guard self.scope == scope else { return nil }
            if let rendered, Self.isUsableTranslation(rendered, language: language) {
                result = LineStudy(
                    lineIndex: result.lineIndex,
                    original: result.original,
                    translationKo: rendered,
                    words: result.words,
                    grammar: result.grammar,
                    engine: .plainTranslation
                )
            }
        }

        entries[lineIndex] = result
        return result
    }

    /// Whether a result is the best this device can produce right now.
    ///
    /// A sentence settles it. Without one, it is settled only when the
    /// translator cannot give one anyway — otherwise the line stays pending so
    /// that a pack downloaded later fills it in.
    private func isFinal(_ study: LineStudy) -> Bool {
        if !study.translationKo.isEmpty { return true }
        return !translatorReady
    }

    /// Walks the whole song, translating every line that still needs it, and
    /// copying a repeated chorus line from the one answer rather than translating
    /// it again.
    ///
    /// One attempt per distinct line: a line the translator cannot render stays
    /// blank with its words shown, and looping would never end on it.
    public func analyzeAll(
        lyrics: Lyrics,
        songTitle: String,
        artist: String,
        onProgress: @MainActor (Int, Int) -> Void = { _, _ in }
    ) async {
        let scope = self.scope
        let pending = pendingLines(in: lyrics)
        let total = pending.count
        guard total > 0 else { return }

        // Grouped by the text itself: a chorus is several lines with identical
        // text, translated once and copied to the rest.
        var groups: [String: [LyricLine]] = [:]
        var order: [String] = []
        for line in pending {
            let key = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(line)
        }

        var done = 0
        for key in order {
            if Task.isCancelled { return }
            guard self.scope == scope else { return }
            guard let lines = groups[key], let first = lines.first else { continue }

            let study = await analyze(
                lineIndex: first.id, in: lyrics, songTitle: songTitle, artist: artist
            )
            guard self.scope == scope else { return }

            if let study {
                for repeated in lines.dropFirst() {
                    entries[repeated.id] = study.moved(to: repeated.id)
                }
            }

            done += lines.count
            onProgress(done, total)
        }
    }

    // MARK: - Shared text rules

    /// Drops what there is nothing to learn from: a line with no Japanese keeps
    /// its translation and loses its "words", and any non-Japanese candidate is
    /// removed from a line that does have Japanese.
    public nonisolated static func learnable(_ study: LineStudy) -> LineStudy {
        guard LineScript.hasJapanese(study.original) else {
            return LineStudy(
                lineIndex: study.lineIndex,
                original: study.original,
                translationKo: study.translationKo,
                words: [],
                grammar: [],
                engine: study.engine
            )
        }

        let japanese = study.words.filter { LineScript.hasJapanese($0.surface) }
        guard japanese.count != study.words.count else { return study }
        return LineStudy(
            lineIndex: study.lineIndex,
            original: study.original,
            translationKo: study.translationKo,
            words: japanese,
            grammar: study.grammar,
            engine: study.engine
        )
    }

    /// Whether a rendered sentence can be shown as the translation.
    ///
    /// A translator with nothing installed returns the source unchanged, and a
    /// half-done one leaves Japanese in the middle — both are worse than showing
    /// the words alone. The test is script: no Japanese left, and the target
    /// language's own letters carrying the bulk of it. Quoted text is excluded,
    /// so a line that quotes the song's own hook is judged on the rest.
    public nonisolated static func isUsableTranslation(_ translation: String, language: AppLanguage) -> Bool {
        judgeUsable(translation, language: language)
    }

    /// The Korean-target check, kept as the bare-argument form the Korean tests
    /// and callers use.
    public nonisolated static func isUsableTranslation(_ translation: String) -> Bool {
        judgeUsable(translation, language: .ko)
    }

    private nonisolated static func judgeUsable(_ translation: String, language: AppLanguage) -> Bool {
        let letters = unquotedLetters(in: translation)
        guard letters.japanese == 0 else { return false }
        switch language {
        case .ko:
            return letters.hangul > 0 && letters.hangul >= letters.latin
        case .en:
            return letters.latin > 0
        }
    }

    /// Counts the letters outside quotation marks, by script.
    private nonisolated static func unquotedLetters(
        in text: String
    ) -> (hangul: Int, latin: Int, japanese: Int) {
        let openers: Set<Character> = ["'", "\"", "「", "『", "\u{2018}", "\u{201C}"]
        let closers: Set<Character> = ["'", "\"", "」", "』", "\u{2019}", "\u{201D}"]

        var counts = (hangul: 0, latin: 0, japanese: 0)
        var quoted = false

        for character in text {
            if quoted {
                if closers.contains(character) { quoted = false }
                continue
            }
            if openers.contains(character) {
                quoted = true
                continue
            }
            guard let scalar = character.unicodeScalars.first else { continue }
            let value = scalar.value
            if (0xAC00...0xD7A3).contains(value)
                || (0x1100...0x11FF).contains(value)
                || (0x3130...0x318F).contains(value) {
                counts.hangul += 1
            } else if character.isLetter, scalar.isASCII {
                counts.latin += 1
            } else if LineScript.hasJapanese(String(character)) {
                counts.japanese += 1
            }
        }
        return counts
    }
}
