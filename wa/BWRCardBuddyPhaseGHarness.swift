import Foundation

nonisolated enum BWRCardBuddyPhaseGHarness {
    nonisolated static let reportJSONURL = URL(fileURLWithPath: "/tmp/bwr_cardbuddy_phaseg_report.json")
    nonisolated static let reportMarkdownURL = URL(fileURLWithPath: "/tmp/bwr_cardbuddy_phaseg_report.md")

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
            groupPanelStyleSuite(),
            boardThemeRoundTripSuite(),
            boardSurfaceOverlayReadabilitySuite(),
            cardPaletteGuardrailSuite()
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

    private nonisolated static func groupPanelStyleSuite() -> SuiteResult {
        let normal = BWRCardBuddyBoardThemeGuardrail.groupPanelStyle(isSelected: false)
        let selected = BWRCardBuddyBoardThemeGuardrail.groupPanelStyle(isSelected: true)

        guard normal.cornerRadius == 28,
              normal.fillHex == "FFFFFF",
              normal.fillOpacity == 0.10,
              normal.strokeHex == "2C251F",
              normal.strokeOpacity == 0.10,
              normal.strokeWidth == 1.0,
              selected.cornerRadius == 28,
              selected.fillHex == BWRCardBuddyCardShell.selectionHex,
              selected.fillOpacity == 0.08,
              selected.strokeHex == BWRCardBuddyCardShell.selectionHex,
              selected.strokeOpacity == 0.42,
              selected.strokeWidth == 1.6 else {
            return fail(
                id: "group-panel-style",
                title: "Group Panel Style",
                summary: "group panel의 선택/비선택 style token이 Phase G 기준으로 잠기지 않았습니다.",
                details: [
                    "normal=\(normal)",
                    "selected=\(selected)"
                ]
            )
        }

        return pass(
            id: "group-panel-style",
            title: "Group Panel Style",
            summary: "group panel이 subtle paper panel과 selected accent panel 두 상태로 고정됩니다.",
            details: [
                "normal stroke=2C251F@0.10 width=1.0",
                "selected stroke=\(BWRCardBuddyCardShell.selectionHex)@0.42 width=1.6"
            ]
        )
    }

    private nonisolated static func boardThemeRoundTripSuite() -> SuiteResult {
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bwr-cardbuddy-phaseg-\(UUID().uuidString)")
            .appendingPathExtension("bwr")
        defer {
            try? FileManager.default.removeItem(at: packageURL)
        }

        do {
            var document = BWRCardBuddyVisualSnapshotFactory.fixtures()[0].document
            let swatch = BWRCardBuddyBoardThemeGuardrail.boardSwatches[1]
            document.boardTheme = BWRBoardThemeState(
                boardBackgroundHex: swatch.hex,
                boardAccentMode: swatch.accentMode
            )

            try BWRPackageStore.fullWrite(document: document, to: packageURL)
            let restored = try BWRPackageStore.read(from: packageURL)

            guard restored.boardTheme == document.boardTheme else {
                return fail(
                    id: "board-theme-roundtrip",
                    title: "Board Theme Round-Trip",
                    summary: "board surface theme가 .bwr package round-trip 뒤 유지되지 않았습니다.",
                    details: [
                        "expected=\(String(describing: document.boardTheme.boardBackgroundHex))/\(document.boardTheme.boardAccentMode.rawValue)",
                        "actual=\(String(describing: restored.boardTheme.boardBackgroundHex))/\(restored.boardTheme.boardAccentMode.rawValue)"
                    ]
                )
            }

            return pass(
                id: "board-theme-roundtrip",
                title: "Board Theme Round-Trip",
                summary: "board surface theme가 document state와 package manifest에 함께 저장됩니다.",
                details: ["package=\(packageURL.path)"]
            )
        } catch {
            return fail(
                id: "board-theme-roundtrip",
                title: "Board Theme Round-Trip",
                summary: "board theme round-trip 중 예외가 발생했습니다.",
                details: [error.localizedDescription]
            )
        }
    }

    private nonisolated static func boardSurfaceOverlayReadabilitySuite() -> SuiteResult {
        let unsafe = BWRCardBuddyBoardThemeGuardrail.boardSwatches.compactMap { swatch -> String? in
            BWRCardBuddyBoardThemeGuardrail.isBoardSurfaceReadable(hex: swatch.hex)
                ? nil
                : "\(swatch.id)=\(swatch.hex)"
        }

        guard unsafe.isEmpty else {
            return fail(
                id: "overlay-readability",
                title: "Overlay Readability",
                summary: "선택 가능한 board surface 중 overlay 대비를 깨뜨리는 swatch가 있습니다.",
                details: unsafe
            )
        }

        return pass(
            id: "overlay-readability",
            title: "Overlay Readability",
            summary: "선택 가능한 board surface 전체에서 selection / cursor / placeholder overlay가 읽힙니다.",
            details: BWRCardBuddyBoardThemeGuardrail.boardSwatches.map { "\($0.id)=\($0.hex)" }
        )
    }

    private nonisolated static func cardPaletteGuardrailSuite() -> SuiteResult {
        var mismatches: [String] = []

        for boardSwatch in BWRCardBuddyBoardThemeGuardrail.boardSwatches {
            for cardSwatch in BWRCardBuddyBoardThemeGuardrail.cardSwatches {
                let resolved = BWRCardBuddyBoardThemeGuardrail.resolvedCardFillHex(
                    cardHex: cardSwatch.hex,
                    boardHex: boardSwatch.hex
                )
                if !BWRCardBuddyBoardThemeGuardrail.isCardReadable(cardHex: resolved, on: boardSwatch.hex) {
                    mismatches.append(
                        "board=\(boardSwatch.id):\(boardSwatch.hex) card=\(cardSwatch.id):\(cardSwatch.hex) resolved=\(resolved)"
                    )
                }
            }
        }

        guard mismatches.isEmpty else {
            return fail(
                id: "card-palette-guardrail",
                title: "Card Palette Guardrail",
                summary: "board background와 card tint 조합 중 여전히 읽히지 않는 조합이 있습니다.",
                details: mismatches
            )
        }

        let sampleBoard = BWRCardBuddyBoardThemeGuardrail.boardSwatches[2]
        let sampleCard = BWRCardBuddyBoardThemeGuardrail.cardSwatches[2]
        let sampleResolved = BWRCardBuddyBoardThemeGuardrail.resolvedCardFillHex(
            cardHex: sampleCard.hex,
            boardHex: sampleBoard.hex
        )

        return pass(
            id: "card-palette-guardrail",
            title: "Card Palette Guardrail",
            summary: "모든 safe board surface에서 card tint가 paper 쪽으로 보정되어 카드가 계속 읽힙니다.",
            details: [
                "combinations=\(BWRCardBuddyBoardThemeGuardrail.boardSwatches.count * BWRCardBuddyBoardThemeGuardrail.cardSwatches.count)",
                "sample=\(sampleBoard.id):\(sampleBoard.hex) + \(sampleCard.id):\(sampleCard.hex) -> \(sampleResolved)"
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
        lines.append("# BWR Card Buddy Phase G Group And Board Theme Integration")
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
