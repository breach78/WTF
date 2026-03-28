import SwiftUI
import AppKit

extension ScenarioWriterView {
    func commitIndexBoardGroupMove(
        groupID: IndexBoardGroupID,
        targetIndex: Int,
        projection: IndexBoardProjection
    ) {
        let liveProjection = resolvedIndexBoardProjection() ?? projection
        guard let movingGroup = liveProjection.groups.first(where: { $0.id == groupID }),
              let movingParentCard = movingGroup.parentCard else { return }
        let visibleGroups = liveProjection.groups.filter { $0.id != groupID && !$0.isTempGroup && $0.parentCard != nil }
        let currentVisibleGroups = liveProjection.groups.filter { !$0.isTempGroup && $0.parentCard != nil }
        let safeTargetIndex = min(max(0, targetIndex), visibleGroups.count)
        if let sourceIndex = currentVisibleGroups.firstIndex(where: { $0.id == groupID }),
           sourceIndex == safeTargetIndex,
           !movingGroup.isTempGroup {
            return
        }

        let previousState = captureScenarioState()
        scenario.performBatchedCardMutation {
            applyIndexBoardGroupMove(
                movingParentCard: movingParentCard,
                context: IndexBoardResolvedGroupMoveContext(
                    groups: resolvedIndexBoardProjection() ?? projection,
                    movingGroupID: groupID,
                    targetIndex: safeTargetIndex
                )
            )
        }

        scheduleIndexBoardCommitCardMutation(
            previousState: previousState,
            actionName: "보드 그룹 이동"
        )
    }

    func commitIndexBoardParentGroupMove(
        target: IndexBoardParentGroupDropTarget,
        projection: IndexBoardProjection
    ) {
        if let surfaceProjection = resolvedIndexBoardSurfaceProjection(),
           let movingGroup = surfaceProjection.parentGroups.first(where: { $0.parentCardID == target.parentCardID }),
           movingGroup.isTempGroup {
            let previousState = captureScenarioState()
            let updatedTempStrips = resolvedUpdatedIndexBoardTempStrips(
                referenceSurfaceProjection: surfaceProjection,
                movingMembers: [IndexBoardTempStripMember(kind: .group, id: target.parentCardID)],
                target: IndexBoardCardDropTarget(
                    groupID: .parent(target.parentCardID),
                    insertionIndex: 0,
                    detachedGridPosition: target.origin
                )
            )
            scenario.performBatchedCardMutation {
                applyIndexBoardTempStripOrdering(updatedTempStrips)
            }
            if let normalizedSurfaceProjection = resolvedIndexBoardSurfaceProjection(
                referenceSurfaceProjection: surfaceProjection,
                overridingTempStrips: updatedTempStrips
            ) {
                persistIndexBoardSurfacePresentation(normalizedSurfaceProjection)
            }
            scheduleIndexBoardCommitCardMutation(
                previousState: previousState,
                actionName: "보드 부모 그룹 이동"
            )
            return
        }
        let previousState = captureScenarioState()
        guard let surfaceProjection = resolvedIndexBoardSurfaceProjection(
            preferredLeadingParentCardID: target.parentCardID,
            overridingGroupPositionsByParentID: [target.parentCardID: target.origin]
        ) else { return }
        persistIndexBoardSurfacePresentation(surfaceProjection)
        scenario.performBatchedCardMutation {
            applyIndexBoardSurfaceParentOrdering(
                surfaceProjection: surfaceProjection,
                projection: projection
            )
        }

        scheduleIndexBoardCommitCardMutation(
            previousState: previousState,
            actionName: "보드 부모 그룹 이동"
        )
    }

    func setIndexBoardParentGroupTemp(
        parentCardID: UUID,
        isTemp: Bool,
        projection: IndexBoardProjection
    ) {
        guard isIndexBoardActive,
              parentCardID != activeIndexBoardSession?.source.parentID,
              let movingParentCard = findCard(by: parentCardID) else { return }

        let previousState = captureScenarioState()
        scenario.performBatchedCardMutation {
            if isTemp {
                let tempContainer = ensureIndexBoardTempContainer()
                applyIndexBoardParentPlacement(
                    movingCard: movingParentCard,
                    destinationParent: tempContainer,
                    destinationIndex: liveOrderedSiblings(parent: tempContainer).count
                )
            } else {
                let sourceParent = activeIndexBoardSession?.source.parentID.flatMap { findCard(by: $0) }
                applyIndexBoardParentPlacement(
                    movingCard: movingParentCard,
                    destinationParent: sourceParent,
                    destinationIndex: liveOrderedSiblings(parent: sourceParent).count
                )
            }

            if let surfaceProjection = resolvedIndexBoardSurfaceProjection() {
                applyIndexBoardSurfaceParentOrdering(
                    surfaceProjection: surfaceProjection,
                    projection: projection
                )
            }
        }

        scheduleIndexBoardCommitCardMutation(
            previousState: previousState,
            actionName: isTemp ? "보드 그룹 Temp 이동" : "보드 그룹 Temp 복귀"
        )
    }
}
