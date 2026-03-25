# Main Workspace Cursor / Focus Navigation Map

이 문서는 메인 작업창에서 커서 이동 키를 눌렀을 때, 키 입력이 어디로 들어가고, 어떤 상태가 바뀌며, 어떤 스크롤/캐럿/포커스 후속 작업이 예약되는지를 코드 기준으로 정리한 것이다.

범위:
- 메인 workspace(main mode) 기준
- 화살표 기반 카드 포커스 이동
- 편집 중 caret boundary를 넘는 카드 전환
- 그 전후에 발생하는 selection, caret restore, keep-visible, column focus alignment, horizontal canvas scroll, diagnostics

제외:
- focus mode 내부 전용 네비게이션
- index board 전용 입력 경로
- history preview 전용 좌우 이동
- 마우스 클릭 중심 포커스 이동 전체

관련 핵심 파일:
- `wa/WriterViews.swift`
- `wa/WriterKeyboardHandlers.swift`
- `wa/WriterCardManagement.swift`
- `wa/WriterCaretAndScroll.swift`
- `wa/MainCanvasScrollCoordinator.swift`
- `wa/MainCanvasNavigationDiagnostics.swift`
- `wa/WriterSharedTypes.swift`

---

## 1. 먼저 걸리는 전역 가드

메인 작업창이 키 입력을 받으려면 먼저 아래 조건을 통과해야 한다.

- `acceptsKeyboardInput == true`
  - split pane이 아니면 항상 true
  - split pane이면 현재 pane이 active pane이어야 함
- focus mode 아님
- history preview 흐름 아님
- index board inline editing 아님

관련 코드:
- `WriterViews.swift`
  - `acceptsKeyboardInput`
  - `workspaceFocusedRoot(for:)`
  - `workspaceCommandBoundRoot(_:)`
- `WriterKeyboardHandlers.swift`
  - `handleGlobalKeyPress(_:)`
  - `startMainNavKeyMonitor()`

중요:
- workspace root는 `.focusable()` + `.focused($isMainViewFocused)`로 키 포커스를 가진다.
- 동시에 `.task`에서 AppKit local monitor도 시작한다.
- 그래서 실제 키 입력은 SwiftUI `onKeyPress` 경로와 AppKit `NSEvent` monitor 경로가 함께 존재한다.

---

## 2. 키 입력 엔트리 포인트

### 2.1 SwiftUI 경로

workspace root에는 다음 핸들러가 붙어 있다.

- `workspaceCommandBoundRoot(_:)`
- `.onKeyPress(phases: [.down, .repeat])`
- 최종 진입 함수: `handleGlobalKeyPress(_:)`

이 경로는 다음 상황에서 주로 동작한다.

- 메인 root가 포커스를 직접 갖고 있을 때
- 편집 중이지만 root-level shortcut 분기를 타야 할 때
- SwiftUI `KeyPress`로 충분히 처리 가능한 키 조합일 때

### 2.2 AppKit local monitor 경로

workspace 시작 시 아래 monitor가 붙는다.

- `startMainNavKeyMonitor()`
- `NSEvent.addLocalMonitorForEvents(matching: [.keyDown])`

이 경로는 메인 카드가 idle 상태일 때 화살표 포커스 이동의 실질적인 주 경로다.

이 monitor는 먼저 아래를 걸러낸다.

- reference window 이벤트
- 입력 비활성 pane
- fountain / clone paste dialog
- focus mode / history / preview mode
- delete alert 처리
- plain escape 처리
- `Cmd-F`
- `Ctrl-Tab`
- editing 중 paste 특수 처리
- AI chat / search / main editing 상태

위 가드를 통과한 뒤 plain arrow만 `handleNavigationKeyCode(...)`로 들어간다.

---

## 3. idle 상태 화살표 포커스 이동

idle 상태란:

- `editingCardID == nil`
- `isSearchFocused == false`
- `showFocusMode == false`

실제 흐름:

1. `mainNavKeyMonitor`
2. `handleNavigationKeyCode(keyCode:isRepeat:isShiftPressed:)`
3. `performMainArrowNavigation(...)`
4. `changeActiveCard(...)`
5. `registerHandledMainArrowNavigation(...)`
6. `handleActiveCardIDChange(_:)`
7. horizontal / vertical scroll 계층 반응

### 3.1 `performMainArrowNavigation(...)`가 하는 일

