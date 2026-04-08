import AppKit
import Combine
import Foundation

@MainActor
final class MainCanvasScrollCoordinator: ObservableObject {
    struct MainColumnGeometryModel {
        var observedFramesByCardID: [UUID: CGRect] = [:]

        var hasObservedFrames: Bool {
            !observedFramesByCardID.isEmpty
        }

        func observedFrame(for cardID: UUID) -> CGRect? {
            observedFramesByCardID[cardID]
        }
    }

    private final class ScrollViewEntry {
        weak var scrollView: NSScrollView?

        init(scrollView: NSScrollView) {
            self.scrollView = scrollView
        }
    }

    private var scrollViewEntriesByViewportKey: [String: ScrollViewEntry] = [:]
    private var geometryModelByViewportKey: [String: MainColumnGeometryModel] = [:]
    private weak var mainCanvasHorizontalScrollView: NSScrollView?
    private var mainCanvasHorizontalOffsetSnapshot: CGFloat?
    private var pendingMainCanvasHorizontalRestoreX: CGFloat?

    func reset() {
        geometryModelByViewportKey = [:]
        mainCanvasHorizontalScrollView = nil
        mainCanvasHorizontalOffsetSnapshot = nil
        pendingMainCanvasHorizontalRestoreX = nil
        pruneReleasedScrollViews()
    }

    func register(scrollView: NSScrollView, for viewportKey: String) {
        scrollViewEntriesByViewportKey[viewportKey] = ScrollViewEntry(scrollView: scrollView)
        pruneReleasedScrollViews()
    }

    func unregister(viewportKey: String, matching scrollView: NSScrollView? = nil) {
        guard let entry = scrollViewEntriesByViewportKey[viewportKey] else { return }
        if let scrollView {
            guard entry.scrollView === scrollView else { return }
        }
        scrollViewEntriesByViewportKey.removeValue(forKey: viewportKey)
        geometryModelByViewportKey.removeValue(forKey: viewportKey)
    }

    func scrollView(for viewportKey: String) -> NSScrollView? {
        if let scrollView = scrollViewEntriesByViewportKey[viewportKey]?.scrollView {
            return scrollView
        }
        scrollViewEntriesByViewportKey.removeValue(forKey: viewportKey)
        return nil
    }

    func updateObservedFrames(_ frames: [UUID: CGRect], for viewportKey: String) {
        geometryModelByViewportKey[viewportKey] = MainColumnGeometryModel(observedFramesByCardID: frames)
    }

    func observedFrame(for viewportKey: String, cardID: UUID) -> CGRect? {
        geometryModelByViewportKey[viewportKey]?.observedFrame(for: cardID)
    }

    func geometryModel(for viewportKey: String) -> MainColumnGeometryModel? {
        geometryModelByViewportKey[viewportKey]
    }

    func registerMainCanvasHorizontalScrollView(_ scrollView: NSScrollView) {
        mainCanvasHorizontalScrollView = scrollView
        mainCanvasHorizontalOffsetSnapshot = max(0, scrollView.contentView.bounds.origin.x)
        indexBoardRestoreTrace(
            "coordinator_register_horizontal_scroll_view",
            "offset=\(debugRestoreCGFloat(scrollView.contentView.bounds.origin.x)) " +
            "visibleWidth=\(String(format: "%.2f", scrollView.documentVisibleRect.width)) " +
            "documentWidth=\(String(format: "%.2f", scrollView.documentView?.bounds.width ?? 0))"
        )
        applyPendingMainCanvasHorizontalRestoreIfNeeded(to: scrollView)
    }

    func unregisterMainCanvasHorizontalScrollView(matching scrollView: NSScrollView? = nil) {
        guard let current = mainCanvasHorizontalScrollView else { return }
        if let scrollView {
            guard current === scrollView else { return }
        }
        mainCanvasHorizontalScrollView = nil
    }

    func resolvedMainCanvasHorizontalScrollView() -> NSScrollView? {
        mainCanvasHorizontalScrollView
    }

    func updateMainCanvasHorizontalOffset(_ offsetX: CGFloat) {
        mainCanvasHorizontalOffsetSnapshot = max(0, offsetX)
    }

