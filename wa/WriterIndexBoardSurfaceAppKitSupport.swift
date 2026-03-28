import SwiftUI
import AppKit
import os.signpost

enum IndexBoardSurfaceAppKitConstants {
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
    static let groupSlotActivationHorizontalInset: CGFloat = 4
    static let groupSlotActivationVerticalInset: CGFloat = 4
    static let groupSlotRetentionHorizontalInset: CGFloat = 20
    static let groupSlotRetentionVerticalInset: CGFloat = 18
    static let cardDropProbeHorizontalInset: CGFloat = 28
    static let cardDropProbeVerticalInset: CGFloat = 26
    static let cardDropTerminalReach: CGFloat = 44
    static let detachedBlockTargetHorizontalInset: CGFloat = 26
    static let detachedBlockTargetVerticalInset: CGFloat = 28
    static let detachedStripInteractionHorizontalInset: CGFloat = 36
    static let detachedStripInteractionVerticalInset: CGFloat = 76
    static let detachedStripRetentionHorizontalInset: CGFloat = 52
    static let detachedStripRetentionVerticalInset: CGFloat = 108
    static let detachedStripActivationVerticalMultiplier: CGFloat = 0.5
    static let detachedStripRetentionVerticalMultiplier: CGFloat = 0.8
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

let indexBoardSurfaceAppKitSignpostLog = OSLog(
    subsystem: Bundle.main.bundleIdentifier ?? "com.riwoong.wa",
    category: "BoardMotion"
)

enum IndexBoardSurfaceAppKitSignpostName {
    static let dragTick: StaticString = "drag_tick"
    static let resolvedDropTarget: StaticString = "resolved_drop_target"
    static let resolvedLocalCardPreview: StaticString = "resolved_local_card_drag_preview"
    static let resolvedLocalGroupPreview: StaticString = "resolved_local_group_drag_preview"
    static let applyCurrentLayout: StaticString = "apply_current_layout"
    static let updateIndicatorLayers: StaticString = "update_indicator_layers"
    static let updateOverlayLayers: StaticString = "update_overlay_layers"
}

@inline(__always)
func withIndexBoardSurfaceAppKitSignpost<T>(
    _ name: StaticString,
    _ body: () -> T
) -> T {
    _ = name
    return body()
}

struct IndexBoardSurfaceAppKitTimingMetric {
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

struct IndexBoardSurfaceAppKitBaselineSession {
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

struct IndexBoardSurfaceAppKitMotionScene {
    let rootLayer: CALayer
    let wrapperContainerLayer: CALayer
    let indicatorContainerLayer: CALayer
    let chipContainerLayer: CALayer
    let cardContainerLayer: CALayer
    let hiddenLiveCardIDs: Set<UUID>
    let hidesLiveChips: Bool
    let hidesLiveWrappers: Bool
    var cardLayersByID: [UUID: CALayer]
    var chipLayersByLaneKey: [String: CALayer]
    var wrapperLayersByLaneKey: [String: CAShapeLayer]
    var sourceGapLayers: [CAShapeLayer]
    var targetIndicatorLayers: [CAShapeLayer]
}

enum IndexBoardSurfaceAppKitBaselineLogger {
    static let isEnabled = false
    static let logURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("wa_board_motion_baseline.log")

