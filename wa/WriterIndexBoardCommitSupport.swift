import SwiftUI
import AppKit

extension ScenarioWriterView {
    func applyIndexBoardSurfaceParentOrdering(
        surfaceProjection: BoardSurfaceProjection,
        projection: IndexBoardProjection
    ) {
        let desiredMainlineParentIDs = surfaceProjection.parentGroups
            .filter { !$0.isTempGroup }
            .compactMap(\.parentCardID)
        let desiredTempParentIDs = surfaceProjection.parentGroups
            .filter(\.isTempGroup)
            .compactMap(\.parentCardID)
        let desiredTempParentIDSet = Set(desiredTempParentIDs)
        let sourceParent = activeIndexBoardSession?.source.parentID.flatMap { findCard(by: $0) }
        let tempContainer = ensureIndexBoardTempContainer()

        let tempStartIndex = liveOrderedSiblings(parent: tempContainer)
            .filter { !desiredTempParentIDSet.contains($0.id) }
            .count

        for (offset, parentID) in desiredTempParentIDs.enumerated() {
            guard parentID != sourceParent?.id else { continue }
            guard let parentCard = findCard(by: parentID) else { continue }
            applyIndexBoardParentPlacement(
                movingCard: parentCard,
                destinationParent: tempContainer,
                destinationIndex: tempStartIndex + offset
            )
        }

        for (targetIndex, parentID) in desiredMainlineParentIDs.enumerated() {
            guard parentID != sourceParent?.id else { continue }
            guard let parentCard = findCard(by: parentID) else { continue }
            let currentProjection = resolvedIndexBoardProjection() ?? projection
            let movingGroupID = IndexBoardGroupID.parent(parentID)
            let visibleGroups = currentProjection.groups.filter {
                $0.id != movingGroupID && !$0.isTempGroup && $0.parentCard != nil
            }
            let safeTargetIndex = min(max(0, targetIndex), visibleGroups.count)
            let previousGroup = safeTargetIndex > 0 ? visibleGroups[safeTargetIndex - 1] : nil
            let nextGroup = safeTargetIndex < visibleGroups.count ? visibleGroups[safeTargetIndex] : nil

            if previousGroup == nil && nextGroup == nil {
                applyIndexBoardParentPlacement(
                    movingCard: parentCard,
                    destinationParent: sourceParent,
                    destinationIndex: 0
                )
            } else {
                applyIndexBoardGroupMove(
                    movingParentCard: parentCard,
                    context: IndexBoardResolvedGroupMoveContext(
                        previousGroup: previousGroup,
                        nextGroup: nextGroup
                    )
                )
            }
        }
    }

    func applyIndexBoardGroupMove(
        movingParentCard: SceneCard,
        context: IndexBoardResolvedGroupMoveContext
    ) {
        let destination = resolvedIndexBoardGroupDestination(
            movingParentCard: movingParentCard,
            previousGroup: context.previousGroup,
            nextGroup: context.nextGroup
        )
        applyIndexBoardParentPlacement(
            movingCard: movingParentCard,
            destinationParent: destination.parent,
            destinationIndex: destination.index
        )
    }

    func applyIndexBoardParentPlacement(
        movingCard: SceneCard,
        destinationParent: SceneCard?,
        destinationIndex: Int
    ) {
        guard isValidIndexBoardParent(destinationParent, for: movingCard) else { return }
        if movingCard.isArchived {
            movingCard.isArchived = false
        }

        let oldParent = movingCard.parent
        normalizeIndices(parent: oldParent)

        let safeDestinationIndex = max(0, destinationIndex)
        if oldParent?.id == destinationParent?.id {
            var siblings = liveOrderedSiblings(parent: destinationParent)
            if let currentIndex = siblings.firstIndex(where: { $0.id == movingCard.id }) {
                siblings.remove(at: currentIndex)
                let insertionIndex = min(
                    max(
                        0,
                        safeDestinationIndex - (currentIndex < safeDestinationIndex ? 1 : 0)
                    ),
                    siblings.count
                )
                siblings.insert(movingCard, at: insertionIndex)

                for (index, sibling) in siblings.enumerated() {
                    sibling.parent = destinationParent
                    sibling.orderIndex = index
                }
                movingCard.isFloating = false

                synchronizeMovedSubtreeCategoryIfNeeded(
                    for: movingCard,
                    oldParent: oldParent,
                    newParent: movingCard.parent
                )
                return
            }
        }

        let insertionIndex = min(safeDestinationIndex, liveOrderedSiblings(parent: destinationParent).count)

        let destinationSiblings = liveOrderedSiblings(parent: destinationParent)
        for sibling in destinationSiblings where sibling.id != movingCard.id && sibling.orderIndex >= insertionIndex {
            sibling.orderIndex += 1
        }

        movingCard.parent = destinationParent
        movingCard.orderIndex = insertionIndex
        movingCard.isFloating = false

        normalizeIndices(parent: movingCard.parent)
        if oldParent?.id != movingCard.parent?.id {
            normalizeIndices(parent: oldParent)
        }

        synchronizeMovedSubtreeCategoryIfNeeded(
            for: movingCard,
            oldParent: oldParent,
            newParent: movingCard.parent
        )
    }

