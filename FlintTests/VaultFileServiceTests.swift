import XCTest
import UIKit
@testable import Flint

final class VaultFileServiceTests: XCTestCase {
    private var temporaryDirectoryURL: URL!
    private var service: VaultFileService!

    override func setUpWithError() throws {
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        service = VaultFileService()
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: temporaryDirectoryURL.path) {
            try FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
    }

    func testDiscoveryBatchesFilterFilesAndDoNotReadInvalidContent() async throws {
        let root = temporaryDirectoryURL!
        for index in 0..<140 {
            try Data([0xff]).write(to: root.appendingPathComponent("Note \(index).md"))
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Directory.md"), withIntermediateDirectories: false)
        try "hidden".write(to: root.appendingPathComponent(".Hidden.md"), atomically: true, encoding: .utf8)
        var batches: [[NoteItem]] = []
        try await service.discoverNotes(in: root, request: ProviderRequest(vaultURL: root)) { batches.append($0) }
        XCTAssertGreaterThan(batches.count, 2)
        XCTAssertTrue(batches.allSatisfy { $0.count <= 64 })
        let notes = batches.flatMap { $0 }
        XCTAssertEqual(notes.count, 140)
        XCTAssertTrue(notes.allSatisfy { $0.previewMarkdown.isEmpty })
        XCTAssertEqual(service.cachedPreviewBytes, 0)
        do {
            _ = try await service.readNote(at: notes[0].url, request: ProviderRequest(vaultURL: root))
            XCTFail("Invalid content must fail separately from discovery")
        } catch { XCTAssertEqual((error as NSError).code, NSFileReadInapplicableStringEncodingError) }
    }

    func testPreviewPrefixHandlesSplitUTF8AndInvalidatesAfterSave() async throws {
        let root = temporaryDirectoryURL!
        let url = root.appendingPathComponent("Prefix.md")
        let prefix = "Preview body\n" + String(repeating: "a", count: 65535 - "Preview body\n".utf8.count)
        try (prefix + "😀tail").write(to: url, atomically: true, encoding: .utf8)
        let notes = try await service.listMarkdownNotes(in: root, request: ProviderRequest(vaultURL: root))
        let note = try XCTUnwrap(notes.first)
        let preview = try await service.preview(for: note, request: ProviderRequest(vaultURL: root))
        XCTAssertEqual(preview, .ready("Preview body", truncated: true))
        XCTAssertGreaterThan(service.cachedPreviewBytes, 0)
        try await service.saveNote("Changed", at: url, request: ProviderRequest(vaultURL: root))
        let changed = try await service.preview(for: note, request: ProviderRequest(vaultURL: root))
        XCTAssertEqual(changed, .ready("Changed", truncated: false))
        service.invalidatePreviews()
        XCTAssertEqual(service.cachedPreviewBytes, 0)
    }

    func testReadEnforcesEightMiBLimitWithoutReturningPartialDocument() async throws {
        let root = temporaryDirectoryURL!, url = root.appendingPathComponent("Large.md")
        let limit = 8 * 1024 * 1024
        try Data(repeating: 97, count: limit).write(to: url)
        let accepted = try await service.readNote(at: url, request: ProviderRequest(vaultURL: root))
        XCTAssertEqual(accepted.utf8.count, limit)
        try Data(repeating: 98, count: limit + 1).write(to: url)
        do {
            _ = try await service.readNote(at: url, request: ProviderRequest(vaultURL: root))
            XCTFail("Oversized document must not return editable partial text")
        } catch { XCTAssertEqual(error as? VaultError, .noteTooLarge) }
        XCTAssertEqual(try Data(contentsOf: url).count, limit + 1)
    }

    func testPreviewCacheEvictsOldEntriesWithinBudgetAndObservesVersionChanges() async throws {
        let root = temporaryDirectoryURL!
        let cachedService = VaultFileService(previewCacheLimit: 1024)
        for index in 0..<6 { try "Body \(index)".write(to: root.appendingPathComponent("Note \(index).md"), atomically: true, encoding: .utf8) }
        let notes = try await cachedService.listMarkdownNotes(in: root, request: ProviderRequest(vaultURL: root))
        for note in notes {
            _ = try await cachedService.preview(for: note, request: ProviderRequest(vaultURL: root))
            XCTAssertLessThanOrEqual(cachedService.cachedPreviewBytes, 1024)
        }
        let evicted = try XCTUnwrap(notes.first)
        let attributes = try FileManager.default.attributesOfItem(atPath: evicted.url.path)
        try "New!!!".write(to: evicted.url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: try XCTUnwrap(attributes[.modificationDate])], ofItemAtPath: evicted.url.path)
        let reloaded = try await cachedService.preview(for: evicted, request: ProviderRequest(vaultURL: root))
        XCTAssertEqual(reloaded.text, "New!!!") // Same version/size: succeeds only if the oldest entry was evicted.
        try "Observed new version".write(to: evicted.url, atomically: true, encoding: .utf8)
        let versioned = try await cachedService.preview(for: evicted, request: ProviderRequest(vaultURL: root))
        XCTAssertEqual(versioned.text, "Observed new version")
    }

