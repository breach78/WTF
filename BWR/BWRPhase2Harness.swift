import Foundation

enum BWRPhase2Harness {
    @discardableResult
    static func runAll() -> Bool {
        let results = [
            memoryModelCRUDCheck(),
            persistenceCRUDCheck(),
            multiLayerRoundTripCheck()
        ]

        for result in results {
            let marker = result.success ? "PASS" : "FAIL"
            print("[BWR Phase 2] \(marker) \(result.title) - \(result.detail)")
        }

        return results.allSatisfy(\.success)
    }

    private static func memoryModelCRUDCheck() -> Phase2HarnessResult {
        var project = BWRHarnessFixtures.singleLayerProject()
        let initialCardCount = project.cards.count
        let initialContentCount = project.contents.count

        guard let createdCardID = project.insertCard(at: BoardSlot(row: 0, column: 1)) else {
            return Phase2HarnessResult(title: "Memory Model CRUD", success: false, detail: "insertCard returned nil")
        }

        project.updatePresentedMarkdown(id: createdCardID, markdown: "## Edited\nCreated in memory")
        project.moveCard(id: createdCardID, to: BoardSlot(row: 2, column: 3))
        project.deleteCard(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)

        let createdCard = project.presentedCard(id: createdCardID)
        let deletedCardMissing = project.presentedCard(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!) == nil
        let success =
            project.cards.count == initialCardCount &&
            project.contents.count == initialContentCount &&
            createdCard?.slot == BoardSlot(row: 2, column: 3) &&
            createdCard?.markdown == "## Edited\nCreated in memory" &&
            deletedCardMissing

        return Phase2HarnessResult(
            title: "Memory Model CRUD",
            success: success,
            detail: success ? "create, update, move, delete all mutate the new card/content/layer model" : "memory model mutation mismatch"
        )
    }

    private static func persistenceCRUDCheck() -> Phase2HarnessResult {
        let url = BWRHarnessFixtures.temporaryPackageURL(prefix: "bwr-phase2-crud")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            var project = BWRHarnessFixtures.singleLayerProject()
            guard let createdCardID = project.insertCard(at: BoardSlot(row: 0, column: 1)) else {
                return Phase2HarnessResult(title: "Persistence CRUD", success: false, detail: "insertCard returned nil")
            }

            project.updatePresentedMarkdown(id: createdCardID, markdown: "## Persisted\nPhase 2 CRUD")
            project.moveCard(id: createdCardID, to: BoardSlot(row: 3, column: 4))
            project.deleteCard(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)

            try BWRDocument(project: project).writePackage(to: url)
            let restored = try BWRDocument.open(from: url).project
            let createdCard = restored.presentedCard(id: createdCardID)
            let deletedCardMissing = restored.presentedCard(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!) == nil

            let success =
                restored == project &&
                createdCard?.slot == BoardSlot(row: 3, column: 4) &&
                createdCard?.markdown == "## Persisted\nPhase 2 CRUD" &&
                deletedCardMissing

            return Phase2HarnessResult(
                title: "Persistence CRUD",
                success: success,
                detail: success
                    ? "create, update, move, delete persist through SQLite round-trip"
                    : "SQLite CRUD round-trip mismatch: originalCards=\(project.cards.count) restoredCards=\(restored.cards.count) originalContents=\(project.contents.count) restoredContents=\(restored.contents.count) createdSlot=\(String(describing: createdCard?.slot)) createdMarkdown=\(createdCard?.markdown ?? "nil") deletedCardMissing=\(deletedCardMissing)"
            )
        } catch {
            return Phase2HarnessResult(title: "Persistence CRUD", success: false, detail: error.localizedDescription)
        }
    }

    private static func multiLayerRoundTripCheck() -> Phase2HarnessResult {
        let url = BWRHarnessFixtures.temporaryPackageURL(prefix: "bwr-phase2-layers")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let original = BWRHarnessFixtures.multiLayerProject()
            try BWRDocument(project: original).writePackage(to: url)
            let restored = try BWRDocument.open(from: url).project

            guard
                let card = restored.presentedCards.first,
                let content = restored.contents[card.instance.contentID]
            else {
                return Phase2HarnessResult(title: "Multi-Layer Round Trip", success: false, detail: "missing restored card or content")
            }

            let success =
                restored == original &&
                content.layers.count == 2 &&
                card.presentedLayer.id == UUID(uuidString: "33333333-3333-3333-3333-333333333333")! &&
                card.markdown.contains("Layer one is presented")

            return Phase2HarnessResult(
                title: "Multi-Layer Round Trip",
                success: success,
                detail: success
                    ? "content/layer model and presentedLayer survive SQLite reopen"
                    : "multi-layer reopen mismatch: restoredLayers=\(content.layers.count) presentedLayer=\(card.presentedLayer.id.uuidString) markdown=\(card.markdown)"
            )
        } catch {
            return Phase2HarnessResult(title: "Multi-Layer Round Trip", success: false, detail: error.localizedDescription)
        }
    }
}

private struct Phase2HarnessResult {
    let title: String
    let success: Bool
    let detail: String
}
