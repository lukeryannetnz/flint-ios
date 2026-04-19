import SwiftUI
import UIKit
import WebKit

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
                vaultURL: model.activeVault?.url,
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
    let vaultURL: URL?
    @Binding var text: String
    @Binding var presentationMode: DocumentPresentationMode
    @Binding var isInlineEditing: Bool
    let hasUnsavedChanges: Bool
    let onSave: () -> Void
    @State private var didAppearForCurrentNote = false
    @State private var inlineEditorHeight: CGFloat = 420
    @State private var isMarkdownEditorFocused = false

    private var document: MarkdownDocument {
        MarkdownDocument(noteTitle: note.title, markdown: text)
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    Color.clear
                        .frame(height: 0)
                        .id("note-top")

                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(note.title)
                                .font(.system(size: 34, weight: .semibold, design: .serif))
                                .foregroundStyle(Color.primary)

                            HStack(spacing: 12) {
                                Text(note.relativePath)
                                Text(note.lastEditedDisplayText)
                                Spacer()
                                DocumentModeMenu(presentationMode: $presentationMode)
                                if isInlineEditing {
                                    Button {
                                        isMarkdownEditorFocused = false
                                    } label: {
                                        Image(systemName: "keyboard.chevron.compact.down")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }

                        if isInlineEditing {
                            InlineMarkdownEditor(
                                text: $text,
                                isEditing: $isInlineEditing,
                                measuredHeight: $inlineEditorHeight,
                                isFocused: $isMarkdownEditorFocused
                            ) {
                                handleInlineEditingEnded()
                            }
                                .id("editor-\(note.url.path)")
                                .frame(maxWidth: .infinity, minHeight: inlineEditorHeight, alignment: .topLeading)
                                .background(documentSurface)
                        } else if presentationMode == .markdown {
                            TextEditor(text: $text)
                                .id("editor-\(note.url.path)")
                                .font(.system(size: 17, weight: .regular, design: .default))
                                .frame(minHeight: 420)
                                .padding(18)
                                .background(documentSurface)
                        } else {
                            MarkdownDocumentView(
                                document: document,
                                noteURL: note.url,
                                vaultURL: vaultURL,
                                onTapDocument: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isInlineEditing = true
                                        isMarkdownEditorFocused = true
                                    }
                                }
                            )
                                .id("rendered-\(note.url.path)")
                                .padding(22)
                                .background(documentSurface)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: note.url) { _, _ in
                    didAppearForCurrentNote = false
                    inlineEditorHeight = 420
                    isMarkdownEditorFocused = false
                    proxy.scrollTo("note-top", anchor: .top)
                }
                .onChange(of: presentationMode) { _, newValue in
                    if newValue == .markdown, isInlineEditing {
                        handleInlineEditingEnded()
                    }
                }
                .onAppear {
                    didAppearForCurrentNote = true
                    proxy.scrollTo("note-top", anchor: .top)
                }
            }

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

    private func handleInlineEditingEnded() {
        guard didAppearForCurrentNote, presentationMode != .markdown, isInlineEditing else { return }

        isMarkdownEditorFocused = false
        withAnimation(.easeInOut(duration: 0.2)) {
            isInlineEditing = false
        }

        onSave()
    }
}

private struct DocumentModeMenu: View {
    @Binding var presentationMode: DocumentPresentationMode

