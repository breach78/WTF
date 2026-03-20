# Focus Mode Shell Retention Plan

목표:
- 포커스 모드를 `작업창을 숨기고 나중에 복원하는 구조`에서
- `작업창 shell은 유지하고, 무거운 렌더링/편집 층만 전환하는 구조`로 옮긴다.

범위:
- 포커스 모드와 작업창의 진입/아웃 lifecycle
- 작업창 viewport / active / editing 문맥 유지
- 포커스 모드 내부 타이핑 성능은 유지

비범위:
- 포커스 모드 세부 caret/스크롤 증상 개별 수정
- 작업창 일반 카드 렌더링 리팩터링

기준 문서:
- `/Users/three/app_build/wa/focus_mode_workspace_positions.md`
- `/Users/three/app_build/wa/focus_mode_entry_exit.md`
- `/Users/three/app_build/wa/focus_scroll.md`

---

## 왜 구조를 바꾸는가

현재 구조는:
- `showFocusMode = true`
- 메인 작업창 브랜치를 화면에서 내리고
- 포커스 모드 브랜치를 띄운 뒤
- 진입 전 snapshot으로 작업창 위치를 기억하고
- 아웃 시 snapshot으로 다시 복원한다

이 방식의 장점:
- 포커스 모드 타이핑 성능을 보호하기 쉽다
- 메인 작업창의 무거운 card tree를 focus mode 동안 직접 안 돌릴 수 있다

하지만 단점:
- 진입/아웃이 `뷰 전환`이 아니라 `상태 재구성`이 된다
- horizontal restore, vertical viewport restore, active/editing/caret restore가 다 분리된다
- retry / late correction / restore race가 계속 생긴다

더 나은 목표 구조는:
- 작업창 shell은 계속 살아 있게 두고
- 포커스 모드 진입 시 무거운 main canvas content만 inert/frozen 상태로 전환
- focus mode editor layer만 위에 활성화

즉 핵심은:
- `restore-driven mode switch`에서
- `retained-shell mode switch`로 바꾸는 것이다

---

## 설계 원칙

1. 작업창의 위치 문맥은 하나의 snapshot/state owner가 가진다.
2. 진입/아웃은 가능한 한 `상태 전환`이어야지 `복원 replay`가 아니어야 한다.
3. 포커스 모드 타이핑 성능 때문에 main workspace의 무거운 content는 그대로 live editing 상태로 유지하지 않는다.
4. shell과 heavy content를 분리한다.
5. 각 페이즈는 화면 동작을 크게 바꾸지 않는 순서로 진행한다.

---

## 목표 구조

최종적으로는 세 층으로 나눈다.

### 1. Workspace Shell

항상 유지되는 것:
- main canvas horizontal/vertical viewport owner
- active/editing identity
- relation/selection context
- persistence bridge

이 층은 포커스 모드 중에도 살아 있다.

### 2. Main Workspace Content

포커스 모드가 아닐 때만 fully active:
- actual main canvas card rendering
- main editor surfaces
- heavy column/card rendering

포커스 모드 중에는:
- 비활성 또는 frozen placeholder

### 3. Focus Mode Layer

포커스 모드에서만 활성:
- focused column cards
- focus editor
- focus search
- focus caret/scroll authority

---

## Phase 1

이름:
- Entry Workspace Snapshot Consolidation

목표:
- 포커스 모드 진입 직전 작업창 문맥을 흩어진 state가 아니라 한 snapshot으로 모은다

이유:
- 현재는
  - `focusModeEntryMainCanvasVisibleLevel`
  - `focusModeEntryMainCanvasHorizontalOffset`
  - `mainColumnViewportOffsetByKey`
  - `activeCardID / editingCardID`
  가 서로 따로 놀고 있다
- 이후 shell retention으로 가려면 entry context의 단일 owner가 먼저 필요하다

실행 내용:
- `FocusModeWorkspaceSnapshot` 도입
- 진입 시:
  - active/editing/selection
  - visible main-canvas level
  - main-canvas horizontal offset
  - per-column viewport offsets
  를 한 번에 캡처
- 아웃 시:
  - horizontal/vertical restore가 이 snapshot을 사용
- focus mode 중 viewport persistence도 이 snapshot의 horizontal offset을 참조

안전성:
- 화면 구조는 아직 바꾸지 않는다
- 진입/아웃의 observable mode switch 방식도 유지한다
- 상태 소유권만 정리한다

진행 상태:
- 완료

적용 파일:
- `/Users/three/app_build/wa/wa/WriterSharedTypes.swift`
- `/Users/three/app_build/wa/wa/WriterViews.swift`
- `/Users/three/app_build/wa/wa/WriterCardManagement.swift`
- `/Users/three/app_build/wa/wa/WriterFocusMode.swift`

---

## Phase 2

이름:
- Presentation Phase State Machine

목표:
- `showFocusMode` 단일 Bool 대신
- `entering / active / exiting / inactive` 성격의 presentation phase를 도입한다

효과:
- monitor start/stop
- key/caret authority 전환
- background switch
- restore trigger
를 모두 명시적 phase transition에 걸 수 있다

안전 포인트:
- rendering branch는 아직 그대로 둘 수 있다
- 우선 lifecycle 소유권만 정리한다

