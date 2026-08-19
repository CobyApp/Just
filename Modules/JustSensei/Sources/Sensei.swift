import Foundation
import JustCore
import Observation

/// The single entry point the app uses for lyric analysis.
///
/// Picks the on-device model when Apple Intelligence is available and falls
/// back to the bundled dictionary otherwise — including when a single call
/// fails at runtime, so one bad line never leaves the user with nothing.
@MainActor
@Observable
public final class Sensei {
    public private(set) var unavailability: OnDeviceSensei.Unavailability?
    /// Line index -> result, so re-tapping a line is instant.
    ///
    /// Line index alone is not an identity: line 3 exists in every song. The
    /// cache therefore carries the song it was filled for, and callers that
    /// write it back to a record must ask through `cache(for:)`.
    public private(set) var entries: [Int: LineStudy] = [:]
    /// The song `entries` belongs to. Nil before any song has been opened.
    public private(set) var songID: String?
    public private(set) var inFlight: Set<Int> = []

    private let onDevice: OnDeviceSensei?
    private let dictionary: DictionarySensei
    /// Whether the on-device model is there at all, which is what decides
    /// whether a dictionary result is an answer or a failure.
    private let modelIsAvailable: Bool

    public init(dictionary: DictionarySensei = DictionarySensei()) {
        self.dictionary = dictionary
        let reason = OnDeviceSensei.availability
        self.unavailability = reason
        self.onDevice = reason == nil ? OnDeviceSensei() : nil
        self.modelIsAvailable = reason == nil
    }

    /// Test seam: the model cannot be summoned in a test run, but the rules
    /// about what its absence means still need checking.
    init(dictionary: DictionarySensei, modelIsAvailable: Bool) {
        self.dictionary = dictionary
        self.onDevice = nil
        self.unavailability = modelIsAvailable ? nil : .deviceNotEligible
        self.modelIsAvailable = modelIsAvailable
    }

    public var usesOnDeviceModel: Bool { modelIsAvailable }

    public func prewarm() {
        onDevice?.prewarm()
    }

    /// Points the cache at a song, dropping the previous song's results.
    ///
    /// Re-opening the song already in scope keeps everything: the player is
    /// reopened far more often than the song changes.
    public func reset(for songID: String) {
        guard songID != self.songID else { return }
        self.songID = songID
        entries.removeAll()
        inFlight.removeAll()
    }

    /// The cache, but only if it still belongs to the song asking for it.
    ///
    /// A session whose song has been left behind gets nil rather than the new
    /// song's entries — writing those to its own record would replace a whole
    /// analysed song with someone else's lines, or with nothing at all.
    ///
    /// Only settled results are handed over. A line the model failed on is
    /// worth showing right now, but persisting it would freeze the failure into
    /// the record: reopening the song would load it back, and nothing would
    /// ever ask the model again.
    public func cache(for songID: String) -> [Int: LineStudy]? {
        guard self.songID == songID else { return nil }
        return entries.filter { isFinal($0.value) }
    }

    public func cached(_ lineIndex: Int) -> LineStudy? { entries[lineIndex] }

    /// Seeds the cache with analyses already persisted for this song.
    ///
    /// Everything persisted is loaded, settled or not. `isFinal` decides
    /// separately whether a line still needs the model, so a record written by
    /// an older build — when a failed line could be saved as if it were an
    /// answer — repairs itself the next time the song is opened.
    public func preload(_ studies: [Int: LineStudy]) {
        for (index, study) in studies where entries[index] == nil {
            entries[index] = study
        }
    }

    /// Lines still needing work — never analysed, or analysed into nothing.
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
        guard let line = lyrics.lines.first(where: { $0.id == lineIndex }) else { return nil }
        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        inFlight.insert(lineIndex)
        defer { inFlight.remove(lineIndex) }

        let result: LineStudy
        if let onDevice {
            do {
                result = try await onDevice.analyze(
                    line: text,
                    lineIndex: lineIndex,
                    previous: lyrics.lines.first { $0.id == lineIndex - 1 }?.text,
                    next: lyrics.lines.first { $0.id == lineIndex + 1 }?.text,
                    songTitle: songTitle,
                    artist: artist
                )
            } catch {
                result = dictionary.analyze(line: text, lineIndex: lineIndex)
            }
        } else {
            result = dictionary.analyze(line: text, lineIndex: lineIndex)
        }

