import SwiftUI
import AppKit

extension ScenarioWriterView {
    func clearMainEditTabArm() {
        mainEditTabArmCardID = nil
        mainEditTabArmAt = .distantPast
    }

    func clearKeyboardRangeSelectionAnchor() {
        keyboardRangeSelectionAnchorCardID = nil
    }

    func applyKeyboardRangeSelection(on level: [SceneCard], anchorID: UUID, targetID: UUID) {
        guard let anchorIndex = level.firstIndex(where: { $0.id == anchorID }),
              let targetIndex = level.firstIndex(where: { $0.id == targetID }) else {
            selectedCardIDs = [targetID]
            return
        }
        let lower = min(anchorIndex, targetIndex)
        let upper = max(anchorIndex, targetIndex)
        let ids = level[lower ... upper].map { $0.id }
        selectedCardIDs = Set(ids)
    }

    func updateKeyboardRangeSelection(from currentCard: SceneCard, to targetCard: SceneCard, in level: [SceneCard]) {
        let anchorID: UUID
        if let existingAnchor = keyboardRangeSelectionAnchorCardID,
           level.contains(where: { $0.id == existingAnchor }) {
            anchorID = existingAnchor
        } else {
            anchorID = currentCard.id
            keyboardRangeSelectionAnchorCardID = anchorID
        }

        if level.contains(where: { $0.id == targetCard.id }) {
            applyKeyboardRangeSelection(on: level, anchorID: anchorID, targetID: targetCard.id)
        } else {
            selectedCardIDs = Set([anchorID, targetCard.id])
        }
    }

    func handleMainEditorBoundaryNavigation(_ press: KeyPress) -> Bool {
        handleMainEditorBoundaryNavigation(
            key: press.key,
            isShiftSelection: press.modifiers.contains(.shift),
            isRepeat: press.phase == .repeat
        )
    }

    func handleMainEditorBoundaryCommand(_ commandSelector: Selector) -> Bool {
        let isRepeat = NSApp.currentEvent?.isARepeat ?? false
        switch NSStringFromSelector(commandSelector) {
        case "cancelOperation:":
            clearMainEditTabArm()
            DispatchQueue.main.async {
                finishEditing(reason: .explicitExit)
            }
            return true
        case "moveUp:":
            return handleMainEditorBoundaryNavigation(key: .upArrow, isShiftSelection: false, isRepeat: isRepeat)
        case "moveDown:":
            return handleMainEditorBoundaryNavigation(key: .downArrow, isShiftSelection: false, isRepeat: isRepeat)
        case "moveLeft:":
            return handleMainEditorBoundaryNavigation(key: .leftArrow, isShiftSelection: false, isRepeat: isRepeat)
        case "moveRight:":
            return handleMainEditorBoundaryNavigation(key: .rightArrow, isShiftSelection: false, isRepeat: isRepeat)
        case "moveUpAndModifySelection:":
            return handleMainEditorBoundaryNavigation(key: .upArrow, isShiftSelection: true, isRepeat: isRepeat)
        case "moveDownAndModifySelection:":
            return handleMainEditorBoundaryNavigation(key: .downArrow, isShiftSelection: true, isRepeat: isRepeat)
        case "moveLeftAndModifySelection:":
            return handleMainEditorBoundaryNavigation(key: .leftArrow, isShiftSelection: true, isRepeat: isRepeat)
        case "moveRightAndModifySelection:":
            return handleMainEditorBoundaryNavigation(key: .rightArrow, isShiftSelection: true, isRepeat: isRepeat)
        default:
            return false
        }
    }

    private func handleMainEditorBoundaryNavigation(
        key: KeyEquivalent,
        isShiftSelection: Bool,
        isRepeat: Bool
    ) -> Bool {
        if let pendingTarget = pendingMainEditingBoundaryNavigationTargetID {
            if !isMainEditingBoundaryTransitionReady(for: pendingTarget) {
                return true
            }
        }
        guard let editingID = editingCardID,
              let editingCard = findCard(by: editingID) else { return false }
        guard let textView = resolvedActiveMainEditorTextView(for: editingID) else { return false }
        guard !textView.hasMarkedText() else { return false }

        let levels = resolvedLevelsWithParents().map(\.cards)
        guard let location = displayedMainCardLocationByID(editingID, in: levels) else { return false }
        let levelIndex = location.level
        let cardIndex = location.index
        guard levels.indices.contains(levelIndex),
              levels[levelIndex].indices.contains(cardIndex) else { return false }

        let currentLevel = levels[levelIndex]
        let content = textView.string as NSString
        let cursor = min(max(0, textView.selectedRange().location), content.length)
        let atTopBoundary = cursor == 0
        let atBottomBoundary = cursor == content.length
        let shouldDiscardEmptyNewCardOnBoundaryMove =
            editingIsNewCard &&
            editingCard.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        switch key {
        case .upArrow:
            guard atTopBoundary else {
                noteMainVerticalCaretNavigation(for: editingID)
                return false
            }
            return handleMainBoundaryUpArrow(
                editingCard: editingCard,
                currentLevel: currentLevel,
                levelIndex: levelIndex,
                cardIndex: cardIndex,
                atTopBoundary: atTopBoundary,
                shouldDiscardEmptyNewCardOnBoundaryMove: shouldDiscardEmptyNewCardOnBoundaryMove,
                isShiftSelection: isShiftSelection,
                isRepeat: isRepeat
            )

        case .downArrow:
            guard atBottomBoundary else {
                noteMainVerticalCaretNavigation(for: editingID)
                return false
            }
            return handleMainBoundaryDownArrow(
                editingCard: editingCard,
                currentLevel: currentLevel,
                levelIndex: levelIndex,
                cardIndex: cardIndex,
                atBottomBoundary: atBottomBoundary,
                shouldDiscardEmptyNewCardOnBoundaryMove: shouldDiscardEmptyNewCardOnBoundaryMove,
                isShiftSelection: isShiftSelection,
                isRepeat: isRepeat
            )

        case .leftArrow:
            return handleMainBoundaryLeftArrow(
                editingCard: editingCard,
                currentLevel: currentLevel,
                atTopBoundary: atTopBoundary,
                cursor: cursor,
                shouldDiscardEmptyNewCardOnBoundaryMove: shouldDiscardEmptyNewCardOnBoundaryMove,
                isShiftSelection: isShiftSelection,
                isRepeat: isRepeat
            )

        case .rightArrow:
            return handleMainBoundaryRightArrow(
                editingCard: editingCard,
                currentLevel: currentLevel,
                levels: levels,
                levelIndex: levelIndex,
                cardIndex: cardIndex,
                atBottomBoundary: atBottomBoundary,
                cursor: cursor,
                contentLength: content.length,
                shouldDiscardEmptyNewCardOnBoundaryMove: shouldDiscardEmptyNewCardOnBoundaryMove,
                isShiftSelection: isShiftSelection,
                isRepeat: isRepeat
            )

        default:
            clearMainBoundaryParentLeftArm()
            clearMainBoundaryChildRightArm()
            clearMainNoChildRightArm()
            return false
        }
    }

