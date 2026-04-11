import SwiftUI

enum BWRPhase5Harness {
    @discardableResult
    static func runAll() -> Bool {
        let results = [
            multiSelectAndSequenceHeadCheck(),
            marqueeSelectionCheck(),
            sequenceSmartDragCheck(),
            clusterDragCheck()
        ]

        for result in results {
            let marker = result.success ? "PASS" : "FAIL"
            print("[BWR Phase 5] \(marker) \(result.title) - \(result.detail)")
        }

        return results.allSatisfy(\.success)
    }

    private static func multiSelectAndSequenceHeadCheck() -> Phase5HarnessResult {
        let ids = SequenceFixture.ids
        let project = sequenceProject()
        var interaction = BoardInteractionState()

        interaction.selectCard(ids.a, at: BoardSlot(row: 0, column: 0))
        interaction.toggleCard(ids.c, at: BoardSlot(row: 0, column: 2))
        let togglePass =
            interaction.selectedCardIDs == Set([ids.a, ids.c]) &&
            interaction.selectionAnchorSlot == BoardSlot(row: 0, column: 0)

        let range = project.cardIDsBetween(BoardSlot(row: 0, column: 0), and: BoardSlot(row: 0, column: 2))
        interaction.selectCards(range, anchorSlot: interaction.selectionAnchorSlot)
        let session = BoardDragController.makeSession(project: project, interaction: interaction, startingFrom: ids.b)

        let sequencePass: Bool
        if case .sequence(let axis, let headCardID, let orderedCardIDs) = session.pattern {
            sequencePass =
                axis == .horizontal &&
                headCardID == ids.a &&
                orderedCardIDs == [ids.a, ids.b, ids.c]
        } else {
            sequencePass = false
        }

        let success = togglePass && sequencePass
        return Phase5HarnessResult(
            title: "Multi Select And Sequence Head",
            success: success,
            detail: success
                ? "command-style toggle keeps the first card anchored and sequence classification preserves that head"
                : "togglePass=\(togglePass) anchor=\(String(describing: interaction.selectionAnchorSlot)) pattern=\(session.pattern)"
        )
    }

    private static func marqueeSelectionCheck() -> Phase5HarnessResult {
        let ids = SequenceFixture.ids
        let project = sequenceProject()
        let layout = BoardCanvasLayout(
            visibleBounds: project.visibleBounds(),
            slotSize: BWRBoardLayoutMetrics.cardSize,
            horizontalSpacing: BWRBoardLayoutMetrics.horizontalGridSpacing,
            verticalSpacing: BWRBoardLayoutMetrics.verticalGridSpacing,
            padding: BWRBoardLayoutMetrics.outerPadding
        )

        let cardsRect = layout
            .rect(for: BoardSlot(row: 0, column: 0))
            .union(layout.rect(for: BoardSlot(row: 0, column: 1)))
            .insetBy(dx: -6, dy: -6)
        let cardSelection = BoardMarqueeController.selection(project: project, layout: layout, rect: cardsRect)

        let emptyRect = layout.rect(for: BoardSlot(row: 1, column: 2)).insetBy(dx: -6, dy: -6)
        let emptySelection = BoardMarqueeController.selection(project: project, layout: layout, rect: emptyRect)

        let success =
            cardSelection.cardIDs == Set([ids.a, ids.b]) &&
            emptySelection.slots == Set([BoardSlot(row: 1, column: 2)])

        return Phase5HarnessResult(
            title: "Marquee Selection",
            success: success,
            detail: success
                ? "marquee selects intersecting cards first and falls back to empty slots when no cards are inside"
                : "cardSelection=\(cardSelection) emptySelection=\(emptySelection)"
        )
    }

    private static func sequenceSmartDragCheck() -> Phase5HarnessResult {
        let ids = SequenceFixture.ids
        var project = sequenceProject()
        var interaction = BoardInteractionState()
        interaction.selectCards(Set([ids.a, ids.b, ids.c]), anchorSlot: BoardSlot(row: 0, column: 0))

        var session = BoardDragController.makeSession(project: project, interaction: interaction, startingFrom: ids.b)
        session.previewOffset = BoardSlotDelta(rows: 0, columns: 1)
        let applied = BoardDragController.apply(project: &project, interaction: &interaction, session: session)

        let success =
            applied &&
            project.presentedCard(id: ids.a)?.slot == BoardSlot(row: 0, column: 1) &&
            project.presentedCard(id: ids.b)?.slot == BoardSlot(row: 0, column: 2) &&
            project.presentedCard(id: ids.c)?.slot == BoardSlot(row: 0, column: 3) &&
            project.presentedCard(id: ids.blocker)?.slot == BoardSlot(row: 0, column: 4) &&
            interaction.selectionAnchorSlot == BoardSlot(row: 0, column: 1) &&
            project.selectedCardID(for: interaction) == ids.a
        let slotSummary = project.liveCards
            .map { "\($0.id.uuidString.prefix(4))@\($0.slot.row),\($0.slot.column)" }
            .joined(separator: ", ")

        return Phase5HarnessResult(
            title: "Sequence Smart Drag",
            success: success,
            detail: success
                ? "sequence drags insert into occupied runs and keep the original head as the anchored card"
                : "applied=\(applied) slots=\(slotSummary) anchor=\(String(describing: interaction.selectionAnchorSlot))"
        )
    }

