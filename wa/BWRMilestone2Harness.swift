import Foundation

@MainActor
enum BWRMilestone2Harness {
    nonisolated static let reportJSONURL = URL(fileURLWithPath: "/tmp/bwr_m2_report.json")
    nonisolated static let reportMarkdownURL = URL(fileURLWithPath: "/tmp/bwr_m2_report.md")

    struct Report: Codable {
        let generatedAt: String
        let suiteCount: Int
        let failureCount: Int
        let suites: [SuiteResult]
    }

    struct SuiteResult: Codable {
        let id: String
        let title: String
        let status: Status
        let summary: String
        let details: [String]
    }

    enum Status: String, Codable {
        case pass
        case fail
    }

    @discardableResult
    static func runAll() -> Bool {
        let suites = [
            attachDetachReorderSuite(),
            splitPlacementSuite(),
            selectionPrecedenceSuite(),
            cloneArchiveSuite(),
            normalizationAndUndoSuite()
        ]

        let report = Report(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            suiteCount: suites.count,
            failureCount: suites.filter { $0.status == .fail }.count,
            suites: suites
        )

        write(report: report)
        return report.failureCount == 0
    }

    private static func attachDetachReorderSuite() -> SuiteResult {
        let document = BWRReferenceDocument(document: slotFixture())
        guard let groupID = document.liveGroups.first?.id,
              let stripID = document.document.parkingStrips.first?.id else {
            return fail(
                id: "attach-detach",
                title: "Attach Detach Reorder",
                summary: "fixture host를 찾지 못했습니다.",
                details: []
            )
        }

        let groupCards = document.orderedLiveCards(inGroup: groupID)
        let stripCards = BWRSlotOrder.orderedCards(inStrip: stripID, document: document.document)
        guard groupCards.count == 2, stripCards.count == 2 else {
            return fail(
                id: "attach-detach",
                title: "Attach Detach Reorder",
                summary: "fixture host 카드 수가 예상과 다릅니다.",
                details: [
                    "groupCards=\(groupCards.count)",
                    "stripCards=\(stripCards.count)"
                ]
            )
        }

        let firstGroupID = groupCards[0].id
        let movingFromStripID = stripCards[0].id
        let detachingID = groupCards[1].id

        document.addCards(toGroup: groupID, cardIDs: [movingFromStripID])
        document.removeCards(fromGroup: groupID, cardIDs: [detachingID])
        document.setCardLayouts([movingFromStripID: BWRPoint(x: -40, y: 0)])

        let finalGroupOrder = document.orderedLiveCards(inGroup: groupID).map(\.id)
        let finalStripOrder = BWRSlotOrder.orderedCards(inStrip: stripID, document: document.document).map(\.id)
        let globalOrder = document.liveCards.map(\.id)
        let movedCard = document.liveCards.first(where: { $0.id == movingFromStripID })
        let detachedCard = document.liveCards.first(where: { $0.id == detachingID })

        guard finalGroupOrder == [movingFromStripID, firstGroupID],
              finalStripOrder.last == detachingID,
              globalOrder.starts(with: finalGroupOrder),
              movedCard?.placement == .attached(hostGroupID: groupID, slotIndex: 0),
              detachedCard?.placement == .parked(stripID: stripID, slotIndex: finalStripOrder.count - 1) else {
            return fail(
                id: "attach-detach",
                title: "Attach Detach Reorder",
                summary: "attach/detach/reorder command가 slot host 규칙과 어긋났습니다.",
                details: [
                    "groupOrder=\(finalGroupOrder.map(\.uuidString).joined(separator: ","))",
                    "stripOrder=\(finalStripOrder.map(\.uuidString).joined(separator: ","))",
                    "globalOrder=\(globalOrder.map(\.uuidString).joined(separator: ","))"
                ]
            )
        }

        return pass(
            id: "attach-detach",
            title: "Attach Detach Reorder",
            summary: "카드 attach, detach, reorder가 single-host slot 순서로 정규화됩니다.",
            details: [
                "groupOrder=\(finalGroupOrder.count)",
                "stripOrder=\(finalStripOrder.count)"
            ]
        )
    }

