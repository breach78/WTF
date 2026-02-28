import SwiftUI
import UniformTypeIdentifiers
import AppKit

final class WeakTextViewBox {
    weak var textView: NSTextView?
}

// MARK: - ScenarioWriterView (메인 struct + 프로퍼티 + body + 레이아웃)

struct ScenarioWriterView: View {
    @Environment(\.openWindow) var openWindow
    enum MainSelectionActiveEdge {
        case start
        case end
    }

    struct AICandidateTrackingState {
        var parentID: UUID? = nil
        var cardIDs: [UUID] = []
        var action: AICardAction? = nil
    }

    struct InactivePaneSnapshotState {
        var levelsData: [LevelData] = []
        var maxLevelCount: Int = 0
        var syncWorkItem: DispatchWorkItem? = nil
    }

    @EnvironmentObject var store: FileStore
    @EnvironmentObject var referenceCardStore: ReferenceCardStore
    @ObservedObject var scenario: Scenario
    let showWorkspaceTopToolbar: Bool
    let splitModeEnabled: Bool
    let splitPaneID: Int
    @State var isSplitPaneActive: Bool

    init(
        scenario: Scenario,
        showWorkspaceTopToolbar: Bool = true,
        splitModeEnabled: Bool = false,
        splitPaneID: Int = 2
    ) {
        self._scenario = ObservedObject(wrappedValue: scenario)
        self.showWorkspaceTopToolbar = showWorkspaceTopToolbar
        self.splitModeEnabled = splitModeEnabled
        self.splitPaneID = splitPaneID
        self._isSplitPaneActive = State(initialValue: !splitModeEnabled || splitPaneID == 2)
    }

