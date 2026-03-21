import SwiftUI

struct IndexBoardScaffoldView: View {
    let session: IndexBoardSessionState
    let sourceTitle: String
    let activeCardCount: Int
    let onClose: () -> Void

    private var boardLabelText: String {
        if let parentID = session.sourceParentID {
            return parentID.uuidString
        }
        return "root"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.94, blue: 0.89),
                    Color(red: 0.90, green: 0.88, blue: 0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Board View")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.86))
                        Text("Phase 0 스캐폴딩")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.black.opacity(0.52))
                    }

                    Spacer(minLength: 0)

                    Button("작업창으로 돌아가기") {
                        onClose()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.black.opacity(0.78))
                }

                VStack(alignment: .leading, spacing: 10) {
                    scaffoldMetricRow(label: "소스 컬럼", value: sourceTitle)
                    scaffoldMetricRow(label: "source parent", value: boardLabelText)
                    scaffoldMetricRow(label: "source depth", value: "\(session.sourceDepth)")
                    scaffoldMetricRow(label: "카드 수", value: "\(activeCardCount)")
                    scaffoldMetricRow(label: "줌", value: String(format: "%.2f", session.zoomScale))
                }
                .padding(18)
                .background(Color.white.opacity(0.64))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text("현재 Phase에서는 pane-level mode, session state, source parent 기반 진입/복귀 상태만 연결되어 있습니다.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.68))

                Spacer(minLength: 0)
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    @ViewBuilder
    private func scaffoldMetricRow(label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.black.opacity(0.46))
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.82))
                .textSelection(.enabled)
        }
    }
}

extension ScenarioWriterView {
    var paneContextID: Int {
        splitModeEnabled ? splitPaneID : 0
    }

    var isIndexBoardActive: Bool {
        indexBoardRuntime.isActive(scenarioID: scenario.id, paneID: paneContextID)
    }

    var activeIndexBoardSession: IndexBoardSessionState? {
        indexBoardRuntime.session(for: scenario.id, paneID: paneContextID)
    }

    var activeBasePaneMode: WriterPaneMode {
        if isIndexBoardActive { return .indexBoard }
        if showFocusMode { return .focus }
        return .main
    }

    var activePaneMode: WriterPaneMode { activeBasePaneMode }

    func handleIndexBoardVisibilityChange(_ isVisible: Bool) {
        if isVisible {
            stopMainNavKeyMonitor()
            stopMainCaretMonitor()
        } else if !showFocusMode {
            startMainNavKeyMonitor()
            startMainCaretMonitor()
            restoreMainKeyboardFocus()
        }
    }

    func handleIndexBoardKeyPress(_ press: KeyPress) -> KeyPress.Result? {
        guard isIndexBoardActive else { return nil }
        if isIndexBoardEditorPresented {
            guard press.phase == .down else { return .ignored }
            let hasOnlyCommandModifier =
                press.modifiers.contains(.command) &&
                !press.modifiers.contains(.option) &&
                !press.modifiers.contains(.control) &&
                !press.modifiers.contains(.shift)
            if press.key == .escape {
                saveIndexBoardEditor()
                return .handled
            }
            if press.key == .return && hasOnlyCommandModifier {
                saveIndexBoardEditor()
                return .handled
            }
            return .ignored
        }
        if let handled = handleIndexBoardZoomShortcut(press) {
            return handled
        }
        if press.phase == .down && press.key == .escape {
            if !selectedCardIDs.isEmpty {
                clearIndexBoardSelection()
                return .handled
            }
            closeIndexBoard()
            return .handled
        }
        if press.phase == .down &&
           press.key == .return &&
           !press.modifiers.contains(.command) &&
           !press.modifiers.contains(.option) &&
           !press.modifiers.contains(.control) &&
           !press.modifiers.contains(.shift) {
            presentIndexBoardEditorForSelection()
            return .handled
        }
        if press.phase == .down &&
           !press.modifiers.contains(.command) &&
           !press.modifiers.contains(.option) &&
           !press.modifiers.contains(.control) {
            let normalized = press.characters.lowercased()
            if normalized == "n" || press.characters == "ㅜ" {
                _ = createIndexBoardTempCard()
                return .handled
            }
        }
        return .handled
    }