    static func append(session: IndexBoardSurfaceAppKitBaselineSession, didCommit: Bool) {
        guard isEnabled else { return }
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

struct IndexBoardSurfaceColorPreset {
    let name: String
    let hex: String
}

let indexBoardSurfaceColorPresets: [IndexBoardSurfaceColorPreset] = [
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

let indexBoardSurfaceDefaultColorToken = "__INDEX_BOARD_DEFAULT_COLOR__"

func indexBoardSurfaceColorSwatchImage(
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

func indexBoardSurfaceAppKitSort(_ lhs: BoardSurfaceItem, _ rhs: BoardSurfaceItem) -> Bool {
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

func indexBoardSurfaceLaneKey(_ laneParentID: UUID?) -> String {
    laneParentID?.uuidString ?? "root"
}

func indexBoardSurfaceAppKitGroupSort(
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

struct IndexBoardSurfaceAppKitGridBounds {
    let minColumn: Int
    let maxColumn: Int
    let minRow: Int
    let maxRow: Int

    var columnCount: Int { max(1, maxColumn - minColumn + 1) }
    var rowCount: Int { max(1, maxRow - minRow + 1) }
}

struct IndexBoardSurfaceAppKitSceneSnapshot {
    let projection: BoardSurfaceProjection
    let orderedItems: [BoardSurfaceItem]
    let cardFrameByID: [UUID: CGRect]
    let chipFrameByLaneKey: [String: CGRect]
    let occupiedGridPositionByCardID: [UUID: IndexBoardGridPosition]
    let logicalGridBounds: IndexBoardSurfaceAppKitGridBounds
}

struct IndexBoardSurfaceAppKitLogicalSnapshot {
    let projection: BoardSurfaceProjection
    let orderedItems: [BoardSurfaceItem]
    let detachedPositionsByCardID: [UUID: IndexBoardGridPosition]
    let tempStrips: [IndexBoardTempStripState]
    let tempGroupWidthsByParentID: [UUID: Int]
}

enum IndexBoardSurfaceAppKitDropPlacement: Equatable {
    case flow(Int)
    case detached(IndexBoardGridPosition)
}

struct IndexBoardSurfaceAppKitDragState {
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

struct IndexBoardSurfaceAppKitPendingCardMove {
    let logicalSnapshot: IndexBoardSurfaceAppKitLogicalSnapshot
    let movingCardIDs: [UUID]
    let movingCardIDSet: Set<UUID>
    let movingTempMembers: [IndexBoardTempStripMember]
    let sourceLaneParentID: UUID?
    let target: IndexBoardCardDropTarget
}

enum IndexBoardSurfaceAppKitPlaceholderStyle {
    case flow
    case detachedSlot
    case detachedParking
}

struct IndexBoardSurfaceAppKitSelectionState {
    let startPoint: CGPoint
    var currentPoint: CGPoint
}

struct IndexBoardSurfaceAppKitViewportSession {
    let baselineMagnification: CGFloat
    let baselineScrollOrigin: CGPoint
    var liveMagnification: CGFloat
    var liveScrollOrigin: CGPoint
}

struct IndexBoardSurfaceAppKitGroupDragState {
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

struct IndexBoardSurfaceAppKitGroupDragPreview {
    let cardFramesByID: [UUID: CGRect]
    let targetFrame: CGRect?
}

struct IndexBoardSurfaceAppKitConfiguration {
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

struct IndexBoardSurfaceAppKitCardRenderState: Equatable {
    let content: String
    let colorHex: String?
    let cloneGroupID: UUID?
}

struct IndexBoardSurfaceAppKitRenderState: Equatable {
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

struct IndexBoardSurfaceAppKitLayoutDiff {
    let changedCardIDs: Set<UUID>
    let affectedLaneKeys: Set<String>
}

extension IndexBoardSurfaceAppKitConfiguration {
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

struct IndexBoardSurfaceAppKitCardSnapshot {
    let cardID: UUID
    let image: NSImage
}

struct IndexBoardSurfaceAppKitLaneChipModel {
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

extension CGFloat {
    var roundedToPixel: CGFloat { rounded(.toNearestOrAwayFromZero) }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

extension CGRect {
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

func indexBoardThemeColor(
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

func indexBoardThemeBorderColor(
    theme: IndexBoardRenderTheme,
    isSelected: Bool,
    isActive: Bool
) -> NSColor {
    let borderRGB = theme.resolvedGroupBorderRGB
    return NSColor(calibratedRed: borderRGB.0, green: borderRGB.1, blue: borderRGB.2, alpha: 0.78)
}

func indexBoardThemePrimaryTextColor(theme: IndexBoardRenderTheme) -> NSColor {
    theme.usesDarkAppearance
        ? NSColor(calibratedWhite: 1, alpha: 0.92)
        : NSColor(calibratedWhite: 0, alpha: 0.82)
}

func indexBoardThemeSecondaryTextColor(theme: IndexBoardRenderTheme) -> NSColor {
    theme.usesDarkAppearance
        ? NSColor(calibratedWhite: 1, alpha: 0.60)
        : NSColor(calibratedWhite: 0, alpha: 0.54)
}

func indexBoardThemeBoardGradient(theme: IndexBoardRenderTheme) -> NSGradient {
    let startRGB = theme.resolvedBoardBackgroundStartRGB
    let endRGB = theme.resolvedBoardBackgroundEndRGB
    return NSGradient(
        starting: NSColor(calibratedRed: startRGB.0, green: startRGB.1, blue: startRGB.2, alpha: 1),
        ending: NSColor(calibratedRed: endRGB.0, green: endRGB.1, blue: endRGB.2, alpha: 1)
    )!
}

func indexBoardThemeAccentColor(theme: IndexBoardRenderTheme) -> NSColor {
    let accentRGB = theme.resolvedAccentRGB
    return NSColor(calibratedRed: accentRGB.0, green: accentRGB.1, blue: accentRGB.2, alpha: 1)
}

func indexBoardSurfaceResolvedPreviewText(
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

func indexBoardSurfaceSingleLinePreview(_ text: String) -> String {
    let collapsed = text
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return collapsed.isEmpty ? "내용 없음" : collapsed
}

