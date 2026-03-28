import SwiftUI
import AppKit

extension ScenarioWriterView {
    var namedCheckpointSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("이름 있는 분기점 만들기")
                .font(.system(size: 18, weight: .bold))
            TextField("분기점 이름 (예: 주인공 성격 수정)", text: newCheckpointNameBinding)
                .textFieldStyle(.roundedBorder)

            Text("노트 (선택)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            TextEditor(text: newCheckpointNoteBinding)
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
                text: snapshotNoteSearchTextBinding,
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

    func requestHistoryAutosave(immediate: Bool = false) {
        let throttleInterval: TimeInterval = 0.45

        if immediate {
            historySaveRequestWorkItem?.cancel()
            historySaveRequestWorkItem = nil
            historySaveRequestNextAllowedAt = Date().addingTimeInterval(throttleInterval)
            saveWriterChanges()
            return
        }

        let now = Date()
        if now >= historySaveRequestNextAllowedAt {
            historySaveRequestNextAllowedAt = now.addingTimeInterval(throttleInterval)
            saveWriterChanges()
            return
        }

        historySaveRequestWorkItem?.cancel()
        let delay = max(0, historySaveRequestNextAllowedAt.timeIntervalSince(now))
        let work = DispatchWorkItem {
            historySaveRequestWorkItem = nil
            historySaveRequestNextAllowedAt = Date().addingTimeInterval(throttleInterval)
            saveWriterChanges()
        }
        historySaveRequestWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func flushPendingHistoryAutosaveIfNeeded() {
        guard historySaveRequestWorkItem != nil else { return }
        historySaveRequestWorkItem?.cancel()
        historySaveRequestWorkItem = nil
        historySaveRequestNextAllowedAt = Date()
        saveWriterChanges()
    }

    func finishNamedSnapshotNoteEditing(restoreMainFocus: Bool) {
        flushPendingHistoryAutosaveIfNeeded()
        isNamedSnapshotNoteEditing = false
        isNamedSnapshotNoteEditorFocused = false
        if restoreMainFocus {
            isMainViewFocused = true
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
                    requestHistoryAutosave()
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
            requestHistoryAutosave(immediate: true)
        }
        if showHistoryBar {
            syncNamedSnapshotNoteForCurrentSelection(focusEditor: false)
        }
        editingSnapshotID = nil
        editedSnapshotName = ""
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
            requestHistoryAutosave()
        }
        return noteCard
    }
}
