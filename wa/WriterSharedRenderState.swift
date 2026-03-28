import SwiftUI
import AppKit
import AVFoundation
import Combine

struct CardState {
    let id: UUID
    let content: String
    let orderIndex: Int
    let createdAt: Date
    let parentID: UUID?
    let category: String?
    let isFloating: Bool
    let isArchived: Bool
    let lastSelectedChildID: UUID?
    let colorHex: String?
    let cloneGroupID: UUID?
}

struct ScenarioState {
    let cards: [CardState]
    let activeCardID: UUID?
    let activeCaretLocation: Int?
    let selectedCardIDs: [UUID]
    let changeCount: Int
    let indexBoardState: IndexBoardUndoState?
}

struct IndexBoardUndoState {
    let logicalState: IndexBoardLogicalState
    let editorDraft: IndexBoardEditorDraft?
    let summaryRecordsByCardID: [UUID: IndexBoardCardSummaryRecord]
}

enum MainRightResolution {
    case target(SceneCard)
    case armed
    case unavailable
}

enum MainArrowDirection {
    case up
    case down
    case left
    case right
}

enum HistoryRetentionTier: String {
    case recentHour
    case recentDay
    case recentWeek
    case recentMonth
    case archive
}

let focusModeBodySafetyInset: CGFloat = 8

final class WeakTextViewBox {
    weak var textView: NSTextView?
}

#if DEBUG
func bounceDebugLog(_ message: @autoclosure () -> String) {}
#else
func bounceDebugLog(_ message: @autoclosure () -> String) {}
#endif

private enum MainWorkspacePhase0Diagnostics {
    static let isEnabled = false
    static let logURL = URL(fileURLWithPath: "/tmp/wa_main_workspace_phase0.log")
    static let queue = DispatchQueue(label: "wa.main-workspace-phase0")
    static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

func mainWorkspacePhase0Mark(_ label: String) {
    guard MainWorkspacePhase0Diagnostics.isEnabled else { return }
    let line = "\n========== \(label) ==========\n"
    let data = Data(line.utf8)
    MainWorkspacePhase0Diagnostics.queue.async {
        if FileManager.default.fileExists(atPath: MainWorkspacePhase0Diagnostics.logURL.path),
           let handle = try? FileHandle(forWritingTo: MainWorkspacePhase0Diagnostics.logURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            return
        }
        try? data.write(to: MainWorkspacePhase0Diagnostics.logURL, options: .atomic)
    }
}

func mainWorkspacePhase0Log(
    _ event: String,
    _ details: @autoclosure @escaping () -> String = ""
) {
    guard MainWorkspacePhase0Diagnostics.isEnabled else { return }
    let timestamp = MainWorkspacePhase0Diagnostics.formatter.string(from: Date())
    let line = "[\(timestamp)] \(event) \(details())\n"
    let data = Data(line.utf8)
    MainWorkspacePhase0Diagnostics.queue.async {
        if FileManager.default.fileExists(atPath: MainWorkspacePhase0Diagnostics.logURL.path),
           let handle = try? FileHandle(forWritingTo: MainWorkspacePhase0Diagnostics.logURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            return
        }
        try? data.write(to: MainWorkspacePhase0Diagnostics.logURL, options: .atomic)
    }
}

func mainWorkspacePhase0CardID(_ id: UUID?) -> String {
    guard let id else { return "nil" }
    return id.uuidString
}

private func mainWorkspacePhase0RectSummary(_ rect: NSRect) -> String {
    "(\(Int(rect.origin.x.rounded())),\(Int(rect.origin.y.rounded())),\(Int(rect.size.width.rounded())),\(Int(rect.size.height.rounded())))"
}

func mainWorkspacePhase0TextViewSummary(
    _ textView: NSTextView?,
    expectedText: String? = nil
) -> String {
    guard let textView else { return "nil" }
    let selected = textView.selectedRange()
    let textLength = (textView.string as NSString).length
    let matchSummary: String
    if let expectedText {
        matchSummary = textView.string == expectedText ? "match" : "mismatch"
    } else {
        matchSummary = "n/a"
    }
    let windowSummary: String
    if let window = textView.window {
        windowSummary = "win=\(ObjectIdentifier(window).hashValue) key=\(window.isKeyWindow)"
    } else {
        windowSummary = "win=nil"
    }
    let scrollSummary: String
    if let scrollView = textView.enclosingScrollView {
        scrollSummary = "scroll=\(ObjectIdentifier(scrollView).hashValue) frame=\(mainWorkspacePhase0RectSummary(scrollView.frame))"
    } else {
        scrollSummary = "scroll=nil"
    }
    let superviewSummary: String
    if let superview = textView.superview {
        superviewSummary = "super=\(String(describing: type(of: superview)))#\(ObjectIdentifier(superview).hashValue)"
    } else {
        superviewSummary = "super=nil"
    }
    return
        "textView=\(ObjectIdentifier(textView).hashValue) class=\(String(describing: type(of: textView))) " +
        "frame=\(mainWorkspacePhase0RectSummary(textView.frame)) bounds=\(mainWorkspacePhase0RectSummary(textView.bounds)) " +
        "\(windowSummary) \(scrollSummary) \(superviewSummary) " +
        "len=\(textLength) sel=\(selected.location):\(selected.length) match=\(matchSummary)"
}

func mainWorkspacePhase0ResponderSummary(expectedText: String? = nil) -> String {
    guard let responder = NSApp.keyWindow?.firstResponder else { return "none" }
    if let textView = responder as? NSTextView {
        return mainWorkspacePhase0TextViewSummary(textView, expectedText: expectedText)
    }
    return "responder=\(String(describing: type(of: responder)))"
}

enum SoftBoundaryFeedbackSound {
    @MainActor static let shared: AVAudioPlayer? = {
        let url = URL(fileURLWithPath: "/System/Library/Sounds/Pop.aiff")
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 0.16
        player?.prepareToPlay()
        return player
    }()
}

@MainActor
func preloadSoftBoundaryFeedbackSound() {
    SoftBoundaryFeedbackSound.shared?.prepareToPlay()
}

@MainActor
func playSoftBoundaryFeedbackSound() {
    guard let sound = SoftBoundaryFeedbackSound.shared else { return }
    if sound.isPlaying {
        sound.stop()
    }
    sound.currentTime = 0
    sound.play()
}

enum ScenarioCardCategory {
    static let plot = "플롯"
    static let note = "노트"
    static let craft = "작법"
    static let uncategorized = "미분류"
}

enum FocusModeLayoutMetrics {
    static let focusModePreferredCardWidth: CGFloat = 916
    static let focusModeOuterHorizontalPadding: CGFloat = 32
    static let focusModeContentPadding: CGFloat = 143
    static let focusModeLineFragmentPadding: CGFloat = 5
    static var focusModeHorizontalPadding: CGFloat {
        max(0, focusModeContentPadding - focusModeLineFragmentPadding)
    }

