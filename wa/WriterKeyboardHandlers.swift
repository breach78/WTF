import SwiftUI
import AppKit

extension ScenarioWriterView {

    // --- Key Handling Logic ---
    func handleGlobalKeyPress(_ press: KeyPress) -> KeyPress.Result {
        if let handled = handleSplitPaneCycleShortcut(press) { return handled }
        if !acceptsKeyboardInput { return .ignored }

        let isNoModifier =
            !press.modifiers.contains(.command) &&
            !press.modifiers.contains(.option) &&
            !press.modifiers.contains(.control) &&
            !press.modifiers.contains(.shift)

        if let handled = handleDeleteAlertShortcut(press) { return handled }

        let isMainEditorTyping = !showHistoryBar && editingCardID != nil
        let isTimelineSearchTyping = !showHistoryBar && isSearchFocused
        let isHistorySearchTyping = showHistoryBar && isNamedSnapshotSearchFocused
        let isHistoryNoteTyping = showHistoryBar && isNamedSnapshotNoteEditing && isNamedSnapshotNoteEditorFocused
        let isTyping = isMainEditorTyping || isTimelineSearchTyping || isHistorySearchTyping || isHistoryNoteTyping
        if let handled = handleDownPhaseShortcuts(
            press,
            isMainEditorTyping: isMainEditorTyping,
            isNoModifier: isNoModifier,
            isTyping: isTyping
        ) { return handled }

        if let handled = handleHistoryNavigationShortcut(press, isTyping: isTyping) { return handled }

        if showHistoryBar {
            if let handled = handleHistoryPreviewClipboardShortcut(press, isTyping: isTyping) {
                return handled
            }
            if isTyping { return .ignored }
            // Do not let history mode keystrokes mutate live scenario state.
            return .handled
        }

        if isTyping {
            if let handled = handleTypingContextShortcut(press, isMainEditorTyping: isMainEditorTyping) { return handled }
            return .ignored
        }

        if let handled = handleClipboardShortcut(press) { return handled }
        if let handled = handleCommandShiftMoveShortcut(press) { return handled }
        if let handled = handleIdleArrowNavigationShortcut(press) { return handled }
        if let handled = handleCommandCreationAndSearchShortcut(press) { return handled }
        if let handled = handlePlainEntryShortcut(press) { return handled }

        return .ignored
    }

    func handleSplitPaneCycleShortcut(_ press: KeyPress) -> KeyPress.Result? {
        if press.phase == .down,
           press.key == .tab,
           press.modifiers.contains(.control),
           !press.modifiers.contains(.command),
           !press.modifiers.contains(.option),
           !press.modifiers.contains(.shift) {
            NotificationCenter.default.post(name: .waCycleSplitPaneRequested, object: nil)
            return .handled
        }
        return nil
    }

    func handleHistoryPreviewClipboardShortcut(_ press: KeyPress, isTyping: Bool) -> KeyPress.Result? {
        guard showHistoryBar else { return nil }
        guard isPreviewingHistory else { return nil }
        guard !isTyping else { return nil }
        guard press.phase == .down else { return nil }
        guard press.modifiers.contains(.command) else { return nil }
        let hasExtraModifier = press.modifiers.contains(.option) || press.modifiers.contains(.control) || press.modifiers.contains(.shift)
        guard !hasExtraModifier else { return nil }

        let normalized = press.characters.lowercased()
        if normalized == "c" || press.characters == "ㅊ" {
            DispatchQueue.main.async {
                copyHistoryPreviewCardsToClipboard()
            }
            return .handled
        }
        return nil
    }

    func handleDeleteAlertShortcut(_ press: KeyPress) -> KeyPress.Result? {
        guard showDeleteAlert, press.phase == .down else { return nil }
        let hasChildren = selectedCardsForDeletion().contains { !$0.children.isEmpty }
        if press.key == .escape {
            showDeleteAlert = false
            isMainViewFocused = true
            return .handled
        }
        if hasChildren && press.key == .return {
            showDeleteAlert = false
            isMainViewFocused = true
            return .handled
        }
        return nil
    }

