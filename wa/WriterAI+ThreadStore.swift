import SwiftUI

extension ScenarioWriterView {
    var aiThreadsMaxCount: Int { 30 }
    var aiMessagesMaxCountPerThread: Int { 140 }
    var aiEmbeddingMaxRecordCount: Int { 1200 }
    var aiRAGTopCardCount: Int { 8 }
    var aiRAGEmbeddingModelCandidates: [String] { ["gemini-embedding-001", "text-embedding-004"] }
    var visibleAIChatScopes: [AIChatScopeType] { [.selectedCards, .plotLine, .noteLine] }

    private func aiPersistenceJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func aiPersistenceJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func aiThreadsJSONEncoder() -> JSONEncoder {
        aiPersistenceJSONEncoder()
    }

    func aiThreadsJSONDecoder() -> JSONDecoder {
        aiPersistenceJSONDecoder()
    }

    func aiEmbeddingJSONEncoder() -> JSONEncoder {
        aiPersistenceJSONEncoder()
    }

    func aiEmbeddingJSONDecoder() -> JSONDecoder {
        aiPersistenceJSONDecoder()
    }

    func normalizedPersistedAIEmbeddings(_ records: [AIEmbeddingRecord], validCardIDs: Set<UUID>) -> [AIEmbeddingRecord] {
        var normalized = records
            .filter { validCardIDs.contains($0.cardID) && !$0.vector.isEmpty }
            .prefix(aiEmbeddingMaxRecordCount)
            .map { $0 }
        normalized.sort { $0.updatedAt > $1.updatedAt }
        return normalized
    }

    func persistAIEmbeddingsImmediately() {
        guard aiEmbeddingIndexLoadedScenarioID == scenario.id else { return }
        let validIDs = Set(
            scenario.cards
                .filter { !$0.isArchived && !$0.isFloating }
                .map(\.id)
        )
        let normalizedRecords = normalizedPersistedAIEmbeddings(Array(aiEmbeddingIndexByCardID.values), validCardIDs: validIDs)
        guard !normalizedRecords.isEmpty else {
            store.saveAIEmbeddingIndexData(nil, for: scenario.id)
            return
        }

        let payload = AIEmbeddingIndexPayload(
            model: aiEmbeddingIndexModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (aiRAGEmbeddingModelCandidates.first ?? "gemini-embedding-001")
                : aiEmbeddingIndexModelID,
            records: normalizedRecords,
            updatedAt: Date()
        )
        guard let data = try? aiEmbeddingJSONEncoder().encode(payload) else { return }
        store.saveAIEmbeddingIndexData(data, for: scenario.id)
    }

