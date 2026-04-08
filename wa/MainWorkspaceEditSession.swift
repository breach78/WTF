import AppKit
import Foundation

@MainActor
final class MainWorkspaceEditSession: NSObject, NSTextViewDelegate {
    struct Configuration: Equatable {
        let cardID: UUID
        let text: String
        let activeEditorSessionID: Int?
        let textWidth: CGFloat
        let bodyHeight: CGFloat
        let fontSize: CGFloat
        let lineSpacing: CGFloat
        let appearance: String
        let isFocused: Bool
    }

    private struct Signature: Equatable {
        let fontSizeBucket: Int
        let lineSpacingBucket: Int
        let isLightAppearance: Bool
        let widthBucket: Int
        let heightBucket: Int
    }

    final class TextView: NSTextView {
        var focusStateHandler: ((Bool) -> Void)?

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted {
                focusStateHandler?(true)
            }
            return accepted
        }

        override func resignFirstResponder() -> Bool {
            let accepted = super.resignFirstResponder()
            if accepted {
                focusStateHandler?(false)
            }
            return accepted
        }
    }

    var onTextChange: ((String, String) -> Void)?
    var onEndEditing: (() -> Void)?
    var onTab: (() -> Void)?
    var onCommandEnter: (() -> Void)?
    var onFocusStateChange: ((Bool) -> Void)?

    private let scrollView = NSScrollView()
    private let textView = TextView()

    private weak var hostView: NSView?
    private var suppressBindingPropagation = false
    private var lastSignature: Signature?
    private var lastAppliedEditorSessionID: Int?
    private var pendingFocusRetry: DispatchWorkItem?
    private var currentConfiguration: Configuration?
    private var lastTabPressAt = Date.distantPast
    private let tabArmingWindow: TimeInterval = 0.45

    override init() {
        super.init()
        setupEditor()
    }

    deinit {
        pendingFocusRetry?.cancel()
    }

    func attach(to hostView: NSView) {
        self.hostView = hostView
        if scrollView.superview !== hostView {
            scrollView.removeFromSuperview()
            hostView.addSubview(scrollView)
        }
    }

    func apply(configuration: Configuration) {
        currentConfiguration = configuration
        updateEditorFrame(for: configuration)
        applyEditorContent(configuration: configuration)
        if configuration.isFocused {
            requestFocus()
        }
    }

    func setHidden(_ isHidden: Bool) {
        scrollView.isHidden = isHidden
    }

    func frameDidChange() {
        guard let configuration = currentConfiguration else { return }
        updateEditorFrame(for: configuration)
    }

    func focus() {
        requestFocus()
    }

    func teardown() {
        pendingFocusRetry?.cancel()
        pendingFocusRetry = nil
        currentConfiguration = nil
        scrollView.removeFromSuperview()
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        guard !suppressBindingPropagation else { return }
        let updated = textView.string
        let previous = currentConfiguration?.text ?? ""
        if previous != updated {
            onTextChange?(previous, updated)
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        _ = notification
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onEndEditing?()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) ||
            commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) ||
            commandSelector == #selector(NSResponder.insertLineBreak(_:)) {
            let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            let hasExactCommandEnter = flags.contains(.command) &&
            !flags.contains(.shift) &&
            !flags.contains(.option) &&
            !flags.contains(.control)
            if hasExactCommandEnter {
                (onCommandEnter ?? onEndEditing)?()
                return true
            }
            if flags.contains(.shift) {
                textView.insertText("\n", replacementRange: textView.selectedRange())
                return true
            }
            return false
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            return handleTabCommand()
        }
        return false
    }

    private func handleTabCommand() -> Bool {
        let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        if !flags.isDisjoint(with: [.command, .option, .control, .shift]) {
            return false
        }

        let now = Date()
        if now.timeIntervalSince(lastTabPressAt) <= tabArmingWindow {
            onTab?()
            lastTabPressAt = .distantPast
            return true
        }
        lastTabPressAt = now
        return true
    }

    private func setupEditor() {
        scrollView.translatesAutoresizingMaskIntoConstraints = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        textView.delegate = self
        textView.focusStateHandler = { [weak self] isFocused in
            self?.onFocusStateChange?(isFocused)
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
        }

        scrollView.documentView = textView
        scrollView.isHidden = true
    }

    private func updateEditorFrame(for configuration: Configuration) {
        let resolvedWidth = max(1, configuration.textWidth)
        let resolvedHeight = max(1, configuration.bodyHeight)
        scrollView.frame = CGRect(origin: .zero, size: CGSize(width: resolvedWidth, height: resolvedHeight))
        textView.frame = CGRect(origin: .zero, size: CGSize(width: resolvedWidth, height: resolvedHeight))
        if let textContainer = textView.textContainer {
            let containerSize = CGSize(width: resolvedWidth, height: .greatestFiniteMagnitude)
            if abs(textContainer.containerSize.width - containerSize.width) > 0.5 {
                textContainer.containerSize = containerSize
            }
        }
    }

    private func applyEditorContent(configuration: Configuration) {
        let signature = Signature(
            fontSizeBucket: Int((configuration.fontSize * 10).rounded()),
            lineSpacingBucket: Int((configuration.lineSpacing * 10).rounded()),
            isLightAppearance: configuration.appearance == "light",
            widthBucket: Int((configuration.textWidth * 10).rounded()),
            heightBucket: Int((configuration.bodyHeight * 10).rounded())
        )

        let font =
            NSFont(name: "SansMonoCJKFinalDraft", size: configuration.fontSize) ??
            NSFont.monospacedSystemFont(ofSize: configuration.fontSize, weight: .regular)
        let color: NSColor = configuration.appearance == "light" ? .black : .white
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = configuration.lineSpacing
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineHeightMultiple = 1.0
        paragraph.paragraphSpacing = 0
        paragraph.paragraphSpacingBefore = 0

        let isFocusedResponder =
            configuration.isFocused &&
            (
                textView.window?.firstResponder === textView ||
                NSApp.keyWindow?.firstResponder === textView
            )
        let hasActiveEditorGuard = isFocusedResponder && configuration.activeEditorSessionID != nil

        if textView.string != configuration.text {
            let selected = textView.selectedRange()
            let modelLength = (configuration.text as NSString).length
            if !hasActiveEditorGuard {
                suppressBindingPropagation = true
                if configuration.text.isEmpty {
                    textView.string = ""
                } else {
                    textView.textStorage?.setAttributedString(
                        NSAttributedString(
                            string: configuration.text,
                            attributes: [
                                .font: font,
                                .foregroundColor: color,
                                .paragraphStyle: paragraph
                            ]
                        )
                    )
                }
                let clampedLocation = min(selected.location, modelLength)
                let clampedLength = min(selected.length, max(0, modelLength - clampedLocation))
                textView.setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
                suppressBindingPropagation = false
                lastAppliedEditorSessionID = configuration.activeEditorSessionID
            }
        } else {
            lastAppliedEditorSessionID = configuration.activeEditorSessionID
        }

        if lastSignature != signature {
            lastSignature = signature
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
            var typingAttributes = textView.typingAttributes
            typingAttributes[.font] = font
            typingAttributes[.foregroundColor] = color
            typingAttributes[.paragraphStyle] = paragraph
            textView.typingAttributes = typingAttributes
        }
    }

    private func requestFocus(remainingRetries: Int = 4) {
        pendingFocusRetry?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let configuration = self.currentConfiguration else { return }
            guard configuration.isFocused else { return }
            guard let window = self.textView.window else {
                if remainingRetries > 0 {
                    self.requestFocus(remainingRetries: remainingRetries - 1)
                }
                return
            }
            if window.firstResponder !== self.textView {
                window.makeFirstResponder(self.textView)
            }
            if window.firstResponder !== self.textView, remainingRetries > 0 {
                self.requestFocus(remainingRetries: remainingRetries - 1)
            }
        }
        pendingFocusRetry = work
        DispatchQueue.main.async(execute: work)
    }
}
