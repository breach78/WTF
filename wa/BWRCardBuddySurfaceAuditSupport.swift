import SwiftUI
import CoreGraphics

nonisolated struct BWRCardBuddySurfaceStyleSnapshot: Equatable, Sendable {
    var boardBackgroundHex: String
    var cardCornerRadius: CGFloat
    var cardShadowBlur: CGFloat
    var cardShadowYOffset: CGFloat
    var cardShadowOpacity: Double
    var cardInnerPadding: CGFloat
    var cardTextInset: CGFloat
    var visibleLineDensity: Int
    var selectionOutlineWidth: CGFloat
    var selectionOuterSpread: CGFloat
    var selectionColorHex: String
    var placeholderCornerRadius: CGFloat
    var placeholderLineWidth: CGFloat
    var placeholderDash: [CGFloat]
    var placeholderFillOpacity: Double
    var cursorCornerRadius: CGFloat
    var cursorFillOpacity: Double
    var cursorStrokeOpacity: Double
    var groupCornerRadius: CGFloat
    var groupFillOpacity: Double
    var groupStrokeWidth: CGFloat
    var groupDash: [CGFloat]

    var shadowSummary: String {
        "\(format(cardShadowBlur)) blur / \(format(cardShadowYOffset))y / \(format(cardShadowOpacity)) alpha"
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.1fpt", Double(value))
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

nonisolated enum BWRCardBuddySurfaceAuditLock {
    static let current = BWRCardBuddySurfaceStyleSnapshot(
        boardBackgroundHex: "F5F5F5",
        cardCornerRadius: 18,
        cardShadowBlur: 8,
        cardShadowYOffset: 5,
        cardShadowOpacity: 0.06,
        cardInnerPadding: 12,
        cardTextInset: 12,
        visibleLineDensity: 6,
        selectionOutlineWidth: 2.4,
        selectionOuterSpread: 0,
        selectionColorHex: "systemAccent",
        placeholderCornerRadius: 16,
        placeholderLineWidth: 2,
        placeholderDash: [10, 6],
        placeholderFillOpacity: 0.14,
        cursorCornerRadius: 18,
        cursorFillOpacity: 0.08,
        cursorStrokeOpacity: 0.18,
        groupCornerRadius: 24,
        groupFillOpacity: 0.025,
        groupStrokeWidth: 1,
        groupDash: [10, 8]
    )

    static let target = BWRCardBuddySurfaceStyleSnapshot(
        boardBackgroundHex: "D3CBC0",
        cardCornerRadius: 14,
        cardShadowBlur: 6,
        cardShadowYOffset: 3,
        cardShadowOpacity: 0.09,
        cardInnerPadding: 14,
        cardTextInset: 14,
        visibleLineDensity: 5,
        selectionOutlineWidth: 4,
        selectionOuterSpread: 8,
        selectionColorHex: "6D96D7",
        placeholderCornerRadius: 14,
        placeholderLineWidth: 1.5,
        placeholderDash: [7, 6],
        placeholderFillOpacity: 0.00,
        cursorCornerRadius: 16,
        cursorFillOpacity: 0.14,
        cursorStrokeOpacity: 0.16,
        groupCornerRadius: 24,
        groupFillOpacity: 0.018,
        groupStrokeWidth: 1,
        groupDash: [8, 8]
    )

    static let sampledSelectionBlueRGB = (r: 109, g: 150, b: 215)
}

nonisolated struct BWRCardBuddySurfaceMetricRow: Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var currentValue: String
    var targetValue: String
    var note: String
}

nonisolated struct BWRCardBuddyOverlayAuditRow: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var currentGrammar: String
    var targetGrammar: String
    var delta: String
}

