import SwiftUI
import AppKit

struct InactivePaneSnapshotState {
    var levelsData: [LevelData] = []
    var maxLevelCount: Int = 0
    var syncWorkItem: DispatchWorkItem? = nil
}

struct FocusModeSearchMatch: Equatable {
    let cardID: UUID
    let range: NSRange
}

struct UpperCardCreationRequest: Identifiable {
    let id = UUID()
    let contextCardID: UUID
    let sourceCardIDs: [UUID]
}

struct WorkspaceFocusPersistenceState: Equatable {
    var lastEditedScenarioID: String = ""
    var lastEditedCardID: String = ""
    var lastFocusedScenarioID: String = ""
    var lastFocusedCardID: String = ""
    var lastFocusedCaretLocation: Int = -1
    var lastFocusedWasEditing: Bool = false
    var lastFocusedWasFocusMode: Bool = false
}

struct WriterWorkspaceSessionState {
    var isSplitPaneActive: Bool = false
    var activeCardID: UUID? = nil
    var selectedCardIDs: Set<UUID> = []
    var editingCardID: UUID? = nil
    var mainEditorSession = MainEditorSessionState()
    var mainEditorEntryFinishGuardCardID: UUID? = nil
    var mainEditorEntryFinishGuardUntil: Date = .distantPast
    var mainEditingScrollIsolationUntil: Date = .distantPast
    var mainEditingScrollIsolationTargetCardID: UUID? = nil
    var pendingMainPreemptiveFocusNavigationTargetID: UUID? = nil
    var showDeleteAlert: Bool = false
    var pendingUpperCardCreationRequest: UpperCardCreationRequest? = nil
    var mainArrowRepeatAnimationSuppressedUntil: Date = .distantPast
    var splitPaneAutoLinkEditsEnabled: Bool = true
    var showTimeline: Bool = false
    var showAIChat: Bool = false
    var exportMessage: String? = nil
    var showExportAlert: Bool = false
    var searchText: String = ""
    var linkedCardsFilterEnabled: Bool = false
    var linkedCardAnchorID: UUID? = nil
    var mainNavKeyMonitor: Any? = nil
    var splitPaneMouseMonitor: Any? = nil
    var isApplyingUndo: Bool = false
    var editingIsNewCard: Bool = false
    var editingStartContent: String = ""
    var editingStartState: ScenarioState? = nil
    var pendingNewCardPrevState: ScenarioState? = nil
    var mainSelectionObserver: NSObjectProtocol? = nil
    var mainCaretEnsureWorkItem: DispatchWorkItem? = nil
    var mainCaretRestoreRequestID: Int = 0
    var undoStack: [ScenarioState] = []
    var redoStack: [ScenarioState] = []
    var mainTypingUndoStack: [ScenarioState] = []
    var mainTypingRedoStack: [ScenarioState] = []
    var mainTypingCoalescingBaseState: ScenarioState? = nil
    var mainTypingCoalescingCardID: UUID? = nil
    var mainTypingLastEditAt: Date = .distantPast
    var mainTypingIdleFinalizeWorkItem: DispatchWorkItem? = nil
    var mainPendingReturnBoundary: Bool = false
    var mainLastCommittedContentByCard: [UUID: String] = [:]
    var mainProgrammaticContentSuppressUntil: Date = .distantPast
    var pendingMainUndoCaretHint: (cardID: UUID, location: Int)? = nil
    var dictationRecorder: LiveSpeechDictationRecorder? = nil
    var dictationIsRecording: Bool = false
    var dictationIsProcessing: Bool = false
    var dictationTargetParentID: UUID? = nil
    var dictationPopupPresented: Bool = false
    var dictationPopupLiveText: String = ""
    var dictationPopupStatusText: String = ""
    var dictationSourceTextViewBox = WeakTextViewBox()
    var mainNoChildRightArmCardID: UUID? = nil
    var mainNoChildRightArmAt: Date = .distantPast
    var mainBoundaryParentLeftArmCardID: UUID? = nil
    var mainBoundaryParentLeftArmAt: Date = .distantPast
    var mainBoundaryChildRightArmCardID: UUID? = nil
    var mainBoundaryChildRightArmAt: Date = .distantPast
    var mainBoundaryFeedbackCardID: UUID? = nil
    var mainBoundaryFeedbackKeyCode: UInt16? = nil
    var mainRecentVerticalArrowKeyCode: UInt16? = nil
    var mainRecentVerticalArrowAt: Date = .distantPast
    var keyboardRangeSelectionAnchorCardID: UUID? = nil
    var mainBottomRevealCardID: UUID? = nil
    var mainBottomRevealTick: Int = 0
    var mainEditTabArmCardID: UUID? = nil
    var mainEditTabArmAt: Date = .distantPast
    var copiedCardTreePayloadData: Data? = nil
    var copiedCloneCardPayloadData: Data? = nil
    var cutCardRootIDs: [UUID] = []
    var cutCardSourceScenarioID: UUID? = nil
    var pendingCloneCardPastePayload: CloneCardClipboardPayload? = nil
    var pendingCardTreePastePayload: CardTreeClipboardPayload? = nil
    var showCloneCardPasteDialog: Bool = false
    var clonePasteDialogSelection: ClonePastePlacement = .child
    var pendingFountainClipboardPastePreview: FountainClipboardPastePreview? = nil
    var showFountainClipboardPasteDialog: Bool = false
    var fountainClipboardPasteSelection: StructuredTextPasteOption = .plainText
    var fountainClipboardPasteSourceTextViewBox = WeakTextViewBox()
    var caretEnsureBurstWorkItems: [DispatchWorkItem] = []
    var mainColumnCachedEditorSlotFramesByKey: [String: [UUID: CGRect]] = [:]
    var inactivePaneSnapshotState = InactivePaneSnapshotState()
    var scenarioTimestampSuppressionActive: Bool = false
    var editingSessionHadTextMutation: Bool = false
    var didRestoreStartupFocusState: Bool = false
    var didRestoreStartupViewportState: Bool = false
    var pendingFocusPersistenceState: WorkspaceFocusPersistenceState? = nil
    var focusPersistenceFlushWorkItem: DispatchWorkItem? = nil
    var interactionRuntime = WriterInteractionRuntime()
}

