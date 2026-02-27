import Foundation
import AppKit
import PDFKit
import CoreText

enum ScriptExportFormatType {
    case centered
    case korean
}

enum ScriptExportElementType {
    case sceneHeading
    case action
    case character
    case dialogue
    case parenthetical
    case transition
    case centered

    case title
    case revision
    case date
    case author
    case company
    case contact

    case coverTitle
    case coverVersion
    case coverDate
    case coverAuthor
    case coverProduction
    case coverContact
}

struct ScriptExportElement {
    var type: ScriptExportElementType
    var text: String
}

final class ScriptMarkdownParser {
    let formatType: ScriptExportFormatType

    init(formatType: ScriptExportFormatType) {
        self.formatType = formatType
    }

    func parse(_ text: String) -> [ScriptExportElement] {
        var elements: [ScriptExportElement] = []
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix("######") {
                let content = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                let type: ScriptExportElementType = formatType == .centered ? .contact : .coverContact
                if formatType == .korean || !content.isEmpty {
                    elements.append(ScriptExportElement(type: type, text: content))
                }
                continue
            }
            if trimmed.hasPrefix("#####") {
                let content = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                let type: ScriptExportElementType = formatType == .centered ? .company : .coverProduction
                if formatType == .korean || !content.isEmpty {
                    elements.append(ScriptExportElement(type: type, text: content))
                }
                continue
            }
            if trimmed.hasPrefix("####") {
                let content = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                let type: ScriptExportElementType = formatType == .centered ? .author : .coverAuthor
                if formatType == .korean || !content.isEmpty {
                    elements.append(ScriptExportElement(type: type, text: content))
                }
                continue
            }
            if trimmed.hasPrefix("###") {
                let content = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let type: ScriptExportElementType = formatType == .centered ? .date : .coverDate
                if formatType == .korean || !content.isEmpty {
                    elements.append(ScriptExportElement(type: type, text: content))
                }
                continue
            }
            if trimmed.hasPrefix("##") {
                let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                let type: ScriptExportElementType = formatType == .centered ? .revision : .coverVersion
                if formatType == .korean || !content.isEmpty {
                    elements.append(ScriptExportElement(type: type, text: content))
                }
                continue
            }
            if trimmed.hasPrefix("#") {
                let content = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                let type: ScriptExportElementType = formatType == .centered ? .title : .coverTitle
                if formatType == .korean || !content.isEmpty {
                    elements.append(ScriptExportElement(type: type, text: content))
                }
                continue
            }

            if trimmed.hasPrefix(">") && trimmed.hasSuffix("<") {
                var cleanText = trimmed
                cleanText.removeFirst()
                cleanText.removeLast()
                cleanText = cleanText.replacingOccurrences(of: "**", with: "")
                elements.append(ScriptExportElement(type: .centered, text: cleanText))
                continue
            }

            if trimmed.hasPrefix(".") {
                let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !content.isEmpty {
                    elements.append(ScriptExportElement(type: .sceneHeading, text: content))
                }
                continue
            }

            if trimmed.uppercased().hasPrefix("EXT.") || trimmed.uppercased().hasPrefix("INT.") {
                elements.append(ScriptExportElement(type: .sceneHeading, text: trimmed))
                continue
            }

            if trimmed.hasPrefix("@") {
                let characterName = String(trimmed.dropFirst())
                elements.append(ScriptExportElement(type: .character, text: characterName))
                continue
            }

            if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") {
                elements.append(ScriptExportElement(type: .parenthetical, text: trimmed))
                continue
            }

            if trimmed.hasSuffix(":") {
                elements.append(ScriptExportElement(type: .transition, text: trimmed))
                continue
            }

            if let lastElement = elements.last,
               lastElement.type == .character || lastElement.type == .parenthetical {
                elements.append(ScriptExportElement(type: .dialogue, text: trimmed))
                continue
            }

            elements.append(ScriptExportElement(type: .action, text: trimmed))
        }

        return elements
    }
}

enum ScriptExportCharacterAlignment {
    case right
    case left
}

struct ScriptExportLayoutConfig {
    var centeredFontSize: CGFloat = 12.0
    var centeredIsCharacterBold: Bool = true
    var centeredIsSceneHeadingBold: Bool = true
    var centeredShowRightSceneNumber: Bool = false

    var koreanFontSize: CGFloat = 11.0
    var koreanIsSceneBold: Bool = true
    var koreanIsCharacterBold: Bool = true
    var koreanCharacterAlignment: ScriptExportCharacterAlignment = .right

    struct CenteredLayout {
        static let marginTop: CGFloat = 72.0
        static let marginBottom: CGFloat = 72.0
        static let marginLeft: CGFloat = 108.0
        static let marginRight: CGFloat = 54.0

        static let sceneLeft: CGFloat = 108.0
        static let sceneRight: CGFloat = 54.0

        static let actionLeft: CGFloat = 108.0
        static let actionRight: CGFloat = 54.0

        static let characterLeft: CGFloat = 252.0
        static let characterRight: CGFloat = 73.0

        static let dialogueLeft: CGFloat = 180.0
        static let dialogueRight: CGFloat = 163.0

        static let parentheticalLeft: CGFloat = 209.0
        static let parentheticalRight: CGFloat = 199.0