    private static func splitPlacementSuite() -> SuiteResult {
        let document = BWRReferenceDocument(document: splitFixture())
        guard let groupID = document.liveGroups.first?.id,
              let stripID = document.document.parkingStrips.first?.id else {
            return fail(
                id: "split",
                title: "Split Placement",
                summary: "split fixture host를 찾지 못했습니다.",
                details: []
            )
        }

        let groupCards = document.orderedLiveCards(inGroup: groupID)
        let stripCards = BWRSlotOrder.orderedCards(inStrip: stripID, document: document.document)
        guard let groupedCard = groupCards.first,
              let parkedCard = stripCards.first else {
            return fail(
                id: "split",
                title: "Split Placement",
                summary: "split 대상 카드를 찾지 못했습니다.",
                details: []
            )
        }

        document.applyLayerMarkdown(cardID: groupedCard.id, layerID: groupedCard.currentLayerID, markdown: "AlphaBeta")
        document.applyLayerMarkdown(cardID: parkedCard.id, layerID: parkedCard.currentLayerID, markdown: "OneTwo")

        guard let groupedSplitID = document.splitCard(cardID: groupedCard.id, atUTF16Location: 5),
              let parkedSplitID = document.splitCard(cardID: parkedCard.id, atUTF16Location: 3),
              let groupedSource = document.liveCards.first(where: { $0.id == groupedCard.id }),
              let groupedSplit = document.liveCards.first(where: { $0.id == groupedSplitID }),
              let parkedSource = document.liveCards.first(where: { $0.id == parkedCard.id }),
              let parkedSplit = document.liveCards.first(where: { $0.id == parkedSplitID }) else {
            return fail(
                id: "split",
                title: "Split Placement",
                summary: "카드 분할 결과를 읽지 못했습니다.",
                details: []
            )
        }

        let groupedOrder = document.orderedLiveCards(inGroup: groupID).map(\.id)
        let parkedOrder = BWRSlotOrder.orderedCards(inStrip: stripID, document: document.document).map(\.id)

        guard groupedSource.currentLayer?.markdown == "Alpha",
              groupedSplit.currentLayer?.markdown == "Beta",
              parkedSource.currentLayer?.markdown == "One",
              parkedSplit.currentLayer?.markdown == "Two",
              groupedOrder.starts(with: [groupedCard.id, groupedSplitID]),
              parkedOrder.starts(with: [parkedCard.id, parkedSplitID]),
              groupedSplit.placement == .attached(hostGroupID: groupID, slotIndex: 1),
              parkedSplit.placement == .parked(stripID: stripID, slotIndex: 1) else {
            return fail(
                id: "split",
                title: "Split Placement",
                summary: "split이 현재 host 다음 slot에 삽입되지 않았습니다.",
                details: [
                    "groupedOrder=\(groupedOrder.map(\.uuidString).joined(separator: ","))",
                    "parkedOrder=\(parkedOrder.map(\.uuidString).joined(separator: ","))"
                ]
            )
        }

        return pass(
            id: "split",
            title: "Split Placement",
            summary: "grouped/parked 카드 split이 현재 visible layer만 나누고 같은 host의 다음 slot에 삽입됩니다.",
            details: [
                "groupedSplit=\(groupedSplitID.uuidString)",
                "parkedSplit=\(parkedSplitID.uuidString)"
            ]
        )
    }

