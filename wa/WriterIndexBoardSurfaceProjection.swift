import Foundation

struct BoardSurfaceLane: Identifiable, Equatable {
    let parentCardID: UUID?
    let laneIndex: Int
    let labelText: String
    let subtitleText: String
    let colorToken: String?
    let isTempLane: Bool

    var id: String {
        if let parentCardID {
            return parentCardID.uuidString
        }
        return "root"
    }
}

struct BoardSurfaceItem: Identifiable, Equatable {
    let cardID: UUID
    let laneParentID: UUID?
    let laneIndex: Int
    let slotIndex: Int?
    let detachedGridPosition: IndexBoardGridPosition?

    var isDetached: Bool { detachedGridPosition != nil }

    var id: UUID { cardID }
}

struct BoardSurfaceProjection: Equatable {
    let source: IndexBoardColumnSource
    let lanes: [BoardSurfaceLane]
    let surfaceItems: [BoardSurfaceItem]
    let orderedCardIDs: [UUID]
}
