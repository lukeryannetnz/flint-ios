import Foundation

struct DiagnosticShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Recovery-only snapshot. The full category/time preview and history controls are phase 6.
final class DiagnosticShareStore {
    static let shared = DiagnosticShareStore()
    private struct Manifest: Encodable {
        let schemaVersion = 1
        let createdAt = Date()
        let eventCount: Int
        let platformReportCount: Int
        let omittedRecords: Int
        let limitations = ["Platform reports may be absent or delayed.", "Originating launch correlation is unknown.",
                           "An interrupted launch or heartbeat gap does not prove a crash."]
    }
    private struct EventRecord: Encodable { let kind = "event"; let event: DebugLogEntry }
    private struct ReportRecord: Encodable { let kind = "platformReport"; let report: SavedPlatformReport }
    private let queue = DispatchQueue(label: "flint.diagnostic-share", qos: .utility)
    private let lock = NSLock()
    private var occupied = false
    private let log: DebugLog
    private let directory: URL
    private let limit: Int
    private let timeout: Double

    init(log: DebugLog = .shared, directory: URL? = nil, limit: Int = 20 * 1024 * 1024, timeout: Double = 5) {
        self.log = log; self.limit = limit; self.timeout = timeout
        self.directory = directory ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Caches/DiagnosticShare", isDirectory: true)
        queue.async { [self] in try? FileManager.default.removeItem(at: self.directory) }
    }

    private func admit() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !occupied else { return false }; occupied = true; return true
    }
    private func release() { lock.lock(); occupied = false; lock.unlock() }
    func cleanup() { queue.async { [self] in try? FileManager.default.removeItem(at: directory); release() } }

    func stage() async throws -> URL {
        guard admit() else { throw CocoaError(.fileWriteUnknown) }
        return try await withCheckedThrowingContinuation { continuation in
            let result = ShareResult(continuation)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                result.resolve(.failure(CocoaError(.fileReadUnknown)))
            }
            log.snapshot { [self] events in
                log.platformSnapshot { [self] reports in
                    queue.async { [self] in
                        do {
                            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                            let entries = events.split(separator: 10).compactMap { try? decoder.decode(DebugLogEntry.self, from: Data($0)) }
                            let payloads = (try? decoder.decode([SavedPlatformReport].self, from: reports)) ?? []
                            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                            var records = Data(); var keptEvents = 0; var keptReports = 0; var omitted = 0
                            func append<T: Encodable>(_ value: T) throws -> Bool {
                                let data = try encoder.encode(value)
                                guard records.count + data.count + 1 <= limit - 1024 else { omitted += 1; return false }
                                records.append(data); records.append(10); return true
                            }
                            for entry in entries { if try append(EventRecord(event: entry)) { keptEvents += 1 } }
                            for report in payloads { if try append(ReportRecord(report: report)) { keptReports += 1 } }
                            var data = try encoder.encode(Manifest(eventCount: keptEvents, platformReportCount: keptReports, omittedRecords: omitted))
                            data.append(10); data.append(records)
                            guard data.count <= limit else { throw CocoaError(.fileWriteOutOfSpace) }
                            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
                            var folder = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
                            try folder.setResourceValues(values)
                            let url = directory.appendingPathComponent("Flint-diagnostics.jsonl")
                            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                            if !result.resolve(.success(url)) { cleanup() }
                        } catch { _ = result.resolve(.failure(error)); cleanup() }
                    }
                }
            }
        }
    }
}

private final class ShareResult {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    init(_ continuation: CheckedContinuation<URL, Error>) { self.continuation = continuation }
    @discardableResult func resolve(_ result: Result<URL, Error>) -> Bool {
        lock.lock(); let pending = continuation; continuation = nil; lock.unlock()
        pending?.resume(with: result); return pending != nil
    }
}
