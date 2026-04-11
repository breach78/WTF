import Foundation

nonisolated enum BWRCardBuddyCardShell {
    static let surface = BWRCardBuddySurfaceAuditLock.target
    static let selectionHex = BWRCardBuddySurfaceAuditLock.target.selectionColorHex

    private static let defaultPaperHex = "FFFFFF"
    private static let legacyPaperHex = "F8FAFC"
    private static let tintBlendRatio = 0.5

    static func preview(for markdown: String) -> BWRCardMarkdownPreviewRenderResult {
        BWRCardMarkdownPreviewRenderer.render(markdown, lineLimit: surface.visibleLineDensity)
    }

    static func resolvedFillHex(for colorHex: String?) -> String {
        guard let normalized = normalizedHex(colorHex) else {
            return defaultPaperHex
        }
        guard normalized != defaultPaperHex, normalized != legacyPaperHex else {
            return defaultPaperHex
        }
        return blendedHex(source: normalized, destination: defaultPaperHex, ratio: tintBlendRatio) ?? defaultPaperHex
    }

    private static func normalizedHex(_ hex: String?) -> String? {
        guard let hex else { return nil }
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).uppercased()
        guard trimmed.count == 6, Int(trimmed, radix: 16) != nil else { return nil }
        return trimmed
    }

    private static func blendedHex(source: String, destination: String, ratio: Double) -> String? {
        guard let sourceValue = Int(source, radix: 16),
              let destinationValue = Int(destination, radix: 16) else {
            return nil
        }

        let red = blendedComponent(
            source: (sourceValue >> 16) & 0xFF,
            destination: (destinationValue >> 16) & 0xFF,
            ratio: ratio
        )
        let green = blendedComponent(
            source: (sourceValue >> 8) & 0xFF,
            destination: (destinationValue >> 8) & 0xFF,
            ratio: ratio
        )
        let blue = blendedComponent(
            source: sourceValue & 0xFF,
            destination: destinationValue & 0xFF,
            ratio: ratio
        )

        return String(format: "%02X%02X%02X", red, green, blue)
    }

    private static func blendedComponent(source: Int, destination: Int, ratio: Double) -> Int {
        let clampedRatio = min(max(ratio, 0), 1)
        let sourceValue = Double(source)
        let destinationValue = Double(destination)
        return Int((destinationValue + (sourceValue - destinationValue) * clampedRatio).rounded())
    }
}
