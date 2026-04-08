import AppKit
import SwiftUI

struct MainWorkspaceSurface: NSViewRepresentable {
    @ObservedObject var controller: MainWorkspaceSurfaceController

    let scrollCoordinator: MainCanvasScrollCoordinator
    let snapshot: MainWorkspaceSnapshot
    let renderState: MainWorkspaceSurfaceRenderState
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
                self.scrollCoordinator.updateMainCanvasHorizontalOffset(
                    max(0, self.horizontalScrollView.contentView.bounds.origin.x)
                )
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
    private var separatorViews: [NSView] = []

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
        for cardView in cardViewsByID.values {
            cardView.teardown()
            cardView.removeFromSuperview()
        }
        for separatorView in separatorViews {
            separatorView.removeFromSuperview()
        }
        cardViewsByID.removeAll()
        separatorViews.removeAll()
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

        let columnWidth = max(1, column.width)
        let cardWidth = max(1, columnWidth - (MainCanvasLayoutMetrics.columnHorizontalPadding * 2))
        let backgroundIsDark = currentBackgroundColor.resolvedSurfaceBrightness < 0.5
        var framesByID: [UUID: CGRect] = [:]
        var cursorY = column.topSpacerHeight
        let activeCardIDs = Set(column.cards.map(\.id))

        for (cardID, cardView) in cardViewsByID where !activeCardIDs.contains(cardID) {
            cardView.teardown()
            cardView.removeFromSuperview()
            cardViewsByID.removeValue(forKey: cardID)
        }
        for separatorView in separatorViews {
            separatorView.removeFromSuperview()
        }
        separatorViews.removeAll()

        for (index, card) in column.cards.enumerated() {
            let height = max(1, column.cardHeightByID[card.id] ?? 1)
            let frame = CGRect(
                x: MainCanvasLayoutMetrics.columnHorizontalPadding,
                y: cursorY,
                width: cardWidth,
                height: height
            )
            let cardView: MainWorkspaceSurfaceCardView
            if let existing = cardViewsByID[card.id] {
                cardView = existing
            } else {
                let created = MainWorkspaceSurfaceCardView()
                cardViewsByID[card.id] = created
                documentView.addSubview(created)
                cardView = created
            }
            cardView.frame = frame
            let displayState = MainWorkspaceSurfaceCardView.displayState(for: card)
            cardView.configure(
                cardID: card.id,
                text: displayState.text,
                isPlaceholder: displayState.isPlaceholder,
                isActive: stateSnapshot.activeCardID == card.id,
                backgroundIsDark: backgroundIsDark,
                appearance: backgroundIsDark ? "dark" : "light",
                isEditing: stateSnapshot.editingCardID == card.id,
                activeEditorSessionID: stateSnapshot.editorSessionID(for: card.id),
                renderMetrics: currentRenderMetrics,
                cardColorHex: card.colorHex,
                onContextMenuPrepare: { [weak self] in
                    guard self != nil else { return }
                    callbacks.onContextMenuPrepare(card.id)
                },
                onContextCopy: { [weak self] in
                    guard self != nil else { return }
                    callbacks.onContextCopy(card.id)
                },
                onContextCut: { [weak self] in
                    guard self != nil else { return }
                    callbacks.onContextCut(card.id)
                },
                onContextPaste: { [weak self] in
                    guard self != nil else { return }
                    callbacks.onContextPaste(card.id)
                },
                onContextCloneCopy: { [weak self] in
                    guard self != nil else { return }
                    callbacks.onContextCloneCopy(card.id)
                },
                onContextDelete: { [weak self] in
                    guard self != nil else { return }
                    callbacks.onContextDelete(card.id)
                },
                onContextColorChange: { [weak self] hex in
                    guard self != nil else { return }
                    callbacks.onContextColorChange(card.id, hex)
                },
                onSelectAtLocation: { [weak self] location in
                    guard self != nil else { return }
                    callbacks.onCardSelect(card.id, location)
                },
                onDoubleClick: { [weak self] in
                    guard self != nil else { return }
                    callbacks.onCardDoubleClick(card.id)
                },
                onTextChange: { [weak self] oldValue, newValue in
                    guard self != nil else { return }
                    callbacks.onEditorTextChange(card.id, oldValue, newValue)
                },
                onEndEdit: { [weak self] in
                    guard self != nil else { return }
                    callbacks.onEditorEnd(card.id)
                },
                onTab: { [weak self] in
                    guard self != nil else { return }
                    callbacks.onEditorTab(card.id)
                },
                onCommandEnter: { [weak self] in
                    guard self != nil else { return }
                    callbacks.onEditorCommandEnter(card.id)
                }
            )
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
                separatorViews.append(separator)
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

    private var cardID: UUID?
    private var onSelectAtLocation: ((CGPoint?) -> Void)?
    private var onDoubleClick: (() -> Void)?
    private var onTextChange: ((String, String) -> Void)?
    private var onEndEdit: (() -> Void)?
    private var onTab: (() -> Void)?
    private var onCommandEnter: (() -> Void)?
    private var text: String = ""
    private var isPlaceholder = false
    private var isActive = false
    private var backgroundIsDark = false
    private var editorAppearance = "dark"
    private var isEditing = false
    private var activeEditorSessionID: Int?
    private var cardColorHex: String?
    private var onContextMenuPrepare: (() -> Void)?
    private var onContextCopy: (() -> Void)?
    private var onContextCut: (() -> Void)?
    private var onContextPaste: (() -> Void)?
    private var onContextCloneCopy: (() -> Void)?
    private var onContextDelete: (() -> Void)?
    private var onContextColorChange: ((String?) -> Void)?
    private var renderMetrics = MainWorkspaceCardRenderMetrics(
        fontSize: 14,
        lineSpacing: 5,
        contentPadding: MainEditorLayoutMetrics.mainCardContentPadding
    )
    private var editSession: MainWorkspaceEditSession?

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
        if isEditing {
            applyEditSessionIfNeeded()
        }
    }

