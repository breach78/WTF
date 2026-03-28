import SwiftUI
import AppKit

final class IndexBoardSurfaceAppKitDocumentView: NSView, IndexBoardSurfaceAppKitCardInteractionDelegate, IndexBoardSurfaceAppKitLaneChipInteractionDelegate, NSTextViewDelegate {
    var configuration: IndexBoardSurfaceAppKitConfiguration
    var lastRenderState: IndexBoardSurfaceAppKitRenderState

    weak var scrollView: NSScrollView?

    var cardViews: [UUID: IndexBoardSurfaceAppKitInteractiveCardView] = [:]
    var laneChipViews: [String: IndexBoardSurfaceAppKitLaneChipView] = [:]
    var laneWrapperLayers: [String: CAShapeLayer] = [:]
    let startAnchorLayer = CAShapeLayer()
    let startAnchorTextLayer = CATextLayer()
    let hoverIndicatorLayer = CAShapeLayer()
    let selectionLayer = CAShapeLayer()
    var sourceGapLayers: [CAShapeLayer] = []
    var targetIndicatorLayers: [CAShapeLayer] = []
    var focusIndicatorLayers: [CAShapeLayer] = []
    var overlayLayers: [CALayer] = []
    var cardFrameByID: [UUID: CGRect] = [:]
    var chipFrameByLaneKey: [String: CGRect] = [:]
    var presentationSurfaceProjection: BoardSurfaceProjection? = nil
    var localCardDragPreviewFramesByID: [UUID: CGRect]? = nil
    var localGroupDragPreviewFramesByID: [UUID: CGRect]? = nil
    var localGroupDragTargetFrame: CGRect? = nil
    var dragState: IndexBoardSurfaceAppKitDragState? = nil
    var groupDragState: IndexBoardSurfaceAppKitGroupDragState? = nil
    var selectionState: IndexBoardSurfaceAppKitSelectionState? = nil
    var pendingBackgroundClickPoint: CGPoint? = nil
    var pendingBackgroundGridPosition: IndexBoardGridPosition? = nil
    var pendingBackgroundClickCount = 0
    var pendingCardClick: (cardID: UUID, point: CGPoint, clickCount: Int)?
    var pendingGroupClick: (parentCardID: UUID, point: CGPoint)?
    var contextMenuCardID: UUID?
    var contextMenuParentCardID: UUID?
    var contextMenuParentGroupIsTemp = false
    var dragSnapshots: [IndexBoardSurfaceAppKitCardSnapshot] = []
    var groupDragSnapshot: NSImage? = nil
    var restingSceneSnapshot: IndexBoardSurfaceAppKitSceneSnapshot? = nil
    var motionScene: IndexBoardSurfaceAppKitMotionScene? = nil
    var keepsMotionSceneUntilCommittedLayout = false
    var frozenLogicalGridBounds: IndexBoardSurfaceAppKitGridBounds? = nil
    var pinnedLogicalGridOrigin: IndexBoardGridPosition? = nil
    var lastRevealRequestToken: Int = 0
    var autoScrollTimer: Timer?
    var hoverTrackingArea: NSTrackingArea?
    var hoverGridPosition: IndexBoardGridPosition?
    var isHoverIndicatorSuppressed = false
    var baselineSession: IndexBoardSurfaceAppKitBaselineSession? = nil
    var inlineEditorScrollView: NSScrollView?
    weak var inlineEditorTextView: NSTextView?
    var inlineEditingCardID: UUID?
    var inlineEditingOriginalContent = ""
    var isEndingInlineEditing = false
    var suppressViewportChangeNotifications = false
    var pendingDropPreservedScrollOrigin: CGPoint? = nil
    var defersLayoutForLiveViewport = false
    var requestsDeferredCommitLayout = false
    var pendingLayoutAnimationDuration: TimeInterval = 0
    var shouldSkipCardViewReconcileForNextLayout = false
    var partialLaneKeysForNextLayout: Set<String>? = nil
    var shouldSkipIndicatorRefreshForNextLayout = false

