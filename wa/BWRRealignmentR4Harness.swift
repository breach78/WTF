import Foundation
import CoreGraphics

@MainActor
enum BWRRealignmentR4Harness {
    nonisolated static let reportJSONURL = URL(fileURLWithPath: "/tmp/bwr_r4_report.json")
    nonisolated static let reportMarkdownURL = URL(fileURLWithPath: "/tmp/bwr_r4_report.md")

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
            attachReflowSuite(),
            detachToParkingSuite(),
            groupBlockDragSuite(),
            stripCleanupAndDeterminismSuite()
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

    private static func attachReflowSuite() -> SuiteResult {
        var document = hostFixture()
        let projection = BWRSlotBoardProjection.project(document: document)
        let groupBID = UUID(uuidString: "00000000-0000-0000-0000-000000000602")!
        let movingCardID = UUID(uuidString: "00000000-0000-0000-0000-000000000052")!

        guard let pointerRect = projection.placeholderRect(for: .group(groupBID), insertionIndex: 1),
              let target = BWRSlotBoardInteraction.resolveCardDropTarget(
                document: document,
                projection: projection,
                draggingCardIDs: [movingCardID],
                leadCardID: movingCardID,
                pointer: CGPoint(x: pointerRect.midX, y: pointerRect.midY),
                viewportState: BWRViewportState()
              ) else {
            return fail(
                id: "attach-reflow",
                title: "Attach Reflow",
                summary: "group attach target를 계산하지 못했습니다.",
                details: []
            )
        }

        switch target.destination {
        case let .existingHost(.group(groupID), insertionIndex):
            guard groupID == groupBID, insertionIndex == 1 else {
                return fail(
                    id: "attach-reflow",
                    title: "Attach Reflow",
                    summary: "attach target host 또는 insertion index가 예상과 다릅니다.",
                    details: ["groupID=\(groupID)", "insertionIndex=\(insertionIndex)"]
                )
            }
        default:
            return fail(
                id: "attach-reflow",
                title: "Attach Reflow",
                summary: "drag가 group attach 대신 다른 destination으로 해석되었습니다.",
                details: ["destination=\(String(describing: target.destination))"]
            )
        }

        let adjusted = BWRSlotBoardInteraction.adjustedInsertionIndex(
            rawInsertionIndex: 1,
            movingCardIDs: [movingCardID],
            targetHost: .group(groupBID),
            document: document
        )
        _ = BWRDocumentReducer.moveCards(
            document: &document,
            to: .group(groupBID),
            cardIDs: [movingCardID],
            insertionIndex: adjusted
        )
        document = BWRSlotPlacementNormalizer.repairedDocument(document)

        let groupsByID = Dictionary(uniqueKeysWithValues: document.groups.map { ($0.id, $0) })
        let stripsByID = Dictionary(uniqueKeysWithValues: document.parkingStrips.map { ($0.id, $0) })
        guard let movedCard = document.cards.first(where: { $0.id == movingCardID }),
              let placement = movedCard.placement,
              placement == .attached(hostGroupID: groupBID, slotIndex: 1),
              groupsByID[groupBID]?.memberCardIDs == [
                UUID(uuidString: "00000000-0000-0000-0000-000000000053")!,
                movingCardID
              ],
              groupsByID[UUID(uuidString: "00000000-0000-0000-0000-000000000601")!]?.memberCardIDs == [
                UUID(uuidString: "00000000-0000-0000-0000-000000000051")!
              ],
              movedCard.layout == BWRShadowPlacementTransition.shadowLayout(
                for: placement,
                cardStableSortKey: movedCard.stableSortKey,
                groupsByID: groupsByID,
                stripsByID: stripsByID
              ) else {
            return fail(
                id: "attach-reflow",
                title: "Attach Reflow",
                summary: "drop 후 group slot order 또는 shadow layout이 즉시 재흐름되지 않았습니다.",
                details: [
                    "groupA=\(groupsByID[UUID(uuidString: "00000000-0000-0000-0000-000000000601")!]?.memberCardIDs ?? [])",
                    "groupB=\(groupsByID[groupBID]?.memberCardIDs ?? [])"
                ]
            )
        }

        return pass(
            id: "attach-reflow",
            title: "Attach Reflow",
            summary: "group attach drag가 slot placeholder를 통해 해석되고, drop 직후 membership과 shadow layout이 즉시 재흐름됩니다.",
            details: [
                "destinationGroup=\(groupBID.uuidString)",
                "placement=\(String(describing: movedCard.placement))"
            ]
        )
    }