    func handleDownPhaseShortcuts(
        _ press: KeyPress,
        isMainEditorTyping: Bool,
        isNoModifier: Bool,
        isTyping: Bool
    ) -> KeyPress.Result? {
        guard press.phase == .down else { return nil }

        if isMainEditorTyping && !showFocusMode && isNoModifier && press.key == .tab {
            let now = Date()
            let editingID = editingCardID
            let isArmed =
                mainEditTabArmCardID == editingID &&
                now.timeIntervalSince(mainEditTabArmAt) <= mainEditDoubleTabInterval
            if isArmed {
                clearMainEditTabArm()
                if editingID != nil {
                    suppressMainFocusRestoreAfterFinishEditing = true
                    DispatchQueue.main.async {
                        finishEditing()
                        addChildCard()
                    }
                }
                return .handled
            }
            mainEditTabArmCardID = editingID
            mainEditTabArmAt = now
            return .handled
        }

        if isMainEditorTyping &&
            press.key == .return &&
            press.modifiers.contains([.command, .option]) &&
            !press.modifiers.contains(.control) &&
            !press.modifiers.contains(.shift) {
            clearMainEditTabArm()
            DispatchQueue.main.async {
                splitCardAtCaret()
            }
            return .handled
        }

        if isMainEditorTyping &&
            !showFocusMode &&
            press.modifiers.contains(.command) &&
            !press.modifiers.contains(.option) &&
            !press.modifiers.contains(.control) &&
            !press.modifiers.contains(.shift) &&
            press.key == .return {
            if editingCardID != nil {
                clearMainEditTabArm()
                suppressMainFocusRestoreAfterFinishEditing = true
                DispatchQueue.main.async {
                    finishEditing()
                    insertSibling(above: false)
                }
                return .handled
            }
        }

        if press.key == .escape {
            if showHistoryBar {
                DispatchQueue.main.async { _ = handleHistoryEscape() }
                return .handled
            }
            if showFocusMode {
                return .handled
            }
            if isTyping {
                if editingCardID != nil {
                    clearMainEditTabArm()
                    DispatchQueue.main.async { finishEditing() }
                }
                else if isSearchFocused { DispatchQueue.main.async { closeSearch() } }
                return .handled
            } else if showTimeline {
                DispatchQueue.main.async { closeSearch() }
                return .handled
            }
            if isFullscreen {
                return .handled
            }
        }

        return nil
    }

    func handleHistoryNavigationShortcut(_ press: KeyPress, isTyping: Bool) -> KeyPress.Result? {
        guard (press.phase == .down || press.phase == .repeat) && showHistoryBar && !isTyping else { return nil }
        if press.modifiers.contains(.command) {
            switch press.key {
            case .leftArrow:
                DispatchQueue.main.async { jumpToPreviousNamedSnapshot() }
                return .handled
            case .rightArrow:
                DispatchQueue.main.async { jumpToNextNamedSnapshot() }
                return .handled
            default:
                break
            }
        } else {
            switch press.key {
            case .leftArrow:
                DispatchQueue.main.async { stepHistoryIndex(by: -1) }
                return .handled
            case .rightArrow:
                DispatchQueue.main.async { stepHistoryIndex(by: 1) }
                return .handled
            default:
                break
            }
        }
        return nil
    }

    func handleTypingContextShortcut(_ press: KeyPress, isMainEditorTyping: Bool) -> KeyPress.Result? {
        if isMainEditorTyping &&
            !showFocusMode &&
            press.phase == .down &&
            !press.modifiers.contains(.command) &&
            !press.modifiers.contains(.option) &&
            !press.modifiers.contains(.control) {
            switch press.key {
            case .upArrow, .downArrow, .leftArrow, .rightArrow:
                if handleMainEditorBoundaryNavigation(press) {
                    return .handled
                }
            default:
                break
            }
        }
        if press.phase == .down && press.key != .tab {
            clearMainEditTabArm()
        }
        if press.phase == .down && press.modifiers.contains(.command) {
            if press.characters == "f" || press.characters == "ㄹ" {
                DispatchQueue.main.async {
                    toggleSearch()
                }
                return .handled
            }
        }
        return nil
    }

