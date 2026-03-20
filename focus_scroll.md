# Focus Mode Scroll Map

This document tracks every known element that affects scrolling in focus mode.

Scope:
- Focus mode only
- Primarily vertical scrolling
- Includes card switching, caret visibility, inner text-view normalization, and fallback reveal
- Excludes main-workspace scrolling unless it directly participates in focus-mode entry or exit

Goals:
- Keep a single reference before changing focus-mode scroll behavior
- Reduce accidental regressions from overlapping scroll owners
- Update this document whenever focus-mode scroll logic changes

Current architecture note:

- Focus mode does not currently have a single scroll authority.
- At minimum, these layers can move or correct scroll state:
  - canvas active-card scroll via `ScrollViewProxy`
  - preserved-viewport card switching
  - outer caret keep-visible scroll
  - typewriter-mode caret scroll
  - inner `NSTextView` scroll-origin normalization
  - programmatic caret retry and fallback reveal
- This is the main reason focus-mode scroll behavior is hard to reason about.

Current refactor note:

- A first ownership split is now implemented in code:
  - `canvasNavigation`
  - `boundaryTransition`
  - `caretEnsure`
  - `fallbackReveal`
- This does not eliminate every correction layer, but it makes late async scroll callbacks check whether they are still the current owner before acting.
- A second reduction is also implemented:
  - bulk focus-mode normalization burst is removed
  - scroll-wheel-ended normalization is disabled
  - offset normalization now behaves as active-editor hygiene instead of a general late scroll correction path
- Boundary transition policy is now narrower:
  - edge-reveal state is only armed when the current caret is actually near the viewport edge
  - fallback reveal is not armed for ordinary mid-viewport card switches
- Post-switch success authority is now stronger:
  - switching to a different focus-mode card marks that card as awaiting a fresh live editor layout commit
  - programmatic caret retry does not spend retry budget while that live layout commit is still pending
  - boundary fallback reveal also waits for the same live layout window before firing
- Entry / exit lifecycle cleanup is also in place:
  - initial focus-mode canvas alignment is now owned by `focusModeCanvas(...)` `onAppear`
  - `focusModeEntryScrollTick` has been retired
  - retained main-workspace shell persistence now reads live horizontal offset instead of an entry-snapshot fallback

## 1. Low-Level Scroll Executors

These functions directly move either the outer focus-mode scroll view or an inner AppKit text-view scroll surface.

- `wa/WriterFocusMode.swift`
  - `performFocusModeCanvasActiveCardScroll(...)`
    - uses `ScrollViewProxy.scrollTo(...)`
  - `handleFocusModeCanvasAppear(...)`
    - uses `proxy.scrollTo(...)`
  - `handleFocusModeFallbackRevealTickChange(...)`
    - uses `proxy.scrollTo(...)`
  - `handleFocusModeBoundsDidChange(...)`
    - forces inner `NSClipView` origin to `.zero`
  - `resetFocusModeTextViewScrollOriginIfNeeded(...)`
    - forces inner `NSClipView` origin to `.zero`
  - `normalizeSingleTextEditorOffsetIfNeeded(...)`
    - forces inner `NSClipView` origin to `.zero`
  - `applyFocusModeCaretScrollPositionIfNeeded(...)`
    - uses `CaretScrollCoordinator.applyVerticalScrollIfNeeded(...)`

Important implementation note:

- `outerScrollView(containing:)` must treat the nearest enclosing scroll view as the outer focus canvas when the editor is hosted directly, and only climb past it when that nearest scroll view is an internal text-editor scroll surface.

Important note:

- Focus mode has both an outer scroll executor and an inner scroll-origin reset path.
- Those are separate systems with separate triggers.

## 2. Focus-Mode Canvas Surface

The focus-mode scroll container is built here:

- `wa/WriterFocusMode.swift`
  - `focusModeCanvas(size:)`

Important hooks on this surface:

- `onChange(of: activeCardID)`
  - `handleFocusModeCanvasActiveCardChange(...)`
- `onAppear`
  - `handleFocusModeCanvasAppear(...)`
- `onChange(of: focusModeFallbackRevealTick)`
  - `handleFocusModeFallbackRevealTickChange(...)`
- `onChange(of: size.width)`
  - `handleFocusModeCanvasWidthChange(...)`

Important structural note:

- Focus mode uses `ScrollView(.vertical)` + `ScrollViewReader` + `LazyVStack`.
- This means card materialization and editor availability are not guaranteed at the same time as `activeCardID` changes.

## 3. Active-Card Canvas Scroll Path

Primary card-level scroll path:

- `wa/WriterFocusMode.swift`
  - `handleFocusModeCanvasActiveCardChange(...)`
  - `handleFocusModeSuppressedScrollIfNeeded(...)`
  - `performFocusModeCanvasActiveCardScroll(...)`
  - `scheduleFocusModeCanvasActiveCardBeginEditingIfNeeded(...)`

Behavior:

- `activeCardID` changes can:
  - scroll the canvas to the new card
  - suppress that scroll once
  - immediately begin editing the card
  - schedule an offset-normalization burst

Important note:

- This path is not just “scroll to active card”.
- It also mutates editor state and queues later normalization work.

## 4. Key-Driven Boundary Navigation

Card-to-card caret navigation enters here:

- `wa/WriterFocusMode.swift`
  - `handleFocusModeArrowNavigation(...)`
  - `focusModeArrowBoundaryState(...)`
  - `consumeFocusModeArrowNavigationWithoutBoundary()`
  - `performFocusModeArrowBoundaryTransition(...)`

Boundary-switch behavior:

- Detects `up/down` boundary at caret `0` or `textLength`
- Switches target card
- Sets excluded responder state
- invalidates previous caret request IDs
- marks pending fallback reveal
- calls `beginFocusModeEditing(... preserveViewportOnSwitch: true)`

Important note:

- Boundary navigation is not a pure caret operation.
- It is a combined transition policy:
  - preserve viewport
  - switch card
  - re-home responder
  - later re-apply caret
  - possibly fall back to explicit reveal

## 5. Inner Text-Editor Normalization Layer

These functions try to keep focus-mode `NSTextView` instances in a geometry state that prevents internal jolts.

- `wa/WriterFocusMode.swift`
  - `startFocusModeScrollMonitor()`
  - `createFocusModeScrollWheelMonitor()`
  - `handleFocusModeScrollWheelEvent(...)`
  - `createFocusModeBoundsObserver()`
  - `handleFocusModeBoundsDidChange(...)`
  - `isFocusModeInternalTextEditorScrollView(...)`
  - `applyFocusModeTextViewGeometryIfNeeded(...)`
  - `applyFocusModeInnerScrollViewGeometryIfNeeded(...)`
  - `normalizeInactiveFocusModeTextEditorOffsets(...)`
  - `normalizeFocusModeTextViews(...)`
  - `resetFocusModeTextViewScrollOriginIfNeeded(...)`
  - `requestFocusModeOffsetNormalization(...)`
  - `scheduleFocusModeOffsetNormalizationBurst(...)`

What this layer does:

- disables inner scrollers
- zeroes content insets
- forces clip-view origins back to zero
- reapplies text-container width and typography
- runs immediate normalization
- runs burst normalization after delays

Important note:

- This layer is a separate correction system from outer caret scroll.
- It exists because focus mode uses AppKit editors inside a SwiftUI scroll surface.

## 6. Caret Monitor and Outer Keep-Visible Scroll

Selection-driven focus-mode scroll enters here:

- `wa/WriterFocusMode.swift`
  - `startFocusModeCaretMonitor()`
  - `handleFocusModeSelectionNotification(...)`
  - `processFocusModeSelectionNotification(...)`
  - `scheduleFocusCaretEnsureForSelectionChange()`
  - `requestFocusModeCaretEnsure(...)`
  - `executeFocusModeCaretEnsureWork(...)`
  - `ensureFocusModeCaretVisible(typewriter:)`
  - `resolveFocusModeCaretEnsureContext()`
  - `resolveFocusModeSelectionRects(...)`
  - `resolveFocusModeCaretViewportContext(...)`
  - `resolveFocusModeCaretTargetY(...)`
  - `resolveFocusModeStandardCaretTargetY(...)`
  - `resolveFocusModeCollapsedSelectionTargetY(...)`
  - `applyFocusModeCaretScrollPositionIfNeeded(...)`

Behavior:

- listens to `NSTextView.didChangeSelectionNotification`
- debounces ensure scheduling
- bypasses the normal debounce when a collapsed caret has already entered the configured edge margin
- in that edge-margin case, the ensure now runs immediately instead of being queued as another cancelable work item
- re-applies text-view geometry before scrolling
- keeps the caret visible in the outer focus-mode scroll view
- collapsed caret keep-visible now uses the same symmetric viewport margin as the standard selection path (`140px` top and bottom)

Important note:

- This is another full scroll owner, independent from card-level `proxy.scrollTo(...)`.

## 7. Typewriter Layer

Typewriter mode overlays special caret targeting on top of standard caret visibility.

