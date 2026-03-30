import AppKit
import Combine
import Foundation
import SwiftUI

enum MainWorkspaceColumnAnchorMode: Equatable {
    case clampedCenter(chromeInset: CGFloat)
    case keepVisible(editingRevealEdge: MainEditingViewportRevealEdge?)
}

enum MainWorkspaceColumnPolicy: Equatable {
    case centerActive(cardID: UUID)
    case centerAncestor(cardID: UUID)
    case centerPreferredDescendant(cardID: UUID)
    case centerOtherDescendant(cardID: UUID)
    case between(afterID: UUID, beforeID: UUID)
    case before(cardID: UUID)
    case after(cardID: UUID)
    case none

    var primaryCardID: UUID? {
        switch self {
        case .centerActive(let cardID),
            .centerAncestor(let cardID),
            .centerPreferredDescendant(let cardID),
            .centerOtherDescendant(let cardID),
            .before(let cardID),
            .after(let cardID):
            return cardID
        case .between, .none:
            return nil
        }
    }

    var debugSummary: String {
        switch self {
        case .centerActive(let cardID):
            return "centerActive:\(cardID.uuidString)"
        case .centerAncestor(let cardID):
            return "centerAncestor:\(cardID.uuidString)"
        case .centerPreferredDescendant(let cardID):
            return "centerPreferredDescendant:\(cardID.uuidString)"
        case .centerOtherDescendant(let cardID):
            return "centerOtherDescendant:\(cardID.uuidString)"
        case .between(let afterID, let beforeID):
            return "between:\(afterID.uuidString):\(beforeID.uuidString)"
        case .before(let cardID):
            return "before:\(cardID.uuidString)"
        case .after(let cardID):
            return "after:\(cardID.uuidString)"
        case .none:
            return "none"
        }
    }
}

struct MainWorkspaceColumnPlan: Equatable {
    let level: Int
    let viewportKey: String
    let policy: MainWorkspaceColumnPolicy
    let anchorMode: MainWorkspaceColumnAnchorMode
    let keepVisibleOnly: Bool
    let forceAlignment: Bool
    let authorityKind: MainVerticalScrollAuthorityKind

    var primaryCardID: UUID? {
        policy.primaryCardID
    }

    var focusDelay: TimeInterval {
        0
    }
}

struct MainWorkspaceScrollPlan: Equatable {
    var generation: Int = 0
    let activeCardID: UUID
    let trigger: String
    let animated: Bool
    let horizontalTargetLevel: Int
    let horizontalTargetX: CGFloat
    let columnPlans: [MainWorkspaceColumnPlan]

    func columnPlan(for viewportKey: String) -> MainWorkspaceColumnPlan? {
        columnPlans.first { $0.viewportKey == viewportKey }
    }
}

private struct MainWorkspaceVisibleDescendantSelection {
    let cardID: UUID
    let isPreferred: Bool
    let path: [UUID]
    let source: MainWorkspaceNavigationModel.PreferredNavigationChildSource
}

extension ScenarioWriterView {
    func publishActiveMainWorkspaceScrollPlan(
        activeID: UUID,
        availableWidth: CGFloat,
        animated: Bool,
        trigger: String
    ) -> MainWorkspaceScrollPlan? {
        guard let plan = buildMainWorkspaceScrollPlan(
            activeID: activeID,
            availableWidth: availableWidth,
            animated: animated,
            trigger: trigger
        ) else {
            return nil
        }
        publishMainWorkspaceScrollPlan(plan)
        guard let publishedPlan = mainWorkspaceScrollPlan else { return nil }
        indexBoardRestoreTrace(
            "main_workspace_scroll_plan_publish",
            "generation=\(publishedPlan.generation) trigger=\(trigger) animated=\(animated) " +
            "active=\(debugRestoreUUID(activeID)) targetLevel=\(publishedPlan.horizontalTargetLevel) " +
            "targetX=\(debugRestoreCGFloat(publishedPlan.horizontalTargetX)) " +
            "columns=\(publishedPlan.columnPlans.count)"
        )
        mainWorkspacePhase0Log(
            "scroll-plan",
            "generation=\(publishedPlan.generation) trigger=\(trigger) active=\(mainWorkspacePhase0CardID(activeID)) " +
            "animated=\(animated) targetLevel=\(publishedPlan.horizontalTargetLevel) " +
            "targetX=\(publishedPlan.horizontalTargetX) policies=\(publishedPlan.columnPlans.map { $0.policy.debugSummary }.joined(separator: ","))"
        )
        return publishedPlan
    }

    func buildMainWorkspaceScrollPlan(
        activeID: UUID,
        availableWidth: CGFloat,
        animated: Bool,
        trigger: String
    ) -> MainWorkspaceScrollPlan? {
        guard !showFocusMode else { return nil }
        guard acceptsKeyboardInput else { return nil }
        let levelsData = resolvedDisplayedMainLevelsWithParents()
        let levels = levelsData.map(\.cards)
        guard let activeCard = findCard(by: activeID),
              let activeLocation = displayedMainCardLocationByID(activeID, in: levels) else {
            return nil
        }

        let visibleWidth =
            mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalScrollView()?.documentVisibleRect.width ??
            max(1, availableWidth)
        let horizontalTargetLevel = resolvedMainWorkspaceHorizontalTargetLevel(for: activeLocation.level)
        let horizontalTargetX = resolvedMainCanvasHorizontalTargetX(
            level: horizontalTargetLevel,
            availableWidth: max(1, availableWidth),
            visibleWidth: max(1, visibleWidth)
        )
        return MainWorkspaceScrollPlan(
            activeCardID: activeID,
            trigger: trigger,
            animated: animated,
            horizontalTargetLevel: horizontalTargetLevel,
            horizontalTargetX: horizontalTargetX,
            columnPlans: resolvedMainWorkspaceColumnPlans(
                levelsData: levelsData,
                activeCard: activeCard,
                activeLevel: activeLocation.level,
                trigger: trigger
            )
        )
    }

    func executeMainWorkspaceScrollPlan(
        _ plan: MainWorkspaceScrollPlan,
        proxy: ScrollViewProxy? = nil,
        availableWidth: CGFloat
    ) {
        guard activeCardID == plan.activeCardID else { return }
        mainWorkspaceScrollDriver.begin(plan: plan)
        applyMainWorkspaceScrollPlan(
            plan,
            proxy: proxy,
            availableWidth: availableWidth,
            allowDeferredRetry: true,
            isVerifyPass: false
        )
    }

