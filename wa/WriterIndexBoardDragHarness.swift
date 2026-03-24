import Foundation
import CoreGraphics

#if DEBUG
enum IndexBoardGroupActivationHarness {
    enum Mode: String {
        case groupSlot
        case groupBlock
        case detached
    }

    struct CaseResult {
        let name: String
        let legacy: Mode
        let resolved: Mode
        let expected: Mode
    }

    private static let blockFrame = CGRect(x: 100, y: 100, width: 320, height: 210)
    private static let slotFrame = CGRect(x: 132, y: 136, width: 256, height: 142)

    private static func legacyMode(for point: CGPoint) -> Mode {
        slotFrame.contains(point) ? .groupSlot : .detached
    }

    private static func expectedMode(for point: CGPoint) -> Mode {
        if slotFrame.contains(point) {
            return .groupSlot
        }
        if blockFrame.contains(point) {
            return .groupBlock
        }
        return .detached
    }

    @MainActor
    static func run() {
        let points: [(String, CGPoint)] = [
            ("slot_inside", CGPoint(x: 220, y: 190)),
            ("block_only_left_edge", CGPoint(x: 114, y: 190)),
            ("slot_inside_again", CGPoint(x: 220, y: 190)),
            ("block_only_top_edge", CGPoint(x: 220, y: 112)),
            ("boundary_before_entry", CGPoint(x: 128, y: 190)),
            ("boundary_after_entry", CGPoint(x: 136, y: 190)),
            ("shake_left_1", CGPoint(x: 118, y: 190)),
            ("shake_right_1", CGPoint(x: 138, y: 190)),
            ("shake_left_2", CGPoint(x: 120, y: 190)),
            ("shake_right_2", CGPoint(x: 140, y: 190)),
            ("outside_block", CGPoint(x: 60, y: 60))
        ]

        let results: [CaseResult] = points.map { name, point in
            let resolved = Mode(
                rawValue: resolvedIndexBoardGroupHoverTargetMode(
                    point: point,
                    slotEntryFrame: slotFrame,
                    activationFrame: blockFrame
                ).rawValue
            ) ?? .detached
            return CaseResult(
                name: name,
                legacy: legacyMode(for: point),
                resolved: resolved,
                expected: expectedMode(for: point)
            )
        }

        let reproducedFailure = results.contains { result in
            result.expected == .groupBlock && result.legacy == .detached
        }
        let fixedPass = results.allSatisfy { $0.resolved == $0.expected }
        let detachedInsideActivation = results.contains { result in
            result.expected != .detached && result.resolved == .detached
        }

        print("GROUP_ACTIVATION_HARNESS_BEGIN")
        for result in results {
            print("case=\(result.name) legacy=\(result.legacy.rawValue) resolved=\(result.resolved.rawValue) expected=\(result.expected.rawValue)")
        }
        print("reproduced_failure=\(reproducedFailure)")
        print("fixed_pass=\(fixedPass)")
        print("detached_inside_activation=\(detachedInsideActivation)")
        print("GROUP_ACTIVATION_HARNESS_END")
    }
}
#endif
