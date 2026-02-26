import SwiftUI
import AppKit

extension ScenarioWriterView {

    private var mainEditorHorizontalPadding: CGFloat { MainEditorLayoutMetrics.mainEditorHorizontalPadding }
    private var mainEditorVerticalPadding: CGFloat { 12 }
    private var mainEditorLineFragmentPadding: CGFloat { MainEditorLayoutMetrics.mainEditorLineFragmentPadding }

    // MARK: - Main Caret Monitor

    func startMainCaretMonitor() {
        if mainSelectionObserver == nil {
            mainSelectionObserver = NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard !showFocusMode else { return }
                guard let editingID = editingCardID else { return }
                guard !isSearchFocused else { return }
                guard NSApp.keyWindow?.identifier?.rawValue != ReferenceWindowConstants.windowID else { return }

                guard let textView =
                    (notification.object as? NSTextView) ??
                    (NSApp.keyWindow?.firstResponder as? NSTextView)
                else {
                    return
                }
                guard textView.window?.identifier?.rawValue != ReferenceWindowConstants.windowID else { return }
                guard (NSApp.keyWindow?.firstResponder as? NSTextView) === textView else { return }

                let responderID = ObjectIdentifier(textView)
                let selected = textView.selectedRange()
                let textLength = (textView.string as NSString).length
                let selectedStart = min(max(0, selected.location), textLength)
                let selectedEnd = min(max(selectedStart, selected.location + selected.length), textLength)
                let previousRangeIsComparable =
                    mainSelectionLastCardID == editingID &&
                    mainSelectionLastResponderID == responderID &&
                    mainSelectionLastLocation >= 0 &&
                    mainSelectionLastLength >= 0
                if selected.length == 0 {
                    mainSelectionActiveEdge = .end
                } else if previousRangeIsComparable {
                    let previousStart = min(max(0, mainSelectionLastLocation), max(0, mainSelectionLastTextLength))
                    let previousEnd = min(
                        max(previousStart, mainSelectionLastLocation + max(0, mainSelectionLastLength)),
                        max(0, mainSelectionLastTextLength)
                    )
                    let movedStart = selectedStart != previousStart
                    let movedEnd = selectedEnd != previousEnd
                    if movedStart && !movedEnd {
                        mainSelectionActiveEdge = .start
                    } else if !movedStart && movedEnd {
                        mainSelectionActiveEdge = .end
                    } else if movedStart && movedEnd {
                        let startDelta = abs(selectedStart - previousStart)
                        let endDelta = abs(selectedEnd - previousEnd)
                        if startDelta > endDelta {
                            mainSelectionActiveEdge = .start
                        } else if endDelta > startDelta {
                            mainSelectionActiveEdge = .end
                        }
                    }
                }
                let isDuplicateSelection =
                    mainSelectionLastCardID == editingID &&
                    mainSelectionLastLocation == selected.location &&
                    mainSelectionLastLength == selected.length &&
                    mainSelectionLastTextLength == textLength &&
                    mainSelectionLastResponderID == responderID
                if isDuplicateSelection {
                    return
                }

                mainSelectionLastCardID = editingID
                mainSelectionLastLocation = selected.location
                mainSelectionLastLength = selected.length
                mainSelectionLastTextLength = textLength
                mainSelectionLastResponderID = responderID

                if mainLineSpacingAppliedResponderID != responderID || mainLineSpacingAppliedCardID != editingID {
                    applyMainEditorLineSpacingIfNeeded()
                }
                normalizeMainEditorTextViewOffsetIfNeeded(textView, reason: "selection-change")

                guard !textView.hasMarkedText() else { return }
                requestCoalescedMainCaretEnsure(minInterval: mainCaretSelectionEnsureMinInterval, delay: 0.0)
            }
        }
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

