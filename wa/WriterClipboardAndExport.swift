import SwiftUI
import AppKit
import QuartzCore
import UniformTypeIdentifiers

extension ScenarioWriterView {

    // MARK: - Export & Deselect

    func deselectAll() {
        finishEditing(reason: .transition)
        activeCardID = nil
        resetActiveRelationStateCache()
        selectedCardIDs = []
    }

    func buildExportText() -> String {
        guard let activeID = activeCardID else { return "" }
        let levels = resolvedLevelsWithParents()
        var target: [SceneCard] = []
        for (idx, data) in levels.enumerated() {
            guard data.cards.contains(where: { $0.id == activeID }) else { continue }
            target = (idx <= 1 || isActiveCardRoot)
                ? data.cards
                : data.cards.filter { $0.category == activeCategory }
            break
        }
        return target.map { $0.content }.joined(separator: "\n\n")
    }

    func exportToClipboard() {
        let txt = buildExportText()
        if txt.isEmpty {
            exportMessage = "출력할 내용이 없습니다."
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(txt, forType: .string)
            exportMessage = "클립보드에 복사되었습니다."
        }
        showExportAlert = true
    }
    
    func copySelectedCardTreeToClipboard() {
        let roots = copySourceRootCards()
        guard !roots.isEmpty else { return }
        let payload = CardTreeClipboardPayload(roots: roots.map { encodeClipboardNode(from: $0) })
        guard persistCardTreePayloadToClipboard(payload) else { return }
        clearCutCardTreeBuffer()
    }

    func cutSelectedCardTreeToClipboard() {
        let roots = copySourceRootCards()
        guard !roots.isEmpty else { return }
        let payload = CardTreeClipboardPayload(roots: roots.map { encodeClipboardNode(from: $0) })
        guard persistCardTreePayloadToClipboard(payload) else { return }
        cutCardRootIDs = roots.map { $0.id }
        cutCardSourceScenarioID = scenario.id
    }

    func copyCardsAsCloneFromContext(_ contextCard: SceneCard) {
        let cards = cloneCopySourceCards(contextCard: contextCard)
        guard !cards.isEmpty else { return }
        let payload = CloneCardClipboardPayload(
            sourceScenarioID: scenario.id,
            items: cards.map { card in
                CloneCardClipboardItem(
                    sourceCardID: card.id,
                    cloneGroupID: card.cloneGroupID,
                    content: card.content,
                    colorHex: card.colorHex,
                    isAICandidate: card.isAICandidate
                )
            }
        )
        guard persistCloneCardPayloadToClipboard(payload) else { return }
        clearCutCardTreeBuffer()
    }

    func cloneCopySourceCards(contextCard: SceneCard) -> [SceneCard] {
        if selectedCardIDs.count > 1, selectedCardIDs.contains(contextCard.id) {
            let selected = selectedCardIDs.compactMap { findCard(by: $0) }
            guard selected.count == selectedCardIDs.count else { return [contextCard] }
            return sortedCardsByCanvasOrder(selected)
        }
        return [contextCard]
    }

    func sortedCardsByCanvasOrder(_ cards: [SceneCard]) -> [SceneCard] {
        let rank = buildCanvasRank()
        return cards.sorted { lhs, rhs in
            let l = rank[lhs.id] ?? (Int.max, Int.max)
            let r = rank[rhs.id] ?? (Int.max, Int.max)
            if l.0 != r.0 { return l.0 < r.0 }
            if l.1 != r.1 { return l.1 < r.1 }
            return lhs.createdAt < rhs.createdAt
        }
    }

    func handleFountainClipboardPasteShortcutIfPossible(from textView: NSTextView) -> Bool {
        guard let preview = loadFountainClipboardPastePreview() else { return false }
        fountainClipboardPasteSourceTextViewBox.textView = textView
        pendingFountainClipboardPastePreview = preview
        showFountainClipboardPasteDialog = true
        return true
    }

