import AppKit
import SwiftUI

final class BWRBoardViewportHandle {
    weak var scrollView: NSScrollView?
}

final class BWRBoardKeyboardHandle {
    weak var view: NSView?

    func focus() {
        guard let view else {
            return
        }

        guard let window = view.window else {
            DispatchQueue.main.async { [weak self] in
                self?.focus()
            }
            return
        }

        if window.firstResponder !== view {
            window.makeFirstResponder(view)
        }
    }
}

struct BWRBoardPointerDragValue: Equatable {
    let startLocation: CGPoint
    let location: CGPoint

    var translation: CGSize {
        CGSize(
            width: location.x - startLocation.x,
            height: location.y - startLocation.y
        )
    }
}

extension NSEvent.ModifierFlags {
    var bwrCommandModifiers: NSEvent.ModifierFlags {
        intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
    }
}

struct BWRBoardKeyboardMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let keyboardHandle: BWRBoardKeyboardHandle
    let onKeyEvent: (NSEvent) -> Bool

    func makeNSView(context: Context) -> BWRBoardKeyboardMonitorView {
        let view = BWRBoardKeyboardMonitorView()
        view.isEnabled = isEnabled
        view.keyboardHandle = keyboardHandle
        view.onKeyEvent = onKeyEvent
        return view
    }

    func updateNSView(_ nsView: BWRBoardKeyboardMonitorView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.keyboardHandle = keyboardHandle
        nsView.onKeyEvent = onKeyEvent
    }
}

struct BWRBoardScrollMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let viewportHandle: BWRBoardViewportHandle
    let onScrollEvent: () -> Void
    let onCommandZoomScroll: (CGFloat, CGPoint) -> Bool

    func makeNSView(context: Context) -> BWRBoardScrollMonitorView {
        let view = BWRBoardScrollMonitorView()
        view.isEnabled = isEnabled
        view.viewportHandle = viewportHandle
        view.onScrollEvent = onScrollEvent
        view.onCommandZoomScroll = onCommandZoomScroll
        return view
    }

    func updateNSView(_ nsView: BWRBoardScrollMonitorView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.viewportHandle = viewportHandle
        nsView.onScrollEvent = onScrollEvent
        nsView.onCommandZoomScroll = onCommandZoomScroll
    }
}

struct BWRBoardNativeMagnificationBridge: NSViewRepresentable {
    @Binding var magnification: CGFloat
    let magnificationRange: ClosedRange<CGFloat>
    let viewportHandle: BWRBoardViewportHandle
    let onWillStartLiveMagnify: () -> Void
    let onDidEndLiveMagnify: () -> Void

    func makeNSView(context: Context) -> BWRBoardNativeMagnificationView {
        let view = BWRBoardNativeMagnificationView()
        view.viewportHandle = viewportHandle
        view.onMagnificationChanged = { value in
            if abs(value - magnification) > 0.0001 {
                DispatchQueue.main.async {
                    self.magnification = value
                }
            }
        }
        view.onWillStartLiveMagnify = onWillStartLiveMagnify
        view.onDidEndLiveMagnify = onDidEndLiveMagnify
        view.updateConfiguration(
            magnification: magnification,
            magnificationRange: magnificationRange
        )
        return view
    }

    func updateNSView(_ nsView: BWRBoardNativeMagnificationView, context: Context) {
        nsView.viewportHandle = viewportHandle
        nsView.onMagnificationChanged = { value in
            if abs(value - magnification) > 0.0001 {
                DispatchQueue.main.async {
                    self.magnification = value
                }
            }
        }
        nsView.onWillStartLiveMagnify = onWillStartLiveMagnify
        nsView.onDidEndLiveMagnify = onDidEndLiveMagnify
        nsView.updateConfiguration(
            magnification: magnification,
            magnificationRange: magnificationRange
        )
    }
}

