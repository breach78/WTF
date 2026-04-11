import Foundation

enum BoardSelection: Equatable {
    case none
    case cards(Set<UUID>)
    case slots(Set<BoardSlot>)

    static func card(_ id: UUID) -> BoardSelection {
        .cards([id])
    }

    static func slot(_ slot: BoardSlot) -> BoardSelection {
        .slots([slot])
    }

    var cardIDs: Set<UUID> {
        guard case .cards(let ids) = self else {
            return []
        }
        return ids
    }

    var slots: Set<BoardSlot> {
        guard case .slots(let slots) = self else {
            return []
        }
        return slots
    }

    var primaryCardID: UUID? {
        cardIDs.sorted { $0.uuidString < $1.uuidString }.first
    }

    var primarySlot: BoardSlot? {
        slots.sorted().first
    }
}

struct BoardInteractionState: Equatable {
    var keyboardCursorSlot: BoardSlot?
    var hoverSlot: BoardSlot?
    var selection: BoardSelection
    var selectionAnchorSlot: BoardSlot?
    var editingCardID: UUID?

    init(
        keyboardCursorSlot: BoardSlot? = nil,
        hoverSlot: BoardSlot? = nil,
        selection: BoardSelection = .none,
        selectionAnchorSlot: BoardSlot? = nil,
        editingCardID: UUID? = nil
    ) {
        self.keyboardCursorSlot = keyboardCursorSlot
        self.hoverSlot = hoverSlot
        self.selection = selection
        self.selectionAnchorSlot = selectionAnchorSlot
        self.editingCardID = editingCardID
    }

    var selectedCardID: UUID? {
        selection.primaryCardID
    }

    var selectedEmptySlot: BoardSlot? {
        selection.primarySlot
    }

    var slotsAffectingVisibleBounds: Set<BoardSlot> {
        var slots = selection.slots
        if let keyboardCursorSlot {
            slots.insert(keyboardCursorSlot)
        }
        return slots
    }

    func isSelected(cardID: UUID) -> Bool {
        selection.cardIDs.contains(cardID)
    }

    var selectedCardIDs: Set<UUID> {
        selection.cardIDs
    }

    func isSelected(emptySlot: BoardSlot) -> Bool {
        selection.slots.contains(emptySlot)
    }

    var selectedEmptySlots: Set<BoardSlot> {
        selection.slots
    }

    mutating func seedKeyboardCursor(ifNeeded fallback: BoardSlot?) {
        guard keyboardCursorSlot == nil else {
            return
        }

        keyboardCursorSlot = fallback ?? .origin
    }

    mutating func selectCard(_ cardID: UUID) {
        selection = .card(cardID)
        if editingCardID != cardID {
            editingCardID = nil
        }
    }

    mutating func selectCard(_ cardID: UUID, at slot: BoardSlot) {
        selectionAnchorSlot = slot
        selectCard(cardID)
    }

    mutating func selectCards(_ ids: Set<UUID>, anchorSlot: BoardSlot?) {
        selection = ids.isEmpty ? .none : .cards(ids)
        selectionAnchorSlot = anchorSlot
        if let editingCardID, !ids.contains(editingCardID) {
            self.editingCardID = nil
        }
    }

    mutating func toggleCard(_ cardID: UUID, at slot: BoardSlot) {
        var ids = selection.cardIDs
        if ids.contains(cardID) {
            ids.remove(cardID)
        } else {
            ids.insert(cardID)
        }

        let anchor = ids.isEmpty ? nil : (selectionAnchorSlot ?? slot)
        selectCards(ids, anchorSlot: anchor)
    }

    mutating func selectEmptySlot(_ slot: BoardSlot) {
        selection = .slot(slot)
        selectionAnchorSlot = slot
        editingCardID = nil
    }

    mutating func selectEmptySlots(_ slots: Set<BoardSlot>, anchorSlot: BoardSlot?) {
        selection = slots.isEmpty ? .none : .slots(slots)
        selectionAnchorSlot = anchorSlot
        editingCardID = nil
    }

    mutating func clearHover(ifMatching slot: BoardSlot) {
        guard hoverSlot == slot else {
            return
        }

        hoverSlot = nil
    }

    mutating func clearSelection() {
        selection = .none
        selectionAnchorSlot = nil
        editingCardID = nil
    }
}

enum BoardKeyboardController {
    static func moveCursor(
        project: BoardProject,
        interaction: inout BoardInteractionState,
        rows: Int,
        columns: Int
    ) {
        let current = cursorSlot(for: project, interaction: &interaction)
        let destination = current.offsetBy(rows: rows, columns: columns)
        selectSlot(destination, in: project, interaction: &interaction)
    }

    static func activateEnter(
        project: inout BoardProject,
        interaction: inout BoardInteractionState
    ) {
        if interaction.editingCardID != nil {
            interaction.editingCardID = nil
            return
        }

        activateEditorAtCursor(project: &project, interaction: &interaction)
    }

    static func advanceByTab(
        project: inout BoardProject,
        interaction: inout BoardInteractionState,
        reverse: Bool
    ) {
        interaction.editingCardID = nil
        moveCursor(
            project: project,
            interaction: &interaction,
            rows: 0,
            columns: reverse ? -1 : 1
        )
        activateEditorAtCursor(project: &project, interaction: &interaction)
    }

