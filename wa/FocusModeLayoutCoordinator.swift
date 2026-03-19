import SwiftUI
import AppKit
import Combine

@MainActor
final class FocusModeLayoutCoordinator: ObservableObject {
    struct CardHeightKey: Hashable {
        let cardID: UUID
        let contentFingerprint: UInt64
        let textLength: Int
        let widthBucket: Int
        let fontSizeBucket: Int
        let lineSpacingBucket: Int
    }

    struct LiveEditorLayoutRecord: Equatable {
        let bodyHeight: CGFloat
        let rawContentFingerprint: UInt64
        let rawTextLength: Int
        let widthBucket: Int
        let fontSizeBucket: Int
        let lineSpacingBucket: Int
        let committedGeneration: Int
    }

    private var cardHeightByKey: [CardHeightKey: CGFloat] = [:]
    @Published private var liveEditorLayoutByCardID: [UUID: LiveEditorLayoutRecord] = [:]
    private var liveEditorPendingGenerationByCardID: [UUID: Int] = [:]

    func reset() {
        cardHeightByKey.removeAll(keepingCapacity: false)
        liveEditorLayoutByCardID.removeAll(keepingCapacity: false)
        liveEditorPendingGenerationByCardID.removeAll(keepingCapacity: false)
    }

    func resolvedCardHeight(
        for card: SceneCard,
        cardWidth: CGFloat,
        fontSize: Double,
        lineSpacing: Double,
        verticalInset: CGFloat,
        liveEditorCardID: UUID? = nil
    ) -> CGFloat {
        if liveEditorCardID == card.id,
           let liveBodyHeight = resolvedLiveEditorBodyHeight(
               for: card,
               cardWidth: cardWidth,
               fontSize: fontSize,
               lineSpacing: lineSpacing
           ) {
            return ceil(liveBodyHeight + (verticalInset * 2))
        }

        let key = resolvedCardHeightKey(
            for: card,
            cardWidth: cardWidth,
            fontSize: fontSize,
            lineSpacing: lineSpacing
        )
        if let cached = cardHeightByKey[key] {
            return cached
        }

        let measuredText = normalizedSharedMeasurementText(card.content)
        let bodyHeight = sharedMeasuredTextBodyHeight(
            text: measuredText,
            fontSize: CGFloat(fontSize * 1.2),
            lineSpacing: CGFloat(lineSpacing),
            width: FocusModeLayoutMetrics.resolvedTextWidth(for: cardWidth),
            lineFragmentPadding: FocusModeLayoutMetrics.focusModeLineFragmentPadding,
            safetyInset: focusModeBodySafetyInset
        )
        let resolved = ceil(bodyHeight + (verticalInset * 2))
        if cardHeightByKey.count >= 2048 {
            cardHeightByKey.removeAll(keepingCapacity: true)
        }
        cardHeightByKey[key] = resolved
        return resolved
    }