    private static func detachToParkingSuite() -> SuiteResult {
        var document = detachFixture()
        let projection = BWRSlotBoardProjection.project(document: document)
        let movingCardID = UUID(uuidString: "00000000-0000-0000-0000-000000000061")!

        guard let target = BWRSlotBoardInteraction.resolveCardDropTarget(
            document: document,
            projection: projection,
            draggingCardIDs: [movingCardID],
            leadCardID: movingCardID,
            pointer: CGPoint(x: 120, y: 980),
            viewportState: BWRViewportState(
                zoomScale: 1,
                scrollOrigin: BWRPoint(x: 0, y: 620),
                viewportSize: BWRSize(width: 1200, height: 700)
            )
        ) else {
            return fail(
                id: "detach-parking",
                title: "Detach To Parking",
                summary: "parking detach target를 계산하지 못했습니다.",
                details: []
            )
        }

        guard case let .newParkingStrip(originSlot, insertionIndex) = target.destination else {
            return fail(
                id: "detach-parking",
                title: "Detach To Parking",
                summary: "group 밖 drag가 새 parking strip candidate로 해석되지 않았습니다.",
                details: ["destination=\(String(describing: target.destination))"]
            )
        }

        _ = BWRDocumentReducer.moveCardsToParkingStrip(
            document: &document,
            cardIDs: [movingCardID],
            originSlot: originSlot,
            insertionIndex: insertionIndex
        )
        document = BWRSlotPlacementNormalizer.repairedDocument(document)

        let groupsByID = Dictionary(uniqueKeysWithValues: document.groups.map { ($0.id, $0) })
        let stripsByID = Dictionary(uniqueKeysWithValues: document.parkingStrips.map { ($0.id, $0) })
        guard let movedCard = document.cards.first(where: { $0.id == movingCardID }),
              let placement = movedCard.placement,
              placement.kind == .parked,
              document.parkingStrips.count == 1,
              groupsByID[UUID(uuidString: "00000000-0000-0000-0000-000000000701")!]?.memberCardIDs == [
                UUID(uuidString: "00000000-0000-0000-0000-000000000062")!
              ],
              movedCard.layout == BWRShadowPlacementTransition.shadowLayout(
                for: placement,
                cardStableSortKey: movedCard.stableSortKey,
                groupsByID: groupsByID,
                stripsByID: stripsByID
              ) else {
            return fail(
                id: "detach-parking",
                title: "Detach To Parking",
                summary: "drop 후 card가 parking strip으로 이동하지 않았거나 shadow layout이 raw pixel로 남았습니다.",
                details: [
                    "strips=\(document.parkingStrips.map { ($0.row, $0.anchorColumn, $0.cardIDs) })",
                    "placement=\(String(describing: document.cards.first(where: { $0.id == movingCardID })?.placement))"
                ]
            )
        }

        return pass(
            id: "detach-parking",
            title: "Detach To Parking",
            summary: "group 밖 drag가 새 parking strip placeholder로 해석되고, drop 직후 parked placement와 shadow layout으로 수렴합니다.",
            details: [
                "origin=\(originSlot)",
                "stripCount=\(document.parkingStrips.count)"
            ]
        )
    }

