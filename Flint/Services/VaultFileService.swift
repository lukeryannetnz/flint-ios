import Foundation
import UIKit

enum VaultError: LocalizedError, Equatable {
    case emptyName
    case invalidName(String)
    case itemAlreadyExists(String)
    case inaccessibleVault
    case noteTooLarge
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
        case .noteTooLarge:
            return "This note exceeds Flint’s 8 MiB editing limit. The file has not been changed."
        case .noteMissing:
            return "The selected note could not be found."
        }
    }
}

protocol VaultFileServing {
    func createVault(named name: String, in parentURL: URL, request: ProviderRequest) async throws -> URL
    func listMarkdownNotes(in vaultURL: URL, request: ProviderRequest) async throws -> [NoteItem]
    func discoverNotes(in vaultURL: URL, request: ProviderRequest, onBatch: @escaping ([NoteItem]) async -> Void) async throws
    func preview(for note: NoteItem, request: ProviderRequest) async throws -> NotePreview
    func invalidatePreviews()
    func createNote(named name: String, in directoryURL: URL, request: ProviderRequest) async throws -> URL
    func readNote(at url: URL, request: ProviderRequest) async throws -> String
    func saveNote(_ text: String, at url: URL, request: ProviderRequest) async throws
    func importImage(from sourceURL: URL, preferredFilename: String?, into noteURL: URL, vaultURL: URL, request: ProviderRequest) async throws -> InsertedNoteImage
    func importCameraImage(_ image: UIImage, into noteURL: URL, vaultURL: URL, request: ProviderRequest) async throws -> InsertedNoteImage
}

extension VaultFileServing {
    func discoverNotes(in vaultURL: URL, request: ProviderRequest, onBatch: @escaping ([NoteItem]) async -> Void) async throws {
        let notes = try await listMarkdownNotes(in: vaultURL, request: request)
        await onBatch(notes)
    }
    func preview(for note: NoteItem, request: ProviderRequest) async throws -> NotePreview {
        note.previewMarkdown.isEmpty ? .empty : .ready(note.previewMarkdown, truncated: false)
    }
    func invalidatePreviews() {}
}

/// Used by one sequential discovery loop. Each next batch runs on a provider worker.
private final class NoteDiscoveryCursor {
    var enumerator: FileManager.DirectoryEnumerator?
    var error: Error?
    var done = false
    var lease: SecurityScopeLease?
}

final class VaultFileService: VaultFileServing {
    private let fileManager: FileManager
    private let executor: ProviderExecutor
    private struct PreviewEntry {
        let modified: Date?
        let size: Int?
        let preview: NotePreview
        let cost: Int
    }
    private let previewCacheLimit: Int
    private let previewLock = NSLock()
    private var previewCache: [URL: PreviewEntry] = [:]
    private var previewOrder: [URL] = []
    private var previewBytes = 0
    private var previewEpoch = 0
    var cachedPreviewBytes: Int { previewLock.lock(); defer { previewLock.unlock() }; return previewBytes }
    func invalidatePreviews() {
        previewLock.lock(); defer { previewLock.unlock() }
        previewCache = [:]; previewOrder = []; previewBytes = 0; previewEpoch += 1
    }


    init(fileManager: FileManager = .default, executor: ProviderExecutor = .shared, previewCacheLimit: Int = 4 * 1024 * 1024) {
        self.fileManager = fileManager
        self.executor = executor
        self.previewCacheLimit = max(0, previewCacheLimit)
    }


    func createVault(named name: String, in parentURL: URL, request: ProviderRequest) async throws -> URL {
        try await executor.execute(request, step: .vaultCreate, mutation: true, resources: [parentURL]) {
            try self.createVaultBlocking(named: name, in: parentURL, context: $0)
        }
    }
    func listMarkdownNotes(in vaultURL: URL, request: ProviderRequest) async throws -> [NoteItem] {
        var result: [NoteItem] = []
        try await discoverNotes(in: vaultURL, request: request) { result += $0 }
        return Self.sortedNotes(result)
    }

    static func sortedNotes(_ notes: [NoteItem]) -> [NoteItem] {
        notes.sorted {
            if $0.lastModifiedAt != $1.lastModifiedAt { return $0.lastModifiedAt > $1.lastModifiedAt }
            return $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }
    }

