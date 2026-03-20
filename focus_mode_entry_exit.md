# Focus Mode Entry / Exit Lifecycle

Phase 1 update:
- pre-focus-mode main-workspace entry context is now consolidated into `focusModeEntryWorkspaceSnapshot`
- when older split field names appear below, read them as snapshot payload fields:
  - `visibleMainCanvasLevel`
  - `mainCanvasHorizontalOffset`
  - `mainColumnViewportOffsets`

Phase 2 update:
- lifecycle ownership is now also tracked by `focusModePresentationPhase`
- transition intent is:
  - `.entering` before `showFocusMode = true`
  - `.active` after entry onChange setup completes
  - `.exiting` before `showFocusMode = false`
  - `.inactive` after exit teardown window completes

Phase 3 update:
- the main workspace shell is now retained underneath focus mode
- `mainCanvasWithOptionalZoom(...)` stays mounted inside the primary workspace `ZStack`
- while focus mode is active it becomes invisible and non-interactive instead of being fully removed
- focus exit still issues restore requests, so current code is a mixed retained-shell + legacy-restore state

Phase 4 update:
- focus exit now prefers retained-shell reuse
- semantic restore replay runs only as a fallback when the retained shell is not sufficiently attached

Phase 5 update:
- entry canvas alignment no longer uses `focusModeEntryScrollTick`
- initial focus-mode canvas alignment is now owned by `focusModeCanvas(...)` `onAppear`
- while focus mode is active, main-workspace horizontal viewport persistence now uses the retained shell's live offset
- `focusModeEntryWorkspaceSnapshot.mainCanvasHorizontalOffset` remains a fallback restore payload, not a general persistence source

이 문서는 `ScenarioWriterView`에서 포커스 모드 진입과 포커스 모드 아웃이 발생할 때 실제로 어떤 함수들이 호출되고, 어떤 상태가 바뀌고, 어떤 비동기 후속 작업이 예약되는지를 코드 기준으로 정리한 것이다.

범위:
- 작업창에서 포커스 모드로 진입할 때
- 포커스 모드에서 다시 작업창으로 나올 때
- 그 과정에 연쇄적으로 반응하는 스크롤, 캐럿, 편집, 검색, 키보드 포커스, 모니터, 복구 요청

제외:
- 포커스 모드 내부에서 타이핑 중 일어나는 일반적인 selection-change 세부 처리 전체
- 메인 작업창 일반 스크롤 로직 전체 설명

관련 핵심 파일:
- `/Users/three/app_build/wa/wa/WriterFocusMode.swift`
- `/Users/three/app_build/wa/wa/WriterViews.swift`
- `/Users/three/app_build/wa/wa/WriterCardManagement.swift`
- `/Users/three/app_build/wa/wa/WriterCaretAndScroll.swift`
- `/Users/three/app_build/wa/wa/WriterUndoRedo.swift`
- `/Users/three/app_build/wa/wa/waApp.swift`

---

## 1. 진입/아웃의 직접 엔트리 포인트

포커스 모드 토글은 최종적으로 `toggleFocusMode()` 하나로 수렴한다.

직접/간접 엔트리 포인트:
- 메뉴/명령 알림
  - `WriterViews.swift`
  - `workspaceCommandBoundRoot(...)`
  - `.onReceive(NotificationCenter.default.publisher(for: .waToggleFocusModeRequested))`
  - `handleToggleFocusModeRequestNotification()`
- 포커스 모드 배경 클릭
  - `WriterFocusMode.swift`
  - `focusModeCanvasBackdrop()`
  - `.onTapGesture { toggleFocusMode() }`
- 기타 직접 호출
  - `WriterViews.swift` / `WriterFocusMode.swift` 안의 일부 UI 흐름

`handleToggleFocusModeRequestNotification()` 가드:
- `acceptsKeyboardInput == true`
- `isPreviewingHistory == false`
- `showHistoryBar == false`

최종 토글 함수:
- `WriterFocusMode.swift`
- `toggleFocusMode()`

`toggleFocusMode()`는 다음 순서로 동작한다.
1. `let entering = !showFocusMode`
2. `entering == true`면 `resolveFocusModeEntryTargetCard()` 호출
3. 타겟 카드가 있으면 `enterFocusMode(with:)`
4. `entering == false`면 `exitFocusMode()`
5. `applyFocusModeVisibilityState(entering:)`
6. `schedulePostFocusModeToggleFocusUpdate()`

