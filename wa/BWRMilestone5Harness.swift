import Foundation
import CoreGraphics

@MainActor
enum BWRMilestone5Harness {
    nonisolated static let reportJSONURL = URL(fileURLWithPath: "/tmp/bwr_m5_report.json")
    nonisolated static let reportMarkdownURL = URL(fileURLWithPath: "/tmp/bwr_m5_report.md")

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
            layoutMatrixSuite(),
            keyboardRoutingSuite(),
            linkPersistenceSuite(),
            macAcceptanceSmokeSuite()
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

    private static func layoutMatrixSuite() -> SuiteResult {
        struct Case {
            let name: String
            let size: CGSize
            let expectedWorkspace: BWRWorkspaceLayoutMode
            let expectedFocus: BWRFocusLayoutMode
        }

        let cases: [Case] = [
            .init(name: "my-mac-host", size: CGSize(width: 1512, height: 982), expectedWorkspace: .regular, expectedFocus: .regular),
            .init(name: "ipad-landscape", size: CGSize(width: 1366, height: 1024), expectedWorkspace: .regular, expectedFocus: .regular),
            .init(name: "stage-manager-medium", size: CGSize(width: 1194, height: 834), expectedWorkspace: .regular, expectedFocus: .regular),
            .init(name: "ipad-portrait", size: CGSize(width: 1024, height: 1366), expectedWorkspace: .compact, expectedFocus: .compact),
            .init(name: "split-half", size: CGSize(width: 820, height: 1024), expectedWorkspace: .compact, expectedFocus: .compact)
        ]

        let mismatches = cases.compactMap { item -> String? in
            let workspace = BWRWorkspaceLayoutMode.resolve(for: item.size)
            let focus = BWRFocusLayoutMode.resolve(for: item.size)
            guard workspace == item.expectedWorkspace, focus == item.expectedFocus else {
                return "\(item.name): workspace=\(workspace.rawValue), focus=\(focus.rawValue)"
            }
            return nil
        }

        let zoomChecks = [
            BWRBoardZoomController.zoomIn(from: 1.0) == 1.1,
            BWRBoardZoomController.zoomOut(from: 1.0) == 0.9,
            BWRBoardZoomController.zoomOut(from: 0.31) == BWRBoardZoomController.minimumScale,
            BWRBoardZoomController.zoomIn(from: 1.59) == BWRBoardZoomController.maximumScale,
            BWRBoardZoomController.reset() == 1.0
        ]

        guard mismatches.isEmpty, zoomChecks.allSatisfy({ $0 }) else {
            return fail(
                id: "layout-matrix",
                title: "Layout Matrix And Zoom",
                summary: "M5 레이아웃 전환 또는 줌 클램프가 portrait/landscape/split/Mac 기대값과 다릅니다.",
                details: mismatches + ["zoomChecks=\(zoomChecks.map(String.init).joined(separator: ","))"]
            )
        }

        return pass(
            id: "layout-matrix",
            title: "Layout Matrix And Zoom",
            summary: "workspace/focus layout이 Mac host, landscape, portrait, split width에서 계획한 모드로 전환되고 줌 클램프도 안정적입니다.",
            details: cases.map {
                "\($0.name)=\($0.expectedWorkspace.rawValue)/\($0.expectedFocus.rawValue)"
            }
        )
    }

