import SwiftUI

extension ScenarioWriterView {
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
}
