import CoreGraphics
import Foundation
import SwiftUI

struct BoardCanvasLayout {
    let visibleBounds: BoardVisibleBounds
    let slotSize: CGSize
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let padding: EdgeInsets

    func rect(for slot: BoardSlot) -> CGRect {
        let x = padding.leading + CGFloat(slot.column - visibleBounds.minColumn) * (slotSize.width + horizontalSpacing)
        let y = padding.top + CGFloat(slot.row - visibleBounds.minRow) * (slotSize.height + verticalSpacing)
        return CGRect(x: x, y: y, width: slotSize.width, height: slotSize.height)
    }

    func slot(at point: CGPoint) -> BoardSlot? {
        let contentX = point.x - padding.leading
        let contentY = point.y - padding.top
        guard contentX >= 0, contentY >= 0 else {
            return nil
        }

        let stepX = slotSize.width + horizontalSpacing
        let stepY = slotSize.height + verticalSpacing
        let columnOffset = Int(floor(contentX / stepX))
        let rowOffset = Int(floor(contentY / stepY))
        guard visibleBounds.columns.indices.contains(columnOffset), visibleBounds.rows.indices.contains(rowOffset) else {
            return nil
        }

        let localX = contentX - CGFloat(columnOffset) * stepX
        let localY = contentY - CGFloat(rowOffset) * stepY
        guard localX <= slotSize.width, localY <= slotSize.height else {
            return nil
        }

        return BoardSlot(
            row: visibleBounds.minRow + rowOffset,
            column: visibleBounds.minColumn + columnOffset
        )
    }

    func nearestSlot(to point: CGPoint) -> BoardSlot? {
        let contentX = point.x - padding.leading
        let contentY = point.y - padding.top
        guard visibleBounds.columnCount > 0, visibleBounds.rowCount > 0 else {
            return nil
        }

        let stepX = slotSize.width + horizontalSpacing
        let stepY = slotSize.height + verticalSpacing
        let maxX = CGFloat(max(visibleBounds.columnCount - 1, 0)) * stepX
        let maxY = CGFloat(max(visibleBounds.rowCount - 1, 0)) * stepY
        let clampedX = min(max(contentX, 0), maxX)
        let clampedY = min(max(contentY, 0), maxY)

        let columnOffset = min(max(Int(floor(clampedX / stepX)), 0), visibleBounds.columnCount - 1)
        let rowOffset = min(max(Int(floor(clampedY / stepY)), 0), visibleBounds.rowCount - 1)
        return BoardSlot(
            row: visibleBounds.minRow + rowOffset,
            column: visibleBounds.minColumn + columnOffset
        )
    }
}
