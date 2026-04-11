import Foundation
import CoreGraphics
import CryptoKit

nonisolated enum BWRCardBuddyLargeEditorChrome {
    static let paperCornerRadius: CGFloat = 18
    static let minimumEditorHeight: CGFloat = 320
}

nonisolated struct BWRCardBuddyAcceptanceMetricsSnapshot: Codable, Equatable, Sendable {
    var slotWidth: Double
    var slotHeight: Double
    var cardWidth: Double
    var cardHeight: Double
    var horizontalGap: Double
    var verticalGap: Double
    var selectionSpread: Double
}

nonisolated struct BWRCardBuddyAcceptanceCardSnapshot: Codable, Equatable, Sendable {
    var cardID: String
    var titlePreview: String
    var hostID: String
    var slotIndex: Int
    var slotRect: BWRBoardRectSnapshot
    var cardRect: BWRBoardRectSnapshot
    var fillHex: String
    var previewLines: [String]
    var isSelected: Bool
    var isInlineEditing: Bool
    var showsLayerAffordance: Bool
    var footerElements: [String]
    var editorRect: BWRBoardRectSnapshot?
    var footerRect: BWRBoardRectSnapshot?
    var containsMetaText: Bool
    var currentLayerName: String
}

nonisolated struct BWRCardBuddyAcceptanceGroupSnapshot: Codable, Equatable, Sendable {
    var groupID: String
    var name: String
    var memberCount: Int
    var rect: BWRBoardRectSnapshot
    var isSelected: Bool
    var fillHex: String
    var fillOpacity: Double
    var strokeHex: String
    var strokeOpacity: Double
    var strokeWidth: Double
}

nonisolated struct BWRCardBuddyAcceptanceOverlaySnapshot: Codable, Equatable, Sendable {
    var role: String
    var hostID: String?
    var slotIndex: Int?
    var descriptor: String
    var rects: [BWRBoardRectSnapshot]
    var targetsEmptySlot: Bool
}

nonisolated struct BWRCardBuddyAcceptanceBoardSnapshot: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var boardBackgroundHex: String?
    var metrics: BWRCardBuddyAcceptanceMetricsSnapshot
    var cardOrder: [String]
    var cards: [BWRCardBuddyAcceptanceCardSnapshot]
    var groups: [BWRCardBuddyAcceptanceGroupSnapshot]
    var overlays: [BWRCardBuddyAcceptanceOverlaySnapshot]

    var digest: String {
        BWRCardBuddyAcceptanceDigest.hex(for: self)
    }
}

nonisolated struct BWRCardBuddyAcceptanceMarkdownSnapshot: Codable, Equatable, Sendable {
    var visibleLines: [String]
    var visibleText: String
    var didTruncate: Bool
    var containsStrongEmphasis: Bool
    var containsListItems: Bool
    var containsSoftBreaks: Bool

    var digest: String {
        BWRCardBuddyAcceptanceDigest.hex(for: self)
    }
}

nonisolated struct BWRCardBuddyAcceptanceLargeEditorSnapshot: Codable, Equatable, Sendable {
    var cardID: String
    var titlePreview: String
    var layerNames: [String]
    var currentLayerName: String
    var currentLayerKind: String
    var bodyLayerCount: Int
    var paperCornerRadius: Double
    var minimumEditorHeight: Double
    var showsDoneAction: Bool
    var showsSplitAction: Bool
    var showsLayerMenu: Bool
    var showsColorMenu: Bool
    var showsRenameAction: Bool

    var digest: String {
        BWRCardBuddyAcceptanceDigest.hex(for: self)
    }
}

nonisolated struct BWRCardBuddyAcceptanceMoveCase: Equatable, Sendable {
    var id: String
    var title: String
    var document: BWRDocument
    var movingCardIDs: [UUID]
    var targetHost: BWRSlotHost
    var rawInsertionIndex: Int
    var expectedHosts: [String: [UUID]]
}

nonisolated struct BWRCardBuddyAcceptanceMoveResult: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var movingCardIDs: [String]
    var targetHostID: String
    var targetInsertionIndex: Int
    var hostsBefore: [String: [String]]
    var hostsAfter: [String: [String]]
    var alignedCardIDs: [String]
    var digest: String
}

private nonisolated struct BWRCardBuddyAcceptanceMoveDigestPayload: Codable, Equatable, Sendable {
    var id: String
    var movingCardIDs: [String]
    var targetHostID: String
    var targetInsertionIndex: Int
    var hostsAfter: [String: [String]]
}