    func handleClipboardShortcut(_ press: KeyPress) -> KeyPress.Result? {
        guard press.phase == .down && press.modifiers.contains(.command) else { return nil }
        let normalized = press.characters.lowercased()
        let hasExtraModifier = press.modifiers.contains(.option) || press.modifiers.contains(.control) || press.modifiers.contains(.shift)
        if !hasExtraModifier && (normalized == "c" || press.characters == "ㅊ") {
            DispatchQueue.main.async { copySelectedCardTreeToClipboard() }
            return .handled
        }
        if !hasExtraModifier && (normalized == "x" || press.characters == "ㅌ") {
            DispatchQueue.main.async { cutSelectedCardTreeToClipboard() }
            return .handled
        }
        if !hasExtraModifier && (normalized == "v" || press.characters == "ㅍ") {
            DispatchQueue.main.async { pasteCopiedCardTree() }
            return .handled
        }
        return nil
    }

    func handleCommandShiftMoveShortcut(_ press: KeyPress) -> KeyPress.Result? {
        guard press.phase == .down && press.modifiers.contains([.command, .shift]) else { return nil }
        switch press.key {
        case .upArrow:
            DispatchQueue.main.async { moveCardHierarchy(direction: .up) }
            return .handled
        case .downArrow:
            DispatchQueue.main.async { moveCardHierarchy(direction: .down) }
            return .handled
        case .leftArrow:
            DispatchQueue.main.async { moveCardHierarchy(direction: .left) }
            return .handled
        case .rightArrow:
            DispatchQueue.main.async { moveCardHierarchy(direction: .right) }
            return .handled
        default:
            break
        }
        return nil
    }

    func handleIdleArrowNavigationShortcut(_ press: KeyPress) -> KeyPress.Result? {
        guard !press.modifiers.contains(.command),
              !press.modifiers.contains(.option),
              !press.modifiers.contains(.control) else { return nil }
        switch press.key {
        case .upArrow, .downArrow, .leftArrow, .rightArrow:
            return handleNavigation(press: press)
        default:
            return nil
        }
    }

    func handleCommandCreationAndSearchShortcut(_ press: KeyPress) -> KeyPress.Result? {
        guard press.phase == .down && press.modifiers.contains(.command) else { return nil }
        if press.modifiers.contains(.shift) && (press.key == .delete || press.key == .init("\u{7f}")) {
            DispatchQueue.main.async { deleteSelectedCard() }
            return .handled
        }
        if press.characters == "f" || press.characters == "ㄹ" {
            DispatchQueue.main.async {
                toggleSearch()
            }
            return .handled
        }
        if press.modifiers.contains(.shift) && (press.characters == "]" || press.characters == "}") {
            DispatchQueue.main.async { toggleTimeline() }
            return .handled
        }
        if !showFocusMode {
            switch press.key {
            case .upArrow:
                DispatchQueue.main.async { insertSibling(above: true) }
                return .handled
            case .downArrow, .return:
                DispatchQueue.main.async { insertSibling(above: false) }
                return .handled
            case .rightArrow:
                DispatchQueue.main.async { addChildCard() }
                return .handled
            default:
                break
            }
        }
        if press.modifiers.contains(.option) {
            switch press.key {
            case .upArrow:
                DispatchQueue.main.async { insertSibling(above: true) }
                return .handled
            case .downArrow, .return:
                DispatchQueue.main.async { insertSibling(above: false) }
                return .handled
            case .rightArrow:
                DispatchQueue.main.async { addChildCard() }
                return .handled
            default:
                break
            }
        }
        return nil
    }

    func handlePlainEntryShortcut(_ press: KeyPress) -> KeyPress.Result? {
        guard press.phase == .down else { return nil }
        switch press.key {
        case .tab:
            DispatchQueue.main.async { addChildCard() }
            return .handled
        case .return:
            if let activeID = activeCardID {
                DispatchQueue.main.async {
                    if let card = findCard(by: activeID) {
                        editingStartContent = card.content
                    }
                    editingStartState = captureScenarioState()
                    editingIsNewCard = false
                    editingCardID = activeID
                }
            }
            return .handled
        default:
            return nil
        }
    }

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
        guard let editingID = editingCardID,
              let editingCard = findCard(by: editingID) else { return false }
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
        guard textView.string == editingCard.content else { return false }
        guard !textView.hasMarkedText() else { return false }

