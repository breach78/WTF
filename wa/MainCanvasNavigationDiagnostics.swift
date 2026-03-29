import Foundation
import QuartzCore
import os

@MainActor
final class MainCanvasNavigationDiagnostics {
    static let shared = MainCanvasNavigationDiagnostics()

    struct DurationStats {
        var count: Int = 0
        var totalMilliseconds: Double = 0
        var maxMilliseconds: Double = 0

        mutating func record(_ milliseconds: Double) {
            count += 1
            totalMilliseconds += milliseconds
            maxMilliseconds = max(maxMilliseconds, milliseconds)
        }

        var averageMilliseconds: Double {
            guard count > 0 else { return 0 }
            return totalMilliseconds / Double(count)
        }
    }

    struct OwnerCounters {
        var focusIntentCount: Int = 0
        var repeatFocusIntentCount: Int = 0
        var firstScrollLatencyStats = DurationStats()
        var relationSyncStats = DurationStats()
        var layoutResolveStats = DurationStats()
        var layoutCacheMissCount: Int = 0
        var verticalNativeScrollCount: Int = 0
        var verticalFallbackScrollCount: Int = 0
        var horizontalNativeScrollCount: Int = 0
        var horizontalFallbackScrollCount: Int = 0
        var animationOverlapCount: Int = 0
        var verticalVerificationRetryCount: Int = 0
        var horizontalRetryCount: Int = 0
        var focusedEditorOverwriteCount: Int = 0
    }

    private struct PendingFocusIntent {
        let signpostID: OSSignpostID
        let startedAt: CFTimeInterval
        let direction: String
        let isRepeat: Bool
        let sourceCardID: UUID?
        let intendedCardID: UUID?
    }

    private struct PendingFirstScrollMeasurement {
        let startedAt: CFTimeInterval
        let direction: String
        let isRepeat: Bool
        let sourceCardID: UUID?
        let intendedCardID: UUID?
    }

    private struct PendingScrollAnimation {
        let signpostID: OSSignpostID
        let isAnimated: Bool
    }

    private let log = OSLog(subsystem: "com.riwoong.wa", category: "MainCanvasNavigation")
    private let summaryURL = URL(fileURLWithPath: "/tmp/wa_main_workspace_phase0_summary.txt")
    private let summaryQueue = DispatchQueue(label: "wa.main-workspace-phase0-summary")
    private let summaryFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private var pendingFocusIntentByOwnerKey: [String: PendingFocusIntent] = [:]
    private var pendingFirstScrollMeasurementByOwnerKey: [String: PendingFirstScrollMeasurement] = [:]
    private var pendingScrollAnimationByToken: [String: PendingScrollAnimation] = [:]
    private var countersByOwnerKey: [String: OwnerCounters] = [:]

    private init() {}

    func reset(ownerKey: String, scenarioID: UUID, splitPaneID: Int) {
        pendingFocusIntentByOwnerKey.removeValue(forKey: ownerKey)
        pendingFirstScrollMeasurementByOwnerKey.removeValue(forKey: ownerKey)
        let pendingTokens = pendingScrollAnimationByToken.keys.filter { $0.hasPrefix("\(ownerKey)|") }
        for token in pendingTokens {
            pendingScrollAnimationByToken.removeValue(forKey: token)
        }
        countersByOwnerKey[ownerKey] = OwnerCounters()
        os_signpost(
            .event,
            log: log,
            name: "DiagnosticsReset",
            "owner=%{public}@ scenario=%{public}@ pane=%{public}d",
            ownerKey as NSString,
            scenarioID.uuidString as NSString,
            splitPaneID
        )
        persistSummary(reason: "reset")
    }