    private static func groupBlockDragSuite() -> SuiteResult {
        var document = hostFixture()
        let projection = BWRSlotBoardProjection.project(document: document)
        let groupBID = UUID(uuidString: "00000000-0000-0000-0000-000000000602")!

        guard let target = BWRSlotBoardInteraction.resolveGroupDropTarget(
            projection: projection,
            groupID: groupBID,
            candidateOriginSlot: BWRSlotCoordinate(column: 0, row: 0)
        ) else {
            return fail(
                id: "group-block",
                title: "Group Block Drag",
                summary: "group block drag target를 계산하지 못했습니다.",
                details: []
            )
        }

        let beforeMembers = document.groups.first(where: { $0.id == groupBID })?.memberCardIDs ?? []
        _ = BWRDocumentReducer.moveGroupOrigin(
            document: &document,
            groupID: groupBID,
            originSlot: target.originSlot
        )
        document = BWRSlotPlacementNormalizer.repairedDocument(document)

        guard let movedGroup = document.groups.first(where: { $0.id == groupBID }),
              movedGroup.originSlot == target.originSlot,
              movedGroup.memberCardIDs == beforeMembers,
              target.originSlot != BWRSlotCoordinate(column: 0, row: 0) else {
            return fail(
                id: "group-block",
                title: "Group Block Drag",
                summary: "group block drag collision scan 또는 member order 보존에 실패했습니다.",
                details: [
                    "targetOrigin=\(target.originSlot)",
                    "members=\(document.groups.first(where: { $0.id == groupBID })?.memberCardIDs ?? [])"
                ]
            )
        }

        return pass(
            id: "group-block",
            title: "Group Block Drag",
            summary: "group block drag는 충돌 시 free-origin scan으로 이동하고 내부 slot order는 그대로 유지됩니다.",
            details: [
                "origin=\(target.originSlot)",
                "memberCount=\(beforeMembers.count)"
            ]
        )
    }

    private static func stripCleanupAndDeterminismSuite() -> SuiteResult {
        var document = stripCleanupFixture()
        let movingCardID = UUID(uuidString: "00000000-0000-0000-0000-000000000071")!
        let targetStripID = UUID(uuidString: "00000000-0000-0000-0000-000000000801")!
        let projection = BWRSlotBoardProjection.project(document: document)

        guard let pointerRect = projection.placeholderRect(for: .strip(targetStripID), insertionIndex: 1) else {
            return fail(
                id: "strip-cleanup",
                title: "Strip Cleanup And Determinism",
                summary: "strip insertion placeholder rect를 계산하지 못했습니다.",
                details: []
            )
        }

        let targets = (0..<10).compactMap { _ in
            BWRSlotBoardInteraction.resolveCardDropTarget(
                document: document,
                projection: projection,
                draggingCardIDs: [movingCardID],
                leadCardID: movingCardID,
                pointer: CGPoint(x: pointerRect.midX, y: pointerRect.midY),
                viewportState: BWRViewportState()
            )
        }
        guard targets.count == 10, targets.dropFirst().allSatisfy({ $0 == targets.first }) else {
            return fail(
                id: "strip-cleanup",
                title: "Strip Cleanup And Determinism",
                summary: "같은 hover 입력에서 detach target이 deterministic하지 않습니다.",
                details: targets.map { "\($0)" }
            )
        }

        let adjustedInsertionIndex = BWRSlotBoardInteraction.adjustedInsertionIndex(
            rawInsertionIndex: 1,
            movingCardIDs: [movingCardID],
            targetHost: .strip(targetStripID),
            document: document
        )
        _ = BWRDocumentReducer.moveCards(
            document: &document,
            to: .strip(targetStripID),
            cardIDs: [movingCardID],
            insertionIndex: adjustedInsertionIndex
        )
        document = BWRSlotPlacementNormalizer.repairedDocument(document)

        guard document.parkingStrips.count == 1,
              document.parkingStrips.first?.id == targetStripID,
              document.parkingStrips.first?.cardIDs == [
                UUID(uuidString: "00000000-0000-0000-0000-000000000072")!,
                movingCardID
              ] else {
            return fail(
                id: "strip-cleanup",
                title: "Strip Cleanup And Determinism",
                summary: "strip-to-strip drop 후 empty strip cleanup 또는 immediate reflow가 동작하지 않았습니다.",
                details: ["strips=\(document.parkingStrips.map { ($0.id, $0.cardIDs) })"]
            )
        }

        return pass(
            id: "strip-cleanup",
            title: "Strip Cleanup And Determinism",
            summary: "같은 drag hover는 같은 target을 만들고, strip 이동 후 빈 strip은 commit 시 제거됩니다.",
            details: ["remainingStrip=\(targetStripID.uuidString)"]
        )
    }

