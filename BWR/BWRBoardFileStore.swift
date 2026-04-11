import Foundation

enum BWRBoardFileStore {
    private static let boardsDirectoryName = "Boards"

    static func createNewBoard(document: BWRDocument = BWRDocument()) throws -> URL {
        let directoryURL = try boardsDirectoryURL()
        let fileURL = uniqueBoardURL(in: directoryURL)
        try document.writePackage(to: fileURL)
        return fileURL
    }

    private static func boardsDirectoryURL() throws -> URL {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        let directoryURL = documentsURL.appendingPathComponent(boardsDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private static func uniqueBoardURL(in directoryURL: URL) -> URL {
        let stem = defaultBoardStem()
        let candidateURL = directoryURL.appendingPathComponent(stem).appendingPathExtension("bwr")

        guard !FileManager.default.fileExists(atPath: candidateURL.path()) else {
            return nextAvailableBoardURL(stem: stem, in: directoryURL)
        }

        return candidateURL
    }

    private static func nextAvailableBoardURL(stem: String, in directoryURL: URL) -> URL {
        for suffix in 2...999 {
            let candidateURL = directoryURL
                .appendingPathComponent("\(stem) \(suffix)")
                .appendingPathExtension("bwr")

            if !FileManager.default.fileExists(atPath: candidateURL.path()) {
                return candidateURL
            }
        }

        return directoryURL
            .appendingPathComponent("\(stem) \(UUID().uuidString.prefix(4))")
            .appendingPathExtension("bwr")
    }

    private static func defaultBoardStem() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "'Board' yyyy-MM-dd HH-mm"
        return formatter.string(from: .now)
    }
}