nonisolated enum BWRCardBuddySurfaceAuditTableFactory {
    static let shellMetrics: [BWRCardBuddySurfaceMetricRow] = [
        BWRCardBuddySurfaceMetricRow(
            id: "card-radius",
            label: "Card radius",
            currentValue: "18pt",
            targetValue: "14pt",
            note: "Current card corners still read as app cards; reference corners are tighter paper rectangles."
        ),
        BWRCardBuddySurfaceMetricRow(
            id: "card-shadow",
            label: "Card shadow",
            currentValue: BWRCardBuddySurfaceAuditLock.current.shadowSummary,
            targetValue: BWRCardBuddySurfaceAuditLock.target.shadowSummary,
            note: "Reference shadow is lower, wider, and calmer than the current lifted app-card shadow."
        ),
        BWRCardBuddySurfaceMetricRow(
            id: "inner-padding",
            label: "Inner padding",
            currentValue: "12pt",
            targetValue: "14pt",
            note: "Target text block needs slightly more breathing room while still starting close to the top-left."
        ),
        BWRCardBuddySurfaceMetricRow(
            id: "text-inset",
            label: "Text inset",
            currentValue: "12pt",
            targetValue: "14pt",
            note: "111.jpg shows the first line anchored by body text, not a header band."
        ),
        BWRCardBuddySurfaceMetricRow(
            id: "line-density",
            label: "Visible line density",
            currentValue: "6 lines",
            targetValue: "5 lines",
            note: "Plan locks the preview closer to five readable lines before overflow disappears."
        )
    ]

    static let selectionMetrics: [BWRCardBuddySurfaceMetricRow] = [
        BWRCardBuddySurfaceMetricRow(
            id: "selection-width",
            label: "Selection outline width",
            currentValue: "2.4pt",
            targetValue: "4pt",
            note: "The reference blue ring is materially thicker than the current stroke."
        ),
        BWRCardBuddySurfaceMetricRow(
            id: "selection-spread",
            label: "Selection outer spread",
            currentValue: "0pt",
            targetValue: "8pt",
            note: "Current selection sits on the card edge; target selection inflates outside the paper."
        ),
        BWRCardBuddySurfaceMetricRow(
            id: "selection-color",
            label: "Selection color",
            currentValue: "system accent",
            targetValue: "#6D96D7 sampled from 111.jpg",
            note: "Locking a reference blue keeps comparison stable across machines."
        )
    ]

    static let overlayRows: [BWRCardBuddyOverlayAuditRow] = [
        BWRCardBuddyOverlayAuditRow(
            id: "keyboard-cursor",
            title: "Keyboard cursor",
            currentGrammar: "Gray rounded slot fill with 1pt stroke; available only through audit injection, not live navigation yet.",
            targetGrammar: "Single gray slot cursor that always marks keyboard position and never borrows selection blue.",
            delta: "Visual direction is close, but Phase C must wire it into real slot navigation."
        ),
        BWRCardBuddyOverlayAuditRow(
            id: "mouse-hover",
            title: "Mouse hover placeholder",
            currentGrammar: "Blue dashed placeholder with fill, same family as drop target.",
            targetGrammar: "Lower-priority neutral dotted placeholder that reads lighter than keyboard cursor and selection.",
            delta: "Current hover is too close to drag destination grammar."
        ),
        BWRCardBuddyOverlayAuditRow(
            id: "drag-source",
            title: "Drag source marker",
            currentGrammar: "Dashed blue source rectangle with translucent fill.",
            targetGrammar: "Lifted source keeps a blue-selected origin card rather than switching to a dashed box.",
            delta: "Current source marker still reads like a placeholder, not an origin anchor."
        ),
        BWRCardBuddyOverlayAuditRow(
            id: "drag-destination",
            title: "Drag destination placeholder",
            currentGrammar: "Same placeholder family as hover; color depends on host attach/detach kind.",
            targetGrammar: "Destination placeholder should feel like the cursor slot becoming magnetized for drop.",
            delta: "Current destination is not distinct enough from hover."
        )
    ]

    static let currentVsTargetRows: [BWRCardBuddySurfaceMetricRow] = [
        BWRCardBuddySurfaceMetricRow(
            id: "card-surface",
            label: "Card surface",
            currentValue: "Header + layer badge + footer meta remain visible",
            targetValue: "Body-only paper surface",
            note: "This row is intentionally descriptive because the surface grammar is not only geometric."
        ),
        BWRCardBuddySurfaceMetricRow(
            id: "selection-read",
            label: "Selection read",
            currentValue: "Edge stroke",
            targetValue: "Outer blue halo",
            note: "111.jpg makes selection read before card content."
        ),
        BWRCardBuddySurfaceMetricRow(
            id: "group-read",
            label: "Group read",
            currentValue: "Dashed frame competes with cards",
            targetValue: "Low-contrast panel behind cards",
            note: "Group stays explicit but loses first-read priority."
        ),
        BWRCardBuddySurfaceMetricRow(
            id: "overlay-separation",
            label: "Overlay separation",
            currentValue: "Hover and destination share one placeholder family",
            targetValue: "Cursor / hover / source / destination all read differently",
            note: "This is the main state-grammar lock for the next phase."
        )
    ]
}

