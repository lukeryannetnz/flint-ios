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
    @Published private(set) var requestedNoteURL: URL?
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

    private let bookmarkStore: VaultBookmarkStoring
    private let fileService: VaultFileServing
    private let restorationSafety: RestorationSafetyChecking
    private let executor: ProviderExecutor
    private let attemptFactory: () -> ProviderAttempt
    private let shareStore: DiagnosticShareStore
    private var didBootstrap = false
    private var vaultGeneration = UUID()
    private var documentGeneration = UUID()
    private var navigationGeneration = UUID()
    private var activeLease: SecurityScopeLease?
    private var loadingAttempt: ProviderAttempt?
    private var noteAttempt: ProviderAttempt?
    private var progressTask: Task<Void, Never>?
    private var autosaveTask: Task<Void, Never>?
    private var saveTask: (id: UUID, task: Task<Void, Never>)?
    private var uncertainSave: UncertainSave?
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
                    guard let url else { return }
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
        isNoteLoading = false; isBusy = false; requestedNoteURL = selectedNote?.url
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
            try await loadVault(url, persist: true, attempt: attempt, generation: generation)
            guard vaultGeneration == generation else { return }
            let completed = phase == .ready
            action.finish(completed ? .success : .abandonment)
            await restorationSafety.finish(completed: completed)
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

    private func loadVault(_ url: URL, persist: Bool, attempt: ProviderAttempt, generation: UUID) async throws {
        let request = ProviderRequest(vaultURL: url, attempt: attempt)
        let lease = try await executor.execute(request, step: .securityScope) { $0.primaryLease }
        guard current(generation, attempt) else { return }
        activeLease = lease
        let bookmark = persist ? try await bookmarkStore.makeBookmark(for: url, request: request) : nil
        guard current(generation, attempt) else { return }
        let discovered = try await fileService.listMarkdownNotes(in: url, request: request)
        guard current(generation, attempt) else { return }
        let first = discovered.first
        let text = try await first.mapAsync { try await self.fileService.readNote(at: $0.url, request: request) }
        guard current(generation, attempt) else { return }
        if let bookmark { bookmarkStore.saveBookmarkData(bookmark) }
        activeVault = Vault(name: url.lastPathComponent, url: url); notes = discovered
        selectedNote = first; requestedNoteURL = first?.url; noteText = text ?? ""; hasUnsavedChanges = false; revision = 0
        documentGeneration = UUID(); uncertainSave = nil; uncertainNoteCreation = nil; completedNoteCreations = [:]
        stopLoading(generation); phase = .ready
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

    func openNote(_ note: NoteItem) async {
        guard let root = activeVault?.url, await prepareNavigation() else { return }
        let vault = vaultGeneration
        noteAttempt?.cancel(); let attempt = attemptFactory(); noteAttempt = attempt
        documentGeneration = UUID(); let document = documentGeneration
        requestedNoteURL = note.url; alertMessage = nil
        isNoteLoading = true; isBusy = true
        defer {
            if documentGeneration == document {
                isNoteLoading = false; isBusy = false; noteAttempt = nil
                requestedNoteURL = selectedNote?.url
            }
        }
        do {
            let text = try await fileService.readNote(at: note.url, request: ProviderRequest(vaultURL: root, attempt: attempt))
            guard vaultGeneration == vault, documentGeneration == document, !attempt.cancelled else { return }
            selectedNote = note; noteText = text; revision = 0; hasUnsavedChanges = false; uncertainSave = nil
        } catch {
            guard vaultGeneration == vault, documentGeneration == document else { return }
            alertMessage = error.localizedDescription
        }
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
                    guard let existing else { return }; url = existing; uncertainNoteCreation = nil
                case .completed(.failure), .notStarted:
                    uncertainNoteCreation = nil
                    url = try await fileService.createNote(named: name, in: folder, request: request)
                }
            } else { url = try await fileService.createNote(named: name, in: folder, request: request) }
            guard vaultGeneration == vault, navigationGeneration == operation else { return }
            completedNoteCreations[key] = url
            let discovered = try await fileService.listMarkdownNotes(in: root, request: request)
            guard vaultGeneration == vault, navigationGeneration == operation else { return }
            notes = discovered
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
        guard !isNoteLoading else { return }
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
                // A refresh failure is optional metadata failure, not a failed write.
                do {
                    let refreshed = try await fileService.listMarkdownNotes(in: root, request: request)
                    guard vaultGeneration == vault, documentGeneration == document else { return }
                    notes = refreshed
                    if let selected = notes.first(where: { $0.url == note.url }) { selectedNote = selected }
                } catch { DebugLog.shared.begin(.metadata).finish(.failure, error: error) }
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

    func importImage(from sourceURL: URL, preferredFilename: String? = nil) async -> InsertedNoteImage? {
        guard let note = selectedNote, let root = activeVault?.url else { return nil }
        let document = documentGeneration, vault = vaultGeneration
        let request = ProviderRequest(vaultURL: root, attempt: attemptFactory())
        isBusy = true; defer { if documentGeneration == document { isBusy = false } }
        do {
            let inserted = try await fileService.importImage(from: sourceURL, preferredFilename: preferredFilename,
                into: note.url, vaultURL: root, request: request)
            guard documentGeneration == document, vaultGeneration == vault else { return nil }
            return inserted
        } catch {
            guard documentGeneration == document, vaultGeneration == vault else { return nil }
            alertMessage = error.localizedDescription; return nil
        }
    }

    func importCameraImage(_ image: UIImage) async -> InsertedNoteImage? {
        guard let note = selectedNote, let root = activeVault?.url else { return nil }
        let document = documentGeneration, vault = vaultGeneration
        let request = ProviderRequest(vaultURL: root, attempt: attemptFactory())
        isBusy = true; defer { if documentGeneration == document { isBusy = false } }
        do {
            let inserted = try await fileService.importCameraImage(image, into: note.url, vaultURL: root, request: request)
            guard documentGeneration == document, vaultGeneration == vault else { return nil }
            return inserted
        } catch {
            guard documentGeneration == document, vaultGeneration == vault else { return nil }
            alertMessage = error.localizedDescription; return nil
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
        autosaveTask?.cancel(); autosaveTask = nil
        activeLease = nil; activeVault = nil; notes = []; selectedNote = nil; requestedNoteURL = nil; noteText = ""
        completedNoteCreations = [:]
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
        stopLoading(generation); phase = .providerRecovery; activeLease = nil
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
