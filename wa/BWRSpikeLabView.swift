import SwiftUI
import AppKit
import Combine

@MainActor
struct BWRSpikeLabView: View {
    @StateObject private var boardStore = BWRBoardSpikeStore()
    @State private var autosaveMetrics: BWRPackageStore.SaveMetrics?
    @State private var autosaveStatus: String = "아직 실행하지 않음"
    @State private var autosaveRunning = false
    @State private var harnessStatus: String = "아직 실행하지 않음"
    @State private var harnessReport: String = ""
    @State private var harnessRunning = false

    var body: some View {
        TabView {
            BWRBoardSpikeTab(store: boardStore)
                .tabItem { Text("Board") }

            BWRTextSplitSpikeTab()
                .tabItem { Text("Text") }

            BWRPhase0AutosaveTab(
                metrics: autosaveMetrics,
                status: autosaveStatus,
                isRunning: autosaveRunning,
                runProbe: runAutosaveProbe
            )
            .tabItem { Text("Autosave") }

            BWRPhase0HarnessTab(
                status: harnessStatus,
                report: harnessReport,
                isRunning: harnessRunning,
                runHarness: runHarness
            )
            .tabItem { Text("Harness") }

            BWRCardBuddyPhase0LabView()
                .tabItem { Text("Card Buddy") }

            BWRCardBuddySurfaceAuditLabView()
                .tabItem { Text("Surface Audit") }
        }
        .padding(16)
        .frame(minWidth: 1080, minHeight: 760)
        .background(Color(nsColor: NSColor.windowBackgroundColor))
        .onAppear {
            loadExistingHarnessReport()
        }
    }

    private func runAutosaveProbe() {
        guard !autosaveRunning else { return }
        autosaveRunning = true
        autosaveStatus = "300 cards × 3 layers delta save를 측정하는 중…"

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let metrics = try BWRPackageStore.measureAutosave(cardCount: 300)
                DispatchQueue.main.async {
                    autosaveMetrics = metrics
                    autosaveStatus = String(
                        format: "완료: full %.2fms / delta %.2fms",
                        metrics.fullSaveMilliseconds,
                        metrics.deltaSaveMilliseconds
                    )
                    autosaveRunning = false
                }
            } catch {
                DispatchQueue.main.async {
                    autosaveMetrics = nil
                    autosaveStatus = "실패: \(error.localizedDescription)"
                    autosaveRunning = false
                }
            }
        }
    }

    private func runHarness() {
        guard !harnessRunning else { return }
        harnessRunning = true
        harnessStatus = "phase-0 harness를 실행하는 중…"

        DispatchQueue.global(qos: .userInitiated).async {
            let success = BWRPhase0Harness.runAll()
            let report = (try? String(contentsOf: BWRPhase0Harness.reportMarkdownURL, encoding: .utf8)) ?? ""
            DispatchQueue.main.async {
                harnessReport = report
                harnessStatus = success
                    ? "완료: failures 0"
                    : "실패 존재: \(BWRPhase0Harness.reportMarkdownURL.path) 확인"
                harnessRunning = false
            }
        }
    }

    private func loadExistingHarnessReport() {
        harnessReport = (try? String(contentsOf: BWRPhase0Harness.reportMarkdownURL, encoding: .utf8)) ?? ""
    }
}

@MainActor
private final class BWRBoardSpikeStore: ObservableObject {
    @Published var cards: [BWRCard]
    @Published var zoomScale: CGFloat = 1.0

    let boardSize = CGSize(width: 2700, height: 2200)
    private let baseCards: [BWRCard]
    private var dragOrigins: [UUID: BWRPoint] = [:]

    init() {
        let seededCards = BWRPhase0SeedFactory.makeBoardSpikeCards(count: 200)
        self.cards = seededCards
        self.baseCards = seededCards
    }

    func reset() {
        cards = baseCards
        zoomScale = 1.0
        dragOrigins.removeAll()
    }

    func updateZoom(with magnification: CGFloat, baseline: CGFloat) {
        zoomScale = min(max(baseline * magnification, 0.3), 1.6)
    }

    func beginDrag(for cardID: UUID) {
        guard dragOrigins[cardID] == nil,
              let card = cards.first(where: { $0.id == cardID }) else { return }
        dragOrigins[cardID] = card.layout
    }

