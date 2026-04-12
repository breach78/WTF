import AppKit
import SwiftUI

enum BoardCanvasTone: CaseIterable {
    case sand
    case parchment
    case stone

    var next: BoardCanvasTone {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else {
            return .sand
        }
        return all[(index + 1) % all.count]
    }

    var boardHex: UInt32 {
        switch self {
        case .sand:
            return 0xD2C8BA
        case .parchment:
            return 0xDDD4C6
        case .stone:
            return 0xCAC3B7
        }
    }

    var boardFill: Color {
        Color(hex: boardHex)
    }

    var windowHex: UInt32 {
        switch self {
        case .sand:
            return 0xEFEAE3
        case .parchment:
            return 0xF1ECE4
        case .stone:
            return 0xE9E5DF
        }
    }

    var windowFill: Color {
        Color(hex: windowHex)
    }
}

struct BWRBoardCanvasView: View {
    let project: BoardProject
    let searchMatches: Set<UUID>
    @Binding var interaction: BoardInteractionState
    @Binding var transientGestureState: BoardTransientGestureState
    @Binding var cursorViewportBounds: BoardVisibleBounds?
    let keyboardHandle: BWRBoardKeyboardHandle
    let showsSlotGuides: Bool
    let canvasTone: BoardCanvasTone
    @Binding var cardScale: CGFloat
    let cardScaleRange: ClosedRange<CGFloat>
    let gestureCancellationToken: Int
    let noteBinding: (UUID) -> Binding<String>?
    let assetForCard: (UUID) -> BoardAsset?
    let onOpenCardForEditing: (UUID) -> Void
    let onCreateCard: (BoardSlot) -> Void
    let onCycleTint: (UUID) -> Void
    let onCommitEditing: () -> Void
    let onCancelEditing: () -> Void
    let onAdvanceEditing: (Bool) -> Void
    let onApplyDrag: (BoardDragSession) -> Void

    @State private var dragSession: BoardDragSession?
    @State private var dragTranslation: CGSize = .zero
    @State private var isSettlingDrop = false
    @State private var frozenDragReflowSlots: [UUID: BoardSlot] = [:]
    @State private var dropSettleToken = 0
    @State private var marqueeRect: CGRect?
    @State private var marqueeStartSlot: BoardSlot?
    @State private var isHoverSuppressedByScroll = false
    @State private var hoverResumeToken = 0
    @State private var isInteractionSuppressedByZoom = false
    @State private var zoomResumeToken = 0
    @FocusState private var focusedCardID: UUID?
    @FocusState private var dragPreviewFocusID: UUID?
    @State private var viewportHandle = BWRBoardViewportHandle()

    private var slotSize: CGSize {
        BWRBoardLayoutMetrics.cardSize
    }

    private var visibleBounds: BoardVisibleBounds {
        var extraSlots = interaction.slotsAffectingVisibleBounds
        if let dragSession {
            extraSlots.formUnion(dragSession.previewSlotSet)
        }
        extraSlots.formUnion(dragReflowSlots.values)
        return project.visibleBounds(including: extraSlots)
    }

    private var boardLayout: BoardCanvasLayout {
        BoardCanvasLayout(
            visibleBounds: visibleBounds,
            slotSize: slotSize,
            horizontalSpacing: BWRBoardLayoutMetrics.horizontalGridSpacing,
            verticalSpacing: BWRBoardLayoutMetrics.verticalGridSpacing,
            padding: BWRBoardLayoutMetrics.outerPadding
        )
    }

    private var slotStep: CGSize {
        CGSize(
            width: slotSize.width + BWRBoardLayoutMetrics.horizontalGridSpacing,
            height: slotSize.height + BWRBoardLayoutMetrics.verticalGridSpacing
        )
    }

    private let pointerDragThreshold: CGFloat = 4

    private var transientGestureStateValue: BoardTransientGestureState {
        BoardTransientGestureState(
            hasDragSession: dragSession != nil,
            hasMarqueeSelection: marqueeStartSlot != nil || marqueeRect != nil
        )
    }

    private var isActivelyDragging: Bool {
        dragSession != nil && (abs(dragTranslation.width) > 0.5 || abs(dragTranslation.height) > 0.5)
    }

    private var computedDragReflowSlots: [UUID: BoardSlot] {
        guard let dragSession, isActivelyDragging else {
            return [:]
        }

        return BoardDragController.previewReflowSlots(project: project, session: dragSession)
    }

    private var dragReflowSlots: [UUID: BoardSlot] {
        isSettlingDrop ? frozenDragReflowSlots : computedDragReflowSlots
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: BWRBoardLayoutMetrics.verticalGridSpacing) {
                        ForEach(visibleBounds.rows, id: \.self) { row in
                            HStack(spacing: BWRBoardLayoutMetrics.horizontalGridSpacing) {
                                ForEach(visibleBounds.columns, id: \.self) { column in
                                    slotCell(for: BoardSlot(row: row, column: column))
                                        .id(BoardSlot(row: row, column: column).id)
                                }
                            }
                        }
                    }
                    .padding(BWRBoardLayoutMetrics.outerPadding)

