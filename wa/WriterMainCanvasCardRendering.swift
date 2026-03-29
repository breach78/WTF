import SwiftUI
import AppKit

struct CardItemContentLayer: View, Equatable {
    @ObservedObject var card: SceneCard
    let backgroundColor: Color
    let backgroundFingerprint: Int
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let preferredTextMeasureWidth: CGFloat
    let appearance: String
    let isEditing: Bool
    let mainEditorSlotCoordinateSpaceName: String?
    let mainEditorManagedExternally: Bool
    let usesExternalMainEditor: Bool
    let disablesInlineMainEditorFallback: Bool
    let externalEditorLiveBodyHeight: CGFloat?
    let onContentChange: ((String, String) -> Void)?
    let onMainEditorMount: ((UUID) -> Void)?
    let onMainEditorUnmount: ((UUID) -> Void)?
    let onMainEditorFocusStateChange: ((UUID, Bool) -> Void)?

    @State private var mainEditingMeasuredBodyHeight: CGFloat = 0
    @State private var mainEditingMeasureWorkItem: DispatchWorkItem? = nil
    @State private var mainEditingMeasureLastAt: Date = .distantPast
    @FocusState private var editorFocus: Bool

    private let mainCardContentPadding: CGFloat = MainEditorLayoutMetrics.mainCardContentPadding
    private let mainEditorVerticalPadding: CGFloat = 24
    private let mainEditorLineFragmentPadding: CGFloat = MainEditorLayoutMetrics.mainEditorLineFragmentPadding
    private let mainEditingMeasureMinInterval: TimeInterval = 0.033
    private let mainEditingMeasureUpdateThreshold: CGFloat = MainEditorLayoutMetrics.mainEditorHeightUpdateThreshold

    private var mainEditorHorizontalPadding: CGFloat {
        MainEditorLayoutMetrics.mainEditorHorizontalPadding
    }

    private var mainEditingTextMeasureWidth: CGFloat {
        max(1, preferredTextMeasureWidth)
    }

    private var alignedMainCardDisplayTextWidth: CGFloat? {
        guard mainEditorSlotCoordinateSpaceName != nil else { return nil }
        return max(1, preferredTextMeasureWidth - (mainEditorLineFragmentPadding * 2))
    }

    private var mainEditorBodyRenderedExternally: Bool {
        mainEditorManagedExternally || usesExternalMainEditor
    }

    private var shouldShowMainEditingTransitionShellText: Bool {
        isEditing && mainEditorManagedExternally && !usesExternalMainEditor
    }

