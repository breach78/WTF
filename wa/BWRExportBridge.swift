import Foundation
import AppKit
import UniformTypeIdentifiers

nonisolated struct BWRExportFeedback: Identifiable, Equatable, Sendable {
    let id = UUID()
    var title: String
    var message: String
}

nonisolated enum BWRExportBridge {
    static func exportText(
        document: BWRDocument,
        groupIDs: [UUID],
        mode: BWRFocusModeKind
    ) -> String {
        let fragments = resolvedGroupIDs(document: document, groupIDs: groupIDs).flatMap { groupID in
            BWRFocusModeProjection.entries(document: document, groupID: groupID, mode: mode)
                .map(\.markdown)
                .filter { !$0.isEmpty }
        }
        return fragments.joined(separator: "\n\n")
    }

    @MainActor
    static func parse(
        text: String,
        format: ScriptExportFormatType
    ) -> [ScriptExportElement] {
        ScriptMarkdownParser(formatType: format).parse(text)
    }

    @MainActor
    static func pdfData(
        text: String,
        format: ScriptExportFormatType,
        userDefaults: UserDefaults = .standard
    ) -> Data {
        let elements = parse(text: text, format: format)
        let generator = ScriptPDFGenerator(format: format, config: loadLayoutConfig(userDefaults: userDefaults))
        return generator.generatePDF(from: elements)
    }

    @MainActor
    static func loadLayoutConfig(userDefaults: UserDefaults = .standard) -> ScriptExportLayoutConfig {
        var config = ScriptExportLayoutConfig()
        config.centeredFontSize = CGFloat(double(forKey: "exportCenteredFontSize", in: userDefaults, fallback: 12.0))
        config.centeredIsCharacterBold = bool(forKey: "exportCenteredCharacterBold", in: userDefaults, fallback: true)
        config.centeredIsSceneHeadingBold = bool(forKey: "exportCenteredSceneHeadingBold", in: userDefaults, fallback: true)
        config.centeredShowRightSceneNumber = bool(forKey: "exportCenteredShowRightSceneNumber", in: userDefaults, fallback: false)
        config.koreanFontSize = CGFloat(double(forKey: "exportKoreanFontSize", in: userDefaults, fallback: 11.0))
        config.koreanIsSceneBold = bool(forKey: "exportKoreanSceneBold", in: userDefaults, fallback: true)
        config.koreanIsCharacterBold = bool(forKey: "exportKoreanCharacterBold", in: userDefaults, fallback: true)
        let alignment = string(forKey: "exportKoreanCharacterAlignment", in: userDefaults, fallback: "right")
        config.koreanCharacterAlignment = alignment == "left" ? .left : .right
        return config
    }

    static func resolvedGroupNames(document: BWRDocument, groupIDs: [UUID]) -> [String] {
        let groupsByID = Dictionary(uniqueKeysWithValues: document.groups.filter { !$0.isArchived }.map { ($0.id, $0) })
        return resolvedGroupIDs(document: document, groupIDs: groupIDs).compactMap { groupsByID[$0]?.name }
    }

    static func baseFileStem(
        documentDisplayName: String,
        groupNames: [String],
        mode: BWRFocusModeKind
    ) -> String {
        let documentStem = sanitizedPathComponent((documentDisplayName as NSString).deletingPathExtension)
        let groupStem: String = {
            if let first = groupNames.first, groupNames.count == 1 {
                return sanitizedPathComponent(first)
            }
            if groupNames.isEmpty {
                return "No_Group"
            }
            return "\(groupNames.count)_Groups"
        }()
        return [documentStem, groupStem, mode.exportFileToken]
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }

    private static func resolvedGroupIDs(document: BWRDocument, groupIDs: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        let uniqueRequested = groupIDs.filter { seen.insert($0).inserted }
        return BWRBoardOrderResolver.orderedGroupIDs(document: document, filteredTo: uniqueRequested)
    }

    private static func sanitizedPathComponent(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = raw.components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Export" : trimmed
    }

    private static func bool(forKey key: String, in defaults: UserDefaults, fallback: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }

    private static func double(forKey key: String, in defaults: UserDefaults, fallback: Double) -> Double {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.double(forKey: key)
    }

    private static func string(forKey key: String, in defaults: UserDefaults, fallback: String) -> String {
        guard let value = defaults.string(forKey: key), !value.isEmpty else { return fallback }
        return value
    }
}

nonisolated private extension BWRFocusModeKind {
    var exportDisplayTitle: String {
        switch self {
        case .currentLayer:
            return "Current Layer"
        case .treatment:
            return "Treatment"
        case .scenario:
            return "Scenario"
        }
    }

    var exportFileToken: String {
        switch self {
        case .currentLayer:
            return "current"
        case .treatment:
            return "treatment"
        case .scenario:
            return "scenario"
        }
    }
}

@MainActor
extension BWRReferenceDocument {
    func exportToClipboard(groupIDs: [UUID], mode: BWRFocusModeKind) -> BWRExportFeedback? {
        let text = BWRExportBridge.exportText(document: document, groupIDs: groupIDs, mode: mode)
        guard !text.isEmpty else {
            return BWRExportFeedback(title: "Export", message: "출력할 내용이 없습니다.")
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return BWRExportFeedback(
            title: "Export",
            message: "\(mode.exportDisplayTitle) 텍스트를 클립보드에 복사했습니다."
        )
    }

    func exportToTextFile(groupIDs: [UUID], mode: BWRFocusModeKind) -> BWRExportFeedback? {
        let text = BWRExportBridge.exportText(document: document, groupIDs: groupIDs, mode: mode)
        guard !text.isEmpty else {
            return BWRExportFeedback(title: "Export", message: "출력할 내용이 없습니다.")
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = exportBaseFileStem(groupIDs: groupIDs, mode: mode) + ".txt"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return BWRExportFeedback(title: "Export", message: "텍스트 파일을 저장했습니다.")
        } catch {
            return BWRExportFeedback(title: "Export", message: "텍스트 파일 저장에 실패했습니다.")
        }
    }

    func exportToPDF(
        groupIDs: [UUID],
        mode: BWRFocusModeKind,
        format: ScriptExportFormatType
    ) -> BWRExportFeedback? {
        let text = BWRExportBridge.exportText(document: document, groupIDs: groupIDs, mode: mode)
        guard !text.isEmpty else {
            return BWRExportFeedback(title: "Export", message: "출력할 내용이 없습니다.")
        }

        let data = BWRExportBridge.pdfData(text: text, format: format)
        guard !data.isEmpty else {
            return BWRExportFeedback(title: "Export", message: "PDF 생성에 실패했습니다.")
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = exportBaseFileStem(groupIDs: groupIDs, mode: mode) + "_" + format.fileToken + ".pdf"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            try data.write(to: url)
            return BWRExportFeedback(title: "Export", message: "PDF를 저장했습니다.")
        } catch {
            return BWRExportFeedback(title: "Export", message: "PDF 저장에 실패했습니다.")
        }
    }

    private func exportBaseFileStem(groupIDs: [UUID], mode: BWRFocusModeKind) -> String {
        BWRExportBridge.baseFileStem(
            documentDisplayName: displayName,
            groupNames: BWRExportBridge.resolvedGroupNames(document: document, groupIDs: groupIDs),
            mode: mode
        )
    }
}

nonisolated private extension ScriptExportFormatType {
    var fileToken: String {
        switch self {
        case .centered:
            return "centered"
        case .korean:
            return "korean"
        }
    }
}
