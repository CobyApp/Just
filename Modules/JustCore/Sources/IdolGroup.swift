import Foundation

/// A group the app teaches from.
///
/// The whole catalogue of this app is this list. There is no search: a song
/// gets in by belonging to one of these groups, which is what makes it an idol
/// app rather than a music app that happens to have idols in it.
///
/// Only the roster is bundled. The songs come from the catalogue, so a new
/// single appears without an app update, and artwork and durations come with it.
public struct IdolGroup: Identifiable, Hashable, Sendable {
    /// The catalogue's artist id.
    ///
    /// An id rather than a name, because names collide. Looked up by name, a
    /// group loses its whole catalogue the day another artist matches better —
    /// and the failure looks like the group simply having no songs.
    public let id: String
    /// As the group writes it.
    public let name: String
    /// What to call it in Korean, for readers who know the group by ear.
    public let readingKo: String
    /// The label it belongs to, shown as a section.
    public let label: Label
    /// Hue for this group's card and accents, 0–1.
    public let hue: Double
    /// The YouTube channels the group's own videos are on: its channel, the
    /// label's channel that carries its music videos, and the auto-generated
    /// 「Topic」 channel with the label's audio tracks. A video from one of
    /// these is the group's own; anything else is somebody's copy.
    public let youtubeChannels: [String]
    /// Other spellings of the name — katakana, the fans' nickname — that a
    /// lyrics database may have indexed the group under.
    public let aliases: [String]

    /// A section of the home screen: a label or a family of groups, in the
    /// order they are shown.
    public enum Label: String, CaseIterable, Sendable {
        case kawaiiLab = "KAWAII LAB."
        case equalLove = "=LOVE · ≠ME · ≒JOY"
        case sakamichi = "坂道シリーズ"
        case fortyEight = "48グループ"
        case helloProject = "Hello! Project"
        case stardust = "STARDUST"
        case more = "그 밖의 인기 그룹"

        /// Whether the section names who the group belongs to, and so is
        /// worth repeating on the group's own page. The last section is only
        /// a shelf.
        public var namesAFamily: Bool { self != .more }
    }

    public init(id: String, name: String, readingKo: String, label: Label, hue: Double, youtubeChannels: [String] = [], aliases: [String] = []) {
        self.id = id
        self.name = name
        self.readingKo = readingKo
        self.label = label
        self.hue = hue
        self.youtubeChannels = youtubeChannels
        self.aliases = aliases
    }
}

