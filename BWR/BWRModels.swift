import Foundation
import SwiftUI

enum BWRTimestamp {
    static func now() -> Date {
        normalized(Date())
    }

    static func normalized(_ date: Date) -> Date {
        let milliseconds = (date.timeIntervalSince1970 * 1_000).rounded()
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }
}

struct BoardContainerMetadata: Hashable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.createdAt = BWRTimestamp.normalized(createdAt)
        self.updatedAt = BWRTimestamp.normalized(updatedAt)
    }
}

struct BoardProject: Equatable {
    var canvas: BoardCanvas
    var cards: [BoardCardInstance]
    var contents: [UUID: BoardCardContent]
    var assets: [UUID: BoardAsset]

    init(
        canvas: BoardCanvas = .default,
        cards: [BoardCardInstance] = [],
        contents: [UUID: BoardCardContent] = [:],
        assets: [UUID: BoardAsset] = [:]
    ) {
        self.canvas = canvas
        self.contents = contents
        self.assets = assets
        self.cards = cards
            .map { card in
                guard let content = contents[card.contentID], let layer = content.presentedLayer(preferredID: card.presentedLayerID) else {
                    return card
                }
                var repaired = card
                repaired.presentedLayerID = layer.id
                return repaired
            }
            .sorted { $0.slot < $1.slot }
    }

    var liveCards: [BoardCardInstance] {
        cards.filter { !$0.deleted }.sorted { $0.slot < $1.slot }
    }

    var presentedCards: [BoardPresentedCard] {
        liveCards.compactMap(presentedCard(for:))
    }

    func card(at slot: BoardSlot) -> BoardPresentedCard? {
        presentedCards.first { $0.slot == slot }
    }

    func presentedCard(id: UUID?) -> BoardPresentedCard? {
        guard let id, let instance = liveCards.first(where: { $0.id == id }) else {
            return nil
        }
        return presentedCard(for: instance)
    }

    func presentedMarkdown(for cardID: UUID) -> String? {
        presentedCard(id: cardID)?.markdown
    }

    func visibleBounds(including extraSlots: Set<BoardSlot> = []) -> BoardVisibleBounds {
        canvas.visibleBounds(
            for: Set(liveCards.map(\.slot)),
            including: extraSlots
        )
    }

    func firstAvailableSlot(preferred: BoardSlot? = nil) -> BoardSlot? {
        let occupied = Set(liveCards.map(\.slot))
        if occupied.isEmpty {
            return preferred ?? .origin
        }

        if let preferred, !occupied.contains(preferred) {
            return preferred
        }

        let anchorSlots = Set(liveCards.map(\.slot)).union(preferred.map { [$0] } ?? [])
        for expansion in 0...24 {
            let bounds = canvas.visibleBounds(
                for: anchorSlots,
                extraPadding: expansion
            )
            if let candidate = bounds.orderedSlots(startingAt: preferred).first(where: { !occupied.contains($0) }) {
                return candidate
            }
        }

        return preferred ?? .origin
    }

    func matchingCardIDs(for query: String) -> Set<UUID> {
        Set(searchResults(for: query).map(\.cardID))
    }

    mutating func insertCard(at preferred: BoardSlot?) -> UUID? {
        guard let slot = firstAvailableSlot(preferred: preferred) else {
            return nil
        }

        let now = BWRTimestamp.now()
        let content = BoardCardContent.singleLayer(
            markdown: "## New card\nWrite in markdown right on the board.",
            createdAt: now,
            updatedAt: now
        )
        let card = BoardCardInstance(
            contentID: content.id,
            slot: slot,
            presentedLayerID: content.layers[0].id,
            palette: .paper,
            createdAt: now,
            updatedAt: now
        )

        contents[content.id] = content
        cards.append(card)
        cards.sort { $0.slot < $1.slot }
        return card.id
    }

    mutating func moveCard(id: UUID, to destination: BoardSlot) {
        guard let sourceIndex = cards.firstIndex(where: { $0.id == id && !$0.deleted }) else {
            return
        }

        if cards[sourceIndex].slot == destination {
            return
        }

        let now = BWRTimestamp.now()
        if let destinationIndex = cards.firstIndex(where: { $0.slot == destination && !$0.deleted }) {
            let sourceSlot = cards[sourceIndex].slot
            cards[destinationIndex].slot = sourceSlot
            cards[destinationIndex].touch(at: now)
        }

        cards[sourceIndex].slot = destination
        cards[sourceIndex].touch(at: now)
        sortCards()
    }