    func scheduleAIEmbeddingPersistence(delay: TimeInterval = 0.8) {
        guard aiEmbeddingIndexLoadedScenarioID == scenario.id else { return }
        aiEmbeddingIndexSaveWorkItem?.cancel()
        let work = DispatchWorkItem { [scenarioID = scenario.id] in
            guard scenarioID == scenario.id else { return }
            persistAIEmbeddingsImmediately()
            aiEmbeddingIndexSaveWorkItem = nil
        }
        aiEmbeddingIndexSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func flushAIEmbeddingPersistence() {
        aiEmbeddingIndexSaveWorkItem?.cancel()
        aiEmbeddingIndexSaveWorkItem = nil
        persistAIEmbeddingsImmediately()
    }

    func loadPersistedAIEmbeddingIndexIfNeeded() {
        guard aiEmbeddingIndexLoadedScenarioID != scenario.id else { return }

        aiEmbeddingIndexSaveWorkItem?.cancel()
        aiEmbeddingIndexSaveWorkItem = nil
        aiEmbeddingIndexLoadedScenarioID = scenario.id
        aiEmbeddingIndexByCardID = [:]
        aiEmbeddingIndexModelID = aiRAGEmbeddingModelCandidates.first ?? "gemini-embedding-001"

        let targetScenarioID = scenario.id
        Task {
            let loadedData = await store.loadAIEmbeddingIndexData(for: targetScenarioID)
            await MainActor.run {
                guard aiEmbeddingIndexLoadedScenarioID == targetScenarioID else { return }
                guard let loadedData,
                      let payload = try? aiEmbeddingJSONDecoder().decode(AIEmbeddingIndexPayload.self, from: loadedData) else {
                    aiEmbeddingIndexByCardID = [:]
                    aiEmbeddingIndexModelID = aiRAGEmbeddingModelCandidates.first ?? "gemini-embedding-001"
                    return
                }
                let validIDs = Set(
                    scenario.cards
                        .filter { !$0.isArchived && !$0.isFloating }
                        .map(\.id)
                )
                let normalized = normalizedPersistedAIEmbeddings(payload.records, validCardIDs: validIDs)
                aiEmbeddingIndexByCardID = Dictionary(uniqueKeysWithValues: normalized.map { ($0.cardID, $0) })
                let trimmedModel = payload.model.trimmingCharacters(in: .whitespacesAndNewlines)
                aiEmbeddingIndexModelID = trimmedModel.isEmpty ? (aiRAGEmbeddingModelCandidates.first ?? "gemini-embedding-001") : trimmedModel
            }
        }
    }

    func normalizedPersistedAIThreads(_ threads: [AIChatThread]) -> [AIChatThread] {
        var normalized = threads.prefix(aiThreadsMaxCount).map { thread in
            var mutable = thread
            mutable.scope.type = mutable.scope.type.normalizedForCurrentUI
            if mutable.messages.count > aiMessagesMaxCountPerThread {
                mutable.messages = Array(mutable.messages.suffix(aiMessagesMaxCountPerThread))
            }
            var tokenUsage = mutable.tokenUsage ?? .zero
            tokenUsage.promptTokens = max(tokenUsage.promptTokens, 0)
            tokenUsage.outputTokens = max(tokenUsage.outputTokens, 0)
            tokenUsage.totalTokens = max(tokenUsage.totalTokens, 0)
            mutable.tokenUsage = tokenUsage
            return mutable
        }
        normalized.sort { $0.updatedAt > $1.updatedAt }
        return normalized
    }

    func persistAIThreadsImmediately() {
        guard aiThreadsLoadedScenarioID == scenario.id else { return }
        let normalizedThreads = normalizedPersistedAIThreads(aiChatThreads)
        let activeThreadID = normalizedThreads.contains(where: { $0.id == activeAIChatThreadID }) ? activeAIChatThreadID : normalizedThreads.first?.id
        guard !normalizedThreads.isEmpty else {
            store.saveAIChatThreadsData(nil, for: scenario.id)
            return
        }

        let payload = AIChatThreadStorePayload(threads: normalizedThreads, activeThreadID: activeThreadID)
        guard let data = try? aiThreadsJSONEncoder().encode(payload) else { return }
        store.saveAIChatThreadsData(data, for: scenario.id)
    }

    func scheduleAIThreadsPersistence(delay: TimeInterval = 0.45) {
        guard aiThreadsLoadedScenarioID == scenario.id else { return }
        aiThreadsSaveWorkItem?.cancel()
        let work = DispatchWorkItem { [scenarioID = scenario.id] in
            guard scenarioID == scenario.id else { return }
            persistAIThreadsImmediately()
            aiThreadsSaveWorkItem = nil
        }
        aiThreadsSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func flushAIThreadsPersistence() {
        aiThreadsSaveWorkItem?.cancel()
        aiThreadsSaveWorkItem = nil
        persistAIThreadsImmediately()
    }

    func loadPersistedAIThreadsIfNeeded() {
        guard aiThreadsLoadedScenarioID != scenario.id else { return }

        aiThreadsSaveWorkItem?.cancel()
        aiThreadsSaveWorkItem = nil
        aiThreadsLoadedScenarioID = scenario.id
        aiChatThreads = []
        activeAIChatThreadID = nil
        aiCardDigestCache = [:]
        aiLastContextPreview = nil
        aiChatInput = ""

        let targetScenarioID = scenario.id
        Task {
            let loadedData = await store.loadAIChatThreadsData(for: targetScenarioID)
            await MainActor.run {
                guard aiThreadsLoadedScenarioID == targetScenarioID else { return }
                if let loadedData,
                   let payload = try? aiThreadsJSONDecoder().decode(AIChatThreadStorePayload.self, from: loadedData) {
                    let normalizedThreads = normalizedPersistedAIThreads(payload.threads)
                    aiChatThreads = normalizedThreads
                    if let savedActive = payload.activeThreadID,
                       normalizedThreads.contains(where: { $0.id == savedActive }) {
                        activeAIChatThreadID = savedActive
                    } else {
                        activeAIChatThreadID = normalizedThreads.first?.id
                    }
                }
                ensureAIChatThreadSelection()
            }
        }
    }

    func handleAIChatScenarioChange() {
        cancelAIChatRequest()
        aiThreadsLoadedScenarioID = nil
        aiEmbeddingIndexLoadedScenarioID = nil
        loadPersistedAIThreadsIfNeeded()
        loadPersistedAIEmbeddingIndexIfNeeded()
    }

    func activeAIChatThreadIndex() -> Int? {
        guard let threadID = activeAIChatThreadID else { return nil }
        return aiChatThreads.firstIndex { $0.id == threadID }
    }

    func activeAIChatMessages() -> [AIChatMessage] {
        guard let index = activeAIChatThreadIndex() else { return [] }
        return aiChatThreads[index].messages
    }

    func messagesForAIThread(_ threadID: UUID) -> [AIChatMessage] {
        guard let index = aiChatThreads.firstIndex(where: { $0.id == threadID }) else { return [] }
        return aiChatThreads[index].messages
    }

    func tokenUsageForAIThread(_ threadID: UUID?) -> AIChatTokenUsage {
        guard let threadID,
              let index = aiChatThreads.firstIndex(where: { $0.id == threadID }) else {
            return .zero
        }
        return aiChatThreads[index].tokenUsage ?? .zero
    }

    func updateAIChatThread(_ threadID: UUID, mutate: (inout AIChatThread) -> Void) {
        guard let index = aiChatThreads.firstIndex(where: { $0.id == threadID }) else { return }
        mutate(&aiChatThreads[index])
        aiChatThreads[index].updatedAt = Date()
        scheduleAIThreadsPersistence()
    }

    func appendAIChatMessage(_ message: AIChatMessage, to threadID: UUID) {
        updateAIChatThread(threadID) { thread in
            thread.messages.append(message)
            if message.role == "user",
               thread.title.hasPrefix("상담 "),
               !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                thread.title = suggestedThreadTitle(from: message.text)
            }
        }
    }

    func clearAIChatMessages(in threadID: UUID) {
        updateAIChatThread(threadID) { thread in
            thread.messages.removeAll()
            thread.rollingSummary = ""
            thread.decisionLog = []
            thread.unresolvedQuestions = []
            thread.tokenUsage = .zero
        }
        if threadID == activeAIChatThreadID {
            aiLastContextPreview = nil
        }
    }

    func currentSelectedCardIDsForAIContext() -> [UUID] {
        if !selectedCardIDs.isEmpty {
            return selectedCardIDs.sorted { $0.uuidString < $1.uuidString }
        }
        if let activeID = activeCardID {
            return [activeID]
        }
        return []
    }

    func deleteAIChatThread(_ threadID: UUID) {
        guard let index = aiChatThreads.firstIndex(where: { $0.id == threadID }) else { return }
        let isActiveThread = (threadID == activeAIChatThreadID)
        if isActiveThread {
            cancelAIChatRequest()
        }

        aiChatThreads.remove(at: index)

        if aiChatThreads.isEmpty {
            createAIChatThread(focusInput: showAIChat)
            setAIStatus("상담 스레드를 삭제했습니다.")
            return
        }

        if isActiveThread {
            let fallbackIndex = min(index, aiChatThreads.count - 1)
            activeAIChatThreadID = aiChatThreads[fallbackIndex].id
            aiChatInput = ""
            aiLastContextPreview = nil
            if showAIChat {
                isAIChatInputFocused = true
            }
        }

        scheduleAIThreadsPersistence(delay: 0.15)
        setAIStatus("상담 스레드를 삭제했습니다.")
    }

    func suggestedThreadTitle(from userMessage: String) -> String {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "상담" }
        let maxLength = 16
        if trimmed.count <= maxLength { return trimmed }
        let index = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        return String(trimmed[..<index]) + "..."
    }

