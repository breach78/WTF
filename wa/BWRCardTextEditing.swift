import SwiftUI
import AppKit

nonisolated enum BWRTextBoundaryNavigationDirection: String, Equatable, Sendable {
    case previousCard
    case nextCard
}

@MainActor
final class BWRCommandTextView: NSTextView {
    let editorUndoManager = UndoManager()
    var keyDownInterceptor: ((NSEvent, BWRCommandTextView) -> Bool)?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        editorUndoManager.groupsByEvent = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        editorUndoManager.groupsByEvent = true
    }

    override var undoManager: UndoManager? {
        editorUndoManager
    }

    override func keyDown(with event: NSEvent) {
        if keyDownInterceptor?(event, self) == true {
            return
        }
        super.keyDown(with: event)
    }

    func markUndoBoundary() {
        editorUndoManager.beginUndoGrouping()
        editorUndoManager.endUndoGrouping()
    }
}

nonisolated struct BWRInlineEditorState: Identifiable, Equatable, Sendable {
    var cardID: UUID
    var layerID: UUID
    var text: String
    var selectedRange: NSRange

    var id: String {
        "\(cardID.uuidString)|\(layerID.uuidString)"
    }
}

@MainActor
struct BWRCardMarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange

    var fontSize: CGFloat = 14
    var textContainerInset: NSSize = NSSize(width: 12, height: 12)
    var autoFocus: Bool = false
    var focusRequestToken: Int = 0
    var centersSelectionWhenFocused: Bool = false
    var onSplit: ((String, NSRange) -> Void)? = nil
    var onEscape: (() -> Void)? = nil
    var onFindCommand: (() -> Bool)? = nil
    var onUndoCommand: (() -> Bool)? = nil
    var onRedoCommand: (() -> Bool)? = nil
    var onBoundaryNavigation: ((BWRTextBoundaryNavigationDirection, String, NSRange) -> Bool)? = nil
    var onTextDidChange: ((String, String, NSRange) -> Void)? = nil
    var onSelectionDidChange: ((NSTextView, NSRange) -> Void)? = nil
    var onTextViewMounted: ((BWRCommandTextView) -> Void)? = nil

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BWRCardMarkdownEditor
        var suppressPropagation = false
        var didRequestInitialFocus = false
        var lastFocusRequestToken: Int = -1

        init(parent: BWRCardMarkdownEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !suppressPropagation else { return }
            let previousText = parent.text
            parent.text = textView.string
            parent.selectedRange = textView.selectedRange()
            parent.onTextDidChange?(previousText, textView.string, textView.selectedRange())
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.selectedRange = textView.selectedRange()
            parent.onSelectionDidChange?(textView, textView.selectedRange())
            if parent.centersSelectionWhenFocused {
                Self.centerSelection(in: textView)
            }
        }

        func textView(
            _ textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape?()
                return parent.onEscape != nil
            }

            guard commandSelector == #selector(NSResponder.insertNewline(_:)) ||
                    commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) ||
                    commandSelector == #selector(NSResponder.insertLineBreak(_:)) else {
                return false
            }

            let event = BWRTextKeyEvent(
                keyCode: NSApp.currentEvent?.keyCode ?? 36,
                modifiers: BWRTextKeyModifiers(
                    shift: NSApp.currentEvent?.modifierFlags.contains(.shift) == true,
                    command: NSApp.currentEvent?.modifierFlags.contains(.command) == true,
                    option: NSApp.currentEvent?.modifierFlags.contains(.option) == true,
                    control: NSApp.currentEvent?.modifierFlags.contains(.control) == true
                ),
                hasMarkedText: textView.hasMarkedText()
            )
            let action = BWRTextKeyCommandRouter.resolve(event)

            switch action {
            case .splitCard:
                parent.onSplit?(textView.string, textView.selectedRange())
                return parent.onSplit != nil
            case .insertNewline:
                textView.insertText("\n", replacementRange: textView.selectedRange())
                return true
            case .passToSystem:
                return false
            }
        }

        static func centerSelection(in textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  let scrollView = textView.enclosingScrollView else {
                return
            }

            let textLength = (textView.string as NSString).length
            let location = min(max(0, textView.selectedRange().location), textLength)
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: location, length: 0),
                actualCharacterRange: nil
            )
            var caretRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            caretRect.origin.x += textView.textContainerInset.width
            caretRect.origin.y += textView.textContainerInset.height

            let clipView = scrollView.contentView
            var targetOrigin = clipView.bounds.origin
            targetOrigin.y = max(0, caretRect.midY - (clipView.bounds.height * 0.5))
            clipView.setBoundsOrigin(targetOrigin)
            scrollView.reflectScrolledClipView(clipView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = BWRCommandTextView(frame: .zero, textContainer: nil)
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.usesFindBar = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = NSColor.clear
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.textContainerInset = textContainerInset
        textView.minSize = NSSize.zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.smartInsertDeleteEnabled = false

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false
            textContainer.lineFragmentPadding = 0
            textContainer.lineBreakMode = NSLineBreakMode.byWordWrapping
        }

        textView.keyDownInterceptor = { event, editor in
            handleKeyDown(event, textView: editor)
        }

        scrollView.documentView = textView
        updateTextView(textView, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.delegate !== context.coordinator {
            textView.delegate = context.coordinator
        }
        textView.font = .systemFont(ofSize: fontSize)
        textView.textContainerInset = textContainerInset
        updateTextView(textView, coordinator: context.coordinator)
    }

    private func updateTextView(_ textView: NSTextView, coordinator: Coordinator) {
        coordinator.parent = self
        if textView.string != text {
            coordinator.suppressPropagation = true
            textView.string = text
            coordinator.suppressPropagation = false
        }

        let clamped = clampedRange(selectedRange, for: textView.string)
        if textView.selectedRange() != clamped {
            textView.setSelectedRange(clamped)
        }

        if let commandTextView = textView as? BWRCommandTextView {
            commandTextView.keyDownInterceptor = { event, editor in
                handleKeyDown(event, textView: editor)
            }
            onTextViewMounted?(commandTextView)
        }

        guard autoFocus,
              !coordinator.didRequestInitialFocus,
              textView.window != nil else {
            if focusRequestToken > 0,
               focusRequestToken > coordinator.lastFocusRequestToken,
               textView.window != nil {
                coordinator.lastFocusRequestToken = focusRequestToken
                DispatchQueue.main.async {
                    textView.window?.makeFirstResponder(textView)
                    if centersSelectionWhenFocused {
                        Coordinator.centerSelection(in: textView)
                    }
                }
            }
            return
        }

        coordinator.didRequestInitialFocus = true
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            if centersSelectionWhenFocused {
                Coordinator.centerSelection(in: textView)
            }
        }
    }

    private func clampedRange(_ range: NSRange, for string: String) -> NSRange {
        let length = (string as NSString).length
        let location = max(0, min(range.location, length))
        let maxLength = max(0, length - location)
        return NSRange(location: location, length: max(0, min(range.length, maxLength)))
    }

    private func handleKeyDown(_ event: NSEvent, textView: BWRCommandTextView) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let hasSystemModifier = flags.contains(.command) || flags.contains(.option) || flags.contains(.control)

        if flags == [.command], characters == "f" {
            return onFindCommand?() ?? false
        }

        if characters == "z", flags.contains(.command) {
            if flags.contains(.shift) {
                return onRedoCommand?() ?? false
            }
            return onUndoCommand?() ?? false
        }

        if !hasSystemModifier && !flags.contains(.shift) {
            let selection = textView.selectedRange()
            let textLength = (textView.string as NSString).length

            if event.keyCode == 126,
               selection.length == 0,
               selection.location == 0 {
                return onBoundaryNavigation?(.previousCard, textView.string, selection) ?? false
            }

            if event.keyCode == 125,
               selection.length == 0,
               selection.location == textLength {
                return onBoundaryNavigation?(.nextCard, textView.string, selection) ?? false
            }
        }

        return false
    }
}
