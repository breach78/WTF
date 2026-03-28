import Foundation

extension FileStore {
    nonisolated private var scenariosURL: URL { folderURL.appendingPathComponent(scenariosFile) }

    private struct ScenarioLoadResult {
        let scenarioID: UUID
        let cardRecords: [CardRecord]
        let historyRecords: [HistorySnapshotRecord]
        let linkedCardRecords: [LinkedCardRecord]
        let summaryRecords: [IndexBoardCardSummaryRecord]
        let cardContents: [UUID: String]
    }

    func load() async {
            try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let scenarioRecords: [ScenarioRecord] = (try? await readJSON(url: scenariosURL, decoder: decoder)) ?? []
            var scenarioMap: [UUID: Scenario] = [:]
            scenarioFolderByID = [:]
            var didRepairInvalidParentLinks = false
            
            // Map to store folder URLs for parallel loading
            var scenarioFolders: [UUID: URL] = [:]

            for s in scenarioRecords {
                let scenario = Scenario(
                    id: s.id,
                    title: s.title,
                    isTemplate: s.isTemplate ?? false,
                    timestamp: s.timestamp,
                    changeCountSinceLastSnapshot: s.changeCountSinceLastSnapshot
                )
                scenarioMap[s.id] = scenario
                let folderName = s.folderName ?? "\(scenarioFolderPrefix)\(s.id.uuidString)"
                scenarioFolderByID[s.id] = folderName
                scenarioFolders[s.id] = folderURL.appendingPathComponent(folderName)
            }

            // Parallel loading using Swift Structured Concurrency
            let results: [ScenarioLoadResult] = await withTaskGroup(of: ScenarioLoadResult?.self) { group in
                for s in scenarioRecords {
                    let scenarioID = s.id
                    guard let scenarioFolder = scenarioFolders[scenarioID] else { continue }
                    
                    let scenarioCardsURL = scenarioFolder.appendingPathComponent(self.cardsFile)
                    let scenarioHistoryURL = scenarioFolder.appendingPathComponent(self.historyFile)
                    let scenarioLinkedCardsURL = scenarioFolder.appendingPathComponent(self.linkedCardsFile)
                    let scenarioSummaryURL = scenarioFolder.appendingPathComponent(self.cardSummariesFile)

                    group.addTask {
                        let perDecoder = JSONDecoder()
                        perDecoder.dateDecodingStrategy = .iso8601

                        guard let cardRecords: [CardRecord] = (try? self.readJSONSync(url: scenarioCardsURL, decoder: perDecoder)) else { return nil }
                        let historyRecords: [HistorySnapshotRecord] = (try? self.readJSONSync(url: scenarioHistoryURL, decoder: perDecoder)) ?? []
                        let linkedCardRecords: [LinkedCardRecord] = (try? self.readJSONSync(url: scenarioLinkedCardsURL, decoder: perDecoder)) ?? []
                        let summaryRecords: [IndexBoardCardSummaryRecord] = (try? self.readJSONSync(url: scenarioSummaryURL, decoder: perDecoder)) ?? []

                        var cardContents: [UUID: String] = Dictionary(minimumCapacity: cardRecords.count)
                        for r in cardRecords {
                            let url = self.cardFileURL(for: r.id, scenarioFolder: scenarioFolder)
                            cardContents[r.id] = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                        }

                        return ScenarioLoadResult(
                            scenarioID: scenarioID,
                            cardRecords: cardRecords,
                            historyRecords: historyRecords,
                            linkedCardRecords: linkedCardRecords,
                            summaryRecords: summaryRecords,
                            cardContents: cardContents
                        )
                    }
                }

                var collected: [ScenarioLoadResult] = []
                for await result in group {
                    if let result = result {
                        collected.append(result)
                    }
                }
                return collected
            }

            let resultsByID = Dictionary(uniqueKeysWithValues: results.map { ($0.scenarioID, $0) })
            for s in scenarioRecords {
                guard let scenario = scenarioMap[s.id],
                      let result = resultsByID[s.id] else { continue }

                scenario.performWithoutTimestampTracking {
                    var cardMap: [UUID: SceneCard] = Dictionary(minimumCapacity: result.cardRecords.count)
                    let recordByID = Dictionary(uniqueKeysWithValues: result.cardRecords.map { ($0.id, $0) })
                    for r in result.cardRecords {
                        let content = result.cardContents[r.id] ?? ""
                        let card = SceneCard(
                            id: r.id,
                            content: content,
                            orderIndex: r.orderIndex,
                            createdAt: r.createdAt,
                            parent: nil,
                            scenario: scenario,
                            category: r.category,
                            isFloating: r.isFloating,
                            isArchived: r.isArchived ?? false,
                            lastSelectedChildID: r.lastSelectedChildID,
                            colorHex: r.colorHex,
                            cloneGroupID: r.cloneGroupID
                        )
                        cardMap[r.id] = card
                        scenario.cards.append(card)
                        lastSavedCardContent[s.id, default: [:]][r.id] = content
                    }

                    var repairedInvalidParents = false
                    for r in result.cardRecords {
                        guard let parentID = r.parentID,
                              let card = cardMap[r.id],
                              let parent = cardMap[parentID] else { continue }

                        var visited: Set<UUID> = [card.id]
                        var currentParentID: UUID? = parentID
                        var createsCycle = false
                        while let currentParentIDValue = currentParentID {
                            guard visited.insert(currentParentIDValue).inserted else {
                                createsCycle = true
                                break
                            }
                            currentParentID = recordByID[currentParentIDValue]?.parentID
                        }

                        if createsCycle {
                            repairedInvalidParents = true
                            continue
                        }

                        card.parent = parent
                    }

                    if repairedInvalidParents {
                        didRepairInvalidParentLinks = true
                        scenario.markCardRecordsDirty()
                        scenario.bumpCardsVersion()
                    }

                    var snapshots: [HistorySnapshot] = []
                    snapshots.reserveCapacity(result.historyRecords.count)
                    for h in result.historyRecords {
                        snapshots.append(HistorySnapshot(
                            id: h.id,
                            timestamp: h.timestamp,
                            name: h.name,
                            scenarioID: h.scenarioID,
                            cardSnapshots: h.cardSnapshots,
                            isDelta: h.isDelta ?? false,
                            deletedCardIDs: h.deletedCardIDs ?? [],
                            isPromoted: h.isPromoted ?? false,
                            promotionReason: h.promotionReason,
                            noteCardID: h.noteCardID
                        ))
                    }
                    scenario.snapshots = snapshots
                    scenario.setLinkedCardRecords(result.linkedCardRecords)

                    let validCardIDs = Set(cardMap.keys)
                    let summaryRecords = result.summaryRecords
                        .compactMap(\.sanitizedForStorage)
                        .filter { validCardIDs.contains($0.cardID) }
                    indexBoardSummaryRecordsByScenarioID[s.id] = Dictionary(
                        uniqueKeysWithValues: summaryRecords.map { ($0.cardID, $0) }
                    )
                }
            }

            scenarios = scenarioMap.values.sorted(by: scenarioSortComparator)

            if scenarios.isEmpty {
                createInitialScenario()
            } else {
                refreshScenarioMetadataObservers()
                synchronizeSharedCraftTrees(preserveExistingTimestamps: true, force: true)
                for scenario in scenarios {
                    scenario.bumpCardsVersion()
                }
                if didRepairInvalidParentLinks {
                    saveAll(immediate: true)
                } else {
                    primeSavedCachesFromCurrentState()
                }
            }
    }

