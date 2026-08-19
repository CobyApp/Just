# 곡을 열면 먼저 다 해석하고 재생 — 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 곡을 고르면 전곡 해석이 끝날 때까지 준비 화면을 보여주고, 끝난 뒤에 재생과 가사 화면으로 넘어간다.

**Architecture:** 준비 단계는 새 화면이 아니라 `PlayerScreen` 안의 한 상태다. `SongSession`이 `phase`를 들고 `prepare()`에서 가사 로딩과 해석 한 바퀴를 끝낸 뒤 `.ready`가 된다. 재생 시작과 `nowPlaying` 확정은 `.ready` 이후로 미뤄, 중단하고 나갔을 때 울린 적 없는 곡의 미니플레이어가 남지 않게 한다.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing, Tuist

**Spec:** `docs/superpowers/specs/2026-08-19-analyze-before-play-design.md`

## Global Constraints

- 커밋 메시지는 한국어 conventional commits. 본문은 `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`로 끝낸다.
- 소스 주석은 영어로 쓴다. 사용자에게 보이는 문자열은 한국어로 둔다.
- 테스트 이름은 한국어 서술문. Swift Testing(`@Test`, `#expect`)을 쓴다.
- 앱 타깃(`App/Sources`)은 테스트 대상이 아니다. 테스트할 로직은 `Modules/` 안에 둔다.
- 빌드·테스트 명령:
  `xcodebuild -workspace Just.xcworkspace -scheme Just -destination 'platform=iOS Simulator,name=iPhone 17' test`
- `Project.swift`를 바꿨을 때만 `tuist generate --no-open`을 다시 돌린다. 새 소스 파일은 glob으로 잡히므로 재생성이 필요 없다.

---

### Task 1: 남은 시간 추정기

**Files:**
- Create: `Modules/JustCore/Sources/AnalysisPace.swift`
- Test: `Tests/CoreTests.swift` (파일 끝에 추가)

**Interfaces:**
- Consumes: 없음
- Produces: `AnalysisPace.init(window: Int = 8)`, `mutating func record(_ seconds: TimeInterval)`, `func estimate(remaining: Int) -> TimeInterval?`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`Tests/CoreTests.swift` 파일 끝에 추가:

```swift
@Suite("해석 남은 시간 추정")
struct AnalysisPaceTests {
    @Test("재본 적이 없으면 추정하지 않는다")
    func noSamplesMeansNoEstimate() {
        #expect(AnalysisPace().estimate(remaining: 10) == nil)
    }

    @Test("한 줄만 재도 추정한다")
    func estimatesFromASingleSample() {
        var pace = AnalysisPace()
        pace.record(10)
        #expect(pace.estimate(remaining: 5) == 50)
    }

    @Test("남은 줄이 없으면 0이다")
    func nothingLeftMeansZero() {
        var pace = AnalysisPace()
        pace.record(10)
        #expect(pace.estimate(remaining: 0) == 0)
    }

    @Test("한 줄이 유난히 오래 걸려도 추정을 지배하지 않는다")
    func oneStallDoesNotDominate() {
        var pace = AnalysisPace()
        for seconds in [10.0, 10.0, 10.0, 600.0] { pace.record(seconds) }
        // 평균이라면 157.5초가 된다.
        #expect(pace.estimate(remaining: 1) == 10)
    }

    @Test("창 밖으로 밀린 표본은 버린다")
    func forgetsSamplesOutsideTheWindow() {
        var pace = AnalysisPace(window: 2)
        for seconds in [100.0, 100.0, 10.0, 10.0] { pace.record(seconds) }
        #expect(pace.estimate(remaining: 1) == 10)
    }

    @Test("말이 안 되는 표본은 세지 않는다")
    func ignoresNonsenseSamples() {
        var pace = AnalysisPace()
        pace.record(-5)
        pace.record(.infinity)
        pace.record(.nan)
        #expect(pace.estimate(remaining: 3) == nil)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild -workspace Just.xcworkspace -scheme Just -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|✘|Test run with"`