중요:
- 실제 UI 가시 상태를 바꾸는 것은 `showFocusMode`
- 하지만 진입/아웃 준비 작업은 `showFocusMode`를 바꾸기 전에 이미 일부 실행된다
- 그리고 진짜 큰 파이프라인은 `showFocusMode`의 `.onChange`에서 시작된다

---

## 2. 진입 타겟 카드 결정

진입 대상은 `resolveFocusModeEntryTargetCard()`에서 정한다.

우선순위:
1. `editingCardID`
2. `activeCardID`
3. `scenario.rootCards.first`

부수 효과:
- `focusPendingProgrammaticBeginEditCardID = nil`

의미:
- 포커스 모드는 기본적으로 "현재 편집 중 카드" 또는 "현재 활성 카드"를 확대된 단일 컬럼 뷰로 옮긴다
- 둘 다 없으면 루트 첫 카드로 fallback 한다

---

## 3. 진입 직전 사전 작업

`enterFocusMode(with:)`가 진입 직전에 하는 일:

### 3.1 메인 캔버스 가로 위치 캡처
- 함수: `captureMainCanvasHorizontalViewportForFocusEntry()`
- 파일: `WriterCardManagement.swift`

캡처하는 값:
- `focusModeEntryMainCanvasVisibleLevel`
- `focusModeEntryMainCanvasHorizontalOffset`

계산 방법:
- 가능하면 실제 메인 캔버스 가로 `NSScrollView`의 현재 offset에서 visible level 계산
- 안 되면 `activeCardID`의 displayed level 사용
- `mainCanvasHorizontalScrollMode`
  - `.oneStep`면 `activeLevel`
  - `.twoStep`면 `max(0, activeLevel - 1)`
- `lastScrolledLevel`도 같이 동기화

의미:
- 포커스 모드 아웃 시 메인 작업창 가로 위치를 semantic하게 복구하기 위한 진입 시점 스냅샷

### 3.2 진입용 캐럿 힌트 저장
- 함수: `enterFocusMode(with:)`

동작:
- `resolvedMainCaretLocation(for: target)`를 읽어서
- 있으면 `pendingFocusModeEntryCaretHint = (target.id, location)`
- 없으면 `pendingFocusModeEntryCaretHint = nil`

의미:
- 메인 작업창에서 마지막으로 기억한 캐럿 위치를 포커스 모드 진입 직후 다시 사용하려는 힌트

### 3.3 진입 대상 카드를 포커스 모드 편집 상태로 준비
- 함수: `beginFocusModeEditing(target, cursorToEnd: false)`

이 함수는 포커스 모드 진입뿐 아니라 포커스 모드 내부 카드 전환에도 재사용된다.

### 3.4 초기 geometry sync 요청
- `DispatchQueue.main.async`
- `requestFocusModeOffsetNormalization(includeActive: true, force: true, reason: "focus-enter-initial")`

의미:
- 포커스 모드 에디터가 처음 뜰 때 텍스트 geometry / typography / internal scroll origin을 한 번 동기화
- 현재 구조에서는 scroll-time correction이 아니라 entry hygiene 용도

---

## 4. showFocusMode 변경 자체가 하는 일

실제 화면 가시성은 `applyFocusModeVisibilityState(entering:)`에서 바뀐다.

### 4.1 애니메이션과 상태 변경
- `withAnimation(quickEaseAnimation)`
- `showFocusMode = entering`

### 4.2 진입 시 같이 꺼지는 UI
`entering == true`일 때:
- `showTimeline = false`
- `showHistoryBar = false`
- `showAIChat = false`
- `exitPreviewMode()`
- `searchText = ""`
- `isSearchFocused = false`
- `isNamedSnapshotSearchFocused = false`

의미:
- 포커스 모드는 작업창의 보조 레일을 닫고 단일 카드 컬럼에 집중하는 모드

### 4.3 토글 후 키보드 포커스 정리
- 함수: `schedulePostFocusModeToggleFocusUpdate()`
- 0.05초 후
  - `!showFocusMode`면 `restoreMainKeyboardFocus()`
  - `showFocusMode`면 `isMainViewFocused = true`

`restoreMainKeyboardFocus()`는 0.0 / 0.03 / 0.08초 재시도로 메인 포커스를 복구한다.

---

## 5. showFocusMode onChange 파이프라인

