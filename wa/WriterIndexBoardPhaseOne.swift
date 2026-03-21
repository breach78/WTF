import SwiftUI

enum IndexBoardGroupID: Hashable, Identifiable {
    case root
    case parent(UUID)

    var id: String {
        switch self {
        case .root:
            return "root"
        case .parent(let parentID):
            return parentID.uuidString
        }
    }

    var parentID: UUID? {
        switch self {
        case .root:
            return nil
        case .parent(let parentID):
            return parentID
        }
    }
}

struct IndexBoardGroupProjection: Identifiable {
    let id: IndexBoardGroupID
    let parentCard: SceneCard?
    let title: String
    let subtitle: String
    let statusText: String
    let isTempGroup: Bool
    let childCards: [SceneCard]
}

struct IndexBoardProjection {
    let source: IndexBoardColumnSource
    let orderedCardIDs: [UUID]
    let groups: [IndexBoardGroupProjection]
}

enum IndexBoardMetrics {
    static let boardHorizontalPadding: CGFloat = 28
    static let boardVerticalPadding: CGFloat = 24
    static let groupWidth: CGFloat = 472
    static let groupSpacing: CGFloat = 24
    static let groupLineSpacing: CGFloat = 24
    static let groupInnerPadding: CGFloat = 18
    static let cardSpacing: CGFloat = 14
    static let cardSize = CGSize(width: 211, height: 136)
    static let cardCornerRadius: CGFloat = 12
    static let cardInnerPadding: CGFloat = 12
}

struct IndexBoardRenderTheme {
    let usesDarkAppearance: Bool
    let cardBaseColorHex: String
    let cardActiveColorHex: String
    let darkCardBaseColorHex: String
    let darkCardActiveColorHex: String

    private var boardTopRGB: (Double, Double, Double) {
        usesDarkAppearance ? (0.10, 0.11, 0.13) : (0.96, 0.94, 0.89)
    }

    private var boardBottomRGB: (Double, Double, Double) {
        usesDarkAppearance ? (0.14, 0.15, 0.18) : (0.90, 0.88, 0.82)
    }

    private var groupRGB: (Double, Double, Double) {
        usesDarkAppearance ? (0.16, 0.17, 0.20) : (0.98, 0.97, 0.94)
    }

    private var groupBorderRGB: (Double, Double, Double) {
        usesDarkAppearance ? (0.28, 0.30, 0.36) : (0.78, 0.75, 0.69)
    }

    private var tabRGB: (Double, Double, Double) {
        usesDarkAppearance ? (0.21, 0.23, 0.28) : (0.89, 0.86, 0.80)
    }

    private var accentRGB: (Double, Double, Double) {
        if usesDarkAppearance {
            return parseHexRGB(darkCardActiveColorHex) ?? (0.31, 0.40, 0.52)
        }
        return parseHexRGB(cardActiveColorHex) ?? (0.74, 0.84, 0.98)
    }

