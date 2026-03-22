import SwiftUI
import AppKit

private enum IndexBoardSurfaceAppKitConstants {
    static let laneChipHeight: CGFloat = 26
    static let laneChipSpacing: CGFloat = 6
    static let lineSpacing: CGFloat = 18
    static let detachedOuterPaddingSlots = 4
    static let surfaceHorizontalOverscan: CGFloat = 0
    static let surfaceVerticalOverscan: CGFloat = 0
    static let minimumCanvasLeadInset: CGFloat = 144
    static let minimumCanvasTopInset: CGFloat = 72
    static let laneWrapperInset: CGFloat = 10
    static let flowInteractionHorizontalInset: CGFloat = 88
    static let flowInteractionVerticalInset: CGFloat = 112
    static let flowInteractionVerticalHysteresis: CGFloat = 148
    static let autoScrollEdgeInset: CGFloat = 80
    static let maxAutoScrollStep: CGFloat = 22
    static let dragThreshold: CGFloat = 3
    static let previewLayoutAnimationDuration: TimeInterval = 0.16
    static let commitLayoutAnimationDuration: TimeInterval = 0.18
    static let overlayShadowRadius: CGFloat = 18
    static let overlayShadowYOffset: CGFloat = 10
    static let cardDropTargetHorizontalInset: CGFloat = 18
    static let cardDropTargetVerticalInset: CGFloat = 20
    static let cardDropRetentionHorizontalInset: CGFloat = 38
    static let cardDropRetentionVerticalInset: CGFloat = 34
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
    static let detachedIndicatorLineWidth: CGFloat = 3
    static let detachedParkingIndicatorLineWidth: CGFloat = 2
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
    let onCreateParentFromSelection: () -> Void
    let onSetParentGroupTemp: (UUID, Bool) -> Void
    let onCardTap: (SceneCard) -> Void
    let onCardDragStart: ([UUID], UUID) -> Void
    let onCardOpen: (SceneCard) -> Void
    let onCardMove: (UUID, IndexBoardCardDropTarget) -> Void
    let onCardMoveSelection: ([UUID], UUID, IndexBoardCardDropTarget) -> Void
    let onMarqueeSelectionChange: (Set<UUID>) -> Void
    let onClearSelection: () -> Void
    let onScrollOffsetChange: (CGPoint) -> Void
    let onZoomScaleChange: (CGFloat) -> Void
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
    let usesDarkAppearance: Bool
    let cardBaseColorHex: String
    let cardActiveColorHex: String
    let darkCardBaseColorHex: String
    let darkCardActiveColorHex: String
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
            usesDarkAppearance: theme.usesDarkAppearance,
            cardBaseColorHex: theme.cardBaseColorHex,
            cardActiveColorHex: theme.cardActiveColorHex,
            darkCardBaseColorHex: theme.darkCardBaseColorHex,
            darkCardActiveColorHex: theme.darkCardActiveColorHex
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
}

extension IndexBoardSurfaceAppKitLaneChipModel: Equatable {
    static func == (
        lhs: IndexBoardSurfaceAppKitLaneChipModel,
        rhs: IndexBoardSurfaceAppKitLaneChipModel
    ) -> Bool {
        lhs.lane == rhs.lane &&
        lhs.theme.usesDarkAppearance == rhs.theme.usesDarkAppearance &&
        lhs.theme.cardActiveColorHex == rhs.theme.cardActiveColorHex &&
        lhs.theme.darkCardActiveColorHex == rhs.theme.darkCardActiveColorHex
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
    let accentHex = theme.usesDarkAppearance ? theme.darkCardActiveColorHex : theme.cardActiveColorHex
    let baseRGB = parseHexRGB(customHex ?? baseHex) ?? (theme.usesDarkAppearance ? (0.16, 0.17, 0.20) : (1.0, 1.0, 1.0))
    let accentRGB = parseHexRGB(accentHex) ?? (theme.usesDarkAppearance ? (0.31, 0.40, 0.52) : (0.74, 0.84, 0.98))
    let amount: Double
    if isActive {
        amount = theme.usesDarkAppearance ? 0.52 : 0.42
    } else if isSelected {
        amount = theme.usesDarkAppearance ? 0.32 : 0.26
    } else {
        amount = 0
    }
    let mixed = (
        baseRGB.0 + ((accentRGB.0 - baseRGB.0) * amount),
        baseRGB.1 + ((accentRGB.1 - baseRGB.1) * amount),
        baseRGB.2 + ((accentRGB.2 - baseRGB.2) * amount)
    )
    return NSColor(
        calibratedRed: mixed.0,
        green: mixed.1,
        blue: mixed.2,
        alpha: 1
    )
}

private func indexBoardThemeBorderColor(
    theme: IndexBoardRenderTheme,
    isSelected: Bool,
    isActive: Bool
) -> NSColor {
    let accentHex = theme.usesDarkAppearance ? theme.darkCardActiveColorHex : theme.cardActiveColorHex
    let accentRGB = parseHexRGB(accentHex) ?? (theme.usesDarkAppearance ? (0.31, 0.40, 0.52) : (0.74, 0.84, 0.98))
    let borderRGB = theme.usesDarkAppearance ? (0.28, 0.30, 0.36) : (0.78, 0.75, 0.69)
    if isActive {
        return NSColor(calibratedRed: accentRGB.0, green: accentRGB.1, blue: accentRGB.2, alpha: 0.96)
    }
    if isSelected {
        return NSColor(calibratedRed: accentRGB.0, green: accentRGB.1, blue: accentRGB.2, alpha: 0.64)
    }
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
    let topRGB = theme.usesDarkAppearance ? (0.10, 0.11, 0.13) : (0.96, 0.94, 0.89)
    let bottomRGB = theme.usesDarkAppearance ? (0.14, 0.15, 0.18) : (0.90, 0.88, 0.82)
    return NSGradient(
        starting: NSColor(calibratedRed: topRGB.0, green: topRGB.1, blue: topRGB.2, alpha: 1),
        ending: NSColor(calibratedRed: bottomRGB.0, green: bottomRGB.1, blue: bottomRGB.2, alpha: 1)
    )!
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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        indexBoardThemeBoardGradient(theme: theme).draw(in: bounds, angle: -32)
    }
}

