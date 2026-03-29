import AppKit
import XCTest
@testable import WTF

@MainActor
final class MainCanvasScrollCoordinatorMotionSessionTests: XCTestCase {
    func testPredictedLayoutEnablesNativeDispatchWithoutObservedFrame() {
        let diagnostics = MainCanvasNavigationDiagnostics.shared
        diagnostics.setEnabledForTesting(true)
        defer { diagnostics.setEnabledForTesting(nil) }

        let scenario = Scenario()
        let card = SceneCard(content: "Predicted native target", scenario: scenario)
        scenario.cards = [card]

        let view = ScenarioWriterView(scenario: scenario)
        diagnostics.reset(
            ownerKey: view.mainCanvasDiagnosticsOwnerKey,
            scenarioID: scenario.id,
            splitPaneID: 0
        )

        let predictedOffset = view.resolvedMainColumnFocusTargetOffset(
            viewportKey: "test.column",
            cards: [card],
            targetID: card.id,
            viewportHeight: 320,
            anchorY: 0
        )
        diagnostics.beginFocusIntent(
            ownerKey: view.mainCanvasDiagnosticsOwnerKey,
            trigger: "activeCardChange",
            isRepeat: false,
            sourceCardID: nil,
            intendedCardID: card.id
        )
        diagnostics.beginScrollAnimation(
            ownerKey: view.mainCanvasDiagnosticsOwnerKey,
            axis: "vertical",
            engine: "native",
            animated: false,
            target: "test.column|\(card.id.uuidString)",
            expectedDuration: 0,
            predictedOnly: true
        )

        let snapshot = tryUnwrap(diagnostics.snapshot(ownerKey: view.mainCanvasDiagnosticsOwnerKey))
        XCTAssertNotNil(predictedOffset)
        XCTAssertEqual(snapshot.predictedNativeScrollCount, 1)
        XCTAssertEqual(snapshot.predictedNativeScrollMissCount, 0)
        XCTAssertEqual(snapshot.verticalFallbackScrollCount, 0)
    }

    func testDiagnosticsTrackClickFocusAndActiveCardChangeFirstMotion() {
        let diagnostics = MainCanvasNavigationDiagnostics.shared
        diagnostics.setEnabledForTesting(true)
        defer { diagnostics.setEnabledForTesting(nil) }

        let ownerKey = "diagnostics-trigger-coverage"
        diagnostics.reset(ownerKey: ownerKey, scenarioID: UUID(), splitPaneID: 0)

        diagnostics.beginFocusIntent(
            ownerKey: ownerKey,
            trigger: "clickFocus",
            isRepeat: false,
            sourceCardID: UUID(),
            intendedCardID: UUID()
        )
        diagnostics.beginScrollAnimation(
            ownerKey: ownerKey,
            axis: "vertical",
            engine: "native",
            animated: false,
            target: "test.column",
            expectedDuration: 0
        )

        diagnostics.beginFocusIntent(
            ownerKey: ownerKey,
            trigger: "activeCardChange",
            isRepeat: false,
            sourceCardID: UUID(),
            intendedCardID: UUID()
        )
        diagnostics.beginScrollAnimation(
            ownerKey: ownerKey,
            axis: "horizontal",
            engine: "native",
            animated: false,
            target: "level:1",
            expectedDuration: 0,
            horizontalMode: .oneStep
        )

        let snapshot = tryUnwrap(diagnostics.snapshot(ownerKey: ownerKey))
        XCTAssertEqual(snapshot.focusIntentCount, 2)
        XCTAssertEqual(snapshot.focusToFirstMotionCountByTrigger["clickFocus"], 1)
        XCTAssertEqual(snapshot.focusToFirstMotionCountByTrigger["activeCardChange"], 1)
        XCTAssertEqual(snapshot.horizontalOneStepScrollCount, 1)
    }

