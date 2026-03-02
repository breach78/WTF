# wa 프로젝트 정밀 리서치 보고서

작성일: 2026-03-02  
분석 대상 루트: `/Users/three/app_build/wa`

## 0) 수행 범위와 검증 결과

- 루트 및 `wa/` 하위 Swift 소스 전량(`22,769` LOC)을 읽고 구조를 추적했다.
- 프로젝트 설정(`Info.plist`, `wa.xcodeproj/project.pbxproj`)과 README를 교차 검증했다.
- 빌드 검증: `xcodebuild -project wa.xcodeproj -scheme wa -configuration Debug -quiet build` 성공.
- 이번 문서는 기능 나열이 아니라, 실제 런타임/저장/상태 전이 기준으로 동작을 역추적한 결과다.

## 1) 프로젝트 한 줄 요약

`WTF`는 macOS용 계층형 카드 기반 시나리오 편집기이며, 핵심 엔진은 `ScenarioWriterView`를 중심으로 한 카드 편집/히스토리/포커스 모드/AI(Gemini)/음성 받아쓰기/스크립트 PDF 출력/레퍼런스 보조창으로 구성된다.

## 2) 코드베이스 맵 (핵심 파일)

| 파일 | LOC | 역할 |
|---|---:|---|
| `wa/waApp.swift` | 2461 | 앱 엔트리, 워크스페이스 북마크, 백업, 명령 라우팅, 설정/메인 컨테이너 |
| `wa/WriterViews.swift` | 1481 | 메인 편집기 상태 허브, 레이아웃/모드 전환 중심 |
| `wa/WriterCardManagement.swift` | 2524 | 카드 생성/삭제/이동, DnD, 클립보드, AI 후보 반영 |
| `wa/WriterFocusMode.swift` | 2435 | 포커스 모드 전용 편집/스크롤/캐럿 안정화 |
| `wa/WriterHistoryView.swift` | 1686 | 스냅샷 엔진, 타임라인 미리보기, 네임드 스냅샷/노트 |
| `wa/WriterAI.swift` | 3450 | AI 채팅 스레드, RAG/임베딩/로컬 벡터 DB, 후보 생성 프롬프트 |
| `wa/GeminiService.swift` | 626 | Gemini 텍스트/JSON/임베딩 API 호출 및 파싱/재시도 |
| `wa/WriterSpeech.swift` | 620 | 실시간 받아쓰기(AVAudioEngine+Speech), Apple Intelligence 요약 적용 |
| `wa/Models.swift` | 1147 | `Scenario`, `SceneCard`, `HistorySnapshot`, `FileStore` |
| `wa/ScriptPDFExport.swift` | 1117 | 스크립트 파싱 및 중앙정렬식/한국식 PDF 렌더러 |
| `wa/WriterUndoRedo.swift` | 692 | 일반/타이핑/포커스 분리 Undo/Redo + 코얼레싱 |
| `wa/WriterKeyboardHandlers.swift` | 1356 | 키보드 단축키/이동/범위선택/계층 이동 |
| `wa/WriterCaretAndScroll.swift` | 814 | 메인 편집 캐럿 추적/가시화/라인스페이싱 강제 |
| `wa/WriterCardViews.swift` | 867 | 카드 셀 UI, 에디터 높이 측정, 드롭 delegate |
| `wa/ReferenceWindow.swift` | 757 | 레퍼런스 보조창, 자체 Undo/Redo, 선택 카드 노출 |
| `wa/WriterSharedTypes.swift` | 419 | 공용 타입/상수/색 파서/클립보드 payload |
| `wa/KeychainStore.swift` | 94 | Gemini API 키 Keychain 저장/조회/삭제 |
| `wa/ContentView.swift` | 1 | 사실상 미사용(빈 파일) |

## 3) 앱 부팅과 워크스페이스(.wtf) 수명주기

### 3.1 워크스페이스 선택/복원

- 앱은 `.wtf`를 폴더 패키지로 취급한다(`UTType waWorkspace`, `LSTypeIsPackage=true`).
- 최초 실행 또는 리셋 시 `NSSavePanel`/`NSOpenPanel`로 `.wtf`를 선택하고, Security-scoped bookmark를 `@AppStorage("storageBookmark")`에 저장한다.
- 재실행 시 bookmark를 복원하고 stale이면 갱신한다.
- 복원 성공 시 `FileStore(folderURL: workspaceURL)`를 만들고 `load()` 비동기 로딩 후 메인 UI를 띄운다.

