import SwiftUI
import AppKit

struct FountainClipboardImport {
    let coverCardContent: String?
    let sceneCards: [String]

    var cardContents: [String] {
        var result: [String] = []
        if let coverCardContent,
           !coverCardContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(coverCardContent)
        }
        result.append(contentsOf: sceneCards)
        return result
    }
}

struct FountainClipboardPastePreview {
    let rawText: String
    let importPayload: FountainClipboardImport
}

enum StructuredTextPasteOption: Equatable {
    case plainText
    case sceneCards
}

func parseFountainClipboardImport(from rawText: String) -> FountainClipboardImport? {
    let normalized = normalizedClipboardText(rawText)
    let lines = normalized.components(separatedBy: "\n")
    guard let firstSceneIndex = lines.firstIndex(where: isFountainSceneHeadingLine) else { return nil }

    let sceneCards = buildFountainSceneCards(from: lines, startingAt: firstSceneIndex)
    guard sceneCards.count >= 2 else { return nil }

    let titlePageFields = parseFountainTitlePageFields(from: Array(lines[..<firstSceneIndex]))
    let coverCardContent = buildFountainCoverCardContent(from: titlePageFields)

    return FountainClipboardImport(
        coverCardContent: coverCardContent,
        sceneCards: sceneCards
    )
}

func normalizedClipboardText(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
}

func isFountainSceneHeadingLine(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }

    if trimmed.hasPrefix(".") {
        let remainder = trimmed.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        return !remainder.isEmpty
    }

    let uppercased = trimmed.uppercased()
    return uppercased.hasPrefix("INT.")
        || uppercased.hasPrefix("EXT.")
        || uppercased.hasPrefix("INT/EXT.")
        || uppercased.hasPrefix("I/E.")
}

func buildFountainSceneCards(from lines: [String], startingAt firstSceneIndex: Int) -> [String] {
    var cards: [String] = []
    var currentLines: [String] = []

    for line in lines[firstSceneIndex...] {
        if isFountainSceneHeadingLine(line),
           !currentLines.isEmpty {
            let card = currentLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !card.isEmpty {
                cards.append(card)
            }
            currentLines = []
        }
        currentLines.append(line)
    }

    let trailingCard = currentLines
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if !trailingCard.isEmpty {
        cards.append(trailingCard)
    }

    return cards
}

func parseFountainTitlePageFields(from lines: [String]) -> [String: [String]] {
    var fields: [String: [String]] = [:]
    var currentKey: String? = nil

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            currentKey = nil
            continue
        }

        if let field = parseFountainTitlePageField(trimmed) {
            let normalizedKey = normalizedFountainTitlePageFieldKey(field.key)
            currentKey = normalizedKey
            if !field.value.isEmpty {
                fields[normalizedKey, default: []].append(field.value)
            } else if fields[normalizedKey] == nil {
                fields[normalizedKey] = []
            }
            continue
        }

        guard line.hasPrefix("\t") || line.hasPrefix(" ") else {
            currentKey = nil
            continue
        }

        guard let currentKey else { continue }
        fields[currentKey, default: []].append(trimmed)
    }

    return fields
}