struct WriterFocusSessionState {
    var showFocusMode: Bool = false
    var focusModeKeyMonitor: Any? = nil
    var focusModeScrollMonitor: Any? = nil
    var focusModePresentationPhase: FocusModePresentationPhase = .inactive
    var showFocusModeSearchPopup: Bool = false
    var focusModeSearchText: String = ""
    var focusModeSearchMatches: [FocusModeSearchMatch] = []
    var focusModeSearchSelectedMatchIndex: Int = -1
    var focusModeSearchHighlightRequestID: Int = 0
    var focusModeSearchPersistentHighlight: FocusModeSearchMatch? = nil
    var focusModeSearchHighlightTextViewBox = WeakTextViewBox()
    var focusModeNextCardScrollAnchor: UnitPoint? = nil
    var focusModeNextCardScrollAnimated: Bool = true
    var focusModeEntryWorkspaceSnapshot: FocusModeWorkspaceSnapshot? = nil
    var suppressFocusModeScrollOnce: Bool = false
    var focusPendingProgrammaticBeginEditCardID: UUID? = nil
    var focusModeCaretRequestID: Int = 0
    var focusModeCaretRequestStartedAt: Date = .distantPast
    var focusModeExitTeardownUntil: Date = .distantPast
    var focusModeBoundaryTransitionPendingReveal: Bool = false
    var focusModePendingFallbackRevealCardID: UUID? = nil
    var focusModeFallbackRevealIssuedCardID: UUID? = nil
    var focusModeFallbackRevealTick: Int = 0
    var focusModeSelectionObserver: NSObjectProtocol? = nil
    var focusExcludedResponderObjectID: ObjectIdentifier? = nil
    var focusExcludedResponderUntil: Date = .distantPast
    var focusDeleteSelectionLockedCardID: UUID? = nil
    var focusDeleteSelectionLockUntil: Date = .distantPast
    var focusCaretEnsureWorkItem: DispatchWorkItem? = nil
    var focusCaretPendingTypewriter: Bool = false
    var focusTypewriterDeferredUntilCompositionEnd: Bool = false
    var focusObservedBodyHeightByCardID: [UUID: CGFloat] = [:]
    var focusUndoStack: [ScenarioState] = []
    var focusRedoStack: [ScenarioState] = []
    var focusTypingCoalescingBaseState: ScenarioState? = nil
    var focusTypingCoalescingCardID: UUID? = nil
    var focusTypingLastEditAt: Date = .distantPast
    var focusTypingIdleFinalizeWorkItem: DispatchWorkItem? = nil
    var focusPendingReturnBoundary: Bool = false
    var focusLastCommittedContentByCard: [UUID: String] = [:]
    var focusProgrammaticContentSuppressUntil: Date = .distantPast
    var pendingFocusUndoCaretHint: (cardID: UUID, location: Int)? = nil
    var focusUndoSelectionEnsureSuppressed: Bool = false
    var focusUndoSelectionEnsureRequestID: Int? = nil
}

struct WriterHistorySessionState {
    var historyIndex: Double = 0
    var isPreviewingHistory: Bool = false
    var previewDiffs: [SnapshotDiff] = []
    var historyPreviewSelectedCardIDs: Set<UUID> = []
    var showHistoryBar: Bool = false
    var showCheckpointDialog: Bool = false
    var newCheckpointName: String = ""
    var newCheckpointNote: String = ""
    var snapshotNoteSearchText: String = ""
    var historySelectedNamedSnapshotNoteCardID: UUID? = nil
    var isNamedSnapshotNoteEditing: Bool = false
    var editingSnapshotID: UUID? = nil
    var editedSnapshotName: String = ""
    var historyKeyMonitor: Any? = nil
    var historyBarMeasuredHeight: CGFloat = 0
    var historyRetentionLastAppliedCount: Int = 0
}

struct WriterBoardSessionState {
    var indexBoardEditorDraft: IndexBoardEditorDraft? = nil
    var isIndexBoardInlineEditing: Bool = false
    var pendingIndexBoardCreationPrevStateByCardID: [UUID: ScenarioState] = [:]
}

