import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - ScenarioWriterView (메인 struct + 프로퍼티 + body + 레이아웃)

struct ScenarioWriterView: View {
    @Environment(\.openWindow) var openWindow
    enum MainSelectionActiveEdge {
        case start
        case end
    }

    @EnvironmentObject var store: FileStore
    @EnvironmentObject var referenceCardStore: ReferenceCardStore
    @ObservedObject var scenario: Scenario

    @AppStorage("fontSize") var fontSize: Double = 14.0
    @AppStorage("appearance") var appearance: String = "dark"
    @AppStorage("backgroundColorHex") var backgroundColorHex: String = "F4F2EE"
    @AppStorage("darkBackgroundColorHex") var darkBackgroundColorHex: String = "111418"
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
    @AppStorage("mainWorkspaceZoomScale") var mainWorkspaceZoomScale: Double = 1.0
    @AppStorage("geminiModelID") var geminiModelID: String = "gemini-3-pro-preview"

    @State var activeCardID: UUID? = nil
    @State var activeAncestorIDs: Set<UUID> = []
    @State var activeDescendantIDs: Set<UUID> = []
    @State var activeSiblingIDs: Set<UUID> = []
    @State var lastActiveCardID: UUID? = nil
    @State var selectedCardIDs: Set<UUID> = []
    @State var suppressAutoScrollOnce: Bool = false
    @State var suppressHorizontalAutoScroll: Bool = false
    @State var maxLevelCount: Int = 0
    @State var lastWorkspaceRootSize: CGSize = .zero

    @State var editingCardID: UUID? = nil
    @State var showDeleteAlert: Bool = false
    @State var lastScrolledLevel: Int = 0
    @State var activeDropTarget: DropTarget? = nil
    
    @State var showTimeline: Bool = false
    @State var showAIChat: Bool = false
    @State var aiChatMessages: [AIChatMessage] = []
    @State var aiChatInput: String = ""
    @State var isAIChatLoading: Bool = false
    @FocusState var isAIChatInputFocused: Bool

    @State var exportMessage: String? = nil
    @State var showExportAlert: Bool = false

    @State var searchText: String = ""
    @FocusState var isSearchFocused: Bool
    @FocusState var isNamedSnapshotSearchFocused: Bool
    @FocusState var focusModeEditorCardID: UUID?