- `wa/WriterFocusMode.swift`
  - `handleFocusTypewriterCaretShortcut(...)`
  - `requestFocusModeCaretEnsure(typewriter:...)`
  - `resolvedFocusModeCaretEnsureTypewriterMode(...)`
  - `resolveFocusModeTypewriterTargetYIfNeeded(...)`

Behavior:

- ordinary selection changes use standard keep-visible
- typewriter-triggered changes can instead move the caret toward a baseline fraction of the viewport
- composition state can defer typewriter execution

Important note:

- This means the caret layer itself has two target policies, not one.

## 8. Programmatic Caret Placement, Retry, and Fallback Reveal

Programmatic card-entry and boundary-entry selection restore uses a separate retry path.

- `wa/WriterFocusMode.swift`
  - `beginFocusModeEditing(...)`
  - `prepareFocusModeBeginEditingCaret(...)`
  - `configureFocusModeProgrammaticCaretExpectation(...)`
  - `scheduleFocusModeBeginEditingCaretApplications(...)`
  - `scheduleFocusModeCaretEnsureBurst()`
  - `applyFocusModeCaretWithRetry(...)`
  - `resolvedFocusModeCaretRetryTextView(...)`
  - `handleFocusModeCaretRetryWithResponder(...)`
  - `handleFocusModeCaretRetryWithoutResponder(...)`
  - `requestFocusModeBoundaryFallbackRevealIfNeeded(...)`
  - `scheduleFocusModeCaretRetry(...)`
  - `applyFocusModeCaretSelection(...)`

Behavior:

- sets expected card and expected caret location
- opens an ignore window for transient wrong selections
- retries responder lookup multiple times
- retries when responder content is stale
- retries when responder-card mapping is stale
- emits fallback reveal if no responder appears
- schedules extra ensure bursts after some entry paths

Important note:

- This is effectively a third correction layer:
  - card switch
  - then programmatic caret restore
  - then fallback reveal if the restore path fails

## 9. Live Layout / Geometry Dependency

Focus mode also depends on live editor layout readiness:

- `wa/FocusModeLayoutCoordinator.swift`
  - `hasPendingLiveEditorLayoutCommit(for:)`
  - `reportLiveEditorLayout(...)`
  - `resolvedCardHeight(...)`
  - `resolvedClickCaretLocation(...)`
- `wa/WriterFocusMode.swift`
  - `shouldDeferFocusModeCaretEnsureForPendingLiveLayout(...)`
  - `observedFocusModeBodyHeight(for:)`

Behavior:

- caret ensure can delay itself until live editor layout commits
- card heights can come from cached measurement or live editor layout
- click-to-caret location is resolved through deterministic text measurement
- switching to a different card now explicitly requires a fresh live editor layout commit before post-switch retry/fallback paths are treated as final failures

Important note:

- This introduces another timing dependency:
  - card state can change
  - responder can change
  - layout may still be pending
  - caret ensure can reschedule itself while waiting

## 10. Focus-Mode Entry / Exit Lifecycle

Lifecycle hooks:

- `wa/WriterViews.swift`
  - `handleShowFocusModeChange(_:)`
- `wa/WriterFocusMode.swift`
  - `toggleFocusMode()`
  - `resolveFocusModeEntryTargetCard()`
  - `enterFocusMode(with:)`
  - `exitFocusMode()`

Entry behavior:

- stop main-workspace monitors
- start focus-mode key monitor
- start focus-mode scroll monitor
- start focus-mode caret monitor
- initial focus-mode canvas alignment occurs on `focusModeCanvas(...)` appear
- call `beginFocusModeEditing(...)`
- immediately schedule offset normalization and burst normalization

Exit behavior:

- stop focus-mode monitors
- restart main-workspace monitors
- request main-canvas restore

Important note:

- Focus-mode entry itself already queues multiple scroll-related operations before the user presses anything.

## 11. Runtime State That Directly Affects Scroll

Persistent runtime state:

- `wa/WriterSharedTypes.swift`
  - `pendingFocusModeEntryCaretHint`
  - `focusResponderCardByObjectID`
  - `focusLineSpacingAppliedCardID`
  - `focusLineSpacingAppliedValue`
  - `focusLineSpacingAppliedFontSize`
  - `focusLineSpacingAppliedResponderID`
  - `focusSelectionLastCardID`
  - `focusSelectionLastLocation`
  - `focusSelectionLastLength`
  - `focusSelectionLastTextLength`
  - `focusSelectionLastResponderID`
  - `focusCaretEnsureLastScheduledAt`
  - `focusProgrammaticCaretExpectedCardID`
  - `focusProgrammaticCaretExpectedLocation`
  - `focusProgrammaticCaretSelectionIgnoreUntil`
  - `focusOffsetNormalizationLastAt`

