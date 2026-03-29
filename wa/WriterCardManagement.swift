import SwiftUI
import AppKit
import QuartzCore
import UniformTypeIdentifiers

extension ScenarioWriterView {

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
        if !shouldAllowActiveCardChangeDuringEditing(to: card.id, force: force) {
            mainWorkspacePhase0Log(
                "active-card-change-suppressed",
                "target=\(mainWorkspacePhase0CardID(card.id)) active=\(mainWorkspacePhase0CardID(activeCardID)) " +
                "editing=\(mainWorkspacePhase0CardID(editingCardID)) " +
                "pendingBoundary=\(mainWorkspacePhase0CardID(pendingMainEditingBoundaryNavigationTargetID)) " +
                "pendingSibling=\(mainWorkspacePhase0CardID(pendingMainEditingSiblingNavigationTargetID))"
            )
            return
        }
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
        MainCanvasNavigationDiagnostics.shared.beginActiveCardMutation(
            ownerKey: mainCanvasDiagnosticsOwnerKey,
            requestedCardID: card.id
        )
        pendingActiveCardID = card.id
        let apply = {
            let applyStartedAt = CACurrentMediaTime()
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
            mainWorkspacePhase0Log(
                "active-card-change",
                "previous=\(mainWorkspacePhase0CardID(previousActiveID)) active=\(mainWorkspacePhase0CardID(activeCardID)) " +
                "editing=\(mainWorkspacePhase0CardID(editingCardID)) shouldFocusMain=\(shouldFocusMain)"
            )
            MainCanvasNavigationDiagnostics.shared.recordActiveCardMutationApplied(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                activeCardID: activeCardID,
                durationMilliseconds: (CACurrentMediaTime() - applyStartedAt) * 1000
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
        finishEditing(reason: .transition)
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

    func takeFinishEditingContext(reason: FinishEditingReason) -> FinishEditingContext? {
        guard let id = editingCardID else { return nil }
        if shouldSuppressFinishEditingDuringEntryGuard(cardID: id, reason: reason) {
            mainWorkspacePhase0Log(
                "take-finish-editing-context-suppressed",
                "card=\(mainWorkspacePhase0CardID(id)) reason=entryGuard responder=\(mainWorkspacePhase0ResponderSummary(expectedText: findCard(by: id)?.content)) " +
                "stack=\(relevantFinishEditingCallStackSummary())"
            )
            return nil
        }
        if reason == .generic, !shouldAllowGenericFinishEditing(cardID: id) {
            mainWorkspacePhase0Log(
                "take-finish-editing-context-suppressed",
                "card=\(mainWorkspacePhase0CardID(id)) reason=genericAuthority responder=\(mainWorkspacePhase0ResponderSummary(expectedText: findCard(by: id)?.content)) " +
                "stack=\(relevantFinishEditingCallStackSummary())"
            )
            return nil
        }
        let inFocusMode = showFocusMode
        let skipMainFocusRestore = suppressMainFocusRestoreAfterFinishEditing || inFocusMode
        suppressMainFocusRestoreAfterFinishEditing = false
        if inFocusMode {
            finalizeFocusTypingCoalescing(reason: "finish-editing")
        }
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
        mainWorkspacePhase0Log(
            "take-finish-editing-context",
            "card=\(mainWorkspacePhase0CardID(id)) active=\(mainWorkspacePhase0CardID(activeCardID)) " +
            "reason=\(reason.rawValue) skipMainFocusRestore=\(skipMainFocusRestore) responder=\(mainWorkspacePhase0ResponderSummary(expectedText: findCard(by: id)?.content)) " +
            "stack=\(relevantFinishEditingCallStackSummary())"
        )
        resetEditingTransientState()
        return context
    }

    private func resignMainEditorFirstResponderIfNeeded(for cardID: UUID?) {
        if let textView = resolvedActiveMainEditorTextView(for: cardID) {
            textView.window?.makeFirstResponder(nil)
            return
        }
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        guard textView.isEditable else { return }
        guard let textViewIdentity = mainEditorSession.textViewIdentity else { return }
        guard ObjectIdentifier(textView).hashValue == textViewIdentity else { return }
        textView.window?.makeFirstResponder(nil)
    }

    func resetEditingTransientState() {
        let editingID = editingCardID
        clearMainEditorEntryFinishGuard(ifMatching: editingID)
        clearMainEditingScrollIsolation(reason: "resetEditingTransientState")
        resignMainEditorFirstResponderIfNeeded(for: editingID)
        mainEditorSession = MainEditorSessionState()
        editingCardID = nil
        pendingMainEditingBoundaryNavigationTargetID = nil
        pendingMainEditingViewportKeepVisibleCardID = nil
        pendingMainEditingViewportRevealEdge = nil
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

    func finishEditing(reason: FinishEditingReason = .generic) {
        guard let context = takeFinishEditingContext(reason: reason) else { return }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard editingCardID == nil else { return }
                isMainViewFocused = true
            }
        }
    }
}