    static func == (lhs: CardItemContentLayer, rhs: CardItemContentLayer) -> Bool {
        lhs.card.id == rhs.card.id &&
            lhs.backgroundFingerprint == rhs.backgroundFingerprint &&
            lhs.fontSize == rhs.fontSize &&
            lhs.lineSpacing == rhs.lineSpacing &&
            lhs.preferredTextMeasureWidth == rhs.preferredTextMeasureWidth &&
            lhs.appearance == rhs.appearance &&
            lhs.isEditing == rhs.isEditing &&
            lhs.mainEditorSlotCoordinateSpaceName == rhs.mainEditorSlotCoordinateSpaceName &&
            lhs.mainEditorManagedExternally == rhs.mainEditorManagedExternally &&
            lhs.usesExternalMainEditor == rhs.usesExternalMainEditor &&
            lhs.disablesInlineMainEditorFallback == rhs.disablesInlineMainEditorFallback &&
            lhs.externalEditorLiveBodyHeight == rhs.externalEditorLiveBodyHeight
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            backgroundColor
            cardEditorSlotContent
        }
        .onChange(of: isEditing) { _, newValue in
            mainWorkspacePhase0Log(
                "card-editing-flag-change",
                "card=\(mainWorkspacePhase0CardID(card.id)) isEditing=\(newValue) " +
                "measuredBody=\(mainEditingMeasuredBodyHeight) " +
                "responder=\(mainWorkspacePhase0ResponderSummary(expectedText: card.content))"
            )
            if newValue && !mainEditorBodyRenderedExternally {
                scheduleMainEditingMeasuredBodyHeightRefresh(immediate: true)
            } else {
                mainEditingMeasureWorkItem?.cancel()
                mainEditingMeasureWorkItem = nil
            }
        }
        .onDisappear {
            mainEditingMeasureWorkItem?.cancel()
            mainEditingMeasureWorkItem = nil
        }
    }

    @ViewBuilder
    private var mainCardDisplayText: some View {
        Text(card.content.isEmpty ? "내용 없음" : card.content)
            .font(.custom("SansMonoCJKFinalDraft", size: fontSize))
            .lineSpacing(lineSpacing)
            .foregroundStyle(
                card.content.isEmpty
                    ? (appearance == "light" ? .black.opacity(0.4) : .white.opacity(0.4))
                    : (appearance == "light" ? .black : .white)
            )
            .frame(width: alignedMainCardDisplayTextWidth, alignment: .leading)
            .padding(mainCardContentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var resolvedMainEditingBodyHeight: CGFloat {
        if mainEditorBodyRenderedExternally {
            if let externalEditorLiveBodyHeight, externalEditorLiveBodyHeight > 1 {
                return externalEditorLiveBodyHeight
            }
            return measureMainEditorBodyHeight(text: card.content, width: mainEditingTextMeasureWidth)
        }
        if mainEditingMeasuredBodyHeight > 1 {
            return mainEditingMeasuredBodyHeight
        }
        return measureMainEditorBodyHeight(text: card.content, width: mainEditingTextMeasureWidth)
    }

    private var mainEditorTextBinding: Binding<String> {
        Binding(
            get: { card.content },
            set: { newValue in
                let oldValue = card.content
                guard oldValue != newValue else { return }
                card.content = newValue
                onContentChange?(oldValue, newValue)
                scheduleMainEditingMeasuredBodyHeightRefresh()
            }
        )
    }

    private func liveMainResponderBodyHeight() -> CGFloat? {
        guard isEditing else { return nil }
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return nil }
        guard textView.string == card.content else { return nil }
        return sharedLiveTextViewBodyHeight(textView)
    }

    private func measureMainEditorBodyHeight(text: String, width: CGFloat) -> CGFloat {
        sharedMeasuredTextBodyHeight(
            text: text,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            width: width,
            lineFragmentPadding: mainEditorLineFragmentPadding,
            safetyInset: 0
        )
    }

    private func refreshMainEditingMeasuredBodyHeight() {
        guard !mainEditorBodyRenderedExternally else { return }
        let liveBodyHeight = liveMainResponderBodyHeight()
        let measured = liveBodyHeight
            ?? measureMainEditorBodyHeight(text: card.content, width: mainEditingTextMeasureWidth)
        mainEditingMeasureLastAt = Date()
        let previous = mainEditingMeasuredBodyHeight
        if abs(previous - measured) > mainEditingMeasureUpdateThreshold {
            mainEditingMeasuredBodyHeight = measured
            mainWorkspacePhase0Log(
                "inline-editor-row-height",
                "card=\(mainWorkspacePhase0CardID(card.id)) source=\(liveBodyHeight != nil ? "liveResponder" : "fallbackMeasure") " +
                "body=\(measured) row=\(measured + (mainEditorVerticalPadding * 2)) previous=\(previous) " +
                "isEditing=\(isEditing) responder=\(mainWorkspacePhase0ResponderSummary(expectedText: card.content))"
            )
        }
    }

    private func scheduleMainEditingMeasuredBodyHeightRefresh(immediate: Bool = false) {
        guard !mainEditorBodyRenderedExternally else {
            mainEditingMeasureWorkItem?.cancel()
            mainEditingMeasureWorkItem = nil
            return
        }

        if immediate {
            mainEditingMeasureWorkItem?.cancel()
            mainEditingMeasureWorkItem = nil
            refreshMainEditingMeasuredBodyHeight()
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(mainEditingMeasureLastAt)
        let delay = max(0, mainEditingMeasureMinInterval - elapsed)
        guard delay > 0.001 else {
            refreshMainEditingMeasuredBodyHeight()
            return
        }

        mainEditingMeasureWorkItem?.cancel()
        let work = DispatchWorkItem {
            mainEditingMeasureWorkItem = nil
            refreshMainEditingMeasuredBodyHeight()
        }
        mainEditingMeasureWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private var shouldReportMainEditorSlotFrame: Bool {
        mainEditorSlotCoordinateSpaceName != nil
    }

    private var externalMainEditorPlaceholder: some View {
        Color.clear
            .frame(
                width: MainCanvasLayoutMetrics.textWidth,
                height: resolvedMainEditingBodyHeight,
                alignment: .topLeading
            )
            .padding(.horizontal, mainEditorHorizontalPadding)
            .padding(.vertical, mainEditorVerticalPadding)
    }

    @ViewBuilder
    private var cardEditorSlotFrameReporter: some View {
        if shouldReportMainEditorSlotFrame,
           let coordinateSpaceName = mainEditorSlotCoordinateSpaceName {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: MainColumnEditorSlotPreferenceKey.self,
                    value: [
                        card.id: geometry.frame(in: .named(coordinateSpaceName))
                    ]
                )
            }
        }
    }

    @ViewBuilder
    private var cardEditorSlotContent: some View {
        ZStack(alignment: .topLeading) {
            if (!isEditing && !mainEditorBodyRenderedExternally) || shouldShowMainEditingTransitionShellText {
                mainCardDisplayText
            }

            if mainEditorBodyRenderedExternally || (isEditing && disablesInlineMainEditorFallback) {
                externalMainEditorPlaceholder
                    .onAppear {
                        mainWorkspacePhase0Log(
                            "inline-editor-placeholder-appear",
                            "card=\(mainWorkspacePhase0CardID(card.id)) " +
                            "managedExternally=\(mainEditorManagedExternally) usesExternal=\(usesExternalMainEditor) " +
                            "fallbackDisabled=\(disablesInlineMainEditorFallback) " +
                            "body=\(resolvedMainEditingBodyHeight)"
                        )
                    }
                    .onDisappear {
                        mainWorkspacePhase0Log(
                            "inline-editor-placeholder-disappear",
                            "card=\(mainWorkspacePhase0CardID(card.id)) managedExternally=\(mainEditorManagedExternally) " +
                            "usesExternal=\(usesExternalMainEditor) fallbackDisabled=\(disablesInlineMainEditorFallback) " +
                            "body=\(resolvedMainEditingBodyHeight)"
                        )
                    }
            } else if isEditing {
                TextEditor(text: mainEditorTextBinding)
                    .font(.custom("SansMonoCJKFinalDraft", size: fontSize))
                    .lineSpacing(lineSpacing)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .scrollIndicators(.never)
                    .frame(
                        width: MainCanvasLayoutMetrics.textWidth,
                        height: resolvedMainEditingBodyHeight,
                        alignment: .topLeading
                    )
                    .padding(.horizontal, mainEditorHorizontalPadding)
                    .padding(.vertical, mainEditorVerticalPadding)
                    .foregroundStyle(appearance == "light" ? .black : .white)
                    .focused($editorFocus)
                    .onAppear {
                        onMainEditorMount?(card.id)
                        mainWorkspacePhase0Log(
                            "inline-editor-appear",
                            "card=\(mainWorkspacePhase0CardID(card.id)) measuredBody=\(mainEditingMeasuredBodyHeight) " +
                            "responder=\(mainWorkspacePhase0ResponderSummary(expectedText: card.content))"
                        )
                        scheduleMainEditingMeasuredBodyHeightRefresh(immediate: true)
                        DispatchQueue.main.async {
                            let alreadyFocusedHere: Bool = {
                                guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
                                return textView.string == card.content
                            }()
                            if !alreadyFocusedHere {
                                editorFocus = true
                            }
                            mainWorkspacePhase0Log(
                                "inline-editor-focus-request",
                                "card=\(mainWorkspacePhase0CardID(card.id)) alreadyFocused=\(alreadyFocusedHere) " +
                                "editorFocus=\(editorFocus) responder=\(mainWorkspacePhase0ResponderSummary(expectedText: card.content))"
                            )
                            scheduleMainEditingMeasuredBodyHeightRefresh(immediate: true)
                        }
                    }
                    .onDisappear {
                        onMainEditorUnmount?(card.id)
                        mainWorkspacePhase0Log(
                            "inline-editor-disappear",
                            "card=\(mainWorkspacePhase0CardID(card.id)) measuredBody=\(mainEditingMeasuredBodyHeight) " +
                            "responder=\(mainWorkspacePhase0ResponderSummary(expectedText: card.content))"
                        )
                        mainEditingMeasureWorkItem?.cancel()
                        mainEditingMeasureWorkItem = nil
                    }
                    .onChange(of: editorFocus) { _, newValue in
                        onMainEditorFocusStateChange?(card.id, newValue)
                        mainWorkspacePhase0Log(
                            "inline-editor-focus-state",
                            "card=\(mainWorkspacePhase0CardID(card.id)) focused=\(newValue) " +
                            "responder=\(mainWorkspacePhase0ResponderSummary(expectedText: card.content))"
                        )
                    }
                    .onChange(of: fontSize) { _, _ in
                        scheduleMainEditingMeasuredBodyHeightRefresh(immediate: true)
                    }
                    .onChange(of: lineSpacing) { _, _ in
                        scheduleMainEditingMeasuredBodyHeightRefresh(immediate: true)
                    }
            }
        }
        .background(cardEditorSlotFrameReporter)
    }
}

