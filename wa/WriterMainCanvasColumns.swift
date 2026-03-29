import SwiftUI
import AppKit
import QuartzCore
import UniformTypeIdentifiers

extension ScenarioWriterView {

    func mainColumnGeometryObservationCardIDs(
        in cards: [SceneCard],
        viewportKey: String,
        viewportHeight: CGFloat
    ) -> Set<UUID> {
        let allIDs = Set(cards.map(\.id))
        guard cards.count > 24 else { return allIDs }

        func insertWindow(
            around centerID: UUID?,
            radius: Int,
            into observedIDs: inout Set<UUID>
        ) {
            guard let centerID,
                  let centerIndex = cards.firstIndex(where: { $0.id == centerID }) else {
                return
            }
            let lowerBound = max(cards.startIndex, centerIndex - radius)
            let upperBound = min(cards.index(before: cards.endIndex), centerIndex + radius)
            for index in lowerBound...upperBound {
                observedIDs.insert(cards[index].id)
            }
        }

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

        let focusTargetID = resolvedMainColumnFocusTargetID(in: cards)
        insertWindow(around: focusTargetID, radius: 8, into: &observedIDs)
        insertWindow(around: activeCardID, radius: 8, into: &observedIDs)
        insertWindow(around: editingCardID, radius: 4, into: &observedIDs)

        if let activeCardID, allIDs.contains(activeCardID) {
            observedIDs.insert(activeCardID)
        }
        if let editingCardID, allIDs.contains(editingCardID) {
            observedIDs.insert(editingCardID)
        }
        for ancestorID in activeAncestorIDs where allIDs.contains(ancestorID) {
            observedIDs.insert(ancestorID)
            insertWindow(around: ancestorID, radius: 3, into: &observedIDs)
        }

        if observedIDs.isEmpty {
            for card in cards.prefix(12) {
                observedIDs.insert(card.id)
            }
        }

        return observedIDs
    }

