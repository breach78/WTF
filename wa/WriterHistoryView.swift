import SwiftUI
import AppKit

extension ScenarioWriterView {
    var timelineView: some View {
        let timelineCards = filteredTimelineCards()
        let timelineEmptyState = timelineEmptyState()
        let anchorCandidate = linkedCardsAnchorCandidateID()
        let canEnableLinkedCardFilter = anchorCandidate != nil
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(appearance == "light" ? .black.opacity(0.6) : .white.opacity(0.8))
                TextField("", text: searchTextBinding, prompt: Text("전체 카드 검색...").foregroundColor(appearance == "light" ? .black.opacity(0.4) : .white.opacity(0.7)))
                    .textFieldStyle(.plain).focused($isSearchFocused).foregroundStyle(appearance == "light" ? .black : .white).onExitCommand { closeSearch() }
                if !searchText.isEmpty { Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.5)) }.buttonStyle(.plain) }
            }
            .padding(10).background(appearance == "light" ? Color.black.opacity(0.05) : Color.white.opacity(0.08)).cornerRadius(8).padding([.horizontal, .top], 12)

            HStack {
                Button {
                    toggleLinkedCardsFilter()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                        Text("연결 카드")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(linkedCardsFilterEnabled ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        linkedCardsFilterEnabled
                        ? Color.accentColor
                        : (appearance == "light" ? Color.black.opacity(0.08) : Color.white.opacity(0.14))
                    )
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!linkedCardsFilterEnabled && !canEnableLinkedCardFilter)

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

            Text(timelineSectionTitle())
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(appearance == "light" ? .black.opacity(0.5) : .white.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
            Divider().background(appearance == "light" ? Color.black.opacity(0.1) : Color.white.opacity(0.1))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(timelineCards) { card in timelineRow(card) }
                        if timelineCards.isEmpty {
                            ContentUnavailableView(
                                timelineEmptyState.title,
                                systemImage: timelineEmptyState.systemImage
                            )
                            .foregroundStyle(appearance == "light" ? .black.opacity(0.3) : .white.opacity(0.5))
                            .scaleEffect(0.7)
                            .padding(.top, 40)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: activeCardID) { _, newID in if let id = newID { withAnimation(quickEaseAnimation) { proxy.scrollTo("timeline-\(id)", anchor: .center) } } }
            }
        }
    }

    func linkedCardsAnchorCandidateID() -> UUID? {
        if let anchorID = linkedCardAnchorID, findCard(by: anchorID) != nil {
            return anchorID
        }
        if let activeID = activeCardID, findCard(by: activeID) != nil {
            return activeID
        }
        if let editingID = editingCardID, findCard(by: editingID) != nil {
            return editingID
        }
        if let previousID = lastActiveCardID, findCard(by: previousID) != nil {
            return previousID
        }
        return scenario.rootCards.first?.id
    }

    func resolvedLinkedCardsAnchorID() -> UUID? {
        guard linkedCardsFilterEnabled else { return nil }
        if let anchorID = linkedCardAnchorID, findCard(by: anchorID) != nil {
            return anchorID
        }
        return linkedCardsAnchorCandidateID()
    }

    func toggleLinkedCardsFilter() {
        if linkedCardsFilterEnabled {
            linkedCardsFilterEnabled = false
            linkedCardAnchorID = nil
            return
        }
        guard let anchorID = linkedCardsAnchorCandidateID() else { return }
        linkedCardAnchorID = anchorID
        linkedCardsFilterEnabled = true
    }

    func disconnectLinkedCardFromAnchor(linkedCardID: UUID) {
        guard let anchorID = resolvedLinkedCardsAnchorID() else { return }
        scenario.disconnectLinkedCard(focusCardID: anchorID, linkedCardID: linkedCardID)
        requestHistoryAutosave(immediate: true)
    }

    func filteredTimelineCards() -> [SceneCard] {
        if linkedCardsFilterEnabled {
            guard let anchorID = resolvedLinkedCardsAnchorID() else { return [] }
            let linkedEntries = scenario.linkedCards(for: anchorID)
            if linkedEntries.isEmpty { return [] }
            let linkedDateByID = Dictionary(uniqueKeysWithValues: linkedEntries.map { ($0.cardID, $0.lastEditedAt) })
            return linkedEntries
                .compactMap { entry in findCard(by: entry.cardID) }
                .filter { matchesSearch($0) }
                .sorted { lhs, rhs in
                    let leftDate = linkedDateByID[lhs.id] ?? .distantPast
                    let rightDate = linkedDateByID[rhs.id] ?? .distantPast
                    if leftDate != rightDate { return leftDate > rightDate }
                    if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
        }

        return scenario.cards
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .filter { matchesSearch($0) }
    }

    func timelineSectionTitle() -> String {
        if linkedCardsFilterEnabled {
            return searchText.isEmpty ? "연결 카드 (최근 편집순)" : "연결 카드 검색 결과"
        }
        return searchText.isEmpty ? "전체 카드 (최신순)" : "검색 결과"
    }

    func timelineEmptyState() -> (title: String, systemImage: String) {
        if linkedCardsFilterEnabled {
            if resolvedLinkedCardsAnchorID() == nil {
                return ("기준 카드가 없습니다", "link.badge.plus")
            }
            if searchText.isEmpty {
                return ("연결 카드가 없습니다", "link")
            }
            return ("'\(searchText)' 검색 결과 없음", "magnifyingglass")
        }
        if searchText.isEmpty {
            return ("카드가 없습니다", "tray")
        }
        return ("'\(searchText)' 검색 결과 없음", "magnifyingglass")
    }
}
