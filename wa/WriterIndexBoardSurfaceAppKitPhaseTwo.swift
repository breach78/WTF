import SwiftUI
import AppKit
import os.signpost

private enum IndexBoardSurfaceAppKitConstants {
    static let laneChipHeight: CGFloat = 26
    static let laneChipSpacing: CGFloat = 6
    static let lineSpacing: CGFloat = 14
    static let detachedOuterPaddingSlots = 4
    static let surfaceHorizontalOverscan: CGFloat = 0
    static let surfaceVerticalOverscan: CGFloat = 0
    static let minimumCanvasLeadInset: CGFloat = 144
    static let minimumCanvasTopInset: CGFloat = 72
    static let laneWrapperInset: CGFloat = 7
    static let flowInteractionHorizontalInset: CGFloat = 88
    static let flowInteractionVerticalInset: CGFloat = 112
    static let flowInteractionVerticalHysteresis: CGFloat = 148
    static let flowInsertionHysteresis: CGFloat = 26
    static let autoScrollEdgeInset: CGFloat = 80
    static let maxAutoScrollStep: CGFloat = 22
    static let dragTickBudgetMilliseconds: Double = 4
    static let dragThreshold: CGFloat = 3
    static let previewLayoutAnimationDuration: TimeInterval = 0.16
    static let commitLayoutAnimationDuration: TimeInterval = 0.18
    static let overlayShadowRadius: CGFloat = 18
    static let overlayShadowYOffset: CGFloat = 10
    static let cardDropTargetHorizontalInset: CGFloat = 18
    static let cardDropTargetVerticalInset: CGFloat = 20
    static let cardDropRetentionHorizontalInset: CGFloat = 38
    static let cardDropRetentionVerticalInset: CGFloat = 34
    static let cardDropTerminalReach: CGFloat = 44
    static let detachedBlockTargetHorizontalInset: CGFloat = 26
    static let detachedBlockTargetVerticalInset: CGFloat = 28
    static let detachedStripInteractionHorizontalInset: CGFloat = 36
    static let detachedStripInteractionVerticalInset: CGFloat = 112
    static let detachedStripRetentionHorizontalInset: CGFloat = 52
    static let detachedStripRetentionVerticalInset: CGFloat = 156
    static let startAnchorWidth: CGFloat = 72
    static let startAnchorHeight: CGFloat = 26
    static let placeholderShadowRadius: CGFloat = 5
    static let placeholderShadowYOffset: CGFloat = 2
    static let placeholderHighlightInset: CGFloat = 5
    static let detachedIndicatorLineWidth: CGFloat = 3
    static let detachedParkingIndicatorLineWidth: CGFloat = 2
    static let hoverIndicatorInset: CGFloat = 4
    static let hoverIndicatorLineWidth: CGFloat = 1.5
}

private let indexBoardSurfaceAppKitSignpostLog = OSLog(
    subsystem: Bundle.main.bundleIdentifier ?? "com.riwoong.wa",
    category: "BoardMotion"
)

private enum IndexBoardSurfaceAppKitSignpostName {
    static let dragTick: StaticString = "drag_tick"
    static let resolvedDropTarget: StaticString = "resolved_drop_target"
    static let resolvedLocalCardPreview: StaticString = "resolved_local_card_drag_preview"
    static let resolvedLocalGroupPreview: StaticString = "resolved_local_group_drag_preview"
    static let applyCurrentLayout: StaticString = "apply_current_layout"
    static let updateIndicatorLayers: StaticString = "update_indicator_layers"
    static let updateOverlayLayers: StaticString = "update_overlay_layers"
}

@inline(__always)
private func withIndexBoardSurfaceAppKitSignpost<T>(
    _ name: StaticString,
    _ body: () -> T
) -> T {
    _ = name
    return body()
}

private struct IndexBoardSurfaceAppKitTimingMetric {
    var count = 0
    var totalDuration: CFTimeInterval = 0
    var maxDuration: CFTimeInterval = 0

    mutating func record(_ duration: CFTimeInterval) {
        count += 1
        totalDuration += duration
        maxDuration = max(maxDuration, duration)
    }

    var averageMilliseconds: Double {
        guard count > 0 else { return 0 }
        return (totalDuration / Double(count)) * 1000
    }

    var maxMilliseconds: Double {
        maxDuration * 1000
    }
}

private struct IndexBoardSurfaceAppKitBaselineSession {
    let kind: String
    let startedAt: Date
    let startedTimestamp: CFTimeInterval
    let orderedItemCountAtStart: Int
    let laneCountAtStart: Int
    let movingCardCountAtStart: Int
    var dragUpdateTickCount = 0
    var autoScrollTickCount = 0
    var retargetCount = 0
    var dragUpdateTiming = IndexBoardSurfaceAppKitTimingMetric()
    var resolvedDropTargetTiming = IndexBoardSurfaceAppKitTimingMetric()
    var resolvedLocalPreviewTiming = IndexBoardSurfaceAppKitTimingMetric()
    var applyCurrentLayoutTiming = IndexBoardSurfaceAppKitTimingMetric()
    var reconcileCardViewsTiming = IndexBoardSurfaceAppKitTimingMetric()
    var reconcileLaneChipViewsTiming = IndexBoardSurfaceAppKitTimingMetric()
    var updateIndicatorLayersTiming = IndexBoardSurfaceAppKitTimingMetric()
    var updateOverlayLayersTiming = IndexBoardSurfaceAppKitTimingMetric()
    var createdCardViews = 0
    var removedCardViews = 0
    var createdLaneChipViews = 0
    var removedLaneChipViews = 0
    var createdIndicatorLayers = 0
    var removedIndicatorLayers = 0
    var createdOverlayLayers = 0
    var removedOverlayLayers = 0
}

private struct IndexBoardSurfaceAppKitMotionScene {
    let rootLayer: CALayer
    let wrapperContainerLayer: CALayer
    let indicatorContainerLayer: CALayer
    let chipContainerLayer: CALayer
    let cardContainerLayer: CALayer
    var cardLayersByID: [UUID: CALayer]
    var chipLayersByLaneKey: [String: CALayer]
    var wrapperLayersByLaneKey: [String: CAShapeLayer]
    var sourceGapLayers: [CAShapeLayer]
    var targetIndicatorLayers: [CAShapeLayer]
}

private enum IndexBoardSurfaceAppKitBaselineLogger {
    static let logURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("wa_board_motion_baseline.log")

    static func append(session: IndexBoardSurfaceAppKitBaselineSession, didCommit: Bool) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let durationMilliseconds = (CFAbsoluteTimeGetCurrent() - session.startedTimestamp) * 1000
        let dragBudgetStatus =
            session.dragUpdateTiming.averageMilliseconds <= IndexBoardSurfaceAppKitConstants.dragTickBudgetMilliseconds ?
            "pass" :
            "warn"
        let retargetRate = session.dragUpdateTickCount > 0 ?
            Double(session.retargetCount) / Double(session.dragUpdateTickCount) :
            0
        let layerChurnCount =
            session.createdIndicatorLayers +
            session.removedIndicatorLayers +
            session.createdOverlayLayers +
            session.removedOverlayLayers

        func timingLine(_ name: String, _ metric: IndexBoardSurfaceAppKitTimingMetric) -> String {
            "\(name): count=\(metric.count) avg_ms=\(String(format: "%.3f", metric.averageMilliseconds)) max_ms=\(String(format: "%.3f", metric.maxMilliseconds))"
        }

        let lines = [
            "[BoardMotionBaseline] started_at=\(formatter.string(from: session.startedAt)) kind=\(session.kind) committed=\(didCommit)",
            "context: items=\(session.orderedItemCountAtStart) lanes=\(session.laneCountAtStart) moving_cards=\(session.movingCardCountAtStart) duration_ms=\(String(format: "%.3f", durationMilliseconds))",
            "ticks: drag=\(session.dragUpdateTickCount) autoscroll=\(session.autoScrollTickCount) retarget=\(session.retargetCount)",
            timingLine("drag_update", session.dragUpdateTiming),
            timingLine("resolved_drop_target", session.resolvedDropTargetTiming),
            timingLine("resolved_local_preview", session.resolvedLocalPreviewTiming),
            timingLine("apply_current_layout", session.applyCurrentLayoutTiming),
            timingLine("reconcile_card_views", session.reconcileCardViewsTiming),
            timingLine("reconcile_lane_chip_views", session.reconcileLaneChipViewsTiming),
            timingLine("update_indicator_layers", session.updateIndicatorLayersTiming),
            timingLine("update_overlay_layers", session.updateOverlayLayersTiming),
            "card_views: created=\(session.createdCardViews) removed=\(session.removedCardViews)",
            "lane_chip_views: created=\(session.createdLaneChipViews) removed=\(session.removedLaneChipViews)",
            "indicator_layers: created=\(session.createdIndicatorLayers) removed=\(session.removedIndicatorLayers)",
            "overlay_layers: created=\(session.createdOverlayLayers) removed=\(session.removedOverlayLayers)",
            "validation: drag_tick_budget_ms=\(String(format: "%.3f", IndexBoardSurfaceAppKitConstants.dragTickBudgetMilliseconds)) avg_drag_tick_ms=\(String(format: "%.3f", session.dragUpdateTiming.averageMilliseconds)) status=\(dragBudgetStatus)",
            "validation: retarget_rate=\(String(format: "%.3f", retargetRate)) layer_churn=\(layerChurnCount)",
            "---"
        ]
        let entry = lines.joined(separator: "\n") + "\n"
        guard let data = entry.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }
}

private struct IndexBoardSurfaceColorPreset {
    let name: String
    let hex: String
}

private let indexBoardSurfaceColorPresets: [IndexBoardSurfaceColorPreset] = [
    .init(name: "버터 옐로", hex: "#F4E6A6"),
    .init(name: "피치", hex: "#F6D0B1"),
    .init(name: "살구", hex: "#F3C5AE"),
    .init(name: "로즈", hex: "#EFC2D4"),
    .init(name: "라일락", hex: "#DCCDF3"),
    .init(name: "스카이", hex: "#CFE3F8"),
    .init(name: "민트", hex: "#CFE9DB"),
    .init(name: "세이지", hex: "#DCE5C2"),
    .init(name: "샌드", hex: "#E6D9C1"),
    .init(name: "포그", hex: "#D9DFE8")
]

private let indexBoardSurfaceDefaultColorToken = "__INDEX_BOARD_DEFAULT_COLOR__"

private func indexBoardSurfaceColorSwatchImage(
    hex: String?,
    defaultHex: String? = nil,
    usesDarkAppearance: Bool
) -> NSImage {
    let size = NSSize(width: 12, height: 12)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
    let path = NSBezierPath(ovalIn: rect)

    if let resolvedHex = hex ?? defaultHex,
       let rgb = parseHexRGB(resolvedHex) {
        NSColor(calibratedRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1).setFill()
        path.fill()
    } else {
        NSColor.clear.setFill()
        path.fill()
    }

    let strokeColor = usesDarkAppearance
        ? NSColor(calibratedWhite: 1, alpha: 0.42)
        : NSColor(calibratedWhite: 0, alpha: 0.28)
    strokeColor.setStroke()
    path.lineWidth = 1
    path.stroke()
    return image
}