extension ScenarioWriterView {
    var focusTypingIdleInterval: TimeInterval { 1.5 }
    var focusOffsetNormalizationMinInterval: TimeInterval { 0.08 }
    var focusCaretSelectionEnsureMinInterval: TimeInterval { 0.016 }
    var mainCaretSelectionEnsureMinInterval: TimeInterval { 0.016 }
    var mainCaretVerticalNavigationBurstWindow: TimeInterval { 0.08 }
    var mainCaretVerticalNavigationEnsureMinInterval: TimeInterval { 0.12 }
    var mainEditDoubleTabInterval: TimeInterval { 0.45 }
    var mainNoChildRightDoublePressInterval: TimeInterval { 0.55 }
    var maxUndoCount: Int { 200 }
    var maxMainTypingUndoCount: Int { 1200 }
    var maxFocusUndoCount: Int { 1200 }
    var deltaSnapshotFullCheckpointInterval: Int { 30 }
    var historyRetentionMinimumCount: Int { 180 }
    var historyRetentionApplyStride: Int { 12 }
    var historyPromotionLargeEditScoreThreshold: Int { 1200 }
    var historyPromotionChangedCardsThreshold: Int { 8 }
    var historyPromotionSessionGapThreshold: TimeInterval { 60 * 15 }
    var inactivePaneSyncThrottleInterval: TimeInterval { 0.16 }
    var timelineWidth: CGFloat { TimelinePanelLayoutMetrics.panelWidth }
    var historyOverlayBottomInset: CGFloat { 88 }
    var columnWidth: CGFloat { MainCanvasLayoutMetrics.columnWidth }
    var mainParentGroupSeparatorHeight: CGFloat { 3 }

    func workspaceBinding<Value>(_ keyPath: WritableKeyPath<WriterWorkspaceSessionState, Value>) -> Binding<Value> {
        Binding(
            get: { workspaceSession[keyPath: keyPath] },
            set: { workspaceSession[keyPath: keyPath] = $0 }
        )
    }

    func focusBinding<Value>(_ keyPath: WritableKeyPath<WriterFocusSessionState, Value>) -> Binding<Value> {
        Binding(
            get: { focusSession[keyPath: keyPath] },
            set: { focusSession[keyPath: keyPath] = $0 }
        )
    }

    func historyBinding<Value>(_ keyPath: WritableKeyPath<WriterHistorySessionState, Value>) -> Binding<Value> {
        Binding(
            get: { historySession[keyPath: keyPath] },
            set: { historySession[keyPath: keyPath] = $0 }
        )
    }

    var showDeleteAlertBinding: Binding<Bool> { workspaceBinding(\.showDeleteAlert) }
    var showCheckpointDialogBinding: Binding<Bool> { historyBinding(\.showCheckpointDialog) }
    var dictationPopupPresentedBinding: Binding<Bool> { workspaceBinding(\.dictationPopupPresented) }
    var showExportAlertBinding: Binding<Bool> { workspaceBinding(\.showExportAlert) }
    var searchTextBinding: Binding<String> { workspaceBinding(\.searchText) }
    var newCheckpointNameBinding: Binding<String> { historyBinding(\.newCheckpointName) }
    var newCheckpointNoteBinding: Binding<String> { historyBinding(\.newCheckpointNote) }
    var snapshotNoteSearchTextBinding: Binding<String> { historyBinding(\.snapshotNoteSearchText) }
    var editedSnapshotNameBinding: Binding<String> { historyBinding(\.editedSnapshotName) }
    var focusModeSearchTextBinding: Binding<String> { focusBinding(\.focusModeSearchText) }

    var isSplitPaneActive: Bool {
        get { workspaceSession.isSplitPaneActive }
        nonmutating set { workspaceSession.isSplitPaneActive = newValue }
    }

    var activeCardID: UUID? {
        get { workspaceSession.activeCardID }
        nonmutating set { workspaceSession.activeCardID = newValue }
    }

    var selectedCardIDs: Set<UUID> {
        get { workspaceSession.selectedCardIDs }
        nonmutating set { workspaceSession.selectedCardIDs = newValue }
    }

    var editingCardID: UUID? {
        get { workspaceSession.editingCardID }
        nonmutating set { workspaceSession.editingCardID = newValue }
    }

    var mainEditorSession: MainEditorSessionState {
        get { workspaceSession.mainEditorSession }
        nonmutating set { workspaceSession.mainEditorSession = newValue }
    }

    var pendingFocusPersistenceState: WorkspaceFocusPersistenceState? {
        get { workspaceSession.pendingFocusPersistenceState }
        nonmutating set { workspaceSession.pendingFocusPersistenceState = newValue }
    }

    var focusPersistenceFlushWorkItem: DispatchWorkItem? {
        get { workspaceSession.focusPersistenceFlushWorkItem }
        nonmutating set { workspaceSession.focusPersistenceFlushWorkItem = newValue }
    }

    var mainEditorEntryFinishGuardCardID: UUID? {
        get { workspaceSession.mainEditorEntryFinishGuardCardID }
        nonmutating set { workspaceSession.mainEditorEntryFinishGuardCardID = newValue }
    }

    var mainEditorEntryFinishGuardUntil: Date {
        get { workspaceSession.mainEditorEntryFinishGuardUntil }
        nonmutating set { workspaceSession.mainEditorEntryFinishGuardUntil = newValue }
    }

    var mainEditingScrollIsolationUntil: Date {
        get { workspaceSession.mainEditingScrollIsolationUntil }
        nonmutating set { workspaceSession.mainEditingScrollIsolationUntil = newValue }
    }

    var mainEditingScrollIsolationTargetCardID: UUID? {
        get { workspaceSession.mainEditingScrollIsolationTargetCardID }
        nonmutating set { workspaceSession.mainEditingScrollIsolationTargetCardID = newValue }
    }

    var pendingMainPreemptiveFocusNavigationTargetID: UUID? {
        get { workspaceSession.pendingMainPreemptiveFocusNavigationTargetID }
        nonmutating set { workspaceSession.pendingMainPreemptiveFocusNavigationTargetID = newValue }
    }

    var showDeleteAlert: Bool {
        get { workspaceSession.showDeleteAlert }
        nonmutating set { workspaceSession.showDeleteAlert = newValue }
    }

    var pendingUpperCardCreationRequest: UpperCardCreationRequest? {
        get { workspaceSession.pendingUpperCardCreationRequest }
        nonmutating set { workspaceSession.pendingUpperCardCreationRequest = newValue }
    }

