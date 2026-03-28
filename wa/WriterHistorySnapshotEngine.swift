import SwiftUI

enum ScenarioHistoryEngine {
    nonisolated static func snapshotOrderLess(_ lhs: CardSnapshot, _ rhs: CardSnapshot) -> Bool {
        if lhs.orderIndex != rhs.orderIndex {
            return lhs.orderIndex < rhs.orderIndex
        }
        return lhs.cardID.uuidString < rhs.cardID.uuidString
    }

    static func retentionRule(
        forAge age: TimeInterval
    ) -> (tier: HistoryRetentionTier, interval: TimeInterval) {
        if age <= 60 * 60 {
            return (.recentHour, 60)
        }
        if age <= 60 * 60 * 24 {
            return (.recentDay, 60 * 10)
        }
        if age <= 60 * 60 * 24 * 7 {
            return (.recentWeek, 60 * 60)
        }
        if age <= 60 * 60 * 24 * 30 {
            return (.recentMonth, 60 * 60 * 24)
        }
        return (.archive, 60 * 60 * 24 * 7)
    }

    static func sortedCardSnapshots(
        from state: [UUID: CardSnapshot]
    ) -> [CardSnapshot] {
        let byParent = Dictionary(grouping: state.values) { $0.parentID }
        var ordered: [CardSnapshot] = []
        var visited = Set<UUID>()

        func appendSubtree(parentID: UUID?) {
            let children = (byParent[parentID] ?? []).sorted(by: snapshotOrderLess)
            for snapshot in children {
                if visited.insert(snapshot.cardID).inserted {
                    ordered.append(snapshot)
                    appendSubtree(parentID: snapshot.cardID)
                }
            }
        }

        appendSubtree(parentID: nil)

        let remaining = state.values
            .filter { !visited.contains($0.cardID) }
            .sorted(by: snapshotOrderLess)
        for snapshot in remaining {
            if visited.insert(snapshot.cardID).inserted {
                ordered.append(snapshot)
                appendSubtree(parentID: snapshot.cardID)
            }
        }

        return ordered
    }

    static func buildDeltaPayload(
        from previousMap: [UUID: CardSnapshot],
        to currentMap: [UUID: CardSnapshot]
    ) -> (changed: [CardSnapshot], deleted: [UUID]) {
        var changed: [CardSnapshot] = []
        for snapshot in currentMap.values {
            if previousMap[snapshot.cardID] != snapshot {
                changed.append(snapshot)
            }
        }
        changed.sort(by: snapshotOrderLess)
        let deleted = previousMap.keys
            .filter { currentMap[$0] == nil }
            .sorted { $0.uuidString < $1.uuidString }
        return (changed, deleted)
    }

    static func shouldInsertFullSnapshotCheckpoint(
        in snapshots: [HistorySnapshot],
        checkpointInterval: Int
    ) -> Bool {
        if snapshots.isEmpty { return true }
        var trailingDeltaCount = 0
        for snapshot in snapshots.reversed() {
            if snapshot.isDelta {
                trailingDeltaCount += 1
            } else {
                break
            }
        }
        return trailingDeltaCount >= checkpointInterval
    }

    static func applySnapshotState(
        _ snapshot: HistorySnapshot,
        to state: inout [UUID: CardSnapshot]
    ) {
        if snapshot.isDelta {
            for deletedID in snapshot.deletedCardIDs {
                state.removeValue(forKey: deletedID)
            }
            for changed in snapshot.cardSnapshots {
                state[changed.cardID] = changed
            }
            return
        }
        state.removeAll(keepingCapacity: true)
        for cardSnapshot in snapshot.cardSnapshots {
            state[cardSnapshot.cardID] = cardSnapshot
        }
        for deletedID in snapshot.deletedCardIDs {
            state.removeValue(forKey: deletedID)
        }
    }
}

