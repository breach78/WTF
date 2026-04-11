import Foundation
import CryptoKit
import PDFKit

@MainActor
enum BWRMilestone4Harness {
    nonisolated static let reportJSONURL = URL(fileURLWithPath: "/tmp/bwr_m4_report.json")
    nonisolated static let reportMarkdownURL = URL(fileURLWithPath: "/tmp/bwr_m4_report.md")
    nonisolated static let artifactsDirectoryURL = URL(fileURLWithPath: "/tmp/bwr_m4_artifacts", isDirectory: true)

    private static let goldenScenarioTextSHA256 = "49ca4af8336fdb1efc3b5e447c820c853ef7db09b6a2008ebca7ee2861df9854"
    private static let goldenCenteredPDFSignature = PDFSignature(
        pageCount: 1,
        pageTextHash: "015a4bd3b2aa4b835a05db2333c02db31a8fa8092b0d3c12b408dc9e1c3b5fa2",
        mediaBoxes: ["595.2x841.8"],
        byteCount: 9639
    )
    private static let goldenKoreanPDFSignature = PDFSignature(
        pageCount: 1,
        pageTextHash: "7274988fbd7a96f8029f1cb189cbbe619d2596b7b192b541f803e708de4b1013",
        mediaBoxes: ["595.2x841.8"],
        byteCount: 9757
    )

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

    struct PDFSignature: Equatable {
        let pageCount: Int
        let pageTextHash: String
        let mediaBoxes: [String]
        let byteCount: Int

        var summary: String {
            "pages=\(pageCount), textHash=\(pageTextHash), boxes=\(mediaBoxes.joined(separator: ",")), bytes=\(byteCount)"
        }
    }

