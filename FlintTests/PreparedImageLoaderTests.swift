import XCTest
import UIKit
import ImageIO
@testable import Flint

@MainActor
final class PreparedImageLoaderTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testLargeImagesAreDownsampledAndChangedVersionsInvalidateCache() async throws {
        let url = try fixture(width: 5000, height: 1000)
        let loader = PreparedImageLoader()
        let reference = NoteImageReference(assetURL: url, vaultURL: root)
        let inline = try await loader.image(for: reference, size: .inline)
        let viewer = try await loader.image(for: reference, size: .viewer, optional: false)
        XCTAssertEqual(inline.image.cgImage?.width, 2048)
        XCTAssertEqual(viewer.image.cgImage?.width, 4096)
        XCTAssertEqual(inline.image.size.width / inline.image.size.height, 5, accuracy: 0.02)
        _ = try fixture(width: 600, height: 300, url: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 10)], ofItemAtPath: url.path)
        let changed = try await loader.image(for: reference, size: .inline)
        XCTAssertEqual(changed.image.cgImage?.width, 600)
        XCTAssertEqual(changed.image.cgImage?.height, 300)
        let cachedBytes = await loader.cachedByteCount
        XCTAssertLessThanOrEqual(cachedBytes, 32 * 1024 * 1024)
    }

    func testDuplicateRequestsDecodeOnceAndOneCallerCanCancelIndependently() async throws {
        let url = try fixture(width: 800, height: 400)
        let entered = expectation(description: "decode started")
        let finished = expectation(description: "decode worker actually finished")
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let decoder = ProviderExecutor(limit: 1, workerDidFinish: { finished.fulfill() })
        let loader = PreparedImageLoader(decoder: decoder, decode: { url, pixels in
            entered.fulfill(); gate.wait()
            return try PreparedImageLoader.downsample(url, pixels: pixels)
        })
        let reference = NoteImageReference(assetURL: url, vaultURL: root)
        let first = Task { try await loader.image(for: reference, size: .inline) }
        await fulfillment(of: [entered], timeout: 5)
        let second = Task { try await loader.image(for: reference, size: .inline) }
        await waitForWaiters(loader, count: 2)
        first.cancel()
        do { _ = try await first.value; XCTFail("Expected cancellation") } catch { }
        XCTAssertEqual(decoder.counts.active, 1)
        gate.signal()
        let image = try await second.value
        XCTAssertEqual(image.image.cgImage?.width, 800)
        await fulfillment(of: [finished], timeout: 20)
        XCTAssertEqual(decoder.counts.active, 0)
    }

    func testMemoryWarningCancelsOptionalDecodeWithoutWaitingAndPreventsLateCacheInsertion() async throws {
        let url = try fixture(width: 800, height: 400)
        let entered = expectation(description: "blocked decode")
        let finished = expectation(description: "decode released")
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let decoder = ProviderExecutor(limit: 1, workerDidFinish: { finished.fulfill() })
        let loader = PreparedImageLoader(decoder: decoder, decode: { url, pixels in
            entered.fulfill(); gate.wait()
            return try PreparedImageLoader.downsample(url, pixels: pixels)
        })
        let task = Task { try await loader.image(for: NoteImageReference(assetURL: url, vaultURL: root), size: .inline) }
        await fulfillment(of: [entered], timeout: 5)
        await loader.memoryWarning()
        do { _ = try await task.value; XCTFail("Expected cancelled optional image") } catch { }
        XCTAssertEqual(decoder.counts.active, 1)
        let cacheBytesBefore = await loader.cachedByteCount
        XCTAssertEqual(cacheBytesBefore, 0)
        gate.signal()
        await fulfillment(of: [finished], timeout: 20)
        let cacheBytesAfter = await loader.cachedByteCount
        XCTAssertEqual(cacheBytesAfter, 0)
    }

    func testUnreadableImageAndSymlinkOutsideVaultAreRejected() async throws {
        let invalid = root.appendingPathComponent("invalid.png")
        try Data("not an image".utf8).write(to: invalid)
        let loader = PreparedImageLoader()
        for url in [invalid, root.appendingPathComponent("missing.png")] {
            do { _ = try await loader.image(for: NoteImageReference(assetURL: url, vaultURL: root), size: .inline); XCTFail("Expected failure") }
            catch { }
        }
        let external = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: external) }
        _ = try fixture(width: 100, height: 50, url: external)
        let link = root.appendingPathComponent("escape.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
        do { _ = try await loader.image(for: NoteImageReference(assetURL: link, vaultURL: root), size: .inline); XCTFail("Expected escape rejection") }
        catch { }
    }

    func testCacheEvictsOldestPixelsAndOversizedValuesAreNotRetained() throws {
        let image = PreparedNoteImage(image: UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20), format: {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; return format
        }()).image { UIColor.red.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 20, height: 20)) })
        let cache = PreparedImageCache(limit: image.byteCount * 2)
        let keys = (0..<3).map { PreparedImageCache.Key(url: root.appendingPathComponent("\($0)"), modified: Date(), created: nil, size: 1, pixels: 20) }
        cache.insert(image, for: keys[0]); cache.insert(image, for: keys[1]); cache.insert(image, for: keys[2])
        XCTAssertNil(cache.value(for: keys[0])); XCTAssertNotNil(cache.value(for: keys[2]))
        XCTAssertLessThanOrEqual(cache.byteCount, image.byteCount * 2)
        let small = PreparedImageCache(limit: image.byteCount - 1)
        small.insert(image, for: keys[0]); XCTAssertEqual(small.byteCount, 0)
        cache.clear(); XCTAssertEqual(cache.byteCount, 0)
    }

    func testTextConstructionDoesNotWaitForImageAccessAndPreservesMarkdown() throws {
        let note = root.appendingPathComponent("note.md")
        let markdown = "Before\n![Caption](missing.png)\nAfter"
        let document = FlintRichTextCodec.attributedString(from: markdown, noteURL: note, vaultURL: root)
        var attachment: FlintMarkdownImageAttachment?
        document.enumerateAttribute(.attachment, in: NSRange(location: 0, length: document.length)) { value, _, _ in
            attachment = value as? FlintMarkdownImageAttachment ?? attachment
        }
        let image = try XCTUnwrap(attachment)
        XCTAssertEqual(image.loadState, .pending)
        for width in [250.0, 500, 300] { image.applyLayout(for: width) }
        XCTAssertEqual(image.loadState, .pending)
        XCTAssertEqual(image.altText, "Caption")
        XCTAssertEqual(FlintRichTextCodec.markdown(from: document), markdown)
    }

    func testCancelledAttachmentCannotPublishLatePixelsAndLayoutDoesNotReload() async throws {
        let url = try fixture(width: 800, height: 400)
        let entered = expectation(description: "attachment decode started")
        let finished = expectation(description: "attachment worker returned")
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let decoder = ProviderExecutor(limit: 1, workerDidFinish: { finished.fulfill() })
        let loader = PreparedImageLoader(decoder: decoder, decode: { url, pixels in
            entered.fulfill(); gate.wait()
            return try PreparedImageLoader.downsample(url, pixels: pixels)
        })
        let attachment = FlintMarkdownImageAttachment(markdownSource: "![Caption](image.png)", assetURL: url,
            altText: "Caption", vaultURL: root)
        var publications = 0
        attachment.load(using: loader) { publications += 1 }
        await fulfillment(of: [entered], timeout: 5)
        attachment.applyLayout(for: 500)
        attachment.cancelLoading()
        gate.signal()
        await fulfillment(of: [finished], timeout: 20)
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(attachment.loadState, .pending)
        XCTAssertEqual(attachment.markdownSource, "![Caption](image.png)")
    }

    func testSuccessfulAttachmentRelayoutUsesPreparedPixelsAfterSourceIsRemoved() async throws {
        let url = try fixture(width: 300, height: 150)
        let loaded = expectation(description: "attachment loaded")
        let attachment = FlintMarkdownImageAttachment(markdownSource: "![Caption](image.png)", assetURL: url,
            altText: "Caption", vaultURL: root)
        attachment.load { loaded.fulfill() }
        await fulfillment(of: [loaded], timeout: 5)
        XCTAssertEqual(attachment.loadState, .loaded)
        try FileManager.default.removeItem(at: url)
        for width in [250.0, 350, 450] { attachment.applyLayout(for: width) }
        XCTAssertEqual(attachment.loadState, .loaded)
        XCTAssertNotNil(attachment.image)
        let measuredBounds = attachment.bounds
        attachment.releaseOffscreenPixels()
        XCTAssertEqual(attachment.loadState, .pending)
        XCTAssertEqual(attachment.bounds, measuredBounds)
    }

    func testPhotoStagingSurvivesOriginalRemovalAndImportWorkerCancellation() async throws {
        let url = try fixture(width: 200, height: 100)
        var staged: StagedPhotoFile? = try await Task.detached { try StagedPhotoFile.copyCallbackFile(url) }.value
        let stagedURL = try XCTUnwrap(staged?.url)
        try FileManager.default.removeItem(at: url)
        let entered = expectation(description: "import worker blocked")
        let finished = expectation(description: "import worker finished")
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let executor = ProviderExecutor(workerDidFinish: { finished.fulfill() })
        var request = ProviderRequest(vaultURL: root)
        request.sourceLifetime = staged
        let task = Task { [request] in
            try await executor.execute(request, step: .imageImport, mutation: true) { _ in
                entered.fulfill(); gate.wait()
                return try Data(contentsOf: stagedURL).count
            }
        }
        request.sourceLifetime = nil; staged = nil
        await fulfillment(of: [entered], timeout: 5)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedURL.path))
        gate.signal()
        await fulfillment(of: [finished], timeout: 20)
        XCTAssertEqual(executor.counts.active, 0)
    }

    func testPhotoSelectionDeadlineIgnoresBackgroundTimeAndRejectsLateCallbacks() async throws {
        let time = ImageTestTime()
        let clock = ForegroundClock(clock: { time.now })
        let attempt = ProviderAttempt(clock: clock)
        var outcomes: [Result<StagedPhotoFile, Error>] = []
        let request = PhotoSelectionRequest(attempt: attempt, automaticSampling: false) { outcomes.append($0) }
        time.now = 20; request.sample()
        XCTAssertTrue(outcomes.isEmpty)
        clock.setActive(false); time.now = 200; request.sample()
        XCTAssertTrue(outcomes.isEmpty)
        clock.setActive(true); time.now = 210; request.sample()
        XCTAssertEqual(outcomes.count, 1)
        if case let .failure(error) = outcomes.first { XCTAssertEqual((error as? ProviderFailure)?.reason, .timedOut) }
        else { XCTFail("Expected foreground deadline") }
        let url = try fixture(width: 200, height: 100)
        await Task.detached { request.receive(url) }.value
        XCTAssertEqual(outcomes.count, 1)
    }

    func testViewerCancellationReturnsBeforeBlockedReadAndKeepsWorkerAccessUntilReturn() async throws {
        let url = try fixture(width: 300, height: 150)
        let entered = expectation(description: "viewer read is blocked")
        let finished = expectation(description: "viewer worker released access")
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let coordinator = ImageReadGate(entered: entered, gate: gate)
        let executor = ProviderExecutor(coordinatorFactory: { coordinator }, workerDidFinish: { finished.fulfill() })
        let loader = PreparedImageLoader(executor: executor)
        let reference = NoteImageReference(assetURL: url, vaultURL: root)
        let viewer = Task { try await loader.image(for: reference, size: .viewer, optional: false) }
        await fulfillment(of: [entered], timeout: 5)
        viewer.cancel()
        do { _ = try await viewer.value; XCTFail("Dismissal must cancel the viewer request") } catch { }
        XCTAssertEqual(executor.counts.active, 1)
        let waiters = await loader.waiterCount
        XCTAssertEqual(waiters, 0)
        gate.signal()
        await fulfillment(of: [finished], timeout: 20)
        XCTAssertEqual(executor.counts.active, 0)
        let bytes = await loader.cachedByteCount
        XCTAssertEqual(bytes, 0)
    }

    private func waitForWaiters(_ loader: PreparedImageLoader, count: Int) async {
        let end = Date().addingTimeInterval(5)
        while await loader.waiterCount < count, Date() < end { await Task.yield() }
        let actual = await loader.waiterCount
        XCTAssertEqual(actual, count)
    }
    @discardableResult private func fixture(width: Int, height: Int, url: URL? = nil) throws -> URL {
        let url = url ?? root.appendingPathComponent(UUID().uuidString + ".png")
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(UIColor.orange.cgColor); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}

private final class ImageTestTime {
    var now = 0.0
}

private final class ImageReadGate: ProviderCoordinating {
    let entered: XCTestExpectation
    let gate: DispatchSemaphore
    init(entered: XCTestExpectation, gate: DispatchSemaphore) { self.entered = entered; self.gate = gate }
    func read(at url: URL, accessor: (URL) -> Void) throws { entered.fulfill(); gate.wait(); accessor(url) }
    func write(at url: URL, accessor: (URL) -> Void) throws { accessor(url) }
    func cancel() {}
}
