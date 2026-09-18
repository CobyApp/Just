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
/// and never in the background — collapsing the player pauses it.
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
    @ObservationIgnored private let log = Logger(subsystem: "com.coby.just", category: "video")
    @ObservationIgnored private let previewPlayer = AVPlayer()
    @ObservationIgnored private let catalog = ITunesCatalog()
    @ObservationIgnored private let youtube: YouTubeClient
    @ObservationIgnored private let directory = VideoDirectory()
    @ObservationIgnored private var videos: [String: String]
    @ObservationIgnored private var alternates: [String: [String]]
    @ObservationIgnored private var channels: [String: VideoDirectory.ChannelUploads]
    @ObservationIgnored private var previewTicker: Task<Void, Never>?
    /// Bumped by every `load`, so a load that has been overtaken can tell.
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var pendingAutoplay = false
    /// Cancels the video if it never starts — see `watchForStall`.
    @ObservationIgnored private var stallWatch: Task<Void, Never>?
    /// How long a video may sit buffering before it is given up on.
    static let stallLimit: Duration = .seconds(15)

    public init(youtube: YouTubeClient = YouTubeClient()) {
        self.youtube = youtube
        let snapshot = directory.restore()
        videos = snapshot.videos
        alternates = snapshot.alternates
        channels = snapshot.channels
        configureAudioSession()
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 99
            MainActor.assumeIsolated { self?.log.info("audio session interruption type \(type)") }
        }
    }

    /// Declares this as a playback app, so the clip is heard in silent mode.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            log.error("audio session: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Loading

    public func load(_ track: Track, autoplay: Bool = true) async {
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
        previewPlayer.pause()
        previewTicker?.cancel()

        do {
            let videoID = try await video(for: track)
            guard generation == loadGeneration else { return }
            startVideo(videoID, autoplay: autoplay)
        } catch {
            guard generation == loadGeneration else { return }
            // No video — the clip, if the catalogue has one.
            do {
                let preview = try await catalog.preview(forSong: track.id)
                guard generation == loadGeneration else { return }
                try startPreview(preview, autoplay: autoplay)
            } catch {
                guard generation == loadGeneration else { return }
                hasVideo = false
                status = .failed(ITunesCatalog.Failure.noPreview.localizedDescription)
            }
        }
    }

    /// The song's video id: remembered, or found on the group's own channels,
    /// or searched for.
    ///
    /// The channels first because they are where the videos are, and a
    /// channel's list costs a hundredth of a search. Only a song the group
    /// has not put on its channels goes to search.
    private func video(for track: Track) async throws -> String {
        if let known = videos[track.id] {
            guard !known.isEmpty else { throw YouTubeClient.Failure.notFound }
            return known
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
            let fitting = YouTubeClient.aboutTheSongsLength(found, track: track, durations: lengths)
            if !fitting.isEmpty { found = fitting }
            log.info("video for \(track.title, privacy: .public) from \(source, privacy: .public): \(found[0].videoID, privacy: .public) (+\(found.count - 1))")
            remember(found[0].videoID, alternates: found.dropFirst().map(\.videoID), for: track.id)
            return found[0].videoID
        } catch YouTubeClient.Failure.notFound {
            log.info("no video found for \(track.title, privacy: .public)")
            remember("", alternates: [], for: track.id)
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
            if let cached = channels[id], !cached.isStale {
                published += cached.videos
                continue
            }
            do {
                let uploads = try await youtube.uploads(ofChannel: id)
                channels[id] = .init(fetchedAt: .now, videos: uploads)
                published += uploads
            } catch YouTubeClient.Failure.noKey {
                throw YouTubeClient.Failure.noKey
            } catch {
                // A channel that would not answer: whatever was cached, even
                // stale, and the others.
                log.error("channel \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                published += channels[id]?.videos ?? []
            }
        }
        persistDirectory()
        return YouTubeClient.rank(published, for: track, channels: ids, strict: true)
            + YouTubeClient.rank(published, for: track, channels: ids, strict: false).filter { loose in
                !YouTubeClient.rank(published, for: track, channels: ids, strict: true).contains(loose)
            }
    }

    private func remember(_ videoID: String, alternates others: [String]? = nil, for trackID: String) {
        videos[trackID] = videoID
        if let others { alternates[trackID] = others }
        persistDirectory()
    }

    private func persistDirectory() {
        let snapshot = VideoDirectory.Snapshot(videos: videos, alternates: alternates, channels: channels)
        let directory = self.directory
        Task.detached(priority: .utility) { directory.persist(snapshot) }
    }

    /// Moves this song to its next video, or gives the song up as having
    /// none. Returns the next id to try.
    ///
    /// For a video that would not play: the search cannot tell in advance,
    /// and the runners-up are usually the same song — the label's audio
    /// track, a live take — which is still the whole song.
    private func advanceVideo() -> String? {
        guard let trackID else { return nil }
        var others = alternates[trackID] ?? []
        if others.isEmpty {
            videos[trackID] = ""
            alternates[trackID] = nil
            persistDirectory()
            return nil
        }
        let next = others.removeFirst()
        videos[trackID] = next
        alternates[trackID] = others
        persistDirectory()
        return next
    }

    private func startVideo(_ videoID: String, autoplay: Bool) {
        isPreview = false
        hasVideo = true
        pendingAutoplay = autoplay
        web.load(videoID: videoID, autoplay: autoplay)
        if autoplay { watchForStall(videoID) }
    }

    /// Some videos never leave 「buffering」 in the embedded player and never
    /// report an error either — the player just spins. Fifteen seconds of
    /// that is a video that will not play here, and the clip takes over, the
    /// same as for a video that refused outright.
    private func watchForStall(_ videoID: String) {
        stallWatch?.cancel()
        stallWatch = Task { [weak self] in
            try? await Task.sleep(for: Self.stallLimit)
            guard let self, !Task.isCancelled, hasVideo, status != .playing, status != .paused else { return }
            log.error("video \(videoID) never started; falling back to the clip")
            pageFailed(code: 0)
        }
    }

    private func startPreview(_ preview: SongPreview, autoplay: Bool) throws {
        guard let url = preview.previewURL else { throw ITunesCatalog.Failure.noPreview }
        log.info("clip \(url.absoluteString, privacy: .public)")
        hasVideo = false
        isPreview = true
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
        web.play()
    }

    public func pause() {
        log.info("pause requested (preview: \(self.isPreview))")
        if isPreview {
            previewPlayer.pause()
            status = .paused
        } else if hasVideo {
            web.pause()
        }
    }

    public func togglePlayback() {
        isPlaying ? pause() : play()
    }

    /// Moves playback to a position in whatever is playing.
    ///
    /// Callers holding a *song* time must check `position.followsLyrics` first.
    public func seek(to time: TimeInterval) {
        let target = max(0, duration > 0 ? min(time, duration) : time)
        if isPreview {
            previewPlayer.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        } else {
            web.seek(to: target)
        }
        currentTime = target
    }

    public func skip(by delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    public func stop() {
        stallWatch?.cancel()
        previewTicker?.cancel()
        previewTicker = nil
        previewPlayer.pause()
        if hasWeb { web.stop() }
        status = .idle
        trackID = nil
        isPreview = false
        hasVideo = false
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
            status = .playing
            stallWatch?.cancel()
        case 2, 0:
            status = .paused
            stallWatch?.cancel()
        case 5: status = .ready
        case 3: if status == .idle || status == .loading { status = .ready }
        default: break
        }
    }

    fileprivate func pageReady() {
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
        if let next = advanceVideo() {
            log.info("video failed (\(code)); trying \(next, privacy: .public)")
            startVideo(next, autoplay: autoplay)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let preview = try await catalog.preview(forSong: trackID)
                guard self.trackID == trackID else { return }
                try startPreview(preview, autoplay: autoplay)
            } catch {
                guard self.trackID == trackID else { return }
                hasVideo = false
                status = .failed("이 곡은 재생할 수 있는 영상을 찾지 못했습니다.")
            }
        }
    }

    // MARK: - Preview clock

    private func startPreviewTicking() {
        previewTicker?.cancel()
        previewTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, isPreview else { return }
                currentTime = previewPlayer.currentTime().seconds
                if let itemDuration = previewPlayer.currentItem?.duration.seconds,
                   itemDuration.isFinite, itemDuration > 0 {
                    duration = itemDuration
                }
                if let item = previewPlayer.currentItem, item.status == .failed {
                    log.error("clip failed: \(item.error?.localizedDescription ?? "?", privacy: .public)")
                }
                if previewPlayer.timeControlStatus == .playing {
                    if status != .playing { status = .playing }
                } else if status == .playing {
                    // Meant to be playing and not: an interruption (another
                    // media session, a call) stopped it. Nobody pressed pause
                    // — that path sets `.paused` — so it is started again.
                    if previewPlayer.rate == 0, let item = previewPlayer.currentItem, item.status == .readyToPlay {
                        if item.duration.isNumeric, previewPlayer.currentTime().seconds >= item.duration.seconds - 0.5 {
                            // The clip simply ended.
                            status = .paused
                        } else {
                            log.info("clip resumed after an interruption")
                            previewPlayer.play()
                        }
                    }
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
    let view: WKWebView
    private unowned let owner: MusicPlayerController
    /// What the page says, for the log — the player's numeric errors are
    /// otherwise invisible from outside the web view.
    let log = Logger(subsystem: "com.coby.just", category: "video")
    private var pageIsReady = false
    private var queued: (videoID: String, autoplay: Bool)?

    init(owner: MusicPlayerController) {
        self.owner = owner
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsPictureInPictureMediaPlayback = false
        view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        super.init()
        configuration.userContentController.add(self, name: "just")
        view.navigationDelegate = self
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
        let call = autoplay ? "loadVideoById" : "cueVideoById"
        run("player.\(call)({videoId: '\(videoID)'});")
    }

    func play() { run("player.playVideo();") }
    func pause() { run("player.pauseVideo();") }
    func seek(to time: TimeInterval) { run("player.seekTo(\(time), true);") }
    func stop() {
        queued = nil
        guard pageIsReady else { return }
        run("player.stopVideo();")
    }

    private func run(_ script: String) {
        view.evaluateJavaScript(script) { _, _ in }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { log.error("page failed to load: \(error.localizedDescription)") }
    }

    nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let event = body["e"] as? String else { return }
        MainActor.assumeIsolated {
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
    var player, tick;
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
          onStateChange: function(ev) { post({e: 'state', s: ev.data, t: player.getCurrentTime(), d: player.getDuration()}); },
          onError: function(ev) { post({e: 'error', c: ev.data}); }
        }
      });
    }
    function startTick() {
      if (tick) clearInterval(tick);
      tick = setInterval(function() {
        if (player && player.getCurrentTime) post({e: 'time', t: player.getCurrentTime(), d: player.getDuration()});
      }, 200);
    }
    </script></body></html>
    """
}
