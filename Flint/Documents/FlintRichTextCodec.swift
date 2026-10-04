import Foundation
import UIKit

enum FlintBlockStyle: String, CaseIterable, Equatable {
    case body
    case heading1
    case heading2
    case heading3
    case bulletList
    case numberedList
    case quote
    case codeBlock

    var label: String {
        switch self {
        case .body:
            return "Body"
        case .heading1:
            return "Title"
        case .heading2:
            return "Heading"
        case .heading3:
            return "Subhead"
        case .bulletList:
            return "Bulleted"
        case .numberedList:
            return "Numbered"
        case .quote:
            return "Quote"
        case .codeBlock:
            return "Code"
        }
    }
}

struct FlintFormattingState: Equatable {
    var blockStyle: FlintBlockStyle = .body
    var isBold = false
    var isItalic = false
    var isCode = false
    var hasLink = false
    var hasSelection = false
    var canUndo = false
    var canRedo = false
}

extension NSAttributedString.Key {
    static let flintBlockStyle = NSAttributedString.Key("FlintBlockStyle")
    static let flintInlineCode = NSAttributedString.Key("FlintInlineCode")
    static let flintBold = NSAttributedString.Key("FlintBold")
    static let flintItalic = NSAttributedString.Key("FlintItalic")
    static let flintImageMarkdownSource = NSAttributedString.Key("FlintImageMarkdownSource")
    static let flintImageAssetURL = NSAttributedString.Key("FlintImageAssetURL")
    static let flintImageAltText = NSAttributedString.Key("FlintImageAltText")
    static let flintSyntheticImageCaption = NSAttributedString.Key("FlintSyntheticImageCaption")
}

enum FlintRichTextCodec {
    private static let bulletPrefix = "\u{2022}\t"
    private static let escapableMarkdownCharacters: Set<Character> = ["\\", "*", "_", "[", "]", "`"]

    static func attributedString(from markdown: String, noteURL: URL? = nil, vaultURL: URL? = nil) -> NSMutableAttributedString {
        let formatting = DebugLog.shared.begin(.textFormat, file: noteURL)
        defer { formatting.finish(.success) }
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var isInsideCodeFence = false
        let result = NSMutableAttributedString()
        var hasVisibleLine = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                isInsideCodeFence.toggle()
                continue
            }

            if hasVisibleLine {
                let newlineAttributes = result.length > 0
                    ? result.attributes(at: max(result.length - 1, 0), effectiveRange: nil)
                    : paragraphAttributes(for: .body)
                result.append(NSAttributedString(string: "\n", attributes: newlineAttributes))
            }

