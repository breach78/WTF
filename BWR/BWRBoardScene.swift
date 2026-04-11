import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct BoardEditingSnapshot: Equatable {
    let cardID: UUID
    let markdown: String
}

struct BWRWorkspaceView: View {
    @Binding var document: BWRDocument
    let fileURL: URL?

    @State private var searchText = ""
    @State private var searchResultIndex = 0
    @State private var interaction = BoardInteractionState()
    @State private var transientGestureState = BoardTransientGestureState()
    @State private var gestureCancellationToken = 0
    @State private var showsSlotGuides = false
    @State private var canvasTone: BoardCanvasTone = .sand
    @State private var scaleStep = 1
    @State private var showsHelp = false
    @State private var showsAssetImporter = false
    @State private var importErrorMessage: String?
    @State private var editingSnapshot: BoardEditingSnapshot?

    private let scaleValues: [CGFloat] = [0.94, 1.0, 1.08]

    private var matchingIDs: Set<UUID> {
        document.project.matchingCardIDs(for: searchText)
    }

    private var searchResults: [BoardSearchResult] {
        document.project.searchResults(for: searchText)
    }

    private var activeSearchResultIndex: Int? {
        BoardSearchNavigator.normalizedIndex(searchResultIndex, count: searchResults.count)
    }

    private var selectedCardID: UUID? {
        document.project.selectedCardID(for: interaction)
    }

    private var selectedCard: BoardPresentedCard? {
        document.project.presentedCard(id: selectedCardID)
    }

    private var selectedSlot: BoardSlot? {
        selectedCard?.slot ?? document.project.selectedEmptySlot(for: interaction)
    }

    private var activeScale: CGFloat {
        scaleValues[scaleStep]
    }

    private var structureReferenceSlot: BoardSlot {
        selectedSlot ?? interaction.keyboardCursorSlot ?? .origin
    }

    private var deleteTargetCardIDs: Set<UUID> {
        BoardDeleteController.targetCardIDs(
            project: document.project,
            interaction: interaction
        )
    }

