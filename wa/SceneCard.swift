import Foundation
import Combine

@MainActor
final class SceneCard: ObservableObject, Identifiable {
    let id: UUID
    @Published var content: String {
        didSet {
            guard content != oldValue else { return }
            guard !isApplyingCloneSynchronization else { return }
            scenario?.propagateCloneContent(from: self, content: content)
            scenario?.markCardContentDirty()
            markSharedCraftDirtyIfNeeded()
            scenario?.markModified()
        }
    }
    @Published var orderIndex: Int {
        didSet {
            guard orderIndex != oldValue else { return }
            scenario?.markCardRecordsDirty()
            markSharedCraftDirtyIfNeeded()
            scenario?.bumpCardsVersion()
            scenario?.markModified()
        }
    }
    @Published var createdAt: Date
    @Published var parent: SceneCard? {
        didSet {
            guard parent?.id != oldValue?.id else { return }
            scenario?.markCardRecordsDirty()
            markSharedCraftDirtyIfNeeded()
            scenario?.bumpCardsVersion()
            scenario?.markModified()
        }
    }
    weak var scenario: Scenario?
    @Published var category: String? {
        didSet {
            guard category != oldValue else { return }
            scenario?.markCardRecordsDirty()
            markSharedCraftDirtyIfNeeded(previousCategory: oldValue)
            scenario?.bumpCardsVersion()
            scenario?.markModified()
        }
    }
    @Published var isFloating: Bool {
        didSet {
            guard isFloating != oldValue else { return }
            scenario?.markCardRecordsDirty()
            markSharedCraftDirtyIfNeeded()
            scenario?.bumpCardsVersion()
            scenario?.markModified()
        }
    }
    @Published var isArchived: Bool {
        didSet {
            guard isArchived != oldValue else { return }
            scenario?.markCardRecordsDirty()
            markSharedCraftDirtyIfNeeded()
            scenario?.bumpCardsVersion()
            scenario?.markModified()
        }
    }
    @Published var lastSelectedChildID: UUID? {
        didSet {
            guard lastSelectedChildID != oldValue else { return }
            scenario?.markCardRecordsDirty()
        }
    }
    @Published var colorHex: String? {
        didSet {
            guard colorHex != oldValue else { return }
            guard !isApplyingCloneSynchronization else { return }
            scenario?.propagateCloneColor(from: self, colorHex: colorHex)
            scenario?.markCardRecordsDirty()
            markSharedCraftDirtyIfNeeded()
            scenario?.markModified()
        }
    }
    @Published var cloneGroupID: UUID? {
        didSet {
            guard cloneGroupID != oldValue else { return }
            scenario?.markCardRecordsDirty()
            markSharedCraftDirtyIfNeeded()
            scenario?.bumpCardsVersion()
            scenario?.markModified()
        }
    }
    @Published var isAICandidate: Bool
    private var isApplyingCloneSynchronization: Bool = false

    init(id: UUID = UUID(), content: String = "", orderIndex: Int = 0, createdAt: Date = Date(), parent: SceneCard? = nil, scenario: Scenario? = nil, category: String? = nil, isFloating: Bool = false, isArchived: Bool = false, lastSelectedChildID: UUID? = nil, colorHex: String? = nil, cloneGroupID: UUID? = nil, isAICandidate: Bool = false) {
        self.id = id
        self.content = content
        self.orderIndex = orderIndex
        self.createdAt = createdAt
        self.parent = parent
        self.scenario = scenario
        self.category = category
        self.isFloating = isFloating
        self.isArchived = isArchived
        self.lastSelectedChildID = lastSelectedChildID
        self.colorHex = colorHex
        self.cloneGroupID = cloneGroupID
        self.isAICandidate = isAICandidate
    }

    private func markSharedCraftDirtyIfNeeded(previousCategory: String? = nil) {
        guard category == ScenarioCardCategory.craft || previousCategory == ScenarioCardCategory.craft else {
            return
        }
        scenario?.markSharedCraftDirty()
    }

    func applyCloneSynchronizedContent(_ newContent: String) {
        guard content != newContent else { return }
        isApplyingCloneSynchronization = true
        content = newContent
        isApplyingCloneSynchronization = false
    }

    func applyCloneSynchronizedColor(_ newColorHex: String?) {
        guard colorHex != newColorHex else { return }
        isApplyingCloneSynchronization = true
        colorHex = newColorHex
        isApplyingCloneSynchronization = false
    }

    var children: [SceneCard] {
        guard let scenario = scenario else { return [] }
        return scenario.children(for: self.id)
    }

    var sortedChildren: [SceneCard] {
        children
    }

    func updateDescendantsCategory(_ newCategory: String?) {
        self.applyDescendantsCategory(newCategory)
    }

    private func applyDescendantsCategory(_ newCategory: String?) {
        self.category = newCategory
        for child in children {
            child.applyDescendantsCategory(newCategory)
        }
    }
}
