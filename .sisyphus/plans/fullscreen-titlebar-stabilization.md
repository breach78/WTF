# Fullscreen Titlebar Stabilization

## TL;DR
> **Summary**: macOS 창 크롬(AppKit)과 에디터 상단 overlay(SwiftUI)의 전환 레이스를 분리 진단하고, 단일 변경-단일 검증 순서로 상단 흰 바/아이콘 Y-드리프트를 안정화한다.
> **Deliverables**:
> - 재현/증거 수집 자동화(전환 스트레스 + 스크린샷/윈도우 상태 로그)
> - main/reference window chrome 정책 비대칭 제거 또는 명시적 고정
> - `NavigationSplitView` top chrome/safe-area와 `workspaceTopToolbar` 앵커의 충돌 해소
> - 기능 영향 보고서(변경 가능성/실제 변경 내역/회귀 결과)
> **Effort**: Large
> **Parallel**: YES - 3 waves
> **Critical Path**: Task 1 -> Task 2 -> Task 3 -> Task 4 -> Task 7 -> Task 9 -> Task 10

## Context
### Original Request
- 지금까지 시도한 방법으로는 증상이 줄기만 하고 근본 해결은 안 됨.
- 최소 코드 변경 원칙 유지.
- 전체 코드를 다시 보되, 이번에는 계획을 길게 세우고 순서대로 해결.
- 기능 변경이 생길 가능성/실제 변경은 반드시 보고.

### Interview Summary
- 확정 요구사항:
  - 상단 흰 바 0화(전체화면/복귀/사이드바 토글/앱 전환 포함)
  - 우측 상단 아이콘은 상단에 바짝 붙고(이상 상태의 내려옴 금지), 잘림/반클립 금지
  - 다른 기능(편집/AI/히스토리/레퍼런스 창 핵심 동작) 비변경
- 작업 원칙:
  - 원인 추정 난사 금지, 단계별 게이트 기반 수리
  - 단계마다 실패 시 롤백 기준 명시
- 테스트 기본값(무응답 가정):
  - `tests-after` + 자동 실행 가능한 전이 스트레스 검증(사람 수동 판정 제외)

### Metis Review (gaps addressed)
- 반영한 가드레일:
  - `configureWindows()` 전역 재적용 과호출로 레이스 증폭 가능 -> 이벤트 coalescing/대상 윈도우 범위 엄격화
  - main vs reference window chrome 정책 비대칭을 명시적으로 점검
  - `NavigationSplitView`/safe-area와 overlay toolbar 문제를 분리해 순차 검증
- 반영한 리스크 통제:
  - 각 단계는 단일 가설만 변경하고 즉시 자동 검증
  - 실패 시 바로 직전 단계로 롤백, 다음 가설로 이동

### Plan Revision (2026-02-26, screenshot sequence)
- 관찰된 순서(사용자 보고):
  - fullscreen 시작 + 시나리오 선택 직후 white bar 발생
  - 앱 비활성/재활성 후 white bar 소거
  - fullscreen exit/re-enter 후 정상
  - split 진입 시 white bar 순간 노출 후 소거 + 우측 상단 아이콘 half-clip
  - fullscreen exit/re-enter 후 다시 정상
- 해석:
  - 고정 레이아웃 결함이 아니라, **첫 전환 시점의 AppKit window chrome 재구성 완료 전/후 레이스** 가능성이 가장 높음.
  - `configureWindowsOnNextRunLoop` coalescing만으로는 "전환 완료 이후" apply가 보장되지 않음(취소/병합으로 late apply 누락 가능).
  - SwiftUI overlay(`workspaceTopToolbar`)는 첫 프레임에서 `safeAreaInsets.top`이 과도/과소로 측정되면 아이콘 클립이 발생하고, 이후 재진입에서 self-heal.
- 수정된 우선순위:
  1. 전환 완료 보장 apply 경로 추가(이벤트 coalescing과 분리)
  2. apply 대상을 source main window 중심으로 제한
  3. toolbar Y 앵커를 "측정값 기반"으로 고정(첫 프레임 보호 클램프)
  4. 기존 전역 coalescer는 보조 경로로 유지

## Work Objectives
### Core Objective
- main window에서 상단 흰 바를 제거하고, 우측 상단 아이콘 클러스터를 전환 상태와 무관하게 고정 Y로 유지한다.

