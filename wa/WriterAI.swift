import SwiftUI
import SQLite3

struct AIChatMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let role: String // "user" or "model"
    let text: String

    init(id: UUID = UUID(), role: String, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

enum AIChatThreadMode: String, CaseIterable, Codable, Sendable {
    case discussion = "논의"
    case structure = "구조 점검"
    case rewrite = "수정"
}

enum AIChatScopeType: String, CaseIterable, Codable, Sendable {
    case selectedCards = "선택 카드"
    case multiSelection = "다중 선택"
    case parentAndChildren = "부모+자식"
    case plotLine = "플롯 전체"
    case noteLine = "노트 전체"

    var normalizedForCurrentUI: AIChatScopeType {
        switch self {
        case .multiSelection, .parentAndChildren:
            return .selectedCards
        case .selectedCards, .plotLine, .noteLine:
            return self
        }
    }
}

struct AIChatThreadScope: Codable, Sendable {
    var type: AIChatScopeType = .selectedCards
    var cardIDs: [UUID] = []
    var includeChildrenDepth: Int = 1
}

struct AIChatThread: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    var mode: AIChatThreadMode
    var scope: AIChatThreadScope
    var messages: [AIChatMessage]
    var rollingSummary: String
    var decisionLog: [String]
    var unresolvedQuestions: [String]
    var tokenUsage: AIChatTokenUsage? = nil
    var updatedAt: Date
}

struct AIChatThreadStorePayload: Codable, Sendable {
    var threads: [AIChatThread]
    var activeThreadID: UUID?
}

struct AIChatMessageSnapshot: Sendable {
    let role: String
    let text: String
}

struct AIChatCardSnapshot: Sendable {
    let id: UUID
    let parentID: UUID?
    let category: String
    let content: String
    let orderIndex: Int
    let createdAt: Date
    let isArchived: Bool
    let isFloating: Bool
}

struct AICardDigest: Sendable {
    let cardID: UUID
    let contentHash: Int
    let shortSummary: String
    let keyFacts: [String]
    let updatedAt: Date
}

struct AIEmbeddingRecord: Codable, Sendable {
    let cardID: UUID
    var contentHash: Int
    var vector: [Float]
    var updatedAt: Date
}

struct AIChatTokenUsage: Codable, Sendable {
    var promptTokens: Int
    var outputTokens: Int
    var totalTokens: Int

    static let zero = AIChatTokenUsage(promptTokens: 0, outputTokens: 0, totalTokens: 0)

    mutating func add(_ usage: AIChatTokenUsage) {
        promptTokens += usage.promptTokens
        outputTokens += usage.outputTokens
        totalTokens += usage.totalTokens
    }
}

struct AIEmbeddingIndexPayload: Codable, Sendable {
    var model: String
    var records: [AIEmbeddingRecord]
    var updatedAt: Date
}

struct AIChatContextPreview: Sendable {
    let scopeLabel: String
    let scopedContext: String
    let ragContext: String
    let globalPlotSummary: String
    let globalNoteSummary: String
    let rollingSummary: String
    let historySummary: String
}

struct AIChatPromptBuildResult: Sendable {
    let prompt: String
    let updatedDigestCache: [UUID: AICardDigest]
    let rollingSummary: String
    let contextPreview: AIChatContextPreview
}

struct AIChatResponseResult: Sendable {
    let text: String
    let usage: AIChatTokenUsage
}

enum AIChatPromptBuilder {
    private static let maxScopedContextLength = 1200
    private static let maxRAGContextLength = 900
    private static let maxGlobalLaneSummaryLength = 500
    private static let maxHistorySummaryLength = 700
    private static let maxRollingSummaryLength = 520
    private static let maxQuestionLength = 600
    private static let maxCardSummaryLength = 140
    private static let maxKeyFactLength = 44
    private static let maxHistoryMessages = 10
    private static let maxRAGCards = 8