    private static func keyboardRoutingSuite() -> SuiteResult {
        let mappings: [String: BWRFocusModeKind] = [
            "1": .currentLayer,
            "2": .treatment,
            "3": .scenario
        ]

        let mappingFailures = mappings.compactMap { key, expected -> String? in
            BWRFocusModeKind.keyboardMapping(for: key) == expected ? nil : "\(key)->\(expected.rawValue)"
        }

        let enterCases: [(String, BWRTextKeyEvent, BWRTextKeyCommandAction)] = [
            (
                "plain-enter",
                BWRTextKeyEvent(
                    keyCode: 36,
                    modifiers: BWRTextKeyModifiers(shift: false, command: false, option: false, control: false),
                    hasMarkedText: false
                ),
                .splitCard
            ),
            (
                "shift-enter",
                BWRTextKeyEvent(
                    keyCode: 36,
                    modifiers: BWRTextKeyModifiers(shift: true, command: false, option: false, control: false),
                    hasMarkedText: false
                ),
                .insertNewline
            ),
            (
                "ime-enter",
                BWRTextKeyEvent(
                    keyCode: 36,
                    modifiers: BWRTextKeyModifiers(shift: false, command: false, option: false, control: false),
                    hasMarkedText: true
                ),
                .passToSystem
            )
        ]

        let routingFailures = enterCases.compactMap { name, event, expected -> String? in
            let actual = BWRTextKeyCommandRouter.resolve(event)
            return actual == expected ? nil : "\(name)=\(actual.rawValue)"
        }

        guard mappingFailures.isEmpty, routingFailures.isEmpty else {
            return fail(
                id: "keyboard",
                title: "Keyboard Routing",
                summary: "M5 키보드 매핑 또는 Enter/Shift+Enter 라우팅이 계획과 다릅니다.",
                details: mappingFailures + routingFailures
            )
        }

        return pass(
            id: "keyboard",
            title: "Keyboard Routing",
            summary: "보드/포커스 모드의 숫자 단축키와 Enter 분기 라우팅이 외부 키보드 기준으로 고정되었습니다.",
            details: [
                "focusKeys=1,2,3",
                "textKeys=enter split / shift-enter newline"
            ]
        )
    }

    private static func linkPersistenceSuite() -> SuiteResult {
        let packageURL = temporaryPackageURL(prefix: "bwr-m5-links")
        defer {
            try? FileManager.default.removeItem(at: packageURL)
        }

        do {
            let reference = BWRReferenceDocument(document: linkFixture())
            reference.attach(fileURL: packageURL)

            guard reference.liveCards.count >= 2 else {
                return fail(
                    id: "links",
                    title: "Link Persistence",
                    summary: "링크 fixture 카드가 부족합니다.",
                    details: []
                )
            }

            let sourceID = reference.liveCards[0].id
            let destinationID = reference.liveCards[1].id

            reference.createLink(sourceCardID: sourceID, destinationCardID: destinationID)
            reference.forceFullSaveNow()
            guard waitUntil(timeout: 2.0, condition: {
                (try? BWRPackageStore.read(from: packageURL).links.count) == 1
            }) else {
                return fail(
                    id: "links",
                    title: "Link Persistence",
                    summary: "생성된 링크가 .bwr 패키지로 flush되지 않았습니다.",
                    details: ["package=\(packageURL.path)"]
                )
            }

            let afterCreate = try BWRPackageStore.read(from: packageURL)
            guard let createdLink = afterCreate.links.first,
                  !createdLink.isArchived else {
                return fail(
                    id: "links",
                    title: "Link Persistence",
                    summary: "패키지에서 live link를 읽지 못했습니다.",
                    details: ["links=\(afterCreate.links.count)"]
                )
            }

            reference.archiveLink(linkID: createdLink.id)
            reference.forceFullSaveNow()
            guard waitUntil(timeout: 2.0, condition: {
                (try? BWRPackageStore.read(from: packageURL).links.first?.isArchived) == true
            }) else {
                return fail(
                    id: "links",
                    title: "Link Persistence",
                    summary: "archive link 결과가 패키지에 반영되지 않았습니다.",
                    details: ["linkID=\(createdLink.id.uuidString)"]
                )
            }

            let archivedDocument = try BWRPackageStore.read(from: packageURL)
            let archivedHits = BWRDocumentSearch.search(document: archivedDocument, query: createdLink.sourceCardID.uuidString.prefix(8).description, scope: .archiveOnly)
            guard archivedDocument.links.first?.isArchived == true,
                  archivedHits.contains(where: { $0.entityKind == .link && $0.entityID == createdLink.id }) else {
                return fail(
                    id: "links",
                    title: "Link Persistence",
                    summary: "archived link가 저장되었지만 archive search에서 찾을 수 없습니다.",
                    details: [
                        "archived=\(archivedDocument.links.first?.isArchived == true)",
                        "archiveHits=\(archivedHits.count)"
                    ]
                )
            }

            reference.restoreLink(linkID: createdLink.id)
            reference.forceFullSaveNow()
            guard waitUntil(timeout: 2.0, condition: {
                (try? BWRPackageStore.read(from: packageURL).links.first?.isArchived) == false
            }) else {
                return fail(
                    id: "links",
                    title: "Link Persistence",
                    summary: "restore link 결과가 패키지에 반영되지 않았습니다.",
                    details: ["linkID=\(createdLink.id.uuidString)"]
                )
            }

            let restoredDocument = try BWRPackageStore.read(from: packageURL)
            guard restoredDocument.links.count == 1,
                  restoredDocument.links[0].sourceCardID == sourceID,
                  restoredDocument.links[0].destinationCardID == destinationID,
                  restoredDocument.links[0].isArchived == false else {
                return fail(
                    id: "links",
                    title: "Link Persistence",
                    summary: "링크 저장/복구 round-trip 후 source/destination 또는 archive 상태가 보존되지 않았습니다.",
                    details: [
                        "source=\(restoredDocument.links.first?.sourceCardID.uuidString ?? "nil")",
                        "destination=\(restoredDocument.links.first?.destinationCardID.uuidString ?? "nil")",
                        "archived=\(restoredDocument.links.first.map { String($0.isArchived) } ?? "nil")"
                    ]
                )
            }

            return pass(
                id: "links",
                title: "Link Persistence",
                summary: "링크 생성, archive/restore, archive search, .bwr 저장 round-trip이 모두 연결되어 동작합니다.",
                details: [
                    "package=\(packageURL.path)",
                    "linkID=\(createdLink.id.uuidString)"
                ]
            )
        } catch {
            return fail(
                id: "links",
                title: "Link Persistence",
                summary: "링크 저장 검증 중 예외가 발생했습니다.",
                details: [error.localizedDescription]
            )
        }
    }