    func testTwoStepStoredValueNormalizesToOneStep() {
        XCTAssertEqual(
            MainCanvasHorizontalScrollMode.normalizePersistedRawValue(
                MainCanvasHorizontalScrollMode.twoStep.rawValue
            ),
            MainCanvasHorizontalScrollMode.oneStep.rawValue
        )
        XCTAssertEqual(
            MainCanvasHorizontalScrollMode.normalizePersistedRawValue(-1),
            MainCanvasHorizontalScrollMode.oneStep.rawValue
        )
    }

    func testConditionalSettleSkipsFalsePathWithoutMeasuredMisalignment() {
        XCTAssertFalse(
            MainWorkspaceMotionEntryPoints.shouldPublishNavigationSettle(
                verticalMisalignment: false,
                horizontalMisalignment: false,
                horizontalMode: .oneStep
            )
        )
        XCTAssertFalse(
            MainWorkspaceMotionEntryPoints.shouldPublishNavigationSettle(
                verticalMisalignment: false,
                horizontalMisalignment: true,
                horizontalMode: .twoStep
            )
        )
        XCTAssertTrue(
            MainWorkspaceMotionEntryPoints.shouldPublishNavigationSettle(
                verticalMisalignment: true,
                horizontalMisalignment: false,
                horizontalMode: .oneStep
            )
        )
    }

    // Drive retry and timeout ordering with a manual scheduler so the session contract stays deterministic.
    func testKeyboardRetargetCancelsStaleVerificationAndAdvancesRevision() {
        let scheduler = MainCanvasMotionManualScheduler()
        let coordinator = makeCoordinator(scheduler: scheduler)
        let sourceID = UUID()
        let targetID = UUID()

        let initialIntent = coordinator.publishIntent(
            kind: .focusChange,
            scope: .allColumns,
            targetCardID: sourceID,
            expectedActiveCardID: sourceID,
            animated: true,
            trigger: "arrowPreview"
        )
        let staleHandle = tryUnwrap(
            coordinator.claimMotionParticipant(
                for: "main.horizontal",
                axis: .horizontal,
                intent: initialIntent
            )
        )

        var staleVerificationRan = false
        let staleWorkItem = DispatchWorkItem {
            staleVerificationRan = true
        }
        coordinator.replaceMotionTask(staleWorkItem, kind: .verification, handle: staleHandle)
        scheduler.schedule(
            after: coordinator.motionPolicy.verificationDelay(animated: true, attempt: 0),
            workItem: staleWorkItem
        )

        let retargetedIntent = coordinator.publishIntent(
            kind: .focusChange,
            scope: .allColumns,
            targetCardID: targetID,
            expectedActiveCardID: targetID,
            animated: false,
            trigger: "arrowPreview"
        )
        XCTAssertEqual(retargetedIntent.sessionID, initialIntent.sessionID)
        XCTAssertEqual(retargetedIntent.sessionRevision, initialIntent.sessionRevision + 1)
        XCTAssertFalse(coordinator.isMotionParticipantCurrent(staleHandle))

        let currentHandle = tryUnwrap(
            coordinator.claimMotionParticipant(
                for: "main.horizontal",
                axis: .horizontal,
                intent: retargetedIntent
            )
        )
        coordinator.updateMotionParticipantState(.aligned, handle: currentHandle)
        scheduler.runAll()

        XCTAssertFalse(staleVerificationRan)
        XCTAssertNil(coordinator.activeMotionSessionSnapshot())
    }

