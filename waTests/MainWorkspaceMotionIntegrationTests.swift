import XCTest
@testable import WTF

@MainActor
final class MainWorkspaceMotionIntegrationTests: XCTestCase {
    func testPreemptiveFocusNavigationPerformsDirectNavigation() {
        let targetID = UUID()
        var pendingTargetID: UUID?
        var performedTargetID: UUID?
        var performedAnimated = true
        var performedTrigger: String?

        MainWorkspaceMotionEntryPoints.publishPreemptiveFocusNavigationIntent(
            targetID: targetID,
            focusNavigationAnimationEnabled: false,
            suppressRepeatAnimation: false,
            trigger: "arrowPreview",
            setPendingPreemptiveTargetID: { pendingTargetID = $0 }
        ) { targetCardID, animated, trigger in
            performedTargetID = targetCardID
            performedAnimated = animated
            performedTrigger = trigger
        } log: { _, _, _ in }

        XCTAssertEqual(pendingTargetID, targetID)
        XCTAssertEqual(performedTargetID, targetID)
        XCTAssertFalse(performedAnimated)
        XCTAssertEqual(performedTrigger, "arrowPreview")
    }

    func testEditingBoundaryHandoffStartsFocusSession() {
        let targetID = UUID()
        let coordinator = MainCanvasScrollCoordinator()
        var pendingTargetID: UUID?

        MainWorkspaceMotionEntryPoints.beginEditingBoundaryMotionSession(
            targetCardID: targetID,
            setPendingPreemptiveTargetID: { pendingTargetID = $0 }
        ) { kind, scope, targetCardID, expectedActiveCardID, animated, trigger in
            _ = coordinator.publishIntent(
                kind: kind,
                scope: scope,
                targetCardID: targetCardID,
                expectedActiveCardID: expectedActiveCardID,
                animated: animated,
                trigger: trigger
            )
        }

        XCTAssertEqual(pendingTargetID, targetID)
        XCTAssertEqual(
            coordinator.activeMotionSessionSnapshot()?.goal,
            .alignToAnchor(cardID: targetID)
        )
        XCTAssertEqual(
            coordinator.consumeLatestIntent(for: "waTests.editingBoundary")?.trigger,
            "editingBoundary"
        )
    }

    func testFocusExitRestoreEntryPointsCaptureRestorePayloads() {
        let activeID = UUID()
        let deferredOffsets = ["main.column.1": CGFloat(120)]
        let snapshot = FocusModeWorkspaceSnapshot(
            activeCardID: activeID,
            editingCardID: nil,
            selectedCardIDs: [activeID],
            visibleMainCanvasLevel: 3,
            mainCanvasHorizontalOffset: 48,
            mainColumnViewportOffsets: deferredOffsets,
            capturedAt: Date()
        )
        var requestedTargetID: UUID?
        var requestedVisibleLevel: Int?
        var requestedForceSemantic: Bool = false
        var requestedReason: MainCanvasViewState.RestoreRequest.Reason?
        var scheduledViewportOffsets: [String: CGFloat] = [:]

        MainWorkspaceMotionEntryPoints.requestMainCanvasRestoreForFocusExit(
            activeCardID: activeID,
            editingCardID: nil,
            lastActiveCardID: nil,
            rootCardID: nil,
            snapshot: snapshot
        ) { targetID, visibleLevel, forceSemantic, reason in
            requestedTargetID = targetID
            requestedVisibleLevel = visibleLevel
            requestedForceSemantic = forceSemantic
            requestedReason = reason
        }
        MainWorkspaceMotionEntryPoints.requestMainCanvasViewportRestoreForFocusExit(
            showFocusMode: false,
            snapshot: snapshot,
            currentOffsets: [:]
        ) { offsets in
            scheduledViewportOffsets = offsets
        }

        XCTAssertEqual(requestedTargetID, activeID)
        XCTAssertEqual(requestedVisibleLevel, 3)
        XCTAssertTrue(requestedForceSemantic)
        XCTAssertEqual(requestedReason, .focusExit)
        XCTAssertEqual(scheduledViewportOffsets, deferredOffsets)
    }

    func testReorderCommitCapturesViewportAndSupersedesCurrentSession() {
        let movedID = UUID()
        let firstTargetID = UUID()
        let secondTargetID = UUID()
        let coordinator = MainCanvasScrollCoordinator()
        var pendingMotionCardIDs: [UUID] = []
        var pendingHorizontalOffset: CGFloat?
        var pendingTargetID: UUID?
        var cancelSettleCount = 0
        var cancelFocusWorkCount = 0
        coordinator.updateMainCanvasHorizontalOffset(96)
        _ = coordinator.publishIntent(
            kind: .focusChange,
            scope: .allColumns,
            targetCardID: firstTargetID,
            expectedActiveCardID: firstTargetID,
            animated: false,
            trigger: "arrowPreview"
        )
        let initialSnapshot = coordinator.activeMotionSessionSnapshot()

        MainWorkspaceMotionEntryPoints.beginReorderMotionSession(
            movedCardIDs: [movedID, movedID],
            anchorCardID: secondTargetID,
            resolvedHorizontalOffset: coordinator.resolvedMainCanvasHorizontalOffset(),
            cancelArrowSettle: { cancelSettleCount += 1 },
            cancelPendingFocusWork: { cancelFocusWorkCount += 1 },
            setPendingReorderMotionCardIDs: { pendingMotionCardIDs = $0 },
            setPendingReorderHorizontalOffsetX: { pendingHorizontalOffset = $0 },
            setPendingPreemptiveTargetID: { pendingTargetID = $0 }
        ) { kind, scope, targetCardID, expectedActiveCardID, animated, trigger in
            _ = coordinator.publishIntent(
                kind: kind,
                scope: scope,
                targetCardID: targetCardID,
                expectedActiveCardID: expectedActiveCardID,
                animated: animated,
                trigger: trigger
            )
        }

        XCTAssertEqual(pendingMotionCardIDs, [movedID])
        XCTAssertEqual(pendingHorizontalOffset ?? -1, 96, accuracy: 0.5)
        XCTAssertEqual(pendingTargetID, secondTargetID)
        XCTAssertEqual(cancelSettleCount, 1)
        XCTAssertEqual(cancelFocusWorkCount, 1)
        XCTAssertEqual(
            coordinator.activeMotionSessionSnapshot()?.sessionID,
            initialSnapshot?.sessionID
        )
        XCTAssertEqual(
            coordinator.activeMotionSessionSnapshot()?.revision,
            (initialSnapshot?.revision ?? 0) + 1
        )
        XCTAssertEqual(
            coordinator.consumeLatestIntent(for: "waTests.reorder")?.trigger,
            "reorderCommit"
        )
    }
}
