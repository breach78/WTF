import Foundation

enum BWRPhase3Harness {
    @discardableResult
    static func runAll() -> Bool {
        let results = [
            sparseBoundsCheck(),
            dynamicInsertionCheck(),
            interactionSeparationCheck()
        ]

        for result in results {
            let marker = result.success ? "PASS" : "FAIL"
            print("[BWR Phase 3] \(marker) \(result.title) - \(result.detail)")
        }

        return results.allSatisfy(\.success)
    }

    private static func sparseBoundsCheck() -> Phase3HarnessResult {
        let project = BoardProject.singleLayer(
            seeds: [
                .init(
                    cardID: UUID(uuidString: "AAAA1111-1111-1111-1111-111111111111")!,
                    contentID: UUID(uuidString: "AAAA2222-2222-2222-2222-222222222222")!,
                    layerID: UUID(uuidString: "AAAA3333-3333-3333-3333-333333333333")!,
                    slot: BoardSlot(row: 20, column: 30),
                    markdown: "Far away"
                )
            ]
        )

        let bounds = project.visibleBounds(including: [BoardSlot(row: 18, column: 34)])
        let success =
            bounds.rowRange == 0...23 &&
            bounds.columnRange == 0...37 &&
            bounds.contains(BoardSlot(row: 20, column: 30)) &&
            bounds.contains(.origin) &&
            bounds.contains(BoardSlot(row: 18, column: 34))

        return Phase3HarnessResult(
            title: "Sparse Visible Bounds",
            success: success,
            detail: success
                ? "visible bounds stay pinned to board origin while trailing space grows to the right and bottom"
                : "unexpected bounds rows=\(bounds.rowRange) columns=\(bounds.columnRange)"
        )
    }

    private static func dynamicInsertionCheck() -> Phase3HarnessResult {
        let project = BWRHarnessFixtures.singleLayerProject()
        let farPreferred = BoardSlot(row: 12, column: 14)
        let nearPreferred = BoardSlot(row: 0, column: 0)

        let success =
            project.firstAvailableSlot(preferred: farPreferred) == farPreferred &&
            project.firstAvailableSlot(preferred: nearPreferred) == BoardSlot(row: 0, column: 1)

        return Phase3HarnessResult(
            title: "Dynamic Slot Insertion",
            success: success,
            detail: success
                ? "slot creation no longer depends on a fixed canvas grid"
                : "unexpected insertion slots far=\(String(describing: project.firstAvailableSlot(preferred: farPreferred))) near=\(String(describing: project.firstAvailableSlot(preferred: nearPreferred)))"
        )
    }

    private static func interactionSeparationCheck() -> Phase3HarnessResult {
        let selectedCardID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let keyboardSlot = BoardSlot(row: 0, column: 0)
        let hoverSlot = BoardSlot(row: 3, column: 4)
        let selectedSlot = BoardSlot(row: 8, column: 9)

        var state = BoardInteractionState(
            keyboardCursorSlot: keyboardSlot,
            hoverSlot: hoverSlot,
            selection: .card(selectedCardID)
        )

        let cardSelectionStaysSeparate =
            state.selectedCardID == selectedCardID &&
            state.keyboardCursorSlot == keyboardSlot &&
            state.hoverSlot == hoverSlot &&
            state.selectedEmptySlot == nil

        state.selectEmptySlot(selectedSlot)
        let slotSelectionStaysSeparate =
            state.selectedCardID == nil &&
            state.selectedEmptySlot == selectedSlot &&
            state.keyboardCursorSlot == keyboardSlot &&
            state.hoverSlot == hoverSlot

        let success = cardSelectionStaysSeparate && slotSelectionStaysSeparate

        return Phase3HarnessResult(
            title: "Interaction Separation",
            success: success,
            detail: success
                ? "selection, keyboard cursor, and hover stay independent"
                : "interaction state leaked across cursor/hover/selection"
        )
    }
}

private struct Phase3HarnessResult {
    let title: String
    let success: Bool
    let detail: String
}
