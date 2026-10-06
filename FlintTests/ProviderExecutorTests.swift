import XCTest
@testable import Flint

@MainActor
final class ProviderExecutorTests: XCTestCase {
    func testTimeoutBeforeAndInsideAccessorReturnsWithoutWaitingAndRetainsLeases() async throws {
        for before in [true, false] {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            let log = DebugLog(directory: folder)
            let time = TestTime(); let clock = ForegroundClock(clock: { time.now })
            let attempt = ProviderAttempt(clock: clock)
            let root = URL(fileURLWithPath: "/tmp/provider-a")
            let source = URL(fileURLWithPath: "/tmp/provider-source")
            let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
            let entered = expectation(description: "blocked stage")
            let cancelled = expectation(description: "coordinator cancellation")
            let counts = ScopeCounts()
            let coordinator = TestCoordinator(before: before, entered: entered, gate: gate, cancelled: cancelled)
            let executor = ProviderExecutor(log: log, automaticSampling: false,
                coordinatorFactory: { coordinator }, startScope: { counts.start($0); return true }, stopScope: { counts.stop($0) })
            let request = ProviderRequest(vaultURL: root, attempt: attempt)
            let value = root.appendingPathComponent("Created.md")
            let task = Task {
                try await executor.execute(request, step: .noteCreate, mutation: true, resources: [source]) { context in
                    try context.coordinated(.coordinationWrite, at: root) { _ in
                        if !before { entered.fulfill(); gate.wait() }
                        return value
                    }
                }
            }
            await fulfillment(of: [entered], timeout: 2)
            XCTAssertEqual(counts.started, 2); XCTAssertEqual(counts.stopped, 0)
            time.advance(30); executor.sample()
            let failure: ProviderFailure
            do { _ = try await task.value; XCTFail("Expected timeout"); return }
            catch { failure = try XCTUnwrap(error as? ProviderFailure) }
            XCTAssertEqual(failure.reason, .timedOut); XCTAssertTrue(failure.uncertainMutation)
            XCTAssertEqual(executor.counts.active, 1); XCTAssertEqual(counts.stopped, 0)
            await fulfillment(of: [cancelled], timeout: 2)
            do {
                _ = try await executor.execute(ProviderRequest(vaultURL: root), step: .noteRead) { _ in 1 }
                XCTFail("A draining vault must reject retry")
            } catch { XCTAssertEqual((error as? ProviderFailure)?.reason, .draining) }
            let other = try await executor.execute(ProviderRequest(vaultURL: URL(fileURLWithPath: "/tmp/provider-b")), step: .noteRead) { _ in
                XCTAssertFalse(Thread.isMainThread); return 42
            }
            XCTAssertEqual(other, 42); XCTAssertEqual(executor.counts.active, 1)
            gate.signal(); await until { executor.counts.active == 0 }
            XCTAssertEqual(counts.started, counts.stopped)
            switch attempt.mutationOutcome(failure.operationID) {
            case .completed(.failure) where before: break
            case let .completed(.success(url)) where !before: XCTAssertEqual(url, value)
            default: XCTFail("Actual mutation outcome must remain available")
            }
            let data: Data = await withCheckedContinuation { continuation in log.snapshot { continuation.resume(returning: $0) } }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let events = try data.split(separator: 10).map { try decoder.decode(DebugLogEntry.self, from: Data($0)) }
                .filter { $0.actionID == failure.operationID }
            XCTAssertEqual(events.filter { [.success, .failure, .timeout, .cancellation, .abandonment].contains($0.result) }.count, 1)
            XCTAssertEqual(events.filter { $0.result == .timeout }.count, 1)
            XCTAssertEqual(events.filter { $0.result == .finishedLater }.count, 1)
        }
    }

    func testTwoDrainingWorkersReturnBusyForAnotherVaultWithoutAddingWorkers() async throws {
        let time = TestTime(), gate = DispatchSemaphore(value: 0)
        let clock = ForegroundClock(clock: { time.now })
        let executor = ProviderExecutor(automaticSampling: false, startScope: { _ in false })
        let entered = expectation(description: "two blocked workers"); entered.expectedFulfillmentCount = 2
        let tasks = ["a", "b"].map { name in
            Task {
                try await executor.execute(ProviderRequest(vaultURL: URL(fileURLWithPath: "/tmp/\(name)"),
                    attempt: ProviderAttempt(clock: clock)), step: .enumeration) { _ in
                    entered.fulfill(); gate.wait(); return 1
                }
            }
        }
        defer { gate.signal(); gate.signal() }
        await fulfillment(of: [entered], timeout: 2)
        time.advance(30); executor.sample()
        for task in tasks {
            do { _ = try await task.value; XCTFail("Expected timeout") }
            catch { XCTAssertEqual((error as? ProviderFailure)?.reason, .timedOut) }
        }
        do {
            _ = try await executor.execute(ProviderRequest(vaultURL: URL(fileURLWithPath: "/tmp/c")), step: .vaultOpen) { _ in
                XCTFail("No new worker may run"); return 1
            }
            XCTFail("Expected busy")
        } catch { XCTAssertEqual((error as? ProviderFailure)?.reason, .busy) }
        XCTAssertEqual(executor.counts.active, 2); XCTAssertEqual(executor.counts.pending, 0)
        gate.signal(); gate.signal(); await until { executor.counts.active == 0 }
    }

