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
        case starto = "STARTO"
        case exileTribe = "EXILE TRIBE"
        case bmsg = "BMSG"
        case boyOther = "오디션 · 보이그룹"
        case bandRock = "밴드"
        case soloUnit = "솔로 · 유닛"
        case vocaloP = "보컬로이드 P"
        case vocaloSinger = "싱어 · 우타이테"
        case anisongSinger = "아니송 싱어"
        case anisongBand = "아니송 밴드 · 유닛"
        case seiyuu = "성우 아티스트"
        case more = "그 밖의 인기 그룹"

        /// Whether the section names who the group belongs to, and so is
        /// worth repeating on the group's own page. The last section is only
        /// a shelf.
        public var namesAFamily: Bool { self != .more }

        /// The broad genre this section belongs to, for the home filter. Ten
        /// fine sections are too many to scan; five genres are not.
        public var genre: Genre {
            switch self {
            case .starto, .exileTribe, .bmsg, .boyOther: .boy
            case .bandRock, .soloUnit: .band
            case .vocaloP, .vocaloSinger: .vocalo
            case .anisongSinger, .anisongBand, .seiyuu: .anime
            default: .girl
            }
        }
    }

    /// The home screen's top-level filter — coarser than `Label`.
    public enum Genre: String, CaseIterable, Sendable {
        case girl = "여자 아이돌"
        case boy = "남자 아이돌"
        case band = "밴드 · 아티스트"
        case vocalo = "보컬로이드"
        case anime = "애니송"

        /// The sections under this genre, in roster order.
        public var labels: [Label] { Label.allCases.filter { $0.genre == self } }
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
    public static let all: [IdolGroup] = [
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
        // Boy idols and dance & vocal groups.
        .init(id: "1772019148", name: "Snow Man", readingKo: "스노우맨", label: .starto, hue: 0.58,
              aliases: ["スノーマン", "スノ"]),
        .init(id: "1808322699", name: "SixTONES", readingKo: "스톤즈", label: .starto, hue: 0.02,
              aliases: ["ストーンズ", "スト"]),
        .init(id: "1758080234", name: "なにわ男子", readingKo: "나니와단시", label: .starto, hue: 0.14,
              aliases: ["Naniwa Danshi", "なにわ"]),
        .init(id: "1745727874", name: "King & Prince", readingKo: "킹앤프린스", label: .starto, hue: 0.72,
              aliases: ["キング＆プリンス", "キンプリ"]),
        .init(id: "555230743", name: "Hey! Say! JUMP", readingKo: "헤이세이점프", label: .starto, hue: 0.50,
              aliases: ["ヘイセイジャンプ"]),
        .init(id: "1579021180", name: "BE:FIRST", readingKo: "비퍼스트", label: .bmsg, hue: 0.66,
              aliases: ["ビーファースト"]),
        .init(id: "1500272115", name: "JO1", readingKo: "제이오원", label: .boyOther, hue: 0.98,
              aliases: ["ジェイオーワン"]),
        .init(id: "1587161346", name: "INI", readingKo: "아이엔아이", label: .boyOther, hue: 0.86,
              aliases: ["アイエヌアイ"]),
        .init(id: "786833865", name: "Da-iCE", readingKo: "다이스", label: .boyOther, hue: 0.30,
              aliases: ["ダイス"]),

        // Bands and solo artists.
        .init(id: "1490256993", name: "YOASOBI", readingKo: "요아소비", label: .soloUnit, hue: 0.62,
              aliases: ["ヨアソビ", "よあそび"]),
        .init(id: "960568308", name: "Official髭男dism", readingKo: "히게단", label: .bandRock, hue: 0.55,
              aliases: ["OFFICIAL HIGE DANDISM", "ヒゲダン", "髭男"]),
        .init(id: "962221033", name: "Mrs. GREEN APPLE", readingKo: "미세스 그린 애플", label: .bandRock, hue: 0.34,
              aliases: ["ミセスグリーンアップル", "ミセス"]),
        .init(id: "1258439196", name: "King Gnu", readingKo: "킹누", label: .bandRock, hue: 0.00,
              aliases: ["キングヌー"]),
        .init(id: "1487570516", name: "Vaundy", readingKo: "바운디", label: .soloUnit, hue: 0.08,
              aliases: ["バウンディ"]),
        .init(id: "302361237", name: "back number", readingKo: "백넘버", label: .bandRock, hue: 0.60,
              aliases: ["バックナンバー", "バクナン"]),
        .init(id: "91160335", name: "RADWIMPS", readingKo: "래드윔프스", label: .bandRock, hue: 0.52,
              aliases: ["ラッドウィンプス", "ラッド"]),
        .init(id: "252239625", name: "ONE OK ROCK", readingKo: "원오크록", label: .bandRock, hue: 0.03,
              aliases: ["ワンオクロック", "ワンオク"]),
        .init(id: "1492604670", name: "Ado", readingKo: "아도", label: .soloUnit, hue: 0.75,
              aliases: ["アド"]),
        .init(id: "1165017710", name: "あいみょん", readingKo: "아이묭", label: .soloUnit, hue: 0.95,
              aliases: ["aimyon", "アイミョン"]),
        .init(id: "1250709916", name: "ヨルシカ", readingKo: "요루시카", label: .soloUnit, hue: 0.48,
              aliases: ["Yorushika", "よるしか"]),
        .init(id: "1428083875", name: "ずっと真夜中でいいのに。", readingKo: "즈토마요", label: .soloUnit, hue: 0.70,
              aliases: ["ZUTOMAYO", "ずとまよ", "ずっと真夜中でいいのに"]),
        .init(id: "454694621", name: "SEKAI NO OWARI", readingKo: "세카오와", label: .bandRock, hue: 0.40,
              aliases: ["セカイノオワリ", "セカオワ"]),
        .init(id: "747734869", name: "緑黄色社会", readingKo: "료쿠샤카", label: .bandRock, hue: 0.28,
              aliases: ["Ryokuoushoku Shakai", "リョクシャカ"]),
        .init(id: "1229933633", name: "Saucy Dog", readingKo: "사우시독", label: .bandRock, hue: 0.05,
              aliases: ["サウシードッグ", "サウシー"]),
        .init(id: "956011835", name: "マカロニえんぴつ", readingKo: "마카로니엔피츠", label: .bandRock, hue: 0.13,
              aliases: ["Macaroni Empitsu", "マカえんぴつ", "マカえん"]),
        .init(id: "1646020674", name: "結束バンド", readingKo: "결속밴드", label: .bandRock, hue: 0.92,
              aliases: ["kessoku band", "けっそくバンド"]),
        .init(id: "74456960", name: "スピッツ", readingKo: "스핏츠", label: .bandRock, hue: 0.35,
              aliases: ["Spitz"]),
        .init(id: "185088141", name: "BUMP OF CHICKEN", readingKo: "범프 오브 치킨", label: .bandRock, hue: 0.64,
              aliases: ["バンプオブチキン", "バンプ"]),
        .init(id: "252312257", name: "サカナクション", readingKo: "사카낙션", label: .bandRock, hue: 0.56,
              aliases: ["sakanaction", "サカナ"]),
        // Boy idols — more of them.
        .init(id: "1797624061", name: "timelesz", readingKo: "타임리즈", label: .starto, hue: 0.60,
              aliases: ["タイムレス", "セクゾ", "Sexy Zone"]),
        .init(id: "1649344367", name: "Travis Japan", readingKo: "트래비스 재팬", label: .starto, hue: 0.55,
              aliases: ["トラビスジャパン", "トラジャ"]),
        .init(id: "1835325063", name: "WEST.", readingKo: "웨스트", label: .starto, hue: 0.08,
              aliases: ["ジャニーズWEST", "ウエスト"]),
        .init(id: "1877076596", name: "Aぇ! group", readingKo: "에이그룹", label: .starto, hue: 0.42,
              aliases: ["Ae! group", "エーグループ"]),
        .init(id: "1356706755", name: "M!LK", readingKo: "밀크", label: .boyOther, hue: 0.90,
              aliases: ["ミルク"]),
        .init(id: "1528939679", name: "OWV", readingKo: "오더블유브이", label: .boyOther, hue: 0.68,
              aliases: ["オウブ"]),
        .init(id: "1674961337", name: "DXTEEN", readingKo: "디엑스틴", label: .boyOther, hue: 0.78,
              aliases: ["ディーエックスティーン"]),
        .init(id: "1678109085", name: "MAZZEL", readingKo: "마젤", label: .bmsg, hue: 0.20,
              aliases: ["マーゼル"]),
        .init(id: "1193836423", name: "THE RAMPAGE", readingKo: "더 램페이지", label: .exileTribe, hue: 0.02,
              aliases: ["ザランページ", "ランページ"]),
        .init(id: "591740317", name: "GENERATIONS", readingKo: "제너레이션즈", label: .exileTribe, hue: 0.62,
              aliases: ["ジェネレーションズ", "ジェネ"]),
        .init(id: "1443863086", name: "FANTASTICS", readingKo: "판타스틱스", label: .exileTribe, hue: 0.34,
              aliases: ["ファンタスティックス"]),

        // Vocaloid — 初音ミク and the producers who define the sound.
        .init(id: "307078957", name: "初音ミク", readingKo: "하츠네 미쿠", label: .vocaloSinger, hue: 0.48,
              aliases: ["Hatsune Miku", "ミク", "ボカロ"]),
        .init(id: "353899348", name: "DECO*27", readingKo: "데코니나", label: .vocaloP, hue: 0.98,
              aliases: ["デコ*27", "デコにーな"]),
        .init(id: "473591721", name: "ピノキオピー", readingKo: "피노키오피", label: .vocaloP, hue: 0.14,
              aliases: ["PinocchioP", "ピノキオP"]),
        .init(id: "329020708", name: "Kikuo", readingKo: "키쿠오", label: .vocaloP, hue: 0.72,
              aliases: ["きくお"]),
        .init(id: "359584491", name: "wowaka", readingKo: "워와카", label: .vocaloP, hue: 0.55,
              aliases: ["ヲワカ", "ボカロP"]),
        .init(id: "320815306", name: "Neru", readingKo: "네루", label: .vocaloP, hue: 0.02,
              aliases: ["ネル"]),
        .init(id: "1080967231", name: "Eve", readingKo: "이브", label: .vocaloSinger, hue: 0.62,
              aliases: ["イブ"]),
        .init(id: "614405787", name: "まふまふ", readingKo: "마후마후", label: .vocaloSinger, hue: 0.86,
              aliases: ["Mafumafu"]),
        .init(id: "524265966", name: "りぶ", readingKo: "리부", label: .vocaloSinger, hue: 0.30,
              aliases: ["Rib"]),

        // Anime songs (アニソン).
        .init(id: "573943518", name: "LiSA", readingKo: "리사", label: .anisongSinger, hue: 0.95,
              aliases: ["リサ"]),
        .init(id: "569972619", name: "Aimer", readingKo: "에메", label: .anisongSinger, hue: 0.68,
              aliases: ["エメ"]),
        .init(id: "548139430", name: "ClariS", readingKo: "클라리스", label: .anisongSinger, hue: 0.90,
              aliases: ["クラリス"]),
        .init(id: "328794122", name: "fripSide", readingKo: "프립사이드", label: .anisongSinger, hue: 0.60,
              aliases: ["フリップサイド"]),
        .init(id: "986704143", name: "OxT", readingKo: "오엑스티", label: .anisongBand, hue: 0.05,
              aliases: ["オーエックスティー"]),
        .init(id: "624956375", name: "FLOW", readingKo: "플로우", label: .anisongBand, hue: 0.02,
              aliases: ["フロウ"]),
        .init(id: "266646351", name: "GRANRODEO", readingKo: "그랜로데오", label: .anisongBand, hue: 0.08,
              aliases: ["グランロデオ"]),
        .init(id: "266646521", name: "JAM Project", readingKo: "잼 프로젝트", label: .anisongBand, hue: 0.62,
              aliases: ["ジャムプロジェクト", "ジャムプロ"]),
        .init(id: "569938402", name: "藍井エイル", readingKo: "아오이 에일", label: .anisongSinger, hue: 0.58,
              aliases: ["Eir Aoi", "エイル"]),
        .init(id: "570031182", name: "春奈るな", readingKo: "하루나 루나", label: .anisongSinger, hue: 0.92,
              aliases: ["Luna Haruna"]),
        .init(id: "73407309", name: "高橋洋子", readingKo: "다카하시 요코", label: .anisongSinger, hue: 0.00,
              aliases: ["Yoko Takahashi"]),
        .init(id: "269552506", name: "宮野真守", readingKo: "미야노 마모루", label: .seiyuu, hue: 0.66,
              aliases: ["Mamoru Miyano"]),
        .init(id: "308629932", name: "水樹奈々", readingKo: "미즈키 나나", label: .seiyuu, hue: 0.75,
              aliases: ["Nana Mizuki", "ナナ"]),
        .init(id: "2299478", name: "angela", readingKo: "안젤라", label: .anisongBand, hue: 0.30,
              aliases: ["アンジェラ"]),

        // Kenshi Yonezu — Hachi as a Vocaloid producer, now one of Japan's biggest.
        .init(id: "530814268", name: "米津玄師", readingKo: "요네즈 켄시", label: .soloUnit, hue: 0.45,
              aliases: ["Kenshi Yonezu", "ハチ", "ヨネヅケンシ"]),
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
    public static func group(forArtist artist: String) -> IdolGroup? {
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
