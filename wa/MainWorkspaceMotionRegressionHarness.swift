#if DEBUG
import AppKit
import Combine
import SwiftUI

@MainActor
final class MainCanvasMotionManualScheduler {
    private struct Entry {
        let id: Int
        let fireTime: TimeInterval
        let workItem: DispatchWorkItem
    }

    private(set) var currentTime: TimeInterval = 0
    private var nextID: Int = 0
    private var entries: [Entry] = []

    func schedule(after delay: TimeInterval, workItem: DispatchWorkItem) {
        nextID &+= 1
        entries.append(
            Entry(
                id: nextID,
                fireTime: currentTime + max(0, delay),
                workItem: workItem
            )
        )
        entries.sort {
            if $0.fireTime != $1.fireTime {
                return $0.fireTime < $1.fireTime
            }
            return $0.id < $1.id
        }
    }

    func advance(by delta: TimeInterval) {
        run(until: currentTime + max(0, delta))
    }

    func runAll() {
        while let nextFireTime = entries
            .filter({ !$0.workItem.isCancelled })
            .map(\.fireTime)
            .min()
        {
            run(until: nextFireTime)
        }
    }

    private func run(until targetTime: TimeInterval) {
        while true {
            entries.sort {
                if $0.fireTime != $1.fireTime {
                    return $0.fireTime < $1.fireTime
                }
                return $0.id < $1.id
            }
            guard let index = entries.firstIndex(where: { !$0.workItem.isCancelled && $0.fireTime <= targetTime }) else {
                break
            }
            let entry = entries.remove(at: index)
            currentTime = entry.fireTime
            guard !entry.workItem.isCancelled else { continue }
            entry.workItem.perform()
        }
        currentTime = max(currentTime, targetTime)
    }
}

@MainActor
enum MainWorkspaceMotionRegressionScenario: String, CaseIterable, Identifiable {
    case keyboardRetarget
    case clickSupersede
    case bottomRevealJoin
    case reorderCommit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keyboardRetarget:
            return "Keyboard Retarget"
        case .clickSupersede:
            return "Click Supersede"
        case .bottomRevealJoin:
            return "Bottom Reveal Join"
        case .reorderCommit:
            return "Reorder Commit"
        }
    }
}

@MainActor
struct MainWorkspaceMotionRegressionResult: Equatable {
    let scenario: MainWorkspaceMotionRegressionScenario
    let passed: Bool
    let details: String

    var summary: String {
        "\(scenario.rawValue):\(passed ? "PASS" : "FAIL") \(details)"
    }
}

@MainActor
final class MainWorkspaceMotionRegressionHarness: ObservableObject {
    @Published private(set) var lastResultSummary: String = "idle"

    func run(_ scenario: MainWorkspaceMotionRegressionScenario) {
        let result = switch scenario {
        case .keyboardRetarget:
            runKeyboardRetargetScenario()
        case .clickSupersede:
            runClickSupersedeScenario()
        case .bottomRevealJoin:
            runBottomRevealJoinScenario()
        case .reorderCommit:
            runReorderCommitScenario()
        }
        lastResultSummary = result.summary
    }

    func runKeyboardRetargetScenario() -> MainWorkspaceMotionRegressionResult {
        let scheduler = MainCanvasMotionManualScheduler()
        let coordinator = makeCoordinator(scheduler: scheduler)
        let sourceID = UUID()
        let targetID = UUID()
        let intentA = coordinator.publishIntent(
            kind: .focusChange,
            scope: .allColumns,
            targetCardID: sourceID,
            expectedActiveCardID: sourceID,
            animated: true,
            trigger: "arrowPreview"
        )
        guard let staleHandle = coordinator.claimMotionParticipant(
            for: "main.horizontal",
            axis: .horizontal,
            intent: intentA
        ) else {
            return failure(.keyboardRetarget, "failed to claim first handle")
        }

        var staleVerificationRan = false
        let staleWorkItem = DispatchWorkItem {
            staleVerificationRan = true
        }
        coordinator.replaceMotionTask(staleWorkItem, kind: .verification, handle: staleHandle)
        scheduler.schedule(
            after: coordinator.motionPolicy.verificationDelay(animated: true, attempt: 0),
            workItem: staleWorkItem
        )

        let intentB = coordinator.publishIntent(
            kind: .focusChange,
            scope: .allColumns,
            targetCardID: targetID,
            expectedActiveCardID: targetID,
            animated: false,
            trigger: "arrowPreview"
        )
        guard intentB.sessionID == intentA.sessionID,
              intentB.sessionRevision == intentA.sessionRevision + 1 else {
            return failure(.keyboardRetarget, "session revision did not retarget in place")
        }
        guard !coordinator.isMotionParticipantCurrent(staleHandle) else {
            return failure(.keyboardRetarget, "stale horizontal handle stayed current")
        }
        guard let currentHandle = coordinator.claimMotionParticipant(
            for: "main.horizontal",
            axis: .horizontal,
            intent: intentB
        ) else {
            return failure(.keyboardRetarget, "failed to claim retargeted handle")
        }

        coordinator.updateMotionParticipantState(.aligned, handle: currentHandle)
        scheduler.runAll()

        guard !staleVerificationRan else {
            return failure(.keyboardRetarget, "stale retry executed after retarget")
        }
        guard coordinator.activeMotionSessionSnapshot() == nil else {
            return failure(.keyboardRetarget, "session did not close after aligned retarget")
        }
        return success(.keyboardRetarget, "stale retry cancelled and revision advanced")
    }

