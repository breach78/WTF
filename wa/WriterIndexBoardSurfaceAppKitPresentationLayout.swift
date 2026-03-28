import SwiftUI
import AppKit

extension IndexBoardSurfaceAppKitDocumentView {
    func applyCurrentLayout(animationDuration: TimeInterval) {
        let bounds = logicalGridBounds
        let gridWidth =
            (CGFloat(bounds.columnCount) * slotSize.width) +
            (CGFloat(max(0, bounds.columnCount - 1)) * IndexBoardMetrics.cardSpacing)
        let gridHeight =
            (CGFloat(bounds.rowCount) * slotSize.height) +
            (CGFloat(max(0, bounds.rowCount - 1)) * IndexBoardSurfaceAppKitConstants.lineSpacing)
        let documentSize = CGSize(
            width: max(
                configuration.canvasSize.width + IndexBoardSurfaceAppKitConstants.surfaceHorizontalOverscan,
                gridWidth + (surfaceHorizontalInset * 2) + IndexBoardSurfaceAppKitConstants.surfaceHorizontalOverscan
            ),
            height: max(
                configuration.canvasSize.height + IndexBoardSurfaceAppKitConstants.surfaceVerticalOverscan,
                gridHeight + surfaceTopInset + surfaceBottomInset + IndexBoardSurfaceAppKitConstants.surfaceVerticalOverscan
            )
        )
        if frame.size != documentSize {
            frame.size = documentSize
        }

        let nextCardFrames = resolvedCurrentCardFrames()
        cardFrameByID = nextCardFrames
        let validCardIDs = Set(orderedItems.map(\.cardID))
        let canReuseCardViews =
            shouldSkipCardViewReconcileForNextLayout &&
            Set(cardViews.keys) == validCardIDs
        shouldSkipCardViewReconcileForNextLayout = false
        let partialLaneKeys = partialLaneKeysForNextLayout
        partialLaneKeysForNextLayout = nil
        let shouldSkipIndicatorRefresh = shouldSkipIndicatorRefreshForNextLayout
        shouldSkipIndicatorRefreshForNextLayout = false

        if canReuseCardViews {
            for (cardID, cardView) in cardViews {
                cardView.isHidden = hiddenCardIDs.contains(cardID)
            }
        } else {
            reconcileCardViews()
            for (cardID, cardView) in cardViews {
                cardView.isHidden = hiddenCardIDs.contains(cardID)
            }
        }
        reconcileLaneChipViews(affectedLaneKeys: partialLaneKeys)
        updateStartAnchor()
        updateLaneWrappers(affectedLaneKeys: partialLaneKeys)
        updateSelectionLayer()
        if !shouldSkipIndicatorRefresh {
            updateIndicatorLayers()
        }
        updateHoverIndicatorLayer()
        updateOverlayLayers()
        layoutInlineEditorIfNeeded()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for item in orderedItems {
                guard let frame = nextCardFrames[item.cardID],
                      let cardView = cardViews[item.cardID] else { continue }
                if animationDuration > 0 {
                    cardView.animator().frame = frame
                } else {
                    cardView.frame = frame
                }
            }
            for (laneKey, chipView) in laneChipViews {
                let chipFrame = chipFrameByLaneKey[laneKey] ?? .zero
                if animationDuration > 0 {
                    chipView.animator().frame = chipFrame
                } else {
                    chipView.frame = chipFrame
                }
                chipView.isHidden = chipFrame.isEmpty
            }
        }

