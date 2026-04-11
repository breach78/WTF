import Foundation
import CoreGraphics

nonisolated enum BWRCardBuddyPhaseCHarness {
    nonisolated static let reportJSONURL = URL(fileURLWithPath: "/tmp/bwr_cardbuddy_phasec_report.json")
    nonisolated static let reportMarkdownURL = URL(fileURLWithPath: "/tmp/bwr_cardbuddy_phasec_report.md")

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
    nonisolated static func runAll() -> Bool {
        let suites = [
            emptySlotCursorSuite(),
            hoverAndCursorSuite(),
            sourceAndDestinationSuite(),
            multiSelectExistingHostFootprintSuite(),
            multiSelectParkingFootprintSuite()
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

    private nonisolated static func emptySlotCursorSuite() -> SuiteResult {
        let fixture = fixtureDocument()
        let target = BWRBoardOrderResolver.nextSlotReference(
            document: fixture.document,
            from: BWRBoardSlotReference(host: .group(fixture.groupBID), slotIndex: 0),
            direction: .right
        )
        let projection = BWRSlotBoardProjection.project(document: fixture.document)

        guard let target,
              projection.slotRect(for: target) != nil,
              BWRSlotOrder.cardID(in: target.host, at: target.slotIndex, document: fixture.document) == nil else {
            return fail(
                id: "empty-slot-cursor",
                title: "Empty Slot Cursor",
                summary: "slot cursor가 카드 없는 슬롯으로 이동하지 못했습니다.",
                details: ["target=\(String(describing: target))"]
            )
        }

        return pass(
            id: "empty-slot-cursor",
            title: "Empty Slot Cursor",
            summary: "방향키 이동이 trailing empty slot까지 도달하고 rect를 유지합니다.",
            details: ["host=\(target.host.snapshotID)", "slotIndex=\(target.slotIndex)"]
        )
    }

    private nonisolated static func hoverAndCursorSuite() -> SuiteResult {
        let fixture = fixtureDocument()
        let projection = BWRSlotBoardProjection.project(document: fixture.document)
        let cursor = BWRBoardSlotReference(host: .group(fixture.groupAID), slotIndex: 2)
        guard let hoverRect = projection.placeholderRect(for: .strip(fixture.stripID), insertionIndex: 1),
              let hover = BWRSlotBoardInteraction.resolveHoverPlaceholder(
                projection: projection,
                pointer: CGPoint(x: hoverRect.midX, y: hoverRect.midY)
              ),
              let projectedHover = hover.projectedPlaceholder(in: projection),
              projection.slotRect(for: cursor) != nil else {
            return fail(
                id: "hover-cursor",
                title: "Hover And Cursor",
                summary: "hover와 cursor를 동시에 계산하지 못했습니다.",
                details: ["hoverRect=\(String(describing: projection.placeholderRect(for: .strip(fixture.stripID), insertionIndex: 1)))"]
            )
        }

        guard case .hoverSlot = projectedHover.kind, hover.hoveredHost == .strip(fixture.stripID) else {
            return fail(
                id: "hover-cursor",
                title: "Hover And Cursor",
                summary: "hover placeholder가 cursor와 다른 overlay family로 분리되지 않았습니다.",
                details: ["hoverKind=\(projectedHover.kind)"]
            )
        }

        return pass(
            id: "hover-cursor",
            title: "Hover And Cursor",
            summary: "hover placeholder와 keyboard cursor가 서로 다른 host에서 동시에 유지됩니다.",
            details: ["cursor=\(cursor.host.snapshotID):\(cursor.slotIndex)", "hover=\(hover.hoveredHost.snapshotID):\(hover.hoveredInsertionIndex)"]
        )
    }

    private nonisolated static func sourceAndDestinationSuite() -> SuiteResult {
        let fixture = fixtureDocument()
        let projection = BWRSlotBoardProjection.project(document: fixture.document)
        guard let targetRect = projection.placeholderRect(for: .group(fixture.groupBID), insertionIndex: 1),
              let target = BWRSlotBoardInteraction.resolveCardDropTarget(
                document: fixture.document,
                projection: projection,
                draggingCardIDs: [fixture.groupACardIDs[0]],
                leadCardID: fixture.groupACardIDs[0],
                pointer: CGPoint(x: targetRect.midX, y: targetRect.midY),
                viewportState: fixture.viewport
              ) else {
            return fail(
                id: "source-destination",
                title: "Source And Destination",
                summary: "drag target를 계산하지 못했습니다.",
                details: []
            )
        }

        let overlay = BWRSlotBoardInteraction.resolveDragOverlayState(
            document: fixture.document,
            projection: projection,
            movingCardIDs: [fixture.groupACardIDs[0]],
            target: target
        )
        let destination = overlay.destinationPlaceholders(in: projection)

        guard overlay.sourceRects(in: projection).count == 1,
              destination.count == 1,
              case .dragDestination = destination[0].kind else {
            return fail(
                id: "source-destination",
                title: "Source And Destination",
                summary: "source marker와 destination placeholder가 동시에 살아 있지 않습니다.",
                details: [
                    "sourceCount=\(overlay.sourceRects(in: projection).count)",
                    "destinationCount=\(destination.count)"
                ]
            )
        }

        return pass(
            id: "source-destination",
            title: "Source And Destination",
            summary: "single-card drag에서 source marker와 destination placeholder가 분리됩니다.",
            details: ["sourceCount=1", "destinationCount=1"]
        )
    }

    private nonisolated static func multiSelectExistingHostFootprintSuite() -> SuiteResult {
        let fixture = fixtureDocument()
        let moving = Array(fixture.groupACardIDs.prefix(2))
        let projection = BWRSlotBoardProjection.project(document: fixture.document)
        guard let targetRect = projection.placeholderRect(for: .strip(fixture.stripID), insertionIndex: 1),
              let target = BWRSlotBoardInteraction.resolveCardDropTarget(
                document: fixture.document,
                projection: projection,
                draggingCardIDs: moving,
                leadCardID: moving[0],
                pointer: CGPoint(x: targetRect.midX, y: targetRect.midY),
                viewportState: fixture.viewport
              ) else {
            return fail(
                id: "multiselect-existing",
                title: "Multi-Select Existing Host",
                summary: "existing-host multi-select drag target를 계산하지 못했습니다.",
                details: []
            )
        }

        let overlay = BWRSlotBoardInteraction.resolveDragOverlayState(
            document: fixture.document,
            projection: projection,
            movingCardIDs: moving,
            target: target
        )

        guard overlay.sourceRects(in: projection).count == 2,
              overlay.destinationPlaceholders(in: projection).count == 2 else {
            return fail(
                id: "multiselect-existing",
                title: "Multi-Select Existing Host",
                summary: "multi-select drag가 source/destination block footprint로 확장되지 않았습니다.",
                details: [
                    "sourceCount=\(overlay.sourceRects(in: projection).count)",
                    "destinationCount=\(overlay.destinationPlaceholders(in: projection).count)"
                ]
            )
        }

        return pass(
            id: "multiselect-existing",
            title: "Multi-Select Existing Host",
            summary: "existing host로의 multi-select drag가 양쪽 모두 contiguous block footprint를 가집니다.",
            details: ["sourceCount=2", "destinationCount=2"]
        )
    }

    private nonisolated static func multiSelectParkingFootprintSuite() -> SuiteResult {
        let fixture = fixtureDocument()
        let moving = Array(fixture.groupACardIDs.prefix(2))
        let projection = BWRSlotBoardProjection.project(document: fixture.document)
        guard let target = BWRSlotBoardInteraction.resolveCardDropTarget(
            document: fixture.document,
            projection: projection,
            draggingCardIDs: moving,
            leadCardID: moving[0],
            pointer: CGPoint(x: 1320, y: 1280),
            viewportState: fixture.viewport
        ) else {
            return fail(
                id: "multiselect-parking",
                title: "Multi-Select Parking",
                summary: "parking multi-select drag target를 계산하지 못했습니다.",
                details: []
            )
        }

        let overlay = BWRSlotBoardInteraction.resolveDragOverlayState(
            document: fixture.document,
            projection: projection,
            movingCardIDs: moving,
            target: target
        )

        guard overlay.sourceRects(in: projection).count == 2,
              overlay.destinationPlaceholders(in: projection).count == 2 else {
            return fail(
                id: "multiselect-parking",
                title: "Multi-Select Parking",
                summary: "parking detach도 multi-select destination block footprint를 유지하지 못했습니다.",
                details: [
                    "sourceCount=\(overlay.sourceRects(in: projection).count)",
                    "destinationCount=\(overlay.destinationPlaceholders(in: projection).count)"
                ]
            )
        }

        return pass(
            id: "multiselect-parking",
            title: "Multi-Select Parking",
            summary: "parking detach에서도 source와 destination이 모두 block footprint로 유지됩니다.",
            details: ["sourceCount=2", "destinationCount=2"]
        )
    }

    private nonisolated static func write(report: Report) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(report).write(to: reportJSONURL, options: .atomic)
        try? makeMarkdown(report: report).write(to: reportMarkdownURL, atomically: true, encoding: .utf8)
    }

    private nonisolated static func makeMarkdown(report: Report) -> String {
        var lines: [String] = []
        lines.append("# BWR Card Buddy Phase C Slot State Model Rewrite")
        lines.append("")
        lines.append("- generatedAt: \(report.generatedAt)")
        lines.append("- suiteCount: \(report.suiteCount)")
        lines.append("- failureCount: \(report.failureCount)")
        lines.append("")
        for suite in report.suites {
            lines.append("- [\(suite.status.rawValue.uppercased())] \(suite.title): \(suite.summary)")
            for detail in suite.details {
                lines.append("  - \(detail)")
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private nonisolated static func pass(id: String, title: String, summary: String, details: [String]) -> SuiteResult {
        SuiteResult(id: id, title: title, status: .pass, summary: summary, details: details)
    }

    private nonisolated static func fail(id: String, title: String, summary: String, details: [String]) -> SuiteResult {
        SuiteResult(id: id, title: title, status: .fail, summary: summary, details: details)
    }

    private nonisolated static func fixtureDocument() -> (
        document: BWRDocument,
        groupAID: UUID,
        groupBID: UUID,
        stripID: UUID,
        groupACardIDs: [UUID],
        viewport: BWRViewportState
    ) {
        let card1 = makeCard(id: UUID(uuidString: "41000000-0000-0000-0000-000000000001")!, stableSortKey: 1, body: "A1")
        let card2 = makeCard(id: UUID(uuidString: "41000000-0000-0000-0000-000000000002")!, stableSortKey: 2, body: "A2")
        let card3 = makeCard(id: UUID(uuidString: "41000000-0000-0000-0000-000000000003")!, stableSortKey: 3, body: "A3")
        let card4 = makeCard(id: UUID(uuidString: "41000000-0000-0000-0000-000000000004")!, stableSortKey: 4, body: "B1")
        let card5 = makeCard(id: UUID(uuidString: "41000000-0000-0000-0000-000000000005")!, stableSortKey: 5, body: "S1")

        let groupAID = UUID(uuidString: "42000000-0000-0000-0000-000000000001")!
        let groupBID = UUID(uuidString: "42000000-0000-0000-0000-000000000002")!
        let stripID = UUID(uuidString: "43000000-0000-0000-0000-000000000001")!
        let timestamp = Date(timeIntervalSince1970: 0)

        let document = BWRDocument(
            schemaVersion: 2,
            createdAt: timestamp,
            updatedAt: timestamp,
            nextStableSortKey: 6,
            cards: [card1, card2, card3, card4, card5],
            groups: [
                BWRGroup(
                    id: groupAID,
                    name: "Alpha",
                    originSlot: BWRSlotCoordinate(column: 0, row: 0),
                    memberCardIDs: [card1.id, card2.id, card3.id],
                    createdAt: timestamp,
                    updatedAt: timestamp
                ),
                BWRGroup(
                    id: groupBID,
                    name: "Beta",
                    originSlot: BWRSlotCoordinate(column: 0, row: 2),
                    memberCardIDs: [card4.id],
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
            ],
            parkingStrips: [
                BWRParkingStrip(
                    id: stripID,
                    row: 5,
                    anchorColumn: 0,
                    cardIDs: [card5.id]
                )
            ]
        )

        return (
            document,
            groupAID,
            groupBID,
            stripID,
            [card1.id, card2.id, card3.id],
            BWRViewportState(
                zoomScale: 1.0,
                scrollOrigin: BWRPoint(x: 0, y: 0),
                viewportSize: BWRSize(width: 1440, height: 960)
            )
        )
    }

    private nonisolated static func makeCard(id: UUID, stableSortKey: Int, body: String) -> BWRCard {
        let layers = BWRCard.defaultLayers(bodyMarkdown: body)
        return BWRCard(
            id: id,
            stableSortKey: Int64(stableSortKey),
            colorHex: "F8FAFC",
            currentLayerID: layers[0].id,
            layout: BWRPoint(x: 0, y: 0),
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            layers: layers
        )
    }
}
