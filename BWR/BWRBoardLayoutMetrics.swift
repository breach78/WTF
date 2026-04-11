import SwiftUI

enum BWRBoardLayoutMetrics {
    static let baseCardSize = CGSize(width: 166, height: 118)
    static let defaultCardScaleMultiplier: CGFloat = 1.15
    static let cardSize = CGSize(
        width: baseCardSize.width * defaultCardScaleMultiplier,
        height: baseCardSize.height * defaultCardScaleMultiplier
    )
    static let gridSpacing: CGFloat = 24
    static let outerPadding = EdgeInsets(top: 34, leading: 36, bottom: 46, trailing: 36)
    static let cardCorner: CGFloat = 15
    static let selectionUnderlayInset: CGFloat = 5
    static var cardSurfaceCorner: CGFloat {
        max(cardCorner - selectionUnderlayInset, 0)
    }
}
