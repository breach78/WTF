import SwiftUI
import AppKit
import QuartzCore
import UniformTypeIdentifiers

extension ScenarioWriterView {

    func scrollToFocus(
        in cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        keepVisibleOnly: Bool = false,
        editingRevealEdge: MainEditingViewportRevealEdge? = nil,
        forceAlignment: Bool = false,
        animated: Bool = true,
        reason: String = "unspecified",
        participantHandle: MainCanvasScrollCoordinator.MotionParticipantHandle? = nil,
        allowsEditingTransitionBypass: Bool = false
    ) {
        guard acceptsKeyboardInput else { return }
        let requestKey = mainColumnScrollCacheKey(level: level, parent: parent)
        let viewportKey = mainColumnViewportStorageKey(level: level)
        guard mainCanvasScrollCoordinator.isMotionParticipantCurrent(participantHandle) else { return }
        mainWorkspacePhase0Log(
            "scroll-to-focus-request",
            "reason=\(reason) level=\(level) active=\(mainWorkspacePhase0CardID(activeCardID)) " +
            "editing=\(mainWorkspacePhase0CardID(editingCardID)) keepVisible=\(keepVisibleOnly) " +
            "edge=\(String(describing: editingRevealEdge)) force=\(forceAlignment) animated=\(animated) " +
            "session=\(participantHandle.map { "\($0.sessionID):\($0.revision):\($0.viewportKey)" } ?? "nil")"
        )

        guard let idToScroll = resolvedMainColumnFocusTargetID(in: cards) else {
            bounceDebugLog(
                "scrollToFocus noTarget reason=\(reason) key=\(requestKey) viewportKey=\(viewportKey) " +
                "\(debugFocusStateSummary())"
            )
            mainColumnLastFocusRequestByKey.removeValue(forKey: requestKey)
            cancelPendingMainColumnFocusVerificationWorkItem(for: viewportKey)
            mainCanvasScrollCoordinator.updateMotionParticipantState(.cancelled, handle: participantHandle)
            return
        }

        let currentOffsetY = resolvedMainColumnCurrentOffsetY(viewportKey: viewportKey)
        let targetLayout = resolvedMainColumnTargetLayout(
            in: cards,
            targetID: idToScroll,
            viewportHeight: viewportHeight
        )
        let targetHeight = targetLayout.map { $0.targetMaxY - $0.targetMinY }
            ?? findCard(by: idToScroll).map { resolvedMainCardHeight(for: $0) }
            ?? 0
        let prefersTopAnchor = targetHeight > viewportHeight
        let request = MainColumnFocusRequest(
            targetID: idToScroll,
            prefersTopAnchor: prefersTopAnchor,
            keepVisibleOnly: keepVisibleOnly,
            editingRevealEdge: editingRevealEdge,
            cardsCount: cards.count,
            firstCardID: cards.first?.id,
            lastCardID: cards.last?.id,
            viewportHeightBucket: Int(viewportHeight.rounded())
        )
        if !forceAlignment,
           mainColumnLastFocusRequestByKey[requestKey] == request {
            bounceDebugLog(
                "scrollToFocus skipped reason=\(reason) key=\(requestKey) viewportKey=\(viewportKey) " +
                "target=\(debugCardIDString(idToScroll)) offset=\(debugCGFloat(currentOffsetY)) " +
                "\(debugMainColumnEstimatedTargetSummary(targetLayout)) " +
                "\(debugMainColumnObservedTargetSummary(viewportKey: viewportKey, targetID: idToScroll, offsetY: currentOffsetY)) " +
                "visible=\(debugMainColumnVisibleCardSummary(viewportKey: viewportKey, cards: cards, viewportHeight: viewportHeight, offsetY: currentOffsetY))"
            )
            scheduleMainColumnFocusVerification(
                viewportKey: viewportKey,
                cards: cards,
                level: level,
                parent: parent,
                targetID: idToScroll,
                proxy: proxy,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor,
                keepVisibleOnly: keepVisibleOnly,
                editingRevealEdge: editingRevealEdge,
                animated: false,
                participantHandle: participantHandle,
                allowsEditingTransitionBypass: allowsEditingTransitionBypass
            )
            return
        }
        mainColumnLastFocusRequestByKey[requestKey] = request

        if keepVisibleOnly,
           isMainColumnFocusTargetVisible(
                viewportKey: viewportKey,
                cards: cards,
                targetID: idToScroll,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor
           ) {
            scheduleMainColumnFocusVerification(
                viewportKey: viewportKey,
                cards: cards,
                level: level,
                parent: parent,
                targetID: idToScroll,
                proxy: proxy,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor,
                keepVisibleOnly: true,
                editingRevealEdge: editingRevealEdge,
                animated: false,
                participantHandle: participantHandle,
                allowsEditingTransitionBypass: allowsEditingTransitionBypass
            )
            return
        }

        if !forceAlignment && shouldSkipMainColumnFocusScroll(
            targetID: idToScroll,
            cards: cards,
            level: level,
            viewportHeight: viewportHeight,
            prefersTopAnchor: prefersTopAnchor
        ) {
            bounceDebugLog(
                "scrollToFocus preserved reason=\(reason) key=\(requestKey) viewportKey=\(viewportKey) " +
                "target=\(debugCardIDString(idToScroll)) offset=\(debugCGFloat(currentOffsetY)) top=\(prefersTopAnchor) " +
                "\(debugMainColumnEstimatedTargetSummary(targetLayout)) " +
                "\(debugMainColumnObservedTargetSummary(viewportKey: viewportKey, targetID: idToScroll, offsetY: currentOffsetY))"
            )
            scheduleMainColumnFocusVerification(
                viewportKey: viewportKey,
                cards: cards,
                level: level,
                parent: parent,
                targetID: idToScroll,
                proxy: proxy,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor,
                keepVisibleOnly: keepVisibleOnly,
                editingRevealEdge: editingRevealEdge,
                animated: false,
                participantHandle: participantHandle,
                allowsEditingTransitionBypass: allowsEditingTransitionBypass
            )
            return
        }

        bounceDebugLog(
            "scrollToFocus reason=\(reason) key=\(requestKey) viewportKey=\(viewportKey) " +
            "target=\(debugCardToken(findCard(by: idToScroll))) height=\(debugCGFloat(targetHeight)) " +
            "viewport=\(debugCGFloat(viewportHeight)) offset=\(debugCGFloat(currentOffsetY)) " +
            "top=\(prefersTopAnchor) keepVisible=\(keepVisibleOnly) force=\(forceAlignment) edge=\(String(describing: editingRevealEdge)) animated=\(animated) " +
            "\(debugMainColumnEstimatedTargetSummary(targetLayout)) " +
            "\(debugMainColumnObservedTargetSummary(viewportKey: viewportKey, targetID: idToScroll, offsetY: currentOffsetY)) " +
            "visible=\(debugMainColumnVisibleCardSummary(viewportKey: viewportKey, cards: cards, viewportHeight: viewportHeight, offsetY: currentOffsetY))"
        )
        mainCanvasScrollCoordinator.updateMotionParticipantState(.moving, handle: participantHandle)
        if keepVisibleOnly {
            applyMainColumnFocusVisibility(
                viewportKey: viewportKey,
                cards: cards,
                targetID: idToScroll,
                proxy: proxy,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor,
                editingRevealEdge: editingRevealEdge,
                animated: animated
            )
        } else {
            applyMainColumnFocusAlignment(
                viewportKey: viewportKey,
                cards: cards,
                targetID: idToScroll,
                proxy: proxy,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor,
                animated: animated
            )
        }
        scheduleMainColumnFocusVerification(
            viewportKey: viewportKey,
            cards: cards,
            level: level,
            parent: parent,
            targetID: idToScroll,
            proxy: proxy,
            viewportHeight: viewportHeight,
            prefersTopAnchor: prefersTopAnchor,
            keepVisibleOnly: keepVisibleOnly,
            editingRevealEdge: editingRevealEdge,
            animated: animated,
            participantHandle: participantHandle,
            allowsEditingTransitionBypass: allowsEditingTransitionBypass
        )
    }

