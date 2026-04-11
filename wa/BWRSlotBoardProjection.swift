import Foundation
import CoreGraphics

nonisolated enum BWRProjectedPlaceholderKind: Equatable, Sendable {
    case hoverSlot(BWRSlotHost)
    case dragDestination(BWRSlotHost?)
    case groupBlock(UUID)
}

nonisolated struct BWRProjectedPlaceholder: Equatable, Sendable, Identifiable {
    var id: String
    var kind: BWRProjectedPlaceholderKind
    var rect: CGRect
}

nonisolated struct BWRProjectedCardRect: Equatable, Sendable {
    var cardID: UUID
    var host: BWRSlotHost
    var slotIndex: Int
    var slotRect: CGRect
    var cardRect: CGRect
}

nonisolated struct BWRProjectedGroupFrame: Equatable, Sendable, Identifiable {
    var group: BWRGroup
    var resolvedOriginSlot: BWRSlotCoordinate
    var footprint: BWRSlotFootprint
    var rect: CGRect
    var slotRects: [CGRect]

    var id: UUID { group.id }
}

nonisolated struct BWRProjectedParkingStripFrame: Equatable, Sendable, Identifiable {
    var strip: BWRParkingStrip
    var resolvedOriginSlot: BWRSlotCoordinate
    var footprint: BWRSlotFootprint
    var rect: CGRect
    var slotRects: [CGRect]

    var id: UUID { strip.id }
}

nonisolated struct BWRSlotBoardProjectionSnapshot: Equatable, Sendable {
    var metrics: BWRSlotBoardMetrics
    var groupFrames: [BWRProjectedGroupFrame]
    var stripFrames: [BWRProjectedParkingStripFrame]
    var cardRectsByID: [UUID: BWRProjectedCardRect]
    var contentSize: CGSize

    func cardRect(for cardID: UUID) -> CGRect? {
        cardRectsByID[cardID]?.cardRect
    }

    func slotRect(for cardID: UUID) -> CGRect? {
        cardRectsByID[cardID]?.slotRect
    }

    func slotCount(for host: BWRSlotHost) -> Int {
        switch host {
        case let .group(groupID):
            return groupFrames.first(where: { $0.group.id == groupID })?.group.memberCardIDs.count ?? 0
        case let .strip(stripID):
            return stripFrames.first(where: { $0.strip.id == stripID })?.strip.cardIDs.count ?? 0
        }
    }

    func cardID(at reference: BWRBoardSlotReference) -> UUID? {
        switch reference.host {
        case let .group(groupID):
            guard let frame = groupFrames.first(where: { $0.group.id == groupID }),
                  reference.slotIndex < frame.group.memberCardIDs.count else {
                return nil
            }
            return frame.group.memberCardIDs[reference.slotIndex]
        case let .strip(stripID):
            guard let frame = stripFrames.first(where: { $0.strip.id == stripID }),
                  reference.slotIndex < frame.strip.cardIDs.count else {
                return nil
            }
            return frame.strip.cardIDs[reference.slotIndex]
        }
    }

    func placeholderRect(for host: BWRSlotHost, insertionIndex: Int) -> CGRect? {
        switch host {
        case let .group(groupID):
            guard let frame = groupFrames.first(where: { $0.group.id == groupID }) else { return nil }
            let slotRect = projectedSlotRect(
                origin: frame.resolvedOriginSlot,
                hostSlotIndex: insertionIndex,
                slotCount: max(frame.group.memberCardIDs.count + 1, 1),
                metrics: metrics
            )
            return BWRSlotBoardGeometry.placeholderRect(in: slotRect, metrics: metrics)
        case let .strip(stripID):
            guard let frame = stripFrames.first(where: { $0.strip.id == stripID }) else { return nil }
            let origin = frame.resolvedOriginSlot
            let slotRect = CGRect(
                x: CGFloat(origin.column + max(0, insertionIndex)) * metrics.slotWidth,
                y: CGFloat(origin.row) * metrics.slotHeight,
                width: metrics.slotWidth,
                height: metrics.slotHeight
            )
            return BWRSlotBoardGeometry.placeholderRect(in: slotRect, metrics: metrics)
        }
    }

    func placeholderRects(
        for host: BWRSlotHost,
        insertionIndex: Int,
        blockLength: Int,
        residentCardCount: Int
    ) -> [CGRect] {
        guard blockLength > 0 else { return [] }
        let finalSlotCount = max(residentCardCount + blockLength, 1)

        switch host {
        case let .group(groupID):
            guard let frame = groupFrames.first(where: { $0.group.id == groupID }) else { return [] }
            return (0..<blockLength).map { offset in
                let slotRect = projectedSlotRect(
                    origin: frame.resolvedOriginSlot,
                    hostSlotIndex: insertionIndex + offset,
                    slotCount: finalSlotCount,
                    metrics: metrics
                )
                return BWRSlotBoardGeometry.placeholderRect(in: slotRect, metrics: metrics)
            }
        case let .strip(stripID):
            guard let frame = stripFrames.first(where: { $0.strip.id == stripID }) else { return [] }
            return (0..<blockLength).map { offset in
                let slotRect = CGRect(
                    x: CGFloat(frame.resolvedOriginSlot.column + insertionIndex + offset) * metrics.slotWidth,
                    y: CGFloat(frame.resolvedOriginSlot.row) * metrics.slotHeight,
                    width: metrics.slotWidth,
                    height: metrics.slotHeight
                )
                return BWRSlotBoardGeometry.placeholderRect(in: slotRect, metrics: metrics)
            }
        }
    }

    func groupBlockPlaceholderRect(groupID: UUID, candidateOriginSlot: BWRSlotCoordinate) -> CGRect? {
        guard let frame = groupFrames.first(where: { $0.group.id == groupID }) else { return nil }
        return frameRect(
            origin: candidateOriginSlot,
            footprint: frame.footprint,
            metrics: metrics
        )
    }

    private func projectedSlotRect(
        origin: BWRSlotCoordinate,
        hostSlotIndex: Int,
        slotCount: Int,
        metrics: BWRSlotBoardMetrics
    ) -> CGRect {
        let local = BWRSlotBoardGeometry.localSlotCoordinate(
            for: hostSlotIndex,
            slotCount: slotCount,
            metrics: metrics
        )
        return BWRSlotBoardGeometry.slotRect(origin: origin, local: local, metrics: metrics)
    }

    private func frameRect(
        origin: BWRSlotCoordinate,
        footprint: BWRSlotFootprint,
        metrics: BWRSlotBoardMetrics
    ) -> CGRect {
        let point = BWRSlotBoardGeometry.point(for: origin, metrics: metrics)
        return CGRect(
            x: point.x,
            y: point.y,
            width: CGFloat(footprint.columns) * metrics.slotWidth,
            height: CGFloat(footprint.rows) * metrics.slotHeight
        )
    }
}

