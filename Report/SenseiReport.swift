import Foundation
import JustCore
import JustLyrics
import Testing

@testable import JustSensei

/// Runs the real on-device analyser over a fixed set of lines and prints what it
/// produced, so a change to the prompt or the refinement rules can be judged by
/// comparing two runs instead of squinting at two lines in the simulator.
///
/// Lives in its own target, which is what keeps it out of a normal test run and
/// what lets it run on a device: the target is hosted by the app, and a hosted
/// test target can be installed on a phone. That matters because the
/// simulator's on-device model has gone missing three times in a day, and the
/// phone in the room has a real one — being unable to measure has blocked more
/// work here than any bug.
///
/// A compile flag did the first job before. It worked, but it had to be
/// remembered, and a run without it measured nothing while looking like it had.
///
/// It asserts nothing about quality — quality is not assertable — but it does
/// count the failure modes that *are* checkable, and those counts are the thing
/// to compare between runs.
///
/// Run on the simulator:
/// ```
/// xcodebuild -workspace Just.xcworkspace -scheme JustReport \
///   -destination 'platform=iOS Simulator,name=iPhone 17' test
/// ```
///
/// Or on the phone, where the model is real:
/// ```
/// xcodebuild -workspace Just.xcworkspace -scheme JustReport \
///   -destination 'platform=iOS,name=Coby' -allowProvisioningUpdates test
/// ```
/// Serialised, and that is not a detail. Swift Testing runs tests in parallel
/// by default, so these three were asking the on-device model at the same time
/// — and the model rejects concurrent requests outright, which is why
/// `GenerationError.concurrentRequests` exists. The report was competing with
/// itself: lines fell back to the dictionary because another test held the
/// model, and one test kept taking the process down with it.
///
/// Numbers from a run that raced itself are not measurements of anything.
@Suite("해석 품질 보고서", .serialized)
@MainActor
struct SenseiReportSuite {
    /// Lines whose failures were actually observed, each with what a correct
    /// answer looks like. A baseline built from real misses rather than invented
    /// examples.
    private struct Fixture {
        let song: String
        let artist: String
        /// Consecutive lines, so `before`/`after` context is real.
        let lines: [String]
        /// Index into `lines` that the report is about.
        let target: Int
        /// What a person would accept, for the reader of the report to compare.
        let expectation: String
        /// Words that betray the translation came from somewhere other than this
        /// line — a neighbour, or the song's own name. Written by hand from
        /// failures actually seen, which is what lets a judgement be counted.
        let forbidden: [String]
    }

    private var fixtures: [Fixture] {
        let yoasobi = [
            "沈むように溶けてゆくように",
            "二人だけの空が広がる夜に",
            "「さよなら」だけだった",
            "その一言で全てが分かった",
            "日が沈み出した空と君の姿",
            "フェンス越しに重なっていた",
            "もう嫌だって 疲れたよなんて",
            "本当は僕も言いたいんだ",
        ]
        return [
            Fixture(
                song: "夜に駆ける", artist: "YOASOBI", lines: yoasobi, target: 0,
                expectation: "가라앉듯이, 녹아내리듯이 — 곡 제목(밤을 달린다)이 새어들면 실패",
                forbidden: ["달리", "달빛"]
            ),
            Fixture(
                song: "夜に駆ける", artist: "YOASOBI", lines: yoasobi, target: 1,
                expectation: "둘만의 하늘이 펼쳐지는 밤에 — 空은 하늘. '공기'는 空気와 혼동한 것",
                forbidden: ["공기"]
            ),
            Fixture(
                song: "夜に駆ける", artist: "YOASOBI", lines: yoasobi, target: 2,
                expectation: "'잘 가' 그 한마디뿐이었다 — 이웃 줄의 뜻을 가져오면 실패",
                forbidden: ["이해", "공기", "펼쳐"]
            ),
            Fixture(
                song: "夜に駆ける", artist: "YOASOBI", lines: yoasobi, target: 3,
                expectation: "그 한마디로 모든 것을 알았다 — 줄 전체가 단어 카드로 오면 실패",
                forbidden: []
            ),
            Fixture(
                song: "夜に駆ける", artist: "YOASOBI", lines: yoasobi, target: 6,
                expectation: "이제 싫다느니 지쳤다느니 — だって/なんて를 인용으로 읽어야 한다",
                forbidden: ["말하고 싶"]
            ),
            Fixture(
                song: "夜に駆ける", artist: "YOASOBI", lines: yoasobi, target: 7,
                expectation: "실은 나도 말하고 싶어 — んだ의 어감이 살아야 한다",
                forbidden: []
            ),
        ]
    }

