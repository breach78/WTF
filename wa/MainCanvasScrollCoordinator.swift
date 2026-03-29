import AppKit
import Combine
import Foundation

@MainActor
final class MainCanvasScrollCoordinator: ObservableObject {
    /*
     Root motion session lifecycle

         idle
          |
          | publish focus intent
          v
      collecting <-------------------------------+
       |   ^                                     |
       |   | supersede focus intent              |
       |   +-------------------------------------+
       |
       | settle recovery begins
       v
      settling
       |   \
       |    \ timeout
       |     \
       |      v
       |   timedOut(close)
       |
       | all admitted participants terminal
       v
      closed -> idle

     Participant terminal contract:
     waiting -> moving -> aligned
                 |         ^
                 |         |
                 +-> timedOut
                 +-> cancelled
     */

    struct MainColumnGeometryModel {
        var observedFramesByCardID: [UUID: CGRect] = [:]

        var hasObservedFrames: Bool {
            !observedFramesByCardID.isEmpty
        }

        func observedFrame(for cardID: UUID) -> CGRect? {
            observedFramesByCardID[cardID]
        }
    }

    enum NavigationIntentKind: String {
        case focusChange
        case settleRecovery
        case childListChange
        case columnAppear
        case bottomReveal
    }

    enum NavigationIntentScope: Equatable {
        case allColumns
        case viewport(String)
    }

    enum MotionGoal: Equatable {
        case alignToAnchor(cardID: UUID?)
        case bottomReveal(cardID: UUID?)
    }

    enum MotionParticipantAxis: String {
        case vertical
        case horizontal
    }

    enum MotionParticipantState: String {
        case waiting
        case moving
        case aligned
        case timedOut
        case cancelled

        var isTerminal: Bool {
            switch self {
            case .aligned, .timedOut, .cancelled:
                return true
            case .waiting, .moving:
                return false
            }
        }
    }

    enum MotionTaskKind: String {
        case focus
        case verification
    }

    enum MotionCorrectionGateReason: String, Equatable {
        case quietWindow
        case sessionClose
    }

    struct MotionPolicy {
        let activeFocusAnimatedDispatchDelay: TimeInterval
        let activeFocusNonAnimatedDispatchDelay: TimeInterval
        let descendantJoinDelay: TimeInterval
        let navigationSettleDelay: TimeInterval
        let sessionTimeout: TimeInterval
        let correctionGateQuietWindowDelay: TimeInterval

        init(
            activeFocusAnimatedDispatchDelay: TimeInterval = 0.01,
            activeFocusNonAnimatedDispatchDelay: TimeInterval = 0.0,
            descendantJoinDelay: TimeInterval = 0.10,
            navigationSettleDelay: TimeInterval = 0.08,
            sessionTimeout: TimeInterval = 0.65,
            correctionGateQuietWindowDelay: TimeInterval = 0.12
        ) {
            self.activeFocusAnimatedDispatchDelay = activeFocusAnimatedDispatchDelay
            self.activeFocusNonAnimatedDispatchDelay = activeFocusNonAnimatedDispatchDelay
            self.descendantJoinDelay = descendantJoinDelay
            self.navigationSettleDelay = navigationSettleDelay
            self.sessionTimeout = sessionTimeout
            self.correctionGateQuietWindowDelay = correctionGateQuietWindowDelay
        }

        func activeFocusDelay(animated: Bool) -> TimeInterval {
            animated ? activeFocusAnimatedDispatchDelay : activeFocusNonAnimatedDispatchDelay
        }

        func verificationDelay(animated: Bool, attempt: Int) -> TimeInterval {
            if animated {
                return attempt == 0 ? 0.18 : 0.10
            }
            return attempt == 0 ? 0.05 : 0.08
        }
    }

    struct MotionParticipantHandle: Equatable {
        let sessionID: Int
        let revision: Int
        let axis: MotionParticipantAxis
        let viewportKey: String
    }

