import SwiftUI
import AppKit
import Combine

final class FocusMonitorRecorder: ObservableObject {
    static let shared = FocusMonitorRecorder()

    @Published var isRecording: Bool = false
    @Published private(set) var visibleLogText: String = ""

    private struct Entry {
        let seq: Int
        let line: String
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var nextSeq: Int = 1
    private var refreshWorkItem: DispatchWorkItem?
    private let maxEntries = 5000

    private let tsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {}

    func clear() {
        lock.lock()
        entries.removeAll(keepingCapacity: true)
        nextSeq = 1
        lock.unlock()
        publishVisibleSnapshotNow()
    }

    func snapshotText() -> String {
        lock.lock()
        let text = entries.map(\.line).joined(separator: "\n")
        lock.unlock()
        return text
    }

    func validateMonotonicSequence() -> Bool {
        lock.lock()
        let seqs = entries.map(\.seq)
        lock.unlock()
        guard !seqs.isEmpty else { return false }
        var expected = seqs[0]
        for seq in seqs {
            if seq != expected { return false }
            expected += 1
        }
        return true
    }

    func record(_ event: String, reason: String = "n/a", payloadBuilder: () -> [String: String]) {
        guard isRecording else { return }
        let payload = payloadBuilder()
        append(event: event, reason: reason, payload: payload)
    }

    func record(_ event: String, reason: String = "n/a", payload: [String: String] = [:]) {
        guard isRecording else { return }
        append(event: event, reason: reason, payload: payload)
    }

    private func append(event: String, reason: String, payload: [String: String]) {
        let seq: Int
        lock.lock()
        seq = nextSeq
        nextSeq += 1
        let ts = tsFormatter.string(from: Date())
        let line = formatLine(seq: seq, ts: ts, event: event, reason: reason, payload: payload)
        entries.append(Entry(seq: seq, line: line))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        lock.unlock()
        scheduleVisibleSnapshotRefresh()
    }

    private func scheduleVisibleSnapshotRefresh() {
        if refreshWorkItem != nil { return }
        let work = DispatchWorkItem { [weak self] in
            self?.refreshWorkItem = nil
            self?.publishVisibleSnapshotNow()
        }
        refreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func publishVisibleSnapshotNow() {
        let snapshot = snapshotText()
        if Thread.isMainThread {
            visibleLogText = snapshot
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.visibleLogText = snapshot
            }
        }
    }

    private func formatLine(seq: Int, ts: String, event: String, reason: String, payload: [String: String]) -> String {
        let ordered = payload.keys.sorted().map { key -> String in
            let value = redactIfNeeded(payload[key] ?? "")
            return "\"\(escape(key))\":\"\(escape(value))\""
        }
        let payloadChunk = ordered.isEmpty ? "" : "," + ordered.joined(separator: ",")
        return "{\"seq\":\"\(seq)\",\"ts\":\"\(escape(ts))\",\"event\":\"\(escape(event))\",\"reason\":\"\(escape(reason))\"\(payloadChunk)}"
    }

    private func redactIfNeeded(_ value: String) -> String {
        let sentinel = ProcessInfo.processInfo.environment["WA_FOCUS_MONITOR_PRIVACY_SENTINEL"] ?? ""
        var result = value
        if !sentinel.isEmpty, result.contains(sentinel) {
            result = result.replacingOccurrences(of: sentinel, with: "[REDACTED]")
        }
        if UUID(uuidString: result) != nil {
            return "id:\(String(result.prefix(8)))"
        }
        return result
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
    }
}

final class FocusMonitorPanel: NSPanel {
    static let canBecomeKeyValue = false
    static let canBecomeMainValue = false
    override var canBecomeKey: Bool { Self.canBecomeKeyValue }
    override var canBecomeMain: Bool { Self.canBecomeMainValue }
}

final class FocusMonitorPanelController: NSObject, NSWindowDelegate {
    static let shared = FocusMonitorPanelController()

    private var panel: FocusMonitorPanel?

    private override init() {
        super.init()
    }

    func showPanel() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let panel = FocusMonitorPanel(
            contentRect: NSRect(x: 80, y: 80, width: 620, height: 420),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Focus Monitor"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: FocusMonitorWindowView(recorder: .shared))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
    }
}

struct FocusMonitorWindowView: View {
    @ObservedObject var recorder: FocusMonitorRecorder

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(recorder.isRecording ? "Stop" : "Start") {
                    recorder.isRecording.toggle()
                    recorder.record("monitor.recording.toggle", reason: "button") {
                        ["isRecording": recorder.isRecording ? "true" : "false"]
                    }
                }

                Button("Clear") {
                    recorder.clear()
                }

                Button("Copy") {
                    let text = recorder.snapshotText()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }

                Spacer()
                Text(recorder.isRecording ? "Monitoring: ON" : "Monitoring: OFF")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }

            Divider()

            ScrollView {
                Text(recorder.visibleLogText.isEmpty ? "(no events)" : recorder.visibleLogText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .padding(8)
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
        }
        .padding(12)
        .frame(minWidth: 540, minHeight: 320)
    }
}
