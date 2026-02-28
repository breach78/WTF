import Foundation
import Combine

@MainActor
final class Scenario: ObservableObject, Identifiable, Hashable {
    static func == (lhs: Scenario, rhs: Scenario) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let id: UUID
    @Published var title: String { didSet { markModified() } }
    @Published var isTemplate: Bool { didSet { markModified() } }
    @Published var timestamp: Date
    @Published var changeCountSinceLastSnapshot: Int
    @Published var cards: [SceneCard] { didSet { markModified() } }
    @Published var snapshots: [HistorySnapshot] {
        didSet {
            cachedSortedSnapshots = nil
            markModified()
        }
    }
    @Published private(set) var cardsVersion: Int = 0
    private var cachedVersion: Int = -1
    private var cachedRoots: [SceneCard] = []
    private var cachedChildrenByParent: [UUID: [SceneCard]] = [:]
    private var cachedCardsByID: [UUID: SceneCard] = [:]
    private var cachedCardLocationByID: [UUID: (level: Int, index: Int)] = [:]
    private var cachedCloneMembersByGroup: [UUID: [SceneCard]] = [:]
    private var activeCloneSyncGroupIDs: Set<UUID> = []
    private var cachedSortedSnapshots: [HistorySnapshot]?
    private var cachedLevels: [[SceneCard]] = []
    private var timestampTrackingSuppressionCount: Int = 0
    private var interactiveTimestampSuppressionCount: Int = 0
    private var pendingModifiedTimestamp: Date?
    private var pendingModifiedWorkItem: DispatchWorkItem?
    private var lastAppliedModifiedAt: Date = .distantPast
    private let modifiedTimestampDebounceInterval: TimeInterval = 0.14

    init(id: UUID = UUID(), title: String = "새 시나리오", isTemplate: Bool = false, timestamp: Date = Date(), changeCountSinceLastSnapshot: Int = 0, cards: [SceneCard] = [], snapshots: [HistorySnapshot] = []) {
        self.id = id
        self.title = title
        self.isTemplate = isTemplate
        self.timestamp = timestamp
        self.changeCountSinceLastSnapshot = changeCountSinceLastSnapshot
        self.cards = cards
        self.snapshots = snapshots
        self.lastAppliedModifiedAt = timestamp
    }

    var rootCards: [SceneCard] {
        rebuildIndexIfNeeded()
        return cachedRoots
    }

    var sortedSnapshots: [HistorySnapshot] {
        if let cached = cachedSortedSnapshots { return cached }
        let sorted = snapshots.sorted { $0.timestamp < $1.timestamp }
        cachedSortedSnapshots = sorted
        return sorted
    }

    func invalidateSnapshotCache() {
        cachedSortedSnapshots = nil
    }

    func markModified(at date: Date = Date()) {
        guard totalTimestampSuppressionCount == 0 else {
            recordPendingModifiedTimestamp(date)
            return
        }
        let elapsed = date.timeIntervalSince(lastAppliedModifiedAt)
        if elapsed >= modifiedTimestampDebounceInterval {
            pendingModifiedWorkItem?.cancel()
            pendingModifiedWorkItem = nil
            pendingModifiedTimestamp = nil
            applyModifiedTimestamp(date)
            return
        }

        recordPendingModifiedTimestamp(date)

        guard pendingModifiedWorkItem == nil else { return }
        let delay = max(0.01, modifiedTimestampDebounceInterval - max(0, elapsed))
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingModifiedWorkItem = nil
            guard self.totalTimestampSuppressionCount == 0 else { return }
            guard let pending = self.pendingModifiedTimestamp else { return }
            self.pendingModifiedTimestamp = nil
            self.applyModifiedTimestamp(pending)
        }
        pendingModifiedWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func performWithoutTimestampTracking(_ work: () -> Void) {
        timestampTrackingSuppressionCount += 1
        defer {
            timestampTrackingSuppressionCount = max(0, timestampTrackingSuppressionCount - 1)
            if totalTimestampSuppressionCount == 0 {
                flushPendingModifiedTimestamp()
            }
        }
        work()
    }

