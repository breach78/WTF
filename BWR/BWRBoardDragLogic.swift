import CoreGraphics
import Foundation

struct BoardSlotDelta: Equatable, Hashable {
    var rows: Int
    var columns: Int

    static let zero = BoardSlotDelta(rows: 0, columns: 0)

    var isZero: Bool {
        rows == 0 && columns == 0
    }
}

enum BoardSequenceAxis: Equatable {
    case horizontal
    case vertical
}

enum BoardSelectionPattern: Equatable {
    case single(headCardID: UUID)
    case sequence(axis: BoardSequenceAxis, headCardID: UUID, orderedCardIDs: [UUID])
    case cluster(headCardID: UUID, orderedCardIDs: [UUID])

    var headCardID: UUID {
        switch self {
        case .single(let headCardID):
            return headCardID
        case .sequence(_, let headCardID, _):
            return headCardID
        case .cluster(let headCardID, _):
            return headCardID
        }
    }

    var orderedCardIDs: [UUID] {
        switch self {
        case .single(let headCardID):
            return [headCardID]
        case .sequence(_, _, let orderedCardIDs):
            return orderedCardIDs
        case .cluster(_, let orderedCardIDs):
            return orderedCardIDs
        }
    }
}

struct BoardDragSession: Equatable {
    var selectedCardIDs: Set<UUID>
    var originSlots: [UUID: BoardSlot]
    var previewOffset: BoardSlotDelta
    var pattern: BoardSelectionPattern

    var previewSlots: [UUID: BoardSlot] {
        originSlots.mapValues { slot in
            slot.offsetBy(rows: previewOffset.rows, columns: previewOffset.columns)
        }
    }

    var previewSlotSet: Set<BoardSlot> {
        Set(previewSlots.values)
    }
}

enum BoardDragController {
    static func makeSession(
        project: BoardProject,
        interaction: BoardInteractionState,
        startingFrom cardID: UUID
    ) -> BoardDragSession {
        let selectedCardIDs = interaction.selectedCardIDs.contains(cardID)
            ? interaction.selectedCardIDs
            : [cardID]
        let orderedCardIDs = project.sortedCardIDs(selectedCardIDs)
        let originSlots = Dictionary(uniqueKeysWithValues: orderedCardIDs.compactMap { id in
            project.presentedCard(id: id).map { (id, $0.slot) }
        })
        let headCardID = project.selectedCardID(for: interaction).flatMap { selectedID in
            selectedCardIDs.contains(selectedID) ? selectedID : nil
        } ?? cardID

        return BoardDragSession(
            selectedCardIDs: selectedCardIDs,
            originSlots: originSlots,
            previewOffset: .zero,
            pattern: classify(project: project, headCardID: headCardID, orderedCardIDs: orderedCardIDs)
        )
    }

    static func slotDelta(
        translation: CGSize,
        slotStep: CGSize
    ) -> BoardSlotDelta {
        let columns = Int((translation.width / slotStep.width).rounded())
        let rows = Int((translation.height / slotStep.height).rounded())
        return BoardSlotDelta(rows: rows, columns: columns)
    }

    static func clampedPreviewOffset(
        _ proposed: BoardSlotDelta,
        originSlots: [UUID: BoardSlot]
    ) -> BoardSlotDelta {
        let minimumRow = originSlots.values.map(\.row).min() ?? 0
        let minimumColumn = originSlots.values.map(\.column).min() ?? 0
        return BoardSlotDelta(
            rows: max(proposed.rows, -minimumRow),
            columns: max(proposed.columns, -minimumColumn)
        )
    }

    static func classify(
        project: BoardProject,
        headCardID: UUID,
        orderedCardIDs: [UUID]
    ) -> BoardSelectionPattern {
        guard !orderedCardIDs.isEmpty else {
            return .single(headCardID: headCardID)
        }
        guard orderedCardIDs.count > 1 else {
            return .single(headCardID: headCardID)
        }

        let slots = orderedCardIDs.compactMap { project.presentedCard(id: $0)?.slot }
        let uniqueRows = Set(slots.map(\.row))
        let uniqueColumns = Set(slots.map(\.column))

        if uniqueRows.count == 1 {
            let ordered = orderedCardIDs.sorted { lhs, rhs in
                guard
                    let left = project.presentedCard(id: lhs)?.slot,
                    let right = project.presentedCard(id: rhs)?.slot
                else {
                    return lhs.uuidString < rhs.uuidString
                }
                return left.column < right.column
            }
            let columns = ordered.compactMap { project.presentedCard(id: $0)?.slot.column }
            let contiguous = zip(columns, columns.dropFirst()).allSatisfy { $1 - $0 == 1 }
            if contiguous {
                return .sequence(
                    axis: .horizontal,
                    headCardID: ordered.first ?? headCardID,
                    orderedCardIDs: ordered
                )
            }
        }

        if uniqueColumns.count == 1 {
            let ordered = orderedCardIDs.sorted { lhs, rhs in
                guard
                    let left = project.presentedCard(id: lhs)?.slot,
                    let right = project.presentedCard(id: rhs)?.slot
                else {
                    return lhs.uuidString < rhs.uuidString
                }
                return left.row < right.row
            }
            let rows = ordered.compactMap { project.presentedCard(id: $0)?.slot.row }
            let contiguous = zip(rows, rows.dropFirst()).allSatisfy { $1 - $0 == 1 }
            if contiguous {
                return .sequence(
                    axis: .vertical,
                    headCardID: ordered.first ?? headCardID,
                    orderedCardIDs: ordered
                )
            }
        }

        return .cluster(headCardID: headCardID, orderedCardIDs: orderedCardIDs)
    }