        static let transitionLeft: CGFloat = 396.0
        static let transitionRight: CGFloat = 84.0

        static let centeredLeft: CGFloat = 79.65
        static let centeredRight: CGFloat = 82.35

        static let lineSpacing: CGFloat = 0.0

        static let pageNumberTop: CGFloat = 36.0
        static let pageNumberRight: CGFloat = 54.0
    }

    struct KoreanLayout {
        static let marginTop: CGFloat = 99.2
        static let marginBottom: CGFloat = 85.0
        static let marginLeft: CGFloat = 85.0
        static let marginRight: CGFloat = 85.0

        static let sceneLeft: CGFloat = 85.0
        static let sceneRight: CGFloat = 85.0

        static let actionLeft: CGFloat = 85.0
        static let actionRight: CGFloat = 85.0

        static let characterLeftAligned: CGFloat = 105.0

        static let dialogueLeft: CGFloat = 85.0
        static let dialogueRight: CGFloat = 113.35
        static let dialogueIndent: CGFloat = 168.8

        static let transitionLeft: CGFloat = 300.0
        static let transitionRight: CGFloat = 85.0

        static let centeredLeft: CGFloat = 85.0
        static let centeredRight: CGFloat = 85.0

        static let paragraphSpacing: CGFloat = 13.0
        static let lineSpacing: CGFloat = 1.0

        static let pageNumberTop: CGFloat = 74.0
        static let pageNumberRight: CGFloat = 75.0
    }

    var centeredParagraphSpacing: CGFloat {
        let baseSpacing: CGFloat = 18.5
        let ratio = centeredFontSize / 12.0
        return baseSpacing * pow(ratio, 6.0)
    }
}

final class ScriptPDFGenerator {
    let config: ScriptExportLayoutConfig
    let format: ScriptExportFormatType

    init(format: ScriptExportFormatType, config: ScriptExportLayoutConfig = ScriptExportLayoutConfig()) {
        self.format = format
        self.config = config
    }

    func generatePDF(from elements: [ScriptExportElement]) -> Data {
        switch format {
        case .centered:
            return ScriptCenteredPDFGenerator(config: config).generate(from: elements)
        case .korean:
            return ScriptKoreanPDFGenerator(config: config).generate(from: elements)
        }
    }
}

final class ScriptCenteredPDFGenerator {
    let config: ScriptExportLayoutConfig
    let pageWidth: CGFloat = 595.2
    let pageHeight: CGFloat = 841.8

    let regularFontName = "SansMonoCJKFinalDraft"
    let boldFontName = "SansMonoCJKFinalDraft-Bold"

    var sceneCounter = 0
    var cursorY: CGFloat = 0
    var pageNumber = 1

    private var context: CGContext?
    private var isFirstPage = true

    init(config: ScriptExportLayoutConfig) {
        self.config = config
        self.cursorY = ScriptExportLayoutConfig.CenteredLayout.marginTop
    }

    func generate(from elements: [ScriptExportElement]) -> Data {
        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        self.context = ctx

        let titleElements = elements.filter { element in
            switch element.type {
            case .title, .revision, .date, .author, .company, .contact: return true
            default: return false
            }
        }
        let scriptElements = elements.filter { element in
            switch element.type {
            case .title, .revision, .date, .author, .company, .contact: return false
            default: return true
            }
        }

        if !titleElements.isEmpty {
            drawTitlePage(elements: titleElements)
        }

        sceneCounter = 0
        cursorY = ScriptExportLayoutConfig.CenteredLayout.marginTop
        pageNumber = 1
        isFirstPage = true

        beginNewPage()

        for (index, element) in scriptElements.enumerated() {
            processElement(element, index: index, allElements: scriptElements)
        }

        ctx.endPDFPage()
        ctx.closePDF()
        return pdfData as Data
    }

