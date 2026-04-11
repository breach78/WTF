import Foundation
import CoreGraphics

nonisolated struct BWRMutationSummary: Equatable, Sendable {
    var changedCardIDs: Set<UUID> = []
    var removedCardIDs: Set<UUID> = []
    var metadataChanged: Bool = false

    var hasChanges: Bool {
        !changedCardIDs.isEmpty || !removedCardIDs.isEmpty || metadataChanged
    }

    mutating func merge(_ other: BWRMutationSummary) {
        changedCardIDs.formUnion(other.changedCardIDs)
        removedCardIDs.formUnion(other.removedCardIDs)
        metadataChanged = metadataChanged || other.metadataChanged
    }
}

nonisolated struct BWRCardSplitResult: Equatable, Sendable {
    var originalCardID: UUID
    var newCardID: UUID
    var summary: BWRMutationSummary
}

nonisolated struct BWRCloneRecursionGuard: Equatable, Sendable {
    var visitedCloneGroupIDs: Set<UUID> = []
}

nonisolated enum BWRSearchScope: String, CaseIterable, Sendable {
    case liveOnly
    case archiveOnly
    case everything
}

nonisolated struct BWRSearchHit: Identifiable, Equatable, Sendable {
    var id: String
    var entityID: UUID
    var entityKind: BWRArchiveEntityKind
    var title: String
    var snippet: String
    var isArchived: Bool
}

nonisolated enum BWRDocumentSearch {
    static func search(document: BWRDocument, query: String, scope: BWRSearchScope) -> [BWRSearchHit] {
        let loweredTerms = searchTokens(from: query)
        guard !loweredTerms.isEmpty else { return [] }

        var hits: [BWRSearchHit] = []
        if scope != .archiveOnly {
            hits.append(contentsOf: liveHits(document: document, terms: loweredTerms))
        }
        if scope != .liveOnly {
            hits.append(contentsOf: archiveHits(document: document, terms: loweredTerms))
        }
        return hits
    }

    private static func liveHits(document: BWRDocument, terms: [String]) -> [BWRSearchHit] {
        var hits: [BWRSearchHit] = []

        for card in BWRBoardOrderResolver.orderedLiveCards(document: document, includeParked: true) {
            let searchBlob = normalizedSearchText(card.layers
                .map(\.markdown)
                .joined(separator: "\n"))
            guard terms.allSatisfy(searchBlob.contains) else { continue }
            hits.append(
                BWRSearchHit(
                    id: "live-card-\(card.id.uuidString)",
                    entityID: card.id,
                    entityKind: .card,
                    title: card.titlePreview,
                    snippet: card.currentLayer?.markdown ?? "",
                    isArchived: false
                )
            )
        }

        let cardsByID = Dictionary(uniqueKeysWithValues: document.cards.map { ($0.id, $0) })
        for group in BWRBoardOrderResolver.orderedLiveGroups(document: document) {
            let memberTitles = group.memberCardIDs.compactMap { cardsByID[$0]?.titlePreview }.joined(separator: " ")
            let searchBlob = normalizedSearchText("\(group.name) \(memberTitles)")
            guard terms.allSatisfy(searchBlob.contains) else { continue }
            hits.append(
                BWRSearchHit(
                    id: "live-group-\(group.id.uuidString)",
                    entityID: group.id,
                    entityKind: .group,
                    title: group.name,
                    snippet: memberTitles,
                    isArchived: false
                )
            )
        }

        return hits
    }

    private static func archiveHits(document: BWRDocument, terms: [String]) -> [BWRSearchHit] {
        document.archive.compactMap { entry in
            let lowered = normalizedSearchText("\(entry.title) \(entry.searchBlob)")
            guard terms.allSatisfy(lowered.contains) else { return nil }
            return BWRSearchHit(
                id: "archive-\(entry.entityKind.rawValue)-\(entry.entityID.uuidString)",
                entityID: entry.entityID,
                entityKind: entry.entityKind,
                title: entry.title,
                snippet: entry.searchBlob,
                isArchived: true
            )
        }
    }

    private static func searchTokens(from text: String) -> [String] {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .map(normalizedSearchText)
            .filter { !$0.isEmpty }
    }

    private static func normalizedSearchText(_ text: String) -> String {
        text
            .lowercased()
            .filter { !$0.isWhitespace }
    }
}

