# Just

J-POP 가사로 일본어를 공부하는 iPhone / iPad 앱.

노래 한 곡이 학습 한 세트입니다. 가사 줄을 누르면 그 줄이 단어로 쪼개지고, 담은
단어는 실제로 나온 가사를 예문 삼아 간격 반복 복습으로 넘어갑니다.

## 만드는 법

```bash
tuist generate
```

Xcode 26.6 이상, iOS 26 SDK, Swift 6.3 기준입니다.

## 실행 전 준비 (한 번만)

Apple Music은 **앱에 붙여넣을 API 키가 없습니다.** 대신 App ID에 서비스를
켜 주어야 MusicKit이 개발자 토큰을 스스로 발급합니다.

1. [Apple Developer 계정의 Identifiers](https://developer.apple.com/account/resources/identifiers/list)
   에서 `com.coby.just` App ID를 만들고 **MusicKit**을 켭니다.
2. Xcode에서 `Just` 타깃 → Signing & Capabilities → 팀을 선택합니다.
3. **실제 기기에서 실행합니다.** 시뮬레이터에는 Apple Music 계정이 없어
   카탈로그 검색과 재생이 동작하지 않습니다.

첫 실행 시 앱이 Apple Music 접근 권한을 요청합니다.

## 화면

```
오늘 ──────┬─ 연속일수 링 + 주간 복습 그래프
          ├─ 복습 대기 CTA
          └─ 이어서 공부하기 (난이도 바)

둘러보기 ──┬─ 검색 (입력하는 대로, 350ms 디바운스)
          ├─ 이어서 공부하기 (진도 표시)
          ├─ 일본 인기곡 (J-Pop 차트)
          └─ 〈아티스트〉의 다른 곡 (보관함 기반 추천)
             ↓ 곡 선택
          플레이어 ──┬─ 싱크 가사 + 후리가나  → 줄 탭 → 단어 카드
                    ├─ 한 줄 구간 반복
                    ├─ 가사 크기 4단계
                    ├─ 이 곡의 단어 (담은 것 모아보기)
                    └─ 앨범 이름 탭 → 앨범 전곡

단어장 ────┬─ 통계 (대기·연속·총계) + JLPT 분포 차트
          └─ JLPT 필터 + 정렬(담은/등급/임박/빈도) → 단어 상세

연습 ──────┬─ 복습 카드 (FSRS)
          ├─ 랜덤 믹스
          ├─ 빈칸 채우기 — 가사에서 단어를 지우고 직접 입력
          ├─ 뜻 보고 쓰기
          └─ 사지선다
```

퀴즈 결과는 별도 점수가 아니라 **FSRS 일정에 그대로 반영**됩니다. 맞히면 `good`,
형태만 틀리면 `hard`, 틀리면 `again`입니다.

입력은 로마자를 받습니다. 한국어 화자의 시스템 키보드는 보통 한글이라
`yume`를 눌러도 자모가 들어오므로, 입력 필드를 ASCII 키보드로 고정하고
로마자를 가나로 실시간 변환해 보여줍니다.

## 구조

```
Just (앱)
 ├── JustCore     도메인 모델, SwiftData 스키마, FSRS 스케줄러
 ├── JustDesign   팔레트 추출, 메시 배경, 후리가나 조판
 ├── JustMusic    MusicKit 검색 + ApplicationMusicPlayer
 ├── JustLyrics   LRCLIB 클라이언트, LRC 파서
 └── JustSensei   형태소 분석, 읽기, 온디바이스 해석 엔진
```

### 데이터 출처

| | 출처 | 비고 |
|---|---|---|
| 곡·앨범·아트워크 | Apple Music (MusicKit) | 키 불필요, 쿼터 없음 |
| 재생 | ApplicationMusicPlayer | 구독 없으면 30초 미리듣기로 대체 |
| 가사 | LRCLIB | 무인증, 싱크 LRC |
| 해석 | Apple Intelligence (온디바이스) | 사전 폴백 내장 |
| 한자 음훈 | 번들 (1,591자) | 한국어 학습자용 |

**Apple Music API는 가사를 제공하지 않습니다.** 음악 앱에 가사가 보이는 것과
별개로 공개 API에는 열려 있지 않아, 싱크 가사는 LRCLIB에서 받습니다.

### 로컬 저장

곡을 열면 그 곡에 딸린 모든 데이터가 기기에 남습니다.

| 데이터 | 위치 | 비고 |
|---|---|---|
| 가사 (LRC) | `StudySong.lyricsData` | 오프라인 재열람 가능 |
| 줄별 해석 전체 | `StudySong.analysisData` | 번역 + 단어 + 문법. 모델은 곡당 한 번만 돈다 |
| 난이도 히스토그램 | `StudySong.levelCounts` | 목록에서 해석을 디코드하지 않아도 되도록 비정규화 |
| 단어·복습 일정 | `VocabEntry` / `ReviewState` | |
| 앨범아트 | Caches/Artwork | URL 해시 파일명. 시스템이 회수 가능 |

곡을 처음 열면 **전곡 해석이 자동으로 시작**됩니다. 줄마다 눌러 기다리는 대신
한 번에 만들어 저장합니다. 진행분은 즉시 기록되므로 중간에 닫아도 버려지지 않고,
다시 열면 남은 줄부터 이어서 합니다.

자동 해석 시점은 설정에서 고릅니다 — 항상 / **저전력 모드가 아닐 때**(기본) / 안 함.
기본값이 저전력 모드를 따르는 이유는, 사용자가 이미 시스템에 에너지 사용 방침을
말해 두었기 때문입니다. 학습 앱이 그걸 앞질러 판단할 이유가 없습니다.

### 번들 사전

`Modules/JustSensei/Resources/seed-dictionary.json`은 생성물입니다.

```bash
python3 Scripts/build-dictionary.py
```

두 층으로 나뉩니다. `Scripts/curated.json`의 149개는 손으로 확인한 것이라 품사와
JLPT 등급까지 신뢰할 수 있고, 나머지 6.8천개는 옆 프로젝트인 `jlpt-app`의
일한 단어 데이터에서 가져왔습니다. 후자는 **뜻과 읽기만** 씁니다 — 원본의 `lv`
필드는 난이도가 아니라 교재 소속 태그라(전 행이 `n1`, 안경과 도서관까지) 등급으로
쓰면 없느니만 못합니다.

### 해석 파이프라인

```
가사 한 줄
 ├─ CFStringTokenizer   문맥 인식 분절 + 읽기
 ├─ NLTagger            사전형(lemma) · 품사
 ├─ FoundationModels    한국어 번역 · 뜻 · 뉘앙스 (guided generation)
 └─ 번들 사전 교차검증   표제어 · 읽기 · 품사 · JLPT 등급 덮어쓰기
                        (가사에 쓰인 표기를 읽기보다 우선)
```

온디바이스 모델은 문맥에는 강하고 암기에는 약합니다. 「〜てる」를 「〜ている」로
되돌리거나 가사를 자연스러운 한국어로 옮기는 일은 잘 하지만, JLPT 등급을 지어내고
표제어 자리에 읽기를 쓰기도 합니다. 그래서 **판단은 모델에, 사실은 사전에** 맡기고,
가사에 실제로 없는 단어는 버립니다 (`JustSensei/Sensei.swift`의 `refine`).

## 접근성

모든 본문 텍스트가 Dynamic Type을 따릅니다. `Font.system(size:)`는 시스템
글자 크기 설정을 무시하고 `Font.custom(_:size:relativeTo:)`는 폰트 파일 이름을
요구하므로, `UIFont`를 `UIFontMetrics`로 통과시키는 `Font.just(_:weight:relativeTo:)`를
씁니다 — 디자인된 포인트 크기를 유지하면서 설정을 존중합니다.

고정 크기로 남긴 것은 SF Symbol 아이콘과 연속일수 링의 숫자뿐입니다. 둘 다
글자와 함께 커지면 안 되는 고정 지오메트리 안에 있습니다.

가사는 여기에 앱 자체의 4단계 조절이 곱해집니다. 시스템 설정과 앱 설정이
같은 텍스트에 함께 작용하므로, 접근성 크기에서는 가사 크기를 낮춰 쓰면 됩니다.

## 위젯

홈 화면 위젯은 앱의 SwiftData를 열지 않습니다. 앱이 App Group 컨테이너에
작은 스냅샷(JSON)을 쓰고 위젯은 그걸 읽습니다 — 위젯이 앱 데이터베이스를
여는 것은 스키마 변경을 따라다녀야 하고 쓰기도 못 하며, 숫자 세 개를 읽자고
기존 사용자 데이터를 마이그레이션할 이유도 없습니다.

App Group `group.com.coby.just`가 필요합니다. 자동 서명이 등록하지 못하면
developer.apple.com > Identifiers > App Groups에서 만들고, App ID의
App Groups 기능에서 연결해 주세요.

## MusicKit App ID 설정 (필수, 1회)

검색이 "개발자 토큰 요청 실패"로 죽으면 이것 때문입니다.

MusicKit은 개발자 토큰을 자동으로 발급하지만, **명시적 App ID에 MusicKit
서비스가 켜져 있을 때만** 가능합니다. 와일드카드 팀 프로비저닝
프로파일(`TEAM.*`)로 서명하면 실패하고, 오류 메시지는 토큰만 말하고 정작
원인인 포털 스위치는 언급하지 않습니다.

1. developer.apple.com > Certificates, Identifiers & Profiles > **Identifiers**
2. **+** > App IDs > App > Bundle ID는 **Explicit**로 `com.coby.just`
3. 그 App ID의 **App Services**에서 **MusicKit** 체크 후 저장
4. 다시 빌드 (`-allowProvisioningUpdates`가 새 프로파일을 받아옵니다)

설정 화면의 **카탈로그 연결 > 연결 확인**으로 실제 성공 여부를 볼 수 있습니다.

## 빌드와 배포

옆 프로젝트 `mana`와 같은 구성입니다.

```bash
bash Scripts/setup.sh        # tuist generate
bundle exec fastlane test    # 시뮬레이터 테스트
bundle exec fastlane beta    # TestFlight 업로드
```

Tuist 버전은 `.mise.toml`에 고정합니다. 서명은 자동이고 팀 id는 매니페스트에
있으므로 `tuist generate`만으로 기기 빌드가 됩니다.

TestFlight는 App Store Connect API 키로 클라우드 서명합니다 — 인증서를 손으로
갱신할 일이 없습니다. 인증 플래그는 `xcargs` 한 곳에만 둡니다(gym이 archive와
export 양쪽에 그대로 넘기므로 `export_xcargs`로 중복하면 xcodebuild가 거부합니다).

`v*` 태그를 밀면 `.github/workflows/deploy.yml`이 돌고, 필요한 시크릿은
`APPSTORE_KEY_ID` / `APPSTORE_ISSUER_ID` / `APPSTORE_PRIVATE_KEY`입니다.

버전은 `MARKETING_VERSION`과 `CURRENT_PROJECT_VERSION`이 정합니다. Info.plist에
값을 박아두면 fastlane이 넘기는 빌드 번호가 무시되어 업로드가 매번 충돌합니다.

`App/Resources/PrivacyInfo.xcprivacy`는 필수입니다. 이 앱은 추적을 하지 않고
수집 항목도 없으며, 필수 사유 API는 UserDefaults(CA92.1) 하나입니다.

## 테스트

```bash
xcodebuild -workspace Just.xcworkspace -scheme Just \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

순수 로직만 덮습니다 — 파싱, 스케줄링, 문자열 처리. 지금까지 실제로 나온 버그가
전부 그 영역이었고, 기기·계정·모델 없이 검증할 수 있는 부분도 거기까지입니다.
56개 테스트가 있고, 그중 여러 개는 실제로 겪은 회귀를 그대로 고정해 둔 것입니다:
CRLF 가사 분할, 번역본 오선택, 동음이의어 표기 뒤바뀜.

## 남은 것

- 번들 사전 6.9천 단어 중 등급·품사가 붙은 것은 손으로 확인한 149개뿐입니다.
- 앨범 전체 트랙 조회(`AppleMusicClient.albumTracks`)는 구현되어 있으나 화면이 없습니다.
- 뮤직비디오는 다루지 않습니다. 공개 API로는 전체 재생이 불가능합니다.
- 곡 난이도는 분석한 줄에서만 집계되므로, 일부만 분석한 곡은 표본이 작습니다.

시뮬레이터에는 Apple Music 계정이 없어 곡을 열 방법이 없으므로, DEBUG 빌드에서만
검색 화면에 샘플 곡 3개가 나옵니다 (`App/Sources/Search/DebugSamples.swift`).
재생은 실패하지만 가사·해석·저장·복습은 실제로 동작합니다.

## 라이선스

MIT. 다만 번들 데이터의 출처는 구분해서 봐 주세요.

- `Scripts/curated.json` (149단어), `Modules/JustSensei/Resources/kanji-ko.json`
  (한자 1,591자 음훈), 그리고 `seed-dictionary.json`의 대부분은 이 저장소 소유자의
  다른 프로젝트에서 가져온 데이터입니다.
- 가사는 저장소에 포함되지 않습니다. 실행 시 [LRCLIB](https://lrclib.net)에서
  받아 기기에만 저장됩니다.
- 곡 정보와 아트워크는 Apple Music 카탈로그에서 옵니다. Apple Media Services
  이용약관이 적용됩니다.
