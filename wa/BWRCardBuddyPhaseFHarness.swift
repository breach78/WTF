import Foundation
import CoreGraphics

nonisolated enum BWRCardBuddyPhaseFHarness {
    nonisolated static let reportJSONURL = URL(fileURLWithPath: "/tmp/bwr_cardbuddy_phasef_report.json")
    nonisolated static let reportMarkdownURL = URL(fileURLWithPath: "/tmp/bwr_cardbuddy_phasef_report.md")

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
            gridBaselineSuite(),
            overlayPrioritySuite(),
            overlayGrammarSuite(),
            sourceBlockFrameSuite(),
            destinationBlockFrameSuite()
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

    private nonisolated static func gridBaselineSuite() -> SuiteResult {
        guard !BWRCardBuddyStateGrammar.showsSlotGridBaseline else {
            return fail(
                id: "grid-baseline",
                title: "Grid Baseline Hidden",
                summary: "Phase F 이후에도 slot baseline이 기본 표시 상태입니다.",
                details: ["showsSlotGridBaseline=true"]
            )
        }

        return pass(
            id: "grid-baseline",
            title: "Grid Baseline Hidden",
            summary: "평상시 board background가 slot baseline 없이 렌더링되도록 잠겼습니다.",
            details: ["showsSlotGridBaseline=false"]
        )
    }

    private nonisolated static func overlayPrioritySuite() -> SuiteResult {
        let keyboard = BWRCardBuddyStateGrammar.interactionPriority(for: .keyboard)
        let pointer = BWRCardBuddyStateGrammar.interactionPriority(for: .pointer)

        guard let keyboardCursorIndex = keyboard.firstIndex(of: .slotCursor),
              let keyboardHoverIndex = keyboard.firstIndex(of: .hoverPlaceholder),
              let pointerCursorIndex = pointer.firstIndex(of: .slotCursor),
              let pointerHoverIndex = pointer.firstIndex(of: .hoverPlaceholder),
              keyboardCursorIndex > keyboardHoverIndex,
              pointerHoverIndex > pointerCursorIndex,
              Array(keyboard.suffix(2)) == [.dragSource, .dragDestination],
              Array(pointer.suffix(2)) == [.dragSource, .dragDestination] else {
            return fail(
                id: "overlay-priority",
                title: "Overlay Priority",
                summary: "keyboard/pointer input priority가 Card Buddy 상태 문법대로 고정되지 않았습니다.",
                details: [
                    "keyboard=\(keyboard.map(\.rawValue).joined(separator: ","))",
                    "pointer=\(pointer.map(\.rawValue).joined(separator: ","))"
                ]
            )
        }

        return pass(
            id: "overlay-priority",
            title: "Overlay Priority",
            summary: "keyboard는 cursor, pointer는 hover를 더 강하게 읽히게 하고 drag overlays는 항상 최상위에 유지합니다.",
            details: [
                "keyboard=\(keyboard.map(\.rawValue).joined(separator: ","))",
                "pointer=\(pointer.map(\.rawValue).joined(separator: ","))"
            ]
        )
    }

    private nonisolated static func overlayGrammarSuite() -> SuiteResult {
        let cursor = BWRCardBuddyStateGrammar.slotCursorStyle(isEmphasized: true)
        let hover = BWRCardBuddyStateGrammar.hoverStyle(isEmphasized: true)
        let source = BWRCardBuddyStateGrammar.dragSourceStyle(isLifted: true)
        let destination = BWRCardBuddyStateGrammar.dragDestinationStyle(
            host: .group(UUID(uuidString: "62000000-0000-0000-0000-000000000001")!)
        )

        let descriptors = [cursor, hover, source, destination].map(\.descriptor)
        guard Set(descriptors).count == 4,
              cursor.dash.isEmpty,
              cursor.fillOpacity > 0,
              !hover.dash.isEmpty,
              hover.strokePalette == .neutral,
              source.strokePalette == .accent,
              source.dash.isEmpty,
              destination.strokePalette == .accent,
              !destination.dash.isEmpty else {
            return fail(
                id: "overlay-grammar",
                title: "Overlay Grammar Separation",
                summary: "cursor / hover / source / destination가 충분히 구분되는 style token으로 잠기지 않았습니다.",
                details: descriptors
            )
        }

        return pass(
            id: "overlay-grammar",
            title: "Overlay Grammar Separation",
            summary: "cursor는 gray solid, hover는 neutral dashed, source는 blue solid, destination은 blue dashed grammar로 분리됩니다.",
            details: descriptors
        )
    }

    private nonisolated static func sourceBlockFrameSuite() -> SuiteResult {
        let fixture = fixtureDocument()
        let movingCardIDs = Array(fixture.groupACardIDs.prefix(2))
        let projection = BWRSlotBoardProjection.project(document: fixture.document)
        let sourceRects = movingCardIDs.compactMap { cardID in
            BWRSlotOrder.indexOfCardInHost(cardID: cardID, document: fixture.document)
        }
        .compactMap { location in
            projection.slotRect(for: BWRBoardSlotReference(host: location.host, slotIndex: location.index))
        }
        let merged = BWRSlotBoardGeometry.contiguousOverlayRects(from: sourceRects, gapTolerance: 1)

        guard sourceRects.count == 2, merged.count == 1 else {
            return fail(
                id: "source-block-frame",
                title: "Source Block Frame",
                summary: "multi-card drag source가 contiguous block frame으로 합쳐지지 않았습니다.",
                details: [
                    "sourceCount=\(sourceRects.count)",
                    "mergedCount=\(merged.count)"
                ]
            )
        }

        return pass(
            id: "source-block-frame",
            title: "Source Block Frame",
            summary: "horizontal multi-card source가 하나의 contiguous block frame으로 렌더링됩니다.",
            details: [
                "sourceCount=2",
                "mergedRect=\(merged[0].debugDescription)"
            ]
        )
    }

    private nonisolated static func destinationBlockFrameSuite() -> SuiteResult {
        let fixture = fixtureDocument()
        let movingCardIDs = Array(fixture.groupACardIDs.prefix(2))
        let projection = BWRSlotBoardProjection.project(document: fixture.document)

        guard let targetRect = projection.placeholderRect(for: .strip(fixture.stripID), insertionIndex: 1),
              let target = BWRSlotBoardInteraction.resolveCardDropTarget(
                document: fixture.document,
                projection: projection,
                draggingCardIDs: movingCardIDs,
                leadCardID: movingCardIDs[0],
                pointer: CGPoint(x: targetRect.midX, y: targetRect.midY),
                viewportState: fixture.viewport
              ) else {
            return fail(
                id: "destination-block-frame",
                title: "Destination Block Frame",
                summary: "Phase F destination overlay fixture를 계산하지 못했습니다.",
                details: []
            )
        }

        let overlay = BWRSlotBoardInteraction.resolveDragOverlayState(
            document: fixture.document,
            projection: projection,
            movingCardIDs: movingCardIDs,
            target: target
        )
        let destinationRects = overlay.destinationPlaceholders(in: projection).map(\.rect)
        let merged = BWRSlotBoardGeometry.contiguousOverlayRects(
            from: destinationRects,
            gapTolerance: BWRCardBuddyStateGrammar.multiBlockBridgeGapCompensation
        )

        guard destinationRects.count == 2, merged.count == 1 else {
            return fail(
                id: "destination-block-frame",
                title: "Destination Block Frame",
                summary: "multi-card drop destination이 contiguous block frame으로 합쳐지지 않았습니다.",
                details: [
                    "destinationCount=\(destinationRects.count)",
                    "mergedCount=\(merged.count)"
                ]
            )
        }

        return pass(
            id: "destination-block-frame",
            title: "Destination Block Frame",
            summary: "multi-card drop destination도 하나의 contiguous block frame grammar로 읽힙니다.",
            details: [
                "destinationCount=2",
                "mergedRect=\(merged[0].debugDescription)"
            ]
        )
    }

    private nonisolated static func fixtureDocument() -> (
        document: BWRDocument,
        stripID: UUID,
        groupACardIDs: [UUID],
        viewport: BWRViewportState
    ) {
        let card1 = makeCard(id: UUID(uuidString: "61000000-0000-0000-0000-000000000001")!, stableSortKey: 1, body: "A1")
        let card2 = makeCard(id: UUID(uuidString: "61000000-0000-0000-0000-000000000002")!, stableSortKey: 2, body: "A2")
        let card3 = makeCard(id: UUID(uuidString: "61000000-0000-0000-0000-000000000003")!, stableSortKey: 3, body: "A3")
        let card4 = makeCard(id: UUID(uuidString: "61000000-0000-0000-0000-000000000004")!, stableSortKey: 4, body: "B1")
        let card5 = makeCard(id: UUID(uuidString: "61000000-0000-0000-0000-000000000005")!, stableSortKey: 5, body: "S1")

        let groupAID = UUID(uuidString: "62000000-0000-0000-0000-000000000001")!
        let groupBID = UUID(uuidString: "62000000-0000-0000-0000-000000000002")!
        let stripID = UUID(uuidString: "63000000-0000-0000-0000-000000000001")!
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
            stripID,
            [card1.id, card2.id, card3.id],
            BWRViewportState(
                zoomScale: 1,
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

    private nonisolated static func write(report: Report) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(report).write(to: reportJSONURL, options: .atomic)
        try? makeMarkdown(report: report).write(to: reportMarkdownURL, atomically: true, encoding: .utf8)
    }

    private nonisolated static func makeMarkdown(report: Report) -> String {
        var lines: [String] = []
        lines.append("# BWR Card Buddy Phase F State Grammar Rendering Rewrite")
        lines.append("")
        lines.append("- generatedAt: \(report.generatedAt)")
        lines.append("- suiteCount: \(report.suiteCount)")
        lines.append("- failureCount: \(report.failureCount)")
        lines.append("")
        for suite in report.suites {
            lines.append("## \(suite.title)")
            lines.append("")
            lines.append("- status: \(suite.status.rawValue)")
            lines.append("- summary: \(suite.summary)")
            for detail in suite.details {
                lines.append("- \(detail)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private nonisolated static func pass(
        id: String,
        title: String,
        summary: String,
        details: [String]
    ) -> SuiteResult {
        SuiteResult(id: id, title: title, status: .pass, summary: summary, details: details)
    }

    private nonisolated static func fail(
        id: String,
        title: String,
        summary: String,
        details: [String]
    ) -> SuiteResult {
        SuiteResult(id: id, title: title, status: .fail, summary: summary, details: details)
    }
}
