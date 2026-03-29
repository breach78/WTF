import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 카드 사이 및 열 상/하단 빈 공간 드롭 영역

struct DropSpacer: View {
    let target: DropTarget
    var alignment: Alignment = .center
    let onDrop: ([NSItemProvider], Bool) -> Void
    @AppStorage("mainCardVerticalGap") private var mainCardVerticalGap: Double = 0.0
    @State private var isHovering: Bool = false

    private var centerGapHeight: CGFloat { max(0, CGFloat(mainCardVerticalGap)) }
    private var centerHitAreaHeight: CGFloat { max(12, centerGapHeight) }

    var body: some View {
        Group {
            if alignment == .center {
                Color.clear
                    .frame(height: centerGapHeight)
                    .overlay(alignment: .center) {
                        ZStack {
                            Color.black.opacity(0.001)
                            if isHovering {
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(height: 4)
                                    .cornerRadius(2)
                                    .transition(.opacity)
                            }
                        }
                        .frame(height: centerHitAreaHeight)
                        .contentShape(Rectangle())
                        .onDrop(of: [.text], isTargeted: $isHovering) { providers in
                            onDrop(providers, isTrailingSiblingBlockDragActive())
                            return true
                        }
                    }
            } else {
                ZStack(alignment: alignment) {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())

                    if isHovering {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 4)
                            .cornerRadius(2)
                            .transition(.opacity)
                    }
                }
                .onDrop(of: [.text], isTargeted: $isHovering) { providers in
                    onDrop(providers, isTrailingSiblingBlockDragActive())
                    return true
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}

// MARK: - 히스토리 프리뷰 카드

struct PreviewCardItem: View {
    let diff: SnapshotDiff
    let isSelected: Bool
    let isMultiSelected: Bool
    var onSelect: () -> Void
    var onCopyCards: () -> Void
    var onCopyContents: () -> Void
    @AppStorage("fontSize") private var fontSize: Double = 14.0
    @AppStorage("appearance") private var appearance: String = "dark"

    private var statusColor: Color {
        switch diff.status {
        case .added: return Color.blue.opacity(0.15)
        case .modified: return Color.yellow.opacity(0.15)
        case .deleted: return Color.red.opacity(0.15)
        case .none: return appearance == "light" ? Color.white : Color(white: 0.18)
        }
    }

    private var statusStrokeColor: Color {
        switch diff.status {
        case .added: return .blue
        case .modified: return .yellow
        case .deleted: return .red
        case .none: return .secondary.opacity(0.3)
        }
    }

    private var selectionFillColor: Color {
        guard isSelected else { return .clear }
        return Color.accentColor.opacity(isMultiSelected ? 0.24 : 0.14)
    }

    private var selectionStrokeColor: Color {
        guard isSelected else { return .clear }
        return Color.accentColor.opacity(isMultiSelected ? 0.95 : 0.75)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if diff.status != .none {
                Text(statusLabel).font(.system(size: 9, weight: .bold)).foregroundColor(statusStrokeColor).padding(.horizontal, 6).padding(.vertical, 2).background(statusStrokeColor.opacity(0.1)).cornerRadius(4).padding([.top, .leading], 8)
            }
            Text(diff.snapshot.content.isEmpty ? "내용 없음" : diff.snapshot.content).font(.custom("SansMonoCJKFinalDraft", size: fontSize)).lineSpacing(1.4).padding(12).frame(maxWidth: .infinity, alignment: .leading).strikethrough(diff.status == .deleted).opacity(diff.status == .deleted ? 0.6 : 1.0)
        }
        .background(statusColor)
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(statusStrokeColor, lineWidth: diff.status == .none ? 1 : 2))
        .overlay(RoundedRectangle(cornerRadius: 4).fill(selectionFillColor))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(selectionStrokeColor, lineWidth: isSelected ? (isMultiSelected ? 2 : 1) : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("카드 복사") { onCopyCards() }
            Button("내용 복사") { onCopyContents() }
        }
    }

