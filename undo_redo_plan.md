# 공통 언두/리두 설계안

## 1. 목적

이 문서의 목표는 `메인 뷰`, `포커스 모드`, `보드 뷰`가 각자 따로 노는 언두/리두가 아니라,
하나의 공통 시스템 위에서 동작하도록 정리하는 것이다.

핵심 기준:

- 사용자는 어느 뷰에서 작업했는지 의식하지 않고 `Cmd+Z`, `Cmd+Shift+Z`를 사용해야 한다.
- 저장 구조를 새로 만들지 않고 현재 `SceneCard` 트리와 세션 상태를 재사용해야 한다.
- 보드 뷰의 카드 이동, 그룹 이동, 카드/그룹 삭제, 큰 카드 편집도 같은 언두 체계에 들어가야 한다.
- 타이핑처럼 coalescing이 필요한 입력은 유지하되, 최종 undo stack은 공통이어야 한다.
- 최소 변경으로 단계적으로 이관해야 한다.

## 2. 현재 상태

현재 앱에는 이미 공통 기반이 일부 존재한다.

- `wa/WriterUndoRedo.swift`
  - `ScenarioState`
  - `captureScenarioState(...)`
  - `restoreScenarioState(...)`
  - `performUndo()`
  - `performRedo()`
- `wa/waApp.swift`
  - 메뉴의 `Undo`, `Redo`가 전역 notification으로 연결되어 있다.
- `wa/WriterViews.swift`
  - `waUndoRequested`, `waRedoRequested`를 받아 실제 undo/redo를 실행한다.

즉, 문서 상태 자체를 되돌리는 기본 엔진은 이미 있다.

하지만 현재 구조의 한계는 분명하다.

- 메인 일반 편집과 포커스 모드가 별도 stack/coalescing을 가진다.
- 보드 뷰는 카드 데이터 변경은 undo 대상이 될 수 있어도,
  `줌`, `스크롤`, `선택`, `보드 배치`, `editorDraft`, `그룹 위치` 같은 보드 세션 상태는 같은 수준으로 복원되지 않는다.
- mutation 진입점이 여러 파일에 퍼져 있어, 어떤 작업은 undo stack에 잘 들어가고 어떤 작업은 누락될 위험이 있다.
- 결과적으로 사용자가 느끼는 언두 단위가 뷰마다 조금씩 다르다.

## 3. 목표 구조

### 3-1. 핵심 원칙

언두/리두의 기준 단위는 더 이상 `문서 상태만`이 아니라 `작업 공간 상태 전체`여야 한다.

즉, 새 공통 스냅샷은 아래 둘을 함께 가져야 한다.

- 문서 상태
- 현재 사용자가 보고 있던 작업 문맥

권장 구조:

```swift
struct WorkspaceUndoSnapshot {
    let scenario: ScenarioState
    let workspace: WorkspaceViewState
}

struct WorkspaceViewState {
    let paneMode: WriterPaneMode
    let activeCardID: UUID?
    let selectedCardIDs: [UUID]
    let focusModeState: FocusUndoState?
    let indexBoardState: IndexBoardUndoState?
}
```

핵심은 `ScenarioState`를 버리는 것이 아니라, 그 위에 `view-state wrapper`를 얹는 것이다.

### 3-2. 보드 뷰에서 반드시 같이 복원할 상태

보드는 데이터만 복원해서는 사용감이 깨진다.
최소한 아래 상태는 함께 복원되어야 한다.

- `sourceParentID`, `sourceDepth`, `sourceCardIDs`
- `zoomScale`
- `scrollOffset`
- `selectedCardIDs`
- `activeCardID`
- `showsBackByCardID`
- `collapsedLaneParentIDs`
- `detachedGridPositionByCardID`
- `groupGridPositionByParentID`
- `tempStrips`
- `lastPresentedCardID`
- `pendingRevealCardID`
- 필요하면 `indexBoardEditorDraft`

이 상태를 하나의 `IndexBoardUndoState`로 묶는 편이 맞다.

## 4. 권장 아키텍처

### 4-1. stack은 하나로 합친다

최종적으로는 아래 두 stack만 남기는 것이 목표다.

- `undoStack: [WorkspaceUndoSnapshot]`
- `redoStack: [WorkspaceUndoSnapshot]`

뷰마다 별도 stack을 유지하지 않는다.

다만 아래는 유지 가능하다.

