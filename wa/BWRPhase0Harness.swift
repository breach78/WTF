import Foundation

enum BWRPhase0Harness {
    nonisolated static let reportJSONURL = URL(fileURLWithPath: "/tmp/bwr_phase0_report.json")
    nonisolated static let reportMarkdownURL = URL(fileURLWithPath: "/tmp/bwr_phase0_report.md")
    nonisolated static let exportScaffoldURL = URL(fileURLWithPath: "/tmp/bwr_phase0_export_scaffold.json")

    struct Report: Codable {
        let generatedAt: String
        let suiteCount: Int
        let failureCount: Int
        let warningCount: Int
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
        case warning
        case fail
    }

    @discardableResult
    nonisolated static func runAll() -> Bool {
        let suites = [
            persistenceRoundTripSuite(),
            rowMajorOrderingSuite(),
            cloneNormalizationSuite(),
            textKeyRoutingSuite(),
            autosavePerformanceSuite(),
            exportParserScaffoldSuite(),
            undoBoundarySuite()
        ]

        let report = Report(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            suiteCount: suites.count,
            failureCount: suites.filter { $0.status == .fail }.count,
            warningCount: suites.filter { $0.status == .warning }.count,
            suites: suites
        )

        write(report: report)
        return report.failureCount == 0
    }

    private nonisolated static func persistenceRoundTripSuite() -> SuiteResult {
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bwr-phase0-roundtrip-\(UUID().uuidString)")
            .appendingPathExtension("bwr")
        defer {
            try? FileManager.default.removeItem(at: packageURL)
        }

        do {
            let document = makeRoundTripFixture()
            try BWRPackageStore.fullWrite(document: document, to: packageURL)
            let restored = try BWRPackageStore.read(from: packageURL)
            guard documentsEquivalent(restored, document) else {
                return fail(
                    id: "roundtrip",
                    title: ".bwr Round-Trip",
                    summary: "패키지 read/write 결과가 원본 문서와 다릅니다.",
                    details: [
                        "package=\(packageURL.path)",
                        "originalCards=\(document.cards.count)",
                        "restoredCards=\(restored.cards.count)"
                    ]
                )
            }

            return pass(
                id: "roundtrip",
                title: ".bwr Round-Trip",
                summary: "패키지 write/read가 안정적으로 round-trip 됩니다.",
                details: [
                    "package=\(packageURL.path)",
                    "cards=\(document.cards.count)",
                    "groups=\(document.groups.count)"
                ]
            )
        } catch {
            return fail(
                id: "roundtrip",
                title: ".bwr Round-Trip",
                summary: "패키지 round-trip 중 예외가 발생했습니다.",
                details: [error.localizedDescription]
            )
        }
    }

    private nonisolated static func rowMajorOrderingSuite() -> SuiteResult {
        let cards = makeOrderingFixture()
        let orderedIDs = BWRRowMajorOrdering.sortedCards(cards).map(\.id.uuidString)
        let expectedIDs = cards
            .sorted(by: manualStableRowMajorCompare)
            .map(\.id.uuidString)

        guard orderedIDs == expectedIDs else {
            return fail(
                id: "ordering",
                title: "Group Row-Major Ordering",
                summary: "row-major 정렬 결과가 기대 순서와 다릅니다.",
                details: [
                    "expected=\(expectedIDs.joined(separator: ","))",
                    "actual=\(orderedIDs.joined(separator: ","))"
                ]
            )
        }

        return pass(
            id: "ordering",
            title: "Group Row-Major Ordering",
            summary: "row-major 정렬이 좌상단→우측→하단 + 안정 tie-breaker를 유지합니다.",
            details: ["orderedIDs=\(orderedIDs.joined(separator: ","))"]
        )
    }

