import SwiftUI
import AppKit

struct IndexBoardEditorDraft: Identifiable, Equatable {
    let cardID: UUID
    var frontText: String
    var showsBack: Bool

    var id: UUID { cardID }
}

@MainActor
private struct IndexBoardPhaseThreeEditorView: View {
    @Binding var draft: IndexBoardEditorDraft
    let card: SceneCard
    let theme: IndexBoardRenderTheme
    let summary: IndexBoardResolvedSummary?
    let onCancel: () -> Void
    let onSave: () -> Void

    @FocusState private var isFrontEditorFocused: Bool

    private var titleText: String {
        let trimmed = draft.frontText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let line = trimmed.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines),
           !line.isEmpty {
            return line
        }
        return "내용 없음"
    }

    private var categoryText: String {
        card.category ?? ScenarioCardCategory.uncategorized
    }

    var body: some View {
        ZStack {
            Color.black.opacity(theme.usesDarkAppearance ? 0.54 : 0.34)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header

                Picker("카드 면", selection: Binding(
                    get: { draft.showsBack },
                    set: { draft.showsBack = $0 }
                )) {
                    Text("앞면").tag(false)
                    Text("뒷면").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 20)

                if draft.showsBack {
                    backContent
                } else {
                    frontContent
                }

                footer
            }
            .frame(width: min(860, NSScreen.main?.visibleFrame.width ?? 860), height: 680)
            .background(theme.groupBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(theme.groupBorder.opacity(0.78), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(theme.usesDarkAppearance ? 0.34 : 0.18), radius: 30, x: 0, y: 20)
            .padding(36)
        }
        .onAppear {
            if !draft.showsBack {
                DispatchQueue.main.async {
                    isFrontEditorFocused = true
                }
            }
        }
        .onChange(of: draft.showsBack) { _, showsBack in
            if !showsBack {
                DispatchQueue.main.async {
                    isFrontEditorFocused = true
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(titleText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primaryTextColor)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Text(categoryText)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.secondaryTextColor)
                    Text("Board Editor")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.secondaryTextColor)
                    Text("Cmd+Enter 저장 · Esc 저장")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.secondaryTextColor)
                }
            }

            Spacer(minLength: 0)

            Button("닫기") {
                onSave()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 18)
        .background(theme.tabBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.groupBorder.opacity(0.65))
                .frame(height: 1)
        }
    }

    private var frontContent: some View {
        TextEditor(text: $draft.frontText)
            .font(.custom("SansMonoCJKFinalDraft", size: 18))
            .foregroundStyle(theme.primaryTextColor)
            .scrollContentBackground(.hidden)
            .background(theme.groupBackground)
            .focused($isFrontEditorFocused)
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var backContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(resolvedSummaryText)
                    .font(.custom("SansMonoCJKFinalDraft", size: 20))
                    .foregroundStyle(theme.primaryTextColor)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                HStack(spacing: 8) {
                    if let summary {
                        Text(summary.sourceLabelText)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.secondaryTextColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.black.opacity(theme.usesDarkAppearance ? 0.18 : 0.06))
                            )

                        if let updatedAt = summary.updatedAt {
                            Text(updatedAt.formatted(date: .numeric, time: .shortened))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(theme.secondaryTextColor)
                        }

                        if summary.isStale {
                            Text("STALE")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.orange.opacity(theme.usesDarkAppearance ? 0.94 : 0.88))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.orange.opacity(theme.usesDarkAppearance ? 0.20 : 0.14))
                                )
                            Text("원문이 바뀌어 요약이 오래됐습니다.")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.orange.opacity(theme.usesDarkAppearance ? 0.94 : 0.88))
                        }
                    } else {
                        Text("저장된 요약이 아직 없습니다.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.secondaryTextColor)
                    }
                }

                Text("현재 Phase에서는 summary sidecar를 읽기 전용으로 표시합니다.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.secondaryTextColor)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var resolvedSummaryText: String {
        summary?.summaryText ?? "요약이 아직 없습니다."
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            Button("저장 후 닫기") {
                onSave()
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accentColor.opacity(theme.usesDarkAppearance ? 0.84 : 0.92))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(theme.tabBackground.opacity(theme.usesDarkAppearance ? 0.88 : 0.78))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.groupBorder.opacity(0.55))
                .frame(height: 1)
        }
    }
}