    func resolvedIndexBoardCardDestination(
        movingCard: SceneCard,
        target: IndexBoardCardDropTarget,
        targetGroup: IndexBoardGroupProjection,
        visibleCards: [SceneCard],
        insertionIndex: Int,
        projection: IndexBoardProjection
    ) -> (parent: SceneCard?, index: Int) {
        if let exactDestination = resolvedExactIndexBoardCardDestination(
            movingCard: movingCard,
            target: target
        ) {
            return exactDestination
        }

        let previousCard = insertionIndex > 0 ? visibleCards[insertionIndex - 1] : nil
        let nextCard = insertionIndex < visibleCards.count ? visibleCards[insertionIndex] : nil

        if let previousCard, let candidateParent = previousCard.parent,
           isValidIndexBoardParent(candidateParent, for: movingCard) {
            return (candidateParent, previousCard.orderIndex + 1)
        }

        if let nextCard, let candidateParent = nextCard.parent,
           isValidIndexBoardParent(candidateParent, for: movingCard) {
            return (candidateParent, nextCard.orderIndex)
        }

        if let ancestorParent = firstValidIndexBoardAncestorParent(
            startingAt: previousCard?.parent?.parent,
            movingCard: movingCard
        ) {
            return (ancestorParent, liveOrderedSiblings(parent: ancestorParent).count)
        }

        if let ancestorParent = firstValidIndexBoardAncestorParent(
            startingAt: nextCard?.parent?.parent,
            movingCard: movingCard
        ) {
            return (ancestorParent, liveOrderedSiblings(parent: ancestorParent).count)
        }

        let fallbackParent = targetGroup.parentCard
        if isValidIndexBoardParent(fallbackParent, for: movingCard) {
            if fallbackParent?.id == movingCard.parent?.id {
                return (fallbackParent, insertionIndex)
            }
            return (fallbackParent, liveOrderedSiblings(parent: fallbackParent).count)
        }

        let safeParent = projection.source.parentID.flatMap { findCard(by: $0) }
        return (safeParent, liveOrderedSiblings(parent: safeParent).count)
    }

    private func resolvedExactIndexBoardCardDestination(
        movingCard: SceneCard,
        target: IndexBoardCardDropTarget
    ) -> (parent: SceneCard?, index: Int)? {
        let previousCard = target.previousCardID.flatMap { candidateID -> SceneCard? in
            guard candidateID != movingCard.id else { return nil }
            return findCard(by: candidateID)
        }
        let nextCard = target.nextCardID.flatMap { candidateID -> SceneCard? in
            guard candidateID != movingCard.id else { return nil }
            return findCard(by: candidateID)
        }

        if let previousCard,
           let nextCard,
           previousCard.parent?.id == nextCard.parent?.id,
           isValidIndexBoardParent(previousCard.parent, for: movingCard) {
            return (previousCard.parent, nextCard.orderIndex)
        }

        let hintedParent = target.laneParentID.flatMap { findCard(by: $0) }
        if let nextCard,
           nextCard.parent?.id == target.laneParentID,
           isValidIndexBoardParent(nextCard.parent, for: movingCard) {
            return (nextCard.parent, nextCard.orderIndex)
        }

        if let previousCard,
           previousCard.parent?.id == target.laneParentID,
           isValidIndexBoardParent(previousCard.parent, for: movingCard) {
            return (previousCard.parent, previousCard.orderIndex + 1)
        }

        if previousCard == nil,
           nextCard == nil,
           isValidIndexBoardParent(hintedParent, for: movingCard) {
            return (hintedParent, max(0, target.insertionIndex))
        }

        if let previousCard,
           nextCard == nil,
           isValidIndexBoardParent(previousCard.parent, for: movingCard) {
            return (previousCard.parent, previousCard.orderIndex + 1)
        }

        if previousCard == nil,
           let nextCard,
           isValidIndexBoardParent(nextCard.parent, for: movingCard) {
            return (nextCard.parent, nextCard.orderIndex)
        }

        return nil
    }

    func resolvedIndexBoardDetachedPositionsAfterRemovingCards(
        _ cardIDs: some Sequence<UUID>
    ) -> [UUID: IndexBoardGridPosition] {
        var detachedPositionsByCardID = activeIndexBoardSession?.detachedGridPositionByCardID ?? [:]
        for cardID in cardIDs {
            detachedPositionsByCardID.removeValue(forKey: cardID)
        }
        return detachedPositionsByCardID
    }

