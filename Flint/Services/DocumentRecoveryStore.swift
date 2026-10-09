import Foundation

struct RecoveredDocument: Codable, Identifiable, Equatable {
    let id: UUID
    let vaultURL: URL
    let noteURL: URL
    let text: String
    let savedAt: Date
}

/// Document content lives here, never in diagnostic evidence. Records require explicit deletion.
final class DocumentRecoveryStore {
    static let shared = DocumentRecoveryStore()
    private let directory: URL
    private let writer = DispatchQueue(label: "flint.document-recovery", qos: .utility)
    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("FlintDocumentRecovery", isDirectory: true)) { self.directory = directory }

    private func perform<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            writer.async { continuation.resume(with: Result { try body() }) }
        }
    }
    func retain(vaultURL: URL, noteURL: URL, text: String) async throws -> RecoveredDocument {
        try await perform { [self] in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var local = directory
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try local.setResourceValues(values)
            let document = RecoveredDocument(id: UUID(), vaultURL: vaultURL, noteURL: noteURL, text: text, savedAt: Date())
            try JSONEncoder().encode(document).write(to: directory.appendingPathComponent(document.id.uuidString + ".json"),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return document
        }
    }
    func list() async throws -> [RecoveredDocument] {
        try await perform { [self] in
            guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
            return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .map { try JSONDecoder().decode(RecoveredDocument.self, from: Data(contentsOf: $0)) }
                .sorted { $0.savedAt > $1.savedAt }
        }
    }
    func remove(_ document: RecoveredDocument) async throws {
        try await perform { [self] in
            try FileManager.default.removeItem(at: directory.appendingPathComponent(document.id.uuidString + ".json"))
        }
    }
}
