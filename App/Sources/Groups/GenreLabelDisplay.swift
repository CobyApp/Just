import RingRingCore
import SwiftUI

/// Localized names for the home filter's genres and sections.
///
/// The enums store Korean raw values, and `Text(rawValue)` would render them
/// verbatim. These literals live in the app target instead, so the String
/// Catalog extracts and translates them; the proper-name sections (KAWAII LAB.,
/// 坂道シリーズ, …) carry no English entry and fall back to their own name.
extension IdolGroup.Genre {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .girl: "여자 아이돌"
        case .boy: "남자 아이돌"
        case .band: "밴드 · 아티스트"
        case .vocalo: "보컬로이드"
        case .anime: "애니송"
        }
    }
}

extension IdolGroup.Label {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .kawaiiLab: "KAWAII LAB."
        case .equalLove: "=LOVE · ≠ME · ≒JOY"
        case .sakamichi: "坂道シリーズ"
        case .fortyEight: "48グループ"
        case .helloProject: "Hello! Project"
        case .stardust: "STARDUST"
        case .starto: "STARTO"
        case .exileTribe: "EXILE TRIBE"
        case .bmsg: "BMSG"
        case .boyOther: "오디션 · 보이그룹"
        case .bandRock: "밴드"
        case .soloUnit: "솔로 · 유닛"
        case .vocaloP: "보컬로이드 P"
        case .vocaloSinger: "싱어 · 우타이테"
        case .anisongSinger: "아니송 싱어"
        case .anisongBand: "아니송 밴드 · 유닛"
        case .seiyuu: "성우 아티스트"
        case .more: "그 밖의 인기 그룹"
        }
    }
}
