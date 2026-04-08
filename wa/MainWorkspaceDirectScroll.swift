import AppKit
import Foundation

private enum MainWorkspaceColumnAnchorMode: Equatable {
    case clampedCenter(chromeInset: CGFloat)
    case keepVisible(editingRevealEdge: MainEditingViewportRevealEdge?)
}

private enum MainWorkspaceColumnPolicy: Equatable {
    case centerActive(cardID: UUID)
    case centerAncestor(cardID: UUID)
    case centerPreferredDescendant(cardID: UUID)
    case centerOtherDescendant(cardID: UUID)
    case between(afterID: UUID, beforeID: UUID)
    case before(cardID: UUID)
    case after(cardID: UUID)
    case none

    var primaryCardID: UUID? {
        switch self {
        case .centerActive(let cardID),
            .centerAncestor(let cardID),
            .centerPreferredDescendant(let cardID),
            .centerOtherDescendant(let cardID),
            .before(let cardID),
            .after(let cardID):
            return cardID
        case .between, .none:
            return nil
        }
    }

    var debugSummary: String {
        switch self {
        case .centerActive(let cardID):
            return "centerActive:\(cardID.uuidString)"
        case .centerAncestor(let cardID):
            return "centerAncestor:\(cardID.uuidString)"
        case .centerPreferredDescendant(let cardID):
            return "centerPreferredDescendant:\(cardID.uuidString)"
        case .centerOtherDescendant(let cardID):
            return "centerOtherDescendant:\(cardID.uuidString)"
        case .between(let afterID, let beforeID):
            return "between:\(afterID.uuidString):\(beforeID.uuidString)"
        case .before(let cardID):
            return "before:\(cardID.uuidString)"
        case .after(let cardID):
            return "after:\(cardID.uuidString)"
        case .none:
            return "none"
        }
    }
}

private struct MainWorkspaceColumnScrollAlignment: Equatable {
    let level: Int
    let viewportKey: String
    let policy: MainWorkspaceColumnPolicy
    let anchorMode: MainWorkspaceColumnAnchorMode
    let keepVisibleOnly: Bool
    let animated: Bool
    let authorityKind: MainVerticalScrollAuthorityKind

    var primaryCardID: UUID? {
        policy.primaryCardID
    }
}

private struct MainWorkspaceVisibleDescendantSelection {
    let cardID: UUID
    let path: [UUID]
    let source: MainWorkspaceNavigationModel.PreferredNavigationChildSource
}

private enum MainWorkspaceDirectColumnApplyOutcome {
    case applied
    case skipped
    case missingViewport
}

private enum MainWorkspacePolicyVerticalAnchor {
    case top
    case center
    case bottom
}

private struct MainWorkspaceColumnPolicyTarget {
    let frame: CGRect
    let anchor: MainWorkspacePolicyVerticalAnchor
}

extension ScenarioWriterView {
    @discardableResult
    func performMainWorkspaceDirectScroll(
        activeID: UUID,
        availableWidth: CGFloat,
        animated: Bool,
        trigger: String
    ) -> Bool {
        guard !showFocusMode else { return false }
        guard acceptsKeyboardInput else { return false }

        let levelsData = resolvedDisplayedMainLevelsWithParents()
        let levels = levelsData.map(\.cards)
        guard let activeCard = findCard(by: activeID),
              let activeLocation = displayedMainCardLocationByID(activeID, in: levels) else {
            return false
        }

        cancelAllPendingMainColumnFocusWork()

        let didApplyHorizontal = performMainCanvasHorizontalScroll(
            level: activeLocation.level,
            availableWidth: max(1, availableWidth),
            animated: animated
        )
        let alignments = resolvedMainWorkspaceColumnScrollAlignments(
            levelsData: levelsData,
            activeCard: activeCard,
            activeLevel: activeLocation.level,
            animated: animated
        )
        let didApplyVertical = applyMainWorkspaceColumnScrollAlignments(
            alignments,
            levelsData: levelsData,
            activeCardID: activeID
        )

        mainWorkspacePhase0Log(
            "direct-scroll",
            "trigger=\(trigger) active=\(mainWorkspacePhase0CardID(activeID)) " +
            "horizontal=\(didApplyHorizontal) vertical=\(didApplyVertical) " +
            "policies=\(alignments.map { $0.policy.debugSummary }.joined(separator: ","))"
        )
        if pendingMainClickFocusTargetID == activeID {
            pendingMainClickFocusTargetID = nil
        }
        return didApplyHorizontal || didApplyVertical
    }