nonisolated enum BWRCardBuddySurfaceAuditScenario: String, CaseIterable, Identifiable, Sendable {
    case normalCard
    case selectedCard
    case keyboardCursor
    case mouseHover
    case dragSource
    case dragDestination
    case groupFrame

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normalCard: return "Normal Card"
        case .selectedCard: return "Selection"
        case .keyboardCursor: return "Keyboard Cursor"
        case .mouseHover: return "Mouse Hover"
        case .dragSource: return "Drag Source"
        case .dragDestination: return "Drag Destination"
        case .groupFrame: return "Group Frame"
        }
    }

    var subtitle: String {
        switch self {
        case .normalCard:
            return "Card shell baseline"
        case .selectedCard:
            return "Selection outline lock"
        case .keyboardCursor:
            return "Single slot cursor"
        case .mouseHover:
            return "Hover placeholder"
        case .dragSource:
            return "Origin marker"
        case .dragDestination:
            return "Drop placeholder"
        case .groupFrame:
            return "Panel behind cards"
        }
    }
}

@MainActor
struct BWRCardBuddySurfaceAuditCanvasView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(BWRCardBuddySurfaceAuditScenario.allCases) { scenario in
                BWRCardBuddySurfaceAuditScenarioRow(scenario: scenario)
            }
        }
    }
}

@MainActor
private struct BWRCardBuddySurfaceAuditScenarioRow: View {
    let scenario: BWRCardBuddySurfaceAuditScenario

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(scenario.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(scenario.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                BWRCardBuddySurfaceAuditBoardColumn(
                    title: "Current BWR",
                    scenario: scenario,
                    style: BWRCardBuddySurfaceAuditLock.current,
                    showLegacyChrome: true
                )
                BWRCardBuddySurfaceAuditBoardColumn(
                    title: "Target Card Buddy Lock",
                    scenario: scenario,
                    style: BWRCardBuddySurfaceAuditLock.target,
                    showLegacyChrome: false
                )
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.02), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

@MainActor
private struct BWRCardBuddySurfaceAuditBoardColumn: View {
    let title: String
    let scenario: BWRCardBuddySurfaceAuditScenario
    let style: BWRCardBuddySurfaceStyleSnapshot
    let showLegacyChrome: Bool

    private let boardSize = CGSize(width: 572, height: 190)
    private let cardRect = CGRect(x: 96, y: 34, width: 220, height: 132)
    private let secondarySlotRect = CGRect(x: 328, y: 34, width: 220, height: 132)
    private let groupRect = CGRect(x: 74, y: 20, width: 474, height: 156)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: style.boardBackgroundHex) ?? Color(nsColor: .windowBackgroundColor))

