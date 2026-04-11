import Foundation

nonisolated enum BWRCardBuddyPhaseDHarness {
    nonisolated static let reportJSONURL = URL(fileURLWithPath: "/tmp/bwr_cardbuddy_phased_report.json")
    nonisolated static let reportMarkdownURL = URL(fileURLWithPath: "/tmp/bwr_cardbuddy_phased_report.md")

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
            surfaceLockSuite(),
            paperColorGrammarSuite(),
            markdownPreviewDensitySuite(),
            selectionGrammarSuite()
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

    private nonisolated static func surfaceLockSuite() -> SuiteResult {
        let surface = BWRCardBuddyCardShell.surface
        guard surface.cardCornerRadius == 14,
              surface.cardShadowBlur == 6,
              surface.cardShadowYOffset == 3,
              surface.cardInnerPadding == 14,
              surface.cardTextInset == 14,
              surface.visibleLineDensity == 5 else {
            return fail(
                id: "surface-lock",
                title: "Surface Lock",
                summary: "Phase D card shell target surface가 계획 값과 다릅니다.",
                details: [
                    "radius=\(surface.cardCornerRadius)",
                    "shadow=\(surface.cardShadowBlur)/\(surface.cardShadowYOffset)",
                    "padding=\(surface.cardInnerPadding)/\(surface.cardTextInset)",
                    "lineDensity=\(surface.visibleLineDensity)"
                ]
            )
        }

        return pass(
            id: "surface-lock",
            title: "Surface Lock",
            summary: "card radius / shadow / padding / preview density가 target surface로 잠겼습니다.",
            details: [
                "radius=14",
                "shadow=6 blur / 3y",
                "padding=14/14",
                "lineDensity=5"
            ]
        )
    }

    private nonisolated static func paperColorGrammarSuite() -> SuiteResult {
        let cases: [(String?, String)] = [
            (nil, "FFFFFF"),
            ("F8FAFC", "FFFFFF"),
            ("E0F2FE", "F0F9FF"),
            ("FEF3C7", "FFF9E3")
        ]

        let mismatches = cases.compactMap { input, expected -> String? in
            let actual = BWRCardBuddyCardShell.resolvedFillHex(for: input)
            return actual == expected ? nil : "input=\(input ?? "nil") expected=\(expected) actual=\(actual)"
        }

        guard mismatches.isEmpty else {
            return fail(
                id: "paper-color",
                title: "Paper Color Grammar",
                summary: "기본 흰색 + 선택 색상 옵션 문법이 기대 값과 다릅니다.",
                details: mismatches
            )
        }

        return pass(
            id: "paper-color",
            title: "Paper Color Grammar",
            summary: "기본 paper white와 soft tint swatch가 고정된 hex로 정규화됩니다.",
            details: cases.map { input, expected in
                "input=\(input ?? "nil") -> \(expected)"
            }
        )
    }

    private nonisolated static func markdownPreviewDensitySuite() -> SuiteResult {
        let markdown = """
        **Intro**
        - First beat
        Second line
        Third line
        Fourth line
        Fifth line
        Sixth line
        """

        let preview = BWRCardBuddyCardShell.preview(for: markdown)
        guard preview.visibleLines.count == 5,
              preview.visibleLines.first == "Intro",
              preview.visibleLines.dropFirst().first == "• First beat",
              preview.didTruncate,
              preview.containsStrongEmphasis,
              preview.containsListItems else {
            return fail(
                id: "markdown-preview",
                title: "Markdown Preview Density",
                summary: "5-line markdown preview renderer contract가 깨졌습니다.",
                details: [
                    "lineCount=\(preview.visibleLines.count)",
                    "first=\(preview.visibleLines.first ?? "<none>")",
                    "second=\(preview.visibleLines.dropFirst().first ?? "<none>")",
                    "didTruncate=\(preview.didTruncate)",
                    "containsStrong=\(preview.containsStrongEmphasis)",
                    "containsList=\(preview.containsListItems)"
                ]
            )
        }

        return pass(
            id: "markdown-preview",
            title: "Markdown Preview Density",
            summary: "markdown preview가 5줄로 자르고, emphasis/list normalization을 유지합니다.",
            details: preview.visibleLines
        )
    }

    private nonisolated static func selectionGrammarSuite() -> SuiteResult {
        let surface = BWRCardBuddyCardShell.surface
        guard BWRCardBuddyCardShell.selectionHex == "6D96D7",
              surface.selectionOutlineWidth == 4,
              surface.selectionOuterSpread == 8 else {
            return fail(
                id: "selection-grammar",
                title: "Selection Grammar",
                summary: "selected card halo grammar가 target 값과 다릅니다.",
                details: [
                    "hex=\(BWRCardBuddyCardShell.selectionHex)",
                    "width=\(surface.selectionOutlineWidth)",
                    "spread=\(surface.selectionOuterSpread)"
                ]
            )
        }

        return pass(
            id: "selection-grammar",
            title: "Selection Grammar",
            summary: "selected card가 blue outer halo grammar를 사용합니다.",
            details: [
                "hex=6D96D7",
                "width=4",
                "spread=8"
            ]
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
        lines.append("# BWR Card Buddy Phase D Report")
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