private func indexBoardSurfaceAppKitSort(_ lhs: BoardSurfaceItem, _ rhs: BoardSurfaceItem) -> Bool {
    let lhsExplicitPosition = lhs.gridPosition ?? lhs.detachedGridPosition
    let rhsExplicitPosition = rhs.gridPosition ?? rhs.detachedGridPosition
    if let lhsExplicitPosition,
       let rhsExplicitPosition {
        if lhsExplicitPosition.row != rhsExplicitPosition.row {
            return lhsExplicitPosition.row < rhsExplicitPosition.row
        }
        if lhsExplicitPosition.column != rhsExplicitPosition.column {
            return lhsExplicitPosition.column < rhsExplicitPosition.column
        }
    } else if lhsExplicitPosition != nil {
        return true
    } else if rhsExplicitPosition != nil {
        return false
    }

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

private func indexBoardSurfaceLaneKey(_ laneParentID: UUID?) -> String {
    laneParentID?.uuidString ?? "root"
}

private func indexBoardSurfaceAppKitGroupSort(
    _ lhs: BoardSurfaceParentGroupPlacement,
    _ rhs: BoardSurfaceParentGroupPlacement
) -> Bool {
    if lhs.origin.row != rhs.origin.row {
        return lhs.origin.row < rhs.origin.row
    }
    if lhs.origin.column != rhs.origin.column {
        return lhs.origin.column < rhs.origin.column
    }
    return lhs.id.id < rhs.id.id
}

private struct IndexBoardSurfaceAppKitGridBounds {
    let minColumn: Int
    let maxColumn: Int
    let minRow: Int
    let maxRow: Int

    var columnCount: Int { max(1, maxColumn - minColumn + 1) }
    var rowCount: Int { max(1, maxRow - minRow + 1) }
}

private struct IndexBoardSurfaceAppKitSceneSnapshot {
    let projection: BoardSurfaceProjection
    let orderedItems: [BoardSurfaceItem]
    let cardFrameByID: [UUID: CGRect]
    let chipFrameByLaneKey: [String: CGRect]
    let occupiedGridPositionByCardID: [UUID: IndexBoardGridPosition]
    let logicalGridBounds: IndexBoardSurfaceAppKitGridBounds
}

private enum IndexBoardSurfaceAppKitDropPlacement: Equatable {
    case flow(Int)
    case detached(IndexBoardGridPosition)
}

private struct IndexBoardSurfaceAppKitDragState {
    let cardID: UUID
    let movingCardIDs: [UUID]
    let movingTempMembers: [IndexBoardTempStripMember]
    let sourceDetachedGridPositionsByCardID: [UUID: IndexBoardGridPosition]
    let sourcePlacement: IndexBoardSurfaceAppKitDropPlacement
    let sourceLaneParentID: UUID?
    let sourceTarget: IndexBoardCardDropTarget
    let initialFrame: CGRect
    let pointerOffset: CGSize
    var pointerInContent: CGPoint
    var dropPlacement: IndexBoardSurfaceAppKitDropPlacement
    var dropTarget: IndexBoardCardDropTarget

    var movingCardIDSet: Set<UUID> {
        Set(movingCardIDs)
    }

    func overlayOrigin() -> CGPoint {
        CGPoint(
            x: pointerInContent.x - pointerOffset.width,
            y: pointerInContent.y - pointerOffset.height
        )
    }
}

private enum IndexBoardSurfaceAppKitPlaceholderStyle {
    case flow
    case detachedSlot
    case detachedParking
}

private struct IndexBoardSurfaceAppKitSelectionState {
    let startPoint: CGPoint
    var currentPoint: CGPoint
}

private struct IndexBoardSurfaceAppKitViewportSession {
    let baselineMagnification: CGFloat
    let baselineScrollOrigin: CGPoint
    var liveMagnification: CGFloat
    var liveScrollOrigin: CGPoint
}

private struct IndexBoardSurfaceAppKitGroupDragState {
    let parentCardID: UUID
    let movingCardIDs: [UUID]
    let initialOrigin: IndexBoardGridPosition
    let initialFrame: CGRect
    let pointerOffset: CGSize
    var pointerInContent: CGPoint
    var targetOrigin: IndexBoardGridPosition

    func overlayOrigin() -> CGPoint {
        CGPoint(
            x: pointerInContent.x - pointerOffset.width,
            y: pointerInContent.y - pointerOffset.height
        )
    }
}

private struct IndexBoardSurfaceAppKitGroupDragPreview {
    let cardFramesByID: [UUID: CGRect]
    let targetFrame: CGRect?
}

private struct IndexBoardSurfaceAppKitConfiguration {
    let surfaceProjection: BoardSurfaceProjection
    let theme: IndexBoardRenderTheme
    let cardsByID: [UUID: SceneCard]
    let activeCardID: UUID?
    let selectedCardIDs: Set<UUID>
    let summaryByCardID: [UUID: IndexBoardResolvedSummary]
    let showsBackByCardID: [UUID: Bool]
    let canvasSize: CGSize
    let zoomScale: CGFloat
    let scrollOffset: CGPoint
    let revealCardID: UUID?
    let revealRequestToken: Int
    let isInteractionEnabled: Bool
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
    let onCardMove: (UUID, IndexBoardCardDropTarget) -> Void
    let onCardMoveSelection: ([UUID], UUID, IndexBoardCardDropTarget) -> Void
    let onMarqueeSelectionChange: (Set<UUID>) -> Void
    let onClearSelection: () -> Void
    let onScrollOffsetChange: (CGPoint) -> Void
    let onZoomScaleChange: (CGFloat) -> Void
    let onViewportFinalize: (CGFloat, CGPoint) -> Void
    let onParentGroupMove: (IndexBoardParentGroupDropTarget) -> Void
}

private struct IndexBoardSurfaceAppKitCardRenderState: Equatable {
    let content: String
    let colorHex: String?
    let cloneGroupID: UUID?
}

private struct IndexBoardSurfaceAppKitRenderState: Equatable {
    let surfaceProjection: BoardSurfaceProjection
    let cardRenderStateByID: [UUID: IndexBoardSurfaceAppKitCardRenderState]
    let activeCardID: UUID?
    let selectedCardIDs: Set<UUID>
    let summaryByCardID: [UUID: IndexBoardResolvedSummary]
    let showsBackByCardID: [UUID: Bool]
    let canvasSize: CGSize
    let zoomScale: CGFloat
    let scrollOffset: CGPoint
    let revealCardID: UUID?
    let revealRequestToken: Int
    let isInteractionEnabled: Bool
    let themeSignature: String

    func equalsIgnoringViewport(_ other: IndexBoardSurfaceAppKitRenderState) -> Bool {
        surfaceProjection == other.surfaceProjection &&
        cardRenderStateByID == other.cardRenderStateByID &&
        activeCardID == other.activeCardID &&
        selectedCardIDs == other.selectedCardIDs &&
        summaryByCardID == other.summaryByCardID &&
        showsBackByCardID == other.showsBackByCardID &&
        canvasSize == other.canvasSize &&
        revealCardID == other.revealCardID &&
        revealRequestToken == other.revealRequestToken &&
        isInteractionEnabled == other.isInteractionEnabled &&
        themeSignature == other.themeSignature
    }
}

private extension IndexBoardSurfaceAppKitConfiguration {
    var renderState: IndexBoardSurfaceAppKitRenderState {
        IndexBoardSurfaceAppKitRenderState(
            surfaceProjection: surfaceProjection,
            cardRenderStateByID: Dictionary(
                uniqueKeysWithValues: cardsByID.map { cardID, card in
                    (
                        cardID,
                        IndexBoardSurfaceAppKitCardRenderState(
                            content: card.content,
                            colorHex: card.colorHex,
                            cloneGroupID: card.cloneGroupID
                        )
                    )
                }
            ),
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
            themeSignature: theme.renderSignature
        )
    }
}

private struct IndexBoardSurfaceAppKitCardSnapshot {
    let cardID: UUID
    let image: NSImage
}

private struct IndexBoardSurfaceAppKitLaneChipModel {
    let lane: BoardSurfaceLane
    let theme: IndexBoardRenderTheme
    let displayText: String
    let tintColorToken: String?
}

extension IndexBoardSurfaceAppKitLaneChipModel: Equatable {
    static func == (
        lhs: IndexBoardSurfaceAppKitLaneChipModel,
        rhs: IndexBoardSurfaceAppKitLaneChipModel
    ) -> Bool {
        lhs.lane == rhs.lane &&
        lhs.displayText == rhs.displayText &&
        lhs.tintColorToken == rhs.tintColorToken &&
        lhs.theme.renderSignature == rhs.theme.renderSignature
    }
}

private extension CGFloat {
    var roundedToPixel: CGFloat { rounded(.toNearestOrAwayFromZero) }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

private extension CGRect {
    func insetBy(dx: CGFloat, dy: CGFloat, clampToPositive: Bool) -> CGRect {
        let inset = insetBy(dx: dx, dy: dy)
        guard clampToPositive else { return inset }
        return CGRect(
            x: inset.origin.x,
            y: inset.origin.y,
            width: max(0, inset.width),
            height: max(0, inset.height)
        )
    }
}

private func indexBoardThemeColor(
    theme: IndexBoardRenderTheme,
    customHex: String? = nil,
    isSelected: Bool = false,
    isActive: Bool = false
) -> NSColor {
    let baseHex = theme.usesDarkAppearance ? theme.darkCardBaseColorHex : theme.cardBaseColorHex
    let baseRGB = parseHexRGB(customHex ?? baseHex) ?? (theme.usesDarkAppearance ? (0.16, 0.17, 0.20) : (1.0, 1.0, 1.0))
    return NSColor(
        calibratedRed: baseRGB.0,
        green: baseRGB.1,
        blue: baseRGB.2,
        alpha: 1
    )
}

private func indexBoardThemeBorderColor(
    theme: IndexBoardRenderTheme,
    isSelected: Bool,
    isActive: Bool
) -> NSColor {
    let borderRGB = theme.resolvedGroupBorderRGB
    return NSColor(calibratedRed: borderRGB.0, green: borderRGB.1, blue: borderRGB.2, alpha: 0.78)
}

private func indexBoardThemePrimaryTextColor(theme: IndexBoardRenderTheme) -> NSColor {
    theme.usesDarkAppearance
        ? NSColor(calibratedWhite: 1, alpha: 0.92)
        : NSColor(calibratedWhite: 0, alpha: 0.82)
}

private func indexBoardThemeSecondaryTextColor(theme: IndexBoardRenderTheme) -> NSColor {
    theme.usesDarkAppearance
        ? NSColor(calibratedWhite: 1, alpha: 0.60)
        : NSColor(calibratedWhite: 0, alpha: 0.54)
}

private func indexBoardThemeBoardGradient(theme: IndexBoardRenderTheme) -> NSGradient {
    let startRGB = theme.resolvedBoardBackgroundStartRGB
    let endRGB = theme.resolvedBoardBackgroundEndRGB
    return NSGradient(
        starting: NSColor(calibratedRed: startRGB.0, green: startRGB.1, blue: startRGB.2, alpha: 1),
        ending: NSColor(calibratedRed: endRGB.0, green: endRGB.1, blue: endRGB.2, alpha: 1)
    )!
}

private func indexBoardThemeAccentColor(theme: IndexBoardRenderTheme) -> NSColor {
    let accentRGB = theme.resolvedAccentRGB
    return NSColor(calibratedRed: accentRGB.0, green: accentRGB.1, blue: accentRGB.2, alpha: 1)
}

private func indexBoardSurfaceResolvedPreviewText(
    card: SceneCard?,
    summary: IndexBoardResolvedSummary?
) -> String {
    if let summary, summary.hasSummary {
        let summaryText = summary.summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summaryText.isEmpty {
            return summaryText
        }
    }

    let contentText = card?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return contentText.isEmpty ? "내용 없음" : contentText
}

private func indexBoardSurfaceSingleLinePreview(_ text: String) -> String {
    let collapsed = text
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return collapsed.isEmpty ? "내용 없음" : collapsed
}

private final class IndexBoardSurfaceAppKitBackgroundView: NSView {
    var theme: IndexBoardRenderTheme {
        didSet {
            needsDisplay = true
        }
    }

    init(theme: IndexBoardRenderTheme) {
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        indexBoardThemeBoardGradient(theme: theme).draw(in: bounds, angle: -32)
    }
}

private final class IndexBoardSurfaceAppKitLaneChipView: NSView {
    private var model: IndexBoardSurfaceAppKitLaneChipModel?
    weak var interactionDelegate: IndexBoardSurfaceAppKitLaneChipInteractionDelegate?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        canDrawSubviewsIntoLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let parentCardID = model?.lane.parentCardID,
              let menu = interactionDelegate?.menuForLaneChip(parentCardID: parentCardID, event: event, in: self) else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let parentCardID = model?.lane.parentCardID else { return nil }
        return interactionDelegate?.menuForLaneChip(parentCardID: parentCardID, event: event, in: self)
    }

    override func mouseDown(with event: NSEvent) {
        guard let parentCardID = model?.lane.parentCardID else { return }
        interactionDelegate?.handleLaneChipMouseDown(parentCardID: parentCardID, event: event, in: self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let parentCardID = model?.lane.parentCardID else { return }
        interactionDelegate?.handleLaneChipMouseDragged(parentCardID: parentCardID, event: event, in: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard let parentCardID = model?.lane.parentCardID else { return }
        interactionDelegate?.handleLaneChipMouseUp(parentCardID: parentCardID, event: event, in: self)
    }

    func update(model: IndexBoardSurfaceAppKitLaneChipModel) {
        guard self.model != model || bounds.size != frame.size else { return }
        self.model = model
        needsDisplay = true
    }

    func snapshotImage() -> NSImage? {
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let model else { return }

        let boundsPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 11, yRadius: 11)
        let tint = resolvedTintColor(for: model)
        tint.withAlphaComponent(model.theme.usesDarkAppearance ? 0.16 : 0.10).setFill()
        boundsPath.fill()
        tint.withAlphaComponent(model.theme.usesDarkAppearance ? 0.40 : 0.22).setStroke()
        boundsPath.lineWidth = 1
        boundsPath.stroke()

        let labelFont = NSFont(name: "SansMonoCJKFinalDraft", size: 11) ?? NSFont.systemFont(ofSize: 11, weight: .semibold)
        let primaryTextColor = model.theme.usesDarkAppearance
            ? NSColor(calibratedWhite: 1, alpha: 0.92)
            : NSColor(calibratedWhite: 0, alpha: 0.82)
        let contentRect = bounds.insetBy(dx: 10, dy: 5)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail

        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: primaryTextColor,
            .paragraphStyle: paragraph
        ]
        let labelAttributed = NSAttributedString(string: model.displayText, attributes: labelAttributes)
        labelAttributed.draw(
            with: contentRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        )
    }

    private func resolvedTintColor(for model: IndexBoardSurfaceAppKitLaneChipModel) -> NSColor {
        if model.lane.isTempLane {
            return NSColor.orange.withAlphaComponent(model.theme.usesDarkAppearance ? 0.92 : 0.88)
        }
        if let token = model.tintColorToken ?? model.lane.colorToken,
           let rgb = parseHexRGB(token) {
            return NSColor(calibratedRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        }
        return indexBoardThemeAccentColor(theme: model.theme)
    }
}

private class IndexBoardSurfaceAppKitCardView: NSView {
    let cardID: UUID

    private var card: SceneCard?
    private var theme: IndexBoardRenderTheme?
    private var isSelected = false
    private var isActive = false
    private var summary: IndexBoardResolvedSummary?
    private var showsBack = false
    private var renderedContent = ""
    private var renderedColorHex: String?
    private var renderedCloneGroupID: UUID?

    init(cardID: UUID) {
        self.cardID = cardID
        super.init(frame: .zero)
        wantsLayer = true
        canDrawSubviewsIntoLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        card: SceneCard,
        theme: IndexBoardRenderTheme,
        isSelected: Bool,
        isActive: Bool,
        summary: IndexBoardResolvedSummary?,
        showsBack: Bool
    ) {
        let needsRefresh =
            self.card !== card ||
            self.theme?.renderSignature != theme.renderSignature ||
            self.isSelected != isSelected ||
            self.isActive != isActive ||
            self.summary != summary ||
            self.showsBack != showsBack ||
            bounds.size != IndexBoardMetrics.cardSize ||
            renderedContent != card.content ||
            renderedColorHex != card.colorHex ||
            renderedCloneGroupID != card.cloneGroupID

        self.card = card
        self.theme = theme
        self.isSelected = isSelected
        self.isActive = isActive
        self.summary = summary
        self.showsBack = showsBack
        renderedContent = card.content
        renderedColorHex = card.colorHex
        renderedCloneGroupID = card.cloneGroupID

        if frame.size != IndexBoardMetrics.cardSize {
            frame.size = IndexBoardMetrics.cardSize
        }

        if needsRefresh {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let card, let theme else { return }

        let cornerRadius = IndexBoardMetrics.cardCornerRadius
        let cardBounds = bounds.insetBy(dx: 0.5, dy: 0.5)
        let backgroundPath = NSBezierPath(roundedRect: cardBounds, xRadius: cornerRadius, yRadius: cornerRadius)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(theme.usesDarkAppearance ? 0.16 : 0.07)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = CGSize(width: 0, height: -4)
        shadow.set()
        indexBoardThemeColor(theme: theme, customHex: card.colorHex, isSelected: isSelected, isActive: isActive).setFill()
        backgroundPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        indexBoardThemeBorderColor(theme: theme, isSelected: isSelected, isActive: isActive).setStroke()
        backgroundPath.lineWidth = 1
        backgroundPath.stroke()

        let inset = IndexBoardMetrics.cardInnerPadding
        let contentRect = bounds.insetBy(dx: inset, dy: inset)
        let primaryTextColor = indexBoardThemePrimaryTextColor(theme: theme)
        let titleText = indexBoardSurfaceResolvedPreviewText(card: card, summary: summary)
        let bodyFont = NSFont(name: "SansMonoCJKFinalDraft", size: 13) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let textRect = contentRect

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributed = NSAttributedString(
            string: titleText,
            attributes: [
                .font: bodyFont,
                .foregroundColor: primaryTextColor,
                .paragraphStyle: paragraph
            ]
        )
        attributed.draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    func snapshotImage() -> NSImage? {
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }
}

private protocol IndexBoardSurfaceAppKitCardInteractionDelegate: AnyObject {
    func handleCardMouseDown(cardID: UUID, event: NSEvent, in view: NSView)
    func handleCardMouseDragged(cardID: UUID, event: NSEvent, in view: NSView)
    func handleCardMouseUp(cardID: UUID, event: NSEvent, in view: NSView)
}

private protocol IndexBoardSurfaceAppKitLaneChipInteractionDelegate: AnyObject {
    func menuForLaneChip(parentCardID: UUID, event: NSEvent, in view: NSView) -> NSMenu?
    func handleLaneChipMouseDown(parentCardID: UUID, event: NSEvent, in view: NSView)
    func handleLaneChipMouseDragged(parentCardID: UUID, event: NSEvent, in view: NSView)
    func handleLaneChipMouseUp(parentCardID: UUID, event: NSEvent, in view: NSView)
}

private final class IndexBoardSurfaceAppKitInteractiveCardView: IndexBoardSurfaceAppKitCardView {
    weak var interactionDelegate: IndexBoardSurfaceAppKitCardInteractionDelegate?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        interactionDelegate?.handleCardMouseDown(cardID: cardID, event: event, in: self)
    }

    override func mouseDragged(with event: NSEvent) {
        interactionDelegate?.handleCardMouseDragged(cardID: cardID, event: event, in: self)
    }

    override func mouseUp(with event: NSEvent) {
        interactionDelegate?.handleCardMouseUp(cardID: cardID, event: event, in: self)
    }
}

private final class IndexBoardSurfaceAppKitInlineTextView: NSTextView {
    var onPostInteraction: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        onPostInteraction?()
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onPostInteraction?()
    }
}

private final class IndexBoardSurfaceAppKitDocumentView: NSView, IndexBoardSurfaceAppKitCardInteractionDelegate, IndexBoardSurfaceAppKitLaneChipInteractionDelegate, NSTextViewDelegate {
    var configuration: IndexBoardSurfaceAppKitConfiguration
    private var lastRenderState: IndexBoardSurfaceAppKitRenderState

    weak var scrollView: NSScrollView?

    private var cardViews: [UUID: IndexBoardSurfaceAppKitInteractiveCardView] = [:]
    private var laneChipViews: [String: IndexBoardSurfaceAppKitLaneChipView] = [:]
    private var laneWrapperLayers: [String: CAShapeLayer] = [:]
    private let startAnchorLayer = CAShapeLayer()
    private let startAnchorTextLayer = CATextLayer()
    private let hoverIndicatorLayer = CAShapeLayer()
    private let selectionLayer = CAShapeLayer()
    private var sourceGapLayers: [CAShapeLayer] = []
    private var targetIndicatorLayers: [CAShapeLayer] = []
    private var focusIndicatorLayers: [CAShapeLayer] = []
    private var overlayLayers: [CALayer] = []
    private var cardFrameByID: [UUID: CGRect] = [:]
    private var chipFrameByLaneKey: [String: CGRect] = [:]
    private var presentationSurfaceProjection: BoardSurfaceProjection? = nil
    private var localCardDragPreviewFramesByID: [UUID: CGRect]? = nil
    private var localGroupDragPreviewFramesByID: [UUID: CGRect]? = nil
    private var localGroupDragTargetFrame: CGRect? = nil
    private var dragState: IndexBoardSurfaceAppKitDragState? = nil
    private var groupDragState: IndexBoardSurfaceAppKitGroupDragState? = nil
    private var selectionState: IndexBoardSurfaceAppKitSelectionState? = nil
    private var pendingBackgroundClickPoint: CGPoint? = nil
    private var pendingBackgroundGridPosition: IndexBoardGridPosition? = nil
    private var pendingBackgroundClickCount = 0
    private var pendingCardClick: (cardID: UUID, point: CGPoint, clickCount: Int)?
    private var pendingGroupClick: (parentCardID: UUID, point: CGPoint)?
    private var contextMenuCardID: UUID?
    private var contextMenuParentCardID: UUID?
    private var contextMenuParentGroupIsTemp = false
    private var dragSnapshots: [IndexBoardSurfaceAppKitCardSnapshot] = []
    private var groupDragSnapshot: NSImage? = nil
    private var restingSceneSnapshot: IndexBoardSurfaceAppKitSceneSnapshot? = nil
    private var motionScene: IndexBoardSurfaceAppKitMotionScene? = nil
    private var frozenLogicalGridBounds: IndexBoardSurfaceAppKitGridBounds? = nil
    private var pinnedLogicalGridOrigin: IndexBoardGridPosition? = nil
    private var lastRevealRequestToken: Int = 0
    private var autoScrollTimer: Timer?
    private var hoverTrackingArea: NSTrackingArea?
    private var hoverGridPosition: IndexBoardGridPosition?
    private var isHoverIndicatorSuppressed = false
    private var baselineSession: IndexBoardSurfaceAppKitBaselineSession? = nil
    private var inlineEditorScrollView: NSScrollView?
    private weak var inlineEditorTextView: NSTextView?
    private var inlineEditingCardID: UUID?
    private var inlineEditingOriginalContent = ""
    private var isEndingInlineEditing = false
    fileprivate var suppressViewportChangeNotifications = false
    fileprivate var pendingDropPreservedScrollOrigin: CGPoint? = nil
    fileprivate var defersLayoutForLiveViewport = false

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

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseMoved(with event: NSEvent) {
        guard configuration.isInteractionEnabled else {
            clearHoverIndicator()
            return
        }
        updateHoverIndicator(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        guard configuration.isInteractionEnabled else { return }
        updateHoverIndicator(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        clearHoverIndicator()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard configuration.isInteractionEnabled else { return nil }

        let point = convert(event.locationInWindow, from: nil)
        let targetLaneChipParentCardID = editableParentCardID(at: point)
        let targetCardID = targetLaneChipParentCardID == nil ? cardID(at: point) : nil
        let menu = NSMenu()

        if !configuration.selectedCardIDs.isEmpty {
            let createParentItem = NSMenuItem(
                title: "선택 카드로 새 부모 만들기",
                action: #selector(handleCreateParentFromSelectionMenuAction),
                keyEquivalent: ""
            )
            createParentItem.target = self
            menu.addItem(createParentItem)
        }

        contextMenuCardID = targetCardID
        contextMenuParentCardID = targetLaneChipParentCardID
        contextMenuParentGroupIsTemp = targetLaneChipParentCardID.flatMap { parentCardID in
            interactionProjection.parentGroups.first(where: { $0.parentCardID == parentCardID })?.isTempGroup
        } ?? false

        if let targetCardID,
           let card = configuration.cardsByID[targetCardID] {
            if !menu.items.isEmpty {
                menu.addItem(NSMenuItem.separator())
            }
            menu.addItem(
                makeColorMenuItem(
                    title: "카드 색상",
                    currentHex: card.colorHex,
                    action: #selector(handleSetCardColorMenuAction(_:))
                )
            )
        } else if let parentCardID = contextMenuParentCardID {
            if !menu.items.isEmpty {
                menu.addItem(NSMenuItem.separator())
            }
            let titleItem = NSMenuItem(title: "그룹 테두리 색상", action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            menu.addItem(titleItem)
            appendColorItems(
                to: menu,
                currentHex: resolvedParentGroupColorHex(parentCardID: parentCardID),
                action: #selector(handleSetGroupColorMenuAction(_:))
            )
        }

        if let parentCardID = contextMenuParentCardID,
           parentCardID != configuration.surfaceProjection.source.parentID {
            if !menu.items.isEmpty {
                menu.addItem(NSMenuItem.separator())
            }
            let tempToggleItem = NSMenuItem(
                title: contextMenuParentGroupIsTemp ? "컬럼으로 복귀" : "Temp로 보내기",
                action: #selector(handleToggleParentGroupTempMenuAction),
                keyEquivalent: ""
            )
            tempToggleItem.target = self
            tempToggleItem.representedObject = parentCardID
            menu.addItem(tempToggleItem)
        }

        if let targetCardID {
            if !menu.items.isEmpty {
                menu.addItem(NSMenuItem.separator())
            }
            let deleteItem = NSMenuItem(
                title: "삭제",
                action: #selector(handleDeleteCardMenuAction),
                keyEquivalent: ""
            )
            deleteItem.target = self
            deleteItem.representedObject = targetCardID
            menu.addItem(deleteItem)
        } else if let parentCardID = contextMenuParentCardID,
                  canDeleteParentGroup(parentCardID: parentCardID) {
            if !menu.items.isEmpty {
                menu.addItem(NSMenuItem.separator())
            }
            let deleteItem = NSMenuItem(
                title: "삭제",
                action: #selector(handleDeleteParentGroupMenuAction),
                keyEquivalent: ""
            )
            deleteItem.target = self
            deleteItem.representedObject = parentCardID
            menu.addItem(deleteItem)
        }

        return menu.items.isEmpty ? nil : menu
    }

    override func rightMouseDown(with event: NSEvent) {
        guard configuration.isInteractionEnabled else {
            super.rightMouseDown(with: event)
            return
        }

        if let menu = menu(for: event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }

        super.rightMouseDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard configuration.isInteractionEnabled else {
            super.mouseDown(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if let inlineEditorScrollView,
           !inlineEditorScrollView.isHidden,
           inlineEditorScrollView.frame.contains(point),
           let textView = inlineEditorTextView {
            window?.makeFirstResponder(textView)
            textView.mouseDown(with: event)
            return
        }
        endInlineEditing(commit: true)
        let backgroundGridPosition = resolvedHoverGridPositionCandidate(at: point)
        clearHoverIndicator()
        if let parentCardID = editableParentCardID(at: point) {
            pendingGroupClick = (parentCardID, point)
            pendingCardClick = nil
            pendingBackgroundClickPoint = nil
            pendingBackgroundGridPosition = nil
            pendingBackgroundClickCount = 0
            selectionState = nil
            updateSelectionLayer()
            return
        }
        if let cardID = cardID(at: point) {
            pendingCardClick = (cardID, point, event.clickCount)
            pendingGroupClick = nil
            pendingBackgroundClickPoint = nil
            pendingBackgroundGridPosition = nil
            pendingBackgroundClickCount = 0
            selectionState = nil
            updateSelectionLayer()
            return
        }
        if let parentCardID = movableParentGroupID(at: point) {
            pendingGroupClick = (parentCardID, point)
            pendingCardClick = nil
            pendingBackgroundClickPoint = nil
            pendingBackgroundGridPosition = nil
            pendingBackgroundClickCount = 0
            selectionState = nil
            updateSelectionLayer()
            return
        }
        pendingBackgroundClickPoint = point
        pendingBackgroundGridPosition = backgroundGridPosition
        pendingBackgroundClickCount = event.clickCount
        pendingCardClick = nil
        pendingGroupClick = nil
        selectionState = nil
        updateSelectionLayer()
    }

    override func mouseDragged(with event: NSEvent) {
        guard configuration.isInteractionEnabled else {
            super.mouseDragged(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        clearHoverIndicator()
        if let pendingCardClick {
            if dragState == nil, pendingCardClick.point.distance(to: location) < IndexBoardSurfaceAppKitConstants.dragThreshold {
                return
            }
            if dragState == nil {
                beginDrag(cardID: pendingCardClick.cardID, pointer: location)
            }
            guard var dragState, dragState.cardID == pendingCardClick.cardID else { return }
            recordBaselineDragTick(autoScrolled: false) {
                let previousTarget = dragState.dropTarget
                dragState.pointerInContent = location
                dragState.dropTarget = recordBaselineTiming(\.resolvedDropTargetTiming) {
                    resolvedDropTarget(for: dragState)
                }
                applyCardDragUpdate(dragState, previousTarget: previousTarget)
            }
            return
        }
        if let pendingGroupClick {
            if groupDragState == nil, pendingGroupClick.point.distance(to: location) < IndexBoardSurfaceAppKitConstants.dragThreshold {
                return
            }
            if groupDragState == nil {
                beginGroupDrag(parentCardID: pendingGroupClick.parentCardID, pointer: location)
            }
            guard var groupDragState, groupDragState.parentCardID == pendingGroupClick.parentCardID else { return }
            recordBaselineDragTick(autoScrolled: false) {
                let previousOrigin = groupDragState.targetOrigin
                groupDragState.pointerInContent = location
                groupDragState.targetOrigin = resolvedGroupDragOrigin(for: groupDragState)
                applyGroupDragUpdate(groupDragState, previousOrigin: previousOrigin)
            }
            return
        }

        guard let startPoint = pendingBackgroundClickPoint else {
            super.mouseDragged(with: event)
            return
        }
        if selectionState == nil, startPoint.distance(to: location) < IndexBoardSurfaceAppKitConstants.dragThreshold {
            return
        }

        if selectionState == nil {
            selectionState = IndexBoardSurfaceAppKitSelectionState(startPoint: startPoint, currentPoint: location)
        } else {
            selectionState?.currentPoint = location
        }
        guard let selectionRect = normalizedSelectionRect() else { return }
        let selectedCardIDs = resolvedSelectedCardIDs(in: selectionRect)
        configuration.onMarqueeSelectionChange(selectedCardIDs)
        updateSelectionLayer()
    }

    override func mouseUp(with event: NSEvent) {
        guard configuration.isInteractionEnabled else {
            super.mouseUp(with: event)
            return
        }

        if let pendingCardClick {
            defer {
                self.pendingCardClick = nil
            }
            if dragState?.cardID == pendingCardClick.cardID {
                endDrag(cardID: pendingCardClick.cardID)
                return
            }
            guard let card = configuration.cardsByID[pendingCardClick.cardID] else { return }
            if event.clickCount == 2 {
                configuration.onCardOpen(card)
            } else {
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let disallowedModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
                let canEnterInlineEdit =
                    configuration.allowsInlineEditing &&
                    flags.intersection(disallowedModifiers).isEmpty &&
                    configuration.activeCardID == card.id &&
                    configuration.selectedCardIDs == Set([card.id])
                if canEnterInlineEdit {
                    beginInlineEditing(cardID: card.id)
                    return
                } else {
                    configuration.onCardTap(card)
                }
            }
            window?.makeFirstResponder(self)
            return
        }
        if let pendingGroupClick {
            defer {
                self.pendingGroupClick = nil
            }
            if groupDragState?.parentCardID == pendingGroupClick.parentCardID {
                endGroupDrag(parentCardID: pendingGroupClick.parentCardID)
                return
            }
            if event.clickCount == 2 {
                configuration.onParentCardOpen(pendingGroupClick.parentCardID)
                return
            }
        }

        if selectionState != nil {
            selectionState = nil
            updateSelectionLayer()
        } else if pendingBackgroundClickCount == 2 {
            configuration.onCreateTempCardAt(pendingBackgroundGridPosition)
        } else {
            configuration.onClearSelection()
        }

        pendingBackgroundClickPoint = nil
        pendingBackgroundGridPosition = nil
        pendingBackgroundClickCount = 0
        window?.makeFirstResponder(self)
        refreshHoverIndicatorFromCurrentMouse()
    }

    override func keyDown(with event: NSEvent) {
        guard configuration.isInteractionEnabled else {
            super.keyDown(with: event)
            return
        }

        if inlineEditingCardID != nil {
            super.keyDown(with: event)
            return
        }

        guard configuration.allowsInlineEditing,
              let cardID = resolvedInlineEditableCardID() else {
            super.keyDown(with: event)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasDisallowedModifier = flags.contains(.command) || flags.contains(.control) || flags.contains(.option)
        if hasDisallowedModifier {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 36 || event.keyCode == 76 {
            beginInlineEditing(cardID: cardID)
            return
        }

        guard let characters = event.characters,
              !characters.isEmpty,
              characters.unicodeScalars.contains(where: { !CharacterSet.controlCharacters.contains($0) }) else {
            super.keyDown(with: event)
            return
        }

        beginInlineEditing(cardID: cardID, seedEvent: event)
    }

    override func layout() {
        super.layout()
        guard !defersLayoutForLiveViewport else { return }
        applyCurrentLayout(animationDuration: 0)
    }

    func updateConfiguration(_ configuration: IndexBoardSurfaceAppKitConfiguration) {
        let nextRenderState = configuration.renderState
        self.configuration = configuration
        selectionLayer.fillColor = indexBoardThemeAccentColor(theme: configuration.theme)
            .withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.14 : 0.10).cgColor
        selectionLayer.strokeColor = indexBoardThemeAccentColor(theme: configuration.theme)
            .withAlphaComponent(0.82).cgColor
        if !configuration.allowsInlineEditing {
            endInlineEditing(commit: true)
        } else if let inlineEditingCardID,
                  configuration.cardsByID[inlineEditingCardID] == nil {
            endInlineEditing(commit: false)
        }
        guard nextRenderState != lastRenderState else { return }
        lastRenderState = nextRenderState
        reconcilePresentationProjection()
        needsLayout = true
    }

    func updateConfigurationForViewportOnly(_ configuration: IndexBoardSurfaceAppKitConfiguration) {
        self.configuration = configuration
        self.lastRenderState = configuration.renderState
    }

    func refreshDisplayAfterLiveMagnify() {
        let contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = contentsScale
        startAnchorTextLayer.contentsScale = contentsScale
        needsDisplay = true

        for cardView in cardViews.values {
            cardView.layer?.contentsScale = contentsScale
            cardView.needsDisplay = true
        }

        for chipView in laneChipViews.values {
            chipView.layer?.contentsScale = contentsScale
            chipView.needsDisplay = true
        }

        displayIfNeeded()
    }

    @objc
    private func handleCreateParentFromSelectionMenuAction() {
        guard !configuration.selectedCardIDs.isEmpty else { return }
        configuration.onCreateParentFromSelection()
    }

    @objc
    private func handleToggleParentGroupTempMenuAction() {
        guard let parentCardID = contextMenuParentCardID else { return }
        configuration.onSetParentGroupTemp(parentCardID, !contextMenuParentGroupIsTemp)
    }

    @objc
    private func handleSetCardColorMenuAction(_ sender: NSMenuItem) {
        guard let cardID = contextMenuCardID else { return }
        configuration.onSetCardColor(cardID, resolvedContextMenuColorHex(from: sender.representedObject))
        refreshColorDependentPresentation()
    }

    @objc
    private func handleSetGroupColorMenuAction(_ sender: NSMenuItem) {
        guard let parentCardID = contextMenuParentCardID else { return }
        configuration.onSetCardColor(parentCardID, resolvedContextMenuColorHex(from: sender.representedObject))
        refreshColorDependentPresentation()
    }

    @objc
    private func handleDeleteCardMenuAction() {
        guard let cardID = contextMenuCardID else { return }
        configuration.onDeleteCard(cardID)
    }

    @objc
    private func handleDeleteParentGroupMenuAction() {
        guard let parentCardID = contextMenuParentCardID,
              canDeleteParentGroup(parentCardID: parentCardID) else { return }
        configuration.onDeleteParentGroup(parentCardID)
    }

    func ensureCardVisible(_ cardID: UUID?) {
        guard let cardID,
              let rect = cardFrameByID[cardID] else { return }
        scrollView?.contentView.scrollToVisible(rect.insetBy(dx: -36, dy: -28))
        scrollView?.reflectScrolledClipView(scrollView!.contentView)
    }

    fileprivate var isInteractingLocally: Bool {
        dragState != nil || groupDragState != nil
    }

    func refreshHoverIndicatorFromCurrentMouse() {
        guard configuration.isInteractionEnabled,
              !isHoverIndicatorSuppressed,
              dragState == nil,
              groupDragState == nil,
              selectionState == nil,
              let scrollView,
              let window else {
            clearHoverIndicator()
            return
        }
        let pointerInWindow = window.mouseLocationOutsideOfEventStream
        let pointerInScrollView = scrollView.convert(pointerInWindow, from: nil)
        guard scrollView.bounds.contains(pointerInScrollView) else {
            clearHoverIndicator()
            return
        }
        updateHoverIndicator(at: convert(pointerInWindow, from: nil))
    }

    func setHoverIndicatorSuppressed(_ suppressed: Bool) {
        isHoverIndicatorSuppressed = suppressed
        if suppressed {
            clearHoverIndicator()
        }
    }

    func handleCardMouseDown(cardID: UUID, event: NSEvent, in view: NSView) {
        guard configuration.isInteractionEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)
        pendingCardClick = (cardID, point, event.clickCount)
        pendingBackgroundClickPoint = nil
        pendingBackgroundGridPosition = nil
        pendingBackgroundClickCount = 0
    }

    func handleCardMouseDragged(cardID: UUID, event: NSEvent, in view: NSView) {
        guard configuration.isInteractionEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)

        if dragState == nil {
            guard let pendingCardClick, pendingCardClick.cardID == cardID else { return }
            if pendingCardClick.point.distance(to: point) < IndexBoardSurfaceAppKitConstants.dragThreshold {
                return
            }
            beginDrag(cardID: cardID, pointer: point)
        }

        guard var dragState, dragState.cardID == cardID else { return }
        recordBaselineDragTick(autoScrolled: false) {
            let previousTarget = dragState.dropTarget
            dragState.pointerInContent = point
            dragState.dropTarget = recordBaselineTiming(\.resolvedDropTargetTiming) {
                resolvedDropTarget(for: dragState)
            }
            applyCardDragUpdate(dragState, previousTarget: previousTarget)
        }
    }

    func handleCardMouseUp(cardID: UUID, event: NSEvent, in view: NSView) {
        guard configuration.isInteractionEnabled else { return }
        defer {
            pendingCardClick = nil
        }

        if dragState?.cardID == cardID {
            endDrag(cardID: cardID)
            return
        }

        guard let card = configuration.cardsByID[cardID] else { return }
        if event.clickCount == 2 {
            configuration.onCardOpen(card)
        } else {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let disallowedModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            let canEnterInlineEdit =
                configuration.allowsInlineEditing &&
                flags.intersection(disallowedModifiers).isEmpty &&
                configuration.activeCardID == card.id &&
                configuration.selectedCardIDs == Set([card.id])
            if canEnterInlineEdit {
                beginInlineEditing(cardID: card.id)
                return
            } else {
                configuration.onCardTap(card)
            }
        }
        window?.makeFirstResponder(self)
    }

    func textDidEndEditing(_ notification: Notification) {
        guard !isEndingInlineEditing else { return }
        endInlineEditing(commit: true)
    }

    func textDidChange(_ notification: Notification) {
        revealInlineEditorSelection()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        revealInlineEditorSelection()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) ||
            commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) ||
            commandSelector == #selector(NSResponder.insertLineBreak(_:)) {
            let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            if flags.contains(.shift) {
                textView.insertText("\n", replacementRange: textView.selectedRange())
                revealInlineEditorSelection()
            } else {
                endInlineEditing(commit: true)
                window?.makeFirstResponder(self)
            }
            return true
        }
        return false
    }

    private func resolvedInlineEditableCardID() -> UUID? {
        guard configuration.selectedCardIDs.count == 1,
              let cardID = configuration.selectedCardIDs.first,
              configuration.activeCardID == cardID,
              configuration.cardsByID[cardID] != nil else {
            return nil
        }
        return cardID
    }

    private func ensureInlineEditor() -> NSTextView {
        if let textView = inlineEditorTextView {
            return textView
        }

        let scrollView = NSScrollView()
        scrollView.wantsLayer = true
        scrollView.drawsBackground = true
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = IndexBoardSurfaceAppKitInlineTextView()
        textView.delegate = self
        textView.onPostInteraction = { [weak self] in
            self?.revealInlineEditorSelection()
        }
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.usesFindBar = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: IndexBoardMetrics.cardInnerPadding - 2, height: IndexBoardMetrics.cardInnerPadding - 2)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]

        if let textContainer = textView.textContainer {
            textContainer.lineFragmentPadding = 0
            textContainer.lineBreakMode = .byWordWrapping
            textContainer.maximumNumberOfLines = 0
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false
            textContainer.containerSize = CGSize(width: 1, height: CGFloat.greatestFiniteMagnitude)
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        textView.font = NSFont(name: "SansMonoCJKFinalDraft", size: 13) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = indexBoardThemePrimaryTextColor(theme: configuration.theme)
        textView.insertionPointColor = indexBoardThemePrimaryTextColor(theme: configuration.theme)
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = [
            .font: textView.font as Any,
            .foregroundColor: textView.textColor as Any,
            .paragraphStyle: paragraphStyle
        ]

        scrollView.documentView = textView
        scrollView.isHidden = true
        addSubview(scrollView)
        inlineEditorScrollView = scrollView
        inlineEditorTextView = textView
        return textView
    }

    private func updateInlineEditorAppearance(for card: SceneCard) {
        guard let scrollView = inlineEditorScrollView,
              let textView = inlineEditorTextView else { return }

        let isSelected = configuration.selectedCardIDs.contains(card.id)
        let isActive = configuration.activeCardID == card.id
        let backgroundColor = indexBoardThemeColor(
            theme: configuration.theme,
            customHex: card.colorHex,
            isSelected: isSelected,
            isActive: isActive
        )
        let borderColor = indexBoardThemeBorderColor(
            theme: configuration.theme,
            isSelected: isSelected,
            isActive: isActive
        )
        let primaryTextColor = indexBoardThemePrimaryTextColor(theme: configuration.theme)

        scrollView.backgroundColor = backgroundColor
        scrollView.layer?.backgroundColor = backgroundColor.cgColor
        scrollView.layer?.cornerRadius = IndexBoardMetrics.cardCornerRadius
        scrollView.layer?.borderWidth = 1
        scrollView.layer?.borderColor = borderColor.cgColor
        scrollView.layer?.masksToBounds = true
        textView.textColor = primaryTextColor
        textView.insertionPointColor = primaryTextColor
        textView.typingAttributes[.foregroundColor] = primaryTextColor
    }

    private func revealInlineEditorSelection() {
        guard let textView = inlineEditorTextView else { return }
        let selectedRange = textView.selectedRange()
        guard selectedRange.location != NSNotFound else { return }
        textView.scrollRangeToVisible(selectedRange)
    }

    private func beginInlineEditing(cardID: UUID, seedEvent: NSEvent? = nil) {
        guard configuration.allowsInlineEditing,
              let card = configuration.cardsByID[cardID],
              let frame = cardFrameByID[cardID] else { return }

        if inlineEditingCardID != cardID {
            endInlineEditing(commit: true)
        }

        let textView = ensureInlineEditor()
        inlineEditingCardID = cardID
        inlineEditingOriginalContent = card.content
        inlineEditorScrollView?.frame = frame
        inlineEditorScrollView?.isHidden = false
        inlineEditorScrollView?.alphaValue = 1
        configuration.onInlineEditingChange(true)
        updateInlineEditorAppearance(for: card)

        if textView.string != card.content {
            textView.string = card.content
        }
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        window?.makeFirstResponder(textView)
        revealInlineEditorSelection()

        if let seedEvent {
            textView.keyDown(with: seedEvent)
        }
    }

    private func endInlineEditing(commit: Bool) {
        guard let cardID = inlineEditingCardID else { return }
        isEndingInlineEditing = true
        defer {
            isEndingInlineEditing = false
        }

        let originalContent = inlineEditingOriginalContent
        let committedText = inlineEditorTextView?.string ?? originalContent
        inlineEditingCardID = nil
        inlineEditingOriginalContent = ""
        inlineEditorScrollView?.isHidden = true
        configuration.onInlineEditingChange(false)

        if commit, committedText != originalContent {
            configuration.onInlineCardEditCommit(cardID, committedText)
        }
    }

    private func layoutInlineEditorIfNeeded() {
        guard let inlineEditingCardID,
              let frame = cardFrameByID[inlineEditingCardID],
              let card = configuration.cardsByID[inlineEditingCardID] else {
            inlineEditorScrollView?.isHidden = true
            return
        }
        inlineEditorScrollView?.frame = frame
        inlineEditorScrollView?.isHidden = false
        updateInlineEditorAppearance(for: card)
    }

    func menuForLaneChip(parentCardID: UUID, event: NSEvent, in view: NSView) -> NSMenu? {
        guard configuration.isInteractionEnabled else { return nil }
        contextMenuCardID = nil
        contextMenuParentCardID = parentCardID
        contextMenuParentGroupIsTemp = contextMenuParentCardID.flatMap { resolvedParentCardID in
            interactionProjection.parentGroups.first(where: { $0.parentCardID == resolvedParentCardID })?.isTempGroup
        } ?? false

        let menu = NSMenu()
        if let parentCardID = contextMenuParentCardID {
            let titleItem = NSMenuItem(title: "그룹 테두리 색상", action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            menu.addItem(titleItem)
            appendColorItems(
                to: menu,
                currentHex: resolvedParentGroupColorHex(parentCardID: parentCardID),
                action: #selector(handleSetGroupColorMenuAction(_:))
            )
        }
        if let parentCardID = contextMenuParentCardID,
           parentCardID != configuration.surfaceProjection.source.parentID {
            if !menu.items.isEmpty {
                menu.addItem(NSMenuItem.separator())
            }
            let tempToggleItem = NSMenuItem(
                title: contextMenuParentGroupIsTemp ? "컬럼으로 복귀" : "Temp로 보내기",
                action: #selector(handleToggleParentGroupTempMenuAction),
                keyEquivalent: ""
            )
            tempToggleItem.target = self
            tempToggleItem.representedObject = parentCardID
            menu.addItem(tempToggleItem)
        }
        if canDeleteParentGroup(parentCardID: parentCardID) {
            if !menu.items.isEmpty {
                menu.addItem(NSMenuItem.separator())
            }
            let deleteItem = NSMenuItem(
                title: "삭제",
                action: #selector(handleDeleteParentGroupMenuAction),
                keyEquivalent: ""
            )
            deleteItem.target = self
            deleteItem.representedObject = parentCardID
            menu.addItem(deleteItem)
        }
        return menu.items.isEmpty ? nil : menu
    }

    func handleLaneChipMouseDown(parentCardID: UUID, event: NSEvent, in view: NSView) {
        guard configuration.isInteractionEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)
        clearHoverIndicator()
        pendingGroupClick = (parentCardID, point)
        pendingCardClick = nil
        pendingBackgroundClickPoint = nil
        pendingBackgroundGridPosition = nil
        pendingBackgroundClickCount = 0
        selectionState = nil
        updateSelectionLayer()
    }

    func handleLaneChipMouseDragged(parentCardID: UUID, event: NSEvent, in view: NSView) {
        guard configuration.isInteractionEnabled else { return }
        let location = convert(event.locationInWindow, from: nil)
        clearHoverIndicator()
        guard let pendingGroupClick, pendingGroupClick.parentCardID == parentCardID else { return }
        if groupDragState == nil, pendingGroupClick.point.distance(to: location) < IndexBoardSurfaceAppKitConstants.dragThreshold {
            return
        }
        if groupDragState == nil {
            beginGroupDrag(parentCardID: pendingGroupClick.parentCardID, pointer: location)
        }
        guard var groupDragState, groupDragState.parentCardID == pendingGroupClick.parentCardID else { return }
        recordBaselineDragTick(autoScrolled: false) {
            let previousOrigin = groupDragState.targetOrigin
            groupDragState.pointerInContent = location
            groupDragState.targetOrigin = resolvedGroupDragOrigin(for: groupDragState)
            applyGroupDragUpdate(groupDragState, previousOrigin: previousOrigin)
        }
    }

    func handleLaneChipMouseUp(parentCardID: UUID, event: NSEvent, in view: NSView) {
        guard configuration.isInteractionEnabled else { return }
        defer { pendingGroupClick = nil }

        if groupDragState?.parentCardID == parentCardID {
            endGroupDrag(parentCardID: parentCardID)
            return
        }

        if event.clickCount == 2 {
            configuration.onParentCardOpen(parentCardID)
        }
    }

    private var effectiveSurfaceProjection: BoardSurfaceProjection {
        presentationSurfaceProjection ?? configuration.surfaceProjection
    }

    private var interactionProjection: BoardSurfaceProjection {
        restingSceneSnapshot?.projection ?? effectiveSurfaceProjection
    }

    private var orderedItems: [BoardSurfaceItem] {
        effectiveSurfaceProjection.surfaceItems.sorted(by: indexBoardSurfaceAppKitSort)
    }

    private var hiddenCardIDs: Set<UUID> {
        Set((dragState?.movingCardIDs ?? []) + (groupDragState?.movingCardIDs ?? []))
    }

    private var interactionOrderedItems: [BoardSurfaceItem] {
        restingSceneSnapshot?.orderedItems ?? orderedItems
    }

    private var parentGroupByID: [BoardSurfaceParentGroupID: BoardSurfaceParentGroupPlacement] {
        Dictionary(uniqueKeysWithValues: effectiveSurfaceProjection.parentGroups.map { ($0.id, $0) })
    }

    private func parentGroup(for item: BoardSurfaceItem) -> BoardSurfaceParentGroupPlacement? {
        guard let parentGroupID = item.parentGroupID else { return nil }
        return parentGroupByID[parentGroupID]
    }

    private var flowItems: [BoardSurfaceItem] {
        orderedItems.filter { $0.parentGroupID != nil }
    }

    private var preferredColumns: Int {
        let availableWidth = max(
            IndexBoardMetrics.cardSize.width,
            configuration.canvasSize.width - (IndexBoardMetrics.boardHorizontalPadding * 2)
        )
        let slotWidth = IndexBoardMetrics.cardSize.width + IndexBoardMetrics.cardSpacing
        let fittedColumns = max(1, Int((availableWidth + IndexBoardMetrics.cardSpacing) / slotWidth))
        return min(max(1, orderedItems.count), fittedColumns)
    }

    private var slotSize: CGSize {
        CGSize(
            width: IndexBoardMetrics.cardSize.width,
            height: IndexBoardMetrics.cardSize.height +
                IndexBoardSurfaceAppKitConstants.laneChipHeight +
                IndexBoardSurfaceAppKitConstants.laneChipSpacing
        )
    }

    private var surfaceHorizontalInset: CGFloat {
        max(IndexBoardMetrics.boardHorizontalPadding, IndexBoardSurfaceAppKitConstants.minimumCanvasLeadInset)
    }

    private var surfaceTopInset: CGFloat {
        max(IndexBoardMetrics.boardVerticalPadding, IndexBoardSurfaceAppKitConstants.minimumCanvasTopInset)
    }

    private var surfaceBottomInset: CGFloat {
        IndexBoardMetrics.boardVerticalPadding
    }

    private var logicalGridBounds: IndexBoardSurfaceAppKitGridBounds {
        if let restingSceneSnapshot {
            return restingSceneSnapshot.logicalGridBounds
        }
        if let frozenLogicalGridBounds {
            return frozenLogicalGridBounds
        }
        return resolvedLogicalGridBounds(for: Array(occupiedGridPositionByCardID().values))
    }

    private func resolvedLogicalGridBounds(
        for positions: [IndexBoardGridPosition]
    ) -> IndexBoardSurfaceAppKitGridBounds {
        let computedBounds = resolvedUnpinnedLogicalGridBounds(for: positions)
        if pinnedLogicalGridOrigin == nil {
            pinnedLogicalGridOrigin = IndexBoardGridPosition(
                column: computedBounds.minColumn,
                row: computedBounds.minRow
            )
        }
        let pinnedOrigin = pinnedLogicalGridOrigin ?? IndexBoardGridPosition(
            column: computedBounds.minColumn,
            row: computedBounds.minRow
        )
        return IndexBoardSurfaceAppKitGridBounds(
            minColumn: pinnedOrigin.column,
            maxColumn: max(computedBounds.maxColumn, pinnedOrigin.column),
            minRow: pinnedOrigin.row,
            maxRow: max(computedBounds.maxRow, pinnedOrigin.row)
        )
    }

    private func resolvedUnpinnedLogicalGridBounds(
        for positions: [IndexBoardGridPosition]
    ) -> IndexBoardSurfaceAppKitGridBounds {
        let minColumn = positions.map(\.column).min() ?? 0
        let maxColumn = positions.map(\.column).max() ?? max(0, preferredColumns - 1)
        let minRow = positions.map(\.row).min() ?? 0
        let maxRow = positions.map(\.row).max() ?? 0
        return IndexBoardSurfaceAppKitGridBounds(
            minColumn: minColumn - IndexBoardSurfaceAppKitConstants.detachedOuterPaddingSlots,
            maxColumn: maxColumn + IndexBoardSurfaceAppKitConstants.detachedOuterPaddingSlots,
            minRow: minRow - IndexBoardSurfaceAppKitConstants.detachedOuterPaddingSlots,
            maxRow: maxRow + IndexBoardSurfaceAppKitConstants.detachedOuterPaddingSlots
        )
    }

    private func snapshotImage(in rect: CGRect) -> NSImage? {
        guard rect.width > 1, rect.height > 1 else { return nil }
        guard let rep = bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        cacheDisplay(in: rect, to: rep)
        let image = NSImage(size: rect.size)
        image.addRepresentation(rep)
        return image
    }

    private func makeRestingSceneSnapshot() -> IndexBoardSurfaceAppKitSceneSnapshot {
        let projection = effectiveSurfaceProjection
        let orderedItems = projection.surfaceItems.sorted(by: indexBoardSurfaceAppKitSort)
        let occupiedGridPositionByCardID = Dictionary(
            uniqueKeysWithValues: orderedItems.compactMap { item -> (UUID, IndexBoardGridPosition)? in
                guard let position = resolvedGridPosition(for: item) else { return nil }
                return (item.cardID, position)
            }
        )
        let logicalGridBounds = resolvedLogicalGridBounds(
            for: Array(occupiedGridPositionByCardID.values)
        )
        return IndexBoardSurfaceAppKitSceneSnapshot(
            projection: projection,
            orderedItems: orderedItems,
            cardFrameByID: cardFrameByID,
            chipFrameByLaneKey: chipFrameByLaneKey,
            occupiedGridPositionByCardID: occupiedGridPositionByCardID,
            logicalGridBounds: logicalGridBounds
        )
    }

    private func interactionCardFrame(for cardID: UUID) -> CGRect? {
        restingSceneSnapshot?.cardFrameByID[cardID] ?? cardFrameByID[cardID]
    }

    private func interactionChipFrame(for laneParentID: UUID?) -> CGRect {
        let laneKey = indexBoardSurfaceLaneKey(laneParentID)
        return restingSceneSnapshot?.chipFrameByLaneKey[laneKey]
            ?? chipFrameByLaneKey[laneKey]
            ?? .null
    }

    private func laneChipParentCardID(at point: CGPoint) -> UUID? {
        interactionProjection.parentGroups
            .compactMap { group -> (UUID, CGRect)? in
                guard let parentCardID = group.parentCardID else { return nil }
                let chipFrame = resolvedLaneChipHitFrame(for: parentCardID)
                guard !chipFrame.isNull else { return nil }
                return (parentCardID, chipFrame)
            }
            .filter { $0.1.contains(point) }
            .sorted { lhs, rhs in
                if lhs.1.minY != rhs.1.minY {
                    return lhs.1.minY < rhs.1.minY
                }
                if lhs.1.minX != rhs.1.minX {
                    return lhs.1.minX < rhs.1.minX
                }
                return lhs.0.uuidString < rhs.0.uuidString
            }
            .first?
            .0
    }

    private func editableParentCardID(at point: CGPoint) -> UUID? {
        interactionProjection.parentGroups
            .compactMap { group -> (UUID, CGRect)? in
                guard let parentCardID = group.parentCardID else { return nil }
                let hitFrame = resolvedEditableParentHeaderHitFrame(for: group)
                guard !hitFrame.isNull else { return nil }
                return (parentCardID, hitFrame)
            }
            .filter { $0.1.contains(point) }
            .sorted { lhs, rhs in
                if lhs.1.minY != rhs.1.minY {
                    return lhs.1.minY < rhs.1.minY
                }
                if lhs.1.minX != rhs.1.minX {
                    return lhs.1.minX < rhs.1.minX
                }
                return lhs.0.uuidString < rhs.0.uuidString
            }
            .first?
            .0
    }

    private func resolvedLaneChipHitFrame(for parentCardID: UUID?) -> CGRect {
        let chipFrame = interactionChipFrame(for: parentCardID)
        guard !chipFrame.isNull else { return .null }
        return chipFrame.insetBy(dx: -8, dy: -6)
    }

    private func resolvedEditableParentHeaderHitFrame(
        for group: BoardSurfaceParentGroupPlacement
    ) -> CGRect {
        guard let groupFrame = resolvedDisplayedParentGroupFrame(for: group) else { return .null }

        let chipFrame = resolvedLaneChipHitFrame(for: group.parentCardID)
        let bandX = groupFrame.minX + max(2, IndexBoardSurfaceAppKitConstants.laneWrapperInset - 2)
        let bandY = groupFrame.minY + 1
        let bandWidth = min(
            max(IndexBoardMetrics.cardSize.width + 12, chipFrame.isNull ? 0 : chipFrame.width + 12),
            max(IndexBoardMetrics.cardSize.width, groupFrame.width - 10)
        )
        let bandHeight = IndexBoardSurfaceAppKitConstants.laneChipHeight + (IndexBoardSurfaceAppKitConstants.laneWrapperInset * 2) + 4
        let headerBandFrame = CGRect(
            x: bandX,
            y: bandY,
            width: bandWidth,
            height: min(groupFrame.height, bandHeight)
        )

        guard !chipFrame.isNull else { return headerBandFrame }
        return headerBandFrame.union(chipFrame.insetBy(dx: -6, dy: -4))
    }

    private func resolvedCurrentCardFrames() -> [UUID: CGRect] {
        if let localCardDragPreviewFramesByID {
            var mergedFrames = restingSceneSnapshot?.cardFrameByID ?? cardFrameByID
            for (cardID, frame) in localCardDragPreviewFramesByID {
                mergedFrames[cardID] = frame
            }
            return mergedFrames
        }
        if let localGroupDragPreviewFramesByID {
            var mergedFrames = restingSceneSnapshot?.cardFrameByID ?? cardFrameByID
            for (cardID, frame) in localGroupDragPreviewFramesByID {
                mergedFrames[cardID] = frame
            }
            return mergedFrames
        }

        var nextCardFrames: [UUID: CGRect] = [:]
        nextCardFrames.reserveCapacity(orderedItems.count)
        for item in orderedItems {
            if let frame = resolvedCardFrame(for: item) {
                nextCardFrames[item.cardID] = frame
            }
        }
        return nextCardFrames
    }

    private func occupiedGridPositionByCardID() -> [UUID: IndexBoardGridPosition] {
        if let restingSceneSnapshot {
            return restingSceneSnapshot.occupiedGridPositionByCardID
        }
        var positionByCardID: [UUID: IndexBoardGridPosition] = [:]
        for item in orderedItems {
            guard let position = resolvedGridPosition(for: item) else { continue }
            positionByCardID[item.cardID] = position
        }
        return positionByCardID
    }

    private func resolvedGridPosition(for item: BoardSurfaceItem) -> IndexBoardGridPosition? {
        if let explicitGridPosition = item.gridPosition {
            return explicitGridPosition
        }
        if let detachedGridPosition = item.detachedGridPosition {
            return detachedGridPosition
        }
        guard let slotIndex = item.slotIndex else { return nil }
        return resolvedFlowGridPosition(for: slotIndex)
    }

    private func cardID(at point: CGPoint) -> UUID? {
        orderedItems.reversed().first { item in
            guard let frame = cardFrameByID[item.cardID] else { return false }
            return frame.contains(point)
        }?.cardID
    }

    private func resolvedTargetParentGroup(
        at point: CGPoint,
        excluding movingCardIDs: Set<UUID>
    ) -> BoardSurfaceParentGroupPlacement? {
        let candidateFrames = interactionProjection.parentGroups.compactMap { group -> (BoardSurfaceParentGroupPlacement, CGRect)? in
            let groupFrames = interactionOrderedItems.compactMap { item -> CGRect? in
                guard item.parentGroupID == group.id,
                      !movingCardIDs.contains(item.cardID),
                      let frame = interactionCardFrame(for: item.cardID) else { return nil }
                return frame
            }
            guard let firstFrame = groupFrames.first else { return nil }
            let cardUnion = groupFrames.dropFirst().reduce(firstFrame) { partial, frame in
                partial.union(frame)
            }
            let chipFrame = interactionChipFrame(for: group.parentCardID)
            let unionFrame = chipFrame.isNull ? cardUnion : cardUnion.union(chipFrame)
            return (group, unionFrame.insetBy(dx: -18, dy: -14))
        }

        return candidateFrames
            .filter { $0.1.contains(point) }
            .sorted { lhs, rhs in
                if lhs.1.minY != rhs.1.minY {
                    return lhs.1.minY < rhs.1.minY
                }
                if lhs.1.minX != rhs.1.minX {
                    return lhs.1.minX < rhs.1.minX
                }
                return lhs.0.id.id < rhs.0.id.id
            }
            .first?
            .0
    }

    private func resolvedCardDropTargetFrame(
        for group: BoardSurfaceParentGroupPlacement,
        visibleCardCount: Int
    ) -> CGRect {
        let cardCount = max(1, visibleCardCount)
        let startSlot = resolvedGridSlotRect(for: group.origin)
        let endSlot = resolvedGridSlotRect(
            for: IndexBoardGridPosition(
                column: group.origin.column + max(0, cardCount - 1),
                row: group.origin.row
            )
        )
        return CGRect(
            x: startSlot.minX - IndexBoardSurfaceAppKitConstants.cardDropTerminalReach,
            y: startSlot.minY + IndexBoardSurfaceAppKitConstants.laneChipHeight + IndexBoardSurfaceAppKitConstants.laneChipSpacing,
            width: (endSlot.maxX - startSlot.minX) + (IndexBoardSurfaceAppKitConstants.cardDropTerminalReach * 2),
            height: IndexBoardMetrics.cardSize.height
        )
    }

    private func resolvedCardDropTargetGroup(
        at point: CGPoint,
        for drag: IndexBoardSurfaceAppKitDragState
    ) -> BoardSurfaceParentGroupPlacement? {
        let visibleCardCountByGroupID = Dictionary(
            grouping: interactionProjection.surfaceItems.filter { item in
                item.parentGroupID != nil && !drag.movingCardIDSet.contains(item.cardID)
            },
            by: { $0.parentGroupID! }
        ).mapValues(\.count)

        let candidateGroups = interactionProjection.parentGroups

        if let retainedParentID = drag.dropTarget.laneParentID ?? drag.sourceLaneParentID,
           let retainedGroup = candidateGroups.first(where: { $0.parentCardID == retainedParentID }) {
            let retainedFrame = resolvedCardDropTargetFrame(
                for: retainedGroup,
                visibleCardCount: visibleCardCountByGroupID[retainedGroup.id] ?? retainedGroup.cardIDs.count
            ).insetBy(
                dx: -IndexBoardSurfaceAppKitConstants.cardDropRetentionHorizontalInset,
                dy: -IndexBoardSurfaceAppKitConstants.cardDropRetentionVerticalInset
            )
            if retainedFrame.contains(point) {
                return retainedGroup
            }
        }

        return candidateGroups
            .compactMap { group -> (BoardSurfaceParentGroupPlacement, CGRect)? in
                let frame = resolvedCardDropTargetFrame(
                    for: group,
                    visibleCardCount: visibleCardCountByGroupID[group.id] ?? group.cardIDs.count
                ).insetBy(
                    dx: -IndexBoardSurfaceAppKitConstants.cardDropTargetHorizontalInset,
                    dy: -IndexBoardSurfaceAppKitConstants.cardDropTargetVerticalInset
                )
                return (group, frame)
            }
            .filter { $0.1.contains(point) }
            .sorted { lhs, rhs in
                if lhs.1.minY != rhs.1.minY {
                    return lhs.1.minY < rhs.1.minY
                }
                if lhs.1.minX != rhs.1.minX {
                    return lhs.1.minX < rhs.1.minX
                }
                return lhs.0.id.id < rhs.0.id.id
            }
            .first?
            .0
    }

    private func movableParentGroupID(at point: CGPoint) -> UUID? {
        let candidateGroups = interactionProjection.parentGroups

        return candidateGroups
            .compactMap { group -> (UUID, CGRect)? in
                guard let parentCardID = group.parentCardID else { return nil }
                guard let handleFrame = resolvedParentGroupHandleFrame(for: group) else { return nil }
                return (
                    parentCardID,
                    handleFrame
                )
            }
            .filter { $0.1.contains(point) }
            .sorted { lhs, rhs in
                if lhs.1.minY != rhs.1.minY {
                    return lhs.1.minY < rhs.1.minY
                }
                if lhs.1.minX != rhs.1.minX {
                    return lhs.1.minX < rhs.1.minX
                }
                return lhs.0.uuidString < rhs.0.uuidString
            }
            .first?
            .0
    }

    private func resolvedParentGroupHandleFrame(
        for group: BoardSurfaceParentGroupPlacement
    ) -> CGRect? {
        guard let groupFrame = resolvedParentGroupFrame(for: group) else { return nil }
        let chipFrame = interactionChipFrame(for: group.parentCardID)
        if chipFrame.isNull {
            return CGRect(
                x: groupFrame.minX - 8,
                y: groupFrame.minY,
                width: groupFrame.width + 16,
                height: min(groupFrame.height, 34)
            )
        }
        return CGRect(
            x: groupFrame.minX - 8,
            y: chipFrame.minY - 6,
            width: groupFrame.width + 16,
            height: chipFrame.height + 12
        )
    }

    private func resolvedFlowGridPosition(for slotIndex: Int) -> IndexBoardGridPosition {
        let safeColumns = max(1, preferredColumns)
        return IndexBoardGridPosition(
            column: max(0, slotIndex) % safeColumns,
            row: max(0, slotIndex) / safeColumns
        )
    }

    private func resolvedGridSlotRect(for position: IndexBoardGridPosition) -> CGRect {
        let bounds = logicalGridBounds
        let normalizedColumn = position.column - bounds.minColumn
        let normalizedRow = position.row - bounds.minRow
        return CGRect(
            x: surfaceHorizontalInset + (CGFloat(normalizedColumn) * (slotSize.width + IndexBoardMetrics.cardSpacing)),
            y: surfaceTopInset + (CGFloat(normalizedRow) * (slotSize.height + IndexBoardSurfaceAppKitConstants.lineSpacing)),
            width: slotSize.width,
            height: slotSize.height
        )
    }

    private func resolvedFlowSlotRect(for slotIndex: Int) -> CGRect {
        resolvedGridSlotRect(for: resolvedFlowGridPosition(for: slotIndex))
    }

    private func resolvedCardFrame(for position: IndexBoardGridPosition) -> CGRect {
        let slotFrame = resolvedGridSlotRect(for: position)
        return CGRect(
            x: slotFrame.minX,
            y: slotFrame.minY + IndexBoardSurfaceAppKitConstants.laneChipHeight + IndexBoardSurfaceAppKitConstants.laneChipSpacing,
            width: IndexBoardMetrics.cardSize.width,
            height: IndexBoardMetrics.cardSize.height
        )
    }

    private func resolvedCardFrame(for item: BoardSurfaceItem) -> CGRect? {
        guard let gridPosition = resolvedGridPosition(for: item) else { return nil }
        return resolvedCardFrame(for: gridPosition)
    }

    private func resolvedFlowInteractionRect(
        slotCount: Int,
        usesVerticalHysteresis: Bool = false
    ) -> CGRect? {
        let safeSlotCount = max(1, slotCount + 1)
        let cardFrames = (0..<safeSlotCount).map { index in
            let slotFrame = resolvedFlowSlotRect(for: index)
            return CGRect(
                x: slotFrame.minX,
                y: slotFrame.minY + IndexBoardSurfaceAppKitConstants.laneChipHeight + IndexBoardSurfaceAppKitConstants.laneChipSpacing,
                width: IndexBoardMetrics.cardSize.width,
                height: IndexBoardMetrics.cardSize.height
            )
        }
        guard let firstFrame = cardFrames.first else { return nil }
        let union = cardFrames.dropFirst().reduce(firstFrame) { partial, frame in
            partial.union(frame)
        }
        return union.insetBy(
            dx: -IndexBoardSurfaceAppKitConstants.flowInteractionHorizontalInset,
            dy: -(usesVerticalHysteresis
                ? IndexBoardSurfaceAppKitConstants.flowInteractionVerticalHysteresis
                : IndexBoardSurfaceAppKitConstants.flowInteractionVerticalInset)
        )
    }

    private func resolvedFlowDropSlotIndex(for point: CGPoint, slotCount: Int) -> Int {
        let safeSlotCount = max(1, slotCount + 1)
        var bestIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for slotIndex in 0..<safeSlotCount {
            let slotFrame = resolvedFlowSlotRect(for: slotIndex)
            let frame = CGRect(
                x: slotFrame.minX,
                y: slotFrame.minY + IndexBoardSurfaceAppKitConstants.laneChipHeight + IndexBoardSurfaceAppKitConstants.laneChipSpacing,
                width: IndexBoardMetrics.cardSize.width,
                height: IndexBoardMetrics.cardSize.height
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

    private func resolvedFlowInsertionSlotCenterX(
        for group: BoardSurfaceParentGroupPlacement,
        insertionIndex: Int
    ) -> CGFloat {
        resolvedCardFrame(
            for: IndexBoardGridPosition(
                column: group.origin.column + max(0, insertionIndex),
                row: group.origin.row
            )
        ).midX
    }

    private func resolvedRetainedFlowInsertionIndex(
        for group: BoardSurfaceParentGroupPlacement,
        visibleItemCount: Int,
        point: CGPoint,
        drag: IndexBoardSurfaceAppKitDragState
    ) -> Int? {
        guard drag.dropTarget.detachedGridPosition == nil,
              !drag.dropTarget.isTempStripTarget,
              drag.dropTarget.laneParentID == group.parentCardID else {
            return nil
        }

        let retainedIndex = min(max(0, drag.dropTarget.insertionIndex), visibleItemCount)
        let currentCenterX = resolvedFlowInsertionSlotCenterX(for: group, insertionIndex: retainedIndex)
        let lowerBoundaryX: CGFloat = {
            guard retainedIndex > 0 else { return -.greatestFiniteMagnitude }
            let previousCenterX = resolvedFlowInsertionSlotCenterX(
                for: group,
                insertionIndex: retainedIndex - 1
            )
            return ((previousCenterX + currentCenterX) / 2) - IndexBoardSurfaceAppKitConstants.flowInsertionHysteresis
        }()
        let upperBoundaryX: CGFloat = {
            guard retainedIndex < visibleItemCount else { return .greatestFiniteMagnitude }
            let nextCenterX = resolvedFlowInsertionSlotCenterX(
                for: group,
                insertionIndex: retainedIndex + 1
            )
            return ((currentCenterX + nextCenterX) / 2) + IndexBoardSurfaceAppKitConstants.flowInsertionHysteresis
        }()

        return (point.x >= lowerBoundaryX && point.x <= upperBoundaryX) ? retainedIndex : nil
    }

    private func resolvedNearestGridPosition(for point: CGPoint) -> IndexBoardGridPosition {
        let bounds = logicalGridBounds
        let columnStep = slotSize.width + IndexBoardMetrics.cardSpacing
        let rowStep = slotSize.height + IndexBoardSurfaceAppKitConstants.lineSpacing
        let rawColumn = Int(((point.x - surfaceHorizontalInset - (slotSize.width / 2)) / columnStep).rounded())
        let rawRow = Int(((point.y - surfaceTopInset - (slotSize.height / 2)) / rowStep).rounded())
        let clampedColumn = min(max(0, rawColumn), bounds.columnCount - 1)
        let clampedRow = min(max(0, rawRow), bounds.rowCount - 1)
        return IndexBoardGridPosition(
            column: bounds.minColumn + clampedColumn,
            row: bounds.minRow + clampedRow
        )
    }

    private func resolvedDetachedGridPosition(for point: CGPoint, excluding excludedCardIDs: Set<UUID>) -> IndexBoardGridPosition {
        let candidate = resolvedNearestGridPosition(for: point)
        let occupiedPositions = Set(
            occupiedGridPositionByCardID().compactMap { entry -> IndexBoardGridPosition? in
                excludedCardIDs.contains(entry.key) ? nil : entry.value
            }
        )
        guard occupiedPositions.contains(candidate) else { return candidate }

        let bounds = logicalGridBounds
        let maxRadius = max(bounds.columnCount, bounds.rowCount)
        for radius in 1...maxRadius {
            var candidates: [IndexBoardGridPosition] = []
            for row in (candidate.row - radius)...(candidate.row + radius) {
                for column in (candidate.column - radius)...(candidate.column + radius) {
                    let rowDelta = abs(row - candidate.row)
                    let columnDelta = abs(column - candidate.column)
                    guard max(rowDelta, columnDelta) == radius else { continue }
                    guard row >= bounds.minRow,
                          row <= bounds.maxRow,
                          column >= bounds.minColumn,
                          column <= bounds.maxColumn else {
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

    private func stationaryParentGroups(
        excluding excludedCardIDs: Set<UUID>
    ) -> [BoardSurfaceParentGroupPlacement] {
        indexBoardSurfaceStationaryParentGroups(
            from: effectiveSurfaceProjection.parentGroups,
            excluding: excludedCardIDs
        )
    }

    private func stationaryDetachedPositions(
        excluding excludedCardIDs: Set<UUID>
    ) -> [UUID: IndexBoardGridPosition] {
        Dictionary(uniqueKeysWithValues: orderedItems.compactMap { item -> (UUID, IndexBoardGridPosition)? in
            guard item.parentGroupID == nil,
                  !excludedCardIDs.contains(item.cardID),
                  let position = item.detachedGridPosition ?? item.gridPosition else {
                return nil
            }
            return (item.cardID, position)
        })
    }

    private func referenceDetachedPositions() -> [UUID: IndexBoardGridPosition] {
        Dictionary(uniqueKeysWithValues: configuration.surfaceProjection.surfaceItems.compactMap { item -> (UUID, IndexBoardGridPosition)? in
            guard item.parentGroupID == nil,
                  let position = item.detachedGridPosition ?? item.gridPosition else {
                return nil
            }
            return (item.cardID, position)
        })
    }

    private func referenceTempStrips() -> [IndexBoardTempStripState] {
        configuration.surfaceProjection.tempStrips
    }

    private func tempLaneParentID() -> UUID? {
        configuration.surfaceProjection.lanes.first(where: \.isTempLane)?.parentCardID
    }

    private func resolvedTempGroupWidthsByParentID(
        from projection: BoardSurfaceProjection
    ) -> [UUID: Int] {
        Dictionary(
            uniqueKeysWithValues: projection.parentGroups.compactMap { placement in
                guard placement.isTempGroup,
                      let parentCardID = placement.parentCardID else {
                    return nil
                }
                return (parentCardID, placement.width)
            }
        )
    }

    private func resolvedTempStripMemberWidth(
        _ member: IndexBoardTempStripMember,
        widthsByParentID: [UUID: Int]
    ) -> Int {
        switch member.kind {
        case .card:
            return 1
        case .group:
            return max(1, widthsByParentID[member.id] ?? 1)
        }
    }

    private func resolvedTempStripSlotDescriptors(
        for strip: IndexBoardTempStripState,
        widthsByParentID: [UUID: Int]
    ) -> [(column: Int, previous: IndexBoardTempStripMember?, next: IndexBoardTempStripMember?)] {
        var descriptors: [(column: Int, previous: IndexBoardTempStripMember?, next: IndexBoardTempStripMember?)] = []
        var cursor = strip.anchorColumn
        descriptors.append((cursor, nil, strip.members.first))

        for (index, member) in strip.members.enumerated() {
            cursor += resolvedTempStripMemberWidth(member, widthsByParentID: widthsByParentID)
            let nextMember = index + 1 < strip.members.count ? strip.members[index + 1] : nil
            descriptors.append((cursor, member, nextMember))
        }

        return descriptors
    }

    private func resolvedTempStripBandFrame(
        for strip: IndexBoardTempStripState,
        widthsByParentID: [UUID: Int],
        movingSlotCount: Int
    ) -> CGRect? {
        let stripWidth = strip.members.reduce(0) { partialResult, member in
            partialResult + resolvedTempStripMemberWidth(member, widthsByParentID: widthsByParentID)
        }
        return resolvedDetachedBlockFrame(
            row: strip.row,
            anchorColumn: strip.anchorColumn,
            slotCount: max(1, stripWidth + movingSlotCount)
        )
    }

    private func resolvedDetachedBlockFrame(
        row: Int,
        anchorColumn: Int,
        slotCount: Int
    ) -> CGRect? {
        guard slotCount > 0 else { return nil }
        let elementFrames = (0..<slotCount).map { offset in
            resolvedCardFrame(
                for: IndexBoardGridPosition(
                    column: anchorColumn + offset,
                    row: row
                )
            )
        }
        guard let firstFrame = elementFrames.first else { return nil }
        return elementFrames.dropFirst().reduce(firstFrame) { partial, frame in
            partial.union(frame)
        }.insetBy(
            dx: -IndexBoardSurfaceAppKitConstants.detachedBlockTargetHorizontalInset,
            dy: -IndexBoardSurfaceAppKitConstants.detachedBlockTargetVerticalInset
        )
    }

    private func resolvedDetachedSlotFrames(
        row: Int,
        anchorColumn: Int,
        slotCount: Int
    ) -> [CGRect] {
        guard slotCount > 0 else { return [] }
        return (0..<slotCount).map { offset in
            resolvedCardFrame(
                for: IndexBoardGridPosition(
                    column: anchorColumn + offset,
                    row: row
                )
            )
        }
    }

    private func resolvedDetachedBlockDropTarget(
        at point: CGPoint,
        for drag: IndexBoardSurfaceAppKitDragState
    ) -> IndexBoardCardDropTarget? {
        let compactedStrips = resolvedIndexBoardTempStripsAfterRemovingMembers(
            strips: referenceTempStrips(),
            movingMembers: drag.movingTempMembers
        )
        let widthsByParentID = resolvedTempGroupWidthsByParentID(from: configuration.surfaceProjection)

        struct Candidate {
            let target: IndexBoardCardDropTarget
            let retained: Bool
            let distance: CGFloat
        }

        var bestCandidate: Candidate?
        let retainedStripID: String? = {
            let retainedPreviousMember = drag.dropTarget.previousTempMember ?? drag.sourceTarget.previousTempMember
            let retainedNextMember = drag.dropTarget.nextTempMember ?? drag.sourceTarget.nextTempMember
            return compactedStrips.first { strip in
                if let retainedPreviousMember, strip.members.contains(retainedPreviousMember) {
                    return true
                }
                if let retainedNextMember, strip.members.contains(retainedNextMember) {
                    return true
                }
                return false
            }?.id
        }()

        for strip in compactedStrips {
            guard let bandFrame = resolvedTempStripBandFrame(
                for: strip,
                widthsByParentID: widthsByParentID,
                movingSlotCount: max(1, drag.movingTempMembers.count)
            ) else {
                continue
            }
            let isRetainedStrip = strip.id == retainedStripID
            let interactionFrame = bandFrame.insetBy(
                dx: -(isRetainedStrip
                    ? IndexBoardSurfaceAppKitConstants.detachedStripRetentionHorizontalInset
                    : IndexBoardSurfaceAppKitConstants.detachedStripInteractionHorizontalInset),
                dy: -(isRetainedStrip
                    ? IndexBoardSurfaceAppKitConstants.detachedStripRetentionVerticalInset
                    : IndexBoardSurfaceAppKitConstants.detachedStripInteractionVerticalInset)
            )
            guard interactionFrame.contains(point) else {
                continue
            }

            let slotDescriptors = resolvedTempStripSlotDescriptors(
                for: strip,
                widthsByParentID: widthsByParentID
            )
            guard let bestSlot = slotDescriptors.min(by: { lhs, rhs in
                let lhsDistance = abs(resolvedCardFrame(
                    for: IndexBoardGridPosition(column: lhs.column, row: strip.row)
                ).midX - point.x)
                let rhsDistance = abs(resolvedCardFrame(
                    for: IndexBoardGridPosition(column: rhs.column, row: strip.row)
                ).midX - point.x)
                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }
                return lhs.column < rhs.column
            }) else {
                continue
            }

            let previousCardID = bestSlot.previous?.kind == .card ? bestSlot.previous?.id : nil
            let nextCardID = bestSlot.next?.kind == .card ? bestSlot.next?.id : nil
            let slotFrame = resolvedCardFrame(
                for: IndexBoardGridPosition(column: bestSlot.column, row: strip.row)
            )
            let distance = abs(slotFrame.midX - point.x) + (abs(slotFrame.midY - point.y) * 0.35)
            let target = IndexBoardCardDropTarget(
                groupID: legacyGroupID(for: tempLaneParentID() ?? drag.sourceLaneParentID),
                insertionIndex: 0,
                laneParentID: tempLaneParentID() ?? drag.sourceLaneParentID,
                previousCardID: previousCardID,
                nextCardID: nextCardID,
                previousTempMember: bestSlot.previous,
                nextTempMember: bestSlot.next,
                preferredColumnCount: nil
            )

            if let currentBest = bestCandidate {
                if isRetainedStrip != currentBest.retained {
                    if isRetainedStrip {
                        bestCandidate = Candidate(target: target, retained: isRetainedStrip, distance: distance)
                    }
                } else if distance < currentBest.distance {
                    bestCandidate = Candidate(target: target, retained: isRetainedStrip, distance: distance)
                }
            } else {
                bestCandidate = Candidate(target: target, retained: isRetainedStrip, distance: distance)
            }
        }

        return bestCandidate?.target
    }

    private func resolvedMovingItems(for draggedCardID: UUID) -> [BoardSurfaceItem] {
        guard configuration.selectedCardIDs.count > 1,
              configuration.selectedCardIDs.contains(draggedCardID) else {
            return orderedItems.filter { $0.cardID == draggedCardID }
        }
        let selectedItems = orderedItems.filter { configuration.selectedCardIDs.contains($0.cardID) }
        return selectedItems.isEmpty ? orderedItems.filter { $0.cardID == draggedCardID } : selectedItems
    }

    private func sourceTarget(for movingItems: [BoardSurfaceItem], primaryItem: BoardSurfaceItem) -> IndexBoardCardDropTarget {
        guard movingItems.count > 1 else {
            return sourceTarget(for: primaryItem)
        }

        let movingCardIDs = Set(movingItems.map(\.cardID))
        let groupedMovingItems = movingItems
            .filter { $0.parentGroupID == primaryItem.parentGroupID }
            .sorted(by: indexBoardSurfaceAppKitSort)

        if let firstGroupedItem = groupedMovingItems.first,
           let parentGroup = parentGroup(for: firstGroupedItem) {
            let visibleItems = orderedItems.filter { item in
                item.parentGroupID == parentGroup.id && !movingCardIDs.contains(item.cardID)
            }
            let insertionIndex = visibleItems.filter { item in
                guard let itemPosition = item.gridPosition,
                      let firstPosition = firstGroupedItem.gridPosition else { return false }
                return itemPosition.column < firstPosition.column
            }.count
            let previousCardID = visibleItems.prefix(insertionIndex).last?.cardID
            let nextCardID = insertionIndex < visibleItems.count ? visibleItems[insertionIndex].cardID : nil
            return IndexBoardCardDropTarget(
                groupID: legacyGroupID(for: parentGroup.parentCardID),
                insertionIndex: insertionIndex,
                laneParentID: parentGroup.parentCardID,
                previousCardID: previousCardID,
                nextCardID: nextCardID,
                preferredColumnCount: nil
            )
        }

        return sourceTarget(for: primaryItem)
    }

    private func sourceTarget(for item: BoardSurfaceItem) -> IndexBoardCardDropTarget {
        if item.parentGroupID == nil,
           let detachedGridPosition = item.detachedGridPosition ?? item.gridPosition {
            if let sourceStrip = configuration.surfaceProjection.tempStrips.first(where: { strip in
                strip.members.contains(IndexBoardTempStripMember(kind: .card, id: item.cardID))
            }),
               let memberIndex = sourceStrip.members.firstIndex(of: IndexBoardTempStripMember(kind: .card, id: item.cardID)) {
                let previousMember = memberIndex > 0 ? sourceStrip.members[memberIndex - 1] : nil
                let nextMember = memberIndex + 1 < sourceStrip.members.count ? sourceStrip.members[memberIndex + 1] : nil
                return IndexBoardCardDropTarget(
                    groupID: legacyGroupID(for: tempLaneParentID() ?? item.laneParentID),
                    insertionIndex: 0,
                    laneParentID: tempLaneParentID() ?? item.laneParentID,
                    previousCardID: previousMember?.kind == .card ? previousMember?.id : nil,
                    nextCardID: nextMember?.kind == .card ? nextMember?.id : nil,
                    previousTempMember: previousMember,
                    nextTempMember: nextMember,
                    preferredColumnCount: nil
                )
            }

            return IndexBoardCardDropTarget(
                groupID: legacyGroupID(for: tempLaneParentID() ?? item.laneParentID),
                insertionIndex: 0,
                laneParentID: tempLaneParentID() ?? item.laneParentID,
                detachedGridPosition: detachedGridPosition,
                preferredColumnCount: nil
            )
        }

        let group = parentGroup(for: item)
        let groupItems = orderedItems.filter { $0.parentGroupID == item.parentGroupID }.sorted(by: indexBoardSurfaceAppKitSort)
        let insertionIndex = groupItems.firstIndex(where: { $0.cardID == item.cardID }) ?? 0
        let previousCardID = insertionIndex > 0 ? groupItems[insertionIndex - 1].cardID : nil
        let nextCardID = insertionIndex + 1 < groupItems.count ? groupItems[insertionIndex + 1].cardID : nil
        return IndexBoardCardDropTarget(
            groupID: legacyGroupID(for: group?.parentCardID ?? item.laneParentID),
            insertionIndex: insertionIndex,
            laneParentID: group?.parentCardID ?? item.laneParentID,
            previousCardID: previousCardID,
            nextCardID: nextCardID,
            preferredColumnCount: nil
        )
    }

    private func resolvedLocalCardDragPreviewFrames(
        for drag: IndexBoardSurfaceAppKitDragState
    ) -> [UUID: CGRect] {
        withIndexBoardSurfaceAppKitSignpost(IndexBoardSurfaceAppKitSignpostName.resolvedLocalCardPreview) {
            let snapshot = restingSceneSnapshot ?? makeRestingSceneSnapshot()
            let baseProjection = snapshot.projection
            let movingCardIDs = drag.movingCardIDSet
            var frames: [UUID: CGRect] = [:]
            let targetIsTemp = drag.dropTarget.isTempStripTarget || drag.dropTarget.detachedGridPosition != nil
            let targetGroupID: BoardSurfaceParentGroupID? = targetIsTemp
                ? nil
                : (drag.dropTarget.laneParentID.map(BoardSurfaceParentGroupID.parent) ?? .root)
            let tempLayout = resolvedIndexBoardTempStripSurfaceLayout(
                strips: resolvedPreviewTempStrips(for: drag),
                tempGroupWidthsByParentID: resolvedTempGroupWidthsByParentID(from: baseProjection)
            )
            let sourceGroupIDs = Set(
                baseProjection.surfaceItems.compactMap { item -> BoardSurfaceParentGroupID? in
                    movingCardIDs.contains(item.cardID) ? item.parentGroupID : nil
                }
            )
            let affectedGroupIDs = Set(
                baseProjection.parentGroups.compactMap { placement -> BoardSurfaceParentGroupID? in
                    if sourceGroupIDs.contains(placement.id) || placement.id == targetGroupID || placement.isTempGroup {
                        return placement.id
                    }
                    return nil
                }
            )

            for placement in baseProjection.parentGroups {
                guard affectedGroupIDs.contains(placement.id) else { continue }
                let origin: IndexBoardGridPosition
                if placement.isTempGroup,
                   let parentCardID = placement.parentCardID,
                   let tempOrigin = tempLayout.groupOriginByParentID[parentCardID] {
                    origin = tempOrigin
                } else {
                    origin = placement.origin
                }

                let stationaryCardIDs = placement.cardIDs.filter { !movingCardIDs.contains($0) }
                let insertionIndex = placement.id == targetGroupID
                    ? min(max(0, drag.dropTarget.insertionIndex), stationaryCardIDs.count)
                    : nil

                for (stationaryIndex, cardID) in stationaryCardIDs.enumerated() {
                    let previewIndex: Int
                    if let insertionIndex, stationaryIndex >= insertionIndex {
                        previewIndex = stationaryIndex + drag.movingCardIDs.count
                    } else {
                        previewIndex = stationaryIndex
                    }

                    let frame = resolvedCardFrame(
                        for: IndexBoardGridPosition(
                            column: origin.column + previewIndex,
                            row: origin.row
                        )
                    )
                    if snapshot.cardFrameByID[cardID] != frame {
                        frames[cardID] = frame
                    }
                }
            }

            for (cardID, position) in tempLayout.detachedPositionsByCardID where !movingCardIDs.contains(cardID) {
                let frame = resolvedCardFrame(for: position)
                if snapshot.cardFrameByID[cardID] != frame {
                    frames[cardID] = frame
                }
            }

            return frames
        }
    }

    private func beginDrag(cardID: UUID, pointer: CGPoint) {
        guard let primaryItem = orderedItems.first(where: { $0.cardID == cardID }),
              let initialFrame = resolvedCardFrame(for: primaryItem) else { return }
        let movingItems = resolvedMovingItems(for: cardID)
        let movingCardIDs = movingItems.map(\.cardID)
        let sourceDetachedGridPositionsByCardID = Dictionary(
            uniqueKeysWithValues: movingItems.compactMap { item -> (UUID, IndexBoardGridPosition)? in
                guard item.parentGroupID == nil,
                      let position = item.detachedGridPosition ?? item.gridPosition else {
                    return nil
                }
                return (item.cardID, position)
            }
        )
        configuration.onCardDragStart(movingCardIDs, cardID)
        let sourceTarget = sourceTarget(for: movingItems, primaryItem: primaryItem)
        let sourcePlacement: IndexBoardSurfaceAppKitDropPlacement
        if let detachedGridPosition = primaryItem.detachedGridPosition,
           primaryItem.parentGroupID == nil {
            sourcePlacement = .detached(detachedGridPosition)
        } else {
            sourcePlacement = .flow(0)
        }

        dragSnapshots = movingCardIDs.compactMap { movingCardID in
            guard let snapshot = cardViews[movingCardID]?.snapshotImage() else { return nil }
            return IndexBoardSurfaceAppKitCardSnapshot(cardID: movingCardID, image: snapshot)
        }

        let movingTempMembers = movingCardIDs.map { IndexBoardTempStripMember(kind: .card, id: $0) }
        let provisionalDragState = IndexBoardSurfaceAppKitDragState(
            cardID: cardID,
            movingCardIDs: movingCardIDs,
            movingTempMembers: movingTempMembers,
            sourceDetachedGridPositionsByCardID: sourceDetachedGridPositionsByCardID,
            sourcePlacement: sourcePlacement,
            sourceLaneParentID: primaryItem.laneParentID,
            sourceTarget: sourceTarget,
            initialFrame: initialFrame,
            pointerOffset: CGSize(
                width: pointer.x - initialFrame.minX,
                height: pointer.y - initialFrame.minY
            ),
            pointerInContent: pointer,
            dropPlacement: sourcePlacement,
            dropTarget: sourceTarget
        )
        let initialTarget = resolvedDropTarget(for: provisionalDragState)
        dragState = IndexBoardSurfaceAppKitDragState(
            cardID: cardID,
            movingCardIDs: movingCardIDs,
            movingTempMembers: movingTempMembers,
            sourceDetachedGridPositionsByCardID: sourceDetachedGridPositionsByCardID,
            sourcePlacement: sourcePlacement,
            sourceLaneParentID: primaryItem.laneParentID,
            sourceTarget: initialTarget,
            initialFrame: initialFrame,
            pointerOffset: CGSize(
                width: pointer.x - initialFrame.minX,
                height: pointer.y - initialFrame.minY
            ),
            pointerInContent: pointer,
            dropPlacement: sourcePlacement,
            dropTarget: initialTarget
        )
        if let dragState {
            presentationSurfaceProjection = resolvedPresentationSurfaceProjection(for: dragState)
        }
        startAutoScrollTimer()
        applyCurrentLayout(animationDuration: 0)
    }

    private func endDrag(cardID: UUID) {
        guard let dragState, dragState.cardID == cardID else { return }
        let preservedScrollOrigin = scrollView?.contentView.bounds.origin
        let target = dragState.dropTarget
        let shouldCommit = target != dragState.sourceTarget
        prepareViewportPreservationAfterDrop(preservedScrollOrigin)

        if shouldCommit {
            presentationSurfaceProjection = resolvedPresentationSurfaceProjection(for: dragState)
        } else {
            presentationSurfaceProjection = nil
        }
        self.dragState = nil
        dragSnapshots = []
        frozenLogicalGridBounds = nil
        stopAutoScrollTimer()
        applyCurrentLayout(animationDuration: IndexBoardSurfaceAppKitConstants.commitLayoutAnimationDuration)
        restoreScrollOriginAfterDrop(preservedScrollOrigin, notifySession: false)
        if !shouldCommit, let preservedScrollOrigin {
            configuration.onScrollOffsetChange(preservedScrollOrigin)
        }

        guard shouldCommit else { return }
        if dragState.movingCardIDs.count > 1 {
            configuration.onCardMoveSelection(dragState.movingCardIDs, cardID, target)
        } else {
            configuration.onCardMove(cardID, target)
        }
    }

    private func beginGroupDrag(parentCardID: UUID, pointer: CGPoint) {
        guard let group = effectiveSurfaceProjection.parentGroups.first(where: { $0.parentCardID == parentCardID }),
              let groupFrame = resolvedParentGroupFrame(for: group) else { return }
        frozenLogicalGridBounds = logicalGridBounds
        groupDragSnapshot = snapshotImage(in: groupFrame)
        groupDragState = IndexBoardSurfaceAppKitGroupDragState(
            parentCardID: parentCardID,
            movingCardIDs: group.cardIDs,
            initialOrigin: group.origin,
            initialFrame: groupFrame,
            pointerOffset: CGSize(
                width: pointer.x - groupFrame.minX,
                height: pointer.y - groupFrame.minY
            ),
            pointerInContent: pointer,
            targetOrigin: group.origin
        )
        if var groupDragState {
            groupDragState.targetOrigin = resolvedGroupDragOrigin(for: groupDragState)
            self.groupDragState = groupDragState
            updateLocalGroupDragPreview(for: groupDragState)
            presentationSurfaceProjection = resolvedPresentationSurfaceProjection(for: groupDragState)
        }
        applyCurrentLayout(animationDuration: 0)
    }

    private func endGroupDrag(parentCardID: UUID) {
        guard let groupDragState, groupDragState.parentCardID == parentCardID else { return }
        let preservedScrollOrigin = scrollView?.contentView.bounds.origin
        let targetOrigin = groupDragState.targetOrigin
        let shouldCommit = targetOrigin != groupDragState.initialOrigin
        prepareViewportPreservationAfterDrop(preservedScrollOrigin)
        if shouldCommit {
            presentationSurfaceProjection = resolvedPresentationSurfaceProjection(for: groupDragState)
        } else {
            presentationSurfaceProjection = nil
        }
        self.groupDragState = nil
        updateLocalGroupDragPreview(for: nil)
        groupDragSnapshot = nil
        frozenLogicalGridBounds = nil
        applyCurrentLayout(animationDuration: IndexBoardSurfaceAppKitConstants.commitLayoutAnimationDuration)
        restoreScrollOriginAfterDrop(preservedScrollOrigin, notifySession: false)
        if !shouldCommit, let preservedScrollOrigin {
            configuration.onScrollOffsetChange(preservedScrollOrigin)
        }
        guard shouldCommit else { return }
        configuration.onParentGroupMove(
            IndexBoardParentGroupDropTarget(
                parentCardID: parentCardID,
                origin: targetOrigin
            )
        )
    }

    private func resolvedGroupDragOrigin(
        for drag: IndexBoardSurfaceAppKitGroupDragState
    ) -> IndexBoardGridPosition {
        let groupOrigin = drag.overlayOrigin()
        let snappedPoint = CGPoint(
            x: groupOrigin.x + (IndexBoardMetrics.cardSize.width / 2),
            y: groupOrigin.y + ((IndexBoardMetrics.cardSize.height + IndexBoardSurfaceAppKitConstants.laneChipHeight) / 2)
        )
        return resolvedNearestGridPosition(for: snappedPoint)
    }

    private func reconcilePresentationProjection() {
        guard dragState == nil,
              groupDragState == nil,
              let presentationSurfaceProjection else {
            if dragState == nil && groupDragState == nil {
                self.presentationSurfaceProjection = nil
            }
            return
        }

        if presentationSurfaceProjection.surfaceItems == configuration.surfaceProjection.surfaceItems {
            self.presentationSurfaceProjection = nil
        }
    }

    private func resolvedDropPlacement(for drag: IndexBoardSurfaceAppKitDragState) -> IndexBoardSurfaceAppKitDropPlacement {
        let visibleItems = flowItems.filter { !drag.movingCardIDSet.contains($0.cardID) }
        let dragCardFrame = CGRect(origin: drag.overlayOrigin(), size: IndexBoardMetrics.cardSize)
        let dragCardCenter = CGPoint(x: dragCardFrame.midX, y: dragCardFrame.midY)

        if let flowInteractionRect = resolvedFlowInteractionRect(
            slotCount: visibleItems.count
        ),
           flowInteractionRect.contains(dragCardCenter) {
            return .flow(
                resolvedFlowDropSlotIndex(
                    for: dragCardCenter,
                    slotCount: visibleItems.count
                )
            )
        }

        return .detached(resolvedDetachedGridPosition(for: drag.pointerInContent, excluding: drag.movingCardIDSet))
    }

    private func resolvedDropTarget(for drag: IndexBoardSurfaceAppKitDragState) -> IndexBoardCardDropTarget {
        let dragCardFrame = CGRect(origin: drag.overlayOrigin(), size: IndexBoardMetrics.cardSize)
        let dragCardCenter = CGPoint(x: dragCardFrame.midX, y: dragCardFrame.midY)

        if let targetGroup = resolvedCardDropTargetGroup(at: dragCardCenter, for: drag) {
            let visibleItems = orderedItems.filter { item in
                item.parentGroupID == targetGroup.id && !drag.movingCardIDSet.contains(item.cardID)
            }
            let insertionIndex = visibleItems.firstIndex(where: { item in
                guard let itemFrame = cardFrameByID[item.cardID] else { return false }
                return dragCardCenter.x < itemFrame.midX
            }) ?? visibleItems.count
            let previousCardID = insertionIndex > 0 ? visibleItems[insertionIndex - 1].cardID : nil
            let nextCardID = insertionIndex < visibleItems.count ? visibleItems[insertionIndex].cardID : nil
            return IndexBoardCardDropTarget(
                groupID: legacyGroupID(for: targetGroup.parentCardID),
                insertionIndex: insertionIndex,
                laneParentID: targetGroup.parentCardID,
                previousCardID: previousCardID,
                nextCardID: nextCardID,
                preferredColumnCount: nil
            )
        }

        let detachedGridPosition = resolvedDetachedGridPosition(
            for: drag.pointerInContent,
            excluding: drag.movingCardIDSet
        )

        if let detachedBlockTarget = resolvedDetachedBlockDropTarget(
            at: dragCardCenter,
            for: drag
        ) {
            if drag.sourceTarget == detachedBlockTarget {
                return drag.sourceTarget
            }
            return detachedBlockTarget
        }

        if drag.sourceTarget.detachedGridPosition == detachedGridPosition,
           drag.sourceTarget.previousTempMember == nil,
           drag.sourceTarget.nextTempMember == nil,
           drag.sourceTarget.previousCardID == nil,
           drag.sourceTarget.nextCardID == nil {
            return drag.sourceTarget
        }
        return IndexBoardCardDropTarget(
            groupID: legacyGroupID(for: tempLaneParentID() ?? drag.sourceLaneParentID),
            insertionIndex: drag.sourceTarget.insertionIndex,
            laneParentID: tempLaneParentID() ?? drag.sourceLaneParentID,
            detachedGridPosition: detachedGridPosition,
            preferredColumnCount: nil
        )
    }

    private func resolvedGroupFrame(
        for group: BoardSurfaceParentGroupPlacement,
        cardFramesByID: [UUID: CGRect]
    ) -> CGRect? {
        let groupFrames = group.cardIDs.compactMap { cardFramesByID[$0] }
        guard let firstFrame = groupFrames.first else { return nil }
        let cardUnion = groupFrames.dropFirst().reduce(firstFrame) { partial, frame in
            partial.union(frame)
        }
        let chipFrame = CGRect(
            x: firstFrame.minX,
            y: firstFrame.minY - IndexBoardSurfaceAppKitConstants.laneChipSpacing - IndexBoardSurfaceAppKitConstants.laneChipHeight,
            width: IndexBoardMetrics.cardSize.width,
            height: IndexBoardSurfaceAppKitConstants.laneChipHeight
        )
        let baseFrame = cardUnion.union(chipFrame)
        return baseFrame.insetBy(
            dx: -IndexBoardSurfaceAppKitConstants.laneWrapperInset,
            dy: -IndexBoardSurfaceAppKitConstants.laneWrapperInset
        )
    }

    private func resolvedPreviewParentGroups(
        for drag: IndexBoardSurfaceAppKitGroupDragState,
        baseProjection: BoardSurfaceProjection
    ) -> [BoardSurfaceParentGroupPlacement] {
        let updatedParentGroups = baseProjection.parentGroups.map { group in
            guard group.parentCardID == drag.parentCardID else { return group }
            return BoardSurfaceParentGroupPlacement(
                id: group.id,
                parentCardID: group.parentCardID,
                origin: drag.targetOrigin,
                cardIDs: group.cardIDs,
                titleText: group.titleText,
                subtitleText: group.subtitleText,
                colorToken: group.colorToken,
                isMainline: group.isMainline,
                isTempGroup: group.isTempGroup
            )
        }

        guard let movingGroup = updatedParentGroups.first(where: { $0.parentCardID == drag.parentCardID }),
              !movingGroup.isTempGroup else {
            return updatedParentGroups.sorted(by: indexBoardSurfaceAppKitGroupSort)
        }

        let normalizedLayout = normalizedIndexBoardSurfaceLayout(
            parentGroups: updatedParentGroups,
            detachedPositionsByCardID: indexBoardDetachedGridPositionsByCardID(from: baseProjection),
            referenceParentGroups: baseProjection.parentGroups,
            referenceDetachedPositionsByCardID: indexBoardDetachedGridPositionsByCardID(from: baseProjection),
            preferredLeadingParentCardID: drag.parentCardID
        )
        return normalizedLayout.parentGroups.sorted(by: indexBoardSurfaceAppKitGroupSort)
    }

    private func resolvedLocalGroupDragPreview(
        for drag: IndexBoardSurfaceAppKitGroupDragState
    ) -> IndexBoardSurfaceAppKitGroupDragPreview? {
        withIndexBoardSurfaceAppKitSignpost(IndexBoardSurfaceAppKitSignpostName.resolvedLocalGroupPreview) {
            let snapshot = restingSceneSnapshot ?? makeRestingSceneSnapshot()
            let previewParentGroups = resolvedPreviewParentGroups(
                for: drag,
                baseProjection: snapshot.projection
            )
            var frames = snapshot.cardFrameByID
            for group in previewParentGroups {
                for (index, cardID) in group.cardIDs.enumerated() {
                    frames[cardID] = resolvedCardFrame(
                        for: IndexBoardGridPosition(
                            column: group.origin.column + index,
                            row: group.origin.row
                        )
                    )
                }
            }
            let targetFrame = previewParentGroups
                .first(where: { $0.parentCardID == drag.parentCardID })
                .map { resolvedCardFrame(for: $0.origin) }
            return IndexBoardSurfaceAppKitGroupDragPreview(
                cardFramesByID: frames,
                targetFrame: targetFrame
            )
        }
    }

    private func resolvedNearestGroupDragOrigin(
        near candidate: IndexBoardGridPosition,
        width: Int,
        occupiedPositions: Set<IndexBoardGridPosition>
    ) -> IndexBoardGridPosition {
        let bounds = logicalGridBounds
        let safeWidth = max(1, width)
        let maxStartColumn = max(bounds.minColumn, bounds.maxColumn - max(0, safeWidth - 1))

        func isValid(_ origin: IndexBoardGridPosition) -> Bool {
            guard origin.row >= bounds.minRow,
                  origin.row <= bounds.maxRow,
                  origin.column >= bounds.minColumn,
                  origin.column <= maxStartColumn else {
                return false
            }
            return !occupiedPositions.contains(origin)
        }

        let clampedCandidate = IndexBoardGridPosition(
            column: min(max(bounds.minColumn, candidate.column), maxStartColumn),
            row: min(max(bounds.minRow, candidate.row), bounds.maxRow)
        )
        if isValid(clampedCandidate) {
            return clampedCandidate
        }

        let maxRadius = max(bounds.columnCount, bounds.rowCount)
        for radius in 1...maxRadius {
            var candidates: [IndexBoardGridPosition] = []
            for row in (clampedCandidate.row - radius)...(clampedCandidate.row + radius) {
                for column in (clampedCandidate.column - radius)...(clampedCandidate.column + radius) {
                    let rowDelta = abs(row - clampedCandidate.row)
                    let columnDelta = abs(column - clampedCandidate.column)
                    guard max(rowDelta, columnDelta) == radius else { continue }
                    candidates.append(IndexBoardGridPosition(column: column, row: row))
                }
            }

            let nearest = candidates.sorted { lhs, rhs in
                let lhsDistance = abs(lhs.row - clampedCandidate.row) + abs(lhs.column - clampedCandidate.column)
                let rhsDistance = abs(rhs.row - clampedCandidate.row) + abs(rhs.column - clampedCandidate.column)
                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }
                if lhs.row != rhs.row {
                    return lhs.row < rhs.row
                }
                return lhs.column < rhs.column
            }

            if let resolved = nearest.first(where: isValid) {
                return resolved
            }
        }

        return dragFallbackGroupOrigin(
            candidate: clampedCandidate,
            maxStartColumn: maxStartColumn,
            bounds: bounds
        )
    }

    private func dragFallbackGroupOrigin(
        candidate: IndexBoardGridPosition,
        maxStartColumn: Int,
        bounds: IndexBoardSurfaceAppKitGridBounds
    ) -> IndexBoardGridPosition {
        IndexBoardGridPosition(
            column: min(max(bounds.minColumn, candidate.column), maxStartColumn),
            row: min(max(bounds.minRow, candidate.row), bounds.maxRow)
        )
    }

    private func shouldPreferDetachedParking(
        at point: CGPoint,
        candidatePosition: IndexBoardGridPosition,
        over stripTarget: IndexBoardCardDropTarget,
        for drag: IndexBoardSurfaceAppKitDragState
    ) -> Bool {
        guard stripTarget.previousTempMember != nil || stripTarget.nextTempMember != nil else {
            return false
        }
        let compactedStrips = resolvedIndexBoardTempStripsAfterRemovingMembers(
            strips: referenceTempStrips(),
            movingMembers: drag.movingTempMembers
        )
        guard let targetStrip = compactedStrips.first(where: { strip in
            if let previousMember = stripTarget.previousTempMember, strip.members.contains(previousMember) {
                return true
            }
            if let nextMember = stripTarget.nextTempMember, strip.members.contains(nextMember) {
                return true
            }
            return false
        }) else {
            return false
        }
        guard candidatePosition.row != targetStrip.row else {
            return false
        }
        let candidateFrame = resolvedCardFrame(for: candidatePosition).insetBy(dx: -18, dy: -18)
        return candidateFrame.contains(point)
    }

    private func isDetachedSourcePreview(_ drag: IndexBoardSurfaceAppKitDragState) -> Bool {
        false
    }

    private func resolvedDetachedSourcePreviewPositions(
        for drag: IndexBoardSurfaceAppKitDragState
    ) -> [UUID: IndexBoardGridPosition] {
        resolvedIndexBoardDetachedPositionsAfterRemovingCards(
            referencePositionsByCardID: referenceDetachedPositions(),
            movingCardIDs: drag.movingCardIDs
        )
    }

    private func resolvedDetachedTargetFrames(
        for drag: IndexBoardSurfaceAppKitDragState
    ) -> [CGRect] {
        if let parkingPosition = drag.dropTarget.detachedGridPosition {
            return drag.movingCardIDs.enumerated().map { offset, _ in
                resolvedCardFrame(
                    for: IndexBoardGridPosition(
                        column: parkingPosition.column + offset,
                        row: parkingPosition.row
                    )
                )
            }
        }

        let compactedStrips = resolvedIndexBoardTempStripsAfterRemovingMembers(
            strips: referenceTempStrips(),
            movingMembers: drag.movingTempMembers
        )
        let widthsByParentID = resolvedTempGroupWidthsByParentID(from: configuration.surfaceProjection)
        let targetStrip = compactedStrips.first { strip in
            if let previousMember = drag.dropTarget.previousTempMember,
               strip.members.contains(previousMember) {
                return true
            }
            if let nextMember = drag.dropTarget.nextTempMember,
               strip.members.contains(nextMember) {
                return true
            }
            return false
        }
        guard let targetStrip else { return [] }

        let slotDescriptors = resolvedTempStripSlotDescriptors(
            for: targetStrip,
            widthsByParentID: widthsByParentID
        )
        let matchingSlot = slotDescriptors.first { descriptor in
            descriptor.previous == drag.dropTarget.previousTempMember &&
            descriptor.next == drag.dropTarget.nextTempMember
        }
        guard let matchingSlot else { return [] }

        return drag.movingCardIDs.enumerated().map { offset, _ in
            resolvedCardFrame(
                for: IndexBoardGridPosition(
                    column: matchingSlot.column + offset,
                    row: targetStrip.row
                )
            )
        }
    }

    private func resolvedDetachedIndicatorFrames(
        for drag: IndexBoardSurfaceAppKitDragState
    ) -> ([CGRect], IndexBoardSurfaceAppKitPlaceholderStyle)? {
        let frames = resolvedDetachedTargetFrames(for: drag)
        guard !frames.isEmpty else { return nil }
        let style: IndexBoardSurfaceAppKitPlaceholderStyle =
            (drag.dropTarget.previousTempMember == nil &&
             drag.dropTarget.nextTempMember == nil &&
             drag.dropTarget.previousCardID == nil &&
             drag.dropTarget.nextCardID == nil)
            ? .detachedParking
            : .detachedSlot
        return (frames, style)
    }

    private func resolvedPreviewTempStrips(
        for drag: IndexBoardSurfaceAppKitDragState
    ) -> [IndexBoardTempStripState] {
        if drag.dropTarget.isTempStripTarget || drag.dropTarget.detachedGridPosition != nil {
            return resolvedIndexBoardTempStripsByApplyingMove(
                strips: referenceTempStrips(),
                movingMembers: drag.movingTempMembers,
                previousMember: drag.dropTarget.previousTempMember,
                nextMember: drag.dropTarget.nextTempMember,
                parkingPosition: drag.dropTarget.detachedGridPosition
            )
        }

        return resolvedIndexBoardTempStripsAfterRemovingMembers(
            strips: referenceTempStrips(),
            movingMembers: drag.movingTempMembers
        )
    }

    private func resolvedPresentationSurfaceProjection(for drag: IndexBoardSurfaceAppKitDragState) -> BoardSurfaceProjection {
        let baseItems = configuration.surfaceProjection.surfaceItems.sorted(by: indexBoardSurfaceAppKitSort)
        let movingIDs = drag.movingCardIDSet
        let movingItemsByCardID = Dictionary(uniqueKeysWithValues: baseItems.compactMap { item -> (UUID, BoardSurfaceItem)? in
            movingIDs.contains(item.cardID) ? (item.cardID, item) : nil
        })
        let baseItemsByCardID = Dictionary(uniqueKeysWithValues: baseItems.map { ($0.cardID, $0) })
        let movingItems = drag.movingCardIDs.compactMap { movingItemsByCardID[$0] }
        let stationaryFlowItems = baseItems
            .filter { !movingIDs.contains($0.cardID) && !$0.isDetached }
            .sorted(by: indexBoardSurfaceAppKitSort)
        let regroupedByGroupID = Dictionary(grouping: stationaryFlowItems, by: { $0.parentGroupID })

        func rebuiltFlowPresentation(
            inserting movingCardIDs: [UUID] = [],
            targetGroupID: BoardSurfaceParentGroupID? = nil,
            insertionIndex: Int? = nil
        ) -> ([BoardSurfaceParentGroupPlacement], [BoardSurfaceItem]) {
            let updatedParentGroups = effectiveSurfaceProjection.parentGroups.map { placement -> BoardSurfaceParentGroupPlacement in
                let stationaryCards = (regroupedByGroupID[placement.id] ?? []).map(\.cardID)
                let cardIDs: [UUID]
                if placement.id == targetGroupID, let insertionIndex {
                    var updated = stationaryCards
                    updated.insert(
                        contentsOf: movingCardIDs,
                        at: min(max(0, insertionIndex), updated.count)
                    )
                    cardIDs = updated
                } else {
                    cardIDs = stationaryCards
                }
                return BoardSurfaceParentGroupPlacement(
                    id: placement.id,
                    parentCardID: placement.parentCardID,
                    origin: placement.origin,
                    cardIDs: cardIDs,
                    titleText: placement.titleText,
                    subtitleText: placement.subtitleText,
                    colorToken: placement.colorToken,
                    isMainline: placement.isMainline,
                    isTempGroup: placement.isTempGroup
                )
            }

            var regroupedItems: [BoardSurfaceItem] = []
            for placement in updatedParentGroups.sorted(by: indexBoardSurfaceAppKitGroupSort) {
                let placementLaneIndex = configuration.surfaceProjection.lanes.first(where: { $0.parentCardID == placement.parentCardID })?.laneIndex
                    ?? movingItems.first?.laneIndex
                    ?? 0
                let parentItems = placement.cardIDs.enumerated().map { index, cardID in
                    BoardSurfaceItem(
                        cardID: cardID,
                        laneParentID: placement.parentCardID,
                        laneIndex: placementLaneIndex,
                        slotIndex: nil,
                        detachedGridPosition: nil,
                        gridPosition: IndexBoardGridPosition(
                            column: placement.origin.column + index,
                            row: placement.origin.row
                        ),
                        parentGroupID: placement.id
                    )
                }
                regroupedItems.append(contentsOf: parentItems)
            }

            return (updatedParentGroups, regroupedItems)
        }

        let presentationParentGroups: [BoardSurfaceParentGroupPlacement]
        let target = drag.dropTarget
        let resolvedItems: [BoardSurfaceItem]
        let previewTempStrips = resolvedPreviewTempStrips(for: drag)
        let previewTempLayout = resolvedIndexBoardTempStripSurfaceLayout(
            strips: previewTempStrips,
            tempGroupWidthsByParentID: resolvedTempGroupWidthsByParentID(
                from: configuration.surfaceProjection
            )
        )
        let previewTempDetachedCardIDs = Set(previewTempLayout.detachedPositionsByCardID.keys)

        func normalizedPresentation(
            from parentGroups: [BoardSurfaceParentGroupPlacement]
        ) -> ([BoardSurfaceParentGroupPlacement], [BoardSurfaceItem]) {
            let updatedParentGroups = parentGroups.map { placement in
                guard placement.isTempGroup,
                      let parentCardID = placement.parentCardID,
                      let origin = previewTempLayout.groupOriginByParentID[parentCardID] else {
                    return placement
                }
                return BoardSurfaceParentGroupPlacement(
                    id: placement.id,
                    parentCardID: placement.parentCardID,
                    origin: origin,
                    cardIDs: placement.cardIDs,
                    titleText: placement.titleText,
                    subtitleText: placement.subtitleText,
                    colorToken: placement.colorToken,
                    isMainline: placement.isMainline,
                    isTempGroup: placement.isTempGroup
                )
            }.sorted(by: indexBoardSurfaceAppKitGroupSort)

            let normalizedFlowItems = updatedParentGroups.flatMap { placement in
                let laneIndex = configuration.surfaceProjection.lanes.first(where: { $0.parentCardID == placement.parentCardID })?.laneIndex
                    ?? movingItems.first?.laneIndex
                    ?? 0
                return placement.cardIDs.enumerated().map { index, cardID in
                    BoardSurfaceItem(
                        cardID: cardID,
                        laneParentID: placement.parentCardID,
                        laneIndex: laneIndex,
                        slotIndex: nil,
                        detachedGridPosition: nil,
                        gridPosition: IndexBoardGridPosition(
                            column: placement.origin.column + index,
                            row: placement.origin.row
                        ),
                        parentGroupID: placement.id
                    )
                }
            }

            let tempLaneIndex = configuration.surfaceProjection.lanes.first(where: \.isTempLane)?.laneIndex
            let normalizedDetachedItems = previewTempLayout.detachedPositionsByCardID
                .sorted { lhs, rhs in
                    if lhs.value.row != rhs.value.row {
                        return lhs.value.row < rhs.value.row
                    }
                    if lhs.value.column != rhs.value.column {
                        return lhs.value.column < rhs.value.column
                    }
                    return lhs.key.uuidString < rhs.key.uuidString
                }
                .compactMap { cardID, position -> BoardSurfaceItem? in
                    guard previewTempDetachedCardIDs.contains(cardID) else { return nil }
                    let sourceItem = baseItemsByCardID[cardID]
                    let resolvedLaneIndex = tempLaneIndex ?? sourceItem?.laneIndex ?? 0
                    let resolvedLaneParentID = tempLaneParentID() ?? sourceItem?.laneParentID
                    return BoardSurfaceItem(
                        cardID: cardID,
                        laneParentID: resolvedLaneParentID,
                        laneIndex: resolvedLaneIndex,
                        slotIndex: nil,
                        detachedGridPosition: position,
                        gridPosition: position,
                        parentGroupID: nil
                    )
                }

            return (updatedParentGroups, normalizedFlowItems + normalizedDetachedItems)
        }

        if target.isTempStripTarget || target.detachedGridPosition != nil {
            let rebuiltFlow = rebuiltFlowPresentation()
            let normalized = normalizedPresentation(from: rebuiltFlow.0)
            presentationParentGroups = normalized.0
            resolvedItems = normalized.1
        } else {
            let targetLaneParentID = target.laneParentID ?? drag.sourceLaneParentID
            let targetGroupID = targetLaneParentID.map(BoardSurfaceParentGroupID.parent) ?? .root
            let rebuiltFlow = rebuiltFlowPresentation(
                inserting: drag.movingCardIDs,
                targetGroupID: targetGroupID,
                insertionIndex: target.insertionIndex
            )
            let normalized = normalizedPresentation(from: rebuiltFlow.0)
            presentationParentGroups = normalized.0
            resolvedItems = normalized.1
        }

        let resolvedTempStrips: [IndexBoardTempStripState] = previewTempStrips
        let sortedItems = resolvedItems.sorted(by: indexBoardSurfaceAppKitSort)
        return BoardSurfaceProjection(
            source: configuration.surfaceProjection.source,
            startAnchor: configuration.surfaceProjection.startAnchor,
            lanes: configuration.surfaceProjection.lanes,
            parentGroups: presentationParentGroups,
            tempStrips: resolvedTempStrips,
            surfaceItems: sortedItems,
            orderedCardIDs: sortedItems.map(\.cardID)
        )
    }

    private func resolvedPresentationSurfaceProjection(
        for drag: IndexBoardSurfaceAppKitGroupDragState
    ) -> BoardSurfaceProjection {
        let baseProjection = restingSceneSnapshot?.projection ?? configuration.surfaceProjection
        let updatedParentGroups = resolvedPreviewParentGroups(
            for: drag,
            baseProjection: baseProjection
        )

        let stationaryDetachedItems = baseProjection.surfaceItems.filter { $0.parentGroupID == nil }
        var regroupedItems: [BoardSurfaceItem] = []
        for placement in updatedParentGroups.sorted(by: indexBoardSurfaceAppKitGroupSort) {
            let laneIndex = baseProjection.lanes.first(where: { $0.parentCardID == placement.parentCardID })?.laneIndex ?? 0
            let updatedItems = placement.cardIDs.enumerated().map { index, cardID in
                BoardSurfaceItem(
                    cardID: cardID,
                    laneParentID: placement.parentCardID,
                    laneIndex: laneIndex,
                    slotIndex: nil,
                    detachedGridPosition: nil,
                    gridPosition: IndexBoardGridPosition(
                        column: placement.origin.column + index,
                        row: placement.origin.row
                    ),
                    parentGroupID: placement.id
                )
            }
            regroupedItems.append(contentsOf: updatedItems)
        }

        let sortedItems = (regroupedItems + stationaryDetachedItems).sorted(by: indexBoardSurfaceAppKitSort)
        return BoardSurfaceProjection(
            source: baseProjection.source,
            startAnchor: baseProjection.startAnchor,
            lanes: baseProjection.lanes,
            parentGroups: updatedParentGroups.sorted(by: indexBoardSurfaceAppKitGroupSort),
            tempStrips: baseProjection.tempStrips,
            surfaceItems: sortedItems,
            orderedCardIDs: sortedItems.map(\.cardID)
        )
    }

    private func applyCardDragUpdate(
        _ updatedState: IndexBoardSurfaceAppKitDragState,
        previousTarget: IndexBoardCardDropTarget
    ) {
        self.dragState = updatedState
        let didRetarget = updatedState.dropTarget != previousTarget
        if didRetarget {
            presentationSurfaceProjection = resolvedPresentationSurfaceProjection(for: updatedState)
            applyCurrentLayout(
                animationDuration: IndexBoardSurfaceAppKitConstants.previewLayoutAnimationDuration
            )
        } else {
            updateOverlayLayers()
        }
    }

    private func applyGroupDragUpdate(
        _ updatedState: IndexBoardSurfaceAppKitGroupDragState,
        previousOrigin: IndexBoardGridPosition
    ) {
        self.groupDragState = updatedState
        updateLocalGroupDragPreview(for: updatedState)
        let didRetarget = updatedState.targetOrigin != previousOrigin
        if didRetarget {
            presentationSurfaceProjection = resolvedPresentationSurfaceProjection(for: updatedState)
            applyCurrentLayout(
                animationDuration: IndexBoardSurfaceAppKitConstants.previewLayoutAnimationDuration
            )
        } else {
            updateOverlayLayers()
        }
    }

    private func updateLocalGroupDragPreview(
        for drag: IndexBoardSurfaceAppKitGroupDragState?
    ) {
        guard let drag,
              drag.targetOrigin != drag.initialOrigin,
              let preview = resolvedLocalGroupDragPreview(for: drag) else {
            localGroupDragPreviewFramesByID = nil
            localGroupDragTargetFrame = nil
            return
        }

        localGroupDragPreviewFramesByID = preview.cardFramesByID
        localGroupDragTargetFrame = preview.targetFrame
    }

    private func resolvedDetachedSelectionPositions(
        count: Int,
        start: IndexBoardGridPosition,
        occupied: Set<IndexBoardGridPosition>
    ) -> [IndexBoardGridPosition] {
        guard count > 0 else { return [] }
        var positions: [IndexBoardGridPosition] = []
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

    private func legacyGroupID(for laneParentID: UUID?) -> IndexBoardGroupID {
        laneParentID.map(IndexBoardGroupID.parent) ?? .root
    }

    private func applyCurrentLayout(animationDuration: TimeInterval) {
        let bounds = logicalGridBounds
        let gridWidth =
            (CGFloat(bounds.columnCount) * slotSize.width) +
            (CGFloat(max(0, bounds.columnCount - 1)) * IndexBoardMetrics.cardSpacing)
        let gridHeight =
            (CGFloat(bounds.rowCount) * slotSize.height) +
            (CGFloat(max(0, bounds.rowCount - 1)) * IndexBoardSurfaceAppKitConstants.lineSpacing)
        let documentSize = CGSize(
            width: max(
                configuration.canvasSize.width + IndexBoardSurfaceAppKitConstants.surfaceHorizontalOverscan,
                gridWidth + (surfaceHorizontalInset * 2) + IndexBoardSurfaceAppKitConstants.surfaceHorizontalOverscan
            ),
            height: max(
                configuration.canvasSize.height + IndexBoardSurfaceAppKitConstants.surfaceVerticalOverscan,
                gridHeight + surfaceTopInset + surfaceBottomInset + IndexBoardSurfaceAppKitConstants.surfaceVerticalOverscan
            )
        )
        if frame.size != documentSize {
            frame.size = documentSize
        }

        let nextCardFrames = resolvedCurrentCardFrames()
        cardFrameByID = nextCardFrames

        reconcileCardViews()
        reconcileLaneChipViews()
        for (cardID, cardView) in cardViews {
            cardView.isHidden = hiddenCardIDs.contains(cardID)
        }
        updateStartAnchor()
        updateLaneWrappers()
        updateSelectionLayer()
        updateIndicatorLayers()
        updateHoverIndicatorLayer()
        updateOverlayLayers()
        layoutInlineEditorIfNeeded()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for item in orderedItems {
                guard let frame = nextCardFrames[item.cardID],
                      let cardView = cardViews[item.cardID] else { continue }
                if animationDuration > 0 {
                    cardView.animator().frame = frame
                } else {
                    cardView.frame = frame
                }
            }
            for (laneKey, chipView) in laneChipViews {
                let chipFrame = chipFrameByLaneKey[laneKey] ?? .zero
                if animationDuration > 0 {
                    chipView.animator().frame = chipFrame
                } else {
                    chipView.frame = chipFrame
                }
                chipView.isHidden = chipFrame.isEmpty
            }
        }

        ensureRevealIfNeeded()
    }

    private func updateStartAnchor() {
        let startRect = resolvedGridSlotRect(for: configuration.surfaceProjection.startAnchor.gridPosition)
        let anchorFrame = CGRect(
            x: startRect.minX - IndexBoardSurfaceAppKitConstants.startAnchorWidth - 20,
            y: startRect.minY,
            width: IndexBoardSurfaceAppKitConstants.startAnchorWidth,
            height: IndexBoardSurfaceAppKitConstants.startAnchorHeight
        )
        startAnchorLayer.path = CGPath(
            roundedRect: anchorFrame,
            cornerWidth: 13,
            cornerHeight: 13,
            transform: nil
        )
        let tint = indexBoardThemeAccentColor(theme: configuration.theme)
            .withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.92 : 0.84)
        startAnchorLayer.fillColor = tint.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.18 : 0.12).cgColor
        startAnchorLayer.strokeColor = tint.cgColor
        startAnchorLayer.lineWidth = 1.5
        startAnchorTextLayer.string = configuration.surfaceProjection.startAnchor.labelText
        startAnchorTextLayer.foregroundColor = tint.cgColor
        startAnchorTextLayer.frame = anchorFrame.insetBy(dx: 6, dy: 5)
    }

    private func reconcileCardViews() {
        let measurementStart = baselineMeasurementStart()
        defer { recordBaselineTiming(\.reconcileCardViewsTiming, from: measurementStart) }
        let validCardIDs = Set(orderedItems.map(\.cardID))
        for (cardID, view) in cardViews where !validCardIDs.contains(cardID) {
            view.removeFromSuperview()
            cardViews.removeValue(forKey: cardID)
            updateBaselineSession { session in
                session.removedCardViews += 1
            }
        }

        for item in orderedItems {
            guard let card = configuration.cardsByID[item.cardID] else { continue }
            let view = cardViews[item.cardID] ?? {
                let created = IndexBoardSurfaceAppKitInteractiveCardView(cardID: item.cardID)
                created.interactionDelegate = self
                created.frame = CGRect(origin: .zero, size: IndexBoardMetrics.cardSize)
                addSubview(created)
                cardViews[item.cardID] = created
                updateBaselineSession { session in
                    session.createdCardViews += 1
                }
                return created
            }()

            view.update(
                card: card,
                theme: configuration.theme,
                isSelected: configuration.selectedCardIDs.contains(card.id),
                isActive: configuration.activeCardID == card.id,
                summary: configuration.summaryByCardID[card.id],
                showsBack: configuration.showsBackByCardID[card.id] ?? false
            )
        }
    }

    private func reconcileLaneChipViews() {
        let measurementStart = baselineMeasurementStart()
        defer { recordBaselineTiming(\.reconcileLaneChipViewsTiming, from: measurementStart) }
        let laneFrames = resolvedLaneChipFrames()
        chipFrameByLaneKey = laneFrames
        let validKeys = Set(laneFrames.keys)
        for (key, view) in laneChipViews where !validKeys.contains(key) {
            view.removeFromSuperview()
            laneChipViews.removeValue(forKey: key)
            updateBaselineSession { session in
                session.removedLaneChipViews += 1
            }
        }

        let laneByKey = Dictionary(uniqueKeysWithValues: effectiveSurfaceProjection.lanes.map { (indexBoardSurfaceLaneKey($0.parentCardID), $0) })
        for (key, frame) in laneFrames {
            guard let lane = laneByKey[key] else { continue }
            let chipView = laneChipViews[key] ?? {
                let created = IndexBoardSurfaceAppKitLaneChipView(frame: frame)
                created.interactionDelegate = self
                addSubview(created)
                laneChipViews[key] = created
                updateBaselineSession { session in
                    session.createdLaneChipViews += 1
                }
                return created
            }()
            chipView.interactionDelegate = self
            chipView.update(
                model: .init(
                    lane: lane,
                    theme: configuration.theme,
                    displayText: resolvedLaneChipDisplayText(for: lane),
                    tintColorToken: resolvedLaneTintColorToken(for: lane)
                )
            )
            chipView.frame = frame
        }
    }

    private func resolvedLaneChipDisplayText(for lane: BoardSurfaceLane) -> String {
        guard let parentCardID = lane.parentCardID,
              let card = configuration.cardsByID[parentCardID] else {
            return indexBoardSurfaceSingleLinePreview(lane.labelText)
        }

        return indexBoardSurfaceSingleLinePreview(
            indexBoardSurfaceResolvedPreviewText(
                card: card,
                summary: configuration.summaryByCardID[parentCardID]
            )
        )
    }

    private func resolvedLaneChipFrames() -> [String: CGRect] {
        let orderedFlowItems = flowItems.sorted(by: indexBoardSurfaceAppKitSort)
        var seenKeys: Set<String> = []
        var frames: [String: CGRect] = [:]
        for item in orderedFlowItems {
            guard !hiddenCardIDs.contains(item.cardID) else { continue }
            let key = indexBoardSurfaceLaneKey(item.laneParentID)
            guard seenKeys.insert(key).inserted,
                  let itemFrame = cardFrameByID[item.cardID] else { continue }
            frames[key] = CGRect(
                x: itemFrame.minX,
                y: itemFrame.minY - IndexBoardSurfaceAppKitConstants.laneChipSpacing - IndexBoardSurfaceAppKitConstants.laneChipHeight,
                width: IndexBoardMetrics.cardSize.width,
                height: IndexBoardSurfaceAppKitConstants.laneChipHeight
            )
        }
        return frames
    }

    private func resolvedParentGroupFrame(
        for group: BoardSurfaceParentGroupPlacement
    ) -> CGRect? {
        let groupFrames = orderedItems.compactMap { item -> CGRect? in
            guard item.parentGroupID == group.id,
                  !hiddenCardIDs.contains(item.cardID),
                  let frame = cardFrameByID[item.cardID] else { return nil }
            return frame
        }
        guard let firstFrame = groupFrames.first else { return nil }
        let cardUnion = groupFrames.dropFirst().reduce(firstFrame) { partial, frame in
            partial.union(frame)
        }
        let chipFrame = chipFrameByLaneKey[indexBoardSurfaceLaneKey(group.parentCardID)] ?? .null
        let baseFrame = chipFrame.isNull ? cardUnion : cardUnion.union(chipFrame)
        return baseFrame.insetBy(
            dx: -IndexBoardSurfaceAppKitConstants.laneWrapperInset,
            dy: -IndexBoardSurfaceAppKitConstants.laneWrapperInset
        )
    }

    private func updateLaneWrappers() {
        let laneByKey = Dictionary(uniqueKeysWithValues: effectiveSurfaceProjection.lanes.map { (indexBoardSurfaceLaneKey($0.parentCardID), $0) })
        var frameByLaneKey: [String: CGRect] = [:]
        for group in effectiveSurfaceProjection.parentGroups {
            let key = indexBoardSurfaceLaneKey(group.parentCardID)
            if let frame = resolvedDisplayedParentGroupFrame(for: group) {
                frameByLaneKey[key] = frame
            }
        }

        let validKeys = Set(frameByLaneKey.keys)
        for (key, layer) in laneWrapperLayers where !validKeys.contains(key) {
            layer.removeFromSuperlayer()
            laneWrapperLayers.removeValue(forKey: key)
        }

        for (key, frame) in frameByLaneKey {
            let wrapperLayer = laneWrapperLayers[key] ?? {
                let created = CAShapeLayer()
                layer?.insertSublayer(created, below: selectionLayer)
                laneWrapperLayers[key] = created
                return created
            }()
            let lane = laneByKey[key]
            wrapperLayer.path = CGPath(
                roundedRect: frame,
                cornerWidth: 18,
                cornerHeight: 18,
                transform: nil
            )
            let tint = resolvedLaneTintColor(for: lane)
            wrapperLayer.fillColor = tint.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.14 : 0.10).cgColor
            wrapperLayer.strokeColor = tint.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.72 : 0.44).cgColor
            wrapperLayer.lineWidth = 4
        }
    }

    private func resolvedDisplayedParentGroupFrame(
        for group: BoardSurfaceParentGroupPlacement
    ) -> CGRect? {
        guard var frame = resolvedParentGroupFrame(for: group) else { return nil }
        guard let dragState,
              dragState.dropTarget.detachedGridPosition == nil,
              !dragState.dropTarget.isTempStripTarget,
              dragState.dropTarget.laneParentID == group.parentCardID else {
            return frame
        }

        let targetFrames = resolvedFlowTargetFrames(for: dragState)
        guard !targetFrames.isEmpty else { return frame }
        for targetFrame in targetFrames {
            frame = frame.union(targetFrame.insetBy(
                dx: -IndexBoardSurfaceAppKitConstants.laneWrapperInset,
                dy: -(IndexBoardSurfaceAppKitConstants.laneWrapperInset + 2)
            ))
        }
        return frame
    }

    private func resolvedLaneTintColorToken(for lane: BoardSurfaceLane?) -> String? {
        guard let lane else { return nil }
        if lane.isTempLane {
            return nil
        }
        if let parentCardID = lane.parentCardID,
           let customHex = configuration.cardsByID[parentCardID]?.colorHex {
            return customHex
        }
        return lane.colorToken
    }

    private func resolvedLaneTintColor(for lane: BoardSurfaceLane?) -> NSColor {
        if let lane, lane.isTempLane {
            return NSColor.orange.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.88 : 0.82)
        }
        if let token = resolvedLaneTintColorToken(for: lane),
           let rgb = parseHexRGB(token) {
            return NSColor(calibratedRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        }
        let borderRGB = configuration.theme.usesDarkAppearance ? (0.28, 0.30, 0.36) : (0.78, 0.75, 0.69)
        return NSColor(calibratedRed: borderRGB.0, green: borderRGB.1, blue: borderRGB.2, alpha: 1)
    }

    private func resolvedParentGroupColorHex(parentCardID: UUID) -> String? {
        configuration.cardsByID[parentCardID]?.colorHex ??
        interactionProjection.parentGroups.first(where: { $0.parentCardID == parentCardID })?.colorToken
    }

    private func canDeleteParentGroup(parentCardID: UUID) -> Bool {
        guard interactionProjection.parentGroups.contains(where: { $0.parentCardID == parentCardID }),
              let parentCard = configuration.cardsByID[parentCardID] else { return false }
        if parentCard.category == ScenarioCardCategory.note {
            return false
        }
        let firstLabel = parentCard.content
            .components(separatedBy: .newlines)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        if firstLabel == ScenarioCardCategory.note {
            return false
        }
        return firstLabel?.caseInsensitiveCompare("temp") != .orderedSame
    }

    private func makeColorMenuItem(
        title: String,
        currentHex: String?,
        action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        appendColorItems(to: submenu, currentHex: currentHex, action: action)
        item.submenu = submenu
        return item
    }

    private func appendColorItems(
        to menu: NSMenu,
        currentHex: String?,
        action: Selector
    ) {
        let defaultItem = NSMenuItem(title: "기본색", action: action, keyEquivalent: "")
        defaultItem.target = self
        defaultItem.representedObject = indexBoardSurfaceDefaultColorToken
        defaultItem.state = currentHex == nil ? .on : .off
        defaultItem.image = indexBoardSurfaceColorSwatchImage(
            hex: nil,
            defaultHex: configuration.theme.usesDarkAppearance
                ? configuration.theme.darkCardBaseColorHex
                : configuration.theme.cardBaseColorHex,
            usesDarkAppearance: configuration.theme.usesDarkAppearance
        )
        menu.addItem(defaultItem)
        menu.addItem(NSMenuItem.separator())

        for preset in indexBoardSurfaceColorPresets {
            let presetItem = NSMenuItem(title: preset.name, action: action, keyEquivalent: "")
            presetItem.target = self
            presetItem.representedObject = preset.hex
            presetItem.image = indexBoardSurfaceColorSwatchImage(
                hex: preset.hex,
                usesDarkAppearance: configuration.theme.usesDarkAppearance
            )
            if let currentHex,
               currentHex.caseInsensitiveCompare(preset.hex) == .orderedSame {
                presetItem.state = .on
            }
            menu.addItem(presetItem)
        }
    }

    private func resolvedContextMenuColorHex(from representedObject: Any?) -> String? {
        guard let token = representedObject as? String else { return nil }
        return token == indexBoardSurfaceDefaultColorToken ? nil : token
    }

    private func refreshColorDependentPresentation() {
        reconcileCardViews()
        reconcileLaneChipViews()
        updateLaneWrappers()
        refreshHoverIndicatorFromCurrentMouse()
    }

    private func updateSelectionLayer() {
        guard let selectionRect = normalizedSelectionRect() else {
            selectionLayer.path = nil
            return
        }
        selectionLayer.path = CGPath(
            roundedRect: selectionRect,
            cornerWidth: 18,
            cornerHeight: 18,
            transform: nil
        )
    }

    private func normalizedSelectionRect() -> CGRect? {
        guard let selectionState else { return nil }
        return CGRect(
            x: min(selectionState.startPoint.x, selectionState.currentPoint.x),
            y: min(selectionState.startPoint.y, selectionState.currentPoint.y),
            width: abs(selectionState.currentPoint.x - selectionState.startPoint.x),
            height: abs(selectionState.currentPoint.y - selectionState.startPoint.y)
        )
    }

    private func resolvedSelectedCardIDs(in selectionRect: CGRect) -> Set<UUID> {
        Set(
            cardFrameByID.compactMap { cardID, frame in
                frame.intersects(selectionRect) ? cardID : nil
            }
        )
    }

    private func updateHoverIndicator(at point: CGPoint) {
        guard dragState == nil,
              groupDragState == nil,
              selectionState == nil,
              !isHoverIndicatorSuppressed else {
            clearHoverIndicator()
            return
        }
        guard let candidate = resolvedHoverGridPositionCandidate(at: point) else {
            clearHoverIndicator()
            return
        }

        hoverGridPosition = candidate
        updateHoverIndicatorLayer()
    }

    private func clearHoverIndicator() {
        hoverGridPosition = nil
        hoverIndicatorLayer.path = nil
        hoverIndicatorLayer.isHidden = true
    }

    private func resolvedHoverGridPositionCandidate(at point: CGPoint) -> IndexBoardGridPosition? {
        guard editableParentCardID(at: point) == nil,
              cardID(at: point) == nil,
              movableParentGroupID(at: point) == nil else {
            return nil
        }

        let candidate = resolvedNearestGridPosition(for: point)
        let occupiedPositions = Set(occupiedGridPositionByCardID().values)
        guard !occupiedPositions.contains(candidate) else {
            return nil
        }
        return candidate
    }

    private func updateHoverIndicatorLayer() {
        guard let hoverGridPosition else {
            clearHoverIndicator()
            return
        }

        let frame = resolvedCardFrame(for: hoverGridPosition).insetBy(
            dx: -IndexBoardSurfaceAppKitConstants.hoverIndicatorInset,
            dy: -IndexBoardSurfaceAppKitConstants.hoverIndicatorInset
        )
        hoverIndicatorLayer.path = CGPath(
            roundedRect: frame,
            cornerWidth: 16,
            cornerHeight: 16,
            transform: nil
        )
        let usesDarkAppearance = configuration.theme.usesDarkAppearance
        hoverIndicatorLayer.fillColor = NSColor.white.withAlphaComponent(usesDarkAppearance ? 0.04 : 0.10).cgColor
        hoverIndicatorLayer.strokeColor = NSColor.black.withAlphaComponent(usesDarkAppearance ? 0.30 : 0.24).cgColor
        hoverIndicatorLayer.lineWidth = IndexBoardSurfaceAppKitConstants.hoverIndicatorLineWidth
        hoverIndicatorLayer.lineDashPattern = [8, 6]
        hoverIndicatorLayer.shadowColor = NSColor.black.withAlphaComponent(usesDarkAppearance ? 0.08 : 0.04).cgColor
        hoverIndicatorLayer.shadowRadius = 3
        hoverIndicatorLayer.shadowOpacity = 1
        hoverIndicatorLayer.shadowOffset = .zero
        hoverIndicatorLayer.isHidden = false
    }

    private func updateIndicatorLayers() {
        withIndexBoardSurfaceAppKitSignpost(IndexBoardSurfaceAppKitSignpostName.updateIndicatorLayers) {
            let measurementStart = baselineMeasurementStart()
            defer { recordBaselineTiming(\.updateIndicatorLayersTiming, from: measurementStart) }
            let sourceGapFrames: [CGRect]
            let sourceGapStyle: IndexBoardSurfaceAppKitPlaceholderStyle?
            if let dragState {
                sourceGapFrames = resolvedSourceGapFrames(for: dragState)
                sourceGapStyle = .flow
            } else if let groupDragState {
                sourceGapFrames = [groupDragState.initialFrame]
                sourceGapStyle = .flow
            } else {
                sourceGapFrames = []
                sourceGapStyle = nil
            }

            let targetFrames: [CGRect]
            let targetStyle: IndexBoardSurfaceAppKitPlaceholderStyle?
            if let dragState {
                let resolved = resolvedTargetIndicatorPresentation(for: dragState)
                targetFrames = resolved.frames
                targetStyle = resolved.style
            } else if groupDragState != nil,
                      let groupFrame = localGroupDragTargetFrame {
                targetFrames = [groupFrame]
                targetStyle = .detachedSlot
            } else {
                targetFrames = []
                targetStyle = nil
            }

            let focusFrames: [CGRect]
            if dragState == nil, groupDragState == nil {
                let highlightedCardIDs = orderedItems
                    .map(\.cardID)
                    .filter { configuration.selectedCardIDs.contains($0) || configuration.activeCardID == $0 }
                focusFrames = highlightedCardIDs.compactMap { cardFrameByID[$0] }
            } else {
                focusFrames = []
            }

            sourceGapLayers = replaceIndicatorLayers(
                existing: sourceGapLayers,
                frames: sourceGapFrames,
                style: sourceGapStyle
            )
            targetIndicatorLayers = replaceIndicatorLayers(
                existing: targetIndicatorLayers,
                frames: targetFrames,
                style: targetStyle
            )
            focusIndicatorLayers = replaceIndicatorLayers(
                existing: focusIndicatorLayers,
                frames: focusFrames,
                style: focusFrames.isEmpty ? nil : .detachedSlot
            )
        }
    }

    private func replaceIndicatorLayers(
        existing: [CAShapeLayer],
        frames: [CGRect],
        style: IndexBoardSurfaceAppKitPlaceholderStyle?
    ) -> [CAShapeLayer] {
        existing.forEach { $0.removeFromSuperlayer() }
        updateBaselineSession { session in
            session.removedIndicatorLayers += existing.count
        }
        guard let style, !frames.isEmpty else { return [] }

        var nextLayers: [CAShapeLayer] = []
        nextLayers.reserveCapacity(frames.count)
        for frame in frames {
            let emphasizedFrame = frame.insetBy(
                dx: -IndexBoardSurfaceAppKitConstants.placeholderHighlightInset,
                dy: -IndexBoardSurfaceAppKitConstants.placeholderHighlightInset
            )
            let layer = CAShapeLayer()
            layer.path = CGPath(
                roundedRect: emphasizedFrame,
                cornerWidth: 16,
                cornerHeight: 16,
                transform: nil
            )
            layer.fillColor = resolvedPlaceholderFillColor(style: style).cgColor
            layer.strokeColor = resolvedPlaceholderStrokeColor(style: style).cgColor
            layer.lineWidth = resolvedPlaceholderLineWidth(style: style)
            layer.lineDashPattern = resolvedPlaceholderLineDashPattern(style: style)
            layer.shadowColor = NSColor.black.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.10 : 0.05).cgColor
            layer.shadowRadius = IndexBoardSurfaceAppKitConstants.placeholderShadowRadius
            layer.shadowOpacity = 1
            layer.shadowOffset = CGSize(width: 0, height: IndexBoardSurfaceAppKitConstants.placeholderShadowYOffset)
            if let hostLayer = self.layer {
                if selectionLayer.superlayer === hostLayer {
                    hostLayer.insertSublayer(layer, below: selectionLayer)
                } else {
                    hostLayer.insertSublayer(layer, at: 0)
                }
            }
            nextLayers.append(layer)
        }
        updateBaselineSession { session in
            session.createdIndicatorLayers += nextLayers.count
        }
        return nextLayers
    }

    private func resolvedTargetIndicatorPresentation(
        for drag: IndexBoardSurfaceAppKitDragState
    ) -> (frames: [CGRect], style: IndexBoardSurfaceAppKitPlaceholderStyle) {
        if let detachedIndicator = resolvedDetachedIndicatorFrames(for: drag) {
            return detachedIndicator
        }
        return (resolvedFlowTargetFrames(for: drag), .detachedSlot)
    }

    private func resolvedPlaceholderFillColor(style: IndexBoardSurfaceAppKitPlaceholderStyle) -> NSColor {
        switch style {
        case .flow:
            if configuration.theme.usesDarkAppearance {
                return NSColor.white.withAlphaComponent(0.08)
            }
            return NSColor.white.withAlphaComponent(0.58)
        case .detachedSlot:
            return indexBoardThemeAccentColor(theme: configuration.theme)
                .withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.20 : 0.18)
        case .detachedParking:
            return NSColor.white.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.04 : 0.12)
        }
    }

    private func resolvedPlaceholderStrokeColor(style: IndexBoardSurfaceAppKitPlaceholderStyle) -> NSColor {
        switch style {
        case .flow:
        let borderRGB = configuration.theme.resolvedGroupBorderRGB
        return NSColor(
            calibratedRed: borderRGB.0,
            green: borderRGB.1,
            blue: borderRGB.2,
            alpha: configuration.theme.usesDarkAppearance ? 0.54 : 0.72
        )
        case .detachedSlot:
            return indexBoardThemeAccentColor(theme: configuration.theme).withAlphaComponent(0.98)
        case .detachedParking:
            return indexBoardThemeAccentColor(theme: configuration.theme)
                .withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.74 : 0.86)
        }
    }

    private func resolvedPlaceholderLineWidth(style: IndexBoardSurfaceAppKitPlaceholderStyle) -> CGFloat {
        switch style {
        case .flow:
            return 1
        case .detachedSlot:
            return IndexBoardSurfaceAppKitConstants.detachedIndicatorLineWidth
        case .detachedParking:
            return IndexBoardSurfaceAppKitConstants.detachedParkingIndicatorLineWidth
        }
    }

    private func resolvedPlaceholderLineDashPattern(style: IndexBoardSurfaceAppKitPlaceholderStyle) -> [NSNumber]? {
        switch style {
        case .detachedParking:
            return [8, 6]
        case .flow, .detachedSlot:
            return nil
        }
    }

    private func resolvedSourceGapFrames(for drag: IndexBoardSurfaceAppKitDragState) -> [CGRect] {
        let hiddenCardIDs = Set(drag.movingCardIDs)
        return drag.movingCardIDs.compactMap { cardID in
            guard hiddenCardIDs.contains(cardID) else { return nil }
            return cardFrameByID[cardID]
        }
    }

    private func resolvedFlowTargetFrames(for drag: IndexBoardSurfaceAppKitDragState) -> [CGRect] {
        guard !drag.dropTarget.isTempStripTarget,
              drag.dropTarget.detachedGridPosition == nil else {
            return []
        }

        let targetGroupID = drag.dropTarget.laneParentID.map(BoardSurfaceParentGroupID.parent) ?? .root
        guard let targetGroup = interactionProjection.parentGroups.first(where: { $0.id == targetGroupID }) else {
            return []
        }

        let insertionIndex = min(max(0, drag.dropTarget.insertionIndex), targetGroup.cardIDs.count)
        return drag.movingCardIDs.enumerated().map { offset, _ in
            resolvedCardFrame(
                for: IndexBoardGridPosition(
                    column: targetGroup.origin.column + insertionIndex + offset,
                    row: targetGroup.origin.row
                )
            )
        }
    }

    private func updateOverlayLayers() {
        withIndexBoardSurfaceAppKitSignpost(IndexBoardSurfaceAppKitSignpostName.updateOverlayLayers) {
            let measurementStart = baselineMeasurementStart()
            defer { recordBaselineTiming(\.updateOverlayLayersTiming, from: measurementStart) }
            let removedOverlayLayerCount = overlayLayers.count
            overlayLayers.forEach { $0.removeFromSuperlayer() }
            overlayLayers.removeAll()
            updateBaselineSession { session in
                session.removedOverlayLayers += removedOverlayLayerCount
            }

            if let dragState {
                syncMovingCardViewsToOverlay(for: dragState)
                let origin = dragState.overlayOrigin()
                let overlayCardIDs = resolvedOverlayCardIDs(for: dragState)
                let snapshotByID = Dictionary(uniqueKeysWithValues: dragSnapshots.map { ($0.cardID, $0.image) })

                for (index, cardID) in overlayCardIDs.enumerated() {
                    guard let image = snapshotByID[cardID],
                          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
                    let reverseIndex = overlayCardIDs.count - index - 1
                    let stackX = CGFloat(reverseIndex) * 14
                    let stackY = CGFloat(reverseIndex) * 4
                    let layer = CALayer()
                    layer.contents = cgImage
                    layer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
                    layer.isOpaque = false
                    layer.frame = CGRect(
                        x: origin.x + stackX,
                        y: origin.y + stackY,
                        width: IndexBoardMetrics.cardSize.width,
                        height: IndexBoardMetrics.cardSize.height
                    )
                    layer.shadowColor = NSColor.black.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.22 : 0.14).cgColor
                    layer.shadowOpacity = 1
                    layer.shadowRadius = IndexBoardSurfaceAppKitConstants.overlayShadowRadius
                    layer.shadowOffset = CGSize(width: 0, height: IndexBoardSurfaceAppKitConstants.overlayShadowYOffset)
                    layer.opacity = cardID == dragState.cardID ? 1 : 0.92
                    self.layer?.addSublayer(layer)
                    overlayLayers.append(layer)
                }
                updateBaselineSession { session in
                    session.createdOverlayLayers += overlayLayers.count
                }
                return
            }

            guard let groupDragState,
                  let groupDragSnapshot,
                  let cgImage = groupDragSnapshot.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let layer = CALayer()
            layer.contents = cgImage
            layer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            layer.isOpaque = false
            layer.frame = CGRect(origin: groupDragState.overlayOrigin(), size: groupDragState.initialFrame.size)
            layer.shadowColor = NSColor.black.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.22 : 0.14).cgColor
            layer.shadowOpacity = 1
            layer.shadowRadius = IndexBoardSurfaceAppKitConstants.overlayShadowRadius + 2
            layer.shadowOffset = CGSize(width: 0, height: IndexBoardSurfaceAppKitConstants.overlayShadowYOffset + 2)
            self.layer?.addSublayer(layer)
            overlayLayers.append(layer)
            updateBaselineSession { session in
                session.createdOverlayLayers += 1
            }
        }
    }

    private func syncMovingCardViewsToOverlay(for drag: IndexBoardSurfaceAppKitDragState) {
        let origin = drag.overlayOrigin()
        let orderedCardIDs = drag.movingCardIDs.filter { $0 != drag.cardID } + [drag.cardID]

        for (index, cardID) in orderedCardIDs.enumerated() {
            guard let cardView = cardViews[cardID] else { continue }
            let reverseIndex = orderedCardIDs.count - index - 1
            let stackX = CGFloat(reverseIndex) * 14
            let stackY = CGFloat(reverseIndex) * 4
            cardView.frame = CGRect(
                x: origin.x + stackX,
                y: origin.y + stackY,
                width: IndexBoardMetrics.cardSize.width,
                height: IndexBoardMetrics.cardSize.height
            )
        }
    }

    private func resolvedOverlayCardIDs(for drag: IndexBoardSurfaceAppKitDragState) -> [UUID] {
        let supportingIDs = drag.movingCardIDs.filter { $0 != drag.cardID }
        let trailingSupport = Array(supportingIDs.suffix(3))
        return trailingSupport + [drag.cardID]
    }

    private func makeSnapshotLayer(image: NSImage, frame: CGRect) -> CALayer? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let layer = CALayer()
        layer.contents = cgImage
        layer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer.isOpaque = false
        layer.frame = frame
        return layer
    }

    private func cloneLaneWrapperLayer(_ source: CAShapeLayer) -> CAShapeLayer {
        let clone = CAShapeLayer()
        clone.path = source.path
        clone.fillColor = source.fillColor
        clone.strokeColor = source.strokeColor
        clone.lineWidth = source.lineWidth
        clone.lineDashPattern = source.lineDashPattern
        clone.shadowColor = source.shadowColor
        clone.shadowRadius = source.shadowRadius
        clone.shadowOpacity = source.shadowOpacity
        clone.shadowOffset = source.shadowOffset
        return clone
    }

    private func setLiveSurfaceHidden(_ hidden: Bool) {
        for cardView in cardViews.values {
            cardView.isHidden = hidden
        }
        for chipView in laneChipViews.values {
            chipView.isHidden = hidden
        }
        for layer in laneWrapperLayers.values {
            layer.isHidden = hidden
        }
        for layer in sourceGapLayers {
            layer.isHidden = hidden
        }
        for layer in targetIndicatorLayers {
            layer.isHidden = hidden
        }
        for layer in focusIndicatorLayers {
            layer.isHidden = hidden
        }
    }

    private func beginMotionScene() {
        guard motionScene == nil,
              let hostLayer = layer else { return }

        let rootLayer = CALayer()
        rootLayer.frame = bounds

        let wrapperContainerLayer = CALayer()
        wrapperContainerLayer.frame = rootLayer.bounds
        rootLayer.addSublayer(wrapperContainerLayer)

        let indicatorContainerLayer = CALayer()
        indicatorContainerLayer.frame = rootLayer.bounds
        rootLayer.addSublayer(indicatorContainerLayer)

        let chipContainerLayer = CALayer()
        chipContainerLayer.frame = rootLayer.bounds
        rootLayer.addSublayer(chipContainerLayer)

        let cardContainerLayer = CALayer()
        cardContainerLayer.frame = rootLayer.bounds
        rootLayer.addSublayer(cardContainerLayer)

        var cardLayersByID: [UUID: CALayer] = [:]
        for item in orderedItems {
            guard let frame = cardFrameByID[item.cardID],
                  let snapshot = cardViews[item.cardID]?.snapshotImage(),
                  let cardLayer = makeSnapshotLayer(image: snapshot, frame: frame) else {
                continue
            }
            cardContainerLayer.addSublayer(cardLayer)
            cardLayersByID[item.cardID] = cardLayer
        }

        var chipLayersByLaneKey: [String: CALayer] = [:]
        for (laneKey, chipView) in laneChipViews {
            let frame = chipFrameByLaneKey[laneKey] ?? chipView.frame
            guard !frame.isEmpty,
                  let snapshot = chipView.snapshotImage(),
                  let chipLayer = makeSnapshotLayer(image: snapshot, frame: frame) else {
                continue
            }
            chipContainerLayer.addSublayer(chipLayer)
            chipLayersByLaneKey[laneKey] = chipLayer
        }

        var wrapperLayersByLaneKey: [String: CAShapeLayer] = [:]
        for group in effectiveSurfaceProjection.parentGroups {
            let laneKey = indexBoardSurfaceLaneKey(group.parentCardID)
            guard let sourceLayer = laneWrapperLayers[laneKey] else { continue }
            let wrapperLayer = cloneLaneWrapperLayer(sourceLayer)
            wrapperContainerLayer.addSublayer(wrapperLayer)
            wrapperLayersByLaneKey[laneKey] = wrapperLayer
        }

        hostLayer.insertSublayer(rootLayer, below: selectionLayer)
        motionScene = IndexBoardSurfaceAppKitMotionScene(
            rootLayer: rootLayer,
            wrapperContainerLayer: wrapperContainerLayer,
            indicatorContainerLayer: indicatorContainerLayer,
            chipContainerLayer: chipContainerLayer,
            cardContainerLayer: cardContainerLayer,
            cardLayersByID: cardLayersByID,
            chipLayersByLaneKey: chipLayersByLaneKey,
            wrapperLayersByLaneKey: wrapperLayersByLaneKey,
            sourceGapLayers: [],
            targetIndicatorLayers: []
        )
        setLiveSurfaceHidden(true)
        updateMotionSceneLayout()
    }

    private func endMotionScene() {
        motionScene?.rootLayer.removeFromSuperlayer()
        motionScene = nil
        setLiveSurfaceHidden(false)
    }

    private func resolvedPreviewLaneChipFrames(
        using cardFramesByID: [UUID: CGRect]
    ) -> [String: CGRect] {
        let orderedFlowItems = flowItems.sorted(by: indexBoardSurfaceAppKitSort)
        var seenKeys: Set<String> = []
        var frames: [String: CGRect] = [:]
        for item in orderedFlowItems {
            guard !hiddenCardIDs.contains(item.cardID) else { continue }
            let key = indexBoardSurfaceLaneKey(item.laneParentID)
            guard seenKeys.insert(key).inserted,
                  let itemFrame = cardFramesByID[item.cardID] else { continue }
            frames[key] = CGRect(
                x: itemFrame.minX,
                y: itemFrame.minY - IndexBoardSurfaceAppKitConstants.laneChipSpacing - IndexBoardSurfaceAppKitConstants.laneChipHeight,
                width: IndexBoardMetrics.cardSize.width,
                height: IndexBoardSurfaceAppKitConstants.laneChipHeight
            )
        }
        return frames
    }

    private func resolvedPreviewParentGroupFrame(
        for group: BoardSurfaceParentGroupPlacement,
        cardFramesByID: [UUID: CGRect],
        chipFramesByLaneKey: [String: CGRect]
    ) -> CGRect? {
        let groupFrames = orderedItems.compactMap { item -> CGRect? in
            guard item.parentGroupID == group.id,
                  !hiddenCardIDs.contains(item.cardID),
                  let frame = cardFramesByID[item.cardID] else { return nil }
            return frame
        }
        guard let firstFrame = groupFrames.first else { return nil }
        let cardUnion = groupFrames.dropFirst().reduce(firstFrame) { partial, frame in
            partial.union(frame)
        }
        let chipFrame = chipFramesByLaneKey[indexBoardSurfaceLaneKey(group.parentCardID)] ?? .null
        let baseFrame = chipFrame.isNull ? cardUnion : cardUnion.union(chipFrame)
        return baseFrame.insetBy(
            dx: -IndexBoardSurfaceAppKitConstants.laneWrapperInset,
            dy: -IndexBoardSurfaceAppKitConstants.laneWrapperInset
        )
    }

    private func resolvedPreviewDisplayedParentGroupFrame(
        for group: BoardSurfaceParentGroupPlacement,
        cardFramesByID: [UUID: CGRect],
        chipFramesByLaneKey: [String: CGRect]
    ) -> CGRect? {
        guard var frame = resolvedPreviewParentGroupFrame(
            for: group,
            cardFramesByID: cardFramesByID,
            chipFramesByLaneKey: chipFramesByLaneKey
        ) else {
            return nil
        }
        guard let dragState,
              dragState.dropTarget.detachedGridPosition == nil,
              !dragState.dropTarget.isTempStripTarget,
              dragState.dropTarget.laneParentID == group.parentCardID else {
            return frame
        }

        let targetFrames = resolvedFlowTargetFrames(for: dragState)
        guard !targetFrames.isEmpty else { return frame }
        for targetFrame in targetFrames {
            frame = frame.union(targetFrame.insetBy(
                dx: -IndexBoardSurfaceAppKitConstants.laneWrapperInset,
                dy: -(IndexBoardSurfaceAppKitConstants.laneWrapperInset + 2)
            ))
        }
        return frame
    }

    private func resolvedPreviewLaneWrapperFrames(
        cardFramesByID: [UUID: CGRect],
        chipFramesByLaneKey: [String: CGRect]
    ) -> [String: CGRect] {
        var frameByLaneKey: [String: CGRect] = [:]
        for group in effectiveSurfaceProjection.parentGroups {
            let key = indexBoardSurfaceLaneKey(group.parentCardID)
            if let frame = resolvedPreviewDisplayedParentGroupFrame(
                for: group,
                cardFramesByID: cardFramesByID,
                chipFramesByLaneKey: chipFramesByLaneKey
            ) {
                frameByLaneKey[key] = frame
            }
        }
        return frameByLaneKey
    }

    private func replaceMotionSceneIndicatorLayers(
        existing: [CAShapeLayer],
        frames: [CGRect],
        style: IndexBoardSurfaceAppKitPlaceholderStyle?,
        in hostLayer: CALayer
    ) -> [CAShapeLayer] {
        existing.forEach { $0.removeFromSuperlayer() }
        guard let style, !frames.isEmpty else { return [] }

        var nextLayers: [CAShapeLayer] = []
        nextLayers.reserveCapacity(frames.count)
        for frame in frames {
            let emphasizedFrame = frame.insetBy(
                dx: -IndexBoardSurfaceAppKitConstants.placeholderHighlightInset,
                dy: -IndexBoardSurfaceAppKitConstants.placeholderHighlightInset
            )
            let layer = CAShapeLayer()
            layer.path = CGPath(
                roundedRect: emphasizedFrame,
                cornerWidth: 16,
                cornerHeight: 16,
                transform: nil
            )
            layer.fillColor = resolvedPlaceholderFillColor(style: style).cgColor
            layer.strokeColor = resolvedPlaceholderStrokeColor(style: style).cgColor
            layer.lineWidth = resolvedPlaceholderLineWidth(style: style)
            layer.lineDashPattern = resolvedPlaceholderLineDashPattern(style: style)
            layer.shadowColor = NSColor.black.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.10 : 0.05).cgColor
            layer.shadowRadius = IndexBoardSurfaceAppKitConstants.placeholderShadowRadius
            layer.shadowOpacity = 1
            layer.shadowOffset = CGSize(width: 0, height: IndexBoardSurfaceAppKitConstants.placeholderShadowYOffset)
            hostLayer.addSublayer(layer)
            nextLayers.append(layer)
        }
        return nextLayers
    }

    private func updateMotionSceneLayout() {
        guard var motionScene else { return }

        motionScene.rootLayer.frame = bounds
        motionScene.wrapperContainerLayer.frame = motionScene.rootLayer.bounds
        motionScene.indicatorContainerLayer.frame = motionScene.rootLayer.bounds
        motionScene.chipContainerLayer.frame = motionScene.rootLayer.bounds
        motionScene.cardContainerLayer.frame = motionScene.rootLayer.bounds

        let previewCardFrames = resolvedCurrentCardFrames()
        for (cardID, layer) in motionScene.cardLayersByID {
            guard !hiddenCardIDs.contains(cardID),
                  let frame = previewCardFrames[cardID] ?? restingSceneSnapshot?.cardFrameByID[cardID] else {
                layer.isHidden = true
                continue
            }
            layer.frame = frame
            layer.isHidden = false
        }

        let previewChipFrames = resolvedPreviewLaneChipFrames(using: previewCardFrames)
        for (laneKey, layer) in motionScene.chipLayersByLaneKey {
            guard let frame = previewChipFrames[laneKey], !frame.isEmpty else {
                layer.isHidden = true
                continue
            }
            layer.frame = frame
            layer.isHidden = false
        }

        let previewWrapperFrames = resolvedPreviewLaneWrapperFrames(
            cardFramesByID: previewCardFrames,
            chipFramesByLaneKey: previewChipFrames
        )
        for (laneKey, wrapperLayer) in motionScene.wrapperLayersByLaneKey {
            guard let frame = previewWrapperFrames[laneKey] else {
                wrapperLayer.isHidden = true
                continue
            }
            wrapperLayer.path = CGPath(
                roundedRect: frame,
                cornerWidth: 18,
                cornerHeight: 18,
                transform: nil
            )
            wrapperLayer.isHidden = false
        }

        let sourceGapFrames: [CGRect]
        let sourceGapStyle: IndexBoardSurfaceAppKitPlaceholderStyle?
        if let dragState {
            sourceGapFrames = resolvedSourceGapFrames(for: dragState)
            sourceGapStyle = .flow
        } else if let groupDragState {
            sourceGapFrames = [groupDragState.initialFrame]
            sourceGapStyle = .flow
        } else {
            sourceGapFrames = []
            sourceGapStyle = nil
        }

        let targetFrames: [CGRect]
        let targetStyle: IndexBoardSurfaceAppKitPlaceholderStyle?
        if let dragState {
            let resolved = resolvedTargetIndicatorPresentation(for: dragState)
            targetFrames = resolved.frames
            targetStyle = resolved.style
        } else if groupDragState != nil,
                  let groupFrame = localGroupDragTargetFrame {
            targetFrames = [groupFrame]
            targetStyle = .detachedSlot
        } else {
            targetFrames = []
            targetStyle = nil
        }

        motionScene.sourceGapLayers = replaceMotionSceneIndicatorLayers(
            existing: motionScene.sourceGapLayers,
            frames: sourceGapFrames,
            style: sourceGapStyle,
            in: motionScene.indicatorContainerLayer
        )
        motionScene.targetIndicatorLayers = replaceMotionSceneIndicatorLayers(
            existing: motionScene.targetIndicatorLayers,
            frames: targetFrames,
            style: targetStyle,
            in: motionScene.indicatorContainerLayer
        )

        self.motionScene = motionScene
    }

    private func beginBaselineSession(kind: String, movingCardCount: Int) {
        _ = kind
        _ = movingCardCount
    }

    private func finishBaselineSession(didCommit: Bool) {
        _ = didCommit
    }

    private func updateBaselineSession(
        _ update: (inout IndexBoardSurfaceAppKitBaselineSession) -> Void
    ) {
        _ = update
    }

    private func baselineMeasurementStart() -> CFTimeInterval? {
        nil
    }

    private func recordBaselineTiming(
        _ keyPath: WritableKeyPath<IndexBoardSurfaceAppKitBaselineSession, IndexBoardSurfaceAppKitTimingMetric>,
        from measurementStart: CFTimeInterval?
    ) {
        _ = keyPath
        _ = measurementStart
    }

    private func recordBaselineTiming<T>(
        _ keyPath: WritableKeyPath<IndexBoardSurfaceAppKitBaselineSession, IndexBoardSurfaceAppKitTimingMetric>,
        _ body: () -> T
    ) -> T {
        _ = keyPath
        return body()
    }

    private func recordBaselineDragTick(
        autoScrolled: Bool,
        _ body: () -> Void
    ) {
        _ = autoScrolled
        body()
    }

    private func ensureRevealIfNeeded() {
        guard configuration.revealRequestToken != lastRevealRequestToken else { return }
        lastRevealRequestToken = configuration.revealRequestToken
        ensureCardVisible(configuration.revealCardID)
    }

    private func startAutoScrollTimer() {
        stopAutoScrollTimer()
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.handleAutoScrollTick()
        }
    }

    private func stopAutoScrollTimer() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }

    private func handleAutoScrollTick() {
        guard var dragState,
              let scrollView else { return }
        let visibleRect = scrollView.documentVisibleRect
        let pointerInViewport = CGPoint(
            x: dragState.pointerInContent.x - visibleRect.minX,
            y: dragState.pointerInContent.y - visibleRect.minY
        )
        let delta = CGPoint(
            x: autoScrollAxisDelta(position: pointerInViewport.x, viewportLength: visibleRect.width),
            y: autoScrollAxisDelta(position: pointerInViewport.y, viewportLength: visibleRect.height)
        )
        guard delta != .zero else { return }
        let maxX = max(0, frame.width - visibleRect.width)
        let maxY = max(0, frame.height - visibleRect.height)
        let targetX = min(max(0, visibleRect.origin.x + delta.x), maxX)
        let targetY = min(max(0, visibleRect.origin.y + delta.y), maxY)
        guard targetX != visibleRect.origin.x || targetY != visibleRect.origin.y else { return }

        scrollView.contentView.setBoundsOrigin(CGPoint(x: targetX, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        let previousTarget = dragState.dropTarget
        dragState.dropTarget = resolvedDropTarget(for: dragState)
        applyCardDragUpdate(dragState, previousTarget: previousTarget)
    }

    private func prepareViewportPreservationAfterDrop(_ preservedOrigin: CGPoint?) {
        pendingDropPreservedScrollOrigin = preservedOrigin
        suppressViewportChangeNotifications = preservedOrigin != nil
    }

    private func restoreScrollOriginAfterDrop(
        _ preservedOrigin: CGPoint?,
        notifySession: Bool
    ) {
        guard let scrollView,
              let preservedOrigin else { return }
        let visibleRect = scrollView.documentVisibleRect
        let maxX = max(0, frame.width - visibleRect.width)
        let maxY = max(0, frame.height - visibleRect.height)
        let clampedOrigin = CGPoint(
            x: min(max(0, preservedOrigin.x), maxX),
            y: min(max(0, preservedOrigin.y), maxY)
        )
        let currentOrigin = scrollView.contentView.bounds.origin
        guard abs(currentOrigin.x - clampedOrigin.x) > 0.5 ||
                abs(currentOrigin.y - clampedOrigin.y) > 0.5 else {
            return
        }
        scrollView.contentView.setBoundsOrigin(clampedOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        if notifySession {
            configuration.onScrollOffsetChange(clampedOrigin)
        }
    }

    private func autoScrollAxisDelta(position: CGFloat, viewportLength: CGFloat) -> CGFloat {
        let edge = IndexBoardSurfaceAppKitConstants.autoScrollEdgeInset
        if position < edge {
            let progress = max(0, min(1, (edge - position) / edge))
            return -IndexBoardSurfaceAppKitConstants.maxAutoScrollStep * progress
        }
        if position > viewportLength - edge {
            let progress = max(0, min(1, (position - (viewportLength - edge)) / edge))
            return IndexBoardSurfaceAppKitConstants.maxAutoScrollStep * progress
        }
        return 0
    }
}

private final class IndexBoardSurfaceAppKitContainerView: NSView {
    private let backgroundView: IndexBoardSurfaceAppKitBackgroundView
    private let scrollView: NSScrollView
    private let documentView: IndexBoardSurfaceAppKitDocumentView
    private var lastContainerRenderState: IndexBoardSurfaceAppKitRenderState
    private var scrollObserver: NSObjectProtocol?
    private var willStartLiveScrollObserver: NSObjectProtocol?
    private var didEndLiveScrollObserver: NSObjectProtocol?
    private var willStartMagnifyObserver: NSObjectProtocol?
    private var magnifyObserver: NSObjectProtocol?
    private var isApplyingExternalViewport = false
    private var isLiveScrolling = false
    private var isLiveMagnifying = false
    private var viewportSession: IndexBoardSurfaceAppKitViewportSession?
    private var viewportCommitTimer: Timer?
    private var pendingLiveMagnification: CGFloat?
    private var pendingLiveScrollOrigin: CGPoint?
    private var hoverResumeTimer: Timer?
    private var pendingViewportReapplyAttempts = 0
    private var isRestoringInitialViewport = true
    private var hasPresentedInitialViewport = false
    private let viewportDebugID = String(UUID().uuidString.prefix(8))
    private var viewportDebugLogBudget = 24

    init(configuration: IndexBoardSurfaceAppKitConfiguration) {
        backgroundView = IndexBoardSurfaceAppKitBackgroundView(theme: configuration.theme)
        scrollView = NSScrollView(frame: .zero)
        documentView = IndexBoardSurfaceAppKitDocumentView(configuration: configuration)
        lastContainerRenderState = configuration.renderState
        super.init(frame: .zero)
        wantsLayer = true

        backgroundView.frame = bounds
        backgroundView.autoresizingMask = [.width, .height]
        addSubview(backgroundView)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.usesPredominantAxisScrolling = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero
        scrollView.scrollerInsets = NSEdgeInsetsZero
        scrollView.allowsMagnification = true
        scrollView.minMagnification = IndexBoardZoom.minScale
        scrollView.maxMagnification = IndexBoardZoom.maxScale
        scrollView.documentView = documentView
        scrollView.contentView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.contentInsets = NSEdgeInsetsZero
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.alphaValue = 0
        documentView.scrollView = scrollView
        addSubview(scrollView)
        suppressScrollPocketVisuals()

        update(configuration: configuration)
        installViewportObservers()
        logViewportDebug("init_complete")
    }

    private func installViewportObservers() {
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.handleViewportChanged()
        }
        willStartLiveScrollObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.isLiveScrolling = true
            self?.isRestoringInitialViewport = false
            self?.updateInitialViewportPresentation()
        }
        didEndLiveScrollObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isLiveScrolling = false
            self.viewportSession = nil
            let origin = self.scrollView.contentView.bounds.origin
            self.pendingLiveScrollOrigin = CGPoint(
                x: max(0, origin.x),
                y: max(0, origin.y)
            )
        }
        willStartMagnifyObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveMagnifyNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.isLiveMagnifying = true
            self?.isRestoringInitialViewport = false
            self?.updateInitialViewportPresentation()
        }
        magnifyObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.isLiveMagnifying = false
            self?.syncViewportAfterLiveMagnify()
            self?.documentView.refreshDisplayAfterLiveMagnify()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
        }
        if let willStartLiveScrollObserver {
            NotificationCenter.default.removeObserver(willStartLiveScrollObserver)
        }
        if let didEndLiveScrollObserver {
            NotificationCenter.default.removeObserver(didEndLiveScrollObserver)
        }
        if let willStartMagnifyObserver {
            NotificationCenter.default.removeObserver(willStartMagnifyObserver)
        }
        if let magnifyObserver {
            NotificationCenter.default.removeObserver(magnifyObserver)
        }
        flushViewportPersistenceForTeardown()
    }

    override func layout() {
        super.layout()
        backgroundView.frame = bounds
        scrollView.frame = bounds
        normalizeScrollViewInsets()
        suppressScrollPocketVisuals()
        applyConfiguredViewportIfNeeded()
        scheduleDeferredViewportReapplyIfNeeded()
        updateInitialViewportPresentation()
        logViewportDebug("layout")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        normalizeScrollViewInsets()
        suppressScrollPocketVisuals()
        DispatchQueue.main.async { [weak self] in
            self?.applyConfiguredViewportIfNeeded()
            self?.scheduleDeferredViewportReapplyIfNeeded()
            self?.updateInitialViewportPresentation()
            self?.logViewportDebug("view_did_move_to_window_async")
        }
    }

    func update(configuration: IndexBoardSurfaceAppKitConfiguration) {
        let nextRenderState = configuration.renderState
        let requiresFullRenderUpdate =
            !nextRenderState.equalsIgnoringViewport(lastContainerRenderState)
        backgroundView.theme = configuration.theme
        if requiresFullRenderUpdate {
            documentView.updateConfiguration(configuration)
            documentView.layoutSubtreeIfNeeded()
        } else {
            documentView.updateConfigurationForViewportOnly(configuration)
        }
        lastContainerRenderState = nextRenderState

        if let pendingLiveMagnification {
            if abs(configuration.zoomScale - pendingLiveMagnification) <= 0.001 {
                self.pendingLiveMagnification = nil
            }
        }
        if let pendingLiveScrollOrigin {
            if abs(configuration.scrollOffset.x - pendingLiveScrollOrigin.x) <= 0.5 &&
                abs(configuration.scrollOffset.y - pendingLiveScrollOrigin.y) <= 0.5 {
                self.pendingLiveScrollOrigin = nil
            }
        }

        applyConfiguredViewportIfNeeded()
        scheduleDeferredViewportReapplyIfNeeded()
        updateInitialViewportPresentation()
        logViewportDebug("update")

        if let preservedOrigin = documentView.pendingDropPreservedScrollOrigin {
            let visibleRect = scrollView.documentVisibleRect
            let maxX = max(0, documentView.frame.width - visibleRect.width)
            let maxY = max(0, documentView.frame.height - visibleRect.height)
            let clampedOrigin = CGPoint(
                x: min(max(0, preservedOrigin.x), maxX),
                y: min(max(0, preservedOrigin.y), maxY)
            )
            let currentOrigin = scrollView.contentView.bounds.origin
            if abs(currentOrigin.x - clampedOrigin.x) > 0.5 ||
                abs(currentOrigin.y - clampedOrigin.y) > 0.5 {
                isApplyingExternalViewport = true
                scrollView.contentView.setBoundsOrigin(NSPoint(x: clampedOrigin.x, y: clampedOrigin.y))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                isApplyingExternalViewport = false
            }
            if abs(clampedOrigin.x - configuration.scrollOffset.x) > 0.5 ||
                abs(clampedOrigin.y - configuration.scrollOffset.y) > 0.5 {
                documentView.configuration.onScrollOffsetChange(clampedOrigin)
            }
            documentView.pendingDropPreservedScrollOrigin = nil
            documentView.suppressViewportChangeNotifications = false
        }

        suppressScrollPocketVisuals()

    }

    private func applyConfiguredViewportIfNeeded() {
        if viewportNeedsExternalApply() {
            logViewportDebug("apply_begin")
        }
        let configuration = documentView.configuration

        if !isLiveMagnifying,
           pendingLiveMagnification == nil,
           abs(scrollView.magnification - configuration.zoomScale) > 0.001 {
            isApplyingExternalViewport = true
            scrollView.setMagnification(
                configuration.zoomScale,
                centeredAt: resolvedMagnificationCenter()
            )
            isApplyingExternalViewport = false
        }

        let currentOrigin = scrollView.contentView.bounds.origin
        if !isLiveMagnifying &&
            viewportSession == nil &&
            pendingLiveScrollOrigin == nil &&
            documentView.pendingDropPreservedScrollOrigin == nil &&
            (abs(currentOrigin.x - configuration.scrollOffset.x) > 0.5 ||
             abs(currentOrigin.y - configuration.scrollOffset.y) > 0.5) {
            isApplyingExternalViewport = true
            scrollView.contentView.setBoundsOrigin(
                NSPoint(
                    x: max(0, configuration.scrollOffset.x),
                    y: max(0, configuration.scrollOffset.y)
                )
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
            isApplyingExternalViewport = false
        }
        if viewportNeedsExternalApply() {
            logViewportDebug("apply_end_needs_more")
        } else {
            logViewportDebug("apply_end_resolved")
        }
    }

    private func viewportNeedsExternalApply() -> Bool {
        guard !isLiveMagnifying,
              viewportSession == nil,
              pendingLiveScrollOrigin == nil,
              documentView.pendingDropPreservedScrollOrigin == nil else {
            return false
        }

        let configuration = documentView.configuration
        let currentOrigin = scrollView.contentView.bounds.origin
        let needsScaleApply = abs(scrollView.magnification - configuration.zoomScale) > 0.001
        let needsOriginApply =
            abs(currentOrigin.x - configuration.scrollOffset.x) > 0.5 ||
            abs(currentOrigin.y - configuration.scrollOffset.y) > 0.5
        return needsScaleApply || needsOriginApply
    }

    private func scheduleDeferredViewportReapplyIfNeeded(maxAttempts: Int = 4) {
        guard viewportNeedsExternalApply() else {
            pendingViewportReapplyAttempts = 0
            return
        }
        guard pendingViewportReapplyAttempts == 0 else { return }
        pendingViewportReapplyAttempts = maxAttempts
        performDeferredViewportReapply()
    }

    private func performDeferredViewportReapply() {
        guard pendingViewportReapplyAttempts > 0 else { return }
        pendingViewportReapplyAttempts -= 1
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyConfiguredViewportIfNeeded()
            self.logViewportDebug("deferred_apply_tick")
            if self.isRestoringInitialViewport, self.initialViewportRestoreCompleted() {
                self.isRestoringInitialViewport = false
            }
            self.updateInitialViewportPresentation()
            if self.viewportNeedsExternalApply(), self.pendingViewportReapplyAttempts > 0 {
                self.performDeferredViewportReapply()
            } else {
                self.pendingViewportReapplyAttempts = 0
            }
        }
    }

    private func updateInitialViewportPresentation() {
        if isRestoringInitialViewport, initialViewportRestoreCompleted() {
            isRestoringInitialViewport = false
        }

        let shouldPresent = !isRestoringInitialViewport
        guard shouldPresent != hasPresentedInitialViewport else { return }
        hasPresentedInitialViewport = shouldPresent
        scrollView.alphaValue = shouldPresent ? 1 : 0
    }

    private func initialViewportRestoreCompleted() -> Bool {
        let configuration = documentView.configuration
        let visibleRect = scrollView.documentVisibleRect
        guard visibleRect.width > 1, visibleRect.height > 1 else { return false }
        guard documentView.frame.width > 1, documentView.frame.height > 1 else { return false }

        let currentOrigin = scrollView.contentView.bounds.origin
        let matchesScale = abs(scrollView.magnification - configuration.zoomScale) <= 0.001
        let matchesOrigin =
            abs(currentOrigin.x - configuration.scrollOffset.x) <= 0.5 &&
            abs(currentOrigin.y - configuration.scrollOffset.y) <= 0.5
        return matchesScale && matchesOrigin
    }

    private func logViewportDebug(_ event: String) {
        guard viewportDebugLogBudget > 0 else { return }
        viewportDebugLogBudget -= 1
        let configuration = documentView.configuration
        let currentOrigin = scrollView.contentView.bounds.origin
        let visibleRect = scrollView.documentVisibleRect
        indexBoardRestoreTrace(
            "board_surface_\(event)",
            "id=\(self.viewportDebugID) desiredScroll=(\(String(format: "%.2f", configuration.scrollOffset.x)),\(String(format: "%.2f", configuration.scrollOffset.y))) " +
            "currentScroll=(\(String(format: "%.2f", currentOrigin.x)),\(String(format: "%.2f", currentOrigin.y))) " +
            "desiredZoom=\(String(format: "%.2f", configuration.zoomScale)) currentZoom=\(String(format: "%.2f", self.scrollView.magnification)) " +
            "docSize=(\(String(format: "%.2f", self.documentView.frame.width)),\(String(format: "%.2f", self.documentView.frame.height))) " +
            "visibleRect=(\(String(format: "%.2f", visibleRect.width)),\(String(format: "%.2f", visibleRect.height))) " +
            "containerBounds=(\(String(format: "%.2f", self.bounds.width)),\(String(format: "%.2f", self.bounds.height))) " +
            "reapplyAttempts=\(self.pendingViewportReapplyAttempts)"
        )
    }

    private func handleViewportChanged() {
        guard !isApplyingExternalViewport,
              !documentView.suppressViewportChangeNotifications else { return }
        if documentView.isInteractingLocally {
            return
        }
        if isRestoringInitialViewport {
            if initialViewportRestoreCompleted() {
                isRestoringInitialViewport = false
            } else {
                scheduleDeferredViewportReapplyIfNeeded()
                logViewportDebug("skip_initial_viewport_change")
                return
            }
        }
        if isLiveMagnifying {
            documentView.refreshHoverIndicatorFromCurrentMouse()
            return
        }
        let origin = scrollView.contentView.bounds.origin
        let resolvedOrigin = CGPoint(x: max(0, origin.x), y: max(0, origin.y))
        let referenceOrigin = viewportSession?.liveScrollOrigin ?? documentView.configuration.scrollOffset
        guard abs(resolvedOrigin.x - referenceOrigin.x) > 0.5 ||
                abs(resolvedOrigin.y - referenceOrigin.y) > 0.5 else {
            documentView.refreshHoverIndicatorFromCurrentMouse()
            return
        }
        updateViewportSessionFromScrollView()
        pendingLiveScrollOrigin = resolvedOrigin
        documentView.configuration.onScrollOffsetChange(resolvedOrigin)
        suspendHoverIndicatorForScroll()
    }

    private func handleMagnificationChanged() {
        guard !isApplyingExternalViewport else { return }
        guard abs(scrollView.magnification - documentView.configuration.zoomScale) > 0.001 else { return }
        documentView.configuration.onZoomScaleChange(scrollView.magnification)
    }

    private func syncViewportAfterLiveMagnify() {
        guard !isApplyingExternalViewport else { return }
        pendingLiveMagnification = scrollView.magnification
        handleMagnificationChanged()
        let origin = scrollView.contentView.bounds.origin
        let resolvedOrigin = CGPoint(x: max(0, origin.x), y: max(0, origin.y))
        pendingLiveScrollOrigin = resolvedOrigin
        if abs(resolvedOrigin.x - documentView.configuration.scrollOffset.x) > 0.5 ||
            abs(resolvedOrigin.y - documentView.configuration.scrollOffset.y) > 0.5 {
            documentView.configuration.onScrollOffsetChange(resolvedOrigin)
        }
        documentView.refreshHoverIndicatorFromCurrentMouse()
    }

    private func suspendHoverIndicatorForScroll() {
        documentView.setHoverIndicatorSuppressed(true)
        resumeHoverIndicatorAfterScrollDelay()
    }

    private func scheduleViewportCommit() {
        viewportCommitTimer?.invalidate()
        viewportCommitTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
            self?.commitViewportSessionIfNeeded()
        }
    }

    private func commitViewportSessionIfNeeded() {
        viewportCommitTimer?.invalidate()
        viewportCommitTimer = nil
        guard let viewportSession else { return }
        let resolvedOrigin = CGPoint(
            x: max(0, viewportSession.liveScrollOrigin.x),
            y: max(0, viewportSession.liveScrollOrigin.y)
        )
        self.viewportSession = nil
        pendingLiveScrollOrigin = resolvedOrigin
        if abs(resolvedOrigin.x - documentView.configuration.scrollOffset.x) > 0.5 ||
            abs(resolvedOrigin.y - documentView.configuration.scrollOffset.y) > 0.5 {
            documentView.configuration.onScrollOffsetChange(resolvedOrigin)
        }
    }

    private func resumeHoverIndicatorAfterScrollDelay() {
        hoverResumeTimer?.invalidate()
        hoverResumeTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.documentView.setHoverIndicatorSuppressed(false)
            self.documentView.refreshHoverIndicatorFromCurrentMouse()
        }
    }

    private func updateViewportSessionFromScrollView() {
        let origin = scrollView.contentView.bounds.origin
        let resolvedOrigin = CGPoint(x: max(0, origin.x), y: max(0, origin.y))
        if var viewportSession {
            viewportSession.liveMagnification = scrollView.magnification
            viewportSession.liveScrollOrigin = resolvedOrigin
            self.viewportSession = viewportSession
        } else {
            viewportSession = IndexBoardSurfaceAppKitViewportSession(
                baselineMagnification: scrollView.magnification,
                baselineScrollOrigin: resolvedOrigin,
                liveMagnification: scrollView.magnification,
                liveScrollOrigin: resolvedOrigin
            )
        }
    }

    func flushViewportPersistenceForTeardown() {
        viewportCommitTimer?.invalidate()
        viewportCommitTimer = nil
        hoverResumeTimer?.invalidate()
        hoverResumeTimer = nil

        let resolvedScale = min(max(scrollView.magnification, IndexBoardZoom.minScale), IndexBoardZoom.maxScale)
        let origin = scrollView.contentView.bounds.origin
        let resolvedOrigin = CGPoint(
            x: max(0, origin.x),
            y: max(0, origin.y)
        )
        documentView.configuration.onViewportFinalize(resolvedScale, resolvedOrigin)
    }

    private func normalizeScrollViewInsets() {
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero
        scrollView.scrollerInsets = NSEdgeInsetsZero
        scrollView.contentView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.contentInsets = NSEdgeInsetsZero
    }

    private func suppressScrollPocketVisuals() {
        hideScrollPocketSubviews(in: scrollView)
    }

    private func hideScrollPocketSubviews(in view: NSView) {
        for subview in view.subviews {
            let className = NSStringFromClass(type(of: subview))
            if shouldHideScrollPocketSubview(className: className) {
                subview.isHidden = true
                subview.alphaValue = 0
            } else {
                hideScrollPocketSubviews(in: subview)
            }
        }
    }

    private func shouldHideScrollPocketSubview(className: String) -> Bool {
        className.contains("NSScrollPocket")
    }

    private func resolvedMagnificationCenter() -> CGPoint {
        let visibleRect = scrollView.documentVisibleRect
        return CGPoint(x: visibleRect.midX, y: visibleRect.midY)
    }
}

private struct IndexBoardSurfaceAppKitCanvas: NSViewRepresentable {
    let configuration: IndexBoardSurfaceAppKitConfiguration

    func makeNSView(context: Context) -> IndexBoardSurfaceAppKitContainerView {
        IndexBoardSurfaceAppKitContainerView(configuration: configuration)
    }

    func updateNSView(_ nsView: IndexBoardSurfaceAppKitContainerView, context: Context) {
        nsView.update(configuration: configuration)
    }

    static func dismantleNSView(_ nsView: IndexBoardSurfaceAppKitContainerView, coordinator: ()) {
        nsView.flushViewportPersistenceForTeardown()
    }
}

@MainActor
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