    private static func macAcceptanceSmokeSuite() -> SuiteResult {
        let packageURL = temporaryPackageURL(prefix: "bwr-m5-mac")
        defer {
            try? FileManager.default.removeItem(at: packageURL)
        }

        do {
            let reference = BWRReferenceDocument(document: macAcceptanceFixture())
            let undoManager = UndoManager()
            undoManager.groupsByEvent = false
            reference.bindUndoManager(undoManager)
            reference.attach(fileURL: packageURL)

            guard let sourceCard = reference.liveCards.first,
                  let sourceLayer = sourceCard.currentLayer else {
                return fail(
                    id: "mac-acceptance",
                    title: "Mac Acceptance Smoke",
                    summary: "fixture의 첫 카드 또는 현재 레이어를 찾지 못했습니다.",
                    details: []
                )
            }

            performUndoStep(undoManager) {
                reference.applyLayerMarkdown(cardID: sourceCard.id, layerID: sourceLayer.id, markdown: "# Revised Board Card")
            }

            let movedPoint = BWRPoint(x: sourceCard.layout.x + 120, y: sourceCard.layout.y + 80)
            performUndoStep(undoManager) {
                reference.setCardLayouts([sourceCard.id: movedPoint])
            }

            var createdCardID: UUID?
            performUndoStep(undoManager) {
                createdCardID = reference.createCard(at: BWRPoint(x: 960, y: 420))
            }
            guard let createdCardID else {
                return fail(
                    id: "mac-acceptance",
                    title: "Mac Acceptance Smoke",
                    summary: "Mac acceptance fixture에서 새 카드를 만들지 못했습니다.",
                    details: []
                )
            }

            performUndoStep(undoManager) {
                reference.addCards(toGroup: reference.liveGroups[0].id, cardIDs: [createdCardID])
            }
            performUndoStep(undoManager) {
                reference.renameGroup(groupID: reference.liveGroups[0].id, newName: "Mac Sequence")
            }
            let renamedGroupName = reference.liveGroups[0].name

            let focusEntries = BWRFocusModeProjection.entries(
                document: reference.document,
                groupID: reference.liveGroups[0].id,
                mode: .currentLayer
            )
            let exportedScenario = BWRExportBridge.exportText(
                document: reference.document,
                groupIDs: [reference.liveGroups[0].id],
                mode: .scenario
            )

            reference.forceFullSaveNow()
            guard waitUntil(timeout: 2.0, condition: {
                (try? BWRPackageStore.read(from: packageURL).cards.count) == reference.document.cards.count
            }) else {
                return fail(
                    id: "mac-acceptance",
                    title: "Mac Acceptance Smoke",
                    summary: "Mac host smoke에서 저장된 .bwr를 다시 읽지 못했습니다.",
                    details: ["package=\(packageURL.path)"]
                )
            }

            let reopened = try BWRPackageStore.read(from: packageURL)
            guard reopened.cards.count == reference.document.cards.count,
                  reopened.groups.count == reference.document.groups.count,
                  focusEntries.count == reference.liveGroups[0].memberCardIDs.count,
                  !exportedScenario.isEmpty,
                  renamedGroupName == "Mac Sequence" else {
                return fail(
                    id: "mac-acceptance",
                    title: "Mac Acceptance Smoke",
                    summary: "보드 편집, 포커스 투영, 출력, 파일 저장 중 하나가 Mac acceptance bar를 넘지 못했습니다.",
                    details: [
                        "cards=\(reopened.cards.count)",
                        "groups=\(reopened.groups.count)",
                        "focusEntries=\(focusEntries.count)",
                        "scenarioLength=\(exportedScenario.count)",
                        "groupName=\(renamedGroupName)"
                    ]
                )
            }

            let canUndoAfterRename = undoManager.canUndo
            undoManager.undo()
            let nameAfterUndo = reference.liveGroups[0].name
            let canRedoAfterUndo = undoManager.canRedo
            undoManager.redo()
            let nameAfterRedo = reference.liveGroups[0].name

            guard canUndoAfterRename,
                  canRedoAfterUndo,
                  nameAfterUndo != "Mac Sequence",
                  nameAfterRedo == "Mac Sequence" else {
                return fail(
                    id: "mac-acceptance",
                    title: "Mac Acceptance Smoke",
                    summary: "Mac acceptance의 undo/redo bar가 통과되지 않았습니다.",
                    details: [
                        "canUndo=\(canUndoAfterRename)",
                        "canRedo=\(canRedoAfterUndo)",
                        "undoName=\(nameAfterUndo)",
                        "redoName=\(nameAfterRedo)"
                    ]
                )
            }

            return pass(
                id: "mac-acceptance",
                title: "Mac Acceptance Smoke",
                summary: "Apple Silicon Mac 검증 호스트에서 보드 편집, 포커스 모드 투영, 파일 저장/열기, 출력, undo/redo 바가 모두 막히지 않습니다.",
                details: [
                    "package=\(packageURL.path)",
                    "cards=\(reopened.cards.count)",
                    "focusEntries=\(focusEntries.count)",
                    "exportLength=\(exportedScenario.count)"
                ]
            )
        } catch {
            return fail(
                id: "mac-acceptance",
                title: "Mac Acceptance Smoke",
                summary: "Mac acceptance smoke 중 예외가 발생했습니다.",
                details: [error.localizedDescription]
            )
        }
    }