    func beginInteractiveTimestampSuppression() {
        interactiveTimestampSuppressionCount += 1
    }

    func endInteractiveTimestampSuppression(flush: Bool = true) {
        interactiveTimestampSuppressionCount = max(0, interactiveTimestampSuppressionCount - 1)
        if flush, totalTimestampSuppressionCount == 0 {
            flushPendingModifiedTimestamp()
        }
    }

    func flushPendingModifiedTimestamp() {
        pendingModifiedWorkItem?.cancel()
        pendingModifiedWorkItem = nil
        guard totalTimestampSuppressionCount == 0 else { return }
        guard let pending = pendingModifiedTimestamp else { return }
        pendingModifiedTimestamp = nil
        applyModifiedTimestamp(pending)
    }

    private var totalTimestampSuppressionCount: Int {
        timestampTrackingSuppressionCount + interactiveTimestampSuppressionCount
    }

    private func recordPendingModifiedTimestamp(_ date: Date) {
        if let pending = pendingModifiedTimestamp {
            if date > pending {
                pendingModifiedTimestamp = date
            }
        } else {
            pendingModifiedTimestamp = date
        }
    }

    private func applyModifiedTimestamp(_ date: Date) {
        lastAppliedModifiedAt = date
        timestamp = date
    }

    func bumpCardsVersion() {
        cardsVersion += 1
    }

    func cardByID(_ id: UUID) -> SceneCard? {
        rebuildIndexIfNeeded()
        return cachedCardsByID[id]
    }

    func cardLocationByID(_ id: UUID) -> (level: Int, index: Int)? {
        rebuildIndexIfNeeded()
        return cachedCardLocationByID[id]
    }

    func children(for parentID: UUID) -> [SceneCard] {
        rebuildIndexIfNeeded()
        return cachedChildrenByParent[parentID] ?? []
    }

    func clonePeers(for cardID: UUID, excluding excludedCardID: UUID? = nil) -> [SceneCard] {
        rebuildIndexIfNeeded()
        guard let card = cachedCardsByID[cardID],
              let cloneGroupID = card.cloneGroupID,
              let members = cachedCloneMembersByGroup[cloneGroupID] else { return [] }
        return members.filter { member in
            member.id != cardID && member.id != excludedCardID
        }
    }

    func isCardCloned(_ cardID: UUID) -> Bool {
        rebuildIndexIfNeeded()
        guard let card = cachedCardsByID[cardID],
              let cloneGroupID = card.cloneGroupID,
              let members = cachedCloneMembersByGroup[cloneGroupID] else { return false }
        return members.count > 1
    }

    func propagateCloneContent(from sourceCard: SceneCard, content: String) {
        guard let cloneGroupID = sourceCard.cloneGroupID else { return }
        rebuildIndexIfNeeded()
        guard let members = cachedCloneMembersByGroup[cloneGroupID], members.count > 1 else { return }
        guard !activeCloneSyncGroupIDs.contains(cloneGroupID) else { return }

        activeCloneSyncGroupIDs.insert(cloneGroupID)
        defer { activeCloneSyncGroupIDs.remove(cloneGroupID) }

        for member in members where member.id != sourceCard.id {
            member.applyCloneSynchronizedContent(content)
        }
    }

    func propagateCloneColor(from sourceCard: SceneCard, colorHex: String?) {
        guard let cloneGroupID = sourceCard.cloneGroupID else { return }
        rebuildIndexIfNeeded()
        guard let members = cachedCloneMembersByGroup[cloneGroupID], members.count > 1 else { return }
        guard !activeCloneSyncGroupIDs.contains(cloneGroupID) else { return }

        activeCloneSyncGroupIDs.insert(cloneGroupID)
        defer { activeCloneSyncGroupIDs.remove(cloneGroupID) }

        for member in members where member.id != sourceCard.id {
            member.applyCloneSynchronizedColor(colorHex)
        }
    }

    var allLevels: [[SceneCard]] {
        rebuildIndexIfNeeded()
        return cachedLevels
    }

