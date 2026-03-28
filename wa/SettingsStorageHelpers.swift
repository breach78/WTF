import AppKit
import SwiftUI

struct SettingsViewStorage: DynamicProperty {
    @AppStorage("backgroundColorHex") var backgroundColorHex: String = "F4F2EE"
    @AppStorage("darkBackgroundColorHex") var darkBackgroundColorHex: String = "111418"
    @AppStorage("cardBaseColorHex") var cardBaseColorHex: String = "FFFFFF"
    @AppStorage("cardActiveColorHex") var cardActiveColorHex: String = "BFD7FF"
    @AppStorage("cardRelatedColorHex") var cardRelatedColorHex: String = "DDE9FF"
    @AppStorage("darkCardBaseColorHex") var darkCardBaseColorHex: String = "1A2029"
    @AppStorage("darkCardActiveColorHex") var darkCardActiveColorHex: String = "2A3A4E"
    @AppStorage("darkCardRelatedColorHex") var darkCardRelatedColorHex: String = "242F3F"
    @AppStorage("indexBoardThemePresetID") var indexBoardThemePresetID: String = IndexBoardThemePreset.currentDefault.rawValue
    @AppStorage("customColorThemePresetsJSON") var customColorThemePresetsJSON: String = ""
    @AppStorage("autoBackupEnabledOnQuit") var autoBackupEnabledOnQuit: Bool = true
    @AppStorage("autoBackupDirectoryPath") var autoBackupDirectoryPath: String = ""
    @AppStorage("storageBookmark") var storageBookmark: Data?
    @AppStorage("forceWorkspaceReset") var forceWorkspaceReset: Bool = false
    @AppStorage("exportCenteredFontSize") var exportCenteredFontSize: Double = 12.0
    @AppStorage("exportCenteredCharacterBold") var exportCenteredCharacterBold: Bool = true
    @AppStorage("exportCenteredSceneHeadingBold") var exportCenteredSceneHeadingBold: Bool = true
    @AppStorage("exportCenteredShowRightSceneNumber") var exportCenteredShowRightSceneNumber: Bool = false
    @AppStorage("exportKoreanFontSize") var exportKoreanFontSize: Double = 11.0
    @AppStorage("exportKoreanSceneBold") var exportKoreanSceneBold: Bool = true
    @AppStorage("exportKoreanCharacterBold") var exportKoreanCharacterBold: Bool = true
    @AppStorage("exportKoreanCharacterAlignment") var exportKoreanCharacterAlignment: String = "right"
    @AppStorage("focusTypewriterEnabled") var focusTypewriterEnabled: Bool = false
    @AppStorage("focusTypewriterBaseline") var focusTypewriterBaseline: Double = 0.60
    @AppStorage("mainCardLineSpacingValueV2") var mainCardLineSpacingValue: Double = 5.0
    @AppStorage("mainCardVerticalGap") var mainCardVerticalGap: Double = 0.0
    @AppStorage("focusModeLineSpacingValueTemp") var focusModeLineSpacingValue: Double = 4.5
    @AppStorage("geminiModelID") var geminiModelID: String = "gemini-3.1-pro-preview"
}

enum SettingsKeychainAdapter {
    static func hasGeminiAPIKey() throws -> Bool {
        try KeychainStore.loadGeminiAPIKey() != nil
    }

    static func saveGeminiAPIKey(_ key: String) throws {
        try KeychainStore.saveGeminiAPIKey(key)
    }

    static func deleteGeminiAPIKey() throws {
        try KeychainStore.deleteGeminiAPIKey()
    }
}

