import SwiftUI
import Combine

enum IndexBoardZoom {
    static let minScale: CGFloat = 0.30
    static let maxScale: CGFloat = 1.60
    static let defaultScale: CGFloat = 1.0
    static let step: CGFloat = 0.05
}

enum WriterPaneMode: String, Equatable {
    case main
    case focus
    case indexBoard
}

struct IndexBoardColumnSource: Equatable, Hashable, Codable {
    let parentID: UUID?
    let depth: Int
}

struct IndexBoardEntrySnapshot: Equatable {
    let activeCardID: UUID?
    let editingCardID: UUID?
    let selectedCardIDs: Set<UUID>
    let editingCaretLocation: Int?
    let visibleMainCanvasLevel: Int?
    let mainCanvasHorizontalOffset: CGFloat?
    let mainColumnViewportOffsets: [String: CGFloat]
}

struct IndexBoardSessionDescriptor: Equatable, Hashable {
    let scenarioID: UUID
    let paneID: Int
    let source: IndexBoardColumnSource

    var sourceParentID: UUID? { source.parentID }
    var sourceDepth: Int { source.depth }
}

struct IndexBoardViewportState: Equatable {
    var zoomScale: CGFloat = IndexBoardZoom.defaultScale
    var scrollOffset: CGPoint = .zero
}

struct IndexBoardPresentationState: Equatable {
    var collapsedLaneParentIDs: Set<UUID> = []
    var showsBackByCardID: [UUID: Bool] = [:]
    var lastPresentedCardID: UUID? = nil
}

struct IndexBoardLogicalState: Equatable {
    var detachedGridPositionByCardID: [UUID: IndexBoardGridPosition] = [:]
    var groupGridPositionByParentID: [UUID: IndexBoardGridPosition] = [:]
    var tempStrips: [IndexBoardTempStripState] = []
}

struct IndexBoardGridPosition: Equatable, Hashable, Codable {
    var column: Int
    var row: Int
}

enum IndexBoardTempStripMemberKind: String, Codable {
    case card
    case group
}

struct IndexBoardTempStripMember: Equatable, Hashable, Codable {
    let kind: IndexBoardTempStripMemberKind
    let id: UUID

    var stableID: String {
        "\(kind.rawValue):\(id.uuidString)"
    }
}

struct IndexBoardTempStripState: Equatable, Identifiable, Codable {
    let id: String
    var row: Int
    var anchorColumn: Int
    var members: [IndexBoardTempStripMember]
}

private struct IndexBoardPersistedSessionRecord: Codable {
    let source: IndexBoardColumnSource
    let sourceCardIDs: [UUID]
    let zoomScale: Double
    let scrollOffsetX: Double
    let scrollOffsetY: Double
    let detachedGridPositionByCardID: [String: IndexBoardGridPosition]
    let groupGridPositionByParentID: [String: IndexBoardGridPosition]
    let tempStrips: [IndexBoardTempStripState]?
    let collapsedLaneParentIDs: [UUID]
    let showsBackByCardID: [String: Bool]
    let lastPresentedCardID: UUID?
}

private extension Dictionary where Key == UUID, Value == IndexBoardGridPosition {
    var persistedIndexBoardDictionary: [String: IndexBoardGridPosition] {
        reduce(into: [:]) { partialResult, entry in
            partialResult[entry.key.uuidString] = entry.value
        }
    }
}

private extension Dictionary where Key == String, Value == IndexBoardGridPosition {
    var restoredIndexBoardDictionary: [UUID: IndexBoardGridPosition] {
        reduce(into: [:]) { partialResult, entry in
            guard let uuid = UUID(uuidString: entry.key) else { return }
            partialResult[uuid] = entry.value
        }
    }
}

private extension Dictionary where Key == UUID, Value == Bool {
    var persistedIndexBoardBoolDictionary: [String: Bool] {
        reduce(into: [:]) { partialResult, entry in
            partialResult[entry.key.uuidString] = entry.value
        }
    }
}

private extension Dictionary where Key == String, Value == Bool {
    var restoredIndexBoardBoolDictionary: [UUID: Bool] {
        reduce(into: [:]) { partialResult, entry in
            guard let uuid = UUID(uuidString: entry.key) else { return }
            partialResult[uuid] = entry.value
        }
    }
}