`WriterViews.swift`의 `.onChange(of: showFocusMode)`는 실질적인 진입/아웃 파이프의 중심이다.

함수:
- `handleShowFocusModeChange(_ isOn: Bool)`

이 함수는 진입/아웃 공통으로 먼저 아래를 초기화/기록한다.

공통 초기화:
- `mainColumnLastFocusRequestByKey = [:]`
- `focusModeLayoutCoordinator.reset()`
- `focusVerticalScrollAuthoritySequence = 0`
- `focusVerticalScrollAuthority = nil`
- `focusModeCaretRequestStartedAt = .distantPast`
- `focusModeWindowBackgroundActive = isOn`
- `FocusMonitorRecorder.shared.record("focus.toggle", ...)`

의미:
- 작업창의 이전 column focus request 캐시 제거
- 포커스 모드 레이아웃/스크롤 권한 상태 리셋
- 앱 윈도우 배경을 포커스 모드 상태에 맞게 변경

앱 레벨 배경 반영:
- `waApp.swift`
- `focusModeWindowBackgroundActive`
- true면 window background를 black으로 그림

---

## 6. 포커스 모드 진입 시 실제로 일어나는 일

`handleShowFocusModeChange(true)` 순서:

### 6.1 메인 작업창 모니터 중지
- `stopMainNavKeyMonitor()`
- `stopMainCaretMonitor()`

의미:
- 작업창 전용 키보드 네비게이션/캐럿 monitor가 포커스 모드에 간섭하지 않도록 중지

### 6.2 메인 타이핑 세션 마감 및 초기화
- `finalizeMainTypingCoalescing(reason: "focus-enter")`
- `resetMainTypingCoalescing()`
- `resetFocusTypingCoalescing()`

의미:
- 메인 작업창 typing undo coalescing 세션 종료
- 포커스 모드 전용 typing coalescing 상태는 깨끗하게 시작

### 6.3 포커스 모드용 "마지막 커밋된 텍스트" 스냅샷 생성
- `focusLastCommittedContentByCard = Dictionary(uniqueKeysWithValues: scenario.cards.map { ($0.id, $0.content) })`

의미:
- 포커스 모드 타이핑 coalescing, boundary typing, content suppression 등에서 기준값으로 사용

### 6.4 포커스 모드 전용 모니터 시작
- `startFocusModeKeyMonitor()`
- `startFocusModeScrollMonitor()`
- `startFocusModeCaretMonitor()`

각 역할:
- key monitor
  - 포커스 모드 전용 `up/down`, `Esc`, 검색, typewriter, 삽입/삭제 shortcut 처리
- scroll monitor
  - 현재 구조에서는 scroll-wheel correction layer를 유지하지 않으며 사실상 비활성화
  - 다만 internal text editor bounds observer 정리 로직과 연동되는 자리
- caret monitor
  - `NSTextView.didChangeSelectionNotification` 구독
  - 시작 직후 eager ensure는 하지 않고, 실제 selection/programmatic caret apply 이후 경로를 기다림

### 6.5 초기 focus-mode canvas 정렬

의미:
- 포커스 모드 캔버스가 실제로 나타난 다음, `focusModeCanvas(...)` `onAppear`가 target card를 `ScrollViewReader`로 한 번 맞춘다

### 6.6 진입 target 카드에 대해 실제 포커스 에디터 시작
- `DispatchQueue.main.async`
- `targetID = focusModeEditorCardID ?? editingCardID ?? activeCardID`
- 이미 `enterFocusMode(with:)`가 `beginFocusModeEditing(...)`를 끝낸 상태이므로
- 여기서는 second `beginFocusModeEditing(...)`를 하지 않는다
- target이 그대로고 `editingCardID == targetID`인데 `focusModeEditorCardID`만 아직 nil이면
  - `focusModeEditorCardID = targetID`

의미:
- 포커스 모드 UI가 실제 렌더된 뒤, 이미 준비된 진입 target의 editor binding만 보완한다

---

## 7. 포커스 모드 진입 시 beginFocusModeEditing()가 하는 일

이 함수는 진입의 핵심이다.

### 7.1 카드 전환 단계
함수 체인:
- `beginFocusModeEditing(...)`
- `applyFocusModeBeginEditingCardTransition(...)`
- `prepareFocusModeForEditingSwitchIfNeeded(targetCardID:)`
- `updateActiveCardForFocusModeEditing(...)`
- `syncFocusModeEditingState(card:switchingToDifferentCard:)`

