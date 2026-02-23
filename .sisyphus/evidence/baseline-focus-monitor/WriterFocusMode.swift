import SwiftUI
import AppKit

extension ScenarioWriterView {

    @ViewBuilder
    func focusModeCanvas(size: CGSize) -> some View {
        let cards = focusedColumnCards()
        ZStack {
            Color.black.opacity(0.90)
                .ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: max(48, size.height * 0.08))
                        VStack(spacing: 0) {
                            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                                focusModeCardBlock(card)
                                    .id("focus-card-\(card.id)")
                                if index < cards.count - 1 {
                                    let next = cards[index + 1]
                                    let parentChanged = card.parent?.id != next.parent?.id
                                    Rectangle()
                                        .fill(
                                            parentChanged
                                            ? Color(hue: 0.61, saturation: 0.5, brightness: 0.95).opacity(0.85)
                                            : (appearance == "light" ? Color.black.opacity(0.08) : Color.white.opacity(0.12))
                                        )
                                        .frame(height: parentChanged ? 2 : 1)
                                        .padding(.horizontal, parentChanged ? 20 : 0)
                                }
                            }
                        }
                        .background(appearance == "light" ? Color.white : Color(white: 0.10))
                        .overlay(
                            Rectangle()
                                .stroke(appearance == "light" ? Color.black.opacity(0.10) : Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .frame(maxWidth: 916)
                        .background(
                            GeometryReader { geometry in
                                Color.clear
                                    .preference(
                                        key: FocusModePanelFramePreferenceKey.self,
                                        value: geometry.frame(in: .named("focus-mode-canvas"))
                                    )
                            }
                        )
                        .padding(.horizontal, 32)
                        Color.clear.frame(height: max(72, size.height * 0.12))
                    }
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: activeCardID) { _, newID in
                    guard let id = newID else { return }
                    requestFocusModeOffsetNormalization(includeActive: true, force: true, reason: "active-card-change")
                    let matchesPendingProgrammaticBegin = (focusPendingProgrammaticBeginEditCardID == id)
                    if matchesPendingProgrammaticBegin {
                        focusPendingProgrammaticBeginEditCardID = nil
                    }
                    if suppressFocusModeScrollOnce {
                        suppressFocusModeScrollOnce = false
                        if matchesPendingProgrammaticBegin {
                            if showFocusMode {
                                focusModeEditorCardID = id
                            }
                            return
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
                        return
                    }
                    let anchor = focusModeNextCardScrollAnchor ?? .center
                    let shouldAnimate = focusModeNextCardScrollAnimated
                    focusModeNextCardScrollAnchor = nil
                    focusModeNextCardScrollAnimated = true
                    if shouldAnimate {
                        withAnimation(quickEaseAnimation) {
                            proxy.scrollTo("focus-card-\(id)", anchor: anchor)
                        }
                    } else {
                        proxy.scrollTo("focus-card-\(id)", anchor: anchor)
                    }
                    if showFocusMode {
                        focusModeEditorCardID = id
                    }
                    if showFocusMode, editingCardID != id, let card = findCard(by: id) {
                        DispatchQueue.main.async {
                            beginFocusModeEditing(card, cursorToEnd: false)
                        }
                    }
                    scheduleFocusModeOffsetNormalizationBurst(includeActive: false)
                }
                .onChange(of: focusModeEntryScrollTick) { _, _ in
                    guard showFocusMode else { return }
                    guard let id = activeCardID else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo("focus-card-\(id)", anchor: .center)
                    }
                }
            }
        }
        .coordinateSpace(name: "focus-mode-canvas")
        .onPreferenceChange(FocusModePanelFramePreferenceKey.self) { frame in
            if !frame.isEmpty {
                let widthChanged = abs(frame.width - focusModePanelFrame.width) > 0.5
                focusModePanelFrame = frame
                if widthChanged {
                    focusObservedBodyHeightByCardID.removeAll()
                    requestFocusModeOffsetNormalization(includeActive: true, force: true, reason: "panel-width-change")
                }
            }
        }
        .simultaneousGesture(
            SpatialTapGesture().onEnded { value in
                guard showFocusMode else { return }
                guard !focusModePanelFrame.isEmpty else { return }
                let inPanel = focusModePanelFrame.contains(value.location)
                if !inPanel {
                    toggleFocusMode()
                }
            }
        )
    }

    @ViewBuilder
    func focusModeCardBlock(_ card: SceneCard) -> some View {
        FocusModeCardEditor(
            card: card,
            isActive: activeCardID == card.id,
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
    }

    func activateFocusModeCardFromClick(_ card: SceneCard) {
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
        let levelsData = getLevelsWithParents()
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
            if !showFocusMode { return event }
            if showDeleteAlert {
                let hasChildren = selectedCardsForDeletion().contains { !$0.children.isEmpty }
                let isEscape = event.keyCode == 53
                let isReturn = event.keyCode == 36 || event.keyCode == 76
                if isEscape || (hasChildren && isReturn) {
                    DispatchQueue.main.async {
                        showDeleteAlert = false
                        isMainViewFocused = true
                    }
                    return nil
                }
            }
            let flags = event.modifierFlags
            let isPlainEscape = event.keyCode == 53 &&
                !flags.contains(.command) &&
                !flags.contains(.option) &&
                !flags.contains(.control) &&
                !flags.contains(.shift)
            if isPlainEscape {
                DispatchQueue.main.async {
                    toggleFocusMode()
                }
                return nil
            }
            let isCmdOnly = flags.contains(.command) && !flags.contains(.option) && !flags.contains(.control) && !flags.contains(.shift)
            let isCmdShift = flags.contains(.command) && flags.contains(.shift) && !flags.contains(.option) && !flags.contains(.control)
            if isCmdShift && (event.keyCode == 51 || event.keyCode == 117) { // delete / forward-delete
                if event.isARepeat { return nil }
                DispatchQueue.main.async {
                    if let targetID = focusModeEditorCardID ?? editingCardID ?? activeCardID {
                        selectedCardIDs = [targetID]
                        if let target = findCard(by: targetID), activeCardID != targetID {
                            changeActiveCard(to: target, shouldFocusMain: false)
                        }
                    }
                    deleteSelectedCard()
                }
                return nil
            }
            if isCmdOnly && (event.keyCode == 36 || event.keyCode == 76) { // return / keypad enter
                if event.isARepeat { return nil }
                DispatchQueue.main.async {
                    insertSibling(above: false)
                }
                return nil
            }
            let isCmdOpt = flags.contains(.command) && flags.contains(.option) && !flags.contains(.control)
            if isCmdOpt && (event.keyCode == 126 || event.keyCode == 125) { // up / down
                if event.isARepeat { return nil }
                let createAbove = (event.keyCode == 126)
                DispatchQueue.main.async {
                    insertSibling(above: createAbove)
                }
                return nil
            }
            if event.keyCode == 36 || event.keyCode == 76 { // return / keypad enter
                let isPlainReturn = !flags.contains(.command) && !flags.contains(.option) && !flags.contains(.control)
                if isPlainReturn,
                   let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
                    let text = textView.string as NSString
                    let caret = min(max(0, textView.selectedRange().location), text.length)
                    focusPendingReturnBoundary = lineHasSignificantContentBeforeBreak(in: text, breakIndex: caret)
                } else if !isPlainReturn {
                    focusPendingReturnBoundary = false
                }
                return event
            }
            if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) || event.modifierFlags.contains(.control) {
                return event
            }
            if focusTypewriterEnabled && isTypewriterTriggerKey(event) {
                if let textView = NSApp.keyWindow?.firstResponder as? NSTextView, textView.hasMarkedText() {
                    focusTypewriterDeferredUntilCompositionEnd = true
                    return event
                }
                DispatchQueue.main.async {
                    requestFocusModeCaretEnsure(typewriter: true, delay: 0.02, reason: "typewriter-key")
                }
                return event
            }
            if event.keyCode != 126 && event.keyCode != 125 { return event } // up/down only
            guard let currentID = focusModeEditorCardID ?? editingCardID,
                  let currentCard = findCard(by: currentID) else { return event }
            guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
                focusModeEditorCardID = currentID
                return nil
            }
            let cards = focusedColumnCards()
            guard let currentIndex = cards.firstIndex(where: { $0.id == currentID }) else { return event }
            let cursor = textView.selectedRange().location
            let length = (currentCard.content as NSString).length
            let visualBoundary = focusCaretVisualBoundaryState(textView: textView, cursor: cursor)
            let atTopBoundary = (cursor == 0) && (visualBoundary?.isTop ?? true)
            let atBottomBoundary = (cursor == length) && (visualBoundary?.isBottom ?? true)
            let isBoundary = (event.keyCode == 126)
                ? (atTopBoundary && currentIndex > 0)
                : (atBottomBoundary && currentIndex < cards.count - 1)

            if event.keyCode == 126 { // up
                guard isBoundary else {
                    clearFocusBoundaryArm()
                    // Cancel deferred boundary caret applies once user continues in-card navigation.
                    focusModeCaretRequestID += 1
                    return event
                }
                if event.isARepeat {
                    return nil
                }
                clearFocusBoundaryArm()
                let previous = cards[currentIndex - 1]
                focusExcludedResponderObjectID = ObjectIdentifier(textView)
                focusExcludedResponderUntil = Date().addingTimeInterval(0.10)
                // Invalidate any pending caret applies from a previous transition before scheduling a new one.
                focusModeCaretRequestID += 1
                DispatchQueue.main.async {
                    beginFocusModeEditing(
                        previous,
                        cursorToEnd: true,
                        preserveViewportOnSwitch: true
                    )
                }
                return nil
            } else { // down
                guard isBoundary else {
                    clearFocusBoundaryArm()
                    // Cancel deferred boundary caret applies once user continues in-card navigation.
                    focusModeCaretRequestID += 1
                    return event
                }
                if event.isARepeat {
                    return nil
                }
                clearFocusBoundaryArm()
                let next = cards[currentIndex + 1]
                focusExcludedResponderObjectID = ObjectIdentifier(textView)
                focusExcludedResponderUntil = Date().addingTimeInterval(0.10)
                // Invalidate any pending caret applies from a previous transition before scheduling a new one.
                focusModeCaretRequestID += 1
                DispatchQueue.main.async {
                    beginFocusModeEditing(
                        next,
                        cursorToEnd: false,
                        preserveViewportOnSwitch: true
                    )
                }
                return nil
            }
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
        focusModeScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            guard showFocusMode else { return event }
            let shouldNormalize = event.phase == .ended || event.momentumPhase == .ended
            DispatchQueue.main.async {
                if shouldNormalize {
                    requestFocusModeOffsetNormalization(reason: "scroll-ended")
                }
            }
            return event
        }
    }

    func stopFocusModeScrollMonitor() {
        if let monitor = focusModeScrollMonitor {
            NSEvent.removeMonitor(monitor)
            focusModeScrollMonitor = nil
        }
    }

    func focusModeTargetContainerWidth(for textView: NSTextView) -> CGFloat {
        let viewportWidth = textView.enclosingScrollView?.contentView.bounds.width ?? textView.bounds.width
        return max(1, viewportWidth)
    }

    @discardableResult
    func applyFocusModeTextViewGeometryIfNeeded(_ textView: NSTextView, reason: String = "focus-mode") -> Bool {
        guard showFocusMode else { return false }
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
        if let scrollView = textView.enclosingScrollView {
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
        }
        if textView.textContainerInset != .zero {
            textView.textContainerInset = .zero
            changed = true
        }
        guard let textContainer = textView.textContainer else { return changed }
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
        _ = reason
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
        guard showFocusMode else { return (0, 0, 0, 0) }
        guard let root = NSApp.keyWindow?.contentView else { return (0, 0, 0, 0) }
        let activeTextView = NSApp.keyWindow?.firstResponder as? NSTextView
        let focusedCardIDs = Set(focusedColumnCards().map(\.id))
        var seen = Set<ObjectIdentifier>()
        var scanned = 0
        var resetCount = 0
        var skippedActive = 0
        var observedUpdates = 0
        var observedByCardID = focusObservedBodyHeightByCardID

        for textView in collectTextViews(in: root) {
            let identity = ObjectIdentifier(textView)
            if seen.contains(identity) { continue }
            seen.insert(identity)
            scanned += 1

            _ = applyFocusModeTextViewGeometryIfNeeded(textView, reason: "offset-normalization")

            let responderID = ObjectIdentifier(textView)
            var mappedCardID = focusResponderCardByObjectID[responderID]
            if mappedCardID == nil, let activeTextView, textView === activeTextView {
                mappedCardID = focusModeEditorCardID ?? editingCardID ?? activeCardID
            }
            if let mappedCardID, focusedCardIDs.contains(mappedCardID) {
                rememberFocusResponderCardMapping(textView: textView)
                if let observed = observedFocusModeBodyHeight(for: textView),
                   abs((observedByCardID[mappedCardID] ?? 0) - observed) > 0.5 {
                    observedByCardID[mappedCardID] = observed
                    observedUpdates += 1
                }
            }

            if !includeActive, let activeTextView, textView === activeTextView {
                skippedActive += 1
                continue
            }
            guard let scrollView = textView.enclosingScrollView else { continue }
            let origin = scrollView.contentView.bounds.origin
            let shouldResetOrigin = abs(origin.x) > 0.5 || abs(origin.y) > 0.5
            if shouldResetOrigin {
                scrollView.contentView.setBoundsOrigin(.zero)
                scrollView.reflectScrolledClipView(scrollView.contentView)
                resetCount += 1
            }
        }

        observedByCardID = observedByCardID.filter { focusedCardIDs.contains($0.key) }
        if observedByCardID != focusObservedBodyHeightByCardID {
            focusObservedBodyHeightByCardID = observedByCardID
        }
        return (scanned, resetCount, skippedActive, observedUpdates)
    }

    func requestFocusModeOffsetNormalization(
        includeActive: Bool = false,
        force: Bool = false,
        reason: String = "unspecified"
    ) {
        let now = Date()
        if !force {
            let elapsed = now.timeIntervalSince(focusOffsetNormalizationLastAt)
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

    func collectScrollViews(in root: NSView) -> [NSScrollView] {
        var result: [NSScrollView] = []
        var stack: [NSView] = [root]
        while let view = stack.popLast() {
            if let scrollView = view as? NSScrollView {
                result.append(scrollView)
            }
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
                if showFocusMode {
                    guard let textView =
                        (notification.object as? NSTextView) ??
                        (NSApp.keyWindow?.firstResponder as? NSTextView)
                    else {
                        return
                    }
                    guard (NSApp.keyWindow?.firstResponder as? NSTextView) === textView else { return }
                    rememberFocusResponderCardMapping(textView: textView)
                    if focusUndoSelectionEnsureSuppressed {
                        return
                    }
                    let responderID = ObjectIdentifier(textView)
                    let selected = textView.selectedRange()
                    let textLength = (textView.string as NSString).length
                    let trackedCardID =
                        focusResponderCardByObjectID[responderID] ??
                        (focusModeEditorCardID ?? editingCardID ?? activeCardID)
                    let isDuplicateSelection =
                        focusSelectionLastCardID == trackedCardID &&
                        focusSelectionLastLocation == selected.location &&
                        focusSelectionLastLength == selected.length &&
                        focusSelectionLastTextLength == textLength &&
                        focusSelectionLastResponderID == responderID
                    if isDuplicateSelection {
                        if focusTypewriterDeferredUntilCompositionEnd, !textView.hasMarkedText() {
                            focusTypewriterDeferredUntilCompositionEnd = false
                            requestFocusModeCaretEnsure(typewriter: true, delay: 0.0, reason: "composition-end")
                        }
                        return
                    }
                    focusSelectionLastCardID = trackedCardID
                    focusSelectionLastLocation = selected.location
                    focusSelectionLastLength = selected.length
                    focusSelectionLastTextLength = textLength
                    focusSelectionLastResponderID = responderID
                    handleFocusModeSelectionChanged()
                    if !textView.hasMarkedText() {
                        let now = Date()
                        let elapsed = now.timeIntervalSince(focusCaretEnsureLastScheduledAt)
                        let delay = max(0, focusCaretSelectionEnsureMinInterval - elapsed)
                        focusCaretEnsureLastScheduledAt = now.addingTimeInterval(delay)
                        requestFocusModeCaretEnsure(typewriter: false, delay: delay, reason: "selection-change")
                    }
                    if focusTypewriterDeferredUntilCompositionEnd,
                       !textView.hasMarkedText() {
                        focusTypewriterDeferredUntilCompositionEnd = false
                        requestFocusModeCaretEnsure(typewriter: true, delay: 0.0, reason: "composition-end")
                    }
                }
            }
        }
        DispatchQueue.main.async {
            requestFocusModeCaretEnsure(typewriter: false, reason: "caret-monitor-start")
            scheduleFocusModeOffsetNormalizationBurst(includeActive: false)
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
        focusUndoSelectionEnsureSuppressed = false
        focusUndoSelectionEnsureRequestID = nil
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
            if focusUndoSelectionEnsureSuppressed && !force {
                focusCaretPendingTypewriter = false
                return
            }
            guard showFocusMode else {
                focusCaretPendingTypewriter = false
                focusTypewriterDeferredUntilCompositionEnd = false
                return
            }
            guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
                focusCaretPendingTypewriter = false
                return
            }
            var runTypewriter = focusTypewriterEnabled && focusCaretPendingTypewriter
            focusCaretPendingTypewriter = false
            if runTypewriter && textView.hasMarkedText() {
                focusTypewriterDeferredUntilCompositionEnd = true
                runTypewriter = false
            }
            if !textView.hasMarkedText() {
                _ = applyFocusModeTextViewGeometryIfNeeded(textView, reason: "caret-ensure")
                let typingElapsed = Date().timeIntervalSince(focusTypingLastEditAt)
                let innerOrigin = textView.enclosingScrollView?.contentView.bounds.origin ?? .zero
                let shouldDeferSingleNormalize = typingElapsed < 0.18 && abs(innerOrigin.y) < 64
                if !shouldDeferSingleNormalize {
                    normalizeSingleTextEditorOffsetIfNeeded(textView, reason: "caret-ensure")
                }
            }
            ensureFocusModeCaretVisible(typewriter: runTypewriter)
            requestFocusModeOffsetNormalization(reason: "caret-ensure")
        }
        focusCaretEnsureWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func ensureFocusModeCaretVisible(typewriter: Bool = false) {
        guard showFocusMode else { return }
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        guard let outerScrollView = outerScrollView(containing: textView) else { return }
        guard let outerDocumentView = outerScrollView.documentView else { return }
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }

        let textLength = (textView.string as NSString).length
        let sel = textView.selectedRange()
        let selStart = min(sel.location, textLength)
        let selEnd = min(sel.location + sel.length, textLength)

        func caretRectInDocument(at location: Int) -> CGRect {
            let gr = layoutManager.glyphRange(forCharacterRange: NSRange(location: location, length: 0), actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: gr, in: textContainer)
            rect.origin.x += textView.textContainerInset.width
            rect.origin.y += textView.textContainerInset.height
            if rect.height < fontSize {
                rect.size.height = fontSize + 2
            }
            return outerDocumentView.convert(rect, from: textView)
        }

        let startRect = caretRectInDocument(at: selStart)
        let endRect = (sel.length > 0) ? caretRectInDocument(at: selEnd) : startRect
        // For typewriter mode, use the end of selection as the primary caret position
        let caretInDocument = (sel.length > 0) ? endRect : startRect

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

        var targetY = visible.origin.y
        if focusTypewriterEnabled && typewriter {
            let baseline = CGFloat(min(max(focusTypewriterBaseline, 0.40), 0.80))
            targetY = caretInDocument.midY - (visible.height * baseline)
        } else {
            if endRect.maxY > maxVisibleY {
                targetY = endRect.maxY - (visible.height - bottomPadding)
            } else if startRect.minY < minVisibleY {
                targetY = max(minY, startRect.minY - topPadding)
            }
        }

        let clampedY = min(max(minY, targetY), maxY)
        let targetYSnapped = typewriter ? round(clampedY) : clampedY
        let deadZone: CGFloat = typewriter ? 14.0 : 1.0
        if abs(targetYSnapped - visible.origin.y) > deadZone {
            outerScrollView.contentView.setBoundsOrigin(NSPoint(x: visible.origin.x, y: targetYSnapped))
            outerScrollView.reflectScrolledClipView(outerScrollView.contentView)
        }
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
        let switchingToDifferentCard = (editingCardID != card.id)
        if showFocusMode, activeCardID != nil, activeCardID != card.id {
            finalizeFocusTypingCoalescing(reason: "focus-card-switch")
        }
        clearFocusBoundaryArm()
        if showFocusMode, editingCardID != nil, editingCardID != card.id {
            commitFocusModeCardEditIfNeeded()
        } else if editingCardID != nil, editingCardID != card.id {
            finishEditing()
        }
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
        let length = (card.content as NSString).length
        let location: Int? = {
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
        }()
        focusModeCaretRequestID += 1
        let requestID = focusModeCaretRequestID
        if let location {
            applyFocusModeCaretWithRetry(expectedCardID: card.id, location: location, retries: 10, requestID: requestID)
            // Focus handoff in SwiftUI can be late; re-apply once more after layout settles.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                applyFocusModeCaretWithRetry(expectedCardID: card.id, location: location, retries: 4, requestID: requestID)
            }
        }
        // Boundary navigation can race with the first focus handoff right after entering focus mode.
        // Re-apply once after the scroll animation window to pin the caret deterministically.
        if let location, cardScrollAnchor != nil || preserveViewportOnSwitch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                applyFocusModeCaretWithRetry(expectedCardID: card.id, location: location, retries: 4, requestID: requestID)
            }
            // Guard against transient off-screen caret during card switch/scroll handoff.
            scheduleFocusModeCaretEnsureBurst()
        }
        // Entry pass: avoid first transition drift when immediately moving to another card.
        if let location, cardScrollAnchor == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                applyFocusModeCaretWithRetry(expectedCardID: card.id, location: location, retries: 4, requestID: requestID)
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
        guard showFocusMode else { return }
        guard !isApplyingUndo else { return }
        guard oldValue != newValue else { return }
        guard cardID == (editingCardID ?? focusModeEditorCardID) else { return }
        let delta = utf16ChangeDelta(oldValue: oldValue, newValue: newValue)
        if Date() < focusProgrammaticContentSuppressUntil {
            focusLastCommittedContentByCard[cardID] = newValue
            return
        }

        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView, textView.hasMarkedText() {
            return
        }

        let now = Date()
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

        focusTypingLastEditAt = now
        focusLastCommittedContentByCard[cardID] = newValue
        scheduleFocusTypingIdleFinalize()

        if focusPendingReturnBoundary {
            focusPendingReturnBoundary = false
            if delta.newChangedLength > 0 && delta.inserted.contains("\n") {
                finalizeFocusTypingCoalescing(reason: "typing-boundary-return")
                return
            }
        }

        if isStrongTextBoundaryChange(newValue: newValue, delta: delta) {
            finalizeFocusTypingCoalescing(reason: "typing-boundary")
        }
    }

    func handleFocusModeSelectionChanged() {
        guard showFocusMode else { return }
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
        guard showFocusMode else { return }
        guard editingCardID == expectedCardID else { return }
        guard requestID == focusModeCaretRequestID else { return }
        focusModeEditorCardID = expectedCardID
        guard let expectedCard = findCard(by: expectedCardID) else { return }
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            let responderID = ObjectIdentifier(textView)
            if let excludedID = focusExcludedResponderObjectID {
                let isWithinExclusionWindow = Date() < focusExcludedResponderUntil
                if isWithinExclusionWindow && responderID == excludedID {
                    if retries > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) {
                            applyFocusModeCaretWithRetry(expectedCardID: expectedCardID, location: location, retries: retries - 1, requestID: requestID)
                        }
                    }
                    return
                }
                if !isWithinExclusionWindow || responderID != excludedID {
                    focusExcludedResponderObjectID = nil
                    focusExcludedResponderUntil = .distantPast
                }
            }
            if let mappedCardID = focusResponderCardByObjectID[responderID], mappedCardID != expectedCardID {
                if retries > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) {
                        applyFocusModeCaretWithRetry(expectedCardID: expectedCardID, location: location, retries: retries - 1, requestID: requestID)
                    }
                }
                return
            }
            // Ignore stale responder from previous card until focus switches.
            if textView.string != expectedCard.content {
                if retries > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                        applyFocusModeCaretWithRetry(expectedCardID: expectedCardID, location: location, retries: retries - 1, requestID: requestID)
                    }
                }
                return
            }
            textView.window?.makeFirstResponder(textView)
            let length = (textView.string as NSString).length
            let safe = max(0, min(location, length))
            textView.setSelectedRange(NSRange(location: safe, length: 0))
            focusResponderCardByObjectID[responderID] = expectedCardID
            focusExcludedResponderObjectID = nil
            focusExcludedResponderUntil = .distantPast
            if focusUndoSelectionEnsureRequestID == requestID {
                focusUndoSelectionEnsureRequestID = nil
                focusUndoSelectionEnsureSuppressed = false
                DispatchQueue.main.async {
                    requestFocusModeCaretEnsure(typewriter: false, delay: 0.0, force: true, reason: "undo-restore-responder")
                }
            }
            return
        }
        guard retries > 0 else {
            if focusUndoSelectionEnsureRequestID == requestID {
                focusUndoSelectionEnsureRequestID = nil
                focusUndoSelectionEnsureSuppressed = false
                requestFocusModeCaretEnsure(typewriter: false, delay: 0.0, force: true, reason: "undo-restore-timeout")
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            applyFocusModeCaretWithRetry(expectedCardID: expectedCardID, location: location, retries: retries - 1, requestID: requestID)
        }
    }

    func toggleFocusMode() {
        let entering = !showFocusMode
        if entering {
            focusPendingProgrammaticBeginEditCardID = nil
            guard let target = activeCardID.flatMap({ findCard(by: $0) }) ?? scenario.rootCards.first else { return }
            if let location = resolvedMainCaretLocation(for: target) {
                pendingFocusModeEntryCaretHint = (target.id, location)
            } else {
                pendingFocusModeEntryCaretHint = nil
            }
            beginFocusModeEditing(target, cursorToEnd: false)
        } else {
            pendingFocusModeEntryCaretHint = nil
            focusPendingProgrammaticBeginEditCardID = nil
            let exitingCardID = editingCardID ?? activeCardID
            finishEditing()
            pendingMainCanvasRestoreCardID = activeCardID ?? exitingCardID
            focusModeEditorCardID = nil
            clearFocusBoundaryArm()
            stopFocusModeKeyMonitor()
            restoreMainKeyboardFocus()
        }
        withAnimation(quickEaseAnimation) {
            showFocusMode = entering
            if entering {
                showTimeline = false
                showHistoryBar = false
                exitPreviewMode()
                searchText = ""
                isSearchFocused = false
                isNamedSnapshotSearchFocused = false
            }
        }
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
