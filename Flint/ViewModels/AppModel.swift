import Foundation
import UIKit

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case onboarding
        case restorationRecovery
        case ready
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var activeVault: Vault?
    @Published private(set) var notes: [NoteItem] = []
    @Published private(set) var selectedNote: NoteItem?
    @Published var noteText = ""
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var isBusy = false
    @Published var alertMessage: String?

    private let bookmarkStore: VaultBookmarkStoring
    private let fileService: VaultFileServing
    private let restorationSafety: RestorationSafetyChecking
    private var restorationAttemptActive = false

    private var didBootstrap = false
    private var activeSecurityScopedURL: URL?
    private var autosaveTask: Task<Void, Never>?

    init(bookmarkStore: VaultBookmarkStoring, fileService: VaultFileServing,
         restorationSafety: RestorationSafetyChecking = RestorationSafety.shared) {
        self.bookmarkStore = bookmarkStore
        self.fileService = fileService
        self.restorationSafety = restorationSafety
    }

    func bootstrap() async {
        return await DebugLog.shared.measureAsync(.launch) {
            guard !didBootstrap else { return }
            didBootstrap = true

            #if DEBUG
            if ImageWorkflowTestSupport.active {
                do {
                    let root = try ImageWorkflowTestSupport.prepare()
                    await openVault(at: root, persistSelection: false)
                    let name = ProcessInfo.processInfo.environment["FLINT_IMAGE_TEST_NOTE"] ?? "Existing.md"
                    if let note = notes.first(where: { $0.url.lastPathComponent == name }) {
                        await openNote(note)
                    }
                } catch {
                    DebugLog.shared.handledFailure(error)
                    alertMessage = error.localizedDescription
                    phase = .onboarding
                }
                return
            }
            #endif

            guard let bookmarkData = bookmarkStore.loadBookmarkData() else {
                phase = .onboarding
                return
            }

            await restoreBookmark(bookmarkData, explicit: false)
        }
    }

    func retryRestoration() async {
        guard phase == .restorationRecovery, !restorationAttemptActive else { return }
        guard let bookmark = bookmarkStore.loadBookmarkData() else { phase = .onboarding; return }
        await restoreBookmark(bookmark, explicit: true)
    }

    func chooseAnotherVault() async {
        guard phase == .restorationRecovery, !restorationAttemptActive else { return }
        restorationAttemptActive = true
        await restorationSafety.finish(completed: false)
        restorationAttemptActive = false
        phase = .onboarding
    }

    private func restoreBookmark(_ bookmark: Data, explicit: Bool) async {
        restorationAttemptActive = true
        defer { restorationAttemptActive = false }
        let action = DebugLog.shared.begin(.restoration)
        guard await restorationSafety.begin(launchID: DebugLog.shared.launchID, explicit: explicit) else {
            action.finish(.abandonment)
            phase = .restorationRecovery
            return
        }
        phase = .loading
        do {
            let url = try bookmarkStore.resolveBookmarkData(bookmark)
            await openVault(at: url, persistSelection: true)
            let completed = phase == .ready
            await restorationSafety.finish(completed: completed)
            action.finish(completed ? .success : .abandonment)
        } catch {
            action.finish(.failure, error: error)
            await restorationSafety.finish(completed: false)
            bookmarkStore.clearBookmarkData()
            phase = .onboarding
            alertMessage = "Your previous vault could not be reopened. Please select it again."
        }
    }

    func openVault(at url: URL, persistSelection: Bool = true) async {
        return await DebugLog.shared.measureAsync(.vaultOpen, file: url) {
            isBusy = true
            defer { isBusy = false }

            autosaveTask?.cancel()
            autosaveTask = nil
            stopAccessingCurrentVault()
            clearCurrentNote()

            let access = DebugLog.shared.begin(.securityScope, file: url)
            let granted = url.startAccessingSecurityScopedResource()
            access.finish(.success, count: granted ? 1 : 0)
            if granted {
                activeSecurityScopedURL = url
            }

            do {
                if persistSelection {
                    let bookmarkData = try bookmarkStore.makeBookmark(for: url)
                    bookmarkStore.saveBookmarkData(bookmarkData)
                }

                activeVault = Vault(name: url.lastPathComponent, url: url)
                phase = .ready
                if let note = try reloadNotes() {
                    try loadNote(note)
                }
            } catch {
                DebugLog.shared.handledFailure(error)
                phase = .onboarding
                activeVault = nil
                notes = []
                selectedNote = nil
                noteText = ""
                hasUnsavedChanges = false
                alertMessage = error.localizedDescription
            }
        }
    }

    func createVault(named name: String, in parentURL: URL) async {
        return await DebugLog.shared.measureAsync(.vaultCreate, file: parentURL) {
            isBusy = true
            defer { isBusy = false }

            let access = DebugLog.shared.begin(.securityScope, file: parentURL)
            let parentAccessStarted = parentURL.startAccessingSecurityScopedResource()
            access.finish(.success, count: parentAccessStarted ? 1 : 0)
            defer {
                if parentAccessStarted {
                    DebugLog.shared.measure(.securityScopeRelease, file: parentURL) { parentURL.stopAccessingSecurityScopedResource() }
                }
            }

            do {
                let vaultURL = try fileService.createVault(named: name, in: parentURL)
                await openVault(at: vaultURL, persistSelection: true)
            } catch {
                DebugLog.shared.handledFailure(error)
                alertMessage = error.localizedDescription
            }
        }
    }

    func openNote(_ note: NoteItem) async {
        return await DebugLog.shared.measureAsync(.noteRead, file: note.url) {
            await saveCurrentNoteIfNeeded()

            do {
                try loadNote(note)
            } catch {
                DebugLog.shared.handledFailure(error)
                alertMessage = error.localizedDescription
            }
        }
    }

    func createNote(named name: String, inFolderPath folderPathComponents: [String] = []) async {
        return await DebugLog.shared.measureAsync(.noteCreate) {
            guard let vaultURL = activeVault?.url else { return }

            isBusy = true
            defer { isBusy = false }

            do {
                let targetDirectoryURL = folderPathComponents.reduce(vaultURL) { partialURL, component in
                    partialURL.appendingPathComponent(component, isDirectory: true)
                }
                let noteURL = try fileService.createNote(named: name, in: targetDirectoryURL)
                _ = try reloadNotes()

                if let note = notes.first(where: { $0.url == noteURL }) {
                    await openNote(note)
                }
            } catch {
                DebugLog.shared.handledFailure(error)
                alertMessage = error.localizedDescription
            }
        }
    }

    func updateNoteText(_ text: String) {
        noteText = text
        hasUnsavedChanges = true
        scheduleAutosave()
    }

    func saveCurrentNoteIfNeeded() async {
        return await DebugLog.shared.measureAsync(.noteSave) {
            guard hasUnsavedChanges, let selectedNote else { return }
            autosaveTask?.cancel()
            autosaveTask = nil

            do {
                try fileService.saveNote(noteText, at: selectedNote.url)
                hasUnsavedChanges = false
                if let note = try reloadNotes() {
                    try loadNote(note)
                }
            } catch {
                DebugLog.shared.handledFailure(error)
                alertMessage = error.localizedDescription
            }
        }
    }

    func importImage(from sourceURL: URL, preferredFilename: String? = nil) async -> InsertedNoteImage? {
        return await DebugLog.shared.measureAsync(.imageImport, file: sourceURL) {
            guard let selectedNote, let vaultURL = activeVault?.url else { return nil }
            isBusy = true
            defer { isBusy = false }

            do {
                return try fileService.importImage(
                    from: sourceURL,
                    preferredFilename: preferredFilename,
                    into: selectedNote.url,
                    vaultURL: vaultURL
                )
            } catch {
                DebugLog.shared.handledFailure(error)
                alertMessage = error.localizedDescription
                return nil
            }
        }
    }

    func importCameraImage(_ image: UIImage) async -> InsertedNoteImage? {
        return await DebugLog.shared.measureAsync(.imageImport) {
            guard let selectedNote, let vaultURL = activeVault?.url else { return nil }
            isBusy = true
            defer { isBusy = false }

            do {
                return try fileService.importCameraImage(image, into: selectedNote.url, vaultURL: vaultURL)
            } catch {
                DebugLog.shared.handledFailure(error)
                alertMessage = error.localizedDescription
                return nil
            }
        }
    }

    func clearAlert() {
        alertMessage = nil
    }

    // Returns a fallback for the caller to open; refreshing metadata never schedules navigation.
    private func reloadNotes() throws -> NoteItem? {
        guard let vault = activeVault else { return nil }

        let selectedURL = selectedNote?.url
        notes = try fileService.listMarkdownNotes(in: vault.url)

        if let selectedURL, let refreshedSelection = notes.first(where: { $0.url == selectedURL }) {
            selectedNote = refreshedSelection
        } else if let firstNote = notes.first {
            return firstNote
        } else {
            clearCurrentNote()
        }
        return nil
    }

    private func loadNote(_ note: NoteItem) throws {
        let text = try fileService.readNote(at: note.url)
        selectedNote = note
        noteText = text
        hasUnsavedChanges = false
    }

    private func clearCurrentNote() {
        selectedNote = nil
        noteText = ""
        hasUnsavedChanges = false
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await self?.saveCurrentNoteIfNeeded()
        }
    }

    private func stopAccessingCurrentVault() {
        if let activeSecurityScopedURL {
            DebugLog.shared.measure(.securityScopeRelease, file: activeSecurityScopedURL) { activeSecurityScopedURL.stopAccessingSecurityScopedResource() }
        }

        activeSecurityScopedURL = nil
    }
}