struct IndexBoardParentGroupDropTarget: Equatable {
    let parentCardID: UUID
    let origin: IndexBoardGridPosition
}

struct IndexBoardNavigationState: Equatable {
    var pendingRevealCardID: UUID? = nil
    var revealRequestToken: Int = 0
}

struct IndexBoardSessionState: Equatable {
    let source: IndexBoardColumnSource
    var sourceCardIDs: [UUID]
    let entrySnapshot: IndexBoardEntrySnapshot
    var viewport = IndexBoardViewportState()
    var logical = IndexBoardLogicalState()
    var presentation = IndexBoardPresentationState()
    var navigation = IndexBoardNavigationState()

    var sourceParentID: UUID? { source.parentID }
    var sourceDepth: Int { source.depth }

    var zoomScale: CGFloat {
        get { viewport.zoomScale }
        set { viewport.zoomScale = newValue }
    }

    var scrollOffset: CGPoint {
        get { viewport.scrollOffset }
        set { viewport.scrollOffset = newValue }
    }

    var collapsedLaneParentIDs: Set<UUID> {
        get { presentation.collapsedLaneParentIDs }
        set { presentation.collapsedLaneParentIDs = newValue }
    }

    var collapsedGroupParentIDs: Set<UUID> {
        get { presentation.collapsedLaneParentIDs }
        set { presentation.collapsedLaneParentIDs = newValue }
    }

    var showsBackByCardID: [UUID: Bool] {
        get { presentation.showsBackByCardID }
        set { presentation.showsBackByCardID = newValue }
    }

    var lastPresentedCardID: UUID? {
        get { presentation.lastPresentedCardID }
        set { presentation.lastPresentedCardID = newValue }
    }

    var detachedGridPositionByCardID: [UUID: IndexBoardGridPosition] {
        get { logical.detachedGridPositionByCardID }
        set { logical.detachedGridPositionByCardID = newValue }
    }

    var groupGridPositionByParentID: [UUID: IndexBoardGridPosition] {
        get { logical.groupGridPositionByParentID }
        set { logical.groupGridPositionByParentID = newValue }
    }

    var tempStrips: [IndexBoardTempStripState] {
        get { logical.tempStrips }
        set { logical.tempStrips = newValue }
    }

    var pendingRevealCardID: UUID? {
        get { navigation.pendingRevealCardID }
        set { navigation.pendingRevealCardID = newValue }
    }

    var revealRequestToken: Int {
        get { navigation.revealRequestToken }
        set { navigation.revealRequestToken = newValue }
    }
}

@MainActor
final class IndexBoardRuntime: ObservableObject {
    struct ActiveSession: Equatable {
        let descriptor: IndexBoardSessionDescriptor
        var session: IndexBoardSessionState
    }

    static let shared = IndexBoardRuntime()

    @Published private var activeSessionByScenarioID: [UUID: ActiveSession] = [:]
    private var liveViewportByDescriptor: [IndexBoardSessionDescriptor: IndexBoardViewportState] = [:]
    private let persistedSessionsKey = "writer.indexboard.persisted-sessions.v1"
    private let deferredPersistQueue = DispatchQueue(
        label: "writer.indexboard.persisted-session-write",
        qos: .utility
    )
    private var deferredPersistWorkItemByScenarioID: [UUID: DispatchWorkItem] = [:]
    private let deferredPersistDelay: TimeInterval = 0.25

    private init() {}

    func activeSession(for scenarioID: UUID) -> ActiveSession? {
        guard let active = activeSessionByScenarioID[scenarioID] else { return nil }
        return resolvedActiveSession(active)
    }

    func activeDescriptor(for scenarioID: UUID) -> IndexBoardSessionDescriptor? {
        activeSessionByScenarioID[scenarioID]?.descriptor
    }

    func session(for scenarioID: UUID, paneID: Int) -> IndexBoardSessionState? {
        guard let active = activeSessionByScenarioID[scenarioID], active.descriptor.paneID == paneID else {
            return nil
        }
        return resolvedSession(active.session, descriptor: active.descriptor)
    }

    func descriptor(for scenarioID: UUID, paneID: Int) -> IndexBoardSessionDescriptor? {
        guard let active = activeSessionByScenarioID[scenarioID], active.descriptor.paneID == paneID else {
            return nil
        }
        return active.descriptor
    }

