import AppKit
import Foundation

enum BWRPhase6Harness {
    @discardableResult
    static func runAll() -> Bool {
        let results = [
            searchAndGoToCheck(),
            searchNavigationCheck(),
            softDeleteRestoreCheck(),
            deleteTargetPriorityCheck(),
            lineEditingCheck(),
            escapePriorityCheck(),
            assetRoundTripAndThumbnailRefreshCheck()
        ]

        for result in results {
            let marker = result.success ? "PASS" : "FAIL"
            print("[BWR Phase 6] \(marker) \(result.title) - \(result.detail)")
        }

        return results.allSatisfy(\.success)
    }

    private static func searchAndGoToCheck() -> Phase6HarnessResult {
        var project = BWRHarnessFixtures.multiLayerProject()
        var interaction = BoardInteractionState()

        guard
            let card = project.presentedCards.first,
            let hiddenLayer = project.contents[card.instance.contentID]?.layers.first(where: { $0.id != card.presentedLayer.id })
        else {
            return Phase6HarnessResult(title: "Search And Go To", success: false, detail: "fixture missing hidden layer")
        }

        let results = project.searchResults(for: "Layer zero")
        guard let firstResult = results.first else {
            return Phase6HarnessResult(title: "Search And Go To", success: false, detail: "search returned no results")
        }

        let applied = BoardGoToController.apply(
            result: firstResult,
            project: &project,
            interaction: &interaction
        )
        let revealedLayerID = project.presentedCard(id: card.id)?.presentedLayer.id
        let success =
            firstResult.layerID == hiddenLayer.id &&
            applied &&
            revealedLayerID == hiddenLayer.id &&
            interaction.selectedCardID == card.id &&
            interaction.keyboardCursorSlot == card.slot

        return Phase6HarnessResult(
            title: "Search And Go To",
            success: success,
            detail: success
                ? "search sees non-presented layers and Go To reveals the matched layer while moving cursor and selection"
                : "resultLayer=\(firstResult.layerID.uuidString) revealed=\(String(describing: revealedLayerID?.uuidString)) cursor=\(String(describing: interaction.keyboardCursorSlot))"
        )
    }

    private static func softDeleteRestoreCheck() -> Phase6HarnessResult {
        let ids = (
            a: UUID(uuidString: "81000000-0000-0000-0000-000000000001")!,
            b: UUID(uuidString: "81000000-0000-0000-0000-000000000002")!,
            c: UUID(uuidString: "81000000-0000-0000-0000-000000000003")!
        )
        var project = BoardProject.singleLayer(
            seeds: [
                .init(
                    cardID: ids.a,
                    contentID: UUID(uuidString: "82000000-0000-0000-0000-000000000001")!,
                    layerID: UUID(uuidString: "83000000-0000-0000-0000-000000000001")!,
                    slot: BoardSlot(row: 0, column: 0),
                    markdown: "A"
                ),
                .init(
                    cardID: ids.b,
                    contentID: UUID(uuidString: "82000000-0000-0000-0000-000000000002")!,
                    layerID: UUID(uuidString: "83000000-0000-0000-0000-000000000002")!,
                    slot: BoardSlot(row: 0, column: 1),
                    markdown: "B"
                ),
                .init(
                    cardID: ids.c,
                    contentID: UUID(uuidString: "82000000-0000-0000-0000-000000000003")!,
                    layerID: UUID(uuidString: "83000000-0000-0000-0000-000000000003")!,
                    slot: BoardSlot(row: 0, column: 2),
                    markdown: "C"
                )
            ]
        )

        let deletedIDs = project.softDeleteCards(ids: Set([ids.b]))
        guard deletedIDs == Set([ids.b]) else {
            return Phase6HarnessResult(title: "Soft Delete Restore", success: false, detail: "soft delete did not tombstone target card")
        }

        let postDeleteCompactionPass =
            project.presentedCard(id: ids.a)?.slot == BoardSlot(row: 0, column: 0) &&
            project.presentedCard(id: ids.c)?.slot == BoardSlot(row: 0, column: 1)
        let restored = project.restoreLatestDeletedCard()
        let success =
            postDeleteCompactionPass &&
            restored?.cardID == ids.b &&
            restored?.slot == BoardSlot(row: 0, column: 1) &&
            project.presentedCard(id: ids.b)?.slot == BoardSlot(row: 0, column: 1) &&
            project.presentedCard(id: ids.c)?.slot == BoardSlot(row: 0, column: 2) &&
            project.deletedCards.isEmpty

        return Phase6HarnessResult(
            title: "Soft Delete Restore",
            success: success,
            detail: success
                ? "soft delete compacts the row to the left and restore reinserts the tombstoned card at its original column"
                : "postDeleteCompactionPass=\(postDeleteCompactionPass) restored=\(String(describing: restored)) a=\(String(describing: project.presentedCard(id: ids.a)?.slot)) b=\(String(describing: project.presentedCard(id: ids.b)?.slot)) c=\(String(describing: project.presentedCard(id: ids.c)?.slot)) deletedCount=\(project.deletedCards.count)"
        )
    }

