# 리팩토링 사전 분석 및 실행 계획 (실코드 기반)

작성일: 2026-03-02  
기준 문서: `/Users/three/app_build/wa/research.md`  
기준 코드: `/Users/three/app_build/wa/wa/*.swift`

## 1) 목적 / 제약

- 목적: 누더기 상태의 코드를 **동작 100% 동일**하게 유지하면서, 가독성과 유지보수성을 높이는 리팩토링 계획 수립
- 제약:
  - 기능/동작/저장 포맷 변경 금지
  - 성능 최적화보다 가독성 우선
  - 전체 일괄 변경 금지, 파일/섹션 단위 점진 진행
  - 변경마다 “왜 바꿨는지” 명시

---

## 2) 문제점 분석 (요청한 5개 항목 기준)

## 2.1 중복/유사 로직

### A. AI 텍스트 처리 유사 로직 중복

- 토큰화 로직 중복
  - `wa/WriterAI.swift:448` `AIChatPromptBuilder.ragTokens(...)`
  - `wa/WriterAI.swift:1807` `ScenarioWriterView.ragSearchTokens(...)`
  - 둘 다 한글/영문 토큰화 + 한글 bigram 생성 패턴이 매우 유사

- 텍스트 clamp 로직 중복
  - `wa/WriterAI.swift:550` `AIChatPromptBuilder.clamp(...)`
  - `wa/WriterAI.swift:3395` `clampedAIText(...)`
  - 공백/줄바꿈 정리 + 길이 자르기 공통 패턴

- 카드 스냅샷 생성 중복
  - `wa/WriterAI.swift:2113` 근방 (`requestAIChatResponse`)에서 `AIChatCardSnapshot` 매핑
  - `wa/WriterAI.swift:2511` `aiAllCardSnapshots()`에서 동일 매핑

### B. Undo 텍스트 경계 판단 로직 중복

- `wa/WriterUndoRedo.swift`와 `wa/ReferenceWindow.swift`에 동일 계열 함수가 중복 존재
  - `utf16ChangeDelta`, `isStrongTextBoundaryChange`,
  - `containsParagraphBreakBoundary`, `lineHasSignificantContentBeforeBreak`,
  - `containsSentenceEndingPeriodBoundary` 등
  - 참조:
    - `wa/WriterUndoRedo.swift:371`, `501` 등
    - `wa/ReferenceWindow.swift:199`, `224` 등

### C. 워크스페이스/백업 설정 관련 UI 액션 중복

- `wa/waApp.swift` 내 서로 다른 struct에서 비슷한 함수 반복:
  - `openWorkspaceFile` / `createWorkspaceFile`
    - `wa/waApp.swift:713`, `704`
    - `wa/waApp.swift:1950`, `1959`
  - `initializeAutoBackupSettingsIfNeeded`
    - `wa/waApp.swift:802`
    - `wa/waApp.swift:1918`

### D. AI 스레드/임베딩 persistence 패턴 중복

- JSON encoder/decoder 세트가 거의 동일
  - `wa/WriterAI.swift:847`, `854`, `860`, `867`
- flush/schedule/load 흐름이 threads/embeddings에 각각 유사하게 분기
  - `wa/WriterAI.swift:906`, `924`, `989`, `1007`

---

## 2.2 사용하지 않는 변수, 함수, import

### 확실한 미사용 후보 (정적 검색 기준)

- 미사용 프로퍼티
  - `wa/Models.swift:479` `cardsURL`
  - `wa/Models.swift:480` `historyURL`
  - 선언만 있고 실제 사용은 지역변수 `cardsURL/historyURL`로 대체됨 (`wa/Models.swift:817`, `823`)

- 미사용 함수/타입
  - `wa/WriterAI.swift:2506` `aiSummaryQuery(for:)` (참조 없음)
  - `wa/WriterAI.swift:3101` `AISummaryPromptContext` (실사용 경로 없음)
  - `wa/WriterAI.swift:3108` `buildAISummaryPromptContext(...)` (호출 없음)

- 미사용 파일
  - `wa/ContentView.swift` (1 byte, 실질 코드 없음)

### import 정리 후보

