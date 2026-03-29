import SwiftUI
import AppKit

private func resolveFocusModeTextFont(_ fontSize: CGFloat) -> NSFont {
    NSFont(name: "SansMonoCJKFinalDraft", size: fontSize)
        ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
}

private func resolveFocusModeTextColor(_ appearance: String) -> NSColor {
    appearance == "light" ? .black : .white
}

private func makeFocusModeRenderParagraphStyle(_ lineSpacing: CGFloat) -> NSMutableParagraphStyle {
    makeSharedRenderParagraphStyle(lineSpacing)
}

private func makeFocusModeAttributedString(
    _ text: String,
    fontSize: CGFloat,
    lineSpacing: CGFloat,
    appearance: String
) -> NSAttributedString {
    NSAttributedString(
        string: text,
        attributes: [
            .font: resolveFocusModeTextFont(fontSize),
            .foregroundColor: resolveFocusModeTextColor(appearance),
            .paragraphStyle: makeFocusModeRenderParagraphStyle(lineSpacing)
        ]
    )
}

private func resolvedFocusModeObservedBodyHeight(_ textView: NSTextView) -> CGFloat? {
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

struct FocusModeReadOnlyTextRenderer: NSViewRepresentable {
    struct Signature: Equatable {
        let text: String
        let textWidthBucket: Int
        let bodyHeightBucket: Int
        let fontSizeBucket: Int
        let lineSpacingBucket: Int
        let isLightAppearance: Bool
    }

    final class Coordinator {
        var lastSignature: Signature?
    }

    let text: String
    let textWidth: CGFloat
    let bodyHeight: CGFloat
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let appearance: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: textWidth, height: bodyHeight))
        textView.isEditable = false
        textView.isSelectable = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.usesFindBar = false
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        if let textContainer = textView.textContainer {
            textContainer.lineFragmentPadding = FocusModeLayoutMetrics.focusModeLineFragmentPadding
            textContainer.lineBreakMode = .byWordWrapping
            textContainer.maximumNumberOfLines = 0
            textContainer.widthTracksTextView = false
            textContainer.heightTracksTextView = false
            textContainer.containerSize = CGSize(width: textWidth, height: .greatestFiniteMagnitude)
        }

        updateTextView(textView, coordinator: context.coordinator)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        updateTextView(textView, coordinator: context.coordinator)
    }

    private func updateTextView(_ textView: NSTextView, coordinator: Coordinator) {
        let signature = Signature(
            text: text,
            textWidthBucket: Int((textWidth * 10).rounded()),
            bodyHeightBucket: Int((bodyHeight * 10).rounded()),
            fontSizeBucket: Int((fontSize * 10).rounded()),
            lineSpacingBucket: Int((lineSpacing * 10).rounded()),
            isLightAppearance: appearance == "light"
        )

        let resolvedWidth = max(1, textWidth)
        let resolvedHeight = max(1, bodyHeight)
        let targetFrame = NSRect(x: 0, y: 0, width: resolvedWidth, height: resolvedHeight)
        if abs(textView.frame.origin.x - targetFrame.origin.x) > 0.01 ||
            abs(textView.frame.origin.y - targetFrame.origin.y) > 0.01 ||
            abs(textView.frame.width - targetFrame.width) > 0.5 ||
            abs(textView.frame.height - targetFrame.height) > 0.5 {
            textView.frame = targetFrame
        }
        if textView.textContainerInset != .zero {
            textView.textContainerInset = .zero
        }

        if let textContainer = textView.textContainer,
           abs(textContainer.containerSize.width - resolvedWidth) > 0.5 {
            textContainer.containerSize = CGSize(width: resolvedWidth, height: .greatestFiniteMagnitude)
        }

        guard coordinator.lastSignature != signature else { return }
        coordinator.lastSignature = signature

        let font = resolveFocusModeTextFont(fontSize)
        let color = resolveFocusModeTextColor(appearance)
        let attributedString = makeFocusModeAttributedString(
            text,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            appearance: appearance
        )
        textView.textStorage?.setAttributedString(attributedString)
        textView.textColor = color
        textView.font = font
    }
}

struct FocusModeEditableTextRenderer: NSViewRepresentable {
    struct Signature: Equatable {
        let textWidthBucket: Int
        let bodyHeightBucket: Int
        let fontSizeBucket: Int
        let lineSpacingBucket: Int
        let isLightAppearance: Bool
        let isFocused: Bool
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FocusModeEditableTextRenderer
        var suppressBindingPropagation = false
        var lastSignature: Signature?

