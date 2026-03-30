import AppKit
import Foundation
import SwiftUI

struct MainWorkspaceActiveRelationSnapshot {
    let sourceCardID: UUID?
    let cardsVersion: Int
    let ancestorIDs: Set<UUID>
    let siblingIDs: Set<UUID>
    let descendantIDs: Set<UUID>
}

struct MainWorkspaceStateSnapshot {
    let activeCardID: UUID?
    let activeHistory: [UUID]
    let cardsVersion: Int
    let rootCards: [SceneCard]
    let levelsData: [LevelData]
    let boundaryNavigableLevels: [[SceneCard]]
    let relationSnapshot: MainWorkspaceActiveRelationSnapshot

    var levels: [[SceneCard]] {
        levelsData.map(\.cards)
    }
}

struct MainWorkspaceSurfaceRenderState {
    let contentFingerprint: Int
    let navigationFingerprint: Int
    let restoreFingerprint: Int
    let hasPendingRestoreRequest: Bool
    let activeCardID: UUID?
}

struct MainWorkspaceSnapshot {
    struct Slot {
        let level: Int
        let column: Column?
    }

    struct Column {
        let level: Int
        let parent: SceneCard?
        let viewportKey: String
        let cards: [SceneCard]
        let cardHeightByID: [UUID: CGFloat]
        let viewportHeight: CGFloat
        let width: CGFloat
        let topSpacerHeight: CGFloat
        let bottomSpacerHeight: CGFloat
        let rowGap: CGFloat
        let separatorHeight: CGFloat
    }

    let ownerKey: String
    let stateSnapshot: MainWorkspaceStateSnapshot
    let availableWidth: CGFloat
    let viewportHeight: CGFloat
    let leadingInset: CGFloat
    let trailingInset: CGFloat
    let slots: [Slot]
    let backgroundColor: NSColor
}

struct MainWorkspaceSurfaceCallbacks {
    let onAppear: (CGFloat) -> Void
    let onNavigation: (CGFloat) -> Void
    let onRestore: (CGFloat) -> Void
    let onApplyPlan: (MainWorkspaceScrollPlan, CGFloat) -> Void
    let onViewportOffsetChange: (String, CGFloat) -> Void
    let onObservedFramesChange: (String, [UUID: CGRect]) -> Void
    let onBackgroundTap: () -> Void
}
