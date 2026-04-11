import Foundation
import CoreGraphics

nonisolated enum BWRCardBuddyEditingChrome {
    static let footerHeight: CGFloat = 24
    static let footerGap: CGFloat = 6
    static let inlineTextInset = CGSize(width: 4, height: 4)
}

nonisolated enum BWRCardBuddyEditingActivation: Equatable, Sendable {
    case beginInlineEdit
    case createCardAndBeginInlineEdit
    case openLargeEditor

    static func keyboardEnter(slotHasCard: Bool) -> Self {
        slotHasCard ? .beginInlineEdit : .createCardAndBeginInlineEdit
    }

    static func doubleClickPreview() -> Self {
        .openLargeEditor
    }
}