Expected: `cannot find 'AnalysisPace' in scope` 컴파일 실패.

- [ ] **Step 3: 최소 구현을 쓴다**

Create `Modules/JustCore/Sources/AnalysisPace.swift`:

```swift
import Foundation

/// Estimates how long an analysis run has left, from how long its lines have
/// actually taken.
///
/// A median over a short window rather than a mean: one line that stalls —
/// thermal throttling, a long verse, the model warming up — should not triple
/// the number the user is staring at for the next ten minutes.
public struct AnalysisPace: Sendable {
    private var samples: [TimeInterval] = []
    private let window: Int

    public init(window: Int = 8) {
        self.window = max(1, window)
    }

    /// Records one line's elapsed time.
    ///
    /// Non-positive and non-finite samples are dropped: a clock that did not
    /// move, or moved to infinity, says nothing about pace.
    public mutating func record(_ seconds: TimeInterval) {
        guard seconds.isFinite, seconds > 0 else { return }
        samples.append(seconds)
        if samples.count > window {
            samples.removeFirst(samples.count - window)
        }
    }

    /// Seconds left for `remaining` lines, or nil when nothing has been timed
    /// yet — showing no estimate is better than showing an invented one.
    public func estimate(remaining: Int) -> TimeInterval? {
        guard !samples.isEmpty else { return nil }
        guard remaining > 0 else { return 0 }
        return median * Double(remaining)
    }

    private var median: TimeInterval {
        let sorted = samples.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

Run: `xcodebuild -workspace Just.xcworkspace -scheme Just -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|✘|Test run with|\*\* TEST"`

Expected: `Test run with 81 tests in 16 suites passed` (75 + 6).

- [ ] **Step 5: 커밋**

```bash
git add Modules/JustCore/Sources/AnalysisPace.swift Tests/CoreTests.swift
git commit -F - <<'EOF'
feat(core): 해석 남은 시간 추정기

줄당 실제 소요를 짧은 창에 모아 중앙값으로 남은 시간을 낸다. 평균을 쓰면
한 줄이 스로틀링으로 멈칫한 것이 열 배로 부풀어 사용자가 보는 숫자를
지배한다.

표본이 없으면 추정하지 않는다. 지어낸 숫자를 보여주느니 아무것도 안
보여주는 편이 낫다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

---

### Task 2: "한 바퀴만 돈다"를 테스트로 못박기

준비 단계는 남은 줄이 없어질 때까지 도는 것이 아니라 정확히 한 바퀴만 돈다. 계속 실패하는 줄 하나가 입장을 영원히 막지 않게 하려는 것이다. `Sensei.analyzeAll`은 이미 진입 시점의 `pendingLines`를 한 번 계산해 그것만 돌므로 production 변경은 없다. 이 성질이 나중에 조용히 깨지지 않도록 테스트로 고정한다.

**Files:**
- Test: `Tests/SenseiTests.swift` (파일 끝에 추가)

**Interfaces:**
- Consumes: `Sensei.init(dictionary:modelIsAvailable:)`, `Sensei.reset(for:)`, `Sensei.analyzeAll(lyrics:songTitle:artist:onProgress:)`, `Sensei.pendingLines(in:)`
- Produces: 없음

- [ ] **Step 1: 테스트를 쓴다**

`Tests/SenseiTests.swift` 파일 끝에 추가:

```swift
@Suite("전곡 해석은 한 바퀴만")
@MainActor
struct AnalyzeAllSinglePassTests {
    private let lyrics = Lyrics(
        lines: [
            LyricLine(id: 0, time: 0, text: "夢を見た"),
            LyricLine(id: 1, time: 4, text: "夜が明ける"),
        ],
        isSynced: true,
        source: "test"
    )

