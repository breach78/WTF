import SwiftUI
import AppKit

struct IndexBoardScaffoldView: View {
    let session: IndexBoardSessionState
    let sourceTitle: String
    let activeCardCount: Int
    let onClose: () -> Void

    private var boardLabelText: String {
        if let parentID = session.sourceParentID {
            return parentID.uuidString
        }
        return "root"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.94, blue: 0.89),
                    Color(red: 0.90, green: 0.88, blue: 0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Board View")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.86))
                        Text("Phase 0 스캐폴딩")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.black.opacity(0.52))
                    }

                    Spacer(minLength: 0)

                    Button("작업창으로 돌아가기") {
                        onClose()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.black.opacity(0.78))
                }

                VStack(alignment: .leading, spacing: 10) {
                    scaffoldMetricRow(label: "소스 컬럼", value: sourceTitle)
                    scaffoldMetricRow(label: "source parent", value: boardLabelText)
                    scaffoldMetricRow(label: "source depth", value: "\(session.sourceDepth)")
                    scaffoldMetricRow(label: "카드 수", value: "\(activeCardCount)")
                    scaffoldMetricRow(label: "줌", value: String(format: "%.2f", session.zoomScale))
                }
                .padding(18)
                .background(Color.white.opacity(0.64))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text("현재 Phase에서는 pane-level mode, session state, source parent 기반 진입/복귀 상태만 연결되어 있습니다.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.68))

                Spacer(minLength: 0)
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    @ViewBuilder
    private func scaffoldMetricRow(label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.black.opacity(0.46))
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.82))
                .textSelection(.enabled)
        }
    }
}

extension ScenarioWriterView {


