import AppKit
import SwiftUI

enum MainCanvasSurfaceFocusAlignment {
    static let defaultAnchorY: CGFloat = 0.25

    static func resolvedTargetOffsetY(
        predictedTarget: MainCanvasSurfacePredictedTarget,
        viewportHeight: CGFloat
    ) -> CGFloat {
        let resolvedViewportHeight = max(1, viewportHeight)
        let anchorY = min(max(0, defaultAnchorY), 1)
        return max(0, predictedTarget.targetMinY - (resolvedViewportHeight * anchorY))
    }
}

struct MainCanvasSurfacePredictedTarget: Equatable {
    let targetCardID: UUID
    let targetMinY: CGFloat
    let targetMaxY: CGFloat
    let layoutKey: MainColumnLayoutCacheKey
}

struct MainCanvasSurfaceViewportDescriptor: Identifiable {
    let level: Int
    let viewportKey: String
    let frame: CGRect
    let desiredOffsetY: CGFloat
    let documentSnapshot: MainCanvasSurfaceDocumentSnapshot
    let predictedFocusTarget: MainCanvasSurfacePredictedTarget?
    let predictedBottomRevealTarget: MainCanvasSurfacePredictedTarget?
    let content: AnyView

    var id: String { viewportKey }
}

struct MainCanvasSurfaceConfiguration {
    let contentSize: CGSize
    let activeLevel: Int?
    let descriptors: [MainCanvasSurfaceViewportDescriptor]
    let motionSessionCloseTick: Int
    let motionCorrectionGateTick: Int
    let motionCorrectionGateSnapshot: MainCanvasScrollCoordinator.MotionCorrectionGateSnapshot?
    let diagnosticsOwnerKey: String
    let onLiveOffsetChange: (String, CGFloat) -> Void
    let onViewportFinalize: (String, CGFloat) -> Void
}

struct MainCanvasSurfaceViewportHost: NSViewRepresentable {
    let configuration: MainCanvasSurfaceConfiguration
    let scrollCoordinator: MainCanvasScrollCoordinator

    func makeNSView(context: Context) -> MainCanvasSurfaceViewportContainerView {
        MainCanvasSurfaceViewportContainerView(
            configuration: configuration,
            scrollCoordinator: scrollCoordinator
        )
    }

    func updateNSView(_ nsView: MainCanvasSurfaceViewportContainerView, context: Context) {
        nsView.update(
            configuration: configuration,
            scrollCoordinator: scrollCoordinator
        )
    }

    static func dismantleNSView(
        _ nsView: MainCanvasSurfaceViewportContainerView,
        coordinator: ()
    ) {
        nsView.flushViewportPersistenceForTeardown()
    }
}

private final class MainCanvasSurfaceViewportScrollView: NSScrollView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

final class MainCanvasSurfaceViewportContainerView: NSView {
    override var isFlipped: Bool { true }

    private var configuration: MainCanvasSurfaceConfiguration
    private weak var scrollCoordinator: MainCanvasScrollCoordinator?
    private weak var horizontalScrollView: NSScrollView?
    private var horizontalBoundsObserver: NSObjectProtocol?
    private var attachRetryWorkItem: DispatchWorkItem?
    private var nodesByViewportKey: [String: MainCanvasColumnViewportNode] = [:]
    private var nodeSyncScheduled = false

    init(
        configuration: MainCanvasSurfaceConfiguration,
        scrollCoordinator: MainCanvasScrollCoordinator
    ) {
        self.configuration = configuration
        self.scrollCoordinator = scrollCoordinator
        super.init(frame: CGRect(origin: .zero, size: configuration.contentSize))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        detachHorizontalObserver()
        flushViewportPersistenceForTeardown()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        for subview in subviews.reversed() {
            let convertedPoint = subview.convert(point, from: self)
            if let hitView = subview.hitTest(convertedPoint) {
                return hitView
            }
        }
        return nil
    }

    override func layout() {
        super.layout()
        synchronizeNodes()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachToHorizontalScrollViewIfNeeded()
        scheduleNodeSync()
    }

