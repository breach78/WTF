import Foundation

enum BoardSurfaceParentGroupID: Hashable, Identifiable, Equatable {
    case root
    case parent(UUID)

    var id: String {
        switch self {
        case .root:
            return "root"
        case .parent(let parentID):
            return parentID.uuidString
        }
    }

    var parentCardID: UUID? {
        switch self {
        case .root:
            return nil
        case .parent(let parentID):
            return parentID
        }
    }
}

struct BoardSurfaceStartAnchor: Equatable {
    let gridPosition: IndexBoardGridPosition
    let labelText: String
}

struct BoardSurfaceParentGroupPlacement: Identifiable, Equatable {
    let id: BoardSurfaceParentGroupID
    let parentCardID: UUID?
    let origin: IndexBoardGridPosition
    let cardIDs: [UUID]
    let titleText: String
    let subtitleText: String
    let colorToken: String?
    let isMainline: Bool
    let isTempGroup: Bool

    var width: Int {
        max(1, cardIDs.count)
    }

    var occupiedColumns: ClosedRange<Int> {
        origin.column...(origin.column + max(0, width - 1))
    }
}

struct BoardSurfaceLane: Identifiable, Equatable {
    let parentCardID: UUID?
    let laneIndex: Int
    let labelText: String
    let subtitleText: String
    let colorToken: String?
    let isTempLane: Bool

    var id: String {
        if let parentCardID {
            return parentCardID.uuidString
        }
        return "root"
    }
}

struct BoardSurfaceItem: Identifiable, Equatable {
    let cardID: UUID
    let laneParentID: UUID?
    let laneIndex: Int
    let slotIndex: Int?
    let detachedGridPosition: IndexBoardGridPosition?
    let gridPosition: IndexBoardGridPosition?
    let parentGroupID: BoardSurfaceParentGroupID?

    init(
        cardID: UUID,
        laneParentID: UUID?,
        laneIndex: Int,
        slotIndex: Int?,
        detachedGridPosition: IndexBoardGridPosition?,
        gridPosition: IndexBoardGridPosition? = nil,
        parentGroupID: BoardSurfaceParentGroupID? = nil
    ) {
        self.cardID = cardID
        self.laneParentID = laneParentID
        self.laneIndex = laneIndex
        self.slotIndex = slotIndex
        self.detachedGridPosition = detachedGridPosition
        self.gridPosition = gridPosition
        self.parentGroupID = parentGroupID
    }

    var isDetached: Bool { detachedGridPosition != nil }

    var id: UUID { cardID }
}

struct BoardSurfaceProjection: Equatable {
    let source: IndexBoardColumnSource
    let startAnchor: BoardSurfaceStartAnchor
    let lanes: [BoardSurfaceLane]
    let parentGroups: [BoardSurfaceParentGroupPlacement]
    let tempStrips: [IndexBoardTempStripState]
    let surfaceItems: [BoardSurfaceItem]
    let orderedCardIDs: [UUID]

    init(
        source: IndexBoardColumnSource,
        startAnchor: BoardSurfaceStartAnchor = BoardSurfaceStartAnchor(
            gridPosition: IndexBoardGridPosition(column: 0, row: 0),
            labelText: "START"
        ),
        lanes: [BoardSurfaceLane],
        parentGroups: [BoardSurfaceParentGroupPlacement] = [],
        tempStrips: [IndexBoardTempStripState] = [],
        surfaceItems: [BoardSurfaceItem],
        orderedCardIDs: [UUID]
    ) {
        self.source = source
        self.startAnchor = startAnchor
        self.lanes = lanes
        self.parentGroups = parentGroups
        self.tempStrips = tempStrips
        self.surfaceItems = surfaceItems
        self.orderedCardIDs = orderedCardIDs
    }
}

private struct IndexBoardTempStripLayoutElement {
    let member: IndexBoardTempStripMember
    let row: Int
    let startColumn: Int
    let width: Int

    var endColumn: Int { startColumn + max(0, width - 1) }
}

private func indexBoardTempStripID(
    row: Int,
    anchorColumn: Int,
    firstMember: IndexBoardTempStripMember
) -> String {
    "temp-strip:\(row):\(anchorColumn):\(firstMember.stableID)"
}

func resolvedIndexBoardTempStripSurfaceLayout(
    strips: [IndexBoardTempStripState],
    tempGroupWidthsByParentID: [UUID: Int]
) -> (
    groupOriginByParentID: [UUID: IndexBoardGridPosition],
    detachedPositionsByCardID: [UUID: IndexBoardGridPosition]
) {
    var groupOriginByParentID: [UUID: IndexBoardGridPosition] = [:]
    var detachedPositionsByCardID: [UUID: IndexBoardGridPosition] = [:]

    for strip in strips.sorted(by: { lhs, rhs in
        if lhs.row != rhs.row {
            return lhs.row < rhs.row
        }
        if lhs.anchorColumn != rhs.anchorColumn {
            return lhs.anchorColumn < rhs.anchorColumn
        }
        return lhs.id < rhs.id
    }) {
        var cursor = strip.anchorColumn
        for member in strip.members {
            switch member.kind {
            case .group:
                let width = max(1, tempGroupWidthsByParentID[member.id] ?? 1)
                groupOriginByParentID[member.id] = IndexBoardGridPosition(column: cursor, row: strip.row)
                cursor += width
            case .card:
                detachedPositionsByCardID[member.id] = IndexBoardGridPosition(column: cursor, row: strip.row)
                cursor += 1
            }
        }
    }

    return (
        groupOriginByParentID: groupOriginByParentID,
        detachedPositionsByCardID: detachedPositionsByCardID
    )
}

