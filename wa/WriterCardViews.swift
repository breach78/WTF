import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 카드 사이 및 열 상/하단 빈 공간 드롭 영역

struct DropSpacer: View {
    let target: DropTarget
    @Binding var activeDropTarget: DropTarget?
    var alignment: Alignment = .center
    let onDrop: ([NSItemProvider]) -> Void
    @AppStorage("mainCardVerticalGap") private var mainCardVerticalGap: Double = 0.0

    @State private var isHovering: Bool = false

    private var centerGapHeight: CGFloat { max(0, CGFloat(mainCardVerticalGap)) }
    private var centerHitAreaHeight: CGFloat { max(12, centerGapHeight) }

    private func updateHoverState(_ newValue: Bool) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if newValue {
                activeDropTarget = target
            } else if activeDropTarget == target {
                activeDropTarget = nil
            }
        }
    }

    var body: some View {
        Group {
            if alignment == .center {
                Color.clear
                    .frame(height: centerGapHeight)
                    .overlay(alignment: .center) {
                        ZStack {
                            Color.black.opacity(0.001)
                            if activeDropTarget == target {
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
                            onDrop(providers)
                            return true
                        }
                    }
            } else {
                ZStack(alignment: alignment) {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())

                    if activeDropTarget == target {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 4)
                            .cornerRadius(2)
                            .transition(.opacity)
                    }
                }
                .onDrop(of: [.text], isTargeted: $isHovering) { providers in
                    onDrop(providers)
                    return true
                }
            }
        }
        .onChange(of: isHovering) { _, newValue in
            updateHoverState(newValue)
        }
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

private enum FocusModeTextHeightCalculator {
    private static var lineFragmentPadding: CGFloat {
        FocusModeLayoutMetrics.focusModeLineFragmentPadding
    }

    static func measureBodyHeight(
        text: String,
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        width: CGFloat
    ) -> CGFloat {
        let measuringText: String
        if text.isEmpty {
            measuringText = " "
        } else if text.hasSuffix("\n") {
            measuringText = text + " "
        } else {
            measuringText = text
        }
        let constrainedWidth = max(1, width)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping

        let font = NSFont(name: "SansMonoCJKFinalDraft", size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        let storage = NSTextStorage(
            string: measuringText,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
        )
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: CGSize(width: constrainedWidth, height: CGFloat.greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = lineFragmentPadding
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.maximumNumberOfLines = 0
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let usedHeight = layoutManager.usedRect(for: textContainer).height
        return max(1, ceil(usedHeight + focusModeBodySafetyInset))
    }
}

struct FocusModeCardEditor: View {
    @ObservedObject var card: SceneCard
    let isActive: Bool
    let fontSize: Double
    let appearance: String
    let horizontalInset: CGFloat
    let observedBodyHeight: CGFloat?
    @FocusState.Binding var focusModeEditorCardID: UUID?
    let onActivate: () -> Void
    let onContentChange: (String, String) -> Void

    @AppStorage("focusModeLineSpacingValueTemp") private var focusModeLineSpacingValue: Double = 4.5
    @State private var measuredBodyHeight: CGFloat = 0
    @State private var measuredCardWidth: CGFloat = 0
    private let verticalInset: CGFloat = 40
    private var targetMeasuredHeight: CGFloat {
        guard measuredBodyHeight > 1 else { return 0 }
        return measuredBodyHeight + (verticalInset * 2)
    }
    private var textEditorBodyHeight: CGFloat {
        max(1, measuredBodyHeight)
    }
    private var focusModeFontSize: CGFloat { CGFloat(fontSize * 1.2) }
    private var focusModeLineSpacing: CGFloat { CGFloat(focusModeLineSpacingValue) }
    private var textEditorMeasureWidth: CGFloat {
        max(1, measuredCardWidth - (horizontalInset * 2))
    }
    private var sizingText: String {
        let text = card.content
        if text.isEmpty { return " " }
        return text
    }

    private var focusModeTextBinding: Binding<String> {
        Binding(
            get: { card.content },
            set: { newValue in
                let oldValue = card.content
                guard oldValue != newValue else { return }
                card.content = newValue
                onContentChange(oldValue, newValue)
                refreshMeasuredHeights()
            }
        )
    }

    private func refreshMeasuredHeights() {
        guard measuredCardWidth > 1 else {
            return
        }
        let deterministicBodyHeight = FocusModeTextHeightCalculator.measureBodyHeight(
            text: sizingText,
            fontSize: focusModeFontSize,
            lineSpacing: focusModeLineSpacing,
            width: textEditorMeasureWidth
        )
        let resolvedBodyHeight: CGFloat
        let observedRangeMin: CGFloat
        let observedRangeMax: CGFloat
        
        if let observedBodyHeight, observedBodyHeight > 1 {
            observedRangeMin = max(1, (deterministicBodyHeight * 0.65) - 80)
            observedRangeMax = (deterministicBodyHeight * 1.6) + 120
            let observedAccepted = observedBodyHeight >= observedRangeMin && observedBodyHeight <= observedRangeMax
            if observedAccepted {
                resolvedBodyHeight = observedBodyHeight
            } else {
                resolvedBodyHeight = deterministicBodyHeight
            }
        } else {
            let noObservedScale: CGFloat = deterministicBodyHeight > 180 ? 0.95 : 1.0
            resolvedBodyHeight = max(1, deterministicBodyHeight * noObservedScale)
        }
        
        if abs(measuredBodyHeight - resolvedBodyHeight) > 0.25 {
            measuredBodyHeight = resolvedBodyHeight
        }
        }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: focusModeTextBinding)
                .font(.custom("SansMonoCJKFinalDraft", size: Double(focusModeFontSize)))
                .lineSpacing(focusModeLineSpacing)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .scrollIndicators(.never)
                .frame(height: targetMeasuredHeight > 1 ? textEditorBodyHeight : nil)
                .padding(.horizontal, horizontalInset)
                .padding(.top, verticalInset)
                .padding(.bottom, verticalInset)
                .foregroundStyle(appearance == "light" ? .black : .white)
                .focused($focusModeEditorCardID, equals: card.id)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        onActivate()
                    }
                )
        }
        .frame(height: targetMeasuredHeight > 1 ? targetMeasuredHeight : nil, alignment: .topLeading)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: FocusModeCardWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(FocusModeCardWidthPreferenceKey.self) { value in
            let normalizedWidth = max(0, round(value * 2) / 2)
            guard abs(measuredCardWidth - normalizedWidth) > 0.25 else { return }
            DispatchQueue.main.async {
                guard abs(measuredCardWidth - normalizedWidth) > 0.25 else { return }
                measuredCardWidth = normalizedWidth
                refreshMeasuredHeights()
            }
        }
        .onAppear {
            refreshMeasuredHeights()
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                refreshMeasuredHeights()
            }
        }
        .onChange(of: fontSize) { _, _ in
            refreshMeasuredHeights()
        }
        .onChange(of: focusModeLineSpacingValue) { _, _ in
            refreshMeasuredHeights()
        }
        .onChange(of: observedBodyHeight) { _, _ in
            refreshMeasuredHeights()
        }
        .contentShape(Rectangle())
        .onTapGesture { onActivate() }
    }

}

