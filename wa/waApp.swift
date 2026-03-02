import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension Notification.Name {
    static let waUndoRequested = Notification.Name("wa.undoRequested")
    static let waRedoRequested = Notification.Name("wa.redoRequested")
    static let waToggleFocusModeRequested = Notification.Name("wa.toggleFocusModeRequested")
    static let waOpenReferenceWindowRequested = Notification.Name("wa.openReferenceWindowRequested")
    static let waCycleSplitPaneRequested = Notification.Name("wa.cycleSplitPaneRequested")
    static let waSplitPaneActivateRequested = Notification.Name("wa.splitPaneActivateRequested")
    static let waRequestSplitPaneFocus = Notification.Name("wa.requestSplitPaneFocus")
}

extension UTType {
    static var waWorkspace: UTType {
        UTType(filenameExtension: "wtf") ?? UTType(exportedAs: "com.wa.workspace", conformingTo: .package)
    }
}

enum WorkspaceBookmarkService {
    static func openWorkspaceBookmark(message: String) -> Data? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.item]
        panel.message = message

        guard panel.runModal() == .OK, let chosenURL = panel.url else { return nil }
        guard chosenURL.pathExtension.lowercased() == "wtf" else { return nil }
        return try? bookmarkData(forWorkspaceURL: chosenURL)
    }

    static func createWorkspaceBookmark(message: String?, defaultFileName: String = "workspace.wtf") -> Data? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.waWorkspace]
        panel.nameFieldStringValue = defaultFileName
        panel.isExtensionHidden = false
        if let message {
            panel.message = message
        }

        guard panel.runModal() == .OK, let chosenURL = panel.url else { return nil }
        let workspaceURL = chosenURL.pathExtension.lowercased() == "wtf"
            ? chosenURL
            : chosenURL.appendingPathExtension("wtf")

        do {
            try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
            return try bookmarkData(forWorkspaceURL: workspaceURL)
        } catch {
            return nil
        }
    }

    private static func bookmarkData(forWorkspaceURL workspaceURL: URL) throws -> Data {
        var url = workspaceURL
        var values = URLResourceValues()
        values.isPackage = true
        try? url.setResourceValues(values)
        return try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}

enum WorkspaceAutoBackupService {
    nonisolated private static let keepLatestCount = 10
    nonisolated private static let dailyRetentionDays = 7
    nonisolated private static let weeklyRetentionDays = 28
    nonisolated private static let archiveSuffix = ".wtf.zip"
    nonisolated private static let workspacePackageExtension = "wtf"
    nonisolated private static let timestampLength = 19 // yyyy-MM-dd-HH-mm-ss
    nonisolated private static let daySeconds: TimeInterval = 24 * 60 * 60

    struct Result {
        let archiveURL: URL
        let deletedCount: Int
    }

