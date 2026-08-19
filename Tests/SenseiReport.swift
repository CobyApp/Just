import Foundation
import JustCore
import Testing

@testable import JustSensei

/// Runs the real on-device analyser over a fixed set of lines and prints what it
/// produced, so a change to the prompt or the refinement rules can be judged by
/// comparing two runs instead of squinting at two lines in the simulator.
///
/// Compiled in only when asked for. A runtime switch was tried first and does
/// not reach here: unit tests run inside the app process, and neither
/// `xcodebuild`'s environment nor the app's defaults arrive in it. A compile
/// flag is the one gate that certainly works, and CI never passes it — so this
/// file does not exist as far as a normal test run is concerned.
///
/// It asserts nothing about quality — quality is not assertable — but it does
/// count the failure modes that *are* checkable, and those counts are the thing
/// to compare between runs.
///
/// Run:
/// ```
/// xcodebuild -workspace Just.xcworkspace -scheme Just \
///   -destination 'platform=iOS Simulator,name=iPhone 17' \
///   -only-testing:JustTests/SenseiReportSuite \
///   OTHER_SWIFT_FLAGS="-DSENSEI_REPORT" test 2>&1 \
///   | sed -n '/SENSEI REPORT BEGIN/,/SENSEI REPORT END/p'
/// ```
#if SENSEI_REPORT

@Suite("해석 품질 보고서")
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
            report += "- 엔진: \(study.engine == .onDevice ? "모델" : "사전")\n"
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
        /// Translations collected so the run can spot itself repeating.
        var translations: [String] = []

        private static let particles: Set<Character> = ["に", "を", "が", "は", "で", "と", "へ", "も", "の"]

        var strayTranslation = 0

        mutating func count(_ study: LineStudy, line: String, forbidden: [String]) {
            if forbidden.contains(where: study.translationKo.contains) { strayTranslation += 1 }
            lines += 1
            if study.translationKo.isEmpty { missingTranslation += 1 }
            translations.append(study.translationKo)
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
            for (index, text) in translations.enumerated() where text.count >= 8 {
                let others = translations.enumerated()
                    .filter { $0.offset != index }
                    .map(\.element)
                if others.contains(where: { Self.shareALongRun(text, $0) }) { echoed += 1 }
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
            var text = "## 셀 수 있는 것\n\n"
            text += "| 항목 | 수 |\n|---|---|\n"
            text += "| 줄 | \(lines) |\n"
            text += "| 번역 없음 | \(missingTranslation) |\n"
            text += "| **다른 줄의 번역과 겹침** | \(echoedTranslations) |\n"
            text += "| **번역에 금지어(이웃·제목에서 온 말)** | \(strayTranslation) |\n"
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

#endif