    private func rebuildIndexIfNeeded() {
        if cachedVersion == cardsVersion { return }
        var roots: [SceneCard] = []
        var childrenByParent: [UUID: [SceneCard]] = [:]
        var byID: [UUID: SceneCard] = Dictionary(minimumCapacity: cards.count)
        var cloneMembersByGroup: [UUID: [SceneCard]] = [:]
        for card in cards {
            byID[card.id] = card
            guard !card.isArchived else { continue }
            if let cloneGroupID = card.cloneGroupID {
                cloneMembersByGroup[cloneGroupID, default: []].append(card)
            }
            if let parent = card.parent {
                childrenByParent[parent.id, default: []].append(card)
            } else if !card.isFloating {
                roots.append(card)
            }
        }
        roots.sort { $0.orderIndex < $1.orderIndex }
        for key in childrenByParent.keys {
            childrenByParent[key]?.sort { $0.orderIndex < $1.orderIndex }
        }
        cachedRoots = roots
        cachedChildrenByParent = childrenByParent
        cachedCardsByID = byID
        cachedCloneMembersByGroup = cloneMembersByGroup
        // Build levels hierarchy
        var levels: [[SceneCard]] = [roots]
        var curr = roots
        while !curr.isEmpty {
            let next = curr.flatMap { childrenByParent[$0.id] ?? [] }
            if next.isEmpty { break }
            levels.append(next)
            curr = next
        }
        var locationByID: [UUID: (level: Int, index: Int)] = [:]
        locationByID.reserveCapacity(cards.count)
        for (levelIndex, levelCards) in levels.enumerated() {
            for (index, card) in levelCards.enumerated() {
                locationByID[card.id] = (levelIndex, index)
            }
        }
        cachedLevels = levels
        cachedCardLocationByID = locationByID
        cachedVersion = cardsVersion
    }
}

@MainActor
final class SceneCard: ObservableObject, Identifiable {
    let id: UUID
    @Published var content: String {
        didSet {
            guard !isApplyingCloneSynchronization else { return }
            scenario?.propagateCloneContent(from: self, content: content)
            scenario?.markModified()
        }
    }
    @Published var orderIndex: Int {
        didSet {
            scenario?.bumpCardsVersion()
            scenario?.markModified()
        }
    }
    @Published var createdAt: Date
    @Published var parent: SceneCard? {
        didSet {
            scenario?.bumpCardsVersion()
            scenario?.markModified()
        }
    }
    weak var scenario: Scenario?
    @Published var category: String? { didSet { scenario?.markModified() } }
    @Published var isFloating: Bool {
        didSet {
            scenario?.bumpCardsVersion()
            scenario?.markModified()
        }
    }
    @Published var isArchived: Bool {
        didSet {
            scenario?.bumpCardsVersion()
            scenario?.markModified()
        }
    }
    @Published var lastSelectedChildID: UUID?
    @Published var colorHex: String? {
        didSet {
            guard !isApplyingCloneSynchronization else { return }
            scenario?.propagateCloneColor(from: self, colorHex: colorHex)
            scenario?.markModified()
        }
    }
    @Published var cloneGroupID: UUID? {
        didSet {
            scenario?.bumpCardsVersion()
            scenario?.markModified()
        }
    }
    @Published var isAICandidate: Bool
    private var isApplyingCloneSynchronization: Bool = false

    init(id: UUID = UUID(), content: String = "", orderIndex: Int = 0, createdAt: Date = Date(), parent: SceneCard? = nil, scenario: Scenario? = nil, category: String? = nil, isFloating: Bool = false, isArchived: Bool = false, lastSelectedChildID: UUID? = nil, colorHex: String? = nil, cloneGroupID: UUID? = nil, isAICandidate: Bool = false) {
        self.id = id
        self.content = content
        self.orderIndex = orderIndex
        self.createdAt = createdAt
        self.parent = parent
        self.scenario = scenario
        self.category = category
        self.isFloating = isFloating
        self.isArchived = isArchived
        self.lastSelectedChildID = lastSelectedChildID
        self.colorHex = colorHex
        self.cloneGroupID = cloneGroupID
        self.isAICandidate = isAICandidate
    }

    fileprivate func applyCloneSynchronizedContent(_ newContent: String) {
        guard content != newContent else { return }
        isApplyingCloneSynchronization = true
        content = newContent
        isApplyingCloneSynchronization = false
    }