    // --- 히스토리 관련 상태 ---
    @State var historyIndex: Double = 0
    @State var isPreviewingHistory: Bool = false
    @State var previewDiffs: [SnapshotDiff] = []
    @State var showHistoryBar: Bool = false
    @State var showCheckpointDialog: Bool = false
    @State var newCheckpointName: String = ""
    @State var newCheckpointNote: String = ""
    @State var snapshotNoteSearchText: String = ""
    @State var historySelectedNamedSnapshotNoteCardID: UUID? = nil
    @State var isNamedSnapshotNoteEditing: Bool = false
    @State var editingSnapshotID: UUID? = nil
    @State var editedSnapshotName: String = ""
    @State var historyKeyMonitor: Any? = nil
    @State var focusModeKeyMonitor: Any? = nil
    @State var focusModeScrollMonitor: Any? = nil
    @State var mainNavKeyMonitor: Any? = nil
    @State var isApplyingUndo: Bool = false
    @State var editingIsNewCard: Bool = false
    @State var editingStartContent: String = ""
    @State var editingStartState: ScenarioState? = nil
    @State var pendingNewCardPrevState: ScenarioState? = nil
    @State var showFocusMode: Bool = false
    @State var focusModeNextCardScrollAnchor: UnitPoint? = nil
    @State var focusModeNextCardScrollAnimated: Bool = true
    @State var suppressFocusModeScrollOnce: Bool = false
    @State var focusPendingProgrammaticBeginEditCardID: UUID? = nil
    @State var focusModeCaretRequestID: Int = 0
    @State var focusModeEntryScrollTick: Int = 0
    @State var focusModeSelectionObserver: NSObjectProtocol? = nil
    @State var mainSelectionObserver: NSObjectProtocol? = nil
    @State var mainCaretEnsureWorkItem: DispatchWorkItem? = nil
    @State var focusExcludedResponderObjectID: ObjectIdentifier? = nil
    @State var focusExcludedResponderUntil: Date = .distantPast
    @State var focusResponderCardByObjectID: [ObjectIdentifier: UUID] = [:]
    @State var focusDeleteSelectionLockedCardID: UUID? = nil
    @State var focusDeleteSelectionLockUntil: Date = .distantPast
    @State var pendingActiveCardID: UUID? = nil
    @State var pendingMainCanvasRestoreCardID: UUID? = nil
    @State var mainCaretLocationByCardID: [UUID: Int] = [:]
    @State var mainCaretRestoreRequestID: Int = 0
    @State var mainLineSpacingAppliedCardID: UUID? = nil
    @State var mainLineSpacingAppliedValue: CGFloat = -1
    @State var mainLineSpacingAppliedResponderID: ObjectIdentifier? = nil
    @State var suppressMainFocusRestoreAfterFinishEditing: Bool = false
    @State var mainSelectionLastCardID: UUID? = nil
    @State var mainSelectionLastLocation: Int = -1
    @State var mainSelectionLastLength: Int = -1
    @State var mainSelectionLastTextLength: Int = -1
    @State var mainSelectionLastResponderID: ObjectIdentifier? = nil
    @State var mainSelectionActiveEdge: MainSelectionActiveEdge = .end
    @State var mainCaretEnsureLastScheduledAt: Date = .distantPast
    @State var pendingFocusModeEntryCaretHint: (cardID: UUID, location: Int)? = nil
    @State var focusCaretEnsureWorkItem: DispatchWorkItem? = nil
    @State var focusCaretPendingTypewriter: Bool = false
    @State var focusTypewriterDeferredUntilCompositionEnd: Bool = false
    @State var focusObservedBodyHeightByCardID: [UUID: CGFloat] = [:]
    @State var focusSelectionLastCardID: UUID? = nil
    @State var focusSelectionLastLocation: Int = -1
    @State var focusSelectionLastLength: Int = -1
    @State var focusSelectionLastTextLength: Int = -1
    @State var focusSelectionLastResponderID: ObjectIdentifier? = nil
    @State var focusCaretEnsureLastScheduledAt: Date = .distantPast
    @State var focusProgrammaticCaretExpectedCardID: UUID? = nil
    @State var focusProgrammaticCaretExpectedLocation: Int = -1
    @State var focusProgrammaticCaretSelectionIgnoreUntil: Date = .distantPast
    @State var undoStack: [ScenarioState] = []
    @State var redoStack: [ScenarioState] = []
    @State var mainTypingUndoStack: [ScenarioState] = []
    @State var mainTypingRedoStack: [ScenarioState] = []
    @State var mainTypingCoalescingBaseState: ScenarioState? = nil
    @State var mainTypingCoalescingCardID: UUID? = nil
    @State var mainTypingLastEditAt: Date = .distantPast
    @State var mainTypingIdleFinalizeWorkItem: DispatchWorkItem? = nil
    @State var mainPendingReturnBoundary: Bool = false
    @State var mainLastCommittedContentByCard: [UUID: String] = [:]
    @State var mainProgrammaticContentSuppressUntil: Date = .distantPast
    @State var pendingMainUndoCaretHint: (cardID: UUID, location: Int)? = nil
    @State var focusUndoStack: [ScenarioState] = []
    @State var focusRedoStack: [ScenarioState] = []
    @State var focusTypingCoalescingBaseState: ScenarioState? = nil
    @State var focusTypingCoalescingCardID: UUID? = nil
    @State var focusTypingLastEditAt: Date = .distantPast
    @State var focusTypingIdleFinalizeWorkItem: DispatchWorkItem? = nil
    @State var focusPendingReturnBoundary: Bool = false
    @State var focusLastCommittedContentByCard: [UUID: String] = [:]
    @State var focusProgrammaticContentSuppressUntil: Date = .distantPast
    @State var pendingFocusUndoCaretHint: (cardID: UUID, location: Int)? = nil
    @State var focusUndoSelectionEnsureSuppressed: Bool = false
    @State var focusUndoSelectionEnsureRequestID: Int? = nil
    @State var focusOffsetNormalizationLastAt: Date = .distantPast
    @State var aiOptionsSheetAction: AICardAction? = nil
    @State var aiSelectedGenerationOptions: Set<AIGenerationOption> = [.balanced]
    @State var aiIsGenerating: Bool = false
    @State var aiStatusMessage: String? = nil
    @State var aiStatusIsError: Bool = false
    @State var aiCandidateParentID: UUID? = nil
    @State var aiCandidateCardIDs: [UUID] = []
    @State var aiCandidateAction: AICardAction? = nil
    @State var dictationRecorder: LiveSpeechDictationRecorder? = nil
    @State var dictationIsRecording: Bool = false
    @State var dictationIsProcessing: Bool = false
    @State var dictationTargetParentID: UUID? = nil
    @State var mainNoChildRightArmCardID: UUID? = nil
    @State var mainNoChildRightArmAt: Date = .distantPast
    @State var mainCardHeights: [UUID: CGFloat] = [:]
    @State var mainCardWidths: [UUID: CGFloat] = [:]
    @State var mainBottomRevealCardID: UUID? = nil
    @State var mainBottomRevealTick: Int = 0
    @State var mainEditTabArmCardID: UUID? = nil
    @State var mainEditTabArmAt: Date = .distantPast
    @State var copiedCardTreePayloadData: Data? = nil
    @State var cutCardRootIDs: [UUID] = []
    @State var cutCardSourceScenarioID: UUID? = nil
    @State var historyBarMeasuredHeight: CGFloat = 0
    @State var historyRetentionLastAppliedCount: Int = 0
    @State var caretEnsureBurstWorkItems: [DispatchWorkItem] = []
    @FocusState var isNamedSnapshotNoteEditorFocused: Bool
    let focusTypingIdleInterval: TimeInterval = 1.5
    let focusOffsetNormalizationMinInterval: TimeInterval = 0.08
    let focusCaretSelectionEnsureMinInterval: TimeInterval = 0.016
    let mainCaretSelectionEnsureMinInterval: TimeInterval = 0.016
    let mainEditDoubleTabInterval: TimeInterval = 0.45
    let mainNoChildRightDoublePressInterval: TimeInterval = 0.55
    let maxUndoCount: Int = 200
    let maxMainTypingUndoCount: Int = 1200
    let maxFocusUndoCount: Int = 1200
    let deltaSnapshotFullCheckpointInterval: Int = 30
    let historyRetentionMinimumCount: Int = 180
    let historyRetentionApplyStride: Int = 12
    let historyPromotionLargeEditScoreThreshold: Int = 1200
    let historyPromotionChangedCardsThreshold: Int = 8
    let historyPromotionSessionGapThreshold: TimeInterval = 60 * 15
    var quickEaseAnimation: Animation {
        .timingCurve(0.25, 0.10, 0.25, 1.00, duration: 0.24)
    }