세부 동작:

#### 7.1.1 이전 포커스 typing 세션 종료
- `showFocusMode && activeCardID != nil && activeCardID != targetCardID`
- `finalizeFocusTypingCoalescing(reason: "focus-card-switch")`

#### 7.1.2 boundary arm 해제
- `clearFocusBoundaryArm()`

#### 7.1.3 기존 editing 상태 커밋 또는 종료
- 포커스 모드 안에서 다른 카드로 이동 중이면
  - `commitFocusModeCardEditIfNeeded()`
- 포커스 모드가 아닌 일반 editing에서 다른 카드로 이동 중이면
  - `finishEditing()`

#### 7.1.4 activeCard 업데이트
- `activeCardID != card.id`면
  - `focusPendingProgrammaticBeginEditCardID = card.id`
  - `preserveViewportOnSwitch == true`면
    - `suppressFocusModeScrollOnce = true`
    - `focusModeNextCardScrollAnchor = nil`
    - `focusModeNextCardScrollAnimated = true`
  - 아니면
    - `focusModeNextCardScrollAnchor = cardScrollAnchor`
    - `focusModeNextCardScrollAnimated = animatedScroll`
  - `changeActiveCard(to: card, deferToMainAsync: showFocusMode)`

#### 7.1.5 편집 상태 동기화
- `selectedCardIDs = [card.id]`
- 카드 전환이면
  - `focusModeLayoutCoordinator.awaitFreshLiveEditorLayoutCommit(for: card.id)`
  - `editingCardID = card.id`
  - `editingStartContent = card.content`
  - `editingStartState = captureScenarioState()`
  - `editingIsNewCard = false`
- `focusModeEditorCardID = card.id`
- `focusLastCommittedContentByCard[card.id] = card.content`

의미:
- 포커스 모드 진입은 단순 뷰 토글이 아니라
  - active card 동기화
  - editing session 재시작
  - undo/coalescing 기준 상태 저장
  - focus-mode-specific editable target 지정
를 한 번에 수행한다

### 7.2 캐럿 위치 결정 단계
함수 체인:
- `prepareFocusModeBeginEditingCaret(...)`
- `resolveFocusModeBeginEditingCaretLocation(...)`
- `configureFocusModeProgrammaticCaretExpectation(...)`

캐럿 위치 우선순위:
1. `explicitCaretLocation`
2. `pendingFocusModeEntryCaretHint` matching card
3. `cursorToEnd == true`면 카드 끝
4. `placeCursorAtStartWhenNoHint == true`면 0
5. 아니면 nil

의미:
- 진입 시 메인 작업창에서 저장한 caret 힌트를 먼저 재사용
- 힌트가 없으면 카드 시작이나 카드 끝으로 진입

### 7.3 캐럿 적용 예약 단계
함수:
- `scheduleFocusModeBeginEditingCaret(...)`

동작:
- `focusModeCaretRequestStartedAt = Date()`
- `focusModeCaretRequestID += 1`
- `scheduleFocusModeBeginEditingCaretApplications(...)`

의미:
- 진입 직후는 responder / editable text view / live layout commit이 아직 정착 전일 수 있으므로
- 실제 캐럿 적용은 여러 비동기 pass로 예약됨

---

## 8. 포커스 모드 캔버스가 진입 직후 하는 일

포커스 모드 캔버스는 `ScrollViewReader + ScrollView(.vertical)` 구조다.

주요 reactive entry points:
- `onChange(of: activeCardID)` → `handleFocusModeCanvasActiveCardChange(...)`
- `onAppear` → `handleFocusModeCanvasAppear(...)`
- `onChange(of: focusModeFallbackRevealTick)` → `handleFocusModeFallbackRevealTickChange(...)`
- `onChange(of: size.width)` → `handleFocusModeCanvasWidthChange(...)`

### 8.1 activeCardID 변경 반응
`handleFocusModeCanvasActiveCardChange(_:, proxy:)`

순서:
1. `focusResponderCardByObjectID.removeAll()`
2. `consumePendingFocusModeProgrammaticBeginMatch(for:)`
3. `handleFocusModeSuppressedScrollIfNeeded(...)`
4. 아니라면
   - `beginFocusModeVerticalScrollAuthority(kind: .canvasNavigation, targetCardID: id)`
   - `performFocusModeCanvasActiveCardScroll(...)`
   - `applyFocusModeCanvasActiveCardEditorState(id:)`
   - `scheduleFocusModeCanvasActiveCardBeginEditingIfNeeded(id:)`