    private static func linkFixture() -> BWRDocument {
        let now = Date(timeIntervalSince1970: 1_728_000_000)
        let cardALayers = BWRCard.defaultLayers(
            bodyMarkdown: "# Link Source",
            treatmentMarkdown: "Treat source",
            scenarioMarkdown: "INT. SOURCE - DAY"
        )
        let cardBLayers = BWRCard.defaultLayers(
            bodyMarkdown: "# Link Destination",
            treatmentMarkdown: "Treat destination",
            scenarioMarkdown: "INT. DESTINATION - DAY"
        )

        let cardA = BWRCard(
            stableSortKey: 1,
            colorHex: "E0F2FE",
            currentLayerID: cardALayers[0].id,
            layout: BWRPoint(x: 240, y: 180),
            createdAt: now,
            updatedAt: now,
            layers: cardALayers
        )
        let cardB = BWRCard(
            stableSortKey: 2,
            colorHex: "DCFCE7",
            currentLayerID: cardBLayers[0].id,
            layout: BWRPoint(x: 520, y: 240),
            createdAt: now,
            updatedAt: now,
            layers: cardBLayers
        )

        return BWRDocument(
            schemaVersion: 1,
            createdAt: now,
            updatedAt: now,
            nextStableSortKey: 3,
            cards: [cardA, cardB]
        )
    }