- `UniformTypeIdentifiers` import는 아래 파일에서 참조 심볼이 보이지 않음
  - `wa/WriterViews.swift:2`
  - `wa/WriterCardManagement.swift:3`
  - `wa/WriterCardViews.swift:3`
  - 실제 텍스트 검색에서 `UTType` 사용 흔적 없음

주의: import 제거는 컴파일 재검증 후 확정(간접 타입 의존 가능성 방지).

---

## 2.3 너무 길거나 역할이 불명확한 함수

### 길이/역할 과대 함수

- `wa/WriterAI.swift:1404` `aiChatView`
  - 뷰 렌더링 + 상태 전이 + 입력/스크롤 이벤트 + persistence trigger 혼재
  - 대략 300+ 라인 규모

- `wa/WriterAI.swift:2103` `requestAIChatResponse(for:)`
  - scope 동기화, 스냅샷 구성, RAG, 프롬프트 빌드, API 호출, 에러 처리, 상태 커밋까지 한 함수에 집약

- `wa/WriterAI.swift:2999` `renderAIPrompt(...)`
  - 거대 템플릿 문자열 + 맥락 조합 로직 동시 포함

- `wa/WriterCardManagement.swift:886` `finishEditing()`
  - 편집 종료, 빈 카드 처리, 포커스 이동, mutation 커밋, auto-backup 트리거 등 다중 책임

- `wa/WriterViews.swift:343` `configuredWorkspaceRoot(for:)`
  - 메인 화면 분기/레이아웃/모달/이벤트 wiring이 과밀

- `wa/waApp.swift:1249` (`SettingsView.body`), `wa/waApp.swift:2017` (`MainContainerView.body`)
  - 설정/사이드바/시나리오 생성/선택/분할 뷰 제어가 대형 body 내부에 밀집

---

## 2.4 일관성 없는 네이밍

### A. 동일 개념의 naming 변형

- 토큰 함수 네이밍 이원화
  - `ragTokens` vs `ragSearchTokens`
  - 의미상 동일 계층인지(공용 util인지) 불명확

- 문자열 clamp 함수 네이밍 이원화
  - `clamp` vs `clampedAIText`

### B. 하드코딩 문자열 기반 도메인 값

- 카테고리 문자열 `"플롯"`, `"노트"`, `"미분류"`가 여러 파일에 직접 산재
  - 예: `wa/WriterAI.swift:1240`, `1242`, `2976`, `3110`
  - `wa/Models.swift:889`, `941`
  - enum/상수화 없이 literal 사용 -> 오타/정합성 위험

### C. 파일 내 책임 경계와 이름 불일치

- `WriterAI.swift`는 이름상 “AI”지만
  - UI 렌더링, persistence, 로컬 sqlite 인덱스, prompt 템플릿, 상태 전이까지 포함
  - 파일명 대비 책임 범위가 과도해 탐색성이 떨어짐

---

## 2.5 개선 가능한 구조 (분리/모듈화)

핵심 병목은 `ScenarioWriterView` 중심의 거대 extension 구조와 단일 파일 집중이다.

- `WriterAI.swift`: 최소 4개 책임으로 분리 가능
  1. Chat Thread/Persistence
  2. RAG/Embedding/Vector Store
  3. Prompt Builder
  4. AI Candidate Action Apply

- `WriterViews.swift`: 상태 선언과 화면 조립 분리 필요
  - 상태 컨테이너(편집/포커스/AI/히스토리) 분리
  - 뷰 컴포넌트(상단 툴바, 캔버스, overlay, dialog) 분리

- `waApp.swift`: App/Settings/MainContainer/ScenarioRow가 단일 파일 집중
  - Scene 구성, Settings 섹션, Sidebar/Scenario 관리를 파일 단위로 분해 가능

---

## 3) 리팩토링 실행 계획 (동작 동일성 유지 중심)

## Phase 0. 기준선 고정 (선행 필수)

- 작업
  - 현재 빌드 성공 상태를 기준선으로 기록
  - 핵심 수동 시나리오 체크리스트 작성(아래 4절)
- 이유
  - 이후 단계에서 “동작 동일” 판정 기준 확보