    func beginFocusIntent(
        ownerKey: String,
        direction: ScenarioWriterView.MainArrowDirection?,
        isRepeat: Bool,
        sourceCardID: UUID?,
        intendedCardID: UUID?
    ) {
        guard let direction else { return }

        if let pending = pendingFocusIntentByOwnerKey.removeValue(forKey: ownerKey) {
            os_signpost(
                .end,
                log: log,
                name: "FocusIntent",
                signpostID: pending.signpostID,
                "owner=%{public}@ status=interrupted elapsed_ms=%{public}.2f",
                ownerKey as NSString,
                elapsedMilliseconds(since: pending.startedAt)
            )
        }

        var counters = countersByOwnerKey[ownerKey] ?? OwnerCounters()
        counters.focusIntentCount += 1
        if isRepeat {
            counters.repeatFocusIntentCount += 1
        }
        countersByOwnerKey[ownerKey] = counters

        let signpostID = OSSignpostID(log: log)
        let directionLabel = string(for: direction)
        os_signpost(
            .begin,
            log: log,
            name: "FocusIntent",
            signpostID: signpostID,
            "owner=%{public}@ direction=%{public}@ repeat=%{public}@ from=%{public}@ to=%{public}@",
            ownerKey as NSString,
            directionLabel as NSString,
            boolString(isRepeat) as NSString,
            cardIDString(sourceCardID),
            cardIDString(intendedCardID)
        )
        pendingFocusIntentByOwnerKey[ownerKey] = PendingFocusIntent(
            signpostID: signpostID,
            startedAt: CACurrentMediaTime(),
            direction: directionLabel,
            isRepeat: isRepeat,
            sourceCardID: sourceCardID,
            intendedCardID: intendedCardID
        )
        pendingFirstScrollMeasurementByOwnerKey[ownerKey] = PendingFirstScrollMeasurement(
            startedAt: CACurrentMediaTime(),
            direction: directionLabel,
            isRepeat: isRepeat,
            sourceCardID: sourceCardID,
            intendedCardID: intendedCardID
        )
        persistSummary(reason: "focus-intent")
    }

    func recordRelationSync(
        ownerKey: String,
        activeCardID: UUID?,
        durationMilliseconds: Double,
        ancestorCount: Int,
        siblingCount: Int,
        descendantCount: Int
    ) {
        var counters = countersByOwnerKey[ownerKey] ?? OwnerCounters()
        counters.relationSyncStats.record(durationMilliseconds)
        countersByOwnerKey[ownerKey] = counters

        os_signpost(
            .event,
            log: log,
            name: "RelationSync",
            "owner=%{public}@ active=%{public}@ duration_ms=%{public}.2f ancestors=%{public}d siblings=%{public}d descendants=%{public}d",
            ownerKey as NSString,
            cardIDString(activeCardID),
            durationMilliseconds,
            ancestorCount,
            siblingCount,
            descendantCount
        )

        if let pending = pendingFocusIntentByOwnerKey.removeValue(forKey: ownerKey) {
            let elapsed = elapsedMilliseconds(since: pending.startedAt)
            os_signpost(
                .end,
                log: log,
                name: "FocusIntent",
                signpostID: pending.signpostID,
                "owner=%{public}@ direction=%{public}@ repeat=%{public}@ active=%{public}@ relation_ms=%{public}.2f total_ms=%{public}.2f",
                ownerKey as NSString,
                pending.direction as NSString,
                boolString(pending.isRepeat) as NSString,
                cardIDString(activeCardID),
                durationMilliseconds,
                elapsed
            )
        }
        persistSummary(reason: "relation-sync")
    }

    func recordColumnLayoutResolve(
        ownerKey: String,
        cardCount: Int,
        viewportHeight: CGFloat,
        cacheHit: Bool,
        containsEditingCard: Bool,
        durationMilliseconds: Double
    ) {
        var counters = countersByOwnerKey[ownerKey] ?? OwnerCounters()
        counters.layoutResolveStats.record(durationMilliseconds)
        if !cacheHit {
            counters.layoutCacheMissCount += 1
        }
        countersByOwnerKey[ownerKey] = counters

        os_signpost(
            .event,
            log: log,
            name: "ColumnLayoutResolve",
            "owner=%{public}@ cards=%{public}d viewport_h=%{public}.1f cache_hit=%{public}@ editing=%{public}@ duration_ms=%{public}.2f",
            ownerKey as NSString,
            cardCount,
            Double(viewportHeight),
            boolString(cacheHit) as NSString,
            boolString(containsEditingCard) as NSString,
            durationMilliseconds
        )
    }