    @Test("사전으로 대체된 줄이 남아도 한 바퀴 뒤에 끝난다")
    func stopsAfterOnePass() async {
        // A device that has the model but cannot reach it: every line falls
        // back to the dictionary and stays unsettled. Preparation must still
        // finish — retrying until nothing is pending would never return.
        let sensei = Sensei(dictionary: DictionarySensei(), modelIsAvailable: true)
        sensei.reset(for: "songA")

        var reported: [Int] = []
        await sensei.analyzeAll(lyrics: lyrics, songTitle: "곡", artist: "가수") { done, _ in
            reported.append(done)
        }

        #expect(reported == [1, 2])
        // Still pending, so opening the song again tries them once more.
        #expect(sensei.pendingLines(in: lyrics).count == 2)
    }
}
```

> Swift 6 엄격 동시성이 `reported`의 가변 캡처를 문제 삼으면, 테스트 함수 안에 `final class Recorder { var dones: [Int] = [] }`를 선언하고 그 인스턴스에 담는다. 둘 다 `@MainActor`라 데이터 경쟁은 없다.

- [ ] **Step 2: 통과를 확인한다**

이 테스트는 처음부터 통과해야 한다. 실패한다면 `analyzeAll`이 이미 한 바퀴를 넘어 돌고 있다는 뜻이므로, 계획을 멈추고 그 사실을 보고한다.

Run: `xcodebuild -workspace Just.xcworkspace -scheme Just -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|✘|Test run with|\*\* TEST"`

Expected: `Test run with 82 tests in 17 suites passed`.

- [ ] **Step 3: 커밋**

```bash
git add Tests/SenseiTests.swift
git commit -F - <<'EOF'
test(sensei): 전곡 해석이 한 바퀴만 돈다는 것을 고정

곧 준비 화면이 이 호출이 끝나기를 기다리게 된다. 남은 줄이 없어질 때까지
도는 구조였다면 계속 실패하는 줄 하나가 입장을 영원히 막는다.

analyzeAll은 진입 시점의 pendingLines만 돈다. 그 성질이 조용히 깨지지
않도록 못박아 둔다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

---

### Task 3: 세션에 준비 단계를 들인다

**Files:**
- Modify: `App/Sources/Player/SongSession.swift`
- Modify: `App/Sources/Player/PlayerScreen.swift` (호출부 이름만 — 화면 분기는 Task 4)
- Modify: `App/Sources/Player/LyricsPane.swift` (「다시 찾기」 호출부)

**Interfaces:**
- Consumes: `AnalysisPace` (Task 1)
- Produces: `SongSession.Phase`, `SongSession.phase`, `func prepare() async`, `func retryLyrics(artistOverride:titleOverride:) async`

- [ ] **Step 1: `Phase`와 저장 프로퍼티를 넣는다**

`App/Sources/Player/SongSession.swift`에서 `enum LyricsState` 선언 바로 아래에 추가:

```swift
    /// How far the song is from being ready to read.
    ///
    /// The player shows a finished song or nothing at all, so this is what
    /// stands between choosing a song and hearing it.
    enum Phase: Equatable {
        case loadingLyrics
        case analyzing(done: Int, total: Int, remaining: TimeInterval?)
        case ready
    }
```

같은 파일의 `private(set) var bulkProgress: (done: Int, total: Int)?` 아래에 추가:

```swift
    private(set) var phase: Phase = .loadingLyrics
