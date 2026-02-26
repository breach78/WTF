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
                store?.flushPendingSaves()
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
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.waWorkspace]
        panel.nameFieldStringValue = "workspace.wtf"
        panel.isExtensionHidden = false
        panel.message = "작업 파일(.wtf)을 선택하거나 새로 만드세요."
        
        if panel.runModal() == .OK, let chosenURL = panel.url {
            var url = chosenURL.pathExtension.lowercased() == "wtf" ? chosenURL : chosenURL.appendingPathExtension("wtf")
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                var values = URLResourceValues()
                values.isPackage = true
                try? url.setResourceValues(values)
                // 향후 앱 재실행 시에도 접근 가능하도록 북마크 생성
                let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                storageBookmark = bookmark
                setupStore()
            } catch {
            }
        }
    }

    private func openWorkspaceFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.item]
        panel.message = "기존 작업 파일(.wtf)을 선택하세요."
        
        if panel.runModal() == .OK, let chosenURL = panel.url {
            guard chosenURL.pathExtension.lowercased() == "wtf" else { return }
            var url = chosenURL
            do {
                var values = URLResourceValues()
                values.isPackage = true
                try? url.setResourceValues(values)
                let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                storageBookmark = bookmark
                setupStore()
            } catch {
            }
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
        var hexValue = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if hexValue.hasPrefix("#") { hexValue.removeFirst() }
        guard hexValue.count == 6, let intVal = Int(hexValue, radix: 16) else { return nil }
        let r = CGFloat((intVal >> 16) & 0xFF) / 255.0
        let g = CGFloat((intVal >> 8) & 0xFF) / 255.0
        let b = CGFloat(intVal & 0xFF) / 255.0
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

}

struct SettingsView: View {
    private struct ShortcutItem: Identifiable {
        let keys: String
        let action: String
        var id: String { "\(keys)|\(action)" }
    }

    private struct ShortcutSection: Identifiable {
        let title: String
        let items: [ShortcutItem]
        var id: String { title }
    }

    private struct GeminiModelOption: Identifiable {
        let value: String
        let title: String
        var id: String { value }
    }

    private enum ColorThemePreset: String, CaseIterable, Identifiable {
        case warmPaper
        case mintFog
        case blueGray
        case sepiaCalm
        case sageSlate
        case quietSlate
        case mellowOlive

        var id: String { rawValue }

        var title: String {
            switch self {
            case .warmPaper: return "Warm Paper"
            case .mintFog: return "Mint Fog"
            case .blueGray: return "Blue Gray"
            case .sepiaCalm: return "Sepia Calm"
            case .sageSlate: return "Sage Slate"
            case .quietSlate: return "Quiet Slate"
            case .mellowOlive: return "Mellow Olive"
            }
        }

        var lightBackground: String {
            switch self {
            case .warmPaper: return "F6F1E6"
            case .mintFog: return "EDF5F0"
            case .blueGray: return "EFF3F6"
            case .sepiaCalm: return "F5ECE0"
            case .sageSlate: return "F0F3EE"
            case .quietSlate: return "4B4F56"
            case .mellowOlive: return "50534C"
            }
        }

        var lightCardBase: String {
            switch self {
            case .warmPaper: return "FFFCF5"
            case .mintFog: return "F9FFFC"
            case .blueGray: return "FBFDFE"
            case .sepiaCalm: return "FFF8EF"
            case .sageSlate: return "FBFEF9"
            case .quietSlate: return "777D86"
            case .mellowOlive: return "7D8178"
            }
        }

        var lightCardActive: String {
            switch self {
            case .warmPaper: return "F2D8B4"
            case .mintFog: return "CCE9DD"
            case .blueGray: return "CDDDEA"
            case .sepiaCalm: return "E8CFAF"
            case .sageSlate: return "D4DEC9"
            case .quietSlate: return "D7E9FB"
            case .mellowOlive: return "E0EDCF"
            }
        }

        var lightCardRelated: String {
            switch self {
            case .warmPaper: return "F7E7CF"
            case .mintFog: return "E0F2EA"
            case .blueGray: return "E1ECF3"
            case .sepiaCalm: return "F1DFC8"
            case .sageSlate: return "E5ECDD"
            case .quietSlate: return "C4DCF3"
            case .mellowOlive: return "D0E2BE"
            }
        }

        var darkBackground: String {
            switch self {
            case .warmPaper: return "141516"
            case .mintFog: return "111A18"
            case .blueGray: return "10161C"
            case .sepiaCalm: return "19140F"
            case .sageSlate: return "121814"
            case .quietSlate: return "141920"
            case .mellowOlive: return "171A14"
            }
        }

        var darkCardBase: String {
            switch self {
            case .warmPaper: return "212220"
            case .mintFog: return "1A2623"
            case .blueGray: return "1A2430"
            case .sepiaCalm: return "2A221A"
            case .sageSlate: return "1D2822"
            case .quietSlate: return "242B35"
            case .mellowOlive: return "282D23"
            }
        }

        var darkCardActive: String {
            switch self {
            case .warmPaper: return "5A4631"
            case .mintFog: return "2F4D46"
            case .blueGray: return "33495E"
            case .sepiaCalm: return "5A4633"
            case .sageSlate: return "3A5147"
            case .quietSlate: return "41546B"
            case .mellowOlive: return "4B5D3D"
            }
        }

        var darkCardRelated: String {
            switch self {
            case .warmPaper: return "3A332B"
            case .mintFog: return "243A35"
            case .blueGray: return "273845"
            case .sepiaCalm: return "413428"
            case .sageSlate: return "2A3B34"
            case .quietSlate: return "374659"
            case .mellowOlive: return "405035"
            }
        }
    }