- 메인 타이핑 coalescing
- 포커스 타이핑 coalescing
- 보드 편집 시트 텍스트 coalescing이 필요해지면 그 로컬 버퍼

중요한 점:

- coalescing 버퍼는 있어도 된다.
- 하지만 coalescing이 끝나서 실제 undo 항목이 만들어질 때는 반드시 공통 stack으로 들어가야 한다.

### 4-2. 기록 경로도 하나로 합친다

현재처럼 각 mutation이 직접 `pushUndoState(...)`, `pushFocusUndoState(...)`를 고르는 대신,
최종 진입점은 하나여야 한다.

권장 API:

```swift
func captureWorkspaceUndoSnapshot() -> WorkspaceUndoSnapshot
func restoreWorkspaceUndoSnapshot(_ snapshot: WorkspaceUndoSnapshot)
func recordWorkspaceUndo(_ previous: WorkspaceUndoSnapshot, actionName: String)
func performWorkspaceUndo()
func performWorkspaceRedo()
```

이후 각 기능은 아래 규칙을 따른다.

- mutation 전: `let previous = captureWorkspaceUndoSnapshot()`
- mutation 후: `recordWorkspaceUndo(previous, actionName: "...")`

이 규칙만 지키면 뷰가 늘어나도 undo 시스템은 늘어나지 않는다.

### 4-3. 명령 라우팅도 하나로 유지한다

현재 `Cmd+Z`, `Cmd+Shift+Z`는 이미 전역 notification 경로를 타고 있다.
이 구조는 유지하는 편이 좋다.

권장 순서:

1. 현재 포커스된 입력 컨텍스트의 typing coalescing을 먼저 finalize한다.
2. 텍스트 전용 undo가 따로 남아 있다면 이를 공통 snapshot 기록 경로로 정리한다.
3. 그 다음 `performWorkspaceUndo()` 또는 `performWorkspaceRedo()`를 실행한다.

즉, 단축키 라우팅은 하나, 스냅샷 복원도 하나로 맞춘다.

## 5. 뷰별 적용 방식

### 5-1. 메인 뷰

메인 뷰는 현재 `ScenarioState` 기반 undo가 이미 가장 많이 깔려 있다.
따라서 첫 단계에서는 메인 뷰 로직을 크게 바꾸기보다,
기존 `ScenarioState`를 `WorkspaceUndoSnapshot.scenario` 안으로 감싸는 식으로 시작하는 게 안전하다.

### 5-2. 포커스 모드

포커스 모드의 핵심은 텍스트 입력 coalescing과 caret 복원이다.
이 둘은 포커스 모드 전용 보조 상태로 남겨도 된다.

다만 최종 undo 항목을 쌓는 stack은 공통이어야 한다.
즉:

- caret 힌트 계산 로직은 포커스 모드 전용
- stack 기록과 redo 초기화는 공통

이렇게 분리하는 것이 맞다.

### 5-3. 보드 뷰

보드는 이번 설계에서 가장 중요한 추가 대상이다.

보드에서 언두가 걸려야 하는 작업:

- 카드 이동
- 선택된 카드 이동
- 그룹 이동
- 카드 삭제
- 그룹 삭제
- 카드 생성
- 부모 그룹 생성
- Temp 전환
- 카드 색상 변경
- 그룹 색상 변경
- 큰 카드 시트 편집 저장

여기서 중요한 기준은 단순하다.

- 화면에서 결과가 달라졌고
- 사용자가 하나의 명령이라고 인식하는 작업이면
- 전부 하나의 workspace undo entry로 기록해야 한다.

## 6. 구현 순서

### 1단계. 공통 snapshot wrapper 도입

먼저 `ScenarioState`를 유지한 채 아래만 추가한다.

- `WorkspaceUndoSnapshot`
- `WorkspaceViewState`
- `IndexBoardUndoState`
- `captureWorkspaceUndoSnapshot()`
- `restoreWorkspaceUndoSnapshot(...)`

이 단계에서는 기존 `performUndo()`, `performRedo()`를 새 함수 내부로 감싸는 수준으로만 바꿔도 된다.

### 2단계. 보드 mutation부터 공통 경로로 이관

보드 뷰는 현재 신규 기능이 빠르게 붙는 영역이라서,
여기부터 공통 경로를 강제하는 편이 이득이 크다.

우선 이관 대상:

- 카드 이동
- 그룹 이동
- 카드 삭제
- 그룹 삭제
- 큰 카드 시트 저장