    func update(
        configuration: MainCanvasSurfaceConfiguration,
        scrollCoordinator: MainCanvasScrollCoordinator
    ) {
        self.configuration = configuration
        self.scrollCoordinator = scrollCoordinator
        frame = CGRect(origin: .zero, size: configuration.contentSize)
        attachToHorizontalScrollViewIfNeeded()
        scheduleNodeSync()
    }

    func flushViewportPersistenceForTeardown() {
        for node in nodesByViewportKey.values {
            node.flushViewportPersistenceForTeardown()
        }
    }

    private func attachToHorizontalScrollViewIfNeeded() {
        guard let resolvedScrollView = resolveHorizontalScrollView() else {
            scheduleAttachRetry()
            return
        }

        attachRetryWorkItem?.cancel()
        attachRetryWorkItem = nil

        guard horizontalScrollView !== resolvedScrollView else { return }
        detachHorizontalObserver()
        horizontalScrollView = resolvedScrollView
        resolvedScrollView.contentView.postsBoundsChangedNotifications = true
        horizontalBoundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: resolvedScrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleNodeSync()
        }
    }

    private func detachHorizontalObserver() {
        attachRetryWorkItem?.cancel()
        attachRetryWorkItem = nil
        if let horizontalBoundsObserver {
            NotificationCenter.default.removeObserver(horizontalBoundsObserver)
        }
        horizontalBoundsObserver = nil
        horizontalScrollView = nil
    }

    private func scheduleAttachRetry() {
        guard attachRetryWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.attachRetryWorkItem = nil
            self.attachToHorizontalScrollViewIfNeeded()
        }
        attachRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    private func scheduleNodeSync() {
        guard !nodeSyncScheduled else { return }
        nodeSyncScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.nodeSyncScheduled = false
            self.synchronizeNodes()
        }
    }

    private func synchronizeNodes() {
        let desiredViewportKeys = resolvedPooledViewportKeys()
        let descriptorsByKey = Dictionary(
            uniqueKeysWithValues: configuration.descriptors.map { ($0.viewportKey, $0) }
        )

        for (viewportKey, node) in nodesByViewportKey where !desiredViewportKeys.contains(viewportKey) {
            node.flushViewportPersistenceForTeardown()
            node.removeFromSuperview()
            nodesByViewportKey.removeValue(forKey: viewportKey)
        }

        for viewportKey in desiredViewportKeys {
            guard let descriptor = descriptorsByKey[viewportKey] else { continue }
            if let node = nodesByViewportKey[viewportKey] {
                node.update(
                    descriptor: descriptor,
                    configuration: configuration,
                    scrollCoordinator: scrollCoordinator
                )
            } else {
                let node = MainCanvasColumnViewportNode(
                    descriptor: descriptor,
                    configuration: configuration,
                    scrollCoordinator: scrollCoordinator
                )
                nodesByViewportKey[viewportKey] = node
                addSubview(node)
            }
        }
    }

    private func resolvedPooledViewportKeys() -> Set<String> {
        Set(configuration.descriptors.map(\.viewportKey))
    }

    private func horizontalVisibleRect() -> CGRect {
        guard let scrollView = horizontalScrollView else {
            return bounds
        }
        return scrollView.contentView.bounds
    }

    private func resolveHorizontalScrollView() -> NSScrollView? {
        if let horizontalScrollView {
            return horizontalScrollView
        }

        var currentView: NSView? = self
        while let candidate = currentView {
            if let scrollView = candidate.enclosingScrollView {
                return scrollView
            }
            currentView = candidate.superview
        }
        return nil
    }
}

private final class MainCanvasColumnViewportNode: NSView {
    override var isFlipped: Bool { true }

    private enum PendingMotionKind {
        case focus
        case bottomReveal
    }

    private struct PendingMotion {
        let sessionID: Int
        let sessionRevision: Int
        let intentID: Int
        let kind: PendingMotionKind
        let capturedTarget: MainCanvasSurfacePredictedTarget
        var latestTarget: MainCanvasSurfacePredictedTarget
        var correctionRequired: Bool
    }

    private struct MotionDispatchResult {
        let duration: TimeInterval
        let requiresCorrection: Bool
        let reachedTarget: Bool
    }

