import Foundation

enum IndexBoardSummarySourceType: String, Codable, Sendable {
    case digest
    case ai
    case manual

    var labelText: String {
        switch self {
        case .digest:
            return "Digest"
        case .ai:
            return "AI"
        case .manual:
            return "수동"
        }
    }
}

struct IndexBoardCardSummaryRecord: Codable, Equatable, Identifiable, Sendable {
    let cardID: UUID
    var summaryText: String
    var sourceContentHash: UInt64
    var updatedAt: Date
    var sourceType: IndexBoardSummarySourceType
    var isStale: Bool

    var id: UUID { cardID }
}

struct IndexBoardResolvedSummary: Equatable {
    let cardID: UUID
    let summaryText: String
    let sourceType: IndexBoardSummarySourceType
    let updatedAt: Date?
    let isStale: Bool
    let usesFallback: Bool

    var hasSummary: Bool {
        !summaryText.isEmpty
    }

    var sourceLabelText: String {
        usesFallback ? "Digest Fallback" : sourceType.labelText
    }
}

func indexBoardNormalizedSummarySourceText(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
}

func indexBoardSummaryContentHash(for text: String) -> UInt64 {
    sharedStableTextFingerprint(indexBoardNormalizedSummarySourceText(text))
}

private func indexBoardNormalizedSummaryText(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func resolvedIndexBoardDigestSummary(
    for card: SceneCard,
    digestCache: [UUID: AICardDigest]
) -> (text: String, updatedAt: Date, isFresh: Bool)? {
    guard let digest = digestCache[card.id] else { return nil }
    let normalizedText = indexBoardNormalizedSummaryText(digest.shortSummary)
    guard !normalizedText.isEmpty else { return nil }
    let normalizedContent = indexBoardNormalizedSummarySourceText(card.content)
    return (
        text: normalizedText,
        updatedAt: digest.updatedAt,
        isFresh: digest.contentHash == normalizedContent.hashValue
    )
}

extension IndexBoardCardSummaryRecord {
    var normalizedSummaryText: String {
        indexBoardNormalizedSummaryText(summaryText)
    }

    var sanitizedForStorage: IndexBoardCardSummaryRecord? {
        let normalizedText = normalizedSummaryText
        guard !normalizedText.isEmpty else { return nil }
        var copy = self
        copy.summaryText = normalizedText
        return copy
    }
}

extension FileStore {
    @MainActor
    func indexBoardSummaryRecord(for cardID: UUID, scenarioID: UUID) -> IndexBoardCardSummaryRecord? {
        indexBoardSummaryRecordsByScenarioID[scenarioID]?[cardID]?.sanitizedForStorage
    }

    @MainActor
    func reconcileIndexBoardSummaryRecords(
        for cards: [SceneCard],
        digestCache: [UUID: AICardDigest],
        scenarioID: UUID
    ) {
        guard !cards.isEmpty else { return }

        var records = indexBoardSummaryRecordsByScenarioID[scenarioID] ?? [:]
        var changed = false

        for card in cards {
            let currentContentHash = indexBoardSummaryContentHash(for: card.content)
            let digestSummary = resolvedIndexBoardDigestSummary(for: card, digestCache: digestCache)

            if let sanitizedRecord = records[card.id]?.sanitizedForStorage {
                if sanitizedRecord.sourceType == .digest,
                   let digestSummary,
                   digestSummary.isFresh {
                    let refreshedRecord = IndexBoardCardSummaryRecord(
                        cardID: card.id,
                        summaryText: digestSummary.text,
                        sourceContentHash: currentContentHash,
                        updatedAt: digestSummary.updatedAt,
                        sourceType: .digest,
                        isStale: false
                    )
                    if refreshedRecord != sanitizedRecord {
                        records[card.id] = refreshedRecord
                        changed = true
                    }
                    continue
                }

                var updatedRecord = sanitizedRecord
                let shouldBeStale = sanitizedRecord.sourceContentHash != currentContentHash
                if updatedRecord.isStale != shouldBeStale {
                    updatedRecord.isStale = shouldBeStale
                    records[card.id] = updatedRecord
                    changed = true
                } else if records[card.id] != sanitizedRecord {
                    records[card.id] = sanitizedRecord
                    changed = true
                }
                continue
            }

            if records[card.id] != nil {
                records.removeValue(forKey: card.id)
                changed = true
            }

            if let digestSummary,
               digestSummary.isFresh {
                records[card.id] = IndexBoardCardSummaryRecord(
                    cardID: card.id,
                    summaryText: digestSummary.text,
                    sourceContentHash: currentContentHash,
                    updatedAt: digestSummary.updatedAt,
                    sourceType: .digest,
                    isStale: false
                )
                changed = true
            }
        }

        guard changed else { return }
        replaceIndexBoardSummaryRecords(records, for: scenarioID)
        saveAll()
    }
}

extension ScenarioWriterView {
    @MainActor
    func reconcileIndexBoardSummaries(for cardIDs: [UUID]) {
        let cards = cardIDs.compactMap(findCard(by:))
        guard !cards.isEmpty else { return }
        store.reconcileIndexBoardSummaryRecords(
            for: cards,
            digestCache: aiCardDigestCache,
            scenarioID: scenario.id
        )
    }

    @MainActor
    func resolvedIndexBoardSummary(for card: SceneCard) -> IndexBoardResolvedSummary? {
        let currentContentHash = indexBoardSummaryContentHash(for: card.content)

        if let storedRecord = store.indexBoardSummaryRecord(for: card.id, scenarioID: scenario.id) {
            return IndexBoardResolvedSummary(
                cardID: card.id,
                summaryText: storedRecord.normalizedSummaryText,
                sourceType: storedRecord.sourceType,
                updatedAt: storedRecord.updatedAt,
                isStale: storedRecord.isStale || storedRecord.sourceContentHash != currentContentHash,
                usesFallback: false
            )
        }

        if let digestSummary = resolvedIndexBoardDigestSummary(for: card, digestCache: aiCardDigestCache) {
            return IndexBoardResolvedSummary(
                cardID: card.id,
                summaryText: digestSummary.text,
                sourceType: .digest,
                updatedAt: digestSummary.updatedAt,
                isStale: !digestSummary.isFresh,
                usesFallback: true
            )
        }

        return nil
    }

    @MainActor
    func resolvedIndexBoardSummary(for cardID: UUID?) -> IndexBoardResolvedSummary? {
        guard let cardID, let card = findCard(by: cardID) else { return nil }
        return resolvedIndexBoardSummary(for: card)
    }
}
