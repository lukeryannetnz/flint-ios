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
        XCTAssertEqual(try service.readNote(at: noteURL), "# Daily Note\nUpdated body")
    }
}