    private func drawTitlePage(elements: [ScriptExportElement]) {
        guard let ctx = context else { return }
        ctx.beginPDFPage(nil)

        var titleText = ""
        var companyText = ""

        let centerStyle = NSMutableParagraphStyle()
        centerStyle.alignment = .center

        var topCursor = pageHeight * 0.35
        var bottomCursor = pageHeight * 0.65

        let coverFontSize: CGFloat = config.centeredFontSize
        let coverFont = NSFont(name: regularFontName, size: coverFontSize) ?? NSFont.systemFont(ofSize: coverFontSize)

        for element in elements {
            if element.type == .title { titleText = element.text }
            if element.type == .company { companyText = element.text }

            let isTopGroup: Bool
            switch element.type {
            case .title, .revision, .date:
                isTopGroup = true
            case .author, .company, .contact:
                isTopGroup = false
            default:
                isTopGroup = true
            }

            let attrStr = NSAttributedString(string: element.text, attributes: [
                .font: coverFont,
                .paragraphStyle: centerStyle,
                .foregroundColor: NSColor.black
            ])

            let width = pageWidth - 108.0
            let height = calculateHeight(of: attrStr, width: width)

            let drawY: CGFloat
            if isTopGroup {
                drawY = pageHeight - topCursor - height
                topCursor += height + 15.0
            } else {
                drawY = pageHeight - bottomCursor - height
                bottomCursor += height + 10.0
            }

            let rect = CGRect(x: 54.0, y: drawY, width: width, height: height)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            attrStr.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
        }

        let disclaimerFontSize: CGFloat = 7.0
        let disclaimerFont = NSFont(name: regularFontName, size: disclaimerFontSize) ?? NSFont.systemFont(ofSize: disclaimerFontSize)

        let displayTitle = titleText.isEmpty ? "제목미정" : titleText
        let displayCompany = companyText.isEmpty ? "작가/제작사" : companyText

        let disclaimerText = """
        본 시나리오 '\(displayTitle)'은 \(displayCompany)의 자산이며, 복제, 재생산, 배포 및 공개는 그 전부 또는 일부를 불문하고 엄격히 금지됩니다. This screenplay, titled \(displayTitle), is the exclusive property of \(displayCompany). Any unauthorized duplication, reproduction, distribution, or disclosure of this material, in whole or in part, is strictly prohibited.
        """

        let disclaimerAttr = NSAttributedString(string: disclaimerText, attributes: [
            .font: disclaimerFont,
            .paragraphStyle: centerStyle,
            .foregroundColor: NSColor.black
        ])

        let disclaimerHeight = calculateHeight(of: disclaimerAttr, width: pageWidth - 108.0)
        let disclaimerRect = CGRect(x: 54.0, y: ScriptExportLayoutConfig.CenteredLayout.marginBottom, width: pageWidth - 108.0, height: disclaimerHeight)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        disclaimerAttr.draw(in: disclaimerRect)
        NSGraphicsContext.restoreGraphicsState()

        ctx.endPDFPage()
    }

    private func beginNewPage() {
        if !isFirstPage {
            context?.endPDFPage()
        }
        context?.beginPDFPage(nil)

        if !isFirstPage {
            pageNumber += 1
            drawPageNumber(pageNumber)
        }

        cursorY = ScriptExportLayoutConfig.CenteredLayout.marginTop
        isFirstPage = false
    }

    private func processElement(_ element: ScriptExportElement, index: Int, allElements: [ScriptExportElement]) {
        var currentSceneNumber: Int? = nil
        if element.type == .sceneHeading {
            sceneCounter += 1
            currentSceneNumber = sceneCounter
        }

        let attributedString = createAttributedString(for: element)
        let width = contentWidth(for: element.type)
        let xPos = xPosition(for: element.type)

        let isTop = abs(cursorY - ScriptExportLayoutConfig.CenteredLayout.marginTop) < 1.0
        let spacing = isTop ? 0.0 : config.centeredParagraphSpacing
        let actualSpacing: CGFloat = (element.type == .dialogue || element.type == .parenthetical) ? 0.0 : spacing

        if element.type == .character {
            var blockHeight = calculateHeight(of: attributedString, width: width)
            var nextIndex = index + 1
            while nextIndex < allElements.count {
                let nextElem = allElements[nextIndex]
                if nextElem.type == .dialogue || nextElem.type == .parenthetical {
                    let nextStr = createAttributedString(for: nextElem)
                    blockHeight += calculateHeight(of: nextStr, width: contentWidth(for: nextElem.type))
                    nextIndex += 1
                } else {
                    break
                }
            }

            let availableHeight = pageHeight - ScriptExportLayoutConfig.CenteredLayout.marginBottom - cursorY
            let maxPageContentHeight = pageHeight - ScriptExportLayoutConfig.CenteredLayout.marginTop - ScriptExportLayoutConfig.CenteredLayout.marginBottom

            if blockHeight <= maxPageContentHeight && (actualSpacing + blockHeight > availableHeight) {
                beginNewPage()
            } else {
                cursorY += actualSpacing
            }

            drawUnsplittableText(attributedString, x: xPos, width: width, sceneNumber: nil)
            return
        }

        if element.type == .sceneHeading {
            let headingHeight = calculateHeight(of: attributedString, width: width)
            let nextRequiredHeight = minimumHeightFollowingSceneHeading(from: index, allElements: allElements)

            if cursorY + actualSpacing + headingHeight + nextRequiredHeight > pageHeight - ScriptExportLayoutConfig.CenteredLayout.marginBottom {
                beginNewPage()
            } else {
                cursorY += actualSpacing
            }

            drawUnsplittableText(attributedString, x: xPos, width: width, sceneNumber: currentSceneNumber)
        } else {
            cursorY += actualSpacing
            drawSplittableText(attributedString, x: xPos, width: width)
        }
    }

    private func minimumHeightFollowingSceneHeading(from index: Int, allElements: [ScriptExportElement]) -> CGFloat {
        let nextIndex = index + 1
        guard nextIndex < allElements.count else { return 0.0 }

        let nextElement = allElements[nextIndex]
        let nextSpacing: CGFloat = (nextElement.type == .dialogue || nextElement.type == .parenthetical) ? 0.0 : config.centeredParagraphSpacing

        switch nextElement.type {
        case .character:
            return nextSpacing + minimumHeightForCharacterBlock(startingAt: nextIndex, allElements: allElements)
        case .sceneHeading:
            let nextString = createAttributedString(for: nextElement)
            let nextHeight = calculateHeight(of: nextString, width: contentWidth(for: nextElement.type))
            return nextSpacing + nextHeight
        default:
            let nextString = createAttributedString(for: nextElement)
            let nextHeight = calculateHeight(of: nextString, width: contentWidth(for: nextElement.type))
            return nextSpacing + min(nextHeight, centeredOneLineHeight)
        }
    }