    @AppStorage("fontSize") var fontSize: Double = 14.0
    @AppStorage("appearance") var appearance: String = "dark"
    @AppStorage("backgroundColorHex") var backgroundColorHex: String = "F4F2EE"
    @AppStorage("darkBackgroundColorHex") var darkBackgroundColorHex: String = "111418"
    @AppStorage("cardActiveColorHex") var cardActiveColorHex: String = "BFD7FF"
    @AppStorage("darkCardActiveColorHex") var darkCardActiveColorHex: String = "2A3A4E"
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
    @AppStorage("geminiModelID") var geminiModelID: String = "gemini-3.1-pro-preview"
    @AppStorage("focusModeWindowBackgroundActive") var focusModeWindowBackgroundActive: Bool = false
    @AppStorage("autoBackupEnabledOnQuit") var autoBackupEnabledOnQuit: Bool = true
    @AppStorage("autoBackupDirectoryPath") var autoBackupDirectoryPath: String = ""
    @AppStorage("lastEditedScenarioID") var lastEditedScenarioID: String = ""
    @AppStorage("lastEditedCardID") var lastEditedCardID: String = ""

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
    @State var aiChatThreads: [AIChatThread] = []
    @State var activeAIChatThreadID: UUID? = nil
    @State var aiChatInput: String = ""
    @State var aiCardDigestCache: [UUID: AICardDigest] = [:]
    @State var aiEmbeddingIndexByCardID: [UUID: AIEmbeddingRecord] = [:]
    @State var aiEmbeddingIndexModelID: String = "gemini-embedding-001"
    @State var aiLastContextPreview: AIChatContextPreview? = nil
    @State var aiThreadsLoadedScenarioID: UUID? = nil
    @State var aiEmbeddingIndexLoadedScenarioID: UUID? = nil
    @State var aiThreadsSaveWorkItem: DispatchWorkItem? = nil
    @State var aiEmbeddingIndexSaveWorkItem: DispatchWorkItem? = nil
    @State var isAIChatLoading: Bool = false
    @State var aiChatRequestTask: Task<Void, Never>? = nil
    @State var aiChatActiveRequestID: UUID? = nil
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
    @State var historyPreviewSelectedCardIDs: Set<UUID> = []
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
    @State var splitPaneMouseMonitor: Any? = nil
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
    @State var aiCandidateState = AICandidateTrackingState()
    @State var aiChildSummaryLoadingCardIDs: Set<UUID> = []
    @State var dictationRecorder: LiveSpeechDictationRecorder? = nil
    @State var dictationIsRecording: Bool = false
    @State var dictationIsProcessing: Bool = false
    @State var dictationTargetParentID: UUID? = nil
    @State var dictationPopupPresented: Bool = false
    @State var dictationPopupLiveText: String = ""
    @State var dictationPopupStatusText: String = ""
    @State var dictationSourceTextViewBox = WeakTextViewBox()
    @State var mainNoChildRightArmCardID: UUID? = nil
    @State var mainNoChildRightArmAt: Date = .distantPast
    @State var mainBoundaryParentLeftArmCardID: UUID? = nil
    @State var mainBoundaryParentLeftArmAt: Date = .distantPast
    @State var mainBoundaryChildRightArmCardID: UUID? = nil
    @State var mainBoundaryChildRightArmAt: Date = .distantPast
    @State var keyboardRangeSelectionAnchorCardID: UUID? = nil
    @State var mainCardHeights: [UUID: CGFloat] = [:]
    @State var mainCardWidths: [UUID: CGFloat] = [:]
    @State var mainBottomRevealCardID: UUID? = nil
    @State var mainBottomRevealTick: Int = 0
    @State var mainEditTabArmCardID: UUID? = nil
    @State var mainEditTabArmAt: Date = .distantPast
    @State var copiedCardTreePayloadData: Data? = nil
    @State var copiedCloneCardPayloadData: Data? = nil
    @State var cutCardRootIDs: [UUID] = []
    @State var cutCardSourceScenarioID: UUID? = nil
    @State var pendingCloneCardPastePayload: CloneCardClipboardPayload? = nil
    @State var pendingCardTreePastePayload: CardTreeClipboardPayload? = nil
    @State var showCloneCardPasteDialog: Bool = false
    @State var clonePasteDialogSelection: ClonePastePlacement = .child
    @State var historyBarMeasuredHeight: CGFloat = 0
    @State var historyRetentionLastAppliedCount: Int = 0
    @State var caretEnsureBurstWorkItems: [DispatchWorkItem] = []
    @State var inactivePaneSnapshotState = InactivePaneSnapshotState()
    @State var scenarioTimestampSuppressionActive: Bool = false
    @State var editingSessionHadTextMutation: Bool = false
    @State var pendingEditEndAutoBackupWorkItem: DispatchWorkItem? = nil
    @State var isEditEndAutoBackupRunning: Bool = false
    @State var hasPendingEditEndAutoBackupRequest: Bool = false
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
    let inactivePaneSyncThrottleInterval: TimeInterval = 0.16
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

    var acceptsKeyboardInput: Bool {
        !splitModeEnabled || isSplitPaneActive
    }

    var isInactiveSplitPane: Bool {
        splitModeEnabled && !isSplitPaneActive
    }

