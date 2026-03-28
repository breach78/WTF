import SwiftUI
import AppKit

extension IndexBoardSurfaceAppKitDocumentView {
    var effectiveSurfaceProjection: BoardSurfaceProjection {
        presentationSurfaceProjection ?? configuration.surfaceProjection
    }

    var dragReferenceProjection: BoardSurfaceProjection {
        restingSceneSnapshot?.projection ?? configuration.surfaceProjection
    }

    var interactionProjection: BoardSurfaceProjection {
        restingSceneSnapshot?.projection ?? effectiveSurfaceProjection
    }

    var orderedItems: [BoardSurfaceItem] {
        effectiveSurfaceProjection.surfaceItems.sorted(by: indexBoardSurfaceAppKitSort)
    }

    var dragLogicalSnapshot: IndexBoardSurfaceAppKitLogicalSnapshot {
        let projection: BoardSurfaceProjection
        let orderedItems: [BoardSurfaceItem]

        if let restingSceneSnapshot {
            projection = restingSceneSnapshot.projection
            orderedItems = restingSceneSnapshot.orderedItems
        } else {
            projection = canonicalizedSnapshotProjection(
                from: effectiveSurfaceProjection,
                frameByID: cardFrameByID
            )
            orderedItems = projection.surfaceItems.sorted(by: indexBoardSurfaceAppKitSort)
        }

        let detachedPositionsByCardID = Dictionary(
            uniqueKeysWithValues: orderedItems.compactMap { item -> (UUID, IndexBoardGridPosition)? in
                guard item.parentGroupID == nil,
                      let position = item.detachedGridPosition ?? item.gridPosition else {
                    return nil
                }
                return (item.cardID, position)
            }
        )

        return IndexBoardSurfaceAppKitLogicalSnapshot(
            projection: projection,
            orderedItems: orderedItems,
            detachedPositionsByCardID: detachedPositionsByCardID,
            tempStrips: projection.tempStrips,
            tempGroupWidthsByParentID: resolvedTempGroupWidthsByParentID(from: projection)
        )
    }

    var hiddenCardIDs: Set<UUID> {
        Set((dragState?.movingCardIDs ?? []) + (groupDragState?.movingCardIDs ?? []))
    }

    var interactionOrderedItems: [BoardSurfaceItem] {
        restingSceneSnapshot?.orderedItems ?? orderedItems
    }

    var parentGroupByID: [BoardSurfaceParentGroupID: BoardSurfaceParentGroupPlacement] {
        Dictionary(uniqueKeysWithValues: effectiveSurfaceProjection.parentGroups.map { ($0.id, $0) })
    }

    func pendingCardMove(
        for drag: IndexBoardSurfaceAppKitDragState
    ) -> IndexBoardSurfaceAppKitPendingCardMove {
        IndexBoardSurfaceAppKitPendingCardMove(
            logicalSnapshot: dragLogicalSnapshot,
            movingCardIDs: drag.movingCardIDs,
            movingCardIDSet: drag.movingCardIDSet,
            movingTempMembers: drag.movingTempMembers,
            sourceLaneParentID: drag.sourceLaneParentID,
            target: drag.dropTarget
        )
    }

    func parentGroup(for item: BoardSurfaceItem) -> BoardSurfaceParentGroupPlacement? {
        guard let parentGroupID = item.parentGroupID else { return nil }
        return parentGroupByID[parentGroupID]
    }

    func canonicalCardIDsByGroupID(
        from projection: BoardSurfaceProjection,
        frameByID: [UUID: CGRect]? = nil
    ) -> [BoardSurfaceParentGroupID: [UUID]] {
        let fallbackOrderByCardID = Dictionary(
            uniqueKeysWithValues: projection.surfaceItems
                .sorted(by: indexBoardSurfaceAppKitSort)
                .enumerated()
                .map { ($1.cardID, $0) }
        )

        return Dictionary(
            grouping: projection.surfaceItems.filter { $0.parentGroupID != nil },
            by: { $0.parentGroupID! }
        ).mapValues { items in
            items.sorted { lhs, rhs in
                let lhsFrame = frameByID?[lhs.cardID]
                let rhsFrame = frameByID?[rhs.cardID]
                if let lhsFrame, let rhsFrame {
                    if lhsFrame.minY != rhsFrame.minY {
                        return lhsFrame.minY < rhsFrame.minY
                    }
                    if lhsFrame.minX != rhsFrame.minX {
                        return lhsFrame.minX < rhsFrame.minX
                    }
                } else if lhsFrame != nil {
                    return true
                } else if rhsFrame != nil {
                    return false
                }

                let lhsFallback = fallbackOrderByCardID[lhs.cardID] ?? .max
                let rhsFallback = fallbackOrderByCardID[rhs.cardID] ?? .max
                if lhsFallback != rhsFallback {
                    return lhsFallback < rhsFallback
                }
                return lhs.cardID.uuidString < rhs.cardID.uuidString
            }.map(\.cardID)
        }
    }

    func canonicalizedSnapshotProjection(
        from projection: BoardSurfaceProjection,
        frameByID: [UUID: CGRect]
    ) -> BoardSurfaceProjection {
        let canonicalIDsByGroupID = canonicalCardIDsByGroupID(
            from: projection,
            frameByID: frameByID
        )
        let laneIndexByParentID = Dictionary(
            uniqueKeysWithValues: projection.lanes.map { ($0.parentCardID, $0.laneIndex) }
        )
        let detachedItems = projection.surfaceItems.filter { $0.parentGroupID == nil }
        let updatedParentGroups = projection.parentGroups.map { placement in
            BoardSurfaceParentGroupPlacement(
                id: placement.id,
                parentCardID: placement.parentCardID,
                origin: placement.origin,
                cardIDs: canonicalIDsByGroupID[placement.id] ?? placement.cardIDs,
                titleText: placement.titleText,
                subtitleText: placement.subtitleText,
                colorToken: placement.colorToken,
                isMainline: placement.isMainline,
                isTempGroup: placement.isTempGroup
            )
        }
        let regroupedItems = updatedParentGroups.flatMap { placement in
            let laneIndex = laneIndexByParentID[placement.parentCardID] ?? 0
            return placement.cardIDs.enumerated().map { index, cardID in
                BoardSurfaceItem(
                    cardID: cardID,
                    laneParentID: placement.parentCardID,
                    laneIndex: laneIndex,
                    slotIndex: nil,
                    detachedGridPosition: nil,
                    gridPosition: IndexBoardGridPosition(
                        column: placement.origin.column + index,
                        row: placement.origin.row
                    ),
                    parentGroupID: placement.id
                )
            }
        }
        let sortedItems = (regroupedItems + detachedItems).sorted(by: indexBoardSurfaceAppKitSort)
        return BoardSurfaceProjection(
            source: projection.source,
            startAnchor: projection.startAnchor,
            lanes: projection.lanes,
            parentGroups: updatedParentGroups,
            tempStrips: projection.tempStrips,
            surfaceItems: sortedItems,
            orderedCardIDs: sortedItems.map(\.cardID)
        )
    }

    var flowItems: [BoardSurfaceItem] {
        orderedItems.filter { $0.parentGroupID != nil }
    }

    var preferredColumns: Int {
        let availableWidth = max(
            IndexBoardMetrics.cardSize.width,
            configuration.canvasSize.width - (IndexBoardMetrics.boardHorizontalPadding * 2)
        )
        let slotWidth = IndexBoardMetrics.cardSize.width + IndexBoardMetrics.cardSpacing
        let fittedColumns = max(1, Int((availableWidth + IndexBoardMetrics.cardSpacing) / slotWidth))
        return min(max(1, orderedItems.count), fittedColumns)
    }

    var slotSize: CGSize {
        CGSize(
            width: IndexBoardMetrics.cardSize.width,
            height: IndexBoardMetrics.cardSize.height +
                IndexBoardSurfaceAppKitConstants.laneChipHeight +
                IndexBoardSurfaceAppKitConstants.laneChipSpacing
        )
    }

    var surfaceHorizontalInset: CGFloat {
        max(IndexBoardMetrics.boardHorizontalPadding, IndexBoardSurfaceAppKitConstants.minimumCanvasLeadInset)
    }

    var surfaceTopInset: CGFloat {
        max(IndexBoardMetrics.boardVerticalPadding, IndexBoardSurfaceAppKitConstants.minimumCanvasTopInset)
    }

    var surfaceBottomInset: CGFloat {
        IndexBoardMetrics.boardVerticalPadding
    }

    var logicalGridBounds: IndexBoardSurfaceAppKitGridBounds {
        if let restingSceneSnapshot {
            return restingSceneSnapshot.logicalGridBounds
        }
        if let frozenLogicalGridBounds {
            return frozenLogicalGridBounds
        }
        return resolvedLogicalGridBounds(for: Array(occupiedGridPositionByCardID().values))
    }

    func resolvedLogicalGridBounds(
        for positions: [IndexBoardGridPosition]
    ) -> IndexBoardSurfaceAppKitGridBounds {
        let computedBounds = resolvedUnpinnedLogicalGridBounds(for: positions)
        if pinnedLogicalGridOrigin == nil {
            pinnedLogicalGridOrigin = IndexBoardGridPosition(
                column: computedBounds.minColumn,
                row: computedBounds.minRow
            )
        }
        let pinnedOrigin = pinnedLogicalGridOrigin ?? IndexBoardGridPosition(
            column: computedBounds.minColumn,
            row: computedBounds.minRow
        )
        return IndexBoardSurfaceAppKitGridBounds(
            minColumn: pinnedOrigin.column,
            maxColumn: max(computedBounds.maxColumn, pinnedOrigin.column),
            minRow: pinnedOrigin.row,
            maxRow: max(computedBounds.maxRow, pinnedOrigin.row)
        )
    }

    func resolvedUnpinnedLogicalGridBounds(
        for positions: [IndexBoardGridPosition]
    ) -> IndexBoardSurfaceAppKitGridBounds {
        let minColumn = positions.map(\.column).min() ?? 0
        let maxColumn = positions.map(\.column).max() ?? max(0, preferredColumns - 1)
        let minRow = positions.map(\.row).min() ?? 0
        let maxRow = positions.map(\.row).max() ?? 0
        return IndexBoardSurfaceAppKitGridBounds(
            minColumn: minColumn - IndexBoardSurfaceAppKitConstants.detachedOuterPaddingSlots,
            maxColumn: maxColumn + IndexBoardSurfaceAppKitConstants.detachedOuterPaddingSlots,
            minRow: minRow - IndexBoardSurfaceAppKitConstants.detachedOuterPaddingSlots,
            maxRow: maxRow + IndexBoardSurfaceAppKitConstants.detachedOuterPaddingSlots
        )
    }