    func testBottomRevealJoinsActiveSessionAndClosesAfterParticipantsAlign() {
        let scheduler = MainCanvasMotionManualScheduler()
        let coordinator = makeCoordinator(scheduler: scheduler)
        let anchorID = UUID()
        let revealID = UUID()

        let focusIntent = coordinator.publishIntent(
            kind: .focusChange,
            scope: .allColumns,
            targetCardID: anchorID,
            expectedActiveCardID: anchorID,
            animated: true,
            trigger: "activeCardChange"
        )
        let rootHandle = tryUnwrap(
            coordinator.claimMotionParticipant(
                for: "root.column",
                axis: .vertical,
                intent: focusIntent
            )
        )

        let bottomIntent = coordinator.publishIntent(
            kind: .bottomReveal,
            scope: .viewport("child.column"),
            targetCardID: revealID,
            expectedActiveCardID: revealID,
            animated: false,
            trigger: "bottomReveal"
        )
        XCTAssertEqual(bottomIntent.sessionID, focusIntent.sessionID)
        XCTAssertEqual(bottomIntent.sessionRevision, focusIntent.sessionRevision)
        XCTAssertEqual(
            coordinator.activeMotionSessionSnapshot()?.goal,
            .bottomReveal(cardID: revealID)
        )

        let childHandle = tryUnwrap(
            coordinator.claimMotionParticipant(
                for: "child.column",
                axis: .vertical,
                intent: bottomIntent
            )
        )
        coordinator.updateObservedFrames([anchorID: CGRect(x: 0, y: 0, width: 120, height: 40)], for: "root.column")
        coordinator.updateObservedFrames([revealID: CGRect(x: 0, y: 320, width: 120, height: 220)], for: "child.column")
        coordinator.updateMotionParticipantState(.aligned, handle: rootHandle)
        coordinator.updateMotionParticipantState(.aligned, handle: childHandle)
        scheduler.runAll()

        XCTAssertNil(coordinator.activeMotionSessionSnapshot())
    }

    func testMotionSessionTimeoutClosesUnresolvedParticipants() async {
        let scheduler = MainCanvasMotionManualScheduler()
        let coordinator = makeCoordinator(scheduler: scheduler)
        let targetID = UUID()

        let intent = coordinator.publishIntent(
            kind: .focusChange,
            scope: .allColumns,
            targetCardID: targetID,
            expectedActiveCardID: targetID,
            animated: false,
            trigger: "activeCardChange"
        )
        let handle = tryUnwrap(
            coordinator.claimMotionParticipant(
                for: "timeout.column",
                axis: .vertical,
                intent: intent
            )
        )

        XCTAssertNotNil(coordinator.activeMotionSessionSnapshot())
        scheduler.advance(by: coordinator.motionPolicy.sessionTimeout + 0.01)
        await Task.yield()

        XCTAssertNil(coordinator.activeMotionSessionSnapshot())
    }

    func testCorrectionGateQuietWindowWaitsUntilRepeatStops() {
        let scheduler = MainCanvasMotionManualScheduler()
        let coordinator = makeCoordinator(scheduler: scheduler)
        let firstTargetID = UUID()
        let secondTargetID = UUID()

        let firstIntent = coordinator.publishIntent(
            kind: .focusChange,
            scope: .allColumns,
            targetCardID: firstTargetID,
            expectedActiveCardID: firstTargetID,
            animated: true,
            trigger: "arrowPreview"
        )
        XCTAssertNil(coordinator.motionCorrectionGateSnapshot())

        scheduler.advance(by: coordinator.motionPolicy.correctionGateQuietWindowDelay * 0.5)
        XCTAssertNil(coordinator.motionCorrectionGateSnapshot())

        let secondIntent = coordinator.publishIntent(
            kind: .focusChange,
            scope: .allColumns,
            targetCardID: secondTargetID,
            expectedActiveCardID: secondTargetID,
            animated: true,
            trigger: "arrowPreview"
        )
        XCTAssertEqual(secondIntent.sessionID, firstIntent.sessionID)
        XCTAssertEqual(secondIntent.sessionRevision, firstIntent.sessionRevision + 1)

        scheduler.advance(by: coordinator.motionPolicy.correctionGateQuietWindowDelay * 0.75)
        XCTAssertNil(coordinator.motionCorrectionGateSnapshot())

        scheduler.advance(by: coordinator.motionPolicy.correctionGateQuietWindowDelay * 0.5)
        let gate = tryUnwrap(coordinator.motionCorrectionGateSnapshot())
        XCTAssertEqual(gate.reason, .quietWindow)
        XCTAssertEqual(gate.sessionID, secondIntent.sessionID)
        XCTAssertEqual(gate.revision, secondIntent.sessionRevision)
        XCTAssertTrue(coordinator.consumeMotionCorrectionBudget(forSessionID: gate.sessionID))
        XCTAssertFalse(coordinator.consumeMotionCorrectionBudget(forSessionID: gate.sessionID))
    }