    var boardBackground: LinearGradient {
        LinearGradient(
            colors: [color(from: boardTopRGB), color(from: boardBottomRGB)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var groupBackground: Color {
        color(from: groupRGB)
    }

    var groupBorder: Color {
        color(from: groupBorderRGB)
    }

    var tabBackground: Color {
        color(from: tabRGB)
    }

    var accentColor: Color {
        color(from: accentRGB)
    }

    var primaryTextColor: Color {
        usesDarkAppearance ? Color.white.opacity(0.92) : Color.black.opacity(0.82)
    }

    var secondaryTextColor: Color {
        usesDarkAppearance ? Color.white.opacity(0.60) : Color.black.opacity(0.54)
    }

    func cardFillColor(customHex: String?, isSelected: Bool, isActive: Bool) -> Color {
        let baseHex = usesDarkAppearance ? darkCardBaseColorHex : cardBaseColorHex
        let baseRGB = parseHexRGB(customHex ?? baseHex) ?? (usesDarkAppearance ? (0.16, 0.17, 0.20) : (1.0, 1.0, 1.0))
        let accent = accentRGB
        let amount: Double
        if isActive {
            amount = usesDarkAppearance ? 0.52 : 0.42
        } else if isSelected {
            amount = usesDarkAppearance ? 0.32 : 0.26
        } else {
            amount = 0.0
        }
        return color(from: mix(base: baseRGB, overlay: accent, amount: amount))
    }

    func cardBorderColor(isSelected: Bool, isActive: Bool) -> Color {
        if isActive {
            return accentColor.opacity(0.96)
        }
        if isSelected {
            return accentColor.opacity(0.64)
        }
        return groupBorder.opacity(0.78)
    }

    private func mix(
        base: (Double, Double, Double),
        overlay: (Double, Double, Double),
        amount: Double
    ) -> (Double, Double, Double) {
        (
            base.0 + ((overlay.0 - base.0) * amount),
            base.1 + ((overlay.1 - base.1) * amount),
            base.2 + ((overlay.2 - base.2) * amount)
        )
    }

    private func color(from rgb: (Double, Double, Double)) -> Color {
        Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }
}

struct IndexBoardCardGridLayout: Layout {
    let columns: Int
    let spacing: CGFloat
    let cardSize: CGSize

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let rows = Int(ceil(Double(subviews.count) / Double(max(1, columns))))
        let width = (CGFloat(max(1, columns)) * cardSize.width) + (CGFloat(max(0, columns - 1)) * spacing)
        let height = (CGFloat(rows) * cardSize.height) + (CGFloat(max(0, rows - 1)) * spacing)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let safeColumns = max(1, columns)
        for (index, subview) in subviews.enumerated() {
            let row = index / safeColumns
            let column = index % safeColumns
            let x = bounds.minX + (CGFloat(column) * (cardSize.width + spacing)) + (cardSize.width / 2)
            let y = bounds.minY + (CGFloat(row) * (cardSize.height + spacing)) + (cardSize.height / 2)
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .center,
                proposal: ProposedViewSize(cardSize)
            )
        }
    }
}

struct IndexBoardWrapLayout: Layout {
    let itemSpacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = max(IndexBoardMetrics.groupWidth, proposal.width ?? (IndexBoardMetrics.groupWidth * 2 + itemSpacing))
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var contentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX > 0 && cursorX + size.width > maxWidth {
                contentWidth = max(contentWidth, cursorX - itemSpacing)
                cursorX = 0
                cursorY += lineHeight + lineSpacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            cursorX += size.width + itemSpacing
        }

        contentWidth = max(contentWidth, max(0, cursorX - itemSpacing))
        let height = cursorY + lineHeight
        return CGSize(width: max(contentWidth, maxWidth), height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let maxWidth = max(IndexBoardMetrics.groupWidth, bounds.width)
        var cursorX = bounds.minX
        var cursorY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX > bounds.minX && cursorX + size.width > bounds.minX + maxWidth {
                cursorX = bounds.minX
                cursorY += lineHeight + lineSpacing
                lineHeight = 0
            }

            subview.place(
                at: CGPoint(x: cursorX, y: cursorY),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )

            cursorX += size.width + itemSpacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

struct IndexBoardCardTile: View {
    @ObservedObject var card: SceneCard
    let theme: IndexBoardRenderTheme
    let isSelected: Bool
    let isActive: Bool
    var summary: IndexBoardResolvedSummary? = nil
    var showsBack: Bool = false
    let onTap: () -> Void
    var onToggleFace: (() -> Void)? = nil
    var onOpen: (() -> Void)? = nil

    private var titleText: String {
        let trimmed = card.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "내용 없음" : trimmed
    }

    private var backSummaryText: String {
        summary?.summaryText ?? "요약이 아직 없습니다."
    }

    private var tileCornerRadius: CGFloat {
        IndexBoardMetrics.cardCornerRadius
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                if let summary,
                   summary.hasSummary {
                    summaryBadge(summary: summary)
                }
                if card.cloneGroupID != nil {
                    Image(systemName: "link")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.secondaryTextColor)
                }
                if let onOpen {
                    Button(action: onOpen) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(theme.secondaryTextColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            if showsBack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(backSummaryText)
                        .font(.custom("SansMonoCJKFinalDraft", size: 13))
                        .foregroundStyle(theme.primaryTextColor)
                        .lineLimit(5)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    HStack(spacing: 6) {
                        if let summary,
                           summary.hasSummary {
                            Text(summary.sourceLabelText)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(theme.secondaryTextColor)
                        } else {
                            Text("요약 없음")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(theme.secondaryTextColor)
                        }

                        if summary?.isStale == true {
                            Text("STALE")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.orange.opacity(theme.usesDarkAppearance ? 0.94 : 0.88))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.orange.opacity(theme.usesDarkAppearance ? 0.20 : 0.16))
                                )
                        }

                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text(titleText)
                    .font(.custom("SansMonoCJKFinalDraft", size: 13))
                    .foregroundStyle(theme.primaryTextColor)
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(IndexBoardMetrics.cardInnerPadding)
        .frame(width: IndexBoardMetrics.cardSize.width, height: IndexBoardMetrics.cardSize.height, alignment: .topLeading)
        .background(theme.cardFillColor(customHex: card.colorHex, isSelected: isSelected, isActive: isActive))
        .overlay(
            RoundedRectangle(cornerRadius: tileCornerRadius, style: .continuous)
                .stroke(theme.cardBorderColor(isSelected: isSelected, isActive: isActive), lineWidth: isActive ? 1.8 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: tileCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: tileCornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(theme.usesDarkAppearance ? 0.16 : 0.07), radius: 8, x: 0, y: 4)
        .onTapGesture(perform: onTap)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    onOpen?()
                }
        )
    }

