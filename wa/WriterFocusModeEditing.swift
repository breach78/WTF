import SwiftUI
import AppKit

extension ScenarioWriterView {

    func beginFocusModeEditing(
        _ card: SceneCard,
        cursorToEnd: Bool,
        cardScrollAnchor: UnitPoint? = nil,
        animatedScroll: Bool = true,
        preserveViewportOnSwitch: Bool = false,
        placeCursorAtStartWhenNoHint: Bool = true,
        allowPendingEntryCaretHint: Bool = true,
        explicitCaretLocation: Int? = nil
    ) {
        let switchingToDifferentCard = applyFocusModeBeginEditingCardTransition(
            card: card,
            cardScrollAnchor: cardScrollAnchor,
            animatedScroll: animatedScroll,
            preserveViewportOnSwitch: preserveViewportOnSwitch
        )
        let location = prepareFocusModeBeginEditingCaret(
            card: card,
            cursorToEnd: cursorToEnd,
            placeCursorAtStartWhenNoHint: placeCursorAtStartWhenNoHint,
            allowPendingEntryCaretHint: allowPendingEntryCaretHint,
            explicitCaretLocation: explicitCaretLocation,
            switchingToDifferentCard: switchingToDifferentCard,
            preserveViewportOnSwitch: preserveViewportOnSwitch
        )
        scheduleFocusModeBeginEditingCaret(
            cardID: card.id,
            location: location,
            cardScrollAnchor: cardScrollAnchor,
            preserveViewportOnSwitch: preserveViewportOnSwitch
        )
    }

    private func applyFocusModeBeginEditingCardTransition(
        card: SceneCard,
        cardScrollAnchor: UnitPoint?,
        animatedScroll: Bool,
        preserveViewportOnSwitch: Bool
    ) -> Bool {
        let switchingToDifferentCard = (editingCardID != card.id)
        prepareFocusModeForEditingSwitchIfNeeded(targetCardID: card.id)
        updateActiveCardForFocusModeEditing(
            card: card,
            cardScrollAnchor: cardScrollAnchor,
            animatedScroll: animatedScroll,
            preserveViewportOnSwitch: preserveViewportOnSwitch
        )
        syncFocusModeEditingState(card: card, switchingToDifferentCard: switchingToDifferentCard)
        return switchingToDifferentCard
    }

    private func prepareFocusModeBeginEditingCaret(
        card: SceneCard,
        cursorToEnd: Bool,
        placeCursorAtStartWhenNoHint: Bool,
        allowPendingEntryCaretHint: Bool,
        explicitCaretLocation: Int?,
        switchingToDifferentCard: Bool,
        preserveViewportOnSwitch: Bool
    ) -> Int? {
        let location = resolveFocusModeBeginEditingCaretLocation(
            card: card,
            cursorToEnd: cursorToEnd,
            placeCursorAtStartWhenNoHint: placeCursorAtStartWhenNoHint,
            allowPendingEntryCaretHint: allowPendingEntryCaretHint,
            explicitCaretLocation: explicitCaretLocation
        )
        configureFocusModeProgrammaticCaretExpectation(
            cardID: card.id,
            location: location,
            switchingToDifferentCard: switchingToDifferentCard,
            preserveViewportOnSwitch: preserveViewportOnSwitch,
            explicitCaretLocation: explicitCaretLocation
        )
        return location
    }

    private func scheduleFocusModeBeginEditingCaret(
        cardID: UUID,
        location: Int?,
        cardScrollAnchor: UnitPoint?,
        preserveViewportOnSwitch: Bool
    ) {
        focusModeCaretRequestStartedAt = Date()
        focusModeCaretRequestID += 1
        let requestID = focusModeCaretRequestID
        scheduleFocusModeBeginEditingCaretApplications(
            cardID: cardID,
            location: location,
            requestID: requestID,
            cardScrollAnchor: cardScrollAnchor,
            preserveViewportOnSwitch: preserveViewportOnSwitch
        )
    }

    private func prepareFocusModeForEditingSwitchIfNeeded(targetCardID: UUID) {
        if showFocusMode, activeCardID != nil, activeCardID != targetCardID {
            finalizeFocusTypingCoalescing(reason: "focus-card-switch")
        }
        clearFocusBoundaryArm()
        if showFocusMode, editingCardID != nil, editingCardID != targetCardID {
            commitFocusModeCardEditIfNeeded()
        } else if editingCardID != nil, editingCardID != targetCardID {
            finishEditing(reason: .transition)
        }
    }

