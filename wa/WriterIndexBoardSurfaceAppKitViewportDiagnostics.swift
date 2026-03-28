import SwiftUI
import AppKit

final class IndexBoardSurfaceAppKitContainerView: NSView {
    private let backgroundView: IndexBoardSurfaceAppKitBackgroundView
    private let scrollView: NSScrollView
    private let documentView: IndexBoardSurfaceAppKitDocumentView
    private var lastContainerRenderState: IndexBoardSurfaceAppKitRenderState
    private var scrollObserver: NSObjectProtocol?
    private var willStartLiveScrollObserver: NSObjectProtocol?
    private var didEndLiveScrollObserver: NSObjectProtocol?
    private var willStartMagnifyObserver: NSObjectProtocol?
    private var magnifyObserver: NSObjectProtocol?
    private var isApplyingExternalViewport = false
    private var isLiveScrolling = false
    private var isLiveMagnifying = false
    private var viewportSession: IndexBoardSurfaceAppKitViewportSession?
    private var viewportCommitTimer: Timer?
    private var pendingLiveMagnification: CGFloat?
    private var pendingLiveScrollOrigin: CGPoint?
    private var hoverResumeTimer: Timer?
    private var pendingViewportReapplyAttempts = 0
    private var isRestoringInitialViewport = true
    private var hasPresentedInitialViewport = false
    private var hasPendingDeferredCommitLayoutFlush = false
    private let viewportDebugID = String(UUID().uuidString.prefix(8))
    private var viewportDebugLogBudget = 24

    init(configuration: IndexBoardSurfaceAppKitConfiguration) {
        backgroundView = IndexBoardSurfaceAppKitBackgroundView(theme: configuration.theme)
        scrollView = NSScrollView(frame: .zero)
        documentView = IndexBoardSurfaceAppKitDocumentView(configuration: configuration)
        lastContainerRenderState = configuration.renderState
        super.init(frame: .zero)
        wantsLayer = true

        backgroundView.frame = bounds
        backgroundView.autoresizingMask = [.width, .height]
        addSubview(backgroundView)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.usesPredominantAxisScrolling = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero
        scrollView.scrollerInsets = NSEdgeInsetsZero
        scrollView.allowsMagnification = true
        scrollView.minMagnification = IndexBoardZoom.minScale
        scrollView.maxMagnification = IndexBoardZoom.maxScale
        scrollView.documentView = documentView
        scrollView.contentView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.contentInsets = NSEdgeInsetsZero
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.alphaValue = 0
        documentView.scrollView = scrollView
        addSubview(scrollView)
        suppressScrollPocketVisuals()

        update(configuration: configuration)
        installViewportObservers()
        logViewportDebug("init_complete")
    }

