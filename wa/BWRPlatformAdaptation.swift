import Foundation
import CoreGraphics

nonisolated enum BWRWorkspaceLayoutMode: String, Sendable {
    case regular
    case compact

    static func resolve(for size: CGSize) -> BWRWorkspaceLayoutMode {
        guard size.width >= 1180, size.height >= 700 else {
            return .compact
        }
        return .regular
    }
}

nonisolated enum BWRFocusLayoutMode: String, Sendable {
    case regular
    case compact

    static func resolve(for size: CGSize) -> BWRFocusLayoutMode {
        guard size.width >= 1100, size.height >= 760 else {
            return .compact
        }
        return .regular
    }
}

nonisolated enum BWRBoardZoomController {
    static let minimumScale = 0.3
    static let maximumScale = 1.6
    static let step = 0.1

    static func zoomIn(from currentScale: Double) -> Double {
        clamped(currentScale + step)
    }

    static func zoomOut(from currentScale: Double) -> Double {
        clamped(currentScale - step)
    }

    static func reset() -> Double {
        1.0
    }

    private static func clamped(_ scale: Double) -> Double {
        min(max(scale, minimumScale), maximumScale)
    }
}

nonisolated extension BWRFocusModeKind {
    static func keyboardMapping(for characters: String) -> BWRFocusModeKind? {
        switch characters {
        case "1":
            return .currentLayer
        case "2":
            return .treatment
        case "3":
            return .scenario
        default:
            return nil
        }
    }
}