    var shouldSuppressScenarioTimestampDuringEditing: Bool {
        acceptsKeyboardInput && editingCardID != nil
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
                .overlay {
                    if splitModeEnabled && !isSplitPaneActive {
                        Color.black
                            .opacity(0.15)
                            .allowsHitTesting(false)
                    }
                }
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
            .simultaneousGesture(TapGesture().onEnded {
                activateSplitPaneIfNeeded()
            })
            .onAppear {
                handleWorkspaceAppear()
            }
            .onChange(of: showHistoryBar) { _, isShown in
                handleHistoryBarVisibilityChange(isShown)
            }
            .onChange(of: Int(historyIndex)) { _, _ in
                handleHistoryIndexChange()
            }
            .onChange(of: activeCardID) { _, newID in
                handleActiveCardIDChange(newID)
            }
            .onChange(of: isSplitPaneActive) { _, _ in
                syncScenarioTimestampSuppressionIfNeeded()
            }
            .onChange(of: scenario.cardsVersion) { _, _ in
                handleScenarioCardsVersionChange()
            }
            .onPreferenceChange(WorkspaceRootSizePreferenceKey.self) { size in
                handleWorkspaceRootSizePreferenceChange(size)
            }
            .onDisappear {
                handleWorkspaceDisappear()
            }
            .onChange(of: showFocusMode) { _, isOn in
                handleShowFocusModeChange(isOn)
            }
            .onChange(of: focusTypewriterEnabled) { _, isOn in
                handleFocusTypewriterEnabledChange(isOn)
            }
            .onChange(of: editingCardID) { oldID, newID in
                handleEditingCardIDChange(oldID: oldID, newID: newID)
            }
            .onChange(of: mainCardLineSpacingValue) { _, _ in
                handleMainCardLineSpacingChange()
            }
            .onChange(of: focusModeEditorCardID) { _, newID in
                handleFocusModeEditorCardIDChange(newID)
            }

        let commandBound = lifecycleBound
            .onReceive(NotificationCenter.default.publisher(for: .waUndoRequested)) { _ in
                handleUndoRequestNotification()
            }
            .onReceive(NotificationCenter.default.publisher(for: .waRedoRequested)) { _ in
                handleRedoRequestNotification()
            }
            .onReceive(NotificationCenter.default.publisher(for: .waToggleFocusModeRequested)) { _ in
                handleToggleFocusModeRequestNotification()
            }
            .onReceive(NotificationCenter.default.publisher(for: .waRequestSplitPaneFocus)) { notification in
                handleSplitPaneFocusRequestNotification(notification)
            }
            .onKeyPress(phases: [.down, .repeat]) { press in
                if !acceptsKeyboardInput { return .handled }
                if showCloneCardPasteDialog { return handleClonePasteDialogKeyPress(press) }
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
                startSplitPaneMouseMonitor()
            }
            .sheet(isPresented: $showCheckpointDialog) {
                namedCheckpointSheet
            }
            .sheet(item: $aiOptionsSheetAction) { action in
                aiOptionsSheet(action: action)
            }
            .sheet(isPresented: $dictationPopupPresented) {
                dictationPopupView
            }
            .alert("알림", isPresented: $showExportAlert) {
                Button("확인", role: .cancel) { isMainViewFocused = true }
            } message: {
                Text(exportMessage ?? "")
            }
            .overlay {
                if showCloneCardPasteDialog {
                    cloneCardPasteDialogOverlay
                }
            }
            .onChange(of: showCloneCardPasteDialog) { _, isShown in
                if isShown {
                    resetClonePasteDialogSelection()
                    return
                }
                if !isShown {
                    pendingCloneCardPastePayload = nil
                    pendingCardTreePastePayload = nil
                }
            }

        return commandBound
    }

    func handleWorkspaceAppear() {
        if activeCardID == nil, let startupCard = startupActiveCard() { changeActiveCard(to: startupCard) }
        isMainViewFocused = true
        if scenario.sortedSnapshots.isEmpty { takeSnapshot(force: true) }
        let snapshotCountBeforeRetention = scenario.snapshots.count
        applyHistoryRetentionPolicyIfNeeded(force: true)
        if scenario.snapshots.count < snapshotCountBeforeRetention {
            store.saveAll()
        }
        historyIndex = Double(max(0, scenario.sortedSnapshots.count - 1))
        maxLevelCount = max(maxLevelCount, resolvedLevelsWithParents().count)
        refreshInactivePaneSnapshotNow()
        updateHistoryKeyMonitor()
        syncScenarioTimestampSuppressionIfNeeded()
    }

