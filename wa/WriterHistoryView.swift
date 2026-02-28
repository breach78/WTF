import SwiftUI
import AppKit

private enum ScenarioHistoryEngine {
    nonisolated static func snapshotOrderLess(_ lhs: CardSnapshot, _ rhs: CardSnapshot) -> Bool {
        if lhs.orderIndex != rhs.orderIndex {
            return lhs.orderIndex < rhs.orderIndex
        }
        return lhs.cardID.uuidString < rhs.cardID.uuidString
    }

    static func retentionRule(
        forAge age: TimeInterval
    ) -> (tier: ScenarioWriterView.HistoryRetentionTier, interval: TimeInterval) {
        if age <= 60 * 60 {
            return (.recentHour, 60)
        }
        if age <= 60 * 60 * 24 {
            return (.recentDay, 60 * 10)
        }
        if age <= 60 * 60 * 24 * 7 {
            return (.recentWeek, 60 * 60)
        }
        if age <= 60 * 60 * 24 * 30 {
            return (.recentMonth, 60 * 60 * 24)
        }
        return (.archive, 60 * 60 * 24 * 7)
    }

    static func sortedCardSnapshots(
        from state: [UUID: CardSnapshot]
    ) -> [CardSnapshot] {
        let byParent = Dictionary(grouping: state.values) { $0.parentID }
        var ordered: [CardSnapshot] = []
        var visited = Set<UUID>()

        func appendSubtree(parentID: UUID?) {
            let children = (byParent[parentID] ?? []).sorted(by: snapshotOrderLess)
            for snapshot in children {
                if visited.insert(snapshot.cardID).inserted {
                    ordered.append(snapshot)
                    appendSubtree(parentID: snapshot.cardID)
                }
            }
        }

        appendSubtree(parentID: nil)

        let remaining = state.values
            .filter { !visited.contains($0.cardID) }
            .sorted(by: snapshotOrderLess)
        for snapshot in remaining {
            if visited.insert(snapshot.cardID).inserted {
                ordered.append(snapshot)
                appendSubtree(parentID: snapshot.cardID)
            }
        }

        return ordered
    }

    static func buildDeltaPayload(
        from previousMap: [UUID: CardSnapshot],
        to currentMap: [UUID: CardSnapshot]
    ) -> (changed: [CardSnapshot], deleted: [UUID]) {
        var changed: [CardSnapshot] = []
        for snapshot in currentMap.values {
            if previousMap[snapshot.cardID] != snapshot {
                changed.append(snapshot)
            }
        }
        changed.sort(by: snapshotOrderLess)
        let deleted = previousMap.keys
            .filter { currentMap[$0] == nil }
            .sorted { $0.uuidString < $1.uuidString }
        return (changed, deleted)
    }

    static func shouldInsertFullSnapshotCheckpoint(
        in snapshots: [HistorySnapshot],
        checkpointInterval: Int
    ) -> Bool {
        if snapshots.isEmpty { return true }
        var trailingDeltaCount = 0
        for snapshot in snapshots.reversed() {
            if snapshot.isDelta {
                trailingDeltaCount += 1
            } else {
                break
            }
        }
        return trailingDeltaCount >= checkpointInterval
    }

    static func applySnapshotState(
        _ snapshot: HistorySnapshot,
        to state: inout [UUID: CardSnapshot]
    ) {
        if snapshot.isDelta {
            for deletedID in snapshot.deletedCardIDs {
                state.removeValue(forKey: deletedID)
            }
            for changed in snapshot.cardSnapshots {
                state[changed.cardID] = changed
            }
            return
        }
        state.removeAll(keepingCapacity: true)
        for cardSnapshot in snapshot.cardSnapshots {
            state[cardSnapshot.cardID] = cardSnapshot
        }
        for deletedID in snapshot.deletedCardIDs {
            state.removeValue(forKey: deletedID)
        }
    }
}

extension ScenarioWriterView {

    private func snapshotOrderLess(_ lhs: CardSnapshot, _ rhs: CardSnapshot) -> Bool {
        ScenarioHistoryEngine.snapshotOrderLess(lhs, rhs)
    }

    private func snapshotDiffOrderLess(_ lhs: SnapshotDiff, _ rhs: SnapshotDiff) -> Bool {
        snapshotOrderLess(lhs.snapshot, rhs.snapshot)
    }