### Deliverables
- 전이 스트레스 재현 하네스 및 증거 산출 스크립트
- 창 크롬 정책 정합화 패치(최소 변경)
- 상단 overlay 앵커/안전영역 정합화 패치(최소 변경)
- 기능 영향/회귀 결과 보고서

### Definition of Done (verifiable conditions with commands)
- `xcodebuild -project "wa.xcodeproj" -scheme "wa" -configuration Debug -destination 'platform=macOS' build` 결과 `** BUILD SUCCEEDED **`
- 전이 스트레스 30회 실행에서 흰 바 탐지 실패 0회
- 전이 스트레스 30회 실행에서 아이콘 Y 오차(기준 프레임 대비) 임계치 초과 0회
- reference window 열림/닫힘 상태 모두에서 main window 상단 흰 바 0회
- 기능 영향 점검 스크립트에서 주요 기능 경로 이상 없음(시나리오 선택, 카드 편집 입력, 우측 패널 토글, AI 패널 토글)

### Must Have
- 변경 파일은 우선 `wa/waApp.swift`, `wa/WriterViews.swift`로 제한
- 필요 시에만 `wa/ReferenceWindow.swift` 수정
- 단계별 증거 파일 생성(`.sisyphus/evidence/`)
- 기능 변화 가능성/발생 시 보고 항목 생성

### Must NOT Have (guardrails, AI slop patterns, scope boundaries)
- `window.styleMask.remove(.titled)` 같은 파괴적 창 동작 변경을 기본 해법으로 채택 금지
- 대규모 UI 리팩터링(네이티브 toolbar 전면 교체, 화면 구조 전면 변경) 금지
- 증거 없는 추측성 변경 다중 동시 적용 금지
- 편집/AI/히스토리/내보내기 로직 변경 금지

## Verification Strategy
> ZERO HUMAN INTERVENTION — all verification is agent-executed.
- Test decision: tests-after (현재 test scheme 미구성)
- QA policy: Every task has agent-executed scenarios
- Evidence: `.sisyphus/evidence/task-{N}-{slug}.{ext}`

## Execution Strategy
### Parallel Execution Waves
> Target: 5-8 tasks per wave. <3 per wave (except final) = under-splitting.
> Extract shared dependencies as Wave-1 tasks for max parallelism.

Wave 1: 재현 고정/관측/범위 축소
- 재현 하네스 구축
- 창 크롬 상태 로깅 추가
- overlay 좌표/안전영역 계측 추가
- reference/main 창 경로 분리 검증
- 기능 영향 기준선 수집

Wave 2: 단일 가설 패치 + 단계별 롤백
- chrome 적용 타이밍 coalescing
- window 대상 범위 제한(키/메인/식별자)
- split/titlebar 상단 배경 소스 제거
- overlay Y-앵커 안정화
- reference window 정책 동기화(필요 시)

Wave 3: 경계 케이스 봉합 + 보고
- fullscreen/앱 전환/사이드바 조합 회귀
- light/dark/system appearance 회귀
- 기능 영향 diff 보고
- 증거 정리 및 완료 판정
- 최종 최소 패치 정리

### Dependency Matrix (full, all tasks)
| Task | Depends On | Blocks |
|---|---|---|
| 1 | - | 2,3,4,5 |
| 2 | 1 | 6,7,8,9 |
| 3 | 1 | 8 |
| 4 | 1 | 9 |
| 5 | 1 | 10 |
| 6 | 2 | 10 |
| 7 | 2 | 10 |
| 8 | 2,3 | 10 |
| 9 | 2,4 | 10 |
| 10 | 5,6,7,8,9 | Final Verification |

### Agent Dispatch Summary (wave → task count → categories)
- Wave 1 -> 5 tasks -> deep(2), unspecified-high(2), quick(1)
- Wave 2 -> 5 tasks -> deep(2), quick(3)
- Wave 3 -> 5 tasks -> unspecified-high(3), writing(1), deep(1)

## TODOs
> Implementation + Test = ONE task. Never separate.
> EVERY task MUST have: Agent Profile + Parallelization + QA Scenarios.

