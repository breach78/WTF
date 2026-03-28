import Foundation
import Combine

extension FileStore {
    func scenarioSortComparator(_ lhs: Scenario, _ rhs: Scenario) -> Bool {
        if lhs.isTemplate != rhs.isTemplate {
            return !lhs.isTemplate && rhs.isTemplate
        }
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp > rhs.timestamp
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    func orderedCards(_ cards: [SceneCard]) -> [SceneCard] {
        cards.sorted {
            if $0.orderIndex != $1.orderIndex {
                return $0.orderIndex < $1.orderIndex
            }
            return $0.createdAt < $1.createdAt
        }
    }

    func primaryRootCard(in scenario: Scenario) -> SceneCard? {
        orderedCards(scenario.rootCards).first
    }

    func directChildren(of parent: SceneCard, in scenario: Scenario) -> [SceneCard] {
        orderedCards(scenario.children(for: parent.id))
    }


    private func resortScenariosInPlace() {
        let sorted = scenarios.sorted(by: scenarioSortComparator)
        guard sorted.map(\.id) != scenarios.map(\.id) else { return }
        scenarios = sorted
    }

    private func scheduleScenarioResort() {
        scenarioResortWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.scenarioResortWorkItem = nil
            self.resortScenariosInPlace()
        }
        scenarioResortWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    func refreshScenarioMetadataObservers() {
        scenarioMetadataObservationByID.removeAll()

        for scenario in scenarios {
            var cancellables: Set<AnyCancellable> = []

            scenario.$timestamp
                .removeDuplicates()
                .sink { [weak self] _ in
                    self?.scheduleScenarioResort()
                }
                .store(in: &cancellables)

            scenario.$isTemplate
                .removeDuplicates()
                .sink { [weak self] _ in
                    self?.scheduleScenarioResort()
                }
                .store(in: &cancellables)

            scenarioMetadataObservationByID[scenario.id] = cancellables
        }
    }

    func addScenario(title: String, fromTemplate template: Scenario? = nil) -> Scenario {
        let scenario = Scenario(title: title)
        _ = ensureScenarioFolder(for: scenario.id)
        if let template {
            scenario.cards = cloneCards(from: template, into: scenario)
        } else {
            let rootCard = SceneCard(content: title, orderIndex: 0, scenario: scenario)
            let plotCard = SceneCard(content: ScenarioCardCategory.plot, orderIndex: 0, parent: rootCard, scenario: scenario, category: ScenarioCardCategory.plot)
            let noteCard = SceneCard(content: ScenarioCardCategory.note, orderIndex: 1, parent: rootCard, scenario: scenario, category: ScenarioCardCategory.note)
            scenario.cards = [rootCard, plotCard, noteCard]
        }
        applySharedCraftSnapshot(currentSharedCraftSnapshot(), to: scenario, preserveTimestamp: false)
        scenario.snapshots = []
        scenario.changeCountSinceLastSnapshot = 0
        scenario.bumpCardsVersion()
        scenarios.insert(scenario, at: 0)
        refreshScenarioMetadataObservers()
        saveAll(immediate: true)
        return scenario
    }

    func makeScenarioTemplate(_ scenario: Scenario) {
        scenario.cards.removeAll { $0.isArchived }
        scenario.snapshots = []
        scenario.changeCountSinceLastSnapshot = 0
        scenario.isTemplate = true
        scenario.bumpCardsVersion()
        saveAll(immediate: true)
    }

    func deleteScenario(_ scenario: Scenario) {
        scenarios.removeAll { $0.id == scenario.id }
        refreshScenarioMetadataObservers()
        if let folderName = scenarioFolderByID[scenario.id] {
            let folder = folderURL.appendingPathComponent(folderName)
            try? fileManager.removeItem(at: folder)
            scenarioFolderByID.removeValue(forKey: scenario.id)
        }
        lastSavedLinkedCardsData.removeValue(forKey: scenario.id)
        lastSavedCardSummariesData.removeValue(forKey: scenario.id)
        lastSavedAIThreadsData.removeValue(forKey: scenario.id)
        lastSavedAIEmbeddingIndexData.removeValue(forKey: scenario.id)
        indexBoardSummaryRecordsByScenarioID.removeValue(forKey: scenario.id)
        saveAll(immediate: true)
    }

    func removeCard(_ card: SceneCard, from scenario: Scenario) {
        let idsToRemove = collectCardIDs(from: card, scenario: scenario)
        scenario.cards.removeAll { idsToRemove.contains($0.id) }
        scenario.pruneLinkedCards(validCardIDs: Set(scenario.cards.map(\.id)))
        scenario.bumpCardsVersion()
        scenario.changeCountSinceLastSnapshot = 0
        synchronizeSharedCraftTrees(preserveExistingTimestamps: true)
        saveAll(immediate: true)
    }

    private func collectCardIDs(from card: SceneCard, scenario: Scenario) -> Set<UUID> {
        var result: Set<UUID> = [card.id]
        for child in scenario.cards.filter({ $0.parent?.id == card.id }) {
            result.formUnion(collectCardIDs(from: child, scenario: scenario))
        }
        return result
    }

    func createInitialScenario() {
        let scenario = Scenario(title: "제목 없음")
        _ = ensureScenarioFolder(for: scenario.id)
        let rootCard = SceneCard(content: "제목 없음", orderIndex: 0, scenario: scenario)
        let plotCard = SceneCard(content: ScenarioCardCategory.plot, orderIndex: 0, parent: rootCard, scenario: scenario, category: ScenarioCardCategory.plot)
        let noteCard = SceneCard(content: ScenarioCardCategory.note, orderIndex: 1, parent: rootCard, scenario: scenario, category: ScenarioCardCategory.note)
        scenario.cards = [rootCard, plotCard, noteCard]
        applySharedCraftSnapshot(defaultSharedCraftSnapshot(), to: scenario, preserveTimestamp: false)
        scenario.bumpCardsVersion()
        scenarios = [scenario]
        refreshScenarioMetadataObservers()
        saveAll(immediate: true)
    }

    private func cloneCards(from template: Scenario, into scenario: Scenario) -> [SceneCard] {
        let sourceCards = template.cards
            .filter { !$0.isArchived }
            .sorted {
                if $0.orderIndex != $1.orderIndex {
                    return $0.orderIndex < $1.orderIndex
                }
                return $0.createdAt < $1.createdAt
            }
        var idMap: [UUID: SceneCard] = [:]
        var clonedCards: [SceneCard] = []
        clonedCards.reserveCapacity(sourceCards.count)

        for source in sourceCards {
            let clone = SceneCard(
                content: source.content,
                orderIndex: source.orderIndex,
                createdAt: Date(),
                parent: nil,
                scenario: scenario,
                category: source.category,
                isFloating: source.isFloating,
                isArchived: false,
                lastSelectedChildID: nil,
                colorHex: source.colorHex,
                cloneGroupID: source.cloneGroupID,
                isAICandidate: false
            )
            idMap[source.id] = clone
            clonedCards.append(clone)
        }

        for source in sourceCards {
            guard let clone = idMap[source.id] else { continue }
            if let sourceParentID = source.parent?.id {
                clone.parent = idMap[sourceParentID]
            }
        }
        return clonedCards
    }

    nonisolated func writeCardContent(id: UUID, content: String, scenarioFolder: URL) {
        let url = cardFileURL(for: id, scenarioFolder: scenarioFolder)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    nonisolated func cleanupOrphanCardFiles(validIDs: Set<UUID>, scenarioFolder: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: scenarioFolder, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("card_") && file.pathExtension == "txt" {
            let name = file.deletingPathExtension().lastPathComponent
            let idPart = name.replacingOccurrences(of: "card_", with: "")
            if let id = UUID(uuidString: idPart), !validIDs.contains(id) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    nonisolated func cardFileURL(for id: UUID, scenarioFolder: URL) -> URL {
        scenarioFolder.appendingPathComponent("card_\(id.uuidString).txt")
    }

    func orderedIndexBoardSummaryRecords(
        for scenarioID: UUID,
        validCardIDs: Set<UUID>
    ) -> [IndexBoardCardSummaryRecord] {
        let records = indexBoardSummaryRecordsByScenarioID[scenarioID] ?? [:]
        return records.values
            .compactMap(\.sanitizedForStorage)
            .filter { validCardIDs.contains($0.cardID) }
            .sorted { lhs, rhs in
                lhs.cardID.uuidString < rhs.cardID.uuidString
            }
    }

    func ensureScenarioFolder(for scenarioID: UUID) -> String {
        if let existing = scenarioFolderByID[scenarioID] { return existing }
        let folderName = "\(scenarioFolderPrefix)\(scenarioID.uuidString)"
        scenarioFolderByID[scenarioID] = folderName
        return folderName
    }
}
