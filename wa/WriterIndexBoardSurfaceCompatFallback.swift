// Compatibility-only SwiftUI fallback surface.
// Active board rendering lives in IndexBoardSurfaceAppKitPhaseTwoView.
// Re-evaluate deletion by 2026-04-11; do not add new responsibilities here.
import SwiftUI
import AppKit
import Combine

private enum IndexBoardSurfacePhaseConstants {
    static let canvasCoordinateSpaceName = "IndexBoardSurfaceCanvasCoordinateSpace"
    static let laneChipHeight: CGFloat = 26
    static let laneChipSpacing: CGFloat = 6
    static let lineSpacing: CGFloat = 18
    static let detachedOuterPaddingSlots = 3
    static let autoScrollEdgeInset: CGFloat = 80
    static let maxAutoScrollStep: CGFloat = 22
    static let flowSnapDistance: CGFloat = 64
    static let surfaceHorizontalOverscan: CGFloat = 320
    static let surfaceVerticalOverscan: CGFloat = 220
    static let minimumCanvasLeadInset: CGFloat = 144
    static let minimumCanvasTopInset: CGFloat = 72
    static let laneWrapperInset: CGFloat = 10
    static let flowInteractionHorizontalInset: CGFloat = 88
    static let flowInteractionVerticalInset: CGFloat = 112
    static let flowInteractionVerticalHysteresis: CGFloat = 148
    static let dragGhostOpacity: CGFloat = 0
}

private func indexBoardSurfaceItemSort(_ lhs: BoardSurfaceItem, _ rhs: BoardSurfaceItem) -> Bool {
    switch (lhs.slotIndex, rhs.slotIndex) {
    case let (.some(lhsSlotIndex), .some(rhsSlotIndex)):
        if lhsSlotIndex != rhsSlotIndex {
            return lhsSlotIndex < rhsSlotIndex
        }
    case (.some, nil):
        return true
    case (nil, .some):
        return false
    case (.none, .none):
        let lhsPosition = lhs.detachedGridPosition ?? .init(column: 0, row: 0)
        let rhsPosition = rhs.detachedGridPosition ?? .init(column: 0, row: 0)
        if lhsPosition.row != rhsPosition.row {
            return lhsPosition.row < rhsPosition.row
        }
        if lhsPosition.column != rhsPosition.column {
            return lhsPosition.column < rhsPosition.column
        }
    }

    if lhs.laneIndex != rhs.laneIndex {
        return lhs.laneIndex < rhs.laneIndex
    }
    return lhs.cardID.uuidString < rhs.cardID.uuidString
}

private struct IndexBoardSurfaceCardFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct IndexBoardGlobalSlotLayout: Layout {
    let columns: Int
    let itemSpacing: CGFloat
    let lineSpacing: CGFloat
    let slotSize: CGSize

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let safeColumns = max(1, columns)
        let rows = Int(ceil(Double(subviews.count) / Double(safeColumns)))
        let width =
            (CGFloat(safeColumns) * slotSize.width) +
            (CGFloat(max(0, safeColumns - 1)) * itemSpacing)
        let height =
            (CGFloat(rows) * slotSize.height) +
            (CGFloat(max(0, rows - 1)) * lineSpacing)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let safeColumns = max(1, columns)
        for (index, subview) in subviews.enumerated() {
            let row = index / safeColumns
            let column = index % safeColumns
            let origin = CGPoint(
                x: bounds.minX + (CGFloat(column) * (slotSize.width + itemSpacing)),
                y: bounds.minY + (CGFloat(row) * (slotSize.height + lineSpacing))
            )
            subview.place(
                at: origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(slotSize)
            )
        }
    }
}

private struct IndexBoardSurfaceCardDragState {
    let cardID: UUID
    let movingCardIDs: [UUID]
    let sourcePlacement: IndexBoardSurfaceDropPlacement
    let sourceLaneParentID: UUID?
    let sourceTarget: IndexBoardCardDropTarget
    let initialFrame: CGRect
    let pointerOffset: CGSize
    var pointerInViewport: CGPoint
    var dropPlacement: IndexBoardSurfaceDropPlacement

    var movingCardIDSet: Set<UUID> {
        Set(movingCardIDs)
    }

    func pointerInContent(scrollOrigin: CGPoint) -> CGPoint {
        CGPoint(
            x: pointerInViewport.x + scrollOrigin.x,
            y: pointerInViewport.y + scrollOrigin.y
        )
    }

    func overlayOrigin(scrollOrigin: CGPoint) -> CGPoint {
        let pointer = pointerInContent(scrollOrigin: scrollOrigin)
        return CGPoint(
            x: pointer.x - pointerOffset.width,
            y: pointer.y - pointerOffset.height
        )
    }
}

private struct IndexBoardSurfaceSelectionDragState {
    let startPoint: CGPoint
    var currentPoint: CGPoint
    var selectedCardIDs: Set<UUID>
}

private enum IndexBoardSurfaceDropPlacement: Equatable {
    case flow(Int)
    case detached(IndexBoardGridPosition)
}

private struct IndexBoardSurfaceGridBounds {
    let minColumn: Int
    let maxColumn: Int
    let minRow: Int
    let maxRow: Int

    var columnCount: Int { max(1, maxColumn - minColumn + 1) }
    var rowCount: Int { max(1, maxRow - minRow + 1) }
}

private enum IndexBoardSurfaceRenderedEntry: Identifiable {
    case live(BoardSurfaceItem)
    case placeholder(cardID: UUID, laneParentID: UUID?)

    var id: String {
        switch self {
        case .live(let item):
            return item.cardID.uuidString
        case .placeholder(let cardID, _):
            return "placeholder-\(cardID.uuidString)"
        }
    }

    var cardID: UUID? {
        switch self {
        case .live(let item):
            return item.cardID
        case .placeholder:
            return nil
        }
    }

    var laneParentID: UUID? {
        switch self {
        case .live(let item):
            return item.laneParentID
        case .placeholder(_, let laneParentID):
            return laneParentID
        }
    }
}

private struct IndexBoardSurfaceLaneChipView: View {
    let lane: BoardSurfaceLane
    let theme: IndexBoardRenderTheme
    let canMoveBackward: Bool
    let canMoveForward: Bool
    let isInteractionEnabled: Bool
    let onMoveBackward: () -> Void
    let onMoveForward: () -> Void

    private var tintColor: Color {
        if lane.isTempLane {
            return Color.orange.opacity(theme.usesDarkAppearance ? 0.92 : 0.88)
        }
        if let token = lane.colorToken,
           let rgb = parseHexRGB(token) {
            return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
        }
        return theme.accentColor
    }

    private var eyebrowText: String {
        if lane.isTempLane {
            return "TEMP"
        }
        if lane.parentCardID == nil {
            return "ROOT"
        }
        return "LANE"
    }

    private var eyebrowBackground: Color {
        if lane.isTempLane {
            return Color.orange.opacity(theme.usesDarkAppearance ? 0.24 : 0.16)
        }
        return Color.black.opacity(theme.usesDarkAppearance ? 0.16 : 0.06)
    }

    private var shellFill: Color {
        tintColor.opacity(theme.usesDarkAppearance ? 0.16 : 0.10)
    }

    private var shellStroke: Color {
        tintColor.opacity(theme.usesDarkAppearance ? 0.40 : 0.22)
    }

    private var reorderCapsuleFill: Color {
        Color.black.opacity(theme.usesDarkAppearance ? 0.12 : 0.05)
    }

