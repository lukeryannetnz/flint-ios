import Foundation
import UIKit

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
    func importImage(from sourceURL: URL, preferredFilename: String?, into noteURL: URL, vaultURL: URL) throws -> InsertedNoteImage
    func importCameraImage(_ image: UIImage, into noteURL: URL, vaultURL: URL) throws -> InsertedNoteImage
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
                    let previewMarkdown = (try? makePreviewMarkdown(for: url)) ?? ""

                    return NoteItem(
                        url: url,
                        title: url.deletingPathExtension().lastPathComponent,
                        relativePath: relativePath,
                        folderPath: normalizedFolderPath,
                        folderName: normalizedFolderPath.components(separatedBy: "/").last.flatMap { $0.isEmpty ? nil : $0 } ?? "Vault",
                        previewMarkdown: previewMarkdown,
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

            try "".write(to: noteURL, atomically: true, encoding: .utf8)
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

    func importImage(from sourceURL: URL, preferredFilename: String?, into noteURL: URL, vaultURL: URL) throws -> InsertedNoteImage {
        try coordinatedWrite(at: vaultURL) { coordinatedVaultURL in
            let assetFolderURL = noteAssetFolderURL(for: noteURL)
            try fileManager.createDirectory(at: assetFolderURL, withIntermediateDirectories: true)

            let preferredBaseName = preferredFilename ?? sourceURL.deletingPathExtension().lastPathComponent
            let pathExtension = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension.lowercased()
            let targetURL = try uniqueAssetURL(in: assetFolderURL, preferredBaseName: preferredBaseName, pathExtension: pathExtension)

            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.copyItem(at: sourceURL, to: targetURL)

            let relativePath = relativeMarkdownPath(from: noteURL, to: targetURL)
            let altText = displayAltText(from: preferredBaseName)
            let markdownSource = "![\(altText)](\(relativePath))"

            guard Self.resolveImageURL(markdownPath: relativePath, noteURL: noteURL, vaultURL: coordinatedVaultURL) != nil else {
                throw VaultError.inaccessibleVault
            }

            return InsertedNoteImage(markdownSource: markdownSource, assetURL: targetURL, altText: altText)
        }
    }

    func importCameraImage(_ image: UIImage, into noteURL: URL, vaultURL: URL) throws -> InsertedNoteImage {
        try coordinatedWrite(at: vaultURL) { coordinatedVaultURL in
            let assetFolderURL = noteAssetFolderURL(for: noteURL)
            try fileManager.createDirectory(at: assetFolderURL, withIntermediateDirectories: true)

            let preferredBaseName = "Photo \(timestampFormatter.string(from: Date()))"
            let targetURL = try uniqueAssetURL(in: assetFolderURL, preferredBaseName: preferredBaseName, pathExtension: "jpg")
            guard let jpegData = image.jpegData(compressionQuality: 0.9) else {
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

    private func makePreviewMarkdown(for url: URL) throws -> String {
        let contents = try String(contentsOf: url, encoding: .utf8)
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
