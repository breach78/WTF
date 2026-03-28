import SwiftUI
import AppKit

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
                            TextField("이름 변경", text: editedSnapshotNameBinding, onCommit: { commitSnapshotNameEdit(snapshotID: currentSnap.id) })
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
        saveWriterChanges(); takeSnapshot(force: true); exitPreviewMode()
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