func parseFountainTitlePageField(_ line: String) -> (key: String, value: String)? {
    guard let separatorIndex = line.firstIndex(of: ":") else { return nil }
    let key = line[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { return nil }
    let valueStart = line.index(after: separatorIndex)
    let value = line[valueStart...].trimmingCharacters(in: .whitespacesAndNewlines)
    return (key: key, value: value)
}

func normalizedFountainTitlePageFieldKey(_ key: String) -> String {
    key
        .lowercased()
        .filter { $0.isLetter || $0.isNumber }
}

func buildFountainCoverCardContent(from fields: [String: [String]]) -> String? {
    let titleValues = fields["title"] ?? []
    let title = titleValues.first?.trimmingCharacters(in: .whitespacesAndNewlines)
    let revision = joinedFountainFieldValues(Array(titleValues.dropFirst()), separator: " / ")
    let date = joinedFountainFieldValues(fields["draftdate"], separator: " / ")
    let author = joinedFountainFieldValues(fields["author"], separator: " / ")
    let company = joinedFountainFieldValues(
        fields["company"]
        ?? fields["productioncompany"]
        ?? fields["production"],
        separator: " / "
    )

    let contact = joinedFountainFieldValues(
        resolvedFountainContactValues(from: fields),
        separator: ", "
    )

    var lines: [String] = []
    if let title, !title.isEmpty {
        lines.append("# \(title)")
    }
    if let revision, !revision.isEmpty {
        lines.append("## \(revision)")
    }
    if let date, !date.isEmpty {
        lines.append("### \(date)")
    }
    if let author, !author.isEmpty {
        lines.append("#### \(author)")
    }
    if let company, !company.isEmpty {
        lines.append("##### \(company)")
    }
    if let contact, !contact.isEmpty {
        lines.append("###### \(contact)")
    }

    let result = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty ? nil : result
}

func resolvedFountainContactValues(from fields: [String: [String]]) -> [String]? {
    if let direct = fields["contact"], !direct.isEmpty {
        return direct
    }

    var values: [String] = []
    if let email = fields["email"]?.first,
       !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        values.append(email)
    }
    if let phone = fields["phone"]?.first,
       !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        values.append(phone)
    }
    return values.isEmpty ? nil : values
}

func joinedFountainFieldValues(_ values: [String]?, separator: String) -> String? {
    guard let values else { return nil }
    let normalized = values
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard !normalized.isEmpty else { return nil }
    return normalized.joined(separator: separator)
}

func sharedLineHasSignificantContentBeforeBreak(in text: NSString, breakIndex: Int) -> Bool {
    guard breakIndex > 0 else { return false }
    var i = breakIndex - 1
    while i >= 0 {
        let unit = text.character(at: i)
        if unit == 10 || unit == 13 {
            return false
        }
        if let scalar = UnicodeScalar(unit), CharacterSet.whitespacesAndNewlines.contains(scalar) {
            if i == 0 { break }
            i -= 1
            continue
        }
        return true
    }
    return false
}

func sharedHasSentenceEndingPeriodBoundarySimple(in text: NSString, delta: TextChangeDelta) -> Bool {
    guard delta.newChangedLength > 0 else { return false }
    let start = delta.prefix
    let end = delta.prefix + delta.newChangedLength
    if start < 0 || end > text.length || start >= end { return false }

    var i = start
    while i < end {
        let unit = text.character(at: i)
        if unit == 46 || unit == 12290 {
            let nextIndex = i + 1
            if nextIndex >= text.length {
                return true
            }
            let nextUnit = text.character(at: nextIndex)
            if let scalar = UnicodeScalar(nextUnit), CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return true
            }
        }
        i += 1
    }
    return false
}

func sharedHasSentenceEndingPeriodBoundaryExtended(in text: NSString, delta: TextChangeDelta) -> Bool {
    guard delta.newChangedLength > 0 else { return false }
    let start = delta.prefix
    let end = delta.prefix + delta.newChangedLength
    if start < 0 || end > text.length || start >= end { return false }

    var i = start
    while i < end {
        let unit = text.character(at: i)
        if unit == 46 || unit == 12290 {
            if sharedIsSentenceEndingPeriod(at: i, in: text) {
                return true
            }
        }
        i += 1
    }
    return false
}

func sharedIsSentenceEndingPeriod(at index: Int, in text: NSString) -> Bool {
    if sharedIsDigitAtUTF16Index(text, index: index - 1) && sharedIsDigitAtUTF16Index(text, index: index + 1) {
        return false
    }

    var i = index + 1
    while i < text.length {
        let unit = text.character(at: i)
        if unit == 10 || unit == 13 {
            return true
        }
        if sharedIsWhitespaceUnit(unit) || sharedIsClosingPunctuationUnit(unit) {
            i += 1
            continue
        }
        return false
    }
    return true
}