- [ ] 1. 재현 하네스 고정 (전이 30회 루프)

  **What to do**: `scripts/ui_stress_titlebar.sh`를 추가해 Debug 앱 실행 후 전체화면 진입/해제, 앱 비활성-재활성, 사이드바 토글을 30회 반복하고 각 단계 스크린샷을 저장한다.
  **Must NOT do**: 앱 기능 코드를 먼저 수정하지 않는다. 하네스 단계에서 UI 로직 변경 금지.

  **Recommended Agent Profile**:
  - Category: `unspecified-high` — Reason: macOS UI 자동화 스크립트 설계가 필요함
  - Skills: [`karpathy-guidelines`] — 최소 변경/검증 우선 원칙 유지
  - Omitted: [`playwright`] — 데스크톱 네이티브 앱이라 브라우저 자동화 부적합

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: 2,3,4,5 | Blocked By: -

  **References** (executor has NO interview context — be exhaustive):
  - Pattern: `wa/waApp.swift:108` — fullscreen 진입 이벤트
  - Pattern: `wa/waApp.swift:111` — fullscreen 해제 이벤트
  - Pattern: `wa/waApp.swift:123` — 앱 활성화 이벤트
  - Pattern: `wa/waApp.swift:1596` — `NavigationSplitView` 기반 메인 레이아웃

  **Acceptance Criteria** (agent-executable only):
  - [ ] `bash scripts/ui_stress_titlebar.sh --iterations 30` 종료코드 0
  - [ ] `.sisyphus/evidence/task-1-repro/`에 최소 60개 스크린샷 생성

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```bash
  Scenario: Happy path stress loop runs end-to-end
    Tool: Bash
    Steps: Build Debug app -> run ui_stress_titlebar.sh 30 iterations -> capture screenshots per transition
    Expected: script exit code 0; screenshot count >= 60; no script-time crash
    Evidence: .sisyphus/evidence/task-1-repro/happy.log

  Scenario: Accessibility permission missing
    Tool: Bash
    Steps: Run same script on environment without AX permission
    Expected: script exits non-zero with explicit actionable error message, not silent pass
    Evidence: .sisyphus/evidence/task-1-repro/error.log
  ```

  **Commit**: YES | Message: `chore(qa): add fullscreen titlebar stress harness` | Files: `scripts/ui_stress_titlebar.sh`, `.sisyphus/evidence/task-1-repro/*`

- [ ] 2. 창 크롬 상태 계측 추가 (DEBUG 한정)

  **What to do**: `configureWindows()`와 전환 이벤트 경로에서 window id/styleMask/titlebar/toolbar/contentLayoutRect/safe-area를 로그로 남기는 DEBUG 계측을 추가한다.
  **Must NOT do**: 릴리즈 빌드 로깅 추가 금지. 런타임 동작을 변경하는 로직 삽입 금지.

  **Recommended Agent Profile**:
  - Category: `quick` — Reason: 단일 파일에 제한된 진단 코드
  - Skills: [`karpathy-guidelines`] — 진단과 기능 변경 분리
  - Omitted: [`frontend-ui-ux`] — 시각 디자인 작업 아님

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: 6,7,8,9 | Blocked By: 1

  **References** (executor has NO interview context — be exhaustive):
  - Pattern: `wa/waApp.swift:341` — `configureWindows()`
  - Pattern: `wa/waApp.swift:350` — `titleVisibility`
  - Pattern: `wa/waApp.swift:352` — `fullSizeContentView`
  - Pattern: `wa/waApp.swift:406` — 재적용 스케줄러

  **Acceptance Criteria** (agent-executable only):
  - [ ] DEBUG 빌드 실행 시 전환 1회당 최소 1개 chrome-state 로그 생성
  - [ ] Release 빌드에서는 해당 로그 문자열이 0회

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```bash
  Scenario: Happy path DEBUG logging visibility
    Tool: Bash
    Steps: Run Debug app with stress harness; grep logs for chrome-state marker
    Expected: marker appears for fullscreen enter/exit + app active transitions
    Evidence: .sisyphus/evidence/task-2-window-telemetry/happy.log

  Scenario: Failure path release leakage check
    Tool: Bash
    Steps: Build Release app; run minimal launch; search for chrome-state marker
    Expected: zero matches; exit code indicates pass
    Evidence: .sisyphus/evidence/task-2-window-telemetry/error.log
  ```

  **Commit**: YES | Message: `chore(debug): add window chrome telemetry markers` | Files: `wa/waApp.swift`