    func nextAIChatThreadTitle() -> String {
        let prefix = "상담 "
        let numbers = aiChatThreads.compactMap { thread -> Int? in
            guard thread.title.hasPrefix(prefix) else { return nil }
            return Int(thread.title.dropFirst(prefix.count))
        }
        let next = (numbers.max() ?? 0) + 1
        return "상담 \(next)"
    }

    func resolvedInitialThreadScope() -> AIChatThreadScope {
        let selectedIDs = currentSelectedCardIDsForAIContext()
        if !selectedIDs.isEmpty {
            return AIChatThreadScope(type: .selectedCards, cardIDs: selectedIDs, includeChildrenDepth: 0)
        }
        return AIChatThreadScope(type: .plotLine, cardIDs: [], includeChildrenDepth: 0)
    }

    func createAIChatThread(focusInput: Bool = true) {
        cancelAIChatRequest()
        let thread = AIChatThread(
            id: UUID(),
            title: nextAIChatThreadTitle(),
            mode: .discussion,
            scope: resolvedInitialThreadScope(),
            messages: [],
            rollingSummary: "",
            decisionLog: [],
            unresolvedQuestions: [],
            updatedAt: Date()
        )
        aiChatThreads.insert(thread, at: 0)
        activeAIChatThreadID = thread.id
        aiChatInput = ""
        aiLastContextPreview = nil
        setAIStatus(nil)
        scheduleAIThreadsPersistence(delay: 0.15)
        if focusInput {
            isAIChatInputFocused = true
        }
    }