func sharedIsWhitespaceUnit(_ unit: unichar) -> Bool {
    guard let scalar = UnicodeScalar(unit) else { return false }
    return CharacterSet.whitespacesAndNewlines.contains(scalar)
}

func sharedIsDigitAtUTF16Index(_ text: NSString, index: Int) -> Bool {
    guard index >= 0, index < text.length else { return false }
    let unit = text.character(at: index)
    guard let scalar = UnicodeScalar(unit) else { return false }
    return CharacterSet.decimalDigits.contains(scalar)
}

func sharedIsClosingPunctuationUnit(_ unit: unichar) -> Bool {
    switch unit {
    case 41, 93, 125, 34, 39:
        return true
    case 12289, 12290, 12291, 12299, 12301, 12303, 12305:
        return true
    case 8217, 8221:
        return true
    default:
        return false
    }
}

func sharedClampTextValue(_ text: String, maxLength: Int, preserveLineBreak: Bool = false) -> String {
    var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !preserveLineBreak {
        normalized = normalized.replacingOccurrences(of: "\n", with: " / ")
    }
    normalized = normalized.replacingOccurrences(of: "\t", with: " ")
    if normalized.isEmpty { return "(비어 있음)" }
    if normalized.count <= maxLength { return normalized }
    let index = normalized.index(normalized.startIndex, offsetBy: maxLength)
    return String(normalized[..<index]) + "..."
}

func sharedSearchTokensValue(from text: String) -> [String] {
    let allowed = text.lowercased().unicodeScalars.map { scalar -> Character in
        if CharacterSet.alphanumerics.contains(scalar) || (scalar.value >= 0xAC00 && scalar.value <= 0xD7A3) {
            return Character(scalar)
        }
        return " "
    }
    let normalized = String(allowed)
    let words = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    var tokens: [String] = []
    tokens.reserveCapacity(words.count * 2)
    for word in words {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { continue }
        tokens.append(trimmed)
        if trimmed.unicodeScalars.contains(where: { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }) {
            let chars = Array(trimmed)
            if chars.count >= 2 {
                for index in 0..<(chars.count - 1) {
                    tokens.append(String(chars[index...index + 1]))
                }
            }
        }
    }
    return tokens
}


enum DiffStatus {
    case added, deleted, modified, none
}

struct SnapshotDiff: Identifiable {
    let id: UUID // cardID
    let snapshot: CardSnapshot
    let status: DiffStatus
}

// MARK: - 드롭 위치 식별을 위한 타입

enum DropTarget: Equatable {
    case before(UUID)
    case after(UUID)
    case onto(UUID)
    case columnTop(UUID?) // 부모 ID
    case columnBottom(UUID?) // 부모 ID
}

let waCardTreePasteboardType = NSPasteboard.PasteboardType("com.riwoong.wa.cardTree")
let waCloneCardPasteboardType = NSPasteboard.PasteboardType("com.riwoong.wa.cloneCard")

struct CardTreeClipboardNode: Codable {
    let content: String
    let colorHex: String?
    let isAICandidate: Bool
    let children: [CardTreeClipboardNode]
}

struct CardTreeClipboardPayload: Codable {
    let roots: [CardTreeClipboardNode]
}

struct CloneCardClipboardItem: Codable {
    let sourceCardID: UUID
    let cloneGroupID: UUID?
    let content: String
    let colorHex: String?
    let isAICandidate: Bool
}

struct CloneCardClipboardPayload: Codable {
    let sourceScenarioID: UUID
    let items: [CloneCardClipboardItem]
}

enum ClonePastePlacement {
    case child
    case sibling
}

struct ClonePeerMenuDestination: Identifiable {
    let id: UUID
    let title: String
}

// MARK: - AI 카드 생성 타입

