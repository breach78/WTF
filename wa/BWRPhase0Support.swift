import Foundation

nonisolated enum BWRLayerKind: String, Codable, CaseIterable, Sendable {
    case body
    case treatment
    case scenario
}

nonisolated enum BWRCardPlacementKind: String, Codable, CaseIterable, Sendable {
    case attached
    case parked
}

nonisolated struct BWRSlotCoordinate: Codable, Equatable, Hashable, Sendable {
    var column: Int
    var row: Int

    init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }
}

nonisolated struct BWRCardPlacement: Codable, Equatable, Hashable, Sendable {
    var kind: BWRCardPlacementKind
    var hostGroupID: UUID?
    var stripID: UUID?
    var slotIndex: Int

    static func attached(hostGroupID: UUID, slotIndex: Int) -> BWRCardPlacement {
        BWRCardPlacement(kind: .attached, hostGroupID: hostGroupID, stripID: nil, slotIndex: slotIndex)
    }

    static func parked(stripID: UUID, slotIndex: Int) -> BWRCardPlacement {
        BWRCardPlacement(kind: .parked, hostGroupID: nil, stripID: stripID, slotIndex: slotIndex)
    }
}

nonisolated struct BWRPoint: Codable, Equatable, Hashable, Sendable {
    var x: Double
    var y: Double
}

nonisolated struct BWRSize: Codable, Equatable, Hashable, Sendable {
    var width: Double
    var height: Double
}

nonisolated struct BWRViewportState: Codable, Equatable, Hashable, Sendable {
    var zoomScale: Double
    var scrollOrigin: BWRPoint
    var viewportSize: BWRSize

    init(
        zoomScale: Double = 1.0,
        scrollOrigin: BWRPoint = BWRPoint(x: 0, y: 0),
        viewportSize: BWRSize = BWRSize(width: 0, height: 0)
    ) {
        self.zoomScale = zoomScale
        self.scrollOrigin = scrollOrigin
        self.viewportSize = viewportSize
    }
}

nonisolated struct BWRCardLayer: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var kind: BWRLayerKind
    var name: String
    var markdown: String
    var order: Int

    init(
        id: UUID = UUID(),
        kind: BWRLayerKind,
        name: String,
        markdown: String,
        order: Int
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.markdown = markdown
        self.order = order
    }
}

nonisolated struct BWRCard: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var stableSortKey: Int64
    var cloneGroupID: UUID?
    var colorHex: String?
    var currentLayerID: UUID
    var placement: BWRCardPlacement?
    var layout: BWRPoint
    var isArchived: Bool
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var layers: [BWRCardLayer]

    init(
        id: UUID = UUID(),
        stableSortKey: Int64,
        cloneGroupID: UUID? = nil,
        colorHex: String? = nil,
        currentLayerID: UUID,
        placement: BWRCardPlacement? = nil,
        layout: BWRPoint,
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        layers: [BWRCardLayer]
    ) {
        self.id = id
        self.stableSortKey = stableSortKey
        self.cloneGroupID = cloneGroupID
        self.colorHex = colorHex
        self.currentLayerID = currentLayerID
        self.placement = placement
        self.layout = layout
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.layers = layers.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    var currentLayer: BWRCardLayer? {
        layers.first(where: { $0.id == currentLayerID })
    }

    var titlePreview: String {
        let currentText = (currentLayer?.markdown ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = currentText.components(separatedBy: .newlines).first ?? ""
        if !firstLine.isEmpty { return firstLine }
        return "Untitled Card"
    }
}

nonisolated struct BWRGroup: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var originSlot: BWRSlotCoordinate?
    var memberCardIDs: [UUID]
    var isArchived: Bool
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        originSlot: BWRSlotCoordinate? = nil,
        memberCardIDs: [UUID],
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.originSlot = originSlot
        self.memberCardIDs = memberCardIDs
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct BWRParkingStrip: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var row: Int
    var anchorColumn: Int
    var cardIDs: [UUID]

    init(
        id: UUID = UUID(),
        row: Int,
        anchorColumn: Int,
        cardIDs: [UUID]
    ) {
        self.id = id
        self.row = row
        self.anchorColumn = anchorColumn
        self.cardIDs = cardIDs
    }
}