struct BWRBoardPointerMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let viewportHandle: BWRBoardViewportHandle
    let onHoverChange: (CGPoint?) -> Void
    let onPrimaryDown: (CGPoint) -> Void
    let onPrimaryDragChanged: (BWRBoardPointerDragValue) -> Void
    let onPrimaryUp: (BWRBoardPointerDragValue, Int) -> Void

    func makeNSView(context: Context) -> BWRBoardPointerMonitorView {
        let view = BWRBoardPointerMonitorView()
        view.isEnabled = isEnabled
        view.viewportHandle = viewportHandle
        view.onHoverChange = onHoverChange
        view.onPrimaryDown = onPrimaryDown
        view.onPrimaryDragChanged = onPrimaryDragChanged
        view.onPrimaryUp = onPrimaryUp
        return view
    }

    func updateNSView(_ nsView: BWRBoardPointerMonitorView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.viewportHandle = viewportHandle
        nsView.onHoverChange = onHoverChange
        nsView.onPrimaryDown = onPrimaryDown
        nsView.onPrimaryDragChanged = onPrimaryDragChanged
        nsView.onPrimaryUp = onPrimaryUp
    }
}

final class BWRBoardKeyboardMonitorView: NSView {
    var isEnabled = true
    weak var keyboardHandle: BWRBoardKeyboardHandle?
    var onKeyEvent: ((NSEvent) -> Bool)?

    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        keyboardHandle?.view = self
        installMonitorIfNeeded()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        keyboardHandle?.view = self
    }

    override func removeFromSuperview() {
        super.removeFromSuperview()
        if keyboardHandle?.view === self {
            keyboardHandle?.view = nil
        }
        removeMonitor()
    }

    deinit {
        removeMonitor()
    }

    private func installMonitorIfNeeded() {
        guard monitor == nil else {
            return
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            return shouldHandle(event) ? nil : event
        }
    }

    private func removeMonitor() {
        guard let monitor else {
            return
        }

        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    private func shouldHandle(_ event: NSEvent) -> Bool {
        guard isEnabled else {
            return false
        }

        guard let window else {
            return false
        }

        guard window.isKeyWindow else {
            return false
        }

        guard let onKeyEvent else {
            return false
        }

        return onKeyEvent(event)
    }
}

final class BWRBoardPointerMonitorView: NSView {
    weak var viewportHandle: BWRBoardViewportHandle?
    var isEnabled = true {
        didSet {
            if !isEnabled {
                pressedState = nil
                onHoverChange?(nil)
            }
        }
    }
    var onHoverChange: ((CGPoint?) -> Void)?
    var onPrimaryDown: ((CGPoint) -> Void)?
    var onPrimaryDragChanged: ((BWRBoardPointerDragValue) -> Void)?
    var onPrimaryUp: ((BWRBoardPointerDragValue, Int) -> Void)?

    private var monitor: Any?
    private var pressedState: (startLocation: CGPoint, clickCount: Int)?

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshViewportHandle()
        installMonitorIfNeeded()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        refreshViewportHandle()
    }

    override func removeFromSuperview() {
        super.removeFromSuperview()
        removeMonitor()
    }

    deinit {
        removeMonitor()
    }

    private func installMonitorIfNeeded() {
        guard monitor == nil else {
            return
        }

        window?.acceptsMouseMovedEvents = true
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved]
        ) { [weak self] event in
            guard let self else {
                return event
            }

            return self.handle(event) ? nil : event
        }
    }

    private func removeMonitor() {
        guard let monitor else {
            return
        }

        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard isEnabled else {
            return false
        }

        guard
            let window,
            event.window === window
        else {
            return false
        }

        guard let scrollView = resolvedScrollView() else {
            return false
        }

        let pointInViewport = scrollView.contentView.convert(event.locationInWindow, from: nil)
        let isInsideViewport = scrollView.contentView.bounds.contains(pointInViewport)

        switch event.type {
        case .mouseMoved:
            guard isInsideViewport else {
                onHoverChange?(nil)
                return false
            }

            onHoverChange?(boardPoint(for: event))
            return false

        case .leftMouseDown:
            guard isInsideViewport, let point = boardPoint(for: event) else {
                return false
            }

            pressedState = (startLocation: point, clickCount: event.clickCount)
            onPrimaryDown?(point)
            return true

        case .leftMouseDragged:
            guard let pressedState, let point = boardPoint(for: event) else {
                return false
            }

            onPrimaryDragChanged?(
                BWRBoardPointerDragValue(
                    startLocation: pressedState.startLocation,
                    location: point
                )
            )
            return true

        case .leftMouseUp:
            guard let pressedState, let point = boardPoint(for: event) else {
                self.pressedState = nil
                return false
            }

            onPrimaryUp?(
                BWRBoardPointerDragValue(
                    startLocation: pressedState.startLocation,
                    location: point
                ),
                pressedState.clickCount
            )
            self.pressedState = nil
            return true

        default:
            return false
        }
    }

    private func boardPoint(for event: NSEvent) -> CGPoint? {
        guard let scrollView = resolvedScrollView() else {
            return nil
        }

        return scrollView.contentView.convert(event.locationInWindow, from: nil)
    }

    private func refreshViewportHandle() {
        viewportHandle?.scrollView = resolvedScrollView()
    }

    private func resolvedScrollView() -> NSScrollView? {
        if let scrollView = viewportHandle?.scrollView {
            return scrollView
        }

        let scrollView = bwrResolvedScrollView()
        viewportHandle?.scrollView = scrollView
        return scrollView
    }
}