    func handleIndexBoardZoomShortcut(_ press: KeyPress) -> KeyPress.Result? {
        guard press.phase == .down else { return nil }
        guard press.modifiers.contains(.command) else { return nil }
        guard !press.modifiers.contains(.option),
              !press.modifiers.contains(.control),
              !press.modifiers.contains(.shift) else { return nil }

        switch press.characters {
        case "-", "_":
            stepIndexBoardZoom(by: -IndexBoardZoom.step)
            return .handled
        case "=", "+":
            stepIndexBoardZoom(by: IndexBoardZoom.step)
            return .handled
        case "0", ")":
            resetIndexBoardZoom()
            return .handled
        default:
            return nil
        }
    }

    func indexBoardSourceTitle(for parentID: UUID?) -> String {
        guard let parentID else { return "(루트)" }
        guard let parent = findCard(by: parentID) else { return "(없는 부모 카드)" }
        return firstMeaningfulLine(from: parent.content) ?? "(내용 없는 부모 카드)"
    }

    func canOpenIndexBoard(sourceParentID: UUID?, sourceDepth: Int) -> Bool {
        guard !showFocusMode else { return false }
        guard !isPreviewingHistory else { return false }
        guard sourceDepth >= 0 else { return false }
        return indexBoardRuntime.canActivate(scenarioID: scenario.id, paneID: paneContextID)
    }

    func openIndexBoard(sourceParentID: UUID?, sourceDepth: Int, sourceCardIDs: [UUID]) {
        guard canOpenIndexBoard(sourceParentID: sourceParentID, sourceDepth: sourceDepth) else { return }

        let session = IndexBoardSessionState(
            source: IndexBoardColumnSource(parentID: sourceParentID, depth: sourceDepth),
            sourceCardIDs: sourceCardIDs,
            entrySnapshot: captureIndexBoardEntrySnapshot()
        )

        finishEditing()
        indexBoardRuntime.activate(session, scenarioID: scenario.id, paneID: paneContextID)
        let summaryTargetIDs = sourceCardIDs + liveIndexBoardTempChildCards().map(\.id)
        reconcileIndexBoardSummaries(for: Array(Set(summaryTargetIDs)))
        isMainViewFocused = true
    }

    @discardableResult
    func deactivateIndexBoardSessionIfNeeded() -> IndexBoardSessionState? {
        guard let session = activeIndexBoardSession else { return nil }
        indexBoardEditorDraft = nil
        indexBoardRuntime.deactivate(scenarioID: scenario.id, paneID: paneContextID)
        return session
    }

    func closeIndexBoard() {
        guard let session = deactivateIndexBoardSessionIfNeeded() else { return }
        restoreIndexBoardExitState(from: session.entrySnapshot)
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

        return IndexBoardEntrySnapshot(
            activeCardID: activeCardID,
            editingCardID: editingCardID,
            selectedCardIDs: selectedCardIDs,
            editingCaretLocation: editingCaretLocation,
            visibleMainCanvasLevel: visibleLevel,
            mainCanvasHorizontalOffset: mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalOffset().map { max(0, $0) },
            mainColumnViewportOffsets: mainColumnViewportOffsetByKey
        )
    }

