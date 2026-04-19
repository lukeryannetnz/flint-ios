import Foundation

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
        stopAccessingCurrentVault()

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
            try reloadNotes()
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
            noteText = try fileService.readNote(at: note.url)
            selectedNote = note
            hasUnsavedChanges = false
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
            try reloadNotes()

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

        do {
            try fileService.saveNote(noteText, at: selectedNote.url)
            try reloadNotes()
            hasUnsavedChanges = false
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func clearAlert() {
        alertMessage = nil
    }

    private func reloadNotes() throws {
        guard let vault = activeVault else { return }

        let selectedURL = selectedNote?.url
        notes = try fileService.listMarkdownNotes(in: vault.url)

        if let selectedURL, let refreshedSelection = notes.first(where: { $0.url == selectedURL }) {
            selectedNote = refreshedSelection
        } else if let firstNote = notes.first {
            Task {
                await openNote(firstNote)
            }
        } else {
            selectedNote = nil
            noteText = ""
            hasUnsavedChanges = false
        }
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