final class BWRBoardScrollMonitorView: NSView {
    var isEnabled = true
    weak var viewportHandle: BWRBoardViewportHandle?
    var onScrollEvent: (() -> Void)?
    var onCommandZoomScroll: ((CGFloat, CGPoint) -> Bool)?

    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshViewportHandle()
        installMonitorIfNeeded()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        refreshViewportHandle()
    }

    override func removeFromSuperview() {
        super.removeFromSuperview()
        removeMonitor()
    }

    deinit {
        removeMonitor()
    }

    private func installMonitorIfNeeded() {
        guard monitor == nil else {
            return
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else {
                return event
            }

            return self.handle(event) ? nil : event
        }
    }

    private func removeMonitor() {
        guard let monitor else {
            return
        }

        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard isEnabled else {
            return false
        }

        guard
            let window,
            event.window === window
        else {
            return false
        }

        guard let scrollView = viewportHandle?.scrollView ?? resolvedScrollView() else {
            return false
        }

        let anchorInContentView = scrollView.contentView.convert(event.locationInWindow, from: nil)
        guard scrollView.contentView.bounds.contains(anchorInContentView) else {
            return false
        }

        if event.modifierFlags.bwrCommandModifiers == [.command] {
            return onCommandZoomScroll?(event.scrollingDeltaY, anchorInContentView) ?? false
        }

        onScrollEvent?()
        return false
    }

    private func refreshViewportHandle() {
        viewportHandle?.scrollView = resolvedScrollView()
    }

    private func resolvedScrollView() -> NSScrollView? {
        bwrResolvedScrollView()
    }
}

final class BWRBoardNativeMagnificationView: NSView {
    weak var viewportHandle: BWRBoardViewportHandle?
    var onMagnificationChanged: ((CGFloat) -> Void)?
    var onWillStartLiveMagnify: (() -> Void)?
    var onDidEndLiveMagnify: (() -> Void)?

    private weak var observedScrollView: NSScrollView?
    private var magnification: CGFloat = 1
    private var magnificationRange: ClosedRange<CGFloat> = 1...1
    private var notificationTokens: [NSObjectProtocol] = []
    private var isApplyingProgrammaticMagnification = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachIfNeeded()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        attachIfNeeded()
    }

    override func removeFromSuperview() {
        super.removeFromSuperview()
        removeObservers()
    }

    deinit {
        removeObservers()
    }

    func updateConfiguration(
        magnification: CGFloat,
        magnificationRange: ClosedRange<CGFloat>
    ) {
        self.magnification = magnification
        self.magnificationRange = magnificationRange
        attachIfNeeded()
        applyProgrammaticMagnificationIfNeeded()
    }

    private func attachIfNeeded() {
        guard let scrollView = viewportHandle?.scrollView ?? resolvedScrollView() else {
            return
        }

        viewportHandle?.scrollView = scrollView

        if observedScrollView !== scrollView {
            removeObservers()
            observedScrollView = scrollView
            installObservers(for: scrollView)
        }

        scrollView.allowsMagnification = true
        scrollView.minMagnification = magnificationRange.lowerBound
        scrollView.maxMagnification = magnificationRange.upperBound
        scrollView.usesPredominantAxisScrolling = false
    }

    private func applyProgrammaticMagnificationIfNeeded() {
        guard let scrollView = observedScrollView else {
            return
        }

        let clamped = min(max(magnification, magnificationRange.lowerBound), magnificationRange.upperBound)
        guard abs(scrollView.magnification - clamped) > 0.0001 else {
            return
        }

        isApplyingProgrammaticMagnification = true
        scrollView.magnification = clamped

        DispatchQueue.main.async { [weak self] in
            self?.isApplyingProgrammaticMagnification = false
        }
    }

    private func installObservers(for scrollView: NSScrollView) {
        let center = NotificationCenter.default
        notificationTokens = [
            center.addObserver(
                forName: NSScrollView.willStartLiveMagnifyNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                self?.onWillStartLiveMagnify?()
            },
            center.addObserver(
                forName: NSScrollView.didEndLiveMagnifyNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                guard let self, let scrollView = self.observedScrollView else {
                    return
                }

                self.onMagnificationChanged?(scrollView.magnification)
                if !self.isApplyingProgrammaticMagnification {
                    self.onDidEndLiveMagnify?()
                }
            }
        ]
    }

    private func removeObservers() {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        notificationTokens.removeAll()
        observedScrollView = nil
    }

    private func resolvedScrollView() -> NSScrollView? {
        bwrResolvedScrollView()
    }
}

