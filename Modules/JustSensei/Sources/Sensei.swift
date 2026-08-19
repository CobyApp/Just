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
    /// Used to read the line the way the line reads, rather than the way the
    /// model guessed it.
    private let tokenizer = JapaneseTokenizer()
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

        // Segmented once for the whole line, then consulted per candidate.
        let tokens = tokenizer.tokenize(study.original)

        let words = study.words.filter { appears($0, in: study.original) }.compactMap { word -> StudyWord? in
            // What the line says this candidate is, before anything else gets an
            // opinion. Grammar stuck to the tail comes off, and a candidate that
            // is nothing but grammar goes away.
            let grounded = Self.grounding(for: word.surface, in: tokens)
            if case .glue = grounded { return nil }

            // The lyric's own spelling for the card, the trimmed form for the
            // dictionary. One value cannot be both: `surface` is quoted back to
            // the reader and blanked out by cloze questions, so it has to stay
            // exactly what the singer wrote.
            var surface = word.surface
            var headword: String?
            var lineReading: String?
            if case .word(let asSung, let trimmed, let reading) = grounded {
                surface = asSung
                headword = trimmed
                lineReading = reading
            }

            let lemma = repairedLemma(for: word)

            // The lyric's own spelling is consulted first; only if the written
            // form is unknown does the model's dictionary form and reading get
            // a say. Trimming above is what lets this hit at all for 「本当は」:
            // 「本当」 is in the dictionary, the two together never could be.
            // The line's reading is handed to the dictionary, not just kept for
            // display: it is what tells 僕/ぼく from 僕/しもべ. Without it,
            // trimming 「僕も」 to 「僕」 started hitting the dictionary and getting
            // back "a servant".
            let match = dictionary.entry(forSpelling: headword ?? surface, reading: lineReading)
                ?? dictionary.lookup(lemma: lemma, reading: lineReading ?? word.reading)

            guard let entry = match else {
                return StudyWord(
                    surface: surface,
                    // With no entry to name the headword, the line's own reading
                    // is a better answer than the model's: it knows 一言 is
                    // ひとこと here, where the model offered そのいかん.
                    dictionaryForm: headword ?? lemma,
                    reading: lineReading ?? word.reading,
                    meaningKo: word.meaningKo,
                    partOfSpeech: word.partOfSpeech,
                    jlpt: word.jlpt,
                    note: Self.sanitize(word.note, hasDictionaryLevel: false)
                )
            }

            return StudyWord(
                surface: surface,
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
            grammar: study.grammar.filter { Self.grammarAppears($0.pattern, in: study.original) },
            engine: study.engine
        )
    }

    /// What the line's own segmentation says a candidate really is.
    enum Grounding: Equatable {
        /// A word the line contains.
        ///
        /// Two forms, because they answer different questions. `surface` is what
        /// the singer wrote, glue and all, and it is what the card shows and what
        /// a cloze question blanks out. `headword` has the grammar trimmed off its
        /// tail, and it is what the dictionary is asked about.
        ///
        /// Conflating them truncated the lyric: 「疲れた」 became 「疲れ」, so a card
        /// claimed the song contained a form it did not, and a cloze question
        /// came out as 「___たよなんて」 with the tail left dangling.
        case word(surface: String, headword: String, reading: String)
        /// Nothing but grammar — 「で」, 「も」, 「んだ」.
        case glue
        /// Does not line up with the line's tokens; leave the candidate alone.
        case unknown
    }

    /// Grounds a candidate in the line the singer actually sang.
    ///
    /// `CFStringTokenizer` is the only on-device API that reads Japanese *in
    /// context* — it knows 一言 is ひとこと and 空 is そら here — and until now that
    /// knowledge was thrown away on the model path and used only in the offline
    /// fallback. The model, meanwhile, offered 「そのいかん」 for 「その一言」 and
    /// pasted particles onto headwords: 「本当は」, 「僕も」, and 「で」 on its own.
    ///
    /// Trimming happens before the dictionary is consulted, which also lifts the
    /// hit rate: 「本当」 is in the dictionary where 「本当は」 never could be.
    ///
    /// Part of speech is deliberately not used. `NLTagger` labels every token in
    /// these lyrics `OtherWord`, so a rule that asked it to point out particles
    /// would quietly never fire. Segmentation is what it actually knows.
    nonisolated static func grounding(
        for surface: String,
        in tokens: [JapaneseToken]
    ) -> Grounding {
        let target = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return .unknown }

        guard let range = tokenRange(covering: target, in: tokens) else {
            return .unknown
        }

        let matched = Array(tokens[range])

        // The same rule the tokenizer already uses to spot glue: one hiragana on
        // its own is grammar, not vocabulary. Trimmed off the headword only —
        // the lyric keeps whatever it wrote.
        var kept = matched
        while let last = kept.last, isGlue(last.surface) {
            kept.removeLast()
        }
        guard !kept.isEmpty else { return .glue }

        let headword = kept.map(\.surface).joined()
        guard !grammaticalForms.contains(headword) else { return .glue }

        return .word(
            surface: matched.map(\.surface).joined(),
            headword: headword,
            reading: kept.map(\.reading).joined()
        )
    }

    private nonisolated static func isGlue(_ surface: String) -> Bool {
        surface.count == 1 && surface.allSatisfy(\.isHiragana)
    }

    /// Kana that carry grammar rather than vocabulary.
    ///
    /// One kana is glue by its shape. These are longer but no more a headword for
    /// a vocabulary card, and this app has already decided where patterns go: the
    /// grammar notes. Left in the word list they also attract wrong dictionary
    /// matches, because a reading is all it takes — 「だけ」 resolved to 丈, a
    /// length, on the strength of a shared reading.
    ///
    /// Nothing is lost by moving them: 「なんて」 is in the line, so a grammar note
    /// about it survives the presence check that guards those.
    ///
    /// Deliberately short, and meant to grow from what the report shows rather
    /// than from guesses about what a model might say.
    private nonisolated static let grammaticalForms: Set<String> = [
        "だけ", "って", "なんて", "よう", "たい", "ない", "だ", "です",
        "ます", "ません", "ました", "から", "けど", "のに", "ので",
        "とか", "でも", "しか", "ほど", "など",
    ]

    /// The run of tokens whose surfaces spell `target`, if any.
    private nonisolated static func tokenRange(
        covering target: String,
        in tokens: [JapaneseToken]
    ) -> Range<Int>? {
        for start in tokens.indices {
            var joined = ""
            for end in start..<tokens.count {
                joined += tokens[end].surface
                if joined == target { return start..<(end + 1) }
                if joined.count >= target.count { break }
            }
        }
        return nil
    }

    /// Whether a grammar note is about something the line actually contains.
    ///
    /// The same rule the word list has always lived by, which the grammar notes
    /// were never held to. Measured over six lines, five of the patterns the
    /// model offered were absent from the lyric — 「〜てしまう」 turned up again and
    /// again on lines containing nothing of the kind, with the line's own
    /// translation pasted in as the explanation.
    ///
    /// Containment is strict on purpose. A pattern written in dictionary form for
    /// a conjugated occurrence will be dropped along with the inventions, and
    /// that is the trade this app already makes for vocabulary: a note claiming
    /// the song contains something it does not is worse than a missing note.
    nonisolated static func grammarAppears(_ pattern: String, in line: String) -> Bool {
        let stripped = pattern
            .replacingOccurrences(of: "〜", with: "")
            .replacingOccurrences(of: "～", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return false }
        return line.contains(stripped)
    }

    /// Rejects vocabulary the line does not actually contain.
    ///
    /// A small model will occasionally answer about a word that is nowhere in
    /// the lyric. Every card in this app claims "this is in the song you are
    /// listening to", so a card that fails that claim is worse than a missing
    /// one — and unlike the model's judgements, presence is checkable.
    func appears(_ word: StudyWord, in line: String) -> Bool {
        for form in [word.surface, word.dictionaryForm] where !form.isEmpty {
            // The length bound governs every candidate, not just the stem match
            // below. Being literally present proves nothing about wordhood when
            // the candidate *is* the line: the model sometimes answers with the
            // whole sentence, which sailed through `contains` and became a card
            // whose headword was the lyric, whose meaning was the lyric's
            // translation, and whose reading no furigana aligner could place.
            //
            // Real headwords in lyrics do not run past five characters; longer
            // strings are phrases, and phrases belong in the grammar notes.
            guard form.count <= Self.maximumHeadwordLength else { continue }

            if line.contains(form) { return true }

            // Conjugated forms only share their stem with the dictionary form:
            // 帰る appears verbatim, but 忘れる appears as 忘れた, so the stem is
            // allowed to stand in. Without the bound above, the model could glue
            // a whole clause together (取り帰るように out of 取りに帰るように)
            // and have it admitted on the strength of one shared kanji.
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

        // Grouped by the text itself. A song is not a list of distinct lines —
        // the chorus comes back — and the model has nothing new to say the
        // second time it sees the same words.
        var groups: [String: [LyricLine]] = [:]
        var order: [String] = []
        for line in pending {
            let key = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(line)
        }

        var done = 0
        for key in order {
            guard let lines = groups[key], let first = lines.first else { continue }
            if Task.isCancelled { return }

            let study = await analyze(
                lineIndex: first.id,
                in: lyrics,
                songTitle: songTitle,
                artist: artist
            )
            done += 1

            // The repeats are filled in from the one answer, each under its own
            // index so the lyric view and the record still address them by line.
            if let study {
                for repeated in lines.dropFirst() {
                    entries[repeated.id] = study.moved(to: repeated.id)
                    done += 1
                }
            }

            onProgress(min(done, pending.count), pending.count)
        }
    }

}
