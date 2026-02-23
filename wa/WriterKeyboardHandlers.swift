import SwiftUI
import AppKit

extension ScenarioWriterView {

    // --- Key Handling Logic ---
    func handleGlobalKeyPress(_ press: KeyPress) -> KeyPress.Result {
        let isNoModifier =
            !press.modifiers.contains(.command) &&
            !press.modifiers.contains(.option) &&
            !press.modifiers.contains(.control) &&
            !press.modifiers.contains(.shift)
        if showDeleteAlert && press.phase == .down {
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
        }
        let isMainEditorTyping = !showHistoryBar && editingCardID != nil
        let isTimelineSearchTyping = !showHistoryBar && isSearchFocused
        let isHistorySearchTyping = showHistoryBar && isNamedSnapshotSearchFocused
        let isHistoryNoteTyping = showHistoryBar && isNamedSnapshotNoteEditing && isNamedSnapshotNoteEditorFocused
        let isTyping = isMainEditorTyping || isTimelineSearchTyping || isHistorySearchTyping || isHistoryNoteTyping
        if press.phase == .down {
            if showFocusMode && press.modifiers.contains([.command, .shift]) {
                let normalized = press.characters.lowercased()
                if normalized == "t" || press.characters == "ㅅ" || press.characters == "ㅆ" {
                    DispatchQueue.main.async {
                        focusTypewriterEnabled.toggle()
                        requestFocusModeCaretEnsure(typewriter: focusTypewriterEnabled, delay: 0.0)
                    }
                    return .handled
                }
            }
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
            if isMainEditorTyping && !showFocusMode && press.modifiers.contains(.command) && press.key == .return {
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
            }
        }
        if (press.phase == .down || press.phase == .repeat) && showHistoryBar && !isTyping {
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
        }
        if showHistoryBar {
            if isTyping { return .ignored }
            // Do not let history mode keystrokes mutate live scenario state.
            return .handled
        }
        if isTyping {
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
            return .ignored
        }

        if press.phase == .down && press.modifiers.contains(.command) {
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
        }

        if press.phase == .down && press.modifiers.contains([.command, .shift]) {
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
            default: break
            }
        }

