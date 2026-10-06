import Foundation
import CryptoKit
import FileProvider
import os

/// Fixed vocabulary: callers cannot accidentally submit document text or error descriptions.
enum DebugLogStep: String, Codable {
    case launch, bookmarkLoad, bookmarkResolve, bookmarkCreate, securityScope, securityScopeRelease
    case vaultOpen, vaultCreate, enumeration, metadata, preview, noteCreate, noteRead, noteSave
    case coordinationRead, coordinationWrite, fileRead, fileWrite, imageRead, imagePrepare
    case imageImport, imageEncode, textFormat, firstUsableScreen, memoryWarning, droppedEntries
}
enum DebugLogResult: String, Codable {
    case started, success, failure, cancellation, timeout, abandonment, finishedLater, observation
}
enum DebugLogError: String, Codable {
    case missingFile, permission, invalidBookmark, invalidText, coordination, unreadableImage
    case providerUnavailable, unavailableDownload, unknown

    static let permittedCodes = [NSFileReadNoSuchFileError, NSFileNoSuchFileError,
        NSFileReadNoPermissionError, NSFileWriteNoPermissionError, NSFileReadCorruptFileError,
        NSUbiquitousFileUnavailableError]

    static func classify(_ error: Error?, step: DebugLogStep) -> (DebugLogError, Int?) {
        if let error = error as? VaultError, error == .noteMissing { return (.missingFile, nil) }
        if let error {
            let e = error as NSError
            if e.domain == NSCocoaErrorDomain {
                switch e.code {
                case NSFileReadNoSuchFileError, NSFileNoSuchFileError: return (.missingFile, e.code)
                case NSFileReadNoPermissionError, NSFileWriteNoPermissionError: return (.permission, e.code)
                case NSUbiquitousFileUnavailableError: return (.unavailableDownload, e.code)
                case NSFileReadCorruptFileError:
                    switch step {
                    case .bookmarkResolve: return (.invalidBookmark, e.code)
                    case .coordinationRead, .coordinationWrite: return (.coordination, e.code)
                    case .imageRead, .imagePrepare, .imageEncode, .imageImport: return (.unreadableImage, e.code)
                    case .preview, .noteRead: return (.invalidText, e.code)
                    default: return (.unknown, e.code)
                    }
                default: break
                }
            }
            if e.domain == NSFileProviderErrorDomain {
                switch e.code {
                case NSFileProviderError.Code.serverUnreachable.rawValue: return (.providerUnavailable, nil)
                case NSFileProviderError.Code.noSuchItem.rawValue: return (.missingFile, nil)
                case NSFileProviderError.Code.notAuthenticated.rawValue: return (.permission, nil)
                default: break
                }
            }
        }
        switch step {
        case .coordinationRead, .coordinationWrite: return (.coordination, nil)
        case .imageRead, .imagePrepare, .imageEncode: return (.unreadableImage, nil)
        default: return (.unknown, nil)
        }
    }
}

struct DebugLogEntry: Codable {
    let schemaVersion: Int
    let timestamp: Date
    let elapsedSeconds: Double
    let severity: String
    let step: DebugLogStep
    let result: DebugLogResult
    let appVersion: String
    let build: String
    let launchID: UUID
    let actionID: UUID
    let parentActionID: UUID?
    let fileID: String?
    let durationSeconds: Double?
    let count: Int?
    let bytes: Int?
    let errorCategory: DebugLogError?
    let errorCode: Int?
}

final class DebugLog {
    static let shared = DebugLog()
    @TaskLocal static var currentAction: UUID?
    @TaskLocal static var currentScope: DebugLogAction?
    let launchID = UUID()
    private let origin = ProcessInfo.processInfo.systemUptime
    private let salt = SymmetricKey(size: .bits256)
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pending = 0
    private var lost = 0
    private let store: DebugLogStore
    private let maintenance: DispatchSourceTimer
    private let appleLog = OSLog(subsystem: "com.lukeryan.flint", category: "DebugLog")
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"

    init(directory: URL? = nil, queue: DispatchQueue = DispatchQueue(label: "flint.debug-log", qos: .utility)) {
        self.queue = queue
        // URL construction only; directory creation and all file access happen on the writer.
        let base = directory ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/DebugLogs", isDirectory: true)
        store = DebugLogStore(directory: base)
        maintenance = DispatchSource.makeTimerSource(queue: queue)
        maintenance.schedule(deadline: .now(), repeating: .seconds(3600), leeway: .seconds(60))
        maintenance.setEventHandler { [store] in try? store.prune() }
        maintenance.resume()
        queue.async { [store] in try? store.prune() }
    }

    deinit { maintenance.cancel() }

    func begin(_ step: DebugLogStep, file: URL? = nil, parent: UUID? = DebugLog.currentAction) -> DebugLogAction {
        DebugLogAction(log: self, step: step, fileID: file.map(fileIdentifier), parent: parent)
    }

    func measure<T>(_ step: DebugLogStep, file: URL? = nil, _ body: () throws -> T) rethrows -> T {
        let action = begin(step, file: file)
        return try Self.$currentAction.withValue(action.id) {
            do {
                let value = try body()
                action.finish(.success)
                return value
            } catch {
                action.finish(.failure, error: error)
                throw error
            }
        }
    }