    private func minimumHeightForCharacterBlock(startingAt startIndex: Int, allElements: [ScriptExportElement]) -> CGFloat {
        var blockHeight: CGFloat = 0.0
        var index = startIndex

        while index < allElements.count {
            let element = allElements[index]
            if index != startIndex && element.type != .dialogue && element.type != .parenthetical {
                break
            }

            let attrString = createAttributedString(for: element)
            blockHeight += calculateHeight(of: attrString, width: contentWidth(for: element.type))
            index += 1
        }

        return blockHeight
    }

    private var centeredOneLineHeight: CGFloat {
        ceil(config.centeredFontSize + ScriptExportLayoutConfig.CenteredLayout.lineSpacing + 2.0)
    }

    private func drawUnsplittableText(_ attrString: NSAttributedString, x: CGFloat, width: CGFloat, sceneNumber: Int?) {
        guard let ctx = context else { return }

        let height = calculateHeight(of: attrString, width: width)
        let yPos = pageHeight - cursorY - height
        let rect = CGRect(x: x, y: yPos, width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        attrString.draw(in: rect)

        if let num = sceneNumber {
            drawLeftSceneNumber(num, at: yPos, height: height)
            if config.centeredShowRightSceneNumber {
                drawRightSceneNumber(num, at: yPos, height: height)
            }
        }

        NSGraphicsContext.restoreGraphicsState()
        cursorY += height
    }

    private func drawSplittableText(_ attrString: NSAttributedString, x: CGFloat, width: CGFloat) {
        guard let ctx = context else { return }

        let textStorage = NSTextStorage(attributedString: attrString)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        var currentGlyphIndex = 0
        while currentGlyphIndex < layoutManager.numberOfGlyphs {
            let availableHeight = pageHeight - ScriptExportLayoutConfig.CenteredLayout.marginBottom - cursorY
            if availableHeight < 10 {
                beginNewPage()
                continue
            }

            let textContainer = NSTextContainer(size: CGSize(width: width, height: availableHeight))
            textContainer.lineFragmentPadding = 0
            layoutManager.addTextContainer(textContainer)

            let glyphRange = layoutManager.glyphRange(for: textContainer)
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let subString = attrString.attributedSubstring(from: charRange)

            let usedRect = layoutManager.usedRect(for: textContainer)
            let height = ceil(usedRect.height)
            let yPos = pageHeight - cursorY - height

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            subString.draw(in: CGRect(x: x, y: yPos, width: width, height: height))
            NSGraphicsContext.restoreGraphicsState()

            cursorY += height
            currentGlyphIndex = NSMaxRange(glyphRange)
            if currentGlyphIndex < layoutManager.numberOfGlyphs {
                beginNewPage()
            }
        }
    }

    private func createAttributedString(for element: ScriptExportElement) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = ScriptExportLayoutConfig.CenteredLayout.lineSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineBreakStrategy = []
        paragraphStyle.allowsDefaultTighteningForTruncation = true

        var text = element.text
        var shouldUseBold = false

        switch element.type {
        case .sceneHeading:
            shouldUseBold = config.centeredIsSceneHeadingBold
            text = text.uppercased()
        case .character:
            shouldUseBold = config.centeredIsCharacterBold
        case .centered:
            shouldUseBold = true
            paragraphStyle.alignment = .center
        case .transition:
            shouldUseBold = false
            text = text.uppercased()
            paragraphStyle.alignment = .right
        default:
            shouldUseBold = false
        }

        let targetFontName = shouldUseBold ? boldFontName : regularFontName
        let font: NSFont
        if let customFont = NSFont(name: targetFontName, size: config.centeredFontSize) {
            font = customFont
        } else {
            font = shouldUseBold
                ? NSFont.monospacedSystemFont(ofSize: config.centeredFontSize, weight: .bold)
                : NSFont.monospacedSystemFont(ofSize: config.centeredFontSize, weight: .regular)
        }

        return NSAttributedString(string: text, attributes: [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.black
        ])
    }