nonisolated enum BWRSlotBoardProjection {
    static func project(
        document: BWRDocument,
        expandedCardIDs: Set<UUID> = [],
        metrics: BWRSlotBoardMetrics = .init()
    ) -> BWRSlotBoardProjectionSnapshot {
        _ = expandedCardIDs
        let cardsByID = Dictionary(uniqueKeysWithValues: document.cards.filter { !$0.isArchived }.map { ($0.id, $0) })
        var occupancy = BWROccupancyMap()
        var groupFrames: [BWRProjectedGroupFrame] = []
        var stripFrames: [BWRProjectedParkingStripFrame] = []
        var cardRectsByID: [UUID: BWRProjectedCardRect] = [:]

        for group in BWRSlotOrder.orderedLiveGroups(in: document) {
            let slotCount = max(group.memberCardIDs.count, 1)
            let footprint = BWRSlotBoardGeometry.footprint(slotCount: slotCount, metrics: metrics)
            let preferredOrigin = group.originSlot ?? BWRSlotCoordinate(column: 0, row: 0)
            let resolvedOrigin = BWRSlotBoardGeometry.scanForFreeOrigin(
                start: preferredOrigin,
                footprint: footprint,
                occupied: occupancy,
                metrics: metrics
            )

            let slotRects = projectedSlotRects(
                origin: resolvedOrigin,
                slotCount: slotCount,
                metrics: metrics
            )
            let rect = frameRect(
                origin: resolvedOrigin,
                footprint: footprint,
                metrics: metrics
            )
            groupFrames.append(
                BWRProjectedGroupFrame(
                    group: group,
                    resolvedOriginSlot: resolvedOrigin,
                    footprint: footprint,
                    rect: rect,
                    slotRects: slotRects
                )
            )
            occupancy.occupy(origin: resolvedOrigin, footprint: footprint)

            for (slotIndex, cardID) in group.memberCardIDs.enumerated() {
                guard cardsByID[cardID] != nil else { continue }
                let slotRect = slotRects[slotIndex]
                let cardRect = BWRSlotBoardGeometry.cardRect(
                    in: slotRect,
                    inlineExpanded: false,
                    metrics: metrics
                )
                cardRectsByID[cardID] = BWRProjectedCardRect(
                    cardID: cardID,
                    host: .group(group.id),
                    slotIndex: slotIndex,
                    slotRect: slotRect,
                    cardRect: cardRect
                )
            }
        }

        for strip in BWRSlotOrder.orderedLiveStrips(in: document) {
            let slotCount = max(strip.cardIDs.count, 1)
            let resolvedOrigin = BWRSlotBoardGeometry.resolveParkingStripOrigin(
                preferredRow: strip.row,
                anchorColumn: strip.anchorColumn,
                slotCount: slotCount,
                occupied: occupancy,
                metrics: metrics
            )
            let footprint = BWRSlotFootprint(columns: slotCount, rows: 1)
            let slotRects = (0..<slotCount).map { slotIndex in
                CGRect(
                    x: CGFloat(resolvedOrigin.column + slotIndex) * metrics.slotWidth,
                    y: CGFloat(resolvedOrigin.row) * metrics.slotHeight,
                    width: metrics.slotWidth,
                    height: metrics.slotHeight
                )
            }
            let rect = frameRect(
                origin: resolvedOrigin,
                footprint: footprint,
                metrics: metrics
            )
            stripFrames.append(
                BWRProjectedParkingStripFrame(
                    strip: strip,
                    resolvedOriginSlot: resolvedOrigin,
                    footprint: footprint,
                    rect: rect,
                    slotRects: slotRects
                )
            )
            occupancy.occupy(origin: resolvedOrigin, footprint: footprint)

            for (slotIndex, cardID) in strip.cardIDs.enumerated() {
                guard cardsByID[cardID] != nil else { continue }
                let slotRect = slotRects[slotIndex]
                let cardRect = BWRSlotBoardGeometry.cardRect(
                    in: slotRect,
                    inlineExpanded: false,
                    metrics: metrics
                )
                cardRectsByID[cardID] = BWRProjectedCardRect(
                    cardID: cardID,
                    host: .strip(strip.id),
                    slotIndex: slotIndex,
                    slotRect: slotRect,
                    cardRect: cardRect
                )
            }
        }

        let contentSize = projectedContentSize(
            groupFrames: groupFrames,
            stripFrames: stripFrames,
            cardRectsByID: cardRectsByID,
            metrics: metrics
        )

        return BWRSlotBoardProjectionSnapshot(
            metrics: metrics,
            groupFrames: groupFrames,
            stripFrames: stripFrames,
            cardRectsByID: cardRectsByID,
            contentSize: contentSize
        )
    }

    private static func projectedSlotRects(
        origin: BWRSlotCoordinate,
        slotCount: Int,
        metrics: BWRSlotBoardMetrics
    ) -> [CGRect] {
        (0..<slotCount).map { slotIndex in
            let local = BWRSlotBoardGeometry.localSlotCoordinate(
                for: slotIndex,
                slotCount: slotCount,
                metrics: metrics
            )
            return BWRSlotBoardGeometry.slotRect(origin: origin, local: local, metrics: metrics)
        }
    }

    private static func frameRect(
        origin: BWRSlotCoordinate,
        footprint: BWRSlotFootprint,
        metrics: BWRSlotBoardMetrics
    ) -> CGRect {
        let point = BWRSlotBoardGeometry.point(for: origin, metrics: metrics)
        return CGRect(
            x: point.x,
            y: point.y,
            width: CGFloat(footprint.columns) * metrics.slotWidth,
            height: CGFloat(footprint.rows) * metrics.slotHeight
        )
    }

    private static func projectedContentSize(
        groupFrames: [BWRProjectedGroupFrame],
        stripFrames: [BWRProjectedParkingStripFrame],
        cardRectsByID: [UUID: BWRProjectedCardRect],
        metrics: BWRSlotBoardMetrics
    ) -> CGSize {
        let maxGroupX = groupFrames.map { $0.rect.maxX }.max() ?? 0
        let maxGroupY = groupFrames.map { $0.rect.maxY }.max() ?? 0
        let maxStripX = stripFrames.map { $0.rect.maxX }.max() ?? 0
        let maxStripY = stripFrames.map { $0.rect.maxY }.max() ?? 0
        let maxCardX = cardRectsByID.values.map { $0.cardRect.maxX }.max() ?? 0
        let maxCardY = cardRectsByID.values.map { $0.cardRect.maxY }.max() ?? 0

        return CGSize(
            width: max(
                metrics.minimumBoardSize.width,
                Swift.max(maxGroupX, Swift.max(maxStripX, maxCardX)) + metrics.boardPadding.width
            ),
            height: max(
                metrics.minimumBoardSize.height,
                Swift.max(maxGroupY, Swift.max(maxStripY, maxCardY)) + metrics.boardPadding.height
            )
        )
    }
}