extension ScenarioWriterView {
    func takeSnapshot(
        force: Bool = false,
        name: String? = nil,
        initialNamedNote: String? = nil,
        attachNamedNote: Bool = true
    ) {
        let normalizedName = normalizedSnapshotName(name)
        if !force && normalizedName == nil {
            scenario.changeCountSinceLastSnapshot += 1
            if scenario.changeCountSinceLastSnapshot < 5 { return }
        }
        if let name = normalizedName {
            let noteCardID: UUID? = attachNamedNote
                ? createNamedSnapshotNoteCard(title: name, initialBody: initialNamedNote)?.id
                : nil
            guard let namedSnapshot = buildHistorySnapshot(name: name, forceFull: true) else { return }
            namedSnapshot.noteCardID = noteCardID
            scenario.snapshots.append(namedSnapshot)
            // 현재 상태를 "최신"으로 남기기 위한 즉시 스냅샷
            if let currentSnapshot = buildHistorySnapshot(name: nil, allowEmptyDelta: true) {
                scenario.snapshots.append(currentSnapshot)
            }
            scenario.changeCountSinceLastSnapshot = 0
            applyHistoryRetentionPolicyIfNeeded()
            requestHistoryAutosave(immediate: true)
            DispatchQueue.main.async {
                self.historyIndex = Double(max(0, self.scenario.sortedSnapshots.count - 1))
                if self.showHistoryBar {
                    self.syncNamedSnapshotNoteForCurrentSelection(focusEditor: false)
                }
            }
            return
        }
        guard let newSnapshot = buildHistorySnapshot(name: nil) else { return }
        scenario.snapshots.append(newSnapshot)
        scenario.changeCountSinceLastSnapshot = 0
        applyHistoryRetentionPolicyIfNeeded()
        requestHistoryAutosave(immediate: true)
        DispatchQueue.main.async { self.historyIndex = Double(max(0, self.scenario.sortedSnapshots.count - 1)) }
    }
    struct HistoryPromotionDecision {
        let isPromoted: Bool
        let reason: String?
    }

    func buildHistorySnapshot(
        name: String?,
        forceFull: Bool = false,
        allowEmptyDelta: Bool = false
    ) -> HistorySnapshot? {
        let currentCardSnapshots = scenario.cards.map { CardSnapshot(from: $0) }
        let currentMap = Dictionary(uniqueKeysWithValues: currentCardSnapshots.map { ($0.cardID, $0) })
        let timestamp = nextSnapshotTimestamp()
        let previousMap = resolvedCardSnapshotMap(
            at: scenario.snapshots.count - 1,
            in: scenario.snapshots
        )
        let shouldBuildFull = forceFull || shouldInsertFullSnapshotCheckpoint(in: scenario.snapshots)
        if shouldBuildFull {
            let deltaFromPrevious = buildDeltaPayload(from: previousMap ?? [:], to: currentMap)
            let promotion = evaluateHistoryPromotion(
                name: name,
                timestamp: timestamp,
                previousMap: previousMap,
                currentMap: currentMap,
                changedSnapshots: deltaFromPrevious.changed,
                deletedCardIDs: deltaFromPrevious.deleted
            )
            return HistorySnapshot(
                timestamp: timestamp,
                name: name,
                scenarioID: scenario.id,
                cardSnapshots: currentCardSnapshots,
                isDelta: false,
                deletedCardIDs: [],
                isPromoted: promotion.isPromoted,
                promotionReason: promotion.reason
            )
        }

        guard let previousMap else {
            let promotion = evaluateHistoryPromotion(
                name: name,
                timestamp: timestamp,
                previousMap: nil,
                currentMap: currentMap,
                changedSnapshots: currentCardSnapshots,
                deletedCardIDs: []
            )
            return HistorySnapshot(
                timestamp: timestamp,
                name: name,
                scenarioID: scenario.id,
                cardSnapshots: currentCardSnapshots,
                isDelta: false,
                deletedCardIDs: [],
                isPromoted: promotion.isPromoted,
                promotionReason: promotion.reason
            )
        }

        let deltaPayload = buildDeltaPayload(from: previousMap, to: currentMap)
        let changedSnapshots = deltaPayload.changed
        let deletedCardIDs = deltaPayload.deleted

        if !allowEmptyDelta && changedSnapshots.isEmpty && deletedCardIDs.isEmpty {
            return nil
        }
        let promotion = evaluateHistoryPromotion(
            name: name,
            timestamp: timestamp,
            previousMap: previousMap,
            currentMap: currentMap,
            changedSnapshots: changedSnapshots,
            deletedCardIDs: deletedCardIDs
        )

        return HistorySnapshot(
            timestamp: timestamp,
            name: name,
            scenarioID: scenario.id,
            cardSnapshots: changedSnapshots,
            isDelta: true,
            deletedCardIDs: deletedCardIDs,
            isPromoted: promotion.isPromoted,
            promotionReason: promotion.reason
        )
    }

