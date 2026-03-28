import SwiftUI
import AppKit

extension IndexBoardSurfaceAppKitDocumentView {
    func textDidEndEditing(_ notification: Notification) {
        guard !isEndingInlineEditing else { return }
        endInlineEditing(commit: true)
    }

    func textDidChange(_ notification: Notification) {
        revealInlineEditorSelection()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        revealInlineEditorSelection()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) ||
            commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) ||
            commandSelector == #selector(NSResponder.insertLineBreak(_:)) {
            let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            if flags.contains(.shift) {
                textView.insertText("\n", replacementRange: textView.selectedRange())
                revealInlineEditorSelection()
            } else {
                endInlineEditing(commit: true)
                window?.makeFirstResponder(self)
            }
            return true
        }
        return false
    }

    func resolvedInlineEditableCardID() -> UUID? {
        guard configuration.selectedCardIDs.count == 1,
              let cardID = configuration.selectedCardIDs.first,
              configuration.activeCardID == cardID,
              configuration.cardsByID[cardID] != nil else {
            return nil
        }
        return cardID
    }

    func ensureInlineEditor() -> NSTextView {
        if let textView = inlineEditorTextView {
            return textView
        }

        let scrollView = NSScrollView()
        scrollView.wantsLayer = true
        scrollView.drawsBackground = true
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = IndexBoardSurfaceAppKitInlineTextView()
        textView.delegate = self
        textView.onPostInteraction = { [weak self] in
            self?.revealInlineEditorSelection()
        }
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.usesFindBar = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: IndexBoardMetrics.cardInnerPadding - 2, height: IndexBoardMetrics.cardInnerPadding - 2)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]

        if let textContainer = textView.textContainer {
            textContainer.lineFragmentPadding = 0
            textContainer.lineBreakMode = .byWordWrapping
            textContainer.maximumNumberOfLines = 0
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false
            textContainer.containerSize = CGSize(width: 1, height: CGFloat.greatestFiniteMagnitude)
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        textView.font = NSFont(name: "SansMonoCJKFinalDraft", size: 13) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = indexBoardThemePrimaryTextColor(theme: configuration.theme)
        textView.insertionPointColor = indexBoardThemePrimaryTextColor(theme: configuration.theme)
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = [
            .font: textView.font as Any,
            .foregroundColor: textView.textColor as Any,
            .paragraphStyle: paragraphStyle
        ]

        scrollView.documentView = textView
        scrollView.isHidden = true
        addSubview(scrollView)
        inlineEditorScrollView = scrollView
        inlineEditorTextView = textView
        return textView
    }

    func updateInlineEditorAppearance(for card: SceneCard) {
        guard let scrollView = inlineEditorScrollView,
              let textView = inlineEditorTextView else { return }

        let isSelected = configuration.selectedCardIDs.contains(card.id)
        let isActive = configuration.activeCardID == card.id
        let backgroundColor = indexBoardThemeColor(
            theme: configuration.theme,
            customHex: card.colorHex,
            isSelected: isSelected,
            isActive: isActive
        )
        let borderColor = indexBoardThemeBorderColor(
            theme: configuration.theme,
            isSelected: isSelected,
            isActive: isActive
        )
        let primaryTextColor = indexBoardThemePrimaryTextColor(theme: configuration.theme)

        scrollView.backgroundColor = backgroundColor
        scrollView.layer?.backgroundColor = backgroundColor.cgColor
        scrollView.layer?.cornerRadius = IndexBoardMetrics.cardCornerRadius
        scrollView.layer?.borderWidth = 1
        scrollView.layer?.borderColor = borderColor.cgColor
        scrollView.layer?.masksToBounds = true
        textView.textColor = primaryTextColor
        textView.insertionPointColor = primaryTextColor
        textView.typingAttributes[.foregroundColor] = primaryTextColor
    }

    func revealInlineEditorSelection() {
        guard let textView = inlineEditorTextView else { return }
        let selectedRange = textView.selectedRange()
        guard selectedRange.location != NSNotFound else { return }
        textView.scrollRangeToVisible(selectedRange)
    }

    func beginInlineEditing(cardID: UUID, seedEvent: NSEvent? = nil) {
        guard configuration.allowsInlineEditing,
              let card = configuration.cardsByID[cardID],
              let frame = cardFrameByID[cardID] else { return }

        if inlineEditingCardID != cardID {
            endInlineEditing(commit: true)
        }

        let textView = ensureInlineEditor()
        inlineEditingCardID = cardID
        inlineEditingOriginalContent = card.content
        inlineEditorScrollView?.frame = frame
        inlineEditorScrollView?.isHidden = false
        inlineEditorScrollView?.alphaValue = 1
        configuration.onInlineEditingChange(true)
        updateInlineEditorAppearance(for: card)

        if textView.string != card.content {
            textView.string = card.content
        }
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        window?.makeFirstResponder(textView)
        revealInlineEditorSelection()

        if let seedEvent {
            textView.keyDown(with: seedEvent)
        }
    }

    func endInlineEditing(commit: Bool) {
        guard let cardID = inlineEditingCardID else { return }
        isEndingInlineEditing = true
        defer {
            isEndingInlineEditing = false
        }

        let originalContent = inlineEditingOriginalContent
        let committedText = inlineEditorTextView?.string ?? originalContent
        inlineEditingCardID = nil
        inlineEditingOriginalContent = ""
        inlineEditorScrollView?.isHidden = true
        configuration.onInlineEditingChange(false)

        if commit, committedText != originalContent {
            configuration.onInlineCardEditCommit(cardID, committedText)
        }
    }

    func layoutInlineEditorIfNeeded() {
        guard let inlineEditingCardID,
              let frame = cardFrameByID[inlineEditingCardID],
              let card = configuration.cardsByID[inlineEditingCardID] else {
            inlineEditorScrollView?.isHidden = true
            return
        }
        inlineEditorScrollView?.frame = frame
        inlineEditorScrollView?.isHidden = false
        updateInlineEditorAppearance(for: card)
    }
}