    private func applyMainWorkspaceScrollPlan(
        _ plan: MainWorkspaceScrollPlan,
        proxy: ScrollViewProxy?,
        availableWidth: CGFloat,
        allowDeferredRetry: Bool,
        isVerifyPass: Bool
    ) {
        guard mainWorkspaceScrollDriver.isCurrent(plan) else { return }
        let levelsData = resolvedDisplayedMainLevelsWithParents()
        guard prepareMainWorkspaceScrollExecutionLayout(
            plan: plan,
            levelsData: levelsData
        ) else {
            if allowDeferredRetry {
                mainWorkspacePhase0Log(
                    "scroll-executor-deferred",
                    "generation=\(plan.generation) active=\(mainWorkspacePhase0CardID(plan.activeCardID))"
                )
                mainWorkspaceScrollDriver.scheduleDeferredApply(for: plan) {
                    applyMainWorkspaceScrollPlan(
                        plan,
                        proxy: proxy,
                        availableWidth: availableWidth,
                        allowDeferredRetry: false,
                        isVerifyPass: isVerifyPass
                    )
                }
            } else {
                mainWorkspacePhase0Log(
                    "scroll-executor-give-up",
                    "generation=\(plan.generation) active=\(mainWorkspacePhase0CardID(plan.activeCardID))"
                )
            }
            return
        }
        let hasPendingMissingColumns = mainWorkspaceScrollDriver.hasPendingMissingViewportKeys(for: plan)

        cancelMainWorkspaceScrollAnimations(for: plan)
        lastScrolledLevel = plan.horizontalTargetLevel

        let appliedHorizontal = applyMainWorkspaceHorizontalScrollPlan(
            plan,
            proxy: proxy,
            availableWidth: availableWidth
        )
        let appliedVertical = applyMainWorkspaceColumnPlans(
            plan: plan,
            levelsData: levelsData
        )

        mainWorkspacePhase0Log(
            "scroll-executor-apply",
            "generation=\(plan.generation) active=\(mainWorkspacePhase0CardID(plan.activeCardID)) " +
            "horizontal=\(appliedHorizontal) vertical=\(appliedVertical) verifyPass=\(isVerifyPass)"
        )
        MainCanvasNavigationDiagnostics.shared.recordScrollApply(
            ownerKey: mainCanvasDiagnosticsOwnerKey,
            generation: plan.generation,
            activeCardID: plan.activeCardID,
            appliedHorizontal: appliedHorizontal,
            appliedVertical: appliedVertical,
            isVerifyPass: isVerifyPass
        )

        if isVerifyPass {
            logMainWorkspaceScrollPlanVerification(plan: plan, levelsData: levelsData)
            return
        }
        mainWorkspaceScrollDriver.scheduleSingleVerify(
            for: plan,
            delay: resolvedMainWorkspaceScrollVerifyDelay(
                animated: plan.animated,
                waitingForColumns: hasPendingMissingColumns
            )
        ) {
            applyMainWorkspaceScrollPlan(
                plan,
                proxy: proxy,
                availableWidth: availableWidth,
                allowDeferredRetry: false,
                isVerifyPass: true
            )
        }
    }

    private func prepareMainWorkspaceScrollExecutionLayout(
        plan: MainWorkspaceScrollPlan,
        levelsData: [LevelData]
    ) -> Bool {
        if let horizontalScrollView = mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalScrollView() {
            if !shouldUseMainWorkspaceSurface {
                MainCanvasNavigationDiagnostics.shared.recordLayoutSubtreeIfNeeded(
                    ownerKey: mainCanvasDiagnosticsOwnerKey,
                    callsite: .horizontalDocumentView
                )
                horizontalScrollView.documentView?.layoutSubtreeIfNeeded()
                MainCanvasNavigationDiagnostics.shared.recordLayoutSubtreeIfNeeded(
                    ownerKey: mainCanvasDiagnosticsOwnerKey,
                    callsite: .horizontalContentSuperview
                )
                horizontalScrollView.contentView.superview?.layoutSubtreeIfNeeded()
                MainCanvasNavigationDiagnostics.shared.recordLayoutSubtreeIfNeeded(
                    ownerKey: mainCanvasDiagnosticsOwnerKey,
                    callsite: .horizontalScrollView
                )
                horizontalScrollView.layoutSubtreeIfNeeded()
            }
        } else {
            mainWorkspacePhase0Log(
                "scroll-executor-missing-horizontal",
                "generation=\(plan.generation) active=\(mainWorkspacePhase0CardID(plan.activeCardID))"
            )
            if shouldUseMainWorkspaceSurface {
                mainWorkspaceScrollDriver.setPendingMissingViewportKeys(["__horizontal__"], for: plan)
                return false
            }
        }

        var missingViewportKeys: [String] = []
        for columnPlan in plan.columnPlans where columnPlan.policy != .none {
            guard levelsData.indices.contains(columnPlan.level) else { continue }
            if levelsData[columnPlan.level].cards.isEmpty {
                continue
            }
            guard let scrollView = mainCanvasScrollCoordinator.scrollView(for: columnPlan.viewportKey) else {
                missingViewportKeys.append(columnPlan.viewportKey)
                continue
            }
            if !shouldUseMainWorkspaceSurface {
                MainCanvasNavigationDiagnostics.shared.recordLayoutSubtreeIfNeeded(
                    ownerKey: mainCanvasDiagnosticsOwnerKey,
                    callsite: .columnDocumentView
                )
                scrollView.documentView?.layoutSubtreeIfNeeded()
                MainCanvasNavigationDiagnostics.shared.recordLayoutSubtreeIfNeeded(
                    ownerKey: mainCanvasDiagnosticsOwnerKey,
                    callsite: .columnContentSuperview
                )
                scrollView.contentView.superview?.layoutSubtreeIfNeeded()
                MainCanvasNavigationDiagnostics.shared.recordLayoutSubtreeIfNeeded(
                    ownerKey: mainCanvasDiagnosticsOwnerKey,
                    callsite: .columnScrollView
                )
                scrollView.layoutSubtreeIfNeeded()
            }
        }

        if !shouldUseMainWorkspaceSurface,
           let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            MainCanvasNavigationDiagnostics.shared.recordLayoutSubtreeIfNeeded(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                callsite: .activeEditorTextView
            )
            textView.layoutSubtreeIfNeeded()
        }

