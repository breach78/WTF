import Foundation

extension FileStore {
    private func craftRootCards(in scenario: Scenario) -> [SceneCard] {
        guard let root = primaryRootCard(in: scenario) else { return [] }
        return directChildren(of: root, in: scenario).filter { $0.category == ScenarioCardCategory.craft }
    }

    private func subtreeIDs(from card: SceneCard, in scenario: Scenario) -> Set<UUID> {
        var result: Set<UUID> = [card.id]
        for child in scenario.children(for: card.id) {
            result.formUnion(subtreeIDs(from: child, in: scenario))
        }
        return result
    }

    func defaultSharedCraftSnapshot() -> SharedCraftTreeNodeSnapshot {
        SharedCraftTreeNodeSnapshot(
            id: sharedCraftRootCardID,
            content: ScenarioCardCategory.craft,
            createdAt: .distantPast,
            colorHex: nil,
            cloneGroupID: nil,
            isAICandidate: false,
            children: []
        )
    }

    private func sharedCraftSnapshot(from card: SceneCard, in scenario: Scenario) -> SharedCraftTreeNodeSnapshot {
        let children = directChildren(of: card, in: scenario).map { child in
            sharedCraftSnapshot(from: child, in: scenario)
        }
        return SharedCraftTreeNodeSnapshot(
            id: card.id,
            content: card.parent?.parent == nil ? ScenarioCardCategory.craft : card.content,
            createdAt: card.createdAt,
            colorHex: card.colorHex,
            cloneGroupID: card.cloneGroupID,
            isAICandidate: card.isAICandidate,
            children: children
        )
    }

    private func combinedSharedCraftSnapshot(in scenario: Scenario) -> SharedCraftTreeNodeSnapshot? {
        let craftRoots = craftRootCards(in: scenario)
        guard let primaryRoot = craftRoots.first else { return nil }

        let mergedChildren = craftRoots.flatMap { craftRoot in
            directChildren(of: craftRoot, in: scenario).map { child in
                sharedCraftSnapshot(from: child, in: scenario)
            }
        }

        return SharedCraftTreeNodeSnapshot(
            id: primaryRoot.id,
            content: ScenarioCardCategory.craft,
            createdAt: primaryRoot.createdAt,
            colorHex: primaryRoot.colorHex,
            cloneGroupID: primaryRoot.cloneGroupID,
            isAICandidate: primaryRoot.isAICandidate,
            children: mergedChildren
        )
    }

    private func sharedCraftNodeCount(_ snapshot: SharedCraftTreeNodeSnapshot) -> Int {
        1 + snapshot.children.reduce(0) { partialResult, child in
            partialResult + sharedCraftNodeCount(child)
        }
    }

    private func bestExistingSharedCraftSourceScenario() -> Scenario? {
        scenarios
            .compactMap { scenario -> (scenario: Scenario, snapshot: SharedCraftTreeNodeSnapshot)? in
                guard let snapshot = combinedSharedCraftSnapshot(in: scenario) else { return nil }
                return (scenario, snapshot)
            }
            .max { lhs, rhs in
                let lhsNodeCount = sharedCraftNodeCount(lhs.snapshot)
                let rhsNodeCount = sharedCraftNodeCount(rhs.snapshot)
                if lhsNodeCount != rhsNodeCount {
                    return lhsNodeCount < rhsNodeCount
                }
                if lhs.scenario.timestamp != rhs.scenario.timestamp {
                    return lhs.scenario.timestamp < rhs.scenario.timestamp
                }
                return lhs.scenario.id.uuidString < rhs.scenario.id.uuidString
            }?
            .scenario
    }

    func currentSharedCraftSnapshot(from sourceScenario: Scenario? = nil) -> SharedCraftTreeNodeSnapshot {
        if let sourceScenario,
           let snapshot = combinedSharedCraftSnapshot(in: sourceScenario) {
            return snapshot
        }
        if let source = bestExistingSharedCraftSourceScenario(),
           let snapshot = combinedSharedCraftSnapshot(in: source) {
            return snapshot
        }
        return defaultSharedCraftSnapshot()
    }