- [ ] 3. overlay 좌표/상단 안전영역 계측

  **What to do**: `workspaceTopToolbar`의 실제 top Y와 safe-area top inset을 DEBUG로 수집해 드리프트를 수치화한다.
  **Must NOT do**: 버튼 동작/아이콘 기능 변경 금지. 시각 스타일 변경 금지.

  **Recommended Agent Profile**:
  - Category: `unspecified-high` — Reason: SwiftUI geometry/preference 계측 필요
  - Skills: [`karpathy-guidelines`] — 계측 코드 최소화
  - Omitted: [`artistry`] — 비정형 실험 불필요

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 8 | Blocked By: 1

  **References** (executor has NO interview context — be exhaustive):
  - Pattern: `wa/WriterViews.swift:603` — 상단 toolbar 주입 지점
  - Pattern: `wa/WriterViews.swift:651` — `workspaceTopToolbar`
  - Pattern: `wa/WriterViews.swift:703` — toolbar safe-area 정책
  - Pattern: `wa/WriterViews.swift:719` — 버튼 top padding

  **Acceptance Criteria** (agent-executable only):
  - [ ] 전이 루프에서 toolbarY와 safeTop 수치가 단계별로 로그에 기록됨
  - [ ] 드리프트 임계(예: 기준 대비 >1pt) 탐지 여부가 pass/fail로 산출됨

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```bash
  Scenario: Happy path geometry telemetry
    Tool: Bash
    Steps: Run Debug app stress loop with geometry telemetry enabled
    Expected: each transition emits toolbarY/safeTop; parser outputs drift summary
    Evidence: .sisyphus/evidence/task-3-overlay-telemetry/happy.log

  Scenario: Failure path telemetry disabled guard
    Tool: Bash
    Steps: Launch app with telemetry flag off
    Expected: no telemetry markers emitted; parser reports disabled state explicitly
    Evidence: .sisyphus/evidence/task-3-overlay-telemetry/error.log
  ```

  **Commit**: NO | Message: `n/a` | Files: `wa/WriterViews.swift`

- [ ] 4. main/reference 창 경로 비대칭 검증

  **What to do**: main window와 reference window를 식별해 상단 바 발생 창을 분리 판정하고, 필요 시 reference 경로가 main에 간섭하는지 확인한다.
  **Must NOT do**: reference 창 기능(플로팅/고정폭/전용 용도) 자체를 변경하지 않는다.

  **Recommended Agent Profile**:
  - Category: `deep` — Reason: 다중 window lifecycle 상호작용 분석
  - Skills: [`karpathy-guidelines`] — 원인 분리 우선
  - Omitted: [`frontend-ui-ux`] — 레이아웃 미세 스타일링 단계 아님

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 9 | Blocked By: 1

  **References** (executor has NO interview context — be exhaustive):
  - Pattern: `wa/waApp.swift:347` — reference window 제외 로직
  - Pattern: `wa/waApp.swift:1825` — `openWindow(id: ReferenceWindowConstants.windowID)` 호출 경로
  - Pattern: `wa/ReferenceWindow.swift:704` — `FloatingReferenceWindowAccessor`
  - Pattern: `wa/ReferenceWindow.swift:715` — `.fullScreenAuxiliary`

  **Acceptance Criteria** (agent-executable only):
  - [ ] 증상 발생 시 어떤 window identifier에서 발생하는지 로그로 확정
  - [ ] reference window 열림/닫힘 각각에 대한 증상 유무 매트릭스 산출

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```bash
  Scenario: Happy path window attribution
    Tool: Bash
    Steps: Run stress harness once with reference closed, once open; collect window identifiers with telemetry
    Expected: symptom attribution report maps strip occurrence to specific window IDs
    Evidence: .sisyphus/evidence/task-4-window-attribution/happy.json

  Scenario: Failure path missing identifier handling
    Tool: Bash
    Steps: Simulate/observe window without identifier during early lifecycle
    Expected: telemetry marks identifier as unknown but does not crash parsing pipeline
    Evidence: .sisyphus/evidence/task-4-window-attribution/error.log
  ```

  **Commit**: NO | Message: `n/a` | Files: `.sisyphus/evidence/task-4-window-attribution/*`

