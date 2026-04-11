import Foundation

@MainActor
enum BWRMilestone1Harness {
    nonisolated static let reportJSONURL = URL(fileURLWithPath: "/tmp/bwr_m1_report.json")
    nonisolated static let reportMarkdownURL = URL(fileURLWithPath: "/tmp/bwr_m1_report.md")

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
    static func runAll() -> Bool {
        let suites = [
            packageRoundTripSuite(),
            placementSchemaSuite(),
            decodeFailureSuite(),
            viewportStateSuite(),
            archiveAndCloneSemanticsSuite(),
            documentAutosaveSuite()
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

    private static func packageRoundTripSuite() -> SuiteResult {
        let packageURL = temporaryPackageURL(prefix: "bwr-m1-roundtrip")
        defer {
            try? FileManager.default.removeItem(at: packageURL)
        }

        do {
            let original = fixtureDocument()
            let preparedOriginal = BWRShadowPlacementTransition.preparedForPersistence(document: original)
            try BWRPackageStore.fullWrite(document: original, to: packageURL)
            let restored = try BWRPackageStore.read(from: packageURL)
            guard documentsEquivalent(preparedOriginal, restored) else {
                return fail(
                    id: "package-roundtrip",
                    title: "Core Package Round-Trip",
                    summary: "BWR 패키지 round-trip 결과가 원본과 다릅니다.",
                    details: [
                        "package=\(packageURL.path)",
                        "preparedSchema=\(preparedOriginal.schemaVersion)",
                        "restoredSchema=\(restored.schemaVersion)"
                    ] + debugLines(for: preparedOriginal, prefix: "prepared") + debugLines(for: restored, prefix: "restored")
                )
            }

            let wrapper = try BWRPackageStore.fileWrapper(document: original, preferredFileName: "Harness.bwr")
            let wrapperRestored = try BWRPackageStore.read(from: wrapper)
            guard documentsEquivalent(preparedOriginal, wrapperRestored) else {
                return fail(
                    id: "package-roundtrip",
                    title: "Core Package Round-Trip",
                    summary: "FileWrapper 기반 round-trip 결과가 원본과 다릅니다.",
                    details: [
                        "preferredFilename=\(wrapper.preferredFilename ?? "nil")"
                    ]
                )
            }

            return pass(
                id: "package-roundtrip",
                title: "Core Package Round-Trip",
                summary: "full write/read와 FileWrapper round-trip이 모두 안정적으로 동작합니다.",
                details: [
                    "cards=\(preparedOriginal.cards.count)",
                    "groups=\(preparedOriginal.groups.count)",
                    "parkingStrips=\(preparedOriginal.parkingStrips.count)",
                    "archive=\(preparedOriginal.archive.count)"
                ]
            )
        } catch {
            return fail(
                id: "package-roundtrip",
                title: "Core Package Round-Trip",
                summary: "패키지 round-trip 중 예외가 발생했습니다.",
                details: [error.localizedDescription]
            )
        }
    }

    private static func placementSchemaSuite() -> SuiteResult {
        let packageURL = temporaryPackageURL(prefix: "bwr-m1-placement")
        defer {
            try? FileManager.default.removeItem(at: packageURL)
        }

        do {
            let original = transitionFixtureDocument()
            let preparedOriginal = BWRShadowPlacementTransition.preparedForPersistence(document: original)
            try BWRPackageStore.fullWrite(document: original, to: packageURL)
            let restored = try BWRPackageStore.read(from: packageURL)

            guard FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("parking-strips.json").path) else {
                return fail(
                    id: "placement-schema",
                    title: "Placement Schema",
                    summary: "parking-strips.json이 패키지에 저장되지 않았습니다.",
                    details: ["package=\(packageURL.path)"]
                )
            }

            let allCardsPlaced = restored.cards.allSatisfy { $0.placement != nil }
            let allGroupsAnchored = restored.groups.allSatisfy { $0.originSlot != nil }
            let stripOrderPreserved = restored.parkingStrips.first?.cardIDs == preparedOriginal.parkingStrips.first?.cardIDs
            guard allCardsPlaced, allGroupsAnchored, stripOrderPreserved else {
                return fail(
                    id: "placement-schema",
                    title: "Placement Schema",
                    summary: "placement/group origin/parking strip persisted state가 기대값과 다릅니다.",
                    details: [
                        "allCardsPlaced=\(allCardsPlaced)",
                        "allGroupsAnchored=\(allGroupsAnchored)",
                        "preparedStrip=\(preparedOriginal.parkingStrips.first?.cardIDs.map(\.uuidString).joined(separator: ",") ?? "nil")",
                        "restoredStrip=\(restored.parkingStrips.first?.cardIDs.map(\.uuidString).joined(separator: ",") ?? "nil")"
                    ]
                )
            }

            return pass(
                id: "placement-schema",
                title: "Placement Schema",
                summary: "R1 placement fields, group origin, parking strip 저장이 round-trip에서 유지됩니다.",
                details: [
                    "schemaVersion=\(restored.schemaVersion)",
                    "parkingStrips=\(restored.parkingStrips.count)",
                    "firstGroupOrigin=\(String(describing: restored.groups.first?.originSlot))"
                ]
            )
        } catch {
            return fail(
                id: "placement-schema",
                title: "Placement Schema",
                summary: "placement schema 검증 중 예외가 발생했습니다.",
                details: [error.localizedDescription]
            )
        }
    }

    private static func decodeFailureSuite() -> SuiteResult {
        let packageURL = temporaryPackageURL(prefix: "bwr-m1-corrupt")
        defer {
            try? FileManager.default.removeItem(at: packageURL)
        }

        do {
            let original = transitionFixtureDocument()
            try BWRPackageStore.fullWrite(document: original, to: packageURL)
            guard let targetCardID = original.cards.first?.id else {
                return fail(
                    id: "decode-failure",
                    title: "Decode Failure Path",
                    summary: "fixture 카드가 비어 있습니다.",
                    details: []
                )
            }

            let cardJSONURL = packageURL
                .appendingPathComponent("cards", isDirectory: true)
                .appendingPathComponent(targetCardID.uuidString, isDirectory: true)
                .appendingPathComponent("card.json")
            let corrupted = """
            {
              "id" : "\(targetCardID.uuidString)",
              "stableSortKey" : 1,
              "currentLayerID" : "00000000-0000-0000-0000-000000000000",
              "placement" : {
                "kind" : "attached",
                "hostGroupID" : null,
                "stripID" : null,
                "slotIndex" : 0
              },
              "layout" : {
                "x" : 0,
                "y" : 0
              },
              "isArchived" : false,
              "createdAt" : "2026-04-09T00:00:00Z",
              "updatedAt" : "2026-04-09T00:00:00Z",
              "layers" : [ ]
            }
            """
            try corrupted.write(to: cardJSONURL, atomically: true, encoding: .utf8)

            do {
                _ = try BWRPackageStore.read(from: packageURL)
                return fail(
                    id: "decode-failure",
                    title: "Decode Failure Path",
                    summary: "손상된 .bwr 패키지를 읽을 때 명시 에러가 발생하지 않았습니다.",
                    details: ["package=\(packageURL.path)"]
                )
            } catch let error as BWRPackageStoreError {
                return pass(
                    id: "decode-failure",
                    title: "Decode Failure Path",
                    summary: "손상된 placement/current layer 패키지가 명시적 package error로 실패합니다.",
                    details: [error.localizedDescription]
                )
            } catch {
                return fail(
                    id: "decode-failure",
                    title: "Decode Failure Path",
                    summary: "손상된 패키지가 package-specific error가 아닌 다른 예외로 실패했습니다.",
                    details: [error.localizedDescription]
                )
            }
        } catch {
            return fail(
                id: "decode-failure",
                title: "Decode Failure Path",
                summary: "decode failure suite 준비 중 예외가 발생했습니다.",
                details: [error.localizedDescription]
            )
        }
    }

    private static func viewportStateSuite() -> SuiteResult {
        let documentURL = temporaryPackageURL(prefix: "bwr-m1-viewport")
        let sceneA = "scene-a"
        let sceneB = "scene-b"
        let stateA = BWRViewportState(
            zoomScale: 1.25,
            scrollOrigin: BWRPoint(x: 180, y: 260),
            viewportSize: BWRSize(width: 1024, height: 768)
        )
        let stateB = BWRViewportState(
            zoomScale: 0.75,
            scrollOrigin: BWRPoint(x: 12, y: 34),
            viewportSize: BWRSize(width: 640, height: 480)
        )

        BWRViewportStateStore.save(stateA, documentURL: documentURL, sceneSessionID: sceneA)
        BWRViewportStateStore.save(stateB, documentURL: documentURL, sceneSessionID: sceneB)

        let restoredA = BWRViewportStateStore.load(documentURL: documentURL, sceneSessionID: sceneA)
        let restoredB = BWRViewportStateStore.load(documentURL: documentURL, sceneSessionID: sceneB)
        guard restoredA == stateA, restoredB == stateB else {
            return fail(
                id: "viewport",
                title: "Viewport Scene Store",
                summary: "scene별 viewport 상태가 독립적으로 복원되지 않았습니다.",
                details: [
                    "sceneA=\(restoredA)",
                    "sceneB=\(restoredB)"
                ]
            )
        }

        return pass(
            id: "viewport",
            title: "Viewport Scene Store",
            summary: "문서 URL + sceneSessionID 단위 viewport 저장이 분리되어 동작합니다.",
            details: [
                "sceneA.zoom=\(restoredA.zoomScale)",
                "sceneB.zoom=\(restoredB.zoomScale)"
            ]
        )
    }

    private static func archiveAndCloneSemanticsSuite() -> SuiteResult {
        var document = fixtureDocument()
        let targetGroupID = document.groups[0].id
        let sharedCardID = document.cards[0].id
        let orphanCardID = document.cards[1].id
        let removedCloneID = document.cards[2].id
        let survivingCloneID = document.cards[3].id

        let summary = BWRDocumentReducer.archiveGroup(document: &document, groupID: targetGroupID)
        let liveCardIDs = Set(document.cards.map(\.id))
        let searchHits = BWRDocumentSearch.search(document: document, query: "orphan", scope: .everything)

        guard document.groups[0].isArchived else {
            return fail(
                id: "archive-clone",
                title: "Archive And Clone Semantics",
                summary: "그룹이 아카이브되지 않았습니다.",
                details: ["groupID=\(targetGroupID.uuidString)"]
            )
        }

        guard liveCardIDs.contains(sharedCardID),
              let sharedCard = document.cards.first(where: { $0.id == sharedCardID }),
              !sharedCard.isArchived else {
            return fail(
                id: "archive-clone",
                title: "Archive And Clone Semantics",
                summary: "다른 live 그룹에도 속한 일반 카드가 살아남지 못했습니다.",
                details: ["sharedCardID=\(sharedCardID.uuidString)"]
            )
        }

        guard let orphanCard = document.cards.first(where: { $0.id == orphanCardID }),
              orphanCard.isArchived else {
            return fail(
                id: "archive-clone",
                title: "Archive And Clone Semantics",
                summary: "다른 live 그룹에 속하지 않은 일반 카드가 아카이브되지 않았습니다.",
                details: ["orphanCardID=\(orphanCardID.uuidString)"]
            )
        }

        guard !liveCardIDs.contains(removedCloneID),
              summary.removedCardIDs.contains(removedCloneID),
              let survivingClone = document.cards.first(where: { $0.id == survivingCloneID }),
              survivingClone.cloneGroupID == nil else {
            return fail(
                id: "archive-clone",
                title: "Archive And Clone Semantics",
                summary: "그룹 삭제 시 clone hard delete 또는 clone collapse 규칙이 어긋났습니다.",
                details: [
                    "removedCloneStillLive=\(liveCardIDs.contains(removedCloneID))",
                    "survivingCloneGroup=\(document.cards.first(where: { $0.id == survivingCloneID })?.cloneGroupID?.uuidString ?? "nil")"
                ]
            )
        }

        guard !document.groups[0].memberCardIDs.contains(removedCloneID),
              !document.groups[1].memberCardIDs.contains(removedCloneID) else {
            return fail(
                id: "archive-clone",
                title: "Archive And Clone Semantics",
                summary: "hard delete된 clone card가 그룹 membership에 남아 있습니다.",
                details: [
                    "groupA.members=\(document.groups[0].memberCardIDs.map { $0.uuidString }.joined(separator: ","))",
                    "groupB.members=\(document.groups[1].memberCardIDs.map { $0.uuidString }.joined(separator: ","))"
                ]
            )
        }

        guard searchHits.contains(where: { $0.entityID == orphanCardID && $0.isArchived }) else {
            return fail(
                id: "archive-clone",
                title: "Archive And Clone Semantics",
                summary: "아카이브된 카드가 검색 결과에 노출되지 않았습니다.",
                details: ["query=orphan"]
            )
        }

        return pass(
            id: "archive-clone",
            title: "Archive And Clone Semantics",
            summary: "그룹 삭제 시 일반 카드 아카이브, clone hard delete, archive search 규칙이 계획과 일치합니다.",
            details: [
                "changedCards=\(summary.changedCardIDs.count)",
                "removedCards=\(summary.removedCardIDs.count)",
                "archiveHits=\(searchHits.count)"
            ]
        )
    }

    private static func documentAutosaveSuite() -> SuiteResult {
        let packageURL = temporaryPackageURL(prefix: "bwr-m1-autosave")
        defer {
            try? FileManager.default.removeItem(at: packageURL)
        }

        do {
            let referenceDocument = BWRReferenceDocument(document: fixtureDocument())
            referenceDocument.attach(fileURL: packageURL)
            guard let card = referenceDocument.liveCards.first,
                  let layer = card.currentLayer else {
                return fail(
                    id: "autosave",
                    title: "Reference Document Autosave",
                    summary: "fixture 문서의 첫 카드 또는 현재 레이어를 찾지 못했습니다.",
                    details: []
                )
            }

            referenceDocument.applyLayerMarkdown(
                cardID: card.id,
                layerID: layer.id,
                markdown: "Autosave proof\n\nMilestone 1"
            )
            referenceDocument.forceFullSaveNow()

            guard waitUntil(timeout: 2.0, condition: {
                FileManager.default.fileExists(atPath: packageURL.path)
                    && referenceDocument.autosaveStatus.contains("complete")
            }) else {
                return fail(
                    id: "autosave",
                    title: "Reference Document Autosave",
                    summary: "ReferenceFileDocument autosave가 제한 시간 안에 완료되지 않았습니다.",
                    details: ["status=\(referenceDocument.autosaveStatus)"]
                )
            }

            let restored = try BWRPackageStore.read(from: packageURL)
            let restoredText = restored.cards
                .first(where: { $0.id == card.id })?
                .layers
                .first(where: { $0.id == layer.id })?
                .markdown

            guard restoredText == "Autosave proof\n\nMilestone 1" else {
                return fail(
                    id: "autosave",
                    title: "Reference Document Autosave",
                    summary: "autosave 후 저장된 레이어 텍스트가 기대값과 다릅니다.",
                    details: ["restoredText=\(restoredText ?? "nil")"]
                )
            }

            return pass(
                id: "autosave",
                title: "Reference Document Autosave",
                summary: "ReferenceFileDocument + debounce/autosave 경로가 실제 .bwr 패키지로 저장됩니다.",
                details: [
                    "status=\(referenceDocument.autosaveStatus)",
                    "package=\(packageURL.path)"
                ]
            )
        } catch {
            return fail(
                id: "autosave",
                title: "Reference Document Autosave",
                summary: "ReferenceFileDocument autosave 검증 중 예외가 발생했습니다.",
                details: [error.localizedDescription]
            )
        }
    }

    private static func fixtureDocument() -> BWRDocument {
        let now = Date(timeIntervalSince1970: 1_000)

        let sharedLayers = BWRCard.defaultLayers(
            bodyMarkdown: "Shared body",
            treatmentMarkdown: "Shared treatment",
            scenarioMarkdown: "Shared scenario"
        )
        let orphanLayers = BWRCard.defaultLayers(
            bodyMarkdown: "Orphan body",
            treatmentMarkdown: "Orphan treatment",
            scenarioMarkdown: "Orphan scenario"
        )
        let cloneALayers = BWRCard.defaultLayers(bodyMarkdown: "Clone A")
        let cloneBLayers = BWRCard.defaultLayers(bodyMarkdown: "Clone B")
        let cloneGroupID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!

        let sharedCard = BWRCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            stableSortKey: 1,
            currentLayerID: sharedLayers[0].id,
            layout: BWRPoint(x: 20, y: 20),
            createdAt: now,
            updatedAt: now,
            layers: sharedLayers
        )
        let orphanCard = BWRCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            stableSortKey: 2,
            currentLayerID: orphanLayers[0].id,
            layout: BWRPoint(x: 240, y: 20),
            createdAt: now,
            updatedAt: now,
            layers: orphanLayers
        )
        let cloneA = BWRCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            stableSortKey: 3,
            cloneGroupID: cloneGroupID,
            currentLayerID: cloneALayers[0].id,
            layout: BWRPoint(x: 460, y: 20),
            createdAt: now,
            updatedAt: now,
            layers: cloneALayers
        )
        let cloneB = BWRCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            stableSortKey: 4,
            cloneGroupID: cloneGroupID,
            currentLayerID: cloneBLayers[0].id,
            layout: BWRPoint(x: 680, y: 20),
            createdAt: now,
            updatedAt: now,
            layers: cloneBLayers
        )

        let groupA = BWRGroup(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            name: "Group A",
            memberCardIDs: [sharedCard.id, orphanCard.id, cloneA.id],
            createdAt: now,
            updatedAt: now
        )
        let groupB = BWRGroup(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            name: "Group B",
            memberCardIDs: [sharedCard.id, cloneB.id],
            createdAt: now,
            updatedAt: now
        )

        return BWRDocument(
            schemaVersion: 2,
            createdAt: now,
            updatedAt: now,
            nextStableSortKey: 5,
            cards: [sharedCard, orphanCard, cloneA, cloneB],
            groups: [groupA, groupB]
        )
    }

    private static func transitionFixtureDocument() -> BWRDocument {
        let now = Date(timeIntervalSince1970: 2_000)
        let groupedLayers = BWRCard.defaultLayers(bodyMarkdown: "Grouped card")
        let parkedLayers = BWRCard.defaultLayers(bodyMarkdown: "Parked card")

        let groupedCard = BWRCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            stableSortKey: 1,
            currentLayerID: groupedLayers[0].id,
            layout: BWRPoint(x: 80, y: 60),
            createdAt: now,
            updatedAt: now,
            layers: groupedLayers
        )
        let parkedCard = BWRCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
            stableSortKey: 2,
            currentLayerID: parkedLayers[0].id,
            layout: BWRPoint(x: 520, y: 420),
            createdAt: now,
            updatedAt: now,
            layers: parkedLayers
        )
        let group = BWRGroup(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000299")!,
            name: "Placement Group",
            memberCardIDs: [groupedCard.id],
            createdAt: now,
            updatedAt: now
        )

        return BWRDocument(
            schemaVersion: 2,
            createdAt: now,
            updatedAt: now,
            nextStableSortKey: 3,
            cards: [groupedCard, parkedCard],
            groups: [group]
        )
    }

    private static func documentsEquivalent(_ lhs: BWRDocument, _ rhs: BWRDocument) -> Bool {
        BWRShadowPlacementTransition.preparedForPersistence(document: lhs) ==
            BWRShadowPlacementTransition.preparedForPersistence(document: rhs)
    }

    private static func debugLines(for document: BWRDocument, prefix: String) -> [String] {
        let stripSummary = document.parkingStrips.map { strip in
            [
                strip.id.uuidString,
                String(strip.row),
                String(strip.anchorColumn),
                strip.cardIDs.map(\.uuidString).joined(separator: ",")
            ].joined(separator: ":")
        }.joined(separator: " | ")

        let groupSummary = document.groups.map { group in
            let origin = group.originSlot.map { "\($0.column),\($0.row)" } ?? "nil"
            return [
                group.id.uuidString,
                origin,
                group.memberCardIDs.map(\.uuidString).joined(separator: ",")
            ].joined(separator: ":")
        }.joined(separator: " | ")

        let cardSummary = document.cards.map { card in
            let placement: String
            if let placementValue = card.placement {
                switch placementValue.kind {
                case .attached:
                    placement = "attached:\(placementValue.hostGroupID?.uuidString ?? "nil"):\(placementValue.slotIndex)"
                case .parked:
                    placement = "parked:\(placementValue.stripID?.uuidString ?? "nil"):\(placementValue.slotIndex)"
                }
            } else {
                placement = "nil"
            }
            return "\(card.id.uuidString):\(placement):\(card.layout.x),\(card.layout.y)"
        }.joined(separator: " | ")

        return [
            "\(prefix).parkingStrips=\(stripSummary)",
            "\(prefix).groups=\(groupSummary)",
            "\(prefix).cards=\(cardSummary)"
        ]
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

    private static func write(report: Report) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            try encoder.encode(report).write(to: reportJSONURL, options: .atomic)
        } catch {
            let fallback = """
            {"error":"failed to encode BWR M1 report","message":"\(error.localizedDescription)"}
            """
            try? fallback.write(to: reportJSONURL, atomically: true, encoding: .utf8)
        }

        try? makeMarkdown(report: report).write(to: reportMarkdownURL, atomically: true, encoding: .utf8)
    }

    private static func makeMarkdown(report: Report) -> String {
        var lines: [String] = []
        lines.append("# BWR Milestone 1 Report")
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
            for detail in suite.details {
                lines.append("- \(detail)")
            }
            lines.append("")
        }

        lines.append("## Paths")
        lines.append("")
        lines.append("- reportJSON: \(reportJSONURL.path)")
        lines.append("- reportMarkdown: \(reportMarkdownURL.path)")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func pass(id: String, title: String, summary: String, details: [String]) -> SuiteResult {
        SuiteResult(id: id, title: title, status: .pass, summary: summary, details: details)
    }

    private static func fail(id: String, title: String, summary: String, details: [String]) -> SuiteResult {
        SuiteResult(id: id, title: title, status: .fail, summary: summary, details: details)
    }
}
