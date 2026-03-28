import SwiftUI

extension ScenarioWriterView {
    enum MoveDirection { case up, down, left, right }

    func moveCardHierarchy(direction: MoveDirection) {
        guard let id = activeCardID, let card = findCard(by: id) else { return }
        let prevState = captureScenarioState()

        normalizeIndices(parent: card.parent)
        let siblings = card.parent?.sortedChildren ?? scenario.rootCards
        guard let currentIndex = siblings.firstIndex(where: { $0.id == id }) else { return }

        switch direction {
        case .up, .down:
            moveCardWithinLevel(card: card, direction: direction)
            normalizeIndices(parent: card.parent)
            card.updateDescendantsCategory(card.parent?.category)
            changeActiveCard(to: card)
            commitCardMutation(
                previousState: prevState,
                actionName: "카드 이동"
            )
            return
        case .left:
            if let parent = card.parent {
                let pIdx = parent.orderIndex
                let grandSiblings = parent.parent?.sortedChildren ?? scenario.rootCards
                for s in grandSiblings where s.orderIndex > pIdx { s.orderIndex += 1 }
                card.parent = parent.parent
                card.orderIndex = pIdx + 1
            }
        case .right:
            if currentIndex > 0 {
                let targetParent = siblings[currentIndex - 1]
                card.parent = targetParent
                card.orderIndex = targetParent.children.count
            }
        }

        normalizeIndices(parent: card.parent)
        card.updateDescendantsCategory(card.parent?.category)
        changeActiveCard(to: card)
        commitCardMutation(
            previousState: prevState,
            actionName: "카드 이동"
        )
    }

    func moveCardWithinLevel(card: SceneCard, direction: MoveDirection) {
        let levels = resolvedAllLevels()
        guard let levelIndex = levels.firstIndex(where: { $0.contains(where: { $0.id == card.id }) }) else { return }
        let level = levels[levelIndex]
        guard let idx = level.firstIndex(where: { $0.id == card.id }) else { return }
        let targetIndex = (direction == .up) ? idx - 1 : idx + 1
        guard targetIndex >= 0 && targetIndex < level.count else { return }
        let target = level[targetIndex]
        let oldParent = card.parent
        let newParent = target.parent

        normalizeIndices(parent: oldParent)
        normalizeIndices(parent: newParent)

        if oldParent?.id == newParent?.id {
            let newIndex = target.orderIndex + (direction == .down ? 1 : 0)
            for s in (newParent?.sortedChildren ?? scenario.rootCards) where s.orderIndex >= newIndex { s.orderIndex += 1 }
            card.orderIndex = newIndex
        } else {
            let newIndex = target.orderIndex + (direction == .down ? 1 : 0)
            for s in (newParent?.sortedChildren ?? scenario.rootCards) where s.orderIndex >= newIndex { s.orderIndex += 1 }
            card.parent = newParent
            card.orderIndex = newIndex
        }

        normalizeIndices(parent: oldParent)
        normalizeIndices(parent: card.parent)
    }

    func normalizeIndices(parent: SceneCard?) {
        let siblings = liveOrderedSiblings(parent: parent)
        for (index, s) in siblings.enumerated() where s.orderIndex != index {
            s.orderIndex = index
        }
    }
}