### 3.2 다중 창 및 명령 라우팅

- 기본 창: 메인 편집.
- 보조 창: `ReferenceWindowConstants.windowID` 식별자로 레퍼런스 카드 창.
- `NotificationCenter` 브로드캐스트로 Undo/Redo/포커스 토글/레퍼런스 창 열기/스플릿 포커스 명령을 각 뷰로 전달한다.
- CommandGroup을 직접 치환해 전역 단축키 동작을 강제한다.

### 3.3 종료 시 처리

- `willTerminate`에서 pending save flush.
- 옵션이 켜져 있으면 `.wtf`를 `ditto`로 `.wtf.zip` 압축 백업 후 보관 정책에 따라 pruning.

## 4) 데이터 모델과 핵심 불변식

### 4.1 `Scenario`

- `cards`, `snapshots`, `timestamp`, `changeCountSinceLastSnapshot` 보유.
- `cardsVersion` 기반 캐시 재구축 전략:
  - root 카드 목록
  - parent->children 맵
  - cardID 인덱스
  - card 위치(level/index)
  - clone group 멤버 맵
  - 전체 level 배열
- 수정 타임스탬프는 즉시 반영이 아니라 디바운스(`0.14s`) 반영.
- 타임스탬프 suppression 모드 2종:
  - 일반 suppression
  - 인터랙션(편집중) suppression

### 4.2 `SceneCard`

- 핵심 필드: `content`, `orderIndex`, `parent`, `category`, `isFloating`, `isArchived`, `colorHex`, `cloneGroupID`, `isAICandidate`.
- `content`/`colorHex` 변경 시 cloneGroup 동기화 전파.
- `orderIndex`/`parent`/archive/floating 변경 시 계층 캐시 무효화 목적 `bumpCardsVersion()`.

### 4.3 클론 카드 동기화

- cloneGroupID 기준 다중 카드가 있을 때 원본 변경이 peer로 전파된다.
- 재진입 방지(`activeCloneSyncGroupIDs`)로 순환 업데이트를 막는다.

## 5) 저장 구조 (`FileStore`) 상세

### 5.1 실제 디스크 레이아웃

`.wtf` 내부:

```text
workspace.wtf/
  scenarios.json
  scenario_<SCENARIO_UUID>/
    cards_index.json
    history.json
    card_<CARD_UUID>.txt
    ai_threads.json
    ai_embedding_index.json
    ai_vector_index.sqlite
```

### 5.2 저장 전략

- 메인 thread에서 payload 생성 후 saveQueue에 enqueue.
- worker 단일 루프가 최신 payload만 순차 처리(`pendingPayload` 덮어쓰기).
- 시나리오별 파일 I/O는 `concurrentIOQueue` 병렬 처리.
- dirty cache(`lastSaved...`)로 바뀐 JSON/텍스트만 기록.
- 카드 삭제 시 orphan `card_*.txt` 정리.

### 5.3 로딩 전략

- `scenarios.json` 로드 후 시나리오 폴더를 TaskGroup 병렬 로딩.
- 각 카드 본문은 `card_<id>.txt` 별도 읽기.
- parent 링크 재연결 후 snapshot 복원.

### 5.4 AI 저장 데이터

- 스레드: `ai_threads.json` (`AIChatThreadStorePayload`).
- 임베딩 인덱스: `ai_embedding_index.json` (`model`, records).
- 로컬 벡터/토큰 인덱스: `ai_vector_index.sqlite`.

## 6) 메인 편집 엔진 (`ScenarioWriterView`) 동작

### 6.1 상태 아키텍처

- 대규모 `@State`로 편집/선택/히스토리/AI/딕테이션/포커스/캐럿/Undo 스택을 분리 관리.
- split mode에서는 활성 pane과 비활성 pane을 분리하고 비활성 pane은 stale snapshot 렌더링으로 비용을 낮춘다.

### 6.2 카드 편집/이동 핵심

