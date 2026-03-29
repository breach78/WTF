import Foundation
import QuartzCore
import Combine

@MainActor
final class MainCanvasPerformanceMonitor: ObservableObject {
    static let loggingEnabledDefaultsKey = "mainCanvasPerformanceLoggingEnabled"
    static let logURL = URL(fileURLWithPath: "/tmp/wa_main_canvas_performance.log")
    private static let sharedFileQueue = DispatchQueue(
        label: "wa.main-canvas-performance-monitor.shared-log"
    )

    private let sampleQueue = DispatchQueue(label: "wa.main-canvas-performance-monitor")
    private let recentLatencyLimit = 120
    private let hitchLogThresholdMilliseconds = 50.0
    private let hitchLogCooldownSeconds = 0.75
    private let summaryIntervalSeconds = 5.0

    private var sampleTimer: DispatchSourceTimer?
    private var recentMainThreadLatencies: [Double] = []
    private var ownerKey: String?
    private var horizontalMode: MainCanvasHorizontalScrollMode = .defaultPolicy
    private var isRunning = false
    private var lastHitchLoggedAt: CFTimeInterval = 0
    private var lastSummaryLoggedAt: CFTimeInterval = 0

    func update(
        isEnabled: Bool,
        ownerKey: String,
        horizontalMode: MainCanvasHorizontalScrollMode
    ) {
        self.horizontalMode = horizontalMode

        if isEnabled {
            UserDefaults.standard.set(true, forKey: Self.loggingEnabledDefaultsKey)
            if isRunning, self.ownerKey == ownerKey {
                return
            }
            stop(emitStopLog: isRunning)
            self.ownerKey = ownerKey
            start()
            return
        }

        stop(emitStopLog: isRunning)
        UserDefaults.standard.set(false, forKey: Self.loggingEnabledDefaultsKey)
    }

    func stop() {
        stop(emitStopLog: isRunning)
    }

    private func start() {
        guard let ownerKey else { return }
        isRunning = true
        recentMainThreadLatencies.removeAll(keepingCapacity: true)
        lastHitchLoggedAt = 0
        lastSummaryLoggedAt = 0
        appendLog(
            event: "monitor.start",
            payload: [
                "owner": ownerKey,
                "horizontal_mode": horizontalModeLabel(horizontalMode),
                "log_path": Self.logURL.path
            ]
        )

        let timer = DispatchSource.makeTimerSource(queue: sampleQueue)
        timer.schedule(
            deadline: .now() + .milliseconds(250),
            repeating: .milliseconds(250),
            leeway: .milliseconds(50)
        )
        timer.setEventHandler { [weak self] in
            let scheduledAt = CACurrentMediaTime()
            Task { @MainActor [weak self] in
                self?.recordSample(scheduledAt: scheduledAt)
            }
        }
        sampleTimer = timer
        timer.resume()
    }

    private func stop(emitStopLog: Bool) {
        sampleTimer?.cancel()
        sampleTimer = nil
        guard isRunning else { return }
        if emitStopLog, let ownerKey {
            let stats = recentLatencyStats()
            appendLog(
                event: "monitor.stop",
                payload: [
                    "owner": ownerKey,
                    "horizontal_mode": horizontalModeLabel(horizontalMode),
                    "main_thread_avg_ms": format(stats.averageMilliseconds),
                    "main_thread_max_ms": format(stats.maxMilliseconds)
                ]
            )
        }
        isRunning = false
        ownerKey = nil
        recentMainThreadLatencies.removeAll(keepingCapacity: false)
    }

    private func recordSample(scheduledAt: CFTimeInterval) {
        guard isRunning, let ownerKey else { return }

        let now = CACurrentMediaTime()
        let latencyMilliseconds = max(0, (now - scheduledAt) * 1000)
        recentMainThreadLatencies.append(latencyMilliseconds)
        if recentMainThreadLatencies.count > recentLatencyLimit {
            recentMainThreadLatencies.removeFirst(recentMainThreadLatencies.count - recentLatencyLimit)
        }

        let stats = recentLatencyStats()
        if latencyMilliseconds >= hitchLogThresholdMilliseconds,
           now - lastHitchLoggedAt >= hitchLogCooldownSeconds {
            lastHitchLoggedAt = now
            appendLog(
                event: "main_thread_hitch",
                payload: [
                    "owner": ownerKey,
                    "latency_ms": format(latencyMilliseconds),
                    "recent_avg_ms": format(stats.averageMilliseconds),
                    "recent_max_ms": format(stats.maxMilliseconds),
                    "recent_over_33ms": "\(stats.over33MillisecondsCount)",
                    "recent_over_50ms": "\(stats.over50MillisecondsCount)",
                    "recent_over_100ms": "\(stats.over100MillisecondsCount)"
                ]
            )
        }

        if now - lastSummaryLoggedAt >= summaryIntervalSeconds {
            lastSummaryLoggedAt = now
            recordSummary(ownerKey: ownerKey, stats: stats)
        }
    }

