import SwiftUI

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
        if let bookmark = WorkspaceBookmarkService.openWorkspaceBookmark(
            message: "기존 작업 파일(.wtf)을 선택하세요."
        ) {
            storageBookmark = bookmark
            DispatchQueue.main.async {
                scheduleAutoHideSidebar()
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

