import AppKit
import SwiftUI

struct MainCanvasSurfaceViewportDescriptor: Identifiable {
    let level: Int
    let viewportKey: String
    let frame: CGRect
    let desiredOffsetY: CGFloat
    let content: AnyView

    var id: String { viewportKey }
}

struct MainCanvasSurfaceConfiguration {
    let contentSize: CGSize
    let activeLevel: Int?
    let descriptors: [MainCanvasSurfaceViewportDescriptor]
    let onLiveOffsetChange: (String, CGFloat) -> Void
    let onViewportFinalize: (String, CGFloat) -> Void
    let onDocumentSizeChange: (String, CGSize) -> Void
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
        let visibleRect = horizontalVisibleRect()
        let visibleViewportKeys = configuration.descriptors.reduce(into: Set<String>()) { partialResult, descriptor in
            if descriptor.frame.intersects(visibleRect) {
                partialResult.insert(descriptor.viewportKey)
            }
        }

        let activeViewportKeys = configuration.descriptors.reduce(into: Set<String>()) { partialResult, descriptor in
            guard let activeLevel = configuration.activeLevel else { return }
            if abs(descriptor.level - activeLevel) <= 1 {
                partialResult.insert(descriptor.viewportKey)
            }
        }

        let pooledViewportKeys = visibleViewportKeys.union(activeViewportKeys)
        if !pooledViewportKeys.isEmpty {
            return pooledViewportKeys
        }
        return Set(configuration.descriptors.prefix(3).map(\.viewportKey))
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

    private let scrollView = NSScrollView(frame: .zero)
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private let viewportKey: String
    private var desiredOffsetY: CGFloat
    private var configuration: MainCanvasSurfaceConfiguration
    private weak var scrollCoordinator: MainCanvasScrollCoordinator?
    private weak var registeredScrollCoordinator: MainCanvasScrollCoordinator?
    private var scrollObserver: NSObjectProtocol?
    private var deferredRestoreAttemptsRemaining = 0
    private var deferredRestoreWorkItem: DispatchWorkItem?
    private var lastReportedOffsetY: CGFloat = .nan
    private var lastReportedDocumentSize: CGSize = .zero
    private var isApplyingDesiredOffset = false
    private var isRestoringInitialViewport = true

    init(
        descriptor: MainCanvasSurfaceViewportDescriptor,
        configuration: MainCanvasSurfaceConfiguration,
        scrollCoordinator: MainCanvasScrollCoordinator?
    ) {
        self.viewportKey = descriptor.viewportKey
        self.desiredOffsetY = max(0, descriptor.desiredOffsetY)
        self.configuration = configuration
        self.scrollCoordinator = scrollCoordinator
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

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        refreshDocumentLayout()
        applyDesiredOffsetIfNeeded()
        scheduleDeferredRestoreIfNeeded()
        updateInitialViewportPresentation()
    }

    func update(
        descriptor: MainCanvasSurfaceViewportDescriptor,
        configuration: MainCanvasSurfaceConfiguration,
        scrollCoordinator: MainCanvasScrollCoordinator?
    ) {
        self.configuration = configuration
        self.scrollCoordinator = scrollCoordinator
        desiredOffsetY = max(0, descriptor.desiredOffsetY)
        frame = descriptor.frame
        hostingView.rootView = descriptor.content
        registerScrollViewIfNeeded()
        refreshDocumentLayout()
        applyDesiredOffsetIfNeeded()
        scheduleDeferredRestoreIfNeeded()
        updateInitialViewportPresentation()
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
        let width = max(1, bounds.width)
        let viewportHeight = max(1, bounds.height)

        if abs(hostingView.frame.width - width) > 0.5 {
            hostingView.frame.size.width = width
        }

        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let documentHeight = max(viewportHeight, fittingSize.height)
        let nextDocumentSize = CGSize(width: width, height: documentHeight)

        if hostingView.frame.size != nextDocumentSize {
            hostingView.frame = CGRect(origin: .zero, size: nextDocumentSize)
        }

        if sizeChanged(from: lastReportedDocumentSize, to: nextDocumentSize) {
            lastReportedDocumentSize = nextDocumentSize
            configuration.onDocumentSizeChange(viewportKey, nextDocumentSize)
        }

        clampCurrentOffsetToDocumentBounds()
    }

    private func clampCurrentOffsetToDocumentBounds() {
        let currentOffsetY = max(0, scrollView.contentView.bounds.origin.y)
        let maxOffsetY = resolvedMaximumOffsetY()
        let clampedOffsetY = min(currentOffsetY, maxOffsetY)
        guard abs(currentOffsetY - clampedOffsetY) > 0.5 else { return }
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

    private func resolvedMaximumOffsetY() -> CGFloat {
        let documentHeight = hostingView.frame.height
        let viewportHeight = max(1, scrollView.contentView.bounds.height)
        return max(0, documentHeight - viewportHeight)
    }

    private func sizeChanged(from lhs: CGSize, to rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) > 0.5 || abs(lhs.height - rhs.height) > 0.5
    }
}
