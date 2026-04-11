import Foundation
import CoreGraphics

nonisolated enum BWRCardBuddyPhaseIHarness {
    nonisolated static let reportJSONURL = URL(fileURLWithPath: "/tmp/bwr_cardbuddy_phasei_report.json")
    nonisolated static let reportMarkdownURL = URL(fileURLWithPath: "/tmp/bwr_cardbuddy_phasei_report.md")

    private static let expectedBoardSnapshotDigests: [String: String] = [
        "card-normal": "7cf36e273b71abddd90b681f61e31a20f7dc4aff5357735b7277be52cfc1b85e",
        "card-selected": "896cccdc2340da96b90140c6c212948748acb0c27a96b64e7acb8861436ebae7",
        "card-inline": "0389f8e632a6dcc5d19901264964853702c4e99aa19c9b8db98f4ab204b946ad",
        "card-colored": "9a7429c0737ee7bd4744391ce424e8fb0245063577cc20f0594382979dc619c0",
        "slot-cursor": "509d62139129c46d2eb450c563096b265279765b3e3511d7635ae7ea0a3be30f",
        "slot-hover": "639cc4a81d97845d8a64063a86c606c02085fb1736e74270b5d6f8372096239c",
        "slot-drag-source": "3bdfac329d450ba531fa837307a96e17fcdf6a8461299ce9983dc6bf17e44bec",
        "slot-drag-destination": "9d3dc19d95d750ce10fa0e2a0678b0dcd77753ceda4cb9ece1d37871b35869f4",
        "slot-empty-placeholder": "f2e59a555ecae5c2861d2447fce9d92fb8b9c4cb7392088ec59644cc8e8cac94",
        "group-mixed": "184938c347d3bae2eb40c3944ffea32fd417ce3919c05588869996bdf920b341"
    ]
    private static let expectedMarkdownDigest: String? = "d62f74502dd21e584b9fed1f60df4d84cb8f9455f9c0732c98d977d065c2e1dc"
    private static let expectedLargeEditorDigest: String? = "d0a901600cdde21e974901a94fbf3eca7e3cb9c3f1f6e01e6205991fc81a938e"

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
            visualSnapshotFixtureSuite(),
            markdownPreviewSnapshotSuite(),
            cardStateSnapshotSuite(),
            slotStateSnapshotSuite(),
            groupMixedSnapshotSuite(),
            largeEditorSnapshotSuite(),
            keyboardSmokeSuite(),
            dragReorderSmokeSuite(),
            unplacedCardDragSmokeSuite(),
            singleCardMoveEdgeCaseSuite(),
            multiCardBlockMoveSuite(),
            boardThemeVariationSuite()
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

    private nonisolated static func visualSnapshotFixtureSuite() -> SuiteResult {
        let fixtures = BWRCardBuddyAcceptanceFixtureFactory.boardFixtures()
        let snapshots = fixtures.map(BWRCardBuddyAcceptanceFixtureFactory.boardSnapshot(for:))
        let actualIDs = snapshots.map(\.id)
        let expectedIDs = BWRCardBuddyAcceptanceFixtureFactory.expectedBoardFixtureIDs

        guard actualIDs == expectedIDs else {
            return fail(
                id: "visual-snapshot-fixtures",
                title: "Visual Snapshot Fixtures",
                summary: "Phase I visual snapshot fixture 세트가 계획한 card/slot/group 조합과 다릅니다.",
                details: [
                    "expected=\(expectedIDs.joined(separator: ","))",
                    "actual=\(actualIDs.joined(separator: ","))"
                ]
            )
        }

        if expectedBoardSnapshotDigests.count == expectedIDs.count {
            let actualDigests = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0.digest) })
            guard actualDigests == expectedBoardSnapshotDigests else {
                return fail(
                    id: "visual-snapshot-fixtures",
                    title: "Visual Snapshot Fixtures",
                    summary: "board visual snapshot digest가 Phase I 고정값과 다릅니다.",
                    details: expectedIDs.map { id in
                        "\(id)=expected:\(expectedBoardSnapshotDigests[id] ?? "nil") actual:\(actualDigests[id] ?? "nil")"
                    }
                )
            }
        }

        return pass(
            id: "visual-snapshot-fixtures",
            title: "Visual Snapshot Fixtures",
            summary: "existing visual snapshot host 위에 card/slot/group acceptance fixture가 모두 준비됐습니다.",
            details: snapshots.map { "\($0.id)=\($0.digest)" }
        )
    }

    private nonisolated static func markdownPreviewSnapshotSuite() -> SuiteResult {
        let snapshot = BWRCardBuddyAcceptanceFixtureFactory.markdownSnapshot()
        let expectedLines = [
            "Opening beat",
            "• Card Buddy shell",
            "• Paper surface",
            "Soft break",
            "next line"
        ]

        guard snapshot.visibleLines == expectedLines,
              snapshot.didTruncate,
              snapshot.containsStrongEmphasis,
              snapshot.containsListItems,
              snapshot.containsSoftBreaks else {
            return fail(
                id: "markdown-preview-snapshot",
                title: "Markdown Preview Snapshot",
                summary: "markdown preview snapshot이 Phase D/E 기준 5줄 grammar와 다릅니다.",
                details: [
                    "lines=\(snapshot.visibleLines)",
                    "didTruncate=\(snapshot.didTruncate)",
                    "strong=\(snapshot.containsStrongEmphasis)",
                    "list=\(snapshot.containsListItems)",
                    "softBreaks=\(snapshot.containsSoftBreaks)",
                    "digest=\(snapshot.digest)"
                ]
            )
        }

        if let expectedMarkdownDigest, snapshot.digest != expectedMarkdownDigest {
            return fail(
                id: "markdown-preview-snapshot",
                title: "Markdown Preview Snapshot",
                summary: "markdown preview digest가 Phase I 고정값과 다릅니다.",
                details: [
                    "expected=\(expectedMarkdownDigest)",
                    "actual=\(snapshot.digest)"
                ]
            )
        }

        return pass(
            id: "markdown-preview-snapshot",
            title: "Markdown Preview Snapshot",
            summary: "markdown preview가 bold/list/soft break를 유지한 5줄 snapshot으로 잠겼습니다.",
            details: [
                "lines=\(snapshot.visibleLines.joined(separator: " | "))",
                "digest=\(snapshot.digest)"
            ]
        )
    }

    private nonisolated static func cardStateSnapshotSuite() -> SuiteResult {
        let snapshotsByID = boardSnapshotsByID()
        guard let normal = snapshotsByID["card-normal"],
              let selected = snapshotsByID["card-selected"],
              let inline = snapshotsByID["card-inline"],
              let colored = snapshotsByID["card-colored"],
              let normalCard = normal.cards.first,
              let selectedCard = selected.cards.first(where: \.isSelected),
              let inlineCard = inline.cards.first(where: \.isInlineEditing),
              let coloredCard = colored.cards.first(where: \.isSelected) else {
            return fail(
                id: "card-state-snapshots",
                title: "Card State Snapshots",
                summary: "normal/selected/inline/colored card snapshot 중 일부를 만들지 못했습니다.",
                details: snapshotsByID.keys.sorted()
            )
        }

        let sizes = Set([
            rectSizeKey(normalCard.cardRect),
            rectSizeKey(selectedCard.cardRect),
            rectSizeKey(inlineCard.cardRect),
            rectSizeKey(coloredCard.cardRect)
        ])

        guard sizes.count == 1,
              !normalCard.isSelected,
              selectedCard.isSelected,
              inlineCard.showsLayerAffordance,
              !normalCard.showsLayerAffordance,
              !selectedCard.containsMetaText,
              !normalCard.containsMetaText,
              coloredCard.fillHex != "FFFFFF" else {
            return fail(
                id: "card-state-snapshots",
                title: "Card State Snapshots",
                summary: "card state snapshot이 고정 크기 / no-meta / editing-only affordance 규칙을 만족하지 않습니다.",
                details: [
                    "sizes=\(Array(sizes))",
                    "normalSelected=\(normalCard.isSelected)",
                    "selectedSelected=\(selectedCard.isSelected)",
                    "inlineFooter=\(inlineCard.footerElements)",
                    "coloredFill=\(coloredCard.fillHex)",
                    "digests=\(["card-normal", "card-selected", "card-inline", "card-colored"].compactMap { id in snapshotsByID[id].map { "\(id)=\($0.digest)" } }.joined(separator: ","))"
                ]
            )
        }

        return pass(
            id: "card-state-snapshots",
            title: "Card State Snapshots",
            summary: "normal/selected/inline/colored 상태에서 카드 크기는 고정이고 메타 텍스트 없이 editing affordance만 바뀝니다.",
            details: [
                "size=\(sizes.first ?? "unknown")",
                "selectedDigest=\(selected.digest)",
                "inlineDigest=\(inline.digest)",
                "coloredFill=\(coloredCard.fillHex)"
            ]
        )
    }

    private nonisolated static func slotStateSnapshotSuite() -> SuiteResult {
        let snapshotsByID = boardSnapshotsByID()
        guard let cursor = snapshotsByID["slot-cursor"]?.overlays.first,
              let hover = snapshotsByID["slot-hover"]?.overlays.first(where: { $0.role == BWRCardBuddyOverlayRole.hoverPlaceholder.rawValue }),
              let source = snapshotsByID["slot-drag-source"]?.overlays.first(where: { $0.role == BWRCardBuddyOverlayRole.dragSource.rawValue }),
              let destination = snapshotsByID["slot-drag-destination"]?.overlays.first(where: { $0.role == BWRCardBuddyOverlayRole.dragDestination.rawValue }),
              let empty = snapshotsByID["slot-empty-placeholder"]?.overlays.first else {
            return fail(
                id: "slot-state-snapshots",
                title: "Slot State Snapshots",
                summary: "cursor/hover/source/destination/empty placeholder snapshot 중 일부를 만들지 못했습니다.",
                details: snapshotsByID.keys.sorted()
            )
        }

        let descriptors = [cursor.descriptor, hover.descriptor, source.descriptor, destination.descriptor, empty.descriptor]
        guard Set(descriptors).count == 4,
              cursor.descriptor.contains("solid"),
              hover.descriptor.contains("dashed"),
              source.descriptor.contains("solid"),
              destination.descriptor.contains("dashed"),
              empty.targetsEmptySlot,
              hover.targetsEmptySlot == false else {
            return fail(
                id: "slot-state-snapshots",
                title: "Slot State Snapshots",
                summary: "slot state overlay snapshot이 서로 구분되지 않거나 empty placeholder를 제대로 가리키지 않습니다.",
                details: [
                    "cursor=\(cursor.descriptor)",
                    "hover=\(hover.descriptor) empty=\(hover.targetsEmptySlot)",
                    "source=\(source.descriptor)",
                    "destination=\(destination.descriptor)",
                    "empty=\(empty.descriptor) empty=\(empty.targetsEmptySlot)"
                ]
            )
        }

        return pass(
            id: "slot-state-snapshots",
            title: "Slot State Snapshots",
            summary: "keyboard cursor, hover, drag source, drag destination, empty placeholder가 서로 다른 snapshot grammar로 잠겼습니다.",
            details: [
                "cursor=\(cursor.descriptor)",
                "hover=\(hover.descriptor)",
                "source=\(source.descriptor)",
                "destination=\(destination.descriptor)",
                "emptyTargetsEmpty=\(empty.targetsEmptySlot)"
            ]
        )
    }

    private nonisolated static func groupMixedSnapshotSuite() -> SuiteResult {
        guard let snapshot = boardSnapshotsByID()["group-mixed"],
              let selectedGroup = snapshot.groups.first(where: \.isSelected),
              let unselectedGroup = snapshot.groups.first(where: { !$0.isSelected }),
              snapshot.cards.contains(where: { $0.hostID.hasPrefix("strip:") }) else {
            return fail(
                id: "group-mixed-snapshot",
                title: "Group Mixed Snapshot",
                summary: "group/non-group mixed snapshot에서 selected group 또는 strip card를 찾지 못했습니다.",
                details: []
            )
        }

        guard selectedGroup.strokeHex == BWRCardBuddyCardShell.selectionHex,
              selectedGroup.strokeWidth > unselectedGroup.strokeWidth,
              snapshot.groups.count == 2 else {
            return fail(
                id: "group-mixed-snapshot",
                title: "Group Mixed Snapshot",
                summary: "group mixed snapshot의 selected/unselected panel grammar가 Phase G 기준과 다릅니다.",
                details: [
                    "selectedStroke=\(selectedGroup.strokeHex) width=\(selectedGroup.strokeWidth)",
                    "unselectedStroke=\(unselectedGroup.strokeHex) width=\(unselectedGroup.strokeWidth)",
                    "digest=\(snapshot.digest)"
                ]
            )
        }

        return pass(
            id: "group-mixed-snapshot",
            title: "Group Mixed Snapshot",
            summary: "group panel과 parked card가 같은 보드에서 공존해도 selected card/group grammar가 분리되어 유지됩니다.",
            details: [
                "selectedGroup=\(selectedGroup.name)",
                "stripCardPresent=true",
                "digest=\(snapshot.digest)"
            ]
        )
    }

    private nonisolated static func largeEditorSnapshotSuite() -> SuiteResult {
        let snapshot = BWRCardBuddyAcceptanceFixtureFactory.largeEditorSnapshot()

        guard snapshot.showsDoneAction,
              snapshot.showsSplitAction,
              snapshot.showsLayerMenu,
              snapshot.showsColorMenu,
              snapshot.showsRenameAction,
              snapshot.bodyLayerCount == 2,
              snapshot.currentLayerKind == BWRLayerKind.body.rawValue,
              snapshot.paperCornerRadius == Double(BWRCardBuddyLargeEditorChrome.paperCornerRadius),
              snapshot.minimumEditorHeight == Double(BWRCardBuddyLargeEditorChrome.minimumEditorHeight) else {
            return fail(
                id: "large-editor-snapshot",
                title: "Large Editor Snapshot",
                summary: "large editor snapshot이 Done/Split/Layer/Color grammar 또는 paper layout 기준을 만족하지 않습니다.",
                details: [
                    "snapshot=\(snapshot)",
                    "digest=\(snapshot.digest)"
                ]
            )
        }

        if let expectedLargeEditorDigest, snapshot.digest != expectedLargeEditorDigest {
            return fail(
                id: "large-editor-snapshot",
                title: "Large Editor Snapshot",
                summary: "large editor digest가 Phase I 고정값과 다릅니다.",
                details: [
                    "expected=\(expectedLargeEditorDigest)",
                    "actual=\(snapshot.digest)"
                ]
            )
        }

        return pass(
            id: "large-editor-snapshot",
            title: "Large Editor Snapshot",
            summary: "large editor가 current layer 중심 paper editor와 Done/Split/Layer/Color action grammar로 잠겼습니다.",
            details: [
                "layers=\(snapshot.layerNames.joined(separator: ","))",
                "digest=\(snapshot.digest)"
            ]
        )
    }

    private nonisolated static func keyboardSmokeSuite() -> SuiteResult {
        let sequence = BWRCardBuddyAcceptanceFixtureFactory.keyboardSmokeReferences()
        let baseDocument = BWRCardBuddyAcceptanceFixtureFactory.boardFixtures()[0].document
        let orderedGroups = BWRBoardOrderResolver.orderedLiveGroups(document: baseDocument)
        guard orderedGroups.count >= 2 else {
            return fail(
                id: "keyboard-smoke",
                title: "Keyboard Smoke",
                summary: "keyboard smoke fixture의 group 수가 부족합니다.",
                details: []
            )
        }

        let expected = [
            "\(BWRCardBuddyAcceptanceFixtureFactory.hostID(.group(orderedGroups[0].id)))#0",
            "\(BWRCardBuddyAcceptanceFixtureFactory.hostID(.group(orderedGroups[0].id)))#1",
            "\(BWRCardBuddyAcceptanceFixtureFactory.hostID(.group(orderedGroups[0].id)))#2",
            "\(BWRCardBuddyAcceptanceFixtureFactory.hostID(.group(orderedGroups[1].id)))#2",
            "\(BWRCardBuddyAcceptanceFixtureFactory.hostID(.group(orderedGroups[1].id)))#1",
            "\(BWRCardBuddyAcceptanceFixtureFactory.hostID(.group(orderedGroups[0].id)))#1"
        ]
        let actual = sequence.map(referenceDescriptor)

        guard actual == expected else {
            return fail(
                id: "keyboard-smoke",
                title: "Keyboard Smoke",
                summary: "slot cursor keyboard smoke sequence가 고정 fixture와 다릅니다.",
                details: [
                    "expected=\(expected)",
                    "actual=\(actual)"
                ]
            )
        }

        return pass(
            id: "keyboard-smoke",
            title: "Keyboard Smoke",
            summary: "keyboard cursor가 group/empty-slot을 가로질러 같은 slot traversal grammar로 이동합니다.",
            details: actual
        )
    }

    private nonisolated static func dragReorderSmokeSuite() -> SuiteResult {
        let moveCase = BWRCardBuddyAcceptanceFixtureFactory.dragReorderFixture()
        let projection = BWRSlotBoardProjection.project(document: moveCase.document)
        guard let pointerRect = projection.placeholderRect(for: moveCase.targetHost, insertionIndex: moveCase.rawInsertionIndex),
              let leadCardID = moveCase.movingCardIDs.first,
              let target = BWRSlotBoardInteraction.resolveCardDropTarget(
                document: moveCase.document,
                projection: projection,
                draggingCardIDs: moveCase.movingCardIDs,
                leadCardID: leadCardID,
                pointer: CGPoint(x: pointerRect.midX, y: pointerRect.midY),
                viewportState: BWRViewportState()
              ) else {
            return fail(
                id: "drag-reorder-smoke",
                title: "Drag Reorder Smoke",
                summary: "drag reorder smoke fixture의 target resolution에 실패했습니다.",
                details: []
            )
        }

        let overlay = BWRSlotBoardInteraction.resolveDragOverlayState(
            document: moveCase.document,
            projection: projection,
            movingCardIDs: moveCase.movingCardIDs,
            target: target
        )
        let result = BWRCardBuddyAcceptanceFixtureFactory.moveResult(for: moveCase)

        guard overlay.sourceRects(in: projection).count == 1,
              overlay.destinationPlaceholders(in: projection).count == 1,
              result.hostsAfter == stringifyHosts(moveCase.expectedHosts),
              result.alignedCardIDs.count == moveCase.movingCardIDs.count else {
            return fail(
                id: "drag-reorder-smoke",
                title: "Drag Reorder Smoke",
                summary: "drag reorder smoke에서 source closing / target opening / slot alignment 중 일부가 깨졌습니다.",
                details: [
                    "sourceCount=\(overlay.sourceRects(in: projection).count)",
                    "destinationCount=\(overlay.destinationPlaceholders(in: projection).count)",
                    "expected=\(stringifyHosts(moveCase.expectedHosts))",
                    "actual=\(result.hostsAfter)",
                    "aligned=\(result.alignedCardIDs)",
                    "digest=\(result.digest)"
                ]
            )
        }

        return pass(
            id: "drag-reorder-smoke",
            title: "Drag Reorder Smoke",
            summary: "drag reorder smoke에서 source host closing, target host opening, moved card slot alignment가 함께 유지됩니다.",
            details: [
                "target=\(String(describing: target.destination))",
                "hostsAfter=\(result.hostsAfter)",
                "digest=\(result.digest)"
            ]
        )
    }

    private nonisolated static func unplacedCardDragSmokeSuite() -> SuiteResult {
        let document = BWRDocument.blank()
        guard let card = document.cards.first else {
            return fail(
                id: "unplaced-card-drag-smoke",
                title: "Unplaced Card Drag Smoke",
                summary: "blank document의 첫 카드를 찾지 못했습니다.",
                details: []
            )
        }

        let projection = BWRSlotBoardProjection.project(document: document)
        let fallbackOrigin = card.layout
        let anchorRect = BWRBoardCardDragResolution.anchorRect(
            projectedRect: projection.cardRect(for: card.id),
            fallbackOrigin: fallbackOrigin,
            cardSize: BWRSlotBoardGeometry.default.cardSize
        )
        guard anchorRect.width == BWRSlotBoardGeometry.default.cardSize.width,
              anchorRect.height == BWRSlotBoardGeometry.default.cardSize.height,
              let target = BWRSlotBoardInteraction.resolveCardDropTarget(
                document: document,
                projection: projection,
                draggingCardIDs: [card.id],
                leadCardID: card.id,
                pointer: CGPoint(x: anchorRect.midX + 24, y: anchorRect.midY + 24),
                viewportState: BWRViewportState()
              ) else {
            return fail(
                id: "unplaced-card-drag-smoke",
                title: "Unplaced Card Drag Smoke",
                summary: "projection 바깥 카드가 drag anchor fallback 또는 drop target을 만들지 못했습니다.",
                details: [
                    "projectedRect=\(String(describing: projection.cardRect(for: card.id)))",
                    "fallbackOrigin=\(fallbackOrigin)",
                    "anchorRect=\(anchorRect)"
                ]
            )
        }

        guard case let .newParkingStrip(originSlot, insertionIndex) = target.destination else {
            return fail(
                id: "unplaced-card-drag-smoke",
                title: "Unplaced Card Drag Smoke",
                summary: "blank document 카드 드래그가 새 parking strip detach로 해석되지 않았습니다.",
                details: [
                    "destination=\(String(describing: target.destination))"
                ]
            )
        }

        var mutated = document
        _ = BWRDocumentReducer.moveCardsToParkingStrip(
            document: &mutated,
            cardIDs: [card.id],
            originSlot: originSlot,
            insertionIndex: insertionIndex
        )
        mutated = BWRSlotPlacementNormalizer.repairedDocument(mutated)
        let repairedProjection = BWRSlotBoardProjection.project(document: mutated)

        guard repairedProjection.stripFrames.count == 1,
              repairedProjection.cardRect(for: card.id) != nil else {
            return fail(
                id: "unplaced-card-drag-smoke",
                title: "Unplaced Card Drag Smoke",
                summary: "blank document 카드가 drop 뒤 parking strip 위 실제 slot rect로 수렴하지 않았습니다.",
                details: [
                    "stripCount=\(repairedProjection.stripFrames.count)",
                    "projectedCardRect=\(String(describing: repairedProjection.cardRect(for: card.id)))"
                ]
            )
        }

        return pass(
            id: "unplaced-card-drag-smoke",
            title: "Unplaced Card Drag Smoke",
            summary: "projection 밖 첫 카드도 drag anchor fallback으로 드래그를 시작하고 parking strip slot으로 정상 수렴합니다.",
            details: [
                "anchorRect=\(anchorRect)",
                "destination=\(originSlot.column),\(originSlot.row)#\(insertionIndex)"
            ]
        )
    }

    private nonisolated static func singleCardMoveEdgeCaseSuite() -> SuiteResult {
        let results = BWRCardBuddyAcceptanceFixtureFactory.singleCardMoveFixtures().map(BWRCardBuddyAcceptanceFixtureFactory.moveResult(for:))
        let expected = Dictionary(uniqueKeysWithValues: BWRCardBuddyAcceptanceFixtureFactory.singleCardMoveFixtures().map { ($0.id, stringifyHosts($0.expectedHosts)) })

        let failures = results.compactMap { result -> String? in
            guard let expectedHosts = expected[result.id],
                  expectedHosts == result.hostsAfter,
                  result.alignedCardIDs.count == 1 else {
                return "\(result.id)=expected:\(expected[result.id] ?? [:]) actual:\(result.hostsAfter) aligned:\(result.alignedCardIDs)"
            }
            return nil
        }

        guard failures.isEmpty else {
            return fail(
                id: "single-card-edge-cases",
                title: "Single Card Move Edge Cases",
                summary: "front/back/middle single-card move 중 source host closing 또는 slot alignment가 깨진 케이스가 있습니다.",
                details: failures
            )
        }

        return pass(
            id: "single-card-edge-cases",
            title: "Single Card Move Edge Cases",
            summary: "맨 앞 카드, 맨 뒤 카드, 중간 삽입 케이스 모두 removal-first grammar로 source host가 닫히고 card가 slot rect에 정렬됩니다.",
            details: results.map { "\($0.id)=\($0.digest)" }
        )
    }

    private nonisolated static func multiCardBlockMoveSuite() -> SuiteResult {
        let moveCase = BWRCardBuddyAcceptanceFixtureFactory.multiCardMoveFixture()
        let result = BWRCardBuddyAcceptanceFixtureFactory.moveResult(for: moveCase)
        let expectedHosts = stringifyHosts(moveCase.expectedHosts)

        guard result.hostsAfter == expectedHosts,
              result.alignedCardIDs.count == moveCase.movingCardIDs.count,
              moveCase.movingCardIDs.map(\.uuidString) == Array(expectedHosts[result.targetHostID, default: []].dropFirst().prefix(moveCase.movingCardIDs.count)) else {
            return fail(
                id: "multi-card-block-move",
                title: "Multi Card Block Move",
                summary: "multi-card move에서 moving block 순서 유지 또는 contiguous insert 결과가 깨졌습니다.",
                details: [
                    "moving=\(moveCase.movingCardIDs.map(\.uuidString))",
                    "expected=\(expectedHosts)",
                    "actual=\(result.hostsAfter)",
                    "aligned=\(result.alignedCardIDs)"
                ]
            )
        }

        return pass(
            id: "multi-card-block-move",
            title: "Multi Card Block Move",
            summary: "multi-card block move 후 moving block 내부 순서가 유지되고 source host는 빈칸 없이 닫힙니다.",
            details: [
                "hostsAfter=\(result.hostsAfter)",
                "digest=\(result.digest)"
            ]
        )
    }

    private nonisolated static func boardThemeVariationSuite() -> SuiteResult {
        let snapshots = BWRCardBuddyAcceptanceFixtureFactory.boardThemeSnapshots()
        let digests = snapshots.map(\.digest)
        let unreadable = snapshots.compactMap { snapshot -> String? in
            guard let boardHex = snapshot.boardBackgroundHex else { return "\(snapshot.id)=missing" }
            return BWRCardBuddyBoardThemeGuardrail.isBoardSurfaceReadable(hex: boardHex) ? nil : "\(snapshot.id)=\(boardHex)"
        }

        guard snapshots.count == BWRCardBuddyBoardThemeGuardrail.boardSwatches.count,
              unreadable.isEmpty,
              Set(digests).count == snapshots.count else {
            return fail(
                id: "board-theme-variation",
                title: "Board Theme Variation",
                summary: "board theme variation harness가 swatch 수, readability, 또는 snapshot uniqueness를 만족하지 않습니다.",
                details: [
                    "count=\(snapshots.count)",
                    "unreadable=\(unreadable)",
                    "uniqueDigests=\(Set(digests).count)"
                ]
            )
        }

        return pass(
            id: "board-theme-variation",
            title: "Board Theme Variation",
            summary: "board surface swatch 전체에서 selection과 placeholder가 계속 읽히고 snapshot이 swatch별로 분리됩니다.",
            details: snapshots.map { "\($0.id)=\($0.boardBackgroundHex ?? "nil"):\($0.digest)" }
        )
    }

    private nonisolated static func boardSnapshotsByID() -> [String: BWRCardBuddyAcceptanceBoardSnapshot] {
        Dictionary(uniqueKeysWithValues: BWRCardBuddyAcceptanceFixtureFactory.boardFixtures().map { fixture in
            let snapshot = BWRCardBuddyAcceptanceFixtureFactory.boardSnapshot(for: fixture)
            return (snapshot.id, snapshot)
        })
    }

    private nonisolated static func rectSizeKey(_ rect: BWRBoardRectSnapshot) -> String {
        "\(Int(rect.width))x\(Int(rect.height))"
    }

    private nonisolated static func stringifyHosts(_ hosts: [String: [UUID]]) -> [String: [String]] {
        hosts.keys.sorted().reduce(into: [String: [String]]()) { partialResult, key in
            partialResult[key] = hosts[key, default: []].map(\.uuidString)
        }
    }

    private nonisolated static func referenceDescriptor(_ reference: BWRBoardSlotReference) -> String {
        "\(BWRCardBuddyAcceptanceFixtureFactory.hostID(reference.host))#\(reference.slotIndex)"
    }

    private nonisolated static func write(report: Report) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(report).write(to: reportJSONURL, options: .atomic)
        try? makeMarkdown(report: report).write(to: reportMarkdownURL, atomically: true, encoding: .utf8)
    }

    private nonisolated static func makeMarkdown(report: Report) -> String {
        var lines: [String] = []
        lines.append("# BWR Card Buddy Phase I Acceptance Harness")
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