    func discoverNotes(in vaultURL: URL, request: ProviderRequest, onBatch: @escaping ([NoteItem]) async -> Void) async throws {
        let cursor = NoteDiscoveryCursor()
        while true {
            let batch = try await executor.execute(request, step: .enumeration) { context -> ([NoteItem], Bool, Error?) in
                try context.coordinated(.coordinationRead, at: vaultURL) { root in
                    if cursor.enumerator == nil {
                        cursor.lease = context.primaryLease
                        guard self.fileManager.fileExists(atPath: root.path) else { throw VaultError.inaccessibleVault }
                        cursor.enumerator = self.fileManager.enumerator(at: root,
                            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .creationDateKey, .contentModificationDateKey],
                            options: [.skipsHiddenFiles], errorHandler: { _, error in cursor.error = error; return false })
                        guard cursor.enumerator != nil else { throw VaultError.inaccessibleVault }
                    }
                    var notes: [NoteItem] = []
                    for _ in 0..<64 {
                        try context.checkCancellation()
                        guard let url = cursor.enumerator?.nextObject() as? URL else { cursor.done = true; break }
                        guard ["md", "markdown"].contains(url.pathExtension.lowercased()) else { continue }
                        do {
                            let values = try DebugLog.shared.measure(.metadata, file: url) {
                                try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .creationDateKey, .contentModificationDateKey])
                            }
                            guard let regular = values.isRegularFile else { throw VaultError.inaccessibleVault }
                            guard regular, values.isSymbolicLink != true else { continue }
                            let path = String(url.path.dropFirst(root.path.count + 1))
                            let folder = path.split(separator: "/").dropLast().joined(separator: "/")
                            notes.append(NoteItem(url: url, title: url.deletingPathExtension().lastPathComponent,
                                relativePath: path, folderPath: folder, folderName: folder.split(separator: "/").last.map(String.init) ?? "Vault",
                                previewMarkdown: "", createdAt: values.creationDate ?? .distantPast,
                                lastModifiedAt: values.contentModificationDate ?? .distantPast))
                        } catch {
                            DebugLog.shared.begin(.metadata, file: url).finish(.failure, error: error)
                            cursor.error = error
                        }
                    }
                    DebugLog.shared.observe(.enumeration, count: notes.count)
                    return (Self.sortedNotes(notes), cursor.done, cursor.error)
                }
            }
            await onBatch(batch.0)
            if let error = batch.2 { throw error }
            if batch.1 { return }
            // A new admission lets queued explicit reads/saves precede the next metadata batch.
            await Task.yield()
        }
    }

    func preview(for note: NoteItem, request: ProviderRequest) async throws -> NotePreview {
        try await executor.execute(request, step: .preview) { context in
            try context.coordinated(.coordinationRead, at: note.url) { url in
                var observedURL = url
                observedURL.removeAllCachedResourceValues()
                let values = try? observedURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                // Opening before a cache hit also verifies that a cached empty note still exists.
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                self.previewLock.lock()
                let epoch = self.previewEpoch
                if let values, let cached = self.previewCache[note.url],
                   cached.modified == values.contentModificationDate, cached.size == values.fileSize {
                    self.previewOrder.removeAll { $0 == note.url }; self.previewOrder.append(note.url)
                    self.previewLock.unlock(); return cached.preview
                }
                self.previewLock.unlock()
                var data = Data()
                while data.count < 64 * 1024 {
                    try context.checkCancellation()
                    let chunk = try handle.read(upToCount: 64 * 1024 - data.count) ?? Data()
                    if chunk.isEmpty { break }
                    data.append(chunk)
                }
                let truncated = data.count == 64 * 1024
                var complete = data
                var contents = String(data: complete, encoding: .utf8)
                if contents == nil && truncated {
                    for _ in 0..<3 where !complete.isEmpty {
                        complete.removeLast()
                        contents = String(data: complete, encoding: .utf8)
                        if contents != nil { break }
                    }
                }
                guard let contents else { throw CocoaError(.fileReadInapplicableStringEncoding) }
                let preview: NotePreview = data.isEmpty ? .empty : .ready(self.makePreviewMarkdown(contents: contents, title: note.title), truncated: truncated)
                // Charge a minimum cost so empty entries also stay bounded.
                let cost = 256 + preview.text.utf8.count + note.url.absoluteString.utf8.count * 2
                self.previewLock.lock(); defer { self.previewLock.unlock() }
                guard epoch == self.previewEpoch else { return preview }
                if let old = self.previewCache.removeValue(forKey: note.url) { self.previewBytes -= old.cost }
                self.previewOrder.removeAll { $0 == note.url }
                while self.previewBytes + cost > self.previewCacheLimit, let oldest = self.previewOrder.first {
                    self.previewOrder.removeFirst()
                    if let old = self.previewCache.removeValue(forKey: oldest) { self.previewBytes -= old.cost }
                }
                if cost <= self.previewCacheLimit {
                    self.previewCache[note.url] = PreviewEntry(modified: values?.contentModificationDate, size: values?.fileSize, preview: preview, cost: cost)
                    self.previewOrder.append(note.url); self.previewBytes += cost
                }
                DebugLog.shared.observe(.preview, bytes: data.count)
                return preview
            }
        }
    }
    func createNote(named name: String, in directoryURL: URL, request: ProviderRequest) async throws -> URL {
        try await executor.execute(request, step: .noteCreate, mutation: true) {
            try self.createNoteBlocking(named: name, in: directoryURL, context: $0)
        }
    }
    func readNote(at url: URL, request: ProviderRequest) async throws -> String {
        try await executor.execute(request, step: .noteRead) { try self.readNoteBlocking(at: url, context: $0) }
    }
    func saveNote(_ text: String, at url: URL, request: ProviderRequest) async throws {
        try await executor.execute(request, step: .noteSave, mutation: true) {
            try self.saveNoteBlocking(text, at: url, context: $0)
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

    private func createNoteBlocking(named name: String, in directoryURL: URL, context: ProviderWorkContext) throws -> URL {
        return try DebugLog.shared.measure(.noteCreate, file: directoryURL) {
            let fileName = try validatedMarkdownFilename(name)

            return try context.coordinated(.coordinationWrite, at: directoryURL) { coordinatedDirectoryURL in
                let noteURL = coordinatedDirectoryURL.appendingPathComponent(fileName, isDirectory: false)

                guard !fileManager.fileExists(atPath: noteURL.path) else {
                    throw VaultError.itemAlreadyExists(fileName)
                }

                try "".write(to: noteURL, atomically: true, encoding: .utf8)
                return noteURL
            }
        }
    }

    private func readNoteBlocking(at url: URL, context: ProviderWorkContext) throws -> String {
        return try DebugLog.shared.measure(.noteRead, file: url) {
            try context.coordinated(.coordinationRead, at: url) { coordinatedURL in
                guard fileManager.fileExists(atPath: coordinatedURL.path) else {
                    throw VaultError.noteMissing
                }

                let handle = try FileHandle(forReadingFrom: coordinatedURL)
                defer { try? handle.close() }
                let limit = 8 * 1024 * 1024
                var data = Data()
                while true {
                    try context.checkCancellation()
                    let chunk = try handle.read(upToCount: min(64 * 1024, limit + 1 - data.count)) ?? Data()
                    if chunk.isEmpty { break }
                    data.append(chunk)
                    guard data.count <= limit else { throw VaultError.noteTooLarge }
                }
                guard let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
                DebugLog.shared.observe(.noteRead, bytes: text.utf8.count)
                return text
            }
        }
    }

    private func saveNoteBlocking(_ text: String, at url: URL, context: ProviderWorkContext) throws {
        return try DebugLog.shared.measure(.noteSave, file: url) {
            #if DEBUG
            if ImageWorkflowSaveFailure.enabled { throw CocoaError(.fileWriteNoPermission) }
            #endif
            try context.coordinated(.coordinationWrite, at: url) { coordinatedURL in
                guard fileManager.fileExists(atPath: coordinatedURL.path) else {
                    throw VaultError.noteMissing
                }

                try text.write(to: coordinatedURL, atomically: true, encoding: .utf8)
                invalidatePreviews()
                DebugLog.shared.observe(.noteSave, bytes: text.utf8.count)
            }
        }
    }

    private func importImageBlocking(from sourceURL: URL, preferredFilename: String?, into noteURL: URL, vaultURL: URL, context: ProviderWorkContext) throws -> InsertedNoteImage {
        return try DebugLog.shared.measure(.imageImport, file: sourceURL) {
            try context.coordinated(.coordinationWrite, at: vaultURL) { coordinatedVaultURL in
                let assetFolderURL = noteAssetFolderURL(for: noteURL)
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

                let relativePath = relativeMarkdownPath(from: noteURL, to: targetURL)
                let altText = displayAltText(from: preferredBaseName)
                let markdownSource = "![\(altText)](\(relativePath))"

                guard Self.resolveImageURL(markdownPath: relativePath, noteURL: noteURL, vaultURL: coordinatedVaultURL) != nil else {
                    throw VaultError.inaccessibleVault
                }

                return InsertedNoteImage(markdownSource: markdownSource, assetURL: targetURL, altText: altText)
            }
        }
    }

    private func importCameraImageBlocking(_ image: UIImage, into noteURL: URL, vaultURL: URL, context: ProviderWorkContext) throws -> InsertedNoteImage {
        return try DebugLog.shared.measure(.imageImport, file: noteURL) {
            try context.coordinated(.coordinationWrite, at: vaultURL) { coordinatedVaultURL in
                let assetFolderURL = noteAssetFolderURL(for: noteURL)
                try fileManager.createDirectory(at: assetFolderURL, withIntermediateDirectories: true)

                let preferredBaseName = "Photo \(timestampFormatter.string(from: Date()))"
                let targetURL = try uniqueAssetURL(in: assetFolderURL, preferredBaseName: preferredBaseName, pathExtension: "jpg")
                guard let jpegData = DebugLog.shared.measure(.imageEncode, { image.jpegData(compressionQuality: 0.9) }) else {
                    throw VaultError.inaccessibleVault
                }
                try jpegData.write(to: targetURL, options: .atomic)

                let relativePath = relativeMarkdownPath(from: noteURL, to: targetURL)
                let altText = displayAltText(from: preferredBaseName)
                let markdownSource = "![\(altText)](\(relativePath))"

                guard Self.resolveImageURL(markdownPath: relativePath, noteURL: noteURL, vaultURL: coordinatedVaultURL) != nil else {
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

    private func makePreviewMarkdown(contents: String, title: String) -> String {
        let normalized = MarkdownDocument.normalizedMarkdown(
            noteTitle: title,
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
