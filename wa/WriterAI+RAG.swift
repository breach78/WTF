import SwiftUI

extension ScenarioWriterView {
    func resolvedRAGEmbeddingModelCandidates(preferredModel: String? = nil) -> [String] {
        var candidates: [String] = []
        if let preferredModel {
            let trimmed = preferredModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                candidates.append(trimmed)
            }
        }
        let loadedModel = aiEmbeddingIndexModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !loadedModel.isEmpty, !candidates.contains(loadedModel) {
            candidates.append(loadedModel)
        }
        for fallback in aiRAGEmbeddingModelCandidates where !candidates.contains(fallback) {
            candidates.append(fallback)
        }
        if candidates.isEmpty {
            candidates = ["gemini-embedding-001"]
        }
        return candidates
    }

    func clippedEmbeddingInput(for card: AIChatCardSnapshot) -> String {
        let raw = "[\(card.category)]\n\(card.content)"
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxLength = 1800
        if normalized.count <= maxLength { return normalized }
        let index = normalized.index(normalized.startIndex, offsetBy: maxLength)
        return String(normalized[..<index])
    }

    func ragTokens(from text: String) -> [String] {
        sharedSearchTokensValue(from: text)
    }

    private func vectorStoreDocuments(
        cards: [AIChatCardSnapshot],
        digests: [UUID: AICardDigest],
        embeddings: [UUID: AIEmbeddingRecord]
    ) -> [AIVectorSQLiteStore.Document] {
        cards.compactMap { card in
            guard let digest = digests[card.id] else { return nil }
            guard let embedding = embeddings[card.id], !embedding.vector.isEmpty else { return nil }
            let mergedSearchText = [
                card.category,
                digest.shortSummary,
                digest.keyFacts.joined(separator: " "),
                clippedEmbeddingInput(for: card)
            ]
            .joined(separator: " ")
            let tokens = ragTokens(from: mergedSearchText)
            let tokenTF = Dictionary(tokens.map { ($0, 1) }, uniquingKeysWith: +)
            return AIVectorSQLiteStore.Document(
                cardID: card.id,
                contentHash: embedding.contentHash,
                category: card.category,
                orderIndex: card.orderIndex,
                updatedAt: embedding.updatedAt,
                vector: embedding.vector,
                searchText: mergedSearchText,
                tokenTF: tokenTF
            )
        }
    }

    func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double {
        guard !lhs.isEmpty, lhs.count == rhs.count else { return 0 }
        var dot: Double = 0
        var lhsNormSquared: Double = 0
        var rhsNormSquared: Double = 0
        for index in lhs.indices {
            let l = Double(lhs[index])
            let r = Double(rhs[index])
            dot += l * r
            lhsNormSquared += l * l
            rhsNormSquared += r * r
        }
        guard lhsNormSquared > 0, rhsNormSquared > 0 else { return 0 }
        return dot / (sqrt(lhsNormSquared) * sqrt(rhsNormSquared))
    }

    func requestEmbeddingsForTexts(
        _ texts: [String],
        apiKey: String,
        taskType: String,
        modelCandidates: [String],
        requestTimeout: TimeInterval
    ) async throws -> (vectors: [[Float]], model: String) {
        guard !texts.isEmpty else {
            return ([], modelCandidates.first ?? "gemini-embedding-001")
        }

        var lastError: Error?
        for model in modelCandidates {
            do {
                if texts.count == 1 {
                    let vector = try await GeminiService.embedText(
                        texts[0],
                        model: model,
                        apiKey: apiKey,
                        taskType: taskType,
                        requestTimeout: requestTimeout
                    )
                    return ([vector], model)
                }

                let chunkSize = 24
                var merged: [[Float]] = []
                merged.reserveCapacity(texts.count)
                var start = 0
                while start < texts.count {
                    let end = min(start + chunkSize, texts.count)
                    let chunk = Array(texts[start..<end])
                    let chunkVectors = try await GeminiService.batchEmbedTexts(
                        chunk,
                        model: model,
                        apiKey: apiKey,
                        taskType: taskType,
                        requestTimeout: requestTimeout
                    )
                    guard chunkVectors.count == chunk.count else {
                        throw GeminiServiceError.invalidResponse
                    }
                    merged.append(contentsOf: chunkVectors)
                    start = end
                }
                return (merged, model)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? GeminiServiceError.invalidResponse
    }

    func buildSemanticRAGContext(
        query: String,
        allCards: [AIChatCardSnapshot],
        scopedCards: [AIChatCardSnapshot],
        digests: [UUID: AICardDigest],
        existingIndex: [UUID: AIEmbeddingRecord],
        apiKey: String,
        vectorDBURL: URL
    ) async -> (semanticContext: String?, updatedIndex: [UUID: AIEmbeddingRecord], resolvedModel: String?) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return (nil, existingIndex, nil)
        }

        let visibleCards = allCards.filter { !$0.isArchived && !$0.isFloating }
        guard !visibleCards.isEmpty else {
            return (nil, existingIndex, nil)
        }

        var updatedIndex = existingIndex
        let validIDs = Set(visibleCards.map(\.id))
        for cardID in Array(updatedIndex.keys) where !validIDs.contains(cardID) {
            updatedIndex.removeValue(forKey: cardID)
        }

        var cardsToEmbed: [AIChatCardSnapshot] = []
        cardsToEmbed.reserveCapacity(visibleCards.count)
        for card in visibleCards {
            let contentHash = card.content.trimmingCharacters(in: .whitespacesAndNewlines).hashValue
            if let existing = updatedIndex[card.id],
               existing.contentHash == contentHash,
               !existing.vector.isEmpty {
                continue
            }
            cardsToEmbed.append(card)
        }

        var embeddingModelUsed: String? = nil
        let modelCandidates = resolvedRAGEmbeddingModelCandidates()
        if !cardsToEmbed.isEmpty {
            let texts = cardsToEmbed.map { clippedEmbeddingInput(for: $0) }
            do {
                let result = try await requestEmbeddingsForTexts(
                    texts,
                    apiKey: apiKey,
                    taskType: "RETRIEVAL_DOCUMENT",
                    modelCandidates: modelCandidates,
                    requestTimeout: 80
                )
                let vectors = result.vectors
                guard vectors.count == cardsToEmbed.count else {
                    return (nil, existingIndex, nil)
                }
                embeddingModelUsed = result.model
                for (index, card) in cardsToEmbed.enumerated() {
                    let vector = vectors[index]
                    guard !vector.isEmpty else { continue }
                    let contentHash = card.content.trimmingCharacters(in: .whitespacesAndNewlines).hashValue
                    updatedIndex[card.id] = AIEmbeddingRecord(
                        cardID: card.id,
                        contentHash: contentHash,
                        vector: vector,
                        updatedAt: Date()
                    )
                }
            } catch {
                return (nil, existingIndex, nil)
            }
        }

        let validCardIDs = Set(visibleCards.map(\.id))
        let sqliteDocuments = vectorStoreDocuments(cards: visibleCards, digests: digests, embeddings: updatedIndex)
        if !sqliteDocuments.isEmpty {
            do {
                try await AIVectorSQLiteStore.shared.syncIndex(
                    dbURL: vectorDBURL,
                    documents: sqliteDocuments,
                    validCardIDs: validCardIDs
                )
            } catch {
                // Keep chat flow alive even if local vector store maintenance fails.
            }
        }

        let resolvedModelCandidates = resolvedRAGEmbeddingModelCandidates(preferredModel: embeddingModelUsed)
        var queryVector: [Float] = []
        var queryModel: String? = nil
        do {
            let result = try await requestEmbeddingsForTexts(
                [trimmedQuery],
                apiKey: apiKey,
                taskType: "RETRIEVAL_QUERY",
                modelCandidates: resolvedModelCandidates,
                requestTimeout: 45
            )
            queryVector = result.vectors.first ?? []
            queryModel = result.model
        } catch {
            queryVector = []
        }

        guard !queryVector.isEmpty else {
            return (nil, updatedIndex, embeddingModelUsed)
        }

        let scopedIDSet = Set(scopedCards.map(\.id))
        let queryTokens = ragTokens(from: trimmedQuery)
        let candidateLimit = max(aiRAGTopCardCount * 24, 140)
        let lexicalCandidates: [UUID]
        if queryTokens.isEmpty {
            lexicalCandidates = []
        } else {
            lexicalCandidates = (try? await AIVectorSQLiteStore.shared.queryCandidateIDs(
                dbURL: vectorDBURL,
                queryTokens: queryTokens,
                limit: candidateLimit
            )) ?? []
        }
        let candidateIDSet = Set(lexicalCandidates)
        let retrievalCards = candidateIDSet.isEmpty
            ? visibleCards
            : visibleCards.filter { candidateIDSet.contains($0.id) }

        var scoredCards: [(card: AIChatCardSnapshot, score: Double)] = []
        scoredCards.reserveCapacity(retrievalCards.count)
        for card in retrievalCards {
            guard let record = updatedIndex[card.id], !record.vector.isEmpty else { continue }
            guard record.vector.count == queryVector.count else { continue }
            var score = cosineSimilarity(queryVector, record.vector)
            guard score > 0 else { continue }
            if scopedIDSet.contains(card.id) {
                score += 0.08
            }
            scoredCards.append((card: card, score: score))
        }

        guard !scoredCards.isEmpty else {
            return (nil, updatedIndex, queryModel ?? embeddingModelUsed)
        }

        scoredCards.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.card.orderIndex != rhs.card.orderIndex { return lhs.card.orderIndex < rhs.card.orderIndex }
            return lhs.card.createdAt < rhs.card.createdAt
        }

        let topCards = scoredCards.prefix(aiRAGTopCardCount)
        var lines: [String] = []
        var budget = 0
        let maxBudget = 900
        for item in topCards {
            guard let digest = digests[item.card.id] else { continue }
            let marker = scopedIDSet.contains(item.card.id) ? "선택 연관" : "질문 연관"
            let facts = digest.keyFacts.prefix(2).joined(separator: " / ")
            let scoreText = String(format: "%.2f", min(max(item.score, 0), 0.99))
            let line = facts.isEmpty
                ? "[\(marker)][\(item.card.category)] \(digest.shortSummary) (유사도 \(scoreText))"
                : "[\(marker)][\(item.card.category)] \(digest.shortSummary) | \(facts) (유사도 \(scoreText))"
            let next = budget + line.count + 1
            if next > maxBudget { break }
            lines.append(line)
            budget = next
        }

        guard !lines.isEmpty else {
            return (nil, updatedIndex, queryModel ?? embeddingModelUsed)
        }
        return (lines.joined(separator: "\n"), updatedIndex, queryModel ?? embeddingModelUsed)
    }

    private struct AIChatRequestSnapshot {
        let threadID: UUID
        let requestID: UUID
        let allCardSnapshots: [AIChatCardSnapshot]
        let scopedCards: [AIChatCardSnapshot]
        let scopeText: String
        let historySnapshots: [AIChatMessageSnapshot]
        let lastUserQuestion: String
        let shouldRefreshRollingSummary: Bool
        let previousRollingSummary: String
        let digestCacheSnapshot: [UUID: AICardDigest]
        let embeddingIndexSnapshot: [UUID: AIEmbeddingRecord]
        let vectorDBURL: URL
        let resolvedModel: String
    }

    private func makeAIChatRequestSnapshot(for threadID: UUID) -> AIChatRequestSnapshot? {
        cancelAIChatRequest()
        syncSelectedScopeForThread(threadID)
        guard let thread = aiChatThreads.first(where: { $0.id == threadID }) else { return nil }

        let allCardSnapshots = aiAllCardSnapshots()
        let scopedCards = resolvedScopedCards(for: thread.scope, allCards: allCardSnapshots)
        let scopeText = scopeLabel(for: thread.scope, cardCount: scopedCards.count)
        let historySnapshots = messagesForAIThread(threadID).map { message in
            AIChatMessageSnapshot(role: message.role, text: message.text)
        }
        let lastUserQuestion = historySnapshots.last(where: { $0.role == "user" })?.text ?? ""
        let userTurnCount = historySnapshots.filter { $0.role == "user" }.count
        let shouldRefreshRollingSummary = thread.rollingSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || userTurnCount % 4 == 0
        return AIChatRequestSnapshot(
            threadID: threadID,
            requestID: UUID(),
            allCardSnapshots: allCardSnapshots,
            scopedCards: scopedCards,
            scopeText: scopeText,
            historySnapshots: historySnapshots,
            lastUserQuestion: lastUserQuestion,
            shouldRefreshRollingSummary: shouldRefreshRollingSummary,
            previousRollingSummary: thread.rollingSummary,
            digestCacheSnapshot: aiCardDigestCache,
            embeddingIndexSnapshot: aiEmbeddingIndexByCardID,
            vectorDBURL: store.aiVectorIndexURL(for: scenario.id),
            resolvedModel: currentGeminiModel()
        )
    }

    private func applyPreparedAIChatState(
        requestID: UUID,
        threadID: UUID,
        preparedContext: AIChatPromptBuildResult?,
        preparedEmbeddingIndex: [UUID: AIEmbeddingRecord],
        preparedEmbeddingModel: String
    ) {
        guard aiChatActiveRequestID == requestID else { return }
        guard let preparedContext else { return }
        aiCardDigestCache = preparedContext.updatedDigestCache
        aiEmbeddingIndexByCardID = preparedEmbeddingIndex
        aiEmbeddingIndexModelID = preparedEmbeddingModel
        scheduleAIEmbeddingPersistence()
        aiLastContextPreview = preparedContext.contextPreview
        updateAIChatThread(threadID) { thread in
            thread.rollingSummary = preparedContext.rollingSummary
        }
    }

    private func finishAIChatSuccess(
        requestID: UUID,
        threadID: UUID,
        buildResult: AIChatPromptBuildResult,
        preparedEmbeddingIndex: [UUID: AIEmbeddingRecord],
        preparedEmbeddingModel: String,
        response: AIChatResponseResult
    ) {
        guard aiChatActiveRequestID == requestID else { return }
        aiCardDigestCache = buildResult.updatedDigestCache
        aiEmbeddingIndexByCardID = preparedEmbeddingIndex
        aiEmbeddingIndexModelID = preparedEmbeddingModel
        scheduleAIEmbeddingPersistence()
        aiLastContextPreview = buildResult.contextPreview
        updateAIChatThread(threadID) { thread in
            thread.rollingSummary = buildResult.rollingSummary
            var totalUsage = thread.tokenUsage ?? .zero
            totalUsage.add(response.usage)
            thread.tokenUsage = totalUsage
        }
        appendAIChatMessage(AIChatMessage(role: "model", text: response.text), to: threadID)
        finishAIChatRequest()
    }

    func requestAIChatResponse(for threadID: UUID) {
        guard let snapshot = makeAIChatRequestSnapshot(for: threadID) else { return }

        isAIChatLoading = true
        aiChatActiveRequestID = snapshot.requestID
        setAIStatus(nil)

        aiChatRequestTask = Task {
            var preparedContext: AIChatPromptBuildResult?
            var preparedEmbeddingIndex = snapshot.embeddingIndexSnapshot
            var preparedEmbeddingModel = aiEmbeddingIndexModelID
            do {
                let apiKey = try loadGeminiAPIKeyForChat()
                let semanticRAG = await buildSemanticRAGContext(
                    query: snapshot.lastUserQuestion,
                    allCards: snapshot.allCardSnapshots,
                    scopedCards: snapshot.scopedCards,
                    digests: snapshot.digestCacheSnapshot,
                    existingIndex: snapshot.embeddingIndexSnapshot,
                    apiKey: apiKey,
                    vectorDBURL: snapshot.vectorDBURL
                )
                preparedEmbeddingIndex = semanticRAG.updatedIndex
                if let resolvedEmbeddingModel = semanticRAG.resolvedModel {
                    preparedEmbeddingModel = resolvedEmbeddingModel
                }

                let buildResult = AIChatPromptBuilder.buildPrompt(
                    allCards: snapshot.allCardSnapshots,
                    scopedCards: snapshot.scopedCards,
                    scopeLabel: snapshot.scopeText,
                    history: snapshot.historySnapshots,
                    lastUserMessage: snapshot.lastUserQuestion,
                    previousRollingSummary: snapshot.previousRollingSummary,
                    digestCache: snapshot.digestCacheSnapshot,
                    refreshRollingSummary: snapshot.shouldRefreshRollingSummary,
                    semanticRAGContext: semanticRAG.semanticContext
                )
                preparedContext = buildResult
                try Task.checkCancellation()

                let response = try await requestGeminiChatResponse(
                    prompt: buildResult.prompt,
                    apiKey: apiKey,
                    model: snapshot.resolvedModel
                )
                try Task.checkCancellation()

                await MainActor.run {
                    finishAIChatSuccess(
                        requestID: snapshot.requestID,
                        threadID: snapshot.threadID,
                        buildResult: buildResult,
                        preparedEmbeddingIndex: preparedEmbeddingIndex,
                        preparedEmbeddingModel: preparedEmbeddingModel,
                        response: response
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    applyPreparedAIChatState(
                        requestID: snapshot.requestID,
                        threadID: snapshot.threadID,
                        preparedContext: preparedContext,
                        preparedEmbeddingIndex: preparedEmbeddingIndex,
                        preparedEmbeddingModel: preparedEmbeddingModel
                    )
                    finishAIChatRequest()
                }
            } catch {
                await MainActor.run {
                    applyPreparedAIChatState(
                        requestID: snapshot.requestID,
                        threadID: snapshot.threadID,
                        preparedContext: preparedContext,
                        preparedEmbeddingIndex: preparedEmbeddingIndex,
                        preparedEmbeddingModel: preparedEmbeddingModel
                    )
                    guard aiChatActiveRequestID == snapshot.requestID else { return }
                    setAIStatusError(error.localizedDescription)
                    appendAIChatMessage(
                        AIChatMessage(role: "model", text: "오류가 발생했습니다: \(error.localizedDescription)"),
                        to: snapshot.threadID
                    )
                    finishAIChatRequest()
                }
            }
        }
    }

    func cancelAIChatRequest(showMessage: Bool = false) {
        aiChatRequestTask?.cancel()
        aiChatRequestTask = nil
        aiChatActiveRequestID = nil
        if isAIChatLoading {
            isAIChatLoading = false
            if showMessage {
                setAIStatus("AI 요청을 중단했습니다.")
            }
        }
    }

    func finishAIChatRequest() {
        aiChatRequestTask = nil
        aiChatActiveRequestID = nil
        isAIChatLoading = false
    }

    func loadGeminiAPIKeyForChat() throws -> String {
        guard let apiKey = try KeychainStore.loadGeminiAPIKey() else {
            throw GeminiServiceError.missingAPIKey
        }
        return apiKey
    }

    private func requestGeminiChatResponse(
        prompt: String,
        apiKey: String,
        model: String
    ) async throws -> AIChatResponseResult {
        let maxContinuationChunks = 4
        var continuationPrompt = prompt
        var mergedResponse = ""
        var generatedChunks = 0
        var accumulatedUsage = AIChatTokenUsage.zero

        while true {
            try Task.checkCancellation()
            let chunk = try await requestGeminiChatChunk(
                prompt: continuationPrompt,
                apiKey: apiKey,
                model: model
            )

            mergedResponse = mergeContinuationResponse(existing: mergedResponse, incoming: chunk.text)
            accumulatedUsage.add(aiTokenUsage(from: chunk.usage))
            generatedChunks += 1

            let finishReason = chunk.finishReason?.uppercased()
            let wasTruncated = finishReason == "MAX_TOKENS"
            guard wasTruncated, generatedChunks < maxContinuationChunks else {
                break
            }

            continuationPrompt = continuationPromptForChat(
                originalPrompt: prompt,
                partialResponse: mergedResponse
            )
        }

        let finalResponse = mergedResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalResponse.isEmpty else {
            throw GeminiServiceError.invalidResponse
        }
        return AIChatResponseResult(text: finalResponse, usage: accumulatedUsage)
    }

    func requestGeminiChatChunk(
        prompt: String,
        apiKey: String,
        model: String
    ) async throws -> GeminiService.TextGenerationResult {
        let attempts: [(timeout: TimeInterval, maxOutputTokens: Int?)] = [
            (75, nil),
            (120, nil)
        ]
        var lastError: Error?

        for (index, attempt) in attempts.enumerated() {
            try Task.checkCancellation()
            do {
                return try await GeminiService.generateTextWithMetadata(
                    prompt: prompt,
                    model: model,
                    apiKey: apiKey,
                    maxOutputTokens: attempt.maxOutputTokens,
                    requestTimeout: attempt.timeout,
                    temperature: 0.95,
                    topP: 0.95
                )
            } catch {
                if error is CancellationError {
                    throw error
                }
                lastError = error
                let isTimeout = (error as? URLError)?.code == .timedOut
                    || error.localizedDescription.localizedCaseInsensitiveContains("timed out")
                guard isTimeout, index < attempts.count - 1 else {
                    throw error
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }

        throw lastError ?? GeminiServiceError.invalidResponse
    }

    func aiTokenUsage(from usage: GeminiService.TokenUsage) -> AIChatTokenUsage {
        AIChatTokenUsage(
            promptTokens: max(usage.promptTokens, 0),
            outputTokens: max(usage.outputTokens, 0),
            totalTokens: max(usage.totalTokens, 0)
        )
    }

    func continuationPromptForChat(
        originalPrompt: String,
        partialResponse: String
    ) -> String {
        let responseTail = String(partialResponse.suffix(1400))
        return """
        \(originalPrompt)

        [중요]
        이전 출력이 길이 제한으로 중간에 끊겼습니다.
        아래는 이미 출력된 답변의 마지막 부분입니다.
        \"\"\"
        \(responseTail)
        \"\"\"
        위 문장 바로 다음 문장부터 이어서 작성하세요.
        - 이미 출력된 내용 반복 금지
        - 번호를 처음부터 다시 시작 금지
        - 사과/메타 설명 금지
        """
    }

    func mergeContinuationResponse(existing: String, incoming: String) -> String {
        let left = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty else { return right }
        guard !right.isEmpty else { return left }

        let maxOverlap = min(280, min(left.count, right.count))
        var overlapLength = 0
        if maxOverlap >= 20 {
            for length in stride(from: maxOverlap, through: 20, by: -1) {
                if left.suffix(length) == right.prefix(length) {
                    overlapLength = length
                    break
                }
            }
        }

        let mergedRight = overlapLength > 0 ? String(right.dropFirst(overlapLength)) : right
        guard !mergedRight.isEmpty else { return left }
        return left + "\n" + mergedRight
    }
}
