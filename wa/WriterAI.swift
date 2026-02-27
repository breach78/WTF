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

private struct AIChatThreadStorePayload: Codable, Sendable {
    var threads: [AIChatThread]
    var activeThreadID: UUID?
}

private struct AIChatMessageSnapshot: Sendable {
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

private struct AIEmbeddingIndexPayload: Codable, Sendable {
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

private struct AIChatPromptBuildResult: Sendable {
    let prompt: String
    let updatedDigestCache: [UUID: AICardDigest]
    let rollingSummary: String
    let contextPreview: AIChatContextPreview
}

private struct AIChatResponseResult: Sendable {
    let text: String
    let usage: AIChatTokenUsage
}

private enum AIChatPromptBuilder {
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
        let globalPlotSummary = buildGlobalLaneSummary(from: visibleCards, digests: resolvedDigestCache, category: "플롯")
        let globalNoteSummary = buildGlobalLaneSummary(from: visibleCards, digests: resolvedDigestCache, category: "노트")
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
        let allowed = text.lowercased().unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || (scalar.value >= 0xAC00 && scalar.value <= 0xD7A3) {
                return Character(scalar)
            }
            return " "
        }
        let normalized = String(allowed)
        let words = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var tokens: [String] = []
        tokens.reserveCapacity(words.count * 2)

        for word in words {
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else { continue }
            tokens.append(trimmed)
            if containsHangul(trimmed) {
                tokens.append(contentsOf: hangulBigrams(trimmed))
            }
        }

        return tokens
    }

    private static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            scalar.value >= 0xAC00 && scalar.value <= 0xD7A3
        }
    }

    private static func hangulBigrams(_ text: String) -> [String] {
        let chars = Array(text)
        guard chars.count >= 2 else { return [] }
        var grams: [String] = []
        grams.reserveCapacity(chars.count - 1)
        for index in 0..<(chars.count - 1) {
            let gram = String(chars[index...index + 1])
            grams.append(gram)
        }
        return grams
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
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preserveLineBreak {
            normalized = normalized.replacingOccurrences(of: "\n", with: " / ")
        }
        normalized = normalized.replacingOccurrences(of: "\t", with: " ")
        if normalized.isEmpty { return "(비어 있음)" }
        if normalized.count <= maxLength { return normalized }
        let index = normalized.index(normalized.startIndex, offsetBy: maxLength)
        return String(normalized[..<index]) + "..."
    }
}

