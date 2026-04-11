import SwiftUI
import Foundation
import CoreGraphics

nonisolated enum BWRBoardInputModality: String, Codable, CaseIterable, Sendable {
    case keyboard
    case pointer
    case drag
}

nonisolated enum BWRSlotCursorVisibility: String, Codable, CaseIterable, Sendable {
    case hidden
    case visible
}

nonisolated enum BWRDragLiftStyle: String, Codable, CaseIterable, Sendable {
    case none
    case lifted
}

nonisolated enum BWRBoardAccentMode: String, Codable, CaseIterable, Sendable {
    case system
    case cool
    case warm
}

nonisolated struct BWRBoardThemeState: Codable, Equatable, Sendable {
    var boardBackgroundHex: String?
    var boardAccentMode: BWRBoardAccentMode

    init(
        boardBackgroundHex: String? = nil,
        boardAccentMode: BWRBoardAccentMode = .system
    ) {
        self.boardBackgroundHex = boardBackgroundHex
        self.boardAccentMode = boardAccentMode
    }
}

nonisolated struct BWRBoardSlotReference: Codable, Equatable, Hashable, Sendable {
    var host: BWRSlotHost
    var slotIndex: Int

    init(host: BWRSlotHost, slotIndex: Int) {
        self.host = host
        self.slotIndex = max(0, slotIndex)
    }
}

