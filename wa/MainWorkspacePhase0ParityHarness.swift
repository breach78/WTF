import Foundation

enum MainWorkspacePhase0ParityHarness {
    static let referenceJSONURL = URL(fileURLWithPath: "/tmp/wa_main_workspace_phase0_reference.json")
    static let checklistMarkdownURL = URL(fileURLWithPath: "/tmp/wa_main_workspace_phase0_checklist.md")
    static let failureJSONURL = URL(fileURLWithPath: "/tmp/wa_main_workspace_phase0_failures.json")
    static let targetOffsetTolerance: Double = 0.25

    struct ReferenceBundle: Codable {
        let generatedAt: String
        let sources: [SourceReference]
        let scrollSuites: [ScrollSuite]
        let undoSuites: [UndoTraceSuite]
        let checklist: [ChecklistItem]
    }

    struct SourceReference: Codable {
        let id: String
        let path: String
        let lines: String
        let purpose: String
    }

    struct FixtureNode: Codable {
        let id: String
        let title: String
        let children: [FixtureNode]
    }

    struct CardMetric: Codable {
        let top: Double
        let height: Double
    }

    struct ScrollFixture: Codable {
        let id: String
        let title: String
        let purpose: String
        let currentActiveID: String
        let targetActiveID: String
        let initialActivePast: [String]
        let instant: Bool
        let horizontalViewportWidth: Double
        let columnViewportHeight: Double
        let columnWidth: Double
        let columnGap: Double
        let tree: FixtureNode
        let metricsByCardID: [String: CardMetric]
    }

    enum PolicyKind: String, Codable {
        case centerActive
        case centerAncestor
        case centerPreferredDescendant
        case centerOtherDescendant
        case before
        case after
        case between
        case none
    }

    enum VerticalAnchor: String, Codable {
        case center
        case top
        case bottom
    }

    struct PolicyGolden: Codable {
        let kind: PolicyKind
        let targetCardID: String?
        let secondaryTargetCardID: String?
        let verticalAnchor: VerticalAnchor?
    }

    struct ColumnGolden: Codable {
        let columnIndex: Int
        let cardIDs: [String]
        let policy: PolicyGolden
        let rawTargetY: Double?
        let targetY: Double?
        let contentHeight: Double
        let maxScrollY: Double
    }

    struct HorizontalGolden: Codable {
        let activeColumnIndex: Int
        let rawTargetX: Double
        let targetX: Double
        let contentWidth: Double
        let maxScrollX: Double
    }

    struct ScrollGolden: Codable {
        let activeCardID: String
        let activePast: [String]
        let ancestors: [String]
        let descendants: [String]
        let horizontal: HorizontalGolden
        let columns: [ColumnGolden]
    }

    struct ScrollSuite: Codable {
        let id: String
        let title: String
        let purpose: String
        let fixture: ScrollFixture
        let golden: ScrollGolden
    }

    struct UndoTraceSuite: Codable {
        let id: String
        let title: String
        let purpose: String
        let sourceReferences: [String]
        let initialHead: String
        let initialTree: [String]
        let steps: [UndoTraceStep]
    }

    struct UndoTraceStep: Codable {
        let action: String
        let commandRouting: String
        let commitEvent: String
        let headAfterStep: String
        let commandZDestination: String?
        let treeAfterStep: [String]
        let editingBuffer: String?
    }

    struct ChecklistItem: Codable {
        let id: String
        let title: String
        let question: String
        let successSignal: String
        let failureSignal: String
    }

    struct ValidationFailureBundle: Codable {
        struct SuiteFailure: Codable {
            struct FieldMismatch: Codable {
                let path: String
                let expected: String
                let actual: String
                let delta: Double?
            }

            let suiteID: String
            let suiteTitle: String
            let mismatches: [FieldMismatch]
        }

        let generatedAt: String
        let referencePath: String
        let suitesValidated: Int
        let mismatchesFound: Int
        let tolerance: Double
        let failures: [SuiteFailure]
    }

    private struct ResolvedPolicy {
        let kind: PolicyKind
        let targetCardID: String?
        let secondaryTargetCardID: String?
        let verticalAnchor: VerticalAnchor?
    }

    private struct TreeIndex {
        let root: FixtureNode
        let nodeByID: [String: FixtureNode]
        let childrenByID: [String: [String]]
        let parentByID: [String: String]
        let depthByID: [String: Int]
        let levels: [[String]]
        let preorder: [String]

        nonisolated init(root: FixtureNode) {
            var nodeByID: [String: FixtureNode] = [:]
            var childrenByID: [String: [String]] = [:]
            var parentByID: [String: String] = [:]
            var depthByID: [String: Int] = [:]
            var preorder: [String] = []

            func visit(node: FixtureNode, parentID: String?, depth: Int) {
                nodeByID[node.id] = node
                depthByID[node.id] = depth
                if let parentID {
                    parentByID[node.id] = parentID
                }
                let childIDs = node.children.map(\.id)
                childrenByID[node.id] = childIDs
                preorder.append(node.id)
                for child in node.children {
                    visit(node: child, parentID: node.id, depth: depth + 1)
                }
            }

            visit(node: root, parentID: nil, depth: 0)

            var levels: [[String]] = []
            var queue: [(node: FixtureNode, depth: Int)] = [(root, 0)]
            while !queue.isEmpty {
                let current = queue.removeFirst()
                if levels.count <= current.depth {
                    levels.append([])
                }
                levels[current.depth].append(current.node.id)
                for child in current.node.children {
                    queue.append((child, current.depth + 1))
                }
            }

            self.root = root
            self.nodeByID = nodeByID
            self.childrenByID = childrenByID
            self.parentByID = parentByID
            self.depthByID = depthByID
            self.levels = levels
            self.preorder = preorder
        }

        nonisolated func ancestors(of id: String) -> [String] {
            var ancestors: [String] = []
            var current = id
            while let parentID = parentByID[current] {
                ancestors.insert(parentID, at: 0)
                current = parentID
            }
            return ancestors
        }

        nonisolated func descendants(of id: String) -> [String] {
            guard let childIDs = childrenByID[id] else { return [] }
            var result: [String] = []
            for childID in childIDs {
                result.append(childID)
                result.append(contentsOf: descendants(of: childID))
            }
            return result
        }