```

- [ ] **Step 2: `start()`를 `prepare()`로 바꾸고 해석을 기다리게 한다**

`App/Sources/Player/SongSession.swift`의 `func start() async { ... }` 전체를 아래로 교체한다. (`sensei.reset(for:)`, `upsertSong`, `preload`, 가사 로딩은 그대로 두고, 끝에서 해석을 **기다린다**는 것이 달라진 점이다.)

```swift
    /// Everything that has to happen before the player may open.
    ///
    /// Analysis is awaited rather than left running behind the lyrics: the
    /// player shows a finished song, and a song filling in line by line under
    /// the reader was the thing this replaces.
    func prepare() async {
        // Claiming the shared cache is the session's own job, not the caller's.
        // Doing it here is what orders it correctly against the outgoing
        // session's final flush: that one runs first, under its own song's
        // scope, so its work is saved before this song takes the cache over.
        // Re-opening the same song is a no-op and keeps everything cached.
        sensei.reset(for: track.id)

        // The song enters the library as soon as it is opened, so "recently
        // played" works without an explicit save step.
        let record = store.upsertSong(track)
        song = record

        // Everything generated for this song before is loaded back before any
        // work is scheduled, so a reopened song costs nothing.
        sensei.preload(record.analyses)

        if let cached = record.lyrics, !cached.isEmpty {
            lyricsState = .ready(cached)
        } else {
            await fetchLyrics()
        }

        // "안 함" and low-power mode keep their meaning: a setting made to save
        // energy must not turn into a ten-minute wait. Those songs open at once
        // and analyse per tapped line, as before.
        if autoAnalysis {
            await analyzeRemaining()
        }

        guard !Task.isCancelled else { return }
        phase = .ready
    }

    /// One pass over the lines that still need the model.
    ///
    /// Exactly one. A line the model keeps failing on stays unsettled forever,
    /// so looping until nothing is pending would never let the song open.
    private func analyzeRemaining() async {
        guard let lyrics else { return }
        let pending = sensei.pendingLines(in: lyrics)
        guard !pending.isEmpty else { return }

        var pace = AnalysisPace()
        var lastTick = Date.now
        phase = .analyzing(done: 0, total: pending.count, remaining: nil)

        await sensei.analyzeAll(
            lyrics: lyrics,
            songTitle: track.title,
            artist: track.artist
        ) { done, total in
            let now = Date.now
            pace.record(now.timeIntervalSince(lastTick))
            lastTick = now
            self.phase = .analyzing(
                done: done,
                total: total,
                remaining: pace.estimate(remaining: total - done)
            )
            // Flushed as it goes, so a cancelled run keeps what it produced.
            self.flush()
        }
        flush()
    }

    /// Re-runs the search with the user's corrected artist and title, then
    /// prepares the song properly.
    ///
    /// Going back through preparation rather than analysing behind the lyrics
    /// keeps one rule: the player only ever shows a finished song.
    func retryLyrics(artistOverride: String?, titleOverride: String?) async {
        phase = .loadingLyrics
        await fetchLyrics(artistOverride: artistOverride, titleOverride: titleOverride)
        if autoAnalysis {
            await analyzeRemaining()
        }
        guard !Task.isCancelled else { return }
        phase = .ready
    }
```

`import JustCore`는 이미 파일 첫 줄에 있으므로 `AnalysisPace`를 쓰기 위한 추가 import는 필요 없다.

- [ ] **Step 3: 호출부 두 곳의 이름을 맞춘다**

`App/Sources/Player/PlayerScreen.swift`의 `.task(id: track.id)` 안에서:

```swift
            await session.start()
```
를
```swift
            await session.prepare()
```
로 바꾼다.

`App/Sources/Player/LyricsPane.swift`의 `MissingLyricsView` 안 「다시 찾기」 버튼에서:

```swift
                Task {
                    await session.fetchLyrics(
                        artistOverride: artist.isEmpty ? nil : artist,
                        titleOverride: title.isEmpty ? nil : title
                    )
                    isRetrying = false
                }
```
를
```swift
                Task {
                    await session.retryLyrics(
                        artistOverride: artist.isEmpty ? nil : artist,
                        titleOverride: title.isEmpty ? nil : title
                    )
                    isRetrying = false
                }
```
로 바꾼다.

- [ ] **Step 4: 빌드와 테스트가 통과하는지 본다**

Run: `xcodebuild -workspace Just.xcworkspace -scheme Just -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|✘|Test run with|\*\* TEST"`

Expected: `Test run with 82 tests in 17 suites passed`. 이 단계에서 화면은 아직 안 바뀐다 — 준비가 끝날 때까지 예전 골격 화면이 보인다.

- [ ] **Step 5: 커밋**

