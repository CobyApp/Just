# 버튼과 빈 화면의 공통 규칙 — 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 무엇이 눌리는지 한눈에 보이게 하고, 비어 있는 화면이 다음 행동을 주게 한다.

**Architecture:** JustDesign에 아이콘 버튼 스타일과 빈 화면 공통 형태를 세우고, 앱의 해당 지점들이 그것을 물려받는다. 빈 화면에서 다른 탭으로 보내려면 탭 선택이 `RootView`의 `@State`를 떠나 `AppModel`에 있어야 한다.

**Tech Stack:** Swift 6, SwiftUI, Tuist

**Spec:** `docs/superpowers/specs/2026-08-19-buttons-and-empty-states-design.md`

## Global Constraints

- 커밋 메시지는 한국어 conventional commits. 본문은 `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`로 끝낸다.
- 소스 주석은 영어. 사용자에게 보이는 문자열은 한국어.
- **파일을 새로 만들었으면 `tuist generate --no-open`을 다시 돌린다.** 생성된 Xcode 프로젝트가 파일 목록을 고정하므로, 재생성 없이는 새 파일이 빌드에 들어가지 않는다.
- 빌드·테스트:
  `xcodebuild -workspace Just.xcworkspace -scheme Just -destination 'platform=iOS Simulator,name=iPhone 17' test`
- 기존 82개 테스트가 계속 통과해야 한다. 이 계획은 새 테스트를 추가하지 않는다 — 레이아웃 속성이라 스냅샷 기반 없이는 코드로 확인할 수 없다. 대신 Task 5에서 화면마다 스크린샷으로 확인한다.
- **최소 탭 영역은 44×44pt.** 이 계획에서 손대는 모든 아이콘 버튼에 적용된다.

---

### Task 1: 아이콘 버튼 스타일

**Files:**
- Modify: `Modules/JustDesign/Sources/JustTheme.swift` (`JustSecondaryButtonStyle` 확장 뒤에 추가)

**Interfaces:**
- Consumes: `JustTheme.Surface.raised`, `JustTheme.Ink.hairline`, `JustTheme.Ink.primary`
- Produces: `ButtonStyle.justIcon`, `JustIconButtonStyle.minimumTapTarget` (CGFloat, 44)

- [ ] **Step 1: 스타일을 추가한다**

`Modules/JustDesign/Sources/JustTheme.swift`에서 `static var justSecondary: JustSecondaryButtonStyle { JustSecondaryButtonStyle() }`가 든 extension의 닫는 괄호 바로 뒤에 추가:

```swift
/// The icon-only control: a transport button, a dismiss, a toggle.
///
/// These were bare images with `.plain`, which asks SwiftUI to draw nothing at
/// all — so the most common button style in the app was the one that declared
/// itself invisible. They were also 30–34pt, under the 44pt minimum, which is
/// what made them feel small as well as look absent.
public struct JustIconButtonStyle: ButtonStyle {
    /// Apple's minimum comfortable target. Not a design preference.
    public static let minimumTapTarget: CGFloat = 44

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(JustTheme.Ink.primary)
            .frame(
                minWidth: Self.minimumTapTarget,
                minHeight: Self.minimumTapTarget
            )
            .background(
                JustTheme.Surface.raised.opacity(configuration.isPressed ? 0.4 : 1),
                in: .circle
            )
            .overlay {
                Circle().strokeBorder(JustTheme.Ink.hairline, lineWidth: 0.5)
            }
            .contentShape(.circle)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == JustIconButtonStyle {
    static var justIcon: JustIconButtonStyle { JustIconButtonStyle() }
}
```

- [ ] **Step 2: 빌드와 테스트**

Run: `xcodebuild -workspace Just.xcworkspace -scheme Just -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|✘|Test run with|\*\* TEST"`

Expected: `Test run with 82 tests in 17 suites passed`. 아직 쓰는 곳이 없으므로 화면은 그대로다.

- [ ] **Step 3: 커밋**

