import Foundation

@MainActor
enum BWRMilestone3Harness {
    nonisolated static let reportJSONURL = URL(fileURLWithPath: "/tmp/bwr_m3_report.json")
    nonisolated static let reportMarkdownURL = URL(fileURLWithPath: "/tmp/bwr_m3_report.md")

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
            projectionModesSuite(),
            focusSearchSuite(),
            visibleLayerSplitSuite(),
            textUndoBoundarySuite()
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

    private static func projectionModesSuite() -> SuiteResult {
        let document = projectionFixture()
        let currentEntries = BWRFocusModeProjection.entries(document: document, groupID: document.groups[0].id, mode: .currentLayer)
        let treatmentEntries = BWRFocusModeProjection.entries(document: document, groupID: document.groups[0].id, mode: .treatment)
        let scenarioEntries = BWRFocusModeProjection.entries(document: document, groupID: document.groups[0].id, mode: .scenario)

        let currentLayerNames = currentEntries.map(\.layerName)
        let treatmentTexts = treatmentEntries.map(\.markdown)
        let scenarioTexts = scenarioEntries.map(\.markdown)
        let orderedCardIDs = currentEntries.map(\.cardID)

        guard currentEntries.count == 3,
              currentLayerNames == ["Body 2", "Treatment", "Body 1"],
              treatmentTexts == ["Treat A", "Treat C", "Treat B"],
              scenarioTexts == ["Scene A", "Scene C", "Scene B"],
              orderedCardIDs == [document.cards[0].id, document.cards[2].id, document.cards[1].id] else {
            return fail(
                id: "projection",
                title: "Focus Projection Modes",
                summary: "current/treatment/scenario 투영 또는 row-major 순서가 계획과 다릅니다.",
                details: [
                    "currentLayers=\(currentLayerNames.joined(separator: ","))",
                    "treatmentTexts=\(treatmentTexts.joined(separator: "|"))",
                    "ordered=\(orderedCardIDs.map(\.uuidString).joined(separator: ","))"
                ]
            )
        }

        return pass(
            id: "projection",
            title: "Focus Projection Modes",
            summary: "포커스 모드가 그룹 row-major 순서를 유지한 채 current/treatment/scenario 레이어를 올바르게 투영합니다.",
            details: [
                "currentLayers=\(currentLayerNames.joined(separator: ","))",
                "cards=\(currentEntries.count)"
            ]
        )
    }

    private static func focusSearchSuite() -> SuiteResult {
        let document = projectionFixture()
        let entries = BWRFocusModeProjection.entries(document: document, groupID: document.groups[0].id, mode: .treatment)
        let overriddenTexts = Dictionary(uniqueKeysWithValues: entries.map { entry in
            let suffix = entry.cardIndex == 1 ? " needle" : ""
            return (entry.id, "\(entry.markdown)\(suffix)")
        })
        let matches = BWRFocusSearchEngine.matches(query: "needle", entries: entries, textByEntryID: overriddenTexts)

        guard matches.count == 1,
              matches[0].entryID == entries[1].id,
              matches[0].preview.contains("needle") else {
            return fail(
                id: "search",
                title: "Focus Search Popup",
                summary: "포커스 검색 엔진이 예상 match를 찾지 못했습니다.",
                details: [
                    "matchCount=\(matches.count)",
                    "preview=\(matches.first?.preview ?? "nil")"
                ]
            )
        }

        return pass(
            id: "search",
            title: "Focus Search Popup",
            summary: "포커스 검색이 현재 포커스 텍스트 조합을 기준으로 match를 찾아 이동 가능한 결과를 만듭니다.",
            details: [
                "entry=\(matches[0].entryID.rawValue)",
                "preview=\(matches[0].preview)"
            ]
        )
    }

