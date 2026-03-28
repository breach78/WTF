import SwiftUI
import AppKit

extension ScenarioWriterView {
    func scheduleIndexBoardCommitCardMutation(
        previousState: ScenarioState,
        actionName: String
    ) {
        let scheduledAt = CFAbsoluteTimeGetCurrent()
        DispatchQueue.main.async {
            indexBoardDropPerformanceLog(
                "deferred_commit_start",
                "action=\(actionName) queue_ms=\(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - scheduledAt) * 1000))"
            )
            let startedAt = CFAbsoluteTimeGetCurrent()
            self.commitCardMutation(
                previousState: previousState,
                actionName: actionName
            )
            indexBoardDropPerformanceLog(
                "deferred_commit_end",
                "action=\(actionName) ms=\(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - startedAt) * 1000))"
            )
        }
    }

    func commitIndexBoardCardMoveSelection(
        cardIDs: [UUID],
        draggedCardID: UUID,
        target: IndexBoardCardDropTarget,
        projection: IndexBoardProjection
    ) {
        let enterStartedAt = CFAbsoluteTimeGetCurrent()
        let liveProjection = resolvedIndexBoardProjection() ?? projection
        let referenceSurfaceProjection = resolvedIndexBoardSurfaceProjection()
        let movingCards = resolvedIndexBoardMovingCards(
            cardIDs: cardIDs,
            preferredColumns: target.preferredColumnCount ?? 1
        )
        guard !movingCards.isEmpty else { return }
        let movingIDs = Set(movingCards.map(\.id))
        let draggedCard = movingCards.first(where: { $0.id == draggedCardID }) ?? movingCards.first
        guard let draggedCard else { return }

        if target.isTempStripTarget {
            commitDetachedIndexBoardCardMoveSelection(
                movingCards: movingCards,
                draggedCard: draggedCard,
                target: target
            )
            return
        }

        guard let targetGroup = liveProjection.groups.first(where: { $0.id == target.groupID }) else { return }
        let visibleCards = targetGroup.childCards.filter { !movingIDs.contains($0.id) }
        let safeInsertionIndex = min(max(0, target.insertionIndex), visibleCards.count)
        indexBoardDropPerformanceLog(
            "commit_selection_enter",
            "cards=\(movingCards.count) enter_ms=\(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - enterStartedAt) * 1000))"
        )
        let captureStartedAt = CFAbsoluteTimeGetCurrent()
        let previousState = captureScenarioState()
        indexBoardDropPerformanceLog(
            "commit_selection_capture_state",
            "ms=\(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - captureStartedAt) * 1000))"
        )
        let updatedDetachedPositionsByCardID = resolvedIndexBoardDetachedPositionsAfterRemovingCards(
            movingIDs
        )

        let destination = resolvedIndexBoardCardDestination(
            movingCard: draggedCard,
            target: target,
            targetGroup: targetGroup,
            visibleCards: visibleCards,
            insertionIndex: safeInsertionIndex,
            projection: liveProjection
        )

        let destinationParent = destination.parent
        var resolvedInsertionIndex = destination.index
        let destinationParentID = destinationParent?.id
        let movedBeforeDestination = movingCards.filter {
            $0.parent?.id == destinationParentID && $0.orderIndex < resolvedInsertionIndex
        }.count
        resolvedInsertionIndex -= movedBeforeDestination
        resolvedInsertionIndex = max(0, resolvedInsertionIndex)

        let isNoOp =
            movingCards.allSatisfy { $0.parent?.id == destinationParentID } &&
            movingCards.enumerated().allSatisfy { offset, card in
                card.orderIndex == resolvedInsertionIndex + offset
            }
        if isNoOp {
            return
        }

        let oldParents = movingCards.map(\.parent)
        let mutationStartedAt = CFAbsoluteTimeGetCurrent()
        scenario.performBatchedCardMutation {
            let destinationSiblings = liveOrderedSiblings(parent: destinationParent)
            for sibling in destinationSiblings where !movingIDs.contains(sibling.id) && sibling.orderIndex >= resolvedInsertionIndex {
                sibling.orderIndex += movingCards.count
            }

            for (offset, card) in movingCards.enumerated() {
                let previousParent = card.parent
                if card.isArchived {
                    card.isArchived = false
                }
                card.parent = destinationParent
                card.orderIndex = resolvedInsertionIndex + offset
                card.isFloating = false
                synchronizeMovedSubtreeCategoryIfNeeded(
                    for: card,
                    oldParent: previousParent,
                    newParent: destinationParent
                )
            }

            normalizeAffectedParents(oldParents: oldParents, destinationParent: destinationParent)
        }
        indexBoardDropPerformanceLog(
            "commit_selection_model_mutation",
            "ms=\(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - mutationStartedAt) * 1000))"
        )

        let surfaceStartedAt = CFAbsoluteTimeGetCurrent()
        if let normalizedSurfaceProjection = resolvedIndexBoardSurfaceProjection(
            referenceSurfaceProjection: referenceSurfaceProjection,
            overridingDetachedPositionsByCardID: updatedDetachedPositionsByCardID
        ) {
            persistIndexBoardSurfacePresentation(normalizedSurfaceProjection)
        }
        indexBoardDropPerformanceLog(
            "commit_selection_surface_persist",
            "ms=\(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - surfaceStartedAt) * 1000))"
        )

        let uiStateStartedAt = CFAbsoluteTimeGetCurrent()
        selectedCardIDs = movingIDs
        changeActiveCard(to: draggedCard, shouldFocusMain: false, deferToMainAsync: false, force: true)
        indexBoardDropPerformanceLog(
            "commit_selection_ui_state",
            "ms=\(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - uiStateStartedAt) * 1000))"
        )
        scheduleIndexBoardCommitCardMutation(
            previousState: previousState,
            actionName: "보드 카드 이동"
        )
    }