            if !isInsideCodeFence,
               let imageReference = markdownImageReference(for: trimmed) {
                result.append(attributedImageBlock(
                    markdownSource: imageReference.markdownSource,
                    altText: imageReference.altText,
                    assetURL: resolvedImageURL(for: imageReference.sourcePath, noteURL: noteURL, vaultURL: vaultURL)
                ))
            } else {
                let style: FlintBlockStyle
                let content: String

                if isInsideCodeFence {
                    style = .codeBlock
                    content = line
                } else if let headingLevel = headingLevel(for: line) {
                    style = headingStyle(for: headingLevel)
                    content = String(line.drop { $0 == "#" || $0 == " " })
                } else if let bulletContent = bulletContent(for: line) {
                    style = .bulletList
                    content = bulletPrefix + bulletContent
                } else if let numbered = numberedListContent(for: line) {
                    style = .numberedList
                    content = "\(numbered.number).\t" + numbered.content
                } else if trimmed.hasPrefix(">") {
                    style = .quote
                    content = String(trimmed.dropFirst().drop(while: { $0 == " " }))
                } else {
                    style = .body
                    content = line
                }

                result.append(attributedParagraph(for: content, style: style))
            }
            hasVisibleLine = true
        }

        if result.length == 0 {
            result.append(attributedParagraph(for: "", style: .body))
        }

        normalizeNumberedListMarkers(in: result)
        return result
    }

    static func markdown(from attributedString: NSAttributedString) -> String {
        let formatting = DebugLog.shared.begin(.textFormat)
        defer { formatting.finish(.success) }
        let paragraphs = attributedString.string.components(separatedBy: "\n")
        guard !paragraphs.isEmpty else { return "" }

        var markdownLines: [String] = []
        var numberedIndex = 0
        var isInsideCodeBlock = false

        for paragraphIndex in paragraphs.indices {
            let location = paragraphLocation(for: paragraphIndex, paragraphs: paragraphs)
            let attributes = safeAttributes(at: location, in: attributedString)
            let style = blockStyle(from: attributes)
            let rawParagraph = paragraphs[paragraphIndex]

            if (attributes[.flintSyntheticImageCaption] as? Bool) == true {
                continue
            }

            if let imageMarkdown = attributes[.flintImageMarkdownSource] as? String {
                if style == .codeBlock, isInsideCodeBlock {
                    markdownLines.append("```")
                    isInsideCodeBlock = false
                }
                markdownLines.append(imageMarkdown)
                numberedIndex = 0
                continue
            }

            if style != .codeBlock, isInsideCodeBlock {
                markdownLines.append("```")
                isInsideCodeBlock = false
            }

            switch style {
            case .heading1:
                markdownLines.append("# " + markdownInline(from: rawParagraph, globalLocation: location, in: attributedString))
                numberedIndex = 0
            case .heading2:
                markdownLines.append("## " + markdownInline(from: rawParagraph, globalLocation: location, in: attributedString))
                numberedIndex = 0
            case .heading3:
                markdownLines.append("### " + markdownInline(from: rawParagraph, globalLocation: location, in: attributedString))
                numberedIndex = 0
            case .bulletList:
                let serialized = markdownInline(from: visibleContent(for: rawParagraph, style: style), globalLocation: location, in: attributedString, visiblePrefixLength: visiblePrefix(for: style, paragraphText: rawParagraph).utf16.count)
                markdownLines.append(serialized.isEmpty ? "" : "- " + serialized)
                numberedIndex = 0
            case .numberedList:
                numberedIndex += 1
                let serialized = markdownInline(from: visibleContent(for: rawParagraph, style: style), globalLocation: location, in: attributedString, visiblePrefixLength: visiblePrefix(for: style, paragraphText: rawParagraph).utf16.count)
                markdownLines.append(serialized.isEmpty ? "" : "\(numberedIndex). " + serialized)
            case .quote:
                markdownLines.append("> " + markdownInline(from: rawParagraph, globalLocation: location, in: attributedString))
                numberedIndex = 0
            case .codeBlock:
                if !isInsideCodeBlock {
                    markdownLines.append("```")
                    isInsideCodeBlock = true
                }
                markdownLines.append(rawParagraph)
                numberedIndex = 0
            case .body:
                markdownLines.append(markdownInline(from: rawParagraph, globalLocation: location, in: attributedString))
                numberedIndex = 0
            }
        }

        if isInsideCodeBlock {
            markdownLines.append("```")
        }

        return markdownLines.joined(separator: "\n")
    }

    static func visiblePrefix(for style: FlintBlockStyle, paragraphText: String) -> String {
        switch style {
        case .bulletList:
            return bulletPrefix
        case .numberedList:
            let numberPart = paragraphText.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "1."
            return numberPart + "\t"
        default:
            return ""
        }
    }

    static func visibleContent(for paragraphText: String, style: FlintBlockStyle) -> String {
        let prefix = visiblePrefix(for: style, paragraphText: paragraphText)
        guard !prefix.isEmpty else { return paragraphText }
        return String(paragraphText.dropFirst(prefix.count))
    }

    static func paragraphText(in text: NSString, paragraphRange: NSRange) -> String {
        guard paragraphRange.location != NSNotFound,
              paragraphRange.length > 0,
              paragraphRange.location < text.length else {
            return ""
        }

        let paragraphEnd = paragraphRange.location + paragraphRange.length
        guard paragraphEnd <= text.length else { return "" }

        let trailingCharacterRange = NSRange(location: paragraphEnd - 1, length: 1)
        let hasTrailingNewline = text.substring(with: trailingCharacterRange) == "\n"
        let contentLength = paragraphRange.length - (hasTrailingNewline ? 1 : 0)
        guard contentLength > 0 else { return "" }

        return text.substring(with: NSRange(location: paragraphRange.location, length: contentLength))
    }

    static func blockStyle(at location: Int, in attributedString: NSAttributedString) -> FlintBlockStyle {
        blockStyle(from: safeAttributes(at: location, in: attributedString))
    }

    static func blockStyle(from attributes: [NSAttributedString.Key: Any]) -> FlintBlockStyle {
        if let rawValue = attributes[.flintBlockStyle] as? String, let style = FlintBlockStyle(rawValue: rawValue) {
            return style
        }

        return .body
    }

    static func applyBlockStyle(_ style: FlintBlockStyle, to attributedString: NSMutableAttributedString, paragraphRange: NSRange) {
        var cursor = paragraphRange.location
        var end = NSMaxRange(paragraphRange)
        var numberedIndex = 1

        while cursor < end, cursor <= attributedString.length {
            let text = attributedString.string as NSString
            guard text.length > 0 else { break }

            let safeLocation = min(cursor, max(text.length - 1, 0))
            let currentParagraphRange = text.paragraphRange(for: NSRange(location: safeLocation, length: 0))
            let paragraphText = paragraphText(in: text, paragraphRange: currentParagraphRange)
            let content = visibleContent(for: paragraphText, style: blockStyle(at: currentParagraphRange.location, in: attributedString))
            let replacement = replacementText(for: content, style: style, numberedIndex: numberedIndex)
            let replacementAttributed = attributedParagraph(for: replacement, style: style)
            let replaceRange = NSRange(location: currentParagraphRange.location, length: paragraphText.utf16.count)
            attributedString.replaceCharacters(in: replaceRange, with: replacementAttributed)
            end += replacementAttributed.length - replaceRange.length

            let hadTrailingNewline = currentParagraphRange.length > replaceRange.length
            cursor = currentParagraphRange.location + replacementAttributed.length + (hadTrailingNewline ? 1 : 0)

            if style == .numberedList {
                numberedIndex += 1
            }
        }

        normalizeNumberedListMarkers(in: attributedString)
    }

    static func normalizeStyling(in attributedString: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attributedString.length)
        let text = attributedString.string as NSString
        var cursor = 0

        while cursor < attributedString.length {
            let paragraphRange = text.paragraphRange(for: NSRange(location: cursor, length: 0))
            let style = blockStyle(at: paragraphRange.location, in: attributedString)
            attributedString.addAttributes(paragraphAttributes(for: style), range: paragraphRange)
            reapplyFonts(in: attributedString, range: paragraphRange)
            cursor = NSMaxRange(paragraphRange)
        }

        if fullRange.length > 0 {
            normalizeNumberedListMarkers(in: attributedString)
        }
    }

    static func formattingState(
        attributedString: NSAttributedString,
        selectedRange: NSRange,
        undoManager: UndoManager?,
        typingAttributes: [NSAttributedString.Key: Any]? = nil
    ) -> FlintFormattingState {
        let location = max(0, min(selectedRange.location, max(attributedString.length - 1, 0)))
        let attributes = selectedRange.length == 0 ? (typingAttributes ?? safeAttributes(at: location, in: attributedString)) : safeAttributes(at: location, in: attributedString)

        return FlintFormattingState(
            blockStyle: blockStyle(from: attributes),
            isBold: isBold(in: attributes),
            isItalic: isItalic(in: attributes),
            isCode: isInlineCode(in: attributes),
            hasLink: attributes[.link] != nil,
            hasSelection: selectedRange.length > 0,
            canUndo: undoManager?.canUndo ?? false,
            canRedo: undoManager?.canRedo ?? false
        )
    }

    static func defaultTypingAttributes(for style: FlintBlockStyle) -> [NSAttributedString.Key: Any] {
        paragraphAttributes(for: style)
    }

    static func updateImageAttachments(in attributedString: NSMutableAttributedString, availableTextWidth: CGFloat) {
        guard attributedString.length > 0 else { return }

        attributedString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributedString.length), options: []) { value, range, _ in
            guard let attachment = value as? FlintMarkdownImageAttachment else { return }
            attachment.applyLayout(for: availableTextWidth)
            attributedString.addAttributes([
                .flintImageMarkdownSource: attachment.markdownSource,
                .flintImageAltText: attachment.altText,
                .flintImageAssetURL: attachment.assetURL as Any
            ], range: range)
        }
    }

    private static func markdownInline(
        from paragraphText: String,
        globalLocation: Int,
        in attributedString: NSAttributedString,
        visiblePrefixLength: Int = 0
    ) -> String {
        if paragraphText.isEmpty {
            return ""
        }

        let contentRange = NSRange(location: globalLocation + visiblePrefixLength, length: paragraphText.utf16.count)
        guard contentRange.location + contentRange.length <= attributedString.length else {
            return paragraphText
        }

        let substring = attributedString.attributedSubstring(from: contentRange)
        let nsSubstring = substring.string as NSString
        var output = ""
        substring.enumerateAttributes(in: NSRange(location: 0, length: substring.length), options: []) { attributes, range, _ in
            output += markdownWrapped(nsSubstring.substring(with: range), attributes: attributes)
        }

        return output
    }

    private static func markdownWrapped(_ text: String, attributes: [NSAttributedString.Key: Any]) -> String {
        guard !text.isEmpty else { return text }

        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "`", with: "\\`")

        if let link = attributes[.link] as? URL {
            return "[\(escaped)](\(link.absoluteString))"
        }

        var wrapped = escaped
        if isInlineCode(in: attributes) {
            wrapped = "`\(wrapped)`"
        }

        let blockStyle = blockStyle(from: attributes)
        let canEmitInlineWeight = blockStyle != .codeBlock
        let isBold = canEmitInlineWeight && isBold(in: attributes)
        let isItalic = canEmitInlineWeight && isItalic(in: attributes)

        if isBold && isItalic {
            wrapped = "***\(wrapped)***"
        } else if isBold {
            wrapped = "**\(wrapped)**"
        } else if isItalic {
            wrapped = "*\(wrapped)*"
        }

        return wrapped
    }

    private static func attributedParagraph(for text: String, style: FlintBlockStyle) -> NSMutableAttributedString {
        let attributed = NSMutableAttributedString(string: text, attributes: paragraphAttributes(for: style))
        if style != .codeBlock {
            applyInlineMarkdown(to: attributed)
        }
        reapplyFonts(in: attributed, range: NSRange(location: 0, length: attributed.length))
        return attributed
    }

    private static func applyInlineMarkdown(to attributed: NSMutableAttributedString) {
        let source = attributed.string
        guard !source.isEmpty else { return }

        let baseAttributes = attributed.attributes(at: 0, effectiveRange: nil)
        let blockStyle = blockStyle(from: baseAttributes)
        let nsSource = source as NSString
        let result = NSMutableAttributedString()
        var location = 0

        while location < nsSource.length {
            let remaining = nsSource.substring(from: location)

            if remaining.hasPrefix("\\"),
               location + 1 < nsSource.length {
                let escapedCharacter = nsSource.substring(with: NSRange(location: location + 1, length: 1))
                if isEscapableMarkdownCharacter(escapedCharacter) {
                    result.append(NSAttributedString(
                        string: escapedCharacter,
                        attributes: baseAttributes
                    ))
                    location += 2
                    continue
                }
            }

            if remaining.hasPrefix("["),
               let labelClose = range(of: "](", in: nsSource, from: location),
               let urlClose = range(of: ")", in: nsSource, from: NSMaxRange(labelClose)) {
                let labelRange = NSRange(location: location + 1, length: labelClose.location - location - 1)
                let urlRange = NSRange(location: NSMaxRange(labelClose), length: urlClose.location - NSMaxRange(labelClose))
                if labelRange.length >= 0, urlRange.length >= 0 {
                    let label = unescapedMarkdownText(nsSource.substring(with: labelRange))
                    let urlString = nsSource.substring(with: urlRange)
                    if let url = URL(string: urlString) {
                        result.append(NSAttributedString(
                            string: label,
                            attributes: mergeParagraphAttributes(from: baseAttributes, additional: [
                                .link: url,
                                .font: inlineFont(blockStyle: blockStyle, bold: false, italic: false)
                            ])
                        ))
                        location = NSMaxRange(urlClose)
                        continue
                    }
                }
            }

            if remaining.hasPrefix("***"),
               let close = range(of: "***", in: nsSource, from: location + 3) {
                let contentRange = NSRange(location: location + 3, length: close.location - location - 3)
                result.append(NSAttributedString(
                    string: unescapedMarkdownText(nsSource.substring(with: contentRange)),
                    attributes: mergeParagraphAttributes(from: baseAttributes, additional: [
                        .flintBold: true,
                        .flintItalic: true,
                        .font: inlineFont(blockStyle: blockStyle, bold: true, italic: true)
                    ])
                ))
                location = NSMaxRange(close)
                continue
            }

            if remaining.hasPrefix("**"),
               let close = range(of: "**", in: nsSource, from: location + 2) {
                let contentRange = NSRange(location: location + 2, length: close.location - location - 2)
                result.append(NSAttributedString(
                    string: unescapedMarkdownText(nsSource.substring(with: contentRange)),
                    attributes: mergeParagraphAttributes(from: baseAttributes, additional: [
                        .flintBold: true,
                        .font: inlineFont(blockStyle: blockStyle, bold: true, italic: false)
                    ])
                ))
                location = NSMaxRange(close)
                continue
            }

            if remaining.hasPrefix("*"),
               let close = range(of: "*", in: nsSource, from: location + 1) {
                let contentRange = NSRange(location: location + 1, length: close.location - location - 1)
                result.append(NSAttributedString(
                    string: unescapedMarkdownText(nsSource.substring(with: contentRange)),
                    attributes: mergeParagraphAttributes(from: baseAttributes, additional: [
                        .flintItalic: true,
                        .font: inlineFont(blockStyle: blockStyle, bold: false, italic: true)
                    ])
                ))
                location = NSMaxRange(close)
                continue
            }

            if remaining.hasPrefix("`"),
               let close = range(of: "`", in: nsSource, from: location + 1) {
                let contentRange = NSRange(location: location + 1, length: close.location - location - 1)
                result.append(NSAttributedString(
                    string: unescapedMarkdownText(nsSource.substring(with: contentRange)),
                    attributes: mergeParagraphAttributes(from: baseAttributes, additional: [
                        .flintInlineCode: true,
                        .font: inlineCodeFont(blockStyle: blockStyle)
                    ])
                ))
                location = NSMaxRange(close)
                continue
            }

            result.append(NSAttributedString(
                string: nsSource.substring(with: NSRange(location: location, length: 1)),
                attributes: baseAttributes
            ))
            location += 1
        }

        attributed.setAttributedString(result)
    }

    private static func range(of needle: String, in source: NSString, from location: Int) -> NSRange? {
        guard location < source.length else { return nil }
        let range = source.range(of: needle, options: [], range: NSRange(location: location, length: source.length - location))
        return range.location == NSNotFound ? nil : range
    }

    private static func mergeParagraphAttributes(from existing: [NSAttributedString.Key: Any], additional: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var merged = existing
        for (key, value) in additional {
            merged[key] = value
        }
        return merged
    }

    private static func isEscapableMarkdownCharacter(_ string: String) -> Bool {
        guard let character = string.first, string.count == 1 else { return false }
        return escapableMarkdownCharacters.contains(character)
    }

    private static func unescapedMarkdownText(_ text: String) -> String {
        var output = ""
        var isEscaping = false

        for character in text {
            if isEscaping {
                if escapableMarkdownCharacters.contains(character) {
                    output.append(character)
                } else {
                    output.append("\\")
                    output.append(character)
                }
                isEscaping = false
                continue
            }

            if character == "\\" {
                isEscaping = true
            } else {
                output.append(character)
            }
        }

        if isEscaping {
            output.append("\\")
        }

        return output
    }

    private static func paragraphLocation(for paragraphIndex: Int, paragraphs: [String]) -> Int {
        guard paragraphIndex > 0 else { return 0 }
        return paragraphs[..<paragraphIndex].reduce(0) { $0 + $1.utf16.count + 1 }
    }

    private static func safeAttributes(at location: Int, in attributedString: NSAttributedString) -> [NSAttributedString.Key: Any] {
        guard attributedString.length > 0 else {
            return paragraphAttributes(for: .body)
        }

        let safeLocation = max(0, min(location, attributedString.length - 1))
        return attributedString.attributes(at: safeLocation, effectiveRange: nil)
    }

    private static func headingLevel(for line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1...3).contains(hashes), trimmed.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func headingStyle(for level: Int) -> FlintBlockStyle {
        switch level {
        case 1:
            return .heading1
        case 2:
            return .heading2
        default:
            return .heading3
        }
    }

    private static func bulletContent(for line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") else { return nil }
        return String(trimmed.dropFirst(2))
    }

    private static func numberedListContent(for line: String) -> (number: Int, content: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let number = Int(parts[0]), parts[1].first == " " else { return nil }
        return (number, String(parts[1].dropFirst()))
    }

    private static func replacementText(for content: String, style: FlintBlockStyle, numberedIndex: Int) -> String {
        switch style {
        case .bulletList:
            return bulletPrefix + content
        case .numberedList:
            return "\(numberedIndex).\t" + content
        default:
            return content
        }
    }

    private static func normalizeNumberedListMarkers(in attributedString: NSMutableAttributedString) {
        let nsString = attributedString.string as NSString
        var cursor = 0
        var currentNumber = 1

        while cursor < attributedString.length {
            let paragraphRange = nsString.paragraphRange(for: NSRange(location: cursor, length: 0))
            let style = blockStyle(at: paragraphRange.location, in: attributedString)
            let paragraphText = nsString.substring(with: NSRange(location: paragraphRange.location, length: max(0, paragraphRange.length - (paragraphRange.location + paragraphRange.length <= nsString.length && nsString.substring(with: NSRange(location: paragraphRange.location + paragraphRange.length - 1, length: 1)) == "\n" ? 1 : 0))))

            if style == .numberedList {
                let prefix = visiblePrefix(for: style, paragraphText: paragraphText)
                let desiredPrefix = "\(currentNumber).\t"
                if prefix != desiredPrefix, paragraphText.hasPrefix(prefix) {
                    let content = visibleContent(for: paragraphText, style: style)
                    let replacement = NSMutableAttributedString(string: desiredPrefix + content, attributes: paragraphAttributes(for: style))
                    let contentRange = NSRange(location: desiredPrefix.utf16.count, length: content.utf16.count)
                    if contentRange.length > 0 {
                        let sourceStart = paragraphRange.location + min(prefix.utf16.count, paragraphText.utf16.count)
                        let sourceRange = NSRange(location: sourceStart, length: min(content.utf16.count, max(0, attributedString.length - sourceStart)))
                        if sourceRange.length > 0 {
                            attributedString.enumerateAttributes(in: sourceRange, options: []) { attributes, range, _ in
                                let mappedRange = NSRange(location: contentRange.location + range.location - sourceRange.location, length: range.length)
                                replacement.addAttributes(attributes, range: mappedRange)
                            }
                        }
                    }
                    attributedString.replaceCharacters(in: NSRange(location: paragraphRange.location, length: paragraphText.utf16.count), with: replacement)
                }
                currentNumber += 1
            } else {
                currentNumber = 1
            }

            cursor = NSMaxRange(nsString.paragraphRange(for: NSRange(location: cursor, length: 0)))
        }
    }

    private static func reapplyFonts(in attributedString: NSMutableAttributedString, range: NSRange) {
        guard range.length > 0 else { return }

        attributedString.enumerateAttributes(in: range, options: []) { attributes, currentRange, _ in
            let blockStyle = blockStyle(from: attributes)
            let isBold = isBold(in: attributes)
            let isItalic = isItalic(in: attributes)
            let isCode = isInlineCode(in: attributes) || blockStyle == .codeBlock

            var updated = attributes
            updated[.font] = isCode ? inlineCodeFont(blockStyle: blockStyle) : inlineFont(blockStyle: blockStyle, bold: isBold, italic: isItalic)
            updated[.foregroundColor] = color(for: blockStyle, isCode: isCode)
            attributedString.setAttributes(updated, range: currentRange)
        }
    }

    static func isBold(in attributes: [NSAttributedString.Key: Any]) -> Bool {
        (attributes[.flintBold] as? Bool) ?? false
    }

    static func isItalic(in attributes: [NSAttributedString.Key: Any]) -> Bool {
        (attributes[.flintItalic] as? Bool) ?? false
    }

    static func isInlineCode(in attributes: [NSAttributedString.Key: Any]) -> Bool {
        (attributes[.flintInlineCode] as? Bool) ?? false
    }

    static func font(for attributes: [NSAttributedString.Key: Any]) -> UIFont {
        let blockStyle = blockStyle(from: attributes)
        let isCode = isInlineCode(in: attributes) || blockStyle == .codeBlock
        if isCode {
            return inlineCodeFont(blockStyle: blockStyle)
        }

        return inlineFont(blockStyle: blockStyle, bold: isBold(in: attributes), italic: isItalic(in: attributes))
    }

    private static func paragraphAttributes(for style: FlintBlockStyle) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 14
        paragraph.paragraphSpacingBefore = style == .heading1 ? 6 : 0

        switch style {
        case .heading1:
            paragraph.paragraphSpacing = 18
        case .heading2:
            paragraph.paragraphSpacing = 16
            paragraph.paragraphSpacingBefore = 6
        case .heading3:
            paragraph.paragraphSpacing = 14
            paragraph.paragraphSpacingBefore = 4
        case .bulletList, .numberedList:
            paragraph.firstLineHeadIndent = 0
            paragraph.headIndent = 22
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 22)]
            paragraph.defaultTabInterval = 22
        case .quote:
            paragraph.firstLineHeadIndent = 18
            paragraph.headIndent = 18
        case .codeBlock:
            paragraph.firstLineHeadIndent = 16
            paragraph.headIndent = 16
            paragraph.paragraphSpacing = 10
        case .body:
            break
        }

        return [
            .paragraphStyle: paragraph,
            .font: inlineFont(blockStyle: style, bold: false, italic: false),
            .foregroundColor: color(for: style, isCode: style == .codeBlock),
            .flintBlockStyle: style.rawValue
        ]
    }

    private static func inlineFont(blockStyle: FlintBlockStyle = .body, bold: Bool, italic: Bool) -> UIFont {
        let base: UIFont

        switch blockStyle {
        case .heading1:
            base = serifFont(size: 34, weight: .semibold)
        case .heading2:
            base = serifFont(size: 28, weight: .semibold)
        case .heading3:
            base = serifFont(size: 22, weight: .semibold)
        case .codeBlock:
            base = UIFont.monospacedSystemFont(ofSize: 17, weight: .regular)
        default:
            base = UIFont.systemFont(ofSize: 19, weight: .regular)
        }

        var traits = base.fontDescriptor.symbolicTraits
        if bold {
            traits.insert(.traitBold)
        }
        if italic {
            traits.insert(.traitItalic)
        }

        if let descriptor = base.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: descriptor, size: base.pointSize)
        }

        return base
    }

    private static func inlineCodeFont(blockStyle: FlintBlockStyle = .body) -> UIFont {
        let size: CGFloat = blockStyle == .heading1 ? 28 : blockStyle == .heading2 ? 22 : 17
        return UIFont.monospacedSystemFont(ofSize: size, weight: .medium)
    }

    private static func serifFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }

    private static func color(for style: FlintBlockStyle, isCode: Bool) -> UIColor {
        if isCode {
            return UIColor.label
        }

        switch style {
        case .quote:
            return UIColor.secondaryLabel
        default:
            return UIColor.label
        }
    }

    private static func markdownImageReference(for line: String) -> (markdownSource: String, altText: String, sourcePath: String)? {
        guard let match = line.wholeMatch(of: /^\!\[(.*)\]\((.+)\)$/) else {
            return nil
        }

        let altText = String(match.output.1)
        let sourcePath = String(match.output.2).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourcePath.isEmpty else { return nil }
        return (markdownSource: line, altText: altText, sourcePath: sourcePath)
    }

    private static func resolvedImageURL(for sourcePath: String, noteURL: URL?, vaultURL: URL?) -> URL? {
        guard let noteURL, let vaultURL else { return nil }
        return VaultFileService.resolveImageURL(markdownPath: sourcePath, noteURL: noteURL, vaultURL: vaultURL)
    }

    private static func attributedImageBlock(markdownSource: String, altText: String, assetURL: URL?) -> NSAttributedString {
        let attachment = FlintMarkdownImageAttachment(markdownSource: markdownSource, assetURL: assetURL, altText: altText)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = altText.isEmpty ? 18 : 8
        paragraph.paragraphSpacingBefore = 6
        paragraph.lineSpacing = 4

        let imageAttributes: [NSAttributedString.Key: Any] = [
            .attachment: attachment,
            .paragraphStyle: paragraph,
            .flintBlockStyle: FlintBlockStyle.body.rawValue,
            .flintImageMarkdownSource: markdownSource,
            .flintImageAltText: altText
        ]

        let result = NSMutableAttributedString(
            string: String(Character(UnicodeScalar(NSTextAttachment.character)!)),
            attributes: imageAttributes
        )
        if let assetURL {
            result.addAttribute(NSAttributedString.Key.flintImageAssetURL, value: assetURL, range: NSRange(location: 0, length: result.length))
        }

        if !altText.isEmpty {
            let captionParagraph = NSMutableParagraphStyle()
            captionParagraph.alignment = .center
            captionParagraph.paragraphSpacing = 18
            captionParagraph.lineSpacing = 3

            let captionAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: captionParagraph,
                .flintBlockStyle: FlintBlockStyle.body.rawValue,
                .flintSyntheticImageCaption: true
            ]
            result.append(NSAttributedString(string: "\n" + altText, attributes: captionAttributes))
        }

        return result
    }
}