    mutating func updatePresentedMarkdown(id: UUID, markdown: String) {
        guard let sourceIndex = cards.firstIndex(where: { $0.id == id && !$0.deleted }) else {
            return
        }
        let contentID = cards[sourceIndex].contentID
        let layerID = cards[sourceIndex].presentedLayerID
        guard var content = contents[contentID],
              let layerIndex = content.layers.firstIndex(where: { $0.id == layerID }) else {
            return
        }

        let now = BWRTimestamp.now()
        content.layers[layerIndex].markdown = markdown
        content.layers[layerIndex].updatedAt = now
        content.updatedAt = now
        contents[contentID] = content
        cards[sourceIndex].touch(at: now)
    }

    mutating func setPalette(id: UUID, palette: CardPalette?) {
        guard let index = cards.firstIndex(where: { $0.id == id && !$0.deleted }) else {
            return
        }

        cards[index].palette = palette
        cards[index].touch()
    }

    mutating func cyclePalette(id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id && !$0.deleted }) else {
            return
        }

        let currentPalette = presentedCard(id: id)?.palette ?? .paper
        cards[index].palette = currentPalette.next
        cards[index].touch()
    }

    mutating func deleteCard(id: UUID) {
        guard let card = cards.first(where: { $0.id == id }) else {
            return
        }

        cards.removeAll { $0.id == id }
        if !cards.contains(where: { $0.contentID == card.contentID }) {
            contents.removeValue(forKey: card.contentID)
        }
    }

    mutating func setCardSlot(id: UUID, to destination: BoardSlot, timestamp: Date = BWRTimestamp.now()) {
        guard let index = cards.firstIndex(where: { $0.id == id && !$0.deleted }) else {
            return
        }

        cards[index].slot = destination
        cards[index].touch(at: timestamp)
    }

    mutating func sortCards() {
        cards.sort { $0.slot < $1.slot }
    }

    private func presentedCard(for instance: BoardCardInstance) -> BoardPresentedCard? {
        guard let content = contents[instance.contentID],
              let layer = content.presentedLayer(preferredID: instance.presentedLayerID) else {
            return nil
        }

        return BoardPresentedCard(instance: instance, presentedLayer: layer)
    }

    static func singleLayer(
        canvas: BoardCanvas = .default,
        seeds: [BoardSingleLayerSeed]
    ) -> BoardProject {
        var cards: [BoardCardInstance] = []
        var contents: [UUID: BoardCardContent] = [:]

        for seed in seeds {
            let layer = BoardLayer(
                id: seed.layerID,
                index: 0,
                createdAt: seed.createdAt,
                markdown: seed.markdown,
                palette: nil,
                assetID: nil,
                updatedAt: seed.updatedAt
            )
            let content = BoardCardContent(
                id: seed.contentID,
                createdAt: seed.createdAt,
                layers: [layer],
                updatedAt: seed.updatedAt
            )
            let card = BoardCardInstance(
                id: seed.cardID,
                contentID: content.id,
                slot: seed.slot,
                presentedLayerID: layer.id,
                palette: seed.palette,
                deleted: false,
                createdAt: seed.createdAt,
                updatedAt: seed.updatedAt
            )
            cards.append(card)
            contents[content.id] = content
        }

        return BoardProject(
            canvas: canvas,
            cards: cards,
            contents: contents
        )
    }

    static let sample = BoardProject.singleLayer(
        seeds: [
            .init(slot: .init(row: 0, column: 2), markdown: "An opening image with breath and distance."),
            .init(slot: .init(row: 0, column: 3), markdown: "A private rule is introduced.\n\nThe board should feel orderly, almost too calm."),
            .init(slot: .init(row: 0, column: 4), markdown: "## Promise\nThe hidden grid keeps every move intentional."),
            .init(slot: .init(row: 0, column: 5), markdown: "A memory lands, and the room suddenly has stakes."),
            .init(slot: .init(row: 0, column: 6), markdown: "The first turn should feel inevitable once seen."),
            .init(slot: .init(row: 1, column: 1), markdown: "A side thread brushes the main thread."),
            .init(slot: .init(row: 1, column: 2), markdown: "This beat exists only to create pressure later."),
            .init(slot: .init(row: 1, column: 8), markdown: "A reveal waits here."),
            .init(slot: .init(row: 2, column: 0), markdown: "A small joke resets the rhythm."),
            .init(slot: .init(row: 2, column: 2), markdown: "Everything looks stable, but the frame is already tilting."),
            .init(slot: .init(row: 2, column: 5), markdown: "### Pivot\nThe center card becomes the hinge."),
            .init(slot: .init(row: 2, column: 6), markdown: "Consequences ripple outward one slot at a time."),
            .init(slot: .init(row: 3, column: 0), markdown: "The next decision appears simple but costs something real."),
            .init(slot: .init(row: 3, column: 2), markdown: "If this card moves, the whole sequence changes meaning."),
            .init(slot: .init(row: 3, column: 3), markdown: "A reaction shot lives here.\n\nKeep it shorter than expected."),
            .init(slot: .init(row: 3, column: 6), markdown: "A quiet answer lands after the pivot."),
            .init(slot: .init(row: 4, column: 3), markdown: "## Heat\nThe emotional center sits lower than the structural center.", palette: .blush),
            .init(slot: .init(row: 4, column: 4), markdown: "A short note that only matters because of placement."),
            .init(slot: .init(row: 5, column: 1), markdown: "Momentum returns once the board reads left to right again."),
            .init(slot: .init(row: 5, column: 4), markdown: "A withheld detail becomes visible when grouped here."),
            .init(slot: .init(row: 5, column: 5), markdown: "A hard cut belongs under the pink note, not beside it."),
            .init(slot: .init(row: 6, column: 1), markdown: "The final movement should feel lighter, not louder.")
        ]
    )
}

