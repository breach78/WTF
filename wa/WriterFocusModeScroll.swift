import SwiftUI
import AppKit

fileprivate enum FocusSelectionActiveEdge {
    case start
    case end
}

fileprivate var _focusSelectionActiveEdge: FocusSelectionActiveEdge = .end

extension ScenarioWriterView {

    func startFocusModeKeyMonitor() {
        if focusModeKeyMonitor != nil { return }
        focusModeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleFocusModeKeyDown(event)
        }
    }

    func handleFocusModeKeyDown(_ event: NSEvent) -> NSEvent? {
        if shouldPassThroughFocusModeEvent(event) { return event }
        if showFountainClipboardPasteDialog {
            _ = handleFountainClipboardPasteDialogKeyDownEvent(event)
            return nil
        }
        if showCloneCardPasteDialog {
            _ = handleClonePasteDialogKeyDownEvent(event)
            return nil
        }
        if handleFocusDeleteAlertShortcutIfNeeded(event) { return nil }

        let flags = event.modifierFlags
        if handleFocusEscapeShortcut(event, flags: flags) { return nil }
        if handleFocusSearchPopupReturnShortcut(event, flags: flags) { return nil }
        if handleFocusSearchShortcut(event, flags: flags) { return nil }
        if handleFocusFountainClipboardPasteShortcut(event, flags: flags) { return nil }
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
            guard showFocusMode else { return }
            let hadEditingState = editingCardID != nil || focusModeEditorCardID != nil
            guard hadEditingState else { return }
            focusModeEditorCardID = nil
            if editingCardID != nil {
                finishEditing(reason: .explicitExit)
            }
        }
        return true
    }

    private func handleFocusSearchPopupReturnShortcut(
        _ event: NSEvent,
        flags: NSEvent.ModifierFlags
    ) -> Bool {
        guard showFocusModeSearchPopup else { return false }
        guard flags.intersection(.deviceIndependentFlagsMask).isEmpty else { return false }
        guard event.keyCode == 36 || event.keyCode == 76 else { return false }
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView, textView.hasMarkedText() {
            return false
        }
        DispatchQueue.main.async {
            moveFocusModeSearchSelection(step: 1)
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

    private func handleFocusFountainClipboardPasteShortcut(
        _ event: NSEvent,
        flags: NSEvent.ModifierFlags
    ) -> Bool {
        guard isCommandOnlyFlags(flags) else { return false }
        let normalized = (event.charactersIgnoringModifiers ?? "").lowercased()
        let isPasteShortcut = normalized == "v" || normalized == "ㅍ" || event.keyCode == 9
        guard isPasteShortcut else { return false }
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
        return handleFountainClipboardPasteShortcutIfPossible(from: textView)
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
        guard event.keyCode == 51 || event.keyCode == 117 else { return false }
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
        guard event.keyCode == 36 || event.keyCode == 76 else { return false }
        if event.isARepeat { return true }
        DispatchQueue.main.async {
            insertSibling(above: false)
        }
        return true
    }

    func handleFocusOptionArrowSiblingShortcut(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        let isCommandOption = flags.contains(.command) && flags.contains(.option) && !flags.contains(.control)
        guard isCommandOption else { return false }
        guard event.keyCode == 126 || event.keyCode == 125 else { return false }
        if event.isARepeat { return true }
        let createAbove = event.keyCode == 126
        DispatchQueue.main.async {
            insertSibling(above: createAbove)
        }
        return true
    }

    func handleFocusReturnBoundaryState(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        guard event.keyCode == 36 || event.keyCode == 76 else { return false }
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
        let selection = textView.selectedRange()
        guard selection.length == 0 else {
            let isUpKey = event.keyCode == 126
            return (isUpKey, false)
        }
        let cursor = selection.location
        let length = (currentCard.content as NSString).length
        let atTopBoundary = (cursor == 0)
        let atBottomBoundary = (cursor == length)
        let isUpKey = event.keyCode == 126
        let isBoundary = isUpKey
            ? (atTopBoundary && currentIndex > 0)
            : (atBottomBoundary && currentIndex < cards.count - 1)
        return (isUpKey, isBoundary)
    }

    private func consumeFocusModeArrowNavigationWithoutBoundary() {
        clearFocusBoundaryArm()
        focusModeCaretRequestID += 1
        focusModeBoundaryTransitionPendingReveal = false
        focusModePendingFallbackRevealCardID = nil
        focusModeFallbackRevealIssuedCardID = nil
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
        focusModeCaretRequestID += 1
        _ = beginFocusModeVerticalScrollAuthority(kind: .boundaryTransition, targetCardID: target.id)
        let requiresBoundaryReveal = shouldForceFocusModeBoundaryReveal(
            textView: textView,
            isUpKey: isUpKey
        )
        focusModeBoundaryTransitionPendingReveal = requiresBoundaryReveal
        focusModePendingFallbackRevealCardID = requiresBoundaryReveal ? target.id : nil
        focusModeFallbackRevealIssuedCardID = nil
        DispatchQueue.main.async {
            beginFocusModeEditing(
                target,
                cursorToEnd: isUpKey,
                cardScrollAnchor: nil,
                animatedScroll: false,
                preserveViewportOnSwitch: true
            )
        }
    }

    private func shouldForceFocusModeBoundaryReveal(
        textView: NSTextView,
        isUpKey: Bool
    ) -> Bool {
        guard let outerScrollView = outerScrollView(containing: textView),
              let outerDocumentView = outerScrollView.documentView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return false
        }

        let selection = textView.selectedRange()
        guard selection.length == 0 else { return false }
        let selectionRects = resolveFocusModeSelectionRects(
            textView: textView,
            layoutManager: layoutManager,
            textContainer: textContainer,
            outerDocumentView: outerDocumentView,
            selection: selection
        )
        let visible = outerScrollView.documentVisibleRect
        let lineHeight = max(1, CGFloat(fontSize * 1.2) + CGFloat(focusModeLineSpacingValue))
        let edgeThreshold = max(20, ceil(lineHeight * 1.5))

        if isUpKey {
            return selectionRects.startRect.minY <= visible.minY + edgeThreshold
        } else {
            return selectionRects.endRect.maxY >= visible.maxY - edgeThreshold
        }
    }

    func isTypewriterTriggerKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 36 || event.keyCode == 76 {
            return true
        }
        let blocked: Set<UInt16> = [48, 51, 117, 53, 123, 124, 125, 126, 115, 119, 116, 121]
        if blocked.contains(event.keyCode) { return false }
        guard let characters = event.characters, !characters.isEmpty else { return false }
        let onlyControl = characters.unicodeScalars.allSatisfy { CharacterSet.controlCharacters.contains($0) }
        return !onlyControl
    }

    func clearFocusBoundaryArm() {
    }

    func stopFocusModeKeyMonitor() {
        clearFocusBoundaryArm()
        if let monitor = focusModeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            focusModeKeyMonitor = nil
        }
    }

    func startFocusModeScrollMonitor() {
        stopFocusModeScrollMonitor()
    }

    private func createFocusModeScrollWheelMonitor() -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            handleFocusModeScrollWheelEvent(event)
        }
    }

    private func handleFocusModeScrollWheelEvent(_ event: NSEvent) -> NSEvent? {
        event
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
        _ = textView
        return FocusModeLayoutMetrics.resolvedTextWidth(
            for: FocusModeLayoutMetrics.focusModePreferredCardWidth
        )
    }

    @discardableResult
    func applyFocusModeTextViewGeometryIfNeeded(_ textView: NSTextView, reason: String = "focus-mode") -> Bool {
        guard showFocusMode else { return false }
        var changed = false
        changed = applyFocusModeTextViewSizingIfNeeded(textView) || changed
        if let scrollView = textView.enclosingScrollView,
           isFocusModeInternalTextEditorScrollView(scrollView) {
            changed = applyFocusModeInnerScrollViewGeometryIfNeeded(scrollView) || changed
        }
        if textView.textContainerInset != .zero {
            textView.textContainerInset = .zero
            changed = true
        }
        changed = applyFocusModeTextContainerGeometryIfNeeded(textView) || changed
        changed = applyFocusModeTextTypographyIfNeeded(textView) || changed
        _ = reason
        return changed
    }

    private func shouldApplyFocusModeTextViewGeometryForCaretEnsure(_ textView: NSTextView) -> Bool {
        guard showFocusMode else { return false }

        let editingID = focusModeEditorCardID ?? editingCardID ?? activeCardID
        let responderID = ObjectIdentifier(textView)
        let targetSpacing = CGFloat(focusModeLineSpacingValue)
        let targetFontSize = CGFloat(fontSize * 1.2)

        if focusLineSpacingAppliedCardID != editingID { return true }
        if abs(focusLineSpacingAppliedValue - targetSpacing) > 0.01 { return true }
        if abs(focusLineSpacingAppliedFontSize - targetFontSize) > 0.01 { return true }
        if focusLineSpacingAppliedResponderID != responderID { return true }
        if textView.textContainerInset != .zero { return true }

        if let scrollView = textView.enclosingScrollView,
           isFocusModeInternalTextEditorScrollView(scrollView) {
            let insets = scrollView.contentInsets
            if abs(insets.top) > 0.01 || abs(insets.left) > 0.01 || abs(insets.bottom) > 0.01 || abs(insets.right) > 0.01 {
                return true
            }
            if scrollView.hasVerticalScroller || scrollView.hasHorizontalScroller || !scrollView.autohidesScrollers {
                return true
            }
            if !scrollView.contentView.postsBoundsChangedNotifications {
                return true
            }
        }

        guard let textContainer = textView.textContainer else { return true }
        if textContainer.lineBreakMode != .byWordWrapping { return true }
        if textContainer.maximumNumberOfLines != 0 { return true }
        if abs(textContainer.lineFragmentPadding - FocusModeLayoutMetrics.focusModeLineFragmentPadding) > 0.01 {
            return true
        }
        if textContainer.widthTracksTextView || textContainer.heightTracksTextView { return true }
        if abs(textContainer.containerSize.width - focusModeTargetContainerWidth(for: textView)) > 0.5 {
            return true
        }

        return false
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

    private struct FocusModeTextLayoutContext {
        let editingID: UUID
        let targetSpacing: CGFloat
        let targetFont: NSFont
        let targetFontSize: CGFloat
        let targetColor: NSColor
        let responderID: ObjectIdentifier
        let shouldApplyFull: Bool
        let shouldUpdateTypingAttributes: Bool
    }

    private func applyFocusModeTextTypographyIfNeeded(_ textView: NSTextView) -> Bool {
        guard showFocusMode else { return false }
        guard let editingID = focusModeEditorCardID ?? editingCardID ?? activeCardID else { return false }

        let context = resolveFocusModeTextLayoutContext(textView: textView, editingID: editingID)
        var changed = false

        if textView.isRichText {
            textView.isRichText = false
            changed = true
        }
        if textView.importsGraphics {
            textView.importsGraphics = false
            changed = true
        }
        if textView.usesFontPanel {
            textView.usesFontPanel = false
            changed = true
        }
        if textView.usesFindBar {
            textView.usesFindBar = false
            changed = true
        }
        if textView.font != context.targetFont {
            textView.font = context.targetFont
            changed = true
        }
        if textView.textColor != context.targetColor {
            textView.textColor = context.targetColor
            changed = true
        }
        if textView.insertionPointColor != context.targetColor {
            textView.insertionPointColor = context.targetColor
            changed = true
        }

        changed = applyFocusModeFullParagraphStyleIfNeeded(textView: textView, context: context) || changed
        changed = applyFocusModeTypingParagraphStyleIfNeeded(textView: textView, context: context) || changed
        persistFocusModeTypographyState(context: context)
        return changed
    }

    private func resolveFocusModeTextLayoutContext(
        textView: NSTextView,
        editingID: UUID
    ) -> FocusModeTextLayoutContext {
        let targetSpacing = CGFloat(focusModeLineSpacingValue)
        let targetFontSize = CGFloat(fontSize * 1.2)
        let targetFont = NSFont(name: "SansMonoCJKFinalDraft", size: targetFontSize)
            ?? NSFont.monospacedSystemFont(ofSize: targetFontSize, weight: .regular)
        let targetColor: NSColor = (appearance == "light") ? .black : .white
        let responderID = ObjectIdentifier(textView)

        let isNewCard = (focusLineSpacingAppliedCardID != editingID)
        let spacingChanged = abs(focusLineSpacingAppliedValue - targetSpacing) > 0.01
        let fontChanged = abs(focusLineSpacingAppliedFontSize - targetFontSize) > 0.01
        let responderChanged = focusLineSpacingAppliedResponderID != responderID
        let shouldApplyFull = isNewCard || spacingChanged || fontChanged || responderChanged

        let currentTypingSpacing =
            ((textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.lineSpacing ?? 0)
        let currentDefaultSpacing = textView.defaultParagraphStyle?.lineSpacing ?? 0
        let currentTypingFont = textView.typingAttributes[.font] as? NSFont
        let currentTypingColor = textView.typingAttributes[.foregroundColor] as? NSColor
        let needsTypingUpdate =
            abs(currentTypingSpacing - targetSpacing) > 0.01 ||
            abs(currentDefaultSpacing - targetSpacing) > 0.01 ||
            currentTypingFont != targetFont ||
            currentTypingColor != targetColor

        return FocusModeTextLayoutContext(
            editingID: editingID,
            targetSpacing: targetSpacing,
            targetFont: targetFont,
            targetFontSize: targetFontSize,
            targetColor: targetColor,
            responderID: responderID,
            shouldApplyFull: shouldApplyFull,
            shouldUpdateTypingAttributes: shouldApplyFull || needsTypingUpdate
        )
    }

    private func applyFocusModeFullParagraphStyleIfNeeded(
        textView: NSTextView,
        context: FocusModeTextLayoutContext
    ) -> Bool {
        guard context.shouldApplyFull else { return false }
        guard let storage = textView.textStorage, storage.length > 0 else { return false }

        let paragraph = makeFocusModeParagraphStyle(
            base: textView.defaultParagraphStyle,
            targetSpacing: context.targetSpacing
        )
        storage.beginEditing()
        storage.addAttributes(
            [
                .paragraphStyle: paragraph,
                .font: context.targetFont,
                .foregroundColor: context.targetColor
            ],
            range: NSRange(location: 0, length: storage.length)
        )
        storage.endEditing()
        return true
    }

    private func applyFocusModeTypingParagraphStyleIfNeeded(
        textView: NSTextView,
        context: FocusModeTextLayoutContext
    ) -> Bool {
        guard context.shouldUpdateTypingAttributes else { return false }

        let typingParagraph =
            (textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ??
            (textView.defaultParagraphStyle?.mutableCopy() as? NSMutableParagraphStyle) ??
            NSMutableParagraphStyle()
        let normalizedParagraph = makeFocusModeParagraphStyle(
            base: typingParagraph,
            targetSpacing: context.targetSpacing
        )
        var typing = textView.typingAttributes
        textView.defaultParagraphStyle = normalizedParagraph
        typing[.paragraphStyle] = normalizedParagraph
        typing[.font] = context.targetFont
        typing[.foregroundColor] = context.targetColor
        textView.typingAttributes = typing
        return true
    }

    private func makeFocusModeParagraphStyle(
        base: NSParagraphStyle?,
        targetSpacing: CGFloat
    ) -> NSMutableParagraphStyle {
        let paragraph = (base?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        paragraph.lineSpacing = targetSpacing
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineHeightMultiple = 1.0
        paragraph.paragraphSpacing = 0
        paragraph.paragraphSpacingBefore = 0
        return paragraph
    }

    private func persistFocusModeTypographyState(context: FocusModeTextLayoutContext) {
        focusLineSpacingAppliedCardID = context.editingID
        focusLineSpacingAppliedValue = context.targetSpacing
        focusLineSpacingAppliedFontSize = context.targetFontSize
        focusLineSpacingAppliedResponderID = context.responderID
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
        guard let textView = resolveSingleFocusModeEditableTextView() else { return (0, 0, 0, 0) }

        let activeTextView = NSApp.keyWindow?.firstResponder as? NSTextView
        let isActiveResponder = (activeTextView != nil && textView === activeTextView)
        if let activeFocusedCardID = focusModeEditorCardID ?? editingCardID ?? activeCardID {
            focusResponderCardByObjectID[ObjectIdentifier(textView)] = activeFocusedCardID
        }

        _ = applyFocusModeTextViewGeometryIfNeeded(
            textView,
            reason: isActiveResponder ? "offset-normalization-active" : "offset-normalization-single"
        )

        guard includeActive || !isActiveResponder else {
            return (1, 0, 1, 0)
        }

        let resetCount = resetFocusModeTextViewScrollOriginIfNeeded(textView) ? 1 : 0
        return (1, resetCount, 0, 0)
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

    func collectEditableFocusModeTextViews(root: NSView) -> [NSTextView] {
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
        if let activeTextView,
           let activeFocusedCardID,
           focusedCardIDs.contains(activeFocusedCardID) {
            let activeIdentity = ObjectIdentifier(activeTextView)
            focusResponderCardByObjectID[activeIdentity] = activeFocusedCardID
        }

        if !focusedCards.isEmpty && focusedCards.count == textViews.count {
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
        guard isFocusModeInternalTextEditorScrollView(scrollView) else { return false }
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
        guard shouldRunFocusModeOffsetNormalization(reason: reason) else { return }
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

    private func shouldRunFocusModeOffsetNormalization(reason: String) -> Bool {
        guard showFocusMode else { return false }
        guard !isReferenceWindowFocused else { return false }
        if let authority = focusVerticalScrollAuthority {
            switch authority.kind {
            case .canvasNavigation, .boundaryTransition, .fallbackReveal:
                return false
            case .caretEnsure:
                return true
            }
        }
        if reason == "canvas-width-change" {
            return true
        }
        return false
    }

    func normalizeSingleTextEditorOffsetIfNeeded(_ textView: NSTextView, reason: String = "single") {
        guard let scrollView = textView.enclosingScrollView else { return }
        guard isFocusModeInternalTextEditorScrollView(scrollView) else { return }
        let origin = scrollView.contentView.bounds.origin
        let shouldResetOrigin = abs(origin.x) > 0.5 || abs(origin.y) > 0.5
        if shouldResetOrigin {
            scrollView.contentView.setBoundsOrigin(.zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    func collectTextViews(in root: NSView) -> [NSTextView] {
        var result: [NSTextView] = []
        var stack: [NSView] = [root]
        while let view = stack.popLast() {
            if let textView = view as? NSTextView {
                result.append(textView)
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
                handleFocusModeSelectionNotification(notification)
            }
        }
    }

    func handleFocusModeSelectionNotification(_ notification: Notification) {
        guard !isFocusModeExitTeardownActive else { return }
        guard let textView = focusModeSelectionTextView(from: notification) else { return }
        guard !focusSelectionProcessingPending else { return }
        focusSelectionProcessingPending = true
        DispatchQueue.main.async {
            focusSelectionProcessingPending = false
            processFocusModeSelectionNotification(textView: textView)
        }
    }

    private func processFocusModeSelectionNotification(textView: NSTextView) {
        guard !isFocusModeExitTeardownActive else { return }
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

        guard let trackedCardID else { return }
        let caretLocation = resolvedFocusCaretPersistenceLocation(selected: selected, textLength: textLength)
        mainCaretLocationByCardID[trackedCardID] = caretLocation
    }

    private func resolvedFocusCaretPersistenceLocation(selected: NSRange, textLength: Int) -> Int {
        let start = min(max(0, selected.location), textLength)
        let end = min(max(start, selected.location + selected.length), textLength)
        if selected.length == 0 {
            return end
        }
        return (_focusSelectionActiveEdge == .start) ? start : end
    }

    func scheduleFocusCaretEnsureForSelectionChange() {
        if !focusModeSelectionNeedsVerticalEnsure() {
            return
        }
        if focusCaretEnsureWorkItem != nil {
            return
        }
        let now = Date()
        let elapsed = now.timeIntervalSince(focusCaretEnsureLastScheduledAt)
        let recentlyMutatedText = now.timeIntervalSince(focusTypingLastEditAt) < 0.08
        let targetMinInterval = recentlyMutatedText
            ? max(focusCaretSelectionEnsureMinInterval, 0.045)
            : focusCaretSelectionEnsureMinInterval
        let delay = max(0, targetMinInterval - elapsed)
        focusCaretEnsureLastScheduledAt = now.addingTimeInterval(delay)
        requestFocusModeCaretEnsure(typewriter: false, delay: delay, reason: "selection-change")
    }

    private func focusModeSelectionNeedsVerticalEnsure() -> Bool {
        guard let context = resolveFocusModeCaretEnsureContext() else { return false }
        let selection = context.textView.selectedRange()
        guard selection.length == 0 else { return true }

        let selectionRects = resolveFocusModeSelectionRects(
            textView: context.textView,
            layoutManager: context.layoutManager,
            textContainer: context.textContainer,
            outerDocumentView: context.outerDocumentView,
            selection: selection
        )
        let viewport = resolveFocusModeCaretViewportContext(outerScrollView: context.outerScrollView)
        let revealPadding = min(viewport.topPadding, viewport.bottomPadding)
        let maxVisibleY = viewport.visible.maxY - revealPadding
        let minVisibleY = viewport.visible.minY + revealPadding
        return selectionRects.endRect.maxY >= maxVisibleY || selectionRects.startRect.minY <= minVisibleY
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
        focusSelectionProcessingPending = false
        focusCaretPendingTypewriter = false
        focusTypewriterDeferredUntilCompositionEnd = false
        focusModeCaretRequestStartedAt = .distantPast
        focusModeBoundaryTransitionPendingReveal = false
        focusModePendingFallbackRevealCardID = nil
        focusModeFallbackRevealIssuedCardID = nil
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
        focusLineSpacingAppliedCardID = nil
        focusLineSpacingAppliedValue = -1
        focusLineSpacingAppliedFontSize = -1
        focusLineSpacingAppliedResponderID = nil
        focusVerticalScrollAuthoritySequence = 0
        focusVerticalScrollAuthority = nil
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
        if isFocusModeExitTeardownActive { return }
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

    func shouldAwaitFocusModeLiveEditorLayoutCommit(
        for cardID: UUID,
        requestID: Int? = nil
    ) -> Bool {
        guard focusModeLayoutCoordinator.hasPendingLiveEditorLayoutCommit(for: cardID) else { return false }
        if let requestID, requestID != focusModeCaretRequestID {
            return false
        }
        return Date().timeIntervalSince(focusModeCaretRequestStartedAt) < 0.28
    }

    func shouldWaitForFocusModeCaretRetryLiveLayout(
        expectedCardID: UUID,
        location: Int,
        retries: Int,
        requestID: Int
    ) -> Bool {
        guard shouldAwaitFocusModeLiveEditorLayoutCommit(for: expectedCardID, requestID: requestID) else {
            return false
        }
        scheduleFocusModeCaretRetry(
            expectedCardID: expectedCardID,
            location: location,
            retries: retries,
            requestID: requestID,
            delay: 0.012,
            consumeRetryBudget: false
        )
        return true
    }

    private func shouldDeferFocusModeCaretEnsureForPendingLiveLayout(force: Bool) -> Bool {
        guard !force else { return false }
        guard let cardID = focusModeEditorCardID ?? editingCardID ?? activeCardID else { return false }
        guard shouldAwaitFocusModeLiveEditorLayoutCommit(for: cardID) else { return false }
        requestFocusModeCaretEnsure(
            typewriter: focusCaretPendingTypewriter,
            delay: 0.012,
            force: false,
            reason: "await-live-layout"
        )
        return true
    }

    private func executeFocusModeCaretEnsureWork(force: Bool) {
        guard !isFocusModeExitTeardownActive else {
            resetFocusModeCaretPendingState(clearDeferredTypewriter: true)
            return
        }
        if focusUndoSelectionEnsureSuppressed && !force {
            resetFocusModeCaretPendingState(clearDeferredTypewriter: false)
            return
        }
        guard showFocusMode else {
            resetFocusModeCaretPendingState(clearDeferredTypewriter: true)
            return
        }
        if shouldDeferFocusModeCaretEnsureForPendingLiveLayout(force: force) {
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

        let authority = beginFocusModeVerticalScrollAuthority(
            kind: .caretEnsure,
            targetCardID: focusModeEditorCardID ?? editingCardID ?? activeCardID
        )
        let runTypewriter = resolvedFocusModeCaretEnsureTypewriterMode(textView: textView)
        if !textView.hasMarkedText() {
            if shouldApplyFocusModeTextViewGeometryForCaretEnsure(textView) {
                _ = applyFocusModeTextViewGeometryIfNeeded(textView, reason: "caret-ensure")
            }
            normalizeSingleTextEditorOffsetIfNeeded(textView, reason: "caret-ensure")
        }
        ensureFocusModeCaretVisible(typewriter: runTypewriter, authority: authority)
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

    func ensureFocusModeCaretVisible(
        typewriter: Bool = false,
        authority: FocusModeVerticalScrollAuthority? = nil
    ) {
        guard !isFocusModeExitTeardownActive else { return }
        guard let context = resolveFocusModeCaretEnsureContext() else { return }
        if let authority, !isFocusModeVerticalScrollAuthorityCurrent(authority) {
            return
        }

        let selectionRects = resolveFocusModeSelectionRects(
            textView: context.textView,
            layoutManager: context.layoutManager,
            textContainer: context.textContainer,
            outerDocumentView: context.outerDocumentView,
            selection: context.textView.selectedRange()
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
            typewriter: typewriter,
            authority: authority
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

    func ensureFocusModeSearchRangeVisible(textView: NSTextView, range: NSRange) {
        guard showFocusMode else { return }
        guard let outerScrollView = outerScrollView(containing: textView),
              let outerDocumentView = outerScrollView.documentView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        let clampedRange = clampedFocusModeSelection(range, textLength: (textView.string as NSString).length)
        let selectionRects = resolveFocusModeSelectionRects(
            textView: textView,
            layoutManager: layoutManager,
            textContainer: textContainer,
            outerDocumentView: outerDocumentView,
            selection: clampedRange
        )
        let viewport = resolveFocusModeCaretViewportContext(outerScrollView: outerScrollView)
        let targetY = resolveFocusModeCaretTargetY(
            selectionRects: selectionRects,
            viewport: viewport,
            typewriter: false
        )
        applyFocusModeCaretScrollPositionIfNeeded(
            outerScrollView: outerScrollView,
            visible: viewport.visible,
            targetY: targetY,
            minY: viewport.minY,
            maxY: viewport.maxY,
            typewriter: false
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
        resolveFocusModeSelectionRects(
            textView: textView,
            layoutManager: layoutManager,
            textContainer: textContainer,
            outerDocumentView: outerDocumentView,
            selection: textView.selectedRange()
        )
    }

    private func resolveFocusModeSelectionRects(
        textView: NSTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        outerDocumentView: NSView,
        selection: NSRange
    ) -> FocusModeCaretSelectionRects {
        let textLength = (textView.string as NSString).length
        let clampedSelection = clampedFocusModeSelection(selection, textLength: textLength)
        let selectionStart = min(clampedSelection.location, textLength)
        let selectionEnd = min(clampedSelection.location + clampedSelection.length, textLength)
        let startRect = focusModeCaretRectInDocument(
            at: selectionStart,
            textView: textView,
            layoutManager: layoutManager,
            textContainer: textContainer,
            outerDocumentView: outerDocumentView
        )
        let endRect = (clampedSelection.length > 0)
            ? focusModeCaretRectInDocument(
                at: selectionEnd,
                textView: textView,
                layoutManager: layoutManager,
                textContainer: textContainer,
                outerDocumentView: outerDocumentView
            )
            : startRect

        return FocusModeCaretSelectionRects(selection: clampedSelection, startRect: startRect, endRect: endRect)
    }

    private func clampedFocusModeSelection(_ selection: NSRange, textLength: Int) -> NSRange {
        let safeLocation = min(max(0, selection.location), textLength)
        let maxLength = max(0, textLength - safeLocation)
        let safeLength = min(max(0, selection.length), maxLength)
        return NSRange(location: safeLocation, length: safeLength)
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
        let inferredTopInset = max(0, -clipOriginY)
        let effectiveTopInset = max(insets.top, inferredTopInset)
        let minY = -effectiveTopInset
        let maxY = max(minY, documentHeight - visible.height + insets.bottom)
        let topPadding: CGFloat = 140
        let bottomPadding: CGFloat = 140
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
        let collapsedRevealPadding = min(viewport.topPadding, viewport.bottomPadding)
        let collapsedMaxVisibleY = viewport.visible.maxY - collapsedRevealPadding
        let collapsedMinVisibleY = viewport.visible.minY + collapsedRevealPadding
        if endRect.maxY > collapsedMaxVisibleY {
            targetY = endRect.maxY - (viewport.visible.height - collapsedRevealPadding)
        } else if startRect.minY < collapsedMinVisibleY {
            targetY = max(viewport.minY, startRect.minY - collapsedRevealPadding)
        }
        return targetY
    }

    private func applyFocusModeCaretScrollPositionIfNeeded(
        outerScrollView: NSScrollView,
        visible: CGRect,
        targetY: CGFloat,
        minY: CGFloat,
        maxY: CGFloat,
        typewriter: Bool,
        authority: FocusModeVerticalScrollAuthority? = nil
    ) {
        if let authority, !isFocusModeVerticalScrollAuthorityCurrent(authority) {
            return
        }
        let recentlyMutatedText = Date().timeIntervalSince(focusTypingLastEditAt) < 0.08
        let deadZone: CGFloat
        if typewriter {
            deadZone = 14.0
        } else if recentlyMutatedText {
            deadZone = 10.0
        } else {
            deadZone = 1.0
        }
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
        guard let enclosing = textView.enclosingScrollView else { return nil }
        if !isFocusModeInternalTextEditorScrollView(enclosing) {
            return enclosing
        }
        var view: NSView? = enclosing.superview
        while let current = view {
            if let scrollView = current as? NSScrollView, scrollView !== enclosing {
                return scrollView
            }
            view = current.superview
        }
        return nil
    }
}