    @discardableResult
    static func runAll() -> Bool {
        let suites = [
            exportBridgeSuite(),
            parserParitySuite(),
            settingsParitySuite(),
            goldenOutputSuite()
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

    private static func exportBridgeSuite() -> SuiteResult {
        let fixture = exportFixture()
        let groupID = fixture.groups[0].id

        let currentText = BWRExportBridge.exportText(document: fixture, groupIDs: [groupID], mode: .currentLayer)
        let treatmentText = BWRExportBridge.exportText(document: fixture, groupIDs: [groupID], mode: .treatment)
        let scenarioText = BWRExportBridge.exportText(document: fixture, groupIDs: [groupID], mode: .scenario)

        guard currentText == expectedCurrentText,
              treatmentText == expectedTreatmentText,
              scenarioText == expectedScenarioText else {
            return fail(
                id: "bridge",
                title: "Export Bridge Composition",
                summary: "선택 그룹 row-major 조합 또는 빈 레이어 필터링 결과가 계획과 다릅니다.",
                details: [
                    "current=\(quoted(currentText))",
                    "treatment=\(quoted(treatmentText))",
                    "scenario=\(quoted(scenarioText))"
                ]
            )
        }

        return pass(
            id: "bridge",
            title: "Export Bridge Composition",
            summary: "BWR export bridge가 현재/Treatment/Scenario 텍스트를 row-major 순서와 빈 레이어 필터링 규칙대로 조합합니다.",
            details: [
                "currentFragments=2",
                "treatmentFragments=3",
                "scenarioFragments=3"
            ]
        )
    }

    private static func parserParitySuite() -> SuiteResult {
        let fixture = exportFixture()
        let groupID = fixture.groups[0].id
        let currentText = BWRExportBridge.exportText(document: fixture, groupIDs: [groupID], mode: .currentLayer)

        let centeredSignatures = elementSignatures(BWRExportBridge.parse(text: currentText, format: .centered))
        let koreanSignatures = elementSignatures(BWRExportBridge.parse(text: currentText, format: .korean))

        guard centeredSignatures == expectedCenteredElementSignatures,
              koreanSignatures == expectedKoreanElementSignatures else {
            return fail(
                id: "parser",
                title: "Parser Element Parity",
                summary: "BWR export text가 기존 parser에서 기대한 element 배열로 해석되지 않았습니다.",
                details: [
                    "centered=\(centeredSignatures.joined(separator: " | "))",
                    "korean=\(koreanSignatures.joined(separator: " | "))"
                ]
            )
        }

        return pass(
            id: "parser",
            title: "Parser Element Parity",
            summary: "BWR export text가 기존 centered/korean parser에서 계획한 element 배열로 파싱됩니다.",
            details: [
                "centeredCount=\(centeredSignatures.count)",
                "koreanCount=\(koreanSignatures.count)"
            ]
        )
    }

    private static func settingsParitySuite() -> SuiteResult {
        let suiteName = "bwr.m4.settings.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return fail(
                id: "settings",
                title: "Export Settings Parity",
                summary: "하네스 전용 UserDefaults를 만들지 못했습니다.",
                details: []
            )
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(13.5, forKey: "exportCenteredFontSize")
        defaults.set(false, forKey: "exportCenteredCharacterBold")
        defaults.set(false, forKey: "exportCenteredSceneHeadingBold")
        defaults.set(true, forKey: "exportCenteredShowRightSceneNumber")
        defaults.set(10.5, forKey: "exportKoreanFontSize")
        defaults.set(false, forKey: "exportKoreanSceneBold")
        defaults.set(false, forKey: "exportKoreanCharacterBold")
        defaults.set("left", forKey: "exportKoreanCharacterAlignment")

        let loaded = BWRExportBridge.loadLayoutConfig(userDefaults: defaults)
        let baselineSuiteName = "bwr.m4.defaults.\(UUID().uuidString)"
        let baselineDefaults = UserDefaults(suiteName: baselineSuiteName)!
        defer {
            baselineDefaults.removePersistentDomain(forName: baselineSuiteName)
        }
        let baseline = BWRExportBridge.loadLayoutConfig(userDefaults: baselineDefaults)

        guard loaded.centeredFontSize == 13.5,
              loaded.centeredIsCharacterBold == false,
              loaded.centeredIsSceneHeadingBold == false,
              loaded.centeredShowRightSceneNumber == true,
              loaded.koreanFontSize == 10.5,
              loaded.koreanIsSceneBold == false,
              loaded.koreanIsCharacterBold == false,
              alignmentName(loaded.koreanCharacterAlignment) == "left",
              baseline.centeredFontSize == 12.0,
              baseline.koreanFontSize == 11.0,
              baseline.centeredIsCharacterBold == true,
              baseline.koreanIsCharacterBold == true else {
            return fail(
                id: "settings",
                title: "Export Settings Parity",
                summary: "기존 export AppStorage/UserDefaults 키를 BWR bridge가 정확히 해석하지 못했습니다.",
                details: [
                    "loaded.centeredFont=\(loaded.centeredFontSize)",
                    "loaded.koreanFont=\(loaded.koreanFontSize)",
                    "loaded.koreanAlignment=\(alignmentName(loaded.koreanCharacterAlignment))",
                    "baseline.centeredFont=\(baseline.centeredFontSize)",
                    "baseline.koreanFont=\(baseline.koreanFontSize)"
                ]
            )
        }

        return pass(
            id: "settings",
            title: "Export Settings Parity",
            summary: "기존 export 설정 키와 기본값을 BWR bridge가 그대로 읽어 layout config에 반영합니다.",
            details: [
                "loaded.centeredFont=\(loaded.centeredFontSize)",
                "loaded.koreanAlignment=\(alignmentName(loaded.koreanCharacterAlignment))"
            ]
        )
    }

    private static func goldenOutputSuite() -> SuiteResult {
        let fixture = exportFixture()
        let groupID = fixture.groups[0].id
        let defaults = goldenDefaults()
        let scenarioText = BWRExportBridge.exportText(document: fixture, groupIDs: [groupID], mode: .scenario)
        let centeredData = BWRExportBridge.pdfData(text: scenarioText, format: .centered, userDefaults: defaults)
        let koreanData = BWRExportBridge.pdfData(text: scenarioText, format: .korean, userDefaults: defaults)

        let scenarioHash = sha256Hex(for: Data(scenarioText.utf8))
        guard let centeredSignature = pdfSignature(for: centeredData),
              let koreanSignature = pdfSignature(for: koreanData) else {
            return fail(
                id: "golden",
                title: "Golden Output Comparison",
                summary: "생성된 PDF를 PDFKit으로 다시 읽지 못했습니다.",
                details: ["artifacts=\(artifactsDirectoryURL.path)"]
            )
        }

        writeGoldenArtifacts(text: scenarioText, centeredData: centeredData, koreanData: koreanData)

        guard scenarioHash == goldenScenarioTextSHA256,
              centeredSignature == goldenCenteredPDFSignature,
              koreanSignature == goldenKoreanPDFSignature else {
            return fail(
                id: "golden",
                title: "Golden Output Comparison",
                summary: "BWR export renderer output이 고정 golden fixture와 일치하지 않습니다.",
                details: [
                    "scenarioHash=\(scenarioHash)",
                    "centered=\(centeredSignature.summary)",
                    "korean=\(koreanSignature.summary)",
                    "artifacts=\(artifactsDirectoryURL.path)"
                ]
            )
        }

        return pass(
            id: "golden",
            title: "Golden Output Comparison",
            summary: "scenario export text와 centered/korean PDF 렌더 시그니처가 고정 golden fixture와 일치합니다.",
            details: [
                "scenarioHash=\(scenarioHash)",
                "centered=\(centeredSignature.summary)",
                "korean=\(koreanSignature.summary)"
            ]
        )
    }

    private static func exportFixture() -> BWRDocument {
        let now = Date(timeIntervalSince1970: 2_000)

        let cardALayers = configuredLayers(
            bodyMarkdowns: [
                "Body A 1",
                "# Card A\n.INT. ROOF - NIGHT\n@MIRA\nWe jump."
            ],
            treatmentMarkdown: "Treatment A",
            scenarioMarkdown: ".INT. ROOF - NIGHT\n@MIRA\nWe jump."
        )
        let cardBLayers = configuredLayers(
            bodyMarkdowns: [""],
            treatmentMarkdown: "Treatment B",
            scenarioMarkdown: ".EXT. STREET - DAY\n@JUN\nRun."
        )
        let cardCLayers = configuredLayers(
            bodyMarkdowns: ["Body C"],
            treatmentMarkdown: "Treatment C",
            scenarioMarkdown: "CUT TO:"
        )

        let cardA = BWRCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            stableSortKey: 1,
            currentLayerID: cardALayers[1].id,
            layout: BWRPoint(x: 40, y: 40),
            createdAt: now,
            updatedAt: now,
            layers: cardALayers
        )
        let cardB = BWRCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            stableSortKey: 2,
            currentLayerID: cardBLayers[0].id,
            layout: BWRPoint(x: 260, y: 40),
            createdAt: now,
            updatedAt: now,
            layers: cardBLayers
        )
        let cardC = BWRCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
            stableSortKey: 3,
            currentLayerID: cardCLayers[1].id,
            layout: BWRPoint(x: 60, y: 260),
            createdAt: now,
            updatedAt: now,
            layers: cardCLayers
        )

        let group = BWRGroup(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000001F0")!,
            name: "Sequence One",
            memberCardIDs: [cardB.id, cardC.id, cardA.id],
            createdAt: now,
            updatedAt: now
        )

        return BWRDocument(
            schemaVersion: 1,
            createdAt: now,
            updatedAt: now,
            nextStableSortKey: 4,
            cards: [cardA, cardB, cardC],
            groups: [group]
        )
    }

    private static func configuredLayers(
        bodyMarkdowns: [String],
        treatmentMarkdown: String,
        scenarioMarkdown: String
    ) -> [BWRCardLayer] {
        let bodyCount = max(1, bodyMarkdowns.count)
        return BWRCard.defaultLayers(
            bodyMarkdown: bodyMarkdowns.first ?? "",
            bodyCount: bodyCount,
            treatmentMarkdown: treatmentMarkdown,
            scenarioMarkdown: scenarioMarkdown
        ).map { layer in
            guard layer.kind == .body else { return layer }
            let bodyIndex = layer.order
            var updated = layer
            if bodyIndex < bodyMarkdowns.count {
                updated.markdown = bodyMarkdowns[bodyIndex]
            }
            return updated
        }
    }

    private static var expectedCurrentText: String {
        """
        # Card A
        .INT. ROOF - NIGHT
        @MIRA
        We jump.

        Treatment C
        """
    }

    private static var expectedTreatmentText: String {
        """
        Treatment A

        Treatment B

        Treatment C
        """
    }

    private static var expectedScenarioText: String {
        """
        .INT. ROOF - NIGHT
        @MIRA
        We jump.

        .EXT. STREET - DAY
        @JUN
        Run.

        CUT TO:
        """
    }

    private static var expectedCenteredElementSignatures: [String] {
        [
            "title|Card A",
            "sceneHeading|INT. ROOF - NIGHT",
            "character|MIRA",
            "dialogue|We jump.",
            "action|Treatment C"
        ]
    }

    private static var expectedKoreanElementSignatures: [String] {
        [
            "coverTitle|Card A",
            "sceneHeading|INT. ROOF - NIGHT",
            "character|MIRA",
            "dialogue|We jump.",
            "action|Treatment C"
        ]
    }

    private static func goldenDefaults() -> UserDefaults {
        let suiteName = "bwr.m4.golden"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(12.0, forKey: "exportCenteredFontSize")
        defaults.set(true, forKey: "exportCenteredCharacterBold")
        defaults.set(true, forKey: "exportCenteredSceneHeadingBold")
        defaults.set(false, forKey: "exportCenteredShowRightSceneNumber")
        defaults.set(11.0, forKey: "exportKoreanFontSize")
        defaults.set(true, forKey: "exportKoreanSceneBold")
        defaults.set(true, forKey: "exportKoreanCharacterBold")
        defaults.set("right", forKey: "exportKoreanCharacterAlignment")
        return defaults
    }

    private static func writeGoldenArtifacts(text: String, centeredData: Data, koreanData: Data) {
        try? FileManager.default.createDirectory(
            at: artifactsDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try? text.write(to: artifactsDirectoryURL.appendingPathComponent("scenario.txt"), atomically: true, encoding: .utf8)
        try? centeredData.write(to: artifactsDirectoryURL.appendingPathComponent("scenario_centered.pdf"))
        try? koreanData.write(to: artifactsDirectoryURL.appendingPathComponent("scenario_korean.pdf"))
    }

    private static func elementSignatures(_ elements: [ScriptExportElement]) -> [String] {
        elements.map { "\(elementTypeName($0.type))|\($0.text)" }
    }

    private static func elementTypeName(_ type: ScriptExportElementType) -> String {
        switch type {
        case .sceneHeading: return "sceneHeading"
        case .action: return "action"
        case .character: return "character"
        case .dialogue: return "dialogue"
        case .parenthetical: return "parenthetical"
        case .transition: return "transition"
        case .centered: return "centered"
        case .title: return "title"
        case .revision: return "revision"
        case .date: return "date"
        case .author: return "author"
        case .company: return "company"
        case .contact: return "contact"
        case .coverTitle: return "coverTitle"
        case .coverVersion: return "coverVersion"
        case .coverDate: return "coverDate"
        case .coverAuthor: return "coverAuthor"
        case .coverProduction: return "coverProduction"
        case .coverContact: return "coverContact"
        }
    }

    private static func alignmentName(_ alignment: ScriptExportCharacterAlignment) -> String {
        switch alignment {
        case .left:
            return "left"
        case .right:
            return "right"
        }
    }

    private static func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func pdfSignature(for data: Data) -> PDFSignature? {
        guard let document = PDFDocument(data: data) else { return nil }

        var pageTexts: [String] = []
        var boxes: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            pageTexts.append(page.string ?? "")
            let box = page.bounds(for: .mediaBox)
            boxes.append(String(format: "%.1fx%.1f", box.width, box.height))
        }

        let joinedText = pageTexts.joined(separator: "\n--PAGE--\n")
        return PDFSignature(
            pageCount: document.pageCount,
            pageTextHash: sha256Hex(for: Data(joinedText.utf8)),
            mediaBoxes: boxes,
            byteCount: data.count
        )
    }

    private static func quoted(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: "\\n")
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
        if let json = try? encoder.encode(report) {
            try? json.write(to: reportJSONURL)
        }

        let markdown = """
        # BWR Milestone 4 Harness

        - generatedAt: \(report.generatedAt)
        - suiteCount: \(report.suiteCount)
        - failureCount: \(report.failureCount)

        \(report.suites.map(markdownSection).joined(separator: "\n\n"))
        """

        try? markdown.write(to: reportMarkdownURL, atomically: true, encoding: .utf8)
    }

    private static func markdownSection(_ suite: SuiteResult) -> String {
        let detailsBlock = suite.details.map { "- \($0)" }.joined(separator: "\n")
        return """
        ## [\(suite.status.rawValue.uppercased())] \(suite.title)

        - id: \(suite.id)
        - summary: \(suite.summary)
        \(detailsBlock)
        """
    }
}