    func testPendingQueueLimitAndQueuedCancellation() async throws {
        let gate = DispatchSemaphore(value: 0)
        let executor = ProviderExecutor(automaticSampling: false, startScope: { _ in false })
        let entered = expectation(description: "capacity occupied"); entered.expectedFulfillmentCount = 2
        let roots = [URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/b")]
        let blockers = roots.map { root in Task {
            try await executor.execute(ProviderRequest(vaultURL: root), step: .enumeration) { _ in
                entered.fulfill(); gate.wait(); return 0
            }
        } }
        defer { gate.signal(); gate.signal() }
        await fulfillment(of: [entered], timeout: 2)
        let attempts = (0..<32).map { _ in ProviderAttempt() }
        let queued = attempts.map { attempt in Task {
            try await executor.execute(ProviderRequest(vaultURL: roots[0], attempt: attempt), step: .preview) { _ in
                XCTFail("Cancelled queued work must not execute"); return 1
            }
        } }
        await until { executor.counts.pending == 32 }
        do {
            _ = try await executor.execute(ProviderRequest(vaultURL: roots[0]), step: .preview) { _ in 1 }
            XCTFail("Expected queue limit")
        } catch { XCTAssertEqual((error as? ProviderFailure)?.reason, .queueFull) }
        attempts.forEach { $0.cancel() }
        for task in queued {
            do { _ = try await task.value; XCTFail("Expected queued cancellation") }
            catch { XCTAssertEqual((error as? ProviderFailure)?.reason, .cancelled) }
        }
        XCTAssertEqual(executor.counts.pending, 0); XCTAssertEqual(executor.counts.active, 2)
        gate.signal(); gate.signal()
        for task in blockers { _ = try await task.value }
        await until { executor.counts.active == 0 }
    }

    func testExplicitRequestsRunBeforeOptionalRequestsForSameVault() async throws {
        let gate = DispatchSemaphore(value: 0)
        let executor = ProviderExecutor(automaticSampling: false, startScope: { _ in false })
        let root = URL(fileURLWithPath: "/tmp/priorities")
        let entered = expectation(description: "one vault blocked")
        let blocker = Task { try await executor.execute(ProviderRequest(vaultURL: root), step: .enumeration) { _ in
            entered.fulfill(); gate.wait(); return 0
        } }
        defer { gate.signal() }
        await fulfillment(of: [entered], timeout: 2)
        let order = TestOrder()
        let optional = Task {
            try await executor.execute(ProviderRequest(vaultURL: root, priority: .optional), step: .preview) { _ in order.add("optional"); return 1 }
        }
        await until { executor.counts.pending == 1 }
        let explicit = Task {
            try await executor.execute(ProviderRequest(vaultURL: root), step: .noteRead) { _ in order.add("explicit"); return 2 }
        }
        await until { executor.counts.pending == 2 }
        XCTAssertEqual(executor.counts.active, 1)
        gate.signal(); _ = try await blocker.value; _ = try await explicit.value; _ = try await optional.value
        XCTAssertEqual(order.values, ["explicit", "optional"])
    }

    func testForegroundBudgetPausesDuringSuspensionAndIsSharedAcrossStages() async throws {
        let time = TestTime(), gate = DispatchSemaphore(value: 0)
        let clock = ForegroundClock(clock: { time.now })
        let attempt = ProviderAttempt(clock: clock)
        let request = ProviderRequest(vaultURL: URL(fileURLWithPath: "/tmp/budget"), attempt: attempt)
        let executor = ProviderExecutor(automaticSampling: false, startScope: { _ in false })
        _ = try await executor.execute(request, step: .bookmarkResolve) { _ in 1 }
        time.advance(10)
        let entered = expectation(description: "second stage blocked")
        let task = Task { try await executor.execute(request, step: .enumeration) { _ in entered.fulfill(); gate.wait(); return 1 } }
        defer { gate.signal() }
        await fulfillment(of: [entered], timeout: 2)
        clock.setActive(false); time.advance(100); executor.sample()
        XCTAssertEqual(attempt.elapsed, 10); XCTAssertFalse(attempt.expired)
        clock.setActive(true); time.advance(19); executor.sample(); XCTAssertFalse(attempt.expired)
        time.advance(1); executor.sample()
        do { _ = try await task.value; XCTFail("Budget must not reset at the second stage") }
        catch { XCTAssertEqual((error as? ProviderFailure)?.reason, .timedOut) }
        gate.signal(); await until { executor.counts.active == 0 }
    }

    func testTaskCancellationReturnsWhileAccessorStillRuns() async throws {
        let gate = DispatchSemaphore(value: 0)
        let entered = expectation(description: "worker blocked")
        let executor = ProviderExecutor(automaticSampling: false, startScope: { _ in false })
        let task = Task { try await executor.execute(ProviderRequest(vaultURL: URL(fileURLWithPath: "/tmp/cancel")), step: .noteRead) { _ in
            entered.fulfill(); gate.wait(); return 1
        } }
        defer { gate.signal() }
        await fulfillment(of: [entered], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertEqual((error as? ProviderFailure)?.reason, .cancelled) }
        XCTAssertEqual(executor.counts.active, 1)
        gate.signal(); await until { executor.counts.active == 0 }
    }

    func testDecodeLaneRunsOneJobAtATime() async throws {
        let gate = DispatchSemaphore(value: 0)
        let executor = ProviderExecutor.decodeLane
        let entered = expectation(description: "one decode running")
        let first = Task { try await executor.execute(ProviderRequest(vaultURL: URL(fileURLWithPath: "/tmp/decode-a")), step: .imagePrepare) { _ in
            entered.fulfill(); gate.wait(); return 1
        } }
        defer { gate.signal() }
        await fulfillment(of: [entered], timeout: 2)
        let second = Task { try await executor.execute(ProviderRequest(vaultURL: URL(fileURLWithPath: "/tmp/decode-b")), step: .imagePrepare) { _ in 2 } }
        await until { executor.counts.pending == 1 }
        XCTAssertEqual(executor.counts.active, 1)
        gate.signal(); _ = try await first.value; _ = try await second.value
    }

    func testRealFileServiceRunsCoordinationAndScopeSetupOutsideMainThread() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let threads = TestOrder()
        let executor = ProviderExecutor(coordinatorFactory: { ThreadCheckingCoordinator(threads) }, startScope: { _ in
            threads.add(Thread.isMainThread ? "main" : "worker"); return false
        })
        let service = VaultFileService(executor: executor)
        let request = ProviderRequest(vaultURL: folder)
        let vault = try await service.createVault(named: "Vault", in: folder, request: request)
        let note = try await service.createNote(named: "Note", in: vault, request: request)
        try await service.saveNote("Body", at: note, request: request)
        let text = try await service.readNote(at: note, request: request)
        let notes = try await service.listMarkdownNotes(in: vault, request: request)
        XCTAssertEqual(text, "Body"); XCTAssertEqual(notes.count, 1)
        XCTAssertFalse(threads.values.contains("main")); XCTAssertGreaterThanOrEqual(threads.values.count, 10)
    }

