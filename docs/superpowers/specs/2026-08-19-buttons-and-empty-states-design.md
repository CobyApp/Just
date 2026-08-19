# 무엇이 눌리는지 보이게 — 버튼과 빈 화면의 공통 규칙

2026-08-19

UI/UX 정리의 첫 덩어리(A). 나머지는 아래 "범위 밖"에 적었다.

## 문제

두 가지가 측정으로 확인됐다.

**버튼이 보이지 않는다.** 스타일 분포가 `.plain` 19개, `justPrimary` 10개,
`justSecondary` 6개, `.glass` 3개다. `.plain`은 "아무 표시도 하지 마라"는
뜻이므로, 앱에서 가장 흔한 버튼 스타일이 보이지 않기로 선언한 것이다.

19개 중 다수는 정당하다 — 곡 카드, 아트워크 타일, 가사 줄처럼 내용 자체가
누를 대상인 경우다. 문제는 진짜 컨트롤인데 `.plain`을 입은 넷과, 배경은
있지만 작은 하나다.

| 위치 | 버튼 | 현재 크기 |
|---|---|---|
| `App/Sources/Player/MiniPlayer.swift:48` | 재생/일시정지 | 32×32 |
| `App/Sources/Player/MiniPlayer.swift:58` | 재생 종료 | 30×30 |
| `App/Sources/Player/PlayerScreen.swift:343` | 전체화면 재생/일시정지 | 34×34 |
| `App/Sources/Player/LineStudySheet.swift:206` | 단어 담기 +/✓ | 배경 없음 |
| `App/Sources/Player/PlayerScreen.swift:144` | 후리가나 토글 | 34×34 (배경 있음) |

Apple이 정한 최소 탭 영역은 44×44다. 전부 그보다 작다.

**빈 화면이 다음 행동을 주지 않는다.** `ContentUnavailableView`를 쓰는 곳이
10군데인데 `actions:`를 준 곳은 3군데다. 단어장과 연습은 "가사에서 줄을 눌러
단어를 담으면 여기에 모입니다"라고만 말하고 끝난다. 곡을 열려면 사용자가
스스로 탭 바를 찾아야 한다.

## 결정

### 1. `JustIconButtonStyle` 신설 — 크기만 보장하고 배경은 칠하지 않는다

아이콘 전용 컨트롤을 위한 `ButtonStyle`. 최소 44×44 탭 영역을 보장하고 눌림에
반응한다. **자기 배경은 그리지 않는다.**

처음에는 `Surface.raised` 원형 배경을 입히기로 했다가, 실제로 화면에서 보고
되돌렸다. 미니플레이어는 이미 `.ultraThinMaterial` 캡슐 안이라, 반투명 바 안에
불투명한 회색 원 두 개가 얹히니 탁해 보였고 「종료」가 「재생」과 같은 무게로
커졌다.

돌아보면 진단이 절반 틀렸다. `.plain` 19개라는 숫자는 실제 냄새였지만, 문제의
그 다섯 개는 **전부 이미 컨테이너 안이거나 자기 배경을 갖고 있었다** — 미니
플레이어와 전체화면 전송부는 재질 캡슐 안, 후리가나 토글과 단어 담기 버튼은
상태를 말하는 자기 원 안. 공통된 결함은 배경 없음이 아니라 **크기**였다.
30~34pt 대 44pt.

그래서 규칙은 하나다. 아이콘 컨트롤은 44pt이고 눌림에 반응한다. **배경이
필요한지는 컨테이너가 결정한다.**

**플레이어 상단의 `∨`와 `⋯`는 `.glass`를 그대로 둔다.** 시스템 스타일이고
이미 배경이 있어 보이며, 손대면 iOS 26 기본 감각에서 멀어진다.

### 2. `JustEmptyState` 신설 — 시스템 컴포넌트를 감싼다

`ContentUnavailableView`를 **대체하지 않고 감싼다.** 그쪽이 접근성과 레이아웃을
공짜로 주므로, 새로 그리면 그것을 잃는다. 감싸는 이유는 세 부분(아이콘·제목·
설명)의 모양과 버튼 스타일을 한 곳에서 정하는 것뿐이다.

행동 버튼은 **필수로 만들지 않는다.** 일곱 곳 중 실제로 필요한 곳은 아래 표의
셋이고, "검색 결과 없음"이나 "복습할 게 없음"은 버튼이 없는 게 맞다 — 전자는
검색어를 바꾸면 되고, 후자는 실패가 아니라 완료다. 억지로 채우면 의미 없는
버튼이 일곱 개 생긴다.