    var body: some View {
        HStack(spacing: 7) {
            Text(eyebrowText)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(lane.isTempLane ? Color.orange.opacity(0.94) : theme.secondaryTextColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(eyebrowBackground)
                )

            Circle()
                .fill(tintColor.opacity(theme.usesDarkAppearance ? 0.84 : 0.92))
                .frame(width: 7, height: 7)

            Text(lane.labelText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.primaryTextColor)
                .lineLimit(1)
                .help(lane.subtitleText)

            Spacer(minLength: 0)

            if canMoveBackward || canMoveForward {
                HStack(spacing: 2) {
                    Button(action: onMoveBackward) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isInteractionEnabled || !canMoveBackward)

                    Button(action: onMoveForward) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isInteractionEnabled || !canMoveForward)
                }
                .foregroundStyle(theme.secondaryTextColor)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(reorderCapsuleFill)
                )
            }
        }
        .padding(.horizontal, 9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(shellFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(shellStroke, lineWidth: 1)
        )
        .frame(width: IndexBoardMetrics.cardSize.width, height: IndexBoardSurfacePhaseConstants.laneChipHeight, alignment: .leading)
    }
}

private struct IndexBoardSurfacePlaceholderTile: View {
    let theme: IndexBoardRenderTheme

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.black.opacity(theme.usesDarkAppearance ? 0.22 : 0.18))
            .frame(
                width: IndexBoardMetrics.cardSize.width,
                height: IndexBoardMetrics.cardSize.height
            )
            .shadow(
                color: Color.black.opacity(theme.usesDarkAppearance ? 0.18 : 0.10),
                radius: 12,
                x: 0,
                y: 6
            )
    }
}

private struct IndexBoardSurfaceSlotView: View {
    let entry: IndexBoardSurfaceRenderedEntry
    let lane: BoardSurfaceLane?
    let showsLaneChip: Bool
    let reservesLaneSpacer: Bool
    let theme: IndexBoardRenderTheme
    let card: SceneCard?
    let isSelected: Bool
    let isActive: Bool
    let summary: IndexBoardResolvedSummary?
    let showsBack: Bool
    let isInteractionEnabled: Bool
    let isGhosted: Bool
    let onTap: () -> Void
    let onOpen: () -> Void
    let onToggleFace: () -> Void
    let canMoveLaneBackward: Bool
    let canMoveLaneForward: Bool
    let onMoveLaneBackward: () -> Void
    let onMoveLaneForward: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: IndexBoardSurfacePhaseConstants.laneChipSpacing) {
            if showsLaneChip, let lane {
                IndexBoardSurfaceLaneChipView(
                    lane: lane,
                    theme: theme,
                    canMoveBackward: canMoveLaneBackward,
                    canMoveForward: canMoveLaneForward,
                    isInteractionEnabled: isInteractionEnabled,
                    onMoveBackward: onMoveLaneBackward,
                    onMoveForward: onMoveLaneForward
                )
            } else if reservesLaneSpacer {
                Color.clear
                    .frame(
                        width: IndexBoardMetrics.cardSize.width,
                        height: IndexBoardSurfacePhaseConstants.laneChipHeight
                    )
            }

            if let card {
                IndexBoardCardTile(
                    card: card,
                    theme: theme,
                    isSelected: isSelected,
                    isActive: isActive,
                    summary: summary,
                    showsBack: showsBack,
                    onTap: {
                        guard isInteractionEnabled else { return }
                        onTap()
                    },
                    onToggleFace: {
                        guard isInteractionEnabled else { return }
                        onToggleFace()
                    },
                    onOpen: {
                        guard isInteractionEnabled else { return }
                        onOpen()
                    }
                )
                .gesture(
                    DragGesture(
                        minimumDistance: 3,
                        coordinateSpace: .named(IndexBoardSurfacePhaseConstants.canvasCoordinateSpaceName)
                    )
                    .onChanged(onDragChanged)
                    .onEnded(onDragEnded)
                )
            } else {
                IndexBoardSurfacePlaceholderTile(theme: theme)
            }
        }
        .frame(
            width: IndexBoardMetrics.cardSize.width,
            height: IndexBoardMetrics.cardSize.height + IndexBoardSurfacePhaseConstants.laneChipHeight + IndexBoardSurfacePhaseConstants.laneChipSpacing,
            alignment: .topLeading
        )
        .opacity(isGhosted ? IndexBoardSurfacePhaseConstants.dragGhostOpacity : 1)
    }
}

@MainActor
struct IndexBoardSurfaceCompatFallbackView: View {
    let surfaceProjection: BoardSurfaceProjection
    let sourceTitle: String
    let canvasSize: CGSize
    let theme: IndexBoardRenderTheme
    let projection: IndexBoardProjection
    let cardsByID: [UUID: SceneCard]
    let activeCardID: UUID?
    let selectedCardIDs: Set<UUID>
    let summaryByCardID: [UUID: IndexBoardResolvedSummary]
    let showsBackByCardID: [UUID: Bool]
    let zoomScale: CGFloat
    let scrollOffset: CGPoint
    let revealCardID: UUID?
    let revealRequestToken: Int
    let isInteractionEnabled: Bool
    let onClose: () -> Void
    let onCreateTempCard: () -> Void
    let onCardTap: (SceneCard) -> Void
    let onCardOpen: (SceneCard) -> Void
    let onCardFaceToggle: (SceneCard) -> Void
    let onZoomScaleChange: (CGFloat) -> Void
    let onZoomStep: (CGFloat) -> Void
    let onZoomReset: () -> Void
    let onScrollOffsetChange: (CGPoint) -> Void
    let onCardMove: (UUID, IndexBoardCardDropTarget) -> Void
    let onCardMoveSelection: ([UUID], UUID, IndexBoardCardDropTarget) -> Void
    let onMarqueeSelectionChange: (Set<UUID>) -> Void
    let onClearSelection: () -> Void
    let onGroupMove: (IndexBoardGroupID, Int) -> Void

    @StateObject private var scrollController = IndexBoardScrollController()
    @State private var cardFrameByID: [UUID: CGRect] = [:]
    @State private var pendingRevealCardID: UUID? = nil
    @State private var cardDragState: IndexBoardSurfaceCardDragState? = nil
    @State private var presentationSurfaceProjection: BoardSurfaceProjection? = nil
    @State private var selectionDragState: IndexBoardSurfaceSelectionDragState? = nil
    @State private var lockedColumnCount: Int? = nil
    @State private var pendingScrollPersistenceWorkItem: DispatchWorkItem? = nil
    @State private var pendingZoomPersistenceWorkItem: DispatchWorkItem? = nil

    private let autoScrollTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    private var effectiveSurfaceProjection: BoardSurfaceProjection {
        presentationSurfaceProjection ?? surfaceProjection
    }

    private var orderedItems: [BoardSurfaceItem] {
        effectiveSurfaceProjection.surfaceItems.sorted(by: indexBoardSurfaceItemSort)
    }

    private var flowItems: [BoardSurfaceItem] {
        orderedItems.filter { !$0.isDetached }
    }

    private var itemByCardID: [UUID: BoardSurfaceItem] {
        Dictionary(uniqueKeysWithValues: orderedItems.map { ($0.cardID, $0) })
    }

    private var laneByKey: [String: BoardSurfaceLane] {
        Dictionary(uniqueKeysWithValues: effectiveSurfaceProjection.lanes.map { (laneKey(for: $0.parentCardID), $0) })
    }

    private var groupByLaneKey: [String: IndexBoardGroupProjection] {
        Dictionary(uniqueKeysWithValues: projection.groups.map { (laneKey(for: $0.id.parentID), $0) })
    }

    private var movableGroupIndices: [Int] {
        projection.groups.enumerated().compactMap { index, group in
            guard group.parentCard != nil, !group.isTempGroup else { return nil }
            return index
        }
    }

    private var slotSize: CGSize {
        CGSize(
            width: IndexBoardMetrics.cardSize.width,
            height: IndexBoardMetrics.cardSize.height +
                IndexBoardSurfacePhaseConstants.laneChipHeight +
                IndexBoardSurfacePhaseConstants.laneChipSpacing
        )
    }

    private var surfaceHorizontalInset: CGFloat {
        max(IndexBoardMetrics.boardHorizontalPadding, IndexBoardSurfacePhaseConstants.minimumCanvasLeadInset)
    }