nonisolated struct BWRBoardRectSnapshot: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(rect: CGRect) {
        self.x = rect.minX
        self.y = rect.minY
        self.width = rect.width
        self.height = rect.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

nonisolated struct BWRSlotCursorState: Codable, Equatable, Sendable {
    var slotCursorHost: BWRSlotHost?
    var slotCursorIndex: Int?
    var slotCursorVisibility: BWRSlotCursorVisibility
    var lastInputModality: BWRBoardInputModality

    init(
        slotCursorHost: BWRSlotHost? = nil,
        slotCursorIndex: Int? = nil,
        slotCursorVisibility: BWRSlotCursorVisibility = .hidden,
        lastInputModality: BWRBoardInputModality = .pointer
    ) {
        self.slotCursorHost = slotCursorHost
        self.slotCursorIndex = slotCursorIndex
        self.slotCursorVisibility = slotCursorVisibility
        self.lastInputModality = lastInputModality
    }

    var slotReference: BWRBoardSlotReference? {
        guard let slotCursorHost, let slotCursorIndex else { return nil }
        return BWRBoardSlotReference(host: slotCursorHost, slotIndex: slotCursorIndex)
    }

    mutating func set(
        reference: BWRBoardSlotReference?,
        modality: BWRBoardInputModality,
        visibility: BWRSlotCursorVisibility = .visible
    ) {
        lastInputModality = modality
        guard let reference else {
            clear(modality: modality)
            return
        }
        slotCursorHost = reference.host
        slotCursorIndex = reference.slotIndex
        slotCursorVisibility = visibility
    }

    mutating func clear(modality: BWRBoardInputModality? = nil) {
        if let modality {
            lastInputModality = modality
        }
        slotCursorHost = nil
        slotCursorIndex = nil
        slotCursorVisibility = .hidden
    }

    mutating func syncSelection(cardID: UUID?, document: BWRDocument, modality: BWRBoardInputModality) {
        lastInputModality = modality
        guard let cardID,
              let location = BWRSlotOrder.indexOfCardInHost(cardID: cardID, document: document) else {
            clear(modality: modality)
            return
        }
        slotCursorHost = location.host
        slotCursorIndex = location.index
        slotCursorVisibility = .visible
    }
}

nonisolated struct BWRHoverPlaceholderState: Codable, Equatable, Sendable {
    var hoveredHost: BWRSlotHost
    var hoveredInsertionIndex: Int
    var hoverLocation: BWRPoint

    init(
        hoveredHost: BWRSlotHost,
        hoveredInsertionIndex: Int,
        hoverLocation: BWRPoint
    ) {
        self.hoveredHost = hoveredHost
        self.hoveredInsertionIndex = max(0, hoveredInsertionIndex)
        self.hoverLocation = hoverLocation
    }

    func projectedPlaceholder(in projection: BWRSlotBoardProjectionSnapshot) -> BWRProjectedPlaceholder? {
        guard let rect = projection.placeholderRect(
            for: hoveredHost,
            insertionIndex: hoveredInsertionIndex
        ) else {
            return nil
        }

        return BWRProjectedPlaceholder(
            id: "hover-\(hoveredHost.snapshotID)-\(hoveredInsertionIndex)",
            kind: .hoverSlot(hoveredHost),
            rect: rect
        )
    }
}

nonisolated struct BWRDragOverlayState: Codable, Equatable, Sendable {
    var dragSourceSlot: BWRBoardSlotReference?
    var dragDestinationSlot: BWRBoardSlotReference?
    var dragSourceSlots: [BWRBoardSlotReference]
    var dragDestinationSlots: [BWRBoardSlotReference]
    var dragDestinationResidentCount: Int?
    var transientDestinationRects: [BWRBoardRectSnapshot]
    var dragLiftStyle: BWRDragLiftStyle

    init(
        dragSourceSlot: BWRBoardSlotReference? = nil,
        dragDestinationSlot: BWRBoardSlotReference? = nil,
        dragSourceSlots: [BWRBoardSlotReference] = [],
        dragDestinationSlots: [BWRBoardSlotReference] = [],
        dragDestinationResidentCount: Int? = nil,
        transientDestinationRects: [BWRBoardRectSnapshot] = [],
        dragLiftStyle: BWRDragLiftStyle = .none
    ) {
        self.dragSourceSlot = dragSourceSlot
        self.dragDestinationSlot = dragDestinationSlot
        self.dragSourceSlots = dragSourceSlots
        self.dragDestinationSlots = dragDestinationSlots
        self.dragDestinationResidentCount = dragDestinationResidentCount
        self.transientDestinationRects = transientDestinationRects
        self.dragLiftStyle = dragLiftStyle
    }

    mutating func clear() {
        dragSourceSlot = nil
        dragDestinationSlot = nil
        dragSourceSlots = []
        dragDestinationSlots = []
        dragDestinationResidentCount = nil
        transientDestinationRects = []
        dragLiftStyle = .none
    }

    func sourceRect(in projection: BWRSlotBoardProjectionSnapshot) -> CGRect? {
        sourceRects(in: projection).first
    }

    func sourceRects(in projection: BWRSlotBoardProjectionSnapshot) -> [CGRect] {
        let references = dragSourceSlots.isEmpty ? [dragSourceSlot].compactMap { $0 } : dragSourceSlots
        return references.compactMap { projection.slotRect(for: $0) }
    }

    func destinationPlaceholder(in projection: BWRSlotBoardProjectionSnapshot) -> BWRProjectedPlaceholder? {
        destinationPlaceholders(in: projection).first
    }

    func destinationPlaceholders(in projection: BWRSlotBoardProjectionSnapshot) -> [BWRProjectedPlaceholder] {
        let references = dragDestinationSlots.isEmpty ? [dragDestinationSlot].compactMap { $0 } : dragDestinationSlots
        if let first = references.first {
            let rects = projection.placeholderRects(
                for: first.host,
                insertionIndex: first.slotIndex,
                blockLength: references.count,
                residentCardCount: dragDestinationResidentCount ?? projection.slotCount(for: first.host)
            )
            return zip(references, rects).map { reference, rect in
                BWRProjectedPlaceholder(
                    id: "drag-destination-\(reference.host.snapshotID)-\(reference.slotIndex)",
                    kind: .dragDestination(reference.host),
                    rect: rect
                )
            }
        }

        return transientDestinationRects.enumerated().map { index, snapshot in
            BWRProjectedPlaceholder(
                id: "drag-destination-transient-\(index)",
                kind: .dragDestination(nil),
                rect: snapshot.cgRect
            )
        }
    }

    func transientDestinationPlaceholder(rect: CGRect) -> BWRProjectedPlaceholder {
        return BWRProjectedPlaceholder(
            id: "drag-destination-transient-\(Int(rect.minX))-\(Int(rect.minY))-\(Int(rect.width))-\(Int(rect.height))",
            kind: .dragDestination(nil),
            rect: rect
        )
    }
}

nonisolated struct BWRBoardChromeState: Codable, Equatable, Sendable {
    var slotCursor: BWRSlotCursorState
    var hoverPlaceholder: BWRHoverPlaceholderState?
    var dragOverlay: BWRDragOverlayState

    init(
        slotCursor: BWRSlotCursorState = .init(),
        hoverPlaceholder: BWRHoverPlaceholderState? = nil,
        dragOverlay: BWRDragOverlayState = .init()
    ) {
        self.slotCursor = slotCursor
        self.hoverPlaceholder = hoverPlaceholder
        self.dragOverlay = dragOverlay
    }
}

nonisolated struct BWRCardMarkdownPreviewRenderResult: Equatable, Sendable {
    var sourceMarkdown: String
    var visibleLines: [String]
    var visibleText: String
    var didTruncate: Bool
    var containsStrongEmphasis: Bool
    var containsListItems: Bool
    var containsSoftBreaks: Bool
}

nonisolated enum BWRCardMarkdownPreviewRenderer {
    static func render(_ markdown: String, lineLimit: Int = 5) -> BWRCardMarkdownPreviewRenderResult {
        let normalizedLines = normalizeLines(markdown)
        let limitedLines = Array(normalizedLines.prefix(max(1, lineLimit)))
        return BWRCardMarkdownPreviewRenderResult(
            sourceMarkdown: markdown,
            visibleLines: limitedLines,
            visibleText: limitedLines.joined(separator: "\n"),
            didTruncate: normalizedLines.count > limitedLines.count,
            containsStrongEmphasis: markdown.contains("**"),
            containsListItems: markdown.contains("- ") || markdown.contains("* "),
            containsSoftBreaks: markdown.contains("  \n")
        )
    }

    private static func normalizeLines(_ markdown: String) -> [String] {
        markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .map(normalizeLine)
            .filter { !$0.isEmpty }
    }

    private static func normalizeLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }

        let withoutStrong = trimmed
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")

        if withoutStrong.hasPrefix("- ") || withoutStrong.hasPrefix("* ") {
            return "• " + withoutStrong.dropFirst(2)
        }

        return withoutStrong
    }
}

