import Foundation

struct Vault: Equatable {
    let name: String
    let url: URL
}

struct InsertedNoteImage: Equatable {
    let markdownSource: String
    let assetURL: URL
    let altText: String
}

struct NoteImageViewerItem: Identifiable, Equatable {
    let assetURL: URL
    let altText: String

    var id: String { assetURL.path + "::" + altText }
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