    private var surfaceVerticalInset: CGFloat {
        max(IndexBoardMetrics.boardVerticalPadding, IndexBoardSurfacePhaseConstants.minimumCanvasTopInset)
    }

    private var preferredColumns: Int {
        lockedColumnCount ?? resolvedInitialColumnCount()
    }

    private var canvasContentWidth: CGFloat {
        max(
            canvasSize.width + IndexBoardSurfacePhaseConstants.surfaceHorizontalOverscan,
            gridContentSize.width +
                (surfaceHorizontalInset * 2) +
                IndexBoardSurfacePhaseConstants.surfaceHorizontalOverscan
        )
    }

    private var gridContentSize: CGSize {
        let width =
            (CGFloat(logicalGridBounds.columnCount) * slotSize.width) +
            (CGFloat(max(0, logicalGridBounds.columnCount - 1)) * IndexBoardMetrics.cardSpacing)
        let height =
            (CGFloat(logicalGridBounds.rowCount) * slotSize.height) +
            (CGFloat(max(0, logicalGridBounds.rowCount - 1)) * IndexBoardSurfacePhaseConstants.lineSpacing)
        return CGSize(width: width, height: height)
    }

    private var canvasContentHeight: CGFloat {
        max(
            canvasSize.height + IndexBoardSurfacePhaseConstants.surfaceVerticalOverscan,
            gridContentSize.height +
                (surfaceVerticalInset * 2) +
                IndexBoardSurfacePhaseConstants.surfaceVerticalOverscan
        )
    }

    private var zoomPercentText: String {
        "\(Int((zoomScale * 100).rounded()))%"
    }

    private var isDragging: Bool {
        cardDragState != nil
    }

    private var marqueeSelectionRect: CGRect? {
        guard let selectionDragState else { return nil }
        return normalizedSelectionRect(
            from: selectionDragState.startPoint,
            to: selectionDragState.currentPoint
        )
    }

