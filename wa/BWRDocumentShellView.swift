import SwiftUI

@MainActor
struct BWRDocumentShellView: View {
    @ObservedObject var document: BWRReferenceDocument
    let fileURL: URL?

    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow

    @FocusState private var boardCommandsFocused: Bool
    @FocusState private var searchFieldFocused: Bool
    @SceneStorage("bwr.document.sceneSessionID") private var sceneSessionID: String = UUID().uuidString

    @State private var selectedCardIDs: Set<UUID> = []
    @State private var selectedGroupID: UUID?
    @State private var searchQuery: String = ""
    @State private var searchScope: BWRSearchScope = .everything
    @State private var newGroupName: String = "New Group"
    @State private var groupRenameDraft: String = ""
    @State private var viewportState = BWRViewportState()
    @State private var inlineEditor: BWRInlineEditorState?
    @State private var largeEditorCardID: UUID?
    @State private var pendingLayerRename: BWRPendingLayerRename?
    @State private var focusPresentation: BWRFocusPresentation?
    @State private var exportFeedback: BWRExportFeedback?
    @State private var compactInspectorTab: BWRCompactInspectorTab = .project
    @State private var boardChromeState = BWRBoardChromeState()

    var body: some View {
        GeometryReader { geometry in
            let layoutMode = BWRWorkspaceLayoutMode.resolve(for: geometry.size)
            Group {
                if layoutMode == .regular {
                    regularShell
                } else {
                    compactShell(height: geometry.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(BWRCardBuddyShellWorkspaceBackground())
        .navigationTitle(document.displayName)
        .focusable()
        .focused($boardCommandsFocused)
        .onAppear {
            document.attach(fileURL: fileURL)
            document.bindUndoManager(undoManager)
            loadViewportState()
            seedSelectionIfNeeded()
            syncBoardChromeSelectionState(modality: .pointer)
            syncRenameDrafts()
            boardCommandsFocused = true
        }
        .onChange(of: fileURL) { _, newValue in
            finishInlineEdit(save: true)
            document.attach(fileURL: newValue)
            loadViewportState()
        }
        .onChange(of: undoManager) { _, newValue in
            document.bindUndoManager(newValue)
        }
        .onChange(of: selectedPrimaryCardID) { _, _ in
            syncBoardChromeSelectionState(modality: boardChromeState.slotCursor.lastInputModality)
            syncRenameDrafts()
        }
        .onChange(of: selectedGroupID) { _, _ in
            syncRenameDrafts()
        }
        .onChange(of: document.liveCards.map(\.id)) { _, _ in
            seedSelectionIfNeeded()
            syncBoardChromeSelectionState(modality: boardChromeState.slotCursor.lastInputModality)
            if let inlineEditor, !document.liveCards.contains(where: { $0.id == inlineEditor.cardID }) {
                self.inlineEditor = nil
            }
        }
        .onChange(of: viewportState) { _, newValue in
            BWRViewportStateStore.save(newValue, documentURL: fileURL, sceneSessionID: sceneSessionID)
        }
        .onKeyPress(phases: [.down, .repeat]) { press in
            handleBoardKeyPress(press)
        }
        .sheet(item: Binding(
            get: { largeEditorCardID.map(BWRLargeEditorTarget.init(cardID:)) },
            set: { largeEditorCardID = $0?.cardID }
        )) { target in
            BWRLargeCardEditorSheet(
                document: document,
                cardID: target.cardID,
                onDismiss: {
                    largeEditorCardID = nil
                    boardCommandsFocused = true
                }
            )
        }
        .sheet(item: $focusPresentation, onDismiss: {
            boardCommandsFocused = true
        }) { presentation in
            BWRFocusModeView(
                document: document,
                groupID: presentation.groupID,
                initialMode: presentation.mode,
                onDismiss: {
                    focusPresentation = nil
                    boardCommandsFocused = true
                }
            )
        }
        .alert(item: $exportFeedback) { feedback in
            Alert(
                title: Text(feedback.title),
                message: Text(feedback.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var regularShell: some View {
        HSplitView {
            leftSidebar
                .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)

            ZStack {
                Color.clear
                VStack(spacing: 16) {
                    headerBand
                    toolbarBand
                    boardStage
                }
                .frame(maxWidth: 1120, maxHeight: .infinity, alignment: .top)
                .padding(.vertical, 12)
                .padding(.horizontal, 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            rightSidebar
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
        }
        .padding(12)
    }

    private func compactShell(height: CGFloat) -> some View {
        VStack(spacing: 12) {
            headerBand
            toolbarBand
            boardStage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            compactInspector(height: min(max(height * 0.34, 240), 360))
        }
        .padding(14)
    }

    private var leftSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                documentInfoPanel
                groupPanel
                archivePanel
            }
            .padding(18)
        }
        .bwrCardBuddyShellSurface(BWRCardBuddyShellChrome.panelStyle(for: .column))
        .padding(.vertical, 10)
        .padding(.leading, 10)
        .padding(.trailing, 6)
    }

    private var documentInfoPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(document.displayName)
                .font(.system(size: 20, weight: .semibold))
            Text(document.displayPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Text(document.autosaveStatus)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack {
                Button("New Card") {
                    createCardNearViewport()
                }
                Button("Open Spike Lab") {
                    openWindow(id: BWRSpikeLabConstants.windowID)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Board Surface")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button("Default") {
                        applyBoardSurface(nil)
                    }
                    .disabled(currentBoardBackgroundHex == nil)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 28, maximum: 28), spacing: 8)], spacing: 8) {
                    ForEach(BWRCardBuddyBoardThemeGuardrail.boardSwatches) { swatch in
                        Button {
                            applyBoardSurface(swatch)
                        } label: {
                            Circle()
                                .fill(BWRCardBuddyBoardThemeGuardrail.boardColor(for: swatch.hex))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            isCurrentBoardSurface(swatch)
                                                ? (Color(hex: BWRCardBuddyCardShell.selectionHex) ?? .accentColor)
                                                : Color.black.opacity(0.12),
                                            lineWidth: isCurrentBoardSurface(swatch) ? 2 : 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .help(swatch.name)
                    }
                }

                Text("카드 tint는 board surface와 너무 가까워지면 paper 쪽으로 자동 보정됩니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .bwrCardBuddyShellSurface(BWRCardBuddyShellChrome.panelStyle(for: .section))
    }

    private var groupPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Groups")
                .font(.system(size: 14, weight: .semibold))

            TextField("New group name", text: $newGroupName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Create From Selection") {
                    finishInlineEdit(save: true)
                    if let groupID = document.createGroup(name: resolvedGroupName, memberCardIDs: Array(selectedCardIDs)) {
                        selectedGroupID = groupID
                        syncRenameDrafts()
                    }
                }
                .disabled(selectedCardIDs.isEmpty)
                Spacer()
                Button("Add Selection") {
                    guard let selectedGroupID else { return }
                    finishInlineEdit(save: true)
                    document.addCards(toGroup: selectedGroupID, cardIDs: Array(selectedCardIDs))
                }
                .disabled(selectedCardIDs.isEmpty || selectedGroupID == nil)
            }

            HStack {
                Button("Remove Selection") {
                    guard let selectedGroupID else { return }
                    finishInlineEdit(save: true)
                    document.removeCards(fromGroup: selectedGroupID, cardIDs: Array(selectedCardIDs))
                }
                .disabled(selectedCardIDs.isEmpty || selectedGroupID == nil)
                Spacer()
                Button("Archive Group") {
                    guard let selectedGroupID else { return }
                    finishInlineEdit(save: true)
                    document.archiveGroup(groupID: selectedGroupID)
                    self.selectedGroupID = document.liveGroups.first?.id
                }
                .disabled(selectedGroupID == nil)
            }

            Menu("Open Focus Mode") {
                Button("Current Layer") {
                    openFocusMode(.currentLayer)
                }
                Button("Treatment") {
                    openFocusMode(.treatment)
                }
                Button("Scenario") {
                    openFocusMode(.scenario)
                }
            }
            .disabled(selectedGroupID == nil)

            Menu("Export Selected Group") {
                Menu("Copy Text") {
                    exportButtons(destination: .clipboard)
                }
                Menu("Save TXT") {
                    exportButtons(destination: .textFile)
                }
                Menu("Save Centered PDF") {
                    exportButtons(destination: .centeredPDF)
                }
                Menu("Save Korean PDF") {
                    exportButtons(destination: .koreanPDF)
                }
            }
            .disabled(selectedGroupID == nil)

            Text("선택 그룹만 현재/Treatment/Scenario 기준으로 TXT/PDF 출력합니다.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            List(selection: Binding(
                get: { selectedGroupID.map { Set([ $0 ]) } ?? [] },
                set: { selection in
                    finishInlineEdit(save: true)
                    selectedGroupID = selection.first
                    syncRenameDrafts()
                }
            )) {
                ForEach(document.liveGroups) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name)
                            .font(.system(size: 12, weight: .medium))
                        Text("\(group.memberCardIDs.count) cards")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .tag(group.id)
                }
            }
            .frame(minHeight: 180)
            .bwrCardBuddySidebarListChrome()

            if let selectedGroup {
                Divider()
                Text("Selected Group")
                    .font(.system(size: 12, weight: .semibold))
                TextField("Group name", text: $groupRenameDraft)
                    .textFieldStyle(.roundedBorder)
                Button("Rename Group") {
                    finishInlineEdit(save: true)
                    document.renameGroup(groupID: selectedGroup.id, newName: groupRenameDraft)
                    syncRenameDrafts()
                }
            }
        }
        .padding(14)
        .bwrCardBuddyShellSurface(BWRCardBuddyShellChrome.panelStyle(for: .section))
    }

    private var rightSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                selectedCardPanel
                linkPanel
                searchPanel
                viewportPanel
            }
            .padding(18)
        }
        .bwrCardBuddyShellSurface(BWRCardBuddyShellChrome.panelStyle(for: .column))
        .padding(.vertical, 10)
        .padding(.leading, 6)
        .padding(.trailing, 10)
    }

    private func compactInspector(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Inspector", selection: $compactInspectorTab) {
                ForEach(BWRCompactInspectorTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch compactInspectorTab {
                    case .project:
                        documentInfoPanel
                        viewportPanel
                    case .groups:
                        groupPanel
                        archivePanel
                    case .selection:
                        selectedCardPanel
                        linkPanel
                    case .search:
                        searchPanel
                        archivePanel
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        }
        .padding(14)
        .bwrCardBuddyShellSurface(BWRCardBuddyShellChrome.panelStyle(for: .column))
    }

    private var headerBand: some View {
        header
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .bwrCardBuddyShellSurface(BWRCardBuddyShellChrome.panelStyle(for: .band))
    }

    private var toolbarBand: some View {
        boardToolbar
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .bwrCardBuddyShellSurface(BWRCardBuddyShellChrome.panelStyle(for: .band))
    }

    private var boardStage: some View {
        boardCanvas
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .bwrCardBuddyShellSurface(BWRCardBuddyShellChrome.panelStyle(for: .stage))
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                headerTitleBlock
                Spacer()
                headerActionButtons
            }

            VStack(alignment: .leading, spacing: 10) {
                headerTitleBlock
                headerActionButtons
            }
        }
    }

    private var boardToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                boardPrimaryActions
                Spacer()
                zoomControls
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    boardPrimaryActions
                    Spacer()
                }
                HStack(spacing: 10) {
                    zoomControls
                    Spacer()
                }
            }
        }
    }

    private var boardCanvas: some View {
        BWRBoardCanvasView(
            document: document,
            selectedCardIDs: $selectedCardIDs,
            selectedGroupID: $selectedGroupID,
            viewportState: $viewportState,
            inlineEditor: $inlineEditor,
            boardChromeState: $boardChromeState,
            boardTheme: document.document.boardTheme,
            beginInlineEdit: { cardID in
                beginInlineEdit(cardID: cardID)
            },
            finishInlineEdit: { save in
                finishInlineEdit(save: save)
            },
            splitInlineEdit: {
                splitInlineEdit()
            },
            cycleInlineLayer: { cardID, direction in
                cycleInlineEditorLayer(cardID: cardID, direction: direction)
            },
            openLargeEditor: { cardID in
                openLargeEditor(cardID: cardID)
            },
            requestLayerRename: { cardID, layerID, currentName in
                pendingLayerRename = BWRPendingLayerRename(cardID: cardID, layerID: layerID, currentName: currentName)
            },
            requestGroupRename: { groupID, currentName in
                selectedGroupID = groupID
                groupRenameDraft = currentName
            }
        )
    }

    private var headerTitleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Board Canvas")
                .font(.system(size: 20, weight: .semibold))
            Text("cards \(document.liveCards.count) / archived \(document.archivedCards.count) / groups \(document.liveGroups.count) / links \(document.liveLinks.count)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var headerActionButtons: some View {
        HStack(spacing: 10) {
            Button("Undo") { undoManager?.undo() }
                .disabled(!(undoManager?.canUndo ?? false))
            Button("Redo") { undoManager?.redo() }
                .disabled(!(undoManager?.canRedo ?? false))
            Button("Save Now") { document.saveNow() }
            Button("Full Save") { document.forceFullSaveNow() }
        }
        .bwrCardBuddyChromeButton(.toolbarAccessory)
    }

    private var boardPrimaryActions: some View {
        Group {
            Button("New Card") {
                createCardNearViewport()
            }

            Button("Inline Edit") {
                guard let cardID = selectedPrimaryCardID else { return }
                beginInlineEdit(cardID: cardID)
            }
            .disabled(selectedPrimaryCardID == nil)

            Button("Open Large Editor") {
                guard let cardID = selectedPrimaryCardID else { return }
                openLargeEditor(cardID: cardID)
            }
            .disabled(selectedPrimaryCardID == nil)

            Menu("Focus Mode") {
                Button("Current Layer") {
                    openFocusMode(.currentLayer)
                }
                Button("Treatment") {
                    openFocusMode(.treatment)
                }
                Button("Scenario") {
                    openFocusMode(.scenario)
                }
            }
            .disabled(selectedGroupID == nil)

            Button("Delete") {
                finishInlineEdit(save: true)
                document.deleteCards(cardIDs: selectedCardIDs)
                selectedCardIDs.removeAll()
                seedSelectionIfNeeded()
            }
            .disabled(selectedCardIDs.isEmpty)
        }
        .bwrCardBuddyChromeButton(.toolbarPrimary)
    }

    private var zoomControls: some View {
        Group {
            Text("Zoom")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { viewportState.zoomScale },
                    set: { viewportState.zoomScale = $0 }
                ),
                in: 0.3...1.6
            )
            .frame(width: 180)
            Text(String(format: "%.2fx", viewportState.zoomScale))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 52)
        }
    }

    private var selectedCardPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Selection")
                .font(.system(size: 14, weight: .semibold))

            if let selectedCard {
                Text(selectedCard.titlePreview)
                    .font(.system(size: 16, weight: .semibold))
                Text(selectedCard.id.uuidString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)

                Picker("Layer", selection: Binding(
                    get: { selectedCard.currentLayerID },
                    set: { document.setCurrentLayer(cardID: selectedCard.id, layerID: $0) }
                )) {
                    ForEach(selectedCard.layers) { layer in
                        Text(layer.name).tag(layer.id)
                    }
                }
                .pickerStyle(.segmented)

                if inlineEditor?.cardID == selectedCard.id {
                    HStack {
                        Button("Prev Layer") {
                            cycleInlineEditorLayer(cardID: selectedCard.id, direction: -1)
                        }
                        Button("Next Layer") {
                            cycleInlineEditorLayer(cardID: selectedCard.id, direction: 1)
                        }
                    }
                }

                HStack {
                    Button("Add Body Layer") {
                        finishInlineEdit(save: true)
                        document.appendBodyLayer(cardID: selectedCard.id)
                    }
                    Button("Delete Layer") {
                        finishInlineEdit(save: true)
                        document.deleteBodyLayer(cardID: selectedCard.id, layerID: selectedCard.currentLayerID)
                    }
                    .disabled(!(selectedCurrentLayer?.kind == .body && selectedCard.layers.filter { $0.kind == .body }.count > 1))
                }

                HStack {
                    ForEach(BWRCardBuddyBoardThemeGuardrail.cardSwatches) { swatch in
                        Button {
                            finishInlineEdit(save: true)
                            document.applyCardColor(cardIDs: selectedCardIDs, colorHex: swatch.hex)
                        } label: {
                            Circle()
                                .fill(
                                    BWRCardBuddyBoardThemeGuardrail.cardSwatchPreviewColor(
                                        for: swatch.hex,
                                        boardHex: currentBoardBackgroundHex
                                    )
                                )
                                .frame(width: 20, height: 20)
                                .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help(swatch.name)
                    }
                }

                if let pendingLayerRename, pendingLayerRename.cardID == selectedCard.id {
                    Divider()
                    Text("Rename Layer")
                        .font(.system(size: 12, weight: .semibold))
                    TextField("Layer name", text: Binding(
                        get: { pendingLayerRename.currentName },
                        set: { newValue in
                            self.pendingLayerRename?.currentName = newValue
                        }
                    ))
                    .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Apply") {
                            finishInlineEdit(save: true)
                            document.renameLayer(
                                cardID: pendingLayerRename.cardID,
                                layerID: pendingLayerRename.layerID,
                                newName: pendingLayerRename.currentName
                            )
                            self.pendingLayerRename = nil
                        }
                        Button("Cancel") {
                            self.pendingLayerRename = nil
                        }
                    }
                }
            } else {
                Text("보드에서 카드를 선택하면 레이어와 색상을 빠르게 편집할 수 있습니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .bwrCardBuddyShellSurface(BWRCardBuddyShellChrome.panelStyle(for: .section))
    }

    private var linkPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Links")
                .font(.system(size: 14, weight: .semibold))

            if let linkPair {
                Menu("Create Link") {
                    Button("\(linkTitle(for: linkPair.sourceID)) -> \(linkTitle(for: linkPair.destinationID))") {
                        finishInlineEdit(save: true)
                        document.createLink(sourceCardID: linkPair.sourceID, destinationCardID: linkPair.destinationID)
                    }
                    Button("\(linkTitle(for: linkPair.destinationID)) -> \(linkTitle(for: linkPair.sourceID))") {
                        finishInlineEdit(save: true)
                        document.createLink(sourceCardID: linkPair.destinationID, destinationCardID: linkPair.sourceID)
                    }
                }
            }

            if selectedCardLinks.isEmpty {
                Text("카드 두 장을 선택해 방향 링크를 만들거나, 현재 카드와 연결된 링크를 여기서 관리할 수 있습니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(selectedCardLinks) { link in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(linkLabel(for: link))
                                .font(.system(size: 12, weight: .medium))
                            Text(link.id.uuidString.prefix(8))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Archive") {
                            finishInlineEdit(save: true)
                            document.archiveLink(linkID: link.id)
                        }
                    }
                }
            }
        }
        .padding(14)
        .bwrCardBuddyShellSurface(BWRCardBuddyShellChrome.panelStyle(for: .section))
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Search")
                .font(.system(size: 14, weight: .semibold))

            TextField("Search cards, groups, archive…", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .focused($searchFieldFocused)

            Picker("Scope", selection: $searchScope) {
                Text("All").tag(BWRSearchScope.everything)
                Text("Live").tag(BWRSearchScope.liveOnly)
                Text("Archive").tag(BWRSearchScope.archiveOnly)
            }
            .pickerStyle(.segmented)

            List(searchResults) { hit in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(hit.title)
                        Spacer()
                        Text(hit.isArchived ? "ARCHIVE" : "LIVE")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(hit.snippet)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    handleSearchSelection(hit)
                }
            }
            .frame(minHeight: 200)
            .bwrCardBuddySidebarListChrome()
        }
        .padding(14)
        .bwrCardBuddyShellSurface(BWRCardBuddyShellChrome.panelStyle(for: .section))
    }

    private var archivePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Archive")
                .font(.system(size: 14, weight: .semibold))

            List {
                if !document.archivedCards.isEmpty {
                    Section("Cards") {
                        ForEach(document.archivedCards) { card in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(card.titlePreview)
                                    Text(card.id.uuidString.prefix(8))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Restore") {
                                    document.restoreCard(cardID: card.id)
                                }
                            }
                        }
                    }
                }

                if !document.archivedGroups.isEmpty {
                    Section("Groups") {
                        ForEach(document.archivedGroups) { group in
                            HStack {
                                Text(group.name)
                                Spacer()
                                Button("Restore") {
                                    document.restoreGroup(groupID: group.id)
                                }
                            }
                        }
                    }
                }

                if !document.archivedLinks.isEmpty {
                    Section("Links") {
                        ForEach(document.archivedLinks) { link in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(linkLabel(for: link))
                                    Text(link.id.uuidString.prefix(8))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Restore") {
                                    document.restoreLink(linkID: link.id)
                                }
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 220)
            .bwrCardBuddySidebarListChrome()
        }
        .padding(14)
        .bwrCardBuddyShellSurface(BWRCardBuddyShellChrome.panelStyle(for: .section))
    }

    private var viewportPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Viewport")
                .font(.system(size: 14, weight: .semibold))
            Text("zoom \(String(format: "%.2f", viewportState.zoomScale))")
                .font(.system(size: 11, design: .monospaced))
            Text("scroll \(Int(viewportState.scrollOrigin.x)), \(Int(viewportState.scrollOrigin.y))")
                .font(.system(size: 11, design: .monospaced))
            Text("size \(Int(viewportState.viewportSize.width)) × \(Int(viewportState.viewportSize.height))")
                .font(.system(size: 11, design: .monospaced))
            Text("Cmd+F/S/+/−/0, Ctrl+L, Enter, Delete, Arrow 키를 보드에서 바로 사용합니다.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .bwrCardBuddyShellSurface(BWRCardBuddyShellChrome.panelStyle(for: .section))
    }

    private var currentBoardBackgroundHex: String? {
        BWRCardBuddyBoardThemeGuardrail.resolvedBoardBackgroundHex(for: document.document.boardTheme)
    }

    private var resolvedGroupName: String {
        let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Group" : trimmed
    }

    private func applyBoardSurface(_ swatch: BWRCardBuddyBoardSurfaceSwatch?) {
        finishInlineEdit(save: true)
        document.updateBoardTheme(
            backgroundHex: swatch?.hex,
            accentMode: swatch?.accentMode ?? .system
        )
    }

    private func isCurrentBoardSurface(_ swatch: BWRCardBuddyBoardSurfaceSwatch) -> Bool {
        currentBoardBackgroundHex == BWRCardBuddyBoardThemeGuardrail.normalizedHex(swatch.hex)
    }

    private var selectedPrimaryCardID: UUID? {
        document.liveCards.first(where: { selectedCardIDs.contains($0.id) })?.id
    }

    private var selectedCard: BWRCard? {
        guard let selectedPrimaryCardID else { return nil }
        return document.liveCards.first(where: { $0.id == selectedPrimaryCardID })
    }

    private var currentSlotCursorReference: BWRBoardSlotReference? {
        boardChromeState.slotCursor.slotReference
    }

    private var selectedCurrentLayer: BWRCardLayer? {
        guard let selectedCard else { return nil }
        return selectedCard.layers.first(where: { $0.id == selectedCard.currentLayerID })
    }

    private var selectedGroup: BWRGroup? {
        guard let selectedGroupID else { return nil }
        return document.liveGroups.first(where: { $0.id == selectedGroupID })
    }

    private var linkPair: (sourceID: UUID, destinationID: UUID)? {
        guard let selectedPrimaryCardID, selectedCardIDs.count == 2 else { return nil }
        guard let otherID = selectedCardIDs.first(where: { $0 != selectedPrimaryCardID }) else { return nil }
        return (selectedPrimaryCardID, otherID)
    }

    private var selectedCardLinks: [BWRLink] {
        guard let selectedPrimaryCardID else { return [] }
        return document.liveLinks(touching: selectedPrimaryCardID)
            .sorted { lhs, rhs in
                if lhs.sourceCardID != rhs.sourceCardID {
                    return lhs.sourceCardID.uuidString < rhs.sourceCardID.uuidString
                }
                if lhs.destinationCardID != rhs.destinationCardID {
                    return lhs.destinationCardID.uuidString < rhs.destinationCardID.uuidString
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private var searchResults: [BWRSearchHit] {
        document.search(query: searchQuery, scope: searchScope)
    }

    private func loadViewportState() {
        viewportState = BWRViewportStateStore.load(documentURL: fileURL, sceneSessionID: sceneSessionID)
    }

    private func seedSelectionIfNeeded(forceCardID: UUID? = nil) {
        let liveIDs = Set(document.liveCards.map(\.id))
        selectedCardIDs = selectedCardIDs.filter { liveIDs.contains($0) }

        if let forceCardID, liveIDs.contains(forceCardID) {
            selectedCardIDs = [forceCardID]
        } else if selectedCardIDs.isEmpty, let first = document.liveCards.first?.id {
            selectedCardIDs = [first]
        }

        if let selectedGroupID, !document.liveGroups.contains(where: { $0.id == selectedGroupID }) {
            self.selectedGroupID = document.liveGroups.first?.id
        } else if self.selectedGroupID == nil {
            self.selectedGroupID = document.liveGroups.first?.id
        }
    }

    private func syncBoardChromeSelectionState(modality: BWRBoardInputModality) {
        if let selectedPrimaryCardID {
            boardChromeState.slotCursor.syncSelection(
                cardID: selectedPrimaryCardID,
                document: document.document,
                modality: modality
            )
            return
        }

        if let currentReference = boardChromeState.slotCursor.slotReference {
            boardChromeState.slotCursor.set(reference: currentReference, modality: modality)
            return
        }

        boardChromeState.slotCursor.set(
            reference: BWRBoardOrderResolver.firstSlotReference(document: document.document),
            modality: modality,
            visibility: .visible
        )
    }

    private func syncRenameDrafts() {
        groupRenameDraft = selectedGroup?.name ?? ""
        if let pendingLayerRename,
           let card = document.liveCards.first(where: { $0.id == pendingLayerRename.cardID }),
           let layer = card.layers.first(where: { $0.id == pendingLayerRename.layerID }) {
            self.pendingLayerRename = BWRPendingLayerRename(cardID: card.id, layerID: layer.id, currentName: layer.name)
        }
    }

    private func createCardNearViewport() {
        finishInlineEdit(save: true)
        if let cardID = document.createCard(
            selectedCardID: selectedPrimaryCardID,
            selectedGroupID: selectedGroupID,
            viewportState: viewportState
        ) {
            seedSelectionIfNeeded(forceCardID: cardID)
            boardCommandsFocused = true
        }
    }

    private func selectSlotReference(_ reference: BWRBoardSlotReference, modality: BWRBoardInputModality) {
        boardChromeState.slotCursor.set(reference: reference, modality: modality)
        if let cardID = BWRSlotOrder.cardID(in: reference.host, at: reference.slotIndex, document: document.document) {
            selectedCardIDs = [cardID]
            selectedGroupID = nil
        } else {
            selectedCardIDs.removeAll()
            switch reference.host {
            case let .group(groupID):
                selectedGroupID = groupID
            case .strip:
                selectedGroupID = nil
            }
        }
    }

    private func activateCurrentSlotCursor() {
        let fallbackReference = selectedPrimaryCardID.flatMap { cardID in
            BWRSlotOrder.indexOfCardInHost(cardID: cardID, document: document.document).map {
                BWRBoardSlotReference(host: $0.host, slotIndex: $0.index)
            }
        }

        guard let reference = currentSlotCursorReference ?? fallbackReference else { return }
        let residentCardID = BWRSlotOrder.cardID(in: reference.host, at: reference.slotIndex, document: document.document)

        switch BWRCardBuddyEditingActivation.keyboardEnter(slotHasCard: residentCardID != nil) {
        case .beginInlineEdit:
            guard let cardID = residentCardID else { return }
            selectSlotReference(reference, modality: .keyboard)
            beginInlineEdit(cardID: cardID)
        case .createCardAndBeginInlineEdit:
            guard let newCardID = document.createCard(in: reference.host, insertionIndex: reference.slotIndex) else {
                return
            }
            seedSelectionIfNeeded(forceCardID: newCardID)
            syncBoardChromeSelectionState(modality: .keyboard)
            beginInlineEdit(cardID: newCardID)
        case .openLargeEditor:
            return
        }
    }

    private func beginInlineEdit(cardID: UUID) {
        finishInlineEdit(save: true)
        guard let card = document.liveCards.first(where: { $0.id == cardID }),
              let layer = card.currentLayer else {
            return
        }
        selectedCardIDs = [cardID]
        selectedGroupID = nil
        inlineEditor = BWRInlineEditorState(
            cardID: cardID,
            layerID: layer.id,
            text: layer.markdown,
            selectedRange: NSRange(location: 0, length: 0)
        )
    }

    private func finishInlineEdit(save: Bool) {
        guard let inlineEditor else { return }
        defer {
            self.inlineEditor = nil
            boardCommandsFocused = true
        }

        guard save,
              let card = document.liveCards.first(where: { $0.id == inlineEditor.cardID }),
              let layer = card.layers.first(where: { $0.id == inlineEditor.layerID }),
              layer.markdown != inlineEditor.text else {
            return
        }

        document.applyLayerMarkdown(cardID: inlineEditor.cardID, layerID: inlineEditor.layerID, markdown: inlineEditor.text)
    }

    private func splitInlineEdit() {
        guard let inlineEditor else { return }

        let splitLocation = inlineEditor.selectedRange.location
        if let newCardID = document.splitCard(
            cardID: inlineEditor.cardID,
            layerID: inlineEditor.layerID,
            committedMarkdown: inlineEditor.text,
            atUTF16Location: splitLocation
        ) {
            self.inlineEditor = nil
            seedSelectionIfNeeded(forceCardID: newCardID)
            beginInlineEdit(cardID: newCardID)
        } else {
            finishInlineEdit(save: true)
        }
    }

    private func cycleInlineEditorLayer(cardID: UUID, direction: Int) {
        guard inlineEditor?.cardID == cardID else { return }
        finishInlineEdit(save: true)
        document.cycleLayers(cardIDs: [cardID], direction: direction)
        beginInlineEdit(cardID: cardID)
    }

    private func openLargeEditor(cardID: UUID) {
        finishInlineEdit(save: true)
        largeEditorCardID = cardID
    }

    private func openFocusMode(_ mode: BWRFocusModeKind) {
        guard let selectedGroupID else { return }
        finishInlineEdit(save: true)
        largeEditorCardID = nil
        focusPresentation = BWRFocusPresentation(groupID: selectedGroupID, mode: mode)
    }

    @ViewBuilder
    private func exportButtons(destination: BWRExportDestination) -> some View {
        Button("Current Layer") {
            exportSelectedGroup(mode: .currentLayer, destination: destination)
        }
        Button("Treatment") {
            exportSelectedGroup(mode: .treatment, destination: destination)
        }
        Button("Scenario") {
            exportSelectedGroup(mode: .scenario, destination: destination)
        }
    }

    private func exportSelectedGroup(mode: BWRFocusModeKind, destination: BWRExportDestination) {
        guard let selectedGroupID else { return }
        finishInlineEdit(save: true)

        let feedback: BWRExportFeedback?
        switch destination {
        case .clipboard:
            feedback = document.exportToClipboard(groupIDs: [selectedGroupID], mode: mode)
        case .textFile:
            feedback = document.exportToTextFile(groupIDs: [selectedGroupID], mode: mode)
        case .centeredPDF:
            feedback = document.exportToPDF(groupIDs: [selectedGroupID], mode: mode, format: .centered)
        case .koreanPDF:
            feedback = document.exportToPDF(groupIDs: [selectedGroupID], mode: mode, format: .korean)
        }

        exportFeedback = feedback
    }

    private func openSearchPanelFromKeyboard() {
        compactInspectorTab = .search
        DispatchQueue.main.async {
            searchFieldFocused = true
        }
    }

    private func updateZoom(_ nextZoom: Double) {
        viewportState.zoomScale = nextZoom
    }

    private func linkTitle(for cardID: UUID) -> String {
        document.document.cards.first(where: { $0.id == cardID })?.titlePreview ?? cardID.uuidString.prefix(4).description
    }

    private func linkLabel(for link: BWRLink) -> String {
        "\(linkTitle(for: link.sourceCardID)) -> \(linkTitle(for: link.destinationCardID))"
    }

    private func handleSearchSelection(_ hit: BWRSearchHit) {
        finishInlineEdit(save: true)
        switch hit.entityKind {
        case .card:
            if hit.isArchived {
                document.restoreCard(cardID: hit.entityID)
            }
            seedSelectionIfNeeded(forceCardID: hit.entityID)
            selectedGroupID = nil
        case .group:
            if hit.isArchived {
                document.restoreGroup(groupID: hit.entityID)
            }
            selectedGroupID = hit.entityID
        case .link:
            if hit.isArchived {
                document.restoreLink(linkID: hit.entityID)
            }
            if let link = document.liveLinks.first(where: { $0.id == hit.entityID }) {
                selectedCardIDs = Set([link.sourceCardID, link.destinationCardID])
                selectedGroupID = nil
            }
        }
    }

    private func handleBoardKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard press.phase == .down || press.phase == .repeat else { return .ignored }
        if largeEditorCardID != nil || inlineEditor != nil {
            return .ignored
        }

        if press.modifiers == [.command],
           (press.characters.lowercased() == "f" || press.characters == "ㄹ") {
            openSearchPanelFromKeyboard()
            return .handled
        }

        if press.modifiers == [.command],
           press.characters.lowercased() == "s" {
            document.saveNow()
            return .handled
        }

        if press.modifiers == [.command, .shift],
           press.characters.lowercased() == "s" {
            document.forceFullSaveNow()
            return .handled
        }

        if press.modifiers == [.command],
           (press.characters == "=" || press.characters == "+") {
            updateZoom(BWRBoardZoomController.zoomIn(from: viewportState.zoomScale))
            return .handled
        }

        if press.modifiers == [.command],
           press.characters == "-" {
            updateZoom(BWRBoardZoomController.zoomOut(from: viewportState.zoomScale))
            return .handled
        }

        if press.modifiers == [.command],
           press.characters == "0" {
            updateZoom(BWRBoardZoomController.reset())
            return .handled
        }

        if press.modifiers == [.command],
           let focusMode = BWRFocusModeKind.keyboardMapping(for: press.characters),
           selectedGroupID != nil {
            openFocusMode(focusMode)
            return .handled
        }

        if press.modifiers.contains(.control),
           !press.modifiers.contains(.command),
           !press.modifiers.contains(.option),
           (press.characters.lowercased() == "l" || press.characters == "ㅣ") {
            document.cycleLayers(cardIDs: selectedCardIDs, direction: press.modifiers.contains(.shift) ? -1 : 1)
            return .handled
        }

        let hasNoSystemModifiers = !press.modifiers.contains(.command) &&
            !press.modifiers.contains(.option) &&
            !press.modifiers.contains(.control)

        if hasNoSystemModifiers && press.key == .return {
            activateCurrentSlotCursor()
            return .handled
        }

        if hasNoSystemModifiers && (press.key == .delete || press.key == .init("\u{7f}")) {
            document.deleteCards(cardIDs: selectedCardIDs)
            selectedCardIDs.removeAll()
            seedSelectionIfNeeded()
            return .handled
        }

        if hasNoSystemModifiers && press.key == .escape {
            finishInlineEdit(save: false)
            selectedGroupID = nil
            selectedCardIDs.removeAll()
            return .handled
        }

        guard hasNoSystemModifiers else { return .ignored }
        switch press.key {
        case .leftArrow:
            moveSlotCursor(direction: .left)
            return .handled
        case .rightArrow:
            moveSlotCursor(direction: .right)
            return .handled
        case .upArrow:
            moveSlotCursor(direction: .up)
            return .handled
        case .downArrow:
            moveSlotCursor(direction: .down)
            return .handled
        default:
            return .ignored
        }
    }

    private func moveSlotCursor(direction: BWRBoardArrowDirection) {
        let anchorReference = currentSlotCursorReference ??
            selectedPrimaryCardID.flatMap { cardID in
                BWRSlotOrder.indexOfCardInHost(cardID: cardID, document: document.document).map {
                    BWRBoardSlotReference(host: $0.host, slotIndex: $0.index)
                }
            }

        let targetReference = BWRBoardOrderResolver.nextSlotReference(
            document: document.document,
            from: anchorReference,
            direction: direction
        )

        if let targetReference {
            selectSlotReference(targetReference, modality: .keyboard)
        }
    }
}

private struct BWRPendingLayerRename: Identifiable {
    let cardID: UUID
    let layerID: UUID
    var currentName: String

    var id: String {
        "\(cardID.uuidString)|\(layerID.uuidString)"
    }
}

private struct BWRLargeEditorTarget: Identifiable {
    let cardID: UUID
    var id: UUID { cardID }
}

private enum BWRExportDestination {
    case clipboard
    case textFile
    case centeredPDF
    case koreanPDF
}

private enum BWRCompactInspectorTab: String, CaseIterable, Identifiable {
    case project
    case groups
    case selection
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .project:
            return "Project"
        case .groups:
            return "Groups"
        case .selection:
            return "Selection"
        case .search:
            return "Search"
        }
    }
}