    static func buildPrompt(
        allCards: [AIChatCardSnapshot],
        scopedCards: [AIChatCardSnapshot],
        scopeLabel: String,
        history: [AIChatMessageSnapshot],
        lastUserMessage: String,
        previousRollingSummary: String,
        digestCache: [UUID: AICardDigest],
        refreshRollingSummary: Bool,
        semanticRAGContext: String? = nil
    ) -> AIChatPromptBuildResult {
        var resolvedDigestCache = digestCache
        let visibleCards = allCards.filter { !$0.isArchived && !$0.isFloating }
        for card in visibleCards {
            resolvedDigestCache[card.id] = buildDigest(for: card, cached: resolvedDigestCache[card.id])
        }

        let scopedContext = buildScopedContext(from: scopedCards, digests: resolvedDigestCache)
        let globalPlotSummary = buildGlobalLaneSummary(from: visibleCards, digests: resolvedDigestCache, category: ScenarioCardCategory.plot)
        let globalNoteSummary = buildGlobalLaneSummary(from: visibleCards, digests: resolvedDigestCache, category: ScenarioCardCategory.note)
        let historySummary = buildHistorySummary(from: history)
        let rollingSummary: String
        if refreshRollingSummary {
            rollingSummary = buildRollingSummary(previous: previousRollingSummary, history: history)
        } else {
            let preserved = previousRollingSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            rollingSummary = preserved.isEmpty
                ? buildRollingSummary(previous: previousRollingSummary, history: history)
                : preserved
        }
        let compactQuestion = clamp(lastUserMessage, maxLength: maxQuestionLength, preserveLineBreak: true)
        let ragContext = semanticRAGContext ?? buildRAGContext(
            query: lastUserMessage,
            allCards: visibleCards,
            scopedCards: scopedCards,
            digests: resolvedDigestCache
        )

        let prompt = """
        AI 시나리오 컨설턴트 시스템 프롬프트

        [역할 및 정체성 (Role & Identity)]
        당신은 업계 최고 수준의 시나리오 컨설턴트이자 크리에이티브 파트너(Dramaturge)다.
        목표는 작가가 스스로도 깨닫지 못한 이야기의 잠재력을 끌어내고, 뻔한 전개를 경계하며, 작품의 밀도를 영화적 완성도까지 끌어올리는 것이다.
        예의 바르되 비평에는 타협이 없고, 막힌 벽을 부술 수 있는 예리한 통찰을 제공한다.

        [컨텍스트 인지 및 작동 방식 (Context Processing)]
        - 카드 시스템 이해: 작가는 플롯, 노트, 캐릭터 등이 담긴 여러 장의 카드를 제공한다.
        - 거시와 미시의 교차: 전체 카드의 큰 흐름과 주제를 항상 배경에서 파악하고, 선택 카드(들)의 세부 변화가 전체 스토리라인에 미치는 영향을 계산해 답한다.
        - 질문 맞춤형 응답: 작가가 묻지 않은 모든 것을 늘어놓지 않고, 질문 의도에 맞는 깊이만 간결하고 임팩트 있게 제시한다.

        [핵심 덕목 및 스킬셋 (Core Virtues & Skillset)]
        - 핵심 관통: 곁가지를 걷어내고 이 씬/플롯이 진짜 말하고자 하는 바를 짚는다.
        - 클리셰 파괴와 반전: 뻔한 A->B 대신, 예상은 빗나가되 논리적으로 맞아떨어지는 C 경로를 제안한다.
        - 갈등과 텐션 극대화: 캐릭터를 더 깊은 딜레마로 밀어 넣고, 씬의 긴장감을 폭발시킬 변수를 찾는다.
        - 영감의 촉매제: 막혔을 때 정답 주입 대신, 사고를 확장시키는 도발적 What if 질문을 던진다.
        - 시청각적 상상력: 텍스트를 넘어 화면의 이미지, 사운드, 공간 무드까지 함께 제안한다.

        [대화 태도 (Tone & Manner)]
        - 작가의 창작물에 깊은 애정과 존중을 가진다.
        - 영혼 없는 칭찬은 피하고, 좋은 점은 왜 작동하는지 분석하며, 아쉬운 점은 대안과 함께 날카롭게 지적한다.
        - 동료 전문가와 회의실에서 아이디어를 핑퐁하는 듯 지적이고 에너제틱한 톤을 유지한다.

        [실시간 프로젝트 컨텍스트]
        [현재 스레드 범위]
        \(scopeLabel)

        [현재 턴 핵심 컨텍스트]
        \(scopedContext)

        [질문 연관 카드(RAG)]
        \(ragContext)

        [전역 플롯 라인 요약]
        \(globalPlotSummary)

        [전역 노트 라인 요약]
        \(globalNoteSummary)

        [스레드 롤링 요약]
        \(rollingSummary)

        [최근 대화 요약]
        \(historySummary)

        [사용자의 마지막 질문]
        \(compactQuestion)

        [응답 규칙]
        - 반드시 한국어로 답한다.
        - 질문에 대한 본문 답변만 출력한다.
        - 결과는 핵심만 간략하게 제시한다. 장황한 설명은 금지한다.
        - 사용자가 길이를 명시하지 않으면 기본 분량은 3~6문장으로 제한한다.
        - 제목/섹션 번호/군더더기 설명은 작가가 명시적으로 요청한 경우에만 사용한다.
        - 문장은 중간에 끊지 말고 완결된 형태로 마무리한다.
        - 플롯 라인, 노트 라인, 캐릭터 설정 간 일관성을 우선한다.
        - 코드블록/JSON은 사용하지 않는다.
        """

        let preview = AIChatContextPreview(
            scopeLabel: scopeLabel,
            scopedContext: scopedContext,
            ragContext: ragContext,
            globalPlotSummary: globalPlotSummary,
            globalNoteSummary: globalNoteSummary,
            rollingSummary: rollingSummary,
            historySummary: historySummary
        )

        return AIChatPromptBuildResult(
            prompt: prompt,
            updatedDigestCache: resolvedDigestCache,
            rollingSummary: rollingSummary,
            contextPreview: preview
        )
    }

