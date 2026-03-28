import SwiftUI
import AppKit

final class WeakTextViewBox {
    weak var textView: NSTextView?
}

struct MainEditorSessionState: Equatable {
    var requestedCardID: UUID? = nil
    var mountedCardID: UUID? = nil
    var textViewIdentity: Int? = nil
    var caretSeedLocation: Int? = nil
    var isFirstResponderReady: Bool = false
    var liveBodyHeight: CGFloat? = nil
}

enum FinishEditingReason: String {
    case generic
    case explicitExit
    case transition
}

// MARK: - ScenarioWriterView (메인 struct + 프로퍼티 + body + 레이아웃)

struct ScenarioWriterView: View {
    @Environment(\.openWindow) var openWindow

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

    @EnvironmentObject var store: FileStore
    @EnvironmentObject var referenceCardStore: ReferenceCardStore
    @EnvironmentObject var appWindowState: AppWindowState
    let scenario: Scenario
    let showWorkspaceTopToolbar: Bool
    let splitModeEnabled: Bool
    let splitPaneID: Int
    @State var isSplitPaneActive: Bool
    @State private var interactionRuntime = WriterInteractionRuntime()
    @StateObject private var mainCanvasViewState = MainCanvasViewState()
    @StateObject var mainCanvasScrollCoordinator = MainCanvasScrollCoordinator()
    @StateObject var focusModeLayoutCoordinator = FocusModeLayoutCoordinator()
    @StateObject private var aiFeatureState = WriterAIFeatureState()
    @StateObject private var editEndAutoBackupState = WriterEditEndAutoBackupState()
    @StateObject private var scenarioObservedState: ScenarioWriterObservedState
    @StateObject var indexBoardCanvasDerivedCache = IndexBoardCanvasDerivedCache()
    @ObservedObject var indexBoardRuntime = IndexBoardRuntime.shared

    init(
        scenario: Scenario,
        showWorkspaceTopToolbar: Bool = true,
        splitModeEnabled: Bool = false,
        splitPaneID: Int = 2
    ) {
        self.scenario = scenario
        self.showWorkspaceTopToolbar = showWorkspaceTopToolbar
        self.splitModeEnabled = splitModeEnabled
        self.splitPaneID = splitPaneID
        self._isSplitPaneActive = State(initialValue: !splitModeEnabled || splitPaneID == 2)
        self._scenarioObservedState = StateObject(wrappedValue: ScenarioWriterObservedState(scenario: scenario))
    }

    @AppStorage("fontSize") var fontSize: Double = 14.0
    @AppStorage("appearance") var appearance: String = "dark"
    @AppStorage("backgroundColorHex") var backgroundColorHex: String = "F4F2EE"
    @AppStorage("darkBackgroundColorHex") var darkBackgroundColorHex: String = "111418"
    @AppStorage("cardBaseColorHex") var cardBaseColorHex: String = "FFFFFF"
    @AppStorage("cardActiveColorHex") var cardActiveColorHex: String = "BFD7FF"
    @AppStorage("cardRelatedColorHex") var cardRelatedColorHex: String = "DDE9FF"
    @AppStorage("darkCardBaseColorHex") var darkCardBaseColorHex: String = "1A2029"
    @AppStorage("darkCardActiveColorHex") var darkCardActiveColorHex: String = "2A3A4E"
    @AppStorage("darkCardRelatedColorHex") var darkCardRelatedColorHex: String = "242F3F"
    @AppStorage("indexBoardThemePresetID") var indexBoardThemePresetID: String = IndexBoardThemePreset.currentDefault.rawValue
    @AppStorage("exportCenteredFontSize") var exportCenteredFontSize: Double = 12.0
    @AppStorage("exportCenteredCharacterBold") var exportCenteredCharacterBold: Bool = true
    @AppStorage("exportCenteredSceneHeadingBold") var exportCenteredSceneHeadingBold: Bool = true
    @AppStorage("exportCenteredShowRightSceneNumber") var exportCenteredShowRightSceneNumber: Bool = false
    @AppStorage("exportKoreanFontSize") var exportKoreanFontSize: Double = 11.0
    @AppStorage("exportKoreanSceneBold") var exportKoreanSceneBold: Bool = true
    @AppStorage("exportKoreanCharacterBold") var exportKoreanCharacterBold: Bool = true
    @AppStorage("exportKoreanCharacterAlignment") var exportKoreanCharacterAlignment: String = "right"
    @AppStorage("focusTypewriterEnabled") var focusTypewriterEnabled: Bool = false
    @AppStorage("focusNavigationAnimationEnabled") var focusNavigationAnimationEnabled: Bool = false
    @AppStorage("focusTypewriterBaseline") var focusTypewriterBaseline: Double = 0.60
    @AppStorage("focusModeLineSpacingValueTemp") var focusModeLineSpacingValue: Double = 4.5
    @AppStorage("mainCardLineSpacingValueV2") var mainCardLineSpacingValue: Double = 5.0
    @AppStorage("mainCardVerticalGap") var mainCardVerticalGap: Double = 0.0
    @AppStorage("mainCanvasHorizontalScrollMode") var mainCanvasHorizontalScrollModeRawValue: Int = MainCanvasHorizontalScrollMode.twoStep.rawValue
    @AppStorage("mainWorkspaceZoomScale") var mainWorkspaceZoomScale: Double = 1.0
    @AppStorage("geminiModelID") var geminiModelID: String = "gemini-3.1-pro-preview"
    @AppStorage("autoBackupEnabledOnQuit") var autoBackupEnabledOnQuit: Bool = true
    @AppStorage("autoBackupDirectoryPath") var autoBackupDirectoryPath: String = ""
    @AppStorage("lastEditedScenarioID") var lastEditedScenarioID: String = ""
    @AppStorage("lastEditedCardID") var lastEditedCardID: String = ""
    @AppStorage("lastFocusedScenarioID") var lastFocusedScenarioID: String = ""
    @AppStorage("lastFocusedCardID") var lastFocusedCardID: String = ""
    @AppStorage("lastFocusedCaretLocation") var lastFocusedCaretLocation: Int = -1
    @AppStorage("lastFocusedWasEditing") var lastFocusedWasEditing: Bool = false
    @AppStorage("lastFocusedWasFocusMode") var lastFocusedWasFocusMode: Bool = false
    @AppStorage("lastFocusedViewportScenarioID") var lastFocusedViewportScenarioID: String = ""
    @AppStorage("lastFocusedViewportOffsetsJSON") var lastFocusedViewportOffsetsJSON: String = ""
    @AppStorage("lastFocusedMainCanvasHorizontalOffsetsJSON") var lastFocusedMainCanvasHorizontalOffsetsJSON: String = ""

    @State var activeCardID: UUID? = nil
    @State var selectedCardIDs: Set<UUID> = []
    @State var editingCardID: UUID? = nil
    @State var mainEditorSession = MainEditorSessionState()
    @State var mainEditorEntryFinishGuardCardID: UUID? = nil
    @State var mainEditorEntryFinishGuardUntil: Date = .distantPast
    @State var mainEditingScrollIsolationUntil: Date = .distantPast
    @State var mainEditingScrollIsolationTargetCardID: UUID? = nil
    @State var pendingMainPreemptiveFocusNavigationTargetID: UUID? = nil
    @State var indexBoardEditorDraft: IndexBoardEditorDraft? = nil
    @State var isIndexBoardInlineEditing: Bool = false
    @State var pendingIndexBoardCreationPrevStateByCardID: [UUID: ScenarioState] = [:]
    @State var showDeleteAlert: Bool = false
    @State var pendingUpperCardCreationRequest: UpperCardCreationRequest? = nil
    @State var mainArrowRepeatAnimationSuppressedUntil: Date = .distantPast
    @State var splitPaneAutoLinkEditsEnabled: Bool = true
    
    @State var showTimeline: Bool = false
    @State var showAIChat: Bool = false
    @FocusState var isAIChatInputFocused: Bool

    @State var exportMessage: String? = nil
    @State var showExportAlert: Bool = false

    @State var searchText: String = ""
    @State var linkedCardsFilterEnabled: Bool = false
    @State var linkedCardAnchorID: UUID? = nil
    @FocusState var isSearchFocused: Bool
    @FocusState var isNamedSnapshotSearchFocused: Bool
    @FocusState var focusModeEditorCardID: UUID?
    @FocusState var isFocusModeSearchFieldFocused: Bool

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
    @State var focusModePresentationPhase: FocusModePresentationPhase = .inactive
    @State var showFocusModeSearchPopup: Bool = false
    @State var focusModeSearchText: String = ""
    @State var focusModeSearchMatches: [FocusModeSearchMatch] = []
    @State var focusModeSearchSelectedMatchIndex: Int = -1
    @State var focusModeSearchHighlightRequestID: Int = 0
    @State var focusModeSearchPersistentHighlight: FocusModeSearchMatch? = nil
    @State var focusModeSearchHighlightTextViewBox = WeakTextViewBox()
    @State var focusModeNextCardScrollAnchor: UnitPoint? = nil
    @State var focusModeNextCardScrollAnimated: Bool = true
    @State var focusModeEntryWorkspaceSnapshot: FocusModeWorkspaceSnapshot? = nil
    @State var suppressFocusModeScrollOnce: Bool = false
    @State var focusPendingProgrammaticBeginEditCardID: UUID? = nil
    @State var focusModeCaretRequestID: Int = 0
    @State var focusModeCaretRequestStartedAt: Date = .distantPast
    @State var focusModeExitTeardownUntil: Date = .distantPast
    @State var focusModeBoundaryTransitionPendingReveal: Bool = false
    @State var focusModePendingFallbackRevealCardID: UUID? = nil
    @State var focusModeFallbackRevealIssuedCardID: UUID? = nil
    @State var focusModeFallbackRevealTick: Int = 0
    @State var focusModeSelectionObserver: NSObjectProtocol? = nil
    @State var mainSelectionObserver: NSObjectProtocol? = nil
    @State var mainCaretEnsureWorkItem: DispatchWorkItem? = nil
    @State var focusExcludedResponderObjectID: ObjectIdentifier? = nil
    @State var focusExcludedResponderUntil: Date = .distantPast
    @State var focusDeleteSelectionLockedCardID: UUID? = nil
    @State var focusDeleteSelectionLockUntil: Date = .distantPast
    @State var mainCaretRestoreRequestID: Int = 0
    @State var focusCaretEnsureWorkItem: DispatchWorkItem? = nil
    @State var focusCaretPendingTypewriter: Bool = false
    @State var focusTypewriterDeferredUntilCompositionEnd: Bool = false
    @State var focusObservedBodyHeightByCardID: [UUID: CGFloat] = [:]
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
    @State var mainBoundaryFeedbackCardID: UUID? = nil
    @State var mainBoundaryFeedbackKeyCode: UInt16? = nil
    @State var mainRecentVerticalArrowKeyCode: UInt16? = nil
    @State var mainRecentVerticalArrowAt: Date = .distantPast
    @State var keyboardRangeSelectionAnchorCardID: UUID? = nil
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
    @State var pendingFountainClipboardPastePreview: FountainClipboardPastePreview? = nil
    @State var showFountainClipboardPasteDialog: Bool = false
    @State var fountainClipboardPasteSelection: StructuredTextPasteOption = .plainText
    @State var fountainClipboardPasteSourceTextViewBox = WeakTextViewBox()
    @State var historyBarMeasuredHeight: CGFloat = 0
    @State var historyRetentionLastAppliedCount: Int = 0
    @State var caretEnsureBurstWorkItems: [DispatchWorkItem] = []
    @State var mainColumnCachedEditorSlotFramesByKey: [String: [UUID: CGRect]] = [:]
    @State var inactivePaneSnapshotState = InactivePaneSnapshotState()
    @State var scenarioTimestampSuppressionActive: Bool = false
    @State var editingSessionHadTextMutation: Bool = false
    @State var didRestoreStartupFocusState: Bool = false
    @State var didRestoreStartupViewportState: Bool = false
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

