import Foundation
import RingRingCore
import RingRingLyrics
import Testing

@testable import RingRingSensei

/// Runs the quick reading over song-like text and prints what it fills in, so a
/// change to the dictionary, the grammar list or the tokenizer can be judged by
/// comparing two runs instead of squinting at two lines in the simulator.
///
/// Lives in its own target — hosted by the app, so it can run on a device where
/// the system translator's language pack is real. It asserts nothing about
/// quality; it counts the things that are checkable and prints the rest.
@Suite("해석 품질 보고서", .serialized)
@MainActor
struct SenseiReportSuite {
    /// What the quick reading actually produces on real-shaped lyrics.
    ///
    /// The three parts are words, grammar and a sentence. The first two are
    /// offline and the same everywhere; the sentence comes from the system
    /// translator, which a simulator often has as `.supported` rather than
    /// `.installed` — a pack only a real screen can download. The report says
    /// which it got, so a run with no sentences is not mistaken for a broken mode.
    @Test("빠른 해석이 실제 가사에서 무엇을 채우는지")
    func writeQuickModeReport() async {
        let packStatus = await PlainTranslator.shared.availability()
        let sensei = Sensei()

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

    /// Consecutive lines written in the register of J-pop lyrics — conditionals,
    /// 〜てる, 〜ように, quoted words, katakana loanwords. Invented rather than
    /// quoted: real lyrics have no business in a source file, and the coverage
    /// report below fetches those instead.
    static let realLyrics: [(String, [String])] = [
        ("夜を追いかけて", [
            "揺れるように消えてゆくように",
            "二人だけの空が続く朝に",
            "「またね」だけだった",
            "あの一言で答えが分かった",
            "本当は僕も笑いたいんだ",
        ]),
        ("手紙", [
            "夢ならもう少し続いてほしかった",
            "あの日の約束がまだ胸にある",
            "薄明かりの中で道を探した",
            "その横顔を今も覚えている",
            "失くしたものの重さを知って",
            "別れ際に君が気づかせてくれた",
        ]),
        ("ひまわり畑", [
            "白い帽子をかぶった君が",
            "風に揺れる花みたいで",
            "季節がいくつ変わっても",
            "僕は君を探してるんだ",
        ]),
    ]

    /// How much of real lyrics the bundled dictionary actually knows.
    ///
    /// Needs no model or translator, so it measures the same everywhere. The gap
    /// it prints is the order worth adding words in.
    @Test("사전이 실제 가사를 얼마나 아는지")
    func writeCoverageReport() async {
        let dictionary = DictionarySensei()
        let tokenizer = JapaneseTokenizer()
        let client = LRCLIBClient()

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
        var kanaToKanji: [String: Int] = [:]

        for song in songs {
            guard let lyrics = try? await client.lyrics(artist: song.artist, title: song.title)
            else { continue }
            reached += 1
            for line in lyrics.lines {
                for token in tokenizer.studyCandidates(in: line.text) {
                    let hit = dictionary.entry(forSpelling: token.surface, reading: token.reading)
                        ?? dictionary.lookup(lemma: token.lemma, reading: token.reading)
                    if let hit {
                        known += 1
                        if !token.surface.contains(where: \.isKanji), hit.l.contains(where: \.isKanji) {
                            kanaToKanji["\(token.surface) → \(hit.l)(\(hit.r)) \(hit.k)", default: 0] += 1
                        }
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

        report += "\n## 모르는 것 (빈도순)\n\n"
        for (word, count) in missing.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }).prefix(80) {
            report += "- \(count)회 \(word)\n"
        }

        report += "\n## 가나 표기가 한자 표제어로 잡힌 것 (빈도순)\n\n"
        report += "| 건수 | \(kanaToKanji.values.reduce(0, +)) |\n\n"
        for (pair, count) in kanaToKanji.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }).prefix(40) {
            report += "- \(count)회 \(pair)\n"
        }

        print("=== COVERAGE BEGIN ===")
        print(report)
        print("=== COVERAGE END ===")
    }
}