    func runClickSupersedeScenario() -> MainWorkspaceMotionRegressionResult {
        let scheduler = MainCanvasMotionManualScheduler()
        let coordinator = makeCoordinator(scheduler: scheduler)
        let clickTargetID = UUID()
        let newerTargetID = UUID()
        let clickIntent = coordinator.publishIntent(
            kind: .focusChange,
            scope: .allColumns,
            targetCardID: clickTargetID,
            expectedActiveCardID: clickTargetID,
            animated: true,
            trigger: "clickFocus"
        )
        guard let staleHandle = coordinator.claimMotionParticipant(
            for: "main.horizontal",
            axis: .horizontal,
            intent: clickIntent
        ) else {
            return failure(.clickSupersede, "failed to claim click handle")
        }

        var staleFocusRan = false
        let staleWorkItem = DispatchWorkItem {
            staleFocusRan = true
        }
        coordinator.replaceMotionTask(staleWorkItem, kind: .focus, handle: staleHandle)
        scheduler.schedule(after: 0.02, workItem: staleWorkItem)

        let newerIntent = coordinator.publishIntent(
            kind: .focusChange,
            scope: .allColumns,
            targetCardID: newerTargetID,
            expectedActiveCardID: newerTargetID,
            animated: false,
            trigger: "activeCardChange"
        )
        guard !coordinator.isMotionParticipantCurrent(staleHandle) else {
            return failure(.clickSupersede, "click handle stayed current after supersede")
        }
        guard let currentHandle = coordinator.claimMotionParticipant(
            for: "main.horizontal",
            axis: .horizontal,
            intent: newerIntent
        ) else {
            return failure(.clickSupersede, "failed to claim superseding handle")
        }

        coordinator.updateMotionParticipantState(.aligned, handle: currentHandle)
        scheduler.runAll()

        guard !staleFocusRan else {
            return failure(.clickSupersede, "stale click retry executed after supersede")
        }
        return success(.clickSupersede, "newer focus beat pending click retry")
    }

    func runBottomRevealJoinScenario() -> MainWorkspaceMotionRegressionResult {
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
        guard let rootHandle = coordinator.claimMotionParticipant(
            for: "root.column",
            axis: .vertical,
            intent: focusIntent
        ) else {
            return failure(.bottomRevealJoin, "failed to claim root vertical participant")
        }

        let bottomIntent = coordinator.publishIntent(
            kind: .bottomReveal,
            scope: .viewport("child.column"),
            targetCardID: revealID,
            expectedActiveCardID: revealID,
            animated: false,
            trigger: "bottomReveal"
        )
        guard bottomIntent.sessionID == focusIntent.sessionID,
              bottomIntent.sessionRevision == focusIntent.sessionRevision else {
            return failure(.bottomRevealJoin, "bottom reveal spawned a second session")
        }
        guard coordinator.activeMotionSessionSnapshot()?.goal == .bottomReveal(cardID: revealID) else {
            return failure(.bottomRevealJoin, "session goal did not switch to bottom reveal")
        }
        guard let childHandle = coordinator.claimMotionParticipant(
            for: "child.column",
            axis: .vertical,
            intent: bottomIntent
        ) else {
            return failure(.bottomRevealJoin, "failed to late-join bottom reveal participant")
        }

        coordinator.updateObservedFrames([anchorID: CGRect(x: 0, y: 0, width: 100, height: 40)], for: "root.column")
        coordinator.updateObservedFrames([revealID: CGRect(x: 0, y: 400, width: 100, height: 220)], for: "child.column")
        coordinator.updateMotionParticipantState(.aligned, handle: rootHandle)
        coordinator.updateMotionParticipantState(.aligned, handle: childHandle)
        scheduler.runAll()

        guard coordinator.activeMotionSessionSnapshot() == nil else {
            return failure(.bottomRevealJoin, "joined session did not close")
        }
        return success(.bottomRevealJoin, "bottom reveal joined active session and closed cleanly")
    }