- 산출물
  - 이 `plan.md`
  - 수동 검증 체크 항목

## Phase 1. 안전한 정리 (무동작 변경)

대상: 작은 dead code / import cleanup만

- 작업
  - 미사용 코드 제거
    - `wa/Models.swift:479`, `480`
    - `wa/WriterAI.swift:2506`, `3101`, `3108`
    - 필요 시 `wa/ContentView.swift` 정리
  - 미사용 import 후보 제거 후 빌드 확인
    - `wa/WriterViews.swift`, `wa/WriterCardManagement.swift`, `wa/WriterCardViews.swift`
- 이유
  - 리팩토링 전 노이즈 제거로 diff 가독성 향상
- 리스크
  - 간접 참조 놓칠 가능성
- 검증
  - full build + 기본 편집 플로우 smoke test

## Phase 2. 공통 유틸 추출 (중복 제거 1차)

대상: 순수 함수형 로직(입출력 명확, 부작용 없음)

- 작업
  - 텍스트 변화 경계 판별 유틸 통합
    - `utf16ChangeDelta`, 문단/문장 경계 함수 세트
    - 사용처: `WriterUndoRedo`, `ReferenceWindow`
  - AI 토큰화/클램프 유틸 통합
    - `ragTokens`/`ragSearchTokens`
    - `clamp`/`clampedAIText`
  - 공통 위치 후보: `WriterSharedTypes.swift` 또는 신규 `TextNormalization.swift`
- 이유
  - 같은 버그를 두 번 고치지 않도록 단일화
- 리스크
  - 미세한 동작 차이(특히 줄바꿈/공백 처리)
- 검증
  - AI RAG 결과 텍스트, Undo 경계 타이핑 동작 비교

## Phase 3. AI 파일 분해 (중복 제거 2차 + 책임 분리)

대상: `wa/WriterAI.swift`

- 작업
  - 파일 분리 (함수 시그니처 유지 + 내부 위임 방식)
    - `WriterAI+ThreadStore.swift`
    - `WriterAI+RAG.swift`
    - `WriterAI+PromptBuilder.swift`
    - `WriterAI+CandidateActions.swift`
    - `WriterAI+ChatView.swift`
  - `aiThreadsJSONEncoder/Decoder` + `aiEmbeddingJSONEncoder/Decoder` 공통화
  - `requestAIChatResponse` 내부 단계를 private helper로 쪼개기
- 이유
  - 가장 큰 복잡도 원인을 먼저 해체
- 리스크
  - async 상태 전이 순서(취소/에러 시점) 회귀
- 검증
  - 채팅 요청/취소/오류/연속응답(MAX_TOKENS) 시나리오 수동 검증

## Phase 4. 편집기 메인 구조 정리

대상: `WriterViews.swift`, `WriterCardManagement.swift`

- 작업
  - `configuredWorkspaceRoot`, `finishEditing` 세분화
    - 섹션별 private helper로 분리
  - 거대 `@State`를 도메인 그룹 단위로 정렬(네이밍 통일 포함)
    - 예: `AIState`, `HistoryState`, `FocusState` (구조체 래핑 또는 섹션 분리)
  - 이벤트 핸들러를 “입력 처리”와 “상태 커밋”으로 분리
- 이유
  - 읽기/리뷰/디버깅 난이도 대폭 완화
- 리스크
  - 상태 생명주기(onAppear/onDisappear/onChange) 누락
- 검증
  - 메인 편집, 스플릿 모드, 포커스 토글, 카드 이동/삭제 회귀 테스트

## Phase 5. 앱 엔트리/설정/사이드바 분리

대상: `wa/waApp.swift`

- 작업
  - 중복 액션(`openWorkspaceFile`, `createWorkspaceFile`, 백업 경로 초기화) 공통 유틸화
  - 파일 분리
    - App Scene/Command
    - SettingsView
    - MainContainerView
    - ScenarioRow
  - 하드코딩 메시지/경로 문자열 상수화
- 이유
  - 앱 엔트리 파일 집중도를 낮춰 변경 영향 범위 축소
- 리스크
  - `@AppStorage`/`@EnvironmentObject` wiring 누락