    var mainArrowRepeatAnimationSuppressedUntil: Date {
        get { workspaceSession.mainArrowRepeatAnimationSuppressedUntil }
        nonmutating set { workspaceSession.mainArrowRepeatAnimationSuppressedUntil = newValue }
    }

    var splitPaneAutoLinkEditsEnabled: Bool {
        get { workspaceSession.splitPaneAutoLinkEditsEnabled }
        nonmutating set { workspaceSession.splitPaneAutoLinkEditsEnabled = newValue }
    }

    var showTimeline: Bool {
        get { workspaceSession.showTimeline }
        nonmutating set { workspaceSession.showTimeline = newValue }
    }

    var showAIChat: Bool {
        get { workspaceSession.showAIChat }
        nonmutating set { workspaceSession.showAIChat = newValue }
    }

    var exportMessage: String? {
        get { workspaceSession.exportMessage }
        nonmutating set { workspaceSession.exportMessage = newValue }
    }

    var showExportAlert: Bool {
        get { workspaceSession.showExportAlert }
        nonmutating set { workspaceSession.showExportAlert = newValue }
    }

    var searchText: String {
        get { workspaceSession.searchText }
        nonmutating set { workspaceSession.searchText = newValue }
    }

    var linkedCardsFilterEnabled: Bool {
        get { workspaceSession.linkedCardsFilterEnabled }
        nonmutating set { workspaceSession.linkedCardsFilterEnabled = newValue }
    }

    var linkedCardAnchorID: UUID? {
        get { workspaceSession.linkedCardAnchorID }
        nonmutating set { workspaceSession.linkedCardAnchorID = newValue }
    }

    var mainNavKeyMonitor: Any? {
        get { workspaceSession.mainNavKeyMonitor }
        nonmutating set { workspaceSession.mainNavKeyMonitor = newValue }
    }

    var splitPaneMouseMonitor: Any? {
        get { workspaceSession.splitPaneMouseMonitor }
        nonmutating set { workspaceSession.splitPaneMouseMonitor = newValue }
    }

    var isApplyingUndo: Bool {
        get { workspaceSession.isApplyingUndo }
        nonmutating set { workspaceSession.isApplyingUndo = newValue }
    }

    var editingIsNewCard: Bool {
        get { workspaceSession.editingIsNewCard }
        nonmutating set { workspaceSession.editingIsNewCard = newValue }
    }

    var editingStartContent: String {
        get { workspaceSession.editingStartContent }
        nonmutating set { workspaceSession.editingStartContent = newValue }
    }

    var editingStartState: ScenarioState? {
        get { workspaceSession.editingStartState }
        nonmutating set { workspaceSession.editingStartState = newValue }
    }

    var pendingNewCardPrevState: ScenarioState? {
        get { workspaceSession.pendingNewCardPrevState }
        nonmutating set { workspaceSession.pendingNewCardPrevState = newValue }
    }

    var mainSelectionObserver: NSObjectProtocol? {
        get { workspaceSession.mainSelectionObserver }
        nonmutating set { workspaceSession.mainSelectionObserver = newValue }
    }

    var mainCaretEnsureWorkItem: DispatchWorkItem? {
        get { workspaceSession.mainCaretEnsureWorkItem }
        nonmutating set { workspaceSession.mainCaretEnsureWorkItem = newValue }
    }

    var mainCaretRestoreRequestID: Int {
        get { workspaceSession.mainCaretRestoreRequestID }
        nonmutating set { workspaceSession.mainCaretRestoreRequestID = newValue }
    }

    var undoStack: [ScenarioState] {
        get { workspaceSession.undoStack }
        nonmutating set { workspaceSession.undoStack = newValue }
    }

    var redoStack: [ScenarioState] {
        get { workspaceSession.redoStack }
        nonmutating set { workspaceSession.redoStack = newValue }
    }

    var mainTypingUndoStack: [ScenarioState] {
        get { workspaceSession.mainTypingUndoStack }
        nonmutating set { workspaceSession.mainTypingUndoStack = newValue }
    }

    var mainTypingRedoStack: [ScenarioState] {
        get { workspaceSession.mainTypingRedoStack }
        nonmutating set { workspaceSession.mainTypingRedoStack = newValue }
    }

    var mainTypingCoalescingBaseState: ScenarioState? {
        get { workspaceSession.mainTypingCoalescingBaseState }
        nonmutating set { workspaceSession.mainTypingCoalescingBaseState = newValue }
    }

    var mainTypingCoalescingCardID: UUID? {
        get { workspaceSession.mainTypingCoalescingCardID }
        nonmutating set { workspaceSession.mainTypingCoalescingCardID = newValue }
    }

    var mainTypingLastEditAt: Date {
        get { workspaceSession.mainTypingLastEditAt }
        nonmutating set { workspaceSession.mainTypingLastEditAt = newValue }
    }

    var mainTypingIdleFinalizeWorkItem: DispatchWorkItem? {
        get { workspaceSession.mainTypingIdleFinalizeWorkItem }
        nonmutating set { workspaceSession.mainTypingIdleFinalizeWorkItem = newValue }
    }

    var mainPendingReturnBoundary: Bool {
        get { workspaceSession.mainPendingReturnBoundary }
        nonmutating set { workspaceSession.mainPendingReturnBoundary = newValue }
    }

    var mainLastCommittedContentByCard: [UUID: String] {
        get { workspaceSession.mainLastCommittedContentByCard }
        nonmutating set { workspaceSession.mainLastCommittedContentByCard = newValue }
    }

