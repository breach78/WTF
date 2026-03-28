import SwiftUI

// Compatibility Contract
// Active board rendering lives in IndexBoardSurfaceAppKitPhaseTwoView.
// This alias exists only to preserve legacy fallback call sites while the
// SwiftUI surface is frozen and queued for deletion review on 2026-04-11.
@available(
    *,
    deprecated,
    message: "Compatibility fallback only. Use IndexBoardSurfaceAppKitPhaseTwoView for the active board surface."
)
typealias IndexBoardSurfacePhaseTwoView = IndexBoardSurfaceCompatFallbackView
