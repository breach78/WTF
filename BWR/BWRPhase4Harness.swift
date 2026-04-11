import Foundation

enum BWRPhase4Harness {
    @discardableResult
    static func runAll() -> Bool {
        let results = [
            enterCreatesAndEditsCheck(),
            tabFlowCheck(),
            arrowAndCardMoveCheck()
        ]

        for result in results {
            let marker = result.success ? "PASS" : "FAIL"
            print("[BWR Phase 4] \(marker) \(result.title) - \(result.detail)")
        }

        return results.allSatisfy(\.success)
    }

    private static func enterCreatesAndEditsCheck() -> Phase4HarnessResult {
        var project = BoardProject()
        var interaction = BoardInteractionState()

        BoardKeyboardController.activateEnter(project: &project, interaction: &interaction)

        let createdCard = project.presentedCards.first
        let success =
            project.presentedCards.count == 1 &&
            createdCard?.slot == .origin &&
            interaction.keyboardCursorSlot == .origin &&
            interaction.selectedCardID == createdCard?.id &&
            interaction.editingCardID == createdCard?.id

        return Phase4HarnessResult(
            title: "Enter Create/Edit",
            success: success,
            detail: success
                ? "Return creates a card on an empty cursor slot and opens inline editing"
                : "enter flow mismatch createdCount=\(project.presentedCards.count) cursor=\(String(describing: interaction.keyboardCursorSlot)) editing=\(String(describing: interaction.editingCardID))"
        )
    }

    private static func tabFlowCheck() -> Phase4HarnessResult {
        var project = BWRHarnessFixtures.singleLayerProject()
        let firstCardID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        var interaction = BoardInteractionState(
            keyboardCursorSlot: .origin,
            selection: .card(firstCardID),
            editingCardID: firstCardID
        )

        BoardKeyboardController.advanceByTab(project: &project, interaction: &interaction, reverse: false)
        let createdCard = project.card(at: BoardSlot(row: 0, column: 1))
        let forwardPass =
            createdCard != nil &&
            interaction.keyboardCursorSlot == BoardSlot(row: 0, column: 1) &&
            interaction.selectedCardID == createdCard?.id &&
            interaction.editingCardID == createdCard?.id

        BoardKeyboardController.advanceByTab(project: &project, interaction: &interaction, reverse: true)
        let backwardPass =
            interaction.keyboardCursorSlot == .origin &&
            interaction.selectedCardID == firstCardID &&
            interaction.editingCardID == firstCardID

        let success = forwardPass && backwardPass
        return Phase4HarnessResult(
            title: "Tab Navigation Flow",
            success: success,
            detail: success
                ? "Tab and Shift-Tab save editing, move logically, and reuse or create cards"
                : "tab flow mismatch createdAt01=\(String(describing: createdCard?.id)) cursor=\(String(describing: interaction.keyboardCursorSlot)) selected=\(String(describing: interaction.selectedCardID)) editing=\(String(describing: interaction.editingCardID))"
        )
    }

    private static func arrowAndCardMoveCheck() -> Phase4HarnessResult {
        var project = BWRHarnessFixtures.singleLayerProject()
        let secondCardID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        var interaction = BoardInteractionState()

        BoardKeyboardController.moveCursor(project: project, interaction: &interaction, rows: 1, columns: 2)
        let cursorSelectedCard =
            interaction.keyboardCursorSlot == BoardSlot(row: 1, column: 2) &&
            interaction.selectedCardID == secondCardID &&
            interaction.editingCardID == nil

        BoardKeyboardController.moveSelectedCard(
            project: &project,
            interaction: &interaction,
            rows: 0,
            columns: -1
        )
        let movedCard = project.presentedCard(id: secondCardID)
        let moveApplied =
            movedCard?.slot == BoardSlot(row: 1, column: 1) &&
            interaction.keyboardCursorSlot == BoardSlot(row: 1, column: 1) &&
            interaction.selectedCardID == secondCardID

        let success = cursorSelectedCard && moveApplied
        return Phase4HarnessResult(
            title: "Arrow Navigation And Move",
            success: success,
            detail: success
                ? "Arrow keys move the cursor and keyboard move commands relocate the selected card"
                : "arrow flow mismatch cursor=\(String(describing: interaction.keyboardCursorSlot)) movedSlot=\(String(describing: movedCard?.slot)) selected=\(String(describing: interaction.selectedCardID))"
        )
    }
}

private struct Phase4HarnessResult {
    let title: String
    let success: Bool
    let detail: String
}
