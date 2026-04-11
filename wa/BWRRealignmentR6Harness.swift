import Foundation
import CoreGraphics

@MainActor
enum BWRRealignmentR6Harness {
    nonisolated static let reportJSONURL = URL(fileURLWithPath: "/tmp/bwr_r6_report.json")
    nonisolated static let reportMarkdownURL = URL(fileURLWithPath: "/tmp/bwr_r6_report.md")

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

    private struct HarnessReport: Codable {
        let generatedAt: String
        let suiteCount: Int
        let failureCount: Int
        let suites: [HarnessSuite]
    }

    private struct HarnessSuite: Codable {
        let id: String
        let title: String
        let status: Status
        let summary: String
        let details: [String]
    }

    private struct HarnessRunResult {
        let name: String
        let report: HarnessReport?
        let launchSucceeded: Bool
    }

    private struct PackageSnapshot: Equatable {
        struct File: Equatable {
            let relativePath: String
            let data: Data
        }

        let files: [File]
    }

    @discardableResult
    static func runAll() -> Bool {
        let milestone2 = runHarness(
            name: "M2",
            reportURL: BWRMilestone2Harness.reportJSONURL,
            run: BWRMilestone2Harness.runAll
        )
        let milestone5 = runHarness(
            name: "M5",
            reportURL: BWRMilestone5Harness.reportJSONURL,
            run: BWRMilestone5Harness.runAll
        )
        let realignment3 = runHarness(
            name: "R3",
            reportURL: BWRRealignmentR3Harness.reportJSONURL,
            run: BWRRealignmentR3Harness.runAll
        )
        let realignment4 = runHarness(
            name: "R4",
            reportURL: BWRRealignmentR4Harness.reportJSONURL,
            run: BWRRealignmentR4Harness.runAll
        )
        let realignment5 = runHarness(
            name: "R5",
            reportURL: BWRRealignmentR5Harness.reportJSONURL,
            run: BWRRealignmentR5Harness.runAll
        )

        let suites = [
            slotOrderingSuite(realignment5),
            attachDetachSuite(realignment4),
            splitPlacementSuite(milestone2),
            cloneDetachDeleteSuite(milestone2),
            loadRepairCorruptionSuite(milestone2),
            macAcceptanceSmokeSuite(milestone5),
            adaptiveLayoutSmokeSuite(milestone5),
            deterministicPlaceholderSuite(realignment3, realignment4),
            keyboardTraversalSnapshotSuite(),
            performanceAndDirtySuite()
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

    private static func slotOrderingSuite(_ report: HarnessRunResult) -> SuiteResult {
        aggregatedSuite(
            id: "slot-order",
            title: "Slot Ordering Suite",
            summary: "focus/export/search/live consumer가 모두 같은 slot-order helper를 따릅니다.",
            harness: report,
            requiredSuiteIDs: ["focus-export", "live-order", "search"]
        )
    }

    private static func attachDetachSuite(_ report: HarnessRunResult) -> SuiteResult {
        aggregatedSuite(
            id: "attach-detach",
            title: "Attach Detach Suite",
            summary: "attach와 detach가 placeholder 기반 drag 해석 뒤 즉시 slot reflow로 수렴합니다.",
            harness: report,
            requiredSuiteIDs: ["attach-reflow", "detach-parking", "group-block"]
        )
    }

    private static func splitPlacementSuite(_ report: HarnessRunResult) -> SuiteResult {
        aggregatedSuite(
            id: "split-placement",
            title: "Split Placement Suite",
            summary: "split로 생긴 새 카드는 원본의 다음 slot에 들어가고 host를 유지합니다.",
            harness: report,
            requiredSuiteIDs: ["split"]
        )
    }

    private static func cloneDetachDeleteSuite(_ report: HarnessRunResult) -> SuiteResult {
        aggregatedSuite(
            id: "clone-delete",
            title: "Clone Detach Delete Suite",
            summary: "group 삭제 시 clone-host 카드는 hard delete되고 survivor는 clone 해제로 정상화됩니다.",
            harness: report,
            requiredSuiteIDs: ["clone"]
        )
    }

    private static func loadRepairCorruptionSuite(_ report: HarnessRunResult) -> SuiteResult {
        aggregatedSuite(
            id: "load-repair",
            title: "Load Repair Corruption Suite",
            summary: "strict load는 corruption을 막고 runtime repair는 single-host invariant를 복원합니다.",
            harness: report,
            requiredSuiteIDs: ["normalize-undo"]
        )
    }

    private static func macAcceptanceSmokeSuite(_ report: HarnessRunResult) -> SuiteResult {
        aggregatedSuite(
            id: "mac-acceptance",
            title: "Mac Acceptance Smoke",
            summary: "Mac host에서 키보드, drag 해석, 저장, export, undo 흐름이 막히지 않습니다.",
            harness: report,
            requiredSuiteIDs: ["mac-acceptance"]
        )
    }

    private static func adaptiveLayoutSmokeSuite(_ report: HarnessRunResult) -> SuiteResult {
        aggregatedSuite(
            id: "adaptive-layout",
            title: "Portrait Landscape Split Layout Smoke",
            summary: "portrait, landscape, split, Mac host에서 workspace/focus layout 전환이 계획과 일치합니다.",
            harness: report,
            requiredSuiteIDs: ["layout-matrix"]
        )
    }

    private static func deterministicPlaceholderSuite(
        _ projectionReport: HarnessRunResult,
        _ interactionReport: HarnessRunResult
    ) -> SuiteResult {
        let projectionSuite = suite(id: "determinism", in: projectionReport.report)
        let placeholderSuite = suite(id: "strip-cleanup", in: interactionReport.report)

        guard projectionReport.launchSucceeded,
              interactionReport.launchSucceeded,
              let projectionSuite,
              let placeholderSuite else {
            return fail(
                id: "placeholder-determinism",
                title: "Deterministic Placeholder Suite",
                summary: "deterministic placeholder acceptance에 필요한 하위 하네스 리포트를 읽지 못했습니다.",
                details: [
                    "R3 launch=\(projectionReport.launchSucceeded)",
                    "R4 launch=\(interactionReport.launchSucceeded)"
                ]
            )
        }

        guard projectionSuite.status == .pass,
              placeholderSuite.status == .pass else {
            return fail(
                id: "placeholder-determinism",
                title: "Deterministic Placeholder Suite",
                summary: "projection 또는 placeholder target이 반복 입력에서 결정적으로 유지되지 않았습니다.",
                details: [
                    "R3 \(projectionSuite.id)=\(projectionSuite.status.rawValue)",
                    "R4 \(placeholderSuite.id)=\(placeholderSuite.status.rawValue)"
                ] + projectionSuite.details + placeholderSuite.details
            )
        }

        return pass(
            id: "placeholder-determinism",
            title: "Deterministic Placeholder Suite",
            summary: "같은 문서와 같은 hover 입력은 projection snapshot과 placeholder target을 반복해도 같은 결과를 냅니다.",
            details: [
                "R3=\(projectionSuite.id)",
                "R4=\(placeholderSuite.id)"
            ]
        )
    }

    private static func keyboardTraversalSnapshotSuite() -> SuiteResult {
        let document = keyboardTraversalFixture()

        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000111")!
        let fourth = UUID(uuidString: "00000000-0000-0000-0000-000000000114")!
        let sixth = UUID(uuidString: "00000000-0000-0000-0000-000000000116")!
        let parked = UUID(uuidString: "00000000-0000-0000-0000-000000000117")!

        let snapshot = [
            "111:R=\(shortID(BWRBoardOrderResolver.nextCardID(document: document, from: first, direction: .right)))",
            "111:D=\(shortID(BWRBoardOrderResolver.nextCardID(document: document, from: first, direction: .down)))",
            "114:D=\(shortID(BWRBoardOrderResolver.nextCardID(document: document, from: fourth, direction: .down)))",
            "116:L=\(shortID(BWRBoardOrderResolver.nextCardID(document: document, from: sixth, direction: .left)))",
            "116:U=\(shortID(BWRBoardOrderResolver.nextCardID(document: document, from: sixth, direction: .up)))",
            "117:U=\(shortID(BWRBoardOrderResolver.nextCardID(document: document, from: parked, direction: .up)))"
        ].joined(separator: " | ")

        let expected = "111:R=112 | 111:D=115 | 114:D=116 | 116:L=115 | 116:U=112 | 117:U=115"
        guard snapshot == expected else {
            return fail(
                id: "keyboard-snapshot",
                title: "Keyboard Traversal Snapshot",
                summary: "wrapped group/strip fixture의 arrow traversal snapshot이 바뀌었습니다.",
                details: [
                    "expected=\(expected)",
                    "actual=\(snapshot)"
                ]
            )
        }

        return pass(
            id: "keyboard-snapshot",
            title: "Keyboard Traversal Snapshot",
            summary: "wrapped group/strip fixture의 화살표 이동 결과가 snapshot으로 고정되었습니다.",
            details: ["snapshot=\(snapshot)"]
        )
    }

    private static func performanceAndDirtySuite() -> SuiteResult {
        let performanceDocument = performanceFixture()
        let viewport = BWRViewportState(
            zoomScale: 1,
            scrollOrigin: BWRPoint(x: 0, y: 0),
            viewportSize: BWRSize(width: 1720, height: 1200)
        )
        let draggingCardID = performanceDocument.groups.first?.memberCardIDs.first

        var warmupTarget: CGPoint?
        for _ in 0..<5 {
            let projection = BWRSlotBoardProjection.project(document: performanceDocument)
            if warmupTarget == nil {
                warmupTarget = pointerForPerformanceTarget(projection: projection)
            }
            guard let draggingCardID,
                  let pointer = warmupTarget else {
                return fail(
                    id: "performance-dirty",
                    title: "Performance And Dirty",
                    summary: "성능 측정에 필요한 projection target을 만들지 못했습니다.",
                    details: []
                )
            }
            _ = BWRSlotBoardInteraction.resolveCardDropTarget(
                document: performanceDocument,
                projection: projection,
                draggingCardIDs: [draggingCardID],
                leadCardID: draggingCardID,
                pointer: pointer,
                viewportState: viewport
            )
        }

        var samples: [Double] = []
        for _ in 0..<25 {
            guard let draggingCardID else {
                return fail(
                    id: "performance-dirty",
                    title: "Performance And Dirty",
                    summary: "성능 fixture의 drag anchor를 찾지 못했습니다.",
                    details: []
                )
            }

            let start = CFAbsoluteTimeGetCurrent()
            let projection = BWRSlotBoardProjection.project(document: performanceDocument)
            guard let pointer = pointerForPerformanceTarget(projection: projection) else {
                return fail(
                    id: "performance-dirty",
                    title: "Performance And Dirty",
                    summary: "성능 측정 중 placeholder pointer를 만들지 못했습니다.",
                    details: []
                )
            }
            _ = BWRSlotBoardInteraction.resolveCardDropTarget(
                document: performanceDocument,
                projection: projection,
                draggingCardIDs: [draggingCardID],
                leadCardID: draggingCardID,
                pointer: pointer,
                viewportState: viewport
            )
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            samples.append(elapsed)
        }

        let median = percentile(samples, percentile: 0.5)
        let p95 = percentile(samples, percentile: 0.95)

        let packageURL = temporaryPackageURL(prefix: "bwr-r6-dirty")
        defer {
            try? FileManager.default.removeItem(at: packageURL)
        }

        let reference = BWRReferenceDocument(document: performanceDocument)
        reference.attach(fileURL: packageURL)
        reference.forceFullSaveNow()

        guard let beforePackage = stablePackageSnapshot(packageURL, timeout: 2.0) else {
            return fail(
                id: "performance-dirty",
                title: "Performance And Dirty",
                summary: "dirty 검증용 .bwr 패키지의 초기 스냅샷을 안정화하지 못했습니다.",
                details: [
                    "package=\(packageURL.path)",
                    "autosave=\(reference.autosaveStatus)"
                ]
            )
        }

        let beforeDocument = reference.document
        let sceneSessionID = "r6-dirty-\(UUID().uuidString)"
        BWRViewportStateStore.save(
            BWRViewportState(
                zoomScale: 1.23,
                scrollOrigin: BWRPoint(x: 420, y: 160),
                viewportSize: BWRSize(width: 1110, height: 834)
            ),
            documentURL: packageURL,
            sceneSessionID: sceneSessionID
        )

        let dirtyProjection = BWRSlotBoardProjection.project(document: reference.document)
        if let draggingCardID,
           let pointer = pointerForPerformanceTarget(projection: dirtyProjection) {
            for _ in 0..<10 {
                _ = BWRSlotBoardInteraction.resolveCardDropTarget(
                    document: reference.document,
                    projection: dirtyProjection,
                    draggingCardIDs: [draggingCardID],
                    leadCardID: draggingCardID,
                    pointer: pointer,
                    viewportState: viewport
                )
            }
        }
        reference.saveNow()

        guard let afterPackage = stablePackageSnapshot(packageURL, timeout: 0.5) else {
            return fail(
                id: "performance-dirty",
                title: "Performance And Dirty",
                summary: "dirty 검증 후 패키지 스냅샷을 안정화하지 못했습니다.",
                details: [
                    "package=\(packageURL.path)",
                    "autosave=\(reference.autosaveStatus)"
                ]
            )
        }

        guard median <= 16.0,
              reference.document == beforeDocument,
              beforePackage == afterPackage else {
            return fail(
                id: "performance-dirty",
                title: "Performance And Dirty",
                summary: "200-card projection 성능 또는 viewport/hover dirty 보장이 acceptance bar를 넘지 못했습니다.",
                details: [
                    String(format: "medianMs=%.3f", median),
                    String(format: "p95Ms=%.3f", p95),
                    "documentChanged=\(reference.document != beforeDocument)",
                    "packageChanged=\(beforePackage != afterPackage)",
                    "autosave=\(reference.autosaveStatus)"
                ]
            )
        }

        return pass(
            id: "performance-dirty",
            title: "Performance And Dirty",
            summary: "200-card fixture의 projection + target resolution median이 기준 이내이고 viewport/hover 변화는 canonical data를 dirty시키지 않습니다.",
            details: [
                String(format: "medianMs=%.3f", median),
                String(format: "p95Ms=%.3f", p95),
                "cardCount=\(performanceDocument.cards.count)"
            ]
        )
    }

    private static func aggregatedSuite(
        id: String,
        title: String,
        summary: String,
        harness: HarnessRunResult,
        requiredSuiteIDs: [String]
    ) -> SuiteResult {
        guard harness.launchSucceeded, let report = harness.report else {
            return fail(
                id: id,
                title: title,
                summary: "\(harness.name) 하네스를 실행했지만 리포트를 읽지 못했습니다.",
                details: ["launch=\(harness.launchSucceeded)"]
            )
        }

        let resolvedSuites = requiredSuiteIDs.compactMap { suite(id: $0, in: report) }
        guard resolvedSuites.count == requiredSuiteIDs.count else {
            let missing = requiredSuiteIDs.filter { target in
                !resolvedSuites.contains(where: { $0.id == target })
            }
            return fail(
                id: id,
                title: title,
                summary: "\(harness.name) 리포트에서 필요한 acceptance suite를 찾지 못했습니다.",
                details: ["missing=\(missing.joined(separator: ","))"]
            )
        }

        let failures = resolvedSuites.filter { $0.status == .fail }
        guard failures.isEmpty else {
            return fail(
                id: id,
                title: title,
                summary: summary,
                details: failures.flatMap { suite in
                    ["\(suite.id)=fail"] + suite.details
                }
            )
        }

        return pass(
            id: id,
            title: title,
            summary: summary,
            details: resolvedSuites.map { "\($0.id)=\($0.status.rawValue)" }
        )
    }

    private static func runHarness(
        name: String,
        reportURL: URL,
        run: @MainActor () -> Bool
    ) -> HarnessRunResult {
        let launchSucceeded = run()
        return HarnessRunResult(
            name: name,
            report: loadHarnessReport(at: reportURL),
            launchSucceeded: launchSucceeded
        )
    }

    private static func loadHarnessReport(at url: URL) -> HarnessReport? {
        let decoder = JSONDecoder()
        for candidate in reportURLCandidates(for: url) {
            guard let data = try? Data(contentsOf: candidate),
                  let report = try? decoder.decode(HarnessReport.self, from: data) else {
                continue
            }
            return report
        }
        return nil
    }

    private static func reportURLCandidates(for url: URL) -> [URL] {
        if url.path.hasPrefix("/tmp/") {
            let privateURL = URL(fileURLWithPath: "/private" + url.path)
            return [url, privateURL]
        }
        return [url]
    }

    private static func suite(id: String, in report: HarnessReport?) -> HarnessSuite? {
        report?.suites.first(where: { $0.id == id })
    }

    private static func pointerForPerformanceTarget(projection: BWRSlotBoardProjectionSnapshot) -> CGPoint? {
        if let group = projection.groupFrames.dropFirst().first,
           let rect = projection.placeholderRect(for: .group(group.group.id), insertionIndex: 1) {
            return CGPoint(x: rect.midX, y: rect.midY)
        }
        if let strip = projection.stripFrames.first,
           let rect = projection.placeholderRect(for: .strip(strip.strip.id), insertionIndex: 0) {
            return CGPoint(x: rect.midX, y: rect.midY)
        }
        return nil
    }

    private static func percentile(_ samples: [Double], percentile: Double) -> Double {
        guard !samples.isEmpty else { return .infinity }
        let sorted = samples.sorted()
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * percentile).rounded())))
        return sorted[index]
    }

    private static func packageSnapshot(_ packageURL: URL) -> PackageSnapshot? {
        guard FileManager.default.fileExists(atPath: packageURL.path),
              let enumerator = FileManager.default.enumerator(
                at: packageURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return nil
        }

        let files = enumerator.compactMap { item -> PackageSnapshot.File? in
            guard let fileURL = item as? URL,
                  let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true,
                  let data = try? Data(contentsOf: fileURL) else {
                return nil
            }
            let relativePath = fileURL.path.replacingOccurrences(of: packageURL.path + "/", with: "")
            return PackageSnapshot.File(relativePath: relativePath, data: data)
        }
        .sorted { lhs, rhs in
            lhs.relativePath < rhs.relativePath
        }

        return PackageSnapshot(files: files)
    }

    private static func stablePackageSnapshot(_ packageURL: URL, timeout: TimeInterval) -> PackageSnapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        var previous: PackageSnapshot?
        var stableCount = 0

        while Date() < deadline {
            let current = packageSnapshot(packageURL)
            if let previous, current == previous {
                stableCount += 1
                if stableCount >= 2 {
                    return current
                }
            } else {
                stableCount = 0
            }
            previous = current
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        return previous
    }

    private static func keyboardTraversalFixture() -> BWRDocument {
        let now = Date(timeIntervalSince1970: 140)
        let groupID = UUID(uuidString: "00000000-0000-0000-0000-000000000951")!
        let stripID = UUID(uuidString: "00000000-0000-0000-0000-000000000952")!

        let cards = [
            makeCard(id: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!, stableSortKey: 1, placement: .attached(hostGroupID: groupID, slotIndex: 0), timestamp: now),
            makeCard(id: UUID(uuidString: "00000000-0000-0000-0000-000000000112")!, stableSortKey: 2, placement: .attached(hostGroupID: groupID, slotIndex: 1), timestamp: now.addingTimeInterval(1)),
            makeCard(id: UUID(uuidString: "00000000-0000-0000-0000-000000000113")!, stableSortKey: 3, placement: .attached(hostGroupID: groupID, slotIndex: 2), timestamp: now.addingTimeInterval(2)),
            makeCard(id: UUID(uuidString: "00000000-0000-0000-0000-000000000114")!, stableSortKey: 4, placement: .attached(hostGroupID: groupID, slotIndex: 3), timestamp: now.addingTimeInterval(3)),
            makeCard(id: UUID(uuidString: "00000000-0000-0000-0000-000000000115")!, stableSortKey: 5, placement: .attached(hostGroupID: groupID, slotIndex: 4), timestamp: now.addingTimeInterval(4)),
            makeCard(id: UUID(uuidString: "00000000-0000-0000-0000-000000000116")!, stableSortKey: 6, placement: .attached(hostGroupID: groupID, slotIndex: 5), timestamp: now.addingTimeInterval(5)),
            makeCard(id: UUID(uuidString: "00000000-0000-0000-0000-000000000117")!, stableSortKey: 7, placement: .parked(stripID: stripID, slotIndex: 0), timestamp: now.addingTimeInterval(6))
        ]

        return BWRDocument(
            schemaVersion: 2,
            createdAt: now,
            updatedAt: now,
            nextStableSortKey: 8,
            cards: cards,
            groups: [
                BWRGroup(
                    id: groupID,
                    name: "Traversal",
                    originSlot: BWRSlotCoordinate(column: 0, row: 0),
                    memberCardIDs: cards.prefix(6).map(\.id),
                    createdAt: now,
                    updatedAt: now
                )
            ],
            parkingStrips: [
                BWRParkingStrip(
                    id: stripID,
                    row: 3,
                    anchorColumn: 0,
                    cardIDs: [cards[6].id]
                )
            ]
        )
    }

    private static func performanceFixture() -> BWRDocument {
        let now = Date(timeIntervalSince1970: 160)
        var cards: [BWRCard] = []
        var groups: [BWRGroup] = []
        var nextStableSortKey: Int64 = 1
        var timestampOffset: TimeInterval = 0

        for groupIndex in 0..<25 {
            let groupID = UUID()
            var memberIDs: [UUID] = []
            for slotIndex in 0..<8 {
                let cardID = UUID()
                memberIDs.append(cardID)
                cards.append(
                    makeCard(
                        id: cardID,
                        stableSortKey: nextStableSortKey,
                        placement: .attached(hostGroupID: groupID, slotIndex: slotIndex),
                        timestamp: now.addingTimeInterval(timestampOffset)
                    )
                )
                nextStableSortKey += 1
                timestampOffset += 1
            }

            groups.append(
                BWRGroup(
                    id: groupID,
                    name: "Group \(groupIndex + 1)",
                    originSlot: BWRSlotCoordinate(column: (groupIndex % 5) * 6, row: (groupIndex / 5) * 4),
                    memberCardIDs: memberIDs,
                    createdAt: now,
                    updatedAt: now.addingTimeInterval(timestampOffset)
                )
            )
        }

        return BWRDocument(
            schemaVersion: 2,
            createdAt: now,
            updatedAt: now.addingTimeInterval(timestampOffset),
            nextStableSortKey: nextStableSortKey,
            cards: cards,
            groups: groups
        )
    }

    private static func makeCard(
        id: UUID,
        stableSortKey: Int64,
        placement: BWRCardPlacement,
        timestamp: Date
    ) -> BWRCard {
        let layers = BWRCard.defaultLayers(
            bodyMarkdown: "Body \(stableSortKey)",
            treatmentMarkdown: "Treatment \(stableSortKey)",
            scenarioMarkdown: "Scenario \(stableSortKey)"
        )
        return BWRCard(
            id: id,
            stableSortKey: stableSortKey,
            currentLayerID: layers[0].id,
            placement: placement,
            layout: BWRPoint(x: 0, y: 0),
            createdAt: timestamp,
            updatedAt: timestamp,
            layers: layers
        )
    }

    private static func shortID(_ id: UUID?) -> String {
        guard let id else { return "nil" }
        return String(id.uuidString.suffix(3))
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
        # BWR Realignment R6 Harness

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
}
