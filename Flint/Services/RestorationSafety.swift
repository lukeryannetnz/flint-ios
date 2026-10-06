import Foundation

protocol RestorationSafetyChecking {
    func begin(launchID: UUID, explicit: Bool) async -> Bool
    func finish(completed: Bool) async
}

/// A separate writer and a bounded logical wait: late disk completion never starts provider work.
final class RestorationSafety: RestorationSafetyChecking {
    static let shared = RestorationSafety()
    struct Marker: Codable {
        enum State: String, Codable { case started, completed, abandoned }
        let version: Int
        let launchID: UUID
        let actionID: UUID
        let timestamp: Date
        let state: State
    }
    private let queue: DispatchQueue
    private let directory: URL
    private let timeout: TimeInterval
    private let terminalStaged: () -> Void
    private let admission = NSLock()
    private var writerOccupied = false
    // Writer-owned. It must never be reset by a second, overlapping attempt.
    private var current: Marker?

    init(directory: URL? = nil, timeout: TimeInterval = 1,
         queue: DispatchQueue = DispatchQueue(label: "flint.restoration-safety", qos: .utility),
         terminalStaged: @escaping () -> Void = {}) {
        self.directory = directory ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/RestorationSafety", isDirectory: true)
        self.timeout = timeout
        self.queue = queue
        self.terminalStaged = terminalStaged
    }

    func begin(launchID: UUID, explicit: Bool = false) async -> Bool {
        await bounded { _ in
            let url = self.directory.appendingPathComponent("marker.json")
            if !explicit {
                do {
                    guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max <= 4096 else { return false }
                    let data = try Data(contentsOf: url)
                    let marker = try JSONDecoder().decode(Marker.self, from: data)
                    guard marker.version == 1, marker.state != .started else { return false }
                } catch CocoaError.fileReadNoSuchFile {
                    // Only confirmed absence permits first-use restoration.
                }
            }
            let marker = Marker(version: 1, launchID: launchID, actionID: UUID(), timestamp: Date(), state: .started)
            try self.write(marker)
            self.current = marker
            return true
        }
    }

    func finish(completed: Bool) async {
        _ = await bounded { result in
            let old: Marker
            if let current = self.current { old = current }
            else {
                let url = self.directory.appendingPathComponent("marker.json")
                guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max <= 4096 else { return false }
                old = try JSONDecoder().decode(Marker.self, from: Data(contentsOf: url))
                guard old.version == 1, old.state == .started else { return false }
            }
            // Keep the authoritative started marker intact throughout potentially slow I/O.
            let staged = self.directory.appendingPathComponent("terminal.json")
            try self.write(Marker(version: 1, launchID: old.launchID, actionID: old.actionID,
                                  timestamp: Date(), state: completed ? .completed : .abandoned), to: staged)
            self.terminalStaged()
            // Publication is admitted only if success wins the race with the deadline.
            // A crash or failed rename after admission still leaves recovery conservative.
            guard result.admitPublication() else { return false }
            let authoritative = self.directory.appendingPathComponent("marker.json")
            guard rename(staged.path, authoritative.path) == 0 else { return false }
            self.current = nil
            return true
        }
    }

    private func write(_ marker: Marker, to destination: URL? = nil) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var folder = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let url = destination ?? directory.appendingPathComponent("marker.json")
        try JSONEncoder().encode(marker).write(to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    private func admit() -> Bool {
        admission.lock(); defer { admission.unlock() }
        guard !writerOccupied else { return false }
        writerOccupied = true
        return true
    }

    private func releaseWriter() {
        admission.lock(); writerOccupied = false; admission.unlock()
    }

    private func bounded(_ work: @escaping (SafetyResult) throws -> Bool) async -> Bool {
        guard admit() else { return false }
        return await withCheckedContinuation { continuation in
            let result = SafetyResult(continuation, timeout: timeout)
            queue.async {
                let value = (try? work(result)) ?? false
                self.releaseWriter()
                result.resolve(value)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { result.timeout() }
        }
    }
}

private final class SafetyResult {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private let deadline: TimeInterval
    init(_ continuation: CheckedContinuation<Bool, Never>, timeout: TimeInterval) {
        self.continuation = continuation
        deadline = ProcessInfo.processInfo.systemUptime + timeout
    }
    private var publicationAdmitted = false
    func admitPublication() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard continuation != nil, ProcessInfo.processInfo.systemUptime < deadline else { return false }
        publicationAdmitted = true
        return true
    }
    func timeout() {
        lock.lock()
        let accepted = publicationAdmitted
        let pending = continuation; continuation = nil
        lock.unlock()
        pending?.resume(returning: accepted)
    }
    func resolve(_ value: Bool) {
        lock.lock(); let pending = continuation; continuation = nil; lock.unlock()
        pending?.resume(returning: value)
    }
}
