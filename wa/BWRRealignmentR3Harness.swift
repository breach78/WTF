import Foundation
import CoreGraphics

@MainActor
enum BWRRealignmentR3Harness {
    nonisolated static let reportJSONURL = URL(fileURLWithPath: "/tmp/bwr_r3_report.json")
    nonisolated static let reportMarkdownURL = URL(fileURLWithPath: "/tmp/bwr_r3_report.md")

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
            groupCollisionScanSuite(),
            parkingStripDeterminismSuite(),
            cardAndPlaceholderRectSuite(),
            deterministicProjectionSuite()
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

    private static func groupCollisionScanSuite() -> SuiteResult {
        let document = collisionFixture()
        let projection = BWRSlotBoardProjection.project(document: document)
        guard projection.groupFrames.count == 2 else {
            return fail(
                id: "group-collision",
                title: "Group Collision Scan",
                summary: "projection group 수가 예상과 다릅니다.",
                details: ["groups=\(projection.groupFrames.count)"]
            )
        }

        let first = projection.groupFrames[0]
        let second = projection.groupFrames[1]
        guard first.resolvedOriginSlot == BWRSlotCoordinate(column: 0, row: 0),
              second.resolvedOriginSlot != first.resolvedOriginSlot,
              !first.rect.intersects(second.rect) else {
            return fail(
                id: "group-collision",
                title: "Group Collision Scan",
                summary: "group origin collision scan이 deterministic free-origin을 찾지 못했습니다.",
                details: [
                    "firstOrigin=\(first.resolvedOriginSlot)",
                    "secondOrigin=\(second.resolvedOriginSlot)",
                    "intersects=\(first.rect.intersects(second.rect))"
                ]
            )
        }

        return pass(
            id: "group-collision",
            title: "Group Collision Scan",
            summary: "겹치는 group origin 입력이 row-major free-origin scan으로 안정적으로 분리됩니다.",
            details: [
                "firstOrigin=\(first.resolvedOriginSlot)",
                "secondOrigin=\(second.resolvedOriginSlot)"
            ]
        )
    }

    private static func parkingStripDeterminismSuite() -> SuiteResult {
        let document = stripFixture()
        let projection = BWRSlotBoardProjection.project(document: document)
        guard projection.stripFrames.count == 2 else {
            return fail(
                id: "strip-determinism",
                title: "Parking Strip Determinism",
                summary: "projection strip 수가 예상과 다릅니다.",
                details: ["strips=\(projection.stripFrames.count)"]
            )
        }

        let first = projection.stripFrames[0]
        let second = projection.stripFrames[1]
        guard first.resolvedOriginSlot == BWRSlotCoordinate(column: 0, row: 3),
              second.resolvedOriginSlot == BWRSlotCoordinate(column: 0, row: 4),
              !first.rect.intersects(second.rect) else {
            return fail(
                id: "strip-determinism",
                title: "Parking Strip Determinism",
                summary: "strip row scan이 anchor collision을 deterministic하게 아래로 밀지 못했습니다.",
                details: [
                    "firstOrigin=\(first.resolvedOriginSlot)",
                    "secondOrigin=\(second.resolvedOriginSlot)"
                ]
            )
        }

        return pass(
            id: "strip-determinism",
            title: "Parking Strip Determinism",
            summary: "겹치는 parking strip이 anchor column을 유지한 채 아래 row-major scan으로 안정적으로 배치됩니다.",
            details: [
                "firstOrigin=\(first.resolvedOriginSlot)",
                "secondOrigin=\(second.resolvedOriginSlot)"
            ]
        )
    }

    private static func cardAndPlaceholderRectSuite() -> SuiteResult {
        let document = slotFixture()
        let projection = BWRSlotBoardProjection.project(
            document: document,
            expandedCardIDs: [UUID(uuidString: "00000000-0000-0000-0000-000000000002")!]
        )
        guard let group = document.groups.first,
              let firstCardID = group.memberCardIDs.first,
              let secondCardID = group.memberCardIDs.dropFirst().first,
              let firstCard = projection.cardRectsByID[firstCardID],
              let secondCard = projection.cardRectsByID[secondCardID],
              let placeholder = projection.placeholderRect(for: .group(group.id), insertionIndex: 1),
              let blockPlaceholder = projection.groupBlockPlaceholderRect(
                groupID: group.id,
                candidateOriginSlot: BWRSlotCoordinate(column: 4, row: 1)
              ) else {
            return fail(
                id: "rects",
                title: "Card And Placeholder Rects",
                summary: "projection rect 계산에 필요한 객체를 찾지 못했습니다.",
                details: []
            )
        }

        guard secondCard.cardRect.width > firstCard.cardRect.width,
              placeholder.width < firstCard.slotRect.width,
              placeholder.minX >= firstCard.slotRect.minX,
              blockPlaceholder.minX == 960,
              blockPlaceholder.minY == 190 else {
            return fail(
                id: "rects",
                title: "Card And Placeholder Rects",
                summary: "card rect 또는 placeholder rect derivation이 기대와 다릅니다.",
                details: [
                    "firstCardRect=\(firstCard.cardRect)",
                    "secondCardRect=\(secondCard.cardRect)",
                    "placeholder=\(placeholder)",
                    "blockPlaceholder=\(blockPlaceholder)"
                ]
            )
        }

        return pass(
            id: "rects",
            title: "Card And Placeholder Rects",
            summary: "slot rect, inline-expanded card rect, insertion placeholder, block placeholder가 모두 같은 geometry helper로 계산됩니다.",
            details: [
                "firstSlot=\(firstCard.slotRect)",
                "placeholder=\(placeholder)"
            ]
        )
    }

