import SwiftUI
import AppKit
import Combine

struct IndexBoardCardDropTarget: Equatable {
    let groupID: IndexBoardGroupID
    let insertionIndex: Int
    let laneParentID: UUID?
    let previousCardID: UUID?
    let nextCardID: UUID?
    let previousTempMember: IndexBoardTempStripMember?
    let nextTempMember: IndexBoardTempStripMember?
    let detachedGridPosition: IndexBoardGridPosition?
    let preferredColumnCount: Int?

    init(
        groupID: IndexBoardGroupID,
        insertionIndex: Int,
        laneParentID: UUID? = nil,
        previousCardID: UUID? = nil,
        nextCardID: UUID? = nil,
        previousTempMember: IndexBoardTempStripMember? = nil,
        nextTempMember: IndexBoardTempStripMember? = nil,
        detachedGridPosition: IndexBoardGridPosition? = nil,
        preferredColumnCount: Int? = nil
    ) {
        self.groupID = groupID
        self.insertionIndex = insertionIndex
        self.laneParentID = laneParentID
        self.previousCardID = previousCardID
        self.nextCardID = nextCardID
        self.previousTempMember = previousTempMember
        self.nextTempMember = nextTempMember
        self.detachedGridPosition = detachedGridPosition
        self.preferredColumnCount = preferredColumnCount
    }

    var isTempStripTarget: Bool {
        detachedGridPosition != nil || previousTempMember != nil || nextTempMember != nil
    }
}

private struct IndexBoardResolvedGroupMoveContext {
    let previousGroup: IndexBoardGroupProjection?
    let nextGroup: IndexBoardGroupProjection?

    init(previousGroup: IndexBoardGroupProjection?, nextGroup: IndexBoardGroupProjection?) {
        self.previousGroup = previousGroup
        self.nextGroup = nextGroup
    }

    init(
        groups projection: IndexBoardProjection,
        movingGroupID: IndexBoardGroupID,
        targetIndex: Int
    ) {
        let visibleGroups = projection.groups.filter { $0.id != movingGroupID && !$0.isTempGroup && $0.parentCard != nil }
        let safeTargetIndex = min(max(0, targetIndex), visibleGroups.count)
        self.previousGroup = safeTargetIndex > 0 ? visibleGroups[safeTargetIndex - 1] : nil
        self.nextGroup = safeTargetIndex < visibleGroups.count ? visibleGroups[safeTargetIndex] : nil
    }
}

private enum IndexBoardPhaseTwoConstants {
    static let canvasCoordinateSpaceName = "IndexBoardCanvasCoordinateSpace"
    static let estimatedGroupHeaderHeight: CGFloat = 84
    static let autoScrollEdgeInset: CGFloat = 80
    static let maxAutoScrollStep: CGFloat = 22
    static let emptyGroupDropWellHeight: CGFloat = IndexBoardMetrics.cardSize.height
}

private struct IndexBoardCardDisplayItem: Identifiable {
    let id: String
    let card: SceneCard?

    static func live(_ card: SceneCard) -> IndexBoardCardDisplayItem {
        IndexBoardCardDisplayItem(id: card.id.uuidString, card: card)
    }

    static func placeholder(cardID: UUID) -> IndexBoardCardDisplayItem {
        IndexBoardCardDisplayItem(id: "placeholder-\(cardID.uuidString)", card: nil)
    }
}

private struct IndexBoardRenderedGroup: Identifiable {
    let id: String
    let group: IndexBoardGroupProjection?
    let placeholderGroupID: IndexBoardGroupID?
    let placeholderHeight: CGFloat?
    let cardItems: [IndexBoardCardDisplayItem]

    static func live(
        _ group: IndexBoardGroupProjection,
        cardItems: [IndexBoardCardDisplayItem]
    ) -> IndexBoardRenderedGroup {
        IndexBoardRenderedGroup(
            id: group.id.id,
            group: group,
            placeholderGroupID: nil,
            placeholderHeight: nil,
            cardItems: cardItems
        )
    }

    static func placeholder(
        groupID: IndexBoardGroupID,
        height: CGFloat
    ) -> IndexBoardRenderedGroup {
        IndexBoardRenderedGroup(
            id: "placeholder-\(groupID.id)",
            group: nil,
            placeholderGroupID: groupID,
            placeholderHeight: height,
            cardItems: []
        )
    }
}

private struct IndexBoardCardDragState {
    let cardID: UUID
    let sourceGroupID: IndexBoardGroupID
    let sourceIndex: Int
    let initialFrame: CGRect
    let pointerOffset: CGSize
    var pointerInViewport: CGPoint
    var dropTarget: IndexBoardCardDropTarget

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

private struct IndexBoardGroupDragState {
    let groupID: IndexBoardGroupID
    let sourceIndex: Int
    let initialFrame: CGRect
    let pointerOffset: CGSize
    var pointerInViewport: CGPoint
    var targetIndex: Int

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

private struct IndexBoardCardFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct IndexBoardGroupFramePreferenceKey: PreferenceKey {
    static var defaultValue: [IndexBoardGroupID: CGRect] = [:]

