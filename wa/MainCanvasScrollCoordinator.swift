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

    enum NavigationIntentKind: String {
        case focusChange
        case settleRecovery
        case childListChange
        case columnAppear
        case bottomReveal
    }

    enum NavigationIntentScope: Equatable {
        case allColumns
        case viewport(String)
    }

    struct NavigationIntent: Equatable {
        let id: Int
        let kind: NavigationIntentKind
        let scope: NavigationIntentScope
        let targetCardID: UUID?
        let expectedActiveCardID: UUID?
        let animated: Bool
        let trigger: String
    }

    private final class ScrollViewEntry {
        weak var scrollView: NSScrollView?

        init(scrollView: NSScrollView) {
            self.scrollView = scrollView
        }
    }

    @Published private(set) var navigationIntentTick: Int = 0

    private var intentSequence: Int = 0
    private var latestGlobalIntent: NavigationIntent?
    private var latestScopedIntentByViewportKey: [String: NavigationIntent] = [:]
    private var lastConsumedIntentIDByViewportKey: [String: Int] = [:]
    private var scrollViewEntriesByViewportKey: [String: ScrollViewEntry] = [:]
    private var geometryModelByViewportKey: [String: MainColumnGeometryModel] = [:]
    private weak var mainCanvasHorizontalScrollView: NSScrollView?
    private var mainCanvasHorizontalOffsetSnapshot: CGFloat?
    private var pendingMainCanvasHorizontalRestoreX: CGFloat?

    func reset() {
        intentSequence = 0
        navigationIntentTick = 0
        latestGlobalIntent = nil
        latestScopedIntentByViewportKey = [:]
        lastConsumedIntentIDByViewportKey = [:]
        geometryModelByViewportKey = [:]
        mainCanvasHorizontalScrollView = nil
        mainCanvasHorizontalOffsetSnapshot = nil
        pendingMainCanvasHorizontalRestoreX = nil
        pruneReleasedScrollViews()
    }

    @discardableResult
    func publishIntent(
        kind: NavigationIntentKind,
        scope: NavigationIntentScope,
        targetCardID: UUID? = nil,
        expectedActiveCardID: UUID? = nil,
        animated: Bool,
        trigger: String
    ) -> NavigationIntent {
        intentSequence &+= 1
        let intent = NavigationIntent(
            id: intentSequence,
            kind: kind,
            scope: scope,
            targetCardID: targetCardID,
            expectedActiveCardID: expectedActiveCardID,
            animated: animated,
            trigger: trigger
        )

        switch scope {
        case .allColumns:
            latestGlobalIntent = intent
        case .viewport(let viewportKey):
            latestScopedIntentByViewportKey[viewportKey] = intent
        }

        navigationIntentTick &+= 1
        return intent
    }

    func consumeLatestIntent(for viewportKey: String) -> NavigationIntent? {
        guard let intent = latestRelevantIntent(for: viewportKey) else { return nil }
        if lastConsumedIntentIDByViewportKey[viewportKey] == intent.id {
            return nil
        }
        lastConsumedIntentIDByViewportKey[viewportKey] = intent.id
        return intent
    }

    func isIntentCurrent(_ intentID: Int, for viewportKey: String) -> Bool {
        latestRelevantIntent(for: viewportKey)?.id == intentID
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
        if let scrollView = mainCanvasHorizontalScrollView {
            applyPendingMainCanvasHorizontalRestoreIfNeeded(to: scrollView)
        }
    }

    private func latestRelevantIntent(for viewportKey: String) -> NavigationIntent? {
        let scopedIntent = latestScopedIntentByViewportKey[viewportKey]
        switch (latestGlobalIntent, scopedIntent) {
        case let (global?, scoped?):
            return scoped.id >= global.id ? scoped : global
        case let (global?, nil):
            return global
        case let (nil, scoped?):
            return scoped
        case (nil, nil):
            return nil
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

        // Wait until the recreated canvas can actually scroll horizontally;
        // otherwise an early restore clamps to zero and strands the viewport at root.
        if targetX > 1, maxX <= 1 {
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

        let targetReachable = maxX + 0.5 >= targetX
        if targetReachable, abs(resolvedTargetX - scrollView.contentView.bounds.origin.x) <= 0.5 {
            pendingMainCanvasHorizontalRestoreX = nil
        }
    }
}