    var mainProgrammaticContentSuppressUntil: Date {
        get { workspaceSession.mainProgrammaticContentSuppressUntil }
        nonmutating set { workspaceSession.mainProgrammaticContentSuppressUntil = newValue }
    }

    var pendingMainUndoCaretHint: (cardID: UUID, location: Int)? {
        get { workspaceSession.pendingMainUndoCaretHint }
        nonmutating set { workspaceSession.pendingMainUndoCaretHint = newValue }
    }

    var dictationRecorder: LiveSpeechDictationRecorder? {
        get { workspaceSession.dictationRecorder }
        nonmutating set { workspaceSession.dictationRecorder = newValue }
    }

    var dictationIsRecording: Bool {
        get { workspaceSession.dictationIsRecording }
        nonmutating set { workspaceSession.dictationIsRecording = newValue }
    }

    var dictationIsProcessing: Bool {
        get { workspaceSession.dictationIsProcessing }
        nonmutating set { workspaceSession.dictationIsProcessing = newValue }
    }

    var dictationTargetParentID: UUID? {
        get { workspaceSession.dictationTargetParentID }
        nonmutating set { workspaceSession.dictationTargetParentID = newValue }
    }

    var dictationPopupPresented: Bool {
        get { workspaceSession.dictationPopupPresented }
        nonmutating set { workspaceSession.dictationPopupPresented = newValue }
    }

    var dictationPopupLiveText: String {
        get { workspaceSession.dictationPopupLiveText }
        nonmutating set { workspaceSession.dictationPopupLiveText = newValue }
    }

    var dictationPopupStatusText: String {
        get { workspaceSession.dictationPopupStatusText }
        nonmutating set { workspaceSession.dictationPopupStatusText = newValue }
    }

    var dictationSourceTextViewBox: WeakTextViewBox {
        get { workspaceSession.dictationSourceTextViewBox }
        nonmutating set { workspaceSession.dictationSourceTextViewBox = newValue }
    }

    var mainNoChildRightArmCardID: UUID? {
        get { workspaceSession.mainNoChildRightArmCardID }
        nonmutating set { workspaceSession.mainNoChildRightArmCardID = newValue }
    }

    var mainNoChildRightArmAt: Date {
        get { workspaceSession.mainNoChildRightArmAt }
        nonmutating set { workspaceSession.mainNoChildRightArmAt = newValue }
    }

    var mainBoundaryParentLeftArmCardID: UUID? {
        get { workspaceSession.mainBoundaryParentLeftArmCardID }
        nonmutating set { workspaceSession.mainBoundaryParentLeftArmCardID = newValue }
    }

    var mainBoundaryParentLeftArmAt: Date {
        get { workspaceSession.mainBoundaryParentLeftArmAt }
        nonmutating set { workspaceSession.mainBoundaryParentLeftArmAt = newValue }
    }

    var mainBoundaryChildRightArmCardID: UUID? {
        get { workspaceSession.mainBoundaryChildRightArmCardID }
        nonmutating set { workspaceSession.mainBoundaryChildRightArmCardID = newValue }
    }

    var mainBoundaryChildRightArmAt: Date {
        get { workspaceSession.mainBoundaryChildRightArmAt }
        nonmutating set { workspaceSession.mainBoundaryChildRightArmAt = newValue }
    }

    var mainBoundaryFeedbackCardID: UUID? {
        get { workspaceSession.mainBoundaryFeedbackCardID }
        nonmutating set { workspaceSession.mainBoundaryFeedbackCardID = newValue }
    }

    var mainBoundaryFeedbackKeyCode: UInt16? {
        get { workspaceSession.mainBoundaryFeedbackKeyCode }
        nonmutating set { workspaceSession.mainBoundaryFeedbackKeyCode = newValue }
    }

    var mainRecentVerticalArrowKeyCode: UInt16? {
        get { workspaceSession.mainRecentVerticalArrowKeyCode }
        nonmutating set { workspaceSession.mainRecentVerticalArrowKeyCode = newValue }
    }

    var mainRecentVerticalArrowAt: Date {
        get { workspaceSession.mainRecentVerticalArrowAt }
        nonmutating set { workspaceSession.mainRecentVerticalArrowAt = newValue }
    }

    var keyboardRangeSelectionAnchorCardID: UUID? {
        get { workspaceSession.keyboardRangeSelectionAnchorCardID }
        nonmutating set { workspaceSession.keyboardRangeSelectionAnchorCardID = newValue }
    }

    var mainBottomRevealCardID: UUID? {
        get { workspaceSession.mainBottomRevealCardID }
        nonmutating set { workspaceSession.mainBottomRevealCardID = newValue }
    }

    var mainBottomRevealTick: Int {
        get { workspaceSession.mainBottomRevealTick }
        nonmutating set { workspaceSession.mainBottomRevealTick = newValue }
    }

    var mainEditTabArmCardID: UUID? {
        get { workspaceSession.mainEditTabArmCardID }
        nonmutating set { workspaceSession.mainEditTabArmCardID = newValue }
    }

    var mainEditTabArmAt: Date {
        get { workspaceSession.mainEditTabArmAt }
        nonmutating set { workspaceSession.mainEditTabArmAt = newValue }
    }

    var copiedCardTreePayloadData: Data? {
        get { workspaceSession.copiedCardTreePayloadData }
        nonmutating set { workspaceSession.copiedCardTreePayloadData = newValue }
    }

    var copiedCloneCardPayloadData: Data? {
        get { workspaceSession.copiedCloneCardPayloadData }
        nonmutating set { workspaceSession.copiedCloneCardPayloadData = newValue }
    }

