import SwiftUI

extension ScenarioWriterView {
    func buildAIPrompt(
        for card: SceneCard,
        action: AICardAction,
        options: Set<AIGenerationOption>,
        sharedContext: AIChatContextPreview? = nil
    ) -> String {
        let sortedOptions = sortedAIGenerationOptions(options)
        let levelIndex = resolvedAILevelIndex(for: card)
        let optionLines = aiPromptOptionLines(from: sortedOptions)
        let context = buildAIPromptContext(for: card, levelIndex: levelIndex)
        return renderAIPrompt(
            for: card,
            action: action,
            optionLines: optionLines,
            context: context,
            sharedContext: sharedContext
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
        let storyFlow = aiColumnFlow(levelIndex: levelIndex, category: ScenarioCardCategory.plot, upToOrder: card.orderIndex)
        let noteFlow = aiColumnFlow(levelIndex: levelIndex, category: ScenarioCardCategory.note, upToOrder: card.orderIndex)
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
        context: AIPromptContext,
        sharedContext: AIChatContextPreview? = nil
    ) -> String {
        let sharedScoped = sharedContext?.scopedContext ?? "(없음)"
        let sharedRAG = sharedContext?.ragContext ?? "(없음)"
        let sharedPlot = sharedContext?.globalPlotSummary ?? "(없음)"
        let sharedNote = sharedContext?.globalNoteSummary ?? "(없음)"
        return """
        당신은 영화 시나리오 공동 집필 파트너다.
        반드시 한국어로 작성하고, JSON 외의 어떤 텍스트도 출력하지 않는다.

        [AI 시나리오 컨설턴트 공통 기준]
        - 업계 최고 수준의 시나리오 컨설턴트 관점으로 판단한다.
        - 뻔한 전개를 피하고, 논리적인 대안을 제시한다.
        - 답변은 핵심만 간결하게 제시한다. 장황한 설명은 금지한다.
        - 칭찬만 하지 말고, 작동 원리와 약점을 분명히 짚는다.

        [AI 시나리오 상담 공통 컨텍스트]
        [선택 범위 핵심]
        \(sharedScoped)

        [질문 연관 카드(RAG)]
        \(sharedRAG)

        [전역 플롯 요약]
        \(sharedPlot)

        [전역 노트 요약]
        \(sharedNote)

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
        카테고리: \(card.category ?? ScenarioCardCategory.uncategorized)
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
        let articleText = clampedAIText(card.content, maxLength: 5600, preserveLineBreak: true)
        return renderEntityDenseSummaryPrompt(articleText: articleText)
    }

    func renderEntityDenseSummaryPrompt(articleText: String) -> String {
        return """
        [Article]
        \(articleText)

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
            return "\(label): [\(card.category ?? ScenarioCardCategory.uncategorized)] \(text)"
        }.joined(separator: "\n")
    }

    func formattedAICardList(_ cards: [SceneCard], maxCards: Int, maxLength: Int) -> String {
        guard !cards.isEmpty else { return "- 없음" }
        let limited = Array(cards.prefix(maxCards))
        var lines = limited.enumerated().map { index, card in
            let text = clampedAIText(card.content, maxLength: maxLength)
            return "\(index + 1). [\(card.category ?? ScenarioCardCategory.uncategorized)] \(text)"
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
            return "\(label): [\(card.category ?? ScenarioCardCategory.uncategorized)] \(text)"
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
                return "\(label): [\(card.category ?? ScenarioCardCategory.uncategorized)] \(text)"
            }.joined(separator: "\n")
        }

        let root = ancestors.first
        let middle = Array(ancestors.dropFirst().dropLast(2))
        let recent = Array(ancestors.suffix(2))
        var lines: [String] = []

        if let root {
            let rootText = clampedAIText(root.content, maxLength: 150)
            lines.append("핵심 기원: [\(root.category ?? ScenarioCardCategory.uncategorized)] \(rootText)")
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
            lines.append("\(label): [\(card.category ?? ScenarioCardCategory.uncategorized)] \(text)")
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
                return "\(absoluteIndex + 1). [\(card.category ?? ScenarioCardCategory.uncategorized)] \(text)"
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
            let snippet = "[\(card.category ?? ScenarioCardCategory.uncategorized)] \(normalized)"
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
        sharedClampTextValue(text, maxLength: maxLength, preserveLineBreak: preserveLineBreak)
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
}
