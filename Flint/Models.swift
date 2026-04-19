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
    let previewText: String
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
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
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

struct MarkdownDocument: Hashable {
    let blocks: [MarkdownBlock]

    init(noteTitle: String, markdown: String) {
        let sanitizedLines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let lines = MarkdownDocument.removingDuplicatedTitle(from: sanitizedLines, noteTitle: noteTitle)
        var parser = MarkdownDocumentParser(lines: lines)
        blocks = parser.parse()
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

enum MarkdownBlock: Hashable, Identifiable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bulletList([String])
    case checklist([ChecklistItem])
    case quote(String)
    case codeBlock(language: String?, code: String)
    case table(headers: [String], rows: [[String]])
    case image(alt: String, source: String)

    var id: String {
        switch self {
        case let .heading(level, text):
            return "heading-\(level)-\(text)"
        case let .paragraph(text):
            return "paragraph-\(text)"
        case let .bulletList(items):
            return "bullet-\(items.joined(separator: "|"))"
        case let .checklist(items):
            return "check-\(items.map(\.text).joined(separator: "|"))"
        case let .quote(text):
            return "quote-\(text)"
        case let .codeBlock(language, code):
            return "code-\(language ?? "plain")-\(code)"
        case let .table(headers, rows):
            return "table-\(headers.joined(separator: "|"))-\(rows.flatMap { $0 }.joined(separator: "|"))"
        case let .image(alt, source):
            return "image-\(alt)-\(source)"
        }
    }
}

struct ChecklistItem: Hashable {
    let text: String
    let isChecked: Bool
}

private struct MarkdownDocumentParser {
    private let lines: [String]
    private var index = 0

    init(lines: [String]) {
        self.lines = lines
    }

    mutating func parse() -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []

        while index < lines.count {
            let currentLine = lines[index]
            let trimmed = currentLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                blocks.append(parseCodeBlock())
                continue
            }

            if let heading = parseHeading(from: trimmed) {
                blocks.append(heading)
                index += 1
                continue
            }

            if let image = parseImage(from: trimmed) {
                blocks.append(image)
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                blocks.append(parseQuote())
                continue
            }

            if isChecklistLine(trimmed) {
                blocks.append(parseChecklist())
                continue
            }

            if isBulletLine(trimmed) {
                blocks.append(parseBulletList())
                continue
            }

            if isTableHeader(at: index) {
                blocks.append(parseTable())
                continue
            }

            blocks.append(parseParagraph())
        }

        return blocks
    }

    private func parseHeading(from trimmed: String) -> MarkdownBlock? {
        let hashes = trimmed.prefix { $0 == "#" }
        let level = hashes.count
        guard (1...6).contains(level), trimmed.dropFirst(level).first == " " else {
            return nil
        }

        return .heading(level: level, text: trimmed.dropFirst(level + 1).description)
    }

    private func parseImage(from trimmed: String) -> MarkdownBlock? {
        guard trimmed.hasPrefix("!["),
              let altClose = trimmed.firstIndex(of: "]"),
              let openParen = trimmed.firstIndex(of: "("),
              let closeParen = trimmed.lastIndex(of: ")"),
              altClose < openParen,
              openParen < closeParen else {
            return nil
        }

        let alt = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<altClose])
        let source = String(trimmed[trimmed.index(after: openParen)..<closeParen])
        return .image(alt: alt, source: source)
    }

    private mutating func parseCodeBlock() -> MarkdownBlock {
        let openingLine = lines[index].trimmingCharacters(in: .whitespaces)
        let language = openingLine.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
        index += 1

        var codeLines: [String] = []
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces) == "```" {
                index += 1
                break
            }

            codeLines.append(line)
            index += 1
        }

        return .codeBlock(language: language.isEmpty ? nil : language, code: codeLines.joined(separator: "\n"))
    }

    private mutating func parseQuote() -> MarkdownBlock {
        var parts: [String] = []
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }
            parts.append(trimmed.dropFirst().trimmingCharacters(in: .whitespaces))
            index += 1
        }
        return .quote(parts.joined(separator: " "))
    }

    private mutating func parseChecklist() -> MarkdownBlock {
        var items: [ChecklistItem] = []
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard isChecklistLine(trimmed) else { break }
            let isChecked = trimmed.lowercased().hasPrefix("- [x]") || trimmed.lowercased().hasPrefix("* [x]")
            let text = trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces)
            items.append(ChecklistItem(text: text, isChecked: isChecked))
            index += 1
        }
        return .checklist(items)
    }

    private mutating func parseBulletList() -> MarkdownBlock {
        var items: [String] = []
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard isBulletLine(trimmed), !isChecklistLine(trimmed) else { break }
            items.append(trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces))
            index += 1
        }
        return .bulletList(items)
    }

    private mutating func parseTable() -> MarkdownBlock {
        let headers = splitTableRow(lines[index])
        index += 2

        var rows: [[String]] = []
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("|"), !trimmed.isEmpty else { break }
            rows.append(splitTableRow(lines[index]))
            index += 1
        }

        return .table(headers: headers, rows: rows)
    }

    private mutating func parseParagraph() -> MarkdownBlock {
        var parts: [String] = []

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty ||
                trimmed.hasPrefix("```") ||
                parseHeading(from: trimmed) != nil ||
                parseImage(from: trimmed) != nil ||
                trimmed.hasPrefix(">") ||
                isChecklistLine(trimmed) ||
                isBulletLine(trimmed) ||
                isTableHeader(at: index) {
                break
            }

            parts.append(trimmed)
            index += 1
        }

        return .paragraph(parts.joined(separator: " "))
    }

    private func isChecklistLine(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        return lowercased.hasPrefix("- [ ] ") || lowercased.hasPrefix("- [x] ") || lowercased.hasPrefix("* [ ] ") || lowercased.hasPrefix("* [x] ")
    }

    private func isBulletLine(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ")
    }

    private func isTableHeader(at index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        let header = lines[index].trimmingCharacters(in: .whitespaces)
        let separator = lines[index + 1].trimmingCharacters(in: .whitespaces)
        return header.contains("|") && separator.replacingOccurrences(of: "|", with: "").allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
    }

    private func splitTableRow(_ line: String) -> [String] {
        line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
