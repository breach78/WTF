import SwiftUI

extension ScenarioWriterView {
    func aiOptionsSheet(action: AICardAction) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(action.sheetTitle)
                .font(.system(size: 18, weight: .bold))

            Text("원하는 방향을 1개 이상 선택하면 해당 성향을 반영한 5개 후보를 만듭니다.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(AIGenerationOption.allCases) { option in
                        Toggle(isOn: aiGenerationOptionBinding(for: option)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(option.shortDescription)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)
            }

            HStack(spacing: 10) {
                Button("취소", role: .cancel) {
                    aiOptionsSheetAction = nil
                }
                Spacer()
                Button("생성") {
                    let selected = aiSelectedGenerationOptions
                    aiOptionsSheetAction = nil
                    requestAICandidates(action: action, selectedOptions: selected)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(aiIsGenerating)
            }
        }
        .padding(20)
        .frame(width: 520, height: 560)
    }

    func openAIOptionsSheet(for action: AICardAction) {
        guard activeCardID != nil else {
            setAIStatusError("먼저 카드 하나를 선택해 주세요.")
            return
        }
        if aiSelectedGenerationOptions.isEmpty {
            aiSelectedGenerationOptions = [.balanced]
        }
        aiOptionsSheetAction = action
    }

    func aiGenerationOptionBinding(for option: AIGenerationOption) -> Binding<Bool> {
        Binding(
            get: { aiSelectedGenerationOptions.contains(option) },
            set: { isOn in
                if isOn {
                    aiSelectedGenerationOptions.insert(option)
                } else {
                    aiSelectedGenerationOptions.remove(option)
                    if aiSelectedGenerationOptions.isEmpty {
                        aiSelectedGenerationOptions.insert(.balanced)
                    }
                }
            }
        )
    }

    // MARK: - AI Generation Actions

    func runAICardActionFromContextMenu(for card: SceneCard, action: AICardAction) {
        prepareCardForContextMenuAIAction(card)
        switch action {
        case .elaborate, .nextScene, .alternative:
            openAIOptionsSheet(for: action)
        case .summary:
            requestAISummaryCandidate()
        }
    }

    func runChildSummaryFromCardContextMenu(for card: SceneCard) {
        prepareCardForContextMenuAIAction(card)
        summarizeDirectChildrenIntoParent(cardID: card.id)
    }

    func applyAICandidateFromCardContextMenu(cardID: UUID) {
        selectedCardIDs = [cardID]
        if let card = findCard(by: cardID) {
            changeActiveCard(to: card, shouldFocusMain: false)
        }
        applySelectedAICandidateToParent(candidateID: cardID)
    }

    func prepareCardForContextMenuAIAction(_ card: SceneCard) {
        suppressMainFocusRestoreAfterFinishEditing = true
        finishEditing()
        selectedCardIDs = [card.id]
        changeActiveCard(to: card, shouldFocusMain: false)
    }

    func aiCardGenerationQuery(for card: SceneCard, action: AICardAction, options: Set<AIGenerationOption>) -> String {
        let optionLabels = sortedAIGenerationOptions(options).map(\.title).joined(separator: ", ")
        let compactCard = clampedAIText(card.content, maxLength: 420, preserveLineBreak: true)
        return "\(action.summaryLabel): \(compactCard)\n옵션: \(optionLabels)"
    }

    func aiAllCardSnapshots() -> [AIChatCardSnapshot] {
        scenario.cards.map { card in
            AIChatCardSnapshot(
                id: card.id,
                parentID: card.parent?.id,
                category: card.category ?? ScenarioCardCategory.uncategorized,
                content: card.content,
                orderIndex: card.orderIndex,
                createdAt: card.createdAt,
                isArchived: card.isArchived,
                isFloating: card.isFloating
            )
        }
    }

    func buildSharedConsultantContextForCardGeneration(
        targetCardID: UUID,
        query: String,
        apiKey: String,
        digestCache: [UUID: AICardDigest],
        embeddingIndex: [UUID: AIEmbeddingRecord]
    ) async -> (
        preview: AIChatContextPreview?,
        updatedDigestCache: [UUID: AICardDigest],
        updatedEmbeddingIndex: [UUID: AIEmbeddingRecord],
        resolvedEmbeddingModel: String?
    ) {
        let allCardSnapshots = aiAllCardSnapshots()
        let visibleCards = allCardSnapshots.filter { !$0.isArchived && !$0.isFloating }
        guard !visibleCards.isEmpty else {
            return (nil, digestCache, embeddingIndex, nil)
        }

        let scopedCards = visibleCards.filter { $0.id == targetCardID }
        let resolvedScopedCards = scopedCards.isEmpty ? Array(visibleCards.prefix(1)) : scopedCards
        let vectorDBURL = store.aiVectorIndexURL(for: scenario.id)
        let semanticRAG = await buildSemanticRAGContext(
            query: query,
            allCards: allCardSnapshots,
            scopedCards: resolvedScopedCards,
            digests: digestCache,
            existingIndex: embeddingIndex,
            apiKey: apiKey,
            vectorDBURL: vectorDBURL
        )

        let scope = AIChatThreadScope(type: .selectedCards, cardIDs: [targetCardID], includeChildrenDepth: 0)
        let buildResult = AIChatPromptBuilder.buildPrompt(
            allCards: allCardSnapshots,
            scopedCards: resolvedScopedCards,
            scopeLabel: scopeLabel(for: scope, cardCount: resolvedScopedCards.count),
            history: [],
            lastUserMessage: query,
            previousRollingSummary: "",
            digestCache: digestCache,
            refreshRollingSummary: false,
            semanticRAGContext: semanticRAG.semanticContext
        )

        return (
            buildResult.contextPreview,
            buildResult.updatedDigestCache,
            semanticRAG.updatedIndex,
            semanticRAG.resolvedModel
        )
    }

    func requestAICandidates(action: AICardAction, selectedOptions: Set<AIGenerationOption>) {
        finishEditing()
        pruneAICandidateTracking()

        guard let parentID = activeCardID,
              let parentCard = findCard(by: parentID) else {
            setAIStatusError("활성 카드가 없어 AI 제안을 만들 수 없습니다.")
            return
        }
        guard parentCard.category == ScenarioCardCategory.plot else {
            setAIStatusError("구체화/다음 장면/대안은 플롯 카드에서만 사용할 수 있습니다.")
            return
        }

        let options = selectedOptions.isEmpty ? Set([AIGenerationOption.balanced]) : selectedOptions
        let resolvedModel = currentGeminiModel()

        aiIsGenerating = true
        aiChildSummaryLoadingCardIDs.insert(parentID)
        setAIStatus("\(action.summaryLabel)을 생성하는 중입니다...")

        Task { @MainActor in
            defer {
                aiIsGenerating = false
                aiChildSummaryLoadingCardIDs.remove(parentID)
            }
            do {
                guard let latestParent = findCard(by: parentID) else { return }
                guard let apiKey = try KeychainStore.loadGeminiAPIKey() else {
                    throw GeminiServiceError.missingAPIKey
                }
                loadPersistedAIEmbeddingIndexIfNeeded()
                let query = aiCardGenerationQuery(for: latestParent, action: action, options: options)
                let sharedContext = await buildSharedConsultantContextForCardGeneration(
                    targetCardID: latestParent.id,
                    query: query,
                    apiKey: apiKey,
                    digestCache: aiCardDigestCache,
                    embeddingIndex: aiEmbeddingIndexByCardID
                )
                aiCardDigestCache = sharedContext.updatedDigestCache
                aiEmbeddingIndexByCardID = sharedContext.updatedEmbeddingIndex
                if let resolvedEmbeddingModel = sharedContext.resolvedEmbeddingModel {
                    aiEmbeddingIndexModelID = resolvedEmbeddingModel
                }
                scheduleAIEmbeddingPersistence()
                let prompt = buildAIPrompt(
                    for: latestParent,
                    action: action,
                    options: options,
                    sharedContext: sharedContext.preview
                )
                let suggestions = try await GeminiService.generateSuggestions(
                    prompt: prompt,
                    model: resolvedModel,
                    apiKey: apiKey
                )
                applyAICandidates(
                    suggestions: suggestions,
                    parentID: parentID,
                    action: action
                )
            } catch {
                setAIStatusError(error.localizedDescription)
            }
        }
    }

    func requestAISummaryCandidate() {
        finishEditing()
        pruneAICandidateTracking()

        guard let parentID = activeCardID,
              findCard(by: parentID) != nil else {
            setAIStatusError("활성 카드가 없어 요약을 만들 수 없습니다.")
            return
        }

        let resolvedModel = currentGeminiModel()

        aiIsGenerating = true
        aiChildSummaryLoadingCardIDs.insert(parentID)
        setAIStatus("요약 제안을 생성하는 중입니다...")

        Task { @MainActor in
            defer {
                aiIsGenerating = false
                aiChildSummaryLoadingCardIDs.remove(parentID)
            }
            do {
                guard let latestParent = findCard(by: parentID) else { return }
                guard let apiKey = try KeychainStore.loadGeminiAPIKey() else {
                    throw GeminiServiceError.missingAPIKey
                }
                let prompt = buildAISummaryPrompt(for: latestParent)
                let summaryText = try await GeminiService.generateText(
                    prompt: prompt,
                    model: resolvedModel,
                    apiKey: apiKey
                )
                let normalized = summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else {
                    throw GeminiServiceError.invalidResponse
                }
                let suggestion = GeminiSuggestion(title: "", content: normalized, rationale: nil)
                applyAICandidates(
                    suggestions: [suggestion],
                    parentID: parentID,
                    action: .summary
                )
            } catch {
                setAIStatusError(error.localizedDescription)
            }
        }
    }

    func applyAICandidates(
        suggestions: [GeminiSuggestion],
        parentID: UUID,
        action: AICardAction
    ) {
        guard let parent = findCard(by: parentID) else {
            setAIStatusError("원본 카드가 사라져 제안을 반영할 수 없습니다.")
            return
        }

        if !aiCandidateState.cardIDs.isEmpty {
            for candidateID in aiCandidateState.cardIDs {
                findCard(by: candidateID)?.isAICandidate = false
            }
        }
        clearStaleAICandidateVisualFlags()

        let prevState = captureScenarioState()
        var newIDs: [UUID] = []
        var nextOrderIndex = parent.children.count
        let maxCount = action == .summary ? 1 : 5
        for (offset, suggestion) in suggestions.prefix(maxCount).enumerated() {
            let normalized = normalizedAICandidateContent(from: suggestion)
            guard !normalized.isEmpty else { continue }
            let card = SceneCard(
                content: normalized,
                orderIndex: nextOrderIndex,
                parent: parent,
                scenario: scenario,
                category: parent.category,
                colorHex: aiCandidateTintHex(for: offset)
            )
            card.isAICandidate = true
            scenario.cards.append(card)
            newIDs.append(card.id)
            nextOrderIndex += 1
        }

        guard !newIDs.isEmpty else {
            setAIStatusError("생성된 후보 내용이 비어 있어 카드를 만들지 못했습니다.")
            return
        }

        scenario.bumpCardsVersion()
        commitCardMutation(
            previousState: prevState,
            actionName: "AI \(action.title)",
            forceSnapshot: true
        )

        aiCandidateState.parentID = parent.id
        aiCandidateState.cardIDs = newIDs
        aiCandidateState.action = action

        if let firstID = newIDs.first,
           let firstCard = findCard(by: firstID) {
            selectedCardIDs = [firstID]
            changeActiveCard(to: firstCard)
        }

        let createdCount = newIDs.count
        if action == .summary {
            setAIStatus("요약 후보 1개를 만들었습니다. 후보 카드 우상단 '선택' 버튼으로 바로 반영할 수 있습니다.")
        } else {
            setAIStatus("\(action.summaryLabel) \(createdCount)개를 만들었습니다. 후보 카드 우상단 '선택' 버튼으로 바로 반영할 수 있습니다.")
        }
    }

    func applySelectedAICandidateToParent(candidateID: UUID? = nil) {
        finishEditing()
        pruneAICandidateTracking()

        guard let parentID = aiCandidateState.parentID,
              let parentCard = findCard(by: parentID) else {
            setAIStatusError("적용할 AI 후보 그룹이 없습니다.")
            return
        }
        guard let action = aiCandidateState.action else {
            setAIStatusError("AI 후보 작업 타입을 확인할 수 확인 할 수 없습니다. 다시 생성해 주세요.")
            return
        }
        let selectedCandidate: SceneCard
        if let candidateID {
            guard aiCandidateState.cardIDs.contains(candidateID),
                  let resolved = findCard(by: candidateID),
                  !resolved.isArchived,
                  resolved.parent?.id == parentID else {
                setAIStatusError("선택한 AI 후보를 찾을 수 없습니다. 후보를 다시 생성해 주세요.")
                return
            }
            selectedCandidate = resolved
        } else {
            guard let resolved = selectedAICandidateCard() else {
                setAIStatusError("AI 후보 카드 중 하나를 먼저 선택해 주세요.")
                return
            }
            selectedCandidate = resolved
        }

        let prevState = captureScenarioState()
        let selectedID = selectedCandidate.id

        switch action {
        case .elaborate, .alternative:
            parentCard.content = selectedCandidate.content
            selectedCandidate.colorHex = nil
            selectedCandidate.isAICandidate = false
        case .summary:
            let summaryText = selectedCandidate.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if parentCard.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parentCard.content = summaryText
            } else {
                parentCard.content += "\n\n---\n\(summaryText)"
            }
            selectedCandidate.isAICandidate = false
            selectedCandidate.isArchived = true
        case .nextScene:
            let destinationParent = parentCard.parent
            let destinationIndex = parentCard.orderIndex + 1
            let destinationSiblings = destinationParent?.sortedChildren ?? scenario.rootCards
            for sibling in destinationSiblings where sibling.id != selectedID && sibling.orderIndex >= destinationIndex {
                sibling.orderIndex += 1
            }
            selectedCandidate.parent = destinationParent
            selectedCandidate.orderIndex = destinationIndex
            selectedCandidate.category = parentCard.category
            selectedCandidate.colorHex = nil
            selectedCandidate.isAICandidate = false
        }

        let candidatesToArchive: [UUID]
        if action == .summary {
            candidatesToArchive = aiCandidateState.cardIDs
        } else {
            candidatesToArchive = aiCandidateState.cardIDs.filter { $0 != selectedID }
        }
        for candidateID in candidatesToArchive {
            if let candidate = findCard(by: candidateID) {
                candidate.isAICandidate = false
                candidate.isArchived = true
            }
        }

        switch action {
        case .elaborate, .alternative, .summary:
            selectedCardIDs = [parentCard.id]
            changeActiveCard(to: parentCard)
        case .nextScene:
            selectedCardIDs = [selectedCandidate.id]
            changeActiveCard(to: selectedCandidate)
        }

        scenario.bumpCardsVersion()
        commitCardMutation(
            previousState: prevState,
            actionName: "AI \(action.title) 적용",
            forceSnapshot: true
        )

        aiCandidateState.parentID = nil
        aiCandidateState.cardIDs = []
        aiCandidateState.action = nil

        switch action {
        case .elaborate, .alternative:
            setAIStatus("선택한 후보를 부모 카드에 반영했고, 나머지 후보는 삭제했습니다.")
        case .summary:
            setAIStatus("요약을 원본 카드 하단(--- 아래)에 추가했고, 모든 요약 후보를 삭제했습니다.")
        case .nextScene:
            setAIStatus("선택한 후보를 부모 바로 아래 형제 카드로 배치했고, 나머지 후보는 삭제했습니다.")
        }
    }

    func currentGeminiModel() -> String {
        let modelName = geminiModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizeGeminiModelID(modelName.isEmpty ? "gemini-3.1-pro-preview" : modelName)
    }

    func normalizeGeminiModelID(_ raw: String) -> String {
        normalizeGeminiModelIDValue(raw)
    }

    func selectedAICandidateCard() -> SceneCard? {
        guard let parentID = aiCandidateState.parentID else { return nil }
        let candidates = aiCandidateState.cardIDs.compactMap { id -> SceneCard? in
            guard let card = findCard(by: id), !card.isArchived else { return nil }
            guard card.parent?.id == parentID else { return nil }
            return card
        }
        guard !candidates.isEmpty else { return nil }

        if let activeID = activeCardID,
           let activeCard = candidates.first(where: { $0.id == activeID }) {
            return activeCard
        }
        if selectedCardIDs.count == 1,
           let selectedID = selectedCardIDs.first,
           let selectedCard = candidates.first(where: { $0.id == selectedID }) {
            return selectedCard
        }
        return nil
    }

    func pruneAICandidateTracking() {
        if let parentID = aiCandidateState.parentID, findCard(by: parentID) == nil {
            aiCandidateState.parentID = nil
            aiCandidateState.cardIDs = []
            aiCandidateState.action = nil
            clearStaleAICandidateVisualFlags()
            return
        }

        if let parentID = aiCandidateState.parentID {
            aiCandidateState.cardIDs = aiCandidateState.cardIDs.filter { id in
                guard let card = findCard(by: id) else { return false }
                guard !card.isArchived else { return false }
                return card.parent?.id == parentID
            }
        }

        if aiCandidateState.cardIDs.isEmpty {
            aiCandidateState.parentID = nil
            aiCandidateState.action = nil
        }

        clearStaleAICandidateVisualFlags()
    }

    // MARK: - AI Status

    func setAIStatus(_ message: String?) {
        aiStatusMessage = message
        aiStatusIsError = false
    }

    func setAIStatusError(_ message: String) {
        aiStatusMessage = message
        aiStatusIsError = true
    }
}
