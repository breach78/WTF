import AppKit
import Foundation

enum BWRBoardDebugLogger {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["BWR_DEBUG_MONITOR"] == "1"
    }

    static func log(_ category: String, _ message: @autoclosure () -> String) {
        guard isEnabled else {
            return
        }

        let timestamp = Self.timestampFormatter.string(from: Date())
        let line = "[BWR Debug][\(timestamp)][\(category)] \(message())\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }

    static func describe(slot: BoardSlot?) -> String {
        guard let slot else {
            return "nil"
        }
        return "r\(slot.row)c\(slot.column)"
    }

    static func describe(selection: BoardSelection) -> String {
        switch selection {
        case .none:
            return "none"
        case .cards(let ids):
            return "cards[\(ids.count)]"
        case .slots(let slots):
            return "slots[\(slots.count)] \(slots.sorted().map(describe(slot:)).joined(separator: ","))"
        }
    }

    static func describe(bounds: BoardVisibleBounds) -> String {
        "rows \(bounds.minRow)...\(bounds.maxRow) cols \(bounds.minColumn)...\(bounds.maxColumn)"
    }

    static func describe(responder: NSResponder?) -> String {
        guard let responder else {
            return "nil"
        }
        return String(describing: type(of: responder))
    }

    static func describe(event: NSEvent) -> String {
        let modifiers = event.modifierFlags.bwrCommandModifiers
        let modifierText = modifiers.isEmpty ? "none" : String(describing: modifiers)
        return "keyCode=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "-") modifiers=\(modifierText)"
    }

    static func describe(gesture: BoardTransientGestureState) -> String {
        "drag=\(gesture.hasDragSession) marquee=\(gesture.hasMarqueeSelection)"
    }

    static func describe(dragSession: BoardDragSession?) -> String {
        guard let dragSession else {
            return "nil"
        }

        return "cards=\(dragSession.selectedCardIDs.count) offset=(\(dragSession.previewOffset.rows),\(dragSession.previewOffset.columns))"
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