nonisolated struct BWRCardBuddyPhase0Dependency: Equatable, Sendable {
    var id: String
    var title: String
    var stateSummary: String
    var filePath: String
}

nonisolated enum BWRCardBuddyPhase0DependencyMap {
    private static let sourceDirectoryURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    private static func path(_ name: String) -> String {
        sourceDirectoryURL.appendingPathComponent(name).path
    }

    static let entries: [BWRCardBuddyPhase0Dependency] = [
        BWRCardBuddyPhase0Dependency(
            id: "slot-cursor",
            title: "Slot Cursor State",
            stateSummary: "BWRDocumentShellView keeps the slot cursor anchor and input modality in boardChromeState.slotCursor.",
            filePath: path("BWRDocumentShellView.swift")
        ),
        BWRCardBuddyPhase0Dependency(
            id: "hover-placeholder",
            title: "Hover Placeholder State",
            stateSummary: "BWRBoardChromeState stores hoveredHost / hoveredInsertionIndex / hoverLocation and projects the placeholder through BWRSlotBoardProjectionSnapshot.",
            filePath: path("BWRCardBuddyPhase0Scaffolding.swift")
        ),
        BWRCardBuddyPhase0Dependency(
            id: "drag-overlay",
            title: "Drag Overlay State",
            stateSummary: "BWRBoardChromeState.dragOverlay reserves separate source and destination slots plus lift style without collapsing them into one placeholder kind.",
            filePath: path("BWRCardBuddyPhase0Scaffolding.swift")
        ),
        BWRCardBuddyPhase0Dependency(
            id: "theme",
            title: "Board Theme Persistence",
            stateSummary: "BWRDocument.boardTheme is persisted through BWRPackageStore.ProjectManifest so board background state lives inside the .bwr package.",
            filePath: path("BWRPhase0Support.swift")
        ),
        BWRCardBuddyPhase0Dependency(
            id: "markdown-preview",
            title: "Markdown Preview Renderer",
            stateSummary: "BWRCardMarkdownPreviewRenderer is the shared preview entrypoint for future card and large-editor markdown snapshots.",
            filePath: path("BWRCardBuddyPhase0Scaffolding.swift")
        ),
        BWRCardBuddyPhase0Dependency(
            id: "snapshot-host",
            title: "Visual Snapshot Host",
            stateSummary: "BWRCardBuddyVisualSnapshotHost injects theme + cursor + hover + drag fixtures into BWRBoardCanvasView without touching the main document shell flow.",
            filePath: path("BWRCardBuddyPhase0Scaffolding.swift")
        )
    ]
}

nonisolated struct BWRCardBuddyVisualSnapshotFixture: Identifiable, Sendable {
    var id: String
    var title: String
    var document: BWRDocument
    var selectedCardIDs: Set<UUID>
    var selectedGroupID: UUID?
    var viewportState: BWRViewportState
    var inlineEditor: BWRInlineEditorState?
    var boardChromeState: BWRBoardChromeState
}