    struct ActiveMotionSessionSnapshot: Equatable {
        let sessionID: Int
        let revision: Int
        let currentIntentID: Int
        let goal: MotionGoal
        let joinWindowOpen: Bool
    }

    struct MotionCorrectionGateSnapshot: Equatable {
        let serial: Int
        let sessionID: Int
        let revision: Int
        let reason: MotionCorrectionGateReason
    }

    struct NavigationIntent: Equatable {
        let id: Int
        let kind: NavigationIntentKind
        let scope: NavigationIntentScope
        let targetCardID: UUID?
        let expectedActiveCardID: UUID?
        let animated: Bool
        let trigger: String
        let sessionID: Int
        let sessionRevision: Int
        let motionGoal: MotionGoal
    }

    private final class ScrollViewEntry {
        weak var scrollView: NSScrollView?

        init(scrollView: NSScrollView) {
            self.scrollView = scrollView
        }
    }

    private enum MotionSessionLifecycle {
        case collecting
        case settling
    }

    private struct MotionParticipantKey: Hashable {
        let axis: MotionParticipantAxis
        let viewportKey: String
    }

    private struct MotionParticipantRecord {
        var state: MotionParticipantState
        var hasObservedGeometry: Bool
    }

    private struct MotionTaskKey: Hashable {
        let participant: MotionParticipantKey
        let kind: MotionTaskKind
    }

    private struct MotionSessionRecord {
        let id: Int
        var revision: Int
        var currentIntentID: Int
        var goal: MotionGoal
        var lifecycle: MotionSessionLifecycle
        var joinWindowOpen: Bool
        var participants: [MotionParticipantKey: MotionParticipantRecord]
        var timeoutWorkItem: DispatchWorkItem?
        var correctionGateQuietWorkItem: DispatchWorkItem?
    }

    @Published private(set) var navigationIntentTick: Int = 0
    @Published private(set) var motionSessionCloseTick: Int = 0
    @Published private(set) var motionCorrectionGateTick: Int = 0

    let motionPolicy: MotionPolicy

    private let scheduleMotionWorkItem: MotionWorkScheduler

    private var intentSequence: Int = 0
    private var latestGlobalIntent: NavigationIntent?
    private var latestScopedIntentByViewportKey: [String: NavigationIntent] = [:]
    private var lastConsumedIntentIDByViewportKey: [String: Int] = [:]
    private var scrollViewEntriesByViewportKey: [String: ScrollViewEntry] = [:]
    private var geometryModelByViewportKey: [String: MainColumnGeometryModel] = [:]
    private weak var mainCanvasHorizontalScrollView: NSScrollView?
    private var mainCanvasHorizontalOffsetSnapshot: CGFloat?
    private var pendingMainCanvasHorizontalRestoreX: CGFloat?
    private var motionSessionSequence: Int = 0
    private var motionCorrectionGateSequence: Int = 0
    private var activeMotionSession: MotionSessionRecord?
    private var latestMotionCorrectionGate: MotionCorrectionGateSnapshot?
    private var consumedMotionCorrectionSessionIDs: Set<Int> = []
    private var scheduledMotionTasks: [MotionTaskKey: DispatchWorkItem] = [:]

