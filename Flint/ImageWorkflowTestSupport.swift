#if DEBUG
import Foundation
import UIKit

/// Only the UI-test runner can enable write failures; Release excludes this type.
enum ImageWorkflowSaveFailure {
    static var removed = false
    static var enabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        return UUID(uuidString: environment["FLINT_IMAGE_TEST_RUN"] ?? "") != nil
            && environment["FLINT_IMAGE_TEST_FAIL_SAVE"] == "1" && !removed
    }
}

/// Enabled only by the UI-test runner. Fixtures live in this app's container.
enum ImageWorkflowTestSupport {
    static var runID: String? {
        guard let raw = ProcessInfo.processInfo.environment["FLINT_IMAGE_TEST_RUN"],
              UUID(uuidString: raw) != nil else { return nil }
        return raw
    }
    static var active: Bool { runID != nil }
    static var directory: URL? {
        runID.map { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImageWorkflowTests/\($0)", isDirectory: true) }
    }
    static var sourceURL: URL? { directory?.appendingPathComponent("Source.png") }
    static var root: URL? { directory?.appendingPathComponent("Vault", isDirectory: true) }
    static func fixtureImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 240, height: 160)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
        }
    }
    static func prepare() throws -> URL {
        guard let directory, let root, let sourceURL else { throw VaultError.inaccessibleVault }
        if ProcessInfo.processInfo.environment["FLINT_IMAGE_TEST_CLEANUP"] == "1" {
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
            throw VaultError.inaccessibleVault
        }
        if !FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let data = fixtureImage().pngData()!
            try data.write(to: sourceURL)
            try data.write(to: root.appendingPathComponent("Existing.png"))
            try "Before\n![Fixture caption](Existing.png)\nAfter".write(to: root.appendingPathComponent("Existing.md"), atomically: true, encoding: .utf8)
            try "Before\n![Missing caption](Missing.png)\nAfter".write(to: root.appendingPathComponent("Missing.md"), atomically: true, encoding: .utf8)
            try "Before\nAfter".write(to: root.appendingPathComponent("Editable.md"), atomically: true, encoding: .utf8)
        }
        if ProcessInfo.processInfo.environment["FLINT_FOLDER_TEST"] == "1" {
            let folder = root.appendingPathComponent("Projects/iOS", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let seed = folder.appendingPathComponent("Seed.md")
            if !FileManager.default.fileExists(atPath: seed.path) {
                try "Nested fixture".write(to: seed, atomically: true, encoding: .utf8)
            }
        }
        return root
    }
    @MainActor
    static func snapshot(model: AppModel) -> String {
        guard let note = model.selectedNote, let root else { return "{}" }
        let saved = (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
        func assets(in markdown: String) -> [[String: Any]] {
            let pattern = #"!\[[^\]]*\]\(([^\)]+)\)"#
            let matches = (try? NSRegularExpression(pattern: pattern))?.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown)) ?? []
            let references = matches.compactMap { Range($0.range(at: 1), in: markdown).map { String(markdown[$0]) } }
            return references.map { ref in
                let resolved = VaultFileService.resolveImageURL(markdownPath: ref, noteURL: note.url, vaultURL: root)
                let managed = note.url.deletingLastPathComponent()
                    .appendingPathComponent(note.url.deletingPathExtension().lastPathComponent + " Assets", isDirectory: true)
                    .resolvingSymlinksInPath().standardizedFileURL
                let insideManaged = resolved?.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == managed
                return ["reference": ref, "managed": insideManaged,
                        "readable": resolved.flatMap { UIImage(contentsOfFile: $0.path) } != nil]
            }
        }
        let value: [String: Any] = ["notePath": note.relativePath, "saved": saved, "editor": model.noteText,
                                   "unsaved": model.hasUnsavedChanges, "assets": assets(in: saved), "editorAssets": assets(in: model.noteText),
                                   "sourceExists": sourceURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
#endif