SwiftUI state:

- `wa/WriterViews.swift`
  - `focusModeScrollMonitor`
  - `suppressFocusModeScrollOnce`
  - `focusPendingProgrammaticBeginEditCardID`
  - `focusModeCaretRequestID`
  - `focusModeBoundaryTransitionPendingReveal`
  - `focusModePendingFallbackRevealCardID`
  - `focusModeFallbackRevealIssuedCardID`
  - `focusModeFallbackRevealTick`
  - `focusModeSelectionObserver`
  - `focusExcludedResponderObjectID`
  - `focusExcludedResponderUntil`
  - `focusCaretEnsureWorkItem`
  - `focusCaretPendingTypewriter`
  - `focusTypewriterDeferredUntilCompositionEnd`
  - `focusObservedBodyHeightByCardID`
  - `caretEnsureBurstWorkItems`
  - `focusOffsetNormalizationMinInterval`
  - `focusCaretSelectionEnsureMinInterval`
  - `focusTypewriterEnabled`
  - `focusTypewriterBaseline`

Important note:

- These states are not just passive storage.
- Many of them are effectively mini state machines that gate when scroll owners are allowed to act.

## 12. Highest-Risk Overlap Zones

The most overlap-prone sequences are:

1. `activeCardID` change
   - canvas scroll
   - begin-editing handoff
   - offset-normalization burst

2. boundary transition with `preserveViewportOnSwitch`
   - card changes without immediate canvas scroll
   - caret restore retries later
   - fallback reveal may still scroll

3. programmatic selection restore
   - selection-ignore window
   - responder mismatch retry
   - stale content retry
   - ensure burst

4. selection-change after programmatic restore
   - duplicate selection suppression
   - standard caret ensure
   - typewriter path
   - normalization request

5. scroll-wheel / bounds correction
   - user scroll ends
   - offset normalization runs
   - inner clip view is re-zeroed

These are the places where “one action becomes several scroll attempts”.

## 13. Why Focus-Mode Scroll Is Hard

The complexity is not caused by one bad heuristic. It comes from the combination of these structural factors:

### A. Multiple Scroll Owners

Focus mode has at least six independent scroll or scroll-correction owners:

- canvas card scroll
- preserved-viewport boundary switching
- outer caret ensure
- typewriter ensure
- inner text-view normalization
- programmatic retry / fallback reveal

Because each owner is valid in isolation, they are easy to add. Together they produce overlaps.

### B. Multiple Coordinate Systems

Focus mode mixes:

- card-level `ScrollViewReader` identity scrolling
- outer `NSScrollView` visible-rect math
- inner `NSTextView` clip-view origin resets
- layout-coordinator cached height and click-caret measurement

That means “where the card is”, “where the caret is”, and “where the text view thinks its origin is” are not the same coordinate system.

### C. Asynchronous Materialization

Focus mode uses:

- `LazyVStack`
- SwiftUI `activeCardID` changes
- AppKit responder handoff
- deferred layout commits

These events do not complete at the same moment.

So the code often has to do:

1. change card
2. wait for editor to exist
3. wait for responder to attach
4. wait for layout to commit
5. then apply caret

Retry logic appears because the system is staged, not atomic.

### D. Inner vs Outer Scroll Fighting

Focus mode explicitly fights `TextEditor` / `NSTextView` internal scrolling:

- internal clip-view origin is forced back to zero
- outer scroll view then tries to keep the caret visible

That means two different scroll surfaces are being controlled on purpose.

### E. Preserve-Viewport Policy Adds Another State Machine

`preserveViewportOnSwitch` is conceptually useful, but it means:

- card switch does not imply reveal
- reveal may happen later through caret ensure
- if caret restore fails, fallback reveal may happen later still

So a single boundary move becomes a multi-step policy negotiation.

## 14. What Would Actually Simplify It

The main simplification target is not “tune the thresholds more”.
The real simplification would be:

- one explicit focus-mode vertical scroll authority at a time
- one final coordinate system for success checks
- one boundary-transition policy
- inner text-view normalization separated from outer reveal logic

The most realistic reduction path would be:

1. split focus-mode scroll into explicit owners
   - card-navigation owner
   - caret-visibility owner
   - fallback-reveal owner

2. make card switching either:
   - preserve viewport only
   - or reveal target card only
   - but not both plus fallback plus ensure burst

3. treat inner `NSTextView` origin reset as editor hygiene, not as general scroll correction

4. let observed live editor layout be the only final authority for post-switch caret placement

Without that kind of ownership split, focus mode will keep needing ignore windows, retry loops, and late corrections.
