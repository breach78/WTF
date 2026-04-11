import Foundation
import UniformTypeIdentifiers

enum BoardLineAxis {
    case row
    case column

    func coordinate(of slot: BoardSlot) -> Int {
        switch self {
        case .row:
            return slot.row
        case .column:
            return slot.column
        }
    }

    func offset(slot: BoardSlot, by delta: Int) -> BoardSlot {
        switch self {
        case .row:
            return slot.offsetBy(rows: delta)
        case .column:
            return slot.offsetBy(columns: delta)
        }
    }
}

enum BoardLineEditOperation {
    case insert
    case delete
}

struct BoardSearchResult: Equatable, Hashable {
    let cardID: UUID
    let layerID: UUID
    let range: NSRange
    let slot: BoardSlot
}

struct BoardTransientGestureState: Equatable {
    var hasDragSession = false
    var hasMarqueeSelection = false

    var hasActiveGesture: Bool {
        hasDragSession || hasMarqueeSelection
    }
}

enum BoardEscapeOutcome: Equatable {
    case none
    case cancelEditing
    case cancelTransientGesture
    case clearSelection
}

extension BoardProject {
    var hasDeletedCards: Bool {
        cards.contains(where: \.deleted)
    }

    var deletedCards: [BoardCardInstance] {
        cards
            .filter(\.deleted)
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func searchResults(for query: String) -> [BoardSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        var results: [BoardSearchResult] = []
        for card in liveCards.sorted(by: { $0.slot < $1.slot }) {
            guard let content = contents[card.contentID] else {
                continue
            }

            for layer in content.layers.sorted(by: { $0.index < $1.index }) {
                for range in layer.markdown.matchRanges(for: trimmed) {
                    results.append(
                        BoardSearchResult(
                            cardID: card.id,
                            layerID: layer.id,
                            range: range,
                            slot: card.slot
                        )
                    )
                }
            }
        }

        return results
    }

    mutating func setPresentedLayer(cardID: UUID, layerID: UUID) -> Bool {
        guard let cardIndex = cards.firstIndex(where: { $0.id == cardID && !$0.deleted }) else {
            return false
        }
        let contentID = cards[cardIndex].contentID
        guard let content = contents[contentID], content.layers.contains(where: { $0.id == layerID }) else {
            return false
        }
        guard cards[cardIndex].presentedLayerID != layerID else {
            return true
        }

        cards[cardIndex].presentedLayerID = layerID
        cards[cardIndex].touch()
        return true
    }

    mutating func softDeleteCards(ids: Set<UUID>) -> Set<UUID> {
        guard !ids.isEmpty else {
            return []
        }

        let timestamp = BWRTimestamp.now()
        var deletedIDs: Set<UUID> = []
        for index in cards.indices {
            guard ids.contains(cards[index].id), cards[index].deleted == false else {
                continue
            }

            cards[index].deleted = true
            cards[index].touch(at: timestamp)
            deletedIDs.insert(cards[index].id)
        }

        sortCards()
        return deletedIDs
    }

    @discardableResult
    mutating func restoreCard(id: UUID) -> (cardID: UUID, slot: BoardSlot)? {
        guard let index = cards.firstIndex(where: { $0.id == id && $0.deleted }) else {
            return nil
        }

        let restoredID = cards[index].id
        let originalSlot = cards[index].slot
        let destination: BoardSlot
        if liveCards.contains(where: { $0.slot == originalSlot }) {
            destination = firstAvailableSlot(preferred: originalSlot) ?? originalSlot
        } else {
            destination = originalSlot
        }

        cards[index].slot = destination
        cards[index].deleted = false
        cards[index].touch()
        sortCards()
        return (restoredID, destination)
    }

    @discardableResult
    mutating func restoreLatestDeletedCard() -> (cardID: UUID, slot: BoardSlot)? {
        guard let latestDeleted = deletedCards.first else {
            return nil
        }

        return restoreCard(id: latestDeleted.id)
    }

    mutating func applyLineEdit(axis: BoardLineAxis, operation: BoardLineEditOperation, at index: Int) -> Set<UUID> {
        let timestamp = BWRTimestamp.now()
        var deletedIDs: Set<UUID> = []

        for cardIndex in cards.indices {
            guard cards[cardIndex].deleted == false else {
                continue
            }

            let coordinate = axis.coordinate(of: cards[cardIndex].slot)
            switch operation {
            case .insert:
                guard coordinate >= index else {
                    continue
                }
                cards[cardIndex].slot = axis.offset(slot: cards[cardIndex].slot, by: 1)
                cards[cardIndex].touch(at: timestamp)
            case .delete:
                if coordinate == index {
                    cards[cardIndex].deleted = true
                    cards[cardIndex].touch(at: timestamp)
                    deletedIDs.insert(cards[cardIndex].id)
                } else if coordinate > index {
                    cards[cardIndex].slot = axis.offset(slot: cards[cardIndex].slot, by: -1)
                    cards[cardIndex].touch(at: timestamp)
                }
            }
        }

        sortCards()
        return deletedIDs
    }

    func presentedAsset(for cardID: UUID) -> BoardAsset? {
        guard let card = presentedCard(id: cardID), let assetID = card.presentedLayer.assetID else {
            return nil
        }
        return assets[assetID]
    }

    func presentedAsset(for card: BoardPresentedCard) -> BoardAsset? {
        guard let assetID = card.presentedLayer.assetID else {
            return nil
        }
        return assets[assetID]
    }

    @discardableResult
    mutating func attachAsset(
        data: Data,
        originalFilename: String?,
        contentType: String?,
        toPresentedLayerOf cardID: UUID
    ) -> UUID? {
        guard let cardIndex = cards.firstIndex(where: { $0.id == cardID && !$0.deleted }) else {
            return nil
        }
        let contentID = cards[cardIndex].contentID
        let layerID = cards[cardIndex].presentedLayerID
        guard var content = contents[contentID],
              let layerIndex = content.layers.firstIndex(where: { $0.id == layerID }) else {
            return nil
        }

        let now = BWRTimestamp.now()
        let existingAssetID = content.layers[layerIndex].assetID
        let assetID = existingAssetID ?? UUID()
        let createdAt = assets[assetID]?.createdAt ?? now
        let storedFilename = BoardAssetStorage.storedFilename(
            assetID: assetID,
            originalFilename: originalFilename,
            contentType: contentType
        )

        assets[assetID] = BoardAsset(
            id: assetID,
            storedFilename: storedFilename,
            originalFilename: originalFilename,
            contentType: contentType,
            data: data,
            createdAt: createdAt,
            updatedAt: now
        )
        content.layers[layerIndex].assetID = assetID
        content.layers[layerIndex].updatedAt = now
        content.updatedAt = now
        contents[contentID] = content
        cards[cardIndex].touch(at: now)
        return assetID
    }

    mutating func removeAsset(fromPresentedLayerOf cardID: UUID) {
        guard let cardIndex = cards.firstIndex(where: { $0.id == cardID && !$0.deleted }) else {
            return
        }
        let contentID = cards[cardIndex].contentID
        let layerID = cards[cardIndex].presentedLayerID
        guard var content = contents[contentID],
              let layerIndex = content.layers.firstIndex(where: { $0.id == layerID }),
              let removedAssetID = content.layers[layerIndex].assetID else {
            return
        }

        let now = BWRTimestamp.now()
        content.layers[layerIndex].assetID = nil
        content.layers[layerIndex].updatedAt = now
        content.updatedAt = now
        contents[contentID] = content
        cards[cardIndex].touch(at: now)

        let assetStillReferenced = contents.values.contains { value in
            value.layers.contains { $0.assetID == removedAssetID }
        }
        if !assetStillReferenced {
            assets.removeValue(forKey: removedAssetID)
        }
    }
}

extension BoardInteractionState {
    mutating func remapSlots(
        for axis: BoardLineAxis,
        operation: BoardLineEditOperation,
        at index: Int
    ) {
        keyboardCursorSlot = keyboardCursorSlot.map { $0.remapped(for: axis, operation: operation, at: index) }
        hoverSlot = hoverSlot.map { $0.remapped(for: axis, operation: operation, at: index) }
        selectionAnchorSlot = selectionAnchorSlot.map { $0.remapped(for: axis, operation: operation, at: index) }

        if case .slots(let slots) = selection {
            selection = .slots(
                Set(slots.map { $0.remapped(for: axis, operation: operation, at: index) })
            )
        }
    }
}

extension BoardSlot {
    func remapped(
        for axis: BoardLineAxis,
        operation: BoardLineEditOperation,
        at index: Int
    ) -> BoardSlot {
        let coordinate = axis.coordinate(of: self)
        switch operation {
        case .insert:
            guard coordinate >= index else {
                return self
            }
            return axis.offset(slot: self, by: 1)
        case .delete:
            guard coordinate > index else {
                return self
            }
            return axis.offset(slot: self, by: -1)
        }
    }
}

enum BoardGoToController {
    @discardableResult
    static func apply(
        result: BoardSearchResult,
        project: inout BoardProject,
        interaction: inout BoardInteractionState
    ) -> Bool {
        guard let slot = project.presentedCard(id: result.cardID)?.slot else {
            return false
        }

        _ = project.setPresentedLayer(cardID: result.cardID, layerID: result.layerID)
        interaction.selectCard(result.cardID, at: slot)
        interaction.keyboardCursorSlot = slot
        interaction.hoverSlot = nil
        interaction.editingCardID = nil
        return true
    }
}

enum BoardDeleteController {
    static func targetCardIDs(
        project: BoardProject,
        interaction: BoardInteractionState
    ) -> Set<UUID> {
        if !interaction.selectedCardIDs.isEmpty {
            return interaction.selectedCardIDs
        }

        if !interaction.selectedEmptySlots.isEmpty {
            return []
        }

        guard
            let cursorSlot = interaction.keyboardCursorSlot,
            let card = project.card(at: cursorSlot)
        else {
            return []
        }

        return [card.id]
    }
}

enum BoardSearchNavigator {
    static func normalizedIndex(_ index: Int?, count: Int) -> Int? {
        guard count > 0 else {
            return nil
        }

        let rawIndex = index ?? 0
        return ((rawIndex % count) + count) % count
    }