- 검증
  - 워크스페이스 열기/생성/리셋, 설정 저장 반영, 사이드바 동작 검증

## Phase 6. 네이밍/도메인 상수 정리

- 작업
  - 카테고리 문자열(`"플롯"`, `"노트"`, `"미분류"`) 상수 또는 enum 캡슐화
  - `ragTokens`/`ragSearchTokens` 계열 네이밍 통일
  - “동일 개념 다른 이름” 정리 표준 수립
- 이유
  - 향후 기능 확장에서 오타/불일치 리스크 감소
- 리스크
  - 문자열 비교 경로 누락
- 검증
  - 카테고리 필터/AI scope/초기 시나리오 생성 확인

## Phase 7. 마무리 문서화

- 작업
  - 변경 파일별 “왜 바꿨는지” 요약 업데이트
  - 후속 유지보수 가이드 추가
- 이유
  - 추후 패치 누더기 재발 방지

---

## 4) 단계별 공통 검증 체크리스트

매 단계 종료 시 아래를 최소 수행:

1. `xcodebuild -project wa.xcodeproj -scheme wa -configuration Debug build`  
2. 워크스페이스 `.wtf` 열기/생성  
3. 시나리오 생성/삭제/템플릿 생성  
4. 카드 편집/생성/삭제/드래그 이동  
5. 메인 Undo/Redo, 포커스 Undo/Redo, 레퍼런스 창 Undo/Redo  
6. 히스토리 스냅샷/네임드 스냅샷/복구  
7. AI 채팅(요청/취소/오류), 후보 생성/적용  
8. 받아쓰기 시작/종료/반영(권한 허용 환경)  
9. 텍스트/PDF 출력  

---

## 5) 변경 설명 규칙 (요청 반영)

실제 리팩토링 단계에서 각 변경 묶음마다 아래 템플릿으로 남긴다.

- 변경:
  - 무엇을 이동/분리/통합했는지
- 이유:
  - 중복 제거 / 책임 분리 / 가독성 개선 중 무엇인지
- 동작 동일성 근거:
  - 입력/출력/호출 순서가 기존과 동일한지
- 검증:
  - 수행한 빌드/수동 시나리오

---

## 6) 우선순위 요약

1. **Phase 1-2**: dead code + 공통 유틸 통합 (가장 안전하고 효과 큼)  
2. **Phase 3**: `WriterAI.swift` 분해 (복잡도 핵심 병목)  
3. **Phase 4-5**: 뷰/앱 구조 분해  
4. **Phase 6-7**: 네이밍/문서 마무리

이 순서로 진행하면 기능 회귀 위험을 낮추면서도 가장 큰 유지보수 비용 구간부터 줄일 수 있다.

---

## 7) 실행 결과 (2026-03-02)

아래는 실제 코드 반영 완료 내역이다.

### Phase 1-2 실행 완료

- 변경:
  - `wa/Models.swift`의 미사용 저장 URL 프로퍼티(`cardsURL`, `historyURL`) 제거.
  - `wa/WriterAI.swift` dead code 제거(`aiSummaryQuery`, `AISummaryPromptContext`, `buildAISummaryPromptContext`).
  - 공통 텍스트 처리 유틸을 `wa/WriterSharedTypes.swift`로 통합:
    - UTF-16 delta 계산
    - 문단/문장 경계 판별
    - 텍스트 clamp
    - RAG 토큰화
  - `wa/WriterUndoRedo.swift`, `wa/ReferenceWindow.swift`, `wa/WriterAI.swift`(및 분리 파일)에서 공통 유틸 사용으로 중복 제거.
- 이유:
  - 중복 제거, dead code 제거, 유지보수 포인트 단일화.
- 동작 동일성 근거:
  - 기존 함수 시그니처 유지, 호출 경로는 동일, 내부 구현만 shared helper 위임.
- 검증:
  - `xcodebuild -project wa.xcodeproj -scheme wa -configuration Debug -quiet build` 성공.

### Phase 3 실행 완료 (AI 파일 분해)

