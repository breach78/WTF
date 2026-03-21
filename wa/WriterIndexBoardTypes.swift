import SwiftUI
import Combine

enum IndexBoardZoom {
    static let minScale: CGFloat = 0.70
    static let maxScale: CGFloat = 1.60
    static let defaultScale: CGFloat = 1.0
    static let step: CGFloat = 0.05
}

enum WriterPaneMode: String, Equatable {
    case main
    case focus
    case indexBoard
}

struct IndexBoardColumnSource: Equatable, Hashable {
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
    var detachedGridPositionByCardID: [UUID: IndexBoardGridPosition] = [:]
}

struct IndexBoardGridPosition: Equatable, Hashable {
    var column: Int
    var row: Int
}

struct IndexBoardNavigationState: Equatable {
    var pendingRevealCardID: UUID? = nil
    var revealRequestToken: Int = 0
}

struct IndexBoardSessionState: Equatable {
    let source: IndexBoardColumnSource
    let sourceCardIDs: [UUID]
    let entrySnapshot: IndexBoardEntrySnapshot
    var viewport = IndexBoardViewportState()
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
        get { presentation.detachedGridPositionByCardID }
        set { presentation.detachedGridPositionByCardID = newValue }
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

    private init() {}

    func activeSession(for scenarioID: UUID) -> ActiveSession? {
        activeSessionByScenarioID[scenarioID]
    }

    func activeDescriptor(for scenarioID: UUID) -> IndexBoardSessionDescriptor? {
        activeSessionByScenarioID[scenarioID]?.descriptor
    }

    func session(for scenarioID: UUID, paneID: Int) -> IndexBoardSessionState? {
        guard let active = activeSessionByScenarioID[scenarioID], active.descriptor.paneID == paneID else {
            return nil
        }
        return active.session
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

    func canActivate(scenarioID: UUID, paneID: Int) -> Bool {
        guard let active = activeSessionByScenarioID[scenarioID] else { return true }
        return active.descriptor.paneID == paneID
    }

    func activate(_ session: IndexBoardSessionState, scenarioID: UUID, paneID: Int) {
        activeSessionByScenarioID[scenarioID] = ActiveSession(
            descriptor: IndexBoardSessionDescriptor(
                scenarioID: scenarioID,
                paneID: paneID,
                source: session.source
            ),
            session: session
        )
    }

    func updateSession(
        for scenarioID: UUID,
        paneID: Int,
        _ transform: (inout IndexBoardSessionState) -> Void
    ) {
        guard var active = activeSessionByScenarioID[scenarioID], active.descriptor.paneID == paneID else { return }
        transform(&active.session)
        activeSessionByScenarioID[scenarioID] = active
    }

    func deactivate(scenarioID: UUID, paneID: Int) {
        guard let active = activeSessionByScenarioID[scenarioID], active.descriptor.paneID == paneID else { return }
        activeSessionByScenarioID.removeValue(forKey: scenarioID)
    }
}
