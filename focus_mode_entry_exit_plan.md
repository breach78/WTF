# Focus Mode Entry / Exit Lightweight Plan

목표:
- 포커스 모드 진입/아웃을 더 가볍게 만든다.
- 포커스 모드 내부 스크롤/캐럿 증상 수정과는 분리해서, 진입/아웃 lifecycle 자체를 단순화한다.
- 포커스 모드 외 작업창, 포커스 모드 내부 일반 동작을 불필요하게 건드리지 않는다.

기준 문서:
- `/Users/three/app_build/wa/focus_mode_entry_exit.md`
- `/Users/three/app_build/wa/focus_scroll.md`
- `/Users/three/app_build/wa/focus_scroll_plan.md`

---

## 문제 정의

현재 포커스 모드 진입/아웃은 다음 이유로 무겁다.

1. 진입 준비가 두 층으로 나뉘어 있다.
- `toggleFocusMode() -> enterFocusMode(with:)`
- `showFocusMode.onChange -> handleShowFocusModeChange(true)`

2. 진입 후 같은 목표 카드에 대해 중복 작업이 걸린다.
- `enterFocusMode(with:)`에서 이미 `beginFocusModeEditing(...)`
- 이어서 `handleShowFocusModeChange(true)`가 다시 async로 `beginFocusModeEditing(...)`를 시도

3. 진입 직후 스크롤/캐럿 루프가 빨리 켜진다.
- key monitor
- caret monitor
- entry scroll tick
- begin-edit caret retry

4. 아웃도 `finishEditing -> showFocusMode false -> main monitor restart -> restore request`로 여러 층에 분산돼 있다.

---

## 설계 원칙

1. 진입 target 준비는 한 경로만 소유한다.
2. 진입 직후에는 같은 target card에 대해 `beginFocusModeEditing(...)`를 두 번 이상 호출하지 않는다.
3. `showFocusMode.onChange`는 모니터 전환과 후속 tick 스케줄링 위주로 남기고, 이미 끝난 진입 준비를 다시 하지 않는다.
4. 각 단계는 이전 단계가 안정화된 뒤에만 다음 단계를 건드린다.
5. 한 페이즈에서 한 가지 축만 줄인다.

---

## Phase 1

이름:
- Single Entry Ownership

목표:
- 포커스 모드 진입 시 `beginFocusModeEditing(...)` 중복 경로 제거

변경 범위:
- `/Users/three/app_build/wa/wa/WriterViews.swift`
- 필요 시 아주 작은 보조 주석만 추가

구체적 작업:
1. `handleShowFocusModeChange(true)`에서 async second `beginFocusModeEditing(...)` 경로 제거
2. 진입 후 유지할 것은 아래만 남긴다
- main monitor stop
- focus monitor start
- `focusModeEntryScrollTick += 1`
- 필요 시 `focusModeEditorCardID` fallback만 유지

안전 이유:
- 실제 진입 target 준비는 이미 `enterFocusMode(with:)`가 수행한다.
- `beginFocusModeEditing(...)`의 상태 변경은 무거운 편이고, active/editing/focus editor를 모두 다시 건드린다.
- 이 중복 제거는 scroll/caret 정책 변경보다 영향 범위가 작다.

성공 기준:
- 포커스 모드 진입이 기존처럼 동작한다.
- 진입 후 target card가 유지된다.
- 진입 직후 불필요한 second begin-editing 로그/흐름이 사라진다.

---

## Phase 2

이름:
- Deferred Caret Monitor Activation

목표:
- editable text view가 실제로 준비되기 전까지 caret ensure 파이프를 늦춘다.

구체적 작업:
1. `startFocusModeCaretMonitor()`는 observer 등록만 하고
2. 초기 `requestFocusModeCaretEnsure(...)`는 live editor ready 시점으로 이동

효과:
- 진입 직후 responder/layout race 감소
- early ensure / late correction 감소

---

## Phase 3

이름:
- Single Entry Scroll Trigger

목표:
- 포커스 모드 entry에서 카드 정렬 트리거를 하나로 줄인다.

후보:
- `focusModeCanvas(...)` `onAppear`만 남기기
- 또는 `activeCardID` change만 남기기

주의:
- 이 단계는 체감 변화가 있어 첫 단계로는 하지 않는다.

후속 상태:
- shell-retention 경로에서는 initial entry alignment가 `focusModeCanvas(...)` `onAppear`로 정리되었다
- `focusModeEntryScrollTick` state는 더 이상 사용하지 않는다

---

## Phase 4

이름:
- Exit Teardown Gate

목표:
- 포커스 모드 아웃 중 새 selection/caret 후속 작업이 다시 생기지 않게 막는다.

구체적 작업:
- 짧은 `isExitingFocusMode` gate
- exit window 동안 selection-change / fallback reveal / late caret retry suppress

진행 상태:
- 구현 완료
- 실제 구현은 `focusModeExitTeardownUntil` 시간창으로 들어갔다.
- `exitFocusMode()` 시작 시 gate를 열고
- 그 창 안에서는 selection notification, caret ensure, caret retry, fallback reveal이 더 이상 새로 동작하지 않는다.

---

## 적용 순서

1. Phase 1: 진입 중복 begin-editing 제거
2. Phase 2: 초기 caret monitor/ensure 지연
3. Phase 3: 진입 scroll trigger 단일화
4. Phase 4: exit teardown gate

---

## 이번 턴 실행 범위

이번 턴에서는 `Phase 1`만 실행한다.

---

## 진행 상태

- Phase 1 완료
- Phase 2 진행 중

Phase 2 구현 원칙:
- `startFocusModeCaretMonitor()`는 observer 등록만 한다.
- 초기 eager `requestFocusModeCaretEnsure(...)`는 제거한다.
- 첫 ensure는 live editor가 실제로 붙고 selection/programmatic caret apply가 발생한 뒤의 경로가 소유한다.
