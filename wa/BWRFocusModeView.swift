import SwiftUI
import AppKit

nonisolated enum BWRFocusModeKind: String, CaseIterable, Identifiable, Sendable {
    case currentLayer
    case treatment
    case scenario

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentLayer:
            return "Current"
        case .treatment:
            return "Treatment"
        case .scenario:
            return "Scenario"
        }
    }
}

nonisolated struct BWRFocusPresentation: Identifiable, Equatable, Sendable {
    var groupID: UUID
    var mode: BWRFocusModeKind

    var id: String {
        "\(groupID.uuidString)|\(mode.rawValue)"
    }
}

nonisolated struct BWRFocusEntryID: Hashable, Equatable, Sendable {
    var cardID: UUID
    var layerID: UUID

    var rawValue: String {
        "\(cardID.uuidString)|\(layerID.uuidString)"
    }
}

nonisolated struct BWRFocusEntry: Identifiable, Equatable, Sendable {
    var id: BWRFocusEntryID
    var cardID: UUID
    var layerID: UUID
    var cardTitle: String
    var layerName: String
    var cardIndex: Int
    var markdown: String
}

nonisolated struct BWRFocusSearchMatch: Identifiable, Equatable, Sendable {
    var id: String
    var entryID: BWRFocusEntryID
    var range: NSRange
    var preview: String
}

nonisolated enum BWRFocusTextBoundaryReason: String, Equatable, Sendable {
    case sentence
    case paragraph
    case idle
    case cardSwitch
    case modeSwitch
    case split
    case dismiss
}

nonisolated enum BWRFocusModeProjection {
    static func entries(
        document: BWRDocument,
        groupID: UUID,
        mode: BWRFocusModeKind
    ) -> [BWRFocusEntry] {
        let orderedCards = BWRBoardOrderResolver.orderedCards(inGroup: groupID, document: document)

        return orderedCards.enumerated().compactMap { index, card in
            guard let layer = resolvedLayer(for: card, mode: mode) else { return nil }
            return BWRFocusEntry(
                id: BWRFocusEntryID(cardID: card.id, layerID: layer.id),
                cardID: card.id,
                layerID: layer.id,
                cardTitle: card.titlePreview,
                layerName: layer.name,
                cardIndex: index,
                markdown: layer.markdown
            )
        }
    }

    private static func resolvedLayer(for card: BWRCard, mode: BWRFocusModeKind) -> BWRCardLayer? {
        switch mode {
        case .currentLayer:
            return card.currentLayer ?? card.layers.first
        case .treatment:
            return card.layers.first(where: { $0.kind == .treatment })
        case .scenario:
            return card.layers.first(where: { $0.kind == .scenario })
        }
    }
}

