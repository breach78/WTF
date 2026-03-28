import SwiftUI
import AppKit

extension ScenarioWriterView {

    private var focusModeCardsBackgroundColor: Color {
        let fallbackLight = (r: 0.75, g: 0.84, b: 1.0)
        let fallbackDark = (r: 0.16, g: 0.23, b: 0.31)
        let hex = isDarkAppearanceActive ? darkCardActiveColorHex : cardActiveColorHex
        if let rgb = rgbFromHex(hex) {
            return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
        }
        let fallback = isDarkAppearanceActive ? fallbackDark : fallbackLight
        return Color(red: fallback.r, green: fallback.g, blue: fallback.b)
    }

    private var focusModeSearchPopupBackgroundColor: Color {
        appearance == "light"
            ? Color.white.opacity(0.96)
            : Color.black.opacity(0.82)
    }

    private var focusModeSearchPopupBorderColor: Color {
        appearance == "light"
            ? Color.black.opacity(0.10)
            : Color.white.opacity(0.12)
    }

    private var focusModeSearchStatusText: String {
        let trimmed = focusModeSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "검색어 입력" }
        guard !focusModeSearchMatches.isEmpty else { return "결과 없음" }
        let current = focusModeSearchSelectedMatchIndex >= 0
            ? min(focusModeSearchSelectedMatchIndex + 1, focusModeSearchMatches.count)
            : 0
        return "\(current)/\(focusModeSearchMatches.count)"
    }

    @ViewBuilder
    var focusModeSearchPopup: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(appearance == "light" ? .black.opacity(0.55) : .white.opacity(0.78))
                TextField(
                    "",
                    text: focusModeSearchTextBinding,
                    prompt: Text("포커스 모드 검색")
                        .foregroundColor(appearance == "light" ? .black.opacity(0.35) : .white.opacity(0.45))
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(appearance == "light" ? .black : .white)
                .focused($isFocusModeSearchFieldFocused)
                .onChange(of: focusModeSearchText) { _, _ in
                    refreshFocusModeSearchResults()
                }
                .onSubmit {
                    moveFocusModeSearchSelection(step: 1)
                }
                Button {
                    closeFocusModeSearchPopup()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(appearance == "light" ? .black.opacity(0.42) : .white.opacity(0.42))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Text(focusModeSearchStatusText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(appearance == "light" ? .black.opacity(0.58) : .white.opacity(0.72))
                Spacer(minLength: 0)
                Button {
                    moveFocusModeSearchSelection(step: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(focusModeSearchMatches.isEmpty)
                .opacity(focusModeSearchMatches.isEmpty ? 0.35 : 1.0)

                Button {
                    moveFocusModeSearchSelection(step: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(focusModeSearchMatches.isEmpty)
                .opacity(focusModeSearchMatches.isEmpty ? 0.35 : 1.0)
            }
            .foregroundStyle(appearance == "light" ? .black.opacity(0.82) : .white.opacity(0.86))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 296)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(focusModeSearchPopupBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(focusModeSearchPopupBorderColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 20, x: 0, y: 10)
    }

    @ViewBuilder
    func focusModeCanvasBackdrop() -> some View {
        Color.black.opacity(0.90)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                guard showFocusMode else { return }
                toggleFocusMode()
            }
    }

    @ViewBuilder
    func focusModeCanvasScrollContent(size: CGSize, cards: [SceneCard]) -> some View {
        let cardWidth = resolvedFocusModeCardWidth(forCanvasWidth: size.width)
        VStack(spacing: 0) {
            Color.clear.frame(height: max(48, size.height * 0.08))
            focusModeCardsColumn(cards: cards, cardWidth: cardWidth)
            Color.clear.frame(height: max(72, size.height * 0.12))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func focusModeCardsColumn(cards: [SceneCard], cardWidth: CGFloat) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                focusModeCardBlock(card, cardWidth: cardWidth)
                    .id(focusModeCardScrollID(card.id))
                if index < cards.count - 1 {
                    focusModeCardDivider(card: card, nextCard: cards[index + 1])
                }
            }
        }
        .background(focusModeCardsBackgroundColor)
        .overlay(Rectangle().stroke(focusModeCardsBorderColor, lineWidth: 1))
        .frame(width: cardWidth)
        .padding(.horizontal, FocusModeLayoutMetrics.focusModeOuterHorizontalPadding)
    }

    @ViewBuilder
    private func focusModeCardDivider(card: SceneCard, nextCard: SceneCard) -> some View {
        let parentChanged = card.parent?.id != nextCard.parent?.id
        Rectangle()
            .fill(
                parentChanged
                ? Color(hue: 0.61, saturation: 0.5, brightness: 0.95).opacity(0.85)
                : (appearance == "light" ? Color.black.opacity(0.08) : Color.white.opacity(0.12))
            )
            .frame(height: parentChanged ? 2 : 1)
            .padding(.horizontal, parentChanged ? 20 : 0)
    }

    private var focusModeCardsBorderColor: Color {
        appearance == "light" ? Color.black.opacity(0.10) : Color.white.opacity(0.12)
    }

    private func focusModeCardScrollID(_ cardID: UUID) -> String {
        "focus-card-\(cardID)"
    }

    @discardableResult
    func beginFocusModeVerticalScrollAuthority(
        kind: FocusModeVerticalScrollAuthorityKind,
        targetCardID: UUID?
    ) -> FocusModeVerticalScrollAuthority {
        focusVerticalScrollAuthoritySequence += 1
        let authority = FocusModeVerticalScrollAuthority(
            id: focusVerticalScrollAuthoritySequence,
            kind: kind,
            targetCardID: targetCardID
        )
        focusVerticalScrollAuthority = authority
        return authority
    }

    func isFocusModeVerticalScrollAuthorityCurrent(_ authority: FocusModeVerticalScrollAuthority?) -> Bool {
        guard let authority else { return false }
        return focusVerticalScrollAuthority == authority
    }

    func isFocusModeVerticalScrollAuthorityCurrent(
        kind: FocusModeVerticalScrollAuthorityKind,
        targetCardID: UUID?
    ) -> Bool {
        guard let authority = focusVerticalScrollAuthority else { return false }
        guard authority.kind == kind else { return false }
        return authority.targetCardID == targetCardID
    }

    func handleFocusModeCanvasActiveCardChange(_ newID: UUID?, proxy: ScrollViewProxy) {
        guard let id = newID else { return }
        focusResponderCardByObjectID.removeAll()
        let matchesPendingProgrammaticBegin = consumePendingFocusModeProgrammaticBeginMatch(for: id)
        if handleFocusModeSuppressedScrollIfNeeded(
            id: id,
            matchesPendingProgrammaticBegin: matchesPendingProgrammaticBegin
        ) {
            return
        }
        let authority = beginFocusModeVerticalScrollAuthority(kind: .canvasNavigation, targetCardID: id)
        performFocusModeCanvasActiveCardScroll(id: id, proxy: proxy, authority: authority)
        applyFocusModeCanvasActiveCardEditorState(id: id)
        scheduleFocusModeCanvasActiveCardBeginEditingIfNeeded(id: id)
    }

    private func consumePendingFocusModeProgrammaticBeginMatch(for id: UUID) -> Bool {
        let matchesPendingProgrammaticBegin = (focusPendingProgrammaticBeginEditCardID == id)
        if matchesPendingProgrammaticBegin {
            focusPendingProgrammaticBeginEditCardID = nil
        }
        return matchesPendingProgrammaticBegin
    }

    private func handleFocusModeSuppressedScrollIfNeeded(
        id: UUID,
        matchesPendingProgrammaticBegin: Bool
    ) -> Bool {
        guard suppressFocusModeScrollOnce else { return false }
        suppressFocusModeScrollOnce = false
        if matchesPendingProgrammaticBegin {
            if showFocusMode {
                focusModeEditorCardID = id
            }
            return true
        }
        if showFocusMode, let card = findCard(by: id) {
            beginFocusModeEditing(
                card,
                cursorToEnd: false,
                animatedScroll: false,
                preserveViewportOnSwitch: true,
                placeCursorAtStartWhenNoHint: false
            )
        } else if showFocusMode {
            focusModeEditorCardID = id
        }
        return true
    }

    private func performFocusModeCanvasActiveCardScroll(
        id: UUID,
        proxy: ScrollViewProxy,
        authority: FocusModeVerticalScrollAuthority
    ) {
        guard isFocusModeVerticalScrollAuthorityCurrent(authority) else { return }
        let anchor = focusModeNextCardScrollAnchor ?? .center
        let shouldAnimate = focusModeNextCardScrollAnimated
        focusModeNextCardScrollAnchor = nil
        focusModeNextCardScrollAnimated = true
        if shouldAnimate {
            withAnimation(quickEaseAnimation) {
                proxy.scrollTo(focusModeCardScrollID(id), anchor: anchor)
            }
        } else {
            proxy.scrollTo(focusModeCardScrollID(id), anchor: anchor)
        }
    }

    private func applyFocusModeCanvasActiveCardEditorState(id: UUID) {
        if showFocusMode {
            focusModeEditorCardID = id
        }
    }

    private func scheduleFocusModeCanvasActiveCardBeginEditingIfNeeded(id: UUID) {
        if showFocusMode, editingCardID != id, let card = findCard(by: id) {
            DispatchQueue.main.async {
                beginFocusModeEditing(card, cursorToEnd: false)
            }
        }
    }

    func handleFocusModeCanvasAppear(proxy: ScrollViewProxy) {
        guard showFocusMode else { return }
        guard focusModePresentationPhase == .entering || focusModePresentationPhase == .active else { return }
        guard let id = focusModeEditorCardID ?? editingCardID ?? activeCardID else { return }
        let authority = beginFocusModeVerticalScrollAuthority(kind: .canvasNavigation, targetCardID: id)
        DispatchQueue.main.async {
            guard isFocusModeVerticalScrollAuthorityCurrent(authority) else { return }
            proxy.scrollTo(focusModeCardScrollID(id), anchor: .center)
        }
    }

    func handleFocusModeFallbackRevealTickChange(proxy: ScrollViewProxy) {
        guard showFocusMode else { return }
        guard let id = focusModePendingFallbackRevealCardID else { return }
        guard isFocusModeVerticalScrollAuthorityCurrent(kind: .fallbackReveal, targetCardID: id) else { return }
        let authority = focusVerticalScrollAuthority
        DispatchQueue.main.async {
            guard isFocusModeVerticalScrollAuthorityCurrent(authority) else { return }
            proxy.scrollTo(focusModeCardScrollID(id))
        }
    }

    func handleFocusModeCanvasWidthChange(oldWidth: CGFloat, newWidth: CGFloat) {
        guard showFocusMode else { return }
        let oldResolvedWidth = resolvedFocusModeCardWidth(forCanvasWidth: oldWidth)
        let newResolvedWidth = resolvedFocusModeCardWidth(forCanvasWidth: newWidth)
        let widthChanged = abs(newResolvedWidth - oldResolvedWidth) > 0.5
        if widthChanged {
            focusModeLayoutCoordinator.reset()
            requestFocusModeOffsetNormalization(includeActive: false, force: true, reason: "canvas-width-change")
        }
    }

    func openFocusModeSearchPopup() {
        guard showFocusMode else { return }
        if !showFocusModeSearchPopup {
            withAnimation(quickEaseAnimation) {
                showFocusModeSearchPopup = true
            }
        }
        refreshFocusModeSearchResults()
        DispatchQueue.main.async {
            guard showFocusModeSearchPopup else { return }
            isFocusModeSearchFieldFocused = true
        }
    }

    func closeFocusModeSearchPopup() {
        focusModeSearchHighlightRequestID += 1
        withAnimation(quickEaseAnimation) {
            showFocusModeSearchPopup = false
        }
        focusModeSearchText = ""
        focusModeSearchMatches = []
        focusModeSearchSelectedMatchIndex = -1
        isFocusModeSearchFieldFocused = false
    }

    private var focusModeSearchHighlightColor: NSColor {
        if appearance == "light" {
            return NSColor.systemYellow.withAlphaComponent(0.38)
        }
        return NSColor.systemYellow.withAlphaComponent(0.26)
    }

    func clearPersistentFocusModeSearchHighlight() {
        if let match = focusModeSearchPersistentHighlight,
           let textView = focusModeSearchHighlightTextViewBox.textView,
           let layoutManager = textView.layoutManager {
            let textLength = (textView.string as NSString).length
            let safeLocation = min(max(0, match.range.location), textLength)
            let safeLength = min(max(0, match.range.length), max(0, textLength - safeLocation))
            if safeLength > 0 {
                let safeRange = NSRange(location: safeLocation, length: safeLength)
                layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: safeRange)
            }
        }
        focusModeSearchPersistentHighlight = nil
        focusModeSearchHighlightTextViewBox.textView = nil
    }

    private func refreshFocusModeSearchResults() {
        let trimmedQuery = focusModeSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            focusModeSearchMatches = []
            focusModeSearchSelectedMatchIndex = -1
            return
        }

        let previousMatch = focusModeSearchMatches.indices.contains(focusModeSearchSelectedMatchIndex)
            ? focusModeSearchMatches[focusModeSearchSelectedMatchIndex]
            : nil

        var matches: [FocusModeSearchMatch] = []
        for card in focusedColumnCards() {
            let text = card.content as NSString
            var searchRange = NSRange(location: 0, length: text.length)
            while searchRange.length > 0 {
                let found = text.range(
                    of: trimmedQuery,
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    range: searchRange
                )
                guard found.location != NSNotFound, found.length > 0 else { break }
                matches.append(FocusModeSearchMatch(cardID: card.id, range: found))
                let nextLocation = found.location + found.length
                guard nextLocation < text.length else { break }
                searchRange = NSRange(location: nextLocation, length: text.length - nextLocation)
            }
        }

        focusModeSearchMatches = matches
        if let previousMatch,
           let preservedIndex = matches.firstIndex(of: previousMatch) {
            focusModeSearchSelectedMatchIndex = preservedIndex
        } else {
            focusModeSearchSelectedMatchIndex = -1
        }
    }

    func refreshFocusModeSearchResultsIfNeeded() {
        guard showFocusModeSearchPopup || focusModeSearchPersistentHighlight != nil else { return }
        refreshFocusModeSearchResults()
    }

    func moveFocusModeSearchSelection(step: Int) {
        refreshFocusModeSearchResults()
        guard !focusModeSearchMatches.isEmpty else { return }

        let count = focusModeSearchMatches.count
        let nextIndex: Int
        if focusModeSearchSelectedMatchIndex < 0 || focusModeSearchSelectedMatchIndex >= count {
            nextIndex = step >= 0 ? 0 : (count - 1)
        } else {
            nextIndex = (focusModeSearchSelectedMatchIndex + step + count) % count
        }

        focusModeSearchSelectedMatchIndex = nextIndex
        revealFocusModeSearchMatch(focusModeSearchMatches[nextIndex])
    }

    private func revealFocusModeSearchMatch(_ match: FocusModeSearchMatch) {
        guard let card = findCard(by: match.cardID) else { return }
        beginFocusModeEditing(
            card,
            cursorToEnd: false,
            cardScrollAnchor: .center,
            animatedScroll: true,
            preserveViewportOnSwitch: false,
            placeCursorAtStartWhenNoHint: false,
            allowPendingEntryCaretHint: false,
            explicitCaretLocation: match.range.location
        )
        if isFocusModeSearchFieldFocused {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                guard showFocusModeSearchPopup else { return }
                isFocusModeSearchFieldFocused = true
            }
        }
        scheduleFocusModeSearchHighlight(match)
    }

    private func scheduleFocusModeSearchHighlight(_ match: FocusModeSearchMatch) {
        focusModeSearchHighlightRequestID += 1
        let requestID = focusModeSearchHighlightRequestID
        let delays: [Double] = [0.0, 0.08, 0.18]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                applyFocusModeSearchHighlightIfPossible(match, requestID: requestID)
            }
        }
    }

    private func applyFocusModeSearchHighlightIfPossible(
        _ match: FocusModeSearchMatch,
        requestID: Int
    ) {
        guard showFocusMode else { return }
        guard requestID == focusModeSearchHighlightRequestID else { return }
        guard let card = findCard(by: match.cardID) else { return }
        guard let textView = resolveFocusModeTextView(for: card) else { return }

        let textLength = (textView.string as NSString).length
        let safeLocation = min(max(0, match.range.location), textLength)
        let safeLength = min(max(0, match.range.length), max(0, textLength - safeLocation))
        guard safeLength > 0 else { return }

        let safeRange = NSRange(location: safeLocation, length: safeLength)
        clearPersistentFocusModeSearchHighlight()
        if let layoutManager = textView.layoutManager {
            layoutManager.addTemporaryAttributes(
                [.backgroundColor: focusModeSearchHighlightColor],
                forCharacterRange: safeRange
            )
            focusModeSearchPersistentHighlight = FocusModeSearchMatch(
                cardID: match.cardID,
                range: safeRange
            )
            focusModeSearchHighlightTextViewBox.textView = textView
        }
        ensureFocusModeSearchRangeVisible(textView: textView, range: safeRange)
        textView.showFindIndicator(for: safeRange)
    }

    private func resolveFocusModeTextView(for card: SceneCard) -> NSTextView? {
        let activeEditorCardID = focusModeEditorCardID ?? editingCardID ?? activeCardID
        guard activeEditorCardID == card.id else { return nil }
        guard let textView = resolveSingleFocusModeEditableTextView() else { return nil }
        focusResponderCardByObjectID[ObjectIdentifier(textView)] = card.id
        return textView
    }

    func resolveSingleFocusModeEditableTextView() -> NSTextView? {
        guard showFocusMode else { return nil }
        guard !isReferenceWindowFocused else { return nil }

        if let responder = NSApp.keyWindow?.firstResponder as? NSTextView,
           responder.isEditable,
           !isReferenceTextView(responder) {
            return responder
        }

        guard let root = NSApp.keyWindow?.contentView else { return nil }
        let editableTextViews = collectTextViews(in: root).filter { textView in
            textView.isEditable && !isReferenceTextView(textView)
        }
        guard !editableTextViews.isEmpty else { return nil }

        if let activeEditorCardID = focusModeEditorCardID ?? editingCardID ?? activeCardID,
           let mapped = editableTextViews.first(where: { textView in
               focusResponderCardByObjectID[ObjectIdentifier(textView)] == activeEditorCardID
           }) {
            return mapped
        }
        return editableTextViews.first
    }

    @ViewBuilder
    func focusModeCardBlock(_ card: SceneCard, cardWidth: CGFloat) -> some View {
        let isActiveCard = activeCardID == card.id
        let editorCardID = focusModeEditorCardID ?? editingCardID ?? activeCardID
        let isCloneLinked = scenario.isCardCloned(card.id)
        let hasLinkedCards = scenario.hasLinkedCards(card.id)
        let isLinkedCard = scenario.isLinkedCard(card.id)
        FocusModeCardEditor(
            card: card,
            isActive: isActiveCard,
            showsEditor: editorCardID == card.id,
            layoutCoordinator: focusModeLayoutCoordinator,
            cardWidth: cardWidth,
            fontSize: fontSize,
            appearance: appearance,
            horizontalInset: FocusModeLayoutMetrics.focusModeHorizontalPadding,
            focusModeEditorCardID: $focusModeEditorCardID,
            onActivate: { clickLocation in
                activateFocusModeCardFromClick(
                    card,
                    clickLocation: clickLocation,
                    cardWidth: cardWidth
                )
            },
            onContentChange: { oldValue, newValue in
                handleFocusModeCardContentChange(cardID: card.id, oldValue: oldValue, newValue: newValue)
            }
        )
        .overlay(alignment: .topLeading) {
            if isCloneLinked {
                Rectangle()
                    .fill(appearance == "light" ? Color.black.opacity(0.48) : Color.white.opacity(0.85))
                    .frame(width: 8, height: 8)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 3) {
                if hasLinkedCards {
                    Rectangle()
                        .fill(appearance == "light" ? Color.black.opacity(0.48) : Color.white.opacity(0.85))
                        .frame(width: 8, height: 8)
                        .allowsHitTesting(false)
                }
                if isLinkedCard {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0))
                        path.addLine(to: CGPoint(x: 8, y: 0))
                        path.addLine(to: CGPoint(x: 8, y: 8))
                        path.closeSubpath()
                    }
                    .fill(appearance == "light" ? Color.black.opacity(0.48) : Color.white.opacity(0.85))
                    .frame(width: 8, height: 8)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    func resolvedFocusModeCardWidth(forCanvasWidth canvasWidth: CGFloat) -> CGFloat {
        _ = canvasWidth
        return FocusModeLayoutMetrics.focusModePreferredCardWidth
    }

    func activateFocusModeCardFromClick(
        _ card: SceneCard,
        clickLocation: CGPoint? = nil,
        cardWidth: CGFloat? = nil
    ) {
        if splitModeEnabled && !isSplitPaneActive {
            activateSplitPaneIfNeeded()
        }
        let clickCaretLocation = resolveFocusModeClickCaretLocation(
            for: card,
            clickLocation: clickLocation,
            cardWidth: cardWidth
        )

        pendingFocusModeEntryCaretHint = nil
        clearFocusDeleteSelectionLock()
        if activeCardID != card.id {
            beginFocusModeEditing(
                card,
                cursorToEnd: false,
                animatedScroll: false,
                preserveViewportOnSwitch: true,
                placeCursorAtStartWhenNoHint: false,
                allowPendingEntryCaretHint: false,
                explicitCaretLocation: clickCaretLocation
            )
        } else {
            selectedCardIDs = [card.id]
            if editingCardID != card.id {
                editingCardID = card.id
                editingStartContent = card.content
                editingStartState = captureScenarioState()
                editingIsNewCard = false
            }
            focusModeEditorCardID = card.id
        }
    }

    func resolveFocusModeClickCaretLocation(
        for card: SceneCard,
        clickLocation: CGPoint? = nil,
        cardWidth: CGFloat? = nil
    ) -> Int? {
        let isCurrentEditorTarget =
            focusModeEditorCardID == card.id ||
            editingCardID == card.id ||
            activeCardID == card.id
        if !isCurrentEditorTarget,
           let clickLocation,
           let cardWidth {
            return focusModeLayoutCoordinator.resolvedClickCaretLocation(
                for: card,
                localPoint: clickLocation,
                cardWidth: cardWidth,
                fontSize: fontSize,
                lineSpacing: focusModeLineSpacingValue,
                horizontalInset: FocusModeLayoutMetrics.focusModeHorizontalPadding,
                verticalInset: FocusModeCardEditor.verticalInset
            )
        }

        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            let responderID = ObjectIdentifier(textView)
            let mappedCardID = focusResponderCardByObjectID[responderID]
            let belongsToTarget = mappedCardID == card.id || textView.string == card.content
            if belongsToTarget {
                guard let window = textView.window else { return nil }
                let screenPoint = NSEvent.mouseLocation
                let windowPoint = window.convertPoint(fromScreen: screenPoint)
                let localPoint = textView.convert(windowPoint, from: nil)
                let rawIndex = textView.characterIndexForInsertion(at: localPoint)
                let length = (textView.string as NSString).length
                let safeIndex = max(0, min(rawIndex, length))
                return safeIndex
            }
        }

        guard let clickLocation, let cardWidth else { return nil }
        return focusModeLayoutCoordinator.resolvedClickCaretLocation(
            for: card,
            localPoint: clickLocation,
            cardWidth: cardWidth,
            fontSize: fontSize,
            lineSpacing: focusModeLineSpacingValue,
            horizontalInset: FocusModeLayoutMetrics.focusModeHorizontalPadding,
            verticalInset: FocusModeCardEditor.verticalInset
        )
    }

    func focusedColumnCards() -> [SceneCard] {
        let levelsData = resolvedLevelsWithParents()
        guard let activeID = activeCardID else {
            return levelsData.first?.cards ?? []
        }
        guard let index = levelsData.firstIndex(where: { data in
            data.cards.contains(where: { $0.id == activeID })
        }) else {
            return levelsData.first?.cards ?? []
        }
        let data = levelsData[index]
        let filtered = (index <= 1 || isActiveCardRoot) ? data.cards : data.cards.filter { $0.category == activeCategory }
        return filtered
    }
}