    static func resolvedTextWidth(for cardWidth: CGFloat) -> CGFloat {
        max(1, cardWidth - (focusModeHorizontalPadding * 2))
    }
}

enum MainEditorLayoutMetrics {
    static let mainCardContentPadding: CGFloat = 24
    static let mainEditorLineFragmentPadding: CGFloat = 5
    static let mainEditorHeightUpdateThreshold: CGFloat = 0.5
    static var mainEditorHorizontalPadding: CGFloat {
        max(0, mainCardContentPadding - mainEditorLineFragmentPadding)
    }
    static var mainEditorEffectiveInset: CGFloat {
        mainEditorHorizontalPadding + mainEditorLineFragmentPadding
    }
}

enum MainCanvasLayoutMetrics {
    static let columnWidth: CGFloat = 416
    static let columnHorizontalPadding: CGFloat = 6

    static var cardWidth: CGFloat {
        max(1, columnWidth - (columnHorizontalPadding * 2))
    }

    static var textWidth: CGFloat {
        max(1, cardWidth - (MainEditorLayoutMetrics.mainEditorHorizontalPadding * 2))
    }
}

enum MainCanvasHorizontalScrollMode: Int, CaseIterable, Identifiable {
    case oneStep = 1
    case twoStep = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .oneStep:
            return "1단계"
        case .twoStep:
            return "2단계"
        }
    }
}

enum MainEditingViewportRevealEdge: Equatable {
    case top
    case bottom
}

enum FocusModeVerticalScrollAuthorityKind: String {
    case canvasNavigation
    case boundaryTransition
    case caretEnsure
    case fallbackReveal
}

struct FocusModeVerticalScrollAuthority: Equatable {
    let id: Int
    let kind: FocusModeVerticalScrollAuthorityKind
    let targetCardID: UUID?
}