    init(configuration: IndexBoardSurfaceAppKitConfiguration) {
        self.configuration = configuration
        self.lastRenderState = configuration.renderState
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        selectionLayer.fillColor = indexBoardThemeAccentColor(theme: configuration.theme)
            .withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.14 : 0.10).cgColor
        selectionLayer.strokeColor = indexBoardThemeAccentColor(theme: configuration.theme)
            .withAlphaComponent(0.82).cgColor
        selectionLayer.lineWidth = 1.5
        startAnchorTextLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        startAnchorTextLayer.alignmentMode = .center
        startAnchorTextLayer.fontSize = 11
        startAnchorTextLayer.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        layer?.addSublayer(startAnchorLayer)
        layer?.addSublayer(startAnchorTextLayer)
        hoverIndicatorLayer.isHidden = true
        layer?.addSublayer(hoverIndicatorLayer)
        layer?.addSublayer(selectionLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        endInlineEditing(commit: true)
    }
}

struct IndexBoardSurfaceAppKitPhaseTwoView: View {
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
    let onCreateTempCardAt: (IndexBoardGridPosition?) -> Void
    let onCreateParentFromSelection: () -> Void
    let onSetParentGroupTemp: (UUID, Bool) -> Void
    let onSetCardColor: (UUID, String?) -> Void
    let onDeleteCard: (UUID) -> Void
    let onDeleteParentGroup: (UUID) -> Void
    let onCardTap: (SceneCard) -> Void
    let onCardDragStart: ([UUID], UUID) -> Void
    let onCardOpen: (SceneCard) -> Void
    let onParentCardOpen: (UUID) -> Void
    let allowsInlineEditing: Bool
    let onInlineEditingChange: (Bool) -> Void
    let onInlineCardEditCommit: (UUID, String) -> Void
    let onCardFaceToggle: (SceneCard) -> Void
    let onZoomScaleChange: (CGFloat) -> Void
    let onZoomStep: (CGFloat) -> Void
    let onZoomReset: () -> Void
    let onScrollOffsetChange: (CGPoint) -> Void
    let onViewportFinalize: (CGFloat, CGPoint) -> Void
    let onShowCheckpoint: () -> Void
    let onToggleHistory: () -> Void
    let onToggleAIChat: () -> Void
    let onToggleTimeline: () -> Void
    let isHistoryVisible: Bool
    let isAIChatVisible: Bool
    let isTimelineVisible: Bool
    let onCardMove: (UUID, IndexBoardCardDropTarget) -> Void
    let onCardMoveSelection: ([UUID], UUID, IndexBoardCardDropTarget) -> Void
    let onMarqueeSelectionChange: (Set<UUID>) -> Void
    let onClearSelection: () -> Void
    let onGroupMove: (IndexBoardGroupID, Int) -> Void
    let onParentGroupMove: (IndexBoardParentGroupDropTarget) -> Void

    private var orderedItems: [BoardSurfaceItem] {
        surfaceProjection.surfaceItems.sorted(by: indexBoardSurfaceAppKitSort)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if orderedItems.isEmpty {
                emptyState
            } else {
                IndexBoardSurfaceAppKitCanvas(
                    configuration: IndexBoardSurfaceAppKitConfiguration(
                        surfaceProjection: surfaceProjection,
                        theme: theme,
                        cardsByID: cardsByID,
                        activeCardID: activeCardID,
                        selectedCardIDs: selectedCardIDs,
                        summaryByCardID: summaryByCardID,
                        showsBackByCardID: showsBackByCardID,
                        canvasSize: canvasSize,
                        zoomScale: zoomScale,
                        scrollOffset: scrollOffset,
                        revealCardID: revealCardID,
                        revealRequestToken: revealRequestToken,
                        isInteractionEnabled: isInteractionEnabled,
                        onCreateTempCard: onCreateTempCard,
                        onCreateTempCardAt: onCreateTempCardAt,
                        onCreateParentFromSelection: onCreateParentFromSelection,
                        onSetParentGroupTemp: onSetParentGroupTemp,
                        onSetCardColor: onSetCardColor,
                        onDeleteCard: onDeleteCard,
                        onDeleteParentGroup: onDeleteParentGroup,
                        onCardTap: onCardTap,
                        onCardDragStart: onCardDragStart,
                        onCardOpen: onCardOpen,
                        onParentCardOpen: onParentCardOpen,
                        allowsInlineEditing: allowsInlineEditing,
                        onInlineEditingChange: onInlineEditingChange,
                        onInlineCardEditCommit: onInlineCardEditCommit,
                        onCardMove: onCardMove,
                        onCardMoveSelection: onCardMoveSelection,
                        onMarqueeSelectionChange: onMarqueeSelectionChange,
                        onClearSelection: onClearSelection,
                        onScrollOffsetChange: onScrollOffsetChange,
                        onZoomScaleChange: onZoomScaleChange,
                        onViewportFinalize: onViewportFinalize,
                        onParentGroupMove: onParentGroupMove
                    )
                )
            }

            topOverlay
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .background(theme.boardBackground)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
    }