의미:
- active card가 바뀌면 포커스 모드 캔버스는 자기 컬럼 내 카드 위치를 다시 맞추고
- 해당 카드를 `focusModeEditorCardID`로 표시하며
- 필요 시 다시 `beginFocusModeEditing(...)`를 호출한다

### 8.2 entry scroll tick 반응
`handleFocusModeEntryScrollTickChange(proxy:)`

동작:
- `showFocusMode == true`
- `focusModeEditorCardID ?? editingCardID ?? activeCardID`를 target으로
- `beginFocusModeVerticalScrollAuthority(kind: .canvasNavigation, targetCardID: id)`
- `proxy.scrollTo(focusModeCardScrollID(id), anchor: .center)`

의미:
- 포커스 모드 진입 직후 target 카드가 중앙 기준으로 한 번 맞춰진다

### 8.3 fallback reveal tick 반응
`handleFocusModeFallbackRevealTickChange(proxy:)`

동작:
- `focusModePendingFallbackRevealCardID`
- authority가 `.fallbackReveal`일 때만
- `proxy.scrollTo(focusModeCardScrollID(id))`

의미:
- boundary transition 후 editor/caret 복원만으로 target이 화면 안에 안 들어오면 마지막 fallback reveal 수행

---

## 9. 포커스 모드 selection / caret 모니터가 진입 직후 하는 일

### 9.1 caret monitor 시작
`startFocusModeCaretMonitor()`

동작:
- `NSTextView.didChangeSelectionNotification` observer 추가

현재 구현:
- monitor start 시점에는 eager caret ensure를 바로 발사하지 않는다
- 첫 ensure는 live editable `NSTextView`가 실제로 붙고 selection/programmatic caret apply가 일어난 뒤의 경로가 맡는다

즉:
- 진입 직후 monitor는 먼저 대기 상태로 들어가고, 실제 caret context가 생긴 뒤 keep-visible 루프가 기동한다

### 9.2 selection notification 처리 파이프
`handleFocusModeSelectionNotification(_:)`
→ `processFocusModeSelectionNotification(textView:)`

가드:
- `showFocusMode`
- `!isApplyingUndo`
- `!isReferenceWindowFocused`
- `NSApp.keyWindow?.firstResponder === textView`

처리 순서:
1. `rememberFocusResponderCardMapping(textView:)`
2. `focusUndoSelectionEnsureSuppressed` 체크
3. `focusModeSelectionContext(for:)`
4. `updateFocusSelectionActiveEdge(...)`
5. `restoreExpectedFocusSelectionIfNeeded(...)`
6. `handleDuplicateFocusSelectionIfNeeded(...)`
7. `applyFocusSelectionNotification(...)`

`applyFocusSelectionNotification(...)`에서 일어나는 일:
- `storeFocusSelectionState(...)`
  - `mainCaretLocationByCardID[trackedCardID] = caretLocation`
  - `persistLastFocusSnapshot(cardID:..., isEditing: true, inFocusMode: true)`
- `handleFocusModeSelectionChanged()`
- marked text가 아니면 `scheduleFocusCaretEnsureForSelectionChange()`

의미:
- 포커스 모드 진입 후 selection이 한 번만 바뀌는 게 아니라
- 실제 editable text view가 붙고 selection이 적용될 때
- caret persistence, selection bookkeeping, keep-visible request가 연쇄적으로 생긴다

---

## 10. 포커스 모드 진입 시 저장/복원에 쓰는 상태들

### 핵심 상태
- `showFocusMode`
- `focusModeEditorCardID`
- `editingCardID`
- `activeCardID`
- `pendingFocusModeEntryCaretHint`
- `focusPendingProgrammaticBeginEditCardID`
- `focusModeEntryScrollTick`
- `focusModeEntryMainCanvasVisibleLevel`
- `focusModeEntryMainCanvasHorizontalOffset`
- `focusModeCaretRequestID`
- `focusModeCaretRequestStartedAt`
- `focusVerticalScrollAuthority`
- `focusLastCommittedContentByCard`
- `focusResponderCardByObjectID`

### persistence 관련 상태
- `lastFocusedScenarioID`
- `lastFocusedCardID`
- `lastFocusedCaretLocation`
- `lastFocusedWasEditing`
- `lastFocusedWasFocusMode`

