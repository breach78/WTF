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
    var resolvedLevelsWithParentsCache: [ScenarioWriterView.LevelData] = []
    var displayedMainLevelsCacheKey: ScenarioWriterView.DisplayedMainLevelsCacheKey? = nil
    var displayedMainLevelsCache: [ScenarioWriterView.LevelData] = []
    var displayedMainCardLocationByIDCache: [UUID: (level: Int, index: Int)] = [:]
    var mainColumnLastFocusRequestByKey: [String: ScenarioWriterView.MainColumnFocusRequest] = [:]
    var mainColumnViewportOffsetByKey: [String: CGFloat] = [:]
    var mainColumnObservedCardFramesByKey: [String: [UUID: CGRect]] = [:]
    var mainColumnLayoutSnapshotByKey: [ScenarioWriterView.MainColumnLayoutCacheKey: ScenarioWriterView.MainColumnLayoutSnapshot] = [:]
    var mainCardHeightRecordByKey: [ScenarioWriterView.MainCardHeightCacheKey: ScenarioWriterView.MainCardHeightRecord] = [:]
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
    var mainSelectionActiveEdge: ScenarioWriterView.MainSelectionActiveEdge = .end
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
    @Published var candidateState = ScenarioWriterView.AICandidateTrackingState()
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
