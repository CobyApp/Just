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

둘러보기 ──┬─ 검색 (Apple Music 카탈로그)
          ├─ 이어서 공부하기 (진도 표시)
          ├─ 일본 인기곡 (J-Pop 차트)
          └─ 〈아티스트〉의 다른 곡 (보관함 기반 추천)
             ↓ 곡 선택
          플레이어 ──┬─ 싱크 가사 + 후리가나  → 줄 탭 → 단어 카드
                    └─ 앨범 이름 탭 → 앨범 전곡

단어장 ────┬─ 통계 (대기·연속·총계) + JLPT 분포 차트
          └─ JLPT 필터 + 단어 목록 → 단어 상세 (나온 곡 전부)

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
| 재생 | ApplicationMusicPlayer | 전곡 재생은 구독 필요 |
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

## 남은 것

- 번들 사전 6.9천 단어 중 등급·품사가 붙은 것은 손으로 확인한 149개뿐입니다.
- 앨범 전체 트랙 조회(`AppleMusicClient.albumTracks`)는 구현되어 있으나 화면이 없습니다.
- 구독이 없는 계정을 위한 30초 미리듣기 재생 경로가 없습니다.
- 뮤직비디오는 다루지 않습니다. 공개 API로는 전체 재생이 불가능합니다.
- 곡 난이도는 분석한 줄에서만 집계되므로, 일부만 분석한 곡은 표본이 작습니다.

시뮬레이터에는 Apple Music 계정이 없어 곡을 열 방법이 없으므로, DEBUG 빌드에서만
검색 화면에 샘플 곡 3개가 나옵니다 (`App/Sources/Search/DebugSamples.swift`).
재생은 실패하지만 가사·해석·저장·복습은 실제로 동작합니다.