                if scenario == .groupFrame {
                    groupFrame
                }
                if scenario == .keyboardCursor {
                    cursor(rect: secondarySlotRect)
                }
                if scenario == .mouseHover {
                    placeholder(rect: secondarySlotRect, kind: .hover)
                }
                if scenario == .dragDestination {
                    placeholder(rect: secondarySlotRect, kind: .destination)
                }
                if scenario == .dragSource {
                    sourceMarker(rect: cardRect)
                }
                card
                if scenario == .selectedCard {
                    selectionHalo(rect: cardRect)
                }
                if scenario == .groupFrame {
                    secondaryCard(offsetX: 160)
                }
            }
            .frame(width: boardSize.width, height: boardSize.height)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var card: some View {
        BWRCardBuddySurfaceAuditCard(
            style: style,
            showLegacyChrome: showLegacyChrome,
            isSelected: scenario == .selectedCard
        )
        .frame(width: cardRect.width, height: cardRect.height)
        .position(x: cardRect.midX, y: cardRect.midY)
    }

    private func secondaryCard(offsetX: CGFloat) -> some View {
        BWRCardBuddySurfaceAuditCard(
            style: style,
            showLegacyChrome: showLegacyChrome,
            isSelected: false
        )
        .frame(width: cardRect.width, height: cardRect.height)
        .position(x: cardRect.midX + offsetX, y: cardRect.midY)
    }

    private var groupFrame: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: style.groupCornerRadius, style: .continuous)
                .fill(Color.black.opacity(style.groupFillOpacity))
            RoundedRectangle(cornerRadius: style.groupCornerRadius, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: style.groupStrokeWidth, dash: style.groupDash))
                .foregroundStyle(Color.black.opacity(0.16))
            Text(showLegacyChrome ? "Current Group" : "Target Group")
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.top, 10)
        }
        .frame(width: groupRect.width, height: groupRect.height)
        .position(x: groupRect.midX, y: groupRect.midY)
    }

    private func selectionHalo(rect: CGRect) -> some View {
        ZStack {
            if style.selectionOuterSpread > 0 {
                RoundedRectangle(cornerRadius: style.cardCornerRadius + style.selectionOuterSpread, style: .continuous)
                    .fill((Color(hex: style.selectionColorHex) ?? .accentColor).opacity(0.22))
                    .frame(
                        width: rect.width + (style.selectionOuterSpread * 2),
                        height: rect.height + (style.selectionOuterSpread * 2)
                    )
            }
            RoundedRectangle(cornerRadius: style.cardCornerRadius + style.selectionOuterSpread * 0.25, style: .continuous)
                .stroke(Color(hex: style.selectionColorHex) ?? .accentColor, lineWidth: style.selectionOutlineWidth)
                .frame(
                    width: rect.width + (style.selectionOuterSpread * 2),
                    height: rect.height + (style.selectionOuterSpread * 2)
                )
        }
        .position(x: rect.midX, y: rect.midY)
    }

    private func placeholder(rect: CGRect, kind: BWRCardBuddySurfaceAuditPlaceholderKind) -> some View {
        RoundedRectangle(cornerRadius: style.placeholderCornerRadius, style: .continuous)
            .fill((kind == .destination ? (Color(hex: style.selectionColorHex) ?? .accentColor) : Color.clear).opacity(style.placeholderFillOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: style.placeholderCornerRadius, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: style.placeholderLineWidth, dash: style.placeholderDash)
                    )
                    .foregroundStyle(kind.strokeColor(selectionHex: style.selectionColorHex, legacy: showLegacyChrome))
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private func cursor(rect: CGRect) -> some View {
        RoundedRectangle(cornerRadius: style.cursorCornerRadius, style: .continuous)
            .fill(Color.black.opacity(style.cursorFillOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: style.cursorCornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(style.cursorStrokeOpacity), lineWidth: 1)
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    @ViewBuilder
    private func sourceMarker(rect: CGRect) -> some View {
        if showLegacyChrome {
            RoundedRectangle(cornerRadius: style.cardCornerRadius, style: .continuous)
                .stroke(
                    Color(hex: style.selectionColorHex) ?? .accentColor,
                    style: StrokeStyle(lineWidth: style.placeholderLineWidth, dash: style.placeholderDash)
                )
                .background(
                    RoundedRectangle(cornerRadius: style.cardCornerRadius, style: .continuous)
                        .fill((Color(hex: style.selectionColorHex) ?? .accentColor).opacity(0.08))
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        } else {
            selectionHalo(rect: rect)
        }
    }
}

private enum BWRCardBuddySurfaceAuditPlaceholderKind {
    case hover
    case destination

    func strokeColor(selectionHex: String, legacy: Bool) -> Color {
        switch self {
        case .hover:
            return legacy ? .accentColor : Color.black.opacity(0.32)
        case .destination:
            return Color(hex: selectionHex) ?? .accentColor
        }
    }
}

@MainActor
private struct BWRCardBuddySurfaceAuditCard: View {
    let style: BWRCardBuddySurfaceStyleSnapshot
    let showLegacyChrome: Bool
    let isSelected: Bool

    private var bodyPreview: String {
        if showLegacyChrome {
            return "Introduce Steve as a 2nd-grade student who has recently moved."
        }
        return "Introduce Steve as a 2nd-grade student\nwho has recently moved."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showLegacyChrome {
                HStack(alignment: .center, spacing: 8) {
                    Text("The New Kid")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("Body 1")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.08), in: Capsule())
                }
                .padding(.horizontal, style.cardTextInset)
                .padding(.top, style.cardInnerPadding)
            }

            Text(bodyPreview)
                .font(.system(size: showLegacyChrome ? 12 : 13, weight: showLegacyChrome ? .regular : .medium))
                .lineLimit(style.visibleLineDensity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(showLegacyChrome ? style.cardTextInset : 0)
                .padding(.top, showLegacyChrome ? 10 : style.cardInnerPadding)
                .padding(.leading, showLegacyChrome ? 0 : style.cardTextInset)
                .padding(.trailing, showLegacyChrome ? 0 : style.cardTextInset)

            if showLegacyChrome {
                HStack(spacing: 8) {
                    Text("BODY")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("4c1a")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, style.cardTextInset)
                .padding(.bottom, style.cardInnerPadding)
            } else {
                Spacer(minLength: style.cardInnerPadding)
            }
        }
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: style.cardCornerRadius, style: .continuous)
                .stroke(showLegacyChrome ? (isSelected ? Color.accentColor : Color.black.opacity(0.10)) : Color.black.opacity(0.08), lineWidth: showLegacyChrome ? (isSelected ? style.selectionOutlineWidth : 1.0) : 1.0)
        )
        .clipShape(RoundedRectangle(cornerRadius: style.cardCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(style.cardShadowOpacity), radius: style.cardShadowBlur, x: 0, y: style.cardShadowYOffset)
    }
}

@MainActor
struct BWRCardBuddySurfaceAuditMetricTable: View {
    let title: String
    let rows: [BWRCardBuddySurfaceMetricRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))

            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(row.label)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 140, alignment: .leading)
                        Text(row.currentValue)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 190, alignment: .leading)
                        Text(row.targetValue)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 190, alignment: .leading)
                    }
                    Text(row.note)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                if row.id != rows.last?.id {
                    Divider()
                }
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.02), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

@MainActor
struct BWRCardBuddyOverlayAuditTable: View {
    let rows: [BWRCardBuddyOverlayAuditRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Overlay Diff Table")
                .font(.system(size: 16, weight: .semibold))

            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    Text(row.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text("Current: \(row.currentGrammar)")
                        .font(.system(size: 12))
                    Text("Target: \(row.targetGrammar)")
                        .font(.system(size: 12))
                    Text("Delta: \(row.delta)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                if row.id != rows.last?.id {
                    Divider()
                }
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.02), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
