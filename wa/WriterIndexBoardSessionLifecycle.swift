import SwiftUI
import AppKit

extension ScenarioWriterView {
    func indexBoardSourceTitle(for parentID: UUID?) -> String {
        guard let parentID else { return "(루트)" }
        guard let parent = findCard(by: parentID) else { return "(없는 부모 카드)" }
        return firstMeaningfulLine(from: parent.content) ?? "(내용 없는 부모 카드)"
    }

    func canOpenIndexBoard(sourceParentID: UUID?, sourceDepth: Int) -> Bool {
        guard !showFocusMode else { return false }
        guard !isPreviewingHistory else { return false }
        guard sourceDepth >= 0 else { return false }
        return true
    }

    func handleOpenIndexBoardRequestNotification() {
        if isIndexBoardActive {
            indexBoardRestoreTrace("board_toggle_request", "action=close activeSession=true")
            closeIndexBoard()
            return
        }

        let entrySnapshot = captureIndexBoardEntrySnapshot()
        indexBoardRestoreTrace(
            "board_toggle_request",
            "action=open activeSession=false entryActive=\(debugRestoreUUID(entrySnapshot.activeCardID)) " +
            "entryEditing=\(debugRestoreUUID(entrySnapshot.editingCardID)) entryOffset=\(debugRestoreCGFloat(entrySnapshot.mainCanvasHorizontalOffset)) " +
            "entryViewportCount=\(entrySnapshot.mainColumnViewportOffsets.count)"
        )
        if let persistedSession = indexBoardRuntime.persistedSession(for: scenario.id, entrySnapshot: entrySnapshot) {
            let liveCards = resolvedLiveIndexBoardSourceCards(for: persistedSession.source)
            indexBoardRestoreTrace(
                "board_toggle_request",
                "usingPersistedSession sourceParent=\(debugRestoreUUID(persistedSession.sourceParentID)) " +
                "sourceDepth=\(persistedSession.sourceDepth) liveCardCount=\(liveCards.count)"
            )
            openIndexBoard(
                sourceParentID: persistedSession.sourceParentID,
                sourceDepth: persistedSession.sourceDepth,
                sourceCardIDs: liveCards.map(\.id)
            )
            return
        }

        guard let fallbackColumn = resolvedFallbackIndexBoardColumnContext() else { return }
        openIndexBoardForColumn(
            level: fallbackColumn.level,
            parent: fallbackColumn.parent,
            cards: fallbackColumn.cards
        )
    }

    func mergedIndexBoardSourceCardIDs(_ liveIDs: [UUID], persistedIDs: [UUID]) -> [UUID] {
        var ordered: [UUID] = []
        var seen: Set<UUID> = []
        for cardID in liveIDs + persistedIDs {
            if seen.insert(cardID).inserted {
                ordered.append(cardID)
            }
        }
        return ordered
    }

    private func resolvedFallbackIndexBoardColumnContext() -> (level: Int, parent: SceneCard?, cards: [SceneCard])? {
        let levels = resolvedDisplayedMainLevelsWithParents()
        guard !levels.isEmpty else { return nil }

        if let activeID = activeCardID,
           let location = displayedMainCardLocationByID(activeID),
           levels.indices.contains(location.level) {
            let data = levels[location.level]
            return (level: location.level, parent: data.parent, cards: data.cards)
        }

        if let visibleLevel = resolvedVisibleMainCanvasLevelFromCurrentScrollPosition() ?? (lastScrolledLevel >= 0 ? lastScrolledLevel : nil),
           levels.indices.contains(visibleLevel) {
            let data = levels[visibleLevel]
            return (level: visibleLevel, parent: data.parent, cards: data.cards)
        }

        if let firstNonEmpty = levels.enumerated().first(where: { !$0.element.cards.isEmpty }) {
            return (level: firstNonEmpty.offset, parent: firstNonEmpty.element.parent, cards: firstNonEmpty.element.cards)
        }

        guard let first = levels.first else { return nil }
        return (level: 0, parent: first.parent, cards: first.cards)
    }

    private func resolvedLiveIndexBoardSourceCards(for source: IndexBoardColumnSource) -> [SceneCard] {
        if let parentID = source.parentID, let parentCard = findCard(by: parentID) {
            return parentCard.sortedChildren
        }
        return scenario.rootCards
    }