    private nonisolated static func cloneNormalizationSuite() -> SuiteResult {
        let cloneGroupID = UUID()
        let cards = makeCloneFixture(cloneGroupID: cloneGroupID)

        let afterOneRemoval = BWRCloneNormalizer.normalize(
            cards: cards,
            inactiveCardIDs: [cards[0].id]
        )
        let survivingGroupIDs = Set(afterOneRemoval.compactMap { $0.cloneGroupID })
        guard survivingGroupIDs == [cloneGroupID] else {
            return fail(
                id: "clone",
                title: "Clone Normalization",
                summary: "2개가 남아 있을 때 cloneGroup이 유지되지 않았습니다.",
                details: ["survivingGroups=\(survivingGroupIDs.map { $0.uuidString }.joined(separator: ","))"]
            )
        }

        let afterTwoRemovals = BWRCloneNormalizer.normalize(
            cards: cards,
            inactiveCardIDs: [cards[0].id, cards[1].id]
        )
        guard afterTwoRemovals.count == 1, afterTwoRemovals[0].cloneGroupID == nil else {
            return fail(
                id: "clone",
                title: "Clone Normalization",
                summary: "clone group이 1개로 줄어든 뒤 해제되지 않았습니다.",
                details: [
                    "survivorCount=\(afterTwoRemovals.count)",
                    "survivorCloneGroup=\(afterTwoRemovals.first?.cloneGroupID?.uuidString ?? "nil")"
                ]
            )
        }

        return pass(
            id: "clone",
            title: "Clone Normalization",
            summary: "삭제 후 clone 그룹 붕괴 규칙이 기대대로 동작합니다.",
            details: [
                "cloneGroupID=\(cloneGroupID.uuidString)",
                "remainingCardID=\(afterTwoRemovals[0].id.uuidString)"
            ]
        )
    }

    private nonisolated static func textKeyRoutingSuite() -> SuiteResult {
        struct Case {
            let name: String
            let event: BWRTextKeyEvent
            let expected: BWRTextKeyCommandAction
        }

        let cases: [Case] = [
            Case(
                name: "plain-enter",
                event: BWRTextKeyEvent(
                    keyCode: 36,
                    modifiers: BWRTextKeyModifiers(shift: false, command: false, option: false, control: false),
                    hasMarkedText: false
                ),
                expected: .splitCard
            ),
            Case(
                name: "shift-enter",
                event: BWRTextKeyEvent(
                    keyCode: 36,
                    modifiers: BWRTextKeyModifiers(shift: true, command: false, option: false, control: false),
                    hasMarkedText: false
                ),
                expected: .insertNewline
            ),
            Case(
                name: "command-enter",
                event: BWRTextKeyEvent(
                    keyCode: 36,
                    modifiers: BWRTextKeyModifiers(shift: false, command: true, option: false, control: false),
                    hasMarkedText: false
                ),
                expected: .passToSystem
            ),
            Case(
                name: "ime-marked-text",
                event: BWRTextKeyEvent(
                    keyCode: 36,
                    modifiers: BWRTextKeyModifiers(shift: false, command: false, option: false, control: false),
                    hasMarkedText: true
                ),
                expected: .passToSystem
            ),
            Case(
                name: "other-key",
                event: BWRTextKeyEvent(
                    keyCode: 49,
                    modifiers: BWRTextKeyModifiers(shift: false, command: false, option: false, control: false),
                    hasMarkedText: false
                ),
                expected: .passToSystem
            )
        ]

        let mismatches = cases.compactMap { testCase -> String? in
            let actual = BWRTextKeyCommandRouter.resolve(testCase.event)
            guard actual != testCase.expected else { return nil }
            return "\(testCase.name): expected \(testCase.expected.rawValue), got \(actual.rawValue)"
        }

        guard mismatches.isEmpty else {
            return fail(
                id: "text-routing",
                title: "Text Key Routing",
                summary: "Enter / Shift+Enter 라우팅 매트릭스에 불일치가 있습니다.",
                details: mismatches
            )
        }

        return pass(
            id: "text-routing",
            title: "Text Key Routing",
            summary: "Enter / Shift+Enter / IME 예외 라우팅이 계획과 일치합니다.",
            details: cases.map { "\($0.name)=\($0.expected.rawValue)" }
        )
    }

