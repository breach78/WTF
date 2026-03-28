import SwiftUI

enum SettingsLayout {
    static let windowWidth: CGFloat = 1160
    static let windowHeight: CGFloat = 760
    static let sidebarWidth: CGFloat = 240
    static let sidebarSectionSpacing: CGFloat = 14
    static let sidebarRowSpacing: CGFloat = 4
    static let contentPadding: CGFloat = 14
    static let cardSpacing: CGFloat = 12
    static let cardContentSpacing: CGFloat = 6
    static let cardPadding: CGFloat = 10
    static let cardCornerRadius: CGFloat = 12
    static let titleCornerRadius: CGFloat = 8
    static let cardTitleFontSize: CGFloat = 14
}

extension SettingsView {
    var shortcutSections: [ShortcutSection] {
        [
            ShortcutSection(
                title: "공통",
                items: [
                    ShortcutItem(keys: "Cmd + Z", action: "실행 취소"),
                    ShortcutItem(keys: "Cmd + Shift + Z", action: "다시 실행"),
                    ShortcutItem(keys: "Cmd + Shift + F", action: "포커스 모드 토글"),
                    ShortcutItem(keys: "Cmd + F", action: "검색창 열기/닫기"),
                    ShortcutItem(keys: "Cmd + Shift + ]", action: "전체 카드(타임라인) 패널 토글")
                ]
            ),
            ShortcutSection(
                title: "메인 작업 모드",
                items: [
                    ShortcutItem(keys: "Arrow ↑ ↓ ← →", action: "카드 이동"),
                    ShortcutItem(keys: "Right (자식 없음 시 빠르게 2회)", action: "인접 부모의 자식 카드로 점프"),
                    ShortcutItem(keys: "Return", action: "선택 카드 편집 시작"),
                    ShortcutItem(keys: "Esc", action: "편집/검색 종료 (상황별)"),
                    ShortcutItem(keys: "Tab + Tab (편집 중)", action: "자식 카드 추가 후 바로 편집"),
                    ShortcutItem(keys: "Tab", action: "자식 카드 추가"),
                    ShortcutItem(keys: "Cmd + ↑", action: "위에 형제 카드 추가"),
                    ShortcutItem(keys: "Cmd + ↓", action: "아래에 형제 카드 추가"),
                    ShortcutItem(keys: "Cmd + Return", action: "편집 종료 후 아래에 형제 카드 추가"),
                    ShortcutItem(keys: "Cmd + →", action: "자식 카드 추가"),
                    ShortcutItem(keys: "Cmd + Shift + Delete", action: "선택 카드(또는 선택 묶음) 삭제"),
                    ShortcutItem(keys: "Cmd + Shift + Arrow", action: "카드 계층 이동(상/하/좌/우)")
                ]
            ),
            ShortcutSection(
                title: "포커스 모드",
                items: [
                    ShortcutItem(keys: "Arrow ↑ / ↓", action: "경계에서 이전/다음 카드로 이동"),
                    ShortcutItem(keys: "Cmd + Shift + T", action: "타이프라이터 모드 토글"),
                    ShortcutItem(keys: "Cmd + Return", action: "아래에 형제 카드 추가"),
                    ShortcutItem(keys: "Cmd + Option + ↑ / ↓", action: "위/아래 형제 카드 추가"),
                    ShortcutItem(keys: "Cmd + Shift + Delete", action: "현재 카드 삭제")
                ]
            ),
            ShortcutSection(
                title: "히스토리 모드",
                items: [
                    ShortcutItem(keys: "Arrow ← / →", action: "타임라인 이전/다음 시점 이동"),
                    ShortcutItem(keys: "Cmd + Arrow ← / →", action: "이전/다음 네임드 스냅샷 이동"),
                    ShortcutItem(keys: "Esc", action: "검색 포커스 해제/노트 편집 종료/히스토리 닫기")
                ]
            )
        ]
    }

