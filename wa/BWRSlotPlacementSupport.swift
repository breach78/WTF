import Foundation

nonisolated enum BWRSlotHost: Hashable, Codable, Sendable {
    case group(UUID)
    case strip(UUID)

    private enum CodingKeys: String, CodingKey {
        case kind
        case id
    }

    private enum Kind: String, Codable {
        case group
        case strip
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let id = try container.decode(UUID.self, forKey: .id)
        switch kind {
        case .group:
            self = .group(id)
        case .strip:
            self = .strip(id)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .group(id):
            try container.encode(Kind.group, forKey: .kind)
            try container.encode(id, forKey: .id)
        case let .strip(id):
            try container.encode(Kind.strip, forKey: .kind)
            try container.encode(id, forKey: .id)
        }
    }
}

nonisolated struct BWRSelectionPlacementTarget: Equatable, Sendable {
    var host: BWRSlotHost
    var insertionIndex: Int
}

nonisolated enum BWRSlotOrder {
    static func orderedLiveGroups(in document: BWRDocument) -> [BWRGroup] {
        document.groups
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                let left = lhs.originSlot ?? BWRSlotCoordinate(column: 0, row: 0)
                let right = rhs.originSlot ?? BWRSlotCoordinate(column: 0, row: 0)
                if left.row != right.row { return left.row < right.row }
                if left.column != right.column { return left.column < right.column }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    static func orderedLiveStrips(in document: BWRDocument) -> [BWRParkingStrip] {
        document.parkingStrips
            .sorted { lhs, rhs in
                if lhs.row != rhs.row { return lhs.row < rhs.row }
                if lhs.anchorColumn != rhs.anchorColumn { return lhs.anchorColumn < rhs.anchorColumn }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    static func orderedLiveCardIDs(in document: BWRDocument) -> [UUID] {
        let cardsByID = Dictionary(uniqueKeysWithValues: document.cards.filter { !$0.isArchived }.map { ($0.id, $0) })
        var ordered: [UUID] = []
        var seen: Set<UUID> = []

        for group in orderedLiveGroups(in: document) {
            for cardID in group.memberCardIDs where cardsByID[cardID] != nil && seen.insert(cardID).inserted {
                ordered.append(cardID)
            }
        }

        for strip in orderedLiveStrips(in: document) {
            for cardID in strip.cardIDs where cardsByID[cardID] != nil && seen.insert(cardID).inserted {
                ordered.append(cardID)
            }
        }

        let remainder = cardsByID.values
            .filter { !seen.contains($0.id) }
            .sorted(by: stableCardCompare)
            .map(\.id)
        ordered.append(contentsOf: remainder)
        return ordered
    }

    static func orderedLiveCards(in document: BWRDocument) -> [BWRCard] {
        let cardsByID = Dictionary(uniqueKeysWithValues: document.cards.filter { !$0.isArchived }.map { ($0.id, $0) })
        return orderedLiveCardIDs(in: document).compactMap { cardsByID[$0] }
    }

    static func orderedArchivedCards(in document: BWRDocument) -> [BWRCard] {
        document.cards
            .filter(\.isArchived)
            .sorted { lhs, rhs in
                let left = lhs.archivedAt ?? lhs.updatedAt
                let right = rhs.archivedAt ?? rhs.updatedAt
                if left != right { return left > right }
                return stableCardCompare(lhs, rhs)
            }
    }

    static func orderedCards(inGroup groupID: UUID, document: BWRDocument) -> [BWRCard] {
        guard let group = document.groups.first(where: { $0.id == groupID && !$0.isArchived }) else { return [] }
        let cardsByID = Dictionary(uniqueKeysWithValues: document.cards.filter { !$0.isArchived }.map { ($0.id, $0) })
        return group.memberCardIDs.compactMap { cardsByID[$0] }
    }

    static func orderedCards(inStrip stripID: UUID, document: BWRDocument) -> [BWRCard] {
        guard let strip = document.parkingStrips.first(where: { $0.id == stripID }) else { return [] }
        let cardsByID = Dictionary(uniqueKeysWithValues: document.cards.filter { !$0.isArchived }.map { ($0.id, $0) })
        return strip.cardIDs.compactMap { cardsByID[$0] }
    }

    static func host(for cardID: UUID, document: BWRDocument) -> BWRSlotHost? {
        if let group = document.groups.first(where: { !$0.isArchived && $0.memberCardIDs.contains(cardID) }) {
            return .group(group.id)
        }
        if let strip = document.parkingStrips.first(where: { $0.cardIDs.contains(cardID) }) {
            return .strip(strip.id)
        }
        return nil
    }

    static func cardIDs(in host: BWRSlotHost, document: BWRDocument) -> [UUID] {
        switch host {
        case let .group(groupID):
            return document.groups.first(where: { $0.id == groupID && !$0.isArchived })?.memberCardIDs ?? []
        case let .strip(stripID):
            return document.parkingStrips.first(where: { $0.id == stripID })?.cardIDs ?? []
        }
    }

    static func cardID(in host: BWRSlotHost, at index: Int, document: BWRDocument) -> UUID? {
        let cardIDs = cardIDs(in: host, document: document)
        guard index >= 0, index < cardIDs.count else { return nil }
        return cardIDs[index]
    }

    static func indexOfCardInHost(cardID: UUID, document: BWRDocument) -> (host: BWRSlotHost, index: Int)? {
        for group in document.groups where !group.isArchived {
            if let index = group.memberCardIDs.firstIndex(of: cardID) {
                return (.group(group.id), index)
            }
        }
        for strip in document.parkingStrips {
            if let index = strip.cardIDs.firstIndex(of: cardID) {
                return (.strip(strip.id), index)
            }
        }
        return nil
    }

    static func stableCardCompare(_ lhs: BWRCard, _ rhs: BWRCard) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        if lhs.stableSortKey != rhs.stableSortKey { return lhs.stableSortKey < rhs.stableSortKey }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

nonisolated enum BWRSelectionPrecedenceResolver {
    private static let stripViewportBandHeight = 190.0

    static func targetForCreateCard(
        document: BWRDocument,
        selectedCardID: UUID?,
        selectedGroupID: UUID?,
        viewportState: BWRViewportState
    ) -> BWRSelectionPlacementTarget? {
        if let selectedCardID,
           let resolved = targetAfterSelectedCard(document: document, selectedCardID: selectedCardID) {
            return resolved
        }

        if let selectedGroupID,
           let group = document.groups.first(where: { $0.id == selectedGroupID && !$0.isArchived }) {
            return BWRSelectionPlacementTarget(
                host: .group(group.id),
                insertionIndex: group.memberCardIDs.count
            )
        }

        if let strip = primaryParkingStrip(document: document, viewportState: viewportState) {
            return BWRSelectionPlacementTarget(
                host: .strip(strip.id),
                insertionIndex: strip.cardIDs.count
            )
        }

        return nil
    }

    static func primaryParkingStrip(document: BWRDocument, viewportState: BWRViewportState) -> BWRParkingStrip? {
        let strips = BWRSlotOrder.orderedLiveStrips(in: document)
        guard !strips.isEmpty else { return nil }

        let viewportCenterY = viewportState.scrollOrigin.y + (viewportState.viewportSize.height * 0.5)
        let viewportBandRow = Int((viewportCenterY / stripViewportBandHeight).rounded(.down))

        return strips.min { lhs, rhs in
            let left = stripRanking(strip: lhs, viewportBandRow: viewportBandRow)
            let right = stripRanking(strip: rhs, viewportBandRow: viewportBandRow)
            if left.distance != right.distance { return left.distance < right.distance }
            if left.sameBand != right.sameBand { return left.sameBand && !right.sameBand }
            if left.anchorColumn != right.anchorColumn { return left.anchorColumn < right.anchorColumn }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func targetAfterSelectedCard(
        document: BWRDocument,
        selectedCardID: UUID
    ) -> BWRSelectionPlacementTarget? {
        guard let location = BWRSlotOrder.indexOfCardInHost(cardID: selectedCardID, document: document) else {
            return nil
        }
        return BWRSelectionPlacementTarget(
            host: location.host,
            insertionIndex: location.index + 1
        )
    }

    private static func stripRanking(strip: BWRParkingStrip, viewportBandRow: Int) -> (distance: Int, sameBand: Bool, anchorColumn: Int) {
        let distance = abs(strip.row - viewportBandRow)
        return (distance, strip.row == viewportBandRow, strip.anchorColumn)
    }
}

nonisolated enum BWRSlotPlacementNormalizer {
    enum Mode: Sendable {
        case runtimeRepair
        case strictLoad
    }

    static func repairedDocument(_ document: BWRDocument) -> BWRDocument {
        (try? normalize(document, mode: .runtimeRepair)) ?? document
    }

    static func validatedForLoad(_ document: BWRDocument) throws -> BWRDocument {
        try normalize(document, mode: .strictLoad)
    }

    private static func normalize(_ source: BWRDocument, mode: Mode) throws -> BWRDocument {
        var document = source
        document.schemaVersion = max(document.schemaVersion, 2)

        let liveCardIDs = Set(document.cards.filter { !$0.isArchived }.map(\.id))
        normalizeLiveGroups(document: &document, liveCardIDs: liveCardIDs)
        normalizeParkingStrips(document: &document, liveCardIDs: liveCardIDs)

        var hostRefs = hostReferences(document: document)
        try resolveHostConflicts(document: &document, hostRefs: &hostRefs, mode: mode)
        try injectUnhostedCards(document: &document, hostRefs: &hostRefs, liveCardIDs: liveCardIDs, mode: mode)

        normalizeLiveGroups(document: &document, liveCardIDs: liveCardIDs)
        normalizeParkingStrips(document: &document, liveCardIDs: liveCardIDs)
        document.cards = BWRCloneNormalizer.normalize(cards: document.cards)
        reassignPlacementsAndShadowLayouts(document: &document)
        return document
    }

    private static func normalizeLiveGroups(document: inout BWRDocument, liveCardIDs: Set<UUID>) {
        for index in document.groups.indices {
            if document.groups[index].originSlot == nil {
                document.groups[index].originSlot = fallbackOriginSlot(for: document.groups[index], document: document, fallbackIndex: index)
            }
            guard !document.groups[index].isArchived else { continue }
            document.groups[index].memberCardIDs = deduplicated(document.groups[index].memberCardIDs)
                .filter { liveCardIDs.contains($0) }
        }
    }

    private static func normalizeParkingStrips(document: inout BWRDocument, liveCardIDs: Set<UUID>) {
        for index in document.parkingStrips.indices {
            document.parkingStrips[index].cardIDs = deduplicated(document.parkingStrips[index].cardIDs)
                .filter { liveCardIDs.contains($0) }
        }
        document.parkingStrips.removeAll { $0.cardIDs.isEmpty }
        document.parkingStrips = BWRSlotOrder.orderedLiveStrips(in: document)
    }

    private static func resolveHostConflicts(
        document: inout BWRDocument,
        hostRefs: inout [UUID: [BWRSlotHost]],
        mode: Mode
    ) throws {
        for (cardID, refs) in hostRefs where refs.count > 1 {
            switch mode {
            case .strictLoad:
                throw BWRPackageStoreError.invalidPlacement(
                    cardID: cardID,
                    reason: "card belongs to multiple live hosts"
                )
            case .runtimeRepair:
                guard let preferredHost = preferredHost(for: cardID, refs: refs, document: document) else { continue }
                pruneHostReferences(
                    document: &document,
                    cardID: cardID,
                    keeping: preferredHost
                )
            }
        }
        hostRefs = hostReferences(document: document)
    }

    private static func injectUnhostedCards(
        document: inout BWRDocument,
        hostRefs: inout [UUID: [BWRSlotHost]],
        liveCardIDs: Set<UUID>,
        mode: Mode
    ) throws {
        for cardID in liveCardIDs where (hostRefs[cardID] ?? []).isEmpty {
            guard let card = document.cards.first(where: { $0.id == cardID }) else { continue }
            if let placement = card.placement {
                switch placement.kind {
                case .attached:
                    if let groupID = placement.hostGroupID,
                       let groupIndex = document.groups.firstIndex(where: { $0.id == groupID && !$0.isArchived }) {
                        insert(cardID: cardID, intoGroupAt: groupID, slotIndex: placement.slotIndex, document: &document)
                        document.groups[groupIndex].updatedAt = max(document.groups[groupIndex].updatedAt, card.updatedAt)
                        continue
                    }
                    if case .strictLoad = mode {
                        throw BWRPackageStoreError.invalidPlacement(
                            cardID: cardID,
                            reason: "attached card is missing a live host group"
                        )
                    }
                case .parked:
                    if let stripID = placement.stripID,
                       document.parkingStrips.contains(where: { $0.id == stripID }) {
                        insert(cardID: cardID, intoStripAt: stripID, slotIndex: placement.slotIndex, document: &document)
                        continue
                    }
                }
            }

            let stripID = ensureRecoveryStrip(document: &document)
            insert(cardID: cardID, intoStripAt: stripID, slotIndex: Int.max, document: &document)
        }
        hostRefs = hostReferences(document: document)
    }

    private static func reassignPlacementsAndShadowLayouts(document: inout BWRDocument) {
        let groupsByID = Dictionary(uniqueKeysWithValues: document.groups.map { ($0.id, $0) })
        let stripsByID = Dictionary(uniqueKeysWithValues: document.parkingStrips.map { ($0.id, $0) })

        for group in document.groups where !group.isArchived {
            for (slotIndex, cardID) in group.memberCardIDs.enumerated() {
                guard let cardIndex = document.cards.firstIndex(where: { $0.id == cardID }) else { continue }
                document.cards[cardIndex].placement = .attached(hostGroupID: group.id, slotIndex: slotIndex)
                document.cards[cardIndex].layout = BWRShadowPlacementTransition.shadowLayout(
                    for: document.cards[cardIndex].placement!,
                    cardStableSortKey: document.cards[cardIndex].stableSortKey,
                    groupsByID: groupsByID,
                    stripsByID: stripsByID
                )
            }
        }

        for strip in document.parkingStrips {
            for (slotIndex, cardID) in strip.cardIDs.enumerated() {
                guard let cardIndex = document.cards.firstIndex(where: { $0.id == cardID }) else { continue }
                document.cards[cardIndex].placement = .parked(stripID: strip.id, slotIndex: slotIndex)
                document.cards[cardIndex].layout = BWRShadowPlacementTransition.shadowLayout(
                    for: document.cards[cardIndex].placement!,
                    cardStableSortKey: document.cards[cardIndex].stableSortKey,
                    groupsByID: groupsByID,
                    stripsByID: stripsByID
                )
            }
        }
    }

    private static func preferredHost(for cardID: UUID, refs: [BWRSlotHost], document: BWRDocument) -> BWRSlotHost? {
        if let placement = document.cards.first(where: { $0.id == cardID })?.placement {
            switch placement.kind {
            case .attached:
                if let groupID = placement.hostGroupID,
                   refs.contains(.group(groupID)) {
                    return .group(groupID)
                }
            case .parked:
                if let stripID = placement.stripID,
                   refs.contains(.strip(stripID)) {
                    return .strip(stripID)
                }
            }
        }

        return refs.sorted { lhs, rhs in
            hostSortKey(lhs, document: document) < hostSortKey(rhs, document: document)
        }.first
    }

    private static func hostSortKey(_ host: BWRSlotHost, document: BWRDocument) -> String {
        switch host {
        case let .group(groupID):
            let group = document.groups.first(where: { $0.id == groupID })
            let origin = group?.originSlot ?? BWRSlotCoordinate(column: 0, row: 0)
            return String(format: "0-%08d-%08d-%@", origin.row, origin.column, groupID.uuidString)
        case let .strip(stripID):
            let strip = document.parkingStrips.first(where: { $0.id == stripID })
            return String(format: "1-%08d-%08d-%@", strip?.row ?? 0, strip?.anchorColumn ?? 0, stripID.uuidString)
        }
    }

    private static func hostReferences(document: BWRDocument) -> [UUID: [BWRSlotHost]] {
        var result: [UUID: [BWRSlotHost]] = [:]
        for group in document.groups where !group.isArchived {
            for cardID in group.memberCardIDs {
                result[cardID, default: []].append(.group(group.id))
            }
        }
        for strip in document.parkingStrips {
            for cardID in strip.cardIDs {
                result[cardID, default: []].append(.strip(strip.id))
            }
        }
        return result
    }

    private static func pruneHostReferences(
        document: inout BWRDocument,
        cardID: UUID,
        keeping preferredHost: BWRSlotHost
    ) {
        for index in document.groups.indices where !document.groups[index].isArchived {
            if case let .group(groupID) = preferredHost, document.groups[index].id == groupID {
                continue
            }
            document.groups[index].memberCardIDs.removeAll { $0 == cardID }
        }
        for index in document.parkingStrips.indices {
            if case let .strip(stripID) = preferredHost, document.parkingStrips[index].id == stripID {
                continue
            }
            document.parkingStrips[index].cardIDs.removeAll { $0 == cardID }
        }
    }

    private static func insert(cardID: UUID, intoGroupAt groupID: UUID, slotIndex: Int, document: inout BWRDocument) {
        guard let groupIndex = document.groups.firstIndex(where: { $0.id == groupID && !$0.isArchived }) else { return }
        document.groups[groupIndex].memberCardIDs.removeAll { $0 == cardID }
        let safeIndex = max(0, min(slotIndex, document.groups[groupIndex].memberCardIDs.count))
        document.groups[groupIndex].memberCardIDs.insert(cardID, at: safeIndex)
    }

    private static func insert(cardID: UUID, intoStripAt stripID: UUID, slotIndex: Int, document: inout BWRDocument) {
        guard let stripIndex = document.parkingStrips.firstIndex(where: { $0.id == stripID }) else { return }
        document.parkingStrips[stripIndex].cardIDs.removeAll { $0 == cardID }
        let safeIndex = max(0, min(slotIndex, document.parkingStrips[stripIndex].cardIDs.count))
        document.parkingStrips[stripIndex].cardIDs.insert(cardID, at: safeIndex)
    }

    static func ensureRecoveryStrip(document: inout BWRDocument) -> UUID {
        if let existing = BWRSelectionPrecedenceResolver.primaryParkingStrip(
            document: document,
            viewportState: BWRViewportState()
        ) {
            return existing.id
        }

        var occupancy = BWROccupancyMap()
        for group in BWRSlotOrder.orderedLiveGroups(in: document) {
            let footprint = BWRSlotBoardGeometry.footprint(
                slotCount: max(group.memberCardIDs.count, 1)
            )
            let origin = group.originSlot ?? BWRSlotCoordinate(column: 0, row: 0)
            let resolved = BWRSlotBoardGeometry.scanForFreeOrigin(
                start: origin,
                footprint: footprint,
                occupied: occupancy
            )
            occupancy.occupy(origin: resolved, footprint: footprint)
        }
        for strip in BWRSlotOrder.orderedLiveStrips(in: document) {
            let footprint = BWRSlotFootprint(columns: max(strip.cardIDs.count, 1), rows: 1)
            let resolved = BWRSlotBoardGeometry.resolveParkingStripOrigin(
                preferredRow: strip.row,
                anchorColumn: strip.anchorColumn,
                slotCount: max(strip.cardIDs.count, 1),
                occupied: occupancy
            )
            occupancy.occupy(origin: resolved, footprint: footprint)
        }

        let viewportBandRow = Int((BWRViewportState().scrollOrigin.y / BWRSlotBoardGeometry.default.slotHeight).rounded(.down))
        let preferredRow = max(viewportBandRow, document.parkingStrips.map(\.row).max() ?? -1)
        let resolvedOrigin = BWRSlotBoardGeometry.resolveParkingStripOrigin(
            preferredRow: preferredRow + 1,
            anchorColumn: 0,
            slotCount: 1,
            occupied: occupancy
        )
        let strip = BWRParkingStrip(
            row: resolvedOrigin.row,
            anchorColumn: resolvedOrigin.column,
            cardIDs: []
        )
        document.parkingStrips.append(strip)
        return strip.id
    }

    private static func fallbackOriginSlot(
        for group: BWRGroup,
        document: BWRDocument,
        fallbackIndex: Int
    ) -> BWRSlotCoordinate {
        let projection = BWRSlotBoardProjection.project(document: document)
        if let projected = projection.groupFrames.first(where: { $0.group.id == group.id }) {
            return projected.resolvedOriginSlot
        }

        return BWRSlotCoordinate(column: 0, row: fallbackIndex)
    }

    private static func deduplicated(_ values: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return values.filter { seen.insert($0).inserted }
    }
}

extension BWRCloneNormalizer {
    nonisolated static func familyLeader(in cards: [BWRCard], cloneGroupID: UUID) -> BWRCard? {
        cards
            .filter { $0.cloneGroupID == cloneGroupID && !$0.isArchived }
            .sorted(by: BWRSlotOrder.stableCardCompare)
            .first
    }

    nonisolated static func orderedIndices(
        in cards: [BWRCard],
        sourceCardID: UUID,
        cloneGroupID: UUID?
    ) -> [Int] {
        guard let cloneGroupID else {
            return cards.indices.filter { cards[$0].id == sourceCardID }
        }

        return cards.enumerated()
            .filter { $0.element.cloneGroupID == cloneGroupID }
            .sorted { lhs, rhs in
                BWRSlotOrder.stableCardCompare(lhs.element, rhs.element)
            }
            .map(\.offset)
    }
}
