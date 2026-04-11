import SwiftUI

enum BWRBoardLayoutMetrics {
    static let baseCardSize = CGSize(width: 166, height: 118)
    static let defaultCardScaleMultiplier: CGFloat = 1.15
    static let cardSize = CGSize(
        width: baseCardSize.width * defaultCardScaleMultiplier,
        height: baseCardSize.height * defaultCardScaleMultiplier
    )
    static let horizontalGridSpacing: CGFloat = 16.2
    static let verticalGridSpacing: CGFloat = 24
    static let outerPadding = EdgeInsets(top: 34, leading: 36, bottom: 46, trailing: 36)
    static let cardCorner: CGFloat = 15
    static let slotEmphasisInset: CGFloat = 5
    static let slotEmphasisCorner: CGFloat = cardCorner
    static func slotEmphasisSize(for size: CGSize) -> CGSize {
        CGSize(
            width: size.width + (slotEmphasisInset * 2),
            height: size.height + (slotEmphasisInset * 2)
        )
    }
    static var cardSurfaceCorner: CGFloat {
        max(cardCorner - slotEmphasisInset, 0)
    }
}