struct FocusModeWorkspaceSnapshot: Equatable {
    let activeCardID: UUID?
    let editingCardID: UUID?
    let selectedCardIDs: Set<UUID>
    let visibleMainCanvasLevel: Int?
    let mainCanvasHorizontalOffset: CGFloat?
    let mainColumnViewportOffsets: [String: CGFloat]
    let capturedAt: Date
}

enum FocusModePresentationPhase: String, Equatable {
    case inactive
    case entering
    case active
    case exiting
}

enum MainSelectionActiveEdge {
    case start
    case end
}

struct AICandidateTrackingState {
    var parentID: UUID? = nil
    var cardIDs: [UUID] = []
    var action: AICardAction? = nil
}

struct LevelData {
    let cards: [SceneCard]
    let parent: SceneCard?
}

struct DisplayedMainLevelsCacheKey: Equatable {
    let cardsVersion: Int
    let activeCategory: String?
    let isActiveCardRoot: Bool
}

struct MainColumnFocusRequest: Equatable {
    let targetID: UUID
    let prefersTopAnchor: Bool
    let keepVisibleOnly: Bool
    let editingRevealEdge: MainEditingViewportRevealEdge?
    let cardsCount: Int
    let firstCardID: UUID?
    let lastCardID: UUID?
    let viewportHeightBucket: Int
}

struct MainColumnLayoutFrame: Equatable {
    let minY: CGFloat
    let maxY: CGFloat

    var height: CGFloat { maxY - minY }
}

enum MainCardHeightMode: Int, Hashable {
    case display
    case editingFallback
}

struct MainCardHeightCacheKey: Hashable {
    let cardID: UUID
    let contentFingerprint: UInt64
    let textLength: Int
    let widthBucket: Int
    let fontSizeBucket: Int
    let lineSpacingBucket: Int
    let mode: MainCardHeightMode
}

struct MainCardHeightRecord {
    let key: MainCardHeightCacheKey
    let height: CGFloat
}

struct MainColumnLayoutCacheKey: Hashable {
    let recordsVersion: Int
    let contentVersion: Int
    let viewportHeightBucket: Int
    let fontSizeBucket: Int
    let lineSpacingBucket: Int
    let editingCardID: UUID?
    let editingHeightBucket: Int
    let cardIDs: [UUID]
}

struct MainColumnLayoutSnapshot {
    let key: MainColumnLayoutCacheKey
    let framesByCardID: [UUID: MainColumnLayoutFrame]
    let orderedCardIDs: [UUID]
    let contentBottomY: CGFloat
}

@MainActor
final class AppWindowState: ObservableObject {
    @Published var focusModeWindowBackgroundActive: Bool = false
}

struct IndexBoardCanvasDigestSnapshot: Equatable {
    let contentHash: Int
    let shortSummary: String
    let updatedAt: Date
}

struct IndexBoardCanvasDerivedPayload {
    let surfaceProjection: BoardSurfaceProjection
    let projection: IndexBoardProjection
    let cardsByID: [UUID: SceneCard]
    let summaryByCardID: [UUID: IndexBoardResolvedSummary]
}

@MainActor
final class IndexBoardCanvasDerivedCache: ObservableObject {
    private var cachedProjectionSurfaceProjection: BoardSurfaceProjection?
    private var cachedProjection: IndexBoardProjection?
    private var cachedReferencedCardIDs: [UUID] = []
    private var cachedCardsVersion: Int = -1
    private var cachedSummaryRecordsByCardID: [UUID: IndexBoardCardSummaryRecord] = [:]
    private var cachedDigestSnapshotsByCardID: [UUID: IndexBoardCanvasDigestSnapshot] = [:]
    private var cachedCardsByID: [UUID: SceneCard] = [:]
    private var cachedSummaryByCardID: [UUID: IndexBoardResolvedSummary] = [:]