이 함수는 현재 `activeCardID`의 displayed location을 기준으로 target을 정한다.

공통 처리:
- `resolvedLevelsWithParents().map(\.cards)`로 현재 표시 레벨 계산
- current level / next level 계산
- 다중 선택인데 `Shift`가 아니면 `selectedCardIDs`를 현재 active 하나로 축소

방향별 처리:

- `up`
  - 같은 level의 이전 카드 우선
  - 없으면 `mainCrossCategoryBoundaryTarget(... step: -1)` 시도
- `down`
  - 같은 level의 다음 카드 우선
  - 마지막 카드면 `requestMainBottomRevealIfNeeded(...)` 먼저 시도
  - 그래도 아니면 `mainCrossCategoryBoundaryTarget(... step: 1)`
- `left`
  - 즉시 parent 카드
- `right`
  - 기억된 child 또는 선호 child 우선
  - child가 없으면 double-press fallback arm 상태 사용

### 3.2 선택 상태 변화

plain arrow:
- `selectedCardIDs = [target.id]`
- `keyboardRangeSelectionAnchorCardID` 초기화

`Shift + arrow`:
- `updateKeyboardRangeSelection(...)`
- anchor가 있으면 유지
- 없으면 현재 카드가 anchor가 됨

### 3.3 빠른 반복 입력 억제

세로 이동에서는 아래 상태가 사용된다.

- `registerMainVerticalArrowPress(for:)`
- `mainRecentVerticalArrowKeyCode`
- `mainRecentVerticalArrowAt`

깊은 level(`levelIndex >= 2`)에서 category가 바뀌는 경계 이동은:

- repeat 입력이거나
- 아주 빠른 burst 입력이면

실제 포커스 이동 대신 `playMainBoundaryFeedbackIfNeeded(...)`만 실행하고 이동을 막는다.

### 3.4 `right`의 double-press fallback

child가 없을 때는 바로 실패하지 않는다.

1. 첫 `right`
   - `armMainNoChildRight(for:)`
   - 실제 이동 없음
2. 두 번째 `right`가 제한 시간 안에 들어오면
   - `nearestLevelChildTarget(...)`
   - 같은 category 우선
   - 없으면 category 무시 fallback

즉, `right`는
- child가 있으면 즉시 이동
- child가 없으면 arm 후 두 번째 눌림에서 nearby sibling child를 찾는 구조다.

---

## 4. 편집 중 화살표 경계 이동

편집 중 화살표는 idle 경로가 아니라 typing-context 경로를 탄다.

실제 흐름:

1. `handleGlobalKeyPress(_:)`
2. `handleTypingContextShortcut(_:isMainEditorTyping:)`
3. `handleMainEditorBoundaryNavigation(_:)`
4. 방향별 boundary handler
5. `switchMainEditingTarget(...)` 또는 `applyMainBoundaryShiftSelection(...)`
6. `handleEditingCardIDChange(oldID:newID:)`
7. caret restore / line spacing / ensure visible

### 4.1 boundary navigation 진입 조건

`handleMainEditorBoundaryNavigation(_:)`는 아래를 모두 요구한다.

- 현재 `editingCardID`가 존재
- `NSApp.keyWindow?.firstResponder`가 `NSTextView`
- textView의 내용이 editing card content와 정확히 일치
- IME marked text 아님

그 뒤 현재 커서를 계산한다.

- `cursor = textView.selectedRange().location`
- `focusCaretVisualBoundaryState(textView:cursor:)`

여기서 단순히 location만 보지 않고:

- caret가 첫 줄 시각 경계인지
- caret가 마지막 줄 시각 경계인지

까지 본다.

### 4.2 `up` / `down`

편집 중 `up`:
- caret가 문서 맨 앞이고
- 시각적으로 첫 줄 경계일 때만
- 이전 카드 또는 cross-category boundary target으로 이동
- target caret는 카드 끝으로 설정

편집 중 `down`:
- caret가 문서 맨 끝이고
- 시각적으로 마지막 줄 경계일 때만
- 다음 카드 또는 cross-category boundary target으로 이동
- target caret는 카드 시작으로 설정

둘 다:
- `editingIsNewCard` 이고 빈 카드면 boundary move 전에 `finishEditing()`
- `Shift`면 편집 종료 후 range selection 경로로 분기
- 일반 이동이면 `switchMainEditingTarget(...)`

