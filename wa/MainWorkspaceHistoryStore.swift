import AppKit
import Foundation
import SwiftUI

struct MainWorkspaceHistoryStore {
    let snapshots: [HistorySnapshot]
    let headIndex: Int?

    var latestHeadIndex: Int? {
        guard !snapshots.isEmpty else { return nil }
        return snapshots.count - 1
    }

    var clampedHeadIndex: Int? {
        guard let latestHeadIndex else { return nil }
        guard let headIndex else { return latestHeadIndex }
        return min(max(0, headIndex), latestHeadIndex)
    }

    var undoTargetIndex: Int? {
        guard let clampedHeadIndex else { return nil }
        guard clampedHeadIndex > 0 else { return nil }
        return clampedHeadIndex - 1
    }

    var redoTargetIndex: Int? {
        guard let clampedHeadIndex, let latestHeadIndex else { return nil }
        guard clampedHeadIndex < latestHeadIndex else { return nil }
        return clampedHeadIndex + 1
    }

    var truncatedSnapshotsForNextCommit: [HistorySnapshot]? {
        guard let clampedHeadIndex else { return nil }
        guard clampedHeadIndex < snapshots.count - 1 else { return nil }
        return Array(snapshots.prefix(clampedHeadIndex + 1))
    }
}

extension ScenarioWriterView {
    func resolvedMainWorkspaceHistoryStore() -> MainWorkspaceHistoryStore {
        MainWorkspaceHistoryStore(
            snapshots: scenario.sortedSnapshots,
            headIndex: mainWorkspaceHistoryHeadIndex
        )
    }

    func syncMainWorkspaceHistoryHeadToLatest() {
        mainWorkspaceHistoryHeadIndex = resolvedMainWorkspaceHistoryStore().latestHeadIndex
    }

    func clampMainWorkspaceHistoryHeadIfNeeded() {
        mainWorkspaceHistoryHeadIndex = resolvedMainWorkspaceHistoryStore().clampedHeadIndex
    }

    func prepareMainWorkspaceHistoryTimelineForCommitIfNeeded() {
        guard !showFocusMode else { return }
        let historyStore = resolvedMainWorkspaceHistoryStore()
        guard let truncatedSnapshots = historyStore.truncatedSnapshotsForNextCommit else { return }
        scenario.snapshots = truncatedSnapshots
        let latest = max(0, truncatedSnapshots.count - 1)
        mainWorkspaceHistoryHeadIndex = latest
        historyIndex = Double(latest)
        isPreviewingHistory = false
        previewDiffs = []
        historyPreviewSelectedCardIDs = []
    }

    func performMainWorkspaceNativeTextUndoIfPossible() -> Bool {
        guard !showFocusMode else { return false }
        guard let editingID = editingCardID,
              let card = findCard(by: editingID) else { return false }

        if let textView = resolveMainEditorTextView(for: card),
           let undoManager = textView.undoManager,
           undoManager.canUndo {
            undoManager.undo()
            return true
        }

        return NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
    }

    func performMainWorkspaceNativeTextRedoIfPossible() -> Bool {
        guard !showFocusMode else { return false }
        guard let editingID = editingCardID,
              let card = findCard(by: editingID) else { return false }

        if let textView = resolveMainEditorTextView(for: card),
           let undoManager = textView.undoManager,
           undoManager.canRedo {
            undoManager.redo()
            return true
        }

        return NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
    }

    func performMainWorkspaceHistoryUndo() {
        guard !showFocusMode else { return }
        let historyStore = resolvedMainWorkspaceHistoryStore()
        guard let targetIndex = historyStore.undoTargetIndex else { return }
        checkoutMainWorkspaceHistory(at: targetIndex)
    }

    func performMainWorkspaceHistoryRedo() {
        guard !showFocusMode else { return }
        let historyStore = resolvedMainWorkspaceHistoryStore()
        guard let targetIndex = historyStore.redoTargetIndex else { return }
        checkoutMainWorkspaceHistory(at: targetIndex)
    }

    func checkoutMainWorkspaceHistory(at targetIndex: Int) {
        guard !showFocusMode else { return }
        let snapshots = scenario.sortedSnapshots
        guard targetIndex >= 0 && targetIndex < snapshots.count else { return }
        guard let restoredSnapshots = resolvedCardSnapshots(at: targetIndex, in: snapshots) else { return }

        let previousActiveID = activeCardID
        let previousSelection = selectedCardIDs
        let existingCreatedAtByCardID = Dictionary(uniqueKeysWithValues: scenario.cards.map { ($0.id, $0.createdAt) })
        let targetTimestamp = snapshots[targetIndex].timestamp

        let restoredCards = restoredSnapshots.map { snapshot in
            SceneCard(
                id: snapshot.cardID,
                content: snapshot.content,
                orderIndex: snapshot.orderIndex,
                createdAt: existingCreatedAtByCardID[snapshot.cardID] ?? targetTimestamp,
                parent: nil,
                scenario: nil,
                category: snapshot.category,
                isFloating: snapshot.isFloating,
                isArchived: snapshot.isArchived,
                lastSelectedChildID: nil,
                colorHex: nil,
                cloneGroupID: snapshot.cloneGroupID
            )
        }

        var restoredByID: [UUID: SceneCard] = [:]
        restoredByID.reserveCapacity(restoredCards.count)
        for card in restoredCards {
            restoredByID[card.id] = card
        }
        for snapshot in restoredSnapshots {
            guard let card = restoredByID[snapshot.cardID] else { continue }
            card.parent = snapshot.parentID.flatMap { restoredByID[$0] }
            card.scenario = scenario
        }

        let validSelection = Set(previousSelection.filter { restoredByID[$0] != nil })
        let resolvedActiveCard: SceneCard? = {
            if let previousActiveID,
               let existing = restoredByID[previousActiveID] {
                return existing
            }
            if let lastActiveCardID,
               let existing = restoredByID[lastActiveCardID] {
                return existing
            }
            return restoredCards.first(where: { $0.parent == nil && !$0.isArchived }) ??
                restoredCards.first(where: { !$0.isArchived })
        }()

        isApplyingUndo = true
        scenario.performWithoutTimestampTracking {
            scenario.performBatchedCardMutation {
                scenario.cards = restoredCards
                scenario.changeCountSinceLastSnapshot = 0
                scenario.bumpCardsVersion()
            }
        }
        resetEditingTransientState()
        mainLastCommittedContentByCard = Dictionary(uniqueKeysWithValues: scenario.cards.map { ($0.id, $0.content) })
        selectedCardIDs = validSelection
        if let resolvedActiveCard {
            if selectedCardIDs.isEmpty {
                selectedCardIDs = [resolvedActiveCard.id]
            }
            changeActiveCard(
                to: resolvedActiveCard,
                shouldFocusMain: false,
                deferToMainAsync: false,
                force: true
            )
        } else {
            activeCardID = nil
            synchronizeMainWorkspaceSelectionState(
                previousActiveID: previousActiveID,
                nextActiveID: nil,
                updateHistory: false
            )
        }
        mainWorkspaceHistoryHeadIndex = targetIndex
        historyIndex = Double(targetIndex)
        isPreviewingHistory = false
        previewDiffs = []
        historyPreviewSelectedCardIDs = []
        saveWriterChanges(immediate: true)
        isApplyingUndo = false
    }
}