    func testCorrectionGatePublishesOnSessionCloseAndBudgetStaysSingleUse() {
        let scheduler = MainCanvasMotionManualScheduler()
        let coordinator = makeCoordinator(scheduler: scheduler)
        let targetID = UUID()

        let intent = coordinator.publishIntent(
            kind: .focusChange,
            scope: .allColumns,
            targetCardID: targetID,
            expectedActiveCardID: targetID,
            animated: false,
            trigger: "activeCardChange"
        )
        let handle = tryUnwrap(
            coordinator.claimMotionParticipant(
                for: "close.column",
                axis: .horizontal,
                intent: intent
            )
        )

        coordinator.updateMotionParticipantState(.aligned, handle: handle)
        scheduler.runAll()

        let gate = tryUnwrap(coordinator.motionCorrectionGateSnapshot())
        XCTAssertEqual(gate.reason, .sessionClose)
        XCTAssertEqual(gate.sessionID, intent.sessionID)
        XCTAssertFalse(coordinator.hasActiveMotionSession())
        XCTAssertTrue(coordinator.consumeMotionCorrectionBudget(forSessionID: gate.sessionID))
        XCTAssertFalse(coordinator.consumeMotionCorrectionBudget(forSessionID: gate.sessionID))
    }

    func testDeferredHorizontalRestoreReplaysAfterSessionClose() {
        let scheduler = MainCanvasMotionManualScheduler()
        let coordinator = makeCoordinator(scheduler: scheduler)
        let scrollView = makeHorizontalScrollView()
        coordinator.registerMainCanvasHorizontalScrollView(scrollView)
        setHorizontalOffset(140, on: scrollView)
        coordinator.updateMainCanvasHorizontalOffset(140)

        let targetID = UUID()
        let intent = coordinator.publishIntent(
            kind: .focusChange,
            scope: .allColumns,
            targetCardID: targetID,
            expectedActiveCardID: targetID,
            animated: true,
            trigger: "activeCardChange"
        )
        let handle = tryUnwrap(
            coordinator.claimMotionParticipant(
                for: "main.horizontal",
                axis: .horizontal,
                intent: intent
            )
        )

        setHorizontalOffset(32, on: scrollView)
        coordinator.updateMainCanvasHorizontalOffset(32)
        coordinator.scheduleMainCanvasHorizontalRestore(offsetX: 140)
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, 32, accuracy: 0.5)

        coordinator.updateMotionParticipantState(.aligned, handle: handle)
        scheduler.runAll()

        XCTAssertEqual(scrollView.contentView.bounds.origin.x, 140, accuracy: 0.5)
    }

    private func makeCoordinator(
        scheduler: MainCanvasMotionManualScheduler
    ) -> MainCanvasScrollCoordinator {
        MainCanvasScrollCoordinator(
            scheduleMotionWorkItem: { delay, workItem in
                scheduler.schedule(after: delay, workItem: workItem)
            }
        )
    }

    private func makeHorizontalScrollView() -> NSScrollView {
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        scrollView.documentView = NSView(frame: CGRect(x: 0, y: 0, width: 1600, height: 240))
        scrollView.hasHorizontalScroller = true
        return scrollView
    }

    private func setHorizontalOffset(_ offsetX: CGFloat, on scrollView: NSScrollView) {
        scrollView.contentView.scroll(to: CGPoint(x: offsetX, y: scrollView.contentView.bounds.origin.y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func tryUnwrap<T>(
        _ value: T?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> T {
        guard let value else {
            XCTFail("Expected value to be non-nil", file: file, line: line)
            fatalError("Unreachable after XCTFail")
        }
        return value
    }
}
