import Foundation

/// UI completion is independent of accessor completion. A cancelled worker continues to own its slot and scopes.
struct ProviderFailure: LocalizedError {
    enum Reason: Equatable { case cancelled, timedOut, busy, draining, queueFull }
    let reason: Reason
    let operationID: UUID
    let uncertainMutation: Bool
    var errorDescription: String? {
        switch reason {
        case .cancelled: return uncertainMutation ? "Cancelled. The file change may still finish." : "The operation was cancelled."
        case .timedOut: return uncertainMutation ? "The file change is taking too long and may still finish." : "The provider did not respond within 30 foreground seconds."
        case .busy: return "Provider workers are still occupied. Try again when previous work stops."
        case .draining: return "Previous work for this vault is still stopping."
        case .queueFull: return "Too many file requests are waiting. Please try again."
        }
    }
}

final class ForegroundClock {
    static let shared = ForegroundClock()
    private let lock = NSLock()
    private let clock: () -> Double
    private var active: Bool
    private var accumulated = 0.0
    private var last: Double
    init(active: Bool = true, clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.active = active; self.clock = clock; last = clock()
    }
    var time: Double {
        lock.lock(); defer { lock.unlock() }
        return accumulated + (active ? max(0, clock() - last) : 0)
    }
    func setActive(_ value: Bool) {
        lock.lock(); let now = clock()
        if active { accumulated += max(0, now - last) }
        last = now; active = value; lock.unlock()
    }
}

final class ProviderAttempt {
    enum MutationOutcome { case running, notStarted, completed(Result<URL?, Error>) }
    let id = UUID()
    private let clock: ForegroundClock
    private let origin: Double
    private let budget: Double
    private let lock = NSLock()
    private var cancellation = false
    private var handlers: [UUID: () -> Void] = [:]
    private var mutations: [UUID: MutationOutcome] = [:]
    private var currentStage: DebugLogStep = .vaultOpen
    init(clock: ForegroundClock = .shared, budget: Double = 30) {
        self.clock = clock; self.budget = budget; origin = clock.time
    }
    var elapsed: Double { max(0, clock.time - origin) }
    var expired: Bool { elapsed >= budget }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancellation }
    var stage: DebugLogStep { lock.lock(); defer { lock.unlock() }; return currentStage }
    func setStage(_ stage: DebugLogStep) { lock.lock(); currentStage = stage; lock.unlock() }
    func cancel() {
        lock.lock(); cancellation = true; let callbacks = Array(handlers.values); lock.unlock()
        callbacks.forEach { $0() }
    }
    fileprivate func register(_ id: UUID, handler: @escaping () -> Void) {
        lock.lock(); handlers[id] = handler; let cancelled = cancellation; lock.unlock()
        if cancelled { handler() }
    }
    fileprivate func unregister(_ id: UUID) { lock.lock(); handlers.removeValue(forKey: id); lock.unlock() }
    fileprivate func mutation(_ id: UUID, outcome: MutationOutcome) { lock.lock(); mutations[id] = outcome; lock.unlock() }
    var mutationIdentity: UUID? { lock.lock(); defer { lock.unlock() }; return mutations.keys.first }
    func mutationOutcome(_ id: UUID) -> MutationOutcome? { lock.lock(); defer { lock.unlock() }; return mutations[id] }
}

struct ProviderRequest {
    enum Priority: Int { case optional = 0, explicit = 1 }
    let vaultURL: URL?
    let attempt: ProviderAttempt
    var priority: Priority = .explicit
    init(vaultURL: URL?, attempt: ProviderAttempt = ProviderAttempt(), priority: Priority = .explicit) {
        self.vaultURL = vaultURL; self.attempt = attempt; self.priority = priority
    }
    fileprivate var key: String { vaultURL?.standardizedFileURL.absoluteString ?? "unresolved-bookmark" }
}

