import XCTest
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
        XCTAssertEqual(try service.readNote(at: noteURL), "# Daily Note\n")

        try service.saveNote("# Daily Note\nUpdated body", at: noteURL)

        let notes = try service.listMarkdownNotes(in: vaultURL)
        XCTAssertEqual(notes.map(\.relativePath), ["Daily Note.md"])
        XCTAssertEqual(notes.first?.folderPath, "")
        XCTAssertEqual(notes.first?.folderName, "Vault")
        XCTAssertEqual(notes.first?.previewMarkdown, "Updated body")
        XCTAssertEqual(try service.readNote(at: noteURL), "# Daily Note\nUpdated body")
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
}