        if !shouldUseMainWorkspaceSurface {
            MainCanvasNavigationDiagnostics.shared.recordLayoutSubtreeIfNeeded(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                callsite: .keyWindowContentView
            )
            NSApp.keyWindow?.contentView?.layoutSubtreeIfNeeded()
        }
        if !missingViewportKeys.isEmpty {
            mainWorkspacePhase0Log(
                "scroll-executor-missing-columns",
                "generation=\(plan.generation) active=\(mainWorkspacePhase0CardID(plan.activeCardID)) " +
                "keys=\(missingViewportKeys.joined(separator: ","))"
            )
        }
        mainWorkspaceScrollDriver.setPendingMissingViewportKeys(missingViewportKeys, for: plan)
        if shouldUseMainWorkspaceSurface, !missingViewportKeys.isEmpty {
            return false
        }
        return true
    }

    private func cancelMainWorkspaceScrollAnimations(for plan: MainWorkspaceScrollPlan) {
        func cancelAnimations(in scrollView: NSScrollView?) {
            guard let scrollView else { return }
            scrollView.contentView.layer?.removeAllAnimations()
            scrollView.documentView?.layer?.removeAllAnimations()
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        cancelAnimations(in: mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalScrollView())
        for columnPlan in plan.columnPlans where columnPlan.policy != .none {
            cancelAnimations(in: mainCanvasScrollCoordinator.scrollView(for: columnPlan.viewportKey))
        }
    }

    private func applyMainWorkspaceColumnPlans(
        plan: MainWorkspaceScrollPlan,
        levelsData: [LevelData]
    ) -> Bool {
        var applied = false
        let consumesKeepVisibleState = plan.columnPlans.contains { columnPlan in
            columnPlan.keepVisibleOnly && columnPlan.primaryCardID == plan.activeCardID
        }
        for columnPlan in plan.columnPlans {
            guard levelsData.indices.contains(columnPlan.level) else { continue }
            let data = levelsData[columnPlan.level]
            guard !data.cards.isEmpty else { continue }
            guard columnPlan.policy != .none else { continue }
            let didApply = applyMainWorkspaceColumnPlanImmediately(
                plan: plan,
                columnPlan: columnPlan,
                cards: data.cards,
                viewportHeight: max(
                    1,
                    mainCanvasScrollCoordinator.scrollView(for: columnPlan.viewportKey)?.documentVisibleRect.height ?? 1
                )
            )
            applied = applied || didApply
        }
        if shouldUseMainWorkspaceSurface, consumesKeepVisibleState {
            pendingMainEditingViewportKeepVisibleCardID = nil
            pendingMainEditingViewportRevealEdge = nil
        }
        return applied
    }

    @discardableResult
    private func applyMainWorkspaceColumnPlanImmediately(
        plan: MainWorkspaceScrollPlan,
        columnPlan: MainWorkspaceColumnPlan,
        cards: [SceneCard],
        viewportHeight: CGFloat
    ) -> Bool {
        let authority = beginMainVerticalScrollAuthority(
            viewportKey: columnPlan.viewportKey,
            kind: columnPlan.authorityKind,
            targetCardID: columnPlan.primaryCardID ?? plan.activeCardID
        )
        guard isMainVerticalScrollAuthorityCurrent(authority, viewportKey: columnPlan.viewportKey) else {
            mainWorkspacePhase0Log(
                "column-plan-apply-skip",
                "generation=\(plan.generation) viewport=\(columnPlan.viewportKey) policy=\(columnPlan.policy.debugSummary) " +
                "reason=staleAuthority authority=\(authority.id)"
            )
            return false
        }
        guard let scrollView = mainCanvasScrollCoordinator.scrollView(for: columnPlan.viewportKey) else {
            mainWorkspacePhase0Log(
                "column-plan-apply-skip",
                "generation=\(plan.generation) viewport=\(columnPlan.viewportKey) policy=\(columnPlan.policy.debugSummary) " +
                "reason=missingScrollView"
            )
            return false
        }
        let visibleRect = scrollView.documentVisibleRect
        let resolvedViewportHeight = max(1, visibleRect.height > 0 ? visibleRect.height : viewportHeight)
        guard let targetOffsetY = resolvedMainWorkspaceColumnPlanTargetOffset(
            viewportKey: columnPlan.viewportKey,
            cards: cards,
            viewportHeight: resolvedViewportHeight,
            columnPlan: columnPlan
        ) else {
            mainWorkspacePhase0Log(
                "column-plan-apply-skip",
                "generation=\(plan.generation) viewport=\(columnPlan.viewportKey) policy=\(columnPlan.policy.debugSummary) " +
                "reason=missingTargetOffset primary=\(mainWorkspacePhase0CardID(columnPlan.primaryCardID))"
            )
            return false
        }

        let documentHeight = resolvedMainWorkspaceColumnDocumentHeight(
            viewportKey: columnPlan.viewportKey,
            cards: cards,
            viewportHeight: resolvedViewportHeight,
            scrollView: scrollView
        )
        let maxY = max(0, documentHeight - visibleRect.height)
        if plan.animated {
            let resolvedTargetY = CaretScrollCoordinator.resolvedVerticalTargetY(
                visibleRect: visibleRect,
                targetY: targetOffsetY,
                minY: 0,
                maxY: maxY,
                snapToPixel: true
            )
            guard abs(resolvedTargetY - visibleRect.origin.y) > 0.5 else {
                mainWorkspacePhase0Log(
                    "column-plan-apply-skip",
                    "generation=\(plan.generation) viewport=\(columnPlan.viewportKey) policy=\(columnPlan.policy.debugSummary) " +
                    "reason=alreadyAtTarget currentY=\(visibleRect.origin.y) targetY=\(resolvedTargetY)"
                )
                return false
            }
            let duration = CaretScrollCoordinator.resolvedVerticalAnimationDuration(
                currentY: visibleRect.origin.y,
                targetY: resolvedTargetY,
                viewportHeight: resolvedViewportHeight
            )
            suspendMainColumnViewportCapture(for: duration + 0.06)
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                axis: "vertical",
                engine: "native",
                animated: true,
                target: "\(columnPlan.viewportKey)|\(columnPlan.policy.debugSummary)",
                expectedDuration: duration
            )
            _ = CaretScrollCoordinator.applyAnimatedVerticalScrollIfNeeded(
                scrollView: scrollView,
                visibleRect: visibleRect,
                targetY: targetOffsetY,
                minY: 0,
                maxY: maxY,
                deadZone: 0.5,
                snapToPixel: true,
                duration: duration
            )
            return true
        }

        suspendMainColumnViewportCapture(for: 0.12)
        MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
            ownerKey: mainCanvasDiagnosticsOwnerKey,
            axis: "vertical",
            engine: "native",
            animated: false,
            target: "\(columnPlan.viewportKey)|\(columnPlan.policy.debugSummary)",
            expectedDuration: 0
        )
        return CaretScrollCoordinator.applyVerticalScrollIfNeeded(
            scrollView: scrollView,
            visibleRect: visibleRect,
            targetY: targetOffsetY,
            minY: 0,
            maxY: maxY,
            deadZone: 0.5,
            snapToPixel: true
        )
    }

    private func resolvedMainWorkspaceScrollVerifyDelay(
        animated: Bool,
        waitingForColumns: Bool
    ) -> TimeInterval {
        if waitingForColumns {
            return animated ? 0.47 : 0.12
        }
        return animated ? 0.32 : 0.06
    }

    @discardableResult
    func applyMainWorkspaceHorizontalScrollPlan(
        _ plan: MainWorkspaceScrollPlan,
        proxy: ScrollViewProxy?,
        availableWidth: CGFloat
    ) -> Bool {
        guard activeCardID == plan.activeCardID else { return false }
        lastScrolledLevel = plan.horizontalTargetLevel
        indexBoardRestoreTrace(
            "main_workspace_scroll_plan_apply_horizontal",
            "generation=\(plan.generation) active=\(debugRestoreUUID(plan.activeCardID)) " +
            "targetLevel=\(plan.horizontalTargetLevel) targetX=\(debugRestoreCGFloat(plan.horizontalTargetX)) " +
            "animated=\(plan.animated)"
        )
        if performMainCanvasHorizontalScroll(
            level: plan.horizontalTargetLevel,
            targetX: plan.horizontalTargetX,
            animated: plan.animated
        ) {
            return true
        }

        if shouldUseMainWorkspaceSurface {
            return false
        }
        guard let proxy else { return false }
        let hAnchor = resolvedMainCanvasHorizontalAnchor(availableWidth: max(1, availableWidth))
        if plan.animated {
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                axis: "horizontal",
                engine: "proxy",
                animated: true,
                target: "plan-level:\(plan.horizontalTargetLevel)",
                expectedDuration: 0.24
            )
            withAnimation(quickEaseAnimation) {
                proxy.scrollTo(plan.horizontalTargetLevel, anchor: hAnchor)
            }
        } else {
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                axis: "horizontal",
                engine: "proxy",
                animated: false,
                target: "plan-level:\(plan.horizontalTargetLevel)",
                expectedDuration: 0
            )
            performWithoutAnimation {
                proxy.scrollTo(plan.horizontalTargetLevel, anchor: hAnchor)
            }
        }
        return true
    }

    @discardableResult
    func performMainCanvasHorizontalScroll(
        level: Int,
        targetX: CGFloat,
        animated: Bool
    ) -> Bool {
        guard let scrollView = mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalScrollView() else {
            indexBoardRestoreTrace(
                "main_canvas_perform_horizontal_scroll_skip",
                "level=\(level) reason=noScrollView animated=\(animated) targetX=\(debugRestoreCGFloat(targetX))"
            )
            return false
        }

        let visibleRect = scrollView.documentVisibleRect
        let documentWidth = scrollView.documentView?.bounds.width ?? 0
        let maxX = max(0, documentWidth - visibleRect.width)
        let targetReachable = maxX + 0.5 >= targetX
        indexBoardRestoreTrace(
            "main_canvas_perform_horizontal_scroll_begin",
            "level=\(level) animated=\(animated) currentX=\(debugRestoreCGFloat(visibleRect.origin.x)) " +
            "targetX=\(debugRestoreCGFloat(targetX)) maxX=\(String(format: "%.2f", maxX)) targetReachable=\(targetReachable)"
        )

        if animated {
            guard targetReachable || targetX <= 0.5 else { return false }
            let resolvedTargetX = CaretScrollCoordinator.resolvedHorizontalTargetX(
                visibleRect: visibleRect,
                targetX: targetX,
                minX: 0,
                maxX: maxX,
                snapToPixel: true
            )
            guard abs(resolvedTargetX - visibleRect.origin.x) > 0.5 else { return true }
            let appliedDuration = CaretScrollCoordinator.resolvedHorizontalAnimationDuration(
                currentX: visibleRect.origin.x,
                targetX: resolvedTargetX,
                viewportWidth: visibleRect.width
            )
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                axis: "horizontal",
                engine: "native",
                animated: true,
                target: "level:\(level)",
                expectedDuration: appliedDuration
            )
            _ = CaretScrollCoordinator.applyAnimatedHorizontalScrollIfNeeded(
                scrollView: scrollView,
                visibleRect: visibleRect,
                targetX: targetX,
                minX: 0,
                maxX: maxX,
                deadZone: 0.5,
                snapToPixel: true,
                duration: appliedDuration
            )
            return true
        }

        MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
            ownerKey: mainCanvasDiagnosticsOwnerKey,
            axis: "horizontal",
            engine: "native",
            animated: false,
            target: "level:\(level)",
            expectedDuration: 0
        )
        let applied = CaretScrollCoordinator.applyHorizontalScrollIfNeeded(
            scrollView: scrollView,
            visibleRect: visibleRect,
            targetX: targetX,
            minX: 0,
            maxX: maxX,
            deadZone: 0.5,
            snapToPixel: true
        )
        if applied {
            bounceDebugLog(
                "nativeMainCanvasHorizontalScroll plan level=\(level) targetX=\(debugCGFloat(targetX)) visibleX=\(debugCGFloat(visibleRect.origin.x))"
            )
        }
        let resolvedTargetX = CaretScrollCoordinator.resolvedHorizontalTargetX(
            visibleRect: visibleRect,
            targetX: targetX,
            minX: 0,
            maxX: maxX,
            snapToPixel: true
        )
        let currentX = scrollView.contentView.bounds.origin.x
        return targetReachable && abs(resolvedTargetX - currentX) <= 0.5
    }

    func handleMainWorkspaceScrollPlan(
        viewportKey: String,
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat
    ) {
        guard !shouldUseMainWorkspaceSurface else { return }
        guard !showFocusMode else { return }
        guard acceptsKeyboardInput else { return }
        guard let plan = mainWorkspaceScrollPlan else { return }
        guard plan.activeCardID == activeCardID else { return }
        guard let columnPlan = plan.columnPlan(for: viewportKey) else { return }
        guard columnPlan.policy != .none else { return }
        if editingCardID != nil && columnPlan.authorityKind != .editingTransition {
            return
        }
        if columnPlan.keepVisibleOnly,
           pendingMainEditingViewportKeepVisibleCardID == plan.activeCardID {
            pendingMainEditingViewportKeepVisibleCardID = nil
            pendingMainEditingViewportRevealEdge = nil
        }
        cancelPendingMainColumnFocusWorkItem(for: viewportKey)
        cancelPendingMainColumnFocusVerificationWorkItem(for: viewportKey)
        let authority = beginMainVerticalScrollAuthority(
            viewportKey: viewportKey,
            kind: columnPlan.authorityKind,
            targetCardID: columnPlan.primaryCardID ?? plan.activeCardID
        )
        bounceDebugLog(
            "mainWorkspaceScrollPlan level=\(level) viewportKey=\(viewportKey) generation=\(plan.generation) " +
            "policy=\(columnPlan.policy.debugSummary) keepVisible=\(columnPlan.keepVisibleOnly) " +
            "force=\(columnPlan.forceAlignment) animated=\(plan.animated) trigger=\(plan.trigger)"
        )
        scheduleMainWorkspaceColumnPlanFocus(
            viewportKey: viewportKey,
            cards: cards,
            level: level,
            parent: parent,
            proxy: proxy,
            viewportHeight: viewportHeight,
            plan: plan,
            columnPlan: columnPlan,
            authority: authority
        )
    }

    private func resolvedMainWorkspaceHorizontalTargetLevel(for activeLevel: Int) -> Int {
        activeLevel
    }

    private func resolvedMainWorkspaceColumnPlans(
        levelsData: [LevelData],
        activeCard: SceneCard,
        activeLevel: Int,
        trigger: String
    ) -> [MainWorkspaceColumnPlan] {
        let preorderIndexByCardID = mainWorkspacePreorderIndexByCardID()
        let isEditingBoundaryTransition =
            editingCardID == activeCard.id &&
            (
                pendingMainEditingBoundaryNavigationTargetID == activeCard.id ||
                pendingMainEditingSiblingNavigationTargetID == activeCard.id
            )
        return levelsData.enumerated().map { level, data in
            let cards = data.cards
            let viewportKey = mainColumnViewportStorageKey(level: level, cards: cards)
            let keepVisibleOnly =
                pendingMainEditingViewportKeepVisibleCardID == activeCard.id &&
                cards.contains(where: { $0.id == activeCard.id })
            let policy = resolvedMainWorkspaceColumnPolicy(
                in: cards,
                level: level,
                activeLevel: activeLevel,
                activeCard: activeCard,
                preorderIndexByCardID: preorderIndexByCardID
            )
            let anchorMode: MainWorkspaceColumnAnchorMode
            if keepVisibleOnly {
                anchorMode = .keepVisible(editingRevealEdge: pendingMainEditingViewportRevealEdge)
            } else {
                anchorMode = .clampedCenter(chromeInset: 51)
            }
            return MainWorkspaceColumnPlan(
                level: level,
                viewportKey: viewportKey,
                policy: policy,
                anchorMode: anchorMode,
                keepVisibleOnly: keepVisibleOnly,
                forceAlignment: trigger == "clickFocus",
                authorityKind: (keepVisibleOnly || isEditingBoundaryTransition) ? .editingTransition : .columnNavigation
            )
        }
    }

    private func resolvedMainWorkspaceColumnPolicy(
        in cards: [SceneCard],
        level: Int,
        activeLevel: Int,
        activeCard: SceneCard,
        preorderIndexByCardID: [UUID: Int]
    ) -> MainWorkspaceColumnPolicy {
        guard !cards.isEmpty else { return .none }
        _ = level
        _ = activeLevel
        if cards.contains(where: { $0.id == activeCard.id }) {
            return .centerActive(cardID: activeCard.id)
        }
        if let ancestor = cards.first(where: { activeAncestorIDs.contains($0.id) }) {
            return .centerAncestor(cardID: ancestor.id)
        }
        if let descendant = resolvedMainWorkspaceVisibleDescendantSelection(in: cards, startingFrom: activeCard) {
            return .centerPreferredDescendant(cardID: descendant.cardID)
        }
        if let otherDescendant = cards.first(where: { activeDescendantIDs.contains($0.id) }) {
            return .centerOtherDescendant(cardID: otherDescendant.id)
        }
        return resolvedMainWorkspaceSurroundingPolicy(
            in: cards,
            around: activeCard.id,
            preorderIndexByCardID: preorderIndexByCardID
        )
    }

    private func resolvedMainWorkspaceVisibleDescendantSelection(
        in cards: [SceneCard],
        startingFrom root: SceneCard
    ) -> MainWorkspaceVisibleDescendantSelection? {
        let visibleCardIDs = Set(cards.map(\.id))
        if let descendantSelection = resolvedMainWorkspaceHistorySortedDescendantSelection(
            from: root,
            visibleCardIDs: visibleCardIDs
        ) {
            mainWorkspacePhase0Log(
                "descendant-selection-monitor",
                "root=\(mainWorkspacePhase0CardID(root.id)) node=\(mainWorkspacePhase0CardID(root.id)) " +
                "mode=path sourceKind=\(descendantSelection.source.debugLabel) target=\(mainWorkspacePhase0CardID(descendantSelection.cardID)) " +
                "visible=\(mainWorkspacePhase0CardList(Array(visibleCardIDs))) path=\(mainWorkspacePhase0CardList(descendantSelection.path))"
            )
            return descendantSelection
        }

        mainWorkspacePhase0Log(
            "descendant-selection-monitor",
            "root=\(mainWorkspacePhase0CardID(root.id)) mode=none visible=\(mainWorkspacePhase0CardList(Array(visibleCardIDs))) " +
            "path=\(mainWorkspacePhase0CardList([root.id]))"
        )
        return nil
    }

    func resolvedMainWorkspaceVisibleDescendantTargetID(
        from root: SceneCard,
        visibleCardIDs: Set<UUID>,
        matching category: String?
    ) -> UUID? {
        _ = category
        return resolvedMainWorkspaceHistorySortedDescendantSelection(
            from: root,
            visibleCardIDs: visibleCardIDs
        )?.cardID
    }

    private func resolvedMainWorkspaceHistorySortedDescendantSelection(
        from root: SceneCard,
        visibleCardIDs: Set<UUID>
    ) -> MainWorkspaceVisibleDescendantSelection? {
        let orderedDescendantIDs = resolvedMainWorkspaceHistorySortedDescendantIDs(from: root)
        guard let cardID = orderedDescendantIDs.first(where: { visibleCardIDs.contains($0) }) else {
            return nil
        }
        return MainWorkspaceVisibleDescendantSelection(
            cardID: cardID,
            isPreferred: true,
            path: [root.id, cardID],
            source: .activeHistory
        )
    }

    private func resolvedMainWorkspaceHistorySortedDescendantIDs(from root: SceneCard) -> [UUID] {
        let historyRankByCardID = resolvedMainWorkspaceHistoryRankByCardID()
        var descendantIDs: [UUID] = []

        func visit(_ card: SceneCard) {
            let sortedChildren = card.sortedChildren.sorted { lhs, rhs in
                let leftRank = historyRankByCardID[lhs.id] ?? Int.max
                let rightRank = historyRankByCardID[rhs.id] ?? Int.max
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhs.createdAt < rhs.createdAt
            }
            for child in sortedChildren {
                descendantIDs.append(child.id)
                visit(child)
            }
        }

        visit(root)
        return descendantIDs
    }

    private func resolvedMainWorkspaceHistoryRankByCardID() -> [UUID: Int] {
        var rankByID: [UUID: Int] = [:]
        for (index, cardID) in mainWorkspaceActiveHistory.enumerated() {
            rankByID[cardID] = index
        }
        return rankByID
    }

    private func resolvedMainWorkspaceVisibleFallbackChildSelection(
        for card: SceneCard,
        visibleCardIDs: Set<UUID>,
        matching category: String?
    ) -> MainWorkspaceNavigationModel.PreferredNavigationChildSelection? {
        guard let selection = MainWorkspaceNavigationModel.preferredNavigationChildSelection(
            for: card,
            matching: category,
            activeHistory: mainWorkspaceActiveHistory
        ) else {
            return nil
        }
        if visibleCardIDs.contains(selection.child.id) {
            return selection
        }
        let hasVisibleDescendant = !scenario.descendantIDs(for: selection.child.id).isDisjoint(with: visibleCardIDs)
        return hasVisibleDescendant ? selection : nil
    }

    func resolvedMainWorkspaceVisibleSubtreeChildSelection(
        for card: SceneCard,
        visibleCardIDs: Set<UUID>,
        matching category: String?,
        preferRememberedAfterHistory: Bool
    ) -> MainWorkspaceNavigationModel.PreferredNavigationChildSelection? {
        let visibleChildren = card.sortedChildren.filter { child in
            guard let category else { return true }
            return child.category == category
        }
        let candidateChildren = visibleChildren.filter { child in
            visibleCardIDs.contains(child.id) || !scenario.descendantIDs(for: child.id).isDisjoint(with: visibleCardIDs)
        }
        guard !candidateChildren.isEmpty else { return nil }

        for childID in mainWorkspaceActiveHistory {
            if let historyMatch = candidateChildren.first(where: { $0.id == childID }) {
                return MainWorkspaceNavigationModel.PreferredNavigationChildSelection(
                    child: historyMatch,
                    source: .activeHistory
                )
            }
        }
        if preferRememberedAfterHistory,
           let rememberedID = card.lastSelectedChildID,
           let remembered = candidateChildren.first(where: { $0.id == rememberedID }) {
            return MainWorkspaceNavigationModel.PreferredNavigationChildSelection(
                child: remembered,
                source: .lastSelectedChild
            )
        }
        if let firstVisible = candidateChildren.first {
            return MainWorkspaceNavigationModel.PreferredNavigationChildSelection(
                child: firstVisible,
                source: .firstAvailable
            )
        }
        if let rememberedID = card.lastSelectedChildID,
           let remembered = candidateChildren.first(where: { $0.id == rememberedID }) {
            return MainWorkspaceNavigationModel.PreferredNavigationChildSelection(
                child: remembered,
                source: .lastSelectedChild
            )
        }
        return nil
    }

    private func resolvedMainWorkspaceSurroundingPolicy(
        in cards: [SceneCard],
        around activeCardID: UUID,
        preorderIndexByCardID: [UUID: Int]
    ) -> MainWorkspaceColumnPolicy {
        guard let activePreorder = preorderIndexByCardID[activeCardID] else { return .none }
        let sortedCards = cards.sorted { lhs, rhs in
            let leftOrder = preorderIndexByCardID[lhs.id] ?? Int.max
            let rightOrder = preorderIndexByCardID[rhs.id] ?? Int.max
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            return lhs.orderIndex < rhs.orderIndex
        }
        let beforeCard = sortedCards.last { (preorderIndexByCardID[$0.id] ?? Int.max) < activePreorder }
        let afterCard = sortedCards.first { (preorderIndexByCardID[$0.id] ?? Int.max) > activePreorder }
        if let beforeCard, let afterCard {
            return .between(afterID: beforeCard.id, beforeID: afterCard.id)
        }
        if let beforeCard {
            return .after(cardID: beforeCard.id)
        }
        if let afterCard {
            return .before(cardID: afterCard.id)
        }
        return .none
    }

    private func mainWorkspacePreorderIndexByCardID() -> [UUID: Int] {
        var orderByID: [UUID: Int] = [:]
        var nextIndex = 0

        func visit(_ card: SceneCard) {
            orderByID[card.id] = nextIndex
            nextIndex += 1
            for child in card.sortedChildren {
                visit(child)
            }
        }

        for root in scenario.rootCards {
            visit(root)
        }
        return orderByID
    }

    private func isMainWorkspaceScrollPlanCurrent(_ plan: MainWorkspaceScrollPlan) -> Bool {
        mainWorkspaceScrollPlan?.generation == plan.generation
    }

    private func scheduleMainWorkspaceColumnPlanFocus(
        viewportKey: String,
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        plan: MainWorkspaceScrollPlan,
        columnPlan: MainWorkspaceColumnPlan,
        authority: MainVerticalScrollAuthority
    ) {
        cancelPendingMainColumnFocusWorkItem(for: viewportKey)
        let focusDelay = columnPlan.focusDelay > 0
            ? columnPlan.focusDelay
            : (plan.animated ? 0.01 : 0.0)
        let workItem = DispatchWorkItem {
            defer { mainColumnPendingFocusWorkItemByKey[viewportKey] = nil }
            guard !showFocusMode else { return }
            guard acceptsKeyboardInput else { return }
            guard activeCardID == plan.activeCardID else { return }
            guard isMainWorkspaceScrollPlanCurrent(plan) else { return }
            guard isMainVerticalScrollAuthorityCurrent(authority, viewportKey: viewportKey) else { return }
            applyMainWorkspaceColumnPlan(
                viewportKey: viewportKey,
                cards: cards,
                level: level,
                parent: parent,
                proxy: proxy,
                viewportHeight: viewportHeight,
                plan: plan,
                columnPlan: columnPlan,
                authority: authority
            )
        }
        mainColumnPendingFocusWorkItemByKey[viewportKey] = workItem
        if focusDelay <= 0 {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + focusDelay, execute: workItem)
        }
    }

    private func applyMainWorkspaceColumnPlan(
        viewportKey: String,
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        plan: MainWorkspaceScrollPlan,
        columnPlan: MainWorkspaceColumnPlan,
        authority: MainVerticalScrollAuthority,
        scheduleVerification: Bool = true
    ) {
        let shouldScheduleColumnVerification = scheduleVerification && !shouldUseMainWorkspaceSurface
        if columnPlan.keepVisibleOnly &&
            isMainWorkspaceColumnPlanVisible(
                viewportKey: viewportKey,
                cards: cards,
                viewportHeight: viewportHeight,
                columnPlan: columnPlan
            ) {
            if shouldScheduleColumnVerification {
                scheduleMainWorkspaceColumnPlanVerification(
                    viewportKey: viewportKey,
                    cards: cards,
                    level: level,
                    parent: parent,
                    proxy: proxy,
                    viewportHeight: viewportHeight,
                    plan: plan,
                    columnPlan: columnPlan,
                    authority: authority
                )
            }
            return
        }

        if !columnPlan.keepVisibleOnly &&
            !columnPlan.forceAlignment &&
            isMainWorkspaceColumnPlanAligned(
                viewportKey: viewportKey,
                cards: cards,
                viewportHeight: viewportHeight,
                columnPlan: columnPlan
            ) {
            if shouldScheduleColumnVerification {
                scheduleMainWorkspaceColumnPlanVerification(
                    viewportKey: viewportKey,
                    cards: cards,
                    level: level,
                    parent: parent,
                    proxy: proxy,
                    viewportHeight: viewportHeight,
                    plan: plan,
                    columnPlan: columnPlan,
                    authority: authority
                )
            }
            return
        }

        mainWorkspacePhase0Log(
            "column-plan-apply",
            "generation=\(plan.generation) viewport=\(viewportKey) policy=\(columnPlan.policy.debugSummary) " +
            "animated=\(plan.animated) keepVisible=\(columnPlan.keepVisibleOnly)"
        )

        if performMainWorkspaceColumnNativeScroll(
            viewportKey: viewportKey,
            cards: cards,
            viewportHeight: viewportHeight,
            plan: plan,
            columnPlan: columnPlan
        ) {
            if shouldScheduleColumnVerification {
                scheduleMainWorkspaceColumnPlanVerification(
                    viewportKey: viewportKey,
                    cards: cards,
                    level: level,
                    parent: parent,
                    proxy: proxy,
                    viewportHeight: viewportHeight,
                    plan: plan,
                    columnPlan: columnPlan,
                    authority: authority
                )
            }
            return
        }

        guard !shouldUseMainWorkspaceSurface else { return }
        guard let targetID = columnPlan.primaryCardID else { return }
        let fallbackAnchor: UnitPoint
        switch columnPlan.anchorMode {
        case .keepVisible:
            fallbackAnchor = .center
        case .clampedCenter:
            // ScrollViewProxy cannot express clamped-center; use .center as a close
            // approximation. The native offset path and verify pass will refine it.
            fallbackAnchor = .center
        }
        suspendMainColumnViewportCapture(for: plan.animated ? 0.32 : 0.12)
        if plan.animated {
            withAnimation(quickEaseAnimation) {
                proxy.scrollTo(targetID, anchor: fallbackAnchor)
            }
        } else {
            performWithoutAnimation {
                proxy.scrollTo(targetID, anchor: fallbackAnchor)
            }
        }
        if shouldScheduleColumnVerification {
            scheduleMainWorkspaceColumnPlanVerification(
                viewportKey: viewportKey,
                cards: cards,
                level: level,
                parent: parent,
                proxy: proxy,
                viewportHeight: viewportHeight,
                plan: plan,
                columnPlan: columnPlan,
                authority: authority
            )
        }
    }

    private func scheduleMainWorkspaceColumnPlanVerification(
        viewportKey: String,
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        plan: MainWorkspaceScrollPlan,
        columnPlan: MainWorkspaceColumnPlan,
        authority: MainVerticalScrollAuthority,
        attempt: Int = 0
    ) {
        cancelPendingMainColumnFocusVerificationWorkItem(for: viewportKey)
        let delay: TimeInterval
        if plan.animated {
            delay = attempt == 0 ? 0.18 : 0.10
        } else {
            delay = attempt == 0 ? 0.05 : 0.08
        }
        var verificationWorkItem: DispatchWorkItem?
        verificationWorkItem = DispatchWorkItem {
            defer {
                if let verificationWorkItem,
                   mainColumnPendingFocusVerificationWorkItemByKey[viewportKey] === verificationWorkItem {
                    mainColumnPendingFocusVerificationWorkItemByKey[viewportKey] = nil
                }
            }
            guard !showFocusMode else { return }
            guard acceptsKeyboardInput else { return }
            guard activeCardID == plan.activeCardID else { return }
            guard isMainWorkspaceScrollPlanCurrent(plan) else { return }
            guard isMainVerticalScrollAuthorityCurrent(authority, viewportKey: viewportKey) else { return }

            let satisfied = columnPlan.keepVisibleOnly
                ? isMainWorkspaceColumnPlanVisible(
                    viewportKey: viewportKey,
                    cards: cards,
                    viewportHeight: viewportHeight,
                    columnPlan: columnPlan
                )
                : isMainWorkspaceColumnPlanAligned(
                    viewportKey: viewportKey,
                    cards: cards,
                    viewportHeight: viewportHeight,
                    columnPlan: columnPlan
                )
            if satisfied {
                return
            }

            if let targetID = columnPlan.primaryCardID {
                MainCanvasNavigationDiagnostics.shared.recordVerificationRetry(
                    ownerKey: mainCanvasDiagnosticsOwnerKey,
                    viewportKey: viewportKey,
                    attempt: attempt,
                    targetID: targetID,
                    observedFrame: observedMainColumnTargetFrame(
                        viewportKey: viewportKey,
                        targetID: targetID
                    ) != nil,
                    animatedRetry: plan.animated
                )
            }

            applyMainWorkspaceColumnPlan(
                viewportKey: viewportKey,
                cards: cards,
                level: level,
                parent: parent,
                proxy: proxy,
                viewportHeight: viewportHeight,
                plan: plan,
                columnPlan: columnPlan,
                authority: authority,
                scheduleVerification: false
            )

            guard attempt < 2 else { return }
            scheduleMainWorkspaceColumnPlanVerification(
                viewportKey: viewportKey,
                cards: cards,
                level: level,
                parent: parent,
                proxy: proxy,
                viewportHeight: viewportHeight,
                plan: plan,
                columnPlan: columnPlan,
                authority: authority,
                attempt: attempt + 1
            )
        }
        if let verificationWorkItem {
            mainColumnPendingFocusVerificationWorkItemByKey[viewportKey] = verificationWorkItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: verificationWorkItem)
        }
    }

    private func isMainWorkspaceColumnPlanVisible(
        viewportKey: String,
        cards: [SceneCard],
        viewportHeight: CGFloat,
        columnPlan: MainWorkspaceColumnPlan
    ) -> Bool {
        guard let targetID = columnPlan.primaryCardID else { return false }
        guard case .keepVisible = columnPlan.anchorMode else {
            return isMainWorkspaceColumnPlanAligned(
                viewportKey: viewportKey,
                cards: cards,
                viewportHeight: viewportHeight,
                columnPlan: columnPlan
            )
        }
        return isMainColumnFocusTargetVisible(
            viewportKey: viewportKey,
            cards: cards,
            targetID: targetID,
            viewportHeight: viewportHeight,
            prefersTopAnchor: false
        )
    }

    private func isMainWorkspaceColumnPlanAligned(
        viewportKey: String,
        cards: [SceneCard],
        viewportHeight: CGFloat,
        columnPlan: MainWorkspaceColumnPlan
    ) -> Bool {
        guard let targetOffsetY = resolvedMainWorkspaceColumnPlanTargetOffset(
            viewportKey: viewportKey,
            cards: cards,
            viewportHeight: viewportHeight,
            columnPlan: columnPlan
        ) else {
            return false
        }
        let visibleRect = resolvedMainColumnVisibleRect(
            viewportKey: viewportKey,
            viewportHeight: viewportHeight
        )
        let documentHeight =
            mainCanvasScrollCoordinator.scrollView(for: viewportKey)?.documentView?.bounds.height ??
            max(visibleRect.height, resolvedMainColumnLayoutSnapshot(in: cards, viewportHeight: viewportHeight).contentBottomY)
        let maxY = max(0, documentHeight - visibleRect.height)
        let resolvedTargetY = CaretScrollCoordinator.resolvedVerticalTargetY(
            visibleRect: visibleRect,
            targetY: targetOffsetY,
            minY: 0,
            maxY: maxY,
            snapToPixel: true
        )
        let currentY = resolvedMainColumnCurrentOffsetY(viewportKey: viewportKey)
        let tolerance: CGFloat = columnPlan.keepVisibleOnly ? 24 : 22
        return abs(resolvedTargetY - currentY) <= tolerance
    }

    private func logMainWorkspaceScrollPlanVerification(
        plan: MainWorkspaceScrollPlan,
        levelsData: [LevelData]
    ) {
        for columnPlan in plan.columnPlans {
            guard columnPlan.policy != .none else { continue }
            guard levelsData.indices.contains(columnPlan.level) else { continue }
            let cards = levelsData[columnPlan.level].cards
            guard !cards.isEmpty else { continue }

            let viewportHeight = max(
                1,
                mainCanvasScrollCoordinator.scrollView(for: columnPlan.viewportKey)?.documentVisibleRect.height ?? 1
            )
            let isVisible = isMainWorkspaceColumnPlanVisible(
                viewportKey: columnPlan.viewportKey,
                cards: cards,
                viewportHeight: viewportHeight,
                columnPlan: columnPlan
            )
            let isAligned = isMainWorkspaceColumnPlanAligned(
                viewportKey: columnPlan.viewportKey,
                cards: cards,
                viewportHeight: viewportHeight,
                columnPlan: columnPlan
            )
            guard !isVisible || !isAligned else { continue }

            let targetOffsetY = resolvedMainWorkspaceColumnPlanTargetOffset(
                viewportKey: columnPlan.viewportKey,
                cards: cards,
                viewportHeight: viewportHeight,
                columnPlan: columnPlan
            )
            let currentY = resolvedMainColumnCurrentOffsetY(viewportKey: columnPlan.viewportKey)
            mainWorkspacePhase0Log(
                "column-plan-verify-mismatch",
                "generation=\(plan.generation) viewport=\(columnPlan.viewportKey) policy=\(columnPlan.policy.debugSummary) " +
                "visible=\(isVisible) aligned=\(isAligned) currentY=\(currentY) targetY=\(targetOffsetY ?? -1) " +
                "primary=\(mainWorkspacePhase0CardID(columnPlan.primaryCardID)) keepVisible=\(columnPlan.keepVisibleOnly)"
            )
        }
    }

    @discardableResult
    private func performMainWorkspaceColumnNativeScroll(
        viewportKey: String,
        cards: [SceneCard],
        viewportHeight: CGFloat,
        plan: MainWorkspaceScrollPlan,
        columnPlan: MainWorkspaceColumnPlan
    ) -> Bool {
        guard let scrollView = mainCanvasScrollCoordinator.scrollView(for: viewportKey) else {
            return false
        }
        let visibleRect = scrollView.documentVisibleRect
        let resolvedViewportHeight = max(1, visibleRect.height)
        guard let targetOffsetY = resolvedMainWorkspaceColumnPlanTargetOffset(
            viewportKey: viewportKey,
            cards: cards,
            viewportHeight: resolvedViewportHeight,
            columnPlan: columnPlan
        ) else {
            return false
        }

        let documentHeight = resolvedMainWorkspaceColumnDocumentHeight(
            viewportKey: viewportKey,
            cards: cards,
            viewportHeight: resolvedViewportHeight,
            scrollView: scrollView
        )
        let maxY = max(0, documentHeight - visibleRect.height)
        if plan.animated {
            let resolvedTargetY = CaretScrollCoordinator.resolvedVerticalTargetY(
                visibleRect: visibleRect,
                targetY: targetOffsetY,
                minY: 0,
                maxY: maxY,
                snapToPixel: true
            )
            guard abs(resolvedTargetY - visibleRect.origin.y) > 0.5 else { return true }
            let appliedDuration = CaretScrollCoordinator.resolvedVerticalAnimationDuration(
                currentY: visibleRect.origin.y,
                targetY: resolvedTargetY,
                viewportHeight: resolvedViewportHeight
            )
            suspendMainColumnViewportCapture(for: appliedDuration + 0.06)
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                axis: "vertical",
                engine: "native",
                animated: true,
                target: "\(viewportKey)|\(columnPlan.policy.debugSummary)",
                expectedDuration: appliedDuration
            )
            _ = CaretScrollCoordinator.applyAnimatedVerticalScrollIfNeeded(
                scrollView: scrollView,
                visibleRect: visibleRect,
                targetY: targetOffsetY,
                minY: 0,
                maxY: maxY,
                deadZone: 0.5,
                snapToPixel: true,
                duration: appliedDuration
            )
            return true
        }

        suspendMainColumnViewportCapture(for: 0.12)
        MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
            ownerKey: mainCanvasDiagnosticsOwnerKey,
            axis: "vertical",
            engine: "native",
            animated: false,
            target: "\(viewportKey)|\(columnPlan.policy.debugSummary)",
            expectedDuration: 0
        )
        _ = CaretScrollCoordinator.applyVerticalScrollIfNeeded(
            scrollView: scrollView,
            visibleRect: visibleRect,
            targetY: targetOffsetY,
            minY: 0,
            maxY: maxY,
            deadZone: 0.5,
            snapToPixel: true
        )
        let resolvedTargetY = CaretScrollCoordinator.resolvedVerticalTargetY(
            visibleRect: visibleRect,
            targetY: targetOffsetY,
            minY: 0,
            maxY: maxY,
            snapToPixel: true
        )
        let currentY = scrollView.contentView.bounds.origin.y
        return abs(resolvedTargetY - currentY) <= 0.5
    }

    private func resolvedMainWorkspaceColumnPlanTargetOffset(
        viewportKey: String,
        cards: [SceneCard],
        viewportHeight: CGFloat,
        columnPlan: MainWorkspaceColumnPlan
    ) -> CGFloat? {
        switch columnPlan.anchorMode {
        case .keepVisible(let editingRevealEdge):
            guard let targetID = columnPlan.primaryCardID else { return nil }
            return resolvedMainColumnVisibilityTargetOffset(
                viewportKey: viewportKey,
                cards: cards,
                targetID: targetID,
                viewportHeight: viewportHeight,
                prefersTopAnchor: false,
                editingRevealEdge: editingRevealEdge
            )

        case .clampedCenter(let chromeInset):
            guard let rect = resolvedMainWorkspaceColumnPlanRect(
                viewportKey: viewportKey,
                cards: cards,
                viewportHeight: viewportHeight,
                columnPlan: columnPlan
            ) else {
                return nil
            }
            let oversizedThreshold = viewportHeight - chromeInset
            let adjustedHeight =
                rect.height > oversizedThreshold
                ? viewportHeight * 0.5 + chromeInset
                : rect.height
            return rect.minY + adjustedHeight * 0.5 - viewportHeight * 0.5
        }
    }

    private func resolvedMainWorkspaceColumnPlanRect(
        viewportKey: String,
        cards: [SceneCard],
        viewportHeight: CGFloat,
        columnPlan: MainWorkspaceColumnPlan
    ) -> CGRect? {
        switch columnPlan.policy {
        case .centerActive(let cardID),
            .centerAncestor(let cardID),
            .centerPreferredDescendant(let cardID),
            .centerOtherDescendant(let cardID):
            return resolvedMainColumnFrame(
                viewportKey: viewportKey,
                cards: cards,
                cardID: cardID,
                viewportHeight: viewportHeight
            )

        case .between(let afterID, let beforeID):
            guard let afterFrame = resolvedMainColumnFrame(
                viewportKey: viewportKey,
                cards: cards,
                cardID: afterID,
                viewportHeight: viewportHeight
            ),
            let beforeFrame = resolvedMainColumnFrame(
                viewportKey: viewportKey,
                cards: cards,
                cardID: beforeID,
                viewportHeight: viewportHeight
            ) else {
                return nil
            }
            let gapStart = afterFrame.maxY
            let gapEnd = beforeFrame.minY
            if gapEnd > gapStart {
                return CGRect(x: 0, y: gapStart, width: 1, height: gapEnd - gapStart)
            }
            let midpoint = (gapStart + gapEnd) * 0.5
            return CGRect(x: 0, y: midpoint, width: 1, height: 1)

        case .before(let cardID):
            return resolvedMainWorkspaceSyntheticGapRect(
                viewportKey: viewportKey,
                cards: cards,
                viewportHeight: viewportHeight,
                cardID: cardID,
                edge: .before
            )

        case .after(let cardID):
            return resolvedMainWorkspaceSyntheticGapRect(
                viewportKey: viewportKey,
                cards: cards,
                viewportHeight: viewportHeight,
                cardID: cardID,
                edge: .after
            )

        case .none:
            return nil
        }
    }

    private enum MainWorkspaceSyntheticGapEdge {
        case before
        case after
    }

    private func resolvedMainWorkspaceSyntheticGapRect(
        viewportKey: String,
        cards: [SceneCard],
        viewportHeight: CGFloat,
        cardID: UUID,
        edge: MainWorkspaceSyntheticGapEdge
    ) -> CGRect? {
        guard let targetFrame = resolvedMainColumnFrame(
            viewportKey: viewportKey,
            cards: cards,
            cardID: cardID,
            viewportHeight: viewportHeight
        ) else {
            return nil
        }

        let snapshot = resolvedMainColumnLayoutSnapshot(in: cards, viewportHeight: viewportHeight)
        guard let index = snapshot.orderedCardIDs.firstIndex(of: cardID) else {
            return nil
        }
        let defaultGap = max(18, min(72, CGFloat(mainCardVerticalGap) + mainParentGroupSeparatorHeight + 16))

        switch edge {
        case .before:
            if index > 0,
               let previousID = snapshot.orderedCardIDs[safe: index - 1],
               let previousFrame = resolvedMainColumnFrame(
                    viewportKey: viewportKey,
                    cards: cards,
                    cardID: previousID,
                    viewportHeight: viewportHeight
               ) {
                let gapStart = previousFrame.maxY
                let gapEnd = targetFrame.minY
                if gapEnd > gapStart {
                    return CGRect(x: 0, y: gapStart, width: 1, height: gapEnd - gapStart)
                }
            }
            return CGRect(
                x: 0,
                y: max(0, targetFrame.minY - defaultGap),
                width: 1,
                height: defaultGap
            )

        case .after:
            if index + 1 < snapshot.orderedCardIDs.count {
                let nextID = snapshot.orderedCardIDs[index + 1]
                if let nextFrame = resolvedMainColumnFrame(
                    viewportKey: viewportKey,
                    cards: cards,
                    cardID: nextID,
                    viewportHeight: viewportHeight
                ) {
                    let gapStart = targetFrame.maxY
                    let gapEnd = nextFrame.minY
                    if gapEnd > gapStart {
                        return CGRect(x: 0, y: gapStart, width: 1, height: gapEnd - gapStart)
                    }
                }
            }
            return CGRect(
                x: 0,
                y: targetFrame.maxY,
                width: 1,
                height: defaultGap
            )
        }
    }

    private func resolvedMainWorkspaceColumnDocumentHeight(
        viewportKey: String,
        cards: [SceneCard],
        viewportHeight: CGFloat,
        scrollView: NSScrollView
    ) -> CGFloat {
        let liveDocumentHeight = scrollView.documentView?.bounds.height ?? 0
        guard shouldUseMainWorkspaceSurface else {
            return liveDocumentHeight
        }

        let predictedDocumentHeight = max(
            viewportHeight,
            resolvedMainColumnLayoutSnapshot(in: cards, viewportHeight: viewportHeight).contentBottomY
        )
        if predictedDocumentHeight > liveDocumentHeight + 1 {
            mainWorkspacePhase0Log(
                "column-plan-document-height-fallback",
                "viewport=\(viewportKey) liveHeight=\(liveDocumentHeight) predictedHeight=\(predictedDocumentHeight)"
            )
        }
        return max(liveDocumentHeight, predictedDocumentHeight)
    }

    private func resolvedMainColumnFrame(
        viewportKey: String,
        cards: [SceneCard],
        cardID: UUID,
        viewportHeight: CGFloat
    ) -> CGRect? {
        let predictedFrame = predictedMainColumnTargetFrame(
            cards: cards,
            targetID: cardID,
            viewportHeight: viewportHeight
        )
        let observedFrame = observedMainColumnTargetFrame(
            viewportKey: viewportKey,
            targetID: cardID
        )
        if shouldUseMainWorkspaceSurface {
            return predictedFrame ?? observedFrame
        }
        if let predictedFrame, let observedFrame {
            let minYDelta = abs(predictedFrame.minY - observedFrame.minY)
            let heightDelta = abs(predictedFrame.height - observedFrame.height)
            if max(minYDelta, heightDelta) > 24 {
                mainWorkspacePhase0Log(
                    "column-plan-frame-mismatch",
                    "viewport=\(viewportKey) card=\(mainWorkspacePhase0CardID(cardID)) " +
                    "predictedMinY=\(predictedFrame.minY) observedMinY=\(observedFrame.minY) " +
                    "predictedHeight=\(predictedFrame.height) observedHeight=\(observedFrame.height)"
                )
            }
            let currentOffsetY = resolvedMainColumnCurrentOffsetY(viewportKey: viewportKey)
            let observedLooksStaleAtTop =
                currentOffsetY <= 1 &&
                observedFrame.minY <= viewportHeight &&
                predictedFrame.minY > max(viewportHeight * 1.5, observedFrame.maxY + viewportHeight)
            if observedLooksStaleAtTop {
                mainWorkspacePhase0Log(
                    "column-plan-frame-prefer-predicted",
                    "viewport=\(viewportKey) card=\(mainWorkspacePhase0CardID(cardID)) " +
                    "currentY=\(currentOffsetY) predictedMinY=\(predictedFrame.minY) observedMinY=\(observedFrame.minY)"
                )
                return predictedFrame
            }
        }
        return observedFrame ?? predictedFrame
    }
}