private extension NSView {
    func bwrResolvedScrollView() -> NSScrollView? {
        if let enclosingScrollView {
            return enclosingScrollView
        }

        if let directAncestor = sequence(first: superview, next: { $0?.superview })
            .compactMap({ $0 as? NSScrollView })
            .first {
            return directAncestor
        }

        let anchorInWindow = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: nil)
        guard let windowRoot = window?.contentView else {
            return nil
        }

        return windowRoot.bwrDescendantScrollViews()
            .filter { scrollView in
                scrollView.convert(scrollView.bounds, to: nil).contains(anchorInWindow)
            }
            .min { lhs, rhs in
                let lhsRect = lhs.convert(lhs.bounds, to: nil)
                let rhsRect = rhs.convert(rhs.bounds, to: nil)
                return lhsRect.width * lhsRect.height < rhsRect.width * rhsRect.height
            }
    }

    func bwrDescendantScrollViews() -> [NSScrollView] {
        subviews.flatMap { subview -> [NSScrollView] in
            let nested = subview.bwrDescendantScrollViews()
            if let scrollView = subview as? NSScrollView {
                return [scrollView] + nested
            }
            return nested
        }
    }
}

struct BWRInlineMarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let isFocused: Bool
    let onCommit: () -> Void
    let onAdvance: (Bool) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onCommit: onCommit,
            onAdvance: onAdvance,
            onCancel: onCancel
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = BWRInlineTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        let editorFontSize = BWRBoardLayoutMetrics.cardEditorFontSize
        textView.font = NSFont(name: "Avenir Next", size: editorFontSize) ?? .systemFont(ofSize: editorFontSize)
        textView.textContainerInset = NSSize(width: 0, height: BWRBoardLayoutMetrics.cardEditorTextInsetHeight)
        textView.onCommit = context.coordinator.onCommit
        textView.onAdvance = context.coordinator.onAdvance
        textView.onCancel = context.coordinator.onCancel

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? BWRInlineTextView else {
            return
        }

        context.coordinator.text = $text
        textView.onCommit = context.coordinator.onCommit
        textView.onAdvance = context.coordinator.onAdvance
        textView.onCancel = context.coordinator.onCancel

        if textView.string != text {
            textView.string = text
        }

        if isFocused, textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        let onCommit: () -> Void
        let onAdvance: (Bool) -> Void
        let onCancel: () -> Void

        init(
            text: Binding<String>,
            onCommit: @escaping () -> Void,
            onAdvance: @escaping (Bool) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.text = text
            self.onCommit = onCommit
            self.onAdvance = onAdvance
            self.onCancel = onCancel
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            text.wrappedValue = textView.string
        }
    }
}

private final class BWRInlineTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onAdvance: ((Bool) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.bwrCommandModifiers
        let hasOnlyShiftModifier = modifiers == [.shift]
        let hasNoModifiers = modifiers.isEmpty

        switch event.keyCode {
        case 36, 76:
            if hasNoModifiers {
                onCommit?()
                return
            }
        case 48:
            if hasNoModifiers || hasOnlyShiftModifier {
                onAdvance?(hasOnlyShiftModifier)
                return
            }
        case 53:
            if hasNoModifiers {
                onCancel?()
                return
            }
        default:
            break
        }

        super.keyDown(with: event)
    }
}
