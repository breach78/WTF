import SwiftUI
import AppKit

fileprivate enum FocusSelectionActiveEdge {
    case start
    case end
}
fileprivate var _focusSelectionActiveEdge: FocusSelectionActiveEdge = .end

extension ScenarioWriterView {

    private var focusTypewriterEnabledLive: Bool {
        if let stored = UserDefaults.standard.object(forKey: "focusTypewriterEnabled") as? Bool {
            return stored
        }
        return focusTypewriterEnabled
    }

    private var isReferenceWindowFocused: Bool {
        NSApp.keyWindow?.identifier?.rawValue == ReferenceWindowConstants.windowID
    }

    private func isReferenceTextView(_ textView: NSTextView) -> Bool {
        textView.window?.identifier?.rawValue == ReferenceWindowConstants.windowID
    }

    private var focusModeCardsBackgroundColor: Color {
        let fallbackLight = (r: 0.75, g: 0.84, b: 1.0)
        let fallbackDark = (r: 0.16, g: 0.23, b: 0.31)
        let hex = isDarkAppearanceActive ? darkCardActiveColorHex : cardActiveColorHex
        if let rgb = rgbFromHex(hex) {
            return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
        }
        let fallback = isDarkAppearanceActive ? fallbackDark : fallbackLight
        return Color(red: fallback.r, green: fallback.g, blue: fallback.b)
    }