    private var topOverlay: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                workspaceStyleToolbarButton(systemName: "arrow.left", fontSize: 13, action: onClose)

                workspaceStyleToolbarButton(systemName: "minus", fontSize: 11) {
                    onZoomStep(-0.10)
                }
                .disabled(zoomScale <= IndexBoardZoom.minScale + 0.001)

                workspaceStyleToolbarButton(fontSize: 10, action: onZoomReset) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 10, weight: .bold))
                }
                .help("줌 100%")
                .disabled(abs(zoomScale - IndexBoardZoom.defaultScale) < 0.001)

                workspaceStyleToolbarButton(systemName: "plus", fontSize: 11) {
                    onZoomStep(0.10)
                }
                .disabled(zoomScale >= IndexBoardZoom.maxScale - 0.001)

                workspaceStyleToolbarButton(
                    systemName: "flag.fill",
                    foregroundColor: .orange,
                    action: onShowCheckpoint
                )
                workspaceStyleToolbarButton(
                    systemName: "clock.arrow.circlepath",
                    isActive: isHistoryVisible,
                    action: onToggleHistory
                )
                workspaceStyleToolbarButton(
                    systemName: "sparkles.tv",
                    isActive: isAIChatVisible,
                    action: onToggleAIChat
                )
                workspaceStyleToolbarButton(
                    systemName: isTimelineVisible ? "sidebar.right" : "sidebar.left",
                    isActive: isTimelineVisible,
                    action: onToggleTimeline
                )
            }
        }
        .padding(.horizontal, 18)
            .padding(.top, 2)
    }

    private func workspaceStyleToolbarButton(
        systemName: String,
        fontSize: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        workspaceStyleToolbarButton(fontSize: fontSize, action: action) {
            Image(systemName: systemName)
                .font(.system(size: fontSize, weight: .bold))
        }
    }

    private func workspaceStyleToolbarButton(
        systemName: String,
        fontSize: CGFloat = 14,
        isActive: Bool = false,
        foregroundColor: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        workspaceStyleToolbarButton(fontSize: fontSize, isActive: isActive, action: action) {
            Image(systemName: systemName)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(isActive ? Color.white : (foregroundColor ?? theme.primaryTextColor))
        }
    }

    private func workspaceStyleToolbarButton<Content: View>(
        fontSize: CGFloat,
        isActive: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background(
            Circle()
                .fill(isActive ? Color.accentColor : Color.clear)
        )
        .background(
            Circle()
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Circle()
                .stroke(
                    Color.white.opacity(theme.usesDarkAppearance ? 0.18 : 0.28),
                    lineWidth: 0.8
                )
        )
        .foregroundStyle(theme.primaryTextColor)
        .padding(.top, 2)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("표시할 카드가 없습니다.")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(theme.primaryTextColor)
            Text("빈 배경 더블클릭이나 N으로 임시 카드를 만들 수 있습니다.")
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
}