    @AppStorage("backgroundColorHex") private var backgroundColorHex: String = "F4F2EE"
    @AppStorage("darkBackgroundColorHex") private var darkBackgroundColorHex: String = "111418"
    @AppStorage("cardBaseColorHex") private var cardBaseColorHex: String = "FFFFFF"
    @AppStorage("cardActiveColorHex") private var cardActiveColorHex: String = "BFD7FF"
    @AppStorage("cardRelatedColorHex") private var cardRelatedColorHex: String = "DDE9FF"
    @AppStorage("darkCardBaseColorHex") private var darkCardBaseColorHex: String = "1A2029"
    @AppStorage("darkCardActiveColorHex") private var darkCardActiveColorHex: String = "2A3A4E"
    @AppStorage("darkCardRelatedColorHex") private var darkCardRelatedColorHex: String = "242F3F"
    @AppStorage("storageBookmark") private var storageBookmark: Data?
    @AppStorage("forceWorkspaceReset") private var forceWorkspaceReset: Bool = false
    @AppStorage("exportCenteredFontSize") private var exportCenteredFontSize: Double = 12.0
    @AppStorage("exportCenteredCharacterBold") private var exportCenteredCharacterBold: Bool = true
    @AppStorage("exportCenteredSceneHeadingBold") private var exportCenteredSceneHeadingBold: Bool = true
    @AppStorage("exportCenteredShowRightSceneNumber") private var exportCenteredShowRightSceneNumber: Bool = false
    @AppStorage("exportKoreanFontSize") private var exportKoreanFontSize: Double = 11.0
    @AppStorage("exportKoreanSceneBold") private var exportKoreanSceneBold: Bool = true
    @AppStorage("exportKoreanCharacterBold") private var exportKoreanCharacterBold: Bool = true
    @AppStorage("exportKoreanCharacterAlignment") private var exportKoreanCharacterAlignment: String = "right"
    @AppStorage("focusTypewriterEnabled") private var focusTypewriterEnabled: Bool = false
    @AppStorage("focusTypewriterBaseline") private var focusTypewriterBaseline: Double = 0.60
    @AppStorage("mainCardLineSpacingValueV2") private var mainCardLineSpacingValue: Double = 5.0
    @AppStorage("mainCardVerticalGap") private var mainCardVerticalGap: Double = 0.0
    @AppStorage("focusModeLineSpacingValueTemp") private var focusModeLineSpacingValue: Double = 4.5
    @AppStorage("geminiModelID") private var geminiModelID: String = "gemini-3-pro-preview"
    @AppStorage("whisperInstallRootPath") private var whisperInstallRootPathStorage: String = ""
    @AppStorage("whisperCLIPath") private var whisperCLIPathStorage: String = ""
    @AppStorage("whisperModelPath") private var whisperModelPathStorage: String = ""

    @State private var geminiAPIKeyInput: String = ""
    @State private var hasGeminiAPIKey: Bool = false
    @State private var aiSettingsStatusMessage: String? = nil
    @State private var aiSettingsStatusIsError: Bool = false
    @State private var selectedColorThemePreset: ColorThemePreset = .warmPaper
    @State private var selectedGeminiModelOption: String = "gemini-3-pro-preview"
    @State private var whisperInstallRootInput: String = ""
    @State private var whisperCLIPathInput: String = ""
    @State private var whisperModelPathInput: String = ""
    @State private var whisperStatusMessage: String? = nil
    @State private var whisperStatusIsError: Bool = false
    @State private var whisperIsInstalled: Bool = false
    @State private var whisperIsInstalling: Bool = false

    private let customGeminiModelToken = "__custom__"
    private let geminiModelOptions: [GeminiModelOption] = [
        GeminiModelOption(value: "gemini-3-pro-preview", title: "Gemini 3 Pro (Preview)"),
        GeminiModelOption(value: "gemini-3-flash", title: "Gemini 3 Flash"),
        GeminiModelOption(value: "gemini-2.5-pro", title: "Gemini 2.5 Pro"),
        GeminiModelOption(value: "gemini-2.5-flash", title: "Gemini 2.5 Flash"),
        GeminiModelOption(value: "gemini-2.0-flash", title: "Gemini 2.0 Flash")
    ]
    private let oflFontFiles: [String] = [
        "Sans Mono CJK Final Draft.otf",
        "Sans Mono CJK Final Draft Bold.otf"
    ]
    private let oflLicenseURL = URL(string: "https://openfontlicense.org/open-font-license-official-text/")!
    
    var onUpdateStore: () -> Void
    