    // MARK: - Timeline & Column View Builders

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
            isEditing: acceptsKeyboardInput && shouldTreatCardAsActivelyEditing(card.id),
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
            onNavigateToClonePeer: { targetID in navigateToCloneCard(targetID) },
            handleEditorCommandBySelector: { selector in
                handleMainEditorBoundaryCommand(selector)
            }
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
    func mainColumnScrollableBody(
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        screenHeight: CGFloat
    ) -> some View {
        let viewportKey = mainColumnViewportStorageKey(level: level)
        let observedCardIDs = mainColumnGeometryObservationCardIDs(
            in: cards,
            viewportKey: viewportKey,
            viewportHeight: screenHeight
        )
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
            }
        }
        .coordinateSpace(name: mainColumnViewportCoordinateSpaceName(viewportKey))
        .overlay(alignment: .topLeading) {
            mainColumnEditorHostOverlay(
                viewportKey: viewportKey,
                cards: cards
            )
        }
        .onPreferenceChange(MainColumnCardFramePreferenceKey.self) { frames in
            mainColumnObservedCardFramesByKey[viewportKey] = frames
            mainCanvasScrollCoordinator.updateObservedFrames(frames, for: viewportKey)
        }
        .onPreferenceChange(MainColumnEditorSlotPreferenceKey.self) { frames in
            mainColumnObservedEditorSlotFramesByKey[viewportKey] = frames
            let validCardIDs = Set(cards.map(\.id))
            let editingSessionCardIDs = Set(
                [mainEditorSession.requestedCardID, mainEditorSession.mountedCardID].compactMap { $0 }
            )
            var cachedFrames = mainColumnCachedEditorSlotFramesByKey[viewportKey] ?? [:]
            cachedFrames = cachedFrames.filter {
                validCardIDs.contains($0.key) || editingSessionCardIDs.contains($0.key)
            }
            for (cardID, frame) in frames where frame.width > 1 && frame.height > 1 {
                cachedFrames[cardID] = frame
            }
            mainColumnCachedEditorSlotFramesByKey[viewportKey] = cachedFrames
        }
        .padding(.horizontal, MainCanvasLayoutMetrics.columnHorizontalPadding)
        .frame(width: columnWidth)
    }

    @ViewBuilder
    func column(for cards: [SceneCard], level: Int, parent: SceneCard?, screenHeight: CGFloat) -> some View {
        let childListSignature = scenario.childListSignature(parentID: parent?.id)
        let viewportKey = mainColumnViewportStorageKey(level: level)
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    mainColumnScrollableBody(
                        cards: cards,
                        level: level,
                        parent: parent,
                        screenHeight: screenHeight
                    )
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
                    if handleMainColumnLateJoinIfPossible(
                        kind: .childListChange,
                        viewportKey: viewportKey,
                        cards: cards,
                        level: level,
                        parent: parent,
                        proxy: proxy,
                        viewportHeight: screenHeight,
                        targetCardID: activeCardID,
                        expectedActiveCardID: activeCardID,
                        animated: false,
                        trigger: "childListChange"
                    ) {
                        return
                    }
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
                    if handleMainColumnLateJoinIfPossible(
                        kind: .columnAppear,
                        viewportKey: viewportKey,
                        cards: cards,
                        level: level,
                        parent: parent,
                        proxy: proxy,
                        viewportHeight: screenHeight,
                        targetCardID: activeCardID,
                        expectedActiveCardID: activeCardID,
                        animated: false,
                        trigger: "columnAppear"
                    ) {
                        return
                    }
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
                    if handleMainColumnLateJoinIfPossible(
                        kind: .bottomReveal,
                        viewportKey: viewportKey,
                        cards: cards,
                        level: level,
                        parent: parent,
                        proxy: proxy,
                        viewportHeight: screenHeight,
                        targetCardID: requestedID,
                        expectedActiveCardID: requestedID,
                        animated: focusNavigationAnimationEnabled,
                        trigger: "mainBottomReveal"
                    ) {
                        return
                    }
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
            .onTapGesture { finishEditing(reason: .transition); isMainViewFocused = true }
        }
        .frame(width: columnWidth)
    }

    @ViewBuilder
    func cardRow(
        _ card: SceneCard,
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
        let viewportKey = mainColumnViewportStorageKey(level: level)
        let editorCoordinateSpaceName = mainColumnViewportCoordinateSpaceName(viewportKey)
        let usesExternalMainEditor = canUseExternalMainEditor(
            cardID: card.id,
            viewportKey: viewportKey,
            cards: columnCards
        )
        let mainEditorManagedExternally =
            isMainWorkspaceEditorSurfaceActive &&
            (mainEditorSession.requestedCardID == card.id || mainEditorSession.mountedCardID == card.id)
        MainCanvasCardItem(
            card: card,
            interactionViewState: mainCanvasInteractionViewState,
            renderSettings: mainCardRenderSettings,
            isEditing: !showFocusMode && acceptsKeyboardInput && shouldTreatCardAsActivelyEditing(card.id),
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
            onNavigateToClonePeer: { targetID in navigateToCloneCard(targetID) },
            mainEditorSlotCoordinateSpaceName: editorCoordinateSpaceName,
            mainEditorManagedExternally: mainEditorManagedExternally,
            usesExternalMainEditor: usesExternalMainEditor,
            disablesInlineMainEditorFallback: true,
            externalEditorLiveBodyHeight:
                usesExternalMainEditor &&
                mainEditorSession.mountedCardID == card.id
                ? mainEditorSession.liveBodyHeight
                : nil,
            onMainEditorMount: { cardID in
                markMainEditorMounted(cardID: cardID)
            },
            onMainEditorUnmount: { cardID in
                markMainEditorUnmounted(cardID: cardID)
            },
            onMainEditorFocusStateChange: { cardID, isFocused in
                updateMainEditorResponderState(cardID: cardID, isFocused: isFocused)
            },
            handleEditorCommandBySelector: { selector in
                handleMainEditorBoundaryCommand(selector)
            }
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
        Button { suppressMainFocusRestoreAfterFinishEditing = true; finishEditing(reason: .transition); addCard(at: level, parent: nil) } label: { Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.vertical, 8) }.buttonStyle(.plain)
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
}