    enum BackupError: LocalizedError {
        case invalidWorkspace
        case backupDirectoryInsideWorkspace
        case compressionFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidWorkspace:
                return "백업할 작업 파일 경로를 찾을 수 없습니다."
            case .backupDirectoryInsideWorkspace:
                return "백업 폴더를 작업 파일(.wtf) 내부에 둘 수 없습니다."
            case .compressionFailed(let stderr):
                if stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return "작업 파일 압축 백업에 실패했습니다."
                }
                return "작업 파일 압축 백업에 실패했습니다: \(stderr)"
            }
        }
    }

    private struct BackupArchiveEntry {
        let url: URL
        let timestamp: Date
    }

    nonisolated static func defaultBackupDirectoryURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("wa-backups", isDirectory: true)
    }

    nonisolated static func resolvedBackupDirectoryURL(from storedPath: String) -> URL {
        let trimmed = storedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return defaultBackupDirectoryURL()
        }
        let expanded = NSString(string: trimmed).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    nonisolated static func createCompressedBackupAndPrune(
        workspaceURL: URL,
        backupDirectoryURL: URL,
        now: Date = Date()
    ) throws -> Result {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: backupDirectoryURL, withIntermediateDirectories: true)
        let workspacePath = workspaceURL.standardizedFileURL.path + "/"
        let backupPath = backupDirectoryURL.standardizedFileURL.path + "/"
        guard !backupPath.hasPrefix(workspacePath) else {
            throw BackupError.backupDirectoryInsideWorkspace
        }

        let workspaceName = sanitizedWorkspaceName(from: workspaceURL)
        guard !workspaceName.isEmpty else { throw BackupError.invalidWorkspace }

        let timestampFormatter = makeTimestampFormatter()
        var archiveTimestamp = now
        var archiveURL = backupDirectoryURL.appendingPathComponent(
            "\(workspaceName)-\(timestampFormatter.string(from: archiveTimestamp))\(archiveSuffix)"
        )
        while fileManager.fileExists(atPath: archiveURL.path) {
            archiveTimestamp = archiveTimestamp.addingTimeInterval(1)
            archiveURL = backupDirectoryURL.appendingPathComponent(
                "\(workspaceName)-\(timestampFormatter.string(from: archiveTimestamp))\(archiveSuffix)"
            )
        }

        try runCompressionCommand(
            workspaceURL: workspaceURL,
            archiveURL: archiveURL,
            workspaceName: workspaceName
        )

        let entries = loadEntries(
            for: workspaceName,
            in: backupDirectoryURL,
            fallbackNow: now
        )
        let deleteTargets = entriesToDelete(entries: entries, now: now)
        for target in deleteTargets {
            try? fileManager.removeItem(at: target.url)
        }

        return Result(archiveURL: archiveURL, deletedCount: deleteTargets.count)
    }

    nonisolated private static func runCompressionCommand(
        workspaceURL: URL,
        archiveURL: URL,
        workspaceName: String
    ) throws {
        let expectedPackageName = "\(workspaceName).\(workspacePackageExtension)"
        if workspaceURL.lastPathComponent.caseInsensitiveCompare(expectedPackageName) == .orderedSame {
            markAsPackageIfPossible(at: workspaceURL)
            try runDittoCompression(sourceURL: workspaceURL, archiveURL: archiveURL)
            return
        }

        // Legacy folder names without .wtf extension are staged to a .wtf package name
        // so unzipping always restores a .wtf container.
        let fileManager = FileManager.default
        let stagingDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("wa-backup-staging-\(UUID().uuidString)", isDirectory: true)
        let stagedWorkspaceURL = stagingDirectoryURL.appendingPathComponent(expectedPackageName, isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectoryURL, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: stagingDirectoryURL)
        }

        do {
            try runDittoCopy(sourceURL: workspaceURL, destinationURL: stagedWorkspaceURL)
            markAsPackageIfPossible(at: stagedWorkspaceURL)
            try runDittoCompression(sourceURL: stagedWorkspaceURL, archiveURL: archiveURL)
        } catch let backupError as BackupError {
            throw backupError
        } catch {
            throw BackupError.compressionFailed(error.localizedDescription)
        }
    }

    nonisolated private static func runDittoCopy(sourceURL: URL, destinationURL: URL) throws {
        try runDittoCommand(arguments: [sourceURL.path, destinationURL.path])
    }

    nonisolated private static func runDittoCompression(sourceURL: URL, archiveURL: URL) throws {
        try runDittoCommand(arguments: [
            "-c",
            "-k",
            "--sequesterRsrc",
            "--keepParent",
            sourceURL.path,
            archiveURL.path
        ])
    }

    nonisolated private static func runDittoCommand(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            throw BackupError.compressionFailed(stderr)
        }
    }

    nonisolated private static func markAsPackageIfPossible(at url: URL) {
        guard url.pathExtension.lowercased() == workspacePackageExtension else { return }
        var mutableURL = url
        var values = URLResourceValues()
        values.isPackage = true
        try? mutableURL.setResourceValues(values)
    }

    nonisolated private static func sanitizedWorkspaceName(from workspaceURL: URL) -> String {
        let base = workspaceURL.deletingPathExtension().lastPathComponent
        let replaced = base.replacingOccurrences(
            of: "[/:\\\\?%*|\"<>]",
            with: "_",
            options: .regularExpression
        )
        let trimmed = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "workspace" : trimmed
    }

    nonisolated private static func makeTimestampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter
    }

    nonisolated private static func loadEntries(
        for workspaceName: String,
        in backupDirectoryURL: URL,
        fallbackNow: Date
    ) -> [BackupArchiveEntry] {
        let fileManager = FileManager.default
        let prefix = "\(workspaceName)-"
        let timestampFormatter = makeTimestampFormatter()
        let urls = (try? fileManager.contentsOfDirectory(
            at: backupDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.compactMap { url in
            let name = url.lastPathComponent
            guard name.hasPrefix(prefix), name.hasSuffix(archiveSuffix) else { return nil }
            guard name.count >= prefix.count + timestampLength + archiveSuffix.count else { return nil }

            let timestampStart = name.index(name.endIndex, offsetBy: -(timestampLength + archiveSuffix.count))
            let timestampEnd = name.index(name.endIndex, offsetBy: -archiveSuffix.count)
            let timestampText = String(name[timestampStart..<timestampEnd])
            let timestamp = timestampFormatter.date(from: timestampText)
                ?? ((try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]).creationDate)
                    ?? (try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]).contentModificationDate)
                    ?? fallbackNow)
            return BackupArchiveEntry(url: url, timestamp: timestamp)
        }
        .sorted { $0.timestamp > $1.timestamp }
    }

    nonisolated private static func entriesToDelete(entries: [BackupArchiveEntry], now: Date) -> [BackupArchiveEntry] {
        guard !entries.isEmpty else { return [] }

        var keepPaths: Set<String> = Set(entries.prefix(keepLatestCount).map { $0.url.path })
        var dailyBucketKeys: Set<String> = []
        var weeklyBucketKeys: Set<String> = []
        var monthlyBucketKeys: Set<String> = []
        let calendar = Calendar(identifier: .gregorian)

        for entry in entries.dropFirst(keepLatestCount) {
            let age = now.timeIntervalSince(entry.timestamp)
            if age < daySeconds * Double(dailyRetentionDays) {
                let comps = calendar.dateComponents([.year, .month, .day], from: entry.timestamp)
                let key = "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
                if dailyBucketKeys.insert(key).inserted {
                    keepPaths.insert(entry.url.path)
                }
                continue
            }

            if age < daySeconds * Double(weeklyRetentionDays) {
                let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: entry.timestamp)
                let key = "\(comps.yearForWeekOfYear ?? 0)-\(comps.weekOfYear ?? 0)"
                if weeklyBucketKeys.insert(key).inserted {
                    keepPaths.insert(entry.url.path)
                }
                continue
            }

            let comps = calendar.dateComponents([.year, .month], from: entry.timestamp)
            let key = "\(comps.year ?? 0)-\(comps.month ?? 0)"
            if monthlyBucketKeys.insert(key).inserted {
                keepPaths.insert(entry.url.path)
            }
        }

        return entries.filter { !keepPaths.contains($0.url.path) }
    }
}