private final class IndexBoardSurfaceAppKitLaneChipView: NSView {
    private var model: IndexBoardSurfaceAppKitLaneChipModel?

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

    func update(model: IndexBoardSurfaceAppKitLaneChipModel) {
        guard self.model != model || bounds.size != frame.size else { return }
        self.model = model
        needsDisplay = true
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

        let eyebrowText = resolvedEyebrowText(for: model.lane)
        let eyebrowFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        let labelFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let primaryTextColor = model.theme.usesDarkAppearance
            ? NSColor(calibratedWhite: 1, alpha: 0.92)
            : NSColor(calibratedWhite: 0, alpha: 0.82)
        let eyebrowTextColor = model.lane.isTempLane
            ? NSColor.orange.withAlphaComponent(0.94)
            : NSColor.black.withAlphaComponent(model.theme.usesDarkAppearance ? 0.72 : 0.54)
        let eyebrowBackgroundColor = model.lane.isTempLane
            ? NSColor.orange.withAlphaComponent(model.theme.usesDarkAppearance ? 0.24 : 0.16)
            : NSColor.black.withAlphaComponent(model.theme.usesDarkAppearance ? 0.16 : 0.06)

        let contentRect = bounds.insetBy(dx: 9, dy: 4)
        let eyebrowAttributes: [NSAttributedString.Key: Any] = [
            .font: eyebrowFont,
            .foregroundColor: eyebrowTextColor
        ]
        let eyebrowAttributed = NSAttributedString(string: eyebrowText, attributes: eyebrowAttributes)
        let eyebrowSize = eyebrowAttributed.size()
        let eyebrowRect = CGRect(
            x: contentRect.minX,
            y: bounds.midY - 9,
            width: eyebrowSize.width + 14,
            height: 18
        )
        let eyebrowPath = NSBezierPath(roundedRect: eyebrowRect, xRadius: 9, yRadius: 9)
        eyebrowBackgroundColor.setFill()
        eyebrowPath.fill()
        eyebrowAttributed.draw(at: CGPoint(x: eyebrowRect.minX + 7, y: eyebrowRect.minY + 4))

        let dotRect = CGRect(
            x: eyebrowRect.maxX + 11,
            y: bounds.midY - 3.5,
            width: 7,
            height: 7
        )
        let dotPath = NSBezierPath(ovalIn: dotRect)
        tint.withAlphaComponent(model.theme.usesDarkAppearance ? 0.84 : 0.92).setFill()
        dotPath.fill()

        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: primaryTextColor
        ]
        let labelAttributed = NSAttributedString(string: model.lane.labelText, attributes: labelAttributes)
        let labelOrigin = CGPoint(
            x: dotRect.maxX + 8,
            y: bounds.midY - (labelAttributed.size().height / 2)
        )
        labelAttributed.draw(at: labelOrigin)
    }

    private func resolvedEyebrowText(for lane: BoardSurfaceLane) -> String {
        if lane.isTempLane {
            return "TEMP"
        }
        if lane.parentCardID == nil {
            return "ROOT"
        }
        return "LANE"
    }

    private func resolvedTintColor(for model: IndexBoardSurfaceAppKitLaneChipModel) -> NSColor {
        if model.lane.isTempLane {
            return NSColor.orange.withAlphaComponent(model.theme.usesDarkAppearance ? 0.92 : 0.88)
        }
        if let token = model.lane.colorToken,
           let rgb = parseHexRGB(token) {
            return NSColor(calibratedRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        }
        let accentHex = model.theme.usesDarkAppearance ? model.theme.darkCardActiveColorHex : model.theme.cardActiveColorHex
        if let rgb = parseHexRGB(accentHex) {
            return NSColor(calibratedRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        }
        return NSColor.controlAccentColor
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
            self.theme?.usesDarkAppearance != theme.usesDarkAppearance ||
            self.theme?.cardBaseColorHex != theme.cardBaseColorHex ||
            self.theme?.cardActiveColorHex != theme.cardActiveColorHex ||
            self.theme?.darkCardBaseColorHex != theme.darkCardBaseColorHex ||
            self.theme?.darkCardActiveColorHex != theme.darkCardActiveColorHex ||
            self.isSelected != isSelected ||
            self.isActive != isActive ||
            self.summary != summary ||
            self.showsBack != showsBack ||
            bounds.size != IndexBoardMetrics.cardSize ||
            (self.card?.content != card.content) ||
            (self.card?.colorHex != card.colorHex) ||
            (self.card?.cloneGroupID != card.cloneGroupID)

        self.card = card
        self.theme = theme
        self.isSelected = isSelected
        self.isActive = isActive
        self.summary = summary
        self.showsBack = showsBack

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
        backgroundPath.lineWidth = isActive ? 1.8 : 1
        backgroundPath.stroke()

        let inset = IndexBoardMetrics.cardInnerPadding
        let contentRect = bounds.insetBy(dx: inset, dy: inset)
        let primaryTextColor = indexBoardThemePrimaryTextColor(theme: theme)
        let secondaryTextColor = indexBoardThemeSecondaryTextColor(theme: theme)

        var titleText = card.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if titleText.isEmpty {
            titleText = "내용 없음"
        }

        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.lineBreakMode = .byTruncatingTail
        let bodyFont = NSFont(name: "SansMonoCJKFinalDraft", size: 13) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let badgeFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
        let iconFont = NSFont.systemFont(ofSize: 10, weight: .bold)

        let topLineRect = CGRect(
            x: contentRect.minX,
            y: contentRect.maxY - 18,
            width: contentRect.width,
            height: 18
        )

        var badgeCursorX = topLineRect.maxX
        if card.cloneGroupID != nil {
            let linkText = NSAttributedString(
                string: "􀉃",
                attributes: [
                    .font: iconFont,
                    .foregroundColor: secondaryTextColor
                ]
            )
            let size = linkText.size()
            linkText.draw(at: CGPoint(x: badgeCursorX - size.width, y: topLineRect.minY + 2))
            badgeCursorX -= size.width + 6
        }

        if let summary, summary.hasSummary {
            let badge = NSAttributedString(
                string: summary.isStale ? "STALE" : summary.sourceLabelText.uppercased(),
                attributes: [
                    .font: badgeFont,
                    .foregroundColor: summary.isStale ? NSColor.orange.withAlphaComponent(0.92) : secondaryTextColor
                ]
            )
            let badgeSize = badge.size()
            let badgeRect = CGRect(
                x: badgeCursorX - badgeSize.width - 10,
                y: topLineRect.minY - 1,
                width: badgeSize.width + 10,
                height: 18
            )
            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 9, yRadius: 9)
            (summary.isStale
                ? NSColor.orange.withAlphaComponent(theme.usesDarkAppearance ? 0.28 : 0.18)
                : NSColor.black.withAlphaComponent(theme.usesDarkAppearance ? 0.16 : 0.06)
            ).setFill()
            badgePath.fill()
            badge.draw(at: CGPoint(x: badgeRect.minX + 5, y: badgeRect.minY + 3))
        }

        let textRect = CGRect(
            x: contentRect.minX,
            y: contentRect.minY + 2,
            width: contentRect.width,
            height: contentRect.height - 24
        )

        let text: String
        if showsBack {
            text = summary?.summaryText ?? "요약이 아직 없습니다."
        } else {
            text = titleText
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributed = NSAttributedString(
            string: text,
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

private final class IndexBoardSurfaceAppKitDocumentView: NSView, IndexBoardSurfaceAppKitCardInteractionDelegate {
    var configuration: IndexBoardSurfaceAppKitConfiguration
    private var lastRenderState: IndexBoardSurfaceAppKitRenderState

    weak var scrollView: NSScrollView?

    private var cardViews: [UUID: IndexBoardSurfaceAppKitInteractiveCardView] = [:]
    private var laneChipViews: [String: IndexBoardSurfaceAppKitLaneChipView] = [:]
    private var laneWrapperLayers: [String: CAShapeLayer] = [:]
    private let startAnchorLayer = CAShapeLayer()
    private let startAnchorTextLayer = CATextLayer()
    private let selectionLayer = CAShapeLayer()
    private var placeholderLayers: [CAShapeLayer] = []
    private var overlayLayers: [CALayer] = []
    private var cardFrameByID: [UUID: CGRect] = [:]
    private var chipFrameByLaneKey: [String: CGRect] = [:]
    private var presentationSurfaceProjection: BoardSurfaceProjection? = nil
    private var dragState: IndexBoardSurfaceAppKitDragState? = nil
    private var groupDragState: IndexBoardSurfaceAppKitGroupDragState? = nil
    private var selectionState: IndexBoardSurfaceAppKitSelectionState? = nil
    private var pendingBackgroundClickPoint: CGPoint? = nil
    private var pendingBackgroundClickCount = 0
    private var pendingCardClick: (cardID: UUID, point: CGPoint, clickCount: Int)?
    private var pendingGroupClick: (parentCardID: UUID, point: CGPoint)?
    private var contextMenuParentCardID: UUID?
    private var contextMenuParentGroupIsTemp = false
    private var dragSnapshots: [IndexBoardSurfaceAppKitCardSnapshot] = []
    private var groupDragSnapshot: NSImage? = nil
    private var frozenLogicalGridBounds: IndexBoardSurfaceAppKitGridBounds? = nil
    private var lastRevealRequestToken: Int = 0
    private var autoScrollTimer: Timer?
    fileprivate var suppressViewportChangeNotifications = false
    fileprivate var pendingDropPreservedScrollOrigin: CGPoint? = nil

    init(configuration: IndexBoardSurfaceAppKitConfiguration) {
        self.configuration = configuration
        self.lastRenderState = configuration.renderState
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        selectionLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.14 : 0.10).cgColor
        selectionLayer.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.82).cgColor
        selectionLayer.lineWidth = 1.5
        startAnchorTextLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        startAnchorTextLayer.alignmentMode = .center
        startAnchorTextLayer.fontSize = 11
        startAnchorTextLayer.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        layer?.addSublayer(startAnchorLayer)
        layer?.addSublayer(startAnchorTextLayer)
        layer?.addSublayer(selectionLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard configuration.isInteractionEnabled else { return nil }

        let point = convert(event.locationInWindow, from: nil)
        let targetGroup = resolvedTargetParentGroup(at: point, excluding: [])
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

        contextMenuParentCardID = targetGroup?.parentCardID
        contextMenuParentGroupIsTemp = targetGroup?.isTempGroup ?? false

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

        return menu.items.isEmpty ? nil : menu
    }

    override func mouseDown(with event: NSEvent) {
        guard configuration.isInteractionEnabled else {
            super.mouseDown(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if let cardID = cardID(at: point) {
            pendingCardClick = (cardID, point, event.clickCount)
            pendingGroupClick = nil
            pendingBackgroundClickPoint = nil
            pendingBackgroundClickCount = 0
            selectionState = nil
            updateSelectionLayer()
            return
        }
        if let parentCardID = movableParentGroupID(at: point) {
            pendingGroupClick = (parentCardID, point)
            pendingCardClick = nil
            pendingBackgroundClickPoint = nil
            pendingBackgroundClickCount = 0
            selectionState = nil
            updateSelectionLayer()
            return
        }
        pendingBackgroundClickPoint = point
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
        if let pendingCardClick {
            if dragState == nil, pendingCardClick.point.distance(to: location) < IndexBoardSurfaceAppKitConstants.dragThreshold {
                return
            }
            if dragState == nil {
                beginDrag(cardID: pendingCardClick.cardID, pointer: location)
            }
            guard var dragState, dragState.cardID == pendingCardClick.cardID else { return }
            let previousTarget = dragState.dropTarget
            dragState.pointerInContent = location
            dragState.dropTarget = resolvedDropTarget(for: dragState)
            applyCardDragUpdate(dragState, previousTarget: previousTarget)
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
            let previousOrigin = groupDragState.targetOrigin
            groupDragState.pointerInContent = location
            groupDragState.targetOrigin = resolvedGroupDragOrigin(for: groupDragState)
            applyGroupDragUpdate(groupDragState, previousOrigin: previousOrigin)
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
                configuration.onCardTap(card)
            }
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
        }

        if selectionState != nil {
            selectionState = nil
            updateSelectionLayer()
        } else if pendingBackgroundClickCount == 2 {
            configuration.onCreateTempCard()
        } else {
            configuration.onClearSelection()
        }

        pendingBackgroundClickPoint = nil
        pendingBackgroundClickCount = 0
    }

    override func layout() {
        super.layout()
        applyCurrentLayout(animationDuration: 0)
    }

    func updateConfiguration(_ configuration: IndexBoardSurfaceAppKitConfiguration) {
        let nextRenderState = configuration.renderState
        self.configuration = configuration
        selectionLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.14 : 0.10).cgColor
        selectionLayer.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.82).cgColor
        guard nextRenderState != lastRenderState else { return }
        lastRenderState = nextRenderState
        reconcilePresentationProjection()
        needsLayout = true
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

    func ensureCardVisible(_ cardID: UUID?) {
        guard let cardID,
              let rect = cardFrameByID[cardID] else { return }
        scrollView?.contentView.scrollToVisible(rect.insetBy(dx: -36, dy: -28))
        scrollView?.reflectScrolledClipView(scrollView!.contentView)
    }

    func handleCardMouseDown(cardID: UUID, event: NSEvent, in view: NSView) {
        guard configuration.isInteractionEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)
        pendingCardClick = (cardID, point, event.clickCount)
        pendingBackgroundClickPoint = nil
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
        let previousTarget = dragState.dropTarget
        dragState.pointerInContent = point
        dragState.dropTarget = resolvedDropTarget(for: dragState)
        applyCardDragUpdate(dragState, previousTarget: previousTarget)
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
            configuration.onCardTap(card)
        }
    }

    private var effectiveSurfaceProjection: BoardSurfaceProjection {
        presentationSurfaceProjection ?? configuration.surfaceProjection
    }

    private var orderedItems: [BoardSurfaceItem] {
        effectiveSurfaceProjection.surfaceItems.sorted(by: indexBoardSurfaceAppKitSort)
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

    private var surfaceVerticalInset: CGFloat {
        max(IndexBoardMetrics.boardVerticalPadding, IndexBoardSurfaceAppKitConstants.minimumCanvasTopInset)
    }

    private var logicalGridBounds: IndexBoardSurfaceAppKitGridBounds {
        if let frozenLogicalGridBounds {
            return frozenLogicalGridBounds
        }
        return resolvedLogicalGridBounds(for: Array(occupiedGridPositionByCardID().values))
    }

    private func resolvedLogicalGridBounds(
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

    private func occupiedGridPositionByCardID() -> [UUID: IndexBoardGridPosition] {
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
        let candidateFrames = effectiveSurfaceProjection.parentGroups.compactMap { group -> (BoardSurfaceParentGroupPlacement, CGRect)? in
            let groupFrames = orderedItems.compactMap { item -> CGRect? in
                guard item.parentGroupID == group.id,
                      !movingCardIDs.contains(item.cardID),
                      let frame = cardFrameByID[item.cardID] else { return nil }
                return frame
            }
            guard let firstFrame = groupFrames.first else { return nil }
            let cardUnion = groupFrames.dropFirst().reduce(firstFrame) { partial, frame in
                partial.union(frame)
            }
            let chipFrame = chipFrameByLaneKey[indexBoardSurfaceLaneKey(group.parentCardID)] ?? .null
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
            x: startSlot.minX,
            y: startSlot.minY + IndexBoardSurfaceAppKitConstants.laneChipHeight + IndexBoardSurfaceAppKitConstants.laneChipSpacing,
            width: endSlot.maxX - startSlot.minX,
            height: IndexBoardMetrics.cardSize.height
        )
    }

    private func resolvedCardDropTargetGroup(
        at point: CGPoint,
        for drag: IndexBoardSurfaceAppKitDragState
    ) -> BoardSurfaceParentGroupPlacement? {
        let visibleCardCountByGroupID = Dictionary(
            grouping: effectiveSurfaceProjection.surfaceItems.filter { item in
                item.parentGroupID != nil && !drag.movingCardIDSet.contains(item.cardID)
            },
            by: { $0.parentGroupID! }
        ).mapValues(\.count)

        let candidateGroups = effectiveSurfaceProjection.parentGroups

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
        guard let parentCardID = resolvedTargetParentGroup(at: point, excluding: [])?.parentCardID,
              parentCardID != configuration.surfaceProjection.source.parentID else {
            return nil
        }
        return parentCardID
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
            y: surfaceVerticalInset + (CGFloat(normalizedRow) * (slotSize.height + IndexBoardSurfaceAppKitConstants.lineSpacing)),
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

    private func resolvedFlowInteractionRect(slotCount: Int, usesVerticalHysteresis: Bool) -> CGRect? {
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

    private func resolvedNearestGridPosition(for point: CGPoint) -> IndexBoardGridPosition {
        let bounds = logicalGridBounds
        let columnStep = slotSize.width + IndexBoardMetrics.cardSpacing
        let rowStep = slotSize.height + IndexBoardSurfaceAppKitConstants.lineSpacing
        let rawColumn = Int(((point.x - surfaceHorizontalInset - (slotSize.width / 2)) / columnStep).rounded())
        let rawRow = Int(((point.y - surfaceVerticalInset - (slotSize.height / 2)) / rowStep).rounded())
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

    private func beginDrag(cardID: UUID, pointer: CGPoint) {
        guard let primaryItem = orderedItems.first(where: { $0.cardID == cardID }),
              let initialFrame = resolvedCardFrame(for: primaryItem) else { return }
        frozenLogicalGridBounds = logicalGridBounds
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
        groupDragSnapshot = nil
        frozenLogicalGridBounds = nil
        applyCurrentLayout(animationDuration: IndexBoardSurfaceAppKitConstants.commitLayoutAnimationDuration)
        restoreScrollOriginAfterDrop(preservedScrollOrigin, notifySession: false)
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
        let usesFlowHysteresis: Bool
        if case .flow = drag.dropPlacement {
            usesFlowHysteresis = true
        } else {
            usesFlowHysteresis = false
        }

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
            let currentRect = CGRect(
                x: resolvedFlowSlotRect(for: currentIndex).minX,
                y: resolvedFlowSlotRect(for: currentIndex).minY + IndexBoardSurfaceAppKitConstants.laneChipHeight + IndexBoardSurfaceAppKitConstants.laneChipSpacing,
                width: IndexBoardMetrics.cardSize.width,
                height: IndexBoardMetrics.cardSize.height
            ).insetBy(dx: -42, dy: -54)
            if currentRect.contains(dragCardCenter) {
                return .flow(currentIndex)
            }
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

        if let detachedBlockTarget = resolvedDetachedBlockDropTarget(
            at: dragCardCenter,
            for: drag
        ) {
            if drag.sourceTarget == detachedBlockTarget {
                return drag.sourceTarget
            }
            return detachedBlockTarget
        }

        let detachedGridPosition = resolvedDetachedGridPosition(
            for: drag.pointerInContent,
            excluding: drag.movingCardIDSet
        )
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
        let updatedParentGroups = configuration.surfaceProjection.parentGroups.map { group in
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

        let stationaryDetachedItems = configuration.surfaceProjection.surfaceItems.filter { $0.parentGroupID == nil }
        var regroupedItems: [BoardSurfaceItem] = []
        for placement in updatedParentGroups.sorted(by: indexBoardSurfaceAppKitGroupSort) {
            let laneIndex = configuration.surfaceProjection.lanes.first(where: { $0.parentCardID == placement.parentCardID })?.laneIndex ?? 0
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
            source: configuration.surfaceProjection.source,
            startAnchor: configuration.surfaceProjection.startAnchor,
            lanes: configuration.surfaceProjection.lanes,
            parentGroups: updatedParentGroups.sorted(by: indexBoardSurfaceAppKitGroupSort),
            surfaceItems: sortedItems,
            orderedCardIDs: sortedItems.map(\.cardID)
        )
    }

    private func applyCardDragUpdate(
        _ updatedState: IndexBoardSurfaceAppKitDragState,
        previousTarget: IndexBoardCardDropTarget
    ) {
        self.dragState = updatedState
        presentationSurfaceProjection = resolvedPresentationSurfaceProjection(for: updatedState)
        let didRetarget = updatedState.dropTarget != previousTarget
        applyCurrentLayout(
            animationDuration: didRetarget
                ? IndexBoardSurfaceAppKitConstants.previewLayoutAnimationDuration
                : 0
        )
    }

    private func applyGroupDragUpdate(
        _ updatedState: IndexBoardSurfaceAppKitGroupDragState,
        previousOrigin: IndexBoardGridPosition
    ) {
        self.groupDragState = updatedState
        presentationSurfaceProjection = resolvedPresentationSurfaceProjection(for: updatedState)
        let didRetarget = updatedState.targetOrigin != previousOrigin
        applyCurrentLayout(
            animationDuration: didRetarget
                ? IndexBoardSurfaceAppKitConstants.previewLayoutAnimationDuration
                : 0
        )
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
                gridHeight + (surfaceVerticalInset * 2) + IndexBoardSurfaceAppKitConstants.surfaceVerticalOverscan
            )
        )
        if frame.size != documentSize {
            frame.size = documentSize
        }

        var nextCardFrames: [UUID: CGRect] = [:]
        nextCardFrames.reserveCapacity(orderedItems.count)
        for item in orderedItems {
            if let frame = resolvedCardFrame(for: item) {
                nextCardFrames[item.cardID] = frame
            }
        }
        cardFrameByID = nextCardFrames

        reconcileCardViews()
        reconcileLaneChipViews()
        let hiddenCardIDs = Set((dragState?.movingCardIDs ?? []) + (groupDragState?.movingCardIDs ?? []))
        for (cardID, cardView) in cardViews {
            cardView.isHidden = hiddenCardIDs.contains(cardID)
        }
        updateStartAnchor()
        updateLaneWrappers()
        updateSelectionLayer()
        updatePlaceholderLayers()
        updateOverlayLayers()

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
        let tint = NSColor.controlAccentColor.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.92 : 0.84)
        startAnchorLayer.fillColor = tint.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.18 : 0.12).cgColor
        startAnchorLayer.strokeColor = tint.cgColor
        startAnchorLayer.lineWidth = 1.5
        startAnchorTextLayer.string = configuration.surfaceProjection.startAnchor.labelText
        startAnchorTextLayer.foregroundColor = tint.cgColor
        startAnchorTextLayer.frame = anchorFrame.insetBy(dx: 6, dy: 5)
    }

    private func reconcileCardViews() {
        let validCardIDs = Set(orderedItems.map(\.cardID))
        for (cardID, view) in cardViews where !validCardIDs.contains(cardID) {
            view.removeFromSuperview()
            cardViews.removeValue(forKey: cardID)
        }

        for item in orderedItems {
            guard let card = configuration.cardsByID[item.cardID] else { continue }
            let view = cardViews[item.cardID] ?? {
                let created = IndexBoardSurfaceAppKitInteractiveCardView(cardID: item.cardID)
                created.interactionDelegate = self
                created.frame = CGRect(origin: .zero, size: IndexBoardMetrics.cardSize)
                addSubview(created)
                cardViews[item.cardID] = created
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
        let laneFrames = resolvedLaneChipFrames()
        chipFrameByLaneKey = laneFrames
        let validKeys = Set(laneFrames.keys)
        for (key, view) in laneChipViews where !validKeys.contains(key) {
            view.removeFromSuperview()
            laneChipViews.removeValue(forKey: key)
        }

        let laneByKey = Dictionary(uniqueKeysWithValues: effectiveSurfaceProjection.lanes.map { (indexBoardSurfaceLaneKey($0.parentCardID), $0) })
        for (key, frame) in laneFrames {
            guard let lane = laneByKey[key] else { continue }
            let chipView = laneChipViews[key] ?? {
                let created = IndexBoardSurfaceAppKitLaneChipView(frame: frame)
                addSubview(created)
                laneChipViews[key] = created
                return created
            }()
            chipView.update(model: .init(lane: lane, theme: configuration.theme))
            chipView.frame = frame
        }
    }

    private func resolvedLaneChipFrames() -> [String: CGRect] {
        let orderedFlowItems = flowItems.sorted(by: indexBoardSurfaceAppKitSort)
        var seenKeys: Set<String> = []
        var frames: [String: CGRect] = [:]
        for item in orderedFlowItems {
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
            if let frame = resolvedParentGroupFrame(for: group) {
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
            wrapperLayer.lineWidth = 2
        }
    }

    private func resolvedLaneTintColor(for lane: BoardSurfaceLane?) -> NSColor {
        if let lane, lane.isTempLane {
            return NSColor.orange.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.88 : 0.82)
        }
        if let token = lane?.colorToken,
           let rgb = parseHexRGB(token) {
            return NSColor(calibratedRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        }
        let borderRGB = configuration.theme.usesDarkAppearance ? (0.28, 0.30, 0.36) : (0.78, 0.75, 0.69)
        return NSColor(calibratedRed: borderRGB.0, green: borderRGB.1, blue: borderRGB.2, alpha: 1)
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

    private func updatePlaceholderLayers() {
        placeholderLayers.forEach { $0.removeFromSuperlayer() }
        placeholderLayers.removeAll()
        let placeholderFrames: [CGRect]
        let placeholderStyle: IndexBoardSurfaceAppKitPlaceholderStyle
        if let dragState {
            let resolved = resolvedPlaceholderPresentation(for: dragState)
            placeholderFrames = resolved.frames
            placeholderStyle = resolved.style
        } else if let groupDragState,
                  let group = effectiveSurfaceProjection.parentGroups.first(where: { $0.parentCardID == groupDragState.parentCardID }),
                  let groupFrame = resolvedParentGroupFrame(for: group) {
            placeholderFrames = [groupFrame]
            placeholderStyle = .flow
        } else {
            return
        }
        for frame in placeholderFrames {
            let layer = CAShapeLayer()
            layer.path = CGPath(
                roundedRect: frame,
                cornerWidth: 14,
                cornerHeight: 14,
                transform: nil
            )
            layer.fillColor = resolvedPlaceholderFillColor(style: placeholderStyle).cgColor
            layer.strokeColor = resolvedPlaceholderStrokeColor(style: placeholderStyle).cgColor
            layer.lineWidth = resolvedPlaceholderLineWidth(style: placeholderStyle)
            layer.lineDashPattern = resolvedPlaceholderLineDashPattern(style: placeholderStyle)
            layer.shadowColor = NSColor.black.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.10 : 0.05).cgColor
            layer.shadowRadius = IndexBoardSurfaceAppKitConstants.placeholderShadowRadius
            layer.shadowOpacity = 1
            layer.shadowOffset = CGSize(width: 0, height: IndexBoardSurfaceAppKitConstants.placeholderShadowYOffset)
            self.layer?.addSublayer(layer)
            placeholderLayers.append(layer)
        }
    }

    private func resolvedPlaceholderPresentation(
        for drag: IndexBoardSurfaceAppKitDragState
    ) -> (frames: [CGRect], style: IndexBoardSurfaceAppKitPlaceholderStyle) {
        if let detachedIndicator = resolvedDetachedIndicatorFrames(for: drag) {
            return detachedIndicator
        }
        return (resolvedPlaceholderFrames(for: drag), .flow)
    }

    private func resolvedPlaceholderFillColor(style: IndexBoardSurfaceAppKitPlaceholderStyle) -> NSColor {
        switch style {
        case .flow:
            if configuration.theme.usesDarkAppearance {
                return NSColor.white.withAlphaComponent(0.08)
            }
            return NSColor.white.withAlphaComponent(0.58)
        case .detachedSlot:
            return NSColor.controlAccentColor.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.20 : 0.18)
        case .detachedParking:
            return NSColor.white.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.04 : 0.12)
        }
    }

    private func resolvedPlaceholderStrokeColor(style: IndexBoardSurfaceAppKitPlaceholderStyle) -> NSColor {
        switch style {
        case .flow:
        let borderRGB = configuration.theme.usesDarkAppearance ? (0.42, 0.45, 0.51) : (0.76, 0.73, 0.67)
        return NSColor(
            calibratedRed: borderRGB.0,
            green: borderRGB.1,
            blue: borderRGB.2,
            alpha: configuration.theme.usesDarkAppearance ? 0.54 : 0.72
        )
        case .detachedSlot:
            return NSColor.controlAccentColor.withAlphaComponent(0.98)
        case .detachedParking:
            return NSColor.controlAccentColor.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.74 : 0.86)
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

    private func resolvedPlaceholderFrames(for drag: IndexBoardSurfaceAppKitDragState) -> [CGRect] {
        let hiddenCardIDs = Set(drag.movingCardIDs)
        return drag.movingCardIDs.compactMap { cardID in
            guard hiddenCardIDs.contains(cardID) else { return nil }
            return cardFrameByID[cardID]
        }
    }

    private func updateOverlayLayers() {
        overlayLayers.forEach { $0.removeFromSuperlayer() }
        overlayLayers.removeAll()

        if let dragState {
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
    }

    private func resolvedOverlayCardIDs(for drag: IndexBoardSurfaceAppKitDragState) -> [UUID] {
        let supportingIDs = drag.movingCardIDs.filter { $0 != drag.cardID }
        let trailingSupport = Array(supportingIDs.suffix(3))
        return trailingSupport + [drag.cardID]
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
        configuration.onScrollOffsetChange(CGPoint(x: targetX, y: targetY))
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
    private var scrollObserver: NSObjectProtocol?
    private var magnifyObserver: NSObjectProtocol?
    private var isApplyingExternalViewport = false

    init(configuration: IndexBoardSurfaceAppKitConfiguration) {
        backgroundView = IndexBoardSurfaceAppKitBackgroundView(theme: configuration.theme)
        scrollView = NSScrollView(frame: .zero)
        documentView = IndexBoardSurfaceAppKitDocumentView(configuration: configuration)
        super.init(frame: .zero)
        wantsLayer = true

        backgroundView.frame = bounds
        backgroundView.autoresizingMask = [.width, .height]
        addSubview(backgroundView)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.allowsMagnification = true
        scrollView.minMagnification = IndexBoardZoom.minScale
        scrollView.maxMagnification = IndexBoardZoom.maxScale
        scrollView.documentView = documentView
        scrollView.contentView.postsBoundsChangedNotifications = true
        documentView.scrollView = scrollView
        addSubview(scrollView)

        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.handleViewportChanged()
        }
        magnifyObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.handleMagnificationChanged()
        }

        update(configuration: configuration)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
        }
        if let magnifyObserver {
            NotificationCenter.default.removeObserver(magnifyObserver)
        }
    }

    override func layout() {
        super.layout()
        backgroundView.frame = bounds
        scrollView.frame = bounds
    }

    func update(configuration: IndexBoardSurfaceAppKitConfiguration) {
        backgroundView.theme = configuration.theme
        documentView.updateConfiguration(configuration)

        if abs(scrollView.magnification - configuration.zoomScale) > 0.001 {
            isApplyingExternalViewport = true
            scrollView.setMagnification(configuration.zoomScale, centeredAt: .zero)
            isApplyingExternalViewport = false
        }

        let currentOrigin = scrollView.contentView.bounds.origin
        if abs(currentOrigin.x - configuration.scrollOffset.x) > 0.5 ||
            abs(currentOrigin.y - configuration.scrollOffset.y) > 0.5 {
            isApplyingExternalViewport = true
            scrollView.contentView.setBoundsOrigin(NSPoint(x: max(0, configuration.scrollOffset.x), y: max(0, configuration.scrollOffset.y)))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            isApplyingExternalViewport = false
        }

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

    }

    private func handleViewportChanged() {
        guard !isApplyingExternalViewport,
              !documentView.suppressViewportChangeNotifications else { return }
        let origin = scrollView.contentView.bounds.origin
        let resolvedOrigin = CGPoint(x: max(0, origin.x), y: max(0, origin.y))
        guard abs(resolvedOrigin.x - documentView.configuration.scrollOffset.x) > 0.5 ||
                abs(resolvedOrigin.y - documentView.configuration.scrollOffset.y) > 0.5 else {
            return
        }
        documentView.configuration.onScrollOffsetChange(resolvedOrigin)
    }

    private func handleMagnificationChanged() {
        guard !isApplyingExternalViewport else { return }
        guard abs(scrollView.magnification - documentView.configuration.zoomScale) > 0.001 else { return }
        documentView.configuration.onZoomScaleChange(scrollView.magnification)
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
    let onCreateParentFromSelection: () -> Void
    let onSetParentGroupTemp: (UUID, Bool) -> Void
    let onCardTap: (SceneCard) -> Void
    let onCardDragStart: ([UUID], UUID) -> Void
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
    let onParentGroupMove: (IndexBoardParentGroupDropTarget) -> Void

    private var orderedItems: [BoardSurfaceItem] {
        surfaceProjection.surfaceItems.sorted(by: indexBoardSurfaceAppKitSort)
    }

    private var zoomPercentText: String {
        "\(Int((zoomScale * 100).rounded()))%"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

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
                        onCreateParentFromSelection: onCreateParentFromSelection,
                        onSetParentGroupTemp: onSetParentGroupTemp,
                        onCardTap: onCardTap,
                        onCardDragStart: onCardDragStart,
                        onCardOpen: onCardOpen,
                        onCardMove: onCardMove,
                        onCardMoveSelection: onCardMoveSelection,
                        onMarqueeSelectionChange: onMarqueeSelectionChange,
                        onClearSelection: onClearSelection,
                        onScrollOffsetChange: onScrollOffsetChange,
                        onZoomScaleChange: onZoomScaleChange,
                        onParentGroupMove: onParentGroupMove
                    )
                )
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .background(theme.boardBackground)
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
                Button(action: { onZoomStep(-IndexBoardZoom.step) }) {
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

                Button(action: { onZoomStep(IndexBoardZoom.step) }) {
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

            Button("선택 묶기") {
                onCreateParentFromSelection()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!isInteractionEnabled || selectedCardIDs.isEmpty)

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
}