final class SecurityScopeLease {
    let url: URL
    private let granted: Bool
    private let stop: (URL) -> Void
    init(url: URL, start: (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
         stop: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }) {
        precondition(!Thread.isMainThread)
        self.url = url; self.stop = stop
        let action = DebugLog.shared.begin(.securityScope, file: url)
        granted = start(url); action.finish(.success, count: granted ? 1 : 0)
    }
    deinit {
        guard granted else { return }
        let url = url, stop = stop
        let release = { DebugLog.shared.measure(.securityScopeRelease, file: url) { stop(url) } }
        if Thread.isMainThread { DispatchQueue.global(qos: .utility).async(execute: release) }
        else { release() }
    }
}

protocol ProviderCoordinating: AnyObject {
    func read(at url: URL, accessor: (URL) -> Void) throws
    func write(at url: URL, accessor: (URL) -> Void) throws
    func cancel()
}
final class SystemProviderCoordinator: ProviderCoordinating {
    private let coordinator = NSFileCoordinator()
    func read(at url: URL, accessor: (URL) -> Void) throws {
        var error: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &error, byAccessor: accessor)
        if let error { throw error }
    }
    func write(at url: URL, accessor: (URL) -> Void) throws {
        var error: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &error, byAccessor: accessor)
        if let error { throw error }
    }
    func cancel() { coordinator.cancel() }
}

final class ProviderWorkContext {
    let attempt: ProviderAttempt
    fileprivate var leases: [SecurityScopeLease] = []
    var primaryLease: SecurityScopeLease? { leases.first }
    private let factory: () -> ProviderCoordinating
    private let log: DebugLog
    private let lock = NSLock()
    private var cancelled = false
    private var coordinators: [ProviderCoordinating] = []
    init(attempt: ProviderAttempt, factory: @escaping () -> ProviderCoordinating, log: DebugLog) {
        self.attempt = attempt; self.factory = factory; self.log = log
    }
    func checkCancellation() throws {
        lock.lock(); let cancelled = cancelled; lock.unlock()
        if cancelled || attempt.cancelled || attempt.expired { throw CancellationError() }
    }
    fileprivate func cancel() {
        lock.lock(); cancelled = true; let coordinators = coordinators; lock.unlock()
        // Cancellation never waits for a provider on the deadline sampler or the UI thread.
        DispatchQueue.global(qos: .utility).async { coordinators.forEach { $0.cancel() } }
    }
    func coordinated<T>(_ step: DebugLogStep, at url: URL, _ accessor: (URL) throws -> T) throws -> T {
        try checkCancellation()
        let coordinator = factory()
        lock.lock(); coordinators.append(coordinator); let cancelled = cancelled; lock.unlock()
        if cancelled { coordinator.cancel(); throw CancellationError() }
        let waiting = log.begin(step, file: url)
        attempt.setStage(step)
        var result: Result<T, Error>?
        do {
            let body: (URL) -> Void = { coordinatedURL in
                waiting.finish(.success)
                result = Result {
                    try self.checkCancellation()
                    let stage: DebugLogStep = step == .coordinationRead ? .fileRead : .fileWrite
                    self.attempt.setStage(stage)
                    return try self.log.measure(stage, file: url) { try accessor(coordinatedURL) }
                }
            }
            if step == .coordinationRead { try coordinator.read(at: url, accessor: body) }
            else { try coordinator.write(at: url, accessor: body) }
        } catch { waiting.finish(.failure, error: error); throw error }
        guard let result else { waiting.finish(.failure); throw VaultError.inaccessibleVault }
        return try result.get()
    }
}