nonisolated enum BWRCardBuddyVisualSnapshotFactory {
    private static let groupID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private static let stripID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!

    static func fixtures() -> [BWRCardBuddyVisualSnapshotFixture] {
        let base = baseDocument()
        let baseViewport = BWRViewportState(
            zoomScale: 1.0,
            scrollOrigin: BWRPoint(x: 0, y: 0),
            viewportSize: BWRSize(width: 1400, height: 920)
        )

        let selectedCardID = base.cards[0].id
        let inlineCard = base.cards[1]

        return [
            BWRCardBuddyVisualSnapshotFixture(
                id: "normal",
                title: "Normal",
                document: base,
                selectedCardIDs: [selectedCardID],
                selectedGroupID: nil,
                viewportState: baseViewport,
                inlineEditor: nil,
                boardChromeState: BWRBoardChromeState()
            ),
            BWRCardBuddyVisualSnapshotFixture(
                id: "cursor",
                title: "Keyboard Cursor",
                document: base,
                selectedCardIDs: [],
                selectedGroupID: nil,
                viewportState: baseViewport,
                inlineEditor: nil,
                boardChromeState: BWRBoardChromeState(
                    slotCursor: BWRSlotCursorState(
                        slotCursorHost: .group(groupID),
                        slotCursorIndex: 1,
                        slotCursorVisibility: .visible,
                        lastInputModality: .keyboard
                    )
                )
            ),
            BWRCardBuddyVisualSnapshotFixture(
                id: "hover",
                title: "Hover Placeholder",
                document: base,
                selectedCardIDs: [],
                selectedGroupID: nil,
                viewportState: baseViewport,
                inlineEditor: nil,
                boardChromeState: BWRBoardChromeState(
                    hoverPlaceholder: BWRHoverPlaceholderState(
                        hoveredHost: .group(groupID),
                        hoveredInsertionIndex: 2,
                        hoverLocation: BWRPoint(x: 400, y: 180)
                    )
                )
            ),
            BWRCardBuddyVisualSnapshotFixture(
                id: "drag",
                title: "Drag Overlay",
                document: base,
                selectedCardIDs: [selectedCardID],
                selectedGroupID: nil,
                viewportState: baseViewport,
                inlineEditor: nil,
                boardChromeState: BWRBoardChromeState(
                    dragOverlay: BWRDragOverlayState(
                        dragSourceSlot: BWRBoardSlotReference(host: .group(groupID), slotIndex: 0),
                        dragDestinationSlot: BWRBoardSlotReference(host: .strip(stripID), slotIndex: 1),
                        dragLiftStyle: .lifted
                    )
                )
            ),
            BWRCardBuddyVisualSnapshotFixture(
                id: "inline-theme",
                title: "Inline + Theme",
                document: themedDocument(base),
                selectedCardIDs: [inlineCard.id],
                selectedGroupID: nil,
                viewportState: baseViewport,
                inlineEditor: BWRInlineEditorState(
                    cardID: inlineCard.id,
                    layerID: inlineCard.currentLayerID,
                    text: inlineCard.currentLayer?.markdown ?? "",
                    selectedRange: NSRange(location: 0, length: 0)
                ),
                boardChromeState: BWRBoardChromeState()
            )
        ]
    }

    private static func baseDocument() -> BWRDocument {
        let first = makeCard(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
            stableSortKey: 1,
            colorHex: "F8FAFC",
            body: "**Opening beat**\n- Card Buddy shell\n- Paper surface",
            layout: BWRPoint(x: 0, y: 0)
        )
        let second = makeCard(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
            stableSortKey: 2,
            colorHex: "FEF3C7",
            body: "Inline editor sample  \nSoft break preserved\n- Hidden affordance",
            layout: BWRPoint(x: 0, y: 0)
        )
        let third = makeCard(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
            stableSortKey: 3,
            colorHex: "E0F2FE",
            body: "Parked note\n- destination strip",
            layout: BWRPoint(x: 0, y: 0)
        )

        return BWRDocument(
            schemaVersion: 2,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            nextStableSortKey: 4,
            cards: [first, second, third],
            groups: [
                BWRGroup(
                    id: groupID,
                    name: "Beat Board",
                    originSlot: BWRSlotCoordinate(column: 0, row: 0),
                    memberCardIDs: [first.id, second.id],
                    createdAt: Date(timeIntervalSince1970: 0),
                    updatedAt: Date(timeIntervalSince1970: 0)
                )
            ],
            parkingStrips: [
                BWRParkingStrip(
                    id: stripID,
                    row: 2,
                    anchorColumn: 0,
                    cardIDs: [third.id]
                )
            ]
        )
    }

    private static func themedDocument(_ base: BWRDocument) -> BWRDocument {
        var themed = base
        themed.boardTheme = BWRBoardThemeState(
            boardBackgroundHex: "FDE68A",
            boardAccentMode: .warm
        )
        return themed
    }

    private static func makeCard(
        id: UUID,
        stableSortKey: Int64,
        colorHex: String,
        body: String,
        layout: BWRPoint
    ) -> BWRCard {
        let layers = BWRCard.defaultLayers(
            bodyMarkdown: body,
            treatmentMarkdown: "Treatment \(stableSortKey)",
            scenarioMarkdown: "Scenario \(stableSortKey)"
        )
        return BWRCard(
            id: id,
            stableSortKey: stableSortKey,
            colorHex: colorHex,
            currentLayerID: layers[0].id,
            layout: layout,
            createdAt: Date(timeIntervalSince1970: TimeInterval(stableSortKey)),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(stableSortKey)),
            layers: layers
        )
    }
}

