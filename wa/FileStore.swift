import Foundation
import Combine

@MainActor
final class FileStore: ObservableObject {
    let currentSchemaVersion = 3
    let sharedCraftRootCardID = UUID(uuidString: "F2EE98E5-93B4-4F58-85A3-3D0C89B1C3E1")!
    @Published var scenarios: [Scenario] = []
    @Published var indexBoardSummaryRecordsByScenarioID: [UUID: [UUID: IndexBoardCardSummaryRecord]] = [:]
    let folderURL: URL

    let fileManager = FileManager.default
    let scenariosFile = "scenarios.json"
    let cardsFile = "cards_index.json"
    let historyFile = "history.json"
    let linkedCardsFile = "linked_cards.json"
    let cardSummariesFile = "card_summaries.json"
    let aiThreadsFile = "ai_threads.json"
    let aiEmbeddingIndexFile = "ai_embedding_index.json"
    let aiVectorIndexFile = "ai_vector_index.sqlite"
    let scenarioFolderPrefix = "scenario_"
    let saveDebounceInterval: TimeInterval = 0.55
    var scenarioFolderByID: [UUID: String] = [:]

    struct ScenarioSavePayload {
        let scenarioID: UUID
        let folderName: String
        let cardRecordsData: Data
        let historyRecordsData: Data
        let linkedCardsData: Data
        let summaryRecordsData: Data
        let cardContentsByID: [UUID: String]
        let validCardIDs: Set<UUID>
    }

    struct SavePayload {
        let scenarioRecordsData: Data
        let scenarioPayloads: [ScenarioSavePayload]
    }

    struct ScenarioPayloadCacheEntry {
        let cardRecordsVersion: Int
        let cardContentVersion: Int
        let historyVersion: Int
        let linkedCardsVersion: Int
        let validCardIDs: Set<UUID>
        let cardRecordsData: Data
        let historyRecordsData: Data
        let linkedCardsData: Data
        let cardContentsByID: [UUID: String]
    }

    struct SharedCraftTreeNodeSnapshot: Equatable {
        let id: UUID
        let content: String
        let createdAt: Date
        let colorHex: String?
        let cloneGroupID: UUID?
        let isAICandidate: Bool
        let children: [SharedCraftTreeNodeSnapshot]
    }

    let concurrentIOQueue = DispatchQueue(label: "wa.filestore.io.concurrent", qos: .utility, attributes: .concurrent)
    let saveQueue = DispatchQueue(label: "wa.filestore.save.queue", qos: .utility)
    let saveQueueKey = DispatchSpecificKey<Void>()
    var saveDebounceWorkItem: DispatchWorkItem?
    nonisolated(unsafe) var saveWorkerRunning: Bool = false
    nonisolated(unsafe) var pendingPayload: SavePayload?

    // Dirty caches: unchanged payloads are skipped. Accessed only from saveQueue.
    nonisolated(unsafe) var lastSavedScenarioRecordsData: Data?
    nonisolated(unsafe) var lastSavedCardsIndexData: [UUID: Data] = [:]
    nonisolated(unsafe) var lastSavedHistoryData: [UUID: Data] = [:]
    nonisolated(unsafe) var lastSavedCardContent: [UUID: [UUID: String]] = [:]
    nonisolated(unsafe) var lastSavedLinkedCardsData: [UUID: Data] = [:]
    nonisolated(unsafe) var lastSavedCardSummariesData: [UUID: Data] = [:]
    nonisolated(unsafe) var lastSavedAIThreadsData: [UUID: Data] = [:]
    nonisolated(unsafe) var lastSavedAIEmbeddingIndexData: [UUID: Data] = [:]
    var scenarioPayloadCacheByID: [UUID: ScenarioPayloadCacheEntry] = [:]
    var scenarioMetadataObservationByID: [UUID: Set<AnyCancellable>] = [:]
    var scenarioResortWorkItem: DispatchWorkItem?

    init(folderURL: URL) {
        self.folderURL = folderURL
        saveQueue.setSpecific(key: saveQueueKey, value: ())
    }
}
