import SwiftUI
import AppKit
import UniformTypeIdentifiers

func isTrailingSiblingBlockDragActive() -> Bool {
    let tracker = MainCardDragSessionTracker.shared
    if tracker.isDragging {
        tracker.refreshCommandState()
        return tracker.isCommandPressed
    }
    return NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
}

struct CardActionZoneDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let performAction: ([NSItemProvider], Bool) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        MainCardDragSessionTracker.shared.refreshCommandState()
        return DropProposal(operation: isTrailingSiblingBlockDragActive() ? .copy : .move)
    }

    func dropEntered(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.15)) { isTargeted = true }
    }

    func dropExited(info: DropInfo) {
        if isTargeted {
            withAnimation(.easeInOut(duration: 0.15)) { isTargeted = false }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.text])
        guard !providers.isEmpty else { return false }
        performAction(providers, isTrailingSiblingBlockDragActive())
        isTargeted = false
        MainCardDragSessionTracker.shared.end()
        return true
    }
}
