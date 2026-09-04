import Foundation
import JustCore

/// Grammar patterns found by matching the line, not by asking the model.
///
/// Asking cost a field on every line and came back empty five times in nine, so
/// it was dropped — and the collection screen it fed would have emptied out with
/// it. Matching restores the feature for nothing: Japanese grammar is a finite,
/// well-catalogued set, a lyric either contains 「〜てしまう」 or it does not, and
/// the explanation of what it means does not vary by song. This is the same
/// division the rest of the analyser already makes — the model for judgement,
/// fixed data for facts.
///
/// What is given up against the model's version is the note tailored to the
/// line. What is gained is that it always fires, always says the same thing, and
/// costs no generation at all.
public enum GrammarPatterns {
    public struct Pattern: Sendable {
        /// What to look for in the line.
        public let forms: [String]
        /// How it is written when shown to the learner.
        public let display: String
        public let explanationKo: String
        /// Patterns whose match implies this one too, so only the longer one is
        /// reported: 「なければならない」 contains 「ない」.
        let supersedes: [String]
        /// Whether the form must follow a predicate to be this pattern.
        ///
        /// For the handful of forms that are two different things depending on
        /// what they attach to. 「から」 after a predicate is a reason — 「言った
        /// から」, 「寂しいから」 — and after a noun it is a starting point:
        /// 「あれから七年」 is "seven years since then", and a note calling that
        /// a reason teaches the opposite of what the line says.
        let requiresPredicate: Bool

        init(
            _ forms: [String],
            display: String? = nil,
            _ explanationKo: String,
            supersedes: [String] = [],
            requiresPredicate: Bool = false
        ) {
            self.forms = forms
            self.display = display ?? "〜\(forms[0])"
            self.explanationKo = explanationKo
            self.supersedes = supersedes
            self.requiresPredicate = requiresPredicate
        }
    }

    /// Kana a predicate ends in, right before an attached particle.
    ///
    /// The う-row (a plain verb), plus い (an adjective), plus た/だ/な. It does
    /// not have to be exact — a noun ending in one of these slips through,
    /// 「あなたから」 being the notable one — but it removes the whole class of
    /// noun-plus-particle that the substring match otherwise reports as
    /// conjugation: 今から, ここから, 明日から, ものに.
    private static let predicateEndings: Set<Character> = [
        "う", "く", "ぐ", "す", "つ", "ぬ", "ぶ", "む", "る",
        "い", "た", "だ", "な",
    ]

    /// Words that contain a pattern's letters without being that pattern.
    ///
    /// The cost of matching on substrings, and it has to be paid explicitly
    /// because there is no way to spot them by shape: 「さよなら」 ends in the
    /// conditional 「なら」, 「素晴らしい」 contains the hearsay 「らしい」, and
    /// 「切ない」 is one adjective rather than a negation. Each of these is a
    /// common word in lyrics, so every one was a note the reader would have been
    /// taught wrongly.
    ///
    /// Blanked out of the line before matching, rather than checked per pattern:
    /// one pass, and a word that hides two patterns only has to be listed once.
    private static let falseFriends = [
        "さよなら", "サヨナラ", "さようなら",   // 〜なら
        "素晴らし", "すばらし",                 // 〜らしい
        "切ない", "せつない", "少ない", "危ない", "はかない", "あどけない",  // 〜ない
        "だいたい", "たいてい", "たいへん",     // 〜たい
        "そのまま", "たまたま",                 // 〜まで is safe; these guard 〜まま
    ]

    /// The line with its false friends blanked out.
    ///
    /// Replaced with a space rather than removed, so blanking a word cannot glue
    /// its neighbours into a form that was never written.
    static func masked(_ line: String) -> String {
        var text = line
        for word in falseFriends where text.contains(word) {
            text = text.replacingOccurrences(
                of: word,
                with: String(repeating: " ", count: word.count)
            )
        }
        return text
    }

    /// Whether `form` occurs in `line` attached to a predicate.
    private static func followsPredicate(_ form: String, in line: String) -> Bool {
        var searchRange = line.startIndex..<line.endIndex
        while let found = line.range(of: form, range: searchRange) {
            if found.lowerBound > line.startIndex {
                let preceding = line[line.index(before: found.lowerBound)]
                if predicateEndings.contains(preceding) { return true }
            }
            guard found.upperBound < line.endIndex else { return false }
            searchRange = found.upperBound..<line.endIndex
        }
        return false
    }