의미:
- 포커스 모드는 뷰 모드 전환일 뿐 아니라
- "현재 집중 중인 카드와 caret"을 앱 전역 persistence에 계속 반영한다

---

## 11. 포커스 모드 아웃 직전에 직접 일어나는 일

`exitFocusMode()`

순서:
1. `beginFocusModeExitTeardownWindow()`
2. `pendingFocusModeEntryCaretHint = nil`
3. `focusPendingProgrammaticBeginEditCardID = nil`
4. `finishEditing()`
5. `focusModeEditorCardID = nil`
6. `clearFocusBoundaryArm()`

핵심:
- 아웃은 먼저 짧은 teardown gate를 열고
- 그 다음 editing session을 끝내고
- 포커스 모드용 editor binding을 해제한 뒤
- 나중에 `showFocusMode = false`가 된다

### 11.1 exit teardown window

`beginFocusModeExitTeardownWindow()`가 하는 일:
- `focusModeExitTeardownUntil = now + 0.35`
- `focusCaretEnsureWorkItem?.cancel()`
- `focusModeCaretRequestID += 1`
- `focusModeBoundaryTransitionPendingReveal = false`
- `focusModePendingFallbackRevealCardID = nil`
- `focusModeFallbackRevealIssuedCardID = nil`
- `clearFocusModeExcludedResponder()`

의미:
- 포커스 모드 아웃 시작 직후의 짧은 시간 동안
- 늦게 들어오는 selection-change, caret ensure, caret retry, fallback reveal이
  다시 포커스 모드 viewport를 건드리지 못하게 막는다

### 11.2 finishEditing()가 포커스 모드 아웃에서 의미하는 것

`finishEditing()`는 `takeFinishEditingContext()`를 통해 현재 editing session을 끊는다.

포커스 모드 아웃 시 `takeFinishEditingContext()`에서 일어나는 일:
- `inFocusMode = showFocusMode`
- `skipMainFocusRestore = suppressMainFocusRestoreAfterFinishEditing || inFocusMode`
- 포커스 모드면
  - `finalizeFocusTypingCoalescing(reason: "finish-editing")`
- `editingCardID` 확보
- 일반 작업창이 아니므로 `rememberMainCaretLocation(...)`는 하지 않음
- `resetEditingTransientState()`
  - `editingCardID = nil`
  - `editingStartContent = ""`
  - `editingIsNewCard = false`
  - `editingStartState = nil`
  - `pendingNewCardPrevState = nil`

그 뒤 `commitFinishedEditingIfNeeded(...)`가 호출되어 실제 카드 내용을 커밋하고 snapshot / save / undo 상태를 정리한다.

즉:
- 포커스 모드 아웃은 단순 뷰 닫기가 아니라 현재 포커스 카드 편집 세션 커밋을 포함한다

---

## 12. showFocusMode false onChange 때 실제로 일어나는 일

`handleShowFocusModeChange(false)` 순서:

### 12.1 포커스 모드 타이핑 세션 종료
- `finalizeFocusTypingCoalescing(reason: "focus-exit")`

### 12.2 포커스 모드 검색 흔적 제거
- `clearPersistentFocusModeSearchHighlight()`
- `closeFocusModeSearchPopup()`

### 12.3 포커스 모드 전용 모니터 중지
- `stopFocusModeKeyMonitor()`
- `stopFocusModeScrollMonitor()`
- `stopFocusModeCaretMonitor()`

`stopFocusModeCaretMonitor()`가 정리하는 상태:
- `focusCaretEnsureWorkItem?.cancel()`
- `focusCaretPendingTypewriter = false`
- `focusTypewriterDeferredUntilCompositionEnd = false`
- `focusModeCaretRequestStartedAt = .distantPast`
- `focusModeBoundaryTransitionPendingReveal = false`
- `focusModePendingFallbackRevealCardID = nil`
- `focusModeFallbackRevealIssuedCardID = nil`
- selection bookkeeping 리셋
- programmatic caret expectation 리셋
- `resetFocusTypingCoalescing()`
- `focusResponderCardByObjectID.removeAll()`
- `focusObservedBodyHeightByCardID.removeAll()`
- line-spacing applied state 리셋
- focus vertical scroll authority 리셋
- notification observer 제거