    private static func visibleLayerSplitSuite() -> SuiteResult {
        let reference = BWRReferenceDocument(document: splitFixture())
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        reference.bindUndoManager(undoManager)

        guard let sourceCard = reference.liveCards.first,
              let treatmentLayer = sourceCard.layers.first(where: { $0.kind == .treatment }),
              let scenarioLayer = sourceCard.layers.first(where: { $0.kind == .scenario }) else {
            return fail(
                id: "split-visible-layer",
                title: "Focus Visible Layer Split",
                summary: "split fixture에서 treatment/scenario 레이어를 찾지 못했습니다.",
                details: []
            )
        }

        let originalBody = sourceCard.layers.first(where: { $0.kind == .body })?.markdown
        let originalScenario = scenarioLayer.markdown
        let committedTreatment = "TreatLeft||TreatRight"
        let splitLocation = ("TreatLeft" as NSString).length

        var newCardID: UUID?
        performUndoStep(undoManager) {
            newCardID = reference.splitCard(
                cardID: sourceCard.id,
                layerID: treatmentLayer.id,
                committedMarkdown: committedTreatment,
                atUTF16Location: splitLocation
            )
        }

        guard let newCardID,
        let updatedSource = reference.liveCards.first(where: { $0.id == sourceCard.id }),
        let newCard = reference.liveCards.first(where: { $0.id == newCardID }),
        let updatedSourceTreatment = updatedSource.layers.first(where: { $0.kind == .treatment }),
        let updatedSourceScenario = updatedSource.layers.first(where: { $0.kind == .scenario }),
        let newTreatment = newCard.layers.first(where: { $0.kind == .treatment }),
        let newScenario = newCard.layers.first(where: { $0.kind == .scenario }),
        let newBody = newCard.layers.first(where: { $0.kind == .body }) else {
            return fail(
                id: "split-visible-layer",
                title: "Focus Visible Layer Split",
                summary: "treatment focused split 결과를 해석하지 못했습니다.",
                details: []
            )
        }

        let allGroupMembersContainNewCard = reference.liveGroups.allSatisfy { group in
            !group.memberCardIDs.contains(sourceCard.id) || group.memberCardIDs.contains(newCardID)
        }

        guard updatedSourceTreatment.markdown == "TreatLeft",
              newTreatment.markdown == "||TreatRight",
              updatedSourceScenario.markdown == originalScenario,
              newScenario.markdown.isEmpty,
              originalBody == updatedSource.layers.first(where: { $0.kind == .body })?.markdown,
              newBody.markdown.isEmpty,
              newCard.currentLayerID == newTreatment.id,
              allGroupMembersContainNewCard else {
            return fail(
                id: "split-visible-layer",
                title: "Focus Visible Layer Split",
                summary: "포커스에서 보이는 레이어만 분할해야 하는 규칙이 깨졌습니다.",
                details: [
                    "source.treat=\(updatedSourceTreatment.markdown)",
                    "new.treat=\(newTreatment.markdown)",
                    "new.currentLayer=\(newCard.currentLayerID.uuidString)",
                    "groupsContainNew=\(allGroupMembersContainNewCard)"
                ]
            )
        }

        return pass(
            id: "split-visible-layer",
            title: "Focus Visible Layer Split",
            summary: "포커스 분할이 visible layer만 나누고, 다른 레이어는 유지한 채 새 카드를 같은 그룹들에 붙입니다.",
            details: [
                "newCard=\(newCardID.uuidString)",
                "newTreatment=\(newTreatment.markdown)"
            ]
        )
    }

    private static func textUndoBoundarySuite() -> SuiteResult {
        let reference = BWRReferenceDocument(document: splitFixture())
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        reference.bindUndoManager(undoManager)

        guard let card = reference.liveCards.first,
              let bodyLayer = card.layers.first(where: { $0.kind == .body }) else {
            return fail(
                id: "text-boundary",
                title: "Focus Text Boundary",
                summary: "text boundary fixture 레이어를 찾지 못했습니다.",
                details: []
            )
        }

        reference.applyLayerMarkdownChanges(
            [BWRLayerMarkdownChange(cardID: card.id, layerID: bodyLayer.id, markdown: "Edited body.")],
            registerUndo: false
        )

        let noUndoRecorded = !(undoManager.canUndo)
        let sentenceBoundary = BWRFocusTextBoundaryDetector.detect(
            previous: "One",
            current: "One.",
            selection: NSRange(location: 4, length: 0)
        )
        let paragraphBoundary = BWRFocusTextBoundaryDetector.detect(
            previous: "One\n",
            current: "One\n\n",
            selection: NSRange(location: 5, length: 0)
        )

        performUndoStep(undoManager) {
            reference.renameGroup(groupID: reference.liveGroups[0].id, newName: "Renamed Sequence")
        }
        let structuralUndoRecorded = undoManager.canUndo

        guard noUndoRecorded,
              sentenceBoundary == .sentence,
              paragraphBoundary == .paragraph,
              structuralUndoRecorded else {
            return fail(
                id: "text-boundary",
                title: "Focus Text Boundary",
                summary: "text commit/no-undo 또는 boundary detection 규칙이 어긋났습니다.",
                details: [
                    "noUndoRecorded=\(noUndoRecorded)",
                    "sentenceBoundary=\(sentenceBoundary?.rawValue ?? "nil")",
                    "paragraphBoundary=\(paragraphBoundary?.rawValue ?? "nil")",
                    "structuralUndoRecorded=\(structuralUndoRecorded)"
                ]
            )
        }

        return pass(
            id: "text-boundary",
            title: "Focus Text Boundary",
            summary: "포커스 텍스트 commit은 structural undo를 오염시키지 않고, 문장/문단 경계를 별도 boundary로 감지합니다.",
            details: [
                "sentenceBoundary=\(sentenceBoundary?.rawValue ?? "nil")",
                "paragraphBoundary=\(paragraphBoundary?.rawValue ?? "nil")"
            ]
        )
    }

