import SwiftUI
import AppKit
import QuartzCore
import UniformTypeIdentifiers

extension ScenarioWriterView {

    func resolvedMainColumnCurrentOffsetY(viewportKey: String) -> CGFloat {
        if let liveOffset = mainCanvasScrollCoordinator
            .scrollView(for: viewportKey)?
            .documentVisibleRect
            .origin
            .y
        {
            return liveOffset
        }
        return mainColumnViewportOffsetByKey[viewportKey] ?? 0
    }

    func resolvedMainColumnFocusTargetOffset(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat,
        anchorY: CGFloat
    ) -> CGFloat? {
        let frame =
            observedMainColumnTargetFrame(
                viewportKey: viewportKey,
                targetID: targetID
            ) ??
            predictedMainColumnTargetFrame(
                cards: cards,
                targetID: targetID,
                viewportHeight: viewportHeight
            )
        guard let frame else {
            return nil
        }

        let clampedAnchorY = min(max(0, anchorY), 1)
        let targetAnchorY = frame.minY + (frame.height * clampedAnchorY)
        return targetAnchorY - (viewportHeight * clampedAnchorY)
    }

    func resolvedMainColumnVisibleRect(
        viewportKey: String,
        viewportHeight: CGFloat
    ) -> CGRect {
        if let visibleRect = mainCanvasScrollCoordinator
            .scrollView(for: viewportKey)?
            .documentVisibleRect
        {
            return visibleRect
        }

        return CGRect(
            x: 0,
            y: resolvedMainColumnCurrentOffsetY(viewportKey: viewportKey),
            width: 1,
            height: viewportHeight
        )
    }

    func predictedMainColumnTargetFrame(
        cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat
    ) -> CGRect? {
        guard let layout = resolvedMainColumnTargetLayout(
            in: cards,
            targetID: targetID,
            viewportHeight: viewportHeight
        ) else {
            return nil
        }
        return CGRect(
            x: 0,
            y: layout.targetMinY,
            width: 1,
            height: layout.targetMaxY - layout.targetMinY
        )
    }

    func observedMainColumnTargetFrame(
        viewportKey: String,
        targetID: UUID
    ) -> CGRect? {
        mainCanvasScrollCoordinator.observedFrame(for: viewportKey, cardID: targetID)
    }

    func resolvedMainColumnBlockFrame(
        viewportKey: String,
        cards: [SceneCard],
        cardIDs: [UUID],
        viewportHeight: CGFloat
    ) -> CGRect? {
        let candidateIDs = cards
            .map(\.id)
            .filter { cardIDs.contains($0) }
        guard !candidateIDs.isEmpty else { return nil }

        var unionFrame: CGRect?
        for cardID in candidateIDs {
            let frame =
                observedMainColumnTargetFrame(
                    viewportKey: viewportKey,
                    targetID: cardID
                ) ??
                predictedMainColumnTargetFrame(
                    cards: cards,
                    targetID: cardID,
                    viewportHeight: viewportHeight
                )
            guard let frame else { continue }
            unionFrame = unionFrame.map { $0.union(frame) } ?? frame
        }
        return unionFrame
    }

    func isMainColumnBlockWithinComfortBand(
        viewportKey: String,
        cards: [SceneCard],
        cardIDs: [UUID],
        viewportHeight: CGFloat
    ) -> Bool {
        guard let frame = resolvedMainColumnBlockFrame(
            viewportKey: viewportKey,
            cards: cards,
            cardIDs: cardIDs,
            viewportHeight: viewportHeight
        ) else {
            return false
        }
        let visibleRect = resolvedMainColumnVisibleRect(
            viewportKey: viewportKey,
            viewportHeight: viewportHeight
        )
        let inset = min(28, visibleRect.height * 0.08)
        return frame.minY >= visibleRect.minY + inset &&
            frame.maxY <= visibleRect.maxY - inset
    }

    func resolvedMainColumnBlockVisibilityTargetOffset(
        viewportKey: String,
        cards: [SceneCard],
        cardIDs: [UUID],
        viewportHeight: CGFloat
    ) -> CGFloat? {
        guard let frame = resolvedMainColumnBlockFrame(
            viewportKey: viewportKey,
            cards: cards,
            cardIDs: cardIDs,
            viewportHeight: viewportHeight
        ) else {
            return nil
        }
        let visibleRect = resolvedMainColumnVisibleRect(
            viewportKey: viewportKey,
            viewportHeight: viewportHeight
        )
        let inset = min(28, visibleRect.height * 0.08)
        if frame.minY < visibleRect.minY + inset {
            return max(0, frame.minY - inset)
        }
        if frame.maxY > visibleRect.maxY - inset {
            return max(0, frame.maxY - (visibleRect.height - inset))
        }
        return visibleRect.origin.y
    }

