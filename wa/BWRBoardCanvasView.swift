import SwiftUI
import AppKit

@MainActor
struct BWRBoardCanvasView: View {
    @ObservedObject var document: BWRReferenceDocument
    @Binding var selectedCardIDs: Set<UUID>
    @Binding var selectedGroupID: UUID?
    @Binding var viewportState: BWRViewportState
    @Binding var inlineEditor: BWRInlineEditorState?
    @Binding var boardChromeState: BWRBoardChromeState

    let boardTheme: BWRBoardThemeState

    let beginInlineEdit: (UUID) -> Void
    let finishInlineEdit: (_ save: Bool) -> Void
    let splitInlineEdit: () -> Void
    let cycleInlineLayer: (_ cardID: UUID, _ direction: Int) -> Void
    let openLargeEditor: (UUID) -> Void
    let requestLayerRename: (UUID, UUID, String) -> Void
    let requestGroupRename: (UUID, String) -> Void

    @State private var zoomBaseline: CGFloat = 1.0
    @State private var cardDragSession: BWRBoardCardDragSession?
    @State private var groupDragSession: BWRBoardGroupDragSession?

    var body: some View {
        GeometryReader { geometry in
            scrollContainer(for: geometry)
            .coordinateSpace(name: "bwrBoardScroll")
            .background(Color(nsColor: .underPageBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        viewportState.zoomScale = Double(min(max(zoomBaseline * value, 0.3), 1.6))
                    }
                    .onEnded { value in
                        viewportState.zoomScale = Double(min(max(zoomBaseline * value, 0.3), 1.6))
                        zoomBaseline = CGFloat(viewportState.zoomScale)
                    }
            )
            .contentShape(Rectangle())
            .onTapGesture {
                finishInlineEdit(true)
                selectedCardIDs.removeAll()
                selectedGroupID = nil
                boardChromeState.hoverPlaceholder = nil
            }
            .onPreferenceChange(BWRBoardScrollOriginPreferenceKey.self) { origin in
                viewportState.scrollOrigin = BWRPoint(
                    x: max(0, Double(-origin.x) / max(viewportState.zoomScale, 0.001)),
                    y: max(0, Double(-origin.y) / max(viewportState.zoomScale, 0.001))
                )
            }
            .onChange(of: viewportState.zoomScale) { _, newValue in
                zoomBaseline = CGFloat(newValue)
            }
        }
    }

    private func scrollContainer(for geometry: GeometryProxy) -> some View {
        ScrollView([.horizontal, .vertical]) {
            boardContent(for: geometry)
        }
    }

    private func boardContent(for geometry: GeometryProxy) -> some View {
        ZStack(alignment: .topLeading) {
            BWRBoardScrollOriginTracker()
            BWRBoardGridBackground(
                boardSize: boardSize,
                customBackgroundColor: resolvedBoardBackgroundColor
            )
            stripLayer
            groupLayer
            prioritizedCursorAndHoverLayers
            sourceOverlayLayer
            dragDestinationLayer
            groupPlaceholderLayer
            cardLayer
        }
        .frame(width: boardSize.width, height: boardSize.height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(resolvedBoardBackgroundColor ?? Color(nsColor: .textBackgroundColor))
        )
        .scaleEffect(CGFloat(viewportState.zoomScale), anchor: .topLeading)
        .onContinuousHover(coordinateSpace: .local) { phase in
            handleContinuousHover(phase)
        }
        .background(scrollTrackingBackground(for: geometry))
    }

    @ViewBuilder
    private var stripLayer: some View {
        ForEach(stripFrames) { frame in
            BWRParkingStripFrameView(frame: frame)
                .frame(width: frame.rect.width, height: frame.rect.height)
                .position(x: frame.rect.midX, y: frame.rect.midY)
        }
    }

    @ViewBuilder
    private var groupLayer: some View {
        ForEach(groupFrames) { frame in
            groupFrameTile(for: frame)
        }
    }

    @ViewBuilder
    private var groupPlaceholderLayer: some View {
        if let placeholder = groupDragSession?.target?.placeholder {
            BWRBoardPlaceholderView(placeholder: placeholder)
                .frame(width: placeholder.rect.width, height: placeholder.rect.height)
                .position(x: placeholder.rect.midX, y: placeholder.rect.midY)
        }
    }