nonisolated enum BWRDocumentReducer {
    static func createCard(
        document: inout BWRDocument,
        bodyMarkdown: String = "",
        colorHex: String? = "F8FAFC",
        layout: BWRPoint = BWRPoint(x: 720, y: 420)
    ) -> UUID {
        let now = Date()
        let layers = BWRCard.defaultLayers(bodyMarkdown: bodyMarkdown)
        let card = BWRCard(
            stableSortKey: document.allocateStableSortKey(),
            colorHex: colorHex,
            currentLayerID: layers[0].id,
            layout: layout,
            createdAt: now,
            updatedAt: now,
            layers: layers
        )
        document.cards.append(card)
        let stripID = BWRSlotPlacementNormalizer.ensureRecoveryStrip(document: &document)
        insert(cardIDs: [card.id], into: .strip(stripID), insertionIndex: Int.max, document: &document)
        document.updatedAt = now
        return card.id
    }

    static func createGroup(
        document: inout BWRDocument,
        name: String,
        memberCardIDs: [UUID]
    ) -> UUID? {
        let liveMemberIDs = deduplicatedCardIDs(memberCardIDs).filter { memberID in
            document.cards.contains(where: { $0.id == memberID && !$0.isArchived })
        }
        guard !liveMemberIDs.isEmpty else { return nil }

        let now = Date()
        let group = BWRGroup(
            name: name,
            originSlot: preferredGroupOrigin(document: document, memberCardIDs: liveMemberIDs),
            memberCardIDs: [],
            createdAt: now,
            updatedAt: now
        )
        document.groups.append(group)
        insert(cardIDs: liveMemberIDs, into: .group(group.id), insertionIndex: 0, document: &document)
        document.updatedAt = now
        return group.id
    }

    static func renameGroup(
        document: inout BWRDocument,
        groupID: UUID,
        newName: String
    ) -> BWRMutationSummary {
        guard let groupIndex = document.groups.firstIndex(where: { $0.id == groupID }) else { return .init() }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, document.groups[groupIndex].name != trimmed else { return .init() }

        document.groups[groupIndex].name = trimmed
        document.groups[groupIndex].updatedAt = Date()
        document.updatedAt = document.groups[groupIndex].updatedAt
        return BWRMutationSummary(metadataChanged: true)
    }

    static func addCards(
        document: inout BWRDocument,
        toGroup groupID: UUID,
        cardIDs: [UUID]
    ) -> BWRMutationSummary {
        attachCards(document: &document, toGroup: groupID, cardIDs: cardIDs, insertionIndex: nil)
    }

    static func removeCards(
        document: inout BWRDocument,
        fromGroup groupID: UUID,
        cardIDs: [UUID]
    ) -> BWRMutationSummary {
        detachCards(document: &document, fromGroup: groupID, cardIDs: cardIDs, preferredStripID: nil, insertionIndex: nil)
    }

    static func setCardLayouts(
        document: inout BWRDocument,
        layoutsByCardID: [UUID: BWRPoint]
    ) -> BWRMutationSummary {
        guard !layoutsByCardID.isEmpty else { return .init() }

        var summary = BWRMutationSummary(metadataChanged: true)
        let liveCardsByID = Dictionary(uniqueKeysWithValues: document.cards.filter { !$0.isArchived }.map { ($0.id, $0) })

        for group in document.groups where !group.isArchived {
            let movedIDs = group.memberCardIDs.filter { layoutsByCardID[$0] != nil }
            guard !movedIDs.isEmpty else { continue }

            let originColumn = group.originSlot?.column ?? 0
            let baseX = Double(originColumn) * 240.0
            let reordered = reorderedHostCardIDs(
                hostCardIDs: group.memberCardIDs,
                movedIDs: movedIDs,
                desiredPositionByID: Dictionary(uniqueKeysWithValues: movedIDs.map { cardID in
                    let desiredX = layoutsByCardID[cardID]?.x ?? baseX
                    return (cardID, (desiredX - baseX) / 240.0)
                }),
                cardsByID: liveCardsByID
            )

            if let groupIndex = document.groups.firstIndex(where: { $0.id == group.id }),
               document.groups[groupIndex].memberCardIDs != reordered {
                document.groups[groupIndex].memberCardIDs = reordered
                document.groups[groupIndex].updatedAt = Date()
                summary.changedCardIDs.formUnion(movedIDs)
            }
        }

        for strip in document.parkingStrips {
            let movedIDs = strip.cardIDs.filter { layoutsByCardID[$0] != nil }
            guard !movedIDs.isEmpty else { continue }

            let baseX = Double(strip.anchorColumn) * 240.0
            let reordered = reorderedHostCardIDs(
                hostCardIDs: strip.cardIDs,
                movedIDs: movedIDs,
                desiredPositionByID: Dictionary(uniqueKeysWithValues: movedIDs.map { cardID in
                    let desiredX = layoutsByCardID[cardID]?.x ?? baseX
                    return (cardID, (desiredX - baseX) / 240.0)
                }),
                cardsByID: liveCardsByID
            )

            if let stripIndex = document.parkingStrips.firstIndex(where: { $0.id == strip.id }),
               document.parkingStrips[stripIndex].cardIDs != reordered {
                document.parkingStrips[stripIndex].cardIDs = reordered
                summary.changedCardIDs.formUnion(movedIDs)
            }
        }

        guard summary.hasChanges else { return .init() }
        document.updatedAt = Date()
        return summary
    }

    static func attachCards(
        document: inout BWRDocument,
        toGroup groupID: UUID,
        cardIDs: [UUID],
        insertionIndex: Int?
    ) -> BWRMutationSummary {
        guard document.groups.contains(where: { $0.id == groupID && !$0.isArchived }) else {
            return .init()
        }

        let resolvedCardIDs = deduplicatedCardIDs(cardIDs).filter { cardID in
            document.cards.contains(where: { $0.id == cardID && !$0.isArchived })
        }
        guard !resolvedCardIDs.isEmpty else { return .init() }

        let now = Date()
        insert(
            cardIDs: resolvedCardIDs,
            into: .group(groupID),
            insertionIndex: insertionIndex ?? Int.max,
            document: &document
        )
        touchHost(.group(groupID), document: &document, timestamp: now)
        document.updatedAt = now
        return BWRMutationSummary(changedCardIDs: Set(resolvedCardIDs), metadataChanged: true)
    }

    static func detachCards(
        document: inout BWRDocument,
        fromGroup groupID: UUID,
        cardIDs: [UUID],
        preferredStripID: UUID?,
        insertionIndex: Int?
    ) -> BWRMutationSummary {
        guard let group = document.groups.first(where: { $0.id == groupID && !$0.isArchived }) else {
            return .init()
        }

        let orderedCardIDs = group.memberCardIDs.filter { cardIDs.contains($0) }
        guard !orderedCardIDs.isEmpty else { return .init() }

        let stripID = preferredStripID.flatMap { preferred in
            document.parkingStrips.contains(where: { $0.id == preferred }) ? preferred : nil
        } ?? BWRSlotPlacementNormalizer.ensureRecoveryStrip(document: &document)

        let now = Date()
        insert(
            cardIDs: orderedCardIDs,
            into: .strip(stripID),
            insertionIndex: insertionIndex ?? Int.max,
            document: &document
        )
        cleanupParkingStrips(document: &document)
        touchHost(.group(groupID), document: &document, timestamp: now)
        touchHost(.strip(stripID), document: &document, timestamp: now)
        document.updatedAt = now
        return BWRMutationSummary(changedCardIDs: Set(orderedCardIDs), metadataChanged: true)
    }

    static func reorderCards(
        document: inout BWRDocument,
        host: BWRSlotHost,
        cardIDs: [UUID],
        insertionIndex: Int
    ) -> BWRMutationSummary {
        moveCards(
            document: &document,
            to: host,
            cardIDs: cardIDs,
            insertionIndex: insertionIndex
        )
    }

    static func moveCards(
        document: inout BWRDocument,
        to host: BWRSlotHost,
        cardIDs: [UUID],
        insertionIndex: Int
    ) -> BWRMutationSummary {
        let resolvedCardIDs = deduplicatedCardIDs(cardIDs).filter { cardID in
            document.cards.contains(where: { $0.id == cardID && !$0.isArchived })
        }
        guard !resolvedCardIDs.isEmpty else { return .init() }

        let sourceHosts = Set(resolvedCardIDs.compactMap { BWRSlotOrder.host(for: $0, document: document) })
        let now = Date()
        insert(cardIDs: resolvedCardIDs, into: host, insertionIndex: insertionIndex, document: &document)
        cleanupParkingStrips(document: &document)
        for touchedHost in sourceHosts.union([host]) {
            touchHost(touchedHost, document: &document, timestamp: now)
        }
        document.updatedAt = now
        return BWRMutationSummary(changedCardIDs: Set(resolvedCardIDs), metadataChanged: true)
    }

    static func moveCardsToParkingStrip(
        document: inout BWRDocument,
        cardIDs: [UUID],
        originSlot: BWRSlotCoordinate,
        insertionIndex: Int
    ) -> BWRMutationSummary {
        let resolvedCardIDs = deduplicatedCardIDs(cardIDs).filter { cardID in
            document.cards.contains(where: { $0.id == cardID && !$0.isArchived })
        }
        guard !resolvedCardIDs.isEmpty else { return .init() }

        let strip = BWRParkingStrip(
            row: originSlot.row,
            anchorColumn: originSlot.column,
            cardIDs: []
        )
        document.parkingStrips.append(strip)
        return moveCards(
            document: &document,
            to: .strip(strip.id),
            cardIDs: resolvedCardIDs,
            insertionIndex: insertionIndex
        )
    }

    static func moveGroupOrigin(
        document: inout BWRDocument,
        groupID: UUID,
        originSlot: BWRSlotCoordinate
    ) -> BWRMutationSummary {
        guard let groupIndex = document.groups.firstIndex(where: { $0.id == groupID && !$0.isArchived }) else {
            return .init()
        }
        guard document.groups[groupIndex].originSlot != originSlot else { return .init() }

        let now = Date()
        document.groups[groupIndex].originSlot = originSlot
        document.groups[groupIndex].updatedAt = now
        document.updatedAt = now
        return BWRMutationSummary(metadataChanged: true)
    }

    static func appendBodyLayer(document: inout BWRDocument, cardID: UUID) -> BWRMutationSummary {
        guard let index = document.cards.firstIndex(where: { $0.id == cardID }) else { return .init() }
        var card = document.cards[index]
        let bodyLayers = card.layers.filter { $0.kind == .body }
        let nextBodyIndex = bodyLayers.count
        let newBodyLayer = BWRCardLayer(
            kind: .body,
            name: BWRNaming.bodyLayerName(for: nextBodyIndex),
            markdown: "",
            order: nextBodyIndex
        )

        var layers = bodyLayers + [newBodyLayer]
        let treatmentLayer = card.layers.first(where: { $0.kind == .treatment }) ?? BWRCardLayer(
            kind: .treatment,
            name: "Treatment",
            markdown: "",
            order: nextBodyIndex + 1
        )
        let scenarioLayer = card.layers.first(where: { $0.kind == .scenario }) ?? BWRCardLayer(
            kind: .scenario,
            name: "Scenario",
            markdown: "",
            order: nextBodyIndex + 2
        )
        layers.append(BWRCardLayer(
            id: treatmentLayer.id,
            kind: .treatment,
            name: treatmentLayer.name,
            markdown: treatmentLayer.markdown,
            order: nextBodyIndex + 1
        ))
        layers.append(BWRCardLayer(
            id: scenarioLayer.id,
            kind: .scenario,
            name: scenarioLayer.name,
            markdown: scenarioLayer.markdown,
            order: nextBodyIndex + 2
        ))

        card.layers = layers
        card.updatedAt = Date()
        document.cards[index] = card
        document.updatedAt = card.updatedAt
        return BWRMutationSummary(changedCardIDs: [card.id], metadataChanged: true)
    }

    static func renameLayer(
        document: inout BWRDocument,
        cardID: UUID,
        layerID: UUID,
        newName: String
    ) -> BWRMutationSummary {
        guard let index = document.cards.firstIndex(where: { $0.id == cardID }),
              let layerIndex = document.cards[index].layers.firstIndex(where: { $0.id == layerID }) else {
            return .init()
        }
        guard document.cards[index].layers[layerIndex].kind == .body else { return .init() }

        document.cards[index].layers[layerIndex].name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        document.cards[index].updatedAt = Date()
        document.updatedAt = document.cards[index].updatedAt
        return BWRMutationSummary(changedCardIDs: [cardID], metadataChanged: true)
    }

    static func deleteBodyLayer(
        document: inout BWRDocument,
        cardID: UUID,
        layerID: UUID
    ) -> BWRMutationSummary {
        guard let index = document.cards.firstIndex(where: { $0.id == cardID }) else { return .init() }
        var card = document.cards[index]
        let bodyLayers = card.layers.filter { $0.kind == .body }
        guard bodyLayers.count > 1,
              let removalIndex = card.layers.firstIndex(where: { $0.id == layerID && $0.kind == .body }) else {
            return .init()
        }

        card.layers.remove(at: removalIndex)
        card.layers = normalizedLayerOrders(card.layers)
        if card.currentLayerID == layerID, let fallback = card.layers.first(where: { $0.kind == .body }) {
            card.currentLayerID = fallback.id
        }
        card.updatedAt = Date()
        document.cards[index] = card
        document.updatedAt = card.updatedAt
        return BWRMutationSummary(changedCardIDs: [cardID], metadataChanged: true)
    }

    static func moveBodyLayer(
        document: inout BWRDocument,
        cardID: UUID,
        layerID: UUID,
        destinationBodyIndex: Int
    ) -> BWRMutationSummary {
        guard let cardIndex = document.cards.firstIndex(where: { $0.id == cardID }) else { return .init() }
        var card = document.cards[cardIndex]
        var bodyLayers = card.layers.filter { $0.kind == .body }
        guard let currentIndex = bodyLayers.firstIndex(where: { $0.id == layerID }) else { return .init() }

        let safeDestination = max(0, min(destinationBodyIndex, bodyLayers.count - 1))
        guard currentIndex != safeDestination else { return .init() }

        let moved = bodyLayers.remove(at: currentIndex)
        bodyLayers.insert(moved, at: safeDestination)

        let treatment = card.layers.first(where: { $0.kind == .treatment })
        let scenario = card.layers.first(where: { $0.kind == .scenario })
        var rebuilt: [BWRCardLayer] = []
        for (index, layer) in bodyLayers.enumerated() {
            rebuilt.append(BWRCardLayer(
                id: layer.id,
                kind: .body,
                name: layer.name,
                markdown: layer.markdown,
                order: index
            ))
        }
        if let treatment {
            rebuilt.append(BWRCardLayer(
                id: treatment.id,
                kind: .treatment,
                name: treatment.name,
                markdown: treatment.markdown,
                order: rebuilt.count
            ))
        }
        if let scenario {
            rebuilt.append(BWRCardLayer(
                id: scenario.id,
                kind: .scenario,
                name: scenario.name,
                markdown: scenario.markdown,
                order: rebuilt.count
            ))
        }

        card.layers = rebuilt
        card.updatedAt = Date()
        document.cards[cardIndex] = card
        document.updatedAt = card.updatedAt
        return BWRMutationSummary(changedCardIDs: [cardID], metadataChanged: true)
    }

    static func setCurrentLayer(
        document: inout BWRDocument,
        cardID: UUID,
        layerID: UUID
    ) -> BWRMutationSummary {
        guard let cardIndex = document.cards.firstIndex(where: { $0.id == cardID }),
              document.cards[cardIndex].layers.contains(where: { $0.id == layerID }) else {
            return .init()
        }

        document.cards[cardIndex].currentLayerID = layerID
        document.cards[cardIndex].updatedAt = Date()
        document.updatedAt = document.cards[cardIndex].updatedAt
        return BWRMutationSummary(changedCardIDs: [cardID], metadataChanged: true)
    }

    static func setCurrentLayerMatchingSignature(
        document: inout BWRDocument,
        cardIDs: Set<UUID>,
        signature: BWRLayerSignature
    ) -> BWRMutationSummary {
        guard !cardIDs.isEmpty else { return .init() }

        var summary = BWRMutationSummary(metadataChanged: true)
        let now = Date()
        for cardIndex in document.cards.indices where cardIDs.contains(document.cards[cardIndex].id) {
            guard let targetLayer = document.cards[cardIndex].layers.first(where: {
                BWRLayerSignature(layer: $0) == signature
            }) else {
                continue
            }
            guard document.cards[cardIndex].currentLayerID != targetLayer.id else { continue }
            document.cards[cardIndex].currentLayerID = targetLayer.id
            document.cards[cardIndex].updatedAt = now
            summary.changedCardIDs.insert(document.cards[cardIndex].id)
        }

        guard summary.hasChanges else { return .init() }
        document.updatedAt = now
        return summary
    }

    static func cycleCurrentLayer(
        document: inout BWRDocument,
        cardIDs: Set<UUID>,
        direction: Int
    ) -> BWRMutationSummary {
        guard !cardIDs.isEmpty else { return .init() }
        let delta = direction >= 0 ? 1 : -1
        var summary = BWRMutationSummary(metadataChanged: true)
        let now = Date()

        for cardIndex in document.cards.indices where cardIDs.contains(document.cards[cardIndex].id) {
            let layers = document.cards[cardIndex].layers
            guard let currentIndex = layers.firstIndex(where: { $0.id == document.cards[cardIndex].currentLayerID }),
                  !layers.isEmpty else {
                continue
            }
            let nextIndex = (currentIndex + delta + layers.count) % layers.count
            guard layers[nextIndex].id != document.cards[cardIndex].currentLayerID else { continue }
            document.cards[cardIndex].currentLayerID = layers[nextIndex].id
            document.cards[cardIndex].updatedAt = now
            summary.changedCardIDs.insert(document.cards[cardIndex].id)
        }

        guard summary.hasChanges else { return .init() }
        document.updatedAt = now
        return summary
    }

    static func updateLayerMarkdown(
        document: inout BWRDocument,
        cardID: UUID,
        layerID: UUID,
        markdown: String,
        recursionGuard: inout BWRCloneRecursionGuard
    ) -> BWRMutationSummary {
        guard let sourceIndex = document.cards.firstIndex(where: { $0.id == cardID }),
              let sourceLayer = document.cards[sourceIndex].layers.first(where: { $0.id == layerID }) else {
            return .init()
        }

        let signature = BWRLayerSignature(layer: sourceLayer)
        let cloneGroupID = document.cards[sourceIndex].cloneGroupID
        let sourceCardID = document.cards[sourceIndex].id
        var summary = BWRMutationSummary()

        let targetIndices = targetCardIndices(
            in: document.cards,
            sourceCardID: sourceCardID,
            cloneGroupID: cloneGroupID,
            recursionGuard: &recursionGuard
        )

        for cardIndex in targetIndices {
            guard let layerIndex = document.cards[cardIndex].layers.firstIndex(where: {
                BWRLayerSignature(layer: $0) == signature
            }) else { continue }
            document.cards[cardIndex].layers[layerIndex].markdown = markdown
            document.cards[cardIndex].updatedAt = Date()
            summary.changedCardIDs.insert(document.cards[cardIndex].id)
        }

        if summary.hasChanges {
            document.updatedAt = Date()
        }
        return summary
    }

    static func updateCardColor(
        document: inout BWRDocument,
        cardID: UUID,
        colorHex: String?,
        recursionGuard: inout BWRCloneRecursionGuard
    ) -> BWRMutationSummary {
        guard let sourceIndex = document.cards.firstIndex(where: { $0.id == cardID }) else { return .init() }
        let cloneGroupID = document.cards[sourceIndex].cloneGroupID
        let targetIndices = targetCardIndices(
            in: document.cards,
            sourceCardID: cardID,
            cloneGroupID: cloneGroupID,
            recursionGuard: &recursionGuard
        )

        var summary = BWRMutationSummary()
        for cardIndex in targetIndices {
            document.cards[cardIndex].colorHex = colorHex
            document.cards[cardIndex].updatedAt = Date()
            summary.changedCardIDs.insert(document.cards[cardIndex].id)
        }
        if summary.hasChanges {
            document.updatedAt = Date()
        }
        return summary
    }

    static func createLink(
        document: inout BWRDocument,
        sourceCardID: UUID,
        destinationCardID: UUID
    ) -> BWRMutationSummary {
        guard sourceCardID != destinationCardID,
              document.cards.contains(where: { $0.id == sourceCardID && !$0.isArchived }),
              document.cards.contains(where: { $0.id == destinationCardID && !$0.isArchived }) else {
            return .init()
        }

        if let archivedIndex = document.links.firstIndex(where: {
            $0.sourceCardID == sourceCardID &&
            $0.destinationCardID == destinationCardID &&
            $0.isArchived
        }) {
            let now = Date()
            document.links[archivedIndex].isArchived = false
            document.links[archivedIndex].archivedAt = nil
            document.links[archivedIndex].updatedAt = now
            refreshArchiveStore(document: &document)
            document.updatedAt = now
            return BWRMutationSummary(metadataChanged: true)
        }

        guard !document.links.contains(where: {
            $0.sourceCardID == sourceCardID &&
            $0.destinationCardID == destinationCardID &&
            !$0.isArchived
        }) else {
            return .init()
        }

        let now = Date()
        document.links.append(
            BWRLink(
                sourceCardID: sourceCardID,
                destinationCardID: destinationCardID,
                createdAt: now,
                updatedAt: now
            )
        )
        refreshArchiveStore(document: &document)
        document.updatedAt = now
        return BWRMutationSummary(metadataChanged: true)
    }

    static func splitCard(
        document: inout BWRDocument,
        cardID: UUID,
        layerID: UUID? = nil,
        atUTF16Location location: Int
    ) -> BWRCardSplitResult? {
        guard let sourceIndex = document.cards.firstIndex(where: { $0.id == cardID }) else { return nil }
        var sourceCard = document.cards[sourceIndex]
        let targetLayerID = layerID ?? sourceCard.currentLayerID
        guard let currentLayerIndex = sourceCard.layers.firstIndex(where: { $0.id == targetLayerID }) else {
            return nil
        }

        let currentText = sourceCard.layers[currentLayerIndex].markdown
        let nsText = currentText as NSString
        let clampedLocation = max(0, min(location, nsText.length))
        let leftText = nsText.substring(to: clampedLocation)
        let rightText = nsText.substring(from: clampedLocation)

        sourceCard.layers[currentLayerIndex].markdown = leftText
        sourceCard.updatedAt = Date()
        document.cards[sourceIndex] = sourceCard

        let now = Date()
        let sourceCurrentLayer = sourceCard.layers[currentLayerIndex]
        let newLayers = sourceCard.layers.map { layer -> BWRCardLayer in
            let markdown: String
            if layer.id == sourceCurrentLayer.id {
                markdown = rightText
            } else {
                markdown = ""
            }
            return BWRCardLayer(
                kind: layer.kind,
                name: layer.name,
                markdown: markdown,
                order: layer.order
            )
        }

        guard let newCurrentLayer = newLayers.first(where: {
            $0.kind == sourceCurrentLayer.kind && $0.name == sourceCurrentLayer.name && $0.order == sourceCurrentLayer.order
        }) else {
            return nil
        }

        let newCard = BWRCard(
            stableSortKey: document.allocateStableSortKey(),
            colorHex: sourceCard.colorHex,
            currentLayerID: newCurrentLayer.id,
            layout: BWRPoint(x: sourceCard.layout.x, y: sourceCard.layout.y + 140),
            createdAt: now,
            updatedAt: now,
            layers: newLayers
        )

        document.cards.append(newCard)
        if let hostLocation = BWRSlotOrder.indexOfCardInHost(cardID: sourceCard.id, document: document) {
            insert(
                cardIDs: [newCard.id],
                into: hostLocation.host,
                insertionIndex: hostLocation.index + 1,
                document: &document
            )
            touchHost(hostLocation.host, document: &document, timestamp: now)
        } else {
            let stripID = BWRSlotPlacementNormalizer.ensureRecoveryStrip(document: &document)
            insert(cardIDs: [newCard.id], into: .strip(stripID), insertionIndex: Int.max, document: &document)
        }
        document.updatedAt = now

        let summary = BWRMutationSummary(
            changedCardIDs: [sourceCard.id, newCard.id],
            metadataChanged: true
        )
        return BWRCardSplitResult(
            originalCardID: sourceCard.id,
            newCardID: newCard.id,
            summary: summary
        )
    }

    static func archiveCard(document: inout BWRDocument, cardID: UUID) -> BWRMutationSummary {
        guard let cardIndex = document.cards.firstIndex(where: { $0.id == cardID && !$0.isArchived }) else {
            return .init()
        }

        let now = Date()
        document.cards[cardIndex].isArchived = true
        document.cards[cardIndex].archivedAt = now
        document.cards[cardIndex].updatedAt = now
        _ = archiveLinksConnected(to: Set([cardID]), document: &document, timestamp: now)
        document.cards = BWRCloneNormalizer.normalize(cards: document.cards)
        refreshArchiveStore(document: &document)
        document.updatedAt = now
        return BWRMutationSummary(changedCardIDs: [cardID], metadataChanged: true)
    }

    static func deleteCard(document: inout BWRDocument, cardID: UUID) -> BWRMutationSummary {
        guard let card = document.cards.first(where: { $0.id == cardID }) else { return .init() }
        if card.cloneGroupID != nil {
            return hardDeleteCard(document: &document, cardID: cardID)
        }
        return archiveCard(document: &document, cardID: cardID)
    }

    static func restoreCard(document: inout BWRDocument, cardID: UUID) -> BWRMutationSummary {
        guard let cardIndex = document.cards.firstIndex(where: { $0.id == cardID && $0.isArchived }) else {
            return .init()
        }

        let now = Date()
        document.cards[cardIndex].isArchived = false
        document.cards[cardIndex].archivedAt = nil
        document.cards[cardIndex].updatedAt = now
        refreshArchiveStore(document: &document)
        document.updatedAt = now
        return BWRMutationSummary(changedCardIDs: [cardID], metadataChanged: true)
    }

    static func archiveLink(document: inout BWRDocument, linkID: UUID) -> BWRMutationSummary {
        guard let linkIndex = document.links.firstIndex(where: { $0.id == linkID && !$0.isArchived }) else {
            return .init()
        }

        let now = Date()
        document.links[linkIndex].isArchived = true
        document.links[linkIndex].archivedAt = now
        document.links[linkIndex].updatedAt = now
        refreshArchiveStore(document: &document)
        document.updatedAt = now
        return BWRMutationSummary(metadataChanged: true)
    }

    static func restoreLink(document: inout BWRDocument, linkID: UUID) -> BWRMutationSummary {
        guard let linkIndex = document.links.firstIndex(where: { $0.id == linkID && $0.isArchived }) else {
            return .init()
        }

        let sourceID = document.links[linkIndex].sourceCardID
        let destinationID = document.links[linkIndex].destinationCardID
        guard document.cards.contains(where: { $0.id == sourceID && !$0.isArchived }),
              document.cards.contains(where: { $0.id == destinationID && !$0.isArchived }) else {
            return .init()
        }

        let now = Date()
        document.links[linkIndex].isArchived = false
        document.links[linkIndex].archivedAt = nil
        document.links[linkIndex].updatedAt = now
        refreshArchiveStore(document: &document)
        document.updatedAt = now
        return BWRMutationSummary(metadataChanged: true)
    }

    static func archiveGroup(document: inout BWRDocument, groupID: UUID) -> BWRMutationSummary {
        guard let groupIndex = document.groups.firstIndex(where: { $0.id == groupID && !$0.isArchived }) else {
            return .init()
        }

        let now = Date()
        let memberCardIDs = document.groups[groupIndex].memberCardIDs
        document.groups[groupIndex].isArchived = true
        document.groups[groupIndex].archivedAt = now
        document.groups[groupIndex].updatedAt = now

        var summary = BWRMutationSummary(metadataChanged: true)
        var newlyArchivedCardIDs: Set<UUID> = []

        for memberCardID in memberCardIDs {
            guard let card = document.cards.first(where: { $0.id == memberCardID && !$0.isArchived }) else { continue }
            if card.cloneGroupID != nil {
                let removalSummary = hardDeleteCard(document: &document, cardID: memberCardID)
                summary.merge(removalSummary)
                continue
            }

            guard let cardIndex = document.cards.firstIndex(where: { $0.id == memberCardID && !$0.isArchived }) else {
                continue
            }

            document.cards[cardIndex].isArchived = true
            document.cards[cardIndex].archivedAt = now
            document.cards[cardIndex].updatedAt = now
            summary.changedCardIDs.insert(memberCardID)
            newlyArchivedCardIDs.insert(memberCardID)
        }

        _ = archiveLinksConnected(
            to: newlyArchivedCardIDs,
            document: &document,
            timestamp: now
        )
        refreshArchiveStore(document: &document)
        document.updatedAt = now
        return summary
    }

    static func restoreGroup(document: inout BWRDocument, groupID: UUID) -> BWRMutationSummary {
        guard let groupIndex = document.groups.firstIndex(where: { $0.id == groupID && $0.isArchived }) else {
            return .init()
        }

        let now = Date()
        document.groups[groupIndex].isArchived = false
        document.groups[groupIndex].archivedAt = nil
        document.groups[groupIndex].updatedAt = now

        var changedCards = Set<UUID>()
        for memberCardID in document.groups[groupIndex].memberCardIDs {
            if let cardIndex = document.cards.firstIndex(where: { $0.id == memberCardID && $0.isArchived }) {
                document.cards[cardIndex].isArchived = false
                document.cards[cardIndex].archivedAt = nil
                document.cards[cardIndex].updatedAt = now
                changedCards.insert(memberCardID)
            }
        }

        refreshArchiveStore(document: &document)
        document.updatedAt = now
        return BWRMutationSummary(changedCardIDs: changedCards, metadataChanged: true)
    }

    static func refreshArchiveStore(document: inout BWRDocument) {
        let existingEntriesByKey = Dictionary(uniqueKeysWithValues: document.archive.map {
            (archiveKey(kind: $0.entityKind, entityID: $0.entityID), $0)
        })

        var refreshedEntries: [BWRArchiveEntry] = []
        for card in document.cards where card.isArchived {
            let key = archiveKey(kind: .card, entityID: card.id)
            let existing = existingEntriesByKey[key]
            refreshedEntries.append(
                BWRArchiveEntry(
                    id: existing?.id ?? UUID(),
                    entityID: card.id,
                    entityKind: .card,
                    title: card.titlePreview,
                    searchBlob: card.layers.map(\.markdown).joined(separator: "\n"),
                    colorHex: card.colorHex,
                    archivedAt: existing?.archivedAt ?? card.archivedAt ?? Date()
                )
            )
        }

        for group in document.groups where group.isArchived {
            let key = archiveKey(kind: .group, entityID: group.id)
            let existing = existingEntriesByKey[key]
            refreshedEntries.append(
                BWRArchiveEntry(
                    id: existing?.id ?? UUID(),
                    entityID: group.id,
                    entityKind: .group,
                    title: group.name,
                    searchBlob: group.name,
                    colorHex: nil,
                    archivedAt: existing?.archivedAt ?? group.archivedAt ?? Date()
                )
            )
        }

        for link in document.links where link.isArchived {
            let key = archiveKey(kind: .link, entityID: link.id)
            let existing = existingEntriesByKey[key]
            refreshedEntries.append(
                BWRArchiveEntry(
                    id: existing?.id ?? UUID(),
                    entityID: link.id,
                    entityKind: .link,
                    title: "Link \(link.sourceCardID.uuidString.prefix(4)) -> \(link.destinationCardID.uuidString.prefix(4))",
                    searchBlob: "\(link.sourceCardID.uuidString) \(link.destinationCardID.uuidString)",
                    colorHex: nil,
                    archivedAt: existing?.archivedAt ?? link.archivedAt ?? Date()
                )
            )
        }

        document.archive = refreshedEntries.sorted { lhs, rhs in
            if lhs.archivedAt != rhs.archivedAt { return lhs.archivedAt > rhs.archivedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func targetCardIndices(
        in cards: [BWRCard],
        sourceCardID: UUID,
        cloneGroupID: UUID?,
        recursionGuard: inout BWRCloneRecursionGuard
    ) -> [Int] {
        guard let cloneGroupID else {
            return cards.indices.filter { cards[$0].id == sourceCardID }
        }

        if recursionGuard.visitedCloneGroupIDs.contains(cloneGroupID) {
            return cards.indices.filter { cards[$0].id == sourceCardID }
        }

        recursionGuard.visitedCloneGroupIDs.insert(cloneGroupID)
        return BWRCloneNormalizer.orderedIndices(
            in: cards,
            sourceCardID: sourceCardID,
            cloneGroupID: cloneGroupID
        )
    }

    private static func archiveKey(kind: BWRArchiveEntityKind, entityID: UUID) -> String {
        "\(kind.rawValue)|\(entityID.uuidString)"
    }

    private static func archiveLinksConnected(
        to archivedCardIDs: Set<UUID>,
        document: inout BWRDocument,
        timestamp: Date
    ) -> Bool {
        guard !archivedCardIDs.isEmpty else { return false }

        var changed = false
        for linkIndex in document.links.indices where !document.links[linkIndex].isArchived {
            let link = document.links[linkIndex]
            guard archivedCardIDs.contains(link.sourceCardID) || archivedCardIDs.contains(link.destinationCardID) else {
                continue
            }
            document.links[linkIndex].isArchived = true
            document.links[linkIndex].archivedAt = timestamp
            document.links[linkIndex].updatedAt = timestamp
            changed = true
        }
        return changed
    }

    private static func hardDeleteCard(document: inout BWRDocument, cardID: UUID) -> BWRMutationSummary {
        guard let cardIndex = document.cards.firstIndex(where: { $0.id == cardID }) else { return .init() }

        let now = Date()
        document.cards.remove(at: cardIndex)
        for groupIndex in document.groups.indices {
            let originalCount = document.groups[groupIndex].memberCardIDs.count
            document.groups[groupIndex].memberCardIDs.removeAll { $0 == cardID }
            if document.groups[groupIndex].memberCardIDs.count != originalCount {
                document.groups[groupIndex].updatedAt = now
            }
        }
        for stripIndex in document.parkingStrips.indices {
            document.parkingStrips[stripIndex].cardIDs.removeAll { $0 == cardID }
        }
        document.parkingStrips.removeAll { $0.cardIDs.isEmpty }

        let normalizedCards = BWRCloneNormalizer.normalize(cards: document.cards)
        let normalizedChangedCardIDs = Set(
            zip(document.cards, normalizedCards)
                .compactMap { before, after in before == after ? nil : after.id }
        )
        document.cards = normalizedCards
        document.links.removeAll { $0.sourceCardID == cardID || $0.destinationCardID == cardID }
        refreshArchiveStore(document: &document)
        document.updatedAt = now
        return BWRMutationSummary(
            changedCardIDs: normalizedChangedCardIDs,
            removedCardIDs: [cardID],
            metadataChanged: true
        )
    }

    private static func normalizedLayerOrders(_ layers: [BWRCardLayer]) -> [BWRCardLayer] {
        let bodyLayers = layers
            .filter { $0.kind == .body }
            .enumerated()
            .map { index, layer in
                BWRCardLayer(
                    id: layer.id,
                    kind: .body,
                    name: layer.name,
                    markdown: layer.markdown,
                    order: index
                )
            }

        let treatmentLayer = layers.first(where: { $0.kind == .treatment }).map {
            BWRCardLayer(
                id: $0.id,
                kind: .treatment,
                name: $0.name,
                markdown: $0.markdown,
                order: bodyLayers.count
            )
        }

        let scenarioLayer = layers.first(where: { $0.kind == .scenario }).map {
            BWRCardLayer(
                id: $0.id,
                kind: .scenario,
                name: $0.name,
                markdown: $0.markdown,
                order: bodyLayers.count + (treatmentLayer == nil ? 0 : 1)
            )
        }

        return bodyLayers + [treatmentLayer, scenarioLayer].compactMap { $0 }
    }

    private static func liveGroupMembershipCounts(
        document: BWRDocument,
        excludingGroupID: UUID? = nil
    ) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for group in document.groups where !group.isArchived && group.id != excludingGroupID {
            for memberCardID in group.memberCardIDs {
                counts[memberCardID, default: 0] += 1
            }
        }
        return counts
    }

    private static func deduplicatedCardIDs(_ cardIDs: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return cardIDs.filter { seen.insert($0).inserted }
    }

    private static func preferredGroupOrigin(document: BWRDocument, memberCardIDs: [UUID]) -> BWRSlotCoordinate {
        let cardsByID = Dictionary(uniqueKeysWithValues: document.cards.map { ($0.id, $0) })
        if let anchor = memberCardIDs.compactMap({ cardsByID[$0] }).sorted(by: BWRSlotOrder.stableCardCompare).first {
            let projection = BWRSlotBoardProjection.project(document: document)
            if let projected = projection.cardRectsByID[anchor.id] {
                return BWRSlotCoordinate(
                    column: max(0, Int((projected.slotRect.minX / projection.metrics.slotWidth).rounded())),
                    row: max(0, Int((projected.slotRect.minY / projection.metrics.slotHeight).rounded()))
                )
            }
        }

        let maxGroupRow = document.groups.compactMap(\.originSlot?.row).max() ?? -1
        let maxStripRow = document.parkingStrips.map(\.row).max() ?? -1
        return BWRSlotCoordinate(column: 0, row: max(maxGroupRow, maxStripRow) + 2)
    }

    private static func reorderedHostCardIDs(
        hostCardIDs: [UUID],
        movedIDs: [UUID],
        desiredPositionByID: [UUID: Double],
        cardsByID: [UUID: BWRCard]
    ) -> [UUID] {
        let originalIndexByID = Dictionary(uniqueKeysWithValues: hostCardIDs.enumerated().map { ($1, $0) })
        return hostCardIDs.sorted { lhs, rhs in
            let leftDesired = desiredPositionByID[lhs] ?? Double(originalIndexByID[lhs] ?? 0)
            let rightDesired = desiredPositionByID[rhs] ?? Double(originalIndexByID[rhs] ?? 0)
            if leftDesired != rightDesired { return leftDesired < rightDesired }

            let leftOriginal = originalIndexByID[lhs] ?? 0
            let rightOriginal = originalIndexByID[rhs] ?? 0
            if leftOriginal != rightOriginal { return leftOriginal < rightOriginal }

            guard let leftCard = cardsByID[lhs], let rightCard = cardsByID[rhs] else {
                return lhs.uuidString < rhs.uuidString
            }
            return BWRSlotOrder.stableCardCompare(leftCard, rightCard)
        }
    }

    private static func insert(
        cardIDs: [UUID],
        into host: BWRSlotHost,
        insertionIndex: Int,
        document: inout BWRDocument
    ) {
        let resolvedCardIDs = deduplicatedCardIDs(cardIDs)
        guard !resolvedCardIDs.isEmpty else { return }
        let resolvedSet = Set(resolvedCardIDs)

        for groupIndex in document.groups.indices where !document.groups[groupIndex].isArchived {
            document.groups[groupIndex].memberCardIDs.removeAll { resolvedSet.contains($0) }
        }
        for stripIndex in document.parkingStrips.indices {
            document.parkingStrips[stripIndex].cardIDs.removeAll { resolvedSet.contains($0) }
        }

        switch host {
        case let .group(groupID):
            guard let groupIndex = document.groups.firstIndex(where: { $0.id == groupID && !$0.isArchived }) else { return }
            let safeIndex = max(0, min(insertionIndex, document.groups[groupIndex].memberCardIDs.count))
            document.groups[groupIndex].memberCardIDs.insert(contentsOf: resolvedCardIDs, at: safeIndex)
        case let .strip(stripID):
            guard let stripIndex = document.parkingStrips.firstIndex(where: { $0.id == stripID }) else { return }
            let safeIndex = max(0, min(insertionIndex, document.parkingStrips[stripIndex].cardIDs.count))
            document.parkingStrips[stripIndex].cardIDs.insert(contentsOf: resolvedCardIDs, at: safeIndex)
        }
    }

    private static func cleanupParkingStrips(document: inout BWRDocument) {
        document.parkingStrips.removeAll { $0.cardIDs.isEmpty }
    }

    private static func touchHost(_ host: BWRSlotHost, document: inout BWRDocument, timestamp: Date) {
        switch host {
        case let .group(groupID):
            if let index = document.groups.firstIndex(where: { $0.id == groupID }) {
                document.groups[index].updatedAt = timestamp
            }
        case .strip:
            break
        }
    }
}

nonisolated struct BWRLayerSignature: Equatable, Hashable, Sendable {
    let kind: BWRLayerKind
    let name: String
    let order: Int

    init(layer: BWRCardLayer) {
        self.kind = layer.kind
        self.name = layer.name
        self.order = layer.order
    }
}