    func loadFountainClipboardPastePreview() -> FountainClipboardPastePreview? {
        let pasteboard = NSPasteboard.general
        guard let rawText = pasteboard.string(forType: .string) else { return nil }
        guard let importPayload = parseFountainClipboardImport(from: rawText) else { return nil }
        return FountainClipboardPastePreview(rawText: rawText, importPayload: importPayload)
    }

    func cancelFountainClipboardPasteDialog() {
        showFountainClipboardPasteDialog = false
        restoreFountainClipboardPasteTextFocusIfNeeded()
    }

    func applyFountainClipboardPasteSelection(_ option: StructuredTextPasteOption) {
        guard let preview = pendingFountainClipboardPastePreview else {
            cancelFountainClipboardPasteDialog()
            return
        }

        showFountainClipboardPasteDialog = false

        switch option {
        case .plainText:
            pasteRawTextIntoFountainClipboardSource(preview.rawText)
        case .sceneCards:
            insertFountainClipboardImportCards(preview.importPayload)
        }
    }

    func restoreFountainClipboardPasteTextFocusIfNeeded() {
        guard let textView = fountainClipboardPasteSourceTextViewBox.textView else { return }
        DispatchQueue.main.async {
            guard let window = textView.window else { return }
            window.makeFirstResponder(textView)
        }
    }

    func pasteRawTextIntoFountainClipboardSource(_ rawText: String) {
        guard let textView = fountainClipboardPasteSourceTextViewBox.textView else { return }
        DispatchQueue.main.async {
            guard let window = textView.window else { return }
            window.makeFirstResponder(textView)
            textView.insertText(rawText, replacementRange: textView.selectedRange())
        }
    }

