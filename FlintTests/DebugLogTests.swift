import XCTest
@testable import Flint

final class DebugLogTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    private func snapshot(_ log: DebugLog) -> Data {
        let done = expectation(description: "writer drains")
        var result = Data()
        log.snapshot { result = $0; done.fulfill() }
        wait(for: [done], timeout: 10)
        return result
    }
    private func entries(_ data: Data) throws -> [DebugLogEntry] {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try data.split(separator: 10).map { try decoder.decode(DebugLogEntry.self, from: Data($0)) }
    }

    func testTimeoutHasOneFinalResultAndOneLateObservation() throws {
        let log = DebugLog(directory: directory)
        let action = log.begin(.noteRead)
        action.finish(.timeout)
        action.finish(.success)
        action.finish(.success)
        let records = try entries(snapshot(log))
        XCTAssertEqual(records.map(\.result), [.started, .timeout, .finishedLater])
        XCTAssertEqual(Set(records.map(\.actionID)), [action.id])
        XCTAssertGreaterThanOrEqual(records.last!.durationSeconds!, 0)
        XCTAssertGreaterThanOrEqual(records.last!.elapsedSeconds, records.first!.elapsedSeconds)
    }

    func testPrivateErrorsAndFilePathsAreNotSavedAndIDsChangeEachLaunch() throws {
        let secret = "/Dropbox/account@example.com/password-secret/private-note.md"
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError,
            userInfo: [NSLocalizedDescriptionKey: secret, NSFilePathErrorKey: secret,
                       NSUnderlyingErrorKey: NSError(domain: secret, code: 12)])
        let log = DebugLog(directory: directory)
        let action = log.begin(.preview, file: URL(fileURLWithPath: secret))
        action.finish(.failure, error: error)
        let data = snapshot(log)
        let text = String(decoding: data, as: UTF8.self)
        for sensitive in ["Dropbox", "account@", "password-secret", "private-note", secret] {
            XCTAssertFalse(text.contains(sensitive))
        }
        let records = try entries(data)
        XCTAssertEqual(records.last?.errorCategory, .permission)
        XCTAssertEqual(records.last?.errorCode, NSFileReadNoPermissionError)
        let other = DebugLog(directory: directory.appendingPathComponent("other"))
        other.begin(.preview, file: URL(fileURLWithPath: secret)).finish(.success)
        XCTAssertNotEqual(records.first?.fileID, try entries(snapshot(other)).first?.fileID)
    }

    func testNestedActionsAndSuccessfulEmptyPreviewDifferFromFailure() throws {
        let log = DebugLog(directory: directory)
        log.measure(.enumeration) {
            log.measure(.preview) { }
            let failed = log.begin(.preview)
            failed.finish(.failure, error: CocoaError(.fileReadNoSuchFile))
        }
        let records = try entries(snapshot(log))
        let parent = records.first!.actionID
        XCTAssertEqual(records.filter { $0.step == .preview && $0.result == .started }.map(\.parentActionID), [parent, parent])
        XCTAssertEqual(records.filter { $0.step == .preview && $0.result != .started }.map(\.result), [.success, .failure])
    }

    func testSlowWriterBoundsQueueAndRecordsDropsWithoutBlockingCaller() throws {
        let queue = DispatchQueue(label: "test.slow-log")
        queue.suspend()
        let log = DebugLog(directory: directory, queue: queue)
        let start = Date()
        for _ in 0..<1000 { log.observe(.memoryWarning) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        queue.resume()
        let first = try entries(snapshot(log))
        XCTAssertLessThanOrEqual(first.count, 512)
        log.observe(.memoryWarning)
        let all = try entries(snapshot(log))
        XCTAssertTrue(all.contains { $0.step == .droppedEntries && ($0.count ?? 0) > 0 })
    }

    func testStorageFailureDoesNotThrowIntoApplication() {
        try! Data("occupied".utf8).write(to: directory)
        let log = DebugLog(directory: directory)
        log.observe(.noteSave)
        XCTAssertTrue(snapshot(log).isEmpty)
    }

    func testDamagedEntriesAreSkippedAndValidFieldsAreReencoded() throws {
        let log = DebugLog(directory: directory)
        log.observe(.noteRead)
        _ = snapshot(log)
        let file = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first!
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("broken\n{unfinished".utf8)); try handle.close()
        XCTAssertEqual(try entries(snapshot(log)).count, 2)
        log.observe(.noteSave)
        XCTAssertFalse(snapshot(log).isEmpty)
    }

    func testSegmentRotationAndOversizedEntryRejection() throws {
        let log = DebugLog(directory: directory.appendingPathComponent("fixture"))
        log.observe(.noteRead)
        let record = try entries(snapshot(log))[0]
        let store = DebugLogStore(directory: directory)
        for _ in 0..<1000 { try store.append(record) }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.pathExtension == "jsonl" }
        XCTAssertGreaterThan(files.count, 1)
        for file in files {
            XCTAssertLessThanOrEqual(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize!, DebugLogStore.segmentLimit)
        }
        let oversized = DebugLogEntry(schemaVersion: 1, timestamp: Date(), elapsedSeconds: 0,
            severity: "info", step: .launch, result: .started, appVersion: String(repeating: "x", count: 17000),
            build: "1", launchID: UUID(), actionID: UUID(), parentActionID: nil, fileID: nil,
            durationSeconds: nil, count: nil, bytes: nil, errorCategory: nil, errorCode: nil)
        XCTAssertThrowsError(try store.append(oversized))
    }

    func testDiskRetentionPrunesOldestAndExpiredSegments() throws {
        let store = DebugLogStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let old = directory.appendingPathComponent("old.jsonl")
        try Data(repeating: 1, count: DebugLogStore.segmentLimit).write(to: old)
        try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSinceNow: -8 * 86400)], ofItemAtPath: old.path)
        try store.prune()
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        for n in 0..<81 {
            try Data(repeating: 1, count: DebugLogStore.segmentLimit).write(to: directory.appendingPathComponent("\(n).jsonl"))
        }
        try store.prune(reserving: 1024)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertLessThan(files.count * DebugLogStore.segmentLimit + 1024, DebugLogStore.totalLimit)
    }
}