    static func reduce(value: inout [IndexBoardGroupID: CGRect], nextValue: () -> [IndexBoardGroupID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

@MainActor
final class IndexBoardScrollController: ObservableObject {
    @Published private(set) var viewportOrigin: CGPoint = .zero
    @Published private(set) var viewportSize: CGSize = .zero
    @Published private(set) var documentSize: CGSize = .zero
    @Published private(set) var magnification: CGFloat = IndexBoardZoom.defaultScale

    fileprivate weak var scrollView: NSScrollView?

    func attach(scrollView: NSScrollView) {
        self.scrollView = scrollView
        refresh(from: scrollView)
    }

    func detach(matching matchingScrollView: NSScrollView? = nil) {
        guard matchingScrollView == nil || matchingScrollView === self.scrollView else { return }
        self.scrollView = nil
        viewportOrigin = .zero
        viewportSize = .zero
        documentSize = .zero
    }

    func refresh(from scrollView: NSScrollView) {
        guard scrollView === self.scrollView else { return }
        viewportOrigin = CGPoint(
            x: max(0, scrollView.contentView.bounds.origin.x),
            y: max(0, scrollView.contentView.bounds.origin.y)
        )
        viewportSize = scrollView.documentVisibleRect.size
        documentSize = scrollView.documentView?.bounds.size ?? .zero
        let rawMagnification = scrollView.allowsMagnification ? scrollView.magnification : IndexBoardZoom.defaultScale
        magnification = min(max(rawMagnification, IndexBoardZoom.minScale), IndexBoardZoom.maxScale)
    }

    func scroll(by delta: CGPoint) {
        guard let scrollView else { return }
        let visibleRect = scrollView.documentVisibleRect
        let maxX = max(0, documentSize.width - visibleRect.width)
        let maxY = max(0, documentSize.height - visibleRect.height)
        let targetX = CaretScrollCoordinator.resolvedHorizontalTargetX(
            visibleRect: visibleRect,
            targetX: visibleRect.origin.x + delta.x,
            minX: 0,
            maxX: maxX,
            snapToPixel: true
        )
        let targetY = CaretScrollCoordinator.resolvedVerticalTargetY(
            visibleRect: visibleRect,
            targetY: visibleRect.origin.y + delta.y,
            minY: 0,
            maxY: maxY,
            snapToPixel: true
        )
        guard abs(targetX - visibleRect.origin.x) > 0.5 || abs(targetY - visibleRect.origin.y) > 0.5 else {
            return
        }
        scrollView.contentView.setBoundsOrigin(NSPoint(x: targetX, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        refresh(from: scrollView)
    }

    func ensureVisible(_ rect: CGRect, padding: CGSize = CGSize(width: 36, height: 28)) {
        guard let scrollView else { return }
        let visibleRect = scrollView.documentVisibleRect
        let paddedRect = rect.insetBy(dx: -padding.width, dy: -padding.height)
        var delta = CGPoint.zero

        if paddedRect.minX < visibleRect.minX {
            delta.x = paddedRect.minX - visibleRect.minX
        } else if paddedRect.maxX > visibleRect.maxX {
            delta.x = paddedRect.maxX - visibleRect.maxX
        }

        if paddedRect.minY < visibleRect.minY {
            delta.y = paddedRect.minY - visibleRect.minY
        } else if paddedRect.maxY > visibleRect.maxY {
            delta.y = paddedRect.maxY - visibleRect.maxY
        }

        guard delta != .zero else { return }
        scroll(by: delta)
    }
}

struct IndexBoardScrollViewAccessor: NSViewRepresentable {
    let scrollController: IndexBoardScrollController
    let desiredMagnification: CGFloat
    let desiredViewportOrigin: CGPoint

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.attach(
            to: view,
            scrollController: scrollController,
            desiredMagnification: desiredMagnification,
            desiredViewportOrigin: desiredViewportOrigin
        )
    }

    final class Coordinator {
        private weak var scrollView: NSScrollView?
        private weak var observedDocumentView: NSView?
        private weak var scrollController: IndexBoardScrollController?
        private var contentBoundsObserver: NSObjectProtocol?
        private var documentFrameObserver: NSObjectProtocol?
        private var documentBoundsObserver: NSObjectProtocol?
        private var attachRetryWorkItem: DispatchWorkItem?

        deinit {
            detach()
        }

        func attach(
            to view: NSView,
            scrollController: IndexBoardScrollController,
            desiredMagnification: CGFloat,
            desiredViewportOrigin: CGPoint
        ) {
            self.scrollController = scrollController
            guard let resolvedScrollView = resolveScrollView(from: view) else {
                scheduleAttachRetry(
                    to: view,
                    scrollController: scrollController,
                    desiredMagnification: desiredMagnification,
                    desiredViewportOrigin: desiredViewportOrigin
                )
                return
            }

            attachRetryWorkItem?.cancel()
            attachRetryWorkItem = nil
            let documentChanged = observedDocumentView !== resolvedScrollView.documentView
            guard scrollView !== resolvedScrollView || documentChanged else {
                applyState(
                    to: resolvedScrollView,
                    desiredMagnification: desiredMagnification,
                    desiredViewportOrigin: desiredViewportOrigin,
                    forceViewportRestore: false
                )
                scrollController.refresh(from: resolvedScrollView)
                return
            }

            detach()
            self.scrollController = scrollController
            scrollView = resolvedScrollView
            installObservers(for: resolvedScrollView)
            applyState(
                to: resolvedScrollView,
                desiredMagnification: desiredMagnification,
                desiredViewportOrigin: desiredViewportOrigin,
                forceViewportRestore: true
            )
            scrollController.attach(scrollView: resolvedScrollView)
        }

        private func detach() {
            attachRetryWorkItem?.cancel()
            attachRetryWorkItem = nil
            if let contentBoundsObserver {
                NotificationCenter.default.removeObserver(contentBoundsObserver)
            }
            if let documentFrameObserver {
                NotificationCenter.default.removeObserver(documentFrameObserver)
            }
            if let documentBoundsObserver {
                NotificationCenter.default.removeObserver(documentBoundsObserver)
            }
            contentBoundsObserver = nil
            documentFrameObserver = nil
            documentBoundsObserver = nil
            observedDocumentView = nil
            if let scrollView {
                scrollController?.detach(matching: scrollView)
            }
            scrollView = nil
        }

        private func scheduleAttachRetry(
            to view: NSView,
            scrollController: IndexBoardScrollController,
            desiredMagnification: CGFloat,
            desiredViewportOrigin: CGPoint
        ) {
            guard attachRetryWorkItem == nil else { return }
            let workItem = DispatchWorkItem { [weak self, weak view] in
                guard let self, let view else { return }
                self.attachRetryWorkItem = nil
                self.attach(
                    to: view,
                    scrollController: scrollController,
                    desiredMagnification: desiredMagnification,
                    desiredViewportOrigin: desiredViewportOrigin
                )
            }
            attachRetryWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
        }

        private func applyState(
            to scrollView: NSScrollView,
            desiredMagnification: CGFloat,
            desiredViewportOrigin: CGPoint,
            forceViewportRestore: Bool
        ) {
            scrollView.allowsMagnification = true
            scrollView.minMagnification = IndexBoardZoom.minScale
            scrollView.maxMagnification = IndexBoardZoom.maxScale

            let clampedMagnification = min(max(desiredMagnification, IndexBoardZoom.minScale), IndexBoardZoom.maxScale)
            let currentMagnification = scrollView.magnification
            let didChangeMagnification = abs(currentMagnification - clampedMagnification) > 0.001
            if didChangeMagnification {
                let visibleRect = scrollView.documentVisibleRect
                let centerPoint = NSPoint(x: visibleRect.midX, y: visibleRect.midY)
                scrollView.setMagnification(clampedMagnification, centeredAt: centerPoint)
            }

            guard forceViewportRestore else { return }
            let visibleRect = scrollView.documentVisibleRect
            let documentBounds = scrollView.documentView?.bounds ?? .zero
            let maxX = max(0, documentBounds.width - visibleRect.width)
            let maxY = max(0, documentBounds.height - visibleRect.height)
            let resolvedOrigin = NSPoint(
                x: min(max(0, desiredViewportOrigin.x), maxX),
                y: min(max(0, desiredViewportOrigin.y), maxY)
            )
            let currentOrigin = scrollView.contentView.bounds.origin
            guard abs(currentOrigin.x - resolvedOrigin.x) > 0.5 || abs(currentOrigin.y - resolvedOrigin.y) > 0.5 else {
                return
            }
            scrollView.contentView.setBoundsOrigin(resolvedOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func installObservers(for scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            contentBoundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                Task { @MainActor [weak self, weak scrollView] in
                    guard let self, let scrollView else { return }
                    self.scrollController?.refresh(from: scrollView)
                }
            }

            if let documentView = scrollView.documentView {
                observedDocumentView = documentView
                documentView.postsFrameChangedNotifications = true
                documentView.postsBoundsChangedNotifications = true
                documentFrameObserver = NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: documentView,
                    queue: .main
                ) { [weak self, weak scrollView] _ in
                    Task { @MainActor [weak self, weak scrollView] in
                        guard let self, let scrollView else { return }
                        self.scrollController?.refresh(from: scrollView)
                    }
                }
                documentBoundsObserver = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: documentView,
                    queue: .main
                ) { [weak self, weak scrollView] _ in
                    Task { @MainActor [weak self, weak scrollView] in
                        guard let self, let scrollView else { return }
                        self.scrollController?.refresh(from: scrollView)
                    }
                }
            }
        }

        private func resolveScrollView(from view: NSView) -> NSScrollView? {
            var current: NSView? = view
            while let candidate = current {
                if let scrollView = candidate.enclosingScrollView {
                    return scrollView
                }
                current = candidate.superview
            }
            return nil
        }
    }
}

private struct IndexBoardCardPlaceholderTile: View {
    let theme: IndexBoardRenderTheme
    let accentOpacity: Double

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(theme.accentColor.opacity(accentOpacity * 0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        theme.accentColor.opacity(accentOpacity),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                    )
            )
            .frame(width: IndexBoardMetrics.cardSize.width, height: IndexBoardMetrics.cardSize.height)
    }
}

private struct IndexBoardGroupPlaceholderView: View {
    let theme: IndexBoardRenderTheme
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(theme.accentColor.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        theme.accentColor.opacity(0.72),
                        style: StrokeStyle(lineWidth: 2, dash: [10, 8])
                    )
            )
            .frame(width: IndexBoardMetrics.groupWidth, height: max(140, height))
    }
}

@MainActor
private struct IndexBoardInteractiveGroupView: View {
    let group: IndexBoardGroupProjection
    let cardItems: [IndexBoardCardDisplayItem]
    let theme: IndexBoardRenderTheme
    let selectedCardIDs: Set<UUID>
    let activeCardID: UUID?
    let summaryByCardID: [UUID: IndexBoardResolvedSummary]
    let showsBackByCardID: [UUID: Bool]
    let isInteractionEnabled: Bool
    let onCardTap: (SceneCard) -> Void
    let onCardOpen: (SceneCard) -> Void
    let onCardFaceToggle: (SceneCard) -> Void
    let onCardDragChanged: (SceneCard, DragGesture.Value) -> Void
    let onCardDragEnded: (SceneCard, DragGesture.Value) -> Void
    let onGroupDragChanged: ((DragGesture.Value) -> Void)?
    let onGroupDragEnded: ((DragGesture.Value) -> Void)?

    private var containsSelectedCard: Bool {
        group.childCards.contains { selectedCardIDs.contains($0.id) }
    }

    private var containsActiveCard: Bool {
        group.childCards.contains { $0.id == activeCardID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if cardItems.isEmpty {
                IndexBoardCardPlaceholderTile(theme: theme, accentOpacity: 0.28)
                    .padding(IndexBoardMetrics.groupInnerPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                IndexBoardCardGridLayout(
                    columns: 2,
                    spacing: IndexBoardMetrics.cardSpacing,
                    cardSize: IndexBoardMetrics.cardSize
                ) {
                    ForEach(cardItems) { item in
                        if let card = item.card {
                            IndexBoardCardTile(
                                card: card,
                                theme: theme,
                                isSelected: selectedCardIDs.contains(card.id),
                                isActive: activeCardID == card.id,
                                summary: summaryByCardID[card.id],
                                showsBack: showsBackByCardID[card.id] ?? false,
                                onTap: {
                                    guard isInteractionEnabled else { return }
                                    onCardTap(card)
                                },
                                onToggleFace: {
                                    guard isInteractionEnabled else { return }
                                    onCardFaceToggle(card)
                                },
                                onOpen: {
                                    guard isInteractionEnabled else { return }
                                    onCardOpen(card)
                                }
                            )
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: IndexBoardCardFramePreferenceKey.self,
                                        value: [
                                            card.id: proxy.frame(in: .named(IndexBoardPhaseTwoConstants.canvasCoordinateSpaceName))
                                        ]
                                    )
                                }
                            )
                            .gesture(
                                DragGesture(
                                    minimumDistance: 3,
                                    coordinateSpace: .named(IndexBoardPhaseTwoConstants.canvasCoordinateSpaceName)
                                )
                                .onChanged { value in
                                    guard isInteractionEnabled else { return }
                                    onCardDragChanged(card, value)
                                }
                                .onEnded { value in
                                    guard isInteractionEnabled else { return }
                                    onCardDragEnded(card, value)
                                }
                            )
                        } else {
                            IndexBoardCardPlaceholderTile(theme: theme, accentOpacity: 0.84)
                        }
                    }
                }
                .padding(IndexBoardMetrics.groupInnerPadding)
            }
        }
        .frame(width: IndexBoardMetrics.groupWidth, alignment: .topLeading)
        .background(theme.groupBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    containsActiveCard
                    ? theme.accentColor.opacity(0.92)
                    : (containsSelectedCard ? theme.accentColor.opacity(0.52) : theme.groupBorder),
                    lineWidth: containsActiveCard ? 2 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(theme.usesDarkAppearance ? 0.24 : 0.08), radius: 18, x: 0, y: 10)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: IndexBoardGroupFramePreferenceKey.self,
                    value: [
                        group.id: proxy.frame(in: .named(IndexBoardPhaseTwoConstants.canvasCoordinateSpaceName))
                    ]
                )
            }
        )
    }

    private var header: some View {
        let gesture = DragGesture(
            minimumDistance: 3,
            coordinateSpace: .named(IndexBoardPhaseTwoConstants.canvasCoordinateSpaceName)
        )
        .onChanged { value in
            guard isInteractionEnabled else { return }
            onGroupDragChanged?(value)
        }
        .onEnded { value in
            guard isInteractionEnabled else { return }
            onGroupDragEnded?(value)
        }

        return IndexBoardGroupHeaderView(
            group: group,
            theme: theme,
            containsActiveCard: containsActiveCard
        )
        .contentShape(Rectangle())
        .modifier(
            IndexBoardOptionalGestureModifier(
                isEnabled: onGroupDragChanged != nil && onGroupDragEnded != nil,
                gesture: gesture
            )
        )
    }
}