    private static func deleteTargetPriorityCheck() -> Phase6HarnessResult {
        let cursorCardID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let project = BWRHarnessFixtures.singleLayerProject()

        let explicitEmptyInteraction = BoardInteractionState(
            keyboardCursorSlot: .origin,
            selection: .slot(BoardSlot(row: 0, column: 1)),
            selectionAnchorSlot: BoardSlot(row: 0, column: 1)
        )
        let explicitCardInteraction = BoardInteractionState(
            keyboardCursorSlot: BoardSlot(row: 1, column: 2),
            selection: .card(cursorCardID),
            selectionAnchorSlot: .origin
        )
        let cursorFallbackInteraction = BoardInteractionState(
            keyboardCursorSlot: .origin
        )

        let explicitEmptyTargets = BoardDeleteController.targetCardIDs(
            project: project,
            interaction: explicitEmptyInteraction
        )
        let explicitCardTargets = BoardDeleteController.targetCardIDs(
            project: project,
            interaction: explicitCardInteraction
        )
        let cursorFallbackTargets = BoardDeleteController.targetCardIDs(
            project: project,
            interaction: cursorFallbackInteraction
        )

        let success =
            explicitEmptyTargets.isEmpty &&
            explicitCardTargets == Set([cursorCardID]) &&
            cursorFallbackTargets == Set([cursorCardID])

        return Phase6HarnessResult(
            title: "Delete Target Priority",
            success: success,
            detail: success
                ? "delete respects explicit empty-slot selection, explicit card selection, and cursor fallback in that order"
                : "empty=\(explicitEmptyTargets.count) explicitCard=\(explicitCardTargets.count) cursorFallback=\(cursorFallbackTargets.count)"
        )
    }

