import JustCore
import JustMusic
import JustSensei
import Observation
import SwiftUI

/// App-wide singletons: one player, one analysis engine.
///
/// Both the system music player and the language-model session are expensive
/// and must not exist twice, so they are owned here and injected rather than
/// constructed per screen.
@MainActor
@Observable
final class AppModel {
    let player = MusicPlayerController()
    let sensei = Sensei()
    let music = AppleMusicClient()
    let reminder = ReviewReminder()

    /// The song the player screen is showing, if any.
    var openTrack: Track?
    var access: AppleMusicClient.Access
    var canPlayFullTracks = true
    var catalogStatus: CatalogStatus = .unknown

    /// Whether catalog requests actually work, which is separate from whether
    /// the user granted access.
    ///
    /// MusicKit mints its developer token from the App ID's MusicKit service.
    /// Signed with a wildcard profile it cannot, and every search fails with an
    /// error that names a token rather than the portal switch behind it — so the
    /// app checks once and says so plainly.
    enum CatalogStatus: Equatable {
        case unknown
        case checking
        case ok
        case failed(String)

        var label: String {
            switch self {
            case .unknown: "확인 안 함"
            case .checking: "확인 중"
            case .ok: "정상"
            case .failed: "실패"
            }
        }

        var advice: String? {
            if case .failed(let message) = self { return message }
            return nil
        }
    }

    var autoAnalysis: AutoAnalysisPolicy {
        didSet { UserDefaults.standard.set(autoAnalysis.rawValue, forKey: Self.autoAnalysisKey) }
    }

    private static let autoAnalysisKey = "analysis.auto"

    init() {
        access = AppleMusicClient.access
        autoAnalysis = UserDefaults.standard.string(forKey: Self.autoAnalysisKey)
            .flatMap(AutoAnalysisPolicy.init(rawValue:)) ?? .unlessLowPower
        sensei.prewarm()
    }

    var isAuthorized: Bool { access == .authorized }

    func requestAccess() async {
        access = await AppleMusicClient.requestAccess()
        if access == .authorized {
            canPlayFullTracks = await AppleMusicClient.canPlayFullTracks()
        }
    }

    /// Only sets state — playback is started by `PlayerScreen`, which owns the
    /// lifetime of the song's session.
    /// Runs a throwaway search to prove the catalog answers.
    func checkCatalog() async {
        guard access == .authorized else {
            catalogStatus = .failed(AppleMusicClient.Failure.notAuthorized.localizedDescription)
            return
        }
        catalogStatus = .checking
        do {
            _ = try await music.search("YOASOBI", limit: 1)
            catalogStatus = .ok
        } catch {
            catalogStatus = .failed(error.localizedDescription)
        }
    }

    func open(_ track: Track) {
        guard track.id != openTrack?.id else { return }
        sensei.reset()
        openTrack = track
    }

    func closePlayer() {
        player.pause()
        openTrack = nil
    }
}