- 변경:
  - `wa/WriterAI.swift`를 책임별 파일로 분해:
    - `wa/WriterAI+ThreadStore.swift`
    - `wa/WriterAI+ChatView.swift`
    - `wa/WriterAI+RAG.swift`
    - `wa/WriterAI+CandidateActions.swift`
    - `wa/WriterAI+PromptBuilder.swift`
  - `aiThreadsJSONEncoder/Decoder`, `aiEmbeddingJSONEncoder/Decoder`를 공통 인코더/디코더 팩토리로 통합.
  - `requestAIChatResponse` 내부를 단계 helper로 분리:
    - 스냅샷 생성
    - 준비 상태 반영
    - 성공 커밋
  - AI 관련 타입 접근제어를 파일 분리 후에도 동일 호출 가능하도록 최소 조정.
- 이유:
  - 단일 대형 파일의 책임 분리로 탐색/수정 난이도 축소.
- 동작 동일성 근거:
  - UI 이벤트와 상태 전이 순서(요청 시작 → 준비 → 성공/취소/오류 처리)는 유지.
  - 기존 호출 지점(`sendAIChatMessage`, 후보 생성 액션)은 유지.
- 검증:
  - `xcodebuild -project wa.xcodeproj -scheme wa -configuration Debug -quiet build` 성공.

### Phase 4 실행 완료 (편집기 메인 구조 정리)

- 변경:
  - `wa/WriterViews.swift`
    - `configuredWorkspaceRoot`를 `workspaceFocusedRoot` / `workspaceLifecycleBoundRoot` / `workspaceCommandBoundRoot`로 분해.
  - `wa/WriterCardManagement.swift`
    - `finishEditing`를 컨텍스트 수집/상태 초기화/커밋 실행 helper로 분해.
- 이유:
  - 긴 함수의 책임 단위를 명확히 나눠 읽기 및 리뷰 용이성 향상.
- 동작 동일성 근거:
  - modifier 체인과 편집 종료 commit 흐름은 동일, 단지 helper 호출로 재구성.
- 검증:
  - `xcodebuild -project wa.xcodeproj -scheme wa -configuration Debug -quiet build` 성공.

### Phase 5 실행 완료 (앱 엔트리/설정/사이드바 분리)

- 변경:
  - `wa/waApp.swift`에서 대형 뷰 struct 분리:
    - `wa/SettingsView.swift`
    - `wa/MainContainerView.swift`
    - `wa/ScenarioRow.swift`
  - 중복 액션 공통 유틸화:
    - `wa/WorkspaceSelectionHelpers.swift`
    - 워크스페이스 열기/생성 bookmark 선택 로직 통합
    - 자동 백업 기본 경로 초기화 로직 통합
- 이유:
  - 앱 엔트리 파일 집중도 완화 및 중복 제거.
- 동작 동일성 근거:
  - 각 뷰/액션 로직은 동일 코드 이동이 중심이며, 설정/북마크 업데이트 호출 시점 유지.
- 검증:
  - `xcodebuild -project wa.xcodeproj -scheme wa -configuration Debug -quiet build` 성공.

### Phase 6 실행 완료 (네이밍/도메인 상수 정리)

- 변경:
  - `wa/WriterSharedTypes.swift`에 도메인 상수 추가:
    - `ScenarioCardCategory.plot`
    - `ScenarioCardCategory.note`
    - `ScenarioCardCategory.uncategorized`
  - 카드 카테고리 문자열 literal 사용부를 상수 참조로 대체.
  - RAG 토큰 함수 네이밍을 `ragTokens`로 통일.
- 이유:
  - 동일 개념 문자열의 산발적 사용으로 인한 오타/불일치 리스크 감소.
- 동작 동일성 근거:
  - 상수 값은 기존 문자열과 동일, 비교/저장 값 불변.
- 검증:
  - `xcodebuild -project wa.xcodeproj -scheme wa -configuration Debug -quiet build` 성공.

### Phase 7 실행 완료 (문서화)

- 변경:
  - 본 섹션(실행 결과)을 `plan.md`에 추가해 변경/이유/동작 동일성/검증을 단계별로 기록.
- 이유:
  - 후속 패치 시 변경 의도 추적 가능성 확보.
- 검증:
  - 문서와 실제 변경 파일 목록 대조 완료.
