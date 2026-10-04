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
        let vault = try service.createVault(named: "Portable", in: temporaryDirectoryURL)
        let noteURL = try service.createNote(named: "Editable", in: vault)
        try service.saveNote("Before\nAfter", at: noteURL)
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

    func testCreateVaultCreatesNamedDirectory() throws {
        let vaultURL = try service.createVault(named: "My Vault", in: temporaryDirectoryURL)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: vaultURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(vaultURL.lastPathComponent, "My Vault")
    }

    func testCreateListReadAndSaveMarkdownNotes() throws {
        let vaultURL = try service.createVault(named: "Vault", in: temporaryDirectoryURL)
        let noteURL = try service.createNote(named: "Daily Note", in: vaultURL)

        XCTAssertEqual(noteURL.lastPathComponent, "Daily Note.md")
        XCTAssertEqual(try service.readNote(at: noteURL), "")

        try service.saveNote("# Daily Note\nUpdated body", at: noteURL)

        let notes = try service.listMarkdownNotes(in: vaultURL)
        XCTAssertEqual(notes.map(\.relativePath), ["Daily Note.md"])
        XCTAssertEqual(notes.first?.folderPath, "")
        XCTAssertEqual(notes.first?.folderName, "Vault")
        XCTAssertEqual(notes.first?.previewMarkdown, "Updated body")
        XCTAssertEqual(try service.readNote(at: noteURL), "# Daily Note\nUpdated body")
    }

    func testCreateNoteAllowsSameNameInAnotherFolder() throws {
        let vault = try service.createVault(named: "Vault", in: temporaryDirectoryURL)
        let folder = vault.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        _ = try service.createNote(named: "Daily", in: vault)
        let nested = try service.createNote(named: "Daily", in: folder)
        XCTAssertEqual(nested, folder.appendingPathComponent("Daily.md"))
        XCTAssertEqual(Set(try service.listMarkdownNotes(in: vault).map(\.relativePath)), ["Daily.md", "Projects/Daily.md"])
    }

    func testCreateNoteInSubfolder() throws {
        let vaultURL = try service.createVault(named: "Vault", in: temporaryDirectoryURL)
        let projectsURL = vaultURL.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: false)

        let noteURL = try service.createNote(named: "Roadmap", in: projectsURL)
        let notes = try service.listMarkdownNotes(in: vaultURL)

        XCTAssertEqual(noteURL.lastPathComponent, "Roadmap.md")
        XCTAssertEqual(notes.map(\.relativePath), ["Projects/Roadmap.md"])
        XCTAssertEqual(notes.first?.folderPath, "Projects")
        XCTAssertEqual(try service.readNote(at: noteURL), "")
    }

    func testCreateNoteRejectsDuplicateNameInSubfolder() throws {
        let vaultURL = try service.createVault(named: "Vault", in: temporaryDirectoryURL)
        let projectsURL = vaultURL.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: false)

        _ = try service.createNote(named: "Roadmap", in: projectsURL)

        XCTAssertThrowsError(try service.createNote(named: "Roadmap", in: projectsURL)) { error in
            XCTAssertEqual(error as? VaultError, .itemAlreadyExists("Roadmap.md"))
        }
    }

    func testListMarkdownNotesCapturesFolderPreviewAndDates() throws {
        let vaultURL = try service.createVault(named: "Vault", in: temporaryDirectoryURL)
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

        let notes = try service.listMarkdownNotes(in: vaultURL)

        XCTAssertEqual(notes.map(\.title), ["Beta", "Alpha"])
        XCTAssertEqual(notes.first?.folderPath, "Projects")
        XCTAssertEqual(notes.first?.folderName, "Projects")
        XCTAssertEqual(notes.first?.previewMarkdown, "second note body")
        XCTAssertEqual(notes.first?.createdAt, newerCreationDate)
        XCTAssertEqual(notes.first?.lastModifiedAt, newerModifiedDate)
    }

    func testListMarkdownNotesBuildsMarkdownAwarePreviewExcerpt() throws {
        let vaultURL = try service.createVault(named: "Vault", in: temporaryDirectoryURL)
        let noteURL = vaultURL.appendingPathComponent("Daily.md")

        try """
        # Daily

        Intro with **bold** text.

        - [x] Done
        - [ ] Next
        > Quoted thought
        """.write(to: noteURL, atomically: true, encoding: .utf8)

        let notes = try service.listMarkdownNotes(in: vaultURL)

        XCTAssertEqual(
            notes.first?.previewMarkdown,
            """
            Intro with **bold** text.

            ✓ Done
            ○ Next
            """
        )
    }

    func testListMarkdownNotesDoesNotMisreadUncheckedTaskContentAsChecked() throws {
        let vaultURL = try service.createVault(named: "Vault", in: temporaryDirectoryURL)
        let noteURL = vaultURL.appendingPathComponent("Tasks.md")

        try """
        # Tasks

        - [ ] mention [x] syntax
        """.write(to: noteURL, atomically: true, encoding: .utf8)

        let notes = try service.listMarkdownNotes(in: vaultURL)

        XCTAssertEqual(notes.first?.previewMarkdown, "○ mention [x] syntax")
    }

    func testResolveImageURLSupportsVaultRootedAndRelativePathsWithinVault() throws {
        let vaultURL = try service.createVault(named: "Vault", in: temporaryDirectoryURL)
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

    func testResolveImageURLRejectsSymlinkEscapingVault() throws {
        let vaultURL = try service.createVault(named: "Vault", in: temporaryDirectoryURL)
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

    func testImportCameraImageCreatesManagedJPEGReference() throws {
        let vaultURL = try service.createVault(named: "Vault", in: temporaryDirectoryURL)
        let noteURL = try service.createNote(named: "Daily", in: vaultURL)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }

        let inserted = try service.importCameraImage(image, into: noteURL, vaultURL: vaultURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: inserted.assetURL.path))
        XCTAssertEqual(inserted.assetURL.pathExtension.lowercased(), "jpg")
        XCTAssertTrue(inserted.markdownSource.contains("![")) 
        XCTAssertTrue(inserted.markdownSource.contains("Daily Assets/"))
    }

    func testImportImagePreservesReadableSourceFormatAndCreatesRelativeMarkdownReference() throws {
        let vaultURL = try service.createVault(named: "Vault", in: temporaryDirectoryURL)
        let noteFolderURL = vaultURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: noteFolderURL, withIntermediateDirectories: true)
        let noteURL = noteFolderURL.appendingPathComponent("Daily.md")
        try "".write(to: noteURL, atomically: true, encoding: .utf8)

        let sourceURL = temporaryDirectoryURL.appendingPathComponent("diagram.heic")
        try Data("heic".utf8).write(to: sourceURL)

        let inserted = try service.importImage(from: sourceURL, preferredFilename: "System Diagram", into: noteURL, vaultURL: vaultURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: inserted.assetURL.path))
        XCTAssertEqual(inserted.assetURL.pathExtension.lowercased(), "heic")
        XCTAssertEqual(inserted.altText, "System Diagram")
        XCTAssertEqual(inserted.markdownSource, "![System Diagram](Daily Assets/System Diagram.heic)")
    }
}