    func canReuseEditingCardForFountainClipboardImport() -> Bool {
        guard let editingID = editingCardID,
              let editingCard = findCard(by: editingID) else { return false }
        guard editingCard.children.isEmpty else { return false }
        return editingCard.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func insertFountainClipboardImportCards(_ importPayload: FountainClipboardImport) {
        let cardContents = importPayload.cardContents
        guard !cardContents.isEmpty else { return }

        let reuseEditingCard = canReuseEditingCardForFountainClipboardImport()
        let anchorCardID = editingCardID ?? activeCardID

        if reuseEditingCard {
            if showFocusMode {
                finalizeFocusTypingCoalescing(reason: "fountain-import")
                focusModeEditorCardID = nil
            } else {
                finalizeMainTypingCoalescing(reason: "fountain-import")
            }
            resetEditingTransientState()
        } else if editingCardID != nil {
            finishEditing(reason: .transition)
            if showFocusMode {
                focusModeEditorCardID = nil
            }
        }

        let prevState = captureScenarioState()
        guard let anchorCard = anchorCardID.flatMap({ findCard(by: $0) }) ?? activeCardID.flatMap({ findCard(by: $0) }) else {
            insertRootLevelFountainClipboardCards(cardContents, previousState: prevState)
            return
        }

        var insertedCards: [SceneCard] = []
        insertedCards.reserveCapacity(cardContents.count)

        if reuseEditingCard {
            anchorCard.content = cardContents[0]
            insertedCards.append(anchorCard)
            let trailingContents = Array(cardContents.dropFirst())
            appendFountainClipboardCards(
                trailingContents,
                parent: anchorCard.parent,
                insertionIndex: anchorCard.orderIndex + 1,
                category: anchorCard.category,
                accumulator: &insertedCards
            )
            normalizeIndices(parent: anchorCard.parent)
        } else {
            appendFountainClipboardCards(
                cardContents,
                parent: anchorCard.parent,
                insertionIndex: anchorCard.orderIndex + 1,
                category: anchorCard.category,
                accumulator: &insertedCards
            )
            normalizeIndices(parent: anchorCard.parent)
        }

        completeFountainClipboardImport(
            insertedCards,
            previousState: prevState
        )
    }

    func insertRootLevelFountainClipboardCards(_ cardContents: [String], previousState: ScenarioState) {
        var insertedCards: [SceneCard] = []
        insertedCards.reserveCapacity(cardContents.count)
        appendFountainClipboardCards(
            cardContents,
            parent: nil,
            insertionIndex: scenario.rootCards.count,
            category: nil,
            accumulator: &insertedCards
        )
        normalizeIndices(parent: nil)
        completeFountainClipboardImport(
            insertedCards,
            previousState: previousState
        )
    }

    func appendFountainClipboardCards(
        _ contents: [String],
        parent: SceneCard?,
        insertionIndex: Int,
        category: String?,
        accumulator: inout [SceneCard]
    ) {
        guard !contents.isEmpty else { return }

        let siblings = parent?.sortedChildren ?? scenario.rootCards
        for sibling in siblings where sibling.orderIndex >= insertionIndex {
            sibling.orderIndex += contents.count
        }

        for (offset, content) in contents.enumerated() {
            let card = SceneCard(
                content: content,
                orderIndex: insertionIndex + offset,
                createdAt: Date(),
                parent: parent,
                scenario: scenario,
                category: parent?.category ?? category,
                isFloating: false,
                isArchived: false,
                lastSelectedChildID: nil,
                colorHex: nil,
                cloneGroupID: nil,
                isAICandidate: false
            )
            scenario.cards.append(card)
            accumulator.append(card)
        }
    }

    func completeFountainClipboardImport(
        _ insertedCards: [SceneCard],
        previousState: ScenarioState
    ) {
        guard !insertedCards.isEmpty else { return }

        scenario.bumpCardsVersion()
        commitCardMutation(
            previousState: previousState,
            actionName: "파운틴 카드 붙여넣기",
            forceSnapshot: true
        )

        selectedCardIDs = Set(insertedCards.map { $0.id })
        if let first = insertedCards.first {
            changeActiveCard(to: first, shouldFocusMain: false)
        }
        if !showFocusMode {
            isMainViewFocused = true
        }
    }

    func handlePasteShortcut() {
        if pasteCutCardTreeIfPossible() {
            return
        }
        if let clonePayload = loadCopiedCloneCardPayload(), !clonePayload.items.isEmpty {
            pendingCloneCardPastePayload = clonePayload
            pendingCardTreePastePayload = nil
            showCloneCardPasteDialog = true
            return
        }
        if let cardTreePayload = loadCopiedCardTreePayload(), !cardTreePayload.roots.isEmpty {
            pendingCardTreePastePayload = cardTreePayload
            pendingCloneCardPastePayload = nil
            showCloneCardPasteDialog = true
        }
    }

    func applyPendingPastePlacement(as placement: ClonePastePlacement) {
        if let payload = pendingCloneCardPastePayload {
            pendingCloneCardPastePayload = nil
            pendingCardTreePastePayload = nil
            showCloneCardPasteDialog = false
            pasteCloneCardPayload(payload, placement: placement)
            return
        }
        if let payload = pendingCardTreePastePayload {
            pendingCloneCardPastePayload = nil
            pendingCardTreePastePayload = nil
            showCloneCardPasteDialog = false
            pasteCardTreePayload(payload, placement: placement)
            return
        }
        pendingCloneCardPastePayload = nil
        pendingCardTreePastePayload = nil
        showCloneCardPasteDialog = false
    }

    func cancelPendingPastePlacement() {
        pendingCloneCardPastePayload = nil
        pendingCardTreePastePayload = nil
        showCloneCardPasteDialog = false
    }

    func applyPendingCloneCardPaste(as placement: ClonePastePlacement) {
        applyPendingPastePlacement(as: placement)
    }

    func cancelPendingCloneCardPaste() {
        cancelPendingPastePlacement()
    }

    func pasteCloneCardPayload(
        _ payload: CloneCardClipboardPayload,
        placement: ClonePastePlacement
    ) {
        guard !payload.items.isEmpty else { return }

        let prevState = captureScenarioState()
        let destination = resolvePasteDestination(for: placement)
        let destinationParent = destination.parent
        let insertionIndex = destination.insertionIndex

        let destinationSiblings = destinationParent?.sortedChildren ?? scenario.rootCards
        for sibling in destinationSiblings where sibling.orderIndex >= insertionIndex {
            sibling.orderIndex += payload.items.count
        }

        var insertedCards: [SceneCard] = []
        insertedCards.reserveCapacity(payload.items.count)

        for (offset, item) in payload.items.enumerated() {
            let source = resolveClonePasteSource(item, sourceScenarioID: payload.sourceScenarioID)
            let newCard = SceneCard(
                content: source.content,
                orderIndex: insertionIndex + offset,
                createdAt: Date(),
                parent: destinationParent,
                scenario: scenario,
                category: destinationParent?.category,
                isFloating: false,
                isArchived: false,
                lastSelectedChildID: nil,
                colorHex: source.colorHex,
                cloneGroupID: source.cloneGroupID,
                isAICandidate: source.isAICandidate
            )
            scenario.cards.append(newCard)
            insertedCards.append(newCard)
        }

        normalizeIndices(parent: destinationParent)
        scenario.bumpCardsVersion()
        selectedCardIDs = Set(insertedCards.map { $0.id })
        if let first = insertedCards.first {
            changeActiveCard(to: first)
        }
        commitCardMutation(
            previousState: prevState,
            actionName: "클론 카드 붙여넣기"
        )
    }

    func resolvePasteDestination(for placement: ClonePastePlacement) -> (parent: SceneCard?, insertionIndex: Int) {
        guard let active = activeCardID.flatMap({ findCard(by: $0) }) else {
            return (nil, scenario.rootCards.count)
        }

        switch placement {
        case .child:
            return (active, active.children.count)
        case .sibling:
            return (active.parent, active.orderIndex + 1)
        }
    }

    func resolveClonePasteDestination(for placement: ClonePastePlacement) -> (parent: SceneCard?, insertionIndex: Int) {
        resolvePasteDestination(for: placement)
    }

    func resolveClonePasteSource(
        _ item: CloneCardClipboardItem,
        sourceScenarioID: UUID
    ) -> (content: String, colorHex: String?, isAICandidate: Bool, cloneGroupID: UUID) {
        if sourceScenarioID == scenario.id,
           let sourceCard = findCard(by: item.sourceCardID),
           !sourceCard.isArchived {
            let resolvedGroupID: UUID
            if let existing = sourceCard.cloneGroupID {
                resolvedGroupID = existing
            } else {
                let created = item.cloneGroupID ?? UUID()
                sourceCard.cloneGroupID = created
                resolvedGroupID = created
            }
            return (
                content: sourceCard.content,
                colorHex: sourceCard.colorHex,
                isAICandidate: sourceCard.isAICandidate,
                cloneGroupID: resolvedGroupID
            )
        }

        return (
            content: item.content,
            colorHex: item.colorHex,
            isAICandidate: item.isAICandidate,
            cloneGroupID: item.cloneGroupID ?? UUID()
        )
    }

    func pasteCopiedCardTree() {
        if pasteCutCardTreeIfPossible() {
            return
        }

        guard let payload = loadCopiedCardTreePayload() else { return }
        guard !payload.roots.isEmpty else { return }
        pasteCardTreePayload(payload, placement: .child)
    }

    func pasteCardTreePayload(
        _ payload: CardTreeClipboardPayload,
        placement: ClonePastePlacement
    ) {
        guard !payload.roots.isEmpty else { return }

        let prevState = captureScenarioState()

        let destination = resolvePasteDestination(for: placement)
        let destinationParent = destination.parent
        let insertionIndex = destination.insertionIndex

        let destinationSiblings = destinationParent?.sortedChildren ?? scenario.rootCards
        for sibling in destinationSiblings where sibling.orderIndex >= insertionIndex {
            sibling.orderIndex += payload.roots.count
        }

        var newRootCards: [SceneCard] = []
        newRootCards.reserveCapacity(payload.roots.count)
        for (offset, rootNode) in payload.roots.enumerated() {
            let newRoot = instantiateClipboardNode(
                rootNode,
                parent: destinationParent,
                orderIndex: insertionIndex + offset
            )
            newRoot.updateDescendantsCategory(destinationParent?.category)
            newRootCards.append(newRoot)
        }

        normalizeIndices(parent: destinationParent)
        scenario.bumpCardsVersion()
        selectedCardIDs = Set(newRootCards.map { $0.id })
        if let first = newRootCards.first {
            changeActiveCard(to: first)
        }

        commitCardMutation(
            previousState: prevState,
            actionName: "카드 붙여넣기"
        )
    }

    func copySourceRootCards() -> [SceneCard] {
        let selected = selectedCardsForDeletion()
        guard !selected.isEmpty else { return [] }
        return movableRoots(from: selected)
    }

    func persistCardTreePayloadToClipboard(_ payload: CardTreeClipboardPayload) -> Bool {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload) else { return false }

        copiedCardTreePayloadData = data
        copiedCloneCardPayloadData = nil
        pendingCloneCardPastePayload = nil
        pendingCardTreePastePayload = nil
        showCloneCardPasteDialog = false

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([waCardTreePasteboardType], owner: nil)
        pasteboard.setData(data, forType: waCardTreePasteboardType)
        return true
    }

