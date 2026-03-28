import SwiftUI
import AppKit

extension ScenarioWriterView {

    func toggleFocusMode() {
        if !showFocusMode && isIndexBoardActive {
            return
        }
        let entering = !showFocusMode
        beginFocusModePresentationTransition(entering: entering)
        if entering {
            guard let target = resolveFocusModeEntryTargetCard() else { return }
            enterFocusMode(with: target)
        } else {
            exitFocusMode()
        }
        applyFocusModeVisibilityState(entering: entering)
        schedulePostFocusModeToggleFocusUpdate()
    }

    private func resolveFocusModeEntryTargetCard() -> SceneCard? {
        focusPendingProgrammaticBeginEditCardID = nil
        return editingCardID
            .flatMap({ findCard(by: $0) })
            ?? activeCardID.flatMap({ findCard(by: $0) })
            ?? scenario.rootCards.first
    }

    private func enterFocusMode(with target: SceneCard) {
        captureFocusModeEntryWorkspaceSnapshot()
        if let location = resolvedMainCaretLocation(for: target) {
            pendingFocusModeEntryCaretHint = (target.id, location)
        } else {
            pendingFocusModeEntryCaretHint = nil
        }
        beginFocusModeEditing(target, cursorToEnd: false)
        DispatchQueue.main.async {
            requestFocusModeOffsetNormalization(includeActive: true, force: true, reason: "focus-enter-initial")
        }
    }

    private func exitFocusMode() {
        beginFocusModeExitTeardownWindow()
        pendingFocusModeEntryCaretHint = nil
        focusPendingProgrammaticBeginEditCardID = nil
        finishEditing(reason: .transition)
        focusModeEditorCardID = nil
        clearFocusBoundaryArm()
    }

    private func applyFocusModeVisibilityState(entering: Bool) {
        withAnimation(quickEaseAnimation) {
            showFocusMode = entering
            if entering {
                showTimeline = false
                showHistoryBar = false
                showAIChat = false
                exitPreviewMode()
                searchText = ""
                isSearchFocused = false
                isNamedSnapshotSearchFocused = false
            }
        }
    }

    private func schedulePostFocusModeToggleFocusUpdate() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if !showFocusMode {
                restoreMainKeyboardFocus()
            } else {
                isMainViewFocused = true
            }
        }
    }

    private func beginFocusModePresentationTransition(entering: Bool) {
        focusModePresentationPhase = entering ? .entering : .exiting
    }

    func completeFocusModePresentationTransitionIfNeeded(entering: Bool) {
        if entering {
            guard showFocusMode else { return }
            guard focusModePresentationPhase == .entering else { return }
            focusModePresentationPhase = .active
        } else {
            guard !showFocusMode else { return }
            guard focusModePresentationPhase == .exiting else { return }
            focusModePresentationPhase = .inactive
        }
    }

    func scheduleFocusModePresentationPhaseResetAfterExit() {
        let delay = max(0.0, focusModeExitTeardownUntil.timeIntervalSinceNow)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            completeFocusModePresentationTransitionIfNeeded(entering: false)
        }
    }

    func restoreMainKeyboardFocus() {
        let delays: [Double] = [0.0, 0.03, 0.08]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                isSearchFocused = false
                isNamedSnapshotSearchFocused = false
                NSApp.keyWindow?.makeFirstResponder(nil)
                isMainViewFocused = true
            }
        }
    }
}