    private static func clusterDragCheck() -> Phase5HarnessResult {
        let ids = ClusterFixture.ids
        var project = clusterProject()
        var interaction = BoardInteractionState()
        interaction.selectCards(Set([ids.head, ids.tail]), anchorSlot: BoardSlot(row: 0, column: 0))

        var blockedSession = BoardDragController.makeSession(project: project, interaction: interaction, startingFrom: ids.tail)
        blockedSession.previewOffset = BoardSlotDelta(rows: 0, columns: 1)
        let blocked = BoardDragController.apply(project: &project, interaction: &interaction, session: blockedSession)
        let blockedPass =
            blocked == false &&
            project.presentedCard(id: ids.head)?.slot == BoardSlot(row: 0, column: 0) &&
            project.presentedCard(id: ids.tail)?.slot == BoardSlot(row: 1, column: 1)

        var movedSession = BoardDragController.makeSession(project: project, interaction: interaction, startingFrom: ids.head)
        movedSession.previewOffset = BoardSlotDelta(rows: 1, columns: 0)
        let moved = BoardDragController.apply(project: &project, interaction: &interaction, session: movedSession)
        let movedPass =
            moved &&
            project.presentedCard(id: ids.head)?.slot == BoardSlot(row: 1, column: 0) &&
            project.presentedCard(id: ids.tail)?.slot == BoardSlot(row: 2, column: 1) &&
            interaction.selectionAnchorSlot == BoardSlot(row: 1, column: 0)

        let success = blockedPass && movedPass
        return Phase5HarnessResult(
            title: "Cluster Drag",
            success: success,
            detail: success
                ? "cluster drags reject invalid collisions and preserve rigid spacing on valid moves"
                : "blockedPass=\(blockedPass) movedPass=\(movedPass) anchor=\(String(describing: interaction.selectionAnchorSlot))"
        )
    }

    private static func sequenceProject() -> BoardProject {
        BoardProject.singleLayer(
            seeds: [
                .init(cardID: SequenceFixture.ids.a, contentID: SequenceFixture.contentA, layerID: SequenceFixture.layerA, slot: BoardSlot(row: 0, column: 0), markdown: "A"),
                .init(cardID: SequenceFixture.ids.b, contentID: SequenceFixture.contentB, layerID: SequenceFixture.layerB, slot: BoardSlot(row: 0, column: 1), markdown: "B"),
                .init(cardID: SequenceFixture.ids.c, contentID: SequenceFixture.contentC, layerID: SequenceFixture.layerC, slot: BoardSlot(row: 0, column: 2), markdown: "C"),
                .init(cardID: SequenceFixture.ids.blocker, contentID: SequenceFixture.contentBlocker, layerID: SequenceFixture.layerBlocker, slot: BoardSlot(row: 0, column: 3), markdown: "Blocker")
            ]
        )
    }

    private static func clusterProject() -> BoardProject {
        BoardProject.singleLayer(
            seeds: [
                .init(cardID: ClusterFixture.ids.head, contentID: ClusterFixture.contentHead, layerID: ClusterFixture.layerHead, slot: BoardSlot(row: 0, column: 0), markdown: "Head"),
                .init(cardID: ClusterFixture.ids.tail, contentID: ClusterFixture.contentTail, layerID: ClusterFixture.layerTail, slot: BoardSlot(row: 1, column: 1), markdown: "Tail"),
                .init(cardID: ClusterFixture.ids.blocker, contentID: ClusterFixture.contentBlocker, layerID: ClusterFixture.layerBlocker, slot: BoardSlot(row: 0, column: 1), markdown: "Blocker")
            ]
        )
    }
}

private struct Phase5HarnessResult {
    let title: String
    let success: Bool
    let detail: String
}

private enum SequenceFixture {
    static let ids = (
        a: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
        b: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
        c: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
        blocker: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!
    )

    static let contentA = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    static let contentB = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    static let contentC = UUID(uuidString: "20000000-0000-0000-0000-000000000003")!
    static let contentBlocker = UUID(uuidString: "20000000-0000-0000-0000-000000000004")!
    static let layerA = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    static let layerB = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
    static let layerC = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
    static let layerBlocker = UUID(uuidString: "30000000-0000-0000-0000-000000000004")!
}

private enum ClusterFixture {
    static let ids = (
        head: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
        tail: UUID(uuidString: "40000000-0000-0000-0000-000000000002")!,
        blocker: UUID(uuidString: "40000000-0000-0000-0000-000000000003")!
    )

    static let contentHead = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!
    static let contentTail = UUID(uuidString: "50000000-0000-0000-0000-000000000002")!
    static let contentBlocker = UUID(uuidString: "50000000-0000-0000-0000-000000000003")!
    static let layerHead = UUID(uuidString: "60000000-0000-0000-0000-000000000001")!
    static let layerTail = UUID(uuidString: "60000000-0000-0000-0000-000000000002")!
    static let layerBlocker = UUID(uuidString: "60000000-0000-0000-0000-000000000003")!
}