    @ViewBuilder
    func previewColumn(for diffs: [SnapshotDiff], level: Int, screenHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { vProxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        Color.clear.frame(height: screenHeight * 0.4)
                        ForEach(diffs) { diff in
                            PreviewCardItem(
                                diff: diff,
                                isSelected: historyPreviewSelectedCardIDs.contains(diff.id),
                                isMultiSelected: historyPreviewSelectedCardIDs.count > 1 && historyPreviewSelectedCardIDs.contains(diff.id),
                                onSelect: {
                                    selectHistoryPreviewCard(diff.id)
                                },
                                onCopyCards: {
                                    copyHistoryPreviewCardsToClipboard(fallbackID: diff.id)
                                },
                                onCopyContents: {
                                    copyHistoryPreviewContentsToClipboard(fallbackID: diff.id)
                                }
                            )
                            .id("preview-card-\(diff.id)")
                        }
                        Color.clear.frame(height: screenHeight * 0.6)
                    }
                    .padding(12).frame(width: columnWidth)
                }
                .onChange(of: Int(historyIndex)) { _, _ in
                    if let firstChange = diffs.first(where: { $0.status != .none }) {
                        withAnimation(quickEaseAnimation) {
                            vProxy.scrollTo("preview-card-\(firstChange.id)", anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: columnWidth)
    }

    func selectHistoryPreviewCard(_ diffID: UUID) {
        guard isPreviewingHistory else { return }
        guard previewDiffs.contains(where: { $0.id == diffID }) else { return }

        let isCommandPressed = NSEvent.modifierFlags.contains(.command)
        if isCommandPressed {
            if historyPreviewSelectedCardIDs.contains(diffID) {
                historyPreviewSelectedCardIDs.remove(diffID)
            } else {
                historyPreviewSelectedCardIDs.insert(diffID)
            }
        } else {
            historyPreviewSelectedCardIDs = [diffID]
        }
        isMainViewFocused = true
    }

    func copyHistoryPreviewCardsToClipboard(fallbackID: UUID? = nil) {
        let targetIDs = resolvedHistoryPreviewCopyTargetIDs(fallbackID: fallbackID)
        guard !targetIDs.isEmpty else { return }

        let diffMap = historyPreviewDiffMap()
        let orderedDiffs = targetIDs
            .compactMap { diffMap[$0] }
            .sorted(by: snapshotDiffOrderLess)
        let roots = orderedDiffs.map { diff in
            CardTreeClipboardNode(
                content: diff.snapshot.content,
                colorHex: nil,
                isAICandidate: false,
                children: []
            )
        }
        guard !roots.isEmpty else { return }

        let payload = CardTreeClipboardPayload(roots: roots)
        guard persistCardTreePayloadToClipboard(payload) else { return }
        clearCutCardTreeBuffer()
    }

    func copyHistoryPreviewContentsToClipboard(fallbackID: UUID? = nil) {
        let targetIDs = resolvedHistoryPreviewCopyTargetIDs(fallbackID: fallbackID)
        guard !targetIDs.isEmpty else { return }

        let diffMap = historyPreviewDiffMap()
        let orderedDiffs = targetIDs
            .compactMap { diffMap[$0] }
            .sorted(by: snapshotDiffOrderLess)
        let text = orderedDiffs
            .map { $0.snapshot.content }
            .joined(separator: "\n\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func resolvedHistoryPreviewCopyTargetIDs(fallbackID: UUID?) -> Set<UUID> {
        let diffMap = historyPreviewDiffMap()
        guard !diffMap.isEmpty else { return [] }

        var targetIDs = historyPreviewSelectedCardIDs.filter { diffMap[$0] != nil }
        if let fallbackID, diffMap[fallbackID] != nil {
            if targetIDs.isEmpty || !targetIDs.contains(fallbackID) {
                targetIDs = [fallbackID]
            }
        }
        return targetIDs
    }

    func historyPreviewDiffMap() -> [UUID: SnapshotDiff] {
        Dictionary(uniqueKeysWithValues: previewDiffs.map { ($0.id, $0) })
    }

    func autoScrollToChanges(hProxy: ScrollViewProxy) {
        let previewLevels = buildPreviewLevels()
        for (idx, diffs) in previewLevels.enumerated() {
            if diffs.contains(where: { $0.status != .none }) {
                hProxy.scrollTo("preview-col-\(idx)", anchor: .center)
                break
            }
        }
    }

    func buildPreviewLevels() -> [[SnapshotDiff]] {
        let orderedDiffs = previewDiffs.filter { !$0.snapshot.isFloating }
        let byParent = Dictionary(grouping: orderedDiffs) { $0.snapshot.parentID }
        let roots = (byParent[nil] ?? []).sorted(by: snapshotDiffOrderLess)
        if roots.isEmpty { return [] }

        var result: [[SnapshotDiff]] = [roots]
        var currentLevel = roots

        while true {
            var nextLevel: [SnapshotDiff] = []
            for parentDiff in currentLevel {
                let children = (byParent[parentDiff.id] ?? []).sorted(by: snapshotDiffOrderLess)
                nextLevel.append(contentsOf: children)
            }
            if nextLevel.isEmpty { break }
            result.append(nextLevel)
            currentLevel = nextLevel
        }

        return result
    }

    @ViewBuilder
    var bottomHistoryBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    if let currentSnap = scenario.sortedSnapshots[safe: Int(historyIndex)], let name = currentSnap.name {
                        if editingSnapshotID == currentSnap.id {
                            TextField("이름 변경", text: $editedSnapshotName, onCommit: { commitSnapshotNameEdit(snapshotID: currentSnap.id) })
                                .textFieldStyle(.plain)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.orange)
                        } else {
                            Button(action: { beginSnapshotNameEdit(snapshot: currentSnap) }) {
                                Text(name)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.orange)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Text("이름 없는 스냅샷")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath").foregroundColor(.accentColor)
                        Text("타임라인 히스토리").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                    }
                    if let currentSnap = scenario.sortedSnapshots[safe: Int(historyIndex)] {
                        Text("\(currentSnap.timestamp, style: .date) \(currentSnap.timestamp, style: .time)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 200, alignment: .leading)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        let snapshots = scenario.sortedSnapshots
                        let count = snapshots.count
                        if count > 1 {
                            ForEach(Array(snapshots.enumerated()), id: \.offset) { idx, snap in
                                if let name = snap.name {
                                    let xPos = (CGFloat(idx) / CGFloat(count - 1)) * geometry.size.width
                                    VStack(spacing: 2) {
                                        Image(systemName: "flag.fill")
                                            .font(.system(size: 8))
                                        Text(name)
                                            .font(.system(size: 7, weight: .medium))
                                            .lineLimit(1)
                                            .frame(width: 60)
                                    }
                                    .foregroundColor(.orange)
                                    .position(x: xPos, y: 4)
                                }
                            }
                        }

                        let maxIndex = Double(max(0, scenario.sortedSnapshots.count - 1))
                        if maxIndex > 0 {
                            Slider(value: Binding(
                                get: {
                                    let safe = historyIndex.isFinite ? historyIndex : 0
                                    return min(max(0, safe), maxIndex)
                                },
                                set: { historyIndex = min(max(0, $0), maxIndex) }
                            ), in: 0...maxIndex, step: 1)
                            .controlSize(.small)
                            .focusable(false)
                            .padding(.top, 14)
                        } else {
                            Capsule()
                                .fill(Color.secondary.opacity(0.25))
                                .frame(height: 4)
                                .padding(.top, 24)
                        }
                    }
                }
                .frame(height: 44)

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Button(action: jumpToPreviousNamedSnapshot) { Label("이전 이름", systemImage: "chevron.left") }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(previousNamedSnapshotIndex() == nil)

                        Button(action: jumpToNextNamedSnapshot) { Label("다음 이름", systemImage: "chevron.right") }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(nextNamedSnapshotIndex() == nil)
                    }
                    HStack(spacing: 8) {
                        Button(action: restoreToSelectedPoint) { Label("이 시점으로 복구", systemImage: "arrow.uturn.backward") }
                            .buttonStyle(.borderedProminent).controlSize(.regular)
                            .disabled(!isPreviewingHistory).opacity(!isPreviewingHistory ? 0.5 : 1.0)

                        Button("미리보기 종료") { exitPreviewMode(); withAnimation(quickEaseAnimation) { showHistoryBar = false } }
                            .buttonStyle(.bordered).controlSize(.regular)
                    }
                }
                .frame(width: 220, alignment: .trailing)
            }
            .padding(.horizontal, 24).padding(.vertical, 12).background(.ultraThinMaterial)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: HistoryBarHeightPreferenceKey.self,
                        value: proxy.size.height
                    )
                }
            )
        }
    }

    var namedCheckpointSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("이름 있는 분기점 만들기")
                .font(.system(size: 18, weight: .bold))
            TextField("분기점 이름 (예: 주인공 성격 수정)", text: $newCheckpointName)
                .textFieldStyle(.roundedBorder)

            Text("노트 (선택)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            TextEditor(text: $newCheckpointNote)
                .font(.custom("SansMonoCJKFinalDraft", size: fontSize))
                .lineSpacing(CGFloat(mainCardLineSpacingValue))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 120, maxHeight: 180)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(appearance == "light" ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(appearance == "light" ? Color.black.opacity(0.10) : Color.white.opacity(0.12), lineWidth: 1)
                )

            HStack(spacing: 10) {
                Spacer()
                Button("취소", role: .cancel) {
                    showCheckpointDialog = false
                }
                Button("저장") {
                    saveNamedCheckpointFromDialog()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(normalizedSnapshotName(newCheckpointName) == nil)
            }
        }
        .padding(20)
        .frame(width: 500)
    }

    struct NamedSnapshotManagerItem: Identifiable {
        let snapshotID: UUID
        let snapshotIndex: Int
        let name: String
        let timestamp: Date
        let noteCardID: UUID?
        var id: UUID { snapshotID }
    }

    @ViewBuilder
    var namedSnapshotManagerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            namedSnapshotManagerSearchBar
            namedSnapshotManagerHeader
            GeometryReader { splitProxy in
                let topHeight = max(160, splitProxy.size.height * 0.4)
                let bottomHeight = max(180, splitProxy.size.height - topHeight)
                VStack(alignment: .leading, spacing: 0) {
                    namedSnapshotManagerList
                        .frame(height: topHeight)
                    Divider()
                        .background(appearance == "light" ? Color.black.opacity(0.1) : Color.white.opacity(0.1))
                    namedSnapshotManagerEditorSection
                        .frame(height: bottomHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    var namedSnapshotManagerSearchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(appearance == "light" ? .black.opacity(0.6) : .white.opacity(0.8))
            TextField(
                "",
                text: $snapshotNoteSearchText,
                prompt: Text("네임드 스냅샷/노트 검색...")
                    .foregroundColor(appearance == "light" ? .black.opacity(0.4) : .white.opacity(0.7))
            )
            .textFieldStyle(.plain)
            .focused($isNamedSnapshotSearchFocused)
            .foregroundStyle(appearance == "light" ? .black : .white)
            if !snapshotNoteSearchText.isEmpty {
                Button {
                    snapshotNoteSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(appearance == "light" ? Color.black.opacity(0.05) : Color.white.opacity(0.08))
        .cornerRadius(8)
        .padding([.horizontal, .top], 12)
    }

    var namedSnapshotManagerHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("네임드 스냅샷 노트")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(appearance == "light" ? .black.opacity(0.5) : .white.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
            Divider()
                .background(appearance == "light" ? Color.black.opacity(0.1) : Color.white.opacity(0.1))
        }
    }

    var namedSnapshotManagerList: some View {
        namedSnapshotManagerListContainer(items: filteredNamedSnapshotManagerItems())
    }

    func namedSnapshotManagerListContainer(items: [NamedSnapshotManagerItem]) -> some View {
        ScrollView {
            namedSnapshotManagerListContent(items: items)
        }
    }

    @ViewBuilder
    func namedSnapshotManagerListContent(items: [NamedSnapshotManagerItem]) -> some View {
        LazyVStack(spacing: 8) {
            ForEach(items) { item in
                namedSnapshotManagerRow(item)
            }
            if items.isEmpty {
                namedSnapshotManagerEmptyState
            }
        }
        .padding(12)
    }

    var namedSnapshotManagerEmptyState: some View {
        ContentUnavailableView(
            snapshotNoteSearchText.isEmpty ? "네임드 스냅샷이 없습니다" : "검색 결과 없음",
            systemImage: snapshotNoteSearchText.isEmpty ? "flag" : "magnifyingglass"
        )
        .foregroundStyle(appearance == "light" ? .black.opacity(0.3) : .white.opacity(0.5))
        .scaleEffect(0.7)
        .padding(.top, 30)
    }

    func namedSnapshotManagerRow(_ item: NamedSnapshotManagerItem) -> some View {
        let isCurrent = item.snapshotIndex == Int(historyIndex)
        let preview = namedSnapshotNoteBodyPreview(item: item)

        return Button {
            selectNamedSnapshotManagerItem(item)
        } label: {
            namedSnapshotManagerRowLabel(item: item, preview: preview, isCurrent: isCurrent)
        }
        .buttonStyle(.plain)
    }

    func namedSnapshotManagerRowLabel(
        item: NamedSnapshotManagerItem,
        preview: String,
        isCurrent: Bool
    ) -> some View {
        let titleColor: Color = appearance == "light" ? .black : .white
        let previewColor: Color = appearance == "light" ? .black.opacity(0.7) : .white.opacity(0.75)
        let fillColor: Color = isCurrent
            ? Color.accentColor.opacity(appearance == "light" ? 0.18 : 0.28)
            : (appearance == "light" ? Color.black.opacity(0.04) : Color.white.opacity(0.06))
        let strokeColor: Color = isCurrent
            ? Color.accentColor.opacity(0.65)
            : (appearance == "light" ? Color.black.opacity(0.08) : Color.white.opacity(0.10))

        let timestampText = namedSnapshotTimestampText(item.timestamp)

        return VStack(alignment: .leading, spacing: 6) {
            Text(item.name)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .foregroundStyle(titleColor)
            Text(timestampText)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            namedSnapshotManagerPreviewText(preview: preview, color: previewColor)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(namedSnapshotManagerRowFill(fillColor: fillColor))
        .overlay(namedSnapshotManagerRowStroke(strokeColor: strokeColor))
    }

    @ViewBuilder
    func namedSnapshotManagerPreviewText(preview: String, color: Color) -> some View {
        if !preview.isEmpty {
            Text(preview)
                .font(.system(size: 11))
                .lineLimit(2)
                .foregroundStyle(color)
        }
    }

    func namedSnapshotTimestampText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    func namedSnapshotManagerRowFill(fillColor: Color) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(fillColor)
    }

    func namedSnapshotManagerRowStroke(strokeColor: Color) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(strokeColor, lineWidth: 1)
    }

    @ViewBuilder
    var namedSnapshotManagerEditorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let noteCardID = historySelectedNamedSnapshotNoteCardID,
               let binding = namedSnapshotNoteBinding(for: noteCardID) {
                namedSnapshotManagerLinkedNoteEditor(
                    noteCardID: noteCardID,
                    binding: binding
                )
            } else {
                ContentUnavailableView(
                    "이 시점은 네임드 스냅샷이 아닙니다",
                    systemImage: "note.text"
                )
                .foregroundStyle(appearance == "light" ? .black.opacity(0.35) : .white.opacity(0.55))
                .scaleEffect(0.8)
                .frame(maxWidth: .infinity, minHeight: 140)
            }
        }
    }

    func namedSnapshotManagerLinkedNoteEditor(
        noteCardID: UUID,
        binding: Binding<String>
    ) -> some View {
        let editorFillColor: Color = appearance == "light" ? Color.black.opacity(0.04) : Color.white.opacity(0.08)
        let editorStrokeColor: Color = appearance == "light" ? Color.black.opacity(0.10) : Color.white.opacity(0.12)
        let editorTextColor: Color = appearance == "light" ? .black : .white

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("연결 노트")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(isNamedSnapshotNoteEditing ? "완료" : "편집") {
                    if isNamedSnapshotNoteEditing {
                        finishNamedSnapshotNoteEditing(restoreMainFocus: true)
                    } else {
                        beginNamedSnapshotNoteEditing()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            Group {
                if isNamedSnapshotNoteEditing {
                    TextEditor(text: binding)
                        .id("named-note-editor-\(noteCardID.uuidString)")
                        .font(.custom("SansMonoCJKFinalDraft", size: fontSize))
                        .lineSpacing(CGFloat(mainCardLineSpacingValue))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .foregroundStyle(editorTextColor)
                        .focused($isNamedSnapshotNoteEditorFocused)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(verbatim: binding.wrappedValue.isEmpty ? " " : binding.wrappedValue)
                            .font(.custom("SansMonoCJKFinalDraft", size: fontSize))
                            .lineSpacing(CGFloat(mainCardLineSpacingValue))
                            .foregroundStyle(editorTextColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .id("named-note-readonly-\(noteCardID.uuidString)")
                    .contentShape(Rectangle())
                    .onTapGesture {
                        beginNamedSnapshotNoteEditing()
                    }
                }
            }
            .frame(minHeight: 190, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(editorFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(editorStrokeColor, lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .onChange(of: noteCardID) { _, _ in
            finishNamedSnapshotNoteEditing(restoreMainFocus: false)
        }
    }

    func beginNamedSnapshotNoteEditing() {
        isNamedSnapshotNoteEditing = true
        DispatchQueue.main.async {
            isNamedSnapshotNoteEditorFocused = true
        }
    }

    func finishNamedSnapshotNoteEditing(restoreMainFocus: Bool) {
        isNamedSnapshotNoteEditing = false
        isNamedSnapshotNoteEditorFocused = false
        if restoreMainFocus {
            isMainViewFocused = true
        }
    }


    @ViewBuilder
    var timelineView: some View {
        VStack(alignment: .leading, spacing: 0) {
            aiTimelineActionPanel

            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(appearance == "light" ? .black.opacity(0.6) : .white.opacity(0.8))
                TextField("", text: $searchText, prompt: Text("전체 카드 검색...").foregroundColor(appearance == "light" ? .black.opacity(0.4) : .white.opacity(0.7)))
                    .textFieldStyle(.plain).focused($isSearchFocused).foregroundStyle(appearance == "light" ? .black : .white).onExitCommand { closeSearch() }
                if !searchText.isEmpty { Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.5)) }.buttonStyle(.plain) }
            }
            .padding(10).background(appearance == "light" ? Color.black.opacity(0.05) : Color.white.opacity(0.08)).cornerRadius(8).padding([.horizontal, .top], 12)

            HStack {
                Spacer()
                Menu {
                    Button("클립보드에 복사") { exportToClipboard() }
                    Button("텍스트 파일로 저장...") { exportToFile() }
                    Divider()
                    Button("중앙정렬식 PDF 저장...") { exportToCenteredPDF() }
                    Button("한국식 PDF 저장...") { exportToKoreanPDF() }
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("출력")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.saturation(0.7))
                    .cornerRadius(6)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 100)
            }
            .padding([.horizontal, .top], 12)

            Text(searchText.isEmpty ? "전체 카드 (최신순)" : "검색 결과").font(.system(size: 12, weight: .bold)).foregroundStyle(appearance == "light" ? .black.opacity(0.5) : .white.opacity(0.7)).padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
            Divider().background(appearance == "light" ? Color.black.opacity(0.1) : Color.white.opacity(0.1))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        let allCards = scenario.cards.sorted { $0.createdAt > $1.createdAt }
                        let filteredTimeline = allCards.filter { matchesSearch($0) }
                        ForEach(filteredTimeline) { card in timelineRow(card) }
                        if filteredTimeline.isEmpty {
                            ContentUnavailableView(searchText.isEmpty ? "카드가 없습니다" : "'\(searchText)' 검색 결과 없음", systemImage: searchText.isEmpty ? "tray" : "magnifyingglass").foregroundStyle(appearance == "light" ? .black.opacity(0.3) : .white.opacity(0.5)).scaleEffect(0.7).padding(.top, 40)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: activeCardID) { _, newID in if let id = newID { withAnimation(quickEaseAnimation) { proxy.scrollTo("timeline-\(id)", anchor: .center) } } }
            }
        }
    }

    func namedSnapshotIndex(forNoteCardID noteCardID: UUID) -> Int? {
        scenario.sortedSnapshots.firstIndex { $0.noteCardID == noteCardID }
    }

    func isNamedSnapshotNoteCard(_ card: SceneCard) -> Bool {
        guard card.category == "네임드 스냅샷 노트" else { return false }
        return namedSnapshotIndex(forNoteCardID: card.id) != nil
    }

    @discardableResult
    func openHistoryFromNamedSnapshotNoteCard(_ card: SceneCard) -> Bool {
        guard let snapshotIndex = namedSnapshotIndex(forNoteCardID: card.id) else { return false }
        let previousIndex = Int(historyIndex)
        isNamedSnapshotNoteEditing = false
        isNamedSnapshotNoteEditorFocused = false
        isNamedSnapshotSearchFocused = false
        withAnimation(quickEaseAnimation) {
            showTimeline = false
            showHistoryBar = true
            historyIndex = Double(snapshotIndex)
        }
        historySelectedNamedSnapshotNoteCardID = card.id
        if previousIndex == snapshotIndex {
            enterPreviewMode(at: snapshotIndex)
        }
        isMainViewFocused = true
        return true
    }

    func filteredNamedSnapshotManagerItems() -> [NamedSnapshotManagerItem] {
        let items = namedSnapshotManagerItems()
        let tokens = searchTokens(from: snapshotNoteSearchText)
        if tokens.isEmpty { return items }
        return items.filter { item in
            let noteText = item.noteCardID
                .flatMap { findCard(by: $0)?.content } ?? ""
            let haystack = normalizedSearchText(item.name + " " + noteText)
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    func namedSnapshotManagerItems() -> [NamedSnapshotManagerItem] {
        scenario.sortedSnapshots
            .enumerated()
            .compactMap { index, snapshot in
                guard let name = normalizedSnapshotName(snapshot.name) else { return nil }
                return NamedSnapshotManagerItem(
                    snapshotID: snapshot.id,
                    snapshotIndex: index,
                    name: name,
                    timestamp: snapshot.timestamp,
                    noteCardID: snapshot.noteCardID
                )
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func namedSnapshotNoteBodyPreview(item: NamedSnapshotManagerItem) -> String {
        guard let noteCardID = item.noteCardID, let card = findCard(by: noteCardID) else { return "" }
        let body = card.content
            .components(separatedBy: "\n")
            .dropFirst()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body
    }

    func selectNamedSnapshotManagerItem(_ item: NamedSnapshotManagerItem) {
        let previousIndex = Int(historyIndex)
        isNamedSnapshotNoteEditing = false
        isNamedSnapshotNoteEditorFocused = false
        historyIndex = Double(item.snapshotIndex)
        if previousIndex == item.snapshotIndex {
            enterPreviewMode(at: item.snapshotIndex)
        }
    }

    func namedSnapshotNoteBinding(for noteCardID: UUID) -> Binding<String>? {
        guard findCard(by: noteCardID) != nil else { return nil }
        return Binding(
            get: { findCard(by: noteCardID)?.content ?? "" },
            set: { newValue in
                guard let card = findCard(by: noteCardID) else { return }
                let syncedValue: String = {
                    if let snapshot = scenario.snapshots.first(where: { $0.noteCardID == noteCardID }),
                       let title = normalizedSnapshotName(snapshot.name) {
                        return syncedSnapshotNoteContent(newValue, title: title)
                    }
                    return newValue
                }()
                if card.content != syncedValue {
                    card.content = syncedValue
                    store.saveAll()
                }
            }
        )
    }

    func saveNamedCheckpointFromDialog() {
        guard let name = normalizedSnapshotName(newCheckpointName) else { return }
        let note = newCheckpointNote.trimmingCharacters(in: .whitespacesAndNewlines)
        takeSnapshot(
            force: true,
            name: name,
            initialNamedNote: note.isEmpty ? nil : note
        )
        showCheckpointDialog = false
        newCheckpointName = ""
        newCheckpointNote = ""
    }

    func normalizedSnapshotName(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func snapshotNoteContent(title: String, body: String?) -> String {
        let trimmedBody = (body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return title }
        return title + "\n\n" + trimmedBody
    }

    func syncedSnapshotNoteContent(_ content: String, title: String) -> String {
        guard !content.isEmpty else { return title }
        guard let newlineIndex = content.firstIndex(of: "\n") else { return title }
        let bodyStart = content.index(after: newlineIndex)
        let tail = content[bodyStart...]
        return title + "\n" + tail
    }

    func updateHistoryKeyMonitor() {
        if showHistoryBar {
            startHistoryKeyMonitor()
        } else {
            stopHistoryKeyMonitor()
        }
    }

    @discardableResult
    func handleHistoryEscape() -> Bool {
        guard showHistoryBar else { return false }

        if isNamedSnapshotSearchFocused {
            isNamedSnapshotSearchFocused = false
            NSApp.keyWindow?.makeFirstResponder(nil)
            isMainViewFocused = true
            return true
        }

        if isNamedSnapshotNoteEditing || isNamedSnapshotNoteEditorFocused {
            finishNamedSnapshotNoteEditing(restoreMainFocus: true)
            NSApp.keyWindow?.makeFirstResponder(nil)
            return true
        }

        if isSearchFocused {
            isSearchFocused = false
            NSApp.keyWindow?.makeFirstResponder(nil)
            isMainViewFocused = true
            return true
        }

        exitPreviewMode()
        withAnimation(quickEaseAnimation) { showHistoryBar = false }
        return true
    }

    func startHistoryKeyMonitor() {
        if historyKeyMonitor != nil { return }
        historyKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if !acceptsKeyboardInput { return event }
            if !showHistoryBar { return event }
            let keyCode = event.keyCode
            if keyCode == 53 { // esc
                DispatchQueue.main.async { _ = handleHistoryEscape() }
                return nil
            }
            if isNamedSnapshotSearchFocused {
                return event
            }
            if isNamedSnapshotNoteEditing && isNamedSnapshotNoteEditorFocused {
                return event
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isCommandOnly =
                flags.contains(.command) &&
                !flags.contains(.option) &&
                !flags.contains(.control) &&
                !flags.contains(.shift)
            let normalized = (event.charactersIgnoringModifiers ?? "").lowercased()
            let isCopyShortcut = normalized == "c" || normalized == "ㅊ" || keyCode == 8
            if isPreviewingHistory && isCommandOnly && isCopyShortcut {
                copyHistoryPreviewCardsToClipboard()
                return nil
            }
            if keyCode == 123 || keyCode == 124 { // left/right arrows
                DispatchQueue.main.async {
                    if event.modifierFlags.contains(.command) {
                        if keyCode == 123 { jumpToPreviousNamedSnapshot() }
                        else { jumpToNextNamedSnapshot() }
                    } else {
                        stepHistoryIndex(by: keyCode == 123 ? -1 : 1)
                    }
                }
                return nil
            }
            return event
        }
    }

    func stopHistoryKeyMonitor() {
        if let monitor = historyKeyMonitor {
            NSEvent.removeMonitor(monitor)
            historyKeyMonitor = nil
        }
    }

    func beginSnapshotNameEdit(snapshot: HistorySnapshot) {
        editingSnapshotID = snapshot.id
        editedSnapshotName = snapshot.name ?? ""
    }

    func commitSnapshotNameEdit(snapshotID: UUID) {
        let trimmed = editedSnapshotName.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = trimmed.isEmpty ? nil : trimmed
        var didMutate = false
        if let idx = scenario.snapshots.firstIndex(where: { $0.id == snapshotID }) {
            scenario.snapshots[idx].name = newName
            didMutate = true
            if newName != nil {
                if ensureNamedSnapshotNoteCard(snapshotID: snapshotID, initialBody: nil, focusEditor: false) != nil {
                    didMutate = true
                }
            }
        }
        if didMutate {
            store.saveAll()
        }
        if showHistoryBar {
            syncNamedSnapshotNoteForCurrentSelection(focusEditor: false)
        }
        editingSnapshotID = nil
        editedSnapshotName = ""
    }

    func takeSnapshot(
        force: Bool = false,
        name: String? = nil,
        initialNamedNote: String? = nil,
        attachNamedNote: Bool = true
    ) {
        let normalizedName = normalizedSnapshotName(name)
        if !force && normalizedName == nil {
            scenario.changeCountSinceLastSnapshot += 1
            if scenario.changeCountSinceLastSnapshot < 5 { return }
        }
        if let name = normalizedName {
            let noteCardID: UUID? = attachNamedNote
                ? createNamedSnapshotNoteCard(title: name, initialBody: initialNamedNote)?.id
                : nil
            guard let namedSnapshot = buildHistorySnapshot(name: name, forceFull: true) else { return }
            namedSnapshot.noteCardID = noteCardID
            scenario.snapshots.append(namedSnapshot)
            // 현재 상태를 "최신"으로 남기기 위한 즉시 스냅샷
            if let currentSnapshot = buildHistorySnapshot(name: nil, allowEmptyDelta: true) {
                scenario.snapshots.append(currentSnapshot)
            }
            scenario.changeCountSinceLastSnapshot = 0
            applyHistoryRetentionPolicyIfNeeded()
            store.saveAll()
            DispatchQueue.main.async {
                self.historyIndex = Double(max(0, self.scenario.sortedSnapshots.count - 1))
                if self.showHistoryBar {
                    self.syncNamedSnapshotNoteForCurrentSelection(focusEditor: false)
                }
            }
            return
        }
        guard let newSnapshot = buildHistorySnapshot(name: nil) else { return }
        scenario.snapshots.append(newSnapshot)
        scenario.changeCountSinceLastSnapshot = 0
        applyHistoryRetentionPolicyIfNeeded()
        store.saveAll()
        DispatchQueue.main.async { self.historyIndex = Double(max(0, self.scenario.sortedSnapshots.count - 1)) }
    }

    @discardableResult
    func createNamedSnapshotNoteCard(title: String, initialBody: String?) -> SceneCard? {
        guard let normalizedTitle = normalizedSnapshotName(title) else { return nil }
        let noteCard = SceneCard(
            content: snapshotNoteContent(title: normalizedTitle, body: initialBody),
            orderIndex: 0,
            createdAt: Date(),
            parent: nil,
            scenario: scenario,
            category: "네임드 스냅샷 노트",
            isFloating: true
        )
        scenario.cards.append(noteCard)
        scenario.bumpCardsVersion()
        return noteCard
    }

    func syncNamedSnapshotNoteForCurrentSelection(focusEditor: Bool) {
        guard let currentSnapshot = scenario.sortedSnapshots[safe: Int(historyIndex)] else {
            historySelectedNamedSnapshotNoteCardID = nil
            isNamedSnapshotNoteEditorFocused = false
            return
        }
        guard normalizedSnapshotName(currentSnapshot.name) != nil else {
            historySelectedNamedSnapshotNoteCardID = nil
            isNamedSnapshotNoteEditorFocused = false
            return
        }
        _ = ensureNamedSnapshotNoteCard(
            snapshotID: currentSnapshot.id,
            initialBody: nil,
            focusEditor: focusEditor
        )
    }

    @discardableResult
    func ensureNamedSnapshotNoteCard(
        snapshotID: UUID,
        initialBody: String?,
        focusEditor: Bool
    ) -> SceneCard? {
        guard let snapshotIndex = scenario.snapshots.firstIndex(where: { $0.id == snapshotID }) else { return nil }
        guard let title = normalizedSnapshotName(scenario.snapshots[snapshotIndex].name) else { return nil }

        var didMutate = false
        let noteCard: SceneCard? = {
            if let noteCardID = scenario.snapshots[snapshotIndex].noteCardID,
               let existing = findCard(by: noteCardID) {
                return existing
            }
            let created = createNamedSnapshotNoteCard(title: title, initialBody: initialBody)
            if let createdID = created?.id {
                scenario.snapshots[snapshotIndex].noteCardID = createdID
                didMutate = true
            }
            return created
        }()

        guard let noteCard else { return nil }
        let synced = syncedSnapshotNoteContent(noteCard.content, title: title)
        if noteCard.content != synced {
            noteCard.content = synced
            didMutate = true
        }

        historySelectedNamedSnapshotNoteCardID = noteCard.id
        if focusEditor {
            DispatchQueue.main.async {
                self.isNamedSnapshotNoteEditorFocused = true
            }
        }
        if didMutate {
            store.saveAll()
        }
        return noteCard
    }

    struct HistoryPromotionDecision {
        let isPromoted: Bool
        let reason: String?
    }

    enum HistoryRetentionTier: String {
        case recentHour
        case recentDay
        case recentWeek
        case recentMonth
        case archive
    }

    func buildHistorySnapshot(
        name: String?,
        forceFull: Bool = false,
        allowEmptyDelta: Bool = false
    ) -> HistorySnapshot? {
        let currentCardSnapshots = scenario.cards.map { CardSnapshot(from: $0) }
        let currentMap = Dictionary(uniqueKeysWithValues: currentCardSnapshots.map { ($0.cardID, $0) })
        let timestamp = nextSnapshotTimestamp()
        let previousMap = resolvedCardSnapshotMap(
            at: scenario.snapshots.count - 1,
            in: scenario.snapshots
        )
        let shouldBuildFull = forceFull || shouldInsertFullSnapshotCheckpoint(in: scenario.snapshots)
        if shouldBuildFull {
            let deltaFromPrevious = buildDeltaPayload(from: previousMap ?? [:], to: currentMap)
            let promotion = evaluateHistoryPromotion(
                name: name,
                timestamp: timestamp,
                previousMap: previousMap,
                currentMap: currentMap,
                changedSnapshots: deltaFromPrevious.changed,
                deletedCardIDs: deltaFromPrevious.deleted
            )
            return HistorySnapshot(
                timestamp: timestamp,
                name: name,
                scenarioID: scenario.id,
                cardSnapshots: currentCardSnapshots,
                isDelta: false,
                deletedCardIDs: [],
                isPromoted: promotion.isPromoted,
                promotionReason: promotion.reason
            )
        }

        guard let previousMap else {
            let promotion = evaluateHistoryPromotion(
                name: name,
                timestamp: timestamp,
                previousMap: nil,
                currentMap: currentMap,
                changedSnapshots: currentCardSnapshots,
                deletedCardIDs: []
            )
            return HistorySnapshot(
                timestamp: timestamp,
                name: name,
                scenarioID: scenario.id,
                cardSnapshots: currentCardSnapshots,
                isDelta: false,
                deletedCardIDs: [],
                isPromoted: promotion.isPromoted,
                promotionReason: promotion.reason
            )
        }

        let deltaPayload = buildDeltaPayload(from: previousMap, to: currentMap)
        let changedSnapshots = deltaPayload.changed
        let deletedCardIDs = deltaPayload.deleted

        if !allowEmptyDelta && changedSnapshots.isEmpty && deletedCardIDs.isEmpty {
            return nil
        }
        let promotion = evaluateHistoryPromotion(
            name: name,
            timestamp: timestamp,
            previousMap: previousMap,
            currentMap: currentMap,
            changedSnapshots: changedSnapshots,
            deletedCardIDs: deletedCardIDs
        )

        return HistorySnapshot(
            timestamp: timestamp,
            name: name,
            scenarioID: scenario.id,
            cardSnapshots: changedSnapshots,
            isDelta: true,
            deletedCardIDs: deletedCardIDs,
            isPromoted: promotion.isPromoted,
            promotionReason: promotion.reason
        )
    }

    func evaluateHistoryPromotion(
        name: String?,
        timestamp: Date,
        previousMap: [UUID: CardSnapshot]?,
        currentMap: [UUID: CardSnapshot],
        changedSnapshots: [CardSnapshot],
        deletedCardIDs: [UUID]
    ) -> HistoryPromotionDecision {
        if let name, !name.isEmpty {
            return HistoryPromotionDecision(isPromoted: true, reason: "named")
        }
        guard let previousMap else {
            return HistoryPromotionDecision(isPromoted: true, reason: "initial")
        }

        let addedCardIDs = currentMap.keys.filter { previousMap[$0] == nil }
        if !addedCardIDs.isEmpty || !deletedCardIDs.isEmpty {
            return HistoryPromotionDecision(isPromoted: true, reason: "structure-add-delete")
        }

        for changed in changedSnapshots {
            guard let previous = previousMap[changed.cardID] else { continue }
            if previous.parentID != changed.parentID ||
                previous.orderIndex != changed.orderIndex ||
                previous.category != changed.category ||
                previous.isFloating != changed.isFloating ||
                previous.isArchived != changed.isArchived ||
                previous.cloneGroupID != changed.cloneGroupID {
                return HistoryPromotionDecision(isPromoted: true, reason: "structure-move")
            }
        }

        let changedCardCount = changedSnapshots.count + deletedCardIDs.count
        let editScore = historyEditScore(
            previousMap: previousMap,
            changedSnapshots: changedSnapshots,
            deletedCardIDs: deletedCardIDs
        )
        if changedCardCount >= historyPromotionChangedCardsThreshold ||
            editScore >= historyPromotionLargeEditScoreThreshold {
            return HistoryPromotionDecision(isPromoted: true, reason: "large-edit")
        }

        if let lastTimestamp = scenario.snapshots.last?.timestamp,
           timestamp.timeIntervalSince(lastTimestamp) >= historyPromotionSessionGapThreshold {
            return HistoryPromotionDecision(isPromoted: true, reason: "session-gap")
        }

        return HistoryPromotionDecision(isPromoted: false, reason: nil)
    }

    func historyEditScore(
        previousMap: [UUID: CardSnapshot],
        changedSnapshots: [CardSnapshot],
        deletedCardIDs: [UUID]
    ) -> Int {
        var score = 0
        for changed in changedSnapshots {
            if let previous = previousMap[changed.cardID], previous.content != changed.content {
                score += max(previous.content.count, changed.content.count)
            } else if previousMap[changed.cardID] == nil {
                score += changed.content.count
            }
        }
        for deletedID in deletedCardIDs {
            if let deleted = previousMap[deletedID] {
                score += deleted.content.count
            }
        }
        return score
    }

    func applyHistoryRetentionPolicyIfNeeded(force: Bool = false) {
        let snapshots = scenario.sortedSnapshots
        let count = snapshots.count
        if !force {
            guard count >= historyRetentionMinimumCount else { return }
            let progressed = count - historyRetentionLastAppliedCount
            guard progressed >= historyRetentionApplyStride else { return }
        }

        let compacted = compactHistorySnapshots(snapshots, now: Date())
        historyRetentionLastAppliedCount = compacted.count
        guard compacted.count < count else { return }

        scenario.snapshots = compacted
        if isPreviewingHistory {
            let clamped = min(max(Int(historyIndex), 0), max(0, compacted.count - 1))
            historyIndex = Double(clamped)
            enterPreviewMode(at: clamped)
        } else {
            historyIndex = Double(max(0, compacted.count - 1))
        }
    }

    func compactHistorySnapshots(_ snapshots: [HistorySnapshot], now: Date) -> [HistorySnapshot] {
        guard snapshots.count > historyRetentionMinimumCount else { return snapshots }
        let keptIndices = retainedHistoryIndices(from: snapshots, now: now)
        guard keptIndices.count < snapshots.count else { return snapshots }
        return rebuildHistorySnapshots(from: snapshots, keeping: keptIndices)
    }

    func retainedHistoryIndices(from snapshots: [HistorySnapshot], now: Date) -> [Int] {
        guard !snapshots.isEmpty else { return [] }
        var keep = Set<Int>()
        keep.insert(0)
        keep.insert(snapshots.count - 1)

        var bucketLatest: [String: Int] = [:]
        for index in snapshots.indices {
            let snapshot = snapshots[index]
            if isSnapshotPromoted(snapshot) {
                keep.insert(index)
                continue
            }
            let age = max(0, now.timeIntervalSince(snapshot.timestamp))
            let rule = historyRetentionRule(forAge: age)
            let bucket = Int(floor(snapshot.timestamp.timeIntervalSince1970 / rule.interval))
            let key = "\(rule.tier.rawValue):\(bucket)"
            if let existing = bucketLatest[key] {
                if snapshots[existing].timestamp <= snapshot.timestamp {
                    bucketLatest[key] = index
                }
            } else {
                bucketLatest[key] = index
            }
        }
        for index in bucketLatest.values {
            keep.insert(index)
        }
        return keep.sorted()
    }

    func historyRetentionRule(forAge age: TimeInterval) -> (tier: HistoryRetentionTier, interval: TimeInterval) {
        ScenarioHistoryEngine.retentionRule(forAge: age)
    }

    func rebuildHistorySnapshots(from snapshots: [HistorySnapshot], keeping keptIndices: [Int]) -> [HistorySnapshot] {
        guard !keptIndices.isEmpty else { return snapshots }
        let keepSet = Set(keptIndices)
        let statesByIndex = historyStatesByIndex(from: snapshots, keepSet: keepSet)

        var rebuilt: [HistorySnapshot] = []
        var previousState: [UUID: CardSnapshot]? = nil
        var trailingDeltaCount = 0
        let latestIndex = snapshots.count - 1

        for index in keptIndices {
            guard let currentState = statesByIndex[index] else { continue }
            let original = snapshots[index]
            let promoted = isSnapshotPromoted(original)
            let shouldForceFull = shouldForceFullHistorySnapshot(
                rebuiltIsEmpty: rebuilt.isEmpty,
                index: index,
                latestIndex: latestIndex,
                promoted: promoted,
                isDeltaSnapshot: original.isDelta,
                trailingDeltaCount: trailingDeltaCount
            )

            if shouldForceFull || previousState == nil {
                rebuilt.append(fullHistorySnapshot(from: original, state: currentState, promoted: promoted))
                previousState = currentState
                trailingDeltaCount = 0
                continue
            }

            let delta = buildDeltaPayload(from: previousState ?? [:], to: currentState)
            if delta.changed.isEmpty && delta.deleted.isEmpty {
                if index == latestIndex || promoted {
                    rebuilt.append(fullHistorySnapshot(from: original, state: currentState, promoted: promoted))
                    previousState = currentState
                    trailingDeltaCount = 0
                }
                continue
            }

            rebuilt.append(deltaHistorySnapshot(from: original, delta: delta, promoted: promoted))
            previousState = currentState
            trailingDeltaCount += 1
        }

        if rebuilt.isEmpty,
           let fallback = fallbackLatestRebuiltHistorySnapshot(statesByIndex: statesByIndex, snapshots: snapshots, latestIndex: latestIndex) {
            return [fallback]
        }
        return rebuilt
    }

    func historyStatesByIndex(
        from snapshots: [HistorySnapshot],
        keepSet: Set<Int>
    ) -> [Int: [UUID: CardSnapshot]] {
        var statesByIndex: [Int: [UUID: CardSnapshot]] = [:]
        var rollingState: [UUID: CardSnapshot] = [:]
        for index in snapshots.indices {
            applySnapshotState(snapshots[index], to: &rollingState)
            if keepSet.contains(index) {
                statesByIndex[index] = rollingState
            }
        }
        return statesByIndex
    }

    func shouldForceFullHistorySnapshot(
        rebuiltIsEmpty: Bool,
        index: Int,
        latestIndex: Int,
        promoted: Bool,
        isDeltaSnapshot: Bool,
        trailingDeltaCount: Int
    ) -> Bool {
        rebuiltIsEmpty ||
        index == latestIndex ||
        promoted ||
        !isDeltaSnapshot ||
        trailingDeltaCount >= deltaSnapshotFullCheckpointInterval
    }

    func fullHistorySnapshot(
        from original: HistorySnapshot,
        state: [UUID: CardSnapshot],
        promoted: Bool
    ) -> HistorySnapshot {
        HistorySnapshot(
            id: original.id,
            timestamp: original.timestamp,
            name: original.name,
            scenarioID: original.scenarioID,
            cardSnapshots: sortedCardSnapshots(from: state),
            isDelta: false,
            deletedCardIDs: [],
            isPromoted: promoted,
            promotionReason: original.promotionReason,
            noteCardID: original.noteCardID
        )
    }

    func deltaHistorySnapshot(
        from original: HistorySnapshot,
        delta: (changed: [CardSnapshot], deleted: [UUID]),
        promoted: Bool
    ) -> HistorySnapshot {
        HistorySnapshot(
            id: original.id,
            timestamp: original.timestamp,
            name: original.name,
            scenarioID: original.scenarioID,
            cardSnapshots: delta.changed,
            isDelta: true,
            deletedCardIDs: delta.deleted,
            isPromoted: promoted,
            promotionReason: original.promotionReason,
            noteCardID: original.noteCardID
        )
    }

    func fallbackLatestRebuiltHistorySnapshot(
        statesByIndex: [Int: [UUID: CardSnapshot]],
        snapshots: [HistorySnapshot],
        latestIndex: Int
    ) -> HistorySnapshot? {
        guard let latestState = statesByIndex[latestIndex], let latest = snapshots.last else { return nil }
        return HistorySnapshot(
            id: latest.id,
            timestamp: latest.timestamp,
            name: latest.name,
            scenarioID: latest.scenarioID,
            cardSnapshots: sortedCardSnapshots(from: latestState),
            isDelta: false,
            deletedCardIDs: [],
            isPromoted: isSnapshotPromoted(latest),
            promotionReason: latest.promotionReason,
            noteCardID: latest.noteCardID
        )
    }

    func isSnapshotPromoted(_ snapshot: HistorySnapshot) -> Bool {
        snapshot.isPromoted || snapshot.name != nil
    }

    func sortedCardSnapshots(from state: [UUID: CardSnapshot]) -> [CardSnapshot] {
        ScenarioHistoryEngine.sortedCardSnapshots(from: state)
    }

    func buildDeltaPayload(
        from previousMap: [UUID: CardSnapshot],
        to currentMap: [UUID: CardSnapshot]
    ) -> (changed: [CardSnapshot], deleted: [UUID]) {
        ScenarioHistoryEngine.buildDeltaPayload(from: previousMap, to: currentMap)
    }

    func shouldInsertFullSnapshotCheckpoint(in snapshots: [HistorySnapshot]) -> Bool {
        ScenarioHistoryEngine.shouldInsertFullSnapshotCheckpoint(
            in: snapshots,
            checkpointInterval: deltaSnapshotFullCheckpointInterval
        )
    }

    func nextSnapshotTimestamp() -> Date {
        let now = Date()
        guard let last = scenario.snapshots.last?.timestamp else { return now }
        if now <= last {
            return last.addingTimeInterval(0.001)
        }
        return now
    }

    func applySnapshotState(_ snapshot: HistorySnapshot, to state: inout [UUID: CardSnapshot]) {
        ScenarioHistoryEngine.applySnapshotState(snapshot, to: &state)
    }

    func resolvedCardSnapshotMap(
        at index: Int,
        in snapshots: [HistorySnapshot]
    ) -> [UUID: CardSnapshot]? {
        guard index >= 0 && index < snapshots.count else { return nil }
        let prefix = snapshots[0...index]
        let startIndex = prefix.lastIndex(where: { !$0.isDelta }) ?? 0
        let startsWithDelta = snapshots[startIndex].isDelta
        var state: [UUID: CardSnapshot] = [:]
        if !startsWithDelta {
            let base = snapshots[startIndex]
            for cardSnapshot in base.cardSnapshots {
                state[cardSnapshot.cardID] = cardSnapshot
            }
            for deletedID in base.deletedCardIDs {
                state.removeValue(forKey: deletedID)
            }
        }
        let applyStart = startsWithDelta ? startIndex : startIndex + 1
        if applyStart <= index {
            for i in applyStart...index {
                applySnapshotState(snapshots[i], to: &state)
            }
        }
        return state
    }

    func resolvedCardSnapshots(
        at index: Int,
        in snapshots: [HistorySnapshot]
    ) -> [CardSnapshot]? {
        guard let resolved = resolvedCardSnapshotMap(at: index, in: snapshots) else { return nil }
        return sortedCardSnapshots(from: resolved)
    }

    func enterPreviewMode(at index: Int) {
        let snapshots = scenario.sortedSnapshots
        guard index >= 0 && index < snapshots.count else { return }
        let currentResolved = resolvedCardSnapshots(at: index, in: snapshots) ?? []
        let prevResolved = index > 0 ? (resolvedCardSnapshots(at: index - 1, in: snapshots) ?? []) : []
        // History preview should mirror the main canvas, which hides archived cards.
        let currentCardSnaps = currentResolved.filter { !$0.isArchived }
        let prevCardSnaps = prevResolved.filter { !$0.isArchived }
        var diffs: [SnapshotDiff] = []
        let prevByID = Dictionary(uniqueKeysWithValues: prevCardSnaps.map { ($0.cardID, $0) })
        let currentByID = Dictionary(uniqueKeysWithValues: currentCardSnaps.map { ($0.cardID, $0) })
        let prevIDs = Set(prevByID.keys); let currentIDs = Set(currentByID.keys)
        for snap in currentCardSnaps {
            if !prevIDs.contains(snap.cardID) {
                diffs.append(SnapshotDiff(id: snap.cardID, snapshot: snap, status: .added))
            } else if let prev = prevByID[snap.cardID] {
                diffs.append(
                    SnapshotDiff(
                        id: snap.cardID,
                        snapshot: snap,
                        status: prev == snap ? .none : .modified
                    )
                )
            }
        }
        for snap in prevCardSnaps { if !currentIDs.contains(snap.cardID) { diffs.append(SnapshotDiff(id: snap.cardID, snapshot: snap, status: .deleted)) } }
        historyPreviewSelectedCardIDs = []
        self.previewDiffs = diffs
        if index < snapshots.count - 1 { isPreviewingHistory = true } else { exitPreviewMode() }
    }

    func exitPreviewMode() {
        isPreviewingHistory = false
        previewDiffs = []
        historyPreviewSelectedCardIDs = []
        historyIndex = Double(max(0, scenario.sortedSnapshots.count - 1))
    }

    func restoreToSelectedPoint() {
        let snapshots = scenario.sortedSnapshots; let index = Int(historyIndex); guard index >= 0 && index < snapshots.count else { return }
        takeSnapshot(force: true, name: "복구 전 시점", attachNamedNote: false)
        let targetCardSnapshots = resolvedCardSnapshots(at: index, in: snapshots) ?? []
        scenario.cards = []
        var idMapping: [UUID: SceneCard] = [:]
        for snap in targetCardSnapshots {
            let newCard = SceneCard(
                id: snap.cardID,
                content: snap.content,
                orderIndex: snap.orderIndex,
                createdAt: Date(),
                parent: nil,
                scenario: scenario,
                category: snap.category,
                isFloating: snap.isFloating,
                isArchived: snap.isArchived,
                cloneGroupID: snap.cloneGroupID
            )
            scenario.cards.append(newCard)
            idMapping[snap.cardID] = newCard
        }
        for snap in targetCardSnapshots { if let parentID = snap.parentID, let card = idMapping[snap.cardID] { card.parent = idMapping[parentID] } }
        scenario.bumpCardsVersion()
        store.saveAll(); takeSnapshot(force: true); exitPreviewMode()
        withAnimation(quickEaseAnimation) { showHistoryBar = false }; if let first = scenario.rootCards.first { changeActiveCard(to: first) }
    }

    func previousNamedSnapshotIndex() -> Int? {
        let snapshots = scenario.sortedSnapshots
        let current = Int(historyIndex)
        guard current > 0 else { return nil }
        for idx in stride(from: current - 1, through: 0, by: -1) {
            if snapshots[idx].name != nil { return idx }
        }
        return nil
    }

    func nextNamedSnapshotIndex() -> Int? {
        let snapshots = scenario.sortedSnapshots
        let current = Int(historyIndex)
        guard current < snapshots.count - 1 else { return nil }
        for idx in (current + 1)..<snapshots.count {
            if snapshots[idx].name != nil { return idx }
        }
        return nil
    }

    func jumpToPreviousNamedSnapshot() {
        guard let idx = previousNamedSnapshotIndex() else { return }
        historyIndex = Double(idx)
        isMainViewFocused = true
    }

    func jumpToNextNamedSnapshot() {
        guard let idx = nextNamedSnapshotIndex() else { return }
        historyIndex = Double(idx)
        isMainViewFocused = true
    }

    func stepHistoryIndex(by delta: Int) {
        let snapshots = scenario.sortedSnapshots
        if snapshots.isEmpty { return }
        let current = Int(historyIndex)
        let next = min(max(current + delta, 0), snapshots.count - 1)
        guard next != current else { return }
        historyIndex = Double(next)
        isMainViewFocused = true
    }

}