    var cutCardRootIDs: [UUID] {
        get { workspaceSession.cutCardRootIDs }
        nonmutating set { workspaceSession.cutCardRootIDs = newValue }
    }

    var cutCardSourceScenarioID: UUID? {
        get { workspaceSession.cutCardSourceScenarioID }
        nonmutating set { workspaceSession.cutCardSourceScenarioID = newValue }
    }

    var pendingCloneCardPastePayload: CloneCardClipboardPayload? {
        get { workspaceSession.pendingCloneCardPastePayload }
        nonmutating set { workspaceSession.pendingCloneCardPastePayload = newValue }
    }

    var pendingCardTreePastePayload: CardTreeClipboardPayload? {
        get { workspaceSession.pendingCardTreePastePayload }
        nonmutating set { workspaceSession.pendingCardTreePastePayload = newValue }
    }

    var showCloneCardPasteDialog: Bool {
        get { workspaceSession.showCloneCardPasteDialog }
        nonmutating set { workspaceSession.showCloneCardPasteDialog = newValue }
    }

    var clonePasteDialogSelection: ClonePastePlacement {
        get { workspaceSession.clonePasteDialogSelection }
        nonmutating set { workspaceSession.clonePasteDialogSelection = newValue }
    }

    var pendingFountainClipboardPastePreview: FountainClipboardPastePreview? {
        get { workspaceSession.pendingFountainClipboardPastePreview }
        nonmutating set { workspaceSession.pendingFountainClipboardPastePreview = newValue }
    }

    var showFountainClipboardPasteDialog: Bool {
        get { workspaceSession.showFountainClipboardPasteDialog }
        nonmutating set { workspaceSession.showFountainClipboardPasteDialog = newValue }
    }

    var fountainClipboardPasteSelection: StructuredTextPasteOption {
        get { workspaceSession.fountainClipboardPasteSelection }
        nonmutating set { workspaceSession.fountainClipboardPasteSelection = newValue }
    }

    var fountainClipboardPasteSourceTextViewBox: WeakTextViewBox {
        get { workspaceSession.fountainClipboardPasteSourceTextViewBox }
        nonmutating set { workspaceSession.fountainClipboardPasteSourceTextViewBox = newValue }
    }

    var caretEnsureBurstWorkItems: [DispatchWorkItem] {
        get { workspaceSession.caretEnsureBurstWorkItems }
        nonmutating set { workspaceSession.caretEnsureBurstWorkItems = newValue }
    }

    var mainColumnCachedEditorSlotFramesByKey: [String: [UUID: CGRect]] {
        get { workspaceSession.mainColumnCachedEditorSlotFramesByKey }
        nonmutating set { workspaceSession.mainColumnCachedEditorSlotFramesByKey = newValue }
    }

    var inactivePaneSnapshotState: InactivePaneSnapshotState {
        get { workspaceSession.inactivePaneSnapshotState }
        nonmutating set { workspaceSession.inactivePaneSnapshotState = newValue }
    }

    var scenarioTimestampSuppressionActive: Bool {
        get { workspaceSession.scenarioTimestampSuppressionActive }
        nonmutating set { workspaceSession.scenarioTimestampSuppressionActive = newValue }
    }

    var editingSessionHadTextMutation: Bool {
        get { workspaceSession.editingSessionHadTextMutation }
        nonmutating set { workspaceSession.editingSessionHadTextMutation = newValue }
    }

    var didRestoreStartupFocusState: Bool {
        get { workspaceSession.didRestoreStartupFocusState }
        nonmutating set { workspaceSession.didRestoreStartupFocusState = newValue }
    }

    var didRestoreStartupViewportState: Bool {
        get { workspaceSession.didRestoreStartupViewportState }
        nonmutating set { workspaceSession.didRestoreStartupViewportState = newValue }
    }

    var interactionRuntime: WriterInteractionRuntime {
        get { workspaceSession.interactionRuntime }
        nonmutating set { workspaceSession.interactionRuntime = newValue }
    }

    var showFocusMode: Bool {
        get { focusSession.showFocusMode }
        nonmutating set { focusSession.showFocusMode = newValue }
    }

    var focusModeKeyMonitor: Any? {
        get { focusSession.focusModeKeyMonitor }
        nonmutating set { focusSession.focusModeKeyMonitor = newValue }
    }

    var focusModeScrollMonitor: Any? {
        get { focusSession.focusModeScrollMonitor }
        nonmutating set { focusSession.focusModeScrollMonitor = newValue }
    }

    var focusModePresentationPhase: FocusModePresentationPhase {
        get { focusSession.focusModePresentationPhase }
        nonmutating set { focusSession.focusModePresentationPhase = newValue }
    }

    var showFocusModeSearchPopup: Bool {
        get { focusSession.showFocusModeSearchPopup }
        nonmutating set { focusSession.showFocusModeSearchPopup = newValue }
    }

    var focusModeSearchText: String {
        get { focusSession.focusModeSearchText }
        nonmutating set { focusSession.focusModeSearchText = newValue }
    }

    var focusModeSearchMatches: [FocusModeSearchMatch] {
        get { focusSession.focusModeSearchMatches }
        nonmutating set { focusSession.focusModeSearchMatches = newValue }
    }

    var focusModeSearchSelectedMatchIndex: Int {
        get { focusSession.focusModeSearchSelectedMatchIndex }
        nonmutating set { focusSession.focusModeSearchSelectedMatchIndex = newValue }
    }