    private static func projectionFixture() -> BWRDocument {
        let now = Date(timeIntervalSince1970: 500)
        let cardA = makeCard(
            stableSortKey: 1,
            layout: BWRPoint(x: 120, y: 120),
            bodyMarkdowns: ["Body A1", "Body A2"],
            currentBodyIndex: 1,
            treatmentMarkdown: "Treat A",
            scenarioMarkdown: "Scene A",
            timestamp: now
        )
        let cardB = makeCard(
            stableSortKey: 2,
            layout: BWRPoint(x: 180, y: 280),
            bodyMarkdowns: ["Body B1"],
            currentBodyIndex: 0,
            treatmentMarkdown: "Treat B",
            scenarioMarkdown: "Scene B",
            timestamp: now.addingTimeInterval(1)
        )
        let cardC = makeCard(
            stableSortKey: 3,
            layout: BWRPoint(x: 340, y: 120),
            bodyMarkdowns: ["Body C1"],
            currentBodyIndex: 0,
            treatmentMarkdown: "Treat C",
            scenarioMarkdown: "Scene C",
            timestamp: now.addingTimeInterval(2)
        )

        var adjustedCardC = cardC
        if let treatmentLayer = adjustedCardC.layers.first(where: { $0.kind == .treatment }) {
            adjustedCardC.currentLayerID = treatmentLayer.id
        }

        return BWRDocument(
            schemaVersion: 1,
            createdAt: now,
            updatedAt: now,
            nextStableSortKey: 4,
            cards: [cardA, cardB, adjustedCardC],
            groups: [
                BWRGroup(
                    name: "Sequence A",
                    memberCardIDs: [cardA.id, adjustedCardC.id, cardB.id],
                    createdAt: now,
                    updatedAt: now
                )
            ]
        )
    }

    private static func splitFixture() -> BWRDocument {
        let now = Date(timeIntervalSince1970: 900)
        let source = makeCard(
            stableSortKey: 1,
            layout: BWRPoint(x: 120, y: 120),
            bodyMarkdowns: ["Body Original"],
            currentBodyIndex: 0,
            treatmentMarkdown: "Treat Original",
            scenarioMarkdown: "Scene Original",
            timestamp: now
        )
        let companion = makeCard(
            stableSortKey: 2,
            layout: BWRPoint(x: 360, y: 120),
            bodyMarkdowns: ["Companion"],
            currentBodyIndex: 0,
            treatmentMarkdown: "Companion Treat",
            scenarioMarkdown: "Companion Scene",
            timestamp: now.addingTimeInterval(1)
        )

        return BWRDocument(
            schemaVersion: 1,
            createdAt: now,
            updatedAt: now,
            nextStableSortKey: 3,
            cards: [source, companion],
            groups: [
                BWRGroup(
                    name: "Focus Group",
                    memberCardIDs: [source.id, companion.id],
                    createdAt: now,
                    updatedAt: now
                )
            ]
        )
    }

    private static func makeCard(
        stableSortKey: Int64,
        layout: BWRPoint,
        bodyMarkdowns: [String],
        currentBodyIndex: Int,
        treatmentMarkdown: String,
        scenarioMarkdown: String,
        timestamp: Date
    ) -> BWRCard {
        let bodyCount = max(1, bodyMarkdowns.count)
        var layers = BWRCard.defaultLayers(
            bodyMarkdown: bodyMarkdowns.first ?? "",
            bodyCount: bodyCount,
            treatmentMarkdown: treatmentMarkdown,
            scenarioMarkdown: scenarioMarkdown
        )

        for index in layers.indices where layers[index].kind == .body {
            layers[index].markdown = bodyMarkdowns[index]
        }

        let currentBodyLayer = layers.filter { $0.kind == .body }[min(max(0, currentBodyIndex), bodyCount - 1)]
        return BWRCard(
            stableSortKey: stableSortKey,
            colorHex: "F8FAFC",
            currentLayerID: currentBodyLayer.id,
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
        # BWR Milestone 3 Harness

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
