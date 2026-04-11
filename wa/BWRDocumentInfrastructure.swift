import SwiftUI
import UniformTypeIdentifiers
import Combine

nonisolated struct BWRLayerMarkdownChange: Equatable, Sendable {
    var cardID: UUID
    var layerID: UUID
    var markdown: String
}

extension UTType {
    nonisolated static var bwrProject: UTType {
        UTType(exportedAs: "com.boardwriter.bwr", conformingTo: .package)
    }
}

nonisolated enum BWRViewportStateStore {
    private static let keyPrefix = "bwr.viewport."
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private static let decoder = JSONDecoder()

    static func load(documentURL: URL?, sceneSessionID: String) -> BWRViewportState {
        guard let documentURL else { return BWRViewportState() }
        let key = storageKey(documentURL: documentURL, sceneSessionID: sceneSessionID)
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? decoder.decode(BWRViewportState.self, from: data) else {
            return BWRViewportState()
        }
        return state
    }

    static func save(_ state: BWRViewportState, documentURL: URL?, sceneSessionID: String) {
        guard let documentURL else { return }
        let key = storageKey(documentURL: documentURL, sceneSessionID: sceneSessionID)
        guard let data = try? encoder.encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func storageKey(documentURL: URL, sceneSessionID: String) -> String {
        keyPrefix + documentURL.standardizedFileURL.path + "|" + sceneSessionID
    }
}

@MainActor
final class BWRReferenceDocument: @preconcurrency ReferenceFileDocument, ObservableObject {
    nonisolated static var readableContentTypes: [UTType] { [.bwrProject] }
    typealias Snapshot = BWRDocument

    @Published private(set) var document: BWRDocument
    @Published private(set) var autosaveStatus: String = "Autosave idle"

    private weak var undoManager: UndoManager?
    private var boundFileURL: URL?
    private var pendingMutationSummary = BWRMutationSummary()
    private var autosaveWorkItem: DispatchWorkItem?
    private let autosaveDelay: TimeInterval = 0.55

    init(document: BWRDocument = .blank()) {
        self.document = BWRSlotPlacementNormalizer.repairedDocument(document)
    }

    required init(configuration: ReadConfiguration) throws {
        self.document = try BWRPackageStore.read(from: configuration.file)
    }

    func snapshot(contentType: UTType) throws -> BWRDocument {
        document
    }

    func fileWrapper(snapshot: BWRDocument, configuration: WriteConfiguration) throws -> FileWrapper {
        try BWRPackageStore.fileWrapper(
            document: snapshot,
            preferredFileName: boundFileURL?.lastPathComponent ?? "Untitled.bwr"
        )
    }

    func attach(fileURL: URL?) {
        boundFileURL = fileURL
        if pendingMutationSummary.hasChanges {
            scheduleAutosave()
        }
    }

    func bindUndoManager(_ undoManager: UndoManager?) {
        self.undoManager = undoManager
    }

    var displayName: String {
        boundFileURL?.lastPathComponent ?? "Untitled.bwr"
    }

    var displayPath: String {
        boundFileURL?.path ?? "Unsaved document"
    }

    var liveCards: [BWRCard] {
        BWRBoardOrderResolver.orderedLiveCards(document: document, includeParked: true)
    }

    var archivedCards: [BWRCard] {
        BWRSlotOrder.orderedArchivedCards(in: document)
    }

    var liveGroups: [BWRGroup] {
        BWRBoardOrderResolver.orderedLiveGroups(document: document)
    }

    var archivedGroups: [BWRGroup] {
        document.groups.filter(\.isArchived).sorted { lhs, rhs in
            let left = lhs.archivedAt ?? lhs.updatedAt
            let right = rhs.archivedAt ?? rhs.updatedAt
            if left != right { return left > right }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    var liveLinks: [BWRLink] {
        document.links.filter { !$0.isArchived }
    }

    var archivedLinks: [BWRLink] {
        document.links.filter(\.isArchived)
    }

    func orderedLiveCards(inGroup groupID: UUID) -> [BWRCard] {
        BWRBoardOrderResolver.orderedCards(inGroup: groupID, document: document)
    }

    func liveLinks(touching cardID: UUID) -> [BWRLink] {
        liveLinks.filter { $0.sourceCardID == cardID || $0.destinationCardID == cardID }
    }

    func createCard() {
        mutate(actionName: "Create Card") { document in
            let cardID = BWRDocumentReducer.createCard(document: &document)
            return BWRMutationSummary(changedCardIDs: [cardID], metadataChanged: true)
        }
    }

    @discardableResult
    func createCard(at layout: BWRPoint) -> UUID? {
        var createdCardID: UUID?
        mutate(actionName: "Create Card") { document in
            let cardID = BWRDocumentReducer.createCard(document: &document, layout: layout)
            createdCardID = cardID
            return BWRMutationSummary(changedCardIDs: [cardID], metadataChanged: true)
        }
        return createdCardID
    }

    @discardableResult
    func createCard(
        selectedCardID: UUID?,
        selectedGroupID: UUID?,
        viewportState: BWRViewportState
    ) -> UUID? {
        var createdCardID: UUID?
        mutate(actionName: "Create Card") { document in
            let cardID = BWRDocumentReducer.createCard(document: &document)
            createdCardID = cardID

            var summary = BWRMutationSummary(changedCardIDs: [cardID], metadataChanged: true)
            if let target = BWRSelectionPrecedenceResolver.targetForCreateCard(
                document: document,
                selectedCardID: selectedCardID,
                selectedGroupID: selectedGroupID,
                viewportState: viewportState
            ) {
                switch target.host {
                case let .group(groupID):
                    summary.merge(
                        BWRDocumentReducer.attachCards(
                            document: &document,
                            toGroup: groupID,
                            cardIDs: [cardID],
                            insertionIndex: target.insertionIndex
                        )
                    )
                case let .strip(stripID):
                    summary.merge(
                        BWRDocumentReducer.reorderCards(
                            document: &document,
                            host: .strip(stripID),
                            cardIDs: [cardID],
                            insertionIndex: target.insertionIndex
                        )
                    )
                }
            }
            return summary
        }
        return createdCardID
    }

    @discardableResult
    func createCard(in host: BWRSlotHost, insertionIndex: Int) -> UUID? {
        var createdCardID: UUID?
        mutate(actionName: "Create Card") { document in
            let cardID = BWRDocumentReducer.createCard(document: &document)
            createdCardID = cardID
            var summary = BWRMutationSummary(changedCardIDs: [cardID], metadataChanged: true)
            summary.merge(
                BWRDocumentReducer.moveCards(
                    document: &document,
                    to: host,
                    cardIDs: [cardID],
                    insertionIndex: insertionIndex
                )
            )
            return summary
        }
        return createdCardID
    }

    @discardableResult
    func createGroup(name: String, memberCardIDs: [UUID]) -> UUID? {
        var createdGroupID: UUID?
        mutate(actionName: "Create Group") { document in
            guard let groupID = BWRDocumentReducer.createGroup(document: &document, name: name, memberCardIDs: memberCardIDs) else {
                return .init()
            }
            createdGroupID = groupID
            return BWRMutationSummary(metadataChanged: true)
        }
        return createdGroupID
    }

    func renameGroup(groupID: UUID, newName: String) {
        mutate(actionName: "Rename Group") { document in
            BWRDocumentReducer.renameGroup(document: &document, groupID: groupID, newName: newName)
        }
    }

    func addCards(toGroup groupID: UUID, cardIDs: [UUID]) {
        mutate(actionName: "Add To Group") { document in
            BWRDocumentReducer.attachCards(
                document: &document,
                toGroup: groupID,
                cardIDs: cardIDs,
                insertionIndex: nil
            )
        }
    }

    func removeCards(fromGroup groupID: UUID, cardIDs: [UUID]) {
        mutate(actionName: "Remove From Group") { document in
            BWRDocumentReducer.detachCards(
                document: &document,
                fromGroup: groupID,
                cardIDs: cardIDs,
                preferredStripID: nil,
                insertionIndex: nil
            )
        }
    }

    func moveCards(to host: BWRSlotHost, cardIDs: [UUID], insertionIndex: Int) {
        mutate(actionName: "Move Cards") { document in
            BWRDocumentReducer.moveCards(
                document: &document,
                to: host,
                cardIDs: cardIDs,
                insertionIndex: insertionIndex
            )
        }
    }

    func moveCardsToParkingStrip(cardIDs: [UUID], originSlot: BWRSlotCoordinate, insertionIndex: Int) {
        mutate(actionName: "Move Cards") { document in
            BWRDocumentReducer.moveCardsToParkingStrip(
                document: &document,
                cardIDs: cardIDs,
                originSlot: originSlot,
                insertionIndex: insertionIndex
            )
        }
    }

    func moveGroupOrigin(groupID: UUID, originSlot: BWRSlotCoordinate) {
        mutate(actionName: "Move Group") { document in
            BWRDocumentReducer.moveGroupOrigin(
                document: &document,
                groupID: groupID,
                originSlot: originSlot
            )
        }
    }

    func setCardLayouts(_ layoutsByCardID: [UUID: BWRPoint]) {
        mutate(actionName: "Move Cards") { document in
            BWRDocumentReducer.setCardLayouts(document: &document, layoutsByCardID: layoutsByCardID)
        }
    }

    func appendBodyLayer(cardID: UUID) {
        mutate(actionName: "Add Body Layer") { document in
            BWRDocumentReducer.appendBodyLayer(document: &document, cardID: cardID)
        }
    }

    func renameLayer(cardID: UUID, layerID: UUID, newName: String) {
        mutate(actionName: "Rename Layer") { document in
            BWRDocumentReducer.renameLayer(document: &document, cardID: cardID, layerID: layerID, newName: newName)
        }
    }

    func deleteBodyLayer(cardID: UUID, layerID: UUID) {
        mutate(actionName: "Delete Body Layer") { document in
            BWRDocumentReducer.deleteBodyLayer(document: &document, cardID: cardID, layerID: layerID)
        }
    }

    func moveBodyLayer(cardID: UUID, layerID: UUID, destinationBodyIndex: Int) {
        mutate(actionName: "Move Body Layer") { document in
            BWRDocumentReducer.moveBodyLayer(
                document: &document,
                cardID: cardID,
                layerID: layerID,
                destinationBodyIndex: destinationBodyIndex
            )
        }
    }

    func setCurrentLayer(cardID: UUID, layerID: UUID) {
        mutate(actionName: "Set Current Layer") { document in
            BWRDocumentReducer.setCurrentLayer(document: &document, cardID: cardID, layerID: layerID)
        }
    }

    func setCurrentLayerMatchingSelection(cardIDs: Set<UUID>, sourceCardID: UUID, sourceLayerID: UUID) {
        guard let sourceCard = document.cards.first(where: { $0.id == sourceCardID }),
              let sourceLayer = sourceCard.layers.first(where: { $0.id == sourceLayerID }) else {
            return
        }

        mutate(actionName: "Set Current Layer") { document in
            BWRDocumentReducer.setCurrentLayerMatchingSignature(
                document: &document,
                cardIDs: cardIDs,
                signature: BWRLayerSignature(layer: sourceLayer)
            )
        }
    }

    func cycleLayers(cardIDs: Set<UUID>, direction: Int) {
        mutate(actionName: "Cycle Layer") { document in
            BWRDocumentReducer.cycleCurrentLayer(document: &document, cardIDs: cardIDs, direction: direction)
        }
    }

    func applyLayerMarkdown(cardID: UUID, layerID: UUID, markdown: String, registerUndo: Bool = true) {
        applyLayerMarkdownChanges(
            [BWRLayerMarkdownChange(cardID: cardID, layerID: layerID, markdown: markdown)],
            registerUndo: registerUndo
        )
    }

    func applyLayerMarkdownChanges(_ changes: [BWRLayerMarkdownChange], registerUndo: Bool = true) {
        guard !changes.isEmpty else { return }
        mutate(actionName: "Edit Layer Text", shouldRegisterUndo: registerUndo) { document in
            var summary = BWRMutationSummary()
            for change in changes {
                var recursionGuard = BWRCloneRecursionGuard()
                summary.merge(
                    BWRDocumentReducer.updateLayerMarkdown(
                        document: &document,
                        cardID: change.cardID,
                        layerID: change.layerID,
                        markdown: change.markdown,
                        recursionGuard: &recursionGuard
                    )
                )
            }
            return summary
        }
    }

    func applyCardColor(cardID: UUID, colorHex: String?) {
        mutate(actionName: "Change Card Color") { document in
            var recursionGuard = BWRCloneRecursionGuard()
            return BWRDocumentReducer.updateCardColor(
                document: &document,
                cardID: cardID,
                colorHex: colorHex,
                recursionGuard: &recursionGuard
            )
        }
    }

    func applyCardColor(cardIDs: Set<UUID>, colorHex: String?) {
        guard !cardIDs.isEmpty else { return }
        mutate(actionName: "Change Card Color") { document in
            var summary = BWRMutationSummary()
            for cardID in cardIDs {
                var recursionGuard = BWRCloneRecursionGuard()
                summary.merge(
                    BWRDocumentReducer.updateCardColor(
                        document: &document,
                        cardID: cardID,
                        colorHex: colorHex,
                        recursionGuard: &recursionGuard
                    )
                )
            }
            return summary
        }
    }

    func updateBoardTheme(backgroundHex: String?, accentMode: BWRBoardAccentMode) {
        mutate(actionName: "Change Board Surface") { document in
            let sanitizedHex = BWRCardBuddyBoardThemeGuardrail.normalizedHex(backgroundHex)
            let nextTheme = BWRBoardThemeState(
                boardBackgroundHex: sanitizedHex,
                boardAccentMode: accentMode
            )
            guard document.boardTheme != nextTheme else { return .init() }
            document.boardTheme = nextTheme
            document.updatedAt = Date()
            return BWRMutationSummary(metadataChanged: true)
        }
    }

    @discardableResult
    func splitCard(cardID: UUID, atUTF16Location location: Int) -> UUID? {
        splitCard(cardID: cardID, layerID: nil, committedMarkdown: nil, atUTF16Location: location)
    }

    @discardableResult
    func splitCard(
        cardID: UUID,
        layerID: UUID?,
        committedMarkdown: String?,
        atUTF16Location location: Int
    ) -> UUID? {
        var createdCardID: UUID?
        let resolvedLayerID = layerID ?? document.cards.first(where: { $0.id == cardID })?.currentLayerID
        let beforeSplitSnapshot: BWRDocument = {
            guard let committedMarkdown,
                  let card = document.cards.first(where: { $0.id == cardID }) else {
                return document
            }

            let effectiveLayerID = resolvedLayerID ?? card.currentLayerID
            guard let sourceLayer = card.layers.first(where: { $0.id == effectiveLayerID }),
                  sourceLayer.markdown != committedMarkdown else {
                return document
            }

            var prepared = document
            var recursionGuard = BWRCloneRecursionGuard()
            _ = BWRDocumentReducer.updateLayerMarkdown(
                document: &prepared,
                cardID: cardID,
                layerID: effectiveLayerID,
                markdown: committedMarkdown,
                recursionGuard: &recursionGuard
            )
            return prepared
        }()

        var workingDocument = beforeSplitSnapshot
        guard let result = BWRDocumentReducer.splitCard(
            document: &workingDocument,
            cardID: cardID,
            layerID: resolvedLayerID,
            atUTF16Location: location
        ) else {
            return nil
        }
        createdCardID = result.newCardID
        workingDocument = BWRSlotPlacementNormalizer.repairedDocument(workingDocument)

        registerUndo(previousDocument: beforeSplitSnapshot, actionName: "Split Card")
        document = workingDocument
        pendingMutationSummary.merge(result.summary)
        scheduleAutosave()
        return createdCardID
    }

    func archiveCard(cardID: UUID) {
        mutate(actionName: "Archive Card") { document in
            BWRDocumentReducer.archiveCard(document: &document, cardID: cardID)
        }
    }

    func deleteCards(cardIDs: Set<UUID>) {
        guard !cardIDs.isEmpty else { return }
        mutate(actionName: "Delete Cards") { document in
            var summary = BWRMutationSummary()
            for cardID in cardIDs {
                summary.merge(BWRDocumentReducer.deleteCard(document: &document, cardID: cardID))
            }
            return summary
        }
    }

    func restoreCard(cardID: UUID) {
        mutate(actionName: "Restore Card") { document in
            BWRDocumentReducer.restoreCard(document: &document, cardID: cardID)
        }
    }

    func archiveGroup(groupID: UUID) {
        mutate(actionName: "Archive Group") { document in
            BWRDocumentReducer.archiveGroup(document: &document, groupID: groupID)
        }
    }

    func createLink(sourceCardID: UUID, destinationCardID: UUID) {
        mutate(actionName: "Create Link") { document in
            BWRDocumentReducer.createLink(
                document: &document,
                sourceCardID: sourceCardID,
                destinationCardID: destinationCardID
            )
        }
    }

    func archiveLink(linkID: UUID) {
        mutate(actionName: "Archive Link") { document in
            BWRDocumentReducer.archiveLink(document: &document, linkID: linkID)
        }
    }

    func restoreLink(linkID: UUID) {
        mutate(actionName: "Restore Link") { document in
            BWRDocumentReducer.restoreLink(document: &document, linkID: linkID)
        }
    }

    func restoreGroup(groupID: UUID) {
        mutate(actionName: "Restore Group") { document in
            BWRDocumentReducer.restoreGroup(document: &document, groupID: groupID)
        }
    }

    func search(query: String, scope: BWRSearchScope) -> [BWRSearchHit] {
        BWRDocumentSearch.search(document: document, query: query, scope: scope)
    }

    func saveNow() {
        autosaveWorkItem?.cancel()
        flushAutosave(forceFullWrite: false)
    }

    func forceFullSaveNow() {
        autosaveWorkItem?.cancel()
        flushAutosave(forceFullWrite: true)
    }

    private func mutate(
        actionName: String,
        shouldRegisterUndo: Bool = true,
        _ change: (inout BWRDocument) -> BWRMutationSummary
    ) {
        let previousDocument = document
        var workingDocument = document
        let summary = change(&workingDocument)
        guard summary.hasChanges else { return }
        workingDocument = BWRSlotPlacementNormalizer.repairedDocument(workingDocument)

        if shouldRegisterUndo {
            registerUndo(previousDocument: previousDocument, actionName: actionName)
        }
        document = workingDocument
        pendingMutationSummary.merge(summary)
        scheduleAutosave()
    }

    private func registerUndo(previousDocument: BWRDocument, actionName: String) {
        undoManager?.registerUndo(withTarget: self) { target in
            target.restoreDocumentSnapshot(previousDocument, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    private func restoreDocumentSnapshot(_ snapshot: BWRDocument, actionName: String) {
        let redoDocument = document
        undoManager?.registerUndo(withTarget: self) { target in
            target.restoreDocumentSnapshot(redoDocument, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        document = BWRSlotPlacementNormalizer.repairedDocument(snapshot)
        pendingMutationSummary = BWRMutationSummary(
            changedCardIDs: Set(snapshot.cards.map(\.id)),
            metadataChanged: true
        )
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        autosaveWorkItem?.cancel()
        guard boundFileURL != nil else {
            autosaveStatus = "Autosave waiting for file URL"
            return
        }

        autosaveStatus = "Autosave scheduled"
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.flushAutosave(forceFullWrite: false)
            }
        }
        autosaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + autosaveDelay, execute: workItem)
    }

    private func flushAutosave(forceFullWrite: Bool) {
        guard let boundFileURL else { return }
        guard pendingMutationSummary.hasChanges || forceFullWrite else {
            autosaveStatus = "Autosave idle"
            return
        }

        let mutationSummary = pendingMutationSummary
        let documentSnapshot = document
        pendingMutationSummary = .init()
        autosaveStatus = "Autosaving…"

        Task.detached(priority: .utility) {
            do {
                if forceFullWrite || mutationSummary.metadataChanged || !FileManager.default.fileExists(atPath: boundFileURL.path) {
                    try BWRPackageStore.fullWrite(document: documentSnapshot, to: boundFileURL)
                } else {
                    try BWRPackageStore.deltaWrite(
                        document: documentSnapshot,
                        to: boundFileURL,
                        changedCardIDs: mutationSummary.changedCardIDs,
                        removedCardIDs: mutationSummary.removedCardIDs
                    )
                }
                await MainActor.run {
                    self.autosaveStatus = "Autosave complete"
                }
            } catch {
                await MainActor.run {
                    self.pendingMutationSummary.merge(mutationSummary)
                    self.autosaveStatus = "Autosave failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