    private func installViewportObservers() {
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.handleViewportChanged()
        }
        willStartLiveScrollObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.isLiveScrolling = true
            self?.isRestoringInitialViewport = false
            self?.updateInitialViewportPresentation()
        }
        didEndLiveScrollObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isLiveScrolling = false
            self.viewportSession = nil
            let origin = self.scrollView.contentView.bounds.origin
            self.pendingLiveScrollOrigin = CGPoint(
                x: max(0, origin.x),
                y: max(0, origin.y)
            )
        }
        willStartMagnifyObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveMagnifyNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.isLiveMagnifying = true
            self?.isRestoringInitialViewport = false
            self?.updateInitialViewportPresentation()
        }
        magnifyObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.isLiveMagnifying = false
            self?.syncViewportAfterLiveMagnify()
            self?.documentView.refreshDisplayAfterLiveMagnify()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
        }
        if let willStartLiveScrollObserver {
            NotificationCenter.default.removeObserver(willStartLiveScrollObserver)
        }
        if let didEndLiveScrollObserver {
            NotificationCenter.default.removeObserver(didEndLiveScrollObserver)
        }
        if let willStartMagnifyObserver {
            NotificationCenter.default.removeObserver(willStartMagnifyObserver)
        }
        if let magnifyObserver {
            NotificationCenter.default.removeObserver(magnifyObserver)
        }
        flushViewportPersistenceForTeardown()
    }

    override func layout() {
        super.layout()
        backgroundView.frame = bounds
        scrollView.frame = bounds
        normalizeScrollViewInsets()
        suppressScrollPocketVisuals()
        applyConfiguredViewportIfNeeded()
        scheduleDeferredViewportReapplyIfNeeded()
        updateInitialViewportPresentation()
        logViewportDebug("layout")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        normalizeScrollViewInsets()
        suppressScrollPocketVisuals()
        DispatchQueue.main.async { [weak self] in
            self?.applyConfiguredViewportIfNeeded()
            self?.scheduleDeferredViewportReapplyIfNeeded()
            self?.updateInitialViewportPresentation()
            self?.logViewportDebug("view_did_move_to_window_async")
        }
    }

    func update(configuration: IndexBoardSurfaceAppKitConfiguration) {
        let nextRenderState = configuration.renderState
        let requiresFullRenderUpdate =
            !nextRenderState.equalsIgnoringViewport(lastContainerRenderState)
        let shouldDeferCommittedLayout =
            requiresFullRenderUpdate && documentView.consumeDeferredCommitLayoutRequest()
        backgroundView.theme = configuration.theme
        if requiresFullRenderUpdate {
            documentView.updateConfiguration(configuration)
            if shouldDeferCommittedLayout {
                scheduleDeferredCommitLayoutFlush()
            } else {
                documentView.layoutSubtreeIfNeeded()
                documentView.finishMotionSceneCommitBridgeIfNeeded()
            }
        } else {
            documentView.updateConfigurationForViewportOnly(configuration)
        }
        lastContainerRenderState = nextRenderState

        if let pendingLiveMagnification {
            if abs(configuration.zoomScale - pendingLiveMagnification) <= 0.001 {
                self.pendingLiveMagnification = nil
            }
        }
        if let pendingLiveScrollOrigin {
            if abs(configuration.scrollOffset.x - pendingLiveScrollOrigin.x) <= 0.5 &&
                abs(configuration.scrollOffset.y - pendingLiveScrollOrigin.y) <= 0.5 {
                self.pendingLiveScrollOrigin = nil
            }
        }

        applyConfiguredViewportIfNeeded()
        scheduleDeferredViewportReapplyIfNeeded()
        updateInitialViewportPresentation()
        logViewportDebug("update")

        if !shouldDeferCommittedLayout {
            applyPendingDropPreservedOriginIfNeeded()
        }

        suppressScrollPocketVisuals()

    }

    private func scheduleDeferredCommitLayoutFlush() {
        guard !hasPendingDeferredCommitLayoutFlush else { return }
        hasPendingDeferredCommitLayoutFlush = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hasPendingDeferredCommitLayoutFlush = false
            self.documentView.layoutSubtreeIfNeeded()
            self.documentView.finishMotionSceneCommitBridgeIfNeeded()
            self.applyConfiguredViewportIfNeeded()
            self.scheduleDeferredViewportReapplyIfNeeded()
            self.updateInitialViewportPresentation()
            self.applyPendingDropPreservedOriginIfNeeded()
            self.suppressScrollPocketVisuals()
        }
    }

    private func applyPendingDropPreservedOriginIfNeeded() {
        guard let preservedOrigin = documentView.pendingDropPreservedScrollOrigin else { return }
        let configuration = documentView.configuration
        let visibleRect = scrollView.documentVisibleRect
        let maxX = max(0, documentView.frame.width - visibleRect.width)
        let maxY = max(0, documentView.frame.height - visibleRect.height)
        let clampedOrigin = CGPoint(
            x: min(max(0, preservedOrigin.x), maxX),
            y: min(max(0, preservedOrigin.y), maxY)
        )
        let currentOrigin = scrollView.contentView.bounds.origin
        if abs(currentOrigin.x - clampedOrigin.x) > 0.5 ||
            abs(currentOrigin.y - clampedOrigin.y) > 0.5 {
            isApplyingExternalViewport = true
            scrollView.contentView.setBoundsOrigin(NSPoint(x: clampedOrigin.x, y: clampedOrigin.y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            isApplyingExternalViewport = false
        }
        if abs(clampedOrigin.x - configuration.scrollOffset.x) > 0.5 ||
            abs(clampedOrigin.y - configuration.scrollOffset.y) > 0.5 {
            documentView.configuration.onScrollOffsetChange(clampedOrigin)
        }
        documentView.pendingDropPreservedScrollOrigin = nil
        documentView.suppressViewportChangeNotifications = false
    }

    private func applyConfiguredViewportIfNeeded() {
        if viewportNeedsExternalApply() {
            logViewportDebug("apply_begin")
        }
        let configuration = documentView.configuration

        if !isLiveMagnifying,
           pendingLiveMagnification == nil,
           abs(scrollView.magnification - configuration.zoomScale) > 0.001 {
            isApplyingExternalViewport = true
            scrollView.setMagnification(
                configuration.zoomScale,
                centeredAt: resolvedMagnificationCenter()
            )
            isApplyingExternalViewport = false
        }

        let currentOrigin = scrollView.contentView.bounds.origin
        if !isLiveMagnifying &&
            viewportSession == nil &&
            pendingLiveScrollOrigin == nil &&
            documentView.pendingDropPreservedScrollOrigin == nil &&
            (abs(currentOrigin.x - configuration.scrollOffset.x) > 0.5 ||
             abs(currentOrigin.y - configuration.scrollOffset.y) > 0.5) {
            isApplyingExternalViewport = true
            scrollView.contentView.setBoundsOrigin(
                NSPoint(
                    x: max(0, configuration.scrollOffset.x),
                    y: max(0, configuration.scrollOffset.y)
                )
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
            isApplyingExternalViewport = false
        }
        if viewportNeedsExternalApply() {
            logViewportDebug("apply_end_needs_more")
        } else {
            logViewportDebug("apply_end_resolved")
        }
    }

    private func viewportNeedsExternalApply() -> Bool {
        guard !isLiveMagnifying,
              viewportSession == nil,
              pendingLiveScrollOrigin == nil,
              documentView.pendingDropPreservedScrollOrigin == nil else {
            return false
        }

        let configuration = documentView.configuration
        let currentOrigin = scrollView.contentView.bounds.origin
        let needsScaleApply = abs(scrollView.magnification - configuration.zoomScale) > 0.001
        let needsOriginApply =
            abs(currentOrigin.x - configuration.scrollOffset.x) > 0.5 ||
            abs(currentOrigin.y - configuration.scrollOffset.y) > 0.5
        return needsScaleApply || needsOriginApply
    }

    private func scheduleDeferredViewportReapplyIfNeeded(maxAttempts: Int = 4) {
        guard viewportNeedsExternalApply() else {
            pendingViewportReapplyAttempts = 0
            return
        }
        guard pendingViewportReapplyAttempts == 0 else { return }
        pendingViewportReapplyAttempts = maxAttempts
        performDeferredViewportReapply()
    }

    private func performDeferredViewportReapply() {
        guard pendingViewportReapplyAttempts > 0 else { return }
        pendingViewportReapplyAttempts -= 1
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyConfiguredViewportIfNeeded()
            self.logViewportDebug("deferred_apply_tick")
            if self.isRestoringInitialViewport, self.initialViewportRestoreCompleted() {
                self.isRestoringInitialViewport = false
            }
            self.updateInitialViewportPresentation()
            if self.viewportNeedsExternalApply(), self.pendingViewportReapplyAttempts > 0 {
                self.performDeferredViewportReapply()
            } else {
                self.pendingViewportReapplyAttempts = 0
            }
        }
    }

    private func updateInitialViewportPresentation() {
        if isRestoringInitialViewport, initialViewportRestoreCompleted() {
            isRestoringInitialViewport = false
        }

        let shouldPresent = !isRestoringInitialViewport
        guard shouldPresent != hasPresentedInitialViewport else { return }
        hasPresentedInitialViewport = shouldPresent
        scrollView.alphaValue = shouldPresent ? 1 : 0
    }

    private func initialViewportRestoreCompleted() -> Bool {
        let configuration = documentView.configuration
        let visibleRect = scrollView.documentVisibleRect
        guard visibleRect.width > 1, visibleRect.height > 1 else { return false }
        guard documentView.frame.width > 1, documentView.frame.height > 1 else { return false }

        let currentOrigin = scrollView.contentView.bounds.origin
        let matchesScale = abs(scrollView.magnification - configuration.zoomScale) <= 0.001
        let matchesOrigin =
            abs(currentOrigin.x - configuration.scrollOffset.x) <= 0.5 &&
            abs(currentOrigin.y - configuration.scrollOffset.y) <= 0.5
        return matchesScale && matchesOrigin
    }

    private func logViewportDebug(_ event: String) {
        guard viewportDebugLogBudget > 0 else { return }
        viewportDebugLogBudget -= 1
        let configuration = documentView.configuration
        let currentOrigin = scrollView.contentView.bounds.origin
        let visibleRect = scrollView.documentVisibleRect
        indexBoardRestoreTrace(
            "board_surface_\(event)",
            "id=\(self.viewportDebugID) desiredScroll=(\(String(format: "%.2f", configuration.scrollOffset.x)),\(String(format: "%.2f", configuration.scrollOffset.y))) " +
            "currentScroll=(\(String(format: "%.2f", currentOrigin.x)),\(String(format: "%.2f", currentOrigin.y))) " +
            "desiredZoom=\(String(format: "%.2f", configuration.zoomScale)) currentZoom=\(String(format: "%.2f", self.scrollView.magnification)) " +
            "docSize=(\(String(format: "%.2f", self.documentView.frame.width)),\(String(format: "%.2f", self.documentView.frame.height))) " +
            "visibleRect=(\(String(format: "%.2f", visibleRect.width)),\(String(format: "%.2f", visibleRect.height))) " +
            "containerBounds=(\(String(format: "%.2f", self.bounds.width)),\(String(format: "%.2f", self.bounds.height))) " +
            "reapplyAttempts=\(self.pendingViewportReapplyAttempts)"
        )
    }

    private func handleViewportChanged() {
        guard !isApplyingExternalViewport,
              !documentView.suppressViewportChangeNotifications else { return }
        if documentView.isInteractingLocally {
            return
        }
        if isRestoringInitialViewport {
            if initialViewportRestoreCompleted() {
                isRestoringInitialViewport = false
            } else {
                scheduleDeferredViewportReapplyIfNeeded()
                logViewportDebug("skip_initial_viewport_change")
                return
            }
        }
        if isLiveMagnifying {
            documentView.refreshHoverIndicatorFromCurrentMouse()
            return
        }
        let origin = scrollView.contentView.bounds.origin
        let resolvedOrigin = CGPoint(x: max(0, origin.x), y: max(0, origin.y))
        let referenceOrigin = viewportSession?.liveScrollOrigin ?? documentView.configuration.scrollOffset
        guard abs(resolvedOrigin.x - referenceOrigin.x) > 0.5 ||
                abs(resolvedOrigin.y - referenceOrigin.y) > 0.5 else {
            documentView.refreshHoverIndicatorFromCurrentMouse()
            return
        }
        updateViewportSessionFromScrollView()
        pendingLiveScrollOrigin = resolvedOrigin
        documentView.configuration.onScrollOffsetChange(resolvedOrigin)
        suspendHoverIndicatorForScroll()
    }

    private func handleMagnificationChanged() {
        guard !isApplyingExternalViewport else { return }
        guard abs(scrollView.magnification - documentView.configuration.zoomScale) > 0.001 else { return }
        documentView.configuration.onZoomScaleChange(scrollView.magnification)
    }

    private func syncViewportAfterLiveMagnify() {
        guard !isApplyingExternalViewport else { return }
        pendingLiveMagnification = scrollView.magnification
        handleMagnificationChanged()
        let origin = scrollView.contentView.bounds.origin
        let resolvedOrigin = CGPoint(x: max(0, origin.x), y: max(0, origin.y))
        pendingLiveScrollOrigin = resolvedOrigin
        if abs(resolvedOrigin.x - documentView.configuration.scrollOffset.x) > 0.5 ||
            abs(resolvedOrigin.y - documentView.configuration.scrollOffset.y) > 0.5 {
            documentView.configuration.onScrollOffsetChange(resolvedOrigin)
        }
        documentView.refreshHoverIndicatorFromCurrentMouse()
    }

    private func suspendHoverIndicatorForScroll() {
        documentView.setHoverIndicatorSuppressed(true)
        resumeHoverIndicatorAfterScrollDelay()
    }

    private func scheduleViewportCommit() {
        viewportCommitTimer?.invalidate()
        viewportCommitTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
            self?.commitViewportSessionIfNeeded()
        }
    }

    private func commitViewportSessionIfNeeded() {
        viewportCommitTimer?.invalidate()
        viewportCommitTimer = nil
        guard let viewportSession else { return }
        let resolvedOrigin = CGPoint(
            x: max(0, viewportSession.liveScrollOrigin.x),
            y: max(0, viewportSession.liveScrollOrigin.y)
        )
        self.viewportSession = nil
        pendingLiveScrollOrigin = resolvedOrigin
        if abs(resolvedOrigin.x - documentView.configuration.scrollOffset.x) > 0.5 ||
            abs(resolvedOrigin.y - documentView.configuration.scrollOffset.y) > 0.5 {
            documentView.configuration.onScrollOffsetChange(resolvedOrigin)
        }
    }

    private func resumeHoverIndicatorAfterScrollDelay() {
        hoverResumeTimer?.invalidate()
        hoverResumeTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.documentView.setHoverIndicatorSuppressed(false)
            self.documentView.refreshHoverIndicatorFromCurrentMouse()
        }
    }

    private func updateViewportSessionFromScrollView() {
        let origin = scrollView.contentView.bounds.origin
        let resolvedOrigin = CGPoint(x: max(0, origin.x), y: max(0, origin.y))
        if var viewportSession {
            viewportSession.liveMagnification = scrollView.magnification
            viewportSession.liveScrollOrigin = resolvedOrigin
            self.viewportSession = viewportSession
        } else {
            viewportSession = IndexBoardSurfaceAppKitViewportSession(
                baselineMagnification: scrollView.magnification,
                baselineScrollOrigin: resolvedOrigin,
                liveMagnification: scrollView.magnification,
                liveScrollOrigin: resolvedOrigin
            )
        }
    }

    func flushViewportPersistenceForTeardown() {
        viewportCommitTimer?.invalidate()
        viewportCommitTimer = nil
        hoverResumeTimer?.invalidate()
        hoverResumeTimer = nil

        let resolvedScale = min(max(scrollView.magnification, IndexBoardZoom.minScale), IndexBoardZoom.maxScale)
        let origin = scrollView.contentView.bounds.origin
        let resolvedOrigin = CGPoint(
            x: max(0, origin.x),
            y: max(0, origin.y)
        )
        documentView.configuration.onViewportFinalize(resolvedScale, resolvedOrigin)
    }

    private func normalizeScrollViewInsets() {
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero
        scrollView.scrollerInsets = NSEdgeInsetsZero
        scrollView.contentView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.contentInsets = NSEdgeInsetsZero
    }

    private func suppressScrollPocketVisuals() {
        hideScrollPocketSubviews(in: scrollView)
    }

    private func hideScrollPocketSubviews(in view: NSView) {
        for subview in view.subviews {
            let className = NSStringFromClass(type(of: subview))
            if shouldHideScrollPocketSubview(className: className) {
                subview.isHidden = true
                subview.alphaValue = 0
            } else {
                hideScrollPocketSubviews(in: subview)
            }
        }
    }

    private func shouldHideScrollPocketSubview(className: String) -> Bool {
        className.contains("NSScrollPocket")
    }

    private func resolvedMagnificationCenter() -> CGPoint {
        let visibleRect = scrollView.documentVisibleRect
        return CGPoint(x: visibleRect.midX, y: visibleRect.midY)
    }
}

struct IndexBoardSurfaceAppKitCanvas: NSViewRepresentable {
    let configuration: IndexBoardSurfaceAppKitConfiguration

    func makeNSView(context: Context) -> IndexBoardSurfaceAppKitContainerView {
        IndexBoardSurfaceAppKitContainerView(configuration: configuration)
    }

    func updateNSView(_ nsView: IndexBoardSurfaceAppKitContainerView, context: Context) {
        nsView.update(configuration: configuration)
    }

    static func dismantleNSView(_ nsView: IndexBoardSurfaceAppKitContainerView, coordinator: ()) {
        nsView.flushViewportPersistenceForTeardown()
    }
}

