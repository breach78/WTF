# Main Workspace Vertical Scroll Map

This document tracks every known element that affects vertical scrolling in the main workspace.

Scope:
- Main workspace only
- Vertical scrolling only
- Excludes focus mode unless it directly affects main workspace behavior

Goals:
- Keep a single reference before changing scroll behavior
- Reduce accidental regressions from overlapping scroll authorities
- Update this document whenever main-workspace scroll logic changes

Current architecture note:

- Main-workspace vertical scroll now uses explicit authority ownership per viewport.
- The intended separation is:
  - non-editing card navigation: column navigation authority
  - editing caret movement: caret-ensure authority
  - startup / focus-exit viewport restore: viewport-restore authority
  - explicit editing boundary reveal: editing-transition authority
- Verification should finalize only against observed frames, not keep re-driving predicted-layout corrections.

## 1. Low-Level Vertical Scroll Executors

These functions directly move an `NSScrollView`.

- `wa/WriterSharedTypes.swift`
  - `CaretScrollCoordinator.applyVerticalScrollIfNeeded(...)`
  - `CaretScrollCoordinator.applyAnimatedVerticalScrollIfNeeded(...)`
- `wa/WriterCardManagement.swift`
  - `performMainColumnNativeFocusScroll(...)`
  - `performMainColumnNativeVisibilityScroll(...)`
- `wa/WriterCaretAndScroll.swift`
  - `applyMainCaretScrollPositionIfNeeded(...)`

## 2. Main Workspace Column Surface

Each vertical column is built here:

- `wa/WriterCardManagement.swift`
  - `column(for:level:parent:screenHeight:)`

Inside this column view, these hooks can trigger vertical movement:

- `onChange(of: mainCanvasScrollCoordinator.navigationIntentTick)`
- `onChange(of: activeCardID)` for click-focus alignment
- `onChange(of: childListSignature)`
- `onAppear`
- `onChange(of: mainBottomRevealTick)`
- `onPreferenceChange(MainColumnCardFramePreferenceKey.self)`
- `mainColumnScrollObserver(...)`

The actual scroll container is:

- `ScrollView(.vertical, showsIndicators: false)`
- `LazyVStack(spacing: 0)`

## 3. Navigation Intent Layer

Main intent owner:

- `wa/MainCanvasScrollCoordinator.swift`

Key types and methods:

- `NavigationIntentKind`
  - `focusChange`
  - `settleRecovery`
  - `childListChange`
  - `columnAppear`
  - `bottomReveal`
- `publishIntent(...)`
- `consumeLatestIntent(for:)`
- `isIntentCurrent(...)`
- `navigationIntentTick`

Main workspace publishers:

- `wa/WriterCardManagement.swift`
  - `publishMainColumnNavigationIntent(...)`
  - `publishMainColumnFocusNavigationIntent(...)`

Main workspace consumer:

- `wa/WriterCardManagement.swift`
  - `handleMainColumnNavigationIntent(...)`

## 4. Main Column Focus / Visibility Logic

Core scroll decision function:

- `wa/WriterCardManagement.swift`
  - `scrollToFocus(...)`

This function decides:

- target card
- alignment vs keep-visible
- top-anchor behavior for tall cards
- editing reveal edge
- forced alignment
- request dedupe
- verification scheduling

Execution branches:

- `applyMainColumnFocusAlignment(...)`
- `applyMainColumnFocusVisibility(...)`

Important helpers:

- `handleMainColumnActiveFocusChange(...)`
- `handleMainColumnImmediateAlignmentIntent(...)`
- `handleMainColumnBottomRevealIntent(...)`
- `handleMainColumnNavigationSettle(...)`

## 5. Geometry and Layout Authority

Observed geometry:

- `wa/MainCanvasScrollCoordinator.swift`
  - `MainColumnGeometryModel`
  - `updateObservedFrames(...)`
  - `observedFrame(for:viewportKey:cardID:)` via `observedFrame(for: cardID:)`

Preference collection:

- `wa/WriterCardManagement.swift`
  - `GeometryReader` in each observed card row
  - `MainColumnCardFramePreferenceKey`

Predicted layout:

- `wa/WriterCardManagement.swift`
  - `resolvedMainColumnLayoutSnapshot(...)`
  - `resolvedMainColumnTargetLayout(...)`
  - `predictedMainColumnTargetFrame(...)`

Observed vs predicted frame consumers:

