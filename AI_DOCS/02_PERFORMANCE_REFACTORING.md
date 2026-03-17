# PHASE 2 — PERFORMANCE REFACTORING

## Goals
- Preserve all visible behavior and persistence semantics.
- Reduce root-view state sprawl in the main writer.
- Tighten SwiftUI invalidation boundaries around AI and edit-end backup flows.
- Improve teardown safety for in-flight AI work and deferred persistence.

## Implemented Refactor
- Extracted AI feature state from `ScenarioWriterView` into `WriterAIFeatureState`.
- Extracted edit-end auto-backup scheduling state from `ScenarioWriterView` into `WriterEditEndAutoBackupState`.
- Kept the existing call sites stable by exposing computed proxy properties and explicit `Binding` helpers from `ScenarioWriterView`.
- Flushed pending AI thread and embedding persistence, and cancelled active AI requests during workspace teardown.
- Preserved existing feature behavior, persistence contracts, and UI composition.

## Performance And Safety Impact
- Reduced the amount of root `@State` owned directly by the massive writer view.
- Moved AI UI-driving state behind a dedicated `ObservableObject`, making ownership clearer and future extraction into a ViewModel or coordinator simpler.
- Kept non-UI AI caches and work items outside `@Published` so they do not trigger unnecessary SwiftUI invalidation.
- Centralized cancellation of pending AI work items and request tasks in the dedicated AI state container and workspace teardown path.
- Isolated edit-end auto-backup bookkeeping from the writer root, reducing unrelated view identity churn.

## Verification
- `xcodebuild -project wa.xcodeproj -scheme wa -configuration Debug build`
- Result: `BUILD SUCCEEDED`

## Complete Updated Files

