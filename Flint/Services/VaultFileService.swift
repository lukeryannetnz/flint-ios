import Foundation

enum VaultError: LocalizedError, Equatable {
    case emptyName
    case invalidName(String)
    case itemAlreadyExists(String)
    case inaccessibleVault
    case noteMissing

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Please provide a name."
        case let .invalidName(name):
            return "\"\(name)\" contains unsupported characters."
        case let .itemAlreadyExists(name):
            return "\"\(name)\" already exists."
        case .inaccessibleVault:
            return "Flint could not access that vault."
        case .noteMissing:
            return "The selected note could not be found."
        }
    }
}

protocol VaultFileServing {
    func createVault(named name: String, in parentURL: URL) throws -> URL
    func listMarkdownNotes(in vaultURL: URL) throws -> [NoteItem]
    func createNote(named name: String, in vaultURL: URL) throws -> URL
    func readNote(at url: URL) throws -> String
    func saveNote(_ text: String, at url: URL) throws
}

final class VaultFileService: VaultFileServing {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func createVault(named name: String, in parentURL: URL) throws -> URL {
        let vaultName = try validatedDisplayName(name)

        return try coordinatedWrite(at: parentURL) { coordinatedParentURL in
            let vaultURL = coordinatedParentURL.appendingPathComponent(vaultName, isDirectory: true)

            guard !fileManager.fileExists(atPath: vaultURL.path) else {
                throw VaultError.itemAlreadyExists(vaultName)
            }

            try fileManager.createDirectory(at: vaultURL, withIntermediateDirectories: false)
            return vaultURL
        }
    }

    func listMarkdownNotes(in vaultURL: URL) throws -> [NoteItem] {
        try coordinatedRead(at: vaultURL) { coordinatedVaultURL in
            guard fileManager.fileExists(atPath: coordinatedVaultURL.path) else {
                throw VaultError.inaccessibleVault
            }

            let enumerator = fileManager.enumerator(
                at: coordinatedVaultURL,
                includingPropertiesForKeys: [.isRegularFileKey, .creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            let notes = (enumerator?.compactMap { $0 as? URL } ?? [])
                .filter { url in
                    let ext = url.pathExtension.lowercased()
                    return ext == "md" || ext == "markdown"
                }
                .map { url in
                    let relativePath = url.path.replacingOccurrences(
                        of: coordinatedVaultURL.path + "/",
                        with: ""
                    )
                    let folderURL = url.deletingLastPathComponent()
                    let relativeFolderPath = folderURL.path.replacingOccurrences(
                        of: coordinatedVaultURL.path,
                        with: ""
                    )
                    let normalizedFolderPath = relativeFolderPath
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                    let previewText = (try? makePreviewText(for: url)) ?? ""

                    return NoteItem(
                        url: url,
                        title: url.deletingPathExtension().lastPathComponent,
                        relativePath: relativePath,
                        folderPath: normalizedFolderPath,
                        folderName: normalizedFolderPath.components(separatedBy: "/").last.flatMap { $0.isEmpty ? nil : $0 } ?? "Vault",
                        previewText: previewText,
                        createdAt: resourceValues?.creationDate ?? .distantPast,
                        lastModifiedAt: resourceValues?.contentModificationDate ?? .distantPast
                    )
                }
                .sorted { (lhs: NoteItem, rhs: NoteItem) in
                    if lhs.lastModifiedAt != rhs.lastModifiedAt {
                        return lhs.lastModifiedAt > rhs.lastModifiedAt
                    }

                    return lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
                }

            return notes
        }
    }

    func createNote(named name: String, in vaultURL: URL) throws -> URL {
        let fileName = try validatedMarkdownFilename(name)

        return try coordinatedWrite(at: vaultURL) { coordinatedVaultURL in
            let noteURL = coordinatedVaultURL.appendingPathComponent(fileName, isDirectory: false)

            guard !fileManager.fileExists(atPath: noteURL.path) else {
                throw VaultError.itemAlreadyExists(fileName)
            }

            let initialContents = "# \(noteURL.deletingPathExtension().lastPathComponent)\n"
            try initialContents.write(to: noteURL, atomically: true, encoding: .utf8)
            return noteURL
        }
    }

    func readNote(at url: URL) throws -> String {
        try coordinatedRead(at: url) { coordinatedURL in
            guard fileManager.fileExists(atPath: coordinatedURL.path) else {
                throw VaultError.noteMissing
            }

            return try String(contentsOf: coordinatedURL, encoding: .utf8)
        }
    }

    func saveNote(_ text: String, at url: URL) throws {
        try coordinatedWrite(at: url) { coordinatedURL in
            guard fileManager.fileExists(atPath: coordinatedURL.path) else {
                throw VaultError.noteMissing
            }

            try text.write(to: coordinatedURL, atomically: true, encoding: .utf8)
        }
    }

    private func validatedDisplayName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw VaultError.emptyName
        }

        guard !trimmed.contains("/") && !trimmed.contains(":") else {
            throw VaultError.invalidName(trimmed)
        }

        return trimmed
    }

    private func validatedMarkdownFilename(_ name: String) throws -> String {
        let trimmed = try validatedDisplayName(name)
        return trimmed.lowercased().hasSuffix(".md") ? trimmed : "\(trimmed).md"
    }

    private func makePreviewText(for url: URL) throws -> String {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let condensed = contents
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return String(condensed.prefix(180))
    }

    private func coordinatedRead<T>(at url: URL, accessor: (URL) throws -> T) throws -> T {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<T, Error>?

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result {
                try accessor(coordinatedURL)
            }
        }

        if let coordinationError {
            throw coordinationError
        }

        guard let result else {
            throw VaultError.inaccessibleVault
        }

        return try result.get()
    }

    private func coordinatedWrite<T>(at url: URL, accessor: (URL) throws -> T) throws -> T {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<T, Error>?

        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { coordinatedURL in
            result = Result {
                try accessor(coordinatedURL)
            }
        }

        if let coordinationError {
            throw coordinationError
        }

        guard let result else {
            throw VaultError.inaccessibleVault
        }

        return try result.get()
    }
}