        init(_ parent: FocusModeEditableTextRenderer) {
            self.parent = parent
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            parent.layoutCoordinator.beginLiveEditorMutation(for: parent.cardID)
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.reportLiveEditorLayout(from: textView)
            guard !suppressBindingPropagation else { return }
            let updated = textView.string
            if parent.text != updated {
                parent.text = updated
            }
        }
    }

    @Binding var text: String
    let cardID: UUID
    let layoutCoordinator: FocusModeLayoutCoordinator
    let textWidth: CGFloat
    let bodyHeight: CGFloat
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let appearance: String
    let isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: textWidth, height: bodyHeight))
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.usesFindBar = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        if let textContainer = textView.textContainer {
            textContainer.lineFragmentPadding = FocusModeLayoutMetrics.focusModeLineFragmentPadding
            textContainer.lineBreakMode = .byWordWrapping
            textContainer.maximumNumberOfLines = 0
            textContainer.widthTracksTextView = false
            textContainer.heightTracksTextView = false
            textContainer.containerSize = CGSize(width: textWidth, height: .greatestFiniteMagnitude)
        }

        updateTextView(textView, coordinator: context.coordinator)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.parent = self
        if textView.delegate !== context.coordinator {
            textView.delegate = context.coordinator
        }
        updateTextView(textView, coordinator: context.coordinator)
    }

    private func reportLiveEditorLayout(from textView: NSTextView) {
        guard let observedBodyHeight = resolvedFocusModeObservedBodyHeight(textView) else { return }
        layoutCoordinator.reportLiveEditorLayout(
            for: cardID,
            rawText: textView.string,
            bodyHeight: observedBodyHeight,
            textWidth: textWidth,
            fontSize: Double(fontSize),
            lineSpacing: Double(lineSpacing)
        )
    }

    private func updateTextView(_ textView: NSTextView, coordinator: Coordinator) {
        let signature = Signature(
            textWidthBucket: Int((textWidth * 10).rounded()),
            bodyHeightBucket: Int((bodyHeight * 10).rounded()),
            fontSizeBucket: Int((fontSize * 10).rounded()),
            lineSpacingBucket: Int((lineSpacing * 10).rounded()),
            isLightAppearance: appearance == "light",
            isFocused: isFocused
        )

        let resolvedWidth = max(1, textWidth)
        let resolvedHeight = max(1, bodyHeight)
        let targetFrame = NSRect(x: 0, y: 0, width: resolvedWidth, height: resolvedHeight)
        if abs(textView.frame.origin.x - targetFrame.origin.x) > 0.01 ||
            abs(textView.frame.origin.y - targetFrame.origin.y) > 0.01 ||
            abs(textView.frame.width - targetFrame.width) > 0.5 ||
            abs(textView.frame.height - targetFrame.height) > 0.5 {
            textView.frame = targetFrame
        }
        if textView.textContainerInset != .zero {
            textView.textContainerInset = .zero
        }

        if let textContainer = textView.textContainer {
            if abs(textContainer.containerSize.width - resolvedWidth) > 0.5 {
                textContainer.containerSize = CGSize(width: resolvedWidth, height: .greatestFiniteMagnitude)
            }
            if abs(textContainer.lineFragmentPadding - FocusModeLayoutMetrics.focusModeLineFragmentPadding) > 0.01 {
                textContainer.lineFragmentPadding = FocusModeLayoutMetrics.focusModeLineFragmentPadding
            }
            textContainer.lineBreakMode = .byWordWrapping
            textContainer.maximumNumberOfLines = 0
            textContainer.widthTracksTextView = false
            textContainer.heightTracksTextView = false
        }

        let font = resolveFocusModeTextFont(fontSize)
        let color = resolveFocusModeTextColor(appearance)
        let paragraph = makeFocusModeRenderParagraphStyle(lineSpacing)

        if textView.string != text {
            let selected = textView.selectedRange()
            coordinator.suppressBindingPropagation = true
            if text.isEmpty {
                textView.string = ""
            } else {
                textView.textStorage?.setAttributedString(
                    makeFocusModeAttributedString(
                        text,
                        fontSize: fontSize,
                        lineSpacing: lineSpacing,
                        appearance: appearance
                    )
                )
            }
            let clampedLocation = min(selected.location, (text as NSString).length)
            let clampedLength = min(selected.length, max(0, (text as NSString).length - clampedLocation))
            textView.setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
            coordinator.suppressBindingPropagation = false
        }

        if coordinator.lastSignature != signature {
            coordinator.lastSignature = signature
            textView.font = font
            textView.textColor = color
            textView.insertionPointColor = color
            textView.defaultParagraphStyle = paragraph
            if let storage = textView.textStorage, storage.length > 0 {
                storage.beginEditing()
                storage.addAttributes(
                    [
                        .font: font,
                        .foregroundColor: color,
                        .paragraphStyle: paragraph
                    ],
                    range: NSRange(location: 0, length: storage.length)
                )
                storage.endEditing()
            }
            var typing = textView.typingAttributes
            typing[.font] = font
            typing[.foregroundColor] = color
            typing[.paragraphStyle] = paragraph
            textView.typingAttributes = typing
        }

        if isFocused,
           let window = textView.window,
           window.firstResponder !== textView {
            DispatchQueue.main.async {
                guard isFocused else { return }
                guard let liveWindow = textView.window, liveWindow.firstResponder !== textView else { return }
                liveWindow.makeFirstResponder(textView)
            }
        }

        reportLiveEditorLayout(from: textView)
    }
}