    private func drawPageNumber(_ number: Int) {
        guard let ctx = context else { return }
        let font = NSFont(name: regularFontName, size: config.centeredFontSize)
            ?? NSFont.monospacedSystemFont(ofSize: config.centeredFontSize, weight: .regular)
        let attrStr = NSAttributedString(string: "\(number).", attributes: [.font: font, .foregroundColor: NSColor.black])

        let extraOffset: CGFloat = 28.35
        let x = pageWidth - ScriptExportLayoutConfig.CenteredLayout.pageNumberRight - 30
        let y = pageHeight - ScriptExportLayoutConfig.CenteredLayout.pageNumberTop - extraOffset

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        attrStr.draw(at: CGPoint(x: x, y: y))
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawLeftSceneNumber(_ number: Int, at y: CGFloat, height: CGFloat) {
        let font = NSFont(name: regularFontName, size: config.centeredFontSize)
            ?? NSFont.monospacedSystemFont(ofSize: config.centeredFontSize, weight: .regular)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right

        let attrStr = NSAttributedString(string: "\(number)", attributes: [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle
        ])

        let width: CGFloat = 50.0
        let centerX = ScriptExportLayoutConfig.CenteredLayout.sceneLeft / 2.0
        let x = centerX - (width / 2.0) - 14.175
        attrStr.draw(in: CGRect(x: x, y: y, width: width, height: height))
    }

    private func drawRightSceneNumber(_ number: Int, at y: CGFloat, height: CGFloat) {
        let font = NSFont(name: regularFontName, size: config.centeredFontSize)
            ?? NSFont.monospacedSystemFont(ofSize: config.centeredFontSize, weight: .regular)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right

        let attrStr = NSAttributedString(string: "\(number)", attributes: [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle
        ])

        let width: CGFloat = 50.0
        let x = pageWidth - ScriptExportLayoutConfig.CenteredLayout.marginRight - width
        attrStr.draw(in: CGRect(x: x, y: y, width: width, height: height))
    }

    private func xPosition(for type: ScriptExportElementType) -> CGFloat {
        switch type {
        case .sceneHeading: return ScriptExportLayoutConfig.CenteredLayout.sceneLeft
        case .action: return ScriptExportLayoutConfig.CenteredLayout.actionLeft
        case .character: return ScriptExportLayoutConfig.CenteredLayout.characterLeft
        case .dialogue: return ScriptExportLayoutConfig.CenteredLayout.dialogueLeft
        case .parenthetical: return ScriptExportLayoutConfig.CenteredLayout.parentheticalLeft
        case .transition: return ScriptExportLayoutConfig.CenteredLayout.transitionLeft
        case .centered: return ScriptExportLayoutConfig.CenteredLayout.centeredLeft
        default: return ScriptExportLayoutConfig.CenteredLayout.actionLeft
        }
    }

    private func contentWidth(for type: ScriptExportElementType) -> CGFloat {
        switch type {
        case .sceneHeading: return pageWidth - ScriptExportLayoutConfig.CenteredLayout.sceneLeft - ScriptExportLayoutConfig.CenteredLayout.sceneRight
        case .action: return pageWidth - ScriptExportLayoutConfig.CenteredLayout.actionLeft - ScriptExportLayoutConfig.CenteredLayout.actionRight
        case .character: return pageWidth - ScriptExportLayoutConfig.CenteredLayout.characterLeft - ScriptExportLayoutConfig.CenteredLayout.characterRight
        case .dialogue: return pageWidth - ScriptExportLayoutConfig.CenteredLayout.dialogueLeft - ScriptExportLayoutConfig.CenteredLayout.dialogueRight
        case .parenthetical: return pageWidth - ScriptExportLayoutConfig.CenteredLayout.parentheticalLeft - ScriptExportLayoutConfig.CenteredLayout.parentheticalRight
        case .transition: return pageWidth - ScriptExportLayoutConfig.CenteredLayout.transitionLeft - ScriptExportLayoutConfig.CenteredLayout.transitionRight
        case .centered: return pageWidth - ScriptExportLayoutConfig.CenteredLayout.centeredLeft - ScriptExportLayoutConfig.CenteredLayout.centeredRight
        default: return pageWidth - ScriptExportLayoutConfig.CenteredLayout.actionLeft - ScriptExportLayoutConfig.CenteredLayout.actionRight
        }
    }

    private func calculateHeight(of string: NSAttributedString, width: CGFloat) -> CGFloat {
        let rect = string.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(rect.height)
    }
}

final class ScriptKoreanPDFGenerator {
    let config: ScriptExportLayoutConfig
    let pageWidth: CGFloat = 595.2
    let pageHeight: CGFloat = 841.8
    let fontName = "Sans Mono CJK Final Draft"
    let safetyMargin: CGFloat = 20.0

    var sceneCounter = 0

    init(config: ScriptExportLayoutConfig) {
        self.config = config
    }