    /// Ordered longest-intent first: the list is scanned in order and a match
    /// removes the patterns it supersedes.
    public static let all: [Pattern] = [
        // Quoting, dismissing, exclaiming — the everyday spoken forms lyrics
        // are made of. だって before って, so 「だって」 is not also counted as
        // a bare quotative.
        .init(["だって"], display: "〜だって",
              "「～도」, 「～라고 해도」, 또는 「그렇지만」. 앞말을 강조하거나 이유를 댈 때 씁니다.",
              supersedes: ["って"]),
        .init(["なんて"], display: "〜なんて",
              "「～같은 것」, 「～라니」. 가볍게 여기거나 놀라움을 담아 말할 때 씁니다."),
        .init(["って"], display: "〜って",
              "「～라고」. 말이나 생각을 인용하거나, 화제를 꺼낼 때의 구어체입니다.",
              requiresPredicate: true),
        .init(["じゃん", "じゃない"], display: "〜じゃない",
              "「～잖아」, 「～가 아니야」. 확인이나 가벼운 반박의 구어체입니다."),
        .init(["んだ", "のだ", "んです"], display: "〜んだ",
              "설명하거나 강조하는 어감을 더합니다. 「～인 거야」."),
        .init(["っぽい"], display: "〜っぽい",
              "「～같은」, 「～스러운」. 그런 느낌이 난다는 뜻입니다."),
        .init(["まま"], display: "〜まま",
              "「～한 채로」. 그 상태를 바꾸지 않고 둔다는 뜻입니다."),
        .init(["とか"], display: "〜とか",
              "「～라든가」. 예를 들어 가볍게 나열할 때 씁니다."),
        .init(["くらい", "ぐらい"], display: "〜くらい",
              "「～정도」, 「～만큼」. 대략의 정도를 나타냅니다."),
        .init(["ほど"], display: "〜ほど",
              "「～만큼」, 「～할 정도로」. 정도를 비교하거나 강조합니다."),
        .init(["たり"], display: "〜たり",
              "「～하거나 ～하거나」. 여러 동작을 예로 들어 늘어놓습니다."),
        .init(["てみる", "てみた", "てみて"], display: "〜てみる",
              "「～해 보다」. 시험 삼아 해 본다는 뜻입니다."),
        .init(["てくれる", "てくれた", "てくれて"], display: "〜てくれる",
              "「～해 주다」. 상대가 나를 위해 해 준다는 뜻입니다."),
        .init(["てあげる", "てあげた"], display: "〜てあげる",
              "「～해 주다」. 내가 상대를 위해 해 준다는 뜻입니다."),
        .init(["てもらう", "てもらった"], display: "〜てもらう",
              "「～해 받다」. 상대가 해 준 것을 내가 받는다는 뜻입니다."),
        .init(["させる", "させて"], display: "〜させる",
              "사역. 「～하게 하다」, 「～시키다」."),
        .init(["られる", "られた", "られて"], display: "〜られる",
              "수동 「～당하다」, 또는 가능 「～할 수 있다」. 문맥으로 갈립니다."),
        .init(["ほうがいい"], display: "〜ほうがいい",
              "「～하는 편이 좋다」. 권하는 말입니다."),

        // Aspect and completion
        .init(["てしまう", "ちゃう", "ちゃった", "てしまった"], display: "〜てしまう",
              "동작이 끝나 버렸음, 또는 그에 대한 아쉬움·후회를 나타냅니다."),
        .init(["ている", "てる", "でいる", "でる"], display: "〜ている",
              "지금 진행 중이거나 그 상태가 이어지고 있음을 나타냅니다. 가사에서는 「〜てる」로 줄여 씁니다."),
        .init(["ておく", "とく"], display: "〜ておく",
              "나중을 위해 미리 해 둔다는 뜻입니다."),
        .init(["てくる"], display: "〜てくる",
              "동작이 이쪽으로 향하거나, 점점 그렇게 되어 옴을 나타냅니다."),
        .init(["ていく", "てゆく"], display: "〜ていく",
              "동작이 멀어지거나, 앞으로 계속 그렇게 되어 감을 나타냅니다."),

        // Desire, intent, attempt
        .init(["たい"], display: "〜たい",
              "말하는 사람이 그렇게 하고 싶다는 뜻입니다."),
        .init(["ようとする", "うとする"], display: "〜ようとする",
              "그렇게 하려고 한다는 의지나 시도를 나타냅니다."),
        .init(["ように"], display: "〜ように",
              "그렇게 되도록, 또는 그런 모양으로. 비유에도 씁니다."),
        .init(["つもり"], display: "〜つもり",
              "그렇게 할 작정이라는 뜻입니다."),

        // Obligation and permission
        .init(["なければならない", "なきゃ", "なくちゃ", "ねばならない"], display: "〜なければならない",
              "그렇게 해야 한다는 의무를 나타냅니다. 가사에서는 「〜なきゃ」로 줄여 씁니다.",
              supersedes: ["ない"]),
        .init(["てもいい"], display: "〜てもいい",
              "그래도 괜찮다는 허락이나 양보입니다."),

        // Conjecture and hearsay
        .init(["かもしれない", "かもしれません"], display: "〜かもしれない",
              "그럴지도 모른다는 추측입니다.", supersedes: ["ない"]),
        .init(["だろう", "でしょう"], display: "〜だろう",
              "그럴 것이라는 추측이나 확인입니다."),
        .init(["そうだ", "そうな", "そうに"], display: "〜そうだ",
              "그렇게 보인다, 또는 그렇게 될 것 같다는 뜻입니다."),
        .init(["みたい"], display: "〜みたい",
              "그런 것 같다, 또는 그것과 비슷하다는 뜻입니다."),
        .init(["らしい"], display: "〜らしい",
              "그렇다고 들었다, 또는 그것답다는 뜻입니다."),
        .init(["はず"], display: "〜はず",
              "당연히 그럴 것이라는 근거 있는 예상입니다."),

        // Conditions
        .init(["たら"], display: "〜たら",
              "그렇게 되면, 이라는 가정입니다."),
        .init(["ならば", "なら"], display: "〜なら",
              "그렇다면, 이라는 가정입니다. 화제를 받아 조건으로 세웁니다."),
        .init(["ければ", "えば", "けば", "せば", "てば", "めば", "れば"], display: "〜ば",
              "가정형입니다. 그렇게 하면, 이라는 조건을 만듭니다."),
        // 「でも」 is the concessive only after ん — the て-form of ぐ/ぬ/ぶ/む
        // verbs, 「読んでも」, 「飲んでも」. Everywhere else it is the particle:
        // 「今でも」 is "even now", not a conjugation, and 「それでも」 is a
        // conjunction. Listing bare 「でも」 reported both as verb concession.
        .init(["ても", "んでも"], display: "〜ても",
              "동사·형용사의 て형에 붙어 '그렇더라도'라는 양보를 나타냅니다. 「たとえ」와 자주 함께 씁니다."),

        // Ability, change, causation
        .init(["ことができる", "ことができない"], display: "〜ことができる",
              "그렇게 할 수 있다는 능력이나 가능성입니다."),
        .init(["ようになる"], display: "〜ようになる",
              "그렇게 되기에 이르렀다는 변화입니다."),
        .init(["なくなる"], display: "〜なくなる",
              "더 이상 그렇지 않게 되었다는 변화입니다.", supersedes: ["ない"]),
        .init(["すぎる"], display: "〜すぎる",
              "지나치게 그렇다는 뜻입니다."),

        // Connectives and discourse
        .init(["ながら"], display: "〜ながら",
              "두 동작을 동시에 함을 나타냅니다."),
        .init(["けれど", "けど", "だけど"], display: "〜けど",
              "역접입니다. 앞말과 반대되는 내용이 이어집니다."),
        .init(["から"], display: "〜から",
              "이유를 나타냅니다. 그러니까, 이므로.",
              requiresPredicate: true),
        .init(["ので"], display: "〜ので",
              "이유를 나타냅니다. 「から」보다 부드럽습니다.",
              requiresPredicate: true),
        .init(["のに"], display: "〜のに",
              "그런데도, 라는 아쉬움이나 불만이 섞인 역접입니다.",
              requiresPredicate: true),
        .init(["だけ"], display: "〜だけ",
              "그것뿐이라는 한정입니다."),
        .init(["しか"], display: "〜しか",
              "그것밖에 없다는 한정입니다. 뒤에 부정이 옵니다."),
        .init(["ばかり"], display: "〜ばかり",
              "그것만, 또는 막 그렇게 한 직후를 나타냅니다."),
        .init(["まで"], display: "〜まで",
              "그때까지, 그 정도까지라는 범위입니다."),
        .init(["ずに", "ないで"], display: "〜ずに",
              "그렇게 하지 않은 채로.", supersedes: ["ない"]),

        // Negation, last so a longer negative pattern claims the line first
        .init(["ない", "ません"], display: "〜ない",
              "부정입니다."),
    ]

    /// Patterns the line contains, most specific first.
    ///
    /// Capped because a lyric line is short and a list of eight notes on one
    /// line is not a lesson, it is noise.
    public static func matches(in line: String, limit: Int = 3) -> [GrammarNote] {
        guard LineScript.hasJapanese(line) else { return [] }

        var claimed = Set<String>()
        var notes: [GrammarNote] = []
        let text = masked(line)

        for pattern in all {
            guard !claimed.contains(pattern.display) else { continue }
            let appears = pattern.requiresPredicate
                ? pattern.forms.contains { followsPredicate($0, in: text) }
                : pattern.forms.contains(where: text.contains)
            guard appears else { continue }

            notes.append(
                GrammarNote(pattern: pattern.display, explanationKo: pattern.explanationKo)
            )
            claimed.insert(pattern.display)
            // A longer pattern that contains a shorter one reports only itself:
            // 「なきゃ」 is not a lesson about 「ない」.
            for superseded in pattern.supersedes {
                if let hidden = all.first(where: { $0.forms.contains(superseded) }) {
                    claimed.insert(hidden.display)
                }
            }
            if notes.count >= limit { break }
        }
        return notes
    }
}
