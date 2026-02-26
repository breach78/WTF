import SwiftUI
import AppKit
import Combine

enum ReferenceWindowConstants {
    static let windowID = "reference-window"
    static let cardWidth: CGFloat = 404
    static let windowWidth: CGFloat = 428
}

@MainActor
final class ReferenceCardStore: ObservableObject {
    struct Entry: Identifiable, Equatable, Codable {
        let scenarioID: UUID
        let cardID: UUID

        var id: String {
            "\(scenarioID.uuidString)|\(cardID.uuidString)"
        }
    }

    private static let persistedEntriesKey = "reference.card.entries.v1"
    private let maxUndoCount = 1200
    private let typingIdleInterval: TimeInterval = 1.5

    @Published private(set) var entries: [Entry] = []

    private struct UndoSnapshot {
        let scenarioID: UUID
        let cardID: UUID
        let content: String
    }

    private var undoStack: [UndoSnapshot] = []
    private var redoStack: [UndoSnapshot] = []
    private var coalescingBase: UndoSnapshot? = nil
    private var coalescingEntryID: String? = nil
    private var typingLastEditAt: Date = .distantPast
    private var typingIdleFinalizeWorkItem: DispatchWorkItem? = nil
    private var pendingReturnBoundary: Bool = false
    private var lastCommittedContentByEntryID: [String: String] = [:]
    private var programmaticContentSuppressUntil: Date = .distantPast

    init() {
        loadPersistedEntries()
    }

    func addCard(cardID: UUID, scenarioID: UUID) {
        let newEntry = Entry(scenarioID: scenarioID, cardID: cardID)
        guard !entries.contains(newEntry) else { return }
        entries.append(newEntry)
        persistEntries()
    }

    func removeCard(cardID: UUID, scenarioID: UUID) {
        finalizeTypingCoalescing(reason: "remove-card")
        entries.removeAll { $0.cardID == cardID && $0.scenarioID == scenarioID }
        lastCommittedContentByEntryID.removeValue(forKey: entryID(scenarioID: scenarioID, cardID: cardID))
        persistEntries()
    }

    func pruneMissingEntries(fileStore: FileStore) {
        let valid = entries.filter { entry in
            guard let scenario = fileStore.scenarios.first(where: { $0.id == entry.scenarioID }) else { return false }
            return scenario.cardByID(entry.cardID) != nil
        }
        if valid != entries {
            entries = valid
            persistEntries()
        }
    }

    func handleContentChange(
        scenarioID: UUID,
        cardID: UUID,
        oldValue: String,
        newValue: String,
        fileStore: FileStore
    ) {
        guard oldValue != newValue else { return }

        let id = entryID(scenarioID: scenarioID, cardID: cardID)
        let delta = utf16ChangeDelta(oldValue: oldValue, newValue: newValue)

        if Date() < programmaticContentSuppressUntil {
            lastCommittedContentByEntryID[id] = newValue
            fileStore.saveAll()
            return
        }

        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           textView.hasMarkedText() {
            fileStore.saveAll()
            return
        }

        let now = Date()
        let shouldBreakByGap = now.timeIntervalSince(typingLastEditAt) > typingIdleInterval
        let shouldBreakByCard = coalescingEntryID != nil && coalescingEntryID != id
        if shouldBreakByGap || shouldBreakByCard {
            finalizeTypingCoalescing(reason: shouldBreakByCard ? "typing-card-switch" : "typing-gap")
        }

        if coalescingBase == nil {
            let committedOld = lastCommittedContentByEntryID[id] ?? oldValue
            coalescingBase = UndoSnapshot(scenarioID: scenarioID, cardID: cardID, content: committedOld)
            coalescingEntryID = id
        }

        typingLastEditAt = now
        lastCommittedContentByEntryID[id] = newValue
        scheduleTypingIdleFinalize()

        if pendingReturnBoundary {
            pendingReturnBoundary = false
            if delta.newChangedLength > 0 && delta.inserted.contains("\n") {
                finalizeTypingCoalescing(reason: "typing-boundary-return")
                fileStore.saveAll()
                return
            }
        }

        if isStrongTextBoundaryChange(newValue: newValue, delta: delta) {
            finalizeTypingCoalescing(reason: "typing-boundary")
        }

        fileStore.saveAll()
    }