    private var statusLabel: String { switch diff.status { case .added: return "NEW"; case .modified: return "EDITED"; case .deleted: return "삭제됨"; case .none: return "" } }
}

// MARK: - 포커스 모드 카드 에디터

struct FocusModeCardEditor: View {
    @ObservedObject var card: SceneCard
    let isActive: Bool
    let showsEditor: Bool
    @ObservedObject var layoutCoordinator: FocusModeLayoutCoordinator
    let cardWidth: CGFloat
    let fontSize: Double
    let appearance: String
    let horizontalInset: CGFloat
    @FocusState.Binding var focusModeEditorCardID: UUID?
    let onActivate: (CGPoint?) -> Void
    let onContentChange: (String, String) -> Void

    @AppStorage("focusModeLineSpacingValueTemp") private var focusModeLineSpacingValue: Double = 4.5
    static let verticalInset: CGFloat = 40
    private var verticalInset: CGFloat { Self.verticalInset }
    private var shellHeight: CGFloat {
        layoutCoordinator.resolvedCardHeight(
            for: card,
            cardWidth: cardWidth,
            fontSize: fontSize,
            lineSpacing: focusModeLineSpacingValue,
            verticalInset: verticalInset,
            liveEditorCardID: showsEditor ? card.id : nil
        )
    }
    private var textEditorBodyHeight: CGFloat {
        max(1, shellHeight - (verticalInset * 2))
    }
    private var focusModeFontSize: CGFloat { CGFloat(fontSize * 1.2) }
    private var focusModeLineSpacing: CGFloat { CGFloat(focusModeLineSpacingValue) }
    private var displayText: String {
        normalizedSharedMeasurementText(card.content)
    }

    private var focusModeTextBinding: Binding<String> {
        Binding(
            get: { card.content },
            set: { newValue in
                let oldValue = card.content
                guard oldValue != newValue else { return }
                card.content = newValue
                onContentChange(oldValue, newValue)
            }
        )
    }

    var body: some View {
        Group {
            if showsEditor {
                focusModeCardContent
            } else {
                focusModeCardContent
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                onActivate(value.location)
                            }
                    )
                    .onTapGesture {
                        onActivate(nil)
                    }
            }
        }
    }

    @ViewBuilder
    private var focusModeCardContent: some View {
        ZStack(alignment: .topLeading) {
            if showsEditor {
                FocusModeEditableTextRenderer(
                    text: focusModeTextBinding,
                    cardID: card.id,
                    layoutCoordinator: layoutCoordinator,
                    textWidth: FocusModeLayoutMetrics.resolvedTextWidth(for: cardWidth),
                    bodyHeight: textEditorBodyHeight,
                    fontSize: focusModeFontSize,
                    lineSpacing: focusModeLineSpacing,
                    appearance: appearance,
                    isFocused: showsEditor
                )
                .frame(height: textEditorBodyHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, horizontalInset)
                .padding(.top, verticalInset)
                .padding(.bottom, verticalInset)
            } else {
                FocusModeReadOnlyTextRenderer(
                    text: displayText,
                    textWidth: FocusModeLayoutMetrics.resolvedTextWidth(for: cardWidth),
                    bodyHeight: textEditorBodyHeight,
                    fontSize: focusModeFontSize,
                    lineSpacing: focusModeLineSpacing,
                    appearance: appearance
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, horizontalInset)
                .padding(.top, verticalInset)
                .padding(.bottom, verticalInset)
                .allowsHitTesting(false)
            }
        }
        .frame(width: cardWidth, alignment: .topLeading)
        .frame(height: shellHeight, alignment: .topLeading)
    }

}

// MARK: - 메인 카드 아이템

struct CardItem: View {
    private enum InlineInsertZoneEdge {
        case top
        case bottom
        case trailing
    }