### 4.3 `left`

편집 중 `left`는 바로 parent로 가지 않는다.

조건:
- caret가 0
- 시각적으로 top boundary
- parent가 존재

동작:

1. 첫 눌림
   - `armMainBoundaryParentLeft(for:)`
   - 실제 이동 없음
2. 두 번째 눌림
   - `switchMainEditingTarget(to: parent, caretLocation: parentLength)`

즉 parent 이동은 double-press arm 구조다.

### 4.4 `right`

편집 중 `right`도 바로 child로 가지 않는다.

조건:
- caret가 contentLength
- 시각적으로 bottom boundary

동작:

1. 첫 눌림
   - `armMainBoundaryChildRight(for:)`
   - child가 없으면 `armMainNoChildRight(for:)`도 같이 설정
2. 두 번째 눌림
   - `resolvedMainRightTarget(...)`
   - child 우선
   - 없으면 nearby sibling child fallback
   - target이 있으면 `switchMainEditingTarget(... caretLocation: 0)`

### 4.5 편집 중 `Shift + boundary`

`Shift`가 들어오면 editing target switch가 아니라:

- `finishEditing()`
- `changeActiveCard(... shouldFocusMain: false)`
- `updateKeyboardRangeSelection(...)`

즉 selection-only 경로로 바뀐다.

---

## 5. `switchMainEditingTarget(...)`가 한 번에 만드는 상태

편집 중 boundary 이동의 핵심 함수는 `switchMainEditingTarget(...)`다.

이 함수는 아래를 한 번에 수행한다.

- 필요 시 빈 신규 카드 `finishEditing()`
- `cancelMainArrowNavigationSettle()`
- `cancelAllPendingMainColumnFocusWork()`
- `pendingMainEditingSiblingNavigationTargetID`
- `pendingMainEditingBoundaryNavigationTargetID`
- 필요 시 `pendingMainEditingViewportKeepVisibleCardID`
- 필요 시 `pendingMainEditingViewportRevealEdge`
- `changeActiveCard(... shouldFocusMain: false, deferToMainAsync: false)`
- `selectedCardIDs = [target.id]`
- `editingCardID = target.id`
- `editingStartContent`
- `editingStartState`
- `editingIsNewCard = false`
- `mainCaretLocationByCardID[target.id] = safeCaretLocation`

중요:
- sibling boundary 이동은 `suppressSiblingNavigationScrolls: true`로 호출되는 경우가 많다.
- 이 경우 explicit keep-visible edge를 만들지 않고, horizontal auto align도 의도적으로 줄인다.

---

## 6. `changeActiveCard(...)`가 실제로 바꾸는 것

포커스 이동의 실질적인 state mutation은 `changeActiveCard(...)`에 모인다.

순서:

1. 빈 편집 카드 정리 필요 시 `cleanupEmptyEditingCardIfNeeded(...)`
2. 이미 active / pending이면 early return
3. `pendingActiveCardID = card.id`
4. apply 블록에서:
   - `lastActiveCardID` 갱신
   - `activeCardID = card.id`
   - split pane이면 `scenario.setSplitPaneActiveCard(...)`
   - `card.parent?.lastSelectedChildID = card.id`
   - `synchronizeActiveRelationState(for: card.id)`
   - 필요 시 `isMainViewFocused = true`
   - `maxLevelCount` 갱신

즉 포커스 이동은 단순 선택 변화가 아니라:

- split pane 공유 상태
- parent가 기억하는 child
- ancestor/sibling/descendant cache
- 복원용 last active 상태

까지 동시에 바꾼다.

---

## 7. `activeCardID` 변경 직후 후속 처리

`activeCardID`가 실제로 바뀌면 `handleActiveCardIDChange(_:)`가 반응한다.

이 함수는 아래를 수행한다.

- `mainColumnLastFocusRequestByKey` 전체 비움
- root card면 `mainColumnViewportRestoreUntil = now + 0.35`
- `persistLastEditedCard(newID)`
- editing 중이 아니면 `persistLastFocusSnapshot(...)`
- split pane active card 동기화
- linked-card filter anchor 동기화
- `synchronizeActiveRelationState(for: newID)`

그리고 분기한다.

### 7.1 pending sibling editing navigation이면