    func performUndo(fileStore: FileStore) -> Bool {
        finalizeTypingCoalescing(reason: "undo-request")
        guard let previous = undoStack.popLast() else { return true }
        guard let scenario = fileStore.scenarios.first(where: { $0.id == previous.scenarioID }),
              let card = scenario.cardByID(previous.cardID) else {
            return true
        }

        let current = UndoSnapshot(scenarioID: previous.scenarioID, cardID: previous.cardID, content: card.content)
        redoStack.append(current)
        if redoStack.count > maxUndoCount {
            redoStack.removeFirst(redoStack.count - maxUndoCount)
        }

        programmaticContentSuppressUntil = Date().addingTimeInterval(0.4)
        card.content = previous.content
        lastCommittedContentByEntryID[entryID(scenarioID: previous.scenarioID, cardID: previous.cardID)] = previous.content
        fileStore.saveAll()
        return true
    }

    func performRedo(fileStore: FileStore) -> Bool {
        finalizeTypingCoalescing(reason: "redo-request")
        guard let next = redoStack.popLast() else { return true }
        guard let scenario = fileStore.scenarios.first(where: { $0.id == next.scenarioID }),
              let card = scenario.cardByID(next.cardID) else {
            return true
        }

        let current = UndoSnapshot(scenarioID: next.scenarioID, cardID: next.cardID, content: card.content)
        undoStack.append(current)
        if undoStack.count > maxUndoCount {
            undoStack.removeFirst(undoStack.count - maxUndoCount)
        }

        programmaticContentSuppressUntil = Date().addingTimeInterval(0.4)
        card.content = next.content
        lastCommittedContentByEntryID[entryID(scenarioID: next.scenarioID, cardID: next.cardID)] = next.content
        fileStore.saveAll()
        return true
    }

    private func pushUndoState(_ previous: UndoSnapshot) {
        undoStack.append(previous)
        if undoStack.count > maxUndoCount {
            undoStack.removeFirst(undoStack.count - maxUndoCount)
        }
        redoStack.removeAll()
    }

