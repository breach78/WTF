import SwiftUI
import AppKit

extension IndexBoardSurfaceAppKitDocumentView {
    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseMoved(with event: NSEvent) {
        guard configuration.isInteractionEnabled else {
            clearHoverIndicator()
            return
        }
        updateHoverIndicator(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        guard configuration.isInteractionEnabled else { return }
        updateHoverIndicator(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        clearHoverIndicator()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard configuration.isInteractionEnabled else { return nil }

        let point = convert(event.locationInWindow, from: nil)
        let targetLaneChipParentCardID = editableParentCardID(at: point)
        let targetCardID = targetLaneChipParentCardID == nil ? cardID(at: point) : nil
        let menu = NSMenu()

        if !configuration.selectedCardIDs.isEmpty {
            let createParentItem = NSMenuItem(
                title: "선택 카드로 새 부모 만들기",
                action: #selector(handleCreateParentFromSelectionMenuAction),
                keyEquivalent: ""
            )
            createParentItem.target = self
            menu.addItem(createParentItem)
        }

        contextMenuCardID = targetCardID
        contextMenuParentCardID = targetLaneChipParentCardID
        contextMenuParentGroupIsTemp = targetLaneChipParentCardID.flatMap { parentCardID in
            interactionProjection.parentGroups.first(where: { $0.parentCardID == parentCardID })?.isTempGroup
        } ?? false

        if let targetCardID,
           let card = configuration.cardsByID[targetCardID] {
            if !menu.items.isEmpty {
                menu.addItem(NSMenuItem.separator())
            }
            menu.addItem(
                makeColorMenuItem(
                    title: "카드 색상",
                    currentHex: card.colorHex,
                    action: #selector(handleSetCardColorMenuAction(_:))
                )
            )
        } else if let parentCardID = contextMenuParentCardID {
            if !menu.items.isEmpty {
                menu.addItem(NSMenuItem.separator())
            }
            let titleItem = NSMenuItem(title: "그룹 테두리 색상", action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            menu.addItem(titleItem)
            appendColorItems(
                to: menu,
                currentHex: resolvedParentGroupColorHex(parentCardID: parentCardID),
                action: #selector(handleSetGroupColorMenuAction(_:))
            )
        }

        if let parentCardID = contextMenuParentCardID,
           parentCardID != configuration.surfaceProjection.source.parentID {
            if !menu.items.isEmpty {
                menu.addItem(NSMenuItem.separator())
            }
            let tempToggleItem = NSMenuItem(
                title: contextMenuParentGroupIsTemp ? "컬럼으로 복귀" : "Temp로 보내기",
                action: #selector(handleToggleParentGroupTempMenuAction),
                keyEquivalent: ""
            )
            tempToggleItem.target = self
            tempToggleItem.representedObject = parentCardID
            menu.addItem(tempToggleItem)
        }

        if let targetCardID {
            if !menu.items.isEmpty {
                menu.addItem(NSMenuItem.separator())
            }
            let deleteItem = NSMenuItem(
                title: "삭제",
                action: #selector(handleDeleteCardMenuAction),
                keyEquivalent: ""
            )
            deleteItem.target = self
            deleteItem.representedObject = targetCardID
            menu.addItem(deleteItem)
        } else if let parentCardID = contextMenuParentCardID,
                  canDeleteParentGroup(parentCardID: parentCardID) {
            if !menu.items.isEmpty {
                menu.addItem(NSMenuItem.separator())
            }
            let deleteItem = NSMenuItem(
                title: "삭제",
                action: #selector(handleDeleteParentGroupMenuAction),
                keyEquivalent: ""
            )
            deleteItem.target = self
            deleteItem.representedObject = parentCardID
            menu.addItem(deleteItem)
        }

        return menu.items.isEmpty ? nil : menu
    }

    override func rightMouseDown(with event: NSEvent) {
        guard configuration.isInteractionEnabled else {
            super.rightMouseDown(with: event)
            return
        }

        if let menu = menu(for: event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }

        super.rightMouseDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard configuration.isInteractionEnabled else {
            super.mouseDown(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if let inlineEditorScrollView,
           !inlineEditorScrollView.isHidden,
           inlineEditorScrollView.frame.contains(point),
           let textView = inlineEditorTextView {
            window?.makeFirstResponder(textView)
            textView.mouseDown(with: event)
            return
        }
        endInlineEditing(commit: true)
        let backgroundGridPosition = resolvedHoverGridPositionCandidate(at: point)
        clearHoverIndicator()
        if let parentCardID = editableParentCardID(at: point) {
            pendingGroupClick = (parentCardID, point)
            pendingCardClick = nil
            pendingBackgroundClickPoint = nil
            pendingBackgroundGridPosition = nil
            pendingBackgroundClickCount = 0
            selectionState = nil
            updateSelectionLayer()
            return
        }
        if let cardID = cardID(at: point) {
            pendingCardClick = (cardID, point, event.clickCount)
            pendingGroupClick = nil
            pendingBackgroundClickPoint = nil
            pendingBackgroundGridPosition = nil
            pendingBackgroundClickCount = 0
            selectionState = nil
            updateSelectionLayer()
            return
        }
        if let parentCardID = movableParentGroupID(at: point) {
            pendingGroupClick = (parentCardID, point)
            pendingCardClick = nil
            pendingBackgroundClickPoint = nil
            pendingBackgroundGridPosition = nil
            pendingBackgroundClickCount = 0
            selectionState = nil
            updateSelectionLayer()
            return
        }
        pendingBackgroundClickPoint = point
        pendingBackgroundGridPosition = backgroundGridPosition
        pendingBackgroundClickCount = event.clickCount
        pendingCardClick = nil
        pendingGroupClick = nil
        selectionState = nil
        updateSelectionLayer()
    }

    override func mouseDragged(with event: NSEvent) {
        guard configuration.isInteractionEnabled else {
            super.mouseDragged(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        clearHoverIndicator()
        if let pendingCardClick {
            if dragState == nil, pendingCardClick.point.distance(to: location) < IndexBoardSurfaceAppKitConstants.dragThreshold {
                return
            }
            if dragState == nil {
                beginDrag(cardID: pendingCardClick.cardID, pointer: location)
            }
            guard var dragState, dragState.cardID == pendingCardClick.cardID else { return }
            recordBaselineDragTick(autoScrolled: false) {
                let previousTarget = dragState.dropTarget
                dragState.pointerInContent = location
                dragState.dropTarget = recordBaselineTiming(\.resolvedDropTargetTiming) {
                    resolvedDropTarget(for: dragState)
                }
                applyCardDragUpdate(dragState, previousTarget: previousTarget)
            }
            return
        }
        if let pendingGroupClick {
            if groupDragState == nil, pendingGroupClick.point.distance(to: location) < IndexBoardSurfaceAppKitConstants.dragThreshold {
                return
            }
            if groupDragState == nil {
                beginGroupDrag(parentCardID: pendingGroupClick.parentCardID, pointer: location)
            }
            guard var groupDragState, groupDragState.parentCardID == pendingGroupClick.parentCardID else { return }
            recordBaselineDragTick(autoScrolled: false) {
                let previousOrigin = groupDragState.targetOrigin
                groupDragState.pointerInContent = location
                groupDragState.targetOrigin = resolvedGroupDragOrigin(for: groupDragState)
                applyGroupDragUpdate(groupDragState, previousOrigin: previousOrigin)
            }
            return
        }

        guard let startPoint = pendingBackgroundClickPoint else {
            super.mouseDragged(with: event)
            return
        }
        if selectionState == nil, startPoint.distance(to: location) < IndexBoardSurfaceAppKitConstants.dragThreshold {
            return
        }

        if selectionState == nil {
            selectionState = IndexBoardSurfaceAppKitSelectionState(startPoint: startPoint, currentPoint: location)
        } else {
            selectionState?.currentPoint = location
        }
        guard let selectionRect = normalizedSelectionRect() else { return }
        let selectedCardIDs = resolvedSelectedCardIDs(in: selectionRect)
        configuration.onMarqueeSelectionChange(selectedCardIDs)
        updateSelectionLayer()
    }

    override func mouseUp(with event: NSEvent) {
        guard configuration.isInteractionEnabled else {
            super.mouseUp(with: event)
            return
        }

        if let pendingCardClick {
            defer {
                self.pendingCardClick = nil
            }
            if dragState?.cardID == pendingCardClick.cardID {
                endDrag(cardID: pendingCardClick.cardID)
                return
            }
            guard let card = configuration.cardsByID[pendingCardClick.cardID] else { return }
            if event.clickCount == 2 {
                configuration.onCardOpen(card)
            } else {
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let disallowedModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
                let canEnterInlineEdit =
                    configuration.allowsInlineEditing &&
                    flags.intersection(disallowedModifiers).isEmpty &&
                    configuration.activeCardID == card.id &&
                    configuration.selectedCardIDs == Set([card.id])
                if canEnterInlineEdit {
                    beginInlineEditing(cardID: card.id)
                    return
                } else {
                    configuration.onCardTap(card)
                }
            }
            window?.makeFirstResponder(self)
            return
        }
        if let pendingGroupClick {
            defer {
                self.pendingGroupClick = nil
            }
            if groupDragState?.parentCardID == pendingGroupClick.parentCardID {
                endGroupDrag(parentCardID: pendingGroupClick.parentCardID)
                return
            }
            if event.clickCount == 2 {
                configuration.onParentCardOpen(pendingGroupClick.parentCardID)
                return
            }
        }

        if selectionState != nil {
            selectionState = nil
            updateSelectionLayer()
        } else if pendingBackgroundClickCount == 2 {
            configuration.onCreateTempCardAt(pendingBackgroundGridPosition)
        } else {
            configuration.onClearSelection()
        }

        pendingBackgroundClickPoint = nil
        pendingBackgroundGridPosition = nil
        pendingBackgroundClickCount = 0
        window?.makeFirstResponder(self)
        refreshHoverIndicatorFromCurrentMouse()
    }

    override func keyDown(with event: NSEvent) {
        guard configuration.isInteractionEnabled else {
            super.keyDown(with: event)
            return
        }

        if inlineEditingCardID != nil {
            super.keyDown(with: event)
            return
        }

        guard configuration.allowsInlineEditing,
              let cardID = resolvedInlineEditableCardID() else {
            super.keyDown(with: event)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasDisallowedModifier = flags.contains(.command) || flags.contains(.control) || flags.contains(.option)
        if hasDisallowedModifier {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 36 || event.keyCode == 76 {
            beginInlineEditing(cardID: cardID)
            return
        }

        guard let characters = event.characters,
              !characters.isEmpty,
              characters.unicodeScalars.contains(where: { !CharacterSet.controlCharacters.contains($0) }) else {
            super.keyDown(with: event)
            return
        }

        beginInlineEditing(cardID: cardID, seedEvent: event)
    }

    override func layout() {
        super.layout()
        guard !defersLayoutForLiveViewport else { return }
        let animationDuration = pendingLayoutAnimationDuration
        pendingLayoutAnimationDuration = 0
        applyCurrentLayout(animationDuration: animationDuration)
    }

    func consumeDeferredCommitLayoutRequest() -> Bool {
        let requested = requestsDeferredCommitLayout
        requestsDeferredCommitLayout = false
        return requested
    }

    func armMotionSceneCommitBridgeIfNeeded() {
        guard motionScene != nil else { return }
        keepsMotionSceneUntilCommittedLayout = true
    }

    func finishMotionSceneCommitBridgeIfNeeded() {
        guard keepsMotionSceneUntilCommittedLayout else { return }
        keepsMotionSceneUntilCommittedLayout = false
        endMotionScene()
    }

    func updateConfiguration(_ configuration: IndexBoardSurfaceAppKitConfiguration) {
        let nextRenderState = configuration.renderState
        let previousRenderState = lastRenderState
        self.configuration = configuration
        selectionLayer.fillColor = indexBoardThemeAccentColor(theme: configuration.theme)
            .withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.14 : 0.10).cgColor
        selectionLayer.strokeColor = indexBoardThemeAccentColor(theme: configuration.theme)
            .withAlphaComponent(0.82).cgColor
        if !configuration.allowsInlineEditing {
            endInlineEditing(commit: true)
        } else if let inlineEditingCardID,
                  configuration.cardsByID[inlineEditingCardID] == nil {
            endInlineEditing(commit: false)
        }
        guard nextRenderState != lastRenderState else { return }
        let layoutDiff = resolvedLayoutDiff(
            from: previousRenderState,
            to: nextRenderState
        )
        shouldSkipCardViewReconcileForNextLayout = canReuseCardViews(
            from: previousRenderState,
            to: nextRenderState
        )
        partialLaneKeysForNextLayout =
            shouldSkipCardViewReconcileForNextLayout ? layoutDiff.affectedLaneKeys : nil
        let highlightedCardIDs = previousRenderState.selectedCardIDs
            .union(nextRenderState.selectedCardIDs)
            .union(previousRenderState.activeCardID.map { Set([$0]) } ?? Set<UUID>())
            .union(nextRenderState.activeCardID.map { Set([$0]) } ?? Set<UUID>())
        shouldSkipIndicatorRefreshForNextLayout =
            shouldSkipCardViewReconcileForNextLayout &&
            previousRenderState.activeCardID == nextRenderState.activeCardID &&
            previousRenderState.selectedCardIDs == nextRenderState.selectedCardIDs &&
            layoutDiff.changedCardIDs.isDisjoint(with: highlightedCardIDs) &&
            (highlightedCardIDs.isEmpty || !focusIndicatorLayers.isEmpty)
        lastRenderState = nextRenderState
        reconcilePresentationProjection()
        needsLayout = true
    }

    func updateConfigurationForViewportOnly(_ configuration: IndexBoardSurfaceAppKitConfiguration) {
        self.configuration = configuration
        self.lastRenderState = configuration.renderState
        shouldSkipCardViewReconcileForNextLayout = false
        partialLaneKeysForNextLayout = nil
        shouldSkipIndicatorRefreshForNextLayout = false
    }

    func refreshDisplayAfterLiveMagnify() {
        let contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = contentsScale
        startAnchorTextLayer.contentsScale = contentsScale
        needsDisplay = true

        for cardView in cardViews.values {
            cardView.layer?.contentsScale = contentsScale
            cardView.needsDisplay = true
        }

        for chipView in laneChipViews.values {
            chipView.layer?.contentsScale = contentsScale
            chipView.needsDisplay = true
        }

        displayIfNeeded()
    }

    @objc
    func handleCreateParentFromSelectionMenuAction() {
        guard !configuration.selectedCardIDs.isEmpty else { return }
        configuration.onCreateParentFromSelection()
    }

    @objc
    func handleToggleParentGroupTempMenuAction() {
        guard let parentCardID = contextMenuParentCardID else { return }
        configuration.onSetParentGroupTemp(parentCardID, !contextMenuParentGroupIsTemp)
    }

    @objc
    func handleSetCardColorMenuAction(_ sender: NSMenuItem) {
        guard let cardID = contextMenuCardID else { return }
        configuration.onSetCardColor(cardID, resolvedContextMenuColorHex(from: sender.representedObject))
        refreshColorDependentPresentation()
    }

    @objc
    func handleSetGroupColorMenuAction(_ sender: NSMenuItem) {
        guard let parentCardID = contextMenuParentCardID else { return }
        configuration.onSetCardColor(parentCardID, resolvedContextMenuColorHex(from: sender.representedObject))
        refreshColorDependentPresentation()
    }

    @objc
    func handleDeleteCardMenuAction() {
        guard let cardID = contextMenuCardID else { return }
        configuration.onDeleteCard(cardID)
    }

    @objc
    func handleDeleteParentGroupMenuAction() {
        guard let parentCardID = contextMenuParentCardID,
              canDeleteParentGroup(parentCardID: parentCardID) else { return }
        configuration.onDeleteParentGroup(parentCardID)
    }

    func ensureCardVisible(_ cardID: UUID?) {
        guard let cardID,
              let rect = cardFrameByID[cardID] else { return }
        scrollView?.contentView.scrollToVisible(rect.insetBy(dx: -36, dy: -28))
        scrollView?.reflectScrolledClipView(scrollView!.contentView)
    }

    var isInteractingLocally: Bool {
        dragState != nil || groupDragState != nil
    }

    func refreshHoverIndicatorFromCurrentMouse() {
        guard configuration.isInteractionEnabled,
              !isHoverIndicatorSuppressed,
              dragState == nil,
              groupDragState == nil,
              selectionState == nil,
              let scrollView,
              let window else {
            clearHoverIndicator()
            return
        }
        let pointerInWindow = window.mouseLocationOutsideOfEventStream
        let pointerInScrollView = scrollView.convert(pointerInWindow, from: nil)
        guard scrollView.bounds.contains(pointerInScrollView) else {
            clearHoverIndicator()
            return
        }
        updateHoverIndicator(at: convert(pointerInWindow, from: nil))
    }

    func setHoverIndicatorSuppressed(_ suppressed: Bool) {
        isHoverIndicatorSuppressed = suppressed
        if suppressed {
            clearHoverIndicator()
        }
    }

    func handleCardMouseDown(cardID: UUID, event: NSEvent, in view: NSView) {
        guard configuration.isInteractionEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)
        pendingCardClick = (cardID, point, event.clickCount)
        pendingBackgroundClickPoint = nil
        pendingBackgroundGridPosition = nil
        pendingBackgroundClickCount = 0
    }

    func handleCardMouseDragged(cardID: UUID, event: NSEvent, in view: NSView) {
        guard configuration.isInteractionEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)

        if dragState == nil {
            guard let pendingCardClick, pendingCardClick.cardID == cardID else { return }
            if pendingCardClick.point.distance(to: point) < IndexBoardSurfaceAppKitConstants.dragThreshold {
                return
            }
            beginDrag(cardID: cardID, pointer: point)
        }

        guard var dragState, dragState.cardID == cardID else { return }
        recordBaselineDragTick(autoScrolled: false) {
            let previousTarget = dragState.dropTarget
            dragState.pointerInContent = point
            dragState.dropTarget = recordBaselineTiming(\.resolvedDropTargetTiming) {
                resolvedDropTarget(for: dragState)
            }
            applyCardDragUpdate(dragState, previousTarget: previousTarget)
        }
    }

    func handleCardMouseUp(cardID: UUID, event: NSEvent, in view: NSView) {
        guard configuration.isInteractionEnabled else { return }
        defer {
            pendingCardClick = nil
        }

        if dragState?.cardID == cardID {
            endDrag(cardID: cardID)
            return
        }

        guard let card = configuration.cardsByID[cardID] else { return }
        if event.clickCount == 2 {
            configuration.onCardOpen(card)
        } else {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let disallowedModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            let canEnterInlineEdit =
                configuration.allowsInlineEditing &&
                flags.intersection(disallowedModifiers).isEmpty &&
                configuration.activeCardID == card.id &&
                configuration.selectedCardIDs == Set([card.id])
            if canEnterInlineEdit {
                beginInlineEditing(cardID: card.id)
                return
            } else {
                configuration.onCardTap(card)
            }
        }
        window?.makeFirstResponder(self)
    }

}

extension IndexBoardSurfaceAppKitDocumentView {
    func menuForLaneChip(parentCardID: UUID, event: NSEvent, in view: NSView) -> NSMenu? {
        guard configuration.isInteractionEnabled else { return nil }
        contextMenuCardID = nil
        contextMenuParentCardID = parentCardID
        contextMenuParentGroupIsTemp = contextMenuParentCardID.flatMap { resolvedParentCardID in
            interactionProjection.parentGroups.first(where: { $0.parentCardID == resolvedParentCardID })?.isTempGroup
        } ?? false

        let menu = NSMenu()
        if let parentCardID = contextMenuParentCardID {
            let titleItem = NSMenuItem(title: "그룹 테두리 색상", action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            menu.addItem(titleItem)
            appendColorItems(
                to: menu,
                currentHex: resolvedParentGroupColorHex(parentCardID: parentCardID),
                action: #selector(handleSetGroupColorMenuAction(_:))
            )
        }
        if let parentCardID = contextMenuParentCardID,
           parentCardID != configuration.surfaceProjection.source.parentID {
            if !menu.items.isEmpty {
                menu.addItem(NSMenuItem.separator())
            }
            let tempToggleItem = NSMenuItem(
                title: contextMenuParentGroupIsTemp ? "컬럼으로 복귀" : "Temp로 보내기",
                action: #selector(handleToggleParentGroupTempMenuAction),
                keyEquivalent: ""
            )
            tempToggleItem.target = self
            tempToggleItem.representedObject = parentCardID
            menu.addItem(tempToggleItem)
        }
        if canDeleteParentGroup(parentCardID: parentCardID) {
            if !menu.items.isEmpty {
                menu.addItem(NSMenuItem.separator())
            }
            let deleteItem = NSMenuItem(
                title: "삭제",
                action: #selector(handleDeleteParentGroupMenuAction),
                keyEquivalent: ""
            )
            deleteItem.target = self
            deleteItem.representedObject = parentCardID
            menu.addItem(deleteItem)
        }
        return menu.items.isEmpty ? nil : menu
    }

    func handleLaneChipMouseDown(parentCardID: UUID, event: NSEvent, in view: NSView) {
        guard configuration.isInteractionEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)
        clearHoverIndicator()
        pendingGroupClick = (parentCardID, point)
        pendingCardClick = nil
        pendingBackgroundClickPoint = nil
        pendingBackgroundGridPosition = nil
        pendingBackgroundClickCount = 0
        selectionState = nil
        updateSelectionLayer()
    }

    func handleLaneChipMouseDragged(parentCardID: UUID, event: NSEvent, in view: NSView) {
        guard configuration.isInteractionEnabled else { return }
        let location = convert(event.locationInWindow, from: nil)
        clearHoverIndicator()
        guard let pendingGroupClick, pendingGroupClick.parentCardID == parentCardID else { return }
        if groupDragState == nil, pendingGroupClick.point.distance(to: location) < IndexBoardSurfaceAppKitConstants.dragThreshold {
            return
        }
        if groupDragState == nil {
            beginGroupDrag(parentCardID: pendingGroupClick.parentCardID, pointer: location)
        }
        guard var groupDragState, groupDragState.parentCardID == pendingGroupClick.parentCardID else { return }
        recordBaselineDragTick(autoScrolled: false) {
            let previousOrigin = groupDragState.targetOrigin
            groupDragState.pointerInContent = location
            groupDragState.targetOrigin = resolvedGroupDragOrigin(for: groupDragState)
            applyGroupDragUpdate(groupDragState, previousOrigin: previousOrigin)
        }
    }

    func handleLaneChipMouseUp(parentCardID: UUID, event: NSEvent, in view: NSView) {
        guard configuration.isInteractionEnabled else { return }
        defer { pendingGroupClick = nil }

        if groupDragState?.parentCardID == parentCardID {
            endGroupDrag(parentCardID: parentCardID)
            return
        }

        if event.clickCount == 2 {
            configuration.onParentCardOpen(parentCardID)
        }
    }

}