- `pendingMainHorizontalScrollAnimation = nil`
- `syncMainCanvasInteractionState()`
- 0.25초 후 target이 그대로면 `pendingMainEditingSiblingNavigationTargetID = nil`
- 여기서 종료

즉 editing boundary sibling 이동은 일반 active-card navigation event를 일부러 생략한다.

### 7.2 editing 중이지만 explicit vertical transition이 없으면

- `syncMainCanvasInteractionState()`
- navigation event emit 없이 종료

### 7.3 일반 포커스 이동이면

- `publishMainColumnFocusNavigationIntent(for: newID)`
- `syncMainCanvasInteractionState(emitNavigationEvent: true)`

여기서부터 horizontal / vertical scroll 파이프라인이 각각 반응한다.

---

## 8. horizontal canvas 반응

메인 캔버스 가로 스크롤은 `MainCanvasHost`가 담당한다.

트리거:
- `viewState.focusNavigationTick` 변화
- `viewState.navigationSettleTick`
- `viewState.pendingRestoreRequest`

포커스 이동 시:

1. `handleActiveCardIDChange(_:)`
2. `syncMainCanvasInteractionState(emitNavigationEvent: true)`
3. `mainCanvasViewState.focusNavigationTargetID = activeCardID`
4. `mainCanvasViewState.focusNavigationTick += 1`
5. `MainCanvasHost.onChange(of: viewState.focusNavigationTick)`
6. `handleMainCanvasActiveCardChange(...)`
7. `scrollToColumnIfNeeded(...)`

`handleMainCanvasActiveCardChange(...)` 안에서는:

- focus mode면 skip
- pending editing sibling target이면 skip
- `suppressHorizontalAutoScroll`이면 skip
- `suppressAutoScrollOnce`면 1회 skip
- click focus target이면 별도 정렬
- 그 외엔 일반 active-card 기준으로 가로 스크롤

`scrollToColumnIfNeeded(...)`는:

- target card가 있는 level 계산
- scroll mode가 `.oneStep` / `.twoStep`인지 반영
- native horizontal scroll 가능하면 직접 적용
- 아니면 `ScrollViewProxy.scrollTo(level, anchor:)`

반복 입력 뒤에는 settle 경로가 한 번 더 돈다.

- `registerHandledMainArrowNavigation(...)`
- `scheduleMainArrowNavigationSettle()`
- 0.08초 후 `.settleRecovery` intent 발행
- 동시에 `mainNavigationSettleTick += 1`
- host의 `onNavigationSettle`가 `handleMainCanvasNavigationSettle(...)`
- 최종 `scrollToColumnIfNeeded(... force: true, animated: false)`

---

## 9. vertical column 반응

세로 정렬은 column별 vertical `ScrollView`가 따로 소비한다.

핵심 레이어:
- `MainCanvasScrollCoordinator.NavigationIntent`
- `navigationIntentTick`
- `handleMainColumnNavigationIntent(...)`

### 9.1 intent 발행

포커스 이동 시 발행되는 대표 intent:

- `focusChange`
- `settleRecovery`
- `childListChange`
- `columnAppear`
- `bottomReveal`

발행 함수:
- `publishMainColumnNavigationIntent(...)`
- `publishMainColumnFocusNavigationIntent(...)`

### 9.2 각 컬럼이 intent 소비

각 column view는:

- `.onChange(of: mainCanvasScrollCoordinator.navigationIntentTick)`

에서 `handleMainColumnNavigationIntent(...)`를 호출한다.

이 함수는 intent 종류에 따라:

- `handleMainColumnActiveFocusChange(...)`
- `handleMainColumnNavigationSettle(...)`
- `handleMainColumnImmediateAlignmentIntent(...)`
- `handleMainColumnBottomRevealIntent(...)`

로 분기한다.

### 9.3 `handleMainColumnActiveFocusChange(...)`

이 함수는 현재 column이 아래 중 하나를 포함할 때만 반응한다.

- active card 자체
- active ancestor
- active card의 preferred descendant target

여기서 추가로 계산한다.

- tall card top reveal 필요 여부
- editing-driven keep-visible 여부
- descendant focus일 때 coalescing delay
- animation 사용 여부
- vertical scroll authority

그 후 `scheduleMainColumnActiveCardFocus(...)`를 예약한다.

### 9.4 `scrollToFocus(...)`

세로 이동의 핵심 결정 함수다.

이 함수는:

- 실제 target card 결정
- tall card면 top anchor 사용
- keep-visible vs alignment 결정
- editing reveal edge 적용
- 요청 dedupe
- visible/aligned 여부 판단
- native scroll vs proxy scroll 결정
- verification 예약

까지 담당한다.

실행 분기:

- `applyMainColumnFocusAlignment(...)`
- `applyMainColumnFocusVisibility(...)`

native 가능 시:
- `performMainColumnNativeFocusScroll(...)`
- `performMainColumnNativeVisibilityScroll(...)`

fallback:
- `ScrollViewProxy.scrollTo(targetID, anchor: ...)`

### 9.5 authority와 verification

세로 이동은 무조건 “누가 현재 이 viewport를 움직일 권한이 있는가”를 체크한다.

authority 종류:
- `columnNavigation`
- `editingTransition`
- `caretEnsure`
- `viewportRestore`

발급:
- `beginMainVerticalScrollAuthority(...)`

검증:
- `scheduleMainColumnFocusVerification(...)`

verification work item은 일정 시간 뒤:

- observed frame 존재 여부
- target visible 여부
- target aligned 여부

를 다시 확인한다.

안 맞으면:
- request cache를 지우고
- scroll을 다시 한 번 수행하고
- 최대 2~4회 재시도한다.

즉 메인 column 세로 정렬은 “바로 끝”이 아니라 verification이 붙은 비동기 체인이다.

---

## 10. editing card 변경 후 이어지는 일

boundary navigation이나 Enter 편집 진입으로 `editingCardID`가 바뀌면 `handleEditingCardIDChange(oldID:newID:)`가 반응한다.

공통 처리:
- `persistLastEditedCard(newID)`
- 필요 시 `persistLastFocusSnapshot(...)`
- edit-end auto-backup 예약/취소 상태 갱신
- scenario timestamp suppression 갱신
- `clearMainEditTabArm()`
- typing coalescing finalize / reset
- old card caret 위치 기억

새 editing target이 생기면:

- main selection bookkeeping reset
- `mainLastCommittedContentByCard[newID] = card.content`
- boundary navigation 여부 확인
- `restoreMainEditingCaret(...)`
- `scheduleMainEditorLineSpacingApplyBurst(...)`
- 필요 시 0.03초 후 `normalizeMainEditorTextViewOffsetIfNeeded(... reason: "edit-change")`

여기서 caret restore는 한 번이 아니다.

- `requestMainCaretRestore(...)`
- 즉시 1회
- 0.08초 후 한 번 더
- 내부적으로 0.016초 간격 재시도

즉 responder가 늦게 붙는 경우까지 고려해 retry가 이미 들어가 있다.

---

## 11. selection / caret monitor 후속 처리

메인 편집 selection 변화는 `startMainCaretMonitor()`가 받는다.

source:
- `NSTextView.didChangeSelectionNotification`

파이프라인:

1. `handleMainSelectionDidChange(_:)`
2. `resolveMainSelectionChangeContext(...)`
3. `shouldIgnoreMainProgrammaticSelection(...)`
4. `updateMainSelectionActiveEdge(...)`
5. duplicate 아니면 `persistMainSelection(...)`
6. 필요 시 `applyMainEditorLineSpacingIfNeeded()`
7. `normalizeMainEditorTextViewOffsetIfNeeded(... reason: "selection-change")`
8. marked text 아니면 `requestCoalescedMainCaretEnsure(...)`

여기서 저장되는 것:

- `mainSelectionLastCardID`
- `mainSelectionLastLocation`
- `mainSelectionLastLength`
- `mainSelectionLastTextLength`
- `mainSelectionLastResponderID`
- `mainCaretLocationByCardID`

즉 카드 전환 직후의 programmatic caret apply와, 사용자가 직접 caret를 움직인 이후의 위치 기억이 모두 이 계층으로 수렴한다.

### 11.1 programmatic selection suppression

클릭 편집 시작이나 explicit caret restore는 selection notification을 그대로 믿지 않는다.

사용 상태:
- `mainProgrammaticCaretSuppressEnsureCardID`
- `mainProgrammaticCaretExpectedCardID`
- `mainProgrammaticCaretExpectedLocation`
- `mainProgrammaticCaretSelectionIgnoreUntil`