    func handleMainColumnNavigationIntent(
        viewportKey: String,
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat
    ) {
        guard let intent = mainCanvasScrollCoordinator.consumeLatestIntent(for: viewportKey) else { return }

        switch intent.kind {
        case .focusChange:
            handleMainColumnActiveFocusChange(
                viewportKey: viewportKey,
                newActiveID: intent.expectedActiveCardID,
                cards: cards,
                level: level,
                parent: parent,
                proxy: proxy,
                viewportHeight: viewportHeight,
                trigger: intent.trigger,
                animatedOverride: intent.animated,
                intent: intent
            )

        case .settleRecovery:
            handleMainColumnNavigationSettle(
                viewportKey: viewportKey,
                cards: cards,
                level: level,
                parent: parent,
                proxy: proxy,
                viewportHeight: viewportHeight,
                intent: intent
            )

        case .childListChange, .columnAppear:
            handleMainColumnImmediateAlignmentIntent(
                viewportKey: viewportKey,
                cards: cards,
                level: level,
                parent: parent,
                proxy: proxy,
                viewportHeight: viewportHeight,
                trigger: intent.trigger,
                intent: intent
            )

        case .bottomReveal:
            handleMainColumnBottomRevealIntent(
                viewportKey: viewportKey,
                cards: cards,
                proxy: proxy,
                viewportHeight: viewportHeight,
                requestedID: intent.targetCardID,
                animated: intent.animated,
                trigger: intent.trigger,
                intent: intent
            )
        }
    }