    func evaluateHistoryPromotion(
        name: String?,
        timestamp: Date,
        previousMap: [UUID: CardSnapshot]?,
        currentMap: [UUID: CardSnapshot],
        changedSnapshots: [CardSnapshot],
        deletedCardIDs: [UUID]
    ) -> HistoryPromotionDecision {
        if let name, !name.isEmpty {
            return HistoryPromotionDecision(isPromoted: true, reason: "named")
        }
        guard let previousMap else {
            return HistoryPromotionDecision(isPromoted: true, reason: "initial")
        }

        let addedCardIDs = currentMap.keys.filter { previousMap[$0] == nil }
        if !addedCardIDs.isEmpty || !deletedCardIDs.isEmpty {
            return HistoryPromotionDecision(isPromoted: true, reason: "structure-add-delete")
        }

        for changed in changedSnapshots {
            guard let previous = previousMap[changed.cardID] else { continue }
            if previous.parentID != changed.parentID ||
                previous.orderIndex != changed.orderIndex ||
                previous.category != changed.category ||
                previous.isFloating != changed.isFloating ||
                previous.isArchived != changed.isArchived ||
                previous.cloneGroupID != changed.cloneGroupID {
                return HistoryPromotionDecision(isPromoted: true, reason: "structure-move")
            }
        }

        let changedCardCount = changedSnapshots.count + deletedCardIDs.count
        let editScore = historyEditScore(
            previousMap: previousMap,
            changedSnapshots: changedSnapshots,
            deletedCardIDs: deletedCardIDs
        )
        if changedCardCount >= historyPromotionChangedCardsThreshold ||
            editScore >= historyPromotionLargeEditScoreThreshold {
            return HistoryPromotionDecision(isPromoted: true, reason: "large-edit")
        }

        if let lastTimestamp = scenario.snapshots.last?.timestamp,
           timestamp.timeIntervalSince(lastTimestamp) >= historyPromotionSessionGapThreshold {
            return HistoryPromotionDecision(isPromoted: true, reason: "session-gap")
        }

        return HistoryPromotionDecision(isPromoted: false, reason: nil)
    }

    func historyEditScore(
        previousMap: [UUID: CardSnapshot],
        changedSnapshots: [CardSnapshot],
        deletedCardIDs: [UUID]
    ) -> Int {
        var score = 0
        for changed in changedSnapshots {
            if let previous = previousMap[changed.cardID], previous.content != changed.content {
                score += max(previous.content.count, changed.content.count)
            } else if previousMap[changed.cardID] == nil {
                score += changed.content.count
            }
        }
        for deletedID in deletedCardIDs {
            if let deleted = previousMap[deletedID] {
                score += deleted.content.count
            }
        }
        return score
    }

    func applyHistoryRetentionPolicyIfNeeded(force: Bool = false) {
        let snapshots = scenario.sortedSnapshots
        let count = snapshots.count
        if !force {
            guard count >= historyRetentionMinimumCount else { return }
            let progressed = count - historyRetentionLastAppliedCount
            guard progressed >= historyRetentionApplyStride else { return }
        }

        let compacted = compactHistorySnapshots(snapshots, now: Date())
        historyRetentionLastAppliedCount = compacted.count
        guard compacted.count < count else { return }

        scenario.snapshots = compacted
        if isPreviewingHistory {
            let clamped = min(max(Int(historyIndex), 0), max(0, compacted.count - 1))
            historyIndex = Double(clamped)
            enterPreviewMode(at: clamped)
        } else {
            historyIndex = Double(max(0, compacted.count - 1))
        }
    }

    func compactHistorySnapshots(_ snapshots: [HistorySnapshot], now: Date) -> [HistorySnapshot] {
        guard snapshots.count > historyRetentionMinimumCount else { return snapshots }
        let keptIndices = retainedHistoryIndices(from: snapshots, now: now)
        guard keptIndices.count < snapshots.count else { return snapshots }
        return rebuildHistorySnapshots(from: snapshots, keeping: keptIndices)
    }