실행 내용:
- `FocusModePresentationPhase` 도입
- 진입 시작 시 `.entering`
- 진입 onChange 후 초기 준비가 끝나면 `.active`
- 아웃 시작 시 `.exiting`
- exit teardown window가 끝나면 `.inactive`

진행 상태:
- 완료

적용 파일:
- `/Users/three/app_build/wa/wa/WriterSharedTypes.swift`
- `/Users/three/app_build/wa/wa/WriterViews.swift`
- `/Users/three/app_build/wa/wa/WriterFocusMode.swift`

---

## Phase 3

이름:
- Retained Main Workspace Shell

목표:
- 포커스 모드 중에도 main workspace shell을 unmount하지 않는다

구체적 방향:
- `primaryWorkspaceColumn(...)` 안에서
  - shell은 계속 유지
  - focus mode layer를 위에 올림
- main workspace content는
  - focus mode 동안 hit-testing off
  - 필요 시 visual opacity/frozen snapshot 처리

기대 효과:
- horizontal/vertical restore replay 필요 감소
- focus exit 시 “어디로 돌아갈지”가 아니라 “원래 있던 shell을 다시 활성화”가 됨

주의:
- heavy main content를 그대로 live로 두면 타이핑 성능이 무거워질 수 있다
- 그래서 shell과 content를 분리해서 content만 inert 처리해야 한다

실행 내용:
- `primaryWorkspaceColumn(...)`에서 `mainCanvasWithOptionalZoom(...)`를 항상 mounted 상태로 유지
- focus mode 동안 main canvas는:
  - `opacity(0)`
  - `allowsHitTesting(false)`
  - `accessibilityHidden(true)`
- `focusModeCanvas(...)`는 그 위에 overlay
- trailing panel / toolbar visibility 정책은 기존 유지

진행 상태:
- 완료

현재 상태 해석:
- shell retention은 들어갔다
- 하지만 heavy content는 아직 truly frozen placeholder로 분리되지 않았다
- exit restore replay도 아직 남아 있다
- 따라서 Phase 3은 `retained shell 1차` 완료 상태다

적용 파일:
- `/Users/three/app_build/wa/wa/WriterViews.swift`
- `/Users/three/app_build/wa/focus_mode_workspace_positions.md`
- `/Users/three/app_build/wa/focus_mode_entry_exit.md`

---

## Phase 4

이름:
- Exit Restore Simplification

목표:
- focus exit에서 semantic restore replay를 줄이고
- retained shell reactivation을 기본 경로로 만든다

바뀌는 것:
- `requestMainCanvasRestoreForFocusExit(...)`
- `requestMainCanvasViewportRestoreForFocusExit(...)`

최종 방향:
- replay는 fallback
- shell reactivation이 주 경로

실행 내용:
- focus exit 시 먼저 retained shell 재사용 가능 여부를 검사
- 조건:
  - main canvas horizontal scroll view가 살아 있음
  - 필요한 vertical viewport scroll views도 살아 있음
- 이 조건이 맞으면:
  - `requestMainCanvasRestoreForFocusExit(...)`
  - `requestMainCanvasViewportRestoreForFocusExit(...)`
  를 호출하지 않음
- 대신 pending restore와 pending main-column focus work만 정리
- scroll-view attachment가 부족할 때만 legacy restore replay를 fallback으로 사용

진행 상태:
- 완료

적용 파일:
- `/Users/three/app_build/wa/wa/WriterCardManagement.swift`
- `/Users/three/app_build/wa/wa/WriterViews.swift`

---

## Phase 5

이름:
- Legacy Entry/Exit State Retirement

목표:
- 예전 복원 중심 경로를 정리한다

정리 후보:
- 중복 restore retry
- old entry snapshot fields
- replay-only helper
- transition 중 late correction 보정층

실행 내용:
- `focusModeEntryScrollTick` 제거
- entry canvas의 첫 정렬은 `focusModeCanvas(...)`의 `onAppear`가 직접 담당
- retained main-workspace shell 이후 불필요해진
  `focusModeEntryWorkspaceSnapshot.mainCanvasHorizontalOffset` 기반 일반 persistence fallback 제거
- `restoreMainCanvasHorizontalViewport(...)`가 더 이상 focus-mode entry snapshot lifecycle을 소유하지 않도록 정리

진행 상태:
- 완료

적용 파일:
- `/Users/three/app_build/wa/wa/WriterViews.swift`
- `/Users/three/app_build/wa/wa/WriterFocusMode.swift`
- `/Users/three/app_build/wa/wa/WriterCardManagement.swift`
- `/Users/three/app_build/wa/focus_mode_entry_exit.md`
- `/Users/three/app_build/wa/focus_mode_workspace_positions.md`
- `/Users/three/app_build/wa/focus_scroll.md`

---

## 추천 진행 순서

1. Phase 1: entry snapshot 통합
2. Phase 2: presentation phase 도입
3. Phase 3: retained shell 도입
4. Phase 4: exit restore 단순화
5. Phase 5: legacy 경로 제거

---

## 현재 결론

최선의 구조는 `포커스 모드가 메인 작업창을 완전히 치우고 나중에 복원하는 구조`가 아니다.

더 나은 구조는:
- 작업창 shell은 유지
- heavy content/editor만 비활성화
- focus mode layer만 전환

이번 단계까지는 그 구조로 가기 위한 가장 안전한 첫 단계, 즉 `entry workspace snapshot consolidation`까지 반영된 상태다.
