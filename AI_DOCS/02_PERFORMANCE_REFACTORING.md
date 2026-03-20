# 02 Performance Refactoring

## Scope

- Preserved visible user behavior, feature set, and persistence semantics.
- Reduced row-level `@AppStorage` observation in repeated SwiftUI views.
- Moved editor-shared types out of `ScenarioWriterView` to remove shared-layer dependence on a view type.
- Replaced persisted focus-mode window background state with app-owned session state.
- Verified the refactor with a successful Debug build via `xcodebuild -project wa.xcodeproj -scheme wa -derivedDataPath .codex_derived build`.

## Refactoring Notes

- `WriterSharedTypes.swift`: extracted view-coupled cache and render types into top-level shared types; added `AppWindowState`, `MainCardRenderSettings`, and `ReferenceCardRenderSettings`.
- `WriterViews.swift`: removed the persisted `focusModeWindowBackgroundActive` flag from view storage, introduced environment-backed session ownership, and centralized main-card render snapshot creation.
- `WriterCardViews.swift`: changed `CardItem` to consume immutable render settings instead of observing multiple user-default keys per row.
- `WriterCardManagement.swift`: injected shared main-card render settings into both timeline and main-canvas card rows.
- `ReferenceWindow.swift`: changed repeated reference rows to consume parent-supplied render settings instead of row-local `@AppStorage`.
- `waApp.swift`: moved transient window background state to an app-owned `StateObject` and supplied it through the main window environment.

--------------------------------
File: WriterSharedTypes.swift
--------------------------------

```swift
import SwiftUI
import AppKit
import AVFoundation
import Combine
import QuartzCore

let focusModeBodySafetyInset: CGFloat = 8

#if DEBUG
func bounceDebugLog(_ message: @autoclosure () -> String) {}
#else
func bounceDebugLog(_ message: @autoclosure () -> String) {}
#endif

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

enum MainVerticalScrollAuthorityKind: String {
    case columnNavigation
    case editingTransition
    case caretEnsure
    case viewportRestore
}

struct MainVerticalScrollAuthority: Equatable {
    let id: Int
    let kind: MainVerticalScrollAuthorityKind
    let targetCardID: UUID?
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
    var pendingActiveCardID: UUID? = nil
    var mainVerticalScrollAuthoritySequence: Int = 0
    var mainVerticalScrollAuthorityByViewportKey: [String: MainVerticalScrollAuthority] = [:]
    var resolvedLevelsWithParentsVersion: Int = -1
    var resolvedLevelsWithParentsCache: [LevelData] = []
    var displayedMainLevelsCacheKey: DisplayedMainLevelsCacheKey? = nil
    var displayedMainLevelsCache: [LevelData] = []
    var displayedMainCardLocationByIDCache: [UUID: (level: Int, index: Int)] = [:]
    var mainColumnLastFocusRequestByKey: [String: MainColumnFocusRequest] = [:]
    var mainColumnViewportOffsetByKey: [String: CGFloat] = [:]
    var mainColumnObservedCardFramesByKey: [String: [UUID: CGRect]] = [:]
    var mainColumnLayoutSnapshotByKey: [MainColumnLayoutCacheKey: MainColumnLayoutSnapshot] = [:]
    var mainCardHeightRecordByKey: [MainCardHeightCacheKey: MainCardHeightRecord] = [:]
    var mainColumnPendingFocusVerificationWorkItemByKey: [String: DispatchWorkItem] = [:]
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

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - 공유 색상 유틸리티 (캐싱)

let hexColorCache = HexColorCache()

final class HexColorCache: @unchecked Sendable {
    private var cache: [String: (Double, Double, Double)] = [:]
    private let lock = NSLock()

    func rgb(from hex: String) -> (Double, Double, Double)? {
        var hexValue = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if hexValue.hasPrefix("#") { hexValue.removeFirst() }
        lock.lock()
        if let cached = cache[hexValue] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        guard hexValue.count == 6, let intVal = Int(hexValue, radix: 16) else { return nil }
        let r = Double((intVal >> 16) & 0xFF) / 255.0
        let g = Double((intVal >> 8) & 0xFF) / 255.0
        let b = Double(intVal & 0xFF) / 255.0
        let result = (r, g, b)
        lock.lock()
        cache[hexValue] = result
        lock.unlock()
        return result
    }
}

func parseHexRGB(_ hex: String, stripAllHashes: Bool = false) -> (Double, Double, Double)? {
    let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = stripAllHashes ? trimmed.replacingOccurrences(of: "#", with: "") : trimmed
    return hexColorCache.rgb(from: normalized)
}

func normalizeGeminiModelIDValue(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let lowered = trimmed.lowercased()
    switch lowered {
    case "gemini-3.1-pro", "gemini-3.1-pro-latest":
        return "gemini-3.1-pro-preview"
    case "gemini-3-pro", "gemini-3.0-pro", "gemini-3-pro-latest":
        return "gemini-3-pro-preview"
    case "gemini-3-flash-latest":
        return "gemini-3-flash"
    default:
        return trimmed
    }
}

// MARK: - Shared Text Measurement Utilities

private let sharedTextHeightMeasurementCache = SharedTextHeightMeasurementCache()

func normalizedSharedMeasurementText(_ text: String) -> String {
    if text.isEmpty {
        return " "
    }
    if text.hasSuffix("\n") {
        return text + " "
    }
    return text
}

func sharedStableTextFingerprint(_ text: String) -> UInt64 {
    var hash: UInt64 = 1469598103934665603
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1099511628211
    }
    return hash
}

final class SharedTextHeightMeasurementCache: @unchecked Sendable {
    private let cache = NSCache<NSString, NSNumber>()

    init() {
        cache.countLimit = 4096
    }

    func measureBodyHeight(
        text: String,
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        width: CGFloat,
        lineFragmentPadding: CGFloat,
        safetyInset: CGFloat
    ) -> CGFloat {
        let measuringText = normalizedSharedMeasurementText(text)
        let constrainedWidth = max(1, width)
        let cacheKey = measurementCacheKey(
            text: measuringText,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            width: constrainedWidth,
            lineFragmentPadding: lineFragmentPadding,
            safetyInset: safetyInset
        )

        if let cached = cache.object(forKey: cacheKey) {
            return CGFloat(cached.doubleValue)
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping

        let font = NSFont(name: "SansMonoCJKFinalDraft", size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        let storage = NSTextStorage(
            string: measuringText,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
        )
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: CGSize(width: constrainedWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.lineFragmentPadding = lineFragmentPadding
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.maximumNumberOfLines = 0
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let usedHeight = layoutManager.usedRect(for: textContainer).height
        let measured = max(1, ceil(usedHeight + safetyInset))
        cache.setObject(NSNumber(value: Double(measured)), forKey: cacheKey)
        return measured
    }

    private func measurementCacheKey(
        text: String,
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        width: CGFloat,
        lineFragmentPadding: CGFloat,
        safetyInset: CGFloat
    ) -> NSString {
        let fingerprint = sharedStableTextFingerprint(text)
        let fontBits = Double(fontSize).bitPattern
        let spacingBits = Double(lineSpacing).bitPattern
        let widthBits = Double(width).bitPattern
        let paddingBits = Double(lineFragmentPadding).bitPattern
        let insetBits = Double(safetyInset).bitPattern
        let key = "\(fontBits)|\(spacingBits)|\(widthBits)|\(paddingBits)|\(insetBits)|\(text.utf16.count)|\(fingerprint)"
        return key as NSString
    }
}

func sharedMeasuredTextBodyHeight(
    text: String,
    fontSize: CGFloat,
    lineSpacing: CGFloat,
    width: CGFloat,
    lineFragmentPadding: CGFloat,
    safetyInset: CGFloat
) -> CGFloat {
    sharedTextHeightMeasurementCache.measureBodyHeight(
        text: text,
        fontSize: fontSize,
        lineSpacing: lineSpacing,
        width: width,
        lineFragmentPadding: lineFragmentPadding,
        safetyInset: safetyInset
    )
}

func sharedResolvedClickCaretLocation(
    text: String,
    localPoint: CGPoint,
    textWidth: CGFloat,
    fontSize: CGFloat,
    lineSpacing: CGFloat,
    horizontalInset: CGFloat,
    verticalInset: CGFloat,
    lineFragmentPadding: CGFloat,
    safetyInset: CGFloat = 0
) -> Int {
    let originalText = text
    let textLength = (originalText as NSString).length
    guard textLength > 0 else { return 0 }

    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = lineSpacing
    paragraphStyle.lineBreakMode = .byWordWrapping

    let font = NSFont(name: "SansMonoCJKFinalDraft", size: fontSize)
        ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

    let storage = NSTextStorage(
        string: normalizedSharedMeasurementText(originalText),
        attributes: [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
    )
    let layoutManager = NSLayoutManager()
    let textContainer = NSTextContainer(
        size: CGSize(width: max(1, textWidth), height: .greatestFiniteMagnitude)
    )
    textContainer.lineFragmentPadding = lineFragmentPadding
    textContainer.lineBreakMode = .byWordWrapping
    textContainer.maximumNumberOfLines = 0
    textContainer.widthTracksTextView = false
    textContainer.heightTracksTextView = false
    layoutManager.addTextContainer(textContainer)
    storage.addLayoutManager(layoutManager)
    layoutManager.ensureLayout(for: textContainer)

    let usedRect = layoutManager.usedRect(for: textContainer)
    let containerPoint = CGPoint(
        x: localPoint.x - horizontalInset,
        y: localPoint.y - verticalInset
    )
    if containerPoint.y <= 0 {
        return 0
    }
    if containerPoint.y >= usedRect.maxY + safetyInset {
        return textLength
    }

    let clampedPoint = CGPoint(
        x: max(0, min(containerPoint.x, textContainer.size.width)),
        y: max(0, containerPoint.y)
    )
    var fraction: CGFloat = 0
    let rawIndex = layoutManager.characterIndex(
        for: clampedPoint,
        in: textContainer,
        fractionOfDistanceBetweenInsertionPoints: &fraction
    )
    return min(max(0, rawIndex), textLength)
}

func sharedLiveTextViewBodyHeight(
    _ textView: NSTextView,
    safetyInset: CGFloat = 0,
    includeTextContainerInset: Bool = false
) -> CGFloat? {
    guard let layoutManager = textView.layoutManager,
          let textContainer = textView.textContainer else { return nil }

    let textLength = (textView.string as NSString).length
    if textLength > 0 {
        let fullRange = NSRange(location: 0, length: textLength)
        layoutManager.ensureGlyphs(forCharacterRange: fullRange)
        layoutManager.ensureLayout(forCharacterRange: fullRange)
    }
    layoutManager.ensureLayout(for: textContainer)

    let usedHeight = layoutManager.usedRect(for: textContainer).height
    guard usedHeight > 0 else { return nil }

    let insetHeight = includeTextContainerInset ? (textView.textContainerInset.height * 2) : 0
    return max(1, ceil(usedHeight + insetHeight + safetyInset))
}

// MARK: - Shared Text Processing Utilities

typealias TextChangeDelta = (prefix: Int, oldChangedLength: Int, newChangedLength: Int, inserted: String)

func sharedUTF16ChangeDeltaValue(oldValue: String, newValue: String) -> TextChangeDelta {
    let oldText = oldValue as NSString
    let newText = newValue as NSString
    let oldLength = oldText.length
    let newLength = newText.length

    var prefix = 0
    let limit = min(oldLength, newLength)
    while prefix < limit && oldText.character(at: prefix) == newText.character(at: prefix) {
        prefix += 1
    }

    var oldSuffix = oldLength
    var newSuffix = newLength
    while oldSuffix > prefix && newSuffix > prefix &&
            oldText.character(at: oldSuffix - 1) == newText.character(at: newSuffix - 1) {
        oldSuffix -= 1
        newSuffix -= 1
    }

    let oldChangedLength = max(0, oldSuffix - prefix)
    let newChangedLength = max(0, newSuffix - prefix)
    let inserted: String
    if newChangedLength > 0 {
        inserted = newText.substring(with: NSRange(location: prefix, length: newChangedLength))
    } else {
        inserted = ""
    }
    return (prefix, oldChangedLength, newChangedLength, inserted)
}

func sharedHasParagraphBreakBoundary(in text: NSString, delta: TextChangeDelta) -> Bool {
    guard delta.newChangedLength > 0 else { return false }
    let start = delta.prefix
    let end = delta.prefix + delta.newChangedLength
    if start < 0 || end > text.length || start >= end { return false }

    var i = start
    while i < end {
        let unit = text.character(at: i)
        if unit == 10 || unit == 13 {
            if sharedLineHasSignificantContentBeforeBreak(in: text, breakIndex: i) {
                return true
            }
        }
        i += 1
    }
    return false
}

// MARK: - Fountain Clipboard Parsing

struct FountainClipboardImport {
    let coverCardContent: String?
    let sceneCards: [String]

    var cardContents: [String] {
        var result: [String] = []
        if let coverCardContent,
           !coverCardContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(coverCardContent)
        }
        result.append(contentsOf: sceneCards)
        return result
    }
}

struct FountainClipboardPastePreview {
    let rawText: String
    let importPayload: FountainClipboardImport
}

enum StructuredTextPasteOption: Equatable {
    case plainText
    case sceneCards
}

func parseFountainClipboardImport(from rawText: String) -> FountainClipboardImport? {
    let normalized = normalizedClipboardText(rawText)
    let lines = normalized.components(separatedBy: "\n")
    guard let firstSceneIndex = lines.firstIndex(where: isFountainSceneHeadingLine) else { return nil }

    let sceneCards = buildFountainSceneCards(from: lines, startingAt: firstSceneIndex)
    guard sceneCards.count >= 2 else { return nil }

    let titlePageFields = parseFountainTitlePageFields(from: Array(lines[..<firstSceneIndex]))
    let coverCardContent = buildFountainCoverCardContent(from: titlePageFields)

    return FountainClipboardImport(
        coverCardContent: coverCardContent,
        sceneCards: sceneCards
    )
}

func normalizedClipboardText(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
}

func isFountainSceneHeadingLine(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }

    if trimmed.hasPrefix(".") {
        let remainder = trimmed.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        return !remainder.isEmpty
    }

    let uppercased = trimmed.uppercased()
    return uppercased.hasPrefix("INT.")
        || uppercased.hasPrefix("EXT.")
        || uppercased.hasPrefix("INT/EXT.")
        || uppercased.hasPrefix("I/E.")
}

func buildFountainSceneCards(from lines: [String], startingAt firstSceneIndex: Int) -> [String] {
    var cards: [String] = []
    var currentLines: [String] = []

    for line in lines[firstSceneIndex...] {
        if isFountainSceneHeadingLine(line),
           !currentLines.isEmpty {
            let card = currentLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !card.isEmpty {
                cards.append(card)
            }
            currentLines = []
        }
        currentLines.append(line)
    }

    let trailingCard = currentLines
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if !trailingCard.isEmpty {
        cards.append(trailingCard)
    }

    return cards
}

func parseFountainTitlePageFields(from lines: [String]) -> [String: [String]] {
    var fields: [String: [String]] = [:]
    var currentKey: String? = nil

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            currentKey = nil
            continue
        }

        if let field = parseFountainTitlePageField(trimmed) {
            let normalizedKey = normalizedFountainTitlePageFieldKey(field.key)
            currentKey = normalizedKey
            if !field.value.isEmpty {
                fields[normalizedKey, default: []].append(field.value)
            } else if fields[normalizedKey] == nil {
                fields[normalizedKey] = []
            }
            continue
        }

        guard line.hasPrefix("\t") || line.hasPrefix(" ") else {
            currentKey = nil
            continue
        }

        guard let currentKey else { continue }
        fields[currentKey, default: []].append(trimmed)
    }

    return fields
}

func parseFountainTitlePageField(_ line: String) -> (key: String, value: String)? {
    guard let separatorIndex = line.firstIndex(of: ":") else { return nil }
    let key = line[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { return nil }
    let valueStart = line.index(after: separatorIndex)
    let value = line[valueStart...].trimmingCharacters(in: .whitespacesAndNewlines)
    return (key: key, value: value)
}

func normalizedFountainTitlePageFieldKey(_ key: String) -> String {
    key
        .lowercased()
        .filter { $0.isLetter || $0.isNumber }
}

func buildFountainCoverCardContent(from fields: [String: [String]]) -> String? {
    let titleValues = fields["title"] ?? []
    let title = titleValues.first?.trimmingCharacters(in: .whitespacesAndNewlines)
    let revision = joinedFountainFieldValues(Array(titleValues.dropFirst()), separator: " / ")
    let date = joinedFountainFieldValues(fields["draftdate"], separator: " / ")
    let author = joinedFountainFieldValues(fields["author"], separator: " / ")
    let company = joinedFountainFieldValues(
        fields["company"]
        ?? fields["productioncompany"]
        ?? fields["production"],
        separator: " / "
    )

    let contact = joinedFountainFieldValues(
        resolvedFountainContactValues(from: fields),
        separator: ", "
    )

    var lines: [String] = []
    if let title, !title.isEmpty {
        lines.append("# \(title)")
    }
    if let revision, !revision.isEmpty {
        lines.append("## \(revision)")
    }
    if let date, !date.isEmpty {
        lines.append("### \(date)")
    }
    if let author, !author.isEmpty {
        lines.append("#### \(author)")
    }
    if let company, !company.isEmpty {
        lines.append("##### \(company)")
    }
    if let contact, !contact.isEmpty {
        lines.append("###### \(contact)")
    }

    let result = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty ? nil : result
}

func resolvedFountainContactValues(from fields: [String: [String]]) -> [String]? {
    if let direct = fields["contact"], !direct.isEmpty {
        return direct
    }

    var values: [String] = []
    if let email = fields["email"]?.first,
       !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        values.append(email)
    }
    if let phone = fields["phone"]?.first,
       !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        values.append(phone)
    }
    return values.isEmpty ? nil : values
}

func joinedFountainFieldValues(_ values: [String]?, separator: String) -> String? {
    guard let values else { return nil }
    let normalized = values
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard !normalized.isEmpty else { return nil }
    return normalized.joined(separator: separator)
}

func sharedLineHasSignificantContentBeforeBreak(in text: NSString, breakIndex: Int) -> Bool {
    guard breakIndex > 0 else { return false }
    var i = breakIndex - 1
    while i >= 0 {
        let unit = text.character(at: i)
        if unit == 10 || unit == 13 {
            return false
        }
        if let scalar = UnicodeScalar(unit), CharacterSet.whitespacesAndNewlines.contains(scalar) {
            if i == 0 { break }
            i -= 1
            continue
        }
        return true
    }
    return false
}

func sharedHasSentenceEndingPeriodBoundarySimple(in text: NSString, delta: TextChangeDelta) -> Bool {
    guard delta.newChangedLength > 0 else { return false }
    let start = delta.prefix
    let end = delta.prefix + delta.newChangedLength
    if start < 0 || end > text.length || start >= end { return false }

    var i = start
    while i < end {
        let unit = text.character(at: i)
        if unit == 46 || unit == 12290 {
            let nextIndex = i + 1
            if nextIndex >= text.length {
                return true
            }
            let nextUnit = text.character(at: nextIndex)
            if let scalar = UnicodeScalar(nextUnit), CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return true
            }
        }
        i += 1
    }
    return false
}

func sharedHasSentenceEndingPeriodBoundaryExtended(in text: NSString, delta: TextChangeDelta) -> Bool {
    guard delta.newChangedLength > 0 else { return false }
    let start = delta.prefix
    let end = delta.prefix + delta.newChangedLength
    if start < 0 || end > text.length || start >= end { return false }

    var i = start
    while i < end {
        let unit = text.character(at: i)
        if unit == 46 || unit == 12290 {
            if sharedIsSentenceEndingPeriod(at: i, in: text) {
                return true
            }
        }
        i += 1
    }
    return false
}

func sharedIsSentenceEndingPeriod(at index: Int, in text: NSString) -> Bool {
    if sharedIsDigitAtUTF16Index(text, index: index - 1) && sharedIsDigitAtUTF16Index(text, index: index + 1) {
        return false
    }

    var i = index + 1
    while i < text.length {
        let unit = text.character(at: i)
        if unit == 10 || unit == 13 {
            return true
        }
        if sharedIsWhitespaceUnit(unit) || sharedIsClosingPunctuationUnit(unit) {
            i += 1
            continue
        }
        return false
    }
    return true
}

func sharedIsWhitespaceUnit(_ unit: unichar) -> Bool {
    guard let scalar = UnicodeScalar(unit) else { return false }
    return CharacterSet.whitespacesAndNewlines.contains(scalar)
}

func sharedIsDigitAtUTF16Index(_ text: NSString, index: Int) -> Bool {
    guard index >= 0, index < text.length else { return false }
    let unit = text.character(at: index)
    guard let scalar = UnicodeScalar(unit) else { return false }
    return CharacterSet.decimalDigits.contains(scalar)
}

func sharedIsClosingPunctuationUnit(_ unit: unichar) -> Bool {
    switch unit {
    case 41, 93, 125, 34, 39:
        return true
    case 12289, 12290, 12291, 12299, 12301, 12303, 12305:
        return true
    case 8217, 8221:
        return true
    default:
        return false
    }
}

func sharedClampTextValue(_ text: String, maxLength: Int, preserveLineBreak: Bool = false) -> String {
    var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !preserveLineBreak {
        normalized = normalized.replacingOccurrences(of: "\n", with: " / ")
    }
    normalized = normalized.replacingOccurrences(of: "\t", with: " ")
    if normalized.isEmpty { return "(비어 있음)" }
    if normalized.count <= maxLength { return normalized }
    let index = normalized.index(normalized.startIndex, offsetBy: maxLength)
    return String(normalized[..<index]) + "..."
}

func sharedSearchTokensValue(from text: String) -> [String] {
    let allowed = text.lowercased().unicodeScalars.map { scalar -> Character in
        if CharacterSet.alphanumerics.contains(scalar) || (scalar.value >= 0xAC00 && scalar.value <= 0xD7A3) {
            return Character(scalar)
        }
        return " "
    }
    let normalized = String(allowed)
    let words = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    var tokens: [String] = []
    tokens.reserveCapacity(words.count * 2)
    for word in words {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { continue }
        tokens.append(trimmed)
        if trimmed.unicodeScalars.contains(where: { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }) {
            let chars = Array(trimmed)
            if chars.count >= 2 {
                for index in 0..<(chars.count - 1) {
                    tokens.append(String(chars[index...index + 1]))
                }
            }
        }
    }
    return tokens
}

enum CaretScrollCoordinator {
    static func resolvedVerticalTargetY(
        visibleRect: CGRect,
        targetY: CGFloat,
        minY: CGFloat,
        maxY: CGFloat,
        snapToPixel: Bool = false
    ) -> CGFloat {
        let clampedY = min(max(minY, targetY), maxY)
        return snapToPixel ? round(clampedY) : clampedY
    }

    static func resolvedVerticalAnimationDuration(
        currentY: CGFloat,
        targetY: CGFloat,
        viewportHeight: CGFloat
    ) -> TimeInterval {
        let distance = abs(targetY - currentY)
        let reference = max(1, viewportHeight)
        let normalized = min(1.8, distance / reference)
        return 0.18 + (0.10 * Double(normalized))
    }

    @discardableResult
    static func applyVerticalScrollIfNeeded(
        scrollView: NSScrollView,
        visibleRect: CGRect,
        targetY: CGFloat,
        minY: CGFloat,
        maxY: CGFloat,
        deadZone: CGFloat = 1.0,
        snapToPixel: Bool = false
    ) -> Bool {
        let resolvedTargetY = resolvedVerticalTargetY(
            visibleRect: visibleRect,
            targetY: targetY,
            minY: minY,
            maxY: maxY,
            snapToPixel: snapToPixel
        )
        guard abs(resolvedTargetY - visibleRect.origin.y) > deadZone else { return false }

        scrollView.contentView.setBoundsOrigin(NSPoint(x: visibleRect.origin.x, y: resolvedTargetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        return true
    }

    @discardableResult
    static func applyAnimatedVerticalScrollIfNeeded(
        scrollView: NSScrollView,
        visibleRect: CGRect,
        targetY: CGFloat,
        minY: CGFloat,
        maxY: CGFloat,
        deadZone: CGFloat = 1.0,
        snapToPixel: Bool = false,
        duration: TimeInterval? = nil
    ) -> TimeInterval? {
        let resolvedTargetY = resolvedVerticalTargetY(
            visibleRect: visibleRect,
            targetY: targetY,
            minY: minY,
            maxY: maxY,
            snapToPixel: snapToPixel
        )
        guard abs(resolvedTargetY - visibleRect.origin.y) > deadZone else { return nil }

        let resolvedDuration = duration ?? resolvedVerticalAnimationDuration(
            currentY: visibleRect.origin.y,
            targetY: resolvedTargetY,
            viewportHeight: visibleRect.height
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = resolvedDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.86, 0.24, 1.0)
            scrollView.contentView.animator().setBoundsOrigin(
                NSPoint(x: visibleRect.origin.x, y: resolvedTargetY)
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
        } completionHandler: {
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        return resolvedDuration
    }

    static func resolvedHorizontalTargetX(
        visibleRect: CGRect,
        targetX: CGFloat,
        minX: CGFloat,
        maxX: CGFloat,
        snapToPixel: Bool = false
    ) -> CGFloat {
        let clampedX = min(max(minX, targetX), maxX)
        return snapToPixel ? round(clampedX) : clampedX
    }

    static func resolvedHorizontalAnimationDuration(
        currentX: CGFloat,
        targetX: CGFloat,
        viewportWidth: CGFloat
    ) -> TimeInterval {
        let distance = abs(targetX - currentX)
        let reference = max(1, viewportWidth)
        let normalized = min(1.8, distance / reference)
        return 0.18 + (0.10 * Double(normalized))
    }

    @discardableResult
    static func applyHorizontalScrollIfNeeded(
        scrollView: NSScrollView,
        visibleRect: CGRect,
        targetX: CGFloat,
        minX: CGFloat,
        maxX: CGFloat,
        deadZone: CGFloat = 1.0,
        snapToPixel: Bool = false
    ) -> Bool {
        let resolvedTargetX = resolvedHorizontalTargetX(
            visibleRect: visibleRect,
            targetX: targetX,
            minX: minX,
            maxX: maxX,
            snapToPixel: snapToPixel
        )
        guard abs(resolvedTargetX - visibleRect.origin.x) > deadZone else { return false }

        scrollView.contentView.setBoundsOrigin(NSPoint(x: resolvedTargetX, y: visibleRect.origin.y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        return true
    }

    @discardableResult
    static func applyAnimatedHorizontalScrollIfNeeded(
        scrollView: NSScrollView,
        visibleRect: CGRect,
        targetX: CGFloat,
        minX: CGFloat,
        maxX: CGFloat,
        deadZone: CGFloat = 1.0,
        snapToPixel: Bool = false,
        duration: TimeInterval? = nil
    ) -> TimeInterval? {
        let resolvedTargetX = resolvedHorizontalTargetX(
            visibleRect: visibleRect,
            targetX: targetX,
            minX: minX,
            maxX: maxX,
            snapToPixel: snapToPixel
        )
        guard abs(resolvedTargetX - visibleRect.origin.x) > deadZone else { return nil }

        let resolvedDuration = duration ?? resolvedHorizontalAnimationDuration(
            currentX: visibleRect.origin.x,
            targetX: resolvedTargetX,
            viewportWidth: visibleRect.width
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = resolvedDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.86, 0.24, 1.0)
            scrollView.contentView.animator().setBoundsOrigin(
                NSPoint(x: resolvedTargetX, y: visibleRect.origin.y)
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
        } completionHandler: {
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        return resolvedDuration
    }
}

struct MainCanvasHorizontalScrollViewAccessor: NSViewRepresentable {
    let scrollCoordinator: MainCanvasScrollCoordinator

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.attach(to: view, scrollCoordinator: scrollCoordinator)
    }

    final class Coordinator {
        private var scrollCoordinator: MainCanvasScrollCoordinator?
        private weak var scrollView: NSScrollView?
        private weak var observedDocumentView: NSView?
        private var contentBoundsObserver: NSObjectProtocol?
        private var documentFrameObserver: NSObjectProtocol?
        private var documentBoundsObserver: NSObjectProtocol?

        deinit {
            detach()
        }

        func attach(to view: NSView, scrollCoordinator: MainCanvasScrollCoordinator) {
            self.scrollCoordinator = scrollCoordinator
            guard let resolvedScrollView = resolveScrollView(from: view) else {
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view else { return }
                    self.attach(to: view, scrollCoordinator: scrollCoordinator)
                }
                return
            }

            let documentViewChanged = observedDocumentView !== resolvedScrollView.documentView
            guard scrollView !== resolvedScrollView || documentViewChanged else { return }
            detach()
            scrollView = resolvedScrollView
            installObservers(for: resolvedScrollView)
            scrollCoordinator.registerMainCanvasHorizontalScrollView(resolvedScrollView)
        }

        private func detach() {
            if let contentBoundsObserver {
                NotificationCenter.default.removeObserver(contentBoundsObserver)
            }
            if let documentFrameObserver {
                NotificationCenter.default.removeObserver(documentFrameObserver)
            }
            if let documentBoundsObserver {
                NotificationCenter.default.removeObserver(documentBoundsObserver)
            }
            contentBoundsObserver = nil
            documentFrameObserver = nil
            documentBoundsObserver = nil
            observedDocumentView = nil
            if let scrollView {
                scrollCoordinator?.unregisterMainCanvasHorizontalScrollView(matching: scrollView)
            }
            scrollView = nil
            scrollCoordinator = nil
        }

        private func installObservers(for scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            contentBoundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                Task { @MainActor [weak self, weak scrollView] in
                    guard let self, let scrollView else { return }
                    self.scrollCoordinator?.refreshMainCanvasHorizontalScrollViewState(scrollView)
                }
            }

            if let documentView = scrollView.documentView {
                observedDocumentView = documentView
                documentView.postsFrameChangedNotifications = true
                documentView.postsBoundsChangedNotifications = true
                documentFrameObserver = NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: documentView,
                    queue: .main
                ) { [weak self, weak scrollView] _ in
                    Task { @MainActor [weak self, weak scrollView] in
                        guard let self, let scrollView else { return }
                        self.scrollCoordinator?.refreshMainCanvasHorizontalScrollViewState(scrollView)
                    }
                }
                documentBoundsObserver = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: documentView,
                    queue: .main
                ) { [weak self, weak scrollView] _ in
                    Task { @MainActor [weak self, weak scrollView] in
                        guard let self, let scrollView else { return }
                        self.scrollCoordinator?.refreshMainCanvasHorizontalScrollViewState(scrollView)
                    }
                }
            }
        }

        private func resolveScrollView(from view: NSView) -> NSScrollView? {
            var current: NSView? = view
            while let candidate = current {
                if let scrollView = candidate.enclosingScrollView {
                    return scrollView
                }
                current = candidate.superview
            }
            return nil
        }
    }
}

struct MainColumnScrollViewAccessor: NSViewRepresentable {
    let scrollCoordinator: MainCanvasScrollCoordinator
    let columnKey: String
    let storedOffsetY: CGFloat?
    let onOffsetChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.attach(
            to: view,
            scrollCoordinator: scrollCoordinator,
            columnKey: columnKey,
            storedOffsetY: storedOffsetY,
            onOffsetChange: onOffsetChange
        )
    }

    final class Coordinator {
        private var scrollCoordinator: MainCanvasScrollCoordinator?
        private weak var scrollView: NSScrollView?
        private var observer: NSObjectProtocol?
        private var attachedColumnKey: String?
        private var lastReportedOffsetY: CGFloat = .nan
        private var offsetChangeHandler: ((CGFloat) -> Void)?

        deinit {
            detach()
        }

        func attach(
            to view: NSView,
            scrollCoordinator: MainCanvasScrollCoordinator,
            columnKey: String,
            storedOffsetY: CGFloat?,
            onOffsetChange: @escaping (CGFloat) -> Void
        ) {
            self.scrollCoordinator = scrollCoordinator
            guard let resolvedScrollView = resolveScrollView(from: view) else {
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view else { return }
                    self.attach(
                        to: view,
                        scrollCoordinator: scrollCoordinator,
                        columnKey: columnKey,
                        storedOffsetY: storedOffsetY,
                        onOffsetChange: onOffsetChange
                    )
                }
                return
            }

            if scrollView !== resolvedScrollView {
                detach()
                scrollView = resolvedScrollView
                installObserver(for: resolvedScrollView)
            }

            let keyChanged = attachedColumnKey != columnKey
            if keyChanged, let previousKey = attachedColumnKey {
                scrollCoordinator.unregister(viewportKey: previousKey, matching: resolvedScrollView)
            }
            attachedColumnKey = columnKey
            scrollCoordinator.register(scrollView: resolvedScrollView, for: columnKey)
            offsetChangeHandler = onOffsetChange
            if keyChanged {
                lastReportedOffsetY = .nan
            }
            publishCurrentOffset()

            if keyChanged, let storedOffsetY, storedOffsetY > 1 {
                applyStoredOffsetIfNeeded(storedOffsetY)
            }
        }

        private func detach() {
            if let attachedColumnKey, let scrollView {
                scrollCoordinator?.unregister(viewportKey: attachedColumnKey, matching: scrollView)
            }
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            observer = nil
            scrollView = nil
            attachedColumnKey = nil
            lastReportedOffsetY = .nan
            offsetChangeHandler = nil
            scrollCoordinator = nil
        }

        private func installObserver(for scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.publishCurrentOffset()
            }
        }

        private func publishCurrentOffset() {
            guard let scrollView, let offsetChangeHandler else { return }
            let originY = scrollView.contentView.bounds.origin.y
            guard lastReportedOffsetY.isNaN || abs(lastReportedOffsetY - originY) > 0.5 else { return }
            lastReportedOffsetY = originY
            DispatchQueue.main.async {
                offsetChangeHandler(originY)
            }
        }

        private func applyStoredOffsetIfNeeded(_ storedOffsetY: CGFloat) {
            guard let scrollView else { return }
            DispatchQueue.main.async { [weak self, weak scrollView] in
                guard let self, let scrollView else { return }
                let visible = scrollView.documentVisibleRect
                let documentHeight = scrollView.documentView?.bounds.height ?? 0
                let maxY = max(0, documentHeight - visible.height)
                bounceDebugLog(
                    "applyStoredOffset key=\(self.attachedColumnKey ?? "nil") " +
                    "stored=\(String(format: "%.1f", storedOffsetY)) current=\(String(format: "%.1f", visible.origin.y)) " +
                    "max=\(String(format: "%.1f", maxY))"
                )
                let applied = CaretScrollCoordinator.applyVerticalScrollIfNeeded(
                    scrollView: scrollView,
                    visibleRect: visible,
                    targetY: storedOffsetY,
                    minY: 0,
                    maxY: maxY,
                    deadZone: 0.5,
                    snapToPixel: true
                )
                if applied {
                    self.lastReportedOffsetY = scrollView.contentView.bounds.origin.y
                }
            }
        }

        private func resolveScrollView(from view: NSView) -> NSScrollView? {
            var current: NSView? = view
            while let candidate = current {
                if let scrollView = candidate.enclosingScrollView {
                    return scrollView
                }
                current = candidate.superview
            }
            return nil
        }
    }
}

// MARK: - 히스토리 비교를 위한 타입

enum DiffStatus {
    case added, deleted, modified, none
}

struct SnapshotDiff: Identifiable {
    let id: UUID // cardID
    let snapshot: CardSnapshot
    let status: DiffStatus
}

// MARK: - 드롭 위치 식별을 위한 타입

enum DropTarget: Equatable {
    case before(UUID)
    case after(UUID)
    case onto(UUID)
    case columnTop(UUID?) // 부모 ID
    case columnBottom(UUID?) // 부모 ID
}

let waCardTreePasteboardType = NSPasteboard.PasteboardType("com.riwoong.wa.cardTree")
let waCloneCardPasteboardType = NSPasteboard.PasteboardType("com.riwoong.wa.cloneCard")

struct CardTreeClipboardNode: Codable {
    let content: String
    let colorHex: String?
    let isAICandidate: Bool
    let children: [CardTreeClipboardNode]
}

struct CardTreeClipboardPayload: Codable {
    let roots: [CardTreeClipboardNode]
}

struct CloneCardClipboardItem: Codable {
    let sourceCardID: UUID
    let cloneGroupID: UUID?
    let content: String
    let colorHex: String?
    let isAICandidate: Bool
}

struct CloneCardClipboardPayload: Codable {
    let sourceScenarioID: UUID
    let items: [CloneCardClipboardItem]
}

enum ClonePastePlacement {
    case child
    case sibling
}

struct ClonePeerMenuDestination: Identifiable {
    let id: UUID
    let title: String
}

// MARK: - AI 카드 생성 타입

enum AICardAction: String, CaseIterable, Identifiable {
    case elaborate
    case nextScene
    case alternative
    case summary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .elaborate:
            return "구체화"
        case .nextScene:
            return "다음 장면"
        case .alternative:
            return "대안"
        case .summary:
            return "요약"
        }
    }

    var sheetTitle: String {
        switch self {
        case .elaborate:
            return "구체화 옵션"
        case .nextScene:
            return "다음 장면 옵션"
        case .alternative:
            return "대안 옵션"
        case .summary:
            return "요약 옵션"
        }
    }

    var summaryLabel: String {
        switch self {
        case .elaborate:
            return "구체화 제안"
        case .nextScene:
            return "다음 장면 제안"
        case .alternative:
            return "대안 제안"
        case .summary:
            return "요약 제안"
        }
    }

    var promptGuideline: String {
        switch self {
        case .elaborate:
            return "현재 카드의 의미를 유지하면서 사건/행동/선택/결과를 더 명확하게 구체화한 5가지 버전을 제시한다. 분량을 억지로 늘리거나 묘사만 과도하게 늘리지 않는다."
        case .nextScene:
            return "현재 카드 다음에 올 수 있는 장면 5가지를 제시한다. 빠르게 비교할 수 있도록 각 제안은 간결하고 핵심 중심으로 쓴다."
        case .alternative:
            return "현재 카드와 핵심 목적은 유지하되 접근 방식과 톤, 사건 배열이 다른 대안 5가지를 제시한다."
        case .summary:
            return "현재 카드의 핵심 정보를 누락 없이 더 높은 밀도로 요약한 최종 결과 1개를 제시한다."
        }
    }

    var contentLengthGuideline: String {
        switch self {
        case .elaborate:
            return "각 content는 3~6문장"
        case .nextScene:
            return "각 content는 1~3문장"
        case .alternative:
            return "각 content는 2~4문장"
        case .summary:
            return "content는 단일 요약문"
        }
    }
}

enum AIGenerationOption: String, CaseIterable, Identifiable, Hashable {
    case balanced
    case conflict
    case choice
    case secret
    case twist
    case emotion
    case relationship
    case worldbuilding
    case symbol
    case genreVariation
    case themeDeepening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced:
            return "균형 확장"
        case .conflict:
            return "갈등"
        case .choice:
            return "선택"
        case .secret:
            return "비밀"
        case .twist:
            return "반전"
        case .emotion:
            return "감정"
        case .relationship:
            return "관계"
        case .worldbuilding:
            return "세계관"
        case .symbol:
            return "상징"
        case .genreVariation:
            return "장르 변주"
        case .themeDeepening:
            return "주제 심화"
        }
    }

    var shortDescription: String {
        switch self {
        case .balanced:
            return "갈등/선택/감정/주제를 균형 있게 강화"
        case .conflict:
            return "내적/관계적/사회적/물리적 갈등의 긴장 강화"
        case .choice:
            return "주인공의 결정 분기로 플롯 방향 변화"
        case .secret:
            return "숨겨진 정보 공개/은폐로 추진력 확보"
        case .twist:
            return "주제와 연결된 반전 또는 전복"
        case .emotion:
            return "관객 감정 이입과 정서 온도 상승"
        case .relationship:
            return "인물 관계의 재정의와 역학 변화"
        case .worldbuilding:
            return "배경 규칙, 사회 구조, 맥락 확장"
        case .symbol:
            return "상징/메타포 장면으로 의미층 강화"
        case .genreVariation:
            return "현재 톤을 유지하며 장르적 긴장 변주"
        case .themeDeepening:
            return "설교 없이 주제를 더 선명하게 강화"
        }
    }

    var promptInstruction: String {
        switch self {
        case .balanced:
            return "갈등, 선택, 감정, 주제의 균형을 유지하면서 서로 다른 5개 방향을 만든다."
        case .conflict:
            return "갈등 유형을 분산한다. (내적/관계적/사회적/물리적/철학적 중 최소 3종류 이상)"
        case .choice:
            return "주인공의 선택이 플롯을 크게 갈라놓도록 설계한다."
        case .secret:
            return "비밀의 노출 시점과 은폐 전략으로 긴장을 설계한다."
        case .twist:
            return "억지 반전이 아니라 기존 주제와 인과를 유지한 전복을 만든다."
        case .emotion:
            return "감정의 원인-표현-여파가 명확히 보이게 한다."
        case .relationship:
            return "인물 간 권력/신뢰/의존 관계가 변하는 지점을 만든다."
        case .worldbuilding:
            return "세계의 규칙이나 제약이 사건을 직접 움직이게 한다."
        case .symbol:
            return "상징 장면이 플롯과 감정의 변화에 실제로 기여하게 한다."
        case .genreVariation:
            return "같은 사건을 장르 톤(스릴러/멜로/누아르/블랙코미디 등)으로 변주한다."
        case .themeDeepening:
            return "주제 문장을 직접 말하지 말고 행동과 결과로 주제를 드러낸다."
        }
    }
}

// MARK: - PreferenceKeys

struct FocusModeMeasuredActiveHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

struct FocusModeMeasuredInactiveHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

struct FocusModeEditorBodyHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

struct FocusModeCardRootHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

struct FocusModeCardFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct MainColumnCardFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct HistoryBarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

```

--------------------------------
File: WriterViews.swift
--------------------------------

```swift
import SwiftUI
import AppKit

final class WeakTextViewBox {
    weak var textView: NSTextView?
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
    @State var mainColumnPendingFocusWorkItemByKey: [String: DispatchWorkItem] = [:]
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

    var mainVerticalScrollAuthoritySequence: Int {
        get { interactionRuntime.mainVerticalScrollAuthoritySequence }
        nonmutating set { interactionRuntime.mainVerticalScrollAuthoritySequence = newValue }
    }

    var mainVerticalScrollAuthorityByViewportKey: [String: MainVerticalScrollAuthority] {
        get { interactionRuntime.mainVerticalScrollAuthorityByViewportKey }
        nonmutating set { interactionRuntime.mainVerticalScrollAuthorityByViewportKey = newValue }
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

    var mainColumnLayoutSnapshotByKey: [MainColumnLayoutCacheKey: MainColumnLayoutSnapshot] {
        get { interactionRuntime.mainColumnLayoutSnapshotByKey }
        nonmutating set { interactionRuntime.mainColumnLayoutSnapshotByKey = newValue }
    }

    var mainCardHeightRecordByKey: [MainCardHeightCacheKey: MainCardHeightRecord] {
        get { interactionRuntime.mainCardHeightRecordByKey }
        nonmutating set { interactionRuntime.mainCardHeightRecordByKey = newValue }
    }

    var mainColumnPendingFocusVerificationWorkItemByKey: [String: DispatchWorkItem] {
        get { interactionRuntime.mainColumnPendingFocusVerificationWorkItemByKey }
        nonmutating set { interactionRuntime.mainColumnPendingFocusVerificationWorkItemByKey = newValue }
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
                    .onChange(of: viewState.focusNavigationTick) { _, _ in
                        onActiveCardChange(
                            viewState.focusNavigationTargetID,
                            proxy,
                            renderState.availableWidth
                        )
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
        publishMainColumnFocusNavigationIntent(for: newID)
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
        if isBoundaryNavigation {
            pendingMainEditingBoundaryNavigationTargetID = nil
        }
        let suppressInitialEnsure = isBoundaryNavigation || mainProgrammaticCaretSuppressEnsureCardID == newID
        restoreMainEditingCaret(
            for: newID,
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
                historyOverlayHost(containerHeight: geometry.size.height)
                    .transition(.move(edge: .trailing))
            }
        } else {
            HStack(spacing: 0) {
                primaryWorkspaceColumn(size: geometry.size, availableWidth: availableWidth)
                if !showFocusMode {
                    trailingWorkspacePanelHost
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
                    .accessibilityHidden(showFocusMode)
                    .zIndex(0)

                if showWorkspaceTopToolbar && !showFocusMode {
                    workspaceTopToolbarHost
                        .zIndex(5)
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
                checkpointToolbarButton
                historyToolbarButton
                aiChatToolbarButton
                timelineToolbarButton
            }
            Spacer()
        }
        .ignoresSafeArea(.container, edges: [.top, .leading, .trailing, .bottom])
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
                guard !showFocusMode else { return }
                handleMainCanvasHistoryIndexChange(hProxy: proxy)
            },
            onActiveCardChange: { newID, proxy, width in
                guard !showFocusMode else { return }
                handleMainCanvasActiveCardChange(newID, hProxy: proxy, availableWidth: width)
            },
            onNavigationSettle: { proxy, width in
                guard !showFocusMode else { return }
                handleMainCanvasNavigationSettle(hProxy: proxy, availableWidth: width)
            },
            onRestoreRequest: { proxy, width in
                guard !showFocusMode else { return }
                handleMainCanvasRestoreRequest(hProxy: proxy, availableWidth: width)
            },
            onAppear: { proxy, width in
                guard !showFocusMode else { return }
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
            finishEditing()
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
        if showFocusMode { return }
        if pendingMainEditingSiblingNavigationTargetID == id { return }
        let clickFocusedTarget = pendingMainClickHorizontalFocusTargetID == id
        if suppressHorizontalAutoScroll && !clickFocusedTarget { return }
        if suppressAutoScrollOnce {
            suppressAutoScrollOnce = false
            if !clickFocusedTarget {
                return
            }
        }
        let animated =
            focusNavigationAnimationEnabled &&
            (pendingMainHorizontalScrollAnimation ?? !shouldSuppressMainArrowRepeatAnimation())
        pendingMainHorizontalScrollAnimation = nil
        if clickFocusedTarget {
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
            scrollToColumnIfNeeded(
                targetCardID: id,
                proxy: hProxy,
                availableWidth: availableWidth,
                force: clickFocusedTarget && mainCanvasHorizontalScrollMode == .oneStep,
                animated: animated
            )
        }
    }

    func scheduleMainCanvasClickHorizontalFocusAlignment(
        targetCardID: UUID,
        hProxy: ScrollViewProxy,
        availableWidth: CGFloat
    ) {
        let animated =
            focusNavigationAnimationEnabled &&
            (pendingMainHorizontalScrollAnimation ?? !shouldSuppressMainArrowRepeatAnimation())
        pendingMainHorizontalScrollAnimation = nil
        let retryDelays: [TimeInterval] = [0.0, 0.03, 0.08, 0.16]

        for (index, delay) in retryDelays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard !showFocusMode else { return }
                guard acceptsKeyboardInput else { return }

                if activeCardID != targetCardID {
                    if pendingMainClickHorizontalFocusTargetID == targetCardID {
                        pendingMainClickHorizontalFocusTargetID = nil
                    }
                    return
                }

                guard displayedMainCardLocationByID(targetCardID) != nil else {
                    return
                }

                if mainCanvasHorizontalScrollMode == .oneStep,
                   let targetLevel = displayedMainCardLocationByID(targetCardID)?.level,
                   let scrollView = mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalScrollView() {
                    let visibleRect = scrollView.documentVisibleRect
                    let targetX = resolvedMainCanvasHorizontalTargetX(
                        level: targetLevel,
                        availableWidth: max(1, availableWidth),
                        visibleWidth: visibleRect.width
                    )
                    lastScrolledLevel = targetLevel
                    mainCanvasScrollCoordinator.scheduleMainCanvasHorizontalRestore(offsetX: targetX)
                    _ = performMainCanvasHorizontalScroll(
                        level: targetLevel,
                        availableWidth: max(1, availableWidth),
                        animated: index == 0 ? animated : false
                    )
                } else {
                    scrollToColumnIfNeeded(
                        targetCardID: targetCardID,
                        proxy: hProxy,
                        availableWidth: availableWidth,
                        force: false,
                        animated: index == 0 ? animated : false
                    )
                }

                if isMainCanvasHorizontallyAlignedForClickFocus(
                    targetCardID: targetCardID,
                    availableWidth: availableWidth
                ) {
                    if pendingMainClickHorizontalFocusTargetID == targetCardID {
                        pendingMainClickHorizontalFocusTargetID = nil
                    }
                }
            }
        }
    }

    func isMainCanvasHorizontallyAlignedForClickFocus(
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
            beginCardEditing(target)
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
        scheduleMainCanvasRestoreRetries {
            applyStoredMainColumnViewportOffsets(restoredOffsets)
        }
    }

    func applyStoredMainColumnViewportOffsets(_ offsets: [String: CGFloat]) {
        guard !offsets.isEmpty else { return }

        var didScheduleCaptureSuspension = false
        for (viewportKey, storedOffsetY) in offsets.sorted(by: { $0.key < $1.key }) {
            guard storedOffsetY > 1 else { continue }
            guard let scrollView = mainCanvasScrollCoordinator.scrollView(for: viewportKey) else { continue }
            _ = beginMainVerticalScrollAuthority(
                viewportKey: viewportKey,
                kind: .viewportRestore,
                targetCardID: activeCardID
            )

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
        } else {
            horizontalOffsets.removeValue(forKey: persistenceKey)
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

```

--------------------------------
File: WriterCardViews.swift
--------------------------------

```swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers

private func resolveFocusModeTextFont(_ fontSize: CGFloat) -> NSFont {
    NSFont(name: "SansMonoCJKFinalDraft", size: fontSize)
        ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
}

private func resolveFocusModeTextColor(_ appearance: String) -> NSColor {
    appearance == "light" ? .black : .white
}

private func makeFocusModeRenderParagraphStyle(_ lineSpacing: CGFloat) -> NSMutableParagraphStyle {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = lineSpacing
    paragraphStyle.lineBreakMode = .byWordWrapping
    paragraphStyle.lineHeightMultiple = 1.0
    paragraphStyle.paragraphSpacing = 0
    paragraphStyle.paragraphSpacingBefore = 0
    return paragraphStyle
}

private func makeFocusModeAttributedString(
    _ text: String,
    fontSize: CGFloat,
    lineSpacing: CGFloat,
    appearance: String
) -> NSAttributedString {
    NSAttributedString(
        string: text,
        attributes: [
            .font: resolveFocusModeTextFont(fontSize),
            .foregroundColor: resolveFocusModeTextColor(appearance),
            .paragraphStyle: makeFocusModeRenderParagraphStyle(lineSpacing)
        ]
    )
}

private func resolvedFocusModeObservedBodyHeight(_ textView: NSTextView) -> CGFloat? {
    guard let layoutManager = textView.layoutManager,
          let textContainer = textView.textContainer else { return nil }
    let textLength = (textView.string as NSString).length
    if textLength > 0 {
        let fullRange = NSRange(location: 0, length: textLength)
        layoutManager.ensureGlyphs(forCharacterRange: fullRange)
        layoutManager.ensureLayout(forCharacterRange: fullRange)
    }
    layoutManager.ensureLayout(for: textContainer)
    let usedHeight = layoutManager.usedRect(for: textContainer).height
    guard usedHeight > 0 else { return nil }
    return max(1, ceil(usedHeight + focusModeBodySafetyInset))
}

private struct FocusModeReadOnlyTextRenderer: NSViewRepresentable {
    struct Signature: Equatable {
        let text: String
        let textWidthBucket: Int
        let bodyHeightBucket: Int
        let fontSizeBucket: Int
        let lineSpacingBucket: Int
        let isLightAppearance: Bool
    }

    final class Coordinator {
        var lastSignature: Signature?
    }

    let text: String
    let textWidth: CGFloat
    let bodyHeight: CGFloat
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let appearance: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: textWidth, height: bodyHeight))
        textView.isEditable = false
        textView.isSelectable = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.usesFindBar = false
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        if let textContainer = textView.textContainer {
            textContainer.lineFragmentPadding = FocusModeLayoutMetrics.focusModeLineFragmentPadding
            textContainer.lineBreakMode = .byWordWrapping
            textContainer.maximumNumberOfLines = 0
            textContainer.widthTracksTextView = false
            textContainer.heightTracksTextView = false
            textContainer.containerSize = CGSize(width: textWidth, height: .greatestFiniteMagnitude)
        }

        updateTextView(textView, coordinator: context.coordinator)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        updateTextView(textView, coordinator: context.coordinator)
    }

    private func updateTextView(_ textView: NSTextView, coordinator: Coordinator) {
        let signature = Signature(
            text: text,
            textWidthBucket: Int((textWidth * 10).rounded()),
            bodyHeightBucket: Int((bodyHeight * 10).rounded()),
            fontSizeBucket: Int((fontSize * 10).rounded()),
            lineSpacingBucket: Int((lineSpacing * 10).rounded()),
            isLightAppearance: appearance == "light"
        )

        let resolvedWidth = max(1, textWidth)
        let resolvedHeight = max(1, bodyHeight)
        textView.frame = NSRect(x: 0, y: 0, width: resolvedWidth, height: resolvedHeight)
        textView.textContainerInset = .zero

        if let textContainer = textView.textContainer,
           abs(textContainer.containerSize.width - resolvedWidth) > 0.5 {
            textContainer.containerSize = CGSize(width: resolvedWidth, height: .greatestFiniteMagnitude)
        }

        guard coordinator.lastSignature != signature else { return }
        coordinator.lastSignature = signature

        let font = resolveFocusModeTextFont(fontSize)
        let color = resolveFocusModeTextColor(appearance)
        let attributedString = makeFocusModeAttributedString(
            text,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            appearance: appearance
        )
        textView.textStorage?.setAttributedString(attributedString)
        textView.textColor = color
        textView.font = font
    }
}

private struct FocusModeEditableTextRenderer: NSViewRepresentable {
    struct Signature: Equatable {
        let textWidthBucket: Int
        let bodyHeightBucket: Int
        let fontSizeBucket: Int
        let lineSpacingBucket: Int
        let isLightAppearance: Bool
        let isFocused: Bool
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FocusModeEditableTextRenderer
        var suppressBindingPropagation = false
        var lastSignature: Signature?

        init(_ parent: FocusModeEditableTextRenderer) {
            self.parent = parent
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            parent.layoutCoordinator.beginLiveEditorMutation(for: parent.cardID)
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.reportLiveEditorLayout(from: textView)
            guard !suppressBindingPropagation else { return }
            let updated = textView.string
            if parent.text != updated {
                parent.text = updated
            }
        }
    }

    @Binding var text: String
    let cardID: UUID
    let layoutCoordinator: FocusModeLayoutCoordinator
    let textWidth: CGFloat
    let bodyHeight: CGFloat
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let appearance: String
    let isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: textWidth, height: bodyHeight))
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.usesFindBar = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        if let textContainer = textView.textContainer {
            textContainer.lineFragmentPadding = FocusModeLayoutMetrics.focusModeLineFragmentPadding
            textContainer.lineBreakMode = .byWordWrapping
            textContainer.maximumNumberOfLines = 0
            textContainer.widthTracksTextView = false
            textContainer.heightTracksTextView = false
            textContainer.containerSize = CGSize(width: textWidth, height: .greatestFiniteMagnitude)
        }

        updateTextView(textView, coordinator: context.coordinator)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.parent = self
        if textView.delegate !== context.coordinator {
            textView.delegate = context.coordinator
        }
        updateTextView(textView, coordinator: context.coordinator)
    }

    private func reportLiveEditorLayout(from textView: NSTextView) {
        guard let observedBodyHeight = resolvedFocusModeObservedBodyHeight(textView) else { return }
        layoutCoordinator.reportLiveEditorLayout(
            for: cardID,
            rawText: textView.string,
            bodyHeight: observedBodyHeight,
            textWidth: textWidth,
            fontSize: Double(fontSize),
            lineSpacing: Double(lineSpacing)
        )
    }

    private func updateTextView(_ textView: NSTextView, coordinator: Coordinator) {
        let signature = Signature(
            textWidthBucket: Int((textWidth * 10).rounded()),
            bodyHeightBucket: Int((bodyHeight * 10).rounded()),
            fontSizeBucket: Int((fontSize * 10).rounded()),
            lineSpacingBucket: Int((lineSpacing * 10).rounded()),
            isLightAppearance: appearance == "light",
            isFocused: isFocused
        )

        let resolvedWidth = max(1, textWidth)
        let resolvedHeight = max(1, bodyHeight)
        textView.frame = NSRect(x: 0, y: 0, width: resolvedWidth, height: resolvedHeight)
        textView.textContainerInset = .zero

        if let textContainer = textView.textContainer {
            if abs(textContainer.containerSize.width - resolvedWidth) > 0.5 {
                textContainer.containerSize = CGSize(width: resolvedWidth, height: .greatestFiniteMagnitude)
            }
            if abs(textContainer.lineFragmentPadding - FocusModeLayoutMetrics.focusModeLineFragmentPadding) > 0.01 {
                textContainer.lineFragmentPadding = FocusModeLayoutMetrics.focusModeLineFragmentPadding
            }
            textContainer.lineBreakMode = .byWordWrapping
            textContainer.maximumNumberOfLines = 0
            textContainer.widthTracksTextView = false
            textContainer.heightTracksTextView = false
        }

        let font = resolveFocusModeTextFont(fontSize)
        let color = resolveFocusModeTextColor(appearance)
        let paragraph = makeFocusModeRenderParagraphStyle(lineSpacing)

        if textView.string != text {
            let selected = textView.selectedRange()
            coordinator.suppressBindingPropagation = true
            if text.isEmpty {
                textView.string = ""
            } else {
                textView.textStorage?.setAttributedString(
                    makeFocusModeAttributedString(
                        text,
                        fontSize: fontSize,
                        lineSpacing: lineSpacing,
                        appearance: appearance
                    )
                )
            }
            let clampedLocation = min(selected.location, (text as NSString).length)
            let clampedLength = min(selected.length, max(0, (text as NSString).length - clampedLocation))
            textView.setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
            coordinator.suppressBindingPropagation = false
        }

        if coordinator.lastSignature != signature {
            coordinator.lastSignature = signature
            textView.font = font
            textView.textColor = color
            textView.insertionPointColor = color
            textView.defaultParagraphStyle = paragraph
            if let storage = textView.textStorage, storage.length > 0 {
                storage.beginEditing()
                storage.addAttributes(
                    [
                        .font: font,
                        .foregroundColor: color,
                        .paragraphStyle: paragraph
                    ],
                    range: NSRange(location: 0, length: storage.length)
                )
                storage.endEditing()
            }
            var typing = textView.typingAttributes
            typing[.font] = font
            typing[.foregroundColor] = color
            typing[.paragraphStyle] = paragraph
            textView.typingAttributes = typing
        }

        if isFocused,
           let window = textView.window,
           window.firstResponder !== textView {
            DispatchQueue.main.async {
                guard isFocused else { return }
                guard let liveWindow = textView.window, liveWindow.firstResponder !== textView else { return }
                liveWindow.makeFirstResponder(textView)
            }
        }

        reportLiveEditorLayout(from: textView)
    }
}

// MARK: - 카드 사이 및 열 상/하단 빈 공간 드롭 영역

struct DropSpacer: View {
    let target: DropTarget
    var alignment: Alignment = .center
    let onDrop: ([NSItemProvider], Bool) -> Void
    @AppStorage("mainCardVerticalGap") private var mainCardVerticalGap: Double = 0.0
    @State private var isHovering: Bool = false

    private var centerGapHeight: CGFloat { max(0, CGFloat(mainCardVerticalGap)) }
    private var centerHitAreaHeight: CGFloat { max(12, centerGapHeight) }

    var body: some View {
        Group {
            if alignment == .center {
                Color.clear
                    .frame(height: centerGapHeight)
                    .overlay(alignment: .center) {
                        ZStack {
                            Color.black.opacity(0.001)
                            if isHovering {
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(height: 4)
                                    .cornerRadius(2)
                                    .transition(.opacity)
                            }
                        }
                        .frame(height: centerHitAreaHeight)
                        .contentShape(Rectangle())
                        .onDrop(of: [.text], isTargeted: $isHovering) { providers in
                            onDrop(providers, isTrailingSiblingBlockDragActive())
                            return true
                        }
                    }
            } else {
                ZStack(alignment: alignment) {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())

                    if isHovering {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 4)
                            .cornerRadius(2)
                            .transition(.opacity)
                    }
                }
                .onDrop(of: [.text], isTargeted: $isHovering) { providers in
                    onDrop(providers, isTrailingSiblingBlockDragActive())
                    return true
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}

// MARK: - 히스토리 프리뷰 카드

struct PreviewCardItem: View {
    let diff: SnapshotDiff
    let isSelected: Bool
    let isMultiSelected: Bool
    var onSelect: () -> Void
    var onCopyCards: () -> Void
    var onCopyContents: () -> Void
    @AppStorage("fontSize") private var fontSize: Double = 14.0
    @AppStorage("appearance") private var appearance: String = "dark"

    private var statusColor: Color {
        switch diff.status {
        case .added: return Color.blue.opacity(0.15)
        case .modified: return Color.yellow.opacity(0.15)
        case .deleted: return Color.red.opacity(0.15)
        case .none: return appearance == "light" ? Color.white : Color(white: 0.18)
        }
    }

    private var statusStrokeColor: Color {
        switch diff.status {
        case .added: return .blue
        case .modified: return .yellow
        case .deleted: return .red
        case .none: return .secondary.opacity(0.3)
        }
    }

    private var selectionFillColor: Color {
        guard isSelected else { return .clear }
        return Color.accentColor.opacity(isMultiSelected ? 0.24 : 0.14)
    }

    private var selectionStrokeColor: Color {
        guard isSelected else { return .clear }
        return Color.accentColor.opacity(isMultiSelected ? 0.95 : 0.75)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if diff.status != .none {
                Text(statusLabel).font(.system(size: 9, weight: .bold)).foregroundColor(statusStrokeColor).padding(.horizontal, 6).padding(.vertical, 2).background(statusStrokeColor.opacity(0.1)).cornerRadius(4).padding([.top, .leading], 8)
            }
            Text(diff.snapshot.content.isEmpty ? "내용 없음" : diff.snapshot.content).font(.custom("SansMonoCJKFinalDraft", size: fontSize)).lineSpacing(1.4).padding(12).frame(maxWidth: .infinity, alignment: .leading).strikethrough(diff.status == .deleted).opacity(diff.status == .deleted ? 0.6 : 1.0)
        }
        .background(statusColor)
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(statusStrokeColor, lineWidth: diff.status == .none ? 1 : 2))
        .overlay(RoundedRectangle(cornerRadius: 4).fill(selectionFillColor))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(selectionStrokeColor, lineWidth: isSelected ? (isMultiSelected ? 2 : 1) : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("카드 복사") { onCopyCards() }
            Button("내용 복사") { onCopyContents() }
        }
    }

    private var statusLabel: String { switch diff.status { case .added: return "NEW"; case .modified: return "EDITED"; case .deleted: return "삭제됨"; case .none: return "" } }
}

// MARK: - 포커스 모드 카드 에디터

struct FocusModeCardEditor: View {
    @ObservedObject var card: SceneCard
    let isActive: Bool
    let showsEditor: Bool
    @ObservedObject var layoutCoordinator: FocusModeLayoutCoordinator
    let cardWidth: CGFloat
    let fontSize: Double
    let appearance: String
    let horizontalInset: CGFloat
    @FocusState.Binding var focusModeEditorCardID: UUID?
    let onActivate: (CGPoint?) -> Void
    let onContentChange: (String, String) -> Void

    @AppStorage("focusModeLineSpacingValueTemp") private var focusModeLineSpacingValue: Double = 4.5
    static let verticalInset: CGFloat = 40
    private var verticalInset: CGFloat { Self.verticalInset }
    private var shellHeight: CGFloat {
        layoutCoordinator.resolvedCardHeight(
            for: card,
            cardWidth: cardWidth,
            fontSize: fontSize,
            lineSpacing: focusModeLineSpacingValue,
            verticalInset: verticalInset,
            liveEditorCardID: showsEditor ? card.id : nil
        )
    }
    private var textEditorBodyHeight: CGFloat {
        max(1, shellHeight - (verticalInset * 2))
    }
    private var focusModeFontSize: CGFloat { CGFloat(fontSize * 1.2) }
    private var focusModeLineSpacing: CGFloat { CGFloat(focusModeLineSpacingValue) }
    private var displayText: String {
        normalizedSharedMeasurementText(card.content)
    }

    private var focusModeTextBinding: Binding<String> {
        Binding(
            get: { card.content },
            set: { newValue in
                let oldValue = card.content
                guard oldValue != newValue else { return }
                card.content = newValue
                onContentChange(oldValue, newValue)
            }
        )
    }

    var body: some View {
        Group {
            if showsEditor {
                focusModeCardContent
            } else {
                focusModeCardContent
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                onActivate(value.location)
                            }
                    )
                    .onTapGesture {
                        onActivate(nil)
                    }
            }
        }
    }

    @ViewBuilder
    private var focusModeCardContent: some View {
        ZStack(alignment: .topLeading) {
            if showsEditor {
                FocusModeEditableTextRenderer(
                    text: focusModeTextBinding,
                    cardID: card.id,
                    layoutCoordinator: layoutCoordinator,
                    textWidth: FocusModeLayoutMetrics.resolvedTextWidth(for: cardWidth),
                    bodyHeight: textEditorBodyHeight,
                    fontSize: focusModeFontSize,
                    lineSpacing: focusModeLineSpacing,
                    appearance: appearance,
                    isFocused: showsEditor
                )
                .frame(height: textEditorBodyHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, horizontalInset)
                .padding(.top, verticalInset)
                .padding(.bottom, verticalInset)
            } else {
                FocusModeReadOnlyTextRenderer(
                    text: displayText,
                    textWidth: FocusModeLayoutMetrics.resolvedTextWidth(for: cardWidth),
                    bodyHeight: textEditorBodyHeight,
                    fontSize: focusModeFontSize,
                    lineSpacing: focusModeLineSpacing,
                    appearance: appearance
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, horizontalInset)
                .padding(.top, verticalInset)
                .padding(.bottom, verticalInset)
                .allowsHitTesting(false)
            }
        }
        .frame(width: cardWidth, alignment: .topLeading)
        .frame(height: shellHeight, alignment: .topLeading)
    }

}

// MARK: - 메인 카드 아이템

struct CardItem: View {
    private enum InlineInsertZoneEdge {
        case top
        case bottom
        case trailing
    }

    @ObservedObject var card: SceneCard
    let renderSettings: MainCardRenderSettings
    let isActive, isSelected, isMultiSelected, isArchived, isAncestor, isDescendant, isEditing: Bool
    let preferredTextMeasureWidth: CGFloat
    let forceNamedSnapshotNoteStyle: Bool
    let forceCustomColorVisibility: Bool
    var onInsertSiblingAbove: (() -> Void)? = nil
    var onInsertSiblingBelow: (() -> Void)? = nil
    var onAddChildCard: (() -> Void)? = nil
    var onDropBefore: (([NSItemProvider], Bool) -> Void)? = nil
    var onDropAfter: (([NSItemProvider], Bool) -> Void)? = nil
    var onDropOnto: (([NSItemProvider], Bool) -> Void)? = nil
    var onSelect, onDoubleClick, onEndEdit: () -> Void
    var onSelectAtLocation: ((CGPoint) -> Void)? = nil
    var onContentChange: ((String, String) -> Void)? = nil
    var onColorChange: ((String?) -> Void)? = nil
    var onReferenceCard: (() -> Void)? = nil
    var onCreateUpperCardFromSelection: (() -> Void)? = nil
    var onSummarizeChildren: (() -> Void)? = nil
    var onAIElaborate: (() -> Void)? = nil
    var onAINextScene: (() -> Void)? = nil
    var onAIAlternative: (() -> Void)? = nil
    var onAISummarizeCurrent: (() -> Void)? = nil
    var aiPlotActionsEnabled: Bool = false
    var onApplyAICandidate: (() -> Void)? = nil
    var isSummarizingChildren: Bool = false
    var isAIBusy: Bool = false
    var onDelete: (() -> Void)? = nil
    var onHardDelete: (() -> Void)? = nil
    var onTranscriptionMode: (() -> Void)? = nil
    var isTranscriptionBusy: Bool = false
    var showsEmptyCardBulkDeleteMenuOnly: Bool = false
    var onBulkDeleteEmptyCards: (() -> Void)? = nil
    var isCloneLinked: Bool = false
    var hasLinkedCards: Bool = false
    var isLinkedCard: Bool = false
    var onDisconnectLinkedCard: (() -> Void)? = nil
    var onCloneCard: (() -> Void)? = nil
    var clonePeerDestinations: [ClonePeerMenuDestination] = []
    var onNavigateToClonePeer: ((UUID) -> Void)? = nil
    @State private var mainEditingMeasuredBodyHeight: CGFloat = 0
    @State private var mainEditingMeasureWorkItem: DispatchWorkItem? = nil
    @State private var mainEditingMeasureLastAt: Date = .distantPast
    @State private var isTopInsertZoneHovered: Bool = false
    @State private var isBottomInsertZoneHovered: Bool = false
    @State private var isTrailingInsertZoneHovered: Bool = false
    @State private var isTopInsertZoneDropTargeted: Bool = false
    @State private var isBottomInsertZoneDropTargeted: Bool = false
    @State private var isTrailingInsertZoneDropTargeted: Bool = false
    @State private var isBodyDropTargeted: Bool = false
    @FocusState private var editorFocus: Bool
    private var fontSize: CGFloat { renderSettings.fontSize }
    private var appearance: String { renderSettings.appearance }
    private var cardBaseColorHex: String { renderSettings.cardBaseColorHex }
    private var cardActiveColorHex: String { renderSettings.cardActiveColorHex }
    private var cardRelatedColorHex: String { renderSettings.cardRelatedColorHex }
    private var darkCardBaseColorHex: String { renderSettings.darkCardBaseColorHex }
    private var darkCardActiveColorHex: String { renderSettings.darkCardActiveColorHex }
    private var darkCardRelatedColorHex: String { renderSettings.darkCardRelatedColorHex }
    private var mainCardLineSpacing: CGFloat { renderSettings.lineSpacing }
    private let mainCardContentPadding: CGFloat = MainEditorLayoutMetrics.mainCardContentPadding
    private let mainEditorVerticalPadding: CGFloat = 24
    private let mainEditorLineFragmentPadding: CGFloat = MainEditorLayoutMetrics.mainEditorLineFragmentPadding
    private let mainEditingMeasureMinInterval: TimeInterval = 0.033
    private let mainEditingMeasureUpdateThreshold: CGFloat = 0.5
    private var mainEditorHorizontalPadding: CGFloat {
        MainEditorLayoutMetrics.mainEditorHorizontalPadding
    }

    private var usesDarkPalette: Bool {
        if appearance == "dark" { return true }
        if appearance == "light" { return false }
        if let best = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
            return best == .darkAqua
        }
        return true
    }

    private var isCandidateVisualCard: Bool {
        (forceCustomColorVisibility || card.isAICandidate) && card.colorHex != nil
    }
    private var shouldShowChildRightEdge: Bool {
        !isArchived && !card.children.isEmpty
    }
    private var hasAIMenuActions: Bool {
        onAIElaborate != nil
            || onAINextScene != nil
            || onAIAlternative != nil
            || onAISummarizeCurrent != nil
            || onSummarizeChildren != nil
    }
    private var resolvedCardRGB: (r: Double, g: Double, b: Double) {
        if forceNamedSnapshotNoteStyle {
            return resolvedNamedSnapshotNoteRGB()
        }
        let base = resolvedBaseRGB()
        if isMultiSelected {
            let overlay = usesDarkPalette ? (r: 0.42, g: 0.56, b: 0.78) : (r: 0.70, g: 0.83, b: 0.98)
            let amount = usesDarkPalette ? 0.58 : 0.62
            return mix(base: base, overlay: overlay, amount: amount)
        }
        if isCandidateVisualCard {
            return base
        }
        let active = resolvedActiveRGB()
        let related = resolvedRelatedRGB()
        if isActive {
            return active
        }
        if isAncestor || isDescendant {
            return related
        }
        return base
    }

    private var childRightEdgeColor: Color {
        let amount = usesDarkPalette ? 0.34 : 0.24
        let rgb = mix(base: resolvedCardRGB, overlay: (0, 0, 0), amount: amount)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private var insertZoneHighlightColor: Color {
        usesDarkPalette ? Color.white.opacity(0.22) : Color.black.opacity(0.18)
    }

    private var insertIndicatorColor: Color {
        usesDarkPalette ? Color.white.opacity(0.92) : Color.black.opacity(0.72)
    }

    private var shouldShowInlineInsertControls: Bool {
        !isArchived && !isEditing
    }

    private var bodyDropTrailingInset: CGFloat {
        (shouldShowInlineInsertControls && onAddChildCard != nil) ? trailingInsertZoneWidth : 0
    }

    private var baseBackgroundColor: Color {
        if isArchived {
            return appearance == "light" ? Color.gray.opacity(0.25) : Color.gray.opacity(0.35)
        }
        if isMultiSelected {
            let base = resolvedBaseRGB()
            let overlay = usesDarkPalette ? (r: 0.42, g: 0.56, b: 0.78) : (r: 0.70, g: 0.83, b: 0.98)
            let amount = usesDarkPalette ? 0.58 : 0.62
            let rgb = mix(base: base, overlay: overlay, amount: amount)
            return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
        }
        let rgb = resolvedBaseRGB()
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private var relatedBackgroundColor: Color {
        let rgb = resolvedRelatedRGB()
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private var activeBackgroundColor: Color {
        let rgb = resolvedActiveRGB()
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private var usesFocusFadeTint: Bool {
        !isArchived && !isMultiSelected && !isCandidateVisualCard
    }

    private var relatedTintOpacity: Double {
        guard usesFocusFadeTint else { return 0 }
        return (!isActive && (isAncestor || isDescendant)) ? 1 : 0
    }

    private var activeTintOpacity: Double {
        guard usesFocusFadeTint else { return 0 }
        return isActive ? 1 : 0
    }

    private var cardBorderColor: Color {
        if usesDarkPalette {
            return Color.white.opacity(0.12)
        }
        return Color.black.opacity(0.10)
    }

    private let horizontalInsertZoneHeight: CGFloat = 27
    private let horizontalInsertZoneWidth: CGFloat = 60
    private let trailingInsertZoneWidth: CGFloat = 30

    private func insertZoneHighlightFill(for edge: InlineInsertZoneEdge) -> AnyShapeStyle {
        let strong = usesDarkPalette ? Color.white.opacity(0.32) : Color.black.opacity(0.24)
        let soft = usesDarkPalette ? Color.white.opacity(0.16) : Color.black.opacity(0.10)

        switch edge {
        case .top:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [strong, soft, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .bottom:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [strong, soft, .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
        case .trailing:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [strong, soft, .clear],
                    startPoint: .trailing,
                    endPoint: .leading
                )
            )
        }
    }

    private var mainEditingTextMeasureWidth: CGFloat {
        max(1, preferredTextMeasureWidth)
    }

    private var resolvedMainEditingBodyHeight: CGFloat {
        if mainEditingMeasuredBodyHeight > 1 {
            return mainEditingMeasuredBodyHeight
        }
        return measureMainEditorBodyHeight(text: card.content, width: mainEditingTextMeasureWidth)
    }

    private var mainEditorTextBinding: Binding<String> {
        Binding(
            get: { card.content },
            set: { newValue in
                let oldValue = card.content
                guard oldValue != newValue else { return }
                card.content = newValue
                onContentChange?(oldValue, newValue)
                scheduleMainEditingMeasuredBodyHeightRefresh()
            }
        )
    }

    private func liveMainResponderBodyHeight() -> CGFloat? {
        guard isEditing else { return nil }
        guard editorFocus else { return nil }
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return nil }
        guard textView.string == card.content else { return nil }
        return sharedLiveTextViewBodyHeight(textView)
    }

    private func measureMainEditorBodyHeight(text: String, width: CGFloat) -> CGFloat {
        sharedMeasuredTextBodyHeight(
            text: text,
            fontSize: CGFloat(fontSize),
            lineSpacing: mainCardLineSpacing,
            width: width,
            lineFragmentPadding: mainEditorLineFragmentPadding,
            safetyInset: 0
        )
    }

    private func refreshMainEditingMeasuredBodyHeight() {
        let measured = liveMainResponderBodyHeight()
            ?? measureMainEditorBodyHeight(text: card.content, width: mainEditingTextMeasureWidth)
        mainEditingMeasureLastAt = Date()
        let previous = mainEditingMeasuredBodyHeight
        if abs(previous - measured) > mainEditingMeasureUpdateThreshold {
            mainEditingMeasuredBodyHeight = measured
        }
    }

    private func scheduleMainEditingMeasuredBodyHeightRefresh(immediate: Bool = false) {
        if immediate {
            mainEditingMeasureWorkItem?.cancel()
            mainEditingMeasureWorkItem = nil
            refreshMainEditingMeasuredBodyHeight()
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(mainEditingMeasureLastAt)
        let delay = max(0, mainEditingMeasureMinInterval - elapsed)
        guard delay > 0.001 else {
            refreshMainEditingMeasuredBodyHeight()
            return
        }

        mainEditingMeasureWorkItem?.cancel()
        let work = DispatchWorkItem {
            mainEditingMeasureWorkItem = nil
            refreshMainEditingMeasuredBodyHeight()
        }
        mainEditingMeasureWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    @ViewBuilder
    private var cardContextMenuContent: some View {
        if let onDisconnectLinkedCard {
            Button("연결 끊기", role: .destructive) { onDisconnectLinkedCard() }
            Divider()
        }
        if showsEmptyCardBulkDeleteMenuOnly {
            if hasAIMenuActions {
                Menu("AI") {
                    Button("구체화") { onAIElaborate?() }
                        .disabled(onAIElaborate == nil || !aiPlotActionsEnabled || isAIBusy)
                    Button("다음 장면") { onAINextScene?() }
                        .disabled(onAINextScene == nil || !aiPlotActionsEnabled || isAIBusy)
                    Button("대안") { onAIAlternative?() }
                        .disabled(onAIAlternative == nil || !aiPlotActionsEnabled || isAIBusy)
                    Divider()
                    Button("선택 카드 요약") { onAISummarizeCurrent?() }
                        .disabled(onAISummarizeCurrent == nil || isAIBusy)
                    Button("자식 카드 요약") { onSummarizeChildren?() }
                        .disabled(onSummarizeChildren == nil || isAIBusy)
                }
                if onBulkDeleteEmptyCards != nil {
                    Divider()
                }
            }
            if let onTranscriptionMode {
                Button("전사 모드") { onTranscriptionMode() }
                    .disabled(isTranscriptionBusy || isAIBusy)
                if onBulkDeleteEmptyCards != nil {
                    Divider()
                }
            }
            if let onBulkDeleteEmptyCards {
                Button("내용 없음 카드 전체 삭제", role: .destructive) { onBulkDeleteEmptyCards() }
            }
        } else {
            if let onCloneCard {
                Button("클론 카드") { onCloneCard() }
                Divider()
            }
            if let onNavigateToClonePeer, !clonePeerDestinations.isEmpty {
                Menu("다른 클론으로 이동") {
                    ForEach(clonePeerDestinations) { destination in
                        Button(destination.title) { onNavigateToClonePeer(destination.id) }
                    }
                }
                Divider()
            }
            if let onReferenceCard {
                Button("레퍼런스 카드로") { onReferenceCard() }
                Divider()
            }
            if let onCreateUpperCardFromSelection {
                Button("새 상위 카드 만들기") { onCreateUpperCardFromSelection() }
                Divider()
            }
            if hasAIMenuActions {
                Menu("AI") {
                    Button("구체화") { onAIElaborate?() }
                        .disabled(onAIElaborate == nil || !aiPlotActionsEnabled || isAIBusy)
                    Button("다음 장면") { onAINextScene?() }
                        .disabled(onAINextScene == nil || !aiPlotActionsEnabled || isAIBusy)
                    Button("대안") { onAIAlternative?() }
                        .disabled(onAIAlternative == nil || !aiPlotActionsEnabled || isAIBusy)
                    Divider()
                    Button("선택 카드 요약") { onAISummarizeCurrent?() }
                        .disabled(onAISummarizeCurrent == nil || isAIBusy)
                    Button("자식 카드 요약") { onSummarizeChildren?() }
                        .disabled(onSummarizeChildren == nil || isAIBusy)
                }
                Divider()
            }
            if let onDelete {
                Button("삭제", role: .destructive) { onDelete() }
            }
            if onDelete != nil {
                Divider()
            }
            if let onColorChange {
                Menu("카드 색") {
                    Button("기본") { onColorChange(nil) }
                    Divider()
                    Button("연보라") { onColorChange("E7D5FF") }
                    Button("하늘") { onColorChange("CFE8FF") }
                    Button("민트") { onColorChange("CFF2E8") }
                    Button("살구") { onColorChange("FFE1CC") }
                    Button("연노랑") { onColorChange("FFF3C4") }
                }
            }
            if let onTranscriptionMode {
                Divider()
                Button("전사 모드") { onTranscriptionMode() }
                    .disabled(isTranscriptionBusy || isAIBusy)
            }
            if let onHardDelete {
                Divider()
                Button("완전 삭제 (모든 곳)", role: .destructive) { onHardDelete() }
            }
        }
    }

    @ViewBuilder
    private var cardSurface: some View {
        ZStack(alignment: .topLeading) {
            baseBackgroundColor

            if usesFocusFadeTint {
                relatedBackgroundColor
                    .opacity(relatedTintOpacity)

                activeBackgroundColor
                    .opacity(activeTintOpacity)
            }

            ZStack(alignment: .topLeading) {
                if !isEditing {
                    Text(card.content.isEmpty ? "내용 없음" : card.content)
                        .font(.custom("SansMonoCJKFinalDraft", size: fontSize))
                        .lineSpacing(mainCardLineSpacing)
                        .foregroundStyle(card.content.isEmpty ? (appearance == "light" ? .black.opacity(0.4) : .white.opacity(0.4)) : (appearance == "light" ? .black : .white))
                        .padding(mainCardContentPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isEditing {
                    TextEditor(text: mainEditorTextBinding)
                        .font(.custom("SansMonoCJKFinalDraft", size: fontSize))
                        .lineSpacing(mainCardLineSpacing)
                        .scrollContentBackground(.hidden)
                        .scrollDisabled(true)
                        .scrollIndicators(.never)
                        .frame(height: resolvedMainEditingBodyHeight, alignment: .topLeading)
                        .padding(.horizontal, mainEditorHorizontalPadding)
                        .padding(.vertical, mainEditorVerticalPadding)
                        .foregroundStyle(appearance == "light" ? .black : .white)
                        .focused($editorFocus)
                        .onAppear {
                            scheduleMainEditingMeasuredBodyHeightRefresh(immediate: true)
                            DispatchQueue.main.async {
                                let alreadyFocusedHere: Bool = {
                                    guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
                                    return textView.string == card.content
                                }()
                                if !alreadyFocusedHere {
                                    editorFocus = true
                                }
                                scheduleMainEditingMeasuredBodyHeightRefresh(immediate: true)
                            }
                        }
                        .onDisappear {
                            mainEditingMeasureWorkItem?.cancel()
                            mainEditingMeasureWorkItem = nil
                        }
                        .onChange(of: fontSize) { _, _ in
                            scheduleMainEditingMeasuredBodyHeightRefresh(immediate: true)
                        }
                        .onChange(of: mainCardLineSpacing) { _, _ in
                            scheduleMainEditingMeasuredBodyHeightRefresh(immediate: true)
                        }
                }

                if isCandidateVisualCard {
                    VStack {
                        HStack(spacing: 6) {
                            Spacer()
                            Text("AI 후보")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(appearance == "light" ? Color.black.opacity(0.12) : Color.white.opacity(0.20))
                                .clipShape(Capsule())
                            if let onApplyAICandidate {
                                Button("선택") {
                                    onApplyAICandidate()
                                }
                                .font(.system(size: 9, weight: .semibold))
                                .buttonStyle(.plain)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(appearance == "light" ? Color.accentColor.opacity(0.22) : Color.accentColor.opacity(0.32))
                                .clipShape(Capsule())
                                .disabled(isAIBusy)
                            }
                        }
                        Spacer()
                    }
                    .padding(8)
                }
            }
        }
        .overlay {
            if let onDropOnto {
                cardBodyDropZone(onDrop: onDropOnto)
            }
        }
        .overlay(alignment: .trailing) {
            ZStack(alignment: .trailing) {
                if shouldShowInlineInsertControls, let onAddChildCard {
                    inlineInsertZone(
                        isHovered: $isTrailingInsertZoneHovered,
                        isDropTargeted: $isTrailingInsertZoneDropTargeted,
                        edge: .trailing,
                        axis: .vertical,
                        action: onAddChildCard,
                        onDrop: nil
                    )
                }
                if shouldShowChildRightEdge {
                    Rectangle()
                        .fill(childRightEdgeColor)
                        .frame(width: 4)
                        .allowsHitTesting(false)
                }
            }
        }
        .overlay(alignment: .top) {
            if shouldShowInlineInsertControls, let onInsertSiblingAbove {
                inlineInsertZone(
                    isHovered: $isTopInsertZoneHovered,
                    isDropTargeted: $isTopInsertZoneDropTargeted,
                    edge: .top,
                    axis: .horizontal,
                    action: onInsertSiblingAbove,
                    onDrop: onDropBefore
                )
            }
        }
        .overlay(alignment: .bottom) {
            if shouldShowInlineInsertControls, let onInsertSiblingBelow {
                inlineInsertZone(
                    isHovered: $isBottomInsertZoneHovered,
                    isDropTargeted: $isBottomInsertZoneDropTargeted,
                    edge: .bottom,
                    axis: .horizontal,
                    action: onInsertSiblingBelow,
                    onDrop: onDropAfter
                )
            }
        }
        .overlay {
            Rectangle()
                .stroke(cardBorderColor, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 3) {
                    if hasLinkedCards {
                        Rectangle()
                            .fill(appearance == "light" ? Color.black.opacity(0.48) : Color.white.opacity(0.85))
                            .frame(width: 8, height: 8)
                            .allowsHitTesting(false)
                    }
                    if isLinkedCard {
                        Path { path in
                            // Right-angle isosceles triangle with the right angle at top-right.
                            path.move(to: CGPoint(x: 0, y: 0))
                            path.addLine(to: CGPoint(x: 8, y: 0))
                            path.addLine(to: CGPoint(x: 8, y: 8))
                            path.closeSubpath()
                        }
                        .fill(appearance == "light" ? Color.black.opacity(0.48) : Color.white.opacity(0.85))
                        .frame(width: 8, height: 8)
                        .allowsHitTesting(false)
                    }
                }
                if isSummarizingChildren {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                        .background(appearance == "light" ? Color.white.opacity(0.92) : Color.black.opacity(0.42))
                        .clipShape(Capsule())
                        .padding(.top, 6)
                        .padding(.trailing, 8)
                        .allowsHitTesting(false)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if isCloneLinked {
                Rectangle()
                    .fill(appearance == "light" ? Color.black.opacity(0.48) : Color.white.opacity(0.85))
                    .frame(width: 8, height: 8)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: isEditing) { _, newValue in
            if newValue {
                scheduleMainEditingMeasuredBodyHeightRefresh(immediate: true)
            } else {
                mainEditingMeasureWorkItem?.cancel()
                mainEditingMeasureWorkItem = nil
            }
        }
        .onDisappear {
            mainEditingMeasureWorkItem?.cancel()
            mainEditingMeasureWorkItem = nil
        }
    }

    var body: some View {
        Group {
            if isEditing {
                cardSurface
            } else {
                cardSurface
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                                let isPlainClick =
                                    !flags.contains(.command) &&
                                    !flags.contains(.shift) &&
                                    !flags.contains(.option) &&
                                    !flags.contains(.control)
                                let shouldRouteClickToCaret =
                                    isPlainClick &&
                                    isActive &&
                                    isSelected &&
                                    !isMultiSelected &&
                                    onSelectAtLocation != nil
                                if shouldRouteClickToCaret, let onSelectAtLocation {
                                    onSelectAtLocation(value.location)
                                } else {
                                    onSelect()
                                }
                            }
                    )
                    .simultaneousGesture(TapGesture(count: 2).onEnded { onDoubleClick() })
            }
        }
        .contextMenu {
            cardContextMenuContent
        }
    }

    private func resolvedBaseRGB() -> (r: Double, g: Double, b: Double) {
        let fallbackLight: (Double, Double, Double) = (1.0, 1.0, 1.0)
        let fallbackDark: (Double, Double, Double) = (0.10, 0.13, 0.16)
        if let custom = card.colorHex, let customRGB = rgbFromHex(custom) {
            if forceCustomColorVisibility || card.isAICandidate {
                if !usesDarkPalette { return customRGB }
                return mix(base: customRGB, overlay: (0, 0, 0), amount: 0.18)
            }
            if !usesDarkPalette { return customRGB }
            return mix(base: customRGB, overlay: (0, 0, 0), amount: 0.65)
        }
        let hex = usesDarkPalette ? darkCardBaseColorHex : cardBaseColorHex
        guard let rgb = rgbFromHex(hex) else {
            return usesDarkPalette ? fallbackDark : fallbackLight
        }
        return rgb
    }

    private func rgbFromHex(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        guard let rgb = parseHexRGB(hex) else { return nil }
        return (r: rgb.0, g: rgb.1, b: rgb.2)
    }

    private func mix(base: (r: Double, g: Double, b: Double), overlay: (r: Double, g: Double, b: Double), amount: Double) -> (r: Double, g: Double, b: Double) {
        let r = base.r * (1.0 - amount) + overlay.r * amount
        let g = base.g * (1.0 - amount) + overlay.g * amount
        let b = base.b * (1.0 - amount) + overlay.b * amount
        return (r, g, b)
    }

    private func resolvedNamedSnapshotNoteRGB() -> (r: Double, g: Double, b: Double) {
        if appearance == "light" {
            return (0.83, 0.94, 0.84)
        }
        return (0.17, 0.30, 0.19)
    }

    @ViewBuilder
    private func inlineInsertZone(
        isHovered: Binding<Bool>,
        isDropTargeted: Binding<Bool>,
        edge: InlineInsertZoneEdge,
        axis: Axis,
        action: @escaping () -> Void,
        onDrop: (([NSItemProvider], Bool) -> Void)?
    ) -> some View {
        if let onDrop {
            inlineInsertZoneContent(
                isHovered: isHovered,
                isDropTargeted: isDropTargeted,
                edge: edge,
                axis: axis,
                action: action
            )
            .onDrop(
                of: [.text],
                delegate: CardActionZoneDropDelegate(
                    isTargeted: isDropTargeted,
                    performAction: onDrop
                )
            )
        } else {
            inlineInsertZoneContent(
                isHovered: isHovered,
                isDropTargeted: isDropTargeted,
                edge: edge,
                axis: axis,
                action: action
            )
        }
    }

    private func inlineInsertZoneContent(
        isHovered: Binding<Bool>,
        isDropTargeted: Binding<Bool>,
        edge: InlineInsertZoneEdge,
        axis: Axis,
        action: @escaping () -> Void
    ) -> some View {
        let isHighlighted = isHovered.wrappedValue || isDropTargeted.wrappedValue
        return ZStack {
            Rectangle()
                .fill(isHighlighted ? insertZoneHighlightFill(for: edge) : AnyShapeStyle(Color.clear))

            if isHighlighted {
                Text("+")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(insertIndicatorColor)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered.wrappedValue = hovering
            }
        }
        .onTapGesture {
            action()
        }
        .frame(
            width: axis == .vertical ? trailingInsertZoneWidth : horizontalInsertZoneWidth,
            height: axis == .horizontal ? horizontalInsertZoneHeight : nil
        )
        .frame(
            maxHeight: axis == .vertical ? .infinity : nil
        )
    }

    @ViewBuilder
    private func cardBodyDropZone(onDrop: @escaping ([NSItemProvider], Bool) -> Void) -> some View {
        GeometryReader { geometry in
            let bodyWidth = max(0, geometry.size.width - bodyDropTrailingInset)
            let bodyHeight = max(0, geometry.size.height - (horizontalInsertZoneHeight * 2))

            Rectangle()
                .fill(isBodyDropTargeted ? insertZoneHighlightColor : .clear)
                .frame(width: bodyWidth, height: bodyHeight, alignment: .topLeading)
                .offset(x: 0, y: horizontalInsertZoneHeight)
                .contentShape(Rectangle())
                .onDrop(
                    of: [.text],
                    delegate: CardActionZoneDropDelegate(
                        isTargeted: $isBodyDropTargeted,
                        performAction: onDrop
                    )
                )
        }
    }

    private func resolvedActiveRGB() -> (r: Double, g: Double, b: Double) {
        let fallbackLight: (Double, Double, Double) = (0.75, 0.84, 1.0)
        let fallbackDark: (Double, Double, Double) = (0.16, 0.23, 0.31)
        let hex = usesDarkPalette ? darkCardActiveColorHex : cardActiveColorHex
        guard let rgb = rgbFromHex(hex) else {
            return usesDarkPalette ? fallbackDark : fallbackLight
        }
        return rgb
    }

    private func resolvedRelatedRGB() -> (r: Double, g: Double, b: Double) {
        let fallbackLight: (Double, Double, Double) = (0.87, 0.92, 1.0)
        let fallbackDark: (Double, Double, Double) = (0.14, 0.18, 0.25)
        let hex = usesDarkPalette ? darkCardRelatedColorHex : cardRelatedColorHex
        guard let rgb = rgbFromHex(hex) else {
            return usesDarkPalette ? fallbackDark : fallbackLight
        }
        return rgb
    }
}

// MARK: - 드래그 앤 드롭 델리게이트 (카드 영역용)

private func isTrailingSiblingBlockDragActive() -> Bool {
    let tracker = MainCardDragSessionTracker.shared
    if tracker.isDragging {
        tracker.refreshCommandState()
        return tracker.isCommandPressed
    }
    return NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
}

private struct CardActionZoneDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let performAction: ([NSItemProvider], Bool) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        MainCardDragSessionTracker.shared.refreshCommandState()
        return DropProposal(operation: isTrailingSiblingBlockDragActive() ? .copy : .move)
    }

    func dropEntered(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.15)) { isTargeted = true }
    }

    func dropExited(info: DropInfo) {
        if isTargeted {
            withAnimation(.easeInOut(duration: 0.15)) { isTargeted = false }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.text])
        guard !providers.isEmpty else { return false }
        performAction(providers, isTrailingSiblingBlockDragActive())
        isTargeted = false
        MainCardDragSessionTracker.shared.end()
        return true
    }
}

```

--------------------------------
File: WriterCardManagement.swift
--------------------------------

```swift
import SwiftUI
import AppKit
import QuartzCore
import UniformTypeIdentifiers

extension ScenarioWriterView {

    // MARK: - Canvas Position Restore

    private var mainCanvasRestoreRetryDelays: [TimeInterval] {
        [0.0, 0.05, 0.18]
    }

    private func enqueueMainCanvasRestoreRequest(
        targetID: UUID?,
        visibleLevel: Int? = nil,
        forceSemantic: Bool = false,
        reason: MainCanvasViewState.RestoreRequest.Reason = .generic
    ) {
        guard !showFocusMode else { return }
        guard let targetID else { return }
        DispatchQueue.main.async {
            guard !showFocusMode else { return }
            scheduleMainCanvasRestoreRequest(
                targetCardID: targetID,
                visibleLevel: visibleLevel,
                forceSemantic: forceSemantic,
                reason: reason
            )
        }
    }

    func scheduleMainCanvasRestoreRetries(_ action: @escaping () -> Void) {
        for delay in mainCanvasRestoreRetryDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                action()
            }
        }
    }

    func restoreMainCanvasPositionIfNeeded(proxy: ScrollViewProxy, availableWidth: CGFloat) {
        guard !showFocusMode else { return }
        guard !isPreviewingHistory else { return }
        guard let request = pendingMainCanvasRestoreRequest else { return }

        if let visibleLevel = request.visibleLevel {
            lastScrolledLevel = max(0, visibleLevel)
            let restored = performMainCanvasHorizontalScroll(
                level: lastScrolledLevel,
                availableWidth: availableWidth,
                animated: false
            )
            guard restored else {
                return
            }
            pendingMainCanvasRestoreRequest = nil
            return
        }

        scrollToColumnIfNeeded(
            targetCardID: request.targetCardID,
            proxy: proxy,
            availableWidth: availableWidth,
            force: request.forceSemantic,
            animated: false
        )
        pendingMainCanvasRestoreRequest = nil
    }

    func requestMainCanvasRestoreForHistoryToggle() {
        enqueueMainCanvasRestoreRequest(
            targetID: activeCardID ?? lastActiveCardID ?? scenario.rootCards.first?.id
        )
    }

    func requestMainCanvasRestoreForFocusExit(using snapshot: FocusModeWorkspaceSnapshot?) {
        let targetID = activeCardID ?? editingCardID ?? lastActiveCardID ?? scenario.rootCards.first?.id
        let visibleLevel = snapshot?.visibleMainCanvasLevel
        enqueueMainCanvasRestoreRequest(
            targetID: targetID,
            visibleLevel: visibleLevel,
            forceSemantic: true,
            reason: MainCanvasViewState.RestoreRequest.Reason.focusExit
        )
    }

    func requestMainCanvasViewportRestoreForFocusExit(using snapshot: FocusModeWorkspaceSnapshot?) {
        guard !showFocusMode else { return }
        let storedOffsets = snapshot?.mainColumnViewportOffsets ?? mainColumnViewportOffsetByKey
        guard !storedOffsets.isEmpty else { return }
        scheduleMainCanvasRestoreRetries {
            guard !showFocusMode else { return }
            applyStoredMainColumnViewportOffsets(storedOffsets)
        }
    }

    func captureFocusModeEntryWorkspaceSnapshot() {
        guard !showFocusMode else { return }
        let visibleLevel: Int?
        if let visibleLevel = resolvedVisibleMainCanvasLevelFromCurrentScrollPosition() {
            lastScrolledLevel = visibleLevel
            focusModeEntryWorkspaceSnapshot = FocusModeWorkspaceSnapshot(
                activeCardID: activeCardID,
                editingCardID: editingCardID,
                selectedCardIDs: selectedCardIDs,
                visibleMainCanvasLevel: visibleLevel,
                mainCanvasHorizontalOffset: mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalOffset().map { max(0, $0) },
                mainColumnViewportOffsets: mainColumnViewportOffsetByKey,
                capturedAt: Date()
            )
            return
        } else if let activeID = activeCardID, let activeLevel = displayedMainCardLocationByID(activeID)?.level {
            switch mainCanvasHorizontalScrollMode {
            case .oneStep:
                visibleLevel = activeLevel
            case .twoStep:
                visibleLevel = max(0, activeLevel - 1)
            }
        } else if lastScrolledLevel >= 0 {
            visibleLevel = lastScrolledLevel
        } else {
            visibleLevel = nil
        }
        if let visibleLevel {
            lastScrolledLevel = visibleLevel
        }
        focusModeEntryWorkspaceSnapshot = FocusModeWorkspaceSnapshot(
            activeCardID: activeCardID,
            editingCardID: editingCardID,
            selectedCardIDs: selectedCardIDs,
            visibleMainCanvasLevel: visibleLevel,
            mainCanvasHorizontalOffset: mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalOffset().map { max(0, $0) },
            mainColumnViewportOffsets: mainColumnViewportOffsetByKey,
            capturedAt: Date()
        )
    }

    func canReuseRetainedMainCanvasShellForFocusExit(using snapshot: FocusModeWorkspaceSnapshot?) -> Bool {
        guard !showFocusMode else { return false }
        guard mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalScrollView() != nil else { return false }
        guard let snapshot else { return true }
        let requiredViewportKeys = snapshot.mainColumnViewportOffsets.compactMap { entry in
            entry.value > 1 ? entry.key : nil
        }
        for viewportKey in requiredViewportKeys {
            guard mainCanvasScrollCoordinator.scrollView(for: viewportKey) != nil else { return false }
        }
        return true
    }

    func finalizeRetainedMainCanvasShellForFocusExitReuse() {
        pendingMainCanvasRestoreRequest = nil
        cancelAllPendingMainColumnFocusWork()
    }

    // MARK: - Main Vertical Scroll Authority

    @discardableResult
    func beginMainVerticalScrollAuthority(
        viewportKey: String,
        kind: MainVerticalScrollAuthorityKind,
        targetCardID: UUID?
    ) -> MainVerticalScrollAuthority {
        mainVerticalScrollAuthoritySequence &+= 1
        let authority = MainVerticalScrollAuthority(
            id: mainVerticalScrollAuthoritySequence,
            kind: kind,
            targetCardID: targetCardID
        )
        mainVerticalScrollAuthorityByViewportKey[viewportKey] = authority
        bounceDebugLog(
            "beginMainVerticalScrollAuthority key=\(viewportKey) kind=\(kind.rawValue) target=\(debugCardIDString(targetCardID)) id=\(authority.id)"
        )
        return authority
    }

    func isMainVerticalScrollAuthorityCurrent(
        _ authority: MainVerticalScrollAuthority?,
        viewportKey: String
    ) -> Bool {
        guard let authority else { return true }
        return mainVerticalScrollAuthorityByViewportKey[viewportKey] == authority
    }

    func resolvedMainColumnViewportKey(forCardID cardID: UUID) -> String? {
        guard let level = displayedMainCardLocationByID(cardID)?.level else { return nil }
        return mainColumnViewportStorageKey(level: level)
    }

    func resolvedVisibleMainCanvasLevelFromCurrentScrollPosition() -> Int? {
        guard let scrollView = mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalScrollView() else { return nil }
        let visualLevelCount = max(1, resolvedDisplayedMainLevelsWithParents().count)
        let visibleRect = scrollView.documentVisibleRect
        let documentWidth = scrollView.documentView?.bounds.width ?? 0
        let availableWidth = max(1, documentWidth - (CGFloat(visualLevelCount) * columnWidth))
        let maxX = max(0, documentWidth - visibleRect.width)
        let currentX = scrollView.contentView.bounds.origin.x

        var bestLevel = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for level in 0..<visualLevelCount {
            let targetX = resolvedMainCanvasHorizontalTargetX(
                level: level,
                availableWidth: availableWidth,
                visibleWidth: visibleRect.width
            )
            let resolvedTargetX = CaretScrollCoordinator.resolvedHorizontalTargetX(
                visibleRect: visibleRect,
                targetX: targetX,
                minX: 0,
                maxX: maxX,
                snapToPixel: true
            )
            let distance = abs(resolvedTargetX - currentX)
            if distance < bestDistance {
                bestDistance = distance
                bestLevel = level
            }
        }
        return bestLevel
    }

    func restoreMainCanvasHorizontalViewport(to storedOffsetX: CGFloat) {
        guard !showFocusMode else { return }
        suppressHorizontalAutoScroll = true
        mainCanvasScrollCoordinator.scheduleMainCanvasHorizontalRestore(offsetX: storedOffsetX)
        scheduleMainCanvasRestoreRetries {
            guard !showFocusMode else { return }
            guard let scrollView = mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalScrollView() else { return }
            let visibleRect = scrollView.documentVisibleRect
            let documentWidth = scrollView.documentView?.bounds.width ?? 0
            let maxX = max(0, documentWidth - visibleRect.width)
            _ = CaretScrollCoordinator.applyHorizontalScrollIfNeeded(
                scrollView: scrollView,
                visibleRect: visibleRect,
                targetX: storedOffsetX,
                minX: 0,
                maxX: maxX,
                deadZone: 0.5,
                snapToPixel: true
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            suppressHorizontalAutoScroll = false
        }
    }

    func requestMainCanvasRestoreForZoomChange() {
        guard !showFocusMode else { return }
        guard !showHistoryBar else { return }
        enqueueMainCanvasRestoreRequest(
            targetID: activeCardID ?? editingCardID ?? lastActiveCardID ?? scenario.rootCards.first?.id
        )
    }

    func requestMainCanvasRestoreForHorizontalScrollModeChange() {
        guard !showFocusMode else { return }
        guard !showHistoryBar else { return }
        enqueueMainCanvasRestoreRequest(
            targetID: activeCardID ?? editingCardID ?? lastActiveCardID ?? scenario.rootCards.first?.id
        )
    }

    func cancelMainArrowNavigationSettle() {
        mainArrowNavigationSettleWorkItem?.cancel()
        mainArrowNavigationSettleWorkItem = nil
    }

    func scheduleMainArrowNavigationSettle() {
        cancelMainArrowNavigationSettle()
        let workItem = DispatchWorkItem {
            defer { mainArrowNavigationSettleWorkItem = nil }
            guard acceptsKeyboardInput else { return }
            guard !showFocusMode else { return }
            guard !isPreviewingHistory else { return }
            guard let activeID = activeCardID, findCard(by: activeID) != nil else { return }
            mainColumnLastFocusRequestByKey = [:]
            bounceDebugLog(
                "mainArrowNavigationSettle target=\(debugCardIDString(activeID)) " +
                "\(debugFocusStateSummary())"
            )
            _ = mainCanvasScrollCoordinator.publishIntent(
                kind: .settleRecovery,
                scope: .allColumns,
                targetCardID: activeID,
                expectedActiveCardID: activeID,
                animated: false,
                trigger: "navigationSettle"
            )
            mainNavigationSettleTick += 1
        }
        mainArrowNavigationSettleWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    @discardableResult
    func publishMainColumnNavigationIntent(
        kind: MainCanvasScrollCoordinator.NavigationIntentKind,
        scope: MainCanvasScrollCoordinator.NavigationIntentScope,
        targetCardID: UUID? = nil,
        expectedActiveCardID: UUID? = nil,
        animated: Bool,
        trigger: String
    ) -> MainCanvasScrollCoordinator.NavigationIntent {
        mainCanvasScrollCoordinator.publishIntent(
            kind: kind,
            scope: scope,
            targetCardID: targetCardID,
            expectedActiveCardID: expectedActiveCardID,
            animated: animated,
            trigger: trigger
        )
    }

    func publishMainColumnFocusNavigationIntent(
        for activeID: UUID?,
        trigger: String = "activeCardChange"
    ) {
        let shouldAnimate =
            focusNavigationAnimationEnabled &&
            !shouldSuppressMainArrowRepeatAnimation()
        _ = publishMainColumnNavigationIntent(
            kind: .focusChange,
            scope: .allColumns,
            targetCardID: activeID,
            expectedActiveCardID: activeID,
            animated: shouldAnimate,
            trigger: trigger
        )
    }

    // MARK: - Debug Helpers

    func debugCGFloat(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }

    func debugCardIDString(_ id: UUID?) -> String {
        guard let id else { return "nil" }
        return String(id.uuidString.prefix(8))
    }

    func debugCardToken(_ card: SceneCard?) -> String {
        guard let card else { return "nil" }
        let compact = card.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = compact.isEmpty ? "empty" : String(compact.prefix(18))
        return "\(debugCardIDString(card.id)):\(preview)"
    }

    func debugUUIDListSummary(_ ids: [UUID], limit: Int = 6) -> String {
        let displayed = ids.prefix(limit).map { debugCardIDString($0) }.joined(separator: ",")
        if ids.count > limit {
            return "[\(displayed),+\(ids.count - limit)]"
        }
        return "[\(displayed)]"
    }

    func debugFocusStateSummary() -> String {
        let sortedAncestors = activeAncestorIDs.sorted { $0.uuidString < $1.uuidString }
        return
            "active=\(debugCardIDString(activeCardID)) pending=\(debugCardIDString(pendingActiveCardID)) " +
            "editing=\(debugCardIDString(editingCardID)) ancestors=\(debugUUIDListSummary(sortedAncestors, limit: 8)) " +
            "siblings=\(activeSiblingIDs.count) descendants=\(activeDescendantIDs.count)"
    }

    func mainColumnViewportCoordinateSpaceName(_ viewportKey: String) -> String {
        "main-column-viewport:\(viewportKey)"
    }

    func debugMainColumnEstimatedTargetSummary(_ layout: (targetMinY: CGFloat, targetMaxY: CGFloat)?) -> String {
        guard let layout else { return "est=unresolved" }
        return "est[\(debugCGFloat(layout.targetMinY)),\(debugCGFloat(layout.targetMaxY))]"
    }

    func debugMainColumnObservedTargetSummary(viewportKey: String, targetID: UUID, offsetY: CGFloat) -> String {
        guard let frame = observedMainColumnTargetFrame(
            viewportKey: viewportKey,
            targetID: targetID
        ) else {
            return "frame=unseen"
        }
        let visibleMinY = frame.minY - offsetY
        let visibleMaxY = frame.maxY - offsetY
        return
            "frame=view[\(debugCGFloat(visibleMinY)),\(debugCGFloat(visibleMaxY))] " +
            "content[\(debugCGFloat(frame.minY)),\(debugCGFloat(frame.maxY))] h=\(debugCGFloat(frame.height))"
    }

    func debugMainColumnVisibleCardSummary(
        viewportKey: String,
        cards: [SceneCard],
        viewportHeight: CGFloat,
        offsetY: CGFloat
    ) -> String {
        if let observedFrames = mainCanvasScrollCoordinator.geometryModel(for: viewportKey)?.observedFramesByCardID,
           !observedFrames.isEmpty {
            let visible = cards.compactMap { card -> String? in
                guard let frame = observedFrames[card.id] else { return nil }
                let visibleMinY = frame.minY - offsetY
                let visibleMaxY = frame.maxY - offsetY
                guard visibleMaxY >= -32, visibleMinY <= viewportHeight + 32 else { return nil }
                let marker = card.id == activeCardID ? "*" : (activeAncestorIDs.contains(card.id) ? "^" : "")
                return "\(marker)\(debugCardIDString(card.id))@\(debugCGFloat(visibleMinY))...\(debugCGFloat(visibleMaxY))"
            }
            if !visible.isEmpty {
                return visible.prefix(6).joined(separator: " | ")
            }
        }

        let snapshot = resolvedMainColumnLayoutSnapshot(in: cards, viewportHeight: viewportHeight)
        var visible: [String] = []
        for cardID in snapshot.orderedCardIDs {
            guard let frame = snapshot.framesByCardID[cardID] else { continue }
            let visibleMinY = frame.minY - offsetY
            let visibleMaxY = frame.maxY - offsetY
            guard visibleMaxY >= -32, visibleMinY <= viewportHeight + 32 else { continue }
            let marker = cardID == activeCardID ? "*" : (activeAncestorIDs.contains(cardID) ? "^" : "")
            visible.append("\(marker)\(debugCardIDString(cardID))@\(debugCGFloat(visibleMinY))...\(debugCGFloat(visibleMaxY))")
            if visible.count == 6 {
                break
            }
        }

        return visible.isEmpty ? "none" : visible.joined(separator: " | ")
    }

    func mainColumnGeometryObservationCardIDs(
        in cards: [SceneCard],
        viewportKey: String,
        viewportHeight: CGFloat
    ) -> Set<UUID> {
        let allIDs = Set(cards.map(\.id))
        guard cards.count > 24 else { return allIDs }

        let snapshot = resolvedMainColumnLayoutSnapshot(in: cards, viewportHeight: viewportHeight)
        let visibleRect = resolvedMainColumnVisibleRect(
            viewportKey: viewportKey,
            viewportHeight: viewportHeight
        )
        let preloadDistance = max(viewportHeight * 0.75, 240)
        let observedMinY = visibleRect.minY - preloadDistance
        let observedMaxY = visibleRect.maxY + preloadDistance

        var observedIDs: Set<UUID> = []
        observedIDs.reserveCapacity(min(cards.count, 24))

        for cardID in snapshot.orderedCardIDs {
            guard let frame = snapshot.framesByCardID[cardID] else { continue }
            guard frame.maxY >= observedMinY, frame.minY <= observedMaxY else { continue }
            observedIDs.insert(cardID)
        }

        if let targetID = resolvedMainColumnFocusTargetID(in: cards),
           let targetIndex = cards.firstIndex(where: { $0.id == targetID }) {
            let lowerBound = max(cards.startIndex, targetIndex - 6)
            let upperBound = min(cards.index(before: cards.endIndex), targetIndex + 6)
            for index in lowerBound...upperBound {
                observedIDs.insert(cards[index].id)
            }
        }

        if let activeCardID, allIDs.contains(activeCardID) {
            observedIDs.insert(activeCardID)
        }
        if let editingCardID, allIDs.contains(editingCardID) {
            observedIDs.insert(editingCardID)
        }

        if observedIDs.isEmpty {
            for card in cards.prefix(12) {
                observedIDs.insert(card.id)
            }
        }

        return observedIDs
    }

    // MARK: - Resolved Colors & Search

    func resolvedBackgroundColor() -> Color {
        if isDarkAppearanceActive {
            let darkRGB = rgbFromHex(darkBackgroundColorHex) ?? (0.07, 0.08, 0.10)
            return Color(red: darkRGB.0, green: darkRGB.1, blue: darkRGB.2)
        }
        let lightRGB = rgbFromHex(backgroundColorHex) ?? (0.96, 0.95, 0.93)
        return Color(red: lightRGB.0, green: lightRGB.1, blue: lightRGB.2)
    }

    func resolvedTimelineBackgroundColor() -> Color {
        if isDarkAppearanceActive {
            return Color(red: 0.11, green: 0.12, blue: 0.14)
        }
        return Color(red: 0.94, green: 0.93, blue: 0.91)
    }

    func matchesSearch(_ card: SceneCard) -> Bool {
        let tokens = searchTokens(from: searchText)
        if tokens.isEmpty { return true }
        let haystack = normalizedSearchText(card.content)
        for token in tokens {
            if !haystack.contains(token) { return false }
        }
        return true
    }

    func searchTokens(from text: String) -> [String] {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .map { normalizedSearchText($0) }
            .filter { !$0.isEmpty }
    }

    func normalizedSearchText(_ text: String) -> String {
        let lowered = text.lowercased()
        let withoutSpaces = lowered.filter { !$0.isWhitespace }
        return String(withoutSpaces)
    }

    // MARK: - Color Utilities

    func rgbFromHex(_ hex: String) -> (Double, Double, Double)? {
        parseHexRGB(hex)
    }

    enum MutationUndoMode {
        case main
        case focusAware
        case none
    }

    func prepareWriterModelForPersistence() {
        store.synchronizeSharedCraftTrees(preserveExistingTimestamps: true)
    }

    func saveWriterChanges(immediate: Bool = false) {
        prepareWriterModelForPersistence()
        store.saveAll(immediate: immediate)
    }

    func persistCardMutation(forceSnapshot: Bool = false, immediateSave: Bool = false) {
        saveWriterChanges(immediate: immediateSave)
        takeSnapshot(force: forceSnapshot)
    }

    func commitCardMutation(
        previousState: ScenarioState,
        actionName: String,
        forceSnapshot: Bool = false,
        immediateSave: Bool = false,
        undoMode: MutationUndoMode = .main
    ) {
        persistCardMutation(forceSnapshot: forceSnapshot, immediateSave: immediateSave)
        switch undoMode {
        case .main:
            pushUndoState(previousState, actionName: actionName)
        case .focusAware:
            if showFocusMode {
                pushFocusUndoState(previousState, actionName: actionName)
            } else {
                pushUndoState(previousState, actionName: actionName)
            }
        case .none:
            break
        }
    }

    // MARK: - Timeline & Column View Builders

    func beginCardEditing(_ card: SceneCard, explicitCaretLocation: Int? = nil) {
        finishEditing()
        pendingMainEditingSiblingNavigationTargetID = nil
        if let explicitCaretLocation {
            pendingMainEditingViewportKeepVisibleCardID = nil
            pendingMainEditingViewportRevealEdge = nil
            let textLength = (card.content as NSString).length
            let safeLocation = min(max(0, explicitCaretLocation), textLength)
            mainCaretLocationByCardID[card.id] = safeLocation
            mainProgrammaticCaretSuppressEnsureCardID = card.id
            mainProgrammaticCaretExpectedCardID = card.id
            mainProgrammaticCaretExpectedLocation = safeLocation
            mainProgrammaticCaretSelectionIgnoreUntil = Date().addingTimeInterval(0.28)
        } else {
            pendingMainEditingViewportKeepVisibleCardID = card.id
            pendingMainEditingViewportRevealEdge = nil
            mainProgrammaticCaretSuppressEnsureCardID = nil
            mainProgrammaticCaretExpectedCardID = nil
            mainProgrammaticCaretExpectedLocation = -1
            mainProgrammaticCaretSelectionIgnoreUntil = .distantPast
        }
        changeActiveCard(to: card)
        editingCardID = card.id
        editingStartContent = card.content
        editingStartState = captureScenarioState()
        editingIsNewCard = false
        selectedCardIDs = [card.id]
    }

    @ViewBuilder
    func timelineRow(_ card: SceneCard) -> some View {
        let isNamedNote = isNamedSnapshotNoteCard(card)
        let isAICandidate = aiCandidateState.cardIDs.contains(card.id) || card.isAICandidate
        let isTimelineSelected = selectedCardIDs.contains(card.id)
        let isTimelineMultiSelected = selectedCardIDs.count > 1 && isTimelineSelected
        let isTimelineEmptyCard = card.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isPlotLineCard = card.category == ScenarioCardCategory.plot
        let canSummarizeChildren = canSummarizeDirectChildren(for: card)
        let isCloneLinked = scenario.isCardCloned(card.id)
        let hasLinkedCards = scenario.hasLinkedCards(card.id)
        let isLinkedCard = scenario.isLinkedCard(card.id)
        let disconnectAnchorID = resolvedLinkedCardsAnchorID()
        let canDisconnectLinkedCard =
            linkedCardsFilterEnabled &&
            disconnectAnchorID.flatMap { anchorID in
                scenario.linkedCardEditDate(
                    focusCardID: anchorID,
                    linkedCardID: card.id
                )
            } != nil
        let clonePeerDestinations = isCloneLinked ? clonePeerMenuDestinations(for: card) : []
        CardItem(
            card: card,
            renderSettings: mainCardRenderSettings,
            isActive: activeCardID == card.id,
            isSelected: selectedCardIDs.contains(card.id),
            isMultiSelected: selectedCardIDs.count > 1 && selectedCardIDs.contains(card.id),
            isArchived: card.isArchived,
            isAncestor: false,
            isDescendant: false,
            isEditing: acceptsKeyboardInput && editingCardID == card.id,
            preferredTextMeasureWidth: TimelinePanelLayoutMetrics.textWidth,
            forceNamedSnapshotNoteStyle: isNamedNote,
            forceCustomColorVisibility: isAICandidate,
            onSelect: {
                if openHistoryFromNamedSnapshotNoteCard(card) { return }
                handleTimelineCardSelect(card)
            },
            onDoubleClick: {
                if openHistoryFromNamedSnapshotNoteCard(card) { return }
                handleTimelineCardDoubleClick(card)
            },
            onEndEdit: { finishEditing() },
            onContentChange: nil,
            onColorChange: { hex in setCardColor(card, hex: hex) },
            onReferenceCard: { addCardToReferenceWindow(card) },
            onSummarizeChildren: canSummarizeChildren ? {
                runChildSummaryFromCardContextMenu(for: card)
            } : nil,
            onAIElaborate: {
                runAICardActionFromContextMenu(for: card, action: .elaborate)
            },
            onAINextScene: {
                runAICardActionFromContextMenu(for: card, action: .nextScene)
            },
            onAIAlternative: {
                runAICardActionFromContextMenu(for: card, action: .alternative)
            },
            onAISummarizeCurrent: {
                runAICardActionFromContextMenu(for: card, action: .summary)
            },
            aiPlotActionsEnabled: isPlotLineCard,
            onApplyAICandidate: isAICandidate ? {
                applyAICandidateFromCardContextMenu(cardID: card.id)
            } : nil,
            isSummarizingChildren: aiChildSummaryLoadingCardIDs.contains(card.id),
            isAIBusy: aiIsGenerating,
            onDelete: { performDelete(card) },
            onHardDelete: { performHardDelete(card) },
            onTranscriptionMode: { startDictationMode(from: card) },
            isTranscriptionBusy: dictationIsRecording || dictationIsProcessing,
            showsEmptyCardBulkDeleteMenuOnly: isTimelineEmptyCard,
            onBulkDeleteEmptyCards: isTimelineEmptyCard ? { performHardDeleteAllTimelineEmptyLeafCards() } : nil,
            isCloneLinked: isCloneLinked,
            hasLinkedCards: hasLinkedCards,
            isLinkedCard: isLinkedCard,
            onDisconnectLinkedCard: canDisconnectLinkedCard ? {
                disconnectLinkedCardFromAnchor(linkedCardID: card.id)
            } : nil,
            onCloneCard: { copyCardsAsCloneFromContext(card) },
            clonePeerDestinations: clonePeerDestinations,
            onNavigateToClonePeer: { targetID in navigateToCloneCard(targetID) }
        )
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isTimelineSelected
                    ? Color.accentColor.opacity(isTimelineMultiSelected ? 0.26 : 0.16)
                    : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isTimelineSelected
                    ? Color.accentColor.opacity(isTimelineMultiSelected ? 0.95 : 0.70)
                    : Color.clear,
                    lineWidth: isTimelineMultiSelected ? 2 : 1
                )
        )
        .id("timeline-\(card.id)")
        .onDrag {
            MainCardDragSessionTracker.shared.begin()
            return NSItemProvider(object: card.id.uuidString as NSString)
        }
    }

    @ViewBuilder
    func column(for cards: [SceneCard], level: Int, parent: SceneCard?, screenHeight: CGFloat) -> some View {
        let childListSignature = scenario.childListSignature(parentID: parent?.id)
        let viewportKey = mainColumnViewportStorageKey(level: level)
        let observedCardIDs = mainColumnGeometryObservationCardIDs(
            in: cards,
            viewportKey: viewportKey,
            viewportHeight: screenHeight
        )
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        if cards.isEmpty {
                            DropSpacer(target: .columnTop(parent?.id), alignment: .bottom) { providers, includeTrailingSiblingBlock in
                                handleGeneralDrop(
                                    providers,
                                    target: .columnTop(parent?.id),
                                    includeTrailingSiblingBlock: includeTrailingSiblingBlock
                                )
                            }
                            .frame(height: screenHeight * 0.4)

                            if level == 0 { addFirstButton(level: level) }

                            DropSpacer(target: .columnBottom(parent?.id), alignment: .top) { providers, includeTrailingSiblingBlock in
                                handleGeneralDrop(
                                    providers,
                                    target: .columnBottom(parent?.id),
                                    includeTrailingSiblingBlock: includeTrailingSiblingBlock
                                )
                            }
                            .frame(height: screenHeight * 0.7)
                        } else {
                            Color.clear.frame(height: screenHeight * 0.4)

                            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                                VStack(spacing: 0) {
                                    cardRow(card, proxy: proxy)
                                        .background(
                                            Group {
                                                if observedCardIDs.contains(card.id) {
                                                    GeometryReader { geometry in
                                                        Color.clear.preference(
                                                            key: MainColumnCardFramePreferenceKey.self,
                                                            value: [
                                                                card.id: geometry.frame(
                                                                    in: .named(mainColumnViewportCoordinateSpaceName(viewportKey))
                                                                )
                                                            ]
                                                        )
                                                    }
                                                }
                                            }
                                        )

                                    if index < cards.count - 1 {
                                        let next = cards[index + 1]
                                        if card.parent?.id != next.parent?.id {
                                            Rectangle()
                                                .fill(appearance == "light" ? Color.black.opacity(0.16) : Color.black.opacity(0.40))
                                                .frame(height: mainParentGroupSeparatorHeight)
                                                .padding(.horizontal, 14)
                                        }
                                        Color.clear.frame(height: max(0, CGFloat(mainCardVerticalGap)))
                                    }
                                }
                            }

                            Color.clear.frame(height: screenHeight * 0.7)
                        }
                    }
                    .coordinateSpace(name: mainColumnViewportCoordinateSpaceName(viewportKey))
                    .onPreferenceChange(MainColumnCardFramePreferenceKey.self) { frames in
                        mainColumnObservedCardFramesByKey[viewportKey] = frames
                        mainCanvasScrollCoordinator.updateObservedFrames(frames, for: viewportKey)
                    }
                    .padding(.horizontal, MainCanvasLayoutMetrics.columnHorizontalPadding)
                    .frame(width: columnWidth)
                    .background(
                        mainColumnScrollObserver(
                            viewportKey: viewportKey,
                            level: level,
                            parent: parent,
                            cards: cards,
                            viewportHeight: screenHeight
                        )
                    )
                }
                .onChange(of: mainCanvasScrollCoordinator.navigationIntentTick) { _, _ in
                    handleMainColumnNavigationIntent(
                        viewportKey: viewportKey,
                        cards: cards,
                        level: level,
                        parent: parent,
                        proxy: proxy,
                        viewportHeight: screenHeight
                    )
                }
                .onChange(of: activeCardID) { _, newID in
                    guard pendingMainClickFocusTargetID == newID else { return }
                    handleMainColumnActiveFocusChange(
                        viewportKey: viewportKey,
                        newActiveID: newID,
                        cards: cards,
                        level: level,
                        parent: parent,
                        proxy: proxy,
                        viewportHeight: screenHeight,
                        trigger: "clickFocus"
                    )
                    DispatchQueue.main.async {
                        if pendingMainClickFocusTargetID == newID {
                            pendingMainClickFocusTargetID = nil
                        }
                    }
                }
                .onChange(of: childListSignature) { _, _ in
                    guard !showFocusMode else { return }
                    guard acceptsKeyboardInput else { return }
                    guard editingCardID == nil else { return }
                    if pendingMainEditingSiblingNavigationTargetID == activeCardID {
                        return
                    }
                    cancelPendingMainColumnFocusWorkItem(for: viewportKey)
                    cancelPendingMainColumnFocusVerificationWorkItem(for: viewportKey)
                    if shouldPreserveMainColumnViewportOnReveal(level: level, storageKey: viewportKey, newActiveID: activeCardID) {
                        return
                    }
                    guard shouldAutoAlignMainColumn(cards: cards, activeID: activeCardID) else { return }
                    _ = publishMainColumnNavigationIntent(
                        kind: .childListChange,
                        scope: .viewport(viewportKey),
                        targetCardID: activeCardID,
                        expectedActiveCardID: activeCardID,
                        animated: false,
                        trigger: "childListChange"
                    )
                }
                .onAppear {
                    guard !showFocusMode else { return }
                    guard acceptsKeyboardInput else { return }
                    guard editingCardID == nil else { return }
                    if pendingMainEditingSiblingNavigationTargetID == activeCardID {
                        return
                    }
                    cancelPendingMainColumnFocusWorkItem(for: viewportKey)
                    cancelPendingMainColumnFocusVerificationWorkItem(for: viewportKey)
                    if shouldPreserveMainColumnViewportOnReveal(level: level, storageKey: viewportKey, newActiveID: activeCardID) {
                        return
                    }
                    guard shouldAutoAlignMainColumn(cards: cards, activeID: activeCardID) else { return }
                    _ = publishMainColumnNavigationIntent(
                        kind: .columnAppear,
                        scope: .viewport(viewportKey),
                        targetCardID: activeCardID,
                        expectedActiveCardID: activeCardID,
                        animated: false,
                        trigger: "columnAppear"
                    )
                }
                .onChange(of: mainBottomRevealTick) { _, _ in
                    guard !showFocusMode else { return }
                    guard acceptsKeyboardInput else { return }
                    guard editingCardID == nil else { return }
                    if pendingMainEditingSiblingNavigationTargetID == activeCardID {
                        return
                    }
                    guard let requestedID = mainBottomRevealCardID else { return }
                    guard activeCardID == requestedID else { return }
                    guard cards.last?.id == requestedID else { return }
                    guard let requestedCard = findCard(by: requestedID) else { return }
                    let cardHeight = resolvedMainCardHeight(for: requestedCard)
                    guard cardHeight > screenHeight else { return }
                    _ = publishMainColumnNavigationIntent(
                        kind: .bottomReveal,
                        scope: .viewport(viewportKey),
                        targetCardID: requestedID,
                        expectedActiveCardID: requestedID,
                        animated: focusNavigationAnimationEnabled,
                        trigger: "mainBottomReveal"
                    )
                }
            }
            .contentShape(Rectangle()).onTapGesture { finishEditing(); isMainViewFocused = true }
        }
        .frame(width: columnWidth)
    }

    func scrollToFocus(
        in cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        keepVisibleOnly: Bool = false,
        editingRevealEdge: MainEditingViewportRevealEdge? = nil,
        forceAlignment: Bool = false,
        animated: Bool = true,
        reason: String = "unspecified",
        authority: MainVerticalScrollAuthority? = nil
    ) {
        guard acceptsKeyboardInput else { return }
        let requestKey = mainColumnScrollCacheKey(level: level, parent: parent)
        let viewportKey = mainColumnViewportStorageKey(level: level)
        guard isMainVerticalScrollAuthorityCurrent(authority, viewportKey: viewportKey) else { return }

        guard let idToScroll = resolvedMainColumnFocusTargetID(in: cards) else {
            bounceDebugLog(
                "scrollToFocus noTarget reason=\(reason) key=\(requestKey) viewportKey=\(viewportKey) " +
                "\(debugFocusStateSummary())"
            )
            mainColumnLastFocusRequestByKey.removeValue(forKey: requestKey)
            cancelPendingMainColumnFocusVerificationWorkItem(for: viewportKey)
            return
        }

        let currentOffsetY = resolvedMainColumnCurrentOffsetY(viewportKey: viewportKey)
        let targetLayout = resolvedMainColumnTargetLayout(
            in: cards,
            targetID: idToScroll,
            viewportHeight: viewportHeight
        )
        let targetHeight = targetLayout.map { $0.targetMaxY - $0.targetMinY }
            ?? findCard(by: idToScroll).map { resolvedMainCardHeight(for: $0) }
            ?? 0
        let prefersTopAnchor = targetHeight > viewportHeight
        let request = MainColumnFocusRequest(
            targetID: idToScroll,
            prefersTopAnchor: prefersTopAnchor,
            keepVisibleOnly: keepVisibleOnly,
            editingRevealEdge: editingRevealEdge,
            cardsCount: cards.count,
            firstCardID: cards.first?.id,
            lastCardID: cards.last?.id,
            viewportHeightBucket: Int(viewportHeight.rounded())
        )
        if !forceAlignment,
           mainColumnLastFocusRequestByKey[requestKey] == request {
            bounceDebugLog(
                "scrollToFocus skipped reason=\(reason) key=\(requestKey) viewportKey=\(viewportKey) " +
                "target=\(debugCardIDString(idToScroll)) offset=\(debugCGFloat(currentOffsetY)) " +
                "\(debugMainColumnEstimatedTargetSummary(targetLayout)) " +
                "\(debugMainColumnObservedTargetSummary(viewportKey: viewportKey, targetID: idToScroll, offsetY: currentOffsetY)) " +
                "visible=\(debugMainColumnVisibleCardSummary(viewportKey: viewportKey, cards: cards, viewportHeight: viewportHeight, offsetY: currentOffsetY))"
            )
            scheduleMainColumnFocusVerification(
                viewportKey: viewportKey,
                cards: cards,
                level: level,
                parent: parent,
                targetID: idToScroll,
                proxy: proxy,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor,
                keepVisibleOnly: keepVisibleOnly,
                editingRevealEdge: editingRevealEdge,
                animated: false,
                authority: authority
            )
            return
        }
        mainColumnLastFocusRequestByKey[requestKey] = request

        if keepVisibleOnly,
           isMainColumnFocusTargetVisible(
                viewportKey: viewportKey,
                cards: cards,
                targetID: idToScroll,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor
           ) {
            scheduleMainColumnFocusVerification(
                viewportKey: viewportKey,
                cards: cards,
                level: level,
                parent: parent,
                targetID: idToScroll,
                proxy: proxy,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor,
                keepVisibleOnly: true,
                editingRevealEdge: editingRevealEdge,
                animated: false,
                authority: authority
            )
            return
        }

        if !forceAlignment && shouldSkipMainColumnFocusScroll(
            targetID: idToScroll,
            cards: cards,
            level: level,
            viewportHeight: viewportHeight,
            prefersTopAnchor: prefersTopAnchor
        ) {
            bounceDebugLog(
                "scrollToFocus preserved reason=\(reason) key=\(requestKey) viewportKey=\(viewportKey) " +
                "target=\(debugCardIDString(idToScroll)) offset=\(debugCGFloat(currentOffsetY)) top=\(prefersTopAnchor) " +
                "\(debugMainColumnEstimatedTargetSummary(targetLayout)) " +
                "\(debugMainColumnObservedTargetSummary(viewportKey: viewportKey, targetID: idToScroll, offsetY: currentOffsetY))"
            )
            scheduleMainColumnFocusVerification(
                viewportKey: viewportKey,
                cards: cards,
                level: level,
                parent: parent,
                targetID: idToScroll,
                proxy: proxy,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor,
                keepVisibleOnly: keepVisibleOnly,
                editingRevealEdge: editingRevealEdge,
                animated: false,
                authority: authority
            )
            return
        }

        bounceDebugLog(
            "scrollToFocus reason=\(reason) key=\(requestKey) viewportKey=\(viewportKey) " +
            "target=\(debugCardToken(findCard(by: idToScroll))) height=\(debugCGFloat(targetHeight)) " +
            "viewport=\(debugCGFloat(viewportHeight)) offset=\(debugCGFloat(currentOffsetY)) " +
            "top=\(prefersTopAnchor) keepVisible=\(keepVisibleOnly) force=\(forceAlignment) edge=\(String(describing: editingRevealEdge)) animated=\(animated) " +
            "\(debugMainColumnEstimatedTargetSummary(targetLayout)) " +
            "\(debugMainColumnObservedTargetSummary(viewportKey: viewportKey, targetID: idToScroll, offsetY: currentOffsetY)) " +
            "visible=\(debugMainColumnVisibleCardSummary(viewportKey: viewportKey, cards: cards, viewportHeight: viewportHeight, offsetY: currentOffsetY))"
        )
        if keepVisibleOnly {
            applyMainColumnFocusVisibility(
                viewportKey: viewportKey,
                cards: cards,
                targetID: idToScroll,
                proxy: proxy,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor,
                editingRevealEdge: editingRevealEdge,
                animated: animated
            )
        } else {
            applyMainColumnFocusAlignment(
                viewportKey: viewportKey,
                cards: cards,
                targetID: idToScroll,
                proxy: proxy,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor,
                animated: animated
            )
        }
        scheduleMainColumnFocusVerification(
            viewportKey: viewportKey,
            cards: cards,
            level: level,
            parent: parent,
            targetID: idToScroll,
            proxy: proxy,
            viewportHeight: viewportHeight,
            prefersTopAnchor: prefersTopAnchor,
            keepVisibleOnly: keepVisibleOnly,
            editingRevealEdge: editingRevealEdge,
            animated: animated,
            authority: authority
        )
    }

    func handleMainColumnNavigationIntent(
        viewportKey: String,
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat
    ) {
        guard let intent = mainCanvasScrollCoordinator.consumeLatestIntent(for: viewportKey) else { return }

        switch intent.kind {
        case .focusChange:
            handleMainColumnActiveFocusChange(
                viewportKey: viewportKey,
                newActiveID: intent.expectedActiveCardID,
                cards: cards,
                level: level,
                parent: parent,
                proxy: proxy,
                viewportHeight: viewportHeight,
                trigger: intent.trigger,
                animatedOverride: intent.animated,
                intentID: intent.id
            )

        case .settleRecovery:
            handleMainColumnNavigationSettle(
                viewportKey: viewportKey,
                cards: cards,
                level: level,
                parent: parent,
                proxy: proxy,
                viewportHeight: viewportHeight
            )

        case .childListChange, .columnAppear:
            handleMainColumnImmediateAlignmentIntent(
                viewportKey: viewportKey,
                cards: cards,
                level: level,
                parent: parent,
                proxy: proxy,
                viewportHeight: viewportHeight,
                trigger: intent.trigger
            )

        case .bottomReveal:
            handleMainColumnBottomRevealIntent(
                viewportKey: viewportKey,
                cards: cards,
                proxy: proxy,
                viewportHeight: viewportHeight,
                requestedID: intent.targetCardID,
                animated: intent.animated,
                trigger: intent.trigger
            )
        }
    }

    func handleMainColumnImmediateAlignmentIntent(
        viewportKey: String,
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        trigger: String
    ) {
        guard !showFocusMode else { return }
        guard acceptsKeyboardInput else { return }
        guard editingCardID == nil else { return }
        cancelPendingMainColumnFocusWorkItem(for: viewportKey)
        cancelPendingMainColumnFocusVerificationWorkItem(for: viewportKey)
        if shouldPreserveMainColumnViewportOnReveal(level: level, storageKey: viewportKey, newActiveID: activeCardID) {
            return
        }
        guard shouldAutoAlignMainColumn(cards: cards, activeID: activeCardID) else { return }
        let authority = beginMainVerticalScrollAuthority(
            viewportKey: viewportKey,
            kind: .columnNavigation,
            targetCardID: activeCardID
        )
        bounceDebugLog(
            "\(trigger) level=\(level) viewportKey=\(viewportKey) " +
            "offset=\(debugCGFloat(mainColumnViewportOffsetByKey[viewportKey] ?? 0)) " +
            "visible=\(debugMainColumnVisibleCardSummary(viewportKey: viewportKey, cards: cards, viewportHeight: viewportHeight, offsetY: mainColumnViewportOffsetByKey[viewportKey] ?? 0))"
        )
        scrollToFocus(
            in: cards,
            level: level,
            parent: parent,
            proxy: proxy,
            viewportHeight: viewportHeight,
            animated: false,
            reason: trigger,
            authority: authority
        )
    }

    func handleMainColumnBottomRevealIntent(
        viewportKey: String,
        cards: [SceneCard],
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        requestedID: UUID?,
        animated: Bool,
        trigger: String
    ) {
        guard !showFocusMode else { return }
        guard acceptsKeyboardInput else { return }
        guard editingCardID == nil else { return }
        guard let requestedID else { return }
        guard activeCardID == requestedID else { return }
        guard cards.last?.id == requestedID else { return }
        guard let requestedCard = findCard(by: requestedID) else { return }
        let cardHeight = resolvedMainCardHeight(for: requestedCard)
        guard cardHeight > viewportHeight else { return }

        bounceDebugLog(
            "\(trigger) viewportKey=\(viewportKey) target=\(debugCardToken(requestedCard)) " +
            "offset=\(debugCGFloat(mainColumnViewportOffsetByKey[viewportKey] ?? 0)) height=\(debugCGFloat(cardHeight))"
        )
        _ = beginMainVerticalScrollAuthority(
            viewportKey: viewportKey,
            kind: .columnNavigation,
            targetCardID: requestedID
        )
        if performMainColumnNativeFocusScroll(
            viewportKey: viewportKey,
            cards: cards,
            targetID: requestedID,
            viewportHeight: viewportHeight,
            anchorY: 1.0,
            animated: animated
        ) {
            return
        }

        suspendMainColumnViewportCapture(for: animated ? 0.32 : 0.12)
        if animated {
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                axis: "vertical",
                engine: "proxy",
                animated: true,
                target: "\(viewportKey)|\(requestedID.uuidString)",
                expectedDuration: 0.24
            )
            withAnimation(quickEaseAnimation) {
                proxy.scrollTo(requestedID, anchor: .bottom)
            }
        } else {
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                axis: "vertical",
                engine: "proxy",
                animated: false,
                target: "\(viewportKey)|\(requestedID.uuidString)",
                expectedDuration: 0
            )
            performWithoutAnimation {
                proxy.scrollTo(requestedID, anchor: .bottom)
            }
        }
    }

    func handleMainColumnActiveFocusChange(
        viewportKey: String,
        newActiveID: UUID?,
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        trigger: String,
        animatedOverride: Bool? = nil,
        intentID: Int? = nil
    ) {
        guard !showFocusMode else { return }
        guard acceptsKeyboardInput else { return }
        guard editingCardID == nil else { return }
        cancelPendingMainColumnFocusWorkItem(for: viewportKey)
        cancelPendingMainColumnFocusVerificationWorkItem(for: viewportKey)
        let forceClickAlignment = trigger == "clickFocus"
        if !forceClickAlignment &&
            shouldPreserveMainColumnViewportOnReveal(level: level, storageKey: viewportKey, newActiveID: newActiveID) {
            return
        }

        let containsActiveCard = cards.contains { $0.id == newActiveID }
        let containsActiveAncestor = cards.contains { activeAncestorIDs.contains($0.id) }
        guard containsActiveCard || containsActiveAncestor else { return }

        let activeCardNeedsTopReveal = containsActiveCard && {
            guard let newActiveID, let targetCard = findCard(by: newActiveID) else { return false }
            return resolvedMainCardHeight(for: targetCard) > viewportHeight
        }()
        let editDrivenKeepVisible = containsActiveCard && pendingMainEditingViewportKeepVisibleCardID == newActiveID
        let editingRevealEdge = editDrivenKeepVisible ? pendingMainEditingViewportRevealEdge : nil
        if editDrivenKeepVisible {
            pendingMainEditingViewportKeepVisibleCardID = nil
            pendingMainEditingViewportRevealEdge = nil
        }
        let shouldAnimate = animatedOverride ?? (
            focusNavigationAnimationEnabled &&
            !shouldSuppressMainArrowRepeatAnimation()
        )
        let authority = beginMainVerticalScrollAuthority(
            viewportKey: viewportKey,
            kind: editDrivenKeepVisible ? .editingTransition : .columnNavigation,
            targetCardID: newActiveID
        )

        bounceDebugLog(
            "\(trigger) level=\(level) viewportKey=\(viewportKey) " +
            "newID=\(newActiveID?.uuidString ?? "nil") activeColumn=\(containsActiveCard) " +
            "ancestorColumn=\(containsActiveAncestor) topReveal=\(activeCardNeedsTopReveal) " +
            "editKeepVisible=\(editDrivenKeepVisible) forceClick=\(forceClickAlignment) animate=\(shouldAnimate) " +
            "offset=\(debugCGFloat(mainColumnViewportOffsetByKey[viewportKey] ?? 0)) " +
            "visible=\(debugMainColumnVisibleCardSummary(viewportKey: viewportKey, cards: cards, viewportHeight: viewportHeight, offsetY: mainColumnViewportOffsetByKey[viewportKey] ?? 0))"
        )
        scheduleMainColumnActiveCardFocus(
            viewportKey: viewportKey,
            expectedActiveID: newActiveID,
            cards: cards,
            level: level,
            parent: parent,
            proxy: proxy,
            viewportHeight: viewportHeight,
            keepVisibleOnly: editDrivenKeepVisible,
            editingRevealEdge: editingRevealEdge,
            forceAlignment: forceClickAlignment,
            animated: shouldAnimate,
            intentID: intentID,
            authority: authority
        )
    }

    func resolvedMainColumnCurrentOffsetY(viewportKey: String) -> CGFloat {
        if let liveOffset = mainCanvasScrollCoordinator
            .scrollView(for: viewportKey)?
            .documentVisibleRect
            .origin
            .y
        {
            return liveOffset
        }
        return mainColumnViewportOffsetByKey[viewportKey] ?? 0
    }

    func resolvedMainColumnFocusTargetOffset(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat,
        anchorY: CGFloat
    ) -> CGFloat? {
        let frame =
            observedMainColumnTargetFrame(
                viewportKey: viewportKey,
                targetID: targetID
            ) ??
            predictedMainColumnTargetFrame(
                cards: cards,
                targetID: targetID,
                viewportHeight: viewportHeight
            )
        guard let frame else {
            return nil
        }

        let clampedAnchorY = min(max(0, anchorY), 1)
        let targetAnchorY = frame.minY + (frame.height * clampedAnchorY)
        return targetAnchorY - (viewportHeight * clampedAnchorY)
    }

    func resolvedMainColumnVisibleRect(
        viewportKey: String,
        viewportHeight: CGFloat
    ) -> CGRect {
        if let visibleRect = mainCanvasScrollCoordinator
            .scrollView(for: viewportKey)?
            .documentVisibleRect
        {
            return visibleRect
        }

        return CGRect(
            x: 0,
            y: resolvedMainColumnCurrentOffsetY(viewportKey: viewportKey),
            width: 1,
            height: viewportHeight
        )
    }

    func predictedMainColumnTargetFrame(
        cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat
    ) -> CGRect? {
        guard let layout = resolvedMainColumnTargetLayout(
            in: cards,
            targetID: targetID,
            viewportHeight: viewportHeight
        ) else {
            return nil
        }
        return CGRect(
            x: 0,
            y: layout.targetMinY,
            width: 1,
            height: layout.targetMaxY - layout.targetMinY
        )
    }

    func observedMainColumnTargetFrame(
        viewportKey: String,
        targetID: UUID
    ) -> CGRect? {
        mainCanvasScrollCoordinator.observedFrame(for: viewportKey, cardID: targetID)
    }

    func isObservedMainColumnFocusTargetVisible(
        viewportKey: String,
        targetID: UUID,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool
    ) -> Bool {
        guard let frame = observedMainColumnTargetFrame(
            viewportKey: viewportKey,
            targetID: targetID
        ) else {
            return false
        }

        let visibleRect = resolvedMainColumnVisibleRect(
            viewportKey: viewportKey,
            viewportHeight: viewportHeight
        )
        let visibleMinY = frame.minY - visibleRect.origin.y
        let visibleMaxY = frame.maxY - visibleRect.origin.y
        if prefersTopAnchor {
            return abs(visibleMinY) <= 24 && visibleMaxY > 24
        }

        let inset = min(24, visibleRect.height * 0.15)
        return visibleMaxY > inset && visibleMinY < (visibleRect.height - inset)
    }

    func isObservedMainColumnFocusTargetAligned(
        viewportKey: String,
        targetID: UUID,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool
    ) -> Bool {
        guard let frame = observedMainColumnTargetFrame(
            viewportKey: viewportKey,
            targetID: targetID
        ) else {
            return false
        }

        let visibleRect = resolvedMainColumnVisibleRect(
            viewportKey: viewportKey,
            viewportHeight: viewportHeight
        )
        let anchorY: CGFloat = prefersTopAnchor ? 0 : 0.4
        let visibleAnchorY = (frame.minY + (frame.height * anchorY)) - visibleRect.origin.y
        let desiredAnchorY = visibleRect.height * anchorY
        let tolerance: CGFloat = prefersTopAnchor ? 16 : 22
        return abs(visibleAnchorY - desiredAnchorY) <= tolerance
    }

    @discardableResult
    func performMainColumnNativeFocusScroll(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat,
        anchorY: CGFloat,
        animated: Bool
    ) -> Bool {
        guard observedMainColumnTargetFrame(
            viewportKey: viewportKey,
            targetID: targetID
        ) != nil else {
            return false
        }
        guard let scrollView = mainCanvasScrollCoordinator.scrollView(for: viewportKey) else {
            return false
        }
        let visible = scrollView.documentVisibleRect
        let resolvedViewportHeight = max(1, visible.height)
        guard let targetOffsetY = resolvedMainColumnFocusTargetOffset(
            viewportKey: viewportKey,
            cards: cards,
            targetID: targetID,
            viewportHeight: resolvedViewportHeight,
            anchorY: anchorY
        ) else {
            return false
        }

        let documentHeight = scrollView.documentView?.bounds.height ?? 0
        let maxY = max(0, documentHeight - visible.height)
        let targetReachable = maxY + 0.5 >= targetOffsetY

        if animated {
            guard targetReachable || targetOffsetY <= 0.5 else { return false }
            let resolvedTargetY = CaretScrollCoordinator.resolvedVerticalTargetY(
                visibleRect: visible,
                targetY: targetOffsetY,
                minY: 0,
                maxY: maxY,
                snapToPixel: true
            )
            guard abs(resolvedTargetY - visible.origin.y) > 0.5 else { return true }
            let appliedDuration = CaretScrollCoordinator.resolvedVerticalAnimationDuration(
                currentY: visible.origin.y,
                targetY: resolvedTargetY,
                viewportHeight: resolvedViewportHeight
            )
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                axis: "vertical",
                engine: "native",
                animated: true,
                target: "\(viewportKey)|\(targetID.uuidString)",
                expectedDuration: appliedDuration
            )
            suspendMainColumnViewportCapture(for: appliedDuration + 0.06)
            _ = CaretScrollCoordinator.applyAnimatedVerticalScrollIfNeeded(
                scrollView: scrollView,
                visibleRect: visible,
                targetY: targetOffsetY,
                minY: 0,
                maxY: maxY,
                deadZone: 0.5,
                snapToPixel: true,
                duration: appliedDuration
            )
            bounceDebugLog(
                "nativeMainColumnFocusScroll key=\(viewportKey) target=\(debugCardIDString(targetID)) " +
                "targetY=\(debugCGFloat(resolvedTargetY)) visibleY=\(debugCGFloat(visible.origin.y)) " +
                "duration=\(String(format: "%.2f", appliedDuration)) viewport=\(debugCGFloat(resolvedViewportHeight))"
            )
            return true
        }

        MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
            ownerKey: mainCanvasDiagnosticsOwnerKey,
            axis: "vertical",
            engine: "native",
            animated: false,
            target: "\(viewportKey)|\(targetID.uuidString)",
            expectedDuration: 0
        )
        suspendMainColumnViewportCapture(for: 0.12)
        let applied = CaretScrollCoordinator.applyVerticalScrollIfNeeded(
            scrollView: scrollView,
            visibleRect: visible,
            targetY: targetOffsetY,
            minY: 0,
            maxY: maxY,
            deadZone: 0.5,
            snapToPixel: true
        )
        if applied {
            bounceDebugLog(
                "nativeMainColumnFocusScroll immediate key=\(viewportKey) target=\(debugCardIDString(targetID)) " +
                "targetY=\(debugCGFloat(targetOffsetY)) visibleY=\(debugCGFloat(visible.origin.y))"
            )
        }
        let resolvedTargetY = CaretScrollCoordinator.resolvedVerticalTargetY(
            visibleRect: visible,
            targetY: targetOffsetY,
            minY: 0,
            maxY: maxY,
            snapToPixel: true
        )
        let currentY = scrollView.contentView.bounds.origin.y
        return targetReachable && abs(resolvedTargetY - currentY) <= 0.5
    }

    func shouldSkipMainColumnFocusScroll(
        targetID: UUID,
        cards: [SceneCard],
        level: Int,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool
    ) -> Bool {
        guard prefersTopAnchor else { return false }
        guard activeCardID == targetID else { return false }
        let viewportKey = mainColumnViewportStorageKey(level: level)
        guard let frame = observedMainColumnTargetFrame(
            viewportKey: viewportKey,
            targetID: targetID
        ) else {
            return false
        }

        let visibleRect = resolvedMainColumnVisibleRect(
            viewportKey: viewportKey,
            viewportHeight: viewportHeight
        )
        let deadZone: CGFloat = 3
        let delta = frame.minY - visibleRect.origin.y
        let shouldSkip = abs(delta) <= deadZone
        if shouldSkip {
            bounceDebugLog(
                "shouldSkipMainColumnFocusScroll target=\(debugCardIDString(targetID)) viewportKey=\(viewportKey) " +
                "offset=\(debugCGFloat(visibleRect.origin.y)) targetMin=\(debugCGFloat(frame.minY)) " +
                "delta=\(debugCGFloat(delta)) " +
                "\(debugMainColumnObservedTargetSummary(viewportKey: viewportKey, targetID: targetID, offsetY: visibleRect.origin.y))"
            )
        }
        return shouldSkip
    }

    func shouldAutoAlignMainColumn(cards: [SceneCard], activeID: UUID?) -> Bool {
        guard let activeID else { return false }
        if cards.contains(where: { $0.id == activeID }) {
            return true
        }
        return cards.contains(where: { activeAncestorIDs.contains($0.id) })
    }

    func resolvedMainColumnLayoutSnapshot(
        in cards: [SceneCard],
        viewportHeight: CGFloat
    ) -> MainColumnLayoutSnapshot {
        let layoutResolveStartedAt = CACurrentMediaTime()
        let cardIDs = cards.map(\.id)
        let editingCardInColumn = editingCardID.flatMap { editingID in
            cards.first(where: { $0.id == editingID })
        }
        let editingLiveHeightOverride = editingCardInColumn.flatMap { card in
            resolvedMainCardLiveEditingHeightOverride(for: card)
        }
        let editingHeightBucket = editingLiveHeightOverride.map { Int(($0 * 10).rounded()) } ?? -1
        let layoutKey = MainColumnLayoutCacheKey(
            recordsVersion: scenario.cardsVersion,
            contentVersion: scenario.cardContentSaveVersion,
            viewportHeightBucket: Int(viewportHeight.rounded()),
            fontSizeBucket: Int((fontSize * 10).rounded()),
            lineSpacingBucket: Int((mainCardLineSpacingValue * 10).rounded()),
            editingCardID: editingCardInColumn?.id,
            editingHeightBucket: editingHeightBucket,
            cardIDs: cardIDs
        )
        let containsEditingCard = editingCardInColumn != nil
        if let cached = mainColumnLayoutSnapshotByKey[layoutKey] {
            MainCanvasNavigationDiagnostics.shared.recordColumnLayoutResolve(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                cardCount: cards.count,
                viewportHeight: viewportHeight,
                cacheHit: true,
                containsEditingCard: containsEditingCard,
                durationMilliseconds: (CACurrentMediaTime() - layoutResolveStartedAt) * 1000
            )
            return cached
        }

        let centerGapHeight = max(0, CGFloat(mainCardVerticalGap))
        var cursorY = viewportHeight * 0.4
        var framesByCardID: [UUID: MainColumnLayoutFrame] = [:]
        framesByCardID.reserveCapacity(cards.count)

        for index in cards.indices {
            let card = cards[index]
            let cardHeight = resolvedMainCardHeight(
                for: card,
                liveEditingHeightOverride: card.id == editingCardInColumn?.id ? editingLiveHeightOverride : nil
            )
            let cardMinY = cursorY
            let cardMaxY = cardMinY + cardHeight
            framesByCardID[card.id] = MainColumnLayoutFrame(minY: cardMinY, maxY: cardMaxY)

            cursorY = cardMaxY
            if index < cards.count - 1 {
                let next = cards[index + 1]
                if card.parent?.id != next.parent?.id {
                    cursorY += mainParentGroupSeparatorHeight
                }
                cursorY += centerGapHeight
            }
        }

        let snapshot = MainColumnLayoutSnapshot(
            key: layoutKey,
            framesByCardID: framesByCardID,
            orderedCardIDs: cardIDs,
            contentBottomY: cursorY
        )
        mainColumnLayoutSnapshotByKey[layoutKey] = snapshot
        MainCanvasNavigationDiagnostics.shared.recordColumnLayoutResolve(
            ownerKey: mainCanvasDiagnosticsOwnerKey,
            cardCount: cards.count,
            viewportHeight: viewportHeight,
            cacheHit: false,
            containsEditingCard: containsEditingCard,
            durationMilliseconds: (CACurrentMediaTime() - layoutResolveStartedAt) * 1000
        )
        return snapshot
    }

    func resolvedMainColumnTargetLayout(
        in cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat
    ) -> (targetMinY: CGFloat, targetMaxY: CGFloat)? {
        guard let frame = resolvedMainColumnLayoutSnapshot(in: cards, viewportHeight: viewportHeight)
            .framesByCardID[targetID] else { return nil }
        return (frame.minY, frame.maxY)
    }

    func mainColumnScrollCacheKey(level: Int, parent: SceneCard?) -> String {
        let parentKey = parent?.id.uuidString ?? "root"
        return "\(level)|\(parentKey)"
    }

    @ViewBuilder
    func mainColumnScrollObserver(
        viewportKey: String,
        level: Int,
        parent: SceneCard?,
        cards: [SceneCard],
        viewportHeight: CGFloat
    ) -> some View {
        MainColumnScrollViewAccessor(
            scrollCoordinator: mainCanvasScrollCoordinator,
            columnKey: viewportKey,
            storedOffsetY: mainColumnViewportOffsetByKey[viewportKey]
        ) { originY in
            guard !showFocusMode else { return }
            let previous = mainColumnViewportOffsetByKey[viewportKey] ?? 0
            let suspended = Date() < mainColumnViewportCaptureSuspendedUntil
            let visibleSummary = debugMainColumnVisibleCardSummary(
                viewportKey: viewportKey,
                cards: cards,
                viewportHeight: viewportHeight,
                offsetY: originY
            )
            if suspended, abs(previous - originY) > 0.5 {
                bounceDebugLog(
                    "viewportOffset ignored level=\(level) key=\(viewportKey) requestKey=\(mainColumnScrollCacheKey(level: level, parent: parent)) " +
                    "prev=\(debugCGFloat(previous)) new=\(debugCGFloat(originY)) " +
                    "suspendedUntil=\(mainColumnViewportCaptureSuspendedUntil.timeIntervalSince1970) " +
                    "\(debugFocusStateSummary()) visible=\(visibleSummary)"
                )
                return
            }
            if abs(previous - originY) > 0.5 {
                mainColumnViewportOffsetByKey[viewportKey] = originY
                bounceDebugLog(
                    "viewportOffset level=\(level) key=\(viewportKey) requestKey=\(mainColumnScrollCacheKey(level: level, parent: parent)) " +
                    "prev=\(debugCGFloat(previous)) new=\(debugCGFloat(originY)) " +
                    "\(debugFocusStateSummary()) visible=\(visibleSummary)"
                )
            }
        }
    }

    func suspendMainColumnViewportCapture(for duration: TimeInterval) {
        let previous = mainColumnViewportCaptureSuspendedUntil
        let until = Date().addingTimeInterval(duration)
        if until > mainColumnViewportCaptureSuspendedUntil {
            mainColumnViewportCaptureSuspendedUntil = until
            bounceDebugLog(
                "suspendMainColumnViewportCapture duration=\(String(format: "%.2f", duration)) " +
                "previousUntil=\(previous.timeIntervalSince1970) newUntil=\(until.timeIntervalSince1970) " +
                "\(debugFocusStateSummary())"
            )
        }
    }

    func mainColumnViewportStorageKey(level: Int) -> String {
        if level <= 1 || isActiveCardRoot {
            return "level:\(level)|all"
        }
        let category = activeCategory ?? "all"
        return "level:\(level)|category:\(category)"
    }

    func shouldPreserveMainColumnViewportOnReveal(level: Int, storageKey: String, newActiveID: UUID?) -> Bool {
        guard level > 1 else { return false }
        guard (mainColumnViewportOffsetByKey[storageKey] ?? 0) > 1 else { return false }
        guard mainColumnViewportRestoreUntil > Date() else { return false }
        guard !shouldSuppressMainArrowRepeatAnimation() else { return false }
        guard let newActiveID, scenario.rootCards.contains(where: { $0.id == newActiveID }) else { return false }
        bounceDebugLog(
            "preserveMainColumnViewportOnReveal level=\(level) key=\(storageKey) " +
            "offset=\(debugCGFloat(mainColumnViewportOffsetByKey[storageKey] ?? 0)) " +
            "restoreUntil=\(mainColumnViewportRestoreUntil.timeIntervalSince1970) newActive=\(debugCardIDString(newActiveID)) " +
            "\(debugFocusStateSummary())"
        )
        return true
    }

    func shouldSuppressMainArrowRepeatAnimation() -> Bool {
        mainArrowRepeatAnimationSuppressedUntil > Date()
    }

    func cancelPendingMainColumnFocusWorkItem(for viewportKey: String) {
        if mainColumnPendingFocusWorkItemByKey[viewportKey] != nil {
            bounceDebugLog("cancelPendingMainColumnFocusWorkItem key=\(viewportKey)")
        }
        mainColumnPendingFocusWorkItemByKey[viewportKey]?.cancel()
        mainColumnPendingFocusWorkItemByKey[viewportKey] = nil
    }

    func cancelPendingMainColumnFocusVerificationWorkItem(for viewportKey: String) {
        if mainColumnPendingFocusVerificationWorkItemByKey[viewportKey] != nil {
            bounceDebugLog("cancelPendingMainColumnFocusVerificationWorkItem key=\(viewportKey)")
        }
        mainColumnPendingFocusVerificationWorkItemByKey[viewportKey]?.cancel()
        mainColumnPendingFocusVerificationWorkItemByKey[viewportKey] = nil
    }

    func cancelAllPendingMainColumnFocusWork() {
        let viewportKeys = Set(mainColumnPendingFocusWorkItemByKey.keys)
            .union(mainColumnPendingFocusVerificationWorkItemByKey.keys)
        for viewportKey in viewportKeys {
            cancelPendingMainColumnFocusWorkItem(for: viewportKey)
            cancelPendingMainColumnFocusVerificationWorkItem(for: viewportKey)
        }
        mainColumnLastFocusRequestByKey.removeAll(keepingCapacity: true)
    }

    func resolvedMainColumnFocusTargetID(in cards: [SceneCard]) -> UUID? {
        if let id = activeCardID, cards.contains(where: { $0.id == id }) {
            return id
        }
        if let target = cards.first(where: { activeAncestorIDs.contains($0.id) }) {
            return target.id
        }
        if let activeID = activeCardID,
           let activeCard = findCard(by: activeID) {
            let directChildren = cards.filter { $0.parent?.id == activeID }
            if let rememberedID = activeCard.lastSelectedChildID,
               directChildren.contains(where: { $0.id == rememberedID }) {
                return rememberedID
            }
            return directChildren.first?.id
        }
        return nil
    }

    func isMainColumnFocusTargetVisible(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool
    ) -> Bool {
        _ = cards
        return isObservedMainColumnFocusTargetVisible(
            viewportKey: viewportKey,
            targetID: targetID,
            viewportHeight: viewportHeight,
            prefersTopAnchor: prefersTopAnchor
        )
    }

    func isMainColumnFocusTargetAligned(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool
    ) -> Bool {
        _ = cards
        return isObservedMainColumnFocusTargetAligned(
            viewportKey: viewportKey,
            targetID: targetID,
            viewportHeight: viewportHeight,
            prefersTopAnchor: prefersTopAnchor
        )
    }

    func applyMainColumnFocusAlignment(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool,
        animated: Bool
    ) {
        let defaultAnchor = UnitPoint(x: 0.5, y: 0.4)
        let focusAnchor = prefersTopAnchor ? UnitPoint(x: 0.5, y: 0.0) : defaultAnchor
        let focusAnchorY = prefersTopAnchor ? CGFloat(0) : CGFloat(defaultAnchor.y)

        if performMainColumnNativeFocusScroll(
            viewportKey: viewportKey,
            cards: cards,
            targetID: targetID,
            viewportHeight: viewportHeight,
            anchorY: focusAnchorY,
            animated: animated
        ) {
            return
        }

        suspendMainColumnViewportCapture(for: animated ? 0.32 : 0.12)
        if animated {
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                axis: "vertical",
                engine: "proxy",
                animated: true,
                target: "\(viewportKey)|\(targetID.uuidString)",
                expectedDuration: 0.24
            )
            withAnimation(quickEaseAnimation) {
                proxy.scrollTo(targetID, anchor: focusAnchor)
            }
        } else {
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                axis: "vertical",
                engine: "proxy",
                animated: false,
                target: "\(viewportKey)|\(targetID.uuidString)",
                expectedDuration: 0
            )
            performWithoutAnimation {
                proxy.scrollTo(targetID, anchor: focusAnchor)
            }
        }
    }

    func resolvedMainColumnVisibilityTargetOffset(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool,
        editingRevealEdge: MainEditingViewportRevealEdge?
    ) -> CGFloat? {
        let frame =
            observedMainColumnTargetFrame(
                viewportKey: viewportKey,
                targetID: targetID
            ) ??
            predictedMainColumnTargetFrame(
                cards: cards,
                targetID: targetID,
                viewportHeight: viewportHeight
            )
        guard let frame else { return nil }

        let visibleRect = resolvedMainColumnVisibleRect(
            viewportKey: viewportKey,
            viewportHeight: viewportHeight
        )
        let inset = min(28, visibleRect.height * 0.08)
        let mainEditingCaretBottomPadding: CGFloat = 120
        if let editingRevealEdge {
            switch editingRevealEdge {
            case .top:
                // Entering a card at its start should only reveal the first line,
                // not snap the whole tall card to the top of the viewport.
                return max(0, frame.minY - (visibleRect.height - inset))
            case .bottom:
                // Match the main editor caret-visibility bottom padding so the
                // card-level reveal and the follow-up caret ensure resolve to
                // the same resting offset instead of causing a second nudge.
                return max(0, frame.maxY - (visibleRect.height - mainEditingCaretBottomPadding))
            }
        }
        if prefersTopAnchor {
            return max(0, frame.minY)
        }
        if frame.minY < visibleRect.minY + inset {
            return max(0, frame.minY - inset)
        }
        if frame.maxY > visibleRect.maxY - inset {
            return frame.maxY - (visibleRect.height - inset)
        }
        return visibleRect.origin.y
    }

    @discardableResult
    func performMainColumnNativeVisibilityScroll(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool,
        editingRevealEdge: MainEditingViewportRevealEdge?,
        animated: Bool
    ) -> Bool {
        guard observedMainColumnTargetFrame(
            viewportKey: viewportKey,
            targetID: targetID
        ) != nil else {
            return false
        }
        guard let scrollView = mainCanvasScrollCoordinator.scrollView(for: viewportKey) else {
            return false
        }
        let visible = scrollView.documentVisibleRect
        let resolvedViewportHeight = max(1, visible.height)
        guard let targetOffsetY = resolvedMainColumnVisibilityTargetOffset(
            viewportKey: viewportKey,
            cards: cards,
            targetID: targetID,
            viewportHeight: resolvedViewportHeight,
            prefersTopAnchor: prefersTopAnchor,
            editingRevealEdge: editingRevealEdge
        ) else {
            return false
        }

        let documentHeight = scrollView.documentView?.bounds.height ?? 0
        let maxY = max(0, documentHeight - visible.height)
        let targetReachable = maxY + 0.5 >= targetOffsetY

        if animated {
            guard targetReachable || targetOffsetY <= 0.5 else { return false }
            let resolvedTargetY = CaretScrollCoordinator.resolvedVerticalTargetY(
                visibleRect: visible,
                targetY: targetOffsetY,
                minY: 0,
                maxY: maxY,
                snapToPixel: true
            )
            guard abs(resolvedTargetY - visible.origin.y) > 0.5 else { return true }
            let appliedDuration = CaretScrollCoordinator.resolvedVerticalAnimationDuration(
                currentY: visible.origin.y,
                targetY: resolvedTargetY,
                viewportHeight: resolvedViewportHeight
            )
            suspendMainColumnViewportCapture(for: appliedDuration + 0.06)
            _ = CaretScrollCoordinator.applyAnimatedVerticalScrollIfNeeded(
                scrollView: scrollView,
                visibleRect: visible,
                targetY: targetOffsetY,
                minY: 0,
                maxY: maxY,
                deadZone: 0.5,
                snapToPixel: true,
                duration: appliedDuration
            )
            return true
        }

        suspendMainColumnViewportCapture(for: 0.12)
        _ = CaretScrollCoordinator.applyVerticalScrollIfNeeded(
            scrollView: scrollView,
            visibleRect: visible,
            targetY: targetOffsetY,
            minY: 0,
            maxY: maxY,
            deadZone: 0.5,
            snapToPixel: true
        )
        let resolvedTargetY = CaretScrollCoordinator.resolvedVerticalTargetY(
            visibleRect: visible,
            targetY: targetOffsetY,
            minY: 0,
            maxY: maxY,
            snapToPixel: true
        )
        let currentY = scrollView.contentView.bounds.origin.y
        return targetReachable && abs(resolvedTargetY - currentY) <= 0.5
    }

    func applyMainColumnFocusVisibility(
        viewportKey: String,
        cards: [SceneCard],
        targetID: UUID,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool,
        editingRevealEdge: MainEditingViewportRevealEdge?,
        animated: Bool
    ) {
        if performMainColumnNativeVisibilityScroll(
            viewportKey: viewportKey,
            cards: cards,
            targetID: targetID,
            viewportHeight: viewportHeight,
            prefersTopAnchor: prefersTopAnchor,
            editingRevealEdge: editingRevealEdge,
            animated: animated
        ) {
            return
        }

        let visibleRect = resolvedMainColumnVisibleRect(
            viewportKey: viewportKey,
            viewportHeight: viewportHeight
        )
        let frame =
            observedMainColumnTargetFrame(
                viewportKey: viewportKey,
                targetID: targetID
            ) ??
            predictedMainColumnTargetFrame(
                cards: cards,
                targetID: targetID,
                viewportHeight: viewportHeight
            )
        guard let frame else { return }

        let inset = min(28, visibleRect.height * 0.08)
        let anchor: UnitPoint
        if let editingRevealEdge {
            anchor = editingRevealEdge == .top ? .top : .bottom
        } else {
            let useTopAnchor = prefersTopAnchor || frame.minY < visibleRect.minY + inset
            anchor = useTopAnchor ? .top : .bottom
        }

        suspendMainColumnViewportCapture(for: animated ? 0.32 : 0.12)
        if animated {
            withAnimation(quickEaseAnimation) {
                proxy.scrollTo(targetID, anchor: anchor)
            }
        } else {
            performWithoutAnimation {
                proxy.scrollTo(targetID, anchor: anchor)
            }
        }
    }

    func scheduleMainColumnFocusVerification(
        viewportKey: String,
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        targetID: UUID,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        prefersTopAnchor: Bool,
        keepVisibleOnly: Bool,
        editingRevealEdge: MainEditingViewportRevealEdge?,
        animated: Bool,
        attempt: Int = 0,
        authority: MainVerticalScrollAuthority? = nil
    ) {
        cancelPendingMainColumnFocusVerificationWorkItem(for: viewportKey)
        let delay: TimeInterval
        if animated {
            delay = attempt == 0 ? 0.18 : 0.10
        } else {
            delay = attempt == 0 ? 0.05 : 0.08
        }
        let requestKey = mainColumnScrollCacheKey(level: level, parent: parent)
        var verificationWorkItem: DispatchWorkItem?
        verificationWorkItem = DispatchWorkItem {
            defer {
                if let verificationWorkItem,
                   mainColumnPendingFocusVerificationWorkItemByKey[viewportKey] === verificationWorkItem {
                    mainColumnPendingFocusVerificationWorkItemByKey[viewportKey] = nil
                }
            }

            guard !showFocusMode else { return }
            guard acceptsKeyboardInput else { return }
            guard isMainVerticalScrollAuthorityCurrent(authority, viewportKey: viewportKey) else { return }
            guard resolvedMainColumnFocusTargetID(in: cards) == targetID else { return }
            let hasObservedTargetFrame = observedMainColumnTargetFrame(
                viewportKey: viewportKey,
                targetID: targetID
            ) != nil
            let targetIsVisible = isMainColumnFocusTargetVisible(
                viewportKey: viewportKey,
                cards: cards,
                targetID: targetID,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor
            )
            let targetIsAligned = hasObservedTargetFrame && isMainColumnFocusTargetAligned(
                viewportKey: viewportKey,
                cards: cards,
                targetID: targetID,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor
            )
            if hasObservedTargetFrame && targetIsVisible && (keepVisibleOnly || targetIsAligned) {
                return
            }
            if !hasObservedTargetFrame {
                guard attempt < 4 else { return }
                scheduleMainColumnFocusVerification(
                    viewportKey: viewportKey,
                    cards: cards,
                    level: level,
                    parent: parent,
                    targetID: targetID,
                    proxy: proxy,
                    viewportHeight: viewportHeight,
                    prefersTopAnchor: prefersTopAnchor,
                    keepVisibleOnly: keepVisibleOnly,
                    editingRevealEdge: editingRevealEdge,
                    animated: animated,
                    attempt: attempt + 1,
                    authority: authority
                )
                return
            }

            bounceDebugLog(
                "verifyMainColumnFocus retry level=\(level) viewportKey=\(viewportKey) " +
                "attempt=\(attempt) target=\(debugCardIDString(targetID)) " +
                "observed=\(hasObservedTargetFrame) " +
                "offset=\(debugCGFloat(resolvedMainColumnCurrentOffsetY(viewportKey: viewportKey))) " +
                "\(debugMainColumnObservedTargetSummary(viewportKey: viewportKey, targetID: targetID, offsetY: resolvedMainColumnCurrentOffsetY(viewportKey: viewportKey)))"
            )
            mainColumnLastFocusRequestByKey.removeValue(forKey: requestKey)
            let retryAnimated = animated && hasObservedTargetFrame
            MainCanvasNavigationDiagnostics.shared.recordVerificationRetry(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                viewportKey: viewportKey,
                attempt: attempt,
                targetID: targetID,
                observedFrame: hasObservedTargetFrame,
                animatedRetry: retryAnimated
            )
            if keepVisibleOnly {
                applyMainColumnFocusVisibility(
                    viewportKey: viewportKey,
                    cards: cards,
                    targetID: targetID,
                    proxy: proxy,
                    viewportHeight: viewportHeight,
                    prefersTopAnchor: prefersTopAnchor,
                    editingRevealEdge: editingRevealEdge,
                    animated: retryAnimated
                )
            } else {
                applyMainColumnFocusAlignment(
                    viewportKey: viewportKey,
                    cards: cards,
                    targetID: targetID,
                    proxy: proxy,
                    viewportHeight: viewportHeight,
                    prefersTopAnchor: prefersTopAnchor,
                    animated: retryAnimated
                )
            }
            guard attempt < (hasObservedTargetFrame ? 2 : 4) else { return }
            scheduleMainColumnFocusVerification(
                viewportKey: viewportKey,
                cards: cards,
                level: level,
                parent: parent,
                targetID: targetID,
                proxy: proxy,
                viewportHeight: viewportHeight,
                prefersTopAnchor: prefersTopAnchor,
                keepVisibleOnly: keepVisibleOnly,
                editingRevealEdge: editingRevealEdge,
                animated: animated,
                attempt: attempt + 1,
                authority: authority
            )
        }
        if let verificationWorkItem {
            mainColumnPendingFocusVerificationWorkItemByKey[viewportKey] = verificationWorkItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: verificationWorkItem)
        }
    }

    func handleMainColumnNavigationSettle(
        viewportKey: String,
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat
    ) {
        guard !showFocusMode else { return }
        guard acceptsKeyboardInput else { return }
        guard editingCardID == nil else { return }
        cancelPendingMainColumnFocusWorkItem(for: viewportKey)
        cancelPendingMainColumnFocusVerificationWorkItem(for: viewportKey)
        guard shouldAutoAlignMainColumn(cards: cards, activeID: activeCardID) else { return }
        let authority = beginMainVerticalScrollAuthority(
            viewportKey: viewportKey,
            kind: .columnNavigation,
            targetCardID: activeCardID
        )
        bounceDebugLog(
            "navigationSettle level=\(level) viewportKey=\(viewportKey) " +
            "active=\(debugCardIDString(activeCardID)) " +
            "offset=\(debugCGFloat(mainColumnViewportOffsetByKey[viewportKey] ?? 0)) " +
            "visible=\(debugMainColumnVisibleCardSummary(viewportKey: viewportKey, cards: cards, viewportHeight: viewportHeight, offsetY: mainColumnViewportOffsetByKey[viewportKey] ?? 0))"
        )
        scrollToFocus(
            in: cards,
            level: level,
            parent: parent,
            proxy: proxy,
            viewportHeight: viewportHeight,
            animated: false,
            reason: "navigationSettle",
            authority: authority
        )
    }

    func scheduleMainColumnActiveCardFocus(
        viewportKey: String,
        expectedActiveID: UUID?,
        cards: [SceneCard],
        level: Int,
        parent: SceneCard?,
        proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        keepVisibleOnly: Bool,
        editingRevealEdge: MainEditingViewportRevealEdge?,
        forceAlignment: Bool,
        animated: Bool,
        intentID: Int? = nil,
        authority: MainVerticalScrollAuthority? = nil
    ) {
        cancelPendingMainColumnFocusWorkItem(for: viewportKey)
        bounceDebugLog(
            "scheduleMainColumnActiveCardFocus level=\(level) viewportKey=\(viewportKey) " +
            "expected=\(debugCardIDString(expectedActiveID)) parent=\(debugCardToken(parent)) " +
            "cards=\(cards.count) force=\(forceAlignment) animated=\(animated) \(debugFocusStateSummary())"
        )
        let focusDelay: TimeInterval = animated ? 0.01 : 0.0
        let workItem = DispatchWorkItem {
            defer { mainColumnPendingFocusWorkItemByKey[viewportKey] = nil }
            bounceDebugLog(
                "executeMainColumnActiveCardFocus level=\(level) viewportKey=\(viewportKey) " +
                "expected=\(debugCardIDString(expectedActiveID)) current=\(debugCardIDString(activeCardID)) " +
                "\(debugFocusStateSummary())"
            )
            if let intentID,
               !mainCanvasScrollCoordinator.isIntentCurrent(intentID, for: viewportKey) {
                bounceDebugLog(
                    "activeCardFocus staleIntent level=\(level) viewportKey=\(viewportKey) intent=\(intentID)"
                )
                return
            }
            guard isMainVerticalScrollAuthorityCurrent(authority, viewportKey: viewportKey) else {
                bounceDebugLog(
                    "activeCardFocus staleAuthority level=\(level) viewportKey=\(viewportKey)"
                )
                return
            }
            guard activeCardID == expectedActiveID else {
                bounceDebugLog(
                    "activeCardFocus stale level=\(level) viewportKey=\(viewportKey) " +
                    "expected=\(expectedActiveID?.uuidString ?? "nil") current=\(activeCardID?.uuidString ?? "nil")"
                )
                return
            }
            scrollToFocus(
                in: cards,
                level: level,
                parent: parent,
                proxy: proxy,
                viewportHeight: viewportHeight,
                keepVisibleOnly: keepVisibleOnly,
                editingRevealEdge: editingRevealEdge,
                forceAlignment: forceAlignment,
                animated: animated,
                reason: "activeCardChange",
                authority: authority
            )
        }
        mainColumnPendingFocusWorkItemByKey[viewportKey] = workItem
        if focusDelay <= 0 {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + focusDelay, execute: workItem)
        }
    }

    func requestMainBottomRevealIfNeeded(
        currentLevel: [SceneCard],
        currentIndex: Int,
        card: SceneCard
    ) -> Bool {
        guard currentIndex == currentLevel.count - 1 else { return false }
        guard activeCardID == card.id else { return false }
        bounceDebugLog("requestMainBottomRevealIfNeeded target=\(debugCardToken(card)) levelCount=\(currentLevel.count)")
        mainBottomRevealCardID = card.id
        mainBottomRevealTick += 1
        return true
    }

    func resolvedMainCardLiveEditingHeightOverride(for card: SceneCard) -> CGFloat? {
        guard editingCardID == card.id else { return nil }
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
              textView.string == card.content,
              let liveBodyHeight = sharedLiveTextViewBodyHeight(textView) else { return nil }
        return ceil(liveBodyHeight + 48)
    }

    func resolvedMainCardHeightCacheKey(
        for card: SceneCard,
        mode: MainCardHeightMode
    ) -> MainCardHeightCacheKey {
        let lineSpacingBucket = Int((CGFloat(mainCardLineSpacingValue) * 10).rounded())
        let fontSizeBucket = Int((CGFloat(fontSize) * 10).rounded())

        let measuringText: String
        let width: CGFloat
        switch mode {
        case .display:
            measuringText = card.content.isEmpty ? "내용 없음" : card.content
            width = max(1, MainCanvasLayoutMetrics.cardWidth - (MainEditorLayoutMetrics.mainCardContentPadding * 2))
        case .editingFallback:
            measuringText = card.content
            width = max(1, MainCanvasLayoutMetrics.textWidth)
        }

        let normalizedText = normalizedSharedMeasurementText(measuringText)
        return MainCardHeightCacheKey(
            cardID: card.id,
            contentFingerprint: sharedStableTextFingerprint(normalizedText),
            textLength: normalizedText.utf16.count,
            widthBucket: Int((width * 10).rounded()),
            fontSizeBucket: fontSizeBucket,
            lineSpacingBucket: lineSpacingBucket,
            mode: mode
        )
    }

    func storeMainCardHeightRecord(_ record: MainCardHeightRecord) {
        if mainCardHeightRecordByKey.count >= 4096 {
            mainCardHeightRecordByKey.removeAll(keepingCapacity: true)
        }
        mainCardHeightRecordByKey[record.key] = record
    }

    func resolvedMainCardHeightRecord(
        for card: SceneCard,
        liveEditingHeightOverride: CGFloat? = nil
    ) -> MainCardHeightRecord {
        if let liveEditingHeightOverride {
            let record = MainCardHeightRecord(
                key: resolvedMainCardHeightCacheKey(for: card, mode: .editingFallback),
                height: liveEditingHeightOverride
            )
            return record
        }

        let lineSpacing = CGFloat(mainCardLineSpacingValue)
        let resolvedFontSize = CGFloat(fontSize)

        if editingCardID == card.id {
            let recordKey = resolvedMainCardHeightCacheKey(for: card, mode: .editingFallback)
            if let cached = mainCardHeightRecordByKey[recordKey] {
                return cached
            }

            let editorBodyHeight = sharedMeasuredTextBodyHeight(
                text: card.content,
                fontSize: resolvedFontSize,
                lineSpacing: lineSpacing,
                width: MainCanvasLayoutMetrics.textWidth,
                lineFragmentPadding: MainEditorLayoutMetrics.mainEditorLineFragmentPadding,
                safetyInset: 0
            )
            let record = MainCardHeightRecord(
                key: recordKey,
                height: ceil(editorBodyHeight + 48)
            )
            storeMainCardHeightRecord(record)
            return record
        }

        let displayText = card.content.isEmpty ? "내용 없음" : card.content
        let displayWidth = max(1, MainCanvasLayoutMetrics.cardWidth - (MainEditorLayoutMetrics.mainCardContentPadding * 2))
        let recordKey = resolvedMainCardHeightCacheKey(for: card, mode: .display)
        if let cached = mainCardHeightRecordByKey[recordKey] {
            return cached
        }

        let displayBodyHeight = sharedMeasuredTextBodyHeight(
            text: displayText,
            fontSize: resolvedFontSize,
            lineSpacing: lineSpacing,
            width: displayWidth,
            lineFragmentPadding: 0,
            safetyInset: 0
        )
        let record = MainCardHeightRecord(
            key: recordKey,
            height: ceil(displayBodyHeight + (MainEditorLayoutMetrics.mainCardContentPadding * 2))
        )
        storeMainCardHeightRecord(record)
        return record
    }

    func resolvedMainCardHeight(
        for card: SceneCard,
        liveEditingHeightOverride: CGFloat? = nil
    ) -> CGFloat {
        if let liveEditingHeightOverride {
            return liveEditingHeightOverride
        }
        if editingCardID == card.id,
           let liveBodyHeight = resolvedMainCardLiveEditingHeightOverride(for: card) {
            return liveBodyHeight
        }
        return resolvedMainCardHeightRecord(for: card).height
    }

    @ViewBuilder
    func cardRow(_ card: SceneCard, proxy: ScrollViewProxy) -> some View {
        let isAICandidate = aiCandidateState.cardIDs.contains(card.id) || card.isAICandidate
        let isPlotLineCard = card.category == ScenarioCardCategory.plot
        let canCreateUpperCard = canCreateUpperCardFromSelection(contextCard: card)
        let canSummarizeChildren = canSummarizeDirectChildren(for: card)
        let isCloneLinked = scenario.isCardCloned(card.id)
        let hasLinkedCards = scenario.hasLinkedCards(card.id)
        let isLinkedCard = scenario.isLinkedCard(card.id)
        let clonePeerDestinations = isCloneLinked ? clonePeerMenuDestinations(for: card) : []
        CardItem(
            card: card,
            renderSettings: mainCardRenderSettings,
            isActive: activeCardID == card.id,
            isSelected: selectedCardIDs.contains(card.id),
            isMultiSelected: selectedCardIDs.count > 1 && selectedCardIDs.contains(card.id),
            isArchived: card.isArchived,
            isAncestor: activeAncestorIDs.contains(card.id) || activeSiblingIDs.contains(card.id),
            isDescendant: activeDescendantIDs.contains(card.id),
            isEditing: !showFocusMode && acceptsKeyboardInput && editingCardID == card.id,
            preferredTextMeasureWidth: MainCanvasLayoutMetrics.textWidth,
            forceNamedSnapshotNoteStyle: false,
            forceCustomColorVisibility: isAICandidate,
            onInsertSiblingAbove: { insertSibling(relativeTo: card, above: true) },
            onInsertSiblingBelow: { insertSibling(relativeTo: card, above: false) },
            onAddChildCard: { addChildCard(to: card) },
            onDropBefore: { providers, includeTrailingSiblingBlock in
                handleGeneralDrop(
                    providers,
                    target: .before(card.id),
                    includeTrailingSiblingBlock: includeTrailingSiblingBlock
                )
            },
            onDropAfter: { providers, includeTrailingSiblingBlock in
                handleGeneralDrop(
                    providers,
                    target: .after(card.id),
                    includeTrailingSiblingBlock: includeTrailingSiblingBlock
                )
            },
            onDropOnto: { providers, includeTrailingSiblingBlock in
                handleGeneralDrop(
                    providers,
                    target: .onto(card.id),
                    includeTrailingSiblingBlock: includeTrailingSiblingBlock
                )
            },
            onSelect: { handleMainWorkspaceCardClick(card) },
            onDoubleClick: {
                beginCardEditing(card)
            },
            onEndEdit: { finishEditing() },
            onSelectAtLocation: { location in
                handleMainWorkspaceCardClick(card, clickLocation: location)
            },
            onContentChange: { oldValue, newValue in
                handleMainEditorContentChange(cardID: card.id, oldValue: oldValue, newValue: newValue)
            },
            onColorChange: { hex in setCardColor(card, hex: hex) },
            onReferenceCard: { addCardToReferenceWindow(card) },
            onCreateUpperCardFromSelection: canCreateUpperCard ? {
                createUpperCardFromSelection(contextCard: card)
            } : nil,
            onSummarizeChildren: canSummarizeChildren ? {
                runChildSummaryFromCardContextMenu(for: card)
            } : nil,
            onAIElaborate: {
                runAICardActionFromContextMenu(for: card, action: .elaborate)
            },
            onAINextScene: {
                runAICardActionFromContextMenu(for: card, action: .nextScene)
            },
            onAIAlternative: {
                runAICardActionFromContextMenu(for: card, action: .alternative)
            },
            onAISummarizeCurrent: {
                runAICardActionFromContextMenu(for: card, action: .summary)
            },
            aiPlotActionsEnabled: isPlotLineCard,
            onApplyAICandidate: isAICandidate ? {
                applyAICandidateFromCardContextMenu(cardID: card.id)
            } : nil,
            isSummarizingChildren: aiChildSummaryLoadingCardIDs.contains(card.id),
            isAIBusy: aiIsGenerating,
            onHardDelete: { performHardDelete(card) },
            onTranscriptionMode: { startDictationMode(from: card) },
            isTranscriptionBusy: dictationIsRecording || dictationIsProcessing,
            isCloneLinked: isCloneLinked,
            hasLinkedCards: hasLinkedCards,
            isLinkedCard: isLinkedCard,
            onCloneCard: { copyCardsAsCloneFromContext(card) },
            clonePeerDestinations: clonePeerDestinations,
            onNavigateToClonePeer: { targetID in navigateToCloneCard(targetID) }
        )
        .id(card.id)
        .onDrag {
            MainCardDragSessionTracker.shared.begin()
            return NSItemProvider(object: card.id.uuidString as NSString)
        }
    }

    func clonePeerMenuDestinations(for card: SceneCard) -> [ClonePeerMenuDestination] {
        let peers = scenario.clonePeers(for: card.id)
        guard !peers.isEmpty else { return [] }
        let orderedPeers = peers.sorted { lhs, rhs in
            let l = scenario.cardLocationByID(lhs.id) ?? (Int.max, Int.max)
            let r = scenario.cardLocationByID(rhs.id) ?? (Int.max, Int.max)
            if l.level != r.level { return l.level < r.level }
            if l.index != r.index { return l.index < r.index }
            return lhs.createdAt < rhs.createdAt
        }
        let baseTitles = orderedPeers.map { cloneParentTitle(for: $0) }

        var titleCounts: [String: Int] = [:]
        for title in baseTitles {
            titleCounts[title, default: 0] += 1
        }

        var resolvedIndexByTitle: [String: Int] = [:]
        return orderedPeers.enumerated().map { offset, peer in
            let baseTitle = baseTitles[offset]
            let totalCount = titleCounts[baseTitle] ?? 0
            let index = (resolvedIndexByTitle[baseTitle] ?? 0) + 1
            resolvedIndexByTitle[baseTitle] = index
            let title = totalCount > 1 ? "\(baseTitle) (\(index))" : baseTitle
            return ClonePeerMenuDestination(id: peer.id, title: title)
        }
    }

    func cloneParentTitle(for card: SceneCard) -> String {
        if let parent = card.parent {
            let firstLine = firstMeaningfulLine(from: parent.content)
            if let firstLine {
                return firstLine
            }
            return "(내용 없는 부모 카드)"
        }
        return "(루트)"
    }

    func firstMeaningfulLine(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if trimmed.count <= 36 { return trimmed }
                let cutoff = trimmed.index(trimmed.startIndex, offsetBy: 36)
                return "\(trimmed[..<cutoff])..."
            }
        }
        return nil
    }

    func navigateToCloneCard(_ cardID: UUID) {
        guard let target = findCard(by: cardID) else { return }
        selectedCardIDs = [target.id]
        changeActiveCard(to: target)
        isMainViewFocused = true
    }

    @ViewBuilder
    func addFirstButton(level: Int) -> some View {
        Button { suppressMainFocusRestoreAfterFinishEditing = true; finishEditing(); addCard(at: level, parent: nil) } label: { Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.vertical, 8) }.buttonStyle(.plain)
    }

    // MARK: - Drag & Drop

    func handleGeneralDrop(
        _ providers: [NSItemProvider],
        target: DropTarget,
        includeTrailingSiblingBlock: Bool = false
    ) {
        guard let provider = providers.first else { return }
        provider.loadObject(ofClass: NSString.self) { string, _ in
            guard let uuidStr = string as? String, let draggedID = UUID(uuidString: uuidStr) else { return }
            DispatchQueue.main.async {
                MainCardDragSessionTracker.shared.end()
                guard let draggedCard = findCard(by: draggedID) else { return }
                if includeTrailingSiblingBlock {
                    let siblingBlock = trailingSiblingBlock(from: draggedCard)
                    if siblingBlock.count > 1 {
                        executeMoveSelection(siblingBlock, draggedCard: draggedCard, target: target)
                        return
                    }
                }
                let selectedCards = selectedCardIDs.compactMap { findCard(by: $0) }
                if selectedCardIDs.count > 1, selectedCardIDs.contains(draggedID) {
                    executeMoveSelection(selectedCards, draggedCard: draggedCard, target: target)
                } else {
                    executeMove(draggedCard, target: target)
                }
            }
        }
    }

    func executeMoveSelection(_ selectedCards: [SceneCard], draggedCard: SceneCard, target: DropTarget) {
        let movingRoots = movableRoots(from: selectedCards)
        guard !movingRoots.isEmpty else { return }

        if case .onto(let targetID) = target, movingRoots.contains(where: { $0.id == targetID }) { return }
        if let targetID = targetIDFrom(target), movingRoots.contains(where: { isDescendant($0, of: targetID) }) { return }

        let prevState = captureScenarioState()
        let destination = resolveDestination(target)
        let destinationParent = destination.parent
        var insertionIndex = destination.index
        let destinationParentID = destinationParent?.id
        let movingIDs = Set(movingRoots.map { $0.id })

        let movedBeforeDestination = movingRoots.filter {
            $0.parent?.id == destinationParentID && $0.orderIndex < insertionIndex
        }.count
        insertionIndex -= movedBeforeDestination
        if insertionIndex < 0 { insertionIndex = 0 }

        let oldParents = movingRoots.map { $0.parent }
        scenario.performBatchedCardMutation {
            let destinationSiblings = liveOrderedSiblings(parent: destinationParent)
            for sibling in destinationSiblings where !movingIDs.contains(sibling.id) && sibling.orderIndex >= insertionIndex {
                sibling.orderIndex += movingRoots.count
            }

            for (offset, card) in movingRoots.enumerated() {
                let previousParent = card.parent
                if card.isArchived {
                    card.isArchived = false
                }
                card.parent = destinationParent
                card.orderIndex = insertionIndex + offset
                card.isFloating = false
                synchronizeMovedSubtreeCategoryIfNeeded(
                    for: card,
                    oldParent: previousParent,
                    newParent: destinationParent
                )
            }

            normalizeAffectedParents(oldParents: oldParents, destinationParent: destinationParent)
        }

        selectedCardIDs = Set(movingRoots.map { $0.id })
        changeActiveCard(to: draggedCard)
        commitCardMutation(
            previousState: prevState,
            actionName: "카드 이동"
        )
    }

    func movableRoots(from cards: [SceneCard]) -> [SceneCard] {
        let selected = Set(cards.map { $0.id })
        let roots = cards.filter { card in
            var p = card.parent
            while let parent = p {
                if selected.contains(parent.id) { return false }
                p = parent.parent
            }
            return true
        }
        let rank = buildCanvasRank()
        return roots.sorted { lhs, rhs in
            let l = rank[lhs.id] ?? (Int.max, Int.max)
            let r = rank[rhs.id] ?? (Int.max, Int.max)
            if l.0 != r.0 { return l.0 < r.0 }
            if l.1 != r.1 { return l.1 < r.1 }
            return lhs.createdAt < rhs.createdAt
        }
    }

    func trailingSiblingBlock(from draggedCard: SceneCard) -> [SceneCard] {
        let siblings = liveOrderedSiblings(parent: draggedCard.parent)
        guard let startIndex = siblings.firstIndex(where: { $0.id == draggedCard.id }) else {
            return [draggedCard]
        }
        return Array(siblings[startIndex...])
    }

    func buildCanvasRank() -> [UUID: (Int, Int)] {
        let levels = resolvedAllLevels()
        var rank: [UUID: (Int, Int)] = Dictionary(minimumCapacity: scenario.cards.count)
        for (levelIndex, cards) in levels.enumerated() {
            for (index, card) in cards.enumerated() {
                rank[card.id] = (levelIndex, index)
            }
        }
        return rank
    }

    func resolveDestination(_ target: DropTarget) -> (parent: SceneCard?, index: Int) {
        switch target {
        case .before(let id):
            if let anchor = findCard(by: id) {
                return (anchor.parent, anchor.orderIndex)
            }
        case .after(let id):
            if let anchor = findCard(by: id) {
                return (anchor.parent, anchor.orderIndex + 1)
            }
        case .onto(let id):
            if let parent = findCard(by: id) {
                return (parent, liveOrderedSiblings(parent: parent).count)
            }
        case .columnTop(let pId):
            let parent = pId.flatMap { findCard(by: $0) }
            return (parent, 0)
        case .columnBottom(let pId):
            let parent = pId.flatMap { findCard(by: $0) }
            let count = liveOrderedSiblings(parent: parent).count
            return (parent, count)
        }
        return (nil, liveOrderedSiblings(parent: nil).count)
    }

    func normalizeAffectedParents(oldParents: [SceneCard?], destinationParent: SceneCard?) {
        var normalizedParentIDs: Set<UUID> = []
        var normalizedRoot = false
        for parent in oldParents {
            if let parent = parent {
                guard normalizedParentIDs.insert(parent.id).inserted else { continue }
                normalizeIndices(parent: parent)
            } else if !normalizedRoot {
                normalizeIndices(parent: nil)
                normalizedRoot = true
            }
        }
        if let destinationParent = destinationParent {
            guard normalizedParentIDs.insert(destinationParent.id).inserted else { return }
            normalizeIndices(parent: destinationParent)
        } else if !normalizedRoot {
            normalizeIndices(parent: nil)
        }
    }

    func executeMove(_ card: SceneCard, target: DropTarget) {
        if case .onto(let targetID) = target, targetID == card.id { return }
        if let targetID = targetIDFrom(target), isDescendant(card, of: targetID) { return }

        let prevState = captureScenarioState()
        scenario.performBatchedCardMutation {
            if card.isArchived {
                card.isArchived = false
            }

            let oldParent = card.parent
            normalizeIndices(parent: oldParent)

            switch target {
            case .before(let id):
                if let anchor = findCard(by: id) {
                    let newParent = anchor.parent
                    let newIndex = anchor.orderIndex
                    let newSiblings = liveOrderedSiblings(parent: newParent)
                    for s in newSiblings where s.orderIndex >= newIndex { s.orderIndex += 1 }
                    card.parent = newParent; card.orderIndex = newIndex
                }
            case .after(let id):
                if let anchor = findCard(by: id) {
                    let newParent = anchor.parent
                    let newIndex = anchor.orderIndex + 1
                    let newSiblings = liveOrderedSiblings(parent: newParent)
                    for s in newSiblings where s.orderIndex >= newIndex { s.orderIndex += 1 }
                    card.parent = newParent; card.orderIndex = newIndex
                }
            case .onto(let id):
                if let parent = findCard(by: id) {
                    card.parent = parent
                    card.orderIndex = liveOrderedSiblings(parent: parent).count
                }
            case .columnTop(let pId):
                let newParent = pId.flatMap { findCard(by: $0) }
                let newSiblings = liveOrderedSiblings(parent: newParent)
                for s in newSiblings { s.orderIndex += 1 }
                card.parent = newParent; card.orderIndex = 0
            case .columnBottom(let pId):
                let newParent = pId.flatMap { findCard(by: $0) }
                let newSiblings = liveOrderedSiblings(parent: newParent)
                card.parent = newParent; card.orderIndex = newSiblings.count
            }

            card.isFloating = false
            normalizeIndices(parent: card.parent)
            if oldParent?.id != card.parent?.id { normalizeIndices(parent: oldParent) }

            synchronizeMovedSubtreeCategoryIfNeeded(
                for: card,
                oldParent: oldParent,
                newParent: card.parent
            )
        }
        changeActiveCard(to: card)
        commitCardMutation(
            previousState: prevState,
            actionName: "카드 이동"
        )
    }

    func targetIDFrom(_ target: DropTarget) -> UUID? {
        switch target {
        case .before(let id), .after(let id), .onto(let id): return id
        default: return nil
        }
    }

    func liveOrderedSiblings(parent: SceneCard?) -> [SceneCard] {
        if !scenario.isCardMutationBatchInProgress {
            if let parent {
                return scenario.children(for: parent.id)
            }
            return scenario.rootCards
        }
        return scenario.cards
            .filter { candidate in
                guard !candidate.isArchived else { return false }
                if let parent {
                    return candidate.parent?.id == parent.id
                }
                return candidate.parent == nil && !candidate.isFloating
            }
            .sorted {
                if $0.orderIndex != $1.orderIndex {
                    return $0.orderIndex < $1.orderIndex
                }
                return $0.createdAt < $1.createdAt
            }
    }

    func synchronizeMovedSubtreeCategoryIfNeeded(
        for card: SceneCard,
        oldParent: SceneCard?,
        newParent: SceneCard?
    ) {
        let previousCategory = oldParent?.category
        let nextCategory = newParent?.category
        guard previousCategory != nextCategory || card.category != nextCategory else { return }
        card.updateDescendantsCategory(nextCategory)
    }

    func isDescendant(_ card: SceneCard, of targetID: UUID) -> Bool {
        var curr = findCard(by: targetID)?.parent
        while let p = curr { if p.id == card.id { return true }; curr = p.parent }; return false
    }

    func resolvedLevelsWithParents() -> [LevelData] {
        if resolvedLevelsWithParentsVersion == scenario.cardsVersion {
            return resolvedLevelsWithParentsCache
        }
        let levels = scenario.allLevels
        let resolved = levels.map { cards in
            LevelData(cards: cards, parent: cards.first?.parent)
        }
        resolvedLevelsWithParentsVersion = scenario.cardsVersion
        resolvedLevelsWithParentsCache = resolved
        return resolved
    }

    func displayedMainLevelsData(from levelsData: [LevelData]) -> [LevelData] {
        if isInactiveSplitPane {
            return levelsData.enumerated().map { index, data in
                LevelData(
                    cards: filteredCardsForMainCanvasColumn(levelIndex: index, cards: data.cards),
                    parent: data.parent
                )
            }
        }

        let cacheKey = DisplayedMainLevelsCacheKey(
            cardsVersion: scenario.cardsVersion,
            activeCategory: activeCategory,
            isActiveCardRoot: isActiveCardRoot
        )
        if displayedMainLevelsCacheKey == cacheKey {
            return displayedMainLevelsCache
        }

        let resolved = levelsData.enumerated().map { index, data in
            LevelData(
                cards: filteredCardsForMainCanvasColumn(levelIndex: index, cards: data.cards),
                parent: data.parent
            )
        }
        var locationByID: [UUID: (level: Int, index: Int)] = [:]
        for (levelIndex, data) in resolved.enumerated() {
            for (index, card) in data.cards.enumerated() {
                locationByID[card.id] = (levelIndex, index)
            }
        }
        displayedMainLevelsCacheKey = cacheKey
        displayedMainLevelsCache = resolved
        displayedMainCardLocationByIDCache = locationByID
        return resolved
    }

    func resolvedDisplayedMainLevelsWithParents() -> [LevelData] {
        displayedMainLevelsData(from: resolvedLevelsWithParents())
    }

    func resolvedDisplayedMainLevels() -> [[SceneCard]] {
        resolvedDisplayedMainLevelsWithParents().map(\.cards)
    }

    func displayedMainCardLocationByID(
        _ id: UUID,
        in levels: [[SceneCard]]
    ) -> (level: Int, index: Int)? {
        for (levelIndex, cards) in levels.enumerated() {
            if let index = cards.firstIndex(where: { $0.id == id }) {
                return (levelIndex, index)
            }
        }
        return nil
    }

    func displayedMainCardLocationByID(_ id: UUID) -> (level: Int, index: Int)? {
        let _ = resolvedDisplayedMainLevelsWithParents()
        return displayedMainCardLocationByIDCache[id]
    }

    func resolvedAllLevels() -> [[SceneCard]] {
        scenario.allLevels
    }

    func scrollToColumnIfNeeded(
        targetCardID: UUID,
        proxy: ScrollViewProxy,
        availableWidth: CGFloat,
        force: Bool = false,
        animated: Bool = true
    ) {
        if !acceptsKeyboardInput && !force { return }
        guard let targetLevel = displayedMainCardLocationByID(targetCardID)?.level else { return }
        let resolvedAvailableWidth = max(1, availableWidth)
        let scrollMode = mainCanvasHorizontalScrollMode
        let performScroll: (Int) -> Void = { level in
            if performMainCanvasHorizontalScroll(
                level: level,
                availableWidth: resolvedAvailableWidth,
                animated: animated
            ) {
                return
            }

            let hAnchor = resolvedMainCanvasHorizontalAnchor(availableWidth: resolvedAvailableWidth)
            if animated {
                MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                    ownerKey: mainCanvasDiagnosticsOwnerKey,
                    axis: "horizontal",
                    engine: "proxy",
                    animated: true,
                    target: "level:\(level)",
                    expectedDuration: 0.24
                )
                withAnimation(quickEaseAnimation) {
                    proxy.scrollTo(level, anchor: hAnchor)
                }
            } else {
                MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                    ownerKey: mainCanvasDiagnosticsOwnerKey,
                    axis: "horizontal",
                    engine: "proxy",
                    animated: false,
                    target: "level:\(level)",
                    expectedDuration: 0
                )
                performWithoutAnimation {
                    proxy.scrollTo(level, anchor: hAnchor)
                }
            }
        }
        switch scrollMode {
        case .oneStep:
            let desiredLevel = targetLevel
            if force || lastScrolledLevel != desiredLevel {
                lastScrolledLevel = desiredLevel
                performScroll(desiredLevel)
            }
        case .twoStep:
            if force {
                lastScrolledLevel = max(0, targetLevel - 1)
                performScroll(lastScrolledLevel)
                return
            }
            if lastScrolledLevel < 0 {
                lastScrolledLevel = max(0, targetLevel - 1)
                performScroll(lastScrolledLevel)
                return
            }
            if targetLevel < lastScrolledLevel {
                lastScrolledLevel = targetLevel
                performScroll(lastScrolledLevel)
            } else if targetLevel > lastScrolledLevel + 1 {
                lastScrolledLevel = targetLevel - 1
                performScroll(lastScrolledLevel)
            }
        }
    }

    func resolvedMainCanvasHorizontalAnchor(availableWidth: CGFloat) -> UnitPoint {
        let resolvedAvailableWidth = max(1, availableWidth)
        switch mainCanvasHorizontalScrollMode {
        case .oneStep:
            return UnitPoint(x: 0.5, y: 0.4)
        case .twoStep:
            let hOffset = (columnWidth / 2) / resolvedAvailableWidth
            return UnitPoint(x: 0.5 - hOffset, y: 0.4)
        }
    }

    func resolvedMainCanvasHorizontalTargetX(
        level: Int,
        availableWidth: CGFloat,
        visibleWidth: CGFloat
    ) -> CGFloat {
        let anchor = resolvedMainCanvasHorizontalAnchor(availableWidth: availableWidth)
        let leadingInset = availableWidth / 2
        let targetMinX = leadingInset + (CGFloat(level) * columnWidth)
        let targetAnchorX = targetMinX + (columnWidth * anchor.x)
        return targetAnchorX - (visibleWidth * anchor.x)
    }

    @discardableResult
    func performMainCanvasHorizontalScroll(
        level: Int,
        availableWidth: CGFloat,
        animated: Bool
    ) -> Bool {
        guard let scrollView = mainCanvasScrollCoordinator.resolvedMainCanvasHorizontalScrollView() else {
            return false
        }

        let visibleRect = scrollView.documentVisibleRect
        let documentWidth = scrollView.documentView?.bounds.width ?? 0
        let maxX = max(0, documentWidth - visibleRect.width)
        let targetX = resolvedMainCanvasHorizontalTargetX(
            level: level,
            availableWidth: availableWidth,
            visibleWidth: visibleRect.width
        )
        let targetReachable = maxX + 0.5 >= targetX

        if animated {
            guard targetReachable || targetX <= 0.5 else { return false }
            let resolvedTargetX = CaretScrollCoordinator.resolvedHorizontalTargetX(
                visibleRect: visibleRect,
                targetX: targetX,
                minX: 0,
                maxX: maxX,
                snapToPixel: true
            )
            guard abs(resolvedTargetX - visibleRect.origin.x) > 0.5 else { return true }
            let appliedDuration = CaretScrollCoordinator.resolvedHorizontalAnimationDuration(
                currentX: visibleRect.origin.x,
                targetX: resolvedTargetX,
                viewportWidth: visibleRect.width
            )
            MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
                ownerKey: mainCanvasDiagnosticsOwnerKey,
                axis: "horizontal",
                engine: "native",
                animated: true,
                target: "level:\(level)",
                expectedDuration: appliedDuration
            )
            _ = CaretScrollCoordinator.applyAnimatedHorizontalScrollIfNeeded(
                scrollView: scrollView,
                visibleRect: visibleRect,
                targetX: targetX,
                minX: 0,
                maxX: maxX,
                deadZone: 0.5,
                snapToPixel: true,
                duration: appliedDuration
            )
            bounceDebugLog(
                "nativeMainCanvasHorizontalScroll level=\(level) " +
                "targetX=\(debugCGFloat(resolvedTargetX)) visibleX=\(debugCGFloat(visibleRect.origin.x)) " +
                "duration=\(String(format: "%.2f", appliedDuration)) viewport=\(debugCGFloat(visibleRect.width))"
            )
            return true
        }

        MainCanvasNavigationDiagnostics.shared.beginScrollAnimation(
            ownerKey: mainCanvasDiagnosticsOwnerKey,
            axis: "horizontal",
            engine: "native",
            animated: false,
            target: "level:\(level)",
            expectedDuration: 0
        )
        let applied = CaretScrollCoordinator.applyHorizontalScrollIfNeeded(
            scrollView: scrollView,
            visibleRect: visibleRect,
            targetX: targetX,
            minX: 0,
            maxX: maxX,
            deadZone: 0.5,
            snapToPixel: true
        )
        if applied {
            bounceDebugLog(
                "nativeMainCanvasHorizontalScroll immediate level=\(level) " +
                "targetX=\(debugCGFloat(targetX)) visibleX=\(debugCGFloat(visibleRect.origin.x))"
            )
        }
        let resolvedTargetX = CaretScrollCoordinator.resolvedHorizontalTargetX(
            visibleRect: visibleRect,
            targetX: targetX,
            minX: 0,
            maxX: maxX,
            snapToPixel: true
        )
        let currentX = scrollView.contentView.bounds.origin.x
        return targetReachable && abs(resolvedTargetX - currentX) <= 0.5
    }

    // MARK: - Card Lookup & Active State

    func findCard(by id: UUID) -> SceneCard? { scenario.cardByID(id) }

    func resolvedActiveRelationFingerprint(
        sourceCardID: UUID?,
        cardsVersion: Int,
        ancestors: Set<UUID>,
        siblings: Set<UUID>,
        descendants: Set<UUID>
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(sourceCardID)
        hasher.combine(cardsVersion)
        hasher.combine(ancestors.count)
        for id in ancestors.sorted(by: { $0.uuidString < $1.uuidString }) {
            hasher.combine(id)
        }
        hasher.combine(siblings.count)
        for id in siblings.sorted(by: { $0.uuidString < $1.uuidString }) {
            hasher.combine(id)
        }
        hasher.combine(descendants.count)
        for id in descendants.sorted(by: { $0.uuidString < $1.uuidString }) {
            hasher.combine(id)
        }
        return hasher.finalize()
    }

    func resetActiveRelationStateCache() {
        if !activeAncestorIDs.isEmpty || !activeSiblingIDs.isEmpty || !activeDescendantIDs.isEmpty || activeRelationSourceCardID != nil {
            bounceDebugLog("resetActiveRelationStateCache \(debugFocusStateSummary())")
        }
        activeAncestorIDs = []
        activeSiblingIDs = []
        activeDescendantIDs = []
        activeRelationSourceCardID = nil
        activeRelationSourceCardsVersion = scenario.cardsVersion
        activeRelationFingerprint = resolvedActiveRelationFingerprint(
            sourceCardID: nil,
            cardsVersion: scenario.cardsVersion,
            ancestors: [],
            siblings: [],
            descendants: []
        )
    }

    func synchronizeActiveRelationState(for activeID: UUID?) {
        let relationSyncStartedAt = CACurrentMediaTime()
        if activeRelationSourceCardID == activeID,
           activeRelationSourceCardsVersion == scenario.cardsVersion {
            return
        }

        guard let activeID, let card = findCard(by: activeID) else {
            resetActiveRelationStateCache()
            return
        }

        var ancestors: Set<UUID> = []
        var parent = card.parent
        while let current = parent {
            ancestors.insert(current.id)
            parent = current.parent
        }

        let siblings = card.parent?.children ?? scenario.rootCards
        let siblingIDs = Set(siblings.map { $0.id }).filter { $0 != card.id }
        let descendantIDs = scenario.descendantIDs(for: card.id)
        let relationChanged =
            activeAncestorIDs != ancestors ||
            activeSiblingIDs != siblingIDs ||
            activeDescendantIDs != descendantIDs ||
            activeRelationSourceCardID != activeID ||
            activeRelationSourceCardsVersion != scenario.cardsVersion

        if activeAncestorIDs != ancestors { activeAncestorIDs = ancestors }
        if activeSiblingIDs != siblingIDs { activeSiblingIDs = siblingIDs }
        if activeDescendantIDs != descendantIDs { activeDescendantIDs = descendantIDs }
        activeRelationSourceCardID = activeID
        activeRelationSourceCardsVersion = scenario.cardsVersion
        activeRelationFingerprint = resolvedActiveRelationFingerprint(
            sourceCardID: activeID,
            cardsVersion: scenario.cardsVersion,
            ancestors: ancestors,
            siblings: siblingIDs,
            descendants: descendantIDs
        )
        if relationChanged {
            bounceDebugLog(
                "synchronizeActiveRelationState active=\(debugCardToken(card)) " +
                "ancestors=\(debugUUIDListSummary(ancestors.sorted { $0.uuidString < $1.uuidString }, limit: 8)) " +
                "siblings=\(siblingIDs.count) descendants=\(descendantIDs.count) version=\(scenario.cardsVersion)"
            )
        }
        MainCanvasNavigationDiagnostics.shared.recordRelationSync(
            ownerKey: mainCanvasDiagnosticsOwnerKey,
            activeCardID: activeID,
            durationMilliseconds: (CACurrentMediaTime() - relationSyncStartedAt) * 1000,
            ancestorCount: ancestors.count,
            siblingCount: siblingIDs.count,
            descendantCount: descendantIDs.count
        )
    }

    func changeActiveCard(
        to card: SceneCard,
        shouldFocusMain: Bool = true,
        deferToMainAsync: Bool = true,
        force: Bool = false
    ) {
        let debugStack = Thread.callStackSymbols
            .filter { $0.contains("/wa/") || $0.contains("WTF") }
            .prefix(6)
            .joined(separator: " | ")
        bounceDebugLog(
            "changeActiveCard requested target=\(card.id.uuidString) current=\(activeCardID?.uuidString ?? "nil") " +
            "pending=\(pendingActiveCardID?.uuidString ?? "nil") force=\(force) async=\(deferToMainAsync) " +
            "stack=\(debugStack)"
        )
        cleanupEmptyEditingCardIfNeeded(beforeSwitchingTo: card.id)
        if !force {
            if activeCardID == card.id, pendingActiveCardID == nil {
                bounceDebugLog("changeActiveCard ignoredAlreadyActive target=\(debugCardToken(card)) shouldFocus=\(shouldFocusMain)")
                if shouldFocusMain { isMainViewFocused = true }
                return
            }
            if pendingActiveCardID == card.id {
                bounceDebugLog("changeActiveCard ignoredPending target=\(debugCardToken(card)) shouldFocus=\(shouldFocusMain)")
                if shouldFocusMain { isMainViewFocused = true }
                return
            }
        } else {
            pendingActiveCardID = nil
        }
        pendingActiveCardID = card.id
        let apply = {
            defer { pendingActiveCardID = nil }
            let previousActiveID = activeCardID
            let previousRememberedChildID = card.parent?.lastSelectedChildID
            if activeCardID != card.id {
                lastActiveCardID = activeCardID
            }
            activeCardID = card.id
            if splitModeEnabled {
                scenario.setSplitPaneActiveCard(card.id, for: splitPaneID)
            }
            card.parent?.lastSelectedChildID = card.id
            synchronizeActiveRelationState(for: card.id)
            if shouldFocusMain { isMainViewFocused = true }
            let levelCount = scenario.allLevels.count
            if levelCount > maxLevelCount { maxLevelCount = levelCount }
            bounceDebugLog(
                "changeActiveCard applied target=\(debugCardToken(card)) previous=\(debugCardIDString(previousActiveID)) " +
                "parent=\(debugCardToken(card.parent)) parentRememberedBefore=\(debugCardIDString(previousRememberedChildID)) " +
                "parentRememberedAfter=\(debugCardIDString(card.parent?.lastSelectedChildID)) " +
                "levelCount=\(levelCount) \(debugFocusStateSummary())"
            )
        }
        if deferToMainAsync || !Thread.isMainThread {
            DispatchQueue.main.async { apply() }
        } else {
            apply()
        }
    }

    func cleanupEmptyEditingCardIfNeeded(beforeSwitchingTo targetCardID: UUID) {
        guard !isApplyingUndo else { return }
        guard let currentEditingID = editingCardID,
              currentEditingID != targetCardID,
              let currentCard = findCard(by: currentEditingID) else { return }
        guard currentCard.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        finishEditing()
    }

    func descendantIDSet(of card: SceneCard) -> Set<UUID> {
        scenario.descendantIDs(for: card.id)
    }

    // MARK: - Finish Editing

    struct FinishEditingContext {
        let cardID: UUID
        let inFocusMode: Bool
        let skipMainFocusRestore: Bool
        let startContent: String
        let startState: ScenarioState?
        let wasNewCard: Bool
        let newCardPrevState: ScenarioState?
    }

    func takeFinishEditingContext() -> FinishEditingContext? {
        let inFocusMode = showFocusMode
        let skipMainFocusRestore = suppressMainFocusRestoreAfterFinishEditing || inFocusMode
        suppressMainFocusRestoreAfterFinishEditing = false
        if inFocusMode {
            finalizeFocusTypingCoalescing(reason: "finish-editing")
        }
        guard let id = editingCardID else { return nil }
        if !inFocusMode {
            rememberMainCaretLocation(for: id)
        }
        let context = FinishEditingContext(
            cardID: id,
            inFocusMode: inFocusMode,
            skipMainFocusRestore: skipMainFocusRestore,
            startContent: editingStartContent,
            startState: editingStartState,
            wasNewCard: editingIsNewCard,
            newCardPrevState: pendingNewCardPrevState
        )
        resetEditingTransientState()
        return context
    }

    func resetEditingTransientState() {
        editingCardID = nil
        editingStartContent = ""
        editingIsNewCard = false
        editingStartState = nil
        pendingNewCardPrevState = nil
    }

    func runFinishEditingCommit(_ apply: @escaping () -> Void) {
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async { apply() }
        }
    }

    func finishEditing() {
        guard let context = takeFinishEditingContext() else { return }
        // Re-entrant finish events can arrive from multiple view layers.
        // Clear edit state first so the same edit cannot be committed twice.
        let apply = {
            commitFinishedEditingIfNeeded(
                id: context.cardID,
                inFocusMode: context.inFocusMode,
                startContent: context.startContent,
                startState: context.startState,
                wasNewCard: context.wasNewCard,
                newCardPrevState: context.newCardPrevState
            )
            restoreMainFocusAfterFinishEditingIfNeeded(skipMainFocusRestore: context.skipMainFocusRestore)
        }
        runFinishEditingCommit(apply)
    }

    func commitFinishedEditingIfNeeded(
        id: UUID,
        inFocusMode: Bool,
        startContent: String,
        startState: ScenarioState?,
        wasNewCard: Bool,
        newCardPrevState: ScenarioState?
    ) {
        guard let card = findCard(by: id) else { return }
        normalizeEditingCardContent(card)
        if card.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            commitEmptyEditingCard(
                card,
                id: id,
                inFocusMode: inFocusMode,
                wasNewCard: wasNewCard
            )
        } else {
            commitNonEmptyEditingCard(
                card,
                id: id,
                inFocusMode: inFocusMode,
                startContent: startContent,
                startState: startState,
                wasNewCard: wasNewCard,
                newCardPrevState: newCardPrevState
            )
        }
    }

    func normalizeEditingCardContent(_ card: SceneCard) {
        while card.content.hasSuffix("\n") {
            card.content.removeLast()
        }
    }

    func commitEmptyEditingCard(
        _ card: SceneCard,
        id: UUID,
        inFocusMode: Bool,
        wasNewCard: Bool
    ) {
        let prevState = captureScenarioState()
        let focusColumnCardsBeforeRemoval = inFocusMode ? focusedColumnCards() : []
        if !card.children.isEmpty {
            if !card.content.isEmpty {
                createArchivedCopy(from: card)
            }
            card.content = ""
            persistCardMutation(forceSnapshot: true)
            pushCardDeleteUndoState(prevState: prevState, inFocusMode: inFocusMode)
            return
        }

        if activeCardID == id {
            suppressAutoScrollOnce = true
            suppressHorizontalAutoScroll = true
            let next: SceneCard? = {
                if wasNewCard,
                   let previousID = lastActiveCardID,
                   previousID != card.id,
                   let previous = findCard(by: previousID),
                   !previous.isArchived {
                    return previous
                }
                if inFocusMode {
                    return nextFocusAfterFocusModeEmptyCardRemoval(
                        removedCard: card,
                        focusColumnCardsBeforeRemoval: focusColumnCardsBeforeRemoval
                    )
                }
                return nextFocusAfterMainModeEmptyCardRemoval(removedCard: card)
            }()
            if let n = next {
                selectedCardIDs = [n.id]
                changeActiveCard(to: n)
            } else {
                selectedCardIDs = []
                activeCardID = nil
                synchronizeActiveRelationState(for: nil)
            }
        }

        card.isArchived = true
        scenario.bumpCardsVersion()
        persistCardMutation(forceSnapshot: true)
        pushCardDeleteUndoState(prevState: prevState, inFocusMode: inFocusMode)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { suppressHorizontalAutoScroll = false }
    }

    func nextFocusAfterMainModeEmptyCardRemoval(removedCard: SceneCard) -> SceneCard? {
        let siblings = removedCard.parent?.sortedChildren ?? scenario.rootCards
        if let index = siblings.firstIndex(where: { $0.id == removedCard.id }) {
            if index > 0 {
                for i in stride(from: index - 1, through: 0, by: -1) {
                    let candidate = siblings[i]
                    if candidate.id != removedCard.id && !candidate.isArchived {
                        return candidate
                    }
                }
            }
            if index + 1 < siblings.count {
                for i in (index + 1)..<siblings.count {
                    let candidate = siblings[i]
                    if candidate.id != removedCard.id && !candidate.isArchived {
                        return candidate
                    }
                }
            }
        }
        if let parent = removedCard.parent, !parent.isArchived {
            return parent
        }
        return scenario.rootCards.first { $0.id != removedCard.id && !$0.isArchived }
    }

    func nextFocusAfterFocusModeEmptyCardRemoval(
        removedCard: SceneCard,
        focusColumnCardsBeforeRemoval: [SceneCard]
    ) -> SceneCard? {
        if let index = focusColumnCardsBeforeRemoval.firstIndex(where: { $0.id == removedCard.id }) {
            if index > 0 {
                for i in stride(from: index - 1, through: 0, by: -1) {
                    let candidate = focusColumnCardsBeforeRemoval[i]
                    if candidate.id != removedCard.id && !candidate.isArchived {
                        return candidate
                    }
                }
            }
            if index + 1 < focusColumnCardsBeforeRemoval.count {
                for i in (index + 1)..<focusColumnCardsBeforeRemoval.count {
                    let candidate = focusColumnCardsBeforeRemoval[i]
                    if candidate.id != removedCard.id && !candidate.isArchived {
                        return candidate
                    }
                }
            }
        }
        if let parent = removedCard.parent, !parent.isArchived {
            return parent
        }
        return nil
    }

    func pushCardDeleteUndoState(prevState: ScenarioState, inFocusMode: Bool) {
        if inFocusMode {
            pushFocusUndoState(prevState, actionName: "카드 삭제")
        } else {
            pushUndoState(prevState, actionName: "카드 삭제")
        }
    }

    func commitNonEmptyEditingCard(
        _ card: SceneCard,
        id: UUID,
        inFocusMode: Bool,
        startContent: String,
        startState: ScenarioState?,
        wasNewCard: Bool,
        newCardPrevState: ScenarioState?
    ) {
        let contentChanged = startContent != card.content
        if !isApplyingUndo {
            if !inFocusMode {
                if wasNewCard, let prev = newCardPrevState {
                    pushUndoState(prev, actionName: "카드 추가")
                } else if let prev = startState, contentChanged {
                    pushUndoState(prev, actionName: "텍스트 편집")
                }
            }
        }
        recordLinkedCardEditIfNeeded(editedCardID: id, contentChanged: contentChanged)
        if inFocusMode {
            focusLastCommittedContentByCard[id] = card.content
        }
        persistCardMutation()
    }

    func recordLinkedCardEditIfNeeded(editedCardID: UUID, contentChanged: Bool) {
        guard contentChanged else { return }
        guard splitModeEnabled, splitPaneID == 2 else { return }
        guard splitPaneAutoLinkEditsEnabled else { return }
        guard let focusCardID = resolvedFocusCardIDForLinkedEditRecording() else { return }
        guard focusCardID != editedCardID else { return }
        scenario.recordLinkedCard(focusCardID: focusCardID, linkedCardID: editedCardID)
    }

    func resolvedFocusCardIDForLinkedEditRecording() -> UUID? {
        if linkedCardsFilterEnabled,
           let anchorID = resolvedLinkedCardsAnchorID(),
           findCard(by: anchorID) != nil {
            return anchorID
        }
        if let leftPaneID = scenario.splitPaneActiveCardID(for: 1),
           findCard(by: leftPaneID) != nil {
            return leftPaneID
        }
        return nil
    }

    func restoreMainFocusAfterFinishEditingIfNeeded(skipMainFocusRestore: Bool) {
        if !skipMainFocusRestore {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { isMainViewFocused = true }
        }
    }

    // MARK: - Export & Deselect

    func deselectAll() {
        finishEditing()
        activeCardID = nil
        resetActiveRelationStateCache()
        selectedCardIDs = []
    }

    func buildExportText() -> String {
        guard let activeID = activeCardID else { return "" }
        let levels = resolvedLevelsWithParents()
        var target: [SceneCard] = []
        for (idx, data) in levels.enumerated() {
            guard data.cards.contains(where: { $0.id == activeID }) else { continue }
            target = (idx <= 1 || isActiveCardRoot)
                ? data.cards
                : data.cards.filter { $0.category == activeCategory }
            break
        }
        return target.map { $0.content }.joined(separator: "\n\n")
    }

    func exportToClipboard() {
        let txt = buildExportText()
        if txt.isEmpty {
            exportMessage = "출력할 내용이 없습니다."
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(txt, forType: .string)
            exportMessage = "클립보드에 복사되었습니다."
        }
        showExportAlert = true
    }

    func copySelectedCardTreeToClipboard() {
        let roots = copySourceRootCards()
        guard !roots.isEmpty else { return }
        let payload = CardTreeClipboardPayload(roots: roots.map { encodeClipboardNode(from: $0) })
        guard persistCardTreePayloadToClipboard(payload) else { return }
        clearCutCardTreeBuffer()
    }

    func cutSelectedCardTreeToClipboard() {
        let roots = copySourceRootCards()
        guard !roots.isEmpty else { return }
        let payload = CardTreeClipboardPayload(roots: roots.map { encodeClipboardNode(from: $0) })
        guard persistCardTreePayloadToClipboard(payload) else { return }
        cutCardRootIDs = roots.map { $0.id }
        cutCardSourceScenarioID = scenario.id
    }

    func copyCardsAsCloneFromContext(_ contextCard: SceneCard) {
        let cards = cloneCopySourceCards(contextCard: contextCard)
        guard !cards.isEmpty else { return }
        let payload = CloneCardClipboardPayload(
            sourceScenarioID: scenario.id,
            items: cards.map { card in
                CloneCardClipboardItem(
                    sourceCardID: card.id,
                    cloneGroupID: card.cloneGroupID,
                    content: card.content,
                    colorHex: card.colorHex,
                    isAICandidate: card.isAICandidate
                )
            }
        )
        guard persistCloneCardPayloadToClipboard(payload) else { return }
        clearCutCardTreeBuffer()
    }

    func cloneCopySourceCards(contextCard: SceneCard) -> [SceneCard] {
        if selectedCardIDs.count > 1, selectedCardIDs.contains(contextCard.id) {
            let selected = selectedCardIDs.compactMap { findCard(by: $0) }
            guard selected.count == selectedCardIDs.count else { return [contextCard] }
            return sortedCardsByCanvasOrder(selected)
        }
        return [contextCard]
    }

    func sortedCardsByCanvasOrder(_ cards: [SceneCard]) -> [SceneCard] {
        let rank = buildCanvasRank()
        return cards.sorted { lhs, rhs in
            let l = rank[lhs.id] ?? (Int.max, Int.max)
            let r = rank[rhs.id] ?? (Int.max, Int.max)
            if l.0 != r.0 { return l.0 < r.0 }
            if l.1 != r.1 { return l.1 < r.1 }
            return lhs.createdAt < rhs.createdAt
        }
    }

    func handleFountainClipboardPasteShortcutIfPossible(from textView: NSTextView) -> Bool {
        guard let preview = loadFountainClipboardPastePreview() else { return false }
        fountainClipboardPasteSourceTextViewBox.textView = textView
        pendingFountainClipboardPastePreview = preview
        showFountainClipboardPasteDialog = true
        return true
    }

    func loadFountainClipboardPastePreview() -> FountainClipboardPastePreview? {
        let pasteboard = NSPasteboard.general
        guard let rawText = pasteboard.string(forType: .string) else { return nil }
        guard let importPayload = parseFountainClipboardImport(from: rawText) else { return nil }
        return FountainClipboardPastePreview(rawText: rawText, importPayload: importPayload)
    }

    func cancelFountainClipboardPasteDialog() {
        showFountainClipboardPasteDialog = false
        restoreFountainClipboardPasteTextFocusIfNeeded()
    }

    func applyFountainClipboardPasteSelection(_ option: StructuredTextPasteOption) {
        guard let preview = pendingFountainClipboardPastePreview else {
            cancelFountainClipboardPasteDialog()
            return
        }

        showFountainClipboardPasteDialog = false

        switch option {
        case .plainText:
            pasteRawTextIntoFountainClipboardSource(preview.rawText)
        case .sceneCards:
            insertFountainClipboardImportCards(preview.importPayload)
        }
    }

    func restoreFountainClipboardPasteTextFocusIfNeeded() {
        guard let textView = fountainClipboardPasteSourceTextViewBox.textView else { return }
        DispatchQueue.main.async {
            guard let window = textView.window else { return }
            window.makeFirstResponder(textView)
        }
    }

    func pasteRawTextIntoFountainClipboardSource(_ rawText: String) {
        guard let textView = fountainClipboardPasteSourceTextViewBox.textView else { return }
        DispatchQueue.main.async {
            guard let window = textView.window else { return }
            window.makeFirstResponder(textView)
            textView.insertText(rawText, replacementRange: textView.selectedRange())
        }
    }

    func canReuseEditingCardForFountainClipboardImport() -> Bool {
        guard let editingID = editingCardID,
              let editingCard = findCard(by: editingID) else { return false }
        guard editingCard.children.isEmpty else { return false }
        return editingCard.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func insertFountainClipboardImportCards(_ importPayload: FountainClipboardImport) {
        let cardContents = importPayload.cardContents
        guard !cardContents.isEmpty else { return }

        let reuseEditingCard = canReuseEditingCardForFountainClipboardImport()
        let anchorCardID = editingCardID ?? activeCardID

        if reuseEditingCard {
            if showFocusMode {
                finalizeFocusTypingCoalescing(reason: "fountain-import")
                focusModeEditorCardID = nil
            } else {
                finalizeMainTypingCoalescing(reason: "fountain-import")
            }
            resetEditingTransientState()
        } else if editingCardID != nil {
            finishEditing()
            if showFocusMode {
                focusModeEditorCardID = nil
            }
        }

        let prevState = captureScenarioState()
        guard let anchorCard = anchorCardID.flatMap({ findCard(by: $0) }) ?? activeCardID.flatMap({ findCard(by: $0) }) else {
            insertRootLevelFountainClipboardCards(cardContents, previousState: prevState)
            return
        }

        var insertedCards: [SceneCard] = []
        insertedCards.reserveCapacity(cardContents.count)

        if reuseEditingCard {
            anchorCard.content = cardContents[0]
            insertedCards.append(anchorCard)
            let trailingContents = Array(cardContents.dropFirst())
            appendFountainClipboardCards(
                trailingContents,
                parent: anchorCard.parent,
                insertionIndex: anchorCard.orderIndex + 1,
                category: anchorCard.category,
                accumulator: &insertedCards
            )
            normalizeIndices(parent: anchorCard.parent)
        } else {
            appendFountainClipboardCards(
                cardContents,
                parent: anchorCard.parent,
                insertionIndex: anchorCard.orderIndex + 1,
                category: anchorCard.category,
                accumulator: &insertedCards
            )
            normalizeIndices(parent: anchorCard.parent)
        }

        completeFountainClipboardImport(
            insertedCards,
            previousState: prevState
        )
    }

    func insertRootLevelFountainClipboardCards(_ cardContents: [String], previousState: ScenarioState) {
        var insertedCards: [SceneCard] = []
        insertedCards.reserveCapacity(cardContents.count)
        appendFountainClipboardCards(
            cardContents,
            parent: nil,
            insertionIndex: scenario.rootCards.count,
            category: nil,
            accumulator: &insertedCards
        )
        normalizeIndices(parent: nil)
        completeFountainClipboardImport(
            insertedCards,
            previousState: previousState
        )
    }

    func appendFountainClipboardCards(
        _ contents: [String],
        parent: SceneCard?,
        insertionIndex: Int,
        category: String?,
        accumulator: inout [SceneCard]
    ) {
        guard !contents.isEmpty else { return }

        let siblings = parent?.sortedChildren ?? scenario.rootCards
        for sibling in siblings where sibling.orderIndex >= insertionIndex {
            sibling.orderIndex += contents.count
        }

        for (offset, content) in contents.enumerated() {
            let card = SceneCard(
                content: content,
                orderIndex: insertionIndex + offset,
                createdAt: Date(),
                parent: parent,
                scenario: scenario,
                category: parent?.category ?? category,
                isFloating: false,
                isArchived: false,
                lastSelectedChildID: nil,
                colorHex: nil,
                cloneGroupID: nil,
                isAICandidate: false
            )
            scenario.cards.append(card)
            accumulator.append(card)
        }
    }

    func completeFountainClipboardImport(
        _ insertedCards: [SceneCard],
        previousState: ScenarioState
    ) {
        guard !insertedCards.isEmpty else { return }

        scenario.bumpCardsVersion()
        commitCardMutation(
            previousState: previousState,
            actionName: "파운틴 카드 붙여넣기",
            forceSnapshot: true
        )

        selectedCardIDs = Set(insertedCards.map { $0.id })
        if let first = insertedCards.first {
            changeActiveCard(to: first, shouldFocusMain: false)
        }
        if !showFocusMode {
            isMainViewFocused = true
        }
    }

    func handlePasteShortcut() {
        if pasteCutCardTreeIfPossible() {
            return
        }
        if let clonePayload = loadCopiedCloneCardPayload(), !clonePayload.items.isEmpty {
            pendingCloneCardPastePayload = clonePayload
            pendingCardTreePastePayload = nil
            showCloneCardPasteDialog = true
            return
        }
        if let cardTreePayload = loadCopiedCardTreePayload(), !cardTreePayload.roots.isEmpty {
            pendingCardTreePastePayload = cardTreePayload
            pendingCloneCardPastePayload = nil
            showCloneCardPasteDialog = true
        }
    }

    func applyPendingPastePlacement(as placement: ClonePastePlacement) {
        if let payload = pendingCloneCardPastePayload {
            pendingCloneCardPastePayload = nil
            pendingCardTreePastePayload = nil
            showCloneCardPasteDialog = false
            pasteCloneCardPayload(payload, placement: placement)
            return
        }
        if let payload = pendingCardTreePastePayload {
            pendingCloneCardPastePayload = nil
            pendingCardTreePastePayload = nil
            showCloneCardPasteDialog = false
            pasteCardTreePayload(payload, placement: placement)
            return
        }
        pendingCloneCardPastePayload = nil
        pendingCardTreePastePayload = nil
        showCloneCardPasteDialog = false
    }

    func cancelPendingPastePlacement() {
        pendingCloneCardPastePayload = nil
        pendingCardTreePastePayload = nil
        showCloneCardPasteDialog = false
    }

    func applyPendingCloneCardPaste(as placement: ClonePastePlacement) {
        applyPendingPastePlacement(as: placement)
    }

    func cancelPendingCloneCardPaste() {
        cancelPendingPastePlacement()
    }

    func pasteCloneCardPayload(
        _ payload: CloneCardClipboardPayload,
        placement: ClonePastePlacement
    ) {
        guard !payload.items.isEmpty else { return }

        let prevState = captureScenarioState()
        let destination = resolvePasteDestination(for: placement)
        let destinationParent = destination.parent
        let insertionIndex = destination.insertionIndex

        let destinationSiblings = destinationParent?.sortedChildren ?? scenario.rootCards
        for sibling in destinationSiblings where sibling.orderIndex >= insertionIndex {
            sibling.orderIndex += payload.items.count
        }

        var insertedCards: [SceneCard] = []
        insertedCards.reserveCapacity(payload.items.count)

        for (offset, item) in payload.items.enumerated() {
            let source = resolveClonePasteSource(item, sourceScenarioID: payload.sourceScenarioID)
            let newCard = SceneCard(
                content: source.content,
                orderIndex: insertionIndex + offset,
                createdAt: Date(),
                parent: destinationParent,
                scenario: scenario,
                category: destinationParent?.category,
                isFloating: false,
                isArchived: false,
                lastSelectedChildID: nil,
                colorHex: source.colorHex,
                cloneGroupID: source.cloneGroupID,
                isAICandidate: source.isAICandidate
            )
            scenario.cards.append(newCard)
            insertedCards.append(newCard)
        }

        normalizeIndices(parent: destinationParent)
        scenario.bumpCardsVersion()
        selectedCardIDs = Set(insertedCards.map { $0.id })
        if let first = insertedCards.first {
            changeActiveCard(to: first)
        }
        commitCardMutation(
            previousState: prevState,
            actionName: "클론 카드 붙여넣기"
        )
    }

    func resolvePasteDestination(for placement: ClonePastePlacement) -> (parent: SceneCard?, insertionIndex: Int) {
        guard let active = activeCardID.flatMap({ findCard(by: $0) }) else {
            return (nil, scenario.rootCards.count)
        }

        switch placement {
        case .child:
            return (active, active.children.count)
        case .sibling:
            return (active.parent, active.orderIndex + 1)
        }
    }

    func resolveClonePasteDestination(for placement: ClonePastePlacement) -> (parent: SceneCard?, insertionIndex: Int) {
        resolvePasteDestination(for: placement)
    }

    func resolveClonePasteSource(
        _ item: CloneCardClipboardItem,
        sourceScenarioID: UUID
    ) -> (content: String, colorHex: String?, isAICandidate: Bool, cloneGroupID: UUID) {
        if sourceScenarioID == scenario.id,
           let sourceCard = findCard(by: item.sourceCardID),
           !sourceCard.isArchived {
            let resolvedGroupID: UUID
            if let existing = sourceCard.cloneGroupID {
                resolvedGroupID = existing
            } else {
                let created = item.cloneGroupID ?? UUID()
                sourceCard.cloneGroupID = created
                resolvedGroupID = created
            }
            return (
                content: sourceCard.content,
                colorHex: sourceCard.colorHex,
                isAICandidate: sourceCard.isAICandidate,
                cloneGroupID: resolvedGroupID
            )
        }

        return (
            content: item.content,
            colorHex: item.colorHex,
            isAICandidate: item.isAICandidate,
            cloneGroupID: item.cloneGroupID ?? UUID()
        )
    }

    func pasteCopiedCardTree() {
        if pasteCutCardTreeIfPossible() {
            return
        }

        guard let payload = loadCopiedCardTreePayload() else { return }
        guard !payload.roots.isEmpty else { return }
        pasteCardTreePayload(payload, placement: .child)
    }

    func pasteCardTreePayload(
        _ payload: CardTreeClipboardPayload,
        placement: ClonePastePlacement
    ) {
        guard !payload.roots.isEmpty else { return }

        let prevState = captureScenarioState()

        let destination = resolvePasteDestination(for: placement)
        let destinationParent = destination.parent
        let insertionIndex = destination.insertionIndex

        let destinationSiblings = destinationParent?.sortedChildren ?? scenario.rootCards
        for sibling in destinationSiblings where sibling.orderIndex >= insertionIndex {
            sibling.orderIndex += payload.roots.count
        }

        var newRootCards: [SceneCard] = []
        newRootCards.reserveCapacity(payload.roots.count)
        for (offset, rootNode) in payload.roots.enumerated() {
            let newRoot = instantiateClipboardNode(
                rootNode,
                parent: destinationParent,
                orderIndex: insertionIndex + offset
            )
            newRoot.updateDescendantsCategory(destinationParent?.category)
            newRootCards.append(newRoot)
        }

        normalizeIndices(parent: destinationParent)
        scenario.bumpCardsVersion()
        selectedCardIDs = Set(newRootCards.map { $0.id })
        if let first = newRootCards.first {
            changeActiveCard(to: first)
        }

        commitCardMutation(
            previousState: prevState,
            actionName: "카드 붙여넣기"
        )
    }

    func copySourceRootCards() -> [SceneCard] {
        let selected = selectedCardsForDeletion()
        guard !selected.isEmpty else { return [] }
        return movableRoots(from: selected)
    }

    func persistCardTreePayloadToClipboard(_ payload: CardTreeClipboardPayload) -> Bool {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload) else { return false }

        copiedCardTreePayloadData = data
        copiedCloneCardPayloadData = nil
        pendingCloneCardPastePayload = nil
        pendingCardTreePastePayload = nil
        showCloneCardPasteDialog = false

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([waCardTreePasteboardType], owner: nil)
        pasteboard.setData(data, forType: waCardTreePasteboardType)
        return true
    }

    func persistCloneCardPayloadToClipboard(_ payload: CloneCardClipboardPayload) -> Bool {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload) else { return false }

        copiedCloneCardPayloadData = data
        copiedCardTreePayloadData = nil
        pendingCloneCardPastePayload = nil
        pendingCardTreePastePayload = nil
        showCloneCardPasteDialog = false

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([waCloneCardPasteboardType], owner: nil)
        pasteboard.setData(data, forType: waCloneCardPasteboardType)
        return true
    }

    func clearCutCardTreeBuffer() {
        cutCardRootIDs = []
        cutCardSourceScenarioID = nil
    }

    func resolvedCardTreePasteDestination() -> (parent: SceneCard?, insertionIndex: Int) {
        if let active = activeCardID.flatMap({ findCard(by: $0) }) {
            return (active, active.children.count)
        }
        return (nil, scenario.rootCards.count)
    }

    func pasteCutCardTreeIfPossible() -> Bool {
        guard cutCardSourceScenarioID == scenario.id else { return false }
        guard !cutCardRootIDs.isEmpty else { return false }

        let roots = cutCardRootIDs.compactMap { findCard(by: $0) }
        guard roots.count == cutCardRootIDs.count else { return false }
        let movingRoots = movableRoots(from: roots)
        guard !movingRoots.isEmpty else { return false }
        guard let draggedCard = movingRoots.first else { return false }

        if let active = activeCardID.flatMap({ findCard(by: $0) }) {
            if movingRoots.contains(where: { $0.id == active.id }) { return false }
            if movingRoots.contains(where: { isDescendant($0, of: active.id) }) { return false }
            executeMoveSelection(movingRoots, draggedCard: draggedCard, target: .onto(active.id))
        } else {
            executeMoveSelection(movingRoots, draggedCard: draggedCard, target: .columnBottom(nil))
        }

        clearCutCardTreeBuffer()
        return true
    }

    func encodeClipboardNode(from card: SceneCard) -> CardTreeClipboardNode {
        CardTreeClipboardNode(
            content: card.content,
            colorHex: card.colorHex,
            isAICandidate: card.isAICandidate,
            children: card.sortedChildren.map { encodeClipboardNode(from: $0) }
        )
    }

    func instantiateClipboardNode(
        _ node: CardTreeClipboardNode,
        parent: SceneCard?,
        orderIndex: Int
    ) -> SceneCard {
        let card = SceneCard(
            content: node.content,
            orderIndex: orderIndex,
            createdAt: Date(),
            parent: parent,
            scenario: scenario,
            category: parent?.category,
            isFloating: false,
            isArchived: false,
            lastSelectedChildID: nil,
            colorHex: node.colorHex,
            isAICandidate: node.isAICandidate
        )
        scenario.cards.append(card)

        for (childIndex, childNode) in node.children.enumerated() {
            _ = instantiateClipboardNode(childNode, parent: card, orderIndex: childIndex)
        }
        return card
    }

    func loadCopiedCardTreePayload() -> CardTreeClipboardPayload? {
        let decoder = JSONDecoder()
        let pasteboard = NSPasteboard.general

        if let data = pasteboard.data(forType: waCardTreePasteboardType),
           let payload = try? decoder.decode(CardTreeClipboardPayload.self, from: data) {
            copiedCardTreePayloadData = data
            return payload
        }

        if let cached = copiedCardTreePayloadData,
           let payload = try? decoder.decode(CardTreeClipboardPayload.self, from: cached) {
            return payload
        }

        return nil
    }

    func loadCopiedCloneCardPayload() -> CloneCardClipboardPayload? {
        let decoder = JSONDecoder()
        let pasteboard = NSPasteboard.general

        if let data = pasteboard.data(forType: waCloneCardPasteboardType),
           let payload = try? decoder.decode(CloneCardClipboardPayload.self, from: data) {
            copiedCloneCardPayloadData = data
            return payload
        }

        if let cached = copiedCloneCardPayloadData,
           let payload = try? decoder.decode(CloneCardClipboardPayload.self, from: cached) {
            return payload
        }

        return nil
    }

    func exportToFile() {
        let txt = buildExportText()
        if txt.isEmpty {
            exportMessage = "출력할 내용이 없습니다."
            showExportAlert = true
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(scenario.title)_출력.txt"
        panel.begin { res in
            guard res == .OK, let url = panel.url else { return }
            try? txt.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    func exportToCenteredPDF() {
        exportToPDF(format: .centered, defaultName: "\(scenario.title)_중앙정렬식.pdf")
    }
    func exportToKoreanPDF() {
        exportToPDF(format: .korean, defaultName: "\(scenario.title)_한국식.pdf")
    }
    func exportToPDF(format: ScriptExportFormatType, defaultName: String) {
        let txt = buildExportText()
        if txt.isEmpty {
            exportMessage = "출력할 내용이 없습니다."
            showExportAlert = true
            return
        }
        let parser = ScriptMarkdownParser(formatType: format)
        let elements = parser.parse(txt)
        var pdfConfig = ScriptExportLayoutConfig()
        pdfConfig.centeredFontSize = CGFloat(exportCenteredFontSize)
        pdfConfig.centeredIsCharacterBold = exportCenteredCharacterBold
        pdfConfig.centeredIsSceneHeadingBold = exportCenteredSceneHeadingBold
        pdfConfig.centeredShowRightSceneNumber = exportCenteredShowRightSceneNumber
        pdfConfig.koreanFontSize = CGFloat(exportKoreanFontSize)
        pdfConfig.koreanIsSceneBold = exportKoreanSceneBold
        pdfConfig.koreanIsCharacterBold = exportKoreanCharacterBold
        pdfConfig.koreanCharacterAlignment = exportKoreanCharacterAlignment == "left" ? .left : .right

        let generator = ScriptPDFGenerator(format: format, config: pdfConfig)
        let data = generator.generatePDF(from: elements)
        if data.isEmpty {
            exportMessage = "PDF 생성에 실패했습니다."
            showExportAlert = true
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = defaultName
        panel.begin { res in
            if res == .OK, let url = panel.url {
                do {
                    try data.write(to: url)
                } catch {
                    exportMessage = "PDF 저장에 실패했습니다."
                    showExportAlert = true
                }
            }
        }
    }

    func toggleTimeline() {
        withAnimation(quickEaseAnimation) {
            showTimeline.toggle()
            if showTimeline {
                showHistoryBar = false
                showAIChat = false
                exitPreviewMode()
            } else {
                exitPreviewMode()
                searchText = ""
                linkedCardsFilterEnabled = false
                linkedCardAnchorID = nil
                isSearchFocused = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isMainViewFocused = true }
            }
        }
    }

    // MARK: - Search & Add Card

    func openSearch() {
        withAnimation(quickEaseAnimation) {
            showTimeline = true
            showAIChat = false
            showHistoryBar = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isSearchFocused = true
        }
    }
    func closeSearch() {
        withAnimation(quickEaseAnimation) {
            showTimeline = false
            searchText = ""
            linkedCardsFilterEnabled = false
            linkedCardAnchorID = nil
            isSearchFocused = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isMainViewFocused = true
        }
    }
    func toggleSearch() {
        if showTimeline {
            closeSearch()
        } else {
            openSearch()
        }
    }

    func addCard(at level: Int, parent: SceneCard?) {
        let prevState = captureScenarioState()
        if showFocusMode {
            finalizeFocusTypingCoalescing(reason: "add-card")
            pushFocusUndoState(prevState, actionName: "카드 추가")
        }
        let new = SceneCard(orderIndex: parent?.children.count ?? scenario.rootCards.count, parent: parent, scenario: scenario, category: parent?.category)
        scenario.cards.append(new)
        scenario.bumpCardsVersion()
        saveWriterChanges()
        selectedCardIDs = [new.id]
        changeActiveCard(to: new, shouldFocusMain: false)
        editingCardID = new.id
        editingStartContent = new.content
        editingIsNewCard = true
        pendingNewCardPrevState = prevState
    }

    // MARK: - Insert, Add Child, Delete

    func sortedCardsForUpperCardCreation(_ cards: [SceneCard]) -> [SceneCard]? {
        guard !cards.isEmpty else { return nil }
        let parentID = cards.first?.parent?.id
        guard cards.allSatisfy({ !$0.isArchived && $0.parent?.id == parentID }) else { return nil }
        return cards.sorted { lhs, rhs in
            if lhs.orderIndex != rhs.orderIndex {
                return lhs.orderIndex < rhs.orderIndex
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    func selectedSiblingsForParentCreation(contextCard: SceneCard) -> [SceneCard]? {
        guard !showFocusMode else { return nil }
        guard !contextCard.isArchived else { return nil }
        if selectedCardIDs.count > 1 {
            guard selectedCardIDs.contains(contextCard.id) else { return nil }
            let selectedCards = selectedCardIDs.compactMap { findCard(by: $0) }
            guard selectedCards.count == selectedCardIDs.count else { return nil }
            return sortedCardsForUpperCardCreation(selectedCards)
        }
        return [contextCard]
    }

    func canCreateUpperCardFromSelection(contextCard: SceneCard) -> Bool {
        guard !showFocusMode else { return false }
        guard !contextCard.isArchived else { return false }
        if selectedCardIDs.count <= 1 {
            return true
        }
        guard selectedCardIDs.contains(contextCard.id) else { return false }
        let selectedCards = selectedCardIDs.compactMap { findCard(by: $0) }
        guard selectedCards.count == selectedCardIDs.count else { return false }
        return sortedCardsForUpperCardCreation(selectedCards) != nil
    }

    func upperCardCreationRequest(contextCard: SceneCard) -> UpperCardCreationRequest? {
        guard let sourceCards = selectedSiblingsForParentCreation(contextCard: contextCard) else { return nil }
        return UpperCardCreationRequest(
            contextCardID: contextCard.id,
            sourceCardIDs: sourceCards.map(\.id)
        )
    }

    func createUpperCardFromSelection(contextCard: SceneCard) {
        guard let request = upperCardCreationRequest(contextCard: contextCard) else { return }
        pendingUpperCardCreationRequest = request
    }

    func upperCardCreationSiblingLayout(
        parent: SceneCard?,
        selectedSiblings: [SceneCard],
        newParent: SceneCard,
        oldSiblings: [SceneCard]
    ) -> [SceneCard]? {
        guard let firstSelected = selectedSiblings.first,
              let insertionIndex = oldSiblings.firstIndex(where: { $0.id == firstSelected.id }) else {
            return nil
        }

        let selectedIDs = Set(selectedSiblings.map(\.id))
        var finalSiblings: [SceneCard] = []
        finalSiblings.reserveCapacity(max(1, oldSiblings.count - selectedSiblings.count + 1))

        for (index, sibling) in oldSiblings.enumerated() {
            if index == insertionIndex {
                finalSiblings.append(newParent)
            }
            guard !selectedIDs.contains(sibling.id) else { continue }
            guard sibling.parent?.id == parent?.id else { continue }
            finalSiblings.append(sibling)
        }

        if insertionIndex >= oldSiblings.count {
            finalSiblings.append(newParent)
        }

        return finalSiblings
    }

    @discardableResult
    func createUpperCardFromSourceCards(
        _ sourceCards: [SceneCard],
        initialContent: String,
        startEditing: Bool,
        actionName: String
    ) -> SceneCard? {
        guard let selectedSiblings = sortedCardsForUpperCardCreation(sourceCards),
              let firstSelected = selectedSiblings.first else { return nil }
        let parent = firstSelected.parent
        let oldSiblings = liveOrderedSiblings(parent: parent)
        let prevState = captureScenarioState()
        suppressMainFocusRestoreAfterFinishEditing = true
        finishEditing()

        let insertionIndex = firstSelected.orderIndex
        let newParent = SceneCard(
            content: initialContent,
            orderIndex: insertionIndex,
            parent: parent,
            scenario: scenario,
            category: parent?.category ?? firstSelected.category
        )

        guard let finalOldSiblings = upperCardCreationSiblingLayout(
            parent: parent,
            selectedSiblings: selectedSiblings,
            newParent: newParent,
            oldSiblings: oldSiblings
        ) else {
            return nil
        }

        scenario.performBatchedCardMutation {
            scenario.cards.append(newParent)

            for (childIndex, selectedCard) in selectedSiblings.enumerated() {
                selectedCard.parent = newParent
                if selectedCard.orderIndex != childIndex {
                    selectedCard.orderIndex = childIndex
                }
            }

            for (index, sibling) in finalOldSiblings.enumerated() {
                if sibling.orderIndex != index {
                    sibling.orderIndex = index
                }
            }
        }

        keyboardRangeSelectionAnchorCardID = nil
        selectedCardIDs = [newParent.id]
        changeActiveCard(to: newParent, shouldFocusMain: false)
        if startEditing {
            editingCardID = newParent.id
            editingStartContent = newParent.content
            editingStartState = captureScenarioState()
            editingIsNewCard = false
            restoreMainEditingCaret(
                for: newParent.id,
                location: (newParent.content as NSString).length
            )
        } else {
            editingCardID = nil
        }
        pendingNewCardPrevState = nil
        isMainViewFocused = true
        commitCardMutation(previousState: prevState, actionName: actionName)
        return newParent
    }

    func createEmptyUpperCard(from request: UpperCardCreationRequest) {
        pendingUpperCardCreationRequest = nil
        let sourceCards = request.sourceCardIDs.compactMap { findCard(by: $0) }
        guard sourceCards.count == request.sourceCardIDs.count else {
            setAIStatusError("원본 카드 상태가 바뀌어 상위 카드를 만들 수 없습니다.")
            return
        }
        _ = createUpperCardFromSourceCards(
            sourceCards,
            initialContent: "",
            startEditing: true,
            actionName: "새 상위 카드 만들기"
        )
    }

    @discardableResult
    func createUpperCardWithResolvedSummary(sourceCards: [SceneCard], summary: String) -> SceneCard? {
        createUpperCardFromSourceCards(
            sourceCards,
            initialContent: summary,
            startEditing: false,
            actionName: "AI 요약 상위 카드 만들기"
        )
    }

    func canSummarizeDirectChildren(for parentCard: SceneCard) -> Bool {
        guard !showFocusMode else { return false }
        return parentCard.children.count >= 2
    }

    func summarizeDirectChildrenIntoParent(cardID: UUID) {
        guard !showFocusMode else { return }
        guard !aiChildSummaryLoadingCardIDs.contains(cardID) else { return }
        guard !aiIsGenerating else {
            setAIStatusError("이미 다른 AI 작업이 진행 중입니다.")
            return
        }
        guard let parentCard = findCard(by: cardID) else { return }
        let directChildren = parentCard.children.sorted {
            if $0.orderIndex != $1.orderIndex { return $0.orderIndex < $1.orderIndex }
            return $0.createdAt < $1.createdAt
        }
        guard directChildren.count >= 2 else {
            setAIStatusError("요약하려면 하위 카드가 2개 이상 필요합니다.")
            return
        }

        suppressMainFocusRestoreAfterFinishEditing = true
        finishEditing()

        let prompt = buildChildCardsSummaryPrompt(parentCard: parentCard, directChildren: directChildren)
        let resolvedModel = currentGeminiModel()

        aiIsGenerating = true
        aiChildSummaryLoadingCardIDs.insert(parentCard.id)
        setAIStatus("하위 카드 요약을 생성하는 중입니다...")

        Task { @MainActor in
            defer {
                aiIsGenerating = false
                aiChildSummaryLoadingCardIDs.remove(parentCard.id)
            }

            do {
                guard let latestParent = findCard(by: parentCard.id) else { return }
                guard let apiKey = try KeychainStore.loadGeminiAPIKey() else {
                    throw GeminiServiceError.missingAPIKey
                }
                let rawSummary = try await GeminiService.generateText(
                    prompt: prompt,
                    model: resolvedModel,
                    apiKey: apiKey
                )
                let summary = normalizedChildSummaryOutput(rawSummary)
                guard !summary.isEmpty else {
                    throw GeminiServiceError.invalidResponse
                }

                let prevState = captureScenarioState()
                let blockTitle = "하위 카드 요약"
                let block = "\(blockTitle)\n\(summary)"
                if latestParent.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    latestParent.content = block
                } else {
                    latestParent.content += "\n\n\(block)"
                }

                scenario.bumpCardsVersion()
                commitCardMutation(
                    previousState: prevState,
                    actionName: "하위 카드 요약",
                    forceSnapshot: true
                )

                selectedCardIDs = [latestParent.id]
                changeActiveCard(to: latestParent, shouldFocusMain: false)
                editingCardID = latestParent.id
                editingStartContent = latestParent.content
                editingStartState = captureScenarioState()
                editingIsNewCard = false
                pendingNewCardPrevState = nil
                restoreMainEditingCaret(
                    for: latestParent.id,
                    location: (latestParent.content as NSString).length
                )
                isMainViewFocused = true

                setAIStatus("하위 카드 요약을 카드 하단에 추가했습니다.")
            } catch {
                setAIStatusError(error.localizedDescription)
            }
        }
    }

    func buildChildCardsSummaryPrompt(parentCard _: SceneCard, directChildren: [SceneCard]) -> String {
        let orderedChildrenText = directChildren.enumerated().map { idx, child in
            let content = clampedAIText(child.content, maxLength: 1400, preserveLineBreak: true)
            return "\(idx + 1). \(content)"
        }.joined(separator: "\n\n")
        return renderEntityDenseSummaryPrompt(articleText: orderedChildrenText)
    }

    func normalizedChildSummaryOutput(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\t", with: " ")
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }

    func splitCardAtCaret() {
        let prevState = captureScenarioState()
        guard let id = editingCardID ?? activeCardID,
              let card = findCard(by: id) else { return }
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        guard !textView.hasMarkedText() else { return }

        if showFocusMode {
            finalizeFocusTypingCoalescing(reason: "split-card")
            pushFocusUndoState(prevState, actionName: "카드 나누기")
        }

        let sourceText = textView.string as NSString
        let splitLocation = min(max(0, textView.selectedRange().location), sourceText.length)
        let upperContent = sourceText.substring(to: splitLocation)
        let lowerContent = sourceText.substring(from: splitLocation)

        let targetOrderIndex = card.orderIndex + 1
        for sibling in (card.parent?.sortedChildren ?? scenario.rootCards) where sibling.orderIndex >= targetOrderIndex {
            sibling.orderIndex += 1
        }

        card.content = upperContent
        let new = SceneCard(orderIndex: targetOrderIndex, parent: card.parent, scenario: scenario, category: card.category)
        new.content = lowerContent
        scenario.cards.append(new)
        scenario.bumpCardsVersion()
        saveWriterChanges()

        selectedCardIDs = [new.id]
        changeActiveCard(to: new, shouldFocusMain: false)
        editingCardID = new.id
        editingStartContent = new.content
        editingIsNewCard = true
        pendingNewCardPrevState = prevState

        if showFocusMode {
            focusModeEditorCardID = new.id
            DispatchQueue.main.async {
                beginFocusModeEditing(new, cursorToEnd: false, cardScrollAnchor: .center)
            }
        } else {
            restoreMainEditingCaret(for: new.id, location: 0)
        }
    }

    func insertSibling(relativeTo card: SceneCard, above: Bool) {
        let prevState = captureScenarioState()
        if showFocusMode {
            finalizeFocusTypingCoalescing(reason: "insert-sibling")
            pushFocusUndoState(prevState, actionName: "카드 추가")
        }
        let target = above ? card.orderIndex : card.orderIndex + 1
        for s in (card.parent?.sortedChildren ?? scenario.rootCards) where s.orderIndex >= target { s.orderIndex += 1 }
        let new = SceneCard(orderIndex: target, parent: card.parent, scenario: scenario, category: card.category)
        scenario.cards.append(new)
        scenario.bumpCardsVersion()
        saveWriterChanges()
        selectedCardIDs = [new.id]
        changeActiveCard(to: new, shouldFocusMain: false)
        editingCardID = new.id
        editingStartContent = new.content
        editingIsNewCard = true
        pendingNewCardPrevState = prevState
        if showFocusMode {
            focusModeEditorCardID = new.id
            DispatchQueue.main.async {
                beginFocusModeEditing(new, cursorToEnd: false, cardScrollAnchor: .center)
            }
        }
    }

    func insertSibling(above: Bool) {
        guard let id = activeCardID, let card = findCard(by: id) else { return }
        insertSibling(relativeTo: card, above: above)
    }

    func addChildCard(to card: SceneCard) {
        let prevState = captureScenarioState()
        if showFocusMode {
            finalizeFocusTypingCoalescing(reason: "add-child")
            pushFocusUndoState(prevState, actionName: "카드 추가")
        }
        let new = SceneCard(orderIndex: card.children.count, parent: card, scenario: scenario, category: card.category)
        scenario.cards.append(new)
        scenario.bumpCardsVersion()
        saveWriterChanges()
        selectedCardIDs = [new.id]
        changeActiveCard(to: new, shouldFocusMain: false)
        editingCardID = new.id
        editingStartContent = new.content
        editingIsNewCard = true
        pendingNewCardPrevState = prevState
    }

    func addChildCard() {
        guard let id = activeCardID, let card = findCard(by: id) else { return }
        addChildCard(to: card)
    }

    func addCardToReferenceWindow(_ card: SceneCard) {
        referenceCardStore.addCard(cardID: card.id, scenarioID: scenario.id)
        openWindow(id: ReferenceWindowConstants.windowID)
    }

    func performDelete(_ card: SceneCard) {
        let prevState = captureScenarioState()
        if !card.children.isEmpty {
            if !card.content.isEmpty {
                createArchivedCopy(from: card)
            }
            card.content = ""
            isMainViewFocused = true
            commitCardMutation(
                previousState: prevState,
                actionName: "카드 삭제",
                forceSnapshot: true
            )
            return
        }

        let levelsBefore = resolvedAllLevels()
        let levelMap = levelsBefore.enumerated().reduce(into: [UUID: Int]()) { acc, entry in
            for c in entry.element { acc[c.id] = entry.offset }
        }
        let next = nextFocusAfterRemoval(
            removedIDs: [card.id],
            levelMap: levelMap,
            levels: levelsBefore,
            preferredAnchorID: card.id
        )
        card.isArchived = true
        scenario.bumpCardsVersion()
        if let n = next {
            suppressAutoScrollOnce = true
            suppressHorizontalAutoScroll = true
            changeActiveCard(to: n)
        } else {
            activeCardID = nil
            resetActiveRelationStateCache()
        }
        isMainViewFocused = true
        commitCardMutation(
            previousState: prevState,
            actionName: "카드 삭제",
            forceSnapshot: true
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { suppressHorizontalAutoScroll = false }
    }

    func performHardDelete(_ card: SceneCard) {
        finishEditing()
        let idsToRemove = resolvedHardDeleteIDs(targetCard: card)
        guard !idsToRemove.isEmpty else { return }

        let prevState = captureScenarioState()
        let levelsBefore = resolvedAllLevels()
        let levelMap = buildLevelMap(from: levelsBefore)
        let preferredAnchorID = activeCardID ?? editingCardID ?? card.id
        let nextCandidate = nextFocusAfterRemoval(
            removedIDs: idsToRemove,
            levelMap: levelMap,
            levels: levelsBefore,
            preferredAnchorID: preferredAnchorID
        )

        applyHardDeleteMutations(idsToRemove)
        applyHardDeleteSelectionState(idsToRemove, nextCandidate: nextCandidate)
        applyHardDeleteEditorAndHistoryState(idsToRemove)

        clearFocusDeleteSelectionLock()
        isMainViewFocused = true
        commitCardMutation(
            previousState: prevState,
            actionName: "카드 완전 삭제",
            forceSnapshot: true,
            immediateSave: true,
            undoMode: .focusAware
        )
    }

    func performHardDeleteAllTimelineEmptyLeafCards() {
        finishEditing()

        let idsToRemove: Set<UUID> = Set(
            scenario.cards.compactMap { card in
                guard card.children.isEmpty else { return nil }
                let isEmpty = card.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                return isEmpty ? card.id : nil
            }
        )
        guard !idsToRemove.isEmpty else { return }

        let prevState = captureScenarioState()
        let levelsBefore = resolvedAllLevels()
        let levelMap = buildLevelMap(from: levelsBefore)
        let preferredAnchorID = activeCardID ?? editingCardID
        let nextCandidate = nextFocusAfterRemoval(
            removedIDs: idsToRemove,
            levelMap: levelMap,
            levels: levelsBefore,
            preferredAnchorID: preferredAnchorID
        )

        applyHardDeleteMutations(idsToRemove)
        applyHardDeleteSelectionState(idsToRemove, nextCandidate: nextCandidate)
        applyHardDeleteEditorAndHistoryState(idsToRemove)

        clearFocusDeleteSelectionLock()
        isMainViewFocused = true
        commitCardMutation(
            previousState: prevState,
            actionName: "내용 없음 카드 전체 삭제",
            forceSnapshot: true,
            immediateSave: true,
            undoMode: .focusAware
        )
    }

    func resolvedHardDeleteIDs(targetCard card: SceneCard) -> Set<UUID> {
        let selected = selectedCardsForDeletion()
        let shouldDeleteSelectionBatch =
            selected.count > 1 &&
            selectedCardIDs.contains(card.id)

        if shouldDeleteSelectionBatch {
            var idsToRemove: Set<UUID> = []
            for selectedCard in selected {
                idsToRemove.formUnion(subtreeIDs(of: selectedCard))
            }
            return idsToRemove
        }
        return subtreeIDs(of: card)
    }

    func applyHardDeleteMutations(_ idsToRemove: Set<UUID>) {
        scenario.cards.removeAll { idsToRemove.contains($0.id) }
        scenario.pruneLinkedCards(validCardIDs: Set(scenario.cards.map(\.id)))
        for snapshot in scenario.snapshots {
            snapshot.cardSnapshots.removeAll { snap in
                idsToRemove.contains(snap.cardID) || (snap.parentID.map { idsToRemove.contains($0) } ?? false)
            }
            snapshot.deletedCardIDs.removeAll { idsToRemove.contains($0) }
            if let noteID = snapshot.noteCardID, idsToRemove.contains(noteID) {
                snapshot.noteCardID = nil
            }
        }
        scenario.invalidateSnapshotCache()
        scenario.bumpCardsVersion()
        scenario.changeCountSinceLastSnapshot = 0
    }

    func applyHardDeleteSelectionState(_ idsToRemove: Set<UUID>, nextCandidate: SceneCard?) {
        selectedCardIDs.subtract(idsToRemove)
        if let activeID = activeCardID, idsToRemove.contains(activeID) {
            if let next = nextCandidate {
                selectedCardIDs = [next.id]
                changeActiveCard(to: next, shouldFocusMain: false)
            } else {
                activeCardID = nil
                synchronizeActiveRelationState(for: nil)
            }
        }
        if selectedCardIDs.isEmpty, let activeID = activeCardID {
            selectedCardIDs = [activeID]
        }
    }

    func applyHardDeleteEditorAndHistoryState(_ idsToRemove: Set<UUID>) {
        if let editingID = editingCardID, idsToRemove.contains(editingID) {
            editingCardID = nil
            focusModeEditorCardID = nil
        }
        if let selectedHistoryNoteID = historySelectedNamedSnapshotNoteCardID,
           idsToRemove.contains(selectedHistoryNoteID) {
            historySelectedNamedSnapshotNoteCardID = nil
            isNamedSnapshotNoteEditing = false
        }
    }

    func armFocusDeleteSelectionLock(targetCardID: UUID, duration: TimeInterval = 0.60) {
        focusDeleteSelectionLockedCardID = targetCardID
        focusDeleteSelectionLockUntil = Date().addingTimeInterval(duration)
    }

    func clearFocusDeleteSelectionLock() {
        focusDeleteSelectionLockedCardID = nil
        focusDeleteSelectionLockUntil = .distantPast
    }

    // MARK: - Delete Selection & Card Tap

    func handleTimelineCardSelect(_ card: SceneCard) {
        if linkedCardsFilterEnabled {
            beginTimelineLinkedCardEditing(card)
            return
        }
        handleCardTap(card)
    }

    func handleTimelineCardDoubleClick(_ card: SceneCard) {
        if linkedCardsFilterEnabled {
            beginTimelineLinkedCardEditing(card)
            return
        }
        beginCardEditing(card)
    }

    func beginTimelineLinkedCardEditing(_ card: SceneCard) {
        let anchorCard = resolvedLinkedCardsAnchorID().flatMap { findCard(by: $0) }
        finishEditing()
        keyboardRangeSelectionAnchorCardID = nil

        if let anchorCard, activeCardID != anchorCard.id {
            changeActiveCard(to: anchorCard, shouldFocusMain: false, deferToMainAsync: false, force: true)
        }

        selectedCardIDs = [card.id]
        editingCardID = card.id
        editingStartContent = card.content
        editingStartState = captureScenarioState()
        editingIsNewCard = false
        isMainViewFocused = true
    }

    func deleteSelectedCard() {
        let anySelection = !selectedCardIDs.isEmpty || activeCardID != nil
        guard anySelection else { return }
        showDeleteAlert = true
    }

    func handleCardTap(_ card: SceneCard) {
        let isCommandPressed = NSEvent.modifierFlags.contains(.command)
        finishEditing()
        keyboardRangeSelectionAnchorCardID = nil
        if isCommandPressed {
            if selectedCardIDs.contains(card.id) {
                selectedCardIDs.remove(card.id)
            } else {
                selectedCardIDs.insert(card.id)
            }
            changeActiveCard(to: card)
        } else {
            selectedCardIDs = [card.id]
            changeActiveCard(to: card)
        }
        isMainViewFocused = true
    }

    private func mainWorkspaceClickModifiers() -> (command: Bool, shift: Bool) {
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return (
            command: flags.contains(.command),
            shift: flags.contains(.shift)
        )
    }

    private func resolvedMainWorkspaceLevel(containing cardID: UUID) -> [SceneCard]? {
        resolvedAllLevels().first { level in
            level.contains(where: { $0.id == cardID })
        }
    }

    private func resolvedMainWorkspaceRangeAnchorID(in level: [SceneCard]) -> UUID? {
        if let anchorID = keyboardRangeSelectionAnchorCardID,
           selectedCardIDs.contains(anchorID),
           level.contains(where: { $0.id == anchorID }) {
            return anchorID
        }

        if selectedCardIDs.count == 1,
           let selectedID = selectedCardIDs.first,
           level.contains(where: { $0.id == selectedID }) {
            return selectedID
        }

        if let activeID = activeCardID,
           selectedCardIDs.contains(activeID),
           level.contains(where: { $0.id == activeID }) {
            return activeID
        }

        return level.first(where: { selectedCardIDs.contains($0.id) })?.id
    }

    private func mainWorkspaceRangeSelectionIDs(
        in level: [SceneCard],
        anchorID: UUID,
        targetID: UUID
    ) -> Set<UUID> {
        guard let anchorIndex = level.firstIndex(where: { $0.id == anchorID }),
              let targetIndex = level.firstIndex(where: { $0.id == targetID }) else {
            return Set([targetID])
        }
        let lower = min(anchorIndex, targetIndex)
        let upper = max(anchorIndex, targetIndex)
        return Set(level[lower ... upper].map { $0.id })
    }

    private func prepareMainWorkspaceClickTarget(_ card: SceneCard) {
        let isNewActiveTarget = activeCardID != card.id
        pendingMainClickFocusTargetID = isNewActiveTarget ? card.id : nil
        pendingMainClickHorizontalFocusTargetID = isNewActiveTarget ? card.id : nil
        finishEditing()
    }

    private func finalizeMainWorkspaceClickTarget(_ card: SceneCard) {
        changeActiveCard(to: card, deferToMainAsync: false)
        isMainViewFocused = true
    }

    private func handleMainWorkspacePlainClick(_ card: SceneCard) {
        prepareMainWorkspaceClickTarget(card)
        selectedCardIDs = [card.id]
        keyboardRangeSelectionAnchorCardID = card.id
        finalizeMainWorkspaceClickTarget(card)
    }

    private func handleMainWorkspaceCommandClick(_ card: SceneCard) {
        prepareMainWorkspaceClickTarget(card)
        let wasSelected = selectedCardIDs.contains(card.id)
        if wasSelected {
            selectedCardIDs.remove(card.id)
            if selectedCardIDs.isEmpty {
                keyboardRangeSelectionAnchorCardID = nil
            } else if keyboardRangeSelectionAnchorCardID == card.id {
                keyboardRangeSelectionAnchorCardID = selectedCardIDs.first
            }
        } else {
            selectedCardIDs.insert(card.id)
            if keyboardRangeSelectionAnchorCardID == nil {
                keyboardRangeSelectionAnchorCardID = card.id
            }
        }
        finalizeMainWorkspaceClickTarget(card)
    }

    private func handleMainWorkspaceRangeClick(_ card: SceneCard, additive: Bool) {
        prepareMainWorkspaceClickTarget(card)
        guard let level = resolvedMainWorkspaceLevel(containing: card.id),
              let anchorID = resolvedMainWorkspaceRangeAnchorID(in: level) else {
            handleMainWorkspacePlainClick(card)
            return
        }

        keyboardRangeSelectionAnchorCardID = anchorID
        let rangeIDs = mainWorkspaceRangeSelectionIDs(
            in: level,
            anchorID: anchorID,
            targetID: card.id
        )
        if additive {
            selectedCardIDs.formUnion(rangeIDs)
        } else {
            selectedCardIDs = rangeIDs
        }
        finalizeMainWorkspaceClickTarget(card)
    }

    private func resolveMainWorkspaceClickCaretLocation(for card: SceneCard, clickLocation: CGPoint?) -> Int? {
        guard let clickLocation else { return nil }
        return sharedResolvedClickCaretLocation(
            text: card.content,
            localPoint: clickLocation,
            textWidth: MainCanvasLayoutMetrics.textWidth,
            fontSize: CGFloat(fontSize),
            lineSpacing: CGFloat(mainCardLineSpacingValue),
            horizontalInset: MainEditorLayoutMetrics.mainEditorHorizontalPadding,
            verticalInset: 24,
            lineFragmentPadding: MainEditorLayoutMetrics.mainEditorLineFragmentPadding
        )
    }

    func handleMainWorkspaceCardClick(_ card: SceneCard, clickLocation: CGPoint? = nil) {
        let modifiers = mainWorkspaceClickModifiers()
        let isPrimarySelection =
            selectedCardIDs.isEmpty ||
            (selectedCardIDs.count == 1 && selectedCardIDs.contains(card.id))
        let shouldBeginEditing =
            acceptsKeyboardInput &&
            !showFocusMode &&
            !modifiers.command &&
            !modifiers.shift &&
            activeCardID == card.id &&
            editingCardID != card.id &&
            isPrimarySelection

        if shouldBeginEditing {
            beginCardEditing(
                card,
                explicitCaretLocation: resolveMainWorkspaceClickCaretLocation(for: card, clickLocation: clickLocation)
            )
            return
        }

        if modifiers.command && modifiers.shift {
            handleMainWorkspaceRangeClick(card, additive: true)
            return
        }
        if modifiers.shift {
            handleMainWorkspaceRangeClick(card, additive: false)
            return
        }
        if modifiers.command {
            handleMainWorkspaceCommandClick(card)
            return
        }
        handleMainWorkspacePlainClick(card)
    }

    func selectedCardsForDeletion() -> [SceneCard] {
        if !selectedCardIDs.isEmpty {
            return selectedCardIDs.compactMap { findCard(by: $0) }
        }
        if let id = activeCardID, let card = findCard(by: id) { return [card] }
        return []
    }

    // MARK: - Perform Delete Selection (Full)

    func performDeleteSelection() {
        let selected = selectedCardsForDeletion()
        guard !selected.isEmpty else { return }
        let focusColumnCardsBeforeDelete = showFocusMode ? focusedColumnCards() : []

        prepareFocusModeForDeleteSelectionIfNeeded()
        let prevState = captureScenarioState()
        let levelsBefore = resolvedAllLevels()
        let levelMap = buildLevelMap(from: levelsBefore)
        let deleteOutcome = resolveDeleteSelectionOutcome(from: selected)
        let idsToRemove = deleteOutcome.idsToRemove
        let didChangeContent = deleteOutcome.didChangeContent

        let activeWasRemoved = activeCardID.map { idsToRemove.contains($0) } ?? false
        let editingWasRemoved = editingCardID.map { idsToRemove.contains($0) } ?? false
        let removalAnchorID = resolveRemovalAnchorID(selected: selected, idsToRemove: idsToRemove)
        let nextCandidate = resolveNextCandidateAfterDelete(
            activeWasRemoved: activeWasRemoved,
            editingWasRemoved: editingWasRemoved,
            removedIDs: idsToRemove,
            removalAnchorID: removalAnchorID,
            focusColumnCardsBeforeDelete: focusColumnCardsBeforeDelete,
            levelsBefore: levelsBefore,
            levelMap: levelMap
        )

        applyPreMutationFocusTransitionForDelete(
            nextCandidate: nextCandidate,
            activeWasRemoved: activeWasRemoved,
            editingWasRemoved: editingWasRemoved
        )

        archiveRemovedCards(idsToRemove)
        persistDeleteSelectionChangesIfNeeded(didChangeContent: didChangeContent, idsToRemove: idsToRemove)
        updateSelectionAfterDelete(
            removedIDs: idsToRemove,
            activeWasRemoved: activeWasRemoved,
            nextCandidate: nextCandidate
        )
        scheduleFocusModeCaretAfterDelete(nextCandidate: nextCandidate)

        isMainViewFocused = true
        if showFocusMode {
            pushFocusUndoState(prevState, actionName: "카드 삭제")
        } else {
            pushUndoState(prevState, actionName: "카드 삭제")
        }
    }

    func prepareFocusModeForDeleteSelectionIfNeeded() {
        guard showFocusMode else { return }
        finalizeFocusTypingCoalescing(reason: "focus-delete-selection")
        focusCaretEnsureWorkItem?.cancel()
        focusCaretEnsureWorkItem = nil
        focusCaretPendingTypewriter = false
        focusTypewriterDeferredUntilCompositionEnd = false
        clearFocusDeleteSelectionLock()
    }

    func buildLevelMap(from levels: [[SceneCard]]) -> [UUID: Int] {
        var levelMap: [UUID: Int] = [:]
        for (levelIndex, cards) in levels.enumerated() {
            for card in cards {
                levelMap[card.id] = levelIndex
            }
        }
        return levelMap
    }

    func resolveDeleteSelectionOutcome(from selected: [SceneCard]) -> (idsToRemove: Set<UUID>, didChangeContent: Bool) {
        var idsToRemove: Set<UUID> = []
        var didChangeContent = false
        let isMultiSelection = selected.count > 1

        if !isMultiSelection, let card = selected.first {
            if card.children.isEmpty {
                idsToRemove.insert(card.id)
            } else {
                idsToRemove.formUnion(subtreeIDs(of: card))
            }
            return (idsToRemove, didChangeContent)
        }

        for card in selected {
            if card.children.isEmpty {
                idsToRemove.insert(card.id)
            } else {
                if !card.content.isEmpty {
                    createArchivedCopy(from: card)
                }
                card.content = ""
                didChangeContent = true
            }
        }
        return (idsToRemove, didChangeContent)
    }

    func resolveRemovalAnchorID(selected: [SceneCard], idsToRemove: Set<UUID>) -> UUID? {
        if let active = activeCardID, idsToRemove.contains(active) {
            return active
        }
        if let editing = editingCardID, idsToRemove.contains(editing) {
            return editing
        }
        return selected.first?.id
    }

    func resolveNextCandidateAfterDelete(
        activeWasRemoved: Bool,
        editingWasRemoved: Bool,
        removedIDs: Set<UUID>,
        removalAnchorID: UUID?,
        focusColumnCardsBeforeDelete: [SceneCard],
        levelsBefore: [[SceneCard]],
        levelMap: [UUID: Int]
    ) -> SceneCard? {
        guard activeWasRemoved || editingWasRemoved else { return nil }
        if showFocusMode,
           let removalAnchorID,
           let fromSiblingGroup = nextFocusFromSiblingGroupAfterRemoval(
            removedIDs: removedIDs,
            anchorID: removalAnchorID
           ) {
            return fromSiblingGroup
        }
        if showFocusMode,
           let fromColumn = nextFocusFromColumnAfterRemoval(
            removedIDs: removedIDs,
            columnCards: focusColumnCardsBeforeDelete,
            preferredAnchorID: removalAnchorID
           ) {
            return fromColumn
        }
        return nextFocusAfterRemoval(
            removedIDs: removedIDs,
            levelMap: levelMap,
            levels: levelsBefore,
            preferredAnchorID: removalAnchorID
        )
    }

    func applyPreMutationFocusTransitionForDelete(
        nextCandidate: SceneCard?,
        activeWasRemoved: Bool,
        editingWasRemoved: Bool
    ) {
        guard showFocusMode && (activeWasRemoved || editingWasRemoved) else { return }
        if let next = nextCandidate {
            // Pre-switch in the same column before model mutation to avoid transient empty/black frame.
            armFocusDeleteSelectionLock(targetCardID: next.id)
            suppressFocusModeScrollOnce = true
            selectedCardIDs = [next.id]
            changeActiveCard(to: next, shouldFocusMain: false, deferToMainAsync: false, force: true)
            editingCardID = next.id
            editingStartContent = next.content
            editingStartState = captureScenarioState()
            editingIsNewCard = false
            focusModeEditorCardID = next.id
            focusLastCommittedContentByCard[next.id] = next.content
        } else {
            editingCardID = nil
            focusModeEditorCardID = nil
            clearFocusDeleteSelectionLock()
        }
    }

    func archiveRemovedCards(_ idsToRemove: Set<UUID>) {
        guard !idsToRemove.isEmpty else { return }
        for card in scenario.cards where idsToRemove.contains(card.id) {
            card.isArchived = true
        }
        scenario.bumpCardsVersion()
    }

    func persistDeleteSelectionChangesIfNeeded(didChangeContent: Bool, idsToRemove: Set<UUID>) {
        guard didChangeContent || !idsToRemove.isEmpty else { return }
        persistCardMutation(forceSnapshot: true)
    }

    func updateSelectionAfterDelete(
        removedIDs: Set<UUID>,
        activeWasRemoved: Bool,
        nextCandidate: SceneCard?
    ) {
        selectedCardIDs.subtract(removedIDs)
        if activeWasRemoved {
            if let next = nextCandidate {
                if !showFocusMode {
                    selectedCardIDs = [next.id]
                    changeActiveCard(to: next)
                } else if selectedCardIDs.isEmpty {
                    selectedCardIDs = [next.id]
                }
            } else {
                selectedCardIDs = []
                activeCardID = nil
                resetActiveRelationStateCache()
                if showFocusMode {
                    editingCardID = nil
                    focusModeEditorCardID = nil
                }
            }
        } else if selectedCardIDs.isEmpty, let activeID = activeCardID, !removedIDs.contains(activeID) {
            selectedCardIDs = [activeID]
        }
    }

    func scheduleFocusModeCaretAfterDelete(nextCandidate: SceneCard?) {
        guard showFocusMode, let next = nextCandidate else { return }
        focusModeCaretRequestID += 1
        let requestID = focusModeCaretRequestID
        applyFocusModeCaretWithRetry(expectedCardID: next.id, location: 0, retries: 10, requestID: requestID)
        DispatchQueue.main.async {
            requestFocusModeCaretEnsure(typewriter: false, delay: 0.0, force: true)
        }
    }

    // MARK: - Focus Navigation After Removal

    func nextFocusFromSiblingGroupAfterRemoval(
        removedIDs: Set<UUID>,
        anchorID: UUID
    ) -> SceneCard? {
        guard let anchor = findCard(by: anchorID) else { return nil }
        let siblings = anchor.parent?.sortedChildren ?? scenario.rootCards
        guard let index = siblings.firstIndex(where: { $0.id == anchorID }) else { return nil }
        if index + 1 < siblings.count {
            for i in (index + 1)..<siblings.count {
                let candidate = siblings[i]
                if !removedIDs.contains(candidate.id) { return candidate }
            }
        }
        if index > 0 {
            for i in stride(from: index - 1, through: 0, by: -1) {
                let candidate = siblings[i]
                if !removedIDs.contains(candidate.id) { return candidate }
            }
        }
        if let parent = anchor.parent, !removedIDs.contains(parent.id) {
            return parent
        }
        return nil
    }

    func nextFocusFromColumnAfterRemoval(
        removedIDs: Set<UUID>,
        columnCards: [SceneCard],
        preferredAnchorID: UUID?
    ) -> SceneCard? {
        guard !columnCards.isEmpty else { return nil }
        let anchorIndex: Int? = {
            if let preferredAnchorID,
               let index = columnCards.firstIndex(where: { $0.id == preferredAnchorID }) {
                return index
            }
            return columnCards.firstIndex(where: { removedIDs.contains($0.id) })
        }()

        if let index = anchorIndex {
            if index + 1 < columnCards.count {
                for i in (index + 1)..<columnCards.count {
                    let candidate = columnCards[i]
                    if !removedIDs.contains(candidate.id) { return candidate }
                }
            }
            if index > 0 {
                for i in stride(from: index - 1, through: 0, by: -1) {
                    let candidate = columnCards[i]
                    if !removedIDs.contains(candidate.id) { return candidate }
                }
            }
        }

        return columnCards.first(where: { !removedIDs.contains($0.id) })
    }

    func subtreeIDs(of card: SceneCard) -> Set<UUID> {
        var result: Set<UUID> = [card.id]
        for child in card.children {
            result.formUnion(subtreeIDs(of: child))
        }
        return result
    }

    func nextFocusAfterRemoval(
        removedIDs: Set<UUID>,
        levelMap: [UUID: Int],
        levels: [[SceneCard]],
        preferredAnchorID: UUID? = nil
    ) -> SceneCard? {
        func candidateFromSiblings(anchorID: UUID) -> SceneCard? {
            guard let anchor = findCard(by: anchorID) else {
                return nil
            }
            let siblings = anchor.parent?.sortedChildren ?? scenario.rootCards
            guard let index = siblings.firstIndex(where: { $0.id == anchorID }) else {
                return nil
            }

            // Prefer immediate flow in the same sibling group: below first, then above.
            if index + 1 < siblings.count {
                for i in (index + 1)..<siblings.count {
                    let candidate = siblings[i]
                    if !removedIDs.contains(candidate.id) { return candidate }
                }
            }
            if index > 0 {
                for i in stride(from: index - 1, through: 0, by: -1) {
                    let candidate = siblings[i]
                    if !removedIDs.contains(candidate.id) { return candidate }
                }
            }

            if let parent = anchor.parent, !removedIDs.contains(parent.id) {
                return parent
            }
            return nil
        }

        var anchors: [UUID] = []
        if let preferredAnchorID { anchors.append(preferredAnchorID) }
        if let active = activeCardID, !anchors.contains(active) { anchors.append(active) }
        for id in removedIDs where !anchors.contains(id) { anchors.append(id) }

        for anchor in anchors {
            if let candidate = candidateFromSiblings(anchorID: anchor) {
                return candidate
            }
        }

        // Fallback: stay in the same depth if possible, but avoid jumping to descendant columns.
        let removedLevels = levelMap
            .filter { removedIDs.contains($0.key) }
            .map { $0.value }
            .sorted()
        for level in removedLevels {
            guard let levelCards = levels[safe: level] else { continue }
            if let candidate = levelCards.first(where: { !removedIDs.contains($0.id) }) {
                return candidate
            }
        }

        return scenario.rootCards.first { !removedIDs.contains($0.id) }
    }

    func createArchivedCopy(from card: SceneCard) {
        let copy = SceneCard(content: card.content, orderIndex: 0, createdAt: Date(), parent: nil, scenario: scenario, category: card.category, isFloating: false, isArchived: true)
        scenario.cards.append(copy)
        scenario.bumpCardsVersion()
    }

    func setCardColor(_ card: SceneCard, hex: String?) {
        let prevState = captureScenarioState()
        card.colorHex = hex
        commitCardMutation(
            previousState: prevState,
            actionName: "카드 색상"
        )
    }
}

```

--------------------------------
File: ReferenceWindow.swift
--------------------------------

```swift
import SwiftUI
import AppKit
import Combine

enum ReferenceWindowConstants {
    static let windowID = "reference-window"
    static let cardWidth: CGFloat = 404
    static let windowWidth: CGFloat = 428
}

@MainActor
final class ReferenceCardStore: ObservableObject {
    struct Entry: Identifiable, Equatable, Codable {
        let scenarioID: UUID
        let cardID: UUID

        var id: String {
            "\(scenarioID.uuidString)|\(cardID.uuidString)"
        }
    }

    private static let persistedEntriesKey = "reference.card.entries.v1"
    private let maxUndoCount = 1200
    private let typingIdleInterval: TimeInterval = 1.5
    private let saveRequestThrottleInterval: TimeInterval = 0.45

    @Published private(set) var entries: [Entry] = []

    private struct UndoSnapshot {
        let scenarioID: UUID
        let cardID: UUID
        let content: String
    }

    private var undoStack: [UndoSnapshot] = []
    private var redoStack: [UndoSnapshot] = []
    private var coalescingBase: UndoSnapshot? = nil
    private var coalescingEntryID: String? = nil
    private var typingLastEditAt: Date = .distantPast
    private var typingIdleFinalizeWorkItem: DispatchWorkItem? = nil
    private var pendingReturnBoundary: Bool = false
    private var lastCommittedContentByEntryID: [String: String] = [:]
    private var programmaticContentSuppressUntil: Date = .distantPast
    private var pendingSaveRequestWorkItem: DispatchWorkItem? = nil
    private var nextAllowedSaveRequestAt: Date = .distantPast

    init() {
        loadPersistedEntries()
    }

    func addCard(cardID: UUID, scenarioID: UUID) {
        let newEntry = Entry(scenarioID: scenarioID, cardID: cardID)
        guard !entries.contains(newEntry) else { return }
        entries.append(newEntry)
        persistEntries()
    }

    func removeCard(cardID: UUID, scenarioID: UUID) {
        finalizeTypingCoalescing(reason: "remove-card")
        entries.removeAll { $0.cardID == cardID && $0.scenarioID == scenarioID }
        lastCommittedContentByEntryID.removeValue(forKey: entryID(scenarioID: scenarioID, cardID: cardID))
        persistEntries()
    }

    func pruneMissingEntries(fileStore: FileStore) {
        let valid = entries.filter { entry in
            guard let scenario = fileStore.scenarios.first(where: { $0.id == entry.scenarioID }) else { return false }
            return scenario.cardByID(entry.cardID) != nil
        }
        if valid != entries {
            entries = valid
            persistEntries()
        }
    }

    func handleContentChange(
        scenarioID: UUID,
        cardID: UUID,
        oldValue: String,
        newValue: String,
        fileStore: FileStore
    ) {
        guard oldValue != newValue else { return }

        let id = entryID(scenarioID: scenarioID, cardID: cardID)
        let delta = utf16ChangeDelta(oldValue: oldValue, newValue: newValue)

        if Date() < programmaticContentSuppressUntil {
            lastCommittedContentByEntryID[id] = newValue
            requestCoalescedSave(fileStore: fileStore)
            return
        }

        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           textView.hasMarkedText() {
            requestCoalescedSave(fileStore: fileStore)
            return
        }

        let now = Date()
        let shouldBreakByGap = now.timeIntervalSince(typingLastEditAt) > typingIdleInterval
        let shouldBreakByCard = coalescingEntryID != nil && coalescingEntryID != id
        if shouldBreakByGap || shouldBreakByCard {
            finalizeTypingCoalescing(reason: shouldBreakByCard ? "typing-card-switch" : "typing-gap")
        }

        if coalescingBase == nil {
            let committedOld = lastCommittedContentByEntryID[id] ?? oldValue
            coalescingBase = UndoSnapshot(scenarioID: scenarioID, cardID: cardID, content: committedOld)
            coalescingEntryID = id
        }

        typingLastEditAt = now
        lastCommittedContentByEntryID[id] = newValue
        scheduleTypingIdleFinalize()

        if pendingReturnBoundary {
            pendingReturnBoundary = false
            if delta.newChangedLength > 0 && delta.inserted.contains("\n") {
                finalizeTypingCoalescing(reason: "typing-boundary-return")
                requestCoalescedSave(fileStore: fileStore, immediate: true)
                return
            }
        }

        if isStrongTextBoundaryChange(newValue: newValue, delta: delta) {
            finalizeTypingCoalescing(reason: "typing-boundary")
        }

        requestCoalescedSave(fileStore: fileStore)
    }

    func performUndo(fileStore: FileStore) -> Bool {
        finalizeTypingCoalescing(reason: "undo-request")
        guard let previous = undoStack.popLast() else { return true }
        guard let scenario = fileStore.scenarios.first(where: { $0.id == previous.scenarioID }),
              let card = scenario.cardByID(previous.cardID) else {
            return true
        }

        let current = UndoSnapshot(scenarioID: previous.scenarioID, cardID: previous.cardID, content: card.content)
        redoStack.append(current)
        if redoStack.count > maxUndoCount {
            redoStack.removeFirst(redoStack.count - maxUndoCount)
        }

        programmaticContentSuppressUntil = Date().addingTimeInterval(0.4)
        card.content = previous.content
        lastCommittedContentByEntryID[entryID(scenarioID: previous.scenarioID, cardID: previous.cardID)] = previous.content
        requestCoalescedSave(fileStore: fileStore, immediate: true)
        return true
    }

    func performRedo(fileStore: FileStore) -> Bool {
        finalizeTypingCoalescing(reason: "redo-request")
        guard let next = redoStack.popLast() else { return true }
        guard let scenario = fileStore.scenarios.first(where: { $0.id == next.scenarioID }),
              let card = scenario.cardByID(next.cardID) else {
            return true
        }

        let current = UndoSnapshot(scenarioID: next.scenarioID, cardID: next.cardID, content: card.content)
        undoStack.append(current)
        if undoStack.count > maxUndoCount {
            undoStack.removeFirst(undoStack.count - maxUndoCount)
        }

        programmaticContentSuppressUntil = Date().addingTimeInterval(0.4)
        card.content = next.content
        lastCommittedContentByEntryID[entryID(scenarioID: next.scenarioID, cardID: next.cardID)] = next.content
        requestCoalescedSave(fileStore: fileStore, immediate: true)
        return true
    }

    private func requestCoalescedSave(fileStore: FileStore, immediate: Bool = false) {
        if immediate {
            pendingSaveRequestWorkItem?.cancel()
            pendingSaveRequestWorkItem = nil
            nextAllowedSaveRequestAt = Date().addingTimeInterval(saveRequestThrottleInterval)
            fileStore.saveAll()
            return
        }

        let now = Date()
        if now >= nextAllowedSaveRequestAt {
            nextAllowedSaveRequestAt = now.addingTimeInterval(saveRequestThrottleInterval)
            fileStore.saveAll()
            return
        }

        pendingSaveRequestWorkItem?.cancel()
        let delay = max(0, nextAllowedSaveRequestAt.timeIntervalSince(now))
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingSaveRequestWorkItem = nil
            self.nextAllowedSaveRequestAt = Date().addingTimeInterval(self.saveRequestThrottleInterval)
            fileStore.saveAll()
        }
        pendingSaveRequestWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func flushPendingSaveIfNeeded(fileStore: FileStore) {
        guard pendingSaveRequestWorkItem != nil else { return }
        pendingSaveRequestWorkItem?.cancel()
        pendingSaveRequestWorkItem = nil
        nextAllowedSaveRequestAt = Date()
        fileStore.saveAll()
    }

    private func pushUndoState(_ previous: UndoSnapshot) {
        undoStack.append(previous)
        if undoStack.count > maxUndoCount {
            undoStack.removeFirst(undoStack.count - maxUndoCount)
        }
        redoStack.removeAll()
    }

    private func scheduleTypingIdleFinalize() {
        typingIdleFinalizeWorkItem?.cancel()
        let work = DispatchWorkItem {
            self.finalizeTypingCoalescing(reason: "typing-idle")
        }
        typingIdleFinalizeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + typingIdleInterval, execute: work)
    }

    private func finalizeTypingCoalescing(reason: String) {
        typingIdleFinalizeWorkItem?.cancel()
        typingIdleFinalizeWorkItem = nil
        guard let base = coalescingBase else { return }
        _ = reason
        coalescingBase = nil
        coalescingEntryID = nil
        pushUndoState(base)
    }

    private func utf16ChangeDelta(oldValue: String, newValue: String) -> (prefix: Int, oldChangedLength: Int, newChangedLength: Int, inserted: String) {
        sharedUTF16ChangeDeltaValue(oldValue: oldValue, newValue: newValue)
    }

    private func isStrongTextBoundaryChange(
        newValue: String,
        delta: (prefix: Int, oldChangedLength: Int, newChangedLength: Int, inserted: String)
    ) -> Bool {
        guard delta.newChangedLength > 0 else { return false }
        let newText = newValue as NSString
        if delta.inserted.contains("\n") {
            return containsParagraphBreakBoundary(in: newText, delta: delta)
        }
        return containsSentenceEndingPeriodBoundary(in: newText, delta: delta)
    }

    private func containsParagraphBreakBoundary(
        in text: NSString,
        delta: (prefix: Int, oldChangedLength: Int, newChangedLength: Int, inserted: String)
    ) -> Bool {
        sharedHasParagraphBreakBoundary(in: text, delta: delta)
    }

    private func lineHasSignificantContentBeforeBreak(in text: NSString, breakIndex: Int) -> Bool {
        sharedLineHasSignificantContentBeforeBreak(in: text, breakIndex: breakIndex)
    }

    private func containsSentenceEndingPeriodBoundary(
        in text: NSString,
        delta: (prefix: Int, oldChangedLength: Int, newChangedLength: Int, inserted: String)
    ) -> Bool {
        sharedHasSentenceEndingPeriodBoundarySimple(in: text, delta: delta)
    }

    private func entryID(scenarioID: UUID, cardID: UUID) -> String {
        "\(scenarioID.uuidString)|\(cardID.uuidString)"
    }

    private func loadPersistedEntries() {
        guard let data = UserDefaults.standard.data(forKey: Self.persistedEntriesKey) else { return }
        guard let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = decoded
    }

    private func persistEntries() {
        guard let encoded = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(encoded, forKey: Self.persistedEntriesKey)
    }
}

struct ReferenceWindowView: View {
    @EnvironmentObject private var store: FileStore
    @EnvironmentObject private var referenceCardStore: ReferenceCardStore
    @AppStorage("fontSize") private var fontSize: Double = 14.0
    @AppStorage("mainCardLineSpacingValueV2") private var mainCardLineSpacingValue: Double = 5.0
    @AppStorage("appearance") private var appearance: String = "dark"
    @AppStorage("cardActiveColorHex") private var cardActiveColorHex: String = "BFD7FF"
    @AppStorage("darkCardActiveColorHex") private var darkCardActiveColorHex: String = "2A3A4E"
    @FocusState private var focusedEntryID: String?
    private let referenceCardWidth: CGFloat = ReferenceWindowConstants.cardWidth

    private var referenceFontSize: CGFloat {
        max(8, CGFloat(fontSize * 0.8))
    }

    private var referenceLineSpacing: CGFloat {
        CGFloat(mainCardLineSpacingValue)
    }

    private var renderSettings: ReferenceCardRenderSettings {
        ReferenceCardRenderSettings(
            fontSize: referenceFontSize,
            appearance: appearance,
            lineSpacing: referenceLineSpacing,
            cardActiveColorHex: cardActiveColorHex,
            darkCardActiveColorHex: darkCardActiveColorHex
        )
    }

    private struct ResolvedEntry: Identifiable {
        let entry: ReferenceCardStore.Entry
        let card: SceneCard

        var id: String { entry.id }
    }

    private var resolvedEntries: [ResolvedEntry] {
        referenceCardStore.entries.compactMap { entry in
            guard let scenario = store.scenarios.first(where: { $0.id == entry.scenarioID }) else { return nil }
            guard let card = scenario.cardByID(entry.cardID) else { return nil }
            return ResolvedEntry(entry: entry, card: card)
        }
    }

    private var panelBackground: Color {
        appearance == "light" ? Color(red: 0.95, green: 0.95, blue: 0.94) : Color(red: 0.12, green: 0.13, blue: 0.15)
    }

    var body: some View {
        ZStack {
            panelBackground
                .ignoresSafeArea()

            if resolvedEntries.isEmpty {
                Text("레퍼런스 카드가 없습니다")
                    .font(.custom("SansMonoCJKFinalDraft", size: 14))
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(resolvedEntries) { resolved in
                            ReferenceCardEditorRow(
                                scenarioID: resolved.entry.scenarioID,
                                cardID: resolved.entry.cardID,
                                entryID: resolved.entry.id,
                                card: resolved.card,
                                renderSettings: renderSettings,
                                cardWidth: referenceCardWidth,
                                focusedEntryID: $focusedEntryID,
                                onContentChange: { scenarioID, cardID, oldValue, newValue in
                                    referenceCardStore.handleContentChange(
                                        scenarioID: scenarioID,
                                        cardID: cardID,
                                        oldValue: oldValue,
                                        newValue: newValue,
                                        fileStore: store
                                    )
                                },
                                onRemove: {
                                    referenceCardStore.removeCard(cardID: resolved.entry.cardID, scenarioID: resolved.entry.scenarioID)
                                }
                            )
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(FloatingReferenceWindowAccessor())
        .onAppear {
            referenceCardStore.pruneMissingEntries(fileStore: store)
        }
        .onChange(of: focusedEntryID) { _, newValue in
            if newValue == nil {
                referenceCardStore.flushPendingSaveIfNeeded(fileStore: store)
            }
        }
        .onDisappear {
            referenceCardStore.flushPendingSaveIfNeeded(fileStore: store)
        }
    }
}

private struct ReferenceCardEditorRow: View {
    let scenarioID: UUID
    let cardID: UUID
    let entryID: String
    @ObservedObject var card: SceneCard
    let renderSettings: ReferenceCardRenderSettings
    let cardWidth: CGFloat
    @FocusState.Binding var focusedEntryID: String?
    let onContentChange: (UUID, UUID, String, String) -> Void
    let onRemove: () -> Void

    @State private var measuredBodyHeight: CGFloat = 0
    @State private var isHovering: Bool = false
    @State private var caretVisibilityWorkItem: DispatchWorkItem? = nil

    private let outerPadding: CGFloat = 10
    private let editorVerticalPadding: CGFloat = 16
    private var appearance: String { renderSettings.appearance }
    private var fontSize: CGFloat { renderSettings.fontSize }
    private var lineSpacing: CGFloat { renderSettings.lineSpacing }
    private var cardActiveColorHex: String { renderSettings.cardActiveColorHex }
    private var darkCardActiveColorHex: String { renderSettings.darkCardActiveColorHex }

    private var isReferenceWindowFocused: Bool {
        NSApp.keyWindow?.identifier?.rawValue == ReferenceWindowConstants.windowID
    }

    private var editorHorizontalPadding: CGFloat {
        MainEditorLayoutMetrics.mainEditorHorizontalPadding
    }

    private var measuredEditorWidth: CGFloat {
        max(1, cardWidth - (outerPadding * 2) - (editorHorizontalPadding * 2))
    }

    private var measurementSafetyInset: CGFloat {
        max(12, lineSpacing + 8)
    }

    private var resolvedEditorHeight: CGFloat {
        max(1, measuredBodyHeight)
    }

    private var isDarkAppearanceActive: Bool {
        if appearance == "dark" { return true }
        if appearance == "light" { return false }
        if let best = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
            return best == .darkAqua
        }
        return true
    }

    private var referenceCardBackgroundColor: Color {
        let fallbackLight = (r: 0.75, g: 0.84, b: 1.0)
        let fallbackDark = (r: 0.16, g: 0.23, b: 0.31)
        let hex = isDarkAppearanceActive ? darkCardActiveColorHex : cardActiveColorHex
        if let rgb = rgbFromHex(hex) {
            return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
        }
        let fallback = isDarkAppearanceActive ? fallbackDark : fallbackLight
        return Color(red: fallback.r, green: fallback.g, blue: fallback.b)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(referenceCardBackgroundColor)

            VStack(alignment: .leading, spacing: 0) {
                TextEditor(text: Binding(
                    get: { card.content },
                    set: { newValue in
                        let oldValue = card.content
                        card.content = newValue
                        focusedEntryID = entryID
                        refreshMeasuredBodyHeight(for: newValue)
                        onContentChange(scenarioID, cardID, oldValue, newValue)
                        requestCaretVisibilityEnsure()
                    }
                ))
                .font(.custom("SansMonoCJKFinalDraft", size: Double(fontSize)))
                .lineSpacing(lineSpacing)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .scrollIndicators(.never)
                .frame(height: resolvedEditorHeight, alignment: .topLeading)
                .padding(.horizontal, editorHorizontalPadding)
                .padding(.vertical, editorVerticalPadding)
                .foregroundStyle(isDarkAppearanceActive ? .white : .black)
                .focused($focusedEntryID, equals: entryID)
            }
            .padding(outerPadding)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .padding(7)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .padding(.top, 14)
            .padding(.trailing, 8)
            .animation(.easeInOut(duration: 0.12), value: isHovering)
        }
        .frame(width: cardWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear {
            refreshMeasuredBodyHeight()
            DispatchQueue.main.async {
                refreshMeasuredBodyHeight()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                refreshMeasuredBodyHeight()
            }
        }
        .onChange(of: card.content) { _, newValue in
            DispatchQueue.main.async {
                refreshMeasuredBodyHeight(for: newValue)
                requestCaretVisibilityEnsure()
            }
        }
        .onChange(of: fontSize) { _, _ in
            refreshMeasuredBodyHeight()
            requestCaretVisibilityEnsure()
        }
        .onChange(of: lineSpacing) { _, _ in
            refreshMeasuredBodyHeight()
            requestCaretVisibilityEnsure()
        }
        .onChange(of: focusedEntryID) { _, newValue in
            if newValue == entryID {
                refreshMeasuredBodyHeight()
                requestCaretVisibilityEnsure()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSTextView.didChangeSelectionNotification)) { notification in
            guard focusedEntryID == entryID else { return }
            guard isReferenceWindowFocused else { return }
            guard let textView = notification.object as? NSTextView else { return }
            guard textView.window?.identifier?.rawValue == ReferenceWindowConstants.windowID else { return }
            guard (NSApp.keyWindow?.firstResponder as? NSTextView) === textView else { return }
            guard textView.string == card.content else { return }
            requestCaretVisibilityEnsure(delay: 0.0)
        }
        .onDisappear {
            caretVisibilityWorkItem?.cancel()
            caretVisibilityWorkItem = nil
        }
    }

    private func requestCaretVisibilityEnsure(delay: Double = 0.012) {
        caretVisibilityWorkItem?.cancel()
        let work = DispatchWorkItem {
            ensureCaretVisibleInReferenceWindow()
        }
        caretVisibilityWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func outerScrollView(containing textView: NSTextView) -> NSScrollView? {
        var node: NSView? = textView
        while let view = node {
            if let scrollView = view as? NSScrollView,
               scrollView.documentView !== textView.enclosingScrollView?.documentView {
                return scrollView
            }
            node = view.superview
        }
        return nil
    }

    private func ensureCaretVisibleInReferenceWindow() {
        guard focusedEntryID == entryID else { return }
        guard isReferenceWindowFocused else { return }
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        guard textView.window?.identifier?.rawValue == ReferenceWindowConstants.windowID else { return }
        guard textView.string == card.content else { return }
        guard let outerScrollView = outerScrollView(containing: textView) else { return }
        guard let outerDocumentView = outerScrollView.documentView else { return }
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }

        layoutManager.ensureLayout(for: textContainer)
        let textLength = (textView.string as NSString).length
        let selection = textView.selectedRange()
        let caretLocation = min(max(0, selection.location + selection.length), textLength)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: caretLocation, length: 0),
            actualCharacterRange: nil
        )
        var caretRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        caretRect.origin.x += textView.textContainerInset.width
        caretRect.origin.y += textView.textContainerInset.height
        if caretRect.height < fontSize {
            caretRect.size.height = fontSize + 2
        }
        let caretRectInDocument = outerDocumentView.convert(caretRect, from: textView)

        let visible = outerScrollView.documentVisibleRect
        let insets = outerScrollView.contentInsets
        let clipOriginY = outerScrollView.contentView.bounds.origin.y
        let inferredTopInset = max(0, -clipOriginY)
        let effectiveTopInset = max(insets.top, inferredTopInset)
        let minY = -effectiveTopInset
        let documentHeight = outerDocumentView.bounds.height
        let maxY = max(minY, documentHeight - visible.height + insets.bottom)

        let topPadding: CGFloat = 48
        let bottomPadding: CGFloat = 64
        let minVisibleY = visible.minY + topPadding
        let maxVisibleY = visible.maxY - bottomPadding

        var targetY = visible.origin.y
        if caretRectInDocument.maxY > maxVisibleY {
            targetY = caretRectInDocument.maxY - (visible.height - bottomPadding)
        } else if caretRectInDocument.minY < minVisibleY {
            targetY = max(minY, caretRectInDocument.minY - topPadding)
        }

        let clampedY = min(max(minY, targetY), maxY)
        if abs(clampedY - visible.origin.y) > 0.5 {
            outerScrollView.contentView.setBoundsOrigin(NSPoint(x: visible.origin.x, y: clampedY))
            outerScrollView.reflectScrolledClipView(outerScrollView.contentView)
        }
    }

    private func refreshMeasuredBodyHeight(for text: String? = nil) {
        let resolvedText = text ?? card.content
        let measured: CGFloat
        if focusedEntryID == entryID,
           let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           textView.window?.identifier?.rawValue == ReferenceWindowConstants.windowID,
           textView.string == resolvedText,
           let liveMeasured = liveFocusedBodyHeight(for: textView) {
            measured = liveMeasured
        } else {
            measured = sharedMeasuredTextBodyHeight(
                text: resolvedText,
                fontSize: fontSize,
                lineSpacing: lineSpacing,
                width: measuredEditorWidth,
                lineFragmentPadding: MainEditorLayoutMetrics.mainEditorLineFragmentPadding,
                safetyInset: measurementSafetyInset
            )
        }
        if abs(measuredBodyHeight - measured) > 0.25 {
            var noAnimation = Transaction()
            noAnimation.animation = nil
            withTransaction(noAnimation) {
                measuredBodyHeight = measured
            }
        }
    }

    private func rgbFromHex(_ hex: String) -> (Double, Double, Double)? {
        parseHexRGB(hex, stripAllHashes: true)
    }

    private func liveFocusedBodyHeight(for textView: NSTextView) -> CGFloat? {
        sharedLiveTextViewBodyHeight(
            textView,
            safetyInset: measurementSafetyInset,
            includeTextContainerInset: true
        )
    }
}

private struct FloatingReferenceWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.identifier = NSUserInterfaceItemIdentifier(ReferenceWindowConstants.windowID)
            window.title = "레퍼런스 카드"
            window.level = .floating
            window.collectionBehavior.insert(.fullScreenAuxiliary)
            let fixedWidth = ReferenceWindowConstants.windowWidth
            window.minSize = NSSize(width: fixedWidth, height: 220)
            window.maxSize = NSSize(width: fixedWidth, height: 2000)
            window.contentMinSize = NSSize(width: fixedWidth, height: 220)
            window.contentMaxSize = NSSize(width: fixedWidth, height: 10000)
            if abs(window.frame.width - fixedWidth) > 0.5 {
                var frame = window.frame
                frame.size.width = fixedWidth
                window.setFrame(frame, display: true)
            }
            window.styleMask.remove(.resizable)
        }
    }
}

```

--------------------------------
File: waApp.swift
--------------------------------

```swift
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
    private static let originXKey = "mainWorkspaceWindowOriginXV1"
    private static let originYKey = "mainWorkspaceWindowOriginYV1"
    private static let fullscreenKey = "mainWorkspaceWindowFullscreenV1"

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
        private var didRestoreWindowState = false
        private var isRestoringWindowState = false
        private var pendingFullscreenRestore = false

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
                didRestoreWindowState = false
                isRestoringWindowState = false
                pendingFullscreenRestore = false
                installObservers(for: attachedWindow)
            }

            restoreWindowStateIfNeeded(for: attachedWindow)
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
                center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
                    self?.persistSize(from: window)
                }
            )
            observers.append(
                center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                    self?.persistFrame(from: window)
                }
            )
            observers.append(
                center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                    self?.persistSize(from: window)
                    self?.finishFullscreenRestoreIfNeeded()
                }
            )
            observers.append(
                center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                    self?.persistSize(from: window)
                    self?.finishFullscreenRestoreIfNeeded()
                }
            )
            observers.append(
                center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                    self?.persistSize(from: window)
                }
            )
            observers.append(
                center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
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

        private func restoreWindowStateIfNeeded(for window: NSWindow) {
            guard !didRestoreWindowState else { return }
            didRestoreWindowState = true
            let defaults = UserDefaults.standard
            let hasSavedOrigin = defaults.object(forKey: MainWindowSizePersistenceAccessor.originXKey) != nil
                && defaults.object(forKey: MainWindowSizePersistenceAccessor.originYKey) != nil
            let width = defaults.double(forKey: MainWindowSizePersistenceAccessor.widthKey)
            let height = defaults.double(forKey: MainWindowSizePersistenceAccessor.heightKey)
            let originX = defaults.double(forKey: MainWindowSizePersistenceAccessor.originXKey)
            let originY = defaults.double(forKey: MainWindowSizePersistenceAccessor.originYKey)
            let shouldRestoreFullscreen = defaults.bool(forKey: MainWindowSizePersistenceAccessor.fullscreenKey)

            isRestoringWindowState = true

            if width >= 500, height >= 400 {
                var frame = window.frame
                frame.size = NSSize(width: width, height: height)
                if hasSavedOrigin {
                    frame.origin = CGPoint(x: originX, y: originY)
                }
                let clampedFrame = clampedFrameToVisibleScreens(frame)
                if abs(window.frame.origin.x - clampedFrame.origin.x) > 0.5
                    || abs(window.frame.origin.y - clampedFrame.origin.y) > 0.5
                    || abs(window.frame.size.width - clampedFrame.size.width) > 0.5
                    || abs(window.frame.size.height - clampedFrame.size.height) > 0.5 {
                    window.setFrame(clampedFrame, display: true)
                }
            }

            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                if shouldRestoreFullscreen, !window.styleMask.contains(.fullScreen) {
                    self.pendingFullscreenRestore = true
                    window.toggleFullScreen(nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                        self?.finishFullscreenRestoreIfNeeded()
                    }
                } else {
                    self.isRestoringWindowState = false
                }
            }
        }

        private func clampedFrameToVisibleScreens(_ frame: CGRect) -> CGRect {
            let screens = NSScreen.screens
            guard !screens.isEmpty else { return frame }
            if screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                return frame
            }

            let visibleFrame = (window?.screen ?? NSScreen.main ?? screens[0]).visibleFrame
            let width = min(frame.width, visibleFrame.width)
            let height = min(frame.height, visibleFrame.height)
            let x = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - width)
            let y = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - height)
            return CGRect(x: x, y: y, width: width, height: height)
        }

        private func finishFullscreenRestoreIfNeeded() {
            guard pendingFullscreenRestore else {
                isRestoringWindowState = false
                return
            }
            pendingFullscreenRestore = false
            isRestoringWindowState = false
        }

        private func persistFrame(from window: NSWindow) {
            guard window.identifier?.rawValue != ReferenceWindowConstants.windowID else { return }
            let width = window.frame.width
            let height = window.frame.height
            guard width >= 500, height >= 400 else { return }
            let defaults = UserDefaults.standard
            defaults.set(width, forKey: MainWindowSizePersistenceAccessor.widthKey)
            defaults.set(height, forKey: MainWindowSizePersistenceAccessor.heightKey)
            defaults.set(window.frame.origin.x, forKey: MainWindowSizePersistenceAccessor.originXKey)
            defaults.set(window.frame.origin.y, forKey: MainWindowSizePersistenceAccessor.originYKey)
        }

        private func persistSize(from window: NSWindow) {
            guard window.identifier?.rawValue != ReferenceWindowConstants.windowID else { return }
            guard !isRestoringWindowState else { return }
            let defaults = UserDefaults.standard
            let isFullscreen = window.styleMask.contains(.fullScreen)
            defaults.set(isFullscreen, forKey: MainWindowSizePersistenceAccessor.fullscreenKey)
            guard !isFullscreen else { return }
            persistFrame(from: window)
        }
    }
}

@main
struct waApp: App {
    @AppStorage("fontSize") private var fontSize: Double = 14.0
    @AppStorage("mainWorkspaceZoomScale") private var mainWorkspaceZoomScale: Double = 1.0
    @AppStorage("mainCanvasHorizontalScrollMode") private var mainCanvasHorizontalScrollModeRawValue: Int = MainCanvasHorizontalScrollMode.twoStep.rawValue
    @AppStorage("focusNavigationAnimationEnabled") private var focusNavigationAnimationEnabled: Bool = false
    @AppStorage("focusTypewriterEnabled") private var focusTypewriterEnabled: Bool = false
    @AppStorage("mainSplitModeEnabled") private var mainSplitModeEnabled: Bool = false
    @AppStorage("appearance") private var appearance: String = "dark"
    @AppStorage("backgroundColorHex") private var backgroundColorHex: String = "F4F2EE"
    @AppStorage("darkBackgroundColorHex") private var darkBackgroundColorHex: String = "111418"
    @AppStorage("forceWorkspaceReset") private var forceWorkspaceReset: Bool = false
    @AppStorage("didResetForV2") private var didResetForV2: Bool = false
    @AppStorage("autoBackupEnabledOnQuit") private var autoBackupEnabledOnQuit: Bool = true
    @AppStorage("autoBackupDirectoryPath") private var autoBackupDirectoryPath: String = ""

    // 폴더 접근 권한을 유지하기 위한 북마크 데이터 저장
    @AppStorage("storageBookmark") private var storageBookmark: Data?

    // 현재 활성화된 파일 스토어를 관리
    @State private var store: FileStore?
    @StateObject private var appWindowState = AppWindowState()
    @StateObject private var referenceCardStore = ReferenceCardStore()
    @State private var didHideReferenceWindowOnLaunch: Bool = false
    @State private var storeSetupRequestID: Int = 0

    init() {
        UserDefaults.standard.set(false, forKey: "TSMLanguageIndicatorEnabled")
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(nsColor: appWindowState.focusModeWindowBackgroundActive ? .black : resolvedWindowBackgroundColor)
                    .ignoresSafeArea()
                Group {
                    if let store = store {
                        // 스토어가 준비되면 메인 뷰 표시
                        MainContainerView()
                            .environmentObject(store)
                            .environmentObject(appWindowState)
                            .environmentObject(referenceCardStore)
                    } else {
                        // 컨테이너가 없으면(최초 실행 시) 설정 화면 표시
                        storageSetupView
                    }
                }
            }
            .background(MainWindowTitleHider())
            .background(MainWindowSizePersistenceAccessor())
            .onAppear {
                applyApplicationAppearance()
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
                preloadSoftBoundaryFeedbackSound()
                appWindowState.focusModeWindowBackgroundActive = false
                hideReferenceWindowOnLaunchOnce()
            }
            .onChange(of: appearance) { _, _ in
                applyApplicationAppearance()
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

                Picker("메인 캔버스 좌우 스크롤", selection: $mainCanvasHorizontalScrollModeRawValue) {
                    ForEach(MainCanvasHorizontalScrollMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                Divider()

                Toggle("포커스 이동 애니메이션", isOn: $focusNavigationAnimationEnabled)
                Divider()

                Toggle("포커스 모드 타이프라이터", isOn: $focusTypewriterEnabled)
                Divider()

                Button("메인 작업창 줌 축소") {
                    adjustMainWorkspaceZoom(by: -0.05)
                }
                .keyboardShortcut("-", modifiers: [.command])
                .disabled(mainWorkspaceZoomScale <= 0.70)

                Button("메인 작업창 줌 확대") {
                    adjustMainWorkspaceZoom(by: 0.05)
                }
                .keyboardShortcut("=", modifiers: [.command])
                .disabled(mainWorkspaceZoomScale >= 1.60)

                Button("메인 작업창 줌 100%") {
                    mainWorkspaceZoomScale = 1.0
                }
                .keyboardShortcut("0", modifiers: [.command])
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
        storeSetupRequestID += 1
        let requestID = storeSetupRequestID

        store?.flushPendingSaves()
        store = nil

        guard let bookmark = storageBookmark else { return }

        Task { @MainActor in
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
                guard requestID == storeSetupRequestID else { return }

                self.store = newStore
            } catch {
                guard requestID == storeSetupRequestID else { return }
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

    private func applyApplicationAppearance() {
        NSApp.appearance = resolvedApplicationAppearance()
    }

    private func resolvedApplicationAppearance() -> NSAppearance? {
        if appearance == "dark" {
            return NSAppearance(named: .darkAqua)
        }
        if appearance == "light" {
            return NSAppearance(named: .aqua)
        }
        return nil
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

```