    private let scrollView = MainCanvasSurfaceViewportScrollView(frame: .zero)
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private let viewportKey: String
    private var currentDescriptor: MainCanvasSurfaceViewportDescriptor
    private var desiredOffsetY: CGFloat
    private var configuration: MainCanvasSurfaceConfiguration
    private weak var scrollCoordinator: MainCanvasScrollCoordinator?
    private weak var registeredScrollCoordinator: MainCanvasScrollCoordinator?
    private var scrollObserver: NSObjectProtocol?
    private var deferredRestoreAttemptsRemaining = 0
    private var deferredRestoreWorkItem: DispatchWorkItem?
    private var lastReportedOffsetY: CGFloat = .nan
    private var lastReportedDocumentSize: CGSize = .zero
    private var lastAppliedDocumentLayoutKey: MainColumnLayoutCacheKey?
    private var lastAppliedViewportSize: CGSize = .zero
    private var isApplyingDesiredOffset = false
    private var isRestoringInitialViewport = true
    private var pendingMotion: PendingMotion?
    private var lastProcessedMotionSessionCloseTick: Int
    private var lastProcessedMotionCorrectionGateTick: Int

    init(
        descriptor: MainCanvasSurfaceViewportDescriptor,
        configuration: MainCanvasSurfaceConfiguration,
        scrollCoordinator: MainCanvasScrollCoordinator?
    ) {
        self.viewportKey = descriptor.viewportKey
        self.currentDescriptor = descriptor
        self.desiredOffsetY = max(0, descriptor.desiredOffsetY)
        self.configuration = configuration
        self.scrollCoordinator = scrollCoordinator
        self.lastProcessedMotionSessionCloseTick = configuration.motionSessionCloseTick
        self.lastProcessedMotionCorrectionGateTick = configuration.motionCorrectionGateTick
        super.init(frame: descriptor.frame)
        configureScrollView()
        hostingView.rootView = descriptor.content
        scrollView.documentView = hostingView
        addSubview(scrollView)
        installScrollObserver()
        update(
            descriptor: descriptor,
            configuration: configuration,
            scrollCoordinator: scrollCoordinator
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
        }
        deferredRestoreWorkItem?.cancel()
        deferredRestoreWorkItem = nil
        flushViewportPersistenceForTeardown()
        unregisterScrollViewIfNeeded()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        let pointInScrollView = scrollView.convert(point, from: self)
        return scrollView.hitTest(pointInScrollView) ?? scrollView
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        refreshDocumentLayoutIfNeeded()
        applyDesiredOffsetIfNeeded()
        scheduleDeferredRestoreIfNeeded()
        updateInitialViewportPresentation()
    }

    func update(
        descriptor: MainCanvasSurfaceViewportDescriptor,
        configuration: MainCanvasSurfaceConfiguration,
        scrollCoordinator: MainCanvasScrollCoordinator?
    ) {
        self.currentDescriptor = descriptor
        self.configuration = configuration
        self.scrollCoordinator = scrollCoordinator
        desiredOffsetY = max(0, descriptor.desiredOffsetY)
        frame = descriptor.frame
        hostingView.rootView = descriptor.content
        registerScrollViewIfNeeded()
        refreshDocumentLayoutIfNeeded()
        applyDesiredOffsetIfNeeded()
        consumeMotionIntentIfNeeded(descriptor: descriptor)
        refreshPendingMotionState(descriptor: descriptor)
        scheduleDeferredRestoreIfNeeded()
        updateInitialViewportPresentation()
        handleMotionCorrectionGateIfNeeded()
        handleMotionSessionCloseIfNeeded()
    }

    func flushViewportPersistenceForTeardown() {
        let originY = max(0, scrollView.contentView.bounds.origin.y)
        configuration.onViewportFinalize(viewportKey, originY)
    }

    private func configureScrollView() {
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero
        scrollView.scrollerInsets = NSEdgeInsetsZero
        scrollView.contentView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.contentInsets = NSEdgeInsetsZero
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.postsBoundsChangedNotifications = true
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.isFlipped = true
    }

