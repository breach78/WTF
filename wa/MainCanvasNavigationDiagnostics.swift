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

    struct Snapshot {
        let focusIntentCount: Int
        let repeatFocusIntentCount: Int
        let verticalNativeScrollCount: Int
        let verticalFallbackScrollCount: Int
        let horizontalNativeScrollCount: Int
        let horizontalFallbackScrollCount: Int
        let verificationRetryCount: Int
        let predictedNativeScrollCount: Int
        let predictedNativeScrollMissCount: Int
        let secondCorrectionCount: Int
        let horizontalOneStepScrollCount: Int
        let focusToFirstMotionAverageMilliseconds: Double
        let focusToFirstMotionAverageMillisecondsByTrigger: [String: Double]
        let focusToFirstMotionCountByTrigger: [String: Int]
    }

    struct OwnerCounters {
        var focusIntentCount: Int = 0
        var repeatFocusIntentCount: Int = 0
        var relationSyncStats = DurationStats()
        var layoutResolveStats = DurationStats()
        var layoutCacheMissCount: Int = 0
        var verticalNativeScrollCount: Int = 0
        var verticalFallbackScrollCount: Int = 0
        var horizontalNativeScrollCount: Int = 0
        var horizontalFallbackScrollCount: Int = 0
        var verificationRetryCount: Int = 0
        var predictedNativeScrollCount: Int = 0
        var predictedNativeScrollMissCount: Int = 0
        var secondCorrectionCount: Int = 0
        var horizontalOneStepScrollCount: Int = 0
        var focusToFirstMotionStats = DurationStats()
        var focusToFirstMotionStatsByTrigger: [String: DurationStats] = [:]

        mutating func recordFirstMotion(milliseconds: Double, trigger: String) {
            focusToFirstMotionStats.record(milliseconds)
            var triggerStats = focusToFirstMotionStatsByTrigger[trigger] ?? DurationStats()
            triggerStats.record(milliseconds)
            focusToFirstMotionStatsByTrigger[trigger] = triggerStats
        }
    }

    private struct PendingFocusIntent {
        let signpostID: OSSignpostID
        let startedAt: CFTimeInterval
        let trigger: String
        let isRepeat: Bool
        let sourceCardID: UUID?
        let intendedCardID: UUID?
        var firstMotionRecorded: Bool
    }

    private let log = OSLog(subsystem: "com.riwoong.wa", category: "MainCanvasNavigation")
    private var pendingFocusIntentByOwnerKey: [String: PendingFocusIntent] = [:]
    private var pendingScrollSignpostIDsByToken: [String: OSSignpostID] = [:]
    private var countersByOwnerKey: [String: OwnerCounters] = [:]
    private var lastSummaryByOwnerKey: [String: String] = [:]
#if DEBUG
    private var enabledOverrideForTesting: Bool?
