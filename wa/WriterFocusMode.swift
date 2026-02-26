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
            Color.black.opacity(0.90)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    guard showFocusMode else { return }
                    toggleFocusMode()
                }
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
                        .background(focusModeCardsBackgroundColor)
                        .overlay(
                            Rectangle()
                                .stroke(appearance == "light" ? Color.black.opacity(0.10) : Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .frame(maxWidth: 916)
                        .padding(.horizontal, 32)
                        Color.clear.frame(height: max(72, size.height * 0.12))
                    }
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: activeCardID) { _, newID in
                    guard let id = newID else { return }
                    focusResponderCardByObjectID.removeAll()
                    
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
                    requestFocusModeOffsetNormalization(includeActive: false, force: true, reason: "active-card-change")
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
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: size.width) { oldWidth, newWidth in
            guard showFocusMode else { return }
            let widthChanged = abs(newWidth - oldWidth) > 0.5
            if widthChanged {
                focusObservedBodyHeightByCardID.removeAll()
                requestFocusModeOffsetNormalization(includeActive: false, force: true, reason: "canvas-width-change")
            }
        }
    }

    @ViewBuilder
    func focusModeCardBlock(_ card: SceneCard) -> some View {
        let isActiveCard = activeCardID == card.id
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
            let isReferenceWindowEvent = event.window?.identifier?.rawValue == ReferenceWindowConstants.windowID
            let isReferenceWindowKey = NSApp.keyWindow?.identifier?.rawValue == ReferenceWindowConstants.windowID
            if isReferenceWindowEvent || isReferenceWindowKey {
                return event
            }
            if !acceptsKeyboardInput { return event }
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
            if isCmdShift {
                let normalized = (event.charactersIgnoringModifiers ?? "").lowercased()
                if normalized == "t" || normalized == "ㅅ" || normalized == "ㅆ" {
                    DispatchQueue.main.async {
                        focusTypewriterEnabled = !focusTypewriterEnabledLive
                    }
                    return nil
                }
            }
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
            if focusTypewriterEnabledLive && isTypewriterTriggerKey(event) {
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
        
        var monitors: [Any] = []
        if let eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel], handler: { event in
            guard acceptsKeyboardInput else { return event }
            guard showFocusMode else { return event }
            let shouldNormalize = event.phase == .ended || event.momentumPhase == .ended
            DispatchQueue.main.async {
                if shouldNormalize {
                    requestFocusModeOffsetNormalization(reason: "scroll-ended")
                }
            }
            return event
        }) {
            monitors.append(eventMonitor)
        }
        
        // 텍스트 추가 시 자동으로 텍스트 뷰 내부 스크롤이 발생하는 현상(Jolt)을 원천 차단
        let boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard acceptsKeyboardInput else { return }
            guard showFocusMode else { return }
            guard let clipView = notification.object as? NSClipView else { return }
            let origin = clipView.bounds.origin
            guard abs(origin.x) > 0.5 || abs(origin.y) > 0.5 else { return }
            
            guard let scrollView = clipView.superview as? NSScrollView else { return }
            guard scrollView.documentView is NSTextView else { return }
            
            // TextEditor가 생성한 내부 ScrollView인지 확인 (스크롤바 및 배경 숨김 상태)
            guard !scrollView.hasVerticalScroller && !scrollView.hasHorizontalScroller && !scrollView.drawsBackground else { return }
            
            clipView.setBoundsOrigin(.zero)
        }
        monitors.append(boundsObserver)
        
        focusModeScrollMonitor = monitors
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
            if !scrollView.contentView.postsBoundsChangedNotifications {
                scrollView.contentView.postsBoundsChangedNotifications = true
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
        guard !isReferenceWindowFocused else { return (0, 0, 0, 0) }
        guard let root = NSApp.keyWindow?.contentView else { return (0, 0, 0, 0) }
        let activeTextView = NSApp.keyWindow?.firstResponder as? NSTextView
        let focusedCards = focusedColumnCards()
        let focusedCardIDs = Set(focusedCards.map(\.id))
        let activeFocusedCardID = focusModeEditorCardID ?? editingCardID ?? activeCardID

        let allEditableTextViews = collectTextViews(in: root).filter { textView in
            textView.isEditable && !isReferenceTextView(textView)
        }
        let rootBounds = root.bounds
        let rootCenterX = rootBounds.midX
        let strictMinWidth = max(280, rootBounds.width * 0.34)
        let looseMinWidth = max(220, rootBounds.width * 0.24)

        func sortedByVerticalPosition(_ views: [NSTextView]) -> [NSTextView] {
            views.sorted {
                let y1 = $0.convert(NSPoint.zero, to: nil).y
                let y2 = $1.convert(NSPoint.zero, to: nil).y
                return y1 > y2
            }
        }

        var textViews = allEditableTextViews.filter { textView in
            let frameInRoot = textView.convert(textView.bounds, to: root)
            guard frameInRoot.width >= strictMinWidth else { return false }
            let centerDistance = abs(frameInRoot.midX - rootCenterX)
            return centerDistance <= (rootBounds.width * 0.22)
        }

        if textViews.count < focusedCards.count {
            textViews = allEditableTextViews.filter { textView in
                let frameInRoot = textView.convert(textView.bounds, to: root)
                return frameInRoot.width >= looseMinWidth
            }
        }

        if textViews.count < focusedCards.count {
            textViews = allEditableTextViews
        }

        if textViews.count > focusedCards.count, !focusedCards.isEmpty {
            let ranked = textViews.sorted { lhs, rhs in
                let lhsFrame = lhs.convert(lhs.bounds, to: root)
                let rhsFrame = rhs.convert(rhs.bounds, to: root)
                let lhsDistance = abs(lhsFrame.midX - rootCenterX)
                let rhsDistance = abs(rhsFrame.midX - rootCenterX)
                if abs(lhsDistance - rhsDistance) > 1 {
                    return lhsDistance < rhsDistance
                }
                return lhsFrame.midY > rhsFrame.midY
            }
            textViews = Array(ranked.prefix(focusedCards.count))
        }

        textViews = sortedByVerticalPosition(textViews)

        if !focusedCards.isEmpty && !textViews.isEmpty {
            let pairCount = min(textViews.count, focusedCards.count)
            for i in 0 ..< pairCount {
                let identity = ObjectIdentifier(textViews[i])
                focusResponderCardByObjectID[identity] = focusedCards[i].id
            }
        }

        for tv in textViews {
            let identity = ObjectIdentifier(tv)
            if focusResponderCardByObjectID[identity] == nil,
               tv === activeTextView,
               let activeFocusedCardID,
               focusedCardIDs.contains(activeFocusedCardID) {
                focusResponderCardByObjectID[identity] = activeFocusedCardID
            }
        }

        var scanned = 0
        var resetCount = 0
        var skippedActive = 0
        var observedUpdates = 0
        var observedByCardID = focusObservedBodyHeightByCardID

        for textView in textViews {
            let identity = ObjectIdentifier(textView)
            scanned += 1

            let isActiveResponder = (activeTextView != nil && textView === activeTextView)
            let mappedCardID = focusResponderCardByObjectID[identity]
            let isFocusEditor = mappedCardID != nil && focusedCardIDs.contains(mappedCardID!)

            if isFocusEditor || isActiveResponder {
                _ = applyFocusModeTextViewGeometryIfNeeded(textView, reason: isActiveResponder ? "offset-normalization-active" : "offset-normalization-inactive")
            }

            if let mappedCardID, focusedCardIDs.contains(mappedCardID) {
                if let observed = observedFocusModeBodyHeight(for: textView),
                   abs((observedByCardID[mappedCardID] ?? 0) - observed) > 0.5 {
                    observedByCardID[mappedCardID] = observed
                    observedUpdates += 1
                }
            }

            if !includeActive, isActiveResponder {
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

        if focusedCardIDs.isEmpty {
            observedByCardID.removeAll()
        } else {
            observedByCardID = observedByCardID.filter { focusedCardIDs.contains($0.key) }
        }
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
                    guard !isReferenceWindowFocused else { return }
                    guard let textView =
                        (notification.object as? NSTextView) ??
                        (NSApp.keyWindow?.firstResponder as? NSTextView)
                    else {
                        return
                    }
                    guard !isReferenceTextView(textView) else { return }
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
                        
                    // 선택 영역의 활성 끝단(Active Edge) 계산 - 스크롤 충돌(Fighting) 방지
                    let selectedStart = min(max(0, selected.location), textLength)
                    let selectedEnd = min(max(selectedStart, selected.location + selected.length), textLength)
                    let previousRangeIsComparable =
                        focusSelectionLastCardID == trackedCardID &&
                        focusSelectionLastResponderID == responderID &&
                        focusSelectionLastLocation >= 0 &&
                        focusSelectionLastLength >= 0

                    if selected.length == 0 {
                        _focusSelectionActiveEdge = .end
                    } else if previousRangeIsComparable {
                        let previousStart = min(max(0, focusSelectionLastLocation), max(0, focusSelectionLastTextLength))
                        let previousEnd = min(
                            max(previousStart, focusSelectionLastLocation + max(0, focusSelectionLastLength)),
                            max(0, focusSelectionLastTextLength)
                        )
                        let movedStart = selectedStart != previousStart
                        let movedEnd = selectedEnd != previousEnd
                        if movedStart && !movedEnd {
                            _focusSelectionActiveEdge = .start
                        } else if !movedStart && movedEnd {
                            _focusSelectionActiveEdge = .end
                        } else if movedStart && movedEnd {
                            let startDelta = abs(selectedStart - previousStart)
                            let endDelta = abs(selectedEnd - previousEnd)
                            if startDelta > endDelta {
                                _focusSelectionActiveEdge = .start
                            } else if endDelta > startDelta {
                                _focusSelectionActiveEdge = .end
                            }
                        }
                    }

                    let transientProgrammaticSelectionIgnored: Bool = {
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
                    }()
                    if transientProgrammaticSelectionIgnored {
                        let expectedLocation = min(max(0, focusProgrammaticCaretExpectedLocation), textLength)
                        if selected.location != expectedLocation || selected.length != 0 {
                            textView.setSelectedRange(NSRange(location: expectedLocation, length: 0))
                        }
                        return
                    }
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
            requestFocusModeOffsetNormalization(includeActive: false, force: true, reason: "caret-monitor-start")
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
            guard !isReferenceTextView(textView) else {
                focusCaretPendingTypewriter = false
                focusTypewriterDeferredUntilCompositionEnd = false
                return
            }
            var runTypewriter = focusTypewriterEnabledLive && focusCaretPendingTypewriter
            focusCaretPendingTypewriter = false
            
            if runTypewriter && textView.hasMarkedText() {
                focusTypewriterDeferredUntilCompositionEnd = true
                runTypewriter = false
            }
            if !textView.hasMarkedText() {
                _ = applyFocusModeTextViewGeometryIfNeeded(textView, reason: "caret-ensure")
                normalizeSingleTextEditorOffsetIfNeeded(textView, reason: "caret-ensure")
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
        guard !isReferenceTextView(textView) else { return }
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
        if focusTypewriterEnabledLive && typewriter {
            let baseline = CGFloat(min(max(focusTypewriterBaseline, 0.40), 0.80))
            let activeRect = (sel.length > 0 && _focusSelectionActiveEdge == .start) ? startRect : endRect
            targetY = activeRect.midY - (visible.height * baseline)
        } else {
            if sel.length > 0 {
                switch _focusSelectionActiveEdge {
                case .start:
                    if startRect.minY < minVisibleY {
                        targetY = max(minY, startRect.minY - topPadding)
                    } else if startRect.maxY > maxVisibleY {
                        targetY = startRect.maxY - (visible.height - bottomPadding)
                    }
                case .end:
                    if endRect.maxY > maxVisibleY {
                        targetY = endRect.maxY - (visible.height - bottomPadding)
                    } else if endRect.minY < minVisibleY {
                        targetY = max(minY, endRect.minY - topPadding)
                    }
                }
            } else {
                if endRect.maxY > maxVisibleY {
                    targetY = endRect.maxY - (visible.height - bottomPadding)
                } else if startRect.minY < minVisibleY {
                    targetY = max(minY, startRect.minY - topPadding)
                }
            }
        }

        let clampedY = min(max(minY, targetY), maxY)
        let targetYSnapped = typewriter ? round(clampedY) : clampedY
        let deadZone: CGFloat = typewriter ? 14.0 : 1.0
        let shouldScroll = abs(targetYSnapped - visible.origin.y) > deadZone
        if shouldScroll {
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
        let shouldApplySelectionIgnoreWindow =
            switchingToDifferentCard || preserveViewportOnSwitch || explicitCaretLocation != nil
        if let location, shouldApplySelectionIgnoreWindow {
            focusProgrammaticCaretExpectedCardID = card.id
            focusProgrammaticCaretExpectedLocation = location
            focusProgrammaticCaretSelectionIgnoreUntil = Date().addingTimeInterval(0.28)
        } else {
            focusProgrammaticCaretExpectedCardID = nil
            focusProgrammaticCaretExpectedLocation = -1
            focusProgrammaticCaretSelectionIgnoreUntil = .distantPast
        }
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
            if cardScrollAnchor != nil {
                scheduleFocusModeCaretEnsureBurst()
            }
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

        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            guard !isReferenceTextView(textView) else { return }
            normalizeSingleTextEditorOffsetIfNeeded(textView, reason: "content-change-sync")
        }

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
            focusProgrammaticCaretExpectedCardID = expectedCardID
            focusProgrammaticCaretExpectedLocation = safe
            focusProgrammaticCaretSelectionIgnoreUntil = Date().addingTimeInterval(0.22)
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
            DispatchQueue.main.async {
                requestFocusModeOffsetNormalization(includeActive: true, force: true, reason: "focus-enter-initial")
                scheduleFocusModeOffsetNormalizationBurst(includeActive: true)
            }
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
                showAIChat = false
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
