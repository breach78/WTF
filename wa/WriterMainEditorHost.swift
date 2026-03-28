import SwiftUI
import AppKit

extension ScenarioWriterView {
    private struct MainWorkspaceEditorHostScaffold: View {
        let viewportKey: String
        let targetCardID: UUID?
        let slotFrame: CGRect?

        var body: some View {
            ZStack(alignment: .topLeading) {
                if let slotFrame {
                    Color.clear
                        .frame(
                            width: max(1, slotFrame.width),
                            height: max(1, slotFrame.height),
                            alignment: .topLeading
                        )
                        .offset(x: slotFrame.minX, y: slotFrame.minY)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
            .onAppear {
                mainWorkspacePhase0Log(
                    "main-editor-host-scaffold",
                    "viewportKey=\(viewportKey) target=\(mainWorkspacePhase0CardID(targetCardID)) " +
                    "frame=\(slotFrame.map { NSStringFromRect($0) } ?? "nil") phase=appear"
                )
            }
            .onChange(of: slotFrame) { _, newFrame in
                mainWorkspacePhase0Log(
                    "main-editor-host-scaffold",
                    "viewportKey=\(viewportKey) target=\(mainWorkspacePhase0CardID(targetCardID)) " +
                    "frame=\(newFrame.map { NSStringFromRect($0) } ?? "nil") phase=frameChange"
                )
            }
            .onChange(of: targetCardID) { _, newTargetID in
                mainWorkspacePhase0Log(
                    "main-editor-host-scaffold",
                    "viewportKey=\(viewportKey) target=\(mainWorkspacePhase0CardID(newTargetID)) " +
                    "frame=\(slotFrame.map { NSStringFromRect($0) } ?? "nil") phase=targetChange"
                )
            }
        }
    }

    var isMainWorkspaceEditorSurfaceActive: Bool {
        !showFocusMode && !isIndexBoardActive
    }

    func resolvedVisibleMainEditorHostTargetID(
        viewportKey: String,
        cards: [SceneCard]? = nil
    ) -> UUID? {
        guard isMainWorkspaceEditorSurfaceActive else { return nil }
        guard let mountedCardID = mainEditorSession.mountedCardID else { return nil }
        if let cards, !cards.contains(where: { $0.id == mountedCardID }) {
            return nil
        }
        guard resolvedMainColumnEditorHostFrame(viewportKey: viewportKey, cardID: mountedCardID) != nil else {
            return nil
        }
        return mountedCardID
    }

    func resolvedMountingMainEditorHostTargetID(
        viewportKey: String,
        cards: [SceneCard]
    ) -> UUID? {
        guard isMainWorkspaceEditorSurfaceActive else { return nil }
        let candidateIDs = [mainEditorSession.requestedCardID, mainEditorSession.mountedCardID].compactMap { $0 }

        for candidateID in candidateIDs {
            guard cards.contains(where: { $0.id == candidateID }) || findCard(by: candidateID) != nil else {
                continue
            }
            guard resolvedMainColumnEditorHostFrame(viewportKey: viewportKey, cardID: candidateID) != nil else {
                continue
            }
            return candidateID
        }

        return nil
    }

    func resolvedMainColumnEditorHostTargetID(
        viewportKey: String,
        cards: [SceneCard]
    ) -> UUID? {
        resolvedMountingMainEditorHostTargetID(viewportKey: viewportKey, cards: cards)
    }

    func resolvedMainColumnEditorHostFrame(
        viewportKey: String,
        cards: [SceneCard]
    ) -> CGRect? {
        guard let targetCardID = resolvedMainColumnEditorHostTargetID(viewportKey: viewportKey, cards: cards) else { return nil }
        return resolvedMainColumnEditorHostFrame(viewportKey: viewportKey, cardID: targetCardID)
    }

    func resolvedMainColumnEditorHostFrame(
        viewportKey: String,
        cardID: UUID
    ) -> CGRect? {
        let frame =
            mainColumnObservedEditorSlotFramesByKey[viewportKey]?[cardID] ??
            mainColumnCachedEditorSlotFramesByKey[viewportKey]?[cardID]
        guard let frame else { return nil }
        guard frame.width > 1, frame.height > 1 else { return nil }
        return frame
    }

    func canUseExternalMainEditor(
        cardID: UUID,
        viewportKey: String,
        cards: [SceneCard]
    ) -> Bool {
        guard isMainWorkspaceEditorSurfaceActive else { return false }
        return resolvedMainColumnEditorHostTargetID(viewportKey: viewportKey, cards: cards) == cardID
    }

    func resolvedMainColumnEditingHostCard(
        viewportKey: String,
        cards: [SceneCard]
    ) -> SceneCard? {
        guard let targetCardID = resolvedMountingMainEditorHostTargetID(viewportKey: viewportKey, cards: cards) else {
            return nil
        }
        return cards.first(where: { $0.id == targetCardID }) ?? findCard(by: targetCardID)
    }

    private func resolvedPreparedMainEditorHostTargetID(
        viewportKey: String,
        cards: [SceneCard]
    ) -> UUID? {
        if let mountingTargetID = resolvedMountingMainEditorHostTargetID(viewportKey: viewportKey, cards: cards) {
            return mountingTargetID
        }
        guard isMainWorkspaceEditorSurfaceActive else { return nil }
        guard editingCardID == nil else { return nil }
        guard let activeCardID else { return nil }
        guard cards.contains(where: { $0.id == activeCardID }) else { return nil }
        guard resolvedMainColumnEditorHostFrame(viewportKey: viewportKey, cardID: activeCardID) != nil else {
            return nil
        }
        return activeCardID
    }

    private func resolvedPreparedMainColumnEditingHostCard(
        viewportKey: String,
        cards: [SceneCard]
    ) -> SceneCard? {
        guard let targetCardID = resolvedPreparedMainEditorHostTargetID(viewportKey: viewportKey, cards: cards) else {
            return nil
        }
        return cards.first(where: { $0.id == targetCardID }) ?? findCard(by: targetCardID)
    }

    private func resolvedMainWorkspaceHostBodyHeight(for card: SceneCard) -> CGFloat {
        if mainEditorSession.mountedCardID == card.id,
           let liveBodyHeight = mainEditorSession.liveBodyHeight,
           liveBodyHeight > 1 {
            return liveBodyHeight
        }
        return sharedMeasuredTextBodyHeight(
            text: card.content,
            fontSize: CGFloat(fontSize),
            lineSpacing: CGFloat(mainCardLineSpacingValue),
            width: MainCanvasLayoutMetrics.textWidth,
            lineFragmentPadding: MainEditorLayoutMetrics.mainEditorLineFragmentPadding,
            safetyInset: 0
        )
    }

    private func mainWorkspaceEditorTextBinding(for cardID: UUID) -> Binding<String> {
        Binding(
            get: { findCard(by: cardID)?.content ?? "" },
            set: { newValue in
                guard let card = findCard(by: cardID) else { return }
                let oldValue = card.content
                guard oldValue != newValue else { return }
                card.content = newValue
                handleMainEditorContentChange(cardID: cardID, oldValue: oldValue, newValue: newValue)
            }
        )
    }

    func updateMainEditorMeasuredBodyHeight(cardID: UUID, measured: CGFloat?) {
        guard mainEditorSession.requestedCardID == cardID || mainEditorSession.mountedCardID == cardID else { return }
        let resolvedHeight = (measured ?? 0) > 1 ? measured : nil
        let previous = mainEditorSession.liveBodyHeight
        let threshold = MainEditorLayoutMetrics.mainEditorHeightUpdateThreshold
        if let previous, let resolvedHeight,
           abs(previous - resolvedHeight) <= threshold {
            return
        }
        if previous == nil && resolvedHeight == nil {
            return
        }
        mainEditorSession.liveBodyHeight = resolvedHeight
        mainWorkspacePhase0Log(
            "main-editor-session",
            "phase=measure card=\(mainWorkspacePhase0CardID(cardID)) body=\(resolvedHeight.map { String(format: "%.1f", $0) } ?? "nil") " +
            "previous=\(previous.map { String(format: "%.1f", $0) } ?? "nil")"
        )
    }

    @ViewBuilder
    private func mainWorkspaceStableHostEditor(card: SceneCard, hostFrame: CGRect, isVisible: Bool) -> some View {
        let bodyHeight = resolvedMainWorkspaceHostBodyHeight(for: card)
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: max(1, hostFrame.width), height: max(1, hostFrame.height), alignment: .topLeading)

            MainWorkspaceEditableTextRenderer(
                text: mainWorkspaceEditorTextBinding(for: card.id),
                cardID: card.id,
                textWidth: MainCanvasLayoutMetrics.textWidth,
                bodyHeight: bodyHeight,
                fontSize: CGFloat(fontSize),
                lineSpacing: CGFloat(mainCardLineSpacingValue),
                appearance: appearance,
                isFocused: editingCardID == card.id,
                onFocusStateChange: { isFocused in
                    updateMainEditorResponderState(cardID: card.id, isFocused: isFocused)
                },
                onMeasuredBodyHeightChange: { measured in
                    updateMainEditorMeasuredBodyHeight(cardID: card.id, measured: measured)
                },
                onCommandBy: { selector in
                    handleMainEditorBoundaryCommand(selector)
                }
            )
            .frame(width: MainCanvasLayoutMetrics.textWidth, height: bodyHeight, alignment: .topLeading)
            .padding(.horizontal, MainEditorLayoutMetrics.mainEditorHorizontalPadding)
            .padding(.vertical, 24)
        }
        .offset(x: hostFrame.minX, y: hostFrame.minY)
        .opacity(isVisible ? 1 : 0.001)
        .allowsHitTesting(isVisible)
        .onAppear {
            markMainEditorMounted(cardID: card.id)
            mainWorkspacePhase0Log(
                "main-editor-host-appear",
                "card=\(mainWorkspacePhase0CardID(card.id)) frame=\(NSStringFromRect(hostFrame)) visible=\(isVisible)"
            )
        }
        .onChange(of: isVisible) { _, newValue in
            mainWorkspacePhase0Log(
                "main-editor-host-visibility",
                "card=\(mainWorkspacePhase0CardID(card.id)) visible=\(newValue) frame=\(NSStringFromRect(hostFrame))"
            )
        }
        .onChange(of: card.id) { oldCardID, newCardID in
            rebindMainEditorMountedCard(from: oldCardID, to: newCardID)
        }
        .onDisappear {
            markMainEditorUnmounted(cardID: card.id)
            mainWorkspacePhase0Log(
                "main-editor-host-disappear",
                "card=\(mainWorkspacePhase0CardID(card.id)) frame=\(NSStringFromRect(hostFrame)) visible=\(isVisible)"
            )
        }
    }