    private func scheduleTypingIdleFinalize() {
        typingIdleFinalizeWorkItem?.cancel()
        let work = DispatchWorkItem {
            self.finalizeTypingCoalescing(reason: "typing-idle")
        }
        typingIdleFinalizeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + typingIdleInterval, execute: work)
    }

    private func finalizeTypingCoalescing(reason: String) {
        typingIdleFinalizeWorkItem?.cancel()
        typingIdleFinalizeWorkItem = nil
        guard let base = coalescingBase else { return }
        _ = reason
        coalescingBase = nil
        coalescingEntryID = nil
        pushUndoState(base)
    }

    private func utf16ChangeDelta(oldValue: String, newValue: String) -> (prefix: Int, oldChangedLength: Int, newChangedLength: Int, inserted: String) {
        let oldUTF16 = Array(oldValue.utf16)
        let newUTF16 = Array(newValue.utf16)
        let oldCount = oldUTF16.count
        let newCount = newUTF16.count

        var prefix = 0
        let minCount = min(oldCount, newCount)
        while prefix < minCount && oldUTF16[prefix] == newUTF16[prefix] {
            prefix += 1
        }

        var oldSuffix = oldCount
        var newSuffix = newCount
        while oldSuffix > prefix && newSuffix > prefix && oldUTF16[oldSuffix - 1] == newUTF16[newSuffix - 1] {
            oldSuffix -= 1
            newSuffix -= 1
        }

        let oldChangedLength = oldSuffix - prefix
        let newChangedLength = newSuffix - prefix
        let inserted = String(decoding: newUTF16[prefix..<newSuffix], as: UTF16.self)
        return (prefix, oldChangedLength, newChangedLength, inserted)
    }

    private func isStrongTextBoundaryChange(
        newValue: String,
        delta: (prefix: Int, oldChangedLength: Int, newChangedLength: Int, inserted: String)
    ) -> Bool {
        guard delta.newChangedLength > 0 else { return false }
        let newText = newValue as NSString
        if delta.inserted.contains("\n") {
            return containsParagraphBreakBoundary(in: newText, delta: delta)
        }
        return containsSentenceEndingPeriodBoundary(in: newText, delta: delta)
    }

    private func containsParagraphBreakBoundary(
        in text: NSString,
        delta: (prefix: Int, oldChangedLength: Int, newChangedLength: Int, inserted: String)
    ) -> Bool {
        guard delta.newChangedLength > 0 else { return false }
        let start = delta.prefix
        let end = delta.prefix + delta.newChangedLength
        if start < 0 || end > text.length || start >= end { return false }

        var i = start
        while i < end {
            let unit = text.character(at: i)
            if unit == 10 || unit == 13 {
                if lineHasSignificantContentBeforeBreak(in: text, breakIndex: i) {
                    return true
                }
            }
            i += 1
        }
        return false
    }

    private func lineHasSignificantContentBeforeBreak(in text: NSString, breakIndex: Int) -> Bool {
        guard breakIndex > 0 else { return false }
        var i = breakIndex - 1
        while i >= 0 {
            let unit = text.character(at: i)
            if unit == 10 || unit == 13 {
                return false
            }
            if let scalar = UnicodeScalar(unit), CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if i == 0 { break }
                i -= 1
                continue
            }
            return true
        }
        return false
    }

    private func containsSentenceEndingPeriodBoundary(
        in text: NSString,
        delta: (prefix: Int, oldChangedLength: Int, newChangedLength: Int, inserted: String)
    ) -> Bool {
        guard delta.newChangedLength > 0 else { return false }
        let start = delta.prefix
        let end = delta.prefix + delta.newChangedLength
        if start < 0 || end > text.length || start >= end { return false }

        var i = start
        while i < end {
            let unit = text.character(at: i)
            if unit == 46 || unit == 12290 {
                let nextIndex = i + 1
                if nextIndex >= text.length {
                    return true
                }
                let nextUnit = text.character(at: nextIndex)
                if let scalar = UnicodeScalar(nextUnit), CharacterSet.whitespacesAndNewlines.contains(scalar) {
                    return true
                }
            }
            i += 1
        }
        return false
    }

    private func entryID(scenarioID: UUID, cardID: UUID) -> String {
        "\(scenarioID.uuidString)|\(cardID.uuidString)"
    }

    private func loadPersistedEntries() {
        guard let data = UserDefaults.standard.data(forKey: Self.persistedEntriesKey) else { return }
        guard let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = decoded
    }

    private func persistEntries() {
        guard let encoded = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(encoded, forKey: Self.persistedEntriesKey)
    }
}

struct ReferenceWindowView: View {
    @EnvironmentObject private var store: FileStore
    @EnvironmentObject private var referenceCardStore: ReferenceCardStore
    @AppStorage("fontSize") private var fontSize: Double = 14.0
    @AppStorage("mainCardLineSpacingValueV2") private var mainCardLineSpacingValue: Double = 5.0
    @AppStorage("appearance") private var appearance: String = "dark"
    @FocusState private var focusedEntryID: String?
    private let referenceCardWidth: CGFloat = ReferenceWindowConstants.cardWidth

    private var referenceFontSize: CGFloat {
        max(8, CGFloat(fontSize * 0.8))
    }

    private var referenceLineSpacing: CGFloat {
        CGFloat(mainCardLineSpacingValue)
    }

    private struct ResolvedEntry: Identifiable {
        let entry: ReferenceCardStore.Entry
        let card: SceneCard

        var id: String { entry.id }
    }

    private var resolvedEntries: [ResolvedEntry] {
        referenceCardStore.entries.compactMap { entry in
            guard let scenario = store.scenarios.first(where: { $0.id == entry.scenarioID }) else { return nil }
            guard let card = scenario.cardByID(entry.cardID) else { return nil }
            return ResolvedEntry(entry: entry, card: card)
        }
    }

