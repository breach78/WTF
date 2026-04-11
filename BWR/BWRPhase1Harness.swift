import Foundation
import SQLite3

enum BWRPhase1Harness {
    @discardableResult
    static func runAll() -> Bool {
        let results = [
            packageStructureCheck(),
            sqliteRoundTripCheck(),
            schemaGuardCheck()
        ]

        for result in results {
            let marker = result.success ? "PASS" : "FAIL"
            print("[BWR Phase 1] \(marker) \(result.title) - \(result.detail)")
        }

        return results.allSatisfy(\.success)
    }

    private static func packageStructureCheck() -> Phase1HarnessResult {
        let url = BWRHarnessFixtures.temporaryPackageURL(prefix: "bwr-phase1-structure")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            try BWRDocument(project: BWRHarnessFixtures.singleLayerProject()).writePackage(to: url)
            let databaseURL = url.appendingPathComponent(BWRSQLitePackageStore.databaseFilename)
            let assetsURL = url.appendingPathComponent(BWRSQLitePackageStore.assetsDirectoryName, isDirectory: true)
            let thumbnailURL = url.appendingPathComponent(BWRSQLitePackageStore.thumbnailFilename)
            var isDirectory: ObjCBool = false

            let success =
                FileManager.default.fileExists(atPath: databaseURL.path) &&
                FileManager.default.fileExists(atPath: assetsURL.path, isDirectory: &isDirectory) &&
                isDirectory.boolValue &&
                FileManager.default.fileExists(atPath: thumbnailURL.path)

            return Phase1HarnessResult(
                title: "Package Structure",
                success: success,
                detail: success ? ".bwr package writes SQLite, assets/, thumbnail.jpg only" : "missing package members"
            )
        } catch {
            return Phase1HarnessResult(title: "Package Structure", success: false, detail: error.localizedDescription)
        }
    }

    private static func sqliteRoundTripCheck() -> Phase1HarnessResult {
        let url = BWRHarnessFixtures.temporaryPackageURL(prefix: "bwr-phase1-roundtrip")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let original = BWRDocument(
                metadata: BoardContainerMetadata(
                    id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                    createdAt: Date(timeIntervalSince1970: 1_710_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_710_000_000)
                ),
                project: BWRHarnessFixtures.singleLayerProject()
            )

            try original.writePackage(to: url)
            let restored = try BWRDocument.open(from: url)
            let success = original.project == restored.project &&
                original.metadata.id == restored.metadata.id &&
                original.metadata.createdAt == restored.metadata.createdAt

            return Phase1HarnessResult(
                title: "SQLite Round Trip",
                success: success,
                detail: success ? "cards and metadata survive reopen from SQLite" : "round-trip content mismatch"
            )
        } catch {
            return Phase1HarnessResult(title: "SQLite Round Trip", success: false, detail: error.localizedDescription)
        }
    }

    private static func schemaGuardCheck() -> Phase1HarnessResult {
        let url = BWRHarnessFixtures.temporaryPackageURL(prefix: "bwr-phase1-schema")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let project = BWRHarnessFixtures.singleLayerProject()
            try BWRDocument(project: project).writePackage(to: url)
            let databaseURL = url.appendingPathComponent(BWRSQLitePackageStore.databaseFilename)

            var handle: OpaquePointer?
            guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let handle else {
                let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
                if let handle { sqlite3_close(handle) }
                return Phase1HarnessResult(title: "Schema Guards", success: false, detail: message)
            }
            defer { sqlite3_close(handle) }

            _ = sqlite3_exec(handle, "PRAGMA foreign_keys = ON;", nil, nil, nil)

            let journalMode = pragmaValue(for: "journal_mode", in: handle)?.lowercased()
            let foreignKeys = pragmaValue(for: "foreign_keys", in: handle)
            let invalidUpdate = """
            UPDATE CardPresentedLayers
            SET presentedLayerId = 'DEAD-BEEF-DEAD-BEEF-DEAD-BEEF-DEAD-BEEF'
            WHERE cardId = '\(project.cards[0].id.uuidString)';
            """

            let triggerRejected = sqlite3_exec(handle, invalidUpdate, nil, nil, nil) != SQLITE_OK
            let success = journalMode == "delete" && foreignKeys == "1" && triggerRejected

            return Phase1HarnessResult(
                title: "Schema Guards",
                success: success,
                detail: success ? "foreign keys, DELETE journal mode, and presented-layer validation are active" : "pragma or trigger validation failed"
            )
        } catch {
            return Phase1HarnessResult(title: "Schema Guards", success: false, detail: error.localizedDescription)
        }
    }

    private static func pragmaValue(for name: String, in handle: OpaquePointer) -> String? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(handle, "PRAGMA \(name);", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        if let text = sqlite3_column_text(statement, 0) {
            return String(cString: text)
        }

        return String(sqlite3_column_int64(statement, 0))
    }
}

private struct Phase1HarnessResult {
    let title: String
    let success: Bool
    let detail: String
}