struct MainCanvasCardItem: View {
    @ObservedObject var card: SceneCard
    @ObservedObject var interactionViewState: MainCanvasInteractionViewState
    let renderSettings: MainCardRenderSettings
    let isEditing: Bool
    let preferredTextMeasureWidth: CGFloat
    let forceNamedSnapshotNoteStyle: Bool
    let forceCustomColorVisibility: Bool
    var onInsertSiblingAbove: (() -> Void)? = nil
    var onInsertSiblingBelow: (() -> Void)? = nil
    var onAddChildCard: (() -> Void)? = nil
    var onDropBefore: (([NSItemProvider], Bool) -> Void)? = nil
    var onDropAfter: (([NSItemProvider], Bool) -> Void)? = nil
    var onDropOnto: (([NSItemProvider], Bool) -> Void)? = nil
    var onSelect: () -> Void
    var onDoubleClick: () -> Void
    var onEndEdit: () -> Void
    var onSelectAtLocation: ((CGPoint) -> Void)? = nil
    var onContentChange: ((String, String) -> Void)? = nil
    var onColorChange: ((String?) -> Void)? = nil
    var onOpenIndexBoard: (() -> Void)? = nil
    var onReferenceCard: (() -> Void)? = nil
    var onCreateUpperCardFromSelection: (() -> Void)? = nil
    var onSummarizeChildren: (() -> Void)? = nil
    var onAIElaborate: (() -> Void)? = nil
    var onAINextScene: (() -> Void)? = nil
    var onAIAlternative: (() -> Void)? = nil
    var onAISummarizeCurrent: (() -> Void)? = nil
    var aiPlotActionsEnabled: Bool = false
    var onApplyAICandidate: (() -> Void)? = nil
    var isSummarizingChildren: Bool = false
    var isAIBusy: Bool = false
    var onDelete: (() -> Void)? = nil
    var onHardDelete: (() -> Void)? = nil
    var onTranscriptionMode: (() -> Void)? = nil
    var isTranscriptionBusy: Bool = false
    var showsEmptyCardBulkDeleteMenuOnly: Bool = false
    var onBulkDeleteEmptyCards: (() -> Void)? = nil
    var isCloneLinked: Bool = false
    var hasLinkedCards: Bool = false
    var isLinkedCard: Bool = false
    var onDisconnectLinkedCard: (() -> Void)? = nil
    var onCloneCard: (() -> Void)? = nil
    var clonePeerDestinations: [ClonePeerMenuDestination] = []
    var onNavigateToClonePeer: ((UUID) -> Void)? = nil
    var mainEditorSlotCoordinateSpaceName: String? = nil
    var mainEditorManagedExternally: Bool = false
    var usesExternalMainEditor: Bool = false
    var disablesInlineMainEditorFallback: Bool = false
    var externalEditorLiveBodyHeight: CGFloat? = nil
    var onMainEditorMount: ((UUID) -> Void)? = nil
    var onMainEditorUnmount: ((UUID) -> Void)? = nil
    var onMainEditorFocusStateChange: ((UUID, Bool) -> Void)? = nil
    var handleEditorCommandBySelector: ((Selector) -> Bool)? = nil