nonisolated enum BWRCardBuddyAcceptanceDigest {
    static func hex<T: Encodable>(for value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else {
            return "encoding-failed"
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated enum BWRCardBuddyAcceptanceFixtureFactory {
    private static let groupAID = UUID(uuidString: "71000000-0000-0000-0000-000000000001")!
    private static let groupBID = UUID(uuidString: "71000000-0000-0000-0000-000000000002")!
    private static let stripID = UUID(uuidString: "71000000-0000-0000-0000-000000000003")!

    private static let cardA1 = UUID(uuidString: "72000000-0000-0000-0000-000000000001")!
    private static let cardA2 = UUID(uuidString: "72000000-0000-0000-0000-000000000002")!
    private static let cardA3 = UUID(uuidString: "72000000-0000-0000-0000-000000000003")!
    private static let cardA4 = UUID(uuidString: "72000000-0000-0000-0000-000000000004")!
    private static let cardB1 = UUID(uuidString: "72000000-0000-0000-0000-000000000005")!
    private static let cardB2 = UUID(uuidString: "72000000-0000-0000-0000-000000000006")!
    private static let cardS1 = UUID(uuidString: "72000000-0000-0000-0000-000000000007")!
    private static let cardS2 = UUID(uuidString: "72000000-0000-0000-0000-000000000008")!

    static let expectedBoardFixtureIDs: [String] = [
        "card-normal",
        "card-selected",
        "card-inline",
        "card-colored",
        "slot-cursor",
        "slot-hover",
        "slot-drag-source",
        "slot-drag-destination",
        "slot-empty-placeholder",
        "group-mixed"
    ]

    static func boardFixtures() -> [BWRCardBuddyVisualSnapshotFixture] {
        let base = baseDocument()
        let viewport = defaultViewport()
        let a2Layer = base.cards.first(where: { $0.id == cardA2 })?.currentLayer

        return [
            BWRCardBuddyVisualSnapshotFixture(
                id: "card-normal",
                title: "Card Normal",
                document: base,
                selectedCardIDs: [],
                selectedGroupID: nil,
                viewportState: viewport,
                inlineEditor: nil,
                boardChromeState: .init()
            ),
            BWRCardBuddyVisualSnapshotFixture(
                id: "card-selected",
                title: "Card Selected",
                document: base,
                selectedCardIDs: [cardA1],
                selectedGroupID: nil,
                viewportState: viewport,
                inlineEditor: nil,
                boardChromeState: .init()
            ),
            BWRCardBuddyVisualSnapshotFixture(
                id: "card-inline",
                title: "Card Inline Editing",
                document: base,
                selectedCardIDs: [cardA2],
                selectedGroupID: nil,
                viewportState: viewport,
                inlineEditor: a2Layer.map {
                    BWRInlineEditorState(
                        cardID: cardA2,
                        layerID: $0.id,
                        text: $0.markdown,
                        selectedRange: NSRange(location: 7, length: 0)
                    )
                },
                boardChromeState: .init()
            ),
            BWRCardBuddyVisualSnapshotFixture(
                id: "card-colored",
                title: "Card Colored",
                document: base,
                selectedCardIDs: [cardA3],
                selectedGroupID: nil,
                viewportState: viewport,
                inlineEditor: nil,
                boardChromeState: .init()
            ),
            BWRCardBuddyVisualSnapshotFixture(
                id: "slot-cursor",
                title: "Slot Keyboard Cursor",
                document: base,
                selectedCardIDs: [],
                selectedGroupID: nil,
                viewportState: viewport,
                inlineEditor: nil,
                boardChromeState: BWRBoardChromeState(
                    slotCursor: BWRSlotCursorState(
                        slotCursorHost: .group(groupAID),
                        slotCursorIndex: 1,
                        slotCursorVisibility: .visible,
                        lastInputModality: .keyboard
                    )
                )
            ),
            BWRCardBuddyVisualSnapshotFixture(
                id: "slot-hover",
                title: "Slot Mouse Hover",
                document: base,
                selectedCardIDs: [],
                selectedGroupID: nil,
                viewportState: viewport,
                inlineEditor: nil,
                boardChromeState: BWRBoardChromeState(
                    slotCursor: BWRSlotCursorState(
                        slotCursorHost: .group(groupAID),
                        slotCursorIndex: 0,
                        slotCursorVisibility: .visible,
                        lastInputModality: .pointer
                    ),
                    hoverPlaceholder: BWRHoverPlaceholderState(
                        hoveredHost: .group(groupAID),
                        hoveredInsertionIndex: 2,
                        hoverLocation: BWRPoint(x: 420, y: 150)
                    )
                )
            ),
            BWRCardBuddyVisualSnapshotFixture(
                id: "slot-drag-source",
                title: "Slot Drag Source",
                document: base,
                selectedCardIDs: [cardA2],
                selectedGroupID: nil,
                viewportState: viewport,
                inlineEditor: nil,
                boardChromeState: BWRBoardChromeState(
                    dragOverlay: BWRDragOverlayState(
                        dragSourceSlot: BWRBoardSlotReference(host: .group(groupAID), slotIndex: 1),
                        dragSourceSlots: [BWRBoardSlotReference(host: .group(groupAID), slotIndex: 1)],
                        dragLiftStyle: .lifted
                    )
                )
            ),
            BWRCardBuddyVisualSnapshotFixture(
                id: "slot-drag-destination",
                title: "Slot Drag Destination",
                document: base,
                selectedCardIDs: [],
                selectedGroupID: nil,
                viewportState: viewport,
                inlineEditor: nil,
                boardChromeState: BWRBoardChromeState(
                    dragOverlay: BWRDragOverlayState(
                        dragDestinationSlot: BWRBoardSlotReference(host: .group(groupBID), slotIndex: 1),
                        dragDestinationSlots: [BWRBoardSlotReference(host: .group(groupBID), slotIndex: 1)],
                        dragDestinationResidentCount: 2,
                        dragLiftStyle: .none
                    )
                )
            ),
            BWRCardBuddyVisualSnapshotFixture(
                id: "slot-empty-placeholder",
                title: "Slot Empty Placeholder",
                document: base,
                selectedCardIDs: [],
                selectedGroupID: nil,
                viewportState: viewport,
                inlineEditor: nil,
                boardChromeState: BWRBoardChromeState(
                    hoverPlaceholder: BWRHoverPlaceholderState(
                        hoveredHost: .group(groupBID),
                        hoveredInsertionIndex: 2,
                        hoverLocation: BWRPoint(x: 460, y: 520)
                    )
                )
            ),
            BWRCardBuddyVisualSnapshotFixture(
                id: "group-mixed",
                title: "Group And Non-Group Mixed",
                document: base,
                selectedCardIDs: [cardS1],
                selectedGroupID: groupBID,
                viewportState: viewport,
                inlineEditor: nil,
                boardChromeState: .init()
            )
        ]
    }

    static func markdownSnapshot() -> BWRCardBuddyAcceptanceMarkdownSnapshot {
        let preview = BWRCardMarkdownPreviewRenderer.render(
            """
            **Opening beat**
            - Card Buddy shell
            - Paper surface
            Soft break  
            next line
            Overflow note
            """,
            lineLimit: BWRCardBuddyCardShell.surface.visibleLineDensity
        )

        return BWRCardBuddyAcceptanceMarkdownSnapshot(
            visibleLines: preview.visibleLines,
            visibleText: preview.visibleText,
            didTruncate: preview.didTruncate,
            containsStrongEmphasis: preview.containsStrongEmphasis,
            containsListItems: preview.containsListItems,
            containsSoftBreaks: preview.containsSoftBreaks
        )
    }

    static func largeEditorSnapshot() -> BWRCardBuddyAcceptanceLargeEditorSnapshot {
        let document = baseDocument()
        guard let card = document.cards.first(where: { $0.id == cardA2 }),
              let currentLayer = card.currentLayer else {
            return BWRCardBuddyAcceptanceLargeEditorSnapshot(
                cardID: "missing",
                titlePreview: "missing",
                layerNames: [],
                currentLayerName: "missing",
                currentLayerKind: "missing",
                bodyLayerCount: 0,
                paperCornerRadius: 0,
                minimumEditorHeight: 0,
                showsDoneAction: false,
                showsSplitAction: false,
                showsLayerMenu: false,
                showsColorMenu: false,
                showsRenameAction: false
            )
        }

        return BWRCardBuddyAcceptanceLargeEditorSnapshot(
            cardID: card.id.uuidString,
            titlePreview: card.titlePreview,
            layerNames: card.layers.map(\.name),
            currentLayerName: currentLayer.name,
            currentLayerKind: currentLayer.kind.rawValue,
            bodyLayerCount: card.layers.filter { $0.kind == .body }.count,
            paperCornerRadius: Double(BWRCardBuddyLargeEditorChrome.paperCornerRadius),
            minimumEditorHeight: Double(BWRCardBuddyLargeEditorChrome.minimumEditorHeight),
            showsDoneAction: true,
            showsSplitAction: true,
            showsLayerMenu: true,
            showsColorMenu: true,
            showsRenameAction: currentLayer.kind == .body
        )
    }

    static func boardThemeSnapshots() -> [BWRCardBuddyAcceptanceBoardSnapshot] {
        BWRCardBuddyBoardThemeGuardrail.boardSwatches.map { swatch in
            var document = baseDocument()
            document.boardTheme = BWRBoardThemeState(
                boardBackgroundHex: swatch.hex,
                boardAccentMode: swatch.accentMode
            )

            let fixture = BWRCardBuddyVisualSnapshotFixture(
                id: "theme-\(swatch.id)",
                title: "Theme \(swatch.name)",
                document: document,
                selectedCardIDs: [cardA1],
                selectedGroupID: nil,
                viewportState: defaultViewport(),
                inlineEditor: nil,
                boardChromeState: BWRBoardChromeState(
                    hoverPlaceholder: BWRHoverPlaceholderState(
                        hoveredHost: .group(groupAID),
                        hoveredInsertionIndex: 2,
                        hoverLocation: BWRPoint(x: 420, y: 150)
                    ),
                    dragOverlay: BWRDragOverlayState(
                        dragDestinationSlot: BWRBoardSlotReference(host: .group(groupBID), slotIndex: 1),
                        dragDestinationSlots: [BWRBoardSlotReference(host: .group(groupBID), slotIndex: 1)],
                        dragDestinationResidentCount: 2,
                        dragLiftStyle: .lifted
                    )
                )
            )

            return boardSnapshot(for: fixture)
        }
    }

    static func keyboardSmokeReferences() -> [BWRBoardSlotReference] {
        let document = baseDocument()
        let directions: [BWRBoardArrowDirection] = [.right, .right, .down, .left, .up]
        var sequence: [BWRBoardSlotReference] = []
        var current = BWRBoardOrderResolver.firstSlotReference(document: document)

        if let current {
            sequence.append(current)
        }

        for direction in directions {
            current = BWRBoardOrderResolver.nextSlotReference(
                document: document,
                from: current,
                direction: direction
            )
            if let current {
                sequence.append(current)
            }
        }

        return sequence
    }

    static func dragReorderFixture() -> BWRCardBuddyAcceptanceMoveCase {
        let document = baseDocument()
        return BWRCardBuddyAcceptanceMoveCase(
            id: "drag-reorder",
            title: "Drag Reorder",
            document: document,
            movingCardIDs: [cardA2],
            targetHost: .group(groupBID),
            rawInsertionIndex: 1,
            expectedHosts: [
                hostID(.group(groupAID)): [cardA1, cardA3, cardA4],
                hostID(.group(groupBID)): [cardB1, cardA2, cardB2],
                hostID(.strip(stripID)): [cardS1, cardS2]
            ]
        )
    }

    static func singleCardMoveFixtures() -> [BWRCardBuddyAcceptanceMoveCase] {
        let document = baseDocument()
        return [
            BWRCardBuddyAcceptanceMoveCase(
                id: "front-to-middle",
                title: "Front To Middle",
                document: document,
                movingCardIDs: [cardA1],
                targetHost: .group(groupAID),
                rawInsertionIndex: 3,
                expectedHosts: [
                    hostID(.group(groupAID)): [cardA2, cardA3, cardA1, cardA4],
                    hostID(.group(groupBID)): [cardB1, cardB2],
                    hostID(.strip(stripID)): [cardS1, cardS2]
                ]
            ),
            BWRCardBuddyAcceptanceMoveCase(
                id: "back-to-middle",
                title: "Back To Middle",
                document: document,
                movingCardIDs: [cardA4],
                targetHost: .strip(stripID),
                rawInsertionIndex: 1,
                expectedHosts: [
                    hostID(.group(groupAID)): [cardA1, cardA2, cardA3],
                    hostID(.group(groupBID)): [cardB1, cardB2],
                    hostID(.strip(stripID)): [cardS1, cardA4, cardS2]
                ]
            ),
            BWRCardBuddyAcceptanceMoveCase(
                id: "middle-insert",
                title: "Middle Insert",
                document: document,
                movingCardIDs: [cardB1],
                targetHost: .group(groupAID),
                rawInsertionIndex: 2,
                expectedHosts: [
                    hostID(.group(groupAID)): [cardA1, cardA2, cardB1, cardA3, cardA4],
                    hostID(.group(groupBID)): [cardB2],
                    hostID(.strip(stripID)): [cardS1, cardS2]
                ]
            )
        ]
    }

    static func multiCardMoveFixture() -> BWRCardBuddyAcceptanceMoveCase {
        let document = baseDocument()
        let moving = BWRSlotBoardInteraction.orderedMovingCardIDs(
            document: document,
            cardIDs: [cardA1, cardA3]
        )
        return BWRCardBuddyAcceptanceMoveCase(
            id: "multi-card-block",
            title: "Multi Card Block Move",
            document: document,
            movingCardIDs: moving,
            targetHost: .group(groupBID),
            rawInsertionIndex: 1,
            expectedHosts: [
                hostID(.group(groupAID)): [cardA2, cardA4],
                hostID(.group(groupBID)): [cardB1, cardA1, cardA3, cardB2],
                hostID(.strip(stripID)): [cardS1, cardS2]
            ]
        )
    }

    static func boardSnapshot(for fixture: BWRCardBuddyVisualSnapshotFixture) -> BWRCardBuddyAcceptanceBoardSnapshot {
        let projection = BWRSlotBoardProjection.project(document: fixture.document)
        let boardHex = BWRCardBuddyBoardThemeGuardrail.resolvedBoardBackgroundHex(for: fixture.document.boardTheme)
        let metrics = BWRSlotBoardGeometry.default
        let cardMetrics = BWRCardBuddyAcceptanceMetricsSnapshot(
            slotWidth: Double(metrics.slotWidth),
            slotHeight: Double(metrics.slotHeight),
            cardWidth: Double(metrics.cardSize.width),
            cardHeight: Double(metrics.cardSize.height),
            horizontalGap: Double(metrics.slotWidth - metrics.cardSize.width),
            verticalGap: Double(metrics.slotHeight - metrics.cardSize.height),
            selectionSpread: Double(BWRCardBuddyCardShell.surface.selectionOuterSpread)
        )

        let orderedCards = BWRBoardOrderResolver.orderedLiveCards(document: fixture.document, includeParked: true)
        let cards = orderedCards.compactMap { card -> BWRCardBuddyAcceptanceCardSnapshot? in
            guard let projected = projection.cardRectsByID[card.id] else { return nil }
            let currentLayer = card.currentLayer ?? card.layers.first
            let preview = BWRCardBuddyCardShell.preview(for: currentLayer?.markdown ?? "")
            let isInlineEditing = fixture.inlineEditor?.cardID == card.id
            let fillHex = BWRCardBuddyBoardThemeGuardrail.resolvedCardFillHex(
                cardHex: card.colorHex,
                boardHex: boardHex
            )

            var footerElements: [String] = []
            var editorRect: BWRBoardRectSnapshot?
            var footerRect: BWRBoardRectSnapshot?
            if isInlineEditing {
                let cardRect = projected.cardRect
                let surface = BWRCardBuddyCardShell.surface
                footerElements = card.layers.count > 1
                    ? ["layer-cycle", "split", "expand"]
                    : ["split", "expand"]
                editorRect = BWRBoardRectSnapshot(
                    rect: BWRSlotBoardGeometry.inlineEditorRect(
                        in: cardRect,
                        footerHeight: BWRCardBuddyEditingChrome.footerHeight,
                        horizontalInset: max(6, surface.cardTextInset - 4),
                        topInset: max(8, surface.cardInnerPadding - 2),
                        bottomInset: surface.cardInnerPadding,
                        footerGap: BWRCardBuddyEditingChrome.footerGap
                    )
                )
                footerRect = BWRBoardRectSnapshot(
                    rect: BWRSlotBoardGeometry.inlineEditorFooterRect(
                        in: cardRect,
                        footerHeight: BWRCardBuddyEditingChrome.footerHeight,
                        horizontalInset: surface.cardTextInset,
                        bottomInset: surface.cardInnerPadding
                    )
                )
            }

            return BWRCardBuddyAcceptanceCardSnapshot(
                cardID: card.id.uuidString,
                titlePreview: card.titlePreview,
                hostID: hostID(projected.host),
                slotIndex: projected.slotIndex,
                slotRect: BWRBoardRectSnapshot(rect: projected.slotRect),
                cardRect: BWRBoardRectSnapshot(rect: projected.cardRect),
                fillHex: fillHex,
                previewLines: preview.visibleLines,
                isSelected: fixture.selectedCardIDs.contains(card.id),
                isInlineEditing: isInlineEditing,
                showsLayerAffordance: isInlineEditing,
                footerElements: footerElements,
                editorRect: editorRect,
                footerRect: footerRect,
                containsMetaText: false,
                currentLayerName: currentLayer?.name ?? "Layer"
            )
        }

        let groups = projection.groupFrames
            .sorted { lhs, rhs in
                if lhs.resolvedOriginSlot.row != rhs.resolvedOriginSlot.row {
                    return lhs.resolvedOriginSlot.row < rhs.resolvedOriginSlot.row
                }
                if lhs.resolvedOriginSlot.column != rhs.resolvedOriginSlot.column {
                    return lhs.resolvedOriginSlot.column < rhs.resolvedOriginSlot.column
                }
                return lhs.group.id.uuidString < rhs.group.id.uuidString
            }
            .map { frame in
                let style = BWRCardBuddyBoardThemeGuardrail.groupPanelStyle(isSelected: fixture.selectedGroupID == frame.group.id)
                return BWRCardBuddyAcceptanceGroupSnapshot(
                    groupID: frame.group.id.uuidString,
                    name: frame.group.name,
                    memberCount: frame.group.memberCardIDs.count,
                    rect: BWRBoardRectSnapshot(rect: frame.rect),
                    isSelected: fixture.selectedGroupID == frame.group.id,
                    fillHex: style.fillHex,
                    fillOpacity: style.fillOpacity,
                    strokeHex: style.strokeHex,
                    strokeOpacity: style.strokeOpacity,
                    strokeWidth: Double(style.strokeWidth)
                )
            }

        return BWRCardBuddyAcceptanceBoardSnapshot(
            id: fixture.id,
            title: fixture.title,
            boardBackgroundHex: boardHex,
            metrics: cardMetrics,
            cardOrder: cards.map(\.cardID),
            cards: cards,
            groups: groups,
            overlays: overlaySnapshots(for: fixture, projection: projection)
        )
    }

    static func moveResult(for moveCase: BWRCardBuddyAcceptanceMoveCase) -> BWRCardBuddyAcceptanceMoveResult {
        let before = hostsByID(in: moveCase.document)
        var document = moveCase.document
        let adjusted = BWRSlotBoardInteraction.adjustedInsertionIndex(
            rawInsertionIndex: moveCase.rawInsertionIndex,
            movingCardIDs: moveCase.movingCardIDs,
            targetHost: moveCase.targetHost,
            document: document
        )

        _ = BWRDocumentReducer.moveCards(
            document: &document,
            to: moveCase.targetHost,
            cardIDs: moveCase.movingCardIDs,
            insertionIndex: adjusted
        )
        document = BWRSlotPlacementNormalizer.repairedDocument(document)

        let after = hostsByID(in: document)
        let projection = BWRSlotBoardProjection.project(document: document)
        let alignedCardIDs = moveCase.movingCardIDs.compactMap { cardID -> String? in
            guard let projected = projection.cardRectsByID[cardID] else { return nil }
            let expected = BWRSlotBoardGeometry.cardRect(
                in: projected.slotRect,
                inlineExpanded: false,
                metrics: projection.metrics
            )
            return projected.cardRect == expected ? cardID.uuidString : nil
        }

        let normalizedBefore = before.keys.sorted().reduce(into: [String: [String]]()) { partialResult, key in
            partialResult[key] = before[key, default: []].map(\.uuidString)
        }
        let normalizedAfter = after.keys.sorted().reduce(into: [String: [String]]()) { partialResult, key in
            partialResult[key] = after[key, default: []].map(\.uuidString)
        }
        let digestPayload = BWRCardBuddyAcceptanceMoveDigestPayload(
            id: moveCase.id,
            movingCardIDs: moveCase.movingCardIDs.map(\.uuidString),
            targetHostID: hostID(moveCase.targetHost),
            targetInsertionIndex: adjusted,
            hostsAfter: normalizedAfter
        )

        return BWRCardBuddyAcceptanceMoveResult(
            id: moveCase.id,
            title: moveCase.title,
            movingCardIDs: moveCase.movingCardIDs.map(\.uuidString),
            targetHostID: hostID(moveCase.targetHost),
            targetInsertionIndex: adjusted,
            hostsBefore: normalizedBefore,
            hostsAfter: normalizedAfter,
            alignedCardIDs: alignedCardIDs,
            digest: BWRCardBuddyAcceptanceDigest.hex(for: digestPayload)
        )
    }

    static func hostID(_ host: BWRSlotHost) -> String {
        switch host {
        case let .group(groupID):
            return "group:\(groupID.uuidString)"
        case let .strip(stripID):
            return "strip:\(stripID.uuidString)"
        }
    }

    private static func overlaySnapshots(
        for fixture: BWRCardBuddyVisualSnapshotFixture,
        projection: BWRSlotBoardProjectionSnapshot
    ) -> [BWRCardBuddyAcceptanceOverlaySnapshot] {
        var overlays: [BWRCardBuddyAcceptanceOverlaySnapshot] = []
        let modality = fixture.boardChromeState.slotCursor.lastInputModality

        if let cursor = fixture.boardChromeState.slotCursor.slotReference,
           fixture.boardChromeState.slotCursor.slotCursorVisibility == .visible,
           let rect = projection.slotRect(for: cursor) {
            let style = BWRCardBuddyStateGrammar.slotCursorStyle(isEmphasized: modality == .keyboard)
            overlays.append(
                BWRCardBuddyAcceptanceOverlaySnapshot(
                    role: style.role.rawValue,
                    hostID: hostID(cursor.host),
                    slotIndex: cursor.slotIndex,
                    descriptor: style.descriptor,
                    rects: [BWRBoardRectSnapshot(rect: rect)],
                    targetsEmptySlot: projection.cardID(at: cursor) == nil
                )
            )
        }

        if let hover = fixture.boardChromeState.hoverPlaceholder,
           let placeholder = hover.projectedPlaceholder(in: projection) {
            let style = BWRCardBuddyStateGrammar.hoverStyle(isEmphasized: modality == .pointer)
            let reference = BWRBoardSlotReference(host: hover.hoveredHost, slotIndex: hover.hoveredInsertionIndex)
            overlays.append(
                BWRCardBuddyAcceptanceOverlaySnapshot(
                    role: style.role.rawValue,
                    hostID: hostID(hover.hoveredHost),
                    slotIndex: hover.hoveredInsertionIndex,
                    descriptor: style.descriptor,
                    rects: [BWRBoardRectSnapshot(rect: placeholder.rect)],
                    targetsEmptySlot: projection.cardID(at: reference) == nil
                )
            )
        }

        let sourceRects = fixture.boardChromeState.dragOverlay.sourceRects(in: projection)
        if !sourceRects.isEmpty {
            let sourceReference = fixture.boardChromeState.dragOverlay.dragSourceSlots.first ?? fixture.boardChromeState.dragOverlay.dragSourceSlot
            let style = BWRCardBuddyStateGrammar.dragSourceStyle(
                isLifted: fixture.boardChromeState.dragOverlay.dragLiftStyle == .lifted
            )
            overlays.append(
                BWRCardBuddyAcceptanceOverlaySnapshot(
                    role: style.role.rawValue,
                    hostID: sourceReference.map { hostID($0.host) },
                    slotIndex: sourceReference?.slotIndex,
                    descriptor: style.descriptor,
                    rects: sourceRects.map(BWRBoardRectSnapshot.init(rect:)),
                    targetsEmptySlot: false
                )
            )
        }

        let destinationPlaceholders = fixture.boardChromeState.dragOverlay.destinationPlaceholders(in: projection)
        if !destinationPlaceholders.isEmpty {
            let destinationReference = fixture.boardChromeState.dragOverlay.dragDestinationSlots.first ?? fixture.boardChromeState.dragOverlay.dragDestinationSlot
            let style = BWRCardBuddyStateGrammar.dragDestinationStyle(host: destinationReference?.host)
            overlays.append(
                BWRCardBuddyAcceptanceOverlaySnapshot(
                    role: style.role.rawValue,
                    hostID: destinationReference.map { hostID($0.host) },
                    slotIndex: destinationReference?.slotIndex,
                    descriptor: style.descriptor,
                    rects: destinationPlaceholders.map { BWRBoardRectSnapshot(rect: $0.rect) },
                    targetsEmptySlot: destinationReference.flatMap { projection.cardID(at: $0) } == nil
                )
            )
        }

        return overlays.sorted { lhs, rhs in
            if lhs.role != rhs.role { return lhs.role < rhs.role }
            if lhs.hostID != rhs.hostID { return lhs.hostID ?? "" < rhs.hostID ?? "" }
            return (lhs.slotIndex ?? 0) < (rhs.slotIndex ?? 0)
        }
    }

    private static func baseDocument() -> BWRDocument {
        let timestamp = Date(timeIntervalSince1970: 0)
        let document = BWRDocument(
            schemaVersion: 2,
            createdAt: timestamp,
            updatedAt: timestamp,
            nextStableSortKey: 9,
            cards: [
                makeCard(
                    id: cardA1,
                    stableSortKey: 1,
                    colorHex: "F8FAFC",
                    bodyMarkdown: """
                    **Opening beat**
                    - Card Buddy shell
                    - Paper surface
                    """
                ),
                makeCard(
                    id: cardA2,
                    stableSortKey: 2,
                    colorHex: "FFFFFF",
                    bodyMarkdown: "Inline editor sample\nLayer cycle should stay subtle",
                    bodyCount: 2
                ),
                makeCard(
                    id: cardA3,
                    stableSortKey: 3,
                    colorHex: "FED7AA",
                    bodyMarkdown: "Colored card\nPaper tint guardrail"
                ),
                makeCard(
                    id: cardA4,
                    stableSortKey: 4,
                    colorHex: "F8FAFC",
                    bodyMarkdown: "Fourth card\nDrag source close"
                ),
                makeCard(
                    id: cardB1,
                    stableSortKey: 5,
                    colorHex: "DCFCE7",
                    bodyMarkdown: "Group B first"
                ),
                makeCard(
                    id: cardB2,
                    stableSortKey: 6,
                    colorHex: "E0F2FE",
                    bodyMarkdown: "Group B second"
                ),
                makeCard(
                    id: cardS1,
                    stableSortKey: 7,
                    colorHex: "F8FAFC",
                    bodyMarkdown: "Parking one"
                ),
                makeCard(
                    id: cardS2,
                    stableSortKey: 8,
                    colorHex: "F8FAFC",
                    bodyMarkdown: "Parking two"
                )
            ],
            groups: [
                BWRGroup(
                    id: groupAID,
                    name: "Alpha",
                    originSlot: BWRSlotCoordinate(column: 0, row: 0),
                    memberCardIDs: [cardA1, cardA2, cardA3, cardA4],
                    createdAt: timestamp,
                    updatedAt: timestamp
                ),
                BWRGroup(
                    id: groupBID,
                    name: "Beta",
                    originSlot: BWRSlotCoordinate(column: 0, row: 2),
                    memberCardIDs: [cardB1, cardB2],
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
            ],
            parkingStrips: [
                BWRParkingStrip(
                    id: stripID,
                    row: 5,
                    anchorColumn: 0,
                    cardIDs: [cardS1, cardS2]
                )
            ]
        )

        return BWRSlotPlacementNormalizer.repairedDocument(document)
    }

    private static func defaultViewport() -> BWRViewportState {
        BWRViewportState(
            zoomScale: 1,
            scrollOrigin: BWRPoint(x: 0, y: 0),
            viewportSize: BWRSize(width: 1440, height: 980)
        )
    }

    private static func makeCard(
        id: UUID,
        stableSortKey: Int64,
        colorHex: String,
        bodyMarkdown: String,
        bodyCount: Int = 1
    ) -> BWRCard {
        let layers = BWRCard.defaultLayers(
            bodyMarkdown: bodyMarkdown,
            bodyCount: bodyCount,
            treatmentMarkdown: "Treatment \(stableSortKey)",
            scenarioMarkdown: "Scenario \(stableSortKey)"
        )

        return BWRCard(
            id: id,
            stableSortKey: stableSortKey,
            colorHex: colorHex,
            currentLayerID: layers[0].id,
            layout: BWRPoint(x: 0, y: 0),
            createdAt: Date(timeIntervalSince1970: TimeInterval(stableSortKey)),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(stableSortKey)),
            layers: layers
        )
    }

    private static func hostsByID(in document: BWRDocument) -> [String: [UUID]] {
        var result: [String: [UUID]] = [:]
        for group in document.liveGroups {
            result[hostID(.group(group.id))] = group.memberCardIDs
        }
        for strip in document.parkingStrips {
            result[hostID(.strip(strip.id))] = strip.cardIDs
        }
        return result
    }
}