    @MainActor
    func measureAsync<T>(_ step: DebugLogStep, file: URL? = nil, _ body: () async -> T) async -> T {
        let action = begin(step, file: file)
        return await Self.$currentAction.withValue(action.id) {
            await Self.$currentScope.withValue(action) {
                let value = await body()
                action.finish(.success)
                return value
            }
        }
    }

    func handledFailure(_ error: Error) { Self.currentScope?.finish(.failure, error: error) }

    func observe(_ step: DebugLogStep, count: Int? = nil, bytes: Int? = nil) {
        let action = begin(step)
        action.finish(.success, count: count, bytes: bytes)
    }

    /// The only reader API: complete, validated records, never vault access. Callback is on the writer.
    func snapshot(completion: @escaping (Data) -> Void) {
        queue.async { [store] in completion((try? store.snapshot()) ?? Data()) }
    }

    private func fileIdentifier(_ url: URL) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(url.absoluteString.utf8), using: salt)
            .prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    fileprivate func signpost(_ action: DebugLogAction, begin: Bool) {
        let id = OSSignpostID(log: appleLog, object: action)
        os_signpost(begin ? .begin : .end, log: appleLog, name: "Flint action", signpostID: id,
                    "%{public}s %{public}s", action.step.rawValue, action.id.uuidString)
    }

    fileprivate func record(_ action: DebugLogAction, result: DebugLogResult, error: Error? = nil,
                            count: Int? = nil, bytes: Int? = nil) {
        let classified = (error != nil || result == .failure)
            ? DebugLogError.classify(error, step: action.step) : nil
        let now = ProcessInfo.processInfo.systemUptime
        let entry = DebugLogEntry(schemaVersion: 1, timestamp: Date(), elapsedSeconds: now - origin,
            severity: result == .failure || result == .timeout ? "error" : "info",
            step: action.step, result: result, appVersion: version, build: build, launchID: launchID,
            actionID: action.id, parentActionID: action.parent, fileID: action.fileID,
            durationSeconds: result == .started ? nil : now - action.start, count: count.map { max(0, $0) },
            bytes: bytes.map { max(0, $0) }, errorCategory: classified?.0, errorCode: classified?.1)
        // Never wait for disk or a slow writer. Only the small admission counter is locked.
        lock.lock()
        guard pending < 512 else { lost = min(lost + 1, Int.max - 1); lock.unlock(); return }
        pending += 1
        lock.unlock()
        queue.async { [self] in
            defer { lock.lock(); pending -= 1; lock.unlock() }
            os_log("%{public}s %{public}s %{public}s", log: appleLog, type: entry.severity == "error" ? .error : .info,
                   entry.step.rawValue, entry.result.rawValue, entry.actionID.uuidString)
            do {
                lock.lock(); let dropped = lost; lock.unlock()
                if dropped > 0 {
                    let counter = DebugLogEntry(schemaVersion: 1, timestamp: entry.timestamp,
                        elapsedSeconds: entry.elapsedSeconds, severity: "info", step: .droppedEntries,
                        result: .observation, appVersion: version, build: build, launchID: launchID,
                        actionID: UUID(), parentActionID: nil, fileID: nil, durationSeconds: nil,
                        count: dropped, bytes: nil, errorCategory: nil, errorCode: nil)
                    try store.append(counter)
                    // New losses may arrive while writing. Remove only the persisted count.
                    lock.lock(); lost -= dropped; lock.unlock()
                }
                try store.append(entry)
            } catch {
                // Storage errors are loss counters, never recursively logged or thrown into editing.
                lock.lock(); lost = min(lost + 1, Int.max - 1); lock.unlock()
            }
        }
    }
}

final class DebugLogAction {
    let id = UUID()
    fileprivate let step: DebugLogStep
    fileprivate let parent: UUID?
    fileprivate let fileID: String?
    fileprivate let start = ProcessInfo.processInfo.systemUptime
    private let log: DebugLog
    private let lock = NSLock()
    private var terminal: DebugLogResult?
    private var lateRecorded = false

    fileprivate init(log: DebugLog, step: DebugLogStep, fileID: String?, parent: UUID?) {
        self.log = log; self.step = step; self.fileID = fileID; self.parent = parent
        log.record(self, result: .started)
        log.signpost(self, begin: true)
    }

    func finish(_ result: DebugLogResult, error: Error? = nil, count: Int? = nil, bytes: Int? = nil) {
        guard [.success, .failure, .cancellation, .timeout, .abandonment].contains(result) else { return }
        lock.lock()
        if let terminal {
            let late = (terminal == .timeout || terminal == .cancellation) && !lateRecorded
                && (result == .success || result == .failure)
            if late { lateRecorded = true }
            lock.unlock()
            if late { log.record(self, result: .finishedLater, error: error, count: count, bytes: bytes) }
            return
        }
        terminal = result
        lock.unlock()
        log.record(self, result: result, error: error, count: count, bytes: bytes)
        log.signpost(self, begin: false)
    }

    deinit { if terminal == nil { finish(.abandonment) } }
}
