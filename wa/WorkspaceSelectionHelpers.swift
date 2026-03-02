import Foundation

enum WorkspaceBookmarkSelectionMode {
    case create
    case open
}

func selectWorkspaceBookmark(mode: WorkspaceBookmarkSelectionMode, message: String?) -> Data? {
    switch mode {
    case .create:
        return WorkspaceBookmarkService.createWorkspaceBookmark(message: message)
    case .open:
        return WorkspaceBookmarkService.openWorkspaceBookmark(message: message ?? "기존 작업 파일(.wtf)을 선택하세요.")
    }
}

func resolvedInitialAutoBackupDirectoryPath(currentPath: String, expandTilde: Bool) -> String {
    let trimmed = currentPath.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return WorkspaceAutoBackupService.defaultBackupDirectoryURL().path
    }
    if expandTilde {
        return NSString(string: trimmed).expandingTildeInPath
    }
    return trimmed
}
