import Foundation
import CoreGraphics

nonisolated enum BWRSlotBoardCardDropDestination: Equatable, Sendable {
    case existingHost(BWRSlotHost, insertionIndex: Int)
    case newParkingStrip(originSlot: BWRSlotCoordinate, insertionIndex: Int)
}

nonisolated struct BWRSlotBoardCardDropTarget: Equatable, Sendable {
    var destination: BWRSlotBoardCardDropDestination
    var placeholder: BWRProjectedPlaceholder
}

nonisolated struct BWRSlotBoardGroupDropTarget: Equatable, Sendable {
    var groupID: UUID
    var originSlot: BWRSlotCoordinate
    var placeholder: BWRProjectedPlaceholder
}

nonisolated enum BWRSlotBoardInteraction {
    static func resolveHoverPlaceholder(
        projection: BWRSlotBoardProjectionSnapshot,
        pointer: CGPoint
    ) -> BWRHoverPlaceholderState? {
        let groupCandidates = projection.groupFrames.compactMap { frame -> (host: BWRSlotHost, insertionIndex: Int, distance: CGFloat)? in
            let visibleCardCount = frame.group.memberCardIDs.count
            let activation = attachmentCaptureRect(
                for: frame,
                visibleCardCount: visibleCardCount,
                projection: projection
            )
            guard activation.contains(pointer) else { return nil }
            let host = BWRSlotHost.group(frame.group.id)
            let insertionIndex = nearestInsertionIndex(
                pointer: pointer,
                host: host,
                slotCount: visibleCardCount,
                projection: projection
            )
            return (host, insertionIndex, pointerDistance(from: pointer, to: activation))
        }

        let stripCandidates = projection.stripFrames.compactMap { frame -> (host: BWRSlotHost, insertionIndex: Int, distance: CGFloat)? in
            let visibleCardCount = frame.strip.cardIDs.count
            let activation = stripCaptureRect(
                for: frame,
                visibleCardCount: visibleCardCount,
                projection: projection
            )
            guard activation.contains(pointer) else { return nil }
            let host = BWRSlotHost.strip(frame.strip.id)
            let insertionIndex = nearestInsertionIndex(
                pointer: pointer,
                host: host,
                slotCount: visibleCardCount,
                projection: projection
            )
            return (host, insertionIndex, pointerDistance(from: pointer, to: activation))
        }

        let winner = (groupCandidates + stripCandidates).sorted { lhs, rhs in
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            let leftKey = hostSortKey(lhs.host, projection: projection)
            let rightKey = hostSortKey(rhs.host, projection: projection)
            if leftKey != rightKey { return leftKey < rightKey }
            return lhs.insertionIndex < rhs.insertionIndex
        }.first

        guard let winner else { return nil }
        return BWRHoverPlaceholderState(
            hoveredHost: winner.host,
            hoveredInsertionIndex: winner.insertionIndex,
            hoverLocation: BWRPoint(x: pointer.x, y: pointer.y)
        )
    }

    static func resolveCardDropTarget(
        document: BWRDocument,
        projection: BWRSlotBoardProjectionSnapshot,
        draggingCardIDs: [UUID],
        leadCardID: UUID,
        pointer: CGPoint,
        viewportState: BWRViewportState
    ) -> BWRSlotBoardCardDropTarget? {
        let draggingSet = Set(draggingCardIDs)
        if let target = attachTarget(
            projection: projection,
            draggingCardIDs: draggingSet,
            pointer: pointer
        ) {
            return target
        }

        if let target = detachTarget(
            document: document,
            projection: projection,
            draggingCardIDs: draggingSet,
            leadCardID: leadCardID,
            pointer: pointer,
            viewportState: viewportState
        ) {
            return target
        }

        return nil
    }

    static func resolveDragOverlayState(
        document: BWRDocument,
        projection: BWRSlotBoardProjectionSnapshot,
        movingCardIDs: [UUID],
        target: BWRSlotBoardCardDropTarget?
    ) -> BWRDragOverlayState {
        guard !movingCardIDs.isEmpty else { return .init() }

        let sourceReferences = movingCardIDs.compactMap { cardID -> BWRBoardSlotReference? in
            guard let location = BWRSlotOrder.indexOfCardInHost(cardID: cardID, document: document) else {
                return nil
            }
            return BWRBoardSlotReference(host: location.host, slotIndex: location.index)
        }

        var overlay = BWRDragOverlayState(
            dragSourceSlot: sourceReferences.first,
            dragDestinationSlot: nil,
            dragSourceSlots: sourceReferences,
            dragDestinationSlots: [],
            dragLiftStyle: .lifted
        )

        guard let target else { return overlay }

        switch target.destination {
        case let .existingHost(host, rawInsertionIndex):
            let adjustedIndex = adjustedInsertionIndex(
                rawInsertionIndex: rawInsertionIndex,
                movingCardIDs: movingCardIDs,
                targetHost: host,
                document: document
            )
            let movingSet = Set(movingCardIDs)
            let residentCount = BWRSlotOrder.cardIDs(in: host, document: document)
                .filter { !movingSet.contains($0) }
                .count
            let destinationReferences = (0..<movingCardIDs.count).map {
                BWRBoardSlotReference(host: host, slotIndex: adjustedIndex + $0)
            }
            overlay.dragDestinationSlot = destinationReferences.first
            overlay.dragDestinationSlots = destinationReferences
            overlay.dragDestinationResidentCount = residentCount
        case let .newParkingStrip(originSlot, insertionIndex):
            overlay.transientDestinationRects = (0..<movingCardIDs.count).map { offset in
                let slotRect = CGRect(
                    x: CGFloat(originSlot.column + insertionIndex + offset) * projection.metrics.slotWidth,
                    y: CGFloat(originSlot.row) * projection.metrics.slotHeight,
                    width: projection.metrics.slotWidth,
                    height: projection.metrics.slotHeight
                )
                return BWRBoardRectSnapshot(
                    rect: BWRSlotBoardGeometry.placeholderRect(in: slotRect, metrics: projection.metrics)
                )
            }
        }

        return overlay
    }

    static func resolveGroupDropTarget(
        projection: BWRSlotBoardProjectionSnapshot,
        groupID: UUID,
        candidateOriginSlot: BWRSlotCoordinate
    ) -> BWRSlotBoardGroupDropTarget? {
        guard let frame = projection.groupFrames.first(where: { $0.group.id == groupID }) else {
            return nil
        }

        var occupancy = BWROccupancyMap()
        for groupFrame in projection.groupFrames where groupFrame.group.id != groupID {
            occupancy.occupy(origin: groupFrame.resolvedOriginSlot, footprint: groupFrame.footprint)
        }
        for stripFrame in projection.stripFrames {
            occupancy.occupy(origin: stripFrame.resolvedOriginSlot, footprint: stripFrame.footprint)
        }

        let resolvedOrigin = BWRSlotBoardGeometry.scanForFreeOrigin(
            start: candidateOriginSlot,
            footprint: frame.footprint,
            occupied: occupancy,
            metrics: projection.metrics
        )
        guard let rect = projection.groupBlockPlaceholderRect(
            groupID: groupID,
            candidateOriginSlot: resolvedOrigin
        ) else {
            return nil
        }

        return BWRSlotBoardGroupDropTarget(
            groupID: groupID,
            originSlot: resolvedOrigin,
            placeholder: BWRProjectedPlaceholder(
                id: "group-block-\(groupID.uuidString)",
                kind: .groupBlock(groupID),
                rect: rect
            )
        )
    }

    static func adjustedInsertionIndex(
        rawInsertionIndex: Int,
        movingCardIDs: [UUID],
        targetHost: BWRSlotHost,
        document: BWRDocument
    ) -> Int {
        guard !movingCardIDs.isEmpty else { return rawInsertionIndex }
        let movingSet = Set(movingCardIDs)
        let hostCardIDs = cardIDs(for: targetHost, document: document)
        guard hostCardIDs.contains(where: { movingSet.contains($0) }) else {
            return rawInsertionIndex
        }
        let shiftedCount = hostCardIDs
            .prefix(max(0, rawInsertionIndex))
            .filter { movingSet.contains($0) }
            .count
        return max(0, rawInsertionIndex - shiftedCount)
    }

    static func orderedMovingCardIDs(document: BWRDocument, cardIDs: Set<UUID>) -> [UUID] {
        BWRSlotOrder.orderedLiveCardIDs(in: document).filter { cardIDs.contains($0) }
    }

    private static func attachTarget(
        projection: BWRSlotBoardProjectionSnapshot,
        draggingCardIDs: Set<UUID>,
        pointer: CGPoint
    ) -> BWRSlotBoardCardDropTarget? {
        let groupCandidates = projection.groupFrames.compactMap { frame -> (frame: BWRProjectedGroupFrame, distance: CGFloat)? in
            let visibleCardCount = frame.group.memberCardIDs.filter { !draggingCardIDs.contains($0) }.count
            let activation = attachmentCaptureRect(
                for: frame,
                visibleCardCount: visibleCardCount,
                projection: projection
            )
            guard activation.contains(pointer) else { return nil }
            return (frame, pointerDistance(from: pointer, to: activation))
        }
        .sorted { lhs, rhs in
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            if lhs.frame.resolvedOriginSlot.row != rhs.frame.resolvedOriginSlot.row {
                return lhs.frame.resolvedOriginSlot.row < rhs.frame.resolvedOriginSlot.row
            }
            if lhs.frame.resolvedOriginSlot.column != rhs.frame.resolvedOriginSlot.column {
                return lhs.frame.resolvedOriginSlot.column < rhs.frame.resolvedOriginSlot.column
            }
            return lhs.frame.group.id.uuidString < rhs.frame.group.id.uuidString
        }

        guard let winner = groupCandidates.first else { return nil }

        let cardCount = winner.frame.group.memberCardIDs.filter { !draggingCardIDs.contains($0) }.count
        let insertionIndex = nearestInsertionIndex(
            pointer: pointer,
            host: .group(winner.frame.group.id),
            slotCount: cardCount,
            projection: projection
        )
        guard let rect = projection.placeholderRect(
            for: .group(winner.frame.group.id),
            insertionIndex: insertionIndex
        ) else {
            return nil
        }

        return BWRSlotBoardCardDropTarget(
            destination: .existingHost(.group(winner.frame.group.id), insertionIndex: insertionIndex),
            placeholder: BWRProjectedPlaceholder(
                id: "attach-\(winner.frame.group.id.uuidString)-\(insertionIndex)",
                kind: .dragDestination(.group(winner.frame.group.id)),
                rect: rect
            )
        )
    }

    private static func attachmentCaptureRect(
        for frame: BWRProjectedGroupFrame,
        visibleCardCount: Int,
        projection: BWRSlotBoardProjectionSnapshot
    ) -> CGRect {
        var capture = frame.rect.insetBy(
            dx: -projection.metrics.slotWidth * 0.18,
            dy: -projection.metrics.slotHeight * 0.12
        )
        for insertionIndex in 0...max(visibleCardCount, 0) {
            if let placeholder = projection.placeholderRect(
                for: .group(frame.group.id),
                insertionIndex: insertionIndex
            ) {
                capture = capture.union(
                    placeholder.insetBy(
                        dx: -projection.metrics.slotWidth * 0.12,
                        dy: -projection.metrics.slotHeight * 0.08
                    )
                )
            }
        }
        return capture
    }

    private static func stripCaptureRect(
        for frame: BWRProjectedParkingStripFrame,
        visibleCardCount: Int,
        projection: BWRSlotBoardProjectionSnapshot
    ) -> CGRect {
        var capture = frame.rect.insetBy(
            dx: -projection.metrics.slotWidth * 0.12,
            dy: -projection.metrics.slotHeight * 0.14
        )
        for insertionIndex in 0...max(visibleCardCount, 0) {
            if let placeholder = projection.placeholderRect(
                for: .strip(frame.strip.id),
                insertionIndex: insertionIndex
            ) {
                capture = capture.union(
                    placeholder.insetBy(
                        dx: -projection.metrics.slotWidth * 0.10,
                        dy: -projection.metrics.slotHeight * 0.08
                    )
                )
            }
        }
        return capture
    }

    private static func detachTarget(
        document: BWRDocument,
        projection: BWRSlotBoardProjectionSnapshot,
        draggingCardIDs: Set<UUID>,
        leadCardID: UUID,
        pointer: CGPoint,
        viewportState: BWRViewportState
    ) -> BWRSlotBoardCardDropTarget? {
        let pointerBandRow = Int((pointer.y / projection.metrics.slotHeight).rounded(.down))
        let stripFrames = projection.stripFrames.sorted { lhs, rhs in
            let left = stripRanking(frame: lhs, pointerBandRow: pointerBandRow, pointer: pointer)
            let right = stripRanking(frame: rhs, pointerBandRow: pointerBandRow, pointer: pointer)
            if left.containsActivation != right.containsActivation {
                return left.containsActivation && !right.containsActivation
            }
            if left.distance != right.distance { return left.distance < right.distance }
            if left.sameBand != right.sameBand { return left.sameBand && !right.sameBand }
            if left.anchorColumn != right.anchorColumn { return left.anchorColumn < right.anchorColumn }
            return lhs.strip.id.uuidString < rhs.strip.id.uuidString
        }

        if let stripFrame = stripFrames.first {
            let visibleCardCount = stripFrame.strip.cardIDs.filter { !draggingCardIDs.contains($0) }.count
            let insertionIndex = nearestInsertionIndex(
                pointer: pointer,
                host: .strip(stripFrame.strip.id),
                slotCount: visibleCardCount,
                projection: projection
            )
            if let rect = projection.placeholderRect(for: .strip(stripFrame.strip.id), insertionIndex: insertionIndex) {
                return BWRSlotBoardCardDropTarget(
                    destination: .existingHost(.strip(stripFrame.strip.id), insertionIndex: insertionIndex),
                    placeholder: BWRProjectedPlaceholder(
                        id: "detach-\(stripFrame.strip.id.uuidString)-\(insertionIndex)",
                        kind: .dragDestination(.strip(stripFrame.strip.id)),
                        rect: rect
                    )
                )
            }
        }

        let predictedOrigin = predictedParkingStripOrigin(
            projection: projection,
            viewportState: viewportState
        )
        let slotRect = CGRect(
            x: CGFloat(predictedOrigin.column) * projection.metrics.slotWidth,
            y: CGFloat(predictedOrigin.row) * projection.metrics.slotHeight,
            width: projection.metrics.slotWidth,
            height: projection.metrics.slotHeight
        )
        let rect = BWRSlotBoardGeometry.placeholderRect(in: slotRect, metrics: projection.metrics)
        return BWRSlotBoardCardDropTarget(
            destination: .newParkingStrip(originSlot: predictedOrigin, insertionIndex: 0),
            placeholder: BWRProjectedPlaceholder(
                id: "detach-new-\(predictedOrigin.column)-\(predictedOrigin.row)",
                kind: .dragDestination(nil),
                rect: rect
            )
        )
    }

    private static func stripRanking(
        frame: BWRProjectedParkingStripFrame,
        pointerBandRow: Int,
        pointer: CGPoint
    ) -> (containsActivation: Bool, distance: Int, sameBand: Bool, anchorColumn: Int) {
        let activation = frame.rect.insetBy(dx: -24, dy: -36)
        let resolvedRow = frame.resolvedOriginSlot.row
        return (
            activation.contains(pointer),
            abs(resolvedRow - pointerBandRow),
            resolvedRow == pointerBandRow,
            frame.strip.anchorColumn
        )
    }

    private static func predictedParkingStripOrigin(
        projection: BWRSlotBoardProjectionSnapshot,
        viewportState: BWRViewportState
    ) -> BWRSlotCoordinate {
        var occupancy = BWROccupancyMap()
        for frame in projection.groupFrames {
            occupancy.occupy(origin: frame.resolvedOriginSlot, footprint: frame.footprint)
        }
        for frame in projection.stripFrames {
            occupancy.occupy(origin: frame.resolvedOriginSlot, footprint: frame.footprint)
        }

        let viewportCenterY = viewportState.scrollOrigin.y + (viewportState.viewportSize.height * 0.5)
        let viewportBandRow = Int((viewportCenterY / projection.metrics.slotHeight).rounded(.down))
        let lastOccupiedRow = max(
            projection.groupFrames.map { $0.resolvedOriginSlot.row + $0.footprint.rows - 1 }.max() ?? -1,
            projection.stripFrames.map { $0.resolvedOriginSlot.row }.max() ?? -1
        )
        return BWRSlotBoardGeometry.resolveParkingStripOrigin(
            preferredRow: max(viewportBandRow, lastOccupiedRow) + 1,
            anchorColumn: 0,
            slotCount: 1,
            occupied: occupancy,
            metrics: projection.metrics
        )
    }

    private static func nearestInsertionIndex(
        pointer: CGPoint,
        host: BWRSlotHost,
        slotCount: Int,
        projection: BWRSlotBoardProjectionSnapshot
    ) -> Int {
        let candidateRange = 0...max(slotCount, 0)
        return candidateRange.min { lhs, rhs in
            let left = insertionScore(
                pointer: pointer,
                host: host,
                insertionIndex: lhs,
                projection: projection
            )
            let right = insertionScore(
                pointer: pointer,
                host: host,
                insertionIndex: rhs,
                projection: projection
            )
            if left.distance != right.distance { return left.distance < right.distance }
            return lhs < rhs
        } ?? 0
    }

    private static func insertionScore(
        pointer: CGPoint,
        host: BWRSlotHost,
        insertionIndex: Int,
        projection: BWRSlotBoardProjectionSnapshot
    ) -> (distance: CGFloat, preferredAxis: CGFloat) {
        guard let rect = projection.placeholderRect(for: host, insertionIndex: insertionIndex) else {
            return (.greatestFiniteMagnitude, .greatestFiniteMagnitude)
        }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return (
            hypot(center.x - pointer.x, center.y - pointer.y),
            abs(center.x - pointer.x)
        )
    }

    private static func pointerDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        if rect.contains(point) { return 0 }
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    private static func hostSortKey(
        _ host: BWRSlotHost,
        projection: BWRSlotBoardProjectionSnapshot
    ) -> String {
        switch host {
        case let .group(groupID):
            guard let frame = projection.groupFrames.first(where: { $0.group.id == groupID }) else {
                return "0-999999-999999-\(groupID.uuidString)"
            }
            return String(
                format: "0-%08d-%08d-%@",
                frame.resolvedOriginSlot.row,
                frame.resolvedOriginSlot.column,
                groupID.uuidString
            )
        case let .strip(stripID):
            guard let frame = projection.stripFrames.first(where: { $0.strip.id == stripID }) else {
                return "1-999999-999999-\(stripID.uuidString)"
            }
            return String(
                format: "1-%08d-%08d-%@",
                frame.resolvedOriginSlot.row,
                frame.resolvedOriginSlot.column,
                stripID.uuidString
            )
        }
    }

    private static func cardIDs(for host: BWRSlotHost, document: BWRDocument) -> [UUID] {
        BWRSlotOrder.cardIDs(in: host, document: document)
    }
}