    private func resolvedMainWorkspaceColumnScrollAlignments(
        levelsData: [LevelData],
        activeCard: SceneCard,
        activeLevel: Int,
        animated: Bool
    ) -> [MainWorkspaceColumnScrollAlignment] {
        let preorderIndexByCardID = mainWorkspacePreorderIndexByCardID()
        let isEditingBoundaryTransition =
            editingCardID == activeCard.id &&
            (
                pendingMainEditingBoundaryNavigationTargetID == activeCard.id ||
                pendingMainEditingSiblingNavigationTargetID == activeCard.id
            )

        return levelsData.enumerated().map { level, data in
            let cards = data.cards
            let viewportKey = mainColumnViewportStorageKey(level: level, cards: cards)
            let keepVisibleOnly =
                pendingMainEditingViewportKeepVisibleCardID == activeCard.id &&
                cards.contains(where: { $0.id == activeCard.id })
            let anchorMode: MainWorkspaceColumnAnchorMode =
                keepVisibleOnly
                ? .keepVisible(editingRevealEdge: pendingMainEditingViewportRevealEdge)
                : .clampedCenter(chromeInset: 51)

            return MainWorkspaceColumnScrollAlignment(
                level: level,
                viewportKey: viewportKey,
                policy: resolvedMainWorkspaceColumnPolicy(
                    in: cards,
                    level: level,
                    activeLevel: activeLevel,
                    activeCard: activeCard,
                    preorderIndexByCardID: preorderIndexByCardID
                ),
                anchorMode: anchorMode,
                keepVisibleOnly: keepVisibleOnly,
                animated: animated,
                authorityKind: (keepVisibleOnly || isEditingBoundaryTransition) ? .editingTransition : .columnNavigation
            )
        }
    }

    private func applyMainWorkspaceColumnScrollAlignments(
        _ alignments: [MainWorkspaceColumnScrollAlignment],
        levelsData: [LevelData],
        activeCardID: UUID
    ) -> Bool {
        var didApply = false
        var didResolveEditingKeepVisible = false

        for alignment in alignments {
            guard levelsData.indices.contains(alignment.level) else { continue }
            let cards = levelsData[alignment.level].cards
            guard !cards.isEmpty else { continue }
            guard alignment.policy != .none else { continue }

            let outcome = applyMainWorkspaceColumnScrollAlignment(
                alignment,
                cards: cards,
                activeCardID: activeCardID
            )
            switch outcome {
            case .applied:
                didApply = true
                if alignment.keepVisibleOnly && alignment.primaryCardID == activeCardID {
                    didResolveEditingKeepVisible = true
                }
            case .skipped:
                if alignment.keepVisibleOnly && alignment.primaryCardID == activeCardID {
                    didResolveEditingKeepVisible = true
                }
            case .missingViewport:
                break
            }
        }

        if didResolveEditingKeepVisible {
            pendingMainEditingViewportKeepVisibleCardID = nil
            pendingMainEditingViewportRevealEdge = nil
        }
        return didApply
    }