func indexBoardTempStrips(
    tempGroups: [BoardSurfaceParentGroupPlacement],
    detachedPositionsByCardID: [UUID: IndexBoardGridPosition]
) -> [IndexBoardTempStripState] {
    let groupElements = tempGroups.compactMap { group -> IndexBoardTempStripLayoutElement? in
        guard let parentCardID = group.parentCardID, !group.cardIDs.isEmpty else { return nil }
        return IndexBoardTempStripLayoutElement(
            member: IndexBoardTempStripMember(kind: .group, id: parentCardID),
            row: group.origin.row,
            startColumn: group.origin.column,
            width: max(1, group.width)
        )
    }
    let detachedElements = detachedPositionsByCardID.map { cardID, position in
        IndexBoardTempStripLayoutElement(
            member: IndexBoardTempStripMember(kind: .card, id: cardID),
            row: position.row,
            startColumn: position.column,
            width: 1
        )
    }
    let elementsByRow = Dictionary(grouping: groupElements + detachedElements, by: \.row)
    var strips: [IndexBoardTempStripState] = []

    for (row, rowElements) in elementsByRow {
        let sortedElements = rowElements.sorted { lhs, rhs in
            if lhs.startColumn != rhs.startColumn {
                return lhs.startColumn < rhs.startColumn
            }
            return lhs.member.stableID < rhs.member.stableID
        }
        guard !sortedElements.isEmpty else { continue }

        var blockStartIndex = 0

        func commitBlock(upTo endIndex: Int) {
            guard blockStartIndex <= endIndex else { return }
            let blockElements = Array(sortedElements[blockStartIndex...endIndex])
            guard let firstElement = blockElements.first else { return }
            strips.append(
                IndexBoardTempStripState(
                    id: indexBoardTempStripID(
                        row: row,
                        anchorColumn: firstElement.startColumn,
                        firstMember: firstElement.member
                    ),
                    row: row,
                    anchorColumn: firstElement.startColumn,
                    members: blockElements.map(\.member)
                )
            )
        }

        for index in 1..<sortedElements.count {
            if sortedElements[index].startColumn > sortedElements[index - 1].endColumn + 1 {
                commitBlock(upTo: index - 1)
                blockStartIndex = index
            }
        }

        commitBlock(upTo: sortedElements.count - 1)
    }

    return strips.sorted { lhs, rhs in
        if lhs.row != rhs.row {
            return lhs.row < rhs.row
        }
        if lhs.anchorColumn != rhs.anchorColumn {
            return lhs.anchorColumn < rhs.anchorColumn
        }
        return lhs.id < rhs.id
    }
}

func resolvedIndexBoardTempStrips(
    persistedStrips: [IndexBoardTempStripState],
    tempGroups: [BoardSurfaceParentGroupPlacement],
    detachedPositionsByCardID: [UUID: IndexBoardGridPosition]
) -> [IndexBoardTempStripState] {
    let availableMembers = Set(
        tempGroups.compactMap { placement in
            placement.parentCardID.map { IndexBoardTempStripMember(kind: .group, id: $0) }
        } + detachedPositionsByCardID.keys.map { IndexBoardTempStripMember(kind: .card, id: $0) }
    )
    var seenMembers: Set<IndexBoardTempStripMember> = []
    var resolved: [IndexBoardTempStripState] = []

    for strip in persistedStrips {
        let filteredMembers = strip.members.filter { member in
            availableMembers.contains(member) && seenMembers.insert(member).inserted
        }
        guard !filteredMembers.isEmpty else { continue }
        resolved.append(
            IndexBoardTempStripState(
                id: strip.id,
                row: strip.row,
                anchorColumn: strip.anchorColumn,
                members: filteredMembers
            )
        )
    }

    let missingTempGroups = tempGroups.filter { placement in
        guard let parentCardID = placement.parentCardID else { return false }
        return !seenMembers.contains(IndexBoardTempStripMember(kind: .group, id: parentCardID))
    }
    let missingDetachedPositions = detachedPositionsByCardID.filter { cardID, _ in
        !seenMembers.contains(IndexBoardTempStripMember(kind: .card, id: cardID))
    }

    resolved.append(
        contentsOf: indexBoardTempStrips(
            tempGroups: missingTempGroups,
            detachedPositionsByCardID: missingDetachedPositions
        )
    )

    return resolved.sorted { lhs, rhs in
        if lhs.row != rhs.row {
            return lhs.row < rhs.row
        }
        if lhs.anchorColumn != rhs.anchorColumn {
            return lhs.anchorColumn < rhs.anchorColumn
        }
        return lhs.id < rhs.id
    }
}

func resolvedIndexBoardTempStripsAfterRemovingMembers(
    strips: [IndexBoardTempStripState],
    movingMembers: [IndexBoardTempStripMember]
) -> [IndexBoardTempStripState] {
    let movingMemberSet = Set(movingMembers)
    return strips.compactMap { strip in
        let stationaryMembers = strip.members.filter { !movingMemberSet.contains($0) }
        guard !stationaryMembers.isEmpty else { return nil }
        return IndexBoardTempStripState(
            id: strip.id,
            row: strip.row,
            anchorColumn: strip.anchorColumn,
            members: stationaryMembers
        )
    }
}