    func isActive(scenarioID: UUID, paneID: Int) -> Bool {
        activeSessionByScenarioID[scenarioID]?.descriptor.paneID == paneID
    }

    var hasActiveSession: Bool {
        !activeSessionByScenarioID.isEmpty
    }

    func canActivate(scenarioID: UUID, paneID: Int) -> Bool {
        guard let active = activeSessionByScenarioID[scenarioID] else { return true }
        return active.descriptor.paneID == paneID
    }

    func activate(_ session: IndexBoardSessionState, scenarioID: UUID, paneID: Int) {
        let descriptor = IndexBoardSessionDescriptor(
            scenarioID: scenarioID,
            paneID: paneID,
            source: session.source
        )
        activeSessionByScenarioID[scenarioID] = ActiveSession(
            descriptor: descriptor,
            session: session
        )
        liveViewportByDescriptor[descriptor] = session.viewport
        persistSession(session, for: scenarioID)
    }

    func updateSession(
        for scenarioID: UUID,
        paneID: Int,
        persist: Bool = true,
        _ transform: (inout IndexBoardSessionState) -> Void
    ) {
        guard var active = activeSessionByScenarioID[scenarioID], active.descriptor.paneID == paneID else { return }
        active.session = resolvedSession(active.session, descriptor: active.descriptor)
        transform(&active.session)
        activeSessionByScenarioID[scenarioID] = active
        liveViewportByDescriptor[active.descriptor] = active.session.viewport
        if persist {
            persistSession(active.session, for: scenarioID)
        }
    }

    func schedulePersistCurrentSession(for scenarioID: UUID, paneID: Int) {
        guard let active = activeSessionByScenarioID[scenarioID], active.descriptor.paneID == paneID else { return }
        let resolvedSession = resolvedSession(active.session, descriptor: active.descriptor)
        scheduleDeferredPersist(resolvedSession, for: scenarioID)
    }

    func schedulePersistCurrentLogicalState(for scenarioID: UUID, paneID: Int) {
        guard let active = activeSessionByScenarioID[scenarioID], active.descriptor.paneID == paneID else { return }
        let resolvedSession = resolvedSession(active.session, descriptor: active.descriptor)
        let fallbackRecord = makePersistedSessionRecord(from: resolvedSession)
        let record = updatedPersistedRecord(
            loadPersistedSessionRecords()[scenarioID.uuidString] ?? fallbackRecord,
            logicalState: resolvedSession.logical
        )
        scheduleDeferredPersistRecord(record, for: scenarioID)
    }

    func deactivate(scenarioID: UUID, paneID: Int) {
        guard let active = activeSessionByScenarioID[scenarioID], active.descriptor.paneID == paneID else { return }
        let resolvedSession = resolvedSession(active.session, descriptor: active.descriptor)
        cancelDeferredPersist(for: scenarioID)
        persistSession(resolvedSession, for: scenarioID)
        liveViewportByDescriptor.removeValue(forKey: active.descriptor)
        activeSessionByScenarioID.removeValue(forKey: scenarioID)
    }

    func updateLiveViewport(
        for scenarioID: UUID,
        paneID: Int,
        zoomScale: CGFloat? = nil,
        scrollOffset: CGPoint? = nil
    ) {
        guard let active = activeSessionByScenarioID[scenarioID], active.descriptor.paneID == paneID else { return }
        var viewport = liveViewportByDescriptor[active.descriptor] ?? active.session.viewport
        if let zoomScale {
            viewport.zoomScale = min(max(zoomScale, IndexBoardZoom.minScale), IndexBoardZoom.maxScale)
        }
        if let scrollOffset {
            viewport.scrollOffset = CGPoint(
                x: max(0, scrollOffset.x),
                y: max(0, scrollOffset.y)
            )
        }
        liveViewportByDescriptor[active.descriptor] = viewport
    }