    func updateDrag(for cardID: UUID, translation: CGSize) {
        guard let start = dragOrigins[cardID],
              let index = cards.firstIndex(where: { $0.id == cardID }) else { return }

        let deltaX = Double(translation.width / max(zoomScale, 0.0001))
        let deltaY = Double(translation.height / max(zoomScale, 0.0001))
        cards[index].layout = BWRPoint(
            x: min(max(0, start.x + deltaX), boardSize.width - 188),
            y: min(max(0, start.y + deltaY), boardSize.height - 124)
        )
        cards[index].updatedAt = Date()
    }

    func endDrag(for cardID: UUID) {
        dragOrigins.removeValue(forKey: cardID)
    }

    func cycleLayer(for cardID: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == cardID }) else { return }
        guard let currentIndex = cards[index].layers.firstIndex(where: { $0.id == cards[index].currentLayerID }) else { return }
        let nextIndex = (currentIndex + 1) % cards[index].layers.count
        cards[index].currentLayerID = cards[index].layers[nextIndex].id
        cards[index].updatedAt = Date()
    }
}

private struct BWRBoardSpikeTab: View {
    @ObservedObject var store: BWRBoardSpikeStore
    @State private var magnificationBaseline: CGFloat = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("200장 보드 스파이크")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Text(String(format: "Zoom %.2fx", store.zoomScale))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { store.zoomScale },
                        set: { store.zoomScale = min(max($0, 0.3), 1.6) }
                    ),
                    in: 0.3...1.6
                )
                .frame(width: 180)
                Button("Reset") {
                    store.reset()
                }
            }

            Text("트랙패드 스크롤로 팬, 핀치나 슬라이더로 줌, 카드 드래그로 자유 배치를 확인합니다. 카드 더블클릭으로 현재 레이어를 순환합니다.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    BWRBoardGridView(boardSize: store.boardSize)
                    ForEach(store.cards) { card in
                        BWRBoardSpikeCard(card: card)
                            .frame(width: 188, height: 124)
                            .position(x: card.layout.x + 94, y: card.layout.y + 62)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        store.beginDrag(for: card.id)
                                        store.updateDrag(for: card.id, translation: value.translation)
                                    }
                                    .onEnded { value in
                                        store.updateDrag(for: card.id, translation: value.translation)
                                        store.endDrag(for: card.id)
                                    }
                            )
                            .onTapGesture(count: 2) {
                                store.cycleLayer(for: card.id)
                            }
                    }
                }
                .frame(width: store.boardSize.width, height: store.boardSize.height, alignment: .topLeading)
                .scaleEffect(store.zoomScale, anchor: .topLeading)
                .frame(
                    width: store.boardSize.width * store.zoomScale,
                    height: store.boardSize.height * store.zoomScale,
                    alignment: .topLeading
                )
                .background(Color(nsColor: NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        store.updateZoom(with: value, baseline: magnificationBaseline)
                    }
                    .onEnded { value in
                        store.updateZoom(with: value, baseline: magnificationBaseline)
                        magnificationBaseline = store.zoomScale
                    }
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .onChange(of: store.zoomScale) { _, newValue in
            magnificationBaseline = newValue
        }
    }
}

private struct BWRBoardGridView: View {
    let boardSize: CGSize