    private nonisolated static func autosavePerformanceSuite() -> SuiteResult {
        do {
            let metrics = try BWRPackageStore.measureAutosave(cardCount: 300)
            let details = [
                String(format: "full=%.2fms", metrics.fullSaveMilliseconds),
                String(format: "delta=%.2fms", metrics.deltaSaveMilliseconds),
                "target=delta < 50ms on iPad Air M2"
            ]

            if metrics.deltaSaveMilliseconds < 50 {
                return pass(
                    id: "autosave",
                    title: "Autosave Performance",
                    summary: "delta save가 phase-0 목표치 안으로 들어왔습니다.",
                    details: details
                )
            }

            if metrics.deltaSaveMilliseconds < 250 {
                return warning(
                    id: "autosave",
                    title: "Autosave Performance",
                    summary: "delta save가 smoke 기준은 통과했지만, iPad 목표치는 아직 보장되지 않습니다.",
                    details: details
                )
            }

            return fail(
                id: "autosave",
                title: "Autosave Performance",
                summary: "delta save가 phase-0 smoke 기준보다 느립니다.",
                details: details
            )
        } catch {
            return fail(
                id: "autosave",
                title: "Autosave Performance",
                summary: "autosave 측정 중 예외가 발생했습니다.",
                details: [error.localizedDescription]
            )
        }
    }

    private nonisolated static func exportParserScaffoldSuite() -> SuiteResult {
        let sample = """
        # BOARD WRITER

        . INT. LAB - DAY

        @RESEARCHER
        The parser scaffold should keep renderer parity honest.

        >CENTERED NOTE<
        """

        let parser = ScriptMarkdownParser(formatType: .centered)
        let elements = parser.parse(sample)
        let elementSummaries = elements.map {
            ExportElementSummary(type: String(describing: $0.type), text: $0.text)
        }

        do {
            let payload = ExportScaffold(
                generatedAt: ISO8601DateFormatter().string(from: Date()),
                sampleInput: sample,
                elementSummaries: elementSummaries
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(payload).write(to: exportScaffoldURL, options: .atomic)

            guard !elementSummaries.isEmpty else {
                return fail(
                    id: "export-scaffold",
                    title: "Export Parser Scaffold",
                    summary: "parser scaffold가 비어 있는 element 배열을 만들었습니다.",
                    details: ["path=\(exportScaffoldURL.path)"]
                )
            }

            return pass(
                id: "export-scaffold",
                title: "Export Parser Scaffold",
                summary: "renderer parity용 parser scaffold를 /tmp에 저장했습니다.",
                details: [
                    "path=\(exportScaffoldURL.path)",
                    "elementCount=\(elementSummaries.count)"
                ]
            )
        } catch {
            return fail(
                id: "export-scaffold",
                title: "Export Parser Scaffold",
                summary: "parser scaffold 저장에 실패했습니다.",
                details: [error.localizedDescription]
            )
        }
    }

    private nonisolated static func undoBoundarySuite() -> SuiteResult {
        let probe = Phase0UndoProbe()
        probe.editText("Alpha brave world")
        probe.splitCurrentCard(atUTF16Location: 12)

        guard probe.segments == ["Alpha brave ", "world"] else {
            return fail(
                id: "undo-boundary",
                title: "Undo Boundary",
                summary: "split 이후 세그먼트 상태가 예상과 다릅니다.",
                details: ["segments=\(probe.segments.joined(separator: " | "))"]
            )
        }

        probe.undoManager.undo()
        guard probe.segments == ["Alpha brave world"] else {
            return fail(
                id: "undo-boundary",
                title: "Undo Boundary",
                summary: "첫 undo가 structural split을 되돌리지 못했습니다.",
                details: ["segments=\(probe.segments.joined(separator: " | "))"]
            )
        }

        probe.undoManager.undo()
        guard probe.segments == ["Alpha world"] else {
            return fail(
                id: "undo-boundary",
                title: "Undo Boundary",
                summary: "두 번째 undo가 선행 텍스트 변경을 되돌리지 못했습니다.",
                details: ["segments=\(probe.segments.joined(separator: " | "))"]
            )
        }

        return pass(
            id: "undo-boundary",
            title: "Undo Boundary",
            summary: "텍스트 변경과 structural split의 undo 경계가 분리되어 있습니다.",
            details: [
                "afterUndo1=Alpha brave world",
                "afterUndo2=Alpha world"
            ]
        )
    }

    private nonisolated static func write(report: Report) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(report).write(to: reportJSONURL, options: .atomic)
        } catch {
            let fallback = """
            {"error":"failed to encode BWR phase-0 report","message":"\(error.localizedDescription)"}
            """
            try? fallback.write(to: reportJSONURL, atomically: true, encoding: .utf8)
        }