func resolvedIndexBoardTempStripsByApplyingMove(
    strips: [IndexBoardTempStripState],
    movingMembers: [IndexBoardTempStripMember],
    previousMember: IndexBoardTempStripMember?,
    nextMember: IndexBoardTempStripMember?,
    parkingPosition: IndexBoardGridPosition?
) -> [IndexBoardTempStripState] {
    var resolvedStrips = resolvedIndexBoardTempStripsAfterRemovingMembers(
        strips: strips,
        movingMembers: movingMembers
    )

    func stripIndex(containing member: IndexBoardTempStripMember) -> Int? {
        resolvedStrips.firstIndex(where: { $0.members.contains(member) })
    }

    if let nextMember, let stripIndex = stripIndex(containing: nextMember),
       let insertionIndex = resolvedStrips[stripIndex].members.firstIndex(of: nextMember) {
        resolvedStrips[stripIndex].members.insert(
            contentsOf: movingMembers,
            at: insertionIndex
        )
        return resolvedStrips.sorted { lhs, rhs in
            if lhs.row != rhs.row { return lhs.row < rhs.row }
            if lhs.anchorColumn != rhs.anchorColumn { return lhs.anchorColumn < rhs.anchorColumn }
            return lhs.id < rhs.id
        }
    }

    if let previousMember, let stripIndex = stripIndex(containing: previousMember),
       let memberIndex = resolvedStrips[stripIndex].members.firstIndex(of: previousMember) {
        resolvedStrips[stripIndex].members.insert(
            contentsOf: movingMembers,
            at: memberIndex + 1
        )
        return resolvedStrips.sorted { lhs, rhs in
            if lhs.row != rhs.row { return lhs.row < rhs.row }
            if lhs.anchorColumn != rhs.anchorColumn { return lhs.anchorColumn < rhs.anchorColumn }
            return lhs.id < rhs.id
        }
    }

    if let parkingPosition, let firstMember = movingMembers.first {
        resolvedStrips.append(
            IndexBoardTempStripState(
                id: indexBoardTempStripID(
                    row: parkingPosition.row,
                    anchorColumn: parkingPosition.column,
                    firstMember: firstMember
                ),
                row: parkingPosition.row,
                anchorColumn: parkingPosition.column,
                members: movingMembers
            )
        )
    }

    return resolvedStrips.sorted { lhs, rhs in
        if lhs.row != rhs.row { return lhs.row < rhs.row }
        if lhs.anchorColumn != rhs.anchorColumn { return lhs.anchorColumn < rhs.anchorColumn }
        return lhs.id < rhs.id
    }
}

func normalizedIndexBoardDetachedGridPositions(
    _ positionsByCardID: [UUID: IndexBoardGridPosition]
) -> [UUID: IndexBoardGridPosition] {
    guard !positionsByCardID.isEmpty else { return [:] }

    let entriesByRow = Dictionary(grouping: positionsByCardID, by: { $0.value.row })
    var normalized: [UUID: IndexBoardGridPosition] = [:]
    normalized.reserveCapacity(positionsByCardID.count)

    for (_, rowEntries) in entriesByRow {
        let sortedEntries = rowEntries.sorted { lhs, rhs in
            if lhs.value.column != rhs.value.column {
                return lhs.value.column < rhs.value.column
            }
            return lhs.key.uuidString < rhs.key.uuidString
        }
        guard !sortedEntries.isEmpty else { continue }

        var blockStartIndex = 0

        func commitBlock(upTo endIndex: Int) {
            guard blockStartIndex <= endIndex else { return }
            let startColumn = sortedEntries[blockStartIndex].value.column
            for (offset, index) in (blockStartIndex...endIndex).enumerated() {
                let entry = sortedEntries[index]
                normalized[entry.key] = IndexBoardGridPosition(
                    column: startColumn + offset,
                    row: entry.value.row
                )
            }
        }

        for index in 1..<sortedEntries.count {
            let previousColumn = sortedEntries[index - 1].value.column
            let currentColumn = sortedEntries[index].value.column
            if currentColumn - previousColumn > 1 {
                commitBlock(upTo: index - 1)
                blockStartIndex = index
            }
        }

        commitBlock(upTo: sortedEntries.count - 1)
    }

    return normalized
}

struct IndexBoardDetachedRowBlock {
    let row: Int
    let anchorColumn: Int
    let cardIDs: [UUID]

    var lastColumn: Int {
        anchorColumn + max(0, cardIDs.count - 1)
    }
}

struct IndexBoardSurfaceRowChainElement {
    enum Kind {
        case group(BoardSurfaceParentGroupPlacement)
        case detached(UUID)
    }

    let kind: Kind
    let row: Int
    let startColumn: Int
    let width: Int
    let cardIDs: [UUID]
    let stableID: String

    var firstCardID: UUID { cardIDs.first! }
    var lastCardID: UUID { cardIDs.last! }
    var endColumn: Int { startColumn + max(0, width - 1) }
}

struct IndexBoardSurfaceRowChain {
    let row: Int
    let anchorColumn: Int
    let elements: [IndexBoardSurfaceRowChainElement]