    func beginScrollAnimation(
        ownerKey: String,
        axis: String,
        engine: String,
        animated: Bool,
        target: String,
        expectedDuration: TimeInterval
    ) {
        recordFirstScrollStartIfNeeded(
            ownerKey: ownerKey,
            axis: axis,
            engine: engine,
            animated: animated,
            target: target
        )

        let token = scrollToken(ownerKey: ownerKey, axis: axis, engine: engine)
        var counters = countersByOwnerKey[ownerKey] ?? OwnerCounters()
        if let existing = pendingScrollAnimationByToken.removeValue(forKey: token) {
            os_signpost(
                .end,
                log: log,
                name: "ScrollAnimation",
                signpostID: existing.signpostID,
                "owner=%{public}@ axis=%{public}@ engine=%{public}@ status=replaced",
                ownerKey as NSString,
                axis as NSString,
                engine as NSString
            )
            if existing.isAnimated || animated {
                counters.animationOverlapCount += 1
                os_signpost(
                    .event,
                    log: log,
                    name: "AnimationOverlap",
                    "owner=%{public}@ axis=%{public}@ engine=%{public}@ target=%{public}@ count=%{public}d",
                    ownerKey as NSString,
                    axis as NSString,
                    engine as NSString,
                    target as NSString,
                    counters.animationOverlapCount
                )
            }
        }

        let signpostID = OSSignpostID(log: log)
        pendingScrollAnimationByToken[token] = PendingScrollAnimation(
            signpostID: signpostID,
            isAnimated: animated
        )

        switch (axis, engine) {
        case ("vertical", "native"):
            counters.verticalNativeScrollCount += 1
        case ("vertical", _):
            counters.verticalFallbackScrollCount += 1
        case ("horizontal", "native"):
            counters.horizontalNativeScrollCount += 1
        case ("horizontal", _):
            counters.horizontalFallbackScrollCount += 1
        default:
            break
        }
        countersByOwnerKey[ownerKey] = counters
        persistSummary(reason: "scroll-begin")

        os_signpost(
            .begin,
            log: log,
            name: "ScrollAnimation",
            signpostID: signpostID,
            "owner=%{public}@ axis=%{public}@ engine=%{public}@ animated=%{public}@ target=%{public}@ duration_ms=%{public}.2f",
            ownerKey as NSString,
            axis as NSString,
            engine as NSString,
            boolString(animated) as NSString,
            target as NSString,
            expectedDuration * 1000
        )

        if expectedDuration <= 0.001 {
            endScrollAnimation(ownerKey: ownerKey, axis: axis, engine: engine, status: "immediate")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + expectedDuration) { [weak self] in
            Task { @MainActor [weak self] in
                self?.endScrollAnimation(ownerKey: ownerKey, axis: axis, engine: engine, status: "completed")
            }
        }
    }

    func recordVerificationRetry(
        ownerKey: String,
        viewportKey: String,
        attempt: Int,
        targetID: UUID,
        observedFrame: Bool,
        animatedRetry: Bool
    ) {
        var counters = countersByOwnerKey[ownerKey] ?? OwnerCounters()
        counters.verticalVerificationRetryCount += 1
        countersByOwnerKey[ownerKey] = counters

        os_signpost(
            .event,
            log: log,
            name: "VerificationRetry",
            "owner=%{public}@ viewport=%{public}@ attempt=%{public}d target=%{public}@ observed=%{public}@ animated=%{public}@",
            ownerKey as NSString,
            viewportKey as NSString,
            attempt,
            cardIDString(targetID),
            boolString(observedFrame) as NSString,
            boolString(animatedRetry) as NSString
        )
        persistSummary(reason: "verification-retry")
    }