private class ProviderJob {
    var id: UUID { action.id }
    let request: ProviderRequest
    let step: DebugLogStep
    let mutation: Bool
    let resources: [URL]
    let context: ProviderWorkContext
    let action: DebugLogAction
    var started = false
    var terminal = false
    var actualError: Error?
    init(request: ProviderRequest, step: DebugLogStep, mutation: Bool, resources: [URL], factory: @escaping () -> ProviderCoordinating, log: DebugLog) {
        self.request = request; self.step = step; self.mutation = mutation; self.resources = resources
        context = ProviderWorkContext(attempt: request.attempt, factory: factory, log: log)
        action = log.begin(step, file: request.vaultURL)
    }
    func execute() -> () -> Void { fatalError("abstract") }
    func fail(_ reason: ProviderFailure.Reason) -> () -> Void { fatalError("abstract") }
}
private final class TypedProviderJob<T>: ProviderJob {
    let work: (ProviderWorkContext) throws -> T
    let continuation: CheckedContinuation<T, Error>
    init(request: ProviderRequest, step: DebugLogStep, mutation: Bool, resources: [URL],
         factory: @escaping () -> ProviderCoordinating, log: DebugLog, continuation: CheckedContinuation<T, Error>,
         work: @escaping (ProviderWorkContext) throws -> T) {
        self.work = work; self.continuation = continuation
        super.init(request: request, step: step, mutation: mutation, resources: resources, factory: factory, log: log)
    }
    override func execute() -> () -> Void {
        let result: Result<T, Error> = Result { try context.checkCancellation(); return try work(context) }
        if case let .failure(error) = result { actualError = error }
        if mutation { request.attempt.mutation(id, outcome: .completed(result.map { $0 as? URL })) }
        return { self.continuation.resume(with: result) }
    }
    override func fail(_ reason: ProviderFailure.Reason) -> () -> Void {
        let failure = ProviderFailure(reason: reason, operationID: id, uncertainMutation: mutation && started)
        if mutation && !started { request.attempt.mutation(id, outcome: .notStarted) }
        return { self.continuation.resume(throwing: failure) }
    }
}

/// Two global blocking slots, one per root, 32 pending jobs. Draining workers retain their slot until actual return.
final class ProviderExecutor {
    static let shared = ProviderExecutor()
    static let decodeLane = ProviderExecutor(limit: 1)
    private let lock = NSLock()
    private let workers = DispatchQueue(label: "flint.provider-workers", qos: .userInitiated, attributes: .concurrent)
    private let sampler: DispatchSourceTimer
    private let limit: Int
    private let pendingLimit: Int
    private let log: DebugLog
    private let factory: () -> ProviderCoordinating
    private let startScope: (URL) -> Bool
    private let stopScope: (URL) -> Void
    private let workerDidFinish: () -> Void
    private var pending: [ProviderJob] = []
    private var running: [UUID: ProviderJob] = [:]