    private static func buildDigest(for card: AIChatCardSnapshot, cached: AICardDigest?) -> AICardDigest {
        let normalizedContent = card.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let hash = normalizedContent.hashValue
        if let cached, cached.contentHash == hash {
            return cached
        }
        let summary = clamp(normalizedContent, maxLength: maxCardSummaryLength, preserveLineBreak: false)
        let keyFacts = extractKeyFacts(from: normalizedContent)
        return AICardDigest(
            cardID: card.id,
            contentHash: hash,
            shortSummary: summary,
            keyFacts: keyFacts,
            updatedAt: Date()
        )
    }

    private static func buildScopedContext(
        from scopedCards: [AIChatCardSnapshot],
        digests: [UUID: AICardDigest]
    ) -> String {
        let orderedCards = scopedCards
            .filter { !$0.isArchived && !$0.isFloating }
            .sorted {
                if $0.orderIndex != $1.orderIndex { return $0.orderIndex < $1.orderIndex }
                return $0.createdAt < $1.createdAt
            }
        if orderedCards.isEmpty { return "(범위 내 카드 없음)" }

        var lines: [String] = []
        var lengthBudget = 0
        for card in orderedCards {
            guard let digest = digests[card.id] else { continue }
            let facts = digest.keyFacts.prefix(3).joined(separator: " / ")
            let line = facts.isEmpty
                ? "[\(card.category)] \(digest.shortSummary)"
                : "[\(card.category)] \(digest.shortSummary) | \(facts)"
            let nextLength = lengthBudget + line.count + 1
            if nextLength > maxScopedContextLength { break }
            lines.append(line)
            lengthBudget = nextLength
        }

        if lines.isEmpty { return "(범위 내 카드 없음)" }
        if lines.count < orderedCards.count { lines.append("... (범위 컨텍스트 생략)") }
        return lines.joined(separator: "\n")
    }

    private static func buildGlobalLaneSummary(
        from cards: [AIChatCardSnapshot],
        digests: [UUID: AICardDigest],
        category: String
    ) -> String {
        let laneCards = cards
            .filter { $0.category == category }
            .sorted {
                if $0.orderIndex != $1.orderIndex { return $0.orderIndex < $1.orderIndex }
                return $0.createdAt < $1.createdAt
            }
        if laneCards.isEmpty { return "(해당 라인 없음)" }

        var lines: [String] = []
        var lengthBudget = 0
        for card in laneCards {
            guard let digest = digests[card.id] else { continue }
            let line = "- \(digest.shortSummary)"
            let nextLength = lengthBudget + line.count + 1
            if nextLength > maxGlobalLaneSummaryLength { break }
            lines.append(line)
            lengthBudget = nextLength
        }

        if lines.isEmpty { return "(해당 라인 없음)" }
        if lines.count < laneCards.count { lines.append("... (일부 생략)") }
        return lines.joined(separator: "\n")
    }