    @discardableResult
    static func apply(
        project: inout BoardProject,
        interaction: inout BoardInteractionState,
        session: BoardDragSession
    ) -> Bool {
        guard !session.previewOffset.isZero else {
            return false
        }

        switch session.pattern {
        case .single(let headCardID):
            guard let destination = session.previewSlots[headCardID] else {
                return false
            }
            project.moveCard(id: headCardID, to: destination)
            interaction.selectCard(headCardID, at: destination)
            interaction.keyboardCursorSlot = destination
            return true
        case .cluster(let headCardID, let orderedCardIDs):
            return applyCluster(
                project: &project,
                interaction: &interaction,
                headCardID: headCardID,
                orderedCardIDs: orderedCardIDs,
                previewSlots: session.previewSlots
            )
        case .sequence(let axis, let headCardID, let orderedCardIDs):
            return applySequence(
                project: &project,
                interaction: &interaction,
                axis: axis,
                headCardID: headCardID,
                orderedCardIDs: orderedCardIDs,
                previewSlots: session.previewSlots,
                delta: session.previewOffset
            )
        }
    }

    static func previewReflowSlots(
        project: BoardProject,
        session: BoardDragSession
    ) -> [UUID: BoardSlot] {
        switch session.pattern {
        case .single(let headCardID):
            guard let destination = session.previewSlots[headCardID] else {
                return [:]
            }
            return previewRowSequenceSlots(
                project: project,
                movingCardIDs: [headCardID],
                destination: destination
            )
        case .sequence(let axis, _, let orderedCardIDs):
            guard
                axis == .horizontal,
                let leftmostCardID = orderedCardIDs.first,
                let destination = session.previewSlots[leftmostCardID]
            else {
                return [:]
            }
            return previewRowSequenceSlots(
                project: project,
                movingCardIDs: orderedCardIDs,
                destination: destination
            )
        case .cluster:
            return [:]
        }
    }

    private static func applyCluster(
        project: inout BoardProject,
        interaction: inout BoardInteractionState,
        headCardID: UUID,
        orderedCardIDs: [UUID],
        previewSlots: [UUID: BoardSlot]
    ) -> Bool {
        let occupiedByOthers = Set(
            project.liveCards
                .filter { !orderedCardIDs.contains($0.id) }
                .map(\.slot)
        )
        let destinations = orderedCardIDs.compactMap { previewSlots[$0] }
        guard destinations.allSatisfy({ !occupiedByOthers.contains($0) }) else {
            return false
        }

        let timestamp = BWRTimestamp.now()
        for cardID in orderedCardIDs {
            guard let destination = previewSlots[cardID] else {
                continue
            }
            project.setCardSlot(id: cardID, to: destination, timestamp: timestamp)
        }
        project.sortCards()

        let anchor = previewSlots[headCardID] ?? orderedCardIDs.first.flatMap { previewSlots[$0] }
        interaction.selectCards(Set(orderedCardIDs), anchorSlot: anchor)
        interaction.keyboardCursorSlot = anchor
        return true
    }