    private static func lineEditingCheck() -> Phase6HarnessResult {
        var project = BoardProject.singleLayer(
            seeds: [
                .init(
                    cardID: UUID(uuidString: "70000000-0000-0000-0000-000000000001")!,
                    contentID: UUID(uuidString: "71000000-0000-0000-0000-000000000001")!,
                    layerID: UUID(uuidString: "72000000-0000-0000-0000-000000000001")!,
                    slot: BoardSlot(row: 0, column: 0),
                    markdown: "Top"
                ),
                .init(
                    cardID: UUID(uuidString: "70000000-0000-0000-0000-000000000002")!,
                    contentID: UUID(uuidString: "71000000-0000-0000-0000-000000000002")!,
                    layerID: UUID(uuidString: "72000000-0000-0000-0000-000000000002")!,
                    slot: BoardSlot(row: 1, column: 1),
                    markdown: "Middle"
                ),
                .init(
                    cardID: UUID(uuidString: "70000000-0000-0000-0000-000000000003")!,
                    contentID: UUID(uuidString: "71000000-0000-0000-0000-000000000003")!,
                    layerID: UUID(uuidString: "72000000-0000-0000-0000-000000000003")!,
                    slot: BoardSlot(row: 2, column: 0),
                    markdown: "Bottom"
                )
            ]
        )
        var interaction = BoardInteractionState(
            keyboardCursorSlot: BoardSlot(row: 2, column: 0),
            hoverSlot: BoardSlot(row: 1, column: 1),
            selection: .slot(BoardSlot(row: 1, column: 1)),
            selectionAnchorSlot: BoardSlot(row: 1, column: 1)
        )

        _ = project.applyLineEdit(axis: .row, operation: .insert, at: 1)
        interaction.remapSlots(for: .row, operation: .insert, at: 1)

        let deletedIDs = project.applyLineEdit(axis: .column, operation: .delete, at: 0)
        interaction.remapSlots(for: .column, operation: .delete, at: 0)
        BoardStructureSelectionController.normalize(
            project: project,
            interaction: &interaction,
            deletedCardIDs: deletedIDs,
            fallbackSlot: BoardSlot(row: 2, column: 0)
        )

        let middleCardID = UUID(uuidString: "70000000-0000-0000-0000-000000000002")!
        let success =
            deletedIDs.count == 2 &&
            project.presentedCard(id: middleCardID)?.slot == BoardSlot(row: 2, column: 0) &&
            interaction.keyboardCursorSlot == BoardSlot(row: 3, column: 0) &&
            interaction.hoverSlot == BoardSlot(row: 2, column: 0) &&
            interaction.selectedCardID == middleCardID &&
            interaction.selectedEmptySlot == nil

        return Phase6HarnessResult(
            title: "Row And Column Editing",
            success: success,
            detail: success
                ? "line edits shift active cards, tombstone deleted-line cards, and normalize slot selection away from occupied slots"
                : "deletedIDs=\(deletedIDs.count) middleSlot=\(String(describing: project.presentedCard(id: middleCardID)?.slot)) cursor=\(String(describing: interaction.keyboardCursorSlot)) hover=\(String(describing: interaction.hoverSlot)) selectedCard=\(String(describing: interaction.selectedCardID)) selectedSlot=\(String(describing: interaction.selectedEmptySlot))"
        )
    }

    private static func searchNavigationCheck() -> Phase6HarnessResult {
        var project = BWRHarnessFixtures.multiLayerProject()
        var interaction = BoardInteractionState()
        let results = project.searchResults(for: "Layer")
        guard results.count == 2 else {
            return Phase6HarnessResult(title: "Search Navigation", success: false, detail: "expected two ordered hits")
        }

        guard
            let secondIndex = BoardSearchNavigator.advancedIndex(current: 0, count: results.count, reverse: false),
            let wrappedIndex = BoardSearchNavigator.advancedIndex(current: secondIndex, count: results.count, reverse: false),
            let previousIndex = BoardSearchNavigator.advancedIndex(current: 0, count: results.count, reverse: true)
        else {
            return Phase6HarnessResult(title: "Search Navigation", success: false, detail: "navigator failed to compute indexes")
        }

        _ = BoardGoToController.apply(
            result: results[secondIndex],
            project: &project,
            interaction: &interaction
        )
        let secondLayerID = project.presentedCard(id: results[secondIndex].cardID)?.presentedLayer.id

        let success =
            secondIndex == 1 &&
            wrappedIndex == 0 &&
            previousIndex == 1 &&
            secondLayerID == results[secondIndex].layerID &&
            interaction.selectedCardID == results[secondIndex].cardID

        return Phase6HarnessResult(
            title: "Search Navigation",
            success: success,
            detail: success
                ? "search results advance and wrap in logical order while Go To follows the active hit"
                : "secondIndex=\(secondIndex) wrappedIndex=\(wrappedIndex) previousIndex=\(previousIndex) revealed=\(String(describing: secondLayerID?.uuidString))"
        )
    }