    func resolve(
        surfaceProjection: BoardSurfaceProjection,
        referencedCardIDs: [UUID],
        cardsVersion: Int,
        summaryRecordsByCardID: [UUID: IndexBoardCardSummaryRecord],
        digestSnapshotsByCardID: [UUID: IndexBoardCanvasDigestSnapshot],
        buildProjection: () -> IndexBoardProjection,
        buildContent: () -> (
            cardsByID: [UUID: SceneCard],
            summaryByCardID: [UUID: IndexBoardResolvedSummary]
        )
    ) -> IndexBoardCanvasDerivedPayload {
        if cachedProjectionSurfaceProjection != surfaceProjection || cachedProjection == nil {
            cachedProjectionSurfaceProjection = surfaceProjection
            cachedProjection = buildProjection()
        }

        let shouldRefreshContent =
            cachedReferencedCardIDs != referencedCardIDs ||
            cachedCardsVersion != cardsVersion ||
            cachedSummaryRecordsByCardID != summaryRecordsByCardID ||
            cachedDigestSnapshotsByCardID != digestSnapshotsByCardID

        if shouldRefreshContent {
            let nextContent = buildContent()
            cachedReferencedCardIDs = referencedCardIDs
            cachedCardsVersion = cardsVersion
            cachedSummaryRecordsByCardID = summaryRecordsByCardID
            cachedDigestSnapshotsByCardID = digestSnapshotsByCardID
            cachedCardsByID = nextContent.cardsByID
            cachedSummaryByCardID = nextContent.summaryByCardID
        }

        return IndexBoardCanvasDerivedPayload(
            surfaceProjection: surfaceProjection,
            projection: cachedProjection ?? buildProjection(),
            cardsByID: cachedCardsByID,
            summaryByCardID: cachedSummaryByCardID
        )
    }
}

struct MainCardRenderSettings: Equatable {
    let fontSize: CGFloat
    let appearance: String
    let lineSpacing: CGFloat
    let cardBaseColorHex: String
    let cardActiveColorHex: String
    let cardRelatedColorHex: String
    let darkCardBaseColorHex: String
    let darkCardActiveColorHex: String
    let darkCardRelatedColorHex: String
}

struct ReferenceCardRenderSettings: Equatable {
    let fontSize: CGFloat
    let appearance: String
    let lineSpacing: CGFloat
    let cardActiveColorHex: String
    let darkCardActiveColorHex: String
}

// Imperative editor caches that do not need SwiftUI-driven invalidation.
final class WriterInteractionRuntime {
    var activeAncestorIDs: Set<UUID> = []
    var activeDescendantIDs: Set<UUID> = []
    var activeSiblingIDs: Set<UUID> = []
    var activeRelationSourceCardID: UUID? = nil
    var activeRelationSourceCardsVersion: Int = -1
    var activeRelationFingerprint: Int = 0
    var lastActiveCardID: UUID? = nil
    var lastScrolledLevel: Int = 0
    var pendingMainHorizontalScrollAnimation: Bool? = nil
    var pendingMainClickFocusTargetID: UUID? = nil
    var pendingMainClickHorizontalFocusTargetID: UUID? = nil
    var pendingMainEditingViewportKeepVisibleCardID: UUID? = nil
    var pendingMainEditingViewportRevealEdge: MainEditingViewportRevealEdge? = nil
    var pendingMainEditingSiblingNavigationTargetID: UUID? = nil
    var pendingMainEditingBoundaryNavigationTargetID: UUID? = nil
    var pendingMainReorderMotionCardIDs: [UUID] = []
    var pendingMainReorderHorizontalOffsetX: CGFloat? = nil
    var pendingMainDeferredColumnViewportRestoreOffsets: [String: CGFloat] = [:]
    var pendingActiveCardID: UUID? = nil
    var resolvedLevelsWithParentsVersion: Int = -1
    var resolvedLevelsWithParentsCache: [LevelData] = []
    var displayedMainLevelsCacheKey: DisplayedMainLevelsCacheKey? = nil
    var displayedMainLevelsCache: [LevelData] = []
    var displayedMainCardLocationByIDCache: [UUID: (level: Int, index: Int)] = [:]
    var mainColumnLastFocusRequestByKey: [String: MainColumnFocusRequest] = [:]
    var mainColumnViewportOffsetByKey: [String: CGFloat] = [:]
    var mainColumnObservedCardFramesByKey: [String: [UUID: CGRect]] = [:]
    var mainColumnObservedEditorSlotFramesByKey: [String: [UUID: CGRect]] = [:]
    var mainColumnLayoutSnapshotByKey: [MainColumnLayoutCacheKey: MainColumnLayoutSnapshot] = [:]
    var mainCardHeightRecordByKey: [MainCardHeightCacheKey: MainCardHeightRecord] = [:]
    var mainColumnViewportCaptureSuspendedUntil: Date = .distantPast
    var mainColumnViewportRestoreUntil: Date = .distantPast
    var mainArrowNavigationSettleWorkItem: DispatchWorkItem? = nil
    var mainCaretLocationByCardID: [UUID: Int] = [:]
    var mainLineSpacingAppliedCardID: UUID? = nil
    var mainLineSpacingAppliedValue: CGFloat = -1
    var mainLineSpacingAppliedResponderID: ObjectIdentifier? = nil
    var suppressMainFocusRestoreAfterFinishEditing: Bool = false
    var mainSelectionLastCardID: UUID? = nil
    var mainSelectionLastLocation: Int = -1
    var mainSelectionLastLength: Int = -1
    var mainSelectionLastTextLength: Int = -1
    var mainSelectionLastResponderID: ObjectIdentifier? = nil
    var mainSelectionActiveEdge: MainSelectionActiveEdge = .end
    var mainCaretEnsureLastScheduledAt: Date = .distantPast
    var mainProgrammaticCaretSuppressEnsureCardID: UUID? = nil
    var mainProgrammaticCaretExpectedCardID: UUID? = nil
    var mainProgrammaticCaretExpectedLocation: Int = -1
    var mainProgrammaticCaretSelectionIgnoreUntil: Date = .distantPast
    var pendingFocusModeEntryCaretHint: (cardID: UUID, location: Int)? = nil
    var focusResponderCardByObjectID: [ObjectIdentifier: UUID] = [:]
    var focusLineSpacingAppliedCardID: UUID? = nil
    var focusLineSpacingAppliedValue: CGFloat = -1
    var focusLineSpacingAppliedFontSize: CGFloat = -1
    var focusLineSpacingAppliedResponderID: ObjectIdentifier? = nil
    var focusSelectionLastCardID: UUID? = nil
    var focusSelectionLastLocation: Int = -1
    var focusSelectionLastLength: Int = -1
    var focusSelectionLastTextLength: Int = -1
    var focusSelectionLastResponderID: ObjectIdentifier? = nil
    var focusCaretEnsureLastScheduledAt: Date = .distantPast
    var focusProgrammaticCaretExpectedCardID: UUID? = nil
    var focusProgrammaticCaretExpectedLocation: Int = -1
    var focusProgrammaticCaretSelectionIgnoreUntil: Date = .distantPast
    var focusOffsetNormalizationLastAt: Date = .distantPast
    var focusSelectionProcessingPending: Bool = false
    var focusVerticalScrollAuthoritySequence: Int = 0
    var focusVerticalScrollAuthority: FocusModeVerticalScrollAuthority? = nil
    var historySaveRequestWorkItem: DispatchWorkItem? = nil
    var historySaveRequestNextAllowedAt: Date = .distantPast
}