- [ ] 5. 기능 영향 기준선 수집

  **What to do**: 현재 동작 기준선(시나리오 선택/카드 편집/AI 패널 토글/타임라인 토글/reference 열기)을 스크립트로 실행해 변경 전 결과를 저장한다.
  **Must NOT do**: 기능 로직 변경 없이 관측만 수행.

  **Recommended Agent Profile**:
  - Category: `unspecified-high` — Reason: 회귀 기준선 자동화가 핵심
  - Skills: [`karpathy-guidelines`] — 기능 비변경 원칙 고정
  - Omitted: [`artistry`] — 창의적 접근 불필요

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 10 | Blocked By: 1

  **References** (executor has NO interview context — be exhaustive):
  - API/Type: `wa/waApp.swift:1596` — `MainContainerView` 루트
  - Pattern: `wa/WriterViews.swift:820` — AI 패널 토글
  - Pattern: `wa/WriterViews.swift:794` — 타임라인 패널 토글
  - Pattern: `wa/waApp.swift:1825` — reference 창 열기

  **Acceptance Criteria** (agent-executable only):
  - [ ] 기준선 시나리오 5종 실행 성공
  - [ ] 기준선 로그/스크린샷 세트가 `.sisyphus/evidence/task-5-baseline/`에 저장

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```bash
  Scenario: Happy path baseline capture
    Tool: Bash
    Steps: Execute scripted interactions for scenario list/select/edit/toggle panels/reference window
    Expected: all scripted checks pass and evidence artifacts generated
    Evidence: .sisyphus/evidence/task-5-baseline/happy.log

  Scenario: Failure path baseline mismatch
    Tool: Bash
    Steps: Force one interaction target to fail (missing menu command)
    Expected: runner reports specific failed step and exits non-zero
    Evidence: .sisyphus/evidence/task-5-baseline/error.log
  ```

  **Commit**: YES | Message: `chore(qa): capture pre-fix behavior baseline` | Files: `scripts/ui_baseline_checks.sh`, `.sisyphus/evidence/task-5-baseline/*`

- [ ] 6. chrome 재적용 이벤트 coalescing 도입

  **What to do**: `configureWindowsOnNextRunLoop()` 호출 폭주를 coalesce하여 동일 burst 내 중복 적용을 줄이고, 마지막 안정 시점 적용은 유지한다.
  **Must NOT do**: notification 구독 자체를 무작위 삭제하지 않는다. late pass 제거 금지.

  **Recommended Agent Profile**:
  - Category: `deep` — Reason: lifecycle race 완화 핵심 단계
  - Skills: [`karpathy-guidelines`] — 변경폭 최소 + 롤백 용이 구조
  - Omitted: [`frontend-ui-ux`] — 스타일링 단계 아님

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: 10 | Blocked By: 2

  **References** (executor has NO interview context — be exhaustive):
  - Pattern: `wa/waApp.swift:108` — fullscreen enter
  - Pattern: `wa/waApp.swift:123` — app active
  - Pattern: `wa/waApp.swift:406` — 기존 4회 지연 재적용
  - Pattern: `wa/waApp.swift:341` — 실제 chrome 적용 함수

  **Acceptance Criteria** (agent-executable only):
  - [ ] 전이 1 burst당 configureWindows 적용 횟수 감소(기준선 대비)
  - [ ] 30회 스트레스에서 흰 바 발생률이 기준선 대비 하락

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```bash
  Scenario: Happy path coalesced lifecycle
    Tool: Bash
    Steps: Run stress harness before/after patch; compare configureWindows invocation counts
    Expected: invocation count reduced without losing final stable apply event
    Evidence: .sisyphus/evidence/task-6-coalescing/happy.json

  Scenario: Failure path missed apply
    Tool: Bash
    Steps: Trigger fast fullscreen enter/exit burst and app reactivation
    Expected: if final apply missing, test fails with explicit "missed-final-apply" reason
    Evidence: .sisyphus/evidence/task-6-coalescing/error.log
  ```

  **Commit**: YES | Message: `fix(window): coalesce chrome reapply bursts` | Files: `wa/waApp.swift`