    var focusModeSearchHighlightRequestID: Int {
        get { focusSession.focusModeSearchHighlightRequestID }
        nonmutating set { focusSession.focusModeSearchHighlightRequestID = newValue }
    }

    var focusModeSearchPersistentHighlight: FocusModeSearchMatch? {
        get { focusSession.focusModeSearchPersistentHighlight }
        nonmutating set { focusSession.focusModeSearchPersistentHighlight = newValue }
    }

    var focusModeSearchHighlightTextViewBox: WeakTextViewBox {
        get { focusSession.focusModeSearchHighlightTextViewBox }
        nonmutating set { focusSession.focusModeSearchHighlightTextViewBox = newValue }
    }

    var focusModeNextCardScrollAnchor: UnitPoint? {
        get { focusSession.focusModeNextCardScrollAnchor }
        nonmutating set { focusSession.focusModeNextCardScrollAnchor = newValue }
    }

    var focusModeNextCardScrollAnimated: Bool {
        get { focusSession.focusModeNextCardScrollAnimated }
        nonmutating set { focusSession.focusModeNextCardScrollAnimated = newValue }
    }

    var focusModeEntryWorkspaceSnapshot: FocusModeWorkspaceSnapshot? {
        get { focusSession.focusModeEntryWorkspaceSnapshot }
        nonmutating set { focusSession.focusModeEntryWorkspaceSnapshot = newValue }
    }

    var suppressFocusModeScrollOnce: Bool {
        get { focusSession.suppressFocusModeScrollOnce }
        nonmutating set { focusSession.suppressFocusModeScrollOnce = newValue }
    }

    var focusPendingProgrammaticBeginEditCardID: UUID? {
        get { focusSession.focusPendingProgrammaticBeginEditCardID }
        nonmutating set { focusSession.focusPendingProgrammaticBeginEditCardID = newValue }
    }

    var focusModeCaretRequestID: Int {
        get { focusSession.focusModeCaretRequestID }
        nonmutating set { focusSession.focusModeCaretRequestID = newValue }
    }

    var focusModeCaretRequestStartedAt: Date {
        get { focusSession.focusModeCaretRequestStartedAt }
        nonmutating set { focusSession.focusModeCaretRequestStartedAt = newValue }
    }

    var focusModeExitTeardownUntil: Date {
        get { focusSession.focusModeExitTeardownUntil }
        nonmutating set { focusSession.focusModeExitTeardownUntil = newValue }
    }

    var focusModeBoundaryTransitionPendingReveal: Bool {
        get { focusSession.focusModeBoundaryTransitionPendingReveal }
        nonmutating set { focusSession.focusModeBoundaryTransitionPendingReveal = newValue }
    }

    var focusModePendingFallbackRevealCardID: UUID? {
        get { focusSession.focusModePendingFallbackRevealCardID }
        nonmutating set { focusSession.focusModePendingFallbackRevealCardID = newValue }
    }

    var focusModeFallbackRevealIssuedCardID: UUID? {
        get { focusSession.focusModeFallbackRevealIssuedCardID }
        nonmutating set { focusSession.focusModeFallbackRevealIssuedCardID = newValue }
    }

    var focusModeFallbackRevealTick: Int {
        get { focusSession.focusModeFallbackRevealTick }
        nonmutating set { focusSession.focusModeFallbackRevealTick = newValue }
    }

    var focusModeSelectionObserver: NSObjectProtocol? {
        get { focusSession.focusModeSelectionObserver }
        nonmutating set { focusSession.focusModeSelectionObserver = newValue }
    }

    var focusExcludedResponderObjectID: ObjectIdentifier? {
        get { focusSession.focusExcludedResponderObjectID }
        nonmutating set { focusSession.focusExcludedResponderObjectID = newValue }
    }

    var focusExcludedResponderUntil: Date {
        get { focusSession.focusExcludedResponderUntil }
        nonmutating set { focusSession.focusExcludedResponderUntil = newValue }
    }

    var focusDeleteSelectionLockedCardID: UUID? {
        get { focusSession.focusDeleteSelectionLockedCardID }
        nonmutating set { focusSession.focusDeleteSelectionLockedCardID = newValue }
    }

    var focusDeleteSelectionLockUntil: Date {
        get { focusSession.focusDeleteSelectionLockUntil }
        nonmutating set { focusSession.focusDeleteSelectionLockUntil = newValue }
    }

    var focusCaretEnsureWorkItem: DispatchWorkItem? {
        get { focusSession.focusCaretEnsureWorkItem }
        nonmutating set { focusSession.focusCaretEnsureWorkItem = newValue }
    }

    var focusCaretPendingTypewriter: Bool {
        get { focusSession.focusCaretPendingTypewriter }
        nonmutating set { focusSession.focusCaretPendingTypewriter = newValue }
    }

    var focusTypewriterDeferredUntilCompositionEnd: Bool {
        get { focusSession.focusTypewriterDeferredUntilCompositionEnd }
        nonmutating set { focusSession.focusTypewriterDeferredUntilCompositionEnd = newValue }
    }

    var focusObservedBodyHeightByCardID: [UUID: CGFloat] {
        get { focusSession.focusObservedBodyHeightByCardID }
        nonmutating set { focusSession.focusObservedBodyHeightByCardID = newValue }
    }

    var focusUndoStack: [ScenarioState] {
        get { focusSession.focusUndoStack }
        nonmutating set { focusSession.focusUndoStack = newValue }
    }

    var focusRedoStack: [ScenarioState] {
        get { focusSession.focusRedoStack }
        nonmutating set { focusSession.focusRedoStack = newValue }
    }