    private static func macAcceptanceFixture() -> BWRDocument {
        let now = Date(timeIntervalSince1970: 1_728_010_000)
        let cardALayers = BWRCard.defaultLayers(
            bodyMarkdown: "# Opening Beat",
            treatmentMarkdown: "Treatment A",
            scenarioMarkdown: "INT. ROOM - DAY\n\nAction A."
        )
        let cardBLayers = BWRCard.defaultLayers(
            bodyMarkdown: "# Conflict",
            treatmentMarkdown: "Treatment B",
            scenarioMarkdown: "INT. HALLWAY - DAY\n\nAction B."
        )

        let cardA = BWRCard(
            stableSortKey: 1,
            colorHex: "F8FAFC",
            currentLayerID: cardALayers[0].id,
            layout: BWRPoint(x: 180, y: 160),
            createdAt: now,
            updatedAt: now,
            layers: cardALayers
        )
        let cardB = BWRCard(
            stableSortKey: 2,
            colorHex: "FEF3C7",
            currentLayerID: cardBLayers[0].id,
            layout: BWRPoint(x: 460, y: 240),
            createdAt: now,
            updatedAt: now,
            layers: cardBLayers
        )
        let group = BWRGroup(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000501")!,
            name: "Sequence 1",
            memberCardIDs: [cardA.id, cardB.id],
            createdAt: now,
            updatedAt: now
        )

        return BWRDocument(
            schemaVersion: 1,
            createdAt: now,
            updatedAt: now,
            nextStableSortKey: 3,
            cards: [cardA, cardB],
            groups: [group]
        )
    }

    private static func temporaryPackageURL(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
            .appendingPathExtension("bwr")
    }

    private static func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    private static func write(report: Report) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            try encoder.encode(report).write(to: reportJSONURL, options: .atomic)
        } catch {
            let fallback = """
            {"error":"failed to encode BWR M5 report","message":"\(error.localizedDescription)"}
            """
            try? fallback.write(to: reportJSONURL, atomically: true, encoding: .utf8)
        }

        try? makeMarkdown(report: report).write(to: reportMarkdownURL, atomically: true, encoding: .utf8)
    }

    private static func makeMarkdown(report: Report) -> String {
        var lines: [String] = []
        lines.append("# BWR Milestone 5 Report")
        lines.append("")
        lines.append("- generatedAt: \(report.generatedAt)")
        lines.append("- suiteCount: \(report.suiteCount)")
        lines.append("- failureCount: \(report.failureCount)")
        lines.append("")

        for suite in report.suites {
            lines.append("## \(suite.title) [\(suite.status.rawValue.uppercased())]")
            lines.append("")
            lines.append(suite.summary)
            lines.append("")
            for detail in suite.details {
                lines.append("- \(detail)")
            }
            lines.append("")
        }

        lines.append("## Paths")
        lines.append("")
        lines.append("- reportJSON: \(reportJSONURL.path)")
        lines.append("- reportMarkdown: \(reportMarkdownURL.path)")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func pass(id: String, title: String, summary: String, details: [String]) -> SuiteResult {
        SuiteResult(id: id, title: title, status: .pass, summary: summary, details: details)
    }

    private static func fail(id: String, title: String, summary: String, details: [String]) -> SuiteResult {
        SuiteResult(id: id, title: title, status: .fail, summary: summary, details: details)
    }

    private static func performUndoStep(_ undoManager: UndoManager, action: () -> Void) {
        undoManager.beginUndoGrouping()
        action()
        undoManager.endUndoGrouping()
    }
}