    fileprivate func applyCloneSynchronizedColor(_ newColorHex: String?) {
        guard colorHex != newColorHex else { return }
        isApplyingCloneSynchronization = true
        colorHex = newColorHex
        isApplyingCloneSynchronization = false
    }

    var children: [SceneCard] {
        guard let scenario = scenario else { return [] }
        return scenario.children(for: self.id)
    }

    var sortedChildren: [SceneCard] {
        children
    }

    func updateDescendantsCategory(_ newCategory: String?) {
        self.applyDescendantsCategory(newCategory)
    }

    private func applyDescendantsCategory(_ newCategory: String?) {
        self.category = newCategory
        for child in children {
            child.applyDescendantsCategory(newCategory)
        }
    }
}

final class HistorySnapshot: Identifiable {
    let id: UUID
    let timestamp: Date
    var name: String?
    let scenarioID: UUID
    var cardSnapshots: [CardSnapshot]
    var isDelta: Bool
    var deletedCardIDs: [UUID]
    var isPromoted: Bool
    var promotionReason: String?
    var noteCardID: UUID?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        name: String? = nil,
        scenarioID: UUID,
        cardSnapshots: [CardSnapshot] = [],
        isDelta: Bool = false,
        deletedCardIDs: [UUID] = [],
        isPromoted: Bool = false,
        promotionReason: String? = nil,
        noteCardID: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.name = name
        self.scenarioID = scenarioID
        self.cardSnapshots = cardSnapshots
        self.isDelta = isDelta
        self.deletedCardIDs = deletedCardIDs
        self.isPromoted = isPromoted
        self.promotionReason = promotionReason
        self.noteCardID = noteCardID
    }
}

struct CardSnapshot: Codable, Equatable {
    let cardID: UUID
    let content: String
    let orderIndex: Int
    let parentID: UUID?
    let category: String?
    let isFloating: Bool
    let isArchived: Bool
    let cloneGroupID: UUID?

    init(from card: SceneCard) {
        self.cardID = card.id
        self.content = card.content
        self.orderIndex = card.orderIndex
        self.parentID = card.parent?.id
        self.category = card.category
        self.isFloating = card.isFloating
        self.isArchived = card.isArchived
        self.cloneGroupID = card.cloneGroupID
    }
}

@MainActor
final class FileStore: ObservableObject {
    private let currentSchemaVersion = 2
    @Published var scenarios: [Scenario] = []
    let folderURL: URL

    private let fileManager = FileManager.default
    private let scenariosFile = "scenarios.json"
    private let cardsFile = "cards_index.json"
    private let historyFile = "history.json"
    private let aiThreadsFile = "ai_threads.json"
    private let aiEmbeddingIndexFile = "ai_embedding_index.json"
    private let aiVectorIndexFile = "ai_vector_index.sqlite"
    private let scenarioFolderPrefix = "scenario_"
    private let saveDebounceInterval: TimeInterval = 0.55
    private var scenarioFolderByID: [UUID: String] = [:]

    private struct ScenarioSavePayload {
        let scenarioID: UUID
        let folderName: String
        let cardRecordsData: Data
        let historyRecordsData: Data
        let cardContentsByID: [UUID: String]
        let validCardIDs: Set<UUID>
    }

    private struct SavePayload {
        let scenarioRecordsData: Data
        let scenarioPayloads: [ScenarioSavePayload]
    }

    private let concurrentIOQueue = DispatchQueue(label: "wa.filestore.io.concurrent", qos: .utility, attributes: .concurrent)
    private let saveQueue = DispatchQueue(label: "wa.filestore.save.queue", qos: .utility)
    private let saveQueueKey = DispatchSpecificKey<Void>()
    private var saveDebounceWorkItem: DispatchWorkItem?
    private nonisolated(unsafe) var saveWorkerRunning: Bool = false
    private nonisolated(unsafe) var pendingPayload: SavePayload?