struct MainWorkspaceEditableTextRenderer: NSViewRepresentable {
    struct Signature: Equatable {
        let textWidthBucket: Int
        let bodyHeightBucket: Int
        let fontSizeBucket: Int
        let lineSpacingBucket: Int
        let isLightAppearance: Bool
    }

    final class TextView: NSTextView {
        var debugCardID: UUID?
        var fixedTextWidth: CGFloat = 0
        var onLayoutPass: ((NSTextView) -> Void)?
        var focusStateHandler: ((Bool) -> Void)?

        private var isApplyingFrameConstraint = false

        private func clampFrameToFixedGeometryIfNeeded() {
            guard !isApplyingFrameConstraint, fixedTextWidth > 1 else { return }
            let resolvedWidth = round(fixedTextWidth)
            guard abs(frame.origin.x) > 0.01 || abs(frame.origin.y) > 0.01 || abs(frame.width - resolvedWidth) > 0.01 else { return }
            isApplyingFrameConstraint = true
            super.setFrameOrigin(.zero)
            super.setFrameSize(NSSize(width: resolvedWidth, height: frame.height))
            isApplyingFrameConstraint = false
        }

        override func setFrameSize(_ newSize: NSSize) {
            let resolvedWidth = fixedTextWidth > 1 ? round(fixedTextWidth) : newSize.width
            super.setFrameSize(NSSize(width: resolvedWidth, height: newSize.height))
        }

        override func setFrameOrigin(_ newOrigin: NSPoint) {
            super.setFrameOrigin(.zero)
        }

        override func layout() {
            super.layout()
            clampFrameToFixedGeometryIfNeeded()
            onLayoutPass?(self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            mainWorkspacePhase0Log(
                "appkit-inline-window",
                "card=\(mainWorkspacePhase0CardID(self.debugCardID)) \(mainWorkspacePhase0TextViewSummary(self))"
            )
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            mainWorkspacePhase0Log(
                "appkit-inline-superview",
                "card=\(mainWorkspacePhase0CardID(self.debugCardID)) \(mainWorkspacePhase0TextViewSummary(self))"
            )
        }

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            mainWorkspacePhase0Log(
                "appkit-inline-become-first-responder",
                "card=\(mainWorkspacePhase0CardID(self.debugCardID)) accepted=\(accepted) \(mainWorkspacePhase0TextViewSummary(self))"
            )
            if accepted {
                focusStateHandler?(true)
            }
            return accepted
        }

