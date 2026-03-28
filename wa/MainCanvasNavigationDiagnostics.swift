import Foundation
import QuartzCore
import os

@MainActor
final class MainCanvasNavigationDiagnostics {
    static let shared = MainCanvasNavigationDiagnostics()
    private let isEnabled = false

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
        var relationSyncStats = DurationStats()
        var layoutResolveStats = DurationStats()
        var layoutCacheMissCount: Int = 0
        var verticalNativeScrollCount: Int = 0
        var verticalFallbackScrollCount: Int = 0
        var horizontalNativeScrollCount: Int = 0
        var horizontalFallbackScrollCount: Int = 0
        var verificationRetryCount: Int = 0
    }

    private struct PendingFocusIntent {
        let signpostID: OSSignpostID
        let startedAt: CFTimeInterval
        let direction: String
        let isRepeat: Bool
        let sourceCardID: UUID?
        let intendedCardID: UUID?
    }

    private let log = OSLog(subsystem: "com.riwoong.wa", category: "MainCanvasNavigation")
    private var pendingFocusIntentByOwnerKey: [String: PendingFocusIntent] = [:]
    private var pendingScrollSignpostIDsByToken: [String: OSSignpostID] = [:]
    private var countersByOwnerKey: [String: OwnerCounters] = [:]

    private init() {}

    func reset(ownerKey: String, scenarioID: UUID, splitPaneID: Int) {
        guard isEnabled else { return }
        pendingFocusIntentByOwnerKey.removeValue(forKey: ownerKey)
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
    }

    func beginFocusIntent(
        ownerKey: String,
        direction: ScenarioWriterView.MainArrowDirection?,
        isRepeat: Bool,
        sourceCardID: UUID?,
        intendedCardID: UUID?
    ) {
        guard isEnabled else { return }
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
                "owner=%{public}@ direction=%{public}@ repeat=%{public}@ active=%{public}@ relation_ms=%{public}.2f total_ms=%{public}.2f",
                ownerKey as NSString,
                pending.direction as NSString,
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
        expectedDuration: TimeInterval
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

    func emitSummary(ownerKey: String, reason: String) {
        guard isEnabled else { return }
        guard let counters = countersByOwnerKey[ownerKey] else { return }

        os_log(
            "summary owner=%{public}@ reason=%{public}@ focus=%{public}d repeat=%{public}d relation_avg_ms=%{public}.2f relation_max_ms=%{public}.2f layout_avg_ms=%{public}.2f layout_max_ms=%{public}.2f layout_miss=%{public}d v_native=%{public}d v_fallback=%{public}d h_native=%{public}d h_fallback=%{public}d retries=%{public}d",
            log: log,
            type: .info,
            ownerKey as NSString,
            reason as NSString,
            counters.focusIntentCount,
            counters.repeatFocusIntentCount,
            counters.relationSyncStats.averageMilliseconds,
            counters.relationSyncStats.maxMilliseconds,
            counters.layoutResolveStats.averageMilliseconds,
            counters.layoutResolveStats.maxMilliseconds,
            counters.layoutCacheMissCount,
            counters.verticalNativeScrollCount,
            counters.verticalFallbackScrollCount,
            counters.horizontalNativeScrollCount,
            counters.horizontalFallbackScrollCount,
            counters.verificationRetryCount
        )
    }

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

    private func elapsedMilliseconds(since startedAt: CFTimeInterval) -> Double {
        (CACurrentMediaTime() - startedAt) * 1000
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