    private func installScrollObserver() {
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.handleScrollChanged()
        }
    }

    private func registerScrollViewIfNeeded() {
        guard let scrollCoordinator else {
            unregisterScrollViewIfNeeded()
            return
        }
        guard registeredScrollCoordinator !== scrollCoordinator else { return }
        unregisterScrollViewIfNeeded()
        registeredScrollCoordinator = scrollCoordinator
        scrollCoordinator.register(scrollView: scrollView, for: viewportKey)
    }

    private func unregisterScrollViewIfNeeded() {
        if let registeredScrollCoordinator {
            registeredScrollCoordinator.unregister(viewportKey: viewportKey, matching: scrollView)
        }
        registeredScrollCoordinator = nil
    }

    private func refreshDocumentLayout() {
        let nextDocumentSize = resolvedDocumentSize()

        if hostingView.frame.size != nextDocumentSize {
            hostingView.frame = CGRect(origin: .zero, size: nextDocumentSize)
        }

        if sizeChanged(from: lastReportedDocumentSize, to: nextDocumentSize) {
            lastReportedDocumentSize = nextDocumentSize
            markPendingMotionCorrectionRequired()
        }

        clampCurrentOffsetToDocumentBounds()
    }

    private func refreshDocumentLayoutIfNeeded() {
        let currentViewportSize = bounds.size
        let currentLayoutKey = currentDescriptor.documentSnapshot.layoutKey
        let needsRefresh =
            lastReportedDocumentSize == .zero ||
            lastAppliedDocumentLayoutKey != currentLayoutKey ||
            sizeChanged(from: lastAppliedViewportSize, to: currentViewportSize)
        guard needsRefresh else { return }
        refreshDocumentLayout()
        lastAppliedDocumentLayoutKey = currentLayoutKey
        lastAppliedViewportSize = currentViewportSize
    }

    private func clampCurrentOffsetToDocumentBounds() {
        let currentOffsetY = max(0, scrollView.contentView.bounds.origin.y)
        let maxOffsetY = resolvedMaximumOffsetY()
        let clampedOffsetY = min(currentOffsetY, maxOffsetY)
        guard abs(currentOffsetY - clampedOffsetY) > 0.5 else { return }
        markPendingMotionCorrectionRequired()
        isApplyingDesiredOffset = true
        scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: clampedOffsetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        isApplyingDesiredOffset = false
        publishOffsetIfNeeded(clampedOffsetY)
    }

    private func applyDesiredOffsetIfNeeded() {
        let currentOffsetY = max(0, scrollView.contentView.bounds.origin.y)
        let clampedDesiredOffsetY = min(desiredOffsetY, resolvedMaximumOffsetY())
        guard abs(currentOffsetY - clampedDesiredOffsetY) > 0.5 else {
            publishOffsetIfNeeded(clampedDesiredOffsetY)
            return
        }
        isApplyingDesiredOffset = true
        scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: clampedDesiredOffsetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        isApplyingDesiredOffset = false
        publishOffsetIfNeeded(clampedDesiredOffsetY)
    }

    private func handleScrollChanged() {
        guard !isApplyingDesiredOffset else { return }
        let currentOffsetY = max(0, scrollView.contentView.bounds.origin.y)
        publishOffsetIfNeeded(currentOffsetY)
        updateInitialViewportPresentation()
    }

    private func publishOffsetIfNeeded(_ offsetY: CGFloat) {
        guard lastReportedOffsetY.isNaN || abs(lastReportedOffsetY - offsetY) > 0.5 else { return }
        lastReportedOffsetY = offsetY
        configuration.onLiveOffsetChange(viewportKey, offsetY)
    }

    private func scheduleDeferredRestoreIfNeeded() {
        guard isRestoringInitialViewport else { return }
        guard initialViewportNeedsDeferredRestore() else {
            deferredRestoreAttemptsRemaining = 0
            deferredRestoreWorkItem?.cancel()
            deferredRestoreWorkItem = nil
            return
        }
        guard deferredRestoreWorkItem == nil else { return }
        deferredRestoreAttemptsRemaining = max(deferredRestoreAttemptsRemaining, 4)
        scheduleNextDeferredRestoreTick()
    }

    private func scheduleNextDeferredRestoreTick() {
        guard deferredRestoreAttemptsRemaining > 0 else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.deferredRestoreWorkItem = nil
            self.deferredRestoreAttemptsRemaining -= 1
            self.refreshDocumentLayout()
            self.applyDesiredOffsetIfNeeded()
            self.updateInitialViewportPresentation()
            if self.initialViewportNeedsDeferredRestore() && self.deferredRestoreAttemptsRemaining > 0 {
                self.scheduleNextDeferredRestoreTick()
            }
        }
        deferredRestoreWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    private func initialViewportNeedsDeferredRestore() -> Bool {
        guard desiredOffsetY > 1 else { return false }
        return abs(max(0, scrollView.contentView.bounds.origin.y) - desiredOffsetY) > 0.5 &&
            resolvedMaximumOffsetY() + 0.5 < desiredOffsetY
    }

    private func updateInitialViewportPresentation() {
        if isRestoringInitialViewport {
            let currentOffsetY = max(0, scrollView.contentView.bounds.origin.y)
            let restoreSettled =
                abs(currentOffsetY - min(desiredOffsetY, resolvedMaximumOffsetY())) <= 0.5 ||
                (deferredRestoreAttemptsRemaining == 0 && deferredRestoreWorkItem == nil)
            if restoreSettled {
                isRestoringInitialViewport = false
            }
        }
        scrollView.alphaValue = isRestoringInitialViewport ? 0 : 1
    }

    private func resolvedDocumentSize() -> CGSize {
        let width = max(1, bounds.width)
        let viewportHeight = max(1, bounds.height)
        return CGSize(
            width: width,
            height: currentDescriptor.documentSnapshot.resolvedDocumentHeight(
                viewportHeight: viewportHeight
            )
        )
    }

    private func resolvedMaximumOffsetY() -> CGFloat {
        let documentHeight = resolvedDocumentSize().height
        let viewportHeight = max(1, scrollView.contentView.bounds.height)
        return max(0, documentHeight - viewportHeight)
    }

    private func consumeMotionIntentIfNeeded(
        descriptor: MainCanvasSurfaceViewportDescriptor
    ) {
        guard let scrollCoordinator,
              let intent = scrollCoordinator.consumeLatestIntent(for: viewportKey) else {
            return
        }

        switch intent.kind {
        case .focusChange, .childListChange, .columnAppear:
            guard let predictedTarget = descriptor.predictedFocusTarget else { return }
            dispatchMotion(
                kind: .focus,
                predictedTarget: predictedTarget,
                intent: intent,
                scrollCoordinator: scrollCoordinator
            )
        case .bottomReveal:
            guard let predictedTarget = descriptor.predictedBottomRevealTarget else { return }
            dispatchMotion(
                kind: .bottomReveal,
                predictedTarget: predictedTarget,
                intent: intent,
                scrollCoordinator: scrollCoordinator
            )
        case .settleRecovery:
            return
        }
    }

    private func dispatchMotion(
        kind: PendingMotionKind,
        predictedTarget: MainCanvasSurfacePredictedTarget,
        intent: MainCanvasScrollCoordinator.NavigationIntent,
        scrollCoordinator: MainCanvasScrollCoordinator
    ) {
        guard let participantHandle = scrollCoordinator.claimMotionParticipant(
            for: viewportKey,
            axis: .vertical,
            intent: intent
        ) else {
            return
        }

        var motion = PendingMotion(
            sessionID: intent.sessionID,
            sessionRevision: intent.sessionRevision,
            intentID: intent.id,
            kind: kind,
            capturedTarget: predictedTarget,
            latestTarget: predictedTarget,
            correctionRequired: false
        )
        let dispatch = applyPredictedMotion(
            kind: kind,
            predictedTarget: predictedTarget,
            animated: intent.animated
        )
        motion.correctionRequired = dispatch.requiresCorrection
        pendingMotion = motion

        if !dispatch.reachedTarget {
            MainCanvasNavigationDiagnostics.shared.recordPredictedNativeScrollMiss(
                ownerKey: configuration.diagnosticsOwnerKey
            )
        }

        guard dispatch.duration > 0.001 else {
            scrollCoordinator.updateMotionParticipantState(.aligned, handle: participantHandle)
            return
        }

        scrollCoordinator.updateMotionParticipantState(.moving, handle: participantHandle)
        var completionWorkItem: DispatchWorkItem?
        completionWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            defer {
                scrollCoordinator.clearMotionTask(
                    kind: .focus,
                    handle: participantHandle
                )
            }
            guard scrollCoordinator.isMotionParticipantCurrent(participantHandle) else { return }
            self.refreshPendingMotionState(descriptor: self.currentDescriptor)
            scrollCoordinator.updateMotionParticipantState(.aligned, handle: participantHandle)
        }
        if let completionWorkItem {
            scrollCoordinator.replaceMotionTask(
                completionWorkItem,
                kind: .focus,
                handle: participantHandle
            )
            DispatchQueue.main.asyncAfter(
                deadline: .now() + dispatch.duration,
                execute: completionWorkItem
            )
        }
    }

    private func applyPredictedMotion(
        kind: PendingMotionKind,
        predictedTarget: MainCanvasSurfacePredictedTarget,
        animated: Bool
    ) -> MotionDispatchResult {
        let visibleRect = scrollView.documentVisibleRect
        let resolvedViewportHeight = max(1, visibleRect.height)
        let desiredTargetY = resolvedTargetOffsetY(
            kind: kind,
            predictedTarget: predictedTarget,
            viewportHeight: resolvedViewportHeight
        )
        let maxY = resolvedMaximumOffsetY()
        let reachable = desiredTargetY <= maxY + 0.5
        let targetLabel = "\(viewportKey)|\(predictedTarget.targetCardID.uuidString)"

        if animated {
            let resolvedTargetY = CaretScrollCoordinator.resolvedVerticalTargetY(
                visibleRect: visibleRect,
                targetY: desiredTargetY,
                minY: 0,
                maxY: maxY,
                snapToPixel: true
            )
            let duration = abs(resolvedTargetY - visibleRect.origin.y) <= 0.5
                ? 0
                : CaretScrollCoordinator.resolvedVerticalAnimationDuration(
                    currentY: visibleRect.origin.y,
                    targetY: resolvedTargetY,
                    viewportHeight: resolvedViewportHeight
                )
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: configuration.diagnosticsOwnerKey,
                axis: "vertical",
                engine: "native",
                animated: true,
                target: targetLabel,
                expectedDuration: duration,
                predictedOnly: true
            )
            _ = CaretScrollCoordinator.applyAnimatedVerticalScrollIfNeeded(
                scrollView: scrollView,
                visibleRect: visibleRect,
                targetY: desiredTargetY,
                minY: 0,
                maxY: maxY,
                deadZone: 0.5,
                snapToPixel: true,
                duration: duration
            )
            return MotionDispatchResult(
                duration: duration,
                requiresCorrection: !reachable,
                reachedTarget: reachable
            )
        }

        MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
            ownerKey: configuration.diagnosticsOwnerKey,
            axis: "vertical",
            engine: "native",
            animated: false,
            target: targetLabel,
            expectedDuration: 0,
            predictedOnly: true
        )
        _ = CaretScrollCoordinator.applyVerticalScrollIfNeeded(
            scrollView: scrollView,
            visibleRect: visibleRect,
            targetY: desiredTargetY,
            minY: 0,
            maxY: maxY,
            deadZone: 0.5,
            snapToPixel: true
        )
        return MotionDispatchResult(
            duration: 0,
            requiresCorrection: !reachable,
            reachedTarget: reachable
        )
    }

    private func refreshPendingMotionState(
        descriptor: MainCanvasSurfaceViewportDescriptor
    ) {
        guard var pendingMotion else { return }
        let latestTarget = resolvedPredictedTarget(
            for: pendingMotion.kind,
            descriptor: descriptor
        )
        guard let latestTarget else {
            pendingMotion.correctionRequired = true
            self.pendingMotion = pendingMotion
            return
        }
        if latestTarget != pendingMotion.latestTarget {
            pendingMotion.correctionRequired = true
            pendingMotion.latestTarget = latestTarget
        }
        let desiredTargetY = resolvedTargetOffsetY(
            kind: pendingMotion.kind,
            predictedTarget: latestTarget,
            viewportHeight: max(1, scrollView.documentVisibleRect.height)
        )
        if desiredTargetY > resolvedMaximumOffsetY() + 0.5 {
            pendingMotion.correctionRequired = true
        }
        self.pendingMotion = pendingMotion
    }

    private func handleMotionSessionCloseIfNeeded() {
        guard configuration.motionSessionCloseTick != lastProcessedMotionSessionCloseTick else {
            return
        }
        lastProcessedMotionSessionCloseTick = configuration.motionSessionCloseTick
        guard let pendingMotion else { return }
        guard let correctionGateSnapshot = configuration.motionCorrectionGateSnapshot,
              correctionGateSnapshot.reason == .sessionClose,
              correctionGateSnapshot.sessionID == pendingMotion.sessionID,
              correctionGateSnapshot.revision == pendingMotion.sessionRevision else {
            self.pendingMotion = nil
            return
        }
        self.pendingMotion = nil
    }

    private func handleMotionCorrectionGateIfNeeded() {
        guard configuration.motionCorrectionGateTick != lastProcessedMotionCorrectionGateTick else {
            return
        }
        lastProcessedMotionCorrectionGateTick = configuration.motionCorrectionGateTick
        guard let correctionGateSnapshot = configuration.motionCorrectionGateSnapshot,
              var pendingMotion,
              correctionGateSnapshot.sessionID == pendingMotion.sessionID,
              correctionGateSnapshot.revision == pendingMotion.sessionRevision else {
            return
        }
        guard pendingMotion.correctionRequired else {
            self.pendingMotion = pendingMotion
            return
        }

        let correctedOffsetY = min(
            resolvedTargetOffsetY(
                kind: pendingMotion.kind,
                predictedTarget: pendingMotion.latestTarget,
                viewportHeight: max(1, scrollView.documentVisibleRect.height)
            ),
            resolvedMaximumOffsetY()
        )
        let currentOffsetY = max(0, scrollView.contentView.bounds.origin.y)
        let tolerance: CGFloat = pendingMotion.kind == .focus ? 16 : 22
        guard abs(currentOffsetY - correctedOffsetY) > tolerance else {
            pendingMotion.correctionRequired = false
            self.pendingMotion = pendingMotion
            return
        }
        guard let scrollCoordinator,
              scrollCoordinator.consumeMotionCorrectionBudget(forSessionID: pendingMotion.sessionID) else {
            self.pendingMotion = pendingMotion
            return
        }

        MainCanvasNavigationDiagnostics.shared.recordSecondCorrection(
            ownerKey: configuration.diagnosticsOwnerKey
        )
        isApplyingDesiredOffset = true
        scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: correctedOffsetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        isApplyingDesiredOffset = false
        publishOffsetIfNeeded(correctedOffsetY)
        pendingMotion.correctionRequired = false
        self.pendingMotion = pendingMotion
    }

    private func resolvedPredictedTarget(
        for kind: PendingMotionKind,
        descriptor: MainCanvasSurfaceViewportDescriptor
    ) -> MainCanvasSurfacePredictedTarget? {
        switch kind {
        case .focus:
            return descriptor.predictedFocusTarget
        case .bottomReveal:
            return descriptor.predictedBottomRevealTarget
        }
    }

    private func resolvedTargetOffsetY(
        kind: PendingMotionKind,
        predictedTarget: MainCanvasSurfacePredictedTarget,
        viewportHeight: CGFloat
    ) -> CGFloat {
        switch kind {
        case .focus:
            return MainCanvasSurfaceFocusAlignment.resolvedTargetOffsetY(
                predictedTarget: predictedTarget,
                viewportHeight: viewportHeight
            )
        case .bottomReveal:
            return max(0, predictedTarget.targetMaxY - viewportHeight)
        }
    }

    private func markPendingMotionCorrectionRequired() {
        guard var pendingMotion else { return }
        pendingMotion.correctionRequired = true
        self.pendingMotion = pendingMotion
    }

    private func sizeChanged(from lhs: CGSize, to rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) > 0.5 || abs(lhs.height - rhs.height) > 0.5
    }
}