@MainActor
struct IndexBoardPhaseTwoView: View {
    let projection: IndexBoardProjection
    let sourceTitle: String
    let canvasSize: CGSize
    let theme: IndexBoardRenderTheme
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
    let onGroupMove: (IndexBoardGroupID, Int) -> Void

    @StateObject private var scrollController = IndexBoardScrollController()
    @State private var cardFrameByID: [UUID: CGRect] = [:]
    @State private var groupFrameByID: [IndexBoardGroupID: CGRect] = [:]
    @State private var cardDragState: IndexBoardCardDragState? = nil
    @State private var groupDragState: IndexBoardGroupDragState? = nil
    @State private var pendingRevealCardID: UUID? = nil
    @State private var pendingScrollPersistenceWorkItem: DispatchWorkItem? = nil
    @State private var pendingZoomPersistenceWorkItem: DispatchWorkItem? = nil

    private let autoScrollTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    private var zoomPercentText: String {
        "\(Int((zoomScale * 100).rounded()))%"
    }

    private var canvasContentWidth: CGFloat {
        let preferredColumns = projection.groups.count >= 2 ? 2 : 1
        let preferredWidth =
            (CGFloat(preferredColumns) * IndexBoardMetrics.groupWidth) +
            (CGFloat(max(0, preferredColumns - 1)) * IndexBoardMetrics.groupSpacing) +
            (IndexBoardMetrics.boardHorizontalPadding * 2)
        return max(canvasSize.width - 24, preferredWidth)
    }

    private var isDragging: Bool {
        cardDragState != nil || groupDragState != nil
    }

    private var renderedGroups: [IndexBoardRenderedGroup] {
        if let groupDragState {
            return renderedGroupsForGroupDrag(groupDragState)
        }
        if let cardDragState {
            return renderedGroupsForCardDrag(cardDragState)
        }
        return projection.groups.map { group in
            IndexBoardRenderedGroup.live(
                group,
                cardItems: group.childCards.map(IndexBoardCardDisplayItem.live(_:))
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if projection.groups.isEmpty {
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
        .onPreferenceChange(IndexBoardCardFramePreferenceKey.self) { frames in
            cardFrameByID = frames
            attemptPendingCardReveal()
        }
        .onPreferenceChange(IndexBoardGroupFramePreferenceKey.self) { frames in
            groupFrameByID = frames
        }
        .onReceive(autoScrollTimer) { _ in
            handleAutoScrollTick()
        }
        .onChange(of: scrollController.viewportOrigin) { _, newValue in
            if !isDragging {
                scheduleScrollOffsetPersistence(newValue)
            }
            recalculateActiveDropTarget()
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
        .onDisappear {
            flushDeferredViewportPersistence()
        }
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.84), value: cardDragAnimationKey)
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.84), value: groupDragAnimationKey)
    }

