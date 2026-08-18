import Foundation

/// How large the lyric type is set.
///
/// A reading surface needs this: the same screen is used propped on a desk and
/// held at arm's length, and the app's own lyric sizes are fixed rather than
/// following Dynamic Type, so there would otherwise be no way to adjust them.
enum LyricTextSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large
    case extraLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "작게"
        case .medium: "보통"
        case .large: "크게"
        case .extraLarge: "아주 크게"
        }
    }

    /// Multiplies the theme's lyric sizes, so the ratio between the active line,
    /// the inactive lines and the translation stays intact.
    var scale: Double {
        switch self {
        case .small: 0.85
        case .medium: 1
        case .large: 1.18
        case .extraLarge: 1.36
        }
    }

    private static let key = "lyrics.textSize"

    static var stored: LyricTextSize {
        UserDefaults.standard.string(forKey: key)
            .flatMap(LyricTextSize.init(rawValue:)) ?? .medium
    }

    func store() {
        UserDefaults.standard.set(rawValue, forKey: Self.key)
    }
}