    func handleHistoryBarVisibilityChange(_ isShown: Bool) {
        updateHistoryKeyMonitor()
        requestMainCanvasRestoreForHistoryToggle()
        historyPreviewSelectedCardIDs = []
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

    func handleHistoryIndexChange() {
        guard showHistoryBar else { return }
        isNamedSnapshotNoteEditing = false
        isNamedSnapshotNoteEditorFocused = false
        syncNamedSnapshotNoteForCurrentSelection(focusEditor: false)
        historyPreviewSelectedCardIDs = []
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

    func handleActiveCardIDChange(_ newID: UUID?) {
        guard acceptsKeyboardInput else { return }
        synchronizeActiveRelationState(for: newID)
    }

    func handleScenarioCardsVersionChange() {
        if isInactiveSplitPane {
            scheduleInactivePaneSnapshotRefresh()
            return
        }
        synchronizeActiveRelationState(for: activeCardID)
        pruneAICandidateTracking()
    }

    func handleWorkspaceRootSizePreferenceChange(_ size: CGSize) {
        let widthChanged = abs(size.width - lastWorkspaceRootSize.width) > 0.5
        let heightChanged = abs(size.height - lastWorkspaceRootSize.height) > 0.5
        guard widthChanged || heightChanged else { return }
        lastWorkspaceRootSize = size
    }

    func handleWorkspaceDisappear() {
        releaseScenarioTimestampSuppressionIfNeeded()
        cancelInactivePaneSnapshotRefresh()
        pendingEditEndAutoBackupWorkItem?.cancel()
        pendingEditEndAutoBackupWorkItem = nil
        hasPendingEditEndAutoBackupRequest = false
        focusModeWindowBackgroundActive = false
        stopHistoryKeyMonitor()
        stopFocusModeKeyMonitor()
        stopFocusModeScrollMonitor()
        stopFocusModeCaretMonitor()
        stopMainNavKeyMonitor()
        stopMainCaretMonitor()
        stopSplitPaneMouseMonitor()
        stopDictationRecording(discardAudio: true)
    }

    func handleShowFocusModeChange(_ isOn: Bool) {
        focusModeWindowBackgroundActive = isOn
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

    func handleFocusTypewriterEnabledChange(_ isOn: Bool) {
        guard showFocusMode else { return }
        if !isOn {
            focusCaretPendingTypewriter = false
            focusTypewriterDeferredUntilCompositionEnd = false
        }
        requestFocusModeCaretEnsure(typewriter: isOn, delay: 0.0, force: true, reason: "typewriter-toggle")
    }

    func handleEditingCardIDChange(oldID: UUID?, newID: UUID?) {
        if let newID {
            persistLastEditedCard(newID)
        }
        if oldID != nil, newID == nil {
            if editingSessionHadTextMutation {
                scheduleEditEndAutoBackup()
            }
            editingSessionHadTextMutation = false
        } else if oldID == nil, newID != nil {
            pendingEditEndAutoBackupWorkItem?.cancel()
            pendingEditEndAutoBackupWorkItem = nil
            hasPendingEditEndAutoBackupRequest = false
            editingSessionHadTextMutation = false
        } else if oldID != nil, oldID != newID {
            editingSessionHadTextMutation = false
        }
        syncScenarioTimestampSuppressionIfNeeded()
        guard acceptsKeyboardInput else { return }
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
        requestCoalescedMainCaretEnsure(minInterval: mainCaretSelectionEnsureMinInterval, delay: 0.03)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            guard !showFocusMode else { return }
            guard editingCardID == newID else { return }
            if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
                normalizeMainEditorTextViewOffsetIfNeeded(textView, reason: "edit-change")
            }
        }
    }

    func markEditingSessionTextMutation() {
        editingSessionHadTextMutation = true
    }

    func scheduleEditEndAutoBackup() {
        guard autoBackupEnabledOnQuit else { return }
        pendingEditEndAutoBackupWorkItem?.cancel()
        let work = DispatchWorkItem { startEditEndAutoBackupNow() }
        pendingEditEndAutoBackupWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    func startEditEndAutoBackupNow() {
        pendingEditEndAutoBackupWorkItem = nil
        guard autoBackupEnabledOnQuit else { return }
        let backupDirectoryURL = WorkspaceAutoBackupService.resolvedBackupDirectoryURL(from: autoBackupDirectoryPath)
        let workspaceURL = store.folderURL

        if isEditEndAutoBackupRunning {
            hasPendingEditEndAutoBackupRequest = true
            return
        }

        store.flushPendingSaves()
        isEditEndAutoBackupRunning = true

        Task.detached(priority: .utility) {
            do {
                let result = try WorkspaceAutoBackupService.createCompressedBackupAndPrune(
                    workspaceURL: workspaceURL,
                    backupDirectoryURL: backupDirectoryURL
                )
                print("Edit-end auto backup created: \(result.archiveURL.path), pruned \(result.deletedCount) file(s)")
            } catch {
                print("Edit-end auto backup failed: \(error.localizedDescription)")
            }

            await MainActor.run {
                isEditEndAutoBackupRunning = false
                if hasPendingEditEndAutoBackupRequest {
                    hasPendingEditEndAutoBackupRequest = false
                    scheduleEditEndAutoBackup()
                }
            }
        }
    }

    func handleMainCardLineSpacingChange() {
        guard acceptsKeyboardInput else { return }
        guard !showFocusMode else { return }
        applyMainEditorLineSpacingIfNeeded(forceApplyToFullText: true)
        requestCoalescedMainCaretEnsure(minInterval: mainCaretSelectionEnsureMinInterval, delay: 0.0)
    }

    func handleFocusModeEditorCardIDChange(_ newID: UUID?) {
        guard showFocusMode else { return }
        guard let id = newID else { return }
        if !acceptsKeyboardInput {
            if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
               isTextViewInCurrentSplitPane(textView) {
                activateSplitPaneIfNeeded()
            }
            return
        }
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
        DispatchQueue.main.async {
            guard showFocusMode else { return }
            guard focusModeEditorCardID == id else { return }
            guard id != editingCardID else { return }
            guard let card = findCard(by: id) else { return }
            activateFocusModeCardFromClick(card)
        }
    }

    func handleUndoRequestNotification() {
        guard acceptsKeyboardInput else { return }
        if isPreviewingHistory || showHistoryBar || isSearchFocused { return }
        DispatchQueue.main.async {
            guard acceptsKeyboardInput else { return }
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
    }

    func handleRedoRequestNotification() {
        guard acceptsKeyboardInput else { return }
        if isPreviewingHistory || showHistoryBar || isSearchFocused { return }
        DispatchQueue.main.async {
            guard acceptsKeyboardInput else { return }
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
    }

    func handleToggleFocusModeRequestNotification() {
        guard acceptsKeyboardInput else { return }
        if isPreviewingHistory || showHistoryBar { return }
        toggleFocusMode()
    }

    func handleSplitPaneFocusRequestNotification(_ notification: Notification) {
        guard splitModeEnabled else { return }
        guard let targetPaneID = notification.object as? Int else { return }
        let shouldActivate = (targetPaneID == splitPaneID)
        isSplitPaneActive = shouldActivate
        guard shouldActivate else {
            refreshInactivePaneSnapshotNow()
            deactivateSplitPaneInput()
            syncScenarioTimestampSuppressionIfNeeded()
            return
        }
        cancelInactivePaneSnapshotRefresh()
        if activeCardID == nil, let first = scenario.rootCards.first {
            changeActiveCard(to: first)
        }
        synchronizeActiveRelationState(for: activeCardID)
        isMainViewFocused = true
        syncScenarioTimestampSuppressionIfNeeded()
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
                mainCanvasWithOptionalZoom(size: size, availableWidth: availableWidth)
                    .opacity(showFocusMode ? 0 : 1)
                    .allowsHitTesting(!showFocusMode)

                if !showFocusMode, showWorkspaceTopToolbar {
                    workspaceTopToolbar
                }

                if showFocusMode {
                    focusModeCanvas(size: size)
                        .ignoresSafeArea(.container, edges: .top)
                        .transition(.opacity)
                        .zIndex(10)
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
        let shouldApplyZoom = !showHistoryBar
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
                    .padding(.leading, 12)
                historyToolbarButton
                aiChatToolbarButton
                timelineToolbarButton
            }
            Spacer()
        }
        .ignoresSafeArea(.container, edges: [.top, .leading, .trailing, .bottom])
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
        .padding(.top, 2)
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
        .padding(.top, 2)
        .help("히스토리 타임라인 열기")
    }

    var dictationPopupView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("전사 모드")
                .font(.system(size: 14, weight: .semibold))

            ScrollView {
                let live = dictationPopupLiveText.trimmingCharacters(in: .whitespacesAndNewlines)
                Text(live.isEmpty ? "음성을 기다리는 중..." : live)
                    .font(.system(size: 12))
                    .foregroundStyle(live.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )

            if !dictationPopupStatusText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(dictationPopupStatusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button("취소") {
                    cancelDictationMode()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(dictationIsProcessing)

                Spacer()

                Button("완료") {
                    finishDictationMode()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!dictationIsRecording || dictationIsProcessing)
            }
        }
        .padding(12)
        .frame(width: 420, height: 280, alignment: .topLeading)
        .onDisappear {
            if dictationIsRecording {
                cancelDictationMode()
            }
        }
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
        .padding(.top, 2)
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
        .padding(.top, 2)
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

    var cloneCardPasteDialogOverlay: some View {
        ZStack {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .onTapGesture {
                    cancelPendingPastePlacement()
                }

            VStack(alignment: .leading, spacing: 12) {
                Text("카드 붙여넣기")
                    .font(.system(size: 16, weight: .semibold))
                Text("붙여넣을 위치를 선택하세요.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    clonePasteDialogOptionRow(placement: .child)
                    clonePasteDialogOptionRow(placement: .sibling)
                }

                Text("↑/↓ 선택 · Enter 확인 · Esc 취소")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(width: 320)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 20, y: 8)
        }
        .zIndex(1000)
        .allowsHitTesting(true)
    }

    @ViewBuilder
    func clonePasteDialogOptionRow(placement: ClonePastePlacement) -> some View {
        let isEnabled = isClonePastePlacementEnabled(placement)
        let isSelected = showCloneCardPasteDialog && clonePasteDialogSelection == placement

        Button {
            guard isEnabled else { return }
            clonePasteDialogSelection = placement
            applyPendingPastePlacement(as: placement)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: clonePasteDialogOptionIcon(placement))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary.opacity(0.7))
                Text(clonePasteDialogOptionTitle(placement))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.75))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.20) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    func clonePasteDialogOptionTitle(_ placement: ClonePastePlacement) -> String {
        switch placement {
        case .child:
            return "자식 카드로 붙여넣기"
        case .sibling:
            return "형제 카드로 붙여넣기"
        }
    }

    func clonePasteDialogOptionIcon(_ placement: ClonePastePlacement) -> String {
        switch placement {
        case .child:
            return "arrow.right"
        case .sibling:
            return "arrow.down"
        }
    }

    // MARK: - Main Canvas

    @ViewBuilder
    func mainCanvas(size: CGSize, availableWidth: CGFloat) -> some View {
        ZStack {
            mainCanvasBackgroundLayer
            mainCanvasScrollContainer(size: size, availableWidth: availableWidth)
        }
        .allowsHitTesting(true)
    }

    var mainCanvasBackgroundLayer: some View {
        resolvedBackgroundColor()
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                if !isPreviewingHistory {
                    deselectAll()
                    isMainViewFocused = true
                }
            }
    }