    func persistedSession(
        for scenarioID: UUID,
        entrySnapshot: IndexBoardEntrySnapshot
    ) -> IndexBoardSessionState? {
        guard let record = persistedSessionRecord(for: scenarioID) else { return nil }
        return IndexBoardSessionState(
            source: record.source,
            sourceCardIDs: record.sourceCardIDs,
            entrySnapshot: entrySnapshot,
            viewport: IndexBoardViewportState(
                zoomScale: CGFloat(record.zoomScale),
                scrollOffset: CGPoint(
                    x: record.scrollOffsetX,
                    y: record.scrollOffsetY
                )
            ),
            logical: IndexBoardLogicalState(
                detachedGridPositionByCardID: record.detachedGridPositionByCardID.restoredIndexBoardDictionary,
                groupGridPositionByParentID: record.groupGridPositionByParentID.restoredIndexBoardDictionary,
                tempStrips: record.tempStrips ?? []
            ),
            presentation: IndexBoardPresentationState(
                collapsedLaneParentIDs: Set(record.collapsedLaneParentIDs),
                showsBackByCardID: record.showsBackByCardID.restoredIndexBoardBoolDictionary,
                lastPresentedCardID: record.lastPresentedCardID
            ),
            navigation: IndexBoardNavigationState()
        )
    }

    func replacePersistedSession(_ session: IndexBoardSessionState?, for scenarioID: UUID) {
        cancelDeferredPersist(for: scenarioID)
        var records = loadPersistedSessionRecords()

        if let session {
            records[scenarioID.uuidString] = makePersistedSessionRecord(from: session)
        } else {
            records.removeValue(forKey: scenarioID.uuidString)
        }

        storePersistedSessionRecords(records)
    }

    func replacePersistedLogicalState(_ logicalState: IndexBoardLogicalState, for scenarioID: UUID) {
        cancelDeferredPersist(for: scenarioID)
        var records = loadPersistedSessionRecords()
        guard let existingRecord = records[scenarioID.uuidString] else { return }
        records[scenarioID.uuidString] = updatedPersistedRecord(existingRecord, logicalState: logicalState)
        storePersistedSessionRecords(records)
    }

    func persistViewport(
        zoomScale: CGFloat,
        scrollOffset: CGPoint,
        for scenarioID: UUID,
        paneID: Int
    ) {
        let resolvedScale = min(max(zoomScale, IndexBoardZoom.minScale), IndexBoardZoom.maxScale)
        let resolvedOffset = CGPoint(
            x: max(0, scrollOffset.x),
            y: max(0, scrollOffset.y)
        )

        if var active = activeSessionByScenarioID[scenarioID],
           active.descriptor.paneID == paneID {
            active.session.zoomScale = resolvedScale
            active.session.scrollOffset = resolvedOffset
            activeSessionByScenarioID[scenarioID] = active
            liveViewportByDescriptor[active.descriptor] = active.session.viewport
            cancelDeferredPersist(for: scenarioID)
            persistSession(active.session, for: scenarioID)
            return
        }

        var records = loadPersistedSessionRecords()
        guard let existingRecord = records[scenarioID.uuidString] else { return }
        records[scenarioID.uuidString] = IndexBoardPersistedSessionRecord(
            source: existingRecord.source,
            sourceCardIDs: existingRecord.sourceCardIDs,
            zoomScale: Double(resolvedScale),
            scrollOffsetX: Double(resolvedOffset.x),
            scrollOffsetY: Double(resolvedOffset.y),
            detachedGridPositionByCardID: existingRecord.detachedGridPositionByCardID,
            groupGridPositionByParentID: existingRecord.groupGridPositionByParentID,
            tempStrips: existingRecord.tempStrips,
            collapsedLaneParentIDs: existingRecord.collapsedLaneParentIDs,
            showsBackByCardID: existingRecord.showsBackByCardID,
            lastPresentedCardID: existingRecord.lastPresentedCardID
        )
        storePersistedSessionRecords(records)
    }

    private func persistedSessionRecord(for scenarioID: UUID) -> IndexBoardPersistedSessionRecord? {
        loadPersistedSessionRecords()[scenarioID.uuidString]
    }

    private func resolvedActiveSession(_ active: ActiveSession) -> ActiveSession {
        ActiveSession(
            descriptor: active.descriptor,
            session: resolvedSession(active.session, descriptor: active.descriptor)
        )
    }

    private func resolvedSession(
        _ session: IndexBoardSessionState,
        descriptor: IndexBoardSessionDescriptor
    ) -> IndexBoardSessionState {
        guard let liveViewport = liveViewportByDescriptor[descriptor] else { return session }
        var resolvedSession = session
        resolvedSession.viewport = liveViewport
        return resolvedSession
    }