    func resolvedMainCanvasHorizontalOffset() -> CGFloat? {
        if let scrollView = mainCanvasHorizontalScrollView {
            let liveOffset = max(0, scrollView.contentView.bounds.origin.x)
            mainCanvasHorizontalOffsetSnapshot = liveOffset
            return liveOffset
        }
        return mainCanvasHorizontalOffsetSnapshot
    }

    func refreshMainCanvasHorizontalScrollViewState(_ scrollView: NSScrollView) {
        guard mainCanvasHorizontalScrollView === scrollView else { return }
        mainCanvasHorizontalOffsetSnapshot = max(0, scrollView.contentView.bounds.origin.x)
        applyPendingMainCanvasHorizontalRestoreIfNeeded(to: scrollView)
    }

    func scheduleMainCanvasHorizontalRestore(offsetX: CGFloat) {
        pendingMainCanvasHorizontalRestoreX = max(0, offsetX)
        indexBoardRestoreTrace(
            "coordinator_schedule_horizontal_restore",
            "targetOffset=\(debugRestoreCGFloat(offsetX)) hasLiveScrollView=\(self.mainCanvasHorizontalScrollView != nil)"
        )
        if let scrollView = mainCanvasHorizontalScrollView {
            applyPendingMainCanvasHorizontalRestoreIfNeeded(to: scrollView)
        }
    }

    private func pruneReleasedScrollViews() {
        scrollViewEntriesByViewportKey = scrollViewEntriesByViewportKey.filter { $0.value.scrollView != nil }
    }

    private func applyPendingMainCanvasHorizontalRestoreIfNeeded(to scrollView: NSScrollView) {
        guard let targetX = pendingMainCanvasHorizontalRestoreX else { return }
        let visibleRect = scrollView.documentVisibleRect
        let documentWidth = scrollView.documentView?.bounds.width ?? 0
        let maxX = max(0, documentWidth - visibleRect.width)
        indexBoardRestoreTrace(
            "coordinator_apply_pending_horizontal_restore_begin",
            "targetOffset=\(debugRestoreCGFloat(targetX)) currentOffset=\(debugRestoreCGFloat(scrollView.contentView.bounds.origin.x)) " +
            "visibleWidth=\(String(format: "%.2f", visibleRect.width)) documentWidth=\(String(format: "%.2f", documentWidth)) maxX=\(String(format: "%.2f", maxX))"
        )

        // Wait until the recreated canvas can actually scroll horizontally;
        // otherwise an early restore clamps to zero and strands the viewport at root.
        if targetX > 1, maxX <= 1 {
            indexBoardRestoreTrace(
                "coordinator_apply_pending_horizontal_restore_deferred",
                "reason=documentNotScrollableYet targetOffset=\(debugRestoreCGFloat(targetX)) maxX=\(String(format: "%.2f", maxX))"
            )
            return
        }

        let resolvedTargetX = CaretScrollCoordinator.resolvedHorizontalTargetX(
            visibleRect: visibleRect,
            targetX: targetX,
            minX: 0,
            maxX: maxX,
            snapToPixel: true
        )
        _ = CaretScrollCoordinator.applyHorizontalScrollIfNeeded(
            scrollView: scrollView,
            visibleRect: visibleRect,
            targetX: targetX,
            minX: 0,
            maxX: maxX,
            deadZone: 0.5,
            snapToPixel: true
        )
        mainCanvasHorizontalOffsetSnapshot = max(0, scrollView.contentView.bounds.origin.x)
        indexBoardRestoreTrace(
            "coordinator_apply_pending_horizontal_restore_applied",
            "targetOffset=\(debugRestoreCGFloat(targetX)) resolvedTarget=\(debugRestoreCGFloat(resolvedTargetX)) " +
            "currentOffset=\(debugRestoreCGFloat(scrollView.contentView.bounds.origin.x))"
        )

        let targetReachable = maxX + 0.5 >= targetX
        if targetReachable, abs(resolvedTargetX - scrollView.contentView.bounds.origin.x) <= 0.5 {
            pendingMainCanvasHorizontalRestoreX = nil
            indexBoardRestoreTrace(
                "coordinator_apply_pending_horizontal_restore_cleared",
                "targetOffset=\(debugRestoreCGFloat(targetX))"
            )
        }
    }
}