    var lastColumn: Int {
        elements.last?.endColumn ?? anchorColumn
    }
}

func indexBoardSurfaceStationaryParentGroups(
    from parentGroups: [BoardSurfaceParentGroupPlacement],
    excluding excludedCardIDs: Set<UUID>
) -> [BoardSurfaceParentGroupPlacement] {
    parentGroups.compactMap { group in
        let stationaryCardIDs = group.cardIDs.filter { !excludedCardIDs.contains($0) }
        guard !stationaryCardIDs.isEmpty else { return nil }
        return BoardSurfaceParentGroupPlacement(
            id: group.id,
            parentCardID: group.parentCardID,
            origin: group.origin,
            cardIDs: stationaryCardIDs,
            titleText: group.titleText,
            subtitleText: group.subtitleText,
            colorToken: group.colorToken,
            isMainline: group.isMainline,
            isTempGroup: group.isTempGroup
        )
    }
}

func indexBoardSurfaceRowChains(
    parentGroups: [BoardSurfaceParentGroupPlacement],
    detachedPositionsByCardID: [UUID: IndexBoardGridPosition]
) -> [IndexBoardSurfaceRowChain] {
    let groupElements = parentGroups.compactMap { group -> IndexBoardSurfaceRowChainElement? in
        guard !group.cardIDs.isEmpty else { return nil }
        return IndexBoardSurfaceRowChainElement(
            kind: .group(group),
            row: group.origin.row,
            startColumn: group.origin.column,
            width: max(1, group.width),
            cardIDs: group.cardIDs,
            stableID: "group:\(group.id.id)"
        )
    }
    let detachedElements = detachedPositionsByCardID.map { cardID, position in
        IndexBoardSurfaceRowChainElement(
            kind: .detached(cardID),
            row: position.row,
            startColumn: position.column,
            width: 1,
            cardIDs: [cardID],
            stableID: "card:\(cardID.uuidString)"
        )
    }
    let elementsByRow = Dictionary(grouping: groupElements + detachedElements, by: \.row)
    var rowChains: [IndexBoardSurfaceRowChain] = []

    for (row, rowElements) in elementsByRow {
        let sortedElements = rowElements.sorted { lhs, rhs in
            if lhs.startColumn != rhs.startColumn {
                return lhs.startColumn < rhs.startColumn
            }
            return lhs.stableID < rhs.stableID
        }
        guard !sortedElements.isEmpty else { continue }

        var blockStartIndex = 0

        func commitBlock(upTo endIndex: Int) {
            guard blockStartIndex <= endIndex else { return }
            let blockElements = Array(sortedElements[blockStartIndex...endIndex])
            rowChains.append(
                IndexBoardSurfaceRowChain(
                    row: row,
                    anchorColumn: blockElements.first?.startColumn ?? 0,
                    elements: blockElements
                )
            )
        }

        for index in 1..<sortedElements.count {
            if sortedElements[index].startColumn > sortedElements[index - 1].endColumn + 1 {
                commitBlock(upTo: index - 1)
                blockStartIndex = index
            }
        }

        commitBlock(upTo: sortedElements.count - 1)
    }

    return rowChains.sorted { lhs, rhs in
        if lhs.row != rhs.row {
            return lhs.row < rhs.row
        }
        return lhs.anchorColumn < rhs.anchorColumn
    }
}

private struct IndexBoardSurfaceRowChainInsertion {
    let chain: IndexBoardSurfaceRowChain
    let insertionIndex: Int
}

private func resolvedIndexBoardSurfaceRowChainInsertion(
    target: IndexBoardCardDropTarget,
    parentGroups: [BoardSurfaceParentGroupPlacement],
    detachedPositionsByCardID: [UUID: IndexBoardGridPosition]
) -> IndexBoardSurfaceRowChainInsertion? {
    let rowChains = indexBoardSurfaceRowChains(
        parentGroups: parentGroups,
        detachedPositionsByCardID: detachedPositionsByCardID
    )

    func chainAndIndex(for cardID: UUID) -> (IndexBoardSurfaceRowChain, Int)? {
        for chain in rowChains {
            if let elementIndex = chain.elements.firstIndex(where: { $0.cardIDs.contains(cardID) }) {
                return (chain, elementIndex)
            }
        }
        return nil
    }

    if let nextCardID = target.nextCardID,
       let (chain, elementIndex) = chainAndIndex(for: nextCardID) {
        return IndexBoardSurfaceRowChainInsertion(chain: chain, insertionIndex: elementIndex)
    }

    if let previousCardID = target.previousCardID,
       let (chain, elementIndex) = chainAndIndex(for: previousCardID) {
        return IndexBoardSurfaceRowChainInsertion(chain: chain, insertionIndex: elementIndex + 1)
    }

    return nil
}