    func snapshotImage(in rect: CGRect) -> NSImage? {
        guard rect.width > 1, rect.height > 1 else { return nil }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int(ceil(rect.width * scale))),
            pixelsHigh: max(1, Int(ceil(rect.height * scale))),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        rep.size = rect.size
        cacheDisplay(in: rect, to: rep)
        let image = NSImage(size: rect.size)
        image.addRepresentation(rep)
        return image
    }

    func makeRestingSceneSnapshot() -> IndexBoardSurfaceAppKitSceneSnapshot {
        let projection = canonicalizedSnapshotProjection(
            from: effectiveSurfaceProjection,
            frameByID: cardFrameByID
        )
        let orderedItems = projection.surfaceItems.sorted(by: indexBoardSurfaceAppKitSort)
        let occupiedGridPositionByCardID = Dictionary(
            uniqueKeysWithValues: orderedItems.compactMap { item -> (UUID, IndexBoardGridPosition)? in
                guard let position = resolvedGridPosition(for: item) else { return nil }
                return (item.cardID, position)
            }
        )
        let logicalGridBounds = resolvedLogicalGridBounds(
            for: Array(occupiedGridPositionByCardID.values)
        )
        return IndexBoardSurfaceAppKitSceneSnapshot(
            projection: projection,
            orderedItems: orderedItems,
            cardFrameByID: cardFrameByID,
            chipFrameByLaneKey: chipFrameByLaneKey,
            occupiedGridPositionByCardID: occupiedGridPositionByCardID,
            logicalGridBounds: logicalGridBounds
        )
    }

    func interactionCardFrame(for cardID: UUID) -> CGRect? {
        restingSceneSnapshot?.cardFrameByID[cardID] ?? cardFrameByID[cardID]
    }

    func interactionChipFrame(for laneParentID: UUID?) -> CGRect {
        let laneKey = indexBoardSurfaceLaneKey(laneParentID)
        return restingSceneSnapshot?.chipFrameByLaneKey[laneKey]
            ?? chipFrameByLaneKey[laneKey]
            ?? .null
    }

    func laneChipParentCardID(at point: CGPoint) -> UUID? {
        interactionProjection.parentGroups
            .compactMap { group -> (UUID, CGRect)? in
                guard let parentCardID = group.parentCardID else { return nil }
                let chipFrame = resolvedLaneChipHitFrame(for: parentCardID)
                guard !chipFrame.isNull else { return nil }
                return (parentCardID, chipFrame)
            }
            .filter { $0.1.contains(point) }
            .sorted { lhs, rhs in
                if lhs.1.minY != rhs.1.minY {
                    return lhs.1.minY < rhs.1.minY
                }
                if lhs.1.minX != rhs.1.minX {
                    return lhs.1.minX < rhs.1.minX
                }
                return lhs.0.uuidString < rhs.0.uuidString
            }
            .first?
            .0
    }

    func editableParentCardID(at point: CGPoint) -> UUID? {
        interactionProjection.parentGroups
            .compactMap { group -> (UUID, CGRect)? in
                guard let parentCardID = group.parentCardID else { return nil }
                let hitFrame = resolvedEditableParentHeaderHitFrame(for: group)
                guard !hitFrame.isNull else { return nil }
                return (parentCardID, hitFrame)
            }
            .filter { $0.1.contains(point) }
            .sorted { lhs, rhs in
                if lhs.1.minY != rhs.1.minY {
                    return lhs.1.minY < rhs.1.minY
                }
                if lhs.1.minX != rhs.1.minX {
                    return lhs.1.minX < rhs.1.minX
                }
                return lhs.0.uuidString < rhs.0.uuidString
            }
            .first?
            .0
    }

    func resolvedLaneChipHitFrame(for parentCardID: UUID?) -> CGRect {
        let chipFrame = interactionChipFrame(for: parentCardID)
        guard !chipFrame.isNull else { return .null }
        return chipFrame.insetBy(dx: -8, dy: -6)
    }

    func resolvedEditableParentHeaderHitFrame(
        for group: BoardSurfaceParentGroupPlacement
    ) -> CGRect {
        guard let groupFrame = resolvedDisplayedParentGroupFrame(for: group) else { return .null }

        let chipFrame = resolvedLaneChipHitFrame(for: group.parentCardID)
        let bandX = groupFrame.minX + max(2, IndexBoardSurfaceAppKitConstants.laneWrapperInset - 2)
        let bandY = groupFrame.minY + 1
        let bandWidth = min(
            max(IndexBoardMetrics.cardSize.width + 12, chipFrame.isNull ? 0 : chipFrame.width + 12),
            max(IndexBoardMetrics.cardSize.width, groupFrame.width - 10)
        )
        let bandHeight = IndexBoardSurfaceAppKitConstants.laneChipHeight + (IndexBoardSurfaceAppKitConstants.laneWrapperInset * 2) + 4
        let headerBandFrame = CGRect(
            x: bandX,
            y: bandY,
            width: bandWidth,
            height: min(groupFrame.height, bandHeight)
        )

        guard !chipFrame.isNull else { return headerBandFrame }
        return headerBandFrame.union(chipFrame.insetBy(dx: -6, dy: -4))
    }

    func resolvedCurrentCardFrames() -> [UUID: CGRect] {
        if let localCardDragPreviewFramesByID {
            var mergedFrames = restingSceneSnapshot?.cardFrameByID ?? cardFrameByID
            for (cardID, frame) in localCardDragPreviewFramesByID {
                mergedFrames[cardID] = frame
            }
            return mergedFrames
        }
        if let localGroupDragPreviewFramesByID {
            var mergedFrames = restingSceneSnapshot?.cardFrameByID ?? cardFrameByID
            for (cardID, frame) in localGroupDragPreviewFramesByID {
                mergedFrames[cardID] = frame
            }
            return mergedFrames
        }

        var nextCardFrames: [UUID: CGRect] = [:]
        nextCardFrames.reserveCapacity(orderedItems.count)
        for item in orderedItems {
            if let frame = resolvedCardFrame(for: item) {
                nextCardFrames[item.cardID] = frame
            }
        }
        return nextCardFrames
    }

    func occupiedGridPositionByCardID() -> [UUID: IndexBoardGridPosition] {
        if let restingSceneSnapshot {
            return restingSceneSnapshot.occupiedGridPositionByCardID
        }
        var positionByCardID: [UUID: IndexBoardGridPosition] = [:]
        for item in orderedItems {
            guard let position = resolvedGridPosition(for: item) else { continue }
            positionByCardID[item.cardID] = position
        }
        return positionByCardID
    }

    func resolvedGridPosition(for item: BoardSurfaceItem) -> IndexBoardGridPosition? {
        if let explicitGridPosition = item.gridPosition {
            return explicitGridPosition
        }
        if let detachedGridPosition = item.detachedGridPosition {
            return detachedGridPosition
        }
        guard let slotIndex = item.slotIndex else { return nil }
        return resolvedFlowGridPosition(for: slotIndex)
    }

    func cardID(at point: CGPoint) -> UUID? {
        orderedItems.reversed().first { item in
            guard let frame = cardFrameByID[item.cardID] else { return false }
            return frame.contains(point)
        }?.cardID
    }

    func resolvedTargetParentGroup(
        at point: CGPoint,
        excluding movingCardIDs: Set<UUID>
    ) -> BoardSurfaceParentGroupPlacement? {
        let candidateFrames = interactionProjection.parentGroups.compactMap { group -> (BoardSurfaceParentGroupPlacement, CGRect)? in
            let groupFrames = interactionOrderedItems.compactMap { item -> CGRect? in
                guard item.parentGroupID == group.id,
                      !movingCardIDs.contains(item.cardID),
                      let frame = interactionCardFrame(for: item.cardID) else { return nil }
                return frame
            }
            guard let firstFrame = groupFrames.first else { return nil }
            let cardUnion = groupFrames.dropFirst().reduce(firstFrame) { partial, frame in
                partial.union(frame)
            }
            let chipFrame = interactionChipFrame(for: group.parentCardID)
            let unionFrame = chipFrame.isNull ? cardUnion : cardUnion.union(chipFrame)
            return (group, unionFrame.insetBy(dx: -18, dy: -14))
        }

        return candidateFrames
            .filter { $0.1.contains(point) }
            .sorted { lhs, rhs in
                if lhs.1.minY != rhs.1.minY {
                    return lhs.1.minY < rhs.1.minY
                }
                if lhs.1.minX != rhs.1.minX {
                    return lhs.1.minX < rhs.1.minX
                }
                return lhs.0.id.id < rhs.0.id.id
            }
            .first?
            .0
    }

    func resolvedCardDropTargetFrame(
        for group: BoardSurfaceParentGroupPlacement,
        visibleCardCount: Int
    ) -> CGRect {
        let cardCount = max(1, visibleCardCount)
        let startSlot = resolvedGridSlotRect(for: group.origin)
        let endSlot = resolvedGridSlotRect(
            for: IndexBoardGridPosition(
                column: group.origin.column + max(0, cardCount - 1),
                row: group.origin.row
            )
        )
        return CGRect(
            x: startSlot.minX - IndexBoardSurfaceAppKitConstants.cardDropTerminalReach,
            y: startSlot.minY + IndexBoardSurfaceAppKitConstants.laneChipHeight + IndexBoardSurfaceAppKitConstants.laneChipSpacing,
            width: (endSlot.maxX - startSlot.minX) + (IndexBoardSurfaceAppKitConstants.cardDropTerminalReach * 2),
            height: IndexBoardMetrics.cardSize.height
        )
    }

    func resolvedDragCardCenter(
        for drag: IndexBoardSurfaceAppKitDragState
    ) -> CGPoint {
        drag.pointerInContent
    }

    enum IndexBoardResolvedCardDropTargetGroupMode {
        case slot(BoardSurfaceParentGroupPlacement)
        case block(BoardSurfaceParentGroupPlacement)
    }

    func resolvedCardDropTargetGroup(
        for drag: IndexBoardSurfaceAppKitDragState
    ) -> IndexBoardResolvedCardDropTargetGroupMode? {
        let logicalSnapshot = dragLogicalSnapshot
        let referenceProjection = logicalSnapshot.projection
        let visibleCardCountByGroupID = Dictionary(
            grouping: logicalSnapshot.orderedItems.filter { item in
                item.parentGroupID != nil && !drag.movingCardIDSet.contains(item.cardID)
            },
            by: { $0.parentGroupID! }
        ).mapValues(\.count)
        let dragCardCenter = resolvedDragCardCenter(for: drag)

        let candidateGroups = referenceProjection.parentGroups

        func resolvedMode(
            for group: BoardSurfaceParentGroupPlacement
        ) -> (mode: IndexBoardResolvedCardDropTargetGroupMode, slotPriority: Bool, primaryDistance: CGFloat, secondaryDistance: CGFloat)? {
            guard let blockFrame = resolvedGroupBlockActivationFrame(
                for: group,
                visibleCardCount: visibleCardCountByGroupID[group.id] ?? group.cardIDs.count,
                horizontalInset: IndexBoardSurfaceAppKitConstants.groupSlotActivationHorizontalInset,
                verticalInset: IndexBoardSurfaceAppKitConstants.groupSlotActivationVerticalInset
            ) else {
                return nil
            }
            let slotFrame = resolvedGroupSlotEntryFrame(
                for: group,
                visibleCardCount: visibleCardCountByGroupID[group.id] ?? group.cardIDs.count,
                horizontalInset: 0,
                verticalInset: 0
            )
            switch resolvedIndexBoardGroupHoverTargetMode(
                point: dragCardCenter,
                slotEntryFrame: slotFrame,
                activationFrame: blockFrame
            ) {
            case .groupSlot:
                let slotDistance = slotFrame.map { hypot($0.midX - dragCardCenter.x, $0.midY - dragCardCenter.y) } ?? .greatestFiniteMagnitude
                let topDistance = slotFrame.map { abs(dragCardCenter.y - $0.minY) } ?? .greatestFiniteMagnitude
                return (.slot(group), true, topDistance, slotDistance)
            case .groupBlock:
                let blockDistance = hypot(blockFrame.midX - dragCardCenter.x, blockFrame.midY - dragCardCenter.y)
                let topDistance = abs(dragCardCenter.y - blockFrame.minY)
                return (.block(group), false, topDistance, blockDistance)
            case .detached:
                return nil
            }
        }

        if let retainedParentID = drag.dropTarget.laneParentID ?? drag.sourceLaneParentID,
           let retainedGroup = candidateGroups.first(where: { $0.parentCardID == retainedParentID }),
           let retainedMode = resolvedMode(for: retainedGroup) {
            return retainedMode.mode
        }

        return candidateGroups
            .compactMap { group -> (IndexBoardResolvedCardDropTargetGroupMode, Bool, CGFloat, CGFloat, String)? in
                guard let resolved = resolvedMode(for: group) else { return nil }
                return (resolved.mode, resolved.slotPriority, resolved.primaryDistance, resolved.secondaryDistance, group.id.id)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 && !rhs.1
                }
                if lhs.2 != rhs.2 {
                    return lhs.2 < rhs.2
                }
                if lhs.3 != rhs.3 {
                    return lhs.3 < rhs.3
                }
                return lhs.4 < rhs.4
            }
            .first?
            .0
    }

    func resolvedGroupBlockActivationFrame(
        for group: BoardSurfaceParentGroupPlacement,
        visibleCardCount: Int,
        horizontalInset: CGFloat,
        verticalInset: CGFloat
    ) -> CGRect? {
        let visibleCount = max(1, visibleCardCount)
        let firstCardFrame = resolvedCardFrame(
            for: IndexBoardGridPosition(
                column: group.origin.column,
                row: group.origin.row
            )
        )
        let lastCardFrame = resolvedCardFrame(
            for: IndexBoardGridPosition(
                column: group.origin.column + max(0, visibleCount - 1),
                row: group.origin.row
            )
        )
        let cardUnion = firstCardFrame.union(lastCardFrame)
        let chipFrame = interactionChipFrame(for: group.parentCardID)
        let baseFrame = chipFrame.isNull ? cardUnion : cardUnion.union(chipFrame)
        return baseFrame.insetBy(
            dx: -(IndexBoardSurfaceAppKitConstants.laneWrapperInset + horizontalInset),
            dy: -(IndexBoardSurfaceAppKitConstants.laneWrapperInset + verticalInset)
        )
    }

    func resolvedGroupSlotEntryFrame(
        for group: BoardSurfaceParentGroupPlacement,
        visibleCardCount: Int,
        horizontalInset: CGFloat,
        verticalInset: CGFloat
    ) -> CGRect? {
        let visibleCount = max(1, visibleCardCount)
        let firstCardFrame = resolvedCardFrame(
            for: IndexBoardGridPosition(
                column: group.origin.column,
                row: group.origin.row
            )
        )
        let lastCardFrame = resolvedCardFrame(
            for: IndexBoardGridPosition(
                column: group.origin.column + max(0, visibleCount - 1),
                row: group.origin.row
            )
        )
        let cardUnion = firstCardFrame.union(lastCardFrame)
        return cardUnion.insetBy(dx: -horizontalInset, dy: -verticalInset)
    }

    func movableParentGroupID(at point: CGPoint) -> UUID? {
        let candidateGroups = interactionProjection.parentGroups

        return candidateGroups
            .compactMap { group -> (UUID, CGRect)? in
                guard let parentCardID = group.parentCardID else { return nil }
                guard let handleFrame = resolvedParentGroupHandleFrame(for: group) else { return nil }
                return (
                    parentCardID,
                    handleFrame
                )
            }
            .filter { $0.1.contains(point) }
            .sorted { lhs, rhs in
                if lhs.1.minY != rhs.1.minY {
                    return lhs.1.minY < rhs.1.minY
                }
                if lhs.1.minX != rhs.1.minX {
                    return lhs.1.minX < rhs.1.minX
                }
                return lhs.0.uuidString < rhs.0.uuidString
            }
            .first?
            .0
    }

    func resolvedParentGroupHandleFrame(
        for group: BoardSurfaceParentGroupPlacement
    ) -> CGRect? {
        guard let groupFrame = resolvedParentGroupFrame(for: group) else { return nil }
        let chipFrame = interactionChipFrame(for: group.parentCardID)
        if chipFrame.isNull {
            return CGRect(
                x: groupFrame.minX - 8,
                y: groupFrame.minY,
                width: groupFrame.width + 16,
                height: min(groupFrame.height, 34)
            )
        }
        return CGRect(
            x: groupFrame.minX - 8,
            y: chipFrame.minY - 6,
            width: groupFrame.width + 16,
            height: chipFrame.height + 12
        )
    }

    func resolvedFlowGridPosition(for slotIndex: Int) -> IndexBoardGridPosition {
        let safeColumns = max(1, preferredColumns)
        return IndexBoardGridPosition(
            column: max(0, slotIndex) % safeColumns,
            row: max(0, slotIndex) / safeColumns
        )
    }

    func resolvedGridSlotRect(for position: IndexBoardGridPosition) -> CGRect {
        let bounds = logicalGridBounds
        let normalizedColumn = position.column - bounds.minColumn
        let normalizedRow = position.row - bounds.minRow
        return CGRect(
            x: surfaceHorizontalInset + (CGFloat(normalizedColumn) * (slotSize.width + IndexBoardMetrics.cardSpacing)),
            y: surfaceTopInset + (CGFloat(normalizedRow) * (slotSize.height + IndexBoardSurfaceAppKitConstants.lineSpacing)),
            width: slotSize.width,
            height: slotSize.height
        )
    }

    func resolvedFlowSlotRect(for slotIndex: Int) -> CGRect {
        resolvedGridSlotRect(for: resolvedFlowGridPosition(for: slotIndex))
    }

    func resolvedCardFrame(for position: IndexBoardGridPosition) -> CGRect {
        let slotFrame = resolvedGridSlotRect(for: position)
        return CGRect(
            x: slotFrame.minX,
            y: slotFrame.minY + IndexBoardSurfaceAppKitConstants.laneChipHeight + IndexBoardSurfaceAppKitConstants.laneChipSpacing,
            width: IndexBoardMetrics.cardSize.width,
            height: IndexBoardMetrics.cardSize.height
        )
    }

    func resolvedCardFrame(for item: BoardSurfaceItem) -> CGRect? {
        guard let gridPosition = resolvedGridPosition(for: item) else { return nil }
        return resolvedCardFrame(for: gridPosition)
    }

    func resolvedFlowInteractionRect(
        slotCount: Int,
        usesVerticalHysteresis: Bool = false
    ) -> CGRect? {
        let safeSlotCount = max(1, slotCount + 1)
        let cardFrames = (0..<safeSlotCount).map { index in
            let slotFrame = resolvedFlowSlotRect(for: index)
            return CGRect(
                x: slotFrame.minX,
                y: slotFrame.minY + IndexBoardSurfaceAppKitConstants.laneChipHeight + IndexBoardSurfaceAppKitConstants.laneChipSpacing,
                width: IndexBoardMetrics.cardSize.width,
                height: IndexBoardMetrics.cardSize.height
            )
        }
        guard let firstFrame = cardFrames.first else { return nil }
        let union = cardFrames.dropFirst().reduce(firstFrame) { partial, frame in
            partial.union(frame)
        }
        return union.insetBy(
            dx: -IndexBoardSurfaceAppKitConstants.flowInteractionHorizontalInset,
            dy: -(usesVerticalHysteresis
                ? IndexBoardSurfaceAppKitConstants.flowInteractionVerticalHysteresis
                : IndexBoardSurfaceAppKitConstants.flowInteractionVerticalInset)
        )
    }

    func resolvedFlowDropSlotIndex(for point: CGPoint, slotCount: Int) -> Int {
        let safeSlotCount = max(1, slotCount + 1)
        var bestIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for slotIndex in 0..<safeSlotCount {
            let slotFrame = resolvedFlowSlotRect(for: slotIndex)
            let frame = CGRect(
                x: slotFrame.minX,
                y: slotFrame.minY + IndexBoardSurfaceAppKitConstants.laneChipHeight + IndexBoardSurfaceAppKitConstants.laneChipSpacing,
                width: IndexBoardMetrics.cardSize.width,
                height: IndexBoardMetrics.cardSize.height
            )
            let dx = point.x - frame.midX
            let dy = point.y - frame.midY
            let distance = (dx * dx) + (dy * dy)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = slotIndex
            }
        }

        return min(max(0, bestIndex), slotCount)
    }

    func resolvedFlowInsertionSlotCenterX(
        for group: BoardSurfaceParentGroupPlacement,
        insertionIndex: Int
    ) -> CGFloat {
        resolvedCardFrame(
            for: IndexBoardGridPosition(
                column: group.origin.column + max(0, insertionIndex),
                row: group.origin.row
            )
        ).midX
    }

    func resolvedRetainedFlowInsertionIndex(
        for group: BoardSurfaceParentGroupPlacement,
        visibleItemCount: Int,
        point: CGPoint,
        drag: IndexBoardSurfaceAppKitDragState
    ) -> Int? {
        guard drag.dropTarget.detachedGridPosition == nil,
              !drag.dropTarget.isTempStripTarget,
              drag.dropTarget.laneParentID == group.parentCardID else {
            return nil
        }

        let retainedIndex = min(max(0, drag.dropTarget.insertionIndex), visibleItemCount)
        let currentCenterX = resolvedFlowInsertionSlotCenterX(for: group, insertionIndex: retainedIndex)
        let lowerBoundaryX: CGFloat = {
            guard retainedIndex > 0 else { return -.greatestFiniteMagnitude }
            let previousCenterX = resolvedFlowInsertionSlotCenterX(
                for: group,
                insertionIndex: retainedIndex - 1
            )
            return ((previousCenterX + currentCenterX) / 2) - IndexBoardSurfaceAppKitConstants.flowInsertionHysteresis
        }()
        let upperBoundaryX: CGFloat = {
            guard retainedIndex < visibleItemCount else { return .greatestFiniteMagnitude }
            let nextCenterX = resolvedFlowInsertionSlotCenterX(
                for: group,
                insertionIndex: retainedIndex + 1
            )
            return ((currentCenterX + nextCenterX) / 2) + IndexBoardSurfaceAppKitConstants.flowInsertionHysteresis
        }()

        return (point.x >= lowerBoundaryX && point.x <= upperBoundaryX) ? retainedIndex : nil
    }

    func resolvedFlowInsertionIndex(
        for group: BoardSurfaceParentGroupPlacement,
        visibleItemCount: Int,
        point: CGPoint,
        drag: IndexBoardSurfaceAppKitDragState
    ) -> Int {
        if let retainedIndex = resolvedRetainedFlowInsertionIndex(
            for: group,
            visibleItemCount: visibleItemCount,
            point: point,
            drag: drag
        ) {
            return retainedIndex
        }

        let safeSlotCount = max(1, visibleItemCount + 1)
        var bestIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for insertionIndex in 0..<safeSlotCount {
            let slotFrame = resolvedCardFrame(
                for: IndexBoardGridPosition(
                    column: group.origin.column + insertionIndex,
                    row: group.origin.row
                )
            )
            let dx = point.x - slotFrame.midX
            let dy = point.y - slotFrame.midY
            let distance = (dx * dx) + (dy * dy)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = insertionIndex
            }
        }

        return min(max(0, bestIndex), visibleItemCount)
    }

    func resolvedNearestGridPosition(for point: CGPoint) -> IndexBoardGridPosition {
        let bounds = logicalGridBounds
        let columnStep = slotSize.width + IndexBoardMetrics.cardSpacing
        let rowStep = slotSize.height + IndexBoardSurfaceAppKitConstants.lineSpacing
        let rawColumn = Int(((point.x - surfaceHorizontalInset - (slotSize.width / 2)) / columnStep).rounded())
        let rawRow = Int(((point.y - surfaceTopInset - (slotSize.height / 2)) / rowStep).rounded())
        let clampedColumn = min(max(0, rawColumn), bounds.columnCount - 1)
        let clampedRow = min(max(0, rawRow), bounds.rowCount - 1)
        return IndexBoardGridPosition(
            column: bounds.minColumn + clampedColumn,
            row: bounds.minRow + clampedRow
        )
    }

    func resolvedDetachedGridPosition(
        for point: CGPoint,
        excluding excludedCardIDs: Set<UUID>,
        logicalSnapshot: IndexBoardSurfaceAppKitLogicalSnapshot? = nil
    ) -> IndexBoardGridPosition {
        let candidate = resolvedNearestGridPosition(for: point)
        let orderedItems = logicalSnapshot?.orderedItems ?? self.orderedItems
        let occupiedPositions = Set(
            orderedItems.compactMap { item -> IndexBoardGridPosition? in
                guard !excludedCardIDs.contains(item.cardID),
                      let position = item.detachedGridPosition ?? item.gridPosition else {
                    return nil
                }
                return position
            }
        )
        guard occupiedPositions.contains(candidate) else { return candidate }

        let bounds = logicalGridBounds
        let maxRadius = max(bounds.columnCount, bounds.rowCount)
        for radius in 1...maxRadius {
            var candidates: [IndexBoardGridPosition] = []
            for row in (candidate.row - radius)...(candidate.row + radius) {
                for column in (candidate.column - radius)...(candidate.column + radius) {
                    let rowDelta = abs(row - candidate.row)
                    let columnDelta = abs(column - candidate.column)
                    guard max(rowDelta, columnDelta) == radius else { continue }
                    guard row >= bounds.minRow,
                          row <= bounds.maxRow,
                          column >= bounds.minColumn,
                          column <= bounds.maxColumn else {
                        continue
                    }
                    candidates.append(IndexBoardGridPosition(column: column, row: row))
                }
            }

            let nearest = candidates.sorted { lhs, rhs in
                let lhsDistance = abs(lhs.row - candidate.row) + abs(lhs.column - candidate.column)
                let rhsDistance = abs(rhs.row - candidate.row) + abs(rhs.column - candidate.column)
                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }
                if lhs.row != rhs.row {
                    return lhs.row < rhs.row
                }
                return lhs.column < rhs.column
            }

            if let resolved = nearest.first(where: { !occupiedPositions.contains($0) }) {
                return resolved
            }
        }

        return candidate
    }

    func stationaryParentGroups(
        excluding excludedCardIDs: Set<UUID>
    ) -> [BoardSurfaceParentGroupPlacement] {
        indexBoardSurfaceStationaryParentGroups(
            from: dragReferenceProjection.parentGroups,
            excluding: excludedCardIDs
        )
    }

    func stationaryDetachedPositions(
        excluding excludedCardIDs: Set<UUID>
    ) -> [UUID: IndexBoardGridPosition] {
        Dictionary(uniqueKeysWithValues: orderedItems.compactMap { item -> (UUID, IndexBoardGridPosition)? in
            guard item.parentGroupID == nil,
                  !excludedCardIDs.contains(item.cardID),
                  let position = item.detachedGridPosition ?? item.gridPosition else {
                return nil
            }
            return (item.cardID, position)
        })
    }

    func referenceDetachedPositions() -> [UUID: IndexBoardGridPosition] {
        Dictionary(uniqueKeysWithValues: dragReferenceProjection.surfaceItems.compactMap { item -> (UUID, IndexBoardGridPosition)? in
            guard item.parentGroupID == nil,
                  let position = item.detachedGridPosition ?? item.gridPosition else {
                return nil
            }
            return (item.cardID, position)
        })
    }

    func referenceTempStrips() -> [IndexBoardTempStripState] {
        dragReferenceProjection.tempStrips
    }

    func tempLaneParentID() -> UUID? {
        configuration.surfaceProjection.lanes.first(where: \.isTempLane)?.parentCardID
    }

    func resolvedTempGroupWidthsByParentID(
        from projection: BoardSurfaceProjection
    ) -> [UUID: Int] {
        Dictionary(
            uniqueKeysWithValues: projection.parentGroups.compactMap { placement in
                guard placement.isTempGroup,
                      let parentCardID = placement.parentCardID else {
                    return nil
                }
                return (parentCardID, placement.width)
            }
        )
    }

    func resolvedTempStripMemberWidth(
        _ member: IndexBoardTempStripMember,
        widthsByParentID: [UUID: Int]
    ) -> Int {
        switch member.kind {
        case .card:
            return 1
        case .group:
            return max(1, widthsByParentID[member.id] ?? 1)
        }
    }

    func resolvedTempStripSlotDescriptors(
        for strip: IndexBoardTempStripState,
        widthsByParentID: [UUID: Int]
    ) -> [(column: Int, previous: IndexBoardTempStripMember?, next: IndexBoardTempStripMember?)] {
        var descriptors: [(column: Int, previous: IndexBoardTempStripMember?, next: IndexBoardTempStripMember?)] = []
        var cursor = strip.anchorColumn
        descriptors.append((cursor, nil, strip.members.first))

        for (index, member) in strip.members.enumerated() {
            cursor += resolvedTempStripMemberWidth(member, widthsByParentID: widthsByParentID)
            let nextMember = index + 1 < strip.members.count ? strip.members[index + 1] : nil
            descriptors.append((cursor, member, nextMember))
        }

        return descriptors
    }

    func resolvedTempStripBandFrame(
        for strip: IndexBoardTempStripState,
        widthsByParentID: [UUID: Int],
        movingSlotCount: Int
    ) -> CGRect? {
        let stripWidth = strip.members.reduce(0) { partialResult, member in
            partialResult + resolvedTempStripMemberWidth(member, widthsByParentID: widthsByParentID)
        }
        return resolvedDetachedBlockFrame(
            row: strip.row,
            anchorColumn: strip.anchorColumn,
            slotCount: max(1, stripWidth + movingSlotCount)
        )
    }

    func resolvedDetachedBlockFrame(
        row: Int,
        anchorColumn: Int,
        slotCount: Int
    ) -> CGRect? {
        guard slotCount > 0 else { return nil }
        let elementFrames = (0..<slotCount).map { offset in
            resolvedCardFrame(
                for: IndexBoardGridPosition(
                    column: anchorColumn + offset,
                    row: row
                )
            )
        }
        guard let firstFrame = elementFrames.first else { return nil }
        return elementFrames.dropFirst().reduce(firstFrame) { partial, frame in
            partial.union(frame)
        }.insetBy(
            dx: -IndexBoardSurfaceAppKitConstants.detachedBlockTargetHorizontalInset,
            dy: -IndexBoardSurfaceAppKitConstants.detachedBlockTargetVerticalInset
        )
    }

    func resolvedDetachedSlotFrames(
        row: Int,
        anchorColumn: Int,
        slotCount: Int
    ) -> [CGRect] {
        guard slotCount > 0 else { return [] }
        return (0..<slotCount).map { offset in
            resolvedCardFrame(
                for: IndexBoardGridPosition(
                    column: anchorColumn + offset,
                    row: row
                )
            )
        }
    }

    func resolvedDetachedBlockDropTarget(
        for drag: IndexBoardSurfaceAppKitDragState
    ) -> IndexBoardCardDropTarget? {
        let logicalSnapshot = dragLogicalSnapshot
        let compactedStrips = resolvedIndexBoardTempStripsAfterRemovingMembers(
            strips: logicalSnapshot.tempStrips,
            movingMembers: drag.movingTempMembers
        )
        let widthsByParentID = logicalSnapshot.tempGroupWidthsByParentID
        let dragCardCenter = resolvedDragCardCenter(for: drag)

        struct Candidate {
            let target: IndexBoardCardDropTarget
            let retained: Bool
            let verticalDistance: CGFloat
            let distance: CGFloat
        }

        var bestCandidate: Candidate?
        let retainedStripID: String? = {
            let retainedPreviousMember = drag.dropTarget.previousTempMember ?? drag.sourceTarget.previousTempMember
            let retainedNextMember = drag.dropTarget.nextTempMember ?? drag.sourceTarget.nextTempMember
            return compactedStrips.first { strip in
                if let retainedPreviousMember, strip.members.contains(retainedPreviousMember) {
                    return true
                }
                if let retainedNextMember, strip.members.contains(retainedNextMember) {
                    return true
                }
                return false
            }?.id
        }()

        for strip in compactedStrips {
            guard let bandFrame = resolvedTempStripBandFrame(
                for: strip,
                widthsByParentID: widthsByParentID,
                movingSlotCount: max(1, drag.movingTempMembers.count)
            ) else {
                continue
            }
            let isRetainedStrip = strip.id == retainedStripID
            let interactionFrame = bandFrame.insetBy(
                dx: -(isRetainedStrip
                    ? IndexBoardSurfaceAppKitConstants.detachedStripRetentionHorizontalInset
                    : IndexBoardSurfaceAppKitConstants.detachedStripInteractionHorizontalInset),
                dy: -(isRetainedStrip
                    ? IndexBoardSurfaceAppKitConstants.detachedStripRetentionVerticalInset
                    : IndexBoardSurfaceAppKitConstants.detachedStripInteractionVerticalInset)
            )
            guard interactionFrame.contains(dragCardCenter) else {
                continue
            }

            let slotDescriptors = resolvedTempStripSlotDescriptors(
                for: strip,
                widthsByParentID: widthsByParentID
            )
            guard let bestSlot = slotDescriptors.min(by: { lhs, rhs in
                let lhsDistance = abs(resolvedCardFrame(
                    for: IndexBoardGridPosition(column: lhs.column, row: strip.row)
                ).midX - dragCardCenter.x)
                let rhsDistance = abs(resolvedCardFrame(
                    for: IndexBoardGridPosition(column: rhs.column, row: strip.row)
                ).midX - dragCardCenter.x)
                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }
                return lhs.column < rhs.column
            }) else {
                continue
            }

            let previousCardID = bestSlot.previous?.kind == .card ? bestSlot.previous?.id : nil
            let nextCardID = bestSlot.next?.kind == .card ? bestSlot.next?.id : nil
            let slotFrame = resolvedCardFrame(
                for: IndexBoardGridPosition(column: bestSlot.column, row: strip.row)
            )
            let verticalDistance = abs(slotFrame.midY - dragCardCenter.y)
            let allowedVerticalDistance = slotFrame.height * (isRetainedStrip
                ? IndexBoardSurfaceAppKitConstants.detachedStripRetentionVerticalMultiplier
                : IndexBoardSurfaceAppKitConstants.detachedStripActivationVerticalMultiplier)
            guard verticalDistance <= allowedVerticalDistance else {
                continue
            }
            let distance = abs(slotFrame.midX - dragCardCenter.x) + (verticalDistance * 0.7)
            let target = IndexBoardCardDropTarget(
                groupID: legacyGroupID(for: tempLaneParentID() ?? drag.sourceLaneParentID),
                insertionIndex: 0,
                laneParentID: tempLaneParentID() ?? drag.sourceLaneParentID,
                previousCardID: previousCardID,
                nextCardID: nextCardID,
                previousTempMember: bestSlot.previous,
                nextTempMember: bestSlot.next,
                preferredColumnCount: nil
            )

            if let currentBest = bestCandidate {
                if isRetainedStrip != currentBest.retained {
                    if isRetainedStrip {
                        bestCandidate = Candidate(
                            target: target,
                            retained: isRetainedStrip,
                            verticalDistance: verticalDistance,
                            distance: distance
                        )
                    }
                } else if verticalDistance != currentBest.verticalDistance {
                    if verticalDistance < currentBest.verticalDistance {
                        bestCandidate = Candidate(
                            target: target,
                            retained: isRetainedStrip,
                            verticalDistance: verticalDistance,
                            distance: distance
                        )
                    }
                } else if distance < currentBest.distance {
                    bestCandidate = Candidate(
                        target: target,
                        retained: isRetainedStrip,
                        verticalDistance: verticalDistance,
                        distance: distance
                    )
                }
            } else {
                bestCandidate = Candidate(
                    target: target,
                    retained: isRetainedStrip,
                    verticalDistance: verticalDistance,
                    distance: distance
                )
            }
        }

        return bestCandidate?.target
    }

    func resolvedMovingItems(for draggedCardID: UUID) -> [BoardSurfaceItem] {
        guard configuration.selectedCardIDs.count > 1,
              configuration.selectedCardIDs.contains(draggedCardID) else {
            return orderedItems.filter { $0.cardID == draggedCardID }
        }
        let selectedItems = orderedItems.filter { configuration.selectedCardIDs.contains($0.cardID) }
        return selectedItems.isEmpty ? orderedItems.filter { $0.cardID == draggedCardID } : selectedItems
    }

    func sourceTarget(for movingItems: [BoardSurfaceItem], primaryItem: BoardSurfaceItem) -> IndexBoardCardDropTarget {
        guard movingItems.count > 1 else {
            return sourceTarget(for: primaryItem)
        }

        let movingCardIDs = Set(movingItems.map(\.cardID))
        let groupedMovingItems = movingItems
            .filter { $0.parentGroupID == primaryItem.parentGroupID }
            .sorted(by: indexBoardSurfaceAppKitSort)

        if let firstGroupedItem = groupedMovingItems.first,
           let parentGroup = parentGroup(for: firstGroupedItem) {
            let visibleItems = orderedItems.filter { item in
                item.parentGroupID == parentGroup.id && !movingCardIDs.contains(item.cardID)
            }
            let insertionIndex = visibleItems.filter { item in
                guard let itemPosition = item.gridPosition,
                      let firstPosition = firstGroupedItem.gridPosition else { return false }
                return itemPosition.column < firstPosition.column
            }.count
            let previousCardID = visibleItems.prefix(insertionIndex).last?.cardID
            let nextCardID = insertionIndex < visibleItems.count ? visibleItems[insertionIndex].cardID : nil
            return IndexBoardCardDropTarget(
                groupID: legacyGroupID(for: parentGroup.parentCardID),
                insertionIndex: insertionIndex,
                laneParentID: parentGroup.parentCardID,
                previousCardID: previousCardID,
                nextCardID: nextCardID,
                preferredColumnCount: nil
            )
        }

        return sourceTarget(for: primaryItem)
    }

    func sourceTarget(for item: BoardSurfaceItem) -> IndexBoardCardDropTarget {
        if item.parentGroupID == nil,
           let detachedGridPosition = item.detachedGridPosition ?? item.gridPosition {
            if let sourceStrip = configuration.surfaceProjection.tempStrips.first(where: { strip in
                strip.members.contains(IndexBoardTempStripMember(kind: .card, id: item.cardID))
            }),
               let memberIndex = sourceStrip.members.firstIndex(of: IndexBoardTempStripMember(kind: .card, id: item.cardID)) {
                let previousMember = memberIndex > 0 ? sourceStrip.members[memberIndex - 1] : nil
                let nextMember = memberIndex + 1 < sourceStrip.members.count ? sourceStrip.members[memberIndex + 1] : nil
                return IndexBoardCardDropTarget(
                    groupID: legacyGroupID(for: tempLaneParentID() ?? item.laneParentID),
                    insertionIndex: 0,
                    laneParentID: tempLaneParentID() ?? item.laneParentID,
                    previousCardID: previousMember?.kind == .card ? previousMember?.id : nil,
                    nextCardID: nextMember?.kind == .card ? nextMember?.id : nil,
                    previousTempMember: previousMember,
                    nextTempMember: nextMember,
                    preferredColumnCount: nil
                )
            }

            return IndexBoardCardDropTarget(
                groupID: legacyGroupID(for: tempLaneParentID() ?? item.laneParentID),
                insertionIndex: 0,
                laneParentID: tempLaneParentID() ?? item.laneParentID,
                detachedGridPosition: detachedGridPosition,
                preferredColumnCount: nil
            )
        }

        let group = parentGroup(for: item)
        let groupItems = orderedItems.filter { $0.parentGroupID == item.parentGroupID }.sorted(by: indexBoardSurfaceAppKitSort)
        let insertionIndex = groupItems.firstIndex(where: { $0.cardID == item.cardID }) ?? 0
        let previousCardID = insertionIndex > 0 ? groupItems[insertionIndex - 1].cardID : nil
        let nextCardID = insertionIndex + 1 < groupItems.count ? groupItems[insertionIndex + 1].cardID : nil
        return IndexBoardCardDropTarget(
            groupID: legacyGroupID(for: group?.parentCardID ?? item.laneParentID),
            insertionIndex: insertionIndex,
            laneParentID: group?.parentCardID ?? item.laneParentID,
            previousCardID: previousCardID,
            nextCardID: nextCardID,
            preferredColumnCount: nil
        )
    }

    func resolvedLocalCardDragPreviewFrames(
        for drag: IndexBoardSurfaceAppKitDragState
    ) -> [UUID: CGRect] {
        withIndexBoardSurfaceAppKitSignpost(IndexBoardSurfaceAppKitSignpostName.resolvedLocalCardPreview) {
            let pendingMove = pendingCardMove(for: drag)
            let snapshot = restingSceneSnapshot ?? makeRestingSceneSnapshot()
            let baseProjection = pendingMove.logicalSnapshot.projection
            let canonicalCardIDsByGroupID = canonicalCardIDsByGroupID(from: baseProjection)
            let movingCardIDs = pendingMove.movingCardIDSet
            var frames: [UUID: CGRect] = [:]
            let targetIsTemp = pendingMove.target.isTempStripTarget || pendingMove.target.detachedGridPosition != nil
            let targetGroupID: BoardSurfaceParentGroupID? = targetIsTemp
                ? nil
                : (pendingMove.target.laneParentID.map(BoardSurfaceParentGroupID.parent) ?? .root)
            let tempLayout = resolvedIndexBoardTempStripSurfaceLayout(
                strips: resolvedPreviewTempStrips(for: pendingMove),
                tempGroupWidthsByParentID: pendingMove.logicalSnapshot.tempGroupWidthsByParentID
            )
            let sourceGroupIDs = Set(
                pendingMove.logicalSnapshot.orderedItems.compactMap { item -> BoardSurfaceParentGroupID? in
                    movingCardIDs.contains(item.cardID) ? item.parentGroupID : nil
                }
            )
            let affectedGroupIDs = Set(
                baseProjection.parentGroups.compactMap { placement -> BoardSurfaceParentGroupID? in
                    if sourceGroupIDs.contains(placement.id) || placement.id == targetGroupID || placement.isTempGroup {
                        return placement.id
                    }
                    return nil
                }
            )

            for placement in baseProjection.parentGroups {
                guard affectedGroupIDs.contains(placement.id) else { continue }
                let origin: IndexBoardGridPosition
                if placement.isTempGroup,
                   let parentCardID = placement.parentCardID,
                   let tempOrigin = tempLayout.groupOriginByParentID[parentCardID] {
                    origin = tempOrigin
                } else {
                    origin = placement.origin
                }

                let groupCardIDs = canonicalCardIDsByGroupID[placement.id] ?? placement.cardIDs
                let stationaryCardIDs = groupCardIDs.filter { !movingCardIDs.contains($0) }
                let insertionIndex = placement.id == targetGroupID
                    ? min(max(0, pendingMove.target.insertionIndex), stationaryCardIDs.count)
                    : nil

                for (stationaryIndex, cardID) in stationaryCardIDs.enumerated() {
                    let previewIndex: Int
                    if let insertionIndex, stationaryIndex >= insertionIndex {
                        previewIndex = stationaryIndex + pendingMove.movingCardIDs.count
                    } else {
                        previewIndex = stationaryIndex
                    }

                    let frame = resolvedCardFrame(
                        for: IndexBoardGridPosition(
                            column: origin.column + previewIndex,
                            row: origin.row
                        )
                    )
                    if snapshot.cardFrameByID[cardID] != frame {
                        frames[cardID] = frame
                    }
                }
            }

            for (cardID, position) in tempLayout.detachedPositionsByCardID where !movingCardIDs.contains(cardID) {
                let frame = resolvedCardFrame(for: position)
                if snapshot.cardFrameByID[cardID] != frame {
                    frames[cardID] = frame
                }
            }

            return frames
        }
    }

    func beginDrag(cardID: UUID, pointer: CGPoint) {
        let dragStartedAt = CFAbsoluteTimeGetCurrent()
        guard let primaryItem = orderedItems.first(where: { $0.cardID == cardID }),
              let initialFrame = resolvedCardFrame(for: primaryItem) else { return }
        let movingItems = resolvedMovingItems(for: cardID)
        beginBaselineSession(kind: "card", movingCardCount: movingItems.count)
        restingSceneSnapshot = makeRestingSceneSnapshot()
        if let snapshot = restingSceneSnapshot {
            let groupOrderSummary = snapshot.projection.parentGroups
                .map { "\($0.id.id)=\($0.cardIDs.map(\.uuidString).joined(separator: ","))" }
                .joined(separator: " | ")
            indexBoardOrderDiagnosticsLog("begin_drag snapshot parentGroups \(groupOrderSummary)")
        }
        let movingCardIDs = movingItems.map(\.cardID)
        let sourceDetachedGridPositionsByCardID = Dictionary(
            uniqueKeysWithValues: movingItems.compactMap { item -> (UUID, IndexBoardGridPosition)? in
                guard item.parentGroupID == nil,
                      let position = item.detachedGridPosition ?? item.gridPosition else {
                    return nil
                }
                return (item.cardID, position)
            }
        )
        configuration.onCardDragStart(movingCardIDs, cardID)
        let sourceTarget = sourceTarget(for: movingItems, primaryItem: primaryItem)
        let sourcePlacement: IndexBoardSurfaceAppKitDropPlacement
        if let detachedGridPosition = primaryItem.detachedGridPosition,
           primaryItem.parentGroupID == nil {
            sourcePlacement = .detached(detachedGridPosition)
        } else {
            sourcePlacement = .flow(0)
        }

        dragSnapshots = movingCardIDs.compactMap { movingCardID in
            guard let snapshot = cardViews[movingCardID]?.snapshotImage() else { return nil }
            return IndexBoardSurfaceAppKitCardSnapshot(cardID: movingCardID, image: snapshot)
        }

        let movingTempMembers = movingCardIDs.map { IndexBoardTempStripMember(kind: .card, id: $0) }
        let provisionalDragState = IndexBoardSurfaceAppKitDragState(
            cardID: cardID,
            movingCardIDs: movingCardIDs,
            movingTempMembers: movingTempMembers,
            sourceDetachedGridPositionsByCardID: sourceDetachedGridPositionsByCardID,
            sourcePlacement: sourcePlacement,
            sourceLaneParentID: primaryItem.laneParentID,
            sourceTarget: sourceTarget,
            initialFrame: initialFrame,
            pointerOffset: CGSize(
                width: pointer.x - initialFrame.minX,
                height: pointer.y - initialFrame.minY
            ),
            pointerInContent: pointer,
            dropPlacement: sourcePlacement,
            dropTarget: sourceTarget
        )
        let initialTarget = resolvedDropTarget(for: provisionalDragState)
        dragState = IndexBoardSurfaceAppKitDragState(
            cardID: cardID,
            movingCardIDs: movingCardIDs,
            movingTempMembers: movingTempMembers,
            sourceDetachedGridPositionsByCardID: sourceDetachedGridPositionsByCardID,
            sourcePlacement: sourcePlacement,
            sourceLaneParentID: primaryItem.laneParentID,
            sourceTarget: initialTarget,
            initialFrame: initialFrame,
            pointerOffset: CGSize(
                width: pointer.x - initialFrame.minX,
                height: pointer.y - initialFrame.minY
            ),
            pointerInContent: pointer,
            dropPlacement: sourcePlacement,
            dropTarget: initialTarget
        )
        if let dragState {
            presentationSurfaceProjection = resolvedPresentationSurfaceProjection(for: dragState)
            updateLocalCardDragPreview(for: dragState)
        }
        beginMotionScene(
            snapshotCardIDs: [],
            hiddenLiveCardIDs: dragState?.movingCardIDSet ?? [],
            includingChips: false,
            includingWrappers: false
        )
        startAutoScrollTimer()
        updateOverlayLayers()
        indexBoardDropPerformanceLog(
            "drag_begin",
            "kind=card card=\(cardID.uuidString) moving_cards=\(movingCardIDs.count) ms=\(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - dragStartedAt) * 1000))"
        )
    }

    func endDrag(cardID: UUID) {
        guard let dragState, dragState.cardID == cardID else { return }
        let preservedScrollOrigin = scrollView?.contentView.bounds.origin
        let target = dragState.dropTarget
        let shouldCommit = target != dragState.sourceTarget && !target.holdsGroupBlock
        if shouldCommit {
            indexBoardDropPerformanceMark("card_drop \(cardID.uuidString)")
        }
        prepareViewportPreservationAfterDrop(preservedScrollOrigin)

        if shouldCommit {
            presentationSurfaceProjection = resolvedPresentationSurfaceProjection(for: dragState)
            pendingLayoutAnimationDuration = IndexBoardSurfaceAppKitConstants.commitLayoutAnimationDuration
            requestsDeferredCommitLayout = true
        } else {
            presentationSurfaceProjection = nil
            pendingLayoutAnimationDuration = 0
        }
        self.dragState = nil
        localCardDragPreviewFramesByID = nil
        dragSnapshots = []
        restingSceneSnapshot = nil
        frozenLogicalGridBounds = nil
        stopAutoScrollTimer()
        if shouldCommit {
            updateOverlayLayers()
        } else {
            endMotionScene()
            applyCurrentLayout(animationDuration: IndexBoardSurfaceAppKitConstants.commitLayoutAnimationDuration)
        }
        restoreScrollOriginAfterDrop(preservedScrollOrigin, notifySession: false)
        if !shouldCommit, let preservedScrollOrigin {
            configuration.onScrollOffsetChange(preservedScrollOrigin)
        }

        guard shouldCommit else {
            finishBaselineSession(didCommit: false)
            return
        }
        let callbackStartedAt = CFAbsoluteTimeGetCurrent()
        if dragState.movingCardIDs.count > 1 {
            configuration.onCardMoveSelection(dragState.movingCardIDs, cardID, target)
        } else {
            configuration.onCardMove(cardID, target)
        }
        indexBoardDropPerformanceLog(
            "surface_commit_callback",
            "mode=\(dragState.movingCardIDs.count > 1 ? "selection" : "single") ms=\(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - callbackStartedAt) * 1000))"
        )
        armMotionSceneCommitBridgeIfNeeded()
        finishBaselineSession(didCommit: true)
    }

    func beginGroupDrag(parentCardID: UUID, pointer: CGPoint) {
        let dragStartedAt = CFAbsoluteTimeGetCurrent()
        guard let group = effectiveSurfaceProjection.parentGroups.first(where: { $0.parentCardID == parentCardID }),
              let groupFrame = resolvedParentGroupFrame(for: group) else { return }
        beginBaselineSession(kind: "group", movingCardCount: group.cardIDs.count)
        restingSceneSnapshot = makeRestingSceneSnapshot()
        frozenLogicalGridBounds = logicalGridBounds
        groupDragSnapshot = snapshotImage(in: groupFrame)
        groupDragState = IndexBoardSurfaceAppKitGroupDragState(
            parentCardID: parentCardID,
            movingCardIDs: group.cardIDs,
            initialOrigin: group.origin,
            initialFrame: groupFrame,
            pointerOffset: CGSize(
                width: pointer.x - groupFrame.minX,
                height: pointer.y - groupFrame.minY
            ),
            pointerInContent: pointer,
            targetOrigin: group.origin
        )
        if var groupDragState {
            groupDragState.targetOrigin = resolvedGroupDragOrigin(for: groupDragState)
            self.groupDragState = groupDragState
            updateLocalGroupDragPreview(for: groupDragState)
            presentationSurfaceProjection = resolvedPresentationSurfaceProjection(for: groupDragState)
        }
        beginMotionScene(
            snapshotCardIDs: Set(group.cardIDs),
            hiddenLiveCardIDs: Set(group.cardIDs),
            includingChips: true,
            includingWrappers: true
        )
        updateOverlayLayers()
        indexBoardDropPerformanceLog(
            "drag_begin",
            "kind=group parent=\(parentCardID.uuidString) moving_cards=\(group.cardIDs.count) ms=\(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - dragStartedAt) * 1000))"
        )
    }

    func endGroupDrag(parentCardID: UUID) {
        guard let groupDragState, groupDragState.parentCardID == parentCardID else { return }
        let preservedScrollOrigin = scrollView?.contentView.bounds.origin
        let targetOrigin = groupDragState.targetOrigin
        let shouldCommit = targetOrigin != groupDragState.initialOrigin
        prepareViewportPreservationAfterDrop(preservedScrollOrigin)
        if shouldCommit {
            presentationSurfaceProjection = resolvedPresentationSurfaceProjection(for: groupDragState)
            pendingLayoutAnimationDuration = IndexBoardSurfaceAppKitConstants.commitLayoutAnimationDuration
        } else {
            presentationSurfaceProjection = nil
            pendingLayoutAnimationDuration = 0
        }
        self.groupDragState = nil
        updateLocalGroupDragPreview(for: nil)
        groupDragSnapshot = nil
        restingSceneSnapshot = nil
        frozenLogicalGridBounds = nil
        if shouldCommit {
            updateOverlayLayers()
        } else {
            endMotionScene()
            applyCurrentLayout(animationDuration: IndexBoardSurfaceAppKitConstants.commitLayoutAnimationDuration)
        }
        restoreScrollOriginAfterDrop(preservedScrollOrigin, notifySession: false)
        if !shouldCommit, let preservedScrollOrigin {
            configuration.onScrollOffsetChange(preservedScrollOrigin)
        }
        guard shouldCommit else {
            finishBaselineSession(didCommit: false)
            return
        }
        configuration.onParentGroupMove(
            IndexBoardParentGroupDropTarget(
                parentCardID: parentCardID,
                origin: targetOrigin
            )
        )
        armMotionSceneCommitBridgeIfNeeded()
        finishBaselineSession(didCommit: true)
    }

    func resolvedGroupDragOrigin(
        for drag: IndexBoardSurfaceAppKitGroupDragState
    ) -> IndexBoardGridPosition {
        let groupOrigin = drag.overlayOrigin()
        let snappedPoint = CGPoint(
            x: groupOrigin.x + (IndexBoardMetrics.cardSize.width / 2),
            y: groupOrigin.y + ((IndexBoardMetrics.cardSize.height + IndexBoardSurfaceAppKitConstants.laneChipHeight) / 2)
        )
        return resolvedNearestGridPosition(for: snappedPoint)
    }

    func reconcilePresentationProjection() {
        guard dragState == nil,
              groupDragState == nil,
              let presentationSurfaceProjection else {
            if dragState == nil && groupDragState == nil {
                self.presentationSurfaceProjection = nil
            }
            return
        }

        if presentationSurfaceProjection.surfaceItems == configuration.surfaceProjection.surfaceItems {
            self.presentationSurfaceProjection = nil
        }
    }

    func resolvedDropPlacement(for drag: IndexBoardSurfaceAppKitDragState) -> IndexBoardSurfaceAppKitDropPlacement {
        let logicalSnapshot = dragLogicalSnapshot
        let visibleItems = logicalSnapshot.orderedItems.filter {
            $0.parentGroupID != nil && !drag.movingCardIDSet.contains($0.cardID)
        }
        let dragCardCenter = resolvedDragCardCenter(for: drag)

        if let flowInteractionRect = resolvedFlowInteractionRect(
            slotCount: visibleItems.count
        ),
           flowInteractionRect.contains(dragCardCenter) {
            return .flow(
                resolvedFlowDropSlotIndex(
                    for: dragCardCenter,
                    slotCount: visibleItems.count
                )
            )
        }

        return .detached(
            resolvedDetachedGridPosition(
                for: dragCardCenter,
                excluding: drag.movingCardIDSet,
                logicalSnapshot: logicalSnapshot
            )
        )
    }

    func resolvedDropTarget(for drag: IndexBoardSurfaceAppKitDragState) -> IndexBoardCardDropTarget {
        let logicalSnapshot = dragLogicalSnapshot
        let dragCardCenter = resolvedDragCardCenter(for: drag)

        if let targetGroupMode = resolvedCardDropTargetGroup(for: drag) {
            switch targetGroupMode {
            case .slot(let targetGroup):
                let visibleItems = logicalSnapshot.orderedItems.filter { item in
                    item.parentGroupID == targetGroup.id && !drag.movingCardIDSet.contains(item.cardID)
                }
                let visibleOrder = visibleItems.map(\.cardID.uuidString).joined(separator: ",")
                indexBoardOrderDiagnosticsLog(
                    "drop_target hover group=\(targetGroup.id.id) visibleOrder=\(visibleOrder) currentTargetInsertion=\(drag.dropTarget.insertionIndex)"
                )
                let insertionIndex = resolvedFlowInsertionIndex(
                    for: targetGroup,
                    visibleItemCount: visibleItems.count,
                    point: dragCardCenter,
                    drag: drag
                )
                let previousCardID = insertionIndex > 0 ? visibleItems[insertionIndex - 1].cardID : nil
                let nextCardID = insertionIndex < visibleItems.count ? visibleItems[insertionIndex].cardID : nil
                return IndexBoardCardDropTarget(
                    groupID: legacyGroupID(for: targetGroup.parentCardID),
                    insertionIndex: insertionIndex,
                    laneParentID: targetGroup.parentCardID,
                    previousCardID: previousCardID,
                    nextCardID: nextCardID,
                    preferredColumnCount: nil
                )
            case .block(let targetGroup):
                if drag.dropTarget.groupBlockParentID == targetGroup.parentCardID {
                    return drag.dropTarget
                }
                return IndexBoardCardDropTarget(
                    groupID: legacyGroupID(for: targetGroup.parentCardID),
                    insertionIndex: drag.sourceTarget.insertionIndex,
                    laneParentID: targetGroup.parentCardID,
                    previousCardID: nil,
                    nextCardID: nil,
                    detachedGridPosition: nil,
                    preferredColumnCount: nil,
                    groupBlockParentID: targetGroup.parentCardID
                )
            }
        }

        let detachedGridPosition = resolvedDetachedGridPosition(
            for: dragCardCenter,
            excluding: drag.movingCardIDSet,
            logicalSnapshot: logicalSnapshot
        )

        if let detachedBlockTarget = resolvedDetachedBlockDropTarget(for: drag) {
            if drag.sourceTarget == detachedBlockTarget {
                return drag.sourceTarget
            }
            return detachedBlockTarget
        }

        if drag.sourceTarget.detachedGridPosition == detachedGridPosition,
           drag.sourceTarget.previousTempMember == nil,
           drag.sourceTarget.nextTempMember == nil,
           drag.sourceTarget.previousCardID == nil,
           drag.sourceTarget.nextCardID == nil {
            return drag.sourceTarget
        }
        return IndexBoardCardDropTarget(
            groupID: legacyGroupID(for: tempLaneParentID() ?? drag.sourceLaneParentID),
            insertionIndex: drag.sourceTarget.insertionIndex,
            laneParentID: tempLaneParentID() ?? drag.sourceLaneParentID,
            detachedGridPosition: detachedGridPosition,
            preferredColumnCount: nil
        )
    }

    func resolvedGroupFrame(
        for group: BoardSurfaceParentGroupPlacement,
        cardFramesByID: [UUID: CGRect]
    ) -> CGRect? {
        let groupFrames = group.cardIDs.compactMap { cardFramesByID[$0] }
        guard let firstFrame = groupFrames.first else { return nil }
        let cardUnion = groupFrames.dropFirst().reduce(firstFrame) { partial, frame in
            partial.union(frame)
        }
        let chipFrame = CGRect(
            x: firstFrame.minX,
            y: firstFrame.minY - IndexBoardSurfaceAppKitConstants.laneChipSpacing - IndexBoardSurfaceAppKitConstants.laneChipHeight,
            width: IndexBoardMetrics.cardSize.width,
            height: IndexBoardSurfaceAppKitConstants.laneChipHeight
        )
        let baseFrame = cardUnion.union(chipFrame)
        return baseFrame.insetBy(
            dx: -IndexBoardSurfaceAppKitConstants.laneWrapperInset,
            dy: -IndexBoardSurfaceAppKitConstants.laneWrapperInset
        )
    }

    func resolvedPreviewParentGroups(
        for drag: IndexBoardSurfaceAppKitGroupDragState,
        baseProjection: BoardSurfaceProjection
    ) -> [BoardSurfaceParentGroupPlacement] {
        let updatedParentGroups = baseProjection.parentGroups.map { group in
            guard group.parentCardID == drag.parentCardID else { return group }
            return BoardSurfaceParentGroupPlacement(
                id: group.id,
                parentCardID: group.parentCardID,
                origin: drag.targetOrigin,
                cardIDs: group.cardIDs,
                titleText: group.titleText,
                subtitleText: group.subtitleText,
                colorToken: group.colorToken,
                isMainline: group.isMainline,
                isTempGroup: group.isTempGroup
            )
        }

        guard let movingGroup = updatedParentGroups.first(where: { $0.parentCardID == drag.parentCardID }),
              !movingGroup.isTempGroup else {
            return updatedParentGroups.sorted(by: indexBoardSurfaceAppKitGroupSort)
        }

        let normalizedLayout = normalizedIndexBoardSurfaceLayout(
            parentGroups: updatedParentGroups,
            detachedPositionsByCardID: indexBoardDetachedGridPositionsByCardID(from: baseProjection),
            referenceParentGroups: baseProjection.parentGroups,
            referenceDetachedPositionsByCardID: indexBoardDetachedGridPositionsByCardID(from: baseProjection),
            preferredLeadingParentCardID: drag.parentCardID
        )
        return normalizedLayout.parentGroups.sorted(by: indexBoardSurfaceAppKitGroupSort)
    }

    func resolvedLocalGroupDragPreview(
        for drag: IndexBoardSurfaceAppKitGroupDragState
    ) -> IndexBoardSurfaceAppKitGroupDragPreview? {
        withIndexBoardSurfaceAppKitSignpost(IndexBoardSurfaceAppKitSignpostName.resolvedLocalGroupPreview) {
            let snapshot = restingSceneSnapshot ?? makeRestingSceneSnapshot()
            let previewParentGroups = resolvedPreviewParentGroups(
                for: drag,
                baseProjection: snapshot.projection
            )
            var frames = snapshot.cardFrameByID
            for group in previewParentGroups {
                for (index, cardID) in group.cardIDs.enumerated() {
                    frames[cardID] = resolvedCardFrame(
                        for: IndexBoardGridPosition(
                            column: group.origin.column + index,
                            row: group.origin.row
                        )
                    )
                }
            }
            let targetFrame = previewParentGroups
                .first(where: { $0.parentCardID == drag.parentCardID })
                .map { resolvedCardFrame(for: $0.origin) }
            return IndexBoardSurfaceAppKitGroupDragPreview(
                cardFramesByID: frames,
                targetFrame: targetFrame
            )
        }
    }

    func resolvedNearestGroupDragOrigin(
        near candidate: IndexBoardGridPosition,
        width: Int,
        occupiedPositions: Set<IndexBoardGridPosition>
    ) -> IndexBoardGridPosition {
        let bounds = logicalGridBounds
        let safeWidth = max(1, width)
        let maxStartColumn = max(bounds.minColumn, bounds.maxColumn - max(0, safeWidth - 1))

        func isValid(_ origin: IndexBoardGridPosition) -> Bool {
            guard origin.row >= bounds.minRow,
                  origin.row <= bounds.maxRow,
                  origin.column >= bounds.minColumn,
                  origin.column <= maxStartColumn else {
                return false
            }
            return !occupiedPositions.contains(origin)
        }

        let clampedCandidate = IndexBoardGridPosition(
            column: min(max(bounds.minColumn, candidate.column), maxStartColumn),
            row: min(max(bounds.minRow, candidate.row), bounds.maxRow)
        )
        if isValid(clampedCandidate) {
            return clampedCandidate
        }

        let maxRadius = max(bounds.columnCount, bounds.rowCount)
        for radius in 1...maxRadius {
            var candidates: [IndexBoardGridPosition] = []
            for row in (clampedCandidate.row - radius)...(clampedCandidate.row + radius) {
                for column in (clampedCandidate.column - radius)...(clampedCandidate.column + radius) {
                    let rowDelta = abs(row - clampedCandidate.row)
                    let columnDelta = abs(column - clampedCandidate.column)
                    guard max(rowDelta, columnDelta) == radius else { continue }
                    candidates.append(IndexBoardGridPosition(column: column, row: row))
                }
            }

            let nearest = candidates.sorted { lhs, rhs in
                let lhsDistance = abs(lhs.row - clampedCandidate.row) + abs(lhs.column - clampedCandidate.column)
                let rhsDistance = abs(rhs.row - clampedCandidate.row) + abs(rhs.column - clampedCandidate.column)
                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }
                if lhs.row != rhs.row {
                    return lhs.row < rhs.row
                }
                return lhs.column < rhs.column
            }

            if let resolved = nearest.first(where: isValid) {
                return resolved
            }
        }

        return dragFallbackGroupOrigin(
            candidate: clampedCandidate,
            maxStartColumn: maxStartColumn,
            bounds: bounds
        )
    }

    func dragFallbackGroupOrigin(
        candidate: IndexBoardGridPosition,
        maxStartColumn: Int,
        bounds: IndexBoardSurfaceAppKitGridBounds
    ) -> IndexBoardGridPosition {
        IndexBoardGridPosition(
            column: min(max(bounds.minColumn, candidate.column), maxStartColumn),
            row: min(max(bounds.minRow, candidate.row), bounds.maxRow)
        )
    }

    func shouldPreferDetachedParking(
        at point: CGPoint,
        candidatePosition: IndexBoardGridPosition,
        over stripTarget: IndexBoardCardDropTarget,
        for drag: IndexBoardSurfaceAppKitDragState
    ) -> Bool {
        guard stripTarget.previousTempMember != nil || stripTarget.nextTempMember != nil else {
            return false
        }
        let compactedStrips = resolvedIndexBoardTempStripsAfterRemovingMembers(
            strips: referenceTempStrips(),
            movingMembers: drag.movingTempMembers
        )
        guard let targetStrip = compactedStrips.first(where: { strip in
            if let previousMember = stripTarget.previousTempMember, strip.members.contains(previousMember) {
                return true
            }
            if let nextMember = stripTarget.nextTempMember, strip.members.contains(nextMember) {
                return true
            }
            return false
        }) else {
            return false
        }
        guard candidatePosition.row != targetStrip.row else {
            return false
        }
        let candidateFrame = resolvedCardFrame(for: candidatePosition).insetBy(dx: -18, dy: -18)
        return candidateFrame.contains(point)
    }

    func isDetachedSourcePreview(_ drag: IndexBoardSurfaceAppKitDragState) -> Bool {
        false
    }

    func resolvedDetachedSourcePreviewPositions(
        for pendingMove: IndexBoardSurfaceAppKitPendingCardMove
    ) -> [UUID: IndexBoardGridPosition] {
        resolvedIndexBoardDetachedPositionsAfterRemovingCards(
            referencePositionsByCardID: pendingMove.logicalSnapshot.detachedPositionsByCardID,
            movingCardIDs: pendingMove.movingCardIDs
        )
    }

    func resolvedDetachedTargetFrames(
        for pendingMove: IndexBoardSurfaceAppKitPendingCardMove
    ) -> [CGRect] {
        if let parkingPosition = pendingMove.target.detachedGridPosition {
            return pendingMove.movingCardIDs.enumerated().map { offset, _ in
                resolvedCardFrame(
                    for: IndexBoardGridPosition(
                        column: parkingPosition.column + offset,
                        row: parkingPosition.row
                    )
                )
            }
        }

        let compactedStrips = resolvedIndexBoardTempStripsAfterRemovingMembers(
            strips: pendingMove.logicalSnapshot.tempStrips,
            movingMembers: pendingMove.movingTempMembers
        )
        let widthsByParentID = pendingMove.logicalSnapshot.tempGroupWidthsByParentID
        let targetStrip = compactedStrips.first { strip in
            if let previousMember = pendingMove.target.previousTempMember,
               strip.members.contains(previousMember) {
                return true
            }
            if let nextMember = pendingMove.target.nextTempMember,
               strip.members.contains(nextMember) {
                return true
            }
            return false
        }
        guard let targetStrip else { return [] }

        let slotDescriptors = resolvedTempStripSlotDescriptors(
            for: targetStrip,
            widthsByParentID: widthsByParentID
        )
        let matchingSlot = slotDescriptors.first { descriptor in
            descriptor.previous == pendingMove.target.previousTempMember &&
            descriptor.next == pendingMove.target.nextTempMember
        }
        guard let matchingSlot else { return [] }

        return pendingMove.movingCardIDs.enumerated().map { offset, _ in
            resolvedCardFrame(
                for: IndexBoardGridPosition(
                    column: matchingSlot.column + offset,
                    row: targetStrip.row
                )
            )
        }
    }

    func resolvedDetachedIndicatorFrames(
        for drag: IndexBoardSurfaceAppKitDragState
    ) -> ([CGRect], IndexBoardSurfaceAppKitPlaceholderStyle)? {
        let pendingMove = pendingCardMove(for: drag)
        guard !pendingMove.target.holdsGroupBlock else { return nil }
        let frames = resolvedDetachedTargetFrames(for: pendingMove)
        guard !frames.isEmpty else { return nil }
        let style: IndexBoardSurfaceAppKitPlaceholderStyle =
            (pendingMove.target.previousTempMember == nil &&
             pendingMove.target.nextTempMember == nil &&
             pendingMove.target.previousCardID == nil &&
             pendingMove.target.nextCardID == nil)
            ? .detachedParking
            : .detachedSlot
        return (frames, style)
    }

    func resolvedPreviewTempStrips(
        for pendingMove: IndexBoardSurfaceAppKitPendingCardMove
    ) -> [IndexBoardTempStripState] {
        if pendingMove.target.isTempStripTarget || pendingMove.target.detachedGridPosition != nil {
            return resolvedIndexBoardTempStripsByApplyingMove(
                strips: pendingMove.logicalSnapshot.tempStrips,
                movingMembers: pendingMove.movingTempMembers,
                previousMember: pendingMove.target.previousTempMember,
                nextMember: pendingMove.target.nextTempMember,
                parkingPosition: pendingMove.target.detachedGridPosition
            )
        }

        return resolvedIndexBoardTempStripsAfterRemovingMembers(
            strips: pendingMove.logicalSnapshot.tempStrips,
            movingMembers: pendingMove.movingTempMembers
        )
    }

    func resolvedPresentationSurfaceProjection(for drag: IndexBoardSurfaceAppKitDragState) -> BoardSurfaceProjection {
        let pendingMove = pendingCardMove(for: drag)
        let baseProjection = pendingMove.logicalSnapshot.projection
        if pendingMove.target.holdsGroupBlock {
            return baseProjection
        }
        let baseItems = baseProjection.surfaceItems.sorted(by: indexBoardSurfaceAppKitSort)
        let canonicalCardIDsByGroupID = canonicalCardIDsByGroupID(from: baseProjection)
        let movingIDs = pendingMove.movingCardIDSet
        let movingItemsByCardID = Dictionary(uniqueKeysWithValues: baseItems.compactMap { item -> (UUID, BoardSurfaceItem)? in
            movingIDs.contains(item.cardID) ? (item.cardID, item) : nil
        })
        let baseItemsByCardID = Dictionary(uniqueKeysWithValues: baseItems.map { ($0.cardID, $0) })
        let movingItems = pendingMove.movingCardIDs.compactMap { movingItemsByCardID[$0] }
        func rebuiltFlowPresentation(
            inserting movingCardIDs: [UUID] = [],
            targetGroupID: BoardSurfaceParentGroupID? = nil,
            insertionIndex: Int? = nil
        ) -> ([BoardSurfaceParentGroupPlacement], [BoardSurfaceItem]) {
            let updatedParentGroups = baseProjection.parentGroups.map { placement -> BoardSurfaceParentGroupPlacement in
                let groupCardIDs = canonicalCardIDsByGroupID[placement.id] ?? placement.cardIDs
                let stationaryCards = groupCardIDs.filter { !movingIDs.contains($0) }
                let cardIDs: [UUID]
                if placement.id == targetGroupID, let insertionIndex {
                    var updated = stationaryCards
                    updated.insert(
                        contentsOf: movingCardIDs,
                        at: min(max(0, insertionIndex), updated.count)
                    )
                    cardIDs = updated
                } else {
                    cardIDs = stationaryCards
                }
                return BoardSurfaceParentGroupPlacement(
                    id: placement.id,
                    parentCardID: placement.parentCardID,
                    origin: placement.origin,
                    cardIDs: cardIDs,
                    titleText: placement.titleText,
                    subtitleText: placement.subtitleText,
                    colorToken: placement.colorToken,
                    isMainline: placement.isMainline,
                    isTempGroup: placement.isTempGroup
                )
            }

            var regroupedItems: [BoardSurfaceItem] = []
            for placement in updatedParentGroups.sorted(by: indexBoardSurfaceAppKitGroupSort) {
                let placementLaneIndex = baseProjection.lanes.first(where: { $0.parentCardID == placement.parentCardID })?.laneIndex
                    ?? movingItems.first?.laneIndex
                    ?? 0
                let parentItems = placement.cardIDs.enumerated().map { index, cardID in
                    BoardSurfaceItem(
                        cardID: cardID,
                        laneParentID: placement.parentCardID,
                        laneIndex: placementLaneIndex,
                        slotIndex: nil,
                        detachedGridPosition: nil,
                        gridPosition: IndexBoardGridPosition(
                            column: placement.origin.column + index,
                            row: placement.origin.row
                        ),
                        parentGroupID: placement.id
                    )
                }
                regroupedItems.append(contentsOf: parentItems)
            }

            return (updatedParentGroups, regroupedItems)
        }

        let presentationParentGroups: [BoardSurfaceParentGroupPlacement]
        let target = pendingMove.target
        let resolvedItems: [BoardSurfaceItem]
        let previewTempStrips = resolvedPreviewTempStrips(for: pendingMove)
        let previewTempLayout = resolvedIndexBoardTempStripSurfaceLayout(
            strips: previewTempStrips,
            tempGroupWidthsByParentID: pendingMove.logicalSnapshot.tempGroupWidthsByParentID
        )
        let previewTempDetachedCardIDs = Set(previewTempLayout.detachedPositionsByCardID.keys)

        func normalizedPresentation(
            from parentGroups: [BoardSurfaceParentGroupPlacement]
        ) -> ([BoardSurfaceParentGroupPlacement], [BoardSurfaceItem]) {
            let updatedParentGroups = parentGroups.map { placement in
                guard placement.isTempGroup,
                      let parentCardID = placement.parentCardID,
                      let origin = previewTempLayout.groupOriginByParentID[parentCardID] else {
                    return placement
                }
                return BoardSurfaceParentGroupPlacement(
                    id: placement.id,
                    parentCardID: placement.parentCardID,
                    origin: origin,
                    cardIDs: placement.cardIDs,
                    titleText: placement.titleText,
                    subtitleText: placement.subtitleText,
                    colorToken: placement.colorToken,
                    isMainline: placement.isMainline,
                    isTempGroup: placement.isTempGroup
                )
            }
            let normalizedLayout = normalizedIndexBoardSurfaceLayout(
                parentGroups: updatedParentGroups,
                detachedPositionsByCardID: previewTempLayout.detachedPositionsByCardID,
                referenceParentGroups: baseProjection.parentGroups,
                referenceDetachedPositionsByCardID: indexBoardDetachedGridPositionsByCardID(from: baseProjection)
            )
            let normalizedParentGroups = normalizedLayout.parentGroups.sorted(by: indexBoardSurfaceAppKitGroupSort)

            let normalizedFlowItems = normalizedParentGroups.flatMap { placement in
                let laneIndex = baseProjection.lanes.first(where: { $0.parentCardID == placement.parentCardID })?.laneIndex
                    ?? movingItems.first?.laneIndex
                    ?? 0
                return placement.cardIDs.enumerated().map { index, cardID in
                    BoardSurfaceItem(
                        cardID: cardID,
                        laneParentID: placement.parentCardID,
                        laneIndex: laneIndex,
                        slotIndex: nil,
                        detachedGridPosition: nil,
                        gridPosition: IndexBoardGridPosition(
                            column: placement.origin.column + index,
                            row: placement.origin.row
                        ),
                        parentGroupID: placement.id
                    )
                }
            }

            let tempLaneIndex = baseProjection.lanes.first(where: \.isTempLane)?.laneIndex
            let normalizedDetachedItems = previewTempLayout.detachedPositionsByCardID
                .sorted { lhs, rhs in
                    if lhs.value.row != rhs.value.row {
                        return lhs.value.row < rhs.value.row
                    }
                    if lhs.value.column != rhs.value.column {
                        return lhs.value.column < rhs.value.column
                    }
                    return lhs.key.uuidString < rhs.key.uuidString
                }
                .compactMap { cardID, position -> BoardSurfaceItem? in
                    guard previewTempDetachedCardIDs.contains(cardID) else { return nil }
                    let sourceItem = baseItemsByCardID[cardID]
                    let resolvedLaneIndex = tempLaneIndex ?? sourceItem?.laneIndex ?? 0
                    let resolvedLaneParentID = tempLaneParentID() ?? sourceItem?.laneParentID
                    return BoardSurfaceItem(
                        cardID: cardID,
                        laneParentID: resolvedLaneParentID,
                        laneIndex: resolvedLaneIndex,
                        slotIndex: nil,
                        detachedGridPosition: position,
                        gridPosition: position,
                        parentGroupID: nil
                    )
                }

            return (normalizedParentGroups, normalizedFlowItems + normalizedDetachedItems)
        }

        if target.isTempStripTarget || target.detachedGridPosition != nil {
            let rebuiltFlow = rebuiltFlowPresentation()
            let normalized = normalizedPresentation(from: rebuiltFlow.0)
            presentationParentGroups = normalized.0
            resolvedItems = normalized.1
        } else {
            let targetLaneParentID = target.laneParentID ?? drag.sourceLaneParentID
            let targetGroupID = targetLaneParentID.map(BoardSurfaceParentGroupID.parent) ?? .root
            let rebuiltFlow = rebuiltFlowPresentation(
                inserting: drag.movingCardIDs,
                targetGroupID: targetGroupID,
                insertionIndex: target.insertionIndex
            )
            let normalized = normalizedPresentation(from: rebuiltFlow.0)
            presentationParentGroups = normalized.0
            resolvedItems = normalized.1
        }

        let resolvedTempStrips: [IndexBoardTempStripState] = previewTempStrips
        let sortedItems = resolvedItems.sorted(by: indexBoardSurfaceAppKitSort)
        return BoardSurfaceProjection(
            source: baseProjection.source,
            startAnchor: baseProjection.startAnchor,
            lanes: baseProjection.lanes,
            parentGroups: presentationParentGroups,
            tempStrips: resolvedTempStrips,
            surfaceItems: sortedItems,
            orderedCardIDs: sortedItems.map(\.cardID)
        )
    }

    func resolvedPresentationSurfaceProjection(
        for drag: IndexBoardSurfaceAppKitGroupDragState
    ) -> BoardSurfaceProjection {
        let baseProjection = restingSceneSnapshot?.projection ?? configuration.surfaceProjection
        let updatedParentGroups = resolvedPreviewParentGroups(
            for: drag,
            baseProjection: baseProjection
        )

        let stationaryDetachedItems = baseProjection.surfaceItems.filter { $0.parentGroupID == nil }
        var regroupedItems: [BoardSurfaceItem] = []
        for placement in updatedParentGroups.sorted(by: indexBoardSurfaceAppKitGroupSort) {
            let laneIndex = baseProjection.lanes.first(where: { $0.parentCardID == placement.parentCardID })?.laneIndex ?? 0
            let updatedItems = placement.cardIDs.enumerated().map { index, cardID in
                BoardSurfaceItem(
                    cardID: cardID,
                    laneParentID: placement.parentCardID,
                    laneIndex: laneIndex,
                    slotIndex: nil,
                    detachedGridPosition: nil,
                    gridPosition: IndexBoardGridPosition(
                        column: placement.origin.column + index,
                        row: placement.origin.row
                    ),
                    parentGroupID: placement.id
                )
            }
            regroupedItems.append(contentsOf: updatedItems)
        }

        let sortedItems = (regroupedItems + stationaryDetachedItems).sorted(by: indexBoardSurfaceAppKitSort)
        return BoardSurfaceProjection(
            source: baseProjection.source,
            startAnchor: baseProjection.startAnchor,
            lanes: baseProjection.lanes,
            parentGroups: updatedParentGroups.sorted(by: indexBoardSurfaceAppKitGroupSort),
            tempStrips: baseProjection.tempStrips,
            surfaceItems: sortedItems,
            orderedCardIDs: sortedItems.map(\.cardID)
        )
    }

    func applyCardDragUpdate(
        _ updatedState: IndexBoardSurfaceAppKitDragState,
        previousTarget: IndexBoardCardDropTarget
    ) {
        self.dragState = updatedState
        updateLocalCardDragPreview(for: updatedState)
        let didRetarget = updatedState.dropTarget != previousTarget
        if didRetarget {
            updateBaselineSession { session in
                session.retargetCount += 1
            }
        }
        if didRetarget {
            presentationSurfaceProjection = resolvedPresentationSurfaceProjection(for: updatedState)
        }
        if motionScene != nil {
            updateMotionSceneLayout()
            updateOverlayLayers()
            return
        }
        if didRetarget {
            applyCurrentLayout(
                animationDuration: IndexBoardSurfaceAppKitConstants.previewLayoutAnimationDuration
            )
        } else {
            updateOverlayLayers()
        }
    }

    func applyGroupDragUpdate(
        _ updatedState: IndexBoardSurfaceAppKitGroupDragState,
        previousOrigin: IndexBoardGridPosition
    ) {
        self.groupDragState = updatedState
        updateLocalGroupDragPreview(for: updatedState)
        let didRetarget = updatedState.targetOrigin != previousOrigin
        if didRetarget {
            updateBaselineSession { session in
                session.retargetCount += 1
            }
        }
        if didRetarget {
            presentationSurfaceProjection = resolvedPresentationSurfaceProjection(for: updatedState)
        }
        if motionScene != nil {
            updateMotionSceneLayout()
            updateOverlayLayers()
            return
        }
        if didRetarget {
            applyCurrentLayout(
                animationDuration: IndexBoardSurfaceAppKitConstants.previewLayoutAnimationDuration
            )
        } else {
            updateOverlayLayers()
        }
    }

    func updateLocalCardDragPreview(
        for drag: IndexBoardSurfaceAppKitDragState?
    ) {
        guard let drag,
              drag.dropTarget != drag.sourceTarget else {
            localCardDragPreviewFramesByID = nil
            return
        }

        let frames = resolvedLocalCardDragPreviewFrames(for: drag)
        localCardDragPreviewFramesByID = frames.isEmpty ? nil : frames
    }

    func updateLocalGroupDragPreview(
        for drag: IndexBoardSurfaceAppKitGroupDragState?
    ) {
        guard let drag,
              drag.targetOrigin != drag.initialOrigin,
              let preview = resolvedLocalGroupDragPreview(for: drag) else {
            localGroupDragPreviewFramesByID = nil
            localGroupDragTargetFrame = nil
            return
        }

        localGroupDragPreviewFramesByID = preview.cardFramesByID
        localGroupDragTargetFrame = preview.targetFrame
    }

    func resolvedDetachedSelectionPositions(
        count: Int,
        start: IndexBoardGridPosition,
        occupied: Set<IndexBoardGridPosition>
    ) -> [IndexBoardGridPosition] {
        guard count > 0 else { return [] }
        var positions: [IndexBoardGridPosition] = []
        var taken = occupied
        var nextColumn = start.column
        while positions.count < count {
            let candidate = IndexBoardGridPosition(column: nextColumn, row: start.row)
            if !taken.contains(candidate) {
                positions.append(candidate)
                taken.insert(candidate)
            }
            nextColumn += 1
        }
        return positions
    }

    func legacyGroupID(for laneParentID: UUID?) -> IndexBoardGroupID {
        laneParentID.map(IndexBoardGroupID.parent) ?? .root
    }

}
