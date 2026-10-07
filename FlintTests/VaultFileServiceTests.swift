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

    func testMetadataBatchesAreBoundedFilterRegularFilesAndDoNotReadContents() async throws {
        for index in 0..<130 {
            // Invalid UTF-8 proves discovery does not read/decode the source.
            try Data([0xff]).write(to: temporaryDirectoryURL.appendingPathComponent("Note \(index).md"))
        }
        try "hidden".write(to: temporaryDirectoryURL.appendingPathComponent(".Hidden.md"), atomically: true, encoding: .utf8)
        try "ignored".write(to: temporaryDirectoryURL.appendingPathComponent("Other.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL.appendingPathComponent("Directory.md"), withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: temporaryDirectoryURL.appendingPathComponent("Link.md"), withDestinationURL: temporaryDirectoryURL.appendingPathComponent("Note 0.md"))
        let executor = ProviderExecutor()
        let service = VaultFileService(executor: executor, metadata: { url in
            XCTAssertFalse(Thread.isMainThread)
            return try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        })
        var cursor: NoteDiscoveryCursor?, notes: [NoteItem] = [], batches = 0
        repeat {
            let batch = try await service.discoverNotes(in: temporaryDirectoryURL, cursor: cursor, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
            XCTAssertLessThanOrEqual(batch.notes.count, 64); XCTAssertLessThanOrEqual(batch.examinedCount, 256)
            XCTAssertFalse(batch.incomplete); XCTAssertEqual(executor.counts.active, 0)
            notes += batch.notes; cursor = batch.cursor; batches += 1
        } while cursor != nil
        XCTAssertGreaterThanOrEqual(batches, 3); XCTAssertEqual(notes.count, 130)
        XCTAssertTrue(notes.allSatisfy { $0.previewMarkdown.isEmpty })
        do {
            _ = try await service.readNote(at: notes[0].url, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
            XCTFail("Invalid content must fail only on explicit read")
        } catch { XCTAssertEqual((error as NSError).code, NSFileReadInapplicableStringEncodingError) }
    }

    func testUnavailableMetadataPreservesUsableNotesAndMarksDiscoveryIncomplete() async throws {
        let available = temporaryDirectoryURL.appendingPathComponent("Available.md")
        let unavailable = temporaryDirectoryURL.appendingPathComponent("Unavailable.md")
        try "body".write(to: available, atomically: true, encoding: .utf8)
        try "body".write(to: unavailable, atomically: true, encoding: .utf8)
        let service = VaultFileService(metadata: { url in
            if url == unavailable { throw CocoaError(.fileReadNoPermission) }
            return try url.resourceValues(forKeys: [.isRegularFileKey])
        })
        let batch = try await service.discoverNotes(in: temporaryDirectoryURL, cursor: nil, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        XCTAssertEqual(batch.notes.map(\.url), [available]); XCTAssertTrue(batch.incomplete)
        XCTAssertNil(batch.cursor)
    }

    func testMissingRegularFileMetadataIsIncompleteRatherThanEmptySuccess() async throws {
        try "note".write(to: temporaryDirectoryURL.appendingPathComponent("Note.md"), atomically: true, encoding: .utf8)
        let service = VaultFileService(metadata: { _ in URLResourceValues() })
        let batch = try await service.discoverNotes(in: temporaryDirectoryURL, cursor: nil, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        XCTAssertTrue(batch.notes.isEmpty); XCTAssertTrue(batch.incomplete); XCTAssertNil(batch.cursor)
    }

    func testPreviewSourceBudgetUTF8BoundaryEmptyAndInvalidContent() async throws {
        let url = temporaryDirectoryURL.appendingPathComponent("Prefix.md")
        var bytes = Data("Visible paragraph\n".utf8)
        bytes.append(Data(repeating: 0x61, count: 64 * 1024 - bytes.count - 1))
        bytes.append(contentsOf: "😀after the prefix".utf8)
        try bytes.write(to: url)
        let notes = try await service.listMarkdownNotes(in: temporaryDirectoryURL, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        let preview = try await service.readPreview(for: XCTUnwrap(notes.first), request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        XCTAssertEqual(preview, .available("Visible paragraph", truncated: true))
        XCTAssertEqual(try VaultFileService.decodePreviewPrefix(Data([0x61, 0xf0, 0x9f, 0x98]), truncated: true), "a")
        XCTAssertThrowsError(try VaultFileService.decodePreviewPrefix(Data([0xff, 0xf0]), truncated: true))
        XCTAssertThrowsError(try VaultFileService.decodePreviewPrefix(Data([0xe0, 0x80]), truncated: true))
        XCTAssertThrowsError(try VaultFileService.decodePreviewPrefix(Data([0xf0, 0x9f]), truncated: false))
        try Data().write(to: url)
        let empty = try await service.readPreview(for: notes[0], request: ProviderRequest(vaultURL: temporaryDirectoryURL))
        XCTAssertEqual(empty, .empty)
        var offset = 0, requested = 0
        let prefix = try VaultFileService.readPrefix(limit: 64 * 1024) { count in
            requested += count; let end = min(offset + count, bytes.count)
            defer { offset = end }; return bytes.subdata(in: offset..<end)
        }
        XCTAssertEqual(prefix.data.count, 64 * 1024); XCTAssertEqual(requested, 64 * 1024)
    }

    func testEditableReadEnforcesActualByteLimitAndDoesNotChangeOversizedFile() async throws {
        let limit = 8 * 1024 * 1024
        let url = temporaryDirectoryURL.appendingPathComponent("Large.md")
        let bytes = Data(repeating: 0x61, count: limit + 100)
        try bytes.write(to: url)
        do {
            _ = try await service.readNote(at: url, request: ProviderRequest(vaultURL: temporaryDirectoryURL))
            XCTFail("Oversized note must not return partial editable content")
        } catch { XCTAssertEqual(error as? VaultError, .noteTooLarge) }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        var countRead = 0
        XCTAssertThrowsError(try VaultFileService.readEditable { count in
            // No metadata; simulate a source continuing to grow during the read.
            countRead += count; return Data(repeating: 0x61, count: count)
        }) { XCTAssertEqual($0 as? VaultError, .noteTooLarge) }
        XCTAssertEqual(countRead, limit + 1)
        var remaining = limit
        let exact = try VaultFileService.readEditable { count in
            let taken = min(count, remaining); remaining -= taken
            return Data(repeating: 0x61, count: taken)
        }
        XCTAssertEqual(exact.utf8.count, limit)
        var reads = 0
        XCTAssertThrowsError(try VaultFileService.readEditable { _ in
            reads += 1
            if reads == 1 { return Data("partial".utf8) }
            throw CocoaError(.fileReadUnknown)
        })
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
        let preview = try await service.readPreview(for: XCTUnwrap(notes.first), request: ProviderRequest(vaultURL: vaultURL))
        XCTAssertEqual(preview, .available("Updated body", truncated: false))
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
        XCTAssertEqual(notes.first?.previewMarkdown, "")
        let preview = try await service.readPreview(for: XCTUnwrap(notes.first), request: ProviderRequest(vaultURL: vaultURL))
        XCTAssertEqual(preview, .available("second note body", truncated: false))
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

        let preview = try await service.readPreview(for: XCTUnwrap(notes.first), request: ProviderRequest(vaultURL: vaultURL))
        XCTAssertEqual(
            preview,
            .available("""
            Intro with **bold** text.

            ✓ Done
            ○ Next
            """, truncated: false)
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

        let preview = try await service.readPreview(for: XCTUnwrap(notes.first), request: ProviderRequest(vaultURL: vaultURL))
        XCTAssertEqual(preview, .available("○ mention [x] syntax", truncated: false))
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