final class MainCardDragSessionTracker {
    static let shared = MainCardDragSessionTracker()

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var pollingTimer: Timer?
    private(set) var isDragging = false
    private(set) var isCommandPressed = false

    private init() {}

    func refreshCommandState() {
        isCommandPressed = NSEvent.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.command)
    }

    func begin() {
        if isDragging {
            refreshCommandState()
            return
        }

        isDragging = true
        refreshCommandState()

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged, .leftMouseUp, .rightMouseUp, .otherMouseUp]
        ) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .flagsChanged:
                self.isCommandPressed = event.modifierFlags
                    .intersection(.deviceIndependentFlagsMask)
                    .contains(.command)
            case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                self.end()
            default:
                break
            }
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged, .leftMouseUp, .rightMouseUp, .otherMouseUp]
        ) { [weak self] event in
            guard let self else { return }
            switch event.type {
            case .flagsChanged:
                self.isCommandPressed = event.modifierFlags
                    .intersection(.deviceIndependentFlagsMask)
                    .contains(.command)
            case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                self.end()
            default:
                break
            }
        }

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, self.isDragging else { return }
            self.refreshCommandState()
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer
    }

    func end() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        pollingTimer?.invalidate()
        pollingTimer = nil
        isDragging = false
        isCommandPressed = false
    }
}

final class MainCanvasViewState: ObservableObject {
    struct RestoreRequest: Equatable {
        enum Reason: String {
            case generic
            case focusExit
        }

        let id: Int
        let targetCardID: UUID
        let visibleLevel: Int?
        let forceSemantic: Bool
        let reason: Reason
    }

