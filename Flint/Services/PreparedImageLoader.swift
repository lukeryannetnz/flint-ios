import Foundation
import ImageIO
import UIKit

/// This reference is lexical only. Workers validate symlinks and file versions before reading.
struct NoteImageReference: Hashable {
    let assetURL: URL
    let vaultURL: URL
}

struct PreparedNoteImage {
    let image: UIImage
    var byteCount: Int { image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0 }
}

private final class TemporaryImageFile {
    let url: URL
    init() { url = FileManager.default.temporaryDirectory.appendingPathComponent("flint-image-" + UUID().uuidString) }
    deinit { try? FileManager.default.removeItem(at: url) }
}

/// Accessed by file workers as well as the loader. The budget covers reusable pixels, not active views.
final class PreparedImageCache {
    struct Key: Hashable {
        let url: URL
        let modified: Date?
        let created: Date?
        let size: Int?
        let pixels: Int
    }
    private let lock = NSLock()
    private let limit: Int
    private var values: [Key: PreparedNoteImage] = [:]
    private var order: [Key] = []
    private var cost = 0
    init(limit: Int = 32 * 1024 * 1024) { self.limit = limit }
    func value(for key: Key) -> PreparedNoteImage? {
        lock.lock(); defer { lock.unlock() }
        guard let value = values[key] else { return nil }
        order.removeAll { $0 == key }; order.append(key)
        return value
    }
    func insert(_ value: PreparedNoteImage, for key: Key) {
        lock.lock(); defer { lock.unlock() }
        if let old = values.removeValue(forKey: key) { cost -= old.byteCount }
        order.removeAll { $0 == key }
        guard value.byteCount <= limit else { return }
        while cost + value.byteCount > limit, let oldest = order.first {
            order.removeFirst()
            if let old = values.removeValue(forKey: oldest) { cost -= old.byteCount }
        }
        values[key] = value; order.append(key); cost += value.byteCount
    }
    func clear() { lock.lock(); values = [:]; order = []; cost = 0; lock.unlock() }
    var byteCount: Int { lock.lock(); defer { lock.unlock() }; return cost }
}

