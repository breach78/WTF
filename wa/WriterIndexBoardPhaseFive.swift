import SwiftUI

private enum IndexBoardTempPathConstants {
    static let tempTitle = "temp"
}

extension ScenarioWriterView {
    private func normalizedIndexBoardPathLabel(from text: String) -> String? {
        text
            .components(separatedBy: .newlines)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    func isIndexBoardNoteContainerCard(_ card: SceneCard) -> Bool {
        if card.category == ScenarioCardCategory.note {
            return true
        }
        return normalizedIndexBoardPathLabel(from: card.content) == ScenarioCardCategory.note
    }

    func isIndexBoardTempContainerCard(_ card: SceneCard) -> Bool {
        guard let label = normalizedIndexBoardPathLabel(from: card.content) else { return false }
        return label.caseInsensitiveCompare(IndexBoardTempPathConstants.tempTitle) == .orderedSame
    }

    func resolvedIndexBoardRootCard() -> SceneCard? {
        scenario.rootCards.first
    }

    func resolvedIndexBoardNoteContainer() -> SceneCard? {
        guard let rootCard = resolvedIndexBoardRootCard() else { return nil }
        return liveOrderedSiblings(parent: rootCard).first(where: isIndexBoardNoteContainerCard(_:))
    }

    func resolvedIndexBoardTempContainer() -> SceneCard? {
        guard let noteCard = resolvedIndexBoardNoteContainer() else { return nil }
        return liveOrderedSiblings(parent: noteCard).first(where: isIndexBoardTempContainerCard(_:))
    }

    func ensureIndexBoardTempContainer() -> SceneCard {
        if let existing = resolvedIndexBoardTempContainer() {
            return existing
        }

        let rootCard: SceneCard = {
            if let existing = resolvedIndexBoardRootCard() {
                return existing
            }
            let title = scenario.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let root = SceneCard(
                content: title.isEmpty ? "제목 없음" : title,
                orderIndex: liveOrderedSiblings(parent: nil).count,
                scenario: scenario
            )
            scenario.cards.append(root)
            return root
        }()

        let noteCard: SceneCard = {
            if let existing = liveOrderedSiblings(parent: rootCard).first(where: isIndexBoardNoteContainerCard(_:)) {
                return existing
            }
            let note = SceneCard(
                content: ScenarioCardCategory.note,
                orderIndex: liveOrderedSiblings(parent: rootCard).count,
                parent: rootCard,
                scenario: scenario,
                category: ScenarioCardCategory.note
            )
            scenario.cards.append(note)
            return note
        }()

        let tempCard = SceneCard(
            content: IndexBoardTempPathConstants.tempTitle,
            orderIndex: liveOrderedSiblings(parent: noteCard).count,
            parent: noteCard,
            scenario: scenario,
            category: ScenarioCardCategory.note
        )
        scenario.cards.append(tempCard)
        return tempCard
    }

    func liveIndexBoardTempChildCards() -> [SceneCard] {
        guard let tempContainer = resolvedIndexBoardTempContainer() else { return [] }
        return liveOrderedSiblings(parent: tempContainer)
    }

    func isIndexBoardTempDescendant(cardID: UUID?) -> Bool {
        guard let cardID, let tempContainer = resolvedIndexBoardTempContainer() else { return false }
        var current = findCard(by: cardID)
        while let card = current {
            if card.id == tempContainer.id {
                return true
            }
            current = card.parent
        }
        return false
    }

    @discardableResult
    func createIndexBoardTempCard(at position: IndexBoardGridPosition? = nil) -> SceneCard? {
        guard isIndexBoardActive else { return nil }

        let previousState = captureScenarioState()
        var createdCard: SceneCard?

        scenario.performBatchedCardMutation {
            let tempCard = ensureIndexBoardTempContainer()

            let newCard = SceneCard(
                orderIndex: liveOrderedSiblings(parent: tempCard).count,
                parent: tempCard,
                scenario: scenario,
                category: tempCard.category
            )
            scenario.cards.append(newCard)
            scenario.bumpCardsVersion()
            createdCard = newCard
        }

        guard let createdCard else { return nil }

        selectedCardIDs = [createdCard.id]
        keyboardRangeSelectionAnchorCardID = createdCard.id
        changeActiveCard(
            to: createdCard,
            shouldFocusMain: false,
            deferToMainAsync: false,
            force: true
        )
        if let position {
            indexBoardRuntime.updateSession(for: scenario.id, paneID: paneContextID) { session in
                session.detachedGridPositionByCardID[createdCard.id] = position
                session.tempStrips.append(
                    IndexBoardTempStripState(
                        id: "temp-strip:\(position.row):\(position.column):card:\(createdCard.id.uuidString)",
                        row: position.row,
                        anchorColumn: position.column,
                        members: [IndexBoardTempStripMember(kind: .card, id: createdCard.id)]
                    )
                )
            }
        }
        requestIndexBoardReveal(cardID: createdCard.id)
        commitCardMutation(
            previousState: previousState,
            actionName: "보드 Temp 카드 생성"
        )
        presentIndexBoardEditor(for: createdCard)
        isMainViewFocused = true
        return createdCard
    }
}