@MainActor
struct IndexBoardPhaseThreeView: View {
    let surfaceProjection: BoardSurfaceProjection?
    let projection: IndexBoardProjection
    let sourceTitle: String
    let canvasSize: CGSize
    let theme: IndexBoardRenderTheme
    let cardsByID: [UUID: SceneCard]
    let activeCardID: UUID?
    let selectedCardIDs: Set<UUID>
    let summaryByCardID: [UUID: IndexBoardResolvedSummary]
    let showsBackByCardID: [UUID: Bool]
    let zoomScale: CGFloat
    let scrollOffset: CGPoint
    let revealCardID: UUID?
    let revealRequestToken: Int
    let editorDraft: IndexBoardEditorDraft?
    let editorSummary: IndexBoardResolvedSummary?
    let onClose: () -> Void
    let onCreateTempCard: () -> Void
    let onCardTap: (SceneCard) -> Void
    let onCardOpen: (SceneCard) -> Void
    let onCardFaceToggle: (SceneCard) -> Void
    let onZoomScaleChange: (CGFloat) -> Void
    let onZoomStep: (CGFloat) -> Void
    let onZoomReset: () -> Void
    let onScrollOffsetChange: (CGPoint) -> Void
    let onCardMove: (UUID, IndexBoardCardDropTarget) -> Void
    let onCardMoveSelection: ([UUID], UUID, IndexBoardCardDropTarget) -> Void
    let onMarqueeSelectionChange: (Set<UUID>) -> Void
    let onClearSelection: () -> Void
    let onGroupMove: (IndexBoardGroupID, Int) -> Void
    let onEditorDraftChange: (IndexBoardEditorDraft) -> Void
    let onCancelEditor: () -> Void
    let onSaveEditor: () -> Void

    private var editorCard: SceneCard? {
        guard let editorDraft else { return nil }
        if let card = cardsByID[editorDraft.cardID] {
            return card
        }
        return projection.groups
            .lazy
            .flatMap(\.childCards)
            .first(where: { $0.id == editorDraft.cardID })
    }

    var body: some View {
        ZStack {
            Group {
                if let surfaceProjection {
                    IndexBoardSurfacePhaseTwoView(
                        surfaceProjection: surfaceProjection,
                        sourceTitle: sourceTitle,
                        canvasSize: canvasSize,
                        theme: theme,
                        projection: projection,
                        cardsByID: cardsByID,
                        activeCardID: activeCardID,
                        selectedCardIDs: selectedCardIDs,
                        summaryByCardID: summaryByCardID,
                        showsBackByCardID: showsBackByCardID,
                        zoomScale: zoomScale,
                        scrollOffset: scrollOffset,
                        revealCardID: revealCardID,
                        revealRequestToken: revealRequestToken,
                        isInteractionEnabled: editorDraft == nil,
                        onClose: onClose,
                        onCreateTempCard: onCreateTempCard,
                        onCardTap: onCardTap,
                        onCardOpen: onCardOpen,
                        onCardFaceToggle: onCardFaceToggle,
                        onZoomScaleChange: onZoomScaleChange,
                        onZoomStep: onZoomStep,
                        onZoomReset: onZoomReset,
                        onScrollOffsetChange: onScrollOffsetChange,
                        onCardMove: onCardMove,
                        onCardMoveSelection: onCardMoveSelection,
                        onMarqueeSelectionChange: onMarqueeSelectionChange,
                        onClearSelection: onClearSelection,
                        onGroupMove: onGroupMove
                    )
                } else {
                    IndexBoardPhaseTwoView(
                        projection: projection,
                        sourceTitle: sourceTitle,
                        canvasSize: canvasSize,
                        theme: theme,
                        activeCardID: activeCardID,
                        selectedCardIDs: selectedCardIDs,
                        summaryByCardID: summaryByCardID,
                        showsBackByCardID: showsBackByCardID,
                        zoomScale: zoomScale,
                        scrollOffset: scrollOffset,
                        revealCardID: revealCardID,
                        revealRequestToken: revealRequestToken,
                        isInteractionEnabled: editorDraft == nil,
                        onClose: onClose,
                        onCreateTempCard: onCreateTempCard,
                        onCardTap: onCardTap,
                        onCardOpen: onCardOpen,
                        onCardFaceToggle: onCardFaceToggle,
                        onZoomScaleChange: onZoomScaleChange,
                        onZoomStep: onZoomStep,
                        onZoomReset: onZoomReset,
                        onScrollOffsetChange: onScrollOffsetChange,
                        onCardMove: onCardMove,
                        onGroupMove: onGroupMove
                    )
                }
            }
            .allowsHitTesting(editorDraft == nil)

            if let editorDraft,
               let editorCard {
                IndexBoardPhaseThreeEditorView(
                    draft: Binding(
                        get: { editorDraft },
                        set: { onEditorDraftChange($0) }
                    ),
                    card: editorCard,
                    theme: theme,
                    summary: editorSummary,
                    onCancel: onCancelEditor,
                    onSave: onSaveEditor
                )
            }
        }
    }
}