enum SettingsWorkspaceFileActionAdapter {
    static func currentStoragePath(from bookmark: Data?) -> String {
        guard let bookmark else { return "설정되지 않음" }
        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return url.path
        }
        return "알 수 없는 경로"
    }

    static func currentAutoBackupPath(from currentPath: String) -> String {
        let trimmed = currentPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return WorkspaceAutoBackupService.defaultBackupDirectoryURL().path
        }
        return NSString(string: trimmed).expandingTildeInPath
    }

    static func initialAutoBackupDirectoryPath(currentPath: String) -> String {
        resolvedInitialAutoBackupDirectoryPath(currentPath: currentPath, expandTilde: true)
    }

    static func selectAutoBackupDirectory(currentPath: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "선택"
        panel.message = "자동 백업 파일을 저장할 폴더를 선택하세요."

        let currentURL = URL(fileURLWithPath: currentPath, isDirectory: true)
        if FileManager.default.fileExists(atPath: currentURL.path) {
            panel.directoryURL = currentURL
        }

        guard panel.runModal() == .OK, let selected = panel.url else { return nil }
        return selected.path
    }

    static func openWorkspaceBookmark() -> Data? {
        selectWorkspaceBookmark(
            mode: .open,
            message: "기존 작업 파일(.wtf)을 선택하세요."
        )
    }

    static func createWorkspaceBookmark() -> Data? {
        selectWorkspaceBookmark(mode: .create, message: nil)
    }
}

extension SettingsView {
    var currentStoragePath: String {
        SettingsWorkspaceFileActionAdapter.currentStoragePath(from: storage.storageBookmark)
    }

    var currentAutoBackupPath: String {
        SettingsWorkspaceFileActionAdapter.currentAutoBackupPath(from: storage.autoBackupDirectoryPath)
    }

    func refreshGeminiAPIKeyStatus() {
        do {
            hasGeminiAPIKey = try SettingsKeychainAdapter.hasGeminiAPIKey()
        } catch {
            hasGeminiAPIKey = false
            setAISettingsStatus(error.localizedDescription, isError: true)
        }
    }

    func saveGeminiAPIKey() {
        let trimmed = geminiAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setAISettingsStatus("저장할 API 키를 입력해 주세요.", isError: true)
            return
        }
        do {
            try SettingsKeychainAdapter.saveGeminiAPIKey(trimmed)
            geminiAPIKeyInput = ""
            refreshGeminiAPIKeyStatus()
            setAISettingsStatus("Gemini API 키를 저장했습니다.", isError: false)
        } catch {
            setAISettingsStatus(error.localizedDescription, isError: true)
        }
    }

    func deleteGeminiAPIKey() {
        do {
            try SettingsKeychainAdapter.deleteGeminiAPIKey()
            geminiAPIKeyInput = ""
            refreshGeminiAPIKeyStatus()
            setAISettingsStatus("저장된 Gemini API 키를 삭제했습니다.", isError: false)
        } catch {
            setAISettingsStatus(error.localizedDescription, isError: true)
        }
    }

    func setAISettingsStatus(_ message: String, isError: Bool) {
        aiSettingsStatusMessage = message
        aiSettingsStatusIsError = isError
    }

    func initializeAutoBackupSettingsIfNeeded() {
        storage.autoBackupDirectoryPath = SettingsWorkspaceFileActionAdapter.initialAutoBackupDirectoryPath(
            currentPath: storage.autoBackupDirectoryPath
        )
    }

    func selectAutoBackupDirectory() {
        guard let selectedPath = SettingsWorkspaceFileActionAdapter.selectAutoBackupDirectory(
            currentPath: currentAutoBackupPath
        ) else { return }
        storage.autoBackupDirectoryPath = selectedPath
        setAutoBackupStatus("자동 백업 폴더를 변경했습니다.", isError: false)
    }

    func setAutoBackupStatus(_ message: String, isError: Bool) {
        autoBackupStatusMessage = message
        autoBackupStatusIsError = isError
    }

    func openWorkspaceFile() {
        guard let bookmark = SettingsWorkspaceFileActionAdapter.openWorkspaceBookmark() else { return }
        storage.storageBookmark = bookmark
        onUpdateStore()
    }

    func createWorkspaceFile() {
        guard let bookmark = SettingsWorkspaceFileActionAdapter.createWorkspaceBookmark() else { return }
        storage.storageBookmark = bookmark
        onUpdateStore()
    }
}