    func generate(from elements: [ScriptExportElement]) -> Data {
        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        let coverElements = elements.filter { isCoverElement($0.type) }
        let scriptElements = elements.filter { !isCoverElement($0.type) }

        if !coverElements.isEmpty {
            context.beginPDFPage(nil)
            setupGraphicsContext(context)
            drawCoverPage(context: context, elements: coverElements)
            context.endPDFPage()
        }

        if !scriptElements.isEmpty {
            sceneCounter = 0
            var cursorY = ScriptExportLayoutConfig.KoreanLayout.marginTop
            var pageNumber = 1

            context.beginPDFPage(nil)
            setupGraphicsContext(context)

            var index = 0
            var previousElementType: ScriptExportElementType? = nil

            while index < scriptElements.count {
                let element = scriptElements[index]

                var currentSceneNumber: Int? = nil
                if element.type == .sceneHeading {
                    sceneCounter += 1
                    currentSceneNumber = sceneCounter
                }

                let (attributedString, width, itemsConsumed, currentType) = processElement(at: index, elements: scriptElements, sceneNumber: currentSceneNumber)

                let spacing: CGFloat
                if isFirstLineOfPage(cursorY) {
                    spacing = 0
                } else if currentType == .sceneHeading {
                    spacing = ScriptExportLayoutConfig.KoreanLayout.paragraphSpacing * 2.5
                } else if previousElementType == .dialogue && currentType == .dialogue {
                    spacing = ScriptExportLayoutConfig.KoreanLayout.lineSpacing
                } else {
                    spacing = ScriptExportLayoutConfig.KoreanLayout.paragraphSpacing
                }

                var nextElementMinHeight: CGFloat = 0.0
                if currentType == .sceneHeading {
                    let nextIndex = index + itemsConsumed
                    if nextIndex < scriptElements.count {
                        let (nextAttr, nextWidth, _, nextType) = processElement(at: nextIndex, elements: scriptElements, sceneNumber: nil)
                        let gap = ScriptExportLayoutConfig.KoreanLayout.paragraphSpacing
                        if nextType == .action {
                            let oneLineHeight = config.koreanFontSize + ScriptExportLayoutConfig.KoreanLayout.lineSpacing + 2.0
                            nextElementMinHeight = gap + oneLineHeight
                        } else {
                            nextElementMinHeight = gap + calculateHeight(of: nextAttr, width: nextWidth)
                        }
                    }
                }

                let height = calculateHeight(of: attributedString, width: width)
                let availableHeight = pageHeight - ScriptExportLayoutConfig.KoreanLayout.marginBottom - cursorY - spacing

                if currentType == .action && height > availableHeight && availableHeight > 0 {
                    cursorY += spacing
                    _ = drawSplittedText(
                        attributedString,
                        in: context,
                        width: width,
                        xPos: xPosition(for: currentType),
                        cursorY: &cursorY,
                        pageNumber: &pageNumber
                    )
                    previousElementType = currentType
                    index += itemsConsumed
                    continue
                }

                let requiredTotalHeight = height + nextElementMinHeight
                if cursorY + spacing + requiredTotalHeight > pageHeight - ScriptExportLayoutConfig.KoreanLayout.marginBottom {
                    context.endPDFPage()
                    context.beginPDFPage(nil)
                    setupGraphicsContext(context)
                    cursorY = ScriptExportLayoutConfig.KoreanLayout.marginTop
                    pageNumber += 1
                    drawPageNumber(pageNumber, in: context)
                } else {
                    cursorY += spacing
                }

                let xPos: CGFloat = (currentType == .dialogue) ? safetyMargin : xPosition(for: currentType)
                let yPos = pageHeight - cursorY - height
                attributedString.draw(in: CGRect(x: xPos, y: yPos, width: width, height: height))

                cursorY += height
                previousElementType = currentType
                index += itemsConsumed
            }
            context.endPDFPage()
        }

        context.closePDF()
        return pdfData as Data
    }

    private func drawCoverPage(context: CGContext, elements: [ScriptExportElement]) {
        let titleText = elements.first(where: { $0.type == .coverTitle })?.text ?? "제목 미정"
        let companyText = elements.first(where: { $0.type == .coverProduction })?.text ?? "제작사 미정"

        var currentY: CGFloat = pageHeight * 0.3
        for type in [ScriptExportElementType.coverTitle, .coverVersion, .coverDate] {
            if let element = elements.first(where: { $0.type == type }) {
                let fontSize: CGFloat = 11.0
                let isBold = (type == .coverTitle)
                let attrStr = createCoverString(text: element.text, fontSize: fontSize, isBold: isBold, align: .center, lineSpacing: 6.0)
                let width = pageWidth - 100
                let height = calculateHeight(of: attrStr, width: width)
                let y = pageHeight - currentY - height
                attrStr.draw(in: CGRect(x: 50.0, y: y, width: width, height: height))
                currentY += height + 25
            }
        }

        currentY = pageHeight * 0.70
        for type in [ScriptExportElementType.coverAuthor, .coverProduction, .coverContact] {
            if let element = elements.first(where: { $0.type == type }) {
                let attrStr = createCoverString(text: element.text, fontSize: 11.0, isBold: false, align: .center, lineSpacing: 6.0)
                let width = pageWidth - 100
                let height = calculateHeight(of: attrStr, width: width)
                let y = pageHeight - currentY - height
                attrStr.draw(in: CGRect(x: 50.0, y: y, width: width, height: height))
                currentY += height + 25
            }
        }

        let legalText = "본 시나리오 <\(titleText)>은 \(companyText)의 자산이며, 복제, 재생산, 배포 및 공개는 그 전부 또는 일부를 불문하고 엄격히 금지됩니다. This screenplay, titled \(titleText), is the exclusive property of \(companyText). Any unauthorized duplication, reproduction, distribution, or disclosure of this material, in whole or in part, is strictly prohibited."
        let legalAttrStr = createCoverString(text: legalText, fontSize: 9.0, isBold: false, align: .center, lineSpacing: 3.0)
        let width = pageWidth - 100
        let height = calculateHeight(of: legalAttrStr, width: width)
        legalAttrStr.draw(in: CGRect(x: 50.0, y: ScriptExportLayoutConfig.KoreanLayout.marginBottom, width: width, height: height))
    }