    private var boardScrollContent: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    guard isInteractionEnabled else { return }
                    onCreateTempCard()
                }

            renderedGroupLayout

            dragOverlay
        }
    }

    private var renderedGroupLayout: some View {
        IndexBoardWrapLayout(
            itemSpacing: IndexBoardMetrics.groupSpacing,
            lineSpacing: IndexBoardMetrics.groupLineSpacing
        ) {
            ForEach(Array(renderedGroups), id: \.id) { renderedGroup in
                renderedGroupView(renderedGroup)
            }
        }
        .padding(.horizontal, IndexBoardMetrics.boardHorizontalPadding)
        .padding(.vertical, IndexBoardMetrics.boardVerticalPadding)
        .frame(width: canvasContentWidth, alignment: .topLeading)
        .coordinateSpace(name: IndexBoardPhaseTwoConstants.canvasCoordinateSpaceName)
    }

    @ViewBuilder
    private func renderedGroupView(_ renderedGroup: IndexBoardRenderedGroup) -> some View {
        if let group = renderedGroup.group {
            IndexBoardInteractiveGroupView(
                group: group,
                cardItems: renderedGroup.cardItems,
                theme: theme,
                selectedCardIDs: selectedCardIDs,
                activeCardID: activeCardID,
                summaryByCardID: summaryByCardID,
                showsBackByCardID: showsBackByCardID,
                isInteractionEnabled: isInteractionEnabled && !isDragging,
                onCardTap: onCardTap,
                onCardOpen: onCardOpen,
                onCardFaceToggle: onCardFaceToggle,
                onCardDragChanged: handleCardDragChanged,
                onCardDragEnded: handleCardDragEnded,
                onGroupDragChanged: groupDragChangedHandler(for: group),
                onGroupDragEnded: groupDragEndedHandler(for: group)
            )
        } else if let placeholderGroupID = renderedGroup.placeholderGroupID {
            IndexBoardGroupPlaceholderView(
                theme: theme,
                height: renderedGroup.placeholderHeight ?? groupPlaceholderHeight(for: placeholderGroupID)
            )
        }
    }

    private func groupDragChangedHandler(
        for group: IndexBoardGroupProjection
    ) -> ((DragGesture.Value) -> Void)? {
        guard group.parentCard != nil, !group.isTempGroup, cardDragState == nil else { return nil }
        return { value in
            handleGroupDragChanged(for: group, value: value)
        }
    }

    private func groupDragEndedHandler(
        for group: IndexBoardGroupProjection
    ) -> ((DragGesture.Value) -> Void)? {
        guard group.parentCard != nil, !group.isTempGroup, cardDragState == nil else { return nil }
        return { value in
            handleGroupDragEnded(for: group, value: value)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(sourceTitle)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primaryTextColor)
                    .lineLimit(1)
                Text("Board View · 그룹 \(projection.groups.count) · 카드 \(projection.orderedCardIDs.count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.secondaryTextColor)
                Text("핀치 또는 Cmd +/- / Cmd 0")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.secondaryTextColor)
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
                .disabled(zoomScale <= IndexBoardZoom.minScale + 0.001)

                Button("100%") {
                    onZoomReset()
                }
                .buttonStyle(.bordered)
                .disabled(abs(zoomScale - IndexBoardZoom.defaultScale) < 0.001)

                Button(action: {
                    onZoomStep(IndexBoardZoom.step)
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.bordered)
                .disabled(zoomScale >= IndexBoardZoom.maxScale - 0.001)

                Text(zoomPercentText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.primaryTextColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(theme.usesDarkAppearance ? 0.22 : 0.08))
                    )
            }

            Button("+ Temp 카드") {
                onCreateTempCard()
            }
            .buttonStyle(.bordered)
            .disabled(!isInteractionEnabled)

            Button("작업창으로 돌아가기") {
                onClose()
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accentColor.opacity(theme.usesDarkAppearance ? 0.84 : 0.92))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(theme.groupBackground.opacity(theme.usesDarkAppearance ? 0.94 : 0.86))
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

    @ViewBuilder
    private var dragOverlay: some View {
        if let drag = cardDragState,
           let card = cardByID(drag.cardID) {
            let origin = drag.overlayOrigin(scrollOrigin: scrollController.viewportOrigin)
            IndexBoardCardTile(
                card: card,
                theme: theme,
                isSelected: true,
                isActive: activeCardID == card.id,
                summary: summaryByCardID[card.id],
                showsBack: showsBackByCardID[card.id] ?? false,
                onTap: {}
            )
            .scaleEffect(1.03)
            .shadow(color: Color.black.opacity(theme.usesDarkAppearance ? 0.34 : 0.16), radius: 24, x: 0, y: 12)
            .offset(x: origin.x, y: origin.y)
            .allowsHitTesting(false)
        } else if let drag = groupDragState,
                  let group = projection.groups.first(where: { $0.id == drag.groupID }) {
            let origin = drag.overlayOrigin(scrollOrigin: scrollController.viewportOrigin)
            IndexBoardGroupView(
                group: group,
                theme: theme,
                selectedCardIDs: selectedCardIDs,
                activeCardID: activeCardID,
                summaryByCardID: summaryByCardID,
                showsBackByCardID: showsBackByCardID,
                onCardTap: { _ in }
            )
            .scaleEffect(1.01)
            .shadow(color: Color.black.opacity(theme.usesDarkAppearance ? 0.34 : 0.16), radius: 26, x: 0, y: 14)
            .offset(x: origin.x, y: origin.y)
            .allowsHitTesting(false)
        }
    }

    private var cardDragAnimationKey: String {
        guard let cardDragState else { return "card-idle" }
        return "\(cardDragState.groupIDKey)-\(cardDragState.dropTarget.insertionIndex)"
    }

    private var groupDragAnimationKey: Int {
        groupDragState?.targetIndex ?? -1
    }

    private func renderedGroupsForCardDrag(_ drag: IndexBoardCardDragState) -> [IndexBoardRenderedGroup] {
        projection.groups.map { group in
            let visibleCards = group.childCards.filter { $0.id != drag.cardID }
            var items = visibleCards.map(IndexBoardCardDisplayItem.live(_:))
            if group.id == drag.dropTarget.groupID {
                let safeIndex = min(max(0, drag.dropTarget.insertionIndex), items.count)
                items.insert(.placeholder(cardID: drag.cardID), at: safeIndex)
            }
            return IndexBoardRenderedGroup.live(group, cardItems: items)
        }
    }

    private func renderedGroupsForGroupDrag(_ drag: IndexBoardGroupDragState) -> [IndexBoardRenderedGroup] {
        let visibleGroups = projection.groups.filter { $0.id != drag.groupID }
        var rendered = visibleGroups.map { group in
            IndexBoardRenderedGroup.live(
                group,
                cardItems: group.childCards.map(IndexBoardCardDisplayItem.live(_:))
            )
        }
        let placeholderHeight = groupPlaceholderHeight(for: drag.groupID)
        let safeIndex = min(max(0, drag.targetIndex), rendered.count)
        rendered.insert(
            .placeholder(groupID: drag.groupID, height: placeholderHeight),
            at: safeIndex
        )
        return rendered
    }

    private func handleCardDragChanged(_ card: SceneCard, value: DragGesture.Value) {
        guard groupDragState == nil else { return }

        if cardDragState?.cardID != card.id {
            cancelDeferredViewportPersistence()
            guard let sourceGroup = projection.groups.first(where: { group in
                group.childCards.contains(where: { $0.id == card.id })
            }) else {
                return
            }
            guard let sourceIndex = sourceGroup.childCards.firstIndex(where: { $0.id == card.id }) else {
                return
            }
            guard let initialFrame = cardFrameByID[card.id] else { return }
            let scrollOrigin = scrollController.viewportOrigin
            let pointerInViewport = CGPoint(
                x: value.location.x - scrollOrigin.x,
                y: value.location.y - scrollOrigin.y
            )
            let dropTarget = IndexBoardCardDropTarget(groupID: sourceGroup.id, insertionIndex: sourceIndex)
            cardDragState = IndexBoardCardDragState(
                cardID: card.id,
                sourceGroupID: sourceGroup.id,
                sourceIndex: sourceIndex,
                initialFrame: initialFrame,
                pointerOffset: CGSize(
                    width: value.startLocation.x - initialFrame.minX,
                    height: value.startLocation.y - initialFrame.minY
                ),
                pointerInViewport: pointerInViewport,
                dropTarget: dropTarget
            )
        }

        guard var drag = cardDragState, drag.cardID == card.id else { return }
        drag.pointerInViewport = CGPoint(
            x: value.location.x - scrollController.viewportOrigin.x,
            y: value.location.y - scrollController.viewportOrigin.y
        )
        drag.dropTarget = resolvedCardDropTarget(for: drag)
        cardDragState = drag
    }

    private func handleCardDragEnded(_ card: SceneCard, value: DragGesture.Value) {
        handleCardDragChanged(card, value: value)
        guard let drag = cardDragState, drag.cardID == card.id else { return }
        let shouldCommit =
            drag.dropTarget.groupID != drag.sourceGroupID ||
            drag.dropTarget.insertionIndex != drag.sourceIndex
        let target = drag.dropTarget
        cardDragState = nil
        flushDeferredViewportPersistence()
        if shouldCommit {
            onCardMove(card.id, target)
        }
    }

    private func handleGroupDragChanged(for group: IndexBoardGroupProjection, value: DragGesture.Value) {
        guard cardDragState == nil else { return }
        guard group.parentCard != nil else { return }

        if groupDragState?.groupID != group.id {
            cancelDeferredViewportPersistence()
            guard let sourceIndex = projection.groups.firstIndex(where: { $0.id == group.id }) else {
                return
            }
            guard let initialFrame = groupFrameByID[group.id] else { return }
            let scrollOrigin = scrollController.viewportOrigin
            let pointerInViewport = CGPoint(
                x: value.location.x - scrollOrigin.x,
                y: value.location.y - scrollOrigin.y
            )
            groupDragState = IndexBoardGroupDragState(
                groupID: group.id,
                sourceIndex: sourceIndex,
                initialFrame: initialFrame,
                pointerOffset: CGSize(
                    width: value.startLocation.x - initialFrame.minX,
                    height: value.startLocation.y - initialFrame.minY
                ),
                pointerInViewport: pointerInViewport,
                targetIndex: sourceIndex
            )
        }

        guard var drag = groupDragState, drag.groupID == group.id else { return }
        drag.pointerInViewport = CGPoint(
            x: value.location.x - scrollController.viewportOrigin.x,
            y: value.location.y - scrollController.viewportOrigin.y
        )
        drag.targetIndex = resolvedGroupTargetIndex(for: drag)
        groupDragState = drag
    }

    private func handleGroupDragEnded(for group: IndexBoardGroupProjection, value: DragGesture.Value) {
        handleGroupDragChanged(for: group, value: value)
        guard let drag = groupDragState, drag.groupID == group.id else { return }
        let targetIndex = drag.targetIndex
        let shouldCommit = targetIndex != drag.sourceIndex
        groupDragState = nil
        flushDeferredViewportPersistence()
        if shouldCommit {
            onGroupMove(group.id, targetIndex)
        }
    }

    private func handleAutoScrollTick() {
        let pointerInViewport: CGPoint
        if let drag = cardDragState {
            pointerInViewport = drag.pointerInViewport
        } else if let drag = groupDragState {
            pointerInViewport = drag.pointerInViewport
        } else {
            return
        }

        let delta = autoScrollDelta(for: pointerInViewport)
        guard delta != .zero else { return }
        scrollController.scroll(by: delta)
        recalculateActiveDropTarget()
    }

    private func recalculateActiveDropTarget() {
        if var drag = cardDragState {
            drag.dropTarget = resolvedCardDropTarget(for: drag)
            cardDragState = drag
        } else if var drag = groupDragState {
            drag.targetIndex = resolvedGroupTargetIndex(for: drag)
            groupDragState = drag
        }
    }

    private func resolvedCardDropTarget(for drag: IndexBoardCardDragState) -> IndexBoardCardDropTarget {
        let pointer = drag.pointerInContent(scrollOrigin: scrollController.viewportOrigin)
        var bestTarget = drag.dropTarget
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for group in projection.groups {
            let visibleCards = group.childCards.filter { $0.id != drag.cardID }
            let slotCount = visibleCards.count + 1
            for insertionIndex in 0..<slotCount {
                let slotRect = resolvedCardSlotRect(for: group, insertionIndex: insertionIndex)
                let distance = distance(from: pointer, to: slotRect)
                if distance < bestDistance {
                    bestDistance = distance
                    bestTarget = IndexBoardCardDropTarget(groupID: group.id, insertionIndex: insertionIndex)
                }
            }
        }

        let currentRect = resolvedCardSlotRect(
            for: drag.dropTarget.groupID,
            insertionIndex: drag.dropTarget.insertionIndex
        )
        let currentDistance = distance(from: pointer, to: currentRect)
        if currentDistance <= bestDistance + 14 {
            return drag.dropTarget
        }
        return bestTarget
    }

    private func resolvedGroupTargetIndex(for drag: IndexBoardGroupDragState) -> Int {
        let pointer = drag.pointerInContent(scrollOrigin: scrollController.viewportOrigin)
        let remainingGroups = projection.groups.filter { $0.id != drag.groupID }
        guard !remainingGroups.isEmpty else { return 0 }

        let slotRects = resolvedGroupSlotRects(for: remainingGroups)
        var bestIndex = drag.targetIndex
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for (index, rect) in slotRects {
            let distance = distance(from: pointer, to: rect)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        if let currentRect = slotRects.first(where: { $0.0 == drag.targetIndex })?.1 {
            let currentDistance = distance(from: pointer, to: currentRect)
            if currentDistance <= bestDistance + 18 {
                return drag.targetIndex
            }
        }

        return bestIndex
    }

    private func resolvedCardSlotRect(
        for groupID: IndexBoardGroupID,
        insertionIndex: Int
    ) -> CGRect {
        guard let group = projection.groups.first(where: { $0.id == groupID }) else {
            return CGRect(origin: .zero, size: IndexBoardMetrics.cardSize)
        }
        return resolvedCardSlotRect(for: group, insertionIndex: insertionIndex)
    }

    private func resolvedCardSlotRect(
        for group: IndexBoardGroupProjection,
        insertionIndex: Int
    ) -> CGRect {
        let gridOrigin = resolvedCardGridOrigin(for: group)
        let safeIndex = max(0, insertionIndex)
        let row = safeIndex / 2
        let column = safeIndex % 2
        return CGRect(
            origin: CGPoint(
                x: gridOrigin.x + (CGFloat(column) * (IndexBoardMetrics.cardSize.width + IndexBoardMetrics.cardSpacing)),
                y: gridOrigin.y + (CGFloat(row) * (IndexBoardMetrics.cardSize.height + IndexBoardMetrics.cardSpacing))
            ),
            size: IndexBoardMetrics.cardSize
        )
    }

    private func resolvedCardGridOrigin(for group: IndexBoardGroupProjection) -> CGPoint {
        let originalFrames = group.childCards.compactMap { cardFrameByID[$0.id] }
        if let minX = originalFrames.map(\.minX).min(),
           let minY = originalFrames.map(\.minY).min() {
            return CGPoint(x: minX, y: minY)
        }

        let groupFrame = groupFrameByID[group.id] ?? CGRect(
            x: IndexBoardMetrics.boardHorizontalPadding,
            y: IndexBoardMetrics.boardVerticalPadding,
            width: IndexBoardMetrics.groupWidth,
            height: IndexBoardPhaseTwoConstants.estimatedGroupHeaderHeight + IndexBoardMetrics.groupInnerPadding + IndexBoardMetrics.cardSize.height
        )
        return CGPoint(
            x: groupFrame.minX + IndexBoardMetrics.groupInnerPadding,
            y: groupFrame.minY + IndexBoardPhaseTwoConstants.estimatedGroupHeaderHeight + IndexBoardMetrics.groupInnerPadding
        )
    }

    private func resolvedGroupSlotRects(for groups: [IndexBoardGroupProjection]) -> [(Int, CGRect)] {
        guard !groups.isEmpty else {
            return [
                (
                    0,
                    CGRect(
                        x: IndexBoardMetrics.boardHorizontalPadding,
                        y: IndexBoardMetrics.boardVerticalPadding,
                        width: IndexBoardMetrics.groupWidth,
                        height: groupPlaceholderHeight(for: .root)
                    )
                )
            ]
        }

        var slots: [(Int, CGRect)] = []

        if let firstFrame = groupFrameByID[groups[0].id] {
            slots.append((
                0,
                CGRect(
                    x: firstFrame.minX - max(24, IndexBoardMetrics.groupSpacing),
                    y: firstFrame.minY,
                    width: max(24, IndexBoardMetrics.groupSpacing),
                    height: firstFrame.height
                )
            ))
        }

        for index in 0..<groups.count {
            guard let currentFrame = groupFrameByID[groups[index].id] else { continue }

            if index == groups.count - 1 {
                slots.append((
                    groups.count,
                    CGRect(
                        x: currentFrame.maxX,
                        y: currentFrame.minY,
                        width: max(24, IndexBoardMetrics.groupSpacing),
                        height: currentFrame.height
                    )
                ))
                continue
            }

            guard let nextFrame = groupFrameByID[groups[index + 1].id] else { continue }
            let sameRow = abs(currentFrame.midY - nextFrame.midY) < min(currentFrame.height, nextFrame.height) * 0.45
            if sameRow {
                let startX = currentFrame.maxX
                let endX = max(startX + 24, nextFrame.minX)
                slots.append((
                    index + 1,
                    CGRect(
                        x: startX,
                        y: min(currentFrame.minY, nextFrame.minY),
                        width: endX - startX,
                        height: max(currentFrame.height, nextFrame.height)
                    )
                ))
            } else {
                slots.append((
                    index + 1,
                    CGRect(
                        x: nextFrame.minX - max(24, IndexBoardMetrics.groupSpacing),
                        y: nextFrame.minY,
                        width: max(24, IndexBoardMetrics.groupSpacing),
                        height: nextFrame.height
                    )
                ))
            }
        }

        return slots
    }

    private func autoScrollDelta(for pointerInViewport: CGPoint) -> CGPoint {
        CGPoint(
            x: autoScrollAxisDelta(position: pointerInViewport.x, viewportLength: scrollController.viewportSize.width),
            y: autoScrollAxisDelta(position: pointerInViewport.y, viewportLength: scrollController.viewportSize.height)
        )
    }

    private func autoScrollAxisDelta(position: CGFloat, viewportLength: CGFloat) -> CGFloat {
        guard viewportLength > 0 else { return 0 }
        let edge = IndexBoardPhaseTwoConstants.autoScrollEdgeInset
        if position < edge {
            let progress = max(0, min(1, (edge - position) / edge))
            return -IndexBoardPhaseTwoConstants.maxAutoScrollStep * progress
        }
        if position > viewportLength - edge {
            let progress = max(0, min(1, (position - (viewportLength - edge)) / edge))
            return IndexBoardPhaseTwoConstants.maxAutoScrollStep * progress
        }
        return 0
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(0, max(rect.minX - point.x, point.x - rect.maxX))
        let dy = max(0, max(rect.minY - point.y, point.y - rect.maxY))
        return sqrt((dx * dx) + (dy * dy))
    }

    private func groupPlaceholderHeight(for groupID: IndexBoardGroupID) -> CGFloat {
        if let groupFrame = groupFrameByID[groupID] {
            return groupFrame.height
        }
        if let group = projection.groups.first(where: { $0.id == groupID }),
           let frame = groupFrameByID[group.id] {
            return frame.height
        }
        return IndexBoardPhaseTwoConstants.estimatedGroupHeaderHeight +
            IndexBoardMetrics.groupInnerPadding * 2 +
            IndexBoardPhaseTwoConstants.emptyGroupDropWellHeight
    }

    private func cardByID(_ cardID: UUID) -> SceneCard? {
        projection.groups
            .lazy
            .flatMap(\.childCards)
            .first(where: { $0.id == cardID })
    }

    private func attemptPendingCardReveal() {
        guard let targetCardID = pendingRevealCardID,
              let frame = cardFrameByID[targetCardID] else {
            return
        }
        scrollController.ensureVisible(frame)
        pendingRevealCardID = nil
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

private extension IndexBoardCardDragState {
    var groupIDKey: String {
        dropTarget.groupID.id
    }
}

private struct IndexBoardOptionalGestureModifier<G: Gesture>: ViewModifier {
    let isEnabled: Bool
    let gesture: G

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.gesture(gesture)
        } else {
            content
        }
    }
}