    func persistCloneCardPayloadToClipboard(_ payload: CloneCardClipboardPayload) -> Bool {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload) else { return false }

        copiedCloneCardPayloadData = data
        copiedCardTreePayloadData = nil
        pendingCloneCardPastePayload = nil
        pendingCardTreePastePayload = nil
        showCloneCardPasteDialog = false

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([waCloneCardPasteboardType], owner: nil)
        pasteboard.setData(data, forType: waCloneCardPasteboardType)
        return true
    }

    func clearCutCardTreeBuffer() {
        cutCardRootIDs = []
        cutCardSourceScenarioID = nil
    }

    func resolvedCardTreePasteDestination() -> (parent: SceneCard?, insertionIndex: Int) {
        if let active = activeCardID.flatMap({ findCard(by: $0) }) {
            return (active, active.children.count)
        }
        return (nil, scenario.rootCards.count)
    }

    func pasteCutCardTreeIfPossible() -> Bool {
        guard cutCardSourceScenarioID == scenario.id else { return false }
        guard !cutCardRootIDs.isEmpty else { return false }

        let roots = cutCardRootIDs.compactMap { findCard(by: $0) }
        guard roots.count == cutCardRootIDs.count else { return false }
        let movingRoots = movableRoots(from: roots)
        guard !movingRoots.isEmpty else { return false }
        guard let draggedCard = movingRoots.first else { return false }

        if let active = activeCardID.flatMap({ findCard(by: $0) }) {
            if movingRoots.contains(where: { $0.id == active.id }) { return false }
            if movingRoots.contains(where: { isDescendant($0, of: active.id) }) { return false }
            executeMoveSelection(movingRoots, draggedCard: draggedCard, target: .onto(active.id))
        } else {
            executeMoveSelection(movingRoots, draggedCard: draggedCard, target: .columnBottom(nil))
        }

        clearCutCardTreeBuffer()
        return true
    }

    func encodeClipboardNode(from card: SceneCard) -> CardTreeClipboardNode {
        CardTreeClipboardNode(
            content: card.content,
            colorHex: card.colorHex,
            isAICandidate: card.isAICandidate,
            children: card.sortedChildren.map { encodeClipboardNode(from: $0) }
        )
    }

    func instantiateClipboardNode(
        _ node: CardTreeClipboardNode,
        parent: SceneCard?,
        orderIndex: Int
    ) -> SceneCard {
        let card = SceneCard(
            content: node.content,
            orderIndex: orderIndex,
            createdAt: Date(),
            parent: parent,
            scenario: scenario,
            category: parent?.category,
            isFloating: false,
            isArchived: false,
            lastSelectedChildID: nil,
            colorHex: node.colorHex,
            isAICandidate: node.isAICandidate
        )
        scenario.cards.append(card)

        for (childIndex, childNode) in node.children.enumerated() {
            _ = instantiateClipboardNode(childNode, parent: card, orderIndex: childIndex)
        }
        return card
    }

    func loadCopiedCardTreePayload() -> CardTreeClipboardPayload? {
        let decoder = JSONDecoder()
        let pasteboard = NSPasteboard.general

        if let data = pasteboard.data(forType: waCardTreePasteboardType),
           let payload = try? decoder.decode(CardTreeClipboardPayload.self, from: data) {
            copiedCardTreePayloadData = data
            return payload
        }

        if let cached = copiedCardTreePayloadData,
           let payload = try? decoder.decode(CardTreeClipboardPayload.self, from: cached) {
            return payload
        }

        return nil
    }

    func loadCopiedCloneCardPayload() -> CloneCardClipboardPayload? {
        let decoder = JSONDecoder()
        let pasteboard = NSPasteboard.general

        if let data = pasteboard.data(forType: waCloneCardPasteboardType),
           let payload = try? decoder.decode(CloneCardClipboardPayload.self, from: data) {
            copiedCloneCardPayloadData = data
            return payload
        }

        if let cached = copiedCloneCardPayloadData,
           let payload = try? decoder.decode(CloneCardClipboardPayload.self, from: cached) {
            return payload
        }

        return nil
    }

    func exportToFile() {
        let txt = buildExportText()
        if txt.isEmpty {
            exportMessage = "출력할 내용이 없습니다."
            showExportAlert = true
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(scenario.title)_출력.txt"
        panel.begin { res in
            guard res == .OK, let url = panel.url else { return }
            try? txt.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    func exportToCenteredPDF() {
        exportToPDF(format: .centered, defaultName: "\(scenario.title)_중앙정렬식.pdf")
    }
    func exportToKoreanPDF() {
        exportToPDF(format: .korean, defaultName: "\(scenario.title)_한국식.pdf")
    }
    func exportToPDF(format: ScriptExportFormatType, defaultName: String) {
        let txt = buildExportText()
        if txt.isEmpty {
            exportMessage = "출력할 내용이 없습니다."
            showExportAlert = true
            return
        }
        let parser = ScriptMarkdownParser(formatType: format)
        let elements = parser.parse(txt)
        var pdfConfig = ScriptExportLayoutConfig()
        pdfConfig.centeredFontSize = CGFloat(exportCenteredFontSize)
        pdfConfig.centeredIsCharacterBold = exportCenteredCharacterBold
        pdfConfig.centeredIsSceneHeadingBold = exportCenteredSceneHeadingBold
        pdfConfig.centeredShowRightSceneNumber = exportCenteredShowRightSceneNumber
        pdfConfig.koreanFontSize = CGFloat(exportKoreanFontSize)
        pdfConfig.koreanIsSceneBold = exportKoreanSceneBold
        pdfConfig.koreanIsCharacterBold = exportKoreanCharacterBold
        pdfConfig.koreanCharacterAlignment = exportKoreanCharacterAlignment == "left" ? .left : .right

        let generator = ScriptPDFGenerator(format: format, config: pdfConfig)
        let data = generator.generatePDF(from: elements)
        if data.isEmpty {
            exportMessage = "PDF 생성에 실패했습니다."
            showExportAlert = true
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = defaultName
        panel.begin { res in
            if res == .OK, let url = panel.url {
                do {
                    try data.write(to: url)
                } catch {
                    exportMessage = "PDF 저장에 실패했습니다."
                    showExportAlert = true
                }
            }
        }
    }
}