        let levels = resolvedAllLevels()
        guard let location = scenario.cardLocationByID(editingID) else { return false }
        let levelIndex = location.level
        let cardIndex = location.index
        guard levels.indices.contains(levelIndex),
              levels[levelIndex].indices.contains(cardIndex) else { return false }

        let currentLevel = levels[levelIndex]
        let content = textView.string as NSString
        let cursor = min(max(0, textView.selectedRange().location), content.length)
        let visualBoundary = focusCaretVisualBoundaryState(textView: textView, cursor: cursor)
        let atTopBoundary = (cursor == 0) && (visualBoundary?.isTop ?? true)
        let atBottomBoundary = (cursor == content.length) && (visualBoundary?.isBottom ?? true)
        let isRepeat = (press.phase == .repeat)
        let shouldDiscardEmptyNewCardOnBoundaryMove =
            editingIsNewCard &&
            editingCard.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isShiftSelection = press.modifiers.contains(.shift)

        switch press.key {
        case .upArrow:
            return handleMainBoundaryUpArrow(
                press: press,
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
            return handleMainBoundaryDownArrow(
                press: press,
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
                press: press,
                editingCard: editingCard,
                currentLevel: currentLevel,
                atTopBoundary: atTopBoundary,
                cursor: cursor,
                shouldDiscardEmptyNewCardOnBoundaryMove: shouldDiscardEmptyNewCardOnBoundaryMove,
                isShiftSelection: isShiftSelection
            )

        case .rightArrow:
            return handleMainBoundaryRightArrow(
                press: press,
                editingCard: editingCard,
                currentLevel: currentLevel,
                levels: levels,
                levelIndex: levelIndex,
                cardIndex: cardIndex,
                atBottomBoundary: atBottomBoundary,
                cursor: cursor,
                contentLength: content.length,
                shouldDiscardEmptyNewCardOnBoundaryMove: shouldDiscardEmptyNewCardOnBoundaryMove,
                isShiftSelection: isShiftSelection
            )

        default:
            clearMainBoundaryParentLeftArm()
            clearMainBoundaryChildRightArm()
            clearMainNoChildRightArm()
            return false
        }
    }

    func handleMainBoundaryUpArrow(
        press: KeyPress,
        editingCard: SceneCard,
        currentLevel: [SceneCard],
        levelIndex: Int,
        cardIndex: Int,
        atTopBoundary: Bool,
        shouldDiscardEmptyNewCardOnBoundaryMove: Bool,
        isShiftSelection: Bool,
        isRepeat: Bool
    ) -> Bool {
        guard atTopBoundary, cardIndex > 0 else { return false }
        let target = currentLevel[cardIndex - 1]
        if isRepeat && levelIndex >= 2 && target.category != editingCard.category {
            return true
        }
        clearMainEditTabArm()
        clearMainBoundaryParentLeftArm()
        clearMainBoundaryChildRightArm()
        clearMainNoChildRightArm()
        if isShiftSelection && press.phase == .down {
            applyMainBoundaryShiftSelection(from: editingCard, to: target, in: currentLevel)
            return true
        }
        let targetLength = (target.content as NSString).length
        switchMainEditingTarget(
            to: target,
            caretLocation: targetLength,
            shouldDiscardEmptyNewCardOnBoundaryMove: shouldDiscardEmptyNewCardOnBoundaryMove
        )
        return true
    }

    func handleMainBoundaryDownArrow(
        press: KeyPress,
        editingCard: SceneCard,
        currentLevel: [SceneCard],
        levelIndex: Int,
        cardIndex: Int,
        atBottomBoundary: Bool,
        shouldDiscardEmptyNewCardOnBoundaryMove: Bool,
        isShiftSelection: Bool,
        isRepeat: Bool
    ) -> Bool {
        guard atBottomBoundary, cardIndex < currentLevel.count - 1 else { return false }
        let target = currentLevel[cardIndex + 1]
        if isRepeat && levelIndex >= 2 && target.category != editingCard.category {
            return true
        }
        clearMainEditTabArm()
        clearMainBoundaryParentLeftArm()
        clearMainBoundaryChildRightArm()
        clearMainNoChildRightArm()
        if isShiftSelection && press.phase == .down {
            applyMainBoundaryShiftSelection(from: editingCard, to: target, in: currentLevel)
            return true
        }
        switchMainEditingTarget(
            to: target,
            caretLocation: 0,
            shouldDiscardEmptyNewCardOnBoundaryMove: shouldDiscardEmptyNewCardOnBoundaryMove
        )
        return true
    }