    private static func hostFixture() -> BWRDocument {
        let now = Date(timeIntervalSince1970: 40)
        let groupAID = UUID(uuidString: "00000000-0000-0000-0000-000000000601")!
        let groupBID = UUID(uuidString: "00000000-0000-0000-0000-000000000602")!

        let cardA = makeCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000051")!,
            stableSortKey: 1,
            placement: .attached(hostGroupID: groupAID, slotIndex: 0),
            timestamp: now
        )
        let cardB = makeCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000052")!,
            stableSortKey: 2,
            placement: .attached(hostGroupID: groupAID, slotIndex: 1),
            timestamp: now.addingTimeInterval(1)
        )
        let cardC = makeCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000053")!,
            stableSortKey: 3,
            placement: .attached(hostGroupID: groupBID, slotIndex: 0),
            timestamp: now.addingTimeInterval(2)
        )

        return BWRDocument(
            schemaVersion: 2,
            createdAt: now,
            updatedAt: now,
            nextStableSortKey: 4,
            cards: [cardA, cardB, cardC],
            groups: [
                BWRGroup(
                    id: groupAID,
                    name: "A",
                    originSlot: BWRSlotCoordinate(column: 0, row: 0),
                    memberCardIDs: [cardA.id, cardB.id],
                    createdAt: now,
                    updatedAt: now
                ),
                BWRGroup(
                    id: groupBID,
                    name: "B",
                    originSlot: BWRSlotCoordinate(column: 4, row: 0),
                    memberCardIDs: [cardC.id],
                    createdAt: now,
                    updatedAt: now
                )
            ]
        )
    }

    private static func detachFixture() -> BWRDocument {
        let now = Date(timeIntervalSince1970: 50)
        let groupID = UUID(uuidString: "00000000-0000-0000-0000-000000000701")!

        let first = makeCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000061")!,
            stableSortKey: 1,
            placement: .attached(hostGroupID: groupID, slotIndex: 0),
            timestamp: now
        )
        let second = makeCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000062")!,
            stableSortKey: 2,
            placement: .attached(hostGroupID: groupID, slotIndex: 1),
            timestamp: now.addingTimeInterval(1)
        )

        return BWRDocument(
            schemaVersion: 2,
            createdAt: now,
            updatedAt: now,
            nextStableSortKey: 3,
            cards: [first, second],
            groups: [
                BWRGroup(
                    id: groupID,
                    name: "Detach",
                    originSlot: BWRSlotCoordinate(column: 0, row: 0),
                    memberCardIDs: [first.id, second.id],
                    createdAt: now,
                    updatedAt: now
                )
            ]
        )
    }

    private static func stripCleanupFixture() -> BWRDocument {
        let now = Date(timeIntervalSince1970: 60)
        let sourceStripID = UUID(uuidString: "00000000-0000-0000-0000-000000000802")!
        let targetStripID = UUID(uuidString: "00000000-0000-0000-0000-000000000801")!

        let first = makeCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000071")!,
            stableSortKey: 1,
            placement: .parked(stripID: sourceStripID, slotIndex: 0),
            timestamp: now
        )
        let second = makeCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000072")!,
            stableSortKey: 2,
            placement: .parked(stripID: targetStripID, slotIndex: 0),
            timestamp: now.addingTimeInterval(1)
        )

        return BWRDocument(
            schemaVersion: 2,
            createdAt: now,
            updatedAt: now,
            nextStableSortKey: 3,
            cards: [first, second],
            parkingStrips: [
                BWRParkingStrip(
                    id: sourceStripID,
                    row: 4,
                    anchorColumn: 0,
                    cardIDs: [first.id]
                ),
                BWRParkingStrip(
                    id: targetStripID,
                    row: 5,
                    anchorColumn: 0,
                    cardIDs: [second.id]
                )
            ]
        )
    }

    private static func makeCard(
        id: UUID,
        stableSortKey: Int64,
        placement: BWRCardPlacement,
        timestamp: Date
    ) -> BWRCard {
        let layers = BWRCard.defaultLayers(bodyMarkdown: "Card \(stableSortKey)")
        return BWRCard(
            id: id,
            stableSortKey: stableSortKey,
            currentLayerID: layers[0].id,
            placement: placement,
            layout: BWRPoint(x: 0, y: 0),
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
        # BWR Realignment R4 Harness

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
}
