import XCTest

final class NoteImageWorkflowTests: XCTestCase {
    private let app = XCUIApplication()
    private var runID = UUID().uuidString

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchEnvironment = ["FLINT_IMAGE_TEST_RUN": runID, "FLINT_IMAGE_TEST_NOTE": "Existing.md"]
    }

    func testExistingImageLoadsWithVisibleBoundsAndCaption() {
        app.launch()
        let image = app.images["note.image.loaded"].firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(image.frame.width, 0)
        XCTAssertGreaterThan(image.frame.height, 0)
        XCTAssertTrue((app.textViews["note.editor"].value as? String)?.contains("Fixture caption") == true)
    }

    override func tearDownWithError() throws {
        app.terminate()
        app.launchEnvironment["FLINT_IMAGE_TEST_CLEANUP"] = "1"
        app.launch()
        app.terminate()
    }

    private func snapshot() throws -> [String: Any] {
        let element = app.staticTexts["test.persistence"]
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(element.label.utf8)) as? [String: Any])
    }

    private func waitForSavedImage() {
        let predicate = NSPredicate { [weak self] _, _ in
            guard let value = try? self?.snapshot() else { return false }
            return value["unsaved"] as? Bool == false && (value["saved"] as? String)?.contains("![") == true
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 10), .completed)
    }

    func testViewerDismissalPreservesEditorAndSavedNote() throws {
        app.launch()
        let image = app.images["note.image.loaded"].firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        let before = try snapshot()
        image.tap()
        let close = app.buttons["image.viewer.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        let after = try snapshot()
        XCTAssertEqual(after["saved"] as? String, before["saved"] as? String)
        XCTAssertEqual(after["editor"] as? String, before["editor"] as? String)
        XCTAssertEqual(after["unsaved"] as? Bool, false)
    }

    func testMissingImageLeavesSurroundingTextReadable() {
        app.launchEnvironment["FLINT_IMAGE_TEST_NOTE"] = "Missing.md"
        app.launch()
        let missing = app.images["note.image.missing"].firstMatch
        XCTAssertTrue(missing.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(missing.frame.width, 0)
        let content = app.textViews["note.editor"].value as? String ?? ""
        XCTAssertTrue(content.hasPrefix("Before"))
        XCTAssertTrue(content.hasSuffix("After"))
        XCTAssertTrue(content.contains("Missing caption"))
        XCTAssertFalse(app.images["note.image.loaded"].exists)
    }

    func testFilesInsertionSurvivesSourceRemovalAndRelaunch() throws {
        try verifyInsertion(source: "Files")
    }

    func testPhotoLibraryInsertionSurvivesSourceRemovalAndRelaunch() throws {
        try verifyInsertion(source: "Photo Library")
    }

    func testCameraInsertionPersistsJPEGAndSurvivesRelaunch() throws {
        try verifyInsertion(source: "Take Photo")
    }

    func testSaveFailureRetainsImageAndRetryPersistsIt() throws {
        app.launchEnvironment["FLINT_IMAGE_TEST_NOTE"] = "Editable.md"
        app.launchEnvironment["FLINT_IMAGE_TEST_FAIL_SAVE"] = "1"
        app.launch()
        let editor = app.textViews["note.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        app.buttons["note.insert-image"].tap()
        app.buttons["Files"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10))
        app.alerts.buttons["OK"].tap()
        let failed = try snapshot()
        XCTAssertEqual(failed["saved"] as? String, "Before\nAfter")
        XCTAssertEqual(failed["unsaved"] as? Bool, true)
        let draft = try XCTUnwrap(failed["editor"] as? String)
        XCTAssertTrue(draft.contains("!["))
        let assets = try XCTUnwrap(failed["editorAssets"] as? [[String: Any]])
        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(assets.first?["managed"] as? Bool, true)
        XCTAssertEqual(assets.first?["readable"] as? Bool, true)
        app.buttons["test.retry-save"].tap()
        waitForSavedImage()
        XCTAssertEqual((try snapshot())["saved"] as? String, draft)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.images["note.image.loaded"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual((try snapshot())["saved"] as? String, draft)
    }

    private func verifyInsertion(source: String) throws {
        app.launchEnvironment["FLINT_IMAGE_TEST_NOTE"] = "Editable.md"
        app.launch()
        let content = app.textViews["note.editor"]
        XCTAssertTrue(content.waitForExistence(timeout: 10))
        content.tap()
        let insert = app.buttons["note.insert-image"]
        XCTAssertTrue(insert.waitForExistence(timeout: 5))
        insert.tap()
        app.buttons[source].tap()
        XCTAssertTrue(app.images["note.image.loaded"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["note.finish-editing"].tap()
        waitForSavedImage()
        let saved = try snapshot()
        let markdown = try XCTUnwrap(saved["saved"] as? String)
        XCTAssertTrue(markdown.hasPrefix("Before\n"))
        XCTAssertTrue(markdown.hasSuffix("\nAfter"))
        XCTAssertTrue(markdown.contains("!["))
        XCTAssertFalse(markdown.contains("file://"))
        let assets = try XCTUnwrap(saved["assets"] as? [[String: Any]])
        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(assets.first?["managed"] as? Bool, true)
        XCTAssertEqual(assets.first?["readable"] as? Bool, true)
        if source == "Take Photo" { XCTAssertTrue((assets.first?["reference"] as? String)?.hasSuffix(".jpg") == true) }
        app.buttons["test.remove-source"].tap()
        XCTAssertFalse((try snapshot())["sourceExists"] as? Bool ?? true)
        app.terminate()
        app.launch()
        let loaded = app.images["note.image.loaded"].firstMatch
        XCTAssertTrue(loaded.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(loaded.frame.width, 0)
        XCTAssertGreaterThan(loaded.frame.height, 0)
        XCTAssertEqual((try snapshot())["saved"] as? String, markdown)
    }
}