extension ScenarioWriterView {
    var isIndexBoardEditorPresented: Bool {
        indexBoardEditorDraft != nil
    }

    func presentIndexBoardEditor(for card: SceneCard) {
        guard isIndexBoardActive else { return }
        finishEditing()
        selectedCardIDs = [card.id]
        changeActiveCard(to: card, shouldFocusMain: false, deferToMainAsync: false, force: true)

        let showsBack = activeIndexBoardSession?.showsBackByCardID[card.id] ?? false
        indexBoardEditorDraft = IndexBoardEditorDraft(
            cardID: card.id,
            frontText: card.content,
            showsBack: showsBack
        )
        indexBoardRuntime.updateSession(for: scenario.id, paneID: paneContextID) { session in
            session.lastPresentedCardID = card.id
        }
        isMainViewFocused = true
    }

    func presentIndexBoardEditorForSelection() {
        guard isIndexBoardActive else { return }
        guard let projection = resolvedIndexBoardProjection() else { return }
        let orderedIDs = projection.orderedCardIDs
        let candidateID =
            activeCardID.flatMap { orderedIDs.contains($0) ? $0 : nil } ??
            orderedIDs.first(where: { selectedCardIDs.contains($0) }) ??
            orderedIDs.first
        guard let candidateID, let card = findCard(by: candidateID) else { return }
        presentIndexBoardEditor(for: card)
    }

    func updateIndexBoardEditorDraft(_ draft: IndexBoardEditorDraft) {
        guard isIndexBoardActive else { return }
        indexBoardEditorDraft = draft
        indexBoardRuntime.updateSession(for: scenario.id, paneID: paneContextID) { session in
            session.showsBackByCardID[draft.cardID] = draft.showsBack
            session.lastPresentedCardID = draft.cardID
        }
    }

    func cancelIndexBoardEditor() {
        saveIndexBoardEditor()
    }

    func saveIndexBoardEditor() {
        guard let draft = indexBoardEditorDraft else { return }
        guard let card = findCard(by: draft.cardID) else {
            indexBoardEditorDraft = nil
            return
        }

        var normalizedContent = draft.frontText
        while normalizedContent.hasSuffix("\n") {
            normalizedContent.removeLast()
        }

        selectedCardIDs = [card.id]
        changeActiveCard(to: card, shouldFocusMain: false, deferToMainAsync: false, force: true)
        indexBoardRuntime.updateSession(for: scenario.id, paneID: paneContextID) { session in
            session.showsBackByCardID[draft.cardID] = draft.showsBack
            session.lastPresentedCardID = draft.cardID
        }

        if normalizedContent != card.content {
            let previousState = captureScenarioState()
            card.content = normalizedContent
            commitCardMutation(
                previousState: previousState,
                actionName: "보드 카드 편집"
            )
            reconcileIndexBoardSummaries(for: [card.id])
        }

        indexBoardEditorDraft = nil
        isMainViewFocused = true
    }
}