- `resolvedMainColumnFocusTargetOffset(...)`
- `resolvedMainColumnVisibilityTargetOffset(...)`
- `isObservedMainColumnFocusTargetVisible(...)`
- `isObservedMainColumnFocusTargetAligned(...)`

Important note:

- Main workspace vertical behavior uses both observed frames and predicted layout snapshots.
- Any mismatch between them can create drift, retries, or visible nudges.

## 6. Visibility / Alignment Heuristics

Important policy helpers:

- `wa/WriterCardManagement.swift`
  - `shouldSkipMainColumnFocusScroll(...)`
  - `shouldPreserveMainColumnViewportOnReveal(...)`
  - `shouldAutoAlignMainColumn(...)`
  - `resolvedMainColumnFocusTargetID(...)`
  - `resolvedMainColumnCurrentOffsetY(...)`
  - `resolvedMainColumnVisibleRect(...)`

Important constants embedded in logic:

- default alignment anchor: `y = 0.4`
- top anchor for tall cards
- visibility inset: derived from viewport height
- editing bottom padding in visibility logic: `120`

## 7. Verification / Retry Layer

Main verification function:

- `wa/WriterCardManagement.swift`
  - `scheduleMainColumnFocusVerification(...)`

Behavior:

- runs after initial scroll
- checks observed visibility/alignment
- can retry by re-running alignment or visibility scroll
- uses different timing for animated vs non-animated paths

Related cancellation:

- `cancelPendingMainColumnFocusWorkItem(...)`
- `cancelPendingMainColumnFocusVerificationWorkItem(...)`
- `cancelAllPendingMainColumnFocusWork()`

Important note:

- This layer is one of the most common sources of "final nudge" or late correction.

## 8. Live Viewport Capture / Persistence / Restore

Live capture:

- `wa/WriterCardManagement.swift`
  - `mainColumnScrollObserver(...)`
  - `suspendMainColumnViewportCapture(for:)`
- `wa/WriterSharedTypes.swift`
  - `MainColumnScrollViewAccessor`

Stored state:

- `mainColumnViewportOffsetByKey`
- `mainColumnViewportCaptureSuspendedUntil`
- `mainColumnViewportRestoreUntil`

Restore and persistence:

- `wa/WriterViews.swift`
  - `restoreStartupViewportIfNeeded()`
  - `applyStoredMainColumnViewportOffsets(...)`
  - `persistCurrentViewportSnapshotIfPossible()`

Important note:

- This is a separate scroll authority from focus alignment.
- Startup and restore behavior can fight with active-card-driven scrolling if not coordinated.

## 9. Active Card Change as an Upstream Trigger

Main upstream function:

- `wa/WriterViews.swift`
  - `handleActiveCardIDChange(_:)`

This function can indirectly cause vertical motion by:

- clearing focus-request cache
- setting restore windows for root transitions
- synchronizing relation state
- publishing focus navigation intent
- syncing main-canvas interaction state

Important note:

- If `activeCardID` changes, vertical motion may occur even when no direct scroll call was made nearby.

## 10. Editing-Mode-Specific Vertical Influences

Main editing transition function:

- `wa/WriterViews.swift`
  - `handleEditingCardIDChange(oldID:newID:)`

This can trigger:

- `restoreMainEditingCaret(...)`
- `scheduleMainEditorLineSpacingApplyBurst(...)`
- delayed `normalizeMainEditorTextViewOffsetIfNeeded(..., reason: "edit-change")`
- `requestCoalescedMainCaretEnsure(...)`

Editing boundary-navigation state:

- `pendingMainEditingSiblingNavigationTargetID`
- `pendingMainEditingBoundaryNavigationTargetID`

Editing target switcher:

- `wa/WriterKeyboardHandlers.swift`
  - `switchMainEditingTarget(...)`

Important note:

- Editing-mode vertical behavior is not only column alignment.
- Caret restore and editor normalization can also move the outer viewport.

## 11. Main Caret Monitor and Outer Scroll

Main caret monitor:

- `wa/WriterCaretAndScroll.swift`
  - `startMainCaretMonitor()`
  - `handleMainSelectionDidChange(_:)`
  - `requestMainCaretEnsure(...)`
  - `requestCoalescedMainCaretEnsure(...)`
  - `ensureMainCaretVisible()`

Caret geometry / viewport helpers:

- `resolveMainCaretSelectionRects(...)`
- `resolveMainCaretViewportContext(...)`
- `resolveMainCaretTargetY(...)`

Editor normalization:

- `normalizeMainEditorTextViewOffsetIfNeeded(...)`
- `normalizeMainEditorInnerScrollView(...)`

Programmatic caret restore:

- `requestMainCaretRestore(...)`
- `restoreMainEditingCaret(...)`
- `applyMainCaretWithRetry(...)`

Important note:

- This path can move the main workspace even when column-level alignment is suppressed.

## 12. Important Main Workspace Scroll State

Stored in interaction/runtime state:

- `pendingMainClickFocusTargetID`
- `pendingMainEditingSiblingNavigationTargetID`
- `pendingMainEditingBoundaryNavigationTargetID`
- `mainBottomRevealTick`
- `mainColumnLastFocusRequestByKey`
- `mainColumnViewportOffsetByKey`
- `mainColumnObservedCardFramesByKey`
- `mainColumnLayoutSnapshotByKey`
- `mainColumnPendingFocusVerificationWorkItemByKey`
- `mainColumnViewportCaptureSuspendedUntil`
- `mainColumnViewportRestoreUntil`

Caret-related state:

- `mainSelectionObserver`
- `mainCaretEnsureWorkItem`
- `mainCaretEnsureLastScheduledAt`
- `mainProgrammaticCaretSuppressEnsureCardID`
- `mainProgrammaticCaretExpectedCardID`
- `mainProgrammaticCaretExpectedLocation`
- `mainProgrammaticCaretSelectionIgnoreUntil`

## 13. Highest-Risk Overlap Points

These are the places most likely to create unstable vertical movement:

- `activeCardID` change triggers column focus alignment
- column lifecycle triggers:
  - `childListChange`
  - `columnAppear`
  - `bottomReveal`
- `scrollToFocus(...)` chooses alignment or keep-visible
- `scheduleMainColumnFocusVerification(...)` retries later
- caret ensure runs after editing transitions
- viewport restore applies stored offsets at startup or restore windows

If behavior looks random, the cause is often not one function but overlap between two or more of these layers.

## 14. Vertical Scroll Authority

Authority state lives in:

- `wa/WriterSharedTypes.swift`
  - `MainVerticalScrollAuthorityKind`
  - `MainVerticalScrollAuthority`
  - `WriterInteractionRuntime.mainVerticalScrollAuthoritySequence`
  - `WriterInteractionRuntime.mainVerticalScrollAuthorityByViewportKey`

Authority helpers live in:

- `wa/WriterCardManagement.swift`
  - `beginMainVerticalScrollAuthority(...)`
  - `isMainVerticalScrollAuthorityCurrent(...)`
  - `resolvedMainColumnViewportKey(forCardID:)`

Authority kinds:

- `columnNavigation`
- `editingTransition`
- `caretEnsure`
- `viewportRestore`

Operational rule:

- Only one vertical authority should be considered current per viewport.
- Late verification or delayed work from an older authority must not re-apply scroll after a newer authority has taken ownership.

## 15. Observed-Frame Finalization Rule

Main rule:

- Predicted layout is allowed to help realize an offscreen target.
- Final success / correction should depend on observed frame geometry.

Current implementation point:

- `wa/WriterCardManagement.swift`
  - `scheduleMainColumnFocusVerification(...)`

Expected behavior:

- if target frame is not yet observed:
  - wait / reschedule
  - do not keep issuing predicted-layout correction scrolls as if they were authoritative
- once observed frame exists:
  - visibility and alignment checks can decide whether to finish or correct

## 16. Working Rules Before Changing Main Vertical Scroll

Before changing behavior:

1. Identify which authority is supposed to own the move:
   - column alignment
   - keep-visible
   - caret ensure
   - viewport restore
2. Confirm whether the target uses observed frame or predicted layout.
3. Check whether verification retry is still active.
4. Check whether editing-mode caret restore is also scheduled.
5. Check whether viewport capture/restore windows are active.
6. Check whether `activeCardID` change will publish a second motion path.

## 17. Update Protocol For This File

Whenever main-workspace vertical scroll logic changes:

- update affected functions in this file
- update any new state variables
- note any removed scroll authority
- keep the "Highest-Risk Overlap Points" section current

Do not treat this file as architecture prose.
Treat it as the operational map for debugging and modifying main-workspace vertical scrolling.
