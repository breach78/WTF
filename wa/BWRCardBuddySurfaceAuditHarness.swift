import Foundation

nonisolated enum BWRCardBuddySurfaceAuditHarness {
    nonisolated static let reportJSONURL = URL(fileURLWithPath: "/tmp/bwr_cardbuddy_phaseb_report.json")
    nonisolated static let reportMarkdownURL = URL(fileURLWithPath: "/tmp/bwr_cardbuddy_phaseb_report.md")

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
            cardShellSnapshotSuite(),
            selectionSnapshotSuite(),
            overlayDiffSuite(),
            currentVsTargetDiffSuite(),
            sharedCanvasGateSuite()
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

    private nonisolated static func cardShellSnapshotSuite() -> SuiteResult {
        let rows = BWRCardBuddySurfaceAuditTableFactory.shellMetrics
        guard rows.count == 5 else {
            return fail(
                id: "card-shell",
                title: "Card Shell Snapshot",
                summary: "카드 쉘 snapshot rows 수가 계획과 다릅니다.",
                details: ["rowCount=\(rows.count)"]
            )
        }

        return pass(
            id: "card-shell",
            title: "Card Shell Snapshot",
            summary: "radius / shadow / inner padding / text inset / line density가 snapshot 값으로 잠겼습니다.",
            details: rows.map { "\($0.label): \($0.currentValue) -> \($0.targetValue)" }
        )
    }

    private nonisolated static func selectionSnapshotSuite() -> SuiteResult {
        let rows = BWRCardBuddySurfaceAuditTableFactory.selectionMetrics
        let targetHex = BWRCardBuddySurfaceAuditLock.target.selectionColorHex
        guard rows.count == 3, targetHex == "6D96D7" else {
            return fail(
                id: "selection",
                title: "Selection Snapshot",
                summary: "selection snapshot lock가 기대 값과 다릅니다.",
                details: [
                    "rowCount=\(rows.count)",
                    "targetHex=\(targetHex)"
                ]
            )
        }

        return pass(
            id: "selection",
            title: "Selection Snapshot",
            summary: "selection outline thickness / outer spread / reference blue가 잠겼습니다.",
            details: rows.map { "\($0.label): \($0.currentValue) -> \($0.targetValue)" }
        )
    }

    private nonisolated static func overlayDiffSuite() -> SuiteResult {
        let rows = BWRCardBuddySurfaceAuditTableFactory.overlayRows
        let expectedIDs = ["keyboard-cursor", "mouse-hover", "drag-source", "drag-destination"]
        guard rows.map(\.id) == expectedIDs else {
            return fail(
                id: "overlay-diff",
                title: "Overlay Diff Table",
                summary: "overlay diff table row 순서가 잠긴 상태와 다릅니다.",
                details: [
                    "expected=\(expectedIDs.joined(separator: ","))",
                    "actual=\(rows.map(\.id).joined(separator: ","))"
                ]
            )
        }

        return pass(
            id: "overlay-diff",
            title: "Overlay Diff Table",
            summary: "keyboard cursor / hover / drag source / drag destination diff가 표로 잠겼습니다.",
            details: rows.map { "\($0.title): \($0.delta)" }
        )
    }

    private nonisolated static func currentVsTargetDiffSuite() -> SuiteResult {
        let rows = BWRCardBuddySurfaceAuditTableFactory.currentVsTargetRows
        guard rows.count == 4 else {
            return fail(
                id: "diff-table",
                title: "Current vs Target Diff Table",
                summary: "current vs target diff table row 수가 예상과 다릅니다.",
                details: ["rowCount=\(rows.count)"]
            )
        }

        return pass(
            id: "diff-table",
            title: "Current vs Target Diff Table",
            summary: "surface / selection / group / overlay separation diff가 잠겼습니다.",
            details: rows.map { "\($0.label): \($0.currentValue) => \($0.targetValue)" }
        )
    }

    private nonisolated static func sharedCanvasGateSuite() -> SuiteResult {
        let scenarios = BWRCardBuddySurfaceAuditScenario.allCases.map(\.id)
        let expected = ["normalCard", "selectedCard", "keyboardCursor", "mouseHover", "dragSource", "dragDestination", "groupFrame"]
        guard scenarios == expected else {
            return fail(
                id: "shared-canvas",
                title: "Shared Canvas Gate",
                summary: "카드와 상태를 나란히 비교하는 shared canvas scenario 구성이 잠기지 않았습니다.",
                details: [
                    "expected=\(expected.joined(separator: ","))",
                    "actual=\(scenarios.joined(separator: ","))"
                ]
            )
        }

        return pass(
            id: "shared-canvas",
            title: "Shared Canvas Gate",
            summary: "같은 테스트 캔버스에서 current/target을 시나리오별로 나란히 비교할 수 있습니다.",
            details: scenarios
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
        lines.append("# BWR Card Buddy Phase B Surface Audit")
        lines.append("")
        lines.append("- generatedAt: \(report.generatedAt)")
        lines.append("- suiteCount: \(report.suiteCount)")
        lines.append("- failureCount: \(report.failureCount)")
        lines.append("")
        lines.append("## Card Shell Snapshot")
        lines.append("")
        lines.append("| Metric | Current | Target |")
        lines.append("| --- | --- | --- |")
        for row in BWRCardBuddySurfaceAuditTableFactory.shellMetrics {
            lines.append("| \(row.label) | \(row.currentValue) | \(row.targetValue) |")
        }
        lines.append("")
        lines.append("## Selection Snapshot")
        lines.append("")
        lines.append("| Metric | Current | Target |")
        lines.append("| --- | --- | --- |")
        for row in BWRCardBuddySurfaceAuditTableFactory.selectionMetrics {
            lines.append("| \(row.label) | \(row.currentValue) | \(row.targetValue) |")
        }
        lines.append("")
        lines.append("## Overlay Diff Table")
        lines.append("")
        lines.append("| State | Current | Target | Delta |")
        lines.append("| --- | --- | --- | --- |")
        for row in BWRCardBuddySurfaceAuditTableFactory.overlayRows {
            lines.append("| \(row.title) | \(row.currentGrammar) | \(row.targetGrammar) | \(row.delta) |")
        }
        lines.append("")
        lines.append("## Current vs Target")
        lines.append("")
        lines.append("| Topic | Current | Target |")
        lines.append("| --- | --- | --- |")
        for row in BWRCardBuddySurfaceAuditTableFactory.currentVsTargetRows {
            lines.append("| \(row.label) | \(row.currentValue) | \(row.targetValue) |")
        }
        lines.append("")
        lines.append("## Harness Suites")
        lines.append("")
        for suite in report.suites {
            lines.append("- [\(suite.status.rawValue.uppercased())] \(suite.title): \(suite.summary)")
        }
        lines.append("")
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