    @Test("고정된 줄에 실제 모델을 돌려 결과를 찍는다")
    func writeReport() async {
        let sensei = Sensei()
        var report = ""
        var flags = Flags()

        report += "# 해석 품질 보고서\n\n"
        report += "엔진: \(sensei.usesOnDeviceModel ? "온디바이스 모델" : "사전 (모델 없음)")\n"
        if !sensei.usesOnDeviceModel {
            report += "\n> 모델을 쓸 수 없어 사전으로 대체됐습니다. "
            report += "이 보고서로는 프롬프트 변경을 판단할 수 없습니다.\n"
        }
        report += "\n"

        for fixture in fixtures {
            let lyrics = Lyrics(
                lines: fixture.lines.enumerated().map { index, text in
                    LyricLine(id: index, time: Double(index) * 4, text: text)
                },
                isSynced: true,
                source: "fixture"
            )

            // A fresh scope per line so nothing carries over between fixtures.
            sensei.reset(for: "\(fixture.song)#\(fixture.target)")

            let study = await sensei.analyze(
                lineIndex: fixture.target,
                in: lyrics,
                songTitle: fixture.song,
                artist: fixture.artist
            )

            report += "## \(fixture.lines[fixture.target])\n\n"
            report += "- 기대: \(fixture.expectation)\n"

            guard let study else {
                report += "- **결과 없음**\n\n"
                continue
            }

            flags.count(study, line: fixture.lines[fixture.target], forbidden: fixture.forbidden)

            report += "- 번역: \(study.translationKo.isEmpty ? "(없음)" : study.translationKo)\n"
            report += "- 엔진: \(study.engine.label)\n"
            report += "- 단어 \(study.words.count)개\n"
            for word in study.words {
                report += "  - `\(word.dictionaryForm)`"
                report += " (가사: \(word.surface), 읽기: \(word.reading))"
                report += " — \(word.meaningKo.isEmpty ? "(뜻 없음)" : word.meaningKo)"
                report += " · \(word.jlpt.rawValue) · \(word.partOfSpeech.rawValue)"
                if !word.note.isEmpty { report += "\n    - 노트: \(word.note)" }
                report += "\n"
            }
            if study.grammar.isEmpty {
                report += "- 문법: (없음)\n"
            } else {
                for note in study.grammar {
                    report += "- 문법 `\(note.pattern)`: \(note.explanationKo)\n"
                }
            }
            report += "\n"
        }

        report += flags.summary()

        print("=== SENSEI REPORT BEGIN ===")
        print(report)
        print("=== SENSEI REPORT END ===")
    }

