import SwiftUI
import AppKit

extension ScenarioWriterView {

    // --- Key Handling Logic ---
    var isMainEditingParentChildBoundaryNavigationEnabled: Bool { false }

    private func monitoredMainKeyboardKeyName(for press: KeyPress) -> String? {
        switch press.key {
        case .return: "return"
        case .escape: "escape"
        case .leftArrow: "left"
        case .rightArrow: "right"
        case .upArrow: "up"
        case .downArrow: "down"
        default: nil
        }
    }

    func monitoredMainKeyboardKeyName(for event: NSEvent) -> String? {
        switch event.keyCode {
        case 36, 76: "return"
        case 53: "escape"
        case 123: "left"
        case 124: "right"
        case 125: "down"
        case 126: "up"
        default: nil
        }
    }

    func logMonitoredMainKeyboardEvent(
        source: String,
        key: String,
        phase: String,
        details: String = ""
    ) {
        let expectedText = (editingCardID ?? activeCardID).flatMap { findCard(by: $0)?.content }
        let suffix = details.isEmpty ? "" : " \(details)"
        mainWorkspacePhase0Log(
            "main-key-flow",
            "source=\(source) key=\(key) phase=\(phase) " +
            "active=\(mainWorkspacePhase0CardID(activeCardID)) editing=\(mainWorkspacePhase0CardID(editingCardID)) " +
            "mainFocused=\(isMainViewFocused) acceptsKeyboard=\(acceptsKeyboardInput) " +
            "responder=\(mainWorkspacePhase0ResponderSummary(expectedText: expectedText))\(suffix)"
        )
    }

    func handleGlobalKeyPress(_ press: KeyPress) -> KeyPress.Result {
        if isIndexBoardInlineEditing {
            return .ignored
        }
        if let handled = handleSplitPaneCycleShortcut(press) { return handled }
        if let handled = handleIndexBoardToggleShortcut(press) { return handled }
        if let handled = handleIndexBoardKeyPress(press) { return handled }
        let monitoredKey = monitoredMainKeyboardKeyName(for: press)
        if !acceptsKeyboardInput {
            if let monitoredKey, press.phase != .repeat {
                logMonitoredMainKeyboardEvent(
                    source: "swiftui",
                    key: monitoredKey,
                    phase: String(describing: press.phase),
                    details: "result=ignored reason=acceptsKeyboardInput=false"
                )
            }
            return .ignored
        }

        let isNoModifier =
            !press.modifiers.contains(.command) &&
            !press.modifiers.contains(.option) &&
            !press.modifiers.contains(.control) &&
            !press.modifiers.contains(.shift)

        if let handled = handleDeleteAlertShortcut(press) { return handled }

        let isMainEditorTyping = !showHistoryBar && isMainEditorActivelyTyping()
        let isTimelineSearchTyping = !showHistoryBar && isSearchFocused
        let isHistorySearchTyping = showHistoryBar && isNamedSnapshotSearchFocused
        let isHistoryNoteTyping = showHistoryBar && isNamedSnapshotNoteEditing && isNamedSnapshotNoteEditorFocused
        let isAIChatTyping = !showHistoryBar && showAIChat && isAIChatInputFocused
        let isTyping = isMainEditorTyping || isTimelineSearchTyping || isHistorySearchTyping || isHistoryNoteTyping || isAIChatTyping
        if let monitoredKey, press.phase != .repeat {
            logMonitoredMainKeyboardEvent(
                source: "swiftui",
                key: monitoredKey,
                phase: String(describing: press.phase),
                details: "typing=\(isTyping) mainEditorTyping=\(isMainEditorTyping)"
            )
        }
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

        if isAIChatTyping {
            if press.phase == .down &&
                press.key == .return &&
                !press.modifiers.contains(.command) &&
                !press.modifiers.contains(.option) &&
                !press.modifiers.contains(.control) &&
                !press.modifiers.contains(.shift) {
                DispatchQueue.main.async {
                    sendAIChatMessage()
                }
                return .handled
            }
            return .ignored
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

    func handleIndexBoardToggleShortcut(_ press: KeyPress) -> KeyPress.Result? {
        guard press.phase == .down else { return nil }
        guard press.modifiers.contains(.command) else { return nil }
        guard !press.modifiers.contains(.option),
              !press.modifiers.contains(.control),
              !press.modifiers.contains(.shift) else { return nil }

        let normalized = press.characters.lowercased()
        guard normalized == "b" || press.characters == "ㅠ" else { return nil }

        DispatchQueue.main.async {
            handleOpenIndexBoardRequestNotification()
        }
        return .handled
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

    func isClonePastePlacementEnabled(_ placement: ClonePastePlacement) -> Bool {
        switch placement {
        case .child:
            return activeCardID != nil
        case .sibling:
            return true
        }
    }

    func resetFountainClipboardPasteDialogSelection() {
        fountainClipboardPasteSelection = .plainText
    }

    func moveFountainClipboardPasteDialogSelection() {
        switch fountainClipboardPasteSelection {
        case .plainText:
            fountainClipboardPasteSelection = .sceneCards
        case .sceneCards:
            fountainClipboardPasteSelection = .plainText
        }
    }

    func confirmFountainClipboardPasteDialogSelection() {
        applyFountainClipboardPasteSelection(fountainClipboardPasteSelection)
    }

    func handleFountainClipboardPasteDialogKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard showFountainClipboardPasteDialog else { return .ignored }
        if press.modifiers.contains(.command) || press.modifiers.contains(.option) || press.modifiers.contains(.control) {
            return .handled
        }
        switch press.key {
        case .upArrow, .downArrow:
            moveFountainClipboardPasteDialogSelection()
            return .handled
        case .return:
            if press.phase == .down {
                confirmFountainClipboardPasteDialogSelection()
            }
            return .handled
        case .escape:
            if press.phase == .down {
                cancelFountainClipboardPasteDialog()
            }
            return .handled
        default:
            return .handled
        }
    }

    func handleFountainClipboardPasteDialogKeyDownEvent(_ event: NSEvent) -> Bool {
        guard showFountainClipboardPasteDialog else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.option) || flags.contains(.control) {
            return true
        }
        switch event.keyCode {
        case 126, 125: // up/down
            DispatchQueue.main.async {
                moveFountainClipboardPasteDialogSelection()
            }
            return true
        case 36, 76: // return
            DispatchQueue.main.async {
                confirmFountainClipboardPasteDialogSelection()
            }
            return true
        case 53: // escape
            DispatchQueue.main.async {
                cancelFountainClipboardPasteDialog()
            }
            return true
        default:
            return true
        }
    }

    func isPlainPasteShortcut(_ press: KeyPress) -> Bool {
        let normalized = press.characters.lowercased()
        return normalized == "v" || press.characters == "ㅍ"
    }

    func resetClonePasteDialogSelection() {
        clonePasteDialogSelection = isClonePastePlacementEnabled(.child) ? .child : .sibling
    }

    func moveClonePasteDialogSelection() {
        if !isClonePastePlacementEnabled(.child) {
            clonePasteDialogSelection = .sibling
            return
        }
        switch clonePasteDialogSelection {
        case .child:
            clonePasteDialogSelection = .sibling
        case .sibling:
            clonePasteDialogSelection = .child
        }
    }

    func confirmClonePasteDialogSelection() {
        guard isClonePastePlacementEnabled(clonePasteDialogSelection) else { return }
        applyPendingPastePlacement(as: clonePasteDialogSelection)
    }

    func handleClonePasteDialogKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard showCloneCardPasteDialog else { return .ignored }
        if press.modifiers.contains(.command) || press.modifiers.contains(.option) || press.modifiers.contains(.control) {
            return .handled
        }
        switch press.key {
        case .upArrow, .downArrow:
            moveClonePasteDialogSelection()
            return .handled
        case .return:
            if press.phase == .down {
                confirmClonePasteDialogSelection()
            }
            return .handled
        case .escape:
            if press.phase == .down {
                cancelPendingPastePlacement()
            }
            return .handled
        default:
            return .handled
        }
    }