        override func resignFirstResponder() -> Bool {
            let accepted = super.resignFirstResponder()
            mainWorkspacePhase0Log(
                "appkit-inline-resign-first-responder",
                "card=\(mainWorkspacePhase0CardID(self.debugCardID)) accepted=\(accepted) \(mainWorkspacePhase0TextViewSummary(self))"
            )
            if accepted {
                focusStateHandler?(false)
            }
            return accepted
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MainWorkspaceEditableTextRenderer
        var suppressBindingPropagation = false
        var lastSignature: Signature?
        var pendingFocusRetry: DispatchWorkItem?
        var sessionEnded = false
        var focusSettled = false
        var lastRenderedCardID: UUID?
        private var lastLoggedLayoutBodyBucket: Int?
        private var lastLoggedLayoutFrameBucket: String?
        private var lastReportedMeasuredBodyHeight: CGFloat?
        private var lastReportedMeasuredBodyCardID: UUID?

        init(_ parent: MainWorkspaceEditableTextRenderer) {
            self.parent = parent
        }

        deinit {
            pendingFocusRetry?.cancel()
        }

        func log(_ event: String, _ textView: NSTextView? = nil, _ details: String = "") {
            let summary: String
            if let textView {
                summary = mainWorkspacePhase0TextViewSummary(textView, expectedText: parent.text)
            } else {
                summary = "textView=nil"
            }
            let detailSuffix = details.isEmpty ? "" : " \(details)"
            mainWorkspacePhase0Log(
                event,
                "card=\(mainWorkspacePhase0CardID(self.parent.cardID))\(detailSuffix) \(summary)"
            )
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            let replacementLength = (replacementString ?? "") .count
            log(
                "appkit-inline-should-change",
                textView,
                "range=\(affectedCharRange.location):\(affectedCharRange.length) replacementLen=\(replacementLength)"
            )
            return true
        }

        func textDidBeginEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            sessionEnded = false
            focusSettled = false
            log("appkit-inline-begin-edit", textView)
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            sessionEnded = true
            focusSettled = false
            pendingFocusRetry?.cancel()
            pendingFocusRetry = nil
            log("appkit-inline-end-edit", textView)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            reportLayout(from: textView, reason: "textDidChange")
            guard !suppressBindingPropagation else {
                log("appkit-inline-text-change-suppressed", textView)
                return
            }
            let updated = textView.string
            if parent.text != updated {
                log("appkit-inline-text-change", textView, "bindingUpdate=true")
                parent.text = updated
            } else {
                log("appkit-inline-text-change", textView, "bindingUpdate=false")
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            log("appkit-inline-selection-change", textView)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            log("appkit-inline-command", textView, "selector=\(NSStringFromSelector(commandSelector))")
            return parent.onCommandBy(commandSelector)
        }

        func reportLayout(from textView: NSTextView, reason: String) {
            if reason == "layout" && parent.shouldSkipLayoutMeasurement() {
                return
            }
            let measured = sharedLiveTextViewBodyHeight(textView)
            let previousReportedHeight = lastReportedMeasuredBodyHeight
            let shouldReportMeasuredHeight: Bool
            if lastReportedMeasuredBodyCardID != parent.cardID {
                shouldReportMeasuredHeight = true
            } else {
                let threshold = MainEditorLayoutMetrics.mainEditorHeightUpdateThreshold
                switch (previousReportedHeight, measured) {
                case let (previous?, current?):
                    shouldReportMeasuredHeight = abs(previous - current) > threshold
                case (nil, nil):
                    shouldReportMeasuredHeight = false
                default:
                    shouldReportMeasuredHeight = true
                }
            }
            if shouldReportMeasuredHeight {
                lastReportedMeasuredBodyCardID = parent.cardID
                lastReportedMeasuredBodyHeight = measured
                parent.onMeasuredBodyHeightChange(measured)
            }

            let bodyBucket = measured.map { Int(($0 * 10).rounded()) } ?? -1
            let frameBucket = "\(Int((textView.frame.width * 10).rounded()))x\(Int((textView.frame.height * 10).rounded()))"
            let shouldLog =
                reason != "layout" ||
                lastLoggedLayoutBodyBucket != bodyBucket ||
                lastLoggedLayoutFrameBucket != frameBucket
            if shouldLog {
                lastLoggedLayoutBodyBucket = bodyBucket
                lastLoggedLayoutFrameBucket = frameBucket
                let measuredSummary = measured.map { String(format: "%.1f", $0) } ?? "nil"
                log(
                    "appkit-inline-layout",
                    textView,
                    "reason=\(reason) measured=\(measuredSummary)"
                )
            }
        }

        func handleLayoutPass(_ textView: NSTextView) {
            reportLayout(from: textView, reason: "layout")
        }

        func handleFocusStateChange(_ isFocused: Bool) {
            parent.onFocusStateChange(isFocused)
        }

        func beginUpdate(cardID: UUID) -> Bool {
            let cardDidChange = lastRenderedCardID != cardID
            lastRenderedCardID = cardID
            return cardDidChange
        }

        func requestFocus(for textView: NSTextView, remainingRetries: Int = 4) {
            pendingFocusRetry?.cancel()
            let work = DispatchWorkItem { [weak textView, weak self] in
                guard let self, let textView else { return }
                self.pendingFocusRetry = nil
                guard self.parent.isFocused else {
                    self.log("appkit-inline-focus-skip", textView, "reason=notFocused")
                    return
                }
                guard let window = textView.window else {
                    self.log("appkit-inline-focus-wait", textView, "reason=noWindow retries=\(remainingRetries)")
                    if remainingRetries > 0 {
                        self.requestFocus(for: textView, remainingRetries: remainingRetries - 1)
                    }
                    return
                }
                let before = window.firstResponder === textView
                self.log("appkit-inline-focus-attempt", textView, "before=\(before) retries=\(remainingRetries)")
                if !before {
                    window.makeFirstResponder(textView)
                }
                let after = window.firstResponder === textView
                if after {
                    self.focusSettled = true
                }
                self.log("appkit-inline-focus-result", textView, "after=\(after) retries=\(remainingRetries)")
                if !after, remainingRetries > 0 {
                    self.requestFocus(for: textView, remainingRetries: remainingRetries - 1)
                }
            }
            pendingFocusRetry = work
            if Thread.isMainThread, textView.window != nil {
                work.perform()
            } else {
                DispatchQueue.main.async(execute: work)
            }
        }
    }

