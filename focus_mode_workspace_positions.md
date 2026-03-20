# Focus Mode And Main Workspace Positions

## Scope

This document tracks what happens to the original main-workspace card layout and viewport positions when focus mode enters and exits.

It answers four concrete questions:

1. What happens to the visible main-workspace card columns when focus mode enters?
2. Where do the main-workspace horizontal and vertical positions go while focus mode is active?
3. What survives only as runtime state, and what is also persisted?
4. How are those positions reconstructed when focus mode exits?

Phase 3 note:

After the retained-shell change, the main workspace shell is no longer fully unmounted on focus-mode entry.

Current state is:

- main canvas remains mounted underneath focus mode
- it becomes visually hidden and non-interactive while focus mode is active
- legacy restore requests still exist on focus exit as a fallback / compatibility path

Phase 5 note:

- main-workspace horizontal persistence no longer falls back to the entry snapshot during focus mode
- the retained shell's live horizontal offset is now the normal source of truth
- `focusModeEntryWorkspaceSnapshot.mainCanvasHorizontalOffset` remains only for fallback exit restore semantics


## Short Answer

The original main-workspace cards still do **not** become focus-mode cards, but the main workspace shell is now retained underneath focus mode instead of being fully removed from the view tree.

When `showFocusMode` becomes `true`, the app overlays the focus-mode canvas on top of the retained main canvas shell. The main-workspace layout is still preserved indirectly through state:

- consolidated entry snapshot:
  - `focusModeEntryWorkspaceSnapshot`
- per-column vertical offsets:
  - `mainColumnViewportOffsetByKey`
- active/editing/caret identity:
  - `activeCardID`
  - `editingCardID`
  - `selectedCardIDs`
  - `mainCaretLocationByCardID`

On focus-mode exit, the app makes the retained main canvas visible and interactive again. Legacy restore logic still exists, but it is now used as a fallback only when the retained shell is not sufficiently attached.


## Visible View Branch Before And After Entry

### Before Entry

The main workspace is visible through:

- `workspaceLayout(for:)`
- `primaryWorkspaceColumn(size:availableWidth:)`
- `mainCanvasWithOptionalZoom(size:availableWidth:)`

Relevant file:

- `/Users/three/app_build/wa/wa/WriterViews.swift`

In this state, the visible main-workspace columns are the actual live `ScrollView` and `LazyVStack` hierarchy of the main canvas.

### After Entry

Inside `primaryWorkspaceColumn(size:availableWidth:)`, the app now keeps:

- `mainCanvasWithOptionalZoom(size:availableWidth:)`

mounted at all times inside the same `ZStack`.

When `showFocusMode == true`:

- the main canvas stays mounted underneath
- its opacity becomes `0`
- hit testing is disabled
- accessibility is hidden
- `focusModeCanvas(size:)` is rendered above it

So the main-workspace card columns are no longer visible or interactive, but the shell is still mounted.

They are not moved into focus mode; they remain as a retained hidden layer below the focus-mode viewport.


## Entry Pipeline

## 1. Toggle Starts

Focus mode entry starts in:

- `toggleFocusMode()`

File:

- `/Users/three/app_build/wa/wa/WriterFocusMode.swift`

When entering:

- `resolveFocusModeEntryTargetCard()` chooses the target card using:
  - `editingCardID`
  - else `activeCardID`
  - else `scenario.rootCards.first`

## 2. Main Canvas Horizontal Position Is Captured

Before the visible branch switches, `enterFocusMode(with:)` calls:

- `captureFocusModeEntryWorkspaceSnapshot()`

This stores a single `FocusModeWorkspaceSnapshot` in:

- `focusModeEntryWorkspaceSnapshot`

Its main-workspace position payload includes:

- `visibleMainCanvasLevel`
- `mainCanvasHorizontalOffset`
- `mainColumnViewportOffsets`
- `activeCardID`
- `editingCardID`
- `selectedCardIDs`

How it is computed:

- Prefer current visible level from real main-canvas horizontal scroll position
- Else fall back to the active card’s displayed level
- Else fall back to `lastScrolledLevel`
- Exact horizontal offset comes from `mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalOffset()`

Files:

- `/Users/three/app_build/wa/wa/WriterFocusMode.swift`
- `/Users/three/app_build/wa/wa/WriterCardManagement.swift`

## 3. Main Canvas Vertical Positions Are Not Re-captured Here

Unlike horizontal position, focus-mode entry does **not** create a special new vertical snapshot.

Instead, the app relies on the existing runtime map:

- `mainColumnViewportOffsetByKey`

This dictionary already tracks the last known vertical offset for each main-workspace column viewport.

Storage owner:

- `WriterInteractionRuntime.mainColumnViewportOffsetByKey`

Files:

- `/Users/three/app_build/wa/wa/WriterSharedTypes.swift`
- `/Users/three/app_build/wa/wa/WriterViews.swift`

