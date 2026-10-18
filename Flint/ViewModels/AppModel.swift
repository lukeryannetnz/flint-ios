import Foundation
import UIKit

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable { case loading, onboarding, restorationRecovery, providerRecovery, ready }
    private enum RecoveryTarget {
        case restoration
        case open(URL, Bool)
        case create(String, URL, ProviderAttempt?, UUID?)
    }
    private enum PendingImageImport {
        case attempt(ProviderAttempt, UUID)
        case completed(InsertedNoteImage)
    }
    private struct NoteCreationKey: Hashable {
        let name: String
        let folder: [String]
    }
    private struct UncertainSave {
        let attempt: ProviderAttempt
        let operation: UUID
        let document: UUID
        let revision: Int
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var activeVault: Vault?
    @Published private(set) var notes: [NoteItem] = []
    @Published private(set) var discoveryState: NoteDiscoveryState = .idle
    @Published private(set) var previewRevision = 0
    @Published private(set) var requestedNoteURL: URL?
    @Published private(set) var failedNoteURL: URL?
    @Published private(set) var selectedNote: NoteItem?
    @Published var noteText = ""
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var isBusy = false
    @Published private(set) var isNoteLoading = false
    @Published private(set) var loadingStage: DebugLogStep = .launch
    @Published private(set) var isSlow = false
    @Published private(set) var recoveryMessage = "The previous vault restoration was interrupted or could not be safely started."
    @Published var alertMessage: String?
    @Published var diagnosticShare: DiagnosticShareItem?
    @Published private(set) var isExportingDiagnostics = false
    @Published private(set) var hasPendingImageImport = false

    private let bookmarkStore: VaultBookmarkStoring
    private let fileService: VaultFileServing
    private let restorationSafety: RestorationSafetyChecking
    private let executor: ProviderExecutor
    private let attemptFactory: () -> ProviderAttempt
    private let shareStore: DiagnosticShareStore
    private var didBootstrap = false
    private var vaultGeneration = UUID()
    private var documentGeneration = UUID()
    private var metadataGeneration = UUID()
    private var pendingRefreshReconciliation: (document: UUID, metadata: UUID)?
    private var initialContentPending = false
    private var navigationGeneration = UUID()
    private var activeLease: SecurityScopeLease?
    private var loadingAttempt: ProviderAttempt?
    private var noteAttempt: ProviderAttempt?
    private var discoveryTask: Task<Void, Never>?
    private var discoveryAttempt: ProviderAttempt?
    private let previewCache = NotePreviewCache()
    private var previewEpoch = UUID()
    private var previewVersions: [URL: UUID] = [:]
    private var previewRequests: [URL: (id: UUID, attempt: ProviderAttempt)] = [:]
    private var progressTask: Task<Void, Never>?
    private var autosaveTask: Task<Void, Never>?
    private var saveTask: (id: UUID, task: Task<Void, Never>)?
    private var uncertainSave: UncertainSave?
    private var pendingImageImports: [URL: [PendingImageImport]] = [:]
    private var inFlightImageImports: [URL: UUID] = [:]
    private var completedNoteCreations: [NoteCreationKey: URL] = [:]
    private var uncertainNoteCreation: (name: String, folder: [String], attempt: ProviderAttempt, operation: UUID)?
    private var revision = 0
    private var recoveryTarget: RecoveryTarget = .restoration

    init(bookmarkStore: VaultBookmarkStoring, fileService: VaultFileServing,
         restorationSafety: RestorationSafetyChecking = RestorationSafety.shared,
         executor: ProviderExecutor = .shared, attemptFactory: @escaping () -> ProviderAttempt = { ProviderAttempt() },
         shareStore: DiagnosticShareStore = .shared) {
        self.bookmarkStore = bookmarkStore; self.fileService = fileService; self.restorationSafety = restorationSafety
        self.executor = executor; self.attemptFactory = attemptFactory; self.shareStore = shareStore
    }

    func bootstrap() async {
        await DebugLog.shared.measureAsync(.launch) {
            guard !didBootstrap else { return }; didBootstrap = true
            #if DEBUG
            if ImageWorkflowTestSupport.active {
                do {
                    let request = ProviderRequest(vaultURL: nil, attempt: attemptFactory())
                    let root = try await executor.execute(request, step: .launch) { _ in try ImageWorkflowTestSupport.prepare() }
                    await openVault(at: root, persistSelection: false)
                    let name = ProcessInfo.processInfo.environment["FLINT_IMAGE_TEST_NOTE"] ?? "Existing.md"
                    if let note = notes.first(where: { $0.url.lastPathComponent == name }) { await openNote(note) }
                } catch { alertMessage = error.localizedDescription; phase = .onboarding }
                return
            }
            #endif
            guard let bookmark = bookmarkStore.loadBookmarkData() else { phase = .onboarding; return }
            await restoreBookmark(bookmark, explicit: false)
        }
    }

    func retryRestoration() async {
        guard phase == .restorationRecovery || phase == .providerRecovery else { return }
        guard loadingAttempt == nil else { return }
        switch recoveryTarget {
        case .restoration:
            guard let bookmark = bookmarkStore.loadBookmarkData() else { phase = .onboarding; return }
            await restoreBookmark(bookmark, explicit: true)
        case let .open(url, persist): await openVault(at: url, persistSelection: persist)
        case let .create(name, parent, oldAttempt, operation):
            if let oldAttempt, let operation {
                switch oldAttempt.mutationOutcome(operation) {
                case .running, nil:
                    recoveryMessage = "Previous creation is still stopping. Its result is not yet known."; return
                case let .completed(.success(url)):
                    guard let url = url.url else { return }
                    await openVault(at: url); return
                case .completed(.failure), .notStarted: break
                }
            }
            await createVault(named: name, in: parent)
        }
    }

    func chooseAnotherVault() async {
        guard phase == .restorationRecovery || phase == .providerRecovery || phase == .loading else { return }
        cancelLoading()
        let generation = vaultGeneration
        await restorationSafety.finish(completed: false)
        guard vaultGeneration == generation else { return }
        phase = .onboarding
    }

    func cancelLoading() {
        guard let attempt = loadingAttempt else { return }
        if case let .create(name, parent, _, _) = recoveryTarget, let operation = attempt.mutationIdentity {
            recoveryTarget = .create(name, parent, attempt, operation)
        }
        attempt.cancel(); vaultGeneration = UUID(); navigationGeneration = UUID()
        stopProgress(); loadingAttempt = nil; isBusy = false; activeLease = nil
        phase = .providerRecovery; recoveryMessage = "Loading was cancelled. Previous provider work may still be stopping."
        if case .restoration = recoveryTarget { Task { await restorationSafety.finish(completed: false) } }
    }

    func cancelNoteLoading() {
        noteAttempt?.cancel(); noteAttempt = nil; documentGeneration = UUID()
        isNoteLoading = false; isBusy = false; requestedNoteURL = selectedNote?.url; failedNoteURL = nil
    }

    private func restoreBookmark(_ bookmark: Data, explicit: Bool) async {
        let attempt = attemptFactory(); let generation = beginLoading(attempt, target: .restoration)
        let action = DebugLog.shared.begin(.restoration)
        let safe = await restorationSafety.begin(launchID: DebugLog.shared.launchID, explicit: explicit)
        guard current(generation, attempt) else { action.finish(.cancellation); return }
        guard safe else {
            action.finish(.abandonment); stopLoading(generation)
            phase = .restorationRecovery
            recoveryMessage = "The previous vault restoration was interrupted or could not be safely started. Its saved selection remains available."
            return
        }
        var didResolveBookmark = false
        do {
            let request = ProviderRequest(vaultURL: nil, attempt: attempt)
            let url = try await bookmarkStore.resolveBookmarkData(bookmark, request: request)
            guard current(generation, attempt) else { action.finish(.cancellation); return }
            didResolveBookmark = true
            try await loadVault(url, persist: true, attempt: attempt, generation: generation, onUsable: {
                action.finish(.success)
                await self.restorationSafety.finish(completed: true)
            })
        } catch {
            guard vaultGeneration == generation else { return }
            action.finish(.failure, error: error)
            let e = error as NSError
            if !didResolveBookmark && e.domain == NSCocoaErrorDomain && e.code == NSFileReadCorruptFileError {
                bookmarkStore.clearBookmarkData(); stopLoading(generation); phase = .onboarding
                alertMessage = "Your previous vault could not be reopened. Please select it again."
            } else { recover(error, generation: generation) }
            await restorationSafety.finish(completed: false)
        }
    }

    func openVault(at url: URL, persistSelection: Bool = true) async {
        guard await prepareNavigation() else { return }
        let attempt = attemptFactory(); let generation = beginLoading(attempt, target: .open(url, persistSelection))
        do { try await loadVault(url, persist: persistSelection, attempt: attempt, generation: generation) }
        catch { recover(error, generation: generation) }
    }

    private func loadVault(_ url: URL, persist: Bool, attempt: ProviderAttempt, generation: UUID,
                           onUsable: (() async -> Void)? = nil) async throws {
        let request = ProviderRequest(vaultURL: url, attempt: attempt)
        let lease = try await executor.execute(request, step: .securityScope) { $0.primaryLease }
        guard current(generation, attempt) else { return }
        activeLease = lease
        let bookmark = persist ? try await bookmarkStore.makeBookmark(for: url, request: request) : nil
        guard current(generation, attempt) else { return }
        discoveryState = .loading
        var batch = try await fileService.discoverNotes(in: url, cursor: nil, request: request)
        guard current(generation, attempt) else { return }
        // Empty intermediate batches do not establish an empty vault.
        while batch.notes.isEmpty, let cursor = batch.cursor {
            batch = try await fileService.discoverNotes(in: url, cursor: cursor, request: request)
            guard current(generation, attempt) else { return }
        }
        if let bookmark { bookmarkStore.saveBookmarkData(bookmark) }
        activeVault = Vault(name: url.lastPathComponent, url: url); notes = batch.notes.sorted(by: NoteItem.mostRecentlyModified)
        selectedNote = nil; requestedNoteURL = nil; failedNoteURL = nil; noteText = ""; hasUnsavedChanges = false; revision = 0
        documentGeneration = UUID(); uncertainSave = nil; uncertainNoteCreation = nil; completedNoteCreations = [:]
        refreshImageImportRecovery()
        initialContentPending = !notes.isEmpty
        stopLoading(generation); phase = .ready
        discoveryState = batch.cursor != nil ? .loading : batch.incomplete ? .incomplete : .complete
        metadataGeneration = UUID(); let metadata = metadataGeneration
        let initiallySeen = Set(notes.map(\.url))
        // Publish the browser, but admit initial content before optional continuation can take its lane.
        if let first = notes.first { await openNote(first, initialAttempt: attempt, onStarted: onUsable) }
        else { await onUsable?() }
        guard vaultGeneration == generation else { return }
        initialContentPending = false
        previewEpoch = UUID(); previewRevision += 1
        guard metadataGeneration == metadata else { return }
        if let cursor = batch.cursor {
            startDiscovery(root: url, cursor: cursor, seen: initiallySeen, incomplete: batch.incomplete, generation: generation)
        }
    }

    private func mergeMetadata(_ discovered: [NoteItem]) {
        var byURL = Dictionary(uniqueKeysWithValues: notes.map { ($0.url, $0) })
        for note in discovered {
            if let old = byURL[note.url], old.lastModifiedAt != note.lastModifiedAt || old.sourceByteCount != note.sourceByteCount {
                invalidatePreview(note.url)
            }
            byURL[note.url] = note
        }
        notes = byURL.values.sorted(by: NoteItem.mostRecentlyModified)
    }

    private func acceptCompleteMetadata(_ refreshed: [NoteItem]) {
        // A full listing is authoritative; an older cursor must never prune its newer URLs.
        metadataGeneration = UUID()
        pendingRefreshReconciliation = nil
        discoveryAttempt?.cancel(); discoveryAttempt = nil
        discoveryTask?.cancel(); discoveryTask = nil
        mergeMetadata(refreshed)
        notes = refreshed.sorted(by: NoteItem.mostRecentlyModified)
        discoveryState = .complete
    }

    private func startDiscovery(root: URL, cursor: NoteDiscoveryCursor?, seen: Set<URL>, incomplete: Bool, generation: UUID,
                                reconcileSelection: Bool = false) {
        discoveryAttempt?.cancel(); discoveryTask?.cancel()
        let startingDocument = documentGeneration
        let attempt = attemptFactory(); discoveryAttempt = attempt
        discoveryState = .loading
        discoveryTask = Task { [weak self] in
            guard let self else { return }
            var cursor = cursor, seen = seen, incomplete = incomplete
            do {
                repeat {
                    let batch = try await fileService.discoverNotes(in: root, cursor: cursor,
                        request: ProviderRequest(vaultURL: root, attempt: attempt, priority: .optional))
                    guard vaultGeneration == generation, discoveryAttempt === attempt, !Task.isCancelled, !attempt.cancelled else { return }
                    mergeMetadata(batch.notes); seen.formUnion(batch.notes.map(\.url))
                    incomplete = incomplete || batch.incomplete; cursor = batch.cursor
                    // Each immutable batch is one coalesced publication and one separately admitted worker job.
                    await Task.yield()
                } while cursor != nil
                guard vaultGeneration == generation, discoveryAttempt === attempt else { return }
                if !incomplete { notes.removeAll { !seen.contains($0.url) } }
                discoveryState = incomplete ? .incomplete : .complete
                if !incomplete, reconcileSelection {
                    discoveryAttempt = nil; discoveryTask = nil
                    await reconcileRefreshedSelection(document: startingDocument)
                }
            } catch {
                guard vaultGeneration == generation, discoveryAttempt === attempt else { return }
                discoveryState = .incomplete
                DebugLog.shared.begin(.enumeration).finish(.failure, error: error)
            }
            if discoveryAttempt === attempt { discoveryAttempt = nil; discoveryTask = nil }
        }
    }

    private func reconcileRefreshedSelection(document: UUID) async {
        guard documentGeneration == document else { return }
        if isNoteLoading {
            pendingRefreshReconciliation = (document, metadataGeneration)
            return
        }
        if let selectedNote, let updated = notes.first(where: { $0.url == selectedNote.url }) {
            self.selectedNote = updated
            return
        }
        guard !hasUnsavedChanges else {
            alertMessage = VaultError.noteMissing.localizedDescription
            return
        }
        // Only a clean document can be discarded; all later work loses the old destination generation.
        documentGeneration = UUID(); navigationGeneration = UUID()
        autosaveTask?.cancel(); autosaveTask = nil
        selectedNote = nil; requestedNoteURL = nil; failedNoteURL = nil; alertMessage = nil
        noteText = ""; revision = 0; uncertainSave = nil; isBusy = false
        refreshImageImportRecovery()
        if let first = notes.first { await openNote(first) }
    }

    func retryDiscovery() {
        guard let root = activeVault?.url else { return }
        metadataGeneration = UUID()
        pendingRefreshReconciliation = nil
        clearPreviews()
        startDiscovery(root: root, cursor: nil, seen: [], incomplete: false, generation: vaultGeneration, reconcileSelection: true)
    }

    func previewDemand(for note: NoteItem) -> NotePreviewDemand {
        NotePreviewDemand(note: note, epoch: previewEpoch, version: previewVersions[note.url])
    }

    func preview(for note: NoteItem) -> NotePreview {
        if previewRequests[note.url] != nil { return .pending }
        return previewCache.value(for: note) ?? .omitted
    }

    func loadPreview(for note: NoteItem) async {
        guard !initialContentPending, let root = activeVault?.url, notes.contains(note) else { return }
        if let existing = previewRequests[note.url] {
            guard existing.attempt.cancelled else { return }
            previewRequests.removeValue(forKey: note.url)
        }
        if let cached = previewCache.value(for: note), cached != .unavailable { return }
        let generation = vaultGeneration, id = UUID(), attempt = attemptFactory()
        previewRequests[note.url] = (id, attempt); previewRevision += 1
        let result: NotePreview
        do {
            result = try await withTaskCancellationHandler {
                try await fileService.readPreview(for: note, request: ProviderRequest(vaultURL: root, attempt: attempt, priority: .optional))
            } onCancel: { attempt.cancel() }
        } catch {
            DebugLog.shared.begin(.preview).finish(.failure, error: error)
            result = .unavailable
        }
        guard vaultGeneration == generation, previewRequests[note.url]?.id == id else { return }
        previewRequests.removeValue(forKey: note.url)
        if !Task.isCancelled, !attempt.cancelled, notes.contains(note) { previewCache.insert(result, for: note) }
        previewRevision += 1
    }

    private func invalidatePreview(_ url: URL) {
        previewRequests.removeValue(forKey: url)?.attempt.cancel()
        previewCache.remove(url); previewVersions[url] = UUID(); previewRevision += 1
    }
    private func clearPreviews() {
        previewRequests.values.forEach { $0.attempt.cancel() }; previewRequests = [:]
        previewCache.removeAll(); previewVersions = [:]; previewEpoch = UUID(); previewRevision += 1
    }

    func createVault(named name: String, in parentURL: URL) async {
        guard await prepareNavigation() else { return }
        let attempt = attemptFactory(); let generation = beginLoading(attempt, target: .create(name, parentURL, nil, nil))
        do {
            let request = ProviderRequest(vaultURL: parentURL, attempt: attempt)
            let url = try await fileService.createVault(named: name, in: parentURL, request: request)
            guard current(generation, attempt) else { return }
            recoveryTarget = .open(url, true)
            try await loadVault(url, persist: true, attempt: attempt, generation: generation)
        } catch {
            guard vaultGeneration == generation else { return }
            if let error = error as? ProviderFailure, error.uncertainMutation {
                recoveryTarget = .create(name, parentURL, attempt, error.operationID)
            }
            recover(error, generation: generation)
        }
    }

    func openNote(_ note: NoteItem, initialAttempt: ProviderAttempt? = nil, onStarted: (() async -> Void)? = nil) async {
        guard let root = activeVault?.url, await prepareNavigation() else { return }
        let vault = vaultGeneration
        noteAttempt?.cancel(); let attempt = initialAttempt ?? attemptFactory(); noteAttempt = attempt
        pendingRefreshReconciliation = nil
        documentGeneration = UUID(); let document = documentGeneration
        requestedNoteURL = note.url; failedNoteURL = nil; alertMessage = nil
        isNoteLoading = true; isBusy = true
        defer {
            if documentGeneration == document {
                isNoteLoading = false; isBusy = false; noteAttempt = nil
                requestedNoteURL = selectedNote?.url
                refreshImageImportRecovery()
                if let pending = pendingRefreshReconciliation, pending.document == document {
                    pendingRefreshReconciliation = nil
                    Task { [weak self] in
                        guard let self, metadataGeneration == pending.metadata else { return }
                        await reconcileRefreshedSelection(document: pending.document)
                    }
                }
            }
        }
        await onStarted?()
        guard vaultGeneration == vault, documentGeneration == document, !attempt.cancelled else { return }
        do {
            let text = try await fileService.readNote(at: note.url, request: ProviderRequest(vaultURL: root, attempt: attempt))
            guard vaultGeneration == vault, documentGeneration == document, !attempt.cancelled else { return }
            selectedNote = note; noteText = text; revision = 0; hasUnsavedChanges = false; uncertainSave = nil
        } catch {
            guard vaultGeneration == vault, documentGeneration == document else { return }
            failedNoteURL = note.url; alertMessage = error.localizedDescription
        }
    }

    func retryNoteLoading() async {
        guard let url = failedNoteURL, let note = notes.first(where: { $0.url == url }) else { return }
        await openNote(note)
    }

    func createNote(named name: String, inFolderPath folderPathComponents: [String] = []) async {
        guard let root = activeVault?.url, await prepareNavigation() else { return }
        let vault = vaultGeneration; let attempt = attemptFactory(); let request = ProviderRequest(vaultURL: root, attempt: attempt)
        let operation = UUID(); navigationGeneration = operation
        isBusy = true; alertMessage = nil
        defer { if navigationGeneration == operation { isBusy = false } }
        do {
            let folder = folderPathComponents.reduce(root) { $0.appendingPathComponent($1, isDirectory: true) }
            let key = NoteCreationKey(name: name, folder: folderPathComponents)
            let url: URL
            if let completed = completedNoteCreations[key] { url = completed }
            else if let uncertain = uncertainNoteCreation, uncertain.name == name, uncertain.folder == folderPathComponents {
                switch uncertain.attempt.mutationOutcome(uncertain.operation) {
                case .running, nil: alertMessage = "Previous note creation is still stopping. Please wait before retrying."; return
                case let .completed(.success(existing)):
                    guard let existing = existing.url else { return }; url = existing; uncertainNoteCreation = nil
                case .completed(.failure), .notStarted:
                    uncertainNoteCreation = nil
                    url = try await fileService.createNote(named: name, in: folder, request: request)
                }
            } else { url = try await fileService.createNote(named: name, in: folder, request: request) }
            guard vaultGeneration == vault else { return }
            completedNoteCreations[key] = url
            guard navigationGeneration == operation else { return }
            let discovered = try await fileService.listMarkdownNotes(in: root, request: request)
            guard vaultGeneration == vault, navigationGeneration == operation else { return }
            acceptCompleteMetadata(discovered)
            if let note = notes.first(where: { $0.url == url }) {
                // Creation has finished; navigation owns any subsequent pending state.
                isBusy = false
                await openNote(note)
                if vaultGeneration == vault, selectedNote?.url == url { completedNoteCreations.removeValue(forKey: key) }
            }
        } catch {
            guard vaultGeneration == vault, navigationGeneration == operation else { return }
            if let failure = error as? ProviderFailure, failure.uncertainMutation {
                uncertainNoteCreation = (name, folderPathComponents, attempt, failure.operationID)
            }
            alertMessage = error.localizedDescription
        }
    }

    func updateNoteText(_ text: String) {
        guard !isNoteLoading, selectedNote != nil else { return }
        noteText = text; revision += 1; hasUnsavedChanges = true; scheduleAutosave()
    }

    func saveCurrentNoteIfNeeded() async {
        if let pending = saveTask {
            await pending.task.value
            if saveTask?.id == pending.id { saveTask = nil }
        }
        guard hasUnsavedChanges, let note = selectedNote, let root = activeVault?.url else { return }
        if let uncertain = uncertainSave {
            switch uncertain.attempt.mutationOutcome(uncertain.operation) {
            case .running, nil: alertMessage = "Previous save is still stopping. Your edits are retained."; return
            case .completed(.success):
                if documentGeneration == uncertain.document, revision == uncertain.revision { hasUnsavedChanges = false }
                uncertainSave = nil
                invalidatePreview(note.url)
                let document = documentGeneration, vault = vaultGeneration
                let request = ProviderRequest(vaultURL: root, attempt: attemptFactory())
                let confirmation = Task { [self] in
                    await refreshMetadataAfterSave(root: root, noteURL: note.url, request: request, document: document, vault: vault)
                }
                let confirmationID = UUID(); saveTask = (confirmationID, confirmation)
                await confirmation.value
                if saveTask?.id == confirmationID { saveTask = nil }
                guard documentGeneration == document, vaultGeneration == vault, selectedNote?.url == note.url else { return }
                if !hasUnsavedChanges { return }
            case .completed(.failure), .notStarted: uncertainSave = nil
            }
        }
        autosaveTask?.cancel(); autosaveTask = nil
        let text = noteText, savedRevision = revision, document = documentGeneration, vault = vaultGeneration
        let attempt = attemptFactory(); let request = ProviderRequest(vaultURL: root, attempt: attempt)
        let task = Task { [self] in
            do {
                try await fileService.saveNote(text, at: note.url, request: request)
                guard vaultGeneration == vault, documentGeneration == document, selectedNote?.url == note.url else { return }
                if revision == savedRevision { hasUnsavedChanges = false }
                invalidatePreview(note.url)
                await refreshMetadataAfterSave(root: root, noteURL: note.url, request: request, document: document, vault: vault)
            } catch {
                guard vaultGeneration == vault, documentGeneration == document else { return }
                if let failure = error as? ProviderFailure, failure.uncertainMutation {
                    uncertainSave = UncertainSave(attempt: attempt, operation: failure.operationID, document: document, revision: savedRevision)
                }
                alertMessage = error.localizedDescription
            }
        }
        let saveID = UUID(); saveTask = (saveID, task)
        await task.value
        if saveTask?.id == saveID { saveTask = nil }
        if hasUnsavedChanges && uncertainSave == nil && revision != savedRevision { scheduleAutosave() }
    }

    private func refreshMetadataAfterSave(root: URL, noteURL: URL, request: ProviderRequest, document: UUID, vault: UUID) async {
        // Optional metadata failure never turns a confirmed write into a failed-save claim.
        do {
            let refreshed = try await fileService.listMarkdownNotes(in: root, request: request)
            guard vaultGeneration == vault, documentGeneration == document, selectedNote?.url == noteURL else { return }
            acceptCompleteMetadata(refreshed)
            if let selected = notes.first(where: { $0.url == noteURL }) { selectedNote = selected }
        } catch { DebugLog.shared.begin(.metadata).finish(.failure, error: error) }
    }

    func importImage(from sourceURL: URL, preferredFilename: String? = nil) async -> InsertedNoteImage? {
        guard let note = selectedNote, let root = activeVault?.url else { return nil }
        return await performImageImport(note: note, root: root) { request in
            try await self.fileService.importImage(from: sourceURL, preferredFilename: preferredFilename,
                into: note.url, vaultURL: root, request: request)
        }
    }

    func importCameraImage(_ image: UIImage) async -> InsertedNoteImage? {
        guard let note = selectedNote, let root = activeVault?.url else { return nil }
        return await performImageImport(note: note, root: root) { request in
            try await self.fileService.importCameraImage(image, into: note.url, vaultURL: root, request: request)
        }
    }

    private func canStartImageImport(for noteURL: URL) -> Bool {
        pendingImageImports[noteURL]?.removeAll { pending in
            guard case let .attempt(attempt, operation) = pending else { return false }
            switch attempt.mutationOutcome(operation) {
            case .completed(.failure), .notStarted: return true
            default: return false
            }
        }
        if pendingImageImports[noteURL]?.isEmpty == true { pendingImageImports.removeValue(forKey: noteURL) }
        refreshImageImportRecovery()
        guard inFlightImageImports[noteURL] == nil else {
            alertMessage = "Another image import is still running for this note."
            return false
        }
        guard pendingImageImports[noteURL]?.isEmpty != false else {
            alertMessage = "A previous image import has an unresolved result. Use Recover image before selecting another source."
            return false
        }
        return true
    }

    private func performImageImport(note: NoteItem, root: URL,
        work: (ProviderRequest) async throws -> InsertedNoteImage) async -> InsertedNoteImage? {
        guard selectedNote?.url == note.url, activeVault?.url == root, canStartImageImport(for: note.url) else { return nil }
        let document = documentGeneration, vault = vaultGeneration
        let importID = UUID(); inFlightImageImports[note.url] = importID
        let request = ProviderRequest(vaultURL: root, attempt: attemptFactory())
        isBusy = true
        defer {
            if inFlightImageImports[note.url] == importID { inFlightImageImports.removeValue(forKey: note.url) }
            if documentGeneration == document { isBusy = false }
        }
        do {
            let inserted = try await work(request)
            guard documentGeneration == document, vaultGeneration == vault else {
                retainImageImport(.completed(inserted), for: note.url); return nil
            }
            return inserted
        } catch {
            if let failure = error as? ProviderFailure, failure.uncertainMutation {
                retainImageImport(.attempt(request.attempt, failure.operationID), for: note.url)
            }
            guard documentGeneration == document, vaultGeneration == vault else { return nil }
            alertMessage = error.localizedDescription; return nil
        }
    }

    private func retainImageImport(_ pending: PendingImageImport, for noteURL: URL) {
        pendingImageImports[noteURL, default: []].append(pending)
        refreshImageImportRecovery()
    }

    private func refreshImageImportRecovery() {
        hasPendingImageImport = selectedNote.map { pendingImageImports[$0.url]?.isEmpty == false } ?? false
    }

    func recoverImageImport(for noteURL: URL) -> InsertedNoteImage? {
        guard selectedNote?.url == noteURL, let pending = pendingImageImports[noteURL]?.first else { return nil }
        let result: Result<InsertedNoteImage, Error>
        switch pending {
        case let .completed(image): result = .success(image)
        case let .attempt(attempt, operation):
            switch attempt.mutationOutcome(operation) {
            case .running, nil:
                alertMessage = "The previous image import is still stopping. Try recovery again when it finishes."
                return nil
            case let .completed(.success(.image(image))): result = .success(image)
            case let .completed(.failure(error)): result = .failure(error)
            case .notStarted, .completed(.success): result = .failure(CocoaError(.fileReadUnknown))
            }
        }
        pendingImageImports[noteURL]?.removeFirst()
        if pendingImageImports[noteURL]?.isEmpty == true { pendingImageImports.removeValue(forKey: noteURL) }
        refreshImageImportRecovery()
        switch result {
        case let .success(image): alertMessage = nil; return image
        case .failure: alertMessage = "The previous import failed. Select the image again."; return nil
        }
    }

    func exportDiagnostics() async {
        guard !isExportingDiagnostics, diagnosticShare == nil else { return }
        let generation = vaultGeneration, requestingPhase = phase
        isExportingDiagnostics = true; defer { isExportingDiagnostics = false }
        do {
            let url = try await shareStore.stage()
            guard vaultGeneration == generation, phase == requestingPhase else { shareStore.cleanup(); return }
            diagnosticShare = DiagnosticShareItem(url: url)
        } catch {
            guard vaultGeneration == generation, phase == requestingPhase else { return }
            alertMessage = "Diagnostics could not be exported. Please try again."
        }
    }
    func finishDiagnosticShare() { diagnosticShare = nil; shareStore.cleanup() }
    func clearAlert() { alertMessage = nil }

    private func prepareNavigation() async -> Bool {
        let navigation = UUID(); navigationGeneration = navigation
        await saveCurrentNoteIfNeeded()
        return navigationGeneration == navigation && !hasUnsavedChanges
    }
    private func beginLoading(_ attempt: ProviderAttempt, target: RecoveryTarget) -> UUID {
        loadingAttempt?.cancel(); noteAttempt?.cancel(); noteAttempt = nil
        discoveryAttempt?.cancel(); discoveryAttempt = nil; discoveryTask?.cancel(); discoveryTask = nil
        metadataGeneration = UUID(); pendingRefreshReconciliation = nil; initialContentPending = false; discoveryState = .idle; clearPreviews()
        autosaveTask?.cancel(); autosaveTask = nil
        activeLease = nil; activeVault = nil; notes = []; selectedNote = nil; requestedNoteURL = nil; failedNoteURL = nil; noteText = ""
        completedNoteCreations = [:]; hasPendingImageImport = false
        hasUnsavedChanges = false; isNoteLoading = false; alertMessage = nil
        vaultGeneration = UUID(); documentGeneration = UUID(); recoveryTarget = target
        loadingAttempt = attempt; phase = .loading; isBusy = true; isSlow = false
        let generation = vaultGeneration
        stopProgress()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.vaultGeneration == generation else { return }
                self.refreshLoadingProgress()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        return generation
    }
    func refreshLoadingProgress() {
        guard let attempt = loadingAttempt else { return }
        loadingStage = attempt.stage; isSlow = attempt.elapsed >= 5
    }

    private func current(_ generation: UUID, _ attempt: ProviderAttempt) -> Bool {
        vaultGeneration == generation && !attempt.cancelled
    }
    private func stopProgress() { progressTask?.cancel(); progressTask = nil }
    private func stopLoading(_ generation: UUID) {
        guard vaultGeneration == generation else { return }
        stopProgress(); loadingAttempt = nil; isBusy = false
    }
    private func recover(_ error: Error, generation: UUID) {
        guard vaultGeneration == generation else { return }
        stopLoading(generation); phase = .providerRecovery; activeLease = nil; discoveryState = .incomplete
        recoveryMessage = error.localizedDescription
    }
    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self else { return }
            self.autosaveTask = nil
            await self.saveCurrentNoteIfNeeded()
        }
    }
}

private extension Optional {
    func mapAsync<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let value = self else { return nil }; return try await transform(value)
    }
}