// MARK: - 메인 카드 아이템

struct CardItem: View {
    @ObservedObject var card: SceneCard
    let isActive, isSelected, isMultiSelected, isArchived, isAncestor, isDescendant, isEditing: Bool
    let dropTarget: DropTarget?
    let forceNamedSnapshotNoteStyle: Bool
    let forceCustomColorVisibility: Bool
    let measuredWidth: CGFloat?
    var onSelect, onDoubleClick, onEndEdit: () -> Void
    var onContentChange: ((String, String) -> Void)? = nil
    var onColorChange: ((String?) -> Void)? = nil
    var onReferenceCard: (() -> Void)? = nil
    var onCreateUpperCardFromSelection: (() -> Void)? = nil
    var onSummarizeChildren: (() -> Void)? = nil
    var isSummarizingChildren: Bool = false
    var onDelete: (() -> Void)? = nil
    var onHardDelete: (() -> Void)? = nil
    var showsEmptyCardBulkDeleteMenuOnly: Bool = false
    var onBulkDeleteEmptyCards: (() -> Void)? = nil
    @State private var mainEditingMeasuredBodyHeight: CGFloat = 0
    @State private var mainEditingMeasureWorkItem: DispatchWorkItem? = nil
    @State private var mainEditingMeasureLastAt: Date = .distantPast
    @FocusState private var editorFocus: Bool
    @AppStorage("fontSize") private var fontSize: Double = 14.0
    @AppStorage("appearance") private var appearance: String = "dark"
    @AppStorage("cardBaseColorHex") private var cardBaseColorHex: String = "FFFFFF"
    @AppStorage("cardActiveColorHex") private var cardActiveColorHex: String = "BFD7FF"
    @AppStorage("cardRelatedColorHex") private var cardRelatedColorHex: String = "DDE9FF"
    @AppStorage("darkCardBaseColorHex") private var darkCardBaseColorHex: String = "1A2029"
    @AppStorage("darkCardActiveColorHex") private var darkCardActiveColorHex: String = "2A3A4E"
    @AppStorage("darkCardRelatedColorHex") private var darkCardRelatedColorHex: String = "242F3F"
    @AppStorage("mainCardLineSpacingValueV2") private var mainCardLineSpacingValue: Double = 5.0
    private var mainCardLineSpacing: CGFloat { CGFloat(mainCardLineSpacingValue) }
    private let mainCardContentPadding: CGFloat = MainEditorLayoutMetrics.mainCardContentPadding
    private let mainEditorVerticalPadding: CGFloat = 24
    private let mainEditorLineFragmentPadding: CGFloat = MainEditorLayoutMetrics.mainEditorLineFragmentPadding
    private let mainEditingMeasureMinInterval: TimeInterval = 0.033
    private let mainEditingMeasureUpdateThreshold: CGFloat = 0.5
    private var mainEditorHorizontalPadding: CGFloat {
        MainEditorLayoutMetrics.mainEditorHorizontalPadding
    }