이 단계가 끝나면 보드에서는 적어도 “내가 방금 한 조작 하나”가 그대로 되돌아가야 한다.

### 3단계. 메인/포커스 stack 합치기

그 다음 기존의:

- `undoStack`, `redoStack`
- `focusUndoStack`, `focusRedoStack`
- `mainTypingUndoStack`, `mainTypingRedoStack`

를 재검토한다.

권장 방향:

- 타이핑 coalescing 버퍼는 뷰별 유지
- 최종 undo entry 저장은 공통 stack 하나

즉, “입력 묶음 방식”만 다르고 “되돌리는 저장소”는 하나로 맞춘다.

### 4단계. 복원 품질 보강

마지막 단계에서는 데이터 복원뿐 아니라 아래 품질을 맞춘다.

- active card 복원
- selected cards 복원
- 보드 줌/스크롤 복원
- 보드에서 editor sheet가 열려 있었다면 복원 정책 결정
- 포커스 모드 caret 복원
- split pane에서 현재 pane 문맥 복원

## 7. 복원 정책

모든 상태를 100% 그대로 되살리는 것이 항상 좋은 것은 아니다.
따라서 아래 정책을 권장한다.

- 카드/그룹 구조, 순서, 색상, 선택 상태는 가능한 한 정확히 복원
- 보드 줌/스크롤은 정확히 복원
- 텍스트 편집 caret은 메인/포커스에서만 복원
- 보드 편집 시트는 처음에는 `닫힌 상태로 복원`을 기본값으로 두고,
  필요하면 이후 `열린 상태 복원`으로 확장

이유:

- 시트 복원은 안정성 비용이 높다.
- 반면 카드 구조와 viewport 복원은 체감 가치가 크다.

## 8. 리스크

가장 큰 리스크는 두 가지다.

### 8-1. 중복 push

한 번의 사용자 조작에 대해 여러 레이어가 각각 undo를 쌓으면,
사용자는 `Cmd+Z`를 두세 번 눌러야 원상복구되는 상태가 된다.

따라서 mutation ownership을 분명히 해야 한다.

- 실제 state를 commit하는 함수만 undo를 기록
- 하위 helper는 undo를 직접 기록하지 않음

### 8-2. 뷰 상태와 문서 상태의 불일치

문서만 복원되고 보드 session이 복원되지 않으면,
카드는 되돌아왔는데 화면은 다른 위치를 보고 있는 문제가 생긴다.

그래서 보드 뷰는 이번 통합에서 반드시 `IndexBoardUndoState`를 같이 가져가야 한다.

## 9. 검증 기준

아래는 최소 검증 시나리오다.

1. 보드에서 카드 한 장 이동 후 `Cmd+Z`, `Cmd+Shift+Z`
2. 보드에서 그룹 이동 후 `Cmd+Z`, `Cmd+Shift+Z`
3. 보드에서 카드 삭제 후 `Cmd+Z`, `Cmd+Shift+Z`
4. 보드에서 그룹 삭제 후 `Cmd+Z`, `Cmd+Shift+Z`
5. 보드에서 카드 색 변경 후 `Cmd+Z`, `Cmd+Shift+Z`
6. 보드에서 큰 카드 시트 저장 후 `Cmd+Z`, `Cmd+Shift+Z`
7. 메인 뷰 편집 후 보드로 이동해서 `Cmd+Z`
8. 포커스 모드 편집 후 메인으로 돌아와 `Cmd+Z`
9. split pane에서 pane A와 pane B가 다른 모드일 때 각각 `Cmd+Z`

이 검증을 통과해야 “뷰마다 따로 설계된 언두”가 아니라
“하나의 작업 공간 언두 시스템”이라고 볼 수 있다.

## 10. 결론

이 앱은 이미 `ScenarioState` 기반 언두 엔진을 갖고 있으므로,
새 언두 시스템을 처음부터 다시 만들 필요는 없다.

맞는 방향은 아래다.

- `ScenarioState`를 유지한다.
- 그 위에 `WorkspaceUndoSnapshot`을 얹는다.
- 보드 세션 상태를 `IndexBoardUndoState`로 묶는다.
- 메인/포커스/보드의 모든 mutation을 공통 기록 함수로 보낸다.
- typing coalescing은 뷰별로 유지하되, 최종 stack은 하나로 합친다.

즉, 이 작업은 `언두 시스템을 여러 개 만드는 일`이 아니라,
이미 있는 문서 상태 언두를 `작업 공간 전체 언두`로 승격시키는 일이다.