        if !press.modifiers.contains(.command) && !press.modifiers.contains(.option) && !press.modifiers.contains(.control) {
            switch press.key { case .upArrow, .downArrow, .leftArrow, .rightArrow: return handleNavigation(press: press); default: break }
        }
            if press.phase == .down && press.modifiers.contains(.command) {
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
                if press.modifiers.contains(.shift) && (press.characters == "]" || press.characters == "}") { DispatchQueue.main.async { toggleTimeline() }; return .handled }
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
                    default: break
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
                    default: break
                    }
                }
            }
        if press.phase == .down {
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
            default: break
            }
        }
        return .ignored
    }

    func clearMainEditTabArm() {
        mainEditTabArmCardID = nil
        mainEditTabArmAt = .distantPast
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
            if handleNavigationKeyCode(event.keyCode, isRepeat: event.isARepeat) {
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

    // --- Navigation Key Code Handler ---
    func handleNavigationKeyCode(_ keyCode: UInt16, isRepeat: Bool = false) -> Bool {
        guard let id = activeCardID else {
            if let first = scenario.rootCards.first {
                changeActiveCard(to: first, deferToMainAsync: false)
                selectedCardIDs = [first.id]
                return true
            }
            return false
        }
        let levels = getAllLevels()
        guard let location = scenario.cardLocationByID(id) else { return false }
        let lIdx = location.level
        let cIdx = location.index
        guard levels.indices.contains(lIdx), levels[lIdx].indices.contains(cIdx) else { return false }
        let currentLevel = levels[lIdx]
        let nextLevel = (lIdx + 1 < levels.count) ? levels[lIdx + 1] : []
        let card = currentLevel[cIdx]
        if selectedCardIDs.count > 1 { selectedCardIDs = [card.id] }

        switch keyCode {
        case 126: // up
            clearMainNoChildRightArm()
            if cIdx > 0 {
                let target = currentLevel[cIdx - 1]
                // Block key-repeat from crossing category boundary (level >= 2)
                if isRepeat && lIdx >= 2 && target.category != card.category { return true }
                changeActiveCard(to: target, deferToMainAsync: false)
                selectedCardIDs = [target.id]
                return true
            }
        case 125: // down
            clearMainNoChildRightArm()
            if cIdx < currentLevel.count - 1 {
                let target = currentLevel[cIdx + 1]
                // Block key-repeat from crossing category boundary (level >= 2)
                if isRepeat && lIdx >= 2 && target.category != card.category { return true }
                changeActiveCard(to: target, deferToMainAsync: false)
                selectedCardIDs = [target.id]
                return true
            }
            if requestMainBottomRevealIfNeeded(currentLevel: currentLevel, currentIndex: cIdx, card: card) {
                return true
            }
        case 124: // right
            let result = resolvedMainRightTarget(
                for: card,
                currentLevel: currentLevel,
                nextLevel: nextLevel,
                currentIndex: cIdx,
                allowDoublePressFallback: !isRepeat
            )
            if case .target(let target) = result {
                changeActiveCard(to: target, deferToMainAsync: false)
                selectedCardIDs = [target.id]
            }
            // Consume right-arrow in main nav even when no move, so arm/double-press
            // state is not re-processed by the parallel SwiftUI onKeyPress path.
            return true
        case 123: // left
            clearMainNoChildRightArm()
            if let p = card.parent {
                changeActiveCard(to: p, deferToMainAsync: false)
                selectedCardIDs = [p.id]
                return true
            }
        default:
            clearMainNoChildRightArm()
            break
        }
        return false
    }

    // --- Navigation Press Handler ---
    func handleNavigation(press: KeyPress) -> KeyPress.Result {
        guard let id = activeCardID else { if let first = scenario.rootCards.first { changeActiveCard(to: first, deferToMainAsync: false); selectedCardIDs = [first.id]; return .handled }; return .ignored }
        let levels = getAllLevels(); guard let location = scenario.cardLocationByID(id) else { return .handled }
        let lIdx = location.level
        let cIdx = location.index
        guard levels.indices.contains(lIdx), levels[lIdx].indices.contains(cIdx) else { return .handled }
        let currentLevel = levels[lIdx]; let nextLevel = (lIdx + 1 < levels.count) ? levels[lIdx + 1] : []; let card = currentLevel[cIdx]
        if selectedCardIDs.count > 1 { selectedCardIDs = [card.id] }
        let isRepeat = (press.phase == .repeat)
        switch press.key {
        case .upArrow:
            clearMainNoChildRightArm()
            if cIdx > 0 {
                let target = currentLevel[cIdx - 1]
                // Block key-repeat from crossing category boundary (level >= 2)
                if isRepeat && lIdx >= 2 && target.category != card.category { break }
                changeActiveCard(to: target, deferToMainAsync: false)
                selectedCardIDs = [target.id]
            }
        case .downArrow:
            clearMainNoChildRightArm()
            if cIdx < currentLevel.count - 1 {
                let target = currentLevel[cIdx + 1]
                // Block key-repeat from crossing category boundary (level >= 2)
                if isRepeat && lIdx >= 2 && target.category != card.category { break }
                changeActiveCard(to: target, deferToMainAsync: false)
                selectedCardIDs = [target.id]
            }
            else {
                _ = requestMainBottomRevealIfNeeded(currentLevel: currentLevel, currentIndex: cIdx, card: card)
            }
        case .rightArrow:
            let allowDoublePressFallback = (press.phase == .down)
            let result = resolvedMainRightTarget(
                for: card,
                currentLevel: currentLevel,
                nextLevel: nextLevel,
                currentIndex: cIdx,
                allowDoublePressFallback: allowDoublePressFallback
            )
            if case .target(let target) = result {
                changeActiveCard(to: target, deferToMainAsync: false)
                selectedCardIDs = [target.id]
            }
        case .leftArrow:
            clearMainNoChildRightArm()
            if let p = card.parent {
                changeActiveCard(to: p, deferToMainAsync: false)
                selectedCardIDs = [p.id]
            }
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
            store.saveAll()
            takeSnapshot()
            changeActiveCard(to: card)
            pushUndoState(prevState, actionName: "카드 이동")
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
        store.saveAll()
        takeSnapshot()
        changeActiveCard(to: card)
        pushUndoState(prevState, actionName: "카드 이동")
    }

    func moveCardWithinLevel(card: SceneCard, direction: MoveDirection) {
        let levels = getAllLevels()
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
