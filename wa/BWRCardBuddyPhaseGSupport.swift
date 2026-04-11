import SwiftUI
import CoreGraphics
import Foundation

nonisolated struct BWRCardBuddyCardSwatch: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let hex: String
}

nonisolated struct BWRCardBuddyBoardSurfaceSwatch: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let hex: String
    let accentMode: BWRBoardAccentMode
}

nonisolated struct BWRCardBuddyGroupPanelStyleSnapshot: Equatable, Sendable {
    var cornerRadius: CGFloat
    var fillHex: String
    var fillOpacity: Double
    var strokeHex: String
    var strokeOpacity: Double
    var strokeWidth: CGFloat
}

nonisolated enum BWRCardBuddyBoardThemeGuardrail {
    static let cardSwatches: [BWRCardBuddyCardSwatch] = [
        .init(id: "paper", name: "Paper", hex: "F8FAFC"),
        .init(id: "sky", name: "Sky", hex: "E0F2FE"),
        .init(id: "mint", name: "Mint", hex: "DCFCE7"),
        .init(id: "amber", name: "Amber", hex: "FEF3C7"),
        .init(id: "rose", name: "Rose", hex: "FCE7F3"),
        .init(id: "lavender", name: "Lavender", hex: "EDE9FE"),
        .init(id: "stone", name: "Stone", hex: "E7E5E4"),
        .init(id: "coral", name: "Coral", hex: "FED7AA")
    ]

    static let boardSwatches: [BWRCardBuddyBoardSurfaceSwatch] = [
        .init(id: "desk", name: "Desk", hex: "D3CBC0", accentMode: .system),
        .init(id: "sand", name: "Sand", hex: "DDD4C7", accentMode: .warm),
        .init(id: "sage", name: "Sage", hex: "D6DED1", accentMode: .cool),
        .init(id: "mist", name: "Mist", hex: "D6E0E3", accentMode: .cool),
        .init(id: "clay", name: "Clay", hex: "E2D3C6", accentMode: .warm),
        .init(id: "stone", name: "Stone", hex: "DAD8D2", accentMode: .system)
    ]

    private static let whiteHex = "FFFFFF"
    private static let minimumCardContrast: Double = 1.12
    private static let minimumCardDistance: Double = 0.12
    private static let minimumOverlayContrast: Double = 1.22
    private static let minimumOverlayDistance: Double = 0.16

    static func groupPanelStyle(isSelected: Bool) -> BWRCardBuddyGroupPanelStyleSnapshot {
        if isSelected {
            return BWRCardBuddyGroupPanelStyleSnapshot(
                cornerRadius: 28,
                fillHex: BWRCardBuddyCardShell.selectionHex,
                fillOpacity: 0.08,
                strokeHex: BWRCardBuddyCardShell.selectionHex,
                strokeOpacity: 0.42,
                strokeWidth: 1.6
            )
        }

        return BWRCardBuddyGroupPanelStyleSnapshot(
            cornerRadius: 28,
            fillHex: whiteHex,
            fillOpacity: 0.10,
            strokeHex: "2C251F",
            strokeOpacity: 0.10,
            strokeWidth: 1.0
        )
    }

    static func resolvedBoardBackgroundHex(for theme: BWRBoardThemeState) -> String? {
        normalizedHex(theme.boardBackgroundHex)
    }

    static func resolvedCardFillHex(cardHex: String?, boardHex: String?) -> String {
        let baseHex = BWRCardBuddyCardShell.resolvedFillHex(for: cardHex)
        guard let normalizedBoard = normalizedHex(boardHex) else {
            return baseHex
        }
        guard !isReadable(
            foregroundHex: baseHex,
            backgroundHex: normalizedBoard,
            minimumContrast: minimumCardContrast,
            minimumDistance: minimumCardDistance
        ) else {
            return baseHex
        }

        var candidate = baseHex
        for ratio in [0.24, 0.38, 0.52, 0.68, 0.82] {
            guard let blended = blendedHex(source: candidate, destination: whiteHex, ratio: ratio) else {
                continue
            }
            candidate = blended
            if isReadable(
                foregroundHex: candidate,
                backgroundHex: normalizedBoard,
                minimumContrast: minimumCardContrast,
                minimumDistance: minimumCardDistance
            ) {
                return candidate
            }
        }

        return whiteHex
    }

    static func isBoardSurfaceReadable(hex: String) -> Bool {
        let overlays = [
            BWRCardBuddyCardShell.selectionHex,
            "6B7280",
            "4B5563",
            "C77E2B"
        ]

        return overlays.allSatisfy { overlayHex in
            isReadable(
                foregroundHex: overlayHex,
                backgroundHex: hex,
                minimumContrast: minimumOverlayContrast,
                minimumDistance: minimumOverlayDistance
            )
        }
    }

    static func isCardReadable(cardHex: String, on boardHex: String?) -> Bool {
        guard let boardHex = normalizedHex(boardHex) else { return true }
        return isReadable(
            foregroundHex: cardHex,
            backgroundHex: boardHex,
            minimumContrast: minimumCardContrast,
            minimumDistance: minimumCardDistance
        )
    }

    static func normalizedHex(_ hex: String?) -> String? {
        guard let hex else { return nil }
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).uppercased()
        guard trimmed.count == 6, Int(trimmed, radix: 16) != nil else { return nil }
        return trimmed
    }

    @MainActor
    static func boardColor(for hex: String) -> Color {
        Color(hex: hex) ?? Color(nsColor: .controlBackgroundColor)
    }

    @MainActor
    static func cardSwatchPreviewColor(for hex: String, boardHex: String?) -> Color {
        boardColor(for: resolvedCardFillHex(cardHex: hex, boardHex: boardHex))
    }

    private static func isReadable(
        foregroundHex: String,
        backgroundHex: String,
        minimumContrast: Double,
        minimumDistance: Double
    ) -> Bool {
        guard let foreground = rgbComponents(hex: foregroundHex),
              let background = rgbComponents(hex: backgroundHex) else {
            return false
        }

        return contrastRatio(foreground, background) >= minimumContrast ||
            perceivedDistance(foreground, background) >= minimumDistance
    }

    private static func rgbComponents(hex: String) -> (r: Double, g: Double, b: Double)? {
        guard let value = Int(hex, radix: 16) else { return nil }
        return (
            r: Double((value >> 16) & 0xFF) / 255.0,
            g: Double((value >> 8) & 0xFF) / 255.0,
            b: Double(value & 0xFF) / 255.0
        )
    }

    private static func relativeLuminance(_ color: (r: Double, g: Double, b: Double)) -> Double {
        func channel(_ value: Double) -> Double {
            if value <= 0.03928 {
                return value / 12.92
            }
            return pow((value + 0.055) / 1.055, 2.4)
        }

        let red = channel(color.r)
        let green = channel(color.g)
        let blue = channel(color.b)
        return (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    }

    private static func contrastRatio(
        _ foreground: (r: Double, g: Double, b: Double),
        _ background: (r: Double, g: Double, b: Double)
    ) -> Double {
        let lhs = relativeLuminance(foreground)
        let rhs = relativeLuminance(background)
        let lighter = max(lhs, rhs)
        let darker = min(lhs, rhs)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func perceivedDistance(
        _ lhs: (r: Double, g: Double, b: Double),
        _ rhs: (r: Double, g: Double, b: Double)
    ) -> Double {
        let red = lhs.r - rhs.r
        let green = lhs.g - rhs.g
        let blue = lhs.b - rhs.b
        return sqrt((red * red) + (green * green) + (blue * blue))
    }

    private static func blendedHex(source: String, destination: String, ratio: Double) -> String? {
        guard let sourceComponents = rgbComponents(hex: source),
              let destinationComponents = rgbComponents(hex: destination) else {
            return nil
        }
        let clamped = min(max(ratio, 0), 1)
        let red = Int((destinationComponents.r + (sourceComponents.r - destinationComponents.r) * clamped) * 255.0)
        let green = Int((destinationComponents.g + (sourceComponents.g - destinationComponents.g) * clamped) * 255.0)
        let blue = Int((destinationComponents.b + (sourceComponents.b - destinationComponents.b) * clamped) * 255.0)
        return String(format: "%02X%02X%02X", red, green, blue)
    }
}