        let refined = refine(result)
        // Kept even when it is not a settled answer, so the line shows its words
        // instead of nothing. `isFinal` is what stops it being treated as the
        // last word — the short-circuit above skips it, so the next pass tries
        // the model again.
        entries[lineIndex] = refined
        return refined
    }

    /// Whether a result is the best this device can produce.
    ///
    /// A translation settles it. Without one, the answer came from the
    /// dictionary, and what that means depends on the device: with no on-device
    /// model it is the best there will ever be, but with one it means the model
    /// call failed — a network of a moment, a guardrail, a busy system — and the
    /// line deserves another attempt rather than a permanent blank.
    private func isFinal(_ study: LineStudy) -> Bool {
        !study.translationKo.isEmpty || !modelIsAvailable
    }

    // MARK: - Refinement

    /// Corrects the two things a 3B on-device model reliably gets wrong.
    ///
    /// It is good at context — spotting that 「〜てる」 is 「〜ている」, rendering
    /// a line as natural Korean — and unreliable at recall: it mislabels JLPT
    /// levels and sometimes writes the *reading* into the dictionary-form
    /// field. Both are facts, not judgements, so the bundled dictionary
    /// overrides the model wherever it has an entry.
    private func refine(_ study: LineStudy) -> LineStudy {
        guard study.engine == .onDevice else { return study }

        let words = study.words.filter { appears($0, in: study.original) }.map { word -> StudyWord in
            let lemma = repairedLemma(for: word)

            // The lyric's own spelling is consulted first; only if the written
            // form is unknown does the model's dictionary form and reading get
            // a say.
            let match = dictionary.entry(forSpelling: word.surface)
                ?? dictionary.lookup(lemma: lemma, reading: word.reading)

            guard let entry = match else {
                return StudyWord(
                    surface: word.surface,
                    dictionaryForm: lemma,
                    reading: word.reading,
                    meaningKo: word.meaningKo,
                    partOfSpeech: word.partOfSpeech,
                    jlpt: word.jlpt,
                    note: Self.sanitize(word.note, hasDictionaryLevel: false)
                )
            }

            return StudyWord(
                surface: word.surface,
                dictionaryForm: entry.l,
                reading: entry.r,
                // The model's gloss is kept: it is written for this line's
                // context, whereas the dictionary gloss is generic.
                meaningKo: word.meaningKo.isEmpty ? entry.k : word.meaningKo,
                // Only the curated tier knows these; for imported words the
                // model's guess is the best available answer.
                partOfSpeech: entry.partOfSpeech ?? word.partOfSpeech,
                jlpt: entry.jlpt ?? word.jlpt,
                note: Self.sanitize(word.note, hasDictionaryLevel: entry.jlpt != nil)
            )
        }

        return LineStudy(
            lineIndex: study.lineIndex,
            original: study.original,
            translationKo: study.translationKo,
            words: words,
            grammar: study.grammar,
            engine: study.engine
        )
    }

    /// Rejects vocabulary the line does not actually contain.
    ///
    /// A small model will occasionally answer about a word that is nowhere in
    /// the lyric. Every card in this app claims "this is in the song you are
    /// listening to", so a card that fails that claim is worse than a missing
    /// one — and unlike the model's judgements, presence is checkable.
    private func appears(_ word: StudyWord, in line: String) -> Bool {
        for form in [word.surface, word.dictionaryForm] where !form.isEmpty {
            if line.contains(form) { return true }

            // Conjugated forms only share their stem with the dictionary form:
            // 帰る appears verbatim, but 忘れる appears as 忘れた. The stem is
            // therefore allowed to stand in — but only for something short
            // enough to be a single word.
            //
            // Without the length bound the model can glue a whole clause
            // together (取り帰るように out of 取りに帰るように) and have it
            // admitted on the strength of one shared kanji. Real headwords in
            // lyrics do not run past five characters; longer strings that are
            // not literally in the line are phrases, not vocabulary.
            guard form.count <= Self.maximumHeadwordLength else { continue }
            let stem = String(form.prefix(while: { $0.isKanji }))
            if !stem.isEmpty, line.contains(stem) { return true }
        }
        return false
    }

    private static let maximumHeadwordLength = 5

    private static func sanitize(_ note: String, hasDictionaryLevel: Bool) -> String {
        guard isKorean(note) else { return "" }
        let cleaned = strippingSchemaTalk(note)
        return hasDictionaryLevel ? strippingLevelClaims(cleaned) : cleaned
    }

    /// Drops notes the model wrote in the wrong language.
    ///
    /// The instructions ask for Korean, and the model mostly complies — but it
    /// sometimes answers in Japanese, and a Japanese explanation of a Japanese
    /// word is no help to the reader it was written for. Presence of Hangul is
    /// the whole test: a genuine Korean note cannot lack it.
    private static func isKorean(_ note: String) -> Bool {
        guard !note.isEmpty else { return true }
        return note.unicodeScalars.contains {
            (0xAC00...0xD7A3).contains($0.value) || (0x3130...0x318F).contains($0.value)
        }
    }

    /// Drops notes that talk about JLPT levels.
    ///
    /// The model volunteers level trivia — "N5에서 N1로 올라간 어휘" — that is
    /// usually invented, and once the dictionary has set the level the note
    /// would contradict the chip sitting right next to it.
    private static func strippingLevelClaims(_ note: String) -> String {
        note.contains(/[Nn][1-5]/) ? "" : note
    }

    /// Drops notes that quote the generation schema back at the user.
    ///
    /// Guided generation puts field names in the prompt, and the model
    /// occasionally answers with them — "dictionaryForm은 'ゆめ'입니다" is a
    /// leak of the plumbing, not an explanation.
    private static func strippingSchemaTalk(_ note: String) -> String {
        let leaks = ["dictionaryForm", "surface", "meaningKo", "partOfSpeech", "jlpt", "reading"]
        return leaks.contains(where: note.contains) ? "" : note
    }

    /// Recovers the written form when the model answered with kana.
    ///
    /// Only applied when the surface form ends in kanji: 夢/ゆめ is a
    /// reading-for-form mix-up worth fixing, but 忘れた/わすれる is a correct
    /// de-inflection that must be left alone.
    private func repairedLemma(for word: StudyWord) -> String {
        let lemma = word.dictionaryForm
        guard !lemma.containsKanji,
              lemma == word.reading,
              let last = word.surface.last,
              last.isKanji
        else { return lemma }
        return word.surface
    }

    /// Walks the whole song one line at a time.
    ///
    /// Sequential rather than concurrent: the on-device model serialises
    /// requests anyway, and doing it in order means the progress bar matches
    /// what the user sees filling in.
    public func analyzeAll(
        lyrics: Lyrics,
        songTitle: String,
        artist: String,
        onProgress: @MainActor (Int, Int) -> Void = { _, _ in }
    ) async {
        let pending = pendingLines(in: lyrics)
        for (offset, line) in pending.enumerated() {
            if Task.isCancelled { return }
            await analyze(
                lineIndex: line.id,
                in: lyrics,
                songTitle: songTitle,
                artist: artist
            )
            onProgress(offset + 1, pending.count)
        }
    }

}