nonisolated struct BWRLink: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var sourceCardID: UUID
    var destinationCardID: UUID
    var isArchived: Bool
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        sourceCardID: UUID,
        destinationCardID: UUID,
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sourceCardID = sourceCardID
        self.destinationCardID = destinationCardID
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated enum BWRArchiveEntityKind: String, Codable, CaseIterable, Sendable {
    case card
    case group
    case link
}

nonisolated struct BWRArchiveEntry: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var entityID: UUID
    var entityKind: BWRArchiveEntityKind
    var title: String
    var searchBlob: String
    var colorHex: String?
    var archivedAt: Date

    init(
        id: UUID = UUID(),
        entityID: UUID,
        entityKind: BWRArchiveEntityKind,
        title: String,
        searchBlob: String,
        colorHex: String?,
        archivedAt: Date
    ) {
        self.id = id
        self.entityID = entityID
        self.entityKind = entityKind
        self.title = title
        self.searchBlob = searchBlob
        self.colorHex = colorHex
        self.archivedAt = archivedAt
    }
}

nonisolated struct BWRDocument: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var createdAt: Date
    var updatedAt: Date
    var nextStableSortKey: Int64
    var boardTheme: BWRBoardThemeState
    var cards: [BWRCard]
    var groups: [BWRGroup]
    var parkingStrips: [BWRParkingStrip]
    var links: [BWRLink]
    var archive: [BWRArchiveEntry]

    init(
        schemaVersion: Int = 2,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        nextStableSortKey: Int64 = 1,
        boardTheme: BWRBoardThemeState = .init(),
        cards: [BWRCard],
        groups: [BWRGroup] = [],
        parkingStrips: [BWRParkingStrip] = [],
        links: [BWRLink] = [],
        archive: [BWRArchiveEntry] = []
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.nextStableSortKey = nextStableSortKey
        self.boardTheme = boardTheme
        self.cards = cards
        self.groups = groups
        self.parkingStrips = parkingStrips
        self.links = links
        self.archive = archive.sorted { lhs, rhs in
            if lhs.archivedAt != rhs.archivedAt { return lhs.archivedAt > rhs.archivedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    mutating func allocateStableSortKey() -> Int64 {
        let allocated = nextStableSortKey
        nextStableSortKey += 1
        return allocated
    }

    var liveCards: [BWRCard] {
        cards.filter { !$0.isArchived }
    }

    var archivedCards: [BWRCard] {
        cards.filter(\.isArchived)
    }

    var liveGroups: [BWRGroup] {
        groups.filter { !$0.isArchived }
    }

    var archivedGroups: [BWRGroup] {
        groups.filter(\.isArchived)
    }

    static func blank() -> BWRDocument {
        let now = Date()
        let firstLayers = BWRCard.defaultLayers(bodyMarkdown: "", bodyCount: 1)
        let firstCard = BWRCard(
            stableSortKey: 1,
            colorHex: "F8FAFC",
            currentLayerID: firstLayers[0].id,
            layout: BWRPoint(x: 720, y: 420),
            createdAt: now,
            updatedAt: now,
            layers: firstLayers
        )
        return BWRDocument(
            schemaVersion: 2,
            createdAt: now,
            updatedAt: now,
            nextStableSortKey: 2,
            cards: [firstCard]
        )
    }
}

nonisolated extension BWRCard {
    static func defaultLayers(
        bodyMarkdown: String,
        bodyCount: Int = 1,
        treatmentMarkdown: String = "",
        scenarioMarkdown: String = ""
    ) -> [BWRCardLayer] {
        let resolvedBodyCount = max(1, bodyCount)
        var layers: [BWRCardLayer] = []
        for index in 0..<resolvedBodyCount {
            let markdown = index == 0 ? bodyMarkdown : ""
            layers.append(
                BWRCardLayer(
                    kind: .body,
                    name: BWRNaming.bodyLayerName(for: index),
                    markdown: markdown,
                    order: index
                )
            )
        }

        layers.append(
            BWRCardLayer(
                kind: .treatment,
                name: "Treatment",
                markdown: treatmentMarkdown,
                order: resolvedBodyCount
            )
        )
        layers.append(
            BWRCardLayer(
                kind: .scenario,
                name: "Scenario",
                markdown: scenarioMarkdown,
                order: resolvedBodyCount + 1
            )
        )
        return layers
    }
}

nonisolated enum BWRNaming {
    static func bodyLayerName(for index: Int) -> String {
        "Body \(index + 1)"
    }
}

nonisolated enum BWRRowMajorOrdering {
    static func sortedCards(_ cards: [BWRCard]) -> [BWRCard] {
        cards.sorted(by: compare)
    }

    static func compare(_ lhs: BWRCard, _ rhs: BWRCard) -> Bool {
        let leftY = quantized(lhs.layout.y)
        let rightY = quantized(rhs.layout.y)
        if leftY != rightY { return leftY < rightY }

        let leftX = quantized(lhs.layout.x)
        let rightX = quantized(rhs.layout.x)
        if leftX != rightX { return leftX < rightX }

        if lhs.stableSortKey != rhs.stableSortKey {
            return lhs.stableSortKey < rhs.stableSortKey
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func quantized(_ value: Double) -> Int {
        Int((value * 100.0).rounded())
    }
}

nonisolated enum BWRCloneNormalizer {
    static func normalize(
        cards: [BWRCard],
        inactiveCardIDs: Set<UUID> = []
    ) -> [BWRCard] {
        let activeCards = cards.filter { !$0.isArchived && !inactiveCardIDs.contains($0.id) }
        let grouped = Dictionary(grouping: activeCards.compactMap { card -> (UUID, UUID)? in
            guard let cloneGroupID = card.cloneGroupID else { return nil }
            return (cloneGroupID, card.id)
        }, by: \.0)

        let cloneGroupsToClear = Set(grouped.compactMap { groupID, members in
            members.count <= 1 ? groupID : nil
        })

        return cards.map { card in
            guard let cloneGroupID = card.cloneGroupID,
                  cloneGroupsToClear.contains(cloneGroupID) else {
                return card
            }

            var cleared = card
            cleared.cloneGroupID = nil
            return cleared
        }
    }
}

nonisolated struct BWRTextKeyModifiers: Codable, Equatable, Hashable, Sendable {
    var shift: Bool
    var command: Bool
    var option: Bool
    var control: Bool

    var hasSystemModifier: Bool {
        command || option || control
    }
}

nonisolated struct BWRTextKeyEvent: Codable, Equatable, Hashable, Sendable {
    var keyCode: UInt16
    var modifiers: BWRTextKeyModifiers
    var hasMarkedText: Bool
}

nonisolated enum BWRTextKeyCommandAction: String, Codable, Equatable, Sendable {
    case splitCard
    case insertNewline
    case passToSystem
}

nonisolated enum BWRTextKeyCommandRouter {
    private static let returnKeyCodes: Set<UInt16> = [36, 76]

    static func resolve(_ event: BWRTextKeyEvent) -> BWRTextKeyCommandAction {
        guard returnKeyCodes.contains(event.keyCode) else { return .passToSystem }
        guard !event.hasMarkedText else { return .passToSystem }
        guard !event.modifiers.hasSystemModifier else { return .passToSystem }
        return event.modifiers.shift ? .insertNewline : .splitCard
    }
}

nonisolated enum BWRPhase0SeedFactory {
    static func makeBoardSpikeCards(count: Int) -> [BWRCard] {
        let palette = ["E0F2FE", "DCFCE7", "FEF3C7", "FCE7F3", "EDE9FE", "F1F5F9"]
        let columns = 10
        let rowHeight = 150.0
        let columnWidth = 220.0

        return (0..<count).map { index in
            let layers = BWRCard.defaultLayers(
                bodyMarkdown: "Card \(index + 1)\n\nDrag me around the board spike.",
                treatmentMarkdown: "Treatment layer for card \(index + 1).",
                scenarioMarkdown: "Scenario layer for card \(index + 1)."
            )
            return BWRCard(
                stableSortKey: Int64(index + 1),
                colorHex: palette[index % palette.count],
                currentLayerID: layers[0].id,
                layout: BWRPoint(
                    x: Double(index % columns) * columnWidth,
                    y: Double(index / columns) * rowHeight
                ),
                createdAt: Date(timeIntervalSince1970: Double(index)),
                updatedAt: Date(timeIntervalSince1970: Double(index)),
                layers: layers
            )
        }
    }

    static func makeAutosaveDocument(cardCount: Int) -> BWRDocument {
        let cards = (0..<cardCount).map { index in
            let layers = BWRCard.defaultLayers(
                bodyMarkdown: """
                # Card \(index + 1)

                This is the body layer for card \(index + 1).
                It exists to stress the phase 0 package writer.
                """,
                treatmentMarkdown: """
                Treatment \(index + 1)

                The board groups will later stitch this layer into focus mode.
                """,
                scenarioMarkdown: """
                INT. TEST ROOM - DAY

                @WRITER
                We are only measuring save throughput here.
                """
            )
            return BWRCard(
                stableSortKey: Int64(index + 1),
                colorHex: index.isMultiple(of: 2) ? "E2E8F0" : "DBEAFE",
                currentLayerID: layers[0].id,
                layout: BWRPoint(x: Double(index % 12) * 180.0, y: Double(index / 12) * 140.0),
                createdAt: Date(timeIntervalSince1970: Double(index)),
                updatedAt: Date(timeIntervalSince1970: Double(index)),
                layers: layers
            )
        }

        return BWRDocument(
            schemaVersion: 1,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1),
            nextStableSortKey: Int64(cardCount + 1),
            cards: cards
        )
    }
}

nonisolated enum BWRShadowPlacementTransition {
    private static let slotWidth = 240.0
    private static let slotHeight = 190.0
    private static let recoveryStripAnchorColumn = 0

    static func preparedForPersistence(document: BWRDocument) -> BWRDocument {
        BWRSlotPlacementNormalizer.repairedDocument(document)
    }

    private static func derivedOriginSlot(
        group: BWRGroup,
        cardsByID: [UUID: BWRCard],
        fallbackIndex: Int
    ) -> BWRSlotCoordinate {
        let memberCards = group.memberCardIDs.compactMap { cardsByID[$0] }
        guard let anchorCard = BWRRowMajorOrdering.sortedCards(memberCards).first else {
            return BWRSlotCoordinate(column: 0, row: fallbackIndex)
        }
        return BWRSlotCoordinate(
            column: max(0, Int((anchorCard.layout.x / slotWidth).rounded(.down))),
            row: max(0, Int((anchorCard.layout.y / slotHeight).rounded(.down)))
        )
    }

    static func shadowLayout(
        for placement: BWRCardPlacement,
        cardStableSortKey: Int64,
        groupsByID: [UUID: BWRGroup],
        stripsByID: [UUID: BWRParkingStrip]
    ) -> BWRPoint {
        switch placement.kind {
        case .attached:
            let groupOrigin = groupsByID[placement.hostGroupID ?? UUID()]?.originSlot ?? BWRSlotCoordinate(column: 0, row: 0)
            return BWRPoint(
                x: Double(groupOrigin.column) * slotWidth + Double(placement.slotIndex) * slotWidth,
                y: Double(groupOrigin.row) * slotHeight
            )
        case .parked:
            let strip = stripsByID[placement.stripID ?? UUID()]
            return BWRPoint(
                x: Double(strip?.anchorColumn ?? recoveryStripAnchorColumn) * slotWidth + Double(placement.slotIndex) * slotWidth,
                y: Double(strip?.row ?? Int(cardStableSortKey)) * slotHeight
            )
        }
    }
}

nonisolated enum BWRPackageStoreError: LocalizedError {
    case unsupportedSchema(Int)
    case invalidPlacement(cardID: UUID, reason: String)
    case invalidGroup(groupID: UUID, reason: String)
    case invalidCurrentLayer(cardID: UUID, layerID: UUID)
    case corruptedPackage(reason: String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            return "Unsupported BWR schema version: \(version)"
        case let .invalidPlacement(cardID, reason):
            return "Invalid placement for card \(cardID.uuidString): \(reason)"
        case let .invalidGroup(groupID, reason):
            return "Invalid group \(groupID.uuidString): \(reason)"
        case let .invalidCurrentLayer(cardID, layerID):
            return "Card \(cardID.uuidString) points to missing current layer \(layerID.uuidString)"
        case let .corruptedPackage(reason):
            return "Corrupted .bwr package: \(reason)"
        }
    }
}

nonisolated enum BWRPackageStore {
    nonisolated struct SaveMetrics: Codable, Equatable, Sendable {
        var fullSaveMilliseconds: Double
        var deltaSaveMilliseconds: Double
    }

    private nonisolated struct ProjectManifest: Codable, Equatable, Sendable {
        var schemaVersion: Int
        var createdAt: Date
        var updatedAt: Date
        var nextStableSortKey: Int64
        var boardTheme: BWRBoardThemeState
        var cardIDs: [UUID]
        var groupIDs: [UUID]
        var parkingStripIDs: [UUID]
        var linkIDs: [UUID]

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case createdAt
            case updatedAt
            case nextStableSortKey
            case boardTheme
            case cardIDs
            case groupIDs
            case parkingStripIDs
            case linkIDs
        }

        init(
            schemaVersion: Int,
            createdAt: Date,
            updatedAt: Date,
            nextStableSortKey: Int64,
            boardTheme: BWRBoardThemeState = .init(),
            cardIDs: [UUID],
            groupIDs: [UUID],
            parkingStripIDs: [UUID],
            linkIDs: [UUID]
        ) {
            self.schemaVersion = schemaVersion
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.nextStableSortKey = nextStableSortKey
            self.boardTheme = boardTheme
            self.cardIDs = cardIDs
            self.groupIDs = groupIDs
            self.parkingStripIDs = parkingStripIDs
            self.linkIDs = linkIDs
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            createdAt = try container.decode(Date.self, forKey: .createdAt)
            updatedAt = try container.decode(Date.self, forKey: .updatedAt)
            nextStableSortKey = try container.decode(Int64.self, forKey: .nextStableSortKey)
            boardTheme = try container.decodeIfPresent(BWRBoardThemeState.self, forKey: .boardTheme) ?? .init()
            cardIDs = try container.decode([UUID].self, forKey: .cardIDs)
            groupIDs = try container.decode([UUID].self, forKey: .groupIDs)
            parkingStripIDs = try container.decode([UUID].self, forKey: .parkingStripIDs)
            linkIDs = try container.decode([UUID].self, forKey: .linkIDs)
        }
    }

    private nonisolated struct CardMetadata: Codable, Equatable, Sendable {
        nonisolated struct PlacementMetadata: Codable, Equatable, Sendable {
            var kind: BWRCardPlacementKind
            var hostGroupID: UUID?
            var stripID: UUID?
            var slotIndex: Int
        }

        nonisolated struct LayerMetadata: Codable, Equatable, Sendable {
            var id: UUID
            var kind: BWRLayerKind
            var name: String
            var order: Int
            var fileName: String
        }

        var id: UUID
        var stableSortKey: Int64
        var cloneGroupID: UUID?
        var colorHex: String?
        var currentLayerID: UUID
        var placement: PlacementMetadata?
        var layout: BWRPoint
        var isArchived: Bool
        var archivedAt: Date?
        var createdAt: Date
        var updatedAt: Date
        var layers: [LayerMetadata]
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func fullWrite(document: BWRDocument, to packageURL: URL) throws {
        let preparedDocument = BWRShadowPlacementTransition.preparedForPersistence(document: document)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: packageURL.path) {
            try fileManager.removeItem(at: packageURL)
        }

        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)
        try markPackageDirectory(at: packageURL)

        try writeProjectManifest(document: preparedDocument, to: packageURL)
        try writeArray(preparedDocument.groups, named: "groups.json", to: packageURL)
        try writeArray(preparedDocument.parkingStrips, named: "parking-strips.json", to: packageURL)
        try writeArray(preparedDocument.links, named: "links.json", to: packageURL)
        try writeArray(preparedDocument.archive, named: "archive.json", to: packageURL)

        let cardsDirectoryURL = packageURL.appendingPathComponent("cards", isDirectory: true)
        try fileManager.createDirectory(at: cardsDirectoryURL, withIntermediateDirectories: true)
        for card in preparedDocument.cards {
            try writeCard(card, to: cardsDirectoryURL)
        }
    }

    static func deltaWrite(
        document: BWRDocument,
        to packageURL: URL,
        changedCardIDs: Set<UUID>,
        removedCardIDs: Set<UUID> = []
    ) throws {
        let preparedDocument = BWRShadowPlacementTransition.preparedForPersistence(document: document)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: packageURL.path) {
            try fullWrite(document: preparedDocument, to: packageURL)
            return
        }

        try markPackageDirectory(at: packageURL)
        try writeProjectManifest(document: preparedDocument, to: packageURL)
        try writeArray(preparedDocument.groups, named: "groups.json", to: packageURL)
        try writeArray(preparedDocument.parkingStrips, named: "parking-strips.json", to: packageURL)
        try writeArray(preparedDocument.links, named: "links.json", to: packageURL)
        try writeArray(preparedDocument.archive, named: "archive.json", to: packageURL)

        let cardsDirectoryURL = packageURL.appendingPathComponent("cards", isDirectory: true)
        try fileManager.createDirectory(at: cardsDirectoryURL, withIntermediateDirectories: true)

        for removedCardID in removedCardIDs {
            let cardDirectoryURL = cardsDirectoryURL.appendingPathComponent(removedCardID.uuidString, isDirectory: true)
            if fileManager.fileExists(atPath: cardDirectoryURL.path) {
                try fileManager.removeItem(at: cardDirectoryURL)
            }
        }

        for card in preparedDocument.cards where changedCardIDs.contains(card.id) {
            try writeCard(card, to: cardsDirectoryURL)
        }
    }

    static func read(from packageURL: URL) throws -> BWRDocument {
        do {
            let manifestURL = packageURL.appendingPathComponent("project.json")
            let manifest = try decoder.decode(ProjectManifest.self, from: Data(contentsOf: manifestURL))
            guard manifest.schemaVersion >= 2 else {
                throw BWRPackageStoreError.unsupportedSchema(manifest.schemaVersion)
            }
            let groups = try readArray([BWRGroup].self, named: "groups.json", from: packageURL)
            let parkingStrips = try readArray([BWRParkingStrip].self, named: "parking-strips.json", from: packageURL, defaultValue: [])
            let links = try readArray([BWRLink].self, named: "links.json", from: packageURL, defaultValue: [])
            let archive = try readArray([BWRArchiveEntry].self, named: "archive.json", from: packageURL, defaultValue: [])
            let cardsDirectoryURL = packageURL.appendingPathComponent("cards", isDirectory: true)
            let cards = try manifest.cardIDs.map { cardID in
                try readCard(id: cardID, from: cardsDirectoryURL)
            }

            let document = BWRDocument(
                schemaVersion: manifest.schemaVersion,
                createdAt: manifest.createdAt,
                updatedAt: manifest.updatedAt,
                nextStableSortKey: manifest.nextStableSortKey,
                boardTheme: manifest.boardTheme,
                cards: cards,
                groups: groups,
                parkingStrips: parkingStrips,
                links: links,
                archive: archive
            )
            return try validatedDocument(document)
        } catch let error as BWRPackageStoreError {
            throw error
        } catch {
            throw BWRPackageStoreError.corruptedPackage(reason: error.localizedDescription)
        }
    }

    static func fileWrapper(
        document: BWRDocument,
        preferredFileName: String = "Document.bwr"
    ) throws -> FileWrapper {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bwr-filewrapper-\(UUID().uuidString)")
            .appendingPathExtension("bwr")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        try fullWrite(document: document, to: tempURL)
        let wrapper = try FileWrapper(url: tempURL, options: .immediate)
        wrapper.preferredFilename = preferredFileName
        return wrapper
    }

    static func read(from fileWrapper: FileWrapper) throws -> BWRDocument {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bwr-read-\(UUID().uuidString)")
            .appendingPathExtension("bwr")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        try fileWrapper.write(
            to: tempURL,
            options: .atomic,
            originalContentsURL: nil
        )
        return try read(from: tempURL)
    }

    static func measureAutosave(cardCount: Int, mutateCardAt index: Int = 0) throws -> SaveMetrics {
        var document = BWRPhase0SeedFactory.makeAutosaveDocument(cardCount: cardCount)
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bwr-phase0-\(UUID().uuidString)")
            .appendingPathExtension("bwr")
        defer {
            try? FileManager.default.removeItem(at: packageURL)
        }

        let fullStart = CFAbsoluteTimeGetCurrent()
        try fullWrite(document: document, to: packageURL)
        let fullDuration = (CFAbsoluteTimeGetCurrent() - fullStart) * 1000.0

        guard document.cards.indices.contains(index) else {
            return SaveMetrics(
                fullSaveMilliseconds: fullDuration,
                deltaSaveMilliseconds: 0
            )
        }

        document.cards[index].layers[0].markdown.append("\n\nDelta save mutation.")
        document.cards[index].updatedAt = Date()
        document.updatedAt = Date()

        let deltaStart = CFAbsoluteTimeGetCurrent()
        try deltaWrite(document: document, to: packageURL, changedCardIDs: [document.cards[index].id])
        let deltaDuration = (CFAbsoluteTimeGetCurrent() - deltaStart) * 1000.0

        return SaveMetrics(
            fullSaveMilliseconds: fullDuration,
            deltaSaveMilliseconds: deltaDuration
        )
    }

    private static func writeProjectManifest(document: BWRDocument, to packageURL: URL) throws {
        let manifest = ProjectManifest(
            schemaVersion: document.schemaVersion,
            createdAt: document.createdAt,
            updatedAt: document.updatedAt,
            nextStableSortKey: document.nextStableSortKey,
            boardTheme: document.boardTheme,
            cardIDs: document.cards.map(\.id),
            groupIDs: document.groups.map(\.id),
            parkingStripIDs: document.parkingStrips.map(\.id),
            linkIDs: document.links.map(\.id)
        )
        let manifestURL = packageURL.appendingPathComponent("project.json")
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
    }

    private static func writeArray<T: Encodable>(
        _ value: T,
        named fileName: String,
        to packageURL: URL
    ) throws {
        let fileURL = packageURL.appendingPathComponent(fileName)
        try encoder.encode(value).write(to: fileURL, options: .atomic)
    }

    private static func readArray<T: Decodable>(
        _ type: T.Type,
        named fileName: String,
        from packageURL: URL,
        defaultValue: T? = nil
    ) throws -> T {
        let fileURL = packageURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            if let defaultValue { return defaultValue }
            throw CocoaError(.fileNoSuchFile)
        }
        return try decoder.decode(T.self, from: Data(contentsOf: fileURL))
    }

    private static func writeCard(_ card: BWRCard, to cardsDirectoryURL: URL) throws {
        let fileManager = FileManager.default
        let cardDirectoryURL = cardsDirectoryURL.appendingPathComponent(card.id.uuidString, isDirectory: true)
        if fileManager.fileExists(atPath: cardDirectoryURL.path) {
            try fileManager.removeItem(at: cardDirectoryURL)
        }
        try fileManager.createDirectory(at: cardDirectoryURL, withIntermediateDirectories: true)

        let layersDirectoryURL = cardDirectoryURL.appendingPathComponent("layers", isDirectory: true)
        try fileManager.createDirectory(at: layersDirectoryURL, withIntermediateDirectories: true)

        let layerMetadata = try card.layers.map { layer in
            let fileName = layerFileName(for: layer)
            let layerURL = layersDirectoryURL.appendingPathComponent(fileName)
            try layer.markdown.write(to: layerURL, atomically: true, encoding: .utf8)
            return CardMetadata.LayerMetadata(
                id: layer.id,
                kind: layer.kind,
                name: layer.name,
                order: layer.order,
                fileName: fileName
            )
        }

        let metadata = CardMetadata(
            id: card.id,
            stableSortKey: card.stableSortKey,
            cloneGroupID: card.cloneGroupID,
            colorHex: card.colorHex,
            currentLayerID: card.currentLayerID,
            placement: card.placement.map {
                CardMetadata.PlacementMetadata(
                    kind: $0.kind,
                    hostGroupID: $0.hostGroupID,
                    stripID: $0.stripID,
                    slotIndex: $0.slotIndex
                )
            },
            layout: card.layout,
            isArchived: card.isArchived,
            archivedAt: card.archivedAt,
            createdAt: card.createdAt,
            updatedAt: card.updatedAt,
            layers: layerMetadata
        )
        let metadataURL = cardDirectoryURL.appendingPathComponent("card.json")
        try encoder.encode(metadata).write(to: metadataURL, options: .atomic)
    }

    private static func readCard(id: UUID, from cardsDirectoryURL: URL) throws -> BWRCard {
        let cardDirectoryURL = cardsDirectoryURL.appendingPathComponent(id.uuidString, isDirectory: true)
        let metadataURL = cardDirectoryURL.appendingPathComponent("card.json")
        let layersDirectoryURL = cardDirectoryURL.appendingPathComponent("layers", isDirectory: true)
        let metadata = try decoder.decode(CardMetadata.self, from: Data(contentsOf: metadataURL))
        let layers = try metadata.layers.map { layerMetadata in
            let markdownURL = layersDirectoryURL.appendingPathComponent(layerMetadata.fileName)
            let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
            return BWRCardLayer(
                id: layerMetadata.id,
                kind: layerMetadata.kind,
                name: layerMetadata.name,
                markdown: markdown,
                order: layerMetadata.order
            )
        }
        return BWRCard(
            id: metadata.id,
            stableSortKey: metadata.stableSortKey,
            cloneGroupID: metadata.cloneGroupID,
            colorHex: metadata.colorHex,
            currentLayerID: metadata.currentLayerID,
            placement: metadata.placement.map {
                BWRCardPlacement(
                    kind: $0.kind,
                    hostGroupID: $0.hostGroupID,
                    stripID: $0.stripID,
                    slotIndex: $0.slotIndex
                )
            },
            layout: metadata.layout,
            isArchived: metadata.isArchived,
            archivedAt: metadata.archivedAt,
            createdAt: metadata.createdAt,
            updatedAt: metadata.updatedAt,
            layers: layers
        )
    }

    private static func validatedDocument(_ document: BWRDocument) throws -> BWRDocument {
        for card in document.cards {
            guard card.layers.contains(where: { $0.id == card.currentLayerID }) else {
                throw BWRPackageStoreError.invalidCurrentLayer(cardID: card.id, layerID: card.currentLayerID)
            }
        }

        return try BWRSlotPlacementNormalizer.validatedForLoad(document)
    }

    private static func layerFileName(for layer: BWRCardLayer) -> String {
        switch layer.kind {
        case .body:
            return "body-\(layer.order + 1).md"
        case .treatment:
            return "treatment.md"
        case .scenario:
            return "scenario.md"
        }
    }

    private static func markPackageDirectory(at packageURL: URL) throws {
        var mutableURL = packageURL
        var values = URLResourceValues()
        values.isPackage = true
        try mutableURL.setResourceValues(values)
    }
}
