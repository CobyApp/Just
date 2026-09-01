import Foundation
// TranslationSession is not Sendable-audited, and its async methods are not
// actor-isolated, so the compiler treats every call as sending it across a
// boundary. The session is created and used only from this main-actor class,
// one line at a time, so the checks are downgraded here — the same treatment
// MusicKit gets in JustMusic.
@preconcurrency import Translation

/// The system translator, for lines the on-device model cannot answer.
///
/// Apple Intelligence needs recent hardware; Apple's translator does not. On an
/// older device the analysis used to stop at dictionary meanings and no
/// translation at all, which for a reader working through a song is the half
/// that mattered. A literal sentence is not what the model gives — no nuance,
/// no grammar notes, no reading of the singer's tone — but it is a translation,
/// and it is what that device can do.
///
/// Also used on capable devices as the last resort, for the handful of lines the
/// model never manages. See `Sensei.analyzeAll`.
@MainActor
public final class PlainTranslator {
    public static let shared = PlainTranslator()

    /// Off is a real choice: this reaches a system service and downloads a
    /// language pack the first time, and someone may not want either.
    private static let enabledKey = "just.plainTranslation.enabled"

    public var isEnabled: Bool {
        get {
            // Absent means on. The alternative is a device that silently shows
            // no translations until the reader finds a switch they were never
            // told about.
            UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    private static let source = Locale.Language(identifier: "ja")
    private static let target = Locale.Language(identifier: "ko")

    private var session: TranslationSession?
    /// Set once the pair is known to be unusable, so a song's worth of lines
    /// does not each pay for the same failed setup.
    private var isUnavailable = false
    /// Set once the pack has been confirmed present, so the check is paid once
    /// rather than per line.
    private var isInstalled = false

    private init() {}

    /// Whether Japanese to Korean can be translated on this device right now.
    ///
    /// `.installed` means yes. `.supported` means the pack has to be downloaded
    /// first, and that cannot be started from here — see `configuration`.
    public func availability() async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: Self.source, to: Self.target)
    }

    /// What a view passes to `.translationTask` to download the pack.
    ///
    /// The framework only offers the download through that modifier, and that is
    /// the right shape anyway: it puts a system prompt on screen, so it belongs
    /// to a screen the reader opened and not to a background analysis run.
    public static var configuration: TranslationSession.Configuration {
        .init(source: source, target: target)
    }

    /// The Korean for one lyric line, or nil when the device cannot say.
    ///
    /// nil rather than the source text: handing back the Japanese would look
    /// like a translation to every caller and would be written into the record
    /// as one. `Sensei` checks the answer is Korean as well, because a
    /// translator with nothing to work with returns the source unchanged.
    public func translate(_ line: String) async -> String? {
        guard isEnabled, !isUnavailable else { return nil }
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Asked before the session is built, not after. The initializer below
        // is `installedSource:` — it takes the pack being present as given, and
        // on a device where it is not, building one took the app down with it:
        // 「Connection to translationd was interrupted, the process exited or
        // crashed」. The simulator never showed this because it reports the pair
        // unsupported and the path was never entered.
        if !isInstalled {
            guard await availability() == .installed else {
                isUnavailable = true
                return nil
            }
            isInstalled = true
        }

        do {
            return try await currentSession().translate(text).targetText
        } catch {
            // One failure is taken as the answer for this launch. What fails
            // here is the pair and the device, not the sentence, so retrying
            // per line would only be slow in the same way.
            isUnavailable = true
            session = nil
            return nil
        }
    }

    /// Fails while the pack is missing, which is deliberate: the session that
    /// could download it needs a view, so a run that finds nothing installed
    /// stops asking rather than stalling on a prompt nobody can see.
    private func currentSession() throws -> TranslationSession {
        if let session { return session }
        let session = TranslationSession(installedSource: Self.source, target: Self.target)
        self.session = session
        return session
    }
}