    func testEmptyAndUnavailablePreviewsRemainDifferent() async throws {
        let root = temporaryDirectoryURL!, url = root.appendingPathComponent("Empty.md")
        try Data().write(to: url)
        let notes = try await service.listMarkdownNotes(in: root, request: ProviderRequest(vaultURL: root))
        let note = try XCTUnwrap(notes.first)
        let empty = try await service.preview(for: note, request: ProviderRequest(vaultURL: root))
        XCTAssertEqual(empty, .empty)
        try FileManager.default.removeItem(at: url)
        do {
            _ = try await service.preview(for: note, request: ProviderRequest(vaultURL: root))
            XCTFail("Removed file must not use cached empty success")
        } catch { XCTAssertNotNil(error) }
    }

    @MainActor
    func testImportedFileRemainsReadableAfterSourceRemovalAndModelRecreation() async throws {
        try await verifyPersistedImage(camera: false)
    }

    @MainActor
    func testCapturedImagePersistsAsJPEGAfterModelRecreation() async throws {
        try await verifyPersistedImage(camera: true)
    }

    @MainActor
    private func verifyPersistedImage(camera: Bool) async throws {
        let vault = try await service.createVault(named: "Portable", in: temporaryDirectoryURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        let noteURL = try await service.createNote(named: "Editable", in: vault, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        try await service.saveNote("Before\nAfter", at: noteURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 160)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
        }
        let source = temporaryDirectoryURL.appendingPathComponent("Original.png")
        try XCTUnwrap(image.pngData()).write(to: source)
        let model = AppModel(bookmarkStore: VaultBookmarkStore(userDefaults: UserDefaults(suiteName: UUID().uuidString)!), fileService: service)
        await model.openVault(at: vault, persistSelection: false)
        let note = try XCTUnwrap(model.notes.first { $0.url == noteURL })
        await model.openNote(note)
        let inserted: InsertedNoteImage?
        if camera { inserted = await model.importCameraImage(image) }
        else { inserted = await model.importImage(from: source, preferredFilename: "Fixture") }
        let result = try XCTUnwrap(inserted)
        XCTAssertEqual(result.assetURL.deletingLastPathComponent(), vault.appendingPathComponent("Editable Assets", isDirectory: true))
        if camera {
            XCTAssertEqual(result.assetURL.pathExtension, "jpg")
            XCTAssertEqual(try Data(contentsOf: result.assetURL).prefix(2), Data([0xff, 0xd8]))
        }
        model.updateNoteText("Before\n" + result.markdownSource + "\nAfter")
        await model.saveCurrentNoteIfNeeded()
        XCTAssertFalse(model.hasUnsavedChanges)
        try FileManager.default.removeItem(at: source)
        let reopened = AppModel(bookmarkStore: VaultBookmarkStore(userDefaults: UserDefaults(suiteName: UUID().uuidString)!), fileService: VaultFileService())
        await reopened.openVault(at: vault, persistSelection: false)
        let reopenedNote = try XCTUnwrap(reopened.notes.first { $0.url == noteURL })
        await reopened.openNote(reopenedNote)
        XCTAssertEqual(reopened.noteText, "Before\n" + result.markdownSource + "\nAfter")
        let attributed = FlintRichTextCodec.attributedString(from: reopened.noteText, noteURL: noteURL, vaultURL: vault)
        var imageURLs: [URL] = []
        attributed.enumerateAttribute(.flintImageAssetURL, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            if let url = value as? URL { imageURLs.append(url) }
        }
        XCTAssertTrue(imageURLs.contains(result.assetURL))
        XCTAssertNotNil(UIImage(contentsOfFile: result.assetURL.path))
        XCTAssertFalse(reopened.noteText.contains("file://"))
    }

    func testCreateVaultCreatesNamedDirectory() async throws {
        let vaultURL = try await service.createVault(named: "My Vault", in: temporaryDirectoryURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: vaultURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(vaultURL.lastPathComponent, "My Vault")
    }

    func testCreateListReadAndSaveMarkdownNotes() async throws {
        let vaultURL = try await service.createVault(named: "Vault", in: temporaryDirectoryURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        let noteURL = try await service.createNote(named: "Daily Note", in: vaultURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))

        XCTAssertEqual(noteURL.lastPathComponent, "Daily Note.md")
        let awaitedResult1 = try await service.readNote(at: noteURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        XCTAssertEqual(awaitedResult1, "")

        try await service.saveNote("# Daily Note\nUpdated body", at: noteURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))

        let notes = try await service.listMarkdownNotes(in: vaultURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        XCTAssertEqual(notes.map(\.relativePath), ["Daily Note.md"])
        XCTAssertEqual(notes.first?.folderPath, "")
        XCTAssertEqual(notes.first?.folderName, "Vault")
        XCTAssertEqual(notes.first?.previewMarkdown, "")
        let preview = try await service.preview(for: XCTUnwrap(notes.first), request: ProviderRequest(vaultURL: vaultURL))
        XCTAssertEqual(preview, .ready("Updated body", truncated: false))
        let awaitedResult2 = try await service.readNote(at: noteURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        XCTAssertEqual(awaitedResult2, "# Daily Note\nUpdated body")
    }

    func testCreateNoteAllowsSameNameInAnotherFolder() async throws {
        let vault = try await service.createVault(named: "Vault", in: temporaryDirectoryURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        let folder = vault.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        _ = try await service.createNote(named: "Daily", in: vault, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        let nested = try await service.createNote(named: "Daily", in: folder, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        XCTAssertEqual(nested, folder.appendingPathComponent("Daily.md"))
        let awaitedResult3 = try await service.listMarkdownNotes(in: vault, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        XCTAssertEqual(Set(awaitedResult3.map(\.relativePath)), ["Daily.md", "Projects/Daily.md"])
    }

    func testCreateNoteInSubfolder() async throws {
        let vaultURL = try await service.createVault(named: "Vault", in: temporaryDirectoryURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        let projectsURL = vaultURL.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: false)

        let noteURL = try await service.createNote(named: "Roadmap", in: projectsURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        let notes = try await service.listMarkdownNotes(in: vaultURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))

        XCTAssertEqual(noteURL.lastPathComponent, "Roadmap.md")
        XCTAssertEqual(notes.map(\.relativePath), ["Projects/Roadmap.md"])
        XCTAssertEqual(notes.first?.folderPath, "Projects")
        let awaitedResult4 = try await service.readNote(at: noteURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        XCTAssertEqual(awaitedResult4, "")
    }

    func testCreateNoteRejectsDuplicateNameInSubfolder() async throws {
        let vaultURL = try await service.createVault(named: "Vault", in: temporaryDirectoryURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        let projectsURL = vaultURL.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: false)

        _ = try await service.createNote(named: "Roadmap", in: projectsURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))

        do {
            _ = try await service.createNote(named: "Roadmap", in: projectsURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
            XCTFail("Expected duplicate rejection")
        } catch { XCTAssertEqual(error as? VaultError, .itemAlreadyExists("Roadmap.md")) }
    }

    func testListMarkdownNotesCapturesFolderPreviewAndDates() async throws {
        let vaultURL = try await service.createVault(named: "Vault", in: temporaryDirectoryURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        let projectFolderURL = vaultURL.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projectFolderURL, withIntermediateDirectories: true)

        let olderNoteURL = projectFolderURL.appendingPathComponent("Alpha.md")
        let newerNoteURL = projectFolderURL.appendingPathComponent("Beta.md")

        try "# Alpha\nfirst note body".write(to: olderNoteURL, atomically: true, encoding: .utf8)
        try "# Beta\nsecond note body".write(to: newerNoteURL, atomically: true, encoding: .utf8)

        let olderCreationDate = Date(timeIntervalSince1970: 100)
        let newerCreationDate = Date(timeIntervalSince1970: 200)
        let olderModifiedDate = Date(timeIntervalSince1970: 300)
        let newerModifiedDate = Date(timeIntervalSince1970: 400)
        try FileManager.default.setAttributes([.creationDate: olderCreationDate, .modificationDate: olderModifiedDate], ofItemAtPath: olderNoteURL.path)
        try FileManager.default.setAttributes([.creationDate: newerCreationDate, .modificationDate: newerModifiedDate], ofItemAtPath: newerNoteURL.path)

        let notes = try await service.listMarkdownNotes(in: vaultURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))

        XCTAssertEqual(notes.map(\.title), ["Beta", "Alpha"])
        XCTAssertEqual(notes.first?.folderPath, "Projects")
        XCTAssertEqual(notes.first?.folderName, "Projects")
        let preview = try await service.preview(for: XCTUnwrap(notes.first), request: ProviderRequest(vaultURL: vaultURL))
        XCTAssertEqual(preview, .ready("second note body", truncated: false))
        XCTAssertEqual(notes.first?.createdAt, newerCreationDate)
        XCTAssertEqual(notes.first?.lastModifiedAt, newerModifiedDate)
    }

    func testListMarkdownNotesBuildsMarkdownAwarePreviewExcerpt() async throws {
        let vaultURL = try await service.createVault(named: "Vault", in: temporaryDirectoryURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        let noteURL = vaultURL.appendingPathComponent("Daily.md")

        try """
        # Daily

        Intro with **bold** text.

        - [x] Done
        - [ ] Next
        > Quoted thought
        """.write(to: noteURL, atomically: true, encoding: .utf8)

        let notes = try await service.listMarkdownNotes(in: vaultURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))

        let preview = try await service.preview(for: XCTUnwrap(notes.first), request: ProviderRequest(vaultURL: vaultURL))
        XCTAssertEqual(
            preview.text,
            """
            Intro with **bold** text.

            ✓ Done
            ○ Next
            """
        )
    }

    func testListMarkdownNotesDoesNotMisreadUncheckedTaskContentAsChecked() async throws {
        let vaultURL = try await service.createVault(named: "Vault", in: temporaryDirectoryURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        let noteURL = vaultURL.appendingPathComponent("Tasks.md")

        try """
        # Tasks

        - [ ] mention [x] syntax
        """.write(to: noteURL, atomically: true, encoding: .utf8)

        let notes = try await service.listMarkdownNotes(in: vaultURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))

        let preview = try await service.preview(for: XCTUnwrap(notes.first), request: ProviderRequest(vaultURL: vaultURL))
        XCTAssertEqual(preview.text, "○ mention [x] syntax")
    }

    func testResolveImageURLSupportsVaultRootedAndRelativePathsWithinVault() async throws {
        let vaultURL = try await service.createVault(named: "Vault", in: temporaryDirectoryURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        let noteURL = vaultURL.appendingPathComponent("Notes/Daily.md")

        let rootResolved = VaultFileService.resolveImageURL(
            markdownPath: "/Attachments/diagram.heic",
            noteURL: noteURL,
            vaultURL: vaultURL
        )
        let relativeResolved = VaultFileService.resolveImageURL(
            markdownPath: "../Shared/diagram.jpg",
            noteURL: noteURL,
            vaultURL: vaultURL.appendingPathComponent("Notes", isDirectory: true)
        )

        XCTAssertEqual(rootResolved, vaultURL.appendingPathComponent("Attachments/diagram.heic"))
        XCTAssertNil(relativeResolved)
    }

    func testResolveImageURLRejectsSymlinkEscapingVault() async throws {
        let vaultURL = try await service.createVault(named: "Vault", in: temporaryDirectoryURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        let noteFolderURL = vaultURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: noteFolderURL, withIntermediateDirectories: true)
        let noteURL = noteFolderURL.appendingPathComponent("Daily.md")
        try "".write(to: noteURL, atomically: true, encoding: .utf8)

        let outsideDirectoryURL = temporaryDirectoryURL.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideDirectoryURL, withIntermediateDirectories: true)

        let symlinkURL = vaultURL.appendingPathComponent("Attachments", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: outsideDirectoryURL)

        let resolved = VaultFileService.resolveImageURL(
            markdownPath: "/Attachments/diagram.heic",
            noteURL: noteURL,
            vaultURL: vaultURL
        )

        XCTAssertNil(resolved)
    }

    func testImportCameraImageCreatesManagedJPEGReference() async throws {
        let vaultURL = try await service.createVault(named: "Vault", in: temporaryDirectoryURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        let noteURL = try await service.createNote(named: "Daily", in: vaultURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }

        let inserted = try await service.importCameraImage(image, into: noteURL, vaultURL: vaultURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))

        XCTAssertTrue(FileManager.default.fileExists(atPath: inserted.assetURL.path))
        XCTAssertEqual(inserted.assetURL.pathExtension.lowercased(), "jpg")
        XCTAssertTrue(inserted.markdownSource.contains("![")) 
        XCTAssertTrue(inserted.markdownSource.contains("Daily Assets/"))
    }

    func testImportImagePreservesReadableSourceFormatAndCreatesRelativeMarkdownReference() async throws {
        let vaultURL = try await service.createVault(named: "Vault", in: temporaryDirectoryURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        let noteFolderURL = vaultURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: noteFolderURL, withIntermediateDirectories: true)
        let noteURL = noteFolderURL.appendingPathComponent("Daily.md")
        try "".write(to: noteURL, atomically: true, encoding: .utf8)

        let sourceURL = temporaryDirectoryURL.appendingPathComponent("diagram.heic")
        try Data("heic".utf8).write(to: sourceURL)

        let inserted = try await service.importImage(from: sourceURL, preferredFilename: "System Diagram", into: noteURL, vaultURL: vaultURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))

        XCTAssertTrue(FileManager.default.fileExists(atPath: inserted.assetURL.path))
        XCTAssertEqual(inserted.assetURL.pathExtension.lowercased(), "heic")
        XCTAssertEqual(inserted.altText, "System Diagram")
        XCTAssertEqual(inserted.markdownSource, "![System Diagram](Daily Assets/System Diagram.heic)")
    }
}
