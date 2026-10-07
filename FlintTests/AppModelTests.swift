import XCTest
import UIKit
@testable import Flint

@MainActor
final class AppModelTests: XCTestCase {
    func testLateVaultResultAfterCancellationCannotReplaceNewVaultOrAlert() async {
        let files = FileServiceSpy(), safety = RestorationSafetySpy()
        let firstRoot = URL(fileURLWithPath: "/tmp/first"), secondRoot = URL(fileURLWithPath: "/tmp/second")
        let first = makeNote(title: "First", url: firstRoot.appendingPathComponent("First.md"))
        let second = makeNote(title: "Second", url: secondRoot.appendingPathComponent("Second.md"))
        let entered = expectation(description: "old discovery pending")
        var release: CheckedContinuation<[NoteItem], Error>?
        files.listHook = { root, _ in
            if root == firstRoot { return try await withCheckedThrowingContinuation { release = $0; entered.fulfill() } }
            return [second]
        }
        files.noteContents[second.url] = "Second content"
        let model = AppModel(bookmarkStore: BookmarkStoreSpy(), fileService: files, restorationSafety: safety)
        let old = Task { await model.openVault(at: firstRoot) }
        await fulfillment(of: [entered], timeout: 2)
        model.cancelLoading()
        XCTAssertEqual(model.phase, .providerRecovery); XCTAssertFalse(model.isBusy)
        await model.chooseAnotherVault()
        await model.openVault(at: secondRoot)
        release?.resume(returning: [first]); await old.value
        XCTAssertEqual(model.activeVault?.url, secondRoot)
        XCTAssertEqual(model.selectedNote, second); XCTAssertEqual(model.noteText, "Second content")
        XCTAssertNil(model.alertMessage); XCTAssertFalse(model.isBusy)
        XCTAssertFalse(files.readNoteCalls.contains(first.url))
    }

    func testLateNoteFailureDoesNotReplaceNewSelectionOrAlert() async {
        let files = FileServiceSpy()
        let first = makeNote(title: "First", url: files.createdVaultURL.appendingPathComponent("First.md"))
        let second = makeNote(title: "Second", url: files.createdVaultURL.appendingPathComponent("Second.md"))
        files.notesToReturn = [first, second]
        let model = AppModel(bookmarkStore: BookmarkStoreSpy(), fileService: files)
        await model.openVault(at: files.createdVaultURL)
        let entered = expectation(description: "old note pending")
        var release: CheckedContinuation<String, Error>?
        files.readHook = { url, _ in
            if url == first.url { return try await withCheckedThrowingContinuation { release = $0; entered.fulfill() } }
            return "Current text"
        }
        let old = Task { await model.openNote(first) }
        await fulfillment(of: [entered], timeout: 2)
        await model.openNote(second)
        release?.resume(throwing: CocoaError(.fileReadNoPermission)); await old.value
        XCTAssertEqual(model.selectedNote, second); XCTAssertEqual(model.noteText, "Current text")
        XCTAssertNil(model.alertMessage); XCTAssertFalse(model.isNoteLoading); XCTAssertFalse(model.isBusy)
    }

    func testTypingDuringAsynchronousSavePreservesNewerDirtyRevision() async {
        let files = FileServiceSpy()
        let note = makeNote(title: "Note", url: files.createdVaultURL.appendingPathComponent("Note.md"))
        files.notesToReturn = [note]
        let model = AppModel(bookmarkStore: BookmarkStoreSpy(), fileService: files)
        await model.openVault(at: files.createdVaultURL)
        let entered = expectation(description: "save pending")
        var release: CheckedContinuation<Void, Never>?
        files.saveHook = { _, _, _ in await withCheckedContinuation { release = $0; entered.fulfill() } }
        model.updateNoteText("Revision A")
        let save = Task { await model.saveCurrentNoteIfNeeded() }
        await fulfillment(of: [entered], timeout: 2)
        model.updateNoteText("Revision B")
        release?.resume(); await save.value
        XCTAssertTrue(model.hasUnsavedChanges); XCTAssertEqual(model.noteText, "Revision B")
        XCTAssertEqual(files.savedNotes.map(\.0), ["Revision A"])
        files.saveHook = nil
        await model.saveCurrentNoteIfNeeded()
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertEqual(files.savedNotes.map(\.0), ["Revision A", "Revision B"])
    }

    func testFailedSavePreventsNavigationAndRetainsOriginalDestinationAndText() async {
        let files = FileServiceSpy()
        let note = makeNote(title: "Note", url: files.createdVaultURL.appendingPathComponent("Note.md"))
        files.notesToReturn = [note]
        let model = AppModel(bookmarkStore: BookmarkStoreSpy(), fileService: files)
        await model.openVault(at: files.createdVaultURL)
        files.saveHook = { _, _, _ in throw CocoaError(.fileWriteNoPermission) }
        model.updateNoteText("Retained edits")
        await model.openVault(at: URL(fileURLWithPath: "/tmp/new-vault"))
        XCTAssertEqual(model.activeVault?.url, files.createdVaultURL)
        XCTAssertEqual(model.selectedNote, note); XCTAssertEqual(model.noteText, "Retained edits")
        XCTAssertTrue(model.hasUnsavedChanges); XCTAssertNotNil(model.alertMessage)
        XCTAssertEqual(files.savedNotes.first?.1, note.url)
        XCTAssertEqual(files.listMarkdownNotesCalls.count, 1)
    }