    private func persistSession(_ session: IndexBoardSessionState, for scenarioID: UUID) {
        cancelDeferredPersist(for: scenarioID)
        var records = loadPersistedSessionRecords()
        records[scenarioID.uuidString] = makePersistedSessionRecord(from: session)
        storePersistedSessionRecords(records)
    }

    private func cancelDeferredPersist(for scenarioID: UUID) {
        deferredPersistWorkItemByScenarioID[scenarioID]?.cancel()
        deferredPersistWorkItemByScenarioID.removeValue(forKey: scenarioID)
    }

    private func scheduleDeferredPersistRecord(
        _ record: IndexBoardPersistedSessionRecord,
        for scenarioID: UUID
    ) {
        cancelDeferredPersist(for: scenarioID)
        let scenarioKey = scenarioID.uuidString
        let persistedSessionsKey = self.persistedSessionsKey
        let workItem = DispatchWorkItem {
            var records: [String: IndexBoardPersistedSessionRecord] = [:]
            if let data = UserDefaults.standard.data(forKey: persistedSessionsKey),
               let decoded = try? JSONDecoder().decode([String: IndexBoardPersistedSessionRecord].self, from: data) {
                records = decoded
            }
            records[scenarioKey] = record
            guard let encoded = try? JSONEncoder().encode(records) else { return }
            UserDefaults.standard.set(encoded, forKey: persistedSessionsKey)
        }
        deferredPersistWorkItemByScenarioID[scenarioID] = workItem
        deferredPersistQueue.asyncAfter(deadline: .now() + deferredPersistDelay, execute: workItem)
    }

    private func scheduleDeferredPersist(_ session: IndexBoardSessionState, for scenarioID: UUID) {
        scheduleDeferredPersistRecord(makePersistedSessionRecord(from: session), for: scenarioID)
    }

    private func updatedPersistedRecord(
        _ record: IndexBoardPersistedSessionRecord,
        logicalState: IndexBoardLogicalState
    ) -> IndexBoardPersistedSessionRecord {
        IndexBoardPersistedSessionRecord(
            source: record.source,
            sourceCardIDs: record.sourceCardIDs,
            zoomScale: record.zoomScale,
            scrollOffsetX: record.scrollOffsetX,
            scrollOffsetY: record.scrollOffsetY,
            detachedGridPositionByCardID: logicalState.detachedGridPositionByCardID.persistedIndexBoardDictionary,
            groupGridPositionByParentID: logicalState.groupGridPositionByParentID.persistedIndexBoardDictionary,
            tempStrips: logicalState.tempStrips,
            collapsedLaneParentIDs: record.collapsedLaneParentIDs,
            showsBackByCardID: record.showsBackByCardID,
            lastPresentedCardID: record.lastPresentedCardID
        )
    }

    private func makePersistedSessionRecord(from session: IndexBoardSessionState) -> IndexBoardPersistedSessionRecord {
        IndexBoardPersistedSessionRecord(
            source: session.source,
            sourceCardIDs: session.sourceCardIDs,
            zoomScale: Double(session.zoomScale),
            scrollOffsetX: Double(session.scrollOffset.x),
            scrollOffsetY: Double(session.scrollOffset.y),
            detachedGridPositionByCardID: session.detachedGridPositionByCardID.persistedIndexBoardDictionary,
            groupGridPositionByParentID: session.groupGridPositionByParentID.persistedIndexBoardDictionary,
            tempStrips: session.tempStrips,
            collapsedLaneParentIDs: Array(session.collapsedLaneParentIDs),
            showsBackByCardID: session.showsBackByCardID.persistedIndexBoardBoolDictionary,
            lastPresentedCardID: session.lastPresentedCardID
        )
    }

    private func loadPersistedSessionRecords() -> [String: IndexBoardPersistedSessionRecord] {
        guard let data = UserDefaults.standard.data(forKey: persistedSessionsKey),
              let records = try? JSONDecoder().decode([String: IndexBoardPersistedSessionRecord].self, from: data) else {
            return [:]
        }
        return records
    }

    private func storePersistedSessionRecords(_ records: [String: IndexBoardPersistedSessionRecord]) {
        guard let encoded = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(encoded, forKey: persistedSessionsKey)
    }
}
