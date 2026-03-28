import SwiftUI
import AppKit

struct MainCanvasHorizontalScrollViewAccessor: NSViewRepresentable {
    let scrollCoordinator: MainCanvasScrollCoordinator

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.attach(to: view, scrollCoordinator: scrollCoordinator)
    }

    final class Coordinator {
        private var scrollCoordinator: MainCanvasScrollCoordinator?
        private weak var scrollView: NSScrollView?
        private weak var observedDocumentView: NSView?
        private var contentBoundsObserver: NSObjectProtocol?
        private var documentFrameObserver: NSObjectProtocol?
        private var documentBoundsObserver: NSObjectProtocol?
        private var attachRetryWorkItem: DispatchWorkItem?

        deinit {
            detach()
        }

        func attach(to view: NSView, scrollCoordinator: MainCanvasScrollCoordinator) {
            self.scrollCoordinator = scrollCoordinator
            guard let resolvedScrollView = resolveScrollView(from: view) else {
                scheduleAttachRetry(to: view, scrollCoordinator: scrollCoordinator)
                return
            }

            attachRetryWorkItem?.cancel()
            attachRetryWorkItem = nil
            let documentViewChanged = observedDocumentView !== resolvedScrollView.documentView
            guard scrollView !== resolvedScrollView || documentViewChanged else { return }
            detach()
            scrollView = resolvedScrollView
            installObservers(for: resolvedScrollView)
            scrollCoordinator.registerMainCanvasHorizontalScrollView(resolvedScrollView)
        }

        private func detach() {
            attachRetryWorkItem?.cancel()
            attachRetryWorkItem = nil
            if let contentBoundsObserver {
                NotificationCenter.default.removeObserver(contentBoundsObserver)
            }
            if let documentFrameObserver {
                NotificationCenter.default.removeObserver(documentFrameObserver)
            }
            if let documentBoundsObserver {
                NotificationCenter.default.removeObserver(documentBoundsObserver)
            }
            contentBoundsObserver = nil
            documentFrameObserver = nil
            documentBoundsObserver = nil
            observedDocumentView = nil
            if let scrollView {
                scrollCoordinator?.unregisterMainCanvasHorizontalScrollView(matching: scrollView)
            }
            scrollView = nil
            scrollCoordinator = nil
        }

        private func scheduleAttachRetry(to view: NSView, scrollCoordinator: MainCanvasScrollCoordinator) {
            guard attachRetryWorkItem == nil else { return }
            let workItem = DispatchWorkItem { [weak self, weak view] in
                guard let self else { return }
                self.attachRetryWorkItem = nil
                guard let view else { return }
                self.attach(to: view, scrollCoordinator: scrollCoordinator)
            }
            attachRetryWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
        }

        private func installObservers(for scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            contentBoundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                Task { @MainActor [weak self, weak scrollView] in
                    guard let self, let scrollView else { return }
                    self.scrollCoordinator?.refreshMainCanvasHorizontalScrollViewState(scrollView)
                }
            }

            if let documentView = scrollView.documentView {
                observedDocumentView = documentView
                documentView.postsFrameChangedNotifications = true
                documentView.postsBoundsChangedNotifications = true
                documentFrameObserver = NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: documentView,
                    queue: .main
                ) { [weak self, weak scrollView] _ in
                    Task { @MainActor [weak self, weak scrollView] in
                        guard let self, let scrollView else { return }
                        self.scrollCoordinator?.refreshMainCanvasHorizontalScrollViewState(scrollView)
                    }
                }
                documentBoundsObserver = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: documentView,
                    queue: .main
                ) { [weak self, weak scrollView] _ in
                    Task { @MainActor [weak self, weak scrollView] in
                        guard let self, let scrollView else { return }
                        self.scrollCoordinator?.refreshMainCanvasHorizontalScrollViewState(scrollView)
                    }
                }
            }
        }

        private func resolveScrollView(from view: NSView) -> NSScrollView? {
            var current: NSView? = view
            while let candidate = current {
                if let scrollView = candidate.enclosingScrollView {
                    return scrollView
                }
                current = candidate.superview
            }
            return nil
        }
    }
}