    @ViewBuilder
    private func summaryBadge(summary: IndexBoardResolvedSummary) -> some View {
        let badgeLabel = Image(systemName: summaryBadgeSymbolName(summary))
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(summary.isStale ? Color.orange.opacity(0.94) : theme.secondaryTextColor)
            .frame(width: 20, height: 20)
            .background(
                Circle()
                    .fill(
                        summaryBadgeBackground(summary)
                    )
            )
            .help(summaryBadgeHelpText(summary))

        if let onToggleFace {
            Button(action: onToggleFace) {
                badgeLabel
            }
            .buttonStyle(.plain)
        } else {
            badgeLabel
        }
    }

    private func summaryBadgeSymbolName(_ summary: IndexBoardResolvedSummary) -> String {
        if summary.isStale {
            return "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        }
        if summary.usesFallback {
            return "doc.text.magnifyingglass"
        }
        switch summary.sourceType {
        case .ai:
            return "sparkles"
        case .manual:
            return "square.and.pencil"
        case .digest:
            return "note.text"
        }
    }

    private func summaryBadgeBackground(_ summary: IndexBoardResolvedSummary) -> Color {
        if summary.isStale {
            return Color.orange.opacity(theme.usesDarkAppearance ? 0.28 : 0.18)
        }
        if showsBack {
            return theme.accentColor.opacity(theme.usesDarkAppearance ? 0.34 : 0.22)
        }
        if summary.usesFallback {
            return theme.accentColor.opacity(theme.usesDarkAppearance ? 0.22 : 0.14)
        }
        return Color.black.opacity(theme.usesDarkAppearance ? 0.16 : 0.06)
    }

    private func summaryBadgeHelpText(_ summary: IndexBoardResolvedSummary) -> String {
        if summary.isStale {
            return "\(summary.sourceLabelText) · 원문이 바뀌어 요약이 오래됐습니다."
        }
        return "\(summary.sourceLabelText) · 요약면 보기"
    }
}

struct IndexBoardGroupHeaderView: View {
    let group: IndexBoardGroupProjection
    let theme: IndexBoardRenderTheme
    let containsActiveCard: Bool

    private var eyebrowText: String {
        if group.isTempGroup {
            return "TEMP"
        }
        if group.parentCard == nil {
            return "ROOT"
        }
        return "GROUP"
    }

    private var badgeFill: Color {
        if group.isTempGroup {
            return Color.orange.opacity(theme.usesDarkAppearance ? 0.26 : 0.18)
        }
        if containsActiveCard {
            return theme.accentColor.opacity(theme.usesDarkAppearance ? 0.34 : 0.22)
        }
        return Color.black.opacity(theme.usesDarkAppearance ? 0.18 : 0.06)
    }

    private var badgeTextColor: Color {
        if group.isTempGroup {
            return Color.orange.opacity(theme.usesDarkAppearance ? 0.96 : 0.90)
        }
        return containsActiveCard ? theme.primaryTextColor : theme.secondaryTextColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 10) {
                Text(eyebrowText)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(badgeTextColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(badgeFill)
                    )

                Text(group.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primaryTextColor)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(group.statusText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(badgeTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(badgeFill)
                    )
            }

            Text(group.subtitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.secondaryTextColor)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, IndexBoardMetrics.groupInnerPadding)
        .padding(.vertical, 14)
        .background(theme.tabBackground)
    }
}

struct IndexBoardGroupView: View {
    let group: IndexBoardGroupProjection
    let theme: IndexBoardRenderTheme
    let selectedCardIDs: Set<UUID>
    let activeCardID: UUID?
    var summaryByCardID: [UUID: IndexBoardResolvedSummary] = [:]
    var showsBackByCardID: [UUID: Bool] = [:]
    var onToggleCardFace: ((SceneCard) -> Void)? = nil
    let onCardTap: (SceneCard) -> Void