    private func resolvedIndexBoardTempGroupWidths(
        surfaceProjection: BoardSurfaceProjection?
    ) -> [UUID: Int] {
        Dictionary(
            uniqueKeysWithValues: surfaceProjection?.parentGroups.compactMap { placement in
                guard placement.isTempGroup,
                      let parentCardID = placement.parentCardID else {
                    return nil
                }
                return (parentCardID, placement.width)
            } ?? []
        )
    }

    func resolvedUpdatedIndexBoardTempStrips(
        referenceSurfaceProjection: BoardSurfaceProjection?,
        movingMembers: [IndexBoardTempStripMember],
        target: IndexBoardCardDropTarget
    ) -> [IndexBoardTempStripState] {
        resolvedIndexBoardTempStripsByApplyingMove(
            strips: referenceSurfaceProjection?.tempStrips ?? [],
            movingMembers: movingMembers,
            previousMember: target.previousTempMember,
            nextMember: target.nextTempMember,
            parkingPosition: target.detachedGridPosition
        )
    }

    func applyIndexBoardTempStripOrdering(
        _ strips: [IndexBoardTempStripState]
    ) {
        guard let tempContainer = resolvedIndexBoardTempContainer() else { return }
        let orderedMemberIDs = strips
            .sorted { lhs, rhs in
                if lhs.row != rhs.row { return lhs.row < rhs.row }
                if lhs.anchorColumn != rhs.anchorColumn { return lhs.anchorColumn < rhs.anchorColumn }
                return lhs.id < rhs.id
            }
            .flatMap(\.members)
            .map(\.id)
        let uniqueOrderedIDs = orderedMemberIDs.reduce(into: [UUID]()) { partialResult, cardID in
            if !partialResult.contains(cardID) {
                partialResult.append(cardID)
            }
        }
        let tempChildren = liveOrderedSiblings(parent: tempContainer)
        let remainingIDs = tempChildren.map(\.id).filter { !uniqueOrderedIDs.contains($0) }
        let finalIDs = uniqueOrderedIDs + remainingIDs

        for (index, cardID) in finalIDs.enumerated() {
            guard let card = findCard(by: cardID) else { continue }
            card.parent = tempContainer
            card.orderIndex = index
            card.isFloating = false
        }

        normalizeIndices(parent: tempContainer)
    }

    private func reindexIndexBoardDetachedSiblingsVisually(preferredColumns: Int?) {
        guard let tempContainer = resolvedIndexBoardTempContainer() else { return }
        reindexIndexBoardSiblingsVisually(
            parent: tempContainer,
            preferredColumns: max(1, preferredColumns ?? 1)
        )
    }

    private func reindexIndexBoardSiblingsVisually(
        parent: SceneCard?,
        preferredColumns: Int
    ) {
        let surfaceProjection = resolvedIndexBoardSurfaceProjection()
        let positionByCardID = resolvedIndexBoardVisualGridPositionByCardID(
            surfaceProjection: surfaceProjection,
            preferredColumns: preferredColumns
        )
        let siblings = liveOrderedSiblings(parent: parent)
        let orderedSiblings = siblings.enumerated().sorted { lhs, rhs in
            let lhsPosition = positionByCardID[lhs.element.id] ?? IndexBoardGridPosition(column: lhs.offset, row: .max / 4)
            let rhsPosition = positionByCardID[rhs.element.id] ?? IndexBoardGridPosition(column: rhs.offset, row: .max / 4)
            if lhsPosition.row != rhsPosition.row {
                return lhsPosition.row < rhsPosition.row
            }
            if lhsPosition.column != rhsPosition.column {
                return lhsPosition.column < rhsPosition.column
            }
            if lhs.element.orderIndex != rhs.element.orderIndex {
                return lhs.element.orderIndex < rhs.element.orderIndex
            }
            return lhs.element.id.uuidString < rhs.element.id.uuidString
        }
        .map(\.element)

        for (index, sibling) in orderedSiblings.enumerated() {
            sibling.orderIndex = index
            sibling.isFloating = false
        }

        normalizeIndices(parent: parent)
    }

