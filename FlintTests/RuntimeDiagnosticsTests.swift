import XCTest
@testable import Flint

final class RuntimeDiagnosticsTests: XCTestCase {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    func testUnfinishedRestorationRequiresExplicitRetryAndCompletionAllowsRelaunch() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let first = RestorationSafety(directory: folder)
        let started = await first.begin(launchID: UUID(), explicit: false)
        XCTAssertTrue(started)
        let next = RestorationSafety(directory: folder)
        let automatic = await next.begin(launchID: UUID(), explicit: false)
        XCTAssertFalse(automatic)
        let retry = await next.begin(launchID: UUID(), explicit: true)
        XCTAssertTrue(retry)
        await next.finish(completed: true)
        let third = RestorationSafety(directory: folder)
        let permitted = await third.begin(launchID: UUID(), explicit: false)
        XCTAssertTrue(permitted)
        await third.finish(completed: false)
        let fourth = await RestorationSafety(directory: folder).begin(launchID: UUID(), explicit: false)
        XCTAssertTrue(fourth)
    }

    func testChoosingAnotherVaultAbandonsPreviousLaunchMarker() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let previous = RestorationSafety(directory: folder)
        let started = await previous.begin(launchID: UUID(), explicit: false)
        XCTAssertTrue(started)
        let next = RestorationSafety(directory: folder)
        let permitted = await next.begin(launchID: UUID(), explicit: false)
        XCTAssertFalse(permitted)
        await next.finish(completed: false)
        let later = await RestorationSafety(directory: folder).begin(launchID: UUID(), explicit: false)
        XCTAssertTrue(later)
    }

    func testCorruptAndUnavailableSafetyStorageFailClosed() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("private broken marker".utf8).write(to: folder.appendingPathComponent("marker.json"))
        let corrupt = await RestorationSafety(directory: folder).begin(launchID: UUID(), explicit: false)
        XCTAssertFalse(corrupt)
        let file = folder.appendingPathComponent("file")
        try Data().write(to: file)
        let failed = await RestorationSafety(directory: file).begin(launchID: UUID(), explicit: true)
        XCTAssertFalse(failed)
    }

    func testMarkerTimeoutDoesNotAwaitWriterAndLateWriteRemainsConservative() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let queue = DispatchQueue(label: "test.marker")
        queue.suspend()
        let safety = RestorationSafety(directory: folder, timeout: 0.01, queue: queue)
        let start = ProcessInfo.processInfo.systemUptime
        let permitted = await safety.begin(launchID: UUID(), explicit: false)
        XCTAssertFalse(permitted)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 1)
        // Retry cannot enqueue a second marker write behind the timed-out writer.
        let retry = await safety.begin(launchID: UUID(), explicit: true)
        XCTAssertFalse(retry)
        queue.resume()
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
        let relaunch = await RestorationSafety(directory: folder).begin(launchID: UUID(), explicit: false)
        XCTAssertFalse(relaunch)
    }

    func testTimedOutTerminalWritesNeverAuthorizeRelaunch() async throws {
        for completed in [true, false] {
            let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
            let queue = DispatchQueue(label: "test.terminal")
            let safety = RestorationSafety(directory: folder, timeout: 0.02, queue: queue)
            let started = await safety.begin(launchID: UUID(), explicit: false)
            XCTAssertTrue(started)
            queue.suspend()
            await safety.finish(completed: completed)
            let retry = await safety.begin(launchID: UUID(), explicit: true)
            XCTAssertFalse(retry)
            queue.resume()
            await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
            let marker = try JSONDecoder().decode(RestorationSafety.Marker.self,
                from: Data(contentsOf: folder.appendingPathComponent("marker.json")))
            XCTAssertEqual(marker.state, .started)
            let automatic = await RestorationSafety(directory: folder).begin(launchID: UUID(), explicit: false)
            XCTAssertFalse(automatic)
            let explicit = await safety.begin(launchID: UUID(), explicit: true)
            XCTAssertTrue(explicit)
            await safety.finish(completed: completed)
            await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
            let permitted = await RestorationSafety(directory: folder).begin(launchID: UUID(), explicit: false)
            XCTAssertTrue(permitted)
        }
    }

    func testTimeoutAfterTerminalStagingPreservesStartedMarker() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let gate = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "test.staged-terminal")
        let safety = RestorationSafety(directory: folder, timeout: 0.02, queue: queue,
            terminalStaged: { gate.wait() })
        let started = await safety.begin(launchID: UUID(), explicit: false)
        XCTAssertTrue(started)
        await safety.finish(completed: true)
        gate.signal()
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("terminal.json").path))
        let automatic = await RestorationSafety(directory: folder).begin(launchID: UUID(), explicit: false)
        XCTAssertFalse(automatic)
    }

    func testTerminalStorageFailurePreservesStartedMarker() async throws {
        for completed in [true, false] {
            let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
            let safety = RestorationSafety(directory: folder)
            let started = await safety.begin(launchID: UUID(), explicit: false)
            XCTAssertTrue(started)
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("terminal.json"),
                withIntermediateDirectories: true)
            await safety.finish(completed: completed)
            let automatic = await RestorationSafety(directory: folder).begin(launchID: UUID(), explicit: false)
            XCTAssertFalse(automatic)
        }
    }

    func testUnsupportedAndOversizedMarkersRequireRecovery() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("marker.json")
        let unsupported = RestorationSafety.Marker(version: 2, launchID: UUID(), actionID: UUID(),
            timestamp: Date(), state: .completed)
        for data in [try JSONEncoder().encode(unsupported), Data(repeating: 32, count: 4097)] {
            try data.write(to: url)
            let automatic = await RestorationSafety(directory: folder).begin(launchID: UUID(), explicit: false)
            XCTAssertFalse(automatic)
        }
    }

    func testForegroundTransitionsKeepOneOutstandingHeartbeat() {
        var now = 0.0
        var events: [ResponsivenessMonitor.Observation] = []
        let monitor = ResponsivenessMonitor(clock: { now }, emit: { events.append($0) })
        monitor.setActive(true)
        let stale = monitor.tick()!
        for _ in 0..<10 {
            monitor.setActive(false); now += 10; monitor.setActive(true)
            XCTAssertNil(monitor.tick())
        }
        XCTAssertTrue(events.isEmpty)
        monitor.acknowledge(stale)
        let fresh = monitor.tick()!
        now += 2
        XCTAssertNil(monitor.tick())
        XCTAssertEqual(events, [.stall([])])
        monitor.acknowledge(fresh)
        XCTAssertEqual(events, [.stall([]), .recovered(2)])
    }

    func testForegroundThresholdsBoundedVolumeAndRecoveryDuration() {
        var now = 0.0
        var events: [ResponsivenessMonitor.Observation] = []
        let monitor = ResponsivenessMonitor(clock: { now }, emit: { events.append($0) })
        monitor.setActive(true)
        let id = UUID(); monitor.begin(id, step: .enumeration)
        let token = monitor.tick()!
        now = 1.99; XCTAssertNil(monitor.tick()); XCTAssertTrue(events.isEmpty)
        now = 2; XCTAssertNil(monitor.tick()); XCTAssertEqual(events, [.stall([id])])
        now = 4.99; _ = monitor.tick(); XCTAssertEqual(events.count, 1)
        now = 5; _ = monitor.tick(); XCTAssertEqual(events.last, .slow(id, .enumeration, 5))
        now = 10; _ = monitor.tick(); XCTAssertEqual(events.count, 2)
        monitor.acknowledge(token)
        XCTAssertEqual(events.last, .recovered(10))
        monitor.end(id)
    }

    func testSuspensionExcludedAndStaleHeartbeatsIgnored() {
        var now = 0.0; var events: [ResponsivenessMonitor.Observation] = []
        let monitor = ResponsivenessMonitor(clock: { now }, emit: { events.append($0) })
        monitor.setActive(true)
        let id = UUID(); monitor.begin(id, step: .vaultOpen)
        let token = monitor.tick()!
        now = 1; _ = monitor.tick(); monitor.setActive(false)
        now = 100; XCTAssertNil(monitor.tick()); monitor.setActive(true)
        monitor.acknowledge(token); XCTAssertTrue(events.isEmpty)
        let fresh = monitor.tick()!
        now = 101; _ = monitor.tick(); monitor.acknowledge(fresh)
        now = 104; let next = monitor.tick()!; monitor.acknowledge(next)
        XCTAssertEqual(events, [.slow(id, .vaultOpen, 5)])
    }

    func testSlowObservationRetainsLastCompletedChildStage() {
        var now = 0.0; var events: [ResponsivenessMonitor.Observation] = []
        let monitor = ResponsivenessMonitor(clock: { now }, emit: { events.append($0) })
        monitor.setActive(true)
        let parent = UUID(), child = UUID()
        monitor.begin(parent, step: .vaultOpen); monitor.begin(child, step: .bookmarkResolve)
        monitor.end(child, parent: parent)
        now = 5; _ = monitor.tick()
        XCTAssertEqual(events, [.slow(parent, .bookmarkResolve, 5)])
    }

    func testStackSanitizerDropsPrivateStringsAndBoundsDepth() throws {
        var frame: [String: Any] = ["binaryUUID": "70B89F27-1634-3580-A695-57CDB41D7743", "address": 42,
            "offsetIntoBinaryTextSegment": 10, "sampleCount": 1, "binaryName": "/private/Secret.md",
            "note": "private text", "alt": "private caption", "bookmark": "private bookmark", "credentials": "private password"]
        for _ in 0..<40 { frame = ["subFrames": [frame], "binaryName": "private name", "address": -1] }
        let data = try JSONSerialization.data(withJSONObject: ["callStackTree": ["callStacks": [["callStackRootFrames": [frame]]]]])
        let clean = PlatformReport.stack(data)
        XCTAssertTrue(clean.truncated)
        XCTAssertLessThanOrEqual(clean.frames.count, 33)
        let json = String(decoding: try JSONEncoder().encode(clean.frames), as: UTF8.self)
        XCTAssertFalse(json.contains("private")); XCTAssertFalse(json.contains("Secret"))
        XCTAssertTrue(clean.frames.allSatisfy { $0.address == nil })
        XCTAssertEqual(clean.frames.map(\.depth), Array(0...32))
        XCTAssertTrue(clean.frames.allSatisfy { $0.threadIndex == 0 })
        XCTAssertNil(PlatformReport.identity("build-private-path"))
    }

    func testOldBuildDeliveryDeduplicatesAndNeverClaimsReceivingLaunch() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = DebugLogStore(directory: folder)
        let end = Date().addingTimeInterval(-3600)
        let report = PlatformReport(schemaVersion: 1, kind: .crash, windowStart: end.addingTimeInterval(-10),
            windowEnd: end, applicationVersion: "0.1", build: "9", multipleVersions: false, values: ["signal": 11],
            frames: [PlatformReport.Frame(binaryUUID: UUID(), address: 42, offset: 10, samples: 1)],
            truncated: false, correlation: "unknown")
        try store.appendPlatform(report)
        try store.appendPlatform(report, receivedAt: Date().addingTimeInterval(20))
        let data = try store.platformSnapshot()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let saved = try decoder.decode([SavedPlatformReport].self, from: data)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].report.build, "9")
        XCTAssertEqual(saved[0].report.correlation, "unknown")
        XCTAssertGreaterThan(saved[0].receivedAt.timeIntervalSince(saved[0].report.windowEnd), 3500)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("launchID"))
        try store.prune(now: end.addingTimeInterval(DebugLogStore.ageLimit + 1))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 0)
    }

    func testPlatformQueueSaturationDropsDeliveriesWithoutBlockingAndAccountsForLoss() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let queue = DispatchQueue(label: "test.platform-writer")
        let log = DebugLog(directory: folder, queue: queue)
        queue.suspend()
        var converted = 0
        for _ in 0..<10 { log.ingestPlatform { converted += 1; return [] } }
        log.observe(.platformEvidence)
        queue.resume()
        let data: Data = await withCheckedContinuation { continuation in
            log.snapshot { continuation.resume(returning: $0) }
        }
        XCTAssertEqual(converted, 8)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let records = try data.split(separator: 10).map { try decoder.decode(DebugLogEntry.self, from: Data($0)) }
        XCTAssertEqual(records.filter { $0.step == .droppedEntries }.map(\.count), [2])
    }

    func testReportAndJournalShareRetentionBudget() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // The prune budget includes both extensions, including malformed/oversized report files.
        let journal = folder.appendingPathComponent("journal.jsonl")
        try Data(repeating: 32, count: DebugLogStore.totalLimit).write(to: journal)
        let store = DebugLogStore(directory: folder)
        let report = PlatformReport(schemaVersion: 1, kind: .hang, windowStart: Date(), windowEnd: Date(),
            applicationVersion: "1", build: "2", multipleVersions: false, values: ["durationSeconds": 2],
            frames: [], truncated: false, correlation: "unknown")
        try store.appendPlatform(report)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        let bytes = try files.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        XCTAssertLessThanOrEqual(bytes, DebugLogStore.totalLimit)
    }

    func testPlatformPrivacyBoundaryRejectsUnpermittedMetadata() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = DebugLogStore(directory: folder)
        let report = PlatformReport(schemaVersion: 1, kind: .metrics, windowStart: Date(), windowEnd: Date(),
            applicationVersion: "private-note-title", build: "1", multipleVersions: false,
            values: ["private-account": 1], frames: [], truncated: false, correlation: "unknown")
        try store.appendPlatform(report)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }
}
