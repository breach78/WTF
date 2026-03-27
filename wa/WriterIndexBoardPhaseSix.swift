import SwiftUI

private enum IndexBoardSplitPaneRequestKeys {
    static let cardID = "cardID"
    static let forceMainWorkspace = "forceMainWorkspace"
    static let beginEditing = "beginEditing"
}

extension ScenarioWriterView {
    func requestIndexBoardReveal(cardID: UUID) {
        guard isIndexBoardActive else { return }
        indexBoardRuntime.updateSession(for: scenario.id, paneID: paneContextID, persist: false) { session in
            session.pendingRevealCardID = cardID
            session.revealRequestToken &+= 1
        }
    }

    func isCardInCurrentIndexBoardRange(_ cardID: UUID) -> Bool {
        guard let projection = resolvedIndexBoardProjection() else { return false }
        return projection.orderedCardIDs.contains(cardID)
    }

    func handleIndexBoardTimelineNavigation(_ card: SceneCard, beginEditing: Bool) {
        guard isIndexBoardActive else { return }

        if isCardInCurrentIndexBoardRange(card.id) {
            selectedCardIDs = [card.id]
            keyboardRangeSelectionAnchorCardID = card.id
            changeActiveCard(
                to: card,
                shouldFocusMain: false,
                deferToMainAsync: false,
                force: true
            )
            requestIndexBoardReveal(cardID: card.id)
            if beginEditing {
                presentIndexBoardEditor(for: card)
            } else {
                isMainViewFocused = true
            }
            return
        }

        if splitModeEnabled {
            openIndexBoardTimelineResultInOtherPane(card, beginEditing: beginEditing)
        } else {
            openIndexBoardTimelineResultInMainWorkspace(card, beginEditing: beginEditing)
        }
    }

    func openIndexBoardTimelineResultInMainWorkspace(_ card: SceneCard, beginEditing: Bool) {
        guard findCard(by: card.id) != nil else { return }
        teardownIndexBoardIfNeeded(restoreEntryState: false)
        finishEditing(reason: .transition)
        selectedCardIDs = [card.id]
        keyboardRangeSelectionAnchorCardID = card.id
        changeActiveCard(
            to: card,
            shouldFocusMain: false,
            deferToMainAsync: false,
            force: true
        )
        if beginEditing {
            beginCardEditing(card)
        } else {
            scheduleMainCanvasRestoreRequest(
                targetCardID: card.id,
                forceSemantic: true
            )
            isMainViewFocused = true
        }
    }

    func openIndexBoardTimelineResultInOtherPane(_ card: SceneCard, beginEditing: Bool) {
        let targetPaneID = splitPaneID == 1 ? 2 : 1
        NotificationCenter.default.post(
            name: .waRequestSplitPaneFocus,
            object: targetPaneID,
            userInfo: [
                IndexBoardSplitPaneRequestKeys.cardID: card.id.uuidString,
                IndexBoardSplitPaneRequestKeys.forceMainWorkspace: true,
                IndexBoardSplitPaneRequestKeys.beginEditing: beginEditing
            ]
        )
    }

    func resolvedSplitPaneRequestedCard(from notification: Notification) -> SceneCard? {
        guard let rawCardID = notification.userInfo?[IndexBoardSplitPaneRequestKeys.cardID] as? String,
              let cardID = UUID(uuidString: rawCardID) else {
            return nil
        }
        return findCard(by: cardID)
    }

    func requestedSplitPaneForceMainWorkspace(from notification: Notification) -> Bool {
        (notification.userInfo?[IndexBoardSplitPaneRequestKeys.forceMainWorkspace] as? Bool) == true
    }

    func requestedSplitPaneBeginEditing(from notification: Notification) -> Bool {
        (notification.userInfo?[IndexBoardSplitPaneRequestKeys.beginEditing] as? Bool) == true
    }
}
