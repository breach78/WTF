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
    private var cardMutationBatchDepth: Int = 0
    private var pendingCardsVersionBump: Bool = false
    private var pendingCardRecordsDirty: Bool = false
    private var pendingCardContentDirty: Bool = false
    private var pendingHistoryDirty: Bool = false
    private var pendingLinkedCardsDirty: Bool = false
    private var pendingSharedCraftDirty: Bool = false
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
        guard totalMutationSuppressionCount == 0 else {
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
            guard self.totalMutationSuppressionCount == 0 else { return }
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
            if totalMutationSuppressionCount == 0 {
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
        if flush, totalMutationSuppressionCount == 0 {
            flushPendingModifiedTimestamp()
        }
    }

    func flushPendingModifiedTimestamp() {
        pendingModifiedWorkItem?.cancel()
        pendingModifiedWorkItem = nil
        guard totalMutationSuppressionCount == 0 else { return }
        guard let pending = pendingModifiedTimestamp else { return }
        pendingModifiedTimestamp = nil
        applyModifiedTimestamp(pending)
    }

    func persistedTimestamp() -> Date {
        pendingModifiedTimestamp ?? timestamp
    }

    private var totalTimestampSuppressionCount: Int {
        timestampTrackingSuppressionCount + interactiveTimestampSuppressionCount
    }

    private var totalMutationSuppressionCount: Int {
        totalTimestampSuppressionCount + cardMutationBatchDepth
    }

    var isCardMutationBatchInProgress: Bool {
        cardMutationBatchDepth > 0
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
        if cardMutationBatchDepth > 0 {
            pendingCardsVersionBump = true
            return
        }
        cardsVersion += 1
    }

    func markSharedCraftDirty() {
        if cardMutationBatchDepth > 0 {
            pendingSharedCraftDirty = true
            return
        }
        sharedCraftTreeDirty = true
    }

    func clearSharedCraftDirty() {
        sharedCraftTreeDirty = false
    }

    func markCardRecordsDirty() {
        if cardMutationBatchDepth > 0 {
            pendingCardRecordsDirty = true
            return
        }
        cardRecordsSaveVersion &+= 1
    }

    func markCardContentDirty() {
        if cardMutationBatchDepth > 0 {
            pendingCardContentDirty = true
            return
        }
        cardContentSaveVersion &+= 1
    }

    func markHistoryDirty() {
        if cardMutationBatchDepth > 0 {
            pendingHistoryDirty = true
            return
        }
        historySaveVersion &+= 1
    }

    func markLinkedCardsDirty() {
        if cardMutationBatchDepth > 0 {
            pendingLinkedCardsDirty = true
            return
        }
        linkedCardsSaveVersion &+= 1
    }

    func performBatchedCardMutation(_ work: () -> Void) {
        cardMutationBatchDepth += 1
        defer {
            cardMutationBatchDepth = max(0, cardMutationBatchDepth - 1)
            if cardMutationBatchDepth == 0 {
                flushBatchedCardMutationIfNeeded()
            }
        }
        work()
    }

    private func flushBatchedCardMutationIfNeeded() {
        if pendingCardRecordsDirty {
            cardRecordsSaveVersion &+= 1
            pendingCardRecordsDirty = false
        }
        if pendingCardContentDirty {
            cardContentSaveVersion &+= 1
            pendingCardContentDirty = false
        }
        if pendingHistoryDirty {
            historySaveVersion &+= 1
            pendingHistoryDirty = false
        }
        if pendingLinkedCardsDirty {
            linkedCardsSaveVersion &+= 1
            pendingLinkedCardsDirty = false
        }
        if pendingSharedCraftDirty {
            sharedCraftTreeDirty = true
            pendingSharedCraftDirty = false
        }
        if pendingCardsVersionBump {
            cardsVersion += 1
            pendingCardsVersionBump = false
        }
        flushPendingModifiedTimestamp()
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
        return computeDescendantIDs(for: cardID)
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

    func linkedCardRecords(validCardIDs: Set<UUID>? = nil) -> [LinkedCardRecord] {
        let validIDs = validCardIDs ?? Set(cards.map(\.id))
        var records: [LinkedCardRecord] = []
        records.reserveCapacity(linkedCardEditDatesByFocusCardID.count * 2)

        for (focusID, byLinked) in linkedCardEditDatesByFocusCardID {
            guard validIDs.contains(focusID) else { continue }
            for (linkedID, lastEditedAt) in byLinked {
                guard validIDs.contains(linkedID), linkedID != focusID else { continue }
                records.append(
                    LinkedCardRecord(
                        focusCardID: focusID,
                        linkedCardID: linkedID,
                        lastEditedAt: lastEditedAt
                    )
                )
            }
        }

        return records.sorted { (lhs: LinkedCardRecord, rhs: LinkedCardRecord) in
            if lhs.focusCardID != rhs.focusCardID {
                return lhs.focusCardID.uuidString < rhs.focusCardID.uuidString
            }
            if lhs.lastEditedAt != rhs.lastEditedAt {
                return lhs.lastEditedAt > rhs.lastEditedAt
            }
            return lhs.linkedCardID.uuidString < rhs.linkedCardID.uuidString
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
        roots.sort {
            if $0.orderIndex != $1.orderIndex {
                return $0.orderIndex < $1.orderIndex
            }
            return $0.createdAt < $1.createdAt
        }
        for key in childrenByParent.keys {
            childrenByParent[key]?.sort {
                if $0.orderIndex != $1.orderIndex {
                    return $0.orderIndex < $1.orderIndex
                }
                return $0.createdAt < $1.createdAt
            }
        }
        cachedRoots = roots
        cachedChildrenByParent = childrenByParent
        cachedRootListSignature = orderedCardIDSignature(roots)
        cachedChildListSignatureByParentID = childrenByParent.mapValues(orderedCardIDSignature(_:))
        cachedCardsByID = byID
        cachedCloneMembersByGroup = cloneMembersByGroup
        cachedDescendantIDsByCardID = [:]
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

    private func computeDescendantIDs(for cardID: UUID) -> Set<UUID> {
        if let cached = cachedDescendantIDsByCardID[cardID] {
            return cached
        }
        let children = cachedChildrenByParent[cardID] ?? []
        var result: Set<UUID> = []
        result.reserveCapacity(children.count * 2)
        for child in children {
            result.insert(child.id)
            result.formUnion(computeDescendantIDs(for: child.id))
        }
        cachedDescendantIDsByCardID[cardID] = result
        return result
    }
}