Meaning:

- the main-workspace vertical layout does not “go into focus mode”
- it remains remembered in runtime as per-column offsets

## 4. Active / Editing / Caret State Is Moved Into Focus Mode State

Still in `enterFocusMode(with:)`, the app calls:

- `beginFocusModeEditing(target, cursorToEnd: false)`

This is where semantic ownership changes:

- `activeCardID` is aligned to the focus target
- `editingCardID` becomes the focus-mode editing card
- `focusModeEditorCardID` is established
- focus-mode caret hint may be consumed
- selection is prepared for the focus editor

This is not the main-workspace layout itself. It is the semantic editing/focus identity that will drive the new focus-mode view.

File:

- `/Users/three/app_build/wa/wa/WriterFocusMode.swift`

## 5. The Visible Branch Switches

After entry preparation, `applyFocusModeVisibilityState(entering: true)` sets:

- `showFocusMode = true`
- hides timeline / history / AI chat
- updates `focusModeWindowBackgroundActive`

At this moment:

- the focus-mode layer becomes the visible foreground canvas
- the original main-workspace shell remains mounted underneath but hidden/inert

Files:

- `/Users/three/app_build/wa/wa/WriterFocusMode.swift`
- `/Users/three/app_build/wa/wa/WriterViews.swift`
- `/Users/three/app_build/wa/wa/waApp.swift`


## Where The Original Main-Workspace Positions Go During Focus Mode

## Horizontal

The main-workspace horizontal position is represented inside:

- `focusModeEntryWorkspaceSnapshot.visibleMainCanvasLevel`
- `focusModeEntryWorkspaceSnapshot.mainCanvasHorizontalOffset`

These are dedicated entry snapshots for later restoration.

## Vertical

The main-workspace vertical position stays in:

- `mainColumnViewportOffsetByKey`

This is a per-column offset map keyed by viewport identity.

That means the original main-workspace columns are not kept alive as visible scroll views in focus mode, but their last known vertical offsets remain cached in runtime memory.

## Caret / Active Identity

The identity of “where the user was working” remains in:

- `activeCardID`
- `editingCardID`
- `selectedCardIDs`
- `mainCaretLocationByCardID`

Those are not layout coordinates, but they are part of reconstructing the same workspace context later.


## Runtime-Only Versus Persisted State

## Runtime-Only During The Session

These are the most important runtime-only carriers for the hidden main workspace:

- `focusModeEntryWorkspaceSnapshot`
- `mainColumnViewportOffsetByKey`
- `mainCanvasScrollCoordinator` live scroll-view attachments

These survive mode switches within the running app session, and now coexist with a retained hidden main-workspace shell.

## Persisted Snapshots

The app also persists workspace-position-related state:

- `lastFocusedViewportOffsetsJSON`
- `lastFocusedMainCanvasHorizontalOffsetsJSON`
- `lastFocusedScenarioID`
- `lastFocusedCardID`
- `lastFocusedCaretLocation`
- `lastFocusedWasEditing`
- `lastFocusedWasFocusMode`

Important detail:

When `persistCurrentViewportSnapshotIfPossible()` runs while focus mode is active, the horizontal persistence path now reads the retained main-workspace shell's live horizontal offset directly.

`focusModeEntryWorkspaceSnapshot.mainCanvasHorizontalOffset` still exists, but only as fallback exit-restore payload when the retained shell cannot be reused.

File:

- `/Users/three/app_build/wa/wa/WriterViews.swift`


## Exit Pipeline

## 1. Focus Mode Begins Teardown

Focus mode exit starts in:

- `exitFocusMode()`

Current behavior includes:

- opening the focus-mode exit teardown gate
- clearing focus-entry hints
- calling `finishEditing()`
- clearing `focusModeEditorCardID`
- clearing focus boundary arm state

File:

- `/Users/three/app_build/wa/wa/WriterFocusMode.swift`

## 2. The Visible Foreground Layer Switches Back

`applyFocusModeVisibilityState(entering: false)` sets:

- `showFocusMode = false`

As soon as this happens:

- the retained `mainCanvasWithOptionalZoom(size:availableWidth:)` becomes visible and interactive again
- the `focusModeCanvas(size:)` overlay disappears

So the original main-workspace shell is no longer reconstructed from nothing. It is already mounted and simply re-exposed.

However, legacy restore logic still exists after exit, so the current code is in a mixed state:

- retained shell is now the primary structure
- restore replay still exists as a fallback compatibility path

## 3. Main Monitors Restart And Fallback Restore Is Considered

Inside `handleShowFocusModeChange(false)` the app:

- finalizes focus typing
- clears focus-mode search UI
- stops focus-mode monitors
- restarts main nav / caret monitors
- first checks whether the retained main-canvas shell can be reused directly
- if yes:
  - clears pending main-canvas restore work
  - clears pending main-column focus work
