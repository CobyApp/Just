import RingRingCore
import RingRingMusic
import RingRingSensei
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
    let music = ITunesCatalog()
    let reminder = ReviewReminder()

    /// The reader's favourite group — 最推し, 「최애」 — if they have picked one.
    ///
    /// Stored as the catalogue id so a renamed group stays picked. It leads
    /// the home screen and lends its colour to the tab bar, the way fans wear
    /// their member colour.
    var oshiID: String? = UserDefaults.standard.string(forKey: AppModel.oshiKey) {
        didSet {
            UserDefaults.standard.set(oshiID, forKey: Self.oshiKey)
            JustStore.publish(oshi: widgetOshi)
        }
    }

    var oshi: IdolGroup? { oshiID.flatMap(IdolGroup.group(id:)) }

    /// The favourite as the widget carries it.
    private var widgetOshi: WidgetSnapshot.Oshi? {
        oshi.map { WidgetSnapshot.Oshi(name: $0.name, hue: $0.hue) }
    }

    func isOshi(_ group: IdolGroup) -> Bool { oshiID == group.id }

    /// Picks the group, or un-picks it if it already was. One favourite:
    /// picking another replaces it.
    func toggleOshi(_ group: IdolGroup) {
        oshiID = isOshi(group) ? nil : group.id
    }

    private static let oshiKey = "oshi.groupID"

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
        var url: URL? { URL(string: "ringring://\(rawValue)") }

        /// Which tab the route lands on. `go(to:)` pushes anything beyond
        /// the tab's root.
        var tab: Tab {
            switch self {
            case .review: .practice
            case .words: .words
            }
        }

        init?(url: URL) {
            guard url.scheme == "ringring" else { return nil }
            // Both spellings appear in the wild: ringring://review has an empty path
            // and a "review" host, while ringring:///review is the reverse.
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
        let storedGoal = UserDefaults.standard.integer(forKey: Self.dailyGoalKey)
        dailyGoal = storedGoal > 0 ? storedGoal : 20
        autoAnalysis = UserDefaults.standard.string(forKey: Self.autoAnalysisKey)
            .flatMap(AutoAnalysisPolicy.init(rawValue:)) ?? .unlessLowPower

        // The store publishes the schedule after every grade and save; the
        // reminder and the badge are how it reaches the user outside the app.
        let reminder = self.reminder
        JustStore.onOutlookChange = { outlook in reminder.update(outlook) }
        JustStore.oshi = widgetOshi
    }

    /// How a line is read: the bundled dictionary for the words and grammar, the
    /// system translator for the sentence.
    var engineLabel: String { "사전 + 시스템 번역" }

    var playbackLabel: String {
        player.isPreview ? "미리듣기 30초" : "YouTube 영상"
    }


    /// Sends the user where a link asked for.
    ///
    /// A reminder that opens the app to wherever the user last was is a reminder
    /// that failed — its whole job is to get them to the cards.
    ///
    /// Picking the tab alone was not enough: 「복습」 landed on the practice
    /// root with the cards one more tap away, and a full-screen player left
    /// open covered whichever tab it picked.
    func go(to route: Route) {
        if openTrack != nil { closePlayer() }
        tab = route.tab
        switch route {
        case .review:
            // Replaces whatever was pushed there: a half-finished quiz is not
            // what a "cards are waiting" link asked to open.
            practicePath = NavigationPath([ReviewRoute()])
        case .words:
            break
        }
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

    /// Where the practice tab is. Here rather than in the screen so a link
    /// from a notification or the widget can push the review cards.
    var practicePath = NavigationPath()

    /// The groups' pictures, restored from disk on first use.
    ///
    /// Owned here rather than as `GroupsScreen`'s `@State`: a `@State`
    /// initial value is evaluated on every init of the screen, and this one
    /// reads the page cache from disk.
    @ObservationIgnored private(set) lazy var groupArtwork = GroupArtworkStore()

    /// Hides the full-screen player, leaving playback alone.
    func closePlayer() {
        openTrack = nil
        // A video may only play while it is on screen — YouTube's terms for
        // the embedded player, and the reason there is no background video.
        // The mini player brings it back.
        if player.hasVideo { player.pause() }
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
