import Foundation
import UIKit

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case onboarding
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

    private var didBootstrap = false
    private var activeSecurityScopedURL: URL?
    private var autosaveTask: Task<Void, Never>?

    init(bookmarkStore: VaultBookmarkStoring, fileService: VaultFileServing) {
        self.bookmarkStore = bookmarkStore
        self.fileService = fileService
    }

    func bootstrap() async {
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
            } catch { alertMessage = error.localizedDescription; phase = .onboarding }
            return
        }
        #endif

        guard let bookmarkData = bookmarkStore.loadBookmarkData() else {
            phase = .onboarding
            return
        }

        do {
            let url = try bookmarkStore.resolveBookmarkData(bookmarkData)
            await openVault(at: url, persistSelection: true)
        } catch {
            bookmarkStore.clearBookmarkData()
            phase = .onboarding
            alertMessage = "Your previous vault could not be reopened. Please select it again."
        }
    }

    func openVault(at url: URL, persistSelection: Bool = true) async {
        isBusy = true
        defer { isBusy = false }

        autosaveTask?.cancel()
        autosaveTask = nil
        stopAccessingCurrentVault()
        clearCurrentNote()

        if url.startAccessingSecurityScopedResource() {
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
            phase = .onboarding
            activeVault = nil
            notes = []
            selectedNote = nil
            noteText = ""
            hasUnsavedChanges = false
            alertMessage = error.localizedDescription
        }
    }

    func createVault(named name: String, in parentURL: URL) async {
        isBusy = true
        defer { isBusy = false }

        let parentAccessStarted = parentURL.startAccessingSecurityScopedResource()
        defer {
            if parentAccessStarted {
                parentURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let vaultURL = try fileService.createVault(named: name, in: parentURL)
            await openVault(at: vaultURL, persistSelection: true)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func openNote(_ note: NoteItem) async {
        await saveCurrentNoteIfNeeded()

        do {
            try loadNote(note)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func createNote(named name: String) async {
        guard let vaultURL = activeVault?.url else { return }

        isBusy = true
        defer { isBusy = false }

        do {
            let noteURL = try fileService.createNote(named: name, in: vaultURL)
            _ = try reloadNotes()

            if let note = notes.first(where: { $0.url == noteURL }) {
                await openNote(note)
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func updateNoteText(_ text: String) {
        noteText = text
        hasUnsavedChanges = true
        scheduleAutosave()
    }

    func saveCurrentNoteIfNeeded() async {
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
            alertMessage = error.localizedDescription
        }
    }

    func importImage(from sourceURL: URL, preferredFilename: String? = nil) async -> InsertedNoteImage? {
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
            alertMessage = error.localizedDescription
            return nil
        }
    }

    func importCameraImage(_ image: UIImage) async -> InsertedNoteImage? {
        guard let selectedNote, let vaultURL = activeVault?.url else { return nil }
        isBusy = true
        defer { isBusy = false }

        do {
            return try fileService.importCameraImage(image, into: selectedNote.url, vaultURL: vaultURL)
        } catch {
            alertMessage = error.localizedDescription
            return nil
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
            activeSecurityScopedURL.stopAccessingSecurityScopedResource()
        }

        activeSecurityScopedURL = nil
    }
}