    private static func buildRAGContext(
        query: String,
        allCards: [AIChatCardSnapshot],
        scopedCards: [AIChatCardSnapshot],
        digests: [UUID: AICardDigest]
    ) -> String {
        let compactQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compactQuery.isEmpty else { return "(질문이 비어 있어 RAG를 생략함)" }

        let queryTokens = ragTokens(from: compactQuery)
        guard !queryTokens.isEmpty else { return "(질문 토큰 부족으로 RAG를 생략함)" }

        let candidateCards = allCards.filter { !$0.isArchived && !$0.isFloating }
        guard !candidateCards.isEmpty else { return "(검색 가능한 카드 없음)" }

        typealias RAGDoc = (card: AIChatCardSnapshot, tf: [String: Int])
        var docs: [RAGDoc] = []
        var documentFrequency: [String: Int] = [:]

        for card in candidateCards {
            let compactCardText = clamp("\(card.category) \(card.content)", maxLength: 900, preserveLineBreak: false)
            let tokens = ragTokens(from: compactCardText)
            let tf = termFrequency(tokens)
            guard !tf.isEmpty else { continue }
            docs.append((card: card, tf: tf))
            for term in tf.keys {
                documentFrequency[term, default: 0] += 1
            }
        }

        guard !docs.isEmpty else { return "(질문과 비교할 카드 벡터가 없음)" }

        let totalDocs = Double(docs.count)
        func idf(_ term: String) -> Double {
            let df = Double(documentFrequency[term] ?? 0)
            return log((1.0 + totalDocs) / (1.0 + df)) + 1.0
        }

        let queryTF = termFrequency(queryTokens)
        var queryVector: [String: Double] = [:]
        var queryNormSquared: Double = 0
        for (term, count) in queryTF {
            let weight = (1.0 + log(Double(count))) * idf(term)
            queryVector[term] = weight
            queryNormSquared += weight * weight
        }

        let queryNorm = sqrt(queryNormSquared)
        guard queryNorm > 0 else { return "(질문 벡터가 비어 있음)" }

        let scopedIDSet = Set(scopedCards.map(\.id))
        var scored: [(card: AIChatCardSnapshot, score: Double)] = []
        scored.reserveCapacity(docs.count)

        for doc in docs {
            var dot: Double = 0
            var docNormSquared: Double = 0

            for (term, count) in doc.tf {
                let docWeight = (1.0 + log(Double(count))) * idf(term)
                docNormSquared += docWeight * docWeight
                if let queryWeight = queryVector[term] {
                    dot += queryWeight * docWeight
                }
            }

            guard docNormSquared > 0 else { continue }
            var score = dot / (queryNorm * sqrt(docNormSquared))
            if score <= 0 { continue }

            if scopedIDSet.contains(doc.card.id) {
                score += 0.08
            }
            scored.append((card: doc.card, score: score))
        }

        guard !scored.isEmpty else { return "(질문과 강하게 연결된 카드 없음)" }

        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.card.orderIndex != rhs.card.orderIndex { return lhs.card.orderIndex < rhs.card.orderIndex }
            return lhs.card.createdAt < rhs.card.createdAt
        }

        let topCards = Array(scored.prefix(maxRAGCards))
        var lines: [String] = []
        var lengthBudget = 0
        for item in topCards {
            guard let digest = digests[item.card.id] else { continue }
            let marker = scopedIDSet.contains(item.card.id) ? "선택 연관" : "질문 연관"
            let facts = digest.keyFacts.prefix(2).joined(separator: " / ")
            let scoreText = String(format: "%.2f", min(max(item.score, 0), 0.99))
            let line = facts.isEmpty
                ? "[\(marker)][\(item.card.category)] \(digest.shortSummary) (유사도 \(scoreText))"
                : "[\(marker)][\(item.card.category)] \(digest.shortSummary) | \(facts) (유사도 \(scoreText))"
            let nextLength = lengthBudget + line.count + 1
            if nextLength > maxRAGContextLength { break }
            lines.append(line)
            lengthBudget = nextLength
        }