    @Binding var text: String
    let cardID: UUID
    let textWidth: CGFloat
    let bodyHeight: CGFloat
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let appearance: String
    let isFocused: Bool
    let selectionSeedLocation: Int?
    let onFocusStateChange: (Bool) -> Void
    let onMeasuredBodyHeightChange: (CGFloat?) -> Void
    let shouldSkipLayoutMeasurement: () -> Bool
    let onCommandBy: (Selector) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = TextView(frame: NSRect(x: 0, y: 0, width: textWidth, height: bodyHeight))
        textView.debugCardID = cardID
        textView.fixedTextWidth = round(textWidth)
        textView.onLayoutPass = { [weak coordinator = context.coordinator] liveTextView in
            coordinator?.handleLayoutPass(liveTextView)
        }
        textView.focusStateHandler = { [weak coordinator = context.coordinator] isFocused in
            coordinator?.handleFocusStateChange(isFocused)
        }
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.usesFindBar = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        if let textContainer = textView.textContainer {
            textContainer.lineFragmentPadding = MainEditorLayoutMetrics.mainEditorLineFragmentPadding
            textContainer.lineBreakMode = .byWordWrapping
            textContainer.maximumNumberOfLines = 0
            textContainer.widthTracksTextView = false
            textContainer.heightTracksTextView = false
            textContainer.containerSize = CGSize(width: textWidth, height: .greatestFiniteMagnitude)
        }

        context.coordinator.log("appkit-inline-make", textView)
        updateTextView(textView, coordinator: context.coordinator)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.parent = self
        if textView.delegate !== context.coordinator {
            textView.delegate = context.coordinator
        }
        if let textView = textView as? TextView {
            if textView.debugCardID != cardID {
                textView.debugCardID = cardID
            }
            let resolvedTextWidth = round(textWidth)
            if abs(textView.fixedTextWidth - resolvedTextWidth) > 0.5 {
                textView.fixedTextWidth = resolvedTextWidth
            }
        }
        context.coordinator.log("appkit-inline-update", textView, "focused=\(isFocused)")
        if context.coordinator.sessionEnded && !isFocused {
            context.coordinator.log("appkit-inline-update-suppressed", textView)
            return
        }
        updateTextView(textView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ textView: NSTextView, coordinator: Coordinator) {
        coordinator.log("appkit-inline-dismantle", textView)
        coordinator.sessionEnded = true
        coordinator.focusSettled = false
        coordinator.pendingFocusRetry?.cancel()
        coordinator.pendingFocusRetry = nil
        textView.delegate = nil
        if let textView = textView as? TextView {
            textView.onLayoutPass = nil
            textView.focusStateHandler = nil
        }
    }

