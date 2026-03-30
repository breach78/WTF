import Foundation

struct MainWorkspaceTreeProjection {
    struct Input {
        let scenario: Scenario
        let activeCardID: UUID?
        let activeHistory: [UUID]
        let activeCategory: String?
        let isActiveCardRoot: Bool
        let fallbackLevelsData: [LevelData]
    }

    let levelsData: [LevelData]
    let activePathIDs: [UUID]
    let locationByID: [UUID: (level: Int, index: Int)]

    static func build(input: Input) -> MainWorkspaceTreeProjection {
        guard let activeCardID = input.activeCardID,
              let activeCard = input.scenario.cardByID(activeCardID) else {
            return fallbackProjection(levelsData: input.fallbackLevelsData)
        }

        let activePath = resolvedActivePath(to: activeCard)
        guard let rootCard = activePath.first,
              input.scenario.rootCards.contains(where: { $0.id == rootCard.id }) else {
            return fallbackProjection(levelsData: input.fallbackLevelsData)
        }

        var levelsData: [LevelData] = [
            LevelData(cards: input.scenario.rootCards, parent: nil)
        ]

        if activePath.count > 1 {
            for levelIndex in 1..<activePath.count {
                let parent = activePath[levelIndex - 1]
                levelsData.append(
                    LevelData(
                        cards: filteredChildren(
                            of: parent,
                            levelIndex: levelIndex,
                            input: input
                        ),
                        parent: parent
                    )
                )
            }
        }

        var currentParent = activePath.last
        var levelIndex = activePath.count
        while let parent = currentParent {
            let cards = filteredChildren(
                of: parent,
                levelIndex: levelIndex,
                input: input
            )
            guard !cards.isEmpty else { break }

            levelsData.append(
                LevelData(
                    cards: cards,
                    parent: parent
                )
            )

            guard let nextParent = preferredContinuationChild(
                for: parent,
                visibleChildren: cards,
                activeHistory: input.activeHistory,
                matching: categoryFilter(
                    for: levelIndex,
                    activeCategory: input.activeCategory,
                    isActiveCardRoot: input.isActiveCardRoot
                )
            ) else {
                break
            }

            currentParent = nextParent
            levelIndex += 1
        }

        return projection(
            levelsData: levelsData,
            activePathIDs: activePath.map(\.id)
        )
    }

    private static func filteredChildren(
        of parent: SceneCard,
        levelIndex: Int,
        input: Input
    ) -> [SceneCard] {
        let category = categoryFilter(
            for: levelIndex,
            activeCategory: input.activeCategory,
            isActiveCardRoot: input.isActiveCardRoot
        )
        return parent.sortedChildren.filter { child in
            guard let category else { return true }
            return child.category == category
        }
    }

    private static func categoryFilter(
        for levelIndex: Int,
        activeCategory: String?,
        isActiveCardRoot: Bool
    ) -> String? {
        guard levelIndex > 1 else { return nil }
        guard !isActiveCardRoot else { return nil }
        return activeCategory
    }

    private static func preferredContinuationChild(
        for parent: SceneCard,
        visibleChildren: [SceneCard],
        activeHistory: [UUID],
        matching category: String?
    ) -> SceneCard? {
        if let selection = MainWorkspaceNavigationModel.preferredVisibleNavigationChildSelection(
            sourceCardID: parent.id,
            visibleChildren: visibleChildren,
            matching: category,
            activeHistory: activeHistory
        ) {
            return selection.child
        }

        if let rememberedID = parent.lastSelectedChildID,
           let remembered = visibleChildren.first(where: { $0.id == rememberedID }) {
            return remembered
        }

        return visibleChildren.first
    }

    private static func resolvedActivePath(to card: SceneCard) -> [SceneCard] {
        var path: [SceneCard] = []
        var current: SceneCard? = card
        while let resolved = current {
            path.append(resolved)
            current = resolved.parent
        }
        return path.reversed()
    }

    private static func fallbackProjection(levelsData: [LevelData]) -> MainWorkspaceTreeProjection {
        projection(levelsData: levelsData, activePathIDs: [])
    }

    private static func projection(
        levelsData: [LevelData],
        activePathIDs: [UUID]
    ) -> MainWorkspaceTreeProjection {
        var locationByID: [UUID: (level: Int, index: Int)] = [:]
        for (levelIndex, levelData) in levelsData.enumerated() {
            for (index, card) in levelData.cards.enumerated() {
                locationByID[card.id] = (levelIndex, index)
            }
        }

        return MainWorkspaceTreeProjection(
            levelsData: levelsData,
            activePathIDs: activePathIDs,
            locationByID: locationByID
        )
    }
}
