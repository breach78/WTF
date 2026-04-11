import Foundation
import CoreGraphics

nonisolated struct BWRSlotBoardMetrics: Equatable, Sendable {
    var slotWidth: CGFloat = 240
    var slotHeight: CGFloat = 190
    var cardSize: CGSize = CGSize(width: 220, height: 158)
    var inlineCardSize: CGSize = CGSize(width: 220, height: 158)
    var maxVisualColumns: Int = 4
    var boardPadding: CGSize = CGSize(width: 360, height: 280)
    var cardInsetX: CGFloat = 10
    var cardInsetY: CGFloat = 16
    var placeholderInset: CGFloat = 8
    var scanColumnLimit: Int = 32

    var minimumBoardSize: CGSize {
        CGSize(width: 1800, height: 1200)
    }
}

nonisolated struct BWRSlotFootprint: Equatable, Hashable, Sendable {
    var columns: Int
    var rows: Int

    init(columns: Int, rows: Int) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
    }
}

nonisolated struct BWROccupancyMap: Equatable, Sendable {
    private(set) var occupiedSlots: Set<BWRSlotCoordinate> = []

    mutating func occupy(origin: BWRSlotCoordinate, footprint: BWRSlotFootprint) {
        for rowOffset in 0..<footprint.rows {
            for columnOffset in 0..<footprint.columns {
                occupiedSlots.insert(
                    BWRSlotCoordinate(
                        column: origin.column + columnOffset,
                        row: origin.row + rowOffset
                    )
                )
            }
        }
    }

    func intersects(origin: BWRSlotCoordinate, footprint: BWRSlotFootprint) -> Bool {
        for rowOffset in 0..<footprint.rows {
            for columnOffset in 0..<footprint.columns {
                let candidate = BWRSlotCoordinate(
                    column: origin.column + columnOffset,
                    row: origin.row + rowOffset
                )
                if occupiedSlots.contains(candidate) {
                    return true
                }
            }
        }
        return false
    }
}