    @ViewBuilder
    func focusModeCanvas(size: CGSize) -> some View {
        let cards = focusedColumnCards()
        ZStack {
            focusModeCanvasBackdrop()
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    focusModeCanvasScrollContent(size: size, cards: cards)
                }
                .onChange(of: activeCardID) { _, newID in
                    handleFocusModeCanvasActiveCardChange(newID, proxy: proxy)
                }
                .onChange(of: focusModeEntryScrollTick) { _, _ in
                    handleFocusModeEntryScrollTickChange(proxy: proxy)
                }
            }
        }
        .coordinateSpace(name: "focus-mode-canvas")
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: size.width) { oldWidth, newWidth in
            handleFocusModeCanvasWidthChange(oldWidth: oldWidth, newWidth: newWidth)
        }
    }

    @ViewBuilder
    private func focusModeCanvasBackdrop() -> some View {
        Color.black.opacity(0.90)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                guard showFocusMode else { return }
                toggleFocusMode()
            }
    }

    @ViewBuilder
    private func focusModeCanvasScrollContent(size: CGSize, cards: [SceneCard]) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: max(48, size.height * 0.08))
            focusModeCardsColumn(cards: cards)
            Color.clear.frame(height: max(72, size.height * 0.12))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func focusModeCardsColumn(cards: [SceneCard]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                focusModeCardBlock(card)
                    .id(focusModeCardScrollID(card.id))
                if index < cards.count - 1 {
                    focusModeCardDivider(card: card, nextCard: cards[index + 1])
                }
            }
        }
        .background(focusModeCardsBackgroundColor)
        .overlay(Rectangle().stroke(focusModeCardsBorderColor, lineWidth: 1))
        .frame(maxWidth: 916)
        .padding(.horizontal, 32)
    }

    @ViewBuilder
    private func focusModeCardDivider(card: SceneCard, nextCard: SceneCard) -> some View {
        let parentChanged = card.parent?.id != nextCard.parent?.id
        Rectangle()
            .fill(
                parentChanged
                ? Color(hue: 0.61, saturation: 0.5, brightness: 0.95).opacity(0.85)
                : (appearance == "light" ? Color.black.opacity(0.08) : Color.white.opacity(0.12))
            )
            .frame(height: parentChanged ? 2 : 1)
            .padding(.horizontal, parentChanged ? 20 : 0)
    }

    private var focusModeCardsBorderColor: Color {
        appearance == "light" ? Color.black.opacity(0.10) : Color.white.opacity(0.12)
    }

    private func focusModeCardScrollID(_ cardID: UUID) -> String {
        "focus-card-\(cardID)"
    }

    private func handleFocusModeCanvasActiveCardChange(_ newID: UUID?, proxy: ScrollViewProxy) {
        guard let id = newID else { return }
        focusResponderCardByObjectID.removeAll()
        let matchesPendingProgrammaticBegin = consumePendingFocusModeProgrammaticBeginMatch(for: id)
        if handleFocusModeSuppressedScrollIfNeeded(
            id: id,
            matchesPendingProgrammaticBegin: matchesPendingProgrammaticBegin
        ) {
            return
        }
        performFocusModeCanvasActiveCardScroll(id: id, proxy: proxy)
        applyFocusModeCanvasActiveCardEditorState(id: id)
        scheduleFocusModeCanvasActiveCardBeginEditingIfNeeded(id: id)
        scheduleFocusModeOffsetNormalizationBurst(includeActive: false)
    }

    private func consumePendingFocusModeProgrammaticBeginMatch(for id: UUID) -> Bool {
        let matchesPendingProgrammaticBegin = (focusPendingProgrammaticBeginEditCardID == id)
        if matchesPendingProgrammaticBegin {
            focusPendingProgrammaticBeginEditCardID = nil
        }
        return matchesPendingProgrammaticBegin
    }

    private func handleFocusModeSuppressedScrollIfNeeded(
        id: UUID,
        matchesPendingProgrammaticBegin: Bool
    ) -> Bool {
        guard suppressFocusModeScrollOnce else { return false }
        suppressFocusModeScrollOnce = false
        if matchesPendingProgrammaticBegin {
            if showFocusMode {
                focusModeEditorCardID = id
            }
            return true
        }
        if showFocusMode, let card = findCard(by: id) {
            beginFocusModeEditing(
                card,
                cursorToEnd: false,
                animatedScroll: false,
                preserveViewportOnSwitch: true,
                placeCursorAtStartWhenNoHint: false
            )
        } else if showFocusMode {
            focusModeEditorCardID = id
        }
        return true
    }

    private func performFocusModeCanvasActiveCardScroll(id: UUID, proxy: ScrollViewProxy) {
        requestFocusModeOffsetNormalization(includeActive: false, force: true, reason: "active-card-change")
        let anchor = focusModeNextCardScrollAnchor ?? .center
        let shouldAnimate = focusModeNextCardScrollAnimated
        focusModeNextCardScrollAnchor = nil
        focusModeNextCardScrollAnimated = true
        if shouldAnimate {
            withAnimation(quickEaseAnimation) {
                proxy.scrollTo(focusModeCardScrollID(id), anchor: anchor)
            }
        } else {
            proxy.scrollTo(focusModeCardScrollID(id), anchor: anchor)
        }
    }

    private func applyFocusModeCanvasActiveCardEditorState(id: UUID) {
        if showFocusMode {
            focusModeEditorCardID = id
        }
    }

    private func scheduleFocusModeCanvasActiveCardBeginEditingIfNeeded(id: UUID) {
        if showFocusMode, editingCardID != id, let card = findCard(by: id) {
            DispatchQueue.main.async {
                beginFocusModeEditing(card, cursorToEnd: false)
            }
        }
    }

    private func handleFocusModeEntryScrollTickChange(proxy: ScrollViewProxy) {
        guard showFocusMode else { return }
        guard let id = activeCardID else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(focusModeCardScrollID(id), anchor: .center)
        }
    }

    private func handleFocusModeCanvasWidthChange(oldWidth: CGFloat, newWidth: CGFloat) {
        guard showFocusMode else { return }
        let widthChanged = abs(newWidth - oldWidth) > 0.5
        if widthChanged {
            focusObservedBodyHeightByCardID.removeAll()
            requestFocusModeOffsetNormalization(includeActive: false, force: true, reason: "canvas-width-change")
        }
    }

    @ViewBuilder
    func focusModeCardBlock(_ card: SceneCard) -> some View {
        let isActiveCard = activeCardID == card.id
        let isCloneLinked = scenario.isCardCloned(card.id)
        FocusModeCardEditor(
            card: card,
            isActive: isActiveCard,
            fontSize: fontSize,
            appearance: appearance,
            horizontalInset: FocusModeLayoutMetrics.focusModeHorizontalPadding,
            observedBodyHeight: focusObservedBodyHeightByCardID[card.id],
            focusModeEditorCardID: $focusModeEditorCardID,
            onActivate: { activateFocusModeCardFromClick(card) },
            onContentChange: { oldValue, newValue in
                handleFocusModeCardContentChange(cardID: card.id, oldValue: oldValue, newValue: newValue)
            }
        )
        .overlay(alignment: .topLeading) {
            if isCloneLinked {
                Rectangle()
                    .fill(appearance == "light" ? Color.black.opacity(0.48) : Color.white.opacity(0.85))
                    .frame(width: 8, height: 8)
                    .allowsHitTesting(false)
            }
        }
    }

    func activateFocusModeCardFromClick(_ card: SceneCard) {
        if splitModeEnabled && !isSplitPaneActive {
            activateSplitPaneIfNeeded()
        }
        let clickCaretLocation = resolveFocusModeClickCaretLocation(for: card)
        
        // Click-to-activate should preserve the system-calculated click caret.
        // Do not reuse pending hint from previous transitions.
        pendingFocusModeEntryCaretHint = nil
        clearFocusDeleteSelectionLock()
        if activeCardID != card.id {
            beginFocusModeEditing(
                card,
                cursorToEnd: false,
                animatedScroll: false,
                preserveViewportOnSwitch: true,
                placeCursorAtStartWhenNoHint: false,
                allowPendingEntryCaretHint: false,
                explicitCaretLocation: clickCaretLocation
            )
        } else {
            selectedCardIDs = [card.id]
            if editingCardID != card.id {
                editingCardID = card.id
                editingStartContent = card.content
                editingStartState = captureScenarioState()
                editingIsNewCard = false
            }
            focusModeEditorCardID = card.id
        }
        // Keep click-insert caret untouched by avoiding forced cursor relocation.
    }

    func resolveFocusModeClickCaretLocation(for card: SceneCard) -> Int? {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return nil }
        let responderID = ObjectIdentifier(textView)
        let mappedCardID = focusResponderCardByObjectID[responderID]
        let belongsToTarget = mappedCardID == card.id || textView.string == card.content
        guard belongsToTarget else { return nil }
        guard let window = textView.window else { return nil }
        let screenPoint = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let localPoint = textView.convert(windowPoint, from: nil)
        let rawIndex = textView.characterIndexForInsertion(at: localPoint)
        let length = (textView.string as NSString).length
        let safeIndex = max(0, min(rawIndex, length))
        return safeIndex
    }

    func focusedColumnCards() -> [SceneCard] {
        let levelsData = resolvedLevelsWithParents()
        guard let activeID = activeCardID else {
            return levelsData.first?.cards ?? []
        }
        guard let index = levelsData.firstIndex(where: { data in
            data.cards.contains(where: { $0.id == activeID })
        }) else {
            return levelsData.first?.cards ?? []
        }
        let data = levelsData[index]
        let filtered = (index <= 1 || isActiveCardRoot) ? data.cards : data.cards.filter { $0.category == activeCategory }
        return filtered
    }

    func startFocusModeKeyMonitor() {
        if focusModeKeyMonitor != nil { return }
        focusModeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleFocusModeKeyDown(event)
        }
    }

    func handleFocusModeKeyDown(_ event: NSEvent) -> NSEvent? {
        if shouldPassThroughFocusModeEvent(event) { return event }
        if showCloneCardPasteDialog {
            _ = handleClonePasteDialogKeyDownEvent(event)
            return nil
        }
        if handleFocusDeleteAlertShortcutIfNeeded(event) { return nil }

        let flags = event.modifierFlags
        if handleFocusEscapeShortcut(event, flags: flags) { return nil }
        if handleFocusCardEditingShortcuts(event, flags: flags) { return nil }
        if shouldPassThroughAfterFocusReturnBoundaryUpdate(event, flags: flags) { return event }
        if shouldPassThroughFocusModeModifierEvent(flags) { return event }
        if handleFocusTypewriterCaretShortcut(event) { return event }
        if !isFocusModeVerticalArrowKey(event) { return event }
        return handleFocusModeArrowNavigation(event)
    }

    private func handleFocusEscapeShortcut(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        guard isPlainFocusEscape(event, flags: flags) else { return false }
        DispatchQueue.main.async {
            toggleFocusMode()
        }
        return true
    }

    private func handleFocusCardEditingShortcuts(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        let isCommandOnly = isCommandOnlyFlags(flags)
        let isCommandShift = isCommandShiftFlags(flags)
        if handleFocusTypewriterToggleShortcut(event, isCommandShift: isCommandShift) { return true }
        if handleFocusDeleteShortcut(event, isCommandShift: isCommandShift) { return true }
        if handleFocusInsertSiblingShortcut(event, isCommandOnly: isCommandOnly) { return true }
        if handleFocusOptionArrowSiblingShortcut(event, flags: flags) { return true }
        return false
    }

    private func shouldPassThroughAfterFocusReturnBoundaryUpdate(
        _ event: NSEvent,
        flags: NSEvent.ModifierFlags
    ) -> Bool {
        handleFocusReturnBoundaryState(event, flags: flags)
    }

    private func shouldPassThroughFocusModeModifierEvent(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.command) || flags.contains(.option) || flags.contains(.control)
    }

    private func isFocusModeVerticalArrowKey(_ event: NSEvent) -> Bool {
        event.keyCode == 126 || event.keyCode == 125
    }

    func shouldPassThroughFocusModeEvent(_ event: NSEvent) -> Bool {
        let isReferenceWindowEvent = event.window?.identifier?.rawValue == ReferenceWindowConstants.windowID
        let isReferenceWindowKey = NSApp.keyWindow?.identifier?.rawValue == ReferenceWindowConstants.windowID
        if isReferenceWindowEvent || isReferenceWindowKey {
            return true
        }
        return !acceptsKeyboardInput || !showFocusMode
    }

    func handleFocusDeleteAlertShortcutIfNeeded(_ event: NSEvent) -> Bool {
        guard showDeleteAlert else { return false }
        let hasChildren = selectedCardsForDeletion().contains { !$0.children.isEmpty }
        let isEscape = event.keyCode == 53
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        guard isEscape || (hasChildren && isReturn) else { return false }
        DispatchQueue.main.async {
            showDeleteAlert = false
            isMainViewFocused = true
        }
        return true
    }

    func isPlainFocusEscape(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        event.keyCode == 53 &&
        !flags.contains(.command) &&
        !flags.contains(.option) &&
        !flags.contains(.control) &&
        !flags.contains(.shift)
    }

    func isCommandOnlyFlags(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.command) &&
        !flags.contains(.option) &&
        !flags.contains(.control) &&
        !flags.contains(.shift)
    }

    func isCommandShiftFlags(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.command) &&
        flags.contains(.shift) &&
        !flags.contains(.option) &&
        !flags.contains(.control)
    }

    func handleFocusTypewriterToggleShortcut(_ event: NSEvent, isCommandShift: Bool) -> Bool {
        guard isCommandShift else { return false }
        let normalized = (event.charactersIgnoringModifiers ?? "").lowercased()
        guard normalized == "t" || normalized == "ㅅ" || normalized == "ㅆ" else { return false }
        DispatchQueue.main.async {
            focusTypewriterEnabled = !focusTypewriterEnabledLive
        }
        return true
    }

    func handleFocusDeleteShortcut(_ event: NSEvent, isCommandShift: Bool) -> Bool {
        guard isCommandShift else { return false }
        guard event.keyCode == 51 || event.keyCode == 117 else { return false } // delete / forward-delete
        if event.isARepeat { return true }
        DispatchQueue.main.async {
            if let targetID = focusModeEditorCardID ?? editingCardID ?? activeCardID {
                selectedCardIDs = [targetID]
                if let target = findCard(by: targetID), activeCardID != targetID {
                    changeActiveCard(to: target, shouldFocusMain: false)
                }
            }
            deleteSelectedCard()
        }
        return true
    }

    func handleFocusInsertSiblingShortcut(_ event: NSEvent, isCommandOnly: Bool) -> Bool {
        guard isCommandOnly else { return false }
        guard event.keyCode == 36 || event.keyCode == 76 else { return false } // return / keypad enter
        if event.isARepeat { return true }
        DispatchQueue.main.async {
            insertSibling(above: false)
        }
        return true
    }

    func handleFocusOptionArrowSiblingShortcut(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        let isCommandOption = flags.contains(.command) && flags.contains(.option) && !flags.contains(.control)
        guard isCommandOption else { return false }
        guard event.keyCode == 126 || event.keyCode == 125 else { return false } // up / down
        if event.isARepeat { return true }
        let createAbove = event.keyCode == 126
        DispatchQueue.main.async {
            insertSibling(above: createAbove)
        }
        return true
    }

    func handleFocusReturnBoundaryState(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        guard event.keyCode == 36 || event.keyCode == 76 else { return false } // return / keypad enter
        let isPlainReturn = !flags.contains(.command) && !flags.contains(.option) && !flags.contains(.control)
        if isPlainReturn,
           let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            let text = textView.string as NSString
            let caret = min(max(0, textView.selectedRange().location), text.length)
            focusPendingReturnBoundary = lineHasSignificantContentBeforeBreak(in: text, breakIndex: caret)
        } else if !isPlainReturn {
            focusPendingReturnBoundary = false
        }
        return true
    }

    func handleFocusTypewriterCaretShortcut(_ event: NSEvent) -> Bool {
        guard focusTypewriterEnabledLive else { return false }
        guard isTypewriterTriggerKey(event) else { return false }
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView, textView.hasMarkedText() {
            focusTypewriterDeferredUntilCompositionEnd = true
            return true
        }
        DispatchQueue.main.async {
            requestFocusModeCaretEnsure(typewriter: true, delay: 0.02, reason: "typewriter-key")
        }
        return true
    }

    func handleFocusModeArrowNavigation(_ event: NSEvent) -> NSEvent? {
        guard let currentID = focusModeEditorCardID ?? editingCardID,
              let currentCard = findCard(by: currentID) else { return event }
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
            focusModeEditorCardID = currentID
            return nil
        }

        let cards = focusedColumnCards()
        guard let currentIndex = cards.firstIndex(where: { $0.id == currentID }) else { return event }
        let boundary = focusModeArrowBoundaryState(
            event: event,
            currentCard: currentCard,
            currentIndex: currentIndex,
            cards: cards,
            textView: textView
        )
        guard boundary.isBoundary else {
            consumeFocusModeArrowNavigationWithoutBoundary()
            return event
        }
        if event.isARepeat { return nil }

        performFocusModeArrowBoundaryTransition(
            isUpKey: boundary.isUpKey,
            cards: cards,
            currentIndex: currentIndex,
            textView: textView
        )
        return nil
    }

    private func focusModeArrowBoundaryState(
        event: NSEvent,
        currentCard: SceneCard,
        currentIndex: Int,
        cards: [SceneCard],
        textView: NSTextView
    ) -> (isUpKey: Bool, isBoundary: Bool) {
        let cursor = textView.selectedRange().location
        let length = (currentCard.content as NSString).length
        let visualBoundary = focusCaretVisualBoundaryState(textView: textView, cursor: cursor)
        let atTopBoundary = (cursor == 0) && (visualBoundary?.isTop ?? true)
        let atBottomBoundary = (cursor == length) && (visualBoundary?.isBottom ?? true)
        let isUpKey = event.keyCode == 126
        let isBoundary = isUpKey
            ? (atTopBoundary && currentIndex > 0)
            : (atBottomBoundary && currentIndex < cards.count - 1)
        return (isUpKey, isBoundary)
    }

    private func consumeFocusModeArrowNavigationWithoutBoundary() {
        clearFocusBoundaryArm()
        // Cancel deferred boundary caret applies once user continues in-card navigation.
        focusModeCaretRequestID += 1
    }

    private func performFocusModeArrowBoundaryTransition(
        isUpKey: Bool,
        cards: [SceneCard],
        currentIndex: Int,
        textView: NSTextView
    ) {
        clearFocusBoundaryArm()
        let target = isUpKey ? cards[currentIndex - 1] : cards[currentIndex + 1]
        focusExcludedResponderObjectID = ObjectIdentifier(textView)
        focusExcludedResponderUntil = Date().addingTimeInterval(0.10)
        // Invalidate any pending caret applies from a previous transition before scheduling a new one.
        focusModeCaretRequestID += 1
        DispatchQueue.main.async {
            beginFocusModeEditing(
                target,
                cursorToEnd: isUpKey,
                preserveViewportOnSwitch: true
            )
        }
    }

    func isTypewriterTriggerKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 36 || event.keyCode == 76 { // return, keypad enter
            return true
        }
        let blocked: Set<UInt16> = [48, 51, 117, 53, 123, 124, 125, 126, 115, 119, 116, 121]
        if blocked.contains(event.keyCode) { return false }
        guard let characters = event.characters, !characters.isEmpty else { return false }
        let onlyControl = characters.unicodeScalars.allSatisfy { CharacterSet.controlCharacters.contains($0) }
        return !onlyControl
    }

    func clearFocusBoundaryArm() {
        // Boundary arm is intentionally a no-op now: focus mode card jump occurs on first key press.
    }

    func stopFocusModeKeyMonitor() {
        clearFocusBoundaryArm()
        if let monitor = focusModeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            focusModeKeyMonitor = nil
        }
    }

    func startFocusModeScrollMonitor() {
        if focusModeScrollMonitor != nil { return }

        var monitors: [Any] = []
        if let eventMonitor = createFocusModeScrollWheelMonitor() {
            monitors.append(eventMonitor)
        }
        monitors.append(createFocusModeBoundsObserver())
        focusModeScrollMonitor = monitors
    }

    private func createFocusModeScrollWheelMonitor() -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            handleFocusModeScrollWheelEvent(event)
        }
    }

    private func handleFocusModeScrollWheelEvent(_ event: NSEvent) -> NSEvent? {
        guard acceptsKeyboardInput else { return event }
        guard showFocusMode else { return event }
        let shouldNormalize = event.phase == .ended || event.momentumPhase == .ended
        if shouldNormalize {
            DispatchQueue.main.async {
                requestFocusModeOffsetNormalization(reason: "scroll-ended")
            }
        }
        return event
    }

    private func createFocusModeBoundsObserver() -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: nil,
            queue: .main
        ) { notification in
            handleFocusModeBoundsDidChange(notification)
        }
    }

    private func handleFocusModeBoundsDidChange(_ notification: Notification) {
        guard acceptsKeyboardInput else { return }
        guard showFocusMode else { return }
        guard let clipView = notification.object as? NSClipView else { return }
        let origin = clipView.bounds.origin
        guard abs(origin.x) > 0.5 || abs(origin.y) > 0.5 else { return }
        guard let scrollView = clipView.superview as? NSScrollView else { return }
        guard isFocusModeInternalTextEditorScrollView(scrollView) else { return }

        // Block TextEditor internal jolt scroll by forcing inner clip origin to zero.
        clipView.setBoundsOrigin(.zero)
    }

    private func isFocusModeInternalTextEditorScrollView(_ scrollView: NSScrollView) -> Bool {
        guard scrollView.documentView is NSTextView else { return false }
        return !scrollView.hasVerticalScroller &&
            !scrollView.hasHorizontalScroller &&
            !scrollView.drawsBackground
    }

    func stopFocusModeScrollMonitor() {
        if let monitors = focusModeScrollMonitor as? [Any] {
            if let eventMonitor = monitors.first {
                NSEvent.removeMonitor(eventMonitor)
            }
            if monitors.count > 1, let boundsObserver = monitors[1] as? NSObjectProtocol {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
        } else if let monitor = focusModeScrollMonitor {
            NSEvent.removeMonitor(monitor)
        }
        focusModeScrollMonitor = nil
    }

    func focusModeTargetContainerWidth(for textView: NSTextView) -> CGFloat {
        let viewportWidth = textView.enclosingScrollView?.contentView.bounds.width ?? textView.bounds.width
        return max(1, viewportWidth)
    }

    @discardableResult
    func applyFocusModeTextViewGeometryIfNeeded(_ textView: NSTextView, reason: String = "focus-mode") -> Bool {
        guard showFocusMode else { return false }
        var changed = false
        changed = applyFocusModeTextViewSizingIfNeeded(textView) || changed
        if let scrollView = textView.enclosingScrollView {
            changed = applyFocusModeInnerScrollViewGeometryIfNeeded(scrollView) || changed
        }
        if textView.textContainerInset != .zero {
            textView.textContainerInset = .zero
            changed = true
        }
        changed = applyFocusModeTextContainerGeometryIfNeeded(textView) || changed
        _ = reason
        return changed
    }

    private func applyFocusModeTextViewSizingIfNeeded(_ textView: NSTextView) -> Bool {
        var changed = false
        if textView.isHorizontallyResizable {
            textView.isHorizontallyResizable = false
            changed = true
        }
        if !textView.isVerticallyResizable {
            textView.isVerticallyResizable = true
            changed = true
        }
        if textView.minSize != .zero {
            textView.minSize = .zero
            changed = true
        }
        let maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        if textView.maxSize != maxSize {
            textView.maxSize = maxSize
            changed = true
        }
        return changed
    }

    private func applyFocusModeInnerScrollViewGeometryIfNeeded(_ scrollView: NSScrollView) -> Bool {
        var changed = false
        if scrollView.hasVerticalScroller {
            scrollView.hasVerticalScroller = false
            changed = true
        }
        if scrollView.hasHorizontalScroller {
            scrollView.hasHorizontalScroller = false
            changed = true
        }
        if !scrollView.autohidesScrollers {
            scrollView.autohidesScrollers = true
            changed = true
        }
        let insets = scrollView.contentInsets
        if abs(insets.top) > 0.01 || abs(insets.left) > 0.01 || abs(insets.bottom) > 0.01 || abs(insets.right) > 0.01 {
            scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
            changed = true
        }
        if !scrollView.contentView.postsBoundsChangedNotifications {
            scrollView.contentView.postsBoundsChangedNotifications = true
            changed = true
        }
        return changed
    }

    private func applyFocusModeTextContainerGeometryIfNeeded(_ textView: NSTextView) -> Bool {
        guard let textContainer = textView.textContainer else { return false }
        var changed = false
        if textContainer.lineBreakMode != .byWordWrapping {
            textContainer.lineBreakMode = .byWordWrapping
            changed = true
        }
        if textContainer.maximumNumberOfLines != 0 {
            textContainer.maximumNumberOfLines = 0
            changed = true
        }
        if abs(textContainer.lineFragmentPadding - FocusModeLayoutMetrics.focusModeLineFragmentPadding) > 0.01 {
            textContainer.lineFragmentPadding = FocusModeLayoutMetrics.focusModeLineFragmentPadding
            changed = true
        }
        if textContainer.widthTracksTextView {
            textContainer.widthTracksTextView = false
            changed = true
        }
        if textContainer.heightTracksTextView {
            textContainer.heightTracksTextView = false
            changed = true
        }
        let targetWidth = focusModeTargetContainerWidth(for: textView)
        if abs(textContainer.containerSize.width - targetWidth) > 0.5 {
            textContainer.containerSize = CGSize(width: targetWidth, height: .greatestFiniteMagnitude)
            changed = true
        }
        return changed
    }

    func observedFocusModeBodyHeight(for textView: NSTextView) -> CGFloat? {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return nil }
        let textLength = (textView.string as NSString).length
        if textLength > 0 {
            let fullRange = NSRange(location: 0, length: textLength)
            layoutManager.ensureGlyphs(forCharacterRange: fullRange)
            layoutManager.ensureLayout(forCharacterRange: fullRange)
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        guard usedHeight > 0 else { return nil }
        return max(1, ceil(usedHeight + focusModeBodySafetyInset))
    }

    @discardableResult
    func normalizeInactiveFocusModeTextEditorOffsets(
        includeActive: Bool = false
    ) -> (scanned: Int, reset: Int, skippedActive: Int, observedUpdates: Int) {
        guard let context = resolveFocusModeOffsetNormalizationContext() else { return (0, 0, 0, 0) }
        mapFocusModeResponderCardsForNormalization(
            textViews: context.textViews,
            focusedCards: context.focusedCards,
            activeTextView: context.activeTextView,
            activeFocusedCardID: context.activeFocusedCardID,
            focusedCardIDs: context.focusedCardIDs
        )

        var observedByCardID = focusObservedBodyHeightByCardID
        let metrics = normalizeFocusModeTextViews(
            textViews: context.textViews,
            includeActive: includeActive,
            activeTextView: context.activeTextView,
            focusedCardIDs: context.focusedCardIDs,
            observedByCardID: &observedByCardID
        )
        syncFocusModeObservedBodyHeights(
            observedByCardID: &observedByCardID,
            focusedCardIDs: context.focusedCardIDs
        )
        return metrics
    }

    private struct FocusModeOffsetNormalizationContext {
        let activeTextView: NSTextView?
        let focusedCards: [SceneCard]
        let focusedCardIDs: Set<UUID>
        let activeFocusedCardID: UUID?
        let textViews: [NSTextView]
    }

    private func resolveFocusModeOffsetNormalizationContext() -> FocusModeOffsetNormalizationContext? {
        guard showFocusMode else { return nil }
        guard !isReferenceWindowFocused else { return nil }
        guard let root = NSApp.keyWindow?.contentView else { return nil }

        let activeTextView = NSApp.keyWindow?.firstResponder as? NSTextView
        let focusedCards = focusedColumnCards()
        let focusedCardIDs = Set(focusedCards.map(\.id))
        let activeFocusedCardID = focusModeEditorCardID ?? editingCardID ?? activeCardID
        let allEditableTextViews = collectEditableFocusModeTextViews(root: root)
        let textViews = resolveFocusModeOffsetNormalizationTextViews(
            root: root,
            focusedCardCount: focusedCards.count,
            allEditableTextViews: allEditableTextViews
        )
        return FocusModeOffsetNormalizationContext(
            activeTextView: activeTextView,
            focusedCards: focusedCards,
            focusedCardIDs: focusedCardIDs,
            activeFocusedCardID: activeFocusedCardID,
            textViews: textViews
        )
    }

    private func syncFocusModeObservedBodyHeights(
        observedByCardID: inout [UUID: CGFloat],
        focusedCardIDs: Set<UUID>
    ) {
        if focusedCardIDs.isEmpty {
            observedByCardID.removeAll()
        } else {
            observedByCardID = observedByCardID.filter { focusedCardIDs.contains($0.key) }
        }
        if observedByCardID != focusObservedBodyHeightByCardID {
            focusObservedBodyHeightByCardID = observedByCardID
        }
    }

    private func collectEditableFocusModeTextViews(root: NSView) -> [NSTextView] {
        collectTextViews(in: root).filter { textView in
            textView.isEditable && !isReferenceTextView(textView)
        }
    }

    private func resolveFocusModeOffsetNormalizationTextViews(
        root: NSView,
        focusedCardCount: Int,
        allEditableTextViews: [NSTextView]
    ) -> [NSTextView] {
        let rootBounds = root.bounds
        var textViews = strictFocusModeOffsetNormalizationCandidates(
            root: root,
            rootBounds: rootBounds,
            allEditableTextViews: allEditableTextViews
        )
        textViews = fallbackFocusModeOffsetNormalizationCandidatesIfNeeded(
            textViews: textViews,
            root: root,
            rootBounds: rootBounds,
            focusedCardCount: focusedCardCount,
            allEditableTextViews: allEditableTextViews
        )
        textViews = trimFocusModeOffsetNormalizationCandidatesIfNeeded(
            textViews: textViews,
            root: root,
            rootBounds: rootBounds,
            focusedCardCount: focusedCardCount
        )
        return sortedFocusModeTextViewsByVerticalPosition(textViews)
    }

    private func strictFocusModeOffsetNormalizationCandidates(
        root: NSView,
        rootBounds: CGRect,
        allEditableTextViews: [NSTextView]
    ) -> [NSTextView] {
        let rootCenterX = rootBounds.midX
        let strictMinWidth = max(280, rootBounds.width * 0.34)
        return allEditableTextViews.filter { textView in
            let frameInRoot = textView.convert(textView.bounds, to: root)
            guard frameInRoot.width >= strictMinWidth else { return false }
            let centerDistance = abs(frameInRoot.midX - rootCenterX)
            return centerDistance <= (rootBounds.width * 0.22)
        }
    }

    private func fallbackFocusModeOffsetNormalizationCandidatesIfNeeded(
        textViews: [NSTextView],
        root: NSView,
        rootBounds: CGRect,
        focusedCardCount: Int,
        allEditableTextViews: [NSTextView]
    ) -> [NSTextView] {
        guard textViews.count < focusedCardCount else { return textViews }
        let looseMinWidth = max(220, rootBounds.width * 0.24)
        let looseMatches = allEditableTextViews.filter { textView in
            let frameInRoot = textView.convert(textView.bounds, to: root)
            return frameInRoot.width >= looseMinWidth
        }
        if looseMatches.count < focusedCardCount {
            return allEditableTextViews
        }
        return looseMatches
    }

    private func trimFocusModeOffsetNormalizationCandidatesIfNeeded(
        textViews: [NSTextView],
        root: NSView,
        rootBounds: CGRect,
        focusedCardCount: Int
    ) -> [NSTextView] {
        guard focusedCardCount > 0 else { return textViews }
        guard textViews.count > focusedCardCount else { return textViews }

        let rootCenterX = rootBounds.midX
        let trimmed = textViews
            .sorted { lhs, rhs in
                let lhsFrame = lhs.convert(lhs.bounds, to: root)
                let rhsFrame = rhs.convert(rhs.bounds, to: root)
                let lhsDistance = abs(lhsFrame.midX - rootCenterX)
                let rhsDistance = abs(rhsFrame.midX - rootCenterX)
                if abs(lhsDistance - rhsDistance) > 1 {
                    return lhsDistance < rhsDistance
                }
                return lhsFrame.midY > rhsFrame.midY
            }
            .prefix(focusedCardCount)
        return Array(trimmed)
    }

    private func sortedFocusModeTextViewsByVerticalPosition(_ views: [NSTextView]) -> [NSTextView] {
        views.sorted {
            let y1 = $0.convert(NSPoint.zero, to: nil).y
            let y2 = $1.convert(NSPoint.zero, to: nil).y
            return y1 > y2
        }
    }

    private func mapFocusModeResponderCardsForNormalization(
        textViews: [NSTextView],
        focusedCards: [SceneCard],
        activeTextView: NSTextView?,
        activeFocusedCardID: UUID?,
        focusedCardIDs: Set<UUID>
    ) {
        if !focusedCards.isEmpty && !textViews.isEmpty {
            let pairCount = min(textViews.count, focusedCards.count)
            for i in 0 ..< pairCount {
                let identity = ObjectIdentifier(textViews[i])
                focusResponderCardByObjectID[identity] = focusedCards[i].id
            }
        }

        for textView in textViews {
            let identity = ObjectIdentifier(textView)
            if focusResponderCardByObjectID[identity] == nil,
               textView === activeTextView,
               let activeFocusedCardID,
               focusedCardIDs.contains(activeFocusedCardID) {
                focusResponderCardByObjectID[identity] = activeFocusedCardID
            }
        }
    }

    private func normalizeFocusModeTextViews(
        textViews: [NSTextView],
        includeActive: Bool,
        activeTextView: NSTextView?,
        focusedCardIDs: Set<UUID>,
        observedByCardID: inout [UUID: CGFloat]
    ) -> (scanned: Int, reset: Int, skippedActive: Int, observedUpdates: Int) {
        var metrics = FocusModeTextViewNormalizationMetrics()
        for textView in textViews {
            normalizeSingleFocusModeTextView(
                textView,
                includeActive: includeActive,
                activeTextView: activeTextView,
                focusedCardIDs: focusedCardIDs,
                observedByCardID: &observedByCardID,
                metrics: &metrics
            )
        }
        return (metrics.scanned, metrics.resetCount, metrics.skippedActive, metrics.observedUpdates)
    }

    private struct FocusModeTextViewNormalizationMetrics {
        var scanned = 0
        var resetCount = 0
        var skippedActive = 0
        var observedUpdates = 0
    }

    private func normalizeSingleFocusModeTextView(
        _ textView: NSTextView,
        includeActive: Bool,
        activeTextView: NSTextView?,
        focusedCardIDs: Set<UUID>,
        observedByCardID: inout [UUID: CGFloat],
        metrics: inout FocusModeTextViewNormalizationMetrics
    ) {
        metrics.scanned += 1
        let identity = ObjectIdentifier(textView)
        let isActiveResponder = (activeTextView != nil && textView === activeTextView)
        let mappedCardID = focusResponderCardByObjectID[identity]
        let isFocusEditor = mappedCardID.map({ focusedCardIDs.contains($0) }) ?? false

        applyFocusModeGeometryForNormalizationIfNeeded(
            textView: textView,
            isActiveResponder: isActiveResponder,
            isFocusEditor: isFocusEditor
        )
        updateObservedFocusModeBodyHeightForNormalization(
            textView: textView,
            mappedCardID: mappedCardID,
            focusedCardIDs: focusedCardIDs,
            observedByCardID: &observedByCardID,
            observedUpdates: &metrics.observedUpdates
        )
        guard includeActive || !isActiveResponder else {
            metrics.skippedActive += 1
            return
        }
        if resetFocusModeTextViewScrollOriginIfNeeded(textView) {
            metrics.resetCount += 1
        }
    }

    private func applyFocusModeGeometryForNormalizationIfNeeded(
        textView: NSTextView,
        isActiveResponder: Bool,
        isFocusEditor: Bool
    ) {
        guard isFocusEditor || isActiveResponder else { return }
        _ = applyFocusModeTextViewGeometryIfNeeded(
            textView,
            reason: isActiveResponder ? "offset-normalization-active" : "offset-normalization-inactive"
        )
    }

    private func updateObservedFocusModeBodyHeightForNormalization(
        textView: NSTextView,
        mappedCardID: UUID?,
        focusedCardIDs: Set<UUID>,
        observedByCardID: inout [UUID: CGFloat],
        observedUpdates: inout Int
    ) {
        guard let mappedCardID, focusedCardIDs.contains(mappedCardID) else { return }
        guard let observed = observedFocusModeBodyHeight(for: textView) else { return }
        guard abs((observedByCardID[mappedCardID] ?? 0) - observed) > 0.5 else { return }
        observedByCardID[mappedCardID] = observed
        observedUpdates += 1
    }

    private func resetFocusModeTextViewScrollOriginIfNeeded(_ textView: NSTextView) -> Bool {
        guard let scrollView = textView.enclosingScrollView else { return false }
        let origin = scrollView.contentView.bounds.origin
        let shouldResetOrigin = abs(origin.x) > 0.5 || abs(origin.y) > 0.5
        guard shouldResetOrigin else { return false }
        scrollView.contentView.setBoundsOrigin(.zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        return true
    }

    func requestFocusModeOffsetNormalization(
        includeActive: Bool = false,
        force: Bool = false,
        reason: String = "unspecified"
    ) {
        let now = Date()
        let elapsed = now.timeIntervalSince(focusOffsetNormalizationLastAt)
        
        if !force {
            if elapsed < focusOffsetNormalizationMinInterval {
                return
            }
        }
        focusOffsetNormalizationLastAt = now
        _ = normalizeInactiveFocusModeTextEditorOffsets(includeActive: includeActive)
    }

    func normalizeSingleTextEditorOffsetIfNeeded(_ textView: NSTextView, reason: String = "single") {
        guard let scrollView = textView.enclosingScrollView else { return }
        let origin = scrollView.contentView.bounds.origin
        let shouldResetOrigin = abs(origin.x) > 0.5 || abs(origin.y) > 0.5
        if shouldResetOrigin {
            scrollView.contentView.setBoundsOrigin(.zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    func scheduleFocusModeOffsetNormalizationBurst(includeActive: Bool) {
        let delays: [Double] = [0.0, 0.05, 0.16]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                requestFocusModeOffsetNormalization(includeActive: includeActive, force: true, reason: "burst-delay-\(String(format: "%.2f", delay))")
            }
        }
    }

    func collectTextViews(in root: NSView) -> [NSTextView] {
        var result: [NSTextView] = []
        var stack: [NSView] = [root]
        while let view = stack.popLast() {
            if let textView = view as? NSTextView {
                result.append(textView)
            }
            // Reverse so left-most child is processed first (depth-first)
            stack.append(contentsOf: view.subviews.reversed())
        }
        return result
    }

    func startFocusModeCaretMonitor() {
        if focusModeSelectionObserver == nil {
            focusModeSelectionObserver = NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: nil,
                queue: .main
            ) { notification in
                handleFocusModeSelectionNotification(notification)
            }
        }
        DispatchQueue.main.async {
            requestFocusModeCaretEnsure(typewriter: false, reason: "caret-monitor-start")
            requestFocusModeOffsetNormalization(includeActive: false, force: true, reason: "caret-monitor-start")
        }
    }

    func handleFocusModeSelectionNotification(_ notification: Notification) {
        guard let textView = focusModeSelectionTextView(from: notification) else { return }
        DispatchQueue.main.async {
            processFocusModeSelectionNotification(textView: textView)
        }
    }

    private func processFocusModeSelectionNotification(textView: NSTextView) {
        guard showFocusMode else { return }
        guard !isApplyingUndo else { return }
        guard !isReferenceWindowFocused else { return }
        guard (NSApp.keyWindow?.firstResponder as? NSTextView) === textView else { return }

        rememberFocusResponderCardMapping(textView: textView)
        if focusUndoSelectionEnsureSuppressed {
            return
        }

        let context = focusModeSelectionContext(for: textView)
        updateFocusSelectionActiveEdge(
            selected: context.selected,
            textLength: context.textLength,
            trackedCardID: context.trackedCardID,
            responderID: context.responderID
        )

        if restoreExpectedFocusSelectionIfNeeded(textView: textView, context: context) { return }
        if handleDuplicateFocusSelectionIfNeeded(textView: textView, context: context) { return }
        applyFocusSelectionNotification(textView: textView, context: context)
    }

    private struct FocusModeSelectionContext {
        let responderID: ObjectIdentifier
        let selected: NSRange
        let textLength: Int
        let trackedCardID: UUID?
    }

    private func focusModeSelectionContext(for textView: NSTextView) -> FocusModeSelectionContext {
        let responderID = ObjectIdentifier(textView)
        let selected = textView.selectedRange()
        let textLength = (textView.string as NSString).length
        let trackedCardID = trackedFocusSelectionCardID(for: responderID)
        return FocusModeSelectionContext(
            responderID: responderID,
            selected: selected,
            textLength: textLength,
            trackedCardID: trackedCardID
        )
    }

    private func restoreExpectedFocusSelectionIfNeeded(
        textView: NSTextView,
        context: FocusModeSelectionContext
    ) -> Bool {
        let shouldIgnoreTransientSelection = shouldIgnoreTransientProgrammaticSelection(
            selected: context.selected,
            textLength: context.textLength,
            trackedCardID: context.trackedCardID
        )
        guard shouldIgnoreTransientSelection else { return false }

        let expectedLocation = min(max(0, focusProgrammaticCaretExpectedLocation), context.textLength)
        if context.selected.location != expectedLocation || context.selected.length != 0 {
            textView.setSelectedRange(NSRange(location: expectedLocation, length: 0))
        }
        return true
    }

    private func handleDuplicateFocusSelectionIfNeeded(
        textView: NSTextView,
        context: FocusModeSelectionContext
    ) -> Bool {
        let duplicate = isDuplicateFocusSelection(
            selected: context.selected,
            textLength: context.textLength,
            trackedCardID: context.trackedCardID,
            responderID: context.responderID
        )
        guard duplicate else { return false }
        handleFocusDeferredTypewriterAfterCompositionIfNeeded(textView: textView)
        return true
    }

    private func applyFocusSelectionNotification(
        textView: NSTextView,
        context: FocusModeSelectionContext
    ) {
        storeFocusSelectionState(
            trackedCardID: context.trackedCardID,
            selected: context.selected,
            textLength: context.textLength,
            responderID: context.responderID
        )
        handleFocusModeSelectionChanged()
        if !textView.hasMarkedText() {
            scheduleFocusCaretEnsureForSelectionChange()
        }
        handleFocusDeferredTypewriterAfterCompositionIfNeeded(textView: textView)
    }

    func focusModeSelectionTextView(from notification: Notification) -> NSTextView? {
        guard let textView =
            (notification.object as? NSTextView) ??
            (NSApp.keyWindow?.firstResponder as? NSTextView)
        else {
            return nil
        }
        guard !isReferenceTextView(textView) else { return nil }
        guard (NSApp.keyWindow?.firstResponder as? NSTextView) === textView else { return nil }
        return textView
    }

    func trackedFocusSelectionCardID(for responderID: ObjectIdentifier) -> UUID? {
        focusResponderCardByObjectID[responderID] ??
        (focusModeEditorCardID ?? editingCardID ?? activeCardID)
    }

    func updateFocusSelectionActiveEdge(
        selected: NSRange,
        textLength: Int,
        trackedCardID: UUID?,
        responderID: ObjectIdentifier
    ) {
        // Compute active selection edge to avoid scroll fighting during caret ensures.
        let selectedEndpoints = normalizedFocusSelectionEndpoints(selected: selected, textLength: textLength)
        if selected.length == 0 {
            _focusSelectionActiveEdge = .end
            return
        }
        guard let previousEndpoints = previousFocusSelectionEndpointsIfComparable(
            trackedCardID: trackedCardID,
            responderID: responderID
        ) else {
            return
        }
        applyFocusSelectionActiveEdge(selected: selectedEndpoints, previous: previousEndpoints)
    }

    private struct FocusSelectionEndpoints {
        let start: Int
        let end: Int
    }

    private func normalizedFocusSelectionEndpoints(selected: NSRange, textLength: Int) -> FocusSelectionEndpoints {
        let start = min(max(0, selected.location), textLength)
        let end = min(max(start, selected.location + selected.length), textLength)
        return FocusSelectionEndpoints(start: start, end: end)
    }

    private func previousFocusSelectionEndpointsIfComparable(
        trackedCardID: UUID?,
        responderID: ObjectIdentifier
    ) -> FocusSelectionEndpoints? {
        let previousRangeIsComparable =
            focusSelectionLastCardID == trackedCardID &&
            focusSelectionLastResponderID == responderID &&
            focusSelectionLastLocation >= 0 &&
            focusSelectionLastLength >= 0
        guard previousRangeIsComparable else { return nil }

        let previousStart = min(max(0, focusSelectionLastLocation), max(0, focusSelectionLastTextLength))
        let previousEnd = min(
            max(previousStart, focusSelectionLastLocation + max(0, focusSelectionLastLength)),
            max(0, focusSelectionLastTextLength)
        )
        return FocusSelectionEndpoints(start: previousStart, end: previousEnd)
    }

    private func applyFocusSelectionActiveEdge(
        selected: FocusSelectionEndpoints,
        previous: FocusSelectionEndpoints
    ) {
        let movedStart = selected.start != previous.start
        let movedEnd = selected.end != previous.end
        if movedStart && !movedEnd {
            _focusSelectionActiveEdge = .start
        } else if !movedStart && movedEnd {
            _focusSelectionActiveEdge = .end
        } else if movedStart && movedEnd {
            let startDelta = abs(selected.start - previous.start)
            let endDelta = abs(selected.end - previous.end)
            if startDelta > endDelta {
                _focusSelectionActiveEdge = .start
            } else if endDelta > startDelta {
                _focusSelectionActiveEdge = .end
            }
        }
    }

    func shouldIgnoreTransientProgrammaticSelection(
        selected: NSRange,
        textLength: Int,
        trackedCardID: UUID?
    ) -> Bool {
        guard Date() < focusProgrammaticCaretSelectionIgnoreUntil else { return false }
        guard let expectedCardID = focusProgrammaticCaretExpectedCardID else { return false }
        guard selected.length == 0 else { return false }
        guard focusProgrammaticCaretExpectedLocation >= 0 else { return false }
        let isExpectedCardContext =
            trackedCardID == expectedCardID ||
            focusModeEditorCardID == expectedCardID ||
            editingCardID == expectedCardID ||
            activeCardID == expectedCardID
        guard isExpectedCardContext else { return false }
        guard findCard(by: expectedCardID) != nil else { return false }

        let expected = min(max(0, focusProgrammaticCaretExpectedLocation), textLength)
        if selected.location == expected {
            focusProgrammaticCaretExpectedCardID = nil
            focusProgrammaticCaretExpectedLocation = -1
            focusProgrammaticCaretSelectionIgnoreUntil = .distantPast
            return false
        }
        let boundaryMismatch = selected.location == 0 || selected.location == textLength
        return boundaryMismatch && abs(selected.location - expected) > 2
    }

    func isDuplicateFocusSelection(
        selected: NSRange,
        textLength: Int,
        trackedCardID: UUID?,
        responderID: ObjectIdentifier
    ) -> Bool {
        focusSelectionLastCardID == trackedCardID &&
        focusSelectionLastLocation == selected.location &&
        focusSelectionLastLength == selected.length &&
        focusSelectionLastTextLength == textLength &&
        focusSelectionLastResponderID == responderID
    }

    func storeFocusSelectionState(
        trackedCardID: UUID?,
        selected: NSRange,
        textLength: Int,
        responderID: ObjectIdentifier
    ) {
        focusSelectionLastCardID = trackedCardID
        focusSelectionLastLocation = selected.location
        focusSelectionLastLength = selected.length
        focusSelectionLastTextLength = textLength
        focusSelectionLastResponderID = responderID
    }

    func scheduleFocusCaretEnsureForSelectionChange() {
        let now = Date()
        let elapsed = now.timeIntervalSince(focusCaretEnsureLastScheduledAt)
        let delay = max(0, focusCaretSelectionEnsureMinInterval - elapsed)
        focusCaretEnsureLastScheduledAt = now.addingTimeInterval(delay)
        requestFocusModeCaretEnsure(typewriter: false, delay: delay, reason: "selection-change")
    }

    func handleFocusDeferredTypewriterAfterCompositionIfNeeded(textView: NSTextView) {
        if focusTypewriterDeferredUntilCompositionEnd, !textView.hasMarkedText() {
            focusTypewriterDeferredUntilCompositionEnd = false
            requestFocusModeCaretEnsure(typewriter: true, delay: 0.0, reason: "composition-end")
        }
    }

    func stopFocusModeCaretMonitor() {
        focusCaretEnsureWorkItem?.cancel()
        focusCaretEnsureWorkItem = nil
        focusCaretPendingTypewriter = false
        focusTypewriterDeferredUntilCompositionEnd = false
        focusSelectionLastCardID = nil
        focusSelectionLastLocation = -1
        focusSelectionLastLength = -1
        focusSelectionLastTextLength = -1
        focusSelectionLastResponderID = nil
        focusCaretEnsureLastScheduledAt = .distantPast
        focusProgrammaticCaretExpectedCardID = nil
        focusProgrammaticCaretExpectedLocation = -1
        focusProgrammaticCaretSelectionIgnoreUntil = .distantPast
        focusUndoSelectionEnsureSuppressed = false
        focusUndoSelectionEnsureRequestID = nil
        _focusSelectionActiveEdge = .end
        resetFocusTypingCoalescing()
        focusResponderCardByObjectID.removeAll()
        focusObservedBodyHeightByCardID.removeAll()
        if let observer = focusModeSelectionObserver {
            NotificationCenter.default.removeObserver(observer)
            focusModeSelectionObserver = nil
        }
    }

    func rememberFocusResponderCardMapping(textView: NSTextView? = nil) {
        guard showFocusMode else { return }
        guard let textView = textView ?? (NSApp.keyWindow?.firstResponder as? NSTextView) else { return }
        guard let cardID = focusModeEditorCardID ?? editingCardID ?? activeCardID else { return }
        focusResponderCardByObjectID[ObjectIdentifier(textView)] = cardID
    }

    func requestFocusModeCaretEnsure(typewriter: Bool, delay: Double = 0.016, force: Bool = false, reason: String = "unspecified") {
        if focusUndoSelectionEnsureSuppressed && !force { return }
        if typewriter {
            focusCaretPendingTypewriter = true
        }
        focusCaretEnsureWorkItem?.cancel()
        let work = DispatchWorkItem {
            focusCaretEnsureWorkItem = nil
            executeFocusModeCaretEnsureWork(force: force)
        }
        focusCaretEnsureWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        _ = reason
    }

    private func executeFocusModeCaretEnsureWork(force: Bool) {
        if focusUndoSelectionEnsureSuppressed && !force {
            resetFocusModeCaretPendingState(clearDeferredTypewriter: false)
            return
        }
        guard showFocusMode else {
            resetFocusModeCaretPendingState(clearDeferredTypewriter: true)
            return
        }
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
            resetFocusModeCaretPendingState(clearDeferredTypewriter: false)
            return
        }
        guard !isReferenceTextView(textView) else {
            resetFocusModeCaretPendingState(clearDeferredTypewriter: true)
            return
        }

        let runTypewriter = resolvedFocusModeCaretEnsureTypewriterMode(textView: textView)
        if !textView.hasMarkedText() {
            _ = applyFocusModeTextViewGeometryIfNeeded(textView, reason: "caret-ensure")
            normalizeSingleTextEditorOffsetIfNeeded(textView, reason: "caret-ensure")
        }
        ensureFocusModeCaretVisible(typewriter: runTypewriter)
        requestFocusModeOffsetNormalization(reason: "caret-ensure")
    }

    private func resetFocusModeCaretPendingState(clearDeferredTypewriter: Bool) {
        focusCaretPendingTypewriter = false
        if clearDeferredTypewriter {
            focusTypewriterDeferredUntilCompositionEnd = false
        }
    }

    private func resolvedFocusModeCaretEnsureTypewriterMode(textView: NSTextView) -> Bool {
        var runTypewriter = focusTypewriterEnabledLive && focusCaretPendingTypewriter
        focusCaretPendingTypewriter = false
        if runTypewriter && textView.hasMarkedText() {
            focusTypewriterDeferredUntilCompositionEnd = true
            runTypewriter = false
        }
        return runTypewriter
    }

    func ensureFocusModeCaretVisible(typewriter: Bool = false) {
        guard let context = resolveFocusModeCaretEnsureContext() else { return }

        let selectionRects = resolveFocusModeCaretSelectionRects(
            textView: context.textView,
            layoutManager: context.layoutManager,
            textContainer: context.textContainer,
            outerDocumentView: context.outerDocumentView
        )
        let viewport = resolveFocusModeCaretViewportContext(outerScrollView: context.outerScrollView)
        let targetY = resolveFocusModeCaretTargetY(
            selectionRects: selectionRects,
            viewport: viewport,
            typewriter: typewriter
        )
        applyFocusModeCaretScrollPositionIfNeeded(
            outerScrollView: context.outerScrollView,
            visible: viewport.visible,
            targetY: targetY,
            minY: viewport.minY,
            maxY: viewport.maxY,
            typewriter: typewriter
        )
    }

    private struct FocusModeCaretEnsureContext {
        let textView: NSTextView
        let outerScrollView: NSScrollView
        let outerDocumentView: NSView
        let layoutManager: NSLayoutManager
        let textContainer: NSTextContainer
    }

    private func resolveFocusModeCaretEnsureContext() -> FocusModeCaretEnsureContext? {
        guard showFocusMode else { return nil }
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return nil }
        guard !isReferenceTextView(textView) else { return nil }
        guard let outerScrollView = outerScrollView(containing: textView),
              let outerDocumentView = outerScrollView.documentView else {
            return nil
        }
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
            return nil
        }
        return FocusModeCaretEnsureContext(
            textView: textView,
            outerScrollView: outerScrollView,
            outerDocumentView: outerDocumentView,
            layoutManager: layoutManager,
            textContainer: textContainer
        )
    }

    private struct FocusModeCaretSelectionRects {
        let selection: NSRange
        let startRect: CGRect
        let endRect: CGRect
    }

    private struct FocusModeCaretViewportContext {
        let visible: CGRect
        let minY: CGFloat
        let maxY: CGFloat
        let minVisibleY: CGFloat
        let maxVisibleY: CGFloat
        let topPadding: CGFloat
        let bottomPadding: CGFloat
    }

    private func resolveFocusModeCaretSelectionRects(
        textView: NSTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        outerDocumentView: NSView
    ) -> FocusModeCaretSelectionRects {
        let textLength = (textView.string as NSString).length
        let selection = textView.selectedRange()
        let selectionStart = min(selection.location, textLength)
        let selectionEnd = min(selection.location + selection.length, textLength)
        let startRect = focusModeCaretRectInDocument(
            at: selectionStart,
            textView: textView,
            layoutManager: layoutManager,
            textContainer: textContainer,
            outerDocumentView: outerDocumentView
        )
        let endRect = (selection.length > 0)
            ? focusModeCaretRectInDocument(
                at: selectionEnd,
                textView: textView,
                layoutManager: layoutManager,
                textContainer: textContainer,
                outerDocumentView: outerDocumentView
            )
            : startRect

        return FocusModeCaretSelectionRects(selection: selection, startRect: startRect, endRect: endRect)
    }

    private func focusModeCaretRectInDocument(
        at location: Int,
        textView: NSTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        outerDocumentView: NSView
    ) -> CGRect {
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: location, length: 0),
            actualCharacterRange: nil
        )
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textView.textContainerInset.width
        rect.origin.y += textView.textContainerInset.height
        if rect.height < fontSize {
            rect.size.height = fontSize + 2
        }
        return outerDocumentView.convert(rect, from: textView)
    }

    private func resolveFocusModeCaretViewportContext(outerScrollView: NSScrollView) -> FocusModeCaretViewportContext {
        let visible = outerScrollView.documentVisibleRect
        let documentHeight = outerScrollView.documentView?.bounds.height ?? 0
        let insets = outerScrollView.contentInsets
        let clipOriginY = outerScrollView.contentView.bounds.origin.y
        // Some layouts report a negative top origin even when contentInsets.top is zero.
        // Infer the effective top inset from the current clip origin to prevent -inset -> 0 jitter.
        let inferredTopInset = max(0, -clipOriginY)
        let effectiveTopInset = max(insets.top, inferredTopInset)
        let minY = -effectiveTopInset
        let maxY = max(minY, documentHeight - visible.height + insets.bottom)
        let topPadding: CGFloat = 120
        let bottomPadding: CGFloat = 120
        let minVisibleY = visible.minY + topPadding
        let maxVisibleY = visible.maxY - bottomPadding

        return FocusModeCaretViewportContext(
            visible: visible,
            minY: minY,
            maxY: maxY,
            minVisibleY: minVisibleY,
            maxVisibleY: maxVisibleY,
            topPadding: topPadding,
            bottomPadding: bottomPadding
        )
    }

    private func resolveFocusModeCaretTargetY(
        selectionRects: FocusModeCaretSelectionRects,
        viewport: FocusModeCaretViewportContext,
        typewriter: Bool
    ) -> CGFloat {
        if let typewriterTargetY = resolveFocusModeTypewriterTargetYIfNeeded(
            selectionRects: selectionRects,
            viewport: viewport,
            typewriter: typewriter
        ) {
            return typewriterTargetY
        }
        return resolveFocusModeStandardCaretTargetY(selectionRects: selectionRects, viewport: viewport)
    }

    private func resolveFocusModeTypewriterTargetYIfNeeded(
        selectionRects: FocusModeCaretSelectionRects,
        viewport: FocusModeCaretViewportContext,
        typewriter: Bool
    ) -> CGFloat? {
        guard focusTypewriterEnabledLive && typewriter else { return nil }
        let baseline = CGFloat(min(max(focusTypewriterBaseline, 0.40), 0.80))
        let selection = selectionRects.selection
        let activeRect =
            (selection.length > 0 && _focusSelectionActiveEdge == .start)
            ? selectionRects.startRect
            : selectionRects.endRect
        return activeRect.midY - (viewport.visible.height * baseline)
    }

    private func resolveFocusModeStandardCaretTargetY(
        selectionRects: FocusModeCaretSelectionRects,
        viewport: FocusModeCaretViewportContext
    ) -> CGFloat {
        let defaultTargetY = viewport.visible.origin.y
        if selectionRects.selection.length > 0 {
            return resolveFocusModeExpandedSelectionTargetY(
                selectionRects: selectionRects,
                viewport: viewport,
                defaultTargetY: defaultTargetY
            )
        }
        return resolveFocusModeCollapsedSelectionTargetY(
            selectionRects: selectionRects,
            viewport: viewport,
            defaultTargetY: defaultTargetY
        )
    }

    private func resolveFocusModeExpandedSelectionTargetY(
        selectionRects: FocusModeCaretSelectionRects,
        viewport: FocusModeCaretViewportContext,
        defaultTargetY: CGFloat
    ) -> CGFloat {
        var targetY = defaultTargetY
        let startRect = selectionRects.startRect
        let endRect = selectionRects.endRect
        switch _focusSelectionActiveEdge {
        case .start:
            if startRect.minY < viewport.minVisibleY {
                targetY = max(viewport.minY, startRect.minY - viewport.topPadding)
            } else if startRect.maxY > viewport.maxVisibleY {
                targetY = startRect.maxY - (viewport.visible.height - viewport.bottomPadding)
            }
        case .end:
            if endRect.maxY > viewport.maxVisibleY {
                targetY = endRect.maxY - (viewport.visible.height - viewport.bottomPadding)
            } else if endRect.minY < viewport.minVisibleY {
                targetY = max(viewport.minY, endRect.minY - viewport.topPadding)
            }
        }
        return targetY
    }

    private func resolveFocusModeCollapsedSelectionTargetY(
        selectionRects: FocusModeCaretSelectionRects,
        viewport: FocusModeCaretViewportContext,
        defaultTargetY: CGFloat
    ) -> CGFloat {
        var targetY = defaultTargetY
        let startRect = selectionRects.startRect
        let endRect = selectionRects.endRect
        if endRect.maxY > viewport.maxVisibleY {
            targetY = endRect.maxY - (viewport.visible.height - viewport.bottomPadding)
        } else if startRect.minY < viewport.minVisibleY {
            targetY = max(viewport.minY, startRect.minY - viewport.topPadding)
        }
        return targetY
    }

    private func applyFocusModeCaretScrollPositionIfNeeded(
        outerScrollView: NSScrollView,
        visible: CGRect,
        targetY: CGFloat,
        minY: CGFloat,
        maxY: CGFloat,
        typewriter: Bool
    ) {
        let deadZone: CGFloat = typewriter ? 14.0 : 1.0
        _ = CaretScrollCoordinator.applyVerticalScrollIfNeeded(
            scrollView: outerScrollView,
            visibleRect: visible,
            targetY: targetY,
            minY: minY,
            maxY: maxY,
            deadZone: deadZone,
            snapToPixel: typewriter
        )
    }

    func outerScrollView(containing textView: NSTextView) -> NSScrollView? {
        let inner = textView.enclosingScrollView
        var view: NSView? = inner?.superview
        while let current = view {
            if let scrollView = current as? NSScrollView, scrollView !== inner {
                return scrollView
            }
            view = current.superview
        }
        return nil
    }

    func beginFocusModeEditing(
        _ card: SceneCard,
        cursorToEnd: Bool,
        cardScrollAnchor: UnitPoint? = nil,
        animatedScroll: Bool = true,
        preserveViewportOnSwitch: Bool = false,
        placeCursorAtStartWhenNoHint: Bool = true,
        allowPendingEntryCaretHint: Bool = true,
        explicitCaretLocation: Int? = nil
    ) {
        let switchingToDifferentCard = applyFocusModeBeginEditingCardTransition(
            card: card,
            cardScrollAnchor: cardScrollAnchor,
            animatedScroll: animatedScroll,
            preserveViewportOnSwitch: preserveViewportOnSwitch
        )
        let location = prepareFocusModeBeginEditingCaret(
            card: card,
            cursorToEnd: cursorToEnd,
            placeCursorAtStartWhenNoHint: placeCursorAtStartWhenNoHint,
            allowPendingEntryCaretHint: allowPendingEntryCaretHint,
            explicitCaretLocation: explicitCaretLocation,
            switchingToDifferentCard: switchingToDifferentCard,
            preserveViewportOnSwitch: preserveViewportOnSwitch
        )
        scheduleFocusModeBeginEditingCaret(
            cardID: card.id,
            location: location,
            cardScrollAnchor: cardScrollAnchor,
            preserveViewportOnSwitch: preserveViewportOnSwitch
        )
    }

    private func applyFocusModeBeginEditingCardTransition(
        card: SceneCard,
        cardScrollAnchor: UnitPoint?,
        animatedScroll: Bool,
        preserveViewportOnSwitch: Bool
    ) -> Bool {
        let switchingToDifferentCard = (editingCardID != card.id)
        prepareFocusModeForEditingSwitchIfNeeded(targetCardID: card.id)
        updateActiveCardForFocusModeEditing(
            card: card,
            cardScrollAnchor: cardScrollAnchor,
            animatedScroll: animatedScroll,
            preserveViewportOnSwitch: preserveViewportOnSwitch
        )
        syncFocusModeEditingState(card: card, switchingToDifferentCard: switchingToDifferentCard)
        return switchingToDifferentCard
    }

    private func prepareFocusModeBeginEditingCaret(
        card: SceneCard,
        cursorToEnd: Bool,
        placeCursorAtStartWhenNoHint: Bool,
        allowPendingEntryCaretHint: Bool,
        explicitCaretLocation: Int?,
        switchingToDifferentCard: Bool,
        preserveViewportOnSwitch: Bool
    ) -> Int? {
        let location = resolveFocusModeBeginEditingCaretLocation(
            card: card,
            cursorToEnd: cursorToEnd,
            placeCursorAtStartWhenNoHint: placeCursorAtStartWhenNoHint,
            allowPendingEntryCaretHint: allowPendingEntryCaretHint,
            explicitCaretLocation: explicitCaretLocation
        )
        configureFocusModeProgrammaticCaretExpectation(
            cardID: card.id,
            location: location,
            switchingToDifferentCard: switchingToDifferentCard,
            preserveViewportOnSwitch: preserveViewportOnSwitch,
            explicitCaretLocation: explicitCaretLocation
        )
        return location
    }

    private func scheduleFocusModeBeginEditingCaret(
        cardID: UUID,
        location: Int?,
        cardScrollAnchor: UnitPoint?,
        preserveViewportOnSwitch: Bool
    ) {
        focusModeCaretRequestID += 1
        let requestID = focusModeCaretRequestID
        scheduleFocusModeBeginEditingCaretApplications(
            cardID: cardID,
            location: location,
            requestID: requestID,
            cardScrollAnchor: cardScrollAnchor,
            preserveViewportOnSwitch: preserveViewportOnSwitch
        )
    }

    private func prepareFocusModeForEditingSwitchIfNeeded(targetCardID: UUID) {
        if showFocusMode, activeCardID != nil, activeCardID != targetCardID {
            finalizeFocusTypingCoalescing(reason: "focus-card-switch")
        }
        clearFocusBoundaryArm()
        if showFocusMode, editingCardID != nil, editingCardID != targetCardID {
            commitFocusModeCardEditIfNeeded()
        } else if editingCardID != nil, editingCardID != targetCardID {
            finishEditing()
        }
    }

    private func updateActiveCardForFocusModeEditing(
        card: SceneCard,
        cardScrollAnchor: UnitPoint?,
        animatedScroll: Bool,
        preserveViewportOnSwitch: Bool
    ) {
        if activeCardID != card.id {
            focusPendingProgrammaticBeginEditCardID = card.id
            if preserveViewportOnSwitch {
                // Keep viewport steady across card boundary transitions; caret ensure will do minimal reveal only.
                suppressFocusModeScrollOnce = true
                focusModeNextCardScrollAnchor = nil
                focusModeNextCardScrollAnimated = true
            } else {
                focusModeNextCardScrollAnchor = cardScrollAnchor
                focusModeNextCardScrollAnimated = animatedScroll
            }
            changeActiveCard(to: card)
        } else if focusPendingProgrammaticBeginEditCardID == card.id {
            focusPendingProgrammaticBeginEditCardID = nil
        }
    }

    private func syncFocusModeEditingState(card: SceneCard, switchingToDifferentCard: Bool) {
        // Update selection/editing state after active-card transition to avoid transient caret jumps
        // in the previous card during boundary navigation.
        selectedCardIDs = [card.id]
        if switchingToDifferentCard {
            editingCardID = card.id
            editingStartContent = card.content
            editingStartState = captureScenarioState()
            editingIsNewCard = false
        }
        focusModeEditorCardID = card.id
        focusLastCommittedContentByCard[card.id] = card.content
    }

    private func resolveFocusModeBeginEditingCaretLocation(
        card: SceneCard,
        cursorToEnd: Bool,
        placeCursorAtStartWhenNoHint: Bool,
        allowPendingEntryCaretHint: Bool,
        explicitCaretLocation: Int?
    ) -> Int? {
        let length = (card.content as NSString).length
        if let explicitCaretLocation {
            return min(max(0, explicitCaretLocation), length)
        }
        if allowPendingEntryCaretHint,
           let hint = pendingFocusModeEntryCaretHint,
           hint.cardID == card.id {
            if showFocusMode {
                pendingFocusModeEntryCaretHint = nil
            }
            return min(max(0, hint.location), length)
        }
        if cursorToEnd { return length }
        return placeCursorAtStartWhenNoHint ? 0 : nil
    }

    private func configureFocusModeProgrammaticCaretExpectation(
        cardID: UUID,
        location: Int?,
        switchingToDifferentCard: Bool,
        preserveViewportOnSwitch: Bool,
        explicitCaretLocation: Int?
    ) {
        let shouldApplySelectionIgnoreWindow =
            switchingToDifferentCard || preserveViewportOnSwitch || explicitCaretLocation != nil
        if let location, shouldApplySelectionIgnoreWindow {
            focusProgrammaticCaretExpectedCardID = cardID
            focusProgrammaticCaretExpectedLocation = location
            focusProgrammaticCaretSelectionIgnoreUntil = Date().addingTimeInterval(0.28)
        } else {
            focusProgrammaticCaretExpectedCardID = nil
            focusProgrammaticCaretExpectedLocation = -1
            focusProgrammaticCaretSelectionIgnoreUntil = .distantPast
        }
    }

    private func scheduleFocusModeBeginEditingCaretApplications(
        cardID: UUID,
        location: Int?,
        requestID: Int,
        cardScrollAnchor: UnitPoint?,
        preserveViewportOnSwitch: Bool
    ) {
        guard let location else { return }

        applyFocusModeCaretWithRetry(expectedCardID: cardID, location: location, retries: 10, requestID: requestID)
        // Focus handoff in SwiftUI can be late; re-apply once more after layout settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            applyFocusModeCaretWithRetry(expectedCardID: cardID, location: location, retries: 4, requestID: requestID)
        }

        // Boundary navigation can race with the first focus handoff right after entering focus mode.
        // Re-apply once after the scroll animation window to pin the caret deterministically.
        if cardScrollAnchor != nil || preserveViewportOnSwitch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                applyFocusModeCaretWithRetry(expectedCardID: cardID, location: location, retries: 4, requestID: requestID)
            }
            if cardScrollAnchor != nil {
                scheduleFocusModeCaretEnsureBurst()
            }
        }

        // Entry pass: avoid first transition drift when immediately moving to another card.
        if cardScrollAnchor == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                applyFocusModeCaretWithRetry(expectedCardID: cardID, location: location, retries: 4, requestID: requestID)
            }
        }
    }

    func scheduleFocusModeCaretEnsureBurst() {
        // Cancel any pending burst from previous invocation
        for item in caretEnsureBurstWorkItems { item.cancel() }
        caretEnsureBurstWorkItems.removeAll()
        // Reduced from 5 to 3 delays — the intermediate ticks are redundant
        let delays: [Double] = [0.0, 0.10, 0.28]
        for delay in delays {
            let work = DispatchWorkItem {
                requestFocusModeCaretEnsure(typewriter: false, delay: 0.0, reason: "ensure-burst")
            }
            caretEnsureBurstWorkItems.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    func handleFocusModeCardContentChange(cardID: UUID, oldValue: String, newValue: String) {
        guard canHandleFocusModeCardContentChange(cardID: cardID, oldValue: oldValue, newValue: newValue) else { return }
        markEditingSessionTextMutation()
        guard syncFocusModeContentChangeEditorOffsetIfNeeded() else { return }

        let delta = utf16ChangeDelta(oldValue: oldValue, newValue: newValue)
        if shouldSuppressFocusModeProgrammaticContentChange(cardID: cardID, newValue: newValue) { return }
        if isFocusModeResponderComposingText() { return }

        let now = Date()
        prepareFocusTypingCoalescingSessionIfNeeded(cardID: cardID, oldValue: oldValue, now: now)
        focusTypingLastEditAt = now
        focusLastCommittedContentByCard[cardID] = newValue
        scheduleFocusTypingIdleFinalize()

        if shouldFinalizeFocusTypingForReturnBoundary(delta: delta) { return }
        finalizeFocusTypingForStrongBoundaryIfNeeded(newValue: newValue, delta: delta)
    }

    private func canHandleFocusModeCardContentChange(cardID: UUID, oldValue: String, newValue: String) -> Bool {
        guard showFocusMode else { return false }
        guard !isApplyingUndo else { return false }
        guard oldValue != newValue else { return false }
        guard cardID == (editingCardID ?? focusModeEditorCardID) else { return false }
        return true
    }

    private func syncFocusModeContentChangeEditorOffsetIfNeeded() -> Bool {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return true }
        guard !isReferenceTextView(textView) else { return false }
        normalizeSingleTextEditorOffsetIfNeeded(textView, reason: "content-change-sync")
        return true
    }

    private func shouldSuppressFocusModeProgrammaticContentChange(cardID: UUID, newValue: String) -> Bool {
        if Date() < focusProgrammaticContentSuppressUntil {
            focusLastCommittedContentByCard[cardID] = newValue
            return true
        }
        return false
    }

    private func isFocusModeResponderComposingText() -> Bool {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            return textView.hasMarkedText()
        }
        return false
    }

    private func prepareFocusTypingCoalescingSessionIfNeeded(cardID: UUID, oldValue: String, now: Date) {
        let shouldBreakByGap = now.timeIntervalSince(focusTypingLastEditAt) > focusTypingIdleInterval
        let shouldBreakByCard = focusTypingCoalescingCardID != nil && focusTypingCoalescingCardID != cardID
        if shouldBreakByGap || shouldBreakByCard {
            finalizeFocusTypingCoalescing(reason: shouldBreakByCard ? "typing-card-switch" : "typing-gap")
        }

        if focusTypingCoalescingBaseState == nil {
            let committedOld = focusLastCommittedContentByCard[cardID] ?? oldValue
            focusTypingCoalescingBaseState = captureScenarioState(
                overridingContentForCardID: cardID,
                overridingContent: committedOld
            )
            focusTypingCoalescingCardID = cardID
        }
    }

    private func shouldFinalizeFocusTypingForReturnBoundary(
        delta: (prefix: Int, oldChangedLength: Int, newChangedLength: Int, inserted: String)
    ) -> Bool {
        guard focusPendingReturnBoundary else { return false }
        focusPendingReturnBoundary = false
        if delta.newChangedLength > 0 && delta.inserted.contains("\n") {
            finalizeFocusTypingCoalescing(reason: "typing-boundary-return")
            return true
        }
        return false
    }

    private func finalizeFocusTypingForStrongBoundaryIfNeeded(
        newValue: String,
        delta: (prefix: Int, oldChangedLength: Int, newChangedLength: Int, inserted: String)
    ) {
        if isStrongTextBoundaryChange(newValue: newValue, delta: delta) {
            finalizeFocusTypingCoalescing(reason: "typing-boundary")
        }
    }

    func handleFocusModeSelectionChanged() {
        guard showFocusMode else { return }

        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            guard !isReferenceTextView(textView) else { return }
            normalizeSingleTextEditorOffsetIfNeeded(textView, reason: "selection-change-sync")
        }
        
        guard focusTypingCoalescingBaseState != nil else { return }
        if Date().timeIntervalSince(focusTypingLastEditAt) > focusTypingIdleInterval {
            finalizeFocusTypingCoalescing(reason: "selection-change")
        }
    }

    func commitFocusModeCardEditIfNeeded() {
        guard showFocusMode else { return }
        guard let currentID = editingCardID, let currentCard = findCard(by: currentID) else { return }
        while currentCard.content.hasSuffix("\n") { currentCard.content.removeLast() }
        let changed = editingStartContent != currentCard.content
        guard changed else { return }
        focusLastCommittedContentByCard[currentID] = currentCard.content
        store.saveAll()
        takeSnapshot()
    }

    func applyFocusModeCaretWithRetry(expectedCardID: UUID, location: Int, retries: Int, requestID: Int) {
        guard let expectedCard = resolveFocusModeCaretRetryExpectedCard(
            expectedCardID: expectedCardID,
            requestID: requestID
        ) else { return }
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            handleFocusModeCaretRetryWithResponder(
                textView: textView,
                expectedCard: expectedCard,
                expectedCardID: expectedCardID,
                location: location,
                retries: retries,
                requestID: requestID
            )
            return
        }
        handleFocusModeCaretRetryWithoutResponder(
            expectedCardID: expectedCardID,
            location: location,
            retries: retries,
            requestID: requestID
        )
    }

    private func resolveFocusModeCaretRetryExpectedCard(
        expectedCardID: UUID,
        requestID: Int
    ) -> SceneCard? {
        guard showFocusMode else { return nil }
        guard editingCardID == expectedCardID else { return nil }
        guard requestID == focusModeCaretRequestID else { return nil }
        focusModeEditorCardID = expectedCardID
        return findCard(by: expectedCardID)
    }

    private func handleFocusModeCaretRetryWithResponder(
        textView: NSTextView,
        expectedCard: SceneCard,
        expectedCardID: UUID,
        location: Int,
        retries: Int,
        requestID: Int
    ) {
        let responderID = ObjectIdentifier(textView)
        if shouldRetryFocusModeCaretForResponder(
            textView: textView,
            responderID: responderID,
            expectedContent: expectedCard.content,
            expectedCardID: expectedCardID,
            location: location,
            retries: retries,
            requestID: requestID
        ) {
            return
        }
        applyFocusModeCaretSelection(
            textView: textView,
            responderID: responderID,
            expectedCardID: expectedCardID,
            requestedLocation: location,
            requestID: requestID
        )
    }

    private func shouldRetryFocusModeCaretForResponder(
        textView: NSTextView,
        responderID: ObjectIdentifier,
        expectedContent: String,
        expectedCardID: UUID,
        location: Int,
        retries: Int,
        requestID: Int
    ) -> Bool {
        if shouldRetryFocusModeCaretForExcludedResponder(
            responderID: responderID,
            expectedCardID: expectedCardID,
            location: location,
            retries: retries,
            requestID: requestID
        ) {
            return true
        }
        if shouldRetryFocusModeCaretForResponderCardMismatch(
            responderID: responderID,
            expectedCardID: expectedCardID,
            location: location,
            retries: retries,
            requestID: requestID
        ) {
            return true
        }
        return shouldRetryFocusModeCaretForStaleResponderContent(
            textView: textView,
            expectedContent: expectedContent,
            expectedCardID: expectedCardID,
            location: location,
            retries: retries,
            requestID: requestID
        )
    }

    private func handleFocusModeCaretRetryWithoutResponder(
        expectedCardID: UUID,
        location: Int,
        retries: Int,
        requestID: Int
    ) {
        guard retries > 0 else {
            completeFocusUndoSelectionEnsureIfNeeded(
                requestID: requestID,
                reason: "undo-restore-timeout",
                onMainAsync: false
            )
            return
        }
        scheduleFocusModeCaretRetry(
            expectedCardID: expectedCardID,
            location: location,
            retries: retries,
            requestID: requestID,
            delay: 0.02
        )
    }

    private func shouldRetryFocusModeCaretForExcludedResponder(
        responderID: ObjectIdentifier,
        expectedCardID: UUID,
        location: Int,
        retries: Int,
        requestID: Int
    ) -> Bool {
        guard let excludedID = focusExcludedResponderObjectID else { return false }
        let isWithinExclusionWindow = Date() < focusExcludedResponderUntil
        if isWithinExclusionWindow && responderID == excludedID {
            scheduleFocusModeCaretRetry(
                expectedCardID: expectedCardID,
                location: location,
                retries: retries,
                requestID: requestID,
                delay: 0.012
            )
            return true
        }
        if !isWithinExclusionWindow || responderID != excludedID {
            clearFocusModeExcludedResponder()
        }
        return false
    }

    private func shouldRetryFocusModeCaretForResponderCardMismatch(
        responderID: ObjectIdentifier,
        expectedCardID: UUID,
        location: Int,
        retries: Int,
        requestID: Int
    ) -> Bool {
        guard let mappedCardID = focusResponderCardByObjectID[responderID], mappedCardID != expectedCardID else {
            return false
        }
        scheduleFocusModeCaretRetry(
            expectedCardID: expectedCardID,
            location: location,
            retries: retries,
            requestID: requestID,
            delay: 0.012
        )
        return true
    }

    private func shouldRetryFocusModeCaretForStaleResponderContent(
        textView: NSTextView,
        expectedContent: String,
        expectedCardID: UUID,
        location: Int,
        retries: Int,
        requestID: Int
    ) -> Bool {
        // Ignore stale responder from previous card until focus switches.
        guard textView.string != expectedContent else { return false }
        scheduleFocusModeCaretRetry(
            expectedCardID: expectedCardID,
            location: location,
            retries: retries,
            requestID: requestID,
            delay: 0.02
        )
        return true
    }

    private func applyFocusModeCaretSelection(
        textView: NSTextView,
        responderID: ObjectIdentifier,
        expectedCardID: UUID,
        requestedLocation: Int,
        requestID: Int
    ) {
        textView.window?.makeFirstResponder(textView)
        let length = (textView.string as NSString).length
        let safe = max(0, min(requestedLocation, length))
        textView.setSelectedRange(NSRange(location: safe, length: 0))
        focusResponderCardByObjectID[responderID] = expectedCardID
        focusProgrammaticCaretExpectedCardID = expectedCardID
        focusProgrammaticCaretExpectedLocation = safe
        focusProgrammaticCaretSelectionIgnoreUntil = Date().addingTimeInterval(0.22)
        clearFocusModeExcludedResponder()
        completeFocusUndoSelectionEnsureIfNeeded(
            requestID: requestID,
            reason: "undo-restore-responder",
            onMainAsync: true
        )
    }

    private func clearFocusModeExcludedResponder() {
        focusExcludedResponderObjectID = nil
        focusExcludedResponderUntil = .distantPast
    }

    private func scheduleFocusModeCaretRetry(
        expectedCardID: UUID,
        location: Int,
        retries: Int,
        requestID: Int,
        delay: Double
    ) {
        guard retries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            applyFocusModeCaretWithRetry(
                expectedCardID: expectedCardID,
                location: location,
                retries: retries - 1,
                requestID: requestID
            )
        }
    }

    private func completeFocusUndoSelectionEnsureIfNeeded(
        requestID: Int,
        reason: String,
        onMainAsync: Bool
    ) {
        guard focusUndoSelectionEnsureRequestID == requestID else { return }
        focusUndoSelectionEnsureRequestID = nil
        focusUndoSelectionEnsureSuppressed = false

        let ensure: () -> Void = {
            requestFocusModeCaretEnsure(typewriter: false, delay: 0.0, force: true, reason: reason)
        }
        if onMainAsync {
            DispatchQueue.main.async(execute: ensure)
        } else {
            ensure()
        }
    }

    func toggleFocusMode() {
        let entering = !showFocusMode
        if entering {
            guard let target = resolveFocusModeEntryTargetCard() else { return }
            enterFocusMode(with: target)
        } else {
            exitFocusMode()
        }
        applyFocusModeVisibilityState(entering: entering)
        schedulePostFocusModeToggleFocusUpdate()
    }

    private func resolveFocusModeEntryTargetCard() -> SceneCard? {
        focusPendingProgrammaticBeginEditCardID = nil
        return activeCardID.flatMap({ findCard(by: $0) }) ?? scenario.rootCards.first
    }

    private func enterFocusMode(with target: SceneCard) {
        if let location = resolvedMainCaretLocation(for: target) {
            pendingFocusModeEntryCaretHint = (target.id, location)
        } else {
            pendingFocusModeEntryCaretHint = nil
        }
        beginFocusModeEditing(target, cursorToEnd: false)
        DispatchQueue.main.async {
            requestFocusModeOffsetNormalization(includeActive: true, force: true, reason: "focus-enter-initial")
            scheduleFocusModeOffsetNormalizationBurst(includeActive: true)
        }
    }

    private func exitFocusMode() {
        pendingFocusModeEntryCaretHint = nil
        focusPendingProgrammaticBeginEditCardID = nil
        finishEditing()
        focusModeEditorCardID = nil
        clearFocusBoundaryArm()
        stopFocusModeKeyMonitor()
        restoreMainKeyboardFocus()
    }

    private func applyFocusModeVisibilityState(entering: Bool) {
        withAnimation(quickEaseAnimation) {
            showFocusMode = entering
            if entering {
                showTimeline = false
                showHistoryBar = false
                showAIChat = false
                exitPreviewMode()
                searchText = ""
                isSearchFocused = false
                isNamedSnapshotSearchFocused = false
            }
        }
    }

    private func schedulePostFocusModeToggleFocusUpdate() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if !showFocusMode {
                restoreMainKeyboardFocus()
            } else {
                isMainViewFocused = true
            }
        }
    }

    func restoreMainKeyboardFocus() {
        let delays: [Double] = [0.0, 0.03, 0.08]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                isSearchFocused = false
                isNamedSnapshotSearchFocused = false
                NSApp.keyWindow?.makeFirstResponder(nil)
                isMainViewFocused = true
            }
        }
    }
}