    private func confirmIndexBoardSourceReplacement(
        currentSourceParentID: UUID?,
        incomingSourceParentID: UUID?
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "보드 컬럼을 바꿀까요?"
        let currentTitle = indexBoardSourceTitle(for: currentSourceParentID)
        let incomingTitle = indexBoardSourceTitle(for: incomingSourceParentID)
        alert.informativeText = "\"\(currentTitle)\" 보드 배치를 버리고 \"\(incomingTitle)\" 컬럼을 새 보드로 엽니다."
        alert.addButton(withTitle: "바꾸기")
        alert.addButton(withTitle: "취소")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func openIndexBoard(sourceParentID: UUID?, sourceDepth: Int, sourceCardIDs: [UUID]) {
        guard canOpenIndexBoard(sourceParentID: sourceParentID, sourceDepth: sourceDepth) else { return }

        let source = IndexBoardColumnSource(parentID: sourceParentID, depth: sourceDepth)
        let entrySnapshot = captureIndexBoardEntrySnapshot()
        indexBoardRestoreTraceMark("board-open")
        indexBoardRestoreTrace(
            "board_open",
            "sourceParent=\(debugRestoreUUID(sourceParentID)) sourceDepth=\(sourceDepth) cardCount=\(sourceCardIDs.count) " +
            "entryActive=\(debugRestoreUUID(entrySnapshot.activeCardID)) entryEditing=\(debugRestoreUUID(entrySnapshot.editingCardID)) " +
            "entryOffset=\(debugRestoreCGFloat(entrySnapshot.mainCanvasHorizontalOffset)) " +
            "entryViewportCount=\(entrySnapshot.mainColumnViewportOffsets.count) " +
            "entryVisibleLevel=\(entrySnapshot.visibleMainCanvasLevel.map(String.init) ?? "nil")"
        )
        let persistedSession = indexBoardRuntime.persistedSession(for: scenario.id, entrySnapshot: entrySnapshot)
        let existingSession = activeIndexBoardSession ?? persistedSession

        if let existingSession,
           existingSession.source != source,
           !confirmIndexBoardSourceReplacement(
            currentSourceParentID: existingSession.sourceParentID,
            incomingSourceParentID: sourceParentID
           ) {
            return
        }

        let session: IndexBoardSessionState
        if let persistedSession,
           persistedSession.source == source {
            session = IndexBoardSessionState(
                source: source,
                sourceCardIDs: mergedIndexBoardSourceCardIDs(sourceCardIDs, persistedIDs: persistedSession.sourceCardIDs),
                entrySnapshot: entrySnapshot,
                viewport: persistedSession.viewport,
                logical: persistedSession.logical,
                presentation: persistedSession.presentation,
                navigation: IndexBoardNavigationState()
            )
        } else {
            session = IndexBoardSessionState(
                source: source,
                sourceCardIDs: sourceCardIDs,
                entrySnapshot: entrySnapshot
            )
        }

        finishEditing(reason: .transition)
        indexBoardRuntime.activate(session, scenarioID: scenario.id, paneID: paneContextID)
        indexBoardRestoreTrace(
            "board_open_activated",
            "sessionSourceParent=\(debugRestoreUUID(session.sourceParentID)) sessionZoom=\(String(format: "%.2f", session.zoomScale)) " +
            "sessionScroll=(\(String(format: "%.2f", session.viewport.scrollOffset.x)),\(String(format: "%.2f", session.viewport.scrollOffset.y)))"
        )
        let summaryTargetIDs = session.sourceCardIDs + liveIndexBoardTempChildCards().map(\.id)
        reconcileIndexBoardSummaries(for: Array(Set(summaryTargetIDs)))
        isMainViewFocused = true
    }

    @discardableResult
    func deactivateIndexBoardSessionIfNeeded() -> IndexBoardSessionState? {
        guard let session = activeIndexBoardSession else { return nil }
        persistIndexBoardViewport(
            zoomScale: session.zoomScale,
            scrollOffset: session.scrollOffset
        )
        let liveOffset = resolvedMainCanvasHorizontalViewportSnapshotOffset()
        indexBoardRestoreTrace(
            "board_deactivate",
            "sessionSourceParent=\(debugRestoreUUID(session.sourceParentID)) liveActive=\(debugRestoreUUID(activeCardID)) " +
            "liveEditing=\(debugRestoreUUID(editingCardID)) liveOffset=\(debugRestoreCGFloat(liveOffset)) " +
            "entryOffset=\(debugRestoreCGFloat(session.entrySnapshot.mainCanvasHorizontalOffset)) " +
            "entryViewportCount=\(session.entrySnapshot.mainColumnViewportOffsets.count)"
        )
        indexBoardEditorDraft = nil
        indexBoardRuntime.deactivate(scenarioID: scenario.id, paneID: paneContextID)
        return session
    }

    func closeIndexBoard() {
        guard let session = deactivateIndexBoardSessionIfNeeded() else { return }
        indexBoardRestoreTraceMark("board-close")
        indexBoardRestoreTrace(
            "board_close",
            "restoreEntryActive=\(debugRestoreUUID(session.entrySnapshot.activeCardID)) " +
            "restoreEntryEditing=\(debugRestoreUUID(session.entrySnapshot.editingCardID)) " +
            "restoreEntryOffset=\(debugRestoreCGFloat(session.entrySnapshot.mainCanvasHorizontalOffset)) " +
            "restoreEntryViewportCount=\(session.entrySnapshot.mainColumnViewportOffsets.count)"
        )
        restoreIndexBoardEntrySnapshot(session.entrySnapshot)
    }

    func teardownIndexBoardIfNeeded(restoreEntryState: Bool) {
        guard let session = deactivateIndexBoardSessionIfNeeded() else { return }
        if restoreEntryState {
            restoreIndexBoardEntrySnapshot(session.entrySnapshot)
        }
    }

    func captureIndexBoardEntrySnapshot() -> IndexBoardEntrySnapshot {
        let visibleLevel: Int?
        if let resolvedLevel = resolvedVisibleMainCanvasLevelFromCurrentScrollPosition() {
            lastScrolledLevel = resolvedLevel
            visibleLevel = resolvedLevel
        } else if let activeID = activeCardID, let activeLevel = displayedMainCardLocationByID(activeID)?.level {
            switch mainCanvasHorizontalScrollMode {
            case .oneStep:
                visibleLevel = activeLevel
            case .twoStep:
                visibleLevel = max(0, activeLevel - 1)
            }
        } else if lastScrolledLevel >= 0 {
            visibleLevel = lastScrolledLevel
        } else {
            visibleLevel = nil
        }

        let editingCaretLocation = editingCardID
            .flatMap { findCard(by: $0) }
            .flatMap { resolvedMainCaretLocation(for: $0) }

        let resolvedHorizontalOffset = resolvedMainCanvasHorizontalViewportSnapshotOffset()
        let snapshot = IndexBoardEntrySnapshot(
            activeCardID: activeCardID,
            editingCardID: editingCardID,
            selectedCardIDs: selectedCardIDs,
            editingCaretLocation: editingCaretLocation,
            visibleMainCanvasLevel: visibleLevel,
            mainCanvasHorizontalOffset: resolvedHorizontalOffset,
            mainColumnViewportOffsets: mainColumnViewportOffsetByKey
        )
        indexBoardRestoreTrace(
            "board_capture_entry_snapshot",
            "active=\(debugRestoreUUID(snapshot.activeCardID)) editing=\(debugRestoreUUID(snapshot.editingCardID)) " +
            "selectionCount=\(snapshot.selectedCardIDs.count) visibleLevel=\(snapshot.visibleMainCanvasLevel.map(String.init) ?? "nil") " +
            "offset=\(debugRestoreCGFloat(snapshot.mainCanvasHorizontalOffset)) viewportCount=\(snapshot.mainColumnViewportOffsets.count) " +
            "viewportOffsets=\(debugRestoreViewportOffsets(snapshot.mainColumnViewportOffsets))"
        )
        return snapshot
    }

    func restoreIndexBoardEntrySnapshot(_ snapshot: IndexBoardEntrySnapshot) {
        let validSelection = Set(snapshot.selectedCardIDs.filter { findCard(by: $0) != nil })
        selectedCardIDs = validSelection
        let hasStoredHorizontalViewport = snapshot.mainCanvasHorizontalOffset != nil
        let hasStoredVerticalViewport = !snapshot.mainColumnViewportOffsets.isEmpty
        let hasStoredViewport = hasStoredHorizontalViewport || hasStoredVerticalViewport
        indexBoardRestoreTrace(
            "board_restore_entry_snapshot_begin",
            "active=\(debugRestoreUUID(snapshot.activeCardID)) editing=\(debugRestoreUUID(snapshot.editingCardID)) " +
            "selectionCount=\(validSelection.count) hasStoredViewport=\(hasStoredViewport) " +
            "offset=\(debugRestoreCGFloat(snapshot.mainCanvasHorizontalOffset)) " +
            "viewportCount=\(snapshot.mainColumnViewportOffsets.count) " +
            "currentLiveOffset=\(debugRestoreCGFloat(resolvedMainCanvasHorizontalViewportSnapshotOffset()))"
        )
        if let visibleLevel = snapshot.visibleMainCanvasLevel {
            lastScrolledLevel = max(0, visibleLevel)
        }
        if hasStoredViewport {
            suppressAutoScrollOnce = true
            suppressHorizontalAutoScroll = true
            let restoreGraceDuration: TimeInterval = hasStoredHorizontalViewport ? 0.35 : 1.4
            mainColumnViewportRestoreUntil = Date().addingTimeInterval(restoreGraceDuration)
            indexBoardRestoreTrace(
                "board_restore_entry_snapshot_flags",
                "suppressAutoScrollOnce=\(suppressAutoScrollOnce) suppressHorizontalAutoScroll=\(suppressHorizontalAutoScroll) " +
                "restoreUntil=\(String(format: "%.3f", mainColumnViewportRestoreUntil.timeIntervalSince1970))"
            )
            if !hasStoredHorizontalViewport {
                DispatchQueue.main.asyncAfter(deadline: .now() + restoreGraceDuration) {
                    suppressHorizontalAutoScroll = false
                    indexBoardRestoreTrace(
                        "board_restore_entry_snapshot_flags_release",
                        "reason=noStoredHorizontalOffset suppressHorizontalAutoScroll=\(suppressHorizontalAutoScroll)"
                    )
                }
            }
        }

        let fallbackCard = scenario.rootCards.first
        let restoredActiveCard = snapshot.activeCardID
            .flatMap { findCard(by: $0) }
            ?? snapshot.editingCardID.flatMap { findCard(by: $0) }
            ?? fallbackCard

        if let restoredActiveCard {
            indexBoardRestoreTrace(
                "board_restore_entry_snapshot_active",
                "restoredActive=\(debugRestoreUUID(restoredActiveCard.id))"
            )
            changeActiveCard(
                to: restoredActiveCard,
                shouldFocusMain: false,
                deferToMainAsync: false,
                force: true
            )
        } else {
            activeCardID = nil
        }

        if let editingID = snapshot.editingCardID, let editingCard = findCard(by: editingID) {
            indexBoardRestoreTrace(
                "board_restore_entry_snapshot_editing",
                "restoredEditing=\(debugRestoreUUID(editingCard.id)) caret=\(snapshot.editingCaretLocation.map(String.init) ?? "nil")"
            )
            changeActiveCard(
                to: editingCard,
                shouldFocusMain: false,
                deferToMainAsync: false,
                force: true
            )
            editingCardID = editingCard.id
            if let caretLocation = snapshot.editingCaretLocation {
                restoreMainEditingCaret(
                    for: editingCard.id,
                    location: caretLocation,
                    suppressInitialEnsure: true
                )
            }
        } else {
            editingCardID = nil
        }

        if let targetOffsetX = snapshot.mainCanvasHorizontalOffset {
            indexBoardRestoreTrace(
                "board_restore_entry_snapshot_horizontal_restore",
                "targetOffset=\(debugRestoreCGFloat(targetOffsetX))"
            )
            restoreMainCanvasHorizontalViewport(to: targetOffsetX)
        }

        if !snapshot.mainColumnViewportOffsets.isEmpty {
            indexBoardRestoreTrace(
                "board_restore_entry_snapshot_column_restore",
                "viewportCount=\(snapshot.mainColumnViewportOffsets.count) " +
                "viewportOffsets=\(debugRestoreViewportOffsets(snapshot.mainColumnViewportOffsets))"
            )
            scheduleMainCanvasRestoreRetries {
                applyStoredMainColumnViewportOffsets(snapshot.mainColumnViewportOffsets)
            }
        }

        if !hasStoredHorizontalViewport, let targetCardID = restoredActiveCard?.id {
            DispatchQueue.main.async {
                indexBoardRestoreTrace(
                    "board_restore_entry_snapshot_semantic_restore",
                    "targetCard=\(debugRestoreUUID(targetCardID)) visibleLevel=\(snapshot.visibleMainCanvasLevel.map(String.init) ?? "nil")"
                )
                scheduleMainCanvasRestoreRequest(
                    targetCardID: targetCardID,
                    visibleLevel: snapshot.visibleMainCanvasLevel,
                    forceSemantic: true
                )
            }
        }

        DispatchQueue.main.async {
            indexBoardRestoreTrace("board_restore_entry_snapshot_focus_restore")
            restoreMainKeyboardFocus()
        }
    }

    func restoreIndexBoardExitState(from entrySnapshot: IndexBoardEntrySnapshot) {
        let liveSelection = Set(selectedCardIDs.filter { findCard(by: $0) != nil })
        let liveActiveCard = activeCardID.flatMap { findCard(by: $0) }
        let liveTargetCard = liveActiveCard
            ?? liveSelection.first.flatMap { findCard(by: $0) }
            ?? entrySnapshot.activeCardID.flatMap { findCard(by: $0) }
            ?? scenario.rootCards.first

        let selectionUnchanged =
            liveSelection == entrySnapshot.selectedCardIDs &&
            liveTargetCard?.id == entrySnapshot.activeCardID

        selectedCardIDs = liveSelection.isEmpty
            ? (liveTargetCard.map { [$0.id] } ?? [])
            : liveSelection

        if let liveTargetCard {
            changeActiveCard(
                to: liveTargetCard,
                shouldFocusMain: false,
                deferToMainAsync: false,
                force: true
            )
        } else {
            activeCardID = nil
        }

        if selectionUnchanged,
           let editingID = entrySnapshot.editingCardID,
           let editingCard = findCard(by: editingID),
           liveTargetCard?.id == editingCard.id {
            editingCardID = editingCard.id
            if let caretLocation = entrySnapshot.editingCaretLocation {
                restoreMainEditingCaret(
                    for: editingCard.id,
                    location: caretLocation,
                    suppressInitialEnsure: true
                )
            }

            if let targetOffsetX = entrySnapshot.mainCanvasHorizontalOffset {
                mainCanvasScrollCoordinator.scheduleMainCanvasHorizontalRestore(offsetX: targetOffsetX)
            }

            if !entrySnapshot.mainColumnViewportOffsets.isEmpty {
                scheduleMainCanvasRestoreRetries {
                    applyStoredMainColumnViewportOffsets(entrySnapshot.mainColumnViewportOffsets)
                }
            }
        } else {
            editingCardID = nil
        }

        if let targetCardID = liveTargetCard?.id {
            DispatchQueue.main.async {
                scheduleMainCanvasRestoreRequest(
                    targetCardID: targetCardID,
                    visibleLevel: selectionUnchanged ? entrySnapshot.visibleMainCanvasLevel : nil,
                    forceSemantic: true
                )
            }
        }

        DispatchQueue.main.async {
            restoreMainKeyboardFocus()
        }
    }

    func openIndexBoardForColumn(level: Int, parent: SceneCard?, cards: [SceneCard]) {
        openIndexBoard(
            sourceParentID: parent?.id,
            sourceDepth: level,
            sourceCardIDs: cards.map(\.id)
        )
    }

    @ViewBuilder
    func indexBoardColumnContextMenu(level: Int, parent: SceneCard?, cards: [SceneCard]) -> some View {
        Button("인덱스 카드 뷰로 보기") {
            openIndexBoardForColumn(level: level, parent: parent, cards: cards)
        }
        .disabled(!canOpenIndexBoard(sourceParentID: parent?.id, sourceDepth: level))
    }
}