struct BoardSingleLayerSeed {
    var cardID: UUID
    var contentID: UUID
    var layerID: UUID
    var slot: BoardSlot
    var markdown: String
    var palette: CardPalette
    var createdAt: Date
    var updatedAt: Date

    init(
        cardID: UUID = UUID(),
        contentID: UUID = UUID(),
        layerID: UUID = UUID(),
        slot: BoardSlot,
        markdown: String,
        palette: CardPalette = .paper,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.cardID = cardID
        self.contentID = contentID
        self.layerID = layerID
        self.slot = slot
        self.markdown = markdown
        self.palette = palette
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct BoardCardInstance: Identifiable, Equatable, Hashable {
    var id: UUID
    var contentID: UUID
    var slot: BoardSlot
    var presentedLayerID: UUID
    var palette: CardPalette?
    var deleted: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        contentID: UUID,
        slot: BoardSlot,
        presentedLayerID: UUID,
        palette: CardPalette? = nil,
        deleted: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.contentID = contentID
        self.slot = slot
        self.presentedLayerID = presentedLayerID
        self.palette = palette
        self.deleted = deleted
        self.createdAt = BWRTimestamp.normalized(createdAt)
        self.updatedAt = BWRTimestamp.normalized(updatedAt)
    }

    var resolvedPalette: CardPalette {
        palette ?? .paper
    }

    mutating func touch(at date: Date = BWRTimestamp.now()) {
        updatedAt = BWRTimestamp.normalized(date)
    }
}

struct BoardCardContent: Identifiable, Equatable, Hashable {
    var id: UUID
    var createdAt: Date
    var layers: [BoardLayer]
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        layers: [BoardLayer],
        updatedAt: Date = .now
    ) {
        self.id = id
        self.createdAt = BWRTimestamp.normalized(createdAt)
        self.layers = layers.sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        self.updatedAt = BWRTimestamp.normalized(updatedAt)
    }

    static func singleLayer(
        id: UUID = UUID(),
        layerID: UUID = UUID(),
        markdown: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) -> BoardCardContent {
        BoardCardContent(
            id: id,
            createdAt: createdAt,
            layers: [
                BoardLayer(
                    id: layerID,
                    index: 0,
                    createdAt: createdAt,
                    markdown: markdown,
                    updatedAt: updatedAt
                )
            ],
            updatedAt: updatedAt
        )
    }

    func layer(id: UUID) -> BoardLayer? {
        layers.first { $0.id == id }
    }

    func presentedLayer(preferredID: UUID) -> BoardLayer? {
        layer(id: preferredID) ?? layers.first
    }
}