    static func moveSelectedCard(
        project: inout BoardProject,
        interaction: inout BoardInteractionState,
        rows: Int,
        columns: Int
    ) {
        interaction.editingCardID = nil
        guard
            let selectedCardID = project.selectedCardID(for: interaction),
            let selectedCard = project.presentedCard(id: selectedCardID)
        else {
            moveCursor(project: project, interaction: &interaction, rows: rows, columns: columns)
            return
        }

        let destination = selectedCard.slot.offsetBy(rows: rows, columns: columns)
        project.moveCard(id: selectedCardID, to: destination)
        interaction.keyboardCursorSlot = destination
        interaction.selectCard(selectedCardID, at: destination)
    }

    static func activateEditorAtCursor(
        project: inout BoardProject,
        interaction: inout BoardInteractionState
    ) {
        let slot = cursorSlot(for: project, interaction: &interaction)
        if let card = project.card(at: slot) {
            interaction.keyboardCursorSlot = slot
            interaction.selectCard(card.id, at: slot)
            interaction.editingCardID = card.id
            return
        }

        guard let cardID = project.insertCard(at: slot) else {
            return
        }

        interaction.keyboardCursorSlot = slot
        interaction.selectCard(cardID, at: slot)
        interaction.editingCardID = cardID
    }

    @discardableResult
    static func cursorSlot(
        for project: BoardProject,
        interaction: inout BoardInteractionState
    ) -> BoardSlot {
        interaction.seedKeyboardCursor(ifNeeded: project.liveCards.first?.slot)
        return interaction.keyboardCursorSlot ?? .origin
    }

    static func selectSlot(
        _ slot: BoardSlot,
        in project: BoardProject,
        interaction: inout BoardInteractionState
    ) {
        interaction.keyboardCursorSlot = slot
        if let card = project.card(at: slot) {
            interaction.selectCard(card.id, at: slot)
        } else {
            interaction.selectEmptySlot(slot)
        }
    }
}

struct BoardVisibleBounds: Equatable {
    let minRow: Int
    let maxRow: Int
    let minColumn: Int
    let maxColumn: Int

    init(
        slots: some Sequence<BoardSlot>,
        padding: Int = 1,
        minimumColumns: Int = 3,
        minimumRows: Int = 3
    ) {
        let collected = Array(slots)
        let basis = collected.isEmpty ? [BoardSlot.origin] : collected

        var minRow = (basis.map(\.row).min() ?? 0) - padding
        var maxRow = (basis.map(\.row).max() ?? 0) + padding
        var minColumn = (basis.map(\.column).min() ?? 0) - padding
        var maxColumn = (basis.map(\.column).max() ?? 0) + padding

        Self.expand(&minRow, &maxRow, minimumSpan: max(minimumRows, 1))
        Self.expand(&minColumn, &maxColumn, minimumSpan: max(minimumColumns, 1))

        self.minRow = minRow
        self.maxRow = maxRow
        self.minColumn = minColumn
        self.maxColumn = maxColumn
    }

    var rowRange: ClosedRange<Int> {
        minRow...maxRow
    }

    var columnRange: ClosedRange<Int> {
        minColumn...maxColumn
    }

    var rows: [Int] {
        Array(rowRange)
    }

    var columns: [Int] {
        Array(columnRange)
    }

    var rowCount: Int {
        maxRow - minRow + 1
    }

    var columnCount: Int {
        maxColumn - minColumn + 1
    }

    var allSlots: [BoardSlot] {
        rows.flatMap { row in
            columns.map { column in
                BoardSlot(row: row, column: column)
            }
        }
    }

    func contains(_ slot: BoardSlot) -> Bool {
        rowRange.contains(slot.row) && columnRange.contains(slot.column)
    }

    func orderedSlots(startingAt preferred: BoardSlot?) -> [BoardSlot] {
        let slots = allSlots
        guard let preferred, let index = slots.firstIndex(of: preferred) else {
            return slots
        }

        return Array(slots[index...]) + Array(slots[..<index])
    }

    private static func expand(_ minValue: inout Int, _ maxValue: inout Int, minimumSpan: Int) {
        guard minimumSpan > 0 else {
            return
        }

        while maxValue - minValue + 1 < minimumSpan {
            if (maxValue - minValue).isMultiple(of: 2) {
                maxValue += 1
            } else {
                minValue -= 1
            }
        }
    }
}

extension BoardProject {
    func selection(for slot: BoardSlot) -> BoardSelection {
        if let card = card(at: slot) {
            return .card(card.id)
        }
        return .slot(slot)
    }

    func sortedCardIDs(_ ids: Set<UUID>) -> [UUID] {
        liveCards
            .filter { ids.contains($0.id) }
            .sorted { $0.slot < $1.slot }
            .map(\.id)
    }

    func selectedCardID(for interaction: BoardInteractionState) -> UUID? {
        let ids = interaction.selectedCardIDs
        guard !ids.isEmpty else {
            return nil
        }

        if let anchor = interaction.selectionAnchorSlot, let card = card(at: anchor), ids.contains(card.id) {
            return card.id
        }

        return sortedCardIDs(ids).first
    }

    func selectedEmptySlot(for interaction: BoardInteractionState) -> BoardSlot? {
        let slots = interaction.selectedEmptySlots
        guard !slots.isEmpty else {
            return nil
        }

        if let anchor = interaction.selectionAnchorSlot, slots.contains(anchor) {
            return anchor
        }

        return slots.sorted().first
    }

    func cardIDsBetween(_ start: BoardSlot, and end: BoardSlot) -> Set<UUID> {
        let lower = min(start, end)
        let upper = max(start, end)
        return Set(
            liveCards
                .filter { lower <= $0.slot && $0.slot <= upper }
                .map(\.id)
        )
    }
}
