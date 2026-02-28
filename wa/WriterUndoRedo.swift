import SwiftUI
import AppKit

extension ScenarioWriterView {

    struct CardState {
        let id: UUID
        let content: String
        let orderIndex: Int
        let createdAt: Date
        let parentID: UUID?
        let category: String?
        let isFloating: Bool
        let isArchived: Bool
        let lastSelectedChildID: UUID?
        let colorHex: String?
        let cloneGroupID: UUID?
    }

    struct ScenarioState {
        let cards: [CardState]
        let activeCardID: UUID?
        let activeCaretLocation: Int?
        let selectedCardIDs: [UUID]
        let changeCount: Int
    }

    func captureScenarioState(
        overridingContentForCardID overrideCardID: UUID? = nil,
        overridingContent overrideContent: String? = nil
    ) -> ScenarioState {
        let effectiveActiveCardID = pendingActiveCardID ?? activeCardID
        let activeCaretLocation: Int? = {
            guard let activeID = effectiveActiveCardID else { return nil }
            guard let activeCard = findCard(by: activeID) else { return nil }
            guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return nil }
            guard textView.string == activeCard.content else { return nil }
            let length = (textView.string as NSString).length
            return min(max(0, textView.selectedRange().location), length)
        }()
        let sourceCards = scenario.cards
        var cards: [CardState] = []
        cards.reserveCapacity(sourceCards.count)
        let hasOverride = overrideCardID != nil && overrideContent != nil
        for card in sourceCards {
            let content = (hasOverride && card.id == overrideCardID) ? (overrideContent!) : card.content
            cards.append(CardState(
                id: card.id,
                content: content,
                orderIndex: card.orderIndex,
                createdAt: card.createdAt,
                parentID: card.parent?.id,
                category: card.category,
                isFloating: card.isFloating,
                isArchived: card.isArchived,
                lastSelectedChildID: card.lastSelectedChildID,
                colorHex: card.colorHex,
                cloneGroupID: card.cloneGroupID
            ))
        }
        return ScenarioState(
            cards: cards,
            activeCardID: effectiveActiveCardID,
            activeCaretLocation: activeCaretLocation,
            selectedCardIDs: Array(selectedCardIDs),
            changeCount: scenario.changeCountSinceLastSnapshot
        )
    }

    func restoreScenarioState(_ state: ScenarioState) {
        isApplyingUndo = true
        let restoredCards = state.cards.map { s in
            SceneCard(
                id: s.id,
                content: s.content,
                orderIndex: s.orderIndex,
                createdAt: s.createdAt,
                parent: nil,
                scenario: nil,
                category: s.category,
                isFloating: s.isFloating,
                isArchived: s.isArchived,
                lastSelectedChildID: s.lastSelectedChildID,
                colorHex: s.colorHex,
                cloneGroupID: s.cloneGroupID
            )
        }
        var map: [UUID: SceneCard] = [:]
        map.reserveCapacity(restoredCards.count)
        for card in restoredCards {
            map[card.id] = card
        }
        for (idx, s) in state.cards.enumerated() {
            if let pid = s.parentID, let parent = map[pid] {
                restoredCards[idx].parent = parent
            }
        }
        for card in restoredCards {
            card.scenario = scenario
        }
        scenario.cards = restoredCards
        scenario.changeCountSinceLastSnapshot = state.changeCount
        scenario.bumpCardsVersion()
        let restoredSelection = Set(state.selectedCardIDs.filter { map[$0] != nil })
        selectedCardIDs = restoredSelection
        if let id = state.activeCardID, let active = map[id] {
            changeActiveCard(to: active, shouldFocusMain: false, deferToMainAsync: !isApplyingUndo, force: isApplyingUndo)
            if selectedCardIDs.isEmpty {
                selectedCardIDs = [active.id]
            }
        } else if showFocusMode,
                  let fallback = (lastActiveCardID.flatMap { map[$0] } ?? scenario.rootCards.first) {
            changeActiveCard(to: fallback, shouldFocusMain: false, deferToMainAsync: !isApplyingUndo, force: isApplyingUndo)
            if selectedCardIDs.isEmpty {
                selectedCardIDs = [fallback.id]
            }
        } else {
            activeCardID = nil
            activeAncestorIDs = []
            activeDescendantIDs = []
            activeSiblingIDs = []
        }
        if showFocusMode {
            focusLastCommittedContentByCard = Dictionary(uniqueKeysWithValues: scenario.cards.map { ($0.id, $0.content) })
            resetFocusTypingCoalescing()
        }
        store.saveAll()
        isApplyingUndo = false
    }

    func pushUndoState(_ previous: ScenarioState, actionName: String) {
        if isApplyingUndo { return }
        undoStack.append(previous)
        if undoStack.count > maxUndoCount {
            undoStack.removeFirst(undoStack.count - maxUndoCount)
        }
        redoStack.removeAll()
    }

    func pushMainTypingUndoState(_ previous: ScenarioState, actionName: String) {
        if isApplyingUndo { return }
        mainTypingUndoStack.append(previous)
        if mainTypingUndoStack.count > maxMainTypingUndoCount {
            mainTypingUndoStack.removeFirst(mainTypingUndoStack.count - maxMainTypingUndoCount)
        }
        mainTypingRedoStack.removeAll()
    }

    func scheduleMainTypingIdleFinalize() {
        mainTypingIdleFinalizeWorkItem?.cancel()
        let work = DispatchWorkItem {
            finalizeMainTypingCoalescing(reason: "typing-idle")
        }
        mainTypingIdleFinalizeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + focusTypingIdleInterval, execute: work)
    }

    func resetMainTypingCoalescing() {
        mainTypingIdleFinalizeWorkItem?.cancel()
        mainTypingIdleFinalizeWorkItem = nil
        mainTypingCoalescingBaseState = nil
        mainTypingCoalescingCardID = nil
        mainTypingLastEditAt = .distantPast
        mainPendingReturnBoundary = false
    }

    func finalizeMainTypingCoalescing(reason: String) {
        mainTypingIdleFinalizeWorkItem?.cancel()
        mainTypingIdleFinalizeWorkItem = nil
        guard let base = mainTypingCoalescingBaseState else { return }
        mainTypingCoalescingBaseState = nil
        mainTypingCoalescingCardID = nil
        pushMainTypingUndoState(base, actionName: "텍스트 편집(\(reason))")
    }

    func handleMainTypingContentChange(cardID: UUID, oldValue: String, newValue: String) {
        guard !showFocusMode else { return }
        guard !isApplyingUndo else { return }
        guard oldValue != newValue else { return }
        guard cardID == (editingCardID ?? focusModeEditorCardID) else { return }

        let delta = utf16ChangeDelta(oldValue: oldValue, newValue: newValue)
        if Date() < mainProgrammaticContentSuppressUntil {
            mainLastCommittedContentByCard[cardID] = newValue
            return
        }

        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           textView.hasMarkedText() {
            return
        }

        let now = Date()
        let shouldBreakByGap = now.timeIntervalSince(mainTypingLastEditAt) > focusTypingIdleInterval
        let shouldBreakByCard = mainTypingCoalescingCardID != nil && mainTypingCoalescingCardID != cardID
        if shouldBreakByGap || shouldBreakByCard {
            finalizeMainTypingCoalescing(reason: shouldBreakByCard ? "typing-card-switch" : "typing-gap")
        }

        if mainTypingCoalescingBaseState == nil {
            let committedOld = mainLastCommittedContentByCard[cardID] ?? oldValue
            mainTypingCoalescingBaseState = captureScenarioState(
                overridingContentForCardID: cardID,
                overridingContent: committedOld
            )
            mainTypingCoalescingCardID = cardID
        }

        mainTypingLastEditAt = now
        mainLastCommittedContentByCard[cardID] = newValue
        scheduleMainTypingIdleFinalize()

        if mainPendingReturnBoundary {
            mainPendingReturnBoundary = false
            if delta.newChangedLength > 0 && delta.inserted.contains("\n") {
                finalizeMainTypingCoalescing(reason: "typing-boundary-return")
                return
            }
        }

        if isStrongTextBoundaryChange(newValue: newValue, delta: delta) {
            finalizeMainTypingCoalescing(reason: "typing-boundary")
        }
    }

    func performMainTypingUndo() -> Bool {
        guard !showFocusMode else { return false }
        guard editingCardID != nil else { return false }
        finalizeMainTypingCoalescing(reason: "undo-request")
        guard let previous = mainTypingUndoStack.popLast() else {
            return true
        }
        let current = captureScenarioState()
        pendingMainUndoCaretHint = computeFocusUndoCaretHint(from: current, to: previous)
        mainProgrammaticContentSuppressUntil = Date().addingTimeInterval(0.4)
        mainTypingRedoStack.append(current)
        if mainTypingRedoStack.count > maxMainTypingUndoCount {
            mainTypingRedoStack.removeFirst(mainTypingRedoStack.count - maxMainTypingUndoCount)
        }
        restoreScenarioState(previous)
        restoreMainEditingContextAfterUndoRedo(restoredState: previous)
        return true
    }

    func performMainTypingRedo() -> Bool {
        guard !showFocusMode else { return false }
        guard editingCardID != nil else { return false }
        finalizeMainTypingCoalescing(reason: "redo-request")
        guard let next = mainTypingRedoStack.popLast() else {
            return true
        }
        let current = captureScenarioState()
        pendingMainUndoCaretHint = computeFocusUndoCaretHint(from: current, to: next)
        mainProgrammaticContentSuppressUntil = Date().addingTimeInterval(0.4)
        mainTypingUndoStack.append(current)
        if mainTypingUndoStack.count > maxMainTypingUndoCount {
            mainTypingUndoStack.removeFirst(mainTypingUndoStack.count - maxMainTypingUndoCount)
        }
        restoreScenarioState(next)
        restoreMainEditingContextAfterUndoRedo(restoredState: next)
        return true
    }

    func restoreMainEditingContextAfterUndoRedo(restoredState: ScenarioState) {
        guard !showFocusMode else { return }
        let resolvedCard: SceneCard? = {
            if let id = restoredState.activeCardID, let card = findCard(by: id) { return card }
            if let id = lastActiveCardID, let card = findCard(by: id) { return card }
            if let id = activeCardID, let card = findCard(by: id) { return card }
            return scenario.rootCards.first
        }()
        guard let card = resolvedCard else {
            editingCardID = nil
            pendingMainUndoCaretHint = nil
            resetMainTypingCoalescing()
            return
        }
        if activeCardID != card.id {
            changeActiveCard(to: card, shouldFocusMain: false, deferToMainAsync: false, force: true)
        }
        let id = card.id
        editingCardID = id
        editingStartContent = card.content
        editingStartState = captureScenarioState()
        editingIsNewCard = false
        mainLastCommittedContentByCard[id] = card.content
        resetMainTypingCoalescing()
        let length = (card.content as NSString).length
        let targetLocation: Int = {
            if let hint = pendingMainUndoCaretHint, hint.cardID == id {
                return min(max(0, hint.location), length)
            }
            if restoredState.activeCardID == id, let saved = restoredState.activeCaretLocation {
                return min(max(0, saved), length)
            }
            return length
        }()
        pendingMainUndoCaretHint = nil
        mainCaretLocationByCardID[id] = targetLocation
        mainCaretRestoreRequestID += 1
        let requestID = mainCaretRestoreRequestID
        applyMainCaretWithRetry(expectedCardID: id, location: targetLocation, retries: 12, requestID: requestID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            applyMainCaretWithRetry(expectedCardID: id, location: targetLocation, retries: 6, requestID: requestID)
        }
        requestCoalescedMainCaretEnsure(minInterval: mainCaretSelectionEnsureMinInterval, delay: 0.0)
    }

    func performMainTextUndoIfPossible() -> Bool {
        performMainTypingUndo()
    }

    func performMainTextRedoIfPossible() -> Bool {
        performMainTypingRedo()
    }

    func performUndo() {
        finishEditing()
        guard let previous = undoStack.popLast() else {
            return
        }
        let current = captureScenarioState()
        redoStack.append(current)
        restoreScenarioState(previous)
    }

    func performRedo() {
        finishEditing()
        guard let next = redoStack.popLast() else {
            return
        }
        let current = captureScenarioState()
        undoStack.append(current)
        if undoStack.count > maxUndoCount {
            undoStack.removeFirst(undoStack.count - maxUndoCount)
        }
        restoreScenarioState(next)
    }

    // MARK: - Focus Typing Coalescing

    func scheduleFocusTypingIdleFinalize() {
        focusTypingIdleFinalizeWorkItem?.cancel()
        let work = DispatchWorkItem {
            finalizeFocusTypingCoalescing(reason: "typing-idle")
        }
        focusTypingIdleFinalizeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + focusTypingIdleInterval, execute: work)
    }

    func resetFocusTypingCoalescing() {
        focusTypingIdleFinalizeWorkItem?.cancel()
        focusTypingIdleFinalizeWorkItem = nil
        focusTypingCoalescingBaseState = nil
        focusTypingCoalescingCardID = nil
        focusTypingLastEditAt = .distantPast
        focusPendingReturnBoundary = false
    }

    func finalizeFocusTypingCoalescing(reason: String) {
        focusTypingIdleFinalizeWorkItem?.cancel()
        focusTypingIdleFinalizeWorkItem = nil
        guard let base = focusTypingCoalescingBaseState else { return }
        focusTypingCoalescingBaseState = nil
        focusTypingCoalescingCardID = nil
        pushFocusUndoState(base, actionName: "텍스트 편집(\(reason))")
    }

    // MARK: - Text Boundary Detection

    func isStrongTextBoundaryChange(
        newValue: String,
        delta: (prefix: Int, oldChangedLength: Int, newChangedLength: Int, inserted: String)
    ) -> Bool {
        // Split boundaries:
        // 1) Enter when closing a non-empty line (paragraph boundary)
        // 2) Sentence-ending period (., 。) at sentence end
        // Blank-line enter is not a boundary.
        guard delta.newChangedLength > 0 else { return false }
        let newText = newValue as NSString

        if delta.inserted.contains("\n") {
            return containsParagraphBreakBoundary(in: newText, delta: delta)
        }

        return containsSentenceEndingPeriodBoundary(in: newText, delta: delta)
    }

    func containsParagraphBreakBoundary(
        in text: NSString,
        delta: (prefix: Int, oldChangedLength: Int, newChangedLength: Int, inserted: String)
    ) -> Bool {
        guard delta.newChangedLength > 0 else { return false }
        let start = delta.prefix
        let end = delta.prefix + delta.newChangedLength
        if start < 0 || end > text.length || start >= end { return false }

        var i = start
        while i < end {
            let unit = text.character(at: i)
            if unit == 10 || unit == 13 { // \n or \r
                if lineHasSignificantContentBeforeBreak(in: text, breakIndex: i) {
                    return true
                }
            }
            i += 1
        }
        return false
    }

    func lineHasSignificantContentBeforeBreak(in text: NSString, breakIndex: Int) -> Bool {
        guard breakIndex > 0 else { return false }
        var i = breakIndex - 1
        while i >= 0 {
            let unit = text.character(at: i)
            if unit == 10 || unit == 13 { // \n or \r
                return false
            }
            if let scalar = UnicodeScalar(unit),
               CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if i == 0 { break }
                i -= 1
                continue
            }
            return true
        }
        return false
    }

    func containsSentenceEndingPeriodBoundary(
        in text: NSString,
        delta: (prefix: Int, oldChangedLength: Int, newChangedLength: Int, inserted: String)
    ) -> Bool {
        guard delta.newChangedLength > 0 else { return false }
        let start = delta.prefix
        let end = delta.prefix + delta.newChangedLength
        if start < 0 || end > text.length || start >= end { return false }

        var i = start
        while i < end {
            let unit = text.character(at: i)
            if unit == 46 || unit == 12290 { // "." or "。"
                if isSentenceEndingPeriod(at: i, in: text) {
                    return true
                }
            }
            i += 1
        }
        return false
    }

    func isSentenceEndingPeriod(at index: Int, in text: NSString) -> Bool {
        // Decimal number (e.g. 3.14) should not split.
        if isDigitAtUTF16Index(text, index: index - 1) && isDigitAtUTF16Index(text, index: index + 1) {
            return false
        }

        // Next significant char determines sentence end.
        // Allow trailing spaces and closing quotes/brackets.
        var i = index + 1
        while i < text.length {
            let unit = text.character(at: i)
            if unit == 10 || unit == 13 { // newline
                return true
            }
            if isWhitespaceUnit(unit) || isClosingPunctuationUnit(unit) {
                i += 1
                continue
            }
            return false
        }
        // End of document after period
        return true
    }

    func isWhitespaceUnit(_ unit: unichar) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    func isDigitAtUTF16Index(_ text: NSString, index: Int) -> Bool {
        guard index >= 0, index < text.length else { return false }
        let unit = text.character(at: index)
        guard let scalar = UnicodeScalar(unit) else { return false }
        return CharacterSet.decimalDigits.contains(scalar)
    }

    func isClosingPunctuationUnit(_ unit: unichar) -> Bool {
        switch unit {
        case 41, 93, 125, 34, 39: // ) ] } " '
            return true
        case 12289, 12290, 12291, 12299, 12301, 12303, 12305: // 、。〃》」』】 etc
            return true
        case 8217, 8221: // ' "
            return true
        default:
            return false
        }
    }

    func utf16ChangeDelta(oldValue: String, newValue: String) -> (prefix: Int, oldChangedLength: Int, newChangedLength: Int, inserted: String) {
        let oldText = oldValue as NSString
        let newText = newValue as NSString
        let oldLength = oldText.length
        let newLength = newText.length

        var prefix = 0
        let limit = min(oldLength, newLength)
        while prefix < limit && oldText.character(at: prefix) == newText.character(at: prefix) {
            prefix += 1
        }

        var oldSuffix = oldLength
        var newSuffix = newLength
        while oldSuffix > prefix && newSuffix > prefix &&
                oldText.character(at: oldSuffix - 1) == newText.character(at: newSuffix - 1) {
            oldSuffix -= 1
            newSuffix -= 1
        }

        let oldChangedLength = max(0, oldSuffix - prefix)
        let newChangedLength = max(0, newSuffix - prefix)
        let inserted: String
        if newChangedLength > 0 {
            inserted = newText.substring(with: NSRange(location: prefix, length: newChangedLength))
        } else {
            inserted = ""
        }
        return (prefix, oldChangedLength, newChangedLength, inserted)
    }

    // MARK: - Focus Undo/Redo

    func computeFocusUndoCaretHint(from before: ScenarioState, to after: ScenarioState) -> (cardID: UUID, location: Int)? {
        let beforeByID = Dictionary(uniqueKeysWithValues: before.cards.map { ($0.id, $0) })
        let afterByID = Dictionary(uniqueKeysWithValues: after.cards.map { ($0.id, $0) })

        func hint(for cardID: UUID) -> (cardID: UUID, location: Int)? {
            guard let oldState = beforeByID[cardID], let newState = afterByID[cardID] else { return nil }
            guard oldState.content != newState.content else { return nil }
            let delta = utf16ChangeDelta(oldValue: oldState.content, newValue: newState.content)
            let targetLen = (newState.content as NSString).length
            let location: Int
            if delta.newChangedLength > delta.oldChangedLength {
                // Text was restored/inserted in target state -> move caret to end of restored span.
                location = delta.prefix + delta.newChangedLength
            } else if delta.newChangedLength == delta.oldChangedLength && delta.newChangedLength > 0 {
                // Replacement -> keep caret at end of replaced span.
                location = delta.prefix + delta.newChangedLength
            } else {
                // Text was removed in target state -> caret at the rollback point.
                location = delta.prefix
            }
            return (cardID: cardID, location: min(max(0, location), targetLen))
        }

        if let preferred = before.activeCardID, let h = hint(for: preferred) { return h }
        if let preferred = after.activeCardID, let h = hint(for: preferred) { return h }

        for card in after.cards {
            if let h = hint(for: card.id) { return h }
        }
        return nil
    }

    func pushFocusUndoState(_ previous: ScenarioState, actionName: String) {
        if isApplyingUndo { return }
        focusUndoStack.append(previous)
        if focusUndoStack.count > maxFocusUndoCount {
            focusUndoStack.removeFirst(focusUndoStack.count - maxFocusUndoCount)
        }
        focusRedoStack.removeAll()
    }

    func performFocusUndo() {
        finalizeFocusTypingCoalescing(reason: "undo-request")
        guard let previous = focusUndoStack.popLast() else {
            return
        }
        let current = captureScenarioState()
        if showFocusMode, current.activeCardID != previous.activeCardID {
            suppressFocusModeScrollOnce = true
            focusModeNextCardScrollAnchor = nil
            focusModeNextCardScrollAnimated = true
        }
        pendingFocusUndoCaretHint = computeFocusUndoCaretHint(from: current, to: previous)
        primeFocusUndoCaretSelectionBeforeRestore()
        focusProgrammaticContentSuppressUntil = Date().addingTimeInterval(0.4)
        focusRedoStack.append(current)
        if focusRedoStack.count > maxFocusUndoCount {
            focusRedoStack.removeFirst(focusRedoStack.count - maxFocusUndoCount)
        }
        restoreScenarioState(previous)
        DispatchQueue.main.async {
            guard showFocusMode else { return }
            restoreFocusEditingContextAfterUndoRedo(restoredState: previous)
        }
    }

    func performFocusRedo() {
        finalizeFocusTypingCoalescing(reason: "redo-request")
        guard let next = focusRedoStack.popLast() else {
            return
        }
        let current = captureScenarioState()
        if showFocusMode, current.activeCardID != next.activeCardID {
            suppressFocusModeScrollOnce = true
            focusModeNextCardScrollAnchor = nil
            focusModeNextCardScrollAnimated = true
        }
        pendingFocusUndoCaretHint = computeFocusUndoCaretHint(from: current, to: next)
        primeFocusUndoCaretSelectionBeforeRestore()
        focusProgrammaticContentSuppressUntil = Date().addingTimeInterval(0.4)
        focusUndoStack.append(current)
        if focusUndoStack.count > maxFocusUndoCount {
            focusUndoStack.removeFirst(focusUndoStack.count - maxFocusUndoCount)
        }
        restoreScenarioState(next)
        DispatchQueue.main.async {
            guard showFocusMode else { return }
            restoreFocusEditingContextAfterUndoRedo(restoredState: next)
        }
    }

    // MARK: - Focus Editing Context Restoration

    func restoreFocusEditingContextAfterUndoRedo(restoredState: ScenarioState) {
        guard showFocusMode else { return }
        focusUndoSelectionEnsureSuppressed = true
        let resolvedCard: SceneCard? = {
            if let id = restoredState.activeCardID, let card = findCard(by: id) { return card }
            if let id = lastActiveCardID, let card = findCard(by: id) { return card }
            if let id = activeCardID, let card = findCard(by: id) { return card }
            return focusedColumnCards().first
        }()
        guard let card = resolvedCard else {
            editingCardID = nil
            focusModeEditorCardID = nil
            pendingFocusUndoCaretHint = nil
            focusUndoSelectionEnsureSuppressed = false
            focusUndoSelectionEnsureRequestID = nil
            return
        }
        if activeCardID != card.id {
            changeActiveCard(to: card, shouldFocusMain: false, deferToMainAsync: false, force: true)
        }
        let id = card.id
        editingCardID = id
        editingStartContent = card.content
        editingStartState = captureScenarioState()
        editingIsNewCard = false
        focusModeEditorCardID = id
        focusLastCommittedContentByCard[id] = card.content
        resetFocusTypingCoalescing()
        let length = (card.content as NSString).length
        let targetLocation: Int = {
            if let hint = pendingFocusUndoCaretHint, hint.cardID == id {
                return min(max(0, hint.location), length)
            }
            if restoredState.activeCardID == id, let saved = restoredState.activeCaretLocation {
                return min(max(0, saved), length)
            }
            return length
        }()
        pendingFocusUndoCaretHint = nil
        focusModeCaretRequestID += 1
        let requestID = focusModeCaretRequestID
        focusUndoSelectionEnsureRequestID = requestID
        applyFocusModeCaretWithRetry(expectedCardID: id, location: targetLocation, retries: 12, requestID: requestID)
        // Fallback: if caret apply callback does not arrive in time, release suppression and ensure once.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            guard focusUndoSelectionEnsureRequestID == requestID else { return }
            focusUndoSelectionEnsureSuppressed = false
            focusUndoSelectionEnsureRequestID = nil
            requestFocusModeCaretEnsure(typewriter: false, delay: 0.0, force: true)
        }
    }

    func primeFocusUndoCaretSelectionBeforeRestore() {
        guard showFocusMode else { return }
        guard let hint = pendingFocusUndoCaretHint else { return }
        guard activeCardID == hint.cardID else { return }
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return }

        let length = (textView.string as NSString).length
        let safe = min(max(0, hint.location), length)
        let current = textView.selectedRange()
        guard current.location != safe || current.length != 0 else { return }

        textView.setSelectedRange(NSRange(location: safe, length: 0))
    }
}