    private func resolvedIndexBoardVisualGridPositionByCardID(
        surfaceProjection: BoardSurfaceProjection?,
        preferredColumns: Int
    ) -> [UUID: IndexBoardGridPosition] {
        guard let surfaceProjection else { return [:] }
        let safePreferredColumns = max(1, preferredColumns)
        var positionByCardID: [UUID: IndexBoardGridPosition] = [:]
        positionByCardID.reserveCapacity(surfaceProjection.surfaceItems.count)

        for item in surfaceProjection.surfaceItems {
            if let explicitGridPosition = item.gridPosition {
                positionByCardID[item.cardID] = explicitGridPosition
            } else if let detachedGridPosition = item.detachedGridPosition {
                positionByCardID[item.cardID] = detachedGridPosition
            } else if let slotIndex = item.slotIndex {
                positionByCardID[item.cardID] = IndexBoardGridPosition(
                    column: slotIndex % safePreferredColumns,
                    row: slotIndex / safePreferredColumns
                )
            }
        }

        return positionByCardID
    }

    func resolvedIndexBoardMovingCards(
        cardIDs: [UUID],
        preferredColumns: Int
    ) -> [SceneCard] {
        let cards = cardIDs.compactMap { findCard(by: $0) }
        guard !cards.isEmpty else { return [] }

        let positionByCardID = resolvedIndexBoardVisualGridPositionByCardID(
            surfaceProjection: resolvedIndexBoardSurfaceProjection(),
            preferredColumns: preferredColumns
        )

        return cards.enumerated().sorted { lhs, rhs in
            let lhsPosition = positionByCardID[lhs.element.id] ?? IndexBoardGridPosition(column: lhs.offset, row: .max / 4)
            let rhsPosition = positionByCardID[rhs.element.id] ?? IndexBoardGridPosition(column: rhs.offset, row: .max / 4)
            if lhsPosition.row != rhsPosition.row {
                return lhsPosition.row < rhsPosition.row
            }
            if lhsPosition.column != rhsPosition.column {
                return lhsPosition.column < rhsPosition.column
            }
            if lhs.element.orderIndex != rhs.element.orderIndex {
                return lhs.element.orderIndex < rhs.element.orderIndex
            }
            return lhs.element.id.uuidString < rhs.element.id.uuidString
        }
        .map(\.element)
    }

    private func resolvedDetachedSelectionPositions(
        count: Int,
        start: IndexBoardGridPosition,
        occupied: Set<IndexBoardGridPosition>
    ) -> [IndexBoardGridPosition] {
        guard count > 0 else { return [] }
        var positions: [IndexBoardGridPosition] = []
        positions.reserveCapacity(count)
        var taken = occupied
        var nextColumn = start.column
        let row = start.row

        while positions.count < count {
            let candidate = IndexBoardGridPosition(column: nextColumn, row: row)
            if !taken.contains(candidate) {
                positions.append(candidate)
                taken.insert(candidate)
            }
            nextColumn += 1
        }

        return positions
    }

    private func resolvedIndexBoardGroupDestination(
        movingParentCard: SceneCard,
        previousGroup: IndexBoardGroupProjection?,
        nextGroup: IndexBoardGroupProjection?
    ) -> (parent: SceneCard?, index: Int) {
        if let previousGroup,
           let previousParentCard = previousGroup.parentCard,
           let candidateParent = previousParentCard.parent,
           isValidIndexBoardParent(candidateParent, for: movingParentCard) {
            return (candidateParent, previousParentCard.orderIndex + 1)
        }

        if let nextGroup,
           let nextParentCard = nextGroup.parentCard,
           let candidateParent = nextParentCard.parent,
           isValidIndexBoardParent(candidateParent, for: movingParentCard) {
            return (candidateParent, nextParentCard.orderIndex)
        }

        if let ancestorParent = firstValidIndexBoardAncestorParent(
            startingAt: previousGroup?.parentCard?.parent?.parent,
            movingCard: movingParentCard
        ) {
            return (ancestorParent, liveOrderedSiblings(parent: ancestorParent).count)
        }

        if let ancestorParent = firstValidIndexBoardAncestorParent(
            startingAt: nextGroup?.parentCard?.parent?.parent,
            movingCard: movingParentCard
        ) {
            return (ancestorParent, liveOrderedSiblings(parent: ancestorParent).count)
        }

        let fallbackParent = movingParentCard.parent
        return (fallbackParent, liveOrderedSiblings(parent: fallbackParent).count)
    }

    private func firstValidIndexBoardAncestorParent(
        startingAt candidate: SceneCard?,
        movingCard: SceneCard
    ) -> SceneCard? {
        var current = candidate
        var visited: Set<UUID> = []
        while let parent = current {
            guard visited.insert(parent.id).inserted else { return nil }
            if isValidIndexBoardParent(parent, for: movingCard) {
                return parent
            }
            current = parent.parent
        }
        return nil
    }

    private func isValidIndexBoardParent(
        _ candidateParent: SceneCard?,
        for movingCard: SceneCard
    ) -> Bool {
        guard let candidateParent else { return true }
        if candidateParent.id == movingCard.id {
            return false
        }
        return !isDescendant(movingCard, of: candidateParent.id)
    }
}
