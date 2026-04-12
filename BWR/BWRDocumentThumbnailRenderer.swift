import AppKit

enum BWRDocumentThumbnailRendererError: LocalizedError {
    case bitmapCreationFailed
    case jpegEncodingFailed

    var errorDescription: String? {
        switch self {
        case .bitmapCreationFailed:
            return "The board thumbnail bitmap could not be created."
        case .jpegEncodingFailed:
            return "The board thumbnail could not be encoded as JPEG."
        }
    }
}

enum BWRDocumentThumbnailRenderer {
    private static let outputSize = CGSize(width: 960, height: 720)
    private static let cardPadding = CGSize(
        width: BWRBoardLayoutMetrics.scaled(44),
        height: BWRBoardLayoutMetrics.scaled(42)
    )
    private static let maxScale: CGFloat = 1.3
    private static let minScale: CGFloat = 0.36

    static func renderJPEG(for project: BoardProject) throws -> Data {
        let image = NSImage(size: outputSize)
        image.lockFocusFlipped(true)

        NSColor(hex: BoardCanvasTone.sand.windowHex).setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: outputSize)).fill()

        drawBoardBackground()
        drawCards(for: project)

        image.unlockFocus()

        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff)
        else {
            throw BWRDocumentThumbnailRendererError.bitmapCreationFailed
        }

        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.84]) else {
            throw BWRDocumentThumbnailRendererError.jpegEncodingFailed
        }

        return data
    }

    private static func drawBoardBackground() {
        let boardRect = CGRect(origin: .zero, size: outputSize).insetBy(dx: 14, dy: 14)
        let boardPath = NSBezierPath(
            roundedRect: boardRect,
            xRadius: 24,
            yRadius: 24
        )
        NSColor(hex: BoardCanvasTone.sand.boardHex).setFill()
        boardPath.fill()

        let glowRect = CGRect(
            x: BWRBoardLayoutMetrics.scaled(80),
            y: BWRBoardLayoutMetrics.scaled(50),
            width: BWRBoardLayoutMetrics.scaled(500),
            height: BWRBoardLayoutMetrics.scaled(220)
        )
        let glowPath = NSBezierPath(ovalIn: glowRect)
        NSColor.white.withAlphaComponent(0.11).setFill()
        glowPath.fill()
    }

    private static func drawCards(for project: BoardProject) {
        let presentedCards = project.presentedCards
        let frames = presentedCards.map { cardFrame(for: $0.slot) }
        let contentBounds = frames.reduce(into: CGRect.null) { partial, frame in
            partial = partial.union(frame)
        }

        let fallbackBounds = CGRect(
            origin: .zero,
            size: CGSize(
                width: BWRBoardLayoutMetrics.cardSize.width * 3,
                height: BWRBoardLayoutMetrics.cardSize.height * 2
            )
        )

        let sourceBounds = (presentedCards.isEmpty ? fallbackBounds : contentBounds)
            .insetBy(dx: -cardPadding.width, dy: -cardPadding.height)

        let availableRect = CGRect(origin: .zero, size: outputSize).insetBy(dx: 46, dy: 42)
        let scale = max(
            min(
                min(availableRect.width / max(sourceBounds.width, 1), availableRect.height / max(sourceBounds.height, 1)),
                maxScale
            ),
            minScale
        )

        let scaledSize = CGSize(width: sourceBounds.width * scale, height: sourceBounds.height * scale)
        let origin = CGPoint(
            x: availableRect.midX - scaledSize.width / 2,
            y: availableRect.midY - scaledSize.height / 2
        )

        for card in presentedCards.sorted(by: { $0.slot < $1.slot }) {
            let baseFrame = cardFrame(for: card.slot)
            let transformed = CGRect(
                x: origin.x + (baseFrame.minX - sourceBounds.minX) * scale,
                y: origin.y + (baseFrame.minY - sourceBounds.minY) * scale,
                width: baseFrame.width * scale,
                height: baseFrame.height * scale
            )
            drawCard(card, asset: project.presentedAsset(for: card), in: transformed)
        }
    }

    private static func cardFrame(for slot: BoardSlot) -> CGRect {
        CGRect(
            x: CGFloat(slot.column) * (BWRBoardLayoutMetrics.cardSize.width + BWRBoardLayoutMetrics.horizontalGridSpacing),
            y: CGFloat(slot.row) * (BWRBoardLayoutMetrics.cardSize.height + BWRBoardLayoutMetrics.verticalGridSpacing),
            width: BWRBoardLayoutMetrics.cardSize.width,
            height: BWRBoardLayoutMetrics.cardSize.height
        )
    }

    private static func drawCard(_ card: BoardPresentedCard, asset: BoardAsset?, in frame: CGRect) {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
        shadow.shadowBlurRadius = BWRBoardLayoutMetrics.scaled(18) * max(frame.width / BWRBoardLayoutMetrics.cardSize.width, 0.55)
        shadow.shadowOffset = NSSize(width: 0, height: BWRBoardLayoutMetrics.scaled(7))
        shadow.set()

        let cardPath = NSBezierPath(
            roundedRect: frame,
            xRadius: BWRBoardLayoutMetrics.cardSurfaceCorner,
            yRadius: BWRBoardLayoutMetrics.cardSurfaceCorner
        )
        NSColor(hex: card.palette.fillHex).setFill()
        cardPath.fill()

        NSGraphicsContext.saveGraphicsState()
        let clipPath = NSBezierPath(
            roundedRect: frame,
            xRadius: BWRBoardLayoutMetrics.cardSurfaceCorner,
            yRadius: BWRBoardLayoutMetrics.cardSurfaceCorner
        )
        clipPath.addClip()

        if let image = asset.flatMap({ NSImage(data: $0.data) }) {
            let imageHeight = frame.height * 0.52
            let imageRect = CGRect(
                x: frame.minX,
                y: frame.minY,
                width: frame.width,
                height: imageHeight
            )
            image.draw(
                in: imageRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 0.94,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high.rawValue]
            )

            let fadeRect = CGRect(
                x: frame.minX,
                y: imageRect.maxY - BWRBoardLayoutMetrics.scaled(22),
                width: frame.width,
                height: BWRBoardLayoutMetrics.scaled(34)
            )
            let fade = NSGradient(
                colors: [
                    NSColor.white.withAlphaComponent(0),
                    NSColor(hex: card.palette.fillHex).withAlphaComponent(0.84)
                ]
            )
            fade?.draw(in: fadeRect, angle: 90)
        }

        let chipRect = CGRect(
            x: frame.minX + BWRBoardLayoutMetrics.scaled(14),
            y: frame.minY + BWRBoardLayoutMetrics.scaled(14),
            width: max(frame.width * 0.23, BWRBoardLayoutMetrics.scaled(28)),
            height: max(frame.height * 0.075, BWRBoardLayoutMetrics.scaled(8))
        )
        let chipPath = NSBezierPath(
            roundedRect: chipRect,
            xRadius: chipRect.height / 2,
            yRadius: chipRect.height / 2
        )
        NSColor(hex: card.palette.chipHex).withAlphaComponent(0.95).setFill()
        chipPath.fill()

        let titleFontSize = max(12, min(22, frame.width * 0.1))
        let bodyFontSize = max(10, min(15, frame.width * 0.058))
        let textInsets = NSEdgeInsets(
            top: asset == nil
                ? BWRBoardLayoutMetrics.scaled(32)
                : max(frame.height * 0.54, BWRBoardLayoutMetrics.scaled(66)),
            left: BWRBoardLayoutMetrics.scaled(16),
            bottom: BWRBoardLayoutMetrics.scaled(14),
            right: BWRBoardLayoutMetrics.scaled(16)
        )

        let titleRect = CGRect(
            x: frame.minX + textInsets.left,
            y: frame.minY + textInsets.top,
            width: frame.width - textInsets.left - textInsets.right,
            height: titleFontSize * 1.7
        )
        let excerptRect = CGRect(
            x: frame.minX + textInsets.left,
            y: titleRect.maxY + BWRBoardLayoutMetrics.scaled(8),
            width: frame.width - textInsets.left - textInsets.right,
            height: max(
                frame.maxY - (titleRect.maxY + BWRBoardLayoutMetrics.scaled(8)) - textInsets.bottom,
                bodyFontSize * 2.5
            )
        )

        drawText(
            card.digest.title,
            in: titleRect,
            font: NSFont(name: "Avenir Next Demi Bold", size: titleFontSize) ?? .systemFont(ofSize: titleFontSize, weight: .semibold),
            color: NSColor(hex: 0x181512),
            lineBreakMode: .byTruncatingTail
        )

        drawText(
            card.digest.excerpt.isEmpty ? "Write in markdown right on the board." : card.digest.excerpt,
            in: excerptRect,
            font: NSFont(name: "Avenir Next", size: bodyFontSize) ?? .systemFont(ofSize: bodyFontSize),
            color: NSColor(hex: 0x49433A).withAlphaComponent(0.94),
            lineBreakMode: .byWordWrapping
        )

        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        font: NSFont,
        color: NSColor,
        lineBreakMode: NSLineBreakMode
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = lineBreakMode
        paragraph.alignment = .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        NSString(string: text).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attributes
        )
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
