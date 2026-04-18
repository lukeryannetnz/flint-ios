import SwiftUI

struct VaultOnboardingView: View {
    @ObservedObject var model: AppModel

    @State private var isShowingOpenPicker = false
    @State private var isShowingCreateFlow = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 12) {
                    Text("flint")
                        .font(.system(size: 42, weight: .bold, design: .rounded))

                    Text("A markdown vault that lives in your folders.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 16) {
                    Button {
                        isShowingCreateFlow = true
                    } label: {
                        Label("Create Vault", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        isShowingOpenPicker = true
                    } label: {
                        Label("Open Vault", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .frame(maxWidth: 420)

                Text("Pick any folder from Files, including Dropbox. Flint stores notes directly as markdown files.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)

                Spacer()
            }
            .padding(24)
            .navigationTitle("Welcome")
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
        .sheet(isPresented: $isShowingCreateFlow) {
            CreateVaultSheet(model: model)
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

private struct CreateVaultSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var model: AppModel
    @State private var vaultName = ""
    @State private var isShowingParentPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Vault Details") {
                    TextField("Vault name", text: $vaultName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    Text("Flint will ask you to choose a parent folder, then create this vault inside it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Choose Parent Folder") {
                        isShowingParentPicker = true
                    }
                    .disabled(vaultName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Create Vault")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingParentPicker) {
            FolderPicker { parentURL in
                isShowingParentPicker = false
                Task {
                    await model.createVault(named: vaultName, in: parentURL)
                    dismiss()
                }
            } onCancel: {
                isShowingParentPicker = false
            }
        }
    }
}