    private func applyMainWorkspaceColumnScrollAlignment(
        _ alignment: MainWorkspaceColumnScrollAlignment,
        cards: [SceneCard],
        activeCardID: UUID
    ) -> MainWorkspaceDirectColumnApplyOutcome {
        let authority = beginMainVerticalScrollAuthority(
            viewportKey: alignment.viewportKey,
            kind: alignment.authorityKind,
            targetCardID: alignment.primaryCardID ?? activeCardID
        )
        guard isMainVerticalScrollAuthorityCurrent(authority, viewportKey: alignment.viewportKey) else {
            return .skipped
        }
        guard let scrollView = mainCanvasScrollCoordinator.scrollView(for: alignment.viewportKey) else {
            return .missingViewport
        }

        scrollView.documentView?.layoutSubtreeIfNeeded()
        let visibleRect = scrollView.documentVisibleRect
        let viewportHeight = max(1, visibleRect.height)
        guard let targetOffsetY = resolvedMainWorkspaceColumnTargetOffset(
            viewportKey: alignment.viewportKey,
            cards: cards,
            viewportHeight: viewportHeight,
            alignment: alignment
        ) else {
            return .skipped
        }

        let documentHeight = resolvedMainWorkspaceColumnDocumentHeight(
            viewportKey: alignment.viewportKey,
            cards: cards,
            viewportHeight: viewportHeight,
            scrollView: scrollView
        )
        let maxY = max(0, documentHeight - visibleRect.height)
        let resolvedTargetY = CaretScrollCoordinator.resolvedVerticalTargetY(
            visibleRect: visibleRect,
            targetY: targetOffsetY,
            minY: 0,
            maxY: maxY,
            snapToPixel: true
        )
        let targetReachable = maxY + 0.5 >= targetOffsetY

        if alignment.animated {
            guard targetReachable || targetOffsetY <= 0.5 else {
                return .skipped
            }
            guard abs(resolvedTargetY - visibleRect.origin.y) > 0.5 else {
                return .applied
            }
            let appliedDuration = CaretScrollCoordinator.resolvedVerticalAnimationDuration(
                currentY: visibleRect.origin.y,
                targetY: resolvedTargetY,
                viewportHeight: viewportHeight
            )
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                axis: "vertical",
                engine: "native",
                animated: true,
                target: "\(alignment.viewportKey)|\(alignment.policy.debugSummary)",
                expectedDuration: appliedDuration
            )
            suspendMainColumnViewportCapture(for: appliedDuration + 0.06)
            let applied = CaretScrollCoordinator.applyAnimatedVerticalScrollIfNeeded(
                scrollView: scrollView,
                visibleRect: visibleRect,
                targetY: targetOffsetY,
                minY: 0,
                maxY: maxY,
                deadZone: 0.5,
                snapToPixel: true,
                duration: appliedDuration
            )
            return applied == nil ? .skipped : .applied
        }

