import SwiftUI
import AppKit

enum MainWorkspaceMotionEntryPoints {
    typealias PublishIntent = (
        MainCanvasScrollCoordinator.NavigationIntentKind,
        MainCanvasScrollCoordinator.NavigationIntentScope,
        UUID?,
        UUID?,
        Bool,
        String
    ) -> Void

    static func beginEditingBoundaryMotionSession(
        targetCardID: UUID,
        animated: Bool = false,
        setPendingPreemptiveTargetID: (UUID?) -> Void,
        publishIntent: PublishIntent
    ) {
        setPendingPreemptiveTargetID(targetCardID)
        publishIntent(
            .focusChange,
            .allColumns,
            targetCardID,
            targetCardID,
            animated,
            "editingBoundary"
        )
    }

    static func beginReorderMotionSession(
        movedCardIDs: [UUID],
        anchorCardID: UUID?,
        resolvedHorizontalOffset: CGFloat?,
        cancelArrowSettle: () -> Void,
        cancelPendingFocusWork: () -> Void,
        setPendingReorderMotionCardIDs: ([UUID]) -> Void,
        setPendingReorderHorizontalOffsetX: (CGFloat?) -> Void,
        setPendingPreemptiveTargetID: (UUID?) -> Void,
        publishIntent: PublishIntent
    ) {
        var seen: Set<UUID> = []
        let resolvedCardIDs = movedCardIDs.filter { seen.insert($0).inserted }
        setPendingReorderMotionCardIDs(resolvedCardIDs)
        setPendingReorderHorizontalOffsetX(resolvedHorizontalOffset)
        cancelArrowSettle()
        cancelPendingFocusWork()
        guard let anchorCardID else { return }
        setPendingPreemptiveTargetID(anchorCardID)
        publishIntent(
            .focusChange,
            .allColumns,
            anchorCardID,
            anchorCardID,
            false,
            "reorderCommit"
        )
    }

    static func publishPreemptiveFocusNavigationIntent(
        targetID: UUID?,
        focusNavigationAnimationEnabled: Bool,
        suppressRepeatAnimation: Bool,
        trigger: String = "arrowPreview",
        setPendingPreemptiveTargetID: (UUID?) -> Void,
        publishIntent: PublishIntent,
        log: (UUID, Bool, String) -> Void
    ) {
        guard let targetID else { return }
        let shouldAnimate = focusNavigationAnimationEnabled && !suppressRepeatAnimation
        setPendingPreemptiveTargetID(targetID)
        publishIntent(
            .focusChange,
            .allColumns,
            targetID,
            targetID,
            shouldAnimate,
            trigger
        )
        log(targetID, shouldAnimate, trigger)
    }

    static func requestMainCanvasRestoreForFocusExit(
        activeCardID: UUID?,
        editingCardID: UUID?,
        lastActiveCardID: UUID?,
        rootCardID: UUID?,
        snapshot: FocusModeWorkspaceSnapshot?,
        enqueueRestore: (UUID?, Int?, Bool, MainCanvasViewState.RestoreRequest.Reason) -> Void
    ) {
        let targetID = activeCardID ?? editingCardID ?? lastActiveCardID ?? rootCardID
        enqueueRestore(targetID, snapshot?.visibleMainCanvasLevel, true, .focusExit)
    }

    static func requestMainCanvasViewportRestoreForFocusExit(
        showFocusMode: Bool,
        snapshot: FocusModeWorkspaceSnapshot?,
        currentOffsets: [String: CGFloat],
        scheduleViewportRestore: ([String: CGFloat]) -> Void
    ) {
        guard !showFocusMode else { return }
        let storedOffsets = snapshot?.mainColumnViewportOffsets ?? currentOffsets
        guard !storedOffsets.isEmpty else { return }
        scheduleViewportRestore(storedOffsets)
    }