    private func createCoverString(text: String, fontSize: CGFloat, isBold: Bool, align: NSTextAlignment, lineSpacing: CGFloat) -> NSAttributedString {
        var font = NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if isBold {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }

        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineSpacing = lineSpacing

        return NSAttributedString(string: text, attributes: [
            .font: font,
            .paragraphStyle: style,
            .foregroundColor: NSColor.black
        ])
    }

    private func isCoverElement(_ type: ScriptExportElementType) -> Bool {
        switch type {
        case .coverTitle, .coverVersion, .coverDate, .coverAuthor, .coverProduction, .coverContact:
            return true
        default:
            return false
        }
    }

    private func drawSplittedText(_ attrString: NSAttributedString, in context: CGContext, width: CGFloat, xPos: CGFloat, cursorY: inout CGFloat, pageNumber: inout Int) -> NSAttributedString? {
        let framesetter = CTFramesetterCreateWithAttributedString(attrString as CFAttributedString)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 10000), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        let lines = CTFrameGetLines(frame) as! [CTLine]

        var currentY = cursorY
        for line in lines {
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let lineHeight = ascent + descent + ScriptExportLayoutConfig.KoreanLayout.lineSpacing

            if currentY + lineHeight > pageHeight - ScriptExportLayoutConfig.KoreanLayout.marginBottom {
                context.endPDFPage()
                context.beginPDFPage(nil)
                setupGraphicsContext(context)
                currentY = ScriptExportLayoutConfig.KoreanLayout.marginTop
                pageNumber += 1
                drawPageNumber(pageNumber, in: context)
            }
            let yPos = pageHeight - currentY - ascent
            context.textPosition = CGPoint(x: xPos, y: yPos)
            CTLineDraw(line, context)
            currentY += lineHeight
        }
        cursorY = currentY
        return nil
    }

    private func setupGraphicsContext(_ context: CGContext) {
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    }

    private func isFirstLineOfPage(_ cursorY: CGFloat) -> Bool {
        abs(cursorY - ScriptExportLayoutConfig.KoreanLayout.marginTop) < 0.5
    }

    private func processElement(at index: Int, elements: [ScriptExportElement], sceneNumber: Int?) -> (NSAttributedString, CGFloat, Int, ScriptExportElementType) {
        let element = elements[index]
        if element.type == .character { return createKoreanDialogueBlock(startIndex: index, elements: elements) }

        if element.type == .sceneHeading {
            let text = element.text.uppercased()
            let sceneText = sceneNumber != nil ? "\(sceneNumber!). \(text)" : text

            var font = NSFont(name: fontName, size: config.koreanFontSize) ?? NSFont.monospacedSystemFont(ofSize: config.koreanFontSize, weight: .regular)
            if config.koreanIsSceneBold {
                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }

            let style = createParagraphStyle(alignment: .left)
            let attrStr = NSAttributedString(string: sceneText, attributes: [.font: font, .paragraphStyle: style, .foregroundColor: NSColor.black])
            return (attrStr, contentWidth(for: .sceneHeading), 1, .sceneHeading)
        }

        let attrStr = createAttributedString(for: element)
        return (attrStr, contentWidth(for: element.type), 1, element.type)
    }

    private func createKoreanDialogueBlock(startIndex: Int, elements: [ScriptExportElement]) -> (NSAttributedString, CGFloat, Int, ScriptExportElementType) {
        let characterElement = elements[startIndex]
        var consumedCount = 1
        let finalText = NSMutableAttributedString()

        let gap: CGFloat = 8.0
        let baseFont = NSFont(name: fontName, size: config.koreanFontSize) ?? NSFont.monospacedSystemFont(ofSize: config.koreanFontSize, weight: .regular)

        var characterFont = baseFont
        if config.koreanIsCharacterBold {
            characterFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
        }

        let nameTab: NSTextTab
        let nameLimitAbsolute: CGFloat
        let nameAnchorAbsolute: CGFloat
        let maxAllowedWidth: CGFloat

        if config.koreanCharacterAlignment == .right {
            nameAnchorAbsolute = ScriptExportLayoutConfig.KoreanLayout.dialogueIndent - gap
            nameLimitAbsolute = ScriptExportLayoutConfig.KoreanLayout.actionLeft
            let relativeNameAnchor = nameAnchorAbsolute - safetyMargin
            nameTab = NSTextTab(textAlignment: .right, location: relativeNameAnchor, options: [:])
            maxAllowedWidth = nameAnchorAbsolute - nameLimitAbsolute
        } else {
            nameLimitAbsolute = ScriptExportLayoutConfig.KoreanLayout.characterLeftAligned
            nameAnchorAbsolute = ScriptExportLayoutConfig.KoreanLayout.dialogueIndent - gap
            let relativeNameStart = nameLimitAbsolute - safetyMargin
            nameTab = NSTextTab(textAlignment: .left, location: relativeNameStart, options: [:])
            maxAllowedWidth = nameAnchorAbsolute - nameLimitAbsolute
        }

        let relativeDialogueStart = ScriptExportLayoutConfig.KoreanLayout.dialogueIndent - safetyMargin
        let dialogueTab = NSTextTab(textAlignment: .left, location: relativeDialogueStart, options: [:])

        let tempAttrs: [NSAttributedString.Key: Any] = [.font: characterFont]
        let actualNameWidth = characterElement.text.size(withAttributes: tempAttrs).width

        var expansionFactor: CGFloat = 0.0
        if actualNameWidth > maxAllowedWidth {
            expansionFactor = (maxAllowedWidth / actualNameWidth) - 1.0
        }

        let style = NSMutableParagraphStyle()
        style.lineSpacing = ScriptExportLayoutConfig.KoreanLayout.lineSpacing
        style.lineBreakMode = .byWordWrapping
        style.alignment = .left
        style.tabStops = [nameTab, dialogueTab]
        style.headIndent = relativeDialogueStart

        var nameAttrs: [NSAttributedString.Key: Any] = [.font: characterFont, .paragraphStyle: style, .foregroundColor: NSColor.black]
        if expansionFactor < 0 { nameAttrs[.expansion] = expansionFactor }

        finalText.append(NSAttributedString(string: "\t" + characterElement.text, attributes: nameAttrs))
        let contentAttrs: [NSAttributedString.Key: Any] = [.font: baseFont, .paragraphStyle: style, .foregroundColor: NSColor.black]
        finalText.append(NSAttributedString(string: "\t", attributes: contentAttrs))

        var currentIndex = startIndex + 1
        while currentIndex < elements.count {
            let nextElement = elements[currentIndex]
            if nextElement.type == .dialogue || nextElement.type == .parenthetical {
                finalText.append(NSAttributedString(string: nextElement.text + " ", attributes: contentAttrs))
                consumedCount += 1
                currentIndex += 1
            } else {
                break
            }
        }

        let expandedWidth = pageWidth - safetyMargin - ScriptExportLayoutConfig.KoreanLayout.dialogueRight
        return (finalText, expandedWidth, consumedCount, .dialogue)
    }