        let markdown = makeMarkdown(report: report)
        try? markdown.write(to: reportMarkdownURL, atomically: true, encoding: .utf8)
    }

    private nonisolated static func makeMarkdown(report: Report) -> String {
        var lines: [String] = []
        lines.append("# BWR Phase 0 Report")
        lines.append("")
        lines.append("- generatedAt: \(report.generatedAt)")
        lines.append("- suiteCount: \(report.suiteCount)")
        lines.append("- failureCount: \(report.failureCount)")
        lines.append("- warningCount: \(report.warningCount)")
        lines.append("")

        for suite in report.suites {
            lines.append("## \(suite.title) [\(suite.status.rawValue.uppercased())]")
            lines.append("")
            lines.append(suite.summary)
            lines.append("")
            if !suite.details.isEmpty {
                for detail in suite.details {
                    lines.append("- \(detail)")
                }
                lines.append("")
            }
        }

        lines.append("## Paths")
        lines.append("")
        lines.append("- reportJSON: \(reportJSONURL.path)")
        lines.append("- reportMarkdown: \(reportMarkdownURL.path)")
        lines.append("- exportScaffold: \(exportScaffoldURL.path)")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private nonisolated static func pass(id: String, title: String, summary: String, details: [String]) -> SuiteResult {
        SuiteResult(id: id, title: title, status: .pass, summary: summary, details: details)
    }

    private nonisolated static func warning(id: String, title: String, summary: String, details: [String]) -> SuiteResult {
        SuiteResult(id: id, title: title, status: .warning, summary: summary, details: details)
    }

    private nonisolated static func fail(id: String, title: String, summary: String, details: [String]) -> SuiteResult {
        SuiteResult(id: id, title: title, status: .fail, summary: summary, details: details)
    }

    private nonisolated static func makeRoundTripFixture() -> BWRDocument {
        let cards = BWRPhase0SeedFactory.makeBoardSpikeCards(count: 4)
        let groups = [
            BWRGroup(name: "Sequence A", memberCardIDs: [cards[0].id, cards[1].id]),
            BWRGroup(name: "Sequence B", memberCardIDs: [cards[1].id, cards[2].id, cards[3].id])
        ]
        return BWRDocument(
            schemaVersion: 1,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            cards: cards,
            groups: groups
        )
    }

    private nonisolated static func makeOrderingFixture() -> [BWRCard] {
        let layers = defaultLayers(title: "Ordering")
        let cards = [
            BWRCard(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                stableSortKey: 2,
                currentLayerID: layers[0].id,
                layout: BWRPoint(x: 120.001, y: 10.002),
                createdAt: Date(timeIntervalSince1970: 2),
                updatedAt: Date(timeIntervalSince1970: 2),
                layers: layers
            ),
            BWRCard(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                stableSortKey: 1,
                currentLayerID: layers[0].id,
                layout: BWRPoint(x: 20.001, y: 10.001),
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 1),
                layers: defaultLayers(title: "Ordering")
            ),
            BWRCard(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                stableSortKey: 3,
                currentLayerID: layers[0].id,
                layout: BWRPoint(x: 20.001, y: 150.000),
                createdAt: Date(timeIntervalSince1970: 3),
                updatedAt: Date(timeIntervalSince1970: 3),
                layers: defaultLayers(title: "Ordering")
            ),
            BWRCard(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                stableSortKey: 4,
                currentLayerID: layers[0].id,
                layout: BWRPoint(x: 120.001, y: 10.002),
                createdAt: Date(timeIntervalSince1970: 4),
                updatedAt: Date(timeIntervalSince1970: 4),
                layers: defaultLayers(title: "Ordering")
            )
        ]
        return cards
    }

    private nonisolated static func manualStableRowMajorCompare(_ lhs: BWRCard, _ rhs: BWRCard) -> Bool {
        let leftY = Int((lhs.layout.y * 100.0).rounded())
        let rightY = Int((rhs.layout.y * 100.0).rounded())
        if leftY != rightY { return leftY < rightY }

        let leftX = Int((lhs.layout.x * 100.0).rounded())
        let rightX = Int((rhs.layout.x * 100.0).rounded())
        if leftX != rightX { return leftX < rightX }

        if lhs.stableSortKey != rhs.stableSortKey {
            return lhs.stableSortKey < rhs.stableSortKey
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private nonisolated static func makeCloneFixture(cloneGroupID: UUID) -> [BWRCard] {
        (0..<3).map { index in
            let layers = defaultLayers(title: "Clone \(index)")
            return BWRCard(
                stableSortKey: Int64(index + 1),
                cloneGroupID: cloneGroupID,
                currentLayerID: layers[0].id,
                layout: BWRPoint(x: Double(index) * 100, y: 0),
                createdAt: Date(timeIntervalSince1970: Double(index)),
                updatedAt: Date(timeIntervalSince1970: Double(index)),
                layers: layers
            )
        }
    }

    private nonisolated static func defaultLayers(title: String) -> [BWRCardLayer] {
        let body = BWRCardLayer(kind: .body, name: "Body 1", markdown: "\(title) body", order: 0)
        let treatment = BWRCardLayer(kind: .treatment, name: "Treatment", markdown: "\(title) treatment", order: 1)
        let scenario = BWRCardLayer(kind: .scenario, name: "Scenario", markdown: "\(title) scenario", order: 2)
        return [body, treatment, scenario]
    }

    private nonisolated static func documentsEquivalent(_ lhs: BWRDocument, _ rhs: BWRDocument) -> Bool {
        guard lhs.schemaVersion == rhs.schemaVersion,
              lhs.createdAt == rhs.createdAt,
              lhs.updatedAt == rhs.updatedAt,
              lhs.nextStableSortKey == rhs.nextStableSortKey,
              lhs.groups == rhs.groups,
              lhs.links == rhs.links,
              lhs.archive == rhs.archive,
              lhs.cards.count == rhs.cards.count else {
            return false
        }

        return zip(lhs.cards, rhs.cards).allSatisfy { left, right in
            left.id == right.id &&
            left.stableSortKey == right.stableSortKey &&
            left.cloneGroupID == right.cloneGroupID &&
            left.colorHex == right.colorHex &&
            left.currentLayerID == right.currentLayerID &&
            left.layout == right.layout &&
            left.isArchived == right.isArchived &&
            left.archivedAt == right.archivedAt &&
            left.createdAt == right.createdAt &&
            left.updatedAt == right.updatedAt &&
            left.layers == right.layers
        }
    }
}

private struct ExportScaffold: Codable {
    let generatedAt: String
    let sampleInput: String
    let elementSummaries: [ExportElementSummary]
}

private struct ExportElementSummary: Codable {
    let type: String
    let text: String
}

private final class Phase0UndoProbe {
    var segments: [String] = ["Alpha world"]
    let undoManager: UndoManager = {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }()

    nonisolated func editText(_ updated: String) {
        performGroupedAction(name: "Edit Text") {
            let previous = segments
            registerUndo(previousSegments: previous)
            segments = [updated]
        }
    }

    nonisolated func splitCurrentCard(atUTF16Location location: Int) {
        performGroupedAction(name: "Split Card") {
            guard let first = segments.first else { return }
            let clamped = max(0, min(location, (first as NSString).length))
            let nsText = first as NSString
            let left = nsText.substring(to: clamped)
            let right = nsText.substring(from: clamped)
            let previous = segments
            registerUndo(previousSegments: previous)
            segments = [left, right]
        }
    }

    private nonisolated func registerUndo(previousSegments: [String]) {
        undoManager.registerUndo(withTarget: self) { target in
            let current = target.segments
            target.registerUndo(previousSegments: current)
            target.segments = previousSegments
        }
    }

    private nonisolated func performGroupedAction(name: String, _ body: () -> Void) {
        undoManager.beginUndoGrouping()
        body()
        undoManager.setActionName(name)
        undoManager.endUndoGrouping()
    }
}
