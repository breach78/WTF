import SwiftUI
import CoreGraphics

nonisolated enum BWRCardBuddyOverlayRole: String, CaseIterable, Sendable {
    case slotCursor
    case hoverPlaceholder
    case dragSource
    case dragDestination
    case groupBlock
}

nonisolated enum BWRCardBuddyOverlayPalette: String, CaseIterable, Sendable {
    case neutral
    case accent
    case warm
}

nonisolated struct BWRCardBuddyOverlayStyleSnapshot: Equatable, Sendable {
    var role: BWRCardBuddyOverlayRole
    var strokePalette: BWRCardBuddyOverlayPalette
    var fillPalette: BWRCardBuddyOverlayPalette?
    var cornerRadius: CGFloat
    var lineWidth: CGFloat
    var dash: [CGFloat]
    var usesRoundDashCaps: Bool
    var strokeOpacity: Double
    var fillOpacity: Double
    var shadowOpacity: Double
    var shadowRadius: CGFloat
    var shadowYOffset: CGFloat

    var descriptor: String {
        let fillDescriptor = fillPalette?.rawValue ?? "none"
        let lineDescriptor = dash.isEmpty ? "solid" : "dashed"
        return "\(role.rawValue):stroke=\(strokePalette.rawValue):fill=\(fillDescriptor):\(lineDescriptor)"
    }
}

nonisolated enum BWRCardBuddyStateGrammar {
    static let showsSlotGridBaseline = false
    static let hoverDash: [CGFloat] = [2, 6]
    static let destinationDash: [CGFloat] = [8, 6]
    static let multiBlockBridgeGapCompensation: CGFloat = (BWRSlotBoardGeometry.default.placeholderInset * 2) + 1

    static func interactionPriority(for modality: BWRBoardInputModality) -> [BWRCardBuddyOverlayRole] {
        switch modality {
        case .keyboard:
            return [.hoverPlaceholder, .slotCursor, .dragSource, .dragDestination]
        case .pointer:
            return [.slotCursor, .hoverPlaceholder, .dragSource, .dragDestination]
        case .drag:
            return [.slotCursor, .hoverPlaceholder, .dragSource, .dragDestination]
        }
    }

    static func slotCursorStyle(isEmphasized: Bool) -> BWRCardBuddyOverlayStyleSnapshot {
        let surface = BWRCardBuddySurfaceAuditLock.target
        return BWRCardBuddyOverlayStyleSnapshot(
            role: .slotCursor,
            strokePalette: .neutral,
            fillPalette: .neutral,
            cornerRadius: surface.cursorCornerRadius,
            lineWidth: 1,
            dash: [],
            usesRoundDashCaps: false,
            strokeOpacity: isEmphasized ? 0.18 : 0.10,
            fillOpacity: isEmphasized ? surface.cursorFillOpacity : 0.08,
            shadowOpacity: 0,
            shadowRadius: 0,
            shadowYOffset: 0
        )
    }

    static func hoverStyle(isEmphasized: Bool) -> BWRCardBuddyOverlayStyleSnapshot {
        let surface = BWRCardBuddySurfaceAuditLock.target
        return BWRCardBuddyOverlayStyleSnapshot(
            role: .hoverPlaceholder,
            strokePalette: .neutral,
            fillPalette: nil,
            cornerRadius: surface.placeholderCornerRadius,
            lineWidth: max(1, surface.placeholderLineWidth - 0.3),
            dash: hoverDash,
            usesRoundDashCaps: true,
            strokeOpacity: isEmphasized ? 0.34 : 0.22,
            fillOpacity: 0,
            shadowOpacity: 0,
            shadowRadius: 0,
            shadowYOffset: 0
        )
    }

    static func dragSourceStyle(isLifted: Bool) -> BWRCardBuddyOverlayStyleSnapshot {
        let surface = BWRCardBuddySurfaceAuditLock.target
        return BWRCardBuddyOverlayStyleSnapshot(
            role: .dragSource,
            strokePalette: .accent,
            fillPalette: .accent,
            cornerRadius: max(surface.cardCornerRadius + 2, surface.cursorCornerRadius),
            lineWidth: isLifted ? 2.5 : 2,
            dash: [],
            usesRoundDashCaps: false,
            strokeOpacity: isLifted ? 0.94 : 0.78,
            fillOpacity: isLifted ? 0.12 : 0.08,
            shadowOpacity: isLifted ? 0.20 : 0.12,
            shadowRadius: isLifted ? 12 : 8,
            shadowYOffset: isLifted ? 6 : 4
        )
    }

    static func dragDestinationStyle(host: BWRSlotHost?) -> BWRCardBuddyOverlayStyleSnapshot {
        let surface = BWRCardBuddySurfaceAuditLock.target
        let palette: BWRCardBuddyOverlayPalette = {
            guard let host else { return .warm }
            switch host {
            case .group:
                return .accent
            case .strip:
                return .warm
            }
        }()

        return BWRCardBuddyOverlayStyleSnapshot(
            role: .dragDestination,
            strokePalette: palette,
            fillPalette: palette,
            cornerRadius: surface.placeholderCornerRadius,
            lineWidth: max(1.5, surface.placeholderLineWidth),
            dash: destinationDash,
            usesRoundDashCaps: true,
            strokeOpacity: 0.92,
            fillOpacity: palette == .accent ? 0.06 : 0.08,
            shadowOpacity: 0.10,
            shadowRadius: 10,
            shadowYOffset: 5
        )
    }

    static func groupBlockStyle() -> BWRCardBuddyOverlayStyleSnapshot {
        let surface = BWRCardBuddySurfaceAuditLock.target
        return BWRCardBuddyOverlayStyleSnapshot(
            role: .groupBlock,
            strokePalette: .accent,
            fillPalette: .accent,
            cornerRadius: surface.groupCornerRadius,
            lineWidth: surface.groupStrokeWidth,
            dash: surface.groupDash,
            usesRoundDashCaps: false,
            strokeOpacity: 0.72,
            fillOpacity: 0.10,
            shadowOpacity: 0.06,
            shadowRadius: 8,
            shadowYOffset: 4
        )
    }

    @MainActor
    static func strokeColor(for palette: BWRCardBuddyOverlayPalette) -> Color {
        switch palette {
        case .neutral:
            return Color.black
        case .accent:
            return Color(hex: BWRCardBuddyCardShell.selectionHex) ?? .accentColor
        case .warm:
            return Color(hex: "C77E2B") ?? Color.orange
        }
    }

    @MainActor
    static func fillColor(for palette: BWRCardBuddyOverlayPalette?) -> Color {
        guard let palette else { return .clear }
        return strokeColor(for: palette)
    }
}