    static func shouldPublishNavigationSettle(
        verticalMisalignment: Bool,
        horizontalMisalignment: Bool,
        horizontalMode: MainCanvasHorizontalScrollMode
    ) -> Bool {
        verticalMisalignment || (
            horizontalMode == .oneStep &&
            horizontalMisalignment
        )
    }
}

extension ScenarioWriterView {
    // MARK: - Canvas Position Restore

    private var mainCanvasRestoreRetryDelays: [TimeInterval] {
        [0.0, 0.05, 0.18]
    }

    private func enqueueMainCanvasRestoreRequest(
        targetID: UUID?,
        visibleLevel: Int? = nil,
        forceSemantic: Bool = false,
        reason: MainCanvasViewState.RestoreRequest.Reason = .generic
    ) {
        guard !showFocusMode else { return }
        guard let targetID else { return }
        DispatchQueue.main.async {
            guard !showFocusMode else { return }
            scheduleMainCanvasRestoreRequest(
                targetCardID: targetID,
                visibleLevel: visibleLevel,
                forceSemantic: forceSemantic,
                reason: reason
            )
        }
    }

    func scheduleMainCanvasRestoreRetries(_ action: @escaping () -> Void) {
        for delay in mainCanvasRestoreRetryDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                action()
            }
        }
    }

    func scheduleMainColumnViewportRestore(_ offsets: [String: CGFloat]) {
        guard !offsets.isEmpty else { return }
        if mainCanvasScrollCoordinator.hasActiveMotionSession() {
            pendingMainDeferredColumnViewportRestoreOffsets = offsets
            indexBoardRestoreTrace(
                "main_canvas_column_viewport_restore_deferred",
                "count=\(offsets.count) sessionActive=true"
            )
            return
        }
        scheduleMainCanvasRestoreRetries {
            guard !showFocusMode else { return }
            applyStoredMainColumnViewportOffsets(offsets)
        }
    }

    func replayDeferredMainColumnViewportRestoreIfNeeded() {
        let offsets = pendingMainDeferredColumnViewportRestoreOffsets
        guard !offsets.isEmpty else { return }
        pendingMainDeferredColumnViewportRestoreOffsets = [:]
        scheduleMainColumnViewportRestore(offsets)
    }

    func restoreMainCanvasPositionIfNeeded(proxy: ScrollViewProxy, availableWidth: CGFloat) {
        guard !showFocusMode else { return }
        guard !isPreviewingHistory else { return }
        guard let request = pendingMainCanvasRestoreRequest else { return }
        if mainCanvasScrollCoordinator.hasActiveMotionSession() {
            indexBoardRestoreTrace(
                "main_canvas_restore_deferred",
                "target=\(debugRestoreUUID(request.targetCardID)) request=\(request.reason.rawValue)"
            )
            return
        }
        if shouldSuppressGeneralMainCanvasScrollDuringEditing(targetCardID: request.targetCardID) {
            indexBoardRestoreTrace(
                "main_canvas_restore_skip",
                "reason=editingIsolation target=\(debugRestoreUUID(request.targetCardID)) request=\(request.reason.rawValue) " +
                "isolationTarget=\(debugRestoreUUID(mainEditingScrollIsolationTargetCardID)) " +
                "until=\(String(format: "%.3f", mainEditingScrollIsolationUntil.timeIntervalSince1970))"
            )
            pendingMainCanvasRestoreRequest = nil
            return
        }

        if let visibleLevel = request.visibleLevel {
            lastScrolledLevel = max(0, visibleLevel)
            let restored = performMainCanvasHorizontalScroll(
                level: lastScrolledLevel,
                availableWidth: availableWidth,
                animated: false
            )
            guard restored else {
                return
            }
            pendingMainCanvasRestoreRequest = nil
            return
        }

        scrollToColumnIfNeeded(
            targetCardID: request.targetCardID,
            proxy: proxy,
            availableWidth: availableWidth,
            force: request.forceSemantic,
            animated: false
        )
        pendingMainCanvasRestoreRequest = nil
    }

    func requestMainCanvasRestoreForHistoryToggle() {
        enqueueMainCanvasRestoreRequest(
            targetID: activeCardID ?? lastActiveCardID ?? scenario.rootCards.first?.id
        )
    }

    func requestMainCanvasRestoreForFocusExit(using snapshot: FocusModeWorkspaceSnapshot?) {
        MainWorkspaceMotionEntryPoints.requestMainCanvasRestoreForFocusExit(
            activeCardID: activeCardID,
            editingCardID: editingCardID,
            lastActiveCardID: lastActiveCardID,
            rootCardID: scenario.rootCards.first?.id,
            snapshot: snapshot
        ) { targetID, visibleLevel, forceSemantic, reason in
            enqueueMainCanvasRestoreRequest(
                targetID: targetID,
                visibleLevel: visibleLevel,
                forceSemantic: forceSemantic,
                reason: reason
            )
        }
    }

    func requestMainCanvasViewportRestoreForFocusExit(using snapshot: FocusModeWorkspaceSnapshot?) {
        MainWorkspaceMotionEntryPoints.requestMainCanvasViewportRestoreForFocusExit(
            showFocusMode: showFocusMode,
            snapshot: snapshot,
            currentOffsets: mainColumnViewportOffsetByKey
        ) { offsets in
            scheduleMainColumnViewportRestore(offsets)
        }
    }

    func captureFocusModeEntryWorkspaceSnapshot() {
        guard !showFocusMode else { return }
        let visibleLevel: Int?
        if let visibleLevel = resolvedVisibleMainCanvasLevelFromCurrentScrollPosition() {
            lastScrolledLevel = visibleLevel
            focusModeEntryWorkspaceSnapshot = FocusModeWorkspaceSnapshot(
                activeCardID: activeCardID,
                editingCardID: editingCardID,
                selectedCardIDs: selectedCardIDs,
                visibleMainCanvasLevel: visibleLevel,
                mainCanvasHorizontalOffset: mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalOffset().map { max(0, $0) },
                mainColumnViewportOffsets: mainColumnViewportOffsetByKey,
                capturedAt: Date()
            )
            return
        } else if let activeID = activeCardID, let activeLevel = displayedMainCardLocationByID(activeID)?.level {
            switch mainCanvasHorizontalScrollMode {
            case .oneStep:
                visibleLevel = activeLevel
            case .twoStep:
                visibleLevel = max(0, activeLevel - 1)
            }
        } else if lastScrolledLevel >= 0 {
            visibleLevel = lastScrolledLevel
        } else {
            visibleLevel = nil
        }
        if let visibleLevel {
            lastScrolledLevel = visibleLevel
        }
        focusModeEntryWorkspaceSnapshot = FocusModeWorkspaceSnapshot(
            activeCardID: activeCardID,
            editingCardID: editingCardID,
            selectedCardIDs: selectedCardIDs,
            visibleMainCanvasLevel: visibleLevel,
            mainCanvasHorizontalOffset: mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalOffset().map { max(0, $0) },
            mainColumnViewportOffsets: mainColumnViewportOffsetByKey,
            capturedAt: Date()
        )
    }

    func canReuseRetainedMainCanvasShellForFocusExit(using snapshot: FocusModeWorkspaceSnapshot?) -> Bool {
        guard !showFocusMode else { return false }
        guard mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalScrollView() != nil else { return false }
        guard let snapshot else { return true }
        let requiredViewportKeys = snapshot.mainColumnViewportOffsets.compactMap { entry in
            entry.value > 1 ? entry.key : nil
        }
        for viewportKey in requiredViewportKeys {
            guard mainCanvasScrollCoordinator.scrollView(for: viewportKey) != nil else { return false }
        }
        return true
    }

    func finalizeRetainedMainCanvasShellForFocusExitReuse() {
        pendingMainCanvasRestoreRequest = nil
        cancelAllPendingMainColumnFocusWork()
    }

    func resolvedMainColumnViewportKey(forCardID cardID: UUID) -> String? {
        guard let level = displayedMainCardLocationByID(cardID)?.level else { return nil }
        return mainColumnViewportStorageKey(level: level)
    }

    func resolvedVisibleMainCanvasLevelFromCurrentScrollPosition() -> Int? {
        guard let scrollView = mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalScrollView() else { return nil }
        let visualLevelCount = max(1, resolvedDisplayedMainLevelsWithParents().count)
        let visibleRect = scrollView.documentVisibleRect
        let documentWidth = scrollView.documentView?.bounds.width ?? 0
        let availableWidth = max(1, documentWidth - (CGFloat(visualLevelCount) * columnWidth))
        let maxX = max(0, documentWidth - visibleRect.width)
        let currentX = scrollView.contentView.bounds.origin.x

        var bestLevel = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for level in 0..<visualLevelCount {
            let targetX = resolvedMainCanvasHorizontalTargetX(
                level: level,
                availableWidth: availableWidth,
                visibleWidth: visibleRect.width
            )
            let resolvedTargetX = CaretScrollCoordinator.resolvedHorizontalTargetX(
                visibleRect: visibleRect,
                targetX: targetX,
                minX: 0,
                maxX: maxX,
                snapToPixel: true
            )
            let distance = abs(resolvedTargetX - currentX)
            if distance < bestDistance {
                bestDistance = distance
                bestLevel = level
            }
        }
        return bestLevel
    }

    func restoreMainCanvasHorizontalViewport(to storedOffsetX: CGFloat) {
        guard !showFocusMode else { return }
        indexBoardRestoreTrace(
            "main_canvas_restore_horizontal_viewport",
            "targetOffset=\(debugRestoreCGFloat(storedOffsetX)) currentOffset=\(debugRestoreCGFloat(mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalOffset()))"
        )
        mainCanvasScrollCoordinator.scheduleMainCanvasHorizontalRestore(offsetX: storedOffsetX)
        if mainCanvasScrollCoordinator.hasActiveMotionSession() {
            indexBoardRestoreTrace(
                "main_canvas_restore_horizontal_viewport_deferred",
                "targetOffset=\(debugRestoreCGFloat(storedOffsetX))"
            )
            return
        }
        suppressHorizontalAutoScroll = true
        scheduleMainCanvasRestoreRetries {
            guard !showFocusMode else { return }
            guard let scrollView = mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalScrollView() else { return }
            let visibleRect = scrollView.documentVisibleRect
            let documentWidth = scrollView.documentView?.bounds.width ?? 0
            let maxX = max(0, documentWidth - visibleRect.width)
            _ = CaretScrollCoordinator.applyHorizontalScrollIfNeeded(
                scrollView: scrollView,
                visibleRect: visibleRect,
                targetX: storedOffsetX,
                minX: 0,
                maxX: maxX,
                deadZone: 0.5,
                snapToPixel: true
            )
            indexBoardRestoreTrace(
                "main_canvas_restore_horizontal_viewport_retry",
                "targetOffset=\(debugRestoreCGFloat(storedOffsetX)) currentOffset=\(debugRestoreCGFloat(scrollView.contentView.bounds.origin.x)) " +
                "maxX=\(String(format: "%.2f", maxX))"
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            suppressHorizontalAutoScroll = false
            indexBoardRestoreTrace(
                "main_canvas_restore_horizontal_viewport_release",
                "targetOffset=\(debugRestoreCGFloat(storedOffsetX)) suppressHorizontalAutoScroll=\(suppressHorizontalAutoScroll)"
            )
        }
    }

    func requestMainCanvasRestoreForZoomChange() {
        guard !showFocusMode else { return }
        guard !showHistoryBar else { return }
        enqueueMainCanvasRestoreRequest(
            targetID: activeCardID ?? editingCardID ?? lastActiveCardID ?? scenario.rootCards.first?.id
        )
    }

    func requestMainCanvasRestoreForHorizontalScrollModeChange() {
        guard !showFocusMode else { return }
        guard !showHistoryBar else { return }
        enqueueMainCanvasRestoreRequest(
            targetID: activeCardID ?? editingCardID ?? lastActiveCardID ?? scenario.rootCards.first?.id
        )
    }

    func cancelMainArrowNavigationSettle() {
        mainArrowNavigationSettleWorkItem?.cancel()
        mainArrowNavigationSettleWorkItem = nil
    }

    func hasMeasuredMainCanvasHorizontalNavigationSettleMisalignment(
        targetCardID: UUID,
        availableWidth: CGFloat
    ) -> Bool {
        guard mainCanvasHorizontalScrollMode == .oneStep else { return false }
        return !isMainCanvasHorizontallyAligned(
            targetCardID: targetCardID,
            availableWidth: availableWidth
        )
    }

    func hasMeasuredMainColumnNavigationSettleMisalignment() -> Bool {
        let levels = resolvedDisplayedMainLevelsWithParents()
        for (level, data) in levels.enumerated() {
            guard shouldAutoAlignMainColumn(cards: data.cards, activeID: activeCardID) else {
                continue
            }
            guard let targetID = resolvedMainColumnFocusTargetID(in: data.cards) else {
                continue
            }
            let viewportKey = mainColumnViewportStorageKey(level: level)
            let viewportHeight = mainCanvasScrollCoordinator
                .scrollView(for: viewportKey)?
                .documentVisibleRect
                .height ?? 0
            guard viewportHeight > 1 else { continue }
            if hasMeasuredMainColumnNavigationSettleMisalignment(
                viewportKey: viewportKey,
                cards: data.cards,
                targetID: targetID,
                viewportHeight: viewportHeight
            ) {
                return true
            }
        }
        return false
    }

    func scheduleMainArrowNavigationSettle() {
        cancelMainArrowNavigationSettle()
        let workItem = DispatchWorkItem {
            defer { mainArrowNavigationSettleWorkItem = nil }
            guard acceptsKeyboardInput else { return }
            guard !showFocusMode else { return }
            guard !isPreviewingHistory else { return }
            guard let activeID = activeCardID, findCard(by: activeID) != nil else { return }
            let verticalMisalignment = hasMeasuredMainColumnNavigationSettleMisalignment()
            let horizontalVisibleWidth = mainCanvasScrollCoordinator
                .resolvedMainCanvasHorizontalScrollView()?
                .documentVisibleRect
                .width ?? 0
            let horizontalMisalignment =
                horizontalVisibleWidth > 1 &&
                hasMeasuredMainCanvasHorizontalNavigationSettleMisalignment(
                    targetCardID: activeID,
                    availableWidth: max(1, horizontalVisibleWidth)
                )
            guard MainWorkspaceMotionEntryPoints.shouldPublishNavigationSettle(
                verticalMisalignment: verticalMisalignment,
                horizontalMisalignment: horizontalMisalignment,
                horizontalMode: mainCanvasHorizontalScrollMode
            ) else {
                bounceDebugLog(
                    "mainArrowNavigationSettle skip target=\(debugCardIDString(activeID)) " +
                    "vertical=\(verticalMisalignment) horizontal=\(horizontalMisalignment)"
                )
                return
            }
            mainColumnLastFocusRequestByKey = [:]
            bounceDebugLog(
                "mainArrowNavigationSettle target=\(debugCardIDString(activeID)) " +
                "vertical=\(verticalMisalignment) horizontal=\(horizontalMisalignment) " +
                "\(debugFocusStateSummary())"
            )
            _ = mainCanvasScrollCoordinator.publishIntent(
                kind: .settleRecovery,
                scope: .allColumns,
                targetCardID: activeID,
                expectedActiveCardID: activeID,
                animated: false,
                trigger: "navigationSettle"
            )
            if horizontalMisalignment && mainCanvasHorizontalScrollMode == .oneStep {
                mainNavigationSettleTick += 1
            }
        }
        mainArrowNavigationSettleWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + mainCanvasScrollCoordinator.motionPolicy.navigationSettleDelay,
            execute: workItem
        )
    }

    /*
     Main workspace focus entry flow

     input decision
       -> publish/begin root session
       -> coordinator owns horizontal + vertical participants
       -> structural late joins reuse that session
       -> settle recovery or timeout close
       -> deferred restore replays after close
     */
    @discardableResult
    func publishMainColumnNavigationIntent(
        kind: MainCanvasScrollCoordinator.NavigationIntentKind,
        scope: MainCanvasScrollCoordinator.NavigationIntentScope,
        targetCardID: UUID? = nil,
        expectedActiveCardID: UUID? = nil,
        animated: Bool,
        trigger: String
    ) -> MainCanvasScrollCoordinator.NavigationIntent {
        mainCanvasScrollCoordinator.publishIntent(
            kind: kind,
            scope: scope,
            targetCardID: targetCardID,
            expectedActiveCardID: expectedActiveCardID,
            animated: animated,
            trigger: trigger
        )
    }

    func beginMainEditingBoundaryMotionSession(
        targetCardID: UUID,
        animated: Bool = false
    ) {
        MainWorkspaceMotionEntryPoints.beginEditingBoundaryMotionSession(
            targetCardID: targetCardID,
            animated: animated,
            setPendingPreemptiveTargetID: { pendingMainPreemptiveFocusNavigationTargetID = $0 }
        ) { kind, scope, targetCardID, expectedActiveCardID, animated, trigger in
            _ = publishMainColumnNavigationIntent(
                kind: kind,
                scope: scope,
                targetCardID: targetCardID,
                expectedActiveCardID: expectedActiveCardID,
                animated: animated,
                trigger: trigger
            )
        }
    }

    func beginMainReorderMotionSession(
        movedCardIDs: [UUID],
        anchorCardID: UUID?
    ) {
        MainWorkspaceMotionEntryPoints.beginReorderMotionSession(
            movedCardIDs: movedCardIDs,
            anchorCardID: anchorCardID,
            resolvedHorizontalOffset: mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalOffset(),
            cancelArrowSettle: { cancelMainArrowNavigationSettle() },
            cancelPendingFocusWork: { cancelAllPendingMainColumnFocusWork() },
            setPendingReorderMotionCardIDs: { pendingMainReorderMotionCardIDs = $0 },
            setPendingReorderHorizontalOffsetX: { pendingMainReorderHorizontalOffsetX = $0 },
            setPendingPreemptiveTargetID: { pendingMainPreemptiveFocusNavigationTargetID = $0 }
        ) { kind, scope, targetCardID, expectedActiveCardID, animated, trigger in
            _ = publishMainColumnNavigationIntent(
                kind: kind,
                scope: scope,
                targetCardID: targetCardID,
                expectedActiveCardID: expectedActiveCardID,
                animated: animated,
                trigger: trigger
            )
        }
    }

    @discardableResult
    func handleMainColumnLateJoinIfPossible(
        kind: MainCanvasScrollCoordinator.NavigationIntentKind,
        viewportKey: String,
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        targetCardID: UUID?,
        expectedActiveCardID: UUID?,
        animated: Bool,
        trigger: String
    ) -> Bool {
        guard let snapshot = mainCanvasScrollCoordinator.activeMotionSessionSnapshot() else {
            return false
        }
        guard snapshot.joinWindowOpen else {
            return true
        }

        let motionGoal: MainCanvasScrollCoordinator.MotionGoal
        switch kind {
        case .bottomReveal:
            motionGoal = .bottomReveal(cardID: targetCardID ?? expectedActiveCardID)
            mainCanvasScrollCoordinator.updateActiveMotionGoal(motionGoal)
        case .focusChange, .settleRecovery, .childListChange, .columnAppear:
            motionGoal = snapshot.goal
        }

        let intent = MainCanvasScrollCoordinator.NavigationIntent(
            id: snapshot.currentIntentID,
            kind: kind,
            scope: .viewport(viewportKey),
            targetCardID: targetCardID,
            expectedActiveCardID: expectedActiveCardID,
            animated: animated,
            trigger: trigger,
            sessionID: snapshot.sessionID,
            sessionRevision: snapshot.revision,
            motionGoal: motionGoal
        )

        switch kind {
        case .childListChange, .columnAppear:
            handleMainColumnImmediateAlignmentIntent(
                viewportKey: viewportKey,
                cards: cards,
                level: level,
                parent: parent,
                proxy: proxy,
                viewportHeight: viewportHeight,
                trigger: trigger,
                intent: intent
            )
        case .bottomReveal:
            handleMainColumnBottomRevealIntent(
                viewportKey: viewportKey,
                cards: cards,
                proxy: proxy,
                viewportHeight: viewportHeight,
                requestedID: targetCardID,
                animated: animated,
                trigger: trigger,
                intent: intent
            )
        case .focusChange, .settleRecovery:
            return false
        }
        return true
    }

    func publishMainColumnFocusNavigationIntent(
        for activeID: UUID?,
        trigger: String = "activeCardChange"
    ) {
        let shouldAnimate =
            focusNavigationAnimationEnabled &&
            !shouldSuppressMainArrowRepeatAnimation()
        _ = publishMainColumnNavigationIntent(
            kind: .focusChange,
            scope: .allColumns,
            targetCardID: activeID,
            expectedActiveCardID: activeID,
            animated: shouldAnimate,
            trigger: trigger
        )
    }

    func publishPreemptiveMainColumnFocusNavigationIntent(
        for targetID: UUID?,
        trigger: String = "arrowPreview"
    ) {
        MainWorkspaceMotionEntryPoints.publishPreemptiveFocusNavigationIntent(
            targetID: targetID,
            focusNavigationAnimationEnabled: focusNavigationAnimationEnabled,
            suppressRepeatAnimation: shouldSuppressMainArrowRepeatAnimation(),
            trigger: trigger,
            setPendingPreemptiveTargetID: { pendingMainPreemptiveFocusNavigationTargetID = $0 }
        ) { kind, scope, targetCardID, expectedActiveCardID, animated, trigger in
            _ = publishMainColumnNavigationIntent(
                kind: kind,
                scope: scope,
                targetCardID: targetCardID,
                expectedActiveCardID: expectedActiveCardID,
                animated: animated,
                trigger: trigger
            )
        } log: { targetID, shouldAnimate, trigger in
            mainWorkspacePhase0Log(
                "preemptive-focus-intent",
                "target=\(mainWorkspacePhase0CardID(targetID)) animated=\(shouldAnimate) trigger=\(trigger)"
            )
        }
    }

    func preemptivelyAlignMainCanvasHorizontally(
        to targetCardID: UUID,
        animated: Bool
    ) {
        guard !showFocusMode else { return }
        guard acceptsKeyboardInput else { return }
        guard !isPreviewingHistory else { return }
        guard mainCanvasHorizontalScrollMode == .oneStep else { return }
        guard let targetLevel = displayedMainCardLocationByID(targetCardID)?.level else { return }
        guard let scrollView = mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalScrollView() else { return }

        let availableWidth = max(1, scrollView.documentVisibleRect.width)
        guard lastScrolledLevel != targetLevel else { return }
        lastScrolledLevel = targetLevel
        let applied = performMainCanvasHorizontalScroll(
            level: targetLevel,
            availableWidth: availableWidth,
            animated: animated
        )
        mainWorkspacePhase0Log(
            "preemptive-horizontal-scroll",
            "target=\(mainWorkspacePhase0CardID(targetCardID)) level=\(targetLevel) animated=\(animated) applied=\(applied)"
        )
    }
}