    private static func deterministicProjectionSuite() -> SuiteResult {
        let document = collisionFixture()
        let first = BWRSlotBoardProjection.project(document: document)
        let second = BWRSlotBoardProjection.project(document: document)

        guard first == second else {
            return fail(
                id: "determinism",
                title: "Deterministic Projection",
                summary: "같은 입력에서 projection snapshot이 동일하게 나오지 않았습니다.",
                details: [
                    "firstGroups=\(first.groupFrames.map(\.resolvedOriginSlot))",
                    "secondGroups=\(second.groupFrames.map(\.resolvedOriginSlot))"
                ]
            )
        }

        return pass(
            id: "determinism",
            title: "Deterministic Projection",
            summary: "같은 입력 문서는 같은 projection frame과 content size를 반복적으로 만듭니다.",
            details: [
                "groupCount=\(first.groupFrames.count)",
                "stripCount=\(first.stripFrames.count)"
            ]
        )
    }

    private static func slotFixture() -> BWRDocument {
        let now = Date(timeIntervalSince1970: 10)
        let groupID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let stripID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!

        let cards = [
            makeCard(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, stableSortKey: 1, placement: .attached(hostGroupID: groupID, slotIndex: 0), timestamp: now),
            makeCard(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, stableSortKey: 2, placement: .attached(hostGroupID: groupID, slotIndex: 1), timestamp: now.addingTimeInterval(1)),
            makeCard(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, stableSortKey: 3, placement: .parked(stripID: stripID, slotIndex: 0), timestamp: now.addingTimeInterval(2))
        ]

        return BWRDocument(
            schemaVersion: 2,
            createdAt: now,
            updatedAt: now,
            nextStableSortKey: 4,
            cards: cards,
            groups: [
                BWRGroup(
                    id: groupID,
                    name: "Sequence",
                    originSlot: BWRSlotCoordinate(column: 0, row: 0),
                    memberCardIDs: [cards[0].id, cards[1].id],
                    createdAt: now,
                    updatedAt: now
                )
            ],
            parkingStrips: [
                BWRParkingStrip(
                    id: stripID,
                    row: 3,
                    anchorColumn: 0,
                    cardIDs: [cards[2].id]
                )
            ]
        )
    }

    private static func collisionFixture() -> BWRDocument {
        let now = Date(timeIntervalSince1970: 20)
        let groupA = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let groupB = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
        let cardA = makeCard(id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!, stableSortKey: 1, placement: .attached(hostGroupID: groupA, slotIndex: 0), timestamp: now)
        let cardB = makeCard(id: UUID(uuidString: "00000000-0000-0000-0000-000000000032")!, stableSortKey: 2, placement: .attached(hostGroupID: groupB, slotIndex: 0), timestamp: now.addingTimeInterval(1))
        let cardC = makeCard(id: UUID(uuidString: "00000000-0000-0000-0000-000000000033")!, stableSortKey: 3, placement: .attached(hostGroupID: groupB, slotIndex: 1), timestamp: now.addingTimeInterval(2))

        return BWRDocument(
            schemaVersion: 2,
            createdAt: now,
            updatedAt: now,
            nextStableSortKey: 4,
            cards: [cardA, cardB, cardC],
            groups: [
                BWRGroup(
                    id: groupA,
                    name: "A",
                    originSlot: BWRSlotCoordinate(column: 0, row: 0),
                    memberCardIDs: [cardA.id],
                    createdAt: now,
                    updatedAt: now
                ),
                BWRGroup(
                    id: groupB,
                    name: "B",
                    originSlot: BWRSlotCoordinate(column: 0, row: 0),
                    memberCardIDs: [cardB.id, cardC.id],
                    createdAt: now,
                    updatedAt: now
                )
            ]
        )
    }

    private static func stripFixture() -> BWRDocument {
        let now = Date(timeIntervalSince1970: 30)
        let stripA = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
        let stripB = UUID(uuidString: "00000000-0000-0000-0000-000000000402")!
        let cardA = makeCard(id: UUID(uuidString: "00000000-0000-0000-0000-000000000041")!, stableSortKey: 1, placement: .parked(stripID: stripA, slotIndex: 0), timestamp: now)
        let cardB = makeCard(id: UUID(uuidString: "00000000-0000-0000-0000-000000000042")!, stableSortKey: 2, placement: .parked(stripID: stripB, slotIndex: 0), timestamp: now.addingTimeInterval(1))

        return BWRDocument(
            schemaVersion: 2,
            createdAt: now,
            updatedAt: now,
            nextStableSortKey: 3,
            cards: [cardA, cardB],
            parkingStrips: [
                BWRParkingStrip(id: stripA, row: 3, anchorColumn: 0, cardIDs: [cardA.id]),
                BWRParkingStrip(id: stripB, row: 3, anchorColumn: 0, cardIDs: [cardB.id])
            ]
        )
    }

    private static func makeCard(
        id: UUID,
        stableSortKey: Int64,
        placement: BWRCardPlacement,
        timestamp: Date
    ) -> BWRCard {
        let layers = BWRCard.defaultLayers(
            bodyMarkdown: "Card \(stableSortKey)",
            treatmentMarkdown: "",
            scenarioMarkdown: ""
        )
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
        # BWR Realignment R3 Harness

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