    func handleMainBoundaryUpArrow(
        editingCard: SceneCard,
        currentLevel: [SceneCard],
        levelIndex: Int,
        cardIndex: Int,
        atTopBoundary: Bool,
        shouldDiscardEmptyNewCardOnBoundaryMove: Bool,
        isShiftSelection: Bool,
        isRepeat: Bool
    ) -> Bool {
        guard atTopBoundary else { return false }
        if isRepeat {
            return true
        }
        let isRapidBurst = registerMainVerticalArrowPress(for: 126)

        let target: SceneCard
        if cardIndex > 0 {
            target = currentLevel[cardIndex - 1]
        } else if let boundaryTarget = mainCrossCategoryBoundaryTarget(
            for: editingCard,
            levelIndex: levelIndex,
            step: -1
        ) {
            target = boundaryTarget
        } else {
            return false
        }

        if shouldSuppressCrossCategoryVerticalTransition(
            from: editingCard,
            to: target,
            levelIndex: levelIndex,
            keyCode: 126,
            isRepeat: isRepeat,
            isRapidBurst: isRapidBurst
        ) {
            return true
        }
        clearMainEditTabArm()
        clearMainBoundaryParentLeftArm()
        clearMainBoundaryChildRightArm()
        clearMainNoChildRightArm()
        if isShiftSelection {
            applyMainBoundaryShiftSelection(
                from: editingCard,
                to: target,
                in: resolvedMainSelectionLevel(
                    for: editingCard,
                    target: target,
                    levelIndex: levelIndex,
                    fallback: currentLevel
                )
            )
            return true
        }
        let targetLength = (target.content as NSString).length
        switchMainEditingTarget(
            to: target,
            caretLocation: targetLength,
            shouldDiscardEmptyNewCardOnBoundaryMove: shouldDiscardEmptyNewCardOnBoundaryMove,
            suppressSiblingNavigationScrolls: true
        )
        return true
    }

    func handleMainBoundaryDownArrow(
        editingCard: SceneCard,
        currentLevel: [SceneCard],
        levelIndex: Int,
        cardIndex: Int,
        atBottomBoundary: Bool,
        shouldDiscardEmptyNewCardOnBoundaryMove: Bool,
        isShiftSelection: Bool,
        isRepeat: Bool
    ) -> Bool {
        guard atBottomBoundary else { return false }
        if isRepeat {
            return true
        }
        let isRapidBurst = registerMainVerticalArrowPress(for: 125)

        let target: SceneCard
        if cardIndex < currentLevel.count - 1 {
            target = currentLevel[cardIndex + 1]
        } else if let boundaryTarget = mainCrossCategoryBoundaryTarget(
            for: editingCard,
            levelIndex: levelIndex,
            step: 1
        ) {
            target = boundaryTarget
        } else {
            return false
        }

        if shouldSuppressCrossCategoryVerticalTransition(
            from: editingCard,
            to: target,
            levelIndex: levelIndex,
            keyCode: 125,
            isRepeat: isRepeat,
            isRapidBurst: isRapidBurst
        ) {
            return true
        }
        clearMainEditTabArm()
        clearMainBoundaryParentLeftArm()
        clearMainBoundaryChildRightArm()
        clearMainNoChildRightArm()
        if isShiftSelection {
            applyMainBoundaryShiftSelection(
                from: editingCard,
                to: target,
                in: resolvedMainSelectionLevel(
                    for: editingCard,
                    target: target,
                    levelIndex: levelIndex,
                    fallback: currentLevel
                )
            )
            return true
        }
        switchMainEditingTarget(
            to: target,
            caretLocation: 0,
            shouldDiscardEmptyNewCardOnBoundaryMove: shouldDiscardEmptyNewCardOnBoundaryMove,
            suppressSiblingNavigationScrolls: true
        )
        return true
    }

    func handleMainBoundaryLeftArrow(
        editingCard: SceneCard,
        currentLevel: [SceneCard],
        atTopBoundary: Bool,
        cursor: Int,
        shouldDiscardEmptyNewCardOnBoundaryMove: Bool,
        isShiftSelection: Bool,
        isRepeat: Bool
    ) -> Bool {
        guard atTopBoundary, cursor == 0 else {
            clearMainBoundaryParentLeftArm()
            return false
        }
        guard let parentCard = editingCard.parent else {
            clearMainBoundaryParentLeftArm()
            return false
        }

        clearMainEditTabArm()
        clearMainBoundaryChildRightArm()
        clearMainNoChildRightArm()
        if isRepeat {
            return true
        }
        if !isMainEditingParentChildBoundaryNavigationEnabled {
            clearMainBoundaryParentLeftArm()
            return true
        }
        if isShiftSelection {
            applyMainBoundaryShiftSelection(from: editingCard, to: parentCard, in: currentLevel)
            return true
        }
        if isMainBoundaryParentLeftArmed(for: editingCard.id) {
            clearMainBoundaryParentLeftArm()
            let parentLength = (parentCard.content as NSString).length
            beginCardEditing(parentCard, explicitCaretLocation: parentLength)
            return true
        }

        armMainBoundaryParentLeft(for: editingCard.id)
        return true
    }