--------------------------------
File: WriterSharedTypes.swift
--------------------------------
```swift
import SwiftUI
import AppKit
import Combine
import QuartzCore

let focusModeBodySafetyInset: CGFloat = 8

#if DEBUG
func bounceDebugLog(_ message: @autoclosure () -> String) {}
#else
func bounceDebugLog(_ message: @autoclosure () -> String) {}
#endif

@MainActor
func playSoftBoundaryFeedbackSound() {
    enum SoftBoundaryFeedbackSound {
        @MainActor static let shared: NSSound? = {
            let url = URL(fileURLWithPath: "/System/Library/Sounds/Pop.aiff")
            let sound = NSSound(contentsOf: url, byReference: true)
            sound?.volume = 0.16
            return sound
        }()
    }

    guard let sound = SoftBoundaryFeedbackSound.shared else { return }
    if sound.isPlaying {
        sound.stop()
    }
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
    var pendingActiveCardID: UUID? = nil
    var resolvedLevelsWithParentsVersion: Int = -1
    var resolvedLevelsWithParentsCache: [ScenarioWriterView.LevelData] = []
    var displayedMainLevelsCacheKey: ScenarioWriterView.DisplayedMainLevelsCacheKey? = nil
    var displayedMainLevelsCache: [ScenarioWriterView.LevelData] = []
    var displayedMainCardLocationByIDCache: [UUID: (level: Int, index: Int)] = [:]
    var mainColumnLastFocusRequestByKey: [String: ScenarioWriterView.MainColumnFocusRequest] = [:]
    var mainColumnViewportOffsetByKey: [String: CGFloat] = [:]
    var mainColumnObservedCardFramesByKey: [String: [UUID: CGRect]] = [:]
    var mainColumnLayoutSnapshotByKey: [ScenarioWriterView.MainColumnLayoutCacheKey: ScenarioWriterView.MainColumnLayoutSnapshot] = [:]
    var mainColumnViewportCaptureSuspendedUntil: Date = .distantPast
    var mainColumnViewportRestoreUntil: Date = .distantPast
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
    var pendingFocusModeEntryCaretHint: (cardID: UUID, location: Int)? = nil
    var focusResponderCardByObjectID: [ObjectIdentifier: UUID] = [:]
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
    @Published var pendingRestoreCardID: UUID? = nil
    @Published var suppressAutoScrollOnce: Bool = false
    @Published var suppressHorizontalAutoScroll: Bool = false
    @Published var maxLevelCount: Int = 0
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
        let measuringText = normalizedMeasurementText(text)
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

    private func normalizedMeasurementText(_ text: String) -> String {
        if text.isEmpty {
            return " "
        }
        if text.hasSuffix("\n") {
            return text + " "
        }
        return text
    }

    private func measurementCacheKey(
        text: String,
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        width: CGFloat,
        lineFragmentPadding: CGFloat,
        safetyInset: CGFloat
    ) -> NSString {
        let fingerprint = stableTextFingerprint(text)
        let fontBits = Double(fontSize).bitPattern
        let spacingBits = Double(lineSpacing).bitPattern
        let widthBits = Double(width).bitPattern
        let paddingBits = Double(lineFragmentPadding).bitPattern
        let insetBits = Double(safetyInset).bitPattern
        let key = "\(fontBits)|\(spacingBits)|\(widthBits)|\(paddingBits)|\(insetBits)|\(text.utf16.count)|\(fingerprint)"
        return key as NSString
    }

    private func stableTextFingerprint(_ text: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
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
}

@MainActor
final class MainColumnScrollRegistry {
    static let shared = MainColumnScrollRegistry()

    private final class Entry {
        weak var scrollView: NSScrollView?

        init(scrollView: NSScrollView) {
            self.scrollView = scrollView
        }
    }

    private var entriesByKey: [String: Entry] = [:]

    private init() {}

    func register(scrollView: NSScrollView, for key: String) {
        entriesByKey[key] = Entry(scrollView: scrollView)
        pruneReleasedEntries()
    }

    func unregister(key: String, matching scrollView: NSScrollView? = nil) {
        guard let entry = entriesByKey[key] else { return }
        if let scrollView {
            guard entry.scrollView === scrollView else { return }
        }
        entriesByKey.removeValue(forKey: key)
    }

    func scrollView(for key: String) -> NSScrollView? {
        if let scrollView = entriesByKey[key]?.scrollView {
            return scrollView
        }
        entriesByKey.removeValue(forKey: key)
        return nil
    }

    private func pruneReleasedEntries() {
        entriesByKey = entriesByKey.filter { $0.value.scrollView != nil }
    }
}

struct MainColumnScrollViewAccessor: NSViewRepresentable {
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
            columnKey: columnKey,
            storedOffsetY: storedOffsetY,
            onOffsetChange: onOffsetChange
        )
    }

    final class Coordinator {
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
            columnKey: String,
            storedOffsetY: CGFloat?,
            onOffsetChange: @escaping (CGFloat) -> Void
        ) {
            guard let resolvedScrollView = resolveScrollView(from: view) else {
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view else { return }
                    self.attach(to: view, columnKey: columnKey, storedOffsetY: storedOffsetY, onOffsetChange: onOffsetChange)
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
                MainColumnScrollRegistry.shared.unregister(key: previousKey, matching: resolvedScrollView)
            }
            attachedColumnKey = columnKey
            MainColumnScrollRegistry.shared.register(scrollView: resolvedScrollView, for: columnKey)
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
                MainColumnScrollRegistry.shared.unregister(key: attachedColumnKey, matching: scrollView)
            }
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            observer = nil
            scrollView = nil
            attachedColumnKey = nil
            lastReportedOffsetY = .nan
            offsetChangeHandler = nil
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

    struct FocusModeSearchMatch: Equatable {
        let cardID: UUID
        let range: NSRange
    }

    struct MainColumnFocusRequest: Equatable {
        let targetID: UUID
        let prefersTopAnchor: Bool
        let cardsCount: Int
        let firstCardID: UUID?
        let lastCardID: UUID?
        let viewportHeightBucket: Int
    }

    struct UpperCardCreationRequest: Identifiable {
        let id = UUID()
        let contextCardID: UUID
        let sourceCardIDs: [UUID]
    }

    @EnvironmentObject var store: FileStore
    @EnvironmentObject var referenceCardStore: ReferenceCardStore
    let scenario: Scenario
    let showWorkspaceTopToolbar: Bool
    let splitModeEnabled: Bool
    let splitPaneID: Int
    @State var isSplitPaneActive: Bool
    @State private var interactionRuntime = WriterInteractionRuntime()
    @StateObject private var mainCanvasViewState = MainCanvasViewState()
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
    @AppStorage("focusModeLineSpacingValueTemp") var focusModeLineSpacingValue: Double = 4.5
    @AppStorage("mainCardLineSpacingValueV2") var mainCardLineSpacingValue: Double = 5.0
    @AppStorage("mainCardVerticalGap") var mainCardVerticalGap: Double = 0.0
    @AppStorage("mainWorkspaceZoomScale") var mainWorkspaceZoomScale: Double = 1.0
    @AppStorage("geminiModelID") var geminiModelID: String = "gemini-3.1-pro-preview"
    @AppStorage("focusModeWindowBackgroundActive") var focusModeWindowBackgroundActive: Bool = false
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
    @State var showFocusModeSearchPopup: Bool = false
    @State var focusModeSearchText: String = ""
    @State var focusModeSearchMatches: [FocusModeSearchMatch] = []
    @State var focusModeSearchSelectedMatchIndex: Int = -1
    @State var focusModeSearchHighlightRequestID: Int = 0
    @State var focusModeSearchPersistentHighlight: FocusModeSearchMatch? = nil
    @State var focusModeSearchHighlightTextViewBox = WeakTextViewBox()
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

    var pendingMainCanvasRestoreCardID: UUID? {
        get { mainCanvasViewState.pendingRestoreCardID }
        nonmutating set { mainCanvasViewState.pendingRestoreCardID = newValue }
    }

    var suppressAutoScrollOnce: Bool {
        get { mainCanvasViewState.suppressAutoScrollOnce }
        nonmutating set { mainCanvasViewState.suppressAutoScrollOnce = newValue }
    }

    var suppressHorizontalAutoScroll: Bool {
        get { mainCanvasViewState.suppressHorizontalAutoScroll }
        nonmutating set { mainCanvasViewState.suppressHorizontalAutoScroll = newValue }
    }

    var maxLevelCount: Int {
        get { mainCanvasViewState.maxLevelCount }
        nonmutating set { mainCanvasViewState.maxLevelCount = newValue }
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

    var mainColumnLayoutSnapshotByKey: [MainColumnLayoutCacheKey: MainColumnLayoutSnapshot] {
        get { interactionRuntime.mainColumnLayoutSnapshotByKey }
        nonmutating set { interactionRuntime.mainColumnLayoutSnapshotByKey = newValue }
    }

    var mainColumnViewportCaptureSuspendedUntil: Date {
        get { interactionRuntime.mainColumnViewportCaptureSuspendedUntil }
        nonmutating set { interactionRuntime.mainColumnViewportCaptureSuspendedUntil = newValue }
    }

    var mainColumnViewportRestoreUntil: Date {
        get { interactionRuntime.mainColumnViewportRestoreUntil }
        nonmutating set { interactionRuntime.mainColumnViewportRestoreUntil = newValue }
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

    var pendingFocusModeEntryCaretHint: (cardID: UUID, location: Int)? {
        get { interactionRuntime.pendingFocusModeEntryCaretHint }
        nonmutating set { interactionRuntime.pendingFocusModeEntryCaretHint = newValue }
    }

    var focusResponderCardByObjectID: [ObjectIdentifier: UUID] {
        get { interactionRuntime.focusResponderCardByObjectID }
        nonmutating set { interactionRuntime.focusResponderCardByObjectID = newValue }
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

    struct LevelData {
        let cards: [SceneCard]
        let parent: SceneCard?
    }

    struct DisplayedMainLevelsCacheKey: Equatable {
        let cardsVersion: Int
        let activeCategory: String?
        let isActiveCardRoot: Bool
    }

    struct MainColumnLayoutFrame: Equatable {
        let minY: CGFloat
        let maxY: CGFloat

        var height: CGFloat { maxY - minY }
    }

    struct MainColumnLayoutCacheKey: Hashable {
        let recordsVersion: Int
        let contentVersion: Int
        let viewportHeightBucket: Int
        let fontSizeBucket: Int
        let lineSpacingBucket: Int
        let cardIDs: [UUID]
    }

    struct MainColumnLayoutSnapshot {
        let key: MainColumnLayoutCacheKey
        let framesByCardID: [UUID: MainColumnLayoutFrame]
        let orderedCardIDs: [UUID]
        let contentBottomY: CGFloat
    }

    struct MainCanvasRenderState: Equatable {
        let size: CGSize
        let availableWidth: CGFloat
        let historyIndex: Int
        let activeCardID: UUID?
        let acceptsKeyboardInput: Bool
        let isPreviewingHistory: Bool
        let backgroundSignature: String
        let contentFingerprint: Int
    }

    struct MainCanvasHost: View, Equatable {
        let renderState: MainCanvasRenderState
        @ObservedObject var viewState: MainCanvasViewState
        let backgroundColor: Color
        let onBackgroundTap: () -> Void
        let onHistoryIndexChange: (ScrollViewProxy) -> Void
        let onActiveCardChange: (UUID?, ScrollViewProxy, CGFloat) -> Void
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
                    .onChange(of: renderState.historyIndex) { _, _ in
                        onHistoryIndexChange(proxy)
                    }
                    .onChange(of: renderState.activeCardID) { _, newID in
                        onActiveCardChange(newID, proxy, renderState.availableWidth)
                    }
                    .onChange(of: viewState.pendingRestoreCardID) { _, _ in
                        onRestoreRequest(proxy, renderState.availableWidth)
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
            .onChange(of: isSplitPaneActive) { _, _ in
                syncScenarioTimestampSuppressionIfNeeded()
            }
            .onChange(of: scenario.id) { _, _ in
                syncScenarioObservedState()
            }
            .onChange(of: scenarioCardsVersion) { _, _ in
                handleScenarioCardsVersionChange()
            }
            .onChange(of: scenarioHistoryVersion) { _, _ in
                handleScenarioHistoryVersionChange()
            }
            .onChange(of: scenarioLinkedCardsVersion) { _, _ in
                handleScenarioLinkedCardsVersionChange()
            }
            .onDisappear {
                handleWorkspaceDisappear()
            }
            .onChange(of: showFocusMode) { _, isOn in
                handleShowFocusModeChange(isOn)
            }
            .onChange(of: mainWorkspaceZoomScale) { oldValue, newValue in
                guard abs(newValue - oldValue) > 0.0001 else { return }
                requestMainCanvasRestoreForZoomChange()
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
        syncScenarioObservedState()
        restoreStartupViewportIfNeeded()
        if activeCardID == nil, let startupCard = startupActiveCard() { changeActiveCard(to: startupCard) }
        restoreStartupFocusIfNeeded()
        requestStartupMainCanvasRestoreIfNeeded()
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
        pruneAICandidateTracking()
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

    func syncScenarioObservedState() {
        scenarioObservedState.bind(to: scenario)
    }

    func handleWorkspaceDisappear() {
        persistCurrentFocusSnapshotIfPossible()
        persistCurrentViewportSnapshotIfPossible()
        releaseScenarioTimestampSuppressionIfNeeded()
        cancelInactivePaneSnapshotRefresh()
        cancelAIChatRequest()
        flushAIThreadsPersistence()
        flushAIEmbeddingPersistence()
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
        mainColumnLastFocusRequestByKey = [:]
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
            stopMainNavKeyMonitor()
            stopMainCaretMonitor()
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
                if focusModeEditorCardID == editingID {
                    return
                }
                if let card = findCard(by: editingID) {
                    beginFocusModeEditing(card, cursorToEnd: false)
                } else {
                    focusModeEditorCardID = editingID
                }
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
            requestMainCanvasRestoreForFocusExit()
            if let activeID = activeCardID {
                persistLastFocusSnapshot(cardID: activeID, isEditing: false, inFocusMode: false)
            }
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
                if showFocusMode {
                    focusModeCanvas(size: size)
                        .ignoresSafeArea(.container, edges: .top)
                        .transition(.opacity)
                        .zIndex(10)
                } else {
                    mainCanvasWithOptionalZoom(size: size, availableWidth: availableWidth)
                    if showWorkspaceTopToolbar {
                        workspaceTopToolbarHost
                    }
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
            activeCardID: activeCardID,
            acceptsKeyboardInput: acceptsKeyboardInput,
            isPreviewingHistory: isPreviewingHistory,
            backgroundSignature: "\(appearance)|\(backgroundColorHex)|\(darkBackgroundColorHex)",
            contentFingerprint: mainCanvasContentFingerprint()
        )
    }

    func mainCanvasContentFingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(scenarioCardsVersion)
        hasher.combine(scenarioLinkedCardsVersion)
        hasher.combine(activeCardID)
        hasher.combine(editingCardID)
        hasher.combine(selectedCardIDs.count)
        for id in selectedCardIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            hasher.combine(id)
        }
        hasher.combine(activeRelationFingerprint)
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
        if suppressHorizontalAutoScroll { return }
        if suppressAutoScrollOnce {
            suppressAutoScrollOnce = false
            return
        }
        if !isPreviewingHistory {
            scrollToColumnIfNeeded(
                targetCardID: id,
                proxy: hProxy,
                availableWidth: availableWidth,
                animated: !shouldSuppressMainArrowRepeatAnimation()
            )
        }
    }

    func handleMainCanvasRestoreRequest(hProxy: ScrollViewProxy, availableWidth: CGFloat) {
        guard !showFocusMode else { return }
        guard acceptsKeyboardInput else { return }
        restoreMainCanvasPositionIfNeeded(proxy: hProxy, availableWidth: availableWidth)
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

    private func restoreStartupViewportIfNeeded() {
        guard !didRestoreStartupViewportState else { return }
        didRestoreStartupViewportState = true

        let restoredOffsets = restoredStartupViewportOffsets()
        guard !restoredOffsets.isEmpty else { return }

        mainColumnViewportOffsetByKey = restoredOffsets
        let restoreDelays: [TimeInterval] = [0.0, 0.05, 0.18]
        for delay in restoreDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                applyStoredMainColumnViewportOffsets(restoredOffsets)
            }
        }
    }

    private func applyStoredMainColumnViewportOffsets(_ offsets: [String: CGFloat]) {
        guard !offsets.isEmpty else { return }

        var didScheduleCaptureSuspension = false
        for (viewportKey, storedOffsetY) in offsets.sorted(by: { $0.key < $1.key }) {
            guard storedOffsetY > 1 else { continue }
            guard let scrollView = MainColumnScrollRegistry.shared.scrollView(for: viewportKey) else { continue }

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
        pendingMainCanvasRestoreCardID = nil
        DispatchQueue.main.async {
            guard !showFocusMode else { return }
            pendingMainCanvasRestoreCardID = targetID
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

        guard !sanitizedOffsets.isEmpty,
              let data = try? JSONEncoder().encode(sanitizedOffsets),
              let encoded = String(data: data, encoding: .utf8) else {
            lastFocusedViewportScenarioID = ""
            lastFocusedViewportOffsetsJSON = ""
            return
        }

        lastFocusedViewportScenarioID = scenario.id.uuidString
        lastFocusedViewportOffsetsJSON = encoded
    }

    private func persistLastEditedCard(_ cardID: UUID) {
        guard let card = findCard(by: cardID), !card.isArchived else { return }
        lastEditedScenarioID = scenario.id.uuidString
        lastEditedCardID = cardID.uuidString
    }
}
```

