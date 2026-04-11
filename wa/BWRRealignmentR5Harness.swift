import Foundation

@MainActor
enum BWRRealignmentR5Harness {
    nonisolated static let reportJSONURL = URL(fileURLWithPath: "/tmp/bwr_r5_report.json")
    nonisolated static let reportMarkdownURL = URL(fileURLWithPath: "/tmp/bwr_r5_report.md")

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
            focusAndExportOrderSuite(),
            liveGroupOrderingSuite(),
            searchOrderingSuite(),
            keyboardTraversalSuite()
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

    private static func focusAndExportOrderSuite() -> SuiteResult {
        let fixture = orderingFixture()
        let reference = BWRReferenceDocument(document: fixture)
        let primaryGroupID = UUID(uuidString: "00000000-0000-0000-0000-000000000901")!
        let secondaryGroupID = UUID(uuidString: "00000000-0000-0000-0000-000000000902")!

        let focusEntries = BWRFocusModeProjection.entries(
            document: reference.document,
            groupID: primaryGroupID,
            mode: .scenario
        )
        let exported = BWRExportBridge.exportText(
            document: reference.document,
            groupIDs: [secondaryGroupID, primaryGroupID],
            mode: .scenario
        )

        let focusedCardIDs = focusEntries.map(\.cardID)
        let expectedFocusOrder = [
            UUID(uuidString: "00000000-0000-0000-0000-000000000081")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000082")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000083")!
        ]
        let expectedExport = [
            "Scene A",
            "Scene B",
            "Scene C",
            "Scene D"
        ].joined(separator: "\n\n")

        guard focusedCardIDs == expectedFocusOrder,
              exported == expectedExport,
              !exported.contains("Scene Parked") else {
            return fail(
                id: "focus-export",
                title: "Focus And Export Slot Order",
                summary: "포커스/출력이 그룹 slot 순서를 따르지 않거나 parked 카드가 섞였습니다.",
                details: [
                    "focus=\(focusedCardIDs.map(\.uuidString).joined(separator: ","))",
                    "export=\(quoted(exported))"
                ]
            )
        }