@MainActor
struct BWRCardBuddyVisualSnapshotHost: View {
    private let fixture: BWRCardBuddyVisualSnapshotFixture

    @StateObject private var document: BWRReferenceDocument
    @State private var selectedCardIDs: Set<UUID>
    @State private var selectedGroupID: UUID?
    @State private var viewportState: BWRViewportState
    @State private var inlineEditor: BWRInlineEditorState?
    @State private var boardChromeState: BWRBoardChromeState

    init(fixture: BWRCardBuddyVisualSnapshotFixture) {
        self.fixture = fixture
        _document = StateObject(wrappedValue: BWRReferenceDocument(document: fixture.document))
        _selectedCardIDs = State(initialValue: fixture.selectedCardIDs)
        _selectedGroupID = State(initialValue: fixture.selectedGroupID)
        _viewportState = State(initialValue: fixture.viewportState)
        _inlineEditor = State(initialValue: fixture.inlineEditor)
        _boardChromeState = State(initialValue: fixture.boardChromeState)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(fixture.title)
                .font(.system(size: 15, weight: .semibold))
            BWRBoardCanvasView(
                document: document,
                selectedCardIDs: $selectedCardIDs,
                selectedGroupID: $selectedGroupID,
                viewportState: $viewportState,
                inlineEditor: $inlineEditor,
                boardChromeState: $boardChromeState,
                boardTheme: document.document.boardTheme,
                beginInlineEdit: { cardID in
                    guard let card = document.liveCards.first(where: { $0.id == cardID }),
                          let currentLayer = card.currentLayer ?? card.layers.first else {
                        return
                    }
                    inlineEditor = BWRInlineEditorState(
                        cardID: card.id,
                        layerID: currentLayer.id,
                        text: currentLayer.markdown,
                        selectedRange: NSRange(location: 0, length: 0)
                    )
                },
                finishInlineEdit: { save in
                    guard save,
                          let inlineEditor else {
                        self.inlineEditor = nil
                        return
                    }
                    document.applyLayerMarkdown(
                        cardID: inlineEditor.cardID,
                        layerID: inlineEditor.layerID,
                        markdown: inlineEditor.text
                    )
                    self.inlineEditor = nil
                },
                splitInlineEdit: {},
                cycleInlineLayer: { _, _ in },
                openLargeEditor: { _ in },
                requestLayerRename: { _, _, _ in },
                requestGroupRename: { _, _ in }
            )
            .frame(height: 720)
        }
        .padding(16)
    }
}

nonisolated extension BWRSlotHost {
    var snapshotID: String {
        switch self {
        case let .group(groupID):
            return "group-\(groupID.uuidString)"
        case let .strip(stripID):
            return "strip-\(stripID.uuidString)"
        }
    }
}

nonisolated extension BWRSlotBoardProjectionSnapshot {
    func slotRect(for reference: BWRBoardSlotReference) -> CGRect? {
        switch reference.host {
        case let .group(groupID):
            guard let frame = groupFrames.first(where: { $0.group.id == groupID }) else {
                return nil
            }
            let slotCount = max(frame.group.memberCardIDs.count, reference.slotIndex + 1, 1)
            let local = BWRSlotBoardGeometry.localSlotCoordinate(
                for: reference.slotIndex,
                slotCount: slotCount,
                metrics: metrics
            )
            return BWRSlotBoardGeometry.slotRect(origin: frame.resolvedOriginSlot, local: local, metrics: metrics)
        case let .strip(stripID):
            guard let frame = stripFrames.first(where: { $0.strip.id == stripID }) else {
                return nil
            }
            return CGRect(
                x: CGFloat(frame.resolvedOriginSlot.column + reference.slotIndex) * metrics.slotWidth,
                y: CGFloat(frame.resolvedOriginSlot.row) * metrics.slotHeight,
                width: metrics.slotWidth,
                height: metrics.slotHeight
            )
        }
    }
}
