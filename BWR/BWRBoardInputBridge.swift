import AppKit
import SwiftUI

struct BWRBoardKeyboardMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onKeyEvent: (NSEvent) -> Bool

    func makeNSView(context: Context) -> BWRBoardKeyboardMonitorView {
        let view = BWRBoardKeyboardMonitorView()
        view.isEnabled = isEnabled
        view.onKeyEvent = onKeyEvent
        return view
    }

    func updateNSView(_ nsView: BWRBoardKeyboardMonitorView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onKeyEvent = onKeyEvent
    }
}

final class BWRBoardKeyboardMonitorView: NSView {
    var isEnabled = true
    var onKeyEvent: ((NSEvent) -> Bool)?

    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitorIfNeeded()
    }

    override func removeFromSuperview() {
        super.removeFromSuperview()
        removeMonitor()
    }

    deinit {
        removeMonitor()
    }

    private func installMonitorIfNeeded() {
        guard monitor == nil else {
            return
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            return shouldHandle(event) ? nil : event
        }
    }

    private func removeMonitor() {
        guard let monitor else {
            return
        }

        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    private func shouldHandle(_ event: NSEvent) -> Bool {
        guard
            isEnabled,
            let window,
            window.isKeyWindow,
            let onKeyEvent
        else {
            return false
        }

        if window.firstResponder is NSTextView {
            return false
        }

        return onKeyEvent(event)
    }
}

struct BWRInlineMarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let isFocused: Bool
    let onCommit: () -> Void
    let onAdvance: (Bool) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onCommit: onCommit,
            onAdvance: onAdvance,
            onCancel: onCancel
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = BWRInlineTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.font = NSFont(name: "Avenir Next", size: 13) ?? .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.onCommit = context.coordinator.onCommit
        textView.onAdvance = context.coordinator.onAdvance
        textView.onCancel = context.coordinator.onCancel

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? BWRInlineTextView else {
            return
        }

        context.coordinator.text = $text
        textView.onCommit = context.coordinator.onCommit
        textView.onAdvance = context.coordinator.onAdvance
        textView.onCancel = context.coordinator.onCancel

        if textView.string != text {
            textView.string = text
        }

        if isFocused, textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        let onCommit: () -> Void
        let onAdvance: (Bool) -> Void
        let onCancel: () -> Void

        init(
            text: Binding<String>,
            onCommit: @escaping () -> Void,
            onAdvance: @escaping (Bool) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.text = text
            self.onCommit = onCommit
            self.onAdvance = onAdvance
            self.onCancel = onCancel
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            text.wrappedValue = textView.string
        }
    }
}

private final class BWRInlineTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onAdvance: ((Bool) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasOnlyShiftModifier = modifiers == [.shift]
        let hasNoModifiers = modifiers.isEmpty

        switch event.keyCode {
        case 36, 76:
            if hasNoModifiers {
                onCommit?()
                return
            }
        case 48:
            if hasNoModifiers || hasOnlyShiftModifier {
                onAdvance?(hasOnlyShiftModifier)
                return
            }
        case 53:
            if hasNoModifiers {
                onCancel?()
                return
            }
        default:
            break
        }

        super.keyDown(with: event)
    }
}