    private var containsSelectedCard: Bool {
        group.childCards.contains { selectedCardIDs.contains($0.id) }
    }

    private var containsActiveCard: Bool {
        group.childCards.contains { $0.id == activeCardID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IndexBoardGroupHeaderView(
                group: group,
                theme: theme,
                containsActiveCard: containsActiveCard
            )

            IndexBoardCardGridLayout(
                columns: 2,
                spacing: IndexBoardMetrics.cardSpacing,
                cardSize: IndexBoardMetrics.cardSize
            ) {
                ForEach(group.childCards, id: \.id) { card in
                    IndexBoardCardTile(
                        card: card,
                        theme: theme,
                        isSelected: selectedCardIDs.contains(card.id),
                        isActive: activeCardID == card.id,
                        summary: summaryByCardID[card.id],
                        showsBack: showsBackByCardID[card.id] ?? false,
                        onTap: {
                            onCardTap(card)
                        },
                        onToggleFace: onToggleCardFace.map { toggle in
                            {
                                toggle(card)
                            }
                        }
                    )
                }
            }
            .padding(IndexBoardMetrics.groupInnerPadding)
        }
        .frame(width: IndexBoardMetrics.groupWidth, alignment: .topLeading)
        .background(theme.groupBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    containsActiveCard
                    ? theme.accentColor.opacity(0.92)
                    : (containsSelectedCard ? theme.accentColor.opacity(0.52) : theme.groupBorder),
                    lineWidth: containsActiveCard ? 2 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(theme.usesDarkAppearance ? 0.24 : 0.08), radius: 18, x: 0, y: 10)
    }
}

struct IndexBoardPhaseOneView: View {
    let projection: IndexBoardProjection
    let sourceTitle: String
    let canvasSize: CGSize
    let theme: IndexBoardRenderTheme
    let activeCardID: UUID?
    let selectedCardIDs: Set<UUID>
    let onClose: () -> Void
    let onCardTap: (SceneCard) -> Void

    private var canvasContentWidth: CGFloat {
        let preferredColumns = projection.groups.count >= 2 ? 2 : 1
        let preferredWidth =
            (CGFloat(preferredColumns) * IndexBoardMetrics.groupWidth) +
            (CGFloat(max(0, preferredColumns - 1)) * IndexBoardMetrics.groupSpacing) +
            (IndexBoardMetrics.boardHorizontalPadding * 2)
        return max(canvasSize.width - 24, preferredWidth)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if projection.groups.isEmpty {
                emptyState
            } else {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    IndexBoardWrapLayout(
                        itemSpacing: IndexBoardMetrics.groupSpacing,
                        lineSpacing: IndexBoardMetrics.groupLineSpacing
                    ) {
                        ForEach(projection.groups) { group in
                            IndexBoardGroupView(
                                group: group,
                                theme: theme,
                                selectedCardIDs: selectedCardIDs,
                                activeCardID: activeCardID,
                                onCardTap: onCardTap
                            )
                        }
                    }
                    .padding(.horizontal, IndexBoardMetrics.boardHorizontalPadding)
                    .padding(.vertical, IndexBoardMetrics.boardVerticalPadding)
                    .frame(width: canvasContentWidth, alignment: .topLeading)
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .background(theme.boardBackground)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(sourceTitle)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primaryTextColor)
                    .lineLimit(1)
                Text("Board View · 그룹 \(projection.groups.count) · 카드 \(projection.orderedCardIDs.count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.secondaryTextColor)
                Text("Phase 1: group wrapper projection + static render + selection")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.secondaryTextColor)
            }

            Spacer(minLength: 0)

            Button("작업창으로 돌아가기") {
                onClose()
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accentColor.opacity(theme.usesDarkAppearance ? 0.84 : 0.92))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(theme.groupBackground.opacity(theme.usesDarkAppearance ? 0.94 : 0.86))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.groupBorder.opacity(0.65))
                .frame(height: 1)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("표시할 카드가 없습니다.")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(theme.primaryTextColor)
            Text("현재 Phase에서는 source column에 남아 있는 live 카드만 보드로 투영합니다.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.secondaryTextColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(40)
    }
}