/// Owns shared loads, per-caller cancellation, and cache publication. UIKit only receives prepared pixels.
actor PreparedImageLoader {
    static let shared = PreparedImageLoader()
    enum Size: Int { case inline = 2048, viewer = 4096 }
    private struct Key: Hashable { let reference: NoteImageReference; let pixels: Int }
    private struct Flight {
        let id: UUID
        let attempt: ProviderAttempt
        var waiters: [UUID: CheckedContinuation<PreparedNoteImage, Error>]
        var optional: Bool
    }
    private enum Source {
        case cached(PreparedNoteImage)
        case file(TemporaryImageFile, PreparedImageCache.Key)
    }
    private let executor: ProviderExecutor
    private let decoder: ProviderExecutor
    private let decode: (URL, Int) throws -> PreparedNoteImage
    private let cache: PreparedImageCache
    var cachedByteCount: Int { cache.byteCount }
    private var cacheGeneration = 0
    private var flights: [Key: Flight] = [:]
    var waiterCount: Int { flights.values.reduce(0) { $0 + $1.waiters.count } }
    private var warningObserver: NSObjectProtocol?

    init(executor: ProviderExecutor = .shared, decoder: ProviderExecutor = .decodeLane,
         cache: PreparedImageCache = PreparedImageCache(),
         decode: @escaping (URL, Int) throws -> PreparedNoteImage = PreparedImageLoader.downsample) {
        self.executor = executor; self.decoder = decoder; self.cache = cache; self.decode = decode
    }
    deinit { if let warningObserver { NotificationCenter.default.removeObserver(warningObserver) } }

    func image(for reference: NoteImageReference, size: Size, optional: Bool = true) async throws -> PreparedNoteImage {
        if warningObserver == nil {
            warningObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil, queue: nil) { [weak self] _ in Task { await self?.memoryWarning() } }
        }
        let key = Key(reference: reference, pixels: size.rawValue), waiter = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if var flight = flights[key] {
                    flight.waiters[waiter] = continuation
                    flight.optional = flight.optional && optional
                    flights[key] = flight
                } else {
                    let id = UUID(), attempt = ProviderAttempt()
                    flights[key] = Flight(id: id, attempt: attempt, waiters: [waiter: continuation], optional: optional)
                    Task { await self.load(key, id: id, attempt: attempt, optional: optional) }
                }
            }
        } onCancel: { Task { await self.cancel(waiter, for: key) } }
    }

    private func cancel(_ waiter: UUID, for key: Key) {
        guard var flight = flights[key], let continuation = flight.waiters.removeValue(forKey: waiter) else { return }
        if flight.waiters.isEmpty { flights.removeValue(forKey: key); flight.attempt.cancel() }
        else { flights[key] = flight }
        continuation.resume(throwing: CancellationError())
    }

    func memoryWarning() {
        cacheGeneration += 1
        cache.clear()
        let optional = flights.filter { $0.value.optional }
        for (key, flight) in optional {
            flights.removeValue(forKey: key); flight.attempt.cancel()
            flight.waiters.values.forEach { $0.resume(throwing: CancellationError()) }
        }
    }

    private func load(_ key: Key, id: UUID, attempt: ProviderAttempt, optional: Bool) async {
        let result: Result<PreparedNoteImage, Error>
        let generation = cacheGeneration
        do {
            let reference = key.reference, cache = cache
            let request = ProviderRequest(vaultURL: reference.vaultURL, attempt: attempt,
                                          priority: optional ? .optional : .explicit)
            let source: Source = try await executor.execute(request, step: .imageRead) { context in
                let location = try context.coordinated(.coordinationRead, at: reference.vaultURL) { currentRoot -> (url: URL, root: URL) in
                    let root = currentRoot.resolvingSymlinksInPath().standardizedFileURL
                    let candidate = try VaultFileService.resolvedItem(reference.assetURL, in: reference.vaultURL,
                        currentRoot: currentRoot).resolvingSymlinksInPath().standardizedFileURL
                    guard candidate.path.hasPrefix(root.path + "/") else { throw VaultError.inaccessibleVault }
                    return (candidate, root)
                }
                return try context.coordinated(.coordinationRead, at: location.url) { coordinatedURL in
                    var url = coordinatedURL.resolvingSymlinksInPath().standardizedFileURL
                    guard url.path.hasPrefix(location.root.path + "/") else { throw VaultError.inaccessibleVault }
                    url.removeAllCachedResourceValues()
                    let details = try url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey, .fileSizeKey, .isRegularFileKey])
                    guard details.isRegularFile == true else { throw VaultError.inaccessibleVault }
                    let version = PreparedImageCache.Key(url: url, modified: details.contentModificationDate,
                        created: details.creationDate, size: details.fileSize, pixels: key.pixels)
                    // If no version can be observed, do not reuse an older image.
                    if details.contentModificationDate != nil, let image = cache.value(for: version) { return .cached(image) }
                    let temporary = TemporaryImageFile()
                    try FileManager.default.copyItem(at: url, to: temporary.url)
                    try context.checkCancellation()
                    return .file(temporary, version)
                }
            }
            switch source {
            case .cached(let image): result = .success(image)
            case let .file(file, version):
                let decode = decode
                let image = try await decoder.execute(ProviderRequest(vaultURL: nil, attempt: attempt,
                    priority: optional ? .optional : .explicit), step: .imagePrepare) { context in
                    try context.checkCancellation()
                    return try autoreleasepool { try decode(file.url, key.pixels) }
                }
                guard flights[key]?.id == id, !attempt.cancelled, !attempt.expired else { return }
                if version.modified != nil, generation == cacheGeneration { cache.insert(image, for: version) }
                result = .success(image)
            }
        } catch { result = .failure(error) }
        guard let flight = flights[key], flight.id == id else { return }
        flights.removeValue(forKey: key)
        flight.waiters.values.forEach { $0.resume(with: result) }
    }

    nonisolated static func downsample(_ url: URL, pixels: Int) throws -> PreparedNoteImage {
        precondition(!Thread.isMainThread)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels
              ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        return PreparedNoteImage(image: UIImage(cgImage: image))
    }
}