    private func until(_ predicate: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !predicate() && Date() < deadline { try? await Task.sleep(for: .milliseconds(2)) }
        XCTAssertTrue(predicate())
    }
}

private final class TestTime {
    private let lock = NSLock(); private var value = 0.0
    var now: Double { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: Double) { lock.lock(); value += seconds; lock.unlock() }
}
private final class ScopeCounts {
    private let lock = NSLock(); private var starts = 0; private var stops = 0
    var started: Int { lock.lock(); defer { lock.unlock() }; return starts }
    var stopped: Int { lock.lock(); defer { lock.unlock() }; return stops }
    func start(_ url: URL) { XCTAssertFalse(Thread.isMainThread); lock.lock(); starts += 1; lock.unlock() }
    func stop(_ url: URL) { XCTAssertFalse(Thread.isMainThread); lock.lock(); stops += 1; lock.unlock() }
}
private final class TestOrder {
    private let lock = NSLock(); private var items: [String] = []
    var values: [String] { lock.lock(); defer { lock.unlock() }; return items }
    func add(_ value: String) { lock.lock(); items.append(value); lock.unlock() }
}
private final class TestCoordinator: ProviderCoordinating {
    let before: Bool; let entered: XCTestExpectation; let gate: DispatchSemaphore; let cancelled: XCTestExpectation
    init(before: Bool, entered: XCTestExpectation, gate: DispatchSemaphore, cancelled: XCTestExpectation) {
        self.before = before; self.entered = entered; self.gate = gate; self.cancelled = cancelled
    }
    func read(at url: URL, accessor: (URL) -> Void) throws { try write(at: url, accessor: accessor) }
    func write(at url: URL, accessor: (URL) -> Void) throws {
        XCTAssertFalse(Thread.isMainThread)
        if before { entered.fulfill(); gate.wait() }
        accessor(url)
    }
    func cancel() { cancelled.fulfill() }
}
private final class ThreadCheckingCoordinator: ProviderCoordinating {
    private let system = SystemProviderCoordinator(); private let threads: TestOrder
    init(_ threads: TestOrder) { self.threads = threads }
    func read(at url: URL, accessor: (URL) -> Void) throws {
        threads.add(Thread.isMainThread ? "main" : "worker"); try system.read(at: url, accessor: accessor)
    }
    func write(at url: URL, accessor: (URL) -> Void) throws {
        threads.add(Thread.isMainThread ? "main" : "worker"); try system.write(at: url, accessor: accessor)
    }
    func cancel() { system.cancel() }
}
