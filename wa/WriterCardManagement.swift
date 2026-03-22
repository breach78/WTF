import SwiftUI
import AppKit
import QuartzCore
import UniformTypeIdentifiers

extension ScenarioWriterView {

    // MARK: - Canvas Position Restore

    private var mainCanvasRestoreRetryDelays: [TimeInterval] {
        [0.0, 0.05, 0.18]
    }

    private var mainColumnDescendantFocusCoalescingDelay: TimeInterval {
        0.10
    }

    private func enqueueMainCanvasRestoreRequest(
        targetID: UUID?,
        visibleLevel: Int? = nil,
        forceSemantic: Bool = false,
        reason: MainCanvasViewState.RestoreRequest.Reason = .generic
    ) {
        guard !showFocusMode else { return }
        guard let targetID else { return }
        DispatchQueue.main.async {
            guard !showFocusMode else { return }
            scheduleMainCanvasRestoreRequest(
                targetCardID: targetID,
                visibleLevel: visibleLevel,
                forceSemantic: forceSemantic,
                reason: reason
            )
        }
    }

    func scheduleMainCanvasRestoreRetries(_ action: @escaping () -> Void) {
        for delay in mainCanvasRestoreRetryDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                action()
            }
        }
    }

    func restoreMainCanvasPositionIfNeeded(proxy: ScrollViewProxy, availableWidth: CGFloat) {
        guard !showFocusMode else { return }
        guard !isPreviewingHistory else { return }
        guard let request = pendingMainCanvasRestoreRequest else { return }

        if let visibleLevel = request.visibleLevel {
            lastScrolledLevel = max(0, visibleLevel)
            let restored = performMainCanvasHorizontalScroll(
                level: lastScrolledLevel,
                availableWidth: availableWidth,
                animated: false
            )
            guard restored else {
                return
            }
            pendingMainCanvasRestoreRequest = nil
            return
        }

        scrollToColumnIfNeeded(
            targetCardID: request.targetCardID,
            proxy: proxy,
            availableWidth: availableWidth,
            force: request.forceSemantic,
            animated: false
        )
        pendingMainCanvasRestoreRequest = nil
    }

    func requestMainCanvasRestoreForHistoryToggle() {
        enqueueMainCanvasRestoreRequest(
            targetID: activeCardID ?? lastActiveCardID ?? scenario.rootCards.first?.id
        )
    }

    func requestMainCanvasRestoreForFocusExit(using snapshot: FocusModeWorkspaceSnapshot?) {
        let targetID = activeCardID ?? editingCardID ?? lastActiveCardID ?? scenario.rootCards.first?.id
        let visibleLevel = snapshot?.visibleMainCanvasLevel
        enqueueMainCanvasRestoreRequest(
            targetID: targetID,
            visibleLevel: visibleLevel,
            forceSemantic: true,
            reason: MainCanvasViewState.RestoreRequest.Reason.focusExit
        )
    }

    func requestMainCanvasViewportRestoreForFocusExit(using snapshot: FocusModeWorkspaceSnapshot?) {
        guard !showFocusMode else { return }
        let storedOffsets = snapshot?.mainColumnViewportOffsets ?? mainColumnViewportOffsetByKey
        guard !storedOffsets.isEmpty else { return }
        scheduleMainCanvasRestoreRetries {
            guard !showFocusMode else { return }
            applyStoredMainColumnViewportOffsets(storedOffsets)
        }
    }

    func captureFocusModeEntryWorkspaceSnapshot() {
        guard !showFocusMode else { return }
        let visibleLevel: Int?
        if let visibleLevel = resolvedVisibleMainCanvasLevelFromCurrentScrollPosition() {
            lastScrolledLevel = visibleLevel
            focusModeEntryWorkspaceSnapshot = FocusModeWorkspaceSnapshot(
                activeCardID: activeCardID,
                editingCardID: editingCardID,
                selectedCardIDs: selectedCardIDs,
                visibleMainCanvasLevel: visibleLevel,
                mainCanvasHorizontalOffset: mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalOffset().map { max(0, $0) },
                mainColumnViewportOffsets: mainColumnViewportOffsetByKey,
                capturedAt: Date()
            )
            return
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
        if let visibleLevel {
            lastScrolledLevel = visibleLevel
        }
        focusModeEntryWorkspaceSnapshot = FocusModeWorkspaceSnapshot(
            activeCardID: activeCardID,
            editingCardID: editingCardID,
            selectedCardIDs: selectedCardIDs,
            visibleMainCanvasLevel: visibleLevel,
            mainCanvasHorizontalOffset: mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalOffset().map { max(0, $0) },
            mainColumnViewportOffsets: mainColumnViewportOffsetByKey,
            capturedAt: Date()
        )
    }

    func canReuseRetainedMainCanvasShellForFocusExit(using snapshot: FocusModeWorkspaceSnapshot?) -> Bool {
        guard !showFocusMode else { return false }
        guard mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalScrollView() != nil else { return false }
        guard let snapshot else { return true }
        let requiredViewportKeys = snapshot.mainColumnViewportOffsets.compactMap { entry in
            entry.value > 1 ? entry.key : nil
        }
        for viewportKey in requiredViewportKeys {
            guard mainCanvasScrollCoordinator.scrollView(for: viewportKey) != nil else { return false }
        }
        return true
    }

    func finalizeRetainedMainCanvasShellForFocusExitReuse() {
        pendingMainCanvasRestoreRequest = nil
        cancelAllPendingMainColumnFocusWork()
    }

    // MARK: - Main Vertical Scroll Authority

    @discardableResult
    func beginMainVerticalScrollAuthority(
        viewportKey: String,
        kind: MainVerticalScrollAuthorityKind,
        targetCardID: UUID?
    ) -> MainVerticalScrollAuthority {
        mainVerticalScrollAuthoritySequence &+= 1
        let authority = MainVerticalScrollAuthority(
            id: mainVerticalScrollAuthoritySequence,
            kind: kind,
            targetCardID: targetCardID
        )
        mainVerticalScrollAuthorityByViewportKey[viewportKey] = authority
        bounceDebugLog(
            "beginMainVerticalScrollAuthority key=\(viewportKey) kind=\(kind.rawValue) target=\(debugCardIDString(targetCardID)) id=\(authority.id)"
        )
        return authority
    }

    func isMainVerticalScrollAuthorityCurrent(
        _ authority: MainVerticalScrollAuthority?,
        viewportKey: String
    ) -> Bool {
        guard let authority else { return true }
        return mainVerticalScrollAuthorityByViewportKey[viewportKey] == authority
    }

    func resolvedMainColumnViewportKey(forCardID cardID: UUID) -> String? {
        guard let level = displayedMainCardLocationByID(cardID)?.level else { return nil }
        return mainColumnViewportStorageKey(level: level)
    }

    func resolvedVisibleMainCanvasLevelFromCurrentScrollPosition() -> Int? {
        guard let scrollView = mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalScrollView() else { return nil }
        let visualLevelCount = max(1, resolvedDisplayedMainLevelsWithParents().count)
        let visibleRect = scrollView.documentVisibleRect
        let documentWidth = scrollView.documentView?.bounds.width ?? 0
        let availableWidth = max(1, documentWidth - (CGFloat(visualLevelCount) * columnWidth))
        let maxX = max(0, documentWidth - visibleRect.width)
        let currentX = scrollView.contentView.bounds.origin.x

        var bestLevel = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for level in 0..<visualLevelCount {
            let targetX = resolvedMainCanvasHorizontalTargetX(
                level: level,
                availableWidth: availableWidth,
                visibleWidth: visibleRect.width
            )
            let resolvedTargetX = CaretScrollCoordinator.resolvedHorizontalTargetX(
                visibleRect: visibleRect,
                targetX: targetX,
                minX: 0,
                maxX: maxX,
                snapToPixel: true
            )
            let distance = abs(resolvedTargetX - currentX)
            if distance < bestDistance {
                bestDistance = distance
                bestLevel = level
            }
        }
        return bestLevel
    }

    func restoreMainCanvasHorizontalViewport(to storedOffsetX: CGFloat) {
        guard !showFocusMode else { return }
        suppressHorizontalAutoScroll = true
        mainCanvasScrollCoordinator.scheduleMainCanvasHorizontalRestore(offsetX: storedOffsetX)
        scheduleMainCanvasRestoreRetries {
            guard !showFocusMode else { return }
            guard let scrollView = mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalScrollView() else { return }
            let visibleRect = scrollView.documentVisibleRect
            let documentWidth = scrollView.documentView?.bounds.width ?? 0
            let maxX = max(0, documentWidth - visibleRect.width)
            _ = CaretScrollCoordinator.applyHorizontalScrollIfNeeded(
                scrollView: scrollView,
                visibleRect: visibleRect,
                targetX: storedOffsetX,
                minX: 0,
                maxX: maxX,
                deadZone: 0.5,
                snapToPixel: true
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            suppressHorizontalAutoScroll = false
        }
    }

    func requestMainCanvasRestoreForZoomChange() {
        guard !showFocusMode else { return }
        guard !showHistoryBar else { return }
        enqueueMainCanvasRestoreRequest(
            targetID: activeCardID ?? editingCardID ?? lastActiveCardID ?? scenario.rootCards.first?.id
        )
    }

    func requestMainCanvasRestoreForHorizontalScrollModeChange() {
        guard !showFocusMode else { return }
        guard !showHistoryBar else { return }
        enqueueMainCanvasRestoreRequest(
            targetID: activeCardID ?? editingCardID ?? lastActiveCardID ?? scenario.rootCards.first?.id
        )
    }

    func cancelMainArrowNavigationSettle() {
        mainArrowNavigationSettleWorkItem?.cancel()
        mainArrowNavigationSettleWorkItem = nil
    }

    func scheduleMainArrowNavigationSettle() {
        cancelMainArrowNavigationSettle()
        let workItem = DispatchWorkItem {
            defer { mainArrowNavigationSettleWorkItem = nil }
            guard acceptsKeyboardInput else { return }
            guard !showFocusMode else { return }
            guard !isPreviewingHistory else { return }
            guard let activeID = activeCardID, findCard(by: activeID) != nil else { return }
            mainColumnLastFocusRequestByKey = [:]
            bounceDebugLog(
                "mainArrowNavigationSettle target=\(debugCardIDString(activeID)) " +
                "\(debugFocusStateSummary())"
            )
            _ = mainCanvasScrollCoordinator.publishIntent(
                kind: .settleRecovery,
                scope: .allColumns,
                targetCardID: activeID,
                expectedActiveCardID: activeID,
                animated: false,
                trigger: "navigationSettle"
            )
            mainNavigationSettleTick += 1
        }
        mainArrowNavigationSettleWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    @discardableResult
    func publishMainColumnNavigationIntent(
        kind: MainCanvasScrollCoordinator.NavigationIntentKind,
        scope: MainCanvasScrollCoordinator.NavigationIntentScope,
        targetCardID: UUID? = nil,
        expectedActiveCardID: UUID? = nil,
        animated: Bool,
        trigger: String
    ) -> MainCanvasScrollCoordinator.NavigationIntent {
        mainCanvasScrollCoordinator.publishIntent(
            kind: kind,
            scope: scope,
            targetCardID: targetCardID,
            expectedActiveCardID: expectedActiveCardID,
            animated: animated,
            trigger: trigger
        )
    }

    func publishMainColumnFocusNavigationIntent(
        for activeID: UUID?,
        trigger: String = "activeCardChange"
    ) {
        let shouldAnimate =
            focusNavigationAnimationEnabled &&
            !shouldSuppressMainArrowRepeatAnimation()
        _ = publishMainColumnNavigationIntent(
            kind: .focusChange,
            scope: .allColumns,
            targetCardID: activeID,
            expectedActiveCardID: activeID,
            animated: shouldAnimate,
            trigger: trigger
        )
    }

    // MARK: - Debug Helpers

    func debugCGFloat(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }

    func debugCardIDString(_ id: UUID?) -> String {
        guard let id else { return "nil" }
        return String(id.uuidString.prefix(8))
    }

    func debugCardToken(_ card: SceneCard?) -> String {
        guard let card else { return "nil" }
        let compact = card.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = compact.isEmpty ? "empty" : String(compact.prefix(18))
        return "\(debugCardIDString(card.id)):\(preview)"
    }

    func debugUUIDListSummary(_ ids: [UUID], limit: Int = 6) -> String {
        let displayed = ids.prefix(limit).map { debugCardIDString($0) }.joined(separator: ",")
        if ids.count > limit {
            return "[\(displayed),+\(ids.count - limit)]"
        }
        return "[\(displayed)]"
    }

    func debugFocusStateSummary() -> String {
        let sortedAncestors = activeAncestorIDs.sorted { $0.uuidString < $1.uuidString }
        return
            "active=\(debugCardIDString(activeCardID)) pending=\(debugCardIDString(pendingActiveCardID)) " +
            "editing=\(debugCardIDString(editingCardID)) ancestors=\(debugUUIDListSummary(sortedAncestors, limit: 8)) " +
            "siblings=\(activeSiblingIDs.count) descendants=\(activeDescendantIDs.count)"
    }

    func mainColumnViewportCoordinateSpaceName(_ viewportKey: String) -> String {
        "main-column-viewport:\(viewportKey)"
    }

    func debugMainColumnEstimatedTargetSummary(_ layout: (targetMinY: CGFloat, targetMaxY: CGFloat)?) -> String {
        guard let layout else { return "est=unresolved" }
        return "est[\(debugCGFloat(layout.targetMinY)),\(debugCGFloat(layout.targetMaxY))]"
    }

    func debugMainColumnObservedTargetSummary(viewportKey: String, targetID: UUID, offsetY: CGFloat) -> String {
        guard let frame = observedMainColumnTargetFrame(
            viewportKey: viewportKey,
            targetID: targetID
        ) else {
            return "frame=unseen"
        }
        let visibleMinY = frame.minY - offsetY
        let visibleMaxY = frame.maxY - offsetY
        return
            "frame=view[\(debugCGFloat(visibleMinY)),\(debugCGFloat(visibleMaxY))] " +
            "content[\(debugCGFloat(frame.minY)),\(debugCGFloat(frame.maxY))] h=\(debugCGFloat(frame.height))"
    }

    func debugMainColumnVisibleCardSummary(
        viewportKey: String,
        cards: [SceneCard],
        viewportHeight: CGFloat,
        offsetY: CGFloat
    ) -> String {
        if let observedFrames = mainCanvasScrollCoordinator.geometryModel(for: viewportKey)?.observedFramesByCardID,
           !observedFrames.isEmpty {
            let visible = cards.compactMap { card -> String? in
                guard let frame = observedFrames[card.id] else { return nil }
                let visibleMinY = frame.minY - offsetY
                let visibleMaxY = frame.maxY - offsetY
                guard visibleMaxY >= -32, visibleMinY <= viewportHeight + 32 else { return nil }
                let marker = card.id == activeCardID ? "*" : (activeAncestorIDs.contains(card.id) ? "^" : "")
                return "\(marker)\(debugCardIDString(card.id))@\(debugCGFloat(visibleMinY))...\(debugCGFloat(visibleMaxY))"
            }
            if !visible.isEmpty {
                return visible.prefix(6).joined(separator: " | ")
            }
        }

        let snapshot = resolvedMainColumnLayoutSnapshot(in: cards, viewportHeight: viewportHeight)
        var visible: [String] = []
        for cardID in snapshot.orderedCardIDs {
            guard let frame = snapshot.framesByCardID[cardID] else { continue }
            let visibleMinY = frame.minY - offsetY
            let visibleMaxY = frame.maxY - offsetY
            guard visibleMaxY >= -32, visibleMinY <= viewportHeight + 32 else { continue }
            let marker = cardID == activeCardID ? "*" : (activeAncestorIDs.contains(cardID) ? "^" : "")
            visible.append("\(marker)\(debugCardIDString(cardID))@\(debugCGFloat(visibleMinY))...\(debugCGFloat(visibleMaxY))")
            if visible.count == 6 {
                break
            }
        }

        return visible.isEmpty ? "none" : visible.joined(separator: " | ")
    }

    func mainColumnGeometryObservationCardIDs(
        in cards: [SceneCard],
        viewportKey: String,
        viewportHeight: CGFloat
    ) -> Set<UUID> {
        let allIDs = Set(cards.map(\.id))
        guard cards.count > 24 else { return allIDs }

        let snapshot = resolvedMainColumnLayoutSnapshot(in: cards, viewportHeight: viewportHeight)
        let visibleRect = resolvedMainColumnVisibleRect(
            viewportKey: viewportKey,
            viewportHeight: viewportHeight
        )
        let preloadDistance = max(viewportHeight * 0.75, 240)
        let observedMinY = visibleRect.minY - preloadDistance
        let observedMaxY = visibleRect.maxY + preloadDistance

        var observedIDs: Set<UUID> = []
        observedIDs.reserveCapacity(min(cards.count, 24))

        for cardID in snapshot.orderedCardIDs {
            guard let frame = snapshot.framesByCardID[cardID] else { continue }
            guard frame.maxY >= observedMinY, frame.minY <= observedMaxY else { continue }
            observedIDs.insert(cardID)
        }

        if let targetID = resolvedMainColumnFocusTargetID(in: cards),
           let targetIndex = cards.firstIndex(where: { $0.id == targetID }) {
            let lowerBound = max(cards.startIndex, targetIndex - 6)
            let upperBound = min(cards.index(before: cards.endIndex), targetIndex + 6)
            for index in lowerBound...upperBound {
                observedIDs.insert(cards[index].id)
            }
        }

        if let activeCardID, allIDs.contains(activeCardID) {
            observedIDs.insert(activeCardID)
        }
        if let editingCardID, allIDs.contains(editingCardID) {
            observedIDs.insert(editingCardID)
        }

        if observedIDs.isEmpty {
            for card in cards.prefix(12) {
                observedIDs.insert(card.id)
            }
        }

        return observedIDs
    }

    // MARK: - Resolved Colors & Search

    func resolvedBackgroundColor() -> Color {
        if isDarkAppearanceActive {
            let darkRGB = rgbFromHex(darkBackgroundColorHex) ?? (0.07, 0.08, 0.10)
            return Color(red: darkRGB.0, green: darkRGB.1, blue: darkRGB.2)
        }
        let lightRGB = rgbFromHex(backgroundColorHex) ?? (0.96, 0.95, 0.93)
        return Color(red: lightRGB.0, green: lightRGB.1, blue: lightRGB.2)
    }

    func resolvedTimelineBackgroundColor() -> Color {
        if isDarkAppearanceActive {
            return Color(red: 0.11, green: 0.12, blue: 0.14)
        }
        return Color(red: 0.94, green: 0.93, blue: 0.91)
    }

    func matchesSearch(_ card: SceneCard) -> Bool {
        let tokens = searchTokens(from: searchText)
        if tokens.isEmpty { return true }
        let haystack = normalizedSearchText(card.content)
        for token in tokens {
            if !haystack.contains(token) { return false }
        }
        return true
    }

    func searchTokens(from text: String) -> [String] {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .map { normalizedSearchText($0) }
            .filter { !$0.isEmpty }
    }

    func normalizedSearchText(_ text: String) -> String {
        let lowered = text.lowercased()
        let withoutSpaces = lowered.filter { !$0.isWhitespace }
        return String(withoutSpaces)
    }

    // MARK: - Color Utilities

    func rgbFromHex(_ hex: String) -> (Double, Double, Double)? {
        parseHexRGB(hex)
    }

    enum MutationUndoMode {
        case main
        case focusAware
        case none
    }

    func prepareWriterModelForPersistence() {
        store.synchronizeSharedCraftTrees(preserveExistingTimestamps: true)
    }

    func saveWriterChanges(immediate: Bool = false) {
        prepareWriterModelForPersistence()
        store.saveAll(immediate: immediate)
    }

    func persistCardMutation(forceSnapshot: Bool = false, immediateSave: Bool = false) {
        saveWriterChanges(immediate: immediateSave)
        takeSnapshot(force: forceSnapshot)
    }

    func commitCardMutation(
        previousState: ScenarioState,
        actionName: String,
        forceSnapshot: Bool = false,
        immediateSave: Bool = false,
        undoMode: MutationUndoMode = .main
    ) {
        persistCardMutation(forceSnapshot: forceSnapshot, immediateSave: immediateSave)
        switch undoMode {
        case .main:
            pushUndoState(previousState, actionName: actionName)
        case .focusAware:
            if showFocusMode {
                pushFocusUndoState(previousState, actionName: actionName)
            } else {
                pushUndoState(previousState, actionName: actionName)
            }
        case .none:
            break
        }
    }

    // MARK: - Timeline & Column View Builders

    func beginCardEditing(_ card: SceneCard, explicitCaretLocation: Int? = nil) {
        finishEditing()
        pendingMainEditingSiblingNavigationTargetID = nil
        if let explicitCaretLocation {
            pendingMainEditingViewportKeepVisibleCardID = nil
            pendingMainEditingViewportRevealEdge = nil
            let textLength = (card.content as NSString).length
            let safeLocation = min(max(0, explicitCaretLocation), textLength)
            mainCaretLocationByCardID[card.id] = safeLocation
            mainProgrammaticCaretSuppressEnsureCardID = card.id
            mainProgrammaticCaretExpectedCardID = card.id
            mainProgrammaticCaretExpectedLocation = safeLocation
            mainProgrammaticCaretSelectionIgnoreUntil = Date().addingTimeInterval(0.28)
        } else {
            pendingMainEditingViewportKeepVisibleCardID = card.id
            pendingMainEditingViewportRevealEdge = nil
            mainProgrammaticCaretSuppressEnsureCardID = nil
            mainProgrammaticCaretExpectedCardID = nil
            mainProgrammaticCaretExpectedLocation = -1
            mainProgrammaticCaretSelectionIgnoreUntil = .distantPast
        }
        changeActiveCard(to: card)
        editingCardID = card.id
        editingStartContent = card.content
        editingStartState = captureScenarioState()
        editingIsNewCard = false
        selectedCardIDs = [card.id]
    }

    @ViewBuilder
    func timelineRow(_ card: SceneCard) -> some View {
        let isNamedNote = isNamedSnapshotNoteCard(card)
        let isAICandidate = aiCandidateState.cardIDs.contains(card.id) || card.isAICandidate
        let isTimelineSelected = selectedCardIDs.contains(card.id)
        let isTimelineMultiSelected = selectedCardIDs.count > 1 && isTimelineSelected
        let isTimelineEmptyCard = card.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isPlotLineCard = card.category == ScenarioCardCategory.plot
        let canSummarizeChildren = canSummarizeDirectChildren(for: card)
        let isCloneLinked = scenario.isCardCloned(card.id)
        let hasLinkedCards = scenario.hasLinkedCards(card.id)
        let isLinkedCard = scenario.isLinkedCard(card.id)
        let disconnectAnchorID = resolvedLinkedCardsAnchorID()
        let canDisconnectLinkedCard =
            linkedCardsFilterEnabled &&
            disconnectAnchorID.flatMap { anchorID in
                scenario.linkedCardEditDate(
                    focusCardID: anchorID,
                    linkedCardID: card.id
                )
            } != nil
        let clonePeerDestinations = isCloneLinked ? clonePeerMenuDestinations(for: card) : []
        CardItem(
            card: card,
            renderSettings: mainCardRenderSettings,
            isActive: activeCardID == card.id,
            isSelected: selectedCardIDs.contains(card.id),
            isMultiSelected: selectedCardIDs.count > 1 && selectedCardIDs.contains(card.id),
            isArchived: card.isArchived,
            isAncestor: false,
            isDescendant: false,
            isEditing: acceptsKeyboardInput && editingCardID == card.id,
            preferredTextMeasureWidth: TimelinePanelLayoutMetrics.textWidth,
            forceNamedSnapshotNoteStyle: isNamedNote,
            forceCustomColorVisibility: isAICandidate,
            onSelect: {
                if openHistoryFromNamedSnapshotNoteCard(card) { return }
                handleTimelineCardSelect(card)
            },
            onDoubleClick: {
                if openHistoryFromNamedSnapshotNoteCard(card) { return }
                handleTimelineCardDoubleClick(card)
            },
            onEndEdit: { finishEditing() },
            onContentChange: nil,
            onColorChange: { hex in setCardColor(card, hex: hex) },
            onReferenceCard: { addCardToReferenceWindow(card) },
            onSummarizeChildren: canSummarizeChildren ? {
                runChildSummaryFromCardContextMenu(for: card)
            } : nil,
            onAIElaborate: {
                runAICardActionFromContextMenu(for: card, action: .elaborate)
            },
            onAINextScene: {
                runAICardActionFromContextMenu(for: card, action: .nextScene)
            },
            onAIAlternative: {
                runAICardActionFromContextMenu(for: card, action: .alternative)
            },
            onAISummarizeCurrent: {
                runAICardActionFromContextMenu(for: card, action: .summary)
            },
            aiPlotActionsEnabled: isPlotLineCard,
            onApplyAICandidate: isAICandidate ? {
                applyAICandidateFromCardContextMenu(cardID: card.id)
            } : nil,
            isSummarizingChildren: aiChildSummaryLoadingCardIDs.contains(card.id),
            isAIBusy: aiIsGenerating,
            onDelete: { performDelete(card) },
            onHardDelete: { performHardDelete(card) },
            onTranscriptionMode: { startDictationMode(from: card) },
            isTranscriptionBusy: dictationIsRecording || dictationIsProcessing,
            showsEmptyCardBulkDeleteMenuOnly: isTimelineEmptyCard,
            onBulkDeleteEmptyCards: isTimelineEmptyCard ? { performHardDeleteAllTimelineEmptyLeafCards() } : nil,
            isCloneLinked: isCloneLinked,
            hasLinkedCards: hasLinkedCards,
            isLinkedCard: isLinkedCard,
            onDisconnectLinkedCard: canDisconnectLinkedCard ? {
                disconnectLinkedCardFromAnchor(linkedCardID: card.id)
            } : nil,
            onCloneCard: { copyCardsAsCloneFromContext(card) },
            clonePeerDestinations: clonePeerDestinations,
            onNavigateToClonePeer: { targetID in navigateToCloneCard(targetID) }
        )
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isTimelineSelected
                    ? Color.accentColor.opacity(isTimelineMultiSelected ? 0.26 : 0.16)
                    : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isTimelineSelected
                    ? Color.accentColor.opacity(isTimelineMultiSelected ? 0.95 : 0.70)
                    : Color.clear,
                    lineWidth: isTimelineMultiSelected ? 2 : 1
                )
        )
        .id("timeline-\(card.id)")
        .onDrag {
            MainCardDragSessionTracker.shared.begin()
            return NSItemProvider(object: card.id.uuidString as NSString)
        }
    }

    @ViewBuilder
    func column(for cards: [SceneCard], level: Int, parent: SceneCard?, screenHeight: CGFloat) -> some View {
        let childListSignature = scenario.childListSignature(parentID: parent?.id)
        let viewportKey = mainColumnViewportStorageKey(level: level)
        let containsActiveCard = cards.contains { $0.id == activeCardID }
        let containsActiveAncestor = cards.contains { activeAncestorIDs.contains($0.id) }
        let observedCardIDs = mainColumnGeometryObservationCardIDs(
            in: cards,
            viewportKey: viewportKey,
            viewportHeight: screenHeight
        )
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        if cards.isEmpty {
                            DropSpacer(target: .columnTop(parent?.id), alignment: .bottom) { providers, includeTrailingSiblingBlock in
                                handleGeneralDrop(
                                    providers,
                                    target: .columnTop(parent?.id),
                                    includeTrailingSiblingBlock: includeTrailingSiblingBlock
                                )
                            }
                            .frame(height: screenHeight * 0.4)

                            if level == 0 { addFirstButton(level: level) }

                            DropSpacer(target: .columnBottom(parent?.id), alignment: .top) { providers, includeTrailingSiblingBlock in
                                handleGeneralDrop(
                                    providers,
                                    target: .columnBottom(parent?.id),
                                    includeTrailingSiblingBlock: includeTrailingSiblingBlock
                                )
                            }
                            .frame(height: screenHeight * 0.7)
                        } else {
                            Color.clear.frame(height: screenHeight * 0.4)

                            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                                VStack(spacing: 0) {
                                    cardRow(
                                        card,
                                        proxy: proxy,
                                        level: level,
                                        parent: parent,
                                        columnCards: cards
                                    )
                                        .background(
                                            Group {
                                                if observedCardIDs.contains(card.id) {
                                                    GeometryReader { geometry in
                                                        Color.clear.preference(
                                                            key: MainColumnCardFramePreferenceKey.self,
                                                            value: [
                                                                card.id: geometry.frame(
                                                                    in: .named(mainColumnViewportCoordinateSpaceName(viewportKey))
                                                                )
                                                            ]
                                                        )
                                                    }
                                                }
                                            }
                                        )

                                    if index < cards.count - 1 {
                                        let next = cards[index + 1]
                                        if card.parent?.id != next.parent?.id {
                                            Rectangle()
                                                .fill(appearance == "light" ? Color.black.opacity(0.16) : Color.black.opacity(0.40))
                                                .frame(height: mainParentGroupSeparatorHeight)
                                                .padding(.horizontal, 14)
                                        }
                                        Color.clear.frame(height: max(0, CGFloat(mainCardVerticalGap)))
                                    }
                                }
                            }

                            Color.clear.frame(height: screenHeight * 0.7)
                        }
                    }
                    .coordinateSpace(name: mainColumnViewportCoordinateSpaceName(viewportKey))
                    .onPreferenceChange(MainColumnCardFramePreferenceKey.self) { frames in
                        mainColumnObservedCardFramesByKey[viewportKey] = frames
                        mainCanvasScrollCoordinator.updateObservedFrames(frames, for: viewportKey)
                    }
                    .padding(.horizontal, MainCanvasLayoutMetrics.columnHorizontalPadding)
                    .frame(width: columnWidth)
                    .background(
                        mainColumnScrollObserver(
                            viewportKey: viewportKey,
                            level: level,
                            parent: parent,
                            cards: cards,
                            viewportHeight: screenHeight
                        )
                    )
                }
                .onChange(of: mainCanvasScrollCoordinator.navigationIntentTick) { _, _ in
                    handleMainColumnNavigationIntent(
                        viewportKey: viewportKey,
                        cards: cards,
                        level: level,
                        parent: parent,
                        proxy: proxy,
                        viewportHeight: screenHeight
                    )
                }
                .onChange(of: activeCardID) { _, newID in
                    guard pendingMainClickFocusTargetID == newID else { return }
                    handleMainColumnActiveFocusChange(
                        viewportKey: viewportKey,
                        newActiveID: newID,
                        cards: cards,
                        level: level,
                        parent: parent,
                        proxy: proxy,
                        viewportHeight: screenHeight,
                        trigger: "clickFocus"
                    )
                    DispatchQueue.main.async {
                        if pendingMainClickFocusTargetID == newID {
                            pendingMainClickFocusTargetID = nil
                        }
                    }
                }
                .onChange(of: childListSignature) { _, _ in
                    guard !showFocusMode else { return }
                    guard acceptsKeyboardInput else { return }
                    guard editingCardID == nil else { return }
                    if pendingMainEditingSiblingNavigationTargetID == activeCardID {
                        return
                    }
                    cancelPendingMainColumnFocusWorkItem(for: viewportKey)
                    cancelPendingMainColumnFocusVerificationWorkItem(for: viewportKey)
                    if shouldPreserveMainColumnViewportOnReveal(level: level, storageKey: viewportKey, newActiveID: activeCardID) {
                        return
                    }
                    guard shouldAutoAlignMainColumn(cards: cards, activeID: activeCardID) else { return }
                    _ = publishMainColumnNavigationIntent(
                        kind: .childListChange,
                        scope: .viewport(viewportKey),
                        targetCardID: activeCardID,
                        expectedActiveCardID: activeCardID,
                        animated: false,
                        trigger: "childListChange"
                    )
                }
                .onAppear {
                    guard !showFocusMode else { return }
                    guard acceptsKeyboardInput else { return }
                    guard editingCardID == nil else { return }
                    if pendingMainEditingSiblingNavigationTargetID == activeCardID {
                        return
                    }
                    cancelPendingMainColumnFocusWorkItem(for: viewportKey)
                    cancelPendingMainColumnFocusVerificationWorkItem(for: viewportKey)
                    if shouldPreserveMainColumnViewportOnReveal(level: level, storageKey: viewportKey, newActiveID: activeCardID) {
                        return
                    }
                    guard shouldAutoAlignMainColumn(cards: cards, activeID: activeCardID) else { return }
                    _ = publishMainColumnNavigationIntent(
                        kind: .columnAppear,
                        scope: .viewport(viewportKey),
                        targetCardID: activeCardID,
                        expectedActiveCardID: activeCardID,
                        animated: false,
                        trigger: "columnAppear"
                    )
                }
                .onChange(of: mainBottomRevealTick) { _, _ in
                    guard !showFocusMode else { return }
                    guard acceptsKeyboardInput else { return }
                    guard editingCardID == nil else { return }
                    if pendingMainEditingSiblingNavigationTargetID == activeCardID {
                        return
                    }
                    guard let requestedID = mainBottomRevealCardID else { return }
                    guard activeCardID == requestedID else { return }
                    guard cards.last?.id == requestedID else { return }
                    guard let requestedCard = findCard(by: requestedID) else { return }
                    let cardHeight = resolvedMainCardHeight(for: requestedCard)
                    guard cardHeight > screenHeight else { return }
                    _ = publishMainColumnNavigationIntent(
                        kind: .bottomReveal,
                        scope: .viewport(viewportKey),
                        targetCardID: requestedID,
                        expectedActiveCardID: requestedID,
                        animated: focusNavigationAnimationEnabled,
                        trigger: "mainBottomReveal"
                    )
                }
            }
            .contentShape(Rectangle())
            .contextMenu {
                indexBoardColumnContextMenu(level: level, parent: parent, cards: cards)
            }
            .onTapGesture { finishEditing(); isMainViewFocused = true }
        }
        .frame(width: columnWidth)
    }

    func scrollToFocus(
        in cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        keepVisibleOnly: Bool = false,
        editingRevealEdge: MainEditingViewportRevealEdge? = nil,
        forceAlignment: Bool = false,
        animated: Bool = true,
        reason: String = "unspecified",
        authority: MainVerticalScrollAuthority? = nil
    ) {
        guard acceptsKeyboardInput else { return }
        let requestKey = mainColumnScrollCacheKey(level: level, parent: parent)
        let viewportKey = mainColumnViewportStorageKey(level: level)
        guard isMainVerticalScrollAuthorityCurrent(authority, viewportKey: viewportKey) else { return }

        guard let idToScroll = resolvedMainColumnFocusTargetID(in: cards) else {
            bounceDebugLog(
                "scrollToFocus noTarget reason=\(reason) key=\(requestKey) viewportKey=\(viewportKey) " +
                "\(debugFocusStateSummary())"
            )
            mainColumnLastFocusRequestByKey.removeValue(forKey: requestKey)
            cancelPendingMainColumnFocusVerificationWorkItem(for: viewportKey)
            return
        }

        let currentOffsetY = resolvedMainColumnCurrentOffsetY(viewportKey: viewportKey)
        let targetLayout = resolvedMainColumnTargetLayout(
            in: cards,
            targetID: idToScroll,
            viewportHeight: viewportHeight
        )
        let targetHeight = targetLayout.map { $0.targetMaxY - $0.targetMinY }
            ?? findCard(by: idToScroll).map { resolvedMainCardHeight(for: $0) }
            ?? 0
        let prefersTopAnchor = targetHeight > viewportHeight
        let request = MainColumnFocusRequest(
            targetID: idToScroll,
            prefersTopAnchor: prefersTopAnchor,
            keepVisibleOnly: keepVisibleOnly,
            editingRevealEdge: editingRevealEdge,
            cardsCount: cards.count,
            firstCardID: cards.first?.id,
            lastCardID: cards.last?.id,
            viewportHeightBucket: Int(viewportHeight.rounded())
        )
        if !forceAlignment,
           mainColumnLastFocusRequestByKey[requestKey] == request {
            bounceDebugLog(
                "scrollToFocus skipped reason=\(reason) key=\(requestKey) viewportKey=\(viewportKey) " +
                "target=\(debugCardIDString(idToScroll)) offset=\(debugCGFloat(currentOffsetY)) " +
                "\(debugMainColumnEstimatedTargetSummary(targetLayout)) " +
                "\(debugMainColumnObservedTargetSummary(viewportKey: viewportKey, targetID: idToScroll, offsetY: currentOffsetY)) " +
                "visible=\(debugMainColumnVisibleCardSummary(viewportKey: viewportKey, cards: cards, viewportHeight: viewportHeight, offsetY: currentOffsetY))"
            )
            scheduleMainColumnFocusVerification(
                viewportKey: viewportKey,
                cards: cards,
                level: level,
                parent: parent,
                targetID: idToScroll,
                proxy: proxy,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor,
                keepVisibleOnly: keepVisibleOnly,
                editingRevealEdge: editingRevealEdge,
                animated: false,
                authority: authority
            )
            return
        }
        mainColumnLastFocusRequestByKey[requestKey] = request

        if keepVisibleOnly,
           isMainColumnFocusTargetVisible(
                viewportKey: viewportKey,
                cards: cards,
                targetID: idToScroll,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor
           ) {
            scheduleMainColumnFocusVerification(
                viewportKey: viewportKey,
                cards: cards,
                level: level,
                parent: parent,
                targetID: idToScroll,
                proxy: proxy,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor,
                keepVisibleOnly: true,
                editingRevealEdge: editingRevealEdge,
                animated: false,
                authority: authority
            )
            return
        }

        if !forceAlignment && shouldSkipMainColumnFocusScroll(
            targetID: idToScroll,
            cards: cards,
            level: level,
            viewportHeight: viewportHeight,
            prefersTopAnchor: prefersTopAnchor
        ) {
            bounceDebugLog(
                "scrollToFocus preserved reason=\(reason) key=\(requestKey) viewportKey=\(viewportKey) " +
                "target=\(debugCardIDString(idToScroll)) offset=\(debugCGFloat(currentOffsetY)) top=\(prefersTopAnchor) " +
                "\(debugMainColumnEstimatedTargetSummary(targetLayout)) " +
                "\(debugMainColumnObservedTargetSummary(viewportKey: viewportKey, targetID: idToScroll, offsetY: currentOffsetY))"
            )
            scheduleMainColumnFocusVerification(
                viewportKey: viewportKey,
                cards: cards,
                level: level,
                parent: parent,
                targetID: idToScroll,
                proxy: proxy,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor,
                keepVisibleOnly: keepVisibleOnly,
                editingRevealEdge: editingRevealEdge,
                animated: false,
                authority: authority
            )
            return
        }

        bounceDebugLog(
            "scrollToFocus reason=\(reason) key=\(requestKey) viewportKey=\(viewportKey) " +
            "target=\(debugCardToken(findCard(by: idToScroll))) height=\(debugCGFloat(targetHeight)) " +
            "viewport=\(debugCGFloat(viewportHeight)) offset=\(debugCGFloat(currentOffsetY)) " +
            "top=\(prefersTopAnchor) keepVisible=\(keepVisibleOnly) force=\(forceAlignment) edge=\(String(describing: editingRevealEdge)) animated=\(animated) " +
            "\(debugMainColumnEstimatedTargetSummary(targetLayout)) " +
            "\(debugMainColumnObservedTargetSummary(viewportKey: viewportKey, targetID: idToScroll, offsetY: currentOffsetY)) " +
            "visible=\(debugMainColumnVisibleCardSummary(viewportKey: viewportKey, cards: cards, viewportHeight: viewportHeight, offsetY: currentOffsetY))"
        )
        if keepVisibleOnly {
            applyMainColumnFocusVisibility(
                viewportKey: viewportKey,
                cards: cards,
                targetID: idToScroll,
                proxy: proxy,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor,
                editingRevealEdge: editingRevealEdge,
                animated: animated
            )
        } else {
            applyMainColumnFocusAlignment(
                viewportKey: viewportKey,
                cards: cards,
                targetID: idToScroll,
                proxy: proxy,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor,
                animated: animated
            )
        }
        scheduleMainColumnFocusVerification(
            viewportKey: viewportKey,
            cards: cards,
            level: level,
            parent: parent,
            targetID: idToScroll,
            proxy: proxy,
            viewportHeight: viewportHeight,
            prefersTopAnchor: prefersTopAnchor,
            keepVisibleOnly: keepVisibleOnly,
            editingRevealEdge: editingRevealEdge,
            animated: animated,
            authority: authority
        )
    }

    func handleMainColumnNavigationIntent(
        viewportKey: String,
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat
    ) {
        guard let intent = mainCanvasScrollCoordinator.consumeLatestIntent(for: viewportKey) else { return }

        switch intent.kind {
        case .focusChange:
            handleMainColumnActiveFocusChange(
                viewportKey: viewportKey,
                newActiveID: intent.expectedActiveCardID,
                cards: cards,
                level: level,
                parent: parent,
                proxy: proxy,
                viewportHeight: viewportHeight,
                trigger: intent.trigger,
                animatedOverride: intent.animated,
                intentID: intent.id
            )

        case .settleRecovery:
            handleMainColumnNavigationSettle(
                viewportKey: viewportKey,
                cards: cards,
                level: level,
                parent: parent,
                proxy: proxy,
                viewportHeight: viewportHeight
            )

        case .childListChange, .columnAppear:
            handleMainColumnImmediateAlignmentIntent(
                viewportKey: viewportKey,
                cards: cards,
                level: level,
                parent: parent,
                proxy: proxy,
                viewportHeight: viewportHeight,
                trigger: intent.trigger
            )

        case .bottomReveal:
            handleMainColumnBottomRevealIntent(
                viewportKey: viewportKey,
                cards: cards,
                proxy: proxy,
                viewportHeight: viewportHeight,
                requestedID: intent.targetCardID,
                animated: intent.animated,
                trigger: intent.trigger
            )
        }
    }

    func handleMainColumnImmediateAlignmentIntent(
        viewportKey: String,
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        trigger: String
    ) {
        guard !showFocusMode else { return }
        guard acceptsKeyboardInput else { return }
        guard editingCardID == nil else { return }
        cancelPendingMainColumnFocusWorkItem(for: viewportKey)
        cancelPendingMainColumnFocusVerificationWorkItem(for: viewportKey)
        if shouldPreserveMainColumnViewportOnReveal(level: level, storageKey: viewportKey, newActiveID: activeCardID) {
            return
        }
        guard shouldAutoAlignMainColumn(cards: cards, activeID: activeCardID) else { return }
        let authority = beginMainVerticalScrollAuthority(
            viewportKey: viewportKey,
            kind: .columnNavigation,
            targetCardID: activeCardID
        )
        bounceDebugLog(
            "\(trigger) level=\(level) viewportKey=\(viewportKey) " +
            "offset=\(debugCGFloat(mainColumnViewportOffsetByKey[viewportKey] ?? 0)) " +
            "visible=\(debugMainColumnVisibleCardSummary(viewportKey: viewportKey, cards: cards, viewportHeight: viewportHeight, offsetY: mainColumnViewportOffsetByKey[viewportKey] ?? 0))"
        )
        scrollToFocus(
            in: cards,
            level: level,
            parent: parent,
            proxy: proxy,
            viewportHeight: viewportHeight,
            animated: false,
            reason: trigger,
            authority: authority
        )
    }

    func handleMainColumnBottomRevealIntent(
        viewportKey: String,
        cards: [SceneCard],
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        requestedID: UUID?,
        animated: Bool,
        trigger: String
    ) {
        guard !showFocusMode else { return }
        guard acceptsKeyboardInput else { return }
        guard editingCardID == nil else { return }
        guard let requestedID else { return }
        guard activeCardID == requestedID else { return }
        guard cards.last?.id == requestedID else { return }
        guard let requestedCard = findCard(by: requestedID) else { return }
        let cardHeight = resolvedMainCardHeight(for: requestedCard)
        guard cardHeight > viewportHeight else { return }

        bounceDebugLog(
            "\(trigger) viewportKey=\(viewportKey) target=\(debugCardToken(requestedCard)) " +
            "offset=\(debugCGFloat(mainColumnViewportOffsetByKey[viewportKey] ?? 0)) height=\(debugCGFloat(cardHeight))"
        )
        _ = beginMainVerticalScrollAuthority(
            viewportKey: viewportKey,
            kind: .columnNavigation,
            targetCardID: requestedID
        )
        if performMainColumnNativeFocusScroll(
            viewportKey: viewportKey,
            cards: cards,
            targetID: requestedID,
            viewportHeight: viewportHeight,
            anchorY: 1.0,
            animated: animated
        ) {
            return
        }

        suspendMainColumnViewportCapture(for: animated ? 0.32 : 0.12)
        if animated {
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                axis: "vertical",
                engine: "proxy",
                animated: true,
                target: "\(viewportKey)|\(requestedID.uuidString)",
                expectedDuration: 0.24
            )
            withAnimation(quickEaseAnimation) {
                proxy.scrollTo(requestedID, anchor: .bottom)
            }
        } else {
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                axis: "vertical",
                engine: "proxy",
                animated: false,
                target: "\(viewportKey)|\(requestedID.uuidString)",
                expectedDuration: 0
            )
            performWithoutAnimation {
                proxy.scrollTo(requestedID, anchor: .bottom)
            }
        }
    }

    func handleMainColumnActiveFocusChange(
        viewportKey: String,
        newActiveID: UUID?,
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        trigger: String,
        animatedOverride: Bool? = nil,
        intentID: Int? = nil
    ) {
        guard !showFocusMode else { return }
        guard acceptsKeyboardInput else { return }
        guard editingCardID == nil else { return }
        cancelPendingMainColumnFocusWorkItem(for: viewportKey)
        cancelPendingMainColumnFocusVerificationWorkItem(for: viewportKey)
        let forceClickAlignment = trigger == "clickFocus"
        if !forceClickAlignment &&
            shouldPreserveMainColumnViewportOnReveal(level: level, storageKey: viewportKey, newActiveID: newActiveID) {
            return
        }

        let containsActiveCard = cards.contains { $0.id == newActiveID }
        let containsActiveAncestor = cards.contains { activeAncestorIDs.contains($0.id) }
        let containsPreferredDescendantTarget =
            !containsActiveCard &&
            !containsActiveAncestor &&
            resolvedMainColumnFocusTargetID(in: cards) != nil
        guard containsActiveCard || containsActiveAncestor || containsPreferredDescendantTarget else { return }

        let activeCardNeedsTopReveal = containsActiveCard && {
            guard let newActiveID, let targetCard = findCard(by: newActiveID) else { return false }
            return resolvedMainCardHeight(for: targetCard) > viewportHeight
        }()
        let editDrivenKeepVisible = containsActiveCard && pendingMainEditingViewportKeepVisibleCardID == newActiveID
        let editingRevealEdge = editDrivenKeepVisible ? pendingMainEditingViewportRevealEdge : nil
        if editDrivenKeepVisible {
            pendingMainEditingViewportKeepVisibleCardID = nil
            pendingMainEditingViewportRevealEdge = nil
        }
        let focusDelayOverride = containsPreferredDescendantTarget
            ? mainColumnDescendantFocusCoalescingDelay
            : nil
        let shouldAnimate = containsPreferredDescendantTarget
            ? false
            : (animatedOverride ?? (
                focusNavigationAnimationEnabled &&
                !shouldSuppressMainArrowRepeatAnimation()
            ))
        let authority = beginMainVerticalScrollAuthority(
            viewportKey: viewportKey,
            kind: editDrivenKeepVisible ? .editingTransition : .columnNavigation,
            targetCardID: newActiveID
        )

        bounceDebugLog(
            "\(trigger) level=\(level) viewportKey=\(viewportKey) " +
            "newID=\(newActiveID?.uuidString ?? "nil") activeColumn=\(containsActiveCard) " +
            "ancestorColumn=\(containsActiveAncestor) descendantColumn=\(containsPreferredDescendantTarget) topReveal=\(activeCardNeedsTopReveal) " +
            "editKeepVisible=\(editDrivenKeepVisible) forceClick=\(forceClickAlignment) animate=\(shouldAnimate) " +
            "offset=\(debugCGFloat(mainColumnViewportOffsetByKey[viewportKey] ?? 0)) " +
            "visible=\(debugMainColumnVisibleCardSummary(viewportKey: viewportKey, cards: cards, viewportHeight: viewportHeight, offsetY: mainColumnViewportOffsetByKey[viewportKey] ?? 0))"
        )
        scheduleMainColumnActiveCardFocus(
            viewportKey: viewportKey,
            expectedActiveID: newActiveID,
            cards: cards,
            level: level,
            parent: parent,
            proxy: proxy,
            viewportHeight: viewportHeight,
            keepVisibleOnly: editDrivenKeepVisible,
            editingRevealEdge: editingRevealEdge,
            forceAlignment: forceClickAlignment,
            animated: shouldAnimate,
            focusDelayOverride: focusDelayOverride,
            intentID: intentID,
            authority: authority
        )
    }

    func resolvedMainColumnCurrentOffsetY(viewportKey: String) -> CGFloat {
        if let liveOffset = mainCanvasScrollCoordinator
            .scrollView(for: viewportKey)?
            .documentVisibleRect
            .origin
            .y
        {
            return liveOffset
        }
        return mainColumnViewportOffsetByKey[viewportKey] ?? 0
    }

    func resolvedMainColumnFocusTargetOffset(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat,
        anchorY: CGFloat
    ) -> CGFloat? {
        let frame =
            observedMainColumnTargetFrame(
                viewportKey: viewportKey,
                targetID: targetID
            ) ??
            predictedMainColumnTargetFrame(
                cards: cards,
                targetID: targetID,
                viewportHeight: viewportHeight
            )
        guard let frame else {
            return nil
        }

        let clampedAnchorY = min(max(0, anchorY), 1)
        let targetAnchorY = frame.minY + (frame.height * clampedAnchorY)
        return targetAnchorY - (viewportHeight * clampedAnchorY)
    }

    func resolvedMainColumnVisibleRect(
        viewportKey: String,
        viewportHeight: CGFloat
    ) -> CGRect {
        if let visibleRect = mainCanvasScrollCoordinator
            .scrollView(for: viewportKey)?
            .documentVisibleRect
        {
            return visibleRect
        }

        return CGRect(
            x: 0,
            y: resolvedMainColumnCurrentOffsetY(viewportKey: viewportKey),
            width: 1,
            height: viewportHeight
        )
    }

    func predictedMainColumnTargetFrame(
        cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat
    ) -> CGRect? {
        guard let layout = resolvedMainColumnTargetLayout(
            in: cards,
            targetID: targetID,
            viewportHeight: viewportHeight
        ) else {
            return nil
        }
        return CGRect(
            x: 0,
            y: layout.targetMinY,
            width: 1,
            height: layout.targetMaxY - layout.targetMinY
        )
    }

    func observedMainColumnTargetFrame(
        viewportKey: String,
        targetID: UUID
    ) -> CGRect? {
        mainCanvasScrollCoordinator.observedFrame(for: viewportKey, cardID: targetID)
    }

    func isObservedMainColumnFocusTargetVisible(
        viewportKey: String,
        targetID: UUID,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool
    ) -> Bool {
        guard let frame = observedMainColumnTargetFrame(
            viewportKey: viewportKey,
            targetID: targetID
        ) else {
            return false
        }

        let visibleRect = resolvedMainColumnVisibleRect(
            viewportKey: viewportKey,
            viewportHeight: viewportHeight
        )
        let visibleMinY = frame.minY - visibleRect.origin.y
        let visibleMaxY = frame.maxY - visibleRect.origin.y
        if prefersTopAnchor {
            return abs(visibleMinY) <= 24 && visibleMaxY > 24
        }

        let inset = min(24, visibleRect.height * 0.15)
        return visibleMaxY > inset && visibleMinY < (visibleRect.height - inset)
    }

    func isObservedMainColumnFocusTargetAligned(
        viewportKey: String,
        targetID: UUID,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool
    ) -> Bool {
        guard let frame = observedMainColumnTargetFrame(
            viewportKey: viewportKey,
            targetID: targetID
        ) else {
            return false
        }

        let visibleRect = resolvedMainColumnVisibleRect(
            viewportKey: viewportKey,
            viewportHeight: viewportHeight
        )
        let anchorY: CGFloat = prefersTopAnchor ? 0 : 0.4
        let visibleAnchorY = (frame.minY + (frame.height * anchorY)) - visibleRect.origin.y
        let desiredAnchorY = visibleRect.height * anchorY
        let tolerance: CGFloat = prefersTopAnchor ? 16 : 22
        return abs(visibleAnchorY - desiredAnchorY) <= tolerance
    }

    @discardableResult
    func performMainColumnNativeFocusScroll(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat,
        anchorY: CGFloat,
        animated: Bool
    ) -> Bool {
        guard observedMainColumnTargetFrame(
            viewportKey: viewportKey,
            targetID: targetID
        ) != nil else {
            return false
        }
        guard let scrollView = mainCanvasScrollCoordinator.scrollView(for: viewportKey) else {
            return false
        }
        let visible = scrollView.documentVisibleRect
        let resolvedViewportHeight = max(1, visible.height)
        guard let targetOffsetY = resolvedMainColumnFocusTargetOffset(
            viewportKey: viewportKey,
            cards: cards,
            targetID: targetID,
            viewportHeight: resolvedViewportHeight,
            anchorY: anchorY
        ) else {
            return false
        }

        let documentHeight = scrollView.documentView?.bounds.height ?? 0
        let maxY = max(0, documentHeight - visible.height)
        let targetReachable = maxY + 0.5 >= targetOffsetY

        if animated {
            guard targetReachable || targetOffsetY <= 0.5 else { return false }
            let resolvedTargetY = CaretScrollCoordinator.resolvedVerticalTargetY(
                visibleRect: visible,
                targetY: targetOffsetY,
                minY: 0,
                maxY: maxY,
                snapToPixel: true
            )
            guard abs(resolvedTargetY - visible.origin.y) > 0.5 else { return true }
            let appliedDuration = CaretScrollCoordinator.resolvedVerticalAnimationDuration(
                currentY: visible.origin.y,
                targetY: resolvedTargetY,
                viewportHeight: resolvedViewportHeight
            )
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                axis: "vertical",
                engine: "native",
                animated: true,
                target: "\(viewportKey)|\(targetID.uuidString)",
                expectedDuration: appliedDuration
            )
            suspendMainColumnViewportCapture(for: appliedDuration + 0.06)
            _ = CaretScrollCoordinator.applyAnimatedVerticalScrollIfNeeded(
                scrollView: scrollView,
                visibleRect: visible,
                targetY: targetOffsetY,
                minY: 0,
                maxY: maxY,
                deadZone: 0.5,
                snapToPixel: true,
                duration: appliedDuration
            )
            bounceDebugLog(
                "nativeMainColumnFocusScroll key=\(viewportKey) target=\(debugCardIDString(targetID)) " +
                "targetY=\(debugCGFloat(resolvedTargetY)) visibleY=\(debugCGFloat(visible.origin.y)) " +
                "duration=\(String(format: "%.2f", appliedDuration)) viewport=\(debugCGFloat(resolvedViewportHeight))"
            )
            return true
        }

        MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
            ownerKey: mainCanvasDiagnosticsOwnerKey,
            axis: "vertical",
            engine: "native",
            animated: false,
            target: "\(viewportKey)|\(targetID.uuidString)",
            expectedDuration: 0
        )
        suspendMainColumnViewportCapture(for: 0.12)
        let applied = CaretScrollCoordinator.applyVerticalScrollIfNeeded(
            scrollView: scrollView,
            visibleRect: visible,
            targetY: targetOffsetY,
            minY: 0,
            maxY: maxY,
            deadZone: 0.5,
            snapToPixel: true
        )
        if applied {
            bounceDebugLog(
                "nativeMainColumnFocusScroll immediate key=\(viewportKey) target=\(debugCardIDString(targetID)) " +
                "targetY=\(debugCGFloat(targetOffsetY)) visibleY=\(debugCGFloat(visible.origin.y))"
            )
        }
        let resolvedTargetY = CaretScrollCoordinator.resolvedVerticalTargetY(
            visibleRect: visible,
            targetY: targetOffsetY,
            minY: 0,
            maxY: maxY,
            snapToPixel: true
        )
        let currentY = scrollView.contentView.bounds.origin.y
        return targetReachable && abs(resolvedTargetY - currentY) <= 0.5
    }

    func shouldSkipMainColumnFocusScroll(
        targetID: UUID,
        cards: [SceneCard],
        level: Int,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool
    ) -> Bool {
        guard prefersTopAnchor else { return false }
        guard activeCardID == targetID else { return false }
        let viewportKey = mainColumnViewportStorageKey(level: level)
        guard let frame = observedMainColumnTargetFrame(
            viewportKey: viewportKey,
            targetID: targetID
        ) else {
            return false
        }

        let visibleRect = resolvedMainColumnVisibleRect(
            viewportKey: viewportKey,
            viewportHeight: viewportHeight
        )
        let deadZone: CGFloat = 3
        let delta = frame.minY - visibleRect.origin.y
        let shouldSkip = abs(delta) <= deadZone
        if shouldSkip {
            bounceDebugLog(
                "shouldSkipMainColumnFocusScroll target=\(debugCardIDString(targetID)) viewportKey=\(viewportKey) " +
                "offset=\(debugCGFloat(visibleRect.origin.y)) targetMin=\(debugCGFloat(frame.minY)) " +
                "delta=\(debugCGFloat(delta)) " +
                "\(debugMainColumnObservedTargetSummary(viewportKey: viewportKey, targetID: targetID, offsetY: visibleRect.origin.y))"
            )
        }
        return shouldSkip
    }

    func shouldAutoAlignMainColumn(cards: [SceneCard], activeID: UUID?) -> Bool {
        guard let activeID else { return false }
        if cards.contains(where: { $0.id == activeID }) {
            return true
        }
        if cards.contains(where: { activeAncestorIDs.contains($0.id) }) {
            return true
        }
        return resolvedMainColumnFocusTargetID(in: cards) != nil
    }

    func resolvedMainColumnLayoutSnapshot(
        in cards: [SceneCard],
        viewportHeight: CGFloat
    ) -> MainColumnLayoutSnapshot {
        let layoutResolveStartedAt = CACurrentMediaTime()
        let cardIDs = cards.map(\.id)
        let editingCardInColumn = editingCardID.flatMap { editingID in
            cards.first(where: { $0.id == editingID })
        }
        let editingLiveHeightOverride = editingCardInColumn.flatMap { card in
            resolvedMainCardLiveEditingHeightOverride(for: card)
        }
        let editingHeightBucket = editingLiveHeightOverride.map { Int(($0 * 10).rounded()) } ?? -1
        let layoutKey = MainColumnLayoutCacheKey(
            recordsVersion: scenario.cardsVersion,
            contentVersion: scenario.cardContentSaveVersion,
            viewportHeightBucket: Int(viewportHeight.rounded()),
            fontSizeBucket: Int((fontSize * 10).rounded()),
            lineSpacingBucket: Int((mainCardLineSpacingValue * 10).rounded()),
            editingCardID: editingCardInColumn?.id,
            editingHeightBucket: editingHeightBucket,
            cardIDs: cardIDs
        )
        let containsEditingCard = editingCardInColumn != nil
        if let cached = mainColumnLayoutSnapshotByKey[layoutKey] {
            MainCanvasNavigationDiagnostics.shared.recordColumnLayoutResolve(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                cardCount: cards.count,
                viewportHeight: viewportHeight,
                cacheHit: true,
                containsEditingCard: containsEditingCard,
                durationMilliseconds: (CACurrentMediaTime() - layoutResolveStartedAt) * 1000
            )
            return cached
        }

        let centerGapHeight = max(0, CGFloat(mainCardVerticalGap))
        var cursorY = viewportHeight * 0.4
        var framesByCardID: [UUID: MainColumnLayoutFrame] = [:]
        framesByCardID.reserveCapacity(cards.count)

        for index in cards.indices {
            let card = cards[index]
            let cardHeight = resolvedMainCardHeight(
                for: card,
                liveEditingHeightOverride: card.id == editingCardInColumn?.id ? editingLiveHeightOverride : nil
            )
            let cardMinY = cursorY
            let cardMaxY = cardMinY + cardHeight
            framesByCardID[card.id] = MainColumnLayoutFrame(minY: cardMinY, maxY: cardMaxY)

            cursorY = cardMaxY
            if index < cards.count - 1 {
                let next = cards[index + 1]
                if card.parent?.id != next.parent?.id {
                    cursorY += mainParentGroupSeparatorHeight
                }
                cursorY += centerGapHeight
            }
        }

        let snapshot = MainColumnLayoutSnapshot(
            key: layoutKey,
            framesByCardID: framesByCardID,
            orderedCardIDs: cardIDs,
            contentBottomY: cursorY
        )
        mainColumnLayoutSnapshotByKey[layoutKey] = snapshot
        MainCanvasNavigationDiagnostics.shared.recordColumnLayoutResolve(
            ownerKey: mainCanvasDiagnosticsOwnerKey,
            cardCount: cards.count,
            viewportHeight: viewportHeight,
            cacheHit: false,
            containsEditingCard: containsEditingCard,
            durationMilliseconds: (CACurrentMediaTime() - layoutResolveStartedAt) * 1000
        )
        return snapshot
    }

    func resolvedMainColumnTargetLayout(
        in cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat
    ) -> (targetMinY: CGFloat, targetMaxY: CGFloat)? {
        guard let frame = resolvedMainColumnLayoutSnapshot(in: cards, viewportHeight: viewportHeight)
            .framesByCardID[targetID] else { return nil }
        return (frame.minY, frame.maxY)
    }

    func mainColumnScrollCacheKey(level: Int, parent: SceneCard?) -> String {
        let parentKey = parent?.id.uuidString ?? "root"
        return "\(level)|\(parentKey)"
    }

    @ViewBuilder
    func mainColumnScrollObserver(
        viewportKey: String,
        level: Int,
        parent: SceneCard?,
        cards: [SceneCard],
        viewportHeight: CGFloat
    ) -> some View {
        MainColumnScrollViewAccessor(
            scrollCoordinator: mainCanvasScrollCoordinator,
            columnKey: viewportKey,
            storedOffsetY: mainColumnViewportOffsetByKey[viewportKey]
        ) { originY in
            guard !showFocusMode else { return }
            let previous = mainColumnViewportOffsetByKey[viewportKey] ?? 0
            let suspended = Date() < mainColumnViewportCaptureSuspendedUntil
            let visibleSummary = debugMainColumnVisibleCardSummary(
                viewportKey: viewportKey,
                cards: cards,
                viewportHeight: viewportHeight,
                offsetY: originY
            )
            if suspended, abs(previous - originY) > 0.5 {
                bounceDebugLog(
                    "viewportOffset ignored level=\(level) key=\(viewportKey) requestKey=\(mainColumnScrollCacheKey(level: level, parent: parent)) " +
                    "prev=\(debugCGFloat(previous)) new=\(debugCGFloat(originY)) " +
                    "suspendedUntil=\(mainColumnViewportCaptureSuspendedUntil.timeIntervalSince1970) " +
                    "\(debugFocusStateSummary()) visible=\(visibleSummary)"
                )
                return
            }
            if abs(previous - originY) > 0.5 {
                mainColumnViewportOffsetByKey[viewportKey] = originY
                bounceDebugLog(
                    "viewportOffset level=\(level) key=\(viewportKey) requestKey=\(mainColumnScrollCacheKey(level: level, parent: parent)) " +
                    "prev=\(debugCGFloat(previous)) new=\(debugCGFloat(originY)) " +
                    "\(debugFocusStateSummary()) visible=\(visibleSummary)"
                )
            }
        }
    }

    func suspendMainColumnViewportCapture(for duration: TimeInterval) {
        let previous = mainColumnViewportCaptureSuspendedUntil
        let until = Date().addingTimeInterval(duration)
        if until > mainColumnViewportCaptureSuspendedUntil {
            mainColumnViewportCaptureSuspendedUntil = until
            bounceDebugLog(
                "suspendMainColumnViewportCapture duration=\(String(format: "%.2f", duration)) " +
                "previousUntil=\(previous.timeIntervalSince1970) newUntil=\(until.timeIntervalSince1970) " +
                "\(debugFocusStateSummary())"
            )
        }
    }

    func mainColumnViewportStorageKey(level: Int) -> String {
        if level <= 1 || isActiveCardRoot {
            return "level:\(level)|all"
        }
        let category = activeCategory ?? "all"
        return "level:\(level)|category:\(category)"
    }

    func shouldPreserveMainColumnViewportOnReveal(level: Int, storageKey: String, newActiveID: UUID?) -> Bool {
        guard level > 1 else { return false }
        guard (mainColumnViewportOffsetByKey[storageKey] ?? 0) > 1 else { return false }
        guard mainColumnViewportRestoreUntil > Date() else { return false }
        guard !shouldSuppressMainArrowRepeatAnimation() else { return false }
        guard let newActiveID, scenario.rootCards.contains(where: { $0.id == newActiveID }) else { return false }
        bounceDebugLog(
            "preserveMainColumnViewportOnReveal level=\(level) key=\(storageKey) " +
            "offset=\(debugCGFloat(mainColumnViewportOffsetByKey[storageKey] ?? 0)) " +
            "restoreUntil=\(mainColumnViewportRestoreUntil.timeIntervalSince1970) newActive=\(debugCardIDString(newActiveID)) " +
            "\(debugFocusStateSummary())"
        )
        return true
    }

    func shouldSuppressMainArrowRepeatAnimation() -> Bool {
        mainArrowRepeatAnimationSuppressedUntil > Date()
    }

    func cancelPendingMainColumnFocusWorkItem(for viewportKey: String) {
        if mainColumnPendingFocusWorkItemByKey[viewportKey] != nil {
            bounceDebugLog("cancelPendingMainColumnFocusWorkItem key=\(viewportKey)")
        }
        mainColumnPendingFocusWorkItemByKey[viewportKey]?.cancel()
        mainColumnPendingFocusWorkItemByKey[viewportKey] = nil
    }

    func cancelPendingMainColumnFocusVerificationWorkItem(for viewportKey: String) {
        if mainColumnPendingFocusVerificationWorkItemByKey[viewportKey] != nil {
            bounceDebugLog("cancelPendingMainColumnFocusVerificationWorkItem key=\(viewportKey)")
        }
        mainColumnPendingFocusVerificationWorkItemByKey[viewportKey]?.cancel()
        mainColumnPendingFocusVerificationWorkItemByKey[viewportKey] = nil
    }

    func cancelAllPendingMainColumnFocusWork() {
        let viewportKeys = Set(mainColumnPendingFocusWorkItemByKey.keys)
            .union(mainColumnPendingFocusVerificationWorkItemByKey.keys)
        for viewportKey in viewportKeys {
            cancelPendingMainColumnFocusWorkItem(for: viewportKey)
            cancelPendingMainColumnFocusVerificationWorkItem(for: viewportKey)
        }
        mainColumnLastFocusRequestByKey.removeAll(keepingCapacity: true)
    }

    func resolvedMainColumnFocusTargetID(in cards: [SceneCard]) -> UUID? {
        if let id = activeCardID, cards.contains(where: { $0.id == id }) {
            return id
        }
        if let target = cards.first(where: { activeAncestorIDs.contains($0.id) }) {
            return target.id
        }
        if let activeID = activeCardID,
           let activeCard = findCard(by: activeID) {
            return resolvedMainColumnPreferredDescendantTargetID(in: cards, startingFrom: activeCard)
        }
        return nil
    }

    private func resolvedMainColumnPreferredDescendantTargetID(
        in cards: [SceneCard],
        startingFrom root: SceneCard
    ) -> UUID? {
        let visibleCardIDs = Set(cards.map(\.id))
        var current: SceneCard? = root
        var visited: Set<UUID> = []

        while let node = current, visited.insert(node.id).inserted {
            let children = node.children
            guard !children.isEmpty else { return nil }

            let preferredChild =
                children.first(where: { $0.id == node.lastSelectedChildID })
                ?? children.first

            guard let preferredChild else { return nil }
            if visibleCardIDs.contains(preferredChild.id) {
                return preferredChild.id
            }
            current = preferredChild
        }

        return nil
    }

    func isMainColumnFocusTargetVisible(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool
    ) -> Bool {
        _ = cards
        return isObservedMainColumnFocusTargetVisible(
            viewportKey: viewportKey,
            targetID: targetID,
            viewportHeight: viewportHeight,
            prefersTopAnchor: prefersTopAnchor
        )
    }

    func isMainColumnFocusTargetAligned(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool
    ) -> Bool {
        _ = cards
        return isObservedMainColumnFocusTargetAligned(
            viewportKey: viewportKey,
            targetID: targetID,
            viewportHeight: viewportHeight,
            prefersTopAnchor: prefersTopAnchor
        )
    }

    func applyMainColumnFocusAlignment(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool,
        animated: Bool
    ) {
        let defaultAnchor = UnitPoint(x: 0.5, y: 0.4)
        let focusAnchor = prefersTopAnchor ? UnitPoint(x: 0.5, y: 0.0) : defaultAnchor
        let focusAnchorY = prefersTopAnchor ? CGFloat(0) : CGFloat(defaultAnchor.y)

        if performMainColumnNativeFocusScroll(
            viewportKey: viewportKey,
            cards: cards,
            targetID: targetID,
            viewportHeight: viewportHeight,
            anchorY: focusAnchorY,
            animated: animated
        ) {
            return
        }

        suspendMainColumnViewportCapture(for: animated ? 0.32 : 0.12)
        if animated {
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                axis: "vertical",
                engine: "proxy",
                animated: true,
                target: "\(viewportKey)|\(targetID.uuidString)",
                expectedDuration: 0.24
            )
            withAnimation(quickEaseAnimation) {
                proxy.scrollTo(targetID, anchor: focusAnchor)
            }
        } else {
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                axis: "vertical",
                engine: "proxy",
                animated: false,
                target: "\(viewportKey)|\(targetID.uuidString)",
                expectedDuration: 0
            )
            performWithoutAnimation {
                proxy.scrollTo(targetID, anchor: focusAnchor)
            }
        }
    }

    func resolvedMainColumnVisibilityTargetOffset(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool,
        editingRevealEdge: MainEditingViewportRevealEdge?
    ) -> CGFloat? {
        let frame =
            observedMainColumnTargetFrame(
                viewportKey: viewportKey,
                targetID: targetID
            ) ??
            predictedMainColumnTargetFrame(
                cards: cards,
                targetID: targetID,
                viewportHeight: viewportHeight
            )
        guard let frame else { return nil }

        let visibleRect = resolvedMainColumnVisibleRect(
            viewportKey: viewportKey,
            viewportHeight: viewportHeight
        )
        let inset = min(28, visibleRect.height * 0.08)
        let mainEditingCaretBottomPadding: CGFloat = 120
        if let editingRevealEdge {
            switch editingRevealEdge {
            case .top:
                // Entering a card at its start should only reveal the first line,
                // not snap the whole tall card to the top of the viewport.
                return max(0, frame.minY - (visibleRect.height - inset))
            case .bottom:
                // Match the main editor caret-visibility bottom padding so the
                // card-level reveal and the follow-up caret ensure resolve to
                // the same resting offset instead of causing a second nudge.
                return max(0, frame.maxY - (visibleRect.height - mainEditingCaretBottomPadding))
            }
        }
        if prefersTopAnchor {
            return max(0, frame.minY)
        }
        if frame.minY < visibleRect.minY + inset {
            return max(0, frame.minY - inset)
        }
        if frame.maxY > visibleRect.maxY - inset {
            return frame.maxY - (visibleRect.height - inset)
        }
        return visibleRect.origin.y
    }

    @discardableResult
    func performMainColumnNativeVisibilityScroll(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool,
        editingRevealEdge: MainEditingViewportRevealEdge?,
        animated: Bool
    ) -> Bool {
        guard observedMainColumnTargetFrame(
            viewportKey: viewportKey,
            targetID: targetID
        ) != nil else {
            return false
        }
        guard let scrollView = mainCanvasScrollCoordinator.scrollView(for: viewportKey) else {
            return false
        }
        let visible = scrollView.documentVisibleRect
        let resolvedViewportHeight = max(1, visible.height)
        guard let targetOffsetY = resolvedMainColumnVisibilityTargetOffset(
            viewportKey: viewportKey,
            cards: cards,
            targetID: targetID,
            viewportHeight: resolvedViewportHeight,
            prefersTopAnchor: prefersTopAnchor,
            editingRevealEdge: editingRevealEdge
        ) else {
            return false
        }

        let documentHeight = scrollView.documentView?.bounds.height ?? 0
        let maxY = max(0, documentHeight - visible.height)
        let targetReachable = maxY + 0.5 >= targetOffsetY

        if animated {
            guard targetReachable || targetOffsetY <= 0.5 else { return false }
            let resolvedTargetY = CaretScrollCoordinator.resolvedVerticalTargetY(
                visibleRect: visible,
                targetY: targetOffsetY,
                minY: 0,
                maxY: maxY,
                snapToPixel: true
            )
            guard abs(resolvedTargetY - visible.origin.y) > 0.5 else { return true }
            let appliedDuration = CaretScrollCoordinator.resolvedVerticalAnimationDuration(
                currentY: visible.origin.y,
                targetY: resolvedTargetY,
                viewportHeight: resolvedViewportHeight
            )
            suspendMainColumnViewportCapture(for: appliedDuration + 0.06)
            _ = CaretScrollCoordinator.applyAnimatedVerticalScrollIfNeeded(
                scrollView: scrollView,
                visibleRect: visible,
                targetY: targetOffsetY,
                minY: 0,
                maxY: maxY,
                deadZone: 0.5,
                snapToPixel: true,
                duration: appliedDuration
            )
            return true
        }

        suspendMainColumnViewportCapture(for: 0.12)
        _ = CaretScrollCoordinator.applyVerticalScrollIfNeeded(
            scrollView: scrollView,
            visibleRect: visible,
            targetY: targetOffsetY,
            minY: 0,
            maxY: maxY,
            deadZone: 0.5,
            snapToPixel: true
        )
        let resolvedTargetY = CaretScrollCoordinator.resolvedVerticalTargetY(
            visibleRect: visible,
            targetY: targetOffsetY,
            minY: 0,
            maxY: maxY,
            snapToPixel: true
        )
        let currentY = scrollView.contentView.bounds.origin.y
        return targetReachable && abs(resolvedTargetY - currentY) <= 0.5
    }

    func applyMainColumnFocusVisibility(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool,
        editingRevealEdge: MainEditingViewportRevealEdge?,
        animated: Bool
    ) {
        if performMainColumnNativeVisibilityScroll(
            viewportKey: viewportKey,
            cards: cards,
            targetID: targetID,
            viewportHeight: viewportHeight,
            prefersTopAnchor: prefersTopAnchor,
            editingRevealEdge: editingRevealEdge,
            animated: animated
        ) {
            return
        }

        let visibleRect = resolvedMainColumnVisibleRect(
            viewportKey: viewportKey,
            viewportHeight: viewportHeight
        )
        let frame =
            observedMainColumnTargetFrame(
                viewportKey: viewportKey,
                targetID: targetID
            ) ??
            predictedMainColumnTargetFrame(
                cards: cards,
                targetID: targetID,
                viewportHeight: viewportHeight
            )
        guard let frame else { return }

        let inset = min(28, visibleRect.height * 0.08)
        let anchor: UnitPoint
        if let editingRevealEdge {
            anchor = editingRevealEdge == .top ? .top : .bottom
        } else {
            let useTopAnchor = prefersTopAnchor || frame.minY < visibleRect.minY + inset
            anchor = useTopAnchor ? .top : .bottom
        }

        suspendMainColumnViewportCapture(for: animated ? 0.32 : 0.12)
        if animated {
            withAnimation(quickEaseAnimation) {
                proxy.scrollTo(targetID, anchor: anchor)
            }
        } else {
            performWithoutAnimation {
                proxy.scrollTo(targetID, anchor: anchor)
            }
        }
    }

    func scheduleMainColumnFocusVerification(
        viewportKey: String,
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        targetID: UUID,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool,
        keepVisibleOnly: Bool,
        editingRevealEdge: MainEditingViewportRevealEdge?,
        animated: Bool,
        attempt: Int = 0,
        authority: MainVerticalScrollAuthority? = nil
    ) {
        cancelPendingMainColumnFocusVerificationWorkItem(for: viewportKey)
        let delay: TimeInterval
        if animated {
            delay = attempt == 0 ? 0.18 : 0.10
        } else {
            delay = attempt == 0 ? 0.05 : 0.08
        }
        let requestKey = mainColumnScrollCacheKey(level: level, parent: parent)
        var verificationWorkItem: DispatchWorkItem?
        verificationWorkItem = DispatchWorkItem {
            defer {
                if let verificationWorkItem,
                   mainColumnPendingFocusVerificationWorkItemByKey[viewportKey] === verificationWorkItem {
                    mainColumnPendingFocusVerificationWorkItemByKey[viewportKey] = nil
                }
            }

            guard !showFocusMode else { return }
            guard acceptsKeyboardInput else { return }
            guard isMainVerticalScrollAuthorityCurrent(authority, viewportKey: viewportKey) else { return }
            guard resolvedMainColumnFocusTargetID(in: cards) == targetID else { return }
            let hasObservedTargetFrame = observedMainColumnTargetFrame(
                viewportKey: viewportKey,
                targetID: targetID
            ) != nil
            let targetIsVisible = isMainColumnFocusTargetVisible(
                viewportKey: viewportKey,
                cards: cards,
                targetID: targetID,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor
            )
            let targetIsAligned = hasObservedTargetFrame && isMainColumnFocusTargetAligned(
                viewportKey: viewportKey,
                cards: cards,
                targetID: targetID,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor
            )
            if hasObservedTargetFrame && targetIsVisible && (keepVisibleOnly || targetIsAligned) {
                return
            }
            if !hasObservedTargetFrame {
                guard attempt < 4 else { return }
                scheduleMainColumnFocusVerification(
                    viewportKey: viewportKey,
                    cards: cards,
                    level: level,
                    parent: parent,
                    targetID: targetID,
                    proxy: proxy,
                    viewportHeight: viewportHeight,
                    prefersTopAnchor: prefersTopAnchor,
                    keepVisibleOnly: keepVisibleOnly,
                    editingRevealEdge: editingRevealEdge,
                    animated: animated,
                    attempt: attempt + 1,
                    authority: authority
                )
                return
            }

            bounceDebugLog(
                "verifyMainColumnFocus retry level=\(level) viewportKey=\(viewportKey) " +
                "attempt=\(attempt) target=\(debugCardIDString(targetID)) " +
                "observed=\(hasObservedTargetFrame) " +
                "offset=\(debugCGFloat(resolvedMainColumnCurrentOffsetY(viewportKey: viewportKey))) " +
                "\(debugMainColumnObservedTargetSummary(viewportKey: viewportKey, targetID: targetID, offsetY: resolvedMainColumnCurrentOffsetY(viewportKey: viewportKey)))"
            )
            mainColumnLastFocusRequestByKey.removeValue(forKey: requestKey)
            let retryAnimated = animated && hasObservedTargetFrame
            MainCanvasNavigationDiagnostics.shared.recordVerificationRetry(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                viewportKey: viewportKey,
                attempt: attempt,
                targetID: targetID,
                observedFrame: hasObservedTargetFrame,
                animatedRetry: retryAnimated
            )
            if keepVisibleOnly {
                applyMainColumnFocusVisibility(
                    viewportKey: viewportKey,
                    cards: cards,
                    targetID: targetID,
                    proxy: proxy,
                    viewportHeight: viewportHeight,
                    prefersTopAnchor: prefersTopAnchor,
                    editingRevealEdge: editingRevealEdge,
                    animated: retryAnimated
                )
            } else {
                applyMainColumnFocusAlignment(
                    viewportKey: viewportKey,
                    cards: cards,
                    targetID: targetID,
                    proxy: proxy,
                    viewportHeight: viewportHeight,
                    prefersTopAnchor: prefersTopAnchor,
                    animated: retryAnimated
                )
            }
            guard attempt < (hasObservedTargetFrame ? 2 : 4) else { return }
            scheduleMainColumnFocusVerification(
                viewportKey: viewportKey,
                cards: cards,
                level: level,
                parent: parent,
                targetID: targetID,
                proxy: proxy,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor,
                keepVisibleOnly: keepVisibleOnly,
                editingRevealEdge: editingRevealEdge,
                animated: animated,
                attempt: attempt + 1,
                authority: authority
            )
        }
        if let verificationWorkItem {
            mainColumnPendingFocusVerificationWorkItemByKey[viewportKey] = verificationWorkItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: verificationWorkItem)
        }
    }

    func handleMainColumnNavigationSettle(
        viewportKey: String,
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat
    ) {
        guard !showFocusMode else { return }
        guard acceptsKeyboardInput else { return }
        guard editingCardID == nil else { return }
        cancelPendingMainColumnFocusWorkItem(for: viewportKey)
        cancelPendingMainColumnFocusVerificationWorkItem(for: viewportKey)
        guard shouldAutoAlignMainColumn(cards: cards, activeID: activeCardID) else { return }
        let authority = beginMainVerticalScrollAuthority(
            viewportKey: viewportKey,
            kind: .columnNavigation,
            targetCardID: activeCardID
        )
        bounceDebugLog(
            "navigationSettle level=\(level) viewportKey=\(viewportKey) " +
            "active=\(debugCardIDString(activeCardID)) " +
            "offset=\(debugCGFloat(mainColumnViewportOffsetByKey[viewportKey] ?? 0)) " +
            "visible=\(debugMainColumnVisibleCardSummary(viewportKey: viewportKey, cards: cards, viewportHeight: viewportHeight, offsetY: mainColumnViewportOffsetByKey[viewportKey] ?? 0))"
        )
        scrollToFocus(
            in: cards,
            level: level,
            parent: parent,
            proxy: proxy,
            viewportHeight: viewportHeight,
            animated: false,
            reason: "navigationSettle",
            authority: authority
        )
    }

    func scheduleMainColumnActiveCardFocus(
        viewportKey: String,
        expectedActiveID: UUID?,
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        keepVisibleOnly: Bool,
        editingRevealEdge: MainEditingViewportRevealEdge?,
        forceAlignment: Bool,
        animated: Bool,
        focusDelayOverride: TimeInterval? = nil,
        intentID: Int? = nil,
        authority: MainVerticalScrollAuthority? = nil
    ) {
        cancelPendingMainColumnFocusWorkItem(for: viewportKey)
        bounceDebugLog(
            "scheduleMainColumnActiveCardFocus level=\(level) viewportKey=\(viewportKey) " +
            "expected=\(debugCardIDString(expectedActiveID)) parent=\(debugCardToken(parent)) " +
            "cards=\(cards.count) force=\(forceAlignment) animated=\(animated) " +
            "delay=\(debugCGFloat(focusDelayOverride ?? (animated ? 0.01 : 0.0))) \(debugFocusStateSummary())"
        )
        let focusDelay: TimeInterval = focusDelayOverride ?? (animated ? 0.01 : 0.0)
        let workItem = DispatchWorkItem {
            defer { mainColumnPendingFocusWorkItemByKey[viewportKey] = nil }
            bounceDebugLog(
                "executeMainColumnActiveCardFocus level=\(level) viewportKey=\(viewportKey) " +
                "expected=\(debugCardIDString(expectedActiveID)) current=\(debugCardIDString(activeCardID)) " +
                "\(debugFocusStateSummary())"
            )
            if let intentID,
               !mainCanvasScrollCoordinator.isIntentCurrent(intentID, for: viewportKey) {
                bounceDebugLog(
                    "activeCardFocus staleIntent level=\(level) viewportKey=\(viewportKey) intent=\(intentID)"
                )
                return
            }
            guard isMainVerticalScrollAuthorityCurrent(authority, viewportKey: viewportKey) else {
                bounceDebugLog(
                    "activeCardFocus staleAuthority level=\(level) viewportKey=\(viewportKey)"
                )
                return
            }
            guard activeCardID == expectedActiveID else {
                bounceDebugLog(
                    "activeCardFocus stale level=\(level) viewportKey=\(viewportKey) " +
                    "expected=\(expectedActiveID?.uuidString ?? "nil") current=\(activeCardID?.uuidString ?? "nil")"
                )
                return
            }
            scrollToFocus(
                in: cards,
                level: level,
                parent: parent,
                proxy: proxy,
                viewportHeight: viewportHeight,
                keepVisibleOnly: keepVisibleOnly,
                editingRevealEdge: editingRevealEdge,
                forceAlignment: forceAlignment,
                animated: animated,
                reason: "activeCardChange",
                authority: authority
            )
        }
        mainColumnPendingFocusWorkItemByKey[viewportKey] = workItem
        if focusDelay <= 0 {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + focusDelay, execute: workItem)
        }
    }

    func requestMainBottomRevealIfNeeded(
        currentLevel: [SceneCard],
        currentIndex: Int,
        card: SceneCard
    ) -> Bool {
        guard currentIndex == currentLevel.count - 1 else { return false }
        guard activeCardID == card.id else { return false }
        bounceDebugLog("requestMainBottomRevealIfNeeded target=\(debugCardToken(card)) levelCount=\(currentLevel.count)")
        mainBottomRevealCardID = card.id
        mainBottomRevealTick += 1
        return true
    }

    func resolvedMainCardLiveEditingHeightOverride(for card: SceneCard) -> CGFloat? {
        guard editingCardID == card.id else { return nil }
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
              textView.string == card.content,
              let liveBodyHeight = sharedLiveTextViewBodyHeight(textView) else { return nil }
        return ceil(liveBodyHeight + 48)
    }

    func resolvedMainCardHeightCacheKey(
        for card: SceneCard,
        mode: MainCardHeightMode
    ) -> MainCardHeightCacheKey {
        let lineSpacingBucket = Int((CGFloat(mainCardLineSpacingValue) * 10).rounded())
        let fontSizeBucket = Int((CGFloat(fontSize) * 10).rounded())

        let measuringText: String
        let width: CGFloat
        switch mode {
        case .display:
            measuringText = card.content.isEmpty ? "내용 없음" : card.content
            width = max(1, MainCanvasLayoutMetrics.cardWidth - (MainEditorLayoutMetrics.mainCardContentPadding * 2))
        case .editingFallback:
            measuringText = card.content
            width = max(1, MainCanvasLayoutMetrics.textWidth)
        }

        let normalizedText = normalizedSharedMeasurementText(measuringText)
        return MainCardHeightCacheKey(
            cardID: card.id,
            contentFingerprint: sharedStableTextFingerprint(normalizedText),
            textLength: normalizedText.utf16.count,
            widthBucket: Int((width * 10).rounded()),
            fontSizeBucket: fontSizeBucket,
            lineSpacingBucket: lineSpacingBucket,
            mode: mode
        )
    }

    func storeMainCardHeightRecord(_ record: MainCardHeightRecord) {
        if mainCardHeightRecordByKey.count >= 4096 {
            mainCardHeightRecordByKey.removeAll(keepingCapacity: true)
        }
        mainCardHeightRecordByKey[record.key] = record
    }

    func resolvedMainCardHeightRecord(
        for card: SceneCard,
        liveEditingHeightOverride: CGFloat? = nil
    ) -> MainCardHeightRecord {
        if let liveEditingHeightOverride {
            let record = MainCardHeightRecord(
                key: resolvedMainCardHeightCacheKey(for: card, mode: .editingFallback),
                height: liveEditingHeightOverride
            )
            return record
        }

        let lineSpacing = CGFloat(mainCardLineSpacingValue)
        let resolvedFontSize = CGFloat(fontSize)

        if editingCardID == card.id {
            let recordKey = resolvedMainCardHeightCacheKey(for: card, mode: .editingFallback)
            if let cached = mainCardHeightRecordByKey[recordKey] {
                return cached
            }

            let editorBodyHeight = sharedMeasuredTextBodyHeight(
                text: card.content,
                fontSize: resolvedFontSize,
                lineSpacing: lineSpacing,
                width: MainCanvasLayoutMetrics.textWidth,
                lineFragmentPadding: MainEditorLayoutMetrics.mainEditorLineFragmentPadding,
                safetyInset: 0
            )
            let record = MainCardHeightRecord(
                key: recordKey,
                height: ceil(editorBodyHeight + 48)
            )
            storeMainCardHeightRecord(record)
            return record
        }

        let displayText = card.content.isEmpty ? "내용 없음" : card.content
        let displayWidth = max(1, MainCanvasLayoutMetrics.cardWidth - (MainEditorLayoutMetrics.mainCardContentPadding * 2))
        let recordKey = resolvedMainCardHeightCacheKey(for: card, mode: .display)
        if let cached = mainCardHeightRecordByKey[recordKey] {
            return cached
        }

        let displayBodyHeight = sharedMeasuredTextBodyHeight(
            text: displayText,
            fontSize: resolvedFontSize,
            lineSpacing: lineSpacing,
            width: displayWidth,
            lineFragmentPadding: 0,
            safetyInset: 0
        )
        let record = MainCardHeightRecord(
            key: recordKey,
            height: ceil(displayBodyHeight + (MainEditorLayoutMetrics.mainCardContentPadding * 2))
        )
        storeMainCardHeightRecord(record)
        return record
    }

    func resolvedMainCardHeight(
        for card: SceneCard,
        liveEditingHeightOverride: CGFloat? = nil
    ) -> CGFloat {
        if let liveEditingHeightOverride {
            return liveEditingHeightOverride
        }
        if editingCardID == card.id,
           let liveBodyHeight = resolvedMainCardLiveEditingHeightOverride(for: card) {
            return liveBodyHeight
        }
        return resolvedMainCardHeightRecord(for: card).height
    }

    @ViewBuilder
    func cardRow(
        _ card: SceneCard,
        proxy: ScrollViewProxy,
        level: Int,
        parent: SceneCard?,
        columnCards: [SceneCard]
    ) -> some View {
        let isAICandidate = aiCandidateState.cardIDs.contains(card.id) || card.isAICandidate
        let isPlotLineCard = card.category == ScenarioCardCategory.plot
        let canCreateUpperCard = canCreateUpperCardFromSelection(contextCard: card)
        let canSummarizeChildren = canSummarizeDirectChildren(for: card)
        let isCloneLinked = scenario.isCardCloned(card.id)
        let hasLinkedCards = scenario.hasLinkedCards(card.id)
        let isLinkedCard = scenario.isLinkedCard(card.id)
        let clonePeerDestinations = isCloneLinked ? clonePeerMenuDestinations(for: card) : []
        CardItem(
            card: card,
            renderSettings: mainCardRenderSettings,
            isActive: activeCardID == card.id,
            isSelected: selectedCardIDs.contains(card.id),
            isMultiSelected: selectedCardIDs.count > 1 && selectedCardIDs.contains(card.id),
            isArchived: card.isArchived,
            isAncestor: activeAncestorIDs.contains(card.id) || activeSiblingIDs.contains(card.id),
            isDescendant: activeDescendantIDs.contains(card.id),
            isEditing: !showFocusMode && acceptsKeyboardInput && editingCardID == card.id,
            preferredTextMeasureWidth: MainCanvasLayoutMetrics.textWidth,
            forceNamedSnapshotNoteStyle: false,
            forceCustomColorVisibility: isAICandidate,
            onInsertSiblingAbove: { insertSibling(relativeTo: card, above: true) },
            onInsertSiblingBelow: { insertSibling(relativeTo: card, above: false) },
            onAddChildCard: { addChildCard(to: card) },
            onDropBefore: { providers, includeTrailingSiblingBlock in
                handleGeneralDrop(
                    providers,
                    target: .before(card.id),
                    includeTrailingSiblingBlock: includeTrailingSiblingBlock
                )
            },
            onDropAfter: { providers, includeTrailingSiblingBlock in
                handleGeneralDrop(
                    providers,
                    target: .after(card.id),
                    includeTrailingSiblingBlock: includeTrailingSiblingBlock
                )
            },
            onDropOnto: { providers, includeTrailingSiblingBlock in
                handleGeneralDrop(
                    providers,
                    target: .onto(card.id),
                    includeTrailingSiblingBlock: includeTrailingSiblingBlock
                )
            },
            onSelect: { handleMainWorkspaceCardClick(card) },
            onDoubleClick: {
                beginCardEditing(card)
            },
            onEndEdit: { finishEditing() },
            onSelectAtLocation: { location in
                handleMainWorkspaceCardClick(card, clickLocation: location)
            },
            onContentChange: { oldValue, newValue in
                handleMainEditorContentChange(cardID: card.id, oldValue: oldValue, newValue: newValue)
            },
            onColorChange: { hex in setCardColor(card, hex: hex) },
            onOpenIndexBoard: {
                openIndexBoardForColumn(level: level, parent: parent, cards: columnCards)
            },
            onReferenceCard: { addCardToReferenceWindow(card) },
            onCreateUpperCardFromSelection: canCreateUpperCard ? {
                createUpperCardFromSelection(contextCard: card)
            } : nil,
            onSummarizeChildren: canSummarizeChildren ? {
                runChildSummaryFromCardContextMenu(for: card)
            } : nil,
            onAIElaborate: {
                runAICardActionFromContextMenu(for: card, action: .elaborate)
            },
            onAINextScene: {
                runAICardActionFromContextMenu(for: card, action: .nextScene)
            },
            onAIAlternative: {
                runAICardActionFromContextMenu(for: card, action: .alternative)
            },
            onAISummarizeCurrent: {
                runAICardActionFromContextMenu(for: card, action: .summary)
            },
            aiPlotActionsEnabled: isPlotLineCard,
            onApplyAICandidate: isAICandidate ? {
                applyAICandidateFromCardContextMenu(cardID: card.id)
            } : nil,
            isSummarizingChildren: aiChildSummaryLoadingCardIDs.contains(card.id),
            isAIBusy: aiIsGenerating,
            onHardDelete: { performHardDelete(card) },
            onTranscriptionMode: { startDictationMode(from: card) },
            isTranscriptionBusy: dictationIsRecording || dictationIsProcessing,
            isCloneLinked: isCloneLinked,
            hasLinkedCards: hasLinkedCards,
            isLinkedCard: isLinkedCard,
            onCloneCard: { copyCardsAsCloneFromContext(card) },
            clonePeerDestinations: clonePeerDestinations,
            onNavigateToClonePeer: { targetID in navigateToCloneCard(targetID) }
        )
        .id(card.id)
        .onDrag {
            MainCardDragSessionTracker.shared.begin()
            return NSItemProvider(object: card.id.uuidString as NSString)
        }
    }

    func clonePeerMenuDestinations(for card: SceneCard) -> [ClonePeerMenuDestination] {
        let peers = scenario.clonePeers(for: card.id)
        guard !peers.isEmpty else { return [] }
        let orderedPeers = peers.sorted { lhs, rhs in
            let l = scenario.cardLocationByID(lhs.id) ?? (Int.max, Int.max)
            let r = scenario.cardLocationByID(rhs.id) ?? (Int.max, Int.max)
            if l.level != r.level { return l.level < r.level }
            if l.index != r.index { return l.index < r.index }
            return lhs.createdAt < rhs.createdAt
        }
        let baseTitles = orderedPeers.map { cloneParentTitle(for: $0) }

        var titleCounts: [String: Int] = [:]
        for title in baseTitles {
            titleCounts[title, default: 0] += 1
        }

        var resolvedIndexByTitle: [String: Int] = [:]
        return orderedPeers.enumerated().map { offset, peer in
            let baseTitle = baseTitles[offset]
            let totalCount = titleCounts[baseTitle] ?? 0
            let index = (resolvedIndexByTitle[baseTitle] ?? 0) + 1
            resolvedIndexByTitle[baseTitle] = index
            let title = totalCount > 1 ? "\(baseTitle) (\(index))" : baseTitle
            return ClonePeerMenuDestination(id: peer.id, title: title)
        }
    }

    func cloneParentTitle(for card: SceneCard) -> String {
        if let parent = card.parent {
            let firstLine = firstMeaningfulLine(from: parent.content)
            if let firstLine {
                return firstLine
            }
            return "(내용 없는 부모 카드)"
        }
        return "(루트)"
    }

    func firstMeaningfulLine(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if trimmed.count <= 36 { return trimmed }
                let cutoff = trimmed.index(trimmed.startIndex, offsetBy: 36)
                return "\(trimmed[..<cutoff])..."
            }
        }
        return nil
    }

    func navigateToCloneCard(_ cardID: UUID) {
        guard let target = findCard(by: cardID) else { return }
        selectedCardIDs = [target.id]
        changeActiveCard(to: target)
        isMainViewFocused = true
    }

    @ViewBuilder
    func addFirstButton(level: Int) -> some View {
        Button { suppressMainFocusRestoreAfterFinishEditing = true; finishEditing(); addCard(at: level, parent: nil) } label: { Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.vertical, 8) }.buttonStyle(.plain)
    }

    // MARK: - Drag & Drop

    func handleGeneralDrop(
        _ providers: [NSItemProvider],
        target: DropTarget,
        includeTrailingSiblingBlock: Bool = false
    ) {
        guard let provider = providers.first else { return }
        provider.loadObject(ofClass: NSString.self) { string, _ in
            guard let uuidStr = string as? String, let draggedID = UUID(uuidString: uuidStr) else { return }
            DispatchQueue.main.async {
                MainCardDragSessionTracker.shared.end()
                guard let draggedCard = findCard(by: draggedID) else { return }
                if includeTrailingSiblingBlock {
                    let siblingBlock = trailingSiblingBlock(from: draggedCard)
                    if siblingBlock.count > 1 {
                        executeMoveSelection(siblingBlock, draggedCard: draggedCard, target: target)
                        return
                    }
                }
                let selectedCards = selectedCardIDs.compactMap { findCard(by: $0) }
                if selectedCardIDs.count > 1, selectedCardIDs.contains(draggedID) {
                    executeMoveSelection(selectedCards, draggedCard: draggedCard, target: target)
                } else {
                    executeMove(draggedCard, target: target)
                }
            }
        }
    }

    func executeMoveSelection(_ selectedCards: [SceneCard], draggedCard: SceneCard, target: DropTarget) {
        let movingRoots = movableRoots(from: selectedCards)
        guard !movingRoots.isEmpty else { return }

        if case .onto(let targetID) = target, movingRoots.contains(where: { $0.id == targetID }) { return }
        if let targetID = targetIDFrom(target), movingRoots.contains(where: { isDescendant($0, of: targetID) }) { return }

        let prevState = captureScenarioState()
        let destination = resolveDestination(target)
        let destinationParent = destination.parent
        var insertionIndex = destination.index
        let destinationParentID = destinationParent?.id
        let movingIDs = Set(movingRoots.map { $0.id })

        let movedBeforeDestination = movingRoots.filter {
            $0.parent?.id == destinationParentID && $0.orderIndex < insertionIndex
        }.count
        insertionIndex -= movedBeforeDestination
        if insertionIndex < 0 { insertionIndex = 0 }

        let oldParents = movingRoots.map { $0.parent }
        scenario.performBatchedCardMutation {
            let destinationSiblings = liveOrderedSiblings(parent: destinationParent)
            for sibling in destinationSiblings where !movingIDs.contains(sibling.id) && sibling.orderIndex >= insertionIndex {
                sibling.orderIndex += movingRoots.count
            }

            for (offset, card) in movingRoots.enumerated() {
                let previousParent = card.parent
                if card.isArchived {
                    card.isArchived = false
                }
                card.parent = destinationParent
                card.orderIndex = insertionIndex + offset
                card.isFloating = false
                synchronizeMovedSubtreeCategoryIfNeeded(
                    for: card,
                    oldParent: previousParent,
                    newParent: destinationParent
                )
            }

            normalizeAffectedParents(oldParents: oldParents, destinationParent: destinationParent)
        }

        selectedCardIDs = Set(movingRoots.map { $0.id })
        changeActiveCard(to: draggedCard)
        commitCardMutation(
            previousState: prevState,
            actionName: "카드 이동"
        )
    }

    func movableRoots(from cards: [SceneCard]) -> [SceneCard] {
        let selected = Set(cards.map { $0.id })
        let roots = cards.filter { card in
            var p = card.parent
            while let parent = p {
                if selected.contains(parent.id) { return false }
                p = parent.parent
            }
            return true
        }
        let rank = buildCanvasRank()
        return roots.sorted { lhs, rhs in
            let l = rank[lhs.id] ?? (Int.max, Int.max)
            let r = rank[rhs.id] ?? (Int.max, Int.max)
            if l.0 != r.0 { return l.0 < r.0 }
            if l.1 != r.1 { return l.1 < r.1 }
            return lhs.createdAt < rhs.createdAt
        }
    }

    func trailingSiblingBlock(from draggedCard: SceneCard) -> [SceneCard] {
        let siblings = liveOrderedSiblings(parent: draggedCard.parent)
        guard let startIndex = siblings.firstIndex(where: { $0.id == draggedCard.id }) else {
            return [draggedCard]
        }
        return Array(siblings[startIndex...])
    }

    func buildCanvasRank() -> [UUID: (Int, Int)] {
        let levels = resolvedAllLevels()
        var rank: [UUID: (Int, Int)] = Dictionary(minimumCapacity: scenario.cards.count)
        for (levelIndex, cards) in levels.enumerated() {
            for (index, card) in cards.enumerated() {
                rank[card.id] = (levelIndex, index)
            }
        }
        return rank
    }

    func resolveDestination(_ target: DropTarget) -> (parent: SceneCard?, index: Int) {
        switch target {
        case .before(let id):
            if let anchor = findCard(by: id) {
                return (anchor.parent, anchor.orderIndex)
            }
        case .after(let id):
            if let anchor = findCard(by: id) {
                return (anchor.parent, anchor.orderIndex + 1)
            }
        case .onto(let id):
            if let parent = findCard(by: id) {
                return (parent, liveOrderedSiblings(parent: parent).count)
            }
        case .columnTop(let pId):
            let parent = pId.flatMap { findCard(by: $0) }
            return (parent, 0)
        case .columnBottom(let pId):
            let parent = pId.flatMap { findCard(by: $0) }
            let count = liveOrderedSiblings(parent: parent).count
            return (parent, count)
        }
        return (nil, liveOrderedSiblings(parent: nil).count)
    }

    func normalizeAffectedParents(oldParents: [SceneCard?], destinationParent: SceneCard?) {
        var normalizedParentIDs: Set<UUID> = []
        var normalizedRoot = false
        for parent in oldParents {
            if let parent = parent {
                guard normalizedParentIDs.insert(parent.id).inserted else { continue }
                normalizeIndices(parent: parent)
            } else if !normalizedRoot {
                normalizeIndices(parent: nil)
                normalizedRoot = true
            }
        }
        if let destinationParent = destinationParent {
            guard normalizedParentIDs.insert(destinationParent.id).inserted else { return }
            normalizeIndices(parent: destinationParent)
        } else if !normalizedRoot {
            normalizeIndices(parent: nil)
        }
    }

    func executeMove(_ card: SceneCard, target: DropTarget) {
        if case .onto(let targetID) = target, targetID == card.id { return }
        if let targetID = targetIDFrom(target), isDescendant(card, of: targetID) { return }

        let prevState = captureScenarioState()
        scenario.performBatchedCardMutation {
            if card.isArchived {
                card.isArchived = false
            }

            let oldParent = card.parent
            normalizeIndices(parent: oldParent)

            switch target {
            case .before(let id):
                if let anchor = findCard(by: id) {
                    let newParent = anchor.parent
                    let newIndex = anchor.orderIndex
                    let newSiblings = liveOrderedSiblings(parent: newParent)
                    for s in newSiblings where s.orderIndex >= newIndex { s.orderIndex += 1 }
                    card.parent = newParent; card.orderIndex = newIndex
                }
            case .after(let id):
                if let anchor = findCard(by: id) {
                    let newParent = anchor.parent
                    let newIndex = anchor.orderIndex + 1
                    let newSiblings = liveOrderedSiblings(parent: newParent)
                    for s in newSiblings where s.orderIndex >= newIndex { s.orderIndex += 1 }
                    card.parent = newParent; card.orderIndex = newIndex
                }
            case .onto(let id):
                if let parent = findCard(by: id) {
                    card.parent = parent
                    card.orderIndex = liveOrderedSiblings(parent: parent).count
                }
            case .columnTop(let pId):
                let newParent = pId.flatMap { findCard(by: $0) }
                let newSiblings = liveOrderedSiblings(parent: newParent)
                for s in newSiblings { s.orderIndex += 1 }
                card.parent = newParent; card.orderIndex = 0
            case .columnBottom(let pId):
                let newParent = pId.flatMap { findCard(by: $0) }
                let newSiblings = liveOrderedSiblings(parent: newParent)
                card.parent = newParent; card.orderIndex = newSiblings.count
            }

            card.isFloating = false
            normalizeIndices(parent: card.parent)
            if oldParent?.id != card.parent?.id { normalizeIndices(parent: oldParent) }

            synchronizeMovedSubtreeCategoryIfNeeded(
                for: card,
                oldParent: oldParent,
                newParent: card.parent
            )
        }
        changeActiveCard(to: card)
        commitCardMutation(
            previousState: prevState,
            actionName: "카드 이동"
        )
    }

    func targetIDFrom(_ target: DropTarget) -> UUID? {
        switch target {
        case .before(let id), .after(let id), .onto(let id): return id
        default: return nil
        }
    }

    func liveOrderedSiblings(parent: SceneCard?) -> [SceneCard] {
        if !scenario.isCardMutationBatchInProgress {
            if let parent {
                return scenario.children(for: parent.id)
            }
            return scenario.rootCards
        }
        return scenario.cards
            .filter { candidate in
                guard !candidate.isArchived else { return false }
                if let parent {
                    return candidate.parent?.id == parent.id
                }
                return candidate.parent == nil && !candidate.isFloating
            }
            .sorted {
                if $0.orderIndex != $1.orderIndex {
                    return $0.orderIndex < $1.orderIndex
                }
                return $0.createdAt < $1.createdAt
            }
    }

    func synchronizeMovedSubtreeCategoryIfNeeded(
        for card: SceneCard,
        oldParent: SceneCard?,
        newParent: SceneCard?
    ) {
        let previousCategory = oldParent?.category
        let nextCategory = newParent?.category
        guard previousCategory != nextCategory || card.category != nextCategory else { return }
        card.updateDescendantsCategory(nextCategory)
    }

    func isDescendant(_ card: SceneCard, of targetID: UUID) -> Bool {
        var curr = findCard(by: targetID)?.parent
        var visited: Set<UUID> = []
        while let p = curr {
            guard visited.insert(p.id).inserted else { return false }
            if p.id == card.id { return true }
            curr = p.parent
        }
        return false
    }

    func resolvedLevelsWithParents() -> [LevelData] {
        if resolvedLevelsWithParentsVersion == scenario.cardsVersion {
            return resolvedLevelsWithParentsCache
        }
        let levels = scenario.allLevels
        let resolved = levels.map { cards in
            LevelData(cards: cards, parent: cards.first?.parent)
        }
        resolvedLevelsWithParentsVersion = scenario.cardsVersion
        resolvedLevelsWithParentsCache = resolved
        return resolved
    }

    func displayedMainLevelsData(from levelsData: [LevelData]) -> [LevelData] {
        if isInactiveSplitPane {
            return levelsData.enumerated().map { index, data in
                LevelData(
                    cards: filteredCardsForMainCanvasColumn(levelIndex: index, cards: data.cards),
                    parent: data.parent
                )
            }
        }

        let cacheKey = DisplayedMainLevelsCacheKey(
            cardsVersion: scenario.cardsVersion,
            activeCategory: activeCategory,
            isActiveCardRoot: isActiveCardRoot
        )
        if displayedMainLevelsCacheKey == cacheKey {
            return displayedMainLevelsCache
        }

        let resolved = levelsData.enumerated().map { index, data in
            LevelData(
                cards: filteredCardsForMainCanvasColumn(levelIndex: index, cards: data.cards),
                parent: data.parent
            )
        }
        var locationByID: [UUID: (level: Int, index: Int)] = [:]
        for (levelIndex, data) in resolved.enumerated() {
            for (index, card) in data.cards.enumerated() {
                locationByID[card.id] = (levelIndex, index)
            }
        }
        displayedMainLevelsCacheKey = cacheKey
        displayedMainLevelsCache = resolved
        displayedMainCardLocationByIDCache = locationByID
        return resolved
    }

    func resolvedDisplayedMainLevelsWithParents() -> [LevelData] {
        displayedMainLevelsData(from: resolvedLevelsWithParents())
    }

    func resolvedDisplayedMainLevels() -> [[SceneCard]] {
        resolvedDisplayedMainLevelsWithParents().map(\.cards)
    }

    func displayedMainCardLocationByID(
        _ id: UUID,
        in levels: [[SceneCard]]
    ) -> (level: Int, index: Int)? {
        for (levelIndex, cards) in levels.enumerated() {
            if let index = cards.firstIndex(where: { $0.id == id }) {
                return (levelIndex, index)
            }
        }
        return nil
    }

    func displayedMainCardLocationByID(_ id: UUID) -> (level: Int, index: Int)? {
        let _ = resolvedDisplayedMainLevelsWithParents()
        return displayedMainCardLocationByIDCache[id]
    }

    func resolvedAllLevels() -> [[SceneCard]] {
        scenario.allLevels
    }

    func scrollToColumnIfNeeded(
        targetCardID: UUID,
        proxy: ScrollViewProxy,
        availableWidth: CGFloat,
        force: Bool = false,
        animated: Bool = true
    ) {
        if !acceptsKeyboardInput && !force { return }
        guard let targetLevel = displayedMainCardLocationByID(targetCardID)?.level else { return }
        let resolvedAvailableWidth = max(1, availableWidth)
        let scrollMode = mainCanvasHorizontalScrollMode
        let performScroll: (Int) -> Void = { level in
            if performMainCanvasHorizontalScroll(
                level: level,
                availableWidth: resolvedAvailableWidth,
                animated: animated
            ) {
                return
            }

            let hAnchor = resolvedMainCanvasHorizontalAnchor(availableWidth: resolvedAvailableWidth)
            if animated {
                MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                    ownerKey: mainCanvasDiagnosticsOwnerKey,
                    axis: "horizontal",
                    engine: "proxy",
                    animated: true,
                    target: "level:\(level)",
                    expectedDuration: 0.24
                )
                withAnimation(quickEaseAnimation) {
                    proxy.scrollTo(level, anchor: hAnchor)
                }
            } else {
                MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                    ownerKey: mainCanvasDiagnosticsOwnerKey,
                    axis: "horizontal",
                    engine: "proxy",
                    animated: false,
                    target: "level:\(level)",
                    expectedDuration: 0
                )
                performWithoutAnimation {
                    proxy.scrollTo(level, anchor: hAnchor)
                }
            }
        }
        switch scrollMode {
        case .oneStep:
            let desiredLevel = targetLevel
            if force || lastScrolledLevel != desiredLevel {
                lastScrolledLevel = desiredLevel
                performScroll(desiredLevel)
            }
        case .twoStep:
            if force {
                lastScrolledLevel = max(0, targetLevel - 1)
                performScroll(lastScrolledLevel)
                return
            }
            if lastScrolledLevel < 0 {
                lastScrolledLevel = max(0, targetLevel - 1)
                performScroll(lastScrolledLevel)
                return
            }
            if targetLevel < lastScrolledLevel {
                lastScrolledLevel = targetLevel
                performScroll(lastScrolledLevel)
            } else if targetLevel > lastScrolledLevel + 1 {
                lastScrolledLevel = targetLevel - 1
                performScroll(lastScrolledLevel)
            }
        }
    }

    func resolvedMainCanvasHorizontalAnchor(availableWidth: CGFloat) -> UnitPoint {
        let resolvedAvailableWidth = max(1, availableWidth)
        switch mainCanvasHorizontalScrollMode {
        case .oneStep:
            return UnitPoint(x: 0.5, y: 0.4)
        case .twoStep:
            let hOffset = (columnWidth / 2) / resolvedAvailableWidth
            return UnitPoint(x: 0.5 - hOffset, y: 0.4)
        }
    }

    func resolvedMainCanvasHorizontalTargetX(
        level: Int,
        availableWidth: CGFloat,
        visibleWidth: CGFloat
    ) -> CGFloat {
        let anchor = resolvedMainCanvasHorizontalAnchor(availableWidth: availableWidth)
        let leadingInset = availableWidth / 2
        let targetMinX = leadingInset + (CGFloat(level) * columnWidth)
        let targetAnchorX = targetMinX + (columnWidth * anchor.x)
        return targetAnchorX - (visibleWidth * anchor.x)
    }

    @discardableResult
    func performMainCanvasHorizontalScroll(
        level: Int,
        availableWidth: CGFloat,
        animated: Bool
    ) -> Bool {
        guard let scrollView = mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalScrollView() else {
            return false
        }

        let visibleRect = scrollView.documentVisibleRect
        let documentWidth = scrollView.documentView?.bounds.width ?? 0
        let maxX = max(0, documentWidth - visibleRect.width)
        let targetX = resolvedMainCanvasHorizontalTargetX(
            level: level,
            availableWidth: availableWidth,
            visibleWidth: visibleRect.width
        )
        let targetReachable = maxX + 0.5 >= targetX

        if animated {
            guard targetReachable || targetX <= 0.5 else { return false }
            let resolvedTargetX = CaretScrollCoordinator.resolvedHorizontalTargetX(
                visibleRect: visibleRect,
                targetX: targetX,
                minX: 0,
                maxX: maxX,
                snapToPixel: true
            )
            guard abs(resolvedTargetX - visibleRect.origin.x) > 0.5 else { return true }
            let appliedDuration = CaretScrollCoordinator.resolvedHorizontalAnimationDuration(
                currentX: visibleRect.origin.x,
                targetX: resolvedTargetX,
                viewportWidth: visibleRect.width
            )
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                axis: "horizontal",
                engine: "native",
                animated: true,
                target: "level:\(level)",
                expectedDuration: appliedDuration
            )
            _ = CaretScrollCoordinator.applyAnimatedHorizontalScrollIfNeeded(
                scrollView: scrollView,
                visibleRect: visibleRect,
                targetX: targetX,
                minX: 0,
                maxX: maxX,
                deadZone: 0.5,
                snapToPixel: true,
                duration: appliedDuration
            )
            bounceDebugLog(
                "nativeMainCanvasHorizontalScroll level=\(level) " +
                "targetX=\(debugCGFloat(resolvedTargetX)) visibleX=\(debugCGFloat(visibleRect.origin.x)) " +
                "duration=\(String(format: "%.2f", appliedDuration)) viewport=\(debugCGFloat(visibleRect.width))"
            )
            return true
        }

        MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
            ownerKey: mainCanvasDiagnosticsOwnerKey,
            axis: "horizontal",
            engine: "native",
            animated: false,
            target: "level:\(level)",
            expectedDuration: 0
        )
        let applied = CaretScrollCoordinator.applyHorizontalScrollIfNeeded(
            scrollView: scrollView,
            visibleRect: visibleRect,
            targetX: targetX,
            minX: 0,
            maxX: maxX,
            deadZone: 0.5,
            snapToPixel: true
        )
        if applied {
            bounceDebugLog(
                "nativeMainCanvasHorizontalScroll immediate level=\(level) " +
                "targetX=\(debugCGFloat(targetX)) visibleX=\(debugCGFloat(visibleRect.origin.x))"
            )
        }
        let resolvedTargetX = CaretScrollCoordinator.resolvedHorizontalTargetX(
            visibleRect: visibleRect,
            targetX: targetX,
            minX: 0,
            maxX: maxX,
            snapToPixel: true
        )
        let currentX = scrollView.contentView.bounds.origin.x
        return targetReachable && abs(resolvedTargetX - currentX) <= 0.5
    }

    // MARK: - Card Lookup & Active State

    func findCard(by id: UUID) -> SceneCard? { scenario.cardByID(id) }

    func resolvedActiveRelationFingerprint(
        sourceCardID: UUID?,
        cardsVersion: Int,
        ancestors: Set<UUID>,
        siblings: Set<UUID>,
        descendants: Set<UUID>
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(sourceCardID)
        hasher.combine(cardsVersion)
        hasher.combine(ancestors.count)
        for id in ancestors.sorted(by: { $0.uuidString < $1.uuidString }) {
            hasher.combine(id)
        }
        hasher.combine(siblings.count)
        for id in siblings.sorted(by: { $0.uuidString < $1.uuidString }) {
            hasher.combine(id)
        }
        hasher.combine(descendants.count)
        for id in descendants.sorted(by: { $0.uuidString < $1.uuidString }) {
            hasher.combine(id)
        }
        return hasher.finalize()
    }

    func resetActiveRelationStateCache() {
        if !activeAncestorIDs.isEmpty || !activeSiblingIDs.isEmpty || !activeDescendantIDs.isEmpty || activeRelationSourceCardID != nil {
            bounceDebugLog("resetActiveRelationStateCache \(debugFocusStateSummary())")
        }
        activeAncestorIDs = []
        activeSiblingIDs = []
        activeDescendantIDs = []
        activeRelationSourceCardID = nil
        activeRelationSourceCardsVersion = scenario.cardsVersion
        activeRelationFingerprint = resolvedActiveRelationFingerprint(
            sourceCardID: nil,
            cardsVersion: scenario.cardsVersion,
            ancestors: [],
            siblings: [],
            descendants: []
        )
    }

    func synchronizeActiveRelationState(for activeID: UUID?) {
        let relationSyncStartedAt = CACurrentMediaTime()
        if activeRelationSourceCardID == activeID,
           activeRelationSourceCardsVersion == scenario.cardsVersion {
            return
        }

        guard let activeID, let card = findCard(by: activeID) else {
            resetActiveRelationStateCache()
            return
        }

        var ancestors: Set<UUID> = []
        var parent = card.parent
        while let current = parent {
            ancestors.insert(current.id)
            parent = current.parent
        }

        let siblings = card.parent?.children ?? scenario.rootCards
        let siblingIDs = Set(siblings.map { $0.id }).filter { $0 != card.id }
        let descendantIDs = scenario.descendantIDs(for: card.id)
        let relationChanged =
            activeAncestorIDs != ancestors ||
            activeSiblingIDs != siblingIDs ||
            activeDescendantIDs != descendantIDs ||
            activeRelationSourceCardID != activeID ||
            activeRelationSourceCardsVersion != scenario.cardsVersion

        if activeAncestorIDs != ancestors { activeAncestorIDs = ancestors }
        if activeSiblingIDs != siblingIDs { activeSiblingIDs = siblingIDs }
        if activeDescendantIDs != descendantIDs { activeDescendantIDs = descendantIDs }
        activeRelationSourceCardID = activeID
        activeRelationSourceCardsVersion = scenario.cardsVersion
        activeRelationFingerprint = resolvedActiveRelationFingerprint(
            sourceCardID: activeID,
            cardsVersion: scenario.cardsVersion,
            ancestors: ancestors,
            siblings: siblingIDs,
            descendants: descendantIDs
        )
        if relationChanged {
            bounceDebugLog(
                "synchronizeActiveRelationState active=\(debugCardToken(card)) " +
                "ancestors=\(debugUUIDListSummary(ancestors.sorted { $0.uuidString < $1.uuidString }, limit: 8)) " +
                "siblings=\(siblingIDs.count) descendants=\(descendantIDs.count) version=\(scenario.cardsVersion)"
            )
        }
        MainCanvasNavigationDiagnostics.shared.recordRelationSync(
            ownerKey: mainCanvasDiagnosticsOwnerKey,
            activeCardID: activeID,
            durationMilliseconds: (CACurrentMediaTime() - relationSyncStartedAt) * 1000,
            ancestorCount: ancestors.count,
            siblingCount: siblingIDs.count,
            descendantCount: descendantIDs.count
        )
    }

    func changeActiveCard(
        to card: SceneCard,
        shouldFocusMain: Bool = true,
        deferToMainAsync: Bool = true,
        force: Bool = false
    ) {
        let debugStack = Thread.callStackSymbols
            .filter { $0.contains("/wa/") || $0.contains("WTF") }
            .prefix(6)
            .joined(separator: " | ")
        bounceDebugLog(
            "changeActiveCard requested target=\(card.id.uuidString) current=\(activeCardID?.uuidString ?? "nil") " +
            "pending=\(pendingActiveCardID?.uuidString ?? "nil") force=\(force) async=\(deferToMainAsync) " +
            "stack=\(debugStack)"
        )
        cleanupEmptyEditingCardIfNeeded(beforeSwitchingTo: card.id)
        if !force {
            if activeCardID == card.id, pendingActiveCardID == nil {
                bounceDebugLog("changeActiveCard ignoredAlreadyActive target=\(debugCardToken(card)) shouldFocus=\(shouldFocusMain)")
                if shouldFocusMain { isMainViewFocused = true }
                return
            }
            if pendingActiveCardID == card.id {
                bounceDebugLog("changeActiveCard ignoredPending target=\(debugCardToken(card)) shouldFocus=\(shouldFocusMain)")
                if shouldFocusMain { isMainViewFocused = true }
                return
            }
        } else {
            pendingActiveCardID = nil
        }
        pendingActiveCardID = card.id
        let apply = {
            defer { pendingActiveCardID = nil }
            let previousActiveID = activeCardID
            let previousRememberedChildID = card.parent?.lastSelectedChildID
            if activeCardID != card.id {
                lastActiveCardID = activeCardID
            }
            activeCardID = card.id
            if splitModeEnabled {
                scenario.setSplitPaneActiveCard(card.id, for: splitPaneID)
            }
            card.parent?.lastSelectedChildID = card.id
            synchronizeActiveRelationState(for: card.id)
            if shouldFocusMain { isMainViewFocused = true }
            let levelCount = scenario.allLevels.count
            if levelCount > maxLevelCount { maxLevelCount = levelCount }
            bounceDebugLog(
                "changeActiveCard applied target=\(debugCardToken(card)) previous=\(debugCardIDString(previousActiveID)) " +
                "parent=\(debugCardToken(card.parent)) parentRememberedBefore=\(debugCardIDString(previousRememberedChildID)) " +
                "parentRememberedAfter=\(debugCardIDString(card.parent?.lastSelectedChildID)) " +
                "levelCount=\(levelCount) \(debugFocusStateSummary())"
            )
        }
        if deferToMainAsync || !Thread.isMainThread {
            DispatchQueue.main.async { apply() }
        } else {
            apply()
        }
    }

    func cleanupEmptyEditingCardIfNeeded(beforeSwitchingTo targetCardID: UUID) {
        guard !isApplyingUndo else { return }
        guard let currentEditingID = editingCardID,
              currentEditingID != targetCardID,
              let currentCard = findCard(by: currentEditingID) else { return }
        guard currentCard.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        finishEditing()
    }

    func descendantIDSet(of card: SceneCard) -> Set<UUID> {
        scenario.descendantIDs(for: card.id)
    }

    // MARK: - Finish Editing

    struct FinishEditingContext {
        let cardID: UUID
        let inFocusMode: Bool
        let skipMainFocusRestore: Bool
        let startContent: String
        let startState: ScenarioState?
        let wasNewCard: Bool
        let newCardPrevState: ScenarioState?
    }

    func takeFinishEditingContext() -> FinishEditingContext? {
        let inFocusMode = showFocusMode
        let skipMainFocusRestore = suppressMainFocusRestoreAfterFinishEditing || inFocusMode
        suppressMainFocusRestoreAfterFinishEditing = false
        if inFocusMode {
            finalizeFocusTypingCoalescing(reason: "finish-editing")
        }
        guard let id = editingCardID else { return nil }
        if !inFocusMode {
            rememberMainCaretLocation(for: id)
        }
        let context = FinishEditingContext(
            cardID: id,
            inFocusMode: inFocusMode,
            skipMainFocusRestore: skipMainFocusRestore,
            startContent: editingStartContent,
            startState: editingStartState,
            wasNewCard: editingIsNewCard,
            newCardPrevState: pendingNewCardPrevState
        )
        resetEditingTransientState()
        return context
    }

    func resetEditingTransientState() {
        editingCardID = nil
        editingStartContent = ""
        editingIsNewCard = false
        editingStartState = nil
        pendingNewCardPrevState = nil
    }

    func runFinishEditingCommit(_ apply: @escaping () -> Void) {
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async { apply() }
        }
    }

    func finishEditing() {
        guard let context = takeFinishEditingContext() else { return }
        // Re-entrant finish events can arrive from multiple view layers.
        // Clear edit state first so the same edit cannot be committed twice.
        let apply = {
            commitFinishedEditingIfNeeded(
                id: context.cardID,
                inFocusMode: context.inFocusMode,
                startContent: context.startContent,
                startState: context.startState,
                wasNewCard: context.wasNewCard,
                newCardPrevState: context.newCardPrevState
            )
            restoreMainFocusAfterFinishEditingIfNeeded(skipMainFocusRestore: context.skipMainFocusRestore)
        }
        runFinishEditingCommit(apply)
    }

    func commitFinishedEditingIfNeeded(
        id: UUID,
        inFocusMode: Bool,
        startContent: String,
        startState: ScenarioState?,
        wasNewCard: Bool,
        newCardPrevState: ScenarioState?
    ) {
        guard let card = findCard(by: id) else { return }
        normalizeEditingCardContent(card)
        if card.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            commitEmptyEditingCard(
                card,
                id: id,
                inFocusMode: inFocusMode,
                wasNewCard: wasNewCard
            )
        } else {
            commitNonEmptyEditingCard(
                card,
                id: id,
                inFocusMode: inFocusMode,
                startContent: startContent,
                startState: startState,
                wasNewCard: wasNewCard,
                newCardPrevState: newCardPrevState
            )
        }
    }

    func normalizeEditingCardContent(_ card: SceneCard) {
        while card.content.hasSuffix("\n") {
            card.content.removeLast()
        }
    }

    func commitEmptyEditingCard(
        _ card: SceneCard,
        id: UUID,
        inFocusMode: Bool,
        wasNewCard: Bool
    ) {
        let prevState = captureScenarioState()
        let focusColumnCardsBeforeRemoval = inFocusMode ? focusedColumnCards() : []
        if !card.children.isEmpty {
            if !card.content.isEmpty {
                createArchivedCopy(from: card)
            }
            card.content = ""
            persistCardMutation(forceSnapshot: true)
            pushCardDeleteUndoState(prevState: prevState, inFocusMode: inFocusMode)
            return
        }

        if activeCardID == id {
            suppressAutoScrollOnce = true
            suppressHorizontalAutoScroll = true
            let next: SceneCard? = {
                if wasNewCard,
                   let previousID = lastActiveCardID,
                   previousID != card.id,
                   let previous = findCard(by: previousID),
                   !previous.isArchived {
                    return previous
                }
                if inFocusMode {
                    return nextFocusAfterFocusModeEmptyCardRemoval(
                        removedCard: card,
                        focusColumnCardsBeforeRemoval: focusColumnCardsBeforeRemoval
                    )
                }
                return nextFocusAfterMainModeEmptyCardRemoval(removedCard: card)
            }()
            if let n = next {
                selectedCardIDs = [n.id]
                changeActiveCard(to: n)
            } else {
                selectedCardIDs = []
                activeCardID = nil
                synchronizeActiveRelationState(for: nil)
            }
        }

        card.isArchived = true
        scenario.bumpCardsVersion()
        persistCardMutation(forceSnapshot: true)
        pushCardDeleteUndoState(prevState: prevState, inFocusMode: inFocusMode)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { suppressHorizontalAutoScroll = false }
    }

    func nextFocusAfterMainModeEmptyCardRemoval(removedCard: SceneCard) -> SceneCard? {
        let siblings = removedCard.parent?.sortedChildren ?? scenario.rootCards
        if let index = siblings.firstIndex(where: { $0.id == removedCard.id }) {
            if index > 0 {
                for i in stride(from: index - 1, through: 0, by: -1) {
                    let candidate = siblings[i]
                    if candidate.id != removedCard.id && !candidate.isArchived {
                        return candidate
                    }
                }
            }
            if index + 1 < siblings.count {
                for i in (index + 1)..<siblings.count {
                    let candidate = siblings[i]
                    if candidate.id != removedCard.id && !candidate.isArchived {
                        return candidate
                    }
                }
            }
        }
        if let parent = removedCard.parent, !parent.isArchived {
            return parent
        }
        return scenario.rootCards.first { $0.id != removedCard.id && !$0.isArchived }
    }

    func nextFocusAfterFocusModeEmptyCardRemoval(
        removedCard: SceneCard,
        focusColumnCardsBeforeRemoval: [SceneCard]
    ) -> SceneCard? {
        if let index = focusColumnCardsBeforeRemoval.firstIndex(where: { $0.id == removedCard.id }) {
            if index > 0 {
                for i in stride(from: index - 1, through: 0, by: -1) {
                    let candidate = focusColumnCardsBeforeRemoval[i]
                    if candidate.id != removedCard.id && !candidate.isArchived {
                        return candidate
                    }
                }
            }
            if index + 1 < focusColumnCardsBeforeRemoval.count {
                for i in (index + 1)..<focusColumnCardsBeforeRemoval.count {
                    let candidate = focusColumnCardsBeforeRemoval[i]
                    if candidate.id != removedCard.id && !candidate.isArchived {
                        return candidate
                    }
                }
            }
        }
        if let parent = removedCard.parent, !parent.isArchived {
            return parent
        }
        return nil
    }

    func pushCardDeleteUndoState(prevState: ScenarioState, inFocusMode: Bool) {
        if inFocusMode {
            pushFocusUndoState(prevState, actionName: "카드 삭제")
        } else {
            pushUndoState(prevState, actionName: "카드 삭제")
        }
    }

    func commitNonEmptyEditingCard(
        _ card: SceneCard,
        id: UUID,
        inFocusMode: Bool,
        startContent: String,
        startState: ScenarioState?,
        wasNewCard: Bool,
        newCardPrevState: ScenarioState?
    ) {
        let contentChanged = startContent != card.content
        if !isApplyingUndo {
            if !inFocusMode {
                if wasNewCard, let prev = newCardPrevState {
                    pushUndoState(prev, actionName: "카드 추가")
                } else if let prev = startState, contentChanged {
                    pushUndoState(prev, actionName: "텍스트 편집")
                }
            }
        }
        recordLinkedCardEditIfNeeded(editedCardID: id, contentChanged: contentChanged)
        if inFocusMode {
            focusLastCommittedContentByCard[id] = card.content
        }
        persistCardMutation()
    }

    func recordLinkedCardEditIfNeeded(editedCardID: UUID, contentChanged: Bool) {
        guard contentChanged else { return }
        guard splitModeEnabled, splitPaneID == 2 else { return }
        guard splitPaneAutoLinkEditsEnabled else { return }
        guard let focusCardID = resolvedFocusCardIDForLinkedEditRecording() else { return }
        guard focusCardID != editedCardID else { return }
        scenario.recordLinkedCard(focusCardID: focusCardID, linkedCardID: editedCardID)
    }

    func resolvedFocusCardIDForLinkedEditRecording() -> UUID? {
        if linkedCardsFilterEnabled,
           let anchorID = resolvedLinkedCardsAnchorID(),
           findCard(by: anchorID) != nil {
            return anchorID
        }
        if let leftPaneID = scenario.splitPaneActiveCardID(for: 1),
           findCard(by: leftPaneID) != nil {
            return leftPaneID
        }
        return nil
    }

    func restoreMainFocusAfterFinishEditingIfNeeded(skipMainFocusRestore: Bool) {
        if !skipMainFocusRestore {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { isMainViewFocused = true }
        }
    }

    // MARK: - Export & Deselect

    func deselectAll() {
        finishEditing()
        activeCardID = nil
        resetActiveRelationStateCache()
        selectedCardIDs = []
    }

    func buildExportText() -> String {
        guard let activeID = activeCardID else { return "" }
        let levels = resolvedLevelsWithParents()
        var target: [SceneCard] = []
        for (idx, data) in levels.enumerated() {
            guard data.cards.contains(where: { $0.id == activeID }) else { continue }
            target = (idx <= 1 || isActiveCardRoot)
                ? data.cards
                : data.cards.filter { $0.category == activeCategory }
            break
        }
        return target.map { $0.content }.joined(separator: "\n\n")
    }

    func exportToClipboard() {
        let txt = buildExportText()
        if txt.isEmpty {
            exportMessage = "출력할 내용이 없습니다."
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(txt, forType: .string)
            exportMessage = "클립보드에 복사되었습니다."
        }
        showExportAlert = true
    }
    
    func copySelectedCardTreeToClipboard() {
        let roots = copySourceRootCards()
        guard !roots.isEmpty else { return }
        let payload = CardTreeClipboardPayload(roots: roots.map { encodeClipboardNode(from: $0) })
        guard persistCardTreePayloadToClipboard(payload) else { return }
        clearCutCardTreeBuffer()
    }

    func cutSelectedCardTreeToClipboard() {
        let roots = copySourceRootCards()
        guard !roots.isEmpty else { return }
        let payload = CardTreeClipboardPayload(roots: roots.map { encodeClipboardNode(from: $0) })
        guard persistCardTreePayloadToClipboard(payload) else { return }
        cutCardRootIDs = roots.map { $0.id }
        cutCardSourceScenarioID = scenario.id
    }

    func copyCardsAsCloneFromContext(_ contextCard: SceneCard) {
        let cards = cloneCopySourceCards(contextCard: contextCard)
        guard !cards.isEmpty else { return }
        let payload = CloneCardClipboardPayload(
            sourceScenarioID: scenario.id,
            items: cards.map { card in
                CloneCardClipboardItem(
                    sourceCardID: card.id,
                    cloneGroupID: card.cloneGroupID,
                    content: card.content,
                    colorHex: card.colorHex,
                    isAICandidate: card.isAICandidate
                )
            }
        )
        guard persistCloneCardPayloadToClipboard(payload) else { return }
        clearCutCardTreeBuffer()
    }

    func cloneCopySourceCards(contextCard: SceneCard) -> [SceneCard] {
        if selectedCardIDs.count > 1, selectedCardIDs.contains(contextCard.id) {
            let selected = selectedCardIDs.compactMap { findCard(by: $0) }
            guard selected.count == selectedCardIDs.count else { return [contextCard] }
            return sortedCardsByCanvasOrder(selected)
        }
        return [contextCard]
    }

    func sortedCardsByCanvasOrder(_ cards: [SceneCard]) -> [SceneCard] {
        let rank = buildCanvasRank()
        return cards.sorted { lhs, rhs in
            let l = rank[lhs.id] ?? (Int.max, Int.max)
            let r = rank[rhs.id] ?? (Int.max, Int.max)
            if l.0 != r.0 { return l.0 < r.0 }
            if l.1 != r.1 { return l.1 < r.1 }
            return lhs.createdAt < rhs.createdAt
        }
    }

    func handleFountainClipboardPasteShortcutIfPossible(from textView: NSTextView) -> Bool {
        guard let preview = loadFountainClipboardPastePreview() else { return false }
        fountainClipboardPasteSourceTextViewBox.textView = textView
        pendingFountainClipboardPastePreview = preview
        showFountainClipboardPasteDialog = true
        return true
    }

    func loadFountainClipboardPastePreview() -> FountainClipboardPastePreview? {
        let pasteboard = NSPasteboard.general
        guard let rawText = pasteboard.string(forType: .string) else { return nil }
        guard let importPayload = parseFountainClipboardImport(from: rawText) else { return nil }
        return FountainClipboardPastePreview(rawText: rawText, importPayload: importPayload)
    }

    func cancelFountainClipboardPasteDialog() {
        showFountainClipboardPasteDialog = false
        restoreFountainClipboardPasteTextFocusIfNeeded()
    }

    func applyFountainClipboardPasteSelection(_ option: StructuredTextPasteOption) {
        guard let preview = pendingFountainClipboardPastePreview else {
            cancelFountainClipboardPasteDialog()
            return
        }

        showFountainClipboardPasteDialog = false

        switch option {
        case .plainText:
            pasteRawTextIntoFountainClipboardSource(preview.rawText)
        case .sceneCards:
            insertFountainClipboardImportCards(preview.importPayload)
        }
    }

    func restoreFountainClipboardPasteTextFocusIfNeeded() {
        guard let textView = fountainClipboardPasteSourceTextViewBox.textView else { return }
        DispatchQueue.main.async {
            guard let window = textView.window else { return }
            window.makeFirstResponder(textView)
        }
    }

    func pasteRawTextIntoFountainClipboardSource(_ rawText: String) {
        guard let textView = fountainClipboardPasteSourceTextViewBox.textView else { return }
        DispatchQueue.main.async {
            guard let window = textView.window else { return }
            window.makeFirstResponder(textView)
            textView.insertText(rawText, replacementRange: textView.selectedRange())
        }
    }

    func canReuseEditingCardForFountainClipboardImport() -> Bool {
        guard let editingID = editingCardID,
              let editingCard = findCard(by: editingID) else { return false }
        guard editingCard.children.isEmpty else { return false }
        return editingCard.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func insertFountainClipboardImportCards(_ importPayload: FountainClipboardImport) {
        let cardContents = importPayload.cardContents
        guard !cardContents.isEmpty else { return }

        let reuseEditingCard = canReuseEditingCardForFountainClipboardImport()
        let anchorCardID = editingCardID ?? activeCardID

        if reuseEditingCard {
            if showFocusMode {
                finalizeFocusTypingCoalescing(reason: "fountain-import")
                focusModeEditorCardID = nil
            } else {
                finalizeMainTypingCoalescing(reason: "fountain-import")
            }
            resetEditingTransientState()
        } else if editingCardID != nil {
            finishEditing()
            if showFocusMode {
                focusModeEditorCardID = nil
            }
        }

        let prevState = captureScenarioState()
        guard let anchorCard = anchorCardID.flatMap({ findCard(by: $0) }) ?? activeCardID.flatMap({ findCard(by: $0) }) else {
            insertRootLevelFountainClipboardCards(cardContents, previousState: prevState)
            return
        }

        var insertedCards: [SceneCard] = []
        insertedCards.reserveCapacity(cardContents.count)

        if reuseEditingCard {
            anchorCard.content = cardContents[0]
            insertedCards.append(anchorCard)
            let trailingContents = Array(cardContents.dropFirst())
            appendFountainClipboardCards(
                trailingContents,
                parent: anchorCard.parent,
                insertionIndex: anchorCard.orderIndex + 1,
                category: anchorCard.category,
                accumulator: &insertedCards
            )
            normalizeIndices(parent: anchorCard.parent)
        } else {
            appendFountainClipboardCards(
                cardContents,
                parent: anchorCard.parent,
                insertionIndex: anchorCard.orderIndex + 1,
                category: anchorCard.category,
                accumulator: &insertedCards
            )
            normalizeIndices(parent: anchorCard.parent)
        }

        completeFountainClipboardImport(
            insertedCards,
            previousState: prevState
        )
    }

    func insertRootLevelFountainClipboardCards(_ cardContents: [String], previousState: ScenarioState) {
        var insertedCards: [SceneCard] = []
        insertedCards.reserveCapacity(cardContents.count)
        appendFountainClipboardCards(
            cardContents,
            parent: nil,
            insertionIndex: scenario.rootCards.count,
            category: nil,
            accumulator: &insertedCards
        )
        normalizeIndices(parent: nil)
        completeFountainClipboardImport(
            insertedCards,
            previousState: previousState
        )
    }

    func appendFountainClipboardCards(
        _ contents: [String],
        parent: SceneCard?,
        insertionIndex: Int,
        category: String?,
        accumulator: inout [SceneCard]
    ) {
        guard !contents.isEmpty else { return }

        let siblings = parent?.sortedChildren ?? scenario.rootCards
        for sibling in siblings where sibling.orderIndex >= insertionIndex {
            sibling.orderIndex += contents.count
        }

        for (offset, content) in contents.enumerated() {
            let card = SceneCard(
                content: content,
                orderIndex: insertionIndex + offset,
                createdAt: Date(),
                parent: parent,
                scenario: scenario,
                category: parent?.category ?? category,
                isFloating: false,
                isArchived: false,
                lastSelectedChildID: nil,
                colorHex: nil,
                cloneGroupID: nil,
                isAICandidate: false
            )
            scenario.cards.append(card)
            accumulator.append(card)
        }
    }

    func completeFountainClipboardImport(
        _ insertedCards: [SceneCard],
        previousState: ScenarioState
    ) {
        guard !insertedCards.isEmpty else { return }

        scenario.bumpCardsVersion()
        commitCardMutation(
            previousState: previousState,
            actionName: "파운틴 카드 붙여넣기",
            forceSnapshot: true
        )

        selectedCardIDs = Set(insertedCards.map { $0.id })
        if let first = insertedCards.first {
            changeActiveCard(to: first, shouldFocusMain: false)
        }
        if !showFocusMode {
            isMainViewFocused = true
        }
    }

    func handlePasteShortcut() {
        if pasteCutCardTreeIfPossible() {
            return
        }
        if let clonePayload = loadCopiedCloneCardPayload(), !clonePayload.items.isEmpty {
            pendingCloneCardPastePayload = clonePayload
            pendingCardTreePastePayload = nil
            showCloneCardPasteDialog = true
            return
        }
        if let cardTreePayload = loadCopiedCardTreePayload(), !cardTreePayload.roots.isEmpty {
            pendingCardTreePastePayload = cardTreePayload
            pendingCloneCardPastePayload = nil
            showCloneCardPasteDialog = true
        }
    }

    func applyPendingPastePlacement(as placement: ClonePastePlacement) {
        if let payload = pendingCloneCardPastePayload {
            pendingCloneCardPastePayload = nil
            pendingCardTreePastePayload = nil
            showCloneCardPasteDialog = false
            pasteCloneCardPayload(payload, placement: placement)
            return
        }
        if let payload = pendingCardTreePastePayload {
            pendingCloneCardPastePayload = nil
            pendingCardTreePastePayload = nil
            showCloneCardPasteDialog = false
            pasteCardTreePayload(payload, placement: placement)
            return
        }
        pendingCloneCardPastePayload = nil
        pendingCardTreePastePayload = nil
        showCloneCardPasteDialog = false
    }

    func cancelPendingPastePlacement() {
        pendingCloneCardPastePayload = nil
        pendingCardTreePastePayload = nil
        showCloneCardPasteDialog = false
    }

    func applyPendingCloneCardPaste(as placement: ClonePastePlacement) {
        applyPendingPastePlacement(as: placement)
    }

    func cancelPendingCloneCardPaste() {
        cancelPendingPastePlacement()
    }

    func pasteCloneCardPayload(
        _ payload: CloneCardClipboardPayload,
        placement: ClonePastePlacement
    ) {
        guard !payload.items.isEmpty else { return }

        let prevState = captureScenarioState()
        let destination = resolvePasteDestination(for: placement)
        let destinationParent = destination.parent
        let insertionIndex = destination.insertionIndex

        let destinationSiblings = destinationParent?.sortedChildren ?? scenario.rootCards
        for sibling in destinationSiblings where sibling.orderIndex >= insertionIndex {
            sibling.orderIndex += payload.items.count
        }

        var insertedCards: [SceneCard] = []
        insertedCards.reserveCapacity(payload.items.count)

        for (offset, item) in payload.items.enumerated() {
            let source = resolveClonePasteSource(item, sourceScenarioID: payload.sourceScenarioID)
            let newCard = SceneCard(
                content: source.content,
                orderIndex: insertionIndex + offset,
                createdAt: Date(),
                parent: destinationParent,
                scenario: scenario,
                category: destinationParent?.category,
                isFloating: false,
                isArchived: false,
                lastSelectedChildID: nil,
                colorHex: source.colorHex,
                cloneGroupID: source.cloneGroupID,
                isAICandidate: source.isAICandidate
            )
            scenario.cards.append(newCard)
            insertedCards.append(newCard)
        }

        normalizeIndices(parent: destinationParent)
        scenario.bumpCardsVersion()
        selectedCardIDs = Set(insertedCards.map { $0.id })
        if let first = insertedCards.first {
            changeActiveCard(to: first)
        }
        commitCardMutation(
            previousState: prevState,
            actionName: "클론 카드 붙여넣기"
        )
    }

    func resolvePasteDestination(for placement: ClonePastePlacement) -> (parent: SceneCard?, insertionIndex: Int) {
        guard let active = activeCardID.flatMap({ findCard(by: $0) }) else {
            return (nil, scenario.rootCards.count)
        }

        switch placement {
        case .child:
            return (active, active.children.count)
        case .sibling:
            return (active.parent, active.orderIndex + 1)
        }
    }

    func resolveClonePasteDestination(for placement: ClonePastePlacement) -> (parent: SceneCard?, insertionIndex: Int) {
        resolvePasteDestination(for: placement)
    }

    func resolveClonePasteSource(
        _ item: CloneCardClipboardItem,
        sourceScenarioID: UUID
    ) -> (content: String, colorHex: String?, isAICandidate: Bool, cloneGroupID: UUID) {
        if sourceScenarioID == scenario.id,
           let sourceCard = findCard(by: item.sourceCardID),
           !sourceCard.isArchived {
            let resolvedGroupID: UUID
            if let existing = sourceCard.cloneGroupID {
                resolvedGroupID = existing
            } else {
                let created = item.cloneGroupID ?? UUID()
                sourceCard.cloneGroupID = created
                resolvedGroupID = created
            }
            return (
                content: sourceCard.content,
                colorHex: sourceCard.colorHex,
                isAICandidate: sourceCard.isAICandidate,
                cloneGroupID: resolvedGroupID
            )
        }

        return (
            content: item.content,
            colorHex: item.colorHex,
            isAICandidate: item.isAICandidate,
            cloneGroupID: item.cloneGroupID ?? UUID()
        )
    }

    func pasteCopiedCardTree() {
        if pasteCutCardTreeIfPossible() {
            return
        }

        guard let payload = loadCopiedCardTreePayload() else { return }
        guard !payload.roots.isEmpty else { return }
        pasteCardTreePayload(payload, placement: .child)
    }

    func pasteCardTreePayload(
        _ payload: CardTreeClipboardPayload,
        placement: ClonePastePlacement
    ) {
        guard !payload.roots.isEmpty else { return }

        let prevState = captureScenarioState()

        let destination = resolvePasteDestination(for: placement)
        let destinationParent = destination.parent
        let insertionIndex = destination.insertionIndex

        let destinationSiblings = destinationParent?.sortedChildren ?? scenario.rootCards
        for sibling in destinationSiblings where sibling.orderIndex >= insertionIndex {
            sibling.orderIndex += payload.roots.count
        }

        var newRootCards: [SceneCard] = []
        newRootCards.reserveCapacity(payload.roots.count)
        for (offset, rootNode) in payload.roots.enumerated() {
            let newRoot = instantiateClipboardNode(
                rootNode,
                parent: destinationParent,
                orderIndex: insertionIndex + offset
            )
            newRoot.updateDescendantsCategory(destinationParent?.category)
            newRootCards.append(newRoot)
        }

        normalizeIndices(parent: destinationParent)
        scenario.bumpCardsVersion()
        selectedCardIDs = Set(newRootCards.map { $0.id })
        if let first = newRootCards.first {
            changeActiveCard(to: first)
        }

        commitCardMutation(
            previousState: prevState,
            actionName: "카드 붙여넣기"
        )
    }

    func copySourceRootCards() -> [SceneCard] {
        let selected = selectedCardsForDeletion()
        guard !selected.isEmpty else { return [] }
        return movableRoots(from: selected)
    }

    func persistCardTreePayloadToClipboard(_ payload: CardTreeClipboardPayload) -> Bool {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload) else { return false }

        copiedCardTreePayloadData = data
        copiedCloneCardPayloadData = nil
        pendingCloneCardPastePayload = nil
        pendingCardTreePastePayload = nil
        showCloneCardPasteDialog = false

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([waCardTreePasteboardType], owner: nil)
        pasteboard.setData(data, forType: waCardTreePasteboardType)
        return true
    }

    func persistCloneCardPayloadToClipboard(_ payload: CloneCardClipboardPayload) -> Bool {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload) else { return false }

        copiedCloneCardPayloadData = data
        copiedCardTreePayloadData = nil
        pendingCloneCardPastePayload = nil
        pendingCardTreePastePayload = nil
        showCloneCardPasteDialog = false

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([waCloneCardPasteboardType], owner: nil)
        pasteboard.setData(data, forType: waCloneCardPasteboardType)
        return true
    }

    func clearCutCardTreeBuffer() {
        cutCardRootIDs = []
        cutCardSourceScenarioID = nil
    }

    func resolvedCardTreePasteDestination() -> (parent: SceneCard?, insertionIndex: Int) {
        if let active = activeCardID.flatMap({ findCard(by: $0) }) {
            return (active, active.children.count)
        }
        return (nil, scenario.rootCards.count)
    }

    func pasteCutCardTreeIfPossible() -> Bool {
        guard cutCardSourceScenarioID == scenario.id else { return false }
        guard !cutCardRootIDs.isEmpty else { return false }

        let roots = cutCardRootIDs.compactMap { findCard(by: $0) }
        guard roots.count == cutCardRootIDs.count else { return false }
        let movingRoots = movableRoots(from: roots)
        guard !movingRoots.isEmpty else { return false }
        guard let draggedCard = movingRoots.first else { return false }

        if let active = activeCardID.flatMap({ findCard(by: $0) }) {
            if movingRoots.contains(where: { $0.id == active.id }) { return false }
            if movingRoots.contains(where: { isDescendant($0, of: active.id) }) { return false }
            executeMoveSelection(movingRoots, draggedCard: draggedCard, target: .onto(active.id))
        } else {
            executeMoveSelection(movingRoots, draggedCard: draggedCard, target: .columnBottom(nil))
        }

        clearCutCardTreeBuffer()
        return true
    }

    func encodeClipboardNode(from card: SceneCard) -> CardTreeClipboardNode {
        CardTreeClipboardNode(
            content: card.content,
            colorHex: card.colorHex,
            isAICandidate: card.isAICandidate,
            children: card.sortedChildren.map { encodeClipboardNode(from: $0) }
        )
    }

    func instantiateClipboardNode(
        _ node: CardTreeClipboardNode,
        parent: SceneCard?,
        orderIndex: Int
    ) -> SceneCard {
        let card = SceneCard(
            content: node.content,
            orderIndex: orderIndex,
            createdAt: Date(),
            parent: parent,
            scenario: scenario,
            category: parent?.category,
            isFloating: false,
            isArchived: false,
            lastSelectedChildID: nil,
            colorHex: node.colorHex,
            isAICandidate: node.isAICandidate
        )
        scenario.cards.append(card)

        for (childIndex, childNode) in node.children.enumerated() {
            _ = instantiateClipboardNode(childNode, parent: card, orderIndex: childIndex)
        }
        return card
    }

    func loadCopiedCardTreePayload() -> CardTreeClipboardPayload? {
        let decoder = JSONDecoder()
        let pasteboard = NSPasteboard.general

        if let data = pasteboard.data(forType: waCardTreePasteboardType),
           let payload = try? decoder.decode(CardTreeClipboardPayload.self, from: data) {
            copiedCardTreePayloadData = data
            return payload
        }

        if let cached = copiedCardTreePayloadData,
           let payload = try? decoder.decode(CardTreeClipboardPayload.self, from: cached) {
            return payload
        }

        return nil
    }

    func loadCopiedCloneCardPayload() -> CloneCardClipboardPayload? {
        let decoder = JSONDecoder()
        let pasteboard = NSPasteboard.general

        if let data = pasteboard.data(forType: waCloneCardPasteboardType),
           let payload = try? decoder.decode(CloneCardClipboardPayload.self, from: data) {
            copiedCloneCardPayloadData = data
            return payload
        }

        if let cached = copiedCloneCardPayloadData,
           let payload = try? decoder.decode(CloneCardClipboardPayload.self, from: cached) {
            return payload
        }

        return nil
    }

    func exportToFile() {
        let txt = buildExportText()
        if txt.isEmpty {
            exportMessage = "출력할 내용이 없습니다."
            showExportAlert = true
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(scenario.title)_출력.txt"
        panel.begin { res in
            guard res == .OK, let url = panel.url else { return }
            try? txt.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    func exportToCenteredPDF() {
        exportToPDF(format: .centered, defaultName: "\(scenario.title)_중앙정렬식.pdf")
    }
    func exportToKoreanPDF() {
        exportToPDF(format: .korean, defaultName: "\(scenario.title)_한국식.pdf")
    }
    func exportToPDF(format: ScriptExportFormatType, defaultName: String) {
        let txt = buildExportText()
        if txt.isEmpty {
            exportMessage = "출력할 내용이 없습니다."
            showExportAlert = true
            return
        }
        let parser = ScriptMarkdownParser(formatType: format)
        let elements = parser.parse(txt)
        var pdfConfig = ScriptExportLayoutConfig()
        pdfConfig.centeredFontSize = CGFloat(exportCenteredFontSize)
        pdfConfig.centeredIsCharacterBold = exportCenteredCharacterBold
        pdfConfig.centeredIsSceneHeadingBold = exportCenteredSceneHeadingBold
        pdfConfig.centeredShowRightSceneNumber = exportCenteredShowRightSceneNumber
        pdfConfig.koreanFontSize = CGFloat(exportKoreanFontSize)
        pdfConfig.koreanIsSceneBold = exportKoreanSceneBold
        pdfConfig.koreanIsCharacterBold = exportKoreanCharacterBold
        pdfConfig.koreanCharacterAlignment = exportKoreanCharacterAlignment == "left" ? .left : .right

        let generator = ScriptPDFGenerator(format: format, config: pdfConfig)
        let data = generator.generatePDF(from: elements)
        if data.isEmpty {
            exportMessage = "PDF 생성에 실패했습니다."
            showExportAlert = true
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = defaultName
        panel.begin { res in
            if res == .OK, let url = panel.url {
                do {
                    try data.write(to: url)
                } catch {
                    exportMessage = "PDF 저장에 실패했습니다."
                    showExportAlert = true
                }
            }
        }
    }
    
    func toggleTimeline() { 
        withAnimation(quickEaseAnimation) { 
            showTimeline.toggle()
            if showTimeline {
                showHistoryBar = false
                showAIChat = false
                exitPreviewMode()
            } else { 
                exitPreviewMode()
                searchText = ""
                linkedCardsFilterEnabled = false
                linkedCardAnchorID = nil
                isSearchFocused = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isMainViewFocused = true } 
            } 
        } 
    }

    // MARK: - Search & Add Card

    func openSearch() {
        withAnimation(quickEaseAnimation) { 
            showTimeline = true 
            showAIChat = false
            showHistoryBar = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isSearchFocused = true
        }
    }
    func closeSearch() {
        withAnimation(quickEaseAnimation) {
            showTimeline = false
            searchText = ""
            linkedCardsFilterEnabled = false
            linkedCardAnchorID = nil
            isSearchFocused = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isMainViewFocused = true
        }
    }
    func toggleSearch() {
        if showTimeline {
            closeSearch()
        } else {
            openSearch()
        }
    }

    func addCard(at level: Int, parent: SceneCard?) {
        let prevState = captureScenarioState()
        if showFocusMode {
            finalizeFocusTypingCoalescing(reason: "add-card")
            pushFocusUndoState(prevState, actionName: "카드 추가")
        }
        let new = SceneCard(orderIndex: parent?.children.count ?? scenario.rootCards.count, parent: parent, scenario: scenario, category: parent?.category)
        scenario.cards.append(new)
        scenario.bumpCardsVersion()
        saveWriterChanges()
        selectedCardIDs = [new.id]
        changeActiveCard(to: new, shouldFocusMain: false)
        editingCardID = new.id
        editingStartContent = new.content
        editingIsNewCard = true
        pendingNewCardPrevState = prevState
    }

    // MARK: - Insert, Add Child, Delete

    func sortedCardsForUpperCardCreation(_ cards: [SceneCard]) -> [SceneCard]? {
        guard !cards.isEmpty else { return nil }
        let parentID = cards.first?.parent?.id
        guard cards.allSatisfy({ !$0.isArchived && $0.parent?.id == parentID }) else { return nil }
        return cards.sorted { lhs, rhs in
            if lhs.orderIndex != rhs.orderIndex {
                return lhs.orderIndex < rhs.orderIndex
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    func selectedSiblingsForParentCreation(contextCard: SceneCard) -> [SceneCard]? {
        guard !showFocusMode else { return nil }
        guard !contextCard.isArchived else { return nil }
        if selectedCardIDs.count > 1 {
            guard selectedCardIDs.contains(contextCard.id) else { return nil }
            let selectedCards = selectedCardIDs.compactMap { findCard(by: $0) }
            guard selectedCards.count == selectedCardIDs.count else { return nil }
            return sortedCardsForUpperCardCreation(selectedCards)
        }
        return [contextCard]
    }

    func canCreateUpperCardFromSelection(contextCard: SceneCard) -> Bool {
        guard !showFocusMode else { return false }
        guard !contextCard.isArchived else { return false }
        if selectedCardIDs.count <= 1 {
            return true
        }
        guard selectedCardIDs.contains(contextCard.id) else { return false }
        let selectedCards = selectedCardIDs.compactMap { findCard(by: $0) }
        guard selectedCards.count == selectedCardIDs.count else { return false }
        return sortedCardsForUpperCardCreation(selectedCards) != nil
    }

    func upperCardCreationRequest(contextCard: SceneCard) -> UpperCardCreationRequest? {
        guard let sourceCards = selectedSiblingsForParentCreation(contextCard: contextCard) else { return nil }
        return UpperCardCreationRequest(
            contextCardID: contextCard.id,
            sourceCardIDs: sourceCards.map(\.id)
        )
    }

    func createUpperCardFromSelection(contextCard: SceneCard) {
        guard let request = upperCardCreationRequest(contextCard: contextCard) else { return }
        pendingUpperCardCreationRequest = request
    }

    func upperCardCreationSiblingLayout(
        parent: SceneCard?,
        selectedSiblings: [SceneCard],
        newParent: SceneCard,
        oldSiblings: [SceneCard]
    ) -> [SceneCard]? {
        guard let firstSelected = selectedSiblings.first,
              let insertionIndex = oldSiblings.firstIndex(where: { $0.id == firstSelected.id }) else {
            return nil
        }

        let selectedIDs = Set(selectedSiblings.map(\.id))
        var finalSiblings: [SceneCard] = []
        finalSiblings.reserveCapacity(max(1, oldSiblings.count - selectedSiblings.count + 1))

        for (index, sibling) in oldSiblings.enumerated() {
            if index == insertionIndex {
                finalSiblings.append(newParent)
            }
            guard !selectedIDs.contains(sibling.id) else { continue }
            guard sibling.parent?.id == parent?.id else { continue }
            finalSiblings.append(sibling)
        }

        if insertionIndex >= oldSiblings.count {
            finalSiblings.append(newParent)
        }

        return finalSiblings
    }

    @discardableResult
    func createUpperCardFromSourceCards(
        _ sourceCards: [SceneCard],
        initialContent: String,
        startEditing: Bool,
        actionName: String
    ) -> SceneCard? {
        guard let selectedSiblings = sortedCardsForUpperCardCreation(sourceCards),
              let firstSelected = selectedSiblings.first else { return nil }
        let parent = firstSelected.parent
        let oldSiblings = liveOrderedSiblings(parent: parent)
        let prevState = captureScenarioState()
        suppressMainFocusRestoreAfterFinishEditing = true
        finishEditing()

        let insertionIndex = firstSelected.orderIndex
        let newParent = SceneCard(
            content: initialContent,
            orderIndex: insertionIndex,
            parent: parent,
            scenario: scenario,
            category: parent?.category ?? firstSelected.category
        )

        guard let finalOldSiblings = upperCardCreationSiblingLayout(
            parent: parent,
            selectedSiblings: selectedSiblings,
            newParent: newParent,
            oldSiblings: oldSiblings
        ) else {
            return nil
        }

        scenario.performBatchedCardMutation {
            scenario.cards.append(newParent)

            for (childIndex, selectedCard) in selectedSiblings.enumerated() {
                selectedCard.parent = newParent
                if selectedCard.orderIndex != childIndex {
                    selectedCard.orderIndex = childIndex
                }
            }

            for (index, sibling) in finalOldSiblings.enumerated() {
                if sibling.orderIndex != index {
                    sibling.orderIndex = index
                }
            }
        }

        keyboardRangeSelectionAnchorCardID = nil
        selectedCardIDs = [newParent.id]
        changeActiveCard(to: newParent, shouldFocusMain: false)
        if startEditing {
            editingCardID = newParent.id
            editingStartContent = newParent.content
            editingStartState = captureScenarioState()
            editingIsNewCard = false
            restoreMainEditingCaret(
                for: newParent.id,
                location: (newParent.content as NSString).length
            )
        } else {
            editingCardID = nil
        }
        pendingNewCardPrevState = nil
        isMainViewFocused = true
        commitCardMutation(previousState: prevState, actionName: actionName)
        return newParent
    }

    func createEmptyUpperCard(from request: UpperCardCreationRequest) {
        pendingUpperCardCreationRequest = nil
        let sourceCards = request.sourceCardIDs.compactMap { findCard(by: $0) }
        guard sourceCards.count == request.sourceCardIDs.count else {
            setAIStatusError("원본 카드 상태가 바뀌어 상위 카드를 만들 수 없습니다.")
            return
        }
        _ = createUpperCardFromSourceCards(
            sourceCards,
            initialContent: "",
            startEditing: true,
            actionName: "새 상위 카드 만들기"
        )
    }

    @discardableResult
    func createUpperCardWithResolvedSummary(sourceCards: [SceneCard], summary: String) -> SceneCard? {
        createUpperCardFromSourceCards(
            sourceCards,
            initialContent: summary,
            startEditing: false,
            actionName: "AI 요약 상위 카드 만들기"
        )
    }

    func canSummarizeDirectChildren(for parentCard: SceneCard) -> Bool {
        guard !showFocusMode else { return false }
        return parentCard.children.count >= 2
    }

    func summarizeDirectChildrenIntoParent(cardID: UUID) {
        guard !showFocusMode else { return }
        guard !aiChildSummaryLoadingCardIDs.contains(cardID) else { return }
        guard !aiIsGenerating else {
            setAIStatusError("이미 다른 AI 작업이 진행 중입니다.")
            return
        }
        guard let parentCard = findCard(by: cardID) else { return }
        let directChildren = parentCard.children.sorted {
            if $0.orderIndex != $1.orderIndex { return $0.orderIndex < $1.orderIndex }
            return $0.createdAt < $1.createdAt
        }
        guard directChildren.count >= 2 else {
            setAIStatusError("요약하려면 하위 카드가 2개 이상 필요합니다.")
            return
        }

        suppressMainFocusRestoreAfterFinishEditing = true
        finishEditing()

        let prompt = buildChildCardsSummaryPrompt(parentCard: parentCard, directChildren: directChildren)
        let resolvedModel = currentGeminiModel()

        aiIsGenerating = true
        aiChildSummaryLoadingCardIDs.insert(parentCard.id)
        setAIStatus("하위 카드 요약을 생성하는 중입니다...")

        Task { @MainActor in
            defer {
                aiIsGenerating = false
                aiChildSummaryLoadingCardIDs.remove(parentCard.id)
            }

            do {
                guard let latestParent = findCard(by: parentCard.id) else { return }
                guard let apiKey = try KeychainStore.loadGeminiAPIKey() else {
                    throw GeminiServiceError.missingAPIKey
                }
                let rawSummary = try await GeminiService.generateText(
                    prompt: prompt,
                    model: resolvedModel,
                    apiKey: apiKey
                )
                let summary = normalizedChildSummaryOutput(rawSummary)
                guard !summary.isEmpty else {
                    throw GeminiServiceError.invalidResponse
                }

                let prevState = captureScenarioState()
                let blockTitle = "하위 카드 요약"
                let block = "\(blockTitle)\n\(summary)"
                if latestParent.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    latestParent.content = block
                } else {
                    latestParent.content += "\n\n\(block)"
                }

                scenario.bumpCardsVersion()
                commitCardMutation(
                    previousState: prevState,
                    actionName: "하위 카드 요약",
                    forceSnapshot: true
                )

                selectedCardIDs = [latestParent.id]
                changeActiveCard(to: latestParent, shouldFocusMain: false)
                editingCardID = latestParent.id
                editingStartContent = latestParent.content
                editingStartState = captureScenarioState()
                editingIsNewCard = false
                pendingNewCardPrevState = nil
                restoreMainEditingCaret(
                    for: latestParent.id,
                    location: (latestParent.content as NSString).length
                )
                isMainViewFocused = true

                setAIStatus("하위 카드 요약을 카드 하단에 추가했습니다.")
            } catch {
                setAIStatusError(error.localizedDescription)
            }
        }
    }

    func buildChildCardsSummaryPrompt(parentCard _: SceneCard, directChildren: [SceneCard]) -> String {
        let orderedChildrenText = directChildren.enumerated().map { idx, child in
            let content = clampedAIText(child.content, maxLength: 1400, preserveLineBreak: true)
            return "\(idx + 1). \(content)"
        }.joined(separator: "\n\n")
        return renderEntityDenseSummaryPrompt(articleText: orderedChildrenText)
    }

    func normalizedChildSummaryOutput(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\t", with: " ")
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }

    func splitCardAtCaret() {
        let prevState = captureScenarioState()
        guard let id = editingCardID ?? activeCardID,
              let card = findCard(by: id) else { return }
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        guard !textView.hasMarkedText() else { return }

        if showFocusMode {
            finalizeFocusTypingCoalescing(reason: "split-card")
            pushFocusUndoState(prevState, actionName: "카드 나누기")
        }

        let sourceText = textView.string as NSString
        let splitLocation = min(max(0, textView.selectedRange().location), sourceText.length)
        let upperContent = sourceText.substring(to: splitLocation)
        let lowerContent = sourceText.substring(from: splitLocation)

        let targetOrderIndex = card.orderIndex + 1
        for sibling in (card.parent?.sortedChildren ?? scenario.rootCards) where sibling.orderIndex >= targetOrderIndex {
            sibling.orderIndex += 1
        }

        card.content = upperContent
        let new = SceneCard(orderIndex: targetOrderIndex, parent: card.parent, scenario: scenario, category: card.category)
        new.content = lowerContent
        scenario.cards.append(new)
        scenario.bumpCardsVersion()
        saveWriterChanges()

        selectedCardIDs = [new.id]
        changeActiveCard(to: new, shouldFocusMain: false)
        editingCardID = new.id
        editingStartContent = new.content
        editingIsNewCard = true
        pendingNewCardPrevState = prevState

        if showFocusMode {
            focusModeEditorCardID = new.id
            DispatchQueue.main.async {
                beginFocusModeEditing(new, cursorToEnd: false, cardScrollAnchor: .center)
            }
        } else {
            restoreMainEditingCaret(for: new.id, location: 0)
        }
    }

    func insertSibling(relativeTo card: SceneCard, above: Bool) {
        let prevState = captureScenarioState()
        if showFocusMode {
            finalizeFocusTypingCoalescing(reason: "insert-sibling")
            pushFocusUndoState(prevState, actionName: "카드 추가")
        }
        let target = above ? card.orderIndex : card.orderIndex + 1
        for s in (card.parent?.sortedChildren ?? scenario.rootCards) where s.orderIndex >= target { s.orderIndex += 1 }
        let new = SceneCard(orderIndex: target, parent: card.parent, scenario: scenario, category: card.category)
        scenario.cards.append(new)
        scenario.bumpCardsVersion()
        saveWriterChanges()
        selectedCardIDs = [new.id]
        changeActiveCard(to: new, shouldFocusMain: false)
        editingCardID = new.id
        editingStartContent = new.content
        editingIsNewCard = true
        pendingNewCardPrevState = prevState
        if showFocusMode {
            focusModeEditorCardID = new.id
            DispatchQueue.main.async {
                beginFocusModeEditing(new, cursorToEnd: false, cardScrollAnchor: .center)
            }
        }
    }

    func insertSibling(above: Bool) {
        guard let id = activeCardID, let card = findCard(by: id) else { return }
        insertSibling(relativeTo: card, above: above)
    }

    func addChildCard(to card: SceneCard) {
        let prevState = captureScenarioState()
        if showFocusMode {
            finalizeFocusTypingCoalescing(reason: "add-child")
            pushFocusUndoState(prevState, actionName: "카드 추가")
        }
        let new = SceneCard(orderIndex: card.children.count, parent: card, scenario: scenario, category: card.category)
        scenario.cards.append(new)
        scenario.bumpCardsVersion()
        saveWriterChanges()
        selectedCardIDs = [new.id]
        changeActiveCard(to: new, shouldFocusMain: false)
        editingCardID = new.id
        editingStartContent = new.content
        editingIsNewCard = true
        pendingNewCardPrevState = prevState
    }

    func addChildCard() {
        guard let id = activeCardID, let card = findCard(by: id) else { return }
        addChildCard(to: card)
    }

    func addCardToReferenceWindow(_ card: SceneCard) {
        referenceCardStore.addCard(cardID: card.id, scenarioID: scenario.id)
        openWindow(id: ReferenceWindowConstants.windowID)
    }

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
        finishEditing()
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
        finishEditing()

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
        finishEditing()
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
        finishEditing()
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
        finishEditing()
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

    func setCardColor(_ card: SceneCard, hex: String?) {
        let prevState = captureScenarioState()
        card.colorHex = hex
        commitCardMutation(
            previousState: prevState,
            actionName: "카드 색상"
        )
    }
}