    func recordHorizontalRetry(
        ownerKey: String,
        reason: String,
        attempt: Int,
        targetID: UUID,
        animated: Bool
    ) {
        var counters = countersByOwnerKey[ownerKey] ?? OwnerCounters()
        counters.horizontalRetryCount += 1
        countersByOwnerKey[ownerKey] = counters

        os_signpost(
            .event,
            log: log,
            name: "HorizontalRetry",
            "owner=%{public}@ reason=%{public}@ attempt=%{public}d target=%{public}@ animated=%{public}@",
            ownerKey as NSString,
            reason as NSString,
            attempt,
            cardIDString(targetID),
            boolString(animated) as NSString
        )
        persistSummary(reason: "horizontal-retry")
    }

    func recordFocusedEditorOverwrite(
        ownerKey: String,
        cardID: UUID,
        selectionBefore: NSRange,
        selectionAfter: NSRange,
        currentLength: Int,
        modelLength: Int
    ) {
        var counters = countersByOwnerKey[ownerKey] ?? OwnerCounters()
        counters.focusedEditorOverwriteCount += 1
        countersByOwnerKey[ownerKey] = counters

        os_signpost(
            .event,
            log: log,
            name: "FocusedEditorOverwrite",
            "owner=%{public}@ card=%{public}@ before=%{public}d:%{public}d after=%{public}d:%{public}d current_len=%{public}d model_len=%{public}d count=%{public}d",
            ownerKey as NSString,
            cardIDString(cardID),
            selectionBefore.location,
            selectionBefore.length,
            selectionAfter.location,
            selectionAfter.length,
            currentLength,
            modelLength,
            counters.focusedEditorOverwriteCount
        )
        persistSummary(reason: "focused-editor-overwrite")
    }

    func emitSummary(ownerKey: String, reason: String) {
        guard let counters = countersByOwnerKey[ownerKey] else { return }

        os_log(
            "summary owner=%{public}@ reason=%{public}@ focus=%{public}d repeat=%{public}d first_scroll_avg_ms=%{public}.2f first_scroll_max_ms=%{public}.2f relation_avg_ms=%{public}.2f relation_max_ms=%{public}.2f layout_avg_ms=%{public}.2f layout_max_ms=%{public}.2f layout_miss=%{public}d v_native=%{public}d v_fallback=%{public}d h_native=%{public}d h_fallback=%{public}d overlaps=%{public}d vertical_retries=%{public}d horizontal_retries=%{public}d focused_overwrites=%{public}d",
            log: log,
            type: .info,
            ownerKey as NSString,
            reason as NSString,
            counters.focusIntentCount,
            counters.repeatFocusIntentCount,
            counters.firstScrollLatencyStats.averageMilliseconds,
            counters.firstScrollLatencyStats.maxMilliseconds,
            counters.relationSyncStats.averageMilliseconds,
            counters.relationSyncStats.maxMilliseconds,
            counters.layoutResolveStats.averageMilliseconds,
            counters.layoutResolveStats.maxMilliseconds,
            counters.layoutCacheMissCount,
            counters.verticalNativeScrollCount,
            counters.verticalFallbackScrollCount,
            counters.horizontalNativeScrollCount,
            counters.horizontalFallbackScrollCount,
            counters.animationOverlapCount,
            counters.verticalVerificationRetryCount,
            counters.horizontalRetryCount,
            counters.focusedEditorOverwriteCount
        )
        persistSummary(reason: reason)
    }

    private func endScrollAnimation(ownerKey: String, axis: String, engine: String, status: String) {
        let token = scrollToken(ownerKey: ownerKey, axis: axis, engine: engine)
        guard let pending = pendingScrollAnimationByToken.removeValue(forKey: token) else { return }
        os_signpost(
            .end,
            log: log,
            name: "ScrollAnimation",
            signpostID: pending.signpostID,
            "owner=%{public}@ axis=%{public}@ engine=%{public}@ status=%{public}@",
            ownerKey as NSString,
            axis as NSString,
            engine as NSString,
            status as NSString
        )
    }

