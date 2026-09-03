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
            "사전과 문법 패턴, 시스템 번역으로 곡 전체를 몇 초 안에 채웁니다. 뜻과 문법은 정확하지만, 문장 해석은 직역에 가깝습니다."
        case .deep:
            "Apple Intelligence가 앞뒤 줄까지 읽고 해석합니다. 훨씬 자연스럽지만 한 곡에 몇 분이 걸립니다."
        }
    }

    /// What the mode is called where a line shows which engine answered it.
    public var badge: String {
        switch self {
        case .quick: "빠른 해석"
        case .deep: "정밀 해석"
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
}