    func handleMainBoundaryRightArrow(
        editingCard: SceneCard,
        currentLevel: [SceneCard],
        levels: [[SceneCard]],
        levelIndex: Int,
        cardIndex: Int,
        atBottomBoundary: Bool,
        cursor: Int,
        contentLength: Int,
        shouldDiscardEmptyNewCardOnBoundaryMove: Bool,
        isShiftSelection: Bool,
        isRepeat: Bool
    ) -> Bool {
        guard atBottomBoundary, cursor == contentLength else {
            clearMainBoundaryChildRightArm()
            clearMainNoChildRightArm()
            return false
        }

        clearMainEditTabArm()
        clearMainBoundaryParentLeftArm()
        let nextLevel = (levelIndex + 1 < levels.count) ? levels[levelIndex + 1] : []
        if isRepeat {
            return true
        }
        if !isMainEditingParentChildBoundaryNavigationEnabled {
            clearMainBoundaryChildRightArm()
            clearMainNoChildRightArm()
            return true
        }

        if isShiftSelection {
            clearMainBoundaryChildRightArm()
            let result = resolvedMainRightTarget(
                for: editingCard,
                currentLevel: currentLevel,
                nextLevel: nextLevel,
                currentIndex: cardIndex,
                allowDoublePressFallback: true
            )
            if case .target(let target) = result {
                applyMainBoundaryShiftSelection(from: editingCard, to: target, in: currentLevel)
            }
            return true
        }

        if isMainBoundaryChildRightArmed(for: editingCard.id) {
            clearMainBoundaryChildRightArm()
            let result = resolvedMainRightTarget(
                for: editingCard,
                currentLevel: currentLevel,
                nextLevel: nextLevel,
                currentIndex: cardIndex,
                allowDoublePressFallback: true
            )
            if case .target(let target) = result {
                beginCardEditing(target, explicitCaretLocation: 0)
            }
            return true
        }

        if preferredMainNavigationChild(for: editingCard, matching: editingCard.category) == nil {
            armMainNoChildRight(for: editingCard.id)
        }
        armMainBoundaryChildRight(for: editingCard.id)
        return true
    }

    func applyMainBoundaryShiftSelection(from editingCard: SceneCard, to target: SceneCard, in level: [SceneCard]) {
        finishEditing(reason: .transition)
        changeActiveCard(to: target, shouldFocusMain: false, deferToMainAsync: false)
        updateKeyboardRangeSelection(from: editingCard, to: target, in: level)
    }

    func switchMainEditingTarget(
        to target: SceneCard,
        caretLocation: Int,
        shouldDiscardEmptyNewCardOnBoundaryMove: Bool,
        suppressSiblingNavigationScrolls: Bool = false
    ) {
        let textLength = (target.content as NSString).length
        let safeCaretLocation = min(max(0, caretLocation), textLength)
        if shouldDiscardEmptyNewCardOnBoundaryMove {
            finishEditing(reason: .transition)
        }
        cancelMainArrowNavigationSettle()
        cancelAllPendingMainColumnFocusWork()
        prepareMainEditorSessionRequest(for: target, explicitCaretLocation: safeCaretLocation)
        beginMainEditingScrollIsolation(
            for: target.id,
            reason: suppressSiblingNavigationScrolls ? "boundary.vertical" : "boundary.horizontal"
        )
        pendingMainEditingSiblingNavigationTargetID = suppressSiblingNavigationScrolls ? target.id : nil
        pendingMainEditingBoundaryNavigationTargetID = target.id
        if suppressSiblingNavigationScrolls {
            pendingMainEditingViewportKeepVisibleCardID = nil
            pendingMainEditingViewportRevealEdge = nil
        } else {
            pendingMainEditingViewportKeepVisibleCardID = target.id
            pendingMainEditingViewportRevealEdge = caretLocation <= 0 ? .top : .bottom
        }
        mainCaretLocationByCardID[target.id] = safeCaretLocation
        mainProgrammaticCaretSuppressEnsureCardID = target.id
        mainProgrammaticCaretExpectedCardID = target.id
        mainProgrammaticCaretExpectedLocation = safeCaretLocation
        mainProgrammaticCaretSelectionIgnoreUntil = Date().addingTimeInterval(0.28)
        changeActiveCard(to: target, shouldFocusMain: false, deferToMainAsync: false)
        selectedCardIDs = [target.id]
        editingCardID = target.id
        editingStartContent = target.content
        editingStartState = captureScenarioState()
        editingIsNewCard = false
    }