    func retainedHistoryIndices(from snapshots: [HistorySnapshot], now: Date) -> [Int] {
        guard !snapshots.isEmpty else { return [] }
        var keep = Set<Int>()
        keep.insert(0)
        keep.insert(snapshots.count - 1)

        var bucketLatest: [String: Int] = [:]
        for index in snapshots.indices {
            let snapshot = snapshots[index]
            if isSnapshotPromoted(snapshot) {
                keep.insert(index)
                continue
            }
            let age = max(0, now.timeIntervalSince(snapshot.timestamp))
            let rule = historyRetentionRule(forAge: age)
            let bucket = Int(floor(snapshot.timestamp.timeIntervalSince1970 / rule.interval))
            let key = "\(rule.tier.rawValue):\(bucket)"
            if let existing = bucketLatest[key] {
                if snapshots[existing].timestamp <= snapshot.timestamp {
                    bucketLatest[key] = index
                }
            } else {
                bucketLatest[key] = index
            }
        }
        for index in bucketLatest.values {
            keep.insert(index)
        }
        return keep.sorted()
    }

    func historyRetentionRule(forAge age: TimeInterval) -> (tier: HistoryRetentionTier, interval: TimeInterval) {
        ScenarioHistoryEngine.retentionRule(forAge: age)
    }

    func rebuildHistorySnapshots(from snapshots: [HistorySnapshot], keeping keptIndices: [Int]) -> [HistorySnapshot] {
        guard !keptIndices.isEmpty else { return snapshots }
        let keepSet = Set(keptIndices)
        let statesByIndex = historyStatesByIndex(from: snapshots, keepSet: keepSet)

        var rebuilt: [HistorySnapshot] = []
        var previousState: [UUID: CardSnapshot]? = nil
        var trailingDeltaCount = 0
        let latestIndex = snapshots.count - 1

        for index in keptIndices {
            guard let currentState = statesByIndex[index] else { continue }
            let original = snapshots[index]
            let promoted = isSnapshotPromoted(original)
            let shouldForceFull = shouldForceFullHistorySnapshot(
                rebuiltIsEmpty: rebuilt.isEmpty,
                index: index,
                latestIndex: latestIndex,
                promoted: promoted,
                isDeltaSnapshot: original.isDelta,
                trailingDeltaCount: trailingDeltaCount
            )

            if shouldForceFull || previousState == nil {
                rebuilt.append(fullHistorySnapshot(from: original, state: currentState, promoted: promoted))
                previousState = currentState
                trailingDeltaCount = 0
                continue
            }

            let delta = buildDeltaPayload(from: previousState ?? [:], to: currentState)
            if delta.changed.isEmpty && delta.deleted.isEmpty {
                if index == latestIndex || promoted {
                    rebuilt.append(fullHistorySnapshot(from: original, state: currentState, promoted: promoted))
                    previousState = currentState
                    trailingDeltaCount = 0
                }
                continue
            }

            rebuilt.append(deltaHistorySnapshot(from: original, delta: delta, promoted: promoted))
            previousState = currentState
            trailingDeltaCount += 1
        }

        if rebuilt.isEmpty,
           let fallback = fallbackLatestRebuiltHistorySnapshot(statesByIndex: statesByIndex, snapshots: snapshots, latestIndex: latestIndex) {
            return [fallback]
        }
        return rebuilt
    }

    func historyStatesByIndex(
        from snapshots: [HistorySnapshot],
        keepSet: Set<Int>
    ) -> [Int: [UUID: CardSnapshot]] {
        var statesByIndex: [Int: [UUID: CardSnapshot]] = [:]
        var rollingState: [UUID: CardSnapshot] = [:]
        for index in snapshots.indices {
            applySnapshotState(snapshots[index], to: &rollingState)
            if keepSet.contains(index) {
                statesByIndex[index] = rollingState
            }
        }
        return statesByIndex
    }

    func shouldForceFullHistorySnapshot(
        rebuiltIsEmpty: Bool,
        index: Int,
        latestIndex: Int,
        promoted: Bool,
        isDeltaSnapshot: Bool,
        trailingDeltaCount: Int
    ) -> Bool {
        rebuiltIsEmpty ||
        index == latestIndex ||
        promoted ||
        !isDeltaSnapshot ||
        trailingDeltaCount >= deltaSnapshotFullCheckpointInterval
    }