--------------------------------
File: WriterAI+ChatView.swift
--------------------------------
```swift
import SwiftUI

extension ScenarioWriterView {
    func handleAIChatInputKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard press.phase == .down else { return .ignored }
        let hasModifier =
            press.modifiers.contains(.command) ||
            press.modifiers.contains(.option) ||
            press.modifiers.contains(.control)
        if press.key == .return && !hasModifier && !press.modifiers.contains(.shift) {
            sendAIChatMessage()
            return .handled
        }
        return .ignored
    }

    func latestAIReplyText(for threadID: UUID?) -> String? {
        guard let threadID else { return nil }
        let text = messagesForAIThread(threadID)
            .reversed()
            .first(where: { $0.role == "model" })?
            .text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    func applyLatestAIReplyToActiveCard() {
        guard let reply = latestAIReplyText(for: activeAIChatThreadID) else {
            setAIStatusError("적용할 AI 답변이 없습니다.")
            return
        }
        guard let activeID = activeCardID,
              let activeCard = findCard(by: activeID) else {
            setAIStatusError("먼저 반영할 카드를 선택해 주세요.")
            return
        }

        finishEditing()
        let prevState = captureScenarioState()
        if activeCard.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            activeCard.content = reply
        } else {
            activeCard.content += "\n\n\(reply)"
        }
        scenario.bumpCardsVersion()
        commitCardMutation(
            previousState: prevState,
            actionName: "AI 상담 반영",
            forceSnapshot: true
        )
        selectedCardIDs = [activeCard.id]
        changeActiveCard(to: activeCard, shouldFocusMain: false)
        setAIStatus("AI 답변을 현재 선택 카드 하단에 반영했습니다.")
    }

    func addLatestAIReplyAsChildCard() {
        guard let reply = latestAIReplyText(for: activeAIChatThreadID) else {
            setAIStatusError("자식 카드로 만들 AI 답변이 없습니다.")
            return
        }
        guard let activeID = activeCardID,
              let parentCard = findCard(by: activeID) else {
            setAIStatusError("먼저 부모 카드를 선택해 주세요.")
            return
        }

        finishEditing()
        let prevState = captureScenarioState()
        let child = SceneCard(
            content: reply,
            orderIndex: parentCard.children.count,
            parent: parentCard,
            scenario: scenario,
            category: parentCard.category
        )
        scenario.cards.append(child)
        scenario.bumpCardsVersion()
        commitCardMutation(
            previousState: prevState,
            actionName: "AI 상담 자식 카드 추가",
            forceSnapshot: true
        )
        selectedCardIDs = [child.id]
        changeActiveCard(to: child, shouldFocusMain: false)
        setAIStatus("AI 답변을 자식 카드로 추가했습니다.")
    }

    func prepareAlternativeRequest() {
        guard let threadID = activeAIChatThreadID else { return }
        let latestUserQuestion = messagesForAIThread(threadID)
            .reversed()
            .first(where: { $0.role == "user" })?
            .text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let latestUserQuestion, !latestUserQuestion.isEmpty else {
            aiChatInput = "지금 맥락에서 대안 3가지를 제시해줘. 서로 다른 방향으로 짧게."
            isAIChatInputFocused = true
            return
        }
        aiChatInput = "방금 질문에 대한 대안 3가지를 서로 다른 방향으로 제시해줘.\n원 질문: \(latestUserQuestion)"
        isAIChatInputFocused = true
    }

    @ViewBuilder
    var aiChatView: some View {
        let activeMessages = activeAIChatMessages()
        let hasLatestReply = latestAIReplyText(for: activeAIChatThreadID) != nil
        let activeThreadTokenUsage = tokenUsageForAIThread(activeAIChatThreadID)
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Text("AI 시나리오 상담")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(appearance == "light" ? .black.opacity(0.7) : .white.opacity(0.8))
                    Spacer()
                    Button {
                        createAIChatThread()
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("새 상담 스레드")

                    Button {
                        guard let threadID = activeAIChatThreadID else { return }
                        deleteAIChatThread(threadID)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("현재 상담 스레드 삭제")

                    Button {
                        toggleAIChat()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 6)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(aiChatThreads) { thread in
                            let isActive = thread.id == activeAIChatThreadID
                            Button {
                                selectAIChatThread(thread.id)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(thread.mode.rawValue)
                                        .font(.system(size: 10, weight: .bold))
                                    Text(thread.title)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("\(thread.messages.count)")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background((isActive ? Color.white : Color.secondary.opacity(0.16)))
                                        .foregroundColor(isActive ? .accentColor : .secondary)
                                        .cornerRadius(10)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    isActive
                                        ? Color.accentColor.opacity(0.88)
                                        : (appearance == "light" ? Color.black.opacity(0.05) : Color.white.opacity(0.10))
                                )
                                .foregroundColor(isActive ? .white : .primary)
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 1)
                }

                if let activeThread = aiChatThreads.first(where: { $0.id == activeAIChatThreadID }) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(visibleAIChatScopes, id: \.self) { scope in
                                let isActiveScope = activeThread.scope.type.normalizedForCurrentUI == scope
                                Button {
                                    applyScopeToActiveThread(scope)
                                } label: {
                                    Text(scope.rawValue)
                                        .font(.system(size: 11, weight: .semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            isActiveScope
                                                ? Color.accentColor.opacity(0.86)
                                                : (appearance == "light" ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                                        )
                                        .foregroundColor(isActiveScope ? .white : .primary)
                                        .cornerRadius(9)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            Divider().background(appearance == "light" ? Color.black.opacity(0.1) : Color.white.opacity(0.15))
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 20) {
                        if activeMessages.isEmpty {
                            VStack(spacing: 14) {
                                Image(systemName: "sparkles.tv")
                                    .font(.system(size: 40))
                                    .foregroundColor(.accentColor.opacity(0.6))
                                Text("AI에게 현재 시나리오에 대해 물어보세요.")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                                if let thread = aiChatThreads.first(where: { $0.id == activeAIChatThreadID }) {
                                    Text("스레드 범위: \(thread.scope.type.rawValue)")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary.opacity(0.8))
                                }
                                Text("예: 이 이야기의 결말을 어떻게 내면 좋을까?")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary.opacity(0.8))
                            }
                            .padding(.top, 70)
                        } else {
                            ForEach(activeMessages) { msg in
                                HStack {
                                    if msg.role == "user" {
                                        Spacer(minLength: 50)
                                        Text(msg.text)
                                            .font(.system(size: 15))
                                            .padding(14)
                                            .background(Color.accentColor.opacity(0.85))
                                            .foregroundColor(.white)
                                            .cornerRadius(14)
                                            .textSelection(.enabled)
                                    } else {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text("AI")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.secondary)
                                            Text(msg.text)
                                                .font(.system(size: 15))
                                                .lineSpacing(3)
                                                .padding(14)
                                                .background(appearance == "light" ? Color.black.opacity(0.05) : Color.white.opacity(0.08))
                                                .cornerRadius(14)
                                                .textSelection(.enabled)
                                        }
                                        Spacer(minLength: 50)
                                    }
                                }
                                .id(msg.id)
                            }
                            
                            if isAIChatLoading {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("AI")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.secondary)
                                        ProgressView()
                                            .controlSize(.regular)
                                            .padding(14)
                                            .background(appearance == "light" ? Color.black.opacity(0.05) : Color.white.opacity(0.08))
                                            .cornerRadius(14)
                                    }
                                    Spacer()
                                }
                                .id("loading")
                            }
                        }
                    }
                    .padding(18)
                }
                .onChange(of: activeMessages.count) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation {
                            proxy.scrollTo(activeMessages.last?.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: activeAIChatThreadID) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation {
                            proxy.scrollTo(activeAIChatMessages().last?.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: isAIChatLoading) { _, isLoading in
                    if isLoading {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation {
                                proxy.scrollTo("loading", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            
            Divider().background(appearance == "light" ? Color.black.opacity(0.1) : Color.white.opacity(0.15))
            
            VStack(spacing: 10) {
                if let message = aiStatusMessage, aiStatusIsError {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("누적 토큰(현재 스레드): 입력 \(activeThreadTokenUsage.promptTokens) / 출력 \(activeThreadTokenUsage.outputTokens) / 총 \(activeThreadTokenUsage.totalTokens)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let context = aiLastContextPreview {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("이번 요청 컨텍스트")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text("범위: \(context.scopeLabel)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("선택 맥락: \(context.scopedContext)")
                            .font(.system(size: 11))
                            .lineLimit(3)
                            .foregroundStyle(.secondary)
                        Text("RAG 연관: \(context.ragContext)")
                            .font(.system(size: 11))
                            .lineLimit(3)
                            .foregroundStyle(.secondary)
                        Text("롤링 요약: \(context.rollingSummary)")
                            .font(.system(size: 11))
                            .lineLimit(3)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(appearance == "light" ? Color.black.opacity(0.035) : Color.white.opacity(0.06))
                    .cornerRadius(8)
                }

                if hasLatestReply {
                    HStack(spacing: 8) {
                        Button("선택 카드에 반영") {
                            applyLatestAIReplyToActiveCard()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(activeCardID == nil)

                        Button("자식 카드로 추가") {
                            addLatestAIReplyAsChildCard()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(activeCardID == nil)

                        Button("대안 3개 요청") {
                            prepareAlternativeRequest()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                HStack(alignment: .bottom, spacing: 10) {
                    if #available(macOS 13.0, *) {
                        TextField("AI에게 질문하기...", text: aiChatInputBinding, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .lineLimit(1...6)
                            .padding(12)
                            .background(appearance == "light" ? Color.black.opacity(0.03) : Color.white.opacity(0.05))
                            .cornerRadius(10)
                            .focused($isAIChatInputFocused)
                            .onKeyPress(phases: [.down]) { press in
                                handleAIChatInputKeyPress(press)
                            }
                            .onSubmit {
                                sendAIChatMessage()
                            }
                    } else {
                        TextField("AI에게 질문하기...", text: aiChatInputBinding)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .padding(12)
                            .background(appearance == "light" ? Color.black.opacity(0.03) : Color.white.opacity(0.05))
                            .cornerRadius(10)
                            .focused($isAIChatInputFocused)
                            .onKeyPress(phases: [.down]) { press in
                                handleAIChatInputKeyPress(press)
                            }
                            .onSubmit {
                                sendAIChatMessage()
                            }
                    }
                        
                    if isAIChatLoading {
                        Button(action: {
                            cancelAIChatRequest(showMessage: true)
                        }) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 7)
                        .help("현재 AI 요청 중단")
                    }

                    Button(action: {
                        sendAIChatMessage()
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(aiChatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAIChatLoading ? .secondary.opacity(0.5) : .accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(aiChatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAIChatLoading)
                    .padding(.bottom, 5)
                }
            }
            .padding(14)
            .background(appearance == "light" ? Color.white : Color(white: 0.12))
        }
        .onAppear {
            loadPersistedAIThreadsIfNeeded()
            loadPersistedAIEmbeddingIndexIfNeeded()
            isMainViewFocused = false
            isAIChatInputFocused = true
            syncActiveThreadSelectedScopeWithCurrentSelection()
        }
        .onChange(of: scenario.id) { _, _ in
            handleAIChatScenarioChange()
        }
        .onChange(of: selectedCardIDs) { _, _ in
            syncActiveThreadSelectedScopeWithCurrentSelection()
        }
        .onChange(of: activeCardID) { _, _ in
            syncActiveThreadSelectedScopeWithCurrentSelection()
        }
        .onDisappear {
            flushAIThreadsPersistence()
            flushAIEmbeddingPersistence()
            cancelAIChatRequest()
        }
    }

    func sendAIChatMessage() {
        ensureAIChatThreadSelection()
        guard let threadID = activeAIChatThreadID else { return }

        let text = aiChatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isAIChatLoading else { return }
        
        aiChatInput = ""
        appendAIChatMessage(AIChatMessage(role: "user", text: text), to: threadID)
        
        requestAIChatResponse(for: threadID)
    }
}
```