    @ViewBuilder
    func mainColumnEditorHostScaffold(
        viewportKey: String,
        cards: [SceneCard]
    ) -> some View {
        MainWorkspaceEditorHostScaffold(
            viewportKey: viewportKey,
            targetCardID: resolvedMainColumnEditorHostTargetID(viewportKey: viewportKey, cards: cards),
            slotFrame: resolvedMainColumnEditorHostFrame(
                viewportKey: viewportKey,
                cards: cards
            )
        )
        .id("main-editor-host-scaffold-\(viewportKey)")
    }

    @ViewBuilder
    func mainColumnEditorHostOverlay(
        viewportKey: String,
        cards: [SceneCard]
    ) -> some View {
        let preparedTargetID = resolvedPreparedMainEditorHostTargetID(viewportKey: viewportKey, cards: cards)
        let hostFrame = preparedTargetID.flatMap {
            resolvedMainColumnEditorHostFrame(viewportKey: viewportKey, cardID: $0)
        }

        ZStack(alignment: .topLeading) {
            mainColumnEditorHostScaffold(
                viewportKey: viewportKey,
                cards: cards
            )

            if let targetCard = resolvedPreparedMainColumnEditingHostCard(viewportKey: viewportKey, cards: cards),
               let hostFrame {
                mainWorkspaceStableHostEditor(
                    card: targetCard,
                    hostFrame: hostFrame,
                    isVisible:
                        editingCardID == targetCard.id ||
                        mainEditorSession.requestedCardID == targetCard.id ||
                        mainEditorSession.mountedCardID == targetCard.id
                )
            }
        }
    }