    let timelineWidth: CGFloat = 416
    let historyOverlayBottomInset: CGFloat = 88
    let columnWidth: CGFloat = 416

    var clampedMainWorkspaceZoomScale: CGFloat {
        CGFloat(min(max(mainWorkspaceZoomScale, 0.70), 1.60))
    }

    var isFullscreen: Bool {
        NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false
    }

    var isDarkAppearanceActive: Bool {
        if appearance == "dark" { return true }
        if appearance == "light" { return false }
        if let best = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
            return best == .darkAqua
        }
        return true
    }

    @FocusState var isMainViewFocused: Bool

    struct LevelData {
        let cards: [SceneCard]
        let parent: SceneCard?
    }

    var activeCategory: String? {
        if isPreviewingHistory { return nil }
        guard let id = activeCardID, let card = findCard(by: id) else { return nil }
        return card.category
    }

    var isActiveCardRoot: Bool {
        guard let id = activeCardID else { return false }
        return scenario.rootCards.contains { $0.id == id }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            configuredWorkspaceRoot(for: geometry)
        }
    }

    func configuredWorkspaceRoot(for geometry: GeometryProxy) -> some View {
        let focusedLayout = workspaceLayout(for: geometry)
            .focusable()
            .focused($isMainViewFocused)
            .focusEffectDisabled()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: WorkspaceRootSizePreferenceKey.self, value: proxy.size)
                }
            )

        let lifecycleBound = focusedLayout
            .onAppear {
                if activeCardID == nil, let first = scenario.rootCards.first { changeActiveCard(to: first) }
                isMainViewFocused = true
                if scenario.sortedSnapshots.isEmpty { takeSnapshot(force: true) }
                let snapshotCountBeforeRetention = scenario.snapshots.count
                applyHistoryRetentionPolicyIfNeeded(force: true)
                if scenario.snapshots.count < snapshotCountBeforeRetention {
                    store.saveAll()
                }
                historyIndex = Double(max(0, scenario.sortedSnapshots.count - 1))
                maxLevelCount = max(maxLevelCount, getLevelsWithParents().count)
                updateHistoryKeyMonitor()
            }
            .onChange(of: showHistoryBar) { _, isShown in
                updateHistoryKeyMonitor()
                requestMainCanvasRestoreForHistoryToggle()
                if isShown {
                    isSearchFocused = false
                    isNamedSnapshotSearchFocused = false
                    isNamedSnapshotNoteEditing = false
                    isNamedSnapshotNoteEditorFocused = false
                    syncNamedSnapshotNoteForCurrentSelection(focusEditor: false)
                } else {
                    historySelectedNamedSnapshotNoteCardID = nil
                    snapshotNoteSearchText = ""
                    isSearchFocused = false
                    isNamedSnapshotSearchFocused = false
                    isNamedSnapshotNoteEditing = false
                    isNamedSnapshotNoteEditorFocused = false
                }
            }
            .onChange(of: Int(historyIndex)) { _, _ in
                guard showHistoryBar else { return }
                isNamedSnapshotNoteEditing = false
                isNamedSnapshotNoteEditorFocused = false
                syncNamedSnapshotNoteForCurrentSelection(focusEditor: false)
                let snapshots = scenario.sortedSnapshots
                let maxIndex = max(0, snapshots.count - 1)
                let currentIndex = min(max(Int(historyIndex), 0), maxIndex)
                if currentIndex < maxIndex {
                    enterPreviewMode(at: currentIndex)
                } else if isPreviewingHistory || !previewDiffs.isEmpty {
                    isPreviewingHistory = false
                    previewDiffs = []
                }
            }
            .onChange(of: activeCardID) { _, newID in
                synchronizeActiveRelationState(for: newID)
            }
            .onChange(of: scenario.cardsVersion) { _, _ in
                synchronizeActiveRelationState(for: activeCardID)
                pruneAICandidateTracking()
            }
            .onPreferenceChange(WorkspaceRootSizePreferenceKey.self) { size in
                let widthChanged = abs(size.width - lastWorkspaceRootSize.width) > 0.5
                let heightChanged = abs(size.height - lastWorkspaceRootSize.height) > 0.5
                guard widthChanged || heightChanged else { return }
                lastWorkspaceRootSize = size
            }
            .onDisappear {
                stopHistoryKeyMonitor()
                stopFocusModeKeyMonitor()
                stopFocusModeScrollMonitor()
                stopFocusModeCaretMonitor()
                stopMainNavKeyMonitor()
                stopMainCaretMonitor()
                stopDictationRecording(discardAudio: true)
            }
            .onChange(of: showFocusMode) { _, isOn in
                FocusMonitorRecorder.shared.record("focus.toggle", reason: "showFocusMode-onChange") {
                    [
                        "entering": isOn ? "true" : "false",
                        "activeCardID": activeCardID?.uuidString ?? "nil",
                        "editingCardID": editingCardID?.uuidString ?? "nil",
                        "focusModeEditorCardID": focusModeEditorCardID?.uuidString ?? "nil"
                    ]
                }
                if isOn {
                    finalizeMainTypingCoalescing(reason: "focus-enter")
                    resetMainTypingCoalescing()
                    resetFocusTypingCoalescing()
                    focusLastCommittedContentByCard = Dictionary(uniqueKeysWithValues: scenario.cards.map { ($0.id, $0.content) })
                    startFocusModeKeyMonitor()
                    startFocusModeScrollMonitor()
                    startFocusModeCaretMonitor()
                    guard let editingID = editingCardID else { return }
                    DispatchQueue.main.async {
                        focusModeEntryScrollTick += 1
                    }
                    DispatchQueue.main.async {
                        guard showFocusMode else { return }
                        guard editingCardID == editingID else { return }
                        if let card = findCard(by: editingID) {
                            beginFocusModeEditing(card, cursorToEnd: false)
                        } else {
                            focusModeEditorCardID = editingID
                        }
                    }
                } else {
                    finalizeFocusTypingCoalescing(reason: "focus-exit")
                    stopFocusModeKeyMonitor()
                    stopFocusModeScrollMonitor()
                    stopFocusModeCaretMonitor()
                }
            }
            .onChange(of: editingCardID) { oldID, newID in
                guard !showFocusMode else { return }
                guard focusModeEditorCardID == nil else { return }
                clearMainEditTabArm()
                if oldID != newID {
                    finalizeMainTypingCoalescing(reason: newID == nil ? "edit-end" : "typing-card-switch")
                }
                if let oldID {
                    rememberMainCaretLocation(for: oldID)
                }
                guard let newID else {
                    resetMainTypingCoalescing()
                    pendingMainUndoCaretHint = nil
                    mainLineSpacingAppliedCardID = nil
                    mainLineSpacingAppliedValue = -1
                    mainLineSpacingAppliedResponderID = nil
                    mainSelectionLastCardID = nil
                    mainSelectionLastLocation = -1
                    mainSelectionLastLength = -1
                    mainSelectionLastTextLength = -1
                    mainSelectionLastResponderID = nil
                    mainSelectionActiveEdge = .end
                    return
                }
                mainSelectionLastCardID = nil
                mainSelectionLastLocation = -1
                mainSelectionLastLength = -1
                mainSelectionLastTextLength = -1
                mainSelectionLastResponderID = nil
                mainSelectionActiveEdge = .end
                resetMainTypingCoalescing()
                if let card = findCard(by: newID) {
                    mainLastCommittedContentByCard[newID] = card.content
                }
                requestMainCaretRestore(for: newID)
                scheduleMainEditorLineSpacingApplyBurst(for: newID)
                requestMainCaretEnsure(delay: 0.03)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    guard !showFocusMode else { return }
                    guard editingCardID == newID else { return }
                    if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
                        normalizeMainEditorTextViewOffsetIfNeeded(textView, reason: "edit-change")
                    }
                }
            }
            .onChange(of: mainCardLineSpacingValue) { _, _ in
                guard !showFocusMode else { return }
                applyMainEditorLineSpacingIfNeeded(forceApplyToFullText: true)
                requestMainCaretEnsure(delay: 0.0)
            }
            .onChange(of: focusModeEditorCardID) { _, newID in
                guard showFocusMode else { return }
                guard let id = newID else { return }
                FocusMonitorRecorder.shared.record("focus.editor.card.change", reason: "focusModeEditorCardID-onChange") {
                    [
                        "focusModeEditorCardID": id.uuidString,
                        "editingCardID": editingCardID?.uuidString ?? "nil",
                        "activeCardID": activeCardID?.uuidString ?? "nil"
                    ]
                }
                if let lockedID = focusDeleteSelectionLockedCardID {
                    if Date() >= focusDeleteSelectionLockUntil {
                        clearFocusDeleteSelectionLock()
                    } else if id != lockedID {
                        return
                    }
                }
                guard id != editingCardID else { return }
                guard let card = findCard(by: id) else { return }
                activateFocusModeCardFromClick(card)
            }

        let commandBound = lifecycleBound
            .onReceive(NotificationCenter.default.publisher(for: .waUndoRequested)) { _ in
                if isPreviewingHistory || showHistoryBar || isSearchFocused { return }
                if showFocusMode {
                    performFocusUndo()
                } else {
                    if performMainTypingUndo() {
                        return
                    }
                    performUndo()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .waRedoRequested)) { _ in
                if isPreviewingHistory || showHistoryBar || isSearchFocused { return }
                if showFocusMode {
                    performFocusRedo()
                } else {
                    if performMainTypingRedo() {
                        return
                    }
                    performRedo()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .waToggleFocusModeRequested)) { _ in
                if isPreviewingHistory || showHistoryBar { return }
                toggleFocusMode()
            }
            .onKeyPress(phases: [.down, .repeat]) { press in
                if isPreviewingHistory { return .ignored }
                return handleGlobalKeyPress(press)
            }
            .alert("카드 삭제", isPresented: $showDeleteAlert) {
                let selectedCards = selectedCardsForDeletion()
                let hasChildren = selectedCards.contains { !$0.children.isEmpty }
                if hasChildren {
                    Button("취소", role: .cancel) { isMainViewFocused = true }
                        .keyboardShortcut(.defaultAction)
                    Button("삭제", role: .destructive) { performDeleteSelection() }
                } else {
                    Button("삭제", role: .destructive) { performDeleteSelection() }
                        .keyboardShortcut(.defaultAction)
                    Button("취소", role: .cancel) { isMainViewFocused = true }
                        .keyboardShortcut(.cancelAction)
                }
            } message: {
                let selectedCards = selectedCardsForDeletion()
                if selectedCards.count > 1 {
                    Text("선택한 카드들을 삭제(또는 내용 삭제)하시겠습니까?")
                } else if let cardToDelete = selectedCards.first {
                    let hasChildren = !cardToDelete.children.isEmpty
                    Text(hasChildren ? "이 카드는 하위 카드를 가지고 있습니다. 삭제하면 하위 카드까지 함께 삭제됩니다. 계속하시겠습니까?" : "카드를 삭제하시겠습니까?")
                }
            }
            .task {
                startMainNavKeyMonitor()
                startMainCaretMonitor()
            }
            .sheet(isPresented: $showCheckpointDialog) {
                namedCheckpointSheet
            }
            .sheet(item: $aiOptionsSheetAction) { action in
                aiOptionsSheet(action: action)
            }
            .alert("알림", isPresented: $showExportAlert) {
                Button("확인", role: .cancel) { isMainViewFocused = true }
            } message: {
                Text(exportMessage ?? "")
            }

        return commandBound
    }

    // MARK: - Layout

    @ViewBuilder
    func workspaceLayout(for geometry: GeometryProxy) -> some View {
        let timelinePanelVisible = (showTimeline || showAIChat) && !showHistoryBar && !showFocusMode
        let availableWidth = geometry.size.width - (timelinePanelVisible ? timelineWidth : 0)

        if showHistoryBar && !showFocusMode {
            ZStack(alignment: .topTrailing) {
                primaryWorkspaceColumn(size: geometry.size, availableWidth: geometry.size.width)
                namedSnapshotManagerOverlay(containerHeight: geometry.size.height)
                    .transition(.move(edge: .trailing))
            }
        } else {
            HStack(spacing: 0) {
                primaryWorkspaceColumn(size: geometry.size, availableWidth: availableWidth)
                if !showFocusMode {
                    trailingWorkspacePanel
                }
            }
        }
    }

    @ViewBuilder
    func primaryWorkspaceColumn(size: CGSize, availableWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            ZStack {
                if showFocusMode {
                    focusModeCanvas(size: size)
                        .transition(.opacity)
                        .zIndex(10)
                } else {
                    mainCanvasWithOptionalZoom(size: size, availableWidth: availableWidth)
                    workspaceTopToolbar
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showHistoryBar && !showFocusMode {
                bottomHistoryBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .onPreferenceChange(HistoryBarHeightPreferenceKey.self) { newHeight in
            historyBarMeasuredHeight = newHeight
        }
    }

    @ViewBuilder
    func mainCanvasWithOptionalZoom(size: CGSize, availableWidth: CGFloat) -> some View {
        let shouldApplyZoom = !showFocusMode && !showHistoryBar
        let scale = shouldApplyZoom ? clampedMainWorkspaceZoomScale : 1.0
        if abs(scale - 1.0) < 0.001 {
            mainCanvas(size: size, availableWidth: availableWidth)
        } else {
            mainCanvas(size: size, availableWidth: availableWidth)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(
                    width: availableWidth / scale,
                    height: size.height / scale,
                    alignment: .topLeading
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        }
    }

    var workspaceTopToolbar: some View {
        VStack {
            HStack(spacing: 12) {
                Spacer()
                checkpointToolbarButton
                historyToolbarButton
                dictationToolbarButton
                aiChatToolbarButton
                timelineToolbarButton
            }
            if dictationIsRecording || dictationIsProcessing {
                HStack(spacing: 6) {
                    Spacer()
                    Circle()
                        .fill(dictationIsRecording ? Color.red : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(dictationIsRecording ? "받아쓰기 진행 중" : "받아쓰기 처리 중")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background((dictationIsRecording ? Color.red.opacity(0.90) : Color.orange.opacity(0.90)))
                        .clipShape(Capsule())
                    Spacer().frame(width: 20)
                }
                .padding(.top, 4)
                .transition(.opacity)
            } else if aiStatusIsError,
                      let message = aiStatusMessage,
                      message.contains("받아쓰기") || message.localizedCaseInsensitiveContains("whisper") || message.contains("마이크") {
                HStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                    Text(message)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer().frame(width: 20)
                }
                .padding(.top, 4)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.red.opacity(0.92))
                .clipShape(Capsule())
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 8)
                .transition(.opacity)
            }
            Spacer()
        }
        .ignoresSafeArea()
        .padding(.top, isFullscreen ? 24 : 0)
    }

    var checkpointToolbarButton: some View {
        Button {
            newCheckpointName = ""
            newCheckpointNote = ""
            showCheckpointDialog = true
        } label: {
            Image(systemName: "flag.fill")
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .foregroundColor(.orange)
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
        .help("이름 있는 분기점 만들기")
    }

    var historyToolbarButton: some View {
        Button {
            withAnimation(quickEaseAnimation) {
                if showHistoryBar {
                    exitPreviewMode()
                    showHistoryBar = false
                } else {
                    showTimeline = false
                    showAIChat = false
                    showHistoryBar = true
                    historyIndex = Double(max(0, scenario.sortedSnapshots.count - 1))
                    isPreviewingHistory = false
                }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .padding(8)
                .background(showHistoryBar ? Color.accentColor : Color.clear)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .foregroundColor(showHistoryBar ? .white : .primary)
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
        .help("히스토리 타임라인 열기")
    }

    var dictationToolbarButton: some View {
        let isBusy = dictationIsProcessing || aiIsGenerating
        return Button {
            toggleDictationRecording()
        } label: {
            Group {
                if dictationIsRecording {
                    Image(systemName: "stop.fill")
                } else if dictationIsProcessing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "mic.fill")
                }
            }
            .padding(8)
            .background(dictationIsRecording ? Color.red : (isBusy ? Color.accentColor.opacity(0.85) : Color.clear))
            .background(.ultraThinMaterial)
            .clipShape(Circle())
            .foregroundColor((dictationIsRecording || isBusy) ? .white : .primary)
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
        .disabled(dictationIsProcessing || aiIsGenerating || (activeCardID == nil && !dictationIsRecording))
        .help(dictationIsRecording ? "받아쓰기 중지 후 요약 카드 생성" : "받아쓰기 시작")
    }
    
    var aiChatToolbarButton: some View {
        Button {
            toggleAIChat()
        } label: {
            Image(systemName: "sparkles.tv")
                .padding(8)
                .background(showAIChat ? Color.accentColor : Color.clear)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .foregroundColor(showAIChat ? .white : .primary)
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
        .help("AI와 시나리오 상담하기")
    }

    var timelineToolbarButton: some View {
        Button {
            if showTimeline {
                toggleTimeline()
            } else {
                withAnimation(quickEaseAnimation) {
                    showHistoryBar = false
                    showAIChat = false
                    exitPreviewMode()
                    showTimeline = true
                }
            }
        } label: {
            Image(systemName: showTimeline ? "sidebar.right" : "sidebar.left")
                .padding(8)
                .background(showTimeline ? Color.accentColor : Color.clear)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .foregroundColor(showTimeline ? .white : .primary)
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
        .padding(.trailing, 20)
        .help("전체 카드 목록 열기")
    }
    
    func toggleAIChat() {
        withAnimation(quickEaseAnimation) {
            showAIChat.toggle()
            if showAIChat {
                showTimeline = false
                showHistoryBar = false
                exitPreviewMode()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isMainViewFocused = true
                }
            }
        }
    }

    @ViewBuilder
    var trailingWorkspacePanel: some View {
        if showTimeline {
            Divider().background(appearance == "light" ? Color.black.opacity(0.1) : Color.white.opacity(0.15))
            timelineView
                .frame(width: timelineWidth)
                .background(resolvedTimelineBackgroundColor())
                .transition(.move(edge: .trailing))
        } else if showAIChat {
            Divider().background(appearance == "light" ? Color.black.opacity(0.1) : Color.white.opacity(0.15))
            aiChatView
                .frame(width: timelineWidth)
                .background(resolvedTimelineBackgroundColor())
                .transition(.move(edge: .trailing))
        }
    }

    func namedSnapshotManagerOverlay(containerHeight: CGFloat) -> some View {
        let bottomInset = historyBarMeasuredHeight > 0 ? historyBarMeasuredHeight : historyOverlayBottomInset
        return HStack(spacing: 0) {
            Divider().background(appearance == "light" ? Color.black.opacity(0.1) : Color.white.opacity(0.15))
            namedSnapshotManagerView
                .frame(width: timelineWidth, height: max(320, containerHeight - bottomInset))
                .background(resolvedTimelineBackgroundColor())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.bottom, bottomInset)
    }

    // MARK: - Main Canvas

    @ViewBuilder
    func mainCanvas(size: CGSize, availableWidth: CGFloat) -> some View {
        ZStack {
            resolvedBackgroundColor()
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { if !isPreviewingHistory { deselectAll(); isMainViewFocused = true } }

            ScrollViewReader { hProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !isPreviewingHistory {
                                    finishEditing()
                                    selectedCardIDs = []
                                    isMainViewFocused = true
                                }
                            }
                    HStack(alignment: .top, spacing: 0) {
                        Spacer().frame(width: availableWidth / 2)
                        if isPreviewingHistory {
                            let previewLevels = getPreviewLevels()
                            ForEach(Array(previewLevels.enumerated()), id: \.offset) { index, diffs in
                                previewColumn(for: diffs, level: index, screenHeight: size.height)
                                        .id("preview-col-\(index)")
                                }
                            } else {
                                let levelsData = getLevelsWithParents()
                                ForEach(Array(levelsData.enumerated()), id: \.offset) { index, data in
                                    let filteredCards: [SceneCard] = {
                                        if index <= 1 || isActiveCardRoot {
                                            return data.cards
                                        }
                                        guard let category = activeCategory else {
                                            return data.cards
                                        }
                                        return data.cards.filter { $0.category == category }
                                    }()
                                    if index <= 1 || !filteredCards.isEmpty {
                                        column(for: filteredCards, level: index, parent: data.parent, screenHeight: size.height)
                                            .id(index)
                                    } else {
                                        Color.clear.frame(width: columnWidth)
                                    }
                                }
                                if maxLevelCount > levelsData.count {
                                    ForEach(levelsData.count..<maxLevelCount, id: \.self) { _ in
                                        Color.clear.frame(width: columnWidth)
                                    }
                                }
                        }
                        Spacer().frame(width: availableWidth / 2)
                    }
                    .background(
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !isPreviewingHistory {
                                    finishEditing()
                                    selectedCardIDs = []
                                    isMainViewFocused = true
                                }
                            }
                    )
                }
                }
                .onChange(of: Int(historyIndex)) { _, _ in
                    if isPreviewingHistory {
                        withAnimation(quickEaseAnimation) {
                            autoScrollToChanges(hProxy: hProxy)
                        }
                    }
                }
                .onChange(of: activeCardID) { _, newID in
                    guard let id = newID else { return }
                    if showFocusMode { return }
                    if suppressHorizontalAutoScroll { return }
                    if suppressAutoScrollOnce {
                        suppressAutoScrollOnce = false
                        return
                    }
                    if !isPreviewingHistory {
                        scrollToColumnIfNeeded(
                            targetCardID: id,
                            proxy: hProxy,
                            availableWidth: availableWidth
                        )
                    }
                }
                .onChange(of: pendingMainCanvasRestoreCardID) { _, _ in
                    restoreMainCanvasPositionIfNeeded(proxy: hProxy, availableWidth: availableWidth)
                }
                .onAppear {
                    restoreMainCanvasPositionIfNeeded(proxy: hProxy, availableWidth: availableWidth)
                }
            }
        }
        .allowsHitTesting(true)
    }
}
