import AVFoundation
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
    /// True while playing a catalog preview clip rather than the full song.
    public private(set) var isPreview = false

    public var isPlaying: Bool { status == .playing }

    @ObservationIgnored
    private let player = ApplicationMusicPlayer.shared
    /// Used only for preview clips. The catalog player cannot play them, and an
    /// AVPlayer cannot play catalog content, so both exist.
    @ObservationIgnored
    private let previewPlayer = AVPlayer()
    @ObservationIgnored
    private let client = AppleMusicClient()
    @ObservationIgnored
    private var ticker: Task<Void, Never>?
    /// Bumped by every `load`, so a load that has been overtaken can tell.
    ///
    /// `load` suspends three times before anything plays. Tapping a second song
    /// while the first is still loading therefore leaves two loads in flight,
    /// and without this the slower one wins on the way out: it queues its own
    /// song and starts it, while `trackID` — and the lyrics on screen — say the
    /// other one.
    @ObservationIgnored
    private var loadGeneration = 0

    public init() {
        configureAudioSession()
    }

    /// Declares this as a playback app.
    ///
    /// Without a category the session defaults to `.soloAmbient`, which obeys
    /// the ringer switch — so the app went silent in vibrate mode, which is
    /// baffling behaviour for something you opened to listen to a song. This was
    /// lost in the move from the web player to MusicKit and has to be set for
    /// the preview path in particular, which is a plain AVPlayer.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    deinit {
        ticker?.cancel()
    }

    // MARK: - Loading

    public func load(_ track: JustCore.Track, autoplay: Bool = true) async {
        guard track.id != trackID else {
            if autoplay { play() }
            return
        }

        loadGeneration &+= 1
        let generation = loadGeneration

        trackID = track.id
        duration = track.duration
        currentTime = 0
        status = .loading

        canPlayFullTracks = await AppleMusicClient.canPlayFullTracks()
        guard generation == loadGeneration else { return }

        do {
            let song = try await client.song(id: track.id)
            guard generation == loadGeneration else { return }

            if canPlayFullTracks {
                try await startCatalogPlayback(song, autoplay: autoplay, generation: generation)
            } else {
                // Without a subscription the catalog will not stream, but the
                // 30-second preview is open to anyone — and a study app is
                // still useful on a clip, since the lyric view is doing the
                // work rather than the audio.
                try startPreviewPlayback(song, autoplay: autoplay)
            }
        } catch {
            // A load that has been overtaken keeps its failure to itself: the
            // song the user is actually waiting on is not the one that failed.
            guard generation == loadGeneration else { return }
            let blameSubscription = AppleMusicClient.access == .authorized
                && !canPlayFullTracks
            status = .failed(
                blameSubscription
                    ? AppleMusicClient.Failure.noPreview.localizedDescription
                    : Self.readableFailure(error)
            )
        }
    }

    private func startCatalogPlayback(_ song: Song, autoplay: Bool, generation: Int) async throws {
        isPreview = false
        previewPlayer.pause()
        player.queue = [song]
        if let songDuration = song.duration { duration = songDuration }
        try await player.prepareToPlay()
        // Preparing is the last suspension point, and the longest. A newer load
        // has already replaced the queue by now, so starting here would play the
        // song the user moved on from.
        guard generation == loadGeneration else { return }
        status = .ready
        startTicking()
        if autoplay { play() }
    }

    private func startPreviewPlayback(_ song: Song, autoplay: Bool) throws {
        guard let url = song.previewAssets?.compactMap(\.url).first else {
            throw AppleMusicClient.Failure.noPreview
        }
        isPreview = true
        previewPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
        // Preview length is not published; it is read off the item once loaded.
        duration = 30
        status = .ready
        startTicking()
        if autoplay { play() }
    }

    /// Keeps framework error domains out of the UI.
    ///
    /// `MPMusicPlayerControllerErrorDomain 오류 1` is what the system player
    /// returns when it has no account to play from — accurate, and useless to
    /// the person reading it.
    private static func readableFailure(_ error: Error) -> String {
        let raw = error.localizedDescription
        guard !raw.contains("ErrorDomain"), !raw.isEmpty else {
            return "이 곡을 재생할 수 없습니다. Apple Music 로그인 상태를 확인해 주세요."
        }
        return raw
    }

    // MARK: - Transport

    public func play() {
        guard !isPreview else {
            previewPlayer.play()
            status = .playing
            return
        }
        Task {
            do {
                try await player.play()
                status = .playing
            } catch {
                status = .failed(Self.readableFailure(error))
            }
        }
    }

    public func pause() {
        if isPreview {
            previewPlayer.pause()
        } else {
            player.pause()
        }
        status = .paused
    }

    public func togglePlayback() {
        isPlaying ? pause() : play()
    }

    public func seek(to time: TimeInterval) {
        let target = max(0, duration > 0 ? min(time, duration) : time)
        if isPreview {
            previewPlayer.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        } else {
            player.playbackTime = target
        }
        currentTime = target
    }

    public func skip(by delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    public func stop() {
        ticker?.cancel()
        ticker = nil
        previewPlayer.pause()
        player.stop()
        status = .idle
        trackID = nil
        isPreview = false
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

                if isPreview {
                    currentTime = previewPlayer.currentTime().seconds
                    if let itemDuration = previewPlayer.currentItem?.duration.seconds,
                       itemDuration.isFinite, itemDuration > 0 {
                        duration = itemDuration
                    }
                    // AVPlayer has no "ended" callback here; the clip simply
                    // stops advancing at its end.
                    if previewPlayer.timeControlStatus == .playing {
                        if status != .playing { status = .playing }
                    } else if status == .playing {
                        status = .paused
                    }
                    continue
                }

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