    func resolvedIndexBoardSurfaceProjection(
        referenceSurfaceProjection: BoardSurfaceProjection? = nil,
        preferredLeadingParentCardID: UUID? = nil,
        overridingGroupPositionsByParentID: [UUID: IndexBoardGridPosition] = [:],
        overridingDetachedPositionsByCardID: [UUID: IndexBoardGridPosition]? = nil,
        overridingTempStrips: [IndexBoardTempStripState]? = nil
    ) -> BoardSurfaceProjection? {
        guard let session = activeIndexBoardSession else { return nil }
        let tempContainer = resolvedIndexBoardTempContainer()
        let tempContainerID = tempContainer?.id
        let liveCards = resolvedLiveIndexBoardSourceCards(for: session)
        let sourceParentIDs = Set(liveCards.compactMap { $0.parent?.id })
        let regularCards = liveCards.filter { card in
            guard let tempContainer else { return true }
            if card.id == tempContainer.id { return false }
            return card.parent?.id != tempContainer.id
        }
        let tempChildCards = liveIndexBoardTempChildCards().filter { card in
            !sourceParentIDs.contains(card.id)
        }
        var orderedCardIDs: [UUID] = []
        orderedCardIDs.reserveCapacity(regularCards.count + tempChildCards.count)
        var seenCardIDs: Set<UUID> = []
        for card in regularCards + tempChildCards {
            if seenCardIDs.insert(card.id).inserted {
                orderedCardIDs.append(card.id)
            }
        }

        var cardsByParentGroupID: [BoardSurfaceParentGroupID: [SceneCard]] = [:]
        var parentGroupOrder: [BoardSurfaceParentGroupID] = []
        for card in regularCards {
            let groupID: BoardSurfaceParentGroupID = {
                if let parentID = card.parent?.id {
                    return .parent(parentID)
                }
                return .root
            }()
            if cardsByParentGroupID[groupID] == nil {
                parentGroupOrder.append(groupID)
            }
            cardsByParentGroupID[groupID, default: []].append(card)
        }

        let storedGroupPositions =
            (activeIndexBoardSession?.groupGridPositionByParentID ?? [:])
            .merging(overridingGroupPositionsByParentID) { _, override in override }
        var nextDefaultColumn = 0
        var provisionalParentGroups: [BoardSurfaceParentGroupPlacement] = []
        provisionalParentGroups.reserveCapacity(parentGroupOrder.count)
        var tempDescendantCache: [UUID: Bool] = [:]

        func resolvedIsTempDescendant(_ cardID: UUID?) -> Bool {
            guard let cardID, let tempContainerID else { return false }
            if let cached = tempDescendantCache[cardID] {
                return cached
            }

            var traversalOrder: [UUID] = []
            traversalOrder.reserveCapacity(8)
            var visited: Set<UUID> = []
            var currentID: UUID? = cardID
            var result = false

            while let currentIDValue = currentID {
                if let cached = tempDescendantCache[currentIDValue] {
                    result = cached
                    break
                }
                if currentIDValue == tempContainerID {
                    result = true
                    break
                }
                guard visited.insert(currentIDValue).inserted else {
                    result = false
                    break
                }
                traversalOrder.append(currentIDValue)
                guard let card = findCard(by: currentIDValue) else {
                    result = false
                    break
                }
                currentID = card.parent?.id
            }

            for traversedID in traversalOrder {
                tempDescendantCache[traversedID] = result
            }
            return result
        }

        for groupID in parentGroupOrder {
            let groupCards = cardsByParentGroupID[groupID] ?? []
            guard !groupCards.isEmpty else { continue }
            let parentCard = groupID.parentCardID.flatMap { findCard(by: $0) }
            let fallbackOrigin = IndexBoardGridPosition(column: nextDefaultColumn, row: 0)
            let resolvedOrigin = groupID.parentCardID.flatMap { storedGroupPositions[$0] } ?? fallbackOrigin
            let isTempGroup = resolvedIsTempDescendant(groupID.parentCardID)
            nextDefaultColumn = max(nextDefaultColumn, resolvedOrigin.column + max(1, groupCards.count))
            provisionalParentGroups.append(
                BoardSurfaceParentGroupPlacement(
                    id: groupID,
                    parentCardID: groupID.parentCardID,
                    origin: resolvedOrigin,
                    cardIDs: groupCards.map(\.id),
                    titleText: indexBoardLaneLabel(
                        for: parentCard,
                        laneParentID: groupID.parentCardID,
                        tempContainerID: tempContainer?.id
                    ),
                    subtitleText: indexBoardLaneSubtitle(
                        for: parentCard,
                        childCards: groupCards,
                        laneParentID: groupID.parentCardID,
                        tempContainerID: tempContainer?.id
                    ),
                    colorToken: indexBoardLaneColorToken(for: parentCard, childCards: groupCards),
                    isMainline: !isTempGroup,
                    isTempGroup: isTempGroup
                )
            )
        }

        let tempProvisionalParentGroups = provisionalParentGroups.filter(\.isTempGroup)
        let mainlineProvisionalParentGroups = provisionalParentGroups.filter { !$0.isTempGroup }
        let detachedGridPositionByCardID =
            overridingDetachedPositionsByCardID
            ?? activeIndexBoardSession?.detachedGridPositionByCardID
            ?? [:]
        let maxGroupRow = provisionalParentGroups.map(\.origin.row).max() ?? 0
        let parkingRow = maxGroupRow + 2
        var nextParkingColumn = 0
        var rawDetachedPositionByCardID: [UUID: IndexBoardGridPosition] = [:]
        rawDetachedPositionByCardID.reserveCapacity(tempChildCards.count)
        for card in tempChildCards {
            rawDetachedPositionByCardID[card.id] = detachedGridPositionByCardID[card.id] ?? {
                defer { nextParkingColumn += 1 }
                return IndexBoardGridPosition(column: nextParkingColumn, row: parkingRow)
            }()
        }

        let resolvedTempStrips = resolvedIndexBoardTempStrips(
            persistedStrips: overridingTempStrips ?? session.tempStrips,
            tempGroups: tempProvisionalParentGroups,
            detachedPositionsByCardID: rawDetachedPositionByCardID
        )
        let tempStripLayout = resolvedIndexBoardTempStripSurfaceLayout(
            strips: resolvedTempStrips,
            tempGroupWidthsByParentID: Dictionary(
                uniqueKeysWithValues: tempProvisionalParentGroups.compactMap { placement in
                    placement.parentCardID.map { ($0, placement.width) }
                }
            )
        )
        let positionedTempParentGroups = tempProvisionalParentGroups.map { placement in
            guard let parentCardID = placement.parentCardID,
                  let resolvedOrigin = tempStripLayout.groupOriginByParentID[parentCardID] else {
                return placement
            }
            return BoardSurfaceParentGroupPlacement(
                id: placement.id,
                parentCardID: placement.parentCardID,
                origin: resolvedOrigin,
                cardIDs: placement.cardIDs,
                titleText: placement.titleText,
                subtitleText: placement.subtitleText,
                colorToken: placement.colorToken,
                isMainline: placement.isMainline,
                isTempGroup: placement.isTempGroup
            )
        }
        rawDetachedPositionByCardID = tempStripLayout.detachedPositionsByCardID.merging(rawDetachedPositionByCardID) { lhs, _ in lhs }

        let sortedParentGroups = (mainlineProvisionalParentGroups + positionedTempParentGroups).sorted(by: indexBoardSurfaceGroupSort)

        let normalizedSurfaceLayout = normalizedIndexBoardSurfaceLayout(
            parentGroups: sortedParentGroups,
            detachedPositionsByCardID: rawDetachedPositionByCardID,
            referenceParentGroups: referenceSurfaceProjection?.parentGroups,
            referenceDetachedPositionsByCardID: referenceSurfaceProjection.map { projection in
                indexBoardDetachedGridPositionsByCardID(from: projection)
            },
            preferredLeadingParentCardID: preferredLeadingParentCardID
        )
        let normalizedParentGroups = normalizedSurfaceLayout.parentGroups.sorted(by: indexBoardSurfaceGroupSort)

        var lanes: [BoardSurfaceLane] = []
        lanes.reserveCapacity(normalizedParentGroups.count + (tempChildCards.isEmpty ? 0 : 1))
        var laneIndexByParentID: [UUID?: Int] = [:]
        for placement in normalizedParentGroups {
            let laneIndex = lanes.count
            laneIndexByParentID[placement.parentCardID] = laneIndex
            lanes.append(
                BoardSurfaceLane(
                    parentCardID: placement.parentCardID,
                    laneIndex: laneIndex,
                    labelText: placement.titleText,
                    subtitleText: placement.subtitleText,
                    colorToken: placement.colorToken,
                    isTempLane: placement.isTempGroup
                )
            )
        }

        let tempLaneIndex: Int? = {
            guard let tempContainer,
                  !tempChildCards.isEmpty else { return nil }
            let laneIndex = lanes.count
            laneIndexByParentID[tempContainer.id] = laneIndex
            lanes.append(
                BoardSurfaceLane(
                    parentCardID: tempContainer.id,
                    laneIndex: laneIndex,
                    labelText: "Temp",
                    subtitleText: "트리 밖 카드 \(tempChildCards.count)장",
                    colorToken: nil,
                    isTempLane: true
                )
            )
            return laneIndex
        }()

        var surfaceItems: [BoardSurfaceItem] = []
        surfaceItems.reserveCapacity(orderedCardIDs.count)

        for placement in normalizedParentGroups {
            let laneIndex = laneIndexByParentID[placement.parentCardID] ?? 0
            for (offset, cardID) in placement.cardIDs.enumerated() {
                surfaceItems.append(
                    BoardSurfaceItem(
                        cardID: cardID,
                        laneParentID: placement.parentCardID,
                        laneIndex: laneIndex,
                        slotIndex: nil,
                        detachedGridPosition: nil,
                        gridPosition: IndexBoardGridPosition(
                            column: placement.origin.column + offset,
                            row: placement.origin.row
                        ),
                        parentGroupID: placement.id
                    )
                )
            }
        }

        if let tempContainer,
           let tempLaneIndex {
            for card in tempChildCards {
                let resolvedPosition = normalizedSurfaceLayout.detachedPositionsByCardID[card.id]
                    ?? rawDetachedPositionByCardID[card.id]
                    ?? IndexBoardGridPosition(column: 0, row: parkingRow)
                surfaceItems.append(
                    BoardSurfaceItem(
                        cardID: card.id,
                        laneParentID: tempContainer.id,
                        laneIndex: tempLaneIndex,
                        slotIndex: nil,
                        detachedGridPosition: resolvedPosition,
                        gridPosition: resolvedPosition,
                        parentGroupID: nil
                    )
                )
            }
        }

        let sortedItems = surfaceItems.sorted(by: indexBoardSurfaceItemGridSort)
        let startAnchorPosition =
            normalizedParentGroups
            .filter { !$0.isTempGroup }
            .min(by: indexBoardSurfaceGroupSort)?
            .origin
            ?? normalizedParentGroups.min(by: indexBoardSurfaceGroupSort)?.origin
            ?? IndexBoardGridPosition(column: 0, row: 0)
        return BoardSurfaceProjection(
            source: session.source,
            startAnchor: BoardSurfaceStartAnchor(
                gridPosition: startAnchorPosition,
                labelText: "START"
            ),
            lanes: lanes,
            parentGroups: normalizedParentGroups,
            tempStrips: resolvedTempStrips,
            surfaceItems: sortedItems,
            orderedCardIDs: sortedItems.map(\.cardID)
        )
    }