extension ScenarioWriterView {
    func commitIndexBoardCardMoveSelection(
        cardIDs: [UUID],
        draggedCardID: UUID,
        target: IndexBoardCardDropTarget,
        projection: IndexBoardProjection
    ) {
        let liveProjection = resolvedIndexBoardProjection() ?? projection
        let referenceSurfaceProjection = resolvedIndexBoardSurfaceProjection()
        let movingCards = resolvedIndexBoardMovingCards(
            cardIDs: cardIDs,
            preferredColumns: target.preferredColumnCount ?? 1
        )
        guard !movingCards.isEmpty else { return }
        let movingIDs = Set(movingCards.map(\.id))
        let draggedCard = movingCards.first(where: { $0.id == draggedCardID }) ?? movingCards.first
        guard let draggedCard else { return }

        if target.isTempStripTarget {
            commitDetachedIndexBoardCardMoveSelection(
                movingCards: movingCards,
                draggedCard: draggedCard,
                target: target
            )
            return
        }

        guard let targetGroup = liveProjection.groups.first(where: { $0.id == target.groupID }) else { return }
        let visibleCards = targetGroup.childCards.filter { !movingIDs.contains($0.id) }
        let safeInsertionIndex = min(max(0, target.insertionIndex), visibleCards.count)

        movingCards.forEach { updateIndexBoardDetachedPosition(cardID: $0.id, position: nil) }

        let destination = resolvedIndexBoardCardDestination(
            movingCard: draggedCard,
            target: target,
            targetGroup: targetGroup,
            visibleCards: visibleCards,
            insertionIndex: safeInsertionIndex,
            projection: liveProjection
        )

        let destinationParent = destination.parent
        var resolvedInsertionIndex = destination.index
        let destinationParentID = destinationParent?.id
        let movedBeforeDestination = movingCards.filter {
            $0.parent?.id == destinationParentID && $0.orderIndex < resolvedInsertionIndex
        }.count
        resolvedInsertionIndex -= movedBeforeDestination
        resolvedInsertionIndex = max(0, resolvedInsertionIndex)

        let isNoOp =
            movingCards.allSatisfy { $0.parent?.id == destinationParentID } &&
            movingCards.enumerated().allSatisfy { offset, card in
                card.orderIndex == resolvedInsertionIndex + offset
            }
        if isNoOp {
            return
        }

        let previousState = captureScenarioState()
        let oldParents = movingCards.map(\.parent)
        scenario.performBatchedCardMutation {
            let destinationSiblings = liveOrderedSiblings(parent: destinationParent)
            for sibling in destinationSiblings where !movingIDs.contains(sibling.id) && sibling.orderIndex >= resolvedInsertionIndex {
                sibling.orderIndex += movingCards.count
            }

            for (offset, card) in movingCards.enumerated() {
                let previousParent = card.parent
                if card.isArchived {
                    card.isArchived = false
                }
                card.parent = destinationParent
                card.orderIndex = resolvedInsertionIndex + offset
                card.isFloating = false
                synchronizeMovedSubtreeCategoryIfNeeded(
                    for: card,
                    oldParent: previousParent,
                    newParent: destinationParent
                )
            }

            normalizeAffectedParents(oldParents: oldParents, destinationParent: destinationParent)
        }

        if let normalizedSurfaceProjection = resolvedIndexBoardSurfaceProjection(
            referenceSurfaceProjection: referenceSurfaceProjection
        ) {
            persistIndexBoardSurfacePresentation(normalizedSurfaceProjection)
        }

        selectedCardIDs = movingIDs
        changeActiveCard(to: draggedCard, shouldFocusMain: false, deferToMainAsync: false, force: true)
        commitCardMutation(
            previousState: previousState,
            actionName: "보드 카드 이동"
        )
    }