    @ObservedObject var card: SceneCard
    let renderSettings: MainCardRenderSettings
    let isActive, isSelected, isMultiSelected, isArchived, isAncestor, isDescendant, isEditing: Bool
    let preferredTextMeasureWidth: CGFloat
    let forceNamedSnapshotNoteStyle: Bool
    let forceCustomColorVisibility: Bool
    var onInsertSiblingAbove: (() -> Void)? = nil
    var onInsertSiblingBelow: (() -> Void)? = nil
    var onAddChildCard: (() -> Void)? = nil
    var onDropBefore: (([NSItemProvider], Bool) -> Void)? = nil
    var onDropAfter: (([NSItemProvider], Bool) -> Void)? = nil
    var onDropOnto: (([NSItemProvider], Bool) -> Void)? = nil
    var onSelect, onDoubleClick, onEndEdit: () -> Void
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
    var isInteractionAffordanceFrozen: Bool = false
    @State private var isTopInsertZoneHovered: Bool = false
    @State private var isBottomInsertZoneHovered: Bool = false
    @State private var isTrailingInsertZoneHovered: Bool = false
    @State private var isTopInsertZoneDropTargeted: Bool = false
    @State private var isBottomInsertZoneDropTargeted: Bool = false
    @State private var isTrailingInsertZoneDropTargeted: Bool = false
    @State private var isBodyDropTargeted: Bool = false
    @State private var lastSpatialTapUptime: TimeInterval = -.greatestFiniteMagnitude
    private var fontSize: CGFloat { renderSettings.fontSize }
    private var appearance: String { renderSettings.appearance }
    private var cardBaseColorHex: String { renderSettings.cardBaseColorHex }
    private var cardActiveColorHex: String { renderSettings.cardActiveColorHex }
    private var cardRelatedColorHex: String { renderSettings.cardRelatedColorHex }
    private var darkCardBaseColorHex: String { renderSettings.darkCardBaseColorHex }
    private var darkCardActiveColorHex: String { renderSettings.darkCardActiveColorHex }
    private var darkCardRelatedColorHex: String { renderSettings.darkCardRelatedColorHex }
    private var mainCardLineSpacing: CGFloat { renderSettings.lineSpacing }

