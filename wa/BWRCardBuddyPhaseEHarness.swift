import Foundation
import CoreGraphics

nonisolated enum BWRCardBuddyPhaseEHarness {
    nonisolated static let reportJSONURL = URL(fileURLWithPath: "/tmp/bwr_cardbuddy_phasee_report.json")
    nonisolated static let reportMarkdownURL = URL(fileURLWithPath: "/tmp/bwr_cardbuddy_phasee_report.md")

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
            fixedCardGeometrySuite(),
            projectionFrameLockSuite(),
            editingRectSuite(),
            inputRuleSuite()
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

    private nonisolated static func fixedCardGeometrySuite() -> SuiteResult {
        let slotRect = CGRect(x: 240, y: 190, width: 240, height: 190)
        let normal = BWRSlotBoardGeometry.cardRect(in: slotRect, inlineExpanded: false)
        let editing = BWRSlotBoardGeometry.cardRect(in: slotRect, inlineExpanded: true)

        guard normal == editing else {
            return fail(
                id: "fixed-geometry",
                title: "Fixed Card Geometry",
                summary: "inline editing 전후 card rect가 달라졌습니다.",
                details: [
                    "normal=\(normal.debugDescription)",
                    "editing=\(editing.debugDescription)"
                ]
            )
        }

        return pass(
            id: "fixed-geometry",
            title: "Fixed Card Geometry",
            summary: "geometry 레벨에서 inline editing이 outer card rect를 바꾸지 않습니다.",
            details: [normal.debugDescription]
        )
    }

    private nonisolated static func projectionFrameLockSuite() -> SuiteResult {
        let fixture = fixtureDocument()
        let firstCardID = fixture.groupACardIDs[0]
        let normalProjection = BWRSlotBoardProjection.project(document: fixture.document)
        let editingProjection = BWRSlotBoardProjection.project(document: fixture.document, expandedCardIDs: [firstCardID])

        guard normalProjection.cardRect(for: firstCardID) == editingProjection.cardRect(for: firstCardID) else {
            return fail(
                id: "projection-lock",
                title: "Projection Frame Lock",
                summary: "projection이 editing card를 여전히 확장 rect로 계산합니다.",
                details: [
                    "normal=\(String(describing: normalProjection.cardRect(for: firstCardID)))",
                    "editing=\(String(describing: editingProjection.cardRect(for: firstCardID)))"
                ]
            )
        }

        return pass(
            id: "projection-lock",
            title: "Projection Frame Lock",
            summary: "projection snapshot도 inline editing 전후 같은 card rect를 유지합니다.",
            details: [String(describing: normalProjection.cardRect(for: firstCardID))]
        )
    }

    private nonisolated static func editingRectSuite() -> SuiteResult {
        let cardRect = CGRect(origin: .zero, size: BWRSlotBoardGeometry.default.cardSize)
        let editorRect = BWRSlotBoardGeometry.inlineEditorRect(
            in: cardRect,
            footerHeight: BWRCardBuddyEditingChrome.footerHeight,
            horizontalInset: 10,
            topInset: 12,
            bottomInset: 14,
            footerGap: BWRCardBuddyEditingChrome.footerGap
        )
        let footerRect = BWRSlotBoardGeometry.inlineEditorFooterRect(
            in: cardRect,
            footerHeight: BWRCardBuddyEditingChrome.footerHeight,
            horizontalInset: 14,
            bottomInset: 14
        )

        let editorInside = cardRect.contains(editorRect)
        let footerInside = cardRect.contains(footerRect)
        let separated = editorRect.maxY <= footerRect.minY - BWRCardBuddyEditingChrome.footerGap + 0.5

        guard editorInside, footerInside, separated else {
            return fail(
                id: "editing-rect",
                title: "Editing Rect Separation",
                summary: "card rect와 editing/footer rect 분리가 고정 카드 안에서 성립하지 않습니다.",
                details: [
                    "card=\(cardRect.debugDescription)",
                    "editorInside=\(editorInside) editor=\(editorRect.debugDescription)",
                    "footerInside=\(footerInside) footer=\(footerRect.debugDescription)",
                    "separated=\(separated)"
                ]
            )
        }

        return pass(
            id: "editing-rect",
            title: "Editing Rect Separation",
            summary: "editor rect와 footer rect가 고정 카드 안에서 분리되어 유지됩니다.",
            details: [
                "editor=\(editorRect.debugDescription)",
                "footer=\(footerRect.debugDescription)"
            ]
        )
    }

    private nonisolated static func inputRuleSuite() -> SuiteResult {
        let enterExisting = BWRCardBuddyEditingActivation.keyboardEnter(slotHasCard: true)
        let enterEmpty = BWRCardBuddyEditingActivation.keyboardEnter(slotHasCard: false)
        let doubleClick = BWRCardBuddyEditingActivation.doubleClickPreview()
        let splitAction = BWRTextKeyCommandRouter.resolve(
            BWRTextKeyEvent(
                keyCode: 36,
                modifiers: BWRTextKeyModifiers(shift: false, command: false, option: false, control: false),
                hasMarkedText: false
            )
        )

        guard enterExisting == .beginInlineEdit,
              enterEmpty == .createCardAndBeginInlineEdit,
              doubleClick == .openLargeEditor,
              splitAction == .splitCard else {
            return fail(
                id: "input-rule",
                title: "Input Rule",
                summary: "Enter / double click / split input grammar가 계획과 다릅니다.",
                details: [
                    "enterExisting=\(String(describing: enterExisting))",
                    "enterEmpty=\(String(describing: enterEmpty))",
                    "doubleClick=\(String(describing: doubleClick))",
                    "splitAction=\(String(describing: splitAction))"
                ]
            )
        }

        return pass(
            id: "input-rule",
            title: "Input Rule",
            summary: "Enter는 inline edit, preview double click은 large editor, editor Enter는 split으로 분리됩니다.",
            details: [
                "enterExisting=beginInlineEdit",
                "enterEmpty=createCardAndBeginInlineEdit",
                "doubleClick=openLargeEditor",
                "editorEnter=splitCard"
            ]
        )
    }

    private nonisolated static func fixtureDocument() -> (
        document: BWRDocument,
        groupACardIDs: [UUID]
    ) {
        let card1 = makeCard(id: UUID(uuidString: "51000000-0000-0000-0000-000000000001")!, stableSortKey: 1, body: "A1")
        let card2 = makeCard(id: UUID(uuidString: "51000000-0000-0000-0000-000000000002")!, stableSortKey: 2, body: "A2")
        let card3 = makeCard(id: UUID(uuidString: "51000000-0000-0000-0000-000000000003")!, stableSortKey: 3, body: "A3")
        let card4 = makeCard(id: UUID(uuidString: "51000000-0000-0000-0000-000000000004")!, stableSortKey: 4, body: "B1")
        let timestamp = Date(timeIntervalSince1970: 0)

        let document = BWRDocument(
            schemaVersion: 2,
            createdAt: timestamp,
            updatedAt: timestamp,
            nextStableSortKey: 5,
            cards: [card1, card2, card3, card4],
            groups: [
                BWRGroup(
                    id: UUID(uuidString: "52000000-0000-0000-0000-000000000001")!,
                    name: "Alpha",
                    originSlot: BWRSlotCoordinate(column: 0, row: 0),
                    memberCardIDs: [card1.id, card2.id, card3.id],
                    createdAt: timestamp,
                    updatedAt: timestamp
                ),
                BWRGroup(
                    id: UUID(uuidString: "52000000-0000-0000-0000-000000000002")!,
                    name: "Beta",
                    originSlot: BWRSlotCoordinate(column: 0, row: 2),
                    memberCardIDs: [card4.id],
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
            ]
        )

        return (document, [card1.id, card2.id, card3.id])
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
        lines.append("# BWR Card Buddy Phase E Report")
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
