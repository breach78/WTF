import CryptoKit
import Foundation
import SQLite3

enum BWRSQLitePackageStoreError: LocalizedError {
    case invalidPackage(String)
    case sqlite(String)
    case invalidMetadata
    case invalidContentRow(String)
    case invalidCardRow(String)
    case invalidAssetRow(String)
    case thumbnailMissing

    var errorDescription: String? {
        switch self {
        case .invalidPackage(let reason):
            return "The .bwr package is invalid: \(reason)"
        case .sqlite(let message):
            return "SQLite storage failed: \(message)"
        case .invalidMetadata:
            return "The package metadata could not be decoded."
        case .invalidContentRow(let reason):
            return "A content row could not be decoded: \(reason)"
        case .invalidCardRow(let reason):
            return "A card row could not be decoded: \(reason)"
        case .invalidAssetRow(let reason):
            return "An asset row could not be decoded: \(reason)"
        case .thumbnailMissing:
            return "The package thumbnail was not written."
        }
    }
}

enum BWRSQLitePackageStore {
    static let databaseFilename = "database.sqlite"
    static let assetsDirectoryName = "assets"
    static let thumbnailFilename = "thumbnail.jpg"

    private static let schemaVersion = 1
    private static let iso8601 = BWRISO8601Codec()

    static func read(from url: URL) throws -> BWRDocument {
        let databaseURL = url.appendingPathComponent(databaseFilename, isDirectory: false)
        let assetsURL = url.appendingPathComponent(assetsDirectoryName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw BWRSQLitePackageStoreError.invalidPackage("\(databaseFilename) is missing")
        }

        let database = try SQLiteDatabase.open(url: databaseURL, readOnly: true)
        defer { database.close() }

        try database.exec("PRAGMA foreign_keys = ON;")
        let metadata = try loadMetadata(from: database)
        let contents = try loadContents(from: database)
        let cards = try loadCardInstances(from: database)
        let assets = try loadAssets(from: database, assetsDirectoryURL: assetsURL)
        let project = BoardProject(cards: cards, contents: contents, assets: assets)
        return BWRDocument(metadata: metadata, project: project)
    }

    static func read(from wrapper: FileWrapper) throws -> BWRDocument {
        let temporaryURL = temporaryPackageURL(prefix: "bwr-read-wrapper")
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        try wrapper.write(to: temporaryURL, options: .atomic, originalContentsURL: nil)
        return try read(from: temporaryURL)
    }

    static func fileWrapper(
        document: BWRDocument,
        preferredFileName: String
    ) throws -> FileWrapper {
        let temporaryURL = temporaryPackageURL(prefix: "bwr-file-wrapper")
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        try writePackage(document: document, to: temporaryURL)
        let wrapper = try FileWrapper(url: temporaryURL, options: .immediate)
        wrapper.preferredFilename = preferredFileName
        return wrapper
    }

    static func fullWrite(document: BWRDocument, to url: URL) throws {
        let temporaryURL = siblingTemporaryPackageURL(for: url)
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        try writePackage(document: document, to: temporaryURL)
        try validatePackage(at: temporaryURL)
        try atomicReplaceItem(at: url, withItemAt: temporaryURL)
    }

