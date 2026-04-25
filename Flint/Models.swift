import Foundation
import UIKit

struct Vault: Equatable {
    let name: String
    let url: URL
}

struct NoteItem: Identifiable, Hashable {
    let url: URL
    let title: String
    let relativePath: String
    let folderPath: String
    let folderName: String
    let previewText: String
    let createdAt: Date
    let lastModifiedAt: Date

    var id: URL { url }
}

struct VaultFolder: Identifiable, Hashable {
    let path: String
    let name: String
    let childFolders: [VaultFolder]
    let notes: [NoteItem]

    var id: String { path }
    var breadcrumbComponents: [String] { path.isEmpty ? [] : path.components(separatedBy: "/") }
    var noteCount: Int { notes.count }
    var descendantNoteCount: Int { notes.count + childFolders.reduce(0) { $0 + $1.descendantNoteCount } }

    func folder(at components: ArraySlice<String>) -> VaultFolder? {
        guard let head = components.first else { return self }
        guard let match = childFolders.first(where: { $0.name == head }) else { return nil }
        return match.folder(at: components.dropFirst())
    }

    static func root(vaultName: String, notes: [NoteItem]) -> VaultFolder {
        var root = FolderAccumulator()

        for note in notes {
            root.insert(note: note, components: note.folderComponents[...])
        }

        return root.makeFolder(path: "", name: vaultName)
    }
}

private struct FolderAccumulator {
    var childFolders: [String: FolderAccumulator] = [:]
    var notes: [NoteItem] = []

    mutating func insert(note: NoteItem, components: ArraySlice<String>) {
        guard let head = components.first else {
            notes.append(note)
            return
        }

        var child = childFolders[head] ?? FolderAccumulator()
        child.insert(note: note, components: components.dropFirst())
        childFolders[head] = child
    }

    func makeFolder(path: String, name: String) -> VaultFolder {
        let folders = childFolders
            .map { childName, accumulator in
                let childPath = path.isEmpty ? childName : "\(path)/\(childName)"
                return accumulator.makeFolder(path: childPath, name: childName)
            }
            .sorted { (lhs: VaultFolder, rhs: VaultFolder) in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        let sortedNotes = notes.sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt > $1.createdAt
            }

            return $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }

        return VaultFolder(path: path, name: name, childFolders: folders, notes: sortedNotes)
    }
}

extension NoteItem {
    var folderComponents: [String] {
        guard !folderPath.isEmpty else { return [] }
        return folderPath.components(separatedBy: "/")
    }

    var lastEditedDisplayText: String {
        Self.relativeDateFormatter.localizedString(for: lastModifiedAt, relativeTo: Date())
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

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
}

enum FlintRichTextCodec {
    private static let bulletPrefix = "\u{2022}\t"

    static func attributedString(from markdown: String) -> NSMutableAttributedString {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        let result = NSMutableAttributedString()
        var isInsideCodeFence = false

        for (index, line) in lines.enumerated() {
            let isLast = index == lines.count - 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                isInsideCodeFence.toggle()
                continue
            }

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

            let paragraph = attributedParagraph(for: content, style: style)
            result.append(paragraph)

            if !isLast {
                result.append(NSAttributedString(string: "\n", attributes: paragraphAttributes(for: style)))
            }
        }

        if result.length == 0 {
            result.append(attributedParagraph(for: "", style: .body))
        }

        normalizeNumberedListMarkers(in: result)
        return result
    }