    private static func escapePriorityCheck() -> Phase6HarnessResult {
        let cardID = UUID(uuidString: "90000000-0000-0000-0000-000000000001")!
        let editingOutcome = BoardEscapeController.outcome(
            interaction: BoardInteractionState(
                keyboardCursorSlot: .origin,
                selection: .card(cardID),
                selectionAnchorSlot: .origin,
                editingCardID: cardID
            ),
            transientGestureState: BoardTransientGestureState(
                hasDragSession: true,
                hasMarqueeSelection: true
            )
        )
        let gestureOutcome = BoardEscapeController.outcome(
            interaction: BoardInteractionState(
                keyboardCursorSlot: .origin,
                selection: .card(cardID),
                selectionAnchorSlot: .origin
            ),
            transientGestureState: BoardTransientGestureState(hasDragSession: true)
        )
        let selectionOutcome = BoardEscapeController.outcome(
            interaction: BoardInteractionState(
                keyboardCursorSlot: .origin,
                selection: .card(cardID),
                selectionAnchorSlot: .origin
            ),
            transientGestureState: BoardTransientGestureState()
        )
        let noneOutcome = BoardEscapeController.outcome(
            interaction: BoardInteractionState(keyboardCursorSlot: .origin),
            transientGestureState: BoardTransientGestureState()
        )

        let success =
            editingOutcome == .cancelEditing &&
            gestureOutcome == .cancelTransientGesture &&
            selectionOutcome == .clearSelection &&
            noneOutcome == .none

        return Phase6HarnessResult(
            title: "Escape Priority",
            success: success,
            detail: success
                ? "escape unwinds editing first, then transient gestures, then selection"
                : "editing=\(editingOutcome) gesture=\(gestureOutcome) selection=\(selectionOutcome) none=\(noneOutcome)"
        )
    }

    private static func assetRoundTripAndThumbnailRefreshCheck() -> Phase6HarnessResult {
        let cardID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let url = BWRHarnessFixtures.temporaryPackageURL(prefix: "bwr-phase6")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        do {
            var document = BWRDocument(project: BWRHarnessFixtures.singleLayerProject())
            let assetData = try samplePNGData()
            let assetID = document.project.attachAsset(
                data: assetData,
                originalFilename: "sample.png",
                contentType: "image/png",
                toPresentedLayerOf: cardID
            )
            guard
                let assetID,
                let storedFilename = document.project.assets[assetID]?.storedFilename
            else {
                return Phase6HarnessResult(title: "Asset Round Trip And Thumbnail", success: false, detail: "asset attach failed")
            }

            try document.writePackage(to: url)
            let assetURL = url
                .appendingPathComponent(BWRSQLitePackageStore.assetsDirectoryName, isDirectory: true)
                .appendingPathComponent(storedFilename, isDirectory: false)
            let thumbnailURL = url.appendingPathComponent(BWRSQLitePackageStore.thumbnailFilename, isDirectory: false)
            let firstThumbnail = try Data(contentsOf: thumbnailURL)

            _ = document.project.softDeleteCards(ids: Set([cardID]))
            try document.writePackage(to: url)
            let secondThumbnail = try Data(contentsOf: thumbnailURL)
            let restored = try BWRDocument.open(from: url)

            let success =
                FileManager.default.fileExists(atPath: assetURL.path) &&
                firstThumbnail != secondThumbnail &&
                restored.project.assets[assetID]?.data == assetData &&
                restored.project.contents.values.contains { content in
                    content.layers.contains { $0.assetID == assetID }
                }

            return Phase6HarnessResult(
                title: "Asset Round Trip And Thumbnail",
                success: success,
                detail: success
                    ? "image assets persist into assets/, reopen with layer linkage intact, and thumbnail.jpg refreshes after document changes"
                    : "assetExists=\(FileManager.default.fileExists(atPath: assetURL.path)) thumbChanged=\(firstThumbnail != secondThumbnail) restoredAsset=\(restored.project.assets[assetID] != nil)"
            )
        } catch {
            return Phase6HarnessResult(
                title: "Asset Round Trip And Thumbnail",
                success: false,
                detail: error.localizedDescription
            )
        }
    }

    private static func samplePNGData() throws -> Data {
        let image = NSImage(size: CGSize(width: 24, height: 24))
        image.lockFocus()
        NSColor(calibratedRed: 0.94, green: 0.62, blue: 0.34, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: 24, height: 24)).fill()
        NSColor(calibratedRed: 0.26, green: 0.36, blue: 0.62, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: 5, y: 5, width: 14, height: 14)).fill()
        image.unlockFocus()

        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.coderInvalidValue)
        }

        return data
    }
}

private struct Phase6HarnessResult {
    let title: String
    let success: Bool
    let detail: String
}
