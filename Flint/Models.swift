import Foundation

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
    let previewMarkdown: String
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
    var previewAttributedText: AttributedString? {
        guard !previewMarkdown.isEmpty else { return nil }
        return try? AttributedString(
            markdown: previewMarkdown,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
    }

    var previewFallbackText: String {
        guard !previewMarkdown.isEmpty else { return "No preview available yet." }
        return previewMarkdown
            .replacingOccurrences(of: "\\*\\*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "\\*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "`", with: "")
    }

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

struct MarkdownDocument: Hashable {
    let markdown: String
    let html: String

    init(noteTitle: String, markdown: String) {
        let normalizedMarkdown = MarkdownDocument.normalizedMarkdown(noteTitle: noteTitle, markdown: markdown)
        self.markdown = normalizedMarkdown
        html = MarkdownHTMLCache.shared.html(for: normalizedMarkdown)
    }

    static func normalizedMarkdown(noteTitle: String, markdown: String) -> String {
        let sanitizedLines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let lines = removingDuplicatedTitle(from: sanitizedLines, noteTitle: noteTitle)
        return lines.joined(separator: "\n")
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
