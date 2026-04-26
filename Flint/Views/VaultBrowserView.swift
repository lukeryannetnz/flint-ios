import SwiftUI
import UIKit

struct VaultBrowserView: View {
    private enum SwipeBackBehavior {
        static let minimumHorizontalTranslation: CGFloat = 60
        static let minimumHorizontalPrediction: CGFloat = 120
        static let maximumVerticalTranslation: CGFloat = 80
    }

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
                }

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
                Section {
                    TextField("Note name", text: $noteName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                Section("Location") {
                    Text(createNoteLocationDescription)
                        .foregroundStyle(.secondary)
                }
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
                        let targetFolderPathComponents = createNoteFolderPathComponents
                        noteName = ""
                        isShowingCreateNoteSheet = false

                        Task {
                            await model.createNote(named: newName, inFolderPath: targetFolderPathComponents)
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

    private var createNoteFolderPathComponents: [String] {
        browserMode == .folders ? folderPathComponents : []
    }

    private var createNoteLocationDescription: String {
        let pathComponents = createNoteFolderPathComponents
        return pathComponents.isEmpty ? "Vault Root" : pathComponents.joined(separator: "/")
    }

    private func syncSelectedNoteURL(_ newValue: URL?) {
        selectedNoteURL = newValue
    }

    private func handleSelectedNoteURLChange(_ newValue: URL?) {
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
        .contentShape(Rectangle())
        .simultaneousGesture(folderBackSwipeGesture)
    }

    private var folderBackSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onEnded { value in
                guard shouldNavigateBackFromFolder(for: value) else { return }
                navigateBackFromFolder()
            }
    }

    private func shouldNavigateBackFromFolder(for value: DragGesture.Value) -> Bool {
        guard browserMode == .folders, !folderPathComponents.isEmpty else { return false }

        let horizontalTranslation = value.translation.width
        let predictedHorizontalTranslation = value.predictedEndTranslation.width
        let verticalTranslation = abs(value.translation.height)

        guard verticalTranslation <= SwipeBackBehavior.maximumVerticalTranslation else {
            return false
        }

        return horizontalTranslation >= SwipeBackBehavior.minimumHorizontalTranslation ||
            predictedHorizontalTranslation >= SwipeBackBehavior.minimumHorizontalPrediction
    }

    private func navigateBackFromFolder() {
        guard !folderPathComponents.isEmpty else { return }
        folderPathComponents.removeLast()
    }
}

private struct NoteDocumentView: View {
    let note: NoteItem
    @Binding var text: String
    let hasUnsavedChanges: Bool
    let onSave: () -> Void
    @State private var isEditing = false
    @State private var formattingState = FlintFormattingState()
    @State private var pendingCommand: RichTextEditorCommand?
    @State private var nextCommandID = 0
    @State private var isShowingLinkPrompt = false
    @State private var pendingLink = "https://"

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(note.relativePath)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(note.lastEditedDisplayText)
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        if isEditing {
                            Button {
                                pendingCommand = makeCommand(.endEditing)
                            } label: {
                                Image(systemName: "keyboard.chevron.compact.down")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                    Text(note.title)
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                        .foregroundStyle(.primary)
                }

                if isEditing {
                    RichFormattingBar(
                        formattingState: formattingState,
                        onCommand: { action in
                            pendingCommand = makeCommand(action)
                        },
                        onInsertLink: {
                            pendingLink = "https://"
                            isShowingLinkPrompt = true
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                RichTextNoteEditor(
                    noteID: note.url,
                    markdown: $text,
                    isEditing: $isEditing,
                    formattingState: $formattingState,
                    pendingCommand: $pendingCommand,
                    onSave: onSave
                )
                .id(note.url.path)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(documentSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if hasUnsavedChanges {
                        HStack(spacing: 10) {
                            Text("Autosaving…")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(18)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 22)
            .padding(.vertical, 28)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isEditing)
        .alert("Add Link", isPresented: $isShowingLinkPrompt) {
            TextField("https://example.com", text: $pendingLink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Apply") {
                pendingCommand = makeCommand(.applyLink(pendingLink))
            }
            .disabled(pendingLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Apply the link to the current selection.")
        }
        .onChange(of: note.url) { _, _ in
            isEditing = false
            formattingState = FlintFormattingState()
            pendingCommand = nil
            pendingLink = "https://"
        }
    }

    private var documentSurface: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(uiColor: .secondarySystemBackground),
                Color(uiColor: .systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func makeCommand(_ action: RichTextEditorCommand.Action) -> RichTextEditorCommand {
        nextCommandID += 1
        return RichTextEditorCommand(id: nextCommandID, action: action)
    }
}

private struct RichTextSurfaceDiagnostics: Equatable {
    var viewportSize: CGSize = .zero
    var contentSize: CGSize = .zero
    var contentOffset: CGPoint = .zero
    var adjustedInsets: UIEdgeInsets = .zero
    var availableTextWidth: CGFloat = 0
    var textContainerWidth: CGFloat = 0
    var selectedRange = NSRange(location: 0, length: 0)
    var isEditing = false
    var isDragging = false
    var isDecelerating = false
    var isTracking = false
    var panState = "possible"

    var horizontalOverflow: CGFloat {
        max(contentSize.width - viewportSize.width, 0)
    }

    var textContainerOverflow: CGFloat {
        max(textContainerWidth - availableTextWidth, 0)
    }
}

private struct RichFormattingBar: View {
    let formattingState: FlintFormattingState
    let onCommand: (RichTextEditorCommand.Action) -> Void
    let onInsertLink: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button {
                    onCommand(.undo)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!formattingState.canUndo)
                .modifier(ChromeButtonStyle(isActive: false))

                Button {
                    onCommand(.redo)
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!formattingState.canRedo)
                .modifier(ChromeButtonStyle(isActive: false))

                Menu {
                    ForEach(FlintBlockStyle.allCases, id: \.self) { style in
                        Button {
                            onCommand(.setBlockStyle(style))
                        } label: {
                            Label(style.label, systemImage: formattingState.blockStyle == style ? "checkmark" : blockSymbol(for: style))
                        }
                    }
                } label: {
                    Label(formattingState.blockStyle.label, systemImage: blockSymbol(for: formattingState.blockStyle))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                }

                Button {
                    onCommand(.toggleBold)
                } label: {
                    Image(systemName: "bold")
                }
                .modifier(ChromeButtonStyle(isActive: formattingState.isBold))

                Button {
                    onCommand(.toggleItalic)
                } label: {
                    Image(systemName: "italic")
                }
                .modifier(ChromeButtonStyle(isActive: formattingState.isItalic))

                Button {
                    onCommand(.toggleInlineCode)
                } label: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                }
                .modifier(ChromeButtonStyle(isActive: formattingState.isCode))

                Button {
                    formattingState.hasLink ? onCommand(.removeLink) : onInsertLink()
                } label: {
                    Image(systemName: formattingState.hasLink ? "link.badge.minus" : "link.badge.plus")
                }
                .disabled(!formattingState.hasSelection && !formattingState.hasLink)
                .modifier(ChromeButtonStyle(isActive: formattingState.hasLink))
            }
        }
    }

    private func blockSymbol(for style: FlintBlockStyle) -> String {
        switch style {
        case .body:
            return "text.alignleft"
        case .heading1:
            return "textformat.size.larger"
        case .heading2:
            return "textformat"
        case .heading3:
            return "textformat.size.smaller"
        case .bulletList:
            return "list.bullet"
        case .numberedList:
            return "list.number"
        case .quote:
            return "text.quote"
        case .codeBlock:
            return "curlybraces"
        }
    }
}

private struct ChromeButtonStyle: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.semibold))
            .foregroundStyle(isActive ? Color.accentColor : .secondary)
            .frame(width: 34, height: 34)
            .background(
                Circle()
                    .fill(isActive ? Color.accentColor.opacity(0.14) : Color(uiColor: .secondarySystemBackground))
            )
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

private struct RichTextEditorCommand: Equatable {
    enum Action: Equatable {
        case toggleBold
        case toggleItalic
        case toggleInlineCode
        case setBlockStyle(FlintBlockStyle)
        case applyLink(String)
        case removeLink
        case undo
        case redo
        case endEditing
    }

    let id: Int
    let action: Action
}

private struct RichTextNoteEditor: UIViewRepresentable {
    let noteID: URL
    @Binding var markdown: String
    @Binding var isEditing: Bool
    @Binding var formattingState: FlintFormattingState
    @Binding var pendingCommand: RichTextEditorCommand?
    let onSave: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            markdown: $markdown,
            isEditing: $isEditing,
            formattingState: $formattingState,
            pendingCommand: $pendingCommand,
            onSave: onSave
        )
    }

    func makeUIView(context: Context) -> FlintRichTextView {
        let textView = FlintRichTextView()
        textView.delegate = context.coordinator
        textView.onReadTap = { [weak coordinator = context.coordinator] location in
            coordinator?.beginEditing(at: location)
        }
        context.coordinator.attach(textView)
        return textView
    }

    func updateUIView(_ textView: FlintRichTextView, context: Context) {
        context.coordinator.onSave = onSave
        context.coordinator.noteID = noteID

        let requiresReload = context.coordinator.lastLoadedNoteID != noteID ||
            (!context.coordinator.isApplyingInternalChange && context.coordinator.lastSerializedMarkdown != markdown)
        let requiresWidthDeferredReload = context.coordinator.needsDeferredWidthLoad && textView.currentAvailableTextWidth() > 1

        if requiresReload || requiresWidthDeferredReload {
            context.coordinator.loadMarkdown(markdown, for: noteID)
        }

        textView.isEditable = isEditing
        textView.isSelectable = isEditing
        textView.tintColor = UIColor(named: "AccentColor") ?? .systemBlue
        textView.showsVerticalScrollIndicator = true
        textView.stabilizeScrollGeometry()
        textView.updatePlaceholderVisibility()

        if isEditing, textView.window != nil, !textView.isFirstResponder {
            DispatchQueue.main.async {
                guard isEditing, textView.window != nil, !textView.isFirstResponder else { return }
                textView.becomeFirstResponder()
            }
        } else if !isEditing, textView.isFirstResponder {
            textView.resignFirstResponder()
        }

        if let pendingCommand, context.coordinator.lastHandledCommandID != pendingCommand.id {
            context.coordinator.handle(command: pendingCommand)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var markdown: String
        @Binding var isEditing: Bool
        @Binding var formattingState: FlintFormattingState
        @Binding var pendingCommand: RichTextEditorCommand?
        var onSave: () -> Void
        weak var textView: FlintRichTextView?
        var noteID: URL?
        var lastLoadedNoteID: URL?
        var lastSerializedMarkdown = ""
        var lastHandledCommandID = 0
        var isApplyingInternalChange = false
        var lastKnownSelectedRange = NSRange(location: 0, length: 0)
        var selectionBeforeToolbarInteraction: NSRange?
        var needsDeferredWidthLoad = true
        var lastLoadedAvailableTextWidth: CGFloat = 0
        var lastOverflowCorrectionWidth: CGFloat = -1
        var isReconcilingLayoutMetrics = false

        init(
            markdown: Binding<String>,
            isEditing: Binding<Bool>,
            formattingState: Binding<FlintFormattingState>,
            pendingCommand: Binding<RichTextEditorCommand?>,
            onSave: @escaping () -> Void
        ) {
            _markdown = markdown
            _isEditing = isEditing
            _formattingState = formattingState
            _pendingCommand = pendingCommand
            self.onSave = onSave
        }

        func attach(_ textView: FlintRichTextView) {
            self.textView = textView
            textView.backgroundColor = .clear
            textView.adjustsFontForContentSizeCategory = true
            textView.alwaysBounceVertical = true
            textView.alwaysBounceHorizontal = false
            textView.autocapitalizationType = .sentences
            textView.autocorrectionType = .yes
            textView.isDirectionalLockEnabled = true
            textView.isScrollEnabled = true
            textView.keyboardDismissMode = .interactive
            textView.smartDashesType = .yes
            textView.smartQuotesType = .yes
            textView.smartInsertDeleteType = .yes
            textView.showsHorizontalScrollIndicator = false
            textView.contentInsetAdjustmentBehavior = .automatic
            textView.textContainerInset = UIEdgeInsets(top: 30, left: 28, bottom: 40, right: 28)
            textView.textContainer.widthTracksTextView = false
            textView.textContainer.heightTracksTextView = false
            textView.textContainer.lineFragmentPadding = 0
            textView.textContainer.lineBreakMode = .byWordWrapping
            textView.typingAttributes = FlintRichTextCodec.defaultTypingAttributes(for: .body)
            textView.linkTextAttributes = [.foregroundColor: UIColor.systemBlue]
            textView.placeholderText = "Start writing. Tap anywhere to place the cursor."
            textView.onLayoutMetricsChange = { [weak self] richTextView in
                DispatchQueue.main.async { [weak self, weak richTextView] in
                    guard let self, let richTextView else { return }
                    self.reconcileLayoutMetrics(in: richTextView)
                }
            }
        }

        func loadMarkdown(_ markdown: String, for noteID: URL) {
            guard let textView else { return }
            let availableWidth = textView.currentAvailableTextWidth()
            if availableWidth <= 1 {
                needsDeferredWidthLoad = true
                return
            }

            isApplyingInternalChange = true
            if lastLoadedNoteID != noteID {
                lastOverflowCorrectionWidth = -1
            }
            let attributed = FlintRichTextCodec.attributedString(from: markdown)
            textView.attributedText = attributed
            FlintRichTextCodec.normalizeStyling(in: textView.textStorage)
            textView.typingAttributes = FlintRichTextCodec.defaultTypingAttributes(for: .body)
            textView.setNeedsLayout()
            textView.layoutIfNeeded()
            textView.stabilizeScrollGeometry()
            let initialRange = NSRange(location: 0, length: 0)
            textView.selectedRange = initialRange
            lastKnownSelectedRange = initialRange
            textView.updatePlaceholderVisibility()
            lastLoadedNoteID = noteID
            lastLoadedAvailableTextWidth = textView.currentAvailableTextWidth()
            lastSerializedMarkdown = markdown
            needsDeferredWidthLoad = false
            formattingState = FlintRichTextCodec.formattingState(
                attributedString: textView.attributedText,
                selectedRange: textView.selectedRange,
                undoManager: textView.undoManager,
                typingAttributes: textView.typingAttributes
            )
            isApplyingInternalChange = false
        }

        func beginEditing(at location: CGPoint) {
            guard let textView else { return }
            let safeLocation = location
            isEditing = true
            DispatchQueue.main.async {
                guard let position = textView.closestPosition(to: safeLocation) else {
                    textView.becomeFirstResponder()
                    return
                }
                textView.selectedTextRange = textView.textRange(from: position, to: position)
                self.lastKnownSelectedRange = textView.selectedRange
                textView.becomeFirstResponder()
                self.refreshStateAndMarkdown(from: textView)
            }
        }

        func handle(command: RichTextEditorCommand) {
            guard let textView else { return }
            lastHandledCommandID = command.id
            restoreSelectionIfNeeded(in: textView)

            switch command.action {
            case .toggleBold:
                toggleFontTrait(.traitBold, in: textView)
            case .toggleItalic:
                toggleFontTrait(.traitItalic, in: textView)
            case .toggleInlineCode:
                toggleInlineCode(in: textView)
            case .setBlockStyle(let style):
                applyBlockStyle(style, in: textView)
            case .applyLink(let string):
                applyLink(string, in: textView)
            case .removeLink:
                mutateSelection(in: textView) { attributed, range in
                    attributed.removeAttribute(.link, range: range)
                }
            case .undo:
                textView.undoManager?.undo()
            case .redo:
                textView.undoManager?.redo()
            case .endEditing:
                isEditing = false
                textView.resignFirstResponder()
            }

            selectionBeforeToolbarInteraction = nil
            pendingCommand = nil
            if isEditing, textView.window != nil, !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
            refreshStateAndMarkdown(from: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !isEditing {
                isEditing = true
            }
            refreshStateAndMarkdown(from: textView)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let richTextView = textView as? FlintRichTextView else { return }
            FlintRichTextCodec.normalizeStyling(in: richTextView.textStorage)
            lastKnownSelectedRange = richTextView.selectedRange
            refreshStateAndMarkdown(from: richTextView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            lastKnownSelectedRange = textView.selectedRange
            refreshStateAndMarkdown(from: textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if pendingCommand != nil {
                selectionBeforeToolbarInteraction = lastKnownSelectedRange
                DispatchQueue.main.async {
                    guard self.pendingCommand != nil else { return }
                    self.isEditing = true
                    textView.becomeFirstResponder()
                    self.refreshStateAndMarkdown(from: textView)
                }
                return
            }

            if isEditing {
                isEditing = false
            }
            onSave()
            refreshStateAndMarkdown(from: textView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let textView = scrollView as? FlintRichTextView else { return }
            textView.stabilizeScrollGeometry()
        }

        func textView(
            _ textView: UITextView,
            shouldInteractWith url: URL,
            in characterRange: NSRange,
            interaction: UITextItemInteraction
        ) -> Bool {
            if isEditing {
                return true
            }

            UIApplication.shared.open(url)
            return false
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            guard let richTextView = textView as? FlintRichTextView else { return true }

            if replacement == "\n" {
                return handleReturn(in: richTextView, range: range)
            }

            return true
        }

        private func handleReturn(in textView: FlintRichTextView, range: NSRange) -> Bool {
            let text = textView.attributedText.string as NSString
            let paragraphRange = text.paragraphRange(for: range)
            let style = FlintRichTextCodec.blockStyle(at: paragraphRange.location, in: textView.attributedText)
            let paragraphText = FlintRichTextCodec.paragraphText(in: text, paragraphRange: paragraphRange)
            let visibleContent = FlintRichTextCodec.visibleContent(for: paragraphText, style: style)

            switch style {
            case .bulletList, .numberedList:
                let nextStyle: FlintBlockStyle = visibleContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .body : style
                let insertion = NSMutableAttributedString(string: "\n", attributes: FlintRichTextCodec.defaultTypingAttributes(for: nextStyle))
                if nextStyle == .bulletList {
                    insertion.append(NSAttributedString(string: FlintRichTextCodec.visiblePrefix(for: .bulletList, paragraphText: ""), attributes: FlintRichTextCodec.defaultTypingAttributes(for: .bulletList)))
                } else if nextStyle == .numberedList {
                    insertion.append(NSAttributedString(string: "1.\t", attributes: FlintRichTextCodec.defaultTypingAttributes(for: .numberedList)))
                }
                textView.textStorage.replaceCharacters(in: range, with: insertion)
                let cursorLocation = range.location + insertion.length
                FlintRichTextCodec.normalizeStyling(in: textView.textStorage)
                textView.selectedRange = NSRange(location: cursorLocation, length: 0)
                refreshStateAndMarkdown(from: textView)
                return false
            case .quote, .heading1, .heading2, .heading3, .codeBlock:
                let followOnStyle: FlintBlockStyle = style == .codeBlock ? .codeBlock : .body
                let insertion = NSAttributedString(string: "\n", attributes: FlintRichTextCodec.defaultTypingAttributes(for: followOnStyle))
                textView.textStorage.replaceCharacters(in: range, with: insertion)
                textView.selectedRange = NSRange(location: range.location + 1, length: 0)
                FlintRichTextCodec.normalizeStyling(in: textView.textStorage)
                refreshStateAndMarkdown(from: textView)
                return false
            case .body:
                return true
            }
        }

        private func toggleFontTrait(_ trait: UIFontDescriptor.SymbolicTraits, in textView: FlintRichTextView) {
            let emphasisKey: NSAttributedString.Key = trait == .traitBold ? .flintBold : .flintItalic

            if textView.selectedRange.length == 0 {
                var typingAttributes = textView.typingAttributes
                let isEnabled = (typingAttributes[emphasisKey] as? Bool) ?? false
                if isEnabled {
                    typingAttributes.removeValue(forKey: emphasisKey)
                } else {
                    typingAttributes[emphasisKey] = true
                }
                typingAttributes[.font] = FlintRichTextCodec.font(for: typingAttributes)
                textView.typingAttributes = typingAttributes
                return
            }

            let selectedAttributes = textView.attributedText.attributes(at: textView.selectedRange.location, effectiveRange: nil)
            let shouldEnableEmphasis: Bool
            if emphasisKey == .flintBold {
                shouldEnableEmphasis = !FlintRichTextCodec.isBold(in: selectedAttributes)
            } else {
                shouldEnableEmphasis = !FlintRichTextCodec.isItalic(in: selectedAttributes)
            }

            mutateSelection(in: textView) { attributed, range in
                if shouldEnableEmphasis {
                    attributed.addAttribute(emphasisKey, value: true, range: range)
                } else {
                    attributed.removeAttribute(emphasisKey, range: range)
                }
            }
        }

        private func toggleInlineCode(in textView: FlintRichTextView) {
            mutateSelection(in: textView) { attributed, range in
                let current = (attributed.attribute(.flintInlineCode, at: max(range.location, 0), effectiveRange: nil) as? Bool) ?? false
                if current {
                    attributed.removeAttribute(.flintInlineCode, range: range)
                } else {
                    attributed.addAttribute(.flintInlineCode, value: true, range: range)
                }
            }
        }

        private func applyBlockStyle(_ style: FlintBlockStyle, in textView: FlintRichTextView) {
            let paragraphRange = (textView.attributedText.string as NSString).paragraphRange(for: textView.selectedRange)
            FlintRichTextCodec.applyBlockStyle(style, to: textView.textStorage, paragraphRange: paragraphRange)
            textView.typingAttributes = FlintRichTextCodec.defaultTypingAttributes(for: style)
        }

        private func applyLink(_ string: String, in textView: FlintRichTextView) {
            guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            mutateSelection(in: textView) { attributed, range in
                attributed.addAttribute(.link, value: url, range: range)
            }
        }

        private func mutateSelection(in textView: FlintRichTextView, mutation: (NSMutableAttributedString, NSRange) -> Void) {
            let selectedRange = effectiveSelectionRange(in: textView)
            guard selectedRange.location != NSNotFound, selectedRange.location < max(textView.attributedText.length, 1) else { return }
            mutation(textView.textStorage, selectedRange)
            FlintRichTextCodec.normalizeStyling(in: textView.textStorage)
            textView.selectedRange = selectedRange
            lastKnownSelectedRange = selectedRange
        }

        private func refreshStateAndMarkdown(from textView: UITextView) {
            formattingState = FlintRichTextCodec.formattingState(
                attributedString: textView.attributedText,
                selectedRange: textView.selectedRange,
                undoManager: textView.undoManager,
                typingAttributes: textView.typingAttributes
            )

            guard !isApplyingInternalChange else { return }
            let nextMarkdown = FlintRichTextCodec.markdown(from: textView.attributedText)
            lastSerializedMarkdown = nextMarkdown
            if markdown != nextMarkdown {
                isApplyingInternalChange = true
                markdown = nextMarkdown
                isApplyingInternalChange = false
            }

            (textView as? FlintRichTextView)?.updatePlaceholderVisibility()
        }

        private func restoreSelectionIfNeeded(in textView: UITextView) {
            if let preservedSelection = selectionBeforeToolbarInteraction,
               preservedSelection.location != NSNotFound {
                let clampedLocation = min(preservedSelection.location, textView.attributedText.length)
                let clampedLength = min(preservedSelection.length, max(0, textView.attributedText.length - clampedLocation))
                textView.selectedRange = NSRange(location: clampedLocation, length: clampedLength)
                lastKnownSelectedRange = textView.selectedRange
                return
            }

            guard isEditing, !textView.isFirstResponder else { return }
            guard lastKnownSelectedRange.location != NSNotFound else { return }
            let clampedLocation = min(lastKnownSelectedRange.location, textView.attributedText.length)
            let clampedLength = min(lastKnownSelectedRange.length, max(0, textView.attributedText.length - clampedLocation))
            textView.selectedRange = NSRange(location: clampedLocation, length: clampedLength)
        }

        private func effectiveSelectionRange(in textView: UITextView) -> NSRange {
            if textView.selectedRange.length > 0 {
                return textView.selectedRange
            }

            if textView.selectedRange.location != NSNotFound, textView.selectedRange.location < textView.attributedText.length {
                return NSRange(location: textView.selectedRange.location, length: 1)
            }

            if lastKnownSelectedRange.length > 0 {
                return lastKnownSelectedRange
            }

            let fallbackLocation = max(min(textView.selectedRange.location - 1, textView.attributedText.length - 1), 0)
            return NSRange(location: fallbackLocation, length: min(1, textView.attributedText.length))
        }

        func reconcileLayoutMetrics(in textView: FlintRichTextView) {
            guard !isApplyingInternalChange, !isReconcilingLayoutMetrics else {
                return
            }

            let availableWidth = textView.currentAvailableTextWidth()
            guard availableWidth > 1 else {
                needsDeferredWidthLoad = true
                return
            }

            let surface = textView.surfaceDiagnostics(isEditing: isEditing)
            let widthChangedSinceLoad = lastLoadedNoteID != nil && abs(lastLoadedAvailableTextWidth - availableWidth) > 0.5
            let hasOverflow = surface.horizontalOverflow > 0.5 || surface.textContainerOverflow > 0.5
            let shouldCorrectOverflow = hasOverflow &&
                !isEditing &&
                !textView.isTracking &&
                !textView.isDragging &&
                !textView.isDecelerating &&
                abs(lastOverflowCorrectionWidth - availableWidth) > 0.5

            guard needsDeferredWidthLoad || widthChangedSinceLoad || shouldCorrectOverflow else {
                return
            }

            guard let currentNoteID = noteID ?? lastLoadedNoteID else {
                return
            }

            let isReloadingCurrentNote = currentNoteID == lastLoadedNoteID
            let preservedOffsetY = textView.contentOffset.y
            let preservedSelection = textView.selectedRange

            isReconcilingLayoutMetrics = true
            loadMarkdown(markdown, for: currentNoteID)
            if shouldCorrectOverflow {
                lastOverflowCorrectionWidth = availableWidth
            }

            if isReloadingCurrentNote {
                if isEditing {
                    let clampedLocation = min(preservedSelection.location, textView.attributedText.length)
                    let clampedLength = min(preservedSelection.length, max(0, textView.attributedText.length - clampedLocation))
                    textView.selectedRange = NSRange(location: clampedLocation, length: clampedLength)
                    lastKnownSelectedRange = textView.selectedRange
                } else {
                    let minimumOffsetY = -textView.adjustedContentInset.top
                    let maximumOffsetY = max(minimumOffsetY, textView.contentSize.height - textView.bounds.height + textView.adjustedContentInset.bottom)
                    let clampedOffsetY = min(max(preservedOffsetY, minimumOffsetY), maximumOffsetY)
                    textView.setContentOffset(CGPoint(x: 0, y: clampedOffsetY), animated: false)
                }
            }

            isReconcilingLayoutMetrics = false
        }
    }
}

private final class FlintRichTextView: UITextView {
    var onReadTap: ((CGPoint) -> Void)?
    var onLayoutMetricsChange: ((FlintRichTextView) -> Void)?
    var placeholderText: String = "" {
        didSet {
            placeholderLabel.text = placeholderText
        }
    }

    private let placeholderLabel = UILabel()
    private let readTapMovementTolerance: CGFloat = 10
    private var readTouchStartLocation: CGPoint?
    private var hasExceededReadTapTolerance = false

    override func layoutSubviews() {
        super.layoutSubviews()
        let widthChanged = stabilizeScrollGeometry()
        let diagnostics = surfaceDiagnostics(isEditing: isEditable)
        if widthChanged || diagnostics.horizontalOverflow > 0.5 || diagnostics.textContainerOverflow > 0.5 {
            onLayoutMetricsChange?(self)
        }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setUpPlaceholder()
        delaysContentTouches = false
        canCancelContentTouches = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpPlaceholder()
        delaysContentTouches = false
        canCancelContentTouches = true
    }

    func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !text.isEmpty
    }

    @discardableResult
    func stabilizeScrollGeometry() -> Bool {
        let targetWidth = availableTextWidth()
        var widthChanged = false
        if targetWidth > 0, abs(textContainer.size.width - targetWidth) > 0.5 {
            widthChanged = true
            textContainer.size = CGSize(width: targetWidth, height: .greatestFiniteMagnitude)
            layoutManager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: textStorage.length), actualCharacterRange: nil)
            layoutManager.ensureLayout(for: textContainer)
        }

        if contentOffset.x != 0 {
            setContentOffset(CGPoint(x: 0, y: contentOffset.y), animated: false)
        }

        return widthChanged
    }

    func surfaceDiagnostics(isEditing: Bool) -> RichTextSurfaceDiagnostics {
        RichTextSurfaceDiagnostics(
            viewportSize: bounds.size,
            contentSize: contentSize,
            contentOffset: contentOffset,
            adjustedInsets: adjustedContentInset,
            availableTextWidth: availableTextWidth(),
            textContainerWidth: textContainer.size.width,
            selectedRange: selectedRange,
            isEditing: isEditing,
            isDragging: isDragging,
            isDecelerating: isDecelerating,
            isTracking: isTracking,
            panState: panGestureRecognizer.state.debugName
        )
    }

    private func setUpPlaceholder() {
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = UIFont.systemFont(ofSize: 19, weight: .regular)
        placeholderLabel.textColor = .tertiaryLabel
        placeholderLabel.numberOfLines = 0
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            placeholderLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 34)
        ])
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !isEditable, let touch = touches.first {
            readTouchStartLocation = touch.location(in: self)
            hasExceededReadTapTolerance = false
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !isEditable,
           let startLocation = readTouchStartLocation,
           let touch = touches.first {
            let currentLocation = touch.location(in: self)
            if abs(currentLocation.x - startLocation.x) > readTapMovementTolerance ||
                abs(currentLocation.y - startLocation.y) > readTapMovementTolerance {
                hasExceededReadTapTolerance = true
            }
        }
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer {
            readTouchStartLocation = nil
            hasExceededReadTapTolerance = false
            super.touchesEnded(touches, with: event)
        }

        guard !isEditable,
              !hasExceededReadTapTolerance,
              let touch = touches.first else {
            return
        }

        let location = touch.location(in: self)
        if let url = linkURL(at: location) {
            UIApplication.shared.open(url)
            return
        }

        onReadTap?(location)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        readTouchStartLocation = nil
        hasExceededReadTapTolerance = false
        super.touchesCancelled(touches, with: event)
    }

    private func linkURL(at location: CGPoint) -> URL? {
        guard textStorage.length > 0 else { return nil }

        var fraction: CGFloat = 0
        let characterIndex = layoutManager.characterIndex(
            for: location,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )

        guard characterIndex < textStorage.length else { return nil }
        return textStorage.attribute(.link, at: characterIndex, effectiveRange: nil) as? URL
    }

    private func availableTextWidth() -> CGFloat {
        max(bounds.width - adjustedContentInset.left - adjustedContentInset.right - textContainerInset.left - textContainerInset.right, 0)
    }

    func currentAvailableTextWidth() -> CGFloat {
        availableTextWidth()
    }
}

private extension UIGestureRecognizer.State {
    var debugName: String {
        switch self {
        case .possible:
            return "possible"
        case .began:
            return "began"
        case .changed:
            return "changed"
        case .ended:
            return "ended"
        case .cancelled:
            return "cancelled"
        case .failed:
            return "failed"
        @unknown default:
            return "unknown"
        }
    }
}