    /// The same lines again, but run the way the app runs them.
    ///
    /// The per-line report above resets the scope for every fixture, so each
    /// line is answered by a session that knows nothing else. That is not what
    /// happens to a reader: opening a song runs one pass over every line, and
    /// one model session answers several of them in a row. Whatever a shared
    /// transcript does to the answers it does here and nowhere else — and the
    /// repeated-line copying only exists on this path too.
    ///
    /// This is the measurement that matters for a change to batching; the one
    /// above is the measurement that matters for a change to the prompt. The
    /// per-line report cannot see this path at all, which is how a session that
    /// overflowed its context window after three lines — failing every line
    /// after it — went unnoticed while the report said nothing was wrong.
    @Test("전곡을 한 번에 돌려 이웃 줄 침범을 센다")
    func writeWholeSongReport() async {
        let sensei = Sensei()
        // A chorus line brought back, so the repeat path runs: it must reappear
        // as a copy, and must not be counted as bleed.
        let texts = [
            "沈むように溶けてゆくように",
            "二人だけの空が広がる夜に",
            "「さよなら」だけだった",
            "その一言で全てが分かった",
            "日が沈み出した空と君の姿",
            "フェンス越しに重なっていた",
            "もう嫌だって 疲れたよなんて",
            "本当は僕も言いたいんだ",
            "「さよなら」だけだった",
        ]
        // The same words the per-line fixtures forbid. Without them the run
        // reports zero because it asked nothing, which reads exactly like a run
        // that asked and found nothing.
        let forbidden: [String: [String]] = [
            "沈むように溶けてゆくように": ["달리", "달빛"],
            "二人だけの空が広がる夜に": ["공기"],
            "「さよなら」だけだった": ["이해", "공기", "펼쳐"],
            "もう嫌だって 疲れたよなんて": ["말하고 싶"],
        ]

        let lyrics = Lyrics(
            lines: texts.enumerated().map { index, text in
                LyricLine(id: index, time: Double(index) * 4, text: text)
            },
            isSynced: true,
            source: "fixture"
        )

        sensei.reset(for: "wholesong")

        // Timed, because speed is a thing being traded against accuracy now and
        // the trade cannot be judged without both numbers in the same report.
        var perLine: [TimeInterval] = []
        var lastTick = Date.now
        let started = lastTick
        await sensei.analyzeAll(lyrics: lyrics, songTitle: "夜に駆ける", artist: "YOASOBI") { _, _ in
            let now = Date.now
            perLine.append(now.timeIntervalSince(lastTick))
            lastTick = now
        }
        let elapsed = Date.now.timeIntervalSince(started)

        var report = "# 전곡 한 번에 — 이웃 줄 침범\n\n"
        report += "엔진: \(sensei.usesOnDeviceModel ? "온디바이스 모델" : "사전 (모델 없음)")\n\n"

        var flags = Flags()
        let dictionary = DictionarySensei()
        var carried: [String] = []

        for line in lyrics.lines {
            guard let study = sensei.cached(line.id) else {
                report += "- \(line.text) — **결과 없음**\n"
                continue
            }
            flags.count(study, line: line.text, forbidden: forbidden[line.text] ?? [])

            // Words the line before had and this one does not. If one of their
            // meanings turns up in this translation, it came from next door.
            //
            // The character-overlap check cannot see this: 「「さよなら」だけだった」
            // came back as 「작별 인사만 있었던 밤에」, and 「밤에」 overlaps the
            // previous line's translation by two characters — far under any
            // threshold that would not also flag every coincidence. The
            // dictionary can see it, because it knows 夜 means 밤 and that this
            // line has no 夜 in it.
            let previous = lyrics.lines.first { $0.id == line.id - 1 }?.text
            if let previous {
                let mine = Set(dictionary.meanings(in: line.text))
                for meaning in dictionary.meanings(in: previous) where !mine.contains(meaning) {
                    // First sense only: a dictionary entry reads 「밤」 or
                    // 「길이, 키」, and the whole string rarely appears verbatim.
                    let head = meaning.split(separator: ",").first.map(String.init) ?? meaning
                    guard head.count >= 2, study.translationKo.contains(head) else { continue }
                    carried.append("\(line.text) ← \(head)")
                    flags.carriedFromNeighbour += 1
                    break
                }
            }

            let translation = study.translationKo.isEmpty ? "(없음)" : study.translationKo
            report += "- \(line.text)\n  - \(translation)\n"
        }

        if !carried.isEmpty {
            report += "\n앞 줄에서 넘어온 말:\n"
            for entry in carried { report += "- \(entry)\n" }
        }

        // The repeat must be a copy of the line it repeats, not a second guess.
        let first = sensei.cached(2)?.translationKo ?? ""
        let repeated = sensei.cached(8)?.translationKo ?? ""
        report += "\n반복 줄 복사: "
        report += first == repeated ? "같음 (기대대로)" : "다름 — `\(first)` vs `\(repeated)`"
        report += "\n\n"
        if !sensei.lastFailure.isEmpty {
            var counts: [String: Int] = [:]
            for reason in sensei.lastFailure.values { counts[reason.label, default: 0] += 1 }
            report += "## 모델이 답하지 않은 이유\n\n"
            for (reason, count) in counts.sorted(by: { $0.value > $1.value }) {
                report += "- \(reason): \(count)\n"
            }
            report += "\n"
        }

        report += "## 속도\n\n"
        report += "| 항목 | 값 |\n|---|---|\n"
        report += "| 전체 |  \(String(format: "%.1f", elapsed))초 |\n"
        if !perLine.isEmpty {
            let sorted = perLine.sorted()
            let median = sorted[sorted.count / 2]
            report += "| 응답당 중앙값 | \(String(format: "%.2f", median))초 |\n"
            report += "| 응답 수 | \(perLine.count) |\n"
        }
        report += "\n"

        report += flags.summary()

        print("=== SENSEI WHOLE SONG BEGIN ===")
        print(report)
        print("=== SENSEI WHOLE SONG END ===")
    }