    // Dirty caches: unchanged payloads are skipped. Accessed only from saveQueue.
    private nonisolated(unsafe) var lastSavedScenarioRecordsData: Data?
    private nonisolated(unsafe) var lastSavedCardsIndexData: [UUID: Data] = [:]
    private nonisolated(unsafe) var lastSavedHistoryData: [UUID: Data] = [:]
    private nonisolated(unsafe) var lastSavedCardContent: [UUID: [UUID: String]] = [:]
    private nonisolated(unsafe) var lastSavedAIThreadsData: [UUID: Data] = [:]
    private nonisolated(unsafe) var lastSavedAIEmbeddingIndexData: [UUID: Data] = [:]

    init(folderURL: URL) {
        self.folderURL = folderURL
        saveQueue.setSpecific(key: saveQueueKey, value: ())
    }

    nonisolated private var scenariosURL: URL { folderURL.appendingPathComponent(scenariosFile) }
    nonisolated private var cardsURL: URL { folderURL.appendingPathComponent(cardsFile) }
    nonisolated private var historyURL: URL { folderURL.appendingPathComponent(historyFile) }

    private struct ScenarioLoadResult {
        let scenarioID: UUID
        let cardRecords: [CardRecord]
        let historyRecords: [HistorySnapshotRecord]
        let cardContents: [UUID: String]
    }

    private func scenarioSortComparator(_ lhs: Scenario, _ rhs: Scenario) -> Bool {
        if lhs.isTemplate != rhs.isTemplate {
            return !lhs.isTemplate && rhs.isTemplate
        }
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp > rhs.timestamp
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func resortScenariosInPlace() {
        let sorted = scenarios.sorted(by: scenarioSortComparator)
        guard sorted.map(\.id) != scenarios.map(\.id) else { return }
        scenarios = sorted
    }

    func load() async {
            try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let scenarioRecords: [ScenarioRecord] = (try? await readJSON(url: scenariosURL, decoder: decoder)) ?? []
            var scenarioMap: [UUID: Scenario] = [:]
            scenarioFolderByID = [:]
            
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

                    group.addTask {
                        let perDecoder = JSONDecoder()
                        perDecoder.dateDecodingStrategy = .iso8601

                        guard let cardRecords: [CardRecord] = (try? self.readJSONSync(url: scenarioCardsURL, decoder: perDecoder)) else { return nil }
                        let historyRecords: [HistorySnapshotRecord] = (try? self.readJSONSync(url: scenarioHistoryURL, decoder: perDecoder)) ?? []

                        var cardContents: [UUID: String] = Dictionary(minimumCapacity: cardRecords.count)
                        for r in cardRecords {
                            let url = self.cardFileURL(for: r.id, scenarioFolder: scenarioFolder)
                            cardContents[r.id] = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                        }

                        return ScenarioLoadResult(
                            scenarioID: scenarioID,
                            cardRecords: cardRecords,
                            historyRecords: historyRecords,
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

                    for r in result.cardRecords {
                        if let parentID = r.parentID, let card = cardMap[r.id], let parent = cardMap[parentID] {
                            card.parent = parent
                        }
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
                }
            }

            scenarios = scenarioMap.values.sorted(by: scenarioSortComparator)
            for scenario in scenarios {
                scenario.bumpCardsVersion()
            }

            if scenarios.isEmpty {
                createInitialScenario()
            } else {
                primeSavedCachesFromCurrentState()
            }
    }

    func saveAll(immediate: Bool = false) {
        for scenario in scenarios {
            scenario.flushPendingModifiedTimestamp()
        }
        resortScenariosInPlace()
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
                    timestamp: scenario.timestamp,
                    changeCountSinceLastSnapshot: scenario.changeCountSinceLastSnapshot,
                    folderName: folderName,
                    schemaVersion: currentSchemaVersion
                )
            }
            let scenarioRecordsData = try encoder.encode(scenarioRecords)

            var scenarioPayloads: [ScenarioSavePayload] = []
            scenarioPayloads.reserveCapacity(scenarios.count)

            for scenario in scenarios {
                let folderName = ensureScenarioFolder(for: scenario.id)
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
                let cardRecordsData = try encoder.encode(cardRecords)
                let historyRecordsData = try encoder.encode(historyRecords)
                let cardContentsByID = Dictionary(uniqueKeysWithValues: scenario.cards.map { ($0.id, $0.content) })
                let validCardIDs = Set(cardContentsByID.keys)

                scenarioPayloads.append(
                    ScenarioSavePayload(
                        scenarioID: scenario.id,
                        folderName: folderName,
                        cardRecordsData: cardRecordsData,
                        historyRecordsData: historyRecordsData,
                        cardContentsByID: cardContentsByID,
                        validCardIDs: validCardIDs
                    )
                )
            }

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
        var cardRecordsData: Data
        var historyRecordsData: Data
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
                lastSavedCardContent[r.scenarioID] = r.updatedContentCache
            }