private struct MainWindowTitleHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let window = view.window else {
            DispatchQueue.main.async {
                guard let window = view.window else { return }
                apply(to: window)
            }
            return
        }
        apply(to: window)
    }

    private func apply(to window: NSWindow) {
        if window.identifier?.rawValue == ReferenceWindowConstants.windowID { return }
        if window.titleVisibility != .hidden {
            window.titleVisibility = .hidden
        }
        if !window.title.isEmpty {
            window.title = ""
        }
    }
}

private struct MainWindowSizePersistenceAccessor: NSViewRepresentable {
    private static let widthKey = "mainWorkspaceWindowWidthV1"
    private static let heightKey = "mainWorkspaceWindowHeightV1"

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.attach(to: view)
    }

    final class Coordinator {
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var didRestoreSize = false

        deinit {
            removeObservers()
        }

        func attach(to view: NSView) {
            guard let attachedWindow = view.window else {
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view else { return }
                    self.attach(to: view)
                }
                return
            }

            if window !== attachedWindow {
                removeObservers()
                window = attachedWindow
                didRestoreSize = false
                installObservers(for: attachedWindow)
            }

            restoreSizeIfNeeded(for: attachedWindow)
        }

        private func installObservers(for window: NSWindow) {
            let center = NotificationCenter.default
            observers.append(
                center.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main) { [weak self] _ in
                    self?.persistSize(from: window)
                }
            )
            observers.append(
                center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                    self?.persistSize(from: window)
                }
            )
            observers.append(
                center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                    self?.persistSize(from: window)
                }
            )
        }

        private func removeObservers() {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers.removeAll()
        }

        private func restoreSizeIfNeeded(for window: NSWindow) {
            guard !didRestoreSize else { return }
            didRestoreSize = true
            let defaults = UserDefaults.standard
            let width = defaults.double(forKey: MainWindowSizePersistenceAccessor.widthKey)
            let height = defaults.double(forKey: MainWindowSizePersistenceAccessor.heightKey)
            guard width >= 500, height >= 400 else { return }
            var frame = window.frame
            if abs(frame.size.width - width) < 0.5, abs(frame.size.height - height) < 0.5 {
                return
            }
            frame.size = NSSize(width: width, height: height)
            window.setFrame(frame, display: true)
        }

        private func persistSize(from window: NSWindow) {
            guard window.identifier?.rawValue != ReferenceWindowConstants.windowID else { return }
            guard !window.styleMask.contains(.fullScreen) else { return }
            let width = window.frame.width
            let height = window.frame.height
            guard width >= 500, height >= 400 else { return }
            let defaults = UserDefaults.standard
            defaults.set(width, forKey: MainWindowSizePersistenceAccessor.widthKey)
            defaults.set(height, forKey: MainWindowSizePersistenceAccessor.heightKey)
        }
    }
}