    private static func writePackage(document: BWRDocument, to packageURL: URL) throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: packageURL)
        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)

        let assetsURL = packageURL.appendingPathComponent(assetsDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: assetsURL, withIntermediateDirectories: true)

        let databaseURL = packageURL.appendingPathComponent(databaseFilename, isDirectory: false)
        let metadata = BoardContainerMetadata(
            id: document.metadata.id,
            createdAt: document.metadata.createdAt,
            updatedAt: BWRTimestamp.now()
        )

        let database = try SQLiteDatabase.open(url: databaseURL, readOnly: false)
        do {
            try database.exec("PRAGMA journal_mode = DELETE;")
            try database.exec("PRAGMA foreign_keys = ON;")
            try database.exec(schemaSQL)
            try database.beginTransaction()
            do {
                try writeDocument(metadata: metadata, project: document.project, into: database)
                try database.commitTransaction()
            } catch {
                try? database.rollbackTransaction()
                throw error
            }
        } catch {
            database.close()
            throw error
        }
        database.close()

        for asset in document.project.assets.values {
            let assetURL = assetsURL.appendingPathComponent(asset.storedFilename, isDirectory: false)
            try asset.data.write(to: assetURL, options: .atomic)
        }

        let thumbnailURL = packageURL.appendingPathComponent(thumbnailFilename, isDirectory: false)
        let thumbnailData = try BWRDocumentThumbnailRenderer.renderJPEG(for: document.project)
        try thumbnailData.write(to: thumbnailURL, options: .atomic)
    }

    private static func validatePackage(at packageURL: URL) throws {
        let fileManager = FileManager.default
        let databaseURL = packageURL.appendingPathComponent(databaseFilename, isDirectory: false)
        let assetsURL = packageURL.appendingPathComponent(assetsDirectoryName, isDirectory: true)
        let thumbnailURL = packageURL.appendingPathComponent(thumbnailFilename, isDirectory: false)

        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw BWRSQLitePackageStoreError.invalidPackage("\(databaseFilename) is missing after write")
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: assetsURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BWRSQLitePackageStoreError.invalidPackage("\(assetsDirectoryName) is missing after write")
        }

        guard fileManager.fileExists(atPath: thumbnailURL.path) else {
            throw BWRSQLitePackageStoreError.thumbnailMissing
        }

        let database = try SQLiteDatabase.open(url: databaseURL, readOnly: true)
        defer { database.close() }
        let assets = try loadAssets(from: database, assetsDirectoryURL: assetsURL)
        for asset in assets.values {
            let assetURL = assetsURL.appendingPathComponent(asset.storedFilename, isDirectory: false)
            guard fileManager.fileExists(atPath: assetURL.path) else {
                throw BWRSQLitePackageStoreError.invalidPackage("\(asset.storedFilename) is missing after write")
            }
        }
    }

    private static func atomicReplaceItem(at destinationURL: URL, withItemAt sourceURL: URL) throws {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: sourceURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func writeDocument(
        metadata: BoardContainerMetadata,
        project: BoardProject,
        into database: SQLiteDatabase
    ) throws {
        let updatedAt = iso8601.string(from: metadata.updatedAt)
        let createdAt = iso8601.string(from: metadata.createdAt)
        let documentID = metadata.id.uuidString

        try database.run(
            """
            INSERT INTO DocumentMeta (documentId, createdAt, updatedAt, schemaVersion)
            VALUES (?, ?, ?, ?);
            """,
            bindings: [
                .text(documentID),
                .text(createdAt),
                .text(updatedAt),
                .int(Int64(schemaVersion))
            ]
        )

        try database.run(
            """
            INSERT INTO DocumentSettings (
                documentId,
                canvasTemplate,
                layoutAlgorithm,
                layoutMode,
                insertMode,
                cardWidth,
                cardHeight,
                spacingX,
                spacingY,
                cardCornerRadius,
                backgroundTone,
                defaultCardPalette,
                tabKeySaves,
                enterKeySaves,
                lastModified
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(documentID),
                .text("chronological"),
                .text("chronological"),
                .text("grid"),
                .text("horizontal"),
                .double(Double(BWRBoardLayoutMetrics.cardSize.width)),
                .double(Double(BWRBoardLayoutMetrics.cardSize.height)),
                .double(Double(BWRBoardLayoutMetrics.gridSpacing)),
                .double(Double(BWRBoardLayoutMetrics.gridSpacing)),
                .double(Double(BWRBoardLayoutMetrics.cardSurfaceCorner)),
                .text("sand"),
                .null,
                .int(1),
                .int(1),
                .text(updatedAt)
            ]
        )

        for asset in project.assets.values.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            try database.run(
                """
                INSERT INTO Assets (
                    assetId,
                    storedFilename,
                    originalFilename,
                    contentType,
                    createdAt,
                    updatedAt
                )
                VALUES (?, ?, ?, ?, ?, ?);
                """,
                bindings: [
                    .text(asset.id.uuidString),
                    .text(asset.storedFilename),
                    .text(asset.originalFilename),
                    .text(asset.contentType),
                    .text(iso8601.string(from: asset.createdAt)),
                    .text(iso8601.string(from: asset.updatedAt))
                ]
            )
        }

        for content in project.contents.values.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            try database.run(
                """
                INSERT INTO CardContents (contentId, createdAt, lastModified)
                VALUES (?, ?, ?);
                """,
                bindings: [
                    .text(content.id.uuidString),
                    .text(iso8601.string(from: content.createdAt)),
                    .text(iso8601.string(from: content.updatedAt))
                ]
            )

            for layer in content.layers.sorted(by: { $0.index < $1.index }) {
                let layerUpdatedAt = iso8601.string(from: layer.updatedAt)
                try database.run(
                    """
                    INSERT INTO Layers (layerId, contentId, layerIndex, createdAt, deleted, lastModified)
                    VALUES (?, ?, ?, ?, ?, ?);
                    """,
                    bindings: [
                        .text(layer.id.uuidString),
                        .text(content.id.uuidString),
                        .int(Int64(layer.index)),
                        .text(iso8601.string(from: layer.createdAt)),
                        .int(0),
                        .text(layerUpdatedAt)
                    ]
                )

                try database.run(
                    """
                    INSERT INTO LayerMarkdown (layerId, markdown, lastModified)
                    VALUES (?, ?, ?);
                    """,
                    bindings: [
                        .text(layer.id.uuidString),
                        .text(layer.markdown),
                        .text(layerUpdatedAt)
                    ]
                )

                if let palette = layer.palette {
                    try database.run(
                        """
                        INSERT INTO LayerPalette (layerId, paletteName, lastModified)
                        VALUES (?, ?, ?);
                        """,
                        bindings: [
                            .text(layer.id.uuidString),
                            .text(palette.rawValue),
                            .text(layerUpdatedAt)
                        ]
                    )
                }

                if let assetID = layer.assetID {
                    try database.run(
                        """
                        INSERT INTO LayerAsset (layerId, assetId, lastModified)
                        VALUES (?, ?, ?);
                        """,
                        bindings: [
                            .text(layer.id.uuidString),
                            .text(assetID.uuidString),
                            .text(layerUpdatedAt)
                        ]
                    )
                }
            }
        }

        for card in project.cards.sorted(by: { $0.slot < $1.slot }) {
            let cardUpdatedAt = iso8601.string(from: card.updatedAt)
            try database.run(
                """
                INSERT INTO Cards (cardId, contentId, x, y, deleted, createdAt, lastModified)
                VALUES (?, ?, ?, ?, ?, ?, ?);
                """,
                bindings: [
                    .text(card.id.uuidString),
                    .text(card.contentID.uuidString),
                    .int(Int64(card.slot.column)),
                    .int(Int64(card.slot.row)),
                    .int(card.deleted ? 1 : 0),
                    .text(iso8601.string(from: card.createdAt)),
                    .text(cardUpdatedAt)
                ]
            )

            try database.run(
                """
                INSERT INTO CardPresentedLayers (cardId, presentedLayerId, lastModified)
                VALUES (?, ?, ?);
                """,
                bindings: [
                    .text(card.id.uuidString),
                    .text(card.presentedLayerID.uuidString),
                    .text(cardUpdatedAt)
                ]
            )

            if let palette = card.palette {
                try database.run(
                    """
                    INSERT INTO CardPalettes (cardId, paletteName, lastModified)
                    VALUES (?, ?, ?);
                    """,
                    bindings: [
                        .text(card.id.uuidString),
                        .text(palette.rawValue),
                        .text(cardUpdatedAt)
                    ]
                )
            }
        }
    }

    private static func loadMetadata(from database: SQLiteDatabase) throws -> BoardContainerMetadata {
        let row = try database.querySingleRow(
            """
            SELECT documentId, createdAt, updatedAt, schemaVersion
            FROM DocumentMeta
            LIMIT 1;
            """
        )

        guard
            let row,
            let rawDocumentID = row.text(at: 0),
            let documentID = UUID(uuidString: rawDocumentID),
            let createdAtString = row.text(at: 1),
            let updatedAtString = row.text(at: 2),
            let createdAt = iso8601.date(from: createdAtString),
            let updatedAt = iso8601.date(from: updatedAtString),
            row.int(at: 3) == Int64(schemaVersion)
        else {
            throw BWRSQLitePackageStoreError.invalidMetadata
        }

        return BoardContainerMetadata(id: documentID, createdAt: createdAt, updatedAt: updatedAt)
    }

    private static func loadContents(from database: SQLiteDatabase) throws -> [UUID: BoardCardContent] {
        let rows = try database.queryRows(
            """
            SELECT
                cc.contentId,
                cc.createdAt,
                cc.lastModified,
                l.layerId,
                l.layerIndex,
                l.createdAt,
                l.lastModified,
                lm.markdown,
                lp.paletteName,
                la.assetId
            FROM CardContents cc
            LEFT JOIN Layers l ON l.contentId = cc.contentId
            LEFT JOIN LayerMarkdown lm ON lm.layerId = l.layerId
            LEFT JOIN LayerPalette lp ON lp.layerId = l.layerId
            LEFT JOIN LayerAsset la ON la.layerId = l.layerId
            WHERE l.deleted IS NULL OR l.deleted = 0
            ORDER BY cc.contentId ASC, l.layerIndex ASC, l.layerId ASC;
            """
        )

        struct PartialContent {
            var createdAt: Date
            var updatedAt: Date
            var layers: [BoardLayer]
        }

        var partials: [UUID: PartialContent] = [:]
        for row in rows {
            guard
                let rawContentID = row.text(at: 0),
                let createdAtString = row.text(at: 1),
                let updatedAtString = row.text(at: 2),
                let createdAt = iso8601.date(from: createdAtString),
                let updatedAt = iso8601.date(from: updatedAtString)
            else {
                throw BWRSQLitePackageStoreError.invalidContentRow("Missing content identifier or timestamps")
            }

            let contentID = storedUUID(from: rawContentID)
            var partial = partials[contentID] ?? PartialContent(
                createdAt: createdAt,
                updatedAt: updatedAt,
                layers: []
            )

            if let rawLayerID = row.text(at: 3) {
                guard
                    let layerCreatedAtString = row.text(at: 5),
                    let layerUpdatedAtString = row.text(at: 6),
                    let layerCreatedAt = iso8601.date(from: layerCreatedAtString),
                    let layerUpdatedAt = iso8601.date(from: layerUpdatedAtString)
                else {
                    throw BWRSQLitePackageStoreError.invalidContentRow("Missing layer timestamps for \(rawContentID)")
                }

                partial.layers.append(
                    BoardLayer(
                        id: storedUUID(from: rawLayerID),
                        index: Int(row.int(at: 4)),
                        createdAt: layerCreatedAt,
                        markdown: row.text(at: 7) ?? "",
                        palette: row.text(at: 8).flatMap(CardPalette.init(rawValue:)),
                        assetID: row.text(at: 9).map { storedUUID(from: $0) },
                        updatedAt: layerUpdatedAt
                    )
                )
            }

            partials[contentID] = partial
        }

        return partials.reduce(into: [:]) { result, entry in
            result[entry.key] = BoardCardContent(
                id: entry.key,
                createdAt: entry.value.createdAt,
                layers: entry.value.layers,
                updatedAt: entry.value.updatedAt
            )
        }
    }

    private static func loadCardInstances(from database: SQLiteDatabase) throws -> [BoardCardInstance] {
        let rows = try database.queryRows(
            """
            SELECT
                c.cardId,
                c.contentId,
                cpl.presentedLayerId,
                c.x,
                c.y,
                c.deleted,
                c.createdAt,
                c.lastModified,
                cp.paletteName
            FROM Cards c
            INNER JOIN CardPresentedLayers cpl ON cpl.cardId = c.cardId
            LEFT JOIN CardPalettes cp ON cp.cardId = c.cardId
            ORDER BY c.y ASC, c.x ASC, c.cardId ASC;
            """
        )

        return try rows.map { row in
            guard
                let rawCardID = row.text(at: 0),
                let rawContentID = row.text(at: 1),
                let rawPresentedLayerID = row.text(at: 2),
                let cardID = UUID(uuidString: rawCardID),
                let createdAtString = row.text(at: 6),
                let updatedAtString = row.text(at: 7),
                let createdAt = iso8601.date(from: createdAtString),
                let updatedAt = iso8601.date(from: updatedAtString)
            else {
                throw BWRSQLitePackageStoreError.invalidCardRow("Missing UUID or timestamp")
            }

            return BoardCardInstance(
                id: cardID,
                contentID: storedUUID(from: rawContentID),
                slot: BoardSlot(row: Int(row.int(at: 4)), column: Int(row.int(at: 3))),
                presentedLayerID: storedUUID(from: rawPresentedLayerID),
                palette: row.text(at: 8).flatMap(CardPalette.init(rawValue:)),
                deleted: row.int(at: 5) != 0,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    private static func loadAssets(
        from database: SQLiteDatabase,
        assetsDirectoryURL: URL
    ) throws -> [UUID: BoardAsset] {
        let rows = try database.queryRows(
            """
            SELECT assetId, storedFilename, originalFilename, contentType, createdAt, updatedAt
            FROM Assets
            ORDER BY assetId ASC;
            """
        )

        return try rows.reduce(into: [:]) { result, row in
            guard
                let rawAssetID = row.text(at: 0),
                let storedFilename = row.text(at: 1),
                let createdAtString = row.text(at: 4),
                let updatedAtString = row.text(at: 5),
                let createdAt = iso8601.date(from: createdAtString),
                let updatedAt = iso8601.date(from: updatedAtString)
            else {
                throw BWRSQLitePackageStoreError.invalidAssetRow("Missing asset metadata")
            }

            let assetID = storedUUID(from: rawAssetID)
            let assetURL = assetsDirectoryURL.appendingPathComponent(storedFilename, isDirectory: false)
            guard FileManager.default.fileExists(atPath: assetURL.path) else {
                throw BWRSQLitePackageStoreError.invalidAssetRow("Missing asset payload for \(storedFilename)")
            }

            result[assetID] = BoardAsset(
                id: assetID,
                storedFilename: storedFilename,
                originalFilename: row.text(at: 2),
                contentType: row.text(at: 3),
                data: try Data(contentsOf: assetURL),
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    private static func storedUUID(from rawValue: String) -> UUID {
        if let uuid = UUID(uuidString: rawValue) {
            return uuid
        }

        let digest = Insecure.SHA1.hash(data: Data(rawValue.utf8))
        let bytes = Array(digest)
        var uuidBytes = Array(bytes.prefix(16))
        uuidBytes[6] = (uuidBytes[6] & 0x0F) | 0x50
        uuidBytes[8] = (uuidBytes[8] & 0x3F) | 0x80

        return uuidBytes.withUnsafeBytes { pointer in
            let tuple = (
                pointer[0], pointer[1], pointer[2], pointer[3],
                pointer[4], pointer[5], pointer[6], pointer[7],
                pointer[8], pointer[9], pointer[10], pointer[11],
                pointer[12], pointer[13], pointer[14], pointer[15]
            )
            return UUID(uuid: tuple)
        }
    }

    private static func siblingTemporaryPackageURL(for url: URL) -> URL {
        let parentURL = url.deletingLastPathComponent()
        let filename = ".\(url.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).tmp"
        return parentURL.appendingPathComponent(filename, isDirectory: true)
    }

    private static func temporaryPackageURL(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    }

    private static let schemaSQL = """
    CREATE TABLE IF NOT EXISTS DocumentMeta (
        documentId TEXT PRIMARY KEY,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        schemaVersion INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS DocumentSettings (
        documentId TEXT PRIMARY KEY,
        canvasTemplate TEXT NOT NULL,
        layoutAlgorithm TEXT NOT NULL,
        layoutMode TEXT NOT NULL,
        insertMode TEXT NOT NULL,
        cardWidth REAL NOT NULL,
        cardHeight REAL NOT NULL,
        spacingX REAL NOT NULL,
        spacingY REAL NOT NULL,
        cardCornerRadius REAL NOT NULL,
        backgroundTone TEXT NOT NULL,
        defaultCardPalette TEXT,
        tabKeySaves INTEGER NOT NULL,
        enterKeySaves INTEGER NOT NULL,
        lastModified TEXT NOT NULL,
        FOREIGN KEY(documentId) REFERENCES DocumentMeta(documentId) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS CardContents (
        contentId TEXT PRIMARY KEY,
        createdAt TEXT NOT NULL,
        lastModified TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS Cards (
        cardId TEXT PRIMARY KEY,
        contentId TEXT NOT NULL UNIQUE,
        x INTEGER NOT NULL,
        y INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        lastModified TEXT NOT NULL,
        FOREIGN KEY(contentId) REFERENCES CardContents(contentId) ON DELETE CASCADE
    );

    CREATE UNIQUE INDEX IF NOT EXISTS Cards_active_slot_unique
    ON Cards (x, y)
    WHERE deleted = 0;

    CREATE TABLE IF NOT EXISTS Layers (
        layerId TEXT PRIMARY KEY,
        contentId TEXT NOT NULL,
        layerIndex INTEGER NOT NULL,
        createdAt TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        lastModified TEXT NOT NULL,
        FOREIGN KEY(contentId) REFERENCES CardContents(contentId) ON DELETE CASCADE
    );

    CREATE UNIQUE INDEX IF NOT EXISTS Layers_content_index_unique
    ON Layers (contentId, layerIndex);

    CREATE TABLE IF NOT EXISTS CardPresentedLayers (
        cardId TEXT PRIMARY KEY,
        presentedLayerId TEXT NOT NULL,
        lastModified TEXT NOT NULL,
        FOREIGN KEY(cardId) REFERENCES Cards(cardId) ON DELETE CASCADE,
        FOREIGN KEY(presentedLayerId) REFERENCES Layers(layerId) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS CardPalettes (
        cardId TEXT PRIMARY KEY,
        paletteName TEXT,
        lastModified TEXT NOT NULL,
        FOREIGN KEY(cardId) REFERENCES Cards(cardId) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS LayerMarkdown (
        layerId TEXT PRIMARY KEY,
        markdown TEXT,
        lastModified TEXT NOT NULL,
        FOREIGN KEY(layerId) REFERENCES Layers(layerId) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS LayerPalette (
        layerId TEXT PRIMARY KEY,
        paletteName TEXT,
        lastModified TEXT NOT NULL,
        FOREIGN KEY(layerId) REFERENCES Layers(layerId) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS Assets (
        assetId TEXT PRIMARY KEY,
        storedFilename TEXT NOT NULL,
        originalFilename TEXT,
        contentType TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS LayerAsset (
        layerId TEXT PRIMARY KEY,
        assetId TEXT,
        lastModified TEXT NOT NULL,
        FOREIGN KEY(layerId) REFERENCES Layers(layerId) ON DELETE CASCADE,
        FOREIGN KEY(assetId) REFERENCES Assets(assetId) ON DELETE SET NULL
    );

    CREATE TRIGGER IF NOT EXISTS CardPresentedLayers_validate_insert
    BEFORE INSERT ON CardPresentedLayers
    FOR EACH ROW
    BEGIN
        SELECT CASE
            WHEN NOT EXISTS (
                SELECT 1
                FROM Cards c
                JOIN Layers l ON l.contentId = c.contentId
                WHERE c.cardId = NEW.cardId
                  AND l.layerId = NEW.presentedLayerId
                  AND l.deleted = 0
            )
            THEN RAISE(ABORT, 'presented layer must belong to the card content')
        END;
    END;

    CREATE TRIGGER IF NOT EXISTS CardPresentedLayers_validate_update
    BEFORE UPDATE OF presentedLayerId ON CardPresentedLayers
    FOR EACH ROW
    BEGIN
        SELECT CASE
            WHEN NOT EXISTS (
                SELECT 1
                FROM Cards c
                JOIN Layers l ON l.contentId = c.contentId
                WHERE c.cardId = NEW.cardId
                  AND l.layerId = NEW.presentedLayerId
                  AND l.deleted = 0
            )
            THEN RAISE(ABORT, 'presented layer must belong to the card content')
        END;
    END;
    """
}

private final class SQLiteDatabase {
    private var handle: OpaquePointer?

    private init(handle: OpaquePointer) {
        self.handle = handle
    }

    static func open(url: URL, readOnly: Bool) throws -> SQLiteDatabase {
        var handle: OpaquePointer?
        let flags = readOnly
            ? SQLITE_OPEN_READONLY
            : SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE
        let result = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown sqlite error"
            if let handle {
                sqlite3_close(handle)
            }
            throw BWRSQLitePackageStoreError.sqlite(message)
        }

        return SQLiteDatabase(handle: handle)
    }

    func close() {
        guard let handle else { return }
        sqlite3_close(handle)
        self.handle = nil
    }

    func exec(_ sql: String) throws {
        guard let handle else {
            throw BWRSQLitePackageStoreError.sqlite("database is closed")
        }

        if sqlite3_exec(handle, sql, nil, nil, nil) != SQLITE_OK {
            throw BWRSQLitePackageStoreError.sqlite(String(cString: sqlite3_errmsg(handle)))
        }
    }

    func beginTransaction() throws {
        try exec("BEGIN IMMEDIATE TRANSACTION;")
    }

    func commitTransaction() throws {
        try exec("COMMIT TRANSACTION;")
    }

    func rollbackTransaction() throws {
        try exec("ROLLBACK TRANSACTION;")
    }

    func run(_ sql: String, bindings: [SQLiteBinding]) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        try bind(bindings, to: statement)

        if sqlite3_step(statement) != SQLITE_DONE {
            guard let handle else {
                throw BWRSQLitePackageStoreError.sqlite("database is closed")
            }
            throw BWRSQLitePackageStoreError.sqlite(String(cString: sqlite3_errmsg(handle)))
        }
    }

    func queryRows(_ sql: String) throws -> [SQLiteRow] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        var rows: [SQLiteRow] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                rows.append(SQLiteRow(statement: statement))
            } else if result == SQLITE_DONE {
                return rows
            } else {
                guard let handle else {
                    throw BWRSQLitePackageStoreError.sqlite("database is closed")
                }
                throw BWRSQLitePackageStoreError.sqlite(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }

    func querySingleRow(_ sql: String) throws -> SQLiteRow? {
        try queryRows(sql).first
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let handle else {
            throw BWRSQLitePackageStoreError.sqlite("database is closed")
        }

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(handle, sql, -1, &statement, nil) != SQLITE_OK || statement == nil {
            throw BWRSQLitePackageStoreError.sqlite(String(cString: sqlite3_errmsg(handle)))
        }
        return statement!
    }

    private func bind(_ bindings: [SQLiteBinding], to statement: OpaquePointer) throws {
        for (index, binding) in bindings.enumerated() {
            let position = Int32(index + 1)
            let result: Int32

            switch binding {
            case .null:
                result = sqlite3_bind_null(statement, position)
            case .text(let value):
                if let value {
                    result = sqlite3_bind_text(statement, position, value, -1, sqliteTransientDestructor)
                } else {
                    result = sqlite3_bind_null(statement, position)
                }
            case .int(let value):
                result = sqlite3_bind_int64(statement, position, value)
            case .double(let value):
                result = sqlite3_bind_double(statement, position, value)
            }

            if result != SQLITE_OK {
                guard let handle else {
                    throw BWRSQLitePackageStoreError.sqlite("database is closed")
                }
                throw BWRSQLitePackageStoreError.sqlite(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }

    private var sqliteTransientDestructor: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }
}

private enum SQLiteBinding {
    case null
    case text(String?)
    case int(Int64)
    case double(Double)
}

private struct SQLiteRow {
    fileprivate let values: [SQLiteValue]

    init(statement: OpaquePointer) {
        let columnCount = sqlite3_column_count(statement)
        var values: [SQLiteValue] = []
        values.reserveCapacity(Int(columnCount))

        for column in 0..<columnCount {
            let type = sqlite3_column_type(statement, column)
            switch type {
            case SQLITE_INTEGER:
                values.append(.int(sqlite3_column_int64(statement, column)))
            case SQLITE_FLOAT:
                values.append(.double(sqlite3_column_double(statement, column)))
            case SQLITE_TEXT:
                if let cString = sqlite3_column_text(statement, column) {
                    values.append(.text(String(cString: cString)))
                } else {
                    values.append(.null)
                }
            default:
                values.append(.null)
            }
        }

        self.values = values
    }

    func text(at index: Int) -> String? {
        guard values.indices.contains(index) else { return nil }
        if case .text(let value) = values[index] {
            return value
        }
        return nil
    }

    func int(at index: Int) -> Int64 {
        guard values.indices.contains(index) else { return 0 }
        switch values[index] {
        case .int(let value):
            return value
        case .double(let value):
            return Int64(value)
        case .text(let value):
            return Int64(value) ?? 0
        case .null:
            return 0
        }
    }
}

private enum SQLiteValue {
    case null
    case text(String)
    case int(Int64)
    case double(Double)
}

private struct BWRISO8601Codec {
    private let formatterWithFractionalSeconds: ISO8601DateFormatter
    private let formatter: ISO8601DateFormatter

    init() {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatterWithFractionalSeconds = fractional

        let regular = ISO8601DateFormatter()
        regular.formatOptions = [.withInternetDateTime]
        formatter = regular
    }

    func string(from date: Date) -> String {
        formatterWithFractionalSeconds.string(from: date)
    }

    func date(from string: String) -> Date? {
        formatterWithFractionalSeconds.date(from: string) ?? formatter.date(from: string)
    }
}
