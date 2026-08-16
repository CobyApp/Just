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

    /// The song the player screen is showing, if any.
    var openTrack: Track?
    var access: AppleMusicClient.Access
    var canPlayFullTracks = true

    init() {
        access = AppleMusicClient.access
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