        let applied = CaretScrollCoordinator.applyVerticalScrollIfNeeded(
            scrollView: scrollView,
            visibleRect: visibleRect,
            targetY: targetOffsetY,
            minY: 0,
            maxY: maxY,
            deadZone: 0.5,
            snapToPixel: true
        )
        MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
            ownerKey: mainCanvasDiagnosticsOwnerKey,
            axis: "vertical",
            engine: "native",
            animated: false,
            target: "\(alignment.viewportKey)|\(alignment.policy.debugSummary)",
            expectedDuration: 0
        )
        suspendMainColumnViewportCapture(for: 0.12)
        return applied ? .applied : .skipped
    }

    private func resolvedMainWorkspaceColumnTargetOffset(
        viewportKey: String,
        cards: [SceneCard],
        viewportHeight: CGFloat,
        alignment: MainWorkspaceColumnScrollAlignment
    ) -> CGFloat? {
        switch alignment.anchorMode {
        case .keepVisible(let editingRevealEdge):
            guard let targetID = alignment.primaryCardID else { return nil }
            return resolvedMainColumnVisibilityTargetOffset(
                viewportKey: viewportKey,
                cards: cards,
                targetID: targetID,
                viewportHeight: viewportHeight,
                prefersTopAnchor: false,
                editingRevealEdge: editingRevealEdge
            )

        case .clampedCenter(let chromeInset):
            guard let target = resolvedMainWorkspaceColumnPolicyTarget(
                viewportKey: viewportKey,
                cards: cards,
                viewportHeight: viewportHeight,
                policy: alignment.policy
            ) else {
                return nil
            }
            switch target.anchor {
            case .top:
                return target.frame.minY - viewportHeight * 0.5
            case .center:
                let oversizedThreshold = viewportHeight - chromeInset
                let adjustedHeight =
                    target.frame.height > oversizedThreshold
                    ? viewportHeight * 0.5 + chromeInset
                    : target.frame.height
                return target.frame.minY + adjustedHeight * 0.5 - viewportHeight * 0.5
            case .bottom:
                return target.frame.maxY - viewportHeight * 0.5
            }
        }
    }

    private func resolvedMainWorkspaceColumnPolicyTarget(
        viewportKey: String,
        cards: [SceneCard],
        viewportHeight: CGFloat,
        policy: MainWorkspaceColumnPolicy
    ) -> MainWorkspaceColumnPolicyTarget? {
        switch policy {
        case .centerActive(let cardID),
            .centerAncestor(let cardID),
            .centerPreferredDescendant(let cardID),
            .centerOtherDescendant(let cardID):
            guard let frame = resolvedMainWorkspaceColumnFrame(
                viewportKey: viewportKey,
                cards: cards,
                cardID: cardID,
                viewportHeight: viewportHeight
            ) else {
                return nil
            }
            return MainWorkspaceColumnPolicyTarget(frame: frame, anchor: .center)

        case .between(let afterID, let beforeID):
            guard let frame = resolvedMainWorkspaceColumnFrame(
                viewportKey: viewportKey,
                cards: cards,
                cardID: afterID,
                viewportHeight: viewportHeight
            ) else {
                return nil
            }
            guard let beforeFrame = resolvedMainWorkspaceColumnFrame(
                viewportKey: viewportKey,
                cards: cards,
                cardID: beforeID,
                viewportHeight: viewportHeight
            ) else {
                return nil
            }
            let hasGap = beforeFrame.minY > frame.maxY
            if hasGap {
                let midpointY = (frame.maxY + beforeFrame.minY) * 0.5
                return MainWorkspaceColumnPolicyTarget(
                    frame: CGRect(x: frame.minX, y: midpointY, width: frame.width, height: 0),
                    anchor: .bottom
                )
            }
            return MainWorkspaceColumnPolicyTarget(frame: frame, anchor: .bottom)

        case .before(let cardID):
            guard let frame = resolvedMainWorkspaceColumnFrame(
                viewportKey: viewportKey,
                cards: cards,
                cardID: cardID,
                viewportHeight: viewportHeight
            ) else {
                return nil
            }
            return MainWorkspaceColumnPolicyTarget(frame: frame, anchor: .top)

        case .after(let cardID):
            guard let frame = resolvedMainWorkspaceColumnFrame(
                viewportKey: viewportKey,
                cards: cards,
                cardID: cardID,
                viewportHeight: viewportHeight
            ) else {
                return nil
            }
            return MainWorkspaceColumnPolicyTarget(frame: frame, anchor: .bottom)

        case .none:
            return nil
        }
    }

    private func resolvedMainWorkspaceColumnDocumentHeight(
        viewportKey: String,
        cards: [SceneCard],
        viewportHeight: CGFloat,
        scrollView: NSScrollView
    ) -> CGFloat {
        let liveDocumentHeight = scrollView.documentView?.bounds.height ?? 0
        let predictedDocumentHeight = max(
            viewportHeight,
            resolvedMainColumnLayoutSnapshot(in: cards, viewportHeight: viewportHeight).contentBottomY
        )
        if predictedDocumentHeight > liveDocumentHeight + 1 {
            mainWorkspacePhase0Log(
                "direct-scroll-document-height-fallback",
                "viewport=\(viewportKey) liveHeight=\(liveDocumentHeight) predictedHeight=\(predictedDocumentHeight)"
            )
        }
        return max(liveDocumentHeight, predictedDocumentHeight)
    }

    private func resolvedMainWorkspaceColumnFrame(
        viewportKey: String,
        cards: [SceneCard],
        cardID: UUID,
        viewportHeight: CGFloat
    ) -> CGRect? {
        let predictedFrame = predictedMainColumnTargetFrame(
            cards: cards,
            targetID: cardID,
            viewportHeight: viewportHeight
        )
        let observedFrame = observedMainColumnTargetFrame(
            viewportKey: viewportKey,
            targetID: cardID
        )
        return observedFrame ?? predictedFrame
    }

    private func resolvedMainWorkspaceColumnPolicy(
        in cards: [SceneCard],
        level: Int,
        activeLevel: Int,
        activeCard: SceneCard,
        preorderIndexByCardID: [UUID: Int]
    ) -> MainWorkspaceColumnPolicy {
        guard !cards.isEmpty else { return .none }
        _ = level
        _ = activeLevel
        let matchingCategory = Set(cards.compactMap(\.category)).count == 1
            ? cards.compactMap(\.category).first
            : nil
        if cards.contains(where: { $0.id == activeCard.id }) {
            return .centerActive(cardID: activeCard.id)
        }
        if let ancestor = cards.first(where: { activeAncestorIDs.contains($0.id) }) {
            return .centerAncestor(cardID: ancestor.id)
        }
        if let descendant = resolvedMainWorkspaceVisibleDescendantSelection(
            in: cards,
            startingFrom: activeCard,
            matching: matchingCategory
        ) {
            return .centerPreferredDescendant(cardID: descendant.cardID)
        }
        if let otherDescendant = cards.first(where: { activeDescendantIDs.contains($0.id) }) {
            return .centerOtherDescendant(cardID: otherDescendant.id)
        }
        return resolvedMainWorkspaceSurroundingPolicy(
            in: cards,
            around: activeCard.id,
            preorderIndexByCardID: preorderIndexByCardID
        )
    }

    private func resolvedMainWorkspaceVisibleDescendantSelection(
        in cards: [SceneCard],
        startingFrom root: SceneCard,
        matching category: String?
    ) -> MainWorkspaceVisibleDescendantSelection? {
        let visibleCardIDs = Set(cards.map(\.id))
        guard let resolvedSelection = preferredVisibleNavigationChild(
            from: root,
            visibleCardIDs: visibleCardIDs,
            matchingCategory: category,
            path: [root.id]
        ) else {
            mainWorkspacePhase0Log(
                "descendant-selection-monitor",
                "root=\(mainWorkspacePhase0CardID(root.id)) mode=none visible=\(mainWorkspacePhase0CardList(Array(visibleCardIDs))) " +
                "path=\(mainWorkspacePhase0CardList([root.id]))"
            )
            return nil
        }

        let selection = MainWorkspaceVisibleDescendantSelection(
            cardID: resolvedSelection.cardID,
            path: resolvedSelection.path,
            source: resolvedSelection.source
        )
        mainWorkspacePhase0Log(
            "descendant-selection-monitor",
            "root=\(mainWorkspacePhase0CardID(root.id)) node=\(mainWorkspacePhase0CardID(root.id)) " +
            "mode=path sourceKind=\(selection.source.debugLabel) target=\(mainWorkspacePhase0CardID(selection.cardID)) " +
            "visible=\(mainWorkspacePhase0CardList(Array(visibleCardIDs))) path=\(mainWorkspacePhase0CardList(selection.path))"
        )
        return selection
    }

    func resolvedMainWorkspaceVisibleDescendantTargetID(
        from root: SceneCard,
        visibleCardIDs: Set<UUID>,
        matching category: String?
    ) -> UUID? {
        return preferredVisibleNavigationChild(
            from: root,
            visibleCardIDs: visibleCardIDs,
            matchingCategory: category,
            path: [root.id]
        )?.cardID
    }

    private struct MainWorkspacePreferredVisibleDescendantSelection {
        let cardID: UUID
        let path: [UUID]
        let source: MainWorkspaceNavigationModel.PreferredNavigationChildSource
    }

    private func preferredVisibleNavigationChild(
        from root: SceneCard,
        visibleCardIDs: Set<UUID>,
        matchingCategory: String?,
        path: [UUID],
        visited: Set<UUID> = []
    ) -> MainWorkspacePreferredVisibleDescendantSelection? {
        if visited.contains(root.id) {
            return nil
        }
        let visibleChildren = root.sortedChildren.filter { child in
            guard visibleCardIDs.contains(child.id) else { return false }
            guard let matchingCategory else { return true }
            return child.category == matchingCategory
        }
        guard !visibleChildren.isEmpty else {
            return nil
        }

        if let historyMatch = firstHistoryMatch(in: visibleChildren) {
            let nextPath = path + [historyMatch.id]
            if let descendant = preferredVisibleNavigationChild(
                from: historyMatch,
                visibleCardIDs: visibleCardIDs,
                matchingCategory: matchingCategory,
                path: nextPath,
                visited: visited.union([root.id])
            ) {
                return descendant
            }
            return MainWorkspacePreferredVisibleDescendantSelection(
                cardID: historyMatch.id,
                path: nextPath,
                source: .activeHistory
            )
        }

        if let rememberedID = root.lastSelectedChildID,
           let rememberedChild = visibleChildren.first(where: { $0.id == rememberedID }) {
            let nextPath = path + [rememberedChild.id]
            if let descendant = preferredVisibleNavigationChild(
                from: rememberedChild,
                visibleCardIDs: visibleCardIDs,
                matchingCategory: matchingCategory,
                path: nextPath,
                visited: visited.union([root.id])
            ) {
                return descendant
            }
            return MainWorkspacePreferredVisibleDescendantSelection(
                cardID: rememberedChild.id,
                path: nextPath,
                source: .lastSelectedChild
            )
        }

        let firstCandidate = visibleChildren.first!
        let nextPath = path + [firstCandidate.id]
        if let descendant = preferredVisibleNavigationChild(
            from: firstCandidate,
            visibleCardIDs: visibleCardIDs,
            matchingCategory: matchingCategory,
            path: nextPath,
            visited: visited.union([root.id])
        ) {
            return descendant
        }
        return MainWorkspacePreferredVisibleDescendantSelection(
            cardID: firstCandidate.id,
            path: nextPath,
            source: .firstAvailable
        )
    }

    private func firstHistoryMatch(in children: [SceneCard]) -> SceneCard? {
        for historyID in mainWorkspaceActiveHistory {
            if let match = children.first(where: { $0.id == historyID }) {
                return match
            }
        }
        return nil
    }

    private func resolvedMainWorkspaceSurroundingPolicy(
        in cards: [SceneCard],
        around activeCardID: UUID,
        preorderIndexByCardID: [UUID: Int]
    ) -> MainWorkspaceColumnPolicy {
        guard let activePreorder = preorderIndexByCardID[activeCardID] else { return .none }
        let sortedCards = cards.sorted { lhs, rhs in
            let leftOrder = preorderIndexByCardID[lhs.id] ?? Int.max
            let rightOrder = preorderIndexByCardID[rhs.id] ?? Int.max
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            return lhs.orderIndex < rhs.orderIndex
        }
        let beforeCard = sortedCards.last { (preorderIndexByCardID[$0.id] ?? Int.max) < activePreorder }
        let afterCard = sortedCards.first { (preorderIndexByCardID[$0.id] ?? Int.max) > activePreorder }
        if let beforeCard, let afterCard {
            return .between(afterID: beforeCard.id, beforeID: afterCard.id)
        }
        if let beforeCard {
            return .after(cardID: beforeCard.id)
        }
        if let afterCard {
            return .before(cardID: afterCard.id)
        }
        return .none
    }

    private func mainWorkspacePreorderIndexByCardID() -> [UUID: Int] {
        var orderByID: [UUID: Int] = [:]
        var nextIndex = 0

        func visit(_ card: SceneCard) {
            orderByID[card.id] = nextIndex
            nextIndex += 1
            for child in card.sortedChildren {
                visit(child)
            }
        }

        for root in scenario.rootCards {
            visit(root)
        }
        return orderByID
    }
}
