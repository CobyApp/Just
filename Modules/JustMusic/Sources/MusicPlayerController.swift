import AVFoundation
import Foundation
import JustCore
import Observation
import WebKit

/// Playback: the song's video through YouTube's embedded player, or its
/// 30-second clip when no video can be played.
///
/// YouTube because it needs no account. Apple Music played full songs only
/// for subscribers and asked everyone else to allow access to a library they
/// did not have; the embedded player plays the group's own music videos for
/// anyone. The terms of that player are honoured here: the video is on screen
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

    @ObservationIgnored private lazy var web = WebPlayer(owner: self)
    @ObservationIgnored private let previewPlayer = AVPlayer()
    @ObservationIgnored private let catalog = ITunesCatalog()
    @ObservationIgnored private let youtube: YouTubeClient
    @ObservationIgnored private let directory = VideoDirectory()
    @ObservationIgnored private var videos: [String: String]
    @ObservationIgnored private var previewTicker: Task<Void, Never>?
    /// Bumped by every `load`, so a load that has been overtaken can tell.
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var pendingAutoplay = false

    public init(youtube: YouTubeClient = YouTubeClient()) {
        self.youtube = youtube
        videos = directory.restore().videos
        configureAudioSession()
    }

    /// Declares this as a playback app, so the clip is heard in silent mode.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
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

    /// The song's video id, from the directory or from a search.
    private func video(for track: Track) async throws -> String {
        if let known = videos[track.id] {
            guard !known.isEmpty else { throw YouTubeClient.Failure.notFound }
            return known
        }
        do {
            let id = try await youtube.videoID(for: track)
            remember(id, for: track.id)
            return id
        } catch YouTubeClient.Failure.notFound {
            remember("", for: track.id)
            throw YouTubeClient.Failure.notFound
        }
    }

    private func remember(_ videoID: String, for trackID: String) {
        videos[trackID] = videoID
        let snapshot = VideoDirectory.Snapshot(videos: videos)
        let directory = self.directory
        Task.detached(priority: .utility) { directory.persist(snapshot) }
    }

    /// Forgets this song's video, so the next open searches again.
    ///
    /// For a video that turned out not to be embeddable: the search cannot
    /// tell, and the directory should not keep pointing at it.
    private func forgetVideo() {
        guard let trackID else { return }
        videos[trackID] = nil
        let snapshot = VideoDirectory.Snapshot(videos: videos)
        let directory = self.directory
        Task.detached(priority: .utility) { directory.persist(snapshot) }
    }

    private func startVideo(_ videoID: String, autoplay: Bool) {
        isPreview = false
        hasVideo = true
        pendingAutoplay = autoplay
        web.load(videoID: videoID, autoplay: autoplay)
    }

    private func startPreview(_ preview: SongPreview, autoplay: Bool) throws {
        guard let url = preview.previewURL else { throw ITunesCatalog.Failure.noPreview }
        hasVideo = false
        isPreview = true
        web.stop()
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
        previewTicker?.cancel()
        previewTicker = nil
        previewPlayer.pause()
        web.stop()
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
        case 1: status = .playing
        case 2, 0: status = .paused
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
    /// private, 101/150 the owner disallows embedding.
    fileprivate func pageFailed(code: Int) {
        guard hasVideo, let trackID else { return }
        let autoplay = pendingAutoplay
        forgetVideo()
        // The clip instead, and the reader is not told a code.
        Task { [weak self] in
            guard let self else { return }
            do {
                let preview = try await catalog.preview(forSong: trackID)
                guard self.trackID == trackID else { return }
                try startPreview(preview, autoplay: autoplay)
            } catch {
                guard self.trackID == trackID else { return }
                hasVideo = false
                status = .failed(
                    code == 101 || code == 150
                        ? "이 영상은 앱 안에서 재생할 수 없게 되어 있고, 미리듣기도 없습니다."
                        : ITunesCatalog.Failure.noPreview.localizedDescription
                )
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
                if previewPlayer.timeControlStatus == .playing {
                    if status != .playing { status = .playing }
                } else if status == .playing {
                    status = .paused
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
        // The player is told this is youtube.com so embedding is allowed the
        // way it is on the web; the same base the official iOS helper uses.
        view.loadHTMLString(Self.page, baseURL: URL(string: "https://www.youtube.com"))
    }

    func load(videoID: String, autoplay: Bool) {
        guard pageIsReady else {
            queued = (videoID, autoplay)
            return
        }
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

    nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let event = body["e"] as? String else { return }
        MainActor.assumeIsolated {
            switch event {
            case "ready":
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
                owner.pageReported(state: body["s"] as? Int ?? -1)
                owner.pageReported(
                    time: body["t"] as? TimeInterval ?? owner.currentTime,
                    duration: body["d"] as? TimeInterval ?? 0
                )
            case "error":
                owner.pageFailed(code: body["c"] as? Int ?? 0)
            default:
                break
            }
        }
    }

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
        playerVars: { playsinline: 1, controls: 0, rel: 0, fs: 0, disablekb: 1, iv_load_policy: 3, origin: 'https://www.youtube.com' },
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