    init(limit: Int = 2, pendingLimit: Int = 32, log: DebugLog = .shared, automaticSampling: Bool = true,
         coordinatorFactory: @escaping () -> ProviderCoordinating = { SystemProviderCoordinator() },
         startScope: @escaping (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
         stopScope: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() },
         workerDidFinish: @escaping () -> Void = {}) {
        self.workerDidFinish = workerDidFinish
        self.limit = limit; self.pendingLimit = pendingLimit; self.log = log; factory = coordinatorFactory
        self.startScope = startScope; self.stopScope = stopScope
        sampler = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "flint.provider-deadlines", qos: .utility))
        sampler.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250), leeway: .milliseconds(50))
        if automaticSampling { sampler.setEventHandler { [weak self] in self?.sample() } }
        sampler.resume()
    }
    deinit { sampler.cancel() }

    func execute<T>(_ request: ProviderRequest, step: DebugLogStep, mutation: Bool = false,
                    resources: [URL] = [], work: @escaping (ProviderWorkContext) throws -> T) async throws -> T {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let job = TypedProviderJob(request: request, step: step, mutation: mutation,
                    resources: ([request.vaultURL].compactMap { $0 } + resources).reduce(into: [URL]()) { values, url in
                        if !values.contains(url) { values.append(url) }
                    }, factory: factory, log: log, continuation: continuation, work: work)
                admit(job)
            }
        } onCancel: { request.attempt.cancel() }
    }

    private func admit(_ job: ProviderJob) {
        lock.lock()
        let failure: ProviderFailure.Reason?
        if job.request.attempt.cancelled { failure = .cancelled }
        else if job.request.attempt.expired { failure = .timedOut }
        else if running.values.contains(where: { $0.request.key == job.request.key && $0.terminal }) { failure = .draining }
        else if running.count == limit && running.values.allSatisfy({ $0.terminal }) { failure = .busy }
        else if pending.count >= pendingLimit && !(running.count < limit && !running.values.contains(where: { $0.request.key == job.request.key })) { failure = .queueFull }
        else { failure = nil }
        if let failure {
            let complete = job.fail(failure); lock.unlock()
            job.action.finish(failure == .cancelled ? .cancellation : failure == .timedOut ? .timeout : .failure)
            complete(); return
        }
        pending.append(job)
        let starts = schedule()
        lock.unlock()
        job.request.attempt.register(job.id) { [weak self] in self?.cancel(job.id, reason: .cancelled) }
        starts.forEach(dispatch)
    }
    /// Caller holds lock; explicit requests precede optional requests, with FIFO within a priority.
    private func schedule() -> [ProviderJob] {
        var starts: [ProviderJob] = []
        while running.count < limit {
            let candidates = pending.indices.filter { index in
                !running.values.contains { $0.request.key == pending[index].request.key }
            }
            guard let index = candidates.max(by: { pending[$0].request.priority.rawValue < pending[$1].request.priority.rawValue }) else { break }
            let priority = pending[index].request.priority
            let first = candidates.first { pending[$0].request.priority == priority }!
            let job = pending.remove(at: first)
            job.started = true; running[job.id] = job
            if job.mutation { job.request.attempt.mutation(job.id, outcome: .running) }
            starts.append(job)
        }
        return starts
    }
    private func dispatch(_ job: ProviderJob) {
        workers.async { [self] in
            for url in job.resources {
                guard (try? job.context.checkCancellation()) != nil else { break }
                job.request.attempt.setStage(.securityScope)
                job.context.leases.append(SecurityScopeLease(url: url, start: startScope, stop: stopScope))
            }
            job.request.attempt.setStage(job.step)
            let callback = DebugLog.$currentAction.withValue(job.action.id) { job.execute() }
            // Release worker-owned resources on this worker, before handing back its capacity.
            job.context.leases = []
            lock.lock()
            var deliver: (() -> Void)? = job.terminal ? nil : callback
            if !job.terminal && (job.request.attempt.cancelled || job.request.attempt.expired) {
                let reason: ProviderFailure.Reason = job.request.attempt.cancelled ? .cancelled : .timedOut
                deliver = job.fail(reason)
                job.action.finish(reason == .cancelled ? .cancellation : .timeout)
            }
            job.terminal = true; running.removeValue(forKey: job.id)
            job.action.finish(job.actualError == nil ? .success : .failure, error: job.actualError)
            let starts = schedule()
            lock.unlock()
            job.request.attempt.unregister(job.id)
            workerDidFinish()
            deliver?()
            starts.forEach(dispatch)
        }
    }
    private func cancel(_ id: UUID, reason: ProviderFailure.Reason) {
        lock.lock()
        let queued = pending.firstIndex { $0.id == id }
        guard let job = queued.map({ pending[$0] }) ?? running[id], !job.terminal else { lock.unlock(); return }
        job.terminal = true
        if let queued { pending.remove(at: queued) }
        let complete = job.fail(reason)
        let starts = schedule()
        job.action.finish(reason == .timedOut ? .timeout : .cancellation)
        lock.unlock()
        complete(); job.context.cancel()
        if queued != nil { job.request.attempt.unregister(id) }
        starts.forEach(dispatch)
    }
    /// Deterministic tests advance their clock and invoke this directly; production uses the independent sampler.
    func sample() {
        lock.lock(); let expired = (pending + Array(running.values)).filter { !$0.terminal && $0.request.attempt.expired }.map(\.id); lock.unlock()
        expired.forEach { cancel($0, reason: .timedOut) }
    }
    var counts: (active: Int, pending: Int) {
        lock.lock(); defer { lock.unlock() }; return (running.count, pending.count)
    }
}