@main
struct waApp: App {
    @AppStorage("fontSize") private var fontSize: Double = 14.0
    @AppStorage("mainWorkspaceZoomScale") private var mainWorkspaceZoomScale: Double = 1.0
    @AppStorage("focusTypewriterEnabled") private var focusTypewriterEnabled: Bool = false
    @AppStorage("mainSplitModeEnabled") private var mainSplitModeEnabled: Bool = false
    @AppStorage("appearance") private var appearance: String = "dark"
    @AppStorage("backgroundColorHex") private var backgroundColorHex: String = "F4F2EE"
    @AppStorage("darkBackgroundColorHex") private var darkBackgroundColorHex: String = "111418"
    @AppStorage("focusModeWindowBackgroundActive") private var focusModeWindowBackgroundActive: Bool = false
    @AppStorage("forceWorkspaceReset") private var forceWorkspaceReset: Bool = false
    @AppStorage("didResetForV2") private var didResetForV2: Bool = false
    @AppStorage("autoBackupEnabledOnQuit") private var autoBackupEnabledOnQuit: Bool = true
    @AppStorage("autoBackupDirectoryPath") private var autoBackupDirectoryPath: String = ""
    
    // 폴더 접근 권한을 유지하기 위한 북마크 데이터 저장
    @AppStorage("storageBookmark") private var storageBookmark: Data?
    
    // 현재 활성화된 파일 스토어를 관리
    @State private var store: FileStore?
    @StateObject private var referenceCardStore = ReferenceCardStore()
    @State private var didHideReferenceWindowOnLaunch: Bool = false