    func handleClonePasteDialogKeyDownEvent(_ event: NSEvent) -> Bool {
        guard showCloneCardPasteDialog else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.option) || flags.contains(.control) {
            return true
        }
        switch event.keyCode {
        case 126, 125: // up/down
            DispatchQueue.main.async {
                moveClonePasteDialogSelection()
            }
            return true
        case 36, 76: // return
            DispatchQueue.main.async {
                confirmClonePasteDialogSelection()
            }
            return true
        case 53: // escape
            DispatchQueue.main.async {
                cancelPendingPastePlacement()
            }
            return true
        default:
            return true
        }
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
                            finishEditing(reason: .transition)
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
                    finishEditing(reason: .transition)
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
                    DispatchQueue.main.async { finishEditing(reason: .explicitExit) }
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
        if isMainEditorTyping &&
            !showFocusMode &&
            press.phase == .down &&
            press.modifiers.contains(.command) &&
            !press.modifiers.contains(.option) &&
            !press.modifiers.contains(.control) &&
            !press.modifiers.contains(.shift) &&
            isPlainPasteShortcut(press) {
            guard let textView = resolvedActiveMainEditorTextView() else {
                return .ignored
            }
            if handleFountainClipboardPasteShortcutIfPossible(from: textView) {
                return .handled
            }
            return .ignored
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
            DispatchQueue.main.async { handlePasteShortcut() }
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
        if mainNavKeyMonitor != nil {
            return nil
        }
        guard !press.modifiers.contains(.command),
              !press.modifiers.contains(.option),
              !press.modifiers.contains(.control) else { return nil }
        if editingCardID != nil {
            return .handled
        }
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
            if let card = resolvedMainEditingTargetCard() {
                logMonitoredMainKeyboardEvent(
                    source: "swiftui",
                    key: "return",
                    phase: "dispatch",
                    details: "dispatch=beginCardEditing active=\(mainWorkspacePhase0CardID(card.id))"
                )
                DispatchQueue.main.async {
                    beginCardEditing(card)
                }
            } else {
                logMonitoredMainKeyboardEvent(
                    source: "swiftui",
                    key: "return",
                    phase: "dispatch",
                    details: "dispatch=none reason=noActiveCard"
                )
            }
            return .handled
        default:
            return nil
        }
    }
}