    func handleMainBoundaryLeftArrow(
        press: KeyPress,
        editingCard: SceneCard,
        currentLevel: [SceneCard],
        atTopBoundary: Bool,
        cursor: Int,
        shouldDiscardEmptyNewCardOnBoundaryMove: Bool,
        isShiftSelection: Bool
    ) -> Bool {
        guard atTopBoundary, cursor == 0 else {
            clearMainBoundaryParentLeftArm()
            return false
        }
        guard let parentCard = editingCard.parent else {
            clearMainBoundaryParentLeftArm()
            return false
        }
        guard press.phase == .down else {
            return true
        }

        clearMainEditTabArm()
        clearMainBoundaryChildRightArm()
        clearMainNoChildRightArm()
        if isShiftSelection {
            applyMainBoundaryShiftSelection(from: editingCard, to: parentCard, in: currentLevel)
            return true
        }
        if isMainBoundaryParentLeftArmed(for: editingCard.id) {
            clearMainBoundaryParentLeftArm()
            let parentLength = (parentCard.content as NSString).length
            switchMainEditingTarget(
                to: parentCard,
                caretLocation: parentLength,
                shouldDiscardEmptyNewCardOnBoundaryMove: shouldDiscardEmptyNewCardOnBoundaryMove
            )
            return true
        }

        armMainBoundaryParentLeft(for: editingCard.id)
        return true
    }

