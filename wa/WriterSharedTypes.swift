import SwiftUI
import AppKit

let focusModeBodySafetyInset: CGFloat = 8

enum ScenarioCardCategory {
    static let plot = "플롯"
    static let note = "노트"
    static let uncategorized = "미분류"
}

enum FocusModeLayoutMetrics {
    static let focusModeContentPadding: CGFloat = 143
    static let focusModeLineFragmentPadding: CGFloat = 5
    static var focusModeHorizontalPadding: CGFloat {
        max(0, focusModeContentPadding - focusModeLineFragmentPadding)
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
        let clampedY = min(max(minY, targetY), maxY)
        let resolvedTargetY = snapToPixel ? round(clampedY) : clampedY
        guard abs(resolvedTargetY - visibleRect.origin.y) > deadZone else { return false }

        scrollView.contentView.setBoundsOrigin(NSPoint(x: visibleRect.origin.x, y: resolvedTargetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        return true
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

struct FocusModeCardWidthPreferenceKey: PreferenceKey {
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

struct MainCardHeightPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct MainCardWidthPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct HistoryBarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct WorkspaceRootSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
