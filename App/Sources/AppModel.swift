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

    /// Which tab is showing.
    ///
    /// Held here rather than in `RootView`'s own state so a screen can send the
    /// user somewhere else — an empty word list has nothing to offer except the
    /// song list, and it could not reach it from inside its own tab.
    var tab: Tab = .groups

    /// The tab bar, in order.
    ///
    /// 「오늘」 used to lead and is gone. What it did is already elsewhere —
    /// 「이어서 공부하기」 sits at the top of browse, the review queue sits at
    /// the top of practice — so it was a screen you passed through on the way
    /// to somewhere else. Songs are what the app is for, so songs are what it
    /// opens on.
    enum Tab: Hashable {
        case groups, mySongs, words, practice
    }

    /// The song the full-screen player is showing, if any.
    var openTrack: Track?
    enum Route: String {
        case review
        case words

        /// The URL a notification or widget carries.
        var url: URL? { URL(string: "just://\(rawValue)") }

        /// Which tab the route lands on. Both screens push further in
        /// themselves, so the route only has to pick the tab.
        var tab: Tab {
            switch self {
            case .review: .practice
            case .words: .words
            }
        }

        init?(url: URL) {
            guard url.scheme == "just" else { return nil }
            // Both spellings appear in the wild: just://review has an empty path
            // and a "review" host, while just:///review is the reverse.
            let name = url.host ?? url.pathComponents.last
            guard let name, let route = Route(rawValue: name) else { return nil }
            self = route
        }
    }

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

    /// Cards per day the progress ring fills toward.
    var dailyGoal: Int {
        didSet { UserDefaults.standard.set(dailyGoal, forKey: Self.dailyGoalKey) }
    }

    private static let dailyGoalKey = "review.dailyGoal"
    static let dailyGoalChoices = [10, 20, 30, 50]

    var autoAnalysis: AutoAnalysisPolicy {
        didSet { UserDefaults.standard.set(autoAnalysis.rawValue, forKey: Self.autoAnalysisKey) }
    }

    private static let autoAnalysisKey = "analysis.auto"

    init() {
        access = AppleMusicClient.access
        let storedGoal = UserDefaults.standard.integer(forKey: Self.dailyGoalKey)
        dailyGoal = storedGoal > 0 ? storedGoal : 20
        autoAnalysis = UserDefaults.standard.string(forKey: Self.autoAnalysisKey)
            .flatMap(AutoAnalysisPolicy.init(rawValue:)) ?? .unlessLowPower
        sensei.prewarm()
    }

    var isAuthorized: Bool { access == .authorized }

    /// Re-reads the system state without prompting.
    ///
    /// Needed because the user can change the permission in Settings while the
    /// app is suspended, and nothing tells the app when they do.
    /// Reads the permission, and asks for it the first time.
    ///
    /// Reading alone was not enough: iOS shows the Apple Music prompt only when
    /// `MusicAuthorization.request()` is called, so an app that merely checks
    /// the status never gets asked — the reader had to find a button to make
    /// the system ask them. Every screen here needs the catalog, so the first
    /// launch asks.
    ///
    /// Asking when it is already decided is harmless: iOS answers from the
    /// existing choice without showing anything.
    func prepareAccess() async {
        if AppleMusicClient.access == .notDetermined {
            await requestAccess()
            return
        }
        await refreshAccess()
    }

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
            // Asked with a group from the roster, which is now the only kind
            // of catalog request the app makes.
            _ = try await music.songs(forArtist: IdolGroup.all[0].id, limit: 1)
            catalogStatus = .ok
        } catch {
            catalogStatus = .failed(error.localizedDescription)
        }
    }

    /// What is answering right now — the mode, not merely what the device can
    /// do. Availability used to be the whole story; now the reader chooses, and
    /// a device that *can* run Apple Intelligence but is set to quick should not
    /// claim to be using it.
    var engineLabel: String {
        guard sensei.usesOnDeviceModel else { return "사전 (오프라인)" }
        switch sensei.depth {
        case .quick: return "빠른 번역"
        case .deep: return "AI 번역"
        }
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

    /// Sends the user where a link asked for.
    ///
    /// A reminder that opens the app to wherever the user last was is a reminder
    /// that failed — its whole job is to get them to the cards.
    func go(to route: Route) {
        tab = route.tab
    }

    /// What the current song was opened from. Drives 이전곡/다음곡.
    private(set) var queue: PlaybackQueue = .empty

    /// Opens a song, remembering the list it came from.
    ///
    /// A song opened on its own — a deep link, a widget — is a queue of one,
    /// and the step buttons are simply off.
    func open(_ track: Track, in list: [Track] = []) {
        queue = PlaybackQueue(list.isEmpty ? [track] : list)
        openTrack = track
    }

    var nextTrack: Track? { (nowPlaying ?? openTrack).flatMap(queue.next(after:)) }
    var previousTrack: Track? { (nowPlaying ?? openTrack).flatMap(queue.previous(before:)) }

    /// Steps within the queue. Opens the player on the new song, because that
    /// is where a song is prepared — its lyrics and translation — before it
    /// plays; switching audio silently underneath the old lyrics would be
    /// worse than showing the new screen.
    func playNext() { if let track = nextTrack { openTrack = track } }
    func playPrevious() { if let track = previousTrack { openTrack = track } }

    /// Called once preparation has finished and playback is about to start.
    ///
    /// Separate from `open` so that backing out of a song still being analysed
    /// leaves nothing behind: no mini player for a song that never made a
    /// sound, and whatever was already playing keeps playing.
    func confirmPlaying(_ track: Track) {
        nowPlaying = track
    }

    /// Where the home tab is — the group whose songs are open, if any.
    ///
    /// Held here rather than as the screen's own `@State` because the view tree
    /// above it can be rebuilt (see `MiniPlayerAccessory`), and a rebuilt
    /// `NavigationStack` with its own state starts over at the grid.
    var groupsPath = NavigationPath()

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