    private func recordSummary(ownerKey: String, stats: MainThreadLatencyStats) {
        let navigationSummary = MainCanvasNavigationDiagnostics.shared.emitSummary(
            ownerKey: ownerKey,
            reason: "performanceMonitor",
            horizontalMode: horizontalMode
        ) ?? "unavailable"

        appendLog(
            event: "summary",
            payload: [
                "owner": ownerKey,
                "horizontal_mode": horizontalModeLabel(horizontalMode),
                "main_thread_avg_ms": format(stats.averageMilliseconds),
                "main_thread_max_ms": format(stats.maxMilliseconds),
                "recent_over_33ms": "\(stats.over33MillisecondsCount)",
                "recent_over_50ms": "\(stats.over50MillisecondsCount)",
                "recent_over_100ms": "\(stats.over100MillisecondsCount)",
                "navigation": navigationSummary
            ]
        )
    }

    private func recentLatencyStats() -> MainThreadLatencyStats {
        guard !recentMainThreadLatencies.isEmpty else { return MainThreadLatencyStats() }
        let count = recentMainThreadLatencies.count
        let total = recentMainThreadLatencies.reduce(0, +)
        let maximum = recentMainThreadLatencies.max() ?? 0
        let over33 = recentMainThreadLatencies.filter { $0 >= 33 }.count
        let over50 = recentMainThreadLatencies.filter { $0 >= 50 }.count
        let over100 = recentMainThreadLatencies.filter { $0 >= 100 }.count
        return MainThreadLatencyStats(
            averageMilliseconds: total / Double(count),
            maxMilliseconds: maximum,
            over33MillisecondsCount: over33,
            over50MillisecondsCount: over50,
            over100MillisecondsCount: over100
        )
    }

    private func appendLog(event: String, payload: [String: String]) {
        Self.appendEvent(event: event, payload: payload)
    }

    static func appendEvent(event: String, payload: [String: String]) {
        let timestamp = ISO8601DateFormatter.performanceMonitor.string(from: Date())
        let line = makeJSONLine(timestamp: timestamp, event: event, payload: payload)
        let data = Data((line + "\n").utf8)
        let logURL = Self.logURL
        sharedFileQueue.async {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path),
               let fileSize = attributes[.size] as? NSNumber,
               fileSize.intValue > 2_000_000 {
                try? Data().write(to: logURL, options: .atomic)
            }
            if FileManager.default.fileExists(atPath: logURL.path),
               let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                return
            }
            try? data.write(to: logURL, options: .atomic)
        }
    }

    private static func makeJSONLine(timestamp: String, event: String, payload: [String: String]) -> String {
        let orderedPayload = payload.keys.sorted().map { key in
            "\"\(escape(key))\":\"\(escape(payload[key] ?? ""))\""
        }
        let payloadChunk = orderedPayload.isEmpty ? "" : "," + orderedPayload.joined(separator: ",")
        return "{\"ts\":\"\(escape(timestamp))\",\"event\":\"\(escape(event))\"\(payloadChunk)}"
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func horizontalModeLabel(_ mode: MainCanvasHorizontalScrollMode) -> String {
        switch mode {
        case .oneStep:
            return "oneStep"
        case .twoStep:
            return "twoStep"
        }
    }
}

private struct MainThreadLatencyStats {
    var averageMilliseconds: Double = 0
    var maxMilliseconds: Double = 0
    var over33MillisecondsCount: Int = 0
    var over50MillisecondsCount: Int = 0
    var over100MillisecondsCount: Int = 0
}

private extension ISO8601DateFormatter {
    static let performanceMonitor: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
