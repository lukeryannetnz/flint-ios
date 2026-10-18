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
    var sourceByteCount: Int? = nil

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

    func resolvedPathComponents(for components: [String]) -> [String] {
        folder(at: components[...])?.breadcrumbComponents ?? []
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

// Discovery values contain metadata only. A cursor is consumed serially by the file adapter.
struct NoteDiscoveryBatch {
    let notes: [NoteItem]
    let cursor: NoteDiscoveryCursor?
    var incomplete = false
    var examinedCount = 0
}

enum NoteDiscoveryState: Equatable {
    case idle, loading, complete, incomplete
}

enum NotePreview: Equatable {
    case omitted, pending, unavailable, empty
    case available(String, truncated: Bool)

    var byteCost: Int {
        if case let .available(text, _) = self { return max(1, text.utf8.count) }
        return 1
    }
}

/// Cache and presentation share the same values; no second unbounded copy is retained.
@MainActor
final class NotePreviewCache {
    private struct Entry { let note: NoteItem; let preview: NotePreview; var access: Int }
    private var entries: [URL: Entry] = [:]
    private var access = 0
    private(set) var byteCount = 0
    let capacity: Int
    init(capacity: Int = 4 * 1024 * 1024) { self.capacity = capacity }

    func value(for note: NoteItem) -> NotePreview? {
        guard var entry = entries[note.url] else { return nil }
        guard entry.note.lastModifiedAt == note.lastModifiedAt,
              entry.note.sourceByteCount == note.sourceByteCount else { remove(note.url); return nil }
        access += 1; entry.access = access; entries[note.url] = entry
        return entry.preview
    }
    func insert(_ preview: NotePreview, for note: NoteItem) {
        remove(note.url)
        guard preview.byteCost <= capacity else { return }
        while byteCount + preview.byteCost > capacity || entries.count >= 512 {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key else { break }
            remove(oldest)
        }
        access += 1; entries[note.url] = Entry(note: note, preview: preview, access: access)
        byteCount += preview.byteCost
    }
    func remove(_ url: URL) {
        if let entry = entries.removeValue(forKey: url) { byteCount -= entry.preview.byteCost }
    }
    func removeAll() { entries = [:]; byteCount = 0 }
}

extension NoteItem {
    static func mostRecentlyModified(_ lhs: NoteItem, _ rhs: NoteItem) -> Bool {
        if lhs.lastModifiedAt != rhs.lastModifiedAt { return lhs.lastModifiedAt > rhs.lastModifiedAt }
        return lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
    }
}

struct NotePreviewDemand: Hashable {
    let note: NoteItem
    let epoch: UUID
    let version: UUID?
}
