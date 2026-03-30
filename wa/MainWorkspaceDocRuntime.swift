import Foundation

struct MainWorkspaceDocRuntime {
    static let activeHistoryLimit = 40

    struct State {
        let activeCardID: UUID?
        let activeHistory: [UUID]
        let relationSnapshot: MainWorkspaceActiveRelationSnapshot
    }

    static func changeMode(
        previousActiveID: UUID?,
        nextActiveID: UUID?,
        activeHistory: [UUID],
        updateHistory: Bool,
        scenario: Scenario
    ) -> State {
        let resolvedHistory = updateHistory
            ? updatedActiveHistory(
                activeHistory,
                previousActiveID: previousActiveID,
                nextActiveID: nextActiveID
            )
            : activeHistory

        return State(
            activeCardID: nextActiveID,
            activeHistory: resolvedHistory,
            relationSnapshot: relationSnapshot(
                activeCardID: nextActiveID,
                scenario: scenario
            )
        )
    }

    static func updatedActiveHistory(
        _ activeHistory: [UUID],
        previousActiveID: UUID?,
        nextActiveID: UUID?
    ) -> [UUID] {
        guard let previousActiveID else { return activeHistory }
        guard previousActiveID != nextActiveID else { return activeHistory }

        var updated = activeHistory.filter { $0 != previousActiveID }
        updated.insert(previousActiveID, at: 0)
        if updated.count > activeHistoryLimit {
            updated.removeSubrange(activeHistoryLimit..<updated.count)
        }
        return updated
    }

    static func relationSnapshot(
        activeCardID: UUID?,
        scenario: Scenario
    ) -> MainWorkspaceActiveRelationSnapshot {
        guard let activeCardID,
              let card = scenario.cardByID(activeCardID) else {
            return MainWorkspaceActiveRelationSnapshot(
                sourceCardID: nil,
                cardsVersion: scenario.cardsVersion,
                ancestorIDs: [],
                siblingIDs: [],
                descendantIDs: []
            )
        }

        var ancestorIDs: Set<UUID> = []
        var parent = card.parent
        while let current = parent {
            ancestorIDs.insert(current.id)
            parent = current.parent
        }

        let siblings = card.parent?.children ?? scenario.rootCards
        return MainWorkspaceActiveRelationSnapshot(
            sourceCardID: activeCardID,
            cardsVersion: scenario.cardsVersion,
            ancestorIDs: ancestorIDs,
            siblingIDs: Set(siblings.map(\.id)).subtracting([activeCardID]),
            descendantIDs: scenario.descendantIDs(for: activeCardID)
        )
    }
}