    func commitIndexBoardCardMove(
        cardID: UUID,
        target: IndexBoardCardDropTarget,
        projection: IndexBoardProjection
    ) {
        let liveProjection = resolvedIndexBoardProjection() ?? projection
        let referenceSurfaceProjection = resolvedIndexBoardSurfaceProjection()
        guard let movingCard = findCard(by: cardID) else { return }
        let isCurrentlyDetached = activeIndexBoardSession?.detachedGridPositionByCardID[movingCard.id] != nil

        if target.isTempStripTarget {
            commitDetachedIndexBoardCardMove(
                movingCard: movingCard,
                target: target
            )
            return
        }

        guard let targetGroup = liveProjection.groups.first(where: { $0.id == target.groupID }) else { return }
        let visibleCards = targetGroup.childCards.filter { $0.id != movingCard.id }
        let safeInsertionIndex = min(max(0, target.insertionIndex), visibleCards.count)

        if !isCurrentlyDetached,
           let sourceGroup = liveProjection.groups.first(where: { group in
            group.childCards.contains(where: { $0.id == movingCard.id })
        }),
           let sourceIndex = sourceGroup.childCards.firstIndex(where: { $0.id == movingCard.id }),
           sourceGroup.id == target.groupID,
           sourceIndex == safeInsertionIndex {
            return
        }

        updateIndexBoardDetachedPosition(cardID: movingCard.id, position: nil)

        let destination = resolvedIndexBoardCardDestination(
            movingCard: movingCard,
            target: target,
            targetGroup: targetGroup,
            visibleCards: visibleCards,
            insertionIndex: safeInsertionIndex,
            projection: liveProjection
        )

        let previousState = captureScenarioState()
        scenario.performBatchedCardMutation {
            if movingCard.isArchived {
                movingCard.isArchived = false
            }

            let oldParent = movingCard.parent
            normalizeIndices(parent: oldParent)

            let destinationParent = destination.parent
            var insertionIndex = destination.index
            if oldParent?.id == destinationParent?.id,
               movingCard.orderIndex < insertionIndex {
                insertionIndex -= 1
            }
            insertionIndex = max(0, insertionIndex)

            let destinationSiblings = liveOrderedSiblings(parent: destinationParent)
            for sibling in destinationSiblings where sibling.id != movingCard.id && sibling.orderIndex >= insertionIndex {
                sibling.orderIndex += 1
            }

            movingCard.parent = destinationParent
            movingCard.orderIndex = insertionIndex
            movingCard.isFloating = false

            normalizeIndices(parent: movingCard.parent)
            if oldParent?.id != movingCard.parent?.id {
                normalizeIndices(parent: oldParent)
            }

            synchronizeMovedSubtreeCategoryIfNeeded(
                for: movingCard,
                oldParent: oldParent,
                newParent: movingCard.parent
            )
        }

        if let normalizedSurfaceProjection = resolvedIndexBoardSurfaceProjection(
            referenceSurfaceProjection: referenceSurfaceProjection
        ) {
            persistIndexBoardSurfacePresentation(normalizedSurfaceProjection)
        }

        selectedCardIDs = [movingCard.id]
        changeActiveCard(to: movingCard, shouldFocusMain: false, deferToMainAsync: false, force: true)
        commitCardMutation(
            previousState: previousState,
            actionName: "보드 카드 이동"
        )
    }

    private func commitDetachedIndexBoardCardMove(
        movingCard: SceneCard,
        target: IndexBoardCardDropTarget
    ) {
        let referenceSurfaceProjection = resolvedIndexBoardSurfaceProjection()
        let previousState = captureScenarioState()
        let updatedTempStrips = resolvedUpdatedIndexBoardTempStrips(
            referenceSurfaceProjection: referenceSurfaceProjection,
            movingMembers: [IndexBoardTempStripMember(kind: .card, id: movingCard.id)],
            target: target
        )

        scenario.performBatchedCardMutation {
            let tempContainer = ensureIndexBoardTempContainer()
            applyIndexBoardParentPlacement(
                movingCard: movingCard,
                destinationParent: tempContainer,
                destinationIndex: liveOrderedSiblings(parent: tempContainer).count
            )
            applyIndexBoardTempStripOrdering(updatedTempStrips)
        }
        applyIndexBoardTempStripPresentation(
            updatedTempStrips,
            referenceSurfaceProjection: referenceSurfaceProjection
        )

        if let normalizedSurfaceProjection = resolvedIndexBoardSurfaceProjection(
            referenceSurfaceProjection: referenceSurfaceProjection
        ) {
            persistIndexBoardSurfacePresentation(normalizedSurfaceProjection)
        }

        selectedCardIDs = [movingCard.id]
        changeActiveCard(to: movingCard, shouldFocusMain: false, deferToMainAsync: false, force: true)
        commitCardMutation(
            previousState: previousState,
            actionName: "보드 카드 이동"
        )
    }

    private func commitDetachedIndexBoardCardMoveSelection(
        movingCards: [SceneCard],
        draggedCard: SceneCard,
        target: IndexBoardCardDropTarget
    ) {
        let movingIDs = Set(movingCards.map(\.id))
        let referenceSurfaceProjection = resolvedIndexBoardSurfaceProjection()
        let previousState = captureScenarioState()
        let updatedTempStrips = resolvedUpdatedIndexBoardTempStrips(
            referenceSurfaceProjection: referenceSurfaceProjection,
            movingMembers: movingCards.map { IndexBoardTempStripMember(kind: .card, id: $0.id) },
            target: target
        )

        scenario.performBatchedCardMutation {
            let tempContainer = ensureIndexBoardTempContainer()
            for card in movingCards {
                applyIndexBoardParentPlacement(
                    movingCard: card,
                    destinationParent: tempContainer,
                    destinationIndex: liveOrderedSiblings(parent: tempContainer).count
                )
            }
            applyIndexBoardTempStripOrdering(updatedTempStrips)
        }
        applyIndexBoardTempStripPresentation(
            updatedTempStrips,
            referenceSurfaceProjection: referenceSurfaceProjection
        )

        if let normalizedSurfaceProjection = resolvedIndexBoardSurfaceProjection(
            referenceSurfaceProjection: referenceSurfaceProjection
        ) {
            persistIndexBoardSurfacePresentation(normalizedSurfaceProjection)
        }

        selectedCardIDs = movingIDs
        changeActiveCard(to: draggedCard, shouldFocusMain: false, deferToMainAsync: false, force: true)
        commitCardMutation(
            previousState: previousState,
            actionName: "보드 카드 이동"
        )
    }

    func commitIndexBoardGroupMove(
        groupID: IndexBoardGroupID,
        targetIndex: Int,
        projection: IndexBoardProjection
    ) {
        let liveProjection = resolvedIndexBoardProjection() ?? projection
        guard let movingGroup = liveProjection.groups.first(where: { $0.id == groupID }),
              let movingParentCard = movingGroup.parentCard else { return }
        let visibleGroups = liveProjection.groups.filter { $0.id != groupID && !$0.isTempGroup && $0.parentCard != nil }
        let currentVisibleGroups = liveProjection.groups.filter { !$0.isTempGroup && $0.parentCard != nil }
        let safeTargetIndex = min(max(0, targetIndex), visibleGroups.count)
        if let sourceIndex = currentVisibleGroups.firstIndex(where: { $0.id == groupID }),
           sourceIndex == safeTargetIndex,
           !movingGroup.isTempGroup {
            return
        }

        let previousState = captureScenarioState()
        scenario.performBatchedCardMutation {
            applyIndexBoardGroupMove(
                movingParentCard: movingParentCard,
                context: IndexBoardResolvedGroupMoveContext(
                    groups: resolvedIndexBoardProjection() ?? projection,
                    movingGroupID: groupID,
                    targetIndex: safeTargetIndex
                )
            )
        }

        commitCardMutation(
            previousState: previousState,
            actionName: "보드 그룹 이동"
        )
    }

    func commitIndexBoardParentGroupMove(
        target: IndexBoardParentGroupDropTarget,
        projection: IndexBoardProjection
    ) {
        guard target.parentCardID != activeIndexBoardSession?.source.parentID else { return }
        if let surfaceProjection = resolvedIndexBoardSurfaceProjection(),
           let movingGroup = surfaceProjection.parentGroups.first(where: { $0.parentCardID == target.parentCardID }),
           movingGroup.isTempGroup {
            let previousState = captureScenarioState()
            let updatedTempStrips = resolvedUpdatedIndexBoardTempStrips(
                referenceSurfaceProjection: surfaceProjection,
                movingMembers: [IndexBoardTempStripMember(kind: .group, id: target.parentCardID)],
                target: IndexBoardCardDropTarget(
                    groupID: .parent(target.parentCardID),
                    insertionIndex: 0,
                    detachedGridPosition: target.origin
                )
            )
            scenario.performBatchedCardMutation {
                applyIndexBoardTempStripOrdering(updatedTempStrips)
            }
            applyIndexBoardTempStripPresentation(
                updatedTempStrips,
                referenceSurfaceProjection: surfaceProjection
            )
            commitCardMutation(
                previousState: previousState,
                actionName: "보드 부모 그룹 이동"
            )
            return
        }
        updateIndexBoardGroupPosition(parentCardID: target.parentCardID, position: target.origin)
        guard let surfaceProjection = resolvedIndexBoardSurfaceProjection() else { return }

        let previousState = captureScenarioState()
        scenario.performBatchedCardMutation {
            applyIndexBoardSurfaceParentOrdering(
                surfaceProjection: surfaceProjection,
                projection: projection
            )
        }

        commitCardMutation(
            previousState: previousState,
            actionName: "보드 부모 그룹 이동"
        )
    }

    func setIndexBoardParentGroupTemp(
        parentCardID: UUID,
        isTemp: Bool,
        projection: IndexBoardProjection
    ) {
        guard isIndexBoardActive,
              parentCardID != activeIndexBoardSession?.source.parentID,
              let movingParentCard = findCard(by: parentCardID) else { return }

        let previousState = captureScenarioState()
        scenario.performBatchedCardMutation {
            if isTemp {
                let tempContainer = ensureIndexBoardTempContainer()
                applyIndexBoardParentPlacement(
                    movingCard: movingParentCard,
                    destinationParent: tempContainer,
                    destinationIndex: liveOrderedSiblings(parent: tempContainer).count
                )
            } else {
                let sourceParent = activeIndexBoardSession?.source.parentID.flatMap { findCard(by: $0) }
                applyIndexBoardParentPlacement(
                    movingCard: movingParentCard,
                    destinationParent: sourceParent,
                    destinationIndex: liveOrderedSiblings(parent: sourceParent).count
                )
            }

            if let surfaceProjection = resolvedIndexBoardSurfaceProjection() {
                applyIndexBoardSurfaceParentOrdering(
                    surfaceProjection: surfaceProjection,
                    projection: projection
                )
            }
        }

        commitCardMutation(
            previousState: previousState,
            actionName: isTemp ? "보드 그룹 Temp 이동" : "보드 그룹 Temp 복귀"
        )
    }