public extension IdolGroup {
    /// Every group, in the order they are shown.
    ///
    /// Ids were checked against the catalogue rather than typed from memory —
    /// MORE STAR was confirmed by its own song 「WITH KAWAII論」, which is how
    /// its label was settled too.
    static let all: [IdolGroup] = [
        // KAWAII LAB. (ASOBISYSTEM)
        .init(id: "1617607581", name: "FRUITS ZIPPER", readingKo: "후룻파", label: .kawaiiLab, hue: 0.92,
              youtubeChannels: ["UCQG8tNnV4hKetLhMb4MopHQ", Channels.kawaiiLab, "UCB_jIxmkTjjAHyVZUD-kf4w"],
              aliases: ["フルーツジッパー", "ふるっぱー"]),
        .init(id: "1671095780", name: "CANDY TUNE", readingKo: "캔디튠", label: .kawaiiLab, hue: 0.02,
              youtubeChannels: ["UCU0PgOXf0lxzVxN2TLzMJkw", Channels.kawaiiLab, "UCCxkkhNWAbbV2mVSqLKDy9w"],
              aliases: ["キャンディーチューン", "きゃんちゅー"]),
        .init(id: "1729116371", name: "SWEET STEADY", readingKo: "스윗스테", label: .kawaiiLab, hue: 0.55,
              youtubeChannels: ["UC5s_kUbxX3P1q6lmDgygD-w", Channels.kawaiiLab, "UCPneIAYQhx4tNGuOWxAqk-Q"],
              aliases: ["スウィートステディ", "すいすて"]),
        .init(id: "1763185226", name: "CUTIE STREET", readingKo: "큐티스트리트", label: .kawaiiLab, hue: 0.85,
              youtubeChannels: ["UCEz-AFAg3EUKsxraad1puQA", Channels.kawaiiLab, "UCMMY6niyWsdwcX9wv4UKVWQ"],
              aliases: ["キューティーストリート", "きゅーすと"]),
        .init(id: "1855752654", name: "MORE STAR", readingKo: "모어스타", label: .kawaiiLab, hue: 0.13,
              youtubeChannels: ["UCBkLxz038AbxBA8CMw6o9oA", Channels.kawaiiLab, "UCmqMNVIY29wyaSDGrEGxqdQ"],
              aliases: ["モアスター"]),

        // 指原莉乃 produce — =LOVE and her two sister groups.
        .init(id: "1273762750", name: "=LOVE", readingKo: "이코러브", label: .equalLove, hue: 0.75,
              youtubeChannels: ["UCv7VutirxDn3RWIJXI68n_A"],
              aliases: ["イコールラブ", "イコラブ", "＝LOVE"]),
        .init(id: "1477023494", name: "≠ME", readingKo: "노이미", label: .equalLove, hue: 0.40,
              youtubeChannels: ["UCBmvHfXdGCvi_b6lFeU-E1Q", "UCoMmiGJkmp_nhEDMKRSlP2w"],
              aliases: ["ノットイコールミー", "ノイミー", "Not Equal Me"]),
        .init(id: "1631260593", name: "≒JOY", readingKo: "니아조이", label: .equalLove, hue: 0.14,
              youtubeChannels: ["UC_qmQbqvW6UES3NT780l2Pg", "UC7j5djR8yT-YfDlKgqYJFiA"],
              aliases: ["ニアリーイコールジョイ", "ニアジョイ", "nearly-equal-joy"]),

        // The 坂道 groups, and the official rival.
        .init(id: "571990937", name: "乃木坂46", readingKo: "노기자카46", label: .sakamichi, hue: 0.78,
              youtubeChannels: ["UCUzpZpX2wRYOk3J8QTFGxDg"],
              aliases: ["Nogizaka46", "のぎざか46"]),
        .init(id: "1541126420", name: "櫻坂46", readingKo: "사쿠라자카46", label: .sakamichi, hue: 0.96,
              youtubeChannels: ["UCmr9bYmymcBmQ1p2tLBRvwg", "UC73u6zwX_OFpzDjujzLs53g"],
              aliases: ["Sakurazaka46", "さくらざか46"]),
        .init(id: "1456116642", name: "日向坂46", readingKo: "히나타자카46", label: .sakamichi, hue: 0.56,
              youtubeChannels: ["UCR0V48DJyWbwEAdxLL5FjxA", "UCZ-HhqyV7T-CyZXGKJOkE8g"],
              aliases: ["Hinatazaka46", "けやき坂46", "ひなたざか46"]),
        .init(id: "1814542524", name: "僕が見たかった青空", readingKo: "보쿠아오", label: .sakamichi, hue: 0.60,
              youtubeChannels: ["UC-_iQWdEZY66nGGaHH0Ygmg", "UCNunvZGY5mnwBAPZAF_4nKA"],
              aliases: ["BOKUAO", "僕青"]),

        // AKB48 and the sister groups.
        .init(id: "292706922", name: "AKB48", readingKo: "에이케이비", label: .fortyEight, hue: 0.93,
              youtubeChannels: ["UCxjXU89x6owat9dA8Z-bzdw", "UCszuiV5XpxGRk8tXmUXxV5Q"],
              aliases: ["エーケービー"]),
        .init(id: "449588039", name: "SKE48", readingKo: "에스케이이", label: .fortyEight, hue: 0.07,
              youtubeChannels: ["UCG-5D9k_fL4FnMeNuraeAtA", "UCWuOKJi3AgdxaaWjFCl9Anw"],
              aliases: ["エスケーイー"]),
        .init(id: "448260895", name: "NMB48", readingKo: "엔엠비", label: .fortyEight, hue: 0.10,
              youtubeChannels: ["UCnhrIe3jZNmqDEL_zSBXADQ", "UCsZLRd70fURguCTuuyCrloQ"],
              aliases: ["エヌエムビー"]),
        .init(id: "583247983", name: "HKT48", readingKo: "에이치케이티", label: .fortyEight, hue: 0.88,
              youtubeChannels: ["UCPQ0GEWwLaam1lTX9P-CgGA", "UCK7cK9QvUPmws7uOak3cAaA"],
              aliases: ["エイチケーティー"]),

        // Hello! Project (UP-FRONT)
        .init(id: "207350119", name: "モーニング娘。", readingKo: "모닝구무스메", label: .helloProject, hue: 0.98,
              youtubeChannels: ["UCoKXb95K5h3sME3c9OCBaeA"],
              aliases: ["Morning Musume", "モー娘。"]),
        .init(id: "960147470", name: "アンジュルム", readingKo: "앙쥬르무", label: .helloProject, hue: 0.62,
              youtubeChannels: ["UCDwcZ85zjLKD-3-jqlv1wQQ", "UCFqQNzTojO959BKG7NaPCaA"],
              aliases: ["ANGERME", "スマイレージ"]),
        .init(id: "623197059", name: "Juice=Juice", readingKo: "쥬스쥬스", label: .helloProject, hue: 0.09,
              youtubeChannels: ["UC6FadPgGviUcq6VQ0CEJqdQ", "UCVI_PBGr3p9o_7ESaY3wSIQ"],
              aliases: ["ジュースジュース", "ジュース＝ジュース"]),
        .init(id: "1063638045", name: "つばきファクトリー", readingKo: "츠바키팩토리", label: .helloProject, hue: 0.95,
              youtubeChannels: ["UCXTsCXNGHmePgo3a47hnsAA", "UC2ugBN5onsPkbuLSoSfZAag"],
              aliases: ["TSUBAKI FACTORY"]),
        .init(id: "1473212760", name: "BEYOOOOONDS", readingKo: "비욘즈", label: .helloProject, hue: 0.50,
              youtubeChannels: ["UCE5GP4BHm2EJx4xyxBVSLlg", "UCsaOio4A0JokPQ-PamLGuVw"],
              aliases: ["ビヨーンズ"]),

        // STARDUST PROMOTION
        .init(id: "448294481", name: "ももいろクローバーZ", readingKo: "모모쿠로", label: .stardust, hue: 0.01,
              youtubeChannels: ["UC6YNWTm6zuMFsjqd0PO3G-Q"],
              aliases: ["Momoiro Clover Z", "ももクロ"]),
        .init(id: "573956537", name: "私立恵比寿中学", readingKo: "에비츄", label: .stardust, hue: 0.32,
              youtubeChannels: ["UCQ6Br7m6vP61FZvjv4lwR5w", "UCVA8Jz4_3rjHoWwMFssTl7Q"],
              aliases: ["Shiritsu Ebisu Chugaku", "エビ中"]),
        .init(id: "1512380754", name: "超ときめき♡宣伝部", readingKo: "토키센", label: .stardust, hue: 0.90,
              youtubeChannels: ["UCPO-HYS3fdDIKlMMgpcCzdg", "UCmTjY5Zh98L7A7A2PnbkwjQ"],
              aliases: ["超ときめき宣伝部", "Cho Tokimeki Sendenbu", "とき宣"]),
        .init(id: "1586407152", name: "いぎなり東北産", readingKo: "이기나리 토호쿠산", label: .stardust, hue: 0.12,
              youtubeChannels: ["UCuCBILJrBdU9bFEykEW0STA", "UChJQ1mpVt0dV1bg4hykwk3A"],
              aliases: ["THE MADE IN TOHOKU", "東北産"]),

        // Everyone else worth studying with.
        .init(id: "1578837625", name: "iLiFE!", readingKo: "아이라이프", label: .more, hue: 0.45,
              youtubeChannels: ["UChVflUz2J_jaaqYjXqvpmQA", "UCX4THHyTI9z4rS_rFTzMGDA"],
              aliases: ["アイライフ", "あいらいふ", "iLIFE!"]),
        .init(id: "1647482977", name: "高嶺のなでしこ", readingKo: "타카네노 나데시코", label: .more, hue: 0.94,
              youtubeChannels: ["UCoR4zZDvWvUIqgEWz4HS-sA"],
              aliases: ["TAKANE NO NADESHIKO", "たかねこ"]),
        .init(id: "1522236715", name: "#ババババンビ", readingKo: "바바바밤비", label: .more, hue: 0.70,
              youtubeChannels: ["UCQjSMUAIL4-rQbcY30ap4_g", "UCvtBzdKSB9p38Fz-G1QWeMA"],
              aliases: ["ババババンビ", "babababambi"]),
        .init(id: "1736570286", name: "ME:I", readingKo: "미아이", label: .more, hue: 0.58,
              youtubeChannels: ["UCvTsv4KmVuBdECI08_HR87Q", "UCmVWcCVzrEgVfNZLY80hfHw"],
              aliases: ["ミーアイ"]),
        .init(id: "1519410581", name: "NiziU", readingKo: "니쥬", label: .more, hue: 0.80,
              youtubeChannels: ["UCHp2q2i85qt_9nn2H7AvGOw", "UCzrllDdhrz1PemEWjgajRCQ"],
              aliases: ["ニジュー"]),
        .init(id: "1231338664", name: "新しい学校のリーダーズ", readingKo: "아타라시이 각코", label: .more, hue: 0.03,
              youtubeChannels: ["UCp0iCvHGMwyfPHpYq7n2sPw", "UCGjPxZv5YraYh_EJk1sH8Tg"],
              aliases: ["ATARASHII GAKKO!"]),
    ]

    /// Channels shared by several groups.
    enum Channels {
        /// KAWAII LAB.'s own channel, where the label publishes every music
        /// video of its groups.
        static let kawaiiLab = "UCW8Q9LBGGBgK6a-u0C0h95A"
    }

    /// The group a song belongs to, by the artist name the catalogue gives.
    ///
    /// The name first, then the spellings in `aliases` — a collaboration or a
    /// romanised credit still finds its group. Short aliases are skipped for
    /// matching: 「東北産」 is safe, a two-letter nickname would catch other
    /// artists' names.
    static func group(forArtist artist: String) -> IdolGroup? {
        let wanted = fold(artist)
        if let byName = all.first(where: { wanted.contains(fold($0.name)) }) {
            return byName
        }
        return all.first { group in
            group.aliases.contains { $0.count >= 4 && wanted.contains(fold($0)) }
        }
    }

    private static func fold(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: " ", with: "")
    }

    public static func group(id: String) -> IdolGroup? {
        all.first { $0.id == id }
    }

    /// The groups under one label, in roster order.
    static func groups(in label: Label) -> [IdolGroup] {
        all.filter { $0.label == label }
    }
}