    func commitIndexBoardCardMove(
        cardID: UUID,
        target: IndexBoardCardDropTarget,
        projection: IndexBoardProjection
    ) {
        let enterStartedAt = CFAbsoluteTimeGetCurrent()
        let liveProjection = resolvedIndexBoardProjection() ?? projection
        let referenceSurfaceProjection = resolvedIndexBoardSurfaceProjection()
        guard let movingCard = findCard(by: cardID) else { return }
        let isCurrentlyDetached = activeIndexBoardSession?.detachedGridPositionByCardID[movingCard.id] != nil

        if target.isTempStripTarget {
            commitDetachedIndexBoardCardMove(
                movingCard: movingCard,
                target: target
            )
            return
        }

        guard let targetGroup = liveProjection.groups.first(where: { $0.id == target.groupID }) else { return }
        let visibleCards = targetGroup.childCards.filter { $0.id != movingCard.id }
        let safeInsertionIndex = min(max(0, target.insertionIndex), visibleCards.count)

        if !isCurrentlyDetached,
           let sourceGroup = liveProjection.groups.first(where: { group in
            group.childCards.contains(where: { $0.id == movingCard.id })
        }),
           let sourceIndex = sourceGroup.childCards.firstIndex(where: { $0.id == movingCard.id }),
           sourceGroup.id == target.groupID,
           sourceIndex == safeInsertionIndex {
            return
        }

        indexBoardDropPerformanceLog(
            "commit_single_enter",
            "card=\(cardID.uuidString) enter_ms=\(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - enterStartedAt) * 1000))"
        )
        let captureStartedAt = CFAbsoluteTimeGetCurrent()
        let previousState = captureScenarioState()
        indexBoardDropPerformanceLog(
            "commit_single_capture_state",
            "ms=\(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - captureStartedAt) * 1000))"
        )
        let updatedDetachedPositionsByCardID = resolvedIndexBoardDetachedPositionsAfterRemovingCards([movingCard.id])

        let destination = resolvedIndexBoardCardDestination(
            movingCard: movingCard,
            target: target,
            targetGroup: targetGroup,
            visibleCards: visibleCards,
            insertionIndex: safeInsertionIndex,
            projection: liveProjection
        )

        let mutationStartedAt = CFAbsoluteTimeGetCurrent()
        scenario.performBatchedCardMutation {
            applyIndexBoardParentPlacement(
                movingCard: movingCard,
                destinationParent: destination.parent,
                destinationIndex: destination.index
            )
        }
        indexBoardDropPerformanceLog(
            "commit_single_model_mutation",
            "ms=\(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - mutationStartedAt) * 1000))"
        )

        let surfaceStartedAt = CFAbsoluteTimeGetCurrent()
        if let normalizedSurfaceProjection = resolvedIndexBoardSurfaceProjection(
            referenceSurfaceProjection: referenceSurfaceProjection,
            overridingDetachedPositionsByCardID: updatedDetachedPositionsByCardID
        ) {
            persistIndexBoardSurfacePresentation(normalizedSurfaceProjection)
        }
        indexBoardDropPerformanceLog(
            "commit_single_surface_persist",
            "ms=\(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - surfaceStartedAt) * 1000))"
        )

        let uiStateStartedAt = CFAbsoluteTimeGetCurrent()
        selectedCardIDs = [movingCard.id]
        changeActiveCard(to: movingCard, shouldFocusMain: false, deferToMainAsync: false, force: true)
        indexBoardDropPerformanceLog(
            "commit_single_ui_state",
            "ms=\(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - uiStateStartedAt) * 1000))"
        )
        scheduleIndexBoardCommitCardMutation(
            previousState: previousState,
            actionName: "보드 카드 이동"
        )
    }