    var body: some View {
        NavigationStack {
            BWRBoardCanvasView(
                project: document.project,
                searchMatches: matchingIDs,
                interaction: $interaction,
                transientGestureState: $transientGestureState,
                showsSlotGuides: showsSlotGuides,
                canvasTone: canvasTone,
                cardScale: activeScale,
                gestureCancellationToken: gestureCancellationToken,
                noteBinding: noteBinding(for:),
                assetForCard: { cardID in
                    document.project.presentedAsset(for: cardID)
                },
                onOpenCardForEditing: openCardForEditing(_:),
                onCreateCard: createCard(at:),
                onCycleTint: cyclePalette(for:),
                onCommitEditing: stopEditing,
                onCancelEditing: cancelEditing,
                onAdvanceEditing: advanceEditing(reverse:),
                onApplyDrag: applyDrag(_:)
            )
            .background(canvasTone.windowFill.ignoresSafeArea())
            .background(
                BWRBoardKeyboardMonitor(
                    isEnabled: interaction.editingCardID == nil,
                    onKeyEvent: handleBoardKeyEvent(_:)
                )
            )
            .toolbar {
                ToolbarItem(placement: .principal) {
                    BWRToolbarSearchField(
                        text: $searchText,
                        resultCount: searchResults.count,
                        activeResultIndex: activeSearchResultIndex,
                        onSubmit: goToCurrentSearchResult,
                        onPreviousResult: goToPreviousSearchResult,
                        onNextResult: goToNextSearchResult
                    )
                }

                ToolbarItemGroup(placement: .automatic) {
                    BWRCircleToolbarButton(systemName: "textformat.size") {
                        cycleScale()
                    }
                    .help("Cycle card size")

                    BWRCircleToolbarButton(systemName: "paintbrush.pointed") {
                        cycleCanvasTone()
                    }
                    .help("Cycle board tone")

                    BWRCircleToolbarButton(
                        systemName: showsSlotGuides ? "square.grid.3x3.fill" : "square.grid.3x3"
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showsSlotGuides.toggle()
                        }
                    }
                    .help("Toggle slot guides")

                    BWRCircleToolbarButton(systemName: "doc.badge.plus") {
                        createCard(at: selectedSlot)
                    }
                    .help("Create card")

                    BWRCircleToolbarButton(systemName: "location.viewfinder") {
                        goToCurrentSearchResult()
                    }
                    .disabled(searchResults.isEmpty)
                    .help("Go to current search result")

                    BWRCircleToolbarButton(systemName: "arrow.uturn.backward.circle") {
                        restoreLatestDeletedCard()
                    }
                    .disabled(!document.project.hasDeletedCards)
                    .help("Restore latest deleted card")

                    BWRCircleToolbarButton(systemName: "trash") {
                        softDeleteSelection()
                    }
                    .disabled(deleteTargetCardIDs.isEmpty)
                    .help("Soft delete selected card")

                    BWRCircleToolbarMenu(systemName: "paperclip") {
                        Button("Attach Image") {
                            showsAssetImporter = true
                        }
                        .disabled(selectedCardID == nil)

                        Button("Remove Asset") {
                            removeAssetFromSelectedCard()
                        }
                        .disabled(document.project.presentedAsset(for: selectedCardID ?? UUID()) == nil)
                    }
                    .help("Attach or remove an image asset")

                    BWRCircleToolbarMenu(systemName: "rectangle.3.group") {
                        Button("Insert Row Before") {
                            applyLineEdit(axis: .row, operation: .insert, at: structureReferenceSlot.row)
                        }
                        Button("Insert Row After") {
                            applyLineEdit(axis: .row, operation: .insert, at: structureReferenceSlot.row + 1)
                        }
                        Button("Delete Current Row") {
                            applyLineEdit(axis: .row, operation: .delete, at: structureReferenceSlot.row)
                        }
                        Divider()
                        Button("Insert Column Before") {
                            applyLineEdit(axis: .column, operation: .insert, at: structureReferenceSlot.column)
                        }
                        Button("Insert Column After") {
                            applyLineEdit(axis: .column, operation: .insert, at: structureReferenceSlot.column + 1)
                        }
                        Button("Delete Current Column") {
                            applyLineEdit(axis: .column, operation: .delete, at: structureReferenceSlot.column)
                        }
                    }
                    .help("Insert or delete rows and columns")

                    BWRCircleToolbarButton(
                        systemName: interaction.editingCardID == nil ? "square.and.pencil" : "checkmark.circle"
                    ) {
                        toggleInlineEditing()
                    }
                    .disabled(selectedCardID == nil)
                    .help("Edit selected card inline")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                BWRFloatingHelpButton(showsHelp: $showsHelp)
                    .padding(18)
            }
            .popover(isPresented: $showsHelp, arrowEdge: .bottom) {
                BWRHelpPopover()
            }
            .onAppear {
                seedInteractionIfNeeded()
            }
            .task(id: fileURL) {
                rememberCurrentDocumentIfNeeded()
            }
            .onChange(of: searchText) { _, _ in
                searchResultIndex = 0
            }
            .onChange(of: searchResults) { _, newValue in
                searchResultIndex = BoardSearchNavigator.normalizedIndex(
                    searchResultIndex,
                    count: newValue.count
                ) ?? 0
            }
            .onDeleteCommand {
                softDeleteSelection()
            }
            .fileImporter(
                isPresented: $showsAssetImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                handleAssetImport(result)
            }
            .alert("Couldn’t Import Asset", isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        importErrorMessage = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importErrorMessage ?? "Unknown import error.")
            }
        }
    }

    private func noteBinding(for cardID: UUID) -> Binding<String>? {
        guard document.project.presentedCard(id: cardID) != nil else {
            return nil
        }

        return Binding(
            get: { document.project.presentedMarkdown(for: cardID) ?? "" },
            set: { newValue in
                document.project.updatePresentedMarkdown(id: cardID, markdown: newValue)
            }
        )
    }

    private func seedInteractionIfNeeded() {
        interaction.seedKeyboardCursor(ifNeeded: document.project.liveCards.first?.slot)
        guard interaction.selection == .none, let firstCard = document.project.liveCards.first else {
            return
        }

        interaction.selectCard(firstCard.id, at: firstCard.slot)
    }

    private func openCardForEditing(_ cardID: UUID) {
        if let slot = document.project.presentedCard(id: cardID)?.slot {
            interaction.selectCard(cardID, at: slot)
            interaction.keyboardCursorSlot = slot
        } else {
            interaction.selectCard(cardID)
        }
        beginEditing(cardID)
    }

    private func createCard(at slot: BoardSlot?) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            guard let cardID = document.project.insertCard(at: slot) else {
                return
            }

            if let createdSlot = document.project.presentedCard(id: cardID)?.slot {
                interaction.selectCard(cardID, at: createdSlot)
                interaction.keyboardCursorSlot = createdSlot
            } else {
                interaction.selectCard(cardID)
            }
            beginEditing(cardID)
        }
    }

    private func applyDrag(_ session: BoardDragSession) {
        _ = BoardDragController.apply(
            project: &document.project,
            interaction: &interaction,
            session: session
        )
    }

    private func cyclePalette(for cardID: UUID) {
        withAnimation(.easeInOut(duration: 0.18)) {
            document.project.cyclePalette(id: cardID)
        }
    }

    private func softDeleteSelection() {
        let targetIDs = deleteTargetCardIDs
        guard !targetIDs.isEmpty else {
            return
        }

        let referenceSlot = selectedSlot ?? interaction.keyboardCursorSlot ?? .origin
        withAnimation(.easeInOut(duration: 0.2)) {
            _ = document.project.softDeleteCards(ids: targetIDs)
        }

        interaction.editingCardID = nil
        editingSnapshot = nil
        interaction.keyboardCursorSlot = referenceSlot
        interaction.selectEmptySlot(referenceSlot)
        interaction.seedKeyboardCursor(ifNeeded: referenceSlot)
    }

    private func restoreLatestDeletedCard() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            guard let restored = document.project.restoreLatestDeletedCard() else {
                return
            }

            interaction.selectCard(restored.cardID, at: restored.slot)
            interaction.keyboardCursorSlot = restored.slot
            interaction.editingCardID = nil
            editingSnapshot = nil
        }
    }

    private func toggleInlineEditing() {
        guard let selectedCardID else {
            return
        }

        if interaction.editingCardID == selectedCardID {
            stopEditing()
        } else {
            beginEditing(selectedCardID)
        }
    }

    private func stopEditing() {
        editingSnapshot = nil
        interaction.editingCardID = nil
    }

    private func cancelEditing() {
        if let editingSnapshot {
            document.project.updatePresentedMarkdown(
                id: editingSnapshot.cardID,
                markdown: editingSnapshot.markdown
            )
        }

        editingSnapshot = nil
        interaction.editingCardID = nil
    }

    private func beginEditing(_ cardID: UUID) {
        if editingSnapshot?.cardID != cardID {
            editingSnapshot = BoardEditingSnapshot(
                cardID: cardID,
                markdown: document.project.presentedMarkdown(for: cardID) ?? ""
            )
        }

        interaction.editingCardID = cardID
    }

    private func goToCurrentSearchResult() {
        guard let activeSearchResultIndex else {
            return
        }

        activateSearchResult(at: activeSearchResultIndex)
    }

    private func goToFirstSearchResult() {
        activateSearchResult(at: 0)
    }

    private func goToPreviousSearchResult() {
        navigateSearchResults(reverse: true)
    }

    private func goToNextSearchResult() {
        navigateSearchResults(reverse: false)
    }

    private func navigateSearchResults(reverse: Bool) {
        guard let nextIndex = BoardSearchNavigator.advancedIndex(
            current: activeSearchResultIndex,
            count: searchResults.count,
            reverse: reverse
        ) else {
            return
        }

        activateSearchResult(at: nextIndex)
    }

    private func activateSearchResult(at index: Int) {
        guard let resolvedIndex = BoardSearchNavigator.normalizedIndex(index, count: searchResults.count) else {
            return
        }
        let result = searchResults[resolvedIndex]
        searchResultIndex = resolvedIndex
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            _ = BoardGoToController.apply(
                result: result,
                project: &document.project,
                interaction: &interaction
            )
        }
    }

    private func applyLineEdit(axis: BoardLineAxis, operation: BoardLineEditOperation, at index: Int) {
        let referenceSlot = structureReferenceSlot
        let remappedReference = referenceSlot.remapped(for: axis, operation: operation, at: index)

        withAnimation(.easeInOut(duration: 0.22)) {
            let deletedIDs = document.project.applyLineEdit(
                axis: axis,
                operation: operation,
                at: index
            )
            interaction.remapSlots(for: axis, operation: operation, at: index)
            normalizeSelectionAfterStructureChange(
                deletedCardIDs: deletedIDs,
                fallbackSlot: remappedReference
            )
        }
    }

    private func normalizeSelectionAfterStructureChange(
        deletedCardIDs: Set<UUID>,
        fallbackSlot: BoardSlot
    ) {
        let previousEditingCardID = interaction.editingCardID
        BoardStructureSelectionController.normalize(
            project: document.project,
            interaction: &interaction,
            deletedCardIDs: deletedCardIDs,
            fallbackSlot: fallbackSlot
        )
        if previousEditingCardID != nil && interaction.editingCardID == nil {
            editingSnapshot = nil
        }
    }

    private func removeAssetFromSelectedCard() {
        guard let selectedCardID else {
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            document.project.removeAsset(fromPresentedLayerOf: selectedCardID)
        }
    }

    private func handleAssetImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first, let selectedCardID else {
                return
            }

            do {
                let accessGranted = url.startAccessingSecurityScopedResource()
                defer {
                    if accessGranted {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let data = try Data(contentsOf: url)
                let contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                withAnimation(.easeInOut(duration: 0.18)) {
                    _ = document.project.attachAsset(
                        data: data,
                        originalFilename: url.lastPathComponent,
                        contentType: contentType,
                        toPresentedLayerOf: selectedCardID
                    )
                }
            } catch {
                importErrorMessage = error.localizedDescription
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }

    private func advanceEditing(reverse: Bool) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            BoardKeyboardController.advanceByTab(
                project: &document.project,
                interaction: &interaction,
                reverse: reverse
            )
        }
    }

    private func handleBoardKeyEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.bwrCommandModifiers
        let plain = modifiers.isEmpty
        let shifted = modifiers == [.shift]
        let optioned = modifiers == [.option]

        BWRBoardDebugLogger.log(
            "key-route",
            "incoming \(BWRBoardDebugLogger.describe(event: event)) plain=\(plain) shift=\(shifted) option=\(optioned)"
        )

        switch event.keyCode {
        case 53:
            guard plain else {
                return false
            }
            return handleEscapeKey()
        case 36, 76:
            guard plain else {
                return false
            }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                BoardKeyboardController.activateEnter(
                    project: &document.project,
                    interaction: &interaction
                )
            }
            return true
        case 48:
            guard plain || shifted else {
                return false
            }
            advanceEditing(reverse: shifted)
            return true
        case 123:
            performArrowCommand(rows: 0, columns: -1, movesCard: optioned, plain: plain)
            return plain || optioned
        case 124:
            performArrowCommand(rows: 0, columns: 1, movesCard: optioned, plain: plain)
            return plain || optioned
        case 125:
            performArrowCommand(rows: 1, columns: 0, movesCard: optioned, plain: plain)
            return plain || optioned
        case 126:
            performArrowCommand(rows: -1, columns: 0, movesCard: optioned, plain: plain)
            return plain || optioned
        default:
            return false
        }
    }

    private func handleEscapeKey() -> Bool {
        switch BoardEscapeController.outcome(
            interaction: interaction,
            transientGestureState: transientGestureState
        ) {
        case .none:
            return false
        case .cancelEditing:
            cancelEditing()
            return true
        case .cancelTransientGesture:
            gestureCancellationToken += 1
            return true
        case .clearSelection:
            interaction.clearSelection()
            return true
        }
    }

    private func performArrowCommand(rows: Int, columns: Int, movesCard: Bool, plain: Bool) {
        guard movesCard || plain else {
            BWRBoardDebugLogger.log(
                "arrow",
                "ignored rows=\(rows) columns=\(columns) plain=\(plain) movesCard=\(movesCard)"
            )
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            BWRBoardDebugLogger.log(
                "arrow",
                "apply rows=\(rows) columns=\(columns) movesCard=\(movesCard) cursor=\(BWRBoardDebugLogger.describe(slot: interaction.keyboardCursorSlot)) selection=\(BWRBoardDebugLogger.describe(selection: interaction.selection))"
            )
            if movesCard {
                BoardKeyboardController.moveSelectedCard(
                    project: &document.project,
                    interaction: &interaction,
                    rows: rows,
                    columns: columns
                )
            } else {
                BoardKeyboardController.moveCursor(
                    project: document.project,
                    interaction: &interaction,
                    rows: rows,
                    columns: columns
                )
            }
        }
    }

    private func cycleScale() {
        scaleStep = (scaleStep + 1) % scaleValues.count
    }

    private func cycleCanvasTone() {
        canvasTone = canvasTone.next
    }

    private func rememberCurrentDocumentIfNeeded() {
        guard let fileURL else {
            return
        }

        BWRRecentDocumentStore.remember(url: fileURL)
    }
}
