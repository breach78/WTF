import SwiftUI
import AppKit

extension ScenarioWriterView {
    func resolvedIndexBoardLogicalState(
        from surfaceProjection: BoardSurfaceProjection
    ) -> IndexBoardLogicalState {
        let groupPositions = Dictionary(
            uniqueKeysWithValues: surfaceProjection.parentGroups.compactMap { placement in
                placement.parentCardID.map { ($0, placement.origin) }
            }
        )
        let detachedPositions = indexBoardDetachedGridPositionsByCardID(from: surfaceProjection)
        let canonicalTempStrips = indexBoardTempStrips(
            tempGroups: surfaceProjection.parentGroups.filter(\.isTempGroup),
            detachedPositionsByCardID: detachedPositions
        )

        return IndexBoardLogicalState(
            detachedGridPositionByCardID: detachedPositions,
            groupGridPositionByParentID: groupPositions,
            tempStrips: canonicalTempStrips
        )
    }

    func applyIndexBoardLogicalState(
        _ logicalState: IndexBoardLogicalState,
        persist: Bool
    ) {
        guard isIndexBoardActive else { return }

        indexBoardRuntime.updateSession(for: scenario.id, paneID: paneContextID, persist: false) { session in
            session.logical = logicalState
        }

        if persist {
            indexBoardRuntime.schedulePersistCurrentLogicalState(for: scenario.id, paneID: paneContextID)
        }
    }

    func persistIndexBoardSurfacePresentation(_ surfaceProjection: BoardSurfaceProjection) {
        applyIndexBoardLogicalState(
            resolvedIndexBoardLogicalState(from: surfaceProjection),
            persist: true
        )
    }

    var clampedIndexBoardZoomScale: CGFloat {
        let rawScale = activeIndexBoardSession?.zoomScale ?? IndexBoardZoom.defaultScale
        return min(max(rawScale, IndexBoardZoom.minScale), IndexBoardZoom.maxScale)
    }

    func setIndexBoardZoomScale(_ scale: CGFloat) {
        guard isIndexBoardActive else { return }
        let clamped = min(max(scale, IndexBoardZoom.minScale), IndexBoardZoom.maxScale)
        let rounded = (clamped * 100).rounded() / 100
        indexBoardRuntime.updateSession(for: scenario.id, paneID: paneContextID, persist: false) { session in
            guard abs(session.zoomScale - rounded) > 0.001 else { return }
            session.zoomScale = rounded
        }
    }

    func stepIndexBoardZoom(by delta: CGFloat) {
        setIndexBoardZoomScale(clampedIndexBoardZoomScale + delta)
    }

    func resetIndexBoardZoom() {
        setIndexBoardZoomScale(IndexBoardZoom.defaultScale)
    }

    func updateIndexBoardScrollOffset(_ offset: CGPoint) {
        guard isIndexBoardActive else { return }
        indexBoardRuntime.updateLiveViewport(
            for: scenario.id,
            paneID: paneContextID,
            scrollOffset: offset
        )
    }

    func persistIndexBoardViewport(zoomScale: CGFloat, scrollOffset: CGPoint) {
        indexBoardRuntime.persistViewport(
            zoomScale: zoomScale,
            scrollOffset: scrollOffset,
            for: scenario.id,
            paneID: paneContextID
        )
    }
}