- if no:
  - calls:
    - `requestMainCanvasRestoreForFocusExit(using:)`
    - `requestMainCanvasViewportRestoreForFocusExit(using:)`

Files:

- `/Users/three/app_build/wa/wa/WriterViews.swift`
- `/Users/three/app_build/wa/wa/WriterCardManagement.swift`

## 4. Horizontal Main-Canvas Position Is Reconstructed Only As Fallback

`requestMainCanvasRestoreForFocusExit(using:)` does this:

- chooses target card from:
  - `activeCardID`
  - else `editingCardID`
  - else `lastActiveCardID`
  - else first root card
- reads `snapshot.visibleMainCanvasLevel`
- enqueues a semantic restore request

Later, `restoreMainCanvasPositionIfNeeded(proxy:availableWidth:)` consumes that request:

- if a `visibleLevel` exists, it performs semantic horizontal restore to that level
- else it falls back to card-driven main-canvas horizontal scrolling

Meaning:

- in the fallback path, the app does not ask “where was the hidden main canvas view object”
- it asks “what semantic horizontal level did we capture before focus mode”

## 5. Vertical Main-Canvas Positions Are Re-applied Only As Fallback

`requestMainCanvasViewportRestoreForFocusExit(using:)`:

- reads `snapshot.mainColumnViewportOffsets`
- schedules retries
- calls `applyStoredMainColumnViewportOffsets(...)`

`applyStoredMainColumnViewportOffsets(...)`:

- iterates the stored per-column offsets
- reattaches to real main-canvas scroll views if available
- applies vertical scroll positions directly

Meaning:

- in the fallback path, the main-workspace vertical positions “come back” from the cached per-column offset map
- in the primary retained-shell path, they simply remain where the hidden shell already was


## What Does Not Happen

Several things are important precisely because they do **not** happen.

### The Original Main-Workspace Cards Do Not Become Focus-Mode Cards

Focus mode does not visually reuse the main-workspace column layout.

It uses a different canvas:

- `focusModeCanvas(size:)`

That canvas is driven by:

- `focusedColumnCards()`
- focus-mode editor state

### The Main Canvas Is Not Restored From A Single Exact Live View Object

The app does not keep one universal “frozen main canvas object” and then simply unhide it later.

Instead, it reconstructs the visible main-workspace placement from:

- semantic horizontal snapshot
- exact horizontal offset snapshot or persistence fallback
- per-column vertical offset map
- active/editing identity

### Card Tree Order Does Not Change On Focus Entry / Exit

Focus mode entry/exit does not move cards in the scenario model.

What changes is:

- the visible branch
- editing owner
- viewport restore state

The underlying scenario card tree remains the same.


## Practical Fragility Points

This is the part most likely to create bugs.

## 1. Branch Swap And View Attachment Timing

The main workspace becomes visible again before every real scroll view is guaranteed to be fully attached.

That is why exit restoration still uses:

- restore requests
- retries
- delayed reapplication of offsets

## 2. Horizontal Restore Is Partly Semantic

Exit restore prefers:

- `focusModeEntryMainCanvasVisibleLevel`

This is robust for “which area of the card tree was visible”, but it is not identical to keeping a live scroll object alive.

## 3. Vertical Restore Depends On Cached Offset Maps

If `mainColumnViewportOffsetByKey` is stale or a viewport key changes, the main-workspace vertical placement can come back imperfectly.

## 4. Persistence And Runtime Snapshots Are Separate

There are two different concepts:

- runtime state for immediate exit restoration
- persisted state for app relaunch restoration

They are related, but not identical.


## State Inventory

### Main Workspace Layout Preservation

- `focusModeEntryWorkspaceSnapshot`
- `mainColumnViewportOffsetByKey`
- `mainCanvasScrollCoordinator`

### Editing / Focus Identity Preservation

- `activeCardID`
- `editingCardID`
- `focusModeEditorCardID`
- `selectedCardIDs`
- `mainCaretLocationByCardID`

### Persistence

- `lastFocusedViewportOffsetsJSON`
- `lastFocusedMainCanvasHorizontalOffsetsJSON`
- `lastFocusedScenarioID`
- `lastFocusedCardID`
- `lastFocusedCaretLocation`
- `lastFocusedWasEditing`
- `lastFocusedWasFocusMode`


## Bottom Line

When focus mode enters, the original main-workspace card layout does not physically travel into focus mode.

Instead:

- the visible main-workspace branch is replaced by the focus-mode branch
- the previous main-workspace layout is remembered through runtime and persisted state
- on exit, the main-workspace branch becomes visible again
- then its horizontal and vertical placement is reconstructed from those stored values

So the answer to “where do the original cards and positions go?” is:

- the cards remain in the scenario model
- the visible main-workspace branch is hidden
- the positions survive as state, not as a visible retained layout
