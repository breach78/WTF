import Foundation

private enum IndexBoardOrderDiagnostics {
    static let isEnabled =
        ProcessInfo.processInfo.environment["WA_INDEX_BOARD_ORDER_TRACE"] == "1" ||
        UserDefaults.standard.bool(forKey: "WAIndexBoardOrderTraceEnabled")
    static let formatter = ISO8601DateFormatter()
}

func indexBoardOrderDiagnosticsLog(_ message: @autoclosure () -> String) {
    guard IndexBoardOrderDiagnostics.isEnabled else { return }
    let line = "[\(IndexBoardOrderDiagnostics.formatter.string(from: Date()))] \(message())\n"
    let url = URL(fileURLWithPath: "/tmp/wa_index_board_order_trace.log")
    let data = Data(line.utf8)
    if FileManager.default.fileExists(atPath: url.path),
       let handle = try? FileHandle(forWritingTo: url) {
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    } else {
        try? data.write(to: url, options: .atomic)
    }
}

private enum IndexBoardDropPerformanceDiagnostics {
    static let logURL = URL(fileURLWithPath: "/tmp/wa_index_board_drop_perf.log")
    static let queue = DispatchQueue(label: "wa.index-board-drop-performance")
    static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func log(_ event: String, details: @autoclosure @escaping () -> String = "") {
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(event) \(details())\n"
        queue.async {
            let data = Data(line.utf8)
            if FileManager.default.fileExists(atPath: logURL.path),
               let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                return
            }
            try? data.write(to: logURL, options: .atomic)
        }
    }
}

func indexBoardDropPerformanceMark(_ label: String) {
    IndexBoardDropPerformanceDiagnostics.log("========== \(label) ==========")
}

func indexBoardDropPerformanceLog(
    _ event: String,
    _ details: @autoclosure @escaping () -> String = ""
) {
    IndexBoardDropPerformanceDiagnostics.log(event, details: details())
}