의도:
- “내가 방금 프로그래밍적으로 caret를 여기로 옮겼다”는 사실을 잠깐 기억
- 그 직후 들어오는 selection change를 중복 side effect 없이 흡수

### 11.2 caret ensure

`requestCoalescedMainCaretEnsure(...)`는 최소 interval을 적용해 ensure를 coalesce한다.

최종 실행:
- `ensureMainCaretVisible()`

여기서는:

- outer scroll view를 찾고
- caret rect / selection rect를 계산하고
- 현재 viewport와 top/bottom padding을 반영해
- vertical scroll authority를 `caretEnsure`로 잡고
- 필요한 경우 실제 column scroll을 미세 조정한다

즉 editing 중엔 카드 포커스 정렬과 별개로 caret visibility가 계속 후속 보정된다.

---

## 12. line spacing / inner scroll normalization

editing target이 바뀌거나 selection/content가 변하면 line spacing 재적용이 붙는다.

핵심 함수:
- `applyMainEditorLineSpacingIfNeeded(...)`
- `scheduleMainEditorLineSpacingApplyBurst(...)`

이 계층은 다음을 보장하려고 한다.

- `NSTextView`가 가로 리사이즈 모드로 흐트러지지 않음
- inner scroll view의 origin이 0으로 유지됨
- text container width가 main canvas width 규칙과 맞음
- paragraph style / typing attributes line spacing이 일치함

`normalizeMainEditorTextViewOffsetIfNeeded(...)`는 아래 상황에서 반복 호출된다.

- `selection-change`
- `content-change`
- `ensure-visible`
- `caret-restore`
- `edit-change`

의도:
- textView 내부 scroll origin이 틀어져 outer viewport와 서로 싸우지 않게 정리

---

## 13. editing 종료 시 포커스 이동과 이어지는 일

화살표 자체는 아니지만, 화살표 경계 이동 과정에서 `finishEditing()`가 끼는 경우가 많다.

`finishEditing()` 경로:

1. `takeFinishEditingContext()`
2. focus mode 여부 / main focus restore skip 여부 계산
3. main mode면 `rememberMainCaretLocation(for:)`
4. `resetEditingTransientState()`
5. `commitFinishedEditingIfNeeded(...)`
6. `restoreMainFocusAfterFinishEditingIfNeeded(...)`

빈 카드면:
- archive/delete 분기
- active card가 그 카드였다면 다음 focus target 재선정
- `suppressAutoScrollOnce = true`
- `suppressHorizontalAutoScroll = true`

비어 있지 않으면:
- undo push
- linked-card edit recording
- save / snapshot

편집 종료 후 텍스트 mutation이 있었으면:
- `scheduleEditEndAutoBackup()`
- 3초 뒤 workspace compressed backup 시도

---

## 14. per-key 요약

### idle `Up`
- 이전 sibling 또는 cross-category boundary target
- `changeActiveCard`
- vertical intent 발행
- horizontal canvas level 이동

### idle `Down`
- 다음 sibling
- 마지막 카드이면서 tall card면 `bottomReveal`
- 아니면 cross-category boundary target

### idle `Left`
- parent로 즉시 이동

### idle `Right`
- child가 있으면 즉시 child
- 없으면 1회 arm, 2회에 nearby sibling child fallback

### editing `Up`
- caret가 top boundary일 때만 이전 카드
- target caret는 끝

### editing `Down`
- caret가 bottom boundary일 때만 다음 카드
- target caret는 시작

### editing `Left`
- top boundary + parent 존재
- 첫 눌림 arm
- 두 번째 눌림에서 parent 이동

### editing `Right`
- bottom boundary
- 첫 눌림 arm
- 두 번째 눌림에서 child 또는 fallback child 이동

### `Shift + arrow`
- idle면 range selection 확장
- editing boundary면 `finishEditing()` 후 selection-only 이동

---

## 15. 실제 함수 체인 예시

### 15.1 idle 상태에서 `Down`으로 포커스 이동