```bash
git add App/Sources/Player/SongSession.swift App/Sources/Player/PlayerScreen.swift App/Sources/Player/LyricsPane.swift
git commit -F - <<'EOF'
refactor(player): 세션에 준비 단계를 들인다

start()를 prepare()로 바꾸고, 해석을 뒤에 흘려보내는 대신 기다린다.
가사가 채워지는 동안 읽게 되던 것을 없애기 위한 준비다.

해석은 정확히 한 바퀴만 돈다. 모델이 계속 실패하는 줄은 미완료로 남으므로,
남은 줄이 없어질 때까지 돌면 곡이 영영 열리지 않는다.

자동 해석 "안 함"과 저전력 모드는 준비를 건너뛴다. 에너지를 아끼려고 둔
설정이 10분 대기로 바뀌어서는 안 된다.

가사 「다시 찾기」가 성공하면 준비 단계로 되돌아간다. 플레이어에는 완성된
곡만 보인다는 규칙을 한 갈래로 유지한다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

---

### Task 4: 준비 화면과 재생 시점

**Files:**
- Create: `App/Sources/Player/PreparingView.swift`
- Modify: `App/Sources/Player/PlayerScreen.swift`
- Modify: `App/Sources/AppModel.swift`

**Interfaces:**
- Consumes: `SongSession.Phase` (Task 3)
- Produces: `AppModel.confirmPlaying(_:)`

- [ ] **Step 1: 준비 화면을 만든다**

Create `App/Sources/Player/PreparingView.swift`:

```swift
import JustCore
import JustDesign
import SwiftUI

/// What the user looks at between choosing a song and hearing it.
///
/// The wait is long — minutes, on a song the model has not seen — so this is
/// not a spinner. It says which song, how far along, and how much is left, and
/// it offers a way out that does not throw the finished lines away.
struct PreparingView: View {
    let track: Track
    let artwork: UIImage?
    let phase: SongSession.Phase
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: JustTheme.Space.loose) {
            Spacer(minLength: 0)

            ArtworkView(image: artwork, cornerRadius: JustTheme.Radius.card, seed: track.id)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 220)
                .shadow(color: .black.opacity(0.4), radius: 24, y: 10)

            VStack(spacing: 4) {
                Text(track.title)
                    .font(JustTheme.Font.title)
                    .foregroundStyle(JustTheme.Ink.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(track.artist)
                    .font(JustTheme.Font.body)
                    .foregroundStyle(JustTheme.Ink.secondary)
                    .lineLimit(1)
            }

            progress

            Spacer(minLength: 0)

            Button("중단", action: onCancel)
                .buttonStyle(.justSecondary)
        }
        .padding(JustTheme.Space.section)
        .frame(maxWidth: 420)
    }

    @ViewBuilder
    private var progress: some View {
        switch phase {
        case .loadingLyrics:
            VStack(spacing: JustTheme.Space.tight) {
                ProgressView()
                Text("가사를 찾는 중")
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(JustTheme.Ink.tertiary)
            }

        case .analyzing(let done, let total, let remaining):
            VStack(spacing: JustTheme.Space.tight) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .tint(JustTheme.Ink.primary)
                HStack {
                    Text("해석 중")
                    Spacer()
                    Text("\(done)/\(total)")
                        .monospacedDigit()
                }
                .font(JustTheme.Font.caption)
                .foregroundStyle(JustTheme.Ink.secondary)

                if let remaining {
                    Text(Self.remainingText(remaining))
                        .font(JustTheme.Font.caption)
                        .foregroundStyle(JustTheme.Ink.tertiary)
                }
            }

        case .ready:
            EmptyView()
        }
    }

    /// Minutes once there is more than one, because a countdown of seconds
    /// across ten minutes is worse company than a round number.
    static func remainingText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "약 \(max(total, 1))초 남음" }
        return "약 \(Int((Double(total) / 60).rounded()))분 남음"
    }
}
```

- [ ] **Step 2: `nowPlaying` 확정을 준비 완료 뒤로 옮긴다**

`App/Sources/AppModel.swift`의 `open(_:)`를 아래로 교체한다:

```swift
    func open(_ track: Track) {
        openTrack = track
    }

    /// Called once preparation has finished and playback is about to start.
    ///
    /// Separate from `open` so that backing out of a song that was still being
    /// analysed leaves nothing behind — no mini player for a song that never
    /// made a sound, and whatever was already playing keeps playing.
    func confirmPlaying(_ track: Track) {
        nowPlaying = track
    }