private actor AIVectorSQLiteStore {
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

extension ScenarioWriterView {

    // MARK: - AI Chat View

    private var aiThreadsMaxCount: Int { 30 }
    private var aiMessagesMaxCountPerThread: Int { 140 }
    private var aiEmbeddingMaxRecordCount: Int { 1200 }
    private var aiRAGTopCardCount: Int { 8 }
    private var aiRAGEmbeddingModelCandidates: [String] { ["gemini-embedding-001", "text-embedding-004"] }
    private var visibleAIChatScopes: [AIChatScopeType] { [.selectedCards, .plotLine, .noteLine] }

    func aiThreadsJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    func aiThreadsJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func aiEmbeddingJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    func aiEmbeddingJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
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
            resolved = visibleCards.filter { $0.category == "플롯" }
        case .noteLine:
            resolved = visibleCards.filter { $0.category == "노트" }
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

    func handleAIChatInputKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard press.phase == .down else { return .ignored }
        let hasModifier =
            press.modifiers.contains(.command) ||
            press.modifiers.contains(.option) ||
            press.modifiers.contains(.control)
        if press.key == .return && !hasModifier && !press.modifiers.contains(.shift) {
            sendAIChatMessage()
            return .handled
        }
        return .ignored
    }

    func latestAIReplyText(for threadID: UUID?) -> String? {
        guard let threadID else { return nil }
        let text = messagesForAIThread(threadID)
            .reversed()
            .first(where: { $0.role == "model" })?
            .text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    func applyLatestAIReplyToActiveCard() {
        guard let reply = latestAIReplyText(for: activeAIChatThreadID) else {
            setAIStatusError("적용할 AI 답변이 없습니다.")
            return
        }
        guard let activeID = activeCardID,
              let activeCard = findCard(by: activeID) else {
            setAIStatusError("먼저 반영할 카드를 선택해 주세요.")
            return
        }

        finishEditing()
        let prevState = captureScenarioState()
        if activeCard.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            activeCard.content = reply
        } else {
            activeCard.content += "\n\n\(reply)"
        }
        scenario.bumpCardsVersion()
        commitCardMutation(
            previousState: prevState,
            actionName: "AI 상담 반영",
            forceSnapshot: true
        )
        selectedCardIDs = [activeCard.id]
        changeActiveCard(to: activeCard, shouldFocusMain: false)
        setAIStatus("AI 답변을 현재 선택 카드 하단에 반영했습니다.")
    }

    func addLatestAIReplyAsChildCard() {
        guard let reply = latestAIReplyText(for: activeAIChatThreadID) else {
            setAIStatusError("자식 카드로 만들 AI 답변이 없습니다.")
            return
        }
        guard let activeID = activeCardID,
              let parentCard = findCard(by: activeID) else {
            setAIStatusError("먼저 부모 카드를 선택해 주세요.")
            return
        }

        finishEditing()
        let prevState = captureScenarioState()
        let child = SceneCard(
            content: reply,
            orderIndex: parentCard.children.count,
            parent: parentCard,
            scenario: scenario,
            category: parentCard.category
        )
        scenario.cards.append(child)
        scenario.bumpCardsVersion()
        commitCardMutation(
            previousState: prevState,
            actionName: "AI 상담 자식 카드 추가",
            forceSnapshot: true
        )
        selectedCardIDs = [child.id]
        changeActiveCard(to: child, shouldFocusMain: false)
        setAIStatus("AI 답변을 자식 카드로 추가했습니다.")
    }

    func prepareAlternativeRequest() {
        guard let threadID = activeAIChatThreadID else { return }
        let latestUserQuestion = messagesForAIThread(threadID)
            .reversed()
            .first(where: { $0.role == "user" })?
            .text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let latestUserQuestion, !latestUserQuestion.isEmpty else {
            aiChatInput = "지금 맥락에서 대안 3가지를 제시해줘. 서로 다른 방향으로 짧게."
            isAIChatInputFocused = true
            return
        }
        aiChatInput = "방금 질문에 대한 대안 3가지를 서로 다른 방향으로 제시해줘.\n원 질문: \(latestUserQuestion)"
        isAIChatInputFocused = true
    }

    @ViewBuilder
    var aiChatView: some View {
        let activeMessages = activeAIChatMessages()
        let hasLatestReply = latestAIReplyText(for: activeAIChatThreadID) != nil
        let activeThreadTokenUsage = tokenUsageForAIThread(activeAIChatThreadID)
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Text("AI 시나리오 상담")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(appearance == "light" ? .black.opacity(0.7) : .white.opacity(0.8))
                    Spacer()
                    Button {
                        createAIChatThread()
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("새 상담 스레드")

                    Button {
                        guard let threadID = activeAIChatThreadID else { return }
                        deleteAIChatThread(threadID)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("현재 상담 스레드 삭제")

                    Button {
                        toggleAIChat()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 6)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(aiChatThreads) { thread in
                            let isActive = thread.id == activeAIChatThreadID
                            Button {
                                selectAIChatThread(thread.id)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(thread.mode.rawValue)
                                        .font(.system(size: 10, weight: .bold))
                                    Text(thread.title)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("\(thread.messages.count)")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background((isActive ? Color.white : Color.secondary.opacity(0.16)))
                                        .foregroundColor(isActive ? .accentColor : .secondary)
                                        .cornerRadius(10)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    isActive
                                        ? Color.accentColor.opacity(0.88)
                                        : (appearance == "light" ? Color.black.opacity(0.05) : Color.white.opacity(0.10))
                                )
                                .foregroundColor(isActive ? .white : .primary)
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 1)
                }

                if let activeThread = aiChatThreads.first(where: { $0.id == activeAIChatThreadID }) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(visibleAIChatScopes, id: \.self) { scope in
                                let isActiveScope = activeThread.scope.type.normalizedForCurrentUI == scope
                                Button {
                                    applyScopeToActiveThread(scope)
                                } label: {
                                    Text(scope.rawValue)
                                        .font(.system(size: 11, weight: .semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            isActiveScope
                                                ? Color.accentColor.opacity(0.86)
                                                : (appearance == "light" ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                                        )
                                        .foregroundColor(isActiveScope ? .white : .primary)
                                        .cornerRadius(9)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            Divider().background(appearance == "light" ? Color.black.opacity(0.1) : Color.white.opacity(0.15))
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 20) {
                        if activeMessages.isEmpty {
                            VStack(spacing: 14) {
                                Image(systemName: "sparkles.tv")
                                    .font(.system(size: 40))
                                    .foregroundColor(.accentColor.opacity(0.6))
                                Text("AI에게 현재 시나리오에 대해 물어보세요.")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                                if let thread = aiChatThreads.first(where: { $0.id == activeAIChatThreadID }) {
                                    Text("스레드 범위: \(thread.scope.type.rawValue)")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary.opacity(0.8))
                                }
                                Text("예: 이 이야기의 결말을 어떻게 내면 좋을까?")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary.opacity(0.8))
                            }
                            .padding(.top, 70)
                        } else {
                            ForEach(activeMessages) { msg in
                                HStack {
                                    if msg.role == "user" {
                                        Spacer(minLength: 50)
                                        Text(msg.text)
                                            .font(.system(size: 15))
                                            .padding(14)
                                            .background(Color.accentColor.opacity(0.85))
                                            .foregroundColor(.white)
                                            .cornerRadius(14)
                                            .textSelection(.enabled)
                                    } else {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text("AI")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.secondary)
                                            Text(msg.text)
                                                .font(.system(size: 15))
                                                .lineSpacing(3)
                                                .padding(14)
                                                .background(appearance == "light" ? Color.black.opacity(0.05) : Color.white.opacity(0.08))
                                                .cornerRadius(14)
                                                .textSelection(.enabled)
                                        }
                                        Spacer(minLength: 50)
                                    }
                                }
                                .id(msg.id)
                            }
                            
                            if isAIChatLoading {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("AI")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.secondary)
                                        ProgressView()
                                            .controlSize(.regular)
                                            .padding(14)
                                            .background(appearance == "light" ? Color.black.opacity(0.05) : Color.white.opacity(0.08))
                                            .cornerRadius(14)
                                    }
                                    Spacer()
                                }
                                .id("loading")
                            }
                        }
                    }
                    .padding(18)
                }
                .onChange(of: activeMessages.count) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation {
                            proxy.scrollTo(activeMessages.last?.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: activeAIChatThreadID) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation {
                            proxy.scrollTo(activeAIChatMessages().last?.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: isAIChatLoading) { _, isLoading in
                    if isLoading {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation {
                                proxy.scrollTo("loading", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            
            Divider().background(appearance == "light" ? Color.black.opacity(0.1) : Color.white.opacity(0.15))
            
            VStack(spacing: 10) {
                if let message = aiStatusMessage, aiStatusIsError {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("누적 토큰(현재 스레드): 입력 \(activeThreadTokenUsage.promptTokens) / 출력 \(activeThreadTokenUsage.outputTokens) / 총 \(activeThreadTokenUsage.totalTokens)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let context = aiLastContextPreview {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("이번 요청 컨텍스트")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text("범위: \(context.scopeLabel)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("선택 맥락: \(context.scopedContext)")
                            .font(.system(size: 11))
                            .lineLimit(3)
                            .foregroundStyle(.secondary)
                        Text("RAG 연관: \(context.ragContext)")
                            .font(.system(size: 11))
                            .lineLimit(3)
                            .foregroundStyle(.secondary)
                        Text("롤링 요약: \(context.rollingSummary)")
                            .font(.system(size: 11))
                            .lineLimit(3)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(appearance == "light" ? Color.black.opacity(0.035) : Color.white.opacity(0.06))
                    .cornerRadius(8)
                }

                if hasLatestReply {
                    HStack(spacing: 8) {
                        Button("선택 카드에 반영") {
                            applyLatestAIReplyToActiveCard()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(activeCardID == nil)

                        Button("자식 카드로 추가") {
                            addLatestAIReplyAsChildCard()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(activeCardID == nil)

                        Button("대안 3개 요청") {
                            prepareAlternativeRequest()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                HStack(alignment: .bottom, spacing: 10) {
                    if #available(macOS 13.0, *) {
                        TextField("AI에게 질문하기...", text: $aiChatInput, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .lineLimit(1...6)
                            .padding(12)
                            .background(appearance == "light" ? Color.black.opacity(0.03) : Color.white.opacity(0.05))
                            .cornerRadius(10)
                            .focused($isAIChatInputFocused)
                            .onKeyPress(phases: [.down]) { press in
                                handleAIChatInputKeyPress(press)
                            }
                            .onSubmit {
                                sendAIChatMessage()
                            }
                    } else {
                        TextField("AI에게 질문하기...", text: $aiChatInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .padding(12)
                            .background(appearance == "light" ? Color.black.opacity(0.03) : Color.white.opacity(0.05))
                            .cornerRadius(10)
                            .focused($isAIChatInputFocused)
                            .onKeyPress(phases: [.down]) { press in
                                handleAIChatInputKeyPress(press)
                            }
                            .onSubmit {
                                sendAIChatMessage()
                            }
                    }
                        
                    if isAIChatLoading {
                        Button(action: {
                            cancelAIChatRequest(showMessage: true)
                        }) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 7)
                        .help("현재 AI 요청 중단")
                    }

                    Button(action: {
                        sendAIChatMessage()
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(aiChatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAIChatLoading ? .secondary.opacity(0.5) : .accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(aiChatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAIChatLoading)
                    .padding(.bottom, 5)
                }
            }
            .padding(14)
            .background(appearance == "light" ? Color.white : Color(white: 0.12))
        }
        .onAppear {
            loadPersistedAIThreadsIfNeeded()
            loadPersistedAIEmbeddingIndexIfNeeded()
            isMainViewFocused = false
            isAIChatInputFocused = true
            syncActiveThreadSelectedScopeWithCurrentSelection()
        }
        .onChange(of: scenario.id) { _, _ in
            handleAIChatScenarioChange()
        }
        .onChange(of: selectedCardIDs) { _, _ in
            syncActiveThreadSelectedScopeWithCurrentSelection()
        }
        .onChange(of: activeCardID) { _, _ in
            syncActiveThreadSelectedScopeWithCurrentSelection()
        }
        .onDisappear {
            flushAIThreadsPersistence()
            flushAIEmbeddingPersistence()
            cancelAIChatRequest()
        }
    }

    func sendAIChatMessage() {
        ensureAIChatThreadSelection()
        guard let threadID = activeAIChatThreadID else { return }

        let text = aiChatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isAIChatLoading else { return }
        
        aiChatInput = ""
        appendAIChatMessage(AIChatMessage(role: "user", text: text), to: threadID)
        
        requestAIChatResponse(for: threadID)
    }

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

    func ragSearchTokens(from text: String) -> [String] {
        let allowed = text.lowercased().unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || (scalar.value >= 0xAC00 && scalar.value <= 0xD7A3) {
                return Character(scalar)
            }
            return " "
        }
        let normalized = String(allowed)
        let words = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var tokens: [String] = []
        tokens.reserveCapacity(words.count * 2)
        for word in words {
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else { continue }
            tokens.append(trimmed)
            if trimmed.unicodeScalars.contains(where: { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }) {
                let chars = Array(trimmed)
                if chars.count >= 2 {
                    for index in 0..<(chars.count - 1) {
                        tokens.append(String(chars[index...index + 1]))
                    }
                }
            }
        }
        return tokens
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
            let tokens = ragSearchTokens(from: mergedSearchText)
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
        let queryTokens = ragSearchTokens(from: trimmedQuery)
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

    func requestAIChatResponse(for threadID: UUID) {
        cancelAIChatRequest()
        syncSelectedScopeForThread(threadID)
        guard let thread = aiChatThreads.first(where: { $0.id == threadID }) else { return }

        let requestID = UUID()
        let allCardSnapshots = scenario.cards.map { card in
            AIChatCardSnapshot(
                id: card.id,
                parentID: card.parent?.id,
                category: card.category ?? "미분류",
                content: card.content,
                orderIndex: card.orderIndex,
                createdAt: card.createdAt,
                isArchived: card.isArchived,
                isFloating: card.isFloating
            )
        }
        let scopedCards = resolvedScopedCards(for: thread.scope, allCards: allCardSnapshots)
        let scopeText = scopeLabel(for: thread.scope, cardCount: scopedCards.count)
        let historySnapshots = messagesForAIThread(threadID).map { message in
            AIChatMessageSnapshot(role: message.role, text: message.text)
        }
        let lastUserQuestion = historySnapshots.last(where: { $0.role == "user" })?.text ?? ""
        let userTurnCount = historySnapshots.filter { $0.role == "user" }.count
        let shouldRefreshRollingSummary = thread.rollingSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || userTurnCount % 4 == 0
        let previousRollingSummary = thread.rollingSummary
        let digestCacheSnapshot = aiCardDigestCache
        let embeddingIndexSnapshot = aiEmbeddingIndexByCardID
        let vectorDBURL = store.aiVectorIndexURL(for: scenario.id)
        let resolvedModel = currentGeminiModel()

        isAIChatLoading = true
        aiChatActiveRequestID = requestID
        setAIStatus(nil)

        aiChatRequestTask = Task {
            var preparedContext: AIChatPromptBuildResult?
            var preparedEmbeddingIndex = embeddingIndexSnapshot
            var preparedEmbeddingModel = aiEmbeddingIndexModelID
            do {
                let apiKey = try loadGeminiAPIKeyForChat()
                let semanticRAG = await buildSemanticRAGContext(
                    query: lastUserQuestion,
                    allCards: allCardSnapshots,
                    scopedCards: scopedCards,
                    digests: digestCacheSnapshot,
                    existingIndex: embeddingIndexSnapshot,
                    apiKey: apiKey,
                    vectorDBURL: vectorDBURL
                )
                preparedEmbeddingIndex = semanticRAG.updatedIndex
                if let resolvedEmbeddingModel = semanticRAG.resolvedModel {
                    preparedEmbeddingModel = resolvedEmbeddingModel
                }

                let buildResult = AIChatPromptBuilder.buildPrompt(
                    allCards: allCardSnapshots,
                    scopedCards: scopedCards,
                    scopeLabel: scopeText,
                    history: historySnapshots,
                    lastUserMessage: lastUserQuestion,
                    previousRollingSummary: previousRollingSummary,
                    digestCache: digestCacheSnapshot,
                    refreshRollingSummary: shouldRefreshRollingSummary,
                    semanticRAGContext: semanticRAG.semanticContext
                )
                preparedContext = buildResult
                try Task.checkCancellation()

                let response = try await requestGeminiChatResponse(
                    prompt: buildResult.prompt,
                    apiKey: apiKey,
                    model: resolvedModel
                )
                try Task.checkCancellation()

                await MainActor.run {
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
            } catch is CancellationError {
                await MainActor.run {
                    guard aiChatActiveRequestID == requestID else { return }
                    if let preparedContext {
                        aiCardDigestCache = preparedContext.updatedDigestCache
                        aiEmbeddingIndexByCardID = preparedEmbeddingIndex
                        aiEmbeddingIndexModelID = preparedEmbeddingModel
                        scheduleAIEmbeddingPersistence()
                        aiLastContextPreview = preparedContext.contextPreview
                        updateAIChatThread(threadID) { thread in
                            thread.rollingSummary = preparedContext.rollingSummary
                        }
                    }
                    finishAIChatRequest()
                }
            } catch {
                await MainActor.run {
                    guard aiChatActiveRequestID == requestID else { return }
                    if let preparedContext {
                        aiCardDigestCache = preparedContext.updatedDigestCache
                        aiEmbeddingIndexByCardID = preparedEmbeddingIndex
                        aiEmbeddingIndexModelID = preparedEmbeddingModel
                        scheduleAIEmbeddingPersistence()
                        aiLastContextPreview = preparedContext.contextPreview
                        updateAIChatThread(threadID) { thread in
                            thread.rollingSummary = preparedContext.rollingSummary
                        }
                    }
                    setAIStatusError(error.localizedDescription)
                    appendAIChatMessage(
                        AIChatMessage(role: "model", text: "오류가 발생했습니다: \(error.localizedDescription)"),
                        to: threadID
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

    // MARK: - Timeline AI Controls

    @ViewBuilder
    var aiTimelineActionPanel: some View {
        let noActiveCard = activeCardID == nil
        let activeCard = activeCardID.flatMap { findCard(by: $0) }
        let isPlotLineActive = activeCard?.category == "플롯"
        VStack(alignment: .leading, spacing: 10) {
            Text("AI 카드 도우미")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(appearance == "light" ? .black.opacity(0.55) : .white.opacity(0.72))

            HStack(spacing: 8) {
                aiActionButton(title: AICardAction.elaborate.title, disabled: noActiveCard || !isPlotLineActive) {
                    openAIOptionsSheet(for: .elaborate)
                }
                aiActionButton(title: AICardAction.nextScene.title, disabled: noActiveCard || !isPlotLineActive) {
                    openAIOptionsSheet(for: .nextScene)
                }
                aiActionButton(title: AICardAction.alternative.title, disabled: noActiveCard || !isPlotLineActive) {
                    openAIOptionsSheet(for: .alternative)
                }
                aiActionButton(title: AICardAction.summary.title, disabled: noActiveCard) {
                    requestAISummaryCandidate()
                }
                aiActionButton(
                    title: "선택",
                    prominent: true,
                    disabled: !canApplyAICandidateSelection
                ) {
                    applySelectedAICandidateToParent()
                }
            }

            if !noActiveCard && !isPlotLineActive {
                Text("구체화/다음 장면/대안은 플롯 카드에서만 사용할 수 있습니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if aiIsGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("AI가 후보를 생성하고 있습니다...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else if let message = aiStatusMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(aiStatusIsError ? Color.red : Color.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(appearance == "light" ? Color.black.opacity(0.04) : Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(appearance == "light" ? Color.black.opacity(0.10) : Color.white.opacity(0.12), lineWidth: 1)
        )
        .cornerRadius(8)
        .padding([.horizontal, .top], 12)
    }

    @ViewBuilder
    func aiActionButton(
        title: String,
        prominent: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        if prominent {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(disabled || aiIsGenerating || dictationIsProcessing || dictationIsRecording)
        } else {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(disabled || aiIsGenerating || dictationIsProcessing || dictationIsRecording)
        }
    }

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

    var canApplyAICandidateSelection: Bool {
        selectedAICandidateCard() != nil
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

    func requestAICandidates(action: AICardAction, selectedOptions: Set<AIGenerationOption>) {
        finishEditing()
        pruneAICandidateTracking()

        guard let parentID = activeCardID,
              let parentCard = findCard(by: parentID) else {
            setAIStatusError("활성 카드가 없어 AI 제안을 만들 수 없습니다.")
            return
        }
        guard parentCard.category == "플롯" else {
            setAIStatusError("구체화/다음 장면/대안은 플롯 카드에서만 사용할 수 있습니다.")
            return
        }

        let options = selectedOptions.isEmpty ? Set([AIGenerationOption.balanced]) : selectedOptions
        let prompt = buildAIPrompt(for: parentCard, action: action, options: options)
        let resolvedModel = currentGeminiModel()

        aiIsGenerating = true
        setAIStatus("\(action.summaryLabel)을 생성하는 중입니다...")

        Task { @MainActor in
            do {
                guard let apiKey = try KeychainStore.loadGeminiAPIKey() else {
                    throw GeminiServiceError.missingAPIKey
                }
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
            aiIsGenerating = false
        }
    }

    func requestAISummaryCandidate() {
        finishEditing()
        pruneAICandidateTracking()

        guard let parentID = activeCardID,
              let parentCard = findCard(by: parentID) else {
            setAIStatusError("활성 카드가 없어 요약을 만들 수 없습니다.")
            return
        }

        let prompt = buildAISummaryPrompt(for: parentCard)
        let resolvedModel = currentGeminiModel()

        aiIsGenerating = true
        setAIStatus("요약 제안을 생성하는 중입니다...")

        Task { @MainActor in
            do {
                guard let apiKey = try KeychainStore.loadGeminiAPIKey() else {
                    throw GeminiServiceError.missingAPIKey
                }
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
            aiIsGenerating = false
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
            setAIStatus("요약 후보 1개를 만들었습니다. 선택 후 '선택'을 누르면 부모 카드가 대체됩니다.")
        } else {
            setAIStatus("\(action.summaryLabel) \(createdCount)개를 만들었습니다. 마음에 드는 카드를 선택하고 '선택'을 누르세요.")
        }
    }

    func applySelectedAICandidateToParent() {
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
        guard let selectedCandidate = selectedAICandidateCard() else {
            setAIStatusError("AI 후보 카드 중 하나를 먼저 선택해 주세요.")
            return
        }

        let prevState = captureScenarioState()
        let selectedID = selectedCandidate.id

        switch action {
        case .elaborate, .alternative, .summary:
            parentCard.content = selectedCandidate.content
            selectedCandidate.colorHex = nil
            selectedCandidate.isAICandidate = false
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

        for candidateID in aiCandidateState.cardIDs where candidateID != selectedID {
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
        case .elaborate, .alternative, .summary:
            setAIStatus("선택한 후보를 부모 카드에 반영했고, 나머지 후보는 삭제했습니다.")
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

    // MARK: - Prompt Builder

    func buildAIPrompt(
        for card: SceneCard,
        action: AICardAction,
        options: Set<AIGenerationOption>
    ) -> String {
        let sortedOptions = sortedAIGenerationOptions(options)
        let levelIndex = resolvedAILevelIndex(for: card)
        let optionLines = aiPromptOptionLines(from: sortedOptions)
        let context = buildAIPromptContext(for: card, levelIndex: levelIndex)
        return renderAIPrompt(
            for: card,
            action: action,
            optionLines: optionLines,
            context: context
        )
    }

    struct AIPromptContext {
        let currentCardContent: String
        let parentThemeContext: String
        let deepeningPathContext: String
        let noteFoundation: String
        let noteFlowContext: String
        let storyFlowContext: String
        let childrenContext: String
    }

    func resolvedAILevelIndex(for card: SceneCard) -> Int? {
        resolvedAllLevels().firstIndex { level in
            level.contains(where: { $0.id == card.id })
        }
    }

    func sortedAIPromptChildren(of card: SceneCard) -> [SceneCard] {
        card.children.sorted {
            if $0.orderIndex != $1.orderIndex {
                return $0.orderIndex < $1.orderIndex
            }
            return $0.createdAt < $1.createdAt
        }
    }

    func aiPromptOptionLines(from sortedOptions: [AIGenerationOption]) -> String {
        sortedOptions
            .map { "- \($0.title): \($0.promptInstruction)" }
            .joined(separator: "\n")
    }

    func buildAIPromptContext(for card: SceneCard, levelIndex: Int?) -> AIPromptContext {
        let pathCards = ancestorPathCards(for: card)
        let storyFlow = aiColumnFlow(levelIndex: levelIndex, category: "플롯", upToOrder: card.orderIndex)
        let noteFlow = aiColumnFlow(levelIndex: levelIndex, category: "노트", upToOrder: card.orderIndex)
        let existingChildren = sortedAIPromptChildren(of: card)

        let currentCardContent = clampedAIText(card.content, maxLength: 1400, preserveLineBreak: true)
        let parentThemeContext = parentThemeAnchors(from: pathCards)
        let deepeningPathContext = adaptiveAICardPath(pathCards)
        let noteFoundation = noteFoundationContext(from: noteFlow)
        let noteFlowContext = adaptiveAICardList(noteFlow, maxCards: 10, maxLength: 250)
        let storyFlowContext = adaptiveAICardList(storyFlow, maxCards: 12, maxLength: 280)
        let childrenContext = adaptiveAICardList(existingChildren, maxCards: 8, maxLength: 220)

        return AIPromptContext(
            currentCardContent: currentCardContent,
            parentThemeContext: parentThemeContext,
            deepeningPathContext: deepeningPathContext,
            noteFoundation: noteFoundation,
            noteFlowContext: noteFlowContext,
            storyFlowContext: storyFlowContext,
            childrenContext: childrenContext
        )
    }

    func renderAIPrompt(
        for card: SceneCard,
        action: AICardAction,
        optionLines: String,
        context: AIPromptContext
    ) -> String {
        """
        당신은 영화 시나리오 공동 집필 파트너다.
        반드시 한국어로 작성하고, JSON 외의 어떤 텍스트도 출력하지 않는다.

        [작업 모드]
        \(action.summaryLabel)
        \(action.promptGuideline)

        [선택된 확장 방향]
        \(optionLines)

        [핵심 제약]
        - 부모-자식은 심화 관계다. 부모 라인의 주제/목표/인과를 유지한 채 더 구체화한다.
        - 현재 열의 위->아래 순서가 이야기 진행 순서다. 현재 카드보다 위에 있는 플롯 흐름과 자연스럽게 이어져야 한다.
        - 노트 라인은 기획의도, 캐릭터 설정, 연출의도의 기반이다. 플롯 제안은 노트 기반 의도를 훼손하면 안 된다.
        - 5개 제안은 서로 분명히 다른 방향이어야 한다.
        - 구체화 모드에서는 길이보다 구체성을 우선한다. (행동, 선택, 인과, 결과가 분명해야 함)
        - \(action.contentLengthGuideline)
        - title은 짧고 구분 가능하게 만든다.
        - markdown, 코드블록, 설명문 금지.

        [부모 라인 주제 앵커]
        \(context.parentThemeContext)

        [부모-자식 심화 경로 (좌->우)]
        \(context.deepeningPathContext)

        [노트 라인 핵심 의도 앵커]
        \(context.noteFoundation)

        [현재 열 노트 흐름 (상->하, 현재까지)]
        \(context.noteFlowContext)

        [현재 열 스토리 흐름 (상->하, 플롯 라인, 현재까지)]
        \(context.storyFlowContext)

        [현재 카드]
        카테고리: \(card.category ?? "미분류")
        내용:
        \(context.currentCardContent)

        [이미 존재하는 같은 부모의 자식 카드]
        \(context.childrenContext)

        [응답 작성 규칙]
        - 노트 라인에서 제시된 기획의도/캐릭터 설정/연출의도를 반영하되, 직접 복붙하지 말고 장면 행동으로 변환한다.
        - 부모 라인 주제와 현재 열의 선행 스토리 흐름을 훼손하지 않는다.
        - 다음 장면 모드에서는 바로 다음 순서에 자연스럽게 붙는 진행만 제안한다.
        - 대안/구체화 모드에서는 사건의 목적과 인과를 유지하면서 표현/접근만 차별화한다.

        출력 JSON 스키마:
        {
          "suggestions": [
            {
              "title": "짧은 제목",
              "content": "제안 본문",
              "rationale": "선택 이유 한 줄"
            }
          ]
        }

        필수 조건:
        - suggestions는 정확히 5개
        - title, content는 빈 문자열 금지
        """
    }

    func buildAISummaryPrompt(for card: SceneCard) -> String {
        let levelIndex = resolvedAILevelIndex(for: card)
        let context = buildAISummaryPromptContext(for: card, levelIndex: levelIndex)
        return renderAISummaryPrompt(context: context)
    }

    struct AISummaryPromptContext {
        let articleText: String
        let pathContext: String
        let plotContext: String
        let noteContext: String
    }

    func buildAISummaryPromptContext(for card: SceneCard, levelIndex: Int?) -> AISummaryPromptContext {
        let pathCards = ancestorPathCards(for: card)
        let plotFlow = aiColumnFlow(levelIndex: levelIndex, category: "플롯", upToOrder: card.orderIndex)
        let noteFlow = aiColumnFlow(levelIndex: levelIndex, category: "노트", upToOrder: card.orderIndex)

        let articleText = clampedAIText(card.content, maxLength: 4200, preserveLineBreak: true)
        let pathContext = adaptiveAICardPath(pathCards)
        let plotContext = adaptiveAICardList(plotFlow, maxCards: 8, maxLength: 220)
        let noteContext = adaptiveAICardList(noteFlow, maxCards: 8, maxLength: 220)

        return AISummaryPromptContext(
            articleText: articleText,
            pathContext: pathContext,
            plotContext: plotContext,
            noteContext: noteContext
        )
    }

    func renderAISummaryPrompt(context: AISummaryPromptContext) -> String {
        """
        아래 텍스트를 대상으로 작업하라.

        [Article]
        \(context.articleText)

        [맥락: 문서 심화 경로]
        \(context.pathContext)

        [맥락: 현재 열 플롯 흐름]
        \(context.plotContext)

        [맥락: 현재 열 노트 흐름]
        \(context.noteContext)

        아래 지시를 정확히 따른다:
        You will generate increasingly concise, entity-dense summaries of the above Article or webpage. Repeat the following 2 steps 5 times.

        Step 1. Identify 1-3 informative Entities (";" delimited) from the Article which are missing from the previously generated summary.


        Step 2. Write a new, denser summary of identical length which covers every entity and detail from the previous summary plus the Missing Entities.


        A Missing Entity is:
         - Relevant: to the main story.
         - Specific: descriptive yet concise (5 words or fewer).
         - Novel: not in the previous summary.
         - Faithful: present in the Article.
         - Anywhere: located anywhere in the Article.


        Guidelines:
         - The first summary should be long (4-5 sentences, ~80 words) yet highly non-specific, containing little information beyond the entities marked as missing. Use overly verbose language and fillers (e.g., "this article discusses") to reach ~80 words.
         - Make every word count: re-write the previous summary to improve flow and make space for additional entities.
         - Make space with fusion, compression, and removal of uninformative phrases like "the article discusses".
         - The summaries should become highly dense and concise yet self-contained, e.g., easily understood without the Article.
         - Missing entities can appear anywhere in the new summary.
         - Never drop entities from the previous summary. If space cannot be made, add fewer new entities.


        Remember, use the exact same number of words for each summary. Answer only in korean.

        추가 출력 규칙:
        - 중간 단계, 엔티티 목록, 해설을 출력하지 않는다.
        - 5회 반복이 끝난 최종 요약문 1개만 출력한다.
        - JSON, 마크다운, 코드블록 금지.
        """
    }

    func aiColumnFlow(levelIndex: Int?, category: String?, upToOrder: Int) -> [SceneCard] {
        guard let levelIndex,
              let levelCards = resolvedAllLevels()[safe: levelIndex] else {
            return []
        }
        return levelCards
            .filter { !$0.isArchived && !$0.isFloating }
            .filter { category == nil || $0.category == category }
            .sorted {
                if $0.orderIndex != $1.orderIndex {
                    return $0.orderIndex < $1.orderIndex
                }
                return $0.createdAt < $1.createdAt
            }
            .filter { $0.orderIndex <= upToOrder }
    }

    func ancestorPathCards(for card: SceneCard) -> [SceneCard] {
        var path: [SceneCard] = []
        var current: SceneCard? = card
        while let node = current {
            path.append(node)
            current = node.parent
        }
        return path.reversed()
    }

    func formattedAICardPath(_ cards: [SceneCard]) -> String {
        guard !cards.isEmpty else { return "- 없음" }
        return cards.enumerated().map { index, card in
            let label = index == cards.count - 1 ? "현재" : "단계 \(index + 1)"
            let text = clampedAIText(card.content, maxLength: 240)
            return "\(label): [\(card.category ?? "미분류")] \(text)"
        }.joined(separator: "\n")
    }

    func formattedAICardList(_ cards: [SceneCard], maxCards: Int, maxLength: Int) -> String {
        guard !cards.isEmpty else { return "- 없음" }
        let limited = Array(cards.prefix(maxCards))
        var lines = limited.enumerated().map { index, card in
            let text = clampedAIText(card.content, maxLength: maxLength)
            return "\(index + 1). [\(card.category ?? "미분류")] \(text)"
        }
        if cards.count > maxCards {
            lines.append("... \(cards.count - maxCards)개 생략")
        }
        return lines.joined(separator: "\n")
    }

    func adaptiveAICardPath(_ cards: [SceneCard]) -> String {
        guard !cards.isEmpty else { return "- 없음" }
        let full = formattedAICardPath(cards)
        let threshold = 680
        let detailedTailCount = 3
        guard full.count > threshold, cards.count > detailedTailCount else {
            return full
        }

        let splitIndex = max(0, cards.count - detailedTailCount)
        let older = Array(cards.prefix(splitIndex))
        let recent = Array(cards.suffix(detailedTailCount))

        var lines: [String] = []
        let compressed = compressedCardMemory(from: older, maxItems: 8, snippetLength: 54, budget: 420)
        if !compressed.isEmpty {
            lines.append("요약 메모(이전 단계 \(older.count)개): \(compressed)")
        }
        let detailedLines = recent.enumerated().map { offset, card in
            let absoluteIndex = splitIndex + offset
            let label = absoluteIndex == cards.count - 1 ? "현재" : "단계 \(absoluteIndex + 1)"
            let text = clampedAIText(card.content, maxLength: 170)
            return "\(label): [\(card.category ?? "미분류")] \(text)"
        }
        lines.append(contentsOf: detailedLines)
        return lines.joined(separator: "\n")
    }

    func parentThemeAnchors(from pathCards: [SceneCard]) -> String {
        guard pathCards.count > 1 else { return "- 없음" }
        let ancestors = Array(pathCards.dropLast())
        guard !ancestors.isEmpty else { return "- 없음" }

        if ancestors.count <= 3 {
            return ancestors.enumerated().map { index, card in
                let label = index == ancestors.count - 1 ? "직전 부모" : "상위 \(index + 1)"
                let text = clampedAIText(card.content, maxLength: 150)
                return "\(label): [\(card.category ?? "미분류")] \(text)"
            }.joined(separator: "\n")
        }

        let root = ancestors.first
        let middle = Array(ancestors.dropFirst().dropLast(2))
        let recent = Array(ancestors.suffix(2))
        var lines: [String] = []

        if let root {
            let rootText = clampedAIText(root.content, maxLength: 150)
            lines.append("핵심 기원: [\(root.category ?? "미분류")] \(rootText)")
        }
        if !middle.isEmpty {
            let compressed = compressedCardMemory(from: middle, maxItems: 5, snippetLength: 52, budget: 320)
            if !compressed.isEmpty {
                lines.append("중간 심화 요약: \(compressed)")
            }
        }
        for (offset, card) in recent.enumerated() {
            let label = offset == recent.count - 1 ? "직전 부모" : "상위 부모"
            let text = clampedAIText(card.content, maxLength: 150)
            lines.append("\(label): [\(card.category ?? "미분류")] \(text)")
        }

        return lines.joined(separator: "\n")
    }

    func noteFoundationContext(from noteFlow: [SceneCard]) -> String {
        guard !noteFlow.isEmpty else { return "- 없음" }
        let limited = Array(noteFlow.prefix(10))
        guard !limited.isEmpty else { return "- 없음" }

        if limited.count <= 3 {
            return limited.enumerated().map { index, card in
                let label = index == 0 ? "기초 의도" : "보조 의도 \(index)"
                let text = clampedAIText(card.content, maxLength: 160)
                return "\(label): \(text)"
            }.joined(separator: "\n")
        }

        let first = limited.first
        let middle = Array(limited.dropFirst().dropLast(2))
        let recent = Array(limited.suffix(2))
        var lines: [String] = []

        if let first {
            let firstText = clampedAIText(first.content, maxLength: 170)
            lines.append("기초 의도: \(firstText)")
        }
        if !middle.isEmpty {
            let compressed = compressedCardMemory(from: middle, maxItems: 5, snippetLength: 50, budget: 300)
            if !compressed.isEmpty {
                lines.append("중간 노트 요약: \(compressed)")
            }
        }
        for (index, card) in recent.enumerated() {
            let label = index == recent.count - 1 ? "최신 노트" : "최근 노트"
            let text = clampedAIText(card.content, maxLength: 140)
            lines.append("\(label): \(text)")
        }

        return lines.joined(separator: "\n")
    }

    func adaptiveAICardList(_ cards: [SceneCard], maxCards: Int, maxLength: Int) -> String {
        guard !cards.isEmpty else { return "- 없음" }
        let full = formattedAICardList(cards, maxCards: maxCards, maxLength: maxLength)
        let threshold = maxLength >= 240 ? 920 : 760
        let detailedTailCount = 3
        guard full.count > threshold else {
            return full
        }

        let limited = Array(cards.prefix(maxCards))
        let recentCount = min(detailedTailCount, limited.count)
        let older = Array(limited.dropLast(recentCount))
        let recent = Array(limited.suffix(recentCount))
        var lines: [String] = []

        if !older.isEmpty {
            let compressed = compressedCardMemory(
                from: older,
                maxItems: 8,
                snippetLength: maxLength >= 240 ? 60 : 54,
                budget: maxLength >= 240 ? 520 : 440
            )
            if !compressed.isEmpty {
                lines.append("요약 메모(이전 카드 \(older.count)개): \(compressed)")
            }
        }

        if !recent.isEmpty {
            lines.append("최근 카드(상세):")
            let detailedLines = recent.enumerated().map { offset, card in
                let absoluteIndex = older.count + offset
                let text = clampedAIText(card.content, maxLength: min(maxLength, 170))
                return "\(absoluteIndex + 1). [\(card.category ?? "미분류")] \(text)"
            }
            lines.append(contentsOf: detailedLines)
        }

        if cards.count > maxCards {
            lines.append("... \(cards.count - maxCards)개 생략")
        }

        return lines.joined(separator: "\n")
    }

    func compressedCardMemory(from cards: [SceneCard], maxItems: Int, snippetLength: Int, budget: Int) -> String {
        guard !cards.isEmpty else { return "" }
        var snippets: [String] = []
        var seen: Set<String> = []

        for card in cards {
            let text = clampedAIText(card.content, maxLength: snippetLength)
            if text == "(비어 있음)" { continue }
            let normalized = text
                .replacingOccurrences(of: " / ", with: " ")
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            let snippet = "[\(card.category ?? "미분류")] \(normalized)"
            let key = snippet.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            snippets.append(snippet)
        }

        guard !snippets.isEmpty else { return "" }
        if snippets.count > maxItems {
            let headCount = max(1, maxItems / 2)
            let tailCount = maxItems - headCount
            snippets = Array(snippets.prefix(headCount)) + Array(snippets.suffix(tailCount))
        }

        let joined = snippets.joined(separator: " | ")
        if joined.count <= budget {
            return joined
        }
        let clippedIndex = joined.index(joined.startIndex, offsetBy: budget)
        return String(joined[..<clippedIndex]) + "..."
    }

    func clampedAIText(_ text: String, maxLength: Int, preserveLineBreak: Bool = false) -> String {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preserveLineBreak {
            normalized = normalized.replacingOccurrences(of: "\n", with: " / ")
        }
        normalized = normalized.replacingOccurrences(of: "\t", with: " ")
        if normalized.count <= maxLength {
            return normalized.isEmpty ? "(비어 있음)" : normalized
        }
        let index = normalized.index(normalized.startIndex, offsetBy: maxLength)
        return String(normalized[..<index]) + "..."
    }

    func normalizedAICandidateContent(from suggestion: GeminiSuggestion) -> String {
        let title = suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = suggestion.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return content }
        if content.hasPrefix(title) { return content }
        return title + "\n" + content
    }

    func sortedAIGenerationOptions(_ options: Set<AIGenerationOption>) -> [AIGenerationOption] {
        let fallback: Set<AIGenerationOption> = options.isEmpty ? [.balanced] : options
        let order = Dictionary(uniqueKeysWithValues: AIGenerationOption.allCases.enumerated().map { ($0.element, $0.offset) })
        return fallback.sorted { lhs, rhs in
            (order[lhs] ?? 0) < (order[rhs] ?? 0)
        }
    }

    func aiCandidateTintHex(for index: Int) -> String {
        let palette = ["F6D2B8", "D6E8C4", "F2CBD8", "F2E3B3", "D8ECCD"]
        return palette[index % palette.count]
    }

    func clearStaleAICandidateVisualFlags() {
        let activeSet = Set(aiCandidateState.cardIDs)
        for card in scenario.cards where card.isAICandidate {
            if activeSet.contains(card.id) && !card.isArchived {
                continue
            }
            card.isAICandidate = false
        }
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