#endif

    private init() {}

    private var isEnabled: Bool {
#if DEBUG
        if let enabledOverrideForTesting {
            return enabledOverrideForTesting
        }
        let environment = ProcessInfo.processInfo.environment
        return environment["WA_UI_TEST_MODE"] == "motion-kernel"
            || environment["WA_MAIN_CANVAS_DIAGNOSTICS"] == "1"
#else
        return false
#endif
    }

    func reset(ownerKey: String, scenarioID: UUID, splitPaneID: Int) {
        guard isEnabled else { return }
        pendingFocusIntentByOwnerKey.removeValue(forKey: ownerKey)
        countersByOwnerKey[ownerKey] = OwnerCounters()
        lastSummaryByOwnerKey.removeValue(forKey: ownerKey)
        os_signpost(
            .event,
            log: log,
            name: "DiagnosticsReset",
            "owner=%{public}@ scenario=%{public}@ pane=%{public}d",
            ownerKey as NSString,
            scenarioID.uuidString as NSString,
            splitPaneID
        )
    }

    func beginFocusIntent(
        ownerKey: String,
        direction: MainArrowDirection?,
        isRepeat: Bool,
        sourceCardID: UUID?,
        intendedCardID: UUID?
    ) {
        guard let direction else { return }
        beginFocusIntent(
            ownerKey: ownerKey,
            trigger: string(for: direction),
            isRepeat: isRepeat,
            sourceCardID: sourceCardID,
            intendedCardID: intendedCardID
        )
    }

    func beginFocusIntent(
        ownerKey: String,
        trigger: String,
        isRepeat: Bool,
        sourceCardID: UUID?,
        intendedCardID: UUID?
    ) {
        guard isEnabled else { return }

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
        os_signpost(
            .begin,
            log: log,
            name: "FocusIntent",
            signpostID: signpostID,
            "owner=%{public}@ trigger=%{public}@ repeat=%{public}@ from=%{public}@ to=%{public}@",
            ownerKey as NSString,
            trigger as NSString,
            boolString(isRepeat) as NSString,
            cardIDString(sourceCardID),
            cardIDString(intendedCardID)
        )
        pendingFocusIntentByOwnerKey[ownerKey] = PendingFocusIntent(
            signpostID: signpostID,
            startedAt: CACurrentMediaTime(),
            trigger: trigger,
            isRepeat: isRepeat,
            sourceCardID: sourceCardID,
            intendedCardID: intendedCardID,
            firstMotionRecorded: false
        )
    }

    func recordRelationSync(
        ownerKey: String,
        activeCardID: UUID?,
        durationMilliseconds: Double,
        ancestorCount: Int,
        siblingCount: Int,
        descendantCount: Int
    ) {
        guard isEnabled else { return }
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
                "owner=%{public}@ trigger=%{public}@ repeat=%{public}@ active=%{public}@ relation_ms=%{public}.2f total_ms=%{public}.2f",
                ownerKey as NSString,
                pending.trigger as NSString,
                boolString(pending.isRepeat) as NSString,
                cardIDString(activeCardID),
                durationMilliseconds,
                elapsed
            )
        }
    }

    func recordColumnLayoutResolve(
        ownerKey: String,
        cardCount: Int,
        viewportHeight: CGFloat,
        cacheHit: Bool,
        containsEditingCard: Bool,
        durationMilliseconds: Double
    ) {
        guard isEnabled else { return }
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
        expectedDuration: TimeInterval,
        predictedOnly: Bool = false,
        horizontalMode: MainCanvasHorizontalScrollMode? = nil
    ) {
        guard isEnabled else { return }
        let token = scrollToken(ownerKey: ownerKey, axis: axis, engine: engine)
        if let existingID = pendingScrollSignpostIDsByToken.removeValue(forKey: token) {
            os_signpost(
                .end,
                log: log,
                name: "ScrollAnimation",
                signpostID: existingID,
                "owner=%{public}@ axis=%{public}@ engine=%{public}@ status=replaced",
                ownerKey as NSString,
                axis as NSString,
                engine as NSString
            )
        }

        let signpostID = OSSignpostID(log: log)
        pendingScrollSignpostIDsByToken[token] = signpostID

        var counters = countersByOwnerKey[ownerKey] ?? OwnerCounters()
        switch (axis, engine) {
        case ("vertical", "native"):
            counters.verticalNativeScrollCount += 1
            if predictedOnly {
                counters.predictedNativeScrollCount += 1
            }
        case ("vertical", _):
            counters.verticalFallbackScrollCount += 1
        case ("horizontal", "native"):
            counters.horizontalNativeScrollCount += 1
        case ("horizontal", _):
            counters.horizontalFallbackScrollCount += 1
        default:
            break
        }
        if axis == "horizontal", horizontalMode == .oneStep {
            counters.horizontalOneStepScrollCount += 1
        }
        if var pending = pendingFocusIntentByOwnerKey[ownerKey], !pending.firstMotionRecorded {
            let elapsed = elapsedMilliseconds(since: pending.startedAt)
            counters.recordFirstMotion(milliseconds: elapsed, trigger: pending.trigger)
            pending.firstMotionRecorded = true
            pendingFocusIntentByOwnerKey[ownerKey] = pending
        }
        countersByOwnerKey[ownerKey] = counters

        os_signpost(
            .begin,
            log: log,
            name: "ScrollAnimation",
            signpostID: signpostID,
            "owner=%{public}@ axis=%{public}@ engine=%{public}@ animated=%{public}@ target=%{public}@ duration_ms=%{public}.2f predicted_only=%{public}@",
            ownerKey as NSString,
            axis as NSString,
            engine as NSString,
            boolString(animated) as NSString,
            target as NSString,
            expectedDuration * 1000,
            boolString(predictedOnly) as NSString
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
        guard isEnabled else { return }
        var counters = countersByOwnerKey[ownerKey] ?? OwnerCounters()
        counters.verificationRetryCount += 1
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
    }

    func recordPredictedNativeScrollMiss(ownerKey: String) {
        guard isEnabled else { return }
        var counters = countersByOwnerKey[ownerKey] ?? OwnerCounters()
        counters.predictedNativeScrollMissCount += 1
        countersByOwnerKey[ownerKey] = counters
    }

    func recordSecondCorrection(ownerKey: String) {
        guard isEnabled else { return }
        var counters = countersByOwnerKey[ownerKey] ?? OwnerCounters()
        counters.secondCorrectionCount += 1
        countersByOwnerKey[ownerKey] = counters
    }

    @discardableResult
    func emitSummary(
        ownerKey: String,
        reason: String,
        horizontalMode: MainCanvasHorizontalScrollMode? = nil
    ) -> String? {
        guard isEnabled else { return nil }
        guard let counters = countersByOwnerKey[ownerKey] else { return nil }
        let summary = summaryString(
            ownerKey: ownerKey,
            reason: reason,
            counters: counters,
            horizontalMode: horizontalMode
        )
        lastSummaryByOwnerKey[ownerKey] = summary

        os_log(
            "%{public}@",
            log: log,
            type: .info,
            summary as NSString
        )
        return summary
    }

    func snapshot(ownerKey: String) -> Snapshot? {
        guard let counters = countersByOwnerKey[ownerKey] else { return nil }
        return Snapshot(
            focusIntentCount: counters.focusIntentCount,
            repeatFocusIntentCount: counters.repeatFocusIntentCount,
            verticalNativeScrollCount: counters.verticalNativeScrollCount,
            verticalFallbackScrollCount: counters.verticalFallbackScrollCount,
            horizontalNativeScrollCount: counters.horizontalNativeScrollCount,
            horizontalFallbackScrollCount: counters.horizontalFallbackScrollCount,
            verificationRetryCount: counters.verificationRetryCount,
            predictedNativeScrollCount: counters.predictedNativeScrollCount,
            predictedNativeScrollMissCount: counters.predictedNativeScrollMissCount,
            secondCorrectionCount: counters.secondCorrectionCount,
            horizontalOneStepScrollCount: counters.horizontalOneStepScrollCount,
            focusToFirstMotionAverageMilliseconds: counters.focusToFirstMotionStats.averageMilliseconds,
            focusToFirstMotionAverageMillisecondsByTrigger: counters.focusToFirstMotionStatsByTrigger.mapValues(\.averageMilliseconds),
            focusToFirstMotionCountByTrigger: counters.focusToFirstMotionStatsByTrigger.mapValues(\.count)
        )
    }

    func latestSummary(ownerKey: String) -> String? {
        lastSummaryByOwnerKey[ownerKey]
    }

#if DEBUG
    func setEnabledForTesting(_ enabled: Bool?) {
        enabledOverrideForTesting = enabled
    }
#endif

    private func endScrollAnimation(ownerKey: String, axis: String, engine: String, status: String) {
        guard isEnabled else { return }
        let token = scrollToken(ownerKey: ownerKey, axis: axis, engine: engine)
        guard let signpostID = pendingScrollSignpostIDsByToken.removeValue(forKey: token) else { return }
        os_signpost(
            .end,
            log: log,
            name: "ScrollAnimation",
            signpostID: signpostID,
            "owner=%{public}@ axis=%{public}@ engine=%{public}@ status=%{public}@",
            ownerKey as NSString,
            axis as NSString,
            engine as NSString,
            status as NSString
        )
    }

    private func summaryString(
        ownerKey: String,
        reason: String,
        counters: OwnerCounters,
        horizontalMode: MainCanvasHorizontalScrollMode?
    ) -> String {
        let triggerSummary = counters.focusToFirstMotionStatsByTrigger
            .keys
            .sorted()
            .map { trigger in
                let stats = counters.focusToFirstMotionStatsByTrigger[trigger] ?? DurationStats()
                return "\(trigger)=\(String(format: "%.2f", stats.averageMilliseconds))ms/\(stats.count)"
            }
            .joined(separator: ",")

        return
            "summary owner=\(ownerKey) reason=\(reason) " +
            "focus=\(counters.focusIntentCount) repeat=\(counters.repeatFocusIntentCount) " +
            "relation_avg_ms=\(String(format: "%.2f", counters.relationSyncStats.averageMilliseconds)) " +
            "relation_max_ms=\(String(format: "%.2f", counters.relationSyncStats.maxMilliseconds)) " +
            "layout_avg_ms=\(String(format: "%.2f", counters.layoutResolveStats.averageMilliseconds)) " +
            "layout_max_ms=\(String(format: "%.2f", counters.layoutResolveStats.maxMilliseconds)) " +
            "layout_miss=\(counters.layoutCacheMissCount) " +
            "v_native=\(counters.verticalNativeScrollCount) " +
            "v_fallback=\(counters.verticalFallbackScrollCount) " +
            "predicted_native=\(counters.predictedNativeScrollCount) " +
            "predicted_miss=\(counters.predictedNativeScrollMissCount) " +
            "h_native=\(counters.horizontalNativeScrollCount) " +
            "h_fallback=\(counters.horizontalFallbackScrollCount) " +
            "horizontal_one_step=\(counters.horizontalOneStepScrollCount) " +
            "retries=\(counters.verificationRetryCount) " +
            "second_correction=\(counters.secondCorrectionCount) " +
            "first_motion_ms=\(String(format: "%.2f", counters.focusToFirstMotionStats.averageMilliseconds)) " +
            "first_motion_by_trigger=[\(triggerSummary)] " +
            "horizontal-mode=\(horizontalModeLabel(horizontalMode))"
    }

    private func horizontalModeLabel(_ mode: MainCanvasHorizontalScrollMode?) -> String {
        switch mode {
        case .oneStep:
            return "oneStep"
        case .twoStep:
            return "twoStep"
        case nil:
            return "unknown"
        }
    }

    private func elapsedMilliseconds(since startedAt: CFTimeInterval) -> Double {
        (CACurrentMediaTime() - startedAt) * 1000
    }

    private func scrollToken(ownerKey: String, axis: String, engine: String) -> String {
        "\(ownerKey)|\(axis)|\(engine)"
    }

    private func string(for direction: MainArrowDirection) -> String {
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