- `finishEditing()`이 대부분의 변형 동작의 트랜잭션 경계.
- 변경은 `captureScenarioState()` -> mutate -> `commitCardMutation(...)`으로 Undo+히스토리 연동.
- DnD는 서브트리 이동 시 descendant 금지/인덱스 재정렬/다중 루트 처리.

### 6.3 클립보드(트리/클론) 파이프라인

- 자체 pasteboard payload 타입 사용:
  - 카드 트리 payload
  - 클론 카드 payload
- cut 상태 버퍼를 별도 추적 후 paste 시 parent/child/sibling 배치 다이얼로그 처리.

## 7) 키보드/내비게이션/캐럿 알고리즘

### 7.1 키보드 처리

- 전역 핸들러는 모드별 우선순위를 가진다.
- 히스토리 모드, 텍스트 편집 중, 포커스 모드, 스플릿 pane 활성 여부에 따라 같은 키의 의미가 달라진다.
- `Cmd+Shift+Arrow`는 계층 이동(구조 이동), 화살표는 카드 탐색, Shift 조합은 범위 선택 앵커 유지.

### 7.2 메인 캐럿 안정화 (`WriterCaretAndScroll`)

- selection change 알림을 기반으로 active edge(start/end) 추적.
- `NSTextView` 내부 스크롤과 외부 ScrollView 스크롤 간 충돌을 줄이기 위해 dead zone 기반 ensure-visible 적용.
- line spacing/typing attributes를 TextStorage에 강제 반영.

### 7.3 포커스 모드 캐럿 안정화 (`WriterFocusMode`)

- 포커스 모드 진입 직후 여러 번 caret apply를 반복 스케줄해 SwiftUI 포커스 경합 대응.
- 내부 editor clip origin을 강제로 정상화하여 튀는 현상 억제.
- typewriter 모드에서는 기준선(`focusTypewriterBaseline`) 중심 스크롤로 보정.

## 8) Undo/Redo 설계 (3계층)

### 8.1 스택 분리

- 일반 구조 변경 undo/redo (`undoStack`, `redoStack`).
- 메인 텍스트 타이핑 전용 coalesced undo.
- 포커스 텍스트 타이핑 전용 coalesced undo.

### 8.2 코얼레싱 경계

- idle gap(`focusTypingIdleInterval = 1.5s`) 경계.
- 카드 전환 경계.
- 문단 경계(줄바꿈).
- 문장 종결점(`.`/`。`) 경계.
- 소수점(`3.14`) 같은 경우는 분할 경계에서 제외.

### 8.3 커서 힌트 복원

- before/after 상태 diff로 caret hint 계산.
- undo/redo 후 활성 카드/selection 복원 + caret 재설정 재시도 루프.

## 9) 히스토리 스냅샷 엔진

### 9.1 스냅샷 포맷

- full snapshot: 전체 `CardSnapshot` 상태.
- delta snapshot: 변경 카드 + 삭제 cardID만 저장.
- named snapshot은 `name`과 optional `noteCardID`를 연결.

### 9.2 체크포인트 정책

- 연속 delta가 `deltaSnapshotFullCheckpointInterval = 30` 이상이면 full 강제 삽입.

### 9.3 보존(컴팩션) 정책

- 최소 보존 수(`historyRetentionMinimumCount = 180`) 이하에서는 컴팩션 생략.
- promoted(named 포함) 스냅샷 우선 보존.
- 나머지는 age-tier bucket별 최신 1개 보존:
  - 1시간 이내: 60초 버킷
  - 1일 이내: 10분 버킷
  - 1주 이내: 1시간 버킷
  - 1개월 이내: 1일 버킷
  - 그 이후: 1주 버킷
- 컴팩션 후 체인을 재구성할 때 중간에 full checkpoint를 주기적으로 다시 주입.

### 9.4 네임드 스냅샷 노트

- 네임드 스냅샷 생성 시 선택적으로 별도 노트 카드를 만들어 `noteCardID`로 연결.
- UI에서 네임드 목록/검색/미리보기/노트 편집을 제공.

## 10) AI 서브시스템 (가장 큰 서브모듈)

### 10.1 두 가지 AI 모드

- 상담 채팅 모드: 스레드형 대화(`AIChatThread`).
- 카드 생성 모드: 구체화/다음 장면/대안/요약 후보 카드 생성.

