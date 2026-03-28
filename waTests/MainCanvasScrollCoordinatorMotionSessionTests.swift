import AppKit
import XCTest
@testable import WTF

@MainActor
final class MainCanvasScrollCoordinatorMotionSessionTests: XCTestCase {
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
