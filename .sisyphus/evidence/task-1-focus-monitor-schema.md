# Focus Monitor Event Schema Contract

## Base Fields (all events)
- `seq`: monotonic sequence number
- `ts`: ISO-8601 timestamp
- `event`: stable event name
- `reason`: trigger reason (or `n/a`)

## State Snapshot Fields
- `showFocusMode`
- `activeCardID`
- `editingCardID`
- `focusModeEditorCardID`
- `isRecording`

## Width/Measurement Fields
- `measuredCardWidth`
- `horizontalInset`
- `textEditorMeasureWidth`
- `focusModeFontSize`
- `focusModeLineSpacing`

## Height Decision Fields
- `deterministicBodyHeight`
- `observedBodyHeight`
- `resolvedBodyHeight`
- `drift`

## NSTextView Geometry Fields
- `textContainerInset`
- `lineFragmentPadding`
- `containerSizeWidth`
- `viewportWidth`
- `widthTracksTextView`
- `heightTracksTextView`
- `contentInsets`

## Normalization Fields
- `includeActive`
- `force`
- `scanned`
- `reset`
- `skippedActive`
- `observedUpdates`

## Caret/Selection Fields
- `selectedLocation`
- `selectedLength`
- `textLength`
- `isDuplicateSelection`
- `typingElapsed`
- `didScroll`

## Required Event Names
- `focus.toggle`
- `focus.activeCard.change`
- `focus.panel.frame.change`
- `focus.card.width.measure`
- `focus.card.height.resolve`
- `focus.geometry.apply`
- `focus.normalization.request`
- `focus.normalization.run`
- `focus.selection.change`
- `focus.caret.ensure.schedule`
- `focus.caret.ensure.run`
- `focus.caret.visible`