    func resolvedClickCaretLocation(
        for card: SceneCard,
        localPoint: CGPoint,
        cardWidth: CGFloat,
        fontSize: Double,
        lineSpacing: Double,
        horizontalInset: CGFloat,
        verticalInset: CGFloat
    ) -> Int {
        let originalText = card.content
        let measuringText = normalizedSharedMeasurementText(originalText)
        let textLength = (originalText as NSString).length
        guard !measuringText.isEmpty else { return 0 }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CGFloat(lineSpacing)
        paragraphStyle.lineBreakMode = .byWordWrapping

        let font = NSFont(name: "SansMonoCJKFinalDraft", size: CGFloat(fontSize * 1.2))
            ?? NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize * 1.2), weight: .regular)

        let storage = NSTextStorage(
            string: measuringText,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
        )
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: CGSize(
                width: FocusModeLayoutMetrics.resolvedTextWidth(for: cardWidth),
                height: .greatestFiniteMagnitude
            )
        )
        textContainer.lineFragmentPadding = FocusModeLayoutMetrics.focusModeLineFragmentPadding
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
        if containerPoint.y >= usedRect.maxY + focusModeBodySafetyInset {
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

    func beginLiveEditorMutation(for cardID: UUID) {
        let currentCommittedGeneration = liveEditorLayoutByCardID[cardID]?.committedGeneration ?? 0
        let currentPendingGeneration = liveEditorPendingGenerationByCardID[cardID] ?? currentCommittedGeneration
        liveEditorPendingGenerationByCardID[cardID] = max(currentCommittedGeneration, currentPendingGeneration) + 1
    }

    func reportLiveEditorLayout(
        for cardID: UUID,
        rawText: String,
        bodyHeight: CGFloat,
        textWidth: CGFloat,
        fontSize: Double,
        lineSpacing: Double
    ) {
        let safeBodyHeight = max(1, ceil(bodyHeight))
        let currentCommittedGeneration = liveEditorLayoutByCardID[cardID]?.committedGeneration ?? 0
        let pendingGeneration = liveEditorPendingGenerationByCardID[cardID] ?? currentCommittedGeneration
        let committedGeneration = max(currentCommittedGeneration, pendingGeneration)
        liveEditorPendingGenerationByCardID[cardID] = committedGeneration

        let newRecord = LiveEditorLayoutRecord(
            bodyHeight: safeBodyHeight,
            rawContentFingerprint: sharedStableTextFingerprint(rawText),
            rawTextLength: rawText.utf16.count,
            widthBucket: Int((textWidth * 10).rounded()),
            fontSizeBucket: Int((fontSize * 10).rounded()),
            lineSpacingBucket: Int((lineSpacing * 10).rounded()),
            committedGeneration: committedGeneration
        )

        if liveEditorLayoutByCardID[cardID] != newRecord {
            liveEditorLayoutByCardID[cardID] = newRecord
        }
    }

    func hasPendingLiveEditorLayoutCommit(for cardID: UUID) -> Bool {
        let pendingGeneration = liveEditorPendingGenerationByCardID[cardID] ?? 0
        let committedGeneration = liveEditorLayoutByCardID[cardID]?.committedGeneration ?? 0
        return pendingGeneration > committedGeneration
    }

    private func resolvedCardHeightKey(
        for card: SceneCard,
        cardWidth: CGFloat,
        fontSize: Double,
        lineSpacing: Double
    ) -> CardHeightKey {
        let normalizedText = normalizedSharedMeasurementText(card.content)
        return CardHeightKey(
            cardID: card.id,
            contentFingerprint: sharedStableTextFingerprint(normalizedText),
            textLength: normalizedText.utf16.count,
            widthBucket: Int((cardWidth * 10).rounded()),
            fontSizeBucket: Int((fontSize * 10).rounded()),
            lineSpacingBucket: Int((lineSpacing * 10).rounded())
        )
    }

    private func resolvedLiveEditorBodyHeight(
        for card: SceneCard,
        cardWidth: CGFloat,
        fontSize: Double,
        lineSpacing: Double
    ) -> CGFloat? {
        guard let record = liveEditorLayoutByCardID[card.id] else { return nil }
        let rawText = card.content
        guard record.rawContentFingerprint == sharedStableTextFingerprint(rawText) else { return nil }
        guard record.rawTextLength == rawText.utf16.count else { return nil }
        let targetTextWidth = FocusModeLayoutMetrics.resolvedTextWidth(for: cardWidth)
        guard record.widthBucket == Int((targetTextWidth * 10).rounded()) else { return nil }
        let targetFontSize = CGFloat(fontSize * 1.2)
        guard record.fontSizeBucket == Int((targetFontSize * 10).rounded()) else { return nil }
        guard record.lineSpacingBucket == Int((lineSpacing * 10).rounded()) else { return nil }
        return record.bodyHeight
    }
}