    private var usesDarkPalette: Bool {
        if appearance == "dark" { return true }
        if appearance == "light" { return false }
        if let best = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
            return best == .darkAqua
        }
        return true
    }

    private var isCandidateVisualCard: Bool {
        (forceCustomColorVisibility || card.isAICandidate) && card.colorHex != nil
    }
    private var shouldShowChildRightEdge: Bool {
        !isArchived && !card.children.isEmpty
    }
    private var hasAIMenuActions: Bool {
        onAIElaborate != nil
            || onAINextScene != nil
            || onAIAlternative != nil
            || onAISummarizeCurrent != nil
            || onSummarizeChildren != nil
    }
    private var childRightEdgeColor: Color {
        let amount = usesDarkPalette ? 0.34 : 0.24
        let rgb = mix(base: resolvedBaseRGB(), overlay: (0, 0, 0), amount: amount)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private var insertZoneHighlightColor: Color {
        usesDarkPalette ? Color.white.opacity(0.22) : Color.black.opacity(0.18)
    }

    private var insertIndicatorColor: Color {
        usesDarkPalette ? Color.white.opacity(0.92) : Color.black.opacity(0.72)
    }

    private var shouldShowInlineInsertControls: Bool {
        !isArchived && !isEditing && !mainEditorBodyRenderedExternally
    }

    private var bodyDropTrailingInset: CGFloat {
        (shouldShowInlineInsertControls && onAddChildCard != nil) ? trailingInsertZoneWidth : 0
    }

    private var contentBackgroundColor: Color {
        if isArchived {
            return appearance == "light" ? Color.gray.opacity(0.25) : Color.gray.opacity(0.35)
        }
        let rgb = resolvedBaseRGB()
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private var contentBackgroundFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(isArchived)
        hasher.combine(appearance)
        hasher.combine(forceNamedSnapshotNoteStyle)
        hasher.combine(forceCustomColorVisibility)
        hasher.combine(card.isAICandidate)
        hasher.combine(card.colorHex)
        return hasher.finalize()
    }

    private var multiSelectionBackgroundColor: Color {
        let base = resolvedBaseRGB()
        let overlay = usesDarkPalette ? (r: 0.42, g: 0.56, b: 0.78) : (r: 0.70, g: 0.83, b: 0.98)
        let amount = usesDarkPalette ? 0.58 : 0.62
        let rgb = mix(base: base, overlay: overlay, amount: amount)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private var relatedBackgroundColor: Color {
        let rgb = resolvedRelatedRGB()
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private var descendantBackgroundColor: Color {
        let rgb = resolvedDescendantRGB()
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private var activeBackgroundColor: Color {
        let rgb = resolvedActiveRGB()
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private var usesFocusFadeTint: Bool {
        !isArchived && !isCandidateVisualCard
    }

    private var relatedTintOpacity: Double {
        guard usesFocusFadeTint else { return 0 }
        return (!isActive && isAncestor) ? 1 : 0
    }

    private var descendantTintOpacity: Double {
        guard usesFocusFadeTint else { return 0 }
        return (!isActive && isDescendant) ? 1 : 0
    }

    private var activeTintOpacity: Double {
        guard usesFocusFadeTint else { return 0 }
        return isActive ? 1 : 0
    }

    private var cardBorderColor: Color {
        if usesDarkPalette {
            return Color.white.opacity(0.12)
        }
        return Color.black.opacity(0.10)
    }

    private let horizontalInsertZoneHeight: CGFloat = 27
    private let horizontalInsertZoneWidth: CGFloat = 60
    private let trailingInsertZoneWidth: CGFloat = 30
    private let plainTapFallbackSuppressionWindow: TimeInterval = 0.25

    private func insertZoneHighlightFill(for edge: InlineInsertZoneEdge) -> AnyShapeStyle {
        let strong = usesDarkPalette ? Color.white.opacity(0.32) : Color.black.opacity(0.24)
        let soft = usesDarkPalette ? Color.white.opacity(0.16) : Color.black.opacity(0.10)

        switch edge {
        case .top:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [strong, soft, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .bottom:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [strong, soft, .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
        case .trailing:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [strong, soft, .clear],
                    startPoint: .trailing,
                    endPoint: .leading
                )
            )
        }
    }

    private var mainEditorBodyRenderedExternally: Bool {
        mainEditorManagedExternally || usesExternalMainEditor
    }

    @ViewBuilder
    private var cardContextMenuContent: some View {
        if let onDisconnectLinkedCard {
            Button("연결 끊기", role: .destructive) { onDisconnectLinkedCard() }
            Divider()
        }
        if showsEmptyCardBulkDeleteMenuOnly {
            if let onOpenIndexBoard {
                Button("인덱스 카드 뷰로 보기") { onOpenIndexBoard() }
                Divider()
            }
            if hasAIMenuActions {
                Menu("AI") {
                    Button("구체화") { onAIElaborate?() }
                        .disabled(onAIElaborate == nil || !aiPlotActionsEnabled || isAIBusy)
                    Button("다음 장면") { onAINextScene?() }
                        .disabled(onAINextScene == nil || !aiPlotActionsEnabled || isAIBusy)
                    Button("대안") { onAIAlternative?() }
                        .disabled(onAIAlternative == nil || !aiPlotActionsEnabled || isAIBusy)
                    Divider()
                    Button("선택 카드 요약") { onAISummarizeCurrent?() }
                        .disabled(onAISummarizeCurrent == nil || isAIBusy)
                    Button("자식 카드 요약") { onSummarizeChildren?() }
                        .disabled(onSummarizeChildren == nil || isAIBusy)
                }
                if onBulkDeleteEmptyCards != nil {
                    Divider()
                }
            }
            if let onTranscriptionMode {
                Button("전사 모드") { onTranscriptionMode() }
                    .disabled(isTranscriptionBusy || isAIBusy)
                if onBulkDeleteEmptyCards != nil {
                    Divider()
                }
            }
            if let onBulkDeleteEmptyCards {
                Button("내용 없음 카드 전체 삭제", role: .destructive) { onBulkDeleteEmptyCards() }
            }
        } else {
            if let onOpenIndexBoard {
                Button("인덱스 카드 뷰로 보기") { onOpenIndexBoard() }
                Divider()
            }
            if let onCloneCard {
                Button("클론 카드") { onCloneCard() }
                Divider()
            }
            if let onNavigateToClonePeer, !clonePeerDestinations.isEmpty {
                Menu("다른 클론으로 이동") {
                    ForEach(clonePeerDestinations) { destination in
                        Button(destination.title) { onNavigateToClonePeer(destination.id) }
                    }
                }
                Divider()
            }
            if let onReferenceCard {
                Button("레퍼런스 카드로") { onReferenceCard() }
                Divider()
            }
            if let onCreateUpperCardFromSelection {
                Button("새 상위 카드 만들기") { onCreateUpperCardFromSelection() }
                Divider()
            }
            if hasAIMenuActions {
                Menu("AI") {
                    Button("구체화") { onAIElaborate?() }
                        .disabled(onAIElaborate == nil || !aiPlotActionsEnabled || isAIBusy)
                    Button("다음 장면") { onAINextScene?() }
                        .disabled(onAINextScene == nil || !aiPlotActionsEnabled || isAIBusy)
                    Button("대안") { onAIAlternative?() }
                        .disabled(onAIAlternative == nil || !aiPlotActionsEnabled || isAIBusy)
                    Divider()
                    Button("선택 카드 요약") { onAISummarizeCurrent?() }
                        .disabled(onAISummarizeCurrent == nil || isAIBusy)
                    Button("자식 카드 요약") { onSummarizeChildren?() }
                        .disabled(onSummarizeChildren == nil || isAIBusy)
                }
                Divider()
            }
            if let onDelete {
                Button("삭제", role: .destructive) { onDelete() }
            }
            if onDelete != nil {
                Divider()
            }
            if let onColorChange {
                Menu("카드 색") {
                    Button("기본") { onColorChange(nil) }
                    Divider()
                    Button("연보라") { onColorChange("E7D5FF") }
                    Button("하늘") { onColorChange("CFE8FF") }
                    Button("민트") { onColorChange("CFF2E8") }
                    Button("살구") { onColorChange("FFE1CC") }
                    Button("연노랑") { onColorChange("FFF3C4") }
                }
            }
            if let onTranscriptionMode {
                Divider()
                Button("전사 모드") { onTranscriptionMode() }
                    .disabled(isTranscriptionBusy || isAIBusy)
            }
            if let onHardDelete {
                Divider()
                Button("완전 삭제 (모든 곳)", role: .destructive) { onHardDelete() }
            }
        }
    }

    @ViewBuilder
    private var cardInteractionBackdrop: some View {
        ZStack(alignment: .topLeading) {
            contentBackgroundColor

            if isMultiSelected {
                multiSelectionBackgroundColor
            } else if usesFocusFadeTint {
                relatedBackgroundColor
                    .opacity(relatedTintOpacity)

                descendantBackgroundColor
                    .opacity(descendantTintOpacity)

                activeBackgroundColor
                    .opacity(activeTintOpacity)
            }
        }
        .allowsHitTesting(false)
    }

    private func cardChromeApplied<Content: View>(to content: Content) -> some View {
        content
        .overlay {
            if let onDropOnto {
                cardBodyDropZone(onDrop: onDropOnto)
            }
        }
        .overlay(alignment: .trailing) {
            ZStack(alignment: .trailing) {
                if shouldShowInlineInsertControls, let onAddChildCard {
                    inlineInsertZone(
                        isHovered: $isTrailingInsertZoneHovered,
                        isDropTargeted: $isTrailingInsertZoneDropTargeted,
                        edge: .trailing,
                        axis: .vertical,
                        action: onAddChildCard,
                        onDrop: nil
                    )
                }
                if shouldShowChildRightEdge {
                    Rectangle()
                        .fill(childRightEdgeColor)
                        .frame(width: 4)
                        .allowsHitTesting(false)
                }
            }
        }
        .overlay(alignment: .top) {
            if shouldShowInlineInsertControls, let onInsertSiblingAbove {
                inlineInsertZone(
                    isHovered: $isTopInsertZoneHovered,
                    isDropTargeted: $isTopInsertZoneDropTargeted,
                    edge: .top,
                    axis: .horizontal,
                    action: onInsertSiblingAbove,
                    onDrop: onDropBefore
                )
            }
        }
        .overlay(alignment: .bottom) {
            if shouldShowInlineInsertControls, let onInsertSiblingBelow {
                inlineInsertZone(
                    isHovered: $isBottomInsertZoneHovered,
                    isDropTargeted: $isBottomInsertZoneDropTargeted,
                    edge: .bottom,
                    axis: .horizontal,
                    action: onInsertSiblingBelow,
                    onDrop: onDropAfter
                )
            }
        }
        .overlay {
            Rectangle()
                .stroke(cardBorderColor, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                if isCandidateVisualCard {
                    VStack {
                        HStack(spacing: 6) {
                            Spacer()
                            Text("AI 후보")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(appearance == "light" ? Color.black.opacity(0.12) : Color.white.opacity(0.20))
                                .clipShape(Capsule())
                            if let onApplyAICandidate {
                                Button("선택") {
                                    onApplyAICandidate()
                                }
                                .font(.system(size: 9, weight: .semibold))
                                .buttonStyle(.plain)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(appearance == "light" ? Color.accentColor.opacity(0.22) : Color.accentColor.opacity(0.32))
                                .clipShape(Capsule())
                                .disabled(isAIBusy)
                            }
                        }
                        Spacer()
                    }
                    .padding(8)
                }
                HStack(spacing: 3) {
                    if hasLinkedCards {
                        Rectangle()
                            .fill(appearance == "light" ? Color.black.opacity(0.48) : Color.white.opacity(0.85))
                            .frame(width: 8, height: 8)
                            .allowsHitTesting(false)
                    }
                    if isLinkedCard {
                        Path { path in
                            // Right-angle isosceles triangle with the right angle at top-right.
                            path.move(to: CGPoint(x: 0, y: 0))
                            path.addLine(to: CGPoint(x: 8, y: 0))
                            path.addLine(to: CGPoint(x: 8, y: 8))
                            path.closeSubpath()
                        }
                        .fill(appearance == "light" ? Color.black.opacity(0.48) : Color.white.opacity(0.85))
                        .frame(width: 8, height: 8)
                        .allowsHitTesting(false)
                    }
                }
                if isSummarizingChildren {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                        .background(appearance == "light" ? Color.white.opacity(0.92) : Color.black.opacity(0.42))
                        .clipShape(Capsule())
                        .padding(.top, 6)
                        .padding(.trailing, 8)
                        .allowsHitTesting(false)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if isCloneLinked {
                Rectangle()
                    .fill(appearance == "light" ? Color.black.opacity(0.48) : Color.white.opacity(0.85))
                    .frame(width: 8, height: 8)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: isInteractionAffordanceFrozen) { _, frozen in
            guard frozen else { return }
            isTopInsertZoneHovered = false
            isBottomInsertZoneHovered = false
            isTrailingInsertZoneHovered = false
        }
    }

    @ViewBuilder
    private var cardSurface: some View {
        cardChromeApplied(
            to: ZStack(alignment: .topLeading) {
                cardInteractionBackdrop
                CardItemContentLayer(
                    card: card,
                    backgroundColor: .clear,
                    backgroundFingerprint: contentBackgroundFingerprint,
                    fontSize: fontSize,
                    lineSpacing: mainCardLineSpacing,
                    preferredTextMeasureWidth: preferredTextMeasureWidth,
                    appearance: appearance,
                    isEditing: isEditing,
                    mainEditorSlotCoordinateSpaceName: mainEditorSlotCoordinateSpaceName,
                    mainEditorManagedExternally: mainEditorManagedExternally,
                    usesExternalMainEditor: usesExternalMainEditor,
                    disablesInlineMainEditorFallback: disablesInlineMainEditorFallback,
                    externalEditorLiveBodyHeight: externalEditorLiveBodyHeight,
                    onContentChange: onContentChange,
                    onMainEditorMount: onMainEditorMount,
                    onMainEditorUnmount: onMainEditorUnmount,
                    onMainEditorFocusStateChange: onMainEditorFocusStateChange
                )
                .equatable()
            }
        )
    }

    var body: some View {
        Group {
            if isEditing {
                cardSurface
            } else {
                cardSurface
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                lastSpatialTapUptime = ProcessInfo.processInfo.systemUptime
                                handleCardTap(at: value.location)
                            }
                    )
                    .onTapGesture {
                        guard shouldHandlePlainTapFallback else { return }
                        handleCardTap()
                    }
                    .simultaneousGesture(TapGesture(count: 2).onEnded { onDoubleClick() })
            }
        }
        .contextMenu {
            cardContextMenuContent
        }
    }

    private var shouldHandlePlainTapFallback: Bool {
        ProcessInfo.processInfo.systemUptime - lastSpatialTapUptime > plainTapFallbackSuppressionWindow
    }

    private func handleCardTap(at clickLocation: CGPoint? = nil) {
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isPlainClick =
            !flags.contains(.command) &&
            !flags.contains(.shift) &&
            !flags.contains(.option) &&
            !flags.contains(.control)
        let shouldRouteClickToCaret =
            isPlainClick &&
            isActive &&
            isSelected &&
            !isMultiSelected &&
            clickLocation != nil &&
            onSelectAtLocation != nil
        if shouldRouteClickToCaret, let clickLocation, let onSelectAtLocation {
            onSelectAtLocation(clickLocation)
        } else {
            onSelect()
        }
    }

    private func resolvedBaseRGB() -> (r: Double, g: Double, b: Double) {
        let fallbackLight: (Double, Double, Double) = (1.0, 1.0, 1.0)
        let fallbackDark: (Double, Double, Double) = (0.10, 0.13, 0.16)
        if let custom = card.colorHex, let customRGB = rgbFromHex(custom) {
            if forceCustomColorVisibility || card.isAICandidate {
                if !usesDarkPalette { return customRGB }
                return mix(base: customRGB, overlay: (0, 0, 0), amount: 0.18)
            }
            if !usesDarkPalette { return customRGB }
            return mix(base: customRGB, overlay: (0, 0, 0), amount: 0.65)
        }
        let hex = usesDarkPalette ? darkCardBaseColorHex : cardBaseColorHex
        guard let rgb = rgbFromHex(hex) else {
            return usesDarkPalette ? fallbackDark : fallbackLight
        }
        return rgb
    }

    private func rgbFromHex(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        guard let rgb = parseHexRGB(hex) else { return nil }
        return (r: rgb.0, g: rgb.1, b: rgb.2)
    }

    private func mix(base: (r: Double, g: Double, b: Double), overlay: (r: Double, g: Double, b: Double), amount: Double) -> (r: Double, g: Double, b: Double) {
        let r = base.r * (1.0 - amount) + overlay.r * amount
        let g = base.g * (1.0 - amount) + overlay.g * amount
        let b = base.b * (1.0 - amount) + overlay.b * amount
        return (r, g, b)
    }

    private func resolvedNamedSnapshotNoteRGB() -> (r: Double, g: Double, b: Double) {
        if appearance == "light" {
            return (0.83, 0.94, 0.84)
        }
        return (0.17, 0.30, 0.19)
    }

    @ViewBuilder
    private func inlineInsertZone(
        isHovered: Binding<Bool>,
        isDropTargeted: Binding<Bool>,
        edge: InlineInsertZoneEdge,
        axis: Axis,
        action: @escaping () -> Void,
        onDrop: (([NSItemProvider], Bool) -> Void)?
    ) -> some View {
        if let onDrop {
            inlineInsertZoneContent(
                isHovered: isHovered,
                isDropTargeted: isDropTargeted,
                edge: edge,
                axis: axis,
                action: action
            )
            .onDrop(
                of: [.text],
                delegate: CardActionZoneDropDelegate(
                    isTargeted: isDropTargeted,
                    performAction: onDrop
                )
            )
        } else {
            inlineInsertZoneContent(
                isHovered: isHovered,
                isDropTargeted: isDropTargeted,
                edge: edge,
                axis: axis,
                action: action
            )
        }
    }

    private func inlineInsertZoneContent(
        isHovered: Binding<Bool>,
        isDropTargeted: Binding<Bool>,
        edge: InlineInsertZoneEdge,
        axis: Axis,
        action: @escaping () -> Void
    ) -> some View {
        let isHighlighted = isHovered.wrappedValue || isDropTargeted.wrappedValue
        return ZStack {
            Rectangle()
                .fill(isHighlighted ? insertZoneHighlightFill(for: edge) : AnyShapeStyle(Color.clear))

            if isHighlighted {
                Text("+")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(insertIndicatorColor)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            guard !isInteractionAffordanceFrozen else {
                if isHovered.wrappedValue {
                    isHovered.wrappedValue = false
                }
                return
            }
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered.wrappedValue = hovering
            }
        }
        .onTapGesture {
            action()
        }
        .frame(
            width: axis == .vertical ? trailingInsertZoneWidth : horizontalInsertZoneWidth,
            height: axis == .horizontal ? horizontalInsertZoneHeight : nil
        )
        .frame(
            maxHeight: axis == .vertical ? .infinity : nil
        )
    }

    @ViewBuilder
    private func cardBodyDropZone(onDrop: @escaping ([NSItemProvider], Bool) -> Void) -> some View {
        GeometryReader { geometry in
            let bodyWidth = max(0, geometry.size.width - bodyDropTrailingInset)
            let bodyHeight = max(0, geometry.size.height - (horizontalInsertZoneHeight * 2))

            Rectangle()
                .fill(isBodyDropTargeted ? insertZoneHighlightColor : .clear)
                .frame(width: bodyWidth, height: bodyHeight, alignment: .topLeading)
                .offset(x: 0, y: horizontalInsertZoneHeight)
                .contentShape(Rectangle())
                .onDrop(
                    of: [.text],
                    delegate: CardActionZoneDropDelegate(
                        isTargeted: $isBodyDropTargeted,
                        performAction: onDrop
                    )
                )
        }
    }

    private func resolvedActiveRGB() -> (r: Double, g: Double, b: Double) {
        let fallbackLight: (Double, Double, Double) = (0.75, 0.84, 1.0)
        let fallbackDark: (Double, Double, Double) = (0.16, 0.23, 0.31)
        let hex = usesDarkPalette ? darkCardActiveColorHex : cardActiveColorHex
        guard let rgb = rgbFromHex(hex) else {
            return usesDarkPalette ? fallbackDark : fallbackLight
        }
        return rgb
    }

    private func resolvedRelatedRGB() -> (r: Double, g: Double, b: Double) {
        let fallbackLight: (Double, Double, Double) = (0.87, 0.92, 1.0)
        let fallbackDark: (Double, Double, Double) = (0.14, 0.18, 0.25)
        let hex = usesDarkPalette ? darkCardRelatedColorHex : cardRelatedColorHex
        guard let rgb = rgbFromHex(hex) else {
            return usesDarkPalette ? fallbackDark : fallbackLight
        }
        return rgb
    }

    private func resolvedDescendantRGB() -> (r: Double, g: Double, b: Double) {
        mix(base: resolvedActiveRGB(), overlay: (0, 0, 0), amount: 0.10)
    }
}