    private static func applySequence(
        project: inout BoardProject,
        interaction: inout BoardInteractionState,
        axis: BoardSequenceAxis,
        headCardID: UUID,
        orderedCardIDs: [UUID],
        previewSlots: [UUID: BoardSlot],
        delta: BoardSlotDelta
    ) -> Bool {
        if axis == .horizontal {
            guard
                let leftmostCardID = orderedCardIDs.first,
                let destination = previewSlots[leftmostCardID]
            else {
                return false
            }

            let placements = project.moveHorizontalSequence(
                cardIDs: orderedCardIDs,
                to: destination
            )
            guard let anchorSlot = placements?[leftmostCardID] else {
                return false
            }

            interaction.selectCards(Set(orderedCardIDs), anchorSlot: anchorSlot)
            interaction.keyboardCursorSlot = anchorSlot
            _ = headCardID
            _ = delta
            return true
        }

        let destinations = orderedCardIDs.compactMap { previewSlots[$0] }
        guard !destinations.isEmpty else {
            return false
        }

        let sourceSlots = orderedCardIDs.compactMap { project.presentedCard(id: $0)?.slot }
        let fixedCoordinate: Int
        let headIndex: Int
        let direction: Int

        switch axis {
        case .horizontal:
            guard Set(destinations.map(\.row)).count == 1 else {
                return applyCluster(
                    project: &project,
                    interaction: &interaction,
                    headCardID: headCardID,
                    orderedCardIDs: orderedCardIDs,
                    previewSlots: previewSlots
                )
            }
            fixedCoordinate = destinations[0].row
            headIndex = previewSlots[headCardID]?.column ?? (destinations.map(\.column).min() ?? 0)
            direction = delta.columns >= 0 ? 1 : -1
        case .vertical:
            guard Set(destinations.map(\.column)).count == 1 else {
                return applyCluster(
                    project: &project,
                    interaction: &interaction,
                    headCardID: headCardID,
                    orderedCardIDs: orderedCardIDs,
                    previewSlots: previewSlots
                )
            }
            fixedCoordinate = destinations[0].column
            headIndex = previewSlots[headCardID]?.row ?? (destinations.map(\.row).min() ?? 0)
            direction = delta.rows >= 0 ? 1 : -1
        }

        let selectedSet = Set(orderedCardIDs)
        let timestamp = BWRTimestamp.now()
        var occupancy = Dictionary(uniqueKeysWithValues: project.liveCards.compactMap { card in
            selectedSet.contains(card.id) ? nil : (card.slot, card.id)
        })

        let placementOrder = direction >= 0 ? Array(orderedCardIDs.reversed()) : orderedCardIDs
        for cardID in placementOrder {
            guard let destination = previewSlots[cardID] else {
                continue
            }
            shiftCollisionChain(
                at: destination,
                axis: axis,
                direction: direction,
                occupancy: &occupancy,
                project: &project,
                timestamp: timestamp
            )
            project.setCardSlot(id: cardID, to: destination, timestamp: timestamp)
            occupancy[destination] = cardID
        }

        project.sortCards()
        let anchorSlot = axis == .horizontal
            ? BoardSlot(row: fixedCoordinate, column: headIndex)
            : BoardSlot(row: headIndex, column: fixedCoordinate)
        interaction.selectCards(selectedSet, anchorSlot: anchorSlot)
        interaction.keyboardCursorSlot = anchorSlot
        _ = sourceSlots
        return true
    }

    private static func shiftCollisionChain(
        at slot: BoardSlot,
        axis: BoardSequenceAxis,
        direction: Int,
        occupancy: inout [BoardSlot: UUID],
        project: inout BoardProject,
        timestamp: Date
    ) {
        guard let otherCardID = occupancy[slot] else {
            return
        }

        let nextSlot: BoardSlot
        switch axis {
        case .horizontal:
            nextSlot = slot.offsetBy(columns: direction)
        case .vertical:
            nextSlot = slot.offsetBy(rows: direction)
        }

        shiftCollisionChain(
            at: nextSlot,
            axis: axis,
            direction: direction,
            occupancy: &occupancy,
            project: &project,
            timestamp: timestamp
        )
        project.setCardSlot(id: otherCardID, to: nextSlot, timestamp: timestamp)
        occupancy.removeValue(forKey: slot)
        occupancy[nextSlot] = otherCardID
    }

    private static func previewRowSequenceSlots(
        project: BoardProject,
        movingCardIDs: [UUID],
        destination: BoardSlot
    ) -> [UUID: BoardSlot] {
        var previewProject = project
        guard previewProject.moveHorizontalSequence(cardIDs: movingCardIDs, to: destination) != nil else {
            return [:]
        }

        let movingCardSet = Set(movingCardIDs)
        let originalSlots = Dictionary(uniqueKeysWithValues: project.liveCards.map { ($0.id, $0.slot) })
        return Dictionary(uniqueKeysWithValues: previewProject.liveCards.compactMap { card in
            guard
                !movingCardSet.contains(card.id),
                let originalSlot = originalSlots[card.id],
                originalSlot != card.slot
            else {
                return nil
            }

            return (card.id, card.slot)
        })
    }
}

enum BoardMarqueeController {
    static func selection(
        project: BoardProject,
        layout: BoardCanvasLayout,
        rect: CGRect
    ) -> BoardSelection {
        let normalized = rect.standardized
        guard normalized.width > 0 || normalized.height > 0 else {
            return .none
        }

        let cardIDs = Set(
            project.liveCards
                .filter { layout.rect(for: $0.slot).intersects(normalized) }
                .map(\.id)
        )
        if !cardIDs.isEmpty {
            return .cards(cardIDs)
        }

        return .none
    }
}