    func performWithoutAnimation(_ updates: () -> Void) {
        var transaction = Transaction()
        transaction.animation = nil
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            updates()
        }
    }

    let timelineWidth: CGFloat = TimelinePanelLayoutMetrics.panelWidth
    let historyOverlayBottomInset: CGFloat = 88
    let columnWidth: CGFloat = MainCanvasLayoutMetrics.columnWidth
    let mainParentGroupSeparatorHeight: CGFloat = 3

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

    var focusModeWindowBackgroundActive: Bool {
        get { appWindowState.focusModeWindowBackgroundActive }
        nonmutating set { appWindowState.focusModeWindowBackgroundActive = newValue }
    }

    var mainCardRenderSettings: MainCardRenderSettings {
        MainCardRenderSettings(
            fontSize: CGFloat(fontSize),
            appearance: appearance,
            lineSpacing: CGFloat(mainCardLineSpacingValue),
            cardBaseColorHex: cardBaseColorHex,
            cardActiveColorHex: cardActiveColorHex,
            cardRelatedColorHex: cardRelatedColorHex,
            darkCardBaseColorHex: darkCardBaseColorHex,
            darkCardActiveColorHex: darkCardActiveColorHex,
            darkCardRelatedColorHex: darkCardRelatedColorHex
        )
    }

    var acceptsKeyboardInput: Bool {
        !splitModeEnabled || isSplitPaneActive
    }

    var activeAncestorIDs: Set<UUID> {
        get { interactionRuntime.activeAncestorIDs }
        nonmutating set { interactionRuntime.activeAncestorIDs = newValue }
    }

    var activeDescendantIDs: Set<UUID> {
        get { interactionRuntime.activeDescendantIDs }
        nonmutating set { interactionRuntime.activeDescendantIDs = newValue }
    }

    var activeSiblingIDs: Set<UUID> {
        get { interactionRuntime.activeSiblingIDs }
        nonmutating set { interactionRuntime.activeSiblingIDs = newValue }
    }

    var activeRelationSourceCardID: UUID? {
        get { interactionRuntime.activeRelationSourceCardID }
        nonmutating set { interactionRuntime.activeRelationSourceCardID = newValue }
    }

    var activeRelationSourceCardsVersion: Int {
        get { interactionRuntime.activeRelationSourceCardsVersion }
        nonmutating set { interactionRuntime.activeRelationSourceCardsVersion = newValue }
    }

    var activeRelationFingerprint: Int {
        get { interactionRuntime.activeRelationFingerprint }
        nonmutating set { interactionRuntime.activeRelationFingerprint = newValue }
    }

    var lastActiveCardID: UUID? {
        get { interactionRuntime.lastActiveCardID }
        nonmutating set { interactionRuntime.lastActiveCardID = newValue }
    }

    var lastScrolledLevel: Int {
        get { interactionRuntime.lastScrolledLevel }
        nonmutating set { interactionRuntime.lastScrolledLevel = newValue }
    }

    var pendingMainHorizontalScrollAnimation: Bool? {
        get { interactionRuntime.pendingMainHorizontalScrollAnimation }
        nonmutating set { interactionRuntime.pendingMainHorizontalScrollAnimation = newValue }
    }

    var pendingMainClickFocusTargetID: UUID? {
        get { interactionRuntime.pendingMainClickFocusTargetID }
        nonmutating set { interactionRuntime.pendingMainClickFocusTargetID = newValue }
    }

    var pendingMainClickHorizontalFocusTargetID: UUID? {
        get { interactionRuntime.pendingMainClickHorizontalFocusTargetID }
        nonmutating set { interactionRuntime.pendingMainClickHorizontalFocusTargetID = newValue }
    }

    var pendingMainReorderHorizontalOffsetX: CGFloat? {
        get { interactionRuntime.pendingMainReorderHorizontalOffsetX }
        nonmutating set { interactionRuntime.pendingMainReorderHorizontalOffsetX = newValue }
    }

    var pendingMainEditingViewportKeepVisibleCardID: UUID? {
        get { interactionRuntime.pendingMainEditingViewportKeepVisibleCardID }
        nonmutating set { interactionRuntime.pendingMainEditingViewportKeepVisibleCardID = newValue }
    }

    var pendingMainEditingViewportRevealEdge: MainEditingViewportRevealEdge? {
        get { interactionRuntime.pendingMainEditingViewportRevealEdge }
        nonmutating set { interactionRuntime.pendingMainEditingViewportRevealEdge = newValue }
    }

    var pendingMainEditingSiblingNavigationTargetID: UUID? {
        get { interactionRuntime.pendingMainEditingSiblingNavigationTargetID }
        nonmutating set { interactionRuntime.pendingMainEditingSiblingNavigationTargetID = newValue }
    }

    var pendingMainEditingBoundaryNavigationTargetID: UUID? {
        get { interactionRuntime.pendingMainEditingBoundaryNavigationTargetID }
        nonmutating set { interactionRuntime.pendingMainEditingBoundaryNavigationTargetID = newValue }
    }

    var pendingMainReorderMotionCardIDs: [UUID] {
        get { interactionRuntime.pendingMainReorderMotionCardIDs }
        nonmutating set { interactionRuntime.pendingMainReorderMotionCardIDs = newValue }
    }

    var pendingMainDeferredColumnViewportRestoreOffsets: [String: CGFloat] {
        get { interactionRuntime.pendingMainDeferredColumnViewportRestoreOffsets }
        nonmutating set { interactionRuntime.pendingMainDeferredColumnViewportRestoreOffsets = newValue }
    }

    var pendingMainCanvasRestoreRequest: MainCanvasViewState.RestoreRequest? {
        get { mainCanvasViewState.pendingRestoreRequest }
        nonmutating set { mainCanvasViewState.pendingRestoreRequest = newValue }
    }

    func scheduleMainCanvasRestoreRequest(
        targetCardID: UUID,
        visibleLevel: Int? = nil,
        forceSemantic: Bool = false,
        reason: MainCanvasViewState.RestoreRequest.Reason = .generic
    ) {
        indexBoardRestoreTrace(
            "main_canvas_schedule_restore_request",
            "target=\(debugRestoreUUID(targetCardID)) visibleLevel=\(visibleLevel.map(String.init) ?? "nil") " +
            "forceSemantic=\(forceSemantic) reason=\(reason) active=\(debugRestoreUUID(activeCardID)) " +
            "editing=\(debugRestoreUUID(editingCardID)) suppressHorizontal=\(suppressHorizontalAutoScroll) " +
            "currentOffset=\(debugRestoreCGFloat(mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalOffset()))"
        )
        mainCanvasViewState.scheduleRestoreRequest(
            targetCardID: targetCardID,
            visibleLevel: visibleLevel,
            forceSemantic: forceSemantic,
            reason: reason
        )
    }

    var suppressAutoScrollOnce: Bool {
        get { mainCanvasViewState.suppressAutoScrollOnce }
        nonmutating set { mainCanvasViewState.suppressAutoScrollOnce = newValue }
    }

    var suppressHorizontalAutoScroll: Bool {
        get { mainCanvasViewState.suppressHorizontalAutoScroll }
        nonmutating set { mainCanvasViewState.suppressHorizontalAutoScroll = newValue }
    }

    var mainNavigationSettleTick: Int {
        get { mainCanvasViewState.navigationSettleTick }
        nonmutating set { mainCanvasViewState.navigationSettleTick = newValue }
    }

    var maxLevelCount: Int {
        get { mainCanvasViewState.maxLevelCount }
        nonmutating set { mainCanvasViewState.maxLevelCount = newValue }
    }

    var mainCanvasHorizontalScrollMode: MainCanvasHorizontalScrollMode {
        get { MainCanvasHorizontalScrollMode(rawValue: mainCanvasHorizontalScrollModeRawValue) ?? .twoStep }
        nonmutating set { mainCanvasHorizontalScrollModeRawValue = newValue.rawValue }
    }

    var mainCanvasDiagnosticsOwnerKey: String {
        let paneKey = splitModeEnabled ? splitPaneID : 0
        return "scenario:\(scenario.id.uuidString)|pane:\(paneKey)"
    }

    func resolvedMainCanvasHorizontalViewportSnapshotOffset() -> CGFloat? {
        if let liveOffset = mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalOffset() {
            return max(0, liveOffset)
        }
        let persistenceKey = mainCanvasHorizontalViewportPersistenceKey()
        return restoredMainCanvasHorizontalViewportOffsets()[persistenceKey].map { max(0, $0) }
    }

    func mainCanvasInteractionFingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(activeCardID)
        hasher.combine(editingCardID)
        hasher.combine(selectedCardIDs.count)
        for id in selectedCardIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            hasher.combine(id)
        }
        hasher.combine(activeRelationFingerprint)
        return hasher.finalize()
    }

    var scenarioCardsVersion: Int {
        scenarioObservedState.cardsVersion
    }

    var scenarioHistoryVersion: Int {
        scenarioObservedState.historyVersion
    }

    var scenarioLinkedCardsVersion: Int {
        scenarioObservedState.linkedCardsVersion
    }

    var pendingActiveCardID: UUID? {
        get { interactionRuntime.pendingActiveCardID }
        nonmutating set { interactionRuntime.pendingActiveCardID = newValue }
    }

    var resolvedLevelsWithParentsVersion: Int {
        get { interactionRuntime.resolvedLevelsWithParentsVersion }
        nonmutating set { interactionRuntime.resolvedLevelsWithParentsVersion = newValue }
    }

    var resolvedLevelsWithParentsCache: [LevelData] {
        get { interactionRuntime.resolvedLevelsWithParentsCache }
        nonmutating set { interactionRuntime.resolvedLevelsWithParentsCache = newValue }
    }

    var displayedMainLevelsCacheKey: DisplayedMainLevelsCacheKey? {
        get { interactionRuntime.displayedMainLevelsCacheKey }
        nonmutating set { interactionRuntime.displayedMainLevelsCacheKey = newValue }
    }

    var displayedMainLevelsCache: [LevelData] {
        get { interactionRuntime.displayedMainLevelsCache }
        nonmutating set { interactionRuntime.displayedMainLevelsCache = newValue }
    }

    var displayedMainCardLocationByIDCache: [UUID: (level: Int, index: Int)] {
        get { interactionRuntime.displayedMainCardLocationByIDCache }
        nonmutating set { interactionRuntime.displayedMainCardLocationByIDCache = newValue }
    }

    var mainColumnLastFocusRequestByKey: [String: MainColumnFocusRequest] {
        get { interactionRuntime.mainColumnLastFocusRequestByKey }
        nonmutating set { interactionRuntime.mainColumnLastFocusRequestByKey = newValue }
    }

    var mainColumnViewportOffsetByKey: [String: CGFloat] {
        get { interactionRuntime.mainColumnViewportOffsetByKey }
        nonmutating set { interactionRuntime.mainColumnViewportOffsetByKey = newValue }
    }

    var mainColumnObservedCardFramesByKey: [String: [UUID: CGRect]] {
        get { interactionRuntime.mainColumnObservedCardFramesByKey }
        nonmutating set { interactionRuntime.mainColumnObservedCardFramesByKey = newValue }
    }

    var mainColumnObservedEditorSlotFramesByKey: [String: [UUID: CGRect]] {
        get { interactionRuntime.mainColumnObservedEditorSlotFramesByKey }
        nonmutating set { interactionRuntime.mainColumnObservedEditorSlotFramesByKey = newValue }
    }

    var mainColumnLayoutSnapshotByKey: [MainColumnLayoutCacheKey: MainColumnLayoutSnapshot] {
        get { interactionRuntime.mainColumnLayoutSnapshotByKey }
        nonmutating set { interactionRuntime.mainColumnLayoutSnapshotByKey = newValue }
    }

    var mainCardHeightRecordByKey: [MainCardHeightCacheKey: MainCardHeightRecord] {
        get { interactionRuntime.mainCardHeightRecordByKey }
        nonmutating set { interactionRuntime.mainCardHeightRecordByKey = newValue }
    }

    var mainColumnViewportCaptureSuspendedUntil: Date {
        get { interactionRuntime.mainColumnViewportCaptureSuspendedUntil }
        nonmutating set { interactionRuntime.mainColumnViewportCaptureSuspendedUntil = newValue }
    }

    var mainColumnViewportRestoreUntil: Date {
        get { interactionRuntime.mainColumnViewportRestoreUntil }
        nonmutating set { interactionRuntime.mainColumnViewportRestoreUntil = newValue }
    }

    var mainArrowNavigationSettleWorkItem: DispatchWorkItem? {
        get { interactionRuntime.mainArrowNavigationSettleWorkItem }
        nonmutating set { interactionRuntime.mainArrowNavigationSettleWorkItem = newValue }
    }

    var mainCaretLocationByCardID: [UUID: Int] {
        get { interactionRuntime.mainCaretLocationByCardID }
        nonmutating set { interactionRuntime.mainCaretLocationByCardID = newValue }
    }

    var mainLineSpacingAppliedCardID: UUID? {
        get { interactionRuntime.mainLineSpacingAppliedCardID }
        nonmutating set { interactionRuntime.mainLineSpacingAppliedCardID = newValue }
    }

    var mainLineSpacingAppliedValue: CGFloat {
        get { interactionRuntime.mainLineSpacingAppliedValue }
        nonmutating set { interactionRuntime.mainLineSpacingAppliedValue = newValue }
    }

    var mainLineSpacingAppliedResponderID: ObjectIdentifier? {
        get { interactionRuntime.mainLineSpacingAppliedResponderID }
        nonmutating set { interactionRuntime.mainLineSpacingAppliedResponderID = newValue }
    }

    var suppressMainFocusRestoreAfterFinishEditing: Bool {
        get { interactionRuntime.suppressMainFocusRestoreAfterFinishEditing }
        nonmutating set { interactionRuntime.suppressMainFocusRestoreAfterFinishEditing = newValue }
    }

    var mainSelectionLastCardID: UUID? {
        get { interactionRuntime.mainSelectionLastCardID }
        nonmutating set { interactionRuntime.mainSelectionLastCardID = newValue }
    }

    var mainSelectionLastLocation: Int {
        get { interactionRuntime.mainSelectionLastLocation }
        nonmutating set { interactionRuntime.mainSelectionLastLocation = newValue }
    }

    var mainSelectionLastLength: Int {
        get { interactionRuntime.mainSelectionLastLength }
        nonmutating set { interactionRuntime.mainSelectionLastLength = newValue }
    }

    var mainSelectionLastTextLength: Int {
        get { interactionRuntime.mainSelectionLastTextLength }
        nonmutating set { interactionRuntime.mainSelectionLastTextLength = newValue }
    }

    var mainSelectionLastResponderID: ObjectIdentifier? {
        get { interactionRuntime.mainSelectionLastResponderID }
        nonmutating set { interactionRuntime.mainSelectionLastResponderID = newValue }
    }

    var mainSelectionActiveEdge: MainSelectionActiveEdge {
        get { interactionRuntime.mainSelectionActiveEdge }
        nonmutating set { interactionRuntime.mainSelectionActiveEdge = newValue }
    }

    var mainCaretEnsureLastScheduledAt: Date {
        get { interactionRuntime.mainCaretEnsureLastScheduledAt }
        nonmutating set { interactionRuntime.mainCaretEnsureLastScheduledAt = newValue }
    }

    var mainProgrammaticCaretSuppressEnsureCardID: UUID? {
        get { interactionRuntime.mainProgrammaticCaretSuppressEnsureCardID }
        nonmutating set { interactionRuntime.mainProgrammaticCaretSuppressEnsureCardID = newValue }
    }

    var mainProgrammaticCaretExpectedCardID: UUID? {
        get { interactionRuntime.mainProgrammaticCaretExpectedCardID }
        nonmutating set { interactionRuntime.mainProgrammaticCaretExpectedCardID = newValue }
    }

    var mainProgrammaticCaretExpectedLocation: Int {
        get { interactionRuntime.mainProgrammaticCaretExpectedLocation }
        nonmutating set { interactionRuntime.mainProgrammaticCaretExpectedLocation = newValue }
    }

    var mainProgrammaticCaretSelectionIgnoreUntil: Date {
        get { interactionRuntime.mainProgrammaticCaretSelectionIgnoreUntil }
        nonmutating set { interactionRuntime.mainProgrammaticCaretSelectionIgnoreUntil = newValue }
    }

    var pendingFocusModeEntryCaretHint: (cardID: UUID, location: Int)? {
        get { interactionRuntime.pendingFocusModeEntryCaretHint }
        nonmutating set { interactionRuntime.pendingFocusModeEntryCaretHint = newValue }
    }

    var focusResponderCardByObjectID: [ObjectIdentifier: UUID] {
        get { interactionRuntime.focusResponderCardByObjectID }
        nonmutating set { interactionRuntime.focusResponderCardByObjectID = newValue }
    }

    var focusLineSpacingAppliedCardID: UUID? {
        get { interactionRuntime.focusLineSpacingAppliedCardID }
        nonmutating set { interactionRuntime.focusLineSpacingAppliedCardID = newValue }
    }

    var focusLineSpacingAppliedValue: CGFloat {
        get { interactionRuntime.focusLineSpacingAppliedValue }
        nonmutating set { interactionRuntime.focusLineSpacingAppliedValue = newValue }
    }

    var focusLineSpacingAppliedFontSize: CGFloat {
        get { interactionRuntime.focusLineSpacingAppliedFontSize }
        nonmutating set { interactionRuntime.focusLineSpacingAppliedFontSize = newValue }
    }

    var focusLineSpacingAppliedResponderID: ObjectIdentifier? {
        get { interactionRuntime.focusLineSpacingAppliedResponderID }
        nonmutating set { interactionRuntime.focusLineSpacingAppliedResponderID = newValue }
    }

    var focusSelectionLastCardID: UUID? {
        get { interactionRuntime.focusSelectionLastCardID }
        nonmutating set { interactionRuntime.focusSelectionLastCardID = newValue }
    }

    var focusSelectionLastLocation: Int {
        get { interactionRuntime.focusSelectionLastLocation }
        nonmutating set { interactionRuntime.focusSelectionLastLocation = newValue }
    }

    var focusSelectionLastLength: Int {
        get { interactionRuntime.focusSelectionLastLength }
        nonmutating set { interactionRuntime.focusSelectionLastLength = newValue }
    }

    var focusSelectionLastTextLength: Int {
        get { interactionRuntime.focusSelectionLastTextLength }
        nonmutating set { interactionRuntime.focusSelectionLastTextLength = newValue }
    }

    var focusSelectionLastResponderID: ObjectIdentifier? {
        get { interactionRuntime.focusSelectionLastResponderID }
        nonmutating set { interactionRuntime.focusSelectionLastResponderID = newValue }
    }

    var focusCaretEnsureLastScheduledAt: Date {
        get { interactionRuntime.focusCaretEnsureLastScheduledAt }
        nonmutating set { interactionRuntime.focusCaretEnsureLastScheduledAt = newValue }
    }

    var focusProgrammaticCaretExpectedCardID: UUID? {
        get { interactionRuntime.focusProgrammaticCaretExpectedCardID }
        nonmutating set { interactionRuntime.focusProgrammaticCaretExpectedCardID = newValue }
    }

    var focusProgrammaticCaretExpectedLocation: Int {
        get { interactionRuntime.focusProgrammaticCaretExpectedLocation }
        nonmutating set { interactionRuntime.focusProgrammaticCaretExpectedLocation = newValue }
    }

    var focusProgrammaticCaretSelectionIgnoreUntil: Date {
        get { interactionRuntime.focusProgrammaticCaretSelectionIgnoreUntil }
        nonmutating set { interactionRuntime.focusProgrammaticCaretSelectionIgnoreUntil = newValue }
    }

    var focusOffsetNormalizationLastAt: Date {
        get { interactionRuntime.focusOffsetNormalizationLastAt }
        nonmutating set { interactionRuntime.focusOffsetNormalizationLastAt = newValue }
    }

    var focusSelectionProcessingPending: Bool {
        get { interactionRuntime.focusSelectionProcessingPending }
        nonmutating set { interactionRuntime.focusSelectionProcessingPending = newValue }
    }

    var focusVerticalScrollAuthoritySequence: Int {
        get { interactionRuntime.focusVerticalScrollAuthoritySequence }
        nonmutating set { interactionRuntime.focusVerticalScrollAuthoritySequence = newValue }
    }

    var focusVerticalScrollAuthority: FocusModeVerticalScrollAuthority? {
        get { interactionRuntime.focusVerticalScrollAuthority }
        nonmutating set { interactionRuntime.focusVerticalScrollAuthority = newValue }
    }

    var historySaveRequestWorkItem: DispatchWorkItem? {
        get { interactionRuntime.historySaveRequestWorkItem }
        nonmutating set { interactionRuntime.historySaveRequestWorkItem = newValue }
    }

    var historySaveRequestNextAllowedAt: Date {
        get { interactionRuntime.historySaveRequestNextAllowedAt }
        nonmutating set { interactionRuntime.historySaveRequestNextAllowedAt = newValue }
    }

    var aiChatThreads: [AIChatThread] {
        get { aiFeatureState.chatThreads }
        nonmutating set { aiFeatureState.chatThreads = newValue }
    }

    var activeAIChatThreadID: UUID? {
        get { aiFeatureState.activeThreadID }
        nonmutating set { aiFeatureState.activeThreadID = newValue }
    }

    var aiChatInput: String {
        get { aiFeatureState.chatInput }
        nonmutating set { aiFeatureState.chatInput = newValue }
    }

    var aiCardDigestCache: [UUID: AICardDigest] {
        get { aiFeatureState.cardDigestCache }
        nonmutating set { aiFeatureState.cardDigestCache = newValue }
    }

    var aiEmbeddingIndexByCardID: [UUID: AIEmbeddingRecord] {
        get { aiFeatureState.embeddingIndexByCardID }
        nonmutating set { aiFeatureState.embeddingIndexByCardID = newValue }
    }

    var aiEmbeddingIndexModelID: String {
        get { aiFeatureState.embeddingIndexModelID }
        nonmutating set { aiFeatureState.embeddingIndexModelID = newValue }
    }

    var aiLastContextPreview: AIChatContextPreview? {
        get { aiFeatureState.lastContextPreview }
        nonmutating set { aiFeatureState.lastContextPreview = newValue }
    }

    var aiThreadsLoadedScenarioID: UUID? {
        get { aiFeatureState.threadsLoadedScenarioID }
        nonmutating set { aiFeatureState.threadsLoadedScenarioID = newValue }
    }

    var aiEmbeddingIndexLoadedScenarioID: UUID? {
        get { aiFeatureState.embeddingIndexLoadedScenarioID }
        nonmutating set { aiFeatureState.embeddingIndexLoadedScenarioID = newValue }
    }

    var aiThreadsSaveWorkItem: DispatchWorkItem? {
        get { aiFeatureState.threadsSaveWorkItem }
        nonmutating set { aiFeatureState.threadsSaveWorkItem = newValue }
    }

    var aiEmbeddingIndexSaveWorkItem: DispatchWorkItem? {
        get { aiFeatureState.embeddingIndexSaveWorkItem }
        nonmutating set { aiFeatureState.embeddingIndexSaveWorkItem = newValue }
    }

    var isAIChatLoading: Bool {
        get { aiFeatureState.isChatLoading }
        nonmutating set { aiFeatureState.isChatLoading = newValue }
    }

    var aiChatRequestTask: Task<Void, Never>? {
        get { aiFeatureState.chatRequestTask }
        nonmutating set { aiFeatureState.chatRequestTask = newValue }
    }

    var aiChatActiveRequestID: UUID? {
        get { aiFeatureState.chatActiveRequestID }
        nonmutating set { aiFeatureState.chatActiveRequestID = newValue }
    }

    var aiOptionsSheetAction: AICardAction? {
        get { aiFeatureState.optionsSheetAction }
        nonmutating set { aiFeatureState.optionsSheetAction = newValue }
    }

    var aiSelectedGenerationOptions: Set<AIGenerationOption> {
        get { aiFeatureState.selectedGenerationOptions }
        nonmutating set { aiFeatureState.selectedGenerationOptions = newValue }
    }

    var aiIsGenerating: Bool {
        get { aiFeatureState.isGenerating }
        nonmutating set { aiFeatureState.isGenerating = newValue }
    }

    var aiStatusMessage: String? {
        get { aiFeatureState.statusMessage }
        nonmutating set { aiFeatureState.statusMessage = newValue }
    }

    var aiStatusIsError: Bool {
        get { aiFeatureState.statusIsError }
        nonmutating set { aiFeatureState.statusIsError = newValue }
    }

    var aiCandidateState: AICandidateTrackingState {
        get { aiFeatureState.candidateState }
        nonmutating set { aiFeatureState.candidateState = newValue }
    }

    var aiChildSummaryLoadingCardIDs: Set<UUID> {
        get { aiFeatureState.childSummaryLoadingCardIDs }
        nonmutating set { aiFeatureState.childSummaryLoadingCardIDs = newValue }
    }

    var pendingEditEndAutoBackupWorkItem: DispatchWorkItem? {
        get { editEndAutoBackupState.pendingWorkItem }
        nonmutating set { editEndAutoBackupState.pendingWorkItem = newValue }
    }

    var isEditEndAutoBackupRunning: Bool {
        get { editEndAutoBackupState.isRunning }
        nonmutating set { editEndAutoBackupState.isRunning = newValue }
    }

    var hasPendingEditEndAutoBackupRequest: Bool {
        get { editEndAutoBackupState.hasPendingRequest }
        nonmutating set { editEndAutoBackupState.hasPendingRequest = newValue }
    }

    var aiChatInputBinding: Binding<String> {
        Binding(
            get: { aiChatInput },
            set: { aiChatInput = $0 }
        )
    }

    var aiOptionsSheetActionBinding: Binding<AICardAction?> {
        Binding(
            get: { aiOptionsSheetAction },
            set: { aiOptionsSheetAction = $0 }
        )
    }

    var isInactiveSplitPane: Bool {
        splitModeEnabled && !isSplitPaneActive
    }

    var shouldSuppressScenarioTimestampDuringEditing: Bool {
        acceptsKeyboardInput && editingCardID != nil
    }

    @FocusState var isMainViewFocused: Bool

    struct MainCanvasRenderState: Equatable {
        let size: CGSize
        let availableWidth: CGFloat
        let historyIndex: Int
        let acceptsKeyboardInput: Bool
        let isPreviewingHistory: Bool
        let backgroundSignature: String
        let contentFingerprint: Int
        let interactionFingerprint: Int
    }

    struct MainCanvasHost: View, Equatable {
        let renderState: MainCanvasRenderState
        @ObservedObject var viewState: MainCanvasViewState
        @ObservedObject var scrollCoordinator: MainCanvasScrollCoordinator
        let backgroundColor: Color
        let onBackgroundTap: () -> Void
        let onHistoryIndexChange: (ScrollViewProxy) -> Void
        let onActiveCardChange: (UUID?, ScrollViewProxy, CGFloat) -> Void
        let onMotionIntent: (ScrollViewProxy, CGFloat) -> Void
        let onMotionSessionClose: (ScrollViewProxy, CGFloat) -> Void
        let onNavigationSettle: (ScrollViewProxy, CGFloat) -> Void
        let onRestoreRequest: (ScrollViewProxy, CGFloat) -> Void
        let onAppear: (ScrollViewProxy, CGFloat) -> Void
        let scrollableContent: () -> AnyView

        static func == (lhs: MainCanvasHost, rhs: MainCanvasHost) -> Bool {
            lhs.renderState == rhs.renderState
        }

        var body: some View {
            ZStack {
                backgroundColor
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !renderState.isPreviewingHistory {
                            onBackgroundTap()
                        }
                    }

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        scrollableContent()
                    }
                    .background(
                        MainCanvasHorizontalScrollViewAccessor(
                            scrollCoordinator: scrollCoordinator
                        )
                    )
                    .onChange(of: renderState.historyIndex) { _, _ in
                        onHistoryIndexChange(proxy)
                    }
                    .onChange(of: scrollCoordinator.navigationIntentTick) { _, _ in
                        onMotionIntent(proxy, renderState.availableWidth)
                    }
                    .onChange(of: viewState.focusNavigationTick) { _, _ in
                        onActiveCardChange(
                            viewState.focusNavigationTargetID,
                            proxy,
                            renderState.availableWidth
                        )
                    }
                    .onChange(of: scrollCoordinator.motionSessionCloseTick) { _, _ in
                        onMotionSessionClose(proxy, renderState.availableWidth)
                    }
                    .onChange(of: viewState.navigationSettleTick) { _, _ in
                        onNavigationSettle(proxy, renderState.availableWidth)
                    }
                    .onChange(of: viewState.pendingRestoreRequest) { _, _ in
                        onRestoreRequest(proxy, renderState.availableWidth)
                    }
                    .onChange(of: renderState.contentFingerprint) { _, _ in
                        if viewState.pendingRestoreRequest != nil {
                            onRestoreRequest(proxy, renderState.availableWidth)
                        }
                    }
                    .onAppear {
                        onAppear(proxy, renderState.availableWidth)
                    }
                }
            }
            .allowsHitTesting(true)
        }
    }

    enum WorkspaceTrailingPanelMode: Int {
        case hidden
        case timeline
        case aiChat
    }

    struct TrailingWorkspacePanelRenderState: Equatable {
        let mode: WorkspaceTrailingPanelMode
        let appearanceSignature: String
        let contentFingerprint: Int
    }

    struct TrailingWorkspacePanelHost: View, Equatable {
        let renderState: TrailingWorkspacePanelRenderState
        let panelWidth: CGFloat
        let backgroundColor: Color
        let dividerColor: Color
        let content: () -> AnyView

        static func == (lhs: TrailingWorkspacePanelHost, rhs: TrailingWorkspacePanelHost) -> Bool {
            lhs.renderState == rhs.renderState
        }

        var body: some View {
            if renderState.mode != .hidden {
                HStack(spacing: 0) {
                    Divider().background(dividerColor)
                    content()
                        .frame(width: panelWidth)
                        .background(backgroundColor)
                        .transition(.move(edge: .trailing))
                }
            }
        }
    }

    struct HistoryOverlayRenderState: Equatable {
        let appearanceSignature: String
        let contentFingerprint: Int
        let containerHeightBucket: Int
        let bottomInsetBucket: Int
    }

    struct HistoryOverlayHost: View, Equatable {
        let renderState: HistoryOverlayRenderState
        let panelWidth: CGFloat
        let containerHeight: CGFloat
        let bottomInset: CGFloat
        let backgroundColor: Color
        let dividerColor: Color
        let content: () -> AnyView

        static func == (lhs: HistoryOverlayHost, rhs: HistoryOverlayHost) -> Bool {
            lhs.renderState == rhs.renderState
        }

        var body: some View {
            HStack(spacing: 0) {
                Divider().background(dividerColor)
                content()
                    .frame(width: panelWidth, height: max(320, containerHeight - bottomInset))
                    .background(backgroundColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.bottom, bottomInset)
        }
    }

    struct WorkspaceToolbarRenderState: Equatable {
        let appearanceSignature: String
        let isHistoryVisible: Bool
        let isTimelineVisible: Bool
        let isAIChatVisible: Bool
        let contentFingerprint: Int
    }

    struct WorkspaceToolbarHost: View, Equatable {
        let renderState: WorkspaceToolbarRenderState
        let content: () -> AnyView

        static func == (lhs: WorkspaceToolbarHost, rhs: WorkspaceToolbarHost) -> Bool {
            lhs.renderState == rhs.renderState
        }

        var body: some View {
            content()
        }
    }

    struct BottomHistoryBarRenderState: Equatable {
        let appearanceSignature: String
        let contentFingerprint: Int
    }

    struct BottomHistoryBarHost: View, Equatable {
        let renderState: BottomHistoryBarRenderState
        let content: () -> AnyView

        static func == (lhs: BottomHistoryBarHost, rhs: BottomHistoryBarHost) -> Bool {
            lhs.renderState == rhs.renderState
        }

        var body: some View {
            content()
        }
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
        workspaceCommandBoundRoot(
            workspaceLifecycleBoundRoot(
                workspaceFocusedRoot(for: geometry)
            )
        )
    }

    func workspaceFocusedRoot(for geometry: GeometryProxy) -> some View {
        workspaceLayout(for: geometry)
            .focusable()
            .focused($isMainViewFocused)
            .focusEffectDisabled()
    }

    func workspaceLifecycleBoundRoot<Content: View>(_ root: Content) -> some View {
        workspaceEditorBoundRoot(
            workspacePreferenceBoundRoot(
                workspaceScenarioBoundRoot(
                    workspacePrimaryLifecycleRoot(root)
                )
            )
        )
    }

    func workspacePrimaryLifecycleRoot<Content: View>(_ root: Content) -> some View {
        root
            .simultaneousGesture(TapGesture().onEnded {
                activateSplitPaneIfNeeded()
            })
            .onAppear {
                handleWorkspaceAppear()
            }
            .onChange(of: showTimeline) { _, isShown in
                handleTimelineVisibilityChange(isShown)
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
            .onChange(of: mainCanvasInteractionFingerprint()) { oldValue, newValue in
                guard oldValue != newValue else { return }
                syncMainCanvasInteractionState()
            }
            .onChange(of: isSplitPaneActive) { _, _ in
                syncScenarioTimestampSuppressionIfNeeded()
            }
            .onChange(of: scenario.id) { _, _ in
                syncScenarioObservedState()
            }
            .onDisappear {
                handleWorkspaceDisappear()
            }
    }

    func workspaceScenarioBoundRoot<Content: View>(_ root: Content) -> some View {
        root
            .onChange(of: scenarioCardsVersion) { _, _ in
                handleScenarioCardsVersionChange()
            }
            .onChange(of: scenarioHistoryVersion) { _, _ in
                handleScenarioHistoryVersionChange()
            }
            .onChange(of: scenarioLinkedCardsVersion) { _, _ in
                handleScenarioLinkedCardsVersionChange()
            }
    }

    func workspacePreferenceBoundRoot<Content: View>(_ root: Content) -> some View {
        root
            .onChange(of: showFocusMode) { _, isOn in
                handleShowFocusModeChange(isOn)
            }
            .onChange(of: isIndexBoardActive) { _, isOn in
                handleIndexBoardVisibilityChange(isOn)
            }
            .onChange(of: mainWorkspaceZoomScale) { oldValue, newValue in
                guard abs(newValue - oldValue) > 0.0001 else { return }
                requestMainCanvasRestoreForZoomChange()
            }
            .onChange(of: mainCanvasHorizontalScrollModeRawValue) { oldValue, newValue in
                guard oldValue != newValue else { return }
                handleMainCanvasHorizontalScrollModeChange()
            }
            .onChange(of: focusTypewriterEnabled) { _, isOn in
                handleFocusTypewriterEnabledChange(isOn)
            }
    }

    func workspaceEditorBoundRoot<Content: View>(_ root: Content) -> some View {
        root
            .onAppear {
                mainWorkspacePhase0Mark(
                    "main-workspace-phase0 scenario=\(scenario.id.uuidString) pane=\(splitPaneID)"
                )
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
    }

    func workspaceCommandBoundRoot<Content: View>(_ root: Content) -> some View {
        root
            .onReceive(NotificationCenter.default.publisher(for: .waUndoRequested)) { _ in
                handleUndoRequestNotification()
            }
            .onReceive(NotificationCenter.default.publisher(for: .waRedoRequested)) { _ in
                handleRedoRequestNotification()
            }
            .onReceive(NotificationCenter.default.publisher(for: .waToggleFocusModeRequested)) { _ in
                handleToggleFocusModeRequestNotification()
            }
            .onReceive(NotificationCenter.default.publisher(for: .waOpenIndexBoardRequested)) { _ in
                handleOpenIndexBoardRequestNotification()
            }
            .onReceive(NotificationCenter.default.publisher(for: .waRequestSplitPaneFocus)) { notification in
                handleSplitPaneFocusRequestNotification(notification)
            }
            .onKeyPress(phases: [.down, .repeat]) { press in
                if !acceptsKeyboardInput { return .handled }
                if showFountainClipboardPasteDialog { return handleFountainClipboardPasteDialogKeyPress(press) }
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
            .confirmationDialog(
                "새 상위 카드 만들기",
                isPresented: Binding(
                    get: { pendingUpperCardCreationRequest != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingUpperCardCreationRequest = nil
                        }
                    }
                ),
                titleVisibility: .visible,
                presenting: pendingUpperCardCreationRequest
            ) { request in
                Button("빈 카드") {
                    createEmptyUpperCard(from: request)
                }
                Button("AI 요약") {
                    requestAIUpperCardSummary(from: request)
                }
                Button("취소", role: .cancel) {
                    pendingUpperCardCreationRequest = nil
                }
            } message: { request in
                if request.sourceCardIDs.count > 1 {
                    Text("선택한 카드들을 묶어 새 상위 카드를 만듭니다.")
                } else {
                    Text("현재 카드 위에 새 상위 카드를 만듭니다.")
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
            .sheet(item: aiOptionsSheetActionBinding) { action in
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
                if showFountainClipboardPasteDialog {
                    fountainClipboardPasteDialogOverlay
                }
                if showCloneCardPasteDialog {
                    cloneCardPasteDialogOverlay
                }
            }
            .onChange(of: showFountainClipboardPasteDialog) { _, isShown in
                if isShown {
                    resetFountainClipboardPasteDialogSelection()
                    return
                }
                if !isShown {
                    pendingFountainClipboardPastePreview = nil
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
    }

    func handleWorkspaceAppear() {
        mainCanvasScrollCoordinator.reset()
        MainCanvasNavigationDiagnostics.shared.reset(
            ownerKey: mainCanvasDiagnosticsOwnerKey,
            scenarioID: scenario.id,
            splitPaneID: splitModeEnabled ? splitPaneID : 0
        )
        syncMainCanvasInteractionState()
        syncScenarioObservedState()
        restoreStartupViewportIfNeeded()
        let restoredHorizontalViewport = restoreStartupMainCanvasHorizontalViewportIfNeeded()
        if activeCardID == nil, let startupCard = startupActiveCard() { changeActiveCard(to: startupCard) }
        restoreStartupFocusIfNeeded()
        if !restoredHorizontalViewport {
            requestStartupMainCanvasRestoreIfNeeded()
        }
        syncSplitPaneActiveCardState(activeCardID)
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

    func handleTimelineVisibilityChange(_ isShown: Bool) {
        if !isShown {
            linkedCardsFilterEnabled = false
            linkedCardAnchorID = nil
        } else if linkedCardsFilterEnabled {
            if let current = activeCardID, findCard(by: current) != nil {
                linkedCardAnchorID = current
            }
        }
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
        let clearedRequestCount = mainColumnLastFocusRequestByKey.count
        mainColumnLastFocusRequestByKey = [:]
        if let newID, scenario.rootCards.contains(where: { $0.id == newID }) {
            mainColumnViewportRestoreUntil = Date().addingTimeInterval(0.35)
        }
        bounceDebugLog(
            "handleActiveCardIDChange new=\(debugCardIDString(newID)) clearedRequests=\(clearedRequestCount) " +
            "restoreUntil=\(mainColumnViewportRestoreUntil.timeIntervalSince1970) \(debugFocusStateSummary())"
        )
        indexBoardRestoreTrace(
            "main_canvas_handle_active_card_change",
            "newID=\(debugRestoreUUID(newID)) clearedRequests=\(clearedRequestCount) " +
            "showFocusMode=\(showFocusMode) boardActive=\(isIndexBoardActive) " +
            "suppressOnce=\(suppressAutoScrollOnce) suppressHorizontal=\(suppressHorizontalAutoScroll) " +
            "restoreUntil=\(String(format: "%.3f", mainColumnViewportRestoreUntil.timeIntervalSince1970)) " +
            "offset=\(debugRestoreCGFloat(mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalOffset()))"
        )
        if let newID, findCard(by: newID) != nil {
            persistLastEditedCard(newID)
            if editingCardID == nil && !showFocusMode {
                persistLastFocusSnapshot(cardID: newID, isEditing: false, inFocusMode: false)
            }
        }
        syncSplitPaneActiveCardState(newID)
        if linkedCardsFilterEnabled, let newID, findCard(by: newID) != nil {
            linkedCardAnchorID = newID
        }
        guard acceptsKeyboardInput else { return }
        synchronizeActiveRelationState(for: newID)
        if pendingMainEditingSiblingNavigationTargetID == newID {
            pendingMainHorizontalScrollAnimation = nil
            syncMainCanvasInteractionState()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if pendingMainEditingSiblingNavigationTargetID == newID,
                   activeCardID == newID,
                   editingCardID == newID {
                    pendingMainEditingSiblingNavigationTargetID = nil
                }
            }
            return
        }
        let hasExplicitEditingVerticalTransition =
            editingCardID != nil &&
            (
                pendingMainEditingViewportKeepVisibleCardID == newID ||
                pendingMainEditingBoundaryNavigationTargetID == newID
            )
        if editingCardID != nil && !hasExplicitEditingVerticalTransition {
            syncMainCanvasInteractionState()
            return
        }
        let clickFocusedTarget = pendingMainClickHorizontalFocusTargetID == newID
        let clickFocusNavigationTarget = pendingMainClickFocusTargetID == newID
        let preemptivelyFocusedTarget = pendingMainPreemptiveFocusNavigationTargetID == newID
        if preemptivelyFocusedTarget {
            pendingMainPreemptiveFocusNavigationTargetID = nil
        }
        if mainColumnViewportRestoreUntil > Date(), !clickFocusedTarget {
            indexBoardRestoreTrace(
                "main_canvas_handle_active_card_change_preserve_viewport",
                "newID=\(debugRestoreUUID(newID)) restoreUntil=\(String(format: "%.3f", mainColumnViewportRestoreUntil.timeIntervalSince1970))"
            )
            syncMainCanvasInteractionState()
            return
        }
        if !preemptivelyFocusedTarget {
            publishMainColumnFocusNavigationIntent(
                for: newID,
                trigger: clickFocusNavigationTarget ? "clickFocus" : "activeCardChange"
            )
        }
        if clickFocusNavigationTarget {
            pendingMainClickFocusTargetID = nil
        }
        syncMainCanvasInteractionState(emitNavigationEvent: true)
    }

    func handleScenarioCardsVersionChange() {
        bounceDebugLog(
            "handleScenarioCardsVersionChange version=\(scenario.cardsVersion) " +
            "\(debugFocusStateSummary())"
        )
        mainColumnLastFocusRequestByKey = [:]
        if isInactiveSplitPane {
            scheduleInactivePaneSnapshotRefresh()
            return
        }
        synchronizeActiveRelationState(for: activeCardID)
        syncMainCanvasInteractionState()
        pruneAICandidateTracking()
    }

    func syncMainCanvasInteractionState(emitNavigationEvent: Bool = false) {
        let interactionFingerprint = mainCanvasInteractionFingerprint()
        if mainCanvasViewState.interactionFingerprint != interactionFingerprint {
            mainCanvasViewState.interactionFingerprint = interactionFingerprint
        }
        if emitNavigationEvent {
            mainCanvasViewState.focusNavigationTargetID = activeCardID
            mainCanvasViewState.focusNavigationTick &+= 1
        }
    }

    func handleScenarioHistoryVersionChange() {
        guard showHistoryBar else { return }
        let maxIndex = max(0, scenario.sortedSnapshots.count - 1)
        if historyIndex > Double(maxIndex) {
            historyIndex = Double(maxIndex)
            return
        }
        if isPreviewingHistory {
            handleHistoryIndexChange()
        }
    }

    func handleScenarioLinkedCardsVersionChange() {
        guard linkedCardsFilterEnabled else { return }
        guard resolvedLinkedCardsAnchorID() == nil else { return }
        linkedCardsFilterEnabled = false
        linkedCardAnchorID = nil
    }

    func handleMainCanvasHorizontalScrollModeChange() {
        guard !showFocusMode else { return }
        requestMainCanvasRestoreForHorizontalScrollModeChange()
    }

    func syncScenarioObservedState() {
        scenarioObservedState.bind(to: scenario)
    }

    func handleWorkspaceDisappear() {
        teardownIndexBoardIfNeeded(restoreEntryState: false)
        MainCanvasNavigationDiagnostics.shared.emitSummary(
            ownerKey: mainCanvasDiagnosticsOwnerKey,
            reason: "workspaceDisappear"
        )
        persistCurrentFocusSnapshotIfPossible()
        persistCurrentViewportSnapshotIfPossible()
        releaseScenarioTimestampSuppressionIfNeeded()
        cancelInactivePaneSnapshotRefresh()
        cancelAIChatRequest()
        flushAIThreadsPersistence()
        flushAIEmbeddingPersistence()
        mainCanvasScrollCoordinator.reset()
        pendingEditEndAutoBackupWorkItem?.cancel()
        pendingEditEndAutoBackupWorkItem = nil
        hasPendingEditEndAutoBackupRequest = false
        mainArrowNavigationSettleWorkItem?.cancel()
        mainArrowNavigationSettleWorkItem = nil
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
        mainColumnLastFocusRequestByKey = [:]
        focusModeLayoutCoordinator.reset()
        focusVerticalScrollAuthoritySequence = 0
        focusVerticalScrollAuthority = nil
        focusModeCaretRequestStartedAt = .distantPast
        if isOn {
            focusModeExitTeardownUntil = .distantPast
        }
        focusModeWindowBackgroundActive = isOn
        FocusMonitorRecorder.shared.record("focus.toggle", reason: "showFocusMode-onChange") {
            [
                "entering": isOn ? "true" : "false",
                "presentationPhase": focusModePresentationPhase.rawValue,
                "activeCardID": activeCardID?.uuidString ?? "nil",
                "editingCardID": editingCardID?.uuidString ?? "nil",
                "focusModeEditorCardID": focusModeEditorCardID?.uuidString ?? "nil"
            ]
        }
        if isOn {
            stopMainNavKeyMonitor()
            stopMainCaretMonitor()
            finalizeMainTypingCoalescing(reason: "focus-enter")
            resetMainTypingCoalescing()
            resetFocusTypingCoalescing()
            focusLastCommittedContentByCard = Dictionary(uniqueKeysWithValues: scenario.cards.map { ($0.id, $0.content) })
            startFocusModeKeyMonitor()
            startFocusModeScrollMonitor()
            startFocusModeCaretMonitor()
            guard let targetID = focusModeEditorCardID ?? editingCardID ?? activeCardID else { return }
            DispatchQueue.main.async {
                guard showFocusMode else { return }
                // Entry target preparation is already owned by enterFocusMode(with:).
                // Avoid a second beginFocusModeEditing(...) pass here.
                if focusModeEditorCardID == targetID {
                    return
                }
                let currentTargetID = editingCardID ?? activeCardID
                guard currentTargetID == targetID else { return }
                if editingCardID == targetID {
                    focusModeEditorCardID = targetID
                }
            }
            DispatchQueue.main.async {
                guard showFocusMode else { return }
                completeFocusModePresentationTransitionIfNeeded(entering: true)
            }
        } else {
            finalizeFocusTypingCoalescing(reason: "focus-exit")
            clearPersistentFocusModeSearchHighlight()
            closeFocusModeSearchPopup()
            stopFocusModeKeyMonitor()
            stopFocusModeScrollMonitor()
            stopFocusModeCaretMonitor()
            startMainNavKeyMonitor()
            startMainCaretMonitor()
            let entryWorkspaceSnapshot = focusModeEntryWorkspaceSnapshot
            if canReuseRetainedMainCanvasShellForFocusExit(using: entryWorkspaceSnapshot) {
                finalizeRetainedMainCanvasShellForFocusExitReuse()
            } else {
                requestMainCanvasRestoreForFocusExit(using: entryWorkspaceSnapshot)
                requestMainCanvasViewportRestoreForFocusExit(using: entryWorkspaceSnapshot)
            }
            focusModeEntryWorkspaceSnapshot = nil
            if let activeID = activeCardID {
                persistLastFocusSnapshot(cardID: activeID, isEditing: false, inFocusMode: false)
            }
            scheduleFocusModePresentationPhaseResetAfterExit()
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
        let expectedText = newID.flatMap { findCard(by: $0)?.content }
        mainWorkspacePhase0Log(
            "editing-card-change",
            "old=\(mainWorkspacePhase0CardID(oldID)) new=\(mainWorkspacePhase0CardID(newID)) " +
            "active=\(mainWorkspacePhase0CardID(activeCardID)) focusMode=\(showFocusMode) " +
            "responder=\(mainWorkspacePhase0ResponderSummary(expectedText: expectedText))"
        )
        if let newID {
            persistLastEditedCard(newID)
            if !showFocusMode {
                persistLastFocusSnapshot(cardID: newID, isEditing: true, inFocusMode: false)
            }
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
        let seedLocation: Int?
        if let newID {
            if mainEditorSession.requestedCardID != newID {
                let length = (findCard(by: newID)?.content as NSString?)?.length ?? 0
                let resolvedSeed = mainCaretLocationByCardID[newID].map { min(max(0, $0), length) }
                mainEditorSession = MainEditorSessionState(
                    requestedCardID: newID,
                    mountedCardID: nil,
                    textViewIdentity: nil,
                    caretSeedLocation: resolvedSeed,
                    isFirstResponderReady: false,
                    liveBodyHeight: nil
                )
                mainWorkspacePhase0Log(
                    "main-editor-session",
                    "phase=sync-request card=\(mainWorkspacePhase0CardID(newID)) seed=\(resolvedSeed.map(String.init) ?? "nil")"
                )
                seedLocation = resolvedSeed
            } else {
                seedLocation = mainEditorSession.caretSeedLocation
            }
        } else {
            mainEditorSession = MainEditorSessionState()
            mainWorkspacePhase0Log(
                "main-editor-session",
                "phase=clear"
            )
            seedLocation = nil
        }
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
            if !showFocusMode, let activeID = activeCardID {
                persistLastFocusSnapshot(cardID: activeID, isEditing: false, inFocusMode: false)
            }
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
        let isBoundaryNavigation = pendingMainEditingBoundaryNavigationTargetID == newID
        let suppressInitialEnsure = isBoundaryNavigation || mainProgrammaticCaretSuppressEnsureCardID == newID
        restoreMainEditingCaret(
            for: newID,
            location: seedLocation,
            suppressInitialEnsure: suppressInitialEnsure,
            ensureDelay: 0.03
        )
        scheduleMainEditorLineSpacingApplyBurst(
            for: newID,
            skipDelayedInnerScrollNormalization: isBoundaryNavigation,
            immediateOnly: isBoundaryNavigation
        )
        if !isBoundaryNavigation {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                guard !showFocusMode else { return }
                guard editingCardID == newID else { return }
                if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
                    normalizeMainEditorTextViewOffsetIfNeeded(textView, reason: "edit-change")
                }
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
        if isIndexBoardActive { return }
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
        let requestedCard = resolvedSplitPaneRequestedCard(from: notification)
        let forceMainWorkspace = requestedSplitPaneForceMainWorkspace(from: notification)
        let beginEditing = requestedSplitPaneBeginEditing(from: notification)

        if forceMainWorkspace {
            if isIndexBoardActive {
                teardownIndexBoardIfNeeded(restoreEntryState: false)
            }
            if showFocusMode {
                toggleFocusMode()
            }
        }

        if let requestedCard {
            if beginEditing {
                beginCardEditing(requestedCard)
            } else {
                finishEditing(reason: .transition)
                selectedCardIDs = [requestedCard.id]
                keyboardRangeSelectionAnchorCardID = requestedCard.id
                changeActiveCard(
                    to: requestedCard,
                    shouldFocusMain: false,
                    deferToMainAsync: false,
                    force: true
                )
                scheduleMainCanvasRestoreRequest(
                    targetCardID: requestedCard.id,
                    forceSemantic: true
                )
                isMainViewFocused = true
            }
        } else if activeCardID == nil, let first = scenario.rootCards.first {
            changeActiveCard(to: first)
        }
        synchronizeActiveRelationState(for: activeCardID)
        isMainViewFocused = true
        syncScenarioTimestampSuppressionIfNeeded()
    }

    // MARK: - Layout

    var showsBottomHistoryUIInCurrentPane: Bool {
        showHistoryBar && activeBasePaneMode != .focus
    }

    var showsWorkspaceTopToolbarInCurrentPane: Bool {
        showWorkspaceTopToolbar && activeBasePaneMode == .main
    }

    @ViewBuilder
    func workspaceLayout(for geometry: GeometryProxy) -> some View {
        let timelinePanelVisible = (showTimeline || showAIChat) && !showHistoryBar && activeBasePaneMode != .focus
        let availableWidth = geometry.size.width - (timelinePanelVisible ? timelineWidth : 0)
        let indexBoardTopSafeAreaInset = max(0, geometry.safeAreaInsets.top)

        if showsBottomHistoryUIInCurrentPane {
            ZStack(alignment: .topTrailing) {
                primaryWorkspaceColumn(
                    size: geometry.size,
                    availableWidth: geometry.size.width,
                    indexBoardTopSafeAreaInset: indexBoardTopSafeAreaInset
                )
                historyOverlayHost(containerHeight: geometry.size.height)
                    .transition(.move(edge: .trailing))
            }
        } else {
            HStack(spacing: 0) {
                primaryWorkspaceColumn(
                    size: geometry.size,
                    availableWidth: availableWidth,
                    indexBoardTopSafeAreaInset: indexBoardTopSafeAreaInset
                )
                if activeBasePaneMode != .focus {
                    trailingWorkspacePanelHost
                }
            }
        }
    }

    @ViewBuilder
    func primaryWorkspaceColumn(
        size: CGSize,
        availableWidth: CGFloat,
        indexBoardTopSafeAreaInset: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            ZStack {
                mainCanvasWithOptionalZoom(size: size, availableWidth: availableWidth)
                    .opacity((showFocusMode || isIndexBoardActive) ? 0 : 1)
                    .allowsHitTesting(!showFocusMode && !isIndexBoardActive)
                    .accessibilityHidden(showFocusMode || isIndexBoardActive)
                    .zIndex(0)

                if activeBasePaneMode == .indexBoard {
                    indexBoardCanvas(
                        size: CGSize(
                            width: availableWidth,
                            height: size.height + indexBoardTopSafeAreaInset
                        )
                    )
                    .offset(y: -indexBoardTopSafeAreaInset)
                    .zIndex(2)
                }

                if showsWorkspaceTopToolbarInCurrentPane {
                    workspaceTopToolbarHost
                        .zIndex(5)
                }

                if activeBasePaneMode == .focus {
                    focusModeCanvas(size: size)
                        .ignoresSafeArea(.container, edges: .top)
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsBottomHistoryUIInCurrentPane {
                bottomHistoryBarHost
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
        let layoutAvailableWidth = max(1, availableWidth / scale)
        let layoutSize = CGSize(
            width: max(1, size.width / scale),
            height: max(1, size.height / scale)
        )
        if abs(scale - 1.0) < 0.001 {
            mainCanvas(size: size, availableWidth: availableWidth)
        } else {
            mainCanvas(size: layoutSize, availableWidth: layoutAvailableWidth)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(
                    width: layoutAvailableWidth,
                    height: layoutSize.height,
                    alignment: .topLeading
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        }
    }

    @ViewBuilder
    var workspaceTopToolbarHost: some View {
        WorkspaceToolbarHost(
            renderState: workspaceToolbarRenderState(),
            content: {
                AnyView(workspaceTopToolbarContent)
            }
        )
        .equatable()
    }

    var showsSplitPaneAutoLinkToggle: Bool {
        splitModeEnabled && splitPaneID == 2
    }

    var splitPaneAutoLinkToolbarButton: some View {
        Button {
            splitPaneAutoLinkEditsEnabled.toggle()
        } label: {
            Image(systemName: "link")
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .foregroundColor(splitPaneAutoLinkEditsEnabled ? .orange : .gray)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .help(
            splitPaneAutoLinkEditsEnabled
            ? "오른쪽 편집을 왼쪽 카드의 연결 카드로 자동 기록합니다."
            : "왼쪽과 오른쪽 편집을 독립적으로 유지합니다."
        )
    }

    var workspaceTopToolbarContent: some View {
        VStack {
            HStack(spacing: 12) {
                Spacer()
                if showsSplitPaneAutoLinkToggle {
                    splitPaneAutoLinkToolbarButton
                }
                focusModeToolbarButton
                indexBoardToolbarButton
                checkpointToolbarButton
                historyToolbarButton
                aiChatToolbarButton
                timelineToolbarButton
            }
            Spacer()
        }
        .ignoresSafeArea(.container, edges: [.top, .leading, .trailing, .bottom])
    }

    var focusModeToolbarButton: some View {
        Button {
            toggleFocusMode()
        } label: {
            Image(systemName: "scope")
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .help("포커스 모드 열기")
    }

    var indexBoardToolbarButton: some View {
        Button {
            handleOpenIndexBoardRequestNotification()
        } label: {
            Image(systemName: "square.grid.3x3.fill")
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .help("보드 뷰 열기")
    }

    @ViewBuilder
    var bottomHistoryBarHost: some View {
        BottomHistoryBarHost(
            renderState: bottomHistoryBarRenderState(),
            content: {
                AnyView(bottomHistoryBar)
            }
        )
        .equatable()
    }

    var checkpointToolbarButton: some View {
        Button {
            presentNamedCheckpointDialog()
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
            toggleHistoryPanel()
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
            toggleTimeline()
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

    func presentNamedCheckpointDialog() {
        newCheckpointName = ""
        newCheckpointNote = ""
        showCheckpointDialog = true
    }

    func toggleHistoryPanel() {
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
    var trailingWorkspacePanelHost: some View {
        let renderState = trailingWorkspacePanelRenderState()
        if renderState.mode != .hidden {
            TrailingWorkspacePanelHost(
                renderState: renderState,
                panelWidth: timelineWidth,
                backgroundColor: resolvedTimelineBackgroundColor(),
                dividerColor: appearance == "light" ? Color.black.opacity(0.1) : Color.white.opacity(0.15),
                content: {
                    AnyView(trailingWorkspacePanelContent)
                }
            )
            .equatable()
        }
    }

    @ViewBuilder
    var trailingWorkspacePanelContent: some View {
        switch trailingWorkspacePanelMode() {
        case .timeline:
            timelineView
        case .aiChat:
            aiChatView
        case .hidden:
            EmptyView()
        }
    }

    @ViewBuilder
    func historyOverlayHost(containerHeight: CGFloat) -> some View {
        let bottomInset = historyBarMeasuredHeight > 0 ? historyBarMeasuredHeight : historyOverlayBottomInset
        HistoryOverlayHost(
            renderState: historyOverlayRenderState(containerHeight: containerHeight, bottomInset: bottomInset),
            panelWidth: timelineWidth,
            containerHeight: containerHeight,
            bottomInset: bottomInset,
            backgroundColor: resolvedTimelineBackgroundColor(),
            dividerColor: appearance == "light" ? Color.black.opacity(0.1) : Color.white.opacity(0.15),
            content: {
                AnyView(namedSnapshotManagerView)
            }
        )
        .equatable()
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

    var fountainClipboardPasteDialogOverlay: some View {
        let sceneCount = pendingFountainClipboardPastePreview?.importPayload.sceneCards.count ?? 0

        return ZStack {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .onTapGesture {
                    cancelFountainClipboardPasteDialog()
                }

            VStack(alignment: .leading, spacing: 12) {
                Text("붙여넣기 방식")
                    .font(.system(size: 16, weight: .semibold))
                Text(sceneCount >= 2 ? "씬 헤딩 \(sceneCount)개를 감지했습니다." : "붙여넣기 방식을 선택하세요.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    fountainClipboardPasteDialogOptionRow(.plainText)
                    fountainClipboardPasteDialogOptionRow(.sceneCards)
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
        .zIndex(1001)
        .allowsHitTesting(true)
    }

    @ViewBuilder
    func fountainClipboardPasteDialogOptionRow(_ option: StructuredTextPasteOption) -> some View {
        let isSelected = showFountainClipboardPasteDialog && fountainClipboardPasteSelection == option

        Button {
            fountainClipboardPasteSelection = option
            applyFountainClipboardPasteSelection(option)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: fountainClipboardPasteDialogOptionIcon(option))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(fountainClipboardPasteDialogOptionTitle(option))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary)
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
    }

    func fountainClipboardPasteDialogOptionTitle(_ option: StructuredTextPasteOption) -> String {
        switch option {
        case .plainText:
            return "그냥 붙여넣기"
        case .sceneCards:
            return "씬별 카드로 나누기"
        }
    }

    func fountainClipboardPasteDialogOptionIcon(_ option: StructuredTextPasteOption) -> String {
        switch option {
        case .plainText:
            return "doc.on.clipboard"
        case .sceneCards:
            return "rectangle.split.3x1"
        }
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
        MainCanvasHost(
            renderState: mainCanvasRenderState(size: size, availableWidth: availableWidth),
            viewState: mainCanvasViewState,
            scrollCoordinator: mainCanvasScrollCoordinator,
            backgroundColor: resolvedBackgroundColor(),
            onBackgroundTap: {
                deselectAll()
                isMainViewFocused = true
            },
            onHistoryIndexChange: { proxy in
                guard !showFocusMode, !isIndexBoardActive else { return }
                handleMainCanvasHistoryIndexChange(hProxy: proxy)
            },
            onActiveCardChange: { newID, proxy, width in
                guard !showFocusMode, !isIndexBoardActive else { return }
                handleMainCanvasActiveCardChange(newID, hProxy: proxy, availableWidth: width)
            },
            onMotionIntent: { proxy, width in
                guard !showFocusMode, !isIndexBoardActive else { return }
                handleMainCanvasMotionIntent(hProxy: proxy, availableWidth: width)
            },
            onMotionSessionClose: { proxy, width in
                guard !showFocusMode, !isIndexBoardActive else { return }
                handleMainCanvasMotionSessionClose(hProxy: proxy, availableWidth: width)
            },
            onNavigationSettle: { proxy, width in
                guard !showFocusMode, !isIndexBoardActive else { return }
                handleMainCanvasNavigationSettle(hProxy: proxy, availableWidth: width)
            },
            onRestoreRequest: { proxy, width in
                guard !showFocusMode, !isIndexBoardActive else { return }
                handleMainCanvasRestoreRequest(hProxy: proxy, availableWidth: width)
            },
            onAppear: { proxy, width in
                guard !showFocusMode, !isIndexBoardActive else { return }
                handleMainCanvasAppear(hProxy: proxy, availableWidth: width)
            },
            scrollableContent: {
                AnyView(mainCanvasScrollableContent(size: size, availableWidth: availableWidth))
            }
        )
        .equatable()
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
        let baseLevelsData = displayedLevelsData()
        let levelsData = displayedMainLevelsData(from: baseLevelsData)
        let visualMaxLevelCount = displayedMaxLevelCount(for: baseLevelsData)
        ForEach(Array(levelsData.enumerated()), id: \.offset) { index, data in
            if index <= 1 || !data.cards.isEmpty {
                column(for: data.cards, level: index, parent: data.parent, screenHeight: screenHeight)
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
        return scenario.filteredCards(atLevel: levelIndex, category: category)
    }

    func mainCanvasRenderState(size: CGSize, availableWidth: CGFloat) -> MainCanvasRenderState {
        MainCanvasRenderState(
            size: size,
            availableWidth: availableWidth,
            historyIndex: Int(historyIndex),
            acceptsKeyboardInput: acceptsKeyboardInput,
            isPreviewingHistory: isPreviewingHistory,
            backgroundSignature: "\(appearance)|\(backgroundColorHex)|\(darkBackgroundColorHex)",
            contentFingerprint: mainCanvasContentFingerprint(),
            interactionFingerprint: mainCanvasInteractionFingerprint()
        )
    }

    func mainCanvasContentFingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(scenarioCardsVersion)
        hasher.combine(scenarioLinkedCardsVersion)
        hasher.combine(isPreviewingHistory)
        hasher.combine(aiCandidateState.cardIDs.count)
        for id in aiCandidateState.cardIDs {
            hasher.combine(id)
        }
        hasher.combine(aiChildSummaryLoadingCardIDs.count)
        for id in aiChildSummaryLoadingCardIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            hasher.combine(id)
        }
        hasher.combine(aiIsGenerating)
        hasher.combine(dictationIsRecording)
        hasher.combine(dictationIsProcessing)
        hasher.combine(isInactiveSplitPane)
        if isInactiveSplitPane {
            hasher.combine(inactivePaneSnapshotState.maxLevelCount)
            for level in inactivePaneSnapshotState.levelsData {
                hasher.combine(level.parent?.id)
                hasher.combine(level.cards.count)
                for card in level.cards {
                    hasher.combine(card.id)
                }
            }
        }
        if isPreviewingHistory {
            hasher.combine(previewDiffs.count)
            for diff in previewDiffs {
                hasher.combine(diff.id)
                switch diff.status {
                case .added: hasher.combine(1)
                case .deleted: hasher.combine(2)
                case .modified: hasher.combine(3)
                case .none: hasher.combine(4)
                }
            }
            hasher.combine(historyPreviewSelectedCardIDs.count)
            for id in historyPreviewSelectedCardIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                hasher.combine(id)
            }
        }
        return hasher.finalize()
    }

    func trailingWorkspacePanelMode() -> WorkspaceTrailingPanelMode {
        if showTimeline {
            return .timeline
        }
        if showAIChat {
            return .aiChat
        }
        return .hidden
    }

    func trailingWorkspacePanelRenderState() -> TrailingWorkspacePanelRenderState {
        TrailingWorkspacePanelRenderState(
            mode: trailingWorkspacePanelMode(),
            appearanceSignature: appearance,
            contentFingerprint: trailingWorkspacePanelContentFingerprint()
        )
    }

    func trailingWorkspacePanelContentFingerprint() -> Int {
        var hasher = Hasher()
        let mode = trailingWorkspacePanelMode()
        hasher.combine(mode.rawValue)
        hasher.combine(appearance)

        switch mode {
        case .timeline:
            hasher.combine(searchText)
            hasher.combine(linkedCardsFilterEnabled)
            hasher.combine(linkedCardAnchorID)
            hasher.combine(activeCardID)
            hasher.combine(editingCardID)
            hasher.combine(selectedCardIDs.count)
            for id in selectedCardIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                hasher.combine(id)
            }
            hasher.combine(scenarioCardsVersion)
            hasher.combine(scenarioLinkedCardsVersion)
            hasher.combine(aiCandidateState.cardIDs.count)
            for id in aiCandidateState.cardIDs {
                hasher.combine(id)
            }
            hasher.combine(aiChildSummaryLoadingCardIDs.count)
            for id in aiChildSummaryLoadingCardIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                hasher.combine(id)
            }
            hasher.combine(aiIsGenerating)
        case .aiChat:
            hasher.combine(aiChatThreads.count)
            for thread in aiChatThreads {
                hasher.combine(thread.id)
                hasher.combine(thread.title)
                hasher.combine(thread.mode.rawValue)
                hasher.combine(thread.scope.type.rawValue)
                hasher.combine(thread.scope.includeChildrenDepth)
                hasher.combine(thread.scope.cardIDs.count)
                for cardID in thread.scope.cardIDs {
                    hasher.combine(cardID)
                }
                hasher.combine(thread.messages.count)
                hasher.combine(thread.rollingSummary)
                hasher.combine(thread.decisionLog.count)
                hasher.combine(thread.unresolvedQuestions.count)
                hasher.combine(thread.updatedAt.timeIntervalSince1970.bitPattern)
            }
            hasher.combine(activeAIChatThreadID)
            hasher.combine(aiChatInput)
            hasher.combine(isAIChatLoading)
            hasher.combine(aiChatActiveRequestID)
            hasher.combine(aiStatusMessage)
            hasher.combine(aiStatusIsError)
            hasher.combine(activeCardID)
            hasher.combine(selectedCardIDs.count)
            hasher.combine(scenarioCardsVersion)
        case .hidden:
            break
        }

        return hasher.finalize()
    }

    func historyOverlayRenderState(containerHeight: CGFloat, bottomInset: CGFloat) -> HistoryOverlayRenderState {
        HistoryOverlayRenderState(
            appearanceSignature: appearance,
            contentFingerprint: historyOverlayContentFingerprint(),
            containerHeightBucket: Int(containerHeight.rounded()),
            bottomInsetBucket: Int(bottomInset.rounded())
        )
    }

    func workspaceToolbarRenderState() -> WorkspaceToolbarRenderState {
        WorkspaceToolbarRenderState(
            appearanceSignature: appearance,
            isHistoryVisible: showHistoryBar,
            isTimelineVisible: showTimeline,
            isAIChatVisible: showAIChat,
            contentFingerprint: workspaceToolbarContentFingerprint()
        )
    }

    func workspaceToolbarContentFingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(appearance)
        hasher.combine(showHistoryBar)
        hasher.combine(showTimeline)
        hasher.combine(showAIChat)
        hasher.combine(showCheckpointDialog)
        hasher.combine(isPreviewingHistory)
        hasher.combine(scenarioHistoryVersion)
        hasher.combine(showsSplitPaneAutoLinkToggle)
        hasher.combine(splitPaneAutoLinkEditsEnabled)
        return hasher.finalize()
    }

    func bottomHistoryBarRenderState() -> BottomHistoryBarRenderState {
        BottomHistoryBarRenderState(
            appearanceSignature: appearance,
            contentFingerprint: bottomHistoryBarContentFingerprint()
        )
    }

    func bottomHistoryBarContentFingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(appearance)
        hasher.combine(scenarioHistoryVersion)
        hasher.combine(Int(historyIndex))
        hasher.combine(isPreviewingHistory)
        hasher.combine(editingSnapshotID)
        hasher.combine(editedSnapshotName)
        hasher.combine(showHistoryBar)
        hasher.combine(historyBarMeasuredHeight.rounded(.toNearestOrAwayFromZero))
        return hasher.finalize()
    }

    func historyOverlayContentFingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(appearance)
        hasher.combine(scenarioHistoryVersion)
        hasher.combine(scenarioCardsVersion)
        hasher.combine(Int(historyIndex))
        hasher.combine(historySelectedNamedSnapshotNoteCardID)
        hasher.combine(isNamedSnapshotNoteEditing)
        hasher.combine(isNamedSnapshotNoteEditorFocused)
        hasher.combine(snapshotNoteSearchText)
        hasher.combine(editingSnapshotID)
        hasher.combine(editedSnapshotName)
        return hasher.finalize()
    }

    func handleMainCanvasInnerTap() {
        if isPreviewingHistory {
            historyPreviewSelectedCardIDs = []
        } else {
            finishEditing(reason: .transition)
            selectedCardIDs = []
            isMainViewFocused = true
        }
    }

    func handleMainCanvasHistoryIndexChange(hProxy: ScrollViewProxy) {
        guard !showFocusMode else { return }
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
        if showFocusMode {
            indexBoardRestoreTrace("main_canvas_auto_scroll_skip", "reason=focusMode target=\(debugRestoreUUID(id))")
            return
        }
        if pendingMainEditingSiblingNavigationTargetID == id {
            indexBoardRestoreTrace("main_canvas_auto_scroll_skip", "reason=pendingSibling target=\(debugRestoreUUID(id))")
            return
        }
        let suppressEditingAutoScroll =
            shouldSuppressGeneralMainCanvasScrollDuringEditing(targetCardID: id) &&
            pendingMainEditingBoundaryNavigationTargetID != id
        if suppressEditingAutoScroll {
            indexBoardRestoreTrace(
                "main_canvas_auto_scroll_skip",
                "reason=editingIsolation target=\(debugRestoreUUID(id)) isolationTarget=\(debugRestoreUUID(mainEditingScrollIsolationTargetCardID)) " +
                "until=\(String(format: "%.3f", mainEditingScrollIsolationUntil.timeIntervalSince1970))"
            )
            return
        }
        let clickFocusedTarget = pendingMainClickHorizontalFocusTargetID == id
        if suppressHorizontalAutoScroll && !clickFocusedTarget {
            indexBoardRestoreTrace(
                "main_canvas_auto_scroll_skip",
                "reason=suppressHorizontal target=\(debugRestoreUUID(id)) clickFocused=\(clickFocusedTarget)"
            )
            return
        }
        if suppressAutoScrollOnce {
            suppressAutoScrollOnce = false
            if !clickFocusedTarget {
                indexBoardRestoreTrace(
                    "main_canvas_auto_scroll_skip",
                    "reason=suppressOnce target=\(debugRestoreUUID(id)) clickFocused=\(clickFocusedTarget)"
                )
                return
            }
        }
        if mainCanvasScrollCoordinator.hasActiveMotionSession() {
            indexBoardRestoreTrace(
                "main_canvas_auto_scroll_skip",
                "reason=motionSession target=\(debugRestoreUUID(id)) clickFocused=\(clickFocusedTarget)"
            )
            return
        }
        let animated =
            focusNavigationAnimationEnabled &&
            (pendingMainHorizontalScrollAnimation ?? !shouldSuppressMainArrowRepeatAnimation())
        pendingMainHorizontalScrollAnimation = nil
        if clickFocusedTarget {
            indexBoardRestoreTrace(
                "main_canvas_auto_scroll_execute",
                "target=\(debugRestoreUUID(id)) trigger=clickFocused animated=\(animated) availableWidth=\(String(format: "%.2f", availableWidth))"
            )
            scrollToColumnIfNeeded(
                targetCardID: id,
                proxy: hProxy,
                availableWidth: availableWidth,
                force: mainCanvasHorizontalScrollMode == .oneStep,
                animated: animated
            )
            if pendingMainClickHorizontalFocusTargetID == id {
                pendingMainClickHorizontalFocusTargetID = nil
            }
            return
        }
        if !isPreviewingHistory {
            indexBoardRestoreTrace(
                "main_canvas_auto_scroll_execute",
                "target=\(debugRestoreUUID(id)) trigger=activeCard animated=\(animated) availableWidth=\(String(format: "%.2f", availableWidth)) " +
                "clickFocused=\(clickFocusedTarget)"
            )
            scrollToColumnIfNeeded(
                targetCardID: id,
                proxy: hProxy,
                availableWidth: availableWidth,
                force: clickFocusedTarget && mainCanvasHorizontalScrollMode == .oneStep,
                animated: animated
            )
        }
    }

    private var mainCanvasHorizontalMotionViewportKey: String {
        "__main_canvas_horizontal__"
    }

    func handleMainCanvasMotionIntent(hProxy: ScrollViewProxy, availableWidth: CGFloat) {
        guard acceptsKeyboardInput else { return }
        guard let intent = mainCanvasScrollCoordinator.consumeLatestIntent(for: mainCanvasHorizontalMotionViewportKey) else {
            return
        }
        switch intent.kind {
        case .focusChange, .settleRecovery:
            break
        case .childListChange, .columnAppear, .bottomReveal:
            return
        }
        guard let participantHandle = mainCanvasScrollCoordinator.claimMotionParticipant(
            for: mainCanvasHorizontalMotionViewportKey,
            axis: .horizontal,
            intent: intent
        ) else { return }
        if intent.kind == .settleRecovery {
            mainCanvasScrollCoordinator.closeJoinWindowIfCurrentSessionMatches(participantHandle)
        }
        let animated = resolvedMainCanvasHorizontalMotionAnimated(for: intent)
        scheduleMainCanvasHorizontalMotion(
            intent: intent,
            hProxy: hProxy,
            availableWidth: availableWidth,
            animated: animated,
            attempt: 0,
            participantHandle: participantHandle
        )
    }

    private func resolvedMainCanvasHorizontalMotionAnimated(
        for intent: MainCanvasScrollCoordinator.NavigationIntent
    ) -> Bool {
        defer { pendingMainHorizontalScrollAnimation = nil }
        guard intent.kind == .focusChange else { return false }
        return pendingMainHorizontalScrollAnimation ?? intent.animated
    }

    private func scheduleMainCanvasHorizontalMotion(
        intent: MainCanvasScrollCoordinator.NavigationIntent,
        hProxy: ScrollViewProxy,
        availableWidth: CGFloat,
        animated: Bool,
        attempt: Int,
        participantHandle: MainCanvasScrollCoordinator.MotionParticipantHandle
    ) {
        guard mainCanvasScrollCoordinator.isMotionParticipantCurrent(participantHandle) else { return }
        let aligned: Bool
        if intent.trigger == "reorderCommit" {
            aligned = applyMainCanvasHorizontalReorderPreserve(availableWidth: availableWidth)
        } else {
            aligned = applyMainCanvasHorizontalFocusAlignment(
                targetCardID: intent.targetCardID ?? intent.expectedActiveCardID,
                hProxy: hProxy,
                availableWidth: availableWidth,
                forceAlignment: intent.trigger == "clickFocus",
                animated: attempt == 0 ? animated : false
            )
        }
        if aligned {
            mainCanvasScrollCoordinator.clearMotionTask(kind: .verification, handle: participantHandle)
            mainCanvasScrollCoordinator.updateMotionParticipantState(.aligned, handle: participantHandle)
            return
        }

        mainCanvasScrollCoordinator.updateMotionParticipantState(.moving, handle: participantHandle)
        let nextAttempt = attempt + 1
        let delay = mainCanvasScrollCoordinator.motionPolicy.verificationDelay(
            animated: animated,
            attempt: attempt
        )
        let verificationWorkItem = DispatchWorkItem {
            mainCanvasScrollCoordinator.clearMotionTask(kind: .verification, handle: participantHandle)
            guard !showFocusMode else { return }
            guard acceptsKeyboardInput else { return }
            if nextAttempt >= 4 {
                mainCanvasScrollCoordinator.updateMotionParticipantState(.timedOut, handle: participantHandle)
                return
            }
            scheduleMainCanvasHorizontalMotion(
                intent: intent,
                hProxy: hProxy,
                availableWidth: availableWidth,
                animated: false,
                attempt: nextAttempt,
                participantHandle: participantHandle
            )
        }
        mainCanvasScrollCoordinator.replaceMotionTask(
            verificationWorkItem,
            kind: .verification,
            handle: participantHandle
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: verificationWorkItem)
    }

    private func applyMainCanvasHorizontalFocusAlignment(
        targetCardID: UUID?,
        hProxy: ScrollViewProxy,
        availableWidth: CGFloat,
        forceAlignment: Bool,
        animated: Bool
    ) -> Bool {
        guard let targetCardID else { return true }
        guard let _ = displayedMainCardLocationByID(targetCardID) else { return false }
        scrollToColumnIfNeeded(
            targetCardID: targetCardID,
            proxy: hProxy,
            availableWidth: availableWidth,
            force: forceAlignment && mainCanvasHorizontalScrollMode == .oneStep,
            animated: animated
        )
        if pendingMainClickHorizontalFocusTargetID == targetCardID {
            pendingMainClickHorizontalFocusTargetID = nil
        }
        return isMainCanvasHorizontallyAligned(
            targetCardID: targetCardID,
            availableWidth: availableWidth
        )
    }

    private func applyMainCanvasHorizontalReorderPreserve(availableWidth _: CGFloat) -> Bool {
        guard let targetOffsetX = pendingMainReorderHorizontalOffsetX else { return true }
        guard let scrollView = mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalScrollView() else { return false }

        let visibleRect = scrollView.documentVisibleRect
        let documentWidth = scrollView.documentView?.bounds.width ?? 0
        let maxX = max(0, documentWidth - visibleRect.width)
        let resolvedTargetX = CaretScrollCoordinator.resolvedHorizontalTargetX(
            visibleRect: visibleRect,
            targetX: targetOffsetX,
            minX: 0,
            maxX: maxX,
            snapToPixel: true
        )
        _ = CaretScrollCoordinator.applyHorizontalScrollIfNeeded(
            scrollView: scrollView,
            visibleRect: visibleRect,
            targetX: targetOffsetX,
            minX: 0,
            maxX: maxX,
            deadZone: 0.5,
            snapToPixel: true
        )
        let currentX = scrollView.contentView.bounds.origin.x
        if abs(resolvedTargetX - currentX) <= 0.5 {
            pendingMainReorderHorizontalOffsetX = nil
            return true
        }
        let aligned =
            abs(resolvedTargetX - (mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalOffset() ?? currentX)) <= 0.5
        if aligned {
            pendingMainReorderHorizontalOffsetX = nil
        }
        return aligned
    }

    func isMainCanvasHorizontallyAligned(
        targetCardID: UUID,
        availableWidth: CGFloat
    ) -> Bool {
        guard let targetLevel = displayedMainCardLocationByID(targetCardID)?.level else { return false }
        guard let scrollView = mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalScrollView() else { return false }

        let visibleRect = scrollView.documentVisibleRect
        let documentWidth = scrollView.documentView?.bounds.width ?? 0
        let maxX = max(0, documentWidth - visibleRect.width)
        let targetX = resolvedMainCanvasHorizontalTargetX(
            level: targetLevel,
            availableWidth: max(1, availableWidth),
            visibleWidth: visibleRect.width
        )
        let resolvedTargetX = CaretScrollCoordinator.resolvedHorizontalTargetX(
            visibleRect: visibleRect,
            targetX: targetX,
            minX: 0,
            maxX: maxX,
            snapToPixel: true
        )
        let currentX = scrollView.contentView.bounds.origin.x
        return abs(resolvedTargetX - currentX) <= 0.5
    }

    func handleMainCanvasMotionSessionClose(hProxy: ScrollViewProxy, availableWidth: CGFloat) {
        guard !showFocusMode else { return }
        pendingMainClickHorizontalFocusTargetID = nil
        pendingMainReorderHorizontalOffsetX = nil
        if pendingMainCanvasRestoreRequest != nil {
            restoreMainCanvasPositionIfNeeded(proxy: hProxy, availableWidth: availableWidth)
        }
        replayDeferredMainColumnViewportRestoreIfNeeded()
    }

    func handleMainCanvasRestoreRequest(hProxy: ScrollViewProxy, availableWidth: CGFloat) {
        guard !showFocusMode else { return }
        guard acceptsKeyboardInput else { return }
        restoreMainCanvasPositionIfNeeded(proxy: hProxy, availableWidth: availableWidth)
    }

    func handleMainCanvasNavigationSettle(hProxy: ScrollViewProxy, availableWidth: CGFloat) {
        guard !showFocusMode else { return }
        guard acceptsKeyboardInput else { return }
        guard !isPreviewingHistory else { return }
        guard let targetID = activeCardID, findCard(by: targetID) != nil else { return }
        guard !mainCanvasScrollCoordinator.hasActiveMotionSession() else { return }
        if shouldSuppressGeneralMainCanvasScrollDuringEditing(targetCardID: targetID) {
            indexBoardRestoreTrace(
                "main_canvas_navigation_settle_skip",
                "reason=editingIsolation target=\(debugRestoreUUID(targetID)) isolationTarget=\(debugRestoreUUID(mainEditingScrollIsolationTargetCardID)) " +
                "until=\(String(format: "%.3f", mainEditingScrollIsolationUntil.timeIntervalSince1970))"
            )
            return
        }
        scrollToColumnIfNeeded(
            targetCardID: targetID,
            proxy: hProxy,
            availableWidth: availableWidth,
            force: true,
            animated: false
        )
    }

    func handleMainCanvasAppear(hProxy: ScrollViewProxy, availableWidth: CGFloat) {
        guard !showFocusMode else { return }
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

    private func syncSplitPaneActiveCardState(_ cardID: UUID?) {
        guard splitModeEnabled else { return }
        scenario.setSplitPaneActiveCard(cardID, for: splitPaneID)
    }

    private struct StartupFocusSnapshot {
        let card: SceneCard
        let caretLocation: Int?
        let restoresEditing: Bool
        let restoresFocusMode: Bool
    }

    private func startupFocusSnapshot() -> StartupFocusSnapshot? {
        guard scenario.id.uuidString == lastFocusedScenarioID,
              let restoredID = UUID(uuidString: lastFocusedCardID),
              let restored = findCard(by: restoredID),
              !restored.isArchived else {
            return nil
        }

        let length = (restored.content as NSString).length
        let caretLocation =
            lastFocusedCaretLocation >= 0
            ? min(max(0, lastFocusedCaretLocation), length)
            : nil

        return StartupFocusSnapshot(
            card: restored,
            caretLocation: caretLocation,
            restoresEditing: lastFocusedWasEditing,
            restoresFocusMode: lastFocusedWasFocusMode
        )
    }

    private func restoreStartupFocusIfNeeded() {
        guard !didRestoreStartupFocusState else { return }
        didRestoreStartupFocusState = true
        guard acceptsKeyboardInput else { return }
        guard let snapshot = startupFocusSnapshot() else { return }

        if let caretLocation = snapshot.caretLocation {
            mainCaretLocationByCardID[snapshot.card.id] = caretLocation
        }

        guard snapshot.restoresEditing || snapshot.restoresFocusMode else { return }

        let targetID = snapshot.card.id
        DispatchQueue.main.async {
            guard acceptsKeyboardInput else { return }
            guard let target = findCard(by: targetID), !target.isArchived else { return }
            if let caretLocation = snapshot.caretLocation {
                mainCaretLocationByCardID[target.id] = caretLocation
            }
            if snapshot.restoresFocusMode {
                guard !showFocusMode else { return }
                if activeCardID != target.id {
                    changeActiveCard(to: target)
                }
                toggleFocusMode()
                return
            }
            guard !showFocusMode else { return }
            finishEditing(reason: .transition)
            selectedCardIDs = [target.id]
            keyboardRangeSelectionAnchorCardID = target.id
            changeActiveCard(
                to: target,
                shouldFocusMain: false,
                deferToMainAsync: false,
                force: true
            )
            scheduleMainCanvasRestoreRequest(
                targetCardID: target.id,
                forceSemantic: true
            )
            isMainViewFocused = true
        }
    }

    private func restoredStartupViewportOffsets() -> [String: CGFloat] {
        guard scenario.id.uuidString == lastFocusedViewportScenarioID else { return [:] }
        guard let data = lastFocusedViewportOffsetsJSON.data(using: .utf8) else { return [:] }
        guard let decoded = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
        return decoded.reduce(into: [String: CGFloat]()) { partialResult, entry in
            let offset = CGFloat(entry.value)
            guard offset.isFinite, offset >= 0 else { return }
            partialResult[entry.key] = offset
        }
    }

    private func mainCanvasHorizontalViewportPersistenceKey() -> String {
        let paneKey = splitModeEnabled ? splitPaneID : 0
        return "scenario:\(scenario.id.uuidString)|pane:\(paneKey)"
    }

    private func restoredMainCanvasHorizontalViewportOffsets() -> [String: CGFloat] {
        guard let data = lastFocusedMainCanvasHorizontalOffsetsJSON.data(using: .utf8) else { return [:] }
        guard let decoded = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
        return decoded.reduce(into: [String: CGFloat]()) { partialResult, entry in
            let offset = CGFloat(entry.value)
            guard offset.isFinite, offset >= 0 else { return }
            partialResult[entry.key] = offset
        }
    }

    @discardableResult
    private func restoreStartupMainCanvasHorizontalViewportIfNeeded() -> Bool {
        let persistenceKey = mainCanvasHorizontalViewportPersistenceKey()
        guard let storedOffsetX = restoredMainCanvasHorizontalViewportOffsets()[persistenceKey] else { return false }
        restoreMainCanvasHorizontalViewport(to: storedOffsetX)
        return true
    }

    private func restoreStartupViewportIfNeeded() {
        guard !didRestoreStartupViewportState else { return }
        didRestoreStartupViewportState = true

        let restoredOffsets = restoredStartupViewportOffsets()
        guard !restoredOffsets.isEmpty else { return }

        mainColumnViewportOffsetByKey = restoredOffsets
        scheduleMainColumnViewportRestore(restoredOffsets)
    }

    func applyStoredMainColumnViewportOffsets(_ offsets: [String: CGFloat]) {
        guard !offsets.isEmpty else { return }
        if mainCanvasScrollCoordinator.hasActiveMotionSession() {
            pendingMainDeferredColumnViewportRestoreOffsets = offsets
            indexBoardRestoreTrace(
                "main_canvas_apply_column_viewport_offsets_deferred",
                "count=\(offsets.count)"
            )
            return
        }
        indexBoardRestoreTrace(
            "main_canvas_apply_column_viewport_offsets_begin",
            "count=\(offsets.count) offsets=\(debugRestoreViewportOffsets(offsets)) active=\(debugRestoreUUID(activeCardID))"
        )

        var didScheduleCaptureSuspension = false
        for (viewportKey, storedOffsetY) in offsets.sorted(by: { $0.key < $1.key }) {
            guard storedOffsetY > 1 else { continue }
            guard let scrollView = mainCanvasScrollCoordinator.scrollView(for: viewportKey) else { continue }

            let visible = scrollView.documentVisibleRect
            let documentHeight = scrollView.documentView?.bounds.height ?? 0
            let maxY = max(0, documentHeight - visible.height)
            if !didScheduleCaptureSuspension {
                suspendMainColumnViewportCapture(for: 0.22)
                didScheduleCaptureSuspension = true
            }
            _ = CaretScrollCoordinator.applyVerticalScrollIfNeeded(
                scrollView: scrollView,
                visibleRect: visible,
                targetY: storedOffsetY,
                minY: 0,
                maxY: maxY,
                deadZone: 0.5,
                snapToPixel: true
            )
            indexBoardRestoreTrace(
                "main_canvas_apply_column_viewport_offsets_applied",
                "viewportKey=\(viewportKey) targetY=\(String(format: "%.2f", storedOffsetY)) " +
                "currentY=\(String(format: "%.2f", scrollView.contentView.bounds.origin.y)) maxY=\(String(format: "%.2f", maxY))"
            )
        }
    }

    private func requestStartupMainCanvasRestoreIfNeeded() {
        guard let targetID = activeCardID ?? startupActiveCard()?.id else { return }
        DispatchQueue.main.async {
            guard !showFocusMode else { return }
            mainCanvasViewState.scheduleRestoreRequest(targetCardID: targetID)
        }
    }

    private func startupActiveCard() -> SceneCard? {
        if let snapshot = startupFocusSnapshot() {
            return snapshot.card
        }
        if scenario.id.uuidString == lastEditedScenarioID,
           let restoredID = UUID(uuidString: lastEditedCardID),
           let restored = findCard(by: restoredID),
           !restored.isArchived {
            return restored
        }
        return scenario.rootCards.last
    }

    func persistLastFocusSnapshot(
        cardID: UUID,
        caretLocation: Int? = nil,
        isEditing: Bool,
        inFocusMode: Bool
    ) {
        guard let card = findCard(by: cardID), !card.isArchived else { return }
        let length = (card.content as NSString).length

        let resolvedCaretLocation: Int
        if let caretLocation {
            resolvedCaretLocation = min(max(0, caretLocation), length)
        } else if let savedLocation = mainCaretLocationByCardID[cardID] {
            resolvedCaretLocation = min(max(0, savedLocation), length)
        } else if lastFocusedScenarioID == scenario.id.uuidString,
                  lastFocusedCardID == cardID.uuidString,
                  lastFocusedCaretLocation >= 0 {
            resolvedCaretLocation = min(max(0, lastFocusedCaretLocation), length)
        } else {
            resolvedCaretLocation = 0
        }

        lastFocusedScenarioID = scenario.id.uuidString
        lastFocusedCardID = cardID.uuidString
        lastFocusedCaretLocation = resolvedCaretLocation
        lastFocusedWasEditing = isEditing
        lastFocusedWasFocusMode = inFocusMode
    }

    private func persistCurrentFocusSnapshotIfPossible() {
        if showFocusMode, let focusedID = focusModeEditorCardID ?? editingCardID ?? activeCardID {
            persistLastFocusSnapshot(cardID: focusedID, isEditing: true, inFocusMode: true)
            return
        }
        if let editingID = editingCardID {
            persistLastFocusSnapshot(cardID: editingID, isEditing: true, inFocusMode: false)
            return
        }
        if let activeID = activeCardID {
            persistLastFocusSnapshot(cardID: activeID, isEditing: false, inFocusMode: false)
        }
    }

    private func persistCurrentViewportSnapshotIfPossible() {
        let sanitizedOffsets = mainColumnViewportOffsetByKey.reduce(into: [String: Double]()) { partialResult, entry in
            guard entry.value.isFinite, entry.value >= 0 else { return }
            partialResult[entry.key] = Double(entry.value)
        }

        if !sanitizedOffsets.isEmpty,
           let data = try? JSONEncoder().encode(sanitizedOffsets),
           let encoded = String(data: data, encoding: .utf8) {
            lastFocusedViewportScenarioID = scenario.id.uuidString
            lastFocusedViewportOffsetsJSON = encoded
        } else {
            lastFocusedViewportScenarioID = ""
            lastFocusedViewportOffsetsJSON = ""
        }

        var horizontalOffsets = restoredMainCanvasHorizontalViewportOffsets()
        let persistenceKey = mainCanvasHorizontalViewportPersistenceKey()
        let resolvedHorizontalOffset = mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalOffset()

        if let resolvedHorizontalOffset {
            horizontalOffsets[persistenceKey] = resolvedHorizontalOffset
        }

        if let data = try? JSONEncoder().encode(horizontalOffsets.reduce(into: [String: Double]()) { partialResult, entry in
            partialResult[entry.key] = Double(entry.value)
        }),
           let encoded = String(data: data, encoding: .utf8) {
            lastFocusedMainCanvasHorizontalOffsetsJSON = encoded
        } else {
            lastFocusedMainCanvasHorizontalOffsetsJSON = ""
        }
    }

    private func persistLastEditedCard(_ cardID: UUID) {
        guard let card = findCard(by: cardID), !card.isArchived else { return }
        lastEditedScenarioID = scenario.id.uuidString
        lastEditedCardID = cardID.uuidString
    }
}