### 10.2 상담 채팅 파이프라인

1. 사용자 메시지 append.  
2. 스레드 scope에 따라 context 카드 집합 계산(`selectedCards/plotLine/noteLine`).  
3. digest cache와 embedding index snapshot 확보.  
4. semantic RAG context 생성 시도.  
5. 시스템 프롬프트+컨텍스트+히스토리+질문 결합.  
6. Gemini 호출(메타데이터 포함) 후 토큰 사용량 누적.  
7. model 응답 append, rolling summary 갱신, 임베딩 인덱스 persist 예약.

### 10.3 프롬프트 구성기(`AIChatPromptBuilder`)

- scoped context, global plot/note summary, history summary, rolling summary를 길이 budget 내로 압축.
- RAG 결과를 `[질문 연관 카드(RAG)]` 섹션에 주입.
- 출력 규칙을 강하게 제한:
  - 한국어
  - 본문만
  - 기본 3~6문장
  - 코드블록/JSON 금지

### 10.4 semantic RAG 구현

- 임베딩 모델 후보: `gemini-embedding-001`, `text-embedding-004`.
- 카드 텍스트를 잘라(`1800`) 임베딩.
- 변경 없는 카드 임베딩은 reuse 시도.
- local sqlite에 2종 인덱스 유지:
  - `embeddings` (vector blob)
  - `token_index` (lexical tf)
- query 시:
  - lexical token으로 1차 candidate 축소
  - cosine similarity로 재정렬
  - scoped 카드 보너스 점수(+0.08)
- 최종 상위 N개를 budget(`900`) 내 텍스트 컨텍스트로 변환.

### 10.5 채팅 응답 연속 청크 처리

- Gemini finish reason이 `MAX_TOKENS`면 continuation prompt로 최대 4청크까지 이어받는다.
- 중복 문장 병합은 suffix/prefix overlap 비교(최대 280자)로 처리.

### 10.6 카드 생성 모드

- 액션: `elaborate`, `nextScene`, `alternative`, `summary`.
- 옵션 세트(`AIGenerationOption`)를 프롬프트에 반영.
- 기본 5개 후보 생성(요약은 1개).
- 후보 카드는 색상 tint + `isAICandidate=true`로 시각적 구분.
- 선택 적용 시 액션별 반영 규칙:
  - elaborate/alternative: 부모 카드 본문 교체.
  - nextScene: 부모 바로 아래 형제 카드로 재배치.
  - summary: 부모 하단에 `---` 구분자로 append.
- 미선택 후보는 archive 처리.

### 10.7 에러/취소 처리

- 새 요청 시작 전 이전 Task cancel.
- 취소/실패 시에도 이미 준비된 context/digest/embedding은 가능한 범위에서 반영하여 손실 최소화.
- 실패 메시지를 model role message로 채팅에 남긴다.

## 11) Gemini API 계층 (`GeminiService`)

- 텍스트 생성, 제안(JSON), 임베딩 단건/배치 지원.
- 요청 timeout/재시도 경로 존재.
- 응답에서 code fence 제거 후 JSON parse 다중 경로 시도.
- 모델/버전 fallback(v1, v1beta) 분기 포함.

## 12) 음성 받아쓰기 (`WriterSpeech`)

- `AVAudioEngine` + `SFSpeechRecognizer` 실시간 전사.
- partial 결과 reset을 감지해 committed+draft text를 병합.
- 종료 시 transcript를 부모 카드에 반영.
- 가능 환경이면 `FoundationModels` 기반 요약 생성 후 함께 append.
- 요약 실패 시 전사만 반영하고 에러 상태를 별도로 전달한다.

## 13) PDF/텍스트 출력

### 13.1 파서

- `ScriptMarkdownParser`가 카드 텍스트를 스크립트 요소(씬, 대사, 지문 등)로 해석.

### 13.2 렌더러

- `ScriptCenteredPDFGenerator`: 중앙정렬식.
- `ScriptKoreanPDFGenerator`: 한국식.
- 공통으로 페이지 브레이크, 미분할 블록, 글꼴/행간/정렬 옵션 처리.
- 설정(`AppStorage`)에서 폰트 크기/강조/정렬 옵션을 사용자 조절 가능.