nonisolated enum BWRSlotBoardGeometry {
    static let `default` = BWRSlotBoardMetrics()

    static func point(
        for slot: BWRSlotCoordinate,
        metrics: BWRSlotBoardMetrics = .init()
    ) -> CGPoint {
        CGPoint(
            x: CGFloat(slot.column) * metrics.slotWidth,
            y: CGFloat(slot.row) * metrics.slotHeight
        )
    }

    static func footprint(
        slotCount: Int,
        metrics: BWRSlotBoardMetrics = .init()
    ) -> BWRSlotFootprint {
        let resolvedCount = max(slotCount, 1)
        let columns = min(metrics.maxVisualColumns, resolvedCount)
        let rows = Int(ceil(Double(resolvedCount) / Double(columns)))
        return BWRSlotFootprint(columns: columns, rows: rows)
    }

    static func localSlotCoordinate(
        for slotIndex: Int,
        slotCount: Int,
        metrics: BWRSlotBoardMetrics = .init()
    ) -> BWRSlotCoordinate {
        let footprint = footprint(slotCount: slotCount, metrics: metrics)
        return BWRSlotCoordinate(
            column: max(0, slotIndex) % footprint.columns,
            row: max(0, slotIndex) / footprint.columns
        )
    }

    static func scanForFreeOrigin(
        start: BWRSlotCoordinate,
        footprint: BWRSlotFootprint,
        occupied: BWROccupancyMap,
        metrics: BWRSlotBoardMetrics = .init()
    ) -> BWRSlotCoordinate {
        let minimumRow = max(0, start.row)
        let minimumColumn = max(0, start.column)

        for row in minimumRow..<(minimumRow + 256) {
            let startColumn = row == minimumRow ? minimumColumn : 0
            let endColumn = startColumn + metrics.scanColumnLimit
            for column in startColumn..<endColumn {
                let candidate = BWRSlotCoordinate(column: column, row: row)
                if !occupied.intersects(origin: candidate, footprint: footprint) {
                    return candidate
                }
            }
        }

        return BWRSlotCoordinate(column: minimumColumn, row: minimumRow)
    }

    static func resolveParkingStripOrigin(
        preferredRow: Int,
        anchorColumn: Int,
        slotCount: Int,
        occupied: BWROccupancyMap,
        metrics: BWRSlotBoardMetrics = .init()
    ) -> BWRSlotCoordinate {
        let footprint = BWRSlotFootprint(columns: max(slotCount, 1), rows: 1)
        let column = max(0, anchorColumn)
        var row = max(0, preferredRow)

        while occupied.intersects(
            origin: BWRSlotCoordinate(column: column, row: row),
            footprint: footprint
        ) {
            row += 1
        }

        return BWRSlotCoordinate(column: column, row: row)
    }

    static func slotRect(
        origin: BWRSlotCoordinate,
        local: BWRSlotCoordinate,
        metrics: BWRSlotBoardMetrics = .init()
    ) -> CGRect {
        let absolute = BWRSlotCoordinate(
            column: origin.column + local.column,
            row: origin.row + local.row
        )
        let point = point(for: absolute, metrics: metrics)
        return CGRect(
            x: point.x,
            y: point.y,
            width: metrics.slotWidth,
            height: metrics.slotHeight
        )
    }

    static func cardRect(
        in slotRect: CGRect,
        inlineExpanded: Bool,
        metrics: BWRSlotBoardMetrics = .init()
    ) -> CGRect {
        _ = inlineExpanded
        let cardSize = metrics.cardSize
        return CGRect(
            x: slotRect.minX + ((metrics.slotWidth - cardSize.width) * 0.5),
            y: slotRect.minY + metrics.cardInsetY,
            width: cardSize.width,
            height: cardSize.height
        )
    }

    static func inlineEditorRect(
        in cardRect: CGRect,
        footerHeight: CGFloat,
        horizontalInset: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat,
        footerGap: CGFloat
    ) -> CGRect {
        let minX = cardRect.minX + horizontalInset
        let width = max(0, cardRect.width - horizontalInset * 2)
        let height = max(
            44,
            cardRect.height - topInset - bottomInset - footerHeight - footerGap
        )
        return CGRect(
            x: minX,
            y: cardRect.minY + topInset,
            width: width,
            height: height
        )
    }

    static func inlineEditorFooterRect(
        in cardRect: CGRect,
        footerHeight: CGFloat,
        horizontalInset: CGFloat,
        bottomInset: CGFloat
    ) -> CGRect {
        let minX = cardRect.minX + horizontalInset
        let width = max(0, cardRect.width - horizontalInset * 2)
        return CGRect(
            x: minX,
            y: max(cardRect.minY, cardRect.maxY - bottomInset - footerHeight),
            width: width,
            height: footerHeight
        )
    }

    static func placeholderRect(
        in slotRect: CGRect,
        metrics: BWRSlotBoardMetrics = .init()
    ) -> CGRect {
        slotRect.insetBy(dx: metrics.placeholderInset, dy: metrics.placeholderInset)
    }

    static func contiguousOverlayRects(
        from rects: [CGRect],
        gapTolerance: CGFloat,
        axisTolerance: CGFloat = 0.5
    ) -> [CGRect] {
        guard rects.count > 1 else { return rects }

        var merged = rects.sorted { lhs, rhs in
            if abs(lhs.minY - rhs.minY) > axisTolerance {
                return lhs.minY < rhs.minY
            }
            if abs(lhs.minX - rhs.minX) > axisTolerance {
                return lhs.minX < rhs.minX
            }
            if lhs.width != rhs.width {
                return lhs.width < rhs.width
            }
            return lhs.height < rhs.height
        }

        var didMerge = true
        while didMerge {
            didMerge = false

            outerLoop: for leftIndex in merged.indices {
                for rightIndex in merged.indices where rightIndex > leftIndex {
                    guard let union = mergedOverlayRectPair(
                        merged[leftIndex],
                        merged[rightIndex],
                        gapTolerance: gapTolerance,
                        axisTolerance: axisTolerance
                    ) else {
                        continue
                    }
                    merged[leftIndex] = union
                    merged.remove(at: rightIndex)
                    didMerge = true
                    break outerLoop
                }
            }
        }

        return merged.sorted { lhs, rhs in
            if abs(lhs.minY - rhs.minY) > axisTolerance {
                return lhs.minY < rhs.minY
            }
            return lhs.minX < rhs.minX
        }
    }

    private static func mergedOverlayRectPair(
        _ lhs: CGRect,
        _ rhs: CGRect,
        gapTolerance: CGFloat,
        axisTolerance: CGFloat
    ) -> CGRect? {
        let horizontalGap = max(rhs.minX - lhs.maxX, lhs.minX - rhs.maxX)
        let verticalGap = max(rhs.minY - lhs.maxY, lhs.minY - rhs.maxY)

        let sameRow = abs(lhs.minY - rhs.minY) <= axisTolerance &&
            abs(lhs.height - rhs.height) <= axisTolerance
        if sameRow && horizontalGap <= gapTolerance + axisTolerance {
            return lhs.union(rhs)
        }

        let sameColumn = abs(lhs.minX - rhs.minX) <= axisTolerance &&
            abs(lhs.width - rhs.width) <= axisTolerance
        if sameColumn && verticalGap <= gapTolerance + axisTolerance {
            return lhs.union(rhs)
        }

        return nil
    }
}
