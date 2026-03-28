import SwiftUI
import AppKit
import QuartzCore
import UniformTypeIdentifiers

extension ScenarioWriterView {

    func performDelete(_ card: SceneCard) {
        let prevState = captureScenarioState()
        if !card.children.isEmpty {
            if !card.content.isEmpty {
                createArchivedCopy(from: card)
            }
            card.content = ""
            isMainViewFocused = true
            commitCardMutation(
                previousState: prevState,
                actionName: "카드 삭제",
                forceSnapshot: true
            )
            return
        }

        let levelsBefore = resolvedAllLevels()
        let levelMap = levelsBefore.enumerated().reduce(into: [UUID: Int]()) { acc, entry in
            for c in entry.element { acc[c.id] = entry.offset }
        }
        let next = nextFocusAfterRemoval(
            removedIDs: [card.id],
            levelMap: levelMap,
            levels: levelsBefore,
            preferredAnchorID: card.id
        )
        card.isArchived = true
        scenario.bumpCardsVersion()
        if let n = next {
            suppressAutoScrollOnce = true
            suppressHorizontalAutoScroll = true
            changeActiveCard(to: n)
        } else {
            activeCardID = nil
            resetActiveRelationStateCache()
        }
        isMainViewFocused = true
        commitCardMutation(
            previousState: prevState,
            actionName: "카드 삭제",
            forceSnapshot: true
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { suppressHorizontalAutoScroll = false }
    }

    func performHardDelete(_ card: SceneCard) {
        finishEditing(reason: .transition)
        let idsToRemove = resolvedHardDeleteIDs(targetCard: card)
        guard !idsToRemove.isEmpty else { return }

        let prevState = captureScenarioState()
        let levelsBefore = resolvedAllLevels()
        let levelMap = buildLevelMap(from: levelsBefore)
        let preferredAnchorID = activeCardID ?? editingCardID ?? card.id
        let nextCandidate = nextFocusAfterRemoval(
            removedIDs: idsToRemove,
            levelMap: levelMap,
            levels: levelsBefore,
            preferredAnchorID: preferredAnchorID
        )

        applyHardDeleteMutations(idsToRemove)
        applyHardDeleteSelectionState(idsToRemove, nextCandidate: nextCandidate)
        applyHardDeleteEditorAndHistoryState(idsToRemove)

        clearFocusDeleteSelectionLock()
        isMainViewFocused = true
        commitCardMutation(
            previousState: prevState,
            actionName: "카드 완전 삭제",
            forceSnapshot: true,
            immediateSave: true,
            undoMode: .focusAware
        )
    }

    func performHardDeleteAllTimelineEmptyLeafCards() {
        finishEditing(reason: .transition)

        let idsToRemove: Set<UUID> = Set(
            scenario.cards.compactMap { card in
                guard card.children.isEmpty else { return nil }
                let isEmpty = card.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                return isEmpty ? card.id : nil
            }
        )
        guard !idsToRemove.isEmpty else { return }

        let prevState = captureScenarioState()
        let levelsBefore = resolvedAllLevels()
        let levelMap = buildLevelMap(from: levelsBefore)
        let preferredAnchorID = activeCardID ?? editingCardID
        let nextCandidate = nextFocusAfterRemoval(
            removedIDs: idsToRemove,
            levelMap: levelMap,
            levels: levelsBefore,
            preferredAnchorID: preferredAnchorID
        )

        applyHardDeleteMutations(idsToRemove)
        applyHardDeleteSelectionState(idsToRemove, nextCandidate: nextCandidate)
        applyHardDeleteEditorAndHistoryState(idsToRemove)

        clearFocusDeleteSelectionLock()
        isMainViewFocused = true
        commitCardMutation(
            previousState: prevState,
            actionName: "내용 없음 카드 전체 삭제",
            forceSnapshot: true,
            immediateSave: true,
            undoMode: .focusAware
        )
    }

    func resolvedHardDeleteIDs(targetCard card: SceneCard) -> Set<UUID> {
        let selected = selectedCardsForDeletion()
        let shouldDeleteSelectionBatch =
            selected.count > 1 &&
            selectedCardIDs.contains(card.id)

        if shouldDeleteSelectionBatch {
            var idsToRemove: Set<UUID> = []
            for selectedCard in selected {
                idsToRemove.formUnion(subtreeIDs(of: selectedCard))
            }
            return idsToRemove
        }
        return subtreeIDs(of: card)
    }

    func applyHardDeleteMutations(_ idsToRemove: Set<UUID>) {
        scenario.cards.removeAll { idsToRemove.contains($0.id) }
        scenario.pruneLinkedCards(validCardIDs: Set(scenario.cards.map(\.id)))
        for snapshot in scenario.snapshots {
            snapshot.cardSnapshots.removeAll { snap in
                idsToRemove.contains(snap.cardID) || (snap.parentID.map { idsToRemove.contains($0) } ?? false)
            }
            snapshot.deletedCardIDs.removeAll { idsToRemove.contains($0) }
            if let noteID = snapshot.noteCardID, idsToRemove.contains(noteID) {
                snapshot.noteCardID = nil
            }
        }
        scenario.invalidateSnapshotCache()
        scenario.bumpCardsVersion()
        scenario.changeCountSinceLastSnapshot = 0
    }

    func applyHardDeleteSelectionState(_ idsToRemove: Set<UUID>, nextCandidate: SceneCard?) {
        selectedCardIDs.subtract(idsToRemove)
        if let activeID = activeCardID, idsToRemove.contains(activeID) {
            if let next = nextCandidate {
                selectedCardIDs = [next.id]
                changeActiveCard(to: next, shouldFocusMain: false)
            } else {
                activeCardID = nil
                synchronizeActiveRelationState(for: nil)
            }
        }
        if selectedCardIDs.isEmpty, let activeID = activeCardID {
            selectedCardIDs = [activeID]
        }
    }

    func applyHardDeleteEditorAndHistoryState(_ idsToRemove: Set<UUID>) {
        if let editingID = editingCardID, idsToRemove.contains(editingID) {
            editingCardID = nil
            focusModeEditorCardID = nil
        }
        if let selectedHistoryNoteID = historySelectedNamedSnapshotNoteCardID,
           idsToRemove.contains(selectedHistoryNoteID) {
            historySelectedNamedSnapshotNoteCardID = nil
            isNamedSnapshotNoteEditing = false
        }
    }

    func armFocusDeleteSelectionLock(targetCardID: UUID, duration: TimeInterval = 0.60) {
        focusDeleteSelectionLockedCardID = targetCardID
        focusDeleteSelectionLockUntil = Date().addingTimeInterval(duration)
    }

    func clearFocusDeleteSelectionLock() {
        focusDeleteSelectionLockedCardID = nil
        focusDeleteSelectionLockUntil = .distantPast
    }

    // MARK: - Delete Selection & Card Tap

    func handleTimelineCardSelect(_ card: SceneCard) {
        if isIndexBoardActive {
            handleIndexBoardTimelineNavigation(card, beginEditing: false)
            return
        }
        if linkedCardsFilterEnabled {
            beginTimelineLinkedCardEditing(card)
            return
        }
        handleCardTap(card)
    }

    func handleTimelineCardDoubleClick(_ card: SceneCard) {
        if isIndexBoardActive {
            handleIndexBoardTimelineNavigation(card, beginEditing: true)
            return
        }
        if linkedCardsFilterEnabled {
            beginTimelineLinkedCardEditing(card)
            return
        }
        beginCardEditing(card)
    }

    func beginTimelineLinkedCardEditing(_ card: SceneCard) {
        let anchorCard = resolvedLinkedCardsAnchorID().flatMap { findCard(by: $0) }
        finishEditing(reason: .transition)
        keyboardRangeSelectionAnchorCardID = nil

        if let anchorCard, activeCardID != anchorCard.id {
            changeActiveCard(to: anchorCard, shouldFocusMain: false, deferToMainAsync: false, force: true)
        }

        selectedCardIDs = [card.id]
        editingCardID = card.id
        editingStartContent = card.content
        editingStartState = captureScenarioState()
        editingIsNewCard = false
        isMainViewFocused = true
    }

    func deleteSelectedCard() {
        let anySelection = !selectedCardIDs.isEmpty || activeCardID != nil
        guard anySelection else { return }
        showDeleteAlert = true
    }

    func handleCardTap(_ card: SceneCard) {
        let isCommandPressed = NSEvent.modifierFlags.contains(.command)
        finishEditing(reason: .transition)
        keyboardRangeSelectionAnchorCardID = nil
        if isCommandPressed {
            if selectedCardIDs.contains(card.id) {
                selectedCardIDs.remove(card.id)
            } else {
                selectedCardIDs.insert(card.id)
            }
            changeActiveCard(to: card)
        } else {
            selectedCardIDs = [card.id]
            changeActiveCard(to: card)
        }
        isMainViewFocused = true
    }

    private func mainWorkspaceClickModifiers() -> (command: Bool, shift: Bool) {
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return (
            command: flags.contains(.command),
            shift: flags.contains(.shift)
        )
    }

    private func resolvedMainWorkspaceLevel(containing cardID: UUID) -> [SceneCard]? {
        resolvedAllLevels().first { level in
            level.contains(where: { $0.id == cardID })
        }
    }

    private func resolvedMainWorkspaceRangeAnchorID(in level: [SceneCard]) -> UUID? {
        if let anchorID = keyboardRangeSelectionAnchorCardID,
           selectedCardIDs.contains(anchorID),
           level.contains(where: { $0.id == anchorID }) {
            return anchorID
        }

        if selectedCardIDs.count == 1,
           let selectedID = selectedCardIDs.first,
           level.contains(where: { $0.id == selectedID }) {
            return selectedID
        }

        if let activeID = activeCardID,
           selectedCardIDs.contains(activeID),
           level.contains(where: { $0.id == activeID }) {
            return activeID
        }

        return level.first(where: { selectedCardIDs.contains($0.id) })?.id
    }

    private func mainWorkspaceRangeSelectionIDs(
        in level: [SceneCard],
        anchorID: UUID,
        targetID: UUID
    ) -> Set<UUID> {
        guard let anchorIndex = level.firstIndex(where: { $0.id == anchorID }),
              let targetIndex = level.firstIndex(where: { $0.id == targetID }) else {
            return Set([targetID])
        }
        let lower = min(anchorIndex, targetIndex)
        let upper = max(anchorIndex, targetIndex)
        return Set(level[lower ... upper].map { $0.id })
    }

    private func prepareMainWorkspaceClickTarget(_ card: SceneCard) {
        let isNewActiveTarget = activeCardID != card.id
        pendingMainClickFocusTargetID = isNewActiveTarget ? card.id : nil
        pendingMainClickHorizontalFocusTargetID = isNewActiveTarget ? card.id : nil
        finishEditing(reason: .transition)
    }

    private func finalizeMainWorkspaceClickTarget(_ card: SceneCard) {
        changeActiveCard(to: card, deferToMainAsync: false)
        isMainViewFocused = true
    }

    private func handleMainWorkspacePlainClick(_ card: SceneCard) {
        prepareMainWorkspaceClickTarget(card)
        selectedCardIDs = [card.id]
        keyboardRangeSelectionAnchorCardID = card.id
        finalizeMainWorkspaceClickTarget(card)
    }

    private func handleMainWorkspaceCommandClick(_ card: SceneCard) {
        prepareMainWorkspaceClickTarget(card)
        let wasSelected = selectedCardIDs.contains(card.id)
        if wasSelected {
            selectedCardIDs.remove(card.id)
            if selectedCardIDs.isEmpty {
                keyboardRangeSelectionAnchorCardID = nil
            } else if keyboardRangeSelectionAnchorCardID == card.id {
                keyboardRangeSelectionAnchorCardID = selectedCardIDs.first
            }
        } else {
            selectedCardIDs.insert(card.id)
            if keyboardRangeSelectionAnchorCardID == nil {
                keyboardRangeSelectionAnchorCardID = card.id
            }
        }
        finalizeMainWorkspaceClickTarget(card)
    }

    private func handleMainWorkspaceRangeClick(_ card: SceneCard, additive: Bool) {
        prepareMainWorkspaceClickTarget(card)
        guard let level = resolvedMainWorkspaceLevel(containing: card.id),
              let anchorID = resolvedMainWorkspaceRangeAnchorID(in: level) else {
            handleMainWorkspacePlainClick(card)
            return
        }

        keyboardRangeSelectionAnchorCardID = anchorID
        let rangeIDs = mainWorkspaceRangeSelectionIDs(
            in: level,
            anchorID: anchorID,
            targetID: card.id
        )
        if additive {
            selectedCardIDs.formUnion(rangeIDs)
        } else {
            selectedCardIDs = rangeIDs
        }
        finalizeMainWorkspaceClickTarget(card)
    }

    private func resolveMainWorkspaceClickCaretLocation(for card: SceneCard, clickLocation: CGPoint?) -> Int? {
        guard let clickLocation else { return nil }
        return sharedResolvedClickCaretLocation(
            text: card.content,
            localPoint: clickLocation,
            textWidth: MainCanvasLayoutMetrics.textWidth,
            fontSize: CGFloat(fontSize),
            lineSpacing: CGFloat(mainCardLineSpacingValue),
            horizontalInset: MainEditorLayoutMetrics.mainEditorHorizontalPadding,
            verticalInset: 24,
            lineFragmentPadding: MainEditorLayoutMetrics.mainEditorLineFragmentPadding
        )
    }

    func handleMainWorkspaceCardClick(_ card: SceneCard, clickLocation: CGPoint? = nil) {
        let modifiers = mainWorkspaceClickModifiers()
        let isPrimarySelection =
            selectedCardIDs.isEmpty ||
            (selectedCardIDs.count == 1 && selectedCardIDs.contains(card.id))
        let shouldBeginEditing =
            acceptsKeyboardInput &&
            !showFocusMode &&
            !modifiers.command &&
            !modifiers.shift &&
            activeCardID == card.id &&
            editingCardID != card.id &&
            isPrimarySelection

        if shouldBeginEditing {
            beginCardEditing(
                card,
                explicitCaretLocation: resolveMainWorkspaceClickCaretLocation(for: card, clickLocation: clickLocation)
            )
            return
        }

        if modifiers.command && modifiers.shift {
            handleMainWorkspaceRangeClick(card, additive: true)
            return
        }
        if modifiers.shift {
            handleMainWorkspaceRangeClick(card, additive: false)
            return
        }
        if modifiers.command {
            handleMainWorkspaceCommandClick(card)
            return
        }
        handleMainWorkspacePlainClick(card)
    }

    func selectedCardsForDeletion() -> [SceneCard] {
        if !selectedCardIDs.isEmpty {
            return selectedCardIDs.compactMap { findCard(by: $0) }
        }
        if let id = activeCardID, let card = findCard(by: id) { return [card] }
        return []
    }

    // MARK: - Perform Delete Selection (Full)

    func performDeleteSelection() {
        let selected = selectedCardsForDeletion()
        guard !selected.isEmpty else { return }
        let focusColumnCardsBeforeDelete = showFocusMode ? focusedColumnCards() : []

        prepareFocusModeForDeleteSelectionIfNeeded()
        let prevState = captureScenarioState()
        let levelsBefore = resolvedAllLevels()
        let levelMap = buildLevelMap(from: levelsBefore)
        let deleteOutcome = resolveDeleteSelectionOutcome(from: selected)
        let idsToRemove = deleteOutcome.idsToRemove
        let didChangeContent = deleteOutcome.didChangeContent

        let activeWasRemoved = activeCardID.map { idsToRemove.contains($0) } ?? false
        let editingWasRemoved = editingCardID.map { idsToRemove.contains($0) } ?? false
        let removalAnchorID = resolveRemovalAnchorID(selected: selected, idsToRemove: idsToRemove)
        let nextCandidate = resolveNextCandidateAfterDelete(
            activeWasRemoved: activeWasRemoved,
            editingWasRemoved: editingWasRemoved,
            removedIDs: idsToRemove,
            removalAnchorID: removalAnchorID,
            focusColumnCardsBeforeDelete: focusColumnCardsBeforeDelete,
            levelsBefore: levelsBefore,
            levelMap: levelMap
        )

        applyPreMutationFocusTransitionForDelete(
            nextCandidate: nextCandidate,
            activeWasRemoved: activeWasRemoved,
            editingWasRemoved: editingWasRemoved
        )

        archiveRemovedCards(idsToRemove)
        persistDeleteSelectionChangesIfNeeded(didChangeContent: didChangeContent, idsToRemove: idsToRemove)
        updateSelectionAfterDelete(
            removedIDs: idsToRemove,
            activeWasRemoved: activeWasRemoved,
            nextCandidate: nextCandidate
        )
        scheduleFocusModeCaretAfterDelete(nextCandidate: nextCandidate)

        isMainViewFocused = true
        if showFocusMode {
            pushFocusUndoState(prevState, actionName: "카드 삭제")
        } else {
            pushUndoState(prevState, actionName: "카드 삭제")
        }
    }

    func prepareFocusModeForDeleteSelectionIfNeeded() {
        guard showFocusMode else { return }
        finalizeFocusTypingCoalescing(reason: "focus-delete-selection")
        focusCaretEnsureWorkItem?.cancel()
        focusCaretEnsureWorkItem = nil
        focusCaretPendingTypewriter = false
        focusTypewriterDeferredUntilCompositionEnd = false
        clearFocusDeleteSelectionLock()
    }

    func buildLevelMap(from levels: [[SceneCard]]) -> [UUID: Int] {
        var levelMap: [UUID: Int] = [:]
        for (levelIndex, cards) in levels.enumerated() {
            for card in cards {
                levelMap[card.id] = levelIndex
            }
        }
        return levelMap
    }

    func resolveDeleteSelectionOutcome(from selected: [SceneCard]) -> (idsToRemove: Set<UUID>, didChangeContent: Bool) {
        var idsToRemove: Set<UUID> = []
        var didChangeContent = false
        let isMultiSelection = selected.count > 1

        if !isMultiSelection, let card = selected.first {
            if card.children.isEmpty {
                idsToRemove.insert(card.id)
            } else {
                idsToRemove.formUnion(subtreeIDs(of: card))
            }
            return (idsToRemove, didChangeContent)
        }

        for card in selected {
            if card.children.isEmpty {
                idsToRemove.insert(card.id)
            } else {
                if !card.content.isEmpty {
                    createArchivedCopy(from: card)
                }
                card.content = ""
                didChangeContent = true
            }
        }
        return (idsToRemove, didChangeContent)
    }

    func resolveRemovalAnchorID(selected: [SceneCard], idsToRemove: Set<UUID>) -> UUID? {
        if let active = activeCardID, idsToRemove.contains(active) {
            return active
        }
        if let editing = editingCardID, idsToRemove.contains(editing) {
            return editing
        }
        return selected.first?.id
    }

    func resolveNextCandidateAfterDelete(
        activeWasRemoved: Bool,
        editingWasRemoved: Bool,
        removedIDs: Set<UUID>,
        removalAnchorID: UUID?,
        focusColumnCardsBeforeDelete: [SceneCard],
        levelsBefore: [[SceneCard]],
        levelMap: [UUID: Int]
    ) -> SceneCard? {
        guard activeWasRemoved || editingWasRemoved else { return nil }
        if showFocusMode,
           let removalAnchorID,
           let fromSiblingGroup = nextFocusFromSiblingGroupAfterRemoval(
            removedIDs: removedIDs,
            anchorID: removalAnchorID
           ) {
            return fromSiblingGroup
        }
        if showFocusMode,
           let fromColumn = nextFocusFromColumnAfterRemoval(
            removedIDs: removedIDs,
            columnCards: focusColumnCardsBeforeDelete,
            preferredAnchorID: removalAnchorID
           ) {
            return fromColumn
        }
        return nextFocusAfterRemoval(
            removedIDs: removedIDs,
            levelMap: levelMap,
            levels: levelsBefore,
            preferredAnchorID: removalAnchorID
        )
    }

    func applyPreMutationFocusTransitionForDelete(
        nextCandidate: SceneCard?,
        activeWasRemoved: Bool,
        editingWasRemoved: Bool
    ) {
        guard showFocusMode && (activeWasRemoved || editingWasRemoved) else { return }
        if let next = nextCandidate {
            // Pre-switch in the same column before model mutation to avoid transient empty/black frame.
            armFocusDeleteSelectionLock(targetCardID: next.id)
            suppressFocusModeScrollOnce = true
            selectedCardIDs = [next.id]
            changeActiveCard(to: next, shouldFocusMain: false, deferToMainAsync: false, force: true)
            editingCardID = next.id
            editingStartContent = next.content
            editingStartState = captureScenarioState()
            editingIsNewCard = false
            focusModeEditorCardID = next.id
            focusLastCommittedContentByCard[next.id] = next.content
        } else {
            editingCardID = nil
            focusModeEditorCardID = nil
            clearFocusDeleteSelectionLock()
        }
    }

    func archiveRemovedCards(_ idsToRemove: Set<UUID>) {
        guard !idsToRemove.isEmpty else { return }
        for card in scenario.cards where idsToRemove.contains(card.id) {
            card.isArchived = true
        }
        scenario.bumpCardsVersion()
    }

    func persistDeleteSelectionChangesIfNeeded(didChangeContent: Bool, idsToRemove: Set<UUID>) {
        guard didChangeContent || !idsToRemove.isEmpty else { return }
        persistCardMutation(forceSnapshot: true)
    }

    func updateSelectionAfterDelete(
        removedIDs: Set<UUID>,
        activeWasRemoved: Bool,
        nextCandidate: SceneCard?
    ) {
        selectedCardIDs.subtract(removedIDs)
        if activeWasRemoved {
            if let next = nextCandidate {
                if !showFocusMode {
                    selectedCardIDs = [next.id]
                    changeActiveCard(to: next)
                } else if selectedCardIDs.isEmpty {
                    selectedCardIDs = [next.id]
                }
            } else {
                selectedCardIDs = []
                activeCardID = nil
                resetActiveRelationStateCache()
                if showFocusMode {
                    editingCardID = nil
                    focusModeEditorCardID = nil
                }
            }
        } else if selectedCardIDs.isEmpty, let activeID = activeCardID, !removedIDs.contains(activeID) {
            selectedCardIDs = [activeID]
        }
    }

    func scheduleFocusModeCaretAfterDelete(nextCandidate: SceneCard?) {
        guard showFocusMode, let next = nextCandidate else { return }
        focusModeCaretRequestID += 1
        let requestID = focusModeCaretRequestID
        applyFocusModeCaretWithRetry(expectedCardID: next.id, location: 0, retries: 10, requestID: requestID)
        DispatchQueue.main.async {
            requestFocusModeCaretEnsure(typewriter: false, delay: 0.0, force: true)
        }
    }

    // MARK: - Focus Navigation After Removal

    func nextFocusFromSiblingGroupAfterRemoval(
        removedIDs: Set<UUID>,
        anchorID: UUID
    ) -> SceneCard? {
        guard let anchor = findCard(by: anchorID) else { return nil }
        let siblings = anchor.parent?.sortedChildren ?? scenario.rootCards
        guard let index = siblings.firstIndex(where: { $0.id == anchorID }) else { return nil }
        if index + 1 < siblings.count {
            for i in (index + 1)..<siblings.count {
                let candidate = siblings[i]
                if !removedIDs.contains(candidate.id) { return candidate }
            }
        }
        if index > 0 {
            for i in stride(from: index - 1, through: 0, by: -1) {
                let candidate = siblings[i]
                if !removedIDs.contains(candidate.id) { return candidate }
            }
        }
        if let parent = anchor.parent, !removedIDs.contains(parent.id) {
            return parent
        }
        return nil
    }

    func nextFocusFromColumnAfterRemoval(
        removedIDs: Set<UUID>,
        columnCards: [SceneCard],
        preferredAnchorID: UUID?
    ) -> SceneCard? {
        guard !columnCards.isEmpty else { return nil }
        let anchorIndex: Int? = {
            if let preferredAnchorID,
               let index = columnCards.firstIndex(where: { $0.id == preferredAnchorID }) {
                return index
            }
            return columnCards.firstIndex(where: { removedIDs.contains($0.id) })
        }()

        if let index = anchorIndex {
            if index + 1 < columnCards.count {
                for i in (index + 1)..<columnCards.count {
                    let candidate = columnCards[i]
                    if !removedIDs.contains(candidate.id) { return candidate }
                }
            }
            if index > 0 {
                for i in stride(from: index - 1, through: 0, by: -1) {
                    let candidate = columnCards[i]
                    if !removedIDs.contains(candidate.id) { return candidate }
                }
            }
        }

        return columnCards.first(where: { !removedIDs.contains($0.id) })
    }

    func subtreeIDs(of card: SceneCard) -> Set<UUID> {
        var result: Set<UUID> = [card.id]
        for child in card.children {
            result.formUnion(subtreeIDs(of: child))
        }
        return result
    }

    func nextFocusAfterRemoval(
        removedIDs: Set<UUID>,
        levelMap: [UUID: Int],
        levels: [[SceneCard]],
        preferredAnchorID: UUID? = nil
    ) -> SceneCard? {
        func candidateFromSiblings(anchorID: UUID) -> SceneCard? {
            guard let anchor = findCard(by: anchorID) else {
                return nil
            }
            let siblings = anchor.parent?.sortedChildren ?? scenario.rootCards
            guard let index = siblings.firstIndex(where: { $0.id == anchorID }) else {
                return nil
            }

            // Prefer immediate flow in the same sibling group: below first, then above.
            if index + 1 < siblings.count {
                for i in (index + 1)..<siblings.count {
                    let candidate = siblings[i]
                    if !removedIDs.contains(candidate.id) { return candidate }
                }
            }
            if index > 0 {
                for i in stride(from: index - 1, through: 0, by: -1) {
                    let candidate = siblings[i]
                    if !removedIDs.contains(candidate.id) { return candidate }
                }
            }

            if let parent = anchor.parent, !removedIDs.contains(parent.id) {
                return parent
            }
            return nil
        }

        var anchors: [UUID] = []
        if let preferredAnchorID { anchors.append(preferredAnchorID) }
        if let active = activeCardID, !anchors.contains(active) { anchors.append(active) }
        for id in removedIDs where !anchors.contains(id) { anchors.append(id) }

        for anchor in anchors {
            if let candidate = candidateFromSiblings(anchorID: anchor) {
                return candidate
            }
        }

        // Fallback: stay in the same depth if possible, but avoid jumping to descendant columns.
        let removedLevels = levelMap
            .filter { removedIDs.contains($0.key) }
            .map { $0.value }
            .sorted()
        for level in removedLevels {
            guard let levelCards = levels[safe: level] else { continue }
            if let candidate = levelCards.first(where: { !removedIDs.contains($0.id) }) {
                return candidate
            }
        }

        return scenario.rootCards.first { !removedIDs.contains($0.id) }
    }

    func createArchivedCopy(from card: SceneCard) {
        let copy = SceneCard(content: card.content, orderIndex: 0, createdAt: Date(), parent: nil, scenario: scenario, category: card.category, isFloating: false, isArchived: true)
        scenario.cards.append(copy)
        scenario.bumpCardsVersion()
    }
}