    @Published var pendingRestoreRequest: RestoreRequest? = nil
    @Published var suppressAutoScrollOnce: Bool = false
    @Published var suppressHorizontalAutoScroll: Bool = false
    @Published var interactionFingerprint: Int = 0
    @Published var focusNavigationTargetID: UUID? = nil
    @Published var focusNavigationTick: Int = 0
    @Published var navigationSettleTick: Int = 0
    @Published var maxLevelCount: Int = 0
    @Published var surfaceDocumentSizeByViewportKey: [String: CGSize] = [:]

    private var restoreRequestSequence: Int = 0

    func scheduleRestoreRequest(
        targetCardID: UUID,
        visibleLevel: Int? = nil,
        forceSemantic: Bool = false,
        reason: RestoreRequest.Reason = .generic
    ) {
        restoreRequestSequence &+= 1
        pendingRestoreRequest = RestoreRequest(
            id: restoreRequestSequence,
            targetCardID: targetCardID,
            visibleLevel: visibleLevel,
            forceSemantic: forceSemantic,
            reason: reason
        )
    }
}

@MainActor
final class WriterAIFeatureState: ObservableObject {
    @Published var chatThreads: [AIChatThread] = []
    @Published var activeThreadID: UUID? = nil
    @Published var chatInput: String = ""
    @Published var lastContextPreview: AIChatContextPreview? = nil
    @Published var isChatLoading: Bool = false
    @Published var chatActiveRequestID: UUID? = nil
    @Published var optionsSheetAction: AICardAction? = nil
    @Published var selectedGenerationOptions: Set<AIGenerationOption> = [.balanced]
    @Published var isGenerating: Bool = false
    @Published var statusMessage: String? = nil
    @Published var statusIsError: Bool = false
    @Published var candidateState = AICandidateTrackingState()
    @Published var childSummaryLoadingCardIDs: Set<UUID> = []

    var cardDigestCache: [UUID: AICardDigest] = [:]
    var embeddingIndexByCardID: [UUID: AIEmbeddingRecord] = [:]
    var embeddingIndexModelID: String = "gemini-embedding-001"
    var threadsLoadedScenarioID: UUID? = nil
    var embeddingIndexLoadedScenarioID: UUID? = nil
    var threadsSaveWorkItem: DispatchWorkItem? = nil
    var embeddingIndexSaveWorkItem: DispatchWorkItem? = nil
    var chatRequestTask: Task<Void, Never>? = nil

    deinit {
        threadsSaveWorkItem?.cancel()
        embeddingIndexSaveWorkItem?.cancel()
        chatRequestTask?.cancel()
    }
}

@MainActor
final class WriterEditEndAutoBackupState: ObservableObject {
    var pendingWorkItem: DispatchWorkItem? = nil
    var isRunning: Bool = false
    var hasPendingRequest: Bool = false

    deinit {
        pendingWorkItem?.cancel()
    }
}

@MainActor
final class ScenarioWriterObservedState: ObservableObject {
    @Published private(set) var cardsVersion: Int = 0
    @Published private(set) var historyVersion: Int = 0
    @Published private(set) var linkedCardsVersion: Int = 0

    private var boundScenarioObjectID: ObjectIdentifier?
    private var cancellables: Set<AnyCancellable> = []

    init(scenario: Scenario) {
        bind(to: scenario)
    }

    func bind(to scenario: Scenario) {
        let objectID = ObjectIdentifier(scenario)
        guard boundScenarioObjectID != objectID else { return }

        boundScenarioObjectID = objectID
        cancellables.removeAll()

        cardsVersion = scenario.cardsVersion
        historyVersion &+= 1
        linkedCardsVersion &+= 1

        scenario.$cardsVersion
            .removeDuplicates()
            .sink { [weak self] newValue in
                self?.cardsVersion = newValue
            }
            .store(in: &cancellables)

        scenario.$snapshots
            .dropFirst()
            .sink { [weak self] _ in
                self?.historyVersion &+= 1
            }
            .store(in: &cancellables)

        scenario.$linkedCardEditDatesByFocusCardID
            .dropFirst()
            .sink { [weak self] _ in
                self?.linkedCardsVersion &+= 1
            }
            .store(in: &cancellables)
    }
}

enum TimelinePanelLayoutMetrics {
    static let panelWidth: CGFloat = 416
    static let contentHorizontalPadding: CGFloat = 12

    static var cardWidth: CGFloat {
        max(1, panelWidth - (contentHorizontalPadding * 2))
    }

    static var textWidth: CGFloat {
        max(1, cardWidth - (MainEditorLayoutMetrics.mainEditorHorizontalPadding * 2))
    }
}

// MARK: - Array safe subscript
