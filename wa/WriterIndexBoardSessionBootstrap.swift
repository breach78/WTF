import SwiftUI
import AppKit

extension ScenarioWriterView {
    var paneContextID: Int {
        splitModeEnabled ? splitPaneID : 0
    }

    var isIndexBoardActive: Bool {
        indexBoardRuntime.isActive(scenarioID: scenario.id, paneID: paneContextID)
    }

    var activeIndexBoardSession: IndexBoardSessionState? {
        indexBoardRuntime.session(for: scenario.id, paneID: paneContextID)
    }

    var activeBasePaneMode: WriterPaneMode {
        if isIndexBoardActive { return .indexBoard }
        if showFocusMode { return .focus }
        return .main
    }

    var activePaneMode: WriterPaneMode { activeBasePaneMode }

    func handleIndexBoardVisibilityChange(_ isVisible: Bool) {
        if isVisible {
            stopMainNavKeyMonitor()
            stopMainCaretMonitor()
        } else if !showFocusMode {
            startMainNavKeyMonitor()
            startMainCaretMonitor()
            restoreMainKeyboardFocus()
        }
    }

    func handleIndexBoardKeyPress(_ press: KeyPress) -> KeyPress.Result? {
        guard isIndexBoardActive else { return nil }
        if isIndexBoardEditorPresented {
            guard press.phase == .down else { return .ignored }
            let hasOnlyCommandModifier =
                press.modifiers.contains(.command) &&
                !press.modifiers.contains(.option) &&
                !press.modifiers.contains(.control) &&
                !press.modifiers.contains(.shift)
            if press.key == .escape {
                saveIndexBoardEditor()
                return .handled
            }
            if press.key == .return && hasOnlyCommandModifier {
                saveIndexBoardEditor()
                return .handled
            }
            return .ignored
        }
        if showHistoryBar {
            return nil
        }
        if isSearchFocused || isNamedSnapshotSearchFocused || isNamedSnapshotNoteEditorFocused {
            return nil
        }
        if showAIChat && isAIChatInputFocused {
            return nil
        }
        if let handled = handleIndexBoardSharedPanelShortcut(press) {
            return handled
        }
        if let handled = handleIndexBoardZoomShortcut(press) {
            return handled
        }
        if press.phase == .down && press.key == .escape {
            return .handled
        }
        if press.phase == .down &&
           press.modifiers.contains(.command) &&
           !press.modifiers.contains(.option) &&
           !press.modifiers.contains(.control) &&
           !press.modifiers.contains(.shift) &&
           (press.key == .delete || press.key == .init("\u{7f}")) {
            DispatchQueue.main.async {
                deleteSelectedIndexBoardCards()
            }
            return .handled
        }
        if press.phase == .down &&
           !press.modifiers.contains(.command) &&
           !press.modifiers.contains(.option) &&
           !press.modifiers.contains(.control) {
            if press.key == .return {
                return canBeginIndexBoardInlineEditingFromKeyboard() ? nil : .handled
            }

            let hasPrintableCharacter =
                !press.characters.isEmpty &&
                press.characters.unicodeScalars.contains { !CharacterSet.controlCharacters.contains($0) }
            if hasPrintableCharacter && canBeginIndexBoardInlineEditingFromKeyboard() {
                return nil
            }

            let normalized = press.characters.lowercased()
            if normalized == "n" || press.characters == "ㅜ" {
                _ = createIndexBoardTempCard()
                return .handled
            }
        }
        return .handled
    }

    func canBeginIndexBoardInlineEditingFromKeyboard() -> Bool {
        guard !isIndexBoardEditorPresented else { return false }
        guard selectedCardIDs.count == 1,
              let selectedCardID = selectedCardIDs.first,
              activeCardID == selectedCardID,
              findCard(by: selectedCardID) != nil else {
            return false
        }
        return true
    }

    func handleIndexBoardSharedPanelShortcut(_ press: KeyPress) -> KeyPress.Result? {
        guard press.phase == .down else { return nil }
        guard press.modifiers.contains(.command) else { return nil }
        guard !press.modifiers.contains(.option),
              !press.modifiers.contains(.control) else { return nil }

        let normalized = press.characters.lowercased()
        if !press.modifiers.contains(.shift) && (normalized == "f" || press.characters == "ㄹ") {
            openSearch()
            return .handled
        }
        if press.modifiers.contains(.shift) && (press.characters == "]" || press.characters == "}") {
            toggleTimeline()
            return .handled
        }
        return nil
    }

    func handleIndexBoardZoomShortcut(_ press: KeyPress) -> KeyPress.Result? {
        guard press.phase == .down else { return nil }
        guard press.modifiers.contains(.command) else { return nil }
        guard !press.modifiers.contains(.option),
              !press.modifiers.contains(.control),
              !press.modifiers.contains(.shift) else { return nil }

        switch press.characters {
        case "-", "_":
            stepIndexBoardZoom(by: -0.10)
            return .handled
        case "=", "+":
            stepIndexBoardZoom(by: 0.10)
            return .handled
        case "0", ")":
            resetIndexBoardZoom()
            return .handled
        case "9", "(":
            setIndexBoardZoomScale(IndexBoardZoom.minScale)
            return .handled
        default:
            return nil
        }
    }
}
