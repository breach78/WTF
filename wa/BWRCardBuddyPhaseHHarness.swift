import Foundation

nonisolated enum BWRCardBuddyPhaseHHarness {
    nonisolated static let reportJSONURL = URL(fileURLWithPath: "/tmp/bwr_cardbuddy_phaseh_report.json")
    nonisolated static let reportMarkdownURL = URL(fileURLWithPath: "/tmp/bwr_cardbuddy_phaseh_report.md")

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
            backdropSoftnessSuite(),
            surfaceHierarchySuite(),
            toolbarChromeSuite()
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

    private nonisolated static func backdropSoftnessSuite() -> SuiteResult {
        let backdrop = BWRCardBuddyShellChrome.backdrop
        let contrast = contrastRatio(foregroundHex: backdrop.topHex, backgroundHex: backdrop.bottomHex)

        guard contrast <= 1.12,
              (0.32...0.48).contains(backdrop.spotlightOpacity) else {
            return fail(
                id: "workspace-backdrop",
                title: "Workspace Backdrop",
                summary: "workspace backdrop가 너무 세거나 spotlight가 과도해 shell softening 기준을 벗어났습니다.",
                details: [
                    "top=\(backdrop.topHex)",
                    "bottom=\(backdrop.bottomHex)",
                    String(format: "contrast=%.3f", contrast),
                    String(format: "spotlightOpacity=%.2f", backdrop.spotlightOpacity)
                ]
            )
        }

        return pass(
            id: "workspace-backdrop",
            title: "Workspace Backdrop",
            summary: "workspace backdrop가 낮은 대비의 desk tone과 중앙 spotlight로 잠겼습니다.",
            details: [
                String(format: "contrast=%.3f", contrast),
                String(format: "spotlightOpacity=%.2f", backdrop.spotlightOpacity)
            ]
        )
    }

    private nonisolated static func surfaceHierarchySuite() -> SuiteResult {
        let column = BWRCardBuddyShellChrome.panelStyle(for: .column)
        let section = BWRCardBuddyShellChrome.panelStyle(for: .section)
        let stage = BWRCardBuddyShellChrome.panelStyle(for: .stage)
        let band = BWRCardBuddyShellChrome.panelStyle(for: .band)

        guard column.fillOpacity < section.fillOpacity,
              section.fillOpacity < stage.fillOpacity,
              band.fillOpacity <= section.fillOpacity,
              column.strokeOpacity <= 0.05,
              section.strokeOpacity <= 0.06,
              stage.strokeOpacity <= 0.07,
              stage.shadowOpacity <= 0.04 else {
            return fail(
                id: "surface-hierarchy",
                title: "Surface Hierarchy",
                summary: "column / section / stage의 시각 계층이 board-first 기준으로 잠기지 않았습니다.",
                details: [
                    "column=\(column)",
                    "section=\(section)",
                    "stage=\(stage)",
                    "band=\(band)"
                ]
            )
        }

        return pass(
            id: "surface-hierarchy",
            title: "Surface Hierarchy",
            summary: "sidebar column보다 section panel이 살짝 강하고, board stage가 그 위에서만 조금 더 읽히도록 잠겼습니다.",
            details: [
                String(format: "columnFill=%.2f", column.fillOpacity),
                String(format: "sectionFill=%.2f", section.fillOpacity),
                String(format: "stageFill=%.2f", stage.fillOpacity),
                String(format: "stageShadow=%.3f", stage.shadowOpacity)
            ]
        )
    }

    private nonisolated static func toolbarChromeSuite() -> SuiteResult {
        let primary = BWRCardBuddyShellChrome.buttonStyle(for: .toolbarPrimary)
        let accessory = BWRCardBuddyShellChrome.buttonStyle(for: .toolbarAccessory)
        let band = BWRCardBuddyShellChrome.panelStyle(for: .band)

        guard accessory.fillOpacity < primary.fillOpacity,
              primary.fillOpacity <= band.fillOpacity + 0.02,
              accessory.strokeOpacity <= primary.strokeOpacity,
              primary.pressedFillOpacity <= 0.24,
              accessory.pressedFillOpacity <= 0.18 else {
            return fail(
                id: "toolbar-chrome",
                title: "Toolbar Chrome",
                summary: "header/toolbar button chrome가 카드보다 먼저 읽힐 정도로 강해졌습니다.",
                details: [
                    "primary=\(primary)",
                    "accessory=\(accessory)",
                    "band=\(band)"
                ]
            )
        }

        return pass(
            id: "toolbar-chrome",
            title: "Toolbar Chrome",
            summary: "header/toolbar actions가 낮은 opacity button chrome으로 잠겨 shell이 card-first 인상을 방해하지 않습니다.",
            details: [
                String(format: "primaryFill=%.2f", primary.fillOpacity),
                String(format: "accessoryFill=%.2f", accessory.fillOpacity),
                String(format: "primaryPressed=%.2f", primary.pressedFillOpacity)
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
        lines.append("# BWR Card Buddy Phase H Shell Softening")
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

    private nonisolated static func contrastRatio(foregroundHex: String, backgroundHex: String) -> Double {
        guard let foreground = rgbComponents(hex: foregroundHex),
              let background = rgbComponents(hex: backgroundHex) else {
            return .infinity
        }

        let lhs = relativeLuminance(foreground)
        let rhs = relativeLuminance(background)
        let lighter = max(lhs, rhs)
        let darker = min(lhs, rhs)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private nonisolated static func rgbComponents(hex: String) -> (r: Double, g: Double, b: Double)? {
        guard let value = Int(hex, radix: 16) else { return nil }
        return (
            r: Double((value >> 16) & 0xFF) / 255.0,
            g: Double((value >> 8) & 0xFF) / 255.0,
            b: Double(value & 0xFF) / 255.0
        )
    }

    private nonisolated static func relativeLuminance(_ color: (r: Double, g: Double, b: Double)) -> Double {
        func channel(_ value: Double) -> Double {
            if value <= 0.03928 {
                return value / 12.92
            }
            return pow((value + 0.055) / 1.055, 2.4)
        }

        let red = channel(color.r)
        let green = channel(color.g)
        let blue = channel(color.b)
        return (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
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