    var body: some View {
        let interaction = interactionViewState.snapshot
        CardItem(
            card: card,
            renderSettings: renderSettings,
            isActive: interaction.activeCardID == card.id,
            isSelected: interaction.isSelected(card.id),
            isMultiSelected: interaction.isMultiSelected(card.id),
            isArchived: card.isArchived,
            isAncestor: interaction.isAncestor(card.id),
            isDescendant: interaction.isDescendant(card.id),
            isEditing: isEditing,
            preferredTextMeasureWidth: preferredTextMeasureWidth,
            forceNamedSnapshotNoteStyle: forceNamedSnapshotNoteStyle,
            forceCustomColorVisibility: forceCustomColorVisibility,
            onInsertSiblingAbove: onInsertSiblingAbove,
            onInsertSiblingBelow: onInsertSiblingBelow,
            onAddChildCard: onAddChildCard,
            onDropBefore: onDropBefore,
            onDropAfter: onDropAfter,
            onDropOnto: onDropOnto,
            onSelect: onSelect,
            onDoubleClick: onDoubleClick,
            onEndEdit: onEndEdit,
            onSelectAtLocation: onSelectAtLocation,
            onContentChange: onContentChange,
            onColorChange: onColorChange,
            onOpenIndexBoard: onOpenIndexBoard,
            onReferenceCard: onReferenceCard,
            onCreateUpperCardFromSelection: onCreateUpperCardFromSelection,
            onSummarizeChildren: onSummarizeChildren,
            onAIElaborate: onAIElaborate,
            onAINextScene: onAINextScene,
            onAIAlternative: onAIAlternative,
            onAISummarizeCurrent: onAISummarizeCurrent,
            aiPlotActionsEnabled: aiPlotActionsEnabled,
            onApplyAICandidate: onApplyAICandidate,
            isSummarizingChildren: isSummarizingChildren,
            isAIBusy: isAIBusy,
            onDelete: onDelete,
            onHardDelete: onHardDelete,
            onTranscriptionMode: onTranscriptionMode,
            isTranscriptionBusy: isTranscriptionBusy,
            showsEmptyCardBulkDeleteMenuOnly: showsEmptyCardBulkDeleteMenuOnly,
            onBulkDeleteEmptyCards: onBulkDeleteEmptyCards,
            isCloneLinked: isCloneLinked,
            hasLinkedCards: hasLinkedCards,
            isLinkedCard: isLinkedCard,
            onDisconnectLinkedCard: onDisconnectLinkedCard,
            onCloneCard: onCloneCard,
            clonePeerDestinations: clonePeerDestinations,
            onNavigateToClonePeer: onNavigateToClonePeer,
            mainEditorSlotCoordinateSpaceName: mainEditorSlotCoordinateSpaceName,
            mainEditorManagedExternally: mainEditorManagedExternally,
            usesExternalMainEditor: usesExternalMainEditor,
            disablesInlineMainEditorFallback: disablesInlineMainEditorFallback,
            externalEditorLiveBodyHeight: externalEditorLiveBodyHeight,
            onMainEditorMount: onMainEditorMount,
            onMainEditorUnmount: onMainEditorUnmount,
            onMainEditorFocusStateChange: onMainEditorFocusStateChange,
            handleEditorCommandBySelector: handleEditorCommandBySelector,
            isInteractionAffordanceFrozen: interaction.affordancesFrozen
        )
    }
}