    private static func selectionPrecedenceSuite() -> SuiteResult {
        let document = BWRReferenceDocument(document: slotFixture())
        guard let groupID = document.liveGroups.first?.id,
              let stripID = document.document.parkingStrips.first?.id else {
            return fail(
                id: "selection",
                title: "Selection Precedence",
                summary: "selection fixture host를 찾지 못했습니다.",
                details: []
            )
        }

        let groupSeed = document.orderedLiveCards(inGroup: groupID)
        let stripSeed = BWRSlotOrder.orderedCards(inStrip: stripID, document: document.document)
        guard let selectedGroupCard = groupSeed.first,
              stripSeed.first != nil else {
            return fail(
                id: "selection",
                title: "Selection Precedence",
                summary: "selection fixture 카드가 부족합니다.",
                details: []
            )
        }

        let defaultViewport = BWRViewportState(
            zoomScale: 1.0,
            scrollOrigin: BWRPoint(x: 0, y: Double(document.document.parkingStrips.first?.row ?? 0) * 190.0),
            viewportSize: BWRSize(width: 900, height: 700)
        )

        guard let insertedAfterCardID = document.createCard(
            selectedCardID: selectedGroupCard.id,
            selectedGroupID: nil,
            viewportState: defaultViewport
        ),
        let insertedFromGroupID = document.createCard(
            selectedCardID: nil,
            selectedGroupID: groupID,
            viewportState: defaultViewport
        ),
        let insertedFromViewportID = document.createCard(
            selectedCardID: nil,
            selectedGroupID: nil,
            viewportState: defaultViewport
        ) else {
            return fail(
                id: "selection",
                title: "Selection Precedence",
                summary: "selection precedence createCard 호출에 실패했습니다.",
                details: []
            )
        }

        let groupOrder = document.orderedLiveCards(inGroup: groupID).map(\.id)
        let stripOrder = BWRSlotOrder.orderedCards(inStrip: stripID, document: document.document).map(\.id)

        guard groupOrder.firstIndex(of: insertedAfterCardID) == 1,
              groupOrder.last == insertedFromGroupID,
              stripOrder.last == insertedFromViewportID else {
            return fail(
                id: "selection",
                title: "Selection Precedence",
                summary: "새 카드 생성 우선순위가 selectedCard -> selectedGroup -> viewport strip 순서를 따르지 않았습니다.",
                details: [
                    "groupOrder=\(groupOrder.map(\.uuidString).joined(separator: ","))",
                    "stripOrder=\(stripOrder.map(\.uuidString).joined(separator: ","))"
                ]
            )
        }

        return pass(
            id: "selection",
            title: "Selection Precedence",
            summary: "새 카드 생성이 selected card, selected group, viewport strip 우선순위로 slot target을 결정합니다.",
            details: [
                "groupCount=\(groupOrder.count)",
                "stripCount=\(stripOrder.count)"
            ]
        )
    }

    private static func cloneArchiveSuite() -> SuiteResult {
        var documentModel = slotFixture()
        let cloneGroupID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!

        guard let baseGroupID = documentModel.groups.first?.id,
              let stripID = documentModel.parkingStrips.first?.id else {
            return fail(
                id: "clone",
                title: "Clone Archive Collapse",
                summary: "clone fixture host를 초기화하지 못했습니다.",
                details: []
            )
        }

        let cloneLayers = BWRCard.defaultLayers(
            bodyMarkdown: "Clone source",
            treatmentMarkdown: "Clone treatment",
            scenarioMarkdown: "Clone scenario"
        )
        let groupClone = BWRCard(
            stableSortKey: documentModel.allocateStableSortKey(),
            cloneGroupID: cloneGroupID,
            colorHex: "FDE68A",
            currentLayerID: cloneLayers[0].id,
            placement: .attached(hostGroupID: baseGroupID, slotIndex: documentModel.groups[0].memberCardIDs.count),
            layout: BWRPoint(x: 0, y: 0),
            createdAt: Date(timeIntervalSince1970: 50),
            updatedAt: Date(timeIntervalSince1970: 50),
            layers: cloneLayers
        )
        let stripClone = BWRCard(
            stableSortKey: documentModel.allocateStableSortKey(),
            cloneGroupID: cloneGroupID,
            colorHex: "FDE68A",
            currentLayerID: cloneLayers[0].id,
            placement: .parked(stripID: stripID, slotIndex: documentModel.parkingStrips[0].cardIDs.count),
            layout: BWRPoint(x: 0, y: 0),
            createdAt: Date(timeIntervalSince1970: 51),
            updatedAt: Date(timeIntervalSince1970: 51),
            layers: cloneLayers
        )
        documentModel.cards.append(groupClone)
        documentModel.cards.append(stripClone)
        documentModel.groups[0].memberCardIDs.append(groupClone.id)
        documentModel.parkingStrips[0].cardIDs.append(stripClone.id)

        let document = BWRReferenceDocument(document: documentModel)
        let cloneInGroupID = groupClone.id
        let survivingCloneID = stripClone.id
        let normalGroupCardID = document.orderedLiveCards(inGroup: baseGroupID)[0].id

        document.archiveGroup(groupID: baseGroupID)

        let survivingClone = document.liveCards.first(where: { $0.id == survivingCloneID })
        let removedCloneStillExists = document.document.cards.contains(where: { $0.id == cloneInGroupID })
        let archivedNormal = document.archivedCards.first(where: { $0.id == normalGroupCardID })

        guard document.archivedGroups.contains(where: { $0.id == baseGroupID }),
              survivingClone != nil,
              survivingClone?.cloneGroupID == nil,
              !removedCloneStillExists,
              archivedNormal != nil else {
            return fail(
                id: "clone",
                title: "Clone Archive Collapse",
                summary: "그룹 아카이브 시 clone hard-delete / collapse 규칙이 지켜지지 않았습니다.",
                details: [
                    "survivingCloneNil=\(survivingClone == nil)",
                    "survivingCloneGroup=\(survivingClone?.cloneGroupID?.uuidString ?? "nil")",
                    "removedCloneStillExists=\(removedCloneStillExists)"
                ]
            )
        }

        document.deleteCards(cardIDs: [survivingCloneID])
        let archivedSurvivor = document.archivedCards.first(where: { $0.id == survivingCloneID })
        guard archivedSurvivor != nil else {
            return fail(
                id: "clone",
                title: "Clone Archive Collapse",
                summary: "collapse 후 단일 clone survivor는 archive 대상이 되어야 합니다.",
                details: []
            )
        }

        return pass(
            id: "clone",
            title: "Clone Archive Collapse",
            summary: "그룹 삭제 시 group-host clone은 hard delete되고 남은 sibling은 clone 해제 후 일반 archive 흐름으로 돌아갑니다.",
            details: [
                "archivedGroups=\(document.archivedGroups.count)",
                "archivedCards=\(document.archivedCards.count)"
            ]
        )
    }

