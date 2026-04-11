import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let bwrBoard = UTType(exportedAs: "com.riwoong.bwr.board", conformingTo: .package)
}

struct BWRDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.bwrBoard] }

    var metadata: BoardContainerMetadata
    var project: BoardProject

    init(
        metadata: BoardContainerMetadata = .init(),
        project: BoardProject = .sample
    ) {
        self.metadata = metadata
        self.project = project
    }

    init(configuration: ReadConfiguration) throws {
        self = try BWRSQLitePackageStore.read(from: configuration.file)
    }

    static func open(from url: URL) throws -> BWRDocument {
        try BWRSQLitePackageStore.read(from: url)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try BWRSQLitePackageStore.fileWrapper(
            document: self,
            preferredFileName: configuration.existingFile?.preferredFilename ?? "Untitled.bwr"
        )
    }

    func writePackage(to url: URL) throws {
        try BWRSQLitePackageStore.fullWrite(document: self, to: url)
    }
}