    func applyMainEditorLineSpacingIfNeeded(forceApplyToFullText: Bool = false) {
        guard !showFocusMode else { return }
        guard let editingID = editingCardID, let card = findCard(by: editingID) else { return }
        guard let textView = resolveMainEditorTextView(for: card) else { return }
        guard textView.string == card.content else { return }

        if textView.isHorizontallyResizable {
            textView.isHorizontallyResizable = false
        }
        if !textView.isVerticallyResizable {
            textView.isVerticallyResizable = true
        }
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        if let innerScrollView = textView.enclosingScrollView {
            if innerScrollView.hasVerticalScroller {
                innerScrollView.hasVerticalScroller = false
            }
            if innerScrollView.hasHorizontalScroller {
                innerScrollView.hasHorizontalScroller = false
            }
            if !innerScrollView.autohidesScrollers {
                innerScrollView.autohidesScrollers = true
            }
            let insets = innerScrollView.contentInsets
            if abs(insets.top) > 0.01 || abs(insets.left) > 0.01 || abs(insets.bottom) > 0.01 || abs(insets.right) > 0.01 {
                innerScrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
            }
        }
        if textView.textContainerInset != .zero {
            textView.textContainerInset = .zero
        }
        let viewportWidth = textView.enclosingScrollView?.contentView.bounds.width ?? textView.bounds.width
        let measuredCardWidth = mainCardWidths[editingID] ?? 0
        if let textContainer = textView.textContainer {
            textContainer.lineBreakMode = .byWordWrapping
            textContainer.maximumNumberOfLines = 0
            if abs(textContainer.lineFragmentPadding - mainEditorLineFragmentPadding) > 0.01 {
                textContainer.lineFragmentPadding = mainEditorLineFragmentPadding
            }
            if textContainer.widthTracksTextView {
                textContainer.widthTracksTextView = false
            }
            textContainer.heightTracksTextView = false
            let expectedTextWidthFromCard = max(0, measuredCardWidth - (MainEditorLayoutMetrics.mainEditorHorizontalPadding * 2))
            let candidateWidth = expectedTextWidthFromCard > 1 ? expectedTextWidthFromCard : viewportWidth
            let targetWidth = max(1, min(viewportWidth, candidateWidth))
            if viewportWidth > 1 {
                assert(targetWidth <= viewportWidth + 0.5, "Main editor container width exceeded viewport")
            }
            if abs(textContainer.containerSize.width - targetWidth) > 0.5 {
                textContainer.containerSize = CGSize(width: targetWidth, height: .greatestFiniteMagnitude)
            }
        }

        let targetSpacing = CGFloat(mainCardLineSpacingValue)
        let responderID = ObjectIdentifier(textView)
        let isNewCard = (mainLineSpacingAppliedCardID != editingID)
        let spacingChanged = abs(mainLineSpacingAppliedValue - targetSpacing) > 0.01
        let responderChanged = mainLineSpacingAppliedResponderID != responderID
        let shouldApplyFull = forceApplyToFullText || isNewCard || spacingChanged
        let currentTypingSpacing =
            ((textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.lineSpacing ?? 0)
        let currentDefaultSpacing = textView.defaultParagraphStyle?.lineSpacing ?? 0
        let needsTypingUpdate = abs(currentTypingSpacing - targetSpacing) > 0.01
        let needsDefaultUpdate = abs(currentDefaultSpacing - targetSpacing) > 0.01

        if shouldApplyFull, let storage = textView.textStorage, storage.length > 0 {
            let paragraph = (textView.defaultParagraphStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            paragraph.lineSpacing = targetSpacing
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.lineHeightMultiple = 1.0
            paragraph.paragraphSpacing = 0
            paragraph.paragraphSpacingBefore = 0
            storage.beginEditing()
            storage.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: storage.length))
            storage.endEditing()
        }

        var typing = textView.typingAttributes
        if needsTypingUpdate || needsDefaultUpdate || shouldApplyFull {
            let typingParagraph =
                (textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ??
                (textView.defaultParagraphStyle?.mutableCopy() as? NSMutableParagraphStyle) ??
                NSMutableParagraphStyle()
            typingParagraph.lineSpacing = targetSpacing
            typingParagraph.lineBreakMode = .byWordWrapping
            typingParagraph.lineHeightMultiple = 1.0
            typingParagraph.paragraphSpacing = 0
            typingParagraph.paragraphSpacingBefore = 0
            textView.defaultParagraphStyle = typingParagraph
            typing[.paragraphStyle] = typingParagraph
            textView.typingAttributes = typing
        }

        mainLineSpacingAppliedCardID = editingID
        mainLineSpacingAppliedValue = targetSpacing
        mainLineSpacingAppliedResponderID = responderID

        _ = responderChanged
    }

    func handleMainEditorContentChange(cardID: UUID, oldValue: String, newValue: String) {
        guard !showFocusMode else { return }
        guard editingCardID == cardID else { return }
        handleMainTypingContentChange(cardID: cardID, oldValue: oldValue, newValue: newValue)
        let oldLineCount = oldValue.reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
        let newLineCount = newValue.reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
        _ = oldLineCount
        _ = newLineCount
        applyMainEditorLineSpacingIfNeeded()
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           textView.window?.identifier?.rawValue != ReferenceWindowConstants.windowID,
           textView.string == newValue {
            normalizeMainEditorTextViewOffsetIfNeeded(textView, reason: "content-change")
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
        guard !showFocusMode else { return }
        guard let editingID = editingCardID, let card = findCard(by: editingID) else { return }
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        guard textView.string == card.content else { return }
        normalizeMainEditorTextViewOffsetIfNeeded(textView, reason: "ensure-visible")
        guard let outerScrollView = outerScrollView(containing: textView) else { return }
        guard let outerDocumentView = outerScrollView.documentView else { return }
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)

        let textLength = (textView.string as NSString).length
        let sel = textView.selectedRange()
        let selStart = min(sel.location, textLength)
        let selEnd = min(sel.location + sel.length, textLength)

        func caretRectInDocument(at location: Int) -> CGRect {
            let gr = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: location, length: 0),
                actualCharacterRange: nil
            )
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

        var targetY = visible.origin.y
        if sel.length > 0 {
            switch mainSelectionActiveEdge {
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

        let clampedY = min(max(minY, targetY), maxY)
        if abs(clampedY - visible.origin.y) > 1.0 {
            outerScrollView.contentView.setBoundsOrigin(NSPoint(x: visible.origin.x, y: clampedY))
            outerScrollView.reflectScrolledClipView(outerScrollView.contentView)
        }
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
            if retries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) {
                    applyMainCaretWithRetry(expectedCardID: expectedCardID, location: location, retries: retries - 1, requestID: requestID)
                }
            }
            return
        }
        guard textView.string == card.content else {
            if retries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) {
                    applyMainCaretWithRetry(expectedCardID: expectedCardID, location: location, retries: retries - 1, requestID: requestID)
                }
            }
            return
        }
        let length = (textView.string as NSString).length
        let safeLocation = min(max(0, location), length)
        let current = textView.selectedRange()
        guard current.location != safeLocation || current.length != 0 else { return }
        textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
        textView.scrollRangeToVisible(NSRange(location: safeLocation, length: 0))
    }

    func resolvedMainCaretLocation(for card: SceneCard) -> Int? {
        rememberMainCaretLocation(for: card.id)
        guard let saved = mainCaretLocationByCardID[card.id] else { return nil }
        let length = (card.content as NSString).length
        return min(max(0, saved), length)
    }

    func focusLineEndLocation(in text: NSString, lineRange: NSRange) -> Int {
        var lineEnd = NSMaxRange(lineRange)
        if lineEnd > lineRange.location && lineEnd <= text.length {
            let lastChar = text.character(at: lineEnd - 1)
            if lastChar == 10 || lastChar == 13 { // \n or \r
                lineEnd -= 1
            }
        }
        return min(max(lineRange.location, lineEnd), text.length)
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

    func focusCaretVisualBoundaryState(textView: NSTextView, cursor: Int) -> FocusCaretVisualBoundaryState? {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return nil }
        layoutManager.ensureLayout(for: textContainer)

        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard glyphRange.length > 0 else {
            return FocusCaretVisualBoundaryState(
                isTop: true,
                isBottom: true,
                caretMidY: 0,
                firstLineMinY: 0,
                firstLineMaxY: 0,
                lastLineMinY: 0,
                lastLineMaxY: 0
            )
        }

        let firstGlyphIndex = glyphRange.location
        let lastGlyphIndex = max(firstGlyphIndex, NSMaxRange(glyphRange) - 1)

        let insets = textView.textContainerInset
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

        let textLength = (textView.string as NSString).length
        let safeCursor = min(max(0, cursor), textLength)
        let insertionGlyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: safeCursor, length: 0),
            actualCharacterRange: nil
        )

        var caretRect = layoutManager.boundingRect(forGlyphRange: insertionGlyphRange, in: textContainer)
        let caretRectFinite =
            caretRect.origin.x.isFinite &&
            caretRect.origin.y.isFinite &&
            caretRect.size.width.isFinite &&
            caretRect.size.height.isFinite
        if caretRect.isEmpty || !caretRectFinite {
            let fallbackGlyph = min(max(firstGlyphIndex, insertionGlyphRange.location), lastGlyphIndex)
            caretRect = layoutManager.lineFragmentUsedRect(
                forGlyphAt: fallbackGlyph,
                effectiveRange: nil,
                withoutAdditionalLayout: true
            )
        }

        let firstLineMinY = firstLineRect.minY + insets.height
        let firstLineMaxY = firstLineRect.maxY + insets.height
        let lastLineMinY = lastLineRect.minY + insets.height
        let lastLineMaxY = lastLineRect.maxY + insets.height
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

}
