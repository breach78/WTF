import AppKit
import SwiftUI

struct MainWorkspaceSurface: NSViewRepresentable {
    @ObservedObject var controller: MainWorkspaceSurfaceController

    let scrollCoordinator: MainCanvasScrollCoordinator
    let snapshot: MainWorkspaceSnapshot
    let renderState: MainWorkspaceSurfaceRenderState
    let plan: MainWorkspaceScrollPlan?
    let callbacks: MainWorkspaceSurfaceCallbacks

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
            callbacks: callbacks
        )
    }

    static func dismantleNSView(_ nsView: MainWorkspaceSurfaceView, coordinator: ()) {
        nsView.teardown()
    }
}

private struct MainWorkspaceSurfaceBranchContext: Hashable {
    let level: Int
    let viewportKey: String
    let parentCardID: UUID?
}

final class MainWorkspaceSurfaceView: NSView {
    private let scrollCoordinator: MainCanvasScrollCoordinator
    private let horizontalScrollView = NSScrollView()
    private let horizontalDocumentView = MainWorkspaceBackgroundView()

    private var horizontalBoundsObserver: NSObjectProtocol?
    private var isPostApplyRefreshScheduled = false
    private var slotViews: [Int: MainWorkspaceSurfaceSlotView] = [:]
    private var columnRegistry: [MainWorkspaceSurfaceBranchContext: MainWorkspaceSurfaceColumnView] = [:]
    private var currentSnapshot: MainWorkspaceSnapshot?
    private var currentCallbacks: MainWorkspaceSurfaceCallbacks?

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
        for slotView in slotViews.values {
            slotView.teardown()
            slotView.removeFromSuperview()
        }
        slotViews.removeAll()
        columnRegistry.removeAll()
        scrollCoordinator.unregisterMainCanvasHorizontalScrollView(matching: horizontalScrollView)
    }

    func apply(
        snapshot: MainWorkspaceSnapshot,
        callbacks: MainWorkspaceSurfaceCallbacks
    ) {
        currentSnapshot = snapshot
        currentCallbacks = callbacks

        scrollCoordinator.registerMainCanvasHorizontalScrollView(horizontalScrollView)
        layer?.backgroundColor = snapshot.backgroundColor.cgColor
        horizontalDocumentView.onBackgroundClick = callbacks.onBackgroundTap

        synchronizeSlots(snapshot: snapshot, callbacks: callbacks)
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
        for columnView in columnRegistry.values {
            columnView.reconnectScrollCoordinator()
        }
        updateDocumentLayout()
        scrollCoordinator.refreshMainCanvasHorizontalScrollViewState(horizontalScrollView)
    }

    func rectForCard(viewportKey: String, cardID: UUID) -> CGRect? {
        columnRegistry.first { $0.key.viewportKey == viewportKey }?.value.rectForCard(cardID)
    }

    func viewportRect(for viewportKey: String) -> CGRect? {
        columnRegistry.first { $0.key.viewportKey == viewportKey }?.value.viewportRect
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

    private func synchronizeSlots(
        snapshot: MainWorkspaceSnapshot,
        callbacks: MainWorkspaceSurfaceCallbacks
    ) {
        let activeLevels = Set(snapshot.slots.map(\.level))
        for level in slotViews.keys where !activeLevels.contains(level) {
            slotViews[level]?.teardown()
            slotViews[level]?.removeFromSuperview()
            slotViews.removeValue(forKey: level)
        }

        for slot in snapshot.slots {
            let slotView: MainWorkspaceSurfaceSlotView
            if let existing = slotViews[slot.level] {
                slotView = existing
            } else {
                let created = MainWorkspaceSurfaceSlotView(scrollCoordinator: scrollCoordinator)
                created.translatesAutoresizingMaskIntoConstraints = true
                slotViews[slot.level] = created
                horizontalDocumentView.addSubview(created)
                slotView = created
            }

            if let column = slot.column {
                slotView.apply(
                    column: column,
                    stateSnapshot: snapshot.stateSnapshot,
                    backgroundColor: snapshot.backgroundColor,
                    renderMetrics: snapshot.cardRenderMetrics,
                    callbacks: callbacks
                )
            } else {
                slotView.clear()
            }
        }

        rebuildColumnRegistry()
    }

    private func rebuildColumnRegistry() {
        columnRegistry = slotViews.values.reduce(into: [:]) { partialResult, slotView in
            guard let columnView = slotView.columnView,
                  let context = columnView.branchContext else { return }
            partialResult[context] = columnView
        }
    }

    private func updateDocumentLayout() {
        guard let snapshot = currentSnapshot else { return }

        let viewportWidth = max(1, horizontalScrollView.contentView.bounds.width)
        let viewportHeight = max(1, horizontalScrollView.contentView.bounds.height)
        let columnCount = max(1, snapshot.slots.count)
        let columnWidth = snapshot.slots.first(where: { $0.column != nil })?.column?.width ?? MainCanvasLayoutMetrics.columnWidth

        let documentSize = CGSize(
            width: max(
                viewportWidth,
                snapshot.leadingInset + (CGFloat(columnCount) * columnWidth) + snapshot.trailingInset
            ),
            height: max(viewportHeight, snapshot.viewportHeight)
        )
        let documentFrame = CGRect(origin: .zero, size: documentSize)
        if horizontalDocumentView.frame != documentFrame {
            horizontalDocumentView.frame = documentFrame
        }

        for slot in snapshot.slots {
            guard let slotView = slotViews[slot.level] else { continue }
            let originX = snapshot.leadingInset + (CGFloat(slot.level) * columnWidth)
            slotView.frame = CGRect(
                x: originX,
                y: 0,
                width: columnWidth,
                height: documentSize.height
            )
            slotView.needsLayout = true
        }
    }
}

