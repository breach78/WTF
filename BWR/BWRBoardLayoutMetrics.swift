import SwiftUI

enum BWRBoardLayoutMetrics {
    static let baseCardSize = CGSize(width: 166, height: 118)
    private static let referenceCardScaleMultiplier: CGFloat = 1.15
    private static let cardSizeIncreaseMultiplier: CGFloat = 1.15
    static let defaultCardScaleMultiplier: CGFloat = referenceCardScaleMultiplier * cardSizeIncreaseMultiplier
    static let referenceCardSize = CGSize(
        width: baseCardSize.width * referenceCardScaleMultiplier,
        height: baseCardSize.height * referenceCardScaleMultiplier
    )
    static let cardSize = CGSize(
        width: baseCardSize.width * defaultCardScaleMultiplier,
        height: baseCardSize.height * defaultCardScaleMultiplier
    )
    static let cardVisualScale = cardSize.width / referenceCardSize.width
    static let horizontalGridSpacing: CGFloat = 16.2
    static let verticalGridSpacing: CGFloat = 24
    static let outerPadding = EdgeInsets(top: 34, leading: 36, bottom: 46, trailing: 36)
    static let cardCorner: CGFloat = scaled(15)
    static let slotEmphasisInset: CGFloat = scaled(5)
    static let slotEmphasisCorner: CGFloat = cardCorner
    static let slotContentShapeCornerBoost: CGFloat = scaled(6)
    static let boardGlowBlurRadius: CGFloat = scaled(90)
    static let boardGlowSize = CGSize(width: scaled(540), height: scaled(300))
    static let boardGlowOffset = CGSize(width: scaled(-170), height: scaled(-160))
    static let dragDestinationStrokeWidth: CGFloat = scaled(1)
    static let dragDestinationHeadStrokeWidth: CGFloat = scaled(1.6)
    static let dragDestinationShadowRadius: CGFloat = scaled(18)
    static let dragDestinationShadowYOffset: CGFloat = scaled(10)
    static let dragPreviewShadowRadius: CGFloat = scaled(16)
    static let dragPreviewHeadShadowRadius: CGFloat = scaled(22)
    static let dragPreviewShadowYOffset: CGFloat = scaled(14)
    static let slotFocusShadowRadius: CGFloat = scaled(18)
    static let slotEmptyShadowRadius: CGFloat = scaled(16)
    static let slotFocusShadowYOffset: CGFloat = scaled(8)
    static let slotDragSourceShadowYOffset: CGFloat = scaled(6)
    static let slotGuideLineWidth: CGFloat = scaled(1)
    static let slotGuideHoverLineWidth: CGFloat = scaled(1.4)
    static let slotGuideDash = [scaled(7), scaled(8)]
    static let emptySlotPromptSpacing: CGFloat = scaled(6)
    static let emptySlotPromptIconSize: CGFloat = scaled(14)
    static let emptySlotPromptTitleSize: CGFloat = scaled(12)
    static let cardSurfaceShadowRadius: CGFloat = scaled(10)
    static let cardSurfaceShadowYOffset: CGFloat = scaled(6)
    static let cardEditorPadding: CGFloat = scaled(10)
    static let cardEditorFontSize: CGFloat = scaled(13)
    static let cardEditorTextInsetHeight: CGFloat = scaled(2)
    static let cardChipSize: CGFloat = scaled(10)
    static let cardChipPadding: CGFloat = scaled(10)
    static let cardSearchStrokeWidth: CGFloat = scaled(1.6)
    static let cardReadSpacing: CGFloat = scaled(10)
    static let cardReadTextSpacing: CGFloat = scaled(6)
    static let cardAssetHeight: CGFloat = scaled(72)
    static let cardAssetCornerRadius: CGFloat = scaled(12)
    static let cardAssetStrokeWidth: CGFloat = scaled(1)
    static let cardContentPadding: CGFloat = scaled(12)
    static let cardTitleFontSize: CGFloat = scaled(13)
    static let cardBodyFontSize: CGFloat = scaled(12)
    static let cardAttachmentFontSize: CGFloat = scaled(11)

    static func slotEmphasisSize(for size: CGSize) -> CGSize {
        CGSize(
            width: size.width + (slotEmphasisInset * 2),
            height: size.height + (slotEmphasisInset * 2)
        )
    }

    static var cardSurfaceCorner: CGFloat {
        max(cardCorner - slotEmphasisInset, 0)
    }

    static func scaled(_ value: CGFloat) -> CGFloat {
        value * cardVisualScale
    }
}