    func handleMainBoundaryRightArrow(
        press: KeyPress,
        editingCard: SceneCard,
        currentLevel: [SceneCard],
        levels: [[SceneCard]],
        levelIndex: Int,
        cardIndex: Int,
        atBottomBoundary: Bool,
        cursor: Int,
        contentLength: Int,
        shouldDiscardEmptyNewCardOnBoundaryMove: Bool,
        isShiftSelection: Bool
    ) -> Bool {
        guard atBottomBoundary, cursor == contentLength else {
            clearMainBoundaryChildRightArm()
            clearMainNoChildRightArm()
            return false
        }
        guard press.phase == .down else {
            return true
        }

        clearMainEditTabArm()
        clearMainBoundaryParentLeftArm()
        let nextLevel = (levelIndex + 1 < levels.count) ? levels[levelIndex + 1] : []

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
                switchMainEditingTarget(
                    to: target,
                    caretLocation: 0,
                    shouldDiscardEmptyNewCardOnBoundaryMove: shouldDiscardEmptyNewCardOnBoundaryMove
                )
            }
            return true
        }

        if preferredChild(for: editingCard, matching: editingCard.category) == nil {
            armMainNoChildRight(for: editingCard.id)
        }
        armMainBoundaryChildRight(for: editingCard.id)
        return true
    }

    func applyMainBoundaryShiftSelection(from editingCard: SceneCard, to target: SceneCard, in level: [SceneCard]) {
        finishEditing()
        changeActiveCard(to: target, shouldFocusMain: false, deferToMainAsync: false)
        updateKeyboardRangeSelection(from: editingCard, to: target, in: level)
    }

    func switchMainEditingTarget(
        to target: SceneCard,
        caretLocation: Int,
        shouldDiscardEmptyNewCardOnBoundaryMove: Bool
    ) {
        if shouldDiscardEmptyNewCardOnBoundaryMove {
            finishEditing()
        }
        changeActiveCard(to: target, shouldFocusMain: false, deferToMainAsync: false)
        selectedCardIDs = [target.id]
        editingCardID = target.id
        editingStartContent = target.content
        editingStartState = captureScenarioState()
        editingIsNewCard = false
        mainCaretLocationByCardID[target.id] = caretLocation
        requestMainCaretRestore(for: target.id)
        requestCoalescedMainCaretEnsure(minInterval: mainCaretSelectionEnsureMinInterval, delay: 0.0)
    }

    // --- Main Nav Key Monitor ---
    func startMainNavKeyMonitor() {
        if mainNavKeyMonitor != nil { return }
        mainNavKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let isReferenceWindowEvent = event.window?.identifier?.rawValue == ReferenceWindowConstants.windowID
            let isReferenceWindowKey = NSApp.keyWindow?.identifier?.rawValue == ReferenceWindowConstants.windowID
            if isReferenceWindowEvent || isReferenceWindowKey {
                return event
            }
            if !acceptsKeyboardInput { return event }
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
            let isCmdOnly = flags.contains(.command) && !flags.contains(.option) && !flags.contains(.control) && !flags.contains(.shift)
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
            if editingCardID != nil || isSearchFocused { return event }
            if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) || event.modifierFlags.contains(.control) {
                return event
            }
            if handleNavigationKeyCode(event.keyCode, isRepeat: event.isARepeat, isShiftPressed: flags.contains(.shift)) {
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

            guard let preferred = preferredChild(for: entry.element, matching: category),
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

    enum MainRightResolution {
        case target(SceneCard)
        case armed
        case unavailable
    }

    enum MainArrowDirection {
        case up
        case down
        case left
        case right
    }

    func resolvedMainRightTarget(
        for card: SceneCard,
        currentLevel: [SceneCard],
        nextLevel: [SceneCard],
        currentIndex: Int,
        allowDoublePressFallback: Bool
    ) -> MainRightResolution {
        if let child = preferredChild(for: card, matching: card.category) {
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

        let levels = resolvedAllLevels()
        guard let location = scenario.cardLocationByID(id) else { return false }
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
            guard cardIndex > 0 else { return false }
            let target = currentLevel[cardIndex - 1]
            if isRepeat && levelIndex >= 2 && target.category != card.category {
                return true
            }
            changeActiveCard(to: target, deferToMainAsync: false)
            if isShiftPressed {
                updateKeyboardRangeSelection(from: card, to: target, in: currentLevel)
            } else {
                selectedCardIDs = [target.id]
                clearKeyboardRangeSelectionAnchor()
            }
            return true

        case .down:
            clearMainNoChildRightArm()
            if cardIndex < currentLevel.count - 1 {
                let target = currentLevel[cardIndex + 1]
                if isRepeat && levelIndex >= 2 && target.category != card.category {
                    return true
                }
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
                return true
            }
            return false

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
            changeActiveCard(to: parent, deferToMainAsync: false)
            selectedCardIDs = [parent.id]
            clearKeyboardRangeSelectionAnchor()
            return true
        }
    }

    // --- Navigation Key Code Handler ---
    func handleNavigationKeyCode(_ keyCode: UInt16, isRepeat: Bool = false, isShiftPressed: Bool = false) -> Bool {
        switch keyCode {
        case 126: // up
            return performMainArrowNavigation(
                .up,
                isRepeat: isRepeat,
                isShiftPressed: isShiftPressed,
                consumeRightArrowWhenUnavailable: false,
                seedRangeAnchorWhenNoActive: true
            )
        case 125: // down
            return performMainArrowNavigation(
                .down,
                isRepeat: isRepeat,
                isShiftPressed: isShiftPressed,
                consumeRightArrowWhenUnavailable: false,
                seedRangeAnchorWhenNoActive: true
            )
        case 124: // right
            return performMainArrowNavigation(
                .right,
                isRepeat: isRepeat,
                isShiftPressed: isShiftPressed,
                consumeRightArrowWhenUnavailable: true,
                seedRangeAnchorWhenNoActive: true
            )
        case 123: // left
            return performMainArrowNavigation(
                .left,
                isRepeat: isRepeat,
                isShiftPressed: isShiftPressed,
                consumeRightArrowWhenUnavailable: false,
                seedRangeAnchorWhenNoActive: true
            )
        default:
            clearMainNoChildRightArm()
            break
        }
        return false
    }

    // --- Navigation Press Handler ---
    func handleNavigation(press: KeyPress) -> KeyPress.Result {
        if activeCardID == nil && scenario.rootCards.isEmpty {
            return .ignored
        }
        let isShiftPressed = press.modifiers.contains(.shift)
        let isRepeat = (press.phase == .repeat)
        switch press.key {
        case .upArrow:
            _ = performMainArrowNavigation(
                .up,
                isRepeat: isRepeat,
                isShiftPressed: isShiftPressed,
                consumeRightArrowWhenUnavailable: false,
                seedRangeAnchorWhenNoActive: false
            )
        case .downArrow:
            _ = performMainArrowNavigation(
                .down,
                isRepeat: isRepeat,
                isShiftPressed: isShiftPressed,
                consumeRightArrowWhenUnavailable: false,
                seedRangeAnchorWhenNoActive: false
            )
        case .rightArrow:
            _ = performMainArrowNavigation(
                .right,
                isRepeat: isRepeat,
                isShiftPressed: isShiftPressed,
                consumeRightArrowWhenUnavailable: false,
                seedRangeAnchorWhenNoActive: false
            )
        case .leftArrow:
            _ = performMainArrowNavigation(
                .left,
                isRepeat: isRepeat,
                isShiftPressed: isShiftPressed,
                consumeRightArrowWhenUnavailable: false,
                seedRangeAnchorWhenNoActive: false
            )
        default: return .ignored
        }
        return .handled
    }

    // --- Card Hierarchy Move Logic (Keyboard) ---
    enum MoveDirection { case up, down, left, right }

    func moveCardHierarchy(direction: MoveDirection) {
        guard let id = activeCardID, let card = findCard(by: id) else { return }
        let prevState = captureScenarioState()

        normalizeIndices(parent: card.parent)
        let siblings = card.parent?.sortedChildren ?? scenario.rootCards
        guard let currentIndex = siblings.firstIndex(where: { $0.id == id }) else { return }

        switch direction {
        case .up, .down:
            moveCardWithinLevel(card: card, direction: direction)
            normalizeIndices(parent: card.parent)
            card.updateDescendantsCategory(card.parent?.category)
            changeActiveCard(to: card)
            commitCardMutation(
                previousState: prevState,
                actionName: "카드 이동"
            )
            return
        case .left:
            if let parent = card.parent {
                let pIdx = parent.orderIndex
                let grandSiblings = parent.parent?.sortedChildren ?? scenario.rootCards
                for s in grandSiblings where s.orderIndex > pIdx { s.orderIndex += 1 }
                card.parent = parent.parent
                card.orderIndex = pIdx + 1
            }
        case .right:
            if currentIndex > 0 {
                let targetParent = siblings[currentIndex - 1]
                card.parent = targetParent
                card.orderIndex = targetParent.children.count
            }
        }

        normalizeIndices(parent: card.parent)
        card.updateDescendantsCategory(card.parent?.category)
        changeActiveCard(to: card)
        commitCardMutation(
            previousState: prevState,
            actionName: "카드 이동"
        )
    }

    func moveCardWithinLevel(card: SceneCard, direction: MoveDirection) {
        let levels = resolvedAllLevels()
        guard let levelIndex = levels.firstIndex(where: { $0.contains(where: { $0.id == card.id }) }) else { return }
        let level = levels[levelIndex]
        guard let idx = level.firstIndex(where: { $0.id == card.id }) else { return }
        let targetIndex = (direction == .up) ? idx - 1 : idx + 1
        guard targetIndex >= 0 && targetIndex < level.count else { return }
        let target = level[targetIndex]
        let oldParent = card.parent
        let newParent = target.parent

        normalizeIndices(parent: oldParent)
        normalizeIndices(parent: newParent)

        if oldParent?.id == newParent?.id {
            let newIndex = target.orderIndex + (direction == .down ? 1 : 0)
            for s in (newParent?.sortedChildren ?? scenario.rootCards) where s.orderIndex >= newIndex { s.orderIndex += 1 }
            card.orderIndex = newIndex
        } else {
            let newIndex = target.orderIndex + (direction == .down ? 1 : 0)
            for s in (newParent?.sortedChildren ?? scenario.rootCards) where s.orderIndex >= newIndex { s.orderIndex += 1 }
            card.parent = newParent
            card.orderIndex = newIndex
        }

        normalizeIndices(parent: oldParent)
        normalizeIndices(parent: card.parent)
    }

    func normalizeIndices(parent: SceneCard?) {
        let siblings = parent?.sortedChildren ?? scenario.rootCards
        for (index, s) in siblings.enumerated() { s.orderIndex = index }
    }
}