private final class MainWorkspaceSurfaceSlotView: NSView {
    fileprivate private(set) var columnView: MainWorkspaceSurfaceColumnView?

    private let scrollCoordinator: MainCanvasScrollCoordinator

    override var isFlipped: Bool {
        true
    }

    init(scrollCoordinator: MainCanvasScrollCoordinator) {
        self.scrollCoordinator = scrollCoordinator
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        columnView?.frame = bounds
    }

    func apply(
        column: MainWorkspaceSnapshot.Column,
        stateSnapshot: MainWorkspaceStateSnapshot,
        backgroundColor: NSColor,
        renderMetrics: MainWorkspaceCardRenderMetrics,
        callbacks: MainWorkspaceSurfaceCallbacks
    ) {
        let needsReplacement = columnView?.branchContext?.viewportKey != column.viewportKey
        if needsReplacement {
            columnView?.teardown()
            columnView?.removeFromSuperview()
            columnView = nil
        }

        let resolvedColumnView: MainWorkspaceSurfaceColumnView
        if let existing = columnView {
            resolvedColumnView = existing
        } else {
            let created = MainWorkspaceSurfaceColumnView(scrollCoordinator: scrollCoordinator)
            created.translatesAutoresizingMaskIntoConstraints = true
            addSubview(created)
            columnView = created
            resolvedColumnView = created
        }

        resolvedColumnView.frame = bounds
        resolvedColumnView.apply(
            column: column,
            stateSnapshot: stateSnapshot,
            backgroundColor: backgroundColor,
            renderMetrics: renderMetrics,
            callbacks: callbacks
        )
    }

    func clear() {
        columnView?.teardown()
        columnView?.removeFromSuperview()
        columnView = nil
    }

    func teardown() {
        clear()
    }
}

private final class MainWorkspaceSurfaceColumnView: NSView {
    private let scrollCoordinator: MainCanvasScrollCoordinator
    private let scrollView = NSScrollView()
    private let documentView = MainWorkspaceBackgroundView()

    private var contentBoundsObserver: NSObjectProtocol?
    private var callbacks: MainWorkspaceSurfaceCallbacks?
    private var currentColumn: MainWorkspaceSnapshot.Column?
    private var currentStateSnapshot: MainWorkspaceStateSnapshot?
    private var currentBackgroundColor: NSColor = .clear
    private var currentRenderMetrics = MainWorkspaceCardRenderMetrics(
        fontSize: 14,
        lineSpacing: 5,
        contentPadding: MainEditorLayoutMetrics.mainCardContentPadding
    )
    private var cardViewsByID: [UUID: MainWorkspaceSurfaceCardView] = [:]

    fileprivate private(set) var branchContext: MainWorkspaceSurfaceBranchContext?

    override var isFlipped: Bool {
        true
    }

    var viewportRect: CGRect? {
        scrollView.documentVisibleRect
    }

    init(scrollCoordinator: MainCanvasScrollCoordinator) {
        self.scrollCoordinator = scrollCoordinator
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setupScrollView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        teardown()
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
    }