    func saveAll(immediate: Bool = false) {
        requestSave(immediate: immediate)
    }

    func flushPendingSaves() {
        if DispatchQueue.getSpecific(key: saveQueueKey) != nil {
            return
        }
        requestSave(immediate: true)
        saveQueue.sync { }
    }

    private func requestSave(immediate: Bool) {
        if immediate {
            saveDebounceWorkItem?.cancel()
            saveDebounceWorkItem = nil
            guard let payload = makeSavePayload() else { return }
            enqueueSavePayload(payload)
            return
        }

        saveDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                self.saveDebounceWorkItem = nil
                guard let payload = self.makeSavePayload() else { return }
                self.enqueueSavePayload(payload)
            }
        }
        saveDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDebounceInterval, execute: work)
    }

    private func makeSavePayload() -> SavePayload? {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let scenarioRecords = scenarios.map { scenario in
                let folderName = ensureScenarioFolder(for: scenario.id)
                return ScenarioRecord(
                    id: scenario.id,
                    title: scenario.title,
                    isTemplate: scenario.isTemplate,
                    timestamp: scenario.persistedTimestamp(),
                    changeCountSinceLastSnapshot: scenario.changeCountSinceLastSnapshot,
                    folderName: folderName,
                    schemaVersion: currentSchemaVersion
                )
            }
            let scenarioRecordsData = try encoder.encode(scenarioRecords)

            var scenarioPayloads: [ScenarioSavePayload] = []
            scenarioPayloads.reserveCapacity(scenarios.count)
            var nextScenarioPayloadCacheByID: [UUID: ScenarioPayloadCacheEntry] = [:]
            nextScenarioPayloadCacheByID.reserveCapacity(scenarios.count)

            for scenario in scenarios {
                let folderName = ensureScenarioFolder(for: scenario.id)
                let validCardIDs = Set(scenario.cards.map(\.id))
                let cachedPayload = scenarioPayloadCacheByID[scenario.id]

                let cardRecordsData: Data = try {
                    guard let cachedPayload,
                          cachedPayload.cardRecordsVersion == scenario.cardRecordsSaveVersion,
                          cachedPayload.validCardIDs == validCardIDs else {
                        let cardRecords = scenario.cards.map { card in
                            CardRecord(
                                id: card.id,
                                scenarioID: scenario.id,
                                parentID: card.parent?.id,
                                orderIndex: card.orderIndex,
                                createdAt: card.createdAt,
                                category: card.category,
                                isFloating: card.isFloating,
                                isArchived: card.isArchived,
                                lastSelectedChildID: card.lastSelectedChildID,
                                schemaVersion: currentSchemaVersion,
                                colorHex: card.colorHex,
                                cloneGroupID: card.cloneGroupID
                            )
                        }
                        return try encoder.encode(cardRecords)
                    }
                    return cachedPayload.cardRecordsData
                }()

                let historyRecordsData: Data = try {
                    guard let cachedPayload,
                          cachedPayload.historyVersion == scenario.historySaveVersion else {
                        let historyRecords = scenario.snapshots.map { snap in
                            HistorySnapshotRecord(
                                id: snap.id,
                                timestamp: snap.timestamp,
                                name: snap.name,
                                scenarioID: scenario.id,
                                cardSnapshots: snap.cardSnapshots,
                                isDelta: snap.isDelta,
                                deletedCardIDs: snap.deletedCardIDs,
                                isPromoted: snap.isPromoted,
                                promotionReason: snap.promotionReason,
                                noteCardID: snap.noteCardID,
                                schemaVersion: currentSchemaVersion
                            )
                        }
                        return try encoder.encode(historyRecords)
                    }
                    return cachedPayload.historyRecordsData
                }()

                let linkedCardsData: Data = try {
                    guard let cachedPayload,
                          cachedPayload.linkedCardsVersion == scenario.linkedCardsSaveVersion else {
                        return try encoder.encode(scenario.linkedCardRecords(validCardIDs: validCardIDs))
                    }
                    return cachedPayload.linkedCardsData
                }()

                let summaryRecordsData = try encoder.encode(
                    orderedIndexBoardSummaryRecords(
                        for: scenario.id,
                        validCardIDs: validCardIDs
                    )
                )

                let cardContentsByID: [UUID: String] = {
                    guard let cachedPayload,
                          cachedPayload.cardContentVersion == scenario.cardContentSaveVersion,
                          cachedPayload.validCardIDs == validCardIDs else {
                        return Dictionary(uniqueKeysWithValues: scenario.cards.map { ($0.id, $0.content) })
                    }
                    return cachedPayload.cardContentsByID
                }()

                nextScenarioPayloadCacheByID[scenario.id] = ScenarioPayloadCacheEntry(
                    cardRecordsVersion: scenario.cardRecordsSaveVersion,
                    cardContentVersion: scenario.cardContentSaveVersion,
                    historyVersion: scenario.historySaveVersion,
                    linkedCardsVersion: scenario.linkedCardsSaveVersion,
                    validCardIDs: validCardIDs,
                    cardRecordsData: cardRecordsData,
                    historyRecordsData: historyRecordsData,
                    linkedCardsData: linkedCardsData,
                    cardContentsByID: cardContentsByID
                )

                scenarioPayloads.append(
                    ScenarioSavePayload(
                        scenarioID: scenario.id,
                        folderName: folderName,
                        cardRecordsData: cardRecordsData,
                        historyRecordsData: historyRecordsData,
                        linkedCardsData: linkedCardsData,
                        summaryRecordsData: summaryRecordsData,
                        cardContentsByID: cardContentsByID,
                        validCardIDs: validCardIDs
                    )
                )
            }

            scenarioPayloadCacheByID = nextScenarioPayloadCacheByID

            return SavePayload(
                scenarioRecordsData: scenarioRecordsData,
                scenarioPayloads: scenarioPayloads
            )
        } catch {
            return nil
        }
    }

    private func enqueueSavePayload(_ payload: SavePayload) {
        saveQueue.async { [weak self] in
            guard let self = self else { return }
            self.pendingPayload = payload
            guard !self.saveWorkerRunning else { return }
            self.saveWorkerRunning = true
            defer { self.saveWorkerRunning = false }
            while let nextPayload = self.pendingPayload {
                self.pendingPayload = nil
                self.performSave(payload: nextPayload)
            }
        }
    }

    private struct ScenarioSaveResult {
        let scenarioID: UUID
        var cardsIndexWritten: Bool = false
        var historyIndexWritten: Bool = false
        var linkedCardsWritten: Bool = false
        var summaryRecordsWritten: Bool = false
        var cardRecordsData: Data
        var historyRecordsData: Data
        var linkedCardsData: Data
        var summaryRecordsData: Data
        var cardContentWriteCount: Int = 0
        var deletedCardFileCount: Int = 0
        var updatedContentCache: [UUID: String]
    }

    private nonisolated func performSave(payload: SavePayload) {
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

            if lastSavedScenarioRecordsData != payload.scenarioRecordsData {
                try payload.scenarioRecordsData.write(to: scenariosURL, options: .atomic)
                lastSavedScenarioRecordsData = payload.scenarioRecordsData
            }

            let activeScenarioIDs = Set(payload.scenarioPayloads.map { $0.scenarioID })

            let group = DispatchGroup()
            let resultLock = NSLock()
            var results: [ScenarioSaveResult] = []
            results.reserveCapacity(payload.scenarioPayloads.count)

            for scenarioPayload in payload.scenarioPayloads {
                let prevCardsData = lastSavedCardsIndexData[scenarioPayload.scenarioID]
                let prevHistoryData = lastSavedHistoryData[scenarioPayload.scenarioID]
                let prevLinkedCardsData = lastSavedLinkedCardsData[scenarioPayload.scenarioID]
                let prevSummaryData = lastSavedCardSummariesData[scenarioPayload.scenarioID]
                let prevContentCache = lastSavedCardContent[scenarioPayload.scenarioID] ?? [:]

                group.enter()
                concurrentIOQueue.async {
                    defer { group.leave() }

                    let scenarioFolder = self.folderURL.appendingPathComponent(scenarioPayload.folderName)
                    try? FileManager.default.createDirectory(at: scenarioFolder, withIntermediateDirectories: true)

                    var result = ScenarioSaveResult(
                        scenarioID: scenarioPayload.scenarioID,
                        cardRecordsData: scenarioPayload.cardRecordsData,
                        historyRecordsData: scenarioPayload.historyRecordsData,
                        linkedCardsData: scenarioPayload.linkedCardsData,
                        summaryRecordsData: scenarioPayload.summaryRecordsData,
                        updatedContentCache: prevContentCache
                    )

                    let cardsURL = scenarioFolder.appendingPathComponent(self.cardsFile)
                    if prevCardsData != scenarioPayload.cardRecordsData {
                        try? scenarioPayload.cardRecordsData.write(to: cardsURL, options: .atomic)
                        result.cardsIndexWritten = true
                    }

                    let historyURL = scenarioFolder.appendingPathComponent(self.historyFile)
                    if prevHistoryData != scenarioPayload.historyRecordsData {
                        try? scenarioPayload.historyRecordsData.write(to: historyURL, options: .atomic)
                        result.historyIndexWritten = true
                    }

                    let linkedCardsURL = scenarioFolder.appendingPathComponent(self.linkedCardsFile)
                    if prevLinkedCardsData != scenarioPayload.linkedCardsData {
                        try? scenarioPayload.linkedCardsData.write(to: linkedCardsURL, options: .atomic)
                        result.linkedCardsWritten = true
                    }

                    let summaryURL = scenarioFolder.appendingPathComponent(self.cardSummariesFile)
                    if prevSummaryData != scenarioPayload.summaryRecordsData {
                        try? scenarioPayload.summaryRecordsData.write(to: summaryURL, options: .atomic)
                        result.summaryRecordsWritten = true
                    }

                    for (cardID, content) in scenarioPayload.cardContentsByID {
                        if result.updatedContentCache[cardID] != content {
                            self.writeCardContent(id: cardID, content: content, scenarioFolder: scenarioFolder)
                            result.updatedContentCache[cardID] = content
                            result.cardContentWriteCount += 1
                        }
                    }

                    let removedCardIDs = Set(result.updatedContentCache.keys).subtracting(scenarioPayload.validCardIDs)
                    for cardID in removedCardIDs {
                        let url = self.cardFileURL(for: cardID, scenarioFolder: scenarioFolder)
                        try? FileManager.default.removeItem(at: url)
                        result.deletedCardFileCount += 1
                    }
                    result.updatedContentCache = result.updatedContentCache.filter { scenarioPayload.validCardIDs.contains($0.key) }
                    self.cleanupOrphanCardFiles(validIDs: scenarioPayload.validCardIDs, scenarioFolder: scenarioFolder)

                    resultLock.lock()
                    results.append(result)
                    resultLock.unlock()
                }
            }
            group.wait()

            for r in results {
                if r.cardsIndexWritten {
                    lastSavedCardsIndexData[r.scenarioID] = r.cardRecordsData
                }
                if r.historyIndexWritten {
                    lastSavedHistoryData[r.scenarioID] = r.historyRecordsData
                }
                if r.linkedCardsWritten {
                    lastSavedLinkedCardsData[r.scenarioID] = r.linkedCardsData
                }
                if r.summaryRecordsWritten {
                    lastSavedCardSummariesData[r.scenarioID] = r.summaryRecordsData
                }
                lastSavedCardContent[r.scenarioID] = r.updatedContentCache
            }

            lastSavedCardsIndexData = lastSavedCardsIndexData.filter { activeScenarioIDs.contains($0.key) }
            lastSavedHistoryData = lastSavedHistoryData.filter { activeScenarioIDs.contains($0.key) }
            lastSavedCardContent = lastSavedCardContent.filter { activeScenarioIDs.contains($0.key) }
            lastSavedLinkedCardsData = lastSavedLinkedCardsData.filter { activeScenarioIDs.contains($0.key) }
            lastSavedCardSummariesData = lastSavedCardSummariesData.filter { activeScenarioIDs.contains($0.key) }
            lastSavedAIThreadsData = lastSavedAIThreadsData.filter { activeScenarioIDs.contains($0.key) }
            lastSavedAIEmbeddingIndexData = lastSavedAIEmbeddingIndexData.filter { activeScenarioIDs.contains($0.key) }

        } catch { }
    }

    private func primeSavedCachesFromCurrentState() {
        guard let payload = makeSavePayload() else { return }
        saveQueue.async { [weak self] in
            guard let self = self else { return }
            self.lastSavedScenarioRecordsData = payload.scenarioRecordsData
            self.lastSavedCardsIndexData = Dictionary(uniqueKeysWithValues: payload.scenarioPayloads.map { ($0.scenarioID, $0.cardRecordsData) })
            self.lastSavedHistoryData = Dictionary(uniqueKeysWithValues: payload.scenarioPayloads.map { ($0.scenarioID, $0.historyRecordsData) })
            self.lastSavedLinkedCardsData = Dictionary(uniqueKeysWithValues: payload.scenarioPayloads.map { ($0.scenarioID, $0.linkedCardsData) })
            self.lastSavedCardSummariesData = Dictionary(uniqueKeysWithValues: payload.scenarioPayloads.map { ($0.scenarioID, $0.summaryRecordsData) })
            self.lastSavedCardContent = Dictionary(uniqueKeysWithValues: payload.scenarioPayloads.map { ($0.scenarioID, $0.cardContentsByID) })
        }
    }

    private func readJSON<T: Decodable>(url: URL, decoder: JSONDecoder) async throws -> T? {
        try await Task.detached(priority: .utility) {
            try self.readJSONSync(url: url, decoder: decoder)
        }.value
    }

    nonisolated private func readJSONSync<T: Decodable>(url: URL, decoder: JSONDecoder) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(T.self, from: data)
    }
}

struct ScenarioRecord: Codable {
    let id: UUID
    let title: String
    let isTemplate: Bool?
    let timestamp: Date
    let changeCountSinceLastSnapshot: Int
    let folderName: String?
    let schemaVersion: Int?
}

struct CardRecord: Codable {
    let id: UUID
    let scenarioID: UUID
    let parentID: UUID?
    let orderIndex: Int
    let createdAt: Date
    let category: String?
    let isFloating: Bool
    let isArchived: Bool?
    let lastSelectedChildID: UUID?
    let schemaVersion: Int?
    let colorHex: String?
    let cloneGroupID: UUID?
}

struct HistorySnapshotRecord: Codable {
    let id: UUID
    let timestamp: Date
    let name: String?
    let scenarioID: UUID
    let cardSnapshots: [CardSnapshot]
    let isDelta: Bool?
    let deletedCardIDs: [UUID]?
    let isPromoted: Bool?
    let promotionReason: String?
    let noteCardID: UUID?
    let schemaVersion: Int?
}

struct LinkedCardRecord: Codable, Equatable {
    let focusCardID: UUID
    let linkedCardID: UUID
    let lastEditedAt: Date
}
