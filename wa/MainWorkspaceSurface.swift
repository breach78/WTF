import AppKit
import SwiftUI

struct MainWorkspaceSurface: NSViewRepresentable {
    @ObservedObject var controller: MainWorkspaceSurfaceController

    let scrollCoordinator: MainCanvasScrollCoordinator
    let snapshot: MainWorkspaceSnapshot
    let renderState: MainWorkspaceSurfaceRenderState
    let plan: MainWorkspaceScrollPlan?
    let callbacks: MainWorkspaceSurfaceCallbacks
    let content: AnyView

    func makeNSView(context: Context) -> MainWorkspaceSurfaceView {
        let view = MainWorkspaceSurfaceView(scrollCoordinator: scrollCoordinator)
        controller.attach(surfaceView: view)
        return view
    }

    func updateNSView(_ nsView: MainWorkspaceSurfaceView, context: Context) {
        controller.attach(surfaceView: nsView)
        controller.apply(
            snapshot: snapshot,
            renderState: renderState,
            plan: plan,
            callbacks: callbacks,
            content: content
        )
    }

    static func dismantleNSView(_ nsView: MainWorkspaceSurfaceView, coordinator: ()) {
        nsView.teardown()
    }
}

final class MainWorkspaceSurfaceView: NSView {
    private let scrollCoordinator: MainCanvasScrollCoordinator
    private let horizontalScrollView = NSScrollView()
    private let horizontalDocumentView = MainWorkspaceBackgroundView()
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))

    private var horizontalBoundsObserver: NSObjectProtocol?
    private var isPostApplyRefreshScheduled = false

    init(scrollCoordinator: MainCanvasScrollCoordinator) {
        self.scrollCoordinator = scrollCoordinator
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setupHorizontalSurface()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        teardown()
    }

    func teardown() {
        if let horizontalBoundsObserver {
            NotificationCenter.default.removeObserver(horizontalBoundsObserver)
            self.horizontalBoundsObserver = nil
        }
        scrollCoordinator.unregisterMainCanvasHorizontalScrollView(matching: horizontalScrollView)
    }

    func apply(
        snapshot: MainWorkspaceSnapshot,
        callbacks: MainWorkspaceSurfaceCallbacks,
        content: AnyView
    ) {
        scrollCoordinator.registerMainCanvasHorizontalScrollView(horizontalScrollView)
        layer?.backgroundColor = snapshot.backgroundColor.cgColor
        horizontalDocumentView.onBackgroundClick = callbacks.onBackgroundTap
        hostingView.rootView = content
        updateDocumentLayout()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        updateDocumentLayout()
    }

    func schedulePostApplyRefresh() {
        guard !isPostApplyRefreshScheduled else { return }
        isPostApplyRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isPostApplyRefreshScheduled = false
            self.scrollCoordinator.refreshMainCanvasHorizontalScrollViewState(self.horizontalScrollView)
        }
    }

    func reconnectScrollCoordinator() {
        scrollCoordinator.registerMainCanvasHorizontalScrollView(horizontalScrollView)
        updateDocumentLayout()
        scrollCoordinator.refreshMainCanvasHorizontalScrollViewState(horizontalScrollView)
    }

    func rectForCard(viewportKey: String, cardID: UUID) -> CGRect? {
        _ = viewportKey
        _ = cardID
        return nil
    }

    func viewportRect(for viewportKey: String) -> CGRect? {
        _ = viewportKey
        return nil
    }

    private func setupHorizontalSurface() {
        horizontalScrollView.translatesAutoresizingMaskIntoConstraints = false
        horizontalScrollView.borderType = .noBorder
        horizontalScrollView.drawsBackground = false
        horizontalScrollView.hasHorizontalScroller = false
        horizontalScrollView.hasVerticalScroller = false
        horizontalScrollView.autohidesScrollers = true
        horizontalScrollView.contentView.postsBoundsChangedNotifications = true

        horizontalDocumentView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.translatesAutoresizingMaskIntoConstraints = true

        horizontalDocumentView.addSubview(hostingView)
        horizontalScrollView.documentView = horizontalDocumentView
        addSubview(horizontalScrollView)

        NSLayoutConstraint.activate([
            horizontalScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            horizontalScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            horizontalScrollView.topAnchor.constraint(equalTo: topAnchor),
            horizontalScrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        horizontalBoundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: horizontalScrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.scrollCoordinator.refreshMainCanvasHorizontalScrollViewState(self.horizontalScrollView)
            }
        }
        scrollCoordinator.registerMainCanvasHorizontalScrollView(horizontalScrollView)
    }

    private func updateDocumentLayout() {
        let viewportWidth = max(1, horizontalScrollView.contentView.bounds.width)
        let viewportHeight = max(1, horizontalScrollView.contentView.bounds.height)
        guard viewportWidth > 1, viewportHeight > 1 else { return }

        let fittingSize = hostingView.fittingSize
        let documentSize = CGSize(
            width: max(viewportWidth, ceil(fittingSize.width)),
            height: viewportHeight
        )

        let documentFrame = CGRect(origin: .zero, size: documentSize)
        if horizontalDocumentView.frame != documentFrame {
            horizontalDocumentView.frame = documentFrame
        }
        if hostingView.frame != documentFrame {
            hostingView.frame = documentFrame
        }
    }
}

private final class MainWorkspaceBackgroundView: NSView {
    var onBackgroundClick: (() -> Void)?

    override var isFlipped: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onBackgroundClick?()
        super.mouseDown(with: event)
    }
}