        ensureRevealIfNeeded()
    }

    func canReuseCardViews(
        from previous: IndexBoardSurfaceAppKitRenderState,
        to next: IndexBoardSurfaceAppKitRenderState
    ) -> Bool {
        previous.cardRenderStateByID == next.cardRenderStateByID &&
        previous.activeCardID == next.activeCardID &&
        previous.selectedCardIDs == next.selectedCardIDs &&
        previous.summaryByCardID == next.summaryByCardID &&
        previous.showsBackByCardID == next.showsBackByCardID &&
        previous.isInteractionEnabled == next.isInteractionEnabled &&
        previous.themeSignature == next.themeSignature &&
        Set(previous.surfaceProjection.orderedCardIDs) == Set(next.surfaceProjection.orderedCardIDs)
    }

    func resolvedLayoutDiff(
        from previous: IndexBoardSurfaceAppKitRenderState,
        to next: IndexBoardSurfaceAppKitRenderState
    ) -> IndexBoardSurfaceAppKitLayoutDiff {
        let previousItemsByID = Dictionary(
            uniqueKeysWithValues: previous.surfaceProjection.surfaceItems.map { ($0.cardID, $0) }
        )
        let nextItemsByID = Dictionary(
            uniqueKeysWithValues: next.surfaceProjection.surfaceItems.map { ($0.cardID, $0) }
        )
        let changedCardIDs = Set(previousItemsByID.keys).union(nextItemsByID.keys).filter { cardID in
            previousItemsByID[cardID] != nextItemsByID[cardID]
        }

        var affectedLaneKeys: Set<String> = []
        for cardID in changedCardIDs {
            if let previousItem = previousItemsByID[cardID] {
                affectedLaneKeys.insert(indexBoardSurfaceLaneKey(previousItem.laneParentID))
            }
            if let nextItem = nextItemsByID[cardID] {
                affectedLaneKeys.insert(indexBoardSurfaceLaneKey(nextItem.laneParentID))
            }
        }

        let previousGroupsByID = Dictionary(
            uniqueKeysWithValues: previous.surfaceProjection.parentGroups.map { ($0.id, $0) }
        )
        let nextGroupsByID = Dictionary(
            uniqueKeysWithValues: next.surfaceProjection.parentGroups.map { ($0.id, $0) }
        )
        for groupID in Set(previousGroupsByID.keys).union(nextGroupsByID.keys) {
            guard previousGroupsByID[groupID] != nextGroupsByID[groupID] else { continue }
            if let previousGroup = previousGroupsByID[groupID] {
                affectedLaneKeys.insert(indexBoardSurfaceLaneKey(previousGroup.parentCardID))
            }
            if let nextGroup = nextGroupsByID[groupID] {
                affectedLaneKeys.insert(indexBoardSurfaceLaneKey(nextGroup.parentCardID))
            }
        }

        let previousLaneKeys = Set(previous.surfaceProjection.lanes.map { indexBoardSurfaceLaneKey($0.parentCardID) })
        let nextLaneKeys = Set(next.surfaceProjection.lanes.map { indexBoardSurfaceLaneKey($0.parentCardID) })
        affectedLaneKeys.formUnion(previousLaneKeys.symmetricDifference(nextLaneKeys))

        return IndexBoardSurfaceAppKitLayoutDiff(
            changedCardIDs: changedCardIDs,
            affectedLaneKeys: affectedLaneKeys
        )
    }

    func updateStartAnchor() {
        let startRect = resolvedGridSlotRect(for: configuration.surfaceProjection.startAnchor.gridPosition)
        let anchorFrame = CGRect(
            x: startRect.minX - IndexBoardSurfaceAppKitConstants.startAnchorWidth - 20,
            y: startRect.minY,
            width: IndexBoardSurfaceAppKitConstants.startAnchorWidth,
            height: IndexBoardSurfaceAppKitConstants.startAnchorHeight
        )
        startAnchorLayer.path = CGPath(
            roundedRect: anchorFrame,
            cornerWidth: 13,
            cornerHeight: 13,
            transform: nil
        )
        let tint = indexBoardThemeAccentColor(theme: configuration.theme)
            .withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.92 : 0.84)
        startAnchorLayer.fillColor = tint.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.18 : 0.12).cgColor
        startAnchorLayer.strokeColor = tint.cgColor
        startAnchorLayer.lineWidth = 1.5
        startAnchorTextLayer.string = configuration.surfaceProjection.startAnchor.labelText
        startAnchorTextLayer.foregroundColor = tint.cgColor
        startAnchorTextLayer.frame = anchorFrame.insetBy(dx: 6, dy: 5)
    }

    func reconcileCardViews() {
        let measurementStart = baselineMeasurementStart()
        defer { recordBaselineTiming(\.reconcileCardViewsTiming, from: measurementStart) }
        let validCardIDs = Set(orderedItems.map(\.cardID))
        for (cardID, view) in cardViews where !validCardIDs.contains(cardID) {
            view.removeFromSuperview()
            cardViews.removeValue(forKey: cardID)
            updateBaselineSession { session in
                session.removedCardViews += 1
            }
        }

        for item in orderedItems {
            guard let card = configuration.cardsByID[item.cardID] else { continue }
            let view = cardViews[item.cardID] ?? {
                let created = IndexBoardSurfaceAppKitInteractiveCardView(cardID: item.cardID)
                created.interactionDelegate = self
                created.frame = CGRect(origin: .zero, size: IndexBoardMetrics.cardSize)
                addSubview(created)
                cardViews[item.cardID] = created
                updateBaselineSession { session in
                    session.createdCardViews += 1
                }
                return created
            }()

            view.update(
                card: card,
                theme: configuration.theme,
                isSelected: configuration.selectedCardIDs.contains(card.id),
                isActive: configuration.activeCardID == card.id,
                summary: configuration.summaryByCardID[card.id],
                showsBack: configuration.showsBackByCardID[card.id] ?? false
            )
        }
    }

    func reconcileLaneChipViews(affectedLaneKeys: Set<String>? = nil) {
        let measurementStart = baselineMeasurementStart()
        defer { recordBaselineTiming(\.reconcileLaneChipViewsTiming, from: measurementStart) }
        let laneFrames = resolvedLaneChipFrames()
        chipFrameByLaneKey = laneFrames
        let validKeys = Set(laneFrames.keys)
        let keysToUpdate = affectedLaneKeys ?? validKeys.union(laneChipViews.keys)
        for (key, view) in laneChipViews where keysToUpdate.contains(key) && !validKeys.contains(key) {
            view.removeFromSuperview()
            laneChipViews.removeValue(forKey: key)
            updateBaselineSession { session in
                session.removedLaneChipViews += 1
            }
        }

        let laneByKey = Dictionary(uniqueKeysWithValues: effectiveSurfaceProjection.lanes.map { (indexBoardSurfaceLaneKey($0.parentCardID), $0) })
        for (key, frame) in laneFrames where keysToUpdate.contains(key) {
            guard let lane = laneByKey[key] else { continue }
            let chipView = laneChipViews[key] ?? {
                let created = IndexBoardSurfaceAppKitLaneChipView(frame: frame)
                created.interactionDelegate = self
                addSubview(created)
                laneChipViews[key] = created
                updateBaselineSession { session in
                    session.createdLaneChipViews += 1
                }
                return created
            }()
            chipView.interactionDelegate = self
            chipView.update(
                model: .init(
                    lane: lane,
                    theme: configuration.theme,
                    displayText: resolvedLaneChipDisplayText(for: lane),
                    tintColorToken: resolvedLaneTintColorToken(for: lane)
                )
            )
            chipView.frame = frame
        }
    }

    func resolvedLaneChipDisplayText(for lane: BoardSurfaceLane) -> String {
        guard let parentCardID = lane.parentCardID,
              let card = configuration.cardsByID[parentCardID] else {
            return indexBoardSurfaceSingleLinePreview(lane.labelText)
        }

        return indexBoardSurfaceSingleLinePreview(
            indexBoardSurfaceResolvedPreviewText(
                card: card,
                summary: configuration.summaryByCardID[parentCardID]
            )
        )
    }

    func resolvedLaneChipFrames() -> [String: CGRect] {
        let orderedFlowItems = flowItems.sorted(by: indexBoardSurfaceAppKitSort)
        var seenKeys: Set<String> = []
        var frames: [String: CGRect] = [:]
        for item in orderedFlowItems {
            guard !hiddenCardIDs.contains(item.cardID) else { continue }
            let key = indexBoardSurfaceLaneKey(item.laneParentID)
            guard seenKeys.insert(key).inserted,
                  let itemFrame = cardFrameByID[item.cardID] else { continue }
            frames[key] = CGRect(
                x: itemFrame.minX,
                y: itemFrame.minY - IndexBoardSurfaceAppKitConstants.laneChipSpacing - IndexBoardSurfaceAppKitConstants.laneChipHeight,
                width: IndexBoardMetrics.cardSize.width,
                height: IndexBoardSurfaceAppKitConstants.laneChipHeight
            )
        }
        return frames
    }

    func resolvedParentGroupFrame(
        for group: BoardSurfaceParentGroupPlacement
    ) -> CGRect? {
        let groupFrames = orderedItems.compactMap { item -> CGRect? in
            guard item.parentGroupID == group.id,
                  !hiddenCardIDs.contains(item.cardID),
                  let frame = cardFrameByID[item.cardID] else { return nil }
            return frame
        }
        guard let firstFrame = groupFrames.first else { return nil }
        let cardUnion = groupFrames.dropFirst().reduce(firstFrame) { partial, frame in
            partial.union(frame)
        }
        let chipFrame = chipFrameByLaneKey[indexBoardSurfaceLaneKey(group.parentCardID)] ?? .null
        let baseFrame = chipFrame.isNull ? cardUnion : cardUnion.union(chipFrame)
        return baseFrame.insetBy(
            dx: -IndexBoardSurfaceAppKitConstants.laneWrapperInset,
            dy: -IndexBoardSurfaceAppKitConstants.laneWrapperInset
        )
    }

    func updateLaneWrappers(affectedLaneKeys: Set<String>? = nil) {
        let laneByKey = Dictionary(uniqueKeysWithValues: effectiveSurfaceProjection.lanes.map { (indexBoardSurfaceLaneKey($0.parentCardID), $0) })
        var frameByLaneKey: [String: CGRect] = [:]
        for group in effectiveSurfaceProjection.parentGroups {
            let key = indexBoardSurfaceLaneKey(group.parentCardID)
            if let frame = resolvedDisplayedParentGroupFrame(for: group) {
                frameByLaneKey[key] = frame
            }
        }

        let validKeys = Set(frameByLaneKey.keys)
        let keysToUpdate = affectedLaneKeys ?? validKeys.union(laneWrapperLayers.keys)
        for (key, layer) in laneWrapperLayers where keysToUpdate.contains(key) && !validKeys.contains(key) {
            layer.removeFromSuperlayer()
            laneWrapperLayers.removeValue(forKey: key)
        }

        for (key, frame) in frameByLaneKey where keysToUpdate.contains(key) {
            let wrapperLayer = laneWrapperLayers[key] ?? {
                let created = CAShapeLayer()
                layer?.insertSublayer(created, below: selectionLayer)
                laneWrapperLayers[key] = created
                return created
            }()
            let lane = laneByKey[key]
            wrapperLayer.path = CGPath(
                roundedRect: frame,
                cornerWidth: 18,
                cornerHeight: 18,
                transform: nil
            )
            let tint = resolvedLaneTintColor(for: lane)
            wrapperLayer.fillColor = tint.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.14 : 0.10).cgColor
            wrapperLayer.strokeColor = tint.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.72 : 0.44).cgColor
            wrapperLayer.lineWidth = 4
        }
    }

    func resolvedDisplayedParentGroupFrame(
        for group: BoardSurfaceParentGroupPlacement
    ) -> CGRect? {
        guard var frame = resolvedParentGroupFrame(for: group) else { return nil }
        guard let dragState,
              dragState.dropTarget.detachedGridPosition == nil,
              !dragState.dropTarget.isTempStripTarget,
              dragState.dropTarget.laneParentID == group.parentCardID else {
            return frame
        }

        let targetFrames = resolvedFlowTargetFrames(for: dragState)
        guard !targetFrames.isEmpty else { return frame }
        for targetFrame in targetFrames {
            frame = frame.union(targetFrame.insetBy(
                dx: -IndexBoardSurfaceAppKitConstants.laneWrapperInset,
                dy: -(IndexBoardSurfaceAppKitConstants.laneWrapperInset + 2)
            ))
        }
        return frame
    }

    func resolvedLaneTintColorToken(for lane: BoardSurfaceLane?) -> String? {
        guard let lane else { return nil }
        if lane.isTempLane {
            return nil
        }
        if let parentCardID = lane.parentCardID,
           let customHex = configuration.cardsByID[parentCardID]?.colorHex {
            return customHex
        }
        return lane.colorToken
    }

    func resolvedLaneTintColor(for lane: BoardSurfaceLane?) -> NSColor {
        if let lane, lane.isTempLane {
            return NSColor.orange.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.88 : 0.82)
        }
        if let token = resolvedLaneTintColorToken(for: lane),
           let rgb = parseHexRGB(token) {
            return NSColor(calibratedRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        }
        let borderRGB = configuration.theme.usesDarkAppearance ? (0.28, 0.30, 0.36) : (0.78, 0.75, 0.69)
        return NSColor(calibratedRed: borderRGB.0, green: borderRGB.1, blue: borderRGB.2, alpha: 1)
    }

    func resolvedParentGroupColorHex(parentCardID: UUID) -> String? {
        configuration.cardsByID[parentCardID]?.colorHex ??
        interactionProjection.parentGroups.first(where: { $0.parentCardID == parentCardID })?.colorToken
    }

    func canDeleteParentGroup(parentCardID: UUID) -> Bool {
        guard interactionProjection.parentGroups.contains(where: { $0.parentCardID == parentCardID }),
              let parentCard = configuration.cardsByID[parentCardID] else { return false }
        if parentCard.category == ScenarioCardCategory.note {
            return false
        }
        let firstLabel = parentCard.content
            .components(separatedBy: .newlines)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        if firstLabel == ScenarioCardCategory.note {
            return false
        }
        return firstLabel?.caseInsensitiveCompare("temp") != .orderedSame
    }

    func makeColorMenuItem(
        title: String,
        currentHex: String?,
        action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        appendColorItems(to: submenu, currentHex: currentHex, action: action)
        item.submenu = submenu
        return item
    }

    func appendColorItems(
        to menu: NSMenu,
        currentHex: String?,
        action: Selector
    ) {
        let defaultItem = NSMenuItem(title: "기본색", action: action, keyEquivalent: "")
        defaultItem.target = self
        defaultItem.representedObject = indexBoardSurfaceDefaultColorToken
        defaultItem.state = currentHex == nil ? .on : .off
        defaultItem.image = indexBoardSurfaceColorSwatchImage(
            hex: nil,
            defaultHex: configuration.theme.usesDarkAppearance
                ? configuration.theme.darkCardBaseColorHex
                : configuration.theme.cardBaseColorHex,
            usesDarkAppearance: configuration.theme.usesDarkAppearance
        )
        menu.addItem(defaultItem)
        menu.addItem(NSMenuItem.separator())

        for preset in indexBoardSurfaceColorPresets {
            let presetItem = NSMenuItem(title: preset.name, action: action, keyEquivalent: "")
            presetItem.target = self
            presetItem.representedObject = preset.hex
            presetItem.image = indexBoardSurfaceColorSwatchImage(
                hex: preset.hex,
                usesDarkAppearance: configuration.theme.usesDarkAppearance
            )
            if let currentHex,
               currentHex.caseInsensitiveCompare(preset.hex) == .orderedSame {
                presetItem.state = .on
            }
            menu.addItem(presetItem)
        }
    }

    func resolvedContextMenuColorHex(from representedObject: Any?) -> String? {
        guard let token = representedObject as? String else { return nil }
        return token == indexBoardSurfaceDefaultColorToken ? nil : token
    }

    func refreshColorDependentPresentation() {
        reconcileCardViews()
        reconcileLaneChipViews()
        updateLaneWrappers()
        refreshHoverIndicatorFromCurrentMouse()
    }

    func updateSelectionLayer() {
        guard let selectionRect = normalizedSelectionRect() else {
            selectionLayer.path = nil
            return
        }
        selectionLayer.path = CGPath(
            roundedRect: selectionRect,
            cornerWidth: 18,
            cornerHeight: 18,
            transform: nil
        )
    }

    func normalizedSelectionRect() -> CGRect? {
        guard let selectionState else { return nil }
        return CGRect(
            x: min(selectionState.startPoint.x, selectionState.currentPoint.x),
            y: min(selectionState.startPoint.y, selectionState.currentPoint.y),
            width: abs(selectionState.currentPoint.x - selectionState.startPoint.x),
            height: abs(selectionState.currentPoint.y - selectionState.startPoint.y)
        )
    }

    func resolvedSelectedCardIDs(in selectionRect: CGRect) -> Set<UUID> {
        Set(
            cardFrameByID.compactMap { cardID, frame in
                frame.intersects(selectionRect) ? cardID : nil
            }
        )
    }

    func updateHoverIndicator(at point: CGPoint) {
        guard dragState == nil,
              groupDragState == nil,
              selectionState == nil,
              !isHoverIndicatorSuppressed else {
            clearHoverIndicator()
            return
        }
        guard let candidate = resolvedHoverGridPositionCandidate(at: point) else {
            clearHoverIndicator()
            return
        }

        hoverGridPosition = candidate
        updateHoverIndicatorLayer()
    }

    func clearHoverIndicator() {
        hoverGridPosition = nil
        hoverIndicatorLayer.path = nil
        hoverIndicatorLayer.isHidden = true
    }

    func resolvedHoverGridPositionCandidate(at point: CGPoint) -> IndexBoardGridPosition? {
        guard editableParentCardID(at: point) == nil,
              cardID(at: point) == nil,
              movableParentGroupID(at: point) == nil else {
            return nil
        }

        let candidate = resolvedNearestGridPosition(for: point)
        let occupiedPositions = Set(occupiedGridPositionByCardID().values)
        guard !occupiedPositions.contains(candidate) else {
            return nil
        }
        return candidate
    }

    func updateHoverIndicatorLayer() {
        guard let hoverGridPosition else {
            clearHoverIndicator()
            return
        }

        let frame = resolvedCardFrame(for: hoverGridPosition).insetBy(
            dx: -IndexBoardSurfaceAppKitConstants.hoverIndicatorInset,
            dy: -IndexBoardSurfaceAppKitConstants.hoverIndicatorInset
        )
        hoverIndicatorLayer.path = CGPath(
            roundedRect: frame,
            cornerWidth: 16,
            cornerHeight: 16,
            transform: nil
        )
        let usesDarkAppearance = configuration.theme.usesDarkAppearance
        hoverIndicatorLayer.fillColor = NSColor.white.withAlphaComponent(usesDarkAppearance ? 0.04 : 0.10).cgColor
        hoverIndicatorLayer.strokeColor = NSColor.black.withAlphaComponent(usesDarkAppearance ? 0.30 : 0.24).cgColor
        hoverIndicatorLayer.lineWidth = IndexBoardSurfaceAppKitConstants.hoverIndicatorLineWidth
        hoverIndicatorLayer.lineDashPattern = [8, 6]
        hoverIndicatorLayer.shadowColor = NSColor.black.withAlphaComponent(usesDarkAppearance ? 0.08 : 0.04).cgColor
        hoverIndicatorLayer.shadowRadius = 3
        hoverIndicatorLayer.shadowOpacity = 1
        hoverIndicatorLayer.shadowOffset = .zero
        hoverIndicatorLayer.isHidden = false
    }

    func updateIndicatorLayers() {
        withIndexBoardSurfaceAppKitSignpost(IndexBoardSurfaceAppKitSignpostName.updateIndicatorLayers) {
            let measurementStart = baselineMeasurementStart()
            defer { recordBaselineTiming(\.updateIndicatorLayersTiming, from: measurementStart) }
            let sourceGapFrames: [CGRect]
            let sourceGapStyle: IndexBoardSurfaceAppKitPlaceholderStyle?
            if let dragState {
                sourceGapFrames = resolvedSourceGapFrames(for: dragState)
                sourceGapStyle = .flow
            } else if let groupDragState {
                sourceGapFrames = [groupDragState.initialFrame]
                sourceGapStyle = .flow
            } else {
                sourceGapFrames = []
                sourceGapStyle = nil
            }

            let targetFrames: [CGRect]
            let targetStyle: IndexBoardSurfaceAppKitPlaceholderStyle?
            if let dragState {
                let resolved = resolvedTargetIndicatorPresentation(for: dragState)
                targetFrames = resolved.frames
                targetStyle = resolved.style
            } else if groupDragState != nil,
                      let groupFrame = localGroupDragTargetFrame {
                targetFrames = [groupFrame]
                targetStyle = .detachedSlot
            } else {
                targetFrames = []
                targetStyle = nil
            }

            let focusFrames: [CGRect]
            if dragState == nil, groupDragState == nil {
                let highlightedCardIDs = orderedItems
                    .map(\.cardID)
                    .filter { configuration.selectedCardIDs.contains($0) || configuration.activeCardID == $0 }
                focusFrames = highlightedCardIDs.compactMap { cardFrameByID[$0] }
            } else {
                focusFrames = []
            }

            sourceGapLayers = replaceIndicatorLayers(
                existing: sourceGapLayers,
                frames: sourceGapFrames,
                style: sourceGapStyle
            )
            targetIndicatorLayers = replaceIndicatorLayers(
                existing: targetIndicatorLayers,
                frames: targetFrames,
                style: targetStyle
            )
            focusIndicatorLayers = replaceIndicatorLayers(
                existing: focusIndicatorLayers,
                frames: focusFrames,
                style: focusFrames.isEmpty ? nil : .detachedSlot
            )
        }
    }

    func replaceIndicatorLayers(
        existing: [CAShapeLayer],
        frames: [CGRect],
        style: IndexBoardSurfaceAppKitPlaceholderStyle?
    ) -> [CAShapeLayer] {
        existing.forEach { $0.removeFromSuperlayer() }
        updateBaselineSession { session in
            session.removedIndicatorLayers += existing.count
        }
        guard let style, !frames.isEmpty else { return [] }

        var nextLayers: [CAShapeLayer] = []
        nextLayers.reserveCapacity(frames.count)
        for frame in frames {
            let emphasizedFrame = frame.insetBy(
                dx: -IndexBoardSurfaceAppKitConstants.placeholderHighlightInset,
                dy: -IndexBoardSurfaceAppKitConstants.placeholderHighlightInset
            )
            let layer = CAShapeLayer()
            layer.path = CGPath(
                roundedRect: emphasizedFrame,
                cornerWidth: 16,
                cornerHeight: 16,
                transform: nil
            )
            layer.fillColor = resolvedPlaceholderFillColor(style: style).cgColor
            layer.strokeColor = resolvedPlaceholderStrokeColor(style: style).cgColor
            layer.lineWidth = resolvedPlaceholderLineWidth(style: style)
            layer.lineDashPattern = resolvedPlaceholderLineDashPattern(style: style)
            layer.shadowColor = NSColor.black.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.10 : 0.05).cgColor
            layer.shadowRadius = IndexBoardSurfaceAppKitConstants.placeholderShadowRadius
            layer.shadowOpacity = 1
            layer.shadowOffset = CGSize(width: 0, height: IndexBoardSurfaceAppKitConstants.placeholderShadowYOffset)
            if let hostLayer = self.layer {
                if selectionLayer.superlayer === hostLayer {
                    hostLayer.insertSublayer(layer, below: selectionLayer)
                } else {
                    hostLayer.insertSublayer(layer, at: 0)
                }
            }
            nextLayers.append(layer)
        }
        updateBaselineSession { session in
            session.createdIndicatorLayers += nextLayers.count
        }
        return nextLayers
    }

    func resolvedTargetIndicatorPresentation(
        for drag: IndexBoardSurfaceAppKitDragState
    ) -> (frames: [CGRect], style: IndexBoardSurfaceAppKitPlaceholderStyle) {
        if let detachedIndicator = resolvedDetachedIndicatorFrames(for: drag) {
            return detachedIndicator
        }
        return (resolvedFlowTargetFrames(for: drag), .detachedSlot)
    }

    func resolvedPlaceholderFillColor(style: IndexBoardSurfaceAppKitPlaceholderStyle) -> NSColor {
        switch style {
        case .flow:
            if configuration.theme.usesDarkAppearance {
                return NSColor.white.withAlphaComponent(0.08)
            }
            return NSColor.white.withAlphaComponent(0.58)
        case .detachedSlot:
            return indexBoardThemeAccentColor(theme: configuration.theme)
                .withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.20 : 0.18)
        case .detachedParking:
            return NSColor.white.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.04 : 0.12)
        }
    }

    func resolvedPlaceholderStrokeColor(style: IndexBoardSurfaceAppKitPlaceholderStyle) -> NSColor {
        switch style {
        case .flow:
        let borderRGB = configuration.theme.resolvedGroupBorderRGB
        return NSColor(
            calibratedRed: borderRGB.0,
            green: borderRGB.1,
            blue: borderRGB.2,
            alpha: configuration.theme.usesDarkAppearance ? 0.54 : 0.72
        )
        case .detachedSlot:
            return indexBoardThemeAccentColor(theme: configuration.theme).withAlphaComponent(0.98)
        case .detachedParking:
            return indexBoardThemeAccentColor(theme: configuration.theme)
                .withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.74 : 0.86)
        }
    }

    func resolvedPlaceholderLineWidth(style: IndexBoardSurfaceAppKitPlaceholderStyle) -> CGFloat {
        switch style {
        case .flow:
            return 1
        case .detachedSlot:
            return IndexBoardSurfaceAppKitConstants.detachedIndicatorLineWidth
        case .detachedParking:
            return IndexBoardSurfaceAppKitConstants.detachedParkingIndicatorLineWidth
        }
    }

    func resolvedPlaceholderLineDashPattern(style: IndexBoardSurfaceAppKitPlaceholderStyle) -> [NSNumber]? {
        switch style {
        case .detachedParking:
            return [8, 6]
        case .flow, .detachedSlot:
            return nil
        }
    }

    func resolvedSourceGapFrames(for drag: IndexBoardSurfaceAppKitDragState) -> [CGRect] {
        let hiddenCardIDs = Set(drag.movingCardIDs)
        return drag.movingCardIDs.compactMap { cardID in
            guard hiddenCardIDs.contains(cardID) else { return nil }
            return cardFrameByID[cardID]
        }
    }

    func resolvedFlowTargetFrames(for drag: IndexBoardSurfaceAppKitDragState) -> [CGRect] {
        guard !drag.dropTarget.isTempStripTarget,
              drag.dropTarget.detachedGridPosition == nil,
              !drag.dropTarget.holdsGroupBlock else {
            return []
        }

        let targetGroupID = drag.dropTarget.laneParentID.map(BoardSurfaceParentGroupID.parent) ?? .root
        guard let targetGroup = interactionProjection.parentGroups.first(where: { $0.id == targetGroupID }) else {
            return []
        }

        let insertionIndex = min(max(0, drag.dropTarget.insertionIndex), targetGroup.cardIDs.count)
        return drag.movingCardIDs.enumerated().map { offset, _ in
            resolvedCardFrame(
                for: IndexBoardGridPosition(
                    column: targetGroup.origin.column + insertionIndex + offset,
                    row: targetGroup.origin.row
                )
            )
        }
    }

    func updateOverlayLayers() {
        withIndexBoardSurfaceAppKitSignpost(IndexBoardSurfaceAppKitSignpostName.updateOverlayLayers) {
            let measurementStart = baselineMeasurementStart()
            defer { recordBaselineTiming(\.updateOverlayLayersTiming, from: measurementStart) }
            let removedOverlayLayerCount = overlayLayers.count
            overlayLayers.forEach { $0.removeFromSuperlayer() }
            overlayLayers.removeAll()
            updateBaselineSession { session in
                session.removedOverlayLayers += removedOverlayLayerCount
            }

            if let dragState {
                syncMovingCardViewsToOverlay(for: dragState)
                let origin = dragState.overlayOrigin()
                let overlayCardIDs = resolvedOverlayCardIDs(for: dragState)
                let snapshotByID = Dictionary(uniqueKeysWithValues: dragSnapshots.map { ($0.cardID, $0.image) })

                for (index, cardID) in overlayCardIDs.enumerated() {
                    guard let image = snapshotByID[cardID],
                          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
                    let reverseIndex = overlayCardIDs.count - index - 1
                    let stackX = CGFloat(reverseIndex) * 14
                    let stackY = CGFloat(reverseIndex) * 4
                    let layer = CALayer()
                    layer.contents = cgImage
                    layer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
                    layer.isOpaque = false
                    layer.frame = CGRect(
                        x: origin.x + stackX,
                        y: origin.y + stackY,
                        width: IndexBoardMetrics.cardSize.width,
                        height: IndexBoardMetrics.cardSize.height
                    )
                    layer.shadowColor = NSColor.black.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.22 : 0.14).cgColor
                    layer.shadowOpacity = 1
                    layer.shadowRadius = IndexBoardSurfaceAppKitConstants.overlayShadowRadius
                    layer.shadowOffset = CGSize(width: 0, height: IndexBoardSurfaceAppKitConstants.overlayShadowYOffset)
                    layer.opacity = cardID == dragState.cardID ? 1 : 0.92
                    self.layer?.addSublayer(layer)
                    overlayLayers.append(layer)
                }
                updateBaselineSession { session in
                    session.createdOverlayLayers += overlayLayers.count
                }
                return
            }

            guard let groupDragState,
                  let groupDragSnapshot,
                  let cgImage = groupDragSnapshot.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let layer = CALayer()
            layer.contents = cgImage
            layer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            layer.isOpaque = false
            layer.frame = CGRect(origin: groupDragState.overlayOrigin(), size: groupDragState.initialFrame.size)
            layer.shadowColor = NSColor.black.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.22 : 0.14).cgColor
            layer.shadowOpacity = 1
            layer.shadowRadius = IndexBoardSurfaceAppKitConstants.overlayShadowRadius + 2
            layer.shadowOffset = CGSize(width: 0, height: IndexBoardSurfaceAppKitConstants.overlayShadowYOffset + 2)
            self.layer?.addSublayer(layer)
            overlayLayers.append(layer)
            updateBaselineSession { session in
                session.createdOverlayLayers += 1
            }
        }
    }

    func syncMovingCardViewsToOverlay(for drag: IndexBoardSurfaceAppKitDragState) {
        let origin = drag.overlayOrigin()
        let orderedCardIDs = drag.movingCardIDs.filter { $0 != drag.cardID } + [drag.cardID]

        for (index, cardID) in orderedCardIDs.enumerated() {
            guard let cardView = cardViews[cardID] else { continue }
            let reverseIndex = orderedCardIDs.count - index - 1
            let stackX = CGFloat(reverseIndex) * 14
            let stackY = CGFloat(reverseIndex) * 4
            cardView.frame = CGRect(
                x: origin.x + stackX,
                y: origin.y + stackY,
                width: IndexBoardMetrics.cardSize.width,
                height: IndexBoardMetrics.cardSize.height
            )
        }
    }

    func resolvedOverlayCardIDs(for drag: IndexBoardSurfaceAppKitDragState) -> [UUID] {
        let supportingIDs = drag.movingCardIDs.filter { $0 != drag.cardID }
        let trailingSupport = Array(supportingIDs.suffix(3))
        return trailingSupport + [drag.cardID]
    }

    func makeSnapshotLayer(image: NSImage, frame: CGRect) -> CALayer? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let layer = CALayer()
        layer.contents = cgImage
        layer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer.isOpaque = false
        layer.frame = frame
        return layer
    }

    func cloneLaneWrapperLayer(_ source: CAShapeLayer) -> CAShapeLayer {
        let clone = CAShapeLayer()
        clone.path = source.path
        clone.fillColor = source.fillColor
        clone.strokeColor = source.strokeColor
        clone.lineWidth = source.lineWidth
        clone.lineDashPattern = source.lineDashPattern
        clone.shadowColor = source.shadowColor
        clone.shadowRadius = source.shadowRadius
        clone.shadowOpacity = source.shadowOpacity
        clone.shadowOffset = source.shadowOffset
        return clone
    }

    func setLiveSurfaceHidden(
        _ hidden: Bool,
        hiddenCardIDs: Set<UUID>? = nil,
        hidesChips: Bool = true,
        hidesWrappers: Bool = true
    ) {
        for (cardID, cardView) in cardViews {
            if hidden {
                cardView.isHidden = hiddenCardIDs?.contains(cardID) ?? true
            } else {
                cardView.isHidden = false
            }
        }
        if hidesChips {
            for chipView in laneChipViews.values {
                chipView.isHidden = hidden
            }
        }
        if hidesWrappers {
            for layer in laneWrapperLayers.values {
                layer.isHidden = hidden
            }
        }
        for layer in sourceGapLayers {
            layer.isHidden = hidden
        }
        for layer in targetIndicatorLayers {
            layer.isHidden = hidden
        }
        for layer in focusIndicatorLayers {
            layer.isHidden = hidden
        }
    }

    func beginMotionScene(
        snapshotCardIDs: Set<UUID>,
        hiddenLiveCardIDs: Set<UUID>,
        includingChips: Bool,
        includingWrappers: Bool
    ) {
        guard motionScene == nil,
              let hostLayer = layer else { return }

        let rootLayer = CALayer()
        rootLayer.frame = bounds

        let wrapperContainerLayer = CALayer()
        wrapperContainerLayer.frame = rootLayer.bounds
        rootLayer.addSublayer(wrapperContainerLayer)

        let indicatorContainerLayer = CALayer()
        indicatorContainerLayer.frame = rootLayer.bounds
        rootLayer.addSublayer(indicatorContainerLayer)

        let chipContainerLayer = CALayer()
        chipContainerLayer.frame = rootLayer.bounds
        rootLayer.addSublayer(chipContainerLayer)

        let cardContainerLayer = CALayer()
        cardContainerLayer.frame = rootLayer.bounds
        rootLayer.addSublayer(cardContainerLayer)

        var cardLayersByID: [UUID: CALayer] = [:]
        for item in orderedItems where snapshotCardIDs.contains(item.cardID) {
            guard let frame = cardFrameByID[item.cardID],
                  let snapshot = cardViews[item.cardID]?.snapshotImage(),
                  let cardLayer = makeSnapshotLayer(image: snapshot, frame: frame) else {
                continue
            }
            cardContainerLayer.addSublayer(cardLayer)
            cardLayersByID[item.cardID] = cardLayer
        }

        var chipLayersByLaneKey: [String: CALayer] = [:]
        if includingChips {
            for (laneKey, chipView) in laneChipViews {
                let frame = chipFrameByLaneKey[laneKey] ?? chipView.frame
                guard !frame.isEmpty,
                      let snapshot = chipView.snapshotImage(),
                      let chipLayer = makeSnapshotLayer(image: snapshot, frame: frame) else {
                    continue
                }
                chipContainerLayer.addSublayer(chipLayer)
                chipLayersByLaneKey[laneKey] = chipLayer
            }
        }

        var wrapperLayersByLaneKey: [String: CAShapeLayer] = [:]
        if includingWrappers {
            for group in effectiveSurfaceProjection.parentGroups {
                let laneKey = indexBoardSurfaceLaneKey(group.parentCardID)
                guard let sourceLayer = laneWrapperLayers[laneKey] else { continue }
                let wrapperLayer = cloneLaneWrapperLayer(sourceLayer)
                wrapperContainerLayer.addSublayer(wrapperLayer)
                wrapperLayersByLaneKey[laneKey] = wrapperLayer
            }
        }

        hostLayer.insertSublayer(rootLayer, below: selectionLayer)
        motionScene = IndexBoardSurfaceAppKitMotionScene(
            rootLayer: rootLayer,
            wrapperContainerLayer: wrapperContainerLayer,
            indicatorContainerLayer: indicatorContainerLayer,
            chipContainerLayer: chipContainerLayer,
            cardContainerLayer: cardContainerLayer,
            hiddenLiveCardIDs: hiddenLiveCardIDs,
            hidesLiveChips: includingChips,
            hidesLiveWrappers: includingWrappers,
            cardLayersByID: cardLayersByID,
            chipLayersByLaneKey: chipLayersByLaneKey,
            wrapperLayersByLaneKey: wrapperLayersByLaneKey,
            sourceGapLayers: [],
            targetIndicatorLayers: []
        )
        setLiveSurfaceHidden(
            true,
            hiddenCardIDs: hiddenLiveCardIDs,
            hidesChips: includingChips,
            hidesWrappers: includingWrappers
        )
        updateMotionSceneLayout()
    }

    func endMotionScene() {
        let hidesLiveChips = motionScene?.hidesLiveChips ?? true
        let hidesLiveWrappers = motionScene?.hidesLiveWrappers ?? true
        motionScene?.rootLayer.removeFromSuperlayer()
        motionScene = nil
        keepsMotionSceneUntilCommittedLayout = false
        setLiveSurfaceHidden(false, hidesChips: hidesLiveChips, hidesWrappers: hidesLiveWrappers)
    }

    func updateLivePreviewCardFrames(
        using previewCardFrames: [UUID: CGRect],
        hiddenCardIDs: Set<UUID>
    ) {
        guard !hiddenCardIDs.isEmpty else { return }
        for item in orderedItems {
            guard !hiddenCardIDs.contains(item.cardID),
                  let cardView = cardViews[item.cardID],
                  let frame = previewCardFrames[item.cardID] else {
                continue
            }
            cardView.frame = frame
            cardView.isHidden = false
        }
    }

    func resolvedPreviewLaneChipFrames(
        using cardFramesByID: [UUID: CGRect]
    ) -> [String: CGRect] {
        let orderedFlowItems = flowItems.sorted(by: indexBoardSurfaceAppKitSort)
        var seenKeys: Set<String> = []
        var frames: [String: CGRect] = [:]
        for item in orderedFlowItems {
            guard !hiddenCardIDs.contains(item.cardID) else { continue }
            let key = indexBoardSurfaceLaneKey(item.laneParentID)
            guard seenKeys.insert(key).inserted,
                  let itemFrame = cardFramesByID[item.cardID] else { continue }
            frames[key] = CGRect(
                x: itemFrame.minX,
                y: itemFrame.minY - IndexBoardSurfaceAppKitConstants.laneChipSpacing - IndexBoardSurfaceAppKitConstants.laneChipHeight,
                width: IndexBoardMetrics.cardSize.width,
                height: IndexBoardSurfaceAppKitConstants.laneChipHeight
            )
        }
        return frames
    }

    func resolvedPreviewParentGroupFrame(
        for group: BoardSurfaceParentGroupPlacement,
        cardFramesByID: [UUID: CGRect],
        chipFramesByLaneKey: [String: CGRect]
    ) -> CGRect? {
        let groupFrames = orderedItems.compactMap { item -> CGRect? in
            guard item.parentGroupID == group.id,
                  !hiddenCardIDs.contains(item.cardID),
                  let frame = cardFramesByID[item.cardID] else { return nil }
            return frame
        }
        guard let firstFrame = groupFrames.first else { return nil }
        let cardUnion = groupFrames.dropFirst().reduce(firstFrame) { partial, frame in
            partial.union(frame)
        }
        let chipFrame = chipFramesByLaneKey[indexBoardSurfaceLaneKey(group.parentCardID)] ?? .null
        let baseFrame = chipFrame.isNull ? cardUnion : cardUnion.union(chipFrame)
        return baseFrame.insetBy(
            dx: -IndexBoardSurfaceAppKitConstants.laneWrapperInset,
            dy: -IndexBoardSurfaceAppKitConstants.laneWrapperInset
        )
    }

    func resolvedPreviewDisplayedParentGroupFrame(
        for group: BoardSurfaceParentGroupPlacement,
        cardFramesByID: [UUID: CGRect],
        chipFramesByLaneKey: [String: CGRect]
    ) -> CGRect? {
        guard var frame = resolvedPreviewParentGroupFrame(
            for: group,
            cardFramesByID: cardFramesByID,
            chipFramesByLaneKey: chipFramesByLaneKey
        ) else {
            return nil
        }
        guard let dragState,
              dragState.dropTarget.detachedGridPosition == nil,
              !dragState.dropTarget.isTempStripTarget,
              dragState.dropTarget.laneParentID == group.parentCardID else {
            return frame
        }

        let targetFrames = resolvedFlowTargetFrames(for: dragState)
        guard !targetFrames.isEmpty else { return frame }
        for targetFrame in targetFrames {
            frame = frame.union(targetFrame.insetBy(
                dx: -IndexBoardSurfaceAppKitConstants.laneWrapperInset,
                dy: -(IndexBoardSurfaceAppKitConstants.laneWrapperInset + 2)
            ))
        }
        return frame
    }

    func resolvedPreviewLaneWrapperFrames(
        cardFramesByID: [UUID: CGRect],
        chipFramesByLaneKey: [String: CGRect]
    ) -> [String: CGRect] {
        var frameByLaneKey: [String: CGRect] = [:]
        for group in effectiveSurfaceProjection.parentGroups {
            let key = indexBoardSurfaceLaneKey(group.parentCardID)
            if let frame = resolvedPreviewDisplayedParentGroupFrame(
                for: group,
                cardFramesByID: cardFramesByID,
                chipFramesByLaneKey: chipFramesByLaneKey
            ) {
                frameByLaneKey[key] = frame
            }
        }
        return frameByLaneKey
    }

    func replaceMotionSceneIndicatorLayers(
        existing: [CAShapeLayer],
        frames: [CGRect],
        style: IndexBoardSurfaceAppKitPlaceholderStyle?,
        in hostLayer: CALayer
    ) -> [CAShapeLayer] {
        existing.forEach { $0.removeFromSuperlayer() }
        guard let style, !frames.isEmpty else { return [] }

        var nextLayers: [CAShapeLayer] = []
        nextLayers.reserveCapacity(frames.count)
        for frame in frames {
            let emphasizedFrame = frame.insetBy(
                dx: -IndexBoardSurfaceAppKitConstants.placeholderHighlightInset,
                dy: -IndexBoardSurfaceAppKitConstants.placeholderHighlightInset
            )
            let layer = CAShapeLayer()
            layer.path = CGPath(
                roundedRect: emphasizedFrame,
                cornerWidth: 16,
                cornerHeight: 16,
                transform: nil
            )
            layer.fillColor = resolvedPlaceholderFillColor(style: style).cgColor
            layer.strokeColor = resolvedPlaceholderStrokeColor(style: style).cgColor
            layer.lineWidth = resolvedPlaceholderLineWidth(style: style)
            layer.lineDashPattern = resolvedPlaceholderLineDashPattern(style: style)
            layer.shadowColor = NSColor.black.withAlphaComponent(configuration.theme.usesDarkAppearance ? 0.10 : 0.05).cgColor
            layer.shadowRadius = IndexBoardSurfaceAppKitConstants.placeholderShadowRadius
            layer.shadowOpacity = 1
            layer.shadowOffset = CGSize(width: 0, height: IndexBoardSurfaceAppKitConstants.placeholderShadowYOffset)
            hostLayer.addSublayer(layer)
            nextLayers.append(layer)
        }
        return nextLayers
    }

    func updateMotionSceneLayout() {
        guard var motionScene else { return }

        motionScene.rootLayer.frame = bounds
        motionScene.wrapperContainerLayer.frame = motionScene.rootLayer.bounds
        motionScene.indicatorContainerLayer.frame = motionScene.rootLayer.bounds
        motionScene.chipContainerLayer.frame = motionScene.rootLayer.bounds
        motionScene.cardContainerLayer.frame = motionScene.rootLayer.bounds

        let previewCardFrames = resolvedCurrentCardFrames()
        updateLivePreviewCardFrames(
            using: previewCardFrames,
            hiddenCardIDs: motionScene.hiddenLiveCardIDs
        )
        for (cardID, layer) in motionScene.cardLayersByID {
            guard !hiddenCardIDs.contains(cardID),
                  let frame = previewCardFrames[cardID] ?? restingSceneSnapshot?.cardFrameByID[cardID] else {
                layer.isHidden = true
                continue
            }
            layer.frame = frame
            layer.isHidden = false
        }

        let previewChipFrames = resolvedPreviewLaneChipFrames(using: previewCardFrames)
        for (laneKey, layer) in motionScene.chipLayersByLaneKey {
            guard let frame = previewChipFrames[laneKey], !frame.isEmpty else {
                layer.isHidden = true
                continue
            }
            layer.frame = frame
            layer.isHidden = false
        }

        let previewWrapperFrames = resolvedPreviewLaneWrapperFrames(
            cardFramesByID: previewCardFrames,
            chipFramesByLaneKey: previewChipFrames
        )
        for (laneKey, wrapperLayer) in motionScene.wrapperLayersByLaneKey {
            guard let frame = previewWrapperFrames[laneKey] else {
                wrapperLayer.isHidden = true
                continue
            }
            wrapperLayer.path = CGPath(
                roundedRect: frame,
                cornerWidth: 18,
                cornerHeight: 18,
                transform: nil
            )
            wrapperLayer.isHidden = false
        }

        let sourceGapFrames: [CGRect]
        let sourceGapStyle: IndexBoardSurfaceAppKitPlaceholderStyle?
        if let dragState {
            sourceGapFrames = resolvedSourceGapFrames(for: dragState)
            sourceGapStyle = .flow
        } else if let groupDragState {
            sourceGapFrames = [groupDragState.initialFrame]
            sourceGapStyle = .flow
        } else {
            sourceGapFrames = []
            sourceGapStyle = nil
        }

        let targetFrames: [CGRect]
        let targetStyle: IndexBoardSurfaceAppKitPlaceholderStyle?
        if let dragState {
            let resolved = resolvedTargetIndicatorPresentation(for: dragState)
            targetFrames = resolved.frames
            targetStyle = resolved.style
        } else if groupDragState != nil,
                  let groupFrame = localGroupDragTargetFrame {
            targetFrames = [groupFrame]
            targetStyle = .detachedSlot
        } else {
            targetFrames = []
            targetStyle = nil
        }

        motionScene.sourceGapLayers = replaceMotionSceneIndicatorLayers(
            existing: motionScene.sourceGapLayers,
            frames: sourceGapFrames,
            style: sourceGapStyle,
            in: motionScene.indicatorContainerLayer
        )
        motionScene.targetIndicatorLayers = replaceMotionSceneIndicatorLayers(
            existing: motionScene.targetIndicatorLayers,
            frames: targetFrames,
            style: targetStyle,
            in: motionScene.indicatorContainerLayer
        )

        self.motionScene = motionScene
    }

    func beginBaselineSession(kind: String, movingCardCount: Int) {
        baselineSession = IndexBoardSurfaceAppKitBaselineSession(
            kind: kind,
            startedAt: Date(),
            startedTimestamp: CFAbsoluteTimeGetCurrent(),
            orderedItemCountAtStart: orderedItems.count,
            laneCountAtStart: effectiveSurfaceProjection.lanes.count,
            movingCardCountAtStart: movingCardCount
        )
    }

    func finishBaselineSession(didCommit: Bool) {
        guard let session = baselineSession else { return }
        IndexBoardSurfaceAppKitBaselineLogger.append(session: session, didCommit: didCommit)
        baselineSession = nil
    }

    func updateBaselineSession(
        _ update: (inout IndexBoardSurfaceAppKitBaselineSession) -> Void
    ) {
        guard var session = baselineSession else { return }
        update(&session)
        baselineSession = session
    }

    func baselineMeasurementStart() -> CFTimeInterval? {
        guard baselineSession != nil else { return nil }
        return CFAbsoluteTimeGetCurrent()
    }

    func recordBaselineTiming(
        _ keyPath: WritableKeyPath<IndexBoardSurfaceAppKitBaselineSession, IndexBoardSurfaceAppKitTimingMetric>,
        from measurementStart: CFTimeInterval?
    ) {
        guard let measurementStart else { return }
        let duration = CFAbsoluteTimeGetCurrent() - measurementStart
        updateBaselineSession { session in
            session[keyPath: keyPath].record(duration)
        }
    }

    func recordBaselineTiming<T>(
        _ keyPath: WritableKeyPath<IndexBoardSurfaceAppKitBaselineSession, IndexBoardSurfaceAppKitTimingMetric>,
        _ body: () -> T
    ) -> T {
        guard baselineSession != nil else { return body() }
        let measurementStart = CFAbsoluteTimeGetCurrent()
        let result = body()
        recordBaselineTiming(keyPath, from: measurementStart)
        return result
    }

    func recordBaselineDragTick(
        autoScrolled: Bool,
        _ body: () -> Void
    ) {
        guard baselineSession != nil else {
            body()
            return
        }
        let measurementStart = CFAbsoluteTimeGetCurrent()
        body()
        let duration = CFAbsoluteTimeGetCurrent() - measurementStart
        updateBaselineSession { session in
            session.dragUpdateTickCount += 1
            if autoScrolled {
                session.autoScrollTickCount += 1
            }
            session.dragUpdateTiming.record(duration)
        }
    }

    func ensureRevealIfNeeded() {
        guard configuration.revealRequestToken != lastRevealRequestToken else { return }
        lastRevealRequestToken = configuration.revealRequestToken
        ensureCardVisible(configuration.revealCardID)
    }

    func startAutoScrollTimer() {
        stopAutoScrollTimer()
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.handleAutoScrollTick()
        }
    }

    func stopAutoScrollTimer() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }

    func handleAutoScrollTick() {
        guard var dragState,
              let scrollView else { return }
        let visibleRect = scrollView.documentVisibleRect
        let pointerInViewport = CGPoint(
            x: dragState.pointerInContent.x - visibleRect.minX,
            y: dragState.pointerInContent.y - visibleRect.minY
        )
        let delta = CGPoint(
            x: autoScrollAxisDelta(position: pointerInViewport.x, viewportLength: visibleRect.width),
            y: autoScrollAxisDelta(position: pointerInViewport.y, viewportLength: visibleRect.height)
        )
        guard delta != .zero else { return }
        let maxX = max(0, frame.width - visibleRect.width)
        let maxY = max(0, frame.height - visibleRect.height)
        let targetX = min(max(0, visibleRect.origin.x + delta.x), maxX)
        let targetY = min(max(0, visibleRect.origin.y + delta.y), maxY)
        guard targetX != visibleRect.origin.x || targetY != visibleRect.origin.y else { return }

        scrollView.contentView.setBoundsOrigin(CGPoint(x: targetX, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        let previousTarget = dragState.dropTarget
        dragState.dropTarget = resolvedDropTarget(for: dragState)
        applyCardDragUpdate(dragState, previousTarget: previousTarget)
    }

    func prepareViewportPreservationAfterDrop(_ preservedOrigin: CGPoint?) {
        pendingDropPreservedScrollOrigin = preservedOrigin
        suppressViewportChangeNotifications = preservedOrigin != nil
    }

    func restoreScrollOriginAfterDrop(
        _ preservedOrigin: CGPoint?,
        notifySession: Bool
    ) {
        guard let scrollView,
              let preservedOrigin else { return }
        let visibleRect = scrollView.documentVisibleRect
        let maxX = max(0, frame.width - visibleRect.width)
        let maxY = max(0, frame.height - visibleRect.height)
        let clampedOrigin = CGPoint(
            x: min(max(0, preservedOrigin.x), maxX),
            y: min(max(0, preservedOrigin.y), maxY)
        )
        let currentOrigin = scrollView.contentView.bounds.origin
        guard abs(currentOrigin.x - clampedOrigin.x) > 0.5 ||
                abs(currentOrigin.y - clampedOrigin.y) > 0.5 else {
            return
        }
        scrollView.contentView.setBoundsOrigin(clampedOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        if notifySession {
            configuration.onScrollOffsetChange(clampedOrigin)
        }
    }

    func autoScrollAxisDelta(position: CGFloat, viewportLength: CGFloat) -> CGFloat {
        let edge = IndexBoardSurfaceAppKitConstants.autoScrollEdgeInset
        if position < edge {
            let progress = max(0, min(1, (edge - position) / edge))
            return -IndexBoardSurfaceAppKitConstants.maxAutoScrollStep * progress
        }
        if position > viewportLength - edge {
            let progress = max(0, min(1, (position - (viewportLength - edge)) / edge))
            return IndexBoardSurfaceAppKitConstants.maxAutoScrollStep * progress
        }
        return 0
    }
}