                    dragDestinationOverlay
                    dragReflowOverlay
                    dragPreviewOverlay
                    marqueeOverlay
                }
                .frame(
                    width: boardWidth,
                    height: boardHeight,
                    alignment: .topLeading
                )
                .contentShape(Rectangle())
            }
            .scrollIndicators(.hidden)
            .overlay {
                ZStack {
                    BWRBoardPointerMonitor(
                        isEnabled: interaction.editingCardID == nil,
                        viewportHandle: viewportHandle,
                        onHoverChange: handlePointerHoverChange(_:),
                        onPrimaryDown: handlePointerPrimaryDown(_:),
                        onPrimaryDragChanged: handlePointerDragChanged(_:),
                        onPrimaryUp: handlePointerPrimaryUp(_:clickCount:)
                    )
                    .allowsHitTesting(false)

                    BWRBoardScrollMonitor(
                        isEnabled: true,
                        viewportHandle: viewportHandle,
                        onScrollEvent: suspendHoverForScroll,
                        onCommandZoomScroll: handleCommandZoomScroll(_:anchorInViewport:)
                    )
                    .allowsHitTesting(false)
                }
            }
            .background {
                BWRBoardNativeMagnificationBridge(
                    magnification: $cardScale,
                    magnificationRange: cardScaleRange,
                    viewportHandle: viewportHandle,
                    onWillStartLiveMagnify: beginZoomInteraction,
                    onDidEndLiveMagnify: endZoomInteractionSoon
                )
                .allowsHitTesting(false)
            }
            .onChange(of: interaction.keyboardCursorSlot) { _, newValue in
                scrollToCursor(newValue, using: proxy)
            }
            .onAppear {
                scrollToCursor(interaction.keyboardCursorSlot, using: proxy)
                refreshCursorViewportBounds()
            }
        }
        .onHover { isHovering in
            if !isHovering {
                interaction.hoverSlot = nil
            }
        }
        .background {
            ZStack {
                canvasTone.boardFill
                Rectangle()
                    .fill(.white.opacity(0.06))
                    .blur(radius: BWRBoardLayoutMetrics.boardGlowBlurRadius)
                    .frame(
                        width: BWRBoardLayoutMetrics.boardGlowSize.width,
                        height: BWRBoardLayoutMetrics.boardGlowSize.height
                    )
                    .offset(
                        x: BWRBoardLayoutMetrics.boardGlowOffset.width,
                        y: BWRBoardLayoutMetrics.boardGlowOffset.height
                    )
            }
        }
        .onChange(of: editingCardID) { _, newValue in
            guard let newValue else {
                focusedCardID = nil
                return
            }

            DispatchQueue.main.async {
                focusedCardID = newValue
            }
        }
        .onTapGesture {
            focusBoardKeyboard()
            if interaction.editingCardID != nil {
                onCommitEditing()
            }
        }
        .onAppear {
            syncTransientGestureState()
            focusBoardKeyboardSoon()
        }
        .onChange(of: transientGestureStateValue) { _, newValue in
            transientGestureState = newValue
        }
        .onChange(of: visibleBounds) { _, _ in
            refreshCursorViewportBounds()
        }
        .onChange(of: gestureCancellationToken) { _, _ in
            cancelTransientGesture()
        }
    }

    private func scrollToCursor(_ slot: BoardSlot?, using proxy: ScrollViewProxy) {
        guard let slot else {
            return
        }

        DispatchQueue.main.async {
            withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.9)) {
                proxy.scrollTo(slot.id)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                refreshCursorViewportBounds()
            }
        }
    }

    private var boardWidth: CGFloat {
        let totalCardWidth = CGFloat(visibleBounds.columnCount) * slotSize.width
        let totalSpacing = CGFloat(max(visibleBounds.columnCount - 1, 0)) * BWRBoardLayoutMetrics.horizontalGridSpacing
        return totalCardWidth + totalSpacing + BWRBoardLayoutMetrics.outerPadding.leading + BWRBoardLayoutMetrics.outerPadding.trailing
    }

    private var boardHeight: CGFloat {
        let totalCardHeight = CGFloat(visibleBounds.rowCount) * slotSize.height
        let totalSpacing = CGFloat(max(visibleBounds.rowCount - 1, 0)) * BWRBoardLayoutMetrics.verticalGridSpacing
        return totalCardHeight + totalSpacing + BWRBoardLayoutMetrics.outerPadding.top + BWRBoardLayoutMetrics.outerPadding.bottom
    }

    @ViewBuilder
    private func slotCell(for slot: BoardSlot) -> some View {
        let card = project.card(at: slot)
        BWRSlotCellView(
            slot: slot,
            card: card,
            slotSize: slotSize,
            isSettlingDrop: isSettlingDrop,
            isSelected: isSelected(slot: slot, card: card),
            isKeyboardCursor: interaction.keyboardCursorSlot == slot,
            isHovered: interaction.hoverSlot == slot,
            isEditing: interaction.editingCardID == card?.id,
            isSearchMatch: card.map { searchMatches.contains($0.id) } ?? false,
            isDragSource: card.map { activeDragCardIDs.contains($0.id) } ?? false,
            isPreviewRelocated: card.map { overlayPreviewCardIDs.contains($0.id) } ?? false,
            usesNativePointerBridge: interaction.editingCardID == nil,
            showsSlotGuides: showsSlotGuides,
            noteBinding: { card in
                noteBinding(card.id)
            },
            asset: card.flatMap { assetForCard($0.id) },
            focusedCardID: $focusedCardID,
            onSelectCard: { card in
                handleCardTap(card)
            },
            onSelectEmpty: {
                handleEmptyTap(slot)
            },
            onHoverChange: { isHovering in
                updateHover(isHovering, for: slot)
            },
            onOpenForEditing: onOpenCardForEditing,
            onCreateCard: {
                onCreateCard(slot)
            },
            onCycleTint: onCycleTint,
            onCommitEditing: onCommitEditing,
            onCancelEditing: onCancelEditing,
            onAdvanceEditing: onAdvanceEditing
        )
    }

    private var editingCardID: UUID? {
        interaction.editingCardID
    }

    private func isSelected(slot: BoardSlot, card: BoardPresentedCard?) -> Bool {
        if let card {
            return interaction.isSelected(cardID: card.id)
        }

        return interaction.isSelected(emptySlot: slot)
    }

    private func updateHover(_ isHovering: Bool, for slot: BoardSlot) {
        guard interaction.editingCardID != nil else {
            return
        }

        guard !isHoverSuppressedByScroll, !isInteractionSuppressedByZoom else {
            if interaction.hoverSlot == slot {
                interaction.hoverSlot = nil
            }
            return
        }

        interaction.hoverSlot = isHovering ? slot : (interaction.hoverSlot == slot ? nil : interaction.hoverSlot)
    }

    private func handlePointerHoverChange(_ point: CGPoint?) {
        guard !isHoverSuppressedByScroll, !isInteractionSuppressedByZoom else {
            interaction.hoverSlot = nil
            return
        }

        guard let point, let slot = boardLayout.slot(at: point) else {
            interaction.hoverSlot = nil
            return
        }

        interaction.hoverSlot = slot
    }

    private func handlePointerPrimaryDown(_ point: CGPoint) {
        focusBoardKeyboard()
        interaction.hoverSlot = nil
        primePointerSelection(at: point)
    }

    private func handlePointerDragChanged(_ value: BWRBoardPointerDragValue) {
        handleBoardPointerChanged(
            startLocation: value.startLocation,
            location: value.location,
            translation: value.translation
        )
    }

    private func handlePointerPrimaryUp(_ value: BWRBoardPointerDragValue, clickCount: Int) {
        let moved = value.translation.magnitude >= pointerDragThreshold
        if dragSession != nil || marqueeStartSlot != nil || moved {
            handleBoardPointerEnded(
                startLocation: value.startLocation,
                location: value.location,
                translation: value.translation
            )
            return
        }

        handlePointerClick(at: value.location, clickCount: clickCount)
        resetTransientPointerState()
    }

    private func handlePointerClick(at point: CGPoint, clickCount: Int) {
        focusBoardKeyboard()

        guard let slot = boardLayout.slot(at: point) else {
            return
        }

        if let card = project.card(at: slot) {
            handleCardTap(card)
            if clickCount >= 2 {
                onOpenCardForEditing(card.id)
            }
            return
        }

        handleEmptyTap(slot)
        if clickCount >= 2 {
            onCreateCard(slot)
        }
    }

    private func suspendHoverForScroll() {
        hoverResumeToken += 1
        let token = hoverResumeToken
        let needsInitialSuppression = !isHoverSuppressedByScroll
        isHoverSuppressedByScroll = true
        if interaction.hoverSlot != nil {
            interaction.hoverSlot = nil
        }
        if needsInitialSuppression {
            focusBoardKeyboard()
            refreshCursorViewportBounds()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            guard hoverResumeToken == token else {
                return
            }

            isHoverSuppressedByScroll = false
        }
    }

    private func beginZoomInteraction() {
        zoomResumeToken += 1
        isInteractionSuppressedByZoom = true
        interaction.hoverSlot = nil
        focusBoardKeyboard()
    }

    private func endZoomInteractionSoon() {
        zoomResumeToken += 1
        let token = zoomResumeToken

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            guard zoomResumeToken == token else {
                return
            }

            isInteractionSuppressedByZoom = false
            refreshCursorViewportBounds()
        }
    }

    private func handleCommandZoomScroll(_ deltaY: CGFloat, anchorInViewport: CGPoint) -> Bool {
        beginZoomInteraction()
        let zoomMultiplier = exp(deltaY * 0.006)
        let nextScale = (cardScale * zoomMultiplier).clamped(to: cardScaleRange)
        if let scrollView = viewportHandle.scrollView {
            scrollView.setMagnification(nextScale, centeredAt: anchorInViewport)
        }
        cardScale = nextScale
        refreshCursorViewportBounds()
        endZoomInteractionSoon()
        return true
    }

    private func refreshCursorViewportBounds() {
        guard let scrollView = viewportHandle.scrollView else {
            return
        }

        let visibleRect = scrollView.contentView.bounds
        let insetPoint: CGFloat = 1
        let topLeading = CGPoint(
            x: visibleRect.minX + insetPoint,
            y: visibleRect.minY + insetPoint
        )
        let bottomTrailing = CGPoint(
            x: max(visibleRect.minX + insetPoint, visibleRect.maxX - insetPoint),
            y: max(visibleRect.minY + insetPoint, visibleRect.maxY - insetPoint)
        )

        guard
            let firstSlot = boardLayout.nearestSlot(to: topLeading),
            let lastSlot = boardLayout.nearestSlot(to: bottomTrailing)
        else {
            cursorViewportBounds = nil
            return
        }

        cursorViewportBounds = BoardVisibleBounds(
            slots: [firstSlot, lastSlot],
            topPadding: 0,
            bottomPadding: 0,
            leadingPadding: 0,
            trailingPadding: 0,
            minimumColumns: 1,
            minimumRows: 1,
            expansionBias: .preserveMinimumEdge
        )
    }

    private var activeDragCardIDs: Set<UUID> {
        guard let dragSession, isActivelyDragging else {
            return []
        }
        return dragSession.selectedCardIDs
    }

    private var overlayPreviewCardIDs: Set<UUID> {
        guard isActivelyDragging else {
            return []
        }
        return Set(project.liveCards.map(\.id)).subtracting(activeDragCardIDs)
    }

    private var dragDestinationOverlay: some View {
        ZStack {
            if let dragSession, !dragSession.previewOffset.isZero, !isSettlingDrop {
                ForEach(project.sortedCardIDs(dragSession.selectedCardIDs), id: \.self) { cardID in
                    if let previewSlot = dragSession.previewSlots[cardID] {
                        dragDestinationBlock(
                            at: previewSlot,
                            isHead: dragSession.pattern.headCardID == cardID,
                            isSingle: dragSession.pattern.orderedCardIDs.count == 1
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.88), value: dragSession?.previewOffset ?? .zero)
    }

    @ViewBuilder
    private func dragDestinationBlock(at slot: BoardSlot, isHead: Bool, isSingle: Bool) -> some View {
        let rect = boardLayout.rect(for: slot)
        let emphasisSize = BWRBoardLayoutMetrics.slotEmphasisSize(for: rect.size)
        RoundedRectangle(cornerRadius: BWRBoardLayoutMetrics.slotEmphasisCorner, style: .continuous)
            .fill(Color(hex: 0x655F56).opacity(isSingle ? 0.78 : 0.72))
            .overlay(
                RoundedRectangle(cornerRadius: BWRBoardLayoutMetrics.slotEmphasisCorner, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(isHead ? 0.24 : 0.14),
                        lineWidth: isHead
                            ? BWRBoardLayoutMetrics.dragDestinationHeadStrokeWidth
                            : BWRBoardLayoutMetrics.dragDestinationStrokeWidth
                    )
            )
            .frame(width: emphasisSize.width, height: emphasisSize.height)
            .position(x: rect.midX, y: rect.midY)
            .shadow(
                color: Color.black.opacity(isHead ? 0.18 : 0.12),
                radius: BWRBoardLayoutMetrics.dragDestinationShadowRadius,
                x: 0,
                y: BWRBoardLayoutMetrics.dragDestinationShadowYOffset
            )
    }

    private var dragPreviewOverlay: some View {
        ZStack {
            if let dragSession, isActivelyDragging {
                ForEach(project.sortedCardIDs(dragSession.selectedCardIDs), id: \.self) { cardID in
                    if let sourceSlot = dragSession.originSlots[cardID],
                       let card = project.presentedCard(id: cardID) {
                        let rect = boardLayout.rect(for: sourceSlot)
                        let liftShadow = dragPreviewLiftShadow(for: cardID, in: dragSession)
                        BWRCardSurfaceView(
                            card: card,
                            noteBinding: nil,
                            isEditing: false,
                            isSearchMatch: false,
                            asset: assetForCard(cardID),
                            focusedCardID: $dragPreviewFocusID,
                            onSelect: {},
                            onOpenForEditing: {},
                            onCycleTint: {},
                            onCommitEditing: {},
                            onCancelEditing: {},
                            onAdvanceEditing: { _ in }
                        )
                        .frame(width: slotSize.width, height: slotSize.height)
                        .position(
                            x: rect.midX + dragTranslation.width,
                            y: rect.midY + dragTranslation.height
                        )
                        .shadow(
                            color: liftShadow.color,
                            radius: liftShadow.radius,
                            x: 0,
                            y: liftShadow.y
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func dragPreviewLiftShadow(for cardID: UUID, in session: BoardDragSession) -> (color: Color, radius: CGFloat, y: CGFloat) {
        guard !isSettlingDrop else {
            return (.clear, 0, 0)
        }

        let isHead = cardID == session.pattern.headCardID
        return (
            Color.black.opacity(isHead ? 0.2 : 0.14),
            isHead
                ? BWRBoardLayoutMetrics.dragPreviewHeadShadowRadius
                : BWRBoardLayoutMetrics.dragPreviewShadowRadius,
            BWRBoardLayoutMetrics.dragPreviewShadowYOffset
        )
    }

    private var dragReflowOverlay: some View {
        ZStack {
            ForEach(project.sortedCardIDs(overlayPreviewCardIDs), id: \.self) { cardID in
                if let card = project.presentedCard(id: cardID) {
                    let sourceRect = boardLayout.rect(for: card.slot)
                    let previewSlot = dragReflowSlots[cardID] ?? card.slot
                    let previewRect = boardLayout.rect(for: previewSlot)
                    BWRCardSurfaceView(
                        card: card,
                        noteBinding: nil,
                        isEditing: false,
                        isSearchMatch: false,
                        asset: assetForCard(cardID),
                        focusedCardID: $dragPreviewFocusID,
                        onSelect: {},
                        onOpenForEditing: {},
                        onCycleTint: {},
                        onCommitEditing: {},
                        onCancelEditing: {},
                        onAdvanceEditing: { _ in }
                    )
                    .frame(width: slotSize.width, height: slotSize.height)
                    .position(x: sourceRect.midX, y: sourceRect.midY)
                    .offset(
                        x: previewRect.midX - sourceRect.midX,
                        y: previewRect.midY - sourceRect.midY
                    )
                    .transition(.identity)
                }
            }
        }
        .allowsHitTesting(false)
        .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.88), value: dragReflowSlots)
    }

    private var marqueeOverlay: some View {
        ZStack {
            if let marqueeRect {
                Rectangle()
                    .fill(Color(hex: 0x78A9F1).opacity(0.12))
                    .overlay(
                        Rectangle()
                            .strokeBorder(
                                Color(hex: 0x78A9F1).opacity(0.9),
                                style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])
                            )
                    )
                    .frame(width: marqueeRect.width, height: marqueeRect.height)
                    .position(x: marqueeRect.midX, y: marqueeRect.midY)
            }
        }
        .allowsHitTesting(false)
    }

    private func handleCardTap(_ card: BoardPresentedCard) {
        focusBoardKeyboard()
        interaction.editingCardID = nil
        let modifiers = currentModifiers

        if modifiers.contains(.command) {
            interaction.toggleCard(card.id, at: card.slot)
            return
        }

        if modifiers.contains(.shift) {
            let anchorSlot = interaction.selectionAnchorSlot.flatMap { anchor in
                project.card(at: anchor) != nil ? anchor : nil
            } ?? card.slot
            let ids = project.cardIDsBetween(anchorSlot, and: card.slot)
            interaction.selectCards(ids.isEmpty ? [card.id] : ids, anchorSlot: anchorSlot)
            return
        }

        interaction.keyboardCursorSlot = card.slot
        interaction.selectCard(card.id, at: card.slot)
    }

    private func handleEmptyTap(_ slot: BoardSlot) {
        focusBoardKeyboard()
        interaction.editingCardID = nil
        interaction.keyboardCursorSlot = slot
        interaction.selectEmptySlot(slot)
    }

    private func focusBoardKeyboard() {
        keyboardHandle.focus()
    }

    private func focusBoardKeyboardSoon() {
        focusBoardKeyboard()

        DispatchQueue.main.async {
            focusBoardKeyboard()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            focusBoardKeyboard()
        }
    }

    private func primePointerSelection(at point: CGPoint) {
        guard interaction.editingCardID == nil else {
            return
        }

        guard currentModifiers.isEmpty else {
            return
        }

        guard
            let slot = boardLayout.slot(at: point),
            let card = project.card(at: slot),
            !interaction.selectedCardIDs.contains(card.id)
        else {
            return
        }

        interaction.keyboardCursorSlot = slot
        interaction.selectCard(card.id, at: slot)
    }

    private func handleBoardPointerChanged(
        startLocation: CGPoint,
        location: CGPoint,
        translation: CGSize
    ) {
        guard interaction.editingCardID == nil, !isInteractionSuppressedByZoom else {
            return
        }

        guard dragSession != nil || marqueeStartSlot != nil || translation.magnitude >= pointerDragThreshold else {
            return
        }

        if dragSession == nil, marqueeStartSlot == nil {
            beginPointerGesture(at: startLocation)
        }

        if let currentSession = dragSession {
            var updated = currentSession
            dragTranslation = translation
            let proposedOffset = BoardDragController.slotDelta(
                translation: translation,
                slotStep: slotStep
            )
            updated.previewOffset = BoardDragController.clampedPreviewOffset(
                proposedOffset,
                originSlots: currentSession.originSlots
            )
            dragSession = updated
            return
        }

        guard let marqueeStartSlot else {
            return
        }

        let rect = CGRect(
            x: min(startLocation.x, location.x),
            y: min(startLocation.y, location.y),
            width: abs(location.x - startLocation.x),
            height: abs(location.y - startLocation.y)
        ).standardized
        marqueeRect = rect

        let selection = BoardMarqueeController.selection(
            project: project,
            layout: boardLayout,
            rect: rect
        )
        applyMarqueeSelection(selection, marqueeStartSlot: marqueeStartSlot)
    }

    private func handleBoardPointerEnded(
        startLocation: CGPoint,
        location: CGPoint,
        translation: CGSize
    ) {
        guard interaction.editingCardID == nil, !isInteractionSuppressedByZoom else {
            resetTransientPointerState()
            return
        }

        if let dragSession, !dragSession.previewOffset.isZero {
            beginDropSettling(for: dragSession)
            return
        }

        guard dragSession != nil || marqueeStartSlot != nil || translation.magnitude >= pointerDragThreshold else {
            resetTransientPointerState()
            return
        }

        guard let marqueeStartSlot else {
            resetTransientPointerState()
            return
        }

        let rect = CGRect(
            x: min(startLocation.x, location.x),
            y: min(startLocation.y, location.y),
            width: abs(location.x - startLocation.x),
            height: abs(location.y - startLocation.y)
        ).standardized
        let selection = BoardMarqueeController.selection(
            project: project,
            layout: boardLayout,
            rect: rect
        )
        applyMarqueeSelection(selection, marqueeStartSlot: marqueeStartSlot)
        resetTransientPointerState()
    }

    private func beginPointerGesture(at point: CGPoint) {
        clearDropSettling()
        guard let slot = boardLayout.slot(at: point) else {
            marqueeStartSlot = boardLayout.nearestSlot(to: point)
            marqueeRect = CGRect(origin: point, size: .zero)
            return
        }

        interaction.hoverSlot = nil
        if let card = project.card(at: slot) {
            if !interaction.selectedCardIDs.contains(card.id) {
                interaction.selectCard(card.id, at: slot)
            }
            dragSession = BoardDragController.makeSession(
                project: project,
                interaction: interaction,
                startingFrom: card.id
            )
            dragTranslation = .zero
            return
        }

        marqueeStartSlot = slot
        marqueeRect = CGRect(origin: point, size: .zero)
    }

    private func applyMarqueeSelection(_ selection: BoardSelection, marqueeStartSlot: BoardSlot) {
        switch selection {
        case .none:
            interaction.clearSelection()
        case .cards(let ids):
            let anchorSlot = project.sortedCardIDs(ids).first.flatMap { id in
                project.presentedCard(id: id)?.slot
            } ?? marqueeStartSlot
            interaction.selectCards(ids, anchorSlot: anchorSlot)
        case .slots(let slots):
            let anchorSlot = slots.contains(marqueeStartSlot) ? marqueeStartSlot : slots.sorted().first
            interaction.selectEmptySlots(slots, anchorSlot: anchorSlot)
        }
    }

    private var currentModifiers: NSEvent.ModifierFlags {
        NSEvent.modifierFlags.bwrCommandModifiers
    }

    private func syncTransientGestureState() {
        transientGestureState = transientGestureStateValue
    }

    private func cancelTransientGesture() {
        clearDropSettling()
        resetTransientPointerState()
    }

    private func beginDropSettling(for session: BoardDragSession) {
        let snappedTranslation = CGSize(
            width: CGFloat(session.previewOffset.columns) * slotStep.width,
            height: CGFloat(session.previewOffset.rows) * slotStep.height
        )
        frozenDragReflowSlots = computedDragReflowSlots
        isSettlingDrop = true
        dropSettleToken += 1
        let currentToken = dropSettleToken

        withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.9)) {
            dragTranslation = snappedTranslation
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard currentToken == dropSettleToken else {
                return
            }
            withAnimation(nil) {
                onApplyDrag(session)
                clearDropSettling()
                resetTransientPointerState()
            }
        }
    }

    private func clearDropSettling() {
        dropSettleToken += 1
        isSettlingDrop = false
        frozenDragReflowSlots = [:]
    }

    private func resetTransientPointerState() {
        dragSession = nil
        dragTranslation = .zero
        marqueeRect = nil
        marqueeStartSlot = nil
        syncTransientGestureState()
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension CGSize {
    var magnitude: CGFloat {
        sqrt((width * width) + (height * height))
    }
}

private struct BWRSlotCellView: View {
    let slot: BoardSlot
    let card: BoardPresentedCard?
    let slotSize: CGSize
    let isSettlingDrop: Bool
    let isSelected: Bool
    let isKeyboardCursor: Bool
    let isHovered: Bool
    let isEditing: Bool
    let isSearchMatch: Bool
    let isDragSource: Bool
    let isPreviewRelocated: Bool
    let usesNativePointerBridge: Bool
    let showsSlotGuides: Bool
    let noteBinding: (BoardPresentedCard) -> Binding<String>?
    let asset: BoardAsset?
    @FocusState.Binding var focusedCardID: UUID?
    let onSelectCard: (BoardPresentedCard) -> Void
    let onSelectEmpty: () -> Void
    let onHoverChange: (Bool) -> Void
    let onOpenForEditing: (UUID) -> Void
    let onCreateCard: () -> Void
    let onCycleTint: (UUID) -> Void
    let onCommitEditing: () -> Void
    let onCancelEditing: () -> Void
    let onAdvanceEditing: (Bool) -> Void

    private var showsFocusedSlot: Bool {
        isKeyboardCursor || isSelected
    }

    private var showsCardFocus: Bool {
        card != nil && showsFocusedSlot
    }

    private var slotEmphasisSize: CGSize {
        BWRBoardLayoutMetrics.slotEmphasisSize(for: slotSize)
    }

    private var hidesCardSurfaceForDragOverlay: Bool {
        isDragSource || isPreviewRelocated
    }

    var body: some View {
        ZStack {
            slotEmphasisBackdrop

            if let card {
                BWRCardSurfaceView(
                    card: card,
                    noteBinding: noteBinding(card),
                    isEditing: isEditing,
                    isSearchMatch: isSearchMatch,
                    asset: asset,
                    focusedCardID: $focusedCardID,
                    onSelect: {
                        onSelectCard(card)
                    },
                    onOpenForEditing: {
                        onOpenForEditing(card.id)
                    },
                    onCycleTint: {
                        onCycleTint(card.id)
                    },
                    onCommitEditing: onCommitEditing,
                    onCancelEditing: onCancelEditing,
                    onAdvanceEditing: onAdvanceEditing
                )
                .frame(width: slotSize.width, height: slotSize.height)
                .opacity(hidesCardSurfaceForDragOverlay ? 0 : 1)
                .allowsHitTesting(!hidesCardSurfaceForDragOverlay)
            } else {
                emptySlotSurface
            }
        }
        .overlay {
            slotOutline
        }
        .frame(width: slotSize.width, height: slotSize.height)
        .contentShape(
            RoundedRectangle(
                cornerRadius: BWRBoardLayoutMetrics.cardCorner + BWRBoardLayoutMetrics.slotContentShapeCornerBoost,
                style: .continuous
            )
        )
        .onHover { isHovering in
            guard !usesNativePointerBridge else {
                return
            }
            onHoverChange(isHovering)
        }
    }

    @ViewBuilder
    private var slotEmphasisBackdrop: some View {
        let shouldShow = showsFocusedSlot
        let showsEmptyFocus = card == nil && showsFocusedSlot
        let fillColor = showsCardFocus
            ? Color(hex: 0x4C8DE7).opacity(isDragSource ? 0.9 : 0.82)
            : Color(hex: 0x655F56).opacity(0.78)
        let shadowColor = showsCardFocus
            ? Color(hex: 0x4C8DE7).opacity(isDragSource ? 0.28 : 0.18)
            : Color.black.opacity(0.16)
        let shadowRadius = showsCardFocus
            ? BWRBoardLayoutMetrics.slotFocusShadowRadius
            : BWRBoardLayoutMetrics.slotEmptyShadowRadius
        let shadowYOffset = isDragSource
            ? BWRBoardLayoutMetrics.slotDragSourceShadowYOffset
            : BWRBoardLayoutMetrics.slotFocusShadowYOffset
        RoundedRectangle(cornerRadius: BWRBoardLayoutMetrics.slotEmphasisCorner, style: .continuous)
            .fill(shouldShow ? fillColor : .clear)
            .frame(width: slotEmphasisSize.width, height: slotEmphasisSize.height)
            .shadow(
                color: shouldShow ? shadowColor : .clear,
                radius: shouldShow ? shadowRadius : 0,
                x: 0,
                y: showsEmptyFocus ? BWRBoardLayoutMetrics.slotFocusShadowYOffset : shadowYOffset
            )
    }

    @ViewBuilder
    private var slotOutline: some View {
        let shouldShowGuides = (showsSlotGuides && card == nil) || isHovered
        RoundedRectangle(cornerRadius: BWRBoardLayoutMetrics.cardCorner, style: .continuous)
            .strokeBorder(
                shouldShowGuides
                    ? Color.white.opacity(isHovered ? 0.92 : (isSelected ? 0.48 : 0.18))
                    : .clear,
                style: StrokeStyle(
                    lineWidth: isHovered
                        ? BWRBoardLayoutMetrics.slotGuideHoverLineWidth
                        : BWRBoardLayoutMetrics.slotGuideLineWidth,
                    dash: BWRBoardLayoutMetrics.slotGuideDash
                )
            )
    }

    @ViewBuilder
    private var emptySlotSurface: some View {
        RoundedRectangle(cornerRadius: BWRBoardLayoutMetrics.cardCorner, style: .continuous)
            .fill(Color.white.opacity((isSelected || isKeyboardCursor) ? 0.18 : 0.001))
            .overlay {
                if isSelected {
                    VStack(spacing: BWRBoardLayoutMetrics.emptySlotPromptSpacing) {
                        Image(systemName: "plus")
                            .font(.system(size: BWRBoardLayoutMetrics.emptySlotPromptIconSize, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                        Text("New card")
                            .font(.custom("Avenir Next", size: BWRBoardLayoutMetrics.emptySlotPromptTitleSize))
                            .foregroundStyle(.white.opacity(0.88))
                    }
                }
            }
            .onTapGesture {
                onSelectEmpty()
            }
            .onTapGesture(count: 2) {
                onCreateCard()
            }
    }
}

private struct BWRCardSurfaceView: View {
    let card: BoardPresentedCard
    let noteBinding: Binding<String>?
    let isEditing: Bool
    let isSearchMatch: Bool
    let asset: BoardAsset?
    @FocusState.Binding var focusedCardID: UUID?
    let onSelect: () -> Void
    let onOpenForEditing: () -> Void
    let onCycleTint: () -> Void
    let onCommitEditing: () -> Void
    let onCancelEditing: () -> Void
    let onAdvanceEditing: (Bool) -> Void

    private var assetImage: NSImage? {
        asset.flatMap { NSImage(data: $0.data) }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: BWRBoardLayoutMetrics.cardSurfaceCorner, style: .continuous)
            .fill(card.palette.fill)
            .shadow(
                color: .black.opacity(0.08),
                radius: BWRBoardLayoutMetrics.cardSurfaceShadowRadius,
                x: 0,
                y: BWRBoardLayoutMetrics.cardSurfaceShadowYOffset
            )
            .overlay(alignment: .topLeading) {
                if isEditing, let noteBinding {
                    BWRInlineMarkdownEditor(
                        text: noteBinding,
                        isFocused: focusedCardID == card.id,
                        onCommit: onCommitEditing,
                        onAdvance: onAdvanceEditing,
                        onCancel: onCancelEditing
                    )
                        .padding(BWRBoardLayoutMetrics.cardEditorPadding)
                } else {
                    cardReadSurface
                }
            }
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(card.palette.chip)
                    .frame(
                        width: BWRBoardLayoutMetrics.cardChipSize,
                        height: BWRBoardLayoutMetrics.cardChipSize
                    )
                    .padding(BWRBoardLayoutMetrics.cardChipPadding)
            }
            .overlay {
                RoundedRectangle(cornerRadius: BWRBoardLayoutMetrics.cardSurfaceCorner, style: .continuous)
                    .strokeBorder(
                        isSearchMatch ? Color(hex: 0xF0D76E).opacity(0.96) : .clear,
                        lineWidth: isSearchMatch ? BWRBoardLayoutMetrics.cardSearchStrokeWidth : 0
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: BWRBoardLayoutMetrics.cardSurfaceCorner, style: .continuous))
            .onTapGesture {
                onSelect()
            }
            .onTapGesture(count: 2) {
                onOpenForEditing()
            }
    }

    private var cardReadSurface: some View {
        VStack(alignment: .leading, spacing: BWRBoardLayoutMetrics.cardReadSpacing) {
            if let assetImage {
                Image(nsImage: assetImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: BWRBoardLayoutMetrics.cardAssetHeight)
                    .clipShape(
                        RoundedRectangle(cornerRadius: BWRBoardLayoutMetrics.cardAssetCornerRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: BWRBoardLayoutMetrics.cardAssetCornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.28), lineWidth: BWRBoardLayoutMetrics.cardAssetStrokeWidth)
                    )
            }

            VStack(alignment: .leading, spacing: BWRBoardLayoutMetrics.cardReadTextSpacing) {
                Text(card.digest.title)
                    .font(.custom("Avenir Next Demi Bold", size: BWRBoardLayoutMetrics.cardTitleFontSize))
                    .foregroundStyle(Color(hex: 0x121212))
                    .lineLimit(2)

                if !card.digest.excerpt.isEmpty {
                    Text(card.digest.excerpt)
                        .font(.custom("Avenir Next", size: BWRBoardLayoutMetrics.cardBodyFontSize))
                        .foregroundStyle(Color(hex: 0x373737))
                        .lineLimit(assetImage == nil ? 5 : 3)
                }

                if let asset, assetImage == nil {
                    Label(asset.originalFilename ?? asset.storedFilename, systemImage: "paperclip")
                        .font(.custom("Avenir Next Demi Bold", size: BWRBoardLayoutMetrics.cardAttachmentFontSize))
                        .foregroundStyle(Color(hex: 0x5B534A))
                        .lineLimit(1)
                }
            }
        }
        .padding(BWRBoardLayoutMetrics.cardContentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct BWRToolbarSearchField: View {
    @Binding var text: String
    let resultCount: Int
    let activeResultIndex: Int?
    let onSubmit: () -> Void
    let onPreviousResult: () -> Void
    let onNextResult: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: 0x9A968F))

            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.custom("Avenir Next", size: 14))
                .frame(width: 290)
                .onSubmit(onSubmit)

            if !text.isEmpty {
                Text(resultBadgeText)
                    .font(.custom("Avenir Next Demi Bold", size: 11))
                    .foregroundStyle(Color(hex: 0x8B857A))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(hex: 0xECE6DD))
                    )
            }

            if resultCount > 1 {
                Button(action: onPreviousResult) {
                    Image(systemName: "chevron.up")
                        .foregroundStyle(Color(hex: 0x8B857A))
                }
                .buttonStyle(.plain)

                Button(action: onNextResult) {
                    Image(systemName: "chevron.down")
                        .foregroundStyle(Color(hex: 0x8B857A))
                }
                .buttonStyle(.plain)
            }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(hex: 0xB7B1A8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.92))
                .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
        )
    }

    private var resultBadgeText: String {
        guard let activeResultIndex else {
            return "\(resultCount)"
        }

        return "\(activeResultIndex + 1)/\(resultCount)"
    }
}

