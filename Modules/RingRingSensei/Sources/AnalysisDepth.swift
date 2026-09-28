import Foundation

/// How much work a song's analysis is allowed to do.
///
/// Both modes answer the same three questions — what the words mean, what
/// grammar the line uses, what the line says — and they differ in what answers
/// them. Quick asks the bundled dictionary, a pattern list and the system
/// translator, and finishes a song in about the time it takes to read this
/// sentence. Deep asks Apple Intelligence, which reads the line in the context
/// of the ones around it and takes a few minutes over a full song.
///
/// This started as a device fact rather than a choice: without Apple
/// Intelligence the analyser fell back to the dictionary, and with it there was
/// no way to decline. But the fallback is not only for old hardware — someone
/// who wants the chorus glossed *now*, or is on battery, or has already read the
/// song once, is well served by the fast answer, and the slow one is a cost they
/// did not choose. So the fallback became a mode, and the mode became a setting.
public enum AnalysisDepth: String, CaseIterable, Identifiable, Sendable {
    /// Dictionary, grammar patterns and the system translator. No model.
    case quick
    /// Apple Intelligence, with the dictionary correcting its facts.
    case deep

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .quick: "빠르게"
        case .deep: "정확하게"
        }
    }

    public var detail: String {
        switch self {
        case .quick:
            "몇 초면 끝납니다. 단어 뜻과 문법은 정확하고, 문장은 직역에 가깝습니다."
        case .deep:
            "AI가 앞뒤 줄까지 읽고 자연스럽게 옮깁니다. 한 곡에 몇 분 걸립니다."
        }
    }

    /// What the mode is called where a line shows which engine answered it.
    public var badge: String {
        switch self {
        case .quick: "빠른 번역"
        case .deep: "AI 번역"
        }
    }
}

/// The chosen mode, remembered across launches.
///
/// `resolved` is what the analyser actually runs, and it is not always what was
/// chosen: on a device without Apple Intelligence deep is not on offer, so the
/// stored choice is reported back as quick rather than as a promise the device
/// cannot keep.
@MainActor
public enum AnalysisDepthPreference {
    private static let key = "just.analysis.depth"

    /// What the reader picked, whether or not this device can do it.
    ///
    /// Quick by default, deep on request. This was the other way round on the
    /// reasoning that someone studying lyrics wants the good reading of them —
    /// which is true, but not at the price of the first thing they see being a
    /// progress bar. Quick fills a whole song in seconds; deep takes minutes,
    /// and minutes are what a person notices.
    ///
    /// Asked for rather than assumed, in two places: the setting, and the
    /// 「이 줄만 정확하게」 button on any line worth the wait. Wanting the model
    /// on one line is far commoner than wanting it on all fifty.
    public static var chosen: AnalysisDepth {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let depth = AnalysisDepth(rawValue: raw)
            else { return .quick }
            return depth
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    public static func resolved(modelIsAvailable: Bool) -> AnalysisDepth {
        modelIsAvailable ? chosen : .quick
    }

    private static let asksKey = "just.analysis.asksEveryTime"

    /// Whether opening a song asks which reading to make.
    ///
    /// On by default. The choice used to live only in settings, where nobody
    /// looks while a progress bar is filling; asking at the moment the wait
    /// begins is asking when the answer matters. A reader who always wants the
    /// same one turns it off from the prompt itself.
    public static var asksEveryTime: Bool {
        get { UserDefaults.standard.object(forKey: asksKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: asksKey) }
    }
}