func indexBoardDetachedRowBlocks(
    from positionsByCardID: [UUID: IndexBoardGridPosition]
) -> [IndexBoardDetachedRowBlock] {
    let entriesByRow = Dictionary(grouping: positionsByCardID, by: { $0.value.row })
    var blocks: [IndexBoardDetachedRowBlock] = []

    for (row, rowEntries) in entriesByRow {
        let sortedEntries = rowEntries.sorted { lhs, rhs in
            if lhs.value.column != rhs.value.column {
                return lhs.value.column < rhs.value.column
            }
            return lhs.key.uuidString < rhs.key.uuidString
        }
        guard !sortedEntries.isEmpty else { continue }

        var blockStartIndex = 0

        func commitBlock(upTo endIndex: Int) {
            guard blockStartIndex <= endIndex else { return }
            blocks.append(
                IndexBoardDetachedRowBlock(
                    row: row,
                    anchorColumn: sortedEntries[blockStartIndex].value.column,
                    cardIDs: sortedEntries[blockStartIndex...endIndex].map(\.key)
                )
            )
        }

        for index in 1..<sortedEntries.count {
            let previousColumn = sortedEntries[index - 1].value.column
            let currentColumn = sortedEntries[index].value.column
            if currentColumn - previousColumn > 1 {
                commitBlock(upTo: index - 1)
                blockStartIndex = index
            }
        }

        commitBlock(upTo: sortedEntries.count - 1)
    }

    return blocks.sorted { lhs, rhs in
        if lhs.row != rhs.row {
            return lhs.row < rhs.row
        }
        return lhs.anchorColumn < rhs.anchorColumn
    }
}

func resolvedIndexBoardDetachedPositionsAfterRemovingCards(
    referencePositionsByCardID: [UUID: IndexBoardGridPosition],
    movingCardIDs: [UUID]
) -> [UUID: IndexBoardGridPosition] {
    let movingCardIDSet = Set(movingCardIDs)
    var resolvedPositions = referencePositionsByCardID.filter { !movingCardIDSet.contains($0.key) }

    for block in indexBoardDetachedRowBlocks(from: referencePositionsByCardID) {
        let stationaryCardIDs = block.cardIDs.filter { !movingCardIDSet.contains($0) }
        for (offset, cardID) in stationaryCardIDs.enumerated() {
            resolvedPositions[cardID] = IndexBoardGridPosition(
                column: block.anchorColumn + offset,
                row: block.row
            )
        }
    }

    return resolvedPositions
}

private func resolvedIndexBoardDetachedParkingPositions(
    count: Int,
    start: IndexBoardGridPosition,
    occupied: Set<IndexBoardGridPosition>
) -> [IndexBoardGridPosition] {
    guard count > 0 else { return [] }
    var positions: [IndexBoardGridPosition] = []
    positions.reserveCapacity(count)
    var taken = occupied
    var nextColumn = start.column

    while positions.count < count {
        let candidate = IndexBoardGridPosition(column: nextColumn, row: start.row)
        if !taken.contains(candidate) {
            positions.append(candidate)
            taken.insert(candidate)
        }
        nextColumn += 1
    }

    return positions
}

private func resolvedIndexBoardDetachedBlockInsertion(
    target: IndexBoardCardDropTarget,
    positionsByCardID: [UUID: IndexBoardGridPosition]
) -> (row: Int, anchorColumn: Int, blockCardIDs: [UUID], insertionIndex: Int)? {
    let blocks = indexBoardDetachedRowBlocks(from: positionsByCardID)
    guard !blocks.isEmpty else { return nil }

    let targetBlock: IndexBoardDetachedRowBlock? = {
        if let previousCardID = target.previousCardID,
           let block = blocks.first(where: { $0.cardIDs.contains(previousCardID) }) {
            return block
        }
        if let nextCardID = target.nextCardID,
           let block = blocks.first(where: { $0.cardIDs.contains(nextCardID) }) {
            return block
        }
        return nil
    }()
    guard let targetBlock else { return nil }

    let insertionIndex: Int
    if let nextCardID = target.nextCardID,
       let nextIndex = targetBlock.cardIDs.firstIndex(of: nextCardID) {
        insertionIndex = nextIndex
    } else if let previousCardID = target.previousCardID,
              let previousIndex = targetBlock.cardIDs.firstIndex(of: previousCardID) {
        insertionIndex = previousIndex + 1
    } else {
        insertionIndex = target.insertionIndex
    }

    return (
        row: targetBlock.row,
        anchorColumn: targetBlock.anchorColumn,
        blockCardIDs: targetBlock.cardIDs,
        insertionIndex: min(max(0, insertionIndex), targetBlock.cardIDs.count)
    )
}

func resolvedIndexBoardDetachedPositionsByApplyingDrop(
    referencePositionsByCardID: [UUID: IndexBoardGridPosition],
    movingCardIDs: [UUID],
    target: IndexBoardCardDropTarget
) -> [UUID: IndexBoardGridPosition] {
    var resolvedPositions = resolvedIndexBoardDetachedPositionsAfterRemovingCards(
        referencePositionsByCardID: referencePositionsByCardID,
        movingCardIDs: movingCardIDs
    )

    if let insertion = resolvedIndexBoardDetachedBlockInsertion(
        target: target,
        positionsByCardID: resolvedPositions
    ) {
        var reorderedBlockCardIDs = insertion.blockCardIDs
        reorderedBlockCardIDs.insert(
            contentsOf: movingCardIDs,
            at: min(max(0, insertion.insertionIndex), reorderedBlockCardIDs.count)
        )
        for (offset, cardID) in reorderedBlockCardIDs.enumerated() {
            resolvedPositions[cardID] = IndexBoardGridPosition(
                column: insertion.anchorColumn + offset,
                row: insertion.row
            )
        }
        return resolvedPositions
    }

    guard let start = target.detachedGridPosition else { return resolvedPositions }
    let parkingPositions = resolvedIndexBoardDetachedParkingPositions(
        count: movingCardIDs.count,
        start: start,
        occupied: Set(resolvedPositions.values)
    )
    for (cardID, position) in zip(movingCardIDs, parkingPositions) {
        resolvedPositions[cardID] = position
    }
    return resolvedPositions
}

