import Foundation

/// When a song should analyse itself on open.
///
/// The default defers to Low Power Mode rather than inventing its own battery
/// heuristic: the user has already told the system how they want energy spent,
/// and a study app second-guessing that is worse than obeying it.
enum AutoAnalysisPolicy: String, CaseIterable, Identifiable, Sendable {
    case always
    case unlessLowPower
    case never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .always: "항상"
        case .unlessLowPower: "저전력 모드가 아닐 때"
        case .never: "안 함"
        }
    }

    var detail: String {
        switch self {
        case .always:
            "곡을 열면 바로 전곡을 해석합니다."
        case .unlessLowPower:
            "평소에는 자동으로 해석하고, 저전력 모드에서는 줄을 누를 때만 해석합니다."
        case .never:
            "가사 줄을 누른 것만 해석합니다. 전곡 해석은 메뉴에서 직접 실행합니다."
        }
    }

    /// Evaluated at the moment a song opens, not cached — Low Power Mode can be
    /// switched on between two songs.
    var allowsAutoRun: Bool {
        switch self {
        case .always: true
        case .unlessLowPower: !ProcessInfo.processInfo.isLowPowerModeEnabled
        case .never: false
        }
    }
}