    private static func normalizationAndUndoSuite() -> SuiteResult {
        let corrupt = corruptFixture()
        do {
            _ = try BWRSlotPlacementNormalizer.validatedForLoad(corrupt)
            return fail(
                id: "normalize-undo",
                title: "Normalization And Undo",
                summary: "strict load validation이 multi-host corruption을 막지 못했습니다.",
                details: []
            )
        } catch {
            // expected
        }

        let document = BWRReferenceDocument(document: corrupt)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        document.bindUndoManager(undoManager)

        guard let groupID = document.liveGroups.first?.id else {
            return fail(
                id: "normalize-undo",
                title: "Normalization And Undo",
                summary: "runtime normalize 후 group을 찾지 못했습니다.",
                details: []
            )
        }

        let normalizedGroupOrder = document.orderedLiveCards(inGroup: groupID).map(\.id)
        let normalizedStripCount = document.document.parkingStrips.first?.cardIDs.count ?? 0
        guard normalizedGroupOrder.count == 2,
              normalizedStripCount == 1 else {
            return fail(
                id: "normalize-undo",
                title: "Normalization And Undo",
                summary: "runtime normalize가 duplicate host/state를 정리하지 못했습니다.",
                details: [
                    "groupOrder=\(normalizedGroupOrder.map(\.uuidString).joined(separator: ","))",
                    "stripCount=\(normalizedStripCount)"
                ]
            )
        }

        guard let firstCard = document.orderedLiveCards(inGroup: groupID).first,
              let secondCard = document.orderedLiveCards(inGroup: groupID).last else {
            return fail(
                id: "normalize-undo",
                title: "Normalization And Undo",
                summary: "언두 대상 카드를 찾지 못했습니다.",
                details: []
            )
        }

        document.applyLayerMarkdown(
            cardID: firstCard.id,
            layerID: firstCard.currentLayerID,
            markdown: "Edited text survives structural undo",
            registerUndo: false
        )

        performUndoStep(undoManager) {
            document.removeCards(fromGroup: groupID, cardIDs: [secondCard.id])
        }

        let detachedHost = BWRSlotOrder.host(for: secondCard.id, document: document.document)
        undoManager.undo()
        let restoredHost = BWRSlotOrder.host(for: secondCard.id, document: document.document)
        let editedFirstCard = document.liveCards.first(where: { $0.id == firstCard.id })
        undoManager.redo()
        let redoneHost = BWRSlotOrder.host(for: secondCard.id, document: document.document)

        guard detachedHost != nil,
              restoredHost == .group(groupID),
              redoneHost != .group(groupID),
              editedFirstCard?.currentLayer?.markdown == "Edited text survives structural undo" else {
            return fail(
                id: "normalize-undo",
                title: "Normalization And Undo",
                summary: "load/undo normalization 또는 text/structural undo 경계가 유지되지 않았습니다.",
                details: [
                    "detachedHost=\(String(describing: detachedHost))",
                    "restoredHost=\(String(describing: restoredHost))",
                    "redoneHost=\(String(describing: redoneHost))"
                ]
            )
        }

        return pass(
            id: "normalize-undo",
            title: "Normalization And Undo",
            summary: "runtime/load normalization이 single-host invariants를 복원하고 structural undo가 text undo를 오염시키지 않습니다.",
            details: [
                "groupOrder=\(normalizedGroupOrder.count)",
                "canUndo=\(undoManager.canUndo)"
            ]
        )
    }