- [ ] 7. chrome 적용 대상 윈도우 범위 정밀화

  **What to do**: `NSApplication.shared.windows` 전체 스캔 대신 키/메인/identifier 기준으로 적용 대상을 축소해, 의도치 않은 window 상태 변형을 차단한다.
  **Must NOT do**: settings/reference 제외 정책을 깨지 않는다. reference 기능 정책을 임의 변경 금지.

  **Recommended Agent Profile**:
  - Category: `quick` — Reason: 조건식 정밀화 중심의 국소 변경
  - Skills: [`karpathy-guidelines`] — 영향면 축소
  - Omitted: [`artistry`] — 비정형 접근 불필요

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: 10 | Blocked By: 2

  **References** (executor has NO interview context — be exhaustive):
  - Pattern: `wa/waApp.swift:344` — 설정/보조 창 제외 조건
  - Pattern: `wa/waApp.swift:347` — reference window 제외
  - Pattern: `wa/waApp.swift:350` — chrome 속성 적용 시작 지점

  **Acceptance Criteria** (agent-executable only):
  - [ ] main window 대상에서는 chrome 속성 적용 로그 유지
  - [ ] 비대상 window에 대한 chrome 속성 write 로그 0회

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```bash
  Scenario: Happy path target scoping
    Tool: Bash
    Steps: Open main + reference + settings-like window states; run stress loop
    Expected: only intended window IDs receive chrome updates
    Evidence: .sisyphus/evidence/task-7-window-scope/happy.json

  Scenario: Failure path unintended target mutation
    Tool: Bash
    Steps: Force creation of auxiliary window; inspect telemetry for chrome writes
    Expected: any unintended write triggers test failure
    Evidence: .sisyphus/evidence/task-7-window-scope/error.log
  ```

  **Commit**: YES | Message: `fix(window): narrow chrome apply target windows` | Files: `wa/waApp.swift`

- [ ] 8. overlay top 앵커 안정화 (safe-area 충돌 제거)

  **What to do**: `workspaceTopToolbar`의 top 기준을 안전영역/컨테이너 기준 하나로 고정하고, per-button top padding 편차를 제거한다.
  **Must NOT do**: 버튼 기능/도움말/토글 로직 변경 금지.

  **Recommended Agent Profile**:
  - Category: `deep` — Reason: SwiftUI top inset 레이스와 시각 고정 동시 해결
  - Skills: [`karpathy-guidelines`] — 최소 변경으로 위치 안정화
  - Omitted: [`frontend-ui-ux`] — 디자인 재작업 아님

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: 10 | Blocked By: 2,3

  **References** (executor has NO interview context — be exhaustive):
  - Pattern: `wa/WriterViews.swift:603` — toolbar 삽입 레이어
  - Pattern: `wa/WriterViews.swift:651` — toolbar 컨테이너
  - Pattern: `wa/WriterViews.swift:703` — safe-area edges
  - Pattern: `wa/WriterViews.swift:719` — top padding (다수 버튼 동일 패턴)
  - Pattern: `wa/WriterFocusMode.swift:143` — focus mode top safe-area 무시

  **Acceptance Criteria** (agent-executable only):
  - [ ] 전이 30회에서 toolbarY 표준편차가 기준선 대비 감소
  - [ ] 아이콘 half-clip/하강 상태 탐지 0회

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```bash
  Scenario: Happy path stable top-right cluster
    Tool: Bash
    Steps: Run stress harness with overlay telemetry enabled
    Expected: toolbar cluster Y remains within threshold for all iterations
    Evidence: .sisyphus/evidence/task-8-overlay-anchor/happy.json

  Scenario: Failure path clip detection
    Tool: Bash
    Steps: Trigger sidebar open/close rapidly during fullscreen transitions
    Expected: clip detector returns zero; non-zero if any partial clipping occurs
    Evidence: .sisyphus/evidence/task-8-overlay-anchor/error.log
  ```

  **Commit**: YES | Message: `fix(toolbar): stabilize top anchor and remove drift` | Files: `wa/WriterViews.swift`, `wa/WriterFocusMode.swift`