    private func latestDirtySharedCraftSourceScenario() -> Scenario? {
        scenarios
            .filter(\.sharedCraftTreeDirty)
            .max {
                if $0.timestamp != $1.timestamp {
                    return $0.timestamp < $1.timestamp
                }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    private func hasMissingSharedCraftRoot() -> Bool {
        scenarios.contains { craftRootCards(in: $0).isEmpty }
    }

    private func existingSharedCraftSnapshot(in scenario: Scenario) -> SharedCraftTreeNodeSnapshot? {
        combinedSharedCraftSnapshot(in: scenario)
    }

    private func instantiateSharedCraftSnapshot(
        _ snapshot: SharedCraftTreeNodeSnapshot,
        parent: SceneCard,
        scenario: Scenario,
        orderIndex: Int
    ) -> [SceneCard] {
        let card = SceneCard(
            id: snapshot.id,
            content: parent.parent == nil ? ScenarioCardCategory.craft : snapshot.content,
            orderIndex: orderIndex,
            createdAt: snapshot.createdAt,
            parent: parent,
            scenario: scenario,
            category: ScenarioCardCategory.craft,
            isFloating: false,
            isArchived: false,
            lastSelectedChildID: nil,
            colorHex: snapshot.colorHex,
            cloneGroupID: snapshot.cloneGroupID,
            isAICandidate: snapshot.isAICandidate
        )

        var cards: [SceneCard] = [card]
        for (childIndex, childSnapshot) in snapshot.children.enumerated() {
            cards.append(
                contentsOf: instantiateSharedCraftSnapshot(
                    childSnapshot,
                    parent: card,
                    scenario: scenario,
                    orderIndex: childIndex
                )
            )
        }
        return cards
    }

    func applySharedCraftSnapshot(
        _ snapshot: SharedCraftTreeNodeSnapshot,
        to scenario: Scenario,
        preserveTimestamp: Bool
    ) {
        guard let titleRoot = primaryRootCard(in: scenario) else { return }
        if existingSharedCraftSnapshot(in: scenario) == snapshot {
            return
        }

        let savedTimestamp = scenario.timestamp
        let savedChangeCount = scenario.changeCountSinceLastSnapshot
        let craftIDsToRemove: Set<UUID> = {
            let roots = craftRootCards(in: scenario)
            guard !roots.isEmpty else { return [] }
            var ids: Set<UUID> = []
            for craftRoot in roots {
                ids.formUnion(subtreeIDs(from: craftRoot, in: scenario))
            }
            return ids
        }()

        scenario.performWithoutTimestampTracking {
            if !craftIDsToRemove.isEmpty {
                scenario.cards.removeAll { craftIDsToRemove.contains($0.id) }
            }

            let nonCraftChildren = directChildren(of: titleRoot, in: scenario)
                .filter { $0.category != ScenarioCardCategory.craft }
            for (index, child) in nonCraftChildren.enumerated() {
                child.orderIndex = index
            }

            let insertedCards = instantiateSharedCraftSnapshot(
                snapshot,
                parent: titleRoot,
                scenario: scenario,
                orderIndex: nonCraftChildren.count
            )
            scenario.cards.append(contentsOf: insertedCards)

            if let lastSelectedChildID = titleRoot.lastSelectedChildID,
               craftIDsToRemove.contains(lastSelectedChildID) {
                titleRoot.lastSelectedChildID = insertedCards.first?.id
            }

            scenario.bumpCardsVersion()
        }

        if preserveTimestamp {
            scenario.timestamp = savedTimestamp
            scenario.changeCountSinceLastSnapshot = savedChangeCount
        }
    }

    func synchronizeSharedCraftTrees(
        preserveExistingTimestamps: Bool,
        force: Bool = false
    ) {
        let sourceScenario = force ? nil : latestDirtySharedCraftSourceScenario()
        guard force || sourceScenario != nil || hasMissingSharedCraftRoot() else {
            return
        }

        let snapshot = currentSharedCraftSnapshot(from: sourceScenario)
        for scenario in scenarios {
            applySharedCraftSnapshot(
                snapshot,
                to: scenario,
                preserveTimestamp: preserveExistingTimestamps
            )
            scenario.clearSharedCraftDirty()
        }
    }
}