    func handleMainColumnImmediateAlignmentIntent(
        viewportKey: String,
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        trigger: String,
        intent: MainCanvasScrollCoordinator.NavigationIntent
    ) {
        guard !showFocusMode else { return }
        guard acceptsKeyboardInput else { return }
        guard editingCardID == nil else { return }
        cancelPendingMainColumnFocusWorkItem(for: viewportKey)
        cancelPendingMainColumnFocusVerificationWorkItem(for: viewportKey)
        if shouldPreserveMainColumnViewportOnReveal(level: level, storageKey: viewportKey, newActiveID: activeCardID) {
            return
        }
        guard shouldAutoAlignMainColumn(cards: cards, activeID: activeCardID) else { return }
        guard let participantHandle = mainCanvasScrollCoordinator.claimMotionParticipant(
            for: viewportKey,
            axis: .vertical,
            intent: intent
        ) else { return }
        bounceDebugLog(
            "\(trigger) level=\(level) viewportKey=\(viewportKey) " +
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
            reason: trigger,
            participantHandle: participantHandle
        )
    }

    func handleMainColumnBottomRevealIntent(
        viewportKey: String,
        cards: [SceneCard],
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        requestedID: UUID?,
        animated: Bool,
        trigger: String,
        intent: MainCanvasScrollCoordinator.NavigationIntent
    ) {
        guard !showFocusMode else { return }
        guard acceptsKeyboardInput else { return }
        guard editingCardID == nil else { return }
        guard let requestedID else { return }
        guard activeCardID == requestedID else { return }
        guard cards.last?.id == requestedID else { return }
        guard let requestedCard = findCard(by: requestedID) else { return }
        let cardHeight = resolvedMainCardHeight(for: requestedCard)
        guard cardHeight > viewportHeight else { return }

        bounceDebugLog(
            "\(trigger) viewportKey=\(viewportKey) target=\(debugCardToken(requestedCard)) " +
            "offset=\(debugCGFloat(mainColumnViewportOffsetByKey[viewportKey] ?? 0)) height=\(debugCGFloat(cardHeight))"
        )
        guard let participantHandle = mainCanvasScrollCoordinator.claimMotionParticipant(
            for: viewportKey,
            axis: .vertical,
            intent: intent
        ) else { return }
        mainCanvasScrollCoordinator.updateMotionParticipantState(.moving, handle: participantHandle)
        if performMainColumnNativeFocusScroll(
            viewportKey: viewportKey,
            cards: cards,
            targetID: requestedID,
            viewportHeight: viewportHeight,
            anchorY: 1.0,
            animated: animated
        ) {
            mainCanvasScrollCoordinator.updateMotionParticipantState(.aligned, handle: participantHandle)
            return
        }

        suspendMainColumnViewportCapture(for: animated ? 0.32 : 0.12)
        if animated {
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                axis: "vertical",
                engine: "proxy",
                animated: true,
                target: "\(viewportKey)|\(requestedID.uuidString)",
                expectedDuration: 0.24
            )
            withAnimation(quickEaseAnimation) {
                proxy.scrollTo(requestedID, anchor: .bottom)
            }
        } else {
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                axis: "vertical",
                engine: "proxy",
                animated: false,
                target: "\(viewportKey)|\(requestedID.uuidString)",
                expectedDuration: 0
            )
            performWithoutAnimation {
                proxy.scrollTo(requestedID, anchor: .bottom)
            }
        }
        mainCanvasScrollCoordinator.updateMotionParticipantState(.aligned, handle: participantHandle)
    }

    func handleMainColumnReorderCommitMotion(
        viewportKey: String,
        cards: [SceneCard],
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        participantHandle: MainCanvasScrollCoordinator.MotionParticipantHandle
    ) -> Bool {
        let movedBlockCardIDs = cards
            .map(\.id)
            .filter { pendingMainReorderMotionCardIDs.contains($0) }
        guard !movedBlockCardIDs.isEmpty else { return false }

        if isMainColumnBlockWithinComfortBand(
            viewportKey: viewportKey,
            cards: cards,
            cardIDs: movedBlockCardIDs,
            viewportHeight: viewportHeight
        ) {
            bounceDebugLog(
                "reorderCommit preserve viewportKey=\(viewportKey) cards=\(movedBlockCardIDs.map(debugCardIDString).joined(separator: ","))"
            )
            mainCanvasScrollCoordinator.updateMotionParticipantState(.aligned, handle: participantHandle)
            return true
        }

        bounceDebugLog(
            "reorderCommit settle viewportKey=\(viewportKey) cards=\(movedBlockCardIDs.map(debugCardIDString).joined(separator: ","))"
        )
        mainCanvasScrollCoordinator.updateMotionParticipantState(.moving, handle: participantHandle)
        applyMainColumnBlockVisibility(
            viewportKey: viewportKey,
            cards: cards,
            cardIDs: movedBlockCardIDs,
            proxy: proxy,
            viewportHeight: viewportHeight,
            animated: false
        )
        mainCanvasScrollCoordinator.updateMotionParticipantState(.aligned, handle: participantHandle)
        return true
    }

    func handleMainColumnActiveFocusChange(
        viewportKey: String,
        newActiveID: UUID?,
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        trigger: String,
        animatedOverride: Bool? = nil,
        intent: MainCanvasScrollCoordinator.NavigationIntent
    ) {
        guard !showFocusMode else { return }
        guard acceptsKeyboardInput else { return }
        guard editingCardID == nil else { return }
        cancelPendingMainColumnFocusWorkItem(for: viewportKey)
        cancelPendingMainColumnFocusVerificationWorkItem(for: viewportKey)
        let forceClickAlignment = trigger == "clickFocus"
        if !forceClickAlignment &&
            shouldPreserveMainColumnViewportOnReveal(level: level, storageKey: viewportKey, newActiveID: newActiveID) {
            return
        }

        let containsActiveCard = cards.contains { $0.id == newActiveID }
        let containsActiveAncestor = cards.contains { activeAncestorIDs.contains($0.id) }
        let containsPreferredDescendantTarget =
            !containsActiveCard &&
            !containsActiveAncestor &&
            resolvedMainColumnFocusTargetID(in: cards) != nil
        guard containsActiveCard || containsActiveAncestor || containsPreferredDescendantTarget else { return }

        let activeCardNeedsTopReveal = containsActiveCard && {
            guard let newActiveID, let targetCard = findCard(by: newActiveID) else { return false }
            return resolvedMainCardHeight(for: targetCard) > viewportHeight
        }()
        let editDrivenKeepVisible = containsActiveCard && pendingMainEditingViewportKeepVisibleCardID == newActiveID
        let editingRevealEdge = editDrivenKeepVisible ? pendingMainEditingViewportRevealEdge : nil
        if editDrivenKeepVisible {
            pendingMainEditingViewportKeepVisibleCardID = nil
            pendingMainEditingViewportRevealEdge = nil
        }
        let focusDelayOverride = containsPreferredDescendantTarget
            ? mainCanvasScrollCoordinator.motionPolicy.descendantJoinDelay
            : nil
        let shouldAnimate = containsPreferredDescendantTarget
            ? false
            : (animatedOverride ?? (
                focusNavigationAnimationEnabled &&
                !shouldSuppressMainArrowRepeatAnimation()
            ))
        guard let participantHandle = mainCanvasScrollCoordinator.claimMotionParticipant(
            for: viewportKey,
            axis: .vertical,
            intent: intent
        ) else { return }

        if trigger == "reorderCommit",
           handleMainColumnReorderCommitMotion(
                viewportKey: viewportKey,
                cards: cards,
                proxy: proxy,
                viewportHeight: viewportHeight,
                participantHandle: participantHandle
           ) {
            return
        }

        bounceDebugLog(
            "\(trigger) level=\(level) viewportKey=\(viewportKey) " +
            "newID=\(newActiveID?.uuidString ?? "nil") activeColumn=\(containsActiveCard) " +
            "ancestorColumn=\(containsActiveAncestor) descendantColumn=\(containsPreferredDescendantTarget) topReveal=\(activeCardNeedsTopReveal) " +
            "editKeepVisible=\(editDrivenKeepVisible) forceClick=\(forceClickAlignment) animate=\(shouldAnimate) " +
            "offset=\(debugCGFloat(mainColumnViewportOffsetByKey[viewportKey] ?? 0)) " +
            "visible=\(debugMainColumnVisibleCardSummary(viewportKey: viewportKey, cards: cards, viewportHeight: viewportHeight, offsetY: mainColumnViewportOffsetByKey[viewportKey] ?? 0))"
        )
        scheduleMainColumnActiveCardFocus(
            viewportKey: viewportKey,
            expectedActiveID: newActiveID,
            cards: cards,
            level: level,
            parent: parent,
            proxy: proxy,
            viewportHeight: viewportHeight,
            keepVisibleOnly: editDrivenKeepVisible,
            editingRevealEdge: editingRevealEdge,
            forceAlignment: forceClickAlignment,
            animated: shouldAnimate,
            focusDelayOverride: focusDelayOverride,
            participantHandle: participantHandle,
            allowsEditingTransitionBypass: editDrivenKeepVisible
        )
    }


    func requestMainBottomRevealIfNeeded(
        currentLevel: [SceneCard],
        currentIndex: Int,
        card: SceneCard
    ) -> Bool {
        guard currentIndex == currentLevel.count - 1 else { return false }
        guard activeCardID == card.id else { return false }
        bounceDebugLog("requestMainBottomRevealIfNeeded target=\(debugCardToken(card)) levelCount=\(currentLevel.count)")
        mainBottomRevealCardID = card.id
        mainBottomRevealTick += 1
        return true
    }

    func scrollToColumnIfNeeded(
        targetCardID: UUID,
        proxy: ScrollViewProxy,
        availableWidth: CGFloat,
        force: Bool = false,
        animated: Bool = true
    ) {
        if !acceptsKeyboardInput && !force { return }
        guard let targetLevel = displayedMainCardLocationByID(targetCardID)?.level else { return }
        indexBoardRestoreTrace(
            "main_canvas_scroll_to_column_if_needed",
            "target=\(debugRestoreUUID(targetCardID)) targetLevel=\(targetLevel) force=\(force) animated=\(animated) " +
            "lastScrolledLevel=\(lastScrolledLevel) mode=\(mainCanvasHorizontalScrollMode.rawValue)"
        )
        let resolvedAvailableWidth = max(1, availableWidth)
        let scrollMode = mainCanvasHorizontalScrollMode
        let performScroll: (Int) -> Void = { level in
            if performMainCanvasHorizontalScroll(
                level: level,
                availableWidth: resolvedAvailableWidth,
                animated: animated
            ) {
                return
            }

            let hAnchor = resolvedMainCanvasHorizontalAnchor(availableWidth: resolvedAvailableWidth)
            if animated {
                MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                    ownerKey: mainCanvasDiagnosticsOwnerKey,
                    axis: "horizontal",
                    engine: "proxy",
                    animated: true,
                    target: "level:\(level)",
                    expectedDuration: 0.24
                )
                withAnimation(quickEaseAnimation) {
                    proxy.scrollTo(level, anchor: hAnchor)
                }
            } else {
                MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                    ownerKey: mainCanvasDiagnosticsOwnerKey,
                    axis: "horizontal",
                    engine: "proxy",
                    animated: false,
                    target: "level:\(level)",
                    expectedDuration: 0
                )
                performWithoutAnimation {
                    proxy.scrollTo(level, anchor: hAnchor)
                }
            }
        }
        switch scrollMode {
        case .oneStep:
            let desiredLevel = targetLevel
            if force || lastScrolledLevel != desiredLevel {
                lastScrolledLevel = desiredLevel
                performScroll(desiredLevel)
            }
        case .twoStep:
            if force {
                lastScrolledLevel = max(0, targetLevel - 1)
                performScroll(lastScrolledLevel)
                return
            }
            if lastScrolledLevel < 0 {
                lastScrolledLevel = max(0, targetLevel - 1)
                performScroll(lastScrolledLevel)
                return
            }
            if targetLevel < lastScrolledLevel {
                lastScrolledLevel = targetLevel
                performScroll(lastScrolledLevel)
            } else if targetLevel > lastScrolledLevel + 1 {
                lastScrolledLevel = targetLevel - 1
                performScroll(lastScrolledLevel)
            }
        }
    }

    func resolvedMainCanvasHorizontalAnchor(availableWidth: CGFloat) -> UnitPoint {
        let resolvedAvailableWidth = max(1, availableWidth)
        switch mainCanvasHorizontalScrollMode {
        case .oneStep:
            return UnitPoint(x: 0.5, y: 0.4)
        case .twoStep:
            let hOffset = (columnWidth / 2) / resolvedAvailableWidth
            return UnitPoint(x: 0.5 - hOffset, y: 0.4)
        }
    }

    func resolvedMainCanvasHorizontalTargetX(
        level: Int,
        availableWidth: CGFloat,
        visibleWidth: CGFloat
    ) -> CGFloat {
        let anchor = resolvedMainCanvasHorizontalAnchor(availableWidth: availableWidth)
        let leadingInset = availableWidth / 2
        let targetMinX = leadingInset + (CGFloat(level) * columnWidth)
        let targetAnchorX = targetMinX + (columnWidth * anchor.x)
        return targetAnchorX - (visibleWidth * anchor.x)
    }

    @discardableResult
    func performMainCanvasHorizontalScroll(
        level: Int,
        availableWidth: CGFloat,
        animated: Bool
    ) -> Bool {
        guard let scrollView = mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalScrollView() else {
            indexBoardRestoreTrace(
                "main_canvas_perform_horizontal_scroll_skip",
                "level=\(level) reason=noScrollView animated=\(animated)"
            )
            return false
        }

        let visibleRect = scrollView.documentVisibleRect
        let documentWidth = scrollView.documentView?.bounds.width ?? 0
        let maxX = max(0, documentWidth - visibleRect.width)
        let targetX = resolvedMainCanvasHorizontalTargetX(
            level: level,
            availableWidth: availableWidth,
            visibleWidth: visibleRect.width
        )
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
            indexBoardRestoreTrace(
                "main_canvas_perform_horizontal_scroll_applied",
                "level=\(level) animated=true resolvedTargetX=\(debugRestoreCGFloat(resolvedTargetX)) " +
                "currentXAfter=\(debugRestoreCGFloat(scrollView.contentView.bounds.origin.x)) duration=\(String(format: "%.2f", appliedDuration))"
            )
            bounceDebugLog(
                "nativeMainCanvasHorizontalScroll level=\(level) " +
                "targetX=\(debugCGFloat(resolvedTargetX)) visibleX=\(debugCGFloat(visibleRect.origin.x)) " +
                "duration=\(String(format: "%.2f", appliedDuration)) viewport=\(debugCGFloat(visibleRect.width))"
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
        indexBoardRestoreTrace(
            "main_canvas_perform_horizontal_scroll_applied",
            "level=\(level) animated=false applied=\(applied) targetX=\(debugRestoreCGFloat(targetX)) " +
            "currentXAfter=\(debugRestoreCGFloat(scrollView.contentView.bounds.origin.x))"
        )
        if applied {
            bounceDebugLog(
                "nativeMainCanvasHorizontalScroll immediate level=\(level) " +
                "targetX=\(debugCGFloat(targetX)) visibleX=\(debugCGFloat(visibleRect.origin.x))"
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
}