    init() {
        UserDefaults.standard.set(false, forKey: "TSMLanguageIndicatorEnabled")
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(nsColor: focusModeWindowBackgroundActive ? .black : resolvedWindowBackgroundColor)
                    .ignoresSafeArea()
                Group {
                    if let store = store {
                        // 스토어가 준비되면 메인 뷰 표시
                        MainContainerView()
                            .environmentObject(store)
                            .environmentObject(referenceCardStore)
                            .preferredColorScheme(appearance == "dark" ? .dark : (appearance == "light" ? .light : nil))
                    } else {
                        // 컨테이너가 없으면(최초 실행 시) 설정 화면 표시
                        storageSetupView
                    }
                }
            }
            .background(MainWindowTitleHider())
            .background(MainWindowSizePersistenceAccessor())
            .onAppear {
                if !didResetForV2 {
                    store?.flushPendingSaves()
                    storageBookmark = nil
                    store = nil
                    didResetForV2 = true
                }
                if forceWorkspaceReset {
                    store?.flushPendingSaves()
                    storageBookmark = nil
                    store = nil
                    forceWorkspaceReset = false
                }
                initializeAutoBackupSettingsIfNeeded()
                setupStore()
                focusModeWindowBackgroundActive = false
                hideReferenceWindowOnLaunchOnce()
            }
            .onChange(of: forceWorkspaceReset) { _, newValue in
                if newValue {
                    store?.flushPendingSaves()
                    storageBookmark = nil
                    store = nil
                    forceWorkspaceReset = false
                }
            }
            .onChange(of: storageBookmark) { _, _ in
                setupStore()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                handleApplicationWillTerminate()
            }
        }
        .windowStyle(.hiddenTitleBar)
        Window("레퍼런스 카드", id: ReferenceWindowConstants.windowID) {
            Group {
                if let store = store {
                    ReferenceWindowView()
                        .frame(width: ReferenceWindowConstants.windowWidth)
                        .environmentObject(store)
                        .preferredColorScheme(appearance == "dark" ? .dark : (appearance == "light" ? .light : nil))
                } else {
                    Text("작업 파일을 먼저 열어주세요.")
                        .padding(20)
                }
            }
            .environmentObject(referenceCardStore)
        }
        .windowResizability(.contentSize)
        .commandsRemoved()
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    if performReferenceWindowUndoIfPossible() {
                        return
                    }
                    NotificationCenter.default.post(name: .waUndoRequested, object: nil)
                }
                .keyboardShortcut("z", modifiers: [.command])

                Button("Redo") {
                    if performReferenceWindowRedoIfPossible() {
                        return
                    }
                    NotificationCenter.default.post(name: .waRedoRequested, object: nil)
                }
                .keyboardShortcut("Z", modifiers: [.command, .shift])
            }
            CommandGroup(after: .windowArrangement) {
                Button("레퍼런스 창 열기") {
                    NotificationCenter.default.post(name: .waOpenReferenceWindowRequested, object: nil)
                }
                .keyboardShortcut("R", modifiers: [.command, .option])
            }
            CommandGroup(after: .textEditing) {
                Button("집중 모드 토글") {
                    NotificationCenter.default.post(name: .waToggleFocusModeRequested, object: nil)
                }
                .keyboardShortcut("F", modifiers: [.command, .shift])
            }
            CommandGroup(before: .windowSize) {
                Toggle("다크 모드", isOn: darkModeMenuBinding)
                Divider()

                Toggle("메인 작업창 스플릿 모드", isOn: $mainSplitModeEnabled)
                Divider()

                Toggle("포커스 모드 타이프라이터", isOn: $focusTypewriterEnabled)
                Divider()

                Button("메인 작업창 줌 축소") {
                    adjustMainWorkspaceZoom(by: -0.05)
                }
                .disabled(mainWorkspaceZoomScale <= 0.70)

                Button("메인 작업창 줌 확대") {
                    adjustMainWorkspaceZoom(by: 0.05)
                }
                .disabled(mainWorkspaceZoomScale >= 1.60)

                Button("메인 작업창 줌 100%") {
                    mainWorkspaceZoomScale = 1.0
                }
                Divider()

                Menu("편집기") {
                    Button("폰트 작게") {
                        adjustFontSize(by: -1)
                    }
                    .disabled(fontSize <= 12)

                    Button("폰트 크게") {
                        adjustFontSize(by: 1)
                    }
                    .disabled(fontSize >= 24)

                    Button("폰트 기본값 (17pt)") {
                        fontSize = 17
                    }
                }
            }
        }
        
        Settings {
            SettingsView(onUpdateStore: { setupStore() })
                .preferredColorScheme(.light)
        }
    }
    
    // --- 저장소 설정 로직 ---
    
    @ViewBuilder
    private var storageSetupView: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            VStack(spacing: 12) {
                Text("데이터 저장 위치 설정")
                    .font(.title)
                    .fontWeight(.bold)
                Text("시나리오 텍스트 파일을 저장할 작업 파일(.wtf)을 선택해주세요.\n클라우드 동기화 폴더(Dropbox, iCloud Drive 등)에 저장하면\n다른 기기에서도 이어서 작업할 수 있습니다.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 40)
            
            VStack(spacing: 12) {
                Button(action: openWorkspaceFile) {
                    Text("기존 작업 파일 열기")
                        .fontWeight(.semibold)
                        .frame(width: 220, height: 32)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(action: createWorkspaceFile) {
                    Text("새 작업 파일 만들기")
                        .fontWeight(.semibold)
                        .frame(width: 220, height: 32)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .frame(minWidth: 550, minHeight: 450)
    }
    
    private func setupStore() {
        guard let bookmark = storageBookmark else { return }

        Task { @MainActor in
            store?.flushPendingSaves()
            self.store = nil
            
            do {
                var isStale = false
                // 북마크로부터 URL 복원 및 권한 획득
                let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                
                if isStale {
                    let newBookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    storageBookmark = newBookmark
                }
                
                _ = url.startAccessingSecurityScopedResource()

                let newStore = FileStore(folderURL: url)
                await newStore.load()

                self.store = newStore
            } catch {
                storageBookmark = nil // 실패 시 다시 선택하도록 초기화
            }
        }
    }
    
    private func createWorkspaceFile() {
        if let bookmark = selectWorkspaceBookmark(
            mode: .create,
            message: "작업 파일(.wtf)을 선택하거나 새로 만드세요."
        ) {
            storageBookmark = bookmark
            setupStore()
        }
    }

    private func openWorkspaceFile() {
        if let bookmark = selectWorkspaceBookmark(
            mode: .open,
            message: "기존 작업 파일(.wtf)을 선택하세요."
        ) {
            storageBookmark = bookmark
            setupStore()
        }
    }

    private func isReferenceWindowFocused() -> Bool {
        NSApp.keyWindow?.identifier?.rawValue == ReferenceWindowConstants.windowID
    }

    private func hideReferenceWindowOnLaunchOnce() {
        guard !didHideReferenceWindowOnLaunch else { return }
        didHideReferenceWindowOnLaunch = true
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows {
                if window.identifier?.rawValue == ReferenceWindowConstants.windowID {
                    window.close()
                }
            }
        }
    }

    private func performReferenceWindowUndoIfPossible() -> Bool {
        guard isReferenceWindowFocused() else { return false }
        guard let store else { return true }
        if referenceCardStore.performUndo(fileStore: store) {
            return true
        }
        return true
    }

    private func performReferenceWindowRedoIfPossible() -> Bool {
        guard isReferenceWindowFocused() else { return false }
        guard let store else { return true }
        if referenceCardStore.performRedo(fileStore: store) {
            return true
        }
        return true
    }

    private func resolvedWindowBackgroundHex() -> String {
        if appearance == "dark" { return darkBackgroundColorHex }
        if appearance == "light" { return backgroundColorHex }
        if let best = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]),
           best == .darkAqua {
            return darkBackgroundColorHex
        }
        return backgroundColorHex
    }

    private var resolvedWindowBackgroundColor: NSColor {
        nsColorFromHex(resolvedWindowBackgroundHex()) ?? NSColor.windowBackgroundColor
    }

    private func nsColorFromHex(_ hex: String) -> NSColor? {
        guard let rgb = parseHexRGB(hex) else { return nil }
        let r = CGFloat(rgb.0)
        let g = CGFloat(rgb.1)
        let b = CGFloat(rgb.2)
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    private var darkModeMenuBinding: Binding<Bool> {
        Binding(
            get: {
                if appearance == "dark" { return true }
                if appearance == "light" { return false }
                if let best = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
                    return best == .darkAqua
                }
                return false
            },
            set: { appearance = $0 ? "dark" : "light" }
        )
    }

    private func adjustFontSize(by delta: Double) {
        let next = min(24.0, max(12.0, fontSize + delta))
        fontSize = next
    }

    private func adjustMainWorkspaceZoom(by delta: Double) {
        let next = min(1.60, max(0.70, mainWorkspaceZoomScale + delta))
        mainWorkspaceZoomScale = (next * 100).rounded() / 100
    }

    private func initializeAutoBackupSettingsIfNeeded() {
        autoBackupDirectoryPath = resolvedInitialAutoBackupDirectoryPath(
            currentPath: autoBackupDirectoryPath,
            expandTilde: false
        )
    }

    private func handleApplicationWillTerminate() {
        store?.flushPendingSaves()
        guard autoBackupEnabledOnQuit else { return }
        guard let workspaceURL = store?.folderURL else { return }
        let backupDirectoryURL = WorkspaceAutoBackupService.resolvedBackupDirectoryURL(from: autoBackupDirectoryPath)
        do {
            let result = try WorkspaceAutoBackupService.createCompressedBackupAndPrune(
                workspaceURL: workspaceURL,
                backupDirectoryURL: backupDirectoryURL
            )
            print("Auto backup created: \(result.archiveURL.path), pruned \(result.deletedCount) file(s)")
        } catch {
            print("Auto backup failed: \(error.localizedDescription)")
        }
    }

}
