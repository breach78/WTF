import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension ScenarioWriterView {

    // MARK: - Canvas Position Restore

    func restoreMainCanvasPositionIfNeeded(proxy: ScrollViewProxy, availableWidth: CGFloat) {
        guard !showFocusMode else { return }
        guard !isPreviewingHistory else { return }
        guard let targetID = pendingMainCanvasRestoreCardID else { return }
        pendingMainCanvasRestoreCardID = nil
        scrollToColumnIfNeeded(
            targetCardID: targetID,
            proxy: proxy,
            availableWidth: availableWidth,
            force: true,
            animated: false
        )
    }

    func requestMainCanvasRestoreForHistoryToggle() {
        guard !showFocusMode else { return }
        let targetID = activeCardID ?? lastActiveCardID ?? scenario.rootCards.first?.id
        guard let targetID else { return }
        pendingMainCanvasRestoreCardID = nil
        DispatchQueue.main.async {
            pendingMainCanvasRestoreCardID = targetID
        }
    }

    func requestMainCanvasRestoreForFocusExit() {
        guard !showFocusMode else { return }
        let targetID = activeCardID ?? editingCardID ?? lastActiveCardID ?? scenario.rootCards.first?.id
        guard let targetID else { return }
        pendingMainCanvasRestoreCardID = nil
        DispatchQueue.main.async {
            pendingMainCanvasRestoreCardID = targetID
        }
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

    func persistCardMutation(forceSnapshot: Bool = false, immediateSave: Bool = false) {
        store.saveAll(immediate: immediateSave)
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

    func beginCardEditing(_ card: SceneCard) {
        finishEditing()
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
        let clonePeerDestinations = isCloneLinked ? clonePeerMenuDestinations(for: card) : []
        CardItem(
            card: card,
            isActive: activeCardID == card.id,
            isSelected: selectedCardIDs.contains(card.id),
            isMultiSelected: selectedCardIDs.count > 1 && selectedCardIDs.contains(card.id),
            isArchived: card.isArchived,
            isAncestor: false,
            isDescendant: false,
            isEditing: acceptsKeyboardInput && editingCardID == card.id,
            dropTarget: nil,
            forceNamedSnapshotNoteStyle: isNamedNote,
            forceCustomColorVisibility: isAICandidate,
            measuredWidth: nil,
            onSelect: {
                if openHistoryFromNamedSnapshotNoteCard(card) { return }
                handleCardTap(card)
            },
            onDoubleClick: {
                if openHistoryFromNamedSnapshotNoteCard(card) { return }
                beginCardEditing(card)
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
        .onDrag { NSItemProvider(object: card.id.uuidString as NSString) }
    }

    @ViewBuilder
    func column(for cards: [SceneCard], level: Int, parent: SceneCard?, screenHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // --- 최상단 드롭 영역 (첫 카드가 정확히 0.4 지점에 오도록 높이를 0.4로 고정) ---
                        DropSpacer(target: .columnTop(parent?.id), activeDropTarget: $activeDropTarget, alignment: .bottom) { providers in
                            handleGeneralDrop(providers, target: .columnTop(parent?.id))
                        }
                        .frame(height: screenHeight * 0.4)

                        ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                            VStack(spacing: 0) {
                                cardRow(card, proxy: proxy)

                                if index < cards.count - 1 {
                                    let next = cards[index + 1]
                                    if card.parent?.id != next.parent?.id {
                                        Rectangle()
                                            .fill(appearance == "light" ? Color.black.opacity(0.16) : Color.black.opacity(0.40))
                                            .frame(height: 2)
                                            .padding(.horizontal, 14)
                                    }
                                }

                                // --- 카드 사이 드롭 영역 ---
                                DropSpacer(target: .after(card.id), activeDropTarget: $activeDropTarget, alignment: .center) { providers in
                                    handleGeneralDrop(providers, target: .after(card.id))
                                }
                            }
                        }

                        if cards.isEmpty && level == 0 { addFirstButton(level: level) }

                        // --- 최하단 드롭 영역 ---
                        DropSpacer(target: .columnBottom(parent?.id), activeDropTarget: $activeDropTarget, alignment: .top) { providers in
                            handleGeneralDrop(providers, target: .columnBottom(parent?.id))
                        }
                        .frame(height: screenHeight * 0.7)
                    }
                    .padding(.horizontal, 6).frame(width: columnWidth)
                }
                .onChange(of: activeCardID) { _, newID in
                    guard !showFocusMode else { return }
                    guard acceptsKeyboardInput else { return }
                    // 현재 열이 활성 카드 본인이거나 그 조상을 포함한 '포커스 경로'일 때만 애니메이션 스크롤
                    // 자식 열이 부모의 움직임에 따라 마구 스크롤되는 현상(Dancing)을 방지합니다.
                    let isDirectPath = cards.contains { $0.id == newID || activeAncestorIDs.contains($0.id) }
                    let isImmediateChildColumn = cards.contains { $0.parent?.id == newID }
                    if isDirectPath || isImmediateChildColumn {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                            scrollToFocus(in: cards, parent: parent, proxy: proxy, viewportHeight: screenHeight, animated: true)
                        }
                    }
                }
                .onChange(of: cards.map { $0.id }) { _, _ in
                    guard !showFocusMode else { return }
                    guard acceptsKeyboardInput else { return }
                    // 부모가 바뀌어 열의 카드 구성이 달라진 경우(자식 열 등장), 애니메이션 없이 즉시 위치를 잡습니다.
                    scrollToFocus(in: cards, parent: parent, proxy: proxy, viewportHeight: screenHeight, animated: false)
                }
                .onAppear {
                    guard !showFocusMode else { return }
                    guard acceptsKeyboardInput else { return }
                    // 처음 열이 그려질 때는 지연 없이 즉시 스냅하여 튀어오르는 느낌을 제거합니다.
                    scrollToFocus(in: cards, parent: parent, proxy: proxy, viewportHeight: screenHeight, animated: false)
                }
                .onPreferenceChange(MainCardHeightPreferenceKey.self) { heights in
                    guard !showFocusMode else { return }
                    guard acceptsKeyboardInput else { return }
                    let previousHeights = mainCardHeights
                    mainCardHeights.merge(heights, uniquingKeysWith: { _, new in new })
                    guard let activeID = activeCardID else { return }
                    guard cards.contains(where: { $0.id == activeID }) else { return }
                    guard let newHeight = heights[activeID] else { return }
                    let oldHeight = previousHeights[activeID] ?? 0
                    if oldHeight <= screenHeight && newHeight > screenHeight {
                        DispatchQueue.main.async {
                            scrollToFocus(in: cards, parent: parent, proxy: proxy, viewportHeight: screenHeight, animated: false)
                        }
                    }
                }
                .onPreferenceChange(MainCardWidthPreferenceKey.self) { widths in
                    guard !showFocusMode else { return }
                    guard acceptsKeyboardInput else { return }
                    let previousWidths = mainCardWidths
                    mainCardWidths.merge(widths, uniquingKeysWith: { _, new in new })
                    guard let editingID = editingCardID else { return }
                    let oldWidth = previousWidths[editingID] ?? 0
                    let newWidth = mainCardWidths[editingID] ?? 0
                    guard abs(newWidth - oldWidth) > 0.25 else { return }
                    DispatchQueue.main.async {
                        guard !showFocusMode else { return }
                        guard editingCardID == editingID else { return }
                        applyMainEditorLineSpacingIfNeeded()
                    }
                }
                .onChange(of: mainBottomRevealTick) { _, _ in
                    guard !showFocusMode else { return }
                    guard acceptsKeyboardInput else { return }
                    guard let requestedID = mainBottomRevealCardID else { return }
                    guard activeCardID == requestedID else { return }
                    guard cards.last?.id == requestedID else { return }
                    guard let cardHeight = mainCardHeights[requestedID], cardHeight > screenHeight else { return }
                    withAnimation(quickEaseAnimation) {
                        proxy.scrollTo(requestedID, anchor: .bottom)
                    }
                }
            }
            .contentShape(Rectangle()).onTapGesture { finishEditing(); isMainViewFocused = true }
        }
        .frame(width: columnWidth)
    }

    func scrollToFocus(
        in cards: [SceneCard],
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        animated: Bool = true
    ) {
        guard acceptsKeyboardInput else { return }
        let defaultAnchor = UnitPoint(x: 0.5, y: 0.4)

        let targetID: UUID?
        if let id = activeCardID, cards.contains(where: { $0.id == id }) {
            targetID = id
        } else if let target = cards.first(where: { activeAncestorIDs.contains($0.id) }) {
            targetID = target.id
        } else if
            let activeID = activeCardID,
            let activeCard = findCard(by: activeID)
        {
            let directChildren = cards.filter { $0.parent?.id == activeID }
            if let rememberedID = activeCard.lastSelectedChildID,
               directChildren.contains(where: { $0.id == rememberedID }) {
                targetID = rememberedID
            } else {
                targetID = directChildren.first?.id
            }
        } else {
            targetID = nil
        }

        if let idToScroll = targetID {
            let focusAnchor: UnitPoint
            if let cardHeight = mainCardHeights[idToScroll], cardHeight > viewportHeight {
                focusAnchor = UnitPoint(x: 0.5, y: 0.0)
            } else {
                focusAnchor = defaultAnchor
            }
            if animated {
                withAnimation(quickEaseAnimation) {
                    proxy.scrollTo(idToScroll, anchor: focusAnchor)
                }
            } else {
                proxy.scrollTo(idToScroll, anchor: focusAnchor)
            }
        }
    }

    func requestMainBottomRevealIfNeeded(
        currentLevel: [SceneCard],
        currentIndex: Int,
        card: SceneCard
    ) -> Bool {
        guard currentIndex == currentLevel.count - 1 else { return false }
        guard activeCardID == card.id else { return false }
        mainBottomRevealCardID = card.id
        mainBottomRevealTick += 1
        return true
    }

    @ViewBuilder
    func cardRow(_ card: SceneCard, proxy: ScrollViewProxy) -> some View {
        let isAICandidate = aiCandidateState.cardIDs.contains(card.id) || card.isAICandidate
        let isPlotLineCard = card.category == ScenarioCardCategory.plot
        let canCreateUpperCard = canCreateUpperCardFromSelection(contextCard: card)
        let canSummarizeChildren = canSummarizeDirectChildren(for: card)
        let isCloneLinked = scenario.isCardCloned(card.id)
        let clonePeerDestinations = isCloneLinked ? clonePeerMenuDestinations(for: card) : []
        CardItem(
            card: card,
            isActive: activeCardID == card.id,
            isSelected: selectedCardIDs.contains(card.id),
            isMultiSelected: selectedCardIDs.count > 1 && selectedCardIDs.contains(card.id),
            isArchived: card.isArchived,
            isAncestor: activeAncestorIDs.contains(card.id) || activeSiblingIDs.contains(card.id),
            isDescendant: activeDescendantIDs.contains(card.id),
            isEditing: !showFocusMode && acceptsKeyboardInput && editingCardID == card.id,
            dropTarget: activeDropTarget,
            forceNamedSnapshotNoteStyle: false,
            forceCustomColorVisibility: isAICandidate,
            measuredWidth: mainCardWidths[card.id],
            onSelect: { handleCardTap(card) },
            onDoubleClick: {
                beginCardEditing(card)
            },
            onEndEdit: { finishEditing() },
            onContentChange: { oldValue, newValue in
                handleMainEditorContentChange(cardID: card.id, oldValue: oldValue, newValue: newValue)
            },
            onColorChange: { hex in setCardColor(card, hex: hex) },
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
            onCloneCard: { copyCardsAsCloneFromContext(card) },
            clonePeerDestinations: clonePeerDestinations,
            onNavigateToClonePeer: { targetID in navigateToCloneCard(targetID) }
        )
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: MainCardHeightPreferenceKey.self,
                    value: [card.id: geometry.size.height]
                )
                .preference(
                    key: MainCardWidthPreferenceKey.self,
                    value: [card.id: geometry.size.width]
                )
            }
        )
        .id(card.id)
        .onDrag { NSItemProvider(object: card.id.uuidString as NSString) }
        .onDrop(of: [.text], delegate: AdvancedCardDropDelegate(targetCard: card, activeDropTarget: $activeDropTarget, performAction: { providers, target in handleGeneralDrop(providers, target: target) }))
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

    func handleGeneralDrop(_ providers: [NSItemProvider], target: DropTarget) {
        guard let provider = providers.first else { return }
        provider.loadObject(ofClass: NSString.self) { string, _ in
            guard let uuidStr = string as? String, let draggedID = UUID(uuidString: uuidStr) else { return }
            DispatchQueue.main.async {
                guard let draggedCard = findCard(by: draggedID) else { return }
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
        let destinationSiblings = destinationParent?.sortedChildren ?? scenario.rootCards
        for sibling in destinationSiblings where !movingIDs.contains(sibling.id) && sibling.orderIndex >= insertionIndex {
            sibling.orderIndex += movingRoots.count
        }

        for (offset, card) in movingRoots.enumerated() {
            if card.isArchived {
                card.isArchived = false
                scenario.bumpCardsVersion()
            }
            card.parent = destinationParent
            card.orderIndex = insertionIndex + offset
            card.isFloating = false
            card.updateDescendantsCategory(card.parent?.category)
        }

        normalizeAffectedParents(oldParents: oldParents, destinationParent: destinationParent)

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
                return (parent, parent.children.count)
            }
        case .columnTop(let pId):
            let parent = pId.flatMap { findCard(by: $0) }
            return (parent, 0)
        case .columnBottom(let pId):
            let parent = pId.flatMap { findCard(by: $0) }
            let count = parent?.children.count ?? scenario.rootCards.count
            return (parent, count)
        }
        return (nil, scenario.rootCards.count)
    }

    func normalizeAffectedParents(oldParents: [SceneCard?], destinationParent: SceneCard?) {
        var normalizedRoot = false
        for parent in oldParents {
            if let parent = parent {
                normalizeIndices(parent: parent)
            } else if !normalizedRoot {
                normalizeIndices(parent: nil)
                normalizedRoot = true
            }
        }
        if let destinationParent = destinationParent {
            normalizeIndices(parent: destinationParent)
        } else if !normalizedRoot {
            normalizeIndices(parent: nil)
        }
    }

    func executeMove(_ card: SceneCard, target: DropTarget) {
        if case .onto(let targetID) = target, targetID == card.id { return }
        if let targetID = targetIDFrom(target), isDescendant(card, of: targetID) { return }

        let prevState = captureScenarioState()

        if card.isArchived {
            card.isArchived = false
            scenario.bumpCardsVersion()
        }

        let oldParent = card.parent
        normalizeIndices(parent: oldParent)

        switch target {
        case .before(let id):
            if let anchor = findCard(by: id) {
                let newParent = anchor.parent
                let newIndex = anchor.orderIndex
                let newSiblings = newParent?.sortedChildren ?? scenario.rootCards
                for s in newSiblings where s.orderIndex >= newIndex { s.orderIndex += 1 }
                card.parent = newParent; card.orderIndex = newIndex
            }
        case .after(let id):
            if let anchor = findCard(by: id) {
                let newParent = anchor.parent
                let newIndex = anchor.orderIndex + 1
                let newSiblings = newParent?.sortedChildren ?? scenario.rootCards
                for s in newSiblings where s.orderIndex >= newIndex { s.orderIndex += 1 }
                card.parent = newParent; card.orderIndex = newIndex
            }
        case .onto(let id):
            if let parent = findCard(by: id) {
                card.parent = parent
                card.orderIndex = parent.children.count
            }
        case .columnTop(let pId):
            let newParent = pId.flatMap { findCard(by: $0) }
            let newSiblings = newParent?.sortedChildren ?? scenario.rootCards
            for s in newSiblings { s.orderIndex += 1 }
            card.parent = newParent; card.orderIndex = 0
        case .columnBottom(let pId):
            let newParent = pId.flatMap { findCard(by: $0) }
            let newSiblings = newParent?.sortedChildren ?? scenario.rootCards
            card.parent = newParent; card.orderIndex = newSiblings.count
        }

        card.isFloating = false
        normalizeIndices(parent: card.parent)
        if oldParent?.id != card.parent?.id { normalizeIndices(parent: oldParent) }

        card.updateDescendantsCategory(card.parent?.category)
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

    func isDescendant(_ card: SceneCard, of targetID: UUID) -> Bool {
        var curr = findCard(by: targetID)?.parent
        while let p = curr { if p.id == card.id { return true }; curr = p.parent }; return false
    }

    func resolvedLevelsWithParents() -> [LevelData] {
        let levels = scenario.allLevels
        return levels.map { cards in
            LevelData(cards: cards, parent: cards.first?.parent)
        }
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
        let levels = resolvedAllLevels(); guard let targetLevel = levels.firstIndex(where: { $0.contains(where: { $0.id == targetCardID }) }) else { return }
        let hOffset = (columnWidth / 2) / availableWidth; let hAnchor = UnitPoint(x: 0.5 - hOffset, y: 0.4)
        let performScroll: (Int) -> Void = { level in
            if animated {
                withAnimation(quickEaseAnimation) {
                    proxy.scrollTo(level, anchor: hAnchor)
                }
            } else {
                proxy.scrollTo(level, anchor: hAnchor)
            }
        }
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

    // MARK: - Card Lookup & Active State

    func findCard(by id: UUID) -> SceneCard? { scenario.cardByID(id) }

    func synchronizeActiveRelationState(for activeID: UUID?) {
        guard let activeID, let card = findCard(by: activeID) else {
            activeAncestorIDs = []
            activeSiblingIDs = []
            activeDescendantIDs = []
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
        let descendantIDs = descendantIDSet(of: card)

        if activeAncestorIDs != ancestors { activeAncestorIDs = ancestors }
        if activeSiblingIDs != siblingIDs { activeSiblingIDs = siblingIDs }
        if activeDescendantIDs != descendantIDs { activeDescendantIDs = descendantIDs }
    }

    func changeActiveCard(
        to card: SceneCard,
        shouldFocusMain: Bool = true,
        deferToMainAsync: Bool = true,
        force: Bool = false
    ) {
        cleanupEmptyEditingCardIfNeeded(beforeSwitchingTo: card.id)
        if !force {
            if activeCardID == card.id, pendingActiveCardID == nil {
                if shouldFocusMain { isMainViewFocused = true }
                return
            }
            if pendingActiveCardID == card.id {
                if shouldFocusMain { isMainViewFocused = true }
                return
            }
        } else {
            pendingActiveCardID = nil
        }
        pendingActiveCardID = card.id
        let apply = {
            defer { pendingActiveCardID = nil }
            if activeCardID != card.id {
                lastActiveCardID = activeCardID
            }
            activeCardID = card.id
            card.parent?.lastSelectedChildID = card.id
            synchronizeActiveRelationState(for: card.id)
            if shouldFocusMain { isMainViewFocused = true }
            let levelCount = resolvedLevelsWithParents().count
            if levelCount > maxLevelCount { maxLevelCount = levelCount }
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
        var ids: Set<UUID> = []
        for child in card.children {
            ids.insert(child.id)
            ids.formUnion(descendantIDSet(of: child))
        }
        return ids
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
        let skipMainFocusRestore = suppressMainFocusRestoreAfterFinishEditing
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
        if !isApplyingUndo {
            if !inFocusMode {
                if wasNewCard, let prev = newCardPrevState {
                    pushUndoState(prev, actionName: "카드 추가")
                } else if let prev = startState, startContent != card.content {
                    pushUndoState(prev, actionName: "텍스트 편집")
                }
            }
        }
        if inFocusMode {
            focusLastCommittedContentByCard[id] = card.content
        }
        persistCardMutation()
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
        activeAncestorIDs = []
        activeDescendantIDs = []
        activeSiblingIDs = []
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
        withAnimation(quickEaseAnimation) { showTimeline = false; searchText = ""; isSearchFocused = false }
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
        store.saveAll()
        selectedCardIDs = [new.id]
        changeActiveCard(to: new, shouldFocusMain: false)
        editingCardID = new.id
        editingStartContent = new.content
        editingIsNewCard = true
        pendingNewCardPrevState = prevState
    }

    // MARK: - Insert, Add Child, Delete

    func selectedSiblingsForParentCreation(contextCard: SceneCard) -> [SceneCard]? {
        guard !showFocusMode else { return nil }
        guard selectedCardIDs.count > 1 else { return nil }
        guard selectedCardIDs.contains(contextCard.id) else { return nil }

        let selectedCards = selectedCardIDs.compactMap { findCard(by: $0) }
        guard selectedCards.count == selectedCardIDs.count else { return nil }
        guard !selectedCards.isEmpty else { return nil }

        let parentID = selectedCards.first?.parent?.id
        guard selectedCards.allSatisfy({ $0.parent?.id == parentID }) else { return nil }

        return selectedCards.sorted { lhs, rhs in
            if lhs.orderIndex != rhs.orderIndex {
                return lhs.orderIndex < rhs.orderIndex
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    func canCreateUpperCardFromSelection(contextCard: SceneCard) -> Bool {
        selectedSiblingsForParentCreation(contextCard: contextCard) != nil
    }

    func createUpperCardFromSelection(contextCard: SceneCard) {
        guard let selectedSiblings = selectedSiblingsForParentCreation(contextCard: contextCard),
              let firstSelected = selectedSiblings.first else { return }

        let prevState = captureScenarioState()
        suppressMainFocusRestoreAfterFinishEditing = true
        finishEditing()

        let parent = firstSelected.parent
        let insertionIndex = firstSelected.orderIndex
        let newParent = SceneCard(
            orderIndex: insertionIndex,
            parent: parent,
            scenario: scenario,
            category: parent?.category ?? firstSelected.category
        )
        scenario.cards.append(newParent)

        for (childIndex, selectedCard) in selectedSiblings.enumerated() {
            selectedCard.parent = newParent
            selectedCard.orderIndex = childIndex
        }

        normalizeIndices(parent: parent)
        normalizeIndices(parent: newParent)

        scenario.bumpCardsVersion()
        keyboardRangeSelectionAnchorCardID = nil
        selectedCardIDs = [newParent.id]
        changeActiveCard(to: newParent, shouldFocusMain: false)
        editingCardID = newParent.id
        editingStartContent = newParent.content
        editingStartState = captureScenarioState()
        editingIsNewCard = false
        pendingNewCardPrevState = nil
        mainCaretLocationByCardID[newParent.id] = 0
        requestMainCaretRestore(for: newParent.id)
        requestCoalescedMainCaretEnsure(minInterval: mainCaretSelectionEnsureMinInterval, delay: 0.0)
        isMainViewFocused = true
        commitCardMutation(
            previousState: prevState,
            actionName: "새 상위 카드 만들기"
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
                mainCaretLocationByCardID[latestParent.id] = (latestParent.content as NSString).length
                requestMainCaretRestore(for: latestParent.id)
                requestCoalescedMainCaretEnsure(minInterval: mainCaretSelectionEnsureMinInterval, delay: 0.0)
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
        store.saveAll()

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
            mainCaretLocationByCardID[new.id] = 0
            requestMainCaretRestore(for: new.id)
            requestCoalescedMainCaretEnsure(minInterval: mainCaretSelectionEnsureMinInterval, delay: 0.0)
        }
    }

    func insertSibling(above: Bool) {
        let prevState = captureScenarioState()
        guard let id = activeCardID, let card = findCard(by: id) else { return }
        if showFocusMode {
            finalizeFocusTypingCoalescing(reason: "insert-sibling")
            pushFocusUndoState(prevState, actionName: "카드 추가")
        }
        let target = above ? card.orderIndex : card.orderIndex + 1
        for s in (card.parent?.sortedChildren ?? scenario.rootCards) where s.orderIndex >= target { s.orderIndex += 1 }
        let new = SceneCard(orderIndex: target, parent: card.parent, scenario: scenario, category: card.category)
        scenario.cards.append(new)
        scenario.bumpCardsVersion()
        store.saveAll()
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
    func addChildCard() {
        let prevState = captureScenarioState()
        guard let id = activeCardID, let card = findCard(by: id) else { return }
        if showFocusMode {
            finalizeFocusTypingCoalescing(reason: "add-child")
            pushFocusUndoState(prevState, actionName: "카드 추가")
        }
        let new = SceneCard(orderIndex: card.children.count, parent: card, scenario: scenario, category: card.category)
        scenario.cards.append(new)
        scenario.bumpCardsVersion()
        store.saveAll()
        selectedCardIDs = [new.id]
        changeActiveCard(to: new, shouldFocusMain: false)
        editingCardID = new.id
        editingStartContent = new.content
        editingIsNewCard = true
        pendingNewCardPrevState = prevState
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
            activeCardID = nil; activeAncestorIDs = []; activeDescendantIDs = []; activeSiblingIDs = []
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
                activeAncestorIDs = []
                activeDescendantIDs = []
                activeSiblingIDs = []
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