1. `mainNavKeyMonitor`
2. `handleNavigationKeyCode(125, ...)`
3. `performMainArrowNavigation(.down, ...)`
4. `changeActiveCard(to: target, deferToMainAsync: false)`
5. `registerHandledMainArrowNavigation(...)`
6. `MainCanvasNavigationDiagnostics.beginFocusIntent(...)`
7. `handleActiveCardIDChange(target.id)`
8. `publishMainColumnFocusNavigationIntent(...)`
9. `syncMainCanvasInteractionState(emitNavigationEvent: true)`
10. `MainCanvasHost.onChange(of: focusNavigationTick)`
11. `handleMainCanvasActiveCardChange(...)`
12. `scrollToColumnIfNeeded(...)`
13. 각 column의 `onChange(of: navigationIntentTick)`
14. `handleMainColumnNavigationIntent(...)`
15. `handleMainColumnActiveFocusChange(...)`
16. `scheduleMainColumnActiveCardFocus(...)`
17. `scrollToFocus(...)`
18. `applyMainColumnFocusAlignment(...)` 또는 native scroll
19. `scheduleMainColumnFocusVerification(...)`

### 15.2 editing 상태에서 `Down`으로 다음 카드로 넘어감

1. `onKeyPress`
2. `handleGlobalKeyPress(_:)`
3. `handleTypingContextShortcut(...)`
4. `handleMainEditorBoundaryNavigation(...)`
5. `focusCaretVisualBoundaryState(...)`
6. `handleMainBoundaryDownArrow(...)`
7. `switchMainEditingTarget(...)`
8. `changeActiveCard(... shouldFocusMain: false, deferToMainAsync: false)`
9. `editingCardID = target.id`
10. `handleActiveCardIDChange(target.id)`
11. sibling boundary 이동이면 일반 navigation event 일부 생략
12. `handleEditingCardIDChange(oldID:newID:)`
13. `restoreMainEditingCaret(...)`
14. `requestMainCaretRestore(...)`
15. selection notification
16. `handleMainSelectionDidChange(...)`
17. `requestCoalescedMainCaretEnsure(...)`
18. `ensureMainCaretVisible()`

---

## 16. diagnostics와 side effect

포커스 이동에는 로그/사운드/복원 상태까지 묶여 있다.

### 16.1 diagnostics

`MainCanvasNavigationDiagnostics`가 추적한다.

- focus intent 시작/종료
- relation sync 시간
- column layout resolve 시간
- vertical/horizontal native vs fallback scroll count
- verification retry count
- workspace disappear summary

즉 화살표 이동 하나가 끝나면 relation sync와 scroll 계층까지 진단 로그에 반영된다.

### 16.2 경계 사운드

이동이 막히는 경우:

- boundary에 더 갈 곳이 없음
- 깊은 level에서 cross-category rapid burst 억제

`playMainBoundaryFeedbackIfNeeded(...)`가 `/System/Library/Sounds/Pop.aiff`를 재생한다.

중복 재생 방지용 게이트:
- `mainBoundaryFeedbackCardID`
- `mainBoundaryFeedbackKeyCode`

### 16.3 persistence

포커스 이동만으로도 다음 복원 정보들이 바뀐다.

- `lastActiveCardID`
- `lastEditedCardID`
- `lastFocusedCardID`
- `lastFocusedCaretLocation`
- split pane별 active card
- parent의 `lastSelectedChildID`
- `mainCaretLocationByCardID`

즉 현재 포커스 이동은 다음 진입/복원 동작의 입력 상태를 동시에 갱신한다.

---

## 17. 해석상 중요한 포인트

### 17.1 편집 중 boundary navigation은 repeat보다 down 중심

`handleTypingContextShortcut(...)`가 boundary navigation을 `press.phase == .down`일 때만 호출한다.

그래서 helper 내부에 `isRepeat` 인자가 있어도, main editor boundary 경로에서는 실제로 repeat가 크게 의미를 가지지 않는 구간이 있다.

### 17.2 editing sibling navigation은 일반 active-card scroll과 다르게 취급된다

`pendingMainEditingSiblingNavigationTargetID`가 켜져 있으면:

- `handleActiveCardIDChange(_:)`가 일반 navigation emit을 줄이고
- horizontal auto align도 억제하고
- editing card 교체 + caret restore 중심으로 흐른다

즉 “카드 포커스 이동”처럼 보이지만 내부적으로는 “편집 세션의 sibling hop”으로 따로 취급된다.

### 17.3 메인 컬럼 세로 정렬은 즉시 완료가 아니다

`scrollToFocus(...)` 이후에도:

- verification work item
- observed frame 확인
- retry scroll

이 연쇄적으로 붙는다.

즉 한 번의 포커스 이동은 동기 state change + 비동기 정렬 보정까지 포함한 lifecycle이다.
