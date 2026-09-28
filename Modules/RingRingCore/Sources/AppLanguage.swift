import Foundation

/// The language the app speaks — its interface and its study content both.
///
/// Tied to the localization iOS actually chose for the bundle, so the meanings,
/// the sentence translations and the buttons are never in three different
/// languages: whatever `Localizable.xcstrings` resolved to is what the
/// dictionary, the grammar notes and the translator target as well.
///
/// Only two, because those are the two the content exists in: Korean, which the
/// app was written in, and English, which JMdict supplies natively. Anything
/// else falls to English rather than to a half-translated screen.
public enum AppLanguage: String, Sendable, CaseIterable {
    case ko
    case en

    /// What iOS picked for this launch. `preferredLocalizations` is the app's
    /// own resolved list — the device's languages filtered to the ones the
    /// bundle ships — so it matches exactly what the String Catalog is showing.
    public static var current: AppLanguage {
        let chosen = Bundle.main.preferredLocalizations.first ?? "en"
        return chosen.hasPrefix("ko") ? .ko : .en
    }

    /// The BCP-47 code the system translator wants for its target.
    public var translationCode: String { rawValue }
}