    private var baseFlowSlotIndexByCardID: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: flowItems.compactMap { item in
            guard let slotIndex = item.slotIndex else { return nil }
            return (item.cardID, slotIndex)
        })
    }

    private var displayedFlowSlotIndexByCardID: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: flowItems.compactMap { item in
            guard let slotIndex = item.slotIndex else { return nil }
            return (item.cardID, slotIndex)
        })
    }

    private var occupiedGridPositionByCardID: [UUID: IndexBoardGridPosition] {
        var positionByCardID: [UUID: IndexBoardGridPosition] = [:]
        positionByCardID.reserveCapacity(orderedItems.count)

        for item in orderedItems {
            guard let position = resolvedVisualGridPosition(for: item) else { continue }
            positionByCardID[item.cardID] = position
        }
        return positionByCardID
    }

    private var logicalGridBounds: IndexBoardSurfaceGridBounds {
        let positions = occupiedGridPositionByCardID.values
        let minColumn = positions.map(\.column).min() ?? 0
        let maxColumn = positions.map(\.column).max() ?? max(0, preferredColumns - 1)
        let minRow = positions.map(\.row).min() ?? 0
        let maxRow = positions.map(\.row).max() ?? 0
        return IndexBoardSurfaceGridBounds(
            minColumn: minColumn - IndexBoardSurfacePhaseConstants.detachedOuterPaddingSlots,
            maxColumn: maxColumn + IndexBoardSurfacePhaseConstants.detachedOuterPaddingSlots,
            minRow: minRow - IndexBoardSurfacePhaseConstants.detachedOuterPaddingSlots,
            maxRow: maxRow + IndexBoardSurfacePhaseConstants.detachedOuterPaddingSlots
        )
    }

    private var laneWrapperFrames: [(id: String, frame: CGRect, tintColor: Color)] {
        var frameByLaneKey: [String: CGRect] = [:]
        let movingCardIDs = cardDragState?.movingCardIDSet ?? []

        for item in flowItems where !movingCardIDs.contains(item.cardID) {
            guard let slotFrame = resolvedRenderedFrame(for: item) else { continue }
            let key = laneKey(for: item.laneParentID)
            let cardFrame = resolvedCardFrame(for: slotFrame, reservesLaneSpacer: true)
                .insetBy(
                    dx: -IndexBoardSurfacePhaseConstants.laneWrapperInset,
                    dy: -IndexBoardSurfacePhaseConstants.laneWrapperInset
                )
            frameByLaneKey[key] = frameByLaneKey[key].map { $0.union(cardFrame) } ?? cardFrame
        }

        return frameByLaneKey.keys.sorted().compactMap { key in
            guard let frame = frameByLaneKey[key] else { return nil }
            let lane = laneByKey[key]
            return (key, frame, resolvedLaneTintColor(for: lane))
        }
    }

    private var renderedEntries: [IndexBoardSurfaceRenderedEntry] {
        orderedItems.map(IndexBoardSurfaceRenderedEntry.live)
    }

    private var laneStartEntryIDs: Set<String> {
        var seenKeys: Set<String> = []
        var ids: Set<String> = []
        let movingCardIDs = cardDragState?.movingCardIDSet ?? []
        let laneEntries = flowItems.compactMap { item -> (id: String, laneParentID: UUID?, sortIndex: Int)? in
            guard !movingCardIDs.contains(item.cardID) else { return nil }
            let sortIndex = displayedFlowSlotIndexByCardID[item.cardID] ?? item.slotIndex ?? 0
            return (item.cardID.uuidString, item.laneParentID, sortIndex)
        }
        .sorted { $0.sortIndex < $1.sortIndex }

        for entry in laneEntries {
            let key = laneKey(for: entry.laneParentID)
            if seenKeys.insert(key).inserted {
                ids.insert(entry.id)
            }
        }
        return ids
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if orderedItems.isEmpty {
                emptyState
            } else {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    boardScrollContent
                }
                .background(
                    IndexBoardScrollViewAccessor(
                        scrollController: scrollController,
                        desiredMagnification: zoomScale,
                        desiredViewportOrigin: scrollOffset
                    )
                )
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .background(theme.boardBackground)
        .onAppear {
            if lockedColumnCount == nil {
                lockedColumnCount = resolvedInitialColumnCount()
            }
            pendingRevealCardID = revealCardID
            attemptPendingCardReveal()
        }
        .onPreferenceChange(IndexBoardSurfaceCardFramePreferenceKey.self) { frames in
            cardFrameByID = frames
            attemptPendingCardReveal()
        }
        .onReceive(autoScrollTimer) { _ in
            handleAutoScrollTick()
        }
        .onChange(of: scrollController.viewportOrigin) { _, newValue in
            if isDragging {
                recalculateDropPlacement()
            } else {
                scheduleScrollOffsetPersistence(newValue)
            }
        }
        .onChange(of: scrollController.magnification) { _, newValue in
            guard !isDragging else { return }
            let clamped = min(max(newValue, IndexBoardZoom.minScale), IndexBoardZoom.maxScale)
            guard abs(clamped - zoomScale) > 0.001 else { return }
            scheduleZoomPersistence(clamped)
        }
        .onChange(of: revealRequestToken) { _, _ in
            pendingRevealCardID = revealCardID
            attemptPendingCardReveal()
        }
        .onChange(of: surfaceProjection) { _, newValue in
            settlePresentationProjection(with: newValue)
        }
        .onDisappear {
            flushDeferredViewportPersistence()
        }
    }

    private var boardScrollContent: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: canvasContentWidth, height: canvasContentHeight)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    guard isInteractionEnabled else { return }
                    onCreateTempCard()
                }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        guard isInteractionEnabled else { return }
                        onClearSelection()
                    }
                )
                .gesture(marqueeSelectionGesture)

            ForEach(laneWrapperFrames, id: \.id) { wrapper in
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(wrapper.tintColor.opacity(theme.usesDarkAppearance ? 0.08 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                wrapper.tintColor.opacity(theme.usesDarkAppearance ? 0.34 : 0.20),
                                lineWidth: 1
                            )
                    )
                    .frame(width: wrapper.frame.width, height: wrapper.frame.height)
                    .offset(x: wrapper.frame.minX, y: wrapper.frame.minY)
                    .allowsHitTesting(false)
            }

            ForEach(renderedEntries) { entry in
                if let frame = resolvedRenderedFrame(for: entry) {
                    renderedEntryView(entry)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }

            if let marqueeSelectionRect {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.accentColor.opacity(theme.usesDarkAppearance ? 0.14 : 0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.82), lineWidth: 1.5)
                    )
                    .frame(width: marqueeSelectionRect.width, height: marqueeSelectionRect.height)
                    .offset(x: marqueeSelectionRect.minX, y: marqueeSelectionRect.minY)
                    .allowsHitTesting(false)
            }

            dragOverlay
        }
        .frame(width: canvasContentWidth, height: canvasContentHeight, alignment: .topLeading)
        .coordinateSpace(name: IndexBoardSurfacePhaseConstants.canvasCoordinateSpaceName)
    }

    @ViewBuilder
    private func renderedEntryView(_ entry: IndexBoardSurfaceRenderedEntry) -> some View {
        let lane = laneByKey[laneKey(for: entry.laneParentID)]
        let showsLaneChip = laneStartEntryIDs.contains(entry.id)
        let laneMoveContext = lane.flatMap { resolvedLaneMoveContext(for: $0) }
        let movingCardIDs = cardDragState?.movingCardIDSet ?? []

        switch entry {
        case .live(let item):
            if let card = cardsByID[item.cardID] {
                IndexBoardSurfaceSlotView(
                    entry: entry,
                    lane: lane,
                    showsLaneChip: showsLaneChip,
                    reservesLaneSpacer: !item.isDetached,
                    theme: theme,
                    card: card,
                    isSelected: selectedCardIDs.contains(card.id),
                    isActive: activeCardID == card.id,
                    summary: summaryByCardID[card.id],
                    showsBack: showsBackByCardID[card.id] ?? false,
                    isInteractionEnabled: isInteractionEnabled && !isDragging,
                    isGhosted: movingCardIDs.contains(card.id),
                    onTap: {
                        onCardTap(card)
                    },
                    onOpen: {
                        onCardOpen(card)
                    },
                    onToggleFace: {
                        onCardFaceToggle(card)
                    },
                    canMoveLaneBackward: laneMoveContext?.targetBackwardIndex != nil,
                    canMoveLaneForward: laneMoveContext?.targetForwardIndex != nil,
                    onMoveLaneBackward: {
                        if let laneMoveContext,
                           let targetIndex = laneMoveContext.targetBackwardIndex {
                            onGroupMove(laneMoveContext.groupID, targetIndex)
                        }
                    },
                    onMoveLaneForward: {
                        if let laneMoveContext,
                           let targetIndex = laneMoveContext.targetForwardIndex {
                            onGroupMove(laneMoveContext.groupID, targetIndex)
                        }
                    },
                    onDragChanged: { value in
                        handleCardDragChanged(item, value: value)
                    },
                    onDragEnded: { value in
                        handleCardDragEnded(item, value: value)
                    }
                )
                .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.92), value: cardDragState?.dropPlacement)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: IndexBoardSurfaceCardFramePreferenceKey.self,
                            value: [
                                card.id: proxy.frame(in: .named(IndexBoardSurfacePhaseConstants.canvasCoordinateSpaceName))
                            ]
                        )
                    }
                )
            }
        case .placeholder:
            IndexBoardSurfaceSlotView(
                entry: entry,
                lane: lane,
                showsLaneChip: showsLaneChip,
                reservesLaneSpacer: true,
                theme: theme,
                card: nil,
                isSelected: false,
                isActive: false,
                summary: nil,
                showsBack: false,
                isInteractionEnabled: false,
                isGhosted: false,
                onTap: {},
                onOpen: {},
                onToggleFace: {},
                canMoveLaneBackward: false,
                canMoveLaneForward: false,
                onMoveLaneBackward: {},
                onMoveLaneForward: {},
                onDragChanged: { _ in },
                onDragEnded: { _ in }
            )
        }
    }

    @ViewBuilder
    private var dragOverlay: some View {
        if let drag = cardDragState,
           let primaryCard = cardsByID[drag.cardID] {
            let origin = drag.overlayOrigin(scrollOrigin: scrollController.viewportOrigin)
            let overlayCardIDs = resolvedOverlayCardIDs(for: drag)
            let placeholderFrames = dragPlaceholderFrames(for: drag)

            ForEach(Array(placeholderFrames.enumerated()), id: \.offset) { _, placeholderFrame in
                IndexBoardSurfacePlaceholderTile(theme: theme)
                    .offset(
                        x: placeholderFrame.minX,
                        y: placeholderFrame.minY
                    )
                    .animation(
                        .interactiveSpring(response: 0.18, dampingFraction: 0.92),
                        value: drag.dropPlacement
                    )
                    .allowsHitTesting(false)
            }

            ForEach(Array(overlayCardIDs.enumerated()), id: \.element) { index, cardID in
                if let card = cardsByID[cardID] {
                    let reverseIndex = overlayCardIDs.count - index - 1
                    let stackX = CGFloat(reverseIndex) * 14
                    let stackY = CGFloat(reverseIndex) * 4
                    IndexBoardCardTile(
                        card: card,
                        theme: theme,
                        isSelected: false,
                        isActive: false,
                        summary: summaryByCardID[card.id],
                        showsBack: showsBackByCardID[card.id] ?? false,
                        onTap: {}
                    )
                    .opacity(cardID == primaryCard.id ? 1 : 0.92)
                    .shadow(
                        color: Color.black.opacity(theme.usesDarkAppearance ? 0.22 : 0.14),
                        radius: 18,
                        x: 0,
                        y: 10
                    )
                    .offset(x: origin.x + stackX, y: origin.y + stackY)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                Text(sourceTitle)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primaryTextColor)
                    .lineLimit(1)

                Text("BOARD · \(surfaceProjection.lanes.count) lanes · \(surfaceProjection.orderedCardIDs.count) cards")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.secondaryTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(theme.usesDarkAppearance ? 0.14 : 0.06))
                    )
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button(action: {
                    onZoomStep(-IndexBoardZoom.step)
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(zoomScale <= IndexBoardZoom.minScale + 0.001)

                Button("100%") {
                    onZoomReset()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(abs(zoomScale - IndexBoardZoom.defaultScale) < 0.001)

                Button(action: {
                    onZoomStep(IndexBoardZoom.step)
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(zoomScale >= IndexBoardZoom.maxScale - 0.001)

                Text(zoomPercentText)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.primaryTextColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(theme.usesDarkAppearance ? 0.22 : 0.08))
                    )
            }

            Button("+ Temp 카드") {
                onCreateTempCard()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!isInteractionEnabled)

            Button("작업창으로 돌아가기") {
                onClose()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(theme.groupBackground.opacity(theme.usesDarkAppearance ? 0.90 : 0.82))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.groupBorder.opacity(0.65))
                .frame(height: 1)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("표시할 카드가 없습니다.")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(theme.primaryTextColor)
            Text("빈 배경 더블클릭, N, 또는 + Temp 카드로 임시 카드를 만들 수 있습니다.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.secondaryTextColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(40)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard isInteractionEnabled else { return }
            onCreateTempCard()
        }
    }

    private var marqueeSelectionGesture: some Gesture {
        DragGesture(
            minimumDistance: 3,
            coordinateSpace: .named(IndexBoardSurfacePhaseConstants.canvasCoordinateSpaceName)
        )
        .onChanged { value in
            handleMarqueeSelectionChanged(value)
        }
        .onEnded { value in
            handleMarqueeSelectionEnded(value)
        }
    }

    private func handleCardDragChanged(_ item: BoardSurfaceItem, value: DragGesture.Value) {
        if cardDragState?.cardID != item.cardID {
            cancelDeferredViewportPersistence()
            guard let initialFrame = cardFrameByID[item.cardID] else { return }
            let movingItems = resolvedMovingItems(for: item)
            let movingCardIDs = movingItems.map(\.cardID)
            let sourcePlacement: IndexBoardSurfaceDropPlacement
            if let detachedGridPosition = item.detachedGridPosition {
                sourcePlacement = .detached(detachedGridPosition)
            } else if let sourceSlotIndex = baseFlowSlotIndexByCardID[item.cardID] ?? item.slotIndex {
                sourcePlacement = .flow(sourceSlotIndex)
            } else {
                return
            }
            let scrollOrigin = scrollController.viewportOrigin
            let pointerInViewport = CGPoint(
                x: value.location.x - scrollOrigin.x,
                y: value.location.y - scrollOrigin.y
            )
            let sourceTarget = sourceTarget(for: movingItems, primaryItem: item)
            cardDragState = IndexBoardSurfaceCardDragState(
                cardID: item.cardID,
                movingCardIDs: movingCardIDs,
                sourcePlacement: sourcePlacement,
                sourceLaneParentID: item.laneParentID,
                sourceTarget: sourceTarget,
                initialFrame: initialFrame,
                pointerOffset: CGSize(
                    width: value.startLocation.x - initialFrame.minX,
                    height: value.startLocation.y - initialFrame.minY
                ),
                pointerInViewport: pointerInViewport,
                dropPlacement: sourcePlacement
            )
        }

        guard var drag = cardDragState, drag.cardID == item.cardID else { return }
        drag.pointerInViewport = CGPoint(
            x: value.location.x - scrollController.viewportOrigin.x,
            y: value.location.y - scrollController.viewportOrigin.y
        )
        drag.dropPlacement = resolvedDropPlacement(for: drag)
        cardDragState = drag
        presentationSurfaceProjection = resolvedPresentationSurfaceProjection(for: drag)
    }

    private func handleCardDragEnded(_ item: BoardSurfaceItem, value: DragGesture.Value) {
        handleCardDragChanged(item, value: value)
        guard let drag = cardDragState, drag.cardID == item.cardID else { return }
        let target = resolvedDropTarget(for: drag)
        let shouldCommit = target != drag.sourceTarget
        flushDeferredViewportPersistence()
        withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.92)) {
            presentationSurfaceProjection = shouldCommit
                ? resolvedPresentationSurfaceProjection(for: drag)
                : nil
            cardDragState = nil
        }
        guard shouldCommit else { return }
        if drag.movingCardIDs.count > 1 {
            onCardMoveSelection(drag.movingCardIDs, item.cardID, target)
        } else {
            onCardMove(item.cardID, target)
        }
    }

    private func handleAutoScrollTick() {
        guard let drag = cardDragState else { return }
        let delta = CGPoint(
            x: autoScrollAxisDelta(
                position: drag.pointerInViewport.x,
                viewportLength: scrollController.viewportSize.width
            ),
            y: autoScrollAxisDelta(
                position: drag.pointerInViewport.y,
                viewportLength: scrollController.viewportSize.height
            )
        )
        guard delta != .zero else { return }
        scrollController.scroll(by: delta)
        recalculateDropPlacement()
    }

    private func recalculateDropPlacement() {
        guard var drag = cardDragState else { return }
        drag.dropPlacement = resolvedDropPlacement(for: drag)
        cardDragState = drag
    }

    private func resolvedDropPlacement(for drag: IndexBoardSurfaceCardDragState) -> IndexBoardSurfaceDropPlacement {
        let pointer = drag.pointerInContent(scrollOrigin: scrollController.viewportOrigin)
        let visibleItems = flowItems.filter { !drag.movingCardIDSet.contains($0.cardID) }
        let dragCardFrame = resolvedDragCardFrame(for: drag)
        let dragCardCenter = CGPoint(x: dragCardFrame.midX, y: dragCardFrame.midY)
        let usesFlowHysteresis = {
            if case .flow = drag.dropPlacement {
                return true
            }
            return false
        }()

        if let flowInteractionRect = resolvedFlowInteractionRect(
            slotCount: visibleItems.count,
            usesVerticalHysteresis: usesFlowHysteresis
        ),
           flowInteractionRect.contains(dragCardCenter) {
            return .flow(
                resolvedFlowDropSlotIndex(
                    for: dragCardCenter,
                    slotCount: visibleItems.count
                )
            )
        }

        if case .flow(let currentIndex) = drag.dropPlacement {
            let currentRect = resolvedCardFrame(
                for: resolvedFlowSlotRect(for: currentIndex),
                reservesLaneSpacer: true
            ).insetBy(dx: -42, dy: -54)
            if currentRect.contains(dragCardCenter) {
                return .flow(currentIndex)
            }
        }

        return .detached(resolvedDetachedGridPosition(for: pointer, excluding: drag.movingCardIDSet))
    }

    private func resolvedDropTarget(for drag: IndexBoardSurfaceCardDragState) -> IndexBoardCardDropTarget {
        switch drag.dropPlacement {
        case .flow(let rawDropSlotIndex):
            let visibleItems = flowItems.filter { !drag.movingCardIDSet.contains($0.cardID) }
            let safeDropSlotIndex = min(max(0, rawDropSlotIndex), visibleItems.count)

            if case .flow(let sourceSlotIndex) = drag.sourcePlacement,
               safeDropSlotIndex == sourceSlotIndex {
                return drag.sourceTarget
            }

            let targetLaneParentID = resolvedPlaceholderLaneParentID(
                safeDropSlotIndex: safeDropSlotIndex,
                visibleItems: visibleItems,
                drag: drag
            ) ?? drag.sourceLaneParentID

            let insertionIndex = visibleItems.prefix(safeDropSlotIndex).filter {
                $0.laneParentID == targetLaneParentID
            }.count
            let previousCardID = safeDropSlotIndex > 0
                ? visibleItems[safeDropSlotIndex - 1].cardID
                : nil
            let nextCardID = safeDropSlotIndex < visibleItems.count
                ? visibleItems[safeDropSlotIndex].cardID
                : nil

            return IndexBoardCardDropTarget(
                groupID: legacyGroupID(for: targetLaneParentID),
                insertionIndex: insertionIndex,
                laneParentID: targetLaneParentID,
                previousCardID: previousCardID,
                nextCardID: nextCardID,
                preferredColumnCount: preferredColumns
            )
        case .detached(let detachedGridPosition):
            if drag.sourceTarget.detachedGridPosition == detachedGridPosition {
                return drag.sourceTarget
            }

            return IndexBoardCardDropTarget(
                groupID: legacyGroupID(for: drag.sourceLaneParentID),
                insertionIndex: drag.sourceTarget.insertionIndex,
                laneParentID: drag.sourceLaneParentID,
                detachedGridPosition: detachedGridPosition,
                preferredColumnCount: preferredColumns
            )
        }
    }

    private func resolvedPlaceholderLaneParentID(
        safeDropSlotIndex: Int,
        visibleItems: [BoardSurfaceItem],
        drag: IndexBoardSurfaceCardDragState
    ) -> UUID? {
        if case .flow(let sourceSlotIndex) = drag.sourcePlacement,
           safeDropSlotIndex == sourceSlotIndex {
            return drag.sourceLaneParentID
        }
        let nextLaneParentID =
            safeDropSlotIndex < visibleItems.count
            ? visibleItems[safeDropSlotIndex].laneParentID
            : nil
        let previousLaneParentID =
            safeDropSlotIndex > 0
            ? visibleItems[safeDropSlotIndex - 1].laneParentID
            : nil

        if let nextLaneParentID,
           let previousLaneParentID,
           nextLaneParentID == previousLaneParentID {
            return nextLaneParentID
        }
        if let nextLaneParentID {
            return nextLaneParentID
        }
        if let previousLaneParentID {
            return previousLaneParentID
        }
        return drag.sourceLaneParentID
    }

    private func resolvedLaneMoveContext(for lane: BoardSurfaceLane) -> (
        groupID: IndexBoardGroupID,
        targetBackwardIndex: Int?,
        targetForwardIndex: Int?
    )? {
        let key = laneKey(for: lane.parentCardID)
        guard let group = groupByLaneKey[key],
              group.parentCard != nil,
              !group.isTempGroup,
              let sourceIndex = projection.groups.firstIndex(where: { $0.id == group.id }),
              let movablePosition = movableGroupIndices.firstIndex(of: sourceIndex) else {
            return nil
        }

        let targetBackwardIndex =
            movablePosition > 0
            ? movableGroupIndices[movablePosition - 1]
            : nil
        let targetForwardIndex =
            movablePosition < movableGroupIndices.count - 1
            ? movableGroupIndices[movablePosition + 1]
            : nil

        return (group.id, targetBackwardIndex, targetForwardIndex)
    }

    private func resolvedMovingItems(for draggedItem: BoardSurfaceItem) -> [BoardSurfaceItem] {
        guard selectedCardIDs.count > 1,
              selectedCardIDs.contains(draggedItem.cardID) else {
            return [draggedItem]
        }

        let selectedItems = orderedItems.filter { selectedCardIDs.contains($0.cardID) }
        return selectedItems.isEmpty ? [draggedItem] : selectedItems
    }

    private func sourceTarget(for movingItems: [BoardSurfaceItem], primaryItem: BoardSurfaceItem) -> IndexBoardCardDropTarget {
        guard movingItems.count > 1 else {
            return sourceTarget(for: primaryItem)
        }

        let movingCardIDs = Set(movingItems.map(\.cardID))
        let flowMovingItems = movingItems
            .filter { !$0.isDetached }
            .sorted { ($0.slotIndex ?? .max) < ($1.slotIndex ?? .max) }

        if let firstFlowItem = flowMovingItems.first {
            let lastFlowSlotIndex = flowMovingItems.last?.slotIndex ?? firstFlowItem.slotIndex ?? 0
            let firstFlowSlotIndex = firstFlowItem.slotIndex ?? 0
            let visibleItems = flowItems.filter { !movingCardIDs.contains($0.cardID) }
            let insertionIndex = visibleItems.filter {
                $0.laneParentID == firstFlowItem.laneParentID &&
                ($0.slotIndex ?? .max) < firstFlowSlotIndex
            }.count
            let previousCardID = visibleItems.last(where: { ($0.slotIndex ?? .min) < firstFlowSlotIndex })?.cardID
            let nextCardID = visibleItems.first(where: { ($0.slotIndex ?? .max) > lastFlowSlotIndex })?.cardID

            return IndexBoardCardDropTarget(
                groupID: legacyGroupID(for: firstFlowItem.laneParentID),
                insertionIndex: insertionIndex,
                laneParentID: firstFlowItem.laneParentID,
                previousCardID: previousCardID,
                nextCardID: nextCardID,
                preferredColumnCount: preferredColumns
            )
        }

        return sourceTarget(for: primaryItem)
    }

    private func sourceTarget(for item: BoardSurfaceItem) -> IndexBoardCardDropTarget {
        if let detachedGridPosition = item.detachedGridPosition {
            return IndexBoardCardDropTarget(
                groupID: legacyGroupID(for: item.laneParentID),
                insertionIndex: 0,
                laneParentID: item.laneParentID,
                detachedGridPosition: detachedGridPosition,
                preferredColumnCount: preferredColumns
            )
        }

        let flowOrderedItems = flowItems
        let itemSlotIndex = item.slotIndex ?? 0
        let insertionIndex = flowOrderedItems.prefix { ($0.slotIndex ?? .max) < itemSlotIndex }.filter {
            $0.laneParentID == item.laneParentID
        }.count
        let previousCardID = flowOrderedItems.last(where: { ($0.slotIndex ?? .min) < itemSlotIndex })?.cardID
        let nextCardID = flowOrderedItems.first(where: { ($0.slotIndex ?? .max) > itemSlotIndex })?.cardID
        return IndexBoardCardDropTarget(
            groupID: legacyGroupID(for: item.laneParentID),
            insertionIndex: insertionIndex,
            laneParentID: item.laneParentID,
            previousCardID: previousCardID,
            nextCardID: nextCardID,
            preferredColumnCount: preferredColumns
        )
    }

    private func handleMarqueeSelectionChanged(_ value: DragGesture.Value) {
        guard isInteractionEnabled, !isDragging else { return }

        let selectionRect = normalizedSelectionRect(
            from: value.startLocation,
            to: value.location
        )
        let nextSelectedCardIDs = resolvedSelectedCardIDs(in: selectionRect)

        if var selectionDragState {
            selectionDragState.currentPoint = value.location
            if selectionDragState.selectedCardIDs != nextSelectedCardIDs {
                selectionDragState.selectedCardIDs = nextSelectedCardIDs
                onMarqueeSelectionChange(nextSelectedCardIDs)
            }
            self.selectionDragState = selectionDragState
        } else {
            selectionDragState = IndexBoardSurfaceSelectionDragState(
                startPoint: value.startLocation,
                currentPoint: value.location,
                selectedCardIDs: nextSelectedCardIDs
            )
            onMarqueeSelectionChange(nextSelectedCardIDs)
        }
    }

    private func handleMarqueeSelectionEnded(_ value: DragGesture.Value) {
        guard isInteractionEnabled else {
            selectionDragState = nil
            return
        }

        handleMarqueeSelectionChanged(value)
        selectionDragState = nil
    }

    private func legacyGroupID(for laneParentID: UUID?) -> IndexBoardGroupID {
        if let laneParentID {
            return .parent(laneParentID)
        }
        return .root
    }

    private func settlePresentationProjection(with liveProjection: BoardSurfaceProjection) {
        guard cardDragState == nil,
              let presentationSurfaceProjection else { return }
        guard presentationSurfaceProjection.surfaceItems == liveProjection.surfaceItems else { return }
        withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.92)) {
            self.presentationSurfaceProjection = nil
        }
    }

    private func resolvedPresentationSurfaceProjection(
        for drag: IndexBoardSurfaceCardDragState
    ) -> BoardSurfaceProjection {
        let baseItems = surfaceProjection.surfaceItems.sorted(by: indexBoardSurfaceItemSort)
        let movingIDs = drag.movingCardIDSet
        let movingItemsByCardID = Dictionary(uniqueKeysWithValues: baseItems.compactMap { item -> (UUID, BoardSurfaceItem)? in
            movingIDs.contains(item.cardID) ? (item.cardID, item) : nil
        })
        let movingItems = drag.movingCardIDs.compactMap { movingItemsByCardID[$0] }
        let stationaryFlowItems = baseItems
            .filter { !movingIDs.contains($0.cardID) && !$0.isDetached }
            .sorted { ($0.slotIndex ?? .max) < ($1.slotIndex ?? .max) }
        let stationaryDetachedItems = baseItems.filter { !movingIDs.contains($0.cardID) && $0.isDetached }

        let resolvedItems: [BoardSurfaceItem]
        switch drag.dropPlacement {
        case .flow(let rawDropSlotIndex):
            let target = resolvedDropTarget(for: drag)
            let safeDropSlotIndex = min(max(0, rawDropSlotIndex), stationaryFlowItems.count)
            let laneParentID = target.laneParentID ?? drag.sourceLaneParentID
            let laneIndex = resolvedLaneIndex(
                for: laneParentID,
                fallback: movingItems.first?.laneIndex ?? 0
            )
            let insertedMovingItems = movingItems.map { item in
                BoardSurfaceItem(
                    cardID: item.cardID,
                    laneParentID: laneParentID,
                    laneIndex: laneIndex,
                    slotIndex: nil,
                    detachedGridPosition: nil
                )
            }

            var flowItems = stationaryFlowItems
            flowItems.insert(contentsOf: insertedMovingItems, at: safeDropSlotIndex)
            let normalizedFlowItems = flowItems.enumerated().map { index, item in
                BoardSurfaceItem(
                    cardID: item.cardID,
                    laneParentID: item.laneParentID,
                    laneIndex: resolvedLaneIndex(for: item.laneParentID, fallback: item.laneIndex),
                    slotIndex: index,
                    detachedGridPosition: nil
                )
            }
            resolvedItems = normalizedFlowItems + stationaryDetachedItems
        case .detached(let startPosition):
            let normalizedFlowItems = stationaryFlowItems.enumerated().map { index, item in
                BoardSurfaceItem(
                    cardID: item.cardID,
                    laneParentID: item.laneParentID,
                    laneIndex: item.laneIndex,
                    slotIndex: index,
                    detachedGridPosition: nil
                )
            }
            let occupiedPositions = Set(
                normalizedFlowItems.compactMap { item -> IndexBoardGridPosition? in
                    guard let slotIndex = item.slotIndex else { return nil }
                    return resolvedFlowGridPosition(for: slotIndex)
                } +
                stationaryDetachedItems.compactMap(\.detachedGridPosition)
            )
            let detachedPositions = resolvedDetachedSelectionPreviewPositions(
                count: movingItems.count,
                start: startPosition,
                occupied: occupiedPositions
            )
            let detachedItems = zip(movingItems, detachedPositions).map { item, position in
                BoardSurfaceItem(
                    cardID: item.cardID,
                    laneParentID: item.laneParentID,
                    laneIndex: item.laneIndex,
                    slotIndex: nil,
                    detachedGridPosition: position
                )
            }
            resolvedItems = normalizedFlowItems + stationaryDetachedItems + detachedItems
        }

        return BoardSurfaceProjection(
            source: surfaceProjection.source,
            lanes: surfaceProjection.lanes,
            surfaceItems: resolvedItems.sorted(by: indexBoardSurfaceItemSort),
            orderedCardIDs: resolvedItems
                .sorted(by: indexBoardSurfaceItemSort)
                .map(\.cardID)
        )
    }

    private func resolvedLaneIndex(for laneParentID: UUID?, fallback: Int) -> Int {
        surfaceProjection.lanes.first(where: { $0.parentCardID == laneParentID })?.laneIndex ?? fallback
    }

    private func resolvedDetachedSelectionPreviewPositions(
        count: Int,
        start: IndexBoardGridPosition,
        occupied: Set<IndexBoardGridPosition>
    ) -> [IndexBoardGridPosition] {
        guard count > 0 else { return [] }
        var positions: [IndexBoardGridPosition] = []
        positions.reserveCapacity(count)
        var taken = occupied
        var nextColumn = start.column

        while positions.count < count {
            let candidate = IndexBoardGridPosition(column: nextColumn, row: start.row)
            if !taken.contains(candidate) {
                positions.append(candidate)
                taken.insert(candidate)
            }
            nextColumn += 1
        }

        return positions
    }

    private func resolvedInitialColumnCount() -> Int {
        let availableWidth = max(
            IndexBoardMetrics.cardSize.width,
            canvasSize.width - (IndexBoardMetrics.boardHorizontalPadding * 2)
        )
        let slotWidth = IndexBoardMetrics.cardSize.width + IndexBoardMetrics.cardSpacing
        let fittedColumns = max(1, Int((availableWidth + IndexBoardMetrics.cardSpacing) / slotWidth))
        return min(max(1, orderedItems.count), fittedColumns)
    }

    private func dragPlaceholderFrames(for drag: IndexBoardSurfaceCardDragState) -> [CGRect] {
        switch drag.dropPlacement {
        case .flow(let dropSlotIndex):
            if case .flow(let sourceSlotIndex) = drag.sourcePlacement,
               sourceSlotIndex == dropSlotIndex {
                return []
            }
            let slotCount = max(1, drag.movingCardIDs.count)
            return (0..<slotCount).map { offset in
                resolvedCardFrame(
                    for: resolvedFlowSlotRect(for: dropSlotIndex + offset),
                    reservesLaneSpacer: true
                )
            }
        case .detached(let gridPosition):
            if drag.sourceTarget.detachedGridPosition == gridPosition {
                return []
            }
            return [
                resolvedCardFrame(
                    for: resolvedGridSlotRect(for: gridPosition),
                    reservesLaneSpacer: false
                )
            ]
        }
    }

    private func resolvedOverlayCardIDs(for drag: IndexBoardSurfaceCardDragState) -> [UUID] {
        let supportingIDs = drag.movingCardIDs.filter { $0 != drag.cardID }
        let trailingSupport = Array(supportingIDs.suffix(3))
        return trailingSupport + [drag.cardID]
    }

    private func resolvedSelectedCardIDs(in selectionRect: CGRect) -> Set<UUID> {
        Set(
            itemByCardID.compactMap { cardID, item in
                guard let slotFrame = cardFrameByID[cardID] else { return nil }
                let cardFrame = resolvedCardFrame(
                    for: slotFrame,
                    reservesLaneSpacer: !item.isDetached
                )
                return cardFrame.intersects(selectionRect) ? cardID : nil
            }
        )
    }

    private func resolvedRenderedFrame(for entry: IndexBoardSurfaceRenderedEntry) -> CGRect? {
        switch entry {
        case .live(let item):
            return resolvedRenderedFrame(for: item)
        case .placeholder:
            return nil
        }
    }

    private func resolvedRenderedFrame(for item: BoardSurfaceItem) -> CGRect? {
        guard let gridPosition = resolvedVisualGridPosition(for: item) else { return nil }
        return resolvedGridSlotRect(for: gridPosition)
    }

    private func resolvedVisualGridPosition(for item: BoardSurfaceItem) -> IndexBoardGridPosition? {
        if cardDragState?.movingCardIDSet.contains(item.cardID) == true {
            switch item.detachedGridPosition {
            case .some(let detachedGridPosition):
                return detachedGridPosition
            case .none:
                if let slotIndex = item.slotIndex {
                    return resolvedFlowGridPosition(for: slotIndex)
                }
            }
        }

        if let detachedGridPosition = item.detachedGridPosition {
            return detachedGridPosition
        }

        guard let slotIndex = displayedFlowSlotIndexByCardID[item.cardID] ?? item.slotIndex else {
            return nil
        }
        return resolvedFlowGridPosition(for: slotIndex)
    }

    private func resolvedFlowGridPosition(for slotIndex: Int) -> IndexBoardGridPosition {
        let safeIndex = max(0, slotIndex)
        return IndexBoardGridPosition(
            column: safeIndex % max(1, preferredColumns),
            row: safeIndex / max(1, preferredColumns)
        )
    }

    private func resolvedFlowSlotRect(for slotIndex: Int) -> CGRect {
        resolvedGridSlotRect(for: resolvedFlowGridPosition(for: slotIndex))
    }

    private func resolvedGridSlotRect(for gridPosition: IndexBoardGridPosition) -> CGRect {
        let normalizedColumn = gridPosition.column - logicalGridBounds.minColumn
        let normalizedRow = gridPosition.row - logicalGridBounds.minRow
        return CGRect(
            x: surfaceHorizontalInset + (CGFloat(normalizedColumn) * (slotSize.width + IndexBoardMetrics.cardSpacing)),
            y: surfaceVerticalInset + (CGFloat(normalizedRow) * (slotSize.height + IndexBoardSurfacePhaseConstants.lineSpacing)),
            width: slotSize.width,
            height: slotSize.height
        )
    }

    private func resolvedCardFrame(for slotFrame: CGRect, reservesLaneSpacer: Bool) -> CGRect {
        CGRect(
            x: slotFrame.minX,
            y: slotFrame.minY + (reservesLaneSpacer ? IndexBoardSurfacePhaseConstants.laneChipHeight + IndexBoardSurfacePhaseConstants.laneChipSpacing : 0),
            width: IndexBoardMetrics.cardSize.width,
            height: IndexBoardMetrics.cardSize.height
        )
    }

    private func resolvedDetachedGridPosition(for point: CGPoint, excluding excludedCardIDs: Set<UUID>) -> IndexBoardGridPosition {
        let candidate = resolvedNearestGridPosition(for: point)
        let occupiedPositions = Set(
            occupiedGridPositionByCardID.compactMap { entry -> IndexBoardGridPosition? in
                excludedCardIDs.contains(entry.key) ? nil : entry.value
            }
        )
        guard occupiedPositions.contains(candidate) else { return candidate }

        let maxRadius = max(logicalGridBounds.columnCount, logicalGridBounds.rowCount)
        for radius in 1...maxRadius {
            var candidates: [IndexBoardGridPosition] = []
            for row in (candidate.row - radius)...(candidate.row + radius) {
                for column in (candidate.column - radius)...(candidate.column + radius) {
                    let rowDelta = abs(row - candidate.row)
                    let columnDelta = abs(column - candidate.column)
                    guard max(rowDelta, columnDelta) == radius else { continue }
                    guard row >= logicalGridBounds.minRow,
                          row <= logicalGridBounds.maxRow,
                          column >= logicalGridBounds.minColumn,
                          column <= logicalGridBounds.maxColumn else {
                        continue
                    }
                    candidates.append(IndexBoardGridPosition(column: column, row: row))
                }
            }

            let nearest = candidates.sorted { lhs, rhs in
                let lhsDistance = abs(lhs.row - candidate.row) + abs(lhs.column - candidate.column)
                let rhsDistance = abs(rhs.row - candidate.row) + abs(rhs.column - candidate.column)
                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }
                if lhs.row != rhs.row {
                    return lhs.row < rhs.row
                }
                return lhs.column < rhs.column
            }

            if let resolved = nearest.first(where: { !occupiedPositions.contains($0) }) {
                return resolved
            }
        }

        return candidate
    }

    private func resolvedDragCardFrame(for drag: IndexBoardSurfaceCardDragState) -> CGRect {
        CGRect(
            origin: drag.overlayOrigin(scrollOrigin: scrollController.viewportOrigin),
            size: IndexBoardMetrics.cardSize
        )
    }

    private func resolvedFlowInteractionRect(slotCount: Int, usesVerticalHysteresis: Bool) -> CGRect? {
        let safeSlotCount = max(1, slotCount + 1)
        let cardFrames = (0..<safeSlotCount).map {
            resolvedCardFrame(
                for: resolvedFlowSlotRect(for: $0),
                reservesLaneSpacer: true
            )
        }
        guard let firstFrame = cardFrames.first else { return nil }
        let union = cardFrames.dropFirst().reduce(firstFrame) { partial, frame in
            partial.union(frame)
        }
        return union.insetBy(
            dx: -IndexBoardSurfacePhaseConstants.flowInteractionHorizontalInset,
            dy: -(usesVerticalHysteresis
                ? IndexBoardSurfacePhaseConstants.flowInteractionVerticalHysteresis
                : IndexBoardSurfacePhaseConstants.flowInteractionVerticalInset)
        )
    }

    private func resolvedFlowDropSlotIndex(for point: CGPoint, slotCount: Int) -> Int {
        let safeSlotCount = max(1, slotCount + 1)
        var bestIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for slotIndex in 0..<safeSlotCount {
            let frame = resolvedCardFrame(
                for: resolvedFlowSlotRect(for: slotIndex),
                reservesLaneSpacer: true
            )
            let dx = point.x - frame.midX
            let dy = point.y - frame.midY
            let distance = (dx * dx) + (dy * dy)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = slotIndex
            }
        }

        return min(max(0, bestIndex), slotCount)
    }

    private func resolvedNearestGridPosition(for point: CGPoint) -> IndexBoardGridPosition {
        let columnStep = slotSize.width + IndexBoardMetrics.cardSpacing
        let rowStep = slotSize.height + IndexBoardSurfacePhaseConstants.lineSpacing
        let rawColumn = Int(((point.x - surfaceHorizontalInset - (slotSize.width / 2)) / columnStep).rounded())
        let rawRow = Int(((point.y - surfaceVerticalInset - (slotSize.height / 2)) / rowStep).rounded())
        let clampedColumn = min(max(0, rawColumn), logicalGridBounds.columnCount - 1)
        let clampedRow = min(max(0, rawRow), logicalGridBounds.rowCount - 1)
        return IndexBoardGridPosition(
            column: logicalGridBounds.minColumn + clampedColumn,
            row: logicalGridBounds.minRow + clampedRow
        )
    }

    private func resolvedLaneTintColor(for lane: BoardSurfaceLane?) -> Color {
        if let lane, lane.isTempLane {
            return Color.orange.opacity(theme.usesDarkAppearance ? 0.88 : 0.82)
        }
        if let token = lane?.colorToken,
           let rgb = parseHexRGB(token) {
            return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
        }
        return theme.groupBorder
    }

    private func autoScrollAxisDelta(position: CGFloat, viewportLength: CGFloat) -> CGFloat {
        guard viewportLength > 0 else { return 0 }
        let edge = IndexBoardSurfacePhaseConstants.autoScrollEdgeInset
        if position < edge {
            let progress = max(0, min(1, (edge - position) / edge))
            return -IndexBoardSurfacePhaseConstants.maxAutoScrollStep * progress
        }
        if position > viewportLength - edge {
            let progress = max(0, min(1, (position - (viewportLength - edge)) / edge))
            return IndexBoardSurfacePhaseConstants.maxAutoScrollStep * progress
        }
        return 0
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(0, max(rect.minX - point.x, point.x - rect.maxX))
        let dy = max(0, max(rect.minY - point.y, point.y - rect.maxY))
        return sqrt((dx * dx) + (dy * dy))
    }

    private func normalizedSelectionRect(from startPoint: CGPoint, to endPoint: CGPoint) -> CGRect {
        CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
    }

    private func attemptPendingCardReveal() {
        guard let pendingRevealCardID,
              let frame = cardFrameByID[pendingRevealCardID] else {
            return
        }
        scrollController.ensureVisible(frame)
        self.pendingRevealCardID = nil
    }

    private func laneKey(for parentID: UUID?) -> String {
        parentID?.uuidString ?? "root"
    }

    private func scheduleScrollOffsetPersistence(_ offset: CGPoint) {
        let resolvedOffset = CGPoint(
            x: max(0, offset.x),
            y: max(0, offset.y)
        )
        guard abs(resolvedOffset.x - scrollOffset.x) > 0.5 || abs(resolvedOffset.y - scrollOffset.y) > 0.5 else {
            return
        }
        pendingScrollPersistenceWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            onScrollOffsetChange(resolvedOffset)
        }
        pendingScrollPersistenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    private func scheduleZoomPersistence(_ scale: CGFloat) {
        let resolvedScale = min(max(scale, IndexBoardZoom.minScale), IndexBoardZoom.maxScale)
        pendingZoomPersistenceWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            onZoomScaleChange(resolvedScale)
        }
        pendingZoomPersistenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: workItem)
    }

    private func cancelDeferredViewportPersistence() {
        pendingScrollPersistenceWorkItem?.cancel()
        pendingScrollPersistenceWorkItem = nil
        pendingZoomPersistenceWorkItem?.cancel()
        pendingZoomPersistenceWorkItem = nil
    }

    private func flushDeferredViewportPersistence() {
        cancelDeferredViewportPersistence()
        onScrollOffsetChange(scrollController.viewportOrigin)
        onZoomScaleChange(scrollController.magnification)
    }
}
