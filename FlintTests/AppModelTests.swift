import XCTest
@testable import Flint

@MainActor
final class AppModelTests: XCTestCase {
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
        await model.saveCurrentNoteIfNeeded()

        XCTAssertEqual(fileService.savedNotes.count, 1)
        XCTAssertEqual(fileService.listMarkdownNotesCalls.count, 2)
        XCTAssertEqual(model.selectedNote?.lastModifiedAt, refreshedNote.lastModifiedAt)
    }

    func testMarkdownDocumentRendersRichHTML() {
        let markdown = """
        # Daily

        Intro paragraph with a [link](https://example.com).

        - one
        - two

        1. first
        2. second

        - [x] done
        - [ ] next

        > quoted line

        | Name | Value |
        | --- | --- |
        | Flint | Spark |

        ```swift
        print("hi")
        ```

        ![Sketch](diagram.png)
        """

        let document = MarkdownDocument(noteTitle: "Daily", markdown: markdown)

        XCTAssertFalse(document.markdown.hasPrefix("# Daily"))
        XCTAssertTrue(document.html.contains("<a href=\"https://example.com\">link</a>"))
        XCTAssertTrue(document.html.contains("<ul><li>one</li><li>two</li></ul>"))
        XCTAssertTrue(document.html.contains("<ol><li>first</li><li>second</li></ol>"))
        XCTAssertTrue(document.html.contains("<ul class=\"task-list\">"))
        XCTAssertTrue(document.html.contains("<blockquote><p>quoted line</p></blockquote>"))
        XCTAssertTrue(document.html.contains("<table>"))
        XCTAssertTrue(document.html.contains("<pre><code class=\"language-swift\">"))
        XCTAssertTrue(document.html.contains("<figure class=\"md-image\"><img src=\"diagram.png\" alt=\"Sketch\" loading=\"lazy\"><figcaption>Sketch</figcaption></figure>"))
    }

    func testMarkdownDocumentRendersYouTubeEmbedAsThumbnail() {
        let markdown = """
        ![Embedded YouTube video](https://www.youtube.com/embed/k51Q4ibkhDk?feature=oembed&autoplay=true)
        """

        let document = MarkdownDocument(noteTitle: "Video", markdown: markdown)

        XCTAssertTrue(document.html.contains("class=\"md-video-thumb\""))
        XCTAssertTrue(document.html.contains("https://www.youtube.com/watch?v=k51Q4ibkhDk"))
        XCTAssertTrue(document.html.contains("https://i.ytimg.com/vi/k51Q4ibkhDk/hqdefault.jpg"))
        XCTAssertTrue(document.html.contains("<figcaption>Embedded YouTube video</figcaption>"))
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

    func makeBookmark(for url: URL) throws -> Data {
        Data("bookmark".utf8)
    }

    func resolveBookmarkData(_ data: Data) throws -> URL {
        URL(fileURLWithPath: "/tmp/resolved-vault", isDirectory: true)
    }
}

private final class FileServiceSpy: VaultFileServing {
    var createdVaultURL = URL(fileURLWithPath: "/tmp/default-vault", isDirectory: true)
    var notesToReturn: [NoteItem] = []
    var notesAfterSave: [NoteItem]?
    var createVaultCalls: [(String, URL)] = []
    var listMarkdownNotesCalls: [URL] = []
    var savedNotes: [(String, URL)] = []

    func createVault(named name: String, in parentURL: URL) throws -> URL {
        createVaultCalls.append((name, parentURL))
        return createdVaultURL
    }

    func listMarkdownNotes(in vaultURL: URL) throws -> [NoteItem] {
        listMarkdownNotesCalls.append(vaultURL)
        if let notesAfterSave, !savedNotes.isEmpty {
            return notesAfterSave
        }
        return notesToReturn
    }

    func createNote(named name: String, in vaultURL: URL) throws -> URL {
        vaultURL.appendingPathComponent(name)
    }

    func readNote(at url: URL) throws -> String {
        ""
    }

    func saveNote(_ text: String, at url: URL) throws {
        savedNotes.append((text, url))
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