```

- [ ] **Step 3: 플레이어를 준비/완료로 가른다**

`App/Sources/Player/PlayerScreen.swift`의 `body` 안 `if let session {` 줄을 아래로 바꾼다:

```swift
            if let session, session.phase == .ready {
```

같은 `body`의 `} else {` 이후 골격(Skeleton) 블록 전체를 아래로 교체한다:

```swift
            } else if let session {
                PreparingView(
                    track: track,
                    artwork: artwork.image,
                    phase: session.phase,
                    onCancel: { app.closePlayer() }
                )
            } else {
                PreparingView(
                    track: track,
                    artwork: artwork.image,
                    phase: .loadingLyrics,
                    onCancel: { app.closePlayer() }
                )
            }
```

그리고 `.task(id: track.id)` 안, `await session.prepare()` 뒤에 있던 재생 호출을 준비 완료 뒤로 옮긴다. `.task(id:)` 블록 전체를 아래로 교체한다:

```swift
        // Keyed on the track: `fullScreenCover(item:)` swaps the item in place
        // rather than dismissing and re-presenting, so picking another song
        // from the album sheet used to leave this screen showing a new title
        // over the old song's session — and never loading the new song at all.
        .task(id: track.id) {
            // The outgoing session flushes here, while the cache is still its
            // own, so its analyses are saved before the new song claims it.
            session?.cancelBulk()

            let session = SongSession(
                track: track,
                context: context,
                sensei: app.sensei,
                autoAnalysis: app.autoAnalysis.allowsAutoRun
            )
            self.session = session
            await session.prepare()

            // Backing out during preparation must leave no trace: the song is
            // not adopted as "now playing" until it is about to be heard.
            guard !Task.isCancelled, session.phase == .ready else { return }
            app.confirmPlaying(track)

            // Only autoplays when this is a different song. Reopening a paused
            // one from the mini player should not start it again.
            await app.player.load(track, autoplay: app.player.trackID != track.id)
        }
```

- [ ] **Step 4: 빌드와 테스트**

Run: `xcodebuild -workspace Just.xcworkspace -scheme Just -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|✘|Test run with|\*\* TEST"`

Expected: `Test run with 82 tests in 17 suites passed`.

- [ ] **Step 5: 커밋**

```bash
git add App/Sources/Player/PreparingView.swift App/Sources/Player/PlayerScreen.swift App/Sources/AppModel.swift
git commit -F - <<'EOF'
feat(player): 해석이 끝난 뒤에 재생과 가사 화면으로 넘어간다

곡을 고르면 아트워크와 진행률, 남은 시간을 보여주는 준비 화면이 먼저 뜨고,
전곡 해석이 끝난 다음에 재생이 시작된다. 번역이 읽는 도중에 하나씩 나타나던
것을 없앤다.

nowPlaying 확정을 준비 완료 뒤로 옮겼다. 중단하고 나갔을 때 한 번도 울린 적
없는 곡의 미니플레이어가 남지 않고, 듣던 곡이 있었다면 준비하는 동안 그대로
재생된다 — 10분이 완전한 정적이 되지는 않는다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

---

### Task 5: 시뮬레이터에서 흐름을 확인한다

앱 타깃은 단위 테스트로 덮이지 않으므로 여기서 직접 본다. 각 항목은 스크린샷으로 확인한다.

**Files:** 없음 (검증만)

- [ ] **Step 1: 깨끗한 상태로 설치**

```bash
xcodebuild -workspace Just.xcworkspace -scheme Just -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/just-dd build
xcrun simctl uninstall booted com.coby.just
xcrun simctl install booted /tmp/just-dd/Build/Products/Debug-iphonesimulator/Just.app
xcrun simctl privacy booted grant media-library com.coby.just
xcrun simctl launch booted com.coby.just
```

- [ ] **Step 2: 새 곡 — 준비 화면이 뜨는가**

둘러보기 → YOASOBI 검색 → `夜に駆ける` 선택. 확인할 것:
- 아트워크·제목·아티스트가 보인다
- "가사를 찾는 중" 다음에 "해석 중 n/56"으로 바뀐다
- 진행률과 "약 n분 남음"이 움직인다
- 음악은 아직 시작되지 않는다

- [ ] **Step 3: 중단 — 흔적이 남지 않는가**

「중단」을 누른다. 확인할 것:
- 검색 화면으로 돌아간다
- **미니플레이어가 생기지 않는다**

- [ ] **Step 4: 이어서 하는가**

같은 곡을 다시 연다. 확인할 것: 진행률이 0이 아니라 중단한 지점 근처에서 시작한다.

- [ ] **Step 5: 완료 — 완성된 화면인가**

끝까지 기다린다. 확인할 것:
- 재생이 시작된다
- 가사 화면이 처음부터 번역이 붙은 상태로 보인다
- 하단에 해석 진행바가 없다

- [ ] **Step 6: 재입장은 즉시인가**

플레이어를 닫고 미니플레이어를 탭한다. 확인할 것: 준비 화면 없이 즉시 가사 화면.

- [ ] **Step 7: 듣던 곡이 계속 재생되는가**

재생 중에 둘러보기로 가서 다른 곡을 연다. 확인할 것: 준비 화면이 뜨는 동안 앞 곡이 계속 들린다.

- [ ] **Step 8: 확인한 것과 못 한 것을 보고한다**

스크린샷과 함께 결과를 정리한다. 실기기가 아니므로 실제 소요 시간은 시뮬레이터 값이라는 점을 명시한다.

---

## Self-Review

**스펙 대조**

| 스펙 요구 | 담당 |
|---|---|
| 준비 단계는 `PlayerScreen` 안의 한 상태 | Task 4 Step 3 |
| 재생·`nowPlaying`을 준비 완료 뒤로 | Task 4 Step 2·3 |
| 준비는 정확히 한 바퀴 | Task 3 Step 2 (`analyzeRemaining`), Task 2 (고정) |
| 진행률 + 남은 시간 추정 | Task 1, Task 4 Step 1 |
| 중단 → 검색 화면으로, 진행분 보존 | Task 4 Step 3, Task 5 Step 3·4 |
| 이미 해석한 곡은 즉시 입장 | Task 3 Step 2 (`pending.isEmpty` 조기 반환), Task 5 Step 6 |
| 가사 없음 → 플레이어의 「다시 찾기」 | Task 3 Step 2 (`lyrics == nil` 조기 반환) |
| 「다시 찾기」 성공 → 준비 단계로 | Task 3 Step 2 (`retryLyrics`), Step 3 |
| Apple Intelligence 없으면 즉시 | 사전 경로는 모델 호출이 없어 자동 충족 |

**스펙에 없던 것을 하나 더했다:** 자동 해석 설정 "안 함"과 저전력 모드는 준비를 건너뛴다 (Task 3 Step 2). 해석이 입장을 막게 된 이상, 에너지를 아끼려는 설정이 10분 대기가 되어서는 안 된다.

**타입 일관성:** `Phase`는 Task 3에서 정의하고 Task 4에서만 쓴다. `AnalysisPace.estimate(remaining:)`는 Task 1의 시그니처 그대로 Task 3에서 호출한다. `confirmPlaying(_:)`는 Task 4에서 정의하고 같은 Task에서 호출한다.

**남은 위험:** `analyzeRemaining`의 진행 콜백이 `var pace`와 `var lastTick`을 가변 캡처한다. 둘 다 `@MainActor`이고 콜백은 escaping이 아니므로 합법이지만, Swift 6 엄격 동시성이 걸고 넘어지면 두 값을 세션의 프로퍼티로 올린다.
