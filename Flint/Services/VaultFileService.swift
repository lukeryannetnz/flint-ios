import Foundation
import UIKit

enum VaultError: LocalizedError, Equatable {
    case emptyName
    case invalidName(String)
    case itemAlreadyExists(String)
    case inaccessibleVault
    case noteMissing
    case noteTooLarge
    case incompleteDiscovery

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
        case .noteTooLarge:
            return "This note exceeds the 8 MiB editing limit. Its file has not been changed."
        case .incompleteDiscovery:
            return "Some notes could not be discovered. Retry discovery to finish loading the vault."
        }
    }
}

protocol VaultFileServing {
    func createVault(named name: String, in parentURL: URL, request: ProviderRequest) async throws -> URL
    func listMarkdownNotes(in vaultURL: URL, request: ProviderRequest) async throws -> [NoteItem]
    func discoverNotes(in vaultURL: URL, cursor: NoteDiscoveryCursor?, request: ProviderRequest) async throws -> NoteDiscoveryBatch
    func readPreview(for note: NoteItem, request: ProviderRequest) async throws -> NotePreview
    func createNote(named name: String, in directoryURL: URL, request: ProviderRequest) async throws -> URL
    func readNote(at url: URL, request: ProviderRequest) async throws -> String
    func saveNote(_ text: String, at url: URL, request: ProviderRequest) async throws
    func importImage(from sourceURL: URL, preferredFilename: String?, into noteURL: URL, vaultURL: URL, request: ProviderRequest) async throws -> InsertedNoteImage
    func importCameraImage(_ image: UIImage, into noteURL: URL, vaultURL: URL, request: ProviderRequest) async throws -> InsertedNoteImage
}

/// Only the file adapter accesses this cursor, inside serial per-vault executor jobs.
final class NoteDiscoveryCursor {
    fileprivate struct Directory {
        let relativePath: String
        var names: [String]?
        var nextIndex = 0
    }
    fileprivate var directories = [Directory(relativePath: "")]
    fileprivate var incomplete = false
}

extension VaultFileServing {
    // Single-batch compatibility for adapters which already supply immutable metadata.
    func discoverNotes(in vaultURL: URL, cursor: NoteDiscoveryCursor?, request: ProviderRequest) async throws -> NoteDiscoveryBatch {
        NoteDiscoveryBatch(notes: try await listMarkdownNotes(in: vaultURL, request: request), cursor: nil)
    }
    func readPreview(for note: NoteItem, request: ProviderRequest) async throws -> NotePreview { .unavailable }
}

final class VaultFileService: VaultFileServing {
    private let fileManager: FileManager
    private let executor: ProviderExecutor
    private let metadata: (URL) throws -> URLResourceValues