    var body: some View {
        Canvas { context, size in
            let minorSpacing: CGFloat = 80
            let majorSpacing: CGFloat = 320
            for x in stride(from: 0, through: size.width, by: minorSpacing) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                let isMajor = Int(x).isMultiple(of: Int(majorSpacing))
                context.stroke(
                    path,
                    with: .color(Color.black.opacity(isMajor ? 0.08 : 0.035)),
                    lineWidth: isMajor ? 1.0 : 0.5
                )
            }
            for y in stride(from: 0, through: size.height, by: minorSpacing) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                let isMajor = Int(y).isMultiple(of: Int(majorSpacing))
                context.stroke(
                    path,
                    with: .color(Color.black.opacity(isMajor ? 0.08 : 0.035)),
                    lineWidth: isMajor ? 1.0 : 0.5
                )
            }
        }
        .frame(width: boardSize.width, height: boardSize.height)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct BWRBoardSpikeCard: View {
    let card: BWRCard

    var body: some View {
        let layer = card.currentLayer ?? card.layers.first
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(layer?.name ?? "Unknown")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(card.id.uuidString.prefix(4))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text(snippet(for: layer?.markdown ?? ""))
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(5)

            Spacer()

            HStack {
                Text(layerKindBadge(for: layer?.kind))
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.06), in: Capsule())
                Spacer()
                Text("dbl click")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)
    }

    private var cardBackgroundColor: Color {
        guard let colorHex = card.colorHex else {
            return Color(nsColor: NSColor.controlBackgroundColor)
        }
        return Color(hex: colorHex) ?? Color(nsColor: NSColor.controlBackgroundColor)
    }

    private func snippet(for markdown: String) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Empty layer" }
        return trimmed
    }

    private func layerKindBadge(for kind: BWRLayerKind?) -> String {
        switch kind {
        case .body: return "BODY"
        case .treatment: return "TREAT"
        case .scenario: return "SCENE"
        case nil: return "NONE"
        }
    }
}

private struct BWRTextSplitSpikeTab: View {
    @State private var segments: [String] = [
        "Card 1\n\nType here, then press Enter to split.\nShift+Enter inserts a newline.",
        "Card 2\n\nThis second card is here so selection changes are visible."
    ]
    @State private var selectedIndex: Int = 0
    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @State private var eventLog: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("텍스트 분기 스파이크")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Button("Reset") {
                    reset()
                }
            }

            Text("실제 NSTextView 위에서 Enter=split, Shift+Enter=newline, IME marked text=system pass-through를 확인합니다.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Cards")
                        .font(.system(size: 13, weight: .semibold))
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, text in
                        Button {
                            selectedIndex = index
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Card \(index + 1)")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(index == selectedIndex ? Color.black.opacity(0.08) : Color.black.opacity(0.03))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .frame(width: 240)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Editor")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("selection \(selectedRange.location):\(selectedRange.length)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    BWRTextEditorProbe(
                        text: bindingForSelectedText(),
                        selectedRange: $selectedRange,
                        onLog: appendEventLog,
                        onSplit: splitSelectedCard(text:selection:)
                    )
                    .frame(minHeight: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )

                    Text("Event Log")
                        .font(.system(size: 13, weight: .semibold))
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(eventLog.enumerated()), id: \.offset) { _, item in
                                Text(item)
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(minHeight: 160)
                    .padding(10)
                    .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func reset() {
        segments = [
            "Card 1\n\nType here, then press Enter to split.\nShift+Enter inserts a newline.",
            "Card 2\n\nThis second card is here so selection changes are visible."
        ]
        selectedIndex = 0
        selectedRange = NSRange(location: 0, length: 0)
        eventLog.removeAll()
    }

    private func bindingForSelectedText() -> Binding<String> {
        Binding(
            get: {
                guard segments.indices.contains(selectedIndex) else { return "" }
                return segments[selectedIndex]
            },
            set: { updated in
                guard segments.indices.contains(selectedIndex) else { return }
                segments[selectedIndex] = updated
            }
        )
    }

    private func appendEventLog(_ message: String) {
        let timestamp = DateFormatter.bwrPhase0Log.string(from: Date())
        eventLog.insert("[\(timestamp)] \(message)", at: 0)
        if eventLog.count > 24 {
            eventLog.removeLast(eventLog.count - 24)
        }
    }

    private func splitSelectedCard(text: String, selection: NSRange) {
        guard segments.indices.contains(selectedIndex) else { return }
        let clampedLocation = max(0, min(selection.location, (text as NSString).length))
        let nsText = text as NSString
        let left = nsText.substring(to: clampedLocation)
        let right = nsText.substring(from: clampedLocation)
        segments[selectedIndex] = left
        segments.insert(right, at: selectedIndex + 1)
        selectedIndex = min(selectedIndex + 1, segments.count - 1)
        selectedRange = NSRange(location: 0, length: 0)
        appendEventLog("split card at utf16 \(clampedLocation)")
    }
}