    private func updateActiveCardForFocusModeEditing(
        card: SceneCard,
        cardScrollAnchor: UnitPoint?,
        animatedScroll: Bool,
        preserveViewportOnSwitch: Bool
    ) {
        if activeCardID != card.id {
            focusPendingProgrammaticBeginEditCardID = card.id
            if preserveViewportOnSwitch {
                suppressFocusModeScrollOnce = true
                focusModeNextCardScrollAnchor = nil
                focusModeNextCardScrollAnimated = true
            } else {
                focusModeNextCardScrollAnchor = cardScrollAnchor
                focusModeNextCardScrollAnimated = animatedScroll
            }
            changeActiveCard(to: card, deferToMainAsync: showFocusMode)
        } else if focusPendingProgrammaticBeginEditCardID == card.id {
            focusPendingProgrammaticBeginEditCardID = nil
        }
    }

    private func syncFocusModeEditingState(card: SceneCard, switchingToDifferentCard: Bool) {
        selectedCardIDs = [card.id]
        if switchingToDifferentCard {
            focusModeLayoutCoordinator.awaitFreshLiveEditorLayoutCommit(for: card.id)
            editingCardID = card.id
            editingStartContent = card.content
            editingStartState = captureScenarioState()
            editingIsNewCard = false
        }
        focusModeEditorCardID = card.id
        focusLastCommittedContentByCard[card.id] = card.content
    }

    private func resolveFocusModeBeginEditingCaretLocation(
        card: SceneCard,
        cursorToEnd: Bool,
        placeCursorAtStartWhenNoHint: Bool,
        allowPendingEntryCaretHint: Bool,
        explicitCaretLocation: Int?
    ) -> Int? {
        let length = (card.content as NSString).length
        if let explicitCaretLocation {
            return min(max(0, explicitCaretLocation), length)
        }
        if allowPendingEntryCaretHint,
           let hint = pendingFocusModeEntryCaretHint,
           hint.cardID == card.id {
            if showFocusMode {
                pendingFocusModeEntryCaretHint = nil
            }
            return min(max(0, hint.location), length)
        }
        if cursorToEnd { return length }
        return placeCursorAtStartWhenNoHint ? 0 : nil
    }

    private func configureFocusModeProgrammaticCaretExpectation(
        cardID: UUID,
        location: Int?,
        switchingToDifferentCard: Bool,
        preserveViewportOnSwitch: Bool,
        explicitCaretLocation: Int?
    ) {
        let shouldApplySelectionIgnoreWindow =
            switchingToDifferentCard || preserveViewportOnSwitch || explicitCaretLocation != nil
        if let location, shouldApplySelectionIgnoreWindow {
            focusProgrammaticCaretExpectedCardID = cardID
            focusProgrammaticCaretExpectedLocation = location
            let ignoreWindow = focusModeBoundaryTransitionPendingReveal ? 0.10 : 0.28
            focusProgrammaticCaretSelectionIgnoreUntil = Date().addingTimeInterval(ignoreWindow)
        } else {
            focusProgrammaticCaretExpectedCardID = nil
            focusProgrammaticCaretExpectedLocation = -1
            focusProgrammaticCaretSelectionIgnoreUntil = .distantPast
        }
    }