    static func markdown(from attributedString: NSAttributedString) -> String {
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
                markdownLines.append("- " + markdownInline(from: visibleContent(for: rawParagraph, style: style), globalLocation: location, in: attributedString, visiblePrefixLength: visiblePrefix(for: style, paragraphText: rawParagraph).utf16.count))
                numberedIndex = 0
            case .numberedList:
                numberedIndex += 1
                markdownLines.append("\(numberedIndex). " + markdownInline(from: visibleContent(for: rawParagraph, style: style), globalLocation: location, in: attributedString, visiblePrefixLength: visiblePrefix(for: style, paragraphText: rawParagraph).utf16.count))
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
        let text = attributedString.string as NSString
        var cursor = paragraphRange.location
        let end = NSMaxRange(paragraphRange)
        var numberedIndex = 1

        while cursor < end {
            let currentParagraphRange = text.paragraphRange(for: NSRange(location: cursor, length: 0))
            let paragraphText = text.substring(with: currentParagraphRange)
            let content = visibleContent(for: paragraphText.replacingOccurrences(of: "\n", with: ""), style: blockStyle(at: currentParagraphRange.location, in: attributedString))
            let replacement = replacementText(for: content, style: style, numberedIndex: numberedIndex)
            let replacementAttributed = attributedParagraph(for: replacement, style: style)
            let replaceRange = NSRange(location: currentParagraphRange.location, length: currentParagraphRange.length - (paragraphText.hasSuffix("\n") ? 1 : 0))
            attributedString.replaceCharacters(in: replaceRange, with: replacementAttributed)

            let updatedText = attributedString.string as NSString
            let nextRange = updatedText.paragraphRange(for: NSRange(location: currentParagraphRange.location, length: 0))
            cursor = NSMaxRange(nextRange)

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
        applyInlineMarkdown(to: attributed)
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

            if remaining.hasPrefix("["),
               let labelClose = range(of: "](", in: nsSource, from: location),
               let urlClose = range(of: ")", in: nsSource, from: NSMaxRange(labelClose)) {
                let labelRange = NSRange(location: location + 1, length: labelClose.location - location - 1)
                let urlRange = NSRange(location: NSMaxRange(labelClose), length: urlClose.location - NSMaxRange(labelClose))
                if labelRange.length >= 0, urlRange.length >= 0 {
                    let label = nsSource.substring(with: labelRange)
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
                    string: nsSource.substring(with: contentRange),
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
                    string: nsSource.substring(with: contentRange),
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
                    string: nsSource.substring(with: contentRange),
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
                    string: nsSource.substring(with: contentRange),
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
}

struct MarkdownDocument: Hashable {
    let markdown: String
    let html: String

    init(noteTitle: String, markdown: String) {
        let sanitizedLines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let lines = MarkdownDocument.removingDuplicatedTitle(from: sanitizedLines, noteTitle: noteTitle)
        let normalizedMarkdown = lines.joined(separator: "\n")
        self.markdown = normalizedMarkdown
        html = MarkdownHTMLCache.shared.html(for: normalizedMarkdown)
    }

    private static func removingDuplicatedTitle(from lines: [String], noteTitle: String) -> [String] {
        guard let firstNonEmptyIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return lines
        }

        let firstLine = lines[firstNonEmptyIndex].trimmingCharacters(in: .whitespaces)
        let normalizedTitle = noteTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if firstLine.hasPrefix("# ") {
            let heading = String(firstLine.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if heading == normalizedTitle {
                var updated = lines
                updated.remove(at: firstNonEmptyIndex)
                while let first = updated.first, first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    updated.removeFirst()
                }
                return updated
            }
        }

        return lines
    }
}

final class MarkdownHTMLCache {
    static let shared = MarkdownHTMLCache()

    private let cache = NSCache<NSString, NSString>()

    func html(for markdown: String) -> String {
        let key = markdown as NSString
        if let cached = cache.object(forKey: key) {
            return cached as String
        }

        let renderedHTML = MarkdownHTMLRenderer.render(markdown: markdown)
        let wrappedHTML = MarkdownHTMLRenderer.wrapDocument(body: renderedHTML)
        cache.setObject(wrappedHTML as NSString, forKey: key)
        return wrappedHTML
    }
}

private enum MarkdownHTMLRenderer {
    static func render(markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var index = 0
        var blocks: [String] = []

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let fence = fencedCodeDelimiter(in: trimmed) {
                blocks.append(parseCodeBlock(lines: lines, index: &index, fence: fence))
                continue
            }

            if let headingHTML = parseHeading(trimmed) {
                blocks.append(headingHTML)
                index += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                blocks.append("<hr />")
                index += 1
                continue
            }

            if isTableHeader(lines: lines, index: index) {
                blocks.append(parseTable(lines: lines, index: &index))
                continue
            }

            if isListLine(trimmed) {
                blocks.append(parseList(lines: lines, index: &index))
                continue
            }

            if trimmed.hasPrefix(">") {
                blocks.append(parseBlockquote(lines: lines, index: &index))
                continue
            }

            blocks.append(parseParagraph(lines: lines, index: &index))
        }

        return blocks.joined(separator: "\n")
    }

    static func wrapDocument(body: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
        <style>
        :root {
          color-scheme: light dark;
          --bg: transparent;
          --secondary: color-mix(in srgb, currentColor 62%, transparent);
          --border: color-mix(in srgb, currentColor 14%, transparent);
          --surface: color-mix(in srgb, currentColor 6%, transparent);
          --surface-strong: color-mix(in srgb, currentColor 10%, transparent);
          --link: #0a84ff;
        }
        html, body {
          margin: 0;
          padding: 0;
          background: var(--bg);
          color: CanvasText;
          font: -apple-system-body;
          line-height: 1.55;
          overflow-x: hidden;
        }
        body {
          padding: 0 0 24px 0;
          word-wrap: break-word;
        }
        h1, h2, h3, h4, h5, h6 {
          line-height: 1.18;
          margin: 1.25em 0 0.45em;
        }
        h1 { font: 700 2rem ui-serif, Georgia, serif; }
        h2 { font: 700 1.6rem ui-serif, Georgia, serif; }
        h3 { font: 700 1.25rem ui-serif, Georgia, serif; }
        p, ul, ol, blockquote, table, pre, figure {
          margin: 0 0 1rem;
        }
        ul, ol {
          padding-left: 1.4rem;
        }
        li + li {
          margin-top: 0.42rem;
        }
        a {
          color: var(--link);
          text-decoration: none;
        }
        code {
          font: 0.92rem ui-monospace, SFMono-Regular, Menlo, monospace;
          background: var(--surface);
          border-radius: 8px;
          padding: 0.12rem 0.35rem;
        }
        pre {
          background: var(--surface);
          border-radius: 18px;
          padding: 1rem;
          overflow-x: auto;
        }
        pre code {
          background: transparent;
          padding: 0;
          border-radius: 0;
        }
        blockquote {
          border-left: 3px solid var(--border);
          padding-left: 0.9rem;
          color: var(--secondary);
        }
        table {
          width: 100%;
          border-collapse: collapse;
          border-spacing: 0;
          display: block;
          overflow-x: auto;
          background: var(--surface);
          border-radius: 16px;
        }
        thead {
          background: var(--surface-strong);
        }
        th, td {
          padding: 0.8rem 0.9rem;
          border-bottom: 1px solid var(--border);
          text-align: left;
          vertical-align: top;
        }
        tr:last-child td {
          border-bottom: none;
        }
        .md-image {
          display: inline-block;
          max-width: min(320px, 100%);
        }
        .md-video-thumb {
          position: relative;
          display: inline-block;
          max-width: min(320px, 100%);
          text-decoration: none;
          color: inherit;
        }
        .md-image img {
          width: 100%;
          max-width: min(320px, 100%);
          max-height: 220px;
          object-fit: cover;
          display: block;
          border-radius: 18px;
          background: var(--surface);
          border: 1px solid var(--border);
        }
        .md-video-thumb .md-play-badge {
          position: absolute;
          left: 50%;
          top: 50%;
          transform: translate(-50%, -50%);
          width: 54px;
          height: 38px;
          border-radius: 12px;
          background: rgba(0, 0, 0, 0.72);
          display: flex;
          align-items: center;
          justify-content: center;
          color: white;
          font-size: 20px;
          line-height: 1;
          pointer-events: none;
          box-shadow: 0 8px 24px rgba(0, 0, 0, 0.2);
        }
        .md-image figcaption {
          margin-top: 0.45rem;
          font-size: 0.82rem;
          color: var(--secondary);
        }
        .task-list {
          list-style: none;
          padding-left: 0;
        }
        .task-list li {
          display: flex;
          align-items: flex-start;
          gap: 0.65rem;
        }
        .task-list input {
          margin-top: 0.22rem;
        }
        hr {
          border: 0;
          border-top: 1px solid var(--border);
          margin: 1.4rem 0;
        }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private static func parseHeading(_ line: String) -> String? {
        let hashes = line.prefix { $0 == "#" }
        let level = hashes.count
        guard (1...6).contains(level), line.dropFirst(level).first == " " else {
            return nil
        }

        let text = String(line.dropFirst(level + 1))
        return "<h\(level)>\(renderInline(text))</h\(level)>"
    }

    private static func fencedCodeDelimiter(in line: String) -> String? {
        if line.hasPrefix("```") { return "```" }
        if line.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    private static func parseCodeBlock(lines: [String], index: inout Int, fence: String) -> String {
        let openingLine = lines[index].trimmingCharacters(in: .whitespaces)
        let language = openingLine.dropFirst(fence.count).trimmingCharacters(in: .whitespacesAndNewlines)
        index += 1

        var codeLines: [String] = []
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces) == fence {
                index += 1
                break
            }

            codeLines.append(line)
            index += 1
        }

        let languageClass = language.isEmpty ? "" : " class=\"language-\(escapeAttribute(language))\""
        return "<pre><code\(languageClass)>\(escapeHTML(codeLines.joined(separator: "\n")))</code></pre>"
    }

    private static func parseParagraph(lines: [String], index: inout Int) -> String {
        var paragraphLines: [String] = []

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty ||
                fencedCodeDelimiter(in: trimmed) != nil ||
                parseHeading(trimmed) != nil ||
                isHorizontalRule(trimmed) ||
                isTableHeader(lines: lines, index: index) ||
                isListLine(trimmed) ||
                trimmed.hasPrefix(">") {
                break
            }

            paragraphLines.append(trimmed)
            index += 1
        }

        return "<p>\(renderInline(paragraphLines.joined(separator: " ")))</p>"
    }

    private static func parseBlockquote(lines: [String], index: inout Int) -> String {
        var quoteLines: [String] = []

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }
            let content = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            quoteLines.append(content)
            index += 1
        }