    private struct ResolvedMainEditorAuthority {
        let cardID: UUID
        let textView: NSTextView
        let textViewIdentity: Int
    }

    private func resolvedMainEditorAuthority(for cardID: UUID? = nil) -> ResolvedMainEditorAuthority? {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return nil }
        guard textView.isEditable else { return nil }
        let resolvedCardID =
            cardID ??
            mainEditorSession.requestedCardID ??
            mainEditorSession.mountedCardID ??
            editingCardID
        guard let resolvedCardID else { return nil }
        guard mainEditorSession.requestedCardID == resolvedCardID || mainEditorSession.mountedCardID == resolvedCardID else {
            return nil
        }

        let identity = ObjectIdentifier(textView).hashValue
        if let card = findCard(by: resolvedCardID), textView.string == card.content {
            return ResolvedMainEditorAuthority(
                cardID: resolvedCardID,
                textView: textView,
                textViewIdentity: identity
            )
        }
        if mainEditorSession.textViewIdentity == identity {
            return ResolvedMainEditorAuthority(
                cardID: resolvedCardID,
                textView: textView,
                textViewIdentity: identity
            )
        }
        return nil
    }

    func resolveMainEditorSessionTextViewIdentity(for cardID: UUID) -> Int? {
        resolvedMainEditorAuthority(for: cardID)?.textViewIdentity
    }

    @discardableResult
    private func refreshMainEditorSessionResponderState(
        for cardID: UUID,
        updateMountedCardID: Bool = true
    ) -> Int? {
        let resolvedTextViewIdentity = resolveMainEditorSessionTextViewIdentity(for: cardID)
        if updateMountedCardID {
            mainEditorSession.mountedCardID = cardID
        }
        mainEditorSession.textViewIdentity = resolvedTextViewIdentity
        mainEditorSession.isFirstResponderReady = resolvedTextViewIdentity != nil
        return resolvedTextViewIdentity
    }

    func resolvedActiveMainEditorTextView(for cardID: UUID? = nil) -> NSTextView? {
        resolvedMainEditorAuthority(for: cardID)?.textView
    }

    func isMainEditorActivelyTyping(cardID: UUID? = nil) -> Bool {
        resolvedActiveMainEditorTextView(for: cardID) != nil
    }

    func shouldTreatCardAsActivelyEditing(_ cardID: UUID) -> Bool {
        guard editingCardID == cardID else { return false }
        if isMainEditorActivelyTyping(cardID: cardID) {
            return true
        }
        return mainEditorSession.requestedCardID == cardID && !mainEditorSession.isFirstResponderReady
    }

    func resolvedMainEditingTargetCard() -> SceneCard? {
        if let activeID = activeCardID,
           let activeCard = findCard(by: activeID) {
            return activeCard
        }
        if let requestedID = mainEditorSession.requestedCardID,
           let requestedCard = findCard(by: requestedID) {
            return requestedCard
        }
        if let mountedID = mainEditorSession.mountedCardID,
           let mountedCard = findCard(by: mountedID) {
            return mountedCard
        }
        if let editingID = editingCardID,
           let editingCard = findCard(by: editingID) {
            return editingCard
        }
        return nil
    }

    func resolvedMainEditingTransitionTargetCardID() -> UUID? {
        pendingMainEditingBoundaryNavigationTargetID ??
        mainEditorSession.requestedCardID ??
        editingCardID
    }

    func isMainEditingBoundaryTransitionReady(for targetCardID: UUID) -> Bool {
        editingCardID == targetCardID &&
        mainEditorSession.requestedCardID == targetCardID &&
        mainEditorSession.isFirstResponderReady
    }

    func isMainEditingTransitionPending(targetCardID: UUID? = nil) -> Bool {
        guard !showFocusMode else { return false }
        let resolvedTargetID = targetCardID ?? resolvedMainEditingTransitionTargetCardID()
        guard let resolvedTargetID else { return false }
        if let pendingTarget = pendingMainEditingBoundaryNavigationTargetID,
           pendingTarget == resolvedTargetID {
            return !isMainEditingBoundaryTransitionReady(for: pendingTarget)
        }
        guard mainEditorSession.requestedCardID == resolvedTargetID else { return false }
        return resolvedActiveMainEditorTextView(for: resolvedTargetID) == nil
    }

    func shouldSuppressGeneralMainCanvasScrollDuringEditing(targetCardID: UUID? = nil) -> Bool {
        let targetMatchesTimedIsolation =
            targetCardID == nil ||
            mainEditingScrollIsolationTargetCardID == nil ||
            targetCardID == mainEditingScrollIsolationTargetCardID
        if targetMatchesTimedIsolation && Date() < mainEditingScrollIsolationUntil {
            return true
        }
        return isMainEditingTransitionPending(targetCardID: targetCardID)
    }

    func shouldSuppressMainColumnFocusVerificationDuringEditing(
        allowsEditingTransitionBypass: Bool,
        targetCardID: UUID
    ) -> Bool {
        if allowsEditingTransitionBypass {
            return false
        }
        return shouldSuppressGeneralMainCanvasScrollDuringEditing(targetCardID: targetCardID)
    }

    func beginMainEditingScrollIsolation(
        for targetCardID: UUID,
        duration: TimeInterval = 0.32,
        reason: String
    ) {
        let previousTargetID = mainEditingScrollIsolationTargetCardID
        let previousUntil = mainEditingScrollIsolationUntil
        let nextUntil = Date().addingTimeInterval(duration)
        mainEditingScrollIsolationTargetCardID = targetCardID
        if nextUntil > mainEditingScrollIsolationUntil {
            mainEditingScrollIsolationUntil = nextUntil
        }
        cancelMainArrowNavigationSettle()
        cancelAllPendingMainColumnFocusWork()
        pendingMainCanvasRestoreRequest = nil
        suspendMainColumnViewportCapture(for: duration)
        mainWorkspacePhase0Log(
            "main-editing-scroll-isolation",
            "phase=begin reason=\(reason) target=\(mainWorkspacePhase0CardID(targetCardID)) " +
            "previousTarget=\(mainWorkspacePhase0CardID(previousTargetID)) " +
            "previousUntil=\(previousUntil.timeIntervalSince1970) " +
            "until=\(mainEditingScrollIsolationUntil.timeIntervalSince1970)"
        )
    }

    func clearMainEditingScrollIsolation(reason: String) {
        guard mainEditingScrollIsolationTargetCardID != nil || mainEditingScrollIsolationUntil > .distantPast else { return }
        mainWorkspacePhase0Log(
            "main-editing-scroll-isolation",
            "phase=clear reason=\(reason) target=\(mainWorkspacePhase0CardID(mainEditingScrollIsolationTargetCardID)) " +
            "until=\(mainEditingScrollIsolationUntil.timeIntervalSince1970)"
        )
        mainEditingScrollIsolationTargetCardID = nil
        mainEditingScrollIsolationUntil = .distantPast
    }

    func shouldAllowActiveCardChangeDuringEditing(to targetCardID: UUID, force: Bool = false) -> Bool {
        guard !force else { return true }
        guard let editingID = editingCardID else { return true }
        if targetCardID == editingID {
            return true
        }
        if pendingMainEditingBoundaryNavigationTargetID == targetCardID {
            return true
        }
        if pendingMainEditingSiblingNavigationTargetID == targetCardID {
            return true
        }
        return false
    }

    func prepareMainEditorSessionRequest(
        for card: SceneCard,
        explicitCaretLocation: Int? = nil
    ) {
        let textLength = (card.content as NSString).length
        let resolvedSeed: Int?
        if let explicitCaretLocation {
            resolvedSeed = min(max(0, explicitCaretLocation), textLength)
        } else if let saved = mainCaretLocationByCardID[card.id] {
            resolvedSeed = min(max(0, saved), textLength)
        } else {
            resolvedSeed = nil
        }
        mainEditorSession = MainEditorSessionState(
            requestedCardID: card.id,
            mountedCardID: nil,
            textViewIdentity: nil,
            caretSeedLocation: resolvedSeed,
            isFirstResponderReady: false,
            liveBodyHeight: nil
        )
        mainWorkspacePhase0Log(
            "main-editor-session",
            "phase=request card=\(mainWorkspacePhase0CardID(card.id)) seed=\(resolvedSeed.map(String.init) ?? "nil")"
        )
    }

    func markMainEditorMounted(cardID: UUID) {
        guard mainEditorSession.requestedCardID == cardID else { return }
        let resolvedTextViewIdentity = refreshMainEditorSessionResponderState(for: cardID)
        mainWorkspacePhase0Log(
            "main-editor-session",
            "phase=mounted requested=\(mainWorkspacePhase0CardID(mainEditorSession.requestedCardID)) " +
            "mounted=\(mainWorkspacePhase0CardID(mainEditorSession.mountedCardID)) textView=\(resolvedTextViewIdentity.map(String.init) ?? "nil") " +
            "ready=\(mainEditorSession.isFirstResponderReady)"
        )
    }

    func markMainEditorUnmounted(cardID: UUID) {
        guard mainEditorSession.mountedCardID == cardID else { return }
        mainEditorSession.mountedCardID = nil
        mainEditorSession.textViewIdentity = nil
        mainEditorSession.isFirstResponderReady = false
        mainEditorSession.liveBodyHeight = nil
        mainWorkspacePhase0Log(
            "main-editor-session",
            "phase=unmounted requested=\(mainWorkspacePhase0CardID(mainEditorSession.requestedCardID)) " +
            "card=\(mainWorkspacePhase0CardID(cardID))"
        )
    }

    func updateMainEditorResponderState(cardID: UUID, isFocused: Bool) {
        guard mainEditorSession.requestedCardID == cardID || mainEditorSession.mountedCardID == cardID else { return }
        let resolvedTextViewIdentity = refreshMainEditorSessionResponderState(for: cardID)
        if mainEditorSession.isFirstResponderReady,
           pendingMainEditingBoundaryNavigationTargetID == cardID {
            pendingMainEditingBoundaryNavigationTargetID = nil
        }
        mainWorkspacePhase0Log(
            "main-editor-session",
            "phase=focus requested=\(mainWorkspacePhase0CardID(mainEditorSession.requestedCardID)) " +
            "mounted=\(mainWorkspacePhase0CardID(mainEditorSession.mountedCardID)) " +
            "card=\(mainWorkspacePhase0CardID(cardID)) focusedHint=\(isFocused) " +
            "textView=\(resolvedTextViewIdentity.map(String.init) ?? "nil") ready=\(mainEditorSession.isFirstResponderReady)"
        )
    }

    func rebindMainEditorMountedCard(from previousCardID: UUID, to cardID: UUID) {
        guard previousCardID != cardID else { return }
        guard mainEditorSession.requestedCardID == cardID else { return }
        let resolvedTextViewIdentity = refreshMainEditorSessionResponderState(for: cardID)
        mainEditorSession.liveBodyHeight = nil
        if mainEditorSession.isFirstResponderReady,
           pendingMainEditingBoundaryNavigationTargetID == cardID {
            pendingMainEditingBoundaryNavigationTargetID = nil
        }
        mainWorkspacePhase0Log(
            "main-editor-session",
            "phase=rebind previous=\(mainWorkspacePhase0CardID(previousCardID)) requested=\(mainWorkspacePhase0CardID(mainEditorSession.requestedCardID)) " +
            "mounted=\(mainWorkspacePhase0CardID(mainEditorSession.mountedCardID)) card=\(mainWorkspacePhase0CardID(cardID)) " +
            "textView=\(resolvedTextViewIdentity.map(String.init) ?? "nil") ready=\(mainEditorSession.isFirstResponderReady)"
        )
    }

    func relevantFinishEditingCallStackSummary() -> String {
        Thread.callStackSymbols
            .filter { $0.contains("/wa/") || $0.contains("WTF") }
            .prefix(8)
            .joined(separator: " | ")
    }

    func armMainEditorEntryFinishGuard(for cardID: UUID) {
        mainEditorEntryFinishGuardCardID = cardID
        mainEditorEntryFinishGuardUntil = Date().addingTimeInterval(1.2)
        mainWorkspacePhase0Log(
            "main-editor-entry-guard",
            "phase=arm card=\(mainWorkspacePhase0CardID(cardID)) until=\(String(format: "%.3f", mainEditorEntryFinishGuardUntil.timeIntervalSince1970))"
        )
    }

    func clearMainEditorEntryFinishGuard(ifMatching cardID: UUID? = nil) {
        if let cardID, mainEditorEntryFinishGuardCardID != cardID {
            return
        }
        if mainEditorEntryFinishGuardCardID != nil || mainEditorEntryFinishGuardUntil > .distantPast {
            mainWorkspacePhase0Log(
                "main-editor-entry-guard",
                "phase=clear card=\(mainWorkspacePhase0CardID(mainEditorEntryFinishGuardCardID))"
            )
        }
        mainEditorEntryFinishGuardCardID = nil
        mainEditorEntryFinishGuardUntil = .distantPast
    }

    func shouldSuppressFinishEditingDuringEntryGuard(cardID: UUID, reason: FinishEditingReason) -> Bool {
        guard reason == .generic else { return false }
        guard !showFocusMode else { return false }
        guard mainEditorEntryFinishGuardCardID == cardID else { return false }
        guard Date() < mainEditorEntryFinishGuardUntil else { return false }
        return true
    }

    func shouldAllowGenericFinishEditing(cardID: UUID) -> Bool {
        guard !showFocusMode else { return true }
        return resolvedActiveMainEditorTextView(for: cardID) == nil
    }

    func beginCardEditing(_ card: SceneCard, explicitCaretLocation: Int? = nil) {
        mainWorkspacePhase0Log(
            "begin-card-edit-request",
            "card=\(mainWorkspacePhase0CardID(card.id)) activeBefore=\(mainWorkspacePhase0CardID(activeCardID)) " +
            "editingBefore=\(mainWorkspacePhase0CardID(editingCardID)) explicitCaret=\(explicitCaretLocation.map(String.init) ?? "nil")"
        )
        if editingCardID != nil {
            suppressMainFocusRestoreAfterFinishEditing = true
        }
        finishEditing(reason: .transition)
        prepareMainEditorSessionRequest(for: card, explicitCaretLocation: explicitCaretLocation)
        beginMainEditingScrollIsolation(
            for: card.id,
            reason: explicitCaretLocation == nil ? "beginCardEditing" : "beginCardEditing.explicitCaret"
        )
        pendingMainEditingSiblingNavigationTargetID = nil
        if let explicitCaretLocation {
            pendingMainEditingViewportKeepVisibleCardID = nil
            pendingMainEditingViewportRevealEdge = nil
            let textLength = (card.content as NSString).length
            let safeLocation = min(max(0, explicitCaretLocation), textLength)
            mainCaretLocationByCardID[card.id] = safeLocation
            mainProgrammaticCaretSuppressEnsureCardID = card.id
            mainProgrammaticCaretExpectedCardID = card.id
            mainProgrammaticCaretExpectedLocation = safeLocation
            mainProgrammaticCaretSelectionIgnoreUntil = Date().addingTimeInterval(0.28)
        } else {
            pendingMainEditingViewportKeepVisibleCardID = card.id
            pendingMainEditingViewportRevealEdge = nil
            mainProgrammaticCaretSuppressEnsureCardID = nil
            mainProgrammaticCaretExpectedCardID = nil
            mainProgrammaticCaretExpectedLocation = -1
            mainProgrammaticCaretSelectionIgnoreUntil = .distantPast
        }
        changeActiveCard(to: card)
        editingCardID = card.id
        editingStartContent = card.content
        editingStartState = captureScenarioState()
        editingIsNewCard = false
        selectedCardIDs = [card.id]
        armMainEditorEntryFinishGuard(for: card.id)
        mainWorkspacePhase0Log(
            "begin-card-edit-applied",
            "card=\(mainWorkspacePhase0CardID(card.id)) active=\(mainWorkspacePhase0CardID(activeCardID)) " +
            "editing=\(mainWorkspacePhase0CardID(editingCardID)) keepVisible=\(mainWorkspacePhase0CardID(pendingMainEditingViewportKeepVisibleCardID)) " +
            "revealEdge=\(String(describing: pendingMainEditingViewportRevealEdge)) responder=\(mainWorkspacePhase0ResponderSummary(expectedText: card.content))"
        )
    }

    func resolvedMainCardLiveEditingHeightOverride(for card: SceneCard) -> CGFloat? {
        guard editingCardID == card.id else { return nil }
        guard mainEditorSession.mountedCardID == card.id,
              let liveBodyHeight = mainEditorSession.liveBodyHeight,
              liveBodyHeight > 1 else {
            return nil
        }
        return ceil(liveBodyHeight + 48)
    }

    func resolvedMainCardHeightCacheKey(
        for card: SceneCard,
        mode: MainCardHeightMode
    ) -> MainCardHeightCacheKey {
        let lineSpacingBucket = Int((CGFloat(mainCardLineSpacingValue) * 10).rounded())
        let fontSizeBucket = Int((CGFloat(fontSize) * 10).rounded())

        let measuringText: String
        let width: CGFloat
        switch mode {
        case .display:
            measuringText = card.content.isEmpty ? "내용 없음" : card.content
            width = max(1, MainCanvasLayoutMetrics.cardWidth - (MainEditorLayoutMetrics.mainCardContentPadding * 2))
        case .editingFallback:
            measuringText = card.content
            width = max(1, MainCanvasLayoutMetrics.textWidth)
        }

        let normalizedText = normalizedSharedMeasurementText(measuringText)
        return MainCardHeightCacheKey(
            cardID: card.id,
            contentFingerprint: sharedStableTextFingerprint(normalizedText),
            textLength: normalizedText.utf16.count,
            widthBucket: Int((width * 10).rounded()),
            fontSizeBucket: fontSizeBucket,
            lineSpacingBucket: lineSpacingBucket,
            mode: mode
        )
    }

    func storeMainCardHeightRecord(_ record: MainCardHeightRecord) {
        if mainCardHeightRecordByKey.count >= 4096 {
            mainCardHeightRecordByKey.removeAll(keepingCapacity: true)
        }
        mainCardHeightRecordByKey[record.key] = record
    }

    func resolvedMainCardHeightRecord(
        for card: SceneCard,
        liveEditingHeightOverride: CGFloat? = nil
    ) -> MainCardHeightRecord {
        if let liveEditingHeightOverride {
            let record = MainCardHeightRecord(
                key: resolvedMainCardHeightCacheKey(for: card, mode: .editingFallback),
                height: liveEditingHeightOverride
            )
            return record
        }

        let lineSpacing = CGFloat(mainCardLineSpacingValue)
        let resolvedFontSize = CGFloat(fontSize)

        if editingCardID == card.id {
            if let liveEditingHeightOverride = resolvedMainCardLiveEditingHeightOverride(for: card) {
                let record = MainCardHeightRecord(
                    key: resolvedMainCardHeightCacheKey(for: card, mode: .editingFallback),
                    height: liveEditingHeightOverride
                )
                return record
            }
            let recordKey = resolvedMainCardHeightCacheKey(for: card, mode: .editingFallback)
            if let cached = mainCardHeightRecordByKey[recordKey] {
                return cached
            }

            let editorBodyHeight = sharedMeasuredTextBodyHeight(
                text: card.content,
                fontSize: resolvedFontSize,
                lineSpacing: lineSpacing,
                width: MainCanvasLayoutMetrics.textWidth,
                lineFragmentPadding: MainEditorLayoutMetrics.mainEditorLineFragmentPadding,
                safetyInset: 0
            )
            let record = MainCardHeightRecord(
                key: recordKey,
                height: ceil(editorBodyHeight + 48)
            )
            storeMainCardHeightRecord(record)
            return record
        }

        let displayText = card.content.isEmpty ? "내용 없음" : card.content
        let displayWidth = max(1, MainCanvasLayoutMetrics.cardWidth - (MainEditorLayoutMetrics.mainCardContentPadding * 2))
        let recordKey = resolvedMainCardHeightCacheKey(for: card, mode: .display)
        if let cached = mainCardHeightRecordByKey[recordKey] {
            return cached
        }

        let displayBodyHeight = sharedMeasuredTextBodyHeight(
            text: displayText,
            fontSize: resolvedFontSize,
            lineSpacing: lineSpacing,
            width: displayWidth,
            lineFragmentPadding: 0,
            safetyInset: 0
        )
        let record = MainCardHeightRecord(
            key: recordKey,
            height: ceil(displayBodyHeight + (MainEditorLayoutMetrics.mainCardContentPadding * 2))
        )
        storeMainCardHeightRecord(record)
        return record
    }

    func resolvedMainCardHeight(
        for card: SceneCard,
        liveEditingHeightOverride: CGFloat? = nil
    ) -> CGFloat {
        if let liveEditingHeightOverride {
            return liveEditingHeightOverride
        }
        if let liveBodyHeight = resolvedMainCardLiveEditingHeightOverride(for: card) {
            return liveBodyHeight
        }
        return resolvedMainCardHeightRecord(for: card).height
    }
}
