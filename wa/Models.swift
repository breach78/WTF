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
    @Published var cards: [SceneCard] {
        didSet {
            markCardRecordsDirty()
            markCardContentDirty()
            markModified()
        }
    }
    @Published var snapshots: [HistorySnapshot] {
        didSet {
            cachedSortedSnapshots = nil
            markHistoryDirty()
            markModified()
        }
    }
    @Published var linkedCardEditDatesByFocusCardID: [UUID: [UUID: Date]] {
        didSet {
            rebuildLinkedTargetCardCache()
            markLinkedCardsDirty()
            markModified()
        }
    }
    @Published private(set) var cardsVersion: Int = 0
    private(set) var cardRecordsSaveVersion: Int = 0
    private(set) var cardContentSaveVersion: Int = 0
    private(set) var historySaveVersion: Int = 0
    private(set) var linkedCardsSaveVersion: Int = 0
    private var cachedVersion: Int = -1
    private var cachedRoots: [SceneCard] = []
    private var cachedChildrenByParent: [UUID: [SceneCard]] = [:]
    private var cachedChildListSignatureByParentID: [UUID: Int] = [:]
    private var cachedCardsByID: [UUID: SceneCard] = [:]
    private var cachedCardLocationByID: [UUID: (level: Int, index: Int)] = [:]
    private var cachedCloneMembersByGroup: [UUID: [SceneCard]] = [:]
    private var cachedDescendantIDsByCardID: [UUID: Set<UUID>] = [:]
    private var cachedLevelCardsByCategory: [Int: [String: [SceneCard]]] = [:]
    private var activeCloneSyncGroupIDs: Set<UUID> = []
    private var cachedSortedSnapshots: [HistorySnapshot]?
    private var cachedLevels: [[SceneCard]] = []
    private var cachedRootListSignature: Int = 0
    private var timestampTrackingSuppressionCount: Int = 0
    private var interactiveTimestampSuppressionCount: Int = 0
    private var pendingModifiedTimestamp: Date?
    private var pendingModifiedWorkItem: DispatchWorkItem?
    private var lastAppliedModifiedAt: Date = .distantPast
    private let modifiedTimestampDebounceInterval: TimeInterval = 0.14
    private var cachedLinkedTargetCardIDs: Set<UUID> = []
    private(set) var sharedCraftTreeDirty: Bool = false
    var splitPaneActiveCardByPaneID: [Int: UUID] = [:]

    init(
        id: UUID = UUID(),
        title: String = "새 시나리오",
        isTemplate: Bool = false,
        timestamp: Date = Date(),
        changeCountSinceLastSnapshot: Int = 0,
        cards: [SceneCard] = [],
        snapshots: [HistorySnapshot] = [],
        linkedCardEditDatesByFocusCardID: [UUID: [UUID: Date]] = [:]
    ) {
        self.id = id
        self.title = title
        self.isTemplate = isTemplate
        self.timestamp = timestamp
        self.changeCountSinceLastSnapshot = changeCountSinceLastSnapshot
        self.cards = cards
        self.snapshots = snapshots
        self.linkedCardEditDatesByFocusCardID = linkedCardEditDatesByFocusCardID
        self.lastAppliedModifiedAt = timestamp
        rebuildLinkedTargetCardCache()
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

    func markSharedCraftDirty() {
        sharedCraftTreeDirty = true
    }

    func clearSharedCraftDirty() {
        sharedCraftTreeDirty = false
    }

    func markCardRecordsDirty() {
        cardRecordsSaveVersion &+= 1
    }

    func markCardContentDirty() {
        cardContentSaveVersion &+= 1
    }

    func markHistoryDirty() {
        historySaveVersion &+= 1
    }

    func markLinkedCardsDirty() {
        linkedCardsSaveVersion &+= 1
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

    func childListSignature(parentID: UUID?) -> Int {
        rebuildIndexIfNeeded()
        if let parentID {
            return cachedChildListSignatureByParentID[parentID] ?? 0
        }
        return cachedRootListSignature
    }

    func filteredCards(atLevel levelIndex: Int, category: String) -> [SceneCard] {
        rebuildIndexIfNeeded()
        return cachedLevelCardsByCategory[levelIndex]?[category] ?? []
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

    func descendantIDs(for cardID: UUID) -> Set<UUID> {
        rebuildIndexIfNeeded()
        return cachedDescendantIDsByCardID[cardID] ?? []
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

    func recordLinkedCard(focusCardID: UUID, linkedCardID: UUID, at date: Date = Date()) {
        guard focusCardID != linkedCardID else { return }
        let validIDs = Set(cards.map(\.id))
        guard validIDs.contains(focusCardID), validIDs.contains(linkedCardID) else { return }

        var byLinked = linkedCardEditDatesByFocusCardID[focusCardID] ?? [:]
        if let previous = byLinked[linkedCardID], previous >= date {
            return
        }
        byLinked[linkedCardID] = date
        linkedCardEditDatesByFocusCardID[focusCardID] = byLinked
    }

    func linkedCards(for focusCardID: UUID) -> [(cardID: UUID, lastEditedAt: Date)] {
        guard let byLinked = linkedCardEditDatesByFocusCardID[focusCardID], !byLinked.isEmpty else {
            return []
        }
        let validIDs = Set(cards.map(\.id))
        return byLinked
            .filter { validIDs.contains($0.key) }
            .map { (cardID: $0.key, lastEditedAt: $0.value) }
            .sorted {
                if $0.lastEditedAt != $1.lastEditedAt {
                    return $0.lastEditedAt > $1.lastEditedAt
                }
                return $0.cardID.uuidString < $1.cardID.uuidString
            }
    }

    func linkedCardEditDate(focusCardID: UUID, linkedCardID: UUID) -> Date? {
        linkedCardEditDatesByFocusCardID[focusCardID]?[linkedCardID]
    }

    func hasLinkedCards(_ focusCardID: UUID) -> Bool {
        guard let byLinked = linkedCardEditDatesByFocusCardID[focusCardID] else { return false }
        return !byLinked.isEmpty
    }

    func isLinkedCard(_ cardID: UUID) -> Bool {
        cachedLinkedTargetCardIDs.contains(cardID)
    }

    func disconnectLinkedCard(focusCardID: UUID, linkedCardID: UUID) {
        guard var byLinked = linkedCardEditDatesByFocusCardID[focusCardID] else { return }
        guard byLinked.removeValue(forKey: linkedCardID) != nil else { return }
        if byLinked.isEmpty {
            linkedCardEditDatesByFocusCardID.removeValue(forKey: focusCardID)
        } else {
            linkedCardEditDatesByFocusCardID[focusCardID] = byLinked
        }
    }

    func setLinkedCardRecords(_ records: [LinkedCardRecord]) {
        var map: [UUID: [UUID: Date]] = [:]
        for record in records {
            var byLinked = map[record.focusCardID] ?? [:]
            if let existing = byLinked[record.linkedCardID], existing >= record.lastEditedAt {
                continue
            }
            byLinked[record.linkedCardID] = record.lastEditedAt
            map[record.focusCardID] = byLinked
        }
        linkedCardEditDatesByFocusCardID = map
        pruneLinkedCards(validCardIDs: Set(cards.map(\.id)))
    }

    func linkedCardRecords() -> [LinkedCardRecord] {
        linkedCardEditDatesByFocusCardID
            .flatMap { focusID, byLinked in
                byLinked.map { linkedID, lastEditedAt in
                    LinkedCardRecord(
                        focusCardID: focusID,
                        linkedCardID: linkedID,
                        lastEditedAt: lastEditedAt
                    )
                }
            }
            .sorted {
                if $0.focusCardID != $1.focusCardID {
                    return $0.focusCardID.uuidString < $1.focusCardID.uuidString
                }
                if $0.lastEditedAt != $1.lastEditedAt {
                    return $0.lastEditedAt > $1.lastEditedAt
                }
                return $0.linkedCardID.uuidString < $1.linkedCardID.uuidString
            }
    }

    func pruneLinkedCards(validCardIDs: Set<UUID>) {
        var cleaned: [UUID: [UUID: Date]] = [:]
        for (focusID, byLinked) in linkedCardEditDatesByFocusCardID {
            guard validCardIDs.contains(focusID) else { continue }
            let validLinks = byLinked.filter { validCardIDs.contains($0.key) && $0.key != focusID }
            if !validLinks.isEmpty {
                cleaned[focusID] = validLinks
            }
        }
        if cleaned != linkedCardEditDatesByFocusCardID {
            linkedCardEditDatesByFocusCardID = cleaned
        }
    }

    func setSplitPaneActiveCard(_ cardID: UUID?, for paneID: Int) {
        guard paneID == 1 || paneID == 2 else { return }
        if let cardID {
            splitPaneActiveCardByPaneID[paneID] = cardID
        } else {
            splitPaneActiveCardByPaneID.removeValue(forKey: paneID)
        }
    }

    func splitPaneActiveCardID(for paneID: Int) -> UUID? {
        splitPaneActiveCardByPaneID[paneID]
    }

    private func rebuildLinkedTargetCardCache() {
        var ids: Set<UUID> = []
        ids.reserveCapacity(linkedCardEditDatesByFocusCardID.count * 2)
        for byLinked in linkedCardEditDatesByFocusCardID.values {
            ids.formUnion(byLinked.keys)
        }
        cachedLinkedTargetCardIDs = ids
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
        cachedRootListSignature = orderedCardIDSignature(roots)
        cachedChildListSignatureByParentID = childrenByParent.mapValues(orderedCardIDSignature(_:))
        cachedCardsByID = byID
        cachedCloneMembersByGroup = cloneMembersByGroup
        cachedDescendantIDsByCardID = buildDescendantIDIndex(childrenByParent: childrenByParent)
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
        var levelCardsByCategory: [Int: [String: [SceneCard]]] = [:]
        for (levelIndex, levelCards) in levels.enumerated() {
            guard !levelCards.isEmpty else { continue }
            var grouped: [String: [SceneCard]] = [:]
            grouped.reserveCapacity(3)
            for card in levelCards {
                let category = card.category ?? ScenarioCardCategory.uncategorized
                grouped[category, default: []].append(card)
            }
            levelCardsByCategory[levelIndex] = grouped
        }
        cachedLevels = levels
        cachedLevelCardsByCategory = levelCardsByCategory
        cachedCardLocationByID = locationByID
        cachedVersion = cardsVersion
    }

    private func orderedCardIDSignature(_ cards: [SceneCard]) -> Int {
        var hasher = Hasher()
        hasher.combine(cards.count)
        for card in cards {
            hasher.combine(card.id)
        }
        return hasher.finalize()
    }

    private func buildDescendantIDIndex(childrenByParent: [UUID: [SceneCard]]) -> [UUID: Set<UUID>] {
        var cache: [UUID: Set<UUID>] = [:]

        func descendants(for cardID: UUID) -> Set<UUID> {
            if let cached = cache[cardID] {
                return cached
            }
            let children = childrenByParent[cardID] ?? []
            var result: Set<UUID> = []
            result.reserveCapacity(children.count * 2)
            for child in children {
                result.insert(child.id)
                result.formUnion(descendants(for: child.id))
            }
            cache[cardID] = result
            return result
        }

        for cardID in cachedCardsByID.keys {
            _ = descendants(for: cardID)
        }

        return cache
    }
}

@MainActor
final class SceneCard: ObservableObject, Identifiable {
    let id: UUID
    @Published var content: String {
        didSet {
            guard !isApplyingCloneSynchronization else { return }
            scenario?.propagateCloneContent(from: self, content: content)
            scenario?.markCardContentDirty()
            markSharedCraftDirtyIfNeeded()
            scenario?.markModified()
        }
    }
    @Published var orderIndex: Int {
        didSet {
            scenario?.markCardRecordsDirty()
            markSharedCraftDirtyIfNeeded()
            scenario?.bumpCardsVersion()
            scenario?.markModified()
        }
    }
    @Published var createdAt: Date
    @Published var parent: SceneCard? {
        didSet {
            scenario?.markCardRecordsDirty()
            markSharedCraftDirtyIfNeeded()
            scenario?.bumpCardsVersion()
            scenario?.markModified()
        }
    }
    weak var scenario: Scenario?
    @Published var category: String? {
        didSet {
            scenario?.markCardRecordsDirty()
            markSharedCraftDirtyIfNeeded(previousCategory: oldValue)
            scenario?.markModified()
        }
    }
    @Published var isFloating: Bool {
        didSet {
            scenario?.markCardRecordsDirty()
            markSharedCraftDirtyIfNeeded()
            scenario?.bumpCardsVersion()
            scenario?.markModified()
        }
    }
    @Published var isArchived: Bool {
        didSet {
            scenario?.markCardRecordsDirty()
            markSharedCraftDirtyIfNeeded()
            scenario?.bumpCardsVersion()
            scenario?.markModified()
        }
    }
    @Published var lastSelectedChildID: UUID? {
        didSet {
            scenario?.markCardRecordsDirty()
        }
    }
    @Published var colorHex: String? {
        didSet {
            guard !isApplyingCloneSynchronization else { return }
            scenario?.propagateCloneColor(from: self, colorHex: colorHex)
            scenario?.markCardRecordsDirty()
            markSharedCraftDirtyIfNeeded()
            scenario?.markModified()
        }
    }
    @Published var cloneGroupID: UUID? {
        didSet {
            scenario?.markCardRecordsDirty()
            markSharedCraftDirtyIfNeeded()
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

    private func markSharedCraftDirtyIfNeeded(previousCategory: String? = nil) {
        guard category == ScenarioCardCategory.craft || previousCategory == ScenarioCardCategory.craft else {
            return
        }
        scenario?.markSharedCraftDirty()
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
    private let currentSchemaVersion = 3
    private let sharedCraftRootCardID = UUID(uuidString: "F2EE98E5-93B4-4F58-85A3-3D0C89B1C3E1")!
    @Published var scenarios: [Scenario] = []
    let folderURL: URL

    private let fileManager = FileManager.default
    private let scenariosFile = "scenarios.json"
    private let cardsFile = "cards_index.json"
    private let historyFile = "history.json"
    private let linkedCardsFile = "linked_cards.json"
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
        let linkedCardsData: Data
        let cardContentsByID: [UUID: String]
        let validCardIDs: Set<UUID>
    }

    private struct SavePayload {
        let scenarioRecordsData: Data
        let scenarioPayloads: [ScenarioSavePayload]
    }

    private struct ScenarioPayloadCacheEntry {
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

    private struct SharedCraftTreeNodeSnapshot: Equatable {
        let id: UUID
        let content: String
        let createdAt: Date
        let colorHex: String?
        let cloneGroupID: UUID?
        let isAICandidate: Bool
        let children: [SharedCraftTreeNodeSnapshot]
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
    private nonisolated(unsafe) var lastSavedLinkedCardsData: [UUID: Data] = [:]
    private nonisolated(unsafe) var lastSavedAIThreadsData: [UUID: Data] = [:]
    private nonisolated(unsafe) var lastSavedAIEmbeddingIndexData: [UUID: Data] = [:]
    private var scenarioPayloadCacheByID: [UUID: ScenarioPayloadCacheEntry] = [:]

    init(folderURL: URL) {
        self.folderURL = folderURL
        saveQueue.setSpecific(key: saveQueueKey, value: ())
    }

    nonisolated private var scenariosURL: URL { folderURL.appendingPathComponent(scenariosFile) }

    private struct ScenarioLoadResult {
        let scenarioID: UUID
        let cardRecords: [CardRecord]
        let historyRecords: [HistorySnapshotRecord]
        let linkedCardRecords: [LinkedCardRecord]
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

    private func orderedCards(_ cards: [SceneCard]) -> [SceneCard] {
        cards.sorted {
            if $0.orderIndex != $1.orderIndex {
                return $0.orderIndex < $1.orderIndex
            }
            return $0.createdAt < $1.createdAt
        }
    }

    private func primaryRootCard(in scenario: Scenario) -> SceneCard? {
        orderedCards(scenario.rootCards).first
    }

    private func directChildren(of parent: SceneCard, in scenario: Scenario) -> [SceneCard] {
        orderedCards(scenario.children(for: parent.id))
    }

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

    private func defaultSharedCraftSnapshot() -> SharedCraftTreeNodeSnapshot {
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

    private func currentSharedCraftSnapshot(from sourceScenario: Scenario? = nil) -> SharedCraftTreeNodeSnapshot {
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

    private func applySharedCraftSnapshot(
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

    private func synchronizeSharedCraftTrees(
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
                    let scenarioLinkedCardsURL = scenarioFolder.appendingPathComponent(self.linkedCardsFile)

                    group.addTask {
                        let perDecoder = JSONDecoder()
                        perDecoder.dateDecodingStrategy = .iso8601

                        guard let cardRecords: [CardRecord] = (try? self.readJSONSync(url: scenarioCardsURL, decoder: perDecoder)) else { return nil }
                        let historyRecords: [HistorySnapshotRecord] = (try? self.readJSONSync(url: scenarioHistoryURL, decoder: perDecoder)) ?? []
                        let linkedCardRecords: [LinkedCardRecord] = (try? self.readJSONSync(url: scenarioLinkedCardsURL, decoder: perDecoder)) ?? []

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
                    scenario.setLinkedCardRecords(result.linkedCardRecords)
                }
            }

            scenarios = scenarioMap.values.sorted(by: scenarioSortComparator)

            if scenarios.isEmpty {
                createInitialScenario()
            } else {
                synchronizeSharedCraftTrees(preserveExistingTimestamps: true, force: true)
                for scenario in scenarios {
                    scenario.bumpCardsVersion()
                }
                primeSavedCachesFromCurrentState()
            }
    }

    func saveAll(immediate: Bool = false) {
        for scenario in scenarios {
            scenario.flushPendingModifiedTimestamp()
        }
        synchronizeSharedCraftTrees(preserveExistingTimestamps: true)
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

            for scenario in scenarios {
                scenario.pruneLinkedCards(validCardIDs: Set(scenario.cards.map(\.id)))
            }

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
                        return try encoder.encode(scenario.linkedCardRecords())
                    }
                    return cachedPayload.linkedCardsData
                }()

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
        var cardRecordsData: Data
        var historyRecordsData: Data
        var linkedCardsData: Data
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
                lastSavedCardContent[r.scenarioID] = r.updatedContentCache
            }

            lastSavedCardsIndexData = lastSavedCardsIndexData.filter { activeScenarioIDs.contains($0.key) }
            lastSavedHistoryData = lastSavedHistoryData.filter { activeScenarioIDs.contains($0.key) }
            lastSavedCardContent = lastSavedCardContent.filter { activeScenarioIDs.contains($0.key) }
            lastSavedLinkedCardsData = lastSavedLinkedCardsData.filter { activeScenarioIDs.contains($0.key) }
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
            let plotCard = SceneCard(content: ScenarioCardCategory.plot, orderIndex: 0, parent: rootCard, scenario: scenario, category: ScenarioCardCategory.plot)
            let noteCard = SceneCard(content: ScenarioCardCategory.note, orderIndex: 1, parent: rootCard, scenario: scenario, category: ScenarioCardCategory.note)
            scenario.cards = [rootCard, plotCard, noteCard]
        }
        applySharedCraftSnapshot(currentSharedCraftSnapshot(), to: scenario, preserveTimestamp: false)
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
        lastSavedLinkedCardsData.removeValue(forKey: scenario.id)
        lastSavedAIThreadsData.removeValue(forKey: scenario.id)
        lastSavedAIEmbeddingIndexData.removeValue(forKey: scenario.id)
        saveAll(immediate: true)
    }

    func removeCard(_ card: SceneCard, from scenario: Scenario) {
        let idsToRemove = collectCardIDs(from: card, scenario: scenario)
        scenario.cards.removeAll { idsToRemove.contains($0.id) }
        scenario.pruneLinkedCards(validCardIDs: Set(scenario.cards.map(\.id)))
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
        let plotCard = SceneCard(content: ScenarioCardCategory.plot, orderIndex: 0, parent: rootCard, scenario: scenario, category: ScenarioCardCategory.plot)
        let noteCard = SceneCard(content: ScenarioCardCategory.note, orderIndex: 1, parent: rootCard, scenario: scenario, category: ScenarioCardCategory.note)
        scenario.cards = [rootCard, plotCard, noteCard]
        applySharedCraftSnapshot(defaultSharedCraftSnapshot(), to: scenario, preserveTimestamp: false)
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

struct LinkedCardRecord: Codable, Equatable {
    let focusCardID: UUID
    let linkedCardID: UUID
    let lastEditedAt: Date
}
