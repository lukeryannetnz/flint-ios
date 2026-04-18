import SwiftUI

struct VaultBrowserView: View {
    @ObservedObject var model: AppModel

    @State private var selectedNoteURL: URL?
    @State private var isShowingOpenPicker = false
    @State private var isShowingCreateNoteSheet = false
    @State private var noteName = ""

    var body: some View {
        NavigationSplitView {
            List(model.notes, selection: $selectedNoteURL) { note in
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title)
                        .font(.headline)
                    Text(note.relativePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(note.url)
            }
            .navigationTitle(model.activeVault?.name ?? "Vault")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        isShowingCreateNoteSheet = true
                    } label: {
                        Label("New Note", systemImage: "square.and.pencil")
                    }

                    Button {
                        isShowingOpenPicker = true
                    } label: {
                        Label("Open Vault", systemImage: "folder")
                    }
                }
            }
            .overlay {
                if model.notes.isEmpty {
                    ContentUnavailableView(
                        "No Notes Yet",
                        systemImage: "doc.text",
                        description: Text("Create your first markdown note in this vault.")
                    )
                }
            }
        } detail: {
            Group {
                if let selectedNote = model.selectedNote {
                    NoteEditorView(
                        note: selectedNote,
                        text: Binding(
                            get: { model.noteText },
                            set: { model.updateNoteText($0) }
                        ),
                        hasUnsavedChanges: model.hasUnsavedChanges,
                        onSave: {
                            Task {
                                await model.saveCurrentNoteIfNeeded()
                            }
                        }
                    )
                } else {
                    ContentUnavailableView(
                        "Select a Note",
                        systemImage: "book.closed",
                        description: Text("Choose a markdown file or create a new note.")
                    )
                }
            }
        }
        .onAppear {
            selectedNoteURL = model.selectedNote?.url
        }
        .onChange(of: model.selectedNote?.url) { _, newValue in
            selectedNoteURL = newValue
        }
        .onChange(of: selectedNoteURL) { _, newValue in
            guard let newValue, let note = model.notes.first(where: { $0.url == newValue }) else { return }

            Task {
                await model.openNote(note)
            }
        }
        .sheet(isPresented: $isShowingOpenPicker) {
            FolderPicker { url in
                isShowingOpenPicker = false
                Task {
                    await model.openVault(at: url)
                }
            } onCancel: {
                isShowingOpenPicker = false
            }
        }
        .sheet(isPresented: $isShowingCreateNoteSheet) {
            NavigationStack {
                Form {
                    TextField("Note name", text: $noteName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }
                .navigationTitle("New Note")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            noteName = ""
                            isShowingCreateNoteSheet = false
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            let newName = noteName
                            noteName = ""
                            isShowingCreateNoteSheet = false

                            Task {
                                await model.createNote(named: newName)
                            }
                        }
                        .disabled(noteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .overlay {
            if model.isBusy {
                ProgressView()
                    .controlSize(.large)
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

private struct NoteEditorView: View {
    let note: NoteItem
    @Binding var text: String
    let hasUnsavedChanges: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title)
                        .font(.title2.weight(.semibold))
                    Text(note.relativePath)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasUnsavedChanges)
            }
            .padding()

            Divider()

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .scrollContentBackground(.hidden)
                .background(Color(uiColor: .secondarySystemBackground))

            Divider()

            HStack {
                Text(hasUnsavedChanges ? "Autosaving…" : "Saved")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