    private func updateTextView(_ textView: NSTextView, coordinator: Coordinator) {
        let cardDidChange = coordinator.beginUpdate(cardID: cardID)
        let signature = Signature(
            textWidthBucket: Int((textWidth * 10).rounded()),
            bodyHeightBucket: Int((bodyHeight * 10).rounded()),
            fontSizeBucket: Int((fontSize * 10).rounded()),
            lineSpacingBucket: Int((lineSpacing * 10).rounded()),
            isLightAppearance: appearance == "light"
        )

        let resolvedWidth = max(1, textWidth)
        let resolvedHeight = max(1, bodyHeight)
        let targetFrame = NSRect(x: 0, y: 0, width: resolvedWidth, height: resolvedHeight)
        if abs(textView.frame.origin.x - targetFrame.origin.x) > 0.01 ||
            abs(textView.frame.origin.y - targetFrame.origin.y) > 0.01 ||
            abs(textView.frame.width - targetFrame.width) > 0.5 ||
            abs(textView.frame.height - targetFrame.height) > 0.5 {
            textView.frame = targetFrame
        }
        if textView.textContainerInset != .zero {
            textView.textContainerInset = .zero
        }

        if let textContainer = textView.textContainer {
            if abs(textContainer.containerSize.width - resolvedWidth) > 0.5 {
                textContainer.containerSize = CGSize(width: resolvedWidth, height: .greatestFiniteMagnitude)
            }
            if abs(textContainer.lineFragmentPadding - MainEditorLayoutMetrics.mainEditorLineFragmentPadding) > 0.01 {
                textContainer.lineFragmentPadding = MainEditorLayoutMetrics.mainEditorLineFragmentPadding
            }
            if textContainer.lineBreakMode != .byWordWrapping {
                textContainer.lineBreakMode = .byWordWrapping
            }
            if textContainer.maximumNumberOfLines != 0 {
                textContainer.maximumNumberOfLines = 0
            }
            if textContainer.widthTracksTextView {
                textContainer.widthTracksTextView = false
            }
            if textContainer.heightTracksTextView {
                textContainer.heightTracksTextView = false
            }
        }

        let font = resolveFocusModeTextFont(fontSize)
        let color = resolveFocusModeTextColor(appearance)
        let paragraph = makeFocusModeRenderParagraphStyle(lineSpacing)
        let seedLocation = selectionSeedLocation.map { min(max(0, $0), (text as NSString).length) }

        if textView.string != text {
            let selected = textView.selectedRange()
            coordinator.suppressBindingPropagation = true
            if text.isEmpty {
                textView.string = ""
            } else {
                textView.textStorage?.setAttributedString(
                    makeFocusModeAttributedString(
                        text,
                        fontSize: fontSize,
                        lineSpacing: lineSpacing,
                        appearance: appearance
                    )
                )
            }
            let length = (text as NSString).length
            if cardDidChange, let seedLocation {
                textView.setSelectedRange(NSRange(location: seedLocation, length: 0))
                coordinator.log(
                    "appkit-inline-sync-text",
                    textView,
                    "newLen=\(length) seededSel=\(seedLocation):0"
                )
            } else {
                let clampedLocation = min(selected.location, length)
                let clampedLength = min(selected.length, max(0, length - clampedLocation))
                textView.setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
                coordinator.log(
                    "appkit-inline-sync-text",
                    textView,
                    "newLen=\(length) preservedSel=\(clampedLocation):\(clampedLength)"
                )
            }
            coordinator.suppressBindingPropagation = false
        }

        if cardDidChange, let seedLocation {
            let length = (textView.string as NSString).length
            let safeLocation = min(seedLocation, length)
            let selected = textView.selectedRange()
            if selected.location != safeLocation || selected.length != 0 {
                textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
                coordinator.log("appkit-inline-selection-seed", textView, "location=\(safeLocation)")
            }
        }

        if coordinator.lastSignature != signature {
            coordinator.lastSignature = signature
            textView.font = font
            textView.textColor = color
            textView.insertionPointColor = color
            textView.defaultParagraphStyle = paragraph
            if let storage = textView.textStorage, storage.length > 0 {
                storage.beginEditing()
                storage.addAttributes(
                    [
                        .font: font,
                        .foregroundColor: color,
                        .paragraphStyle: paragraph
                    ],
                    range: NSRange(location: 0, length: storage.length)
                )
                storage.endEditing()
            }
            var typing = textView.typingAttributes
            typing[.font] = font
            typing[.foregroundColor] = color
            typing[.paragraphStyle] = paragraph
            textView.typingAttributes = typing
            coordinator.log("appkit-inline-signature", textView, "focused=\(isFocused)")
        }

        if isFocused && !coordinator.focusSettled {
            coordinator.requestFocus(for: textView)
        }
    }
}
