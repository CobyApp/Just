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

**Apple Music API는 가사를 제공하지 않습니다.** 음악 앱에 가사가 보이는 것과
별개로 공개 API에는 열려 있지 않아, 싱크 가사는 LRCLIB에서 받습니다.

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
```

온디바이스 모델은 문맥에는 강하고 암기에는 약합니다. 「〜てる」를 「〜ている」로
되돌리거나 가사를 자연스러운 한국어로 옮기는 일은 잘 하지만, JLPT 등급을 지어내고
표제어 자리에 읽기를 쓰기도 합니다. 그래서 **판단은 모델에, 사실은 사전에** 맡기고,
가사에 실제로 없는 단어는 버립니다 (`JustSensei/Sensei.swift`의 `refine`).

## 남은 것

- 번들 사전 6.9천 단어 중 등급·품사가 붙은 것은 손으로 확인한 149개뿐입니다.
- 앨범 전체 트랙 조회(`AppleMusicClient.albumTracks`)는 구현되어 있으나 화면이 없습니다.
- 구독이 없는 계정을 위한 30초 미리듣기 재생 경로가 없습니다.