    private var panelBackground: Color {
        appearance == "light" ? Color(red: 0.95, green: 0.95, blue: 0.94) : Color(red: 0.12, green: 0.13, blue: 0.15)
    }

    var body: some View {
        ZStack {
            panelBackground
                .ignoresSafeArea()

            if resolvedEntries.isEmpty {
                Text("레퍼런스 카드가 없습니다")
                    .font(.custom("SansMonoCJKFinalDraft", size: 14))
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(resolvedEntries) { resolved in
                            ReferenceCardEditorRow(
                                scenarioID: resolved.entry.scenarioID,
                                cardID: resolved.entry.cardID,
                                entryID: resolved.entry.id,
                                card: resolved.card,
                                appearance: appearance,
                                cardWidth: referenceCardWidth,
                                fontSize: referenceFontSize,
                                lineSpacing: referenceLineSpacing,
                                focusedEntryID: $focusedEntryID,
                                onContentChange: { scenarioID, cardID, oldValue, newValue in
                                    referenceCardStore.handleContentChange(
                                        scenarioID: scenarioID,
                                        cardID: cardID,
                                        oldValue: oldValue,
                                        newValue: newValue,
                                        fileStore: store
                                    )
                                },
                                onRemove: {
                                    referenceCardStore.removeCard(cardID: resolved.entry.cardID, scenarioID: resolved.entry.scenarioID)
                                }
                            )
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(FloatingReferenceWindowAccessor())
        .onAppear {
            referenceCardStore.pruneMissingEntries(fileStore: store)
        }
    }
}

private struct ReferenceCardEditorRow: View {
    let scenarioID: UUID
    let cardID: UUID
    let entryID: String
    @ObservedObject var card: SceneCard
    let appearance: String
    let cardWidth: CGFloat
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    @AppStorage("cardActiveColorHex") private var cardActiveColorHex: String = "BFD7FF"
    @AppStorage("darkCardActiveColorHex") private var darkCardActiveColorHex: String = "2A3A4E"
    @FocusState.Binding var focusedEntryID: String?
    let onContentChange: (UUID, UUID, String, String) -> Void
    let onRemove: () -> Void

    @State private var measuredBodyHeight: CGFloat = 0
    @State private var isHovering: Bool = false
    @State private var caretVisibilityWorkItem: DispatchWorkItem? = nil

    private let outerPadding: CGFloat = 10
    private let editorVerticalPadding: CGFloat = 16

    private var isReferenceWindowFocused: Bool {
        NSApp.keyWindow?.identifier?.rawValue == ReferenceWindowConstants.windowID
    }

    private var editorHorizontalPadding: CGFloat {
        MainEditorLayoutMetrics.mainEditorHorizontalPadding
    }

    private var measuredEditorWidth: CGFloat {
        max(1, cardWidth - (outerPadding * 2) - (editorHorizontalPadding * 2))
    }

    private var measurementSafetyInset: CGFloat {
        max(12, lineSpacing + 8)
    }

    private var resolvedEditorHeight: CGFloat {
        max(1, measuredBodyHeight)
    }

    private var isDarkAppearanceActive: Bool {
        if appearance == "dark" { return true }
        if appearance == "light" { return false }
        if let best = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
            return best == .darkAqua
        }
        return true
    }

    private var referenceCardBackgroundColor: Color {
        let fallbackLight = (r: 0.75, g: 0.84, b: 1.0)
        let fallbackDark = (r: 0.16, g: 0.23, b: 0.31)
        let hex = isDarkAppearanceActive ? darkCardActiveColorHex : cardActiveColorHex
        if let rgb = rgbFromHex(hex) {
            return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
        }
        let fallback = isDarkAppearanceActive ? fallbackDark : fallbackLight
        return Color(red: fallback.r, green: fallback.g, blue: fallback.b)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(referenceCardBackgroundColor)

            VStack(alignment: .leading, spacing: 0) {
                TextEditor(text: Binding(
                    get: { card.content },
                    set: { newValue in
                        let oldValue = card.content
                        card.content = newValue
                        focusedEntryID = entryID
                        refreshMeasuredBodyHeight(for: newValue)
                        onContentChange(scenarioID, cardID, oldValue, newValue)
                        requestCaretVisibilityEnsure()
                    }
                ))
                .font(.custom("SansMonoCJKFinalDraft", size: Double(fontSize)))
                .lineSpacing(lineSpacing)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .scrollIndicators(.never)
                .frame(height: resolvedEditorHeight, alignment: .topLeading)
                .padding(.horizontal, editorHorizontalPadding)
                .padding(.vertical, editorVerticalPadding)
                .foregroundStyle(isDarkAppearanceActive ? .white : .black)
                .focused($focusedEntryID, equals: entryID)
            }
            .padding(outerPadding)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .padding(7)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .padding(.top, 14)
            .padding(.trailing, 8)
            .animation(.easeInOut(duration: 0.12), value: isHovering)
        }
        .frame(width: cardWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear {
            refreshMeasuredBodyHeight()
            DispatchQueue.main.async {
                refreshMeasuredBodyHeight()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                refreshMeasuredBodyHeight()
            }
        }
        .onChange(of: card.content) { _, newValue in
            DispatchQueue.main.async {
                refreshMeasuredBodyHeight(for: newValue)
                requestCaretVisibilityEnsure()
            }
        }
        .onChange(of: fontSize) { _, _ in
            refreshMeasuredBodyHeight()
            requestCaretVisibilityEnsure()
        }
        .onChange(of: lineSpacing) { _, _ in
            refreshMeasuredBodyHeight()
            requestCaretVisibilityEnsure()
        }
        .onChange(of: focusedEntryID) { _, newValue in
            if newValue == entryID {
                refreshMeasuredBodyHeight()
                requestCaretVisibilityEnsure()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSTextView.didChangeSelectionNotification)) { notification in
            guard focusedEntryID == entryID else { return }
            guard isReferenceWindowFocused else { return }
            guard let textView = notification.object as? NSTextView else { return }
            guard textView.window?.identifier?.rawValue == ReferenceWindowConstants.windowID else { return }
            guard (NSApp.keyWindow?.firstResponder as? NSTextView) === textView else { return }
            guard textView.string == card.content else { return }
            requestCaretVisibilityEnsure(delay: 0.0)
        }
        .onDisappear {
            caretVisibilityWorkItem?.cancel()
            caretVisibilityWorkItem = nil
        }
    }

    private func requestCaretVisibilityEnsure(delay: Double = 0.012) {
        caretVisibilityWorkItem?.cancel()
        let work = DispatchWorkItem {
            ensureCaretVisibleInReferenceWindow()
        }
        caretVisibilityWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func outerScrollView(containing textView: NSTextView) -> NSScrollView? {
        var node: NSView? = textView
        while let view = node {
            if let scrollView = view as? NSScrollView,
               scrollView.documentView !== textView.enclosingScrollView?.documentView {
                return scrollView
            }
            node = view.superview
        }
        return nil
    }

    private func ensureCaretVisibleInReferenceWindow() {
        guard focusedEntryID == entryID else { return }
        guard isReferenceWindowFocused else { return }
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        guard textView.window?.identifier?.rawValue == ReferenceWindowConstants.windowID else { return }
        guard textView.string == card.content else { return }
        guard let outerScrollView = outerScrollView(containing: textView) else { return }
        guard let outerDocumentView = outerScrollView.documentView else { return }
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }

        layoutManager.ensureLayout(for: textContainer)
        let textLength = (textView.string as NSString).length
        let selection = textView.selectedRange()
        let caretLocation = min(max(0, selection.location + selection.length), textLength)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: caretLocation, length: 0),
            actualCharacterRange: nil
        )
        var caretRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        caretRect.origin.x += textView.textContainerInset.width
        caretRect.origin.y += textView.textContainerInset.height
        if caretRect.height < fontSize {
            caretRect.size.height = fontSize + 2
        }
        let caretRectInDocument = outerDocumentView.convert(caretRect, from: textView)

        let visible = outerScrollView.documentVisibleRect
        let insets = outerScrollView.contentInsets
        let clipOriginY = outerScrollView.contentView.bounds.origin.y
        let inferredTopInset = max(0, -clipOriginY)
        let effectiveTopInset = max(insets.top, inferredTopInset)
        let minY = -effectiveTopInset
        let documentHeight = outerDocumentView.bounds.height
        let maxY = max(minY, documentHeight - visible.height + insets.bottom)

        let topPadding: CGFloat = 48
        let bottomPadding: CGFloat = 64
        let minVisibleY = visible.minY + topPadding
        let maxVisibleY = visible.maxY - bottomPadding

        var targetY = visible.origin.y
        if caretRectInDocument.maxY > maxVisibleY {
            targetY = caretRectInDocument.maxY - (visible.height - bottomPadding)
        } else if caretRectInDocument.minY < minVisibleY {
            targetY = max(minY, caretRectInDocument.minY - topPadding)
        }

        let clampedY = min(max(minY, targetY), maxY)
        if abs(clampedY - visible.origin.y) > 0.5 {
            outerScrollView.contentView.setBoundsOrigin(NSPoint(x: visible.origin.x, y: clampedY))
            outerScrollView.reflectScrolledClipView(outerScrollView.contentView)
        }
    }