    func mainCanvasScrollContainer(size: CGSize, availableWidth: CGFloat) -> some View {
        ScrollViewReader { hProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                mainCanvasScrollableContent(size: size, availableWidth: availableWidth)
            }
            .onChange(of: Int(historyIndex)) { _, _ in
                handleMainCanvasHistoryIndexChange(hProxy: hProxy)
            }
            .onChange(of: activeCardID) { _, newID in
                handleMainCanvasActiveCardChange(newID, hProxy: hProxy, availableWidth: availableWidth)
            }
            .onChange(of: pendingMainCanvasRestoreCardID) { _, _ in
                handleMainCanvasRestoreRequest(hProxy: hProxy, availableWidth: availableWidth)
            }
            .onAppear {
                handleMainCanvasAppear(hProxy: hProxy, availableWidth: availableWidth)
            }
        }
    }

    @ViewBuilder
    func mainCanvasScrollableContent(size: CGSize, availableWidth: CGFloat) -> some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    handleMainCanvasInnerTap()
                }
            HStack(alignment: .top, spacing: 0) {
                Spacer().frame(width: availableWidth / 2)
                if isPreviewingHistory {
                    let previewLevels = buildPreviewLevels()
                    ForEach(Array(previewLevels.enumerated()), id: \.offset) { index, diffs in
                        previewColumn(for: diffs, level: index, screenHeight: size.height)
                            .id("preview-col-\(index)")
                    }
                } else {
                    mainCanvasLevelColumns(screenHeight: size.height)
                }
                Spacer().frame(width: availableWidth / 2)
            }
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleMainCanvasInnerTap()
                    }
            )
        }
    }

    @ViewBuilder
    func mainCanvasLevelColumns(screenHeight: CGFloat) -> some View {
        let levelsData = displayedLevelsData()
        let visualMaxLevelCount = displayedMaxLevelCount(for: levelsData)
        ForEach(Array(levelsData.enumerated()), id: \.offset) { index, data in
            let filteredCards = filteredCardsForMainCanvasColumn(levelIndex: index, cards: data.cards)
            if index <= 1 || !filteredCards.isEmpty {
                column(for: filteredCards, level: index, parent: data.parent, screenHeight: screenHeight)
                    .id(index)
            } else {
                Color.clear.frame(width: columnWidth)
            }
        }
        if visualMaxLevelCount > levelsData.count {
            ForEach(levelsData.count..<visualMaxLevelCount, id: \.self) { _ in
                Color.clear.frame(width: columnWidth)
            }
        }
    }

    func filteredCardsForMainCanvasColumn(levelIndex: Int, cards: [SceneCard]) -> [SceneCard] {
        if levelIndex <= 1 || isActiveCardRoot {
            return cards
        }
        guard let category = activeCategory else {
            return cards
        }
        return cards.filter { $0.category == category }
    }

    func handleMainCanvasInnerTap() {
        if isPreviewingHistory {
            historyPreviewSelectedCardIDs = []
        } else {
            finishEditing()
            selectedCardIDs = []
            isMainViewFocused = true
        }
    }

    func handleMainCanvasHistoryIndexChange(hProxy: ScrollViewProxy) {
        guard acceptsKeyboardInput else { return }
        if isPreviewingHistory {
            withAnimation(quickEaseAnimation) {
                autoScrollToChanges(hProxy: hProxy)
            }
        }
    }

    func handleMainCanvasActiveCardChange(_ newID: UUID?, hProxy: ScrollViewProxy, availableWidth: CGFloat) {
        guard acceptsKeyboardInput else { return }
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

    func handleMainCanvasRestoreRequest(hProxy: ScrollViewProxy, availableWidth: CGFloat) {
        guard acceptsKeyboardInput else { return }
        restoreMainCanvasPositionIfNeeded(proxy: hProxy, availableWidth: availableWidth)
    }

    func handleMainCanvasAppear(hProxy: ScrollViewProxy, availableWidth: CGFloat) {
        if acceptsKeyboardInput {
            restoreMainCanvasPositionIfNeeded(proxy: hProxy, availableWidth: availableWidth)
        }
    }

    func activateSplitPaneIfNeeded() {
        guard splitModeEnabled else { return }
        NotificationCenter.default.post(name: .waSplitPaneActivateRequested, object: splitPaneID)
    }

    private func startSplitPaneMouseMonitor() {
        guard splitModeEnabled else { return }
        guard splitPaneMouseMonitor == nil else { return }
        splitPaneMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            guard splitModeEnabled else { return event }
            guard !isSplitPaneActive else { return event }
            guard let window = event.window, let contentView = window.contentView else { return event }
            let pointInContent = contentView.convert(event.locationInWindow, from: nil)
            let dividerX = contentView.bounds.midX
            let isTargetPane = splitPaneID == 1 ? pointInContent.x <= dividerX : pointInContent.x >= dividerX
            if isTargetPane {
                NotificationCenter.default.post(name: .waSplitPaneActivateRequested, object: splitPaneID)
            }
            return event
        }
    }

    private func stopSplitPaneMouseMonitor() {
        guard let monitor = splitPaneMouseMonitor else { return }
        NSEvent.removeMonitor(monitor)
        splitPaneMouseMonitor = nil
    }

    private func isTextViewInCurrentSplitPane(_ textView: NSTextView) -> Bool {
        guard splitModeEnabled else { return true }
        guard let window = textView.window, let contentView = window.contentView else { return true }
        let frameInContent = textView.convert(textView.bounds, to: contentView)
        let dividerX = contentView.bounds.midX
        if splitPaneID == 1 {
            return frameInContent.midX <= dividerX
        }
        return frameInContent.midX >= dividerX
    }

    private func deactivateSplitPaneInput() {
        isMainViewFocused = false
        isSearchFocused = false
        isNamedSnapshotSearchFocused = false
        isNamedSnapshotNoteEditorFocused = false
        isNamedSnapshotNoteEditing = false
        isAIChatInputFocused = false
    }

    private func syncScenarioTimestampSuppressionIfNeeded() {
        let shouldSuppress = shouldSuppressScenarioTimestampDuringEditing
        if shouldSuppress {
            if !scenarioTimestampSuppressionActive {
                scenario.beginInteractiveTimestampSuppression()
                scenarioTimestampSuppressionActive = true
            }
            return
        }
        if scenarioTimestampSuppressionActive {
            scenarioTimestampSuppressionActive = false
            scenario.endInteractiveTimestampSuppression(flush: true)
        }
    }

    private func releaseScenarioTimestampSuppressionIfNeeded() {
        guard scenarioTimestampSuppressionActive else { return }
        scenarioTimestampSuppressionActive = false
        scenario.endInteractiveTimestampSuppression(flush: true)
    }

    private func displayedLevelsData() -> [LevelData] {
        if isInactiveSplitPane, !inactivePaneSnapshotState.levelsData.isEmpty {
            return inactivePaneSnapshotState.levelsData
        }
        return resolvedLevelsWithParents()
    }

    private func displayedMaxLevelCount(for levelsData: [LevelData]) -> Int {
        if isInactiveSplitPane {
            return max(inactivePaneSnapshotState.maxLevelCount, levelsData.count)
        }
        return maxLevelCount
    }

    private func cancelInactivePaneSnapshotRefresh() {
        inactivePaneSnapshotState.syncWorkItem?.cancel()
        inactivePaneSnapshotState.syncWorkItem = nil
    }

    private func refreshInactivePaneSnapshotNow() {
        guard splitModeEnabled else { return }
        cancelInactivePaneSnapshotRefresh()
        let levelsData = resolvedLevelsWithParents()
        inactivePaneSnapshotState.levelsData = levelsData
        inactivePaneSnapshotState.maxLevelCount = max(maxLevelCount, levelsData.count)
    }

    private func scheduleInactivePaneSnapshotRefresh() {
        guard isInactiveSplitPane else { return }
        cancelInactivePaneSnapshotRefresh()
        let workItem = DispatchWorkItem {
            guard isInactiveSplitPane else { return }
            let levelsData = resolvedLevelsWithParents()
            inactivePaneSnapshotState.levelsData = levelsData
            inactivePaneSnapshotState.maxLevelCount = max(maxLevelCount, levelsData.count)
        }
        inactivePaneSnapshotState.syncWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + inactivePaneSyncThrottleInterval,
            execute: workItem
        )
    }

    private func startupActiveCard() -> SceneCard? {
        if scenario.id.uuidString == lastEditedScenarioID,
           let restoredID = UUID(uuidString: lastEditedCardID),
           let restored = findCard(by: restoredID),
           !restored.isArchived {
            return restored
        }
        return scenario.rootCards.first
    }

    private func persistLastEditedCard(_ cardID: UUID) {
        guard let card = findCard(by: cardID), !card.isArchived else { return }
        lastEditedScenarioID = scenario.id.uuidString
        lastEditedCardID = cardID.uuidString
    }
}