    private func applyIndexBoardSurfaceParentOrdering(
        surfaceProjection: BoardSurfaceProjection,
        projection: IndexBoardProjection
    ) {
        let desiredMainlineParentIDs = surfaceProjection.parentGroups
            .filter { !$0.isTempGroup }
            .compactMap(\.parentCardID)
        let desiredTempParentIDs = surfaceProjection.parentGroups
            .filter(\.isTempGroup)
            .compactMap(\.parentCardID)
        let desiredTempParentIDSet = Set(desiredTempParentIDs)
        let sourceParent = activeIndexBoardSession?.source.parentID.flatMap { findCard(by: $0) }
        let tempContainer = ensureIndexBoardTempContainer()

        let tempStartIndex = liveOrderedSiblings(parent: tempContainer)
            .filter { !desiredTempParentIDSet.contains($0.id) }
            .count

        for (offset, parentID) in desiredTempParentIDs.enumerated() {
            guard parentID != sourceParent?.id else { continue }
            guard let parentCard = findCard(by: parentID) else { continue }
            applyIndexBoardParentPlacement(
                movingCard: parentCard,
                destinationParent: tempContainer,
                destinationIndex: tempStartIndex + offset
            )
        }

        for (targetIndex, parentID) in desiredMainlineParentIDs.enumerated() {
            guard parentID != sourceParent?.id else { continue }
            guard let parentCard = findCard(by: parentID) else { continue }
            let currentProjection = resolvedIndexBoardProjection() ?? projection
            let movingGroupID = IndexBoardGroupID.parent(parentID)
            let visibleGroups = currentProjection.groups.filter {
                $0.id != movingGroupID && !$0.isTempGroup && $0.parentCard != nil
            }
            let safeTargetIndex = min(max(0, targetIndex), visibleGroups.count)
            let previousGroup = safeTargetIndex > 0 ? visibleGroups[safeTargetIndex - 1] : nil
            let nextGroup = safeTargetIndex < visibleGroups.count ? visibleGroups[safeTargetIndex] : nil

            if previousGroup == nil && nextGroup == nil {
                applyIndexBoardParentPlacement(
                    movingCard: parentCard,
                    destinationParent: sourceParent,
                    destinationIndex: 0
                )
            } else {
                applyIndexBoardGroupMove(
                    movingParentCard: parentCard,
                    context: IndexBoardResolvedGroupMoveContext(
                        previousGroup: previousGroup,
                        nextGroup: nextGroup
                    )
                )
            }
        }
    }

    private func applyIndexBoardGroupMove(
        movingParentCard: SceneCard,
        context: IndexBoardResolvedGroupMoveContext
    ) {
        let destination = resolvedIndexBoardGroupDestination(
            movingParentCard: movingParentCard,
            previousGroup: context.previousGroup,
            nextGroup: context.nextGroup
        )
        applyIndexBoardParentPlacement(
            movingCard: movingParentCard,
            destinationParent: destination.parent,
            destinationIndex: destination.index
        )
    }

    private func applyIndexBoardParentPlacement(
        movingCard: SceneCard,
        destinationParent: SceneCard?,
        destinationIndex: Int
    ) {
        guard isValidIndexBoardParent(destinationParent, for: movingCard) else { return }
        if movingCard.isArchived {
            movingCard.isArchived = false
        }

        let oldParent = movingCard.parent
        normalizeIndices(parent: oldParent)

        var insertionIndex = destinationIndex
        if oldParent?.id == destinationParent?.id,
           movingCard.orderIndex < insertionIndex {
            insertionIndex -= 1
        }
        insertionIndex = max(0, insertionIndex)

        let destinationSiblings = liveOrderedSiblings(parent: destinationParent)
        for sibling in destinationSiblings where sibling.id != movingCard.id && sibling.orderIndex >= insertionIndex {
            sibling.orderIndex += 1
        }

        movingCard.parent = destinationParent
        movingCard.orderIndex = insertionIndex
        movingCard.isFloating = false

        normalizeIndices(parent: movingCard.parent)
        if oldParent?.id != movingCard.parent?.id {
            normalizeIndices(parent: oldParent)
        }

        synchronizeMovedSubtreeCategoryIfNeeded(
            for: movingCard,
            oldParent: oldParent,
            newParent: movingCard.parent
        )
    }

    private func resolvedIndexBoardCardDestination(
        movingCard: SceneCard,
        target: IndexBoardCardDropTarget,
        targetGroup: IndexBoardGroupProjection,
        visibleCards: [SceneCard],
        insertionIndex: Int,
        projection: IndexBoardProjection
    ) -> (parent: SceneCard?, index: Int) {
        if let exactDestination = resolvedExactIndexBoardCardDestination(
            movingCard: movingCard,
            target: target
        ) {
            return exactDestination
        }

        let previousCard = insertionIndex > 0 ? visibleCards[insertionIndex - 1] : nil
        let nextCard = insertionIndex < visibleCards.count ? visibleCards[insertionIndex] : nil

        if let previousCard, let candidateParent = previousCard.parent,
           isValidIndexBoardParent(candidateParent, for: movingCard) {
            return (candidateParent, previousCard.orderIndex + 1)
        }

        if let nextCard, let candidateParent = nextCard.parent,
           isValidIndexBoardParent(candidateParent, for: movingCard) {
            return (candidateParent, nextCard.orderIndex)
        }

        if let ancestorParent = firstValidIndexBoardAncestorParent(
            startingAt: previousCard?.parent?.parent,
            movingCard: movingCard
        ) {
            return (ancestorParent, liveOrderedSiblings(parent: ancestorParent).count)
        }

        if let ancestorParent = firstValidIndexBoardAncestorParent(
            startingAt: nextCard?.parent?.parent,
            movingCard: movingCard
        ) {
            return (ancestorParent, liveOrderedSiblings(parent: ancestorParent).count)
        }

        let fallbackParent = targetGroup.parentCard
        if isValidIndexBoardParent(fallbackParent, for: movingCard) {
            if fallbackParent?.id == movingCard.parent?.id {
                return (fallbackParent, insertionIndex)
            }
            return (fallbackParent, liveOrderedSiblings(parent: fallbackParent).count)
        }

        let safeParent = projection.source.parentID.flatMap { findCard(by: $0) }
        return (safeParent, liveOrderedSiblings(parent: safeParent).count)
    }

    private func resolvedExactIndexBoardCardDestination(
        movingCard: SceneCard,
        target: IndexBoardCardDropTarget
    ) -> (parent: SceneCard?, index: Int)? {
        let previousCard = target.previousCardID.flatMap { candidateID -> SceneCard? in
            guard candidateID != movingCard.id else { return nil }
            return findCard(by: candidateID)
        }
        let nextCard = target.nextCardID.flatMap { candidateID -> SceneCard? in
            guard candidateID != movingCard.id else { return nil }
            return findCard(by: candidateID)
        }

        if let previousCard,
           let nextCard,
           previousCard.parent?.id == nextCard.parent?.id,
           isValidIndexBoardParent(previousCard.parent, for: movingCard) {
            return (previousCard.parent, nextCard.orderIndex)
        }

        let hintedParent = target.laneParentID.flatMap { findCard(by: $0) }
        if let nextCard,
           nextCard.parent?.id == target.laneParentID,
           isValidIndexBoardParent(nextCard.parent, for: movingCard) {
            return (nextCard.parent, nextCard.orderIndex)
        }

        if let previousCard,
           previousCard.parent?.id == target.laneParentID,
           isValidIndexBoardParent(previousCard.parent, for: movingCard) {
            return (previousCard.parent, previousCard.orderIndex + 1)
        }

        if previousCard == nil,
           nextCard == nil,
           isValidIndexBoardParent(hintedParent, for: movingCard) {
            return (hintedParent, max(0, target.insertionIndex))
        }

        if let previousCard,
           nextCard == nil,
           isValidIndexBoardParent(previousCard.parent, for: movingCard) {
            return (previousCard.parent, previousCard.orderIndex + 1)
        }

        if previousCard == nil,
           let nextCard,
           isValidIndexBoardParent(nextCard.parent, for: movingCard) {
            return (nextCard.parent, nextCard.orderIndex)
        }

        return nil
    }

    private func updateIndexBoardDetachedPosition(cardID: UUID, position: IndexBoardGridPosition?) {
        indexBoardRuntime.updateSession(for: scenario.id, paneID: paneContextID) { session in
            if let position {
                session.detachedGridPositionByCardID[cardID] = position
            } else {
                session.detachedGridPositionByCardID.removeValue(forKey: cardID)
            }
        }
    }

    private func resolvedIndexBoardTempGroupWidths(
        surfaceProjection: BoardSurfaceProjection?
    ) -> [UUID: Int] {
        Dictionary(
            uniqueKeysWithValues: surfaceProjection?.parentGroups.compactMap { placement in
                guard placement.isTempGroup,
                      let parentCardID = placement.parentCardID else {
                    return nil
                }
                return (parentCardID, placement.width)
            } ?? []
        )
    }

