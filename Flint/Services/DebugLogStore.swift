import Foundation

/// Accessed exclusively by DebugLog's serial writer. JSON lines isolate incomplete writes.
final class DebugLogStore {
    let directory: URL
    private let manager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var segment: URL?
    private var segmentSize = 0
    static let totalLimit = 20 * 1024 * 1024
    static let segmentLimit = 256 * 1024
    static let entryLimit = 16 * 1024
    static let ageLimit: TimeInterval = 7 * 24 * 60 * 60

    init(directory: URL) {
        self.directory = directory
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func append(_ entry: DebugLogEntry) throws {
        var data = try encoder.encode(entry)
        data.append(10)
        guard data.count <= Self.entryLimit else { throw CocoaError(.fileWriteOutOfSpace) }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var folder = directory; try folder.setResourceValues(values)
        try prune(reserving: data.count)
        if segment == nil || segmentSize + data.count > Self.segmentLimit {
            segment = directory.appendingPathComponent(UUID().uuidString + ".jsonl")
            segmentSize = 0
            guard manager.createFile(atPath: segment!.path, contents: nil,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let handle = try FileHandle(forWritingTo: segment!)
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            segmentSize += data.count
        } catch {
            // Never append behind a partial record after a failed write.
            segment = nil; segmentSize = 0
            throw error
        }
    }

    func prune(reserving: Int = 0, now: Date = Date()) throws {
        var files = try segments()
        for file in files where now.timeIntervalSince(file.date) >= Self.ageLimit {
            try remove(file.url)
        }
        files = try segments()
        var size = files.reduce(0) { $0 + $1.size }
        for file in files where size + reserving > Self.totalLimit {
            try remove(file.url); size -= file.size
        }
    }

    func snapshot() throws -> Data {
        try prune()
        var output = Data()
        for file in try segments() {
            // Malformed/oversized segments cannot force unbounded reads.
            guard file.size <= Self.segmentLimit,
                  let data = try? Data(contentsOf: file.url) else { continue }
            let lines = data.split(separator: 10, omittingEmptySubsequences: false)
            for line in lines.dropLast() where !line.isEmpty && line.count <= Self.entryLimit {
                guard let entry = try? decoder.decode(DebugLogEntry.self, from: Data(line)),
                      entry.schemaVersion == 1, isSafe(entry),
                      Date().timeIntervalSince(entry.timestamp) < Self.ageLimit else { continue }
                // Re-encode fixed fields: unknown malicious fields never survive snapshot/export.
                let clean = try encoder.encode(entry)
                guard output.count + clean.count + 1 <= Self.totalLimit else { return output }
                output.append(clean); output.append(10)
            }
        }
        return output
    }

    private func isSafe(_ entry: DebugLogEntry) -> Bool {
        func safeIdentity(_ value: String) -> Bool {
            !value.isEmpty && value.count <= 64 && value.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-").contains($0)
            }
        }
        let safeFile = entry.fileID.map { value in
            value.count == 24 && value.allSatisfy { "0123456789abcdef".contains($0) }
        } ?? true
        let allowedCodes = [NSFileReadNoSuchFileError, NSFileNoSuchFileError,
                            NSFileReadNoPermissionError, NSFileWriteNoPermissionError, NSFileReadCorruptFileError]
        return ["info", "error"].contains(entry.severity) && safeIdentity(entry.appVersion)
            && safeIdentity(entry.build) && safeFile && entry.elapsedSeconds.isFinite && entry.elapsedSeconds >= 0
            && (entry.durationSeconds.map { $0.isFinite && $0 >= 0 } ?? true)
            && (entry.count.map { $0 >= 0 } ?? true) && (entry.bytes.map { $0 >= 0 } ?? true)
            && (entry.errorCode.map { allowedCodes.contains($0) } ?? true)
    }

    private func remove(_ url: URL) throws {
        try manager.removeItem(at: url)
        if segment == url { segment = nil; segmentSize = 0 }
    }
    private func segments() throws -> [(url: URL, size: Int, date: Date)] {
        guard manager.fileExists(atPath: directory.path) else { return [] }
        return try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey])
            .filter { $0.pathExtension == "jsonl" }
            .map { url in
                let v = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                return (url: url, size: v.fileSize ?? 0, date: v.creationDate ?? .distantPast)
            }.sorted { $0.date < $1.date }
    }
}