| 빈 화면 | 행동 |
|---|---|
| `Library/LibraryScreen.swift:71` 저장한 단어 없음 | **곡 보러 가기** → 둘러보기 탭 |
| `Practice/PracticeScreen.swift:34` 연습할 단어 없음 | **곡 보러 가기** → 둘러보기 탭 |
| `Player/AlbumSheet.swift:30` 앨범 로드 실패 | **다시 시도** |
| `Search/SearchScreen.swift:54` 연결 오류 | 이미 있음 (유지) |
| `Settings/AppleMusicGate.swift:16` 권한 | 이미 있음 (유지) |
| `Review/ReviewScreen.swift:148` 복습 없음 | 이미 있음 (유지) |
| `Search/SearchScreen.swift:68` 검색 결과 없음 | 없음 — 검색어를 바꾸면 된다 |
| `Search/DiscoveryView.swift:125` 시작 안내 | 없음 — 검색창이 바로 위에 있다 |
| `Player/SongWordsSheet.swift:39` 담은 단어 없음 | 없음 — 시트를 닫으면 된다 |
| `Practice/QuizScreen.swift:39` 문제 없음 | 없음 — 앞 화면이 이미 막는다 |

### 3. 탭 선택을 `AppModel`로 올린다

단어장·연습의 빈 화면이 "곡 보러 가기"를 하려면 다른 탭으로 넘어가야 한다.
지금 탭 선택은 `RootView`의 `@State`에 갇혀 있어 화면에서 손댈 수 없다.
`AppModel`로 올려 화면이 목적지를 말할 수 있게 한다.

## 손댈 곳

| 파일 | 내용 |
|---|---|
| `Modules/JustDesign/Sources/JustTheme.swift` | `JustIconButtonStyle` 추가 |
| `Modules/JustDesign/Sources/JustEmptyState.swift` (신규) | 빈 화면 공통 형태 |
| `App/Sources/AppModel.swift` | 탭 선택 보유 |
| `App/Sources/RootView.swift` | 선택을 `AppModel`에서 읽기 |
| `App/Sources/Player/MiniPlayer.swift` | 아이콘 버튼 2곳 |
| `App/Sources/Player/PlayerScreen.swift` | 아이콘 버튼 1곳, 후리가나 44pt (스타일 유지) |
| `App/Sources/Player/LineStudySheet.swift` | 담기 버튼 44pt (스타일 유지) |
| `App/Sources/Library/LibraryScreen.swift` | 빈 화면 + 행동 |
| `App/Sources/Practice/PracticeScreen.swift` | 빈 화면 + 행동 |
| `App/Sources/Player/AlbumSheet.swift` | 빈 화면 + 행동 |
| 나머지 빈 화면 6곳 | 공통 형태로 교체 (행동 없음) |

## 검증

**이 작업에는 넣을 만한 단위 테스트가 없다.** 44pt 탭 영역과 버튼의 시각적
대비는 레이아웃 속성이라 스냅샷 테스트 없이 코드로 확인할 수 없고, 이
저장소에는 스냅샷 테스트 기반이 없다. 억지로 만드는 대신 두 가지로 확인한다.

- **기존 82개 테스트가 깨지지 않는 것** — 회귀만 막는다.
- **바뀐 화면을 하나씩 스크린샷** — 미니플레이어, 전체화면 전송부, 단어
  카드, 단어장 빈 화면, 연습 빈 화면. 각 버튼이 배경을 갖고 44pt인지, 빈
  화면의 「곡 보러 가기」가 실제로 둘러보기 탭으로 보내는지 본다.

## 범위 밖

- **B. 첫 화면(오늘)** — 커다란 「0」을 앞세우지 않기, 「이어서 공부하기」의
  겹친 진도/난이도 막대 정리. 오늘 화면은 `ContentUnavailableView`를 쓰지
  않아 이 덩어리의 공통 컴포넌트로 덮이지 않는다.
- **C. 플레이어** — 「⋯」 뒤에 숨은 다섯 기능(가사 전체화면, 남은 줄 분석,
  가사 크기, 이 곡의 단어, 앨범 보기) 재배치.
- **D. 단어장·연습** — 정렬·필터를 글자 있는 컨트롤로, 단어가 없을 때
  검색창과 정렬을 띄우지 않기.