    private func createParagraphStyle(alignment: NSTextAlignment) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = ScriptExportLayoutConfig.KoreanLayout.lineSpacing
        style.lineBreakMode = .byWordWrapping
        style.alignment = alignment
        return style
    }

    private func createAttributedString(for element: ScriptExportElement) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = ScriptExportLayoutConfig.KoreanLayout.lineSpacing
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byWordWrapping

        var font = NSFont(name: fontName, size: config.koreanFontSize) ?? NSFont.monospacedSystemFont(ofSize: config.koreanFontSize, weight: .regular)
        let text = element.text

        switch element.type {
        case .action:
            paragraphStyle.alignment = .left
            paragraphStyle.hyphenationFactor = 1.0
        case .transition:
            paragraphStyle.alignment = .right
        case .centered:
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            paragraphStyle.alignment = .center
        case .sceneHeading:
            paragraphStyle.alignment = .left
        default:
            break
        }

        return NSAttributedString(string: text, attributes: [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.black
        ])
    }

    private func xPosition(for type: ScriptExportElementType) -> CGFloat {
        switch type {
        case .sceneHeading: return ScriptExportLayoutConfig.KoreanLayout.sceneLeft
        case .action: return ScriptExportLayoutConfig.KoreanLayout.actionLeft
        case .transition: return ScriptExportLayoutConfig.KoreanLayout.transitionLeft
        case .centered: return ScriptExportLayoutConfig.KoreanLayout.centeredLeft
        default: return ScriptExportLayoutConfig.KoreanLayout.marginLeft
        }
    }

    private func contentWidth(for type: ScriptExportElementType) -> CGFloat {
        switch type {
        case .sceneHeading: return pageWidth - ScriptExportLayoutConfig.KoreanLayout.sceneLeft - ScriptExportLayoutConfig.KoreanLayout.sceneRight
        case .action: return pageWidth - ScriptExportLayoutConfig.KoreanLayout.actionLeft - ScriptExportLayoutConfig.KoreanLayout.actionRight
        case .dialogue, .character, .parenthetical: return pageWidth - ScriptExportLayoutConfig.KoreanLayout.dialogueLeft - ScriptExportLayoutConfig.KoreanLayout.dialogueRight
        case .transition: return pageWidth - ScriptExportLayoutConfig.KoreanLayout.transitionLeft - ScriptExportLayoutConfig.KoreanLayout.transitionRight
        case .centered: return pageWidth - ScriptExportLayoutConfig.KoreanLayout.centeredLeft - ScriptExportLayoutConfig.KoreanLayout.centeredRight
        default: return pageWidth - ScriptExportLayoutConfig.KoreanLayout.marginLeft - ScriptExportLayoutConfig.KoreanLayout.marginRight
        }
    }

    private func calculateHeight(of string: NSAttributedString, width: CGFloat) -> CGFloat {
        let rect = string.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(rect.height)
    }

    private func drawPageNumber(_ number: Int, in context: CGContext) {
        if number == 1 { return }
        let text = "\(number)."
        let font = NSFont(name: fontName, size: config.koreanFontSize) ?? NSFont.monospacedSystemFont(ofSize: config.koreanFontSize, weight: .regular)
        let x = pageWidth - ScriptExportLayoutConfig.KoreanLayout.pageNumberRight - 20
        let y = pageHeight - ScriptExportLayoutConfig.KoreanLayout.pageNumberTop
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black])
            .draw(at: CGPoint(x: x, y: y))
    }
}
