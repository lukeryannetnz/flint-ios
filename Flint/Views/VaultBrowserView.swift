import SwiftUI

struct VaultBrowserView: View {
    private enum BrowserMode: String, CaseIterable, Identifiable {
        case recent
        case folders

        var id: String { rawValue }

        var title: String {
            switch self {
            case .recent:
                return "Recent"
            case .folders:
                return "All Notes"
            }
        }
    }

    @ObservedObject var model: AppModel

    @State private var selectedNoteURL: URL?
    @State private var isShowingOpenPicker = false
    @State private var isShowingCreateNoteSheet = false
    @State private var noteName = ""
    @State private var browserMode: BrowserMode = .recent
    @State private var folderPathComponents: [String] = []
    @State private var presentationMode: DocumentPresentationMode = .rendered
    @State private var isInlineEditing = false

    var body: some View {
        splitView
            .onAppear {
                selectedNoteURL = model.selectedNote?.url
            }
            .onChange(of: browserMode) { _, newValue in
                handleBrowserModeChange(newValue)
            }
            .onChange(of: model.selectedNote?.url) { _, newValue in
                syncSelectedNoteURL(newValue)
            }
            .onChange(of: selectedNoteURL) { _, newValue in
                handleSelectedNoteURLChange(newValue)
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
                createNoteSheet
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

    private var splitView: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
    }

    private var sidebarContent: some View {
        browserListContent
            .navigationTitle(sidebarTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Browse", selection: $browserMode) {
                        ForEach(BrowserMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .opacity(isInlineEditing ? 0 : 1)
                }

                if !isInlineEditing {
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
    }

    @ViewBuilder
    private var detailContent: some View {
        if let selectedNote = model.selectedNote {
            NoteDocumentView(
                note: selectedNote,
                text: Binding(
                    get: { model.noteText },
                    set: { model.updateNoteText($0) }
                ),
                presentationMode: $presentationMode,
                isInlineEditing: $isInlineEditing,
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

    private var createNoteSheet: some View {
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

    private func handleBrowserModeChange(_ newValue: BrowserMode) {
        if newValue == .recent {
            folderPathComponents = []
        }
    }

    private func syncSelectedNoteURL(_ newValue: URL?) {
        selectedNoteURL = newValue
    }

    private func handleSelectedNoteURLChange(_ newValue: URL?) {
        if model.selectedNote?.url != newValue {
            isInlineEditing = false
        }

        guard let newValue, let note = model.notes.first(where: { $0.url == newValue }) else { return }

        Task {
            await model.openNote(note)
        }
    }

    private var sidebarTitle: String {
        if browserMode == .folders, let currentFolder {
            return currentFolder.path.isEmpty ? currentFolder.name : currentFolder.name
        }

        return model.activeVault?.name ?? "Vault"
    }

    private var folderTree: VaultFolder {
        VaultFolder.root(vaultName: model.activeVault?.name ?? "Vault", notes: model.notes)
    }

    private var currentFolder: VaultFolder? {
        folderTree.folder(at: folderPathComponents[...])
    }

    @ViewBuilder
    private var browserListContent: some View {
        if browserMode == .recent {
            recentNotesList
        } else {
            allNotesList
        }
    }

    private var recentNotesList: some View {
        List(selection: $selectedNoteURL) {
            ForEach(model.notes) { note in
                RecentNoteCard(note: note)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .tag(note.url)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var allNotesList: some View {
        List(selection: $selectedNoteURL) {
            if let currentFolder {
                Section {
                    BreadcrumbBar(
                        vaultName: model.activeVault?.name ?? "Vault",
                        pathComponents: folderPathComponents,
                        onSelectDepth: { depth in
                            folderPathComponents = Array(folderPathComponents.prefix(depth))
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                    .listRowSeparator(.hidden)

                    ForEach(currentFolder.childFolders) { folder in
                        Button {
                            folderPathComponents = folder.breadcrumbComponents
                        } label: {
                            FolderDrilldownRow(folder: folder)
                        }
                    }

                    ForEach(currentFolder.notes) { note in
                        FolderNoteRow(note: note)
                            .tag(note.url)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

private enum DocumentPresentationMode: String, CaseIterable, Identifiable {
    case rendered
    case markdown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rendered:
            return "Document"
        case .markdown:
            return "Markdown"
        }
    }
}

private struct NoteDocumentView: View {
    let note: NoteItem
    @Binding var text: String
    @Binding var presentationMode: DocumentPresentationMode
    @Binding var isInlineEditing: Bool
    let hasUnsavedChanges: Bool
    let onSave: () -> Void

    private var document: MarkdownDocument {
        MarkdownDocument(noteTitle: note.title, markdown: text)
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(note.title)
                            .font(.system(size: 34, weight: .semibold, design: .serif))
                            .foregroundStyle(Color.primary)

                        HStack(spacing: 12) {
                            Text(note.relativePath)
                            Text(note.lastEditedDisplayText)
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                        if !isInlineEditing {
                            Picker("View Mode", selection: $presentationMode) {
                                ForEach(DocumentPresentationMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 280)
                        }
                    }

                    if presentationMode == .markdown || isInlineEditing {
                        TextEditor(text: $text)
                            .font(.system(size: 17, weight: .regular, design: .default))
                            .frame(minHeight: 420)
                            .padding(18)
                            .background(documentSurface)
                            .overlay(alignment: .topTrailing) {
                                if isInlineEditing {
                                    Button("Done") {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isInlineEditing = false
                                        }
                                    }
                                    .padding(14)
                                }
                            }
                    } else {
                        MarkdownDocumentView(document: document)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isInlineEditing = true
                                }
                            }
                            .padding(22)
                            .background(documentSurface)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack {
                Spacer()

                if hasUnsavedChanges {
                    HStack {
                        Text("Autosaving…")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Save", action: onSave)
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 18)
                    .padding(.horizontal, 22)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isInlineEditing)
    }

    private var documentSurface: some ShapeStyle {
        Color(uiColor: .secondarySystemBackground)
    }
}

private struct RecentNoteCard: View {
    let note: NoteItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(note.folderPath.isEmpty ? "Top level" : note.folderPath)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(note.title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(note.previewText.isEmpty ? "No preview available yet." : note.previewText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Text(note.lastEditedDisplayText)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private struct FolderNoteRow: View {
    let note: NoteItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.title)
                .font(.headline.weight(.medium))
            Text(note.previewText.isEmpty ? "No preview available yet." : note.previewText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Text(note.lastEditedDisplayText)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

private struct FolderDrilldownRow: View {
    let folder: VaultFolder

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.body)
                .foregroundStyle(Color(red: 0.98, green: 0.63, blue: 0.19))

            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name)
                    .font(.headline.weight(.medium))
                    .foregroundStyle(.primary)
                Text("\(folder.descendantNoteCount) notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

private struct BreadcrumbBar: View {
    let vaultName: String
    let pathComponents: [String]
    let onSelectDepth: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                BreadcrumbChip(title: vaultName, isEmphasized: pathComponents.isEmpty) {
                    onSelectDepth(0)
                }

                ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)

                    BreadcrumbChip(title: component, isEmphasized: index == pathComponents.count - 1) {
                        onSelectDepth(index + 1)
                    }
                }
            }
        }
    }
}

private struct BreadcrumbChip: View {
    let title: String
    let isEmphasized: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(isEmphasized ? .semibold : .medium))
                .foregroundStyle(isEmphasized ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isEmphasized ? Color(uiColor: .secondarySystemBackground) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct MarkdownDocumentView: View {
    let document: MarkdownDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(document.blocks) { block in
                MarkdownBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case let .heading(level, text):
            markdownText(text, font: headingFont(for: level))
        case let .paragraph(text):
            markdownText(text, font: .system(size: 18, weight: .regular, design: .default))
                .foregroundStyle(.primary)
        case let .bulletList(items):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("•")
                        markdownText(item, font: .system(size: 18))
                    }
                }
            }
        case let .checklist(items):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isChecked ? Color.accentColor : Color.secondary)
                        markdownText(item.text, font: .system(size: 18))
                    }
                }
            }
        case let .quote(text):
            HStack(alignment: .top, spacing: 14) {
                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(width: 3)
                markdownText(text, font: .system(size: 18, design: .serif))
                    .foregroundStyle(.secondary)
            }
        case let .codeBlock(language, code):
            VStack(alignment: .leading, spacing: 10) {
                if let language {
                    Text(language.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(size: 15, weight: .regular, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        case let .table(headers, rows):
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    ForEach(headers, id: \.self) { header in
                        Text(header)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            markdownText(cell, font: .system(size: 16))
                        }
                    }
                }
            }
            .padding(16)
            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        case let .image(alt, source):
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemBackground))
                    .frame(height: 180)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text(source)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                if !alt.isEmpty {
                    Text(alt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func markdownText(_ string: String, font: Font) -> some View {
        Group {
            if let attributed = try? AttributedString(markdown: string) {
                Text(attributed)
                    .font(font)
                    .tint(.accentColor)
            } else {
                Text(string)
                    .font(font)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .system(size: 30, weight: .semibold, design: .serif)
        case 2:
            return .system(size: 24, weight: .semibold, design: .serif)
        case 3:
            return .system(size: 20, weight: .semibold, design: .serif)
        default:
            return .system(size: 18, weight: .semibold, design: .default)
        }
    }
}