    init(
        motionPolicy: MotionPolicy = MotionPolicy(),
        scheduleMotionWorkItem: @escaping MotionWorkScheduler = { delay, workItem in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    ) {
        self.motionPolicy = motionPolicy
        self.scheduleMotionWorkItem = scheduleMotionWorkItem
    }

    func reset() {
        cancelActiveMotionSession(reason: "reset")
        intentSequence = 0
        navigationIntentTick = 0
        motionSessionCloseTick = 0
        motionCorrectionGateTick = 0
        latestGlobalIntent = nil
        latestScopedIntentByViewportKey = [:]
        lastConsumedIntentIDByViewportKey = [:]
        geometryModelByViewportKey = [:]
        mainCanvasHorizontalScrollView = nil
        mainCanvasHorizontalOffsetSnapshot = nil
        pendingMainCanvasHorizontalRestoreX = nil
        latestMotionCorrectionGate = nil
        consumedMotionCorrectionSessionIDs.removeAll(keepingCapacity: false)
        pruneReleasedScrollViews()
    }

    @discardableResult
    func publishIntent(
        kind: NavigationIntentKind,
        scope: NavigationIntentScope,
        targetCardID: UUID? = nil,
        expectedActiveCardID: UUID? = nil,
        animated: Bool,
        trigger: String
    ) -> NavigationIntent {
        intentSequence &+= 1
        let goal = resolvedMotionGoal(
            kind: kind,
            targetCardID: targetCardID,
            expectedActiveCardID: expectedActiveCardID
        )
        let session = transitionMotionSession(
            for: kind,
            goal: goal,
            intentID: intentSequence
        )
        let intent = NavigationIntent(
            id: intentSequence,
            kind: kind,
            scope: scope,
            targetCardID: targetCardID,
            expectedActiveCardID: expectedActiveCardID,
            animated: animated,
            trigger: trigger,
            sessionID: session.id,
            sessionRevision: session.revision,
            motionGoal: goal
        )

        switch scope {
        case .allColumns:
            latestGlobalIntent = intent
        case .viewport(let viewportKey):
            latestScopedIntentByViewportKey[viewportKey] = intent
        }

        navigationIntentTick &+= 1
        return intent
    }

    func consumeLatestIntent(for viewportKey: String) -> NavigationIntent? {
        guard let intent = latestRelevantIntent(for: viewportKey) else { return nil }
        if lastConsumedIntentIDByViewportKey[viewportKey] == intent.id {
            return nil
        }
        lastConsumedIntentIDByViewportKey[viewportKey] = intent.id
        return intent
    }

    func activeMotionSessionSnapshot() -> ActiveMotionSessionSnapshot? {
        guard let session = activeMotionSession else { return nil }
        return ActiveMotionSessionSnapshot(
            sessionID: session.id,
            revision: session.revision,
            currentIntentID: session.currentIntentID,
            goal: session.goal,
            joinWindowOpen: session.joinWindowOpen
        )
    }

    func hasActiveMotionSession() -> Bool {
        activeMotionSession != nil
    }

    func motionCorrectionGateSnapshot() -> MotionCorrectionGateSnapshot? {
        latestMotionCorrectionGate
    }

    func consumeMotionCorrectionBudget(forSessionID sessionID: Int) -> Bool {
        guard !consumedMotionCorrectionSessionIDs.contains(sessionID) else { return false }
        consumedMotionCorrectionSessionIDs.insert(sessionID)
        return true
    }

    func claimMotionParticipant(
        for viewportKey: String,
        axis: MotionParticipantAxis,
        intent: NavigationIntent
    ) -> MotionParticipantHandle? {
        guard var session = activeMotionSession,
              session.id == intent.sessionID,
              session.revision == intent.sessionRevision else {
            return nil
        }

        let key = MotionParticipantKey(axis: axis, viewportKey: viewportKey)
        let hasObservedGeometry: Bool
        switch axis {
        case .vertical:
            hasObservedGeometry = geometryModelByViewportKey[viewportKey]?.hasObservedFrames ?? false
        case .horizontal:
            hasObservedGeometry = true
        }

        var participant = session.participants[key] ?? MotionParticipantRecord(
            state: hasObservedGeometry ? .moving : .waiting,
            hasObservedGeometry: hasObservedGeometry
        )
        if hasObservedGeometry {
            participant.hasObservedGeometry = true
            if participant.state == .waiting {
                participant.state = .moving
            }
        } else if !participant.hasObservedGeometry {
            participant.state = .waiting
        }
        session.participants[key] = participant
        activeMotionSession = session

        return MotionParticipantHandle(
            sessionID: session.id,
            revision: session.revision,
            axis: axis,
            viewportKey: viewportKey
        )
    }

    func isMotionParticipantCurrent(_ handle: MotionParticipantHandle?) -> Bool {
        guard let handle, let session = activeMotionSession else { return true }
        guard session.id == handle.sessionID, session.revision == handle.revision else {
            return false
        }
        let key = MotionParticipantKey(axis: handle.axis, viewportKey: handle.viewportKey)
        return session.participants[key] != nil
    }

    func updateMotionParticipantState(
        _ state: MotionParticipantState,
        handle: MotionParticipantHandle?
    ) {
        guard let handle,
              var session = activeMotionSession,
              session.id == handle.sessionID,
              session.revision == handle.revision else {
            return
        }

        let key = MotionParticipantKey(axis: handle.axis, viewportKey: handle.viewportKey)
        guard var participant = session.participants[key] else { return }
        participant.state = state
        if state != .waiting {
            participant.hasObservedGeometry = true
        }
        session.participants[key] = participant
        activeMotionSession = session
        closeActiveMotionSessionIfFinished()
    }

    func replaceMotionTask(
        _ workItem: DispatchWorkItem,
        kind: MotionTaskKind,
        handle: MotionParticipantHandle?
    ) {
        guard let key = motionTaskKey(for: kind, handle: handle),
              isMotionParticipantCurrent(handle) else {
            workItem.cancel()
            return
        }
        scheduledMotionTasks[key]?.cancel()
        scheduledMotionTasks[key] = workItem
    }

    func clearMotionTask(
        kind: MotionTaskKind,
        handle: MotionParticipantHandle?
    ) {
        guard let key = motionTaskKey(for: kind, handle: handle) else { return }
        scheduledMotionTasks.removeValue(forKey: key)
    }

    func cancelMotionTask(
        axis: MotionParticipantAxis,
        viewportKey: String,
        kind: MotionTaskKind
    ) {
        let participant = MotionParticipantKey(axis: axis, viewportKey: viewportKey)
        let key = MotionTaskKey(participant: participant, kind: kind)
        scheduledMotionTasks[key]?.cancel()
        scheduledMotionTasks.removeValue(forKey: key)
    }

    func cancelActiveMotionSession(reason: String) {
        guard var session = activeMotionSession else { return }
        cancelCorrectionGateQuietWorkItem(for: &session)
        for key in session.participants.keys {
            var participant = session.participants[key]
            participant?.state = .cancelled
            session.participants[key] = participant
            cancelScheduledMotionTasks(for: key)
        }
        cancelTimeoutWorkItem(for: &session)
        activeMotionSession = nil
        finalizeMotionSessionClose()
    }

    func closeJoinWindowIfCurrentSessionMatches(_ handle: MotionParticipantHandle?) {
        guard let handle,
              var session = activeMotionSession,
              session.id == handle.sessionID,
              session.revision == handle.revision else {
            return
        }
        cancelCorrectionGateQuietWorkItem(for: &session)
        session.joinWindowOpen = false
        session.lifecycle = .settling
        activeMotionSession = session
    }

    func updateActiveMotionGoal(_ goal: MotionGoal) {
        guard var session = activeMotionSession else { return }
        session.goal = goal
        activeMotionSession = session
    }

    func register(scrollView: NSScrollView, for viewportKey: String) {
        scrollViewEntriesByViewportKey[viewportKey] = ScrollViewEntry(scrollView: scrollView)
        pruneReleasedScrollViews()
    }

    func unregister(viewportKey: String, matching scrollView: NSScrollView? = nil) {
        guard let entry = scrollViewEntriesByViewportKey[viewportKey] else { return }
        if let scrollView {
            guard entry.scrollView === scrollView else { return }
        }
        scrollViewEntriesByViewportKey.removeValue(forKey: viewportKey)
        geometryModelByViewportKey.removeValue(forKey: viewportKey)
    }

    func scrollView(for viewportKey: String) -> NSScrollView? {
        if let scrollView = scrollViewEntriesByViewportKey[viewportKey]?.scrollView {
            return scrollView
        }
        scrollViewEntriesByViewportKey.removeValue(forKey: viewportKey)
        return nil
    }

    func hasRegisteredScrollView(for viewportKey: String) -> Bool {
        scrollView(for: viewportKey) != nil
    }

    func updateObservedFrames(_ frames: [UUID: CGRect], for viewportKey: String) {
        geometryModelByViewportKey[viewportKey] = MainColumnGeometryModel(observedFramesByCardID: frames)
        guard !frames.isEmpty,
              var session = activeMotionSession else {
            return
        }
        let key = MotionParticipantKey(axis: .vertical, viewportKey: viewportKey)
        guard var participant = session.participants[key] else { return }
        participant.hasObservedGeometry = true
        if participant.state == .waiting {
            participant.state = .moving
        }
        session.participants[key] = participant
        activeMotionSession = session
    }

    func observedFrame(for viewportKey: String, cardID: UUID) -> CGRect? {
        geometryModelByViewportKey[viewportKey]?.observedFrame(for: cardID)
    }

    func geometryModel(for viewportKey: String) -> MainColumnGeometryModel? {
        geometryModelByViewportKey[viewportKey]
    }

    func registerMainCanvasHorizontalScrollView(_ scrollView: NSScrollView) {
        mainCanvasHorizontalScrollView = scrollView
        mainCanvasHorizontalOffsetSnapshot = max(0, scrollView.contentView.bounds.origin.x)
        indexBoardRestoreTrace(
            "coordinator_register_horizontal_scroll_view",
            "offset=\(debugRestoreCGFloat(scrollView.contentView.bounds.origin.x)) " +
            "visibleWidth=\(String(format: "%.2f", scrollView.documentVisibleRect.width)) " +
            "documentWidth=\(String(format: "%.2f", scrollView.documentView?.bounds.width ?? 0))"
        )
        applyPendingMainCanvasHorizontalRestoreIfNeeded(to: scrollView)
    }

    func unregisterMainCanvasHorizontalScrollView(matching scrollView: NSScrollView? = nil) {
        guard let current = mainCanvasHorizontalScrollView else { return }
        if let scrollView {
            guard current === scrollView else { return }
        }
        mainCanvasHorizontalScrollView = nil
    }

    func resolvedMainCanvasHorizontalScrollView() -> NSScrollView? {
        mainCanvasHorizontalScrollView
    }

    func updateMainCanvasHorizontalOffset(_ offsetX: CGFloat) {
        mainCanvasHorizontalOffsetSnapshot = max(0, offsetX)
    }

    func resolvedMainCanvasHorizontalOffset() -> CGFloat? {
        if let scrollView = mainCanvasHorizontalScrollView {
            let liveOffset = max(0, scrollView.contentView.bounds.origin.x)
            mainCanvasHorizontalOffsetSnapshot = liveOffset
            return liveOffset
        }
        return mainCanvasHorizontalOffsetSnapshot
    }

    func refreshMainCanvasHorizontalScrollViewState(_ scrollView: NSScrollView) {
        guard mainCanvasHorizontalScrollView === scrollView else { return }
        mainCanvasHorizontalOffsetSnapshot = max(0, scrollView.contentView.bounds.origin.x)
        applyPendingMainCanvasHorizontalRestoreIfNeeded(to: scrollView)
    }

    func scheduleMainCanvasHorizontalRestore(offsetX: CGFloat) {
        pendingMainCanvasHorizontalRestoreX = max(0, offsetX)
        indexBoardRestoreTrace(
            "coordinator_schedule_horizontal_restore",
            "targetOffset=\(debugRestoreCGFloat(offsetX)) hasLiveScrollView=\(self.mainCanvasHorizontalScrollView != nil) " +
            "sessionActive=\(self.activeMotionSession != nil)"
        )
        guard activeMotionSession == nil else { return }
        if let scrollView = mainCanvasHorizontalScrollView {
            applyPendingMainCanvasHorizontalRestoreIfNeeded(to: scrollView)
        }
    }

    private func latestRelevantIntent(for viewportKey: String) -> NavigationIntent? {
        let scopedIntent = latestScopedIntentByViewportKey[viewportKey]
        switch (latestGlobalIntent, scopedIntent) {
        case let (global?, scoped?):
            return scoped.id >= global.id ? scoped : global
        case let (global?, nil):
            return global
        case let (nil, scoped?):
            return scoped
        case (nil, nil):
            return nil
        }
    }

    private func resolvedMotionGoal(
        kind: NavigationIntentKind,
        targetCardID: UUID?,
        expectedActiveCardID: UUID?
    ) -> MotionGoal {
        switch kind {
        case .bottomReveal:
            return .bottomReveal(cardID: targetCardID ?? expectedActiveCardID)
        case .focusChange, .settleRecovery, .childListChange, .columnAppear:
            return .alignToAnchor(cardID: targetCardID ?? expectedActiveCardID)
        }
    }

    private func transitionMotionSession(
        for kind: NavigationIntentKind,
        goal: MotionGoal,
        intentID: Int
    ) -> MotionSessionRecord {
        switch kind {
        case .focusChange:
            if var session = activeMotionSession {
                cancelAllScheduledMotionTasks()
                cancelTimeoutWorkItem(for: &session)
                cancelCorrectionGateQuietWorkItem(for: &session)
                session.revision &+= 1
                session.currentIntentID = intentID
                session.goal = goal
                session.lifecycle = .collecting
                session.joinWindowOpen = true
                session.participants.removeAll(keepingCapacity: true)
                scheduleTimeoutWorkItem(for: &session)
                scheduleCorrectionGateQuietWorkItem(for: &session)
                activeMotionSession = session
                return session
            }
            var session = startMotionSession(goal: goal, intentID: intentID)
            scheduleCorrectionGateQuietWorkItem(for: &session)
            activeMotionSession = session
            return session

        case .settleRecovery:
            if var session = activeMotionSession {
                cancelTimeoutWorkItem(for: &session)
                cancelCorrectionGateQuietWorkItem(for: &session)
                session.currentIntentID = intentID
                session.goal = goal
                session.lifecycle = .settling
                session.joinWindowOpen = false
                scheduleTimeoutWorkItem(for: &session)
                activeMotionSession = session
                return session
            }
            var session = startMotionSession(goal: goal, intentID: intentID)
            session.lifecycle = .settling
            session.joinWindowOpen = false
            activeMotionSession = session
            return session

        case .childListChange, .columnAppear, .bottomReveal:
            if var session = activeMotionSession {
                session.currentIntentID = intentID
                if kind == .bottomReveal {
                    session.goal = goal
                }
                cancelCorrectionGateQuietWorkItem(for: &session)
                if session.lifecycle == .collecting {
                    scheduleCorrectionGateQuietWorkItem(for: &session)
                }
                activeMotionSession = session
                return session
            }
            return startMotionSession(goal: goal, intentID: intentID)
        }
    }

    private func startMotionSession(
        goal: MotionGoal,
        intentID: Int
    ) -> MotionSessionRecord {
        motionSessionSequence &+= 1
        var session = MotionSessionRecord(
            id: motionSessionSequence,
            revision: 1,
            currentIntentID: intentID,
            goal: goal,
            lifecycle: .collecting,
            joinWindowOpen: true,
            participants: [:],
            timeoutWorkItem: nil,
            correctionGateQuietWorkItem: nil
        )
        scheduleTimeoutWorkItem(for: &session)
        activeMotionSession = session
        return session
    }

    private func scheduleTimeoutWorkItem(for session: inout MotionSessionRecord) {
        let sessionID = session.id
        let revision = session.revision
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.handleMotionSessionTimeout(sessionID: sessionID, revision: revision)
            }
        }
        session.timeoutWorkItem = workItem
        scheduleMotionWorkItem(motionPolicy.sessionTimeout, workItem)
    }

    private func cancelTimeoutWorkItem(for session: inout MotionSessionRecord) {
        session.timeoutWorkItem?.cancel()
        session.timeoutWorkItem = nil
    }

    private func scheduleCorrectionGateQuietWorkItem(for session: inout MotionSessionRecord) {
        cancelCorrectionGateQuietWorkItem(for: &session)
        guard session.lifecycle == .collecting else { return }
        guard !consumedMotionCorrectionSessionIDs.contains(session.id) else { return }

        let sessionID = session.id
        let revision = session.revision
        let currentIntentID = session.currentIntentID
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.handleCorrectionGateQuietWindow(
                    sessionID: sessionID,
                    revision: revision,
                    intentID: currentIntentID
                )
            }
        }
        session.correctionGateQuietWorkItem = workItem
        scheduleMotionWorkItem(motionPolicy.correctionGateQuietWindowDelay, workItem)
    }

    private func cancelCorrectionGateQuietWorkItem(for session: inout MotionSessionRecord) {
        session.correctionGateQuietWorkItem?.cancel()
        session.correctionGateQuietWorkItem = nil
    }

    private func handleCorrectionGateQuietWindow(
        sessionID: Int,
        revision: Int,
        intentID: Int
    ) {
        guard var session = activeMotionSession,
              session.id == sessionID,
              session.revision == revision,
              session.currentIntentID == intentID,
              session.lifecycle == .collecting else {
            return
        }
        session.correctionGateQuietWorkItem = nil
        activeMotionSession = session
        publishMotionCorrectionGate(
            sessionID: sessionID,
            revision: revision,
            reason: .quietWindow
        )
    }

    private func handleMotionSessionTimeout(sessionID: Int, revision: Int) {
        guard var session = activeMotionSession,
              session.id == sessionID,
              session.revision == revision else {
            return
        }

        for key in session.participants.keys {
            guard var participant = session.participants[key],
                  !participant.state.isTerminal else {
                continue
            }
            participant.state = .timedOut
            session.participants[key] = participant
            cancelScheduledMotionTasks(for: key)
        }
        cancelCorrectionGateQuietWorkItem(for: &session)
        cancelTimeoutWorkItem(for: &session)
        activeMotionSession = session
        closeActiveMotionSessionIfFinished(force: true)
    }

    private func closeActiveMotionSessionIfFinished(force: Bool = false) {
        guard var session = activeMotionSession else { return }
        let participants = Array(session.participants.values)
        let shouldClose = force || (!participants.isEmpty && participants.allSatisfy { $0.state.isTerminal })
        guard shouldClose else { return }
        let sessionID = session.id
        let revision = session.revision
        cancelCorrectionGateQuietWorkItem(for: &session)
        cancelTimeoutWorkItem(for: &session)
        cancelAllScheduledMotionTasks()
        activeMotionSession = nil
        finalizeMotionSessionClose(sessionID: sessionID, revision: revision)
    }

    private func motionTaskKey(
        for kind: MotionTaskKind,
        handle: MotionParticipantHandle?
    ) -> MotionTaskKey? {
        guard let handle else { return nil }
        let participant = MotionParticipantKey(axis: handle.axis, viewportKey: handle.viewportKey)
        return MotionTaskKey(participant: participant, kind: kind)
    }

    private func cancelScheduledMotionTasks(for participant: MotionParticipantKey) {
        let matchingKeys = scheduledMotionTasks.keys.filter { $0.participant == participant }
        for key in matchingKeys {
            scheduledMotionTasks[key]?.cancel()
            scheduledMotionTasks.removeValue(forKey: key)
        }
    }

    private func cancelAllScheduledMotionTasks() {
        for key in scheduledMotionTasks.keys {
            scheduledMotionTasks[key]?.cancel()
        }
        scheduledMotionTasks.removeAll(keepingCapacity: false)
    }

    private func pruneReleasedScrollViews() {
        scrollViewEntriesByViewportKey = scrollViewEntriesByViewportKey.filter { $0.value.scrollView != nil }
    }

    private func finalizeMotionSessionClose(
        sessionID: Int? = nil,
        revision: Int? = nil
    ) {
        if let sessionID, let revision {
            publishMotionCorrectionGate(
                sessionID: sessionID,
                revision: revision,
                reason: .sessionClose
            )
        }
        motionSessionCloseTick &+= 1
        if let scrollView = mainCanvasHorizontalScrollView {
            applyPendingMainCanvasHorizontalRestoreIfNeeded(to: scrollView)
        }
    }

    private func publishMotionCorrectionGate(
        sessionID: Int,
        revision: Int,
        reason: MotionCorrectionGateReason
    ) {
        motionCorrectionGateSequence &+= 1
        latestMotionCorrectionGate = MotionCorrectionGateSnapshot(
            serial: motionCorrectionGateSequence,
            sessionID: sessionID,
            revision: revision,
            reason: reason
        )
        motionCorrectionGateTick &+= 1
    }

    private func applyPendingMainCanvasHorizontalRestoreIfNeeded(to scrollView: NSScrollView) {
        guard let targetX = pendingMainCanvasHorizontalRestoreX else { return }
        guard activeMotionSession == nil else {
            indexBoardRestoreTrace(
                "coordinator_apply_pending_horizontal_restore_deferred",
                "reason=sessionActive targetOffset=\(debugRestoreCGFloat(targetX))"
            )
            return
        }
        let visibleRect = scrollView.documentVisibleRect
        let documentWidth = scrollView.documentView?.bounds.width ?? 0
        let maxX = max(0, documentWidth - visibleRect.width)
        indexBoardRestoreTrace(
            "coordinator_apply_pending_horizontal_restore_begin",
            "targetOffset=\(debugRestoreCGFloat(targetX)) currentOffset=\(debugRestoreCGFloat(scrollView.contentView.bounds.origin.x)) " +
            "visibleWidth=\(String(format: "%.2f", visibleRect.width)) documentWidth=\(String(format: "%.2f", documentWidth)) maxX=\(String(format: "%.2f", maxX))"
        )

        // Wait until the recreated canvas can actually scroll horizontally;
        // otherwise an early restore clamps to zero and strands the viewport at root.
        if targetX > 1, maxX <= 1 {
            indexBoardRestoreTrace(
                "coordinator_apply_pending_horizontal_restore_deferred",
                "reason=documentNotScrollableYet targetOffset=\(debugRestoreCGFloat(targetX)) maxX=\(String(format: "%.2f", maxX))"
            )
            return
        }

        let resolvedTargetX = CaretScrollCoordinator.resolvedHorizontalTargetX(
            visibleRect: visibleRect,
            targetX: targetX,
            minX: 0,
            maxX: maxX,
            snapToPixel: true
        )
        _ = CaretScrollCoordinator.applyHorizontalScrollIfNeeded(
            scrollView: scrollView,
            visibleRect: visibleRect,
            targetX: targetX,
            minX: 0,
            maxX: maxX,
            deadZone: 0.5,
            snapToPixel: true
        )
        mainCanvasHorizontalOffsetSnapshot = max(0, scrollView.contentView.bounds.origin.x)
        indexBoardRestoreTrace(
            "coordinator_apply_pending_horizontal_restore_applied",
            "targetOffset=\(debugRestoreCGFloat(targetX)) resolvedTarget=\(debugRestoreCGFloat(resolvedTargetX)) " +
            "currentOffset=\(debugRestoreCGFloat(scrollView.contentView.bounds.origin.x))"
        )

        let targetReachable = maxX + 0.5 >= targetX
        if targetReachable, abs(resolvedTargetX - scrollView.contentView.bounds.origin.x) <= 0.5 {
            pendingMainCanvasHorizontalRestoreX = nil
            indexBoardRestoreTrace(
                "coordinator_apply_pending_horizontal_restore_cleared",
                "targetOffset=\(debugRestoreCGFloat(targetX))"
            )
        }
    }
}
    typealias MotionWorkScheduler = @MainActor (_ delay: TimeInterval, _ workItem: DispatchWorkItem) -> Void
