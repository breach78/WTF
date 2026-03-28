import Foundation

final class HistorySnapshot: Identifiable {
    let id: UUID
    let timestamp: Date
    var name: String?
    let scenarioID: UUID
    var cardSnapshots: [CardSnapshot]
    var isDelta: Bool
    var deletedCardIDs: [UUID]
    var isPromoted: Bool
    var promotionReason: String?
    var noteCardID: UUID?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        name: String? = nil,
        scenarioID: UUID,
        cardSnapshots: [CardSnapshot] = [],
        isDelta: Bool = false,
        deletedCardIDs: [UUID] = [],
        isPromoted: Bool = false,
        promotionReason: String? = nil,
        noteCardID: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.name = name
        self.scenarioID = scenarioID
        self.cardSnapshots = cardSnapshots
        self.isDelta = isDelta
        self.deletedCardIDs = deletedCardIDs
        self.isPromoted = isPromoted
        self.promotionReason = promotionReason
        self.noteCardID = noteCardID
    }
}

struct CardSnapshot: Codable, Equatable {
    let cardID: UUID
    let content: String
    let orderIndex: Int
    let parentID: UUID?
    let category: String?
    let isFloating: Bool
    let isArchived: Bool
    let cloneGroupID: UUID?

    init(from card: SceneCard) {
        self.cardID = card.id
        self.content = card.content
        self.orderIndex = card.orderIndex
        self.parentID = card.parent?.id
        self.category = card.category
        self.isFloating = card.isFloating
        self.isArchived = card.isArchived
        self.cloneGroupID = card.cloneGroupID
    }
}