### 12.4 메인 작업창 모니터 재시작
- `startMainNavKeyMonitor()`
- `startMainCaretMonitor()`

### 12.5 메인 캔버스 복구 요청
- `requestMainCanvasRestoreForFocusExit()`
- `requestMainCanvasViewportRestoreForFocusExit()`

### 12.6 마지막 포커스 스냅샷 저장
- `if let activeID = activeCardID { persistLastFocusSnapshot(cardID: activeID, isEditing: false, inFocusMode: false) }`

의미:
- 포커스 모드를 빠져나오면
  - 포커스 모드 전용 모니터/상태를 모두 해제하고
  - 메인 작업창의 키보드/캐럿 감시를 되살리고
  - 메인 작업창 viewport와 semantic visible level 복구를 요청한다

추가 가드:
- `focusModeExitTeardownUntil`이 살아 있는 동안은
  - `handleFocusModeSelectionNotification(...)`
  - `processFocusModeSelectionNotification(...)`
  - `requestFocusModeCaretEnsure(...)`
  - `executeFocusModeCaretEnsureWork(...)`
  - `ensureFocusModeCaretVisible(...)`
  - `applyFocusModeCaretWithRetry(...)`
  - `requestFocusModeBoundaryFallbackRevealIfNeeded(...)`
  가 조기 종료될 수 있다

---

## 13. 포커스 모드 아웃 후 메인 작업창 복구 파이프

### 13.1 semantic 가로 복구 요청
함수:
- `requestMainCanvasRestoreForFocusExit()`

동작:
1. `targetID = activeCardID ?? editingCardID ?? lastActiveCardID ?? scenario.rootCards.first?.id`
2. `visibleLevel = focusModeEntryMainCanvasVisibleLevel`
3. `focusModeEntryMainCanvasVisibleLevel = nil`
4. `focusModeEntryMainCanvasHorizontalOffset = nil`
5. `enqueueMainCanvasRestoreRequest(targetID: targetID, visibleLevel: visibleLevel, forceSemantic: true, reason: .focusExit)`

의미:
- 메인 작업창 아웃 후의 가로 복구는
  - raw offset 직접 복원보다
  - "진입 전 보고 있던 visible level"을 semantic restore request로 다시 맞추는 쪽에 가깝다

### 13.2 세로 viewport 복구 요청
함수:
- `requestMainCanvasViewportRestoreForFocusExit()`

동작:
- `storedOffsets = mainColumnViewportOffsetByKey`
- 비어 있지 않으면 `scheduleMainCanvasRestoreRetries { applyStoredMainColumnViewportOffsets(storedOffsets) }`

retry delay:
- `0.0`
- `0.05`
- `0.18`

의미:
- 포커스 모드 진입 전 저장해 둔 각 main column의 세로 offset을 다시 적용

### 13.3 메인 작업창 실제 복구 소비 지점
- `restoreMainCanvasPositionIfNeeded(proxy:availableWidth:)`
- `pendingMainCanvasRestoreRequest`를 읽어서
  - `visibleLevel` restore 또는
  - `targetCardID` 기반 `scrollToColumnIfNeeded(...)`
  - 이후 pending clear

즉 포커스 모드 아웃은 "즉시 복구"가 아니라 "복구 request를 발행하고, 메인 캔버스 host가 준비되면 소비"하는 구조다.

---

## 14. 포커스 모드 진입/아웃과 앱 레벨 UI가 같이 바뀌는 것들

### 진입 시
- window background를 black으로 변경
  - `focusModeWindowBackgroundActive = true`
- timeline/history/chat 닫힘
- 일반 검색 입력 focus 해제
- named snapshot 관련 focus 해제

### 아웃 시
- window background 복귀
  - `focusModeWindowBackgroundActive = false`
- main nav / main caret monitor 재시작
- `restoreMainKeyboardFocus()` 예약

---

## 15. 진입/아웃과 관련된 중요한 비동기 후속 작업

이 부분이 실제 버그를 자주 만드는 구간이다.

### 진입 후 비동기 체인
1. `enterFocusMode(with:)`
2. `beginFocusModeEditing(...)`
3. `changeActiveCard(...)`
4. `showFocusMode = true`
5. `handleShowFocusModeChange(true)`
6. 포커스 모드 캔버스 `onAppear`
7. 포커스 모드 캔버스의 `activeCardID onChange`
8. `focusModeEditorCardID` 보강
9. `NSTextView` first responder / selection 붙음
10. `didChangeSelectionNotification`
11. `requestFocusModeCaretEnsure(...)`
12. live layout commit 대기 / retry / fallback reveal 가능