- [ ] 9. reference window chrome 간섭 차단 (조건부)

  **What to do**: Task 4에서 reference 경로 간섭이 확인된 경우에만 reference 창의 상단 영역 정책을 main과 충돌하지 않게 최소 조정한다.
  **Must NOT do**: reference 창의 floating/폭 고정/보조 창 역할을 변경하지 않는다.

  **Recommended Agent Profile**:
  - Category: `quick` — Reason: 조건부 1~2지점 패치
  - Skills: [`karpathy-guidelines`] — 필요 시에만 변경
  - Omitted: [`artistry`] — 비정형 접근 불필요

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: 10 | Blocked By: 2,4

  **References** (executor has NO interview context — be exhaustive):
  - Pattern: `wa/ReferenceWindow.swift:704` — accessor 진입점
  - Pattern: `wa/ReferenceWindow.swift:715` — fullscreen auxiliary
  - Pattern: `wa/waApp.swift:347` — main chrome 적용 제외 정책

  **Acceptance Criteria** (agent-executable only):
  - [ ] reference open 상태에서도 main window 흰 바/아이콘 드리프트 재현 0회
  - [ ] reference 창 핵심 동작(floating, fixed width) 유지

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```bash
  Scenario: Happy path with reference window open
    Tool: Bash
    Steps: Open reference window; run full stress transitions on main window
    Expected: main window top-strip/drift detectors remain zero violations
    Evidence: .sisyphus/evidence/task-9-reference-isolation/happy.log

  Scenario: Failure path reference behavior regression
    Tool: Bash
    Steps: Verify reference window width and floating level after patch
    Expected: width remains fixed at configured value; floating level preserved
    Evidence: .sisyphus/evidence/task-9-reference-isolation/error.log
  ```

  **Commit**: YES | Message: `fix(reference-window): prevent chrome interference on main window` | Files: `wa/ReferenceWindow.swift` (if needed), `wa/waApp.swift` (if needed)

- [ ] 10. 기능 영향 리포트 + 최종 회귀 파이프라인 고정

  **What to do**: 변경 전 기준선(Task 5)과 변경 후 결과를 diff하여 기능 영향(있음/없음, 영향 범위, 완화책)을 문서화하고 CI/로컬 재검증 명령을 고정한다.
  **Must NOT do**: 영향 항목 누락/축소 보고 금지.

  **Recommended Agent Profile**:
  - Category: `writing` — Reason: 기술 보고 + 증거 정리
  - Skills: [`karpathy-guidelines`] — 사실 기반 보고
  - Omitted: [`frontend-ui-ux`] — 구현 단계 아님

  **Parallelization**: Can Parallel: NO | Wave 3 | Blocks: Final Verification | Blocked By: 5,6,7,8,9

  **References** (executor has NO interview context — be exhaustive):
  - Pattern: `.sisyphus/evidence/task-5-baseline/*` — 기준선
  - Pattern: `.sisyphus/evidence/task-6-coalescing/*` — lifecycle 개선 결과
  - Pattern: `.sisyphus/evidence/task-8-overlay-anchor/*` — 아이콘 위치 안정화 결과
  - Pattern: `.sisyphus/evidence/task-9-reference-isolation/*` — 보조창 간섭 검증

  **Acceptance Criteria** (agent-executable only):
  - [ ] `.sisyphus/evidence/titlebar-final-report.md` 생성
  - [ ] 영향 항목 표에 `none` 또는 구체 영향+완화가 명시됨
  - [ ] 재검증 명령 1세트로 동일 결과 재현됨

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```bash
  Scenario: Happy path final regression report
    Tool: Bash
    Steps: Run baseline-vs-after diff script and generate markdown report
    Expected: report includes pass/fail table and file-level change impact summary
    Evidence: .sisyphus/evidence/task-10-final-report/happy.md

  Scenario: Failure path missing evidence artifact
    Tool: Bash
    Steps: Run report generator with one required evidence file removed
    Expected: generator exits non-zero and lists missing artifact paths
    Evidence: .sisyphus/evidence/task-10-final-report/error.log
  ```

  **Commit**: YES | Message: `chore(qa): add final titlebar stabilization report` | Files: `.sisyphus/evidence/titlebar-final-report.md`, `scripts/ui_regression_diff.sh`

## Final Verification Wave (4 parallel agents, ALL must APPROVE)
- [ ] F1. Plan Compliance Audit — oracle
- [ ] F2. Code Quality Review — unspecified-high
- [ ] F3. Real Manual QA — unspecified-high (+ playwright if UI)
- [ ] F4. Scope Fidelity Check — deep

## Commit Strategy
- 단계 커밋 전략:
  - Milestone A: 관측/재현 하네스 도입
  - Milestone B: root-cause 최소 패치(핵심)
  - Milestone C: 회귀/정리
- 커밋 메시지 규칙: `fix(window): ...`, `fix(toolbar): ...`, `chore(qa): ...`

## Success Criteria
- 흰 바 재현율 0/30 cycles
- 아이콘 Y-드리프트 임계 초과 0/30 cycles
- 기능 영향 체크리스트 이상 0건
- 변경 파일 수 최소화(목표: 2~3 files)
