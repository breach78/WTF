import SwiftUI
import AppKit

private final class MainEditorFixedOriginClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = super.constrainBoundsRect(proposedBounds)
        constrained.origin = .zero
        return constrained
    }
}

extension ScenarioWriterView {

    private var mainEditorHorizontalPadding: CGFloat { MainEditorLayoutMetrics.mainEditorHorizontalPadding }
    private var mainEditorLineFragmentPadding: CGFloat { MainEditorLayoutMetrics.mainEditorLineFragmentPadding }

    // MARK: - Main Caret Monitor

    func startMainCaretMonitor() {
        guard mainSelectionObserver == nil else { return }
        mainSelectionObserver = NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification,
            object: nil,
            queue: .main
        ) { notification in
            handleMainSelectionDidChange(notification)
        }
    }

    private struct MainSelectionChangeContext {
        let editingID: UUID
        let textView: NSTextView
        let responderID: ObjectIdentifier
        let selected: NSRange
        let textLength: Int
        let selectedStart: Int
        let selectedEnd: Int
    }

    private func handleMainSelectionDidChange(_ notification: Notification) {
        guard let context = resolveMainSelectionChangeContext(from: notification) else { return }

        updateMainSelectionActiveEdge(using: context)
        guard !isDuplicateMainSelection(context) else { return }
        persistMainSelection(context)

        if mainLineSpacingAppliedResponderID != context.responderID || mainLineSpacingAppliedCardID != context.editingID {
            applyMainEditorLineSpacingIfNeeded()
        }
        normalizeMainEditorTextViewOffsetIfNeeded(context.textView, reason: "selection-change")

        guard !context.textView.hasMarkedText() else { return }
        requestCoalescedMainCaretEnsure(minInterval: mainCaretSelectionEnsureMinInterval, delay: 0.0)
    }

    private func resolveMainSelectionChangeContext(from notification: Notification) -> MainSelectionChangeContext? {
        guard !showFocusMode else { return nil }
        guard let editingID = editingCardID else { return nil }
        guard !isSearchFocused else { return nil }
        guard NSApp.keyWindow?.identifier?.rawValue != ReferenceWindowConstants.windowID else { return nil }
        guard let textView = resolveMainSelectionTextView(from: notification) else { return nil }

        let selected = textView.selectedRange()
        let textLength = (textView.string as NSString).length
        let selectedStart = min(max(0, selected.location), textLength)
        let selectedEnd = min(max(selectedStart, selected.location + selected.length), textLength)

        return MainSelectionChangeContext(
            editingID: editingID,
            textView: textView,
            responderID: ObjectIdentifier(textView),
            selected: selected,
            textLength: textLength,
            selectedStart: selectedStart,
            selectedEnd: selectedEnd
        )
    }

    private func resolveMainSelectionTextView(from notification: Notification) -> NSTextView? {
        guard let textView =
            (notification.object as? NSTextView) ??
            (NSApp.keyWindow?.firstResponder as? NSTextView)
        else {
            return nil
        }
        guard textView.window?.identifier?.rawValue != ReferenceWindowConstants.windowID else { return nil }
        guard (NSApp.keyWindow?.firstResponder as? NSTextView) === textView else { return nil }
        return textView
    }

    private func updateMainSelectionActiveEdge(using context: MainSelectionChangeContext) {
        let previousRangeIsComparable =
            mainSelectionLastCardID == context.editingID &&
            mainSelectionLastResponderID == context.responderID &&
            mainSelectionLastLocation >= 0 &&
            mainSelectionLastLength >= 0

        if context.selected.length == 0 {
            mainSelectionActiveEdge = .end
            return
        }
        guard previousRangeIsComparable else { return }

        let previousStart = min(max(0, mainSelectionLastLocation), max(0, mainSelectionLastTextLength))
        let previousEnd = min(
            max(previousStart, mainSelectionLastLocation + max(0, mainSelectionLastLength)),
            max(0, mainSelectionLastTextLength)
        )
        let movedStart = context.selectedStart != previousStart
        let movedEnd = context.selectedEnd != previousEnd
        if movedStart && !movedEnd {
            mainSelectionActiveEdge = .start
        } else if !movedStart && movedEnd {
            mainSelectionActiveEdge = .end
        } else if movedStart && movedEnd {
            let startDelta = abs(context.selectedStart - previousStart)
            let endDelta = abs(context.selectedEnd - previousEnd)
            if startDelta > endDelta {
                mainSelectionActiveEdge = .start
            } else if endDelta > startDelta {
                mainSelectionActiveEdge = .end
            }
        }
    }

    private func isDuplicateMainSelection(_ context: MainSelectionChangeContext) -> Bool {
        mainSelectionLastCardID == context.editingID &&
        mainSelectionLastLocation == context.selected.location &&
        mainSelectionLastLength == context.selected.length &&
        mainSelectionLastTextLength == context.textLength &&
        mainSelectionLastResponderID == context.responderID
    }

    private func persistMainSelection(_ context: MainSelectionChangeContext) {
        mainSelectionLastCardID = context.editingID
        mainSelectionLastLocation = context.selected.location
        mainSelectionLastLength = context.selected.length
        mainSelectionLastTextLength = context.textLength
        mainSelectionLastResponderID = context.responderID
    }

    func stopMainCaretMonitor() {
        mainCaretEnsureWorkItem?.cancel()
        mainCaretEnsureWorkItem = nil
        mainSelectionLastCardID = nil
        mainSelectionLastLocation = -1
        mainSelectionLastLength = -1
        mainSelectionLastTextLength = -1
        mainSelectionLastResponderID = nil
        mainSelectionActiveEdge = .end
        mainCaretEnsureLastScheduledAt = .distantPast
        mainLineSpacingAppliedResponderID = nil
        if let observer = mainSelectionObserver {
            NotificationCenter.default.removeObserver(observer)
            mainSelectionObserver = nil
        }
    }

    func scheduleMainEditorLineSpacingApplyBurst(for cardID: UUID) {
        let delays: [Double] = [0.0, 0.03, 0.09]
        for (index, delay) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard !showFocusMode else { return }
                guard editingCardID == cardID else { return }
                let shouldForceFullApply = index == 0
                applyMainEditorLineSpacingIfNeeded(forceApplyToFullText: shouldForceFullApply)
            }
        }
    }

    func resolveMainEditorTextView(for card: SceneCard) -> NSTextView? {
        if let firstResponder = NSApp.keyWindow?.firstResponder as? NSTextView,
           firstResponder.isEditable,
           !firstResponder.isHidden,
           firstResponder.string == card.content {
            return firstResponder
        }

        if let keyRoot = NSApp.keyWindow?.contentView {
            let candidates = collectTextViews(in: keyRoot)
            if let exact = candidates.first(where: { $0.isEditable && !$0.isHidden && $0.string == card.content }) {
                return exact
            }
        }

        if let mainRoot = NSApp.mainWindow?.contentView {
            let candidates = collectTextViews(in: mainRoot)
            if let exact = candidates.first(where: { $0.isEditable && !$0.isHidden && $0.string == card.content }) {
                return exact
            }
        }

        return nil
    }

    func applyMainEditorLineSpacingIfNeeded(
        forceApplyToFullText: Bool = false,
        preferredTextView: NSTextView? = nil
    ) {
        guard !showFocusMode else { return }
        guard let editingID = editingCardID, let card = findCard(by: editingID) else { return }
        let textView = preferredTextView ?? resolveMainEditorTextView(for: card)
        guard let textView else { return }
        guard textView.string == card.content else { return }

        prepareMainEditorTextViewForLineSpacing(textView)
        configureMainEditorTextContainerWidth(textView, editingID: editingID)

        let context = resolveMainEditorLineSpacingContext(
            textView: textView,
            editingID: editingID,
            forceApplyToFullText: forceApplyToFullText
        )
        applyMainEditorFullParagraphStyleIfNeeded(textView: textView, context: context)
        applyMainEditorTypingParagraphStyleIfNeeded(textView: textView, context: context)
        persistMainLineSpacingState(editingID: editingID, context: context)
    }

    private struct MainEditorLineSpacingContext {
        let targetSpacing: CGFloat
        let responderID: ObjectIdentifier
        let shouldApplyFull: Bool
        let shouldUpdateTypingAttributes: Bool
    }

    private func prepareMainEditorTextViewForLineSpacing(_ textView: NSTextView) {
        if textView.isHorizontallyResizable {
            textView.isHorizontallyResizable = false
        }
        if !textView.isVerticallyResizable {
            textView.isVerticallyResizable = true
        }
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        if let innerScrollView = textView.enclosingScrollView {
            normalizeMainEditorInnerScrollView(innerScrollView)
        }
        if textView.textContainerInset != .zero {
            textView.textContainerInset = .zero
        }
    }

    private func normalizeMainEditorInnerScrollView(_ scrollView: NSScrollView) {
        if scrollView.hasVerticalScroller {
            scrollView.hasVerticalScroller = false
        }
        if scrollView.hasHorizontalScroller {
            scrollView.hasHorizontalScroller = false
        }
        if !scrollView.autohidesScrollers {
            scrollView.autohidesScrollers = true
        }
        let insets = scrollView.contentInsets
        if abs(insets.top) > 0.01 || abs(insets.left) > 0.01 || abs(insets.bottom) > 0.01 || abs(insets.right) > 0.01 {
            scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        }
        if !(scrollView.contentView is MainEditorFixedOriginClipView) {
            let currentClipView = scrollView.contentView
            let fixedClipView = MainEditorFixedOriginClipView(frame: currentClipView.frame)
            fixedClipView.drawsBackground = currentClipView.drawsBackground
            fixedClipView.backgroundColor = currentClipView.backgroundColor
            let existingDocumentView = scrollView.documentView
            scrollView.contentView = fixedClipView
            if scrollView.documentView !== existingDocumentView {
                scrollView.documentView = existingDocumentView
            }
        }
        if scrollView.contentView.bounds.origin != .zero {
            scrollView.contentView.setBoundsOrigin(.zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func configureMainEditorTextContainerWidth(_ textView: NSTextView, editingID: UUID) {
        guard let textContainer = textView.textContainer else { return }

        let viewportWidth = textView.enclosingScrollView?.contentView.bounds.width ?? textView.bounds.width
        let measuredCardWidth = mainCardWidths[editingID] ?? 0
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.maximumNumberOfLines = 0
        if abs(textContainer.lineFragmentPadding - mainEditorLineFragmentPadding) > 0.01 {
            textContainer.lineFragmentPadding = mainEditorLineFragmentPadding
        }
        if textContainer.widthTracksTextView {
            textContainer.widthTracksTextView = false
        }
        textContainer.heightTracksTextView = false

        let expectedTextWidthFromCard = max(0, measuredCardWidth - (mainEditorHorizontalPadding * 2))
        let candidateWidth = expectedTextWidthFromCard > 1 ? expectedTextWidthFromCard : viewportWidth
        let targetWidth = max(1, min(viewportWidth, candidateWidth))
        if viewportWidth > 1 {
            assert(targetWidth <= viewportWidth + 0.5, "Main editor container width exceeded viewport")
        }
        if abs(textContainer.containerSize.width - targetWidth) > 0.5 {
            textContainer.containerSize = CGSize(width: targetWidth, height: .greatestFiniteMagnitude)
        }
    }

    private func resolveMainEditorLineSpacingContext(
        textView: NSTextView,
        editingID: UUID,
        forceApplyToFullText: Bool
    ) -> MainEditorLineSpacingContext {
        let targetSpacing = CGFloat(mainCardLineSpacingValue)
        let responderID = ObjectIdentifier(textView)
        let isNewCard = (mainLineSpacingAppliedCardID != editingID)
        let spacingChanged = abs(mainLineSpacingAppliedValue - targetSpacing) > 0.01
        let shouldApplyFull = forceApplyToFullText || isNewCard || spacingChanged
        let currentTypingSpacing =
            ((textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.lineSpacing ?? 0)
        let currentDefaultSpacing = textView.defaultParagraphStyle?.lineSpacing ?? 0
        let needsTypingUpdate = abs(currentTypingSpacing - targetSpacing) > 0.01
        let needsDefaultUpdate = abs(currentDefaultSpacing - targetSpacing) > 0.01

        return MainEditorLineSpacingContext(
            targetSpacing: targetSpacing,
            responderID: responderID,
            shouldApplyFull: shouldApplyFull,
            shouldUpdateTypingAttributes: needsTypingUpdate || needsDefaultUpdate || shouldApplyFull
        )
    }

    private func applyMainEditorFullParagraphStyleIfNeeded(textView: NSTextView, context: MainEditorLineSpacingContext) {
        guard context.shouldApplyFull else { return }
        guard let storage = textView.textStorage, storage.length > 0 else { return }

        let paragraph = makeMainEditorParagraphStyle(
            base: textView.defaultParagraphStyle,
            targetSpacing: context.targetSpacing
        )
        storage.beginEditing()
        storage.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
    }

    private func applyMainEditorTypingParagraphStyleIfNeeded(textView: NSTextView, context: MainEditorLineSpacingContext) {
        guard context.shouldUpdateTypingAttributes else { return }

        let typingParagraph =
            (textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ??
            (textView.defaultParagraphStyle?.mutableCopy() as? NSMutableParagraphStyle) ??
            NSMutableParagraphStyle()
        let normalizedParagraph = makeMainEditorParagraphStyle(base: typingParagraph, targetSpacing: context.targetSpacing)
        var typing = textView.typingAttributes
        textView.defaultParagraphStyle = normalizedParagraph
        typing[.paragraphStyle] = normalizedParagraph
        textView.typingAttributes = typing
    }

    private func makeMainEditorParagraphStyle(base: NSParagraphStyle?, targetSpacing: CGFloat) -> NSMutableParagraphStyle {
        let paragraph = (base?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        paragraph.lineSpacing = targetSpacing
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineHeightMultiple = 1.0
        paragraph.paragraphSpacing = 0
        paragraph.paragraphSpacingBefore = 0
        return paragraph
    }

    private func persistMainLineSpacingState(editingID: UUID, context: MainEditorLineSpacingContext) {
        mainLineSpacingAppliedCardID = editingID
        mainLineSpacingAppliedValue = context.targetSpacing
        mainLineSpacingAppliedResponderID = context.responderID
    }

    func handleMainEditorContentChange(cardID: UUID, oldValue: String, newValue: String) {
        guard !showFocusMode else { return }
        guard editingCardID == cardID else { return }
        markEditingSessionTextMutation()
        handleMainTypingContentChange(cardID: cardID, oldValue: oldValue, newValue: newValue)
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           textView.window?.identifier?.rawValue != ReferenceWindowConstants.windowID,
           textView.string == newValue {
            applyMainEditorLineSpacingIfNeeded(preferredTextView: textView)
            normalizeMainEditorTextViewOffsetIfNeeded(textView, reason: "content-change")
        } else {
            applyMainEditorLineSpacingIfNeeded()
        }
        requestCoalescedMainCaretEnsure(minInterval: mainCaretSelectionEnsureMinInterval, delay: 0.0)
    }

    // MARK: - Main Caret Ensure Visible

    func requestMainCaretEnsure(delay: Double = 0.01) {
        guard !showFocusMode else { return }
        guard editingCardID != nil else { return }
        mainCaretEnsureWorkItem?.cancel()
        let work = DispatchWorkItem {
            mainCaretEnsureWorkItem = nil
            ensureMainCaretVisible()
        }
        mainCaretEnsureWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func requestCoalescedMainCaretEnsure(minInterval: TimeInterval, delay: Double = 0.0) {
        let now = Date()
        let elapsed = now.timeIntervalSince(mainCaretEnsureLastScheduledAt)
        let extraDelay = max(0, minInterval - elapsed)
        let resolvedDelay = max(delay, extraDelay)
        mainCaretEnsureLastScheduledAt = now.addingTimeInterval(resolvedDelay)
        requestMainCaretEnsure(delay: resolvedDelay)
    }

    func ensureMainCaretVisible() {
        guard let context = resolveMainCaretEnsureContext() else { return }
        normalizeMainEditorTextViewOffsetIfNeeded(context.textView, reason: "ensure-visible")
        context.layoutManager.ensureLayout(for: context.textContainer)

        guard let selectionRects = resolveMainCaretSelectionRects(
            textView: context.textView,
            layoutManager: context.layoutManager,
            textContainer: context.textContainer,
            outerDocumentView: context.outerDocumentView
        ) else {
            return
        }
        let viewport = resolveMainCaretViewportContext(outerScrollView: context.outerScrollView)
        let targetY = resolveMainCaretTargetY(selectionRects: selectionRects, viewport: viewport)
        applyMainCaretScrollPositionIfNeeded(
            outerScrollView: context.outerScrollView,
            visible: viewport.visible,
            targetY: targetY,
            minY: viewport.minY,
            maxY: viewport.maxY
        )
    }

    private struct MainCaretEnsureContext {
        let textView: NSTextView
        let outerScrollView: NSScrollView
        let outerDocumentView: NSView
        let layoutManager: NSLayoutManager
        let textContainer: NSTextContainer
    }

    private func resolveMainCaretEnsureContext() -> MainCaretEnsureContext? {
        guard !showFocusMode else { return nil }
        guard let editingID = editingCardID, let card = findCard(by: editingID) else { return nil }
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return nil }
        guard textView.string == card.content else { return nil }
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return nil }
        guard let outerScrollView = outerScrollView(containing: textView),
              let outerDocumentView = outerScrollView.documentView else {
            return nil
        }
        return MainCaretEnsureContext(
            textView: textView,
            outerScrollView: outerScrollView,
            outerDocumentView: outerDocumentView,
            layoutManager: layoutManager,
            textContainer: textContainer
        )
    }

    private struct MainCaretSelectionRects {
        let selection: NSRange
        let startRect: CGRect
        let endRect: CGRect
    }

    private struct MainCaretViewportContext {
        let visible: CGRect
        let minY: CGFloat
        let maxY: CGFloat
        let minVisibleY: CGFloat
        let maxVisibleY: CGFloat
        let topPadding: CGFloat
        let bottomPadding: CGFloat
    }

    private func resolveMainCaretSelectionRects(
        textView: NSTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        outerDocumentView: NSView
    ) -> MainCaretSelectionRects? {
        let textLength = (textView.string as NSString).length
        let sel = textView.selectedRange()
        let selStart = min(sel.location, textLength)
        let selEnd = min(sel.location + sel.length, textLength)
        let startRect = mainCaretRectInDocument(
            at: selStart,
            textView: textView,
            layoutManager: layoutManager,
            textContainer: textContainer,
            outerDocumentView: outerDocumentView
        )
        let endRect = (sel.length > 0)
            ? mainCaretRectInDocument(
                at: selEnd,
                textView: textView,
                layoutManager: layoutManager,
                textContainer: textContainer,
                outerDocumentView: outerDocumentView
            )
            : startRect

        return MainCaretSelectionRects(selection: sel, startRect: startRect, endRect: endRect)
    }

    private func mainCaretRectInDocument(
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

    private func resolveMainCaretViewportContext(outerScrollView: NSScrollView) -> MainCaretViewportContext {
        let visible = outerScrollView.documentVisibleRect
        let insets = outerScrollView.contentInsets
        let clipOriginY = outerScrollView.contentView.bounds.origin.y
        let inferredTopInset = max(0, -clipOriginY)
        let effectiveTopInset = max(insets.top, inferredTopInset)
        let minY = -effectiveTopInset
        let documentHeight = outerScrollView.documentView?.bounds.height ?? 0
        let maxY = max(minY, documentHeight - visible.height + insets.bottom)
        let topPadding: CGFloat = 120
        let bottomPadding: CGFloat = 120
        let minVisibleY = visible.minY + topPadding
        let maxVisibleY = visible.maxY - bottomPadding

        return MainCaretViewportContext(
            visible: visible,
            minY: minY,
            maxY: maxY,
            minVisibleY: minVisibleY,
            maxVisibleY: maxVisibleY,
            topPadding: topPadding,
            bottomPadding: bottomPadding
        )
    }

    private func resolveMainCaretTargetY(
        selectionRects: MainCaretSelectionRects,
        viewport: MainCaretViewportContext
    ) -> CGFloat {
        var targetY = viewport.visible.origin.y
        let selection = selectionRects.selection
        let startRect = selectionRects.startRect
        let endRect = selectionRects.endRect

        if selection.length > 0 {
            switch mainSelectionActiveEdge {
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
        } else {
            if endRect.maxY > viewport.maxVisibleY {
                targetY = endRect.maxY - (viewport.visible.height - viewport.bottomPadding)
            } else if startRect.minY < viewport.minVisibleY {
                targetY = max(viewport.minY, startRect.minY - viewport.topPadding)
            }
        }

        return targetY
    }

    private func applyMainCaretScrollPositionIfNeeded(
        outerScrollView: NSScrollView,
        visible: CGRect,
        targetY: CGFloat,
        minY: CGFloat,
        maxY: CGFloat
    ) {
        _ = CaretScrollCoordinator.applyVerticalScrollIfNeeded(
            scrollView: outerScrollView,
            visibleRect: visible,
            targetY: targetY,
            minY: minY,
            maxY: maxY
        )
    }

    func normalizeMainEditorTextViewOffsetIfNeeded(_ textView: NSTextView, reason: String) {
        guard let scrollView = textView.enclosingScrollView else { return }
        let origin = scrollView.contentView.bounds.origin
        let shouldResetX = abs(origin.x) > 0.5
        let shouldResetY = abs(origin.y) > 0.5
        let hasActiveSelectionRange = textView.selectedRange().length > 0
        let shouldResetYForReason =
            shouldResetY &&
            !(reason == "selection-change" && hasActiveSelectionRange)
        guard shouldResetX || shouldResetYForReason else { return }
        let targetOrigin = NSPoint(
            x: shouldResetX ? 0 : origin.x,
            y: shouldResetYForReason ? 0 : origin.y
        )
        scrollView.contentView.setBoundsOrigin(targetOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - Main Caret Remember / Restore

    func rememberMainCaretLocation(for cardID: UUID) {
        guard !showFocusMode else { return }
        guard focusModeEditorCardID == nil else { return }
        guard let card = findCard(by: cardID) else { return }
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        guard textView.string == card.content else { return }
        let length = (textView.string as NSString).length
        let safeLocation = min(max(0, textView.selectedRange().location), length)
        mainCaretLocationByCardID[cardID] = safeLocation
    }

    func requestMainCaretRestore(for cardID: UUID) {
        guard !showFocusMode else { return }
        guard focusModeEditorCardID == nil else { return }
        guard let location = mainCaretLocationByCardID[cardID] else { return }
        mainCaretRestoreRequestID += 1
        let requestID = mainCaretRestoreRequestID
        applyMainCaretWithRetry(expectedCardID: cardID, location: location, retries: 12, requestID: requestID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            applyMainCaretWithRetry(expectedCardID: cardID, location: location, retries: 6, requestID: requestID)
        }
    }

    func applyMainCaretWithRetry(expectedCardID: UUID, location: Int, retries: Int, requestID: Int) {
        guard !showFocusMode else { return }
        guard focusModeEditorCardID == nil else { return }
        guard editingCardID == expectedCardID else { return }
        guard requestID == mainCaretRestoreRequestID else { return }
        guard let card = findCard(by: expectedCardID) else { return }
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
            scheduleMainCaretRestoreRetry(
                expectedCardID: expectedCardID,
                location: location,
                retries: retries,
                requestID: requestID
            )
            return
        }
        guard textView.string == card.content else {
            scheduleMainCaretRestoreRetry(
                expectedCardID: expectedCardID,
                location: location,
                retries: retries,
                requestID: requestID
            )
            return
        }
        let length = (textView.string as NSString).length
        let safeLocation = min(max(0, location), length)
        let current = textView.selectedRange()
        guard current.location != safeLocation || current.length != 0 else { return }
        textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
        textView.scrollRangeToVisible(NSRange(location: safeLocation, length: 0))
    }

    private func scheduleMainCaretRestoreRetry(expectedCardID: UUID, location: Int, retries: Int, requestID: Int) {
        guard retries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) {
            applyMainCaretWithRetry(
                expectedCardID: expectedCardID,
                location: location,
                retries: retries - 1,
                requestID: requestID
            )
        }
    }

    func resolvedMainCaretLocation(for card: SceneCard) -> Int? {
        rememberMainCaretLocation(for: card.id)
        guard let saved = mainCaretLocationByCardID[card.id] else { return nil }
        let length = (card.content as NSString).length
        return min(max(0, saved), length)
    }

    // MARK: - Focus Caret Visual Boundary

    struct FocusCaretVisualBoundaryState {
        let isTop: Bool
        let isBottom: Bool
        let caretMidY: CGFloat
        let firstLineMinY: CGFloat
        let firstLineMaxY: CGFloat
        let lastLineMinY: CGFloat
        let lastLineMaxY: CGFloat
    }

    private struct FocusCaretLineFragments {
        let firstGlyphIndex: Int
        let lastGlyphIndex: Int
        let firstLineRect: CGRect
        let lastLineRect: CGRect
    }

    func focusCaretVisualBoundaryState(textView: NSTextView, cursor: Int) -> FocusCaretVisualBoundaryState? {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return nil }
        layoutManager.ensureLayout(for: textContainer)
        guard let lineFragments = resolveFocusCaretLineFragments(
            layoutManager: layoutManager,
            textContainer: textContainer
        ) else {
            return emptyFocusCaretVisualBoundaryState()
        }
        let insets = textView.textContainerInset
        let textLength = (textView.string as NSString).length
        let safeCursor = min(max(0, cursor), textLength)
        let caretRect = resolveFocusCaretRect(
            layoutManager: layoutManager,
            textContainer: textContainer,
            safeCursor: safeCursor,
            firstGlyphIndex: lineFragments.firstGlyphIndex,
            lastGlyphIndex: lineFragments.lastGlyphIndex
        )

        let firstLineMinY = lineFragments.firstLineRect.minY + insets.height
        let firstLineMaxY = lineFragments.firstLineRect.maxY + insets.height
        let lastLineMinY = lineFragments.lastLineRect.minY + insets.height
        let lastLineMaxY = lineFragments.lastLineRect.maxY + insets.height
        let caretMidY = caretRect.midY + insets.height
        let tolerance = max(1.0, CGFloat(fontSize) * 0.20)

        return FocusCaretVisualBoundaryState(
            isTop: caretMidY <= firstLineMaxY + tolerance,
            isBottom: caretMidY >= lastLineMinY - tolerance,
            caretMidY: caretMidY,
            firstLineMinY: firstLineMinY,
            firstLineMaxY: firstLineMaxY,
            lastLineMinY: lastLineMinY,
            lastLineMaxY: lastLineMaxY
        )
    }

    private func emptyFocusCaretVisualBoundaryState() -> FocusCaretVisualBoundaryState {
        FocusCaretVisualBoundaryState(
            isTop: true,
            isBottom: true,
            caretMidY: 0,
            firstLineMinY: 0,
            firstLineMaxY: 0,
            lastLineMinY: 0,
            lastLineMaxY: 0
        )
    }

    private func resolveFocusCaretLineFragments(
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> FocusCaretLineFragments? {
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard glyphRange.length > 0 else { return nil }

        let firstGlyphIndex = glyphRange.location
        let lastGlyphIndex = max(firstGlyphIndex, NSMaxRange(glyphRange) - 1)
        let firstLineRect = layoutManager.lineFragmentUsedRect(
            forGlyphAt: firstGlyphIndex,
            effectiveRange: nil,
            withoutAdditionalLayout: true
        )
        let lastLineRect = layoutManager.lineFragmentUsedRect(
            forGlyphAt: lastGlyphIndex,
            effectiveRange: nil,
            withoutAdditionalLayout: true
        )
        return FocusCaretLineFragments(
            firstGlyphIndex: firstGlyphIndex,
            lastGlyphIndex: lastGlyphIndex,
            firstLineRect: firstLineRect,
            lastLineRect: lastLineRect
        )
    }

    private func resolveFocusCaretRect(
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        safeCursor: Int,
        firstGlyphIndex: Int,
        lastGlyphIndex: Int
    ) -> CGRect {
        let insertionGlyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: safeCursor, length: 0),
            actualCharacterRange: nil
        )
        var caretRect = layoutManager.boundingRect(forGlyphRange: insertionGlyphRange, in: textContainer)
        if caretRect.isEmpty || !isFiniteRect(caretRect) {
            let fallbackGlyph = min(max(firstGlyphIndex, insertionGlyphRange.location), lastGlyphIndex)
            caretRect = layoutManager.lineFragmentUsedRect(
                forGlyphAt: fallbackGlyph,
                effectiveRange: nil,
                withoutAdditionalLayout: true
            )
        }
        return caretRect
    }

    private func isFiniteRect(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite &&
        rect.origin.y.isFinite &&
        rect.size.width.isFinite &&
        rect.size.height.isFinite
    }

}