    var normalizedSearchQuery: String {
        settingsSearchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    var isSearching: Bool {
        !normalizedSearchQuery.isEmpty
    }

    var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayout.sidebarSectionSpacing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("설정")
                        .font(.headline)
                    Text("카테고리")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                sidebarSection(title: "설정", categories: SettingsCategory.primary)
                sidebarSection(title: "정보", categories: SettingsCategory.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(width: SettingsLayout.sidebarWidth, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    func sidebarSection(title: String, categories: [SettingsCategory]) -> some View {
        VStack(alignment: .leading, spacing: SettingsLayout.sidebarRowSpacing) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 6)

            ForEach(categories) { category in
                Button {
                    selectCategory(category)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: category.systemImage)
                            .frame(width: 16)
                        Text(category.title)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selectedCategory == category ? Color.accentColor.opacity(0.18) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
    }

    func selectCategory(_ category: SettingsCategory) {
        selectedCategory = category
        if isSearching {
            settingsSearchQuery = ""
        }
    }

    @ViewBuilder
    var detailContent: some View {
        if isSearching {
            searchResultsView
        } else if let selectedCategory {
            categoryView(for: selectedCategory, showHeader: true)
        } else {
            ContentUnavailableView("카테고리를 선택하세요", systemImage: "sidebar.left")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    var searchResultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayout.cardSpacing + 6) {
                Text("검색 결과")
                    .font(.title3.weight(.semibold))
                Text("\"\(settingsSearchQuery)\"에 해당하는 설정만 표시합니다.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(SettingsCategory.searchOrder) { category in
                    if hasVisibleCards(in: category) {
                        VStack(alignment: .leading, spacing: SettingsLayout.cardSpacing) {
                            Text(category.title)
                                .font(.headline)
                                .padding(.top, 2)
                            categoryCards(for: category)
                        }
                    }
                }

                if !SettingsCategory.searchOrder.contains(where: { hasVisibleCards(in: $0) }) {
                    ContentUnavailableView(
                        "검색 결과가 없습니다",
                        systemImage: "magnifyingglass",
                        description: Text("다른 키워드를 입력하거나 카테고리를 직접 탐색해 보세요.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(SettingsLayout.contentPadding)
            .controlSize(.small)
        }
    }

    func categoryView(for category: SettingsCategory, showHeader: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayout.cardSpacing) {
                if showHeader {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.title)
                            .font(.title3.weight(.semibold))
                        Text(category.descriptionText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 2)
                }

                categoryCards(for: category)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(SettingsLayout.contentPadding)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    func categoryCards(for category: SettingsCategory) -> some View {
        switch category {
        case .workEnvironment:
            workEnvironmentCards
        case .appearance:
            appearanceCards
        case .ai:
            aiCards
        case .export:
            exportCards
        case .dataBackup:
            dataBackupCards
        case .aboutLegal:
            aboutLegalCards
        }
    }

    func hasVisibleCards(in category: SettingsCategory) -> Bool {
        switch category {
        case .workEnvironment:
            if cardMatches(title: "빠른 설정", keywords: ["행간", "자동 백업", "타이프라이터", "자주", "빠른", "quick"]) { return true }
            if cardMatches(title: "편집기 설정", keywords: ["메인", "행간", "카드 간격", "editor"]) { return true }
            if cardMatches(title: "포커스 모드 설정", keywords: ["포커스", "타이프라이터", "기준선", "focus"]) { return true }
            return shortcutSections.contains(where: shortcutSectionMatches)
        case .appearance:
            return cardMatches(title: "색상 테마 프리셋", keywords: ["색상", "테마", "프리셋", "palette", "theme"]) ||
                cardMatches(title: "색상 설정", keywords: ["라이트", "다크", "배경", "카드", "custom color"]) ||
                cardMatches(title: "색상 초기화", keywords: ["기본값", "reset", "restore default"])
        case .ai:
            return cardMatches(title: "AI 설정", keywords: ["gemini", "모델", "API 키", "keychain", "ai"])
        case .export:
            return cardMatches(title: "출력 설정", keywords: ["PDF", "중앙정렬식", "한국식", "폰트", "정렬", "export"])
        case .dataBackup:
            return cardMatches(title: "데이터 저장소", keywords: ["작업 파일", "workspace", "저장 경로"]) ||
                cardMatches(title: "자동 백업", keywords: ["백업", "보관", "zip", "backup"])
        case .aboutLegal:
            return cardMatches(title: "앱 정보", keywords: ["버전", "정보", "about"]) ||
                cardMatches(title: "폰트 라이선스 (OFL)", keywords: ["라이선스", "법적", "폰트", "ofl"])
        }
    }

    func cardMatches(title: String, keywords: [String] = []) -> Bool {
        guard isSearching else { return true }
        let haystack = ([title] + keywords)
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        return haystack.contains(normalizedSearchQuery)
    }

    func shortcutSectionMatches(_ section: ShortcutSection) -> Bool {
        guard isSearching else { return true }
        if cardMatches(title: section.title, keywords: ["단축키", "shortcut", "keyboard"]) {
            return true
        }
        return section.items.contains { item in
            cardMatches(
                title: item.action,
                keywords: [item.keys, section.title, "단축키", "shortcut", "keyboard"]
            )
        }
    }

    @ViewBuilder
    func settingsCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SettingsLayout.cardContentSpacing) {
            Text(title)
                .font(.system(size: SettingsLayout.cardTitleFontSize, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: SettingsLayout.titleCornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                )

            VStack(alignment: .leading, spacing: SettingsLayout.cardContentSpacing) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(SettingsLayout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: SettingsLayout.cardCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsLayout.cardCornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    func shortcutRow(_ item: ShortcutItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.action)
                .font(.system(size: 11))
                .lineLimit(2)
            Spacer(minLength: 8)
            Text(item.keys)
                .font(.system(size: 10, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}
