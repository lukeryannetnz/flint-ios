import SwiftUI

struct VaultOnboardingView: View {
    @ObservedObject var model: AppModel

    @State private var isShowingOpenPicker = false
    @State private var isShowingCreateFlow = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.04, green: 0.05, blue: 0.08),
                        Color(red: 0.09, green: 0.06, blue: 0.11),
                        Color(red: 0.03, green: 0.04, blue: 0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Circle()
                    .fill(Color(red: 1.0, green: 0.39, blue: 0.19).opacity(0.18))
                    .frame(width: 320, height: 320)
                    .blur(radius: 80)
                    .offset(x: 120, y: -260)

                Circle()
                    .fill(Color(red: 0.1, green: 0.78, blue: 0.95).opacity(0.12))
                    .frame(width: 280, height: 280)
                    .blur(radius: 90)
                    .offset(x: -140, y: 220)

                ScrollView {
                    VStack(spacing: 24) {
                        Spacer(minLength: 16)

                        Image("FlintBrandBoard")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 440)
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.35), radius: 30, y: 16)

                        VStack(spacing: 12) {
                            Text("flint")
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)

                            Text("Strike a spark. Keep every note in a markdown vault you own.")
                                .font(.headline)
                                .foregroundStyle(Color.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 460)
                        }

                        VStack(spacing: 16) {
                            Button {
                                isShowingCreateFlow = true
                            } label: {
                                Label("Create Vault", systemImage: "folder.badge.plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 1.0, green: 0.44, blue: 0.17))
                            .controlSize(.large)

                            Button {
                                isShowingOpenPicker = true
                            } label: {
                                Label("Open Vault", systemImage: "folder")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(Color.white.opacity(0.9))
                            .controlSize(.large)
                        }
                        .frame(maxWidth: 420)

                        Text("Choose a folder from Files, including Dropbox. Flint stores notes directly as markdown files you can keep, sync, and inspect outside the app.")
                            .font(.footnote)
                            .foregroundStyle(Color.white.opacity(0.68))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 460)

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
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