    var focusTypingCoalescingBaseState: ScenarioState? {
        get { focusSession.focusTypingCoalescingBaseState }
        nonmutating set { focusSession.focusTypingCoalescingBaseState = newValue }
    }

    var focusTypingCoalescingCardID: UUID? {
        get { focusSession.focusTypingCoalescingCardID }
        nonmutating set { focusSession.focusTypingCoalescingCardID = newValue }
    }

    var focusTypingLastEditAt: Date {
        get { focusSession.focusTypingLastEditAt }
        nonmutating set { focusSession.focusTypingLastEditAt = newValue }
    }

    var focusTypingIdleFinalizeWorkItem: DispatchWorkItem? {
        get { focusSession.focusTypingIdleFinalizeWorkItem }
        nonmutating set { focusSession.focusTypingIdleFinalizeWorkItem = newValue }
    }

    var focusPendingReturnBoundary: Bool {
        get { focusSession.focusPendingReturnBoundary }
        nonmutating set { focusSession.focusPendingReturnBoundary = newValue }
    }

    var focusLastCommittedContentByCard: [UUID: String] {
        get { focusSession.focusLastCommittedContentByCard }
        nonmutating set { focusSession.focusLastCommittedContentByCard = newValue }
    }

    var focusProgrammaticContentSuppressUntil: Date {
        get { focusSession.focusProgrammaticContentSuppressUntil }
        nonmutating set { focusSession.focusProgrammaticContentSuppressUntil = newValue }
    }

    var pendingFocusUndoCaretHint: (cardID: UUID, location: Int)? {
        get { focusSession.pendingFocusUndoCaretHint }
        nonmutating set { focusSession.pendingFocusUndoCaretHint = newValue }
    }

    var focusUndoSelectionEnsureSuppressed: Bool {
        get { focusSession.focusUndoSelectionEnsureSuppressed }
        nonmutating set { focusSession.focusUndoSelectionEnsureSuppressed = newValue }
    }

    var focusUndoSelectionEnsureRequestID: Int? {
        get { focusSession.focusUndoSelectionEnsureRequestID }
        nonmutating set { focusSession.focusUndoSelectionEnsureRequestID = newValue }
    }

    var historyIndex: Double {
        get { historySession.historyIndex }
        nonmutating set { historySession.historyIndex = newValue }
    }

    var isPreviewingHistory: Bool {
        get { historySession.isPreviewingHistory }
        nonmutating set { historySession.isPreviewingHistory = newValue }
    }

    var previewDiffs: [SnapshotDiff] {
        get { historySession.previewDiffs }
        nonmutating set { historySession.previewDiffs = newValue }
    }

    var historyPreviewSelectedCardIDs: Set<UUID> {
        get { historySession.historyPreviewSelectedCardIDs }
        nonmutating set { historySession.historyPreviewSelectedCardIDs = newValue }
    }

    var showHistoryBar: Bool {
        get { historySession.showHistoryBar }
        nonmutating set { historySession.showHistoryBar = newValue }
    }

    var showCheckpointDialog: Bool {
        get { historySession.showCheckpointDialog }
        nonmutating set { historySession.showCheckpointDialog = newValue }
    }

    var newCheckpointName: String {
        get { historySession.newCheckpointName }
        nonmutating set { historySession.newCheckpointName = newValue }
    }

    var newCheckpointNote: String {
        get { historySession.newCheckpointNote }
        nonmutating set { historySession.newCheckpointNote = newValue }
    }

    var snapshotNoteSearchText: String {
        get { historySession.snapshotNoteSearchText }
        nonmutating set { historySession.snapshotNoteSearchText = newValue }
    }

    var historySelectedNamedSnapshotNoteCardID: UUID? {
        get { historySession.historySelectedNamedSnapshotNoteCardID }
        nonmutating set { historySession.historySelectedNamedSnapshotNoteCardID = newValue }
    }

    var isNamedSnapshotNoteEditing: Bool {
        get { historySession.isNamedSnapshotNoteEditing }
        nonmutating set { historySession.isNamedSnapshotNoteEditing = newValue }
    }

    var editingSnapshotID: UUID? {
        get { historySession.editingSnapshotID }
        nonmutating set { historySession.editingSnapshotID = newValue }
    }

    var editedSnapshotName: String {
        get { historySession.editedSnapshotName }
        nonmutating set { historySession.editedSnapshotName = newValue }
    }

    var historyKeyMonitor: Any? {
        get { historySession.historyKeyMonitor }
        nonmutating set { historySession.historyKeyMonitor = newValue }
    }

    var historyBarMeasuredHeight: CGFloat {
        get { historySession.historyBarMeasuredHeight }
        nonmutating set { historySession.historyBarMeasuredHeight = newValue }
    }

    var historyRetentionLastAppliedCount: Int {
        get { historySession.historyRetentionLastAppliedCount }
        nonmutating set { historySession.historyRetentionLastAppliedCount = newValue }
    }

    var indexBoardEditorDraft: IndexBoardEditorDraft? {
        get { boardSession.indexBoardEditorDraft }
        nonmutating set { boardSession.indexBoardEditorDraft = newValue }
    }

    var isIndexBoardInlineEditing: Bool {
        get { boardSession.isIndexBoardInlineEditing }
        nonmutating set { boardSession.isIndexBoardInlineEditing = newValue }
    }

    var pendingIndexBoardCreationPrevStateByCardID: [UUID: ScenarioState] {
        get { boardSession.pendingIndexBoardCreationPrevStateByCardID }
        nonmutating set { boardSession.pendingIndexBoardCreationPrevStateByCardID = newValue }
    }
}