    // --- Main Nav Key Monitor ---
    func startMainNavKeyMonitor() {
        guard !showFocusMode else { return }
        if mainNavKeyMonitor != nil { return }
        mainNavKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let isReferenceWindowEvent = event.window?.identifier?.rawValue == ReferenceWindowConstants.windowID
            let isReferenceWindowKey = NSApp.keyWindow?.identifier?.rawValue == ReferenceWindowConstants.windowID
            if isReferenceWindowEvent || isReferenceWindowKey {
                return event
            }
            if !acceptsKeyboardInput { return event }
            if showFountainClipboardPasteDialog {
                _ = handleFountainClipboardPasteDialogKeyDownEvent(event)
                return nil
            }
            if showCloneCardPasteDialog {
                _ = handleClonePasteDialogKeyDownEvent(event)
                return nil
            }
            if showFocusMode || showHistoryBar || isPreviewingHistory { return event }
            if showDeleteAlert {
                let hasChildren = selectedCardsForDeletion().contains { !$0.children.isEmpty }
                let isEscape = event.keyCode == 53
                let isReturn = event.keyCode == 36 || event.keyCode == 76
                if isEscape || (hasChildren && isReturn) {
                    DispatchQueue.main.async {
                        showDeleteAlert = false
                        isMainViewFocused = true
                    }
                    return nil
                }
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isPlainEscape =
                event.keyCode == 53 &&
                !flags.contains(.command) &&
                !flags.contains(.option) &&
                !flags.contains(.control) &&
                !flags.contains(.shift)
            if isPlainEscape {
                if let textView = NSApp.keyWindow?.firstResponder as? NSTextView, textView.hasMarkedText() {
                    return event
                }
                if editingCardID != nil {
                    clearMainEditTabArm()
                    DispatchQueue.main.async {
                        finishEditing(reason: .explicitExit)
                    }
                    return nil
                }
                if isSearchFocused || showTimeline {
                    DispatchQueue.main.async {
                        closeSearch()
                    }
                    return nil
                }
                if isFullscreen {
                    return nil
                }
            }
            let isCmdOnly = flags.contains(.command) && !flags.contains(.option) && !flags.contains(.control) && !flags.contains(.shift)
            if let monitoredKey = monitoredMainKeyboardKeyName(for: event), !event.isARepeat {
                logMonitoredMainKeyboardEvent(
                    source: "local-monitor",
                    key: monitoredKey,
                    phase: "down",
                    details: "keyCode=\(event.keyCode)"
                )
            }
            let isMainEditorTyping = isMainEditorActivelyTyping()
            let isPlainReturn =
                (event.keyCode == 36 || event.keyCode == 76) &&
                !flags.contains(.command) &&
                !flags.contains(.option) &&
                !flags.contains(.control) &&
                !flags.contains(.shift)
            let normalized = (event.charactersIgnoringModifiers ?? "").lowercased()
            let isFindShortcut = normalized == "f" || normalized == "ㄹ" || event.keyCode == 3
            let isCtrlTab = flags.contains(.control) && !flags.contains(.command) && !flags.contains(.option) && !flags.contains(.shift) && event.keyCode == 48
            if isCtrlTab {
                NotificationCenter.default.post(name: .waCycleSplitPaneRequested, object: nil)
                return nil
            }
            if isCmdOnly && isFindShortcut {
                DispatchQueue.main.async {
                    toggleSearch()
                }
                return nil
            }
            let isPasteShortcut = normalized == "v" || normalized == "ㅍ" || event.keyCode == 9
            if isCmdOnly && isMainEditorTyping && isPasteShortcut {
                if let textView = resolvedActiveMainEditorTextView(),
                   handleFountainClipboardPasteShortcutIfPossible(from: textView) {
                    return nil
                }
            }
            if showAIChat && isAIChatInputFocused {
                return event
            }
            if isPlainReturn && !isMainEditorTyping && !isSearchFocused {
                guard let card = resolvedMainEditingTargetCard() else {
                    logMonitoredMainKeyboardEvent(
                        source: "local-monitor",
                        key: "return",
                        phase: "dispatch",
                        details: "dispatch=none reason=noActiveCard"
                    )
                    return event
                }
                logMonitoredMainKeyboardEvent(
                    source: "local-monitor",
                    key: "return",
                    phase: "dispatch",
                    details: "dispatch=beginCardEditing active=\(mainWorkspacePhase0CardID(card.id))"
                )
                DispatchQueue.main.async {
                    beginCardEditing(card)
                }
                return nil
            }
            let isMainEditingArrow =
                !flags.contains(.command) &&
                !flags.contains(.option) &&
                !flags.contains(.control) &&
                [123, 124, 125, 126].contains(event.keyCode)
            if isMainEditingArrow &&
                editingCardID != nil &&
                !isMainEditorTyping {
                mainWorkspacePhase0Log(
                    "main-nav-monitor-editing-arrow-suppressed",
                    "keyCode=\(event.keyCode) repeat=\(event.isARepeat) reason=noAuthoritativeTextView " +
                    "editing=\(mainWorkspacePhase0CardID(editingCardID)) " +
                    "requested=\(mainWorkspacePhase0CardID(mainEditorSession.requestedCardID)) " +
                    "pending=\(mainWorkspacePhase0CardID(pendingMainEditingBoundaryNavigationTargetID)) " +
                    "responder=\(mainWorkspacePhase0ResponderSummary(expectedText: editingCardID.flatMap { findCard(by: $0)?.content }))"
                )
                return nil
            }
            if isMainEditorTyping {
                if isMainEditingArrow {
                    mainWorkspacePhase0Log(
                        "main-nav-monitor-editing-arrow-pass-through",
                        "keyCode=\(event.keyCode) repeat=\(event.isARepeat) " +
                        "editing=\(mainWorkspacePhase0CardID(editingCardID)) " +
                        "responder=\(mainWorkspacePhase0ResponderSummary(expectedText: editingCardID.flatMap { findCard(by: $0)?.content }))"
                    )
                }
                return event
            }
            if isSearchFocused { return event }
            if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) || event.modifierFlags.contains(.control) {
                return event
            }
            if event.isARepeat {
                mainArrowRepeatAnimationSuppressedUntil = Date().addingTimeInterval(0.16)
            }
            bounceDebugLog(
                "mainNavKeyMonitor keyCode=\(event.keyCode) repeat=\(event.isARepeat) " +
                "active=\(activeCardID?.uuidString ?? "nil")"
            )
            if handleNavigationKeyCode(
                event.keyCode,
                isRepeat: event.isARepeat,
                isShiftPressed: flags.contains(.shift)
            ) {
                return nil
            }
            if [123, 124, 125, 126].contains(event.keyCode) {
                playMainBoundaryFeedbackIfNeeded(for: event.keyCode, activeID: activeCardID)
                return nil
            }
            return event
        }
    }

    func stopMainNavKeyMonitor() {
        if let monitor = mainNavKeyMonitor {
            NSEvent.removeMonitor(monitor)
            mainNavKeyMonitor = nil
        }
    }

    func clearMainBoundaryFeedbackGate() {
        mainBoundaryFeedbackCardID = nil
        mainBoundaryFeedbackKeyCode = nil
    }

    func playMainBoundaryFeedbackIfNeeded(for keyCode: UInt16, activeID: UUID?) {
        guard mainBoundaryFeedbackCardID != activeID || mainBoundaryFeedbackKeyCode != keyCode else {
            return
        }
        mainBoundaryFeedbackCardID = activeID
        mainBoundaryFeedbackKeyCode = keyCode
        playSoftBoundaryFeedbackSound()
    }

    func boundaryFeedbackKeyCode(for key: KeyEquivalent) -> UInt16? {
        switch key {
        case .upArrow: return 126
        case .downArrow: return 125
        case .rightArrow: return 124
        case .leftArrow: return 123
        default: return nil
        }
    }

    func registerMainVerticalArrowPress(for keyCode: UInt16) -> Bool {
        let now = Date()
        let isRapidBurst =
            mainRecentVerticalArrowKeyCode == keyCode &&
            now.timeIntervalSince(mainRecentVerticalArrowAt) <= 0.24
        mainRecentVerticalArrowKeyCode = keyCode
        mainRecentVerticalArrowAt = now
        return isRapidBurst
    }

    func shouldSuppressCrossCategoryVerticalTransition(
        from source: SceneCard,
        to target: SceneCard,
        levelIndex: Int,
        keyCode: UInt16,
        isRepeat: Bool,
        isRapidBurst: Bool
    ) -> Bool {
        guard levelIndex >= 2 else { return false }
        guard target.category != source.category else { return false }
        guard isRepeat || isRapidBurst else { return false }
        playMainBoundaryFeedbackIfNeeded(for: keyCode, activeID: source.id)
        return true
    }

    func clearMainNoChildRightArm() {
        mainNoChildRightArmCardID = nil
        mainNoChildRightArmAt = .distantPast
    }

    func armMainNoChildRight(for cardID: UUID) {
        mainNoChildRightArmCardID = cardID
        mainNoChildRightArmAt = Date()
    }

    func isMainNoChildRightArmed(for cardID: UUID) -> Bool {
        guard mainNoChildRightArmCardID == cardID else { return false }
        return Date().timeIntervalSince(mainNoChildRightArmAt) <= mainNoChildRightDoublePressInterval
    }

    func clearMainBoundaryParentLeftArm() {
        mainBoundaryParentLeftArmCardID = nil
        mainBoundaryParentLeftArmAt = .distantPast
    }

    func armMainBoundaryParentLeft(for cardID: UUID) {
        mainBoundaryParentLeftArmCardID = cardID
        mainBoundaryParentLeftArmAt = Date()
    }

    func isMainBoundaryParentLeftArmed(for cardID: UUID) -> Bool {
        guard mainBoundaryParentLeftArmCardID == cardID else { return false }
        return Date().timeIntervalSince(mainBoundaryParentLeftArmAt) <= mainNoChildRightDoublePressInterval
    }

    func clearMainBoundaryChildRightArm() {
        mainBoundaryChildRightArmCardID = nil
        mainBoundaryChildRightArmAt = .distantPast
    }

    func armMainBoundaryChildRight(for cardID: UUID) {
        mainBoundaryChildRightArmCardID = cardID
        mainBoundaryChildRightArmAt = Date()
    }

    func isMainBoundaryChildRightArmed(for cardID: UUID) -> Bool {
        guard mainBoundaryChildRightArmCardID == cardID else { return false }
        return Date().timeIntervalSince(mainBoundaryChildRightArmAt) <= mainNoChildRightDoublePressInterval
    }

    // --- Preferred Child / Right Target Resolution ---
    func preferredChild(for card: SceneCard) -> SceneCard? {
        card.children.first(where: { $0.id == card.lastSelectedChildID }) ?? card.sortedChildren.first
    }

    func preferredChild(for card: SceneCard, matching category: String?) -> SceneCard? {
        guard let category else {
            return preferredChild(for: card)
        }

        if let rememberedID = card.lastSelectedChildID,
           let remembered = card.children.first(where: { $0.id == rememberedID && $0.category == category }) {
            return remembered
        }

        return card.sortedChildren.first(where: { $0.category == category })
    }

    func preferredMainNavigationChild(for card: SceneCard, matching category: String?) -> SceneCard? {
        if let matched = preferredChild(for: card, matching: category) {
            return matched
        }
        return preferredChild(for: card)
    }

    func resolvedMainUnfilteredLevel(at levelIndex: Int) -> [SceneCard]? {
        let levels = resolvedLevelsWithParents()
        guard levels.indices.contains(levelIndex) else { return nil }
        return levels[levelIndex].cards
    }

    private func resolvedMainBoundaryNavigableLevel(at levelIndex: Int) -> [SceneCard]? {
        guard let level = resolvedMainUnfilteredLevel(at: levelIndex) else { return nil }
        let filtered = level.filter { !isIndexBoardTempDescendant(cardID: $0.id) }
        return filtered.isEmpty ? level : filtered
    }

    func mainCrossCategoryBoundaryTarget(
        for card: SceneCard,
        levelIndex: Int,
        step: Int
    ) -> SceneCard? {
        guard levelIndex >= 2 else { return nil }
        guard let level = resolvedMainBoundaryNavigableLevel(at: levelIndex),
              let index = level.firstIndex(where: { $0.id == card.id }) else {
            return nil
        }

        let targetIndex = index + step
        guard level.indices.contains(targetIndex) else { return nil }
        let target = level[targetIndex]
        guard target.category != card.category else { return nil }
        return target
    }

    func resolvedMainSelectionLevel(
        for card: SceneCard,
        target: SceneCard,
        levelIndex: Int,
        fallback: [SceneCard]
    ) -> [SceneCard] {
        guard target.category != card.category,
              let fullLevel = resolvedMainBoundaryNavigableLevel(at: levelIndex) else {
            return fallback
        }
        return fullLevel
    }

    func nearestChildInSibling(
        _ sibling: SceneCard,
        matching category: String?,
        rankedNextLevel: [SceneCard],
        anchorRank: Int
    ) -> (child: SceneCard, nextRank: Int)? {
        let candidates: [SceneCard]
        if let category {
            candidates = sibling.sortedChildren.filter { $0.category == category }
        } else {
            candidates = sibling.sortedChildren
        }

        let rankedCandidates = candidates.compactMap { child -> (child: SceneCard, nextRank: Int)? in
            guard let nextRank = rankedNextLevel.firstIndex(where: { $0.id == child.id }) else {
                return nil
            }
            return (child, nextRank)
        }
        guard !rankedCandidates.isEmpty else { return nil }

        return rankedCandidates.min { lhs, rhs in
            let leftDistance = abs(lhs.nextRank - anchorRank)
            let rightDistance = abs(rhs.nextRank - anchorRank)
            if leftDistance != rightDistance {
                return leftDistance < rightDistance
            }

            let leftForwardBias = lhs.nextRank >= anchorRank ? 0 : 1
            let rightForwardBias = rhs.nextRank >= anchorRank ? 0 : 1
            if leftForwardBias != rightForwardBias {
                return leftForwardBias < rightForwardBias
            }

            if lhs.nextRank != rhs.nextRank {
                return lhs.nextRank < rhs.nextRank
            }
            return lhs.child.orderIndex < rhs.child.orderIndex
        }
    }

    func nearestLevelChildTarget(
        in level: [SceneCard],
        nextLevel: [SceneCard],
        around index: Int,
        matching category: String?
    ) -> SceneCard? {
        guard level.indices.contains(index) else { return nil }
        guard level.count > 1 else { return nil }

        let rankedLevel = level.enumerated().filter { _, item in
            category == nil || item.category == category
        }
        guard let activeRank = rankedLevel.firstIndex(where: { entry in
            entry.offset == index
        }) else {
            return nil
        }

        let rankedNextLevel = nextLevel.filter { card in
            category == nil || card.category == category
        }
        var candidates: [(siblingRank: Int, child: SceneCard, nextRank: Int)] = []
        for (rank, entry) in rankedLevel.enumerated() {
            if entry.offset == index {
                continue
            }

            guard let preferred = preferredMainNavigationChild(for: entry.element, matching: category),
                  let nextRank = rankedNextLevel.firstIndex(where: { $0.id == preferred.id }) else {
                continue
            }
            candidates.append((rank, preferred, nextRank))
        }

        guard !candidates.isEmpty else { return nil }
        let nearestParentDistance = candidates
            .map { abs($0.siblingRank - activeRank) }
            .min()
            ?? Int.max

        let nearestParents = candidates.filter {
            abs($0.siblingRank - activeRank) == nearestParentDistance
        }
        guard !nearestParents.isEmpty else { return nil }

        let chosenParent = nearestParents.min { lhs, rhs in
            let lhsBias = lhs.siblingRank > activeRank ? 0 : 1
            let rhsBias = rhs.siblingRank > activeRank ? 0 : 1
            if lhsBias != rhsBias {
                return lhsBias < rhsBias
            }

            if lhs.siblingRank != rhs.siblingRank {
                return lhs.siblingRank < rhs.siblingRank
            }

            if lhs.nextRank != rhs.nextRank {
                return lhs.nextRank < rhs.nextRank
            }

            return lhs.child.orderIndex < rhs.child.orderIndex
        }

        return chosenParent?.child
    }

    func nearestLevelChildTarget(in level: [SceneCard], around index: Int) -> SceneCard? {
        return nearestLevelChildTarget(
            in: level,
            nextLevel: [],
            around: index,
            matching: nil
        )
    }

    func resolvedMainRightTarget(
        for card: SceneCard,
        currentLevel: [SceneCard],
        nextLevel: [SceneCard],
        currentIndex: Int,
        allowDoublePressFallback: Bool
    ) -> MainRightResolution {
        if let child = preferredMainNavigationChild(for: card, matching: card.category) {
            clearMainNoChildRightArm()
            return .target(child)
        }
        guard allowDoublePressFallback else {
            clearMainNoChildRightArm()
            return .unavailable
        }
        if isMainNoChildRightArmed(for: card.id) {
            clearMainNoChildRightArm()
            if let target = nearestLevelChildTarget(
                in: currentLevel,
                nextLevel: nextLevel,
                around: currentIndex,
                matching: card.category
            ) {
                return .target(target)
            }
            if let target = nearestLevelChildTarget(
                in: currentLevel,
                nextLevel: nextLevel,
                around: currentIndex,
                matching: nil
            ) {
                return .target(target)
            }
            return .unavailable
        }
        armMainNoChildRight(for: card.id)
        return .armed
    }

    @discardableResult
    func performMainArrowNavigation(
        _ direction: MainArrowDirection,
        isRepeat: Bool,
        isShiftPressed: Bool,
        consumeRightArrowWhenUnavailable: Bool,
        seedRangeAnchorWhenNoActive: Bool
    ) -> Bool {
        guard let id = activeCardID else {
            if let first = scenario.rootCards.first {
                clearMainBoundaryFeedbackGate()
                publishPreemptiveMainColumnFocusNavigationIntent(
                    for: first.id,
                    trigger: "arrowPreview.initial"
                )
                changeActiveCard(to: first, deferToMainAsync: false)
                selectedCardIDs = [first.id]
                if seedRangeAnchorWhenNoActive && isShiftPressed {
                    keyboardRangeSelectionAnchorCardID = first.id
                } else {
                    clearKeyboardRangeSelectionAnchor()
                }
                return true
            }
            return false
        }

        let levels = resolvedLevelsWithParents().map(\.cards)
        guard let location = displayedMainCardLocationByID(id, in: levels) else { return false }
        let levelIndex = location.level
        let cardIndex = location.index
        guard levels.indices.contains(levelIndex),
              levels[levelIndex].indices.contains(cardIndex) else {
            return false
        }

        let currentLevel = levels[levelIndex]
        let nextLevel = (levelIndex + 1 < levels.count) ? levels[levelIndex + 1] : []
        let card = currentLevel[cardIndex]
        if !isShiftPressed && selectedCardIDs.count > 1 {
            selectedCardIDs = [card.id]
        }

        switch direction {
        case .up:
            clearMainNoChildRightArm()
            let isRapidBurst = registerMainVerticalArrowPress(for: 126)
            let target: SceneCard
            if cardIndex > 0 {
                target = currentLevel[cardIndex - 1]
            } else if let boundaryTarget = mainCrossCategoryBoundaryTarget(
                for: card,
                levelIndex: levelIndex,
                step: -1
            ) {
                target = boundaryTarget
            } else {
                return false
            }
            if shouldSuppressCrossCategoryVerticalTransition(
                from: card,
                to: target,
                levelIndex: levelIndex,
                keyCode: 126,
                isRepeat: isRepeat,
                isRapidBurst: isRapidBurst
            ) {
                return true
            }
            clearMainBoundaryFeedbackGate()
            publishPreemptiveMainColumnFocusNavigationIntent(
                for: target.id,
                trigger: "arrowPreview.up"
            )
            changeActiveCard(to: target, deferToMainAsync: false)
            if isShiftPressed {
                updateKeyboardRangeSelection(
                    from: card,
                    to: target,
                    in: resolvedMainSelectionLevel(
                        for: card,
                        target: target,
                        levelIndex: levelIndex,
                        fallback: currentLevel
                    )
                )
            } else {
                selectedCardIDs = [target.id]
                clearKeyboardRangeSelectionAnchor()
            }
            return true

        case .down:
            clearMainNoChildRightArm()
            let isRapidBurst = registerMainVerticalArrowPress(for: 125)
            if cardIndex < currentLevel.count - 1 {
                let target = currentLevel[cardIndex + 1]
                if shouldSuppressCrossCategoryVerticalTransition(
                    from: card,
                    to: target,
                    levelIndex: levelIndex,
                    keyCode: 125,
                    isRepeat: isRepeat,
                    isRapidBurst: isRapidBurst
                ) {
                    return true
                }
                clearMainBoundaryFeedbackGate()
                publishPreemptiveMainColumnFocusNavigationIntent(
                    for: target.id,
                    trigger: "arrowPreview.down"
                )
                changeActiveCard(to: target, deferToMainAsync: false)
                if isShiftPressed {
                    updateKeyboardRangeSelection(from: card, to: target, in: currentLevel)
                } else {
                    selectedCardIDs = [target.id]
                    clearKeyboardRangeSelectionAnchor()
                }
                return true
            }
            if requestMainBottomRevealIfNeeded(currentLevel: currentLevel, currentIndex: cardIndex, card: card) {
                clearMainBoundaryFeedbackGate()
                return true
            }
            guard let target = mainCrossCategoryBoundaryTarget(
                for: card,
                levelIndex: levelIndex,
                step: 1
            ) else {
                return false
            }
            if shouldSuppressCrossCategoryVerticalTransition(
                from: card,
                to: target,
                levelIndex: levelIndex,
                keyCode: 125,
                isRepeat: isRepeat,
                isRapidBurst: isRapidBurst
            ) {
                return true
            }
            clearMainBoundaryFeedbackGate()
            publishPreemptiveMainColumnFocusNavigationIntent(
                for: target.id,
                trigger: "arrowPreview.downBoundary"
            )
            changeActiveCard(to: target, deferToMainAsync: false)
            if isShiftPressed {
                updateKeyboardRangeSelection(
                    from: card,
                    to: target,
                    in: resolvedMainSelectionLevel(
                        for: card,
                        target: target,
                        levelIndex: levelIndex,
                        fallback: currentLevel
                    )
                )
            } else {
                selectedCardIDs = [target.id]
                clearKeyboardRangeSelectionAnchor()
            }
            return true

        case .right:
            let allowDoublePressFallback = !isRepeat
            let result = resolvedMainRightTarget(
                for: card,
                currentLevel: currentLevel,
                nextLevel: nextLevel,
                currentIndex: cardIndex,
                allowDoublePressFallback: allowDoublePressFallback
            )
            if case .target(let target) = result {
                clearMainBoundaryFeedbackGate()
                publishPreemptiveMainColumnFocusNavigationIntent(
                    for: target.id,
                    trigger: "arrowPreview.right"
                )
                changeActiveCard(to: target, deferToMainAsync: false)
                selectedCardIDs = [target.id]
                clearKeyboardRangeSelectionAnchor()
                return true
            }
            if consumeRightArrowWhenUnavailable {
                return true
            }
            return false

        case .left:
            clearMainNoChildRightArm()
            guard let parent = card.parent else { return false }
            clearMainBoundaryFeedbackGate()
            publishPreemptiveMainColumnFocusNavigationIntent(
                for: parent.id,
                trigger: "arrowPreview.left"
            )
            changeActiveCard(to: parent, deferToMainAsync: false)
            selectedCardIDs = [parent.id]
            clearKeyboardRangeSelectionAnchor()
            return true
        }
    }

    // --- Navigation Key Code Handler ---
    func handleNavigationKeyCode(_ keyCode: UInt16, isRepeat: Bool = false, isShiftPressed: Bool = false) -> Bool {
        let previousActiveID = activeCardID
        let handled: Bool
        switch keyCode {
        case 126: // up
            handled = performMainArrowNavigation(
                .up,
                isRepeat: isRepeat,
                isShiftPressed: isShiftPressed,
                consumeRightArrowWhenUnavailable: false,
                seedRangeAnchorWhenNoActive: true
            )
        case 125: // down
            handled = performMainArrowNavigation(
                .down,
                isRepeat: isRepeat,
                isShiftPressed: isShiftPressed,
                consumeRightArrowWhenUnavailable: false,
                seedRangeAnchorWhenNoActive: true
            )
        case 124: // right
            handled = performMainArrowNavigation(
                .right,
                isRepeat: isRepeat,
                isShiftPressed: isShiftPressed,
                consumeRightArrowWhenUnavailable: true,
                seedRangeAnchorWhenNoActive: true
            )
        case 123: // left
            handled = performMainArrowNavigation(
                .left,
                isRepeat: isRepeat,
                isShiftPressed: isShiftPressed,
                consumeRightArrowWhenUnavailable: false,
                seedRangeAnchorWhenNoActive: true
            )
        default:
            clearMainNoChildRightArm()
            handled = false
        }
        if handled {
            registerHandledMainArrowNavigation(
                direction: directionForNavigationKeyCode(keyCode),
                previousActiveID: previousActiveID,
                isRepeat: isRepeat
            )
        }
        return handled
    }

    // --- Navigation Press Handler ---
    func handleNavigation(press: KeyPress) -> KeyPress.Result {
        if activeCardID == nil && scenario.rootCards.isEmpty {
            return .ignored
        }
        let isShiftPressed = press.modifiers.contains(.shift)
        let isRepeat = (press.phase == .repeat)
        if isRepeat {
            mainArrowRepeatAnimationSuppressedUntil = Date().addingTimeInterval(0.16)
        }
        let previousActiveID = activeCardID
        let handled: Bool
        bounceDebugLog(
            "handleNavigation key=\(String(describing: press.key)) phase=\(String(describing: press.phase)) " +
            "repeat=\(isRepeat) active=\(activeCardID?.uuidString ?? "nil")"
        )
        switch press.key {
        case .upArrow:
            handled = performMainArrowNavigation(
                .up,
                isRepeat: isRepeat,
                isShiftPressed: isShiftPressed,
                consumeRightArrowWhenUnavailable: false,
                seedRangeAnchorWhenNoActive: false
            )
        case .downArrow:
            handled = performMainArrowNavigation(
                .down,
                isRepeat: isRepeat,
                isShiftPressed: isShiftPressed,
                consumeRightArrowWhenUnavailable: false,
                seedRangeAnchorWhenNoActive: false
            )
        case .rightArrow:
            handled = performMainArrowNavigation(
                .right,
                isRepeat: isRepeat,
                isShiftPressed: isShiftPressed,
                consumeRightArrowWhenUnavailable: false,
                seedRangeAnchorWhenNoActive: false
            )
        case .leftArrow:
            handled = performMainArrowNavigation(
                .left,
                isRepeat: isRepeat,
                isShiftPressed: isShiftPressed,
                consumeRightArrowWhenUnavailable: false,
                seedRangeAnchorWhenNoActive: false
            )
        default: return .ignored
        }
        if handled {
            registerHandledMainArrowNavigation(
                direction: directionForNavigationKeyPress(press.key),
                previousActiveID: previousActiveID,
                isRepeat: isRepeat
            )
        }
        if !handled, let keyCode = boundaryFeedbackKeyCode(for: press.key) {
            playMainBoundaryFeedbackIfNeeded(for: keyCode, activeID: activeCardID)
        }
        return .handled
    }

    func directionForNavigationKeyCode(_ keyCode: UInt16) -> MainArrowDirection? {
        switch keyCode {
        case 126: return .up
        case 125: return .down
        case 124: return .right
        case 123: return .left
        default: return nil
        }
    }

    func directionForNavigationKeyPress(_ key: KeyEquivalent) -> MainArrowDirection? {
        switch key {
        case .upArrow: return .up
        case .downArrow: return .down
        case .rightArrow: return .right
        case .leftArrow: return .left
        default: return nil
        }
    }

    func registerHandledMainArrowNavigation(
        direction: MainArrowDirection?,
        previousActiveID: UUID?,
        isRepeat: Bool
    ) {
        guard let direction else { return }

        mainWorkspacePhase0Log(
            "focus-intent",
            "direction=\(String(describing: direction)) repeat=\(isRepeat) " +
            "from=\(mainWorkspacePhase0CardID(previousActiveID)) to=\(mainWorkspacePhase0CardID(activeCardID)) " +
            "editing=\(mainWorkspacePhase0CardID(editingCardID))"
        )

        MainCanvasNavigationDiagnostics.shared.beginFocusIntent(
            ownerKey: mainCanvasDiagnosticsOwnerKey,
            direction: direction,
            isRepeat: isRepeat,
            sourceCardID: previousActiveID,
            intendedCardID: activeCardID
        )

        switch direction {
        case .left, .right:
            if activeCardID != previousActiveID {
                pendingMainHorizontalScrollAnimation = !isRepeat
            } else {
                pendingMainHorizontalScrollAnimation = nil
            }
            if isRepeat {
                scheduleMainArrowNavigationSettle()
            } else {
                cancelMainArrowNavigationSettle()
            }

        case .up, .down:
            pendingMainHorizontalScrollAnimation = nil
            if isRepeat || !focusNavigationAnimationEnabled {
                scheduleMainArrowNavigationSettle()
            } else {
                cancelMainArrowNavigationSettle()
            }
        }
    }
}