func resolvedIndexBoardDetachedSurfaceLayoutByApplyingDrop(
    parentGroups: [BoardSurfaceParentGroupPlacement],
    detachedPositionsByCardID: [UUID: IndexBoardGridPosition],
    movingCardIDs: [UUID],
    target: IndexBoardCardDropTarget,
    referenceParentGroups: [BoardSurfaceParentGroupPlacement]? = nil,
    referenceDetachedPositionsByCardID: [UUID: IndexBoardGridPosition]? = nil
) -> (
    parentGroups: [BoardSurfaceParentGroupPlacement],
    detachedPositionsByCardID: [UUID: IndexBoardGridPosition]
) {
    let movingCardIDSet = Set(movingCardIDs)
    let stationaryParentGroups = indexBoardSurfaceStationaryParentGroups(
        from: parentGroups,
        excluding: movingCardIDSet
    )
    let resolvedDetachedPositions = resolvedIndexBoardDetachedPositionsByApplyingDrop(
        referencePositionsByCardID: detachedPositionsByCardID,
        movingCardIDs: movingCardIDs,
        target: target
    )

    return normalizedIndexBoardSurfaceLayout(
        parentGroups: stationaryParentGroups,
        detachedPositionsByCardID: resolvedDetachedPositions,
        referenceParentGroups: referenceParentGroups ?? stationaryParentGroups,
        referenceDetachedPositionsByCardID: referenceDetachedPositionsByCardID ?? detachedPositionsByCardID
    )
}

func indexBoardDetachedGridPositionsByCardID(
    from surfaceProjection: BoardSurfaceProjection
) -> [UUID: IndexBoardGridPosition] {
    surfaceProjection.surfaceItems.reduce(into: [UUID: IndexBoardGridPosition]()) { partialResult, item in
        guard item.parentGroupID == nil,
              let position = item.detachedGridPosition ?? item.gridPosition else { return }
        partialResult[item.cardID] = position
    }
}

private func resolvedIndexBoardNonOverlappingParentGroups(
    _ parentGroups: [BoardSurfaceParentGroupPlacement],
    detachedPositionsByCardID: [UUID: IndexBoardGridPosition] = [:],
    preferredLeadingParentCardID: UUID? = nil
) -> [BoardSurfaceParentGroupPlacement] {
    let nonTempGroups = parentGroups.filter { !$0.isTempGroup }
    guard !nonTempGroups.isEmpty else { return parentGroups }

    func sortGroups(
        _ lhs: BoardSurfaceParentGroupPlacement,
        _ rhs: BoardSurfaceParentGroupPlacement
    ) -> Bool {
        if lhs.origin.column != rhs.origin.column {
            return lhs.origin.column < rhs.origin.column
        }
        return lhs.id.id < rhs.id.id
    }

    let groupsByRow = Dictionary(grouping: nonTempGroups, by: { $0.origin.row })
    let detachedColumnsByRow = Dictionary(grouping: detachedPositionsByCardID.values, by: \.row)
        .mapValues { positions in
            positions.map(\.column).sorted()
        }
    var resolvedOriginByID: [BoardSurfaceParentGroupID: IndexBoardGridPosition] = [:]

    func resolvedColumnAvoidingDetachedOccupancy(
        startingAt proposedColumn: Int,
        width: Int,
        detachedColumns: [Int]
    ) -> Int {
        guard !detachedColumns.isEmpty else { return proposedColumn }

        var resolvedColumn = proposedColumn
        while let overlappingColumn = detachedColumns.first(where: { column in
            column >= resolvedColumn && column <= resolvedColumn + max(0, width - 1)
        }) {
            resolvedColumn = overlappingColumn + 1
        }
        return resolvedColumn
    }

    for (row, rowGroups) in groupsByRow {
        let sortedGroups = rowGroups.sorted(by: sortGroups)
        let detachedColumns = detachedColumnsByRow[row] ?? []

        if let preferredLeadingParentCardID,
           let preferredGroup = sortedGroups.first(where: { $0.parentCardID == preferredLeadingParentCardID }) {
            let preferredStartColumn = preferredGroup.origin.column
            let resolvedPreferredColumn = resolvedColumnAvoidingDetachedOccupancy(
                startingAt: preferredGroup.origin.column,
                width: preferredGroup.width,
                detachedColumns: detachedColumns
            )
            resolvedOriginByID[preferredGroup.id] = IndexBoardGridPosition(
                column: resolvedPreferredColumn,
                row: row
            )

            let unaffectedLeadingGroups = sortedGroups.filter {
                $0.id != preferredGroup.id && $0.occupiedColumns.upperBound < preferredStartColumn
            }
            for group in unaffectedLeadingGroups {
                let resolvedColumn = resolvedColumnAvoidingDetachedOccupancy(
                    startingAt: group.origin.column,
                    width: group.width,
                    detachedColumns: detachedColumns
                )
                resolvedOriginByID[group.id] = IndexBoardGridPosition(
                    column: resolvedColumn,
                    row: row
                )
            }

            var cursor = resolvedPreferredColumn + preferredGroup.width
            let trailingGroups = sortedGroups.filter {
                $0.id != preferredGroup.id && $0.occupiedColumns.upperBound >= preferredStartColumn
            }

            for group in trailingGroups {
                let resolvedColumn = resolvedColumnAvoidingDetachedOccupancy(
                    startingAt: max(group.origin.column, cursor),
                    width: group.width,
                    detachedColumns: detachedColumns
                )
                resolvedOriginByID[group.id] = IndexBoardGridPosition(
                    column: resolvedColumn,
                    row: row
                )
                cursor = resolvedColumn + group.width
            }
            continue
        }

        var cursor: Int?
        for group in sortedGroups {
            let resolvedColumn = resolvedColumnAvoidingDetachedOccupancy(
                startingAt: max(group.origin.column, cursor ?? group.origin.column),
                width: group.width,
                detachedColumns: detachedColumns
            )
            resolvedOriginByID[group.id] = IndexBoardGridPosition(
                column: resolvedColumn,
                row: row
            )
            cursor = resolvedColumn + group.width
        }
    }

    return parentGroups.map { group in
        guard let resolvedOrigin = resolvedOriginByID[group.id] else { return group }
        return BoardSurfaceParentGroupPlacement(
            id: group.id,
            parentCardID: group.parentCardID,
            origin: resolvedOrigin,
            cardIDs: group.cardIDs,
            titleText: group.titleText,
            subtitleText: group.subtitleText,
            colorToken: group.colorToken,
            isMainline: group.isMainline,
            isTempGroup: group.isTempGroup
        )
    }
}

