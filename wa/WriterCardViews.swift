import SwiftUI
import AppKit
import UniformTypeIdentifiers

private func resolveFocusModeTextFont(_ fontSize: CGFloat) -> NSFont {
    NSFont(name: "SansMonoCJKFinalDraft", size: fontSize)
        ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
}

private func resolveFocusModeTextColor(_ appearance: String) -> NSColor {
    appearance == "light" ? .black : .white
}

private func makeFocusModeRenderParagraphStyle(_ lineSpacing: CGFloat) -> NSMutableParagraphStyle {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = lineSpacing
    paragraphStyle.lineBreakMode = .byWordWrapping
    paragraphStyle.lineHeightMultiple = 1.0
    paragraphStyle.paragraphSpacing = 0
    paragraphStyle.paragraphSpacingBefore = 0
    return paragraphStyle
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

private struct FocusModeReadOnlyTextRenderer: NSViewRepresentable {
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
        textView.frame = NSRect(x: 0, y: 0, width: resolvedWidth, height: resolvedHeight)
        textView.textContainerInset = .zero

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

private struct FocusModeEditableTextRenderer: NSViewRepresentable {
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
        textView.frame = NSRect(x: 0, y: 0, width: resolvedWidth, height: resolvedHeight)
        textView.textContainerInset = .zero

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
        private var lastLoggedLayoutBodyBucket: Int?
        private var lastLoggedLayoutFrameBucket: String?

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
            reportLayout(from: textView, reason: "selection")
            log("appkit-inline-selection-change", textView)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            log("appkit-inline-command", textView, "selector=\(NSStringFromSelector(commandSelector))")
            return parent.onCommandBy(commandSelector)
        }

        func reportLayout(from textView: NSTextView, reason: String) {
            let measured = sharedLiveTextViewBodyHeight(textView)
            parent.onMeasuredBodyHeightChange(measured)

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

        func requestFocus(for textView: NSTextView, remainingRetries: Int = 4) {
            pendingFocusRetry?.cancel()
            let work = DispatchWorkItem { [weak textView, weak self] in
                guard let self, let textView else { return }
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
            DispatchQueue.main.async(execute: work)
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
    let onFocusStateChange: (Bool) -> Void
    let onMeasuredBodyHeightChange: (CGFloat?) -> Void
    let onCommandBy: (Selector) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = TextView(frame: NSRect(x: 0, y: 0, width: textWidth, height: bodyHeight))
        textView.debugCardID = cardID
        textView.fixedTextWidth = round(textWidth)
        textView.onLayoutPass = { liveTextView in
            context.coordinator.reportLayout(from: liveTextView, reason: "layout")
        }
        textView.focusStateHandler = onFocusStateChange
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
            textView.debugCardID = cardID
            textView.fixedTextWidth = round(textWidth)
            textView.onLayoutPass = { liveTextView in
                context.coordinator.reportLayout(from: liveTextView, reason: "layout")
            }
            textView.focusStateHandler = onFocusStateChange
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
        let signature = Signature(
            textWidthBucket: Int((textWidth * 10).rounded()),
            bodyHeightBucket: Int((bodyHeight * 10).rounded()),
            fontSizeBucket: Int((fontSize * 10).rounded()),
            lineSpacingBucket: Int((lineSpacing * 10).rounded()),
            isLightAppearance: appearance == "light"
        )

        let resolvedWidth = max(1, textWidth)
        let resolvedHeight = max(1, bodyHeight)
        textView.frame = NSRect(x: 0, y: 0, width: resolvedWidth, height: resolvedHeight)
        textView.textContainerInset = .zero

        if let textContainer = textView.textContainer {
            if abs(textContainer.containerSize.width - resolvedWidth) > 0.5 {
                textContainer.containerSize = CGSize(width: resolvedWidth, height: .greatestFiniteMagnitude)
            }
            if abs(textContainer.lineFragmentPadding - MainEditorLayoutMetrics.mainEditorLineFragmentPadding) > 0.01 {
                textContainer.lineFragmentPadding = MainEditorLayoutMetrics.mainEditorLineFragmentPadding
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
            let length = (text as NSString).length
            let clampedLocation = min(selected.location, length)
            let clampedLength = min(selected.length, max(0, length - clampedLocation))
            textView.setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
            coordinator.suppressBindingPropagation = false
            coordinator.log(
                "appkit-inline-sync-text",
                textView,
                "newLen=\(length) preservedSel=\(clampedLocation):\(clampedLength)"
            )
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

        coordinator.reportLayout(from: textView, reason: "updateNSView")
    }
}

// MARK: - 카드 사이 및 열 상/하단 빈 공간 드롭 영역

struct DropSpacer: View {
    let target: DropTarget
    var alignment: Alignment = .center
    let onDrop: ([NSItemProvider], Bool) -> Void
    @AppStorage("mainCardVerticalGap") private var mainCardVerticalGap: Double = 0.0
    @State private var isHovering: Bool = false

    private var centerGapHeight: CGFloat { max(0, CGFloat(mainCardVerticalGap)) }
    private var centerHitAreaHeight: CGFloat { max(12, centerGapHeight) }

    var body: some View {
        Group {
            if alignment == .center {
                Color.clear
                    .frame(height: centerGapHeight)
                    .overlay(alignment: .center) {
                        ZStack {
                            Color.black.opacity(0.001)
                            if isHovering {
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(height: 4)
                                    .cornerRadius(2)
                                    .transition(.opacity)
                            }
                        }
                        .frame(height: centerHitAreaHeight)
                        .contentShape(Rectangle())
                        .onDrop(of: [.text], isTargeted: $isHovering) { providers in
                            onDrop(providers, isTrailingSiblingBlockDragActive())
                            return true
                        }
                    }
            } else {
                ZStack(alignment: alignment) {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())

                    if isHovering {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 4)
                            .cornerRadius(2)
                            .transition(.opacity)
                    }
                }
                .onDrop(of: [.text], isTargeted: $isHovering) { providers in
                    onDrop(providers, isTrailingSiblingBlockDragActive())
                    return true
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}

// MARK: - 히스토리 프리뷰 카드

struct PreviewCardItem: View {
    let diff: SnapshotDiff
    let isSelected: Bool
    let isMultiSelected: Bool
    var onSelect: () -> Void
    var onCopyCards: () -> Void
    var onCopyContents: () -> Void
    @AppStorage("fontSize") private var fontSize: Double = 14.0
    @AppStorage("appearance") private var appearance: String = "dark"

    private var statusColor: Color {
        switch diff.status {
        case .added: return Color.blue.opacity(0.15)
        case .modified: return Color.yellow.opacity(0.15)
        case .deleted: return Color.red.opacity(0.15)
        case .none: return appearance == "light" ? Color.white : Color(white: 0.18)
        }
    }

    private var statusStrokeColor: Color {
        switch diff.status {
        case .added: return .blue
        case .modified: return .yellow
        case .deleted: return .red
        case .none: return .secondary.opacity(0.3)
        }
    }

    private var selectionFillColor: Color {
        guard isSelected else { return .clear }
        return Color.accentColor.opacity(isMultiSelected ? 0.24 : 0.14)
    }

    private var selectionStrokeColor: Color {
        guard isSelected else { return .clear }
        return Color.accentColor.opacity(isMultiSelected ? 0.95 : 0.75)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if diff.status != .none {
                Text(statusLabel).font(.system(size: 9, weight: .bold)).foregroundColor(statusStrokeColor).padding(.horizontal, 6).padding(.vertical, 2).background(statusStrokeColor.opacity(0.1)).cornerRadius(4).padding([.top, .leading], 8)
            }
            Text(diff.snapshot.content.isEmpty ? "내용 없음" : diff.snapshot.content).font(.custom("SansMonoCJKFinalDraft", size: fontSize)).lineSpacing(1.4).padding(12).frame(maxWidth: .infinity, alignment: .leading).strikethrough(diff.status == .deleted).opacity(diff.status == .deleted ? 0.6 : 1.0)
        }
        .background(statusColor)
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(statusStrokeColor, lineWidth: diff.status == .none ? 1 : 2))
        .overlay(RoundedRectangle(cornerRadius: 4).fill(selectionFillColor))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(selectionStrokeColor, lineWidth: isSelected ? (isMultiSelected ? 2 : 1) : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("카드 복사") { onCopyCards() }
            Button("내용 복사") { onCopyContents() }
        }
    }

    private var statusLabel: String { switch diff.status { case .added: return "NEW"; case .modified: return "EDITED"; case .deleted: return "삭제됨"; case .none: return "" } }
}

// MARK: - 포커스 모드 카드 에디터

struct FocusModeCardEditor: View {
    @ObservedObject var card: SceneCard
    let isActive: Bool
    let showsEditor: Bool
    @ObservedObject var layoutCoordinator: FocusModeLayoutCoordinator
    let cardWidth: CGFloat
    let fontSize: Double
    let appearance: String
    let horizontalInset: CGFloat
    @FocusState.Binding var focusModeEditorCardID: UUID?
    let onActivate: (CGPoint?) -> Void
    let onContentChange: (String, String) -> Void

    @AppStorage("focusModeLineSpacingValueTemp") private var focusModeLineSpacingValue: Double = 4.5
    static let verticalInset: CGFloat = 40
    private var verticalInset: CGFloat { Self.verticalInset }
    private var shellHeight: CGFloat {
        layoutCoordinator.resolvedCardHeight(
            for: card,
            cardWidth: cardWidth,
            fontSize: fontSize,
            lineSpacing: focusModeLineSpacingValue,
            verticalInset: verticalInset,
            liveEditorCardID: showsEditor ? card.id : nil
        )
    }
    private var textEditorBodyHeight: CGFloat {
        max(1, shellHeight - (verticalInset * 2))
    }
    private var focusModeFontSize: CGFloat { CGFloat(fontSize * 1.2) }
    private var focusModeLineSpacing: CGFloat { CGFloat(focusModeLineSpacingValue) }
    private var displayText: String {
        normalizedSharedMeasurementText(card.content)
    }

    private var focusModeTextBinding: Binding<String> {
        Binding(
            get: { card.content },
            set: { newValue in
                let oldValue = card.content
                guard oldValue != newValue else { return }
                card.content = newValue
                onContentChange(oldValue, newValue)
            }
        )
    }

    var body: some View {
        Group {
            if showsEditor {
                focusModeCardContent
            } else {
                focusModeCardContent
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                onActivate(value.location)
                            }
                    )
                    .onTapGesture {
                        onActivate(nil)
                    }
            }
        }
    }

    @ViewBuilder
    private var focusModeCardContent: some View {
        ZStack(alignment: .topLeading) {
            if showsEditor {
                FocusModeEditableTextRenderer(
                    text: focusModeTextBinding,
                    cardID: card.id,
                    layoutCoordinator: layoutCoordinator,
                    textWidth: FocusModeLayoutMetrics.resolvedTextWidth(for: cardWidth),
                    bodyHeight: textEditorBodyHeight,
                    fontSize: focusModeFontSize,
                    lineSpacing: focusModeLineSpacing,
                    appearance: appearance,
                    isFocused: showsEditor
                )
                .frame(height: textEditorBodyHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, horizontalInset)
                .padding(.top, verticalInset)
                .padding(.bottom, verticalInset)
            } else {
                FocusModeReadOnlyTextRenderer(
                    text: displayText,
                    textWidth: FocusModeLayoutMetrics.resolvedTextWidth(for: cardWidth),
                    bodyHeight: textEditorBodyHeight,
                    fontSize: focusModeFontSize,
                    lineSpacing: focusModeLineSpacing,
                    appearance: appearance
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, horizontalInset)
                .padding(.top, verticalInset)
                .padding(.bottom, verticalInset)
                .allowsHitTesting(false)
            }
        }
        .frame(width: cardWidth, alignment: .topLeading)
        .frame(height: shellHeight, alignment: .topLeading)
    }

}

// MARK: - 메인 카드 아이템

struct CardItem: View {
    private enum InlineInsertZoneEdge {
        case top
        case bottom
        case trailing
    }

    @ObservedObject var card: SceneCard
    let renderSettings: MainCardRenderSettings
    let isActive, isSelected, isMultiSelected, isArchived, isAncestor, isDescendant, isEditing: Bool
    let preferredTextMeasureWidth: CGFloat
    let forceNamedSnapshotNoteStyle: Bool
    let forceCustomColorVisibility: Bool
    var onInsertSiblingAbove: (() -> Void)? = nil
    var onInsertSiblingBelow: (() -> Void)? = nil
    var onAddChildCard: (() -> Void)? = nil
    var onDropBefore: (([NSItemProvider], Bool) -> Void)? = nil
    var onDropAfter: (([NSItemProvider], Bool) -> Void)? = nil
    var onDropOnto: (([NSItemProvider], Bool) -> Void)? = nil
    var onSelect, onDoubleClick, onEndEdit: () -> Void
    var onSelectAtLocation: ((CGPoint) -> Void)? = nil
    var onContentChange: ((String, String) -> Void)? = nil
    var onColorChange: ((String?) -> Void)? = nil
    var onOpenIndexBoard: (() -> Void)? = nil
    var onReferenceCard: (() -> Void)? = nil
    var onCreateUpperCardFromSelection: (() -> Void)? = nil
    var onSummarizeChildren: (() -> Void)? = nil
    var onAIElaborate: (() -> Void)? = nil
    var onAINextScene: (() -> Void)? = nil
    var onAIAlternative: (() -> Void)? = nil
    var onAISummarizeCurrent: (() -> Void)? = nil
    var aiPlotActionsEnabled: Bool = false
    var onApplyAICandidate: (() -> Void)? = nil
    var isSummarizingChildren: Bool = false
    var isAIBusy: Bool = false
    var onDelete: (() -> Void)? = nil
    var onHardDelete: (() -> Void)? = nil
    var onTranscriptionMode: (() -> Void)? = nil
    var isTranscriptionBusy: Bool = false
    var showsEmptyCardBulkDeleteMenuOnly: Bool = false
    var onBulkDeleteEmptyCards: (() -> Void)? = nil
    var isCloneLinked: Bool = false
    var hasLinkedCards: Bool = false
    var isLinkedCard: Bool = false
    var onDisconnectLinkedCard: (() -> Void)? = nil
    var onCloneCard: (() -> Void)? = nil
    var clonePeerDestinations: [ClonePeerMenuDestination] = []
    var onNavigateToClonePeer: ((UUID) -> Void)? = nil
    var mainEditorSlotCoordinateSpaceName: String? = nil
    var mainEditorManagedExternally: Bool = false
    var usesExternalMainEditor: Bool = false
    var externalEditorLiveBodyHeight: CGFloat? = nil
    var onMainEditorMount: ((UUID) -> Void)? = nil
    var onMainEditorUnmount: ((UUID) -> Void)? = nil
    var onMainEditorFocusStateChange: ((UUID, Bool) -> Void)? = nil
    var handleEditorCommandBySelector: ((Selector) -> Bool)? = nil
    @State private var mainEditingMeasuredBodyHeight: CGFloat = 0
    @State private var mainEditingMeasureWorkItem: DispatchWorkItem? = nil
    @State private var mainEditingMeasureLastAt: Date = .distantPast
    @State private var isTopInsertZoneHovered: Bool = false
    @State private var isBottomInsertZoneHovered: Bool = false
    @State private var isTrailingInsertZoneHovered: Bool = false
    @State private var isTopInsertZoneDropTargeted: Bool = false
    @State private var isBottomInsertZoneDropTargeted: Bool = false
    @State private var isTrailingInsertZoneDropTargeted: Bool = false
    @State private var isBodyDropTargeted: Bool = false
    @FocusState private var editorFocus: Bool
    private var fontSize: CGFloat { renderSettings.fontSize }
    private var appearance: String { renderSettings.appearance }
    private var cardBaseColorHex: String { renderSettings.cardBaseColorHex }
    private var cardActiveColorHex: String { renderSettings.cardActiveColorHex }
    private var cardRelatedColorHex: String { renderSettings.cardRelatedColorHex }
    private var darkCardBaseColorHex: String { renderSettings.darkCardBaseColorHex }
    private var darkCardActiveColorHex: String { renderSettings.darkCardActiveColorHex }
    private var darkCardRelatedColorHex: String { renderSettings.darkCardRelatedColorHex }
    private var mainCardLineSpacing: CGFloat { renderSettings.lineSpacing }
    private let mainCardContentPadding: CGFloat = MainEditorLayoutMetrics.mainCardContentPadding
    private let mainEditorVerticalPadding: CGFloat = 24
    private let mainEditorLineFragmentPadding: CGFloat = MainEditorLayoutMetrics.mainEditorLineFragmentPadding
    private let mainEditingMeasureMinInterval: TimeInterval = 0.033
    private let mainEditingMeasureUpdateThreshold: CGFloat = 0.5
    private var mainEditorHorizontalPadding: CGFloat {
        MainEditorLayoutMetrics.mainEditorHorizontalPadding
    }

    private var usesDarkPalette: Bool {
        if appearance == "dark" { return true }
        if appearance == "light" { return false }
        if let best = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
            return best == .darkAqua
        }
        return true
    }

    private var isCandidateVisualCard: Bool {
        (forceCustomColorVisibility || card.isAICandidate) && card.colorHex != nil
    }
    private var shouldShowChildRightEdge: Bool {
        !isArchived && !card.children.isEmpty
    }
    private var hasAIMenuActions: Bool {
        onAIElaborate != nil
            || onAINextScene != nil
            || onAIAlternative != nil
            || onAISummarizeCurrent != nil
            || onSummarizeChildren != nil
    }
    private var resolvedCardRGB: (r: Double, g: Double, b: Double) {
        if forceNamedSnapshotNoteStyle {
            return resolvedNamedSnapshotNoteRGB()
        }
        let base = resolvedBaseRGB()
        if isMultiSelected {
            let overlay = usesDarkPalette ? (r: 0.42, g: 0.56, b: 0.78) : (r: 0.70, g: 0.83, b: 0.98)
            let amount = usesDarkPalette ? 0.58 : 0.62
            return mix(base: base, overlay: overlay, amount: amount)
        }
        if isCandidateVisualCard {
            return base
        }
        let active = resolvedActiveRGB()
        if isActive {
            return active
        }
        if isDescendant {
            return resolvedDescendantRGB()
        }
        if isAncestor {
            return resolvedRelatedRGB()
        }
        return base
    }

    private var childRightEdgeColor: Color {
        let amount = usesDarkPalette ? 0.34 : 0.24
        let rgb = mix(base: resolvedCardRGB, overlay: (0, 0, 0), amount: amount)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private var insertZoneHighlightColor: Color {
        usesDarkPalette ? Color.white.opacity(0.22) : Color.black.opacity(0.18)
    }

    private var insertIndicatorColor: Color {
        usesDarkPalette ? Color.white.opacity(0.92) : Color.black.opacity(0.72)
    }

    private var shouldShowInlineInsertControls: Bool {
        !isArchived && !isEditing
    }

    private var bodyDropTrailingInset: CGFloat {
        (shouldShowInlineInsertControls && onAddChildCard != nil) ? trailingInsertZoneWidth : 0
    }

    private var baseBackgroundColor: Color {
        if isArchived {
            return appearance == "light" ? Color.gray.opacity(0.25) : Color.gray.opacity(0.35)
        }
        if isMultiSelected {
            let base = resolvedBaseRGB()
            let overlay = usesDarkPalette ? (r: 0.42, g: 0.56, b: 0.78) : (r: 0.70, g: 0.83, b: 0.98)
            let amount = usesDarkPalette ? 0.58 : 0.62
            let rgb = mix(base: base, overlay: overlay, amount: amount)
            return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
        }
        let rgb = resolvedBaseRGB()
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private var relatedBackgroundColor: Color {
        let rgb = resolvedRelatedRGB()
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private var descendantBackgroundColor: Color {
        let rgb = resolvedDescendantRGB()
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private var activeBackgroundColor: Color {
        let rgb = resolvedActiveRGB()
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private var usesFocusFadeTint: Bool {
        !isArchived && !isMultiSelected && !isCandidateVisualCard
    }

    private var relatedTintOpacity: Double {
        guard usesFocusFadeTint else { return 0 }
        return (!isActive && isAncestor) ? 1 : 0
    }

    private var descendantTintOpacity: Double {
        guard usesFocusFadeTint else { return 0 }
        return (!isActive && isDescendant) ? 1 : 0
    }

    private var activeTintOpacity: Double {
        guard usesFocusFadeTint else { return 0 }
        return isActive ? 1 : 0
    }

    private var cardBorderColor: Color {
        if usesDarkPalette {
            return Color.white.opacity(0.12)
        }
        return Color.black.opacity(0.10)
    }

    private let horizontalInsertZoneHeight: CGFloat = 27
    private let horizontalInsertZoneWidth: CGFloat = 60
    private let trailingInsertZoneWidth: CGFloat = 30

    private func insertZoneHighlightFill(for edge: InlineInsertZoneEdge) -> AnyShapeStyle {
        let strong = usesDarkPalette ? Color.white.opacity(0.32) : Color.black.opacity(0.24)
        let soft = usesDarkPalette ? Color.white.opacity(0.16) : Color.black.opacity(0.10)

        switch edge {
        case .top:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [strong, soft, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .bottom:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [strong, soft, .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
        case .trailing:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [strong, soft, .clear],
                    startPoint: .trailing,
                    endPoint: .leading
                )
            )
        }
    }

    private var mainEditingTextMeasureWidth: CGFloat {
        max(1, preferredTextMeasureWidth)
    }

    private var resolvedMainEditingBodyHeight: CGFloat {
        if usesExternalMainEditor {
            if let externalEditorLiveBodyHeight, externalEditorLiveBodyHeight > 1 {
                return externalEditorLiveBodyHeight
            }
            return measureMainEditorBodyHeight(text: card.content, width: mainEditingTextMeasureWidth)
        }
        if mainEditingMeasuredBodyHeight > 1 {
            return mainEditingMeasuredBodyHeight
        }
        return measureMainEditorBodyHeight(text: card.content, width: mainEditingTextMeasureWidth)
    }

    private var mainEditorTextBinding: Binding<String> {
        Binding(
            get: { card.content },
            set: { newValue in
                let oldValue = card.content
                guard oldValue != newValue else { return }
                card.content = newValue
                onContentChange?(oldValue, newValue)
                scheduleMainEditingMeasuredBodyHeightRefresh()
            }
        )
    }

    private func liveMainResponderBodyHeight() -> CGFloat? {
        guard isEditing else { return nil }
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return nil }
        guard textView.string == card.content else { return nil }
        return sharedLiveTextViewBodyHeight(textView)
    }

    private func measureMainEditorBodyHeight(text: String, width: CGFloat) -> CGFloat {
        sharedMeasuredTextBodyHeight(
            text: text,
            fontSize: CGFloat(fontSize),
            lineSpacing: mainCardLineSpacing,
            width: width,
            lineFragmentPadding: mainEditorLineFragmentPadding,
            safetyInset: 0
        )
    }

    private func refreshMainEditingMeasuredBodyHeight() {
        let liveBodyHeight = liveMainResponderBodyHeight()
        let measured = liveBodyHeight
            ?? measureMainEditorBodyHeight(text: card.content, width: mainEditingTextMeasureWidth)
        mainEditingMeasureLastAt = Date()
        let previous = mainEditingMeasuredBodyHeight
        if abs(previous - measured) > mainEditingMeasureUpdateThreshold {
            mainEditingMeasuredBodyHeight = measured
            mainWorkspacePhase0Log(
                "inline-editor-row-height",
                "card=\(mainWorkspacePhase0CardID(card.id)) source=\(liveBodyHeight != nil ? "liveResponder" : "fallbackMeasure") " +
                "body=\(measured) row=\(measured + (mainEditorVerticalPadding * 2)) previous=\(previous) " +
                "isEditing=\(isEditing) responder=\(mainWorkspacePhase0ResponderSummary(expectedText: card.content))"
            )
        }
    }

    private func updateMainEditingMeasuredBodyHeight(_ measured: CGFloat?, source: String) {
        guard let measured, measured > 0 else { return }
        mainEditingMeasureLastAt = Date()
        let previous = mainEditingMeasuredBodyHeight
        if abs(previous - measured) > mainEditingMeasureUpdateThreshold {
            mainEditingMeasuredBodyHeight = measured
            mainWorkspacePhase0Log(
                "inline-editor-row-height",
                "card=\(mainWorkspacePhase0CardID(card.id)) source=\(source) " +
                "body=\(measured) row=\(measured + (mainEditorVerticalPadding * 2)) previous=\(previous) " +
                "isEditing=\(isEditing) responder=\(mainWorkspacePhase0ResponderSummary(expectedText: card.content))"
            )
        }
    }

    private func scheduleMainEditingMeasuredBodyHeightRefresh(immediate: Bool = false) {
        if immediate {
            mainEditingMeasureWorkItem?.cancel()
            mainEditingMeasureWorkItem = nil
            refreshMainEditingMeasuredBodyHeight()
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(mainEditingMeasureLastAt)
        let delay = max(0, mainEditingMeasureMinInterval - elapsed)
        guard delay > 0.001 else {
            refreshMainEditingMeasuredBodyHeight()
            return
        }

        mainEditingMeasureWorkItem?.cancel()
        let work = DispatchWorkItem {
            mainEditingMeasureWorkItem = nil
            refreshMainEditingMeasuredBodyHeight()
        }
        mainEditingMeasureWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private var shouldReportMainEditorSlotFrame: Bool {
        mainEditorSlotCoordinateSpaceName != nil && (isActive || isEditing || usesExternalMainEditor)
    }

    @ViewBuilder
    private var cardEditorSlotFrameReporter: some View {
        if shouldReportMainEditorSlotFrame,
           let coordinateSpaceName = mainEditorSlotCoordinateSpaceName {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: MainColumnEditorSlotPreferenceKey.self,
                    value: [
                        card.id: geometry.frame(in: .named(coordinateSpaceName))
                    ]
                )
            }
        }
    }

    @ViewBuilder
    private var cardEditorSlotContent: some View {
        ZStack(alignment: .topLeading) {
            if !isEditing && !usesExternalMainEditor {
                Text(card.content.isEmpty ? "내용 없음" : card.content)
                    .font(.custom("SansMonoCJKFinalDraft", size: fontSize))
                    .lineSpacing(mainCardLineSpacing)
                    .foregroundStyle(card.content.isEmpty ? (appearance == "light" ? .black.opacity(0.4) : .white.opacity(0.4)) : (appearance == "light" ? .black : .white))
                    .padding(mainCardContentPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !isEditing && usesExternalMainEditor {
                Color.clear
                    .frame(
                        width: MainCanvasLayoutMetrics.textWidth,
                        height: resolvedMainEditingBodyHeight,
                        alignment: .topLeading
                    )
                    .padding(.horizontal, mainEditorHorizontalPadding)
                    .padding(.vertical, mainEditorVerticalPadding)
            }

            if isEditing {
                if usesExternalMainEditor {
                    Color.clear
                        .frame(
                            width: MainCanvasLayoutMetrics.textWidth,
                            height: resolvedMainEditingBodyHeight,
                            alignment: .topLeading
                        )
                        .padding(.horizontal, mainEditorHorizontalPadding)
                        .padding(.vertical, mainEditorVerticalPadding)
                        .onAppear {
                            mainWorkspacePhase0Log(
                                "inline-editor-placeholder-appear",
                                "card=\(mainWorkspacePhase0CardID(card.id)) active=\(isActive) selected=\(isSelected) " +
                                "body=\(resolvedMainEditingBodyHeight)"
                            )
                        }
                        .onDisappear {
                            mainWorkspacePhase0Log(
                                "inline-editor-placeholder-disappear",
                                "card=\(mainWorkspacePhase0CardID(card.id)) body=\(resolvedMainEditingBodyHeight)"
                            )
                        }
                } else {
                    TextEditor(text: mainEditorTextBinding)
                        .font(.custom("SansMonoCJKFinalDraft", size: fontSize))
                        .lineSpacing(mainCardLineSpacing)
                        .scrollContentBackground(.hidden)
                        .scrollDisabled(true)
                        .scrollIndicators(.never)
                        .frame(
                            width: MainCanvasLayoutMetrics.textWidth,
                            height: resolvedMainEditingBodyHeight,
                            alignment: .topLeading
                        )
                        .padding(.horizontal, mainEditorHorizontalPadding)
                        .padding(.vertical, mainEditorVerticalPadding)
                        .foregroundStyle(appearance == "light" ? .black : .white)
                        .focused($editorFocus)
                        .onAppear {
                            onMainEditorMount?(card.id)
                            mainWorkspacePhase0Log(
                                "inline-editor-appear",
                                "card=\(mainWorkspacePhase0CardID(card.id)) active=\(isActive) selected=\(isSelected) " +
                                "measuredBody=\(mainEditingMeasuredBodyHeight) responder=\(mainWorkspacePhase0ResponderSummary(expectedText: card.content))"
                            )
                            scheduleMainEditingMeasuredBodyHeightRefresh(immediate: true)
                            DispatchQueue.main.async {
                                let alreadyFocusedHere: Bool = {
                                    guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
                                    return textView.string == card.content
                                }()
                                if !alreadyFocusedHere {
                                    editorFocus = true
                                }
                                mainWorkspacePhase0Log(
                                    "inline-editor-focus-request",
                                    "card=\(mainWorkspacePhase0CardID(card.id)) alreadyFocused=\(alreadyFocusedHere) " +
                                    "editorFocus=\(editorFocus) responder=\(mainWorkspacePhase0ResponderSummary(expectedText: card.content))"
                                )
                                scheduleMainEditingMeasuredBodyHeightRefresh(immediate: true)
                            }
                        }
                        .onDisappear {
                            onMainEditorUnmount?(card.id)
                            mainWorkspacePhase0Log(
                                "inline-editor-disappear",
                                "card=\(mainWorkspacePhase0CardID(card.id)) measuredBody=\(mainEditingMeasuredBodyHeight) " +
                                "responder=\(mainWorkspacePhase0ResponderSummary(expectedText: card.content))"
                            )
                            mainEditingMeasureWorkItem?.cancel()
                            mainEditingMeasureWorkItem = nil
                        }
                        .onChange(of: editorFocus) { _, newValue in
                            onMainEditorFocusStateChange?(card.id, newValue)
                            mainWorkspacePhase0Log(
                                "inline-editor-focus-state",
                                "card=\(mainWorkspacePhase0CardID(card.id)) focused=\(newValue) " +
                                "responder=\(mainWorkspacePhase0ResponderSummary(expectedText: card.content))"
                            )
                        }
                        .onChange(of: fontSize) { _, _ in
                            scheduleMainEditingMeasuredBodyHeightRefresh(immediate: true)
                        }
                        .onChange(of: mainCardLineSpacing) { _, _ in
                            scheduleMainEditingMeasuredBodyHeightRefresh(immediate: true)
                        }
                }
            }
        }
        .background(cardEditorSlotFrameReporter)
    }

    @ViewBuilder
    private var cardContextMenuContent: some View {
        if let onDisconnectLinkedCard {
            Button("연결 끊기", role: .destructive) { onDisconnectLinkedCard() }
            Divider()
        }
        if showsEmptyCardBulkDeleteMenuOnly {
            if let onOpenIndexBoard {
                Button("인덱스 카드 뷰로 보기") { onOpenIndexBoard() }
                Divider()
            }
            if hasAIMenuActions {
                Menu("AI") {
                    Button("구체화") { onAIElaborate?() }
                        .disabled(onAIElaborate == nil || !aiPlotActionsEnabled || isAIBusy)
                    Button("다음 장면") { onAINextScene?() }
                        .disabled(onAINextScene == nil || !aiPlotActionsEnabled || isAIBusy)
                    Button("대안") { onAIAlternative?() }
                        .disabled(onAIAlternative == nil || !aiPlotActionsEnabled || isAIBusy)
                    Divider()
                    Button("선택 카드 요약") { onAISummarizeCurrent?() }
                        .disabled(onAISummarizeCurrent == nil || isAIBusy)
                    Button("자식 카드 요약") { onSummarizeChildren?() }
                        .disabled(onSummarizeChildren == nil || isAIBusy)
                }
                if onBulkDeleteEmptyCards != nil {
                    Divider()
                }
            }
            if let onTranscriptionMode {
                Button("전사 모드") { onTranscriptionMode() }
                    .disabled(isTranscriptionBusy || isAIBusy)
                if onBulkDeleteEmptyCards != nil {
                    Divider()
                }
            }
            if let onBulkDeleteEmptyCards {
                Button("내용 없음 카드 전체 삭제", role: .destructive) { onBulkDeleteEmptyCards() }
            }
        } else {
            if let onOpenIndexBoard {
                Button("인덱스 카드 뷰로 보기") { onOpenIndexBoard() }
                Divider()
            }
            if let onCloneCard {
                Button("클론 카드") { onCloneCard() }
                Divider()
            }
            if let onNavigateToClonePeer, !clonePeerDestinations.isEmpty {
                Menu("다른 클론으로 이동") {
                    ForEach(clonePeerDestinations) { destination in
                        Button(destination.title) { onNavigateToClonePeer(destination.id) }
                    }
                }
                Divider()
            }
            if let onReferenceCard {
                Button("레퍼런스 카드로") { onReferenceCard() }
                Divider()
            }
            if let onCreateUpperCardFromSelection {
                Button("새 상위 카드 만들기") { onCreateUpperCardFromSelection() }
                Divider()
            }
            if hasAIMenuActions {
                Menu("AI") {
                    Button("구체화") { onAIElaborate?() }
                        .disabled(onAIElaborate == nil || !aiPlotActionsEnabled || isAIBusy)
                    Button("다음 장면") { onAINextScene?() }
                        .disabled(onAINextScene == nil || !aiPlotActionsEnabled || isAIBusy)
                    Button("대안") { onAIAlternative?() }
                        .disabled(onAIAlternative == nil || !aiPlotActionsEnabled || isAIBusy)
                    Divider()
                    Button("선택 카드 요약") { onAISummarizeCurrent?() }
                        .disabled(onAISummarizeCurrent == nil || isAIBusy)
                    Button("자식 카드 요약") { onSummarizeChildren?() }
                        .disabled(onSummarizeChildren == nil || isAIBusy)
                }
                Divider()
            }
            if let onDelete {
                Button("삭제", role: .destructive) { onDelete() }
            }
            if onDelete != nil {
                Divider()
            }
            if let onColorChange {
                Menu("카드 색") {
                    Button("기본") { onColorChange(nil) }
                    Divider()
                    Button("연보라") { onColorChange("E7D5FF") }
                    Button("하늘") { onColorChange("CFE8FF") }
                    Button("민트") { onColorChange("CFF2E8") }
                    Button("살구") { onColorChange("FFE1CC") }
                    Button("연노랑") { onColorChange("FFF3C4") }
                }
            }
            if let onTranscriptionMode {
                Divider()
                Button("전사 모드") { onTranscriptionMode() }
                    .disabled(isTranscriptionBusy || isAIBusy)
            }
            if let onHardDelete {
                Divider()
                Button("완전 삭제 (모든 곳)", role: .destructive) { onHardDelete() }
            }
        }
    }

    @ViewBuilder
    private var cardShellContent: some View {
        ZStack(alignment: .topLeading) {
            baseBackgroundColor

            if usesFocusFadeTint {
                relatedBackgroundColor
                    .opacity(relatedTintOpacity)

                descendantBackgroundColor
                    .opacity(descendantTintOpacity)

                activeBackgroundColor
                    .opacity(activeTintOpacity)
            }

            cardEditorSlotContent
        }
    }

    private func cardChromeApplied<Content: View>(to content: Content) -> some View {
        content
        .overlay {
            if let onDropOnto {
                cardBodyDropZone(onDrop: onDropOnto)
            }
        }
        .overlay(alignment: .trailing) {
            ZStack(alignment: .trailing) {
                if shouldShowInlineInsertControls, let onAddChildCard {
                    inlineInsertZone(
                        isHovered: $isTrailingInsertZoneHovered,
                        isDropTargeted: $isTrailingInsertZoneDropTargeted,
                        edge: .trailing,
                        axis: .vertical,
                        action: onAddChildCard,
                        onDrop: nil
                    )
                }
                if shouldShowChildRightEdge {
                    Rectangle()
                        .fill(childRightEdgeColor)
                        .frame(width: 4)
                        .allowsHitTesting(false)
                }
            }
        }
        .overlay(alignment: .top) {
            if shouldShowInlineInsertControls, let onInsertSiblingAbove {
                inlineInsertZone(
                    isHovered: $isTopInsertZoneHovered,
                    isDropTargeted: $isTopInsertZoneDropTargeted,
                    edge: .top,
                    axis: .horizontal,
                    action: onInsertSiblingAbove,
                    onDrop: onDropBefore
                )
            }
        }
        .overlay(alignment: .bottom) {
            if shouldShowInlineInsertControls, let onInsertSiblingBelow {
                inlineInsertZone(
                    isHovered: $isBottomInsertZoneHovered,
                    isDropTargeted: $isBottomInsertZoneDropTargeted,
                    edge: .bottom,
                    axis: .horizontal,
                    action: onInsertSiblingBelow,
                    onDrop: onDropAfter
                )
            }
        }
        .overlay {
            Rectangle()
                .stroke(cardBorderColor, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                if isCandidateVisualCard {
                    VStack {
                        HStack(spacing: 6) {
                            Spacer()
                            Text("AI 후보")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(appearance == "light" ? Color.black.opacity(0.12) : Color.white.opacity(0.20))
                                .clipShape(Capsule())
                            if let onApplyAICandidate {
                                Button("선택") {
                                    onApplyAICandidate()
                                }
                                .font(.system(size: 9, weight: .semibold))
                                .buttonStyle(.plain)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(appearance == "light" ? Color.accentColor.opacity(0.22) : Color.accentColor.opacity(0.32))
                                .clipShape(Capsule())
                                .disabled(isAIBusy)
                            }
                        }
                        Spacer()
                    }
                    .padding(8)
                }
                HStack(spacing: 3) {
                    if hasLinkedCards {
                        Rectangle()
                            .fill(appearance == "light" ? Color.black.opacity(0.48) : Color.white.opacity(0.85))
                            .frame(width: 8, height: 8)
                            .allowsHitTesting(false)
                    }
                    if isLinkedCard {
                        Path { path in
                            // Right-angle isosceles triangle with the right angle at top-right.
                            path.move(to: CGPoint(x: 0, y: 0))
                            path.addLine(to: CGPoint(x: 8, y: 0))
                            path.addLine(to: CGPoint(x: 8, y: 8))
                            path.closeSubpath()
                        }
                        .fill(appearance == "light" ? Color.black.opacity(0.48) : Color.white.opacity(0.85))
                        .frame(width: 8, height: 8)
                        .allowsHitTesting(false)
                    }
                }
                if isSummarizingChildren {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                        .background(appearance == "light" ? Color.white.opacity(0.92) : Color.black.opacity(0.42))
                        .clipShape(Capsule())
                        .padding(.top, 6)
                        .padding(.trailing, 8)
                        .allowsHitTesting(false)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if isCloneLinked {
                Rectangle()
                    .fill(appearance == "light" ? Color.black.opacity(0.48) : Color.white.opacity(0.85))
                    .frame(width: 8, height: 8)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: isEditing) { _, newValue in
            mainWorkspacePhase0Log(
                "card-editing-flag-change",
                "card=\(mainWorkspacePhase0CardID(card.id)) isEditing=\(newValue) active=\(isActive) " +
                "measuredBody=\(mainEditingMeasuredBodyHeight) responder=\(mainWorkspacePhase0ResponderSummary(expectedText: card.content))"
            )
            if newValue {
                scheduleMainEditingMeasuredBodyHeightRefresh(immediate: true)
            } else {
                mainEditingMeasureWorkItem?.cancel()
                mainEditingMeasureWorkItem = nil
            }
        }
        .onDisappear {
            mainEditingMeasureWorkItem?.cancel()
            mainEditingMeasureWorkItem = nil
        }
    }

    @ViewBuilder
    private var cardSurface: some View {
        cardChromeApplied(to: cardShellContent)
    }

    var body: some View {
        Group {
            if isEditing {
                cardSurface
            } else {
                cardSurface
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                                let isPlainClick =
                                    !flags.contains(.command) &&
                                    !flags.contains(.shift) &&
                                    !flags.contains(.option) &&
                                    !flags.contains(.control)
                                let shouldRouteClickToCaret =
                                    isPlainClick &&
                                    isActive &&
                                    isSelected &&
                                    !isMultiSelected &&
                                    onSelectAtLocation != nil
                                if shouldRouteClickToCaret, let onSelectAtLocation {
                                    onSelectAtLocation(value.location)
                                } else {
                                    onSelect()
                                }
                            }
                    )
                    .simultaneousGesture(TapGesture(count: 2).onEnded { onDoubleClick() })
            }
        }
        .contextMenu {
            cardContextMenuContent
        }
    }

    private func resolvedBaseRGB() -> (r: Double, g: Double, b: Double) {
        let fallbackLight: (Double, Double, Double) = (1.0, 1.0, 1.0)
        let fallbackDark: (Double, Double, Double) = (0.10, 0.13, 0.16)
        if let custom = card.colorHex, let customRGB = rgbFromHex(custom) {
            if forceCustomColorVisibility || card.isAICandidate {
                if !usesDarkPalette { return customRGB }
                return mix(base: customRGB, overlay: (0, 0, 0), amount: 0.18)
            }
            if !usesDarkPalette { return customRGB }
            return mix(base: customRGB, overlay: (0, 0, 0), amount: 0.65)
        }
        let hex = usesDarkPalette ? darkCardBaseColorHex : cardBaseColorHex
        guard let rgb = rgbFromHex(hex) else {
            return usesDarkPalette ? fallbackDark : fallbackLight
        }
        return rgb
    }

    private func rgbFromHex(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        guard let rgb = parseHexRGB(hex) else { return nil }
        return (r: rgb.0, g: rgb.1, b: rgb.2)
    }

    private func mix(base: (r: Double, g: Double, b: Double), overlay: (r: Double, g: Double, b: Double), amount: Double) -> (r: Double, g: Double, b: Double) {
        let r = base.r * (1.0 - amount) + overlay.r * amount
        let g = base.g * (1.0 - amount) + overlay.g * amount
        let b = base.b * (1.0 - amount) + overlay.b * amount
        return (r, g, b)
    }

    private func resolvedNamedSnapshotNoteRGB() -> (r: Double, g: Double, b: Double) {
        if appearance == "light" {
            return (0.83, 0.94, 0.84)
        }
        return (0.17, 0.30, 0.19)
    }

    @ViewBuilder
    private func inlineInsertZone(
        isHovered: Binding<Bool>,
        isDropTargeted: Binding<Bool>,
        edge: InlineInsertZoneEdge,
        axis: Axis,
        action: @escaping () -> Void,
        onDrop: (([NSItemProvider], Bool) -> Void)?
    ) -> some View {
        if let onDrop {
            inlineInsertZoneContent(
                isHovered: isHovered,
                isDropTargeted: isDropTargeted,
                edge: edge,
                axis: axis,
                action: action
            )
            .onDrop(
                of: [.text],
                delegate: CardActionZoneDropDelegate(
                    isTargeted: isDropTargeted,
                    performAction: onDrop
                )
            )
        } else {
            inlineInsertZoneContent(
                isHovered: isHovered,
                isDropTargeted: isDropTargeted,
                edge: edge,
                axis: axis,
                action: action
            )
        }
    }

    private func inlineInsertZoneContent(
        isHovered: Binding<Bool>,
        isDropTargeted: Binding<Bool>,
        edge: InlineInsertZoneEdge,
        axis: Axis,
        action: @escaping () -> Void
    ) -> some View {
        let isHighlighted = isHovered.wrappedValue || isDropTargeted.wrappedValue
        return ZStack {
            Rectangle()
                .fill(isHighlighted ? insertZoneHighlightFill(for: edge) : AnyShapeStyle(Color.clear))

            if isHighlighted {
                Text("+")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(insertIndicatorColor)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered.wrappedValue = hovering
            }
        }
        .onTapGesture {
            action()
        }
        .frame(
            width: axis == .vertical ? trailingInsertZoneWidth : horizontalInsertZoneWidth,
            height: axis == .horizontal ? horizontalInsertZoneHeight : nil
        )
        .frame(
            maxHeight: axis == .vertical ? .infinity : nil
        )
    }

    @ViewBuilder
    private func cardBodyDropZone(onDrop: @escaping ([NSItemProvider], Bool) -> Void) -> some View {
        GeometryReader { geometry in
            let bodyWidth = max(0, geometry.size.width - bodyDropTrailingInset)
            let bodyHeight = max(0, geometry.size.height - (horizontalInsertZoneHeight * 2))

            Rectangle()
                .fill(isBodyDropTargeted ? insertZoneHighlightColor : .clear)
                .frame(width: bodyWidth, height: bodyHeight, alignment: .topLeading)
                .offset(x: 0, y: horizontalInsertZoneHeight)
                .contentShape(Rectangle())
                .onDrop(
                    of: [.text],
                    delegate: CardActionZoneDropDelegate(
                        isTargeted: $isBodyDropTargeted,
                        performAction: onDrop
                    )
                )
        }
    }

    private func resolvedActiveRGB() -> (r: Double, g: Double, b: Double) {
        let fallbackLight: (Double, Double, Double) = (0.75, 0.84, 1.0)
        let fallbackDark: (Double, Double, Double) = (0.16, 0.23, 0.31)
        let hex = usesDarkPalette ? darkCardActiveColorHex : cardActiveColorHex
        guard let rgb = rgbFromHex(hex) else {
            return usesDarkPalette ? fallbackDark : fallbackLight
        }
        return rgb
    }

    private func resolvedRelatedRGB() -> (r: Double, g: Double, b: Double) {
        let fallbackLight: (Double, Double, Double) = (0.87, 0.92, 1.0)
        let fallbackDark: (Double, Double, Double) = (0.14, 0.18, 0.25)
        let hex = usesDarkPalette ? darkCardRelatedColorHex : cardRelatedColorHex
        guard let rgb = rgbFromHex(hex) else {
            return usesDarkPalette ? fallbackDark : fallbackLight
        }
        return rgb
    }

    private func resolvedDescendantRGB() -> (r: Double, g: Double, b: Double) {
        mix(base: resolvedActiveRGB(), overlay: (0, 0, 0), amount: 0.10)
    }
}

// MARK: - 드래그 앤 드롭 델리게이트 (카드 영역용)

private func isTrailingSiblingBlockDragActive() -> Bool {
    let tracker = MainCardDragSessionTracker.shared
    if tracker.isDragging {
        tracker.refreshCommandState()
        return tracker.isCommandPressed
    }
    return NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
}

private struct CardActionZoneDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let performAction: ([NSItemProvider], Bool) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        MainCardDragSessionTracker.shared.refreshCommandState()
        return DropProposal(operation: isTrailingSiblingBlockDragActive() ? .copy : .move)
    }

    func dropEntered(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.15)) { isTargeted = true }
    }

    func dropExited(info: DropInfo) {
        if isTargeted {
            withAnimation(.easeInOut(duration: 0.15)) { isTargeted = false }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.text])
        guard !providers.isEmpty else { return false }
        performAction(providers, isTrailingSiblingBlockDragActive())
        isTargeted = false
        MainCardDragSessionTracker.shared.end()
        return true
    }
}
