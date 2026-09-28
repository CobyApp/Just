import Foundation
import RingRingCore

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
        "ささえ", "支え", "冴え", "さえぎ",      // 〜さえ (支える, 冴える, 遮る)
        "つつむ", "つつみ",                     // 〜つつ (包む)
        "もんだい", "問題", "もんく", "文句",   // 〜もん (問題, 文句)
        "何回",                                 // 〜なんか (何回)
        "かもめ",                               // 〜かも (鴎)
        "酔って", "寄って",                     // 〜によって (〜に酔って, 〜に寄って)
        "ごめんなさい", "おやすみなさい",       // 〜なさい
        "食べき",                               // 〜べき (食べきる)
        "いいわけ", "言い訳",                   // 〜わけ (言い訳)
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
        .init(["なんか"], display: "〜なんか",
              "「～따위」, 「～같은 거」. 앞말을 가볍게 낮추거나 예로 드는 구어체입니다."),
        .init(["など"], display: "〜など",
              "「～등」, 「～따위」. 예를 들어 나열하거나 가볍게 낮추는, 「なんか」의 문어투입니다."),
        .init(["って"], display: "〜って",
              "「～라고」. 말이나 생각을 인용하거나, 화제를 꺼낼 때의 구어체입니다.",
              requiresPredicate: true),

        // Compound negatives and set phrases — before bare 〜ない so the longer
        // meaning claims the line first.
        .init(["なければならない", "なければいけない", "なきゃ", "なくちゃ", "ねばならない"], display: "〜なければならない",
              "그렇게 해야 한다는 의무를 나타냅니다. 가사에서는 「〜なきゃ」, 「〜なくちゃ」로 줄여 씁니다.",
              supersedes: ["ない"]),
        .init(["なくてもいい", "なくていい", "なくてもかまわない"], display: "〜なくてもいい",
              "그렇게 하지 않아도 된다는 뜻입니다.", supersedes: ["ない", "てもいい"]),
        .init(["てはいけない", "てはならない", "ちゃいけない", "じゃいけない", "ちゃだめ", "じゃだめ"], display: "〜てはいけない",
              "그렇게 하면 안 된다는 금지입니다. 가사에서는 「〜ちゃだめ」로 줄여 씁니다.",
              supersedes: ["ない"]),
        .init(["ずにはいられない"], display: "〜ずにはいられない",
              "그렇게 하지 않고는 견딜 수 없다는, 감정이 북받치는 표현입니다.",
              supersedes: ["ない", "ずに"]),
        .init(["ないでください", "ないでくれ", "ないでね"], display: "〜ないでください",
              "그렇게 하지 말아 달라는 부탁입니다.", supersedes: ["ない", "ないで"]),
        .init(["しょうがない", "しかたない", "しかたがない", "しようがない"], display: "〜しょうがない",
              "어쩔 수 없다, 견딜 수 없다는 뜻입니다. 감정을 강조할 때 자주 씁니다.",
              supersedes: ["ない"]),
        .init(["てたまらない", "でたまらない"], display: "〜てたまらない",
              "참을 수 없을 만큼 그렇다는, 감정의 세기를 나타냅니다.",
              supersedes: ["ない"]),
        .init(["てならない", "でならない"], display: "〜てならない",
              "저절로 그렇게 느껴져 견딜 수 없다는 뜻입니다.", supersedes: ["ない"]),
        .init(["っこない"], display: "〜っこない",
              "「절대 ～할 리 없다」. 강하게 부정하는 구어체입니다.", supersedes: ["ない"]),
        .init(["ようがない", "ようもない"], display: "〜ようがない",
              "그렇게 할 방법이 없다는 뜻입니다.", supersedes: ["ない"]),
        .init(["ことはない"], display: "〜ことはない",
              "그럴 필요는 없다며 위로하거나 말리는 표현입니다.", supersedes: ["ない"]),
        .init(["しかない"], display: "〜しかない",
              "그렇게 할 수밖에 없다는 뜻입니다.", supersedes: ["ない", "しか"]),
        .init(["わけにはいかない"], display: "〜わけにはいかない",
              "사정상 그렇게 할 수는 없다는 뜻입니다.", supersedes: ["ない", "わけ"]),
        .init(["はずがない", "はずはない", "はずない"], display: "〜はずがない",
              "그럴 리가 없다는 강한 부정입니다.", supersedes: ["ない", "はず"]),
        .init(["にちがいない", "に違いない"], display: "〜にちがいない",
              "틀림없이 그럴 것이라는 확신입니다.", supersedes: ["ない"]),
        .init(["にすぎない"], display: "〜にすぎない",
              "그것에 불과하다며 낮추는 표현입니다.", supersedes: ["ない"]),
        .init(["ではない", "ではありません", "じゃありません"], display: "〜ではない",
              "「～가 아니다」라는 부정입니다. 「じゃない」의 격식체입니다.", supersedes: ["ない"]),
        .init(["じゃないか", "じゃないの"], display: "〜じゃないか",
              "「～잖아」, 「～아니야?」. 확인하거나 강하게 주장하는 구어체입니다.",
              supersedes: ["ない", "じゃない"]),
        .init(["たくない", "たくなかった"], display: "〜たくない",
              "그렇게 하고 싶지 않다는 뜻입니다.", supersedes: ["ない"]),
        .init(["かもしれない", "かもしれません"], display: "〜かもしれない",
              "그럴지도 모른다는 추측입니다.", supersedes: ["ない", "かも"]),
        .init(["ことができる", "ことができない"], display: "〜ことができる",
              "그렇게 할 수 있다는 능력이나 가능성입니다.", supersedes: ["ない"]),

        // Giving/receiving and te-form auxiliaries. Longer 〜させ…/〜て… come
        // before the shorter forms they contain.
        .init(["させられる", "させられた"], display: "〜させられる",
              "사역수동. 「(어쩔 수 없이) ～하게 되다」, 시켜서 하는 것을 나타냅니다.",
              supersedes: ["られる"]),
        .init(["させてください", "させてほしい"], display: "〜させてください",
              "「～하게 해 주세요」. 내가 하도록 허락을 구하는 표현입니다.",
              supersedes: ["させて", "てください"]),
        .init(["させてもらう", "させてもらった"], display: "〜させてもらう",
              "상대의 허락을 받아 내가 그렇게 한다는 겸손한 표현입니다.",
              supersedes: ["させて", "てもらう"]),
        .init(["てほしい", "てほしかった", "でほしい"], display: "〜てほしい",
              "상대가 그렇게 해 주기를 바란다는 뜻입니다."),
        .init(["てみる", "てみた", "てみて", "てみたい"], display: "〜てみる",
              "「～해 보다」. 시험 삼아 해 본다는 뜻입니다."),
        .init(["てあげる", "てあげた"], display: "〜てあげる",
              "「～해 주다」. 내가 상대를 위해 해 준다는 뜻입니다."),
        .init(["てくれる", "てくれた", "てくれて", "てくれ"], display: "〜てくれる",
              "「～해 주다」. 상대가 나를 위해 해 준다는 뜻입니다.", supersedes: ["てく"]),
        .init(["てもらう", "てもらった"], display: "〜てもらう",
              "「～해 받다」. 상대가 해 준 것을 내가 받는다는 뜻입니다."),
        .init(["ていただく", "ていただいた", "ていただける"], display: "〜ていただく",
              "「～해 받다」의 겸양 표현입니다. 상대의 행동을 정중히 높입니다."),
        .init(["てください", "でください"], display: "〜てください",
              "「～해 주세요」. 정중한 부탁이나 지시입니다."),
        .init(["なさい"], display: "〜なさい",
              "「～하렴」, 「～해라」. 손윗사람이 부드럽게 명령하는 말투입니다."),
        .init(["てある"], display: "〜てある",
              "누군가 그렇게 해 둔 상태가 남아 있음을 나타냅니다."),
        .init(["てから", "でから"], display: "〜てから",
              "「～하고 나서」. 그 동작 뒤에 다음이 이어짐을 나타냅니다."),
        .init(["ておく", "とく"], display: "〜ておく",
              "나중을 위해 미리 해 둔다는 뜻입니다. 가사에서는 「〜とく」로 줄여 씁니다."),
        .init(["てくる"], display: "〜てくる",
              "동작이 이쪽으로 향하거나, 점점 그렇게 되어 옴을 나타냅니다.", supersedes: ["てく"]),
        .init(["ていく", "てゆく", "てく", "てった"], display: "〜ていく",
              "동작이 멀어지거나, 앞으로 계속 그렇게 되어 감을 나타냅니다. 가사에서는 「〜てく」, 「〜てった」로 줄여 씁니다."),
        .init(["てしまう", "ちゃう", "ちゃった", "てしまった", "じゃう", "じゃった"], display: "〜てしまう",
              "동작이 끝나 버렸음, 또는 그에 대한 아쉬움·후회를 나타냅니다. 가사에서는 「〜ちゃう」, 「〜じゃう」로 줄여 씁니다."),
        .init(["に決まってる", "に決まっている", "にきまってる"], display: "〜に決まってる",
              "「분명히 ～다」. 그럴 것이 뻔하다는 강한 확신입니다.", supersedes: ["てる"]),
        .init(["ている", "てる", "でいる", "でる"], display: "〜ている",
              "지금 진행 중이거나 그 상태가 이어지고 있음을 나타냅니다. 가사에서는 「〜てる」로 줄여 씁니다."),
        .init(["させる", "させて"], display: "〜させる",
              "사역. 「～하게 하다」, 「～시키다」."),
        .init(["られる", "られた", "られて"], display: "〜られる",
              "수동 「～당하다」, 또는 가능 「～할 수 있다」. 문맥으로 갈립니다."),

        // Change, purpose, decision. 〜ようにする/〜ようになる before 〜ように.
        .init(["ようにする", "ようにして", "ようにした"], display: "〜ようにする",
              "그렇게 되도록 애쓴다, 그렇게 하기로 한다는 뜻입니다.", supersedes: ["ように"]),
        .init(["ようになる", "ようになった"], display: "〜ようになる",
              "그렇게 되기에 이르렀다는 변화입니다.", supersedes: ["ように"]),
        .init(["ようとする", "うとする"], display: "〜ようとする",
              "그렇게 하려고 한다는 의지나 시도를 나타냅니다."),
        .init(["ようと思う", "ようとおもう", "うと思う", "うとおもう"], display: "〜ようと思う",
              "그렇게 하려고 마음먹는다는 뜻입니다.", supersedes: ["と思う"]),
        .init(["ように"], display: "〜ように",
              "그렇게 되도록, 또는 그런 모양으로. 비유에도 씁니다."),
        .init(["ようだ", "ような", "ようです"], display: "〜ようだ",
              "그런 것 같다, 또는 그것과 같다는 비유·추측입니다."),
        .init(["ために", "ための", "ためだ"], display: "〜ために",
              "그렇게 하기 위해, 또는 그 때문에. 목적이나 이유를 나타냅니다."),
        .init(["ことにする", "ことにした", "ことにしよう"], display: "〜ことにする",
              "그렇게 하기로 스스로 정한다는 뜻입니다."),
        .init(["ことになる", "ことになった"], display: "〜ことになる",
              "사정에 따라 그렇게 되기로 정해졌다는 뜻입니다."),
        .init(["ことがある", "ことがあった"], display: "〜ことがある",
              "그런 적이 있다, 또는 가끔 그럴 때가 있다는 뜻입니다."),

        // Desire, intent, advice
        .init(["たい", "たくて", "たくって"], display: "〜たい",
              "말하는 사람이 그렇게 하고 싶다는 뜻입니다."),
        .init(["たくなる", "たくなった"], display: "〜たくなる",
              "그렇게 하고 싶어진다는, 마음이 그리 움직임을 나타냅니다."),
        .init(["たがる", "たがって", "たがった"], display: "〜たがる",
              "남이 그렇게 하고 싶어한다는, 제삼자의 욕구를 나타냅니다."),
        .init(["つもり"], display: "〜つもり",
              "그렇게 할 작정이라는 뜻입니다."),
        .init(["ましょう", "ましょ"], display: "〜ましょう",
              "「～합시다」, 「～할까요」. 함께 하자고 권하는 정중한 표현입니다."),
        .init(["ませんか"], display: "〜ませんか",
              "「～하지 않을래요?」. 정중하게 권유하는 표현입니다.", supersedes: ["ません"]),
        .init(["てもいい", "ていい", "でもいい"], display: "〜てもいい",
              "그래도 괜찮다는 허락이나 양보입니다."),
        .init(["べき"], display: "〜べき",
              "마땅히 그렇게 해야 한다는 뜻입니다.", requiresPredicate: true),
        .init(["ばいい"], display: "〜ばいい",
              "그렇게 하면 된다는 조언이나 해결책입니다.", supersedes: ["れば"]),
        .init(["たらいい"], display: "〜たらいい",
              "그렇게 하면 좋겠다, 그렇게 하면 된다는 뜻입니다.", supersedes: ["たら"]),
        .init(["ばよかった"], display: "〜ばよかった",
              "그렇게 했으면 좋았을 텐데, 라는 후회입니다.", supersedes: ["れば"]),
        .init(["といい"], display: "〜といい",
              "그렇게 되면 좋겠다는 바람입니다.", requiresPredicate: true),
        .init(["ほうがいい"], display: "〜ほうがいい",
              "「～하는 편이 좋다」. 권하는 말입니다.", supersedes: ["ほうが"]),
        .init(["ほうが", "方が"], display: "〜ほうが",
              "「～쪽이」. 둘을 견주어 한쪽을 고를 때 씁니다."),

        // Conjecture and hearsay
        .init(["かも"], display: "〜かも",
              "그럴지도 모른다는 추측을 가볍게 흘리는 구어체입니다.", requiresPredicate: true),
        .init(["だろう", "でしょう", "でしょ"], display: "〜だろう",
              "그럴 것이라는 추측이나 확인입니다."),
        .init(["そうだ", "そうな", "そうに"], display: "〜そうだ",
              "그렇게 보인다, 또는 그렇게 될 것 같다는 뜻입니다."),
        .init(["みたい", "みたいな", "みたいに"], display: "〜みたい",
              "그런 것 같다, 또는 그것과 비슷하다는 뜻입니다."),
        .init(["らしい"], display: "〜らしい",
              "그렇다고 들었다, 또는 그것답다는 뜻입니다."),
        .init(["はず"], display: "〜はず",
              "당연히 그럴 것이라는 근거 있는 예상입니다."),
        .init(["のかな", "んかな"], display: "〜かな",
              "「～일까」, 「～려나」. 혼잣말처럼 가볍게 묻거나 바라는 어감입니다."),
        .init(["かしら"], display: "〜かしら",
              "「～일까」. 「かな」와 같되 조금 더 부드러운 어감입니다.", requiresPredicate: true),
        .init(["わけ"], display: "〜わけ",
              "그럴 만한 사정이나 까닭이라는 뜻입니다.", requiresPredicate: true),
        .init(["ものだ", "ものです"], display: "〜ものだ",
              "본래 그런 법이다, 또는 곧잘 그랬다는 회상입니다.", requiresPredicate: true),
        .init(["かどうか"], display: "〜かどうか",
              "그런지 아닌지, 라는 갈림을 나타냅니다."),
        .init(["と思う", "とおもう", "と思った", "とおもった"], display: "〜と思う",
              "「～라고 생각한다」. 자신의 판단이나 의견을 말합니다."),
        .init(["気がする", "きがする", "気がした", "きがした"], display: "〜気がする",
              "「～인 듯한 느낌이 든다」. 어렴풋한 느낌을 말합니다."),
        .init(["ことか"], display: "〜ことか",
              "「얼마나 ～한지」. 감정의 정도를 감탄하듯 강조합니다.", requiresPredicate: true),
        .init(["によると", "によれば"], display: "〜によると",
              "「～에 따르면」. 들은 내용의 출처를 댈 때 씁니다."),
        .init(["という", "っていう"], display: "〜という",
              "「～라고 하는」, 「～라는」. 이름을 대거나 내용을 설명합니다."),

        // Conditions
        .init(["たら"], display: "〜たら",
              "그렇게 되면, 이라는 가정입니다."),
        .init(["ならば", "なら"], display: "〜なら",
              "그렇다면, 이라는 가정입니다. 화제를 받아 조건으로 세웁니다."),
        .init(["ければ", "えば", "けば", "せば", "てば", "めば", "れば", "べば", "げば"], display: "〜ば",
              "가정형입니다. 그렇게 하면, 이라는 조건을 만듭니다."),
        // 「でも」 is the concessive only after ん — the て-form of ぐ/ぬ/ぶ/む
        // verbs, 「読んでも」, 「飲んでも」. Everywhere else it is the particle:
        // 「今でも」 is "even now", not a conjugation, and 「それでも」 is a
        // conjunction. Listing bare 「でも」 reported both as verb concession.
        .init(["ても", "んでも"], display: "〜ても",
              "동사·형용사의 て형에 붙어 '그렇더라도'라는 양보를 나타냅니다. 「たとえ」와 자주 함께 씁니다."),

        // Reason, contrast, concession
        .init(["ながら"], display: "〜ながら",
              "두 동작을 동시에 함을 나타냅니다."),
        .init(["けれど", "けど", "だけど"], display: "〜けど",
              "역접입니다. 앞말과 반대되는 내용이 이어집니다."),
        .init(["からには"], display: "〜からには",
              "「～한 이상」. 그렇게 된 이상 당연히 그래야 한다는 뜻입니다.", supersedes: ["から"]),
        .init(["から"], display: "〜から",
              "이유를 나타냅니다. 그러니까, 이므로.",
              requiresPredicate: true),
        .init(["ので"], display: "〜ので",
              "이유를 나타냅니다. 「から」보다 부드럽습니다.",
              requiresPredicate: true),
        .init(["のに"], display: "〜のに",
              "그런데도, 라는 아쉬움이나 불만이 섞인 역접입니다.",
              requiresPredicate: true),
        .init(["おかげで", "おかげだ"], display: "〜おかげで",
              "「～덕분에」. 좋은 결과의 원인을 고맙게 댈 때 씁니다."),
        .init(["せいで", "せいか", "せいだ"], display: "〜せいで",
              "「～탓에」. 나쁜 결과의 원인을 댈 때 씁니다."),
        .init(["くせに"], display: "〜くせに",
              "「～면서」, 「～주제에」. 못마땅함을 담은 역접입니다."),
        .init(["ものの"], display: "〜ものの",
              "그렇기는 하지만, 이라는 역접입니다.", requiresPredicate: true),

        // Time and sequence
        .init(["うちに"], display: "〜うちに",
              "그런 동안에, 그렇게 되기 전에. 상태가 유지되는 사이를 나타냅니다.",
              requiresPredicate: true),
        .init(["とたん", "とたんに", "途端"], display: "〜とたん",
              "「～한 순간」. 그 직후에 다른 일이 일어남을 나타냅니다."),
        .init(["とき"], display: "〜とき",
              "「～할 때」. 그 때·경우를 나타냅니다.", requiresPredicate: true),
        .init(["まえに"], display: "〜まえに",
              "「～하기 전에」. 그 동작에 앞섬을 나타냅니다.", requiresPredicate: true),
        .init(["あとで"], display: "〜あとで",
              "「～한 뒤에」. 그 동작 다음을 나타냅니다.", requiresPredicate: true),
        .init(["たびに"], display: "〜たびに",
              "「～할 때마다」. 그럴 때마다 매번 그렇다는 뜻입니다.", requiresPredicate: true),
        .init(["ついでに"], display: "〜ついでに",
              "「～하는 김에」. 그 참에 다른 일도 함을 나타냅니다."),
        .init(["わりに", "わりには"], display: "〜わりに",
              "「～에 비해서는」. 예상과 다른 정도를 나타냅니다.", requiresPredicate: true),

        // Limiting, focus, degree
        .init(["だけ"], display: "〜だけ",
              "그것뿐이라는 한정입니다."),
        .init(["しか"], display: "〜しか",
              "그것밖에 없다는 한정입니다. 뒤에 부정이 옵니다."),
        .init(["さえ"], display: "〜さえ",
              "「～조차」, 「～마저」. 극단적인 예를 들거나, 그것만 있으면 충분함을 나타냅니다."),
        .init(["こそ"], display: "〜こそ",
              "「바로 ～」. 다른 것이 아니라 그것임을 힘주어 말합니다."),
        .init(["ばかり", "ばっかり", "ばっか"], display: "〜ばかり",
              "그것만, 또는 막 그렇게 한 직후를 나타냅니다."),
        .init(["ほど"], display: "〜ほど",
              "「～만큼」, 「～할 정도로」. 정도를 비교하거나 강조합니다."),
        .init(["くらい", "ぐらい"], display: "〜くらい",
              "「～정도」, 「～만큼」. 대략의 정도를 나타냅니다."),
        .init(["までに"], display: "〜までに",
              "「～까지는」. 그 기한 안에 끝냄을 나타냅니다.", supersedes: ["まで"]),
        .init(["まで"], display: "〜まで",
              "그때까지, 그 정도까지라는 범위입니다."),
        .init(["どころか"], display: "〜どころか",
              "「～은커녕」. 앞말은 물론이고 오히려 그 반대임을 강조합니다."),
        .init(["っきり", "きりで"], display: "〜きり",
              "「～뿐」, 「～한 채로」. 그것만으로 한정됨을 나타냅니다."),
        .init(["だらけ"], display: "〜だらけ",
              "「～투성이」. 그것이 온통 가득하다는 뜻입니다."),
        .init(["について", "については"], display: "〜について",
              "「～에 대해」. 그것을 화제·대상으로 삼습니다."),
        .init(["によって", "により"], display: "〜によって",
              "「～에 의해」, 「～에 따라」. 수단·원인·기준을 나타냅니다."),
        .init(["に対して", "にたいして"], display: "〜に対して",
              "「～에 대하여」. 상대·대상을 향함을 나타냅니다."),

        // Manner, state, aspect
        .init(["まま"], display: "〜まま",
              "「～한 채로」. 그 상태를 바꾸지 않고 둔다는 뜻입니다."),
        .init(["ずに", "ないで"], display: "〜ずに",
              "그렇게 하지 않은 채로.", supersedes: ["ない"]),
        .init(["がち"], display: "〜がち",
              "「～하기 쉬운」, 「곧잘 ～하는」. 그런 경향이 잦다는 뜻입니다."),
        .init(["つつ"], display: "〜つつ",
              "「～하면서」. 두 동작을 동시에 하는 문어투이며, 역접에도 씁니다."),
        .init(["っぱなし", "ぱなし"], display: "〜っぱなし",
              "「～한 채로 둠」. 그렇게 해 놓고 그대로 방치함을 나타냅니다."),
        .init(["ことなく"], display: "〜ことなく",
              "「～하는 일 없이」. 그렇게 하지 않은 채 이어짐을 나타냅니다."),

        // Discourse and colloquial
        .init(["んだ", "のだ", "んです"], display: "〜んだ",
              "설명하거나 강조하는 어감을 더합니다. 「～인 거야」."),
        .init(["もん", "だもん", "んだもん", "だもの"], display: "〜もん",
              "「～인 걸」. 이유를 대며 어리광이나 투정을 담는 구어체입니다."),
        .init(["じゃん", "じゃない"], display: "〜じゃない",
              "「～잖아」, 「～가 아니야」. 확인이나 가벼운 반박의 구어체입니다."),
        .init(["っぽい"], display: "〜っぽい",
              "「～같은」, 「～스러운」. 그런 느낌이 난다는 뜻입니다."),
        .init(["とか"], display: "〜とか",
              "「～라든가」. 예를 들어 가볍게 나열할 때 씁니다."),
        .init(["たり"], display: "〜たり",
              "「～하거나 ～하거나」. 여러 동작을 예로 들어 늘어놓습니다."),

        // Change and degree
        .init(["なくなる"], display: "〜なくなる",
              "더 이상 그렇지 않게 되었다는 변화입니다.", supersedes: ["ない"]),
        .init(["すぎる"], display: "〜すぎる",
              "지나치게 그렇다는 뜻입니다."),

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