struct MainColumnScrollViewAccessor: NSViewRepresentable {
    let scrollCoordinator: MainCanvasScrollCoordinator
    let columnKey: String
    let storedOffsetY: CGFloat?
    let onOffsetChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.attach(
            to: view,
            scrollCoordinator: scrollCoordinator,
            columnKey: columnKey,
            storedOffsetY: storedOffsetY,
            onOffsetChange: onOffsetChange
        )
    }

    final class Coordinator {
        private var scrollCoordinator: MainCanvasScrollCoordinator?
        private weak var scrollView: NSScrollView?
        private var observer: NSObjectProtocol?
        private var attachedColumnKey: String?
        private var lastReportedOffsetY: CGFloat = .nan
        private var offsetChangeHandler: ((CGFloat) -> Void)?
        private var attachRetryWorkItem: DispatchWorkItem?

        deinit {
            detach()
        }

        func attach(
            to view: NSView,
            scrollCoordinator: MainCanvasScrollCoordinator,
            columnKey: String,
            storedOffsetY: CGFloat?,
            onOffsetChange: @escaping (CGFloat) -> Void
        ) {
            self.scrollCoordinator = scrollCoordinator
            guard let resolvedScrollView = resolveScrollView(from: view) else {
                scheduleAttachRetry(
                    to: view,
                    scrollCoordinator: scrollCoordinator,
                    columnKey: columnKey,
                    storedOffsetY: storedOffsetY,
                    onOffsetChange: onOffsetChange
                )
                return
            }

            attachRetryWorkItem?.cancel()
            attachRetryWorkItem = nil
            if scrollView !== resolvedScrollView {
                detach()
                scrollView = resolvedScrollView
                installObserver(for: resolvedScrollView)
            }

            let keyChanged = attachedColumnKey != columnKey
            if keyChanged, let previousKey = attachedColumnKey {
                scrollCoordinator.unregister(viewportKey: previousKey, matching: resolvedScrollView)
            }
            attachedColumnKey = columnKey
            scrollCoordinator.register(scrollView: resolvedScrollView, for: columnKey)
            offsetChangeHandler = onOffsetChange
            if keyChanged {
                lastReportedOffsetY = .nan
            }
            publishCurrentOffset()

            if keyChanged, let storedOffsetY, storedOffsetY > 1 {
                applyStoredOffsetIfNeeded(storedOffsetY)
            }
        }

        private func detach() {
            attachRetryWorkItem?.cancel()
            attachRetryWorkItem = nil
            if let attachedColumnKey, let scrollView {
                scrollCoordinator?.unregister(viewportKey: attachedColumnKey, matching: scrollView)
            }
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            observer = nil
            scrollView = nil
            attachedColumnKey = nil
            lastReportedOffsetY = .nan
            offsetChangeHandler = nil
            scrollCoordinator = nil
        }

        private func scheduleAttachRetry(
            to view: NSView,
            scrollCoordinator: MainCanvasScrollCoordinator,
            columnKey: String,
            storedOffsetY: CGFloat?,
            onOffsetChange: @escaping (CGFloat) -> Void
        ) {
            guard attachRetryWorkItem == nil else { return }
            let workItem = DispatchWorkItem { [weak self, weak view] in
                guard let self else { return }
                self.attachRetryWorkItem = nil
                guard let view else { return }
                self.attach(
                    to: view,
                    scrollCoordinator: scrollCoordinator,
                    columnKey: columnKey,
                    storedOffsetY: storedOffsetY,
                    onOffsetChange: onOffsetChange
                )
            }
            attachRetryWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
        }

        private func installObserver(for scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.publishCurrentOffset()
            }
        }

        private func publishCurrentOffset() {
            guard let scrollView, let offsetChangeHandler else { return }
            let originY = scrollView.contentView.bounds.origin.y
            guard lastReportedOffsetY.isNaN || abs(lastReportedOffsetY - originY) > 0.5 else { return }
            lastReportedOffsetY = originY
            DispatchQueue.main.async {
                offsetChangeHandler(originY)
            }
        }

        private func applyStoredOffsetIfNeeded(_ storedOffsetY: CGFloat) {
            guard let scrollView else { return }
            DispatchQueue.main.async { [weak self, weak scrollView] in
                guard let self, let scrollView else { return }
                let visible = scrollView.documentVisibleRect
                let documentHeight = scrollView.documentView?.bounds.height ?? 0
                let maxY = max(0, documentHeight - visible.height)
                bounceDebugLog(
                    "applyStoredOffset key=\(self.attachedColumnKey ?? "nil") " +
                    "stored=\(String(format: "%.1f", storedOffsetY)) current=\(String(format: "%.1f", visible.origin.y)) " +
                    "max=\(String(format: "%.1f", maxY))"
                )
                let applied = CaretScrollCoordinator.applyVerticalScrollIfNeeded(
                    scrollView: scrollView,
                    visibleRect: visible,
                    targetY: storedOffsetY,
                    minY: 0,
                    maxY: maxY,
                    deadZone: 0.5,
                    snapToPixel: true
                )
                if applied {
                    self.lastReportedOffsetY = scrollView.contentView.bounds.origin.y
                }
            }
        }

        private func resolveScrollView(from view: NSView) -> NSScrollView? {
            var current: NSView? = view
            while let candidate = current {
                if let scrollView = candidate.enclosingScrollView {
                    return scrollView
                }
                current = candidate.superview
            }
            return nil
        }
    }
}

// MARK: - 히스토리 비교를 위한 타입