    func apply(
        column: MainWorkspaceSnapshot.Column,
        stateSnapshot: MainWorkspaceStateSnapshot,
        backgroundColor: NSColor,
        renderMetrics: MainWorkspaceCardRenderMetrics,
        callbacks: MainWorkspaceSurfaceCallbacks
    ) {
        self.callbacks = callbacks
        currentColumn = column
        currentStateSnapshot = stateSnapshot
        currentBackgroundColor = backgroundColor
        currentRenderMetrics = renderMetrics
        documentView.onBackgroundClick = callbacks.onBackgroundTap

        let nextContext = MainWorkspaceSurfaceBranchContext(
            level: column.level,
            viewportKey: column.viewportKey,
            parentCardID: column.parent?.id
        )
        if branchContext != nextContext {
            if let previousViewportKey = branchContext?.viewportKey {
                callbacks.onObservedFramesChange(previousViewportKey, [:])
                scrollCoordinator.unregister(viewportKey: previousViewportKey, matching: scrollView)
            }
            branchContext = nextContext
            scrollCoordinator.register(scrollView: scrollView, for: column.viewportKey)
        }

        renderColumn()
    }

    func reconnectScrollCoordinator() {
        guard let branchContext else { return }
        scrollCoordinator.register(scrollView: scrollView, for: branchContext.viewportKey)
        emitCurrentMeasurements()
    }

    func teardown() {
        if let contentBoundsObserver {
            NotificationCenter.default.removeObserver(contentBoundsObserver)
            self.contentBoundsObserver = nil
        }
        if let viewportKey = branchContext?.viewportKey {
            callbacks?.onObservedFramesChange(viewportKey, [:])
            scrollCoordinator.unregister(viewportKey: viewportKey, matching: scrollView)
        }
        branchContext = nil
        callbacks = nil
        currentColumn = nil
        currentStateSnapshot = nil
        cardViewsByID.removeAll()
    }

    func rectForCard(_ cardID: UUID) -> CGRect? {
        cardViewsByID[cardID]?.frame
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.contentView.postsBoundsChangedNotifications = true

        documentView.translatesAutoresizingMaskIntoConstraints = true
        scrollView.documentView = documentView
        addSubview(scrollView)

        contentBoundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            guard let self,
                  let callbacks = self.callbacks,
                  let branchContext = self.branchContext else { return }
            callbacks.onViewportOffsetChange(
                branchContext.viewportKey,
                max(0, self.scrollView.contentView.bounds.origin.y)
            )
        }
    }

    private func renderColumn() {
        guard let column = currentColumn,
              let stateSnapshot = currentStateSnapshot,
              let callbacks else { return }

        for view in documentView.subviews {
            view.removeFromSuperview()
        }
        cardViewsByID.removeAll()

        let columnWidth = max(1, column.width)
        let cardWidth = max(1, columnWidth - (MainCanvasLayoutMetrics.columnHorizontalPadding * 2))
        let backgroundIsDark = currentBackgroundColor.resolvedSurfaceBrightness < 0.5
        var framesByID: [UUID: CGRect] = [:]
        var cursorY = column.topSpacerHeight

        for (index, card) in column.cards.enumerated() {
            let height = max(1, column.cardHeightByID[card.id] ?? 1)
            let frame = CGRect(
                x: MainCanvasLayoutMetrics.columnHorizontalPadding,
                y: cursorY,
                width: cardWidth,
                height: height
            )
            let cardView = MainWorkspaceSurfaceCardView()
            cardView.frame = frame
            let displayState = MainWorkspaceSurfaceCardView.displayState(for: card)
            cardView.configure(
                text: displayState.text,
                isPlaceholder: displayState.isPlaceholder,
                isActive: stateSnapshot.activeCardID == card.id,
                backgroundIsDark: backgroundIsDark,
                renderMetrics: currentRenderMetrics,
                onSelect: { [weak self] in
                    guard self != nil else { return }
                    callbacks.onCardSelect(card.id)
                },
                onDoubleClick: { [weak self] in
                    guard self != nil else { return }
                    callbacks.onCardDoubleClick(card.id)
                }
            )
            documentView.addSubview(cardView)
            cardViewsByID[card.id] = cardView
            framesByID[card.id] = frame
            cursorY += height

            guard index < column.cards.count - 1 else { continue }
            let nextCard = column.cards[index + 1]
            if card.parent?.id != nextCard.parent?.id {
                let separator = NSView(frame: CGRect(
                    x: 14,
                    y: cursorY,
                    width: max(1, cardWidth - 28),
                    height: column.separatorHeight
                ))
                separator.wantsLayer = true
                separator.layer?.backgroundColor = (
                    backgroundIsDark
                    ? NSColor.white.withAlphaComponent(0.20)
                    : NSColor.black.withAlphaComponent(0.14)
                ).cgColor
                separator.layer?.cornerRadius = column.separatorHeight * 0.5
                documentView.addSubview(separator)
                cursorY += column.separatorHeight
            }

            if column.rowGap > 0 {
                cursorY += column.rowGap
            }
        }

        let contentBottom = cursorY + column.bottomSpacerHeight
        let documentHeight = max(column.viewportHeight, contentBottom)
        let documentFrame = CGRect(x: 0, y: 0, width: columnWidth, height: documentHeight)
        if documentView.frame != documentFrame {
            documentView.frame = documentFrame
        }

        callbacks.onObservedFramesChange(column.viewportKey, framesByID)
        callbacks.onViewportOffsetChange(
            column.viewportKey,
            max(0, scrollView.contentView.bounds.origin.y)
        )
    }

    private func emitCurrentMeasurements() {
        guard let column = currentColumn,
              let callbacks else { return }
        callbacks.onObservedFramesChange(
            column.viewportKey,
            cardViewsByID.reduce(into: [:]) { partialResult, element in
                partialResult[element.key] = element.value.frame
            }
        )
        callbacks.onViewportOffsetChange(
            column.viewportKey,
            max(0, scrollView.contentView.bounds.origin.y)
        )
    }
}