### 아웃 후 비동기 체인
1. `finishEditing()`
2. `showFocusMode = false`
3. `handleShowFocusModeChange(false)`
4. main monitor 재시작
5. main canvas restore request 발행
6. main canvas host가 pending restore request 소비
7. viewport restore retry pass 적용
8. keyboard focus restore retry pass 적용

이 비동기 체인 때문에
- 진입/아웃은 단일 함수 호출이 아니라
- 여러 onChange / DispatchQueue.main.async / monitor callback / selection notification이 중첩된 파이프라인이다

---

## 16. 왜 이 흐름이 복잡해 보이는가

포커스 모드 진입/아웃이 복잡한 이유는 세 가지다.

### 16.1 `showFocusMode`만 바꾸면 끝나는 구조가 아니다
- 진입 전 이미
  - 메인 canvas snapshot 캡처
  - entry caret hint 저장
  - editing session 준비
가 일어난다

### 16.2 진입 후 실제 focus editor 정착까지 여러 비동기 단계가 있다
- active card 반영
- focusModeEditorCardID 설정
- editable NSTextView 실현
- first responder 이동
- live layout commit
- selection notification
- caret ensure

### 16.3 아웃도 단순 해제가 아니라 "편집 커밋 + 메인 작업창 restore"다
- finishEditing
- focus typing finalize
- monitor 전환
- main canvas restore request
- viewport restore retry
- keyboard focus restore retry

즉 포커스 모드 진입/아웃은 사실상 "모드 전환"이면서 동시에
- 편집 세션 전환
- 스크롤 surface 전환
- 키보드 이벤트 라우팅 전환
- caret persistence 전환
- window chrome 상태 전환
을 같이 수행한다

---

## 17. 앞으로 수정할 때 특히 주의할 지점

### A. 진입 target 결정과 showFocusMode onChange를 분리해서 생각할 것
- `toggleFocusMode()` 안의 entry preparation
- `handleShowFocusModeChange(true)` 안의 reactive setup
를 섞어서 보면 버그 원인을 놓치기 쉽다

### B. `beginFocusModeEditing(...)`는 진입 전용이 아니다
- 진입
- 카드 클릭
- boundary transition
- 내부 카드 전환
모두 재사용한다

### C. 포커스 모드 아웃 복구는 `request` 기반이다
- `requestMainCanvasRestoreForFocusExit()`
- `requestMainCanvasViewportRestoreForFocusExit()`
즉 아웃 시점에 바로 화면이 복구되는 게 아니라, main canvas host가 나중에 소비한다

### D. 진입/아웃 버그는 대개 아래 중 하나다
- entry target card 잘못 선택
- `focusModeEditorCardID`와 `editingCardID`가 엇갈림
- `focusPendingProgrammaticBeginEditCardID` stale
- live layout commit 전에 caret/fallback가 너무 빨리 움직임
- focus exit restore request가 메인 캔버스 attach 시점과 어긋남

---

## 18. 요약

포커스 모드 진입:
1. 진입 대상 카드 결정
2. 메인 작업창 viewport / caret snapshot 캡처
3. `beginFocusModeEditing(...)`로 active/editing/focus editor 상태 준비
4. `showFocusMode = true`
5. 메인 모니터 중지, 포커스 모드 모니터 시작
6. entry scroll tick, begin-edit caret request, selection notification, caret ensure 순으로 정착

포커스 모드 아웃:
1. `finishEditing()`로 현재 편집 세션 커밋
2. `focusModeEditorCardID = nil`
3. `showFocusMode = false`
4. 포커스 모드 모니터 중지, 메인 모니터 재시작
5. 메인 캔버스 restore request + viewport restore retry 발행
6. keyboard focus 복구

이 문서를 기준으로 포커스 모드 진입/아웃 버그를 볼 때는 항상 아래 질문부터 확인하는 것이 좋다.
- 진입 전 캡처가 올바른가
- showFocusMode onChange에서 어떤 모니터가 켜지고 꺼졌는가
- beginFocusModeEditing가 어떤 옵션으로 호출됐는가
- live layout commit 전/후에 어떤 caret request가 예약됐는가
- 아웃 후 main canvas restore request가 실제로 소비됐는가