    /// What the fast mode actually produces on real lyrics.
    ///
    /// The mode is offered as a complete answer — words, grammar and a sentence
    /// — so the claim worth checking is whether the three are actually there,
    /// line by line, on lyrics rather than on a test string. It needs no model,
    /// which is the whole point: this is the one path that can be measured
    /// wherever it is run.
    ///
    /// The sentence comes from the system translator, and that is the part that
    /// may be missing here — a simulator often has Japanese-to-Korean as
    /// `.supported` rather than `.installed`, meaning a language pack that only
    /// a real screen can be asked to download. The report says which it got, so
    /// a run with no translations is not mistaken for a broken mode.
    @Test("빠른 해석이 실제 가사에서 무엇을 채우는지")
    func writeQuickModeReport() async {
        let packStatus = await PlainTranslator.shared.availability()
        let sensei = Sensei()
        sensei.depth = .quick

        var lines: [String] = []
        var withWords = 0
        var withGrammar = 0
        var withTranslation = 0
        var grammarCounts: [String: Int] = [:]
        var bare: [String] = []

        for (song, songLines) in Self.realLyrics {
            let lyrics = Lyrics(
                lines: songLines.enumerated().map { LyricLine(id: $0.offset, time: nil, text: $0.element) },
                isSynced: false,
                source: "report"
            )
            sensei.reset(for: song)

            for line in lyrics.lines {
                guard let study = await sensei.analyze(
                    lineIndex: line.id, in: lyrics, songTitle: song, artist: "-"
                ) else { continue }

                if !study.words.isEmpty { withWords += 1 }
                if !study.grammar.isEmpty { withGrammar += 1 }
                if !study.translationKo.isEmpty { withTranslation += 1 }
                for note in study.grammar { grammarCounts[note.pattern, default: 0] += 1 }
                // A line with no words and no grammar is a line the fast mode
                // had nothing to say about, which is what to go and look at.
                if study.words.isEmpty, study.grammar.isEmpty, LineScript.hasJapanese(line.text) {
                    bare.append(line.text)
                }
                lines.append(
                    "\(line.text)\n  단어 \(study.words.count) · 문법 \(study.grammar.map(\.pattern).joined(separator: " "))"
                        + (study.translationKo.isEmpty ? "" : "\n  → \(study.translationKo)")
                )
            }
        }

        let total = lines.count
        func share(_ n: Int) -> String {
            total == 0 ? "-" : "\(n)/\(total) (\(Int((Double(n) / Double(total) * 100).rounded()))%)"
        }

        var report = lines.joined(separator: "\n")
        report += "\n\n--- 빠른 해석 요약 ---\n"
        report += "줄 \(total)\n"
        report += "단어가 붙은 줄 \(share(withWords))\n"
        report += "문법이 붙은 줄 \(share(withGrammar))\n"
        report += "번역이 붙은 줄 \(share(withTranslation))  [번역 팩: \(packStatus)]\n"
        report += "아무것도 못 붙인 일본어 줄 \(bare.count)\n"
        for line in bare { report += "  · \(line)\n" }
        report += "\n패턴 출현\n"
        for (pattern, count) in grammarCounts.sorted(by: { $0.value > $1.value }) {
            report += "  \(pattern) \(count)\n"
        }

        print("=== QUICK MODE BEGIN ===")
        print(report)
        print("=== QUICK MODE END ===")
    }