struct BWRCircleToolbarButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0x59544B))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.95))
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                )
        }
        .buttonStyle(.plain)
    }
}

struct BWRCircleToolbarMenu<Content: View>: View {
    let systemName: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0x59544B))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.95))
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                )
        }
        .menuStyle(.borderlessButton)
    }
}

struct BWRFloatingHelpButton: View {
    @Binding var showsHelp: Bool

    var body: some View {
        Button {
            showsHelp.toggle()
        } label: {
            Image(systemName: "ellipsis.message.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: 0x625D54))
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.94))
                        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
                )
        }
        .buttonStyle(.plain)
    }
}

struct BWRHelpPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Board shortcuts")
                .font(.custom("Avenir Next Demi Bold", size: 16))

            Text("Single click selects a card or slot.")
                .font(.custom("Avenir Next", size: 13))
            Text("The dark slot is the keyboard cursor anchor.")
                .font(.custom("Avenir Next", size: 13))
            Text("The dotted slot follows hover and stays separate from selection.")
                .font(.custom("Avenir Next", size: 13))
            Text("Command-click adds or removes cards from the current selection.")
                .font(.custom("Avenir Next", size: 13))
            Text("Shift-click grows a sequence selection from the anchored card.")
                .font(.custom("Avenir Next", size: 13))
            Text("Drag on empty space to marquee-select cards or slots.")
                .font(.custom("Avenir Next", size: 13))
            Text("Press Return on the cursor slot to edit a card or create one.")
                .font(.custom("Avenir Next", size: 13))
            Text("Press Tab or Shift-Tab to save and continue editing next or previous slots.")
                .font(.custom("Avenir Next", size: 13))
            Text("Use Arrow keys to move the cursor, and Option-Arrow to move the selected card.")
                .font(.custom("Avenir Next", size: 13))
            Text("Press Escape to cancel inline editing, then transient gestures, then selection.")
                .font(.custom("Avenir Next", size: 13))
            Text("Restore brings back the latest soft-deleted card near its original slot.")
                .font(.custom("Avenir Next", size: 13))
            Text("Search Enter or the location button jumps to the current logical match, and the chevrons move through results.")
                .font(.custom("Avenir Next", size: 13))
            Text("Structure menu inserts or deletes rows and columns around the current slot.")
                .font(.custom("Avenir Next", size: 13))
            Text("Attach Image links an image asset to the presented layer and saves it into the package.")
                .font(.custom("Avenir Next", size: 13))
            Text("Double-click a card to edit markdown inline.")
                .font(.custom("Avenir Next", size: 13))
            Text("Double-click an empty slot to create a new card there.")
                .font(.custom("Avenir Next", size: 13))
            Text("Single-card drags swap, sequence drags insert, and cluster drags stay rigid.")
                .font(.custom("Avenir Next", size: 13))
            Text("Long-press a card to cycle its paper color.")
                .font(.custom("Avenir Next", size: 13))
        }
        .padding(18)
        .frame(width: 320, alignment: .leading)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
