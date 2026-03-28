import SwiftUI
import AppKit
import QuartzCore
import UniformTypeIdentifiers

extension ScenarioWriterView {

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
        beginMainReorderMotionSession(
            movedCardIDs: movingRoots.map(\.id),
            anchorCardID: draggedCard.id
        )
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
        beginMainReorderMotionSession(
            movedCardIDs: [card.id],
            anchorCardID: card.id
        )
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
        finishEditing(reason: .transition)

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
        finishEditing(reason: .transition)

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

    func setCardColor(_ card: SceneCard, hex: String?) {
        let prevState = captureScenarioState()
        card.colorHex = hex
        commitCardMutation(
            previousState: prevState,
            actionName: "카드 색상"
        )
    }
}