    init(fileManager: FileManager = .default, executor: ProviderExecutor = .shared,
         metadata: @escaping (URL) throws -> URLResourceValues = { try $0.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .creationDateKey, .contentModificationDateKey, .fileSizeKey]) }) {
        self.fileManager = fileManager
        self.executor = executor
        self.metadata = metadata
    }


    func createVault(named name: String, in parentURL: URL, request: ProviderRequest) async throws -> URL {
        try await executor.execute(request, step: .vaultCreate, mutation: true, resources: [parentURL]) {
            try self.createVaultBlocking(named: name, in: parentURL, context: $0)
        }
    }
    func listMarkdownNotes(in vaultURL: URL, request: ProviderRequest) async throws -> [NoteItem] {
        var notes: [NoteItem] = [], cursor: NoteDiscoveryCursor?
        repeat {
            let batch = try await discoverNotes(in: vaultURL, cursor: cursor, request: request)
            notes += batch.notes; cursor = batch.cursor
            if cursor == nil && batch.incomplete { throw VaultError.incompleteDiscovery }
        } while cursor != nil
        return notes.sorted(by: NoteItem.mostRecentlyModified)
    }
    func discoverNotes(in vaultURL: URL, cursor: NoteDiscoveryCursor?, request: ProviderRequest) async throws -> NoteDiscoveryBatch {
        try await executor.execute(request, step: .enumeration) {
            try self.discoveryBatch(in: vaultURL, cursor: cursor ?? NoteDiscoveryCursor(), context: $0)
        }
    }
    func readPreview(for note: NoteItem, request: ProviderRequest) async throws -> NotePreview {
        try await executor.execute(request, step: .preview) { context in
            try self.coordinatedItem(at: note.url, in: request.vaultURL, step: .coordinationRead, context: context) { url in
                let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                let prefix = try Self.readPrefix(limit: 64 * 1024, check: context.checkCancellation, hasMore: {
                    try context.checkCancellation()
                    let offset = try handle.offset()
                    return try handle.seekToEnd() > offset
                }) { try handle.read(upToCount: $0) ?? Data() }
                let text = try Self.decodePreviewPrefix(prefix.data, truncated: prefix.truncated)
                DebugLog.shared.observe(.preview, bytes: prefix.data.count)
                if text.isEmpty { return .empty }
                return .available(self.makePreviewMarkdown(contents: text, for: note.url), truncated: prefix.truncated)
            }
        }
    }
    func createNote(named name: String, in directoryURL: URL, request: ProviderRequest) async throws -> URL {
        try await executor.execute(request, step: .noteCreate, mutation: true) {
            try self.createNoteBlocking(named: name, in: directoryURL, vaultURL: request.vaultURL, context: $0)
        }
    }
    func readNote(at url: URL, request: ProviderRequest) async throws -> String {
        try await executor.execute(request, step: .noteRead) { try self.readNoteBlocking(at: url, vaultURL: request.vaultURL, context: $0) }
    }
    func saveNote(_ text: String, at url: URL, request: ProviderRequest) async throws {
        try await executor.execute(request, step: .noteSave, mutation: true) {
            try self.saveNoteBlocking(text, at: url, vaultURL: request.vaultURL, context: $0)
        }
    }
    func importImage(from sourceURL: URL, preferredFilename: String?, into noteURL: URL, vaultURL: URL,
                     request: ProviderRequest) async throws -> InsertedNoteImage {
        try await executor.execute(request, step: .imageImport, mutation: true, resources: [sourceURL]) {
            try self.importImageBlocking(from: sourceURL, preferredFilename: preferredFilename, into: noteURL,
                                        vaultURL: vaultURL, context: $0)
        }
    }
    func importCameraImage(_ image: UIImage, into noteURL: URL, vaultURL: URL,
                           request: ProviderRequest) async throws -> InsertedNoteImage {
        try await executor.execute(request, step: .imageImport, mutation: true) {
            try self.importCameraImageBlocking(image, into: noteURL, vaultURL: vaultURL, context: $0)
        }
    }

    private func createVaultBlocking(named name: String, in parentURL: URL, context: ProviderWorkContext) throws -> URL {
        return try DebugLog.shared.measure(.vaultCreate, file: parentURL) {
            let vaultName = try validatedDisplayName(name)

            return try context.coordinated(.coordinationWrite, at: parentURL) { coordinatedParentURL in
                let vaultURL = coordinatedParentURL.appendingPathComponent(vaultName, isDirectory: true)

                guard !fileManager.fileExists(atPath: vaultURL.path) else {
                    throw VaultError.itemAlreadyExists(vaultName)
                }

                try fileManager.createDirectory(at: vaultURL, withIntermediateDirectories: false)
                return vaultURL
            }
        }
    }

    private func discoveryBatch(in vaultURL: URL, cursor: NoteDiscoveryCursor, context: ProviderWorkContext) throws -> NoteDiscoveryBatch {
        try context.coordinated(.coordinationRead, at: vaultURL) { root in
            guard fileManager.fileExists(atPath: root.path) else { throw VaultError.inaccessibleVault }
            var notes: [NoteItem] = [], examined = 0
            while examined < 256 && notes.count < 64 {
                try context.checkCancellation()
                guard let directory = cursor.directories.last else {
                    DebugLog.shared.observe(.enumeration, count: notes.count)
                    return NoteDiscoveryBatch(notes: notes.sorted(by: NoteItem.mostRecentlyModified), cursor: nil, incomplete: cursor.incomplete, examinedCount: examined)
                }
                let directoryURL = directory.relativePath.isEmpty ? root : root.appendingPathComponent(directory.relativePath, isDirectory: true)
                let index = cursor.directories.count - 1
                if directory.names == nil {
                    do {
                        // Snapshot names only. No filesystem object survives this accessor.
                        // A directory listing is indivisible in Foundation; metadata work is batched below.
                        cursor.directories[index].names = try fileManager.contentsOfDirectory(at: directoryURL,
                            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).map(\.lastPathComponent)
                    } catch {
                        cursor.incomplete = true
                        DebugLog.shared.begin(.enumeration, file: directoryURL).finish(.failure, error: error)
                        cursor.directories.removeLast()
                        continue
                    }
                }
                guard let names = cursor.directories[index].names, cursor.directories[index].nextIndex < names.count else {
                    cursor.directories.removeLast()
                    continue
                }
                let name = names[cursor.directories[index].nextIndex]
                cursor.directories[index].nextIndex += 1
                examined += 1
                let url = directoryURL.appendingPathComponent(name)
                let relativePath = directory.relativePath.isEmpty ? name : directory.relativePath + "/" + name
                do {
                    let type = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    if type.isSymbolicLink == true { continue }
                    if type.isDirectory == true {
                        cursor.directories.append(.init(relativePath: relativePath))
                        continue
                    }
                } catch {
                    cursor.incomplete = true
                    DebugLog.shared.begin(.metadata, file: url).finish(.failure, error: error)
                    continue
                }
                let ext = url.pathExtension.lowercased()
                guard ext == "md" || ext == "markdown" else { continue }
                do {
                    let values = try DebugLog.shared.measure(.metadata, file: url) { try metadata(url) }
                    guard let regular = values.isRegularFile else { throw VaultError.inaccessibleVault }
                    guard regular, values.isSymbolicLink != true else { continue }
                    let folder = relativePath.split(separator: "/").dropLast().joined(separator: "/")
                    notes.append(NoteItem(url: vaultURL.appendingPathComponent(relativePath), title: url.deletingPathExtension().lastPathComponent,
                        relativePath: relativePath, folderPath: folder,
                        folderName: folder.split(separator: "/").last.map(String.init) ?? "Vault",
                        previewMarkdown: "", createdAt: values.creationDate ?? .distantPast,
                        lastModifiedAt: values.contentModificationDate ?? .distantPast, sourceByteCount: values.fileSize))
                } catch {
                    cursor.incomplete = true
                    DebugLog.shared.begin(.metadata, file: url).finish(.failure, error: error)
                }
            }
            DebugLog.shared.observe(.enumeration, count: notes.count)
            return NoteDiscoveryBatch(notes: notes.sorted(by: NoteItem.mostRecentlyModified), cursor: cursor, incomplete: cursor.incomplete, examinedCount: examined)
        }
    }

    /// Reads actual bytes, irrespective of missing/stale file-size metadata. At most one probe byte exceeds the budget.
    static func readEditable(check: () throws -> Void = {}, read: (Int) throws -> Data) throws -> String {
        let limit = 8 * 1024 * 1024
        var data = Data()
        while true {
            try check()
            let chunk = try read(min(16 * 1024, limit - data.count + 1))
            if chunk.isEmpty { break }
            guard chunk.count <= limit - data.count else { throw VaultError.noteTooLarge }
            data.append(chunk)
        }
        guard let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        return text
    }
    static func readPrefix(limit: Int, check: () throws -> Void = {}, hasMore: () throws -> Bool, read: (Int) throws -> Data) throws -> (data: Data, truncated: Bool) {
        var data = Data()
        while data.count < limit {
            try check()
            let chunk = try read(min(16 * 1024, limit - data.count))
            if chunk.isEmpty { return (data, false) }
            data.append(chunk)
        }
        return (data, try hasMore())
    }
    static func decodePreviewPrefix(_ data: Data, truncated: Bool) throws -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        if truncated {
            let bytes = Array(data.suffix(4))
            for count in 1...min(3, bytes.count) {
                let tail = Array(bytes.suffix(count))
                let first = tail[0]
                let expected = (0xC2...0xDF).contains(first) ? 2 : (0xE0...0xEF).contains(first) ? 3 : (0xF0...0xF4).contains(first) ? 4 : 0
                let secondValid = tail.count < 2 || !((first == 0xE0 && tail[1] < 0xA0) ||
                    (first == 0xED && tail[1] > 0x9F) || (first == 0xF0 && tail[1] < 0x90) || (first == 0xF4 && tail[1] > 0x8F))
                if expected > count, secondValid, tail.dropFirst().allSatisfy({ (0x80...0xBF).contains($0) }),
                   let text = String(data: data.dropLast(count), encoding: .utf8) { return text }
            }
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    /// Logical note URLs preserve vault-lane/cache identity; filesystem URLs exist only inside this claim.
    private func coordinatedItem<T>(at url: URL, in vaultURL: URL?, step: DebugLogStep,
                                    context: ProviderWorkContext, accessor: (URL) throws -> T) throws -> T {
        guard let vaultURL else { return try context.coordinated(step, at: url, accessor) }
        // Directory coordination alone does not coordinate its children. Resolve under a root claim,
        // then use the URL supplied by the item's own claim for all content access.
        let currentItem = try context.coordinated(.coordinationRead, at: vaultURL) { currentRoot in
            try Self.resolvedItem(url, in: vaultURL, currentRoot: currentRoot)
        }
        return try context.coordinated(step, at: currentItem, accessor)
    }

    private static func resolvedItem(_ url: URL, in vaultURL: URL, currentRoot: URL) throws -> URL {
        let rootPath = vaultURL.standardizedFileURL.path
        let itemPath = url.standardizedFileURL.path
        if itemPath == rootPath { return currentRoot }
        guard itemPath.hasPrefix(rootPath + "/") else { throw VaultError.inaccessibleVault }
        return currentRoot.appendingPathComponent(String(itemPath.dropFirst(rootPath.count + 1)))
    }

    private func createNoteBlocking(named name: String, in directoryURL: URL, vaultURL: URL?, context: ProviderWorkContext) throws -> URL {
        return try DebugLog.shared.measure(.noteCreate, file: directoryURL) {
            let fileName = try validatedMarkdownFilename(name)

            return try coordinatedItem(at: directoryURL, in: vaultURL, step: .coordinationWrite, context: context) { coordinatedDirectoryURL in
                let noteURL = coordinatedDirectoryURL.appendingPathComponent(fileName, isDirectory: false)

                guard !fileManager.fileExists(atPath: noteURL.path) else {
                    throw VaultError.itemAlreadyExists(fileName)
                }

                try "".write(to: noteURL, atomically: true, encoding: .utf8)
                return vaultURL == nil ? noteURL : directoryURL.appendingPathComponent(fileName)
            }
        }
    }

    private func readNoteBlocking(at url: URL, vaultURL: URL?, context: ProviderWorkContext) throws -> String {
        return try DebugLog.shared.measure(.noteRead, file: url) {
            try coordinatedItem(at: url, in: vaultURL, step: .coordinationRead, context: context) { coordinatedURL in
                guard fileManager.fileExists(atPath: coordinatedURL.path) else {
                    throw VaultError.noteMissing
                }

                let handle = try FileHandle(forReadingFrom: coordinatedURL); defer { try? handle.close() }
                let text = try Self.readEditable(check: context.checkCancellation) { try handle.read(upToCount: $0) ?? Data() }
                DebugLog.shared.observe(.noteRead, bytes: text.utf8.count)
                return text
            }
        }
    }

    private func saveNoteBlocking(_ text: String, at url: URL, vaultURL: URL?, context: ProviderWorkContext) throws {
        return try DebugLog.shared.measure(.noteSave, file: url) {
            #if DEBUG
            if ImageWorkflowSaveFailure.enabled { throw CocoaError(.fileWriteNoPermission) }
            #endif
            try coordinatedItem(at: url, in: vaultURL, step: .coordinationWrite, context: context) { coordinatedURL in
                guard fileManager.fileExists(atPath: coordinatedURL.path) else {
                    throw VaultError.noteMissing
                }

                try text.write(to: coordinatedURL, atomically: true, encoding: .utf8)
                DebugLog.shared.observe(.noteSave, bytes: text.utf8.count)
            }
        }
    }

    private func importImageBlocking(from sourceURL: URL, preferredFilename: String?, into noteURL: URL, vaultURL: URL, context: ProviderWorkContext) throws -> InsertedNoteImage {
        return try DebugLog.shared.measure(.imageImport, file: sourceURL) {
            try context.coordinated(.coordinationWrite, at: vaultURL) { coordinatedVaultURL in
                let coordinatedNoteURL = try Self.resolvedItem(noteURL, in: vaultURL, currentRoot: coordinatedVaultURL)
                let assetFolderURL = noteAssetFolderURL(for: coordinatedNoteURL)
                try fileManager.createDirectory(at: assetFolderURL, withIntermediateDirectories: true)

                let preferredBaseName = preferredFilename ?? sourceURL.deletingPathExtension().lastPathComponent
                let pathExtension = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension.lowercased()
                let targetURL = try uniqueAssetURL(in: assetFolderURL, preferredBaseName: preferredBaseName, pathExtension: pathExtension)

                if fileManager.fileExists(atPath: targetURL.path) {
                    try fileManager.removeItem(at: targetURL)
                }
                try context.coordinated(.coordinationRead, at: sourceURL) { coordinatedSource in
                    try fileManager.copyItem(at: coordinatedSource, to: targetURL)
                }

                let relativePath = relativeMarkdownPath(from: coordinatedNoteURL, to: targetURL)
                let altText = displayAltText(from: preferredBaseName)
                let markdownSource = "![\(altText)](\(relativePath))"

                guard Self.resolveImageURL(markdownPath: relativePath, noteURL: coordinatedNoteURL, vaultURL: coordinatedVaultURL) != nil else {
                    throw VaultError.inaccessibleVault
                }

                return InsertedNoteImage(markdownSource: markdownSource, assetURL: targetURL, altText: altText)
            }
        }
    }

    private func importCameraImageBlocking(_ image: UIImage, into noteURL: URL, vaultURL: URL, context: ProviderWorkContext) throws -> InsertedNoteImage {
        return try DebugLog.shared.measure(.imageImport, file: noteURL) {
            try context.coordinated(.coordinationWrite, at: vaultURL) { coordinatedVaultURL in
                let coordinatedNoteURL = try Self.resolvedItem(noteURL, in: vaultURL, currentRoot: coordinatedVaultURL)
                let assetFolderURL = noteAssetFolderURL(for: coordinatedNoteURL)
                try fileManager.createDirectory(at: assetFolderURL, withIntermediateDirectories: true)

                let preferredBaseName = "Photo \(timestampFormatter.string(from: Date()))"
                let targetURL = try uniqueAssetURL(in: assetFolderURL, preferredBaseName: preferredBaseName, pathExtension: "jpg")
                guard let jpegData = DebugLog.shared.measure(.imageEncode, { image.jpegData(compressionQuality: 0.9) }) else {
                    throw VaultError.inaccessibleVault
                }
                try jpegData.write(to: targetURL, options: .atomic)

                let relativePath = relativeMarkdownPath(from: coordinatedNoteURL, to: targetURL)
                let altText = displayAltText(from: preferredBaseName)
                let markdownSource = "![\(altText)](\(relativePath))"

                guard Self.resolveImageURL(markdownPath: relativePath, noteURL: coordinatedNoteURL, vaultURL: coordinatedVaultURL) != nil else {
                    throw VaultError.inaccessibleVault
                }

                return InsertedNoteImage(markdownSource: markdownSource, assetURL: targetURL, altText: altText)
            }
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

    private func makePreviewMarkdown(contents: String, for url: URL) -> String {
        return DebugLog.shared.measure(.preview, file: url) {
            let normalized = MarkdownDocument.normalizedMarkdown(
                noteTitle: url.deletingPathExtension().lastPathComponent,
                markdown: contents
            )
            let lines = normalized.components(separatedBy: .newlines)
            var previewLines: [String] = []
            var characterCount = 0
            var isInsideCodeFence = false

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if let fence = fencedCodeDelimiter(in: trimmed) {
                    isInsideCodeFence.toggle()
                    if isInsideCodeFence, previewLines.isEmpty {
                        previewLines.append("`\(fence)`")
                        characterCount += fence.count + 2
                    }
                    continue
                }

                guard !isInsideCodeFence else { continue }

                if trimmed.isEmpty {
                    if !previewLines.isEmpty, previewLines.last != "" {
                        previewLines.append("")
                    }
                    continue
                }

                if isTableSeparator(trimmed) {
                    continue
                }

                let previewLine = previewDisplayLine(for: trimmed)
                guard !previewLine.isEmpty else { continue }

                let separatorCost = previewLines.isEmpty ? 0 : 1
                if characterCount + previewLine.count + separatorCost > 220 {
                    break
                }

                previewLines.append(previewLine)
                characterCount += previewLine.count + separatorCost

                if previewLines.count >= 4 {
                    break
                }
            }

            while previewLines.last == "" {
                previewLines.removeLast()
            }

            return previewLines.joined(separator: "\n")
        }
    }

    private func previewDisplayLine(for line: String) -> String {
        if let headingRange = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
            let heading = line[headingRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return heading.isEmpty ? "" : "**\(heading)**"
        }

        if let checkboxMatch = line.range(of: #"^[-*]\s+\[( |x|X)\]\s+"#, options: .regularExpression) {
            let checkboxToken = line[checkboxMatch].lowercased()
            let marker = checkboxToken.contains("[x]") ? "✓" : "○"
            let content = line[checkboxMatch.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? "" : "\(marker) \(content)"
        }

        if let bulletRange = line.range(of: #"^[-*]\s+"#, options: .regularExpression) {
            let content = line[bulletRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? "" : "• \(content)"
        }

        if let orderedRange = line.range(of: #"^(\d+)\.\s+"#, options: .regularExpression) {
            let prefix = String(line[..<orderedRange.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let content = line[orderedRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? "" : "\(prefix) \(content)"
        }

        if let quoteRange = line.range(of: #"^>\s*"#, options: .regularExpression) {
            let content = line[quoteRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? "" : "_\(content)_"
        }

        return line
    }

    private func fencedCodeDelimiter(in line: String) -> String? {
        if line.hasPrefix("```") { return "```" }
        if line.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    private func isTableSeparator(_ line: String) -> Bool {
        line.contains("|") &&
            line
            .replacingOccurrences(of: "|", with: "")
            .allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
    }

    private func noteAssetFolderURL(for noteURL: URL) -> URL {
        let noteDirectoryURL = noteURL.deletingLastPathComponent()
        let noteName = noteURL.deletingPathExtension().lastPathComponent
        return noteDirectoryURL.appendingPathComponent("\(noteName) Assets", isDirectory: true)
    }

    private func uniqueAssetURL(in directoryURL: URL, preferredBaseName: String, pathExtension: String) throws -> URL {
        let sanitizedBaseName = try validatedDisplayName(preferredBaseName.replacingOccurrences(of: ".", with: " "))
        let trimmedExtension = pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseExtension = trimmedExtension.isEmpty ? "jpg" : trimmedExtension

        var candidateURL = directoryURL.appendingPathComponent("\(sanitizedBaseName).\(baseExtension)", isDirectory: false)
        var suffix = 2

        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateURL = directoryURL.appendingPathComponent("\(sanitizedBaseName) \(suffix).\(baseExtension)", isDirectory: false)
            suffix += 1
        }

        return candidateURL
    }

    private func relativeMarkdownPath(from noteURL: URL, to assetURL: URL) -> String {
        let noteDirectoryURL = noteURL.deletingLastPathComponent().standardizedFileURL
        let standardizedAssetURL = assetURL.standardizedFileURL

        if standardizedAssetURL.deletingLastPathComponent() == noteDirectoryURL {
            return standardizedAssetURL.lastPathComponent
        }

        let notePathComponents = noteDirectoryURL.pathComponents
        let assetPathComponents = standardizedAssetURL.pathComponents

        var sharedPrefixCount = 0
        while sharedPrefixCount < notePathComponents.count &&
                sharedPrefixCount < assetPathComponents.count &&
                notePathComponents[sharedPrefixCount] == assetPathComponents[sharedPrefixCount] {
            sharedPrefixCount += 1
        }

        let parentTraversal = Array(repeating: "..", count: max(notePathComponents.count - sharedPrefixCount, 0))
        let remainingComponents = Array(assetPathComponents.dropFirst(sharedPrefixCount))
        return (parentTraversal + remainingComponents).joined(separator: "/")
    }

    private func displayAltText(from baseName: String) -> String {
        let trimmed = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Image" }
        return trimmed.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
    }

    private var timestampFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }

    static func resolveImageURL(markdownPath: String, noteURL: URL, vaultURL: URL) -> URL? {
        let trimmed = markdownPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let cleanedPath = cleanedMarkdownPath(trimmed)
        if let url = URL(string: cleanedPath), url.scheme != nil {
            return nil
        }

        let standardizedVaultURL = vaultURL.standardizedFileURL
        let candidateURL: URL
        if cleanedPath.hasPrefix("/") {
            candidateURL = standardizedVaultURL.appendingPathComponent(String(cleanedPath.dropFirst()), isDirectory: false)
        } else {
            candidateURL = noteURL.deletingLastPathComponent().appendingPathComponent(cleanedPath, isDirectory: false)
        }

        let standardizedCandidate = candidateURL.standardizedFileURL
        let resolvedCandidateParent = standardizedCandidate
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
        let resolvedVaultURL = standardizedVaultURL.resolvingSymlinksInPath()
        let resolvedCandidate = resolvedCandidateParent
            .appendingPathComponent(standardizedCandidate.lastPathComponent, isDirectory: false)
            .resolvingSymlinksInPath()
        let vaultPath = resolvedVaultURL.path
        let candidatePath = resolvedCandidate.path
        guard candidatePath == vaultPath || candidatePath.hasPrefix(vaultPath + "/") else {
            return nil
        }

        return resolvedCandidate
    }

    private static func cleanedMarkdownPath(_ path: String) -> String {
        let withoutAngles: String
        if path.hasPrefix("<"), path.hasSuffix(">") {
            withoutAngles = String(path.dropFirst().dropLast())
        } else {
            withoutAngles = path
        }
        return withoutAngles.removingPercentEncoding ?? withoutAngles
    }
}