        let innerHTML = render(markdown: quoteLines.joined(separator: "\n"))
        return "<blockquote>\(innerHTML)</blockquote>"
    }

    private static func parseList(lines: [String], index: inout Int) -> String {
        let firstTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
        let ordered = isOrderedListLine(firstTrimmed)
        let taskList = isChecklistLine(firstTrimmed)
        var items: [String] = []

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard isListLine(trimmed) else { break }
            guard isOrderedListLine(trimmed) == ordered || (!ordered && !isOrderedListLine(trimmed)) else { break }

            if taskList, isChecklistLine(trimmed) {
                let isChecked = trimmed.lowercased().hasPrefix("- [x]") || trimmed.lowercased().hasPrefix("* [x]")
                let itemText = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                let checkbox = "<input type=\"checkbox\" disabled\(isChecked ? " checked" : "")>"
                items.append("<li>\(checkbox)<span>\(renderInline(itemText))</span></li>")
                index += 1
                continue
            }

            if ordered {
                let content = trimmed.replacingOccurrences(
                    of: #"^\d+\.\s+"#,
                    with: "",
                    options: .regularExpression
                )
                items.append("<li>\(renderInline(content))</li>")
            } else {
                let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                items.append("<li>\(renderInline(content))</li>")
            }
            index += 1
        }

        if taskList {
            return "<ul class=\"task-list\">\(items.joined())</ul>"
        }

        let tag = ordered ? "ol" : "ul"
        return "<\(tag)>\(items.joined())</\(tag)>"
    }

    private static func parseTable(lines: [String], index: inout Int) -> String {
        let headers = splitTableRow(lines[index])
        index += 2

        var rows: [[String]] = []
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.contains("|") else { break }
            rows.append(splitTableRow(lines[index]))
            index += 1
        }

        let headHTML = headers.map { "<th>\(renderInline($0))</th>" }.joined()
        let rowHTML = rows.map { row in
            "<tr>\(row.map { "<td>\(renderInline($0))</td>" }.joined())</tr>"
        }.joined()

        return "<table><thead><tr>\(headHTML)</tr></thead><tbody>\(rowHTML)</tbody></table>"
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        line.range(of: #"^([-*_])(\s*\1){2,}\s*$"#, options: .regularExpression) != nil
    }

    private static func isListLine(_ line: String) -> Bool {
        isChecklistLine(line) || isUnorderedListLine(line) || isOrderedListLine(line)
    }

    private static func isChecklistLine(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        return lowercased.hasPrefix("- [ ] ") || lowercased.hasPrefix("- [x] ") ||
            lowercased.hasPrefix("* [ ] ") || lowercased.hasPrefix("* [x] ")
    }

    private static func isUnorderedListLine(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ")
    }

    private static func isOrderedListLine(_ line: String) -> Bool {
        line.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil
    }

    private static func isTableHeader(lines: [String], index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        let header = lines[index].trimmingCharacters(in: .whitespaces)
        let separator = lines[index + 1].trimmingCharacters(in: .whitespaces)
        guard header.contains("|") else { return false }
        return separator.replacingOccurrences(of: "|", with: "").allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
    }

    private static func splitTableRow(_ line: String) -> [String] {
        line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func renderInline(_ text: String) -> String {
        var placeholders: [String: String] = [:]
        var placeholderIndex = 0
        var working = text

        func replace(_ pattern: String, transform: ([String]) -> String) {
            let regex = try? NSRegularExpression(pattern: pattern, options: [])
            guard let regex else { return }

            while let match = regex.firstMatch(in: working, range: NSRange(working.startIndex..., in: working)) {
                let parts = (0..<match.numberOfRanges).compactMap { groupIndex -> String? in
                    guard let range = Range(match.range(at: groupIndex), in: working) else { return nil }
                    return String(working[range])
                }
                let placeholder = "@@MD\(placeholderIndex)@@"
                placeholderIndex += 1
                placeholders[placeholder] = transform(parts)
                if let range = Range(match.range(at: 0), in: working) {
                    working.replaceSubrange(range, with: placeholder)
                }
            }
        }

        replace(#"!\[([^\]]*)\]\(([^)]+)\)"#) { parts in
            let alt = parts.count > 1 ? parts[1] : ""
            let source = parts.count > 2 ? parts[2] : ""
            if let video = youtubeThumbnailMarkup(alt: alt, source: source) {
                return video
            }
            let caption = alt.isEmpty ? "" : "<figcaption>\(escapeHTML(alt))</figcaption>"
            return "<figure class=\"md-image\"><img src=\"\(escapeAttribute(source))\" alt=\"\(escapeAttribute(alt))\" loading=\"lazy\">\(caption)</figure>"
        }

        replace(#"\[([^\]]+)\]\(([^)]+)\)"#) { parts in
            let label = parts.count > 1 ? renderInline(parts[1]) : ""
            let target = parts.count > 2 ? parts[2] : ""
            return "<a href=\"\(escapeAttribute(target))\">\(label)</a>"
        }

        replace(#"`([^`]+)`"#) { parts in
            let code = parts.count > 1 ? parts[1] : ""
            return "<code>\(escapeHTML(code))</code>"
        }

        working = escapeHTML(working)
        working = working.replacingOccurrences(of: #"(?s)\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        working = working.replacingOccurrences(of: #"(?s)__(.+?)__"#, with: "<strong>$1</strong>", options: .regularExpression)
        working = working.replacingOccurrences(of: #"(?s)\*(.+?)\*"#, with: "<em>$1</em>", options: .regularExpression)
        working = working.replacingOccurrences(of: #"(?s)_(.+?)_"#, with: "<em>$1</em>", options: .regularExpression)
        working = working.replacingOccurrences(of: #"(?s)~~(.+?)~~"#, with: "<del>$1</del>", options: .regularExpression)

        for placeholder in placeholders.keys.sorted(by: { $0.count > $1.count }) {
            if let replacement = placeholders[placeholder] {
                working = working.replacingOccurrences(of: escapeHTML(placeholder), with: replacement)
            }
        }

        return working
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func escapeAttribute(_ text: String) -> String {
        escapeHTML(text).replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func youtubeThumbnailMarkup(alt: String, source: String) -> String? {
        guard let url = URL(string: source),
              let videoID = youtubeVideoID(from: url) else {
            return nil
        }

        let watchURL = "https://www.youtube.com/watch?v=\(videoID)"
        let thumbnailURL = "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg"
        let caption = alt.isEmpty ? "YouTube video" : alt

        return """
        <figure class="md-image"><a class="md-video-thumb" href="\(watchURL)"><img src="\(thumbnailURL)" alt="\(escapeAttribute(caption))" loading="lazy"><span class="md-play-badge">▶</span></a><figcaption>\(escapeHTML(caption))</figcaption></figure>
        """
    }

    private static func youtubeVideoID(from url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }

        if host.contains("youtube.com") {
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            if let embedIndex = pathComponents.firstIndex(of: "embed"), embedIndex + 1 < pathComponents.count {
                return normalizedYouTubeVideoID(pathComponents[embedIndex + 1])
            }

            if url.path == "/watch",
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let value = components.queryItems?.first(where: { $0.name == "v" })?.value {
                return normalizedYouTubeVideoID(value)
            }
        }

        if host == "youtu.be" {
            return normalizedYouTubeVideoID(url.lastPathComponent)
        }

        return nil
    }

    private static func normalizedYouTubeVideoID(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cleaned = trimmed.replacingOccurrences(of: #"[^A-Za-z0-9_-]"#, with: "", options: .regularExpression)
        return cleaned.isEmpty ? nil : cleaned
    }
}