        return pass(
            id: "focus-export",
            title: "Focus And Export Slot Order",
            summary: "포커스와 export가 scrambled layout shadow를 무시하고 그룹 slot 순서만 따르며 parked 카드는 제외합니다.",
            details: [
                "focusCount=\(focusEntries.count)",
                "exportFragments=4"
            ]
        )
    }

    private static func liveGroupOrderingSuite() -> SuiteResult {
        let reference = BWRReferenceDocument(document: orderingFixture())
        let orderedGroupIDs = reference.liveGroups.map(\.id)
        let orderedCardIDs = reference.liveCards.map(\.id)

        let expectedGroupIDs = [
            UUID(uuidString: "00000000-0000-0000-0000-000000000901")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000902")!
        ]
        let expectedCardPrefix = [
            UUID(uuidString: "00000000-0000-0000-0000-000000000081")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000082")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000083")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000084")!
        ]

        guard orderedGroupIDs == expectedGroupIDs,
              Array(orderedCardIDs.prefix(expectedCardPrefix.count)) == expectedCardPrefix else {
            return fail(
                id: "live-order",
                title: "Live Group And Card Ordering",
                summary: "document 소비자 정렬이 visible slot order로 수렴하지 않았습니다.",
                details: [
                    "groups=\(orderedGroupIDs.map(\.uuidString).joined(separator: ","))",
                    "cards=\(orderedCardIDs.map(\.uuidString).joined(separator: ","))"
                ]
            )
        }

        return pass(
            id: "live-order",
            title: "Live Group And Card Ordering",
            summary: "document.liveGroups/liveCards가 이름이나 stale layout이 아니라 visible slot order를 따릅니다.",
            details: [
                "groups=\(orderedGroupIDs.count)",
                "cards=\(orderedCardIDs.count)"
            ]
        )
    }

    private static func searchOrderingSuite() -> SuiteResult {
        let hits = BWRDocumentSearch.search(
            document: orderingFixture(),
            query: "needle",
            scope: .liveOnly
        )
        let cardHitIDs = hits.filter { $0.entityKind == .card }.map(\.entityID)
        let expectedCardHits = [
            UUID(uuidString: "00000000-0000-0000-0000-000000000081")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000082")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000083")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000084")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000085")!
        ]

        guard cardHitIDs == expectedCardHits else {
            return fail(
                id: "search",
                title: "Search Ordering",
                summary: "search hit가 slot order 대신 raw layout 또는 비결정 순서로 나옵니다.",
                details: [
                    "cardHits=\(cardHitIDs.map(\.uuidString).joined(separator: ","))",
                    "allHits=\(hits.map { "\($0.entityKind.rawValue):\($0.entityID.uuidString)" }.joined(separator: " | "))"
                ]
            )
        }

        return pass(
            id: "search",
            title: "Search Ordering",
            summary: "search live card hit가 visible slot order를 따르고, grouped 카드 뒤에 parked 카드가 안정적으로 옵니다.",
            details: ["cardHits=\(cardHitIDs.count)"]
        )
    }

    private static func keyboardTraversalSuite() -> SuiteResult {
        let fixture = traversalFixture()
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000111")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000112")!
        let fifth = UUID(uuidString: "00000000-0000-0000-0000-000000000115")!
        let sixth = UUID(uuidString: "00000000-0000-0000-0000-000000000116")!

        let right = BWRBoardOrderResolver.nextCardID(document: fixture, from: first, direction: .right)
        let down = BWRBoardOrderResolver.nextCardID(document: fixture, from: first, direction: .down)
        let left = BWRBoardOrderResolver.nextCardID(document: fixture, from: sixth, direction: .left)
        let up = BWRBoardOrderResolver.nextCardID(document: fixture, from: sixth, direction: .up)

        guard right == second,
              down == fifth,
              left == fifth,
              up == second else {
            return fail(
                id: "keyboard-traversal",
                title: "Keyboard Traversal",
                summary: "arrow traversal이 slot 좌표가 아니라 예전 layout distance 규칙을 따르거나 비결정적입니다.",
                details: [
                    "right=\(right?.uuidString ?? "nil")",
                    "down=\(down?.uuidString ?? "nil")",
                    "left=\(left?.uuidString ?? "nil")",
                    "up=\(up?.uuidString ?? "nil")"
                ]
            )
        }

        return pass(
            id: "keyboard-traversal",
            title: "Keyboard Traversal",
            summary: "arrow traversal이 wrapped group fixture에서도 slot 좌표 기준으로 결정적으로 이동합니다.",
            details: [
                "right=\(second.uuidString)",
                "down=\(fifth.uuidString)"
            ]
        )
    }

    private static func orderingFixture() -> BWRDocument {
        let now = Date(timeIntervalSince1970: 70)
        let groupAID = UUID(uuidString: "00000000-0000-0000-0000-000000000901")!
        let groupBID = UUID(uuidString: "00000000-0000-0000-0000-000000000902")!
        let stripID = UUID(uuidString: "00000000-0000-0000-0000-000000000903")!

        let cards = [
            makeCard(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000081")!,
                stableSortKey: 1,
                placement: .attached(hostGroupID: groupAID, slotIndex: 0),
                layout: BWRPoint(x: 9000, y: 8800),
                body: "Body A needle",
                treatment: "Treat A",
                scenario: "Scene A",
                timestamp: now
            ),
            makeCard(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000082")!,
                stableSortKey: 2,
                placement: .attached(hostGroupID: groupAID, slotIndex: 1),
                layout: BWRPoint(x: 100, y: 7800),
                body: "Body B needle",
                treatment: "Treat B",
                scenario: "Scene B",
                timestamp: now.addingTimeInterval(1)
            ),
            makeCard(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000083")!,
                stableSortKey: 3,
                placement: .attached(hostGroupID: groupAID, slotIndex: 2),
                layout: BWRPoint(x: 3000, y: 120),
                body: "Body C needle",
                treatment: "Treat C",
                scenario: "Scene C",
                timestamp: now.addingTimeInterval(2)
            ),
            makeCard(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000084")!,
                stableSortKey: 4,
                placement: .attached(hostGroupID: groupBID, slotIndex: 0),
                layout: BWRPoint(x: 42, y: 42),
                body: "Body D needle",
                treatment: "Treat D",
                scenario: "Scene D",
                timestamp: now.addingTimeInterval(3)
            ),
            makeCard(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000085")!,
                stableSortKey: 5,
                placement: .parked(stripID: stripID, slotIndex: 0),
                layout: BWRPoint(x: 12_000, y: 12_000),
                body: "Body Parked needle",
                treatment: "Treat Parked",
                scenario: "Scene Parked",
                timestamp: now.addingTimeInterval(4)
            )
        ]

        return BWRDocument(
            schemaVersion: 2,
            createdAt: now,
            updatedAt: now,
            nextStableSortKey: 6,
            cards: cards,
            groups: [
                BWRGroup(
                    id: groupAID,
                    name: "Zulu Group",
                    originSlot: BWRSlotCoordinate(column: 0, row: 0),
                    memberCardIDs: [cards[0].id, cards[1].id, cards[2].id],
                    createdAt: now,
                    updatedAt: now
                ),
                BWRGroup(
                    id: groupBID,
                    name: "Alpha Group",
                    originSlot: BWRSlotCoordinate(column: 4, row: 0),
                    memberCardIDs: [cards[3].id],
                    createdAt: now,
                    updatedAt: now
                )
            ],
            parkingStrips: [
                BWRParkingStrip(
                    id: stripID,
                    row: 4,
                    anchorColumn: 0,
                    cardIDs: [cards[4].id]
                )
            ]
        )
    }

    private static func traversalFixture() -> BWRDocument {
        let now = Date(timeIntervalSince1970: 80)
        let groupID = UUID(uuidString: "00000000-0000-0000-0000-000000000911")!
        let stripID = UUID(uuidString: "00000000-0000-0000-0000-000000000912")!

        let cards = [
            makeCard(id: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!, stableSortKey: 1, placement: .attached(hostGroupID: groupID, slotIndex: 0), layout: BWRPoint(x: 900, y: 900), body: "A", treatment: "TA", scenario: "SA", timestamp: now),
            makeCard(id: UUID(uuidString: "00000000-0000-0000-0000-000000000112")!, stableSortKey: 2, placement: .attached(hostGroupID: groupID, slotIndex: 1), layout: BWRPoint(x: 100, y: 1100), body: "B", treatment: "TB", scenario: "SB", timestamp: now.addingTimeInterval(1)),
            makeCard(id: UUID(uuidString: "00000000-0000-0000-0000-000000000113")!, stableSortKey: 3, placement: .attached(hostGroupID: groupID, slotIndex: 2), layout: BWRPoint(x: 5000, y: 1200), body: "C", treatment: "TC", scenario: "SC", timestamp: now.addingTimeInterval(2)),
            makeCard(id: UUID(uuidString: "00000000-0000-0000-0000-000000000114")!, stableSortKey: 4, placement: .attached(hostGroupID: groupID, slotIndex: 3), layout: BWRPoint(x: 7000, y: 100), body: "D", treatment: "TD", scenario: "SD", timestamp: now.addingTimeInterval(3)),
            makeCard(id: UUID(uuidString: "00000000-0000-0000-0000-000000000115")!, stableSortKey: 5, placement: .attached(hostGroupID: groupID, slotIndex: 4), layout: BWRPoint(x: 80, y: 80), body: "E", treatment: "TE", scenario: "SE", timestamp: now.addingTimeInterval(4)),
            makeCard(id: UUID(uuidString: "00000000-0000-0000-0000-000000000116")!, stableSortKey: 6, placement: .attached(hostGroupID: groupID, slotIndex: 5), layout: BWRPoint(x: 10_000, y: 20), body: "F", treatment: "TF", scenario: "SF", timestamp: now.addingTimeInterval(5)),
            makeCard(id: UUID(uuidString: "00000000-0000-0000-0000-000000000117")!, stableSortKey: 7, placement: .parked(stripID: stripID, slotIndex: 0), layout: BWRPoint(x: 22, y: 22), body: "P", treatment: "TP", scenario: "SP", timestamp: now.addingTimeInterval(6))
        ]

        return BWRDocument(
            schemaVersion: 2,
            createdAt: now,
            updatedAt: now,
            nextStableSortKey: 8,
            cards: cards,
            groups: [
                BWRGroup(
                    id: groupID,
                    name: "Traversal",
                    originSlot: BWRSlotCoordinate(column: 0, row: 0),
                    memberCardIDs: cards.prefix(6).map(\.id),
                    createdAt: now,
                    updatedAt: now
                )
            ],
            parkingStrips: [
                BWRParkingStrip(
                    id: stripID,
                    row: 4,
                    anchorColumn: 0,
                    cardIDs: [cards[6].id]
                )
            ]
        )
    }

    private static func makeCard(
        id: UUID,
        stableSortKey: Int64,
        placement: BWRCardPlacement,
        layout: BWRPoint,
        body: String,
        treatment: String,
        scenario: String,
        timestamp: Date
    ) -> BWRCard {
        let layers = BWRCard.defaultLayers(
            bodyMarkdown: body,
            treatmentMarkdown: treatment,
            scenarioMarkdown: scenario
        )
        return BWRCard(
            id: id,
            stableSortKey: stableSortKey,
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

    private static func quoted(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func write(report: Report) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(report).write(to: reportJSONURL, options: .atomic)

        let markdown = """
        # BWR Realignment R5 Harness

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
