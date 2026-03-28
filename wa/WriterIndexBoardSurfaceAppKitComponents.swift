import SwiftUI
import AppKit

final class IndexBoardSurfaceAppKitBackgroundView: NSView {
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

final class IndexBoardSurfaceAppKitLaneChipView: NSView {
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
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int(ceil(bounds.width * scale))),
            pixelsHigh: max(1, Int(ceil(bounds.height * scale))),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        rep.size = bounds.size
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

class IndexBoardSurfaceAppKitCardView: NSView {
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
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int(ceil(bounds.width * scale))),
            pixelsHigh: max(1, Int(ceil(bounds.height * scale))),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        rep.size = bounds.size
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }
}

protocol IndexBoardSurfaceAppKitCardInteractionDelegate: AnyObject {
    func handleCardMouseDown(cardID: UUID, event: NSEvent, in view: NSView)
    func handleCardMouseDragged(cardID: UUID, event: NSEvent, in view: NSView)
    func handleCardMouseUp(cardID: UUID, event: NSEvent, in view: NSView)
}

protocol IndexBoardSurfaceAppKitLaneChipInteractionDelegate: AnyObject {
    func menuForLaneChip(parentCardID: UUID, event: NSEvent, in view: NSView) -> NSMenu?
    func handleLaneChipMouseDown(parentCardID: UUID, event: NSEvent, in view: NSView)
    func handleLaneChipMouseDragged(parentCardID: UUID, event: NSEvent, in view: NSView)
    func handleLaneChipMouseUp(parentCardID: UUID, event: NSEvent, in view: NSView)
}

final class IndexBoardSurfaceAppKitInteractiveCardView: IndexBoardSurfaceAppKitCardView {
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

final class IndexBoardSurfaceAppKitInlineTextView: NSTextView {
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