    private var usesDarkPalette: Bool {
        if appearance == "dark" { return true }
        if appearance == "light" { return false }
        if let best = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
            return best == .darkAqua
        }
        return true
    }

    private var isOntoTarget: Bool { if case .onto(let id) = dropTarget { return id == card.id } else { return false } }
    private var isCandidateVisualCard: Bool {
        (forceCustomColorVisibility || card.isAICandidate) && card.colorHex != nil
    }
    private var shouldShowChildRightEdge: Bool {
        !isArchived && !card.children.isEmpty
    }

    private var resolvedCardRGB: (r: Double, g: Double, b: Double) {
        if forceNamedSnapshotNoteStyle {
            return resolvedNamedSnapshotNoteRGB()
        }
        let base = resolvedBaseRGB()
        if isMultiSelected {
            let overlay = usesDarkPalette ? (r: 0.42, g: 0.56, b: 0.78) : (r: 0.70, g: 0.83, b: 0.98)
            let amount = usesDarkPalette ? 0.58 : 0.62
            return mix(base: base, overlay: overlay, amount: amount)
        }
        if isCandidateVisualCard {
            return base
        }
        let active = resolvedActiveRGB()
        let related = resolvedRelatedRGB()
        if isOntoTarget || isActive {
            return active
        }
        if isAncestor || isDescendant {
            return related
        }
        return base
    }

    private var childRightEdgeColor: Color {
        let amount = usesDarkPalette ? 0.34 : 0.24
        let rgb = mix(base: resolvedCardRGB, overlay: (0, 0, 0), amount: amount)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private var backgroundColor: Color {
        if isArchived {
            return appearance == "light" ? Color.gray.opacity(0.25) : Color.gray.opacity(0.35)
        }
        let rgb = resolvedCardRGB
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private var mainEditingTextMeasureWidth: CGFloat {
        let cardWidth = measuredWidth ?? 392
        return max(1, cardWidth - (MainEditorLayoutMetrics.mainEditorHorizontalPadding * 2))
    }

    private var resolvedMainEditingBodyHeight: CGFloat {
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
        guard editorFocus else { return nil }
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return nil }
        guard textView.string == card.content else { return nil }
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return nil }
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        guard usedHeight > 0 else { return nil }
        return max(1, ceil(usedHeight))
    }

    private func measureMainEditorBodyHeight(text: String, width: CGFloat) -> CGFloat {
        let content: String
        if text.isEmpty {
            content = " "
        } else if text.hasSuffix("\n") {
            content = text + " "
        } else {
            content = text
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = mainCardLineSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping

        let font = NSFont(name: "SansMonoCJKFinalDraft", size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        let storage = NSTextStorage(
            string: content,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
        )
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: CGSize(width: max(1, width), height: CGFloat.greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = mainEditorLineFragmentPadding
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.maximumNumberOfLines = 0
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        return max(1, ceil(usedHeight))
    }

    private func refreshMainEditingMeasuredBodyHeight() {
        let measured = liveMainResponderBodyHeight()
            ?? measureMainEditorBodyHeight(text: card.content, width: mainEditingTextMeasureWidth)
        mainEditingMeasureLastAt = Date()
        let previous = mainEditingMeasuredBodyHeight
        if abs(previous - measured) > mainEditingMeasureUpdateThreshold {
            mainEditingMeasuredBodyHeight = measured
        }
    }

    private func scheduleMainEditingMeasuredBodyHeightRefresh(immediate: Bool = false) {
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

    var body: some View {
        ZStack(alignment: .topLeading) {
            backgroundColor

            ZStack(alignment: .topLeading) {
                if !isEditing {
                    Text(card.content.isEmpty ? "내용 없음" : card.content)
                        .font(.custom("SansMonoCJKFinalDraft", size: fontSize))
                        .lineSpacing(mainCardLineSpacing)
                        .foregroundStyle(card.content.isEmpty ? (appearance == "light" ? .black.opacity(0.4) : .white.opacity(0.4)) : (appearance == "light" ? .black : .white))
                        .padding(mainCardContentPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isEditing {
                    TextEditor(text: mainEditorTextBinding)
                        .font(.custom("SansMonoCJKFinalDraft", size: fontSize))
                        .lineSpacing(mainCardLineSpacing)
                        .scrollContentBackground(.hidden)
                        .scrollDisabled(true)
                        .scrollIndicators(.never)
                        .frame(height: resolvedMainEditingBodyHeight, alignment: .topLeading)
                        .padding(.horizontal, mainEditorHorizontalPadding)
                        .padding(.vertical, mainEditorVerticalPadding)
                        .foregroundStyle(appearance == "light" ? .black : .white)
                        .focused($editorFocus)
                        .onAppear {
                            scheduleMainEditingMeasuredBodyHeightRefresh(immediate: true)
                            DispatchQueue.main.async {
                                let alreadyFocusedHere: Bool = {
                                    guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
                                    return textView.string == card.content
                                }()
                                if !alreadyFocusedHere {
                                    editorFocus = true
                                }
                                scheduleMainEditingMeasuredBodyHeightRefresh(immediate: true)
                            }
                        }
                        .onDisappear {
                            mainEditingMeasureWorkItem?.cancel()
                            mainEditingMeasureWorkItem = nil
                        }
                        .onChange(of: measuredWidth) { _, _ in
                            scheduleMainEditingMeasuredBodyHeightRefresh(immediate: true)
                        }
                        .onChange(of: fontSize) { _, _ in
                            scheduleMainEditingMeasuredBodyHeightRefresh(immediate: true)
                        }
                        .onChange(of: mainCardLineSpacing) { _, _ in
                            scheduleMainEditingMeasuredBodyHeightRefresh(immediate: true)
                        }
                }

                if isCandidateVisualCard {
                    VStack {
                        HStack {
                            Spacer()
                            Text("AI 후보")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(appearance == "light" ? Color.black.opacity(0.12) : Color.white.opacity(0.20))
                                .clipShape(Capsule())
                        }
                        Spacer()
                    }
                    .padding(8)
                }
            }
        }
        .overlay(alignment: .trailing) {
            if shouldShowChildRightEdge {
                Rectangle()
                    .fill(childRightEdgeColor)
                    .frame(width: 4)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
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
        .onTapGesture { onSelect() }
        .simultaneousGesture(TapGesture(count: 2).onEnded { onDoubleClick() })
        .onChange(of: isEditing) { _, newValue in
            if newValue {
                scheduleMainEditingMeasuredBodyHeightRefresh(immediate: true)
            } else {
                mainEditingMeasureWorkItem?.cancel()
                mainEditingMeasureWorkItem = nil
            }
        }
        .contextMenu {
            if showsEmptyCardBulkDeleteMenuOnly {
                if let onBulkDeleteEmptyCards {
                    Button("내용 없음 카드 전체 삭제", role: .destructive) { onBulkDeleteEmptyCards() }
                }
            } else {
                if let onReferenceCard {
                    Button("레퍼런스 카드로") { onReferenceCard() }
                    Divider()
                }
                if let onCreateUpperCardFromSelection {
                    Button("새 상위 카드 만들기") { onCreateUpperCardFromSelection() }
                    Divider()
                }
                if let onSummarizeChildren {
                    Button("하위 카드 요약") { onSummarizeChildren() }
                    Divider()
                }
                if let onDelete {
                    Button("삭제", role: .destructive) { onDelete() }
                }
                if onDelete != nil {
                    Divider()
                }
                Button("기본") { onColorChange?(nil) }
                Divider()
                Button("연보라") { onColorChange?("E7D5FF") }
                Button("하늘") { onColorChange?("CFE8FF") }
                Button("민트") { onColorChange?("CFF2E8") }
                Button("살구") { onColorChange?("FFE1CC") }
                Button("연노랑") { onColorChange?("FFF3C4") }
                if let onHardDelete {
                    Divider()
                    Button("완전 삭제 (모든 곳)", role: .destructive) { onHardDelete() }
                }
            }
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
}

// MARK: - 드래그 앤 드롭 델리게이트 (카드 본체용)

struct AdvancedCardDropDelegate: DropDelegate {
    let targetCard: SceneCard
    @Binding var activeDropTarget: DropTarget?
    let performAction: ([NSItemProvider], DropTarget) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.15)) { activeDropTarget = .onto(targetCard.id) }
    }

    func dropExited(info: DropInfo) {
        if activeDropTarget == .onto(targetCard.id) {
            withAnimation(.easeInOut(duration: 0.15)) { activeDropTarget = nil }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.text])
        performAction(providers, .onto(targetCard.id))
        activeDropTarget = nil
        return true
    }
}