func normalizedIndexBoardSurfaceLayout(
    parentGroups: [BoardSurfaceParentGroupPlacement],
    detachedPositionsByCardID: [UUID: IndexBoardGridPosition],
    referenceParentGroups: [BoardSurfaceParentGroupPlacement]? = nil,
    referenceDetachedPositionsByCardID: [UUID: IndexBoardGridPosition]? = nil,
    preferredLeadingParentCardID: UUID? = nil
) -> (
    parentGroups: [BoardSurfaceParentGroupPlacement],
    detachedPositionsByCardID: [UUID: IndexBoardGridPosition]
) {
    if let preferredLeadingParentCardID {
        return (
            parentGroups: resolvedIndexBoardNonOverlappingParentGroups(
                parentGroups,
                detachedPositionsByCardID: detachedPositionsByCardID,
                preferredLeadingParentCardID: preferredLeadingParentCardID
            ),
            detachedPositionsByCardID: detachedPositionsByCardID
        )
    }

    let mainlineParentGroups = parentGroups.filter { !$0.isTempGroup }
    let referenceMainlineParentGroups = (referenceParentGroups ?? parentGroups).filter { !$0.isTempGroup }

    struct RowElement {
        enum Kind {
            case group(BoardSurfaceParentGroupID)
            case detached(UUID)
        }

        let kind: Kind
        let row: Int
        let startColumn: Int
        let width: Int
        let stableID: String

        var endColumn: Int { startColumn + max(0, width - 1) }
    }

    struct RowClusterAnchor {
        let anchorColumn: Int
        let stableIDs: Set<String>
    }

    func resolvedRowElements(
        parentGroups: [BoardSurfaceParentGroupPlacement],
        detachedPositionsByCardID: [UUID: IndexBoardGridPosition]
    ) -> [RowElement] {
        let groupElements = parentGroups.map { group in
            RowElement(
                kind: .group(group.id),
                row: group.origin.row,
                startColumn: group.origin.column,
                width: max(1, group.width),
                stableID: "group:\(group.id.id)"
            )
        }
        let detachedElements = detachedPositionsByCardID.map { cardID, position in
            RowElement(
                kind: .detached(cardID),
                row: position.row,
                startColumn: position.column,
                width: 1,
                stableID: "card:\(cardID.uuidString)"
            )
        }
        return groupElements + detachedElements
    }

    func resolvedRowClusterAnchors(
        elements: [RowElement]
    ) -> [Int: [RowClusterAnchor]] {
        let elementsByRow = Dictionary(grouping: elements, by: \.row)
        var anchorsByRow: [Int: [RowClusterAnchor]] = [:]

        for (row, rowElements) in elementsByRow {
            let sortedElements = rowElements.sorted { lhs, rhs in
                if lhs.startColumn != rhs.startColumn {
                    return lhs.startColumn < rhs.startColumn
                }
                return lhs.stableID < rhs.stableID
            }
            guard !sortedElements.isEmpty else { continue }

            var blockStartIndex = 0

            func commitBlock(upTo endIndex: Int) {
                guard blockStartIndex <= endIndex else { return }
                let stableIDs = Set(sortedElements[blockStartIndex...endIndex].map(\.stableID))
                anchorsByRow[row, default: []].append(
                    RowClusterAnchor(
                        anchorColumn: sortedElements[blockStartIndex].startColumn,
                        stableIDs: stableIDs
                    )
                )
            }

            for index in 1..<sortedElements.count {
                if sortedElements[index].startColumn > sortedElements[index - 1].endColumn + 1 {
                    commitBlock(upTo: index - 1)
                    blockStartIndex = index
                }
            }

            commitBlock(upTo: sortedElements.count - 1)
        }

        return anchorsByRow
    }

    let rowElements = resolvedRowElements(
        parentGroups: mainlineParentGroups,
        detachedPositionsByCardID: detachedPositionsByCardID
    )
    let referenceAnchorsByRow = resolvedRowClusterAnchors(
        elements: resolvedRowElements(
            parentGroups: referenceMainlineParentGroups,
            detachedPositionsByCardID: referenceDetachedPositionsByCardID ?? detachedPositionsByCardID
        )
    )
    let elementsByRow = Dictionary(grouping: rowElements, by: \.row)
    var normalizedGroupOriginByID: [BoardSurfaceParentGroupID: IndexBoardGridPosition] = [:]

    for (row, rowElements) in elementsByRow {
        let sortedElements = rowElements.sorted { lhs, rhs in
            if lhs.startColumn != rhs.startColumn {
                return lhs.startColumn < rhs.startColumn
            }
            return lhs.stableID < rhs.stableID
        }
        guard !sortedElements.isEmpty else { continue }

        var blockStartIndex = 0
        var remainingReferenceAnchors = referenceAnchorsByRow[row] ?? []

        func commitBlock(upTo endIndex: Int) {
            guard blockStartIndex <= endIndex else { return }
            let stableIDs = Set(sortedElements[blockStartIndex...endIndex].map(\.stableID))
            let currentStartColumn = sortedElements[blockStartIndex].startColumn
            let clusterStartColumn: Int = {
                let matches = remainingReferenceAnchors.enumerated().compactMap { index, anchor -> (index: Int, overlap: Int, distance: Int, anchorColumn: Int)? in
                    let overlap = anchor.stableIDs.intersection(stableIDs).count
                    guard overlap > 0 else { return nil }
                    return (
                        index: index,
                        overlap: overlap,
                        distance: abs(anchor.anchorColumn - currentStartColumn),
                        anchorColumn: anchor.anchorColumn
                    )
                }
                guard let bestMatch = matches.sorted(by: { lhs, rhs in
                    if lhs.overlap != rhs.overlap {
                        return lhs.overlap > rhs.overlap
                    }
                    if lhs.distance != rhs.distance {
                        return lhs.distance < rhs.distance
                    }
                    if lhs.anchorColumn != rhs.anchorColumn {
                        return lhs.anchorColumn < rhs.anchorColumn
                    }
                    return lhs.index < rhs.index
                }).first else {
                    return currentStartColumn
                }
                let anchorColumn = remainingReferenceAnchors[bestMatch.index].anchorColumn
                remainingReferenceAnchors.remove(at: bestMatch.index)
                return min(anchorColumn, currentStartColumn)
            }()
            var cursor = clusterStartColumn

            for index in blockStartIndex...endIndex {
                let element = sortedElements[index]
                cursor = max(cursor, element.startColumn)
                switch element.kind {
                case .group(let groupID):
                    normalizedGroupOriginByID[groupID] = IndexBoardGridPosition(
                        column: cursor,
                        row: row
                    )
                case .detached:
                    break
                }
                cursor += element.width
            }
        }

        for index in 1..<sortedElements.count {
            if sortedElements[index].startColumn > sortedElements[index - 1].endColumn + 1 {
                commitBlock(upTo: index - 1)
                blockStartIndex = index
            }
        }

        commitBlock(upTo: sortedElements.count - 1)
    }

    let normalizedParentGroups = parentGroups.map { group in
        BoardSurfaceParentGroupPlacement(
            id: group.id,
            parentCardID: group.parentCardID,
            origin: group.isTempGroup ? group.origin : (normalizedGroupOriginByID[group.id] ?? group.origin),
            cardIDs: group.cardIDs,
            titleText: group.titleText,
            subtitleText: group.subtitleText,
            colorToken: group.colorToken,
            isMainline: group.isMainline,
            isTempGroup: group.isTempGroup
        )
    }
    let resolvedParentGroups = resolvedIndexBoardNonOverlappingParentGroups(
        normalizedParentGroups,
        detachedPositionsByCardID: detachedPositionsByCardID,
        preferredLeadingParentCardID: preferredLeadingParentCardID
    )

    return (
        parentGroups: resolvedParentGroups,
        detachedPositionsByCardID: detachedPositionsByCardID
    )
}

func normalizedIndexBoardDetachedSurfaceItems(
    _ items: [BoardSurfaceItem]
) -> [BoardSurfaceItem] {
    let positionsByCardID = items.reduce(into: [UUID: IndexBoardGridPosition]()) { partialResult, item in
        if let position = item.detachedGridPosition ?? item.gridPosition {
            partialResult[item.cardID] = position
        }
    }
    let normalizedPositions = normalizedIndexBoardDetachedGridPositions(positionsByCardID)
    return items.map { item in
        let position = normalizedPositions[item.cardID] ?? item.detachedGridPosition ?? item.gridPosition
        return BoardSurfaceItem(
            cardID: item.cardID,
            laneParentID: item.laneParentID,
            laneIndex: item.laneIndex,
            slotIndex: item.slotIndex,
            detachedGridPosition: position,
            gridPosition: position,
            parentGroupID: item.parentGroupID
        )
    }
}
