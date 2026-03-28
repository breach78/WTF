import SwiftUI
import AppKit
import QuartzCore

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

func makeSharedRenderParagraphStyle(_ lineSpacing: CGFloat) -> NSMutableParagraphStyle {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = lineSpacing
    paragraphStyle.lineBreakMode = .byWordWrapping
    paragraphStyle.lineBreakStrategy = [.hangulWordPriority]
    paragraphStyle.lineHeightMultiple = 1.0
    paragraphStyle.paragraphSpacing = 0
    paragraphStyle.paragraphSpacingBefore = 0
    return paragraphStyle
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

        let paragraphStyle = makeSharedRenderParagraphStyle(lineSpacing)

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

    let paragraphStyle = makeSharedRenderParagraphStyle(lineSpacing)

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

struct MainColumnEditorSlotPreferenceKey: PreferenceKey {
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