        if lines.isEmpty { return "(질문과 강하게 연결된 카드 없음)" }
        if lines.count < topCards.count { lines.append("... (RAG 결과 일부 생략)") }
        return lines.joined(separator: "\n")
    }

    private static func ragTokens(from text: String) -> [String] {
        sharedSearchTokensValue(from: text)
    }

    private static func termFrequency(_ tokens: [String]) -> [String: Int] {
        var tf: [String: Int] = [:]
        tf.reserveCapacity(tokens.count)
        for token in tokens {
            tf[token, default: 0] += 1
        }
        return tf
    }

    private static func buildHistorySummary(from history: [AIChatMessageSnapshot]) -> String {
        let recentMessages = Array(history.suffix(maxHistoryMessages))
        if recentMessages.isEmpty { return "(대화 없음)" }

        var lines: [String] = []
        var lengthBudget = 0
        for msg in recentMessages {
            let roleName = msg.role == "user" ? "사용자" : "AI"
            let compactText = clamp(msg.text, maxLength: 260, preserveLineBreak: true)
            let line = "\(roleName): \(compactText)"
            let nextLength = lengthBudget + line.count + 2
            if nextLength > maxHistorySummaryLength { break }
            lines.append(line)
            lengthBudget = nextLength
        }
        if lines.isEmpty { return "(대화 없음)" }
        if lines.count < recentMessages.count { lines.insert("... (이전 대화 생략)", at: 0) }
        return lines.joined(separator: "\n\n")
    }

    private static func buildRollingSummary(previous: String, history: [AIChatMessageSnapshot]) -> String {
        let compactPrevious = clamp(previous, maxLength: 320, preserveLineBreak: true)
        let latest = buildHistorySummary(from: Array(history.suffix(6)))
        let merged = [compactPrevious, latest]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "(대화 없음)" }
            .joined(separator: "\n")
        if merged.isEmpty { return "(요약 없음)" }
        return clamp(merged, maxLength: maxRollingSummaryLength, preserveLineBreak: true)
    }

    private static func extractKeyFacts(from text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\n", with: ". ")
        let separators = CharacterSet(charactersIn: ".!?;")
        let chunks = normalized.components(separatedBy: separators)
        var facts: [String] = []
        for chunk in chunks {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 6 else { continue }
            facts.append(clamp(trimmed, maxLength: maxKeyFactLength, preserveLineBreak: false))
            if facts.count >= 4 { break }
        }
        if facts.isEmpty {
            let fallback = clamp(text, maxLength: maxKeyFactLength, preserveLineBreak: false)
            if fallback != "(비어 있음)" {
                facts = [fallback]
            }
        }
        return facts
    }

    private static func clamp(_ text: String, maxLength: Int, preserveLineBreak: Bool) -> String {
        sharedClampTextValue(text, maxLength: maxLength, preserveLineBreak: preserveLineBreak)
    }
}