    func applyMainColumnBlockVisibility(
        viewportKey: String,
        cards: [SceneCard],
        cardIDs: [UUID],
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        animated: Bool
    ) {
        guard let targetOffsetY = resolvedMainColumnBlockVisibilityTargetOffset(
            viewportKey: viewportKey,
            cards: cards,
            cardIDs: cardIDs,
            viewportHeight: viewportHeight
        ) else {
            return
        }

        if let scrollView = mainCanvasScrollCoordinator.scrollView(for: viewportKey) {
            let visible = scrollView.documentVisibleRect
            let documentHeight = scrollView.documentView?.bounds.height ?? 0
            let maxY = max(0, documentHeight - visible.height)
            if animated {
                let resolvedTargetY = CaretScrollCoordinator.resolvedVerticalTargetY(
                    visibleRect: visible,
                    targetY: targetOffsetY,
                    minY: 0,
                    maxY: maxY,
                    snapToPixel: true
                )
                let duration = CaretScrollCoordinator.resolvedVerticalAnimationDuration(
                    currentY: visible.origin.y,
                    targetY: resolvedTargetY,
                    viewportHeight: max(1, visible.height)
                )
                suspendMainColumnViewportCapture(for: duration + 0.06)
                _ = CaretScrollCoordinator.applyAnimatedVerticalScrollIfNeeded(
                    scrollView: scrollView,
                    visibleRect: visible,
                    targetY: targetOffsetY,
                    minY: 0,
                    maxY: maxY,
                    deadZone: 0.5,
                    snapToPixel: true,
                    duration: duration
                )
            } else {
                suspendMainColumnViewportCapture(for: 0.12)
                _ = CaretScrollCoordinator.applyVerticalScrollIfNeeded(
                    scrollView: scrollView,
                    visibleRect: visible,
                    targetY: targetOffsetY,
                    minY: 0,
                    maxY: maxY,
                    deadZone: 0.5,
                    snapToPixel: true
                )
            }
            return
        }

        let orderedCardIDs = cards.map(\.id).filter { cardIDs.contains($0) }
        let anchor: UnitPoint = targetOffsetY <= resolvedMainColumnCurrentOffsetY(viewportKey: viewportKey) ? .top : .bottom
        let anchorCardID = anchor == .top ? orderedCardIDs.first : orderedCardIDs.last
        guard let anchorCardID else { return }
        suspendMainColumnViewportCapture(for: animated ? 0.32 : 0.12)
        if animated {
            withAnimation(quickEaseAnimation) {
                proxy.scrollTo(anchorCardID, anchor: anchor)
            }
        } else {
            performWithoutAnimation {
                proxy.scrollTo(anchorCardID, anchor: anchor)
            }
        }
    }

    func isObservedMainColumnFocusTargetVisible(
        viewportKey: String,
        targetID: UUID,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool
    ) -> Bool {
        guard let frame = observedMainColumnTargetFrame(
            viewportKey: viewportKey,
            targetID: targetID
        ) else {
            return false
        }

        let visibleRect = resolvedMainColumnVisibleRect(
            viewportKey: viewportKey,
            viewportHeight: viewportHeight
        )
        let visibleMinY = frame.minY - visibleRect.origin.y
        let visibleMaxY = frame.maxY - visibleRect.origin.y
        if prefersTopAnchor {
            return abs(visibleMinY) <= 24 && visibleMaxY > 24
        }

        let inset = min(24, visibleRect.height * 0.15)
        return visibleMaxY > inset && visibleMinY < (visibleRect.height - inset)
    }

    func isObservedMainColumnFocusTargetAligned(
        viewportKey: String,
        targetID: UUID,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool
    ) -> Bool {
        guard let frame = observedMainColumnTargetFrame(
            viewportKey: viewportKey,
            targetID: targetID
        ) else {
            return false
        }

        let visibleRect = resolvedMainColumnVisibleRect(
            viewportKey: viewportKey,
            viewportHeight: viewportHeight
        )
        let anchorY: CGFloat = prefersTopAnchor ? 0 : 0.4
        let visibleAnchorY = (frame.minY + (frame.height * anchorY)) - visibleRect.origin.y
        let desiredAnchorY = visibleRect.height * anchorY
        let tolerance: CGFloat = prefersTopAnchor ? 16 : 22
        return abs(visibleAnchorY - desiredAnchorY) <= tolerance
    }

    @discardableResult
    func performMainColumnNativeFocusScroll(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat,
        anchorY: CGFloat,
        animated: Bool
    ) -> Bool {
        guard observedMainColumnTargetFrame(
            viewportKey: viewportKey,
            targetID: targetID
        ) != nil else {
            return false
        }
        guard let scrollView = mainCanvasScrollCoordinator.scrollView(for: viewportKey) else {
            return false
        }
        let visible = scrollView.documentVisibleRect
        let resolvedViewportHeight = max(1, visible.height)
        guard let targetOffsetY = resolvedMainColumnFocusTargetOffset(
            viewportKey: viewportKey,
            cards: cards,
            targetID: targetID,
            viewportHeight: resolvedViewportHeight,
            anchorY: anchorY
        ) else {
            return false
        }

        let documentHeight = scrollView.documentView?.bounds.height ?? 0
        let maxY = max(0, documentHeight - visible.height)
        let targetReachable = maxY + 0.5 >= targetOffsetY

        if animated {
            guard targetReachable || targetOffsetY <= 0.5 else { return false }
            let resolvedTargetY = CaretScrollCoordinator.resolvedVerticalTargetY(
                visibleRect: visible,
                targetY: targetOffsetY,
                minY: 0,
                maxY: maxY,
                snapToPixel: true
            )
            guard abs(resolvedTargetY - visible.origin.y) > 0.5 else { return true }
            let appliedDuration = CaretScrollCoordinator.resolvedVerticalAnimationDuration(
                currentY: visible.origin.y,
                targetY: resolvedTargetY,
                viewportHeight: resolvedViewportHeight
            )
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                axis: "vertical",
                engine: "native",
                animated: true,
                target: "\(viewportKey)|\(targetID.uuidString)",
                expectedDuration: appliedDuration
            )
            suspendMainColumnViewportCapture(for: appliedDuration + 0.06)
            _ = CaretScrollCoordinator.applyAnimatedVerticalScrollIfNeeded(
                scrollView: scrollView,
                visibleRect: visible,
                targetY: targetOffsetY,
                minY: 0,
                maxY: maxY,
                deadZone: 0.5,
                snapToPixel: true,
                duration: appliedDuration
            )
            bounceDebugLog(
                "nativeMainColumnFocusScroll key=\(viewportKey) target=\(debugCardIDString(targetID)) " +
                "targetY=\(debugCGFloat(resolvedTargetY)) visibleY=\(debugCGFloat(visible.origin.y)) " +
                "duration=\(String(format: "%.2f", appliedDuration)) viewport=\(debugCGFloat(resolvedViewportHeight))"
            )
            mainWorkspacePhase0Log(
                "native-focus-scroll",
                "mode=animated key=\(viewportKey) target=\(mainWorkspacePhase0CardID(targetID)) " +
                "visibleY=\(visible.origin.y) targetY=\(resolvedTargetY) duration=\(appliedDuration) viewport=\(resolvedViewportHeight)"
            )
            return true
        }

        MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
            ownerKey: mainCanvasDiagnosticsOwnerKey,
            axis: "vertical",
            engine: "native",
            animated: false,
            target: "\(viewportKey)|\(targetID.uuidString)",
            expectedDuration: 0
        )
        suspendMainColumnViewportCapture(for: 0.12)
        let applied = CaretScrollCoordinator.applyVerticalScrollIfNeeded(
            scrollView: scrollView,
            visibleRect: visible,
            targetY: targetOffsetY,
            minY: 0,
            maxY: maxY,
            deadZone: 0.5,
            snapToPixel: true
        )
        if applied {
            bounceDebugLog(
                "nativeMainColumnFocusScroll immediate key=\(viewportKey) target=\(debugCardIDString(targetID)) " +
                "targetY=\(debugCGFloat(targetOffsetY)) visibleY=\(debugCGFloat(visible.origin.y))"
            )
            mainWorkspacePhase0Log(
                "native-focus-scroll",
                "mode=immediate key=\(viewportKey) target=\(mainWorkspacePhase0CardID(targetID)) " +
                "visibleY=\(visible.origin.y) targetY=\(targetOffsetY) viewport=\(resolvedViewportHeight)"
            )
        }
        let resolvedTargetY = CaretScrollCoordinator.resolvedVerticalTargetY(
            visibleRect: visible,
            targetY: targetOffsetY,
            minY: 0,
            maxY: maxY,
            snapToPixel: true
        )
        let currentY = scrollView.contentView.bounds.origin.y
        return targetReachable && abs(resolvedTargetY - currentY) <= 0.5
    }

    func shouldSkipMainColumnFocusScroll(
        targetID: UUID,
        cards: [SceneCard],
        level: Int,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool
    ) -> Bool {
        guard prefersTopAnchor else { return false }
        guard activeCardID == targetID else { return false }
        let viewportKey = mainColumnViewportStorageKey(level: level)
        guard let frame = observedMainColumnTargetFrame(
            viewportKey: viewportKey,
            targetID: targetID
        ) else {
            return false
        }

        let visibleRect = resolvedMainColumnVisibleRect(
            viewportKey: viewportKey,
            viewportHeight: viewportHeight
        )
        let deadZone: CGFloat = 3
        let delta = frame.minY - visibleRect.origin.y
        let shouldSkip = abs(delta) <= deadZone
        if shouldSkip {
            bounceDebugLog(
                "shouldSkipMainColumnFocusScroll target=\(debugCardIDString(targetID)) viewportKey=\(viewportKey) " +
                "offset=\(debugCGFloat(visibleRect.origin.y)) targetMin=\(debugCGFloat(frame.minY)) " +
                "delta=\(debugCGFloat(delta)) " +
                "\(debugMainColumnObservedTargetSummary(viewportKey: viewportKey, targetID: targetID, offsetY: visibleRect.origin.y))"
            )
        }
        return shouldSkip
    }

    func shouldAutoAlignMainColumn(cards: [SceneCard], activeID: UUID?) -> Bool {
        guard let activeID else { return false }
        if cards.contains(where: { $0.id == activeID }) {
            return true
        }
        if cards.contains(where: { activeAncestorIDs.contains($0.id) }) {
            return true
        }
        return resolvedMainColumnFocusTargetID(in: cards) != nil
    }

    func resolvedMainColumnLayoutSnapshot(
        in cards: [SceneCard],
        viewportHeight: CGFloat
    ) -> MainColumnLayoutSnapshot {
        let layoutResolveStartedAt = CACurrentMediaTime()
        let cardIDs = cards.map(\.id)
        let editingCardInColumn = editingCardID.flatMap { editingID in
            cards.first(where: { $0.id == editingID })
        }
        let editingLiveHeightOverride = editingCardInColumn.flatMap { card in
            resolvedMainCardLiveEditingHeightOverride(for: card)
        }
        let editingHeightBucket = editingLiveHeightOverride.map { Int(($0 * 10).rounded()) } ?? -1
        let layoutKey = MainColumnLayoutCacheKey(
            recordsVersion: scenario.cardsVersion,
            contentVersion: scenario.cardContentSaveVersion,
            viewportHeightBucket: Int(viewportHeight.rounded()),
            fontSizeBucket: Int((fontSize * 10).rounded()),
            lineSpacingBucket: Int((mainCardLineSpacingValue * 10).rounded()),
            editingCardID: editingCardInColumn?.id,
            editingHeightBucket: editingHeightBucket,
            cardIDs: cardIDs
        )
        let containsEditingCard = editingCardInColumn != nil
        if let cached = mainColumnLayoutSnapshotByKey[layoutKey] {
            MainCanvasNavigationDiagnostics.shared.recordColumnLayoutResolve(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                cardCount: cards.count,
                viewportHeight: viewportHeight,
                cacheHit: true,
                containsEditingCard: containsEditingCard,
                durationMilliseconds: (CACurrentMediaTime() - layoutResolveStartedAt) * 1000
            )
            return cached
        }

        let centerGapHeight = max(0, CGFloat(mainCardVerticalGap))
        var cursorY = viewportHeight * 0.4
        var framesByCardID: [UUID: MainColumnLayoutFrame] = [:]
        framesByCardID.reserveCapacity(cards.count)

        for index in cards.indices {
            let card = cards[index]
            let cardHeight = resolvedMainCardHeight(
                for: card,
                liveEditingHeightOverride: card.id == editingCardInColumn?.id ? editingLiveHeightOverride : nil
            )
            let cardMinY = cursorY
            let cardMaxY = cardMinY + cardHeight
            framesByCardID[card.id] = MainColumnLayoutFrame(minY: cardMinY, maxY: cardMaxY)

            cursorY = cardMaxY
            if index < cards.count - 1 {
                let next = cards[index + 1]
                if card.parent?.id != next.parent?.id {
                    cursorY += mainParentGroupSeparatorHeight
                }
                cursorY += centerGapHeight
            }
        }

        let snapshot = MainColumnLayoutSnapshot(
            key: layoutKey,
            framesByCardID: framesByCardID,
            orderedCardIDs: cardIDs,
            contentBottomY: cursorY
        )
        mainColumnLayoutSnapshotByKey[layoutKey] = snapshot
        MainCanvasNavigationDiagnostics.shared.recordColumnLayoutResolve(
            ownerKey: mainCanvasDiagnosticsOwnerKey,
            cardCount: cards.count,
            viewportHeight: viewportHeight,
            cacheHit: false,
            containsEditingCard: containsEditingCard,
            durationMilliseconds: (CACurrentMediaTime() - layoutResolveStartedAt) * 1000
        )
        return snapshot
    }

    func resolvedMainColumnTargetLayout(
        in cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat
    ) -> (targetMinY: CGFloat, targetMaxY: CGFloat)? {
        guard let frame = resolvedMainColumnLayoutSnapshot(in: cards, viewportHeight: viewportHeight)
            .framesByCardID[targetID] else { return nil }
        return (frame.minY, frame.maxY)
    }

    func mainColumnScrollCacheKey(level: Int, parent: SceneCard?) -> String {
        let parentKey = parent?.id.uuidString ?? "root"
        return "\(level)|\(parentKey)"
    }

    @ViewBuilder
    func mainColumnScrollObserver(
        viewportKey: String,
        level: Int,
        parent: SceneCard?,
        cards: [SceneCard],
        viewportHeight: CGFloat
    ) -> some View {
        MainColumnScrollViewAccessor(
            scrollCoordinator: mainCanvasScrollCoordinator,
            columnKey: viewportKey,
            storedOffsetY: mainColumnViewportOffsetByKey[viewportKey]
        ) { originY in
            guard !showFocusMode else { return }
            let previous = mainColumnViewportOffsetByKey[viewportKey] ?? 0
            let suspended = Date() < mainColumnViewportCaptureSuspendedUntil
            let visibleSummary = debugMainColumnVisibleCardSummary(
                viewportKey: viewportKey,
                cards: cards,
                viewportHeight: viewportHeight,
                offsetY: originY
            )
            if suspended, abs(previous - originY) > 0.5 {
                bounceDebugLog(
                    "viewportOffset ignored level=\(level) key=\(viewportKey) requestKey=\(mainColumnScrollCacheKey(level: level, parent: parent)) " +
                    "prev=\(debugCGFloat(previous)) new=\(debugCGFloat(originY)) " +
                    "suspendedUntil=\(mainColumnViewportCaptureSuspendedUntil.timeIntervalSince1970) " +
                    "\(debugFocusStateSummary()) visible=\(visibleSummary)"
                )
                return
            }
            if abs(previous - originY) > 0.5 {
                mainColumnViewportOffsetByKey[viewportKey] = originY
                bounceDebugLog(
                    "viewportOffset level=\(level) key=\(viewportKey) requestKey=\(mainColumnScrollCacheKey(level: level, parent: parent)) " +
                    "prev=\(debugCGFloat(previous)) new=\(debugCGFloat(originY)) " +
                    "\(debugFocusStateSummary()) visible=\(visibleSummary)"
                )
            }
        }
    }

    func suspendMainColumnViewportCapture(for duration: TimeInterval) {
        let previous = mainColumnViewportCaptureSuspendedUntil
        let until = Date().addingTimeInterval(duration)
        if until > mainColumnViewportCaptureSuspendedUntil {
            mainColumnViewportCaptureSuspendedUntil = until
            bounceDebugLog(
                "suspendMainColumnViewportCapture duration=\(String(format: "%.2f", duration)) " +
                "previousUntil=\(previous.timeIntervalSince1970) newUntil=\(until.timeIntervalSince1970) " +
                "\(debugFocusStateSummary())"
            )
        }
    }

    func mainColumnViewportStorageKey(level: Int) -> String {
        if level <= 1 || isActiveCardRoot {
            return "level:\(level)|all"
        }
        let category = activeCategory ?? "all"
        return "level:\(level)|category:\(category)"
    }

    func shouldPreserveMainColumnViewportOnReveal(level: Int, storageKey: String, newActiveID: UUID?) -> Bool {
        guard level > 1 else { return false }
        guard (mainColumnViewportOffsetByKey[storageKey] ?? 0) > 1 else { return false }
        guard mainColumnViewportRestoreUntil > Date() else { return false }
        guard !shouldSuppressMainArrowRepeatAnimation() else { return false }
        guard let newActiveID, scenario.rootCards.contains(where: { $0.id == newActiveID }) else { return false }
        bounceDebugLog(
            "preserveMainColumnViewportOnReveal level=\(level) key=\(storageKey) " +
            "offset=\(debugCGFloat(mainColumnViewportOffsetByKey[storageKey] ?? 0)) " +
            "restoreUntil=\(mainColumnViewportRestoreUntil.timeIntervalSince1970) newActive=\(debugCardIDString(newActiveID)) " +
            "\(debugFocusStateSummary())"
        )
        return true
    }

    func shouldSuppressMainArrowRepeatAnimation() -> Bool {
        mainArrowRepeatAnimationSuppressedUntil > Date()
    }

    func cancelPendingMainColumnFocusWorkItem(for viewportKey: String) {
        bounceDebugLog("cancelPendingMainColumnFocusWorkItem key=\(viewportKey)")
        mainCanvasScrollCoordinator.cancelMotionTask(
            axis: .vertical,
            viewportKey: viewportKey,
            kind: .focus
        )
    }

    func cancelPendingMainColumnFocusVerificationWorkItem(for viewportKey: String) {
        bounceDebugLog("cancelPendingMainColumnFocusVerificationWorkItem key=\(viewportKey)")
        mainCanvasScrollCoordinator.cancelMotionTask(
            axis: .vertical,
            viewportKey: viewportKey,
            kind: .verification
        )
    }

    func cancelAllPendingMainColumnFocusWork() {
        mainCanvasScrollCoordinator.cancelActiveMotionSession(reason: "cancelAllPendingMainColumnFocusWork")
        mainColumnLastFocusRequestByKey.removeAll(keepingCapacity: true)
    }

    func resolvedMainColumnFocusTargetID(in cards: [SceneCard]) -> UUID? {
        if let id = activeCardID, cards.contains(where: { $0.id == id }) {
            return id
        }
        if let target = cards.first(where: { activeAncestorIDs.contains($0.id) }) {
            return target.id
        }
        if let activeID = activeCardID,
           let activeCard = findCard(by: activeID) {
            return resolvedMainColumnPreferredDescendantTargetID(in: cards, startingFrom: activeCard)
        }
        return nil
    }

    private func resolvedMainColumnPreferredDescendantTargetID(
        in cards: [SceneCard],
        startingFrom root: SceneCard
    ) -> UUID? {
        let visibleCardIDs = Set(cards.map(\.id))
        var current: SceneCard? = root
        var visited: Set<UUID> = []

        while let node = current, visited.insert(node.id).inserted {
            let children = node.children
            guard !children.isEmpty else { return nil }

            let preferredChild =
                children.first(where: { $0.id == node.lastSelectedChildID })
                ?? children.first

            guard let preferredChild else { return nil }
            if visibleCardIDs.contains(preferredChild.id) {
                return preferredChild.id
            }
            current = preferredChild
        }

        return nil
    }

    func isMainColumnFocusTargetVisible(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool
    ) -> Bool {
        _ = cards
        return isObservedMainColumnFocusTargetVisible(
            viewportKey: viewportKey,
            targetID: targetID,
            viewportHeight: viewportHeight,
            prefersTopAnchor: prefersTopAnchor
        )
    }

    func isMainColumnFocusTargetAligned(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool
    ) -> Bool {
        _ = cards
        return isObservedMainColumnFocusTargetAligned(
            viewportKey: viewportKey,
            targetID: targetID,
            viewportHeight: viewportHeight,
            prefersTopAnchor: prefersTopAnchor
        )
    }

    func applyMainColumnFocusAlignment(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool,
        animated: Bool
    ) {
        let defaultAnchor = UnitPoint(x: 0.5, y: 0.4)
        let focusAnchor = prefersTopAnchor ? UnitPoint(x: 0.5, y: 0.0) : defaultAnchor
        let focusAnchorY = prefersTopAnchor ? CGFloat(0) : CGFloat(defaultAnchor.y)

        if performMainColumnNativeFocusScroll(
            viewportKey: viewportKey,
            cards: cards,
            targetID: targetID,
            viewportHeight: viewportHeight,
            anchorY: focusAnchorY,
            animated: animated
        ) {
            return
        }

        suspendMainColumnViewportCapture(for: animated ? 0.32 : 0.12)
        if animated {
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                axis: "vertical",
                engine: "proxy",
                animated: true,
                target: "\(viewportKey)|\(targetID.uuidString)",
                expectedDuration: 0.24
            )
            withAnimation(quickEaseAnimation) {
                proxy.scrollTo(targetID, anchor: focusAnchor)
            }
        } else {
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                axis: "vertical",
                engine: "proxy",
                animated: false,
                target: "\(viewportKey)|\(targetID.uuidString)",
                expectedDuration: 0
            )
            performWithoutAnimation {
                proxy.scrollTo(targetID, anchor: focusAnchor)
            }
        }
    }

    func resolvedMainColumnVisibilityTargetOffset(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool,
        editingRevealEdge: MainEditingViewportRevealEdge?
    ) -> CGFloat? {
        let frame =
            observedMainColumnTargetFrame(
                viewportKey: viewportKey,
                targetID: targetID
            ) ??
            predictedMainColumnTargetFrame(
                cards: cards,
                targetID: targetID,
                viewportHeight: viewportHeight
            )
        guard let frame else { return nil }

        let visibleRect = resolvedMainColumnVisibleRect(
            viewportKey: viewportKey,
            viewportHeight: viewportHeight
        )
        let inset = min(28, visibleRect.height * 0.08)
        let mainEditingCaretBottomPadding: CGFloat = 120
        if let editingRevealEdge {
            switch editingRevealEdge {
            case .top:
                // Entering a card at its start should only reveal the first line,
                // not snap the whole tall card to the top of the viewport.
                return max(0, frame.minY - (visibleRect.height - inset))
            case .bottom:
                // Match the main editor caret-visibility bottom padding so the
                // card-level reveal and the follow-up caret ensure resolve to
                // the same resting offset instead of causing a second nudge.
                return max(0, frame.maxY - (visibleRect.height - mainEditingCaretBottomPadding))
            }
        }
        if prefersTopAnchor {
            return max(0, frame.minY)
        }
        if frame.minY < visibleRect.minY + inset {
            return max(0, frame.minY - inset)
        }
        if frame.maxY > visibleRect.maxY - inset {
            return frame.maxY - (visibleRect.height - inset)
        }
        return visibleRect.origin.y
    }

    @discardableResult
    func performMainColumnNativeVisibilityScroll(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool,
        editingRevealEdge: MainEditingViewportRevealEdge?,
        animated: Bool
    ) -> Bool {
        guard observedMainColumnTargetFrame(
            viewportKey: viewportKey,
            targetID: targetID
        ) != nil else {
            return false
        }
        guard let scrollView = mainCanvasScrollCoordinator.scrollView(for: viewportKey) else {
            return false
        }
        let visible = scrollView.documentVisibleRect
        let resolvedViewportHeight = max(1, visible.height)
        guard let targetOffsetY = resolvedMainColumnVisibilityTargetOffset(
            viewportKey: viewportKey,
            cards: cards,
            targetID: targetID,
            viewportHeight: resolvedViewportHeight,
            prefersTopAnchor: prefersTopAnchor,
            editingRevealEdge: editingRevealEdge
        ) else {
            return false
        }

        let documentHeight = scrollView.documentView?.bounds.height ?? 0
        let maxY = max(0, documentHeight - visible.height)
        let targetReachable = maxY + 0.5 >= targetOffsetY

        if animated {
            guard targetReachable || targetOffsetY <= 0.5 else { return false }
            let resolvedTargetY = CaretScrollCoordinator.resolvedVerticalTargetY(
                visibleRect: visible,
                targetY: targetOffsetY,
                minY: 0,
                maxY: maxY,
                snapToPixel: true
            )
            guard abs(resolvedTargetY - visible.origin.y) > 0.5 else { return true }
            let appliedDuration = CaretScrollCoordinator.resolvedVerticalAnimationDuration(
                currentY: visible.origin.y,
                targetY: resolvedTargetY,
                viewportHeight: resolvedViewportHeight
            )
            suspendMainColumnViewportCapture(for: appliedDuration + 0.06)
            _ = CaretScrollCoordinator.applyAnimatedVerticalScrollIfNeeded(
                scrollView: scrollView,
                visibleRect: visible,
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
        _ = CaretScrollCoordinator.applyVerticalScrollIfNeeded(
            scrollView: scrollView,
            visibleRect: visible,
            targetY: targetOffsetY,
            minY: 0,
            maxY: maxY,
            deadZone: 0.5,
            snapToPixel: true
        )
        let resolvedTargetY = CaretScrollCoordinator.resolvedVerticalTargetY(
            visibleRect: visible,
            targetY: targetOffsetY,
            minY: 0,
            maxY: maxY,
            snapToPixel: true
        )
        let currentY = scrollView.contentView.bounds.origin.y
        return targetReachable && abs(resolvedTargetY - currentY) <= 0.5
    }

    func applyMainColumnFocusVisibility(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool,
        editingRevealEdge: MainEditingViewportRevealEdge?,
        animated: Bool
    ) {
        if performMainColumnNativeVisibilityScroll(
            viewportKey: viewportKey,
            cards: cards,
            targetID: targetID,
            viewportHeight: viewportHeight,
            prefersTopAnchor: prefersTopAnchor,
            editingRevealEdge: editingRevealEdge,
            animated: animated
        ) {
            return
        }

        let visibleRect = resolvedMainColumnVisibleRect(
            viewportKey: viewportKey,
            viewportHeight: viewportHeight
        )
        let frame =
            observedMainColumnTargetFrame(
                viewportKey: viewportKey,
                targetID: targetID
            ) ??
            predictedMainColumnTargetFrame(
                cards: cards,
                targetID: targetID,
                viewportHeight: viewportHeight
            )
        guard let frame else { return }

        let inset = min(28, visibleRect.height * 0.08)
        let anchor: UnitPoint
        if let editingRevealEdge {
            anchor = editingRevealEdge == .top ? .top : .bottom
        } else {
            let useTopAnchor = prefersTopAnchor || frame.minY < visibleRect.minY + inset
            anchor = useTopAnchor ? .top : .bottom
        }

        suspendMainColumnViewportCapture(for: animated ? 0.32 : 0.12)
        if animated {
            withAnimation(quickEaseAnimation) {
                proxy.scrollTo(targetID, anchor: anchor)
            }
        } else {
            performWithoutAnimation {
                proxy.scrollTo(targetID, anchor: anchor)
            }
        }
    }

    func scheduleMainColumnFocusVerification(
        viewportKey: String,
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        targetID: UUID,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool,
        keepVisibleOnly: Bool,
        editingRevealEdge: MainEditingViewportRevealEdge?,
        animated: Bool,
        attempt: Int = 0,
        participantHandle: MainCanvasScrollCoordinator.MotionParticipantHandle? = nil,
        allowsEditingTransitionBypass: Bool = false
    ) {
        cancelPendingMainColumnFocusVerificationWorkItem(for: viewportKey)
        if shouldSuppressMainColumnFocusVerificationDuringEditing(
            allowsEditingTransitionBypass: allowsEditingTransitionBypass,
            targetCardID: targetID
        ) {
            return
        }
        let delay = mainCanvasScrollCoordinator.motionPolicy.verificationDelay(
            animated: animated,
            attempt: attempt
        )
        let requestKey = mainColumnScrollCacheKey(level: level, parent: parent)
        var verificationWorkItem: DispatchWorkItem?
        verificationWorkItem = DispatchWorkItem {
            defer {
                mainCanvasScrollCoordinator.clearMotionTask(
                    kind: .verification,
                    handle: participantHandle
                )
            }

            guard !showFocusMode else { return }
            guard acceptsKeyboardInput else { return }
            guard !shouldSuppressMainColumnFocusVerificationDuringEditing(
                allowsEditingTransitionBypass: allowsEditingTransitionBypass,
                targetCardID: targetID
            ) else { return }
            guard mainCanvasScrollCoordinator.isMotionParticipantCurrent(participantHandle) else { return }
            guard resolvedMainColumnFocusTargetID(in: cards) == targetID else {
                mainCanvasScrollCoordinator.updateMotionParticipantState(.cancelled, handle: participantHandle)
                return
            }
            let hasObservedTargetFrame = observedMainColumnTargetFrame(
                viewportKey: viewportKey,
                targetID: targetID
            ) != nil
            let targetIsVisible = isMainColumnFocusTargetVisible(
                viewportKey: viewportKey,
                cards: cards,
                targetID: targetID,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor
            )
            let targetIsAligned = hasObservedTargetFrame && isMainColumnFocusTargetAligned(
                viewportKey: viewportKey,
                cards: cards,
                targetID: targetID,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor
            )
            if hasObservedTargetFrame && targetIsVisible && (keepVisibleOnly || targetIsAligned) {
                mainCanvasScrollCoordinator.updateMotionParticipantState(.aligned, handle: participantHandle)
                return
            }
            if !hasObservedTargetFrame {
                guard attempt < 4 else {
                    mainCanvasScrollCoordinator.updateMotionParticipantState(.timedOut, handle: participantHandle)
                    return
                }
                mainCanvasScrollCoordinator.updateMotionParticipantState(.waiting, handle: participantHandle)
                scheduleMainColumnFocusVerification(
                    viewportKey: viewportKey,
                    cards: cards,
                    level: level,
                    parent: parent,
                    targetID: targetID,
                    proxy: proxy,
                    viewportHeight: viewportHeight,
                    prefersTopAnchor: prefersTopAnchor,
                    keepVisibleOnly: keepVisibleOnly,
                    editingRevealEdge: editingRevealEdge,
                    animated: animated,
                    attempt: attempt + 1,
                    participantHandle: participantHandle,
                    allowsEditingTransitionBypass: allowsEditingTransitionBypass
                )
                return
            }

            bounceDebugLog(
                "verifyMainColumnFocus retry level=\(level) viewportKey=\(viewportKey) " +
                "attempt=\(attempt) target=\(debugCardIDString(targetID)) " +
                "observed=\(hasObservedTargetFrame) " +
                "offset=\(debugCGFloat(resolvedMainColumnCurrentOffsetY(viewportKey: viewportKey))) " +
                "\(debugMainColumnObservedTargetSummary(viewportKey: viewportKey, targetID: targetID, offsetY: resolvedMainColumnCurrentOffsetY(viewportKey: viewportKey)))"
            )
            mainColumnLastFocusRequestByKey.removeValue(forKey: requestKey)
            let retryAnimated = animated && hasObservedTargetFrame
            MainCanvasNavigationDiagnostics.shared.recordVerificationRetry(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                viewportKey: viewportKey,
                attempt: attempt,
                targetID: targetID,
                observedFrame: hasObservedTargetFrame,
                animatedRetry: retryAnimated
            )
            mainCanvasScrollCoordinator.updateMotionParticipantState(.moving, handle: participantHandle)
            if keepVisibleOnly {
                applyMainColumnFocusVisibility(
                    viewportKey: viewportKey,
                    cards: cards,
                    targetID: targetID,
                    proxy: proxy,
                    viewportHeight: viewportHeight,
                    prefersTopAnchor: prefersTopAnchor,
                    editingRevealEdge: editingRevealEdge,
                    animated: retryAnimated
                )
            } else {
                applyMainColumnFocusAlignment(
                    viewportKey: viewportKey,
                    cards: cards,
                    targetID: targetID,
                    proxy: proxy,
                    viewportHeight: viewportHeight,
                    prefersTopAnchor: prefersTopAnchor,
                    animated: retryAnimated
                )
            }
            guard attempt < (hasObservedTargetFrame ? 2 : 4) else { return }
            scheduleMainColumnFocusVerification(
                viewportKey: viewportKey,
                cards: cards,
                level: level,
                parent: parent,
                targetID: targetID,
                proxy: proxy,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor,
                keepVisibleOnly: keepVisibleOnly,
                editingRevealEdge: editingRevealEdge,
                animated: animated,
                attempt: attempt + 1,
                participantHandle: participantHandle,
                allowsEditingTransitionBypass: allowsEditingTransitionBypass
            )
        }
        if let verificationWorkItem {
            mainCanvasScrollCoordinator.replaceMotionTask(
                verificationWorkItem,
                kind: .verification,
                handle: participantHandle
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: verificationWorkItem)
        }
    }

    func handleMainColumnNavigationSettle(
        viewportKey: String,
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        intent: MainCanvasScrollCoordinator.NavigationIntent
    ) {
        guard !showFocusMode else { return }
        guard acceptsKeyboardInput else { return }
        guard editingCardID == nil else { return }
        cancelPendingMainColumnFocusWorkItem(for: viewportKey)
        cancelPendingMainColumnFocusVerificationWorkItem(for: viewportKey)
        guard shouldAutoAlignMainColumn(cards: cards, activeID: activeCardID) else { return }
        guard let participantHandle = mainCanvasScrollCoordinator.claimMotionParticipant(
            for: viewportKey,
            axis: .vertical,
            intent: intent
        ) else { return }
        mainCanvasScrollCoordinator.closeJoinWindowIfCurrentSessionMatches(participantHandle)
        bounceDebugLog(
            "navigationSettle level=\(level) viewportKey=\(viewportKey) " +
            "active=\(debugCardIDString(activeCardID)) " +
            "offset=\(debugCGFloat(mainColumnViewportOffsetByKey[viewportKey] ?? 0)) " +
            "visible=\(debugMainColumnVisibleCardSummary(viewportKey: viewportKey, cards: cards, viewportHeight: viewportHeight, offsetY: mainColumnViewportOffsetByKey[viewportKey] ?? 0))"
        )
        scrollToFocus(
            in: cards,
            level: level,
            parent: parent,
            proxy: proxy,
            viewportHeight: viewportHeight,
            animated: false,
            reason: "navigationSettle",
            participantHandle: participantHandle
        )
    }

    func scheduleMainColumnActiveCardFocus(
        viewportKey: String,
        expectedActiveID: UUID?,
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        keepVisibleOnly: Bool,
        editingRevealEdge: MainEditingViewportRevealEdge?,
        forceAlignment: Bool,
        animated: Bool,
        focusDelayOverride: TimeInterval? = nil,
        participantHandle: MainCanvasScrollCoordinator.MotionParticipantHandle? = nil,
        allowsEditingTransitionBypass: Bool = false
    ) {
        cancelPendingMainColumnFocusWorkItem(for: viewportKey)
        bounceDebugLog(
            "scheduleMainColumnActiveCardFocus level=\(level) viewportKey=\(viewportKey) " +
            "expected=\(debugCardIDString(expectedActiveID)) parent=\(debugCardToken(parent)) " +
            "cards=\(cards.count) force=\(forceAlignment) animated=\(animated) " +
            "delay=\(debugCGFloat(CGFloat(focusDelayOverride ?? mainCanvasScrollCoordinator.motionPolicy.activeFocusDelay(animated: animated)))) \(debugFocusStateSummary())"
        )
        let focusDelay = focusDelayOverride ?? mainCanvasScrollCoordinator.motionPolicy.activeFocusDelay(animated: animated)
        let workItem = DispatchWorkItem {
            defer {
                mainCanvasScrollCoordinator.clearMotionTask(
                    kind: .focus,
                    handle: participantHandle
                )
            }
            bounceDebugLog(
                "executeMainColumnActiveCardFocus level=\(level) viewportKey=\(viewportKey) " +
                "expected=\(debugCardIDString(expectedActiveID)) current=\(debugCardIDString(activeCardID)) " +
                "\(debugFocusStateSummary())"
            )
            guard mainCanvasScrollCoordinator.isMotionParticipantCurrent(participantHandle) else {
                bounceDebugLog(
                    "activeCardFocus staleSession level=\(level) viewportKey=\(viewportKey)"
                )
                return
            }
            guard activeCardID == expectedActiveID else {
                bounceDebugLog(
                    "activeCardFocus stale level=\(level) viewportKey=\(viewportKey) " +
                    "expected=\(expectedActiveID?.uuidString ?? "nil") current=\(activeCardID?.uuidString ?? "nil")"
                )
                mainCanvasScrollCoordinator.updateMotionParticipantState(.cancelled, handle: participantHandle)
                return
            }
            scrollToFocus(
                in: cards,
                level: level,
                parent: parent,
                proxy: proxy,
                viewportHeight: viewportHeight,
                keepVisibleOnly: keepVisibleOnly,
                editingRevealEdge: editingRevealEdge,
                forceAlignment: forceAlignment,
                animated: animated,
                reason: "activeCardChange",
                participantHandle: participantHandle,
                allowsEditingTransitionBypass: allowsEditingTransitionBypass
            )
        }
        mainCanvasScrollCoordinator.replaceMotionTask(
            workItem,
            kind: .focus,
            handle: participantHandle
        )
        if focusDelay <= 0 {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + focusDelay, execute: workItem)
        }
    }
}