    private func commitDetachedIndexBoardCardMove(
        movingCard: SceneCard,
        target: IndexBoardCardDropTarget
    ) {
        let enterStartedAt = CFAbsoluteTimeGetCurrent()
        let referenceSurfaceProjection = resolvedIndexBoardSurfaceProjection()
        let captureStartedAt = CFAbsoluteTimeGetCurrent()
        let previousState = captureScenarioState()
        indexBoardDropPerformanceLog(
            "commit_detached_capture_state",
            "card=\(movingCard.id.uuidString) enter_ms=\(String(format: "%.3f", (captureStartedAt - enterStartedAt) * 1000)) ms=\(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - captureStartedAt) * 1000))"
        )
        let updatedTempStrips = resolvedUpdatedIndexBoardTempStrips(
            referenceSurfaceProjection: referenceSurfaceProjection,
            movingMembers: [IndexBoardTempStripMember(kind: .card, id: movingCard.id)],
            target: target
        )

        let mutationStartedAt = CFAbsoluteTimeGetCurrent()
        scenario.performBatchedCardMutation {
            let tempContainer = ensureIndexBoardTempContainer()
            applyIndexBoardParentPlacement(
                movingCard: movingCard,
                destinationParent: tempContainer,
                destinationIndex: liveOrderedSiblings(parent: tempContainer).count
            )
            applyIndexBoardTempStripOrdering(updatedTempStrips)
        }
        indexBoardDropPerformanceLog(
            "commit_detached_model_mutation",
            "ms=\(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - mutationStartedAt) * 1000))"
        )

        let surfaceStartedAt = CFAbsoluteTimeGetCurrent()
        if let normalizedSurfaceProjection = resolvedIndexBoardSurfaceProjection(
            referenceSurfaceProjection: referenceSurfaceProjection,
            overridingTempStrips: updatedTempStrips
        ) {
            persistIndexBoardSurfacePresentation(normalizedSurfaceProjection)
        }
        indexBoardDropPerformanceLog(
            "commit_detached_surface_persist",
            "ms=\(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - surfaceStartedAt) * 1000))"
        )

        let uiStateStartedAt = CFAbsoluteTimeGetCurrent()
        selectedCardIDs = [movingCard.id]
        changeActiveCard(to: movingCard, shouldFocusMain: false, deferToMainAsync: false, force: true)
        indexBoardDropPerformanceLog(
            "commit_detached_ui_state",
            "ms=\(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - uiStateStartedAt) * 1000))"
        )
        scheduleIndexBoardCommitCardMutation(
            previousState: previousState,
            actionName: "보드 카드 이동"
        )
    }

    private func commitDetachedIndexBoardCardMoveSelection(
        movingCards: [SceneCard],
        draggedCard: SceneCard,
        target: IndexBoardCardDropTarget
    ) {
        let enterStartedAt = CFAbsoluteTimeGetCurrent()
        let movingIDs = Set(movingCards.map(\.id))
        let referenceSurfaceProjection = resolvedIndexBoardSurfaceProjection()
        let captureStartedAt = CFAbsoluteTimeGetCurrent()
        let previousState = captureScenarioState()
        indexBoardDropPerformanceLog(
            "commit_detached_selection_capture_state",
            "cards=\(movingCards.count) enter_ms=\(String(format: "%.3f", (captureStartedAt - enterStartedAt) * 1000)) ms=\(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - captureStartedAt) * 1000))"
        )
        let updatedTempStrips = resolvedUpdatedIndexBoardTempStrips(
            referenceSurfaceProjection: referenceSurfaceProjection,
            movingMembers: movingCards.map { IndexBoardTempStripMember(kind: .card, id: $0.id) },
            target: target
        )

        let mutationStartedAt = CFAbsoluteTimeGetCurrent()
        scenario.performBatchedCardMutation {
            let tempContainer = ensureIndexBoardTempContainer()
            for card in movingCards {
                applyIndexBoardParentPlacement(
                    movingCard: card,
                    destinationParent: tempContainer,
                    destinationIndex: liveOrderedSiblings(parent: tempContainer).count
                )
            }
            applyIndexBoardTempStripOrdering(updatedTempStrips)
        }
        indexBoardDropPerformanceLog(
            "commit_detached_selection_model_mutation",
            "ms=\(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - mutationStartedAt) * 1000))"
        )

        let surfaceStartedAt = CFAbsoluteTimeGetCurrent()
        if let normalizedSurfaceProjection = resolvedIndexBoardSurfaceProjection(
            referenceSurfaceProjection: referenceSurfaceProjection,
            overridingTempStrips: updatedTempStrips
        ) {
            persistIndexBoardSurfacePresentation(normalizedSurfaceProjection)
        }
        indexBoardDropPerformanceLog(
            "commit_detached_selection_surface_persist",
            "ms=\(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - surfaceStartedAt) * 1000))"
        )

        let uiStateStartedAt = CFAbsoluteTimeGetCurrent()
        selectedCardIDs = movingIDs
        changeActiveCard(to: draggedCard, shouldFocusMain: false, deferToMainAsync: false, force: true)
        indexBoardDropPerformanceLog(
            "commit_detached_selection_ui_state",
            "ms=\(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - uiStateStartedAt) * 1000))"
        )
        scheduleIndexBoardCommitCardMutation(
            previousState: previousState,
            actionName: "보드 카드 이동"
        )
    }
}