    private var currentStoragePath: String {
        guard let bookmark = storageBookmark else { return "설정되지 않음" }
        var isStale = false
        if let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
            return url.path
        }
        return "알 수 없는 경로"
    }

    private var shortcutSections: [ShortcutSection] {
        [
            ShortcutSection(
                title: "공통",
                items: [
                    ShortcutItem(keys: "Cmd + Z", action: "실행 취소"),
                    ShortcutItem(keys: "Cmd + Shift + Z", action: "다시 실행"),
                    ShortcutItem(keys: "Cmd + Shift + F", action: "포커스 모드 토글"),
                    ShortcutItem(keys: "Cmd + F", action: "검색창 열기/닫기"),
                    ShortcutItem(keys: "Cmd + Shift + ]", action: "전체 카드(타임라인) 패널 토글")
                ]
            ),
            ShortcutSection(
                title: "메인 작업 모드",
                items: [
                    ShortcutItem(keys: "Arrow ↑ ↓ ← →", action: "카드 이동"),
                    ShortcutItem(keys: "Right (자식 없음 시 빠르게 2회)", action: "인접 부모의 자식 카드로 점프"),
                    ShortcutItem(keys: "Return", action: "선택 카드 편집 시작"),
                    ShortcutItem(keys: "Esc", action: "편집/검색 종료 (상황별)"),
                    ShortcutItem(keys: "Tab + Tab (편집 중)", action: "자식 카드 추가 후 바로 편집"),
                    ShortcutItem(keys: "Tab", action: "자식 카드 추가"),
                    ShortcutItem(keys: "Cmd + ↑", action: "위에 형제 카드 추가"),
                    ShortcutItem(keys: "Cmd + ↓", action: "아래에 형제 카드 추가"),
                    ShortcutItem(keys: "Cmd + Return", action: "편집 종료 후 아래에 형제 카드 추가"),
                    ShortcutItem(keys: "Cmd + →", action: "자식 카드 추가"),
                    ShortcutItem(keys: "Cmd + Shift + Delete", action: "선택 카드(또는 선택 묶음) 삭제"),
                    ShortcutItem(keys: "Cmd + Shift + Arrow", action: "카드 계층 이동(상/하/좌/우)")
                ]
            ),
            ShortcutSection(
                title: "포커스 모드",
                items: [
                    ShortcutItem(keys: "Arrow ↑ / ↓", action: "경계에서 이전/다음 카드로 이동"),
                    ShortcutItem(keys: "Cmd + Shift + T", action: "타이프라이터 모드 토글"),
                    ShortcutItem(keys: "Cmd + Return", action: "아래에 형제 카드 추가"),
                    ShortcutItem(keys: "Cmd + Option + ↑ / ↓", action: "위/아래 형제 카드 추가"),
                    ShortcutItem(keys: "Cmd + Shift + Delete", action: "현재 카드 삭제")
                ]
            ),
            ShortcutSection(
                title: "히스토리 모드",
                items: [
                    ShortcutItem(keys: "Arrow ← / →", action: "타임라인 이전/다음 시점 이동"),
                    ShortcutItem(keys: "Cmd + Arrow ← / →", action: "이전/다음 네임드 스냅샷 이동"),
                    ShortcutItem(keys: "Esc", action: "검색 포커스 해제/노트 편집 종료/히스토리 닫기")
                ]
            )
        ]
    }

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case settings
        case shortcuts

        var id: String { rawValue }
    }

    @State private var selectedSettingsTab: SettingsTab = .settings

    private enum SettingsLayout {
        static let windowWidth: CGFloat = 1120
        static let windowHeight: CGFloat = 700
        static let contentPadding: CGFloat = 12
        static let columnSpacing: CGFloat = 10
        static let cardSpacing: CGFloat = 12
        static let cardContentSpacing: CGFloat = 6
        static let cardPadding: CGFloat = 10
        static let cardCornerRadius: CGFloat = 12
        static let titleCornerRadius: CGFloat = 8
        static let cardTitleFontSize: CGFloat = 14
    }

    private var shortcutLeftSections: [ShortcutSection] {
        Array(shortcutSections.prefix(2))
    }

    private var shortcutRightSections: [ShortcutSection] {
        Array(shortcutSections.dropFirst(2))
    }

    private var oflLicenseText: String {
        """
        SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007

        PREAMBLE
        The goals of the Open Font License (OFL) are to stimulate worldwide development
        of collaborative font projects, to support the font creation efforts of academic
        and linguistic communities, and to provide a free and open framework in which
        fonts may be shared and improved in partnership with others.

        The OFL allows the licensed fonts to be used, studied, modified and redistributed
        freely as long as they are not sold by themselves. The fonts, including any
        derivative works, can be bundled, embedded, redistributed and/or sold with any
        software provided that any reserved names are not used by derivative works. The
        fonts and derivatives, however, cannot be released under any other type of
        license. The requirement for fonts to remain under this license does not apply
        to any document created using the fonts or their derivatives.

        DEFINITIONS
        "Font Software" refers to the set of files released by the Copyright Holder(s)
        under this license and clearly marked as such. This may include source files,
        build scripts and documentation.

        "Reserved Font Name" refers to any names specified as such after the copyright
        statement(s).

        "Original Version" refers to the collection of Font Software components as
        distributed by the Copyright Holder(s).

        "Modified Version" refers to any derivative made by adding to, deleting, or
        substituting -- in part or in whole -- any of the components of the Original
        Version, by changing formats or by porting the Font Software to a new environment.

        "Author" refers to any designer, engineer, programmer, technical writer or other
        person who contributed to the Font Software.

        PERMISSION & CONDITIONS
        Permission is hereby granted, free of charge, to any person obtaining a copy
        of the Font Software, to use, study, copy, merge, embed, modify, redistribute,
        and sell modified and unmodified copies of the Font Software, subject to the
        following conditions:

        1) Neither the Font Software nor any of its individual components, in Original
           or Modified Versions, may be sold by itself.

        2) Original or Modified Versions of the Font Software may be bundled,
           redistributed and/or sold with any software, provided that each copy contains
           the above copyright notice and this license. These can be included either as
           stand-alone text files, human-readable headers or in the appropriate
           machine-readable metadata fields within text or binary files as long as those
           fields can be easily viewed by the user.

        3) No Modified Version of the Font Software may use the Reserved Font Name(s)
           unless explicit written permission is granted by the corresponding Copyright
           Holder. This restriction only applies to the primary font name as presented
           to the users.

        4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font Software
           shall not be used to promote, endorse or advertise any Modified Version,
           except to acknowledge the contribution(s) of the Copyright Holder(s) and the
           Author(s) or with their explicit written permission.

        5) The Font Software, modified or unmodified, in part or in whole, must be
           distributed entirely under this license, and must not be distributed under any
           other license. The requirement for fonts to remain under this license does not
           apply to any document created using the Font Software.

        TERMINATION
        This license becomes null and void if any of the above conditions are not met.

        DISCLAIMER
        THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF MERCHANTABILITY, FITNESS
        FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF COPYRIGHT, PATENT, TRADEMARK, OR
        OTHER RIGHT. IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM,
        DAMAGES OR OTHER LIABILITY, INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL,
        OR CONSEQUENTIAL DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
        ARISING FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM OTHER
        DEALINGS IN THE FONT SOFTWARE.
        """
    }

    @ViewBuilder
    private func oflFontLicenseCard() -> some View {
        settingsCard(title: "폰트 라이선스 (OFL)") {
            Text("앱에 포함된 아래 폰트 파일은 SIL Open Font License 1.1 조건으로 배포됩니다.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(oflFontFiles, id: \.self) { fileName in
                    Text(fileName)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            Link("OFL 공식 전문 열기", destination: oflLicenseURL)
                .font(.system(size: 11))

            DisclosureGroup("라이선스 전문 보기") {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(oflLicenseText)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 130, maxHeight: 220)
                .padding(.top, 4)
            }
            .font(.system(size: 11))
        }
    }

    var body: some View {
        TabView(selection: $selectedSettingsTab) {
            threeColumnContent(
                first: {
                    settingsCard(title: "편집기 설정") {
                        Text("메인 모드 행간 (임시): \(String(format: "%.2f", mainCardLineSpacingValue))")
                        Slider(value: $mainCardLineSpacingValue, in: 1.0...8.0, step: 0.05)

                        Text("카드 위아래 간격: \(Int(mainCardVerticalGap.rounded()))")
                        Slider(value: $mainCardVerticalGap, in: 0.0...28.0, step: 1.0)
                        Text("기본값은 0이며, 필요할 때만 행 간격을 넓혀 보이게 합니다.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)

                        Text("포커스 모드 행간 (임시): \(String(format: "%.2f", focusModeLineSpacingValue))")
                        Slider(value: $focusModeLineSpacingValue, in: 0.0...6.0, step: 0.05)
                    }

                    settingsCard(title: "포커스 모드 설정") {
                        Text("타이프라이터 토글은 상단 메뉴 > 화면에서 변경합니다.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)

                        Picker("타이프라이터 기준선", selection: $focusTypewriterBaseline) {
                            Text("중앙 50%").tag(0.50)
                            Text("기본 60%").tag(0.60)
                            Text("아래 66%").tag(0.66)
                        }
                        .pickerStyle(.segmented)
                        .disabled(!focusTypewriterEnabled)

                        Text(focusTypewriterEnabled ? "현재 타이프라이터 모드가 켜져 있습니다." : "현재 타이프라이터 모드가 꺼져 있습니다.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    settingsCard(title: "데이터 저장소") {
                        Text("현재 저장 경로:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(currentStoragePath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)

                        Button("기존 작업 파일 열기...") {
                            openWorkspaceFile()
                        }

                        Button("새 작업 파일 만들기...") {
                            createWorkspaceFile()
                        }

                        Button("작업 파일 초기화 (다시 선택)") {
                            storageBookmark = nil
                            forceWorkspaceReset = true
                        }
                    }

                    oflFontLicenseCard()
                },
                second: {
                    settingsCard(title: "출력 설정") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("중앙정렬식 PDF")
                                .font(.subheadline.weight(.semibold))
                            Text("폰트 크기: \(String(format: "%.1f", exportCenteredFontSize))pt")
                            Slider(value: $exportCenteredFontSize, in: 8...20, step: 0.5)
                            Toggle("헤딩 볼드", isOn: $exportCenteredSceneHeadingBold)
                            Toggle("캐릭터 볼드", isOn: $exportCenteredCharacterBold)
                            Toggle("오른쪽 씬 번호 표시", isOn: $exportCenteredShowRightSceneNumber)

                            Divider()

                            Text("한국식 PDF")
                                .font(.subheadline.weight(.semibold))
                            Text("폰트 크기: \(String(format: "%.1f", exportKoreanFontSize))pt")
                            Slider(value: $exportKoreanFontSize, in: 8...20, step: 0.5)
                            Toggle("씬 헤딩 볼드", isOn: $exportKoreanSceneBold)
                            Toggle("캐릭터 볼드", isOn: $exportKoreanCharacterBold)
                            Picker("캐릭터 정렬", selection: $exportKoreanCharacterAlignment) {
                                Text("오른쪽").tag("right")
                                Text("왼쪽").tag("left")
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    settingsCard(title: "AI 설정") {
                        Text("Gemini 모델")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("모델 선택", selection: $selectedGeminiModelOption) {
                            ForEach(geminiModelOptions) { option in
                                Text(option.title).tag(option.value)
                            }
                            Text("직접 입력").tag(customGeminiModelToken)
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedGeminiModelOption) { _, newValue in
                            guard newValue != customGeminiModelToken else { return }
                            geminiModelID = newValue
                        }

                        TextField("예: gemini-3-pro-preview", text: $geminiModelID)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: geminiModelID) { _, _ in
                                syncGeminiModelOptionSelection()
                            }

                        Text("Gemini 3 Pro의 API 모델 ID는 gemini-3-pro-preview 입니다. 404가 뜨면 상단 메뉴에서 다른 모델을 선택하세요.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(2)

                        Text("Gemini API 키")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SecureField(hasGeminiAPIKey ? "새 키를 입력하면 덮어씁니다" : "API 키 입력", text: $geminiAPIKeyInput)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 8) {
                            Button(hasGeminiAPIKey ? "키 업데이트" : "키 저장") {
                                saveGeminiAPIKey()
                            }
                            .disabled(geminiAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button("키 삭제", role: .destructive) {
                                deleteGeminiAPIKey()
                            }
                            .disabled(!hasGeminiAPIKey)
                        }

                        Text(hasGeminiAPIKey ? "현재 API 키가 저장되어 있습니다." : "현재 저장된 API 키가 없습니다.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(2)

                        if let message = aiSettingsStatusMessage {
                            Text(message)
                                .font(.system(size: 11))
                                .foregroundColor(aiSettingsStatusIsError ? .red : .secondary)
                                .lineLimit(2)
                        }
                    }
                },
                third: {
                    settingsCard(title: "Whisper 받아쓰기") {
                        Text("로컬 whisper.cpp 엔진을 사용합니다. 다른 Mac에서는 자동 설치로 CLI/모델을 한 번에 준비할 수 있습니다.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(2)

                        TextField("설치 루트 경로", text: $whisperInstallRootInput)
                            .textFieldStyle(.roundedBorder)

                        TextField("whisper-cli 경로", text: $whisperCLIPathInput)
                            .textFieldStyle(.roundedBorder)

                        TextField("모델 경로 (.bin)", text: $whisperModelPathInput)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 8) {
                            Button("경로 저장") {
                                saveWhisperPathSettings(statusMessage: "Whisper 경로를 저장했습니다.")
                                refreshWhisperStatusFromInputs()
                            }
                            .disabled(whisperIsInstalling)

                            Button("기본 경로 채우기") {
                                fillWhisperDefaultPaths()
                                setWhisperStatus("Whisper 기본 경로를 채웠습니다.", isError: false)
                            }
                            .disabled(whisperIsInstalling)
                        }

                        HStack(spacing: 8) {
                            Button("설치 상태 확인") {
                                refreshWhisperStatusFromInputs()
                            }
                            .disabled(whisperIsInstalling)

                            Button("자동 설치 / 업데이트") {
                                installOrUpdateWhisper()
                            }
                            .disabled(whisperIsInstalling)

                            if whisperIsInstalling {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        Text(whisperIsInstalled ? "현재 Whisper 받아쓰기 사용 가능" : "현재 Whisper 설치 또는 경로 확인이 필요합니다.")
                            .font(.system(size: 11))
                            .foregroundColor(whisperIsInstalled ? .secondary : .orange)
                            .lineLimit(2)

                        if let message = whisperStatusMessage {
                            Text(message)
                                .font(.system(size: 11))
                                .foregroundColor(whisperStatusIsError ? .red : .secondary)
                                .lineLimit(2)
                        }
                    }

                    settingsCard(title: "색상 테마 프리셋") {
                        Picker("프리셋", selection: $selectedColorThemePreset) {
                            ForEach(ColorThemePreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)

                        Button("선택한 프리셋 적용") {
                            applyColorThemePreset(selectedColorThemePreset)
                        }

                        Text("라이트/다크 모드는 그대로 유지하며 카드/배경 색 팔레트만 교체합니다.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    settingsCard(title: "색상 설정") {
                        themedColorPickerRow(
                            title: "앱 배경 색",
                            lightHex: $backgroundColorHex,
                            darkHex: $darkBackgroundColorHex,
                            lightFallback: Color(red: 0.96, green: 0.95, blue: 0.93),
                            darkFallback: Color(red: 0.07, green: 0.08, blue: 0.10)
                        )
                        themedColorPickerRow(
                            title: "카드 기본 색",
                            lightHex: $cardBaseColorHex,
                            darkHex: $darkCardBaseColorHex,
                            lightFallback: Color.white,
                            darkFallback: Color(red: 0.10, green: 0.13, blue: 0.16)
                        )
                        themedColorPickerRow(
                            title: "선택 카드 색",
                            lightHex: $cardActiveColorHex,
                            darkHex: $darkCardActiveColorHex,
                            lightFallback: Color(red: 0.75, green: 0.84, blue: 1.0),
                            darkFallback: Color(red: 0.16, green: 0.23, blue: 0.31)
                        )
                        themedColorPickerRow(
                            title: "연결 카드 색",
                            lightHex: $cardRelatedColorHex,
                            darkHex: $darkCardRelatedColorHex,
                            lightFallback: Color(red: 0.87, green: 0.92, blue: 1.0),
                            darkFallback: Color(red: 0.14, green: 0.18, blue: 0.25)
                        )
                    }

                    settingsCard(title: "색상 초기화") {
                        Button("카드/배경 색 기본값으로") { resetColorsToDefaults() }
                    }
                }
            )
            .padding(SettingsLayout.contentPadding)
            .controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .tabItem { Label("설정", systemImage: "gearshape.2") }
            .tag(SettingsTab.settings)

            twoColumnContent(
                left: {
                    ForEach(shortcutLeftSections) { section in
                        settingsCard(title: section.title) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(section.items) { item in
                                    shortcutRow(item)
                                }
                            }
                        }
                    }
                },
                right: {
                    ForEach(shortcutRightSections) { section in
                        settingsCard(title: section.title) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(section.items) { item in
                                    shortcutRow(item)
                                }
                            }
                        }
                    }
                }
            )
            .padding(SettingsLayout.contentPadding)
            .controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .tabItem { Label("단축키", systemImage: "keyboard") }
            .tag(SettingsTab.shortcuts)
        }
        .frame(width: SettingsLayout.windowWidth, height: SettingsLayout.windowHeight)
        .onAppear {
            refreshGeminiAPIKeyStatus()
            syncGeminiModelOptionSelection()
            loadWhisperPathInputsFromResolvedConfig()
            refreshWhisperStatusFromInputs()
        }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SettingsLayout.cardContentSpacing) {
            Text(title)
                .font(.system(size: SettingsLayout.cardTitleFontSize, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: SettingsLayout.titleCornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                )

            VStack(alignment: .leading, spacing: SettingsLayout.cardContentSpacing) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(SettingsLayout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: SettingsLayout.cardCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsLayout.cardCornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func threeColumnContent<First: View, Second: View, Third: View>(
        @ViewBuilder first: () -> First,
        @ViewBuilder second: () -> Second,
        @ViewBuilder third: () -> Third
    ) -> some View {
        HStack(alignment: .top, spacing: SettingsLayout.columnSpacing) {
            VStack(alignment: .leading, spacing: SettingsLayout.cardSpacing) {
                first()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: SettingsLayout.cardSpacing) {
                second()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: SettingsLayout.cardSpacing) {
                third()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func twoColumnContent<Left: View, Right: View>(
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) -> some View {
        HStack(alignment: .top, spacing: SettingsLayout.columnSpacing) {
            VStack(alignment: .leading, spacing: SettingsLayout.cardSpacing) {
                left()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: SettingsLayout.cardSpacing) {
                right()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func shortcutRow(_ item: ShortcutItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.action)
                .font(.system(size: 11))
                .lineLimit(2)
            Spacer(minLength: 8)
            Text(item.keys)
                .font(.system(size: 10, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func colorBinding(hex: Binding<String>, fallback: Color) -> Binding<Color> {
        Binding(
            get: { colorFromHex(hex.wrappedValue) ?? fallback },
            set: { newColor in
                hex.wrappedValue = hexFromColor(newColor)
            }
        )
    }

    @ViewBuilder
    private func themedColorPickerRow(
        title: String,
        lightHex: Binding<String>,
        darkHex: Binding<String>,
        lightFallback: Color,
        darkFallback: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 10) {
                ColorPicker(
                    "라이트",
                    selection: colorBinding(hex: lightHex, fallback: lightFallback)
                )
                ColorPicker(
                    "다크",
                    selection: colorBinding(hex: darkHex, fallback: darkFallback)
                )
            }
        }
    }

    private func colorFromHex(_ hex: String) -> Color? {
        var hexValue = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if hexValue.hasPrefix("#") { hexValue.removeFirst() }
        guard hexValue.count == 6, let intVal = Int(hexValue, radix: 16) else { return nil }
        let r = Double((intVal >> 16) & 0xFF) / 255.0
        let g = Double((intVal >> 8) & 0xFF) / 255.0
        let b = Double(intVal & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    private func hexFromColor(_ color: Color) -> String {
        let ns = NSColor(color)
        let rgb = ns.usingColorSpace(.deviceRGB) ?? ns
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "%02X%02X%02X", r, g, b)
    }

    private func resetColorsToDefaults() {
        backgroundColorHex = "F4F2EE"
        darkBackgroundColorHex = "111418"
        cardBaseColorHex = "FFFFFF"
        cardActiveColorHex = "BFD7FF"
        cardRelatedColorHex = "DDE9FF"
        darkCardBaseColorHex = "1A2029"
        darkCardActiveColorHex = "2A3A4E"
        darkCardRelatedColorHex = "242F3F"
    }

    private func applyColorThemePreset(_ preset: ColorThemePreset) {
        backgroundColorHex = preset.lightBackground
        darkBackgroundColorHex = preset.darkBackground
        cardBaseColorHex = preset.lightCardBase
        cardActiveColorHex = preset.lightCardActive
        cardRelatedColorHex = preset.lightCardRelated
        darkCardBaseColorHex = preset.darkCardBase
        darkCardActiveColorHex = preset.darkCardActive
        darkCardRelatedColorHex = preset.darkCardRelated
    }

    private func syncGeminiModelOptionSelection() {
        let normalized = normalizeGeminiModelID(geminiModelID)
        if normalized != geminiModelID {
            geminiModelID = normalized
        }
        let trimmedModel = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        if geminiModelOptions.contains(where: { $0.value == trimmedModel }) {
            selectedGeminiModelOption = trimmedModel
        } else {
            selectedGeminiModelOption = customGeminiModelToken
        }
    }

    private func normalizeGeminiModelID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        switch lowered {
        case "gemini-3-pro", "gemini-3.0-pro", "gemini-3-pro-latest":
            return "gemini-3-pro-preview"
        case "gemini-3-flash-latest":
            return "gemini-3-flash"
        default:
            return trimmed
        }
    }

    private func refreshGeminiAPIKeyStatus() {
        do {
            hasGeminiAPIKey = try KeychainStore.loadGeminiAPIKey() != nil
        } catch {
            hasGeminiAPIKey = false
            setAISettingsStatus(error.localizedDescription, isError: true)
        }
    }

    private func saveGeminiAPIKey() {
        let trimmed = geminiAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setAISettingsStatus("저장할 API 키를 입력해 주세요.", isError: true)
            return
        }
        do {
            try KeychainStore.saveGeminiAPIKey(trimmed)
            geminiAPIKeyInput = ""
            refreshGeminiAPIKeyStatus()
            setAISettingsStatus("Gemini API 키를 저장했습니다.", isError: false)
        } catch {
            setAISettingsStatus(error.localizedDescription, isError: true)
        }
    }

    private func deleteGeminiAPIKey() {
        do {
            try KeychainStore.deleteGeminiAPIKey()
            geminiAPIKeyInput = ""
            refreshGeminiAPIKeyStatus()
            setAISettingsStatus("저장된 Gemini API 키를 삭제했습니다.", isError: false)
        } catch {
            setAISettingsStatus(error.localizedDescription, isError: true)
        }
    }

    private func setAISettingsStatus(_ message: String, isError: Bool) {
        aiSettingsStatusMessage = message
        aiSettingsStatusIsError = isError
    }

    private func loadWhisperPathInputsFromResolvedConfig() {
        let resolved = WhisperConfiguration.resolvedPaths()
        whisperInstallRootInput = resolved.installRootPath
        whisperCLIPathInput = resolved.cliPath
        whisperModelPathInput = resolved.modelPath
        whisperInstallRootPathStorage = resolved.installRootPath
        whisperCLIPathStorage = resolved.cliPath
        whisperModelPathStorage = resolved.modelPath
    }

    private func fillWhisperDefaultPaths() {
        let baseRoot = whisperInstallRootInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedRoot = baseRoot.isEmpty ? WhisperConfiguration.defaultInstallRootPath() : baseRoot
        let defaultsForRoot = WhisperConfiguration.paths(forInstallRoot: resolvedRoot)
        whisperInstallRootInput = defaultsForRoot.installRootPath
        whisperCLIPathInput = defaultsForRoot.cliPath
        whisperModelPathInput = defaultsForRoot.modelPath
    }

    private func resolvedWhisperPathsFromInputs() -> WhisperPaths {
        let trimmedRoot = whisperInstallRootInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCLI = whisperCLIPathInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = whisperModelPathInput.trimmingCharacters(in: .whitespacesAndNewlines)

        let inferredRoot =
            !trimmedRoot.isEmpty
            ? trimmedRoot
            : (WhisperConfiguration.inferInstallRoot(cliPath: trimmedCLI, modelPath: trimmedModel)
                ?? WhisperConfiguration.defaultInstallRootPath())

        let defaultsForRoot = WhisperConfiguration.paths(forInstallRoot: inferredRoot)
        return WhisperPaths(
            installRootPath: inferredRoot,
            cliPath: trimmedCLI.isEmpty ? defaultsForRoot.cliPath : trimmedCLI,
            modelPath: trimmedModel.isEmpty ? defaultsForRoot.modelPath : trimmedModel
        )
    }

    private func saveWhisperPathSettings(statusMessage: String?) {
        let resolved = resolvedWhisperPathsFromInputs()
        WhisperConfiguration.save(paths: resolved)
        whisperInstallRootPathStorage = resolved.installRootPath
        whisperCLIPathStorage = resolved.cliPath
        whisperModelPathStorage = resolved.modelPath
        whisperInstallRootInput = resolved.installRootPath
        whisperCLIPathInput = resolved.cliPath
        whisperModelPathInput = resolved.modelPath
        if let statusMessage {
            setWhisperStatus(statusMessage, isError: false)
        }
    }

    private func refreshWhisperStatusFromInputs() {
        let resolved = resolvedWhisperPathsFromInputs()
        let status = WhisperInstallService.inspectEnvironment(paths: resolved)
        whisperIsInstalled = status.isReady
        setWhisperStatus(status.message, isError: !status.isReady)
    }

    private func installOrUpdateWhisper() {
        guard !whisperIsInstalling else { return }

        whisperIsInstalling = true
        setWhisperStatus("Whisper 자동 설치를 시작합니다...", isError: false)

        let targetRoot = resolvedWhisperPathsFromInputs().installRootPath
        Task {
            do {
                let installed = try await WhisperInstallService.installOrUpdate(
                    installRootPath: targetRoot,
                    progress: { message in
                        Task { @MainActor in
                            setWhisperStatus(message, isError: false)
                        }
                    }
                )
                await MainActor.run {
                    whisperIsInstalling = false
                    whisperInstallRootInput = installed.installRootPath
                    whisperCLIPathInput = installed.cliPath
                    whisperModelPathInput = installed.modelPath
                    saveWhisperPathSettings(statusMessage: "Whisper 설치 및 설정이 완료되었습니다.")
                    refreshWhisperStatusFromInputs()
                }
            } catch {
                await MainActor.run {
                    whisperIsInstalling = false
                    whisperIsInstalled = false
                    setWhisperStatus(error.localizedDescription, isError: true)
                }
            }
        }
    }

    private func setWhisperStatus(_ message: String, isError: Bool) {
        whisperStatusMessage = message
        whisperStatusIsError = isError
    }

    private func openWorkspaceFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.item]
        panel.message = "기존 작업 파일(.wtf)을 선택하세요."
        
        if panel.runModal() == .OK, let chosenURL = panel.url {
            guard chosenURL.pathExtension.lowercased() == "wtf" else { return }
            var url = chosenURL
            do {
                var values = URLResourceValues()
                values.isPackage = true
                try? url.setResourceValues(values)
                let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                storageBookmark = bookmark
                onUpdateStore()
            } catch {
                // Logging intentionally muted.
            }
        }
    }

    private func createWorkspaceFile() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.waWorkspace]
        panel.nameFieldStringValue = "workspace.wtf"
        panel.isExtensionHidden = false
        
        if panel.runModal() == .OK, let chosenURL = panel.url {
            var url = chosenURL.pathExtension.lowercased() == "wtf" ? chosenURL : chosenURL.appendingPathExtension("wtf")
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                var values = URLResourceValues()
                values.isPackage = true
                try? url.setResourceValues(values)
                let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                storageBookmark = bookmark
                onUpdateStore()
            } catch {
                // Logging intentionally muted.
            }
        }
    }
}

struct MainContainerView: View {
    private enum ScenarioCreationMode: String, CaseIterable, Identifiable {
        case clean
        case template

        var id: String { rawValue }
    }

    @EnvironmentObject private var store: FileStore
    @Environment(\.openWindow) private var openWindow
    @AppStorage("storageBookmark") private var storageBookmark: Data?
    @AppStorage("mainSplitModeEnabled") private var mainSplitModeEnabled: Bool = false
    @AppStorage("lastSelectedScenarioID") private var lastSelectedScenarioID: String = ""
    @State private var selectedScenario: Scenario?
    @State private var editingScenario: Scenario?
    @State private var newTitle: String = ""
    @State private var isSidebarVisible: Bool = true
    @State private var sidebarOpenedFromToggle: Bool = false
    @State private var showNewScenarioDialog: Bool = false
    @State private var newScenarioName: String = ""
    @State private var scenarioCreationMode: ScenarioCreationMode = .clean
    @State private var selectedTemplateScenarioID: UUID? = nil
    @State private var pendingAutoHideWorkItem: DispatchWorkItem?
    @State private var activeSplitPaneID: Int = 2
    @State private var sidebarEscapeMonitor: Any?
    @State private var isMainWindowFullscreen: Bool = false
    
    @FocusState private var isNameFocused: Bool
    
    private var currentWorkspaceName: String {
        guard let bookmark = storageBookmark else { return "작업 파일 없음" }
        var isStale = false
        if let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
            return url.lastPathComponent
        }
        return "작업 파일 없음"
    }

    private var templateScenarios: [Scenario] {
        store.scenarios.filter { $0.isTemplate }
    }

    private var sidebarToggleLeadingPadding: CGFloat {
        isMainWindowFullscreen ? 14 : 86
    }

    private var sidebarToggleTopPadding: CGFloat {
        isMainWindowFullscreen ? 14 : -30
    }

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                sidebarPanel
                    .frame(width: 296)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Group {
                if let scenario = selectedScenario {
                    scenarioDetailView(for: scenario)
                } else {
                    ContentUnavailableView("시나리오를 선택하세요", systemImage: "pencil.and.outline")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if isSidebarVisible && sidebarOpenedFromToggle {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            closeToggleOpenedSidebar()
                        }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if !isSidebarVisible {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        sidebarOpenedFromToggle = true
                        isSidebarVisible = true
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.leading, sidebarToggleLeadingPadding)
                .padding(.top, sidebarToggleTopPadding)
            }
        }
        .animation(.easeOut(duration: 0.18), value: isSidebarVisible)
        .ignoresSafeArea(.container, edges: [.leading, .trailing, .bottom])
        .sheet(isPresented: $showNewScenarioDialog) {
            VStack(alignment: .leading, spacing: 14) {
                Text("새 시나리오 만들기")
                    .font(.headline)

                TextField("시나리오 이름", text: $newScenarioName)
                    .textFieldStyle(.roundedBorder)

                Picker("생성 방식", selection: $scenarioCreationMode) {
                    Text("클린 시나리오").tag(ScenarioCreationMode.clean)
                    Text("템플릿에서 생성").tag(ScenarioCreationMode.template)
                }
                .pickerStyle(.segmented)

                if scenarioCreationMode == .template {
                    if templateScenarios.isEmpty {
                        Text("사용 가능한 템플릿이 없습니다. 먼저 시나리오를 템플릿으로 만드세요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("템플릿 선택", selection: $selectedTemplateScenarioID) {
                            ForEach(templateScenarios) { template in
                                Text(template.title.isEmpty ? "제목 없음" : template.title)
                                    .tag(Optional(template.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                HStack {
                    Spacer()
                    Button("취소", role: .cancel) {
                        showNewScenarioDialog = false
                    }
                    Button("생성") {
                        createScenarioFromDialog()
                    }
                    .disabled(scenarioCreationMode == .template && selectedTemplateScenarioID == nil)
                }
            }
            .padding(20)
            .frame(width: 420)
        }
        .onChange(of: selectedScenario) { _, newValue in
            guard newValue != nil else { return }
            if let scenario = newValue {
                lastSelectedScenarioID = scenario.id.uuidString
            }
            sidebarOpenedFromToggle = false
            scheduleAutoHideSidebar()
        }
        .onAppear {
            restoreSelectedScenarioIfNeeded()
            startSidebarEscapeMonitor()
            refreshMainWindowFullscreenState()
        }
        .onChange(of: store.scenarios.map(\.id)) { _, _ in
            restoreSelectedScenarioIfNeeded()
        }
        .onDisappear {
            stopSidebarEscapeMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            refreshMainWindowFullscreenState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            refreshMainWindowFullscreenState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeMainNotification)) { _ in
            refreshMainWindowFullscreenState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refreshMainWindowFullscreenState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshMainWindowFullscreenState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .waOpenReferenceWindowRequested)) { _ in
            openWindow(id: ReferenceWindowConstants.windowID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .waCycleSplitPaneRequested)) { _ in
            guard mainSplitModeEnabled else { return }
            activeSplitPaneID = (activeSplitPaneID == 1) ? 2 : 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .waSplitPaneActivateRequested)) { notification in
            guard mainSplitModeEnabled else { return }
            guard let paneID = notification.object as? Int else { return }
            activeSplitPaneID = (paneID == 1) ? 1 : 2
        }
        .onChange(of: mainSplitModeEnabled) { _, enabled in
            if enabled {
                if activeSplitPaneID != 1 && activeSplitPaneID != 2 {
                    activeSplitPaneID = 2
                }
                requestSplitPaneFocus(activeSplitPaneID)
            }
        }
    }

    private var sidebarPanel: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selectedScenario) {
                    ForEach(store.scenarios) { scenario in
                        if editingScenario == scenario {
                            TextField("제목 입력", text: $newTitle)
                                .font(.custom("SansMonoCJKFinalDraft", size: 18))
                                .focused($isNameFocused)
                                .onSubmit {
                                    finishEditingTitle(scenario)
                                }
                                .onAppear {
                                    isNameFocused = true
                                }
                        } else {
                            ScenarioRow(
                                scenario: scenario,
                                onRename: { startEditing(scenario) },
                                onDelete: { deleteScenario(scenario) },
                                onMakeTemplate: { makeTemplate(from: scenario) }
                            )
                            .tag(scenario)
                        }
                    }
                }
                .padding(.top, 26)
                .background(Color(NSColor.controlBackgroundColor))
                
                VStack(spacing: 0) {
                    Divider()
                    Button(action: {
                        newScenarioName = ""
                        scenarioCreationMode = .clean
                        selectedTemplateScenarioID = templateScenarios.first?.id
                        showNewScenarioDialog = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("새 시나리오 추가").fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(0)
                    }
                    .buttonStyle(.plain)
                    .padding()
                    
                    Button(action: openWorkspaceFromSidebar) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text(currentWorkspaceName)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 10)
                        .foregroundStyle(.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(NSColor.windowBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func createScenarioFromDialog() {
        let trimmed = newScenarioName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "제목 없음" : trimmed
        let selectedTemplate = selectedTemplateScenarioID.flatMap { id in
            store.scenarios.first(where: { $0.id == id && $0.isTemplate })
        }
        let template: Scenario? = scenarioCreationMode == .template ? selectedTemplate : nil
        let newScenario = store.addScenario(title: name, fromTemplate: template)
        selectedScenario = newScenario
        editingScenario = nil
        newTitle = ""
        showNewScenarioDialog = false
        scheduleAutoHideSidebar()
    }

    private func makeTemplate(from scenario: Scenario) {
        store.makeScenarioTemplate(scenario)
    }

    private func openWorkspaceFromSidebar() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.item]
        panel.message = "기존 작업 파일(.wtf)을 선택하세요."
        
        if panel.runModal() == .OK, let chosenURL = panel.url {
            guard chosenURL.pathExtension.lowercased() == "wtf" else { return }
            do {
                var values = URLResourceValues()
                values.isPackage = true
                var url = chosenURL
                try? url.setResourceValues(values)
                let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                storageBookmark = bookmark
                DispatchQueue.main.async {
                    scheduleAutoHideSidebar()
                }
            } catch {
                // Logging intentionally muted.
            }
        }
    }

    private func scheduleAutoHideSidebar() {
        pendingAutoHideWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            withAnimation {
                isSidebarVisible = false
            }
            sidebarOpenedFromToggle = false
        }
        pendingAutoHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func closeToggleOpenedSidebar() {
        guard isSidebarVisible, sidebarOpenedFromToggle else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            isSidebarVisible = false
        }
        sidebarOpenedFromToggle = false
    }

    private func startSidebarEscapeMonitor() {
        guard sidebarEscapeMonitor == nil else { return }
        sidebarEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isSidebarVisible, sidebarOpenedFromToggle else { return event }
            guard event.keyCode == 53 else { return event } // Esc
            closeToggleOpenedSidebar()
            return nil
        }
    }

    private func stopSidebarEscapeMonitor() {
        guard let monitor = sidebarEscapeMonitor else { return }
        NSEvent.removeMonitor(monitor)
        sidebarEscapeMonitor = nil
    }

    private func refreshMainWindowFullscreenState() {
        if let key = NSApp.keyWindow, isPrimaryWorkspaceWindow(key) {
            isMainWindowFullscreen = key.styleMask.contains(.fullScreen)
            return
        }
        if let main = NSApp.mainWindow, isPrimaryWorkspaceWindow(main) {
            isMainWindowFullscreen = main.styleMask.contains(.fullScreen)
            return
        }
        if let fallback = NSApplication.shared.windows.first(where: isPrimaryWorkspaceWindow) {
            isMainWindowFullscreen = fallback.styleMask.contains(.fullScreen)
            return
        }
        isMainWindowFullscreen = false
    }

    private func isPrimaryWorkspaceWindow(_ window: NSWindow) -> Bool {
        if window.identifier?.rawValue == ReferenceWindowConstants.windowID { return false }
        let identifier = window.identifier?.rawValue.lowercased() ?? ""
        if identifier.contains("settings") { return false }
        if window is NSPanel { return false }
        return window.canBecomeMain
    }
    
    private func startEditing(_ scenario: Scenario) {
        editingScenario = scenario
        newTitle = scenario.title
        isNameFocused = true
    }
    
    private func finishEditingTitle(_ scenario: Scenario) {
        let finalTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = finalTitle.isEmpty ? "새로운 이야기" : finalTitle
        
        let oldTitle = scenario.title
        scenario.title = displayTitle
        
        if let rootCard = scenario.rootCards.first, (rootCard.content == oldTitle || rootCard.content == "제목 없음") {
            rootCard.content = displayTitle
        }
        
        editingScenario = nil
        store.saveAll()
        
        withAnimation {
            isSidebarVisible = false
        }
        sidebarOpenedFromToggle = false
    }

    private func deleteScenario(_ scenario: Scenario) {
        if selectedScenario == scenario { selectedScenario = nil }
        if editingScenario == scenario { editingScenario = nil }
        store.deleteScenario(scenario)
    }

    private func requestSplitPaneFocus(_ paneID: Int) {
        NotificationCenter.default.post(name: .waRequestSplitPaneFocus, object: paneID)
    }

    private func restoreSelectedScenarioIfNeeded() {
        guard !store.scenarios.isEmpty else {
            selectedScenario = nil
            return
        }

        if let current = selectedScenario,
           let matchedCurrent = store.scenarios.first(where: { $0.id == current.id }) {
            if current !== matchedCurrent {
                selectedScenario = matchedCurrent
            }
            return
        }

        if let rememberedID = UUID(uuidString: lastSelectedScenarioID),
           let remembered = store.scenarios.first(where: { $0.id == rememberedID }) {
            selectedScenario = remembered
            return
        }

        selectedScenario = store.scenarios.first
    }

    @ViewBuilder
    private func scenarioDetailView(for scenario: Scenario) -> some View {
        if mainSplitModeEnabled {
            splitScenarioDetailView(for: scenario)
        } else {
            ScenarioWriterView(scenario: scenario)
                .id(scenario.id)
        }
    }

    private func splitScenarioDetailView(for scenario: Scenario) -> some View {
        HStack(spacing: 0) {
            ScenarioWriterView(
                scenario: scenario,
                showWorkspaceTopToolbar: false,
                splitModeEnabled: true,
                splitPaneID: 1
            )
            .id("\(scenario.id.uuidString)-split-left")

            Divider()
                .background(Color.black.opacity(0.20))

            ScenarioWriterView(
                scenario: scenario,
                showWorkspaceTopToolbar: true,
                splitModeEnabled: true,
                splitPaneID: 2
            )
            .id("\(scenario.id.uuidString)-split-right")
        }
        .onAppear {
            requestSplitPaneFocus(activeSplitPaneID)
        }
        .onChange(of: activeSplitPaneID) { _, newValue in
            requestSplitPaneFocus(newValue)
        }
    }
}

struct ScenarioRow: View {
    @ObservedObject var scenario: Scenario
    var onRename: () -> Void
    var onDelete: () -> Void
    var onMakeTemplate: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(scenario.title.isEmpty ? "제목 없음" : scenario.title)
                .font(.custom("SansMonoCJKFinalDraft", size: 18))
            if scenario.isTemplate {
                Text("템플릿")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
            .padding(.vertical, 2)
            .contextMenu {
                Button("이름 변경") { onRename() }
                Button("템플릿으로 만들기") { onMakeTemplate() }
                Button("삭제", role: .destructive) { onDelete() }
            }
    }
}