    private func refreshMeasuredBodyHeight(for text: String? = nil) {
        let resolvedText = text ?? card.content
        let measured: CGFloat
        if focusedEntryID == entryID,
           let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           textView.window?.identifier?.rawValue == ReferenceWindowConstants.windowID,
           textView.string == resolvedText,
           let liveMeasured = liveFocusedBodyHeight(for: textView) {
            measured = liveMeasured
        } else {
            measured = ReferenceCardTextHeightCalculator.measureBodyHeight(
                text: resolvedText,
                fontSize: fontSize,
                lineSpacing: lineSpacing,
                width: measuredEditorWidth,
                safetyInset: measurementSafetyInset
            )
        }
        if abs(measuredBodyHeight - measured) > 0.25 {
            var noAnimation = Transaction()
            noAnimation.animation = nil
            withTransaction(noAnimation) {
                measuredBodyHeight = measured
            }
        }
    }

    private func rgbFromHex(_ hex: String) -> (Double, Double, Double)? {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return (r, g, b)
    }

    private func liveFocusedBodyHeight(for textView: NSTextView) -> CGFloat? {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return nil }
        let textLength = (textView.string as NSString).length
        let fullRange = NSRange(location: 0, length: textLength)
        if textLength > 0 {
            layoutManager.ensureGlyphs(forCharacterRange: fullRange)
            layoutManager.ensureLayout(forCharacterRange: fullRange)
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        guard usedHeight > 0 else { return nil }
        let insetHeight = textView.textContainerInset.height * 2
        return max(1, ceil(usedHeight + insetHeight + measurementSafetyInset))
    }
}

