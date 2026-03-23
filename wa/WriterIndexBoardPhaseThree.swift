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
private struct IndexBoardEditorTextView: NSViewRepresentable {
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: IndexBoardEditorTextView
        var suppressBindingPropagation = false

        init(_ parent: IndexBoardEditorTextView) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.onFocus()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !suppressBindingPropagation else { return }
            let updatedText = textView.string
            if parent.text != updatedText {
                parent.text = updatedText
            }
        }
    }

    @Binding var text: String
    let font: NSFont
    let textColor: NSColor
    let lineSpacing: CGFloat
    let isFocused: Bool
    let textViewBox: WeakTextViewBox?
    let onFocus: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.usesFindBar = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]

        if let textContainer = textView.textContainer {
            textContainer.lineFragmentPadding = 0
            textContainer.lineBreakMode = .byWordWrapping
            textContainer.maximumNumberOfLines = 0
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false
            textContainer.containerSize = CGSize(width: 1, height: CGFloat.greatestFiniteMagnitude)
        }

        textViewBox?.textView = textView
        scrollView.documentView = textView
        updateTextView(textView, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textViewBox?.textView = textView
        if textView.delegate !== context.coordinator {
            textView.delegate = context.coordinator
        }
        updateTextView(textView, coordinator: context.coordinator)
    }

    private func updateTextView(_ textView: NSTextView, coordinator: Coordinator) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = lineSpacing

        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        textView.defaultParagraphStyle = paragraphStyle

        var typingAttributes = textView.typingAttributes
        typingAttributes[.font] = font
        typingAttributes[.foregroundColor] = textColor
        typingAttributes[.paragraphStyle] = paragraphStyle
        textView.typingAttributes = typingAttributes

        let isComposingMarkedText =
            textView.hasMarkedText() &&
            textView.window?.firstResponder === textView

        if textView.string != text && !isComposingMarkedText {
            let selectedRange = textView.selectedRange()
            coordinator.suppressBindingPropagation = true
            textView.string = text
            if let textStorage = textView.textStorage, textStorage.length > 0 {
                textStorage.addAttributes(
                    [
                        .font: font,
                        .foregroundColor: textColor,
                        .paragraphStyle: paragraphStyle
                    ],
                    range: NSRange(location: 0, length: textStorage.length)
                )
            }
            let textLength = (text as NSString).length
            let clampedLocation = min(selectedRange.location, textLength)
            let clampedLength = min(selectedRange.length, max(0, textLength - clampedLocation))
            textView.setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
            coordinator.suppressBindingPropagation = false
        }

        if isFocused,
           let window = textView.window,
           window.firstResponder !== textView {
            DispatchQueue.main.async {
                guard isFocused, let liveWindow = textView.window, liveWindow.firstResponder !== textView else { return }
                liveWindow.makeFirstResponder(textView)
            }
        }
    }
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
    @State private var summaryTextViewBox = WeakTextViewBox()
    @State private var contentTextViewBox = WeakTextViewBox()

    private let editorCardBackground = Color.white
    private let editorCardBorder = Color.black.opacity(0.16)
    private let editorDivider = Color(red: 0.82, green: 0.24, blue: 0.19)
    private let editorPrimaryText = Color.black.opacity(0.84)
    private let editorSecondaryText = Color.black.opacity(0.42)

    private var contentPreviewText: String {
        let trimmed = draft.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(2)
            .joined(separator: "\n")
        if !normalized.isEmpty {
            return normalized
        }
        return "내용 없음"
    }

    private var hasCustomSummary: Bool {
        !draft.summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showsSummaryPlaceholder: Bool {
        !hasCustomSummary && focusedField != .summary
    }

    private func enforceInitialContentFocus() {
        focusedField = nil
        let delays: [TimeInterval] = [0, 0.05, 0.16]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                focusedField = .content
                guard let textView = contentTextViewBox.textView,
                      let window = textView.window else { return }
                if window.firstResponder !== textView {
                    window.makeFirstResponder(textView)
                }
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let headerHeight = max(76, min(108, proxy.size.height / 9))

            VStack(alignment: .leading, spacing: 0) {
                header
                    .frame(height: headerHeight, alignment: .topLeading)
                editorContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 860, height: 680)
        .background(editorCardBackground)
        .overlay(
            Rectangle()
                .stroke(editorCardBorder, lineWidth: 1)
        )
        .onAppear {
            enforceInitialContentFocus()
        }
    }

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            headerSummaryEditor

            Button {
                onSave()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(editorSecondaryText)
            }
            .buttonStyle(.plain)
            .padding(.top, 13)
            .padding(.trailing, 4)
            .offset(x: 60, y: -5)
            .help("닫기")
        }
        .padding(.leading, 28)
        .padding(.trailing, 108)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background(editorCardBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(editorDivider)
                .frame(height: 2)
        }
    }

    private var headerSummaryEditor: some View {
        ZStack(alignment: .topLeading) {
            if showsSummaryPlaceholder {
                Text(contentPreviewText)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(editorSecondaryText)
                    .lineSpacing(3)
                    .lineLimit(2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .offset(y: 17)
                    .allowsHitTesting(false)
            }

            IndexBoardEditorTextView(
                text: $draft.summaryText,
                font: .systemFont(ofSize: 20, weight: hasCustomSummary ? .bold : .semibold),
                textColor: NSColor(editorPrimaryText),
                lineSpacing: 3,
                isFocused: focusedField == .summary,
                textViewBox: summaryTextViewBox,
                onFocus: {
                    focusedField = .summary
                }
            )
                .padding(.horizontal, -5)
                .padding(.vertical, -8)
                .offset(y: 17)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = .summary
        }
    }

    private var editorContent: some View {
        ZStack(alignment: .topLeading) {
            editorCardBackground

            if draft.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("원문을 입력하세요")
                    .font(.custom("SansMonoCJKFinalDraft", size: 16))
                    .foregroundStyle(editorSecondaryText)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 24)
                    .allowsHitTesting(false)
            }

            IndexBoardEditorTextView(
                text: $draft.contentText,
                font: NSFont(name: "SansMonoCJKFinalDraft", size: 16) ?? .monospacedSystemFont(ofSize: 16, weight: .regular),
                textColor: NSColor(editorPrimaryText),
                lineSpacing: 0,
                isFocused: focusedField == .content,
                textViewBox: contentTextViewBox,
                onFocus: {
                    focusedField = .content
                }
            )
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    let editorDraftBinding: Binding<IndexBoardEditorDraft?>
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
    let onViewportFinalize: (CGFloat, CGPoint) -> Void
    let onShowCheckpoint: () -> Void
    let onToggleHistory: () -> Void
    let onToggleAIChat: () -> Void
    let onToggleTimeline: () -> Void
    let isHistoryVisible: Bool
    let isAIChatVisible: Bool
    let isTimelineVisible: Bool
    let onCardMove: (UUID, IndexBoardCardDropTarget) -> Void
    let onCardMoveSelection: ([UUID], UUID, IndexBoardCardDropTarget) -> Void
    let onMarqueeSelectionChange: (Set<UUID>) -> Void
    let onClearSelection: () -> Void
    let onGroupMove: (IndexBoardGroupID, Int) -> Void
    let onParentGroupMove: (IndexBoardParentGroupDropTarget) -> Void
    let onCancelEditor: () -> Void
    let onSaveEditor: () -> Void

    private var editorDraft: IndexBoardEditorDraft? {
        editorDraftBinding.wrappedValue
    }

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
                    onViewportFinalize: onViewportFinalize,
                    onShowCheckpoint: onShowCheckpoint,
                    onToggleHistory: onToggleHistory,
                    onToggleAIChat: onToggleAIChat,
                    onToggleTimeline: onToggleTimeline,
                    isHistoryVisible: isHistoryVisible,
                    isAIChatVisible: isAIChatVisible,
                    isTimelineVisible: isTimelineVisible,
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
                        get: { editorDraftBinding.wrappedValue ?? editorDraft },
                        set: { editorDraftBinding.wrappedValue = $0 }
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
    }

    private func discardPendingIndexBoardCreation(cardID: UUID, previousState: ScenarioState) {
        pendingIndexBoardCreationPrevStateByCardID.removeValue(forKey: cardID)
        restoreScenarioState(previousState)
    }

    func cancelIndexBoardEditor() {
        saveIndexBoardEditor()
    }

    func saveIndexBoardEditor() {
        guard let draft = indexBoardEditorDraft else { return }
        let pendingCreationPreviousState = pendingIndexBoardCreationPrevStateByCardID[draft.cardID]
        guard let card = findCard(by: draft.cardID) else {
            pendingIndexBoardCreationPrevStateByCardID.removeValue(forKey: draft.cardID)
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
        let isMeaningfullyEmpty =
            normalizedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            normalizedSummary.isEmpty

        if let pendingCreationPreviousState, isMeaningfullyEmpty {
            discardPendingIndexBoardCreation(
                cardID: draft.cardID,
                previousState: pendingCreationPreviousState
            )
            return
        }

        let contentChanged = normalizedContent != card.content
        let summaryChanged = normalizedSummary != existingSummaryText
        let showsBackChanged = draft.showsBack != existingShowsBack
        let hasMeaningfulChange = contentChanged || summaryChanged || showsBackChanged

        let previousState: ScenarioState? = {
            if let pendingCreationPreviousState {
                return pendingCreationPreviousState
            }
            return hasMeaningfulChange ? captureScenarioState() : nil
        }()

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
                actionName: pendingCreationPreviousState == nil ? "보드 카드 편집" : "보드 Temp 카드 생성"
            )
        }

        pendingIndexBoardCreationPrevStateByCardID.removeValue(forKey: draft.cardID)
        indexBoardEditorDraft = nil
    }
}