private final class MainWorkspaceSurfaceCardView: NSView {
    private let textField = NSTextField(labelWithString: "")

    private var onSelect: (() -> Void)?
    private var onDoubleClick: (() -> Void)?
    private var text: String = ""
    private var isPlaceholder = false
    private var isActive = false
    private var backgroundIsDark = false
    private var renderMetrics = MainWorkspaceCardRenderMetrics(
        fontSize: 14,
        lineSpacing: 5,
        contentPadding: MainEditorLayoutMetrics.mainCardContentPadding
    )

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.borderWidth = 1
        setupTextField()
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let inset = renderMetrics.contentPadding
        textField.frame = bounds.insetBy(dx: inset, dy: inset)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onDoubleClick?()
            return
        }
        onSelect?()
    }

    func configure(
        text: String,
        isPlaceholder: Bool,
        isActive: Bool,
        backgroundIsDark: Bool,
        renderMetrics: MainWorkspaceCardRenderMetrics,
        onSelect: @escaping () -> Void,
        onDoubleClick: @escaping () -> Void
    ) {
        self.text = text
        self.isPlaceholder = isPlaceholder
        self.isActive = isActive
        self.backgroundIsDark = backgroundIsDark
        self.renderMetrics = renderMetrics
        self.onSelect = onSelect
        self.onDoubleClick = onDoubleClick
        updateAppearance()
        needsLayout = true
    }

    private func setupTextField() {
        textField.translatesAutoresizingMaskIntoConstraints = true
        textField.lineBreakMode = .byWordWrapping
        textField.maximumNumberOfLines = 0
        textField.usesSingleLineMode = false
        addSubview(textField)
    }

    private func updateAppearance() {
        guard let layer else { return }

        let fillColor: NSColor
        let borderColor: NSColor
        let textColor: NSColor

        if isActive {
            fillColor = NSColor.controlAccentColor.withAlphaComponent(0.18)
            borderColor = NSColor.controlAccentColor.withAlphaComponent(0.60)
            textColor = backgroundIsDark ? .white : .black
        } else if backgroundIsDark {
            fillColor = NSColor.white.withAlphaComponent(0.06)
            borderColor = NSColor.white.withAlphaComponent(0.10)
            textColor = NSColor.white.withAlphaComponent(0.92)
        } else {
            fillColor = NSColor.white.withAlphaComponent(0.78)
            borderColor = NSColor.black.withAlphaComponent(0.08)
            textColor = NSColor.black.withAlphaComponent(0.88)
        }

        layer.backgroundColor = fillColor.cgColor
        layer.borderColor = borderColor.cgColor
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = renderMetrics.lineSpacing
        let resolvedFont =
            NSFont(name: "SansMonoCJKFinalDraft", size: renderMetrics.fontSize) ??
            NSFont.monospacedSystemFont(ofSize: renderMetrics.fontSize, weight: .regular)
        textField.attributedStringValue = NSAttributedString(
            string: text,
            attributes: [
                .font: resolvedFont,
                .foregroundColor: isPlaceholder ? textColor.withAlphaComponent(0.4) : textColor,
                .paragraphStyle: paragraphStyle
            ]
        )
    }

    static func displayState(for card: SceneCard) -> (text: String, isPlaceholder: Bool) {
        if card.content.isEmpty {
            return ("내용 없음", true)
        }
        return (card.content, false)
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

private extension NSColor {
    var resolvedSurfaceBrightness: CGFloat {
        guard let color = usingColorSpace(.deviceRGB) else { return 1 }
        return (color.redComponent * 0.299) + (color.greenComponent * 0.587) + (color.blueComponent * 0.114)
    }
}
