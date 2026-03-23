import SwiftUI
import AppKit

struct IndexBoardEditorDraft: Identifiable, Equatable {
    let cardID: UUID
    var contentText: String
    var summaryText: String
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

    private enum EditorField {
        case summary
        case content
    }

    @FocusState private var focusedField: EditorField?

    private var titleText: String {
        let trimmed = draft.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
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
        VStack(alignment: .leading, spacing: 0) {
            header
            editorContent
        }
        .frame(width: 860, height: 680)
        .background(theme.groupBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.groupBorder.opacity(0.78), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear {
            DispatchQueue.main.async {
                focusedField = .content
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
                    Text("요약 · 원문")
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

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            editorSection(
                title: "요약",
                text: $draft.summaryText,
                placeholder: summaryPlaceholder,
                focusedField: .summary,
                minHeight: 168,
                maxHeight: 220
            )

            editorSection(
                title: "원문",
                text: $draft.contentText,
                placeholder: "원문을 입력하세요",
                focusedField: .content,
                minHeight: nil,
                maxHeight: nil
            )
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var summaryPlaceholder: String {
        if let summary, summary.hasSummary {
            return summary.summaryText
        }
        return "요약이 없으면 비워둘 수 있습니다."
    }

    private func editorSection(
        title: String,
        text: Binding<String>,
        placeholder: String,
        focusedField targetField: EditorField,
        minHeight: CGFloat?,
        maxHeight: CGFloat?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.secondaryTextColor)
                if title == "요약", let summary {
                    Text(summary.sourceLabelText)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.secondaryTextColor)
                }
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.tabBackground.opacity(theme.usesDarkAppearance ? 0.82 : 0.72))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(theme.groupBorder.opacity(0.55), lineWidth: 1)

                if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(.custom("SansMonoCJKFinalDraft", size: 16))
                        .foregroundStyle(theme.secondaryTextColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }

                TextEditor(text: text)
                    .font(.custom("SansMonoCJKFinalDraft", size: 16))
                    .foregroundStyle(theme.primaryTextColor)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($focusedField, equals: targetField)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(minHeight: minHeight, maxHeight: maxHeight)
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
    let onCreateTempCardAt: (IndexBoardGridPosition?) -> Void
    let onCreateParentFromSelection: () -> Void
    let onSetParentGroupTemp: (UUID, Bool) -> Void
    let onSetCardColor: (UUID, String?) -> Void
    let onDeleteCard: (UUID) -> Void
    let onDeleteParentGroup: (UUID) -> Void
    let onCardTap: (SceneCard) -> Void
    let onCardDragStart: ([UUID], UUID) -> Void
    let onCardOpen: (SceneCard) -> Void
    let onParentCardOpen: (UUID) -> Void
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
    let onParentGroupMove: (IndexBoardParentGroupDropTarget) -> Void
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

    private var isEditorPresented: Binding<Bool> {
        Binding(
            get: { editorDraft != nil && editorCard != nil },
            set: { isPresented in
                guard !isPresented, editorDraft != nil else { return }
                onCancelEditor()
            }
        )
    }

    var body: some View {
        Group {
            if let surfaceProjection {
                IndexBoardSurfaceAppKitPhaseTwoView(
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
                    isInteractionEnabled: true,
                    onClose: onClose,
                    onCreateTempCard: onCreateTempCard,
                    onCreateTempCardAt: onCreateTempCardAt,
                    onCreateParentFromSelection: onCreateParentFromSelection,
                    onSetParentGroupTemp: onSetParentGroupTemp,
                    onSetCardColor: onSetCardColor,
                    onDeleteCard: onDeleteCard,
                    onDeleteParentGroup: onDeleteParentGroup,
                    onCardTap: onCardTap,
                    onCardDragStart: onCardDragStart,
                    onCardOpen: onCardOpen,
                    onParentCardOpen: onParentCardOpen,
                    onCardFaceToggle: onCardFaceToggle,
                    onZoomScaleChange: onZoomScaleChange,
                    onZoomStep: onZoomStep,
                    onZoomReset: onZoomReset,
                    onScrollOffsetChange: onScrollOffsetChange,
                    onCardMove: onCardMove,
                    onCardMoveSelection: onCardMoveSelection,
                    onMarqueeSelectionChange: onMarqueeSelectionChange,
                    onClearSelection: onClearSelection,
                    onGroupMove: onGroupMove,
                    onParentGroupMove: onParentGroupMove
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
                    isInteractionEnabled: true,
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
        .sheet(isPresented: isEditorPresented) {
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
                .frame(minWidth: 860, minHeight: 680)
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
        let showsBack = activeIndexBoardSession?.showsBackByCardID[card.id] ?? false
        indexBoardEditorDraft = IndexBoardEditorDraft(
            cardID: card.id,
            contentText: card.content,
            summaryText: resolvedIndexBoardSummary(for: card)?.summaryText ?? "",
            showsBack: showsBack
        )
        indexBoardRuntime.updateSession(for: scenario.id, paneID: paneContextID, persist: false) { session in
            session.lastPresentedCardID = card.id
        }
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
        indexBoardRuntime.updateSession(for: scenario.id, paneID: paneContextID, persist: false) { session in
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

        let existingSummaryText = resolvedIndexBoardSummary(for: card)?.summaryText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var normalizedContent = draft.contentText
        while normalizedContent.hasSuffix("\n") {
            normalizedContent.removeLast()
        }
        let normalizedSummary = draft.summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingShowsBack = activeIndexBoardSession?.showsBackByCardID[draft.cardID] ?? false

        let contentChanged = normalizedContent != card.content
        let summaryChanged = normalizedSummary != existingSummaryText
        let showsBackChanged = draft.showsBack != existingShowsBack
        let hasMeaningfulChange = contentChanged || summaryChanged || showsBackChanged

        let previousState = hasMeaningfulChange ? captureScenarioState() : nil

        indexBoardRuntime.updateSession(for: scenario.id, paneID: paneContextID, persist: false) { session in
            session.showsBackByCardID[draft.cardID] = draft.showsBack
            session.lastPresentedCardID = draft.cardID
        }

        if contentChanged {
            card.content = normalizedContent
        }

        if summaryChanged {
            setIndexBoardManualSummary(for: card, summaryText: normalizedSummary)
        }

        if contentChanged || summaryChanged {
            reconcileIndexBoardSummaries(for: [card.id])
        }

        if let previousState {
            commitCardMutation(
                previousState: previousState,
                actionName: "보드 카드 편집"
            )
        }

        indexBoardEditorDraft = nil
    }
}