    private func resolvedLiveIndexBoardSourceCards(for session: IndexBoardSessionState) -> [SceneCard] {
        let sourceIDSet = Set(session.sourceCardIDs)
        let originalIndexByID = Dictionary(uniqueKeysWithValues: session.sourceCardIDs.enumerated().map { index, cardID in
            (cardID, index)
        })

        return sourceIDSet.compactMap { findCard(by: $0) }
            .sorted { lhs, rhs in
                let lhsParentOrder = lhs.parent?.orderIndex ?? lhs.orderIndex
                let rhsParentOrder = rhs.parent?.orderIndex ?? rhs.orderIndex
                if lhsParentOrder != rhsParentOrder {
                    return lhsParentOrder < rhsParentOrder
                }

                let lhsParentID = lhs.parent?.id
                let rhsParentID = rhs.parent?.id
                if lhsParentID != rhsParentID {
                    let lhsFallback = originalIndexByID[lhs.id] ?? .max
                    let rhsFallback = originalIndexByID[rhs.id] ?? .max
                    if lhsFallback != rhsFallback {
                        return lhsFallback < rhsFallback
                    }
                    return (lhsParentID?.uuidString ?? "") < (rhsParentID?.uuidString ?? "")
                }

                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }

                let lhsFallback = originalIndexByID[lhs.id] ?? .max
                let rhsFallback = originalIndexByID[rhs.id] ?? .max
                if lhsFallback != rhsFallback {
                    return lhsFallback < rhsFallback
                }

                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func resolvedIndexBoardProjection(
        from surfaceProjection: BoardSurfaceProjection
    ) -> IndexBoardProjection {
        let groups = surfaceProjection.parentGroups.compactMap { placement -> IndexBoardGroupProjection? in
            let childCards = placement.cardIDs.compactMap { findCard(by: $0) }
            guard !childCards.isEmpty else { return nil }
            let parentCard = placement.parentCardID.flatMap { findCard(by: $0) }
            return IndexBoardGroupProjection(
                id: placement.parentCardID.map { IndexBoardGroupID.parent($0) } ?? .root,
                parentCard: parentCard,
                title: placement.titleText,
                subtitle: placement.subtitleText,
                statusText: indexBoardLaneStatusText(
                    for: parentCard,
                    childCards: childCards,
                    laneParentID: placement.parentCardID,
                    isTempLane: placement.isTempGroup
                ),
                isTempGroup: placement.isTempGroup,
                childCards: childCards
            )
        }

        return IndexBoardProjection(
            source: surfaceProjection.source,
            orderedCardIDs: surfaceProjection.orderedCardIDs,
            groups: groups
        )
    }

    func resolvedIndexBoardProjection() -> IndexBoardProjection? {
        guard let surfaceProjection = resolvedIndexBoardSurfaceProjection() else { return nil }
        return resolvedIndexBoardProjection(from: surfaceProjection)
    }

    private func resolvedIndexBoardMainlineGroupIDs(
        from groups: [BoardSurfaceParentGroupPlacement]
    ) -> Set<BoardSurfaceParentGroupID> {
        guard let startGroup = groups.min(by: { lhs, rhs in
            if lhs.origin.row != rhs.origin.row {
                return lhs.origin.row < rhs.origin.row
            }
            if lhs.origin.column != rhs.origin.column {
                return lhs.origin.column < rhs.origin.column
            }
            return lhs.id.id < rhs.id.id
        }) else {
            return []
        }

        let groupsByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        var visited: Set<BoardSurfaceParentGroupID> = [startGroup.id]
        var queue: [BoardSurfaceParentGroupID] = [startGroup.id]

        while let currentID = queue.first {
            queue.removeFirst()
            guard let current = groupsByID[currentID] else { continue }
            for candidate in groups where !visited.contains(candidate.id) {
                if indexBoardSurfaceGroupsAreConnected(current, candidate) {
                    visited.insert(candidate.id)
                    queue.append(candidate.id)
                }
            }
        }

        return visited
    }

    private func normalizedIndexBoardParentGroups(
        _ groups: [BoardSurfaceParentGroupPlacement],
        mainlineGroupIDs: Set<BoardSurfaceParentGroupID>
    ) -> [BoardSurfaceParentGroupPlacement] {
        let mainlineGroups = groups.filter { mainlineGroupIDs.contains($0.id) }
        let rowShift = mainlineGroups.map(\.origin.row).min() ?? 0
        let columnShift = mainlineGroups.map(\.origin.column).min() ?? 0

        return groups.map { group in
            let isMainline = mainlineGroupIDs.contains(group.id)
            let shiftedOrigin: IndexBoardGridPosition
            if isMainline {
                shiftedOrigin = IndexBoardGridPosition(
                    column: group.origin.column - columnShift,
                    row: group.origin.row - rowShift
                )
            } else {
                shiftedOrigin = group.origin
            }

            return BoardSurfaceParentGroupPlacement(
                id: group.id,
                parentCardID: group.parentCardID,
                origin: shiftedOrigin,
                cardIDs: group.cardIDs,
                titleText: group.titleText,
                subtitleText: group.subtitleText,
                colorToken: group.colorToken,
                isMainline: isMainline,
                isTempGroup: !isMainline
            )
        }
    }

    private func indexBoardSurfaceGroupsAreConnected(
        _ lhs: BoardSurfaceParentGroupPlacement,
        _ rhs: BoardSurfaceParentGroupPlacement
    ) -> Bool {
        if lhs.origin.row == rhs.origin.row {
            return lhs.occupiedColumns.upperBound + 1 == rhs.occupiedColumns.lowerBound ||
                rhs.occupiedColumns.upperBound + 1 == lhs.occupiedColumns.lowerBound
        }

        if abs(lhs.origin.row - rhs.origin.row) == 1 {
            return lhs.occupiedColumns.overlaps(rhs.occupiedColumns)
        }

        return false
    }

    private func indexBoardSurfaceGroupSort(
        _ lhs: BoardSurfaceParentGroupPlacement,
        _ rhs: BoardSurfaceParentGroupPlacement
    ) -> Bool {
        if lhs.origin.row != rhs.origin.row {
            return lhs.origin.row < rhs.origin.row
        }
        if lhs.origin.column != rhs.origin.column {
            return lhs.origin.column < rhs.origin.column
        }
        return lhs.id.id < rhs.id.id
    }

    private func indexBoardSurfaceItemGridSort(
        _ lhs: BoardSurfaceItem,
        _ rhs: BoardSurfaceItem
    ) -> Bool {
        let lhsPosition = lhs.gridPosition ?? lhs.detachedGridPosition ?? IndexBoardGridPosition(column: .max / 4, row: .max / 4)
        let rhsPosition = rhs.gridPosition ?? rhs.detachedGridPosition ?? IndexBoardGridPosition(column: .max / 4, row: .max / 4)
        if lhsPosition.row != rhsPosition.row {
            return lhsPosition.row < rhsPosition.row
        }
        if lhsPosition.column != rhsPosition.column {
            return lhsPosition.column < rhsPosition.column
        }
        return lhs.cardID.uuidString < rhs.cardID.uuidString
    }

    func indexBoardLaneLabel(
        for parentCard: SceneCard?,
        laneParentID: UUID?,
        tempContainerID: UUID?
    ) -> String {
        if let tempContainerID, laneParentID == tempContainerID {
            return "Temp"
        }
        if let parentCard {
            return firstMeaningfulLine(from: parentCard.content) ?? "(내용 없는 부모 카드)"
        }
        let trimmedScenarioTitle = scenario.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedScenarioTitle.isEmpty ? "(루트)" : trimmedScenarioTitle
    }

    func indexBoardLaneSubtitle(
        for parentCard: SceneCard?,
        childCards: [SceneCard],
        laneParentID: UUID?,
        tempContainerID: UUID?
    ) -> String {
        if let tempContainerID, laneParentID == tempContainerID {
            return "root -> 노트 -> temp 아래의 임시 카드 \(childCards.count)장"
        }
        if let parentCard {
            let lines = parentCard.content
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if lines.count >= 2 {
                return lines[1]
            }
            return "하위 카드 \(childCards.count)장"
        }
        return "루트 카드 \(childCards.count)장"
    }

    func indexBoardLaneColorToken(for parentCard: SceneCard?, childCards: [SceneCard]) -> String? {
        parentCard?.colorHex ?? childCards.first?.colorHex
    }

    func indexBoardLaneStatusText(
        for parentCard: SceneCard?,
        childCards: [SceneCard],
        laneParentID: UUID?,
        isTempLane: Bool
    ) -> String {
        if isTempLane {
            return "TEMP · \(childCards.count)"
        }
        if laneParentID == nil && parentCard == nil {
            return "ROOT · \(childCards.count)"
        }
        let category = parentCard?.category ?? childCards.first?.category ?? ScenarioCardCategory.uncategorized
        return "\(category) · \(childCards.count)"
    }

    func indexBoardGroupTitle(for parentCard: SceneCard?) -> String {
        indexBoardLaneLabel(for: parentCard, laneParentID: parentCard?.id, tempContainerID: nil)
    }

    func indexBoardGroupSubtitle(for parentCard: SceneCard?, childCards: [SceneCard]) -> String {
        indexBoardLaneSubtitle(for: parentCard, childCards: childCards, laneParentID: parentCard?.id, tempContainerID: nil)
    }

    func indexBoardGroupStatusText(for parentCard: SceneCard?, childCards: [SceneCard]) -> String {
        if parentCard == nil {
            return "ROOT · \(childCards.count)"
        }
        let category = parentCard?.category ?? childCards.first?.category ?? ScenarioCardCategory.uncategorized
        return "\(category) · \(childCards.count)"
    }


    func handleIndexBoardCardClick(_ card: SceneCard, orderedCardIDs: [UUID]) {
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommandPressed = flags.contains(.command)
        let isShiftPressed = flags.contains(.shift)

        finishEditing(reason: .transition)

        if isCommandPressed && isShiftPressed {
            handleIndexBoardRangeClick(card, orderedCardIDs: orderedCardIDs, additive: true)
        } else if isShiftPressed {
            handleIndexBoardRangeClick(card, orderedCardIDs: orderedCardIDs, additive: false)
        } else if isCommandPressed {
            handleIndexBoardCommandClick(card)
        } else {
            selectedCardIDs = [card.id]
            keyboardRangeSelectionAnchorCardID = card.id
        }

        changeActiveCard(to: card, deferToMainAsync: false)
        isMainViewFocused = true
    }

    func handleIndexBoardCardDragStart(cardID: UUID, movingCardIDs: [UUID]) {
        guard let card = findCard(by: cardID) else { return }

        finishEditing(reason: .transition)

        let movingIDSet = Set(movingCardIDs)
        if !movingIDSet.isEmpty,
           selectedCardIDs.isSuperset(of: movingIDSet),
           movingIDSet.contains(cardID) {
            selectedCardIDs = movingIDSet
        } else {
            selectedCardIDs = [cardID]
        }

        keyboardRangeSelectionAnchorCardID = cardID
        changeActiveCard(to: card, deferToMainAsync: false)
        isMainViewFocused = true
    }

    func handleIndexBoardCommandClick(_ card: SceneCard) {
        if selectedCardIDs.contains(card.id) {
            selectedCardIDs.remove(card.id)
            if keyboardRangeSelectionAnchorCardID == card.id {
                keyboardRangeSelectionAnchorCardID = selectedCardIDs.first
            }
        } else {
            selectedCardIDs.insert(card.id)
            if keyboardRangeSelectionAnchorCardID == nil {
                keyboardRangeSelectionAnchorCardID = card.id
            }
        }
    }

    func handleIndexBoardRangeClick(_ card: SceneCard, orderedCardIDs: [UUID], additive: Bool) {
        guard let anchorID = resolvedIndexBoardRangeAnchorID(in: orderedCardIDs) else {
            selectedCardIDs = [card.id]
            keyboardRangeSelectionAnchorCardID = card.id
            return
        }

        keyboardRangeSelectionAnchorCardID = anchorID
        let rangeIDs = indexBoardRangeSelectionIDs(
            in: orderedCardIDs,
            anchorID: anchorID,
            targetID: card.id
        )

        if additive {
            selectedCardIDs.formUnion(rangeIDs)
        } else {
            selectedCardIDs = rangeIDs
        }
    }

    func resolvedIndexBoardRangeAnchorID(in orderedCardIDs: [UUID]) -> UUID? {
        if let anchorID = keyboardRangeSelectionAnchorCardID,
           selectedCardIDs.contains(anchorID),
           orderedCardIDs.contains(anchorID) {
            return anchorID
        }

        if selectedCardIDs.count == 1,
           let selectedID = selectedCardIDs.first,
           orderedCardIDs.contains(selectedID) {
            return selectedID
        }

        if let activeCardID, selectedCardIDs.contains(activeCardID), orderedCardIDs.contains(activeCardID) {
            return activeCardID
        }

        return orderedCardIDs.first(where: { selectedCardIDs.contains($0) })
    }

    func indexBoardRangeSelectionIDs(
        in orderedCardIDs: [UUID],
        anchorID: UUID,
        targetID: UUID
    ) -> Set<UUID> {
        guard let anchorIndex = orderedCardIDs.firstIndex(of: anchorID),
              let targetIndex = orderedCardIDs.firstIndex(of: targetID) else {
            return [targetID]
        }

        let lowerBound = min(anchorIndex, targetIndex)
        let upperBound = max(anchorIndex, targetIndex)
        return Set(orderedCardIDs[lowerBound ... upperBound])
    }

    func applyIndexBoardMarqueeSelection(_ cardIDs: Set<UUID>, orderedCardIDs: [UUID]) {
        finishEditing(reason: .transition)

        let orderedSelection = orderedCardIDs.filter { cardIDs.contains($0) }
        selectedCardIDs = Set(orderedSelection)
        keyboardRangeSelectionAnchorCardID = orderedSelection.first

        if let primaryCardID = orderedSelection.first,
           let card = findCard(by: primaryCardID) {
            changeActiveCard(to: card, deferToMainAsync: false)
        }

        isMainViewFocused = true
    }

    func clearIndexBoardSelection() {
        selectedCardIDs = []
        keyboardRangeSelectionAnchorCardID = nil
        activeCardID = nil
        synchronizeActiveRelationState(for: nil)
        isMainViewFocused = true
    }

    func deleteSelectedIndexBoardCards() {
        performIndexBoardDeletion(
            cards: selectedCardsForDeletion(),
            preferredAnchorCardID: activeCardID,
            actionName: "보드 카드 삭제"
        )
    }

    func deleteIndexBoardCardFromContextMenu(_ cardID: UUID) {
        let targetIDs: [UUID]
        if selectedCardIDs.contains(cardID) {
            let selectedIDSet = selectedCardIDs
            let orderedSelection = resolvedIndexBoardSurfaceProjection()?.orderedCardIDs.filter { selectedIDSet.contains($0) } ?? []
            targetIDs = orderedSelection.isEmpty ? [cardID] : orderedSelection
        } else {
            targetIDs = [cardID]
        }

        performIndexBoardDeletion(
            cards: targetIDs.compactMap { findCard(by: $0) },
            preferredAnchorCardID: cardID,
            actionName: "보드 카드 삭제"
        )
    }

    func deleteIndexBoardParentGroupFromContextMenu(_ parentCardID: UUID) {
        guard let parentCard = findCard(by: parentCardID),
              !isIndexBoardTempContainerCard(parentCard),
              !isIndexBoardNoteContainerCard(parentCard) else { return }

        performIndexBoardDeletion(
            cards: [parentCard],
            preferredAnchorCardID: parentCardID,
            actionName: "보드 그룹 삭제"
        )
    }

    private func performIndexBoardDeletion(
        cards: [SceneCard],
        preferredAnchorCardID: UUID?,
        actionName: String
    ) {
        guard isIndexBoardActive else { return }
        guard !cards.isEmpty else { return }

        let orderedCardIDsBefore = resolvedIndexBoardSurfaceProjection()?.orderedCardIDs ?? cards.map(\.id)
        let previousState = captureScenarioState()
        let deleteOutcome = resolveDeleteSelectionOutcome(from: cards)
        let removedIDs = deleteOutcome.idsToRemove
        let didChangeContent = deleteOutcome.didChangeContent
        guard didChangeContent || !removedIDs.isEmpty else { return }

        archiveRemovedCards(removedIDs)
        cleanupIndexBoardSessionAfterDelete(removedIDs, persist: false)

        let nextCandidate = resolvedNextIndexBoardCandidateAfterDelete(
            orderedCardIDsBefore: orderedCardIDsBefore,
            removedIDs: removedIDs,
            preferredAnchorCardID: preferredAnchorCardID ?? cards.first?.id
        )
        updateIndexBoardSelectionAfterDelete(
            removedIDs: removedIDs,
            nextCandidate: nextCandidate
        )

        if let surfaceProjection = resolvedIndexBoardSurfaceProjection(
            preferredLeadingParentCardID: nextCandidate?.parent?.id
        ) {
            persistIndexBoardSurfacePresentation(surfaceProjection)
        } else {
            indexBoardRuntime.updateSession(for: scenario.id, paneID: paneContextID) { _ in }
        }

        commitCardMutation(
            previousState: previousState,
            actionName: actionName,
            forceSnapshot: true
        )
        isMainViewFocused = true
    }

    private func cleanupIndexBoardSessionAfterDelete(_ removedIDs: Set<UUID>, persist: Bool) {
        guard !removedIDs.isEmpty else { return }
        indexBoardRuntime.updateSession(for: scenario.id, paneID: paneContextID, persist: persist) { session in
            session.sourceCardIDs.removeAll { removedIDs.contains($0) }
            session.collapsedLaneParentIDs.subtract(removedIDs)
            session.showsBackByCardID = session.showsBackByCardID.filter { !removedIDs.contains($0.key) }
            session.detachedGridPositionByCardID = session.detachedGridPositionByCardID.filter { !removedIDs.contains($0.key) }
            session.groupGridPositionByParentID = session.groupGridPositionByParentID.filter { !removedIDs.contains($0.key) }
            session.tempStrips = session.tempStrips.compactMap { strip in
                let members = strip.members.filter { !removedIDs.contains($0.id) }
                guard !members.isEmpty else { return nil }
                return IndexBoardTempStripState(
                    id: strip.id,
                    row: strip.row,
                    anchorColumn: strip.anchorColumn,
                    members: members
                )
            }
            if let lastPresentedCardID = session.lastPresentedCardID,
               removedIDs.contains(lastPresentedCardID) {
                session.lastPresentedCardID = nil
            }
            if let pendingRevealCardID = session.pendingRevealCardID,
               removedIDs.contains(pendingRevealCardID) {
                session.pendingRevealCardID = nil
            }
        }
    }

    private func resolvedNextIndexBoardCandidateAfterDelete(
        orderedCardIDsBefore: [UUID],
        removedIDs: Set<UUID>,
        preferredAnchorCardID: UUID?
    ) -> SceneCard? {
        let remainingIDs = orderedCardIDsBefore.filter { !removedIDs.contains($0) }
        guard !remainingIDs.isEmpty else { return nil }

        if let preferredAnchorCardID,
           let anchorIndex = orderedCardIDsBefore.firstIndex(of: preferredAnchorCardID) {
            if anchorIndex + 1 < orderedCardIDsBefore.count {
                for candidateID in orderedCardIDsBefore[(anchorIndex + 1)...] where !removedIDs.contains(candidateID) {
                    if let card = findCard(by: candidateID), !card.isArchived { return card }
                }
            }
            if anchorIndex > 0 {
                for candidateID in orderedCardIDsBefore[..<anchorIndex].reversed() where !removedIDs.contains(candidateID) {
                    if let card = findCard(by: candidateID), !card.isArchived { return card }
                }
            }
        }

        for candidateID in remainingIDs {
            if let card = findCard(by: candidateID), !card.isArchived {
                return card
            }
        }
        return nil
    }

    private func updateIndexBoardSelectionAfterDelete(
        removedIDs: Set<UUID>,
        nextCandidate: SceneCard?
    ) {
        selectedCardIDs.subtract(removedIDs)
        let activeWasRemoved = activeCardID.map { removedIDs.contains($0) } ?? false

        if activeWasRemoved {
            if let nextCandidate {
                selectedCardIDs = [nextCandidate.id]
                keyboardRangeSelectionAnchorCardID = nextCandidate.id
                changeActiveCard(
                    to: nextCandidate,
                    shouldFocusMain: false,
                    deferToMainAsync: false,
                    force: true
                )
            } else {
                selectedCardIDs = []
                keyboardRangeSelectionAnchorCardID = nil
                activeCardID = nil
                resetActiveRelationStateCache()
                synchronizeActiveRelationState(for: nil)
            }
            return
        }

        if let anchorID = keyboardRangeSelectionAnchorCardID,
           removedIDs.contains(anchorID) {
            keyboardRangeSelectionAnchorCardID = selectedCardIDs.first
        }

        if selectedCardIDs.isEmpty,
           let activeCardID,
           !removedIDs.contains(activeCardID) {
            selectedCardIDs = [activeCardID]
            keyboardRangeSelectionAnchorCardID = activeCardID
        }
    }

    func updateIndexBoardGroupPosition(parentCardID: UUID, position: IndexBoardGridPosition?) {
        guard isIndexBoardActive else { return }
        indexBoardRuntime.updateSession(for: scenario.id, paneID: paneContextID) { session in
            if let position {
                session.groupGridPositionByParentID[parentCardID] = position
            } else {
                session.groupGridPositionByParentID.removeValue(forKey: parentCardID)
            }
        }
    }

    private func indexBoardRowMajorPredecessorGroup(
        in surfaceProjection: BoardSurfaceProjection,
        targetOrigin: IndexBoardGridPosition
    ) -> BoardSurfaceParentGroupPlacement? {
        surfaceProjection.parentGroups
            .filter { !$0.isTempGroup }
            .last { placement in
                if placement.origin.row != targetOrigin.row {
                    return placement.origin.row < targetOrigin.row
                }
                return placement.origin.column <= targetOrigin.column
            }
    }

    private func resolvedIndexBoardParentCreationInsertionContext(
        surfaceProjection: BoardSurfaceProjection,
        targetOrigin: IndexBoardGridPosition
    ) -> (parent: SceneCard?, index: Int) {
        let sourceParent = activeIndexBoardSession?.source.parentID.flatMap { findCard(by: $0) }
        guard let predecessorGroup = indexBoardRowMajorPredecessorGroup(
            in: surfaceProjection,
            targetOrigin: targetOrigin
        ), let predecessorParent = predecessorGroup.parentCardID.flatMap({ findCard(by: $0) }) else {
            return (sourceParent, 0)
        }

        let predecessorContainer: SceneCard? = {
            guard let candidate = predecessorParent.parent else { return nil }
            return isIndexBoardTempDescendant(cardID: candidate.id) ? nil : candidate
        }()
        let insertionParent = predecessorContainer ?? sourceParent

        guard predecessorParent.parent?.id == insertionParent?.id else {
            return (insertionParent, liveOrderedSiblings(parent: insertionParent).count)
        }

        return (insertionParent, predecessorParent.orderIndex + 1)
    }

    private func resolvedIndexBoardParentCreationCategory(
        selectedCards: [SceneCard],
        insertionParent: SceneCard?
    ) -> String? {
        func isSemanticParent(_ card: SceneCard?) -> Bool {
            guard let card else { return false }
            return !isIndexBoardNoteContainerCard(card) && !isIndexBoardTempContainerCard(card)
        }

        if isSemanticParent(insertionParent) {
            return insertionParent?.category
        }

        if let selectedCategory = selectedCards.lazy.compactMap(\.category).first(where: {
            $0 != ScenarioCardCategory.note
        }) {
            return selectedCategory
        }

        let sourceParent = activeIndexBoardSession?.source.parentID.flatMap { findCard(by: $0) }
        if isSemanticParent(sourceParent) {
            return sourceParent?.category
        }

        return selectedCards.first?.category
    }

    func createIndexBoardParentFromSelection() {
        guard isIndexBoardActive,
              !selectedCardIDs.isEmpty,
              let surfaceProjection = resolvedIndexBoardSurfaceProjection() else { return }

        let selectedItems = surfaceProjection.surfaceItems.filter { selectedCardIDs.contains($0.cardID) }
            .sorted(by: indexBoardSurfaceItemGridSort)
        let selectedCards = selectedItems.compactMap { item in
            findCard(by: item.cardID)
        }
        guard !selectedCards.isEmpty else { return }

        let targetOrigin = selectedItems.compactMap { $0.gridPosition ?? $0.detachedGridPosition }
            .min { lhs, rhs in
                if lhs.row != rhs.row { return lhs.row < rhs.row }
                return lhs.column < rhs.column
            } ?? IndexBoardGridPosition(column: 0, row: 0)
        let insertionContext = resolvedIndexBoardParentCreationInsertionContext(
            surfaceProjection: surfaceProjection,
            targetOrigin: targetOrigin
        )

        let previousState = captureScenarioState()
        var createdParent: SceneCard?
        let oldParents = selectedCards.map(\.parent)

        scenario.performBatchedCardMutation {
            let insertionParent = insertionContext.parent
            let insertionIndex = min(
                max(0, insertionContext.index),
                liveOrderedSiblings(parent: insertionParent).count
            )
            let newParentCategory = resolvedIndexBoardParentCreationCategory(
                selectedCards: selectedCards,
                insertionParent: insertionParent
            )
            let newParent = SceneCard(
                content: "",
                orderIndex: insertionIndex,
                parent: insertionParent,
                scenario: scenario,
                category: newParentCategory
            )

            for sibling in liveOrderedSiblings(parent: insertionParent) where sibling.orderIndex >= insertionIndex {
                sibling.orderIndex += 1
            }
            scenario.cards.append(newParent)

            for (childIndex, card) in selectedCards.enumerated() {
                let previousParent = card.parent
                card.parent = newParent
                card.orderIndex = childIndex
                card.isFloating = false
                synchronizeMovedSubtreeCategoryIfNeeded(
                    for: card,
                    oldParent: previousParent,
                    newParent: newParent
                )
            }

            normalizeIndices(parent: insertionParent)
            normalizeIndices(parent: newParent)
            for oldParent in oldParents {
                if oldParent?.id != insertionParent?.id {
                    normalizeIndices(parent: oldParent)
                }
            }

            createdParent = newParent
        }

        guard let createdParent else { return }

        indexBoardRuntime.updateSession(for: scenario.id, paneID: paneContextID) { session in
            session.sourceCardIDs = mergedIndexBoardSourceCardIDs(
                session.sourceCardIDs,
                persistedIDs: selectedCards.map(\.id)
            )
            for card in selectedCards {
                session.detachedGridPositionByCardID.removeValue(forKey: card.id)
            }
        }
        updateIndexBoardGroupPosition(parentCardID: createdParent.id, position: targetOrigin)

        selectedCardIDs = Set(selectedCards.map(\.id))
        keyboardRangeSelectionAnchorCardID = selectedCards.first?.id
        if let firstSelectedCard = selectedCards.first {
            changeActiveCard(to: firstSelectedCard, deferToMainAsync: false)
            requestIndexBoardReveal(cardID: firstSelectedCard.id)
        }
        commitCardMutation(
            previousState: previousState,
            actionName: "보드 부모 카드 생성"
        )
    }

    func toggleIndexBoardCardFace(_ card: SceneCard) {
        guard isIndexBoardActive else { return }
        let nextShowsBack = !(activeIndexBoardSession?.showsBackByCardID[card.id] ?? false)
        indexBoardRuntime.updateSession(for: scenario.id, paneID: paneContextID) { session in
            session.showsBackByCardID[card.id] = nextShowsBack
        }
    }

    @ViewBuilder
    func indexBoardCanvas(size: CGSize) -> some View {
        if let surfaceProjection = resolvedIndexBoardSurfaceProjection() {
            let referencedCardIDs = Array(
                Set(surfaceProjection.orderedCardIDs + surfaceProjection.parentGroups.compactMap(\.parentCardID))
            ).sorted { $0.uuidString < $1.uuidString }
            let storedSummaryRecords = store.indexBoardSummaryRecordsByScenarioID[scenario.id] ?? [:]
            let referencedSummaryRecordsByCardID = Dictionary(
                uniqueKeysWithValues: referencedCardIDs.compactMap { cardID in
                    storedSummaryRecords[cardID]?.sanitizedForStorage.map { (cardID, $0) }
                }
            )
            let referencedDigestSnapshotsByCardID = referencedCardIDs.reduce(
                into: [UUID: IndexBoardCanvasDigestSnapshot]()
            ) { partialResult, cardID in
                guard let digest = aiCardDigestCache[cardID] else { return }
                partialResult[cardID] = IndexBoardCanvasDigestSnapshot(
                    contentHash: digest.contentHash,
                    shortSummary: digest.shortSummary,
                    updatedAt: digest.updatedAt
                )
            }
            let derivedPayload = indexBoardCanvasDerivedCache.resolve(
                surfaceProjection: surfaceProjection,
                referencedCardIDs: referencedCardIDs,
                cardsVersion: scenarioCardsVersion,
                summaryRecordsByCardID: referencedSummaryRecordsByCardID,
                digestSnapshotsByCardID: referencedDigestSnapshotsByCardID
            ) {
                resolvedIndexBoardProjection(from: surfaceProjection)
            } buildContent: {
                let cardsByID = Dictionary(
                    uniqueKeysWithValues: referencedCardIDs.compactMap { cardID in
                        findCard(by: cardID).map { (cardID, $0) }
                    }
                )
                let summaryByCardID = Dictionary(
                    uniqueKeysWithValues: referencedCardIDs.compactMap { cardID in
                        resolvedIndexBoardSummary(for: cardID).map { (cardID, $0) }
                    }
                )
                return (
                    cardsByID: cardsByID,
                    summaryByCardID: summaryByCardID
                )
            }
            let projection = derivedPayload.projection
            let boardThemePreset = IndexBoardThemePreset(rawValue: indexBoardThemePresetID) ?? .currentDefault
            let zoomScale = clampedIndexBoardZoomScale
            let scrollOffset = activeIndexBoardSession?.scrollOffset ?? .zero
            let showsBackByCardID = activeIndexBoardSession?.showsBackByCardID ?? [:]
            let revealCardID = activeIndexBoardSession?.pendingRevealCardID
            let revealRequestToken = activeIndexBoardSession?.revealRequestToken ?? 0
            IndexBoardPhaseThreeView(
                surfaceProjection: derivedPayload.surfaceProjection,
                projection: derivedPayload.projection,
                sourceTitle: indexBoardSourceTitle(for: derivedPayload.surfaceProjection.source.parentID),
                canvasSize: size,
                theme: IndexBoardRenderTheme(
                    usesDarkAppearance: isDarkAppearanceActive,
                    backgroundColorHex: backgroundColorHex,
                    darkBackgroundColorHex: darkBackgroundColorHex,
                    cardBaseColorHex: cardActiveColorHex,
                    cardActiveColorHex: cardActiveColorHex,
                    darkCardBaseColorHex: darkCardActiveColorHex,
                    darkCardActiveColorHex: darkCardActiveColorHex,
                    boardBackgroundStartHex: boardThemePreset.lightBoardBackgroundStartHex(fallback: backgroundColorHex),
                    boardBackgroundEndHex: boardThemePreset.lightBoardBackgroundEndHex(fallback: backgroundColorHex),
                    darkBoardBackgroundStartHex: boardThemePreset.darkBoardBackgroundStartHex(fallback: darkBackgroundColorHex),
                    darkBoardBackgroundEndHex: boardThemePreset.darkBoardBackgroundEndHex(fallback: darkBackgroundColorHex),
                    groupBackgroundHex: boardThemePreset.lightGroupBackgroundHex,
                    darkGroupBackgroundHex: boardThemePreset.darkGroupBackgroundHex,
                    groupBorderHex: boardThemePreset.lightGroupBorderHex,
                    darkGroupBorderHex: boardThemePreset.darkGroupBorderHex,
                    tabBackgroundHex: boardThemePreset.lightTabBackgroundHex,
                    darkTabBackgroundHex: boardThemePreset.darkTabBackgroundHex,
                    accentHex: boardThemePreset.lightAccentHex(fallback: cardActiveColorHex),
                    darkAccentHex: boardThemePreset.darkAccentHex(fallback: darkCardActiveColorHex)
                ),
                cardsByID: derivedPayload.cardsByID,
                activeCardID: activeCardID,
                selectedCardIDs: selectedCardIDs,
                summaryByCardID: derivedPayload.summaryByCardID,
                showsBackByCardID: showsBackByCardID,
                zoomScale: zoomScale,
                scrollOffset: scrollOffset,
                revealCardID: revealCardID,
                revealRequestToken: revealRequestToken,
                editorDraftBinding: Binding(
                    get: { indexBoardEditorDraft },
                    set: { newValue in
                        guard let newValue else {
                            indexBoardEditorDraft = nil
                            return
                        }
                        updateIndexBoardEditorDraft(newValue)
                    }
                ),
                editorSummary: resolvedIndexBoardSummary(for: indexBoardEditorDraft?.cardID),
                onClose: closeIndexBoard,
                onCreateTempCard: {
                    _ = createIndexBoardTempCard()
                },
                onCreateTempCardAt: { position in
                    _ = createIndexBoardTempCard(at: position)
                },
                onCreateParentFromSelection: {
                    createIndexBoardParentFromSelection()
                },
                onSetParentGroupTemp: { parentCardID, isTemp in
                    setIndexBoardParentGroupTemp(
                        parentCardID: parentCardID,
                        isTemp: isTemp,
                        projection: derivedPayload.projection
                    )
                },
                onSetCardColor: { cardID, hex in
                    guard let card = findCard(by: cardID) else { return }
                    setCardColor(card, hex: hex)
                },
                onDeleteCard: { cardID in
                    deleteIndexBoardCardFromContextMenu(cardID)
                },
                onDeleteParentGroup: { parentCardID in
                    deleteIndexBoardParentGroupFromContextMenu(parentCardID)
                },
                onCardTap: { card in
                    handleIndexBoardCardClick(card, orderedCardIDs: surfaceProjection.orderedCardIDs)
                },
                onCardDragStart: { movingCardIDs, draggedCardID in
                    handleIndexBoardCardDragStart(
                        cardID: draggedCardID,
                        movingCardIDs: movingCardIDs
                    )
                },
                onCardOpen: { card in
                    presentIndexBoardEditor(for: card)
                },
                onParentCardOpen: { parentCardID in
                    guard let parentCard = findCard(by: parentCardID) else { return }
                    presentIndexBoardEditor(for: parentCard)
                },
                onCardFaceToggle: { card in
                    toggleIndexBoardCardFace(card)
                },
                allowsInlineEditing: indexBoardEditorDraft == nil,
                onInlineEditingChange: { isEditing in
                    isIndexBoardInlineEditing = isEditing
                },
                onInlineCardEditCommit: { cardID, contentText in
                    commitIndexBoardInlineEdit(cardID: cardID, contentText: contentText)
                },
                onZoomScaleChange: { scale in
                    setIndexBoardZoomScale(scale)
                },
                onZoomStep: { delta in
                    stepIndexBoardZoom(by: delta)
                },
                onZoomReset: {
                    resetIndexBoardZoom()
                },
                onScrollOffsetChange: { offset in
                    updateIndexBoardScrollOffset(offset)
                },
                onViewportFinalize: { zoomScale, scrollOffset in
                    persistIndexBoardViewport(
                        zoomScale: zoomScale,
                        scrollOffset: scrollOffset
                    )
                },
                onShowCheckpoint: {
                    presentNamedCheckpointDialog()
                },
                onToggleHistory: {
                    toggleHistoryPanel()
                },
                onToggleAIChat: {
                    toggleAIChat()
                },
                onToggleTimeline: {
                    toggleTimeline()
                },
                isHistoryVisible: showHistoryBar,
                isAIChatVisible: showAIChat,
                isTimelineVisible: showTimeline,
                onCardMove: { cardID, target in
                    commitIndexBoardCardMove(
                        cardID: cardID,
                        target: target,
                        projection: projection
                    )
                },
                onCardMoveSelection: { cardIDs, draggedCardID, target in
                    commitIndexBoardCardMoveSelection(
                        cardIDs: cardIDs,
                        draggedCardID: draggedCardID,
                        target: target,
                        projection: projection
                    )
                },
                onMarqueeSelectionChange: { cardIDs in
                    applyIndexBoardMarqueeSelection(
                        cardIDs,
                        orderedCardIDs: surfaceProjection.orderedCardIDs
                    )
                },
                onClearSelection: {
                    clearIndexBoardSelection()
                },
                onGroupMove: { groupID, targetIndex in
                    commitIndexBoardGroupMove(
                        groupID: groupID,
                        targetIndex: targetIndex,
                        projection: projection
                    )
                },
                onParentGroupMove: { target in
                    commitIndexBoardParentGroupMove(
                        target: target,
                        projection: projection
                    )
                },
                onCancelEditor: {
                    saveIndexBoardEditor()
                },
                onSaveEditor: {
                    saveIndexBoardEditor()
                }
            )
        } else if let session = activeIndexBoardSession {
            IndexBoardScaffoldView(
                session: session,
                sourceTitle: indexBoardSourceTitle(for: session.sourceParentID),
                activeCardCount: session.sourceCardIDs.count,
                onClose: closeIndexBoard
            )
        } else {
            Color.clear
                .frame(width: size.width, height: size.height)
        }
    }

}