struct BoardLayer: Identifiable, Equatable, Hashable {
    var id: UUID
    var index: Int
    var createdAt: Date
    var markdown: String
    var palette: CardPalette?
    var assetID: UUID?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        index: Int,
        createdAt: Date = .now,
        markdown: String,
        palette: CardPalette? = nil,
        assetID: UUID? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.index = index
        self.createdAt = BWRTimestamp.normalized(createdAt)
        self.markdown = markdown
        self.palette = palette
        self.assetID = assetID
        self.updatedAt = BWRTimestamp.normalized(updatedAt)
    }
}

struct BoardAsset: Identifiable, Equatable, Hashable {
    var id: UUID
    var storedFilename: String
    var originalFilename: String?
    var contentType: String?
    var data: Data
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        storedFilename: String,
        originalFilename: String? = nil,
        contentType: String? = nil,
        data: Data = Data(),
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.storedFilename = storedFilename
        self.originalFilename = originalFilename
        self.contentType = contentType
        self.data = data
        self.createdAt = BWRTimestamp.normalized(createdAt)
        self.updatedAt = BWRTimestamp.normalized(updatedAt)
    }
}

struct BoardPresentedCard: Identifiable, Equatable, Hashable {
    let instance: BoardCardInstance
    let presentedLayer: BoardLayer

    var id: UUID { instance.id }
    var slot: BoardSlot { instance.slot }
    var palette: CardPalette { instance.palette ?? presentedLayer.palette ?? .paper }
    var markdown: String { presentedLayer.markdown }
    var digest: MarkdownDigest { MarkdownDigest(markdown: markdown) }
}

struct BoardCanvas: Hashable {
    var viewportPadding: Int
    var minimumColumns: Int
    var minimumRows: Int

    static let `default` = BoardCanvas()

    init(
        viewportPadding: Int = 1,
        minimumColumns: Int = 3,
        minimumRows: Int = 3
    ) {
        self.viewportPadding = viewportPadding
        self.minimumColumns = minimumColumns
        self.minimumRows = minimumRows
    }

    func visibleBounds(
        for occupiedSlots: Set<BoardSlot>,
        including extraSlots: Set<BoardSlot> = [],
        extraPadding: Int = 0
    ) -> BoardVisibleBounds {
        BoardVisibleBounds(
            slots: occupiedSlots.union(extraSlots),
            padding: viewportPadding + extraPadding,
            minimumColumns: minimumColumns,
            minimumRows: minimumRows
        )
    }
}

struct BoardSlot: Hashable, Comparable, Identifiable {
    var row: Int
    var column: Int

    static let origin = BoardSlot(row: 0, column: 0)

    var id: String { "\(row)-\(column)" }

    func offsetBy(rows: Int = 0, columns: Int = 0) -> BoardSlot {
        BoardSlot(row: row + rows, column: column + columns)
    }

    static func < (lhs: BoardSlot, rhs: BoardSlot) -> Bool {
        if lhs.row == rhs.row {
            return lhs.column < rhs.column
        }
        return lhs.row < rhs.row
    }
}

enum CardPalette: String, CaseIterable, Identifiable {
    case paper
    case blush
    case butter
    case mist

    var id: String { rawValue }

    var next: CardPalette {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else {
            return .paper
        }
        return all[(index + 1) % all.count]
    }

    var fillHex: UInt32 {
        switch self {
        case .paper:
            return 0xFFFDFC
        case .blush:
            return 0xF2B6BA
        case .butter:
            return 0xF5E8B2
        case .mist:
            return 0xDDE7F7
        }
    }

    var fill: Color {
        Color(hex: fillHex)
    }

    var chipHex: UInt32 {
        switch self {
        case .paper:
            return 0xF0EAE1
        case .blush:
            return 0xE18A93
        case .butter:
            return 0xD9BC58
        case .mist:
            return 0x93ADDA
        }
    }

    var chip: Color {
        Color(hex: chipHex)
    }
}

struct MarkdownDigest: Hashable {
    let title: String
    let excerpt: String
    let searchBody: String

    init(markdown: String) {
        let clean = markdown
            .replacingOccurrences(of: "\\[[^\\]]+\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "[#>*_`-]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let pieces = clean
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let first = pieces.first {
            title = first
            excerpt = pieces.dropFirst().joined(separator: " ")
        } else {
            title = "Empty card"
            excerpt = "Double-click to write markdown."
        }

        searchBody = clean
    }
}