    func selectAIChatThread(_ threadID: UUID) {
        guard activeAIChatThreadID != threadID else { return }
        cancelAIChatRequest()
        activeAIChatThreadID = threadID
        aiChatInput = ""
        aiLastContextPreview = nil
        setAIStatus(nil)
        scheduleAIThreadsPersistence(delay: 0.15)
    }

    func ensureAIChatThreadSelection() {
        if aiChatThreads.isEmpty {
            createAIChatThread(focusInput: false)
            return
        }
        if activeAIChatThreadIndex() == nil {
            activeAIChatThreadID = aiChatThreads.first?.id
        }
    }

    func resolvedScopedCards(
        for scope: AIChatThreadScope,
        allCards: [AIChatCardSnapshot]
    ) -> [AIChatCardSnapshot] {
        let visibleCards = allCards.filter { !$0.isArchived && !$0.isFloating }
        let resolvedScopeType = scope.type.normalizedForCurrentUI

        func cards(for ids: [UUID]) -> [AIChatCardSnapshot] {
            let idSet = Set(ids)
            return visibleCards.filter { idSet.contains($0.id) }
        }

        var resolved: [AIChatCardSnapshot]
        switch resolvedScopeType {
        case .selectedCards, .multiSelection:
            let fallbackIDs: [UUID]
            let liveSelectionIDs = currentSelectedCardIDsForAIContext()
            if !liveSelectionIDs.isEmpty {
                fallbackIDs = liveSelectionIDs
            } else if !scope.cardIDs.isEmpty {
                fallbackIDs = scope.cardIDs
            } else {
                fallbackIDs = []
            }
            resolved = cards(for: fallbackIDs)
        case .parentAndChildren:
            resolved = []
        case .plotLine:
            resolved = visibleCards.filter { $0.category == ScenarioCardCategory.plot }
        case .noteLine:
            resolved = visibleCards.filter { $0.category == ScenarioCardCategory.note }
        }

        if resolved.isEmpty {
            return Array(visibleCards.prefix(24))
        }
        return resolved.sorted {
            if $0.orderIndex != $1.orderIndex { return $0.orderIndex < $1.orderIndex }
            return $0.createdAt < $1.createdAt
        }
    }

    func scopeLabel(for scope: AIChatThreadScope, cardCount: Int) -> String {
        "\(scope.type.normalizedForCurrentUI.rawValue) (\(cardCount)개 카드)"
    }

    func applyScopeToActiveThread(_ type: AIChatScopeType) {
        guard let threadID = activeAIChatThreadID else { return }
        cancelAIChatRequest()
        var newScope = AIChatThreadScope(type: type, cardIDs: [], includeChildrenDepth: 0)
        switch type {
        case .selectedCards:
            newScope.cardIDs = currentSelectedCardIDsForAIContext()
        case .multiSelection, .parentAndChildren:
            newScope.type = .selectedCards
            newScope.cardIDs = currentSelectedCardIDsForAIContext()
        case .plotLine, .noteLine:
            break
        }

        updateAIChatThread(threadID) { thread in
            thread.scope = newScope
        }
        aiLastContextPreview = nil
        setAIStatus("스레드 범위를 '\(type.rawValue)'로 설정했습니다.")
    }

    func syncSelectedScopeForThread(_ threadID: UUID) {
        guard let index = aiChatThreads.firstIndex(where: { $0.id == threadID }) else { return }
        guard aiChatThreads[index].scope.type.normalizedForCurrentUI == .selectedCards else { return }

        let latestSelectionIDs = currentSelectedCardIDsForAIContext()
        guard !latestSelectionIDs.isEmpty else { return }

        if Set(aiChatThreads[index].scope.cardIDs) == Set(latestSelectionIDs) {
            return
        }

        updateAIChatThread(threadID) { thread in
            thread.scope.type = .selectedCards
            thread.scope.cardIDs = latestSelectionIDs
            thread.scope.includeChildrenDepth = 0
        }
    }

    func syncActiveThreadSelectedScopeWithCurrentSelection() {
        guard let threadID = activeAIChatThreadID else { return }
        syncSelectedScopeForThread(threadID)
    }
}
