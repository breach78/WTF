import Foundation
import Combine
import SwiftUI

@MainActor
final class MainWorkspaceSurfaceController: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    private weak var surfaceView: MainWorkspaceSurfaceView?
    private var hasAppeared = false
    private var lastNavigationFingerprint: Int?
    private var lastContentFingerprint: Int?
    private var lastRestoreFingerprint: Int?

    func attach(surfaceView: MainWorkspaceSurfaceView) {
        self.surfaceView = surfaceView
    }

    func reconnectSurfaceIfAttached() {
        surfaceView?.reconnectScrollCoordinator()
    }

    func reset() {
        hasAppeared = false
        lastNavigationFingerprint = nil
        lastContentFingerprint = nil
        lastRestoreFingerprint = nil
    }

    func rectForCard(viewportKey: String, cardID: UUID) -> CGRect? {
        surfaceView?.rectForCard(viewportKey: viewportKey, cardID: cardID)
    }

    func viewportRect(for viewportKey: String) -> CGRect? {
        surfaceView?.viewportRect(for: viewportKey)
    }

    func apply(
        snapshot: MainWorkspaceSnapshot,
        renderState: MainWorkspaceSurfaceRenderState,
        callbacks: MainWorkspaceSurfaceCallbacks
    ) {
        guard let surfaceView else { return }

        surfaceView.apply(
            snapshot: snapshot,
            callbacks: callbacks
        )
        surfaceView.schedulePostApplyRefresh()

        if !hasAppeared {
            hasAppeared = true
            callbacks.onAppear(snapshot.availableWidth)
        } else {
            if lastNavigationFingerprint != renderState.navigationFingerprint {
                callbacks.onNavigation(snapshot.availableWidth)
            }
            if lastRestoreFingerprint != renderState.restoreFingerprint {
                callbacks.onRestore(snapshot.availableWidth)
            } else if renderState.hasPendingRestoreRequest,
                      lastContentFingerprint != renderState.contentFingerprint {
                callbacks.onRestore(snapshot.availableWidth)
            }
        }

        lastNavigationFingerprint = renderState.navigationFingerprint
        lastContentFingerprint = renderState.contentFingerprint
        lastRestoreFingerprint = renderState.restoreFingerprint
    }
}