    override func mouseDown(with event: NSEvent) {
        if isEditing {
            editSession?.focus()
            super.mouseDown(with: event)
            return
        }
        let localPoint = convert(event.locationInWindow, from: nil)
        if event.clickCount >= 2 {
            onDoubleClick?()
            return
        }
        onSelectAtLocation?(localPoint)
    }

    override func rightMouseDown(with event: NSEvent) {
        onContextMenuPrepare?()
        if let menu = contextMenuForSelection() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        super.rightMouseDown(with: event)
    }

    private func contextMenuForSelection() -> NSMenu? {
        let menu = NSMenu()

        if onContextCopy != nil {
            let copyItem = NSMenuItem(title: "복사", action: #selector(handleContextCopy), keyEquivalent: "")
            copyItem.target = self
            menu.addItem(copyItem)
        }

        if onContextCut != nil {
            if !menu.items.isEmpty { menu.addItem(NSMenuItem.separator()) }
            let cutItem = NSMenuItem(title: "잘라내기", action: #selector(handleContextCut), keyEquivalent: "")
            cutItem.target = self
            menu.addItem(cutItem)
        }

        if onContextPaste != nil {
            if !menu.items.isEmpty { menu.addItem(NSMenuItem.separator()) }
            let pasteItem = NSMenuItem(title: "붙여넣기", action: #selector(handleContextPaste), keyEquivalent: "")
            pasteItem.target = self
            menu.addItem(pasteItem)
        }

        if onContextCloneCopy != nil {
            if !menu.items.isEmpty { menu.addItem(NSMenuItem.separator()) }
            let cloneItem = NSMenuItem(title: "클론 복사", action: #selector(handleContextCloneCopy), keyEquivalent: "")
            cloneItem.target = self
            menu.addItem(cloneItem)
        }

        if onContextDelete != nil {
            if !menu.items.isEmpty { menu.addItem(NSMenuItem.separator()) }
            let deleteItem = NSMenuItem(title: "삭제", action: #selector(handleContextDelete), keyEquivalent: "")
            deleteItem.target = self
            menu.addItem(deleteItem)
        }

        if onContextColorChange != nil {
            if !menu.items.isEmpty { menu.addItem(NSMenuItem.separator()) }
            let colorMenuItem = NSMenuItem(title: "색상", action: nil, keyEquivalent: "")
            let colorSubmenu = NSMenu(title: "색상")
            appendColorMenuItem(to: colorSubmenu, title: "기본", colorHex: nil)
            appendColorMenuItem(to: colorSubmenu, title: "연보라", colorHex: "E7D5FF")
            appendColorMenuItem(to: colorSubmenu, title: "하늘", colorHex: "CFE8FF")
            appendColorMenuItem(to: colorSubmenu, title: "민트", colorHex: "CFF2E8")
            appendColorMenuItem(to: colorSubmenu, title: "살구", colorHex: "FFE1CC")
            appendColorMenuItem(to: colorSubmenu, title: "연노랑", colorHex: "FFF3C4")
            colorMenuItem.submenu = colorSubmenu
            menu.addItem(colorMenuItem)
        }

        return menu.items.isEmpty ? nil : menu
    }

    private func appendColorMenuItem(to menu: NSMenu, title: String, colorHex: String?) {
        let item = NSMenuItem(title: title, action: #selector(handleContextColorMenu(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = colorHex ?? "__main_surface_card_color_default__"
        item.state = (cardColorHex == colorHex) ? .on : .off
        menu.addItem(item)
    }

    @objc private func handleContextCopy() {
        onContextCopy?()
    }

    @objc private func handleContextCut() {
        onContextCut?()
    }

    @objc private func handleContextPaste() {
        onContextPaste?()
    }

    @objc private func handleContextCloneCopy() {
        onContextCloneCopy?()
    }

    @objc private func handleContextDelete() {
        onContextDelete?()
    }

    @objc private func handleContextColorMenu(_ sender: NSMenuItem) {
        let defaultToken = "__main_surface_card_color_default__"
        let value = sender.representedObject as? String
        onContextColorChange?(value == defaultToken ? nil : value)
    }

    func configure(
        cardID: UUID,
        text: String,
        isPlaceholder: Bool,
        isActive: Bool,
        backgroundIsDark: Bool,
        appearance: String,
        isEditing: Bool,
        activeEditorSessionID: Int?,
        renderMetrics: MainWorkspaceCardRenderMetrics,
        cardColorHex: String?,
        onContextMenuPrepare: @escaping () -> Void,
        onContextCopy: @escaping () -> Void,
        onContextCut: @escaping () -> Void,
        onContextPaste: @escaping () -> Void,
        onContextCloneCopy: @escaping () -> Void,
        onContextDelete: @escaping () -> Void,
        onContextColorChange: @escaping (String?) -> Void,
        onSelectAtLocation: @escaping (CGPoint?) -> Void,
        onDoubleClick: @escaping () -> Void,
        onTextChange: @escaping (String, String) -> Void,
        onEndEdit: @escaping () -> Void,
        onTab: @escaping () -> Void,
        onCommandEnter: @escaping () -> Void
    ) {
        self.cardID = cardID
        self.text = text
        self.isPlaceholder = isPlaceholder
        self.isActive = isActive
        self.backgroundIsDark = backgroundIsDark
        self.editorAppearance = appearance
        self.isEditing = isEditing
        self.activeEditorSessionID = activeEditorSessionID
        self.renderMetrics = renderMetrics
        self.cardColorHex = cardColorHex
        self.onContextMenuPrepare = onContextMenuPrepare
        self.onContextCopy = onContextCopy
        self.onContextCut = onContextCut
        self.onContextPaste = onContextPaste
        self.onContextCloneCopy = onContextCloneCopy
        self.onContextDelete = onContextDelete
        self.onContextColorChange = onContextColorChange
        self.onSelectAtLocation = onSelectAtLocation
        self.onDoubleClick = onDoubleClick
        self.onTextChange = onTextChange
        self.onEndEdit = onEndEdit
        self.onTab = onTab
        self.onCommandEnter = onCommandEnter
        updateAppearance()
        if isEditing {
            applyEditSessionIfNeeded()
        } else {
            teardownEditSession()
        }
        needsLayout = true
    }

    func teardown() {
        teardownEditSession()
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
        textField.isHidden = isEditing
    }

    private func resolvedEditSession() -> MainWorkspaceEditSession {
        if let editSession {
            return editSession
        }
        let created = MainWorkspaceEditSession()
        editSession = created
        return created
    }

    private func applyEditSessionIfNeeded() {
        guard isEditing,
              let cardID else { return }

        let editSession = resolvedEditSession()
        editSession.onTextChange = { [weak self] oldValue, newValue in
            guard let self, self.cardID == cardID else { return }
            self.onTextChange?(oldValue, newValue)
        }
        editSession.onEndEditing = { [weak self] in
            guard let self, self.cardID == cardID else { return }
            self.onEndEdit?()
        }
        editSession.onTab = { [weak self] in
            guard let self, self.cardID == cardID else { return }
            self.onTab?()
        }
        editSession.onCommandEnter = { [weak self] in
            guard let self, self.cardID == cardID else { return }
            self.onCommandEnter?()
        }
        editSession.onFocusStateChange = { _ in }
        editSession.attach(to: self)
        editSession.setHidden(false)
        editSession.apply(
            configuration: MainWorkspaceEditSession.Configuration(
                cardID: cardID,
                text: text,
                activeEditorSessionID: activeEditorSessionID,
                textWidth: max(1, bounds.width - (MainEditorLayoutMetrics.mainEditorHorizontalPadding * 2)),
                bodyHeight: max(1, bounds.height - MainEditorLayoutMetrics.mainEditorVerticalInsets),
                fontSize: renderMetrics.fontSize,
                lineSpacing: renderMetrics.lineSpacing,
                appearance: editorAppearance,
                isFocused: true
            )
        )
    }

    private func teardownEditSession() {
        guard let editSession else {
            textField.isHidden = false
            return
        }
        editSession.teardown()
        self.editSession = nil
        textField.isHidden = false
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
