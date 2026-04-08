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
    let editingCardID: UUID?
    let activeEditorSessionID: Int?
    let activeHistory: [UUID]
    let cardsVersion: Int
    let rootCards: [SceneCard]
    let levelsData: [LevelData]
    let boundaryNavigableLevels: [[SceneCard]]
    let relationSnapshot: MainWorkspaceActiveRelationSnapshot

    var levels: [[SceneCard]] {
        levelsData.map(\.cards)
    }

    func editorSessionID(for cardID: UUID) -> Int? {
        guard editingCardID == cardID else { return nil }
        return activeEditorSessionID
    }
}

struct MainWorkspaceSurfaceRenderState {
    let contentFingerprint: Int
    let navigationFingerprint: Int
    let restoreFingerprint: Int
    let hasPendingRestoreRequest: Bool
    let activeCardID: UUID?
}

struct MainWorkspaceCardRenderMetrics {
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let contentPadding: CGFloat
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
    let cardRenderMetrics: MainWorkspaceCardRenderMetrics
}

struct MainWorkspaceSurfaceCallbacks {
    let onAppear: (CGFloat) -> Void
    let onNavigation: (CGFloat) -> Void
    let onRestore: (CGFloat) -> Void
    let onViewportOffsetChange: (String, CGFloat) -> Void
    let onObservedFramesChange: (String, [UUID: CGRect]) -> Void
    let onCardSelect: (UUID, CGPoint?) -> Void
    let onCardDoubleClick: (UUID) -> Void
    let onEditorTextChange: (UUID, String, String) -> Void
    let onEditorEnd: (UUID) -> Void
    let onEditorTab: (UUID) -> Void
    let onEditorCommandEnter: (UUID) -> Void
    let onContextMenuPrepare: (UUID) -> Void
    let onContextCopy: (UUID) -> Void
    let onContextCut: (UUID) -> Void
    let onContextPaste: (UUID) -> Void
    let onContextCloneCopy: (UUID) -> Void
    let onContextDelete: (UUID) -> Void
    let onContextColorChange: (UUID, String?) -> Void
    let onBackgroundTap: () -> Void
}