    private func scheduleFocusModeBeginEditingCaretApplications(
        cardID: UUID,
        location: Int?,
        requestID: Int,
        cardScrollAnchor: UnitPoint?,
        preserveViewportOnSwitch: Bool
    ) {
        guard let location else { return }

        applyFocusModeCaretWithRetry(expectedCardID: cardID, location: location, retries: 10, requestID: requestID)
        let isViewportPreservingBoundarySwitch = preserveViewportOnSwitch && cardScrollAnchor == nil
        let followupDelay = isViewportPreservingBoundarySwitch ? 0.05 : 0.08
        DispatchQueue.main.asyncAfter(deadline: .now() + followupDelay) {
            applyFocusModeCaretWithRetry(expectedCardID: cardID, location: location, retries: 4, requestID: requestID)
        }

        if cardScrollAnchor != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                applyFocusModeCaretWithRetry(expectedCardID: cardID, location: location, retries: 4, requestID: requestID)
            }
            scheduleFocusModeCaretEnsureBurst()
        }

        if cardScrollAnchor == nil && !preserveViewportOnSwitch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                applyFocusModeCaretWithRetry(expectedCardID: cardID, location: location, retries: 4, requestID: requestID)
            }
        }
    }

    func scheduleFocusModeCaretEnsureBurst() {
        for item in caretEnsureBurstWorkItems { item.cancel() }
        caretEnsureBurstWorkItems.removeAll()
        let delays: [Double] = [0.0, 0.22]
        for delay in delays {
            let work = DispatchWorkItem {
                requestFocusModeCaretEnsure(typewriter: false, delay: 0.0, reason: "ensure-burst")
            }
            caretEnsureBurstWorkItems.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    func handleFocusModeCardContentChange(cardID: UUID, oldValue: String, newValue: String) {
        guard canHandleFocusModeCardContentChange(cardID: cardID, oldValue: oldValue, newValue: newValue) else { return }
        clearPersistentFocusModeSearchHighlight()
        markEditingSessionTextMutation()
        guard syncFocusModeContentChangeEditorOffsetIfNeeded() else { return }

        let delta = utf16ChangeDelta(oldValue: oldValue, newValue: newValue)
        if shouldSuppressFocusModeProgrammaticContentChange(cardID: cardID, newValue: newValue) { return }
        if isFocusModeResponderComposingText() { return }

        let now = Date()
        prepareFocusTypingCoalescingSessionIfNeeded(cardID: cardID, oldValue: oldValue, now: now)
        focusTypingLastEditAt = now
        focusLastCommittedContentByCard[cardID] = newValue
        scheduleFocusTypingIdleFinalize()
        refreshFocusModeSearchResultsIfNeeded()

        if shouldFinalizeFocusTypingForReturnBoundary(delta: delta) { return }
        finalizeFocusTypingForStrongBoundaryIfNeeded(newValue: newValue, delta: delta)
    }

    private func canHandleFocusModeCardContentChange(cardID: UUID, oldValue: String, newValue: String) -> Bool {
        guard showFocusMode else { return false }
        guard !isApplyingUndo else { return false }
        guard oldValue != newValue else { return false }
        guard cardID == (editingCardID ?? focusModeEditorCardID) else { return false }
        return true
    }

    private func syncFocusModeContentChangeEditorOffsetIfNeeded() -> Bool {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return true }
        guard !isReferenceTextView(textView) else { return false }
        normalizeSingleTextEditorOffsetIfNeeded(textView, reason: "content-change-sync")
        return true
    }

    private func shouldSuppressFocusModeProgrammaticContentChange(cardID: UUID, newValue: String) -> Bool {
        if Date() < focusProgrammaticContentSuppressUntil {
            focusLastCommittedContentByCard[cardID] = newValue
            return true
        }
        return false
    }

    func handleFocusSearchShortcut(
        _ event: NSEvent,
        flags: NSEvent.ModifierFlags
    ) -> Bool {
        guard isCommandOnlyFlags(flags) else { return false }
        let normalized = (event.charactersIgnoringModifiers ?? "").lowercased()
        let isFindShortcut = normalized == "f" || normalized == "ㄹ" || event.keyCode == 3
        guard isFindShortcut else { return false }
        DispatchQueue.main.async {
            if showFocusModeSearchPopup {
                closeFocusModeSearchPopup()
            } else {
                openFocusModeSearchPopup()
            }
        }
        return true
    }

    private func isFocusModeResponderComposingText() -> Bool {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            return textView.hasMarkedText()
        }
        return false
    }

    private func prepareFocusTypingCoalescingSessionIfNeeded(cardID: UUID, oldValue: String, now: Date) {
        let shouldBreakByGap = now.timeIntervalSince(focusTypingLastEditAt) > focusTypingIdleInterval
        let shouldBreakByCard = focusTypingCoalescingCardID != nil && focusTypingCoalescingCardID != cardID
        if shouldBreakByGap || shouldBreakByCard {
            finalizeFocusTypingCoalescing(reason: shouldBreakByCard ? "typing-card-switch" : "typing-gap")
        }

        if focusTypingCoalescingBaseState == nil {
            let committedOld = focusLastCommittedContentByCard[cardID] ?? oldValue
            focusTypingCoalescingBaseState = captureScenarioState(
                overridingContentForCardID: cardID,
                overridingContent: committedOld
            )
            focusTypingCoalescingCardID = cardID
        }
    }

    private func shouldFinalizeFocusTypingForReturnBoundary(
        delta: (prefix: Int, oldChangedLength: Int, newChangedLength: Int, inserted: String)
    ) -> Bool {
        guard focusPendingReturnBoundary else { return false }
        focusPendingReturnBoundary = false
        if delta.newChangedLength > 0 && delta.inserted.contains("\n") {
            finalizeFocusTypingCoalescing(reason: "typing-boundary-return")
            return true
        }
        return false
    }

    private func finalizeFocusTypingForStrongBoundaryIfNeeded(
        newValue: String,
        delta: (prefix: Int, oldChangedLength: Int, newChangedLength: Int, inserted: String)
    ) {
        if isStrongTextBoundaryChange(newValue: newValue, delta: delta) {
            finalizeFocusTypingCoalescing(reason: "typing-boundary")
        }
    }

    func handleFocusModeSelectionChanged() {
        guard showFocusMode else { return }

        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            guard !isReferenceTextView(textView) else { return }
            normalizeSingleTextEditorOffsetIfNeeded(textView, reason: "selection-change-sync")
        }

        guard focusTypingCoalescingBaseState != nil else { return }
        if Date().timeIntervalSince(focusTypingLastEditAt) > focusTypingIdleInterval {
            finalizeFocusTypingCoalescing(reason: "selection-change")
        }
    }

    func commitFocusModeCardEditIfNeeded() {
        guard showFocusMode else { return }
        guard let currentID = editingCardID, let currentCard = findCard(by: currentID) else { return }
        while currentCard.content.hasSuffix("\n") { currentCard.content.removeLast() }
        let changed = editingStartContent != currentCard.content
        guard changed else { return }
        focusLastCommittedContentByCard[currentID] = currentCard.content
        saveWriterChanges()
        takeSnapshot()
    }

    func applyFocusModeCaretWithRetry(expectedCardID: UUID, location: Int, retries: Int, requestID: Int) {
        guard !isFocusModeExitTeardownActive else { return }
        guard let expectedCard = resolveFocusModeCaretRetryExpectedCard(
            expectedCardID: expectedCardID,
            requestID: requestID
        ) else { return }
        if shouldWaitForFocusModeCaretRetryLiveLayout(
            expectedCardID: expectedCardID,
            location: location,
            retries: retries,
            requestID: requestID
        ) {
            return
        }
        if let textView = resolvedFocusModeCaretRetryTextView(expectedCardID: expectedCardID) {
            handleFocusModeCaretRetryWithResponder(
                textView: textView,
                expectedCard: expectedCard,
                expectedCardID: expectedCardID,
                location: location,
                retries: retries,
                requestID: requestID
            )
            return
        }
        handleFocusModeCaretRetryWithoutResponder(
            expectedCardID: expectedCardID,
            location: location,
            retries: retries,
            requestID: requestID
        )
    }

    private func resolvedFocusModeCaretRetryTextView(expectedCardID: UUID) -> NSTextView? {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           textView.isEditable,
           !isReferenceTextView(textView) {
            return textView
        }

        guard showFocusMode else { return nil }
        guard !isReferenceWindowFocused else { return nil }
        guard let root = NSApp.keyWindow?.contentView else { return nil }

        let editableTextViews = collectEditableFocusModeTextViews(root: root)
        guard !editableTextViews.isEmpty else { return nil }

        if let mapped = editableTextViews.first(where: { textView in
            focusResponderCardByObjectID[ObjectIdentifier(textView)] == expectedCardID
        }) {
            return mapped
        }

        if editableTextViews.count == 1 {
            return editableTextViews[0]
        }

        guard let expectedCard = findCard(by: expectedCardID) else { return nil }
        let matchingByContent = editableTextViews.filter { $0.string == expectedCard.content }
        if matchingByContent.count == 1 {
            return matchingByContent[0]
        }

        return nil
    }

    private func resolveFocusModeCaretRetryExpectedCard(
        expectedCardID: UUID,
        requestID: Int
    ) -> SceneCard? {
        guard showFocusMode else { return nil }
        guard editingCardID == expectedCardID else { return nil }
        guard requestID == focusModeCaretRequestID else { return nil }
        focusModeEditorCardID = expectedCardID
        return findCard(by: expectedCardID)
    }

    private func handleFocusModeCaretRetryWithResponder(
        textView: NSTextView,
        expectedCard: SceneCard,
        expectedCardID: UUID,
        location: Int,
        retries: Int,
        requestID: Int
    ) {
        let responderID = ObjectIdentifier(textView)
        if shouldRetryFocusModeCaretForResponder(
            textView: textView,
            responderID: responderID,
            expectedContent: expectedCard.content,
            expectedCardID: expectedCardID,
            location: location,
            retries: retries,
            requestID: requestID
        ) {
            return
        }
        applyFocusModeCaretSelection(
            textView: textView,
            responderID: responderID,
            expectedCardID: expectedCardID,
            requestedLocation: location,
            requestID: requestID
        )
    }

    private func shouldRetryFocusModeCaretForResponder(
        textView: NSTextView,
        responderID: ObjectIdentifier,
        expectedContent: String,
        expectedCardID: UUID,
        location: Int,
        retries: Int,
        requestID: Int
    ) -> Bool {
        if shouldRetryFocusModeCaretForExcludedResponder(
            responderID: responderID,
            expectedCardID: expectedCardID,
            location: location,
            retries: retries,
            requestID: requestID
        ) {
            return true
        }
        if shouldRetryFocusModeCaretForResponderCardMismatch(
            responderID: responderID,
            expectedCardID: expectedCardID,
            location: location,
            retries: retries,
            requestID: requestID
        ) {
            return true
        }
        return shouldRetryFocusModeCaretForStaleResponderContent(
            textView: textView,
            expectedContent: expectedContent,
            expectedCardID: expectedCardID,
            location: location,
            retries: retries,
            requestID: requestID
        )
    }

    private func handleFocusModeCaretRetryWithoutResponder(
        expectedCardID: UUID,
        location: Int,
        retries: Int,
        requestID: Int
    ) {
        if shouldWaitForFocusModeCaretRetryLiveLayout(
            expectedCardID: expectedCardID,
            location: location,
            retries: retries,
            requestID: requestID
        ) {
            return
        }
        requestFocusModeBoundaryFallbackRevealIfNeeded(expectedCardID: expectedCardID)
        guard retries > 0 else {
            completeFocusUndoSelectionEnsureIfNeeded(
                requestID: requestID,
                reason: "undo-restore-timeout",
                onMainAsync: false
            )
            return
        }
        scheduleFocusModeCaretRetry(
            expectedCardID: expectedCardID,
            location: location,
            retries: retries,
            requestID: requestID,
            delay: 0.02
        )
    }

    private func requestFocusModeBoundaryFallbackRevealIfNeeded(expectedCardID: UUID) {
        guard !isFocusModeExitTeardownActive else { return }
        guard focusModeBoundaryTransitionPendingReveal else { return }
        guard focusModePendingFallbackRevealCardID == expectedCardID else { return }
        guard focusModeFallbackRevealIssuedCardID != expectedCardID else { return }
        guard showFocusMode else { return }
        guard !shouldAwaitFocusModeLiveEditorLayoutCommit(for: expectedCardID) else { return }
        _ = beginFocusModeVerticalScrollAuthority(kind: .fallbackReveal, targetCardID: expectedCardID)
        focusModeFallbackRevealIssuedCardID = expectedCardID
        focusModeFallbackRevealTick += 1
    }

    private func shouldRetryFocusModeCaretForExcludedResponder(
        responderID: ObjectIdentifier,
        expectedCardID: UUID,
        location: Int,
        retries: Int,
        requestID: Int
    ) -> Bool {
        guard let excludedID = focusExcludedResponderObjectID else { return false }
        let isWithinExclusionWindow = Date() < focusExcludedResponderUntil
        if isWithinExclusionWindow && responderID == excludedID {
            scheduleFocusModeCaretRetry(
                expectedCardID: expectedCardID,
                location: location,
                retries: retries,
                requestID: requestID,
                delay: 0.012
            )
            return true
        }
        if !isWithinExclusionWindow || responderID != excludedID {
            clearFocusModeExcludedResponder()
        }
        return false
    }

    private func shouldRetryFocusModeCaretForResponderCardMismatch(
        responderID: ObjectIdentifier,
        expectedCardID: UUID,
        location: Int,
        retries: Int,
        requestID: Int
    ) -> Bool {
        guard let mappedCardID = focusResponderCardByObjectID[responderID], mappedCardID != expectedCardID else {
            return false
        }
        scheduleFocusModeCaretRetry(
            expectedCardID: expectedCardID,
            location: location,
            retries: retries,
            requestID: requestID,
            delay: 0.012
        )
        return true
    }

    private func shouldRetryFocusModeCaretForStaleResponderContent(
        textView: NSTextView,
        expectedContent: String,
        expectedCardID: UUID,
        location: Int,
        retries: Int,
        requestID: Int
    ) -> Bool {
        guard textView.string != expectedContent else { return false }
        scheduleFocusModeCaretRetry(
            expectedCardID: expectedCardID,
            location: location,
            retries: retries,
            requestID: requestID,
            delay: 0.02
        )
        return true
    }

    private func applyFocusModeCaretSelection(
        textView: NSTextView,
        responderID: ObjectIdentifier,
        expectedCardID: UUID,
        requestedLocation: Int,
        requestID: Int
    ) {
        let length = (textView.string as NSString).length
        let safe = max(0, min(requestedLocation, length))
        let targetSelection = NSRange(location: safe, length: 0)
        if textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        }
        if textView.selectedRange() != targetSelection {
            textView.setSelectedRange(targetSelection)
        }
        focusResponderCardByObjectID[responderID] = expectedCardID
        focusProgrammaticCaretExpectedCardID = expectedCardID
        focusProgrammaticCaretExpectedLocation = safe
        focusProgrammaticCaretSelectionIgnoreUntil = Date().addingTimeInterval(0.22)
        if focusModeBoundaryTransitionPendingReveal,
           focusModePendingFallbackRevealCardID == expectedCardID {
            focusModeBoundaryTransitionPendingReveal = false
            focusModePendingFallbackRevealCardID = nil
            focusModeFallbackRevealIssuedCardID = nil
            DispatchQueue.main.async {
                requestFocusModeCaretEnsure(
                    typewriter: false,
                    delay: 0.0,
                    force: true,
                    reason: "boundary-transition-selection"
                )
            }
        }
        if focusModePendingFallbackRevealCardID == expectedCardID {
            focusModePendingFallbackRevealCardID = nil
            focusModeFallbackRevealIssuedCardID = nil
        }
        clearFocusModeExcludedResponder()
        completeFocusUndoSelectionEnsureIfNeeded(
            requestID: requestID,
            reason: "undo-restore-responder",
            onMainAsync: true
        )
    }

    func clearFocusModeExcludedResponder() {
        focusExcludedResponderObjectID = nil
        focusExcludedResponderUntil = .distantPast
    }

    func scheduleFocusModeCaretRetry(
        expectedCardID: UUID,
        location: Int,
        retries: Int,
        requestID: Int,
        delay: Double,
        consumeRetryBudget: Bool = true
    ) {
        if consumeRetryBudget {
            guard retries > 0 else { return }
        }
        let nextRetries = consumeRetryBudget ? (retries - 1) : retries
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            applyFocusModeCaretWithRetry(
                expectedCardID: expectedCardID,
                location: location,
                retries: nextRetries,
                requestID: requestID
            )
        }
    }

    func completeFocusUndoSelectionEnsureIfNeeded(
        requestID: Int,
        reason: String,
        onMainAsync: Bool
    ) {
        guard focusUndoSelectionEnsureRequestID == requestID else { return }
        focusUndoSelectionEnsureRequestID = nil
        focusUndoSelectionEnsureSuppressed = false

        let ensure: () -> Void = {
            requestFocusModeCaretEnsure(typewriter: false, delay: 0.0, force: true, reason: reason)
        }
        if onMainAsync {
            DispatchQueue.main.async(execute: ensure)
        } else {
            ensure()
        }
    }
}