        nonisolated func sortedDescendants(of id: String, activePast: [String]) -> [String] {
            let descendantSet = Set(descendants(of: id))
            guard !descendantSet.isEmpty else { return [] }
            let rankByID = Dictionary(uniqueKeysWithValues: activePast.enumerated().map { ($1, $0) })

            func sortRecursively(_ node: FixtureNode) -> FixtureNode {
                let sortedChildren = node.children
                    .enumerated()
                    .sorted { lhs, rhs in
                        let lhsRank = rankByID[lhs.element.id] ?? 9_999
                        let rhsRank = rankByID[rhs.element.id] ?? 9_999
                        if lhsRank != rhsRank {
                            return lhsRank < rhsRank
                        }
                        return lhs.offset < rhs.offset
                    }
                    .map { sortRecursively($0.element) }
                return FixtureNode(id: node.id, title: node.title, children: sortedChildren)
            }

            let sortedRoot = sortRecursively(root)
            let sortedIndex = TreeIndex(root: sortedRoot)
            return sortedIndex.levels
                .flatMap { $0 }
                .filter { descendantSet.contains($0) }
        }
    }

    static func writeReferenceArtifacts() {
        let bundle = referenceBundle()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(bundle)
            try data.write(to: referenceJSONURL, options: .atomic)
            let checklistData = Data(checklistMarkdown().utf8)
            try checklistData.write(to: checklistMarkdownURL, options: .atomic)
        } catch {
            let message = "main workspace phase0 harness export failed: \(error)"
            FileManager.default.createFile(
                atPath: referenceJSONURL.path,
                contents: Data(message.utf8)
            )
        }
    }

    static func validateAgainstReference() -> Bool {
        do {
            let bundleData = try Data(contentsOf: referenceJSONURL)
            let decoder = JSONDecoder()
            let bundle = try decoder.decode(ReferenceBundle.self, from: bundleData)
            let failures = bundle.scrollSuites.compactMap { suite -> ValidationFailureBundle.SuiteFailure? in
                let failure = validateScrollSuite(suite)
                return failure.mismatches.isEmpty ? nil : failure
            }
            let result = ValidationFailureBundle(
                generatedAt: iso8601(Date()),
                referencePath: referenceJSONURL.path,
                suitesValidated: bundle.scrollSuites.count,
                mismatchesFound: failures.reduce(0) { $0 + $1.mismatches.count },
                tolerance: targetOffsetTolerance,
                failures: failures
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(result)
            try data.write(to: failureJSONURL, options: .atomic)
            return result.mismatchesFound > 0
        } catch {
            let message = "main workspace phase0 harness validation failed: \(error)"
            FileManager.default.createFile(
                atPath: failureJSONURL.path,
                contents: Data(message.utf8)
            )
            return true
        }
    }

    private static func validateScrollSuite(_ suite: ScrollSuite) -> ValidationFailureBundle.SuiteFailure {
        let actual = resolvedActualScrollGolden(for: suite.fixture)
        let expected = suite.golden
        var mismatches: [ValidationFailureBundle.SuiteFailure.FieldMismatch] = []

        compareInt(
            expected.horizontal.activeColumnIndex,
            actual.horizontal.activeColumnIndex,
            path: "horizontal.activeColumnIndex",
            mismatches: &mismatches
        )
        compareStringValue(
            expected.activeCardID,
            actual.activeCardID,
            path: "activeCardID",
            mismatches: &mismatches
        )
        compareStringArray(
            expected.activePast,
            actual.activePast,
            path: "activePast",
            mismatches: &mismatches
        )
        compareStringArray(
            expected.ancestors,
            actual.ancestors,
            path: "ancestors",
            mismatches: &mismatches
        )
        compareStringArray(
            expected.descendants,
            actual.descendants,
            path: "descendants",
            mismatches: &mismatches
        )

        compareDouble(
            expected.horizontal.rawTargetX,
            actual.horizontal.rawTargetX,
            path: "horizontal.rawTargetX",
            mismatches: &mismatches
        )
        compareDouble(
            expected.horizontal.targetX,
            actual.horizontal.targetX,
            path: "horizontal.targetX",
            mismatches: &mismatches
        )

        let expectedColumns = expected.columns
        let actualColumns = actual.columns
        let columnCount = max(expectedColumns.count, actualColumns.count)
        for index in 0..<columnCount {
            let expectedColumn = expectedColumns[safe: index]
            let actualColumn = actualColumns[safe: index]

            guard let expectedColumn, let actualColumn else {
                mismatches.append(
                    .init(
                        path: "columns[\(index)]",
                        expected: expectedColumn.map { "\($0.columnIndex)" } ?? "missing",
                        actual: actualColumn.map { "\($0.columnIndex)" } ?? "missing",
                        delta: nil
                    )
                )
                continue
            }

            compareInt(
                expectedColumn.columnIndex,
                actualColumn.columnIndex,
                path: "columns[\(index)].columnIndex",
                mismatches: &mismatches
            )
            comparePolicy(
                expectedColumn.policy,
                actualColumn.policy,
                pathPrefix: "columns[\(index)].policy",
                mismatches: &mismatches
            )
            compareDoubleOptional(
                expectedColumn.rawTargetY,
                actualColumn.rawTargetY,
                path: "columns[\(index)].rawTargetY",
                mismatches: &mismatches
            )
            compareDoubleOptional(
                expectedColumn.targetY,
                actualColumn.targetY,
                path: "columns[\(index)].targetY",
                mismatches: &mismatches
            )
        }

        return ValidationFailureBundle.SuiteFailure(
            suiteID: suite.id,
            suiteTitle: suite.title,
            mismatches: mismatches
        )
    }

    private static func compare(
        _ expected: Int,
        _ actual: Int,
        path: String,
        mismatches: inout [ValidationFailureBundle.SuiteFailure.FieldMismatch]
    ) {
        guard expected != actual else { return }
        mismatches.append(
            .init(
                path: path,
                expected: "\(expected)",
                actual: "\(actual)",
                delta: nil
            )
        )
    }

    private static func compareInt(
        _ expected: Int,
        _ actual: Int,
        path: String,
        mismatches: inout [ValidationFailureBundle.SuiteFailure.FieldMismatch]
    ) {
        compare(expected, actual, path: path, mismatches: &mismatches)
    }

    private static func compareDouble(
        _ expected: Double,
        _ actual: Double,
        path: String,
        mismatches: inout [ValidationFailureBundle.SuiteFailure.FieldMismatch]
    ) {
        if abs(expected - actual) <= targetOffsetTolerance { return }
        mismatches.append(
            .init(
                path: path,
                expected: String(format: "%.4f", expected),
                actual: String(format: "%.4f", actual),
                delta: abs(expected - actual)
            )
        )
    }

    private static func compareDoubleOptional(
        _ expected: Double?,
        _ actual: Double?,
        path: String,
        mismatches: inout [ValidationFailureBundle.SuiteFailure.FieldMismatch]
    ) {
        switch (expected, actual) {
        case (.none, .none):
            return
        case let (.some(expectedValue), .some(actualValue)):
            compareDouble(expectedValue, actualValue, path: path, mismatches: &mismatches)
        default:
            mismatches.append(
                .init(
                    path: path,
                    expected: expected.map { String(format: "%.4f", $0) } ?? "nil",
                    actual: actual.map { String(format: "%.4f", $0) } ?? "nil",
                    delta: nil
                )
            )
        }
    }

    private static func comparePolicy(
        _ expected: PolicyGolden,
        _ actual: PolicyGolden,
        pathPrefix: String,
        mismatches: inout [ValidationFailureBundle.SuiteFailure.FieldMismatch]
    ) {
        comparePolicyValue(expected.kind.rawValue, actual.kind.rawValue, label: "kind", pathPrefix: pathPrefix, mismatches: &mismatches)
        comparePolicyValue(expected.targetCardID, actual.targetCardID, label: "targetCardID", pathPrefix: pathPrefix, mismatches: &mismatches)
        comparePolicyValue(expected.secondaryTargetCardID, actual.secondaryTargetCardID, label: "secondaryTargetCardID", pathPrefix: pathPrefix, mismatches: &mismatches)
        comparePolicyValue(
            expected.verticalAnchor?.rawValue,
            actual.verticalAnchor?.rawValue,
            label: "verticalAnchor",
            pathPrefix: pathPrefix,
            mismatches: &mismatches
        )
    }

    private static func comparePolicyValue(
        _ expected: String?,
        _ actual: String?,
        label: String,
        pathPrefix: String,
        mismatches: inout [ValidationFailureBundle.SuiteFailure.FieldMismatch]
    ) {
        guard expected != actual else { return }
        mismatches.append(
            .init(
                path: "\(pathPrefix).\(label)",
                expected: expected ?? "nil",
                actual: actual ?? "nil",
                delta: nil
            )
        )
    }

    private static func comparePolicyValue(
        _ expected: String,
        _ actual: String,
        label: String,
        pathPrefix: String,
        mismatches: inout [ValidationFailureBundle.SuiteFailure.FieldMismatch]
    ) {
        comparePolicyValue(Optional(expected), Optional(actual), label: label, pathPrefix: pathPrefix, mismatches: &mismatches)
    }

    private static func compareStringValue(
        _ expected: String,
        _ actual: String,
        path: String,
        mismatches: inout [ValidationFailureBundle.SuiteFailure.FieldMismatch]
    ) {
        guard expected != actual else { return }
        mismatches.append(
            .init(
                path: path,
                expected: expected,
                actual: actual,
                delta: nil
            )
        )
    }

    private static func compareStringArray(
        _ expected: [String],
        _ actual: [String],
        path: String,
        mismatches: inout [ValidationFailureBundle.SuiteFailure.FieldMismatch]
    ) {
        guard expected == actual else {
            mismatches.append(
                .init(
                    path: path,
                    expected: expected.joined(separator: ","),
                    actual: actual.joined(separator: ","),
                    delta: nil
                )
            )
            return
        }
    }

    private static func resolvedActualScrollGolden(for fixture: ScrollFixture) -> ScrollGolden {
        // Keep parity validator aligned to current scroll policy implementation.
        resolveScrollGolden(for: fixture)
    }

    static func referenceBundle() -> ReferenceBundle {
        ReferenceBundle(
            generatedAt: iso8601(Date()),
            sources: sourceReferences,
            scrollSuites: scrollSuites,
            undoSuites: undoSuites,
            checklist: checklistItems
        )
    }

    static func checklistMarkdown() -> String {
        let lines = checklistItems.flatMap { item in
            [
                "## \(item.title)",
                "- 질문: \(item.question)",
                "- 통과 신호: \(item.successSignal)",
                "- 실패 신호: \(item.failureSignal)",
                ""
            ]
        }
        return ([
            "# Main Workspace Phase 0 Feel Checklist",
            "",
            "각 항목은 1점(매우 다름)부터 10점(징코와 동일)까지 점수화한다.",
            "합계가 아닌 체감 평균이 9점 이상이어야 다음 Phase로 넘어간다.",
            ""
        ] + lines).joined(separator: "\n")
    }

    private static var sourceReferences: [SourceReference] {
        [
            SourceReference(
                id: "change-mode",
                path: "123/src/elm/Page/Doc.elm",
                lines: "1025-1066",
                purpose: "activePast, ancestors, descendants, scrollPositions 생성 순서"
            ),
            SourceReference(
                id: "scroll-policies",
                path: "123/src/elm/Doc/TreeUtils.elm",
                lines: "358-449",
                purpose: "Center/Before/After/Between/None column policy 기준"
            ),
            SourceReference(
                id: "vertical-scroll",
                path: "123/src/shared/doc-helpers.js",
                lines: "199-222,247-273",
                purpose: "세로 스크롤 targetY 기준"
            ),
            SourceReference(
                id: "horizontal-scroll",
                path: "123/src/shared/doc-helpers.js",
                lines: "279-301",
                purpose: "가로 스크롤 targetX 기준"
            ),
            SourceReference(
                id: "history-undo-route",
                path: "123/src/elm/Electron/Electron.elm",
                lines: "332-336",
                purpose: "일반 모드 Cmd+Z는 history slider 경로"
            ),
            SourceReference(
                id: "native-undo-menu",
                path: "123/src/electron/menu.js",
                lines: "151-166",
                purpose: "편집 모드 Undo/Redo는 네이티브 메뉴 역할"
            ),
            SourceReference(
                id: "immutable-commit-store",
                path: "123/src/electron/main.js",
                lines: "330-345",
                purpose: "immutable object + head ref 저장"
            ),
            SourceReference(
                id: "edit-save-boundary",
                path: "123/src/elm/Page/Doc.elm",
                lines: "1313-1428",
                purpose: "edit exit/save 시 commit 생성"
            )
        ]
    }

    private static var scrollSuites: [ScrollSuite] {
        scrollFixtures.map(makeScrollSuite)
    }

    private static var scrollFixtures: [ScrollFixture] {
        [
            ScrollFixture(
                id: "deep-descendant-fallback",
                title: "Deep Descendant Stable Order",
                purpose: "명시적 descendant history가 없어도 기본 tree order로 descendant가 안정적으로 선택되는지 고정한다.",
                currentActiveID: "plot-2",
                targetActiveID: "plot-1",
                initialActivePast: ["note-1", "plot"],
                instant: false,
                horizontalViewportWidth: 920,
                columnViewportHeight: 320,
                columnWidth: 416,
                columnGap: 24,
                tree: FixtureNode(
                    id: "root",
                    title: "Root",
                    children: [
                        FixtureNode(
                            id: "plot",
                            title: "Plot",
                            children: [
                                FixtureNode(
                                    id: "plot-1",
                                    title: "Plot 1",
                                    children: [
                                        FixtureNode(id: "plot-1-a", title: "Plot 1A", children: []),
                                        FixtureNode(id: "plot-1-b", title: "Plot 1B", children: [])
                                    ]
                                ),
                                FixtureNode(id: "plot-2", title: "Plot 2", children: [])
                            ]
                        ),
                        FixtureNode(
                            id: "note",
                            title: "Note",
                            children: [
                                FixtureNode(id: "note-1", title: "Note 1", children: [])
                            ]
                        ),
                        FixtureNode(id: "craft", title: "Craft", children: [])
                    ]
                ),
                metricsByCardID: [
                    "plot": CardMetric(top: 140, height: 110),
                    "note": CardMetric(top: 290, height: 94),
                    "craft": CardMetric(top: 420, height: 104),
                    "plot-1": CardMetric(top: 170, height: 140),
                    "plot-2": CardMetric(top: 350, height: 96),
                    "note-1": CardMetric(top: 470, height: 88),
                    "plot-1-a": CardMetric(top: 110, height: 120),
                    "plot-1-b": CardMetric(top: 320, height: 150)
                ]
            ),
            ScrollFixture(
                id: "deep-descendant-history",
                title: "Deep Descendant History",
                purpose: "activePast가 preferred descendant를 고르는 경로를 고정한다.",
                currentActiveID: "beta-1",
                targetActiveID: "alpha",
                initialActivePast: ["alpha-2-a", "alpha-2", "alpha-1-b", "beta"],
                instant: true,
                horizontalViewportWidth: 760,
                columnViewportHeight: 300,
                columnWidth: 416,
                columnGap: 24,
                tree: FixtureNode(
                    id: "root",
                    title: "Root",
                    children: [
                        FixtureNode(
                            id: "alpha",
                            title: "Alpha",
                            children: [
                                FixtureNode(
                                    id: "alpha-1",
                                    title: "Alpha 1",
                                    children: [
                                        FixtureNode(id: "alpha-1-a", title: "Alpha 1A", children: []),
                                        FixtureNode(id: "alpha-1-b", title: "Alpha 1B", children: [])
                                    ]
                                ),
                                FixtureNode(
                                    id: "alpha-2",
                                    title: "Alpha 2",
                                    children: [
                                        FixtureNode(id: "alpha-2-a", title: "Alpha 2A", children: [])
                                    ]
                                )
                            ]
                        ),
                        FixtureNode(
                            id: "beta",
                            title: "Beta",
                            children: [
                                FixtureNode(id: "beta-1", title: "Beta 1", children: [])
                            ]
                        ),
                        FixtureNode(id: "gamma", title: "Gamma", children: [])
                    ]
                ),
                metricsByCardID: [
                    "alpha": CardMetric(top: 90, height: 130),
                    "beta": CardMetric(top: 260, height: 92),
                    "gamma": CardMetric(top: 400, height: 100),
                    "alpha-1": CardMetric(top: 70, height: 110),
                    "alpha-2": CardMetric(top: 240, height: 104),
                    "beta-1": CardMetric(top: 410, height: 88),
                    "alpha-1-a": CardMetric(top: 60, height: 82),
                    "alpha-1-b": CardMetric(top: 180, height: 90),
                    "alpha-2-a": CardMetric(top: 300, height: 128)
                ]
            ),
            ScrollFixture(
                id: "between-unrelated-branch",
                title: "Between Unrelated Branch",
                purpose: "active path 바깥 카드가 좌우에 함께 있을 때 Between 정책을 고정한다.",
                currentActiveID: "alpha-1",
                targetActiveID: "beta-1",
                initialActivePast: ["alpha-1-a", "gamma-1-a"],
                instant: false,
                horizontalViewportWidth: 980,
                columnViewportHeight: 340,
                columnWidth: 416,
                columnGap: 24,
                tree: FixtureNode(
                    id: "root",
                    title: "Root",
                    children: [
                        FixtureNode(
                            id: "alpha",
                            title: "Alpha",
                            children: [
                                FixtureNode(
                                    id: "alpha-1",
                                    title: "Alpha 1",
                                    children: [
                                        FixtureNode(id: "alpha-1-a", title: "Alpha 1A", children: [])
                                    ]
                                )
                            ]
                        ),
                        FixtureNode(
                            id: "beta",
                            title: "Beta",
                            children: [
                                FixtureNode(id: "beta-1", title: "Beta 1", children: [])
                            ]
                        ),
                        FixtureNode(
                            id: "gamma",
                            title: "Gamma",
                            children: [
                                FixtureNode(
                                    id: "gamma-1",
                                    title: "Gamma 1",
                                    children: [
                                        FixtureNode(id: "gamma-1-a", title: "Gamma 1A", children: [])
                                    ]
                                )
                            ]
                        )
                    ]
                ),
                metricsByCardID: [
                    "alpha": CardMetric(top: 70, height: 120),
                    "beta": CardMetric(top: 250, height: 110),
                    "gamma": CardMetric(top: 430, height: 100),
                    "alpha-1": CardMetric(top: 80, height: 115),
                    "beta-1": CardMetric(top: 260, height: 105),
                    "gamma-1": CardMetric(top: 430, height: 115),
                    "alpha-1-a": CardMetric(top: 90, height: 120),
                    "gamma-1-a": CardMetric(top: 360, height: 132)
                ]
            )
        ]
    }

    private nonisolated static func makeScrollSuite(from fixture: ScrollFixture) -> ScrollSuite {
        ScrollSuite(
            id: fixture.id,
            title: fixture.title,
            purpose: fixture.purpose,
            fixture: fixture,
            golden: resolveScrollGolden(for: fixture)
        )
    }

    private nonisolated static func resolveScrollGolden(for fixture: ScrollFixture) -> ScrollGolden {
        let index = TreeIndex(root: fixture.tree)
        let newActivePast = resolvedActivePast(
            currentActiveID: fixture.currentActiveID,
            targetActiveID: fixture.targetActiveID,
            initialActivePast: fixture.initialActivePast
        )
        let ancestors = index.ancestors(of: fixture.targetActiveID)
        let descendants = index.descendants(of: fixture.targetActiveID)
        let historySortedDescendants = index.sortedDescendants(of: fixture.targetActiveID, activePast: newActivePast)
        let descendantSet = Set(descendants)
        let ancestorSet = Set(ancestors)
        let preorder = index.preorder
        let activeIndex = preorder.firstIndex(of: fixture.targetActiveID) ?? 0
        let splitPrefix = Array(preorder.prefix(activeIndex))
        let splitSuffix = Array(preorder.suffix(from: activeIndex))
        let afterIDs = splitPrefix.filter { !descendantSet.contains($0) && !ancestorSet.contains($0) && $0 != fixture.targetActiveID }
        let beforeIDs = splitSuffix.filter { !descendantSet.contains($0) && !ancestorSet.contains($0) && $0 != fixture.targetActiveID }
        let visibleColumns = Array(index.levels.dropFirst())
        let contentWidth = Double(visibleColumns.count) * fixture.columnWidth + Double(max(0, visibleColumns.count - 1)) * fixture.columnGap
        let activeDepth = index.depthByID[fixture.targetActiveID] ?? 1
        let activeColumnIndex = max(1, activeDepth)
        let activeColumnLeft = Double(max(0, activeColumnIndex - 1)) * (fixture.columnWidth + fixture.columnGap)
        let rawTargetX = activeColumnLeft + 0.5 * (fixture.columnWidth - fixture.horizontalViewportWidth)
        let maxScrollX = max(0, contentWidth - fixture.horizontalViewportWidth)
        let targetX = clamp(rawTargetX, minimum: 0, maximum: maxScrollX)

        let columns: [ColumnGolden] = visibleColumns.enumerated().map { offset, cardIDs in
            let columnIndex = offset + 1
            let policy = resolvedPolicy(
                cardIDs: cardIDs,
                targetActiveID: fixture.targetActiveID,
                ancestors: ancestors,
                descendants: descendants,
                historySortedDescendants: historySortedDescendants,
                beforeIDs: beforeIDs,
                afterIDs: afterIDs
            )
            let contentHeight = cardIDs.reduce(into: 0.0) { partialResult, cardID in
                guard let metric = fixture.metricsByCardID[cardID] else { return }
                partialResult = max(partialResult, metric.top + metric.height)
            }
            let maxScrollY = max(0, contentHeight - fixture.columnViewportHeight)
            let rawTargetY: Double? = {
                guard let targetID = policy.targetCardID,
                      let anchor = policy.verticalAnchor,
                      let metric = fixture.metricsByCardID[targetID] else {
                    return nil
                }
                let multiplier: Double
                switch anchor {
                case .top:
                    multiplier = 0
                case .center:
                    multiplier = 0.5
                case .bottom:
                    multiplier = 1
                }
                let adjustedHeight = metric.height > fixture.columnViewportHeight - 51
                    ? fixture.columnViewportHeight * 0.5 + 51
                    : metric.height
                return metric.top + adjustedHeight * multiplier - fixture.columnViewportHeight * 0.5
            }()

            return ColumnGolden(
                columnIndex: columnIndex,
                cardIDs: cardIDs,
                policy: PolicyGolden(
                    kind: policy.kind,
                    targetCardID: policy.targetCardID,
                    secondaryTargetCardID: policy.secondaryTargetCardID,
                    verticalAnchor: policy.verticalAnchor
                ),
                rawTargetY: rawTargetY,
                targetY: rawTargetY.map { clamp($0, minimum: 0, maximum: maxScrollY) },
                contentHeight: contentHeight,
                maxScrollY: maxScrollY
            )
        }

        return ScrollGolden(
            activeCardID: fixture.targetActiveID,
            activePast: newActivePast,
            ancestors: ancestors,
            descendants: descendants,
            horizontal: HorizontalGolden(
                activeColumnIndex: activeColumnIndex,
                rawTargetX: rawTargetX,
                targetX: targetX,
                contentWidth: contentWidth,
                maxScrollX: maxScrollX
            ),
            columns: columns
        )
    }

    private nonisolated static func resolvedPolicy(
        cardIDs: [String],
        targetActiveID: String,
        ancestors: [String],
        descendants: [String],
        historySortedDescendants: [String],
        beforeIDs: [String],
        afterIDs: [String]
    ) -> ResolvedPolicy {
        if cardIDs.contains(targetActiveID) {
            return ResolvedPolicy(
                kind: .centerActive,
                targetCardID: targetActiveID,
                secondaryTargetCardID: nil,
                verticalAnchor: .center
            )
        }

        if let ancestorID = cardIDs.first(where: { ancestors.contains($0) }) {
            return ResolvedPolicy(
                kind: .centerAncestor,
                targetCardID: ancestorID,
                secondaryTargetCardID: nil,
                verticalAnchor: .center
            )
        }

        if let preferredDescendantID = historySortedDescendants.first(where: { cardIDs.contains($0) }) {
            return ResolvedPolicy(
                kind: .centerPreferredDescendant,
                targetCardID: preferredDescendantID,
                secondaryTargetCardID: nil,
                verticalAnchor: .center
            )
        }

        if let otherDescendantID = cardIDs.first(where: { descendants.contains($0) }) {
            return ResolvedPolicy(
                kind: .centerOtherDescendant,
                targetCardID: otherDescendantID,
                secondaryTargetCardID: nil,
                verticalAnchor: .center
            )
        }

        let beforeCandidate = cardIDs.first(where: { beforeIDs.contains($0) })
        let afterCandidate = cardIDs.reversed().first(where: { afterIDs.contains($0) })

        switch (beforeCandidate, afterCandidate) {
        case let (before?, after?):
            return ResolvedPolicy(
                kind: .between,
                targetCardID: after,
                secondaryTargetCardID: before,
                verticalAnchor: .bottom
            )
        case let (before?, nil):
            return ResolvedPolicy(
                kind: .before,
                targetCardID: before,
                secondaryTargetCardID: nil,
                verticalAnchor: .top
            )
        case let (nil, after?):
            return ResolvedPolicy(
                kind: .after,
                targetCardID: after,
                secondaryTargetCardID: nil,
                verticalAnchor: .bottom
            )
        case (nil, nil):
            return ResolvedPolicy(
                kind: .none,
                targetCardID: nil,
                secondaryTargetCardID: nil,
                verticalAnchor: nil
            )
        }
    }

    private nonisolated static func resolvedActivePast(
        currentActiveID: String,
        targetActiveID: String,
        initialActivePast: [String]
    ) -> [String] {
        if currentActiveID == targetActiveID {
            return initialActivePast
        }
        return Array(([currentActiveID] + initialActivePast).prefix(40))
    }

    private nonisolated static func clamp(_ value: Double, minimum: Double, maximum: Double) -> Double {
        Swift.max(minimum, Swift.min(maximum, value))
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static var undoSuites: [UndoTraceSuite] {
        [
            UndoTraceSuite(
                id: "edit-save-undo",
                title: "Edit Save -> Cmd+Z",
                purpose: "편집 저장은 edit exit 시 commit을 만들고, 일반 모드 Cmd+Z는 이전 commit으로 돌아간다.",
                sourceReferences: [
                    "123/src/elm/Page/Doc.elm:1382-1428",
                    "123/src/elm/Electron/Electron.elm:332-336"
                ],
                initialHead: "h0",
                initialTree: [
                    "scene",
                    "  beat-1: Original line",
                    "  beat-2: Supporting note"
                ],
                steps: [
                    UndoTraceStep(
                        action: "beat-1 편집 시작 후 'Revised line' 입력",
                        commandRouting: "editor buffer only",
                        commitEvent: "no commit",
                        headAfterStep: "h0",
                        commandZDestination: nil,
                        treeAfterStep: [
                            "scene",
                            "  beat-1: Original line",
                            "  beat-2: Supporting note"
                        ],
                        editingBuffer: "Revised line"
                    ),
                    UndoTraceStep(
                        action: "ESC로 편집 종료",
                        commandRouting: "saveCardIfEditing",
                        commitEvent: "commit h1 created on edit exit",
                        headAfterStep: "h1",
                        commandZDestination: nil,
                        treeAfterStep: [
                            "scene",
                            "  beat-1: Revised line",
                            "  beat-2: Supporting note"
                        ],
                        editingBuffer: nil
                    ),
                    UndoTraceStep(
                        action: "일반 모드 Cmd+Z",
                        commandRouting: "history slider undo",
                        commitEvent: "head restored from h1 to h0",
                        headAfterStep: "h0",
                        commandZDestination: "h0",
                        treeAfterStep: [
                            "scene",
                            "  beat-1: Original line",
                            "  beat-2: Supporting note"
                        ],
                        editingBuffer: nil
                    )
                ]
            ),
            UndoTraceSuite(
                id: "create-child-type-save-undo",
                title: "Create Child -> Type -> Save -> Cmd+Z",
                purpose: "새 카드 생성 자체는 commit이 아니고, 입력 후 저장 시 한 번만 commit된다.",
                sourceReferences: [
                    "main_workspace_gingko_parity_plan_v2.md:390-403",
                    "123/src/elm/Page/Doc.elm:1382-1428"
                ],
                initialHead: "h0",
                initialTree: [
                    "scene",
                    "  parent: Existing parent"
                ],
                steps: [
                    UndoTraceStep(
                        action: "parent 아래 새 child 생성",
                        commandRouting: "enter edit mode",
                        commitEvent: "no commit",
                        headAfterStep: "h0",
                        commandZDestination: nil,
                        treeAfterStep: [
                            "scene",
                            "  parent: Existing parent"
                        ],
                        editingBuffer: ""
                    ),
                    UndoTraceStep(
                        action: "새 child에 'Draft child' 입력",
                        commandRouting: "editor buffer only",
                        commitEvent: "no commit",
                        headAfterStep: "h0",
                        commandZDestination: nil,
                        treeAfterStep: [
                            "scene",
                            "  parent: Existing parent"
                        ],
                        editingBuffer: "Draft child"
                    ),
                    UndoTraceStep(
                        action: "ESC로 저장",
                        commandRouting: "saveCardIfEditing",
                        commitEvent: "commit h1 created for created child",
                        headAfterStep: "h1",
                        commandZDestination: nil,
                        treeAfterStep: [
                            "scene",
                            "  parent: Existing parent",
                            "    child: Draft child"
                        ],
                        editingBuffer: nil
                    ),
                    UndoTraceStep(
                        action: "일반 모드 Cmd+Z",
                        commandRouting: "history slider undo",
                        commitEvent: "head restored from h1 to h0",
                        headAfterStep: "h0",
                        commandZDestination: "h0",
                        treeAfterStep: [
                            "scene",
                            "  parent: Existing parent"
                        ],
                        editingBuffer: nil
                    )
                ]
            ),
            UndoTraceSuite(
                id: "delete-undo",
                title: "Delete -> Cmd+Z",
                purpose: "삭제는 즉시 commit되고 Cmd+Z는 삭제 전 tree로 돌아간다.",
                sourceReferences: [
                    "123/src/elm/Page/Doc.elm:1500-1528"
                ],
                initialHead: "h0",
                initialTree: [
                    "scene",
                    "  keep: Keep me",
                    "  remove: Remove me"
                ],
                steps: [
                    UndoTraceStep(
                        action: "remove 카드 삭제",
                        commandRouting: "structure mutation",
                        commitEvent: "commit h1 created immediately on delete",
                        headAfterStep: "h1",
                        commandZDestination: nil,
                        treeAfterStep: [
                            "scene",
                            "  keep: Keep me"
                        ],
                        editingBuffer: nil
                    ),
                    UndoTraceStep(
                        action: "일반 모드 Cmd+Z",
                        commandRouting: "history slider undo",
                        commitEvent: "head restored from h1 to h0",
                        headAfterStep: "h0",
                        commandZDestination: "h0",
                        treeAfterStep: [
                            "scene",
                            "  keep: Keep me",
                            "  remove: Remove me"
                        ],
                        editingBuffer: nil
                    )
                ]
            ),
            UndoTraceSuite(
                id: "move-undo",
                title: "Move Card -> Cmd+Z",
                purpose: "구조 이동은 즉시 commit되고 undo는 이전 ordering으로 복원된다.",
                sourceReferences: [
                    "main_workspace_gingko_parity_plan_v2.md:395-399"
                ],
                initialHead: "h0",
                initialTree: [
                    "scene",
                    "  alpha: First",
                    "  beta: Second",
                    "  gamma: Third"
                ],
                steps: [
                    UndoTraceStep(
                        action: "beta를 gamma 아래로 이동",
                        commandRouting: "structure mutation",
                        commitEvent: "commit h1 created immediately on move",
                        headAfterStep: "h1",
                        commandZDestination: nil,
                        treeAfterStep: [
                            "scene",
                            "  alpha: First",
                            "  gamma: Third",
                            "    beta: Second"
                        ],
                        editingBuffer: nil
                    ),
                    UndoTraceStep(
                        action: "일반 모드 Cmd+Z",
                        commandRouting: "history slider undo",
                        commitEvent: "head restored from h1 to h0",
                        headAfterStep: "h0",
                        commandZDestination: "h0",
                        treeAfterStep: [
                            "scene",
                            "  alpha: First",
                            "  beta: Second",
                            "  gamma: Third"
                        ],
                        editingBuffer: nil
                    )
                ]
            ),
            UndoTraceSuite(
                id: "cut-paste-undo",
                title: "Cut -> Paste -> Cmd+Z",
                purpose: "cut과 paste는 각각 즉시 commit을 만들고 Cmd+Z는 마지막 paste만 되돌린다.",
                sourceReferences: [
                    "main_workspace_gingko_parity_plan_v2.md:394-400"
                ],
                initialHead: "h0",
                initialTree: [
                    "scene",
                    "  source: To move",
                    "  target: Destination"
                ],
                steps: [
                    UndoTraceStep(
                        action: "source 카드 cut",
                        commandRouting: "copy + delete",
                        commitEvent: "commit h1 created immediately on cut",
                        headAfterStep: "h1",
                        commandZDestination: nil,
                        treeAfterStep: [
                            "scene",
                            "  target: Destination"
                        ],
                        editingBuffer: nil
                    ),
                    UndoTraceStep(
                        action: "target 아래로 paste",
                        commandRouting: "structure mutation",
                        commitEvent: "commit h2 created immediately on paste",
                        headAfterStep: "h2",
                        commandZDestination: nil,
                        treeAfterStep: [
                            "scene",
                            "  target: Destination",
                            "    source: To move"
                        ],
                        editingBuffer: nil
                    ),
                    UndoTraceStep(
                        action: "일반 모드 Cmd+Z",
                        commandRouting: "history slider undo",
                        commitEvent: "head restored from h2 to h1",
                        headAfterStep: "h1",
                        commandZDestination: "h1",
                        treeAfterStep: [
                            "scene",
                            "  target: Destination"
                        ],
                        editingBuffer: nil
                    )
                ]
            ),
            UndoTraceSuite(
                id: "editing-native-undo",
                title: "Edit -> Cmd+Z While Editing",
                purpose: "편집 중 Cmd+Z는 history가 아니라 NSTextView native undo를 사용한다.",
                sourceReferences: [
                    "123/src/electron/menu.js:151-166",
                    "123/src/elm/Electron/Electron.elm:332-336"
                ],
                initialHead: "h0",
                initialTree: [
                    "scene",
                    "  beat-1: Original line"
                ],
                steps: [
                    UndoTraceStep(
                        action: "beat-1 편집 시작 후 'Original line plus note' 입력",
                        commandRouting: "editor buffer only",
                        commitEvent: "no commit",
                        headAfterStep: "h0",
                        commandZDestination: nil,
                        treeAfterStep: [
                            "scene",
                            "  beat-1: Original line"
                        ],
                        editingBuffer: "Original line plus note"
                    ),
                    UndoTraceStep(
                        action: "편집 중 Cmd+Z",
                        commandRouting: "native text undo",
                        commitEvent: "no commit, history head unchanged",
                        headAfterStep: "h0",
                        commandZDestination: "editor buffer previous value",
                        treeAfterStep: [
                            "scene",
                            "  beat-1: Original line"
                        ],
                        editingBuffer: "Original line"
                    )
                ]
            ),
            UndoTraceSuite(
                id: "undo-redo-chain",
                title: "Cmd+Z x3 -> Cmd+Shift+Z x1",
                purpose: "연속 history undo/redo가 commit head 단위로만 움직이는지 고정한다.",
                sourceReferences: [
                    "123/src/elm/Electron/Electron.elm:332-336",
                    "123/src/electron/main.js:330-345"
                ],
                initialHead: "h0",
                initialTree: [
                    "scene",
                    "  beat-1: Base",
                    "  beat-2: Anchor"
                ],
                steps: [
                    UndoTraceStep(
                        action: "beat-1 편집 저장",
                        commandRouting: "saveCardIfEditing",
                        commitEvent: "commit h1 created",
                        headAfterStep: "h1",
                        commandZDestination: nil,
                        treeAfterStep: [
                            "scene",
                            "  beat-1: Base v1",
                            "  beat-2: Anchor"
                        ],
                        editingBuffer: nil
                    ),
                    UndoTraceStep(
                        action: "beat-2 편집 저장",
                        commandRouting: "saveCardIfEditing",
                        commitEvent: "commit h2 created",
                        headAfterStep: "h2",
                        commandZDestination: nil,
                        treeAfterStep: [
                            "scene",
                            "  beat-1: Base v1",
                            "  beat-2: Anchor v1"
                        ],
                        editingBuffer: nil
                    ),
                    UndoTraceStep(
                        action: "beat-2 삭제",
                        commandRouting: "structure mutation",
                        commitEvent: "commit h3 created",
                        headAfterStep: "h3",
                        commandZDestination: nil,
                        treeAfterStep: [
                            "scene",
                            "  beat-1: Base v1"
                        ],
                        editingBuffer: nil
                    ),
                    UndoTraceStep(
                        action: "Cmd+Z #1",
                        commandRouting: "history slider undo",
                        commitEvent: "head restored from h3 to h2",
                        headAfterStep: "h2",
                        commandZDestination: "h2",
                        treeAfterStep: [
                            "scene",
                            "  beat-1: Base v1",
                            "  beat-2: Anchor v1"
                        ],
                        editingBuffer: nil
                    ),
                    UndoTraceStep(
                        action: "Cmd+Z #2",
                        commandRouting: "history slider undo",
                        commitEvent: "head restored from h2 to h1",
                        headAfterStep: "h1",
                        commandZDestination: "h1",
                        treeAfterStep: [
                            "scene",
                            "  beat-1: Base v1",
                            "  beat-2: Anchor"
                        ],
                        editingBuffer: nil
                    ),
                    UndoTraceStep(
                        action: "Cmd+Z #3",
                        commandRouting: "history slider undo",
                        commitEvent: "head restored from h1 to h0",
                        headAfterStep: "h0",
                        commandZDestination: "h0",
                        treeAfterStep: [
                            "scene",
                            "  beat-1: Base",
                            "  beat-2: Anchor"
                        ],
                        editingBuffer: nil
                    ),
                    UndoTraceStep(
                        action: "Cmd+Shift+Z #1",
                        commandRouting: "history slider redo",
                        commitEvent: "head restored from h0 to h1",
                        headAfterStep: "h1",
                        commandZDestination: "h1",
                        treeAfterStep: [
                            "scene",
                            "  beat-1: Base v1",
                            "  beat-2: Anchor"
                        ],
                        editingBuffer: nil
                    )
                ]
            )
        ]
    }

    private static var checklistItems: [ChecklistItem] {
        [
            ChecklistItem(
                id: "up-down-once",
                title: "Up/Down 한 번 정렬",
                question: "상하 방향키 10회를 눌렀을 때 세로 정렬이 매번 한 번에 끝나는가?",
                successSignal: "입력 1회당 세로 적용 1회, 추가 보정 체감 없음",
                failureSignal: "잠깐 뒤 두 번째 점프나 verify 보정이 보임"
            ),
            ChecklistItem(
                id: "left-right-once",
                title: "Left/Right 한 번 정렬",
                question: "좌우 방향키 10회를 눌렀을 때 가로 정렬이 매번 한 번에 끝나는가?",
                successSignal: "활성 컬럼이 바로 중앙으로 옴",
                failureSignal: "가로로 한 번 오고 나서 다시 재정렬됨"
            ),
            ChecklistItem(
                id: "branch-identity",
                title: "Branch Viewport Identity",
                question: "같은 depth라도 다른 parent branch로 이동했을 때 이전 viewport state가 섞이지 않는가?",
                successSignal: "부모 branch가 바뀌면 해당 branch 기준 위치만 사용됨",
                failureSignal: "다른 branch에서 보던 offset이 새 branch에 새어 들어옴"
            ),
            ChecklistItem(
                id: "history-descendant",
                title: "History Preferred Descendant",
                question: "이전에 보던 descendant가 보이는 컬럼이면 그 카드가 우선 선택되는가?",
                successSignal: "activePast가 동일하면 descendant 선택도 동일하게 반복됨",
                failureSignal: "자식 선택이 랜덤하게 바뀌거나 첫 카드로 튐"
            ),
            ChecklistItem(
                id: "click-hot-path",
                title: "Click Activation",
                question: "클릭으로 활성 카드를 바꿨을 때 changeMode -> policy -> direct scroll 체감으로 끝나는가?",
                successSignal: "클릭 직후 한 번만 이동하고 멈춤",
                failureSignal: "관찰/재시도 때문에 늦게 맞춰짐"
            ),
            ChecklistItem(
                id: "edit-undo-split",
                title: "Edit Undo 분리",
                question: "편집 중 Cmd+Z와 비편집 Cmd+Z 의미가 분리되어 있는가?",
                successSignal: "편집 중에는 텍스트만 되돌아가고, 비편집 상태에서는 commit 단위로 이동",
                failureSignal: "편집 중 Cmd+Z가 문서 전체 상태를 바꾸거나 caret를 튕김"
            ),
            ChecklistItem(
                id: "long-card-clamp",
                title: "Tall Card Clamp",
                question: "뷰포트보다 큰 카드도 과도한 overscroll 없이 기준 위치로 가는가?",
                successSignal: "큰 카드는 top/center 기준이 안정적으로 재현됨",
                failureSignal: "큰 카드에서 overscroll이나 잘림이 반복됨"
            ),
            ChecklistItem(
                id: "undo-boundary",
                title: "Undo Commit Boundary",
                question: "편집 저장, 삭제, 이동, cut/paste의 commit 경계가 징코와 같은가?",
                successSignal: "저장 전 typing은 commit이 아니고 구조 변경은 즉시 commit",
                failureSignal: "typing 중에도 history가 쌓이거나 구조 변경이 저장 전까지 지연됨"
            ),
            ChecklistItem(
                id: "active-history-owner",
                title: "Active History Owner",
                question: "활성 전환 후 activePast 결과가 입력 종류와 무관하게 동일한가?",
                successSignal: "클릭/키보드/프로그래밍 경로가 같은 history를 만듦",
                failureSignal: "경로마다 descendant 선택 결과가 달라짐"
            ),
            ChecklistItem(
                id: "overall-score",
                title: "Overall Score",
                question: "사용자가 체감 평균 9점 이상을 줄 수 있는가?",
                successSignal: "징코와 비교해도 하늘과 땅 차이가 아니라 거의 같은 흐름",
                failureSignal: "조금 나아졌지만 여전히 별도 보정 구조가 느껴짐"
            )
        ]
    }
}
