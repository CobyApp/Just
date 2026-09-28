import AVFoundation
import Foundation
import JustCore
import Observation
import os
import WebKit

/// Playback: the song's video through YouTube's embedded player, or its
/// 30-second clip when no video can be played.
///
/// YouTube because it needs no account: the embedded player plays the
/// group's own music videos for anyone. The 30-second catalogue clip is the
/// last resort, for a song with no playable video at all. The terms of that player are honoured here: the video is on screen
/// while it plays (`videoView`, shown by the player screen), never audio alone
/// and never in the background — collapsing the player pauses it, so does
/// leaving the app (`sceneDidChange`), and a play asked for while the video
/// is out of sight waits until it is on screen.
///
/// The clock is read from the page every 200 ms. A lyric line changes on a
/// beat a listener can hear, and five readings a second is well inside that.
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
    /// True while playing the catalogue clip rather than a video.
    public private(set) var isPreview = false
    /// True while a video is loaded — what the stage shows, and what has to
    /// stay visible.
    public private(set) var hasVideo = false

    public var isPlaying: Bool { status == .playing }

    /// Where playback is, saying which clock it is on — see `PlaybackPosition`.
    public var position: PlaybackPosition {
        isPreview ? .excerpt(currentTime) : .inSong(currentTime)
    }

    /// The video, to be placed on screen by whoever is showing the player.
    public var videoView: UIView { web.view }

    @ObservationIgnored private lazy var web: WebPlayer = {
        hasWeb = true
        return WebPlayer(owner: self)
    }()
    /// Whether the page has been created. It is made only for a video: made
    /// for a clip it loaded YouTube's player anyway, and that player's media
    /// session cut the clip off mid-way.
    @ObservationIgnored private var hasWeb = false
    /// The log, whether or not the page exists.
    @ObservationIgnored private let log = Logger(subsystem: "com.coby.ringring", category: "video")
    @ObservationIgnored private let previewPlayer = AVPlayer()
    @ObservationIgnored private let catalog = ITunesCatalog()
    @ObservationIgnored private let youtube: YouTubeClient
    /// Which video plays which song — see `VideoDirectory`.
    @ObservationIgnored private var known: VideoDirectory.Snapshot
    @ObservationIgnored private let writer: VideoDirectoryWriter
    @ObservationIgnored private var writeSequence = 0
    @ObservationIgnored private var previewTicker: Task<Void, Never>?
    /// Bumped by every `load`, so a load that has been overtaken can tell.
    @ObservationIgnored private var loadGeneration = 0
    /// Whether the song should play once its video is ready — carried to the
    /// next video when one refuses.
    @ObservationIgnored private var pendingAutoplay = false
    /// Video lookups in flight, by song id — see `video(for:)`.
    @ObservationIgnored private var lookups: [String: Task<String, any Error>] = [:]
    /// The video the page was last told to play.
    @ObservationIgnored private var currentVideoID: String?
    /// Cancels the video if it never starts — see `watchForStall`.
    @ObservationIgnored private var stallWatch: Task<Void, Never>?
    /// A stall watch asked for before the page was ready, for this video.
    @ObservationIgnored private var stallWatchAwaitsPage: String?
    /// Videos that stalled during this load. Skipped for the rest of it, but
    /// not held against them: a stall is usually the connection.
    @ObservationIgnored private var stalledThisLoad: Set<String> = []
    /// How long a video may sit buffering before it is given up on.
    static let stallLimit: Duration = .seconds(15)
    /// The longest the whole video lookup may take — channels, search,
    /// lengths — before the clip is tried instead. Each request has its own
    /// ten seconds; this bounds a lookup that makes several.
    static let lookupBudget: Duration = .seconds(20)

    /// Play was asked for while the video could not be seen — the player
    /// still opening, the app in the background. Honoured when it can be.
    @ObservationIgnored private var playsWhenOnScreen = false
    /// Whether the app is in front, as the scene last reported.
    @ObservationIgnored private var sceneIsActive = true
    /// Pauses a video a moment after it leaves the screen.
    @ObservationIgnored private var offscreenCheck: Task<Void, Never>?

    /// Set once the audio session has been given its category. Not at
    /// launch: activating a playback session stops whatever the reader was
    /// listening to in another app, before they have asked for anything.
    @ObservationIgnored private var audioSessionConfigured = false
    /// The clip was paused by an interruption, and may resume when the
    /// system says it should.
    @ObservationIgnored private var resumeAfterInterruption = false
    /// Consecutive clock ticks the clip has sat stopped while meant to play.
    @ObservationIgnored private var stoppedTicks = 0
    /// Ticks to wait before restarting a clip nobody paused. The system's own
    /// pauses — a call, headphones pulled out — arrive as notifications just
    /// after the player stops, and they mark the clip paused, which ends the
    /// wait before it could restart the clip over them.
    static let resumeAfterTicks = 3

    public var hasFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    public init(youtube: YouTubeClient = YouTubeClient()) {
        self.youtube = youtube
        let directory = VideoDirectory()
        known = directory.restore()
        writer = VideoDirectoryWriter(directory: directory)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 99
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            MainActor.assumeIsolated {
                self?.audioInterrupted(type: type, options: options)
            }
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            MainActor.assumeIsolated { self?.routeChanged(reason: reason) }
        }
    }

    /// Declares this as a playback app, so the clip is heard in silent mode,
    /// and makes the session current. Called on the way to making a sound.
    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            if !audioSessionConfigured {
                try session.setCategory(.playback, mode: .default)
                audioSessionConfigured = true
            }
            try session.setActive(true)
        } catch {
            log.error("audio session: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Loading

    public func load(_ track: Track, autoplay: Bool = true) async {
        // The same song again is a resume — unless it failed, when opening it
        // again is how the reader retries.
        if track.id == trackID, !hasFailed {
            if autoplay { play() }
            return
        }

        loadGeneration &+= 1
        let generation = loadGeneration

        // Whatever the last song left running goes before anything else, so
        // its page's clock cannot tick into this song's position.
        clearPlayback()
        trackID = track.id
        duration = track.duration
        currentTime = 0
        status = .loading

        var videoError: (any Error)?
        do {
            let videoID = try await videoWithinBudget(for: track)
            guard generation == loadGeneration else { return }
            startVideo(videoID, autoplay: autoplay)
            return
        } catch {
            guard generation == loadGeneration else { return }
            if error.isCancellation { abandonLoad(); return }
            videoError = error
        }
        // No video — the clip, if the catalogue has one.
        do {
            let preview = try await catalog.preview(forSong: track.id)
            guard generation == loadGeneration else { return }
            try startPreview(preview, autoplay: autoplay)
        } catch {
            guard generation == loadGeneration else { return }
            if error.isCancellation { abandonLoad(); return }
            hasVideo = false
            status = .failed(PlaybackFailure.message(videoError: videoError, previewError: error))
        }
    }

    /// A load given up by its caller: nothing about the song is wrong, so
    /// nothing is kept that would stop the next open from trying again.
    private func abandonLoad() {
        log.info("load cancelled")
        trackID = nil
        status = .idle
    }

    /// `video(for:)`, given up after `lookupBudget` as if the network had
    /// timed out.
    private func videoWithinBudget(for track: Track) async throws -> String {
        let budget = Self.lookupBudget
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await self.video(for: track) }
            group.addTask {
                try await Task.sleep(for: budget)
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let found = try await group.next() else { throw CancellationError() }
            return found
        }
    }

    /// The song's video id: remembered, or found on the group's own channels,
    /// or searched for.
    ///
    /// The channels first because they are where the videos are, and a
    /// channel's list costs a hundredth of a search. Only a song the group
    /// has not put on its channels goes to search.
    ///
    /// One lookup per song at a time: a prefetch and the load that follows
    /// it share the same task, so the channels are read once.
    private func video(for track: Track) async throws -> String {
        if case .video(let id) = known.lookup(track.id) { return id }
        if let running = lookups[track.id] { return try await running.value }
        let lookup = Task { try await self.resolveVideo(for: track) }
        lookups[track.id] = lookup
        defer { lookups[track.id] = nil }
        return try await lookup.value
    }

    /// Starts finding a song's video without playing anything.
    ///
    /// Called as soon as a song is opened, so the channels are read and the
    /// video chosen while the lyrics are fetched, the reader picks a reading
    /// and the ad runs — not after all of that. The answer lands in the
    /// directory; the load that follows finds it there, or joins the lookup
    /// if it is still running.
    public func prefetchVideo(for track: Track) {
        guard youtube.hasKey, lookups[track.id] == nil else { return }
        if case .unknown = known.lookup(track.id) {
            Task { _ = try? await self.video(for: track) }
        }
    }

    private func resolveVideo(for track: Track) async throws -> String {
        switch known.lookup(track.id) {
        case .video(let id): return id
        case .noVideo: throw YouTubeClient.Failure.notFound
        case .unknown: break
        }
        let group = IdolGroup.group(forArtist: track.artist)
        let groupChannels = group?.youtubeChannels ?? []
        do {
            var found = try await fromChannels(groupChannels, for: track)
            var source = "the group's channels"
            if found.isEmpty {
                found = try await youtube.videos(for: track, channels: groupChannels)
                source = "search"
            }
            // The lengths decide what is the song and what only mentions it.
            // One request; the ranking above cannot tell a Short from an MV.
            let lengths = (try? await youtube.durations(of: Array(found.prefix(50).map(\.videoID)))) ?? [:]
            // `try?` above swallows a cancellation; an abandoned lookup must
            // not go on to remember an unfiltered answer.
            try Task.checkCancellation()
            let fitting = YouTubeClient.aboutTheSongsLength(found, track: track, durations: lengths)
            if !fitting.isEmpty { found = fitting }
            log.info("video for \(track.title, privacy: .public) from \(source, privacy: .public): \(found[0].videoID, privacy: .public) (+\(found.count - 1))")
            known.record(found[0].videoID, alternates: found.dropFirst().map(\.videoID), for: track.id)
            persistDirectory()
            return found[0].videoID
        } catch YouTubeClient.Failure.notFound {
            log.info("no video found for \(track.title, privacy: .public)")
            known.recordMiss(for: track.id, permanent: false)
            persistDirectory()
            throw YouTubeClient.Failure.notFound
        } catch {
            log.error("video search failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// This song among what the group's channels have published, best first.
    /// Refreshes a channel's list when it is a day old or missing.
    private func fromChannels(_ ids: [String], for track: Track) async throws -> [YouTubeClient.Candidate] {
        var published: [YouTubeClient.Candidate] = []
        for id in ids {
            let cached = known.channels[id]
            if let cached, cached.isDeep, !cached.isStale {
                published += cached.videos
                continue
            }
            do {
                if let cached, cached.isDeep {
                    // Topped up: the pages newer than what is already here,
                    // usually one request.
                    let newer = try await youtube.uploads(ofChannel: id, stoppingAt: Set(cached.videos.map(\.videoID)))
                    known.channels[id] = cached.merging(newer: newer)
                } else {
                    // Missing, or read shallow by an earlier build: in full.
                    let uploads = try await youtube.uploads(ofChannel: id)
                    known.channels[id] = .init(fetchedAt: .now, videos: uploads)
                }
                published += known.channels[id]?.videos ?? []
            } catch YouTubeClient.Failure.noKey {
                throw YouTubeClient.Failure.noKey
            } catch let error where error.isCancellation {
                throw error
            } catch {
                // A channel that would not answer: whatever was cached, even
                // stale, and the others.
                log.error("channel \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                published += known.channels[id]?.videos ?? []
            }
        }
        persistDirectory()
        return YouTubeClient.rank(published, for: track, channels: ids, strict: true)
            + YouTubeClient.rank(published, for: track, channels: ids, strict: false).filter { loose in
                !YouTubeClient.rank(published, for: track, channels: ids, strict: true).contains(loose)
            }
    }

    /// Saves the directory, in order — see `VideoDirectoryWriter`.
    private func persistDirectory() {
        writeSequence &+= 1
        let snapshot = known
        let sequence = writeSequence
        let writer = self.writer
        Task.detached(priority: .utility) { await writer.write(snapshot, sequence: sequence) }
    }

    /// Moves this song to its next video, or gives the song up as having
    /// none. Returns the next id to try.
    ///
    /// For a video that would not play: the search cannot tell in advance,
    /// and the runners-up are usually the same song — the label's audio
    /// track, a live take — which is still the whole song.
    private func advanceVideo(afterError code: Int) -> String? {
        guard let trackID else { return nil }
        if code == 0 {
            // A stall, not an answer from YouTube: slow or offline looks the
            // same. The next candidate is tried for now, but nothing is
            // recorded — writing it down cost good videos their place, and
            // after every candidate stalled once, marked the song as having
            // none for a week.
            if let currentVideoID { stalledThisLoad.insert(currentVideoID) }
            return known.alternates[trackID]?.first { !stalledThisLoad.contains($0) }
        }
        let next = known.advance(trackID, afterError: code)
        persistDirectory()
        return next
    }

    /// Stops and forgets whatever is playing, video or clip. The song's
    /// identity (`trackID`) and `status` are the caller's to set.
    private func clearPlayback() {
        stallWatch?.cancel()
        stallWatch = nil
        stallWatchAwaitsPage = nil
        stalledThisLoad = []
        offscreenCheck?.cancel()
        offscreenCheck = nil
        previewTicker?.cancel()
        previewTicker = nil
        previewPlayer.pause()
        previewPlayer.replaceCurrentItem(with: nil)
        if hasWeb { web.stop() }
        isPreview = false
        hasVideo = false
        currentVideoID = nil
        pendingAutoplay = false
        playsWhenOnScreen = false
        resumeAfterInterruption = false
        stoppedTicks = 0
    }

    private func startVideo(_ videoID: String, autoplay: Bool) {
        // Never the clip and the video together.
        previewTicker?.cancel()
        previewTicker = nil
        previewPlayer.pause()
        stallWatch?.cancel()
        isPreview = false
        hasVideo = true
        currentVideoID = videoID
        pendingAutoplay = autoplay
        // A new video after one that failed mid-play starts over: left at
        // `.playing`, the UI showed playback and the stall watch, which only
        // acts on a video that has not started, never fired.
        status = .loading
        // A video starts only where it can be seen. Until the stage is on
        // screen it is only cued, and `videoWindowChanged` starts it.
        let playsNow = autoplay && canShowVideo
        playsWhenOnScreen = autoplay && !playsNow
        if playsNow { activateAudioSession() }
        web.load(videoID: videoID, autoplay: playsNow)
        if playsNow { watchForStall(videoID) }
    }

    /// Some videos never leave 「buffering」 in the embedded player and never
    /// report an error either — the player just spins. Fifteen seconds of
    /// that is a video that will not play here, and the clip takes over, the
    /// same as for a video that refused outright.
    private func watchForStall(_ videoID: String) {
        stallWatch?.cancel()
        // The clock starts once the page can take the video. Before that it
        // is still fetching YouTube's player script, and on a slow first
        // launch those fifteen seconds were blamed on the video.
        guard hasWeb, web.pageIsReady else {
            stallWatchAwaitsPage = videoID
            return
        }
        stallWatchAwaitsPage = nil
        let generation = loadGeneration
        stallWatch = Task { [weak self] in
            try? await Task.sleep(for: Self.stallLimit)
            guard let self, !Task.isCancelled,
                  generation == loadGeneration, currentVideoID == videoID,
                  hasVideo, status != .playing, status != .paused
            else { return }
            log.error("video \(videoID) never started; falling back to the clip")
            pageFailed(code: 0)
        }
    }

    private func startPreview(_ preview: SongPreview, autoplay: Bool) throws {
        guard let url = preview.previewURL else { throw ITunesCatalog.Failure.noPreview }
        log.info("clip \(url.absoluteString, privacy: .public)")
        stallWatch?.cancel()
        hasVideo = false
        isPreview = true
        currentVideoID = nil
        playsWhenOnScreen = false
        if hasWeb { web.stop() }
        previewPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
        duration = 30
        status = .ready
        startPreviewTicking()
        if autoplay { play() }
    }

    // MARK: - Transport

    public func play() {
        if isPreview {
            activateAudioSession()
            resumeAfterInterruption = false
            stoppedTicks = 0
            // An AVPlayer parked at the end of its item ignores `play()`.
            if let item = previewPlayer.currentItem,
               item.duration.isNumeric,
               previewPlayer.currentTime() >= item.duration {
                previewPlayer.seek(to: .zero)
                currentTime = 0
            }
            previewPlayer.play()
            status = .playing
            return
        }
        guard hasVideo else { return }
        guard canShowVideo else {
            // Out of sight — the mini player's 「이어서 보기」 asks for play
            // while the full screen is still opening. The video starts once
            // its stage is on screen, never before.
            log.info("play deferred until the video is on screen")
            playsWhenOnScreen = true
            return
        }
        playVideoNow()
    }

    private func playVideoNow() {
        playsWhenOnScreen = false
        pendingAutoplay = true
        activateAudioSession()
        web.play()
        // A cued video, pressed play on, can stall like an autoplayed one.
        if status != .playing, let currentVideoID { watchForStall(currentVideoID) }
    }

    public func pause() {
        log.info("pause requested (preview: \(self.isPreview))")
        stallWatch?.cancel()
        stallWatchAwaitsPage = nil
        playsWhenOnScreen = false
        resumeAfterInterruption = false
        if isPreview {
            previewPlayer.pause()
            status = .paused
        } else if hasVideo {
            pendingAutoplay = false
            web.pause()
        }
    }

    public func togglePlayback() {
        isPlaying ? pause() : play()
    }

    /// Moves playback to a position in whatever is playing.
    ///
    /// Callers holding a *song* time must check `position.followsLyrics` first.
    /// Moves within the current song — and only the current song.
    ///
    /// While the next song's video is still being looked up, the page holds
    /// the previous one, stopped. Seeking it anyway — a lyric line tapped
    /// mid-load — started it playing, under the new song's lyrics and art,
    /// with nothing to stop it: its events belong to an old load and are
    /// dropped. That was 「tapping a line changed the song」.
    public func seek(to time: TimeInterval) {
        let target = max(0, duration > 0 ? min(time, duration) : time)
        if isPreview {
            previewPlayer.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        } else if hasVideo, currentVideoID != nil {
            web.seek(to: target)
        } else {
            return
        }
        currentTime = target
    }

    public func skip(by delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    public func stop() {
        loadGeneration &+= 1
        clearPlayback()
        status = .idle
        trackID = nil
    }

    // MARK: - Being seen

    /// Whether a video may play right now: the app in front and the video
    /// in a window.
    private var canShowVideo: Bool {
        sceneIsActive && hasWeb && web.view.window != nil
    }

    /// The app's scene came to the front or left it. A video does not play
    /// where it cannot be seen — YouTube's terms for the embedded player —
    /// so leaving pauses it. The clip is audio, and carries on.
    public func sceneDidChange(isActive: Bool) {
        sceneIsActive = isActive
        if isActive {
            if playsWhenOnScreen, hasVideo, canShowVideo { playVideoNow() }
            return
        }
        playsWhenOnScreen = false
        if hasVideo {
            log.info("scene left the front; pausing the video")
            stallWatch?.cancel()
            web.pause()
        }
    }

    /// The video's view entered or left a window.
    fileprivate func videoWindowChanged(isOnScreen: Bool) {
        offscreenCheck?.cancel()
        offscreenCheck = nil
        if isOnScreen {
            if playsWhenOnScreen, hasVideo, canShowVideo { playVideoNow() }
        } else {
            scheduleOffscreenCheck()
        }
    }

    /// Pauses the video if it is still out of sight in a moment. Not at once:
    /// the stage moving between layouts (lyrics full screen and back) takes
    /// the view out of one window and puts it into the next.
    private func scheduleOffscreenCheck() {
        offscreenCheck?.cancel()
        offscreenCheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled, hasVideo, hasWeb, web.view.window == nil else { return }
            log.info("video left the screen; pausing")
            playsWhenOnScreen = false
            stallWatch?.cancel()
            web.pause()
        }
    }

    // MARK: - The audio session

    private func audioInterrupted(type: UInt, options: UInt) {
        log.info("audio session interruption type \(type)")
        switch AVAudioSession.InterruptionType(rawValue: type) {
        case .began:
            guard status == .playing else { return }
            if isPreview {
                previewPlayer.pause()
                status = .paused
                resumeAfterInterruption = true
            } else if hasVideo {
                // The page reports its own pause; a video is not resumed on
                // the system's say-so, only by the reader.
                stallWatch?.cancel()
                web.pause()
            }
        case .ended:
            guard resumeAfterInterruption else { return }
            resumeAfterInterruption = false
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
            if shouldResume, isPreview, status == .paused { play() }
        default:
            break
        }
    }

    /// Headphones pulled out, a Bluetooth speaker gone: pause, as every
    /// player does, rather than carry on out loud.
    private func routeChanged(reason: UInt) {
        guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
        log.info("audio route lost; pausing")
        resumeAfterInterruption = false
        if isPreview {
            previewPlayer.pause()
            if status == .playing { status = .paused }
        } else if hasVideo {
            stallWatch?.cancel()
            web.pause()
        }
    }

    // MARK: - From the page

    fileprivate func pageReported(time: TimeInterval, duration reported: TimeInterval) {
        guard hasVideo else { return }
        currentTime = time
        if reported > 0 { duration = reported }
    }

    /// YouTube's player states: -1 unstarted, 0 ended, 1 playing, 2 paused,
    /// 3 buffering, 5 cued.
    fileprivate func pageReported(state: Int) {
        guard hasVideo else { return }
        switch state {
        case 1:
            // Started while the app is not in front — the lock screen's or
            // Control Center's play button reaching the page's media session.
            // A video may not play unseen, so it is stopped again.
            guard sceneIsActive else {
                log.info("video started in the background; pausing")
                web.pause()
                return
            }
            status = .playing
            stallWatch?.cancel()
            if hasWeb, web.view.window == nil { scheduleOffscreenCheck() }
        case 2, 0:
            status = .paused
            stallWatch?.cancel()
        case 5: status = .ready
        case 3: if status == .idle || status == .loading { status = .ready }
        default: break
        }
    }

    fileprivate func pageReady() {
        if let waiting = stallWatchAwaitsPage, waiting == currentVideoID, hasVideo {
            watchForStall(waiting)
        }
        guard hasVideo, status == .loading else { return }
        status = .ready
    }

    /// The player's error codes: 2 bad id, 5 HTML5 failure, 100 not found or
    /// private, 101/150 the owner disallows embedding — and 0 from the stall
    /// watch. Whatever the reason, the next video for the song is tried, and
    /// only when there is none does the clip take over.
    fileprivate func pageFailed(code: Int) {
        guard hasVideo, let trackID else { return }
        stallWatch?.cancel()
        let autoplay = pendingAutoplay
        if let next = advanceVideo(afterError: code) {
            log.info("video failed (\(code)); trying \(next, privacy: .public)")
            startVideo(next, autoplay: autoplay)
            return
        }
        // No video left: the stage goes while the clip is looked up.
        if hasWeb { web.stop() }
        hasVideo = false
        currentVideoID = nil
        playsWhenOnScreen = false
        status = .loading
        let generation = loadGeneration
        Task { [weak self] in
            guard let self else { return }
            do {
                let preview = try await catalog.preview(forSong: trackID)
                guard generation == loadGeneration, self.trackID == trackID else { return }
                try startPreview(preview, autoplay: autoplay)
            } catch {
                guard generation == loadGeneration, self.trackID == trackID else { return }
                status = .failed(PlaybackFailure.message(videoError: nil, previewError: error))
            }
        }
    }

    // MARK: - Preview clock

    private func startPreviewTicking() {
        previewTicker?.cancel()
        stoppedTicks = 0
        previewTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, !Task.isCancelled, isPreview else { return }
                currentTime = previewPlayer.currentTime().seconds
                if let itemDuration = previewPlayer.currentItem?.duration.seconds,
                   itemDuration.isFinite, itemDuration > 0 {
                    duration = itemDuration
                }
                if let item = previewPlayer.currentItem, item.status == .failed {
                    log.error("clip failed: \(item.error?.localizedDescription ?? "?", privacy: .public)")
                }
                if previewPlayer.timeControlStatus == .playing {
                    stoppedTicks = 0
                    if status != .playing { status = .playing }
                } else if status == .playing {
                    // Meant to be playing and not. Nobody pressed pause — that
                    // path sets `.paused` — and neither did the system: an
                    // interruption or a lost route sets `.paused` too, and
                    // `resumeAfterTicks` gives its notification time to land.
                    // What is left is another media session (the ad SDK's)
                    // taking the player's rate away, so it is started again.
                    if previewPlayer.rate == 0, let item = previewPlayer.currentItem, item.status == .readyToPlay {
                        if item.duration.isNumeric, previewPlayer.currentTime().seconds >= item.duration.seconds - 0.5 {
                            // The clip simply ended.
                            stoppedTicks = 0
                            status = .paused
                        } else {
                            stoppedTicks += 1
                            if stoppedTicks >= Self.resumeAfterTicks {
                                stoppedTicks = 0
                                log.info("clip resumed after being stopped by another session")
                                previewPlayer.play()
                            }
                        }
                    }
                } else {
                    stoppedTicks = 0
                }
            }
        }
    }
}

// MARK: - The page

/// One web view holding YouTube's IFrame player, kept for the life of the app.
///
/// The page is loaded once; songs are swapped with `loadVideoById`, which is
/// far quicker than reloading the player. Messages come back through
/// `webkit.messageHandlers.just`.
@MainActor
private final class WebPlayer: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let view: VideoWebView
    private unowned let owner: MusicPlayerController
    /// What the page says, for the log — the player's numeric errors are
    /// otherwise invisible from outside the web view.
    let log = Logger(subsystem: "com.coby.ringring", category: "video")
    private(set) var pageIsReady = false
    private var queued: (videoID: String, autoplay: Bool)?
    /// Numbers each video handed to the page. The page stamps every message
    /// with the number it is playing under, and only messages stamped with
    /// `expected` are passed on: the old video's last clock ticks, still in
    /// flight when the next song loads, would otherwise land as the new
    /// song's position — and its late errors would skip the new song's video.
    private var sequence = 0
    /// The number of the video now in the page; nil when it holds none.
    private var expected: Int?

    init(owner: MusicPlayerController) {
        self.owner = owner
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsPictureInPictureMediaPlayback = false
        view = VideoWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        super.init()
        configuration.userContentController.add(self, name: "just")
        view.navigationDelegate = self
        view.onWindowChange = { [unowned owner = self.owner] isOnScreen in
            owner.videoWindowChanged(isOnScreen: isOnScreen)
        }
        // The page needs an https origin of its own: YouTube now checks the
        // embedding page's referer and answers error 152/153 to a page that
        // has none or claims to be youtube.com itself (the old helper trick).
        // Nothing is fetched from this address; it is the app's name as an
        // origin, and the same value is passed to the player as `origin`.
        view.loadHTMLString(Self.page, baseURL: URL(string: Self.origin))
    }

    func load(videoID: String, autoplay: Bool) {
        guard pageIsReady else {
            log.info("page not ready; queued \(videoID)")
            queued = (videoID, autoplay)
            return
        }
        log.info("load \(videoID) autoplay=\(autoplay)")
        sequence &+= 1
        expected = sequence
        let call = autoplay ? "loadVideoById" : "cueVideoById"
        run("gen = \(sequence); player.\(call)({videoId: '\(videoID)'});")
    }

    /// Before the page is ready there is no player to tell; the queued
    /// video is told instead.
    func play() {
        guard pageIsReady else {
            if let queued { self.queued = (queued.videoID, true) }
            return
        }
        run("player.playVideo();")
    }

    func pause() {
        guard pageIsReady else {
            if let queued { self.queued = (queued.videoID, false) }
            return
        }
        run("player.pauseVideo();")
    }

    func seek(to time: TimeInterval) {
        // No video handed over since the last stop: whatever is in the page is
        // a previous song's, and `seekTo` would start it.
        guard pageIsReady, expected != nil else { return }
        run("player.seekTo(\(time), true);")
    }

    func stop() {
        queued = nil
        expected = nil
        guard pageIsReady else { return }
        run("gen = 0; player.stopVideo();")
    }

    private func run(_ script: String) {
        view.evaluateJavaScript(script) { _, _ in }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { log.error("page failed to load: \(error.localizedDescription)") }
    }

    nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            guard let body = message.body as? [String: Any], let event = body["e"] as? String else { return }
            let stamp = body["g"] as? Int
            // Everything but 「ready」 is about a video, and must be about
            // this one.
            if event != "ready", stamp == nil || stamp != expected { return }
            switch event {
            case "ready":
                log.info("player ready")
                pageIsReady = true
                if let queued {
                    self.queued = nil
                    load(videoID: queued.videoID, autoplay: queued.autoplay)
                }
                owner.pageReady()
            case "time":
                owner.pageReported(
                    time: body["t"] as? TimeInterval ?? 0,
                    duration: body["d"] as? TimeInterval ?? 0
                )
            case "state":
                log.info("player state \(body["s"] as? Int ?? -1)")
                owner.pageReported(state: body["s"] as? Int ?? -1)
                owner.pageReported(
                    time: body["t"] as? TimeInterval ?? owner.currentTime,
                    duration: body["d"] as? TimeInterval ?? 0
                )
            case "error":
                log.error("player error \(body["c"] as? Int ?? 0)")
                owner.pageFailed(code: body["c"] as? Int ?? 0)
            default:
                break
            }
        }
    }

    static let origin = "https://utaring.app"

    /// The player fills the page; the page's own controls are off because
    /// the app draws its own transport, and one set of controls is enough.
    private static let page = """
    <!doctype html><html><head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>html,body{margin:0;background:#000;height:100%;overflow:hidden}#p{position:absolute;inset:0}</style>
    </head><body><div id="p"></div>
    <script>
    var player, tick, gen = 0;
    function post(m){ window.webkit.messageHandlers.just.postMessage(m); }
    var tag = document.createElement('script');
    tag.src = 'https://www.youtube.com/iframe_api';
    document.head.appendChild(tag);
    function onYouTubeIframeAPIReady() {
      player = new YT.Player('p', {
        width: '100%', height: '100%',
        playerVars: { playsinline: 1, controls: 0, rel: 0, fs: 0, disablekb: 1, iv_load_policy: 3, origin: 'https://utaring.app' },
        events: {
          onReady: function() { post({e: 'ready'}); startTick(); },
          onStateChange: function(ev) { post({e: 'state', g: gen, s: ev.data, t: player.getCurrentTime(), d: player.getDuration()}); },
          onError: function(ev) { post({e: 'error', g: gen, c: ev.data}); }
        }
      });
    }
    function startTick() {
      if (tick) clearInterval(tick);
      tick = setInterval(function() {
        if (player && player.getCurrentTime) post({e: 'time', g: gen, t: player.getCurrentTime(), d: player.getDuration()});
      }, 200);
    }
    </script></body></html>
    """
}

/// The page's web view, saying when it enters or leaves a window — which is
/// when the video can and cannot be seen.
private final class VideoWebView: WKWebView {
    var onWindowChange: (@MainActor (Bool) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window != nil)
    }
}