    /// Consecutive lines from songs a learner would actually open. Shared by the
    /// reports that measure over real lyrics rather than over fixtures.
    static let realLyrics: [(String, [String])] = [
        ("夜に駆ける", [
            "沈むように溶けてゆくように",
            "二人だけの空が広がる夜に",
            "「さよなら」だけだった",
            "その一言で全てが分かった",
            "日が沈み出した空と君の姿",
            "フェンス越しに重なっていた",
            "もう嫌だって 疲れたよなんて",
            "本当は僕も言いたいんだ",
        ]),
        ("Lemon", [
            "夢ならばどれほどよかったでしょう",
            "今でもあなたはわたしの光",
            "暗闇であなたの背をなぞった",
            "その輪郭を鮮明に覚えている",
            "戻らない幸せがあることを",
            "最後にあなたが教えてくれた",
        ]),
        ("マリーゴールド", [
            "麦わらの帽子の君が",
            "揺れたマリーゴールドに似てる",
            "あれから七年経っても",
            "僕は君に会いたいんだ",
        ]),
    ]

    /// How much of real lyrics the bundled dictionary actually knows.
    ///
    /// This is what feeds `<words>` into the prompt, and that grounding is what
    /// fixed 空 — the model kept writing 「공기」 until the dictionary's own
    /// reading was put in front of it. Where the dictionary is blank the model
    /// is back to guessing, so the gap is worth knowing rather than assuming.
    ///
    /// Needs no model, which is why it is here: it measures on a machine where
    /// the on-device assets have gone missing, which they have all day.
    @Test("사전이 실제 가사를 얼마나 아는지")
    func writeCoverageReport() async {
        let dictionary = DictionarySensei()
        let tokenizer = JapaneseTokenizer()
        let client = LRCLIBClient()

        // Fetched rather than pasted in. Three hand-copied songs were enough to
        // find that the dictionary was missing 日 and 物; finding what is left
        // needs more lyrics than anyone wants to keep in a source file, and
        // these are the songs a learner would actually open.
        //
        // Network in a measurement is fine — it is not a test of anything, and
        // a run that cannot reach LRCLIB says so in its own numbers.
        let songs: [(artist: String, title: String)] = [
            ("YOASOBI", "夜に駆ける"), ("米津玄師", "Lemon"),
            ("Official髭男dism", "Pretender"), ("あいみょん", "マリーゴールド"),
            ("King Gnu", "白日"), ("Ado", "うっせぇわ"),
            ("YOASOBI", "アイドル"), ("Vaundy", "怪獣の花唄"),
            ("優里", "ドライフラワー"), ("back number", "水平線"),
            ("米津玄師", "KICK BACK"), ("Mrs. GREEN APPLE", "青と夏"),
            ("LiSA", "紅蓮華"), ("RADWIMPS", "前前前世"),
            ("YOASOBI", "群青"),
        ]

        var known = 0
        var missing: [String: Int] = [:]
        var reached = 0

        for song in songs {
            guard let lyrics = try? await client.lyrics(artist: song.artist, title: song.title)
            else { continue }
            reached += 1
            for line in lyrics.lines {
                for token in tokenizer.studyCandidates(in: line.text) {
                    let hit = dictionary.entry(forSpelling: token.surface, reading: token.reading)
                        ?? dictionary.lookup(lemma: token.lemma, reading: token.reading)
                    if hit != nil {
                        known += 1
                    } else {
                        missing["\(token.lemma)(\(token.reading))", default: 0] += 1
                    }
                }
            }
        }

        let total = known + missing.values.reduce(0, +)
        var report = "# 사전 커버리지\n\n"
        report += "| 항목 | 값 |\n|---|---|\n"
        report += "| 받아온 곡 | \(reached)/\(songs.count) |\n"
        report += "| 후보 단어 | \(total) |\n"
        report += "| 사전이 아는 것 | \(known) |\n"
        if total > 0 {
            report += "| 비율 | \(Int(Double(known) / Double(total) * 100))% |\n"
        }

        // Ordered by how often they come up, because that is the order worth
        // adding them in.
        report += "\n## 모르는 것 (빈도순)\n\n"
        for (word, count) in missing.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }).prefix(80) {
            report += "- \(count)회 \(word)\n"
        }

        print("=== COVERAGE BEGIN ===")
        print(report)
        print("=== COVERAGE END ===")
    }

    /// The failure modes that can be counted rather than judged.
    ///
    /// Quality is not assertable, but these are: they are properties of the
    /// output text, and their totals are what tells you whether a prompt change
    /// helped or only felt like it did.
    private struct Flags {
        var lines = 0
        var missingTranslation = 0
        var words = 0
        var kanaHeadwordForKanjiSurface = 0
        var headwordIsHalfTheLine = 0
        var headwordEndsInParticle = 0
        var missingMeaning = 0
        var noGrammar = 0
        var fabricatedGrammar = 0
        var particleOnlyWord = 0
        /// Translations with the line each came from, so the run can spot
        /// itself repeating. The line is kept because a repeated lyric is
        /// *supposed* to repeat its translation — the chorus is answered once
        /// and copied — and counting those would bury the real thing this looks
        /// for.
        var translations: [(line: String, text: String)] = []

        private static let particles: Set<Character> = ["に", "を", "が", "は", "で", "と", "へ", "も", "の"]

        var strayTranslation = 0
        var untranslatedJapanese = 0
        var dictionaryFallback = 0
        var paddedTranslation = 0
        var carriedFromNeighbour = 0

        mutating func count(_ study: LineStudy, line: String, forbidden: [String]) {
            if forbidden.contains(where: study.translationKo.contains) { strayTranslation += 1 }
            lines += 1
            // Anything but the model means the model did not answer this line —
            // the system translator filling in counts here too, because what
            // this number is for is telling a real measurement of the model
            // apart from a run where it never spoke.
            if study.engine != .onDevice { dictionaryFallback += 1 }
            if study.translationKo.isEmpty { missingTranslation += 1 }
            // Kana surviving into the Korean line means a stretch was copied
            // rather than translated — 「フェンス越しに」 came back as
            // 「페ンス를 넘어서서」. Kana rather than kanji: a Korean sentence has
            // no reason to hold either, but kanji alone would also flag a
            // legitimately quoted Chinese character.
            // Only outside quotation marks. Counting quoted Japanese made this
            // read 3 when one line was broken and two were the same repeated
            // line quoting 「さよなら」 back, exactly as the lyric does — the same
            // over-counting the bleed metric had.
            if !Sensei.isUsableTranslation(study.translationKo), !study.translationKo.isEmpty {
                untranslatedJapanese += 1
            }
            translations.append((line: line, text: study.translationKo))

            // A translation far longer than the line it renders is the model
            // padding. Measured, not guessed: 「「さよなら」だけだった」 — eleven
            // characters — came back as a conditional about parting being
            // enough, and 「沈むように溶けてゆくように」 gained an inner door that
            // is in no part of the song. Both are short lines stretched.
            //
            // A ratio rather than a length, because a long line has room for a
            // long sentence. Korean is more compact than Japanese here, so
            // twice the characters already means words were added.
            if !study.translationKo.isEmpty, !line.isEmpty,
               Double(study.translationKo.count) > Double(line.count) * 2.0 {
                paddedTranslation += 1
            }
            if study.grammar.isEmpty { noGrammar += 1 }

            // The same rule the word list already lives by: presence in the line
            // is checkable, and a pattern the line does not contain was invented.
            for note in study.grammar {
                let pattern = note.pattern.replacingOccurrences(of: "〜", with: "")
                if !pattern.isEmpty, !line.contains(pattern) { fabricatedGrammar += 1 }
            }

            for word in study.words {
                words += 1
                if word.meaningKo.isEmpty { missingMeaning += 1 }
                // The instructions forbid particles outright, so a headword that
                // is one bare kana is the model ignoring them.
                if word.dictionaryForm.count == 1,
                   let only = word.dictionaryForm.first,
                   Self.particles.contains(only) {
                    particleOnlyWord += 1
                }
                // 「夜に」 came back with 「よるに」 as its headword: a reading with a
                // particle stuck to it, which is not a word anyone can look up.
                if !word.dictionaryForm.containsKanji, word.surface.containsKanji {
                    kanaHeadwordForKanjiSurface += 1
                }
                if word.dictionaryForm.count * 2 >= line.count {
                    headwordIsHalfTheLine += 1
                }
                if let last = word.dictionaryForm.last,
                   Self.particles.contains(last),
                   word.dictionaryForm.count > 1 {
                    headwordEndsInParticle += 1
                }
            }
        }

        /// Lines whose translation repeats another line's.
        ///
        /// The model's commonest failure here is answering about the neighbour
        /// instead of the target, and when it does, two fixtures come back saying
        /// the same thing. A shared run of eight characters is long enough that
        /// two different lyric lines would not produce it by chance.
        private var echoedTranslations: Int {
            var echoed = 0
            for (index, entry) in translations.enumerated() where entry.text.count >= 8 {
                let others = translations.enumerated()
                    .filter { $0.offset != index && $0.element.line != entry.line }
                    .map(\.element.text)
                if others.contains(where: { Self.shareALongRun(entry.text, $0) }) { echoed += 1 }
            }
            return echoed
        }

        private static func shareALongRun(_ lhs: String, _ rhs: String) -> Bool {
            let run = 8
            guard lhs.count >= run else { return false }
            let characters = Array(lhs)
            for start in 0...(characters.count - run) {
                let piece = String(characters[start..<(start + run)])
                if rhs.contains(piece) { return true }
            }
            return false
        }

        func summary() -> String {
            var text = ""
            // The model being installed is not the model answering. Twice now a
            // run has reported "온디바이스 모델" while the asset catalog was empty
            // underneath and every line fell back — and the numbers from such a
            // run say nothing about a prompt or a batching change.
            if lines > 0, dictionaryFallback == lines {
                text += "> **모든 줄이 사전으로 대체됐습니다.** 모델이 설치되어 있다고\n"
                text += "> 보고하더라도 실제 생성은 전부 실패했다는 뜻입니다. 아래 숫자로는\n"
                text += "> 프롬프트나 묶음 변경을 판단할 수 없습니다.\n\n"
            }
            text += "## 셀 수 있는 것\n\n"
            text += "| 항목 | 수 |\n|---|---|\n"
            text += "| 줄 | \(lines) |\n"
            text += "| 번역 없음 | \(missingTranslation) |\n"
            text += "| **사전으로 대체된 줄 (모델 호출 실패)** | \(dictionaryFallback) |\n"
            text += "| **다른 줄의 번역과 겹침** | \(echoedTranslations) |\n"
            text += "| **앞 줄의 단어가 번역에 넘어옴** | \(carriedFromNeighbour) |\n"
            text += "| **번역에 금지어(이웃·제목에서 온 말)** | \(strayTranslation) |\n"
            text += "| **번역에 일본어가 그대로 남음** | \(untranslatedJapanese) |\n"
            text += "| **번역이 원문의 두 배 넘게 길다(부풀림)** | \(paddedTranslation) |\n"
            text += "| 문법 노트 없음 | \(noGrammar) |\n"
            text += "| **가사에 없는 문법 패턴** | \(fabricatedGrammar) |\n"
            text += "| 단어 | \(words) |\n"
            text += "| 뜻 없음 | \(missingMeaning) |\n"
            text += "| 표기엔 한자, 표제어는 가나뿐 | \(kanaHeadwordForKanjiSurface) |\n"
            text += "| 표제어가 줄의 절반 이상 | \(headwordIsHalfTheLine) |\n"
            text += "| 표제어가 조사로 끝남 | \(headwordEndsInParticle) |\n"
            text += "| **표제어가 조사 한 글자** | \(particleOnlyWord) |\n"
            return text
        }
    }
}