private enum ReferenceCardTextHeightCalculator {
    static func measureBodyHeight(
        text: String,
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        width: CGFloat,
        safetyInset: CGFloat
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
        textContainer.lineFragmentPadding = MainEditorLayoutMetrics.mainEditorLineFragmentPadding
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.maximumNumberOfLines = 0
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let usedHeight = layoutManager.usedRect(for: textContainer).height
        return max(1, ceil(usedHeight + safetyInset))
    }
}

private struct FloatingReferenceWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.identifier = NSUserInterfaceItemIdentifier(ReferenceWindowConstants.windowID)
            window.title = "레퍼런스 카드"
            window.level = .normal
            window.collectionBehavior.insert(.fullScreenAuxiliary)
            let fixedWidth = ReferenceWindowConstants.windowWidth
            window.minSize = NSSize(width: fixedWidth, height: 220)
            window.maxSize = NSSize(width: fixedWidth, height: 2000)
            window.contentMinSize = NSSize(width: fixedWidth, height: 220)
            window.contentMaxSize = NSSize(width: fixedWidth, height: 10000)
            if abs(window.frame.width - fixedWidth) > 0.5 {
                var frame = window.frame
                frame.size.width = fixedWidth
                window.setFrame(frame, display: true)
            }
            window.styleMask.remove(.resizable)
        }
    }
}