    func fullHistorySnapshot(
        from original: HistorySnapshot,
        state: [UUID: CardSnapshot],
        promoted: Bool
    ) -> HistorySnapshot {
        HistorySnapshot(
            id: original.id,
            timestamp: original.timestamp,
            name: original.name,
            scenarioID: original.scenarioID,
            cardSnapshots: sortedCardSnapshots(from: state),
            isDelta: false,
            deletedCardIDs: [],
            isPromoted: promoted,
            promotionReason: original.promotionReason,
            noteCardID: original.noteCardID
        )
    }

    func deltaHistorySnapshot(
        from original: HistorySnapshot,
        delta: (changed: [CardSnapshot], deleted: [UUID]),
        promoted: Bool
    ) -> HistorySnapshot {
        HistorySnapshot(
            id: original.id,
            timestamp: original.timestamp,
            name: original.name,
            scenarioID: original.scenarioID,
            cardSnapshots: delta.changed,
            isDelta: true,
            deletedCardIDs: delta.deleted,
            isPromoted: promoted,
            promotionReason: original.promotionReason,
            noteCardID: original.noteCardID
        )
    }

    func fallbackLatestRebuiltHistorySnapshot(
        statesByIndex: [Int: [UUID: CardSnapshot]],
        snapshots: [HistorySnapshot],
        latestIndex: Int
    ) -> HistorySnapshot? {
        guard let latestState = statesByIndex[latestIndex], let latest = snapshots.last else { return nil }
        return HistorySnapshot(
            id: latest.id,
            timestamp: latest.timestamp,
            name: latest.name,
            scenarioID: latest.scenarioID,
            cardSnapshots: sortedCardSnapshots(from: latestState),
            isDelta: false,
            deletedCardIDs: [],
            isPromoted: isSnapshotPromoted(latest),
            promotionReason: latest.promotionReason,
            noteCardID: latest.noteCardID
        )
    }

    func isSnapshotPromoted(_ snapshot: HistorySnapshot) -> Bool {
        snapshot.isPromoted || snapshot.name != nil
    }

    func sortedCardSnapshots(from state: [UUID: CardSnapshot]) -> [CardSnapshot] {
        ScenarioHistoryEngine.sortedCardSnapshots(from: state)
    }

    func buildDeltaPayload(
        from previousMap: [UUID: CardSnapshot],
        to currentMap: [UUID: CardSnapshot]
    ) -> (changed: [CardSnapshot], deleted: [UUID]) {
        ScenarioHistoryEngine.buildDeltaPayload(from: previousMap, to: currentMap)
    }

    func shouldInsertFullSnapshotCheckpoint(in snapshots: [HistorySnapshot]) -> Bool {
        ScenarioHistoryEngine.shouldInsertFullSnapshotCheckpoint(
            in: snapshots,
            checkpointInterval: deltaSnapshotFullCheckpointInterval
        )
    }

    func nextSnapshotTimestamp() -> Date {
        let now = Date()
        guard let last = scenario.snapshots.last?.timestamp else { return now }
        if now <= last {
            return last.addingTimeInterval(0.001)
        }
        return now
    }

    func applySnapshotState(_ snapshot: HistorySnapshot, to state: inout [UUID: CardSnapshot]) {
        ScenarioHistoryEngine.applySnapshotState(snapshot, to: &state)
    }

    func resolvedCardSnapshotMap(
        at index: Int,
        in snapshots: [HistorySnapshot]
    ) -> [UUID: CardSnapshot]? {
        guard index >= 0 && index < snapshots.count else { return nil }
        let prefix = snapshots[0...index]
        let startIndex = prefix.lastIndex(where: { !$0.isDelta }) ?? 0
        let startsWithDelta = snapshots[startIndex].isDelta
        var state: [UUID: CardSnapshot] = [:]
        if !startsWithDelta {
            let base = snapshots[startIndex]
            for cardSnapshot in base.cardSnapshots {
                state[cardSnapshot.cardID] = cardSnapshot
            }
            for deletedID in base.deletedCardIDs {
                state.removeValue(forKey: deletedID)
            }
        }
        let applyStart = startsWithDelta ? startIndex : startIndex + 1
        if applyStart <= index {
            for i in applyStart...index {
                applySnapshotState(snapshots[i], to: &state)
            }
        }
        return state
    }

    func resolvedCardSnapshots(
        at index: Int,
        in snapshots: [HistorySnapshot]
    ) -> [CardSnapshot]? {
        guard let resolved = resolvedCardSnapshotMap(at: index, in: snapshots) else { return nil }
        return sortedCardSnapshots(from: resolved)
    }
}