```bash
git add Modules/JustDesign/Sources/JustTheme.swift
git commit -F - <<'EOF'
feat(design): 아이콘 버튼 스타일

아이콘만 있는 컨트롤에 배경과 테두리를 주고 탭 영역을 44pt로 보장한다.

지금까지 이 자리들은 .plain에 맨 이미지였다. .plain은 SwiftUI에게 아무것도
그리지 말라는 뜻이라, 앱에서 가장 흔한 버튼 스타일이 스스로 보이지 않기로
선언한 것이었다. 크기도 30~34pt로 최소 44pt 아래여서, 안 보이는 데다 작았다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

---

### Task 2: 아이콘 버튼 적용과 크기 교정

**Files:**
- Modify: `App/Sources/Player/MiniPlayer.swift:38-59`
- Modify: `App/Sources/Player/PlayerScreen.swift` (후리가나 토글, `CompactTransport` 재생 버튼)
- Modify: `App/Sources/Player/LineStudySheet.swift` (담기 버튼)

**Interfaces:**
- Consumes: `ButtonStyle.justIcon`, `JustIconButtonStyle.minimumTapTarget` (Task 1)
- Produces: 없음

- [ ] **Step 1: 미니플레이어의 두 버튼**

`App/Sources/Player/MiniPlayer.swift`에서 아래 블록을

```swift
                Button {
                    app.player.togglePlayback()
                } label: {
                    Image(systemName: app.player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(JustTheme.Ink.primary)
                        .frame(width: 32, height: 32)
                }
                // A plain style keeps this from inheriting the row's tap, which
                // would expand the player instead of toggling playback.
                .buttonStyle(.plain)

                Button {
                    app.stopPlayback()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(JustTheme.Ink.secondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("재생 종료")
```

로 바꾼다:

```swift
                Button {
                    app.player.togglePlayback()
                } label: {
                    Image(systemName: app.player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                }
                // A styled icon button also keeps this from inheriting the row's
                // tap, which would expand the player instead of toggling
                // playback.
                .buttonStyle(.justIcon)
                .accessibilityLabel(app.player.isPlaying ? "일시정지" : "재생")

                Button {
                    app.stopPlayback()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(.justIcon)
                .accessibilityLabel("재생 종료")
```

- [ ] **Step 2: 전체화면 전송부의 재생 버튼**

`App/Sources/Player/PlayerScreen.swift`의 `CompactTransport` 안에서

```swift
            Button { player.togglePlayback() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(JustTheme.Ink.primary)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
```

를

```swift
            Button { player.togglePlayback() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
            }
            .buttonStyle(.justIcon)
            .accessibilityLabel(player.isPlaying ? "일시정지" : "재생")
```

로 바꾼다.

- [ ] **Step 3: 후리가나 토글 — 스타일은 두고 크기만**

`App/Sources/Player/PlayerScreen.swift`의 후리가나 버튼에서

```swift
                    .frame(width: 34, height: 34)
```

를

```swift
                    // The fill already says on/off; only the target was small.
                    .frame(
                        width: JustIconButtonStyle.minimumTapTarget,
                        height: JustIconButtonStyle.minimumTapTarget
                    )
```

로 바꾼다. `.buttonStyle(.plain)`과 배경·테두리는 **그대로 둔다** — 켜짐을 배경 채움으로 말하는 처리를 일반 스타일로 갈아치우면 그 정보를 잃는다.

- [ ] **Step 4: 단어 담기 버튼 — 스타일은 두고 크기만**

`App/Sources/Player/LineStudySheet.swift`의 담기 버튼에서

```swift
                        .frame(width: 30, height: 30)
```

를

```swift
                        // Green fill already says saved; only the target was small.
                        .frame(
                            width: JustIconButtonStyle.minimumTapTarget,
                            height: JustIconButtonStyle.minimumTapTarget
                        )
```

로 바꾼다. 초록 채움과 테두리는 그대로 둔다.

`LineStudySheet.swift`가 `JustDesign`을 import하는지 확인한다. 파일 첫 줄들에 `import JustDesign`이 없으면 추가한다.

- [ ] **Step 5: 빌드와 테스트**

Run: `xcodebuild -workspace Just.xcworkspace -scheme Just -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|✘|Test run with|\*\* TEST"`

Expected: `Test run with 82 tests in 17 suites passed`.

- [ ] **Step 6: 커밋**

```bash
git add App/Sources/Player/MiniPlayer.swift App/Sources/Player/PlayerScreen.swift App/Sources/Player/LineStudySheet.swift
git commit -F - <<'EOF'
fix(player): 안 보이던 아이콘 버튼에 배경을 주고 44pt로 키운다

미니플레이어 재생·종료와 전체화면 재생은 배경이 아예 없었다. 새 아이콘 버튼
스타일을 입힌다.

후리가나 토글과 단어 담기 버튼은 스타일을 바꾸지 않고 크기만 올린다. 전자는
켜짐을, 후자는 저장됨을 배경 채움으로 말하고 있어서, 일반 스타일로 갈아치우면
그 정보가 사라진다. 문제는 34pt와 30pt라는 크기뿐이었다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

---

### Task 3: 탭 선택을 AppModel로

빈 화면의 「곡 보러 가기」가 다른 탭으로 보내려면 선택이 화면에서 닿는 곳에 있어야 한다.

**Files:**
- Modify: `App/Sources/AppModel.swift`
- Modify: `App/Sources/RootView.swift`

**Interfaces:**
- Consumes: 없음
- Produces: `AppModel.Tab` (`.today`, `.browse`, `.words`, `.practice`), `AppModel.tab`

- [ ] **Step 1: `AppModel`에 탭을 들인다**

`App/Sources/AppModel.swift`의 `var openTrack: Track?` 선언 바로 위에 추가:

```swift
    /// Which tab is showing.
    ///
    /// Held here rather than in `RootView`'s own state so a screen can send the
    /// user somewhere else — an empty word list has nothing to offer except the
    /// song list, and it could not reach it from inside its own tab.
    var tab: Tab = .today

    enum Tab: Hashable {
        case today, browse, words, practice
    }
```

- [ ] **Step 2: `RootView`가 그것을 쓰게 한다**

`App/Sources/RootView.swift`에서 `@State private var selection: Destination = .today`와 `enum Destination { case today, browse, words, practice }` 선언을 **삭제**하고, `TabView(selection: $selection)`을 `TabView(selection: $app.tab)`으로 바꾼다. 각 `Tab`의 `value:`도 `Destination.today` → `AppModel.Tab.today` 식으로 바꾼다.

`body`는 이미 첫 줄에 `@Bindable var app = app`을 두고 있으므로 `$app.tab`이 바로 쓰인다.

`MiniPlayerAccessory` 아래의 주석 중 "Tab selection lives in `RootView`'s own state rather than inside the `TabView`, so rebuilding the subtree when a song starts does not move the user to another tab."는 사실이 아니게 되므로 아래로 바꾼다:

```swift
/// ... Tab selection lives in `AppModel` rather than inside the `TabView`, so
/// rebuilding the subtree when a song starts does not move the user to another
/// tab — and a screen can send them to one deliberately.
```

- [ ] **Step 3: 빌드와 테스트**

Run: `xcodebuild -workspace Just.xcworkspace -scheme Just -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|✘|Test run with|\*\* TEST"`

Expected: `Test run with 82 tests in 17 suites passed`. 탭 동작은 눈에 보이는 변화가 없어야 한다.

- [ ] **Step 4: 커밋**

```bash
git add App/Sources/AppModel.swift App/Sources/RootView.swift
git commit -F - <<'EOF'
refactor: 탭 선택을 AppModel로 올린다

RootView의 @State에 갇혀 있어서 화면이 다른 탭으로 보낼 수 없었다. 단어가
하나도 없는 단어장이 사용자에게 내놓을 것은 곡 목록뿐인데, 자기 탭 안에서는
거기에 닿을 방법이 없었다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

---

### Task 4: 빈 화면 공통 형태와 다음 행동

**Files:**
- Create: `Modules/JustDesign/Sources/JustEmptyState.swift`
- Modify: `App/Sources/Library/LibraryScreen.swift:71-76`
- Modify: `App/Sources/Practice/PracticeScreen.swift:34-39`
- Modify: `App/Sources/Player/AlbumSheet.swift:30-36`
- Modify: `App/Sources/Search/SearchScreen.swift`, `App/Sources/Search/DiscoveryView.swift`, `App/Sources/Player/SongWordsSheet.swift`, `App/Sources/Practice/QuizScreen.swift`, `App/Sources/Review/ReviewScreen.swift`, `App/Sources/Settings/AppleMusicGate.swift`

**Interfaces:**
- Consumes: `AppModel.tab`, `AppModel.Tab` (Task 3)
- Produces: `JustEmptyState(icon:title:message:actionTitle:action:)` — `actionTitle`과 `action`은 기본값 nil

- [ ] **Step 1: 공통 형태를 만든다**

Create `Modules/JustDesign/Sources/JustEmptyState.swift`:

```swift
import SwiftUI

/// A screen with nothing in it yet, and what to do about that.
///
/// Wraps `ContentUnavailableView` rather than replacing it: the system view
/// already handles layout, Dynamic Type and accessibility, and redrawing it by
/// hand would give all of that up. What this adds is one place to decide the
/// button's style — and a named `actionTitle`, so that offering a way forward is
/// a visible decision at every call site rather than something easy to forget.
///
/// Seven of the app's ten empty screens had no action at all. Three of those
/// were dead ends the user could only leave by finding the tab bar themselves.
public struct JustEmptyState: View {
    private let icon: String
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    /// - Parameters:
    ///   - actionTitle: nil when there is genuinely nothing to offer — a search
    ///     with no results wants a different query, not a button, and "nothing
    ///     left to review" is a finish line rather than a failure.
    public init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.justPrimary)
            }
        }
    }
}
```

- [ ] **Step 2: 단어장 빈 화면에 다음 행동을 준다**

`App/Sources/Library/LibraryScreen.swift`에서

```swift
        if words.isEmpty {
            ContentUnavailableView {
                Label("아직 저장한 단어가 없습니다", systemImage: "character.book.closed")
            } description: {
                Text("가사에서 줄을 눌러 단어를 담으면 여기에 모입니다.")
            }
        } else {
```

를

```swift
        if words.isEmpty {
            JustEmptyState(
                icon: "character.book.closed",
                title: "아직 저장한 단어가 없습니다",
                message: "가사에서 줄을 눌러 단어를 담으면 여기에 모입니다.",
                actionTitle: "곡 보러 가기",
                action: { app.tab = .browse }
            )
        } else {
```

로 바꾼다. 이 파일은 이미 `app`을 환경에서 읽고 있다(`refresh()`가 `app.reminder`를 쓴다).

- [ ] **Step 3: 연습 빈 화면에 다음 행동을 준다**

`App/Sources/Practice/PracticeScreen.swift`에서

```swift
        if entries.isEmpty {
            ContentUnavailableView {
                Label("아직 연습할 단어가 없습니다", systemImage: "square.dashed")
            } description: {
                Text("가사에서 줄을 눌러 단어를 담으면 그 단어와 가사로 문제를 만듭니다.")
            }
        } else {
```

를

```swift
        if entries.isEmpty {
            JustEmptyState(
                icon: "square.dashed",
                title: "아직 연습할 단어가 없습니다",
                message: "가사에서 줄을 눌러 단어를 담으면 그 단어와 가사로 문제를 만듭니다.",
                actionTitle: "곡 보러 가기",
                action: { app.tab = .browse }
            )
        } else {
```

로 바꾼다. 이 파일에 `@Environment(AppModel.self) private var app`이 없으면 추가한다.

- [ ] **Step 4: 앨범 로드 실패에 다시 시도를 준다**

`App/Sources/Player/AlbumSheet.swift`의 실패 분기에서 `ContentUnavailableView { Label("앨범을 불러오지 못했습니다", ...) } description: { Text(failure) }`를 아래로 바꾼다:

```swift
                        JustEmptyState(
                            icon: "square.stack",
                            title: "앨범을 불러오지 못했습니다",
                            message: failure,
                            actionTitle: "다시 시도",
                            action: { retryToken += 1 }
                        )
```

그리고 재시도가 실제로 동작하도록 `@State private var retryToken = 0`을 추가하고, 앨범을 불러오는 `.task`를 `.task(id: retryToken)`으로 바꾸며 그 안에서 `failure = nil`을 먼저 세워 이전 오류를 지운다.

- [ ] **Step 5: 나머지 여섯 곳을 공통 형태로 옮긴다**

행동 없이 형태만 통일한다. 각 파일에서 `ContentUnavailableView { Label(제목, systemImage: 아이콘) } description: { Text(설명) }` 꼴을 `JustEmptyState(icon: 아이콘, title: 제목, message: 설명)`으로 바꾼다.

- `App/Sources/Search/DiscoveryView.swift:125` — "좋아하는 노래로 시작하세요" / `music.note`
- `App/Sources/Player/SongWordsSheet.swift:39` — "담은 단어가 없습니다" / `character.book.closed`
- `App/Sources/Practice/QuizScreen.swift:39` — "연습할 단어가 없습니다" / `square.dashed`

`actions:`를 이미 가진 셋(`SearchScreen.swift:54` 연결 오류, `Settings/AppleMusicGate.swift:16`, `Review/ReviewScreen.swift:148`)은 **손대지 않는다.** 버튼이 둘인 경우가 있어 `JustEmptyState`의 단일 행동에 맞지 않고, 이미 보이는 버튼을 갖고 있다.

`SearchScreen.swift:68`의 `ContentUnavailableView.search(text: query)`도 **그대로 둔다.** 시스템이 검색 결과 없음에 맞는 문구와 아이콘을 알아서 준다.

- [ ] **Step 6: 프로젝트 재생성, 빌드와 테스트**

Run:
```
tuist generate --no-open
xcodebuild -workspace Just.xcworkspace -scheme Just -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|✘|Test run with|\*\* TEST"
```

Expected: `Test run with 82 tests in 17 suites passed`.

- [ ] **Step 7: 커밋**

```bash
git add Modules/JustDesign/Sources/JustEmptyState.swift App/Sources
git commit -F - <<'EOF'
feat(ui): 비어 있는 화면이 다음 행동을 준다

빈 화면 열 곳 중 일곱 곳에 행동 버튼이 없었다. 그중 셋 — 단어장, 연습, 앨범
로드 실패 — 은 사용자가 탭 바를 스스로 찾아야만 벗어날 수 있는 막다른 길이었다.
단어장과 연습은 「곡 보러 가기」로 둘러보기 탭에 보내고, 앨범 실패는 다시
시도하게 한다.

공통 형태는 ContentUnavailableView를 대체하지 않고 감싼다. 시스템 뷰가 레이아웃,
Dynamic Type, 접근성을 이미 처리하므로 새로 그리면 그것을 잃는다. 감싸서 얻는
것은 버튼 스타일을 한 곳에서 정하는 것과, actionTitle이라는 이름 덕에 "내놓을
길이 있는가"가 호출부마다 눈에 보이는 결정이 된다는 것이다.

검색 결과 없음과 복습 완료에는 버튼을 넣지 않았다. 전자는 검색어를 바꾸면
되고, 후자는 실패가 아니라 결승선이다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

---

### Task 5: 시뮬레이터에서 눈으로 확인

단위 테스트로 덮이지 않는 부분이다. 각 항목을 스크린샷으로 확인한다.

**Files:** 없음 (검증만)

- [ ] **Step 1: 설치**

```bash
xcodebuild -workspace Just.xcworkspace -scheme Just -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/just-dd build
xcrun simctl install booted /tmp/just-dd/Build/Products/Debug-iphonesimulator/Just.app
xcrun simctl privacy booted grant media-library com.coby.just
xcrun simctl launch booted com.coby.just
```

- [ ] **Step 2: 단어장 빈 화면**

단어장 탭. 확인할 것: 「곡 보러 가기」 버튼이 흰 캡슐로 보이고, 누르면 **둘러보기 탭으로 넘어간다**.

- [ ] **Step 3: 연습 빈 화면**

연습 탭. 확인할 것: 같은 버튼이 있고 같은 곳으로 보낸다.

- [ ] **Step 4: 미니플레이어**

곡을 하나 준비시켜 재생 상태를 만든 뒤 플레이어를 닫는다. 확인할 것: 재생/일시정지와 종료 버튼이 **원형 배경과 테두리를 갖고**, 이전보다 크다.

- [ ] **Step 5: 단어 카드의 담기 버튼**

가사 줄을 눌러 단어 카드를 연다. 확인할 것: `+` 버튼이 44pt로 커졌고, 누르면 초록 체크로 바뀐다(저장 표시가 살아 있다).

- [ ] **Step 6: 후리가나 토글과 전체화면 전송부**

플레이어 상단 후리가나 버튼이 44pt이고 켜짐/꺼짐이 여전히 배경 채움으로 구분되는지. 「⋯」 → 가사 전체화면으로 들어가 하단 재생 버튼이 배경을 갖는지.

- [ ] **Step 7: 결과 보고**

스크린샷과 함께 정리한다. 확인하지 못한 것이 있으면 그것도 밝힌다.

---

## Self-Review

**스펙 대조**

| 스펙 요구 | 담당 |
|---|---|
| `JustIconButtonStyle` 신설, 44pt 보장 | Task 1 |
| 배경 없는 셋에 적용 | Task 2 Step 1·2 |
| 배경 있는 둘은 크기만 | Task 2 Step 3·4 |
| `∨`/`⋯`는 `.glass` 유지 | 손대지 않음 (계획에 등장하지 않음) |
| `JustEmptyState` — 시스템 뷰를 감싼다 | Task 4 Step 1 |
| 단어장·연습에 「곡 보러 가기」 | Task 4 Step 2·3 |
| 앨범 실패에 「다시 시도」 | Task 4 Step 4 |
| 버튼 없는 여섯 곳은 형태만 통일 | Task 4 Step 5 |
| 탭 선택을 `AppModel`로 | Task 3 |
| 82개 테스트 유지 + 스크린샷 검증 | 각 Task의 테스트 단계, Task 5 |

**스펙보다 좁힌 것:** 스펙은 "나머지 빈 화면 6곳"을 공통 형태로 옮긴다고 했지만, 계획은 **셋만** 옮긴다. 나머지 셋은 이미 `actions:`로 버튼을 갖고 있고, 그중 둘은 버튼이 두 개여서 `JustEmptyState`의 단일 행동에 맞지 않는다. 억지로 맞추려면 컴포넌트에 두 번째 버튼을 넣어야 하는데, 그것은 호출부 두 곳을 위해 API를 넓히는 일이다. `SearchScreen`의 `.search(text:)`도 시스템이 더 잘하므로 그대로 둔다.

**타입 일관성:** `JustIconButtonStyle.minimumTapTarget`은 Task 1에서 정의하고 Task 2 Step 3·4에서 쓴다. `AppModel.Tab`은 Task 3에서 정의하고 Task 4 Step 2·3에서 `app.tab = .browse`로 쓴다. `JustEmptyState`의 인자 이름(`icon:title:message:actionTitle:action:`)은 Task 4 전체에서 동일하다.

**남은 위험:** `RootView`의 `Tab("오늘", ..., value: Destination.today)`에서 `Destination`을 지우면 네 곳의 `value:`를 모두 고쳐야 한다. 하나라도 놓치면 컴파일이 깨지므로 Task 3 Step 3의 빌드에서 바로 잡힌다.