    private func resolvedUpdatedIndexBoardTempStrips(
        referenceSurfaceProjection: BoardSurfaceProjection?,
        movingMembers: [IndexBoardTempStripMember],
        target: IndexBoardCardDropTarget
    ) -> [IndexBoardTempStripState] {
        resolvedIndexBoardTempStripsByApplyingMove(
            strips: referenceSurfaceProjection?.tempStrips ?? [],
            movingMembers: movingMembers,
            previousMember: target.previousTempMember,
            nextMember: target.nextTempMember,
            parkingPosition: target.detachedGridPosition
        )
    }

    private func applyIndexBoardTempStripPresentation(
        _ strips: [IndexBoardTempStripState],
        referenceSurfaceProjection: BoardSurfaceProjection?
    ) {
        let layout = resolvedIndexBoardTempStripSurfaceLayout(
            strips: strips,
            tempGroupWidthsByParentID: resolvedIndexBoardTempGroupWidths(
                surfaceProjection: referenceSurfaceProjection
            )
        )
        let tempGroupIDs = Set(
            strips.flatMap(\.members).compactMap { member in
                member.kind == .group ? member.id : nil
            }
        )

        indexBoardRuntime.updateSession(for: scenario.id, paneID: paneContextID) { session in
            session.tempStrips = strips
            session.detachedGridPositionByCardID = layout.detachedPositionsByCardID
            for parentCardID in tempGroupIDs {
                if let position = layout.groupOriginByParentID[parentCardID] {
                    session.groupGridPositionByParentID[parentCardID] = position
                }
            }
        }
    }

    private func applyIndexBoardTempStripOrdering(
        _ strips: [IndexBoardTempStripState]
    ) {
        guard let tempContainer = resolvedIndexBoardTempContainer() else { return }
        let orderedMemberIDs = strips
            .sorted { lhs, rhs in
                if lhs.row != rhs.row { return lhs.row < rhs.row }
                if lhs.anchorColumn != rhs.anchorColumn { return lhs.anchorColumn < rhs.anchorColumn }
                return lhs.id < rhs.id
            }
            .flatMap(\.members)
            .map(\.id)
        let uniqueOrderedIDs = orderedMemberIDs.reduce(into: [UUID]()) { partialResult, cardID in
            if !partialResult.contains(cardID) {
                partialResult.append(cardID)
            }
        }
        let tempChildren = liveOrderedSiblings(parent: tempContainer)
        let remainingIDs = tempChildren.map(\.id).filter { !uniqueOrderedIDs.contains($0) }
        let finalIDs = uniqueOrderedIDs + remainingIDs

        for (index, cardID) in finalIDs.enumerated() {
            guard let card = findCard(by: cardID) else { continue }
            card.parent = tempContainer
            card.orderIndex = index
            card.isFloating = false
        }

        normalizeIndices(parent: tempContainer)
    }

    private func reindexIndexBoardDetachedSiblingsVisually(preferredColumns: Int?) {
        guard let tempContainer = resolvedIndexBoardTempContainer() else { return }
        reindexIndexBoardSiblingsVisually(
            parent: tempContainer,
            preferredColumns: max(1, preferredColumns ?? 1)
        )
    }

    private func reindexIndexBoardSiblingsVisually(
        parent: SceneCard?,
        preferredColumns: Int
    ) {
        let surfaceProjection = resolvedIndexBoardSurfaceProjection()
        let positionByCardID = resolvedIndexBoardVisualGridPositionByCardID(
            surfaceProjection: surfaceProjection,
            preferredColumns: preferredColumns
        )
        let siblings = liveOrderedSiblings(parent: parent)
        let orderedSiblings = siblings.enumerated().sorted { lhs, rhs in
            let lhsPosition = positionByCardID[lhs.element.id] ?? IndexBoardGridPosition(column: lhs.offset, row: .max / 4)
            let rhsPosition = positionByCardID[rhs.element.id] ?? IndexBoardGridPosition(column: rhs.offset, row: .max / 4)
            if lhsPosition.row != rhsPosition.row {
                return lhsPosition.row < rhsPosition.row
            }
            if lhsPosition.column != rhsPosition.column {
                return lhsPosition.column < rhsPosition.column
            }
            if lhs.element.orderIndex != rhs.element.orderIndex {
                return lhs.element.orderIndex < rhs.element.orderIndex
            }
            return lhs.element.id.uuidString < rhs.element.id.uuidString
        }
        .map(\.element)

        for (index, sibling) in orderedSiblings.enumerated() {
            sibling.orderIndex = index
            sibling.isFloating = false
        }

        normalizeIndices(parent: parent)
    }

    private func resolvedIndexBoardVisualGridPositionByCardID(
        surfaceProjection: BoardSurfaceProjection?,
        preferredColumns: Int
    ) -> [UUID: IndexBoardGridPosition] {
        guard let surfaceProjection else { return [:] }
        let safePreferredColumns = max(1, preferredColumns)
        var positionByCardID: [UUID: IndexBoardGridPosition] = [:]
        positionByCardID.reserveCapacity(surfaceProjection.surfaceItems.count)

        for item in surfaceProjection.surfaceItems {
            if let explicitGridPosition = item.gridPosition {
                positionByCardID[item.cardID] = explicitGridPosition
            } else if let detachedGridPosition = item.detachedGridPosition {
                positionByCardID[item.cardID] = detachedGridPosition
            } else if let slotIndex = item.slotIndex {
                positionByCardID[item.cardID] = IndexBoardGridPosition(
                    column: slotIndex % safePreferredColumns,
                    row: slotIndex / safePreferredColumns
                )
            }
        }

        return positionByCardID
    }

    private func resolvedIndexBoardMovingCards(
        cardIDs: [UUID],
        preferredColumns: Int
    ) -> [SceneCard] {
        let cards = cardIDs.compactMap { findCard(by: $0) }
        guard !cards.isEmpty else { return [] }

        let positionByCardID = resolvedIndexBoardVisualGridPositionByCardID(
            surfaceProjection: resolvedIndexBoardSurfaceProjection(),
            preferredColumns: preferredColumns
        )

        return cards.enumerated().sorted { lhs, rhs in
            let lhsPosition = positionByCardID[lhs.element.id] ?? IndexBoardGridPosition(column: lhs.offset, row: .max / 4)
            let rhsPosition = positionByCardID[rhs.element.id] ?? IndexBoardGridPosition(column: rhs.offset, row: .max / 4)
            if lhsPosition.row != rhsPosition.row {
                return lhsPosition.row < rhsPosition.row
            }
            if lhsPosition.column != rhsPosition.column {
                return lhsPosition.column < rhsPosition.column
            }
            if lhs.element.orderIndex != rhs.element.orderIndex {
                return lhs.element.orderIndex < rhs.element.orderIndex
            }
            return lhs.element.id.uuidString < rhs.element.id.uuidString
        }
        .map(\.element)
    }

    private func resolvedDetachedSelectionPositions(
        count: Int,
        start: IndexBoardGridPosition,
        occupied: Set<IndexBoardGridPosition>
    ) -> [IndexBoardGridPosition] {
        guard count > 0 else { return [] }
        var positions: [IndexBoardGridPosition] = []
        positions.reserveCapacity(count)
        var taken = occupied
        var nextColumn = start.column
        let row = start.row

        while positions.count < count {
            let candidate = IndexBoardGridPosition(column: nextColumn, row: row)
            if !taken.contains(candidate) {
                positions.append(candidate)
                taken.insert(candidate)
            }
            nextColumn += 1
        }

        return positions
    }

    private func resolvedIndexBoardGroupDestination(
        movingParentCard: SceneCard,
        previousGroup: IndexBoardGroupProjection?,
        nextGroup: IndexBoardGroupProjection?
    ) -> (parent: SceneCard?, index: Int) {
        if let previousGroup,
           let previousParentCard = previousGroup.parentCard,
           let candidateParent = previousParentCard.parent,
           isValidIndexBoardParent(candidateParent, for: movingParentCard) {
            return (candidateParent, previousParentCard.orderIndex + 1)
        }

        if let nextGroup,
           let nextParentCard = nextGroup.parentCard,
           let candidateParent = nextParentCard.parent,
           isValidIndexBoardParent(candidateParent, for: movingParentCard) {
            return (candidateParent, nextParentCard.orderIndex)
        }

        if let ancestorParent = firstValidIndexBoardAncestorParent(
            startingAt: previousGroup?.parentCard?.parent?.parent,
            movingCard: movingParentCard
        ) {
            return (ancestorParent, liveOrderedSiblings(parent: ancestorParent).count)
        }

        if let ancestorParent = firstValidIndexBoardAncestorParent(
            startingAt: nextGroup?.parentCard?.parent?.parent,
            movingCard: movingParentCard
        ) {
            return (ancestorParent, liveOrderedSiblings(parent: ancestorParent).count)
        }

        let fallbackParent = movingParentCard.parent
        return (fallbackParent, liveOrderedSiblings(parent: fallbackParent).count)
    }

    private func firstValidIndexBoardAncestorParent(
        startingAt candidate: SceneCard?,
        movingCard: SceneCard
    ) -> SceneCard? {
        var current = candidate
        var visited: Set<UUID> = []
        while let parent = current {
            guard visited.insert(parent.id).inserted else { return nil }
            if isValidIndexBoardParent(parent, for: movingCard) {
                return parent
            }
            current = parent.parent
        }
        return nil
    }

    private func isValidIndexBoardParent(
        _ candidateParent: SceneCard?,
        for movingCard: SceneCard
    ) -> Bool {
        guard let candidateParent else { return true }
        if candidateParent.id == movingCard.id {
            return false
        }
        return !isDescendant(movingCard, of: candidateParent.id)
    }
}
