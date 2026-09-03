import Foundation
// For the refusal cases only — the model itself lives behind OnDeviceSensei.
import FoundationModels
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
    /// The system translator, injected so the rules around it can be tested
    /// without one.
    private let translate: @MainActor (String) async -> String?

    /// Lines the model refused, keyed by their text.
    ///
    /// A guardrail refusal is deterministic — the same words get the same
    /// refusal — so asking again is a model call spent on a known answer. It
    /// happens more than it sounds like it would: J-pop is full of parting and
    /// death, and 「夜に駆ける」 alone tripped the guardrail three times in one
    /// nine-line run. Those are the lines that made the song slow.
    ///
    /// Keyed by text rather than index so a repeated chorus line is only
    /// refused once. Cleared with the rest of the scope when the song changes.
    private var refusedByModel: Set<String> = []

    /// Why the model did not answer, per line.
    ///
    /// The fallback is silent by design — a reader does not need to hear that
    /// a guardrail fired — but three separate investigations today ended with a
    /// throwaway probe rebuilt to ask the same question. Kept in memory, wiped
    /// with the song, read by the report.
    public private(set) var lastFailure: [Int: ModelFailure] = [:]
    private let dictionary: DictionarySensei
    /// Used to read the line the way the line reads, rather than the way the
    /// model guessed it.
    private let tokenizer = JapaneseTokenizer()
    /// Whether the on-device model is there at all.
    private let modelIsAvailable: Bool

    /// Which of the two analyses runs.
    ///
    /// Settable, and changing it clears the results the other mode produced so
    /// the song is answered again by the newly chosen one. Only *its* results:
    /// switching to quick keeps the model's answers, because a mode that
    /// discarded better work to be fast would be a strange thing to offer.
    public var depth: AnalysisDepth {
        didSet {
            guard depth != oldValue else { return }
            if depth == .deep {
                // The dictionary's answers are exactly what deep mode is meant
                // to improve on, so they stop counting as answers. The system
                // translator's are dropped with them: it filled the sentence
                // but left the words as the dictionary had them.
                entries = entries.filter { $0.value.engine == .onDevice }
            }
        }
    }

    /// Whether the model will be asked, which is what decides whether a
    /// dictionary result is an answer or a failure.
    /// Asked of `modelIsAvailable` rather than of `onDevice`, which are the
    /// same thing in the app and deliberately not in a test: the seam claims
    /// availability without a model instance, because the rules about what the
    /// model's absence means are exactly what needs checking.
    private var usesModel: Bool { modelIsAvailable && depth == .deep }

    public init(dictionary: DictionarySensei = DictionarySensei()) {
        self.dictionary = dictionary
        let reason = OnDeviceSensei.availability
        self.unavailability = reason
        self.onDevice = reason == nil ? OnDeviceSensei() : nil
        self.modelIsAvailable = reason == nil
        self.depth = AnalysisDepthPreference.resolved(modelIsAvailable: reason == nil)
        self.translate = { await PlainTranslator.shared.translate($0) }
    }

    /// Test seam: the model cannot be summoned in a test run, but the rules
    /// about what its absence means still need checking.
    init(
        dictionary: DictionarySensei,
        modelIsAvailable: Bool,
        depth: AnalysisDepth = .deep,
        translate: @escaping @MainActor (String) async -> String? = { _ in nil }
    ) {
        self.translate = translate
        self.dictionary = dictionary
        self.onDevice = nil
        self.unavailability = modelIsAvailable ? nil : .deviceNotEligible
        self.modelIsAvailable = modelIsAvailable
        self.depth = modelIsAvailable ? depth : .quick
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
        refusedByModel.removeAll()
        lastFailure.removeAll()
        // The model's own transcript is state too, and it outlives this cache:
        // one session answers several lines now, so without this the new song's
        // opening lines are answered with the old song's questions still in
        // context.
        onDevice?.startFresh()
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

        return await produce(
            text: text,
            lineIndex: lineIndex,
            in: lyrics,
            songTitle: songTitle,
            artist: artist,
            useModel: usesModel
        )
    }

    /// A better reading of one line, whatever mode the song was analysed in.
    ///
    /// This is what makes the fast mode worth choosing rather than merely
    /// enduring. Quick gives the whole song in seconds, and most lines only ever
    /// need that much — but the one line the reader stops on, the one they came
    /// back to the song for, deserves the model. Asking for it a line at a time
    /// costs seconds instead of the minutes a whole song costs.
    ///
    /// The cache is deliberately not consulted: a quick answer for this line is
    /// already settled by `isFinal`, and being asked to improve it is precisely
    /// a request to ignore that.
    /// - Returns: nil when there is no model to ask, or the line is not there.
    @discardableResult
    public func deepen(
        lineIndex: Int,
        in lyrics: Lyrics,
        songTitle: String,
        artist: String
    ) async -> LineStudy? {
        guard modelIsAvailable else { return nil }
        guard let line = lyrics.lines.first(where: { $0.id == lineIndex }) else { return nil }
        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard !inFlight.contains(lineIndex) else { return entries[lineIndex] }

        // The memo is dropped for this line. It exists to stop a background
        // pass spending calls on an answer already known — but this is not a
        // background pass, it is someone tapping a button, and an explicit
        // request that silently does nothing is worse than a wasted call. If
        // the guardrail fires again the memo is simply written back.
        refusedByModel.remove(text)

        return await produce(
            text: text,
            lineIndex: lineIndex,
            in: lyrics,
            songTitle: songTitle,
            artist: artist,
            useModel: true
        )
    }

    /// Whether a line has an answer that the model could improve on.
    ///
    /// Not merely "is there a model": a line the model already answered has
    /// nothing better coming, and offering to redo it would promise something
    /// that is not on offer.
    public func canDeepen(_ lineIndex: Int) -> Bool {
        guard modelIsAvailable, !inFlight.contains(lineIndex) else { return false }
        guard let study = entries[lineIndex] else { return false }
        return study.engine != .onDevice
    }

    /// Runs one line through one of the two engines and files the result.
    private func produce(
        text: String,
        lineIndex: Int,
        in lyrics: Lyrics,
        songTitle: String,
        artist: String,
        useModel: Bool
    ) async -> LineStudy? {
        inFlight.insert(lineIndex)
        defer { inFlight.remove(lineIndex) }

        let result: LineStudy
        if let onDevice, useModel, !refusedByModel.contains(text) {
            do {
                result = try await onDevice.analyze(
                    line: text,
                    lineIndex: lineIndex,
                    previous: lyrics.lines.first { $0.id == lineIndex - 1 }?.text,
                    next: lyrics.lines.first { $0.id == lineIndex + 1 }?.text,
                    songTitle: songTitle,
                    artist: artist,
                    glossary: dictionary.glossary(for: text)
                )
            } catch let error as LanguageModelSession.GenerationError {
                // A refusal is about these words and will not change on a
                // second asking. Anything else — a busy system, a moment's
                // failure — is worth another attempt on the next pass.
                switch error {
                case .guardrailViolation:
                    refusedByModel.insert(text)
                    lastFailure[lineIndex] = .guardrail
                case .refusal:
                    refusedByModel.insert(text)
                    lastFailure[lineIndex] = .refused
                case .exceededContextWindowSize:
                    lastFailure[lineIndex] = .contextWindow
                case .assetsUnavailable:
                    lastFailure[lineIndex] = .assetsMissing
                case .rateLimited:
                    lastFailure[lineIndex] = .rateLimited
                case .concurrentRequests:
                    lastFailure[lineIndex] = .concurrent
                case .decodingFailure:
                    lastFailure[lineIndex] = .decoding
                default:
                    lastFailure[lineIndex] = .other
                }
                result = dictionary.analyze(line: text, lineIndex: lineIndex)
            } catch {
                lastFailure[lineIndex] = .other
                result = dictionary.analyze(line: text, lineIndex: lineIndex)
            }
        } else {
            result = dictionary.analyze(line: text, lineIndex: lineIndex)
        }

        var refined = Self.learnable(refine(result))

        // Grammar, in both modes, from matching the line rather than asking.
        // The model stopped being asked for grammar notes — the field came back
        // empty on most lines and an unused field still costs the output it is
        // generated into — which left the collection screen with no supply at
        // all. Matching restores it for nothing, and it is the same trade the
        // rest of this file makes: the model for judgement, fixed data for
        // facts. Only when nothing is there already, so a song analysed by an
        // older build keeps the tailored notes it was given.
        if refined.grammar.isEmpty {
            let matched = GrammarPatterns.matches(in: refined.original)
            if !matched.isEmpty {
                refined = LineStudy(
                    lineIndex: refined.lineIndex,
                    original: refined.original,
                    translationKo: refined.translationKo,
                    words: refined.words,
                    grammar: matched,
                    engine: refined.engine
                )
            }
        }

        // Nothing better is coming for this line, so fill it now rather than
        // leaving it blank. Where the model *is* being asked, this waits until
        // it has had its passes — see `analyzeAll`.
        // A line the model refused is in the same position as a device with no
        // model: asking again is spending a call on an answer already known.
        if refined.translationKo.isEmpty, !useModel || refusedByModel.contains(text) {
            refined = await translated(refined)
        }
        // A failed attempt must not cost the reader what they already had.
        //
        // The model's failure path falls back to the dictionary, which has no
        // translation — so a line that already carried one, asked to be read
        // more carefully and refused, would come back *worse* than before. That
        // is a plain loss caused by asking for an improvement, and it is exactly
        // what `deepen` invites people to do.
        //
        // Only compared on the translation. Words and grammar come from the
        // dictionary either way, so there is nothing to lose there.
        if refined.translationKo.isEmpty,
           let existing = entries[lineIndex],
           !existing.translationKo.isEmpty {
            return existing
        }

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
        // Quick mode has already done everything it can for this line, whether
        // or not that produced a translation — the system translator can be off,
        // or have no language pack, and there is nothing else to try.
        guard usesModel else { return true }
        // A translation settles it, but only when something other than the
        // dictionary produced the line. Without that second clause a song
        // analysed in quick mode would look finished after switching to deep,
        // and the model would never be asked about it.
        return !study.translationKo.isEmpty && study.engine != .dictionary
    }

    // MARK: - Refinement

    /// Corrects the two things a 3B on-device model reliably gets wrong.
    ///
    /// It is good at context — spotting that 「〜てる」 is 「〜ている」, rendering
    /// a line as natural Korean — and unreliable at recall: it mislabels JLPT
    /// levels and sometimes writes the *reading* into the dictionary-form
    /// field. Both are facts, not judgements, so the bundled dictionary
    /// overrides the model wherever it has an entry.
    /// Whether an answer can be shown to the reader as the Korean line.
    ///
    /// A Korean sentence contains Hangul. The model sometimes returns the lyric
    /// itself instead of translating it, and that answer is worse than none:
    /// `isFinal` only asks whether a translation is non-empty, so an echoed
    /// line is written to the record as a settled result and the line is never
    /// asked about again. Six of nine lines came back that way in one
    /// whole-song run.
    ///
    /// Hangul anywhere is enough. 「페ンス 너머로」 left katakana in the middle,
    /// which is a bad translation rather than a non-translation — the reader is
    /// better served by seeing it, and the report counts it separately.
    public nonisolated static func isUsableTranslation(_ translation: String) -> Bool {
        let letters = unquotedLetters(in: translation)
        // Hangul has to be the bulk of it, not merely present. Asking only
        // whether there was any let 「가 fence across from each other.」 through
        // on the strength of one character.
        return letters.hangul > 0
            && letters.japanese == 0
            && letters.hangul >= letters.latin
    }

    /// Counts the letters outside quotation marks, by script.
    ///
    /// Quoted text is excluded on purpose, and both exclusions matter. The
    /// lyric 「「さよなら」だけだった」 quotes a word, so a translation that quotes
    /// it back is showing the reader what was said — and a Korean line quoting
    /// the song's own English hook is right even when the quote is longer than
    /// the sentence around it.
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

    /// Drops what there is nothing to learn from, whichever engine produced it.
    ///
    /// Applied outside the model-only refinement below, and that placement is
    /// the point: the dictionary path used to return its words untouched, so on
    /// a device without the model an English line handed back English "words"
    /// with invented readings, and they went into the review schedule.
    ///
    /// A line with no Japanese in it keeps its translation and loses everything
    /// else — its words are not Japanese words, and a grammar note about an
    /// English phrase is the model filling in a form it was handed.
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

        // An answer that is not Korean is cleared rather than kept. Emptying it
        // is what keeps the line unsettled, so the next pass asks again instead
        // of the record freezing the lyric in as its own translation. The words
        // survive — they were grounded in the line and are worth showing.
        let translation = Self.isUsableTranslation(study.translationKo) ? study.translationKo : ""

        return LineStudy(
            lineIndex: study.lineIndex,
            original: study.original,
            translationKo: translation,
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
        let total = pendingLines(in: lyrics).count
        guard total > 0 else { return }

        // Repeated while it is getting somewhere. One pass used to be the whole
        // run, so a line the model dropped — a moment's guardrail, a busy
        // system, a context window that overflowed — stayed blank until the
        // reader found the menu item for it. Looping until nothing is pending
        // would never return on a line that always fails, so the condition is
        // progress rather than completion: the first pass that settles nothing
        // ends the run. At most one pass per line, so it terminates.
        while !Task.isCancelled {
            let before = pendingLines(in: lyrics).count
            guard before > 0 else { return }

            await onePass(lyrics: lyrics, songTitle: songTitle, artist: artist) {
                // Lines that now have an answer, not attempts made. A bar that
                // fills while every line is failing says the opposite of what
                // is happening, and the remaining-time estimate is computed off
                // this number.
                onProgress(total - self.pendingLines(in: lyrics).count, total)
            }

            if pendingLines(in: lyrics).count >= before { break }
        }

        // Whatever the model never managed. Last, deliberately: a line the
        // model can answer is worth more than a literal rendering of it, so the
        // translator only gets what is left after the model has stopped making
        // progress.
        for line in pendingLines(in: lyrics) {
            if Task.isCancelled { return }
            guard let study = entries[line.id] else { continue }
            let filled = await translated(study)
            guard !filled.translationKo.isEmpty else { continue }
            entries[line.id] = filled
            onProgress(total - pendingLines(in: lyrics).count, total)
        }
    }

    /// The same study with a translation from the system translator, when it
    /// can give one that is actually Korean.
    ///
    /// The words and their meanings are left exactly as they were — they came
    /// from the bundled dictionary and are the part this path does well. Only
    /// the sentence is new, and the engine says so, because "사전" would be a
    /// lie about where it came from and the report counts on the difference.
    private func translated(_ study: LineStudy) async -> LineStudy {
        guard let text = await translate(study.original),
              Self.isUsableTranslation(text)
        else { return study }

        return LineStudy(
            lineIndex: study.lineIndex,
            original: study.original,
            translationKo: text,
            words: study.words,
            grammar: study.grammar,
            engine: .plainTranslation
        )
    }

    /// One attempt at each line that still needs one.
    private func onePass(
        lyrics: Lyrics,
        songTitle: String,
        artist: String,
        onLine: @MainActor () -> Void
    ) async {
        // Grouped by the text itself. A song is not a list of distinct lines —
        // the chorus comes back — and the model has nothing new to say the
        // second time it sees the same words.
        var groups: [String: [LyricLine]] = [:]
        var order: [String] = []
        for line in pendingLines(in: lyrics) {
            let key = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(line)
        }

        for key in order {
            guard let lines = groups[key], let first = lines.first else { continue }
            if Task.isCancelled { return }

            let study = await analyze(
                lineIndex: first.id,
                in: lyrics,
                songTitle: songTitle,
                artist: artist
            )

            // The repeats are filled in from the one answer, each under its own
            // index so the lyric view and the record still address them by line.
            if let study {
                for repeated in lines.dropFirst() {
                    entries[repeated.id] = study.moved(to: repeated.id)
                }
            }

            onLine()
        }
    }

}