            lastSavedCardsIndexData = lastSavedCardsIndexData.filter { activeScenarioIDs.contains($0.key) }
            lastSavedHistoryData = lastSavedHistoryData.filter { activeScenarioIDs.contains($0.key) }
            lastSavedCardContent = lastSavedCardContent.filter { activeScenarioIDs.contains($0.key) }
            lastSavedAIThreadsData = lastSavedAIThreadsData.filter { activeScenarioIDs.contains($0.key) }

        } catch { }
    }

    private func primeSavedCachesFromCurrentState() {
        guard let payload = makeSavePayload() else { return }
        saveQueue.async { [weak self] in
            guard let self = self else { return }
            self.lastSavedScenarioRecordsData = payload.scenarioRecordsData
            self.lastSavedCardsIndexData = Dictionary(uniqueKeysWithValues: payload.scenarioPayloads.map { ($0.scenarioID, $0.cardRecordsData) })
            self.lastSavedHistoryData = Dictionary(uniqueKeysWithValues: payload.scenarioPayloads.map { ($0.scenarioID, $0.historyRecordsData) })
            self.lastSavedCardContent = Dictionary(uniqueKeysWithValues: payload.scenarioPayloads.map { ($0.scenarioID, $0.cardContentsByID) })
        }
    }

    func addScenario(title: String, fromTemplate template: Scenario? = nil) -> Scenario {
        let scenario = Scenario(title: title)
        _ = ensureScenarioFolder(for: scenario.id)
        if let template {
            scenario.cards = cloneCards(from: template, into: scenario)
        } else {
            let rootCard = SceneCard(content: title, orderIndex: 0, scenario: scenario)
            let plotCard = SceneCard(content: "플롯", orderIndex: 0, parent: rootCard, scenario: scenario, category: "플롯")
            let noteCard = SceneCard(content: "노트", orderIndex: 1, parent: rootCard, scenario: scenario, category: "노트")
            scenario.cards = [rootCard, plotCard, noteCard]
        }
        scenario.snapshots = []
        scenario.changeCountSinceLastSnapshot = 0
        scenario.bumpCardsVersion()
        scenarios.insert(scenario, at: 0)
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
        if let folderName = scenarioFolderByID[scenario.id] {
            let folder = folderURL.appendingPathComponent(folderName)
            try? fileManager.removeItem(at: folder)
            scenarioFolderByID.removeValue(forKey: scenario.id)
        }
        lastSavedAIThreadsData.removeValue(forKey: scenario.id)
        saveAll(immediate: true)
    }

    func removeCard(_ card: SceneCard, from scenario: Scenario) {
        let idsToRemove = collectCardIDs(from: card, scenario: scenario)
        scenario.cards.removeAll { idsToRemove.contains($0.id) }
        scenario.bumpCardsVersion()
        scenario.changeCountSinceLastSnapshot = 0
        saveAll(immediate: true)
    }

    private func collectCardIDs(from card: SceneCard, scenario: Scenario) -> Set<UUID> {
        var result: Set<UUID> = [card.id]
        for child in scenario.cards.filter({ $0.parent?.id == card.id }) {
            result.formUnion(collectCardIDs(from: child, scenario: scenario))
        }
        return result
    }

    private func createInitialScenario() {
        let scenario = Scenario(title: "제목 없음")
        _ = ensureScenarioFolder(for: scenario.id)
        let rootCard = SceneCard(content: "제목 없음", orderIndex: 0, scenario: scenario)
        let plotCard = SceneCard(content: "플롯", orderIndex: 0, parent: rootCard, scenario: scenario, category: "플롯")
        let noteCard = SceneCard(content: "노트", orderIndex: 1, parent: rootCard, scenario: scenario, category: "노트")
        scenario.cards = [rootCard, plotCard, noteCard]
        scenario.bumpCardsVersion()
        scenarios = [scenario]
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

    nonisolated private func writeCardContent(id: UUID, content: String, scenarioFolder: URL) {
        let url = cardFileURL(for: id, scenarioFolder: scenarioFolder)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    nonisolated private func cleanupOrphanCardFiles(validIDs: Set<UUID>, scenarioFolder: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: scenarioFolder, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("card_") && file.pathExtension == "txt" {
            let name = file.deletingPathExtension().lastPathComponent
            let idPart = name.replacingOccurrences(of: "card_", with: "")
            if let id = UUID(uuidString: idPart), !validIDs.contains(id) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    nonisolated private func cardFileURL(for id: UUID, scenarioFolder: URL) -> URL {
        scenarioFolder.appendingPathComponent("card_\(id.uuidString).txt")
    }

    private func ensureScenarioFolder(for scenarioID: UUID) -> String {
        if let existing = scenarioFolderByID[scenarioID] { return existing }
        let folderName = "\(scenarioFolderPrefix)\(scenarioID.uuidString)"
        scenarioFolderByID[scenarioID] = folderName
        return folderName
    }

    private func aiThreadsURL(for scenarioID: UUID) -> URL {
        let folderName = ensureScenarioFolder(for: scenarioID)
        let scenarioFolder = folderURL.appendingPathComponent(folderName)
        return scenarioFolder.appendingPathComponent(aiThreadsFile)
    }

    private func aiEmbeddingIndexURL(for scenarioID: UUID) -> URL {
        let folderName = ensureScenarioFolder(for: scenarioID)
        let scenarioFolder = folderURL.appendingPathComponent(folderName)
        return scenarioFolder.appendingPathComponent(aiEmbeddingIndexFile)
    }

    func aiVectorIndexURL(for scenarioID: UUID) -> URL {
        let folderName = ensureScenarioFolder(for: scenarioID)
        let scenarioFolder = folderURL.appendingPathComponent(folderName)
        return scenarioFolder.appendingPathComponent(aiVectorIndexFile)
    }

    func loadAIChatThreadsData(for scenarioID: UUID) async -> Data? {
        let url = aiThreadsURL(for: scenarioID)
        return await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try? Data(contentsOf: url)
        }.value
    }

    func saveAIChatThreadsData(_ data: Data?, for scenarioID: UUID) {
        let url = aiThreadsURL(for: scenarioID)
        let folder = url.deletingLastPathComponent()
        saveQueue.async { [weak self] in
            guard let self else { return }
            if let data {
                if self.lastSavedAIThreadsData[scenarioID] == data {
                    return
                }
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                do {
                    try data.write(to: url, options: .atomic)
                    self.lastSavedAIThreadsData[scenarioID] = data
                } catch { }
            } else {
                if FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                }
                self.lastSavedAIThreadsData.removeValue(forKey: scenarioID)
            }
        }
    }

    func loadAIEmbeddingIndexData(for scenarioID: UUID) async -> Data? {
        let url = aiEmbeddingIndexURL(for: scenarioID)
        return await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try? Data(contentsOf: url)
        }.value
    }

    func saveAIEmbeddingIndexData(_ data: Data?, for scenarioID: UUID) {
        let url = aiEmbeddingIndexURL(for: scenarioID)
        let folder = url.deletingLastPathComponent()
        saveQueue.async { [weak self] in
            guard let self else { return }
            if let data {
                if self.lastSavedAIEmbeddingIndexData[scenarioID] == data {
                    return
                }
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                do {
                    try data.write(to: url, options: .atomic)
                    self.lastSavedAIEmbeddingIndexData[scenarioID] = data
                } catch { }
            } else {
                if FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                }
                self.lastSavedAIEmbeddingIndexData.removeValue(forKey: scenarioID)
            }
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
