import Foundation

extension FileStore {
    private func aiThreadsURL(for scenarioID: UUID) -> URL {
        let folderName = ensureScenarioFolder(for: scenarioID)
        let scenarioFolder = folderURL.appendingPathComponent(folderName)
        return scenarioFolder.appendingPathComponent(aiThreadsFile)
    }

    private func aiEmbeddingIndexURL(for scenarioID: UUID) -> URL {
        let folderName = ensureScenarioFolder(for: scenarioID)
        let scenarioFolder = folderURL.appendingPathComponent(folderName)
        return scenarioFolder.appendingPathComponent(aiEmbeddingIndexFile)
    }

    func aiVectorIndexURL(for scenarioID: UUID) -> URL {
        let folderName = ensureScenarioFolder(for: scenarioID)
        let scenarioFolder = folderURL.appendingPathComponent(folderName)
        return scenarioFolder.appendingPathComponent(aiVectorIndexFile)
    }

    func loadAIChatThreadsData(for scenarioID: UUID) async -> Data? {
        let url = aiThreadsURL(for: scenarioID)
        return await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try? Data(contentsOf: url)
        }.value
    }

    func saveAIChatThreadsData(_ data: Data?, for scenarioID: UUID) {
        let url = aiThreadsURL(for: scenarioID)
        let folder = url.deletingLastPathComponent()
        saveQueue.async { [weak self] in
            guard let self else { return }
            if let data {
                if self.lastSavedAIThreadsData[scenarioID] == data {
                    return
                }
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                do {
                    try data.write(to: url, options: .atomic)
                    self.lastSavedAIThreadsData[scenarioID] = data
                } catch { }
            } else {
                if FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                }
                self.lastSavedAIThreadsData.removeValue(forKey: scenarioID)
            }
        }
    }

    func loadAIEmbeddingIndexData(for scenarioID: UUID) async -> Data? {
        let url = aiEmbeddingIndexURL(for: scenarioID)
        return await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try? Data(contentsOf: url)
        }.value
    }

    func saveAIEmbeddingIndexData(_ data: Data?, for scenarioID: UUID) {
        let url = aiEmbeddingIndexURL(for: scenarioID)
        let folder = url.deletingLastPathComponent()
        saveQueue.async { [weak self] in
            guard let self else { return }
            if let data {
                if self.lastSavedAIEmbeddingIndexData[scenarioID] == data {
                    return
                }
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                do {
                    try data.write(to: url, options: .atomic)
                    self.lastSavedAIEmbeddingIndexData[scenarioID] = data
                } catch { }
            } else {
                if FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                }
                self.lastSavedAIEmbeddingIndexData.removeValue(forKey: scenarioID)
            }
        }
    }

    @MainActor
    func replaceIndexBoardSummaryRecords(
        _ records: [UUID: IndexBoardCardSummaryRecord],
        for scenarioID: UUID
    ) {
        indexBoardSummaryRecordsByScenarioID[scenarioID] = records
    }
}