    func testUncertainCreationRetryWaitsForActualResultAndOpensExistingVault() async {
        let time = ModelTestTime(); let clock = ForegroundClock(clock: { time.now })
        let executor = ProviderExecutor(automaticSampling: false, startScope: { _ in false })
        let files = FileServiceSpy(); let gate = DispatchSemaphore(value: 0)
        let entered = expectation(description: "creation accessor blocked")
        let created = files.createdVaultURL
        files.createHook = { _, _, request in
            try await executor.execute(request, step: .vaultCreate, mutation: true) { _ in
                entered.fulfill(); gate.wait(); return created
            }
        }
        defer { gate.signal() }
        let model = AppModel(bookmarkStore: BookmarkStoreSpy(), fileService: files, restorationSafety: RestorationSafetySpy(),
            executor: executor, attemptFactory: { ProviderAttempt(clock: clock) })
        let creation = Task { await model.createVault(named: "New", in: URL(fileURLWithPath: "/tmp/parent")) }
        await fulfillment(of: [entered], timeout: 2)
        time.advance(5); model.refreshLoadingProgress(); XCTAssertTrue(model.isSlow)
        time.advance(25); executor.sample(); await creation.value
        XCTAssertEqual(model.phase, .providerRecovery)
        await model.retryRestoration()
        XCTAssertEqual(files.createVaultCalls.count, 1)
        XCTAssertTrue(model.recoveryMessage.contains("still stopping"))
        gate.signal(); await modelWait { executor.counts.active == 0 }
        await model.retryRestoration()
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.activeVault?.url, created)
        XCTAssertEqual(files.createVaultCalls.count, 1)
    }

    func testUncertainSaveDoesNotOverlapRetryAndAcknowledgesActualSuccess() async {
        let time = ModelTestTime(); let clock = ForegroundClock(clock: { time.now })
        let executor = ProviderExecutor(automaticSampling: false, startScope: { _ in false })
        let files = FileServiceSpy()
        let note = makeNote(title: "Note", url: files.createdVaultURL.appendingPathComponent("Note.md"))
        files.notesToReturn = [note]
        let model = AppModel(bookmarkStore: BookmarkStoreSpy(), fileService: files, executor: executor,
            attemptFactory: { ProviderAttempt(clock: clock) })
        await model.openVault(at: files.createdVaultURL)
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let entered = expectation(description: "save accessor blocked")
        files.saveHook = { _, _, request in
            try await executor.execute(request, step: .noteSave, mutation: true) { _ in entered.fulfill(); gate.wait() }
        }
        model.updateNoteText("Retained save")
        let save = Task { await model.saveCurrentNoteIfNeeded() }
        await fulfillment(of: [entered], timeout: 2)
        time.advance(30); executor.sample(); await save.value
        XCTAssertTrue(model.hasUnsavedChanges)
        await model.saveCurrentNoteIfNeeded()
        XCTAssertEqual(files.savedNotes.count, 1)
        gate.signal(); await modelWait { executor.counts.active == 0 }
        await model.saveCurrentNoteIfNeeded()
        XCTAssertEqual(files.savedNotes.count, 1); XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testCancelChooseAnotherVaultAndExportRemainUsableWithBothWorkersDraining() async throws {
        let executor = ProviderExecutor(automaticSampling: false, startScope: { _ in false })
        let files = FileServiceSpy(), safety = RestorationSafetySpy()
        let blockedRoot = URL(fileURLWithPath: "/tmp/blocked-vault")
        let gate = DispatchSemaphore(value: 0), otherGate = DispatchSemaphore(value: 0)
        defer { gate.signal(); otherGate.signal() }
        let entered = expectation(description: "vault discovery blocked")
        files.listHook = { root, request in
            if root == blockedRoot {
                return try await executor.execute(request, step: .enumeration) { _ in entered.fulfill(); gate.wait(); return [] }
            }
            return []
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = DebugLog(directory: folder.appendingPathComponent("logs"))
        log.begin(.noteRead, file: URL(fileURLWithPath: "/private/secret.md")).finish(.failure,
            error: NSError(domain: "private password", code: 999, userInfo: [NSLocalizedDescriptionKey: "private note text"]))
        let share = DiagnosticShareStore(log: log, directory: folder.appendingPathComponent("share"))
        let model = AppModel(bookmarkStore: BookmarkStoreSpy(), fileService: files, restorationSafety: safety,
            executor: executor, shareStore: share)
        let open = Task { await model.openVault(at: blockedRoot) }
        await fulfillment(of: [entered], timeout: 2)
        let otherEntered = expectation(description: "second slot blocked")
        let otherAttempt = ProviderAttempt()
        let other = Task {
            try await executor.execute(ProviderRequest(vaultURL: URL(fileURLWithPath: "/tmp/other-blocked"), attempt: otherAttempt), step: .noteRead) { _ in
                otherEntered.fulfill(); otherGate.wait(); return 1
            }
        }
        await fulfillment(of: [otherEntered], timeout: 2)
        model.cancelLoading(); otherAttempt.cancel(); await open.value
        _ = try? await other.value
        XCTAssertEqual(model.phase, .providerRecovery); XCTAssertFalse(model.isBusy)
        await model.exportDiagnostics()
        let url = try XCTUnwrap(model.diagnosticShare?.url)
        let data = try Data(contentsOf: url)
        XCTAssertLessThanOrEqual(data.count, 20 * 1024 * 1024)
        let contents = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(contents.contains("secret.md")); XCTAssertFalse(contents.contains("private note text"))
        XCTAssertFalse(contents.contains("private password")); XCTAssertTrue(contents.contains("Originating launch correlation is unknown"))
        await model.chooseAnotherVault()
        XCTAssertEqual(model.phase, .onboarding)
        let nextRoot = URL(fileURLWithPath: "/tmp/new-vault")
        await model.openVault(at: nextRoot)
        XCTAssertEqual(model.phase, .providerRecovery)
        XCTAssertTrue(model.recoveryMessage.contains("occupied")); XCTAssertEqual(executor.counts.active, 2)
        otherGate.signal(); await modelWait { executor.counts.active == 1 }
        await model.openVault(at: nextRoot)
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.activeVault?.url, nextRoot)
        gate.signal(); await modelWait { executor.counts.active == 0 }
        XCTAssertNil(model.alertMessage); XCTAssertFalse(model.isBusy)
        model.finishDiagnosticShare(); await modelWait { !FileManager.default.fileExists(atPath: url.path) }
    }

    func testLateDiagnosticExportDoesNotPresentOnNewScreen() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let queue = DispatchQueue(label: "test.blocked-diagnostic-writer")
        let log = DebugLog(directory: folder.appendingPathComponent("logs"), queue: queue)
        let shareFolder = folder.appendingPathComponent("share")
        let share = DiagnosticShareStore(log: log, directory: shareFolder)
        let model = AppModel(bookmarkStore: BookmarkStoreSpy(), fileService: FileServiceSpy(),
            restorationSafety: RestorationSafetySpy(), shareStore: share)
        queue.suspend()
        let export = Task { await model.exportDiagnostics() }
        await modelWait { model.isExportingDiagnostics }
        await model.chooseAnotherVault()
        XCTAssertEqual(model.phase, .onboarding)
        queue.resume()
        await export.value
        XCTAssertNil(model.diagnosticShare); XCTAssertNil(model.alertMessage)
        await modelWait { !FileManager.default.fileExists(atPath: shareFolder.path) }
    }

    func testLateAbandonmentCannotReplaceNewVaultWithOnboarding() async {
        let safety = RestorationSafetySpy()
        var release: CheckedContinuation<Void, Never>?
        safety.finishHook = { await withCheckedContinuation { release = $0 } }
        let model = AppModel(bookmarkStore: BookmarkStoreSpy(), fileService: FileServiceSpy(), restorationSafety: safety)
        let choose = Task { await model.chooseAnotherVault() }
        await modelWait { release != nil }
        let root = URL(fileURLWithPath: "/tmp/new-vault-after-abandonment")
        await model.openVault(at: root)
        XCTAssertEqual(model.phase, .ready)
        release?.resume(); await choose.value
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.activeVault?.url, root)
    }

    func testCreationRetryReusesSuccessAfterDiscoveryFailure() async {
        let files = FileServiceSpy()
        let root = URL(fileURLWithPath: "/tmp/created-note-recovery")
        let model = AppModel(bookmarkStore: BookmarkStoreSpy(), fileService: files, restorationSafety: RestorationSafetySpy())
        await model.openVault(at: root)
        files.listHook = { _, _ in throw CocoaError(.fileReadUnknown) }
        await model.createNote(named: "Created.md")
        XCTAssertEqual(files.createdNoteCalls.count, 1)
        files.listHook = nil
        files.readHook = { _, _ in throw CocoaError(.fileReadUnknown) }
        await model.createNote(named: "Created.md")
        XCTAssertEqual(files.createdNoteCalls.count, 1)
        XCTAssertNil(model.selectedNote)
        files.readHook = nil
        await model.createNote(named: "Created.md")
        XCTAssertEqual(files.createdNoteCalls.count, 1)
        XCTAssertEqual(model.selectedNote?.url, root.appendingPathComponent("Created.md"))
        XCTAssertFalse(model.isBusy)
    }

    func testFailedAndCancelledNoteRequestsRestoreRetainedSelectionForImmediateRetry() async {
        let files = FileServiceSpy(), root = URL(fileURLWithPath: "/tmp/selection-recovery")
        let first = makeNote(title: "First", url: root.appendingPathComponent("First.md"))
        let second = makeNote(title: "Second", url: root.appendingPathComponent("Second.md"))
        files.notesToReturn = [first, second]
        let model = AppModel(bookmarkStore: BookmarkStoreSpy(), fileService: files, restorationSafety: RestorationSafetySpy())
        await model.openVault(at: root)
        files.readHook = { _, _ in throw CocoaError(.fileReadUnknown) }
        await model.openNote(second)
        XCTAssertEqual(model.requestedNoteURL, first.url)
        XCTAssertEqual(model.selectedNote?.url, first.url)
        files.readHook = nil
        await model.openNote(second)
        XCTAssertEqual(model.selectedNote?.url, second.url)
        var release: CheckedContinuation<String, Error>?
        files.readHook = { _, _ in try await withCheckedThrowingContinuation { release = $0 } }
        let pending = Task { await model.openNote(first) }
        await modelWait { release != nil }
        XCTAssertEqual(model.requestedNoteURL, first.url)
        model.cancelNoteLoading()
        XCTAssertEqual(model.requestedNoteURL, second.url)
        release?.resume(returning: "obsolete")
        await pending.value
        XCTAssertEqual(model.requestedNoteURL, second.url)
        files.readHook = nil
        await model.openNote(first)
        XCTAssertEqual(model.selectedNote?.url, first.url)
        XCTAssertFalse(model.isBusy)
    }

    func testCorruptContentAfterBookmarkResolutionPreservesSavedPermission() async {
        for failDiscovery in [true, false] {
            let bookmarks = BookmarkStoreSpy(), files = FileServiceSpy()
            let data = Data("valid bookmark".utf8); bookmarks.storedBookmarkData = data
            files.notesToReturn = [makeNote(title: "Corrupt", url: URL(fileURLWithPath: "/tmp/resolved-vault/Corrupt.md"))]
            if failDiscovery { files.listHook = { _, _ in throw CocoaError(.fileReadCorruptFile) } }
            else { files.readHook = { _, _ in throw CocoaError(.fileReadCorruptFile) } }
            let model = AppModel(bookmarkStore: bookmarks, fileService: files, restorationSafety: RestorationSafetySpy())
            await model.bootstrap()
            XCTAssertEqual(bookmarks.storedBookmarkData, data)
            XCTAssertEqual(model.phase, .providerRecovery)
        }
        let invalid = BookmarkStoreSpy(); invalid.storedBookmarkData = Data("invalid".utf8)
        invalid.resolveError = CocoaError(.fileReadCorruptFile)
        let model = AppModel(bookmarkStore: invalid, fileService: FileServiceSpy(), restorationSafety: RestorationSafetySpy())
        await model.bootstrap()
        XCTAssertNil(invalid.storedBookmarkData); XCTAssertEqual(model.phase, .onboarding)
    }

    func testCreatedNoteSaveBeforeNavigationFailureClearsBusyAndKeepsRecoveryResult() async {
        let files = FileServiceSpy(), root = URL(fileURLWithPath: "/tmp/creation-dirty-editor")
        let original = makeNote(title: "Original", url: root.appendingPathComponent("Original.md"))
        files.notesToReturn = [original]
        let model = AppModel(bookmarkStore: BookmarkStoreSpy(), fileService: files, restorationSafety: RestorationSafetySpy())
        await model.openVault(at: root)
        var release: CheckedContinuation<[NoteItem], Error>?
        files.listHook = { _, _ in try await withCheckedThrowingContinuation { release = $0 } }
        files.saveHook = { _, _, _ in throw CocoaError(.fileWriteNoPermission) }
        let creation = Task { await model.createNote(named: "Created.md") }
        await modelWait { release != nil }
        model.updateNoteText("Edits while creation is pending")
        files.listHook = nil
        release?.resume(returning: files.notesToReturn)
        await creation.value
        XCTAssertEqual(model.selectedNote?.url, original.url)
        XCTAssertEqual(model.noteText, "Edits while creation is pending")
        XCTAssertTrue(model.hasUnsavedChanges); XCTAssertFalse(model.isBusy)
        files.saveHook = nil
        await model.createNote(named: "Created.md")
        XCTAssertEqual(files.createdNoteCalls.count, 1)
        XCTAssertEqual(model.selectedNote?.url, root.appendingPathComponent("Created.md"))
    }

    func testLateFileAndCameraImportsRecoverOnceWithoutCreatingAnotherAssetOrCrossingNotes() async throws {
        for camera in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let note = makeNote(title: "Original", url: root.appendingPathComponent("Original.md"))
            let asset = root.appendingPathComponent("Imported.png")
            let inserted = InsertedNoteImage(markdownSource: "![Imported](Imported.png)", assetURL: asset, altText: "Imported")
            let time = ModelTestTime(), clock = ForegroundClock(clock: { time.now })
            let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
            let entered = expectation(description: "import accessor blocked")
            let drained = expectation(description: "import worker actually returned")
            let executor = ProviderExecutor(automaticSampling: false, startScope: { _ in false }, workerDidFinish: { drained.fulfill() })
            // Bootstrap scopes use a different executor so only the import fulfills this lifecycle expectation.
            let scopes = ProviderExecutor(startScope: { _ in false })
            let files = FileServiceSpy(); files.notesToReturn = [note]
            let importWork: (ProviderRequest) async throws -> InsertedNoteImage = { request in
                try await executor.execute(request, step: .imageImport, mutation: true) { _ in
                    try Data("completed asset".utf8).write(to: asset)
                    entered.fulfill(); gate.wait(); return inserted
                }
            }
            files.imageImportHook = { request in try await importWork(request) }
            let model = AppModel(bookmarkStore: BookmarkStoreSpy(), fileService: files, restorationSafety: RestorationSafetySpy(),
                executor: scopes, attemptFactory: { ProviderAttempt(clock: clock) })
            await model.openVault(at: root)
            let source = root.appendingPathComponent("Source.png")
            let importTask = Task { camera ? await model.importCameraImage(UIImage()) : await model.importImage(from: source) }
            await fulfillment(of: [entered], timeout: 2)
            time.advance(30); executor.sample()
            let early = await importTask.value
            XCTAssertNil(early); XCTAssertTrue(model.hasPendingImageImport)
            XCTAssertNil(model.recoverImageImport(for: note.url))
            let duplicate = await model.importImage(from: source)
            XCTAssertNil(duplicate)
            XCTAssertEqual(files.importedImages.count + files.importedCameraImages.count, 1)
            let otherRoot = root.appendingPathComponent("OtherVault")
            let other = makeNote(title: "Other", url: otherRoot.appendingPathComponent("Other.md"))
            files.notesToReturn = [other]
            await model.openVault(at: otherRoot)
            XCTAssertFalse(model.hasPendingImageImport)
            gate.signal(); await fulfillment(of: [drained], timeout: 20)
            XCTAssertNil(model.recoverImageImport(for: note.url))
            XCTAssertEqual(model.selectedNote?.url, other.url); XCTAssertNil(model.alertMessage)
            files.notesToReturn = [note]
            await model.openVault(at: root)
            XCTAssertTrue(model.hasPendingImageImport)
            XCTAssertEqual(model.recoverImageImport(for: note.url), inserted)
            XCTAssertFalse(model.hasPendingImageImport)
            XCTAssertNil(model.recoverImageImport(for: note.url))
            XCTAssertEqual(files.importedImages.count + files.importedCameraImages.count, 1)
            XCTAssertTrue(FileManager.default.fileExists(atPath: asset.path))
        }
    }

    func testSecondSourceCallbackCannotStartWhileFirstImportIsInFlight() async {
        let files = FileServiceSpy(), root = URL(fileURLWithPath: "/tmp/in-flight-images")
        let note = makeNote(title: "Note", url: root.appendingPathComponent("Note.md"))
        let inserted = InsertedNoteImage(markdownSource: "![Image](Image.png)", assetURL: root.appendingPathComponent("Image.png"), altText: "Image")
        files.notesToReturn = [note]
        var release: CheckedContinuation<InsertedNoteImage, Error>?
        files.imageImportHook = { _ in
            if release != nil { return inserted }
            return try await withCheckedThrowingContinuation { release = $0 }
        }
        let model = AppModel(bookmarkStore: BookmarkStoreSpy(), fileService: files, restorationSafety: RestorationSafetySpy())
        await model.openVault(at: root)
        let first = Task { await model.importImage(from: root.appendingPathComponent("Source.png")) }
        await modelWait { release != nil }
        let second = await model.importCameraImage(UIImage())
        XCTAssertNil(second); XCTAssertTrue(model.isBusy)
        XCTAssertEqual(files.importedImages.count + files.importedCameraImages.count, 1)
        release?.resume(returning: inserted)
        let completed = await first.value
        XCTAssertEqual(completed, inserted); XCTAssertFalse(model.isBusy)
    }

    func testActualLateImportFailureAllowsNewSourceWithoutRecovery() async throws {
        let time = ModelTestTime(), clock = ForegroundClock(clock: { time.now })
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let entered = expectation(description: "first import blocked")
        let drained = expectation(description: "failed import actually finished")
        let executor = ProviderExecutor(automaticSampling: false, startScope: { _ in false }, workerDidFinish: { drained.fulfill() })
        let root = URL(fileURLWithPath: "/tmp/failed-import-replacement"), files = FileServiceSpy()
        let note = makeNote(title: "Note", url: root.appendingPathComponent("Note.md"))
        files.notesToReturn = [note]
        files.imageImportHook = { request in
            try await executor.execute(request, step: .imageImport, mutation: true) { _ -> InsertedNoteImage in
                entered.fulfill(); gate.wait(); throw CocoaError(.fileReadUnknown)
            }
        }
        let model = AppModel(bookmarkStore: BookmarkStoreSpy(), fileService: files, restorationSafety: RestorationSafetySpy(),
            attemptFactory: { ProviderAttempt(clock: clock) })
        await model.openVault(at: root)
        let first = Task { await model.importImage(from: root.appendingPathComponent("Unavailable.png")) }
        await fulfillment(of: [entered], timeout: 2)
        time.advance(30); executor.sample()
        let early = await first.value
        XCTAssertNil(early); XCTAssertTrue(model.hasPendingImageImport)
        gate.signal(); await fulfillment(of: [drained], timeout: 20)
        files.imageImportHook = nil
        let replacement = await model.importImage(from: root.appendingPathComponent("New.png"))
        XCTAssertNotNil(replacement); XCTAssertFalse(model.hasPendingImageImport)
        XCTAssertEqual(files.importedImages.count, 2)
    }

    private func modelWait(_ predicate: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !predicate() && Date() < deadline { try? await Task.sleep(for: .milliseconds(2)) }
        XCTAssertTrue(predicate())
    }

    func testOpenVaultLoadsFirstNoteBeforeReturningAndSavesPreviousEditorState() async {
        let files = FileServiceSpy()
        let first = makeNote(title: "First", url: files.createdVaultURL.appendingPathComponent("First.md"))
        files.notesToReturn = [first]
        files.noteContents[first.url] = "First content"
        let model = AppModel(bookmarkStore: BookmarkStoreSpy(), fileService: files)

        await model.openVault(at: files.createdVaultURL)
        XCTAssertEqual(model.selectedNote, first)
        XCTAssertEqual(model.noteText, "First content")
        model.updateNoteText("Unsaved previous content")

        let nextVault = URL(fileURLWithPath: "/tmp/next-vault")
        let next = makeNote(title: "Next", url: nextVault.appendingPathComponent("Next.md"))
        files.notesToReturn = [next]
        files.noteContents[next.url] = "Next content"
        await model.openVault(at: nextVault)
        await Task.yield()

        XCTAssertEqual(model.selectedNote, next)
        XCTAssertEqual(model.noteText, "Next content")
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertEqual(files.savedNotes.first?.0, "Unsaved previous content")
        XCTAssertEqual(files.readNoteCalls, [first.url, next.url])
    }

    func testCreatingNoteDoesNotScheduleFallbackNavigation() async {
        let files = FileServiceSpy()
        let existing = makeNote(title: "Existing", url: files.createdVaultURL.appendingPathComponent("Existing.md"))
        let model = AppModel(bookmarkStore: BookmarkStoreSpy(), fileService: files)
        await model.openVault(at: files.createdVaultURL)
        files.notesToReturn = [existing]

        await model.createNote(named: "Created.md")
        await Task.yield()

        XCTAssertEqual(model.selectedNote?.url, files.createdVaultURL.appendingPathComponent("Created.md"))
        XCTAssertEqual(files.readNoteCalls, [files.createdVaultURL.appendingPathComponent("Created.md")])
    }

    func testVaultFolderResolvedPathComponentsFallsBackToRootForMissingFolder() {
        let notes = [
            makeNote(
                title: "Runbook",
                url: URL(fileURLWithPath: "/tmp/vault/Projects/iOS/runbook.md"),
                folderPath: "Projects/iOS",
                createdAt: .init(timeIntervalSince1970: 300)
            )
        ]

        let root = VaultFolder.root(vaultName: "Flint Vault", notes: notes)

        XCTAssertEqual(root.resolvedPathComponents(for: ["Projects", "iOS"]), ["Projects", "iOS"])
        XCTAssertEqual(root.resolvedPathComponents(for: ["Projects", "Missing"]), [])
    }

    func testCreateNoteInNestedFolderSelectsCreatedNoteWithoutDelayedNavigation() async {
        let files = FileServiceSpy()
        let existing = makeNote(title: "Existing", url: files.createdVaultURL.appendingPathComponent("Existing.md"))
        files.notesToReturn = [existing]
        let model = AppModel(bookmarkStore: BookmarkStoreSpy(), fileService: files)
        await model.openVault(at: files.createdVaultURL)
        await model.createNote(named: "Daily.md", inFolderPath: ["Projects", "iOS"])
        let expected = files.createdVaultURL.appendingPathComponent("Projects/iOS/Daily.md")
        XCTAssertEqual(model.selectedNote?.url, expected)
        await Task.yield()
        XCTAssertEqual(model.selectedNote?.url, expected)
        XCTAssertEqual(files.readNoteCalls, [existing.url, expected])
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testInterruptedRestorationAndMarkerFailurePreventProviderWorkWithoutDeletingBookmark() async {
        do {
            let bookmarkStore = BookmarkStoreSpy(); bookmarkStore.storedBookmarkData = Data("bookmark".utf8)
            let files = FileServiceSpy(); let safety = RestorationSafetySpy(); safety.allowed = false
            let model = AppModel(bookmarkStore: bookmarkStore, fileService: files, restorationSafety: safety)
            await model.bootstrap()
            XCTAssertEqual(model.phase, .restorationRecovery)
            XCTAssertEqual(bookmarkStore.resolveCalls, 0)
            XCTAssertTrue(files.listMarkdownNotesCalls.isEmpty)
            XCTAssertNotNil(bookmarkStore.storedBookmarkData)
            await model.chooseAnotherVault()
            XCTAssertEqual(model.phase, .onboarding)
            XCTAssertNotNil(bookmarkStore.storedBookmarkData)
        }
    }

    func testExplicitRestorationRetryReopensBookmarkAndCommitsCompletion() async {
        let bookmarkStore = BookmarkStoreSpy(); bookmarkStore.storedBookmarkData = Data("bookmark".utf8)
        let files = FileServiceSpy(); let safety = RestorationSafetySpy(); safety.allowed = false
        let model = AppModel(bookmarkStore: bookmarkStore, fileService: files, restorationSafety: safety)
        await model.bootstrap()
        safety.allowed = true
        await model.retryRestoration()
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(safety.explicitAttempts, [false, true])
        XCTAssertEqual(safety.completions, [true])
        XCTAssertEqual(bookmarkStore.resolveCalls, 1)
    }

    func testHandledRestorationFailureCommitsAbandonment() async {
        let bookmarkStore = BookmarkStoreSpy(); bookmarkStore.storedBookmarkData = Data("bookmark".utf8)
        bookmarkStore.resolveError = CocoaError(.fileReadCorruptFile)
        let files = FileServiceSpy(); let safety = RestorationSafetySpy()
        let model = AppModel(bookmarkStore: bookmarkStore, fileService: files, restorationSafety: safety)
        await model.bootstrap()
        XCTAssertEqual(model.phase, .onboarding)
        XCTAssertEqual(safety.completions, [false])
        XCTAssertNil(bookmarkStore.storedBookmarkData)
        XCTAssertTrue(files.listMarkdownNotesCalls.isEmpty)
    }

    func testBootstrapWithoutStoredBookmarkShowsOnboarding() async {
        let bookmarkStore = BookmarkStoreSpy()
        let fileService = FileServiceSpy()
        let model = AppModel(bookmarkStore: bookmarkStore, fileService: fileService)

        await model.bootstrap()

        XCTAssertEqual(model.phase, .onboarding)
        XCTAssertNil(model.activeVault)
    }

    func testCreateVaultPersistsBookmarkAndLoadsVault() async {
        let bookmarkStore = BookmarkStoreSpy()
        let fileService = FileServiceSpy()
        let parentURL = URL(fileURLWithPath: "/tmp")
        let createdVaultURL = parentURL.appendingPathComponent("Flint Vault", isDirectory: true)
        fileService.createdVaultURL = createdVaultURL

        let model = AppModel(bookmarkStore: bookmarkStore, fileService: fileService)

        await model.createVault(named: "Flint Vault", in: parentURL)

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.activeVault?.url, createdVaultURL)
        XCTAssertEqual(fileService.createVaultCalls.count, 1)
        XCTAssertEqual(bookmarkStore.savedBookmarkData, Data("bookmark".utf8))
    }

    func testSaveCurrentNoteIfNeededRefreshesNotesAfterPersisting() async {
        let bookmarkStore = BookmarkStoreSpy()
        let fileService = FileServiceSpy()
        let noteURL = URL(fileURLWithPath: "/tmp/default-vault/Daily.md")
        let initialNote = makeNote(title: "Daily", url: noteURL, modifiedAt: .init(timeIntervalSince1970: 100))
        let refreshedNote = makeNote(title: "Daily", url: noteURL, modifiedAt: .init(timeIntervalSince1970: 200))
        fileService.notesToReturn = [initialNote]
        fileService.notesAfterSave = [refreshedNote]

        let model = AppModel(bookmarkStore: bookmarkStore, fileService: fileService)
        await model.openVault(at: fileService.createdVaultURL)
        await model.openNote(initialNote)

        model.updateNoteText("updated")
        let readsBeforeSave = fileService.readNoteCalls
        await model.saveCurrentNoteIfNeeded()

        XCTAssertEqual(fileService.savedNotes.count, 1)
        XCTAssertEqual(fileService.listMarkdownNotesCalls.count, 2)
        XCTAssertEqual(model.selectedNote?.lastModifiedAt, refreshedNote.lastModifiedAt)
        XCTAssertEqual(fileService.readNoteCalls, readsBeforeSave)
        XCTAssertEqual(model.noteText, "updated")
    }

    func testRichTextCodecMapsMarkdownIntoFormattingModel() {
        let markdown = """
        # Daily

        Intro paragraph with a [link](https://example.com).

        - one
        - two

        1. first
        2. second

        > quoted line

        ```swift
        print("hi")
        ```
        """

        let attributed = FlintRichTextCodec.attributedString(from: markdown)
        let string = attributed.string as NSString

        XCTAssertEqual(FlintRichTextCodec.blockStyle(at: 0, in: attributed), .heading1)

        let bulletRange = string.range(of: "•\tone")
        XCTAssertNotEqual(bulletRange.location, NSNotFound)
        XCTAssertEqual(FlintRichTextCodec.blockStyle(at: bulletRange.location, in: attributed), .bulletList)

        let numberRange = string.range(of: "1.\tfirst")
        XCTAssertNotEqual(numberRange.location, NSNotFound)
        XCTAssertEqual(FlintRichTextCodec.blockStyle(at: numberRange.location, in: attributed), .numberedList)

        let quoteRange = string.range(of: "quoted line")
        XCTAssertNotEqual(quoteRange.location, NSNotFound)
        XCTAssertEqual(FlintRichTextCodec.blockStyle(at: quoteRange.location, in: attributed), .quote)

        let linkRange = string.range(of: "link")
        let link = attributed.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL
        XCTAssertEqual(link?.absoluteString, "https://example.com")

        let codeRange = string.range(of: "print(\"hi\")")
        XCTAssertEqual(FlintRichTextCodec.blockStyle(at: codeRange.location, in: attributed), .codeBlock)
    }

    func testRichTextCodecReturnsEmptyParagraphTextForEmptyRange() {
        XCTAssertEqual(
            FlintRichTextCodec.paragraphText(in: NSString(string: ""), paragraphRange: NSRange(location: 0, length: 0)),
            ""
        )
    }

    func testRichTextCodecSerializesFormattingBackToMarkdown() {
        let markdown = """
        ## Sprint Plan

        Ship the **prototype** with a [review link](https://example.com).

        - polish interactions
        - normalize paste

        1. build
        2. test

        > stay native

        ```
        print("done")
        ```
        """

        let attributed = FlintRichTextCodec.attributedString(from: markdown)
        let serialized = FlintRichTextCodec.markdown(from: attributed)

        XCTAssertTrue(serialized.contains("## Sprint Plan"))
        XCTAssertTrue(serialized.contains("**prototype**"))
        XCTAssertTrue(serialized.contains("[review link](https://example.com)"))
        XCTAssertTrue(serialized.contains("- polish interactions"))
        XCTAssertTrue(serialized.contains("1. build"))
        XCTAssertTrue(serialized.contains("> stay native"))
        XCTAssertTrue(serialized.contains("```"))
        XCTAssertTrue(serialized.contains("print(\"done\")"))
    }

    func testRichTextCodecResolvesAndRoundTripsMarkdownImages() throws {
        let vaultURL = URL(fileURLWithPath: "/tmp/vault", isDirectory: true)
        let noteURL = vaultURL.appendingPathComponent("Notes/Daily.md")
        let attributed = FlintRichTextCodec.attributedString(
            from: "![Diagram](/Attachments/diagram.heic)",
            noteURL: noteURL,
            vaultURL: vaultURL
        )

        let markdownSource = attributed.attribute(.flintImageMarkdownSource, at: 0, effectiveRange: nil) as? String
        let assetURL = attributed.attribute(.flintImageAssetURL, at: 0, effectiveRange: nil) as? URL

        XCTAssertEqual(markdownSource, "![Diagram](/Attachments/diagram.heic)")
        XCTAssertEqual(assetURL, vaultURL.appendingPathComponent("Attachments/diagram.heic"))
        XCTAssertEqual(FlintRichTextCodec.markdown(from: attributed), "![Diagram](/Attachments/diagram.heic)")
    }

    func testRichTextCodecCreatesAttachmentAndCaptionForStandaloneImageMarkdown() {
        let vaultURL = URL(fileURLWithPath: "/tmp/vault", isDirectory: true)
        let noteURL = vaultURL.appendingPathComponent("Notes/Daily.md")
        let attributed = FlintRichTextCodec.attributedString(
            from: "![System Diagram](../Attachments/diagram.jpg)",
            noteURL: noteURL,
            vaultURL: vaultURL
        )

        XCTAssertTrue(attributed.attribute(.attachment, at: 0, effectiveRange: nil) is FlintMarkdownImageAttachment)
        XCTAssertEqual(attributed.string, "\(Character(UnicodeScalar(NSTextAttachment.character)!))\nSystem Diagram")

        let captionRange = (attributed.string as NSString).range(of: "System Diagram")
        XCTAssertEqual(
            attributed.attribute(.flintSyntheticImageCaption, at: captionRange.location, effectiveRange: nil) as? Bool,
            true
        )
    }

    func testImportImageUsesSelectedNoteAndVaultContext() async {
        let bookmarkStore = BookmarkStoreSpy()
        let fileService = FileServiceSpy()
        let noteURL = URL(fileURLWithPath: "/tmp/default-vault/Daily.md")
        let note = makeNote(title: "Daily", url: noteURL)
        let sourceURL = URL(fileURLWithPath: "/tmp/imports/diagram.heic")
        fileService.notesToReturn = [note]

        let model = AppModel(bookmarkStore: bookmarkStore, fileService: fileService)
        await model.openVault(at: fileService.createdVaultURL)
        await model.openNote(note)

        let inserted = await model.importImage(from: sourceURL, preferredFilename: "Diagram")

        XCTAssertEqual(fileService.importedImages.count, 1)
        XCTAssertEqual(fileService.importedImages.first?.0, sourceURL)
        XCTAssertEqual(fileService.importedImages.first?.1, "Diagram")
        XCTAssertEqual(fileService.importedImages.first?.2, noteURL)
        XCTAssertEqual(fileService.importedImages.first?.3, fileService.createdVaultURL)
        XCTAssertEqual(inserted?.markdownSource, "![Imported](Daily Assets/imported.jpg)")
    }

    func testImportCameraImageUsesSelectedNoteAndVaultContext() async {
        let bookmarkStore = BookmarkStoreSpy()
        let fileService = FileServiceSpy()
        let noteURL = URL(fileURLWithPath: "/tmp/default-vault/Daily.md")
        let note = makeNote(title: "Daily", url: noteURL)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        }
        fileService.notesToReturn = [note]

        let model = AppModel(bookmarkStore: bookmarkStore, fileService: fileService)
        await model.openVault(at: fileService.createdVaultURL)
        await model.openNote(note)

        let inserted = await model.importCameraImage(image)

        XCTAssertEqual(fileService.importedCameraImages.count, 1)
        XCTAssertEqual(fileService.importedCameraImages.first?.1, noteURL)
        XCTAssertEqual(fileService.importedCameraImages.first?.2, fileService.createdVaultURL)
        XCTAssertEqual(inserted?.markdownSource, "![Camera](Daily Assets/camera.jpg)")
    }

    func testRichTextCodecTracksSemanticBoldAndItalicAttributes() {
        let markdown = """
        # Title

        Use **bold**, *italic*, and ***both***.
        """

        let attributed = FlintRichTextCodec.attributedString(from: markdown)
        let string = attributed.string as NSString

        let headingState = FlintRichTextCodec.formattingState(
            attributedString: attributed,
            selectedRange: NSRange(location: 0, length: 0),
            undoManager: nil
        )
        XCTAssertFalse(headingState.isBold)
        XCTAssertFalse(headingState.isItalic)

        let boldRange = string.range(of: "bold")
        XCTAssertEqual(attributed.attribute(.flintBold, at: boldRange.location, effectiveRange: nil) as? Bool, true)
        XCTAssertNil(attributed.attribute(.flintItalic, at: boldRange.location, effectiveRange: nil))

        let italicRange = string.range(of: "italic")
        XCTAssertEqual(attributed.attribute(.flintItalic, at: italicRange.location, effectiveRange: nil) as? Bool, true)
        XCTAssertNil(attributed.attribute(.flintBold, at: italicRange.location, effectiveRange: nil))

        let bothRange = string.range(of: "both")
        let emphasisState = FlintRichTextCodec.formattingState(
            attributedString: attributed,
            selectedRange: NSRange(location: bothRange.location, length: 0),
            undoManager: nil
        )
        XCTAssertTrue(emphasisState.isBold)
        XCTAssertTrue(emphasisState.isItalic)
    }

    func testRichTextCodecAppliesBlockStyleAcrossMultipleParagraphsWithoutCorruptingAdjacentContent() {
        let markdown = """
        - one
        - two

        > keep me
        """

        let attributed = FlintRichTextCodec.attributedString(from: markdown)
        let string = attributed.string as NSString
        let secondRange = string.range(of: "•\ttwo")
        let paragraphRange = string.paragraphRange(for: NSRange(location: 0, length: NSMaxRange(secondRange)))

        FlintRichTextCodec.applyBlockStyle(.body, to: attributed, paragraphRange: paragraphRange)

        XCTAssertEqual(FlintRichTextCodec.markdown(from: attributed), "one\ntwo\n\n> keep me")

        let updatedString = attributed.string as NSString
        let quoteRange = updatedString.range(of: "keep me")
        XCTAssertEqual(FlintRichTextCodec.blockStyle(at: quoteRange.location, in: attributed), .quote)
    }

    func testRichTextCodecPreservesLiteralContentInsideFencedCodeBlocks() {
        let markdown = """
        ```
        *ptr* [x](y)
        ```
        """

        let attributed = FlintRichTextCodec.attributedString(from: markdown)
        XCTAssertEqual(attributed.string, "*ptr* [x](y)")
        XCTAssertEqual(FlintRichTextCodec.blockStyle(at: 0, in: attributed), .codeBlock)

        let string = attributed.string as NSString
        let codeRange = string.range(of: "*ptr* [x](y)")
        XCTAssertNotEqual(codeRange.location, NSNotFound)
        guard codeRange.location != NSNotFound else { return }
        XCTAssertNil(attributed.attribute(.link, at: codeRange.location, effectiveRange: nil))
        XCTAssertNil(attributed.attribute(.flintBold, at: codeRange.location, effectiveRange: nil))
        XCTAssertNil(attributed.attribute(.flintItalic, at: codeRange.location, effectiveRange: nil))
        XCTAssertEqual(FlintRichTextCodec.markdown(from: attributed), markdown)
    }

    func testRichTextCodecRoundTripsEscapedLiteralMarkdownPunctuation() {
        let markdown = #"""
        Literal \*asterisk\*, \_underscore\_, \[brackets\], \\ slash, and \`tick\`
        """#

        let attributed = FlintRichTextCodec.attributedString(from: markdown)

        XCTAssertEqual(attributed.string, #"Literal *asterisk*, _underscore_, [brackets], \ slash, and `tick`"#)
        XCTAssertEqual(FlintRichTextCodec.markdown(from: attributed), markdown)
    }

    func testVaultFolderBuildsNestedTreeFromNotes() {
        let notes = [
            makeNote(
                title: "Root",
                url: URL(fileURLWithPath: "/tmp/vault/root.md"),
                folderPath: "",
                createdAt: .init(timeIntervalSince1970: 100)
            ),
            makeNote(
                title: "API",
                url: URL(fileURLWithPath: "/tmp/vault/Projects/iOS/api.md"),
                folderPath: "Projects/iOS",
                createdAt: .init(timeIntervalSince1970: 200)
            ),
            makeNote(
                title: "Runbook",
                url: URL(fileURLWithPath: "/tmp/vault/Projects/iOS/runbook.md"),
                folderPath: "Projects/iOS",
                createdAt: .init(timeIntervalSince1970: 300)
            ),
            makeNote(
                title: "Zed",
                url: URL(fileURLWithPath: "/tmp/vault/Zeta/zed.md"),
                folderPath: "Zeta",
                createdAt: .init(timeIntervalSince1970: 50)
            )
        ]

        let root = VaultFolder.root(vaultName: "Flint Vault", notes: notes)

        XCTAssertEqual(root.notes.map(\.title), ["Root"])
        XCTAssertEqual(root.childFolders.first?.name, "Projects")
        XCTAssertEqual(root.childFolders.last?.name, "Zeta")
        XCTAssertEqual(root.childFolders.first?.childFolders.first?.name, "iOS")
        XCTAssertEqual(root.childFolders.first?.childFolders.first?.notes.map(\.title), ["Runbook", "API"])
    }
}

private final class BookmarkStoreSpy: VaultBookmarkStoring {
    var storedBookmarkData: Data?
    var savedBookmarkData: Data?
    var resolveCalls = 0
    var resolveError: Error?

    func loadBookmarkData() -> Data? {
        storedBookmarkData
    }

    func saveBookmarkData(_ data: Data) {
        savedBookmarkData = data
        storedBookmarkData = data
    }

    func clearBookmarkData() {
        storedBookmarkData = nil
    }

    func makeBookmark(for url: URL, request: ProviderRequest) async throws -> Data {
        Data("bookmark".utf8)
    }

    func resolveBookmarkData(_ data: Data, request: ProviderRequest) async throws -> URL {
        resolveCalls += 1
        if let resolveError { throw resolveError }
        return URL(fileURLWithPath: "/tmp/resolved-vault", isDirectory: true)
    }
}

@MainActor
private final class FileServiceSpy: VaultFileServing {
    var createdVaultURL = URL(fileURLWithPath: "/tmp/default-vault", isDirectory: true)
    var notesToReturn: [NoteItem] = []
    var notesAfterSave: [NoteItem]?
    var listHook: ((URL, ProviderRequest) async throws -> [NoteItem])?
    var readHook: ((URL, ProviderRequest) async throws -> String)?
    var saveHook: ((String, URL, ProviderRequest) async throws -> Void)?
    var createHook: ((String, URL, ProviderRequest) async throws -> URL)?
    var createVaultCalls: [(String, URL)] = []
    var createdNoteCalls: [(String, URL)] = []
    var listMarkdownNotesCalls: [URL] = []
    var savedNotes: [(String, URL)] = []
    var noteContents: [URL: String] = [:]
    var readNoteCalls: [URL] = []
    var imageImportHook: ((ProviderRequest) async throws -> InsertedNoteImage)?
    var importedImages: [(URL, String?, URL, URL)] = []
    var importedCameraImages: [(UIImage, URL, URL)] = []

    func createVault(named name: String, in parentURL: URL, request: ProviderRequest) async throws -> URL {
        createVaultCalls.append((name, parentURL))
        if let createHook { return try await createHook(name, parentURL, request) }
        return createdVaultURL
    }

    func listMarkdownNotes(in vaultURL: URL, request: ProviderRequest) async throws -> [NoteItem] {
        listMarkdownNotesCalls.append(vaultURL)
        if let listHook { return try await listHook(vaultURL, request) }
        if let notesAfterSave, !savedNotes.isEmpty {
            return notesAfterSave
        }
        return notesToReturn
    }

    func createNote(named name: String, in vaultURL: URL, request: ProviderRequest) async throws -> URL {
        createdNoteCalls.append((name, vaultURL))
        let url = vaultURL.appendingPathComponent(name)
        if notesToReturn.contains(where: { $0.url == url }) { throw VaultError.itemAlreadyExists(name) }
        notesToReturn.append(makeNote(title: name, url: url))
        return url
    }

    func readNote(at url: URL, request: ProviderRequest) async throws -> String {
        readNoteCalls.append(url)
        if let readHook { return try await readHook(url, request) }
        return noteContents[url] ?? ""
    }

    func saveNote(_ text: String, at url: URL, request: ProviderRequest) async throws {
        savedNotes.append((text, url))
        if let saveHook { try await saveHook(text, url, request) }
    }

    func importImage(from sourceURL: URL, preferredFilename: String?, into noteURL: URL, vaultURL: URL, request: ProviderRequest) async throws -> InsertedNoteImage {
        importedImages.append((sourceURL, preferredFilename, noteURL, vaultURL))
        if let imageImportHook { return try await imageImportHook(request) }
        return InsertedNoteImage(
            markdownSource: "![Imported](Daily Assets/imported.jpg)",
            assetURL: noteURL.deletingLastPathComponent().appendingPathComponent("Daily Assets/imported.jpg"),
            altText: "Imported"
        )
    }

    func importCameraImage(_ image: UIImage, into noteURL: URL, vaultURL: URL, request: ProviderRequest) async throws -> InsertedNoteImage {
        importedCameraImages.append((image, noteURL, vaultURL))
        if let imageImportHook { return try await imageImportHook(request) }
        return InsertedNoteImage(
            markdownSource: "![Camera](Daily Assets/camera.jpg)",
            assetURL: noteURL.deletingLastPathComponent().appendingPathComponent("Daily Assets/camera.jpg"),
            altText: "Camera"
        )
    }
}

private func makeNote(
    title: String,
    url: URL,
    folderPath: String = "",
    createdAt: Date = .distantPast,
    modifiedAt: Date = .distantPast
) -> NoteItem {
    NoteItem(
        url: url,
        title: title,
        relativePath: folderPath.isEmpty ? "\(title).md" : "\(folderPath)/\(title).md",
        folderPath: folderPath,
        folderName: folderPath.components(separatedBy: "/").last.flatMap { $0.isEmpty ? nil : $0 } ?? "Vault",
        previewMarkdown: "Preview for \(title)",
        createdAt: createdAt,
        lastModifiedAt: modifiedAt
    )
}

private final class RestorationSafetySpy: RestorationSafetyChecking {
    var allowed = true
    var explicitAttempts: [Bool] = []
    var completions: [Bool] = []
    var finishHook: (() async -> Void)?
    func begin(launchID: UUID, explicit: Bool) async -> Bool { explicitAttempts.append(explicit); return allowed }
    func finish(completed: Bool) async { completions.append(completed); await finishHook?() }
}

private final class ModelTestTime {
    private let lock = NSLock(); private var time = 0.0
    var now: Double { lock.lock(); defer { lock.unlock() }; return time }
    func advance(_ seconds: Double) { lock.lock(); time += seconds; lock.unlock() }
}