    private static func slotFixture() -> BWRDocument {
        let now = Date(timeIntervalSince1970: 100)
        let groupID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let stripID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!

        let alpha = makeCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            stableSortKey: 1,
            placement: .attached(hostGroupID: groupID, slotIndex: 0),
            layout: BWRPoint(x: 0, y: 0),
            colorHex: "F8FAFC",
            bodyMarkdown: "Alpha",
            timestamp: now
        )
        let bravo = makeCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            stableSortKey: 2,
            placement: .attached(hostGroupID: groupID, slotIndex: 1),
            layout: BWRPoint(x: 240, y: 0),
            colorHex: "E0F2FE",
            bodyMarkdown: "Bravo",
            timestamp: now.addingTimeInterval(1)
        )
        let charlie = makeCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            stableSortKey: 3,
            placement: .parked(stripID: stripID, slotIndex: 0),
            layout: BWRPoint(x: 0, y: 760),
            colorHex: "DCFCE7",
            bodyMarkdown: "Charlie",
            timestamp: now.addingTimeInterval(2)
        )
        let delta = makeCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            stableSortKey: 4,
            placement: .parked(stripID: stripID, slotIndex: 1),
            layout: BWRPoint(x: 240, y: 760),
            colorHex: "FEF3C7",
            bodyMarkdown: "Delta",
            timestamp: now.addingTimeInterval(3)
        )

        return BWRDocument(
            schemaVersion: 2,
            createdAt: now,
            updatedAt: now,
            nextStableSortKey: 5,
            cards: [alpha, bravo, charlie, delta],
            groups: [
                BWRGroup(
                    id: groupID,
                    name: "Sequence A",
                    originSlot: BWRSlotCoordinate(column: 0, row: 0),
                    memberCardIDs: [alpha.id, bravo.id],
                    createdAt: now,
                    updatedAt: now
                )
            ],
            parkingStrips: [
                BWRParkingStrip(
                    id: stripID,
                    row: 4,
                    anchorColumn: 0,
                    cardIDs: [charlie.id, delta.id]
                )
            ]
        )
    }

    private static func splitFixture() -> BWRDocument {
        let base = slotFixture()
        return BWRDocument(
            schemaVersion: base.schemaVersion,
            createdAt: base.createdAt,
            updatedAt: base.updatedAt,
            nextStableSortKey: base.nextStableSortKey,
            cards: Array(base.cards.prefix(3)),
            groups: base.groups,
            parkingStrips: [
                BWRParkingStrip(
                    id: base.parkingStrips[0].id,
                    row: base.parkingStrips[0].row,
                    anchorColumn: base.parkingStrips[0].anchorColumn,
                    cardIDs: [base.cards[2].id]
                )
            ]
        )
    }

    private static func corruptFixture() -> BWRDocument {
        let now = Date(timeIntervalSince1970: 200)
        let groupID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let stripID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!

        let alpha = makeCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            stableSortKey: 1,
            placement: .attached(hostGroupID: groupID, slotIndex: 0),
            layout: BWRPoint(x: 0, y: 0),
            colorHex: "F8FAFC",
            bodyMarkdown: "Alpha",
            timestamp: now
        )
        let bravo = makeCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            stableSortKey: 2,
            placement: nil,
            layout: BWRPoint(x: 240, y: 0),
            colorHex: "E0F2FE",
            bodyMarkdown: "Bravo",
            timestamp: now.addingTimeInterval(1)
        )
        let charlie = makeCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
            stableSortKey: 3,
            placement: .parked(stripID: stripID, slotIndex: 0),
            layout: BWRPoint(x: 0, y: 760),
            colorHex: "DCFCE7",
            bodyMarkdown: "Charlie",
            timestamp: now.addingTimeInterval(2)
        )
        var archived = makeCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
            stableSortKey: 4,
            placement: .parked(stripID: stripID, slotIndex: 3),
            layout: BWRPoint(x: 480, y: 760),
            colorHex: "FEF3C7",
            bodyMarkdown: "Archived",
            timestamp: now.addingTimeInterval(3)
        )
        archived.isArchived = true
        archived.archivedAt = now.addingTimeInterval(10)

        return BWRDocument(
            schemaVersion: 2,
            createdAt: now,
            updatedAt: now,
            nextStableSortKey: 5,
            cards: [alpha, bravo, charlie, archived],
            groups: [
                BWRGroup(
                    id: groupID,
                    name: "Corrupt Group",
                    originSlot: BWRSlotCoordinate(column: 0, row: 0),
                    memberCardIDs: [alpha.id, bravo.id, alpha.id],
                    createdAt: now,
                    updatedAt: now
                )
            ],
            parkingStrips: [
                BWRParkingStrip(
                    id: stripID,
                    row: 4,
                    anchorColumn: 0,
                    cardIDs: [alpha.id, charlie.id, archived.id]
                )
            ]
        )
    }

    private static func makeCard(
        id: UUID,
        stableSortKey: Int64,
        placement: BWRCardPlacement?,
        layout: BWRPoint,
        colorHex: String,
        bodyMarkdown: String,
        timestamp: Date
    ) -> BWRCard {
        let layers = BWRCard.defaultLayers(
            bodyMarkdown: bodyMarkdown,
            treatmentMarkdown: "Treatment \(bodyMarkdown)",
            scenarioMarkdown: "Scenario \(bodyMarkdown)"
        )
        return BWRCard(
            id: id,
            stableSortKey: stableSortKey,
            colorHex: colorHex,
            currentLayerID: layers[0].id,
            placement: placement,
            layout: layout,
            createdAt: timestamp,
            updatedAt: timestamp,
            layers: layers
        )
    }

    private static func pass(id: String, title: String, summary: String, details: [String]) -> SuiteResult {
        SuiteResult(id: id, title: title, status: .pass, summary: summary, details: details)
    }

    private static func fail(id: String, title: String, summary: String, details: [String]) -> SuiteResult {
        SuiteResult(id: id, title: title, status: .fail, summary: summary, details: details)
    }

    private static func write(report: Report) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(report).write(to: reportJSONURL, options: .atomic)

        let markdown = """
        # BWR Milestone 2 Harness

        - generatedAt: \(report.generatedAt)
        - suiteCount: \(report.suiteCount)
        - failureCount: \(report.failureCount)

        \(report.suites.map(markdownLine(for:)).joined(separator: "\n\n"))
        """
        try? markdown.write(to: reportMarkdownURL, atomically: true, encoding: .utf8)
    }

    private static func markdownLine(for suite: SuiteResult) -> String {
        let details = suite.details.map { "- \($0)" }.joined(separator: "\n")
        return """
        ## [\(suite.status.rawValue.uppercased())] \(suite.title)
        \(suite.summary)
        \(details.isEmpty ? "" : "\n" + details)
        """
    }

    private static func performUndoStep(_ undoManager: UndoManager, action: () -> Void) {
        undoManager.beginUndoGrouping()
        action()
        undoManager.endUndoGrouping()
    }
}