@MainActor
private struct BWRLargeCardEditorSheet: View {
    @ObservedObject var document: BWRReferenceDocument
    let cardID: UUID
    let onDismiss: () -> Void

    @State private var draftText: String = ""
    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @State private var pendingRenameLayerID: UUID?
    @State private var pendingRenameValue: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let card {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.titlePreview)
                            .font(.system(size: 22, weight: .semibold))
                        Text(card.id.uuidString)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Done") {
                        commitDraftIfNeeded()
                        onDismiss()
                    }
                }

                Picker("Layer", selection: Binding(
                    get: { card.currentLayerID },
                    set: { newLayerID in
                        commitDraftIfNeeded()
                        document.setCurrentLayer(cardID: card.id, layerID: newLayerID)
                        reloadDraft()
                    }
                )) {
                    ForEach(card.layers) { layer in
                        Text(layer.name).tag(layer.id)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Menu("Layer") {
                        Button("Add Body Layer") {
                            commitDraftIfNeeded()
                            document.appendBodyLayer(cardID: card.id)
                        }
                        Button("Delete Current Body Layer") {
                            commitDraftIfNeeded()
                            document.deleteBodyLayer(cardID: card.id, layerID: card.currentLayerID)
                        }
                        .disabled(!(currentLayer?.kind == .body && card.layers.filter { $0.kind == .body }.count > 1))
                        Button("Rename Current Body Layer…") {
                            guard let currentLayer else { return }
                            pendingRenameLayerID = currentLayer.id
                            pendingRenameValue = currentLayer.name
                        }
                        .disabled(currentLayer?.kind != .body)
                        Divider()
                        Button("Move Layer Left") {
                            guard let currentLayer,
                                  let bodyIndex = bodyLayerIndex(for: currentLayer, in: card) else { return }
                            commitDraftIfNeeded()
                            document.moveBodyLayer(cardID: card.id, layerID: currentLayer.id, destinationBodyIndex: max(0, bodyIndex - 1))
                        }
                        .disabled(currentLayer?.kind != .body)
                        Button("Move Layer Right") {
                            guard let currentLayer,
                                  let bodyIndex = bodyLayerIndex(for: currentLayer, in: card) else { return }
                            let maxBodyIndex = max(0, card.layers.filter { $0.kind == .body }.count - 1)
                            commitDraftIfNeeded()
                            document.moveBodyLayer(cardID: card.id, layerID: currentLayer.id, destinationBodyIndex: min(maxBodyIndex, bodyIndex + 1))
                        }
                        .disabled(currentLayer?.kind != .body)
                    }

                    Menu("Color") {
                        ForEach(BWRCardBuddyBoardThemeGuardrail.cardSwatches) { swatch in
                            Button(swatch.name) {
                                document.applyCardColor(cardID: card.id, colorHex: swatch.hex)
                            }
                        }
                    }

                    Spacer()

                    Button("Split") {
                        _ = document.splitCard(
                            cardID: card.id,
                            layerID: card.currentLayerID,
                            committedMarkdown: draftText,
                            atUTF16Location: selectedRange.location
                        )
                        onDismiss()
                    }
                }

                if pendingRenameLayerID != nil {
                    HStack(spacing: 10) {
                        TextField("Layer name", text: $pendingRenameValue)
                            .textFieldStyle(.roundedBorder)
                        Button("Apply") {
                            guard let pendingRenameLayerID else { return }
                            let trimmed = pendingRenameValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            commitDraftIfNeeded()
                            document.renameLayer(cardID: card.id, layerID: pendingRenameLayerID, newName: trimmed)
                            self.pendingRenameLayerID = nil
                        }
                        Button("Cancel") {
                            pendingRenameLayerID = nil
                        }
                    }
                }

                BWRCardMarkdownEditor(
                    text: $draftText,
                    selectedRange: $selectedRange,
                    fontSize: 16,
                    autoFocus: true,
                    onSplit: { _, range in
                        _ = document.splitCard(
                            cardID: card.id,
                            layerID: card.currentLayerID,
                            committedMarkdown: draftText,
                            atUTF16Location: range.location
                        )
                        onDismiss()
                    },
                    onEscape: {
                        onDismiss()
                    }
                )
                .frame(minHeight: BWRCardBuddyLargeEditorChrome.minimumEditorHeight, idealHeight: 520, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: BWRCardBuddyLargeEditorChrome.paperCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: BWRCardBuddyLargeEditorChrome.paperCornerRadius, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
            } else {
                Text("Card not found.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onAppear {
            reloadDraft()
        }
        .onChange(of: card?.currentLayerID) { _, _ in
            reloadDraft()
        }
    }

    private var card: BWRCard? {
        document.liveCards.first(where: { $0.id == cardID })
    }

    private var currentLayer: BWRCardLayer? {
        guard let card else { return nil }
        return card.layers.first(where: { $0.id == card.currentLayerID })
    }

    private func reloadDraft() {
        draftText = currentLayer?.markdown ?? ""
        selectedRange = NSRange(location: 0, length: 0)
    }

    private func commitDraftIfNeeded() {
        guard let card,
              let currentLayer,
              currentLayer.markdown != draftText else {
            return
        }
        document.applyLayerMarkdown(cardID: card.id, layerID: currentLayer.id, markdown: draftText)
    }

    private func bodyLayerIndex(for layer: BWRCardLayer, in card: BWRCard) -> Int? {
        card.layers.filter { $0.kind == .body }.firstIndex(where: { $0.id == layer.id })
    }
}