private struct BWRTextEditorProbe: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let onLog: (String) -> Void
    let onSplit: (String, NSRange) -> Void

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BWRTextEditorProbe
        var suppressPropagation = false

        init(parent: BWRTextEditorProbe) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !suppressPropagation else { return }
            parent.text = textView.string
            parent.selectedRange = textView.selectedRange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.selectedRange = textView.selectedRange()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) ||
                    commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) ||
                    commandSelector == #selector(NSResponder.insertLineBreak(_:)) else {
                return false
            }

            let event = BWRTextKeyEvent(
                keyCode: NSApp.currentEvent?.keyCode ?? 36,
                modifiers: BWRTextKeyModifiers(
                    shift: NSApp.currentEvent?.modifierFlags.contains(.shift) == true,
                    command: NSApp.currentEvent?.modifierFlags.contains(.command) == true,
                    option: NSApp.currentEvent?.modifierFlags.contains(.option) == true,
                    control: NSApp.currentEvent?.modifierFlags.contains(.control) == true
                ),
                hasMarkedText: textView.hasMarkedText()
            )

            let action = BWRTextKeyCommandRouter.resolve(event)
            parent.onLog("keyCode=\(event.keyCode) shift=\(event.modifiers.shift) marked=\(event.hasMarkedText) -> \(action.rawValue)")

            switch action {
            case .splitCard:
                parent.onSplit(textView.string, textView.selectedRange())
                return true
            case .insertNewline:
                textView.insertText("\n", replacementRange: textView.selectedRange())
                return true
            case .passToSystem:
                return false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

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
        textView.font = .systemFont(ofSize: 15)
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false
            textContainer.lineFragmentPadding = 0
            textContainer.lineBreakMode = .byWordWrapping
        }

        scrollView.documentView = textView
        updateTextView(textView, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.delegate !== context.coordinator {
            textView.delegate = context.coordinator
        }
        updateTextView(textView, coordinator: context.coordinator)
    }

    private func updateTextView(_ textView: NSTextView, coordinator: Coordinator) {
        coordinator.parent = self
        if textView.string != text {
            coordinator.suppressPropagation = true
            textView.string = text
            coordinator.suppressPropagation = false
        }

        let length = (textView.string as NSString).length
        let clamped = NSRange(
            location: max(0, min(selectedRange.location, length)),
            length: max(0, min(selectedRange.length, length - max(0, min(selectedRange.location, length))))
        )
        if textView.selectedRange() != clamped {
            textView.setSelectedRange(clamped)
        }
    }
}

private struct BWRPhase0AutosaveTab: View {
    let metrics: BWRPackageStore.SaveMetrics?
    let status: String
    let isRunning: Bool
    let runProbe: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Autosave 성능 스파이크")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Button(isRunning ? "Running…" : "Run Probe") {
                    runProbe()
                }
                .disabled(isRunning)
            }

            Text("300 cards × 3 layers를 `.bwr` 패키지에 저장하고, 단일 카드 변경의 delta save 비용을 측정합니다.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Text(status)
                    .font(.system(size: 13, weight: .medium))

                if let metrics {
                    Text(String(format: "Full Save: %.2fms", metrics.fullSaveMilliseconds))
                    Text(String(format: "Delta Save: %.2fms", metrics.deltaSaveMilliseconds))
                    Text("Goal: delta < 50ms on iPad Air M2")
                        .foregroundStyle(.secondary)
                } else {
                    Text("아직 수치가 없습니다.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Spacer()
        }
    }
}

private struct BWRPhase0HarnessTab: View {
    let status: String
    let report: String
    let isRunning: Bool
    let runHarness: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Phase-0 Harness")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Button(isRunning ? "Running…" : "Run Harness") {
                    runHarness()
                }
                .disabled(isRunning)
            }

            Text("round-trip, ordering, clone normalization, key routing, autosave, export scaffold, undo boundary 결과를 `/tmp`에 저장합니다.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(status)
                .font(.system(size: 13, weight: .medium))

            ScrollView {
                Text(report.isEmpty ? "리포트가 아직 없습니다." : report)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack {
                Text(BWRPhase0Harness.reportMarkdownURL.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(BWRPhase0Harness.exportScaffoldURL.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private extension DateFormatter {
    static let bwrPhase0Log: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