    var body: some View {
        Menu {
            ForEach(DocumentPresentationMode.allCases) { mode in
                Button {
                    presentationMode = mode
                } label: {
                    Label(mode.title, systemImage: presentationMode == mode ? "checkmark" : mode.iconName)
                }
            }
        } label: {
            Label(presentationMode.title, systemImage: presentationMode.iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
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
    let noteURL: URL
    let vaultURL: URL?
    let onTapDocument: () -> Void
    @State private var contentHeight: CGFloat = 1

    var body: some View {
        MarkdownWebView(
            html: document.html,
            noteURL: noteURL,
            vaultURL: vaultURL,
            onTapDocument: onTapDocument,
            contentHeight: $contentHeight
        )
        .frame(height: max(contentHeight, 1))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InlineMarkdownEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool
    @Binding var measuredHeight: CGFloat
    @Binding var isFocused: Bool
    let onEndEditing: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isEditing: $isEditing,
            measuredHeight: $measuredHeight,
            isFocused: $isFocused,
            onEndEditing: onEndEditing
        )
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.adjustsFontForContentSizeCategory = true
        textView.alwaysBounceVertical = false
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .yes
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.isScrollEnabled = false
        textView.keyboardDismissMode = .interactive
        textView.textAlignment = .natural
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.showsHorizontalScrollIndicator = false
        textView.smartDashesType = .yes
        textView.smartQuotesType = .yes
        textView.smartInsertDeleteType = .yes
        textView.textContainerInset = UIEdgeInsets(top: 22, left: 22, bottom: 22, right: 22)
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onEndEditing = onEndEditing

        if textView.text != text {
            textView.text = text
        }

        if isEditing, isFocused, textView.window != nil, !textView.isFirstResponder {
            DispatchQueue.main.async {
                guard isEditing, isFocused, textView.window != nil, !textView.isFirstResponder else { return }
                textView.becomeFirstResponder()
            }
        } else if (!isEditing || !isFocused), textView.isFirstResponder {
            textView.resignFirstResponder()
        }

        context.coordinator.updateMeasuredHeight(for: textView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        return CGSize(width: width, height: max(measuredHeight, 420))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        @Binding var isEditing: Bool
        @Binding var measuredHeight: CGFloat
        @Binding var isFocused: Bool
        var onEndEditing: () -> Void
        weak var textView: UITextView?

        init(
            text: Binding<String>,
            isEditing: Binding<Bool>,
            measuredHeight: Binding<CGFloat>,
            isFocused: Binding<Bool>,
            onEndEditing: @escaping () -> Void
        ) {
            _text = text
            _isEditing = isEditing
            _measuredHeight = measuredHeight
            _isFocused = isFocused
            self.onEndEditing = onEndEditing
        }

        func textViewDidChange(_ textView: UITextView) {
            self.textView = textView
            text = textView.text
            updateMeasuredHeight(for: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            self.textView = textView
            if !isEditing {
                isEditing = true
            }
            if !isFocused {
                isFocused = true
            }
            updateMeasuredHeight(for: textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            self.textView = textView
            text = textView.text
            updateMeasuredHeight(for: textView)
            if isFocused {
                isFocused = false
            }
            if isEditing {
                isEditing = false
            }
            onEndEditing()
        }

        func updateMeasuredHeight(for textView: UITextView) {
            let targetWidth = textView.bounds.width > 0
                ? textView.bounds.width
                : UIScreen.main.bounds.width - 88
            guard targetWidth > 0 else { return }

            let fittingSize = textView.sizeThatFits(
                CGSize(width: targetWidth, height: .greatestFiniteMagnitude)
            )
            let nextHeight = max(fittingSize.height, 420)

            if abs(measuredHeight - nextHeight) > 0.5 {
                DispatchQueue.main.async {
                    self.measuredHeight = nextHeight
                }
            }
        }
    }
}

private struct MarkdownWebView: UIViewRepresentable {
    let html: String
    let noteURL: URL
    let vaultURL: URL?
    let onTapDocument: () -> Void
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight, onTapDocument: onTapDocument)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: Coordinator.documentTapHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onTapDocument = onTapDocument
        let contentKey = "\(noteURL.path)|\(html)"
        guard context.coordinator.lastContentKey != contentKey else { return }
        context.coordinator.lastContentKey = contentKey
        webView.loadHTMLString(html, baseURL: vaultURL ?? noteURL.deletingLastPathComponent())
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.documentTapHandlerName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let documentTapHandlerName = "documentTap"

        @Binding var contentHeight: CGFloat
        var lastContentKey: String?
        var onTapDocument: () -> Void

        init(contentHeight: Binding<CGFloat>, onTapDocument: @escaping () -> Void) {
            _contentHeight = contentHeight
            self.onTapDocument = onTapDocument
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let installTapHandler = """
            (() => {
              if (window.__flintDocumentTapInstalled) { return; }
              window.__flintDocumentTapInstalled = true;
              document.addEventListener('click', function(event) {
                const link = event.target.closest('a');
                if (link) { return; }
                window.webkit.messageHandlers.\(Self.documentTapHandlerName).postMessage('tap');
              });
            })();
            """
            webView.evaluateJavaScript(installTapHandler)
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { result, _ in
                guard let height = result as? CGFloat else { return }
                DispatchQueue.main.async {
                    self.contentHeight = height
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.documentTapHandlerName else { return }
            DispatchQueue.main.async {
                self.onTapDocument()
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}

extension DocumentPresentationMode {
    var iconName: String {
        switch self {
        case .rendered:
            return "doc.richtext"
        case .markdown:
            return "chevron.left.forwardslash.chevron.right"
        }
    }
}
