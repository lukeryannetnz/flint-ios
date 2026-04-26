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

    func testCreateNoteUsesCurrentFolderContext() async {
        let bookmarkStore = BookmarkStoreSpy()
        let fileService = FileServiceSpy()
        let createdNoteURL = fileService.createdVaultURL.appendingPathComponent("Projects/iOS/Daily.md")
        let createdNote = makeNote(
            title: "Daily",
            url: createdNoteURL,
            folderPath: "Projects/iOS",
            createdAt: .init(timeIntervalSince1970: 100),
            modifiedAt: .init(timeIntervalSince1970: 100)
        )
        fileService.createdNoteURL = createdNoteURL
        fileService.notesAfterCreate = [createdNote]

        let model = AppModel(bookmarkStore: bookmarkStore, fileService: fileService)
        await model.openVault(at: fileService.createdVaultURL)
        await model.createNote(named: "Daily", inFolderPath: ["Projects", "iOS"])

        XCTAssertEqual(fileService.createNoteCalls.count, 1)
        XCTAssertEqual(fileService.createNoteCalls.first?.0, "Daily")
        XCTAssertEqual(
            fileService.createNoteCalls.first?.1,
            fileService.createdVaultURL.appendingPathComponent("Projects/iOS", isDirectory: true)
        )
        XCTAssertEqual(model.selectedNote?.url, createdNoteURL)
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
    var createdNoteURL: URL?
    var notesToReturn: [NoteItem] = []
    var notesAfterCreate: [NoteItem]?
    var notesAfterSave: [NoteItem]?
    var createVaultCalls: [(String, URL)] = []
    var createNoteCalls: [(String, URL)] = []
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
        if let notesAfterCreate, !createNoteCalls.isEmpty {
            return notesAfterCreate
        }
        return notesToReturn
    }

    func createNote(named name: String, in directoryURL: URL) throws -> URL {
        createNoteCalls.append((name, directoryURL))
        return createdNoteURL ?? directoryURL.appendingPathComponent(name)
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