    static func advancedIndex(
        current: Int?,
        count: Int,
        reverse: Bool
    ) -> Int? {
        guard let current = normalizedIndex(current, count: count) else {
            return nil
        }

        if reverse {
            return (current + count - 1) % count
        }

        return (current + 1) % count
    }
}

enum BoardEscapeController {
    static func outcome(
        interaction: BoardInteractionState,
        transientGestureState: BoardTransientGestureState
    ) -> BoardEscapeOutcome {
        if interaction.editingCardID != nil {
            return .cancelEditing
        }

        if transientGestureState.hasActiveGesture {
            return .cancelTransientGesture
        }

        if interaction.selection != .none {
            return .clearSelection
        }

        return .none
    }
}

enum BoardStructureSelectionController {
    static func normalize(
        project: BoardProject,
        interaction: inout BoardInteractionState,
        deletedCardIDs: Set<UUID>,
        fallbackSlot: BoardSlot
    ) {
        let survivingSelectedIDs = interaction.selectedCardIDs.subtracting(deletedCardIDs)
        if let editingCardID = interaction.editingCardID, deletedCardIDs.contains(editingCardID) {
            interaction.editingCardID = nil
        }

        if !survivingSelectedIDs.isEmpty {
            let anchorSlot = interaction.selectionAnchorSlot.flatMap { anchor in
                if let card = project.card(at: anchor), survivingSelectedIDs.contains(card.id) {
                    return anchor
                }
                return nil
            } ?? project.sortedCardIDs(survivingSelectedIDs).first.flatMap { id in
                project.presentedCard(id: id)?.slot
            }
            interaction.selectCards(survivingSelectedIDs, anchorSlot: anchorSlot)
            return
        }

        let selectedSlots = interaction.selectedEmptySlots
        if !selectedSlots.isEmpty {
            let emptySlots = Set(selectedSlots.filter { project.card(at: $0) == nil })
            let occupiedCardIDs = Set(selectedSlots.compactMap { project.card(at: $0)?.id })
            if !occupiedCardIDs.isEmpty && !emptySlots.isEmpty {
                if let anchor = interaction.selectionAnchorSlot {
                    if emptySlots.contains(anchor) {
                        interaction.selectEmptySlots(emptySlots, anchorSlot: anchor)
                        return
                    }

                    if let card = project.card(at: anchor), occupiedCardIDs.contains(card.id) {
                        interaction.selectCards(occupiedCardIDs, anchorSlot: anchor)
                        return
                    }
                }
            }

            if !occupiedCardIDs.isEmpty {
                let anchorSlot = interaction.selectionAnchorSlot.flatMap { anchor in
                    if let card = project.card(at: anchor), occupiedCardIDs.contains(card.id) {
                        return anchor
                    }
                    return nil
                } ?? project.sortedCardIDs(occupiedCardIDs).first.flatMap { id in
                    project.presentedCard(id: id)?.slot
                }
                interaction.selectCards(occupiedCardIDs, anchorSlot: anchorSlot)
                return
            }

            if !emptySlots.isEmpty {
                let anchorSlot = interaction.selectionAnchorSlot.flatMap { anchor in
                    emptySlots.contains(anchor) ? anchor : nil
                } ?? emptySlots.sorted().first
                interaction.selectEmptySlots(emptySlots, anchorSlot: anchorSlot)
                return
            }
        }

        let emptyFallbackSlot = project.firstAvailableSlot(preferred: fallbackSlot) ?? fallbackSlot
        interaction.selectEmptySlot(emptyFallbackSlot)
        interaction.keyboardCursorSlot = interaction.keyboardCursorSlot ?? emptyFallbackSlot
    }
}

private enum BoardAssetStorage {
    static func storedFilename(
        assetID: UUID,
        originalFilename: String?,
        contentType: String?
    ) -> String {
        let pathExtension = originalFilename
            .flatMap { filename in
                let ext = URL(fileURLWithPath: filename).pathExtension
                return ext.isEmpty ? nil : ext.lowercased()
            }
            ?? contentType.flatMap { UTType(mimeType: $0)?.preferredFilenameExtension }
            ?? "bin"

        return "\(assetID.uuidString.lowercased()).\(pathExtension)"
    }
}

private extension String {
    func matchRanges(for query: String) -> [NSRange] {
        let source = self as NSString
        var results: [NSRange] = []
        var searchRange = NSRange(location: 0, length: source.length)

        while searchRange.length > 0 {
            let match = source.range(
                of: query,
                options: [.caseInsensitive],
                range: searchRange
            )
            guard match.location != NSNotFound else {
                break
            }

            results.append(match)
            let nextLocation = match.location + max(match.length, 1)
            guard nextLocation <= source.length else {
                break
            }
            searchRange = NSRange(location: nextLocation, length: source.length - nextLocation)
        }

        return results
    }
}
