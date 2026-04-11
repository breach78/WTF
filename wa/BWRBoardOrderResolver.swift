import Foundation
import CoreGraphics

nonisolated enum BWRBoardArrowDirection: Sendable {
    case left
    case right
    case up
    case down
}

nonisolated struct BWRBoardOrderedCardPosition: Equatable, Sendable {
    var card: BWRCard
    var host: BWRSlotHost
    var slotIndex: Int
    var coordinate: BWRSlotCoordinate
    var boardIndex: Int
}

nonisolated struct BWRBoardOrderedSlotPosition: Equatable, Sendable {
    var reference: BWRBoardSlotReference
    var rect: CGRect
    var coordinate: BWRSlotCoordinate
    var boardIndex: Int
}

nonisolated enum BWRBoardOrderResolver {
    static func orderedLiveGroups(document: BWRDocument) -> [BWRGroup] {
        let groupsByID = Dictionary(uniqueKeysWithValues: document.groups.filter { !$0.isArchived }.map { ($0.id, $0) })
        let projection = BWRSlotBoardProjection.project(document: document)
        return visibleGroupFrames(projection: projection).compactMap { groupsByID[$0.group.id] }
    }

    static func orderedLiveCards(document: BWRDocument, includeParked: Bool = true) -> [BWRCard] {
        let projection = BWRSlotBoardProjection.project(document: document)
        return orderedCardPositions(document: document, includeParked: includeParked, projection: projection).map(\.card)
    }

    static func orderedCards(inGroup groupID: UUID, document: BWRDocument) -> [BWRCard] {
        BWRSlotOrder.orderedCards(inGroup: groupID, document: document)
    }

    static func orderedGroupIDs(document: BWRDocument, filteredTo groupIDs: [UUID]) -> [UUID] {
        let filter = Set(groupIDs)
        return orderedLiveGroups(document: document)
            .map(\.id)
            .filter { filter.contains($0) }
    }

    static func nextCardID(
        document: BWRDocument,
        from anchorCardID: UUID?,
        direction: BWRBoardArrowDirection
    ) -> UUID? {
        let projection = BWRSlotBoardProjection.project(document: document)
        let positions = orderedCardPositions(document: document, includeParked: true, projection: projection)
        guard !positions.isEmpty else { return nil }
        guard let anchorCardID,
              let anchor = positions.first(where: { $0.card.id == anchorCardID }) else {
            return positions.first?.card.id
        }

        let candidates = positions.filter { candidate in
            guard candidate.card.id != anchor.card.id else { return false }
            switch direction {
            case .left:
                return candidate.coordinate.column < anchor.coordinate.column
            case .right:
                return candidate.coordinate.column > anchor.coordinate.column
            case .up:
                return candidate.coordinate.row < anchor.coordinate.row
            case .down:
                return candidate.coordinate.row > anchor.coordinate.row
            }
        }

        return candidates.min { lhs, rhs in
            traversalScore(for: lhs, from: anchor, direction: direction) <
            traversalScore(for: rhs, from: anchor, direction: direction)
        }?.card.id
    }

    static func nextSlotReference(
        document: BWRDocument,
        from anchorReference: BWRBoardSlotReference?,
        direction: BWRBoardArrowDirection
    ) -> BWRBoardSlotReference? {
        let projection = BWRSlotBoardProjection.project(document: document)
        let positions = orderedSlotPositions(document: document, projection: projection)
        guard !positions.isEmpty else { return nil }

        guard let anchorReference,
              let anchor = positions.first(where: { $0.reference == anchorReference }) else {
            return positions.first?.reference
        }

        let candidates = positions.filter { candidate in
            guard candidate.reference != anchor.reference else { return false }
            switch direction {
            case .left:
                return candidate.coordinate.column < anchor.coordinate.column
            case .right:
                return candidate.coordinate.column > anchor.coordinate.column
            case .up:
                return candidate.coordinate.row < anchor.coordinate.row
            case .down:
                return candidate.coordinate.row > anchor.coordinate.row
            }
        }

        return candidates.min { lhs, rhs in
            slotTraversalScore(for: lhs, from: anchor, direction: direction) <
            slotTraversalScore(for: rhs, from: anchor, direction: direction)
        }?.reference
    }

    static func firstSlotReference(document: BWRDocument) -> BWRBoardSlotReference? {
        let projection = BWRSlotBoardProjection.project(document: document)
        return orderedSlotPositions(document: document, projection: projection).first?.reference
    }

    private static func orderedCardPositions(
        document: BWRDocument,
        includeParked: Bool,
        projection: BWRSlotBoardProjectionSnapshot
    ) -> [BWRBoardOrderedCardPosition] {
        let cardsByID = Dictionary(uniqueKeysWithValues: document.cards.filter { !$0.isArchived }.map { ($0.id, $0) })
        var orderedIDs: [UUID] = []
        var seen: Set<UUID> = []

        for frame in visibleGroupFrames(projection: projection) {
            for cardID in frame.group.memberCardIDs where cardsByID[cardID] != nil && seen.insert(cardID).inserted {
                orderedIDs.append(cardID)
            }
        }

        if includeParked {
            for frame in visibleStripFrames(projection: projection) {
                for cardID in frame.strip.cardIDs where cardsByID[cardID] != nil && seen.insert(cardID).inserted {
                    orderedIDs.append(cardID)
                }
            }
        }

        let remainder = cardsByID.values
            .filter { !seen.contains($0.id) }
            .sorted(by: BWRSlotOrder.stableCardCompare)
            .map(\.id)
        orderedIDs.append(contentsOf: remainder)

        return orderedIDs.enumerated().compactMap { index, cardID in
            guard let card = cardsByID[cardID],
                  let projected = projection.cardRectsByID[cardID] else {
                return nil
            }
            return BWRBoardOrderedCardPosition(
                card: card,
                host: projected.host,
                slotIndex: projected.slotIndex,
                coordinate: slotCoordinate(for: projected, metrics: projection.metrics),
                boardIndex: index
            )
        }
    }

    private static func orderedSlotPositions(
        document: BWRDocument,
        projection: BWRSlotBoardProjectionSnapshot
    ) -> [BWRBoardOrderedSlotPosition] {
        var positions: [BWRBoardOrderedSlotPosition] = []

        for frame in visibleGroupFrames(projection: projection) {
            let slotCount = frame.group.memberCardIDs.count
            let cursorSlotCount = max(slotCount + 1, 1)
            for slotIndex in 0..<cursorSlotCount {
                let reference = BWRBoardSlotReference(host: .group(frame.group.id), slotIndex: slotIndex)
                guard let rect = projection.slotRect(for: reference) else { continue }
                positions.append(
                    BWRBoardOrderedSlotPosition(
                        reference: reference,
                        rect: rect,
                        coordinate: slotCoordinate(for: rect, metrics: projection.metrics),
                        boardIndex: positions.count
                    )
                )
            }
        }

        for frame in visibleStripFrames(projection: projection) {
            let slotCount = frame.strip.cardIDs.count
            let cursorSlotCount = max(slotCount + 1, 1)
            for slotIndex in 0..<cursorSlotCount {
                let reference = BWRBoardSlotReference(host: .strip(frame.strip.id), slotIndex: slotIndex)
                guard let rect = projection.slotRect(for: reference) else { continue }
                positions.append(
                    BWRBoardOrderedSlotPosition(
                        reference: reference,
                        rect: rect,
                        coordinate: slotCoordinate(for: rect, metrics: projection.metrics),
                        boardIndex: positions.count
                    )
                )
            }
        }

        return positions
    }

    private static func visibleGroupFrames(projection: BWRSlotBoardProjectionSnapshot) -> [BWRProjectedGroupFrame] {
        projection.groupFrames.sorted { lhs, rhs in
            if lhs.resolvedOriginSlot.row != rhs.resolvedOriginSlot.row {
                return lhs.resolvedOriginSlot.row < rhs.resolvedOriginSlot.row
            }
            if lhs.resolvedOriginSlot.column != rhs.resolvedOriginSlot.column {
                return lhs.resolvedOriginSlot.column < rhs.resolvedOriginSlot.column
            }
            return lhs.group.id.uuidString < rhs.group.id.uuidString
        }
    }

    private static func visibleStripFrames(projection: BWRSlotBoardProjectionSnapshot) -> [BWRProjectedParkingStripFrame] {
        projection.stripFrames.sorted { lhs, rhs in
            if lhs.resolvedOriginSlot.row != rhs.resolvedOriginSlot.row {
                return lhs.resolvedOriginSlot.row < rhs.resolvedOriginSlot.row
            }
            if lhs.resolvedOriginSlot.column != rhs.resolvedOriginSlot.column {
                return lhs.resolvedOriginSlot.column < rhs.resolvedOriginSlot.column
            }
            return lhs.strip.id.uuidString < rhs.strip.id.uuidString
        }
    }

    private static func slotCoordinate(
        for projected: BWRProjectedCardRect,
        metrics: BWRSlotBoardMetrics
    ) -> BWRSlotCoordinate {
        BWRSlotCoordinate(
            column: max(0, Int((projected.slotRect.minX / metrics.slotWidth).rounded())),
            row: max(0, Int((projected.slotRect.minY / metrics.slotHeight).rounded()))
        )
    }

    private static func slotCoordinate(
        for rect: CGRect,
        metrics: BWRSlotBoardMetrics
    ) -> BWRSlotCoordinate {
        BWRSlotCoordinate(
            column: max(0, Int((rect.minX / metrics.slotWidth).rounded())),
            row: max(0, Int((rect.minY / metrics.slotHeight).rounded()))
        )
    }

    private static func traversalScore(
        for candidate: BWRBoardOrderedCardPosition,
        from anchor: BWRBoardOrderedCardPosition,
        direction: BWRBoardArrowDirection
    ) -> String {
        let rowDelta = abs(candidate.coordinate.row - anchor.coordinate.row)
        let columnDelta = abs(candidate.coordinate.column - anchor.coordinate.column)

        switch direction {
        case .left, .right:
            let sameRowPenalty = candidate.coordinate.row == anchor.coordinate.row ? 0 : 1
            return String(
                format: "%02d-%04d-%04d-%08d",
                sameRowPenalty,
                columnDelta,
                rowDelta,
                candidate.boardIndex
            )
        case .up, .down:
            let sameColumnPenalty = candidate.coordinate.column == anchor.coordinate.column ? 0 : 1
            return String(
                format: "%02d-%04d-%04d-%08d",
                sameColumnPenalty,
                rowDelta,
                columnDelta,
                candidate.boardIndex
            )
        }
    }

    private static func slotTraversalScore(
        for candidate: BWRBoardOrderedSlotPosition,
        from anchor: BWRBoardOrderedSlotPosition,
        direction: BWRBoardArrowDirection
    ) -> String {
        let rowDelta = abs(candidate.coordinate.row - anchor.coordinate.row)
        let columnDelta = abs(candidate.coordinate.column - anchor.coordinate.column)

        switch direction {
        case .left, .right:
            let sameRowPenalty = candidate.coordinate.row == anchor.coordinate.row ? 0 : 1
            return String(
                format: "%02d-%04d-%04d-%08d",
                sameRowPenalty,
                columnDelta,
                rowDelta,
                candidate.boardIndex
            )
        case .up, .down:
            let sameColumnPenalty = candidate.coordinate.column == anchor.coordinate.column ? 0 : 1
            return String(
                format: "%02d-%04d-%04d-%08d",
                sameColumnPenalty,
                rowDelta,
                columnDelta,
                candidate.boardIndex
            )
        }
    }
}
