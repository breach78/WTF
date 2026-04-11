import Foundation

nonisolated enum BWRCardBuddyPhase0Harness {
    nonisolated static let reportJSONURL = URL(fileURLWithPath: "/tmp/bwr_cardbuddy_phase0_report.json")
    nonisolated static let reportMarkdownURL = URL(fileURLWithPath: "/tmp/bwr_cardbuddy_phase0_report.md")

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
            dependencyMapSuite(),
            themeRoundTripSuite(),
            markdownPreviewSuite(),
            snapshotFixtureSuite()
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

    private nonisolated static func dependencyMapSuite() -> SuiteResult {
        let missingPaths = BWRCardBuddyPhase0DependencyMap.entries.compactMap { entry -> String? in
            FileManager.default.fileExists(atPath: entry.filePath)
                ? nil
                : "\(entry.id)=missing \(entry.filePath)"
        }

        guard missingPaths.isEmpty else {
            return fail(
                id: "dependency-map",
                title: "Dependency Map",
                summary: "Phase 0 seam map가 가리키는 파일 중 누락된 경로가 있습니다.",
                details: missingPaths
            )
        }

        return pass(
            id: "dependency-map",
            title: "Dependency Map",
            summary: "cursor / hover / drag / preview / theme / snapshot host seam이 모두 고정됐습니다.",
            details: BWRCardBuddyPhase0DependencyMap.entries.map {
                "\($0.id)=\($0.filePath)"
            }
        )
    }

    private nonisolated static func themeRoundTripSuite() -> SuiteResult {
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bwr-cardbuddy-phase0-\(UUID().uuidString)")
            .appendingPathExtension("bwr")
        defer {
            try? FileManager.default.removeItem(at: packageURL)
        }

        do {
            var document = BWRCardBuddyVisualSnapshotFactory.fixtures()[0].document
            document.boardTheme = BWRBoardThemeState(
                boardBackgroundHex: "D9F99D",
                boardAccentMode: .cool
            )

            try BWRPackageStore.fullWrite(document: document, to: packageURL)
            let restored = try BWRPackageStore.read(from: packageURL)

            guard restored.boardTheme == document.boardTheme else {
                return fail(
                    id: "theme-roundtrip",
                    title: "Theme Round-Trip",
                    summary: "board theme가 .bwr package round-trip 뒤 유지되지 않았습니다.",
                    details: [
                        "expected=\(String(describing: document.boardTheme.boardBackgroundHex))/\(document.boardTheme.boardAccentMode.rawValue)",
                        "actual=\(String(describing: restored.boardTheme.boardBackgroundHex))/\(restored.boardTheme.boardAccentMode.rawValue)"
                    ]
                )
            }

            return pass(
                id: "theme-roundtrip",
                title: "Theme Round-Trip",
                summary: "board background / accent theme가 project manifest에 저장됩니다.",
                details: ["package=\(packageURL.path)"]
            )
        } catch {
            return fail(
                id: "theme-roundtrip",
                title: "Theme Round-Trip",
                summary: "board theme round-trip 중 예외가 발생했습니다.",
                details: [error.localizedDescription]
            )
        }
    }

    private nonisolated static func markdownPreviewSuite() -> SuiteResult {
        let markdown = """
        **Bold opener**
        - first bullet
        - second bullet
        soft break trail  
        next line
        final line
        """

        let preview = BWRCardMarkdownPreviewRenderer.render(markdown, lineLimit: 5)
        guard preview.containsStrongEmphasis,
              preview.containsListItems,
              preview.containsSoftBreaks,
              preview.didTruncate else {
            return fail(
                id: "markdown-preview",
                title: "Markdown Preview Renderer",
                summary: "markdown preview seam이 기대한 preview metadata를 만들지 못했습니다.",
                details: [
                    "containsStrong=\(preview.containsStrongEmphasis)",
                    "containsList=\(preview.containsListItems)",
                    "containsSoftBreak=\(preview.containsSoftBreaks)",
                    "didTruncate=\(preview.didTruncate)",
                    "visibleText=\(preview.visibleText)"
                ]
            )
        }

        return pass(
            id: "markdown-preview",
            title: "Markdown Preview Renderer",
            summary: "bold / list / soft break / truncation 규칙이 future card preview seam으로 고정됐습니다.",
            details: preview.visibleLines
        )
    }

    private nonisolated static func snapshotFixtureSuite() -> SuiteResult {
        let fixtures = BWRCardBuddyVisualSnapshotFactory.fixtures()
        let requiredIDs: Set<String> = ["normal", "cursor", "hover", "drag", "inline-theme"]
        let actualIDs = Set(fixtures.map(\.id))

        guard actualIDs == requiredIDs else {
            return fail(
                id: "snapshot-fixtures",
                title: "Snapshot Fixtures",
                summary: "visual snapshot fixture 세트가 계획한 상태 조합과 다릅니다.",
                details: [
                    "expected=\(requiredIDs.sorted().joined(separator: ","))",
                    "actual=\(actualIDs.sorted().joined(separator: ","))"
                ]
            )
        }

        let themedFixture = fixtures.first(where: { $0.id == "inline-theme" })
        let cursorFixture = fixtures.first(where: { $0.id == "cursor" })
        let hoverFixture = fixtures.first(where: { $0.id == "hover" })
        let dragFixture = fixtures.first(where: { $0.id == "drag" })

        guard themedFixture?.document.boardTheme.boardBackgroundHex != nil,
              cursorFixture?.boardChromeState.slotCursor.slotCursorVisibility == .visible,
              hoverFixture?.boardChromeState.hoverPlaceholder != nil,
              dragFixture?.boardChromeState.dragOverlay.dragDestinationSlot != nil else {
            return fail(
                id: "snapshot-fixtures",
                title: "Snapshot Fixtures",
                summary: "snapshot host에 주입할 theme/cursor/hover/drag fixture가 완성되지 않았습니다.",
                details: [
                    "themeHex=\(String(describing: themedFixture?.document.boardTheme.boardBackgroundHex))",
                    "cursorVisible=\(String(describing: cursorFixture?.boardChromeState.slotCursor.slotCursorVisibility.rawValue))",
                    "hoverPresent=\(hoverFixture?.boardChromeState.hoverPlaceholder != nil)",
                    "dragPresent=\(dragFixture?.boardChromeState.dragOverlay.dragDestinationSlot != nil)"
                ]
            )
        }

        return pass(
            id: "snapshot-fixtures",
            title: "Snapshot Fixtures",
            summary: "visual snapshot host가 normal/cursor/hover/drag/inline-theme preflight fixture를 모두 갖습니다.",
            details: fixtures.map { "\($0.id)=\($0.title)" }
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
        lines.append("# BWR Card Buddy Phase 0 Report")
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