nonisolated enum BWRFocusSearchEngine {
    static func matches(query: String, entries: [BWRFocusEntry], textByEntryID: [BWRFocusEntryID: String]) -> [BWRFocusSearchMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var results: [BWRFocusSearchMatch] = []
        for entry in entries {
            let text = textByEntryID[entry.id] ?? entry.markdown
            let nsText = text as NSString
            var searchRange = NSRange(location: 0, length: nsText.length)

            while searchRange.length > 0 {
                let found = nsText.range(
                    of: trimmed,
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    range: searchRange
                )
                guard found.location != NSNotFound, found.length > 0 else { break }

                results.append(
                    BWRFocusSearchMatch(
                        id: "\(entry.id.rawValue)|\(found.location)|\(found.length)",
                        entryID: entry.id,
                        range: found,
                        preview: preview(for: nsText as String, range: found)
                    )
                )

                let nextLocation = found.location + found.length
                guard nextLocation < nsText.length else { break }
                searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
            }
        }
        return results
    }

    private static func preview(for text: String, range: NSRange) -> String {
        let nsText = text as NSString
        let previewStart = max(0, range.location - 18)
        let previewEnd = min(nsText.length, range.location + range.length + 22)
        let previewRange = NSRange(location: previewStart, length: previewEnd - previewStart)
        return nsText.substring(with: previewRange).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated enum BWRFocusTextBoundaryDetector {
    static func detect(previous: String, current: String, selection: NSRange) -> BWRFocusTextBoundaryReason? {
        guard previous != current else { return nil }
        let nsText = current as NSString
        let cursor = min(max(0, selection.location), nsText.length)
        guard cursor > 0 else { return nil }

        let lastCharacter = nsText.substring(with: NSRange(location: cursor - 1, length: 1))
        if lastCharacter == "\n" {
            if cursor >= 2 {
                let previousCharacter = nsText.substring(with: NSRange(location: cursor - 2, length: 1))
                if previousCharacter == "\n" {
                    return .paragraph
                }
            }
            return nil
        }

        if [".", "!", "?"].contains(lastCharacter) {
            return .sentence
        }

        return nil
    }
}

@MainActor
private struct BWRFocusDraftState {
    var text: String
    var committedText: String
    var selectedRange: NSRange

    var isDirty: Bool {
        text != committedText
    }
}

@MainActor
private struct BWRFocusSelectionRequest: Equatable {
    var entryID: BWRFocusEntryID
    var selectedRange: NSRange
    var token: Int
}

@MainActor
private final class BWRFocusTextViewBox {
    weak var textView: BWRCommandTextView?

    init(textView: BWRCommandTextView?) {
        self.textView = textView
    }
}

@MainActor
struct BWRFocusModeView: View {
    @ObservedObject var document: BWRReferenceDocument
    let groupID: UUID
    let initialMode: BWRFocusModeKind
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @AppStorage("bwr.focus.typewriterEnabled") private var typewriterEnabled: Bool = true
    @FocusState private var searchFieldFocused: Bool

    @State private var mode: BWRFocusModeKind
    @State private var drafts: [BWRFocusEntryID: BWRFocusDraftState] = [:]
    @State private var activeEntryID: BWRFocusEntryID?
    @State private var focusRequest: BWRFocusSelectionRequest?
    @State private var registeredEditors: [BWRFocusEntryID: BWRFocusTextViewBox] = [:]
    @State private var searchText: String = ""
    @State private var searchMatches: [BWRFocusSearchMatch] = []
    @State private var selectedSearchIndex: Int = -1
    @State private var showsSearchPopup: Bool = false
    @State private var idleFinalizeWorkItem: DispatchWorkItem?

    init(
        document: BWRReferenceDocument,
        groupID: UUID,
        initialMode: BWRFocusModeKind,
        onDismiss: @escaping () -> Void
    ) {
        self.document = document
        self.groupID = groupID
        self.initialMode = initialMode
        self.onDismiss = onDismiss
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        GeometryReader { geometry in
            let layoutMode = BWRFocusLayoutMode.resolve(for: geometry.size)
            ZStack {
                Color.black.opacity(0.94)
                    .ignoresSafeArea()

                VStack(spacing: layoutMode == .regular ? 18 : 12) {
                    header(layoutMode: layoutMode)
                    focusCanvas(layoutMode: layoutMode)
                }
                .padding(.horizontal, layoutMode == .regular ? 26 : 14)
                .padding(.vertical, layoutMode == .regular ? 20 : 14)

                if showsSearchPopup {
                    searchPopup(width: min(300, max(220, geometry.size.width - 32)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, layoutMode == .regular ? 20 : 14)
                        .padding(.trailing, layoutMode == .regular ? 30 : 16)
                }
            }
        }
        .onAppear {
            syncDrafts()
            ensureActiveEntry()
        }
        .onDisappear {
            finalizeFocusSession(reason: .dismiss)
        }
        .onChange(of: entryFingerprint) { _, _ in
            syncDrafts()
            ensureActiveEntry()
            refreshSearchMatchesIfNeeded()
            if currentGroup == nil {
                closeFocusMode()
            }
        }
        .onChange(of: mode) { oldMode, _ in
            guard oldMode != mode else { return }
            finalizeTextBoundary(reason: .modeSwitch, commitAll: true)
            syncDrafts()
            ensureActiveEntry(forceFirst: true)
            refreshSearchMatchesIfNeeded()
        }
        .onKeyPress(phases: [.down]) { press in
            handleRootKeyPress(press)
        }
        .onExitCommand {
            if showsSearchPopup {
                closeSearchPopup()
            } else {
                closeFocusMode()
            }
        }
    }

    private var currentGroup: BWRGroup? {
        document.liveGroups.first(where: { $0.id == groupID })
    }

    private var entries: [BWRFocusEntry] {
        BWRFocusModeProjection.entries(document: document.document, groupID: groupID, mode: mode)
    }

    private var entryFingerprint: [String] {
        entries.map { "\($0.id.rawValue)|\($0.cardTitle)|\($0.markdown)" }
    }

    private var searchStatusText: String {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "검색어 입력" }
        guard !searchMatches.isEmpty else { return "결과 없음" }
        let current = min(max(0, selectedSearchIndex + 1), searchMatches.count)
        return "\(current)/\(searchMatches.count)"
    }

    private func header(layoutMode: BWRFocusLayoutMode) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                headerTitleBlock(layoutMode: layoutMode)
                Spacer(minLength: 12)
                headerControls(layoutMode: layoutMode)
            }

            VStack(alignment: .leading, spacing: 10) {
                headerTitleBlock(layoutMode: layoutMode)
                headerControls(layoutMode: .compact)
            }
        }
    }

    private func headerTitleBlock(layoutMode: BWRFocusLayoutMode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(currentGroup?.name ?? "Archived Group")
                .font(.system(size: layoutMode == .regular ? 24 : 20, weight: .semibold))
                .foregroundStyle(.white)
            Text("\(entries.count) cards in focus")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.58))
        }
    }

    private func headerControls(layoutMode: BWRFocusLayoutMode) -> some View {
        VStack(alignment: layoutMode == .regular ? .trailing : .leading, spacing: 10) {
            Picker("Mode", selection: $mode) {
                ForEach(BWRFocusModeKind.allCases) { focusMode in
                    Text(focusMode.title).tag(focusMode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: layoutMode == .regular ? 320 : .infinity)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    focusActionButtons
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        focusPrimaryButtons
                    }
                    HStack(spacing: 10) {
                        focusSecondaryButtons
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var focusActionButtons: some View {
        focusPrimaryButtons
        focusSecondaryButtons
    }

    @ViewBuilder
    private var focusPrimaryButtons: some View {
        Toggle("Typewriter", isOn: $typewriterEnabled)
            .toggleStyle(.button)

        Button("Search") {
            openSearchPopup()
        }
        .keyboardShortcut("f", modifiers: [.command])

        Button("Split") {
            splitActiveEntry()
        }
        .disabled(activeEntryID == nil)
    }

    @ViewBuilder
    private var focusSecondaryButtons: some View {
        Button("Undo") {
            _ = performUndo()
        }
        .disabled(!canUndo)

        Button("Redo") {
            _ = performRedo()
        }
        .disabled(!canRedo)

        Button("Done") {
            closeFocusMode()
        }
    }

    private func focusCanvas(layoutMode: BWRFocusLayoutMode) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: layoutMode == .regular ? 40 : 18)
                    ForEach(entries) { entry in
                        focusCardBlock(for: entry, layoutMode: layoutMode)
                            .id(entry.id.rawValue)
                        if entry.cardIndex < entries.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.16))
                                .frame(height: 1)
                                .padding(.horizontal, layoutMode == .regular ? 24 : 12)
                        }
                    }
                    Color.clear.frame(height: layoutMode == .regular ? 80 : 28)
                }
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                revealActiveEntry(with: proxy, animated: false)
            }
            .onChange(of: activeEntryID) { _, _ in
                revealActiveEntry(with: proxy, animated: true)
            }
            .onChange(of: focusRequest?.token) { _, _ in
                revealActiveEntry(with: proxy, animated: true)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: layoutMode == .regular ? 28 : 22, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: layoutMode == .regular ? 28 : 22, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func focusCardBlock(for entry: BWRFocusEntry, layoutMode: BWRFocusLayoutMode) -> some View {
        let isActive = activeEntryID == entry.id

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(entry.cardTitle)
                    .font(.system(size: layoutMode == .regular ? 15 : 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(entry.layerName.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08), in: Capsule())
                Spacer()
                Text(String(format: "%02d", entry.cardIndex + 1))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }

            BWRCardMarkdownEditor(
                text: textBinding(for: entry.id, fallback: entry.markdown),
                selectedRange: selectedRangeBinding(for: entry.id),
                fontSize: layoutMode == .regular ? 22 : 18,
                autoFocus: false,
                focusRequestToken: focusToken(for: entry.id),
                centersSelectionWhenFocused: typewriterEnabled && isActive,
                onSplit: { _, range in
                    split(entry: entry, at: range.location)
                },
                onEscape: {
                    if showsSearchPopup {
                        closeSearchPopup()
                    } else {
                        closeFocusMode()
                    }
                },
                onFindCommand: {
                    openSearchPopup()
                    return true
                },
                onUndoCommand: {
                    performUndo()
                },
                onRedoCommand: {
                    performRedo()
                },
                onBoundaryNavigation: { direction, _, range in
                    navigateBoundary(from: entry.id, direction: direction, selection: range)
                },
                onTextDidChange: { previous, current, range in
                    handleTextChange(for: entry.id, previous: previous, current: current, selection: range)
                },
                onSelectionDidChange: { _, range in
                    handleSelectionChange(for: entry.id, selection: range)
                },
                onTextViewMounted: { textView in
                    DispatchQueue.main.async {
                        registeredEditors[entry.id] = BWRFocusTextViewBox(textView: textView)
                    }
                }
            )
            .frame(
                minHeight: layoutMode == .regular ? 290 : 220,
                idealHeight: layoutMode == .regular ? 360 : 280,
                maxHeight: layoutMode == .regular ? 420 : 340
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isActive ? Color.white.opacity(0.55) : Color.white.opacity(0.12), lineWidth: isActive ? 1.8 : 1.0)
            )
        }
        .padding(.horizontal, layoutMode == .regular ? 72 : 22)
        .padding(.vertical, layoutMode == .regular ? 28 : 18)
        .background(isActive ? Color.white.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            setActiveEntry(entry.id, desiredRange: drafts[entry.id]?.selectedRange ?? NSRange(location: 0, length: 0), reveal: true)
        }
    }

    private func searchPopup(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.72))
                TextField("Focus search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .focused($searchFieldFocused)
                    .onChange(of: searchText) { _, _ in
                        refreshSearchMatches()
                    }
                    .onSubmit {
                        moveSearchSelection(step: 1)
                    }
                Button {
                    closeSearchPopup()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.56))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Text(searchStatusText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button {
                    moveSearchSelection(step: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(searchMatches.isEmpty)
                Button {
                    moveSearchSelection(step: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(searchMatches.isEmpty)
            }

            if let activeMatch = activeSearchMatch {
                Text(activeMatch.preview)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var activeSearchMatch: BWRFocusSearchMatch? {
        guard searchMatches.indices.contains(selectedSearchIndex) else { return nil }
        return searchMatches[selectedSearchIndex]
    }

    private var canUndo: Bool {
        if let activeEntryID,
           registeredEditors[activeEntryID]?.textView?.undoManager?.canUndo == true {
            return true
        }
        return undoManager?.canUndo ?? false
    }

    private var canRedo: Bool {
        if let activeEntryID,
           registeredEditors[activeEntryID]?.textView?.undoManager?.canRedo == true {
            return true
        }
        return undoManager?.canRedo ?? false
    }

    private func textBinding(for entryID: BWRFocusEntryID, fallback: String) -> Binding<String> {
        Binding(
            get: { drafts[entryID]?.text ?? fallback },
            set: { newValue in
                var draft = drafts[entryID] ?? BWRFocusDraftState(
                    text: fallback,
                    committedText: fallback,
                    selectedRange: NSRange(location: 0, length: 0)
                )
                draft.text = newValue
                drafts[entryID] = draft
            }
        )
    }

    private func selectedRangeBinding(for entryID: BWRFocusEntryID) -> Binding<NSRange> {
        Binding(
            get: { drafts[entryID]?.selectedRange ?? NSRange(location: 0, length: 0) },
            set: { newValue in
                guard var draft = drafts[entryID] else { return }
                draft.selectedRange = newValue
                drafts[entryID] = draft
            }
        )
    }

    private func focusToken(for entryID: BWRFocusEntryID) -> Int {
        guard focusRequest?.entryID == entryID else { return 0 }
        return focusRequest?.token ?? 0
    }

    private func syncDrafts() {
        let sourceEntries = entries
        var nextDrafts: [BWRFocusEntryID: BWRFocusDraftState] = [:]

        for entry in sourceEntries {
            if let existing = drafts[entry.id] {
                var draft = existing
                if !existing.isDirty {
                    draft.text = entry.markdown
                }
                draft.committedText = entry.markdown
                nextDrafts[entry.id] = draft
            } else {
                nextDrafts[entry.id] = BWRFocusDraftState(
                    text: entry.markdown,
                    committedText: entry.markdown,
                    selectedRange: NSRange(location: 0, length: 0)
                )
            }
        }

        drafts = nextDrafts
        registeredEditors = registeredEditors.filter { nextDrafts[$0.key] != nil }
        if let activeEntryID, nextDrafts[activeEntryID] == nil {
            self.activeEntryID = sourceEntries.first?.id
        }
    }

    private func ensureActiveEntry(forceFirst: Bool = false) {
        guard !entries.isEmpty else { return }
        if forceFirst || activeEntryID == nil || drafts[activeEntryID!] == nil {
            let entryID = entries[0].id
            activeEntryID = entryID
            let selection = drafts[entryID]?.selectedRange ?? NSRange(location: 0, length: 0)
            focusRequest = BWRFocusSelectionRequest(entryID: entryID, selectedRange: selection, token: (focusRequest?.token ?? 0) + 1)
        }
    }

    private func revealActiveEntry(with proxy: ScrollViewProxy, animated: Bool) {
        guard let activeEntryID else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(activeEntryID.rawValue, anchor: .center)
            }
        } else {
            proxy.scrollTo(activeEntryID.rawValue, anchor: .center)
        }
    }

    private func handleRootKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard press.phase == .down else { return .ignored }
        if press.modifiers == [.command],
           (press.characters.lowercased() == "f" || press.characters == "ㄹ") {
            openSearchPopup()
            return .handled
        }
        if press.modifiers == [.command],
           let mappedMode = BWRFocusModeKind.keyboardMapping(for: press.characters) {
            mode = mappedMode
            return .handled
        }
        if press.modifiers == [.command],
           press.characters.lowercased() == "g" {
            moveSearchSelection(step: 1)
            return .handled
        }
        if press.modifiers == [.command, .shift],
           press.characters.lowercased() == "g" {
            moveSearchSelection(step: -1)
            return .handled
        }
        return .ignored
    }

    private func openSearchPopup() {
        showsSearchPopup = true
        refreshSearchMatches()
        DispatchQueue.main.async {
            searchFieldFocused = true
        }
    }

    private func closeSearchPopup() {
        showsSearchPopup = false
        searchText = ""
        searchMatches = []
        selectedSearchIndex = -1
        searchFieldFocused = false
    }

    private func refreshSearchMatches() {
        let textByEntryID = Dictionary(uniqueKeysWithValues: drafts.map { ($0.key, $0.value.text) })
        searchMatches = BWRFocusSearchEngine.matches(query: searchText, entries: entries, textByEntryID: textByEntryID)
        selectedSearchIndex = searchMatches.isEmpty ? -1 : 0
        if let match = activeSearchMatch {
            revealSearchMatch(match)
        }
    }

    private func refreshSearchMatchesIfNeeded() {
        guard showsSearchPopup || !searchText.isEmpty else { return }
        refreshSearchMatches()
    }

    private func moveSearchSelection(step: Int) {
        refreshSearchMatches()
        guard !searchMatches.isEmpty else { return }
        if selectedSearchIndex < 0 {
            selectedSearchIndex = step >= 0 ? 0 : (searchMatches.count - 1)
        } else {
            selectedSearchIndex = (selectedSearchIndex + step + searchMatches.count) % searchMatches.count
        }
        if let match = activeSearchMatch {
            revealSearchMatch(match)
        }
    }

    private func revealSearchMatch(_ match: BWRFocusSearchMatch) {
        setActiveEntry(match.entryID, desiredRange: match.range, reveal: true)
        if showsSearchPopup {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                searchFieldFocused = true
            }
        }
    }

    private func setActiveEntry(
        _ entryID: BWRFocusEntryID,
        desiredRange: NSRange? = nil,
        reveal: Bool,
        finalizePrevious: Bool = true
    ) {
        _ = reveal
        if finalizePrevious, let activeEntryID, activeEntryID != entryID {
            finalizeTextBoundary(reason: .cardSwitch, entryID: activeEntryID)
        }

        activeEntryID = entryID
        let range = desiredRange ?? drafts[entryID]?.selectedRange ?? NSRange(location: 0, length: 0)
        if var draft = drafts[entryID] {
            draft.selectedRange = range
            drafts[entryID] = draft
        }

        focusRequest = BWRFocusSelectionRequest(
            entryID: entryID,
            selectedRange: range,
            token: (focusRequest?.token ?? 0) + 1
        )
    }

    private func handleSelectionChange(for entryID: BWRFocusEntryID, selection: NSRange) {
        guard var draft = drafts[entryID] else { return }
        draft.selectedRange = selection
        drafts[entryID] = draft

        if activeEntryID != entryID {
            setActiveEntry(entryID, desiredRange: selection, reveal: true)
        }
    }

    private func handleTextChange(
        for entryID: BWRFocusEntryID,
        previous: String,
        current: String,
        selection: NSRange
    ) {
        guard var draft = drafts[entryID] else { return }
        draft.text = current
        draft.selectedRange = selection
        drafts[entryID] = draft

        if activeEntryID != entryID {
            setActiveEntry(entryID, desiredRange: selection, reveal: true)
        }

        if let boundary = BWRFocusTextBoundaryDetector.detect(previous: previous, current: current, selection: selection) {
            finalizeTextBoundary(reason: boundary, entryID: entryID)
        } else {
            scheduleIdleFinalize(for: entryID)
        }

        refreshSearchMatchesIfNeeded()
    }

    private func scheduleIdleFinalize(for entryID: BWRFocusEntryID) {
        idleFinalizeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [entryID] in
            Task { @MainActor in
                finalizeTextBoundary(reason: .idle, entryID: entryID)
            }
        }
        idleFinalizeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    private func finalizeTextBoundary(
        reason: BWRFocusTextBoundaryReason,
        entryID: BWRFocusEntryID? = nil,
        commitAll: Bool = false
    ) {
        idleFinalizeWorkItem?.cancel()

        if let resolvedEntryID = entryID ?? activeEntryID,
           let textView = registeredEditors[resolvedEntryID]?.textView {
            textView.markUndoBoundary()
        }

        if commitAll {
            commitDirtyDrafts()
        } else if let resolvedEntryID = entryID ?? activeEntryID {
            commitDirtyDrafts(entryIDs: [resolvedEntryID])
        }

        if reason == .dismiss || reason == .modeSwitch {
            refreshSearchMatchesIfNeeded()
        }
    }

    private func commitDirtyDrafts(entryIDs: Set<BWRFocusEntryID>? = nil) {
        let changes = drafts.compactMap { entryID, draft -> BWRLayerMarkdownChange? in
            guard entryIDs?.contains(entryID) ?? true else { return nil }
            guard draft.isDirty else { return nil }
            return BWRLayerMarkdownChange(cardID: entryID.cardID, layerID: entryID.layerID, markdown: draft.text)
        }

        guard !changes.isEmpty else { return }
        document.applyLayerMarkdownChanges(changes, registerUndo: false)
        for change in changes {
            let entryID = BWRFocusEntryID(cardID: change.cardID, layerID: change.layerID)
            guard var draft = drafts[entryID] else { continue }
            draft.committedText = draft.text
            drafts[entryID] = draft
        }
    }

    private func navigateBoundary(
        from entryID: BWRFocusEntryID,
        direction: BWRTextBoundaryNavigationDirection,
        selection: NSRange
    ) -> Bool {
        guard let currentIndex = entries.firstIndex(where: { $0.id == entryID }) else { return false }

        let targetIndex: Int
        let targetSelection: NSRange
        switch direction {
        case .previousCard:
            guard currentIndex > 0 else { return false }
            targetIndex = currentIndex - 1
            let targetText = drafts[entries[targetIndex].id]?.text ?? entries[targetIndex].markdown
            let textLength = (targetText as NSString).length
            targetSelection = NSRange(location: textLength, length: 0)
        case .nextCard:
            guard currentIndex < entries.count - 1 else { return false }
            targetIndex = currentIndex + 1
            targetSelection = NSRange(location: 0, length: 0)
        }

        let targetEntryID = entries[targetIndex].id
        setActiveEntry(targetEntryID, desiredRange: targetSelection, reveal: true)
        return true
    }

    private func splitActiveEntry() {
        guard let activeEntryID,
              let draft = drafts[activeEntryID] else { return }
        split(entryID: activeEntryID, at: draft.selectedRange.location)
    }

    private func split(entry: BWRFocusEntry, at location: Int) {
        split(entryID: entry.id, at: location)
    }

    private func split(entryID: BWRFocusEntryID, at location: Int) {
        finalizeTextBoundary(reason: .split, commitAll: true)
        guard let draft = drafts[entryID],
              let newCardID = document.splitCard(
                cardID: entryID.cardID,
                layerID: entryID.layerID,
                committedMarkdown: draft.text,
                atUTF16Location: location
              ) else {
            return
        }

        syncDrafts()
        let candidateEntries = entries.filter { $0.cardID == newCardID }
        let targetEntryID = candidateEntries.first(where: { $0.layerID == entryID.layerID })?.id ?? candidateEntries.first?.id
        if let targetEntryID {
            setActiveEntry(targetEntryID, desiredRange: NSRange(location: 0, length: 0), reveal: true, finalizePrevious: false)
        }
    }

    @discardableResult
    private func performUndo() -> Bool {
        if let activeEntryID,
           let textView = registeredEditors[activeEntryID]?.textView,
           textView.undoManager?.canUndo == true {
            textView.undoManager?.undo()
            if var draft = drafts[activeEntryID] {
                draft.text = textView.string
                draft.selectedRange = textView.selectedRange()
                drafts[activeEntryID] = draft
            }
            scheduleIdleFinalize(for: activeEntryID)
            refreshSearchMatchesIfNeeded()
            return true
        }

        finalizeTextBoundary(reason: .cardSwitch, commitAll: true)
        guard undoManager?.canUndo == true else { return false }
        undoManager?.undo()
        syncDrafts()
        ensureActiveEntry()
        return true
    }

    @discardableResult
    private func performRedo() -> Bool {
        if let activeEntryID,
           let textView = registeredEditors[activeEntryID]?.textView,
           textView.undoManager?.canRedo == true {
            textView.undoManager?.redo()
            if var draft = drafts[activeEntryID] {
                draft.text = textView.string
                draft.selectedRange = textView.selectedRange()
                drafts[activeEntryID] = draft
            }
            scheduleIdleFinalize(for: activeEntryID)
            refreshSearchMatchesIfNeeded()
            return true
        }

        finalizeTextBoundary(reason: .cardSwitch, commitAll: true)
        guard undoManager?.canRedo == true else { return false }
        undoManager?.redo()
        syncDrafts()
        ensureActiveEntry()
        return true
    }

    private func finalizeFocusSession(reason: BWRFocusTextBoundaryReason) {
        finalizeTextBoundary(reason: reason, commitAll: true)
    }

    private func closeFocusMode() {
        finalizeFocusSession(reason: .dismiss)
        onDismiss()
        dismiss()
    }
}
