import Foundation

enum IndexBoardRestoreDiagnostics {
    static let logURL = URL(fileURLWithPath: "/tmp/wa_index_board_restore_trace.log")

    private static let queue = DispatchQueue(label: "wa.index-board-restore-diagnostics")
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func log(_ event: String, details: @autoclosure @escaping () -> String = "") {
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(event) \(details())\n"
        queue.async {
            let data = Data(line.utf8)
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    defer { try? handle.close() }
                    try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    return
                }
            }
            try? data.write(to: logURL, options: .atomic)
        }
    }

    static func markSession(_ label: String) {
        log("========== \(label) ==========")
    }
}

func indexBoardRestoreTrace(_ event: String, _ details: @autoclosure @escaping () -> String = "") {
    IndexBoardRestoreDiagnostics.log(event, details: details())
}

func indexBoardRestoreTraceMark(_ label: String) {
    IndexBoardRestoreDiagnostics.markSession(label)
}

func debugRestoreUUID(_ value: UUID?) -> String {
    guard let value else { return "nil" }
    return value.uuidString
}

func debugRestoreCGFloat(_ value: CGFloat?) -> String {
    guard let value else { return "nil" }
    return String(format: "%.2f", value)
}

func debugRestoreViewportOffsets(_ offsets: [String: CGFloat]) -> String {
    guard !offsets.isEmpty else { return "[]" }
    let sorted = offsets
        .sorted { $0.key < $1.key }
        .prefix(6)
        .map { "\($0.key)=\(String(format: "%.2f", $0.value))" }
        .joined(separator: ",")
    let suffix = offsets.count > 6 ? ",..." : ""
    return "[\(sorted)\(suffix)]"
}