actor AIVectorSQLiteStore {
    static let shared = AIVectorSQLiteStore()

    struct Document: Sendable {
        let cardID: UUID
        let contentHash: Int
        let category: String
        let orderIndex: Int
        let updatedAt: Date
        let vector: [Float]
        let searchText: String
        let tokenTF: [String: Int]
    }

    enum StoreError: Error {
        case openFailed(String)
        case sqlite(String)
    }

    private var transientDestructor: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    func syncIndex(
        dbURL: URL,
        documents: [Document],
        validCardIDs: Set<UUID>
    ) throws {
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let db = try openDatabase(at: dbURL)
        defer { sqlite3_close(db) }

        try exec(sql: "PRAGMA journal_mode=WAL;", db: db)
        try exec(sql: "PRAGMA synchronous=NORMAL;", db: db)
        try exec(sql: "PRAGMA temp_store=MEMORY;", db: db)
        try createSchema(db: db)

        try exec(sql: "BEGIN IMMEDIATE TRANSACTION;", db: db)
        do {
            let upsertSQL = """
            INSERT INTO embeddings(card_id, content_hash, category, order_index, updated_at, vector, search_text)
            VALUES(?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(card_id) DO UPDATE SET
                content_hash = excluded.content_hash,
                category = excluded.category,
                order_index = excluded.order_index,
                updated_at = excluded.updated_at,
                vector = excluded.vector,
                search_text = excluded.search_text;
            """
            let deleteTokenSQL = "DELETE FROM token_index WHERE card_id = ?;"
            let insertTokenSQL = """
            INSERT INTO token_index(token, card_id, tf)
            VALUES(?, ?, ?)
            ON CONFLICT(token, card_id) DO UPDATE SET tf = excluded.tf;
            """
            let deleteEmbeddingSQL = "DELETE FROM embeddings WHERE card_id = ?;"
            let selectIDsSQL = "SELECT card_id FROM embeddings;"

            let upsertStmt = try prepare(sql: upsertSQL, db: db)
            defer { sqlite3_finalize(upsertStmt) }
            let deleteTokenStmt = try prepare(sql: deleteTokenSQL, db: db)
            defer { sqlite3_finalize(deleteTokenStmt) }
            let insertTokenStmt = try prepare(sql: insertTokenSQL, db: db)
            defer { sqlite3_finalize(insertTokenStmt) }
            let deleteEmbeddingStmt = try prepare(sql: deleteEmbeddingSQL, db: db)
            defer { sqlite3_finalize(deleteEmbeddingStmt) }
            let selectIDsStmt = try prepare(sql: selectIDsSQL, db: db)
            defer { sqlite3_finalize(selectIDsStmt) }

            for doc in documents where !doc.vector.isEmpty {
                sqlite3_reset(upsertStmt)
                sqlite3_clear_bindings(upsertStmt)

                let vectorData = doc.vector.withUnsafeBufferPointer { pointer -> Data in
                    guard let baseAddress = pointer.baseAddress else { return Data() }
                    return Data(
                        bytes: baseAddress,
                        count: pointer.count * MemoryLayout<Float>.stride
                    )
                }

                sqlite3_bind_text(upsertStmt, 1, doc.cardID.uuidString, -1, transientDestructor)
                sqlite3_bind_int64(upsertStmt, 2, Int64(doc.contentHash))
                sqlite3_bind_text(upsertStmt, 3, doc.category, -1, transientDestructor)
                sqlite3_bind_int64(upsertStmt, 4, Int64(doc.orderIndex))
                sqlite3_bind_double(upsertStmt, 5, doc.updatedAt.timeIntervalSince1970)
                let _ = vectorData.withUnsafeBytes { bytes in
                    if let base = bytes.baseAddress, bytes.count > 0 {
                        sqlite3_bind_blob(upsertStmt, 6, base, Int32(bytes.count), transientDestructor)
                    } else {
                        sqlite3_bind_null(upsertStmt, 6)
                    }
                }
                sqlite3_bind_text(upsertStmt, 7, doc.searchText, -1, transientDestructor)
                try stepDone(upsertStmt, db: db)

                sqlite3_reset(deleteTokenStmt)
                sqlite3_clear_bindings(deleteTokenStmt)
                sqlite3_bind_text(deleteTokenStmt, 1, doc.cardID.uuidString, -1, transientDestructor)
                try stepDone(deleteTokenStmt, db: db)

                for (token, tf) in doc.tokenTF where !token.isEmpty {
                    sqlite3_reset(insertTokenStmt)
                    sqlite3_clear_bindings(insertTokenStmt)
                    sqlite3_bind_text(insertTokenStmt, 1, token, -1, transientDestructor)
                    sqlite3_bind_text(insertTokenStmt, 2, doc.cardID.uuidString, -1, transientDestructor)
                    sqlite3_bind_double(insertTokenStmt, 3, Double(tf))
                    try stepDone(insertTokenStmt, db: db)
                }
            }

            var existingIDs: [String] = []
            while sqlite3_step(selectIDsStmt) == SQLITE_ROW {
                if let cString = sqlite3_column_text(selectIDsStmt, 0) {
                    existingIDs.append(String(cString: cString))
                }
            }
            for idString in existingIDs {
                guard let id = UUID(uuidString: idString) else { continue }
                if validCardIDs.contains(id) { continue }

                sqlite3_reset(deleteTokenStmt)
                sqlite3_clear_bindings(deleteTokenStmt)
                sqlite3_bind_text(deleteTokenStmt, 1, idString, -1, transientDestructor)
                try stepDone(deleteTokenStmt, db: db)

                sqlite3_reset(deleteEmbeddingStmt)
                sqlite3_clear_bindings(deleteEmbeddingStmt)
                sqlite3_bind_text(deleteEmbeddingStmt, 1, idString, -1, transientDestructor)
                try stepDone(deleteEmbeddingStmt, db: db)
            }

            try exec(sql: "COMMIT;", db: db)
        } catch {
            try? exec(sql: "ROLLBACK;", db: db)
            throw error
        }
    }

    func queryCandidateIDs(
        dbURL: URL,
        queryTokens: [String],
        limit: Int,
        fallbackLimit: Int = 160
    ) throws -> [UUID] {
        let db = try openDatabase(at: dbURL)
        defer { sqlite3_close(db) }
        try createSchema(db: db)

        var orderedIDs: [UUID] = []
        var seen: Set<UUID> = []

        let uniqueTokens = Array(Set(queryTokens.filter { !$0.isEmpty }))
        if !uniqueTokens.isEmpty {
            let placeholders = Array(repeating: "?", count: uniqueTokens.count).joined(separator: ",")
            let sql = """
            SELECT card_id, SUM(tf) AS score
            FROM token_index
            WHERE token IN (\(placeholders))
            GROUP BY card_id
            ORDER BY score DESC
            LIMIT ?;
            """
            let stmt = try prepare(sql: sql, db: db)
            defer { sqlite3_finalize(stmt) }

            for (index, token) in uniqueTokens.enumerated() {
                sqlite3_bind_text(stmt, Int32(index + 1), token, -1, transientDestructor)
            }
            sqlite3_bind_int64(stmt, Int32(uniqueTokens.count + 1), Int64(max(limit, fallbackLimit)))

            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let cString = sqlite3_column_text(stmt, 0) else { continue }
                guard let id = UUID(uuidString: String(cString: cString)) else { continue }
                if seen.insert(id).inserted {
                    orderedIDs.append(id)
                    if orderedIDs.count >= limit {
                        return orderedIDs
                    }
                }
            }
        }

        let recentStmt = try prepare(
            sql: "SELECT card_id FROM embeddings ORDER BY updated_at DESC LIMIT ?;",
            db: db
        )
        defer { sqlite3_finalize(recentStmt) }
        sqlite3_bind_int64(recentStmt, 1, Int64(max(limit, fallbackLimit)))
        while sqlite3_step(recentStmt) == SQLITE_ROW {
            guard let cString = sqlite3_column_text(recentStmt, 0) else { continue }
            guard let id = UUID(uuidString: String(cString: cString)) else { continue }
            if seen.insert(id).inserted {
                orderedIDs.append(id)
                if orderedIDs.count >= limit { break }
            }
        }

        return orderedIDs
    }

    private func openDatabase(at url: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(url.path, &db, flags, nil)
        guard result == SQLITE_OK, let db else {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let db {
                sqlite3_close(db)
            }
            throw StoreError.openFailed(message)
        }
        return db
    }

    private func createSchema(db: OpaquePointer) throws {
        try exec(
            sql: """
            CREATE TABLE IF NOT EXISTS embeddings (
                card_id TEXT PRIMARY KEY,
                content_hash INTEGER NOT NULL,
                category TEXT NOT NULL,
                order_index INTEGER NOT NULL,
                updated_at REAL NOT NULL,
                vector BLOB NOT NULL,
                search_text TEXT NOT NULL
            );
            """,
            db: db
        )
        try exec(
            sql: """
            CREATE TABLE IF NOT EXISTS token_index (
                token TEXT NOT NULL,
                card_id TEXT NOT NULL,
                tf REAL NOT NULL,
                PRIMARY KEY(token, card_id)
            );
            """,
            db: db
        )
        try exec(sql: "CREATE INDEX IF NOT EXISTS idx_embeddings_updated_at ON embeddings(updated_at DESC);", db: db)
        try exec(sql: "CREATE INDEX IF NOT EXISTS idx_token_index_card_id ON token_index(card_id);", db: db)
    }

    private func exec(sql: String, db: OpaquePointer) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw StoreError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func prepare(sql: String, db: OpaquePointer) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw StoreError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        guard let stmt else {
            throw StoreError.sqlite("statement prepare failed")
        }
        return stmt
    }

    private func stepDone(_ stmt: OpaquePointer, db: OpaquePointer) throws {
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw StoreError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }
}