    private func recordFirstScrollStartIfNeeded(
        ownerKey: String,
        axis: String,
        engine: String,
        animated: Bool,
        target: String
    ) {
        guard let pending = pendingFirstScrollMeasurementByOwnerKey.removeValue(forKey: ownerKey) else { return }
        let elapsed = elapsedMilliseconds(since: pending.startedAt)
        var counters = countersByOwnerKey[ownerKey] ?? OwnerCounters()
        counters.firstScrollLatencyStats.record(elapsed)
        countersByOwnerKey[ownerKey] = counters

        os_signpost(
            .event,
            log: log,
            name: "FocusToFirstScroll",
            "owner=%{public}@ direction=%{public}@ repeat=%{public}@ axis=%{public}@ engine=%{public}@ target=%{public}@ from=%{public}@ intended=%{public}@ elapsed_ms=%{public}.2f animated=%{public}@",
            ownerKey as NSString,
            pending.direction as NSString,
            boolString(pending.isRepeat) as NSString,
            axis as NSString,
            engine as NSString,
            target as NSString,
            cardIDString(pending.sourceCardID),
            cardIDString(pending.intendedCardID),
            elapsed,
            boolString(animated) as NSString
        )
    }

    private func elapsedMilliseconds(since startedAt: CFTimeInterval) -> Double {
        (CACurrentMediaTime() - startedAt) * 1000
    }

    private func persistSummary(reason: String) {
        let timestamp = summaryFormatter.string(from: Date())
        var lines: [String] = [
            "updated_at=\(timestamp)",
            "reason=\(reason)"
        ]

        for ownerKey in countersByOwnerKey.keys.sorted() {
            guard let counters = countersByOwnerKey[ownerKey] else { continue }
            lines.append("")
            lines.append("[\(ownerKey)]")
            lines.append("focus_intent_count=\(counters.focusIntentCount)")
            lines.append("repeat_focus_intent_count=\(counters.repeatFocusIntentCount)")
            lines.append(
                String(
                    format: "arrow_to_first_scroll_avg_ms=%.2f",
                    counters.firstScrollLatencyStats.averageMilliseconds
                )
            )
            lines.append(
                String(
                    format: "arrow_to_first_scroll_max_ms=%.2f",
                    counters.firstScrollLatencyStats.maxMilliseconds
                )
            )
            lines.append("animation_overlap_count=\(counters.animationOverlapCount)")
            lines.append("vertical_verify_retry_count=\(counters.verticalVerificationRetryCount)")
            lines.append("horizontal_retry_count=\(counters.horizontalRetryCount)")
            lines.append("active_editor_caret_jump_count=\(counters.focusedEditorOverwriteCount)")
            lines.append(
                String(
                    format: "relation_sync_avg_ms=%.2f",
                    counters.relationSyncStats.averageMilliseconds
                )
            )
            lines.append(
                String(
                    format: "relation_sync_max_ms=%.2f",
                    counters.relationSyncStats.maxMilliseconds
                )
            )
            lines.append(
                String(
                    format: "layout_resolve_avg_ms=%.2f",
                    counters.layoutResolveStats.averageMilliseconds
                )
            )
            lines.append(
                String(
                    format: "layout_resolve_max_ms=%.2f",
                    counters.layoutResolveStats.maxMilliseconds
                )
            )
            lines.append("layout_cache_miss_count=\(counters.layoutCacheMissCount)")
            lines.append("vertical_native_scroll_count=\(counters.verticalNativeScrollCount)")
            lines.append("vertical_fallback_scroll_count=\(counters.verticalFallbackScrollCount)")
            lines.append("horizontal_native_scroll_count=\(counters.horizontalNativeScrollCount)")
            lines.append("horizontal_fallback_scroll_count=\(counters.horizontalFallbackScrollCount)")
        }

        let data = Data(lines.joined(separator: "\n").appending("\n").utf8)
        summaryQueue.async { [summaryURL] in
            try? data.write(to: summaryURL, options: .atomic)
        }
    }

    private func scrollToken(ownerKey: String, axis: String, engine: String) -> String {
        "\(ownerKey)|\(axis)|\(engine)"
    }

    private func string(for direction: ScenarioWriterView.MainArrowDirection) -> String {
        switch direction {
        case .up: return "up"
        case .down: return "down"
        case .left: return "left"
        case .right: return "right"
        }
    }

    private func boolString(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private func cardIDString(_ id: UUID?) -> NSString {
        (id?.uuidString ?? "nil") as NSString
    }
}
