import Combine
import Foundation
import SwiftUI

@MainActor
final class MainWorkspaceScrollDriver: ObservableObject {
    private(set) var activeGeneration: Int = 0
    private(set) var activeCardID: UUID? = nil

    private var deferredApplyWorkItem: DispatchWorkItem? = nil
    private var verifyWorkItem: DispatchWorkItem? = nil
    private var deferredApplyGeneration: Int? = nil
    private var pendingMissingViewportKeys: Set<String> = []

    func reset() {
        deferredApplyWorkItem?.cancel()
        deferredApplyWorkItem = nil
        verifyWorkItem?.cancel()
        verifyWorkItem = nil
        deferredApplyGeneration = nil
        pendingMissingViewportKeys = []
        activeGeneration = 0
        activeCardID = nil
    }

    func begin(plan: MainWorkspaceScrollPlan) {
        deferredApplyWorkItem?.cancel()
        deferredApplyWorkItem = nil
        verifyWorkItem?.cancel()
        verifyWorkItem = nil
        deferredApplyGeneration = nil
        pendingMissingViewportKeys = []
        activeGeneration = plan.generation
        activeCardID = plan.activeCardID
    }

    func isCurrent(_ plan: MainWorkspaceScrollPlan) -> Bool {
        activeGeneration == plan.generation && activeCardID == plan.activeCardID
    }

    func hasPendingWork(for cardID: UUID?) -> Bool {
        guard let cardID else { return false }
        guard activeCardID == cardID else { return false }
        return deferredApplyWorkItem != nil || verifyWorkItem != nil
    }

    func setPendingMissingViewportKeys(
        _ viewportKeys: [String],
        for plan: MainWorkspaceScrollPlan
    ) {
        guard isCurrent(plan) else { return }
        pendingMissingViewportKeys = Set(viewportKeys)
    }

    func hasPendingMissingViewportKeys(for plan: MainWorkspaceScrollPlan) -> Bool {
        guard isCurrent(plan) else { return false }
        return !pendingMissingViewportKeys.isEmpty
    }

    func scheduleDeferredApply(
        for plan: MainWorkspaceScrollPlan,
        action: @escaping () -> Void
    ) {
        guard deferredApplyGeneration != plan.generation else { return }
        deferredApplyWorkItem?.cancel()
        deferredApplyGeneration = plan.generation
        let workItem = DispatchWorkItem { [weak self] in
            defer {
                self?.deferredApplyWorkItem = nil
                if self?.deferredApplyGeneration == plan.generation {
                    self?.deferredApplyGeneration = nil
                }
            }
            guard self?.isCurrent(plan) == true else { return }
            action()
        }
        deferredApplyWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    func scheduleSingleVerify(
        for plan: MainWorkspaceScrollPlan,
        delay: TimeInterval,
        action: @escaping () -> Void
    ) {
        verifyWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            defer { self?.verifyWorkItem = nil }
            guard self?.isCurrent(plan) == true else { return }
            action()
        }
        verifyWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
