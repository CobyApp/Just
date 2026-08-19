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

    /// The song the full-screen player is showing, if any.
    var openTrack: Track?
    /// The song loaded in the player, whether or not the full screen is up.
    ///
    /// Separate from `openTrack` so dismissing the player does not stop the
    /// music: closing a player and having the song die is not what "close"
    /// means in a music app.
    var nowPlaying: Track?
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

    /// Re-reads the system state without prompting.
    ///
    /// Needed because the user can change the permission in Settings while the
    /// app is suspended, and nothing tells the app when they do.
    func refreshAccess() async {
        access = AppleMusicClient.access
        if access == .authorized {
            canPlayFullTracks = await AppleMusicClient.canPlayFullTracks()
            await checkCatalog()
        }
    }

    func requestAccess() async {
        access = await AppleMusicClient.requestAccess()
        if access == .authorized {
            canPlayFullTracks = await AppleMusicClient.canPlayFullTracks()
            await checkCatalog()
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

    var engineLabel: String {
        sensei.usesOnDeviceModel ? "Apple Intelligence (온디바이스)" : "사전 (오프라인)"
    }

    var playbackLabel: String {
        canPlayFullTracks ? "전곡" : "미리듣기 30초"
    }

    /// The single thing standing between the user and a working catalog, or nil.
    ///
    /// Collapsing access, subscription and catalog state into one optional is
    /// what lets Settings show a problem only when there is one — listing all
    /// three unconditionally is what made the screen read as a diagnostics dump.
    var connectionProblem: ConnectionProblem? {
        switch access {
        case .notDetermined: .needsAuthorization
        case .denied: .denied
        case .restricted: .restricted
        case .authorized:
            if case .failed(let message) = catalogStatus { .catalog(message) } else { nil }
        }
    }

    enum ConnectionProblem {
        case needsAuthorization
        case denied
        case restricted
        case catalog(String)

        var message: String {
            switch self {
            case .needsAuthorization:
                "아직 Apple Music 접근을 허용하지 않았습니다. 곡 검색과 재생에 필요합니다."
            case .denied:
                "접근이 거부되어 있습니다. iOS는 한 번 거부한 권한을 앱에서 다시 물어볼 수 없으므로, 설정에서 직접 켜 주세요."
            case .restricted:
                "스크린 타임이나 기기 관리 정책으로 Apple Music 접근이 제한되어 있습니다."
            case .catalog(let message):
                message
            }
        }

        var actionTitle: String {
            switch self {
            case .needsAuthorization: "허용하기"
            case .denied, .restricted: "설정 열기"
            case .catalog: "다시 확인"
            }
        }

        @MainActor
        func act(openURL: OpenURLAction, app: AppModel) {
            switch self {
            case .needsAuthorization:
                Task { await app.requestAccess() }
            case .denied, .restricted:
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            case .catalog:
                Task { await app.checkCatalog() }
            }
        }
    }

    func open(_ track: Track) {
        openTrack = track
    }

    /// Called once preparation has finished and playback is about to start.
    ///
    /// Separate from `open` so that backing out of a song still being analysed
    /// leaves nothing behind: no mini player for a song that never made a
    /// sound, and whatever was already playing keeps playing.
    func confirmPlaying(_ track: Track) {
        nowPlaying = track
    }

    /// Hides the full-screen player, leaving playback alone.
    func closePlayer() {
        openTrack = nil
    }

    /// Reopens the full screen for whatever is loaded.
    func expandPlayer() {
        guard let nowPlaying else { return }
        openTrack = nowPlaying
    }

    /// Stops and forgets the current song.
    func stopPlayback() {
        player.stop()
        openTrack = nil
        nowPlaying = nil
    }
}