    func runReorderCommitScenario() -> MainWorkspaceMotionRegressionResult {
        let scheduler = MainCanvasMotionManualScheduler()
        let coordinator = makeCoordinator(scheduler: scheduler)
        let scrollView = makeHorizontalScrollView()
        coordinator.registerMainCanvasHorizontalScrollView(scrollView)
        setHorizontalOffset(140, on: scrollView)
        coordinator.updateMainCanvasHorizontalOffset(140)

        let targetID = UUID()
        let initialIntent = coordinator.publishIntent(
            kind: .focusChange,
            scope: .allColumns,
            targetCardID: targetID,
            expectedActiveCardID: targetID,
            animated: true,
            trigger: "activeCardChange"
        )
        guard let staleHandle = coordinator.claimMotionParticipant(
            for: "main.horizontal",
            axis: .horizontal,
            intent: initialIntent
        ) else {
            return failure(.reorderCommit, "failed to claim pre-drop handle")
        }

        var staleRetryRan = false
        let staleWorkItem = DispatchWorkItem {
            staleRetryRan = true
        }
        coordinator.replaceMotionTask(staleWorkItem, kind: .verification, handle: staleHandle)
        scheduler.schedule(after: 0.04, workItem: staleWorkItem)

        setHorizontalOffset(32, on: scrollView)
        coordinator.updateMainCanvasHorizontalOffset(32)
        coordinator.scheduleMainCanvasHorizontalRestore(offsetX: 140)
        guard abs(scrollView.contentView.bounds.origin.x - 32) <= 0.5 else {
            return failure(.reorderCommit, "restore applied before reorder session closed")
        }

        let reorderIntent = coordinator.publishIntent(
            kind: .focusChange,
            scope: .allColumns,
            targetCardID: targetID,
            expectedActiveCardID: targetID,
            animated: false,
            trigger: "reorderCommit"
        )
        guard reorderIntent.sessionID == initialIntent.sessionID,
              reorderIntent.sessionRevision == initialIntent.sessionRevision + 1 else {
            return failure(.reorderCommit, "reorder did not supersede existing session")
        }
        guard !coordinator.isMotionParticipantCurrent(staleHandle) else {
            return failure(.reorderCommit, "stale pre-drop handle survived reorder commit")
        }
        guard let reorderHandle = coordinator.claimMotionParticipant(
            for: "main.horizontal",
            axis: .horizontal,
            intent: reorderIntent
        ) else {
            return failure(.reorderCommit, "failed to claim reorder session handle")
        }

        coordinator.updateMotionParticipantState(.aligned, handle: reorderHandle)
        scheduler.runAll()

        guard !staleRetryRan else {
            return failure(.reorderCommit, "pre-drop retry executed after reorder commit")
        }
        guard abs(scrollView.contentView.bounds.origin.x - 140) <= 0.5 else {
            return failure(.reorderCommit, "deferred horizontal preserve did not replay after close")
        }
        return success(.reorderCommit, "post-drop preserve replayed after supersede")
    }

    private func makeCoordinator(scheduler: MainCanvasMotionManualScheduler) -> MainCanvasScrollCoordinator {
        MainCanvasScrollCoordinator(
            scheduleMotionWorkItem: { delay, workItem in
                scheduler.schedule(after: delay, workItem: workItem)
            }
        )
    }

    private func makeHorizontalScrollView() -> NSScrollView {
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        let documentView = NSView(frame: CGRect(x: 0, y: 0, width: 1600, height: 240))
        scrollView.documentView = documentView
        scrollView.hasHorizontalScroller = true
        return scrollView
    }

    private func setHorizontalOffset(_ offsetX: CGFloat, on scrollView: NSScrollView) {
        let point = CGPoint(x: offsetX, y: scrollView.contentView.bounds.origin.y)
        scrollView.contentView.scroll(to: point)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func success(
        _ scenario: MainWorkspaceMotionRegressionScenario,
        _ details: String
    ) -> MainWorkspaceMotionRegressionResult {
        MainWorkspaceMotionRegressionResult(
            scenario: scenario,
            passed: true,
            details: details
        )
    }

    private func failure(
        _ scenario: MainWorkspaceMotionRegressionScenario,
        _ details: String
    ) -> MainWorkspaceMotionRegressionResult {
        MainWorkspaceMotionRegressionResult(
            scenario: scenario,
            passed: false,
            details: details
        )
    }
}

@MainActor
struct MainWorkspaceMotionRegressionHarnessView: View {
    @StateObject private var harness = MainWorkspaceMotionRegressionHarness()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Main Workspace Motion Kernel Harness")
                .font(.headline)
                .accessibilityIdentifier("motion-harness-title")

            ForEach(MainWorkspaceMotionRegressionScenario.allCases) { scenario in
                Button(scenario.title) {
                    harness.run(scenario)
                }
                .accessibilityIdentifier("motion-\(scenario.rawValue)-button")
            }

            TextField("", text: .constant(harness.lastResultSummary))
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .disabled(true)
                .padding(.top, 8)
                .accessibilityIdentifier("motion-result-field")
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 280, alignment: .topLeading)
    }
}
#endif