/// Owns a picker callback's temporary copy until the actual import worker releases it.
final class StagedPhotoFile {
    let url: URL
    let preferredFilename: String
    let attempt: ProviderAttempt
    private static let admission = DispatchSemaphore(value: 2)
    private init(url: URL, preferredFilename: String, attempt: ProviderAttempt) {
        self.url = url; self.preferredFilename = preferredFilename; self.attempt = attempt
    }
    static func copyCallbackFile(_ source: URL, attempt: ProviderAttempt = ProviderAttempt()) throws -> StagedPhotoFile {
        precondition(!Thread.isMainThread)
        guard admission.wait(timeout: .now()) == .success else { throw CocoaError(.fileReadUnknown) }
        defer { admission.signal() }
        let lease = SecurityScopeLease(url: source)
        return try withExtendedLifetime(lease) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("flint-photo-" + UUID().uuidString)
                .appendingPathExtension(source.pathExtension)
            do {
                try DebugLog.shared.measure(.imageImport, file: source) { try FileManager.default.copyItem(at: source, to: url) }
                return StagedPhotoFile(url: url, preferredFilename: source.deletingPathExtension().lastPathComponent, attempt: attempt)
            } catch { try? FileManager.default.removeItem(at: url); throw error }
        }
    }
    deinit {
        let url = url
        DispatchQueue.global(qos: .utility).async { try? FileManager.default.removeItem(at: url) }
    }
}

/// Bounds the wait for Photos and its callback copy without extending the callback URL's lifetime.
final class PhotoSelectionRequest {
    private let lock = NSLock()
    private let attempt: ProviderAttempt
    private let completion: (Result<StagedPhotoFile, Error>) -> Void
    private let timer: DispatchSourceTimer
    private var terminal = false
    private var progress: Progress?
    init(attempt: ProviderAttempt = ProviderAttempt(), automaticSampling: Bool = true,
         completion: @escaping (Result<StagedPhotoFile, Error>) -> Void) {
        self.attempt = attempt; self.completion = completion
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "flint.photo-deadline", qos: .utility))
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
        if automaticSampling { timer.setEventHandler { [weak self] in self?.sample() } }
        timer.resume()
    }
    deinit { timer.cancel() }
    func setProgress(_ progress: Progress) {
        lock.lock(); self.progress = progress; let finished = terminal; lock.unlock()
        if finished { DispatchQueue.global(qos: .utility).async { progress.cancel() } }
    }
    func receive(_ url: URL?) {
        sample()
        lock.lock(); let finished = terminal; lock.unlock()
        guard !finished else { return }
        let result = Result { () throws -> StagedPhotoFile in
            guard let url else { throw CocoaError(.fileReadUnknown) }
            return try StagedPhotoFile.copyCallbackFile(url, attempt: attempt)
        }
        finish(result)
    }
    func sample() {
        if attempt.expired { finish(.failure(ProviderFailure(reason: .timedOut, operationID: attempt.id, uncertainMutation: false))) }
    }
    func cancel() { finish(.failure(CancellationError())) }
    private func finish(_ result: Result<StagedPhotoFile, Error>) {
        lock.lock()
        guard !terminal else { lock.unlock(); return }
        terminal = true; let progress = progress; self.progress = nil
        lock.unlock(); timer.cancel()
        if case .failure = result { DispatchQueue.global(qos: .utility).async { progress?.cancel() } }
        let delivered: Result<StagedPhotoFile, Error> = attempt.expired
            ? .failure(ProviderFailure(reason: .timedOut, operationID: attempt.id, uncertainMutation: false)) : result
        completion(delivered)
    }
}