    @ViewBuilder
    private var prioritizedCursorAndHoverLayers: some View {
        switch boardChromeState.slotCursor.lastInputModality {
        case .keyboard:
            hoverOverlayLayer(isEmphasized: false)
            slotCursorLayer(isEmphasized: true)
        case .pointer:
            slotCursorLayer(isEmphasized: false)
            hoverOverlayLayer(isEmphasized: true)
        case .drag:
            slotCursorLayer(isEmphasized: false)
            hoverOverlayLayer(isEmphasized: false)
        }
    }

    @ViewBuilder
    private var dragDestinationLayer: some View {
        let style = BWRCardBuddyStateGrammar.dragDestinationStyle(host: dragDestinationHost)
        ForEach(Array(dragDestinationOverlayRects.enumerated()), id: \.offset) { _, rect in
            BWRBoardOverlayFrameView(style: style)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    @ViewBuilder
    private func hoverOverlayLayer(isEmphasized: Bool) -> some View {
        if let placeholder = hoverPlaceholder {
            BWRBoardPlaceholderView(placeholder: placeholder, isEmphasized: isEmphasized)
                .frame(width: placeholder.rect.width, height: placeholder.rect.height)
                .position(x: placeholder.rect.midX, y: placeholder.rect.midY)
        }
    }

    @ViewBuilder
    private func slotCursorLayer(isEmphasized: Bool) -> some View {
        if let rect = slotCursorRect {
            BWRBoardSlotCursorView(isEmphasized: isEmphasized)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    @ViewBuilder
    private var sourceOverlayLayer: some View {
        ForEach(Array(dragSourceOverlayRects.enumerated()), id: \.offset) { _, rect in
            BWRBoardDragSourceView(isLifted: boardChromeState.dragOverlay.dragLiftStyle == .lifted)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    @ViewBuilder
    private var cardLayer: some View {
        ForEach(document.liveCards) { card in
            cardView(for: card)
        }
    }

    private func scrollTrackingBackground(for geometry: GeometryProxy) -> some View {
        GeometryReader { contentGeometry in
            Color.clear
                .onAppear {
                    updateViewportSize(from: geometry.size)
                }
                .onChange(of: geometry.size) { _, newSize in
                    updateViewportSize(from: newSize)
                }
                .preference(
                    key: BWRBoardScrollOriginPreferenceKey.self,
                    value: contentGeometry.frame(in: .named("bwrBoardScroll")).origin
                )
        }
    }

    private func cardTile(for card: BWRCard) -> some View {
        let isSelected = selectedCardIDs.contains(card.id)
        let effectiveSelection = selectionTarget(containing: card.id)
        let currentLayer = card.currentLayer ?? card.layers.first
        let surface = BWRCardBuddyCardShell.surface
        let isInlineEditing = inlineEditor?.cardID == card.id
        let preview = BWRCardBuddyCardShell.preview(for: currentLayer?.markdown ?? "")

        return ZStack {
            if isSelected {
                BWRBoardCardSelectionHalo(surface: surface)
            }

            Group {
                if isInlineEditing {
                    GeometryReader { geometry in
                        let cardBounds = CGRect(origin: .zero, size: geometry.size)
                        let editorRect = BWRSlotBoardGeometry.inlineEditorRect(
                            in: cardBounds,
                            footerHeight: BWRCardBuddyEditingChrome.footerHeight,
                            horizontalInset: max(6, surface.cardTextInset - 4),
                            topInset: max(8, surface.cardInnerPadding - 2),
                            bottomInset: surface.cardInnerPadding,
                            footerGap: BWRCardBuddyEditingChrome.footerGap
                        )
                        let footerRect = BWRSlotBoardGeometry.inlineEditorFooterRect(
                            in: cardBounds,
                            footerHeight: BWRCardBuddyEditingChrome.footerHeight,
                            horizontalInset: surface.cardTextInset,
                            bottomInset: surface.cardInnerPadding
                        )

                        ZStack(alignment: .topLeading) {
                            BWRCardMarkdownEditor(
                                text: inlineEditorTextBinding,
                                selectedRange: inlineEditorSelectionBinding,
                                fontSize: 14,
                                textContainerInset: NSSize(
                                    width: BWRCardBuddyEditingChrome.inlineTextInset.width,
                                    height: BWRCardBuddyEditingChrome.inlineTextInset.height
                                ),
                                autoFocus: true,
                                onSplit: { _, _ in
                                    splitInlineEdit()
                                },
                                onEscape: {
                                    finishInlineEdit(false)
                                }
                            )
                            .frame(width: editorRect.width, height: editorRect.height)
                            .position(x: editorRect.midX, y: editorRect.midY)

                            BWRBoardInlineEditorFooter(
                                layerName: currentLayer?.name ?? "Layer",
                                showsLayerCycle: card.layers.count > 1,
                                onPreviousLayer: {
                                    cycleInlineLayer(card.id, -1)
                                },
                                onNextLayer: {
                                    cycleInlineLayer(card.id, 1)
                                },
                                onExpand: {
                                    finishInlineEdit(true)
                                    openLargeEditor(card.id)
                                }
                            )
                            .frame(width: footerRect.width, height: footerRect.height)
                            .position(x: footerRect.midX, y: footerRect.midY)
                        }
                    }
                } else {
                    BWRBoardCardMarkdownPreviewBlock(
                        preview: preview,
                        surface: surface
                    )
                    .padding(.horizontal, surface.cardTextInset)
                    .padding(.top, surface.cardInnerPadding)
                    .padding(.bottom, surface.cardInnerPadding)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(cardBackgroundColor(for: card))
            .overlay(
                RoundedRectangle(cornerRadius: surface.cardCornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: surface.cardCornerRadius, style: .continuous))
            .shadow(
                color: .black.opacity(surface.cardShadowOpacity),
                radius: surface.cardShadowBlur,
                x: 0,
                y: surface.cardShadowYOffset
            )
        }
        .opacity(draggingCardIDs.contains(card.id) ? 0.84 : 1)
        .contentShape(RoundedRectangle(cornerRadius: surface.cardCornerRadius, style: .continuous))
        .onTapGesture {
            finishInlineEdit(true)
            selectCard(card.id, additive: additiveSelectionEnabled)
        }
        .onTapGesture(count: 2) {
            selectCard(card.id, additive: false)
            guard BWRCardBuddyEditingActivation.doubleClickPreview() == .openLargeEditor else { return }
            finishInlineEdit(true)
            openLargeEditor(card.id)
        }
        .contextMenu {
            Menu("Current Layer") {
                ForEach(card.layers) { layer in
                    Button(layer.name) {
                        finishInlineEdit(true)
                        document.setCurrentLayerMatchingSelection(
                            cardIDs: effectiveSelection,
                            sourceCardID: card.id,
                            sourceLayerID: layer.id
                        )
                    }
                }
            }

            Button("Add Body Layer") {
                finishInlineEdit(true)
                document.appendBodyLayer(cardID: card.id)
            }

            Button("Delete Current Body Layer") {
                guard let currentLayer else { return }
                finishInlineEdit(true)
                document.deleteBodyLayer(cardID: card.id, layerID: currentLayer.id)
            }
            .disabled(!(currentLayer?.kind == .body && card.layers.filter { $0.kind == .body }.count > 1))

            Button("Rename Current Body Layer…") {
                guard let currentLayer else { return }
                finishInlineEdit(true)
                requestLayerRename(card.id, currentLayer.id, currentLayer.name)
            }
            .disabled(currentLayer?.kind != .body)

            Divider()

            Menu("Color") {
                ForEach(BWRCardBuddyBoardThemeGuardrail.cardSwatches) { swatch in
                    Button(swatch.name) {
                        finishInlineEdit(true)
                        document.applyCardColor(cardIDs: effectiveSelection, colorHex: swatch.hex)
                    }
                }
                Button("Clear Color") {
                    finishInlineEdit(true)
                    document.applyCardColor(cardIDs: effectiveSelection, colorHex: nil)
                }
            }

            Divider()

            Button("Inline Edit") {
                selectCard(card.id, additive: false)
                beginInlineEdit(card.id)
            }
            Button("Open Large Editor") {
                selectCard(card.id, additive: false)
                finishInlineEdit(true)
                openLargeEditor(card.id)
            }

            Divider()

            Button("Delete", role: .destructive) {
                finishInlineEdit(true)
                document.deleteCards(cardIDs: effectiveSelection)
                selectedCardIDs.subtract(effectiveSelection)
            }
        }
    }

    private func groupFrameTile(for frame: BWRProjectedGroupFrame) -> some View {
        let style = BWRCardBuddyBoardThemeGuardrail.groupPanelStyle(isSelected: selectedGroupID == frame.group.id)
        return BWRGroupFrameView(
            frame: frame,
            isSelected: selectedGroupID == frame.group.id
        )
        .frame(width: frame.rect.width, height: frame.rect.height)
        .position(x: frame.rect.midX, y: frame.rect.midY)
        .contentShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        .onTapGesture {
            finishInlineEdit(true)
            selectedGroupID = frame.group.id
            selectedCardIDs.removeAll()
        }
        .contextMenu {
            Button("Rename Group…") {
                finishInlineEdit(true)
                requestGroupRename(frame.group.id, frame.group.name)
            }
            Button("Add Selection To Group") {
                finishInlineEdit(true)
                document.addCards(toGroup: frame.group.id, cardIDs: Array(selectedCardIDs))
            }
            .disabled(selectedCardIDs.isEmpty)
            Button("Remove Selection From Group") {
                finishInlineEdit(true)
                document.removeCards(fromGroup: frame.group.id, cardIDs: Array(selectedCardIDs))
            }
            .disabled(selectedCardIDs.isEmpty)
            Divider()
            Button("Archive Group", role: .destructive) {
                finishInlineEdit(true)
                document.archiveGroup(groupID: frame.group.id)
            }
        }
        .gesture(groupDragGesture(for: frame))
    }

    private func cardView(for card: BWRCard) -> some View {
        cardTile(for: card)
            .frame(
                width: BWRBoardMetrics.cardWidth,
                height: BWRBoardMetrics.cardHeight
            )
            .position(
                x: displayedLayout(for: card).x + (BWRBoardMetrics.cardWidth / 2),
                y: displayedLayout(for: card).y + (BWRBoardMetrics.cardHeight / 2)
            )
            .gesture(cardDragGesture(for: card))
    }

    private var inlineEditorTextBinding: Binding<String> {
        Binding(
            get: { inlineEditor?.text ?? "" },
            set: { newValue in
                guard inlineEditor != nil else { return }
                inlineEditor?.text = newValue
            }
        )
    }

    private var inlineEditorSelectionBinding: Binding<NSRange> {
        Binding(
            get: { inlineEditor?.selectedRange ?? NSRange(location: 0, length: 0) },
            set: { newValue in
                guard inlineEditor != nil else { return }
                inlineEditor?.selectedRange = newValue
            }
        )
    }

    private var boardSize: CGSize {
        var width = boardProjection.contentSize.width
        var height = boardProjection.contentSize.height
        let selectionSpread = BWRCardBuddyCardShell.surface.selectionOuterSpread
        for placeholder in dragDestinationPlaceholders + [hoverPlaceholder, groupDragSession?.target?.placeholder].compactMap({ $0 }) {
            width = max(width, placeholder.rect.maxX + BWRSlotBoardGeometry.default.boardPadding.width)
            height = max(height, placeholder.rect.maxY + BWRSlotBoardGeometry.default.boardPadding.height)
        }
        for rect in dragSourceRects {
            width = max(width, rect.maxX + BWRSlotBoardGeometry.default.boardPadding.width)
            height = max(height, rect.maxY + BWRSlotBoardGeometry.default.boardPadding.height)
        }
        if selectionSpread > 0 {
            for card in document.liveCards where selectedCardIDs.contains(card.id) {
                let layout = displayedLayout(for: card)
                width = max(width, layout.x + BWRBoardMetrics.cardWidth + selectionSpread + BWRSlotBoardGeometry.default.boardPadding.width)
                height = max(height, layout.y + BWRBoardMetrics.cardHeight + selectionSpread + BWRSlotBoardGeometry.default.boardPadding.height)
            }
        }
        return CGSize(width: width, height: height)
    }

    private var groupFrames: [BWRProjectedGroupFrame] {
        boardProjection.groupFrames
    }

    private var stripFrames: [BWRProjectedParkingStripFrame] {
        boardProjection.stripFrames
    }

    private var dragDestinationPlaceholders: [BWRProjectedPlaceholder] {
        let projected = boardChromeState.dragOverlay.destinationPlaceholders(in: boardProjection)
        if !projected.isEmpty {
            return projected
        }
        if let transient = cardDragSession?.target?.placeholder {
            return [transient]
        }
        return []
    }

    private var hoverPlaceholder: BWRProjectedPlaceholder? {
        boardChromeState.hoverPlaceholder?.projectedPlaceholder(in: boardProjection)
    }

    private var slotCursorRect: CGRect? {
        guard boardChromeState.slotCursor.slotCursorVisibility == .visible,
              let slotReference = boardChromeState.slotCursor.slotReference else {
            return nil
        }
        return boardProjection.slotRect(for: slotReference)
    }

    private var dragSourceRects: [CGRect] {
        boardChromeState.dragOverlay.sourceRects(in: boardProjection)
    }

    private var dragSourceOverlayRects: [CGRect] {
        BWRSlotBoardGeometry.contiguousOverlayRects(from: dragSourceRects, gapTolerance: 1)
    }

    private var dragDestinationOverlayRects: [CGRect] {
        BWRSlotBoardGeometry.contiguousOverlayRects(
            from: dragDestinationPlaceholders.map(\.rect),
            gapTolerance: BWRCardBuddyStateGrammar.multiBlockBridgeGapCompensation
        )
    }

    private var dragDestinationHost: BWRSlotHost? {
        guard let placeholder = dragDestinationPlaceholders.first else { return nil }
        guard case let .dragDestination(host) = placeholder.kind else { return nil }
        return host
    }

    private var draggingCardIDs: Set<UUID> {
        Set(cardDragSession?.movingCardIDs ?? [])
    }

    private func displayedLayout(for card: BWRCard) -> BWRPoint {
        if let rect = boardProjection.cardRect(for: card.id) {
            return BWRPoint(x: rect.minX, y: rect.minY)
        }
        guard let placement = card.placement else {
            return BWRPoint(x: 0, y: 0)
        }
        let groupsByID = Dictionary(uniqueKeysWithValues: document.document.groups.map { ($0.id, $0) })
        let stripsByID = Dictionary(uniqueKeysWithValues: document.document.parkingStrips.map { ($0.id, $0) })
        return BWRShadowPlacementTransition.shadowLayout(
            for: placement,
            cardStableSortKey: card.stableSortKey,
            groupsByID: groupsByID,
            stripsByID: stripsByID
        )
    }

    private func selectCard(_ cardID: UUID, additive: Bool) {
        if additive {
            if selectedCardIDs.contains(cardID) {
                selectedCardIDs.remove(cardID)
            } else {
                selectedCardIDs.insert(cardID)
            }
        } else {
            selectedCardIDs = [cardID]
        }
        selectedGroupID = nil
        boardChromeState.slotCursor.syncSelection(
            cardID: selectedCardIDs.first,
            document: document.document,
            modality: .pointer
        )
    }

    private func handleContinuousHover(_ phase: HoverPhase) {
        guard cardDragSession == nil, groupDragSession == nil else { return }

        switch phase {
        case let .active(point):
            let logicalPoint = logicalBoardPoint(for: point)
            boardChromeState.hoverPlaceholder = BWRSlotBoardInteraction.resolveHoverPlaceholder(
                projection: boardProjection,
                pointer: logicalPoint
            )
        case .ended:
            boardChromeState.hoverPlaceholder = nil
        }
    }

    private func logicalBoardPoint(for point: CGPoint) -> CGPoint {
        let scale = max(viewportState.zoomScale, 0.001)
        return CGPoint(x: point.x / scale, y: point.y / scale)
    }

    private func selectionTarget(containing cardID: UUID) -> Set<UUID> {
        selectedCardIDs.contains(cardID) ? selectedCardIDs : [cardID]
    }

    private func orderedDragCardIDs(containing cardID: UUID) -> [UUID] {
        let selection = selectionTarget(containing: cardID)
        return BWRSlotBoardInteraction.orderedMovingCardIDs(document: document.document, cardIDs: selection)
    }

    private func updateViewportSize(from size: CGSize) {
        let width = Double(size.width) / max(viewportState.zoomScale, 0.001)
        let height = Double(size.height) / max(viewportState.zoomScale, 0.001)
        viewportState.viewportSize = BWRSize(width: width, height: height)
    }

    private func cardDragGesture(for card: BWRCard) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard inlineEditor?.cardID != card.id else { return }
                if !selectedCardIDs.contains(card.id) {
                    selectCard(card.id, additive: false)
                }

                let movingCardIDs = orderedDragCardIDs(containing: card.id)
                let cardRect = dragAnchorRect(for: card)
                let scale = max(viewportState.zoomScale, 0.001)
                let pointer = CGPoint(
                    x: cardRect.midX + (value.translation.width / scale),
                    y: cardRect.midY + (value.translation.height / scale)
                )

                let target = BWRSlotBoardInteraction.resolveCardDropTarget(
                    document: document.document,
                    projection: boardProjection,
                    draggingCardIDs: movingCardIDs,
                    leadCardID: card.id,
                    pointer: pointer,
                    viewportState: viewportState
                )
                cardDragSession = BWRBoardCardDragSession(
                    movingCardIDs: movingCardIDs,
                    leadCardID: card.id,
                    target: target
                )
                boardChromeState.hoverPlaceholder = nil
                boardChromeState.dragOverlay = BWRSlotBoardInteraction.resolveDragOverlayState(
                    document: document.document,
                    projection: boardProjection,
                    movingCardIDs: movingCardIDs,
                    target: target
                )
            }
            .onEnded { _ in
                guard let session = cardDragSession else { return }
                finishInlineEdit(true)
                applyCardDropTarget(session.target, movingCardIDs: session.movingCardIDs)
                cardDragSession = nil
                boardChromeState.dragOverlay.clear()
            }
    }

    private func dragAnchorRect(for card: BWRCard) -> CGRect {
        BWRBoardCardDragResolution.anchorRect(
            projectedRect: boardProjection.cardRect(for: card.id),
            fallbackOrigin: displayedLayout(for: card),
            cardSize: CGSize(width: BWRBoardMetrics.cardWidth, height: BWRBoardMetrics.cardHeight)
        )
    }

    private func groupDragGesture(for frame: BWRProjectedGroupFrame) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                finishInlineEdit(true)
                selectedGroupID = frame.group.id
                selectedCardIDs.removeAll()
                boardChromeState.hoverPlaceholder = nil
                boardChromeState.dragOverlay.clear()

                let scale = max(viewportState.zoomScale, 0.001)
                let deltaColumns = Int((value.translation.width / scale / boardProjection.metrics.slotWidth).rounded())
                let deltaRows = Int((value.translation.height / scale / boardProjection.metrics.slotHeight).rounded())
                let candidateOrigin = BWRSlotCoordinate(
                    column: max(0, frame.resolvedOriginSlot.column + deltaColumns),
                    row: max(0, frame.resolvedOriginSlot.row + deltaRows)
                )

                groupDragSession = BWRBoardGroupDragSession(
                    groupID: frame.group.id,
                    target: BWRSlotBoardInteraction.resolveGroupDropTarget(
                        projection: boardProjection,
                        groupID: frame.group.id,
                        candidateOriginSlot: candidateOrigin
                    )
                )
            }
            .onEnded { _ in
                guard let target = groupDragSession?.target else {
                    groupDragSession = nil
                    return
                }
                finishInlineEdit(true)
                document.moveGroupOrigin(groupID: target.groupID, originSlot: target.originSlot)
                selectedGroupID = target.groupID
                selectedCardIDs.removeAll()
                groupDragSession = nil
                boardChromeState.hoverPlaceholder = nil
            }
    }

    private func applyCardDropTarget(_ target: BWRSlotBoardCardDropTarget?, movingCardIDs: [UUID]) {
        guard let target, !movingCardIDs.isEmpty else { return }
        switch target.destination {
        case let .existingHost(host, rawInsertionIndex):
            let adjustedInsertionIndex = BWRSlotBoardInteraction.adjustedInsertionIndex(
                rawInsertionIndex: rawInsertionIndex,
                movingCardIDs: movingCardIDs,
                targetHost: host,
                document: document.document
            )
            document.moveCards(
                to: host,
                cardIDs: movingCardIDs,
                insertionIndex: adjustedInsertionIndex
            )
            if case let .group(groupID) = host {
                selectedGroupID = groupID
            } else {
                selectedGroupID = nil
            }
        case let .newParkingStrip(originSlot, insertionIndex):
            document.moveCardsToParkingStrip(
                cardIDs: movingCardIDs,
                originSlot: originSlot,
                insertionIndex: insertionIndex
            )
            selectedGroupID = nil
        }
        selectedCardIDs = Set(movingCardIDs)
        boardChromeState.slotCursor.syncSelection(
            cardID: movingCardIDs.first,
            document: document.document,
            modality: .drag
        )
        boardChromeState.hoverPlaceholder = nil
    }

    private func cardBackgroundColor(for card: BWRCard) -> Color {
        let fillHex = BWRCardBuddyBoardThemeGuardrail.resolvedCardFillHex(
            cardHex: card.colorHex,
            boardHex: resolvedBoardBackgroundHex
        )
        return Color(hex: fillHex) ?? .white
    }

    private var additiveSelectionEnabled: Bool {
        #if os(macOS)
        guard let event = NSApp.currentEvent else { return false }
        return event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift)
        #else
        return false
        #endif
    }

    private var boardProjection: BWRSlotBoardProjectionSnapshot {
        BWRSlotBoardProjection.project(document: document.document)
    }

    private var resolvedBoardBackgroundColor: Color? {
        guard let hex = resolvedBoardBackgroundHex else { return nil }
        return Color(hex: hex)
    }

    private var resolvedBoardBackgroundHex: String? {
        BWRCardBuddyBoardThemeGuardrail.resolvedBoardBackgroundHex(for: boardTheme)
    }
}

private struct BWRBoardCardDragSession: Equatable {
    var movingCardIDs: [UUID]
    var leadCardID: UUID
    var target: BWRSlotBoardCardDropTarget?
}

private struct BWRBoardGroupDragSession: Equatable {
    var groupID: UUID
    var target: BWRSlotBoardGroupDropTarget?
}

private enum BWRBoardMetrics {
    static let cardWidth: CGFloat = BWRSlotBoardGeometry.default.cardSize.width
    static let cardHeight: CGFloat = BWRSlotBoardGeometry.default.cardSize.height
}

nonisolated enum BWRBoardCardDragResolution {
    static func anchorRect(projectedRect: CGRect?, fallbackOrigin: BWRPoint, cardSize: CGSize) -> CGRect {
        if let projectedRect {
            return projectedRect
        }

        return CGRect(
            x: fallbackOrigin.x,
            y: fallbackOrigin.y,
            width: cardSize.width,
            height: cardSize.height
        )
    }
}

private struct BWRBoardGridBackground: View {
    let boardSize: CGSize
    let customBackgroundColor: Color?

    var body: some View {
        ZStack {
            if BWRCardBuddyStateGrammar.showsSlotGridBaseline {
                Canvas { context, size in
                    let metrics = BWRSlotBoardGeometry.default
                    for x in stride(from: 0, through: size.width, by: metrics.slotWidth) {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(
                            path,
                            with: .color(Color.black.opacity(0.06)),
                            lineWidth: 0.8
                        )
                    }
                    for y in stride(from: 0, through: size.height, by: metrics.slotHeight) {
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(
                            path,
                            with: .color(Color.black.opacity(0.06)),
                            lineWidth: 0.8
                        )
                    }
                }
            }
        }
        .frame(width: boardSize.width, height: boardSize.height)
        .background(
            Group {
                if let customBackgroundColor {
                    customBackgroundColor.opacity(0.92)
                } else {
                    LinearGradient(
                        colors: [
                            Color(nsColor: .windowBackgroundColor),
                            Color(nsColor: .underPageBackgroundColor)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        )
    }
}

private struct BWRBoardCardSelectionHalo: View {
    let surface: BWRCardBuddySurfaceStyleSnapshot

    var body: some View {
        let selectionColor = Color(hex: BWRCardBuddyCardShell.selectionHex) ?? .accentColor
        ZStack {
            if surface.selectionOuterSpread > 0 {
                RoundedRectangle(
                    cornerRadius: surface.cardCornerRadius + surface.selectionOuterSpread,
                    style: .continuous
                )
                .fill(selectionColor.opacity(0.22))
                .padding(-surface.selectionOuterSpread)
            }

            RoundedRectangle(
                cornerRadius: surface.cardCornerRadius + surface.selectionOuterSpread * 0.25,
                style: .continuous
            )
            .stroke(selectionColor, lineWidth: surface.selectionOutlineWidth)
            .padding(-surface.selectionOuterSpread)
        }
        .allowsHitTesting(false)
    }
}

private struct BWRBoardCardMarkdownPreviewBlock: View {
    let preview: BWRCardMarkdownPreviewRenderResult
    let surface: BWRCardBuddySurfaceStyleSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: preview.containsSoftBreaks ? 5 : 4) {
            if preview.visibleLines.isEmpty {
                Text("Empty card")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black.opacity(0.38))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(preview.visibleLines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(.system(size: 13, weight: lineWeight(at: index)))
                        .foregroundStyle(lineColor(at: index))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer(minLength: max(0, surface.cardInnerPadding - 4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func lineWeight(at index: Int) -> Font.Weight {
        if preview.containsStrongEmphasis && index == 0 {
            return .semibold
        }
        return index == 0 && !preview.containsListItems ? .medium : .regular
    }

    private func lineColor(at index: Int) -> Color {
        index == 0 ? Color.black.opacity(0.86) : Color.black.opacity(0.78)
    }
}

private struct BWRBoardInlineEditorFooter: View {
    let layerName: String
    let showsLayerCycle: Bool
    let onPreviousLayer: () -> Void
    let onNextLayer: () -> Void
    let onExpand: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if showsLayerCycle {
                iconButton(systemName: "chevron.left.circle", action: onPreviousLayer, label: "Previous Layer")
                Text(layerName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                iconButton(systemName: "chevron.right.circle", action: onNextLayer, label: "Next Layer")
            }

            Spacer(minLength: 6)

            Label("Split", systemImage: "arrow.turn.down.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            iconButton(systemName: "arrow.up.left.and.arrow.down.right", action: onExpand, label: "Open Large Editor")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func iconButton(systemName: String, action: @escaping () -> Void, label: String) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 18, height: 18)
                .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

private struct BWRBoardSlotCursorView: View {
    let isEmphasized: Bool

    var body: some View {
        BWRBoardOverlayFrameView(style: BWRCardBuddyStateGrammar.slotCursorStyle(isEmphasized: isEmphasized))
    }
}

private struct BWRBoardDragSourceView: View {
    let isLifted: Bool

    var body: some View {
        BWRBoardOverlayFrameView(style: BWRCardBuddyStateGrammar.dragSourceStyle(isLifted: isLifted))
    }
}

private struct BWRGroupFrameView: View {
    let frame: BWRProjectedGroupFrame
    let isSelected: Bool

    var body: some View {
        let style = BWRCardBuddyBoardThemeGuardrail.groupPanelStyle(isSelected: isSelected)
        let fillColor = BWRCardBuddyBoardThemeGuardrail.boardColor(for: style.fillHex)
        let strokeColor = BWRCardBuddyBoardThemeGuardrail.boardColor(for: style.strokeHex)

        ZStack {
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .fill(fillColor.opacity(style.fillOpacity))
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .strokeBorder(strokeColor.opacity(style.strokeOpacity), lineWidth: style.strokeWidth)
        }
        .allowsHitTesting(false)
    }
}

private struct BWRParkingStripFrameView: View {
    let frame: BWRProjectedParkingStripFrame

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.018))
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1, dash: [8, 6])
                )
                .foregroundStyle(Color.black.opacity(0.14))
            VStack(alignment: .leading, spacing: 4) {
                Text("Parking Strip")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(frame.strip.cardIDs.count) cards")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }
}

private struct BWRBoardOverlayFrameView: View {
    let style: BWRCardBuddyOverlayStyleSnapshot

    var body: some View {
        let strokeColor = BWRCardBuddyStateGrammar.strokeColor(for: style.strokePalette)
        let fillColor = BWRCardBuddyStateGrammar.fillColor(for: style.fillPalette)

        RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
            .fill(fillColor.opacity(style.fillOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(
                            lineWidth: style.lineWidth,
                            lineCap: style.usesRoundDashCaps ? .round : .butt,
                            lineJoin: .round,
                            dash: style.dash
                        )
                    )
                    .foregroundStyle(strokeColor.opacity(style.strokeOpacity))
            )
            .shadow(
                color: strokeColor.opacity(style.shadowOpacity),
                radius: style.shadowRadius,
                x: 0,
                y: style.shadowYOffset
            )
            .allowsHitTesting(false)
    }
}

private struct BWRBoardPlaceholderView: View {
    let placeholder: BWRProjectedPlaceholder
    var isEmphasized: Bool = true

    var body: some View {
        BWRBoardOverlayFrameView(style: overlayStyle)
    }

    private var overlayStyle: BWRCardBuddyOverlayStyleSnapshot {
        switch placeholder.kind {
        case .groupBlock:
            return BWRCardBuddyStateGrammar.groupBlockStyle()
        case .hoverSlot:
            return BWRCardBuddyStateGrammar.hoverStyle(isEmphasized: isEmphasized)
        case let .dragDestination(host):
            return BWRCardBuddyStateGrammar.dragDestinationStyle(host: host)
        }
    }
}

private struct BWRBoardScrollOriginTracker: View {
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
    }
}

private struct BWRBoardScrollOriginPreferenceKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero

    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}

extension Color {
    init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard trimmed.count == 6, let value = Int(trimmed, radix: 16) else { return nil }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}
