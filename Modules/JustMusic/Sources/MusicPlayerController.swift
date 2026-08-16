import Foundation
import JustCore
// MusicKit's player types are not Sendable-audited yet; the player is only
// ever touched from this main-actor class, so the checks are downgraded here.
@preconcurrency import MusicKit
import Observation

/// Playback through `ApplicationMusicPlayer`.
///
/// Replaces the previous WKWebView/JS bridge outright. Beyond removing a web
/// view from a music app, this matters for the lyric view specifically:
/// `playbackTime` is read directly off the system player instead of arriving
/// over a script-message hop, so the highlighted line lands on the beat.
@MainActor
@Observable
public final class MusicPlayerController {
    public enum Status: Equatable, Sendable {
        case idle
        case loading
        case ready
        case playing
        case paused
        case failed(String)
    }

    public private(set) var status: Status = .idle
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var trackID: String?
    /// False when the account cannot stream catalog content, so the UI can say
    /// why nothing plays instead of failing silently.
    public private(set) var canPlayFullTracks = true

    public var isPlaying: Bool { status == .playing }

    @ObservationIgnored
    private let player = ApplicationMusicPlayer.shared
    @ObservationIgnored
    private let client = AppleMusicClient()
    @ObservationIgnored
    private var ticker: Task<Void, Never>?

    public init() {}

    deinit {
        ticker?.cancel()
    }

    // MARK: - Loading

    public func load(_ track: JustCore.Track, autoplay: Bool = true) async {
        guard track.id != trackID else {
            if autoplay { play() }
            return
        }

        trackID = track.id
        duration = track.duration
        currentTime = 0
        status = .loading

        canPlayFullTracks = await AppleMusicClient.canPlayFullTracks()

        do {
            let song = try await client.song(id: track.id)
            player.queue = [song]
            if let songDuration = song.duration { duration = songDuration }
            try await player.prepareToPlay()
            status = .ready
            startTicking()
            if autoplay { play() }
        } catch {
            status = .failed(
                canPlayFullTracks
                    ? error.localizedDescription
                    : AppleMusicClient.Failure.noSubscription.localizedDescription
            )
        }
    }

    // MARK: - Transport

    public func play() {
        Task {
            do {
                try await player.play()
                status = .playing
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    public func pause() {
        player.pause()
        status = .paused
    }

    public func togglePlayback() {
        isPlaying ? pause() : play()
    }

    public func seek(to time: TimeInterval) {
        let target = max(0, duration > 0 ? min(time, duration) : time)
        player.playbackTime = target
        currentTime = target
    }

    public func skip(by delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    public func stop() {
        ticker?.cancel()
        ticker = nil
        player.stop()
        status = .idle
        trackID = nil
    }

    // MARK: - Position

    /// Polls `playbackTime` rather than observing it.
    ///
    /// `ApplicationMusicPlayer.State` publishes status changes but not a
    /// continuous time signal, so a lyric view needs its own clock. 10 Hz is
    /// comfortably below the cost of a redraw and above the precision a
    /// listener can perceive in a line change.
    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                currentTime = player.playbackTime
                switch player.state.playbackStatus {
                case .playing: if status != .playing { status = .playing }
                case .paused: if status == .playing { status = .paused }
                case .stopped, .interrupted, .seekingBackward, .seekingForward: break
                @unknown default: break
                }
            }
        }
    }
}
