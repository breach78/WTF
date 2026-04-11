import Foundation

enum BWRHarnessFixtures {
    static func temporaryPackageURL(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
            .appendingPathExtension("bwr")
    }

    static func singleLayerProject() -> BoardProject {
        BoardProject.singleLayer(
            seeds: [
                .init(
                    cardID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    contentID: UUID(uuidString: "AAAAAAAA-1111-1111-1111-111111111111")!,
                    layerID: UUID(uuidString: "BBBBBBBB-1111-1111-1111-111111111111")!,
                    slot: BoardSlot(row: 0, column: 0),
                    markdown: "# Opening beat\nA precise first note.",
                    palette: .paper,
                    createdAt: Date(timeIntervalSince1970: 1_710_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_710_000_100)
                ),
                .init(
                    cardID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    contentID: UUID(uuidString: "AAAAAAAA-2222-2222-2222-222222222222")!,
                    layerID: UUID(uuidString: "BBBBBBBB-2222-2222-2222-222222222222")!,
                    slot: BoardSlot(row: 1, column: 2),
                    markdown: "## Turn\nA second card with blush emphasis.",
                    palette: .blush,
                    createdAt: Date(timeIntervalSince1970: 1_710_000_200),
                    updatedAt: Date(timeIntervalSince1970: 1_710_000_300)
                )
            ]
        )
    }

    static func multiLayerProject() -> BoardProject {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let secondaryLayerID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let contentID = UUID(uuidString: "CCCCCCCC-3333-3333-3333-333333333333")!

        let content = BoardCardContent(
            id: contentID,
            createdAt: now,
            layers: [
                BoardLayer(
                    id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                    index: 0,
                    createdAt: now,
                    markdown: "# Base\nLayer zero",
                    palette: .paper,
                    updatedAt: now
                ),
                BoardLayer(
                    id: secondaryLayerID,
                    index: 1,
                    createdAt: now,
                    markdown: "## Alternate\nLayer one is presented",
                    palette: .mist,
                    updatedAt: now.addingTimeInterval(30)
                )
            ],
            updatedAt: now.addingTimeInterval(30)
        )

        return BoardProject(
            cards: [
                BoardCardInstance(
                    id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                    contentID: contentID,
                    slot: BoardSlot(row: 0, column: 1),
                    presentedLayerID: secondaryLayerID,
                    palette: .butter,
                    createdAt: now,
                    updatedAt: now.addingTimeInterval(30)
                )
            ],
            contents: [contentID: content]
        )
    }
}