    func restoreIndexBoardEntrySnapshot(_ snapshot: IndexBoardEntrySnapshot) {
        let validSelection = Set(snapshot.selectedCardIDs.filter { findCard(by: $0) != nil })
        selectedCardIDs = validSelection

        let fallbackCard = scenario.rootCards.first
        let restoredActiveCard = snapshot.activeCardID
            .flatMap { findCard(by: $0) }
            ?? snapshot.editingCardID.flatMap { findCard(by: $0) }
            ?? fallbackCard

        if let restoredActiveCard {
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
            mainCanvasScrollCoordinator.scheduleMainCanvasHorizontalRestore(offsetX: targetOffsetX)
        }

        if !snapshot.mainColumnViewportOffsets.isEmpty {
            scheduleMainCanvasRestoreRetries {
                applyStoredMainColumnViewportOffsets(snapshot.mainColumnViewportOffsets)
            }
        }

        if let targetCardID = restoredActiveCard?.id {
            DispatchQueue.main.async {
                scheduleMainCanvasRestoreRequest(
                    targetCardID: targetCardID,
                    visibleLevel: snapshot.visibleMainCanvasLevel,
                    forceSemantic: true
                )
            }
        }

        DispatchQueue.main.async {
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

    func resolvedIndexBoardSurfaceProjection() -> BoardSurfaceProjection? {
        guard let session = activeIndexBoardSession else { return nil }
        let tempContainer = resolvedIndexBoardTempContainer()
        let liveCards = resolvedLiveIndexBoardSourceCards(for: session)
        let regularCards = liveCards.filter { card in
            guard let tempContainer else { return true }
            if card.id == tempContainer.id { return false }
            return card.parent?.id != tempContainer.id
        }
        let tempChildCards = liveIndexBoardTempChildCards()
        var orderedCardIDs: [UUID] = []
        orderedCardIDs.reserveCapacity(regularCards.count + tempChildCards.count)
        var seenCardIDs: Set<UUID> = []
        for card in regularCards + tempChildCards {
            if seenCardIDs.insert(card.id).inserted {
                orderedCardIDs.append(card.id)
            }
        }

        var cardsByLaneParentID: [UUID?: [SceneCard]] = [:]
        var laneParentOrder: [UUID?] = []

        for card in regularCards {
            let laneParentID = card.parent?.id
            if cardsByLaneParentID[laneParentID] == nil {
                laneParentOrder.append(laneParentID)
            }
            cardsByLaneParentID[laneParentID, default: []].append(card)
        }

        if let tempContainer,
           !tempChildCards.isEmpty {
            if cardsByLaneParentID[tempContainer.id] == nil {
                laneParentOrder.append(tempContainer.id)
            }
            cardsByLaneParentID[tempContainer.id, default: []].append(contentsOf: tempChildCards)
        }

        var lanes: [BoardSurfaceLane] = []
        lanes.reserveCapacity(laneParentOrder.count)

        let detachedGridPositionByCardID = activeIndexBoardSession?.detachedGridPositionByCardID ?? [:]

        var surfaceItems: [BoardSurfaceItem] = []
        surfaceItems.reserveCapacity(orderedCardIDs.count)
        var nextSlotIndex = 0

        for (laneIndex, laneParentID) in laneParentOrder.enumerated() {
            let laneCards = cardsByLaneParentID[laneParentID] ?? []
            guard !laneCards.isEmpty else { continue }
            let parentCard = laneParentID.flatMap { findCard(by: $0) }
            let isTempLane = tempContainer?.id == laneParentID
            lanes.append(
                BoardSurfaceLane(
                    parentCardID: laneParentID,
                    laneIndex: laneIndex,
                    labelText: indexBoardLaneLabel(
                        for: parentCard,
                        laneParentID: laneParentID,
                        tempContainerID: tempContainer?.id
                    ),
                    subtitleText: indexBoardLaneSubtitle(
                        for: parentCard,
                        childCards: laneCards,
                        laneParentID: laneParentID,
                        tempContainerID: tempContainer?.id
                    ),
                    colorToken: indexBoardLaneColorToken(for: parentCard, childCards: laneCards),
                    isTempLane: isTempLane
                )
            )

            let flowLaneCards = laneCards.filter { detachedGridPositionByCardID[$0.id] == nil }
            let detachedLaneCards = laneCards.filter { detachedGridPositionByCardID[$0.id] != nil }

            for card in flowLaneCards {
                surfaceItems.append(
                    BoardSurfaceItem(
                        cardID: card.id,
                        laneParentID: laneParentID,
                        laneIndex: laneIndex,
                        slotIndex: nextSlotIndex,
                        detachedGridPosition: nil
                    )
                )
                nextSlotIndex += 1
            }

            for card in detachedLaneCards {
                surfaceItems.append(
                    BoardSurfaceItem(
                        cardID: card.id,
                        laneParentID: laneParentID,
                        laneIndex: laneIndex,
                        slotIndex: nil,
                        detachedGridPosition: detachedGridPositionByCardID[card.id]
                    )
                )
            }
        }

        return BoardSurfaceProjection(
            source: session.source,
            lanes: lanes,
            surfaceItems: surfaceItems,
            orderedCardIDs: orderedCardIDs
        )
    }

    private func resolvedLiveIndexBoardSourceCards(for session: IndexBoardSessionState) -> [SceneCard] {
        let sourceIDSet = Set(session.sourceCardIDs)
        let originalIndexByID = Dictionary(uniqueKeysWithValues: session.sourceCardIDs.enumerated().map { index, cardID in
            (cardID, index)
        })

        return sourceIDSet.compactMap { findCard(by: $0) }
            .sorted { lhs, rhs in
                let lhsParentOrder = lhs.parent?.orderIndex ?? lhs.orderIndex
                let rhsParentOrder = rhs.parent?.orderIndex ?? rhs.orderIndex
                if lhsParentOrder != rhsParentOrder {
                    return lhsParentOrder < rhsParentOrder
                }

                let lhsParentID = lhs.parent?.id
                let rhsParentID = rhs.parent?.id
                if lhsParentID != rhsParentID {
                    let lhsFallback = originalIndexByID[lhs.id] ?? .max
                    let rhsFallback = originalIndexByID[rhs.id] ?? .max
                    if lhsFallback != rhsFallback {
                        return lhsFallback < rhsFallback
                    }
                    return (lhsParentID?.uuidString ?? "") < (rhsParentID?.uuidString ?? "")
                }

                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }

                let lhsFallback = originalIndexByID[lhs.id] ?? .max
                let rhsFallback = originalIndexByID[rhs.id] ?? .max
                if lhsFallback != rhsFallback {
                    return lhsFallback < rhsFallback
                }

                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func resolvedIndexBoardProjection() -> IndexBoardProjection? {
        guard let surfaceProjection = resolvedIndexBoardSurfaceProjection() else { return nil }

        let groups = surfaceProjection.lanes.compactMap { lane -> IndexBoardGroupProjection? in
            let childCards = surfaceProjection.surfaceItems
                .filter { $0.laneIndex == lane.laneIndex }
                .compactMap { findCard(by: $0.cardID) }
            guard !childCards.isEmpty else { return nil }

            let parentCard = lane.parentCardID.flatMap { findCard(by: $0) }
            let isTempGroup = resolvedIndexBoardTempContainer()?.id == lane.parentCardID

            return IndexBoardGroupProjection(
                id: lane.parentCardID.map { IndexBoardGroupID.parent($0) } ?? .root,
                parentCard: parentCard,
                title: lane.labelText,
                subtitle: lane.subtitleText,
                statusText: indexBoardLaneStatusText(
                    for: parentCard,
                    childCards: childCards,
                    laneParentID: lane.parentCardID,
                    isTempLane: isTempGroup
                ),
                isTempGroup: isTempGroup,
                childCards: childCards
            )
        }

        return IndexBoardProjection(
            source: surfaceProjection.source,
            orderedCardIDs: surfaceProjection.orderedCardIDs,
            groups: groups
        )
    }

    func indexBoardLaneLabel(
        for parentCard: SceneCard?,
        laneParentID: UUID?,
        tempContainerID: UUID?
    ) -> String {
        if let tempContainerID, laneParentID == tempContainerID {
            return "Temp"
        }
        if let parentCard {
            return firstMeaningfulLine(from: parentCard.content) ?? "(내용 없는 부모 카드)"
        }
        let trimmedScenarioTitle = scenario.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedScenarioTitle.isEmpty ? "(루트)" : trimmedScenarioTitle
    }

    func indexBoardLaneSubtitle(
        for parentCard: SceneCard?,
        childCards: [SceneCard],
        laneParentID: UUID?,
        tempContainerID: UUID?
    ) -> String {
        if let tempContainerID, laneParentID == tempContainerID {
            return "root -> 노트 -> temp 아래의 임시 카드 \(childCards.count)장"
        }
        if let parentCard {
            let lines = parentCard.content
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if lines.count >= 2 {
                return lines[1]
            }
            return "하위 카드 \(childCards.count)장"
        }
        return "루트 카드 \(childCards.count)장"
    }

    func indexBoardLaneColorToken(for parentCard: SceneCard?, childCards: [SceneCard]) -> String? {
        parentCard?.colorHex ?? childCards.first?.colorHex
    }

    func indexBoardLaneStatusText(
        for parentCard: SceneCard?,
        childCards: [SceneCard],
        laneParentID: UUID?,
        isTempLane: Bool
    ) -> String {
        if isTempLane {
            return "TEMP · \(childCards.count)"
        }
        if laneParentID == nil && parentCard == nil {
            return "ROOT · \(childCards.count)"
        }
        let category = parentCard?.category ?? childCards.first?.category ?? ScenarioCardCategory.uncategorized
        return "\(category) · \(childCards.count)"
    }

    func indexBoardGroupTitle(for parentCard: SceneCard?) -> String {
        indexBoardLaneLabel(for: parentCard, laneParentID: parentCard?.id, tempContainerID: nil)
    }

    func indexBoardGroupSubtitle(for parentCard: SceneCard?, childCards: [SceneCard]) -> String {
        indexBoardLaneSubtitle(for: parentCard, childCards: childCards, laneParentID: parentCard?.id, tempContainerID: nil)
    }

    func indexBoardGroupStatusText(for parentCard: SceneCard?, childCards: [SceneCard]) -> String {
        if parentCard == nil {
            return "ROOT · \(childCards.count)"
        }
        let category = parentCard?.category ?? childCards.first?.category ?? ScenarioCardCategory.uncategorized
        return "\(category) · \(childCards.count)"
    }

    var clampedIndexBoardZoomScale: CGFloat {
        let rawScale = activeIndexBoardSession?.zoomScale ?? IndexBoardZoom.defaultScale
        return min(max(rawScale, IndexBoardZoom.minScale), IndexBoardZoom.maxScale)
    }

    func setIndexBoardZoomScale(_ scale: CGFloat) {
        guard isIndexBoardActive else { return }
        let clamped = min(max(scale, IndexBoardZoom.minScale), IndexBoardZoom.maxScale)
        let rounded = (clamped * 100).rounded() / 100
        indexBoardRuntime.updateSession(for: scenario.id, paneID: paneContextID) { session in
            session.zoomScale = rounded
        }
    }

    func stepIndexBoardZoom(by delta: CGFloat) {
        setIndexBoardZoomScale(clampedIndexBoardZoomScale + delta)
    }

    func resetIndexBoardZoom() {
        setIndexBoardZoomScale(IndexBoardZoom.defaultScale)
    }

    func updateIndexBoardScrollOffset(_ offset: CGPoint) {
        guard isIndexBoardActive else { return }
        indexBoardRuntime.updateSession(for: scenario.id, paneID: paneContextID) { session in
            session.scrollOffset = CGPoint(
                x: max(0, offset.x),
                y: max(0, offset.y)
            )
        }
    }

    func handleIndexBoardCardClick(_ card: SceneCard, orderedCardIDs: [UUID]) {
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommandPressed = flags.contains(.command)
        let isShiftPressed = flags.contains(.shift)

        finishEditing()

        if isCommandPressed && isShiftPressed {
            handleIndexBoardRangeClick(card, orderedCardIDs: orderedCardIDs, additive: true)
        } else if isShiftPressed {
            handleIndexBoardRangeClick(card, orderedCardIDs: orderedCardIDs, additive: false)
        } else if isCommandPressed {
            handleIndexBoardCommandClick(card)
        } else {
            selectedCardIDs = [card.id]
            keyboardRangeSelectionAnchorCardID = card.id
        }

        changeActiveCard(to: card, deferToMainAsync: false)
        isMainViewFocused = true
    }

    func handleIndexBoardCommandClick(_ card: SceneCard) {
        if selectedCardIDs.contains(card.id) {
            selectedCardIDs.remove(card.id)
            if keyboardRangeSelectionAnchorCardID == card.id {
                keyboardRangeSelectionAnchorCardID = selectedCardIDs.first
            }
        } else {
            selectedCardIDs.insert(card.id)
            if keyboardRangeSelectionAnchorCardID == nil {
                keyboardRangeSelectionAnchorCardID = card.id
            }
        }
    }

    func handleIndexBoardRangeClick(_ card: SceneCard, orderedCardIDs: [UUID], additive: Bool) {
        guard let anchorID = resolvedIndexBoardRangeAnchorID(in: orderedCardIDs) else {
            selectedCardIDs = [card.id]
            keyboardRangeSelectionAnchorCardID = card.id
            return
        }

        keyboardRangeSelectionAnchorCardID = anchorID
        let rangeIDs = indexBoardRangeSelectionIDs(
            in: orderedCardIDs,
            anchorID: anchorID,
            targetID: card.id
        )

        if additive {
            selectedCardIDs.formUnion(rangeIDs)
        } else {
            selectedCardIDs = rangeIDs
        }
    }

    func resolvedIndexBoardRangeAnchorID(in orderedCardIDs: [UUID]) -> UUID? {
        if let anchorID = keyboardRangeSelectionAnchorCardID,
           selectedCardIDs.contains(anchorID),
           orderedCardIDs.contains(anchorID) {
            return anchorID
        }

        if selectedCardIDs.count == 1,
           let selectedID = selectedCardIDs.first,
           orderedCardIDs.contains(selectedID) {
            return selectedID
        }

        if let activeCardID, selectedCardIDs.contains(activeCardID), orderedCardIDs.contains(activeCardID) {
            return activeCardID
        }

        return orderedCardIDs.first(where: { selectedCardIDs.contains($0) })
    }

    func indexBoardRangeSelectionIDs(
        in orderedCardIDs: [UUID],
        anchorID: UUID,
        targetID: UUID
    ) -> Set<UUID> {
        guard let anchorIndex = orderedCardIDs.firstIndex(of: anchorID),
              let targetIndex = orderedCardIDs.firstIndex(of: targetID) else {
            return [targetID]
        }

        let lowerBound = min(anchorIndex, targetIndex)
        let upperBound = max(anchorIndex, targetIndex)
        return Set(orderedCardIDs[lowerBound ... upperBound])
    }

    func applyIndexBoardMarqueeSelection(_ cardIDs: Set<UUID>, orderedCardIDs: [UUID]) {
        finishEditing()

        let orderedSelection = orderedCardIDs.filter { cardIDs.contains($0) }
        selectedCardIDs = Set(orderedSelection)
        keyboardRangeSelectionAnchorCardID = orderedSelection.first

        if let primaryCardID = orderedSelection.first,
           let card = findCard(by: primaryCardID) {
            changeActiveCard(to: card, deferToMainAsync: false)
        }

        isMainViewFocused = true
    }

    func clearIndexBoardSelection() {
        selectedCardIDs = []
        keyboardRangeSelectionAnchorCardID = nil
        activeCardID = nil
        synchronizeActiveRelationState(for: nil)
        isMainViewFocused = true
    }

    func toggleIndexBoardCardFace(_ card: SceneCard) {
        guard isIndexBoardActive else { return }
        let nextShowsBack = !(activeIndexBoardSession?.showsBackByCardID[card.id] ?? false)
        indexBoardRuntime.updateSession(for: scenario.id, paneID: paneContextID) { session in
            session.showsBackByCardID[card.id] = nextShowsBack
        }
    }

    @ViewBuilder
    func indexBoardCanvas(size: CGSize) -> some View {
        if let surfaceProjection = resolvedIndexBoardSurfaceProjection(),
           let projection = resolvedIndexBoardProjection() {
            let cardsByID = Dictionary(
                uniqueKeysWithValues: surfaceProjection.orderedCardIDs.compactMap { cardID in
                    findCard(by: cardID).map { (cardID, $0) }
                }
            )
            let summaryByCardID = Dictionary(
                uniqueKeysWithValues: surfaceProjection.orderedCardIDs.compactMap { cardID in
                    resolvedIndexBoardSummary(for: cardID).map { (cardID, $0) }
                }
            )
            let zoomScale = clampedIndexBoardZoomScale
            let scrollOffset = activeIndexBoardSession?.scrollOffset ?? .zero
            let showsBackByCardID = activeIndexBoardSession?.showsBackByCardID ?? [:]
            let revealCardID = activeIndexBoardSession?.pendingRevealCardID
            let revealRequestToken = activeIndexBoardSession?.revealRequestToken ?? 0
            IndexBoardPhaseThreeView(
                surfaceProjection: surfaceProjection,
                projection: projection,
                sourceTitle: indexBoardSourceTitle(for: surfaceProjection.source.parentID),
                canvasSize: size,
                theme: IndexBoardRenderTheme(
                    usesDarkAppearance: isDarkAppearanceActive,
                    cardBaseColorHex: cardBaseColorHex,
                    cardActiveColorHex: cardActiveColorHex,
                    darkCardBaseColorHex: darkCardBaseColorHex,
                    darkCardActiveColorHex: darkCardActiveColorHex
                ),
                cardsByID: cardsByID,
                activeCardID: activeCardID,
                selectedCardIDs: selectedCardIDs,
                summaryByCardID: summaryByCardID,
                showsBackByCardID: showsBackByCardID,
                zoomScale: zoomScale,
                scrollOffset: scrollOffset,
                revealCardID: revealCardID,
                revealRequestToken: revealRequestToken,
                editorDraft: indexBoardEditorDraft,
                editorSummary: resolvedIndexBoardSummary(for: indexBoardEditorDraft?.cardID),
                onClose: closeIndexBoard,
                onCreateTempCard: {
                    _ = createIndexBoardTempCard()
                },
                onCardTap: { card in
                    handleIndexBoardCardClick(card, orderedCardIDs: surfaceProjection.orderedCardIDs)
                },
                onCardOpen: { card in
                    presentIndexBoardEditor(for: card)
                },
                onCardFaceToggle: { card in
                    toggleIndexBoardCardFace(card)
                },
                onZoomScaleChange: { scale in
                    setIndexBoardZoomScale(scale)
                },
                onZoomStep: { delta in
                    stepIndexBoardZoom(by: delta)
                },
                onZoomReset: {
                    resetIndexBoardZoom()
                },
                onScrollOffsetChange: { offset in
                    updateIndexBoardScrollOffset(offset)
                },
                onCardMove: { cardID, target in
                    commitIndexBoardCardMove(
                        cardID: cardID,
                        target: target,
                        projection: projection
                    )
                },
                onCardMoveSelection: { cardIDs, draggedCardID, target in
                    commitIndexBoardCardMoveSelection(
                        cardIDs: cardIDs,
                        draggedCardID: draggedCardID,
                        target: target,
                        projection: projection
                    )
                },
                onMarqueeSelectionChange: { cardIDs in
                    applyIndexBoardMarqueeSelection(
                        cardIDs,
                        orderedCardIDs: surfaceProjection.orderedCardIDs
                    )
                },
                onClearSelection: {
                    clearIndexBoardSelection()
                },
                onGroupMove: { groupID, targetIndex in
                    commitIndexBoardGroupMove(
                        groupID: groupID,
                        targetIndex: targetIndex,
                        projection: projection
                    )
                },
                onEditorDraftChange: { draft in
                    updateIndexBoardEditorDraft(draft)
                },
                onCancelEditor: {
                    saveIndexBoardEditor()
                },
                onSaveEditor: {
                    saveIndexBoardEditor()
                }
            )
        } else if let session = activeIndexBoardSession {
            IndexBoardScaffoldView(
                session: session,
                sourceTitle: indexBoardSourceTitle(for: session.sourceParentID),
                activeCardCount: session.sourceCardIDs.count,
                onClose: closeIndexBoard
            )
        } else {
            Color.clear
                .frame(width: size.width, height: size.height)
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