## 14) 레퍼런스 창 (`ReferenceWindow`)

- 메인 시나리오의 선택 카드들을 별도 floating utility window에서 고정 참조.
- `ReferenceCardStore`가 UserDefaults 영속화 + 자체 undo/redo를 갖는다.
- 메인 Undo와 충돌하지 않게, reference 창 포커스 상태일 때는 reference undo/redo 우선 수행.

## 15) 설정/테마/UX 정책

- 광범위한 `@AppStorage` 기반 사용자 옵션:
  - 외관(라이트/다크/자동), 배경/카드 색상 테마
  - 폰트/줌/행간
  - 포커스 typewriter
  - PDF 출력 프리셋
  - Gemini 모델 ID
  - 백업 옵션/경로
- 메인 윈도우 title 숨김, 창 크기 복원/저장.
- 스플릿 모드에서 활성 pane만 입력 수용.

## 16) 성능/동시성 설계 포인트

- 로딩: 시나리오별 병렬 로딩(TaskGroup).
- 저장: payload 합성(main) + save worker(serial) + 시나리오별 I/O 병렬.
- UI 안정화:
  - caret ensure coalescing
  - scroll suppression 플래그
  - programmatic content suppress window(undo 직후 등)
- AI 인덱싱:
  - 변경 카드만 재임베딩
  - lexical candidate 좁힌 뒤 vector score

## 17) 확인된 리스크 및 개선 권고

### 17.1 기술 리스크

- `String.hashValue`를 임베딩 contentHash로 사용 중.
  - Swift `hashValue`는 프로세스 간 안정성이 보장되지 않아 재실행 시 캐시 재사용률이 떨어질 수 있다.
  - 권고: stable hash(SHA-256/xxHash)로 교체.

- `ENABLE_APP_SANDBOX = NO`.
  - 배포 정책/보안 요구가 있는 환경에서는 제약이 될 수 있다.

- `MACOSX_DEPLOYMENT_TARGET = 26.2`.
  - 매우 최신 타깃이므로 하위 macOS 호환 범위가 좁다.

- `wa/ContentView.swift`는 빈 파일.
  - 잔존 아티팩트라면 정리 권장.

### 17.2 제품 동작 관점

- AI 프롬프트/옵션/후보 생성 로직이 강력하지만 한 파일(`WriterAI.swift`)에 집중되어 유지보수 난이도가 높다.
  - 권고: `ThreadStore`, `RAGIndexer`, `PromptBuilder`, `CandidateApplier` 단위로 분리.

- 대규모 `@State` 집합(`ScenarioWriterView`)은 회귀 원인 추적이 어렵다.
  - 권고: 상태 도메인별 ViewModel 분리(History, AI, Caret, Focus).

### 17.3 문서 일관성

- README의 일부 모델 표기가 코드 기본값(`gemini-3.1-pro-preview`)과 불일치 가능성이 있다.
  - 권고: README/설정 기본값 동기화.

## 18) 실제 동작 플로우 요약

1. 앱 실행 -> bookmark로 `.wtf` 복원 -> `FileStore.load()` 병렬 로드.  
2. `MainContainerView`에서 시나리오 선택/편집.  
3. 카드 변경 시 `Scenario`가 timestamp/버전/clone 동기화 처리.  
4. `FileStore`가 디바운스+증분 저장.  
5. 히스토리는 delta/full 스냅샷과 retention 정책으로 누적/컴팩션.  
6. AI/받아쓰기/PDF/레퍼런스 기능이 같은 카드 모델에 비파괴적으로 결합.  
7. 종료 시 저장 flush + 조건부 압축 백업 + 백업 정리.

## 19) 결론

이 프로젝트는 단순 노트 앱이 아니라, `카드 계층 편집 엔진 + 히스토리 버전관리 + AI 보조 집필 + 음성 입력 + PDF 출력`을 단일 macOS 앱 안에서 정교하게 결합한 구조다.  
특히 강점은 `상태 복원력(Undo/Redo/캐럿 복구)`, `히스토리 엔진`, `RAG+로컬 인덱스 하이브리드`이며, 가장 큰 유지보수 과제는 `WriterAI.swift`/`WriterViews.swift`의 책임 과집중을 모듈화하는 것이다.
